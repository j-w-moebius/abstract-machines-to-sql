DROP TYPE IF EXISTS term,env,closure,stack,lam,app CASCADE;
DROP TABLE IF EXISTS terms, root_terms;

CREATE DOMAIN term AS integer;
CREATE DOMAIN env AS integer;
CREATE TYPE app AS (fun term, arg term);

-- The self-referencing table terms holds all globally existing terms.
-- invariant: After filling it with load_term, it doesn't change.
CREATE TABLE terms (id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY, i int, lam term, app app);

-- holds references all terms in table terms that are root_terms
CREATE TABLE root_terms(id integer PRIMARY KEY, term integer REFERENCES terms);

CREATE TYPE closure AS (t term, e env);    -- Closure = (Term, Env)
CREATE DOMAIN stack AS closure[];

DROP SEQUENCE IF EXISTS env_keys;
CREATE SEQUENCE env_keys START 1;

-- load a term from JSON into tabular representation in table terms
CREATE FUNCTION load_term(t jsonb) RETURNS term AS
$$
  INSERT INTO terms(i, lam, app) (
    SELECT new.*
      FROM jsonb_each(t) AS _(type, content),
          LATERAL (

            SELECT i, null::term, null::app
            FROM jsonb_to_record(t) AS _(i int)
            WHERE type = 'i'
              
              UNION ALL

            SELECT null::int, load_term(lam), null::app
            FROM jsonb_to_record(t) AS _(lam jsonb)
            WHERE type = 'lam'

              UNION ALL

            SELECT null::int, null::term, row(load_term(fun),load_term(arg))::app
            FROM jsonb_to_record(content) AS _(fun jsonb, arg jsonb)
            WHERE type = 'app'

          ) AS new(lit, lam, app)
  )
  RETURNING id
$$
LANGUAGE SQL VOLATILE;

-- we use the PG Hashtable extension to model environments
-- It has a key column (id) and two value columns
-- holding the variable's associated closure and a pointer to the next closure 
-- A table row corresponds to a closure. An environment can be seen as a stack of closures.
-- Hence, linking multiple closures to environments is done via the self-reference in column 'next'.

SELECT prepareHT(1, 1, null::env, null :: closure, null :: env);

-- only for debugging
CREATE FUNCTION display_envs() RETURNS TABLE (env env, c closure, next env) AS 
$$
  SELECT * 
  FROM scanHT(1) AS _(env env, c closure, next env)
  ORDER BY env
$$
LANGUAGE SQL VOLATILE;