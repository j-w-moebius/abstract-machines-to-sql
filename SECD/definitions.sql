DROP TYPE IF EXISTS term,var,primitive,env,closure,val,stack,directive,control,frame,dump,lam,app,rule,machine_state,env_entry CASCADE;
DROP TABLE IF EXISTS terms;

--CREATE DOMAIN term AS jsonb;
CREATE DOMAIN term AS integer;
CREATE DOMAIN var  AS text;
CREATE TYPE primitive AS ENUM('apply');
CREATE DOMAIN env AS int;
CREATE TYPE closure AS (v var, t term, e env);    -- Closure = (Var, Term, Env)
CREATE TYPE val AS (c closure, n int);            -- Val = Closure | Int
CREATE DOMAIN stack AS val[];
CREATE TYPE directive AS (t term, p primitive);   -- Directive = Term | Primitive
CREATE DOMAIN control AS directive[];
CREATE TYPE frame AS (s stack, e env, c control); -- Frame = (Stack, Env, Control)
CREATE DOMAIN dump AS frame[]; 

CREATE TYPE lam AS (ide var, body term);
CREATE TYPE app AS (fun term, arg term);

CREATE TYPE rule AS ENUM('1', '2', '3', '4', '5', '6', '7');

CREATE TYPE machine_state AS (s stack, e env, c control, d dump);
CREATE TYPE env_entry AS (id env, name var, val val);

CREATE TABLE terms (id integer GENERATED ALWAYS AS IDENTITY, lit int, var var, lam lam, app app);

ALTER TABLE terms
  ADD PRIMARY KEY (id);

DROP SEQUENCE IF EXISTS env_keys;
CREATE SEQUENCE env_keys START 1;

CREATE FUNCTION load_term(t jsonb) RETURNS term AS
$$
  INSERT INTO terms(lit, var, lam, app) (
    SELECT new.*
      FROM jsonb_each(t) AS _(type, content),
          LATERAL (

            SELECT lit, null, null::lam, null::app
            FROM jsonb_to_record(t) AS _(lit int)
            WHERE type = 'lit'
              
              UNION ALL

            SELECT null::int, var, null::lam, null::app
            FROM jsonb_to_record(t) AS _(var var)
            WHERE type = 'var'

              UNION ALL

            SELECT null::int, null, row(var, load_term(body))::lam, null::app
            FROM jsonb_to_record(content) AS _(var var, body jsonb)
            WHERE type = 'lam'

              UNION ALL

            SELECT null::int, null, null::lam, row(load_term(fun),load_term(arg))::app
            FROM jsonb_to_record(content) AS _(fun jsonb, arg jsonb)
            WHERE type = 'app'

          ) AS new(lit, var, lam, app)
  )
  RETURNING id
$$
LANGUAGE SQL VOLATILE;

DROP TYPE IF EXISTS rec_type;
CREATE TYPE rec_type AS (finished boolean, ms machine_state, e env_entry);