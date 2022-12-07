DROP TYPE IF EXISTS term,var,primitive,env,closure,val,stack,directive,control,frame,dump,term_type,lam,app CASCADE;
DROP TABLE IF EXISTS environments, terms;

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

CREATE TABLE environments(id env, name var, def val);
ALTER TABLE environments
  ADD PRIMARY KEY (id, name);

-- look up identifier ide in environment env
-- return corresponding value or null if ide not defined in env
CREATE FUNCTION lookup(e env, ide var) RETURNS val AS
$$
  SELECT t.def
  FROM environments AS t
  WHERE t.id = e
    AND t.name = ide
$$
LANGUAGE SQL VOLATILE;

-- extend an environment env's bindings by (ide -> v)
CREATE FUNCTION extend(e env, ide var, v val) RETURNS env AS
$$
  INSERT INTO environments VALUES (e, ide, v)
    ON CONFLICT (id, name) DO UPDATE
      SET def = v
  RETURNING e
$$
LANGUAGE SQL VOLATILE;

-- return new empty env
CREATE FUNCTION empty_env() RETURNS env AS 
$$
  SELECT nextval('env_keys')
$$
LANGUAGE SQL VOLATILE;

-- delete env old and return new
CREATE FUNCTION replace_env(old env, new env) RETURNS env AS 
$$
  DELETE FROM environments AS t
    WHERE t.id = old;
  SELECT new
$$
LANGUAGE SQL VOLATILE;

-- create copy of env e
CREATE FUNCTION copy_env(e env) RETURNS env AS
$$
  WITH fresh_env AS 
    (SELECT empty_env()),
  _ AS                   -- RETURNING doesn't work with empty environments
    (INSERT INTO environments
      (SELECT f.id, t.name, t.def
       FROM environments AS t, fresh_env AS f(id)
       WHERE t.id = e))
  SELECT f.id
  FROM fresh_env AS f(id)
$$
LANGUAGE SQL VOLATILE;