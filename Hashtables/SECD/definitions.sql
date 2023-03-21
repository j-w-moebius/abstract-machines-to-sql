DROP TYPE IF EXISTS term,var,primitive,env,closure,val,stack,directive,control,frame,dump,lam,app CASCADE;
DROP TABLE IF EXISTS terms, root_terms;

CREATE DOMAIN term AS integer;
CREATE DOMAIN var  AS text;
CREATE TYPE lam AS (ide var, body term);
CREATE TYPE app AS (fun term, arg term);

-- The self-referencing table terms holds all globally existing terms and subterms.
-- invariant: After filling it with load_term, it doesn't change.
CREATE TABLE terms (id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY, lit int, var var, lam lam, app app);

-- holds references all terms in table terms that are root_terms
CREATE TABLE root_terms(id integer PRIMARY KEY, term integer REFERENCES terms);

CREATE TYPE primitive AS ENUM('apply');
CREATE DOMAIN env AS bigint;
CREATE TYPE closure AS (v var, t term, e env);    -- Closure = (Var, Term, Env)
CREATE TYPE val AS (c closure, n int);            -- Val = Closure | Int
CREATE DOMAIN stack AS val[];
CREATE TYPE directive AS (t term, p primitive);   -- Directive = Term | Primitive
CREATE DOMAIN control AS directive[];
CREATE TYPE frame AS (s stack, e env, c control); -- Frame = (Stack, Env, Control)
CREATE DOMAIN dump AS frame[]; 

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

-- we use the PG Hashtable extension to model environments
-- The environment HT has one key columns (environment_id) and three value columns
-- holding the variable's name, its value and a pointer to the parent environment
SELECT prepareHT(1, 1, null::env, null :: var, null :: val, null :: env);

-- only for debugging
CREATE FUNCTION display_envs() RETURNS TABLE (env env, ide var, val val, parent env) AS 
$$
  SELECT * 
  FROM scanHT(1) AS _(env env, ide var, val val, parent env)
  ORDER BY env, ide
$$
LANGUAGE SQL VOLATILE;


-- import terms from JSON representatin in to table 'terms'
INSERT INTO root_terms (
  SELECT term_id, term
  FROM input_terms_secd AS _(set_id, term_id, t), load_term(t) AS __(term)
  WHERE set_id = :term_set
);