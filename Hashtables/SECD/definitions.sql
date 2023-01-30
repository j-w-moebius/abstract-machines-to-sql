DROP TYPE IF EXISTS term,var,primitive,env,closure,val,stack,directive,control,frame,dump,term_type,lam,app CASCADE;
DROP TABLE IF EXISTS terms, root_terms;

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

CREATE TABLE terms (id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY, lit int, var var, lam lam, app app);

CREATE TABLE root_terms (id integer REFERENCES terms);

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
-- It has two key columns (environment_id, identifier) and one value column
-- holding the variable's value
SELECT prepareHT(1, 2, null::env, null :: var, null :: val);

-- look up identifier ide in environment env
-- return corresponding value or null if ide not defined in env
CREATE FUNCTION lookup(e env, ide var) RETURNS val AS
$$
  SELECT v FROM lookupHT(1, false, e, ide) AS _(_ env, __ var, v val);
$$
LANGUAGE SQL VOLATILE;

-- extend an environment env's bindings by (ide -> v)
-- overwrite if variable is already bound
CREATE FUNCTION extend(e env, ide var, v val) RETURNS env AS
$$
  SELECT e FROM insertToHT(1, true, e, ide, v);
$$
LANGUAGE SQL VOLATILE;

-- return new empty env
CREATE FUNCTION empty_env() RETURNS env AS 
$$
  SELECT nextval('env_keys')
$$
LANGUAGE SQL VOLATILE;

-- create copy of env e
CREATE FUNCTION copy_env(e env) RETURNS env AS
$$
  SELECT DISTINCT new_env
  FROM scanHT(1) AS _(env env, ide var, val val), 
       empty_env() AS new_env,
  LATERAL insertToHT(1, false, new_env, ide, val)
  WHERE env = e
$$
LANGUAGE SQL VOLATILE;


-- only for debugging
CREATE FUNCTION display_envs() RETURNS TABLE (env env, ide var, val val) AS 
$$
  SELECT * 
  FROM scanHT(1) AS _(env env, ide var, val val)
  ORDER BY env, ide
$$
LANGUAGE SQL VOLATILE;