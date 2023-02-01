DROP TYPE IF EXISTS term,env,closure,stack,lam,app CASCADE;
DROP TABLE IF EXISTS terms, root_terms;

CREATE DOMAIN term AS integer;
CREATE DOMAIN env AS integer;
CREATE TYPE closure AS (t term, e env);    -- Closure = (Term, Env)
CREATE DOMAIN stack AS closure[];

CREATE TYPE app AS (fun term, arg term);

-- The self-referencing table terms holds all globally existing terms.
-- invariant: After filling it with load_term, it doesn't change.

-- Term = I Int           (De Bruijn Index)
--      | Lam Term        (Lambda with body)
--      | App Term Term   (Application with fun and arg)

CREATE TABLE terms (id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY, i int, lam term, app app);

CREATE TABLE root_terms(id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY, term integer REFERENCES terms);

ALTER TABLE terms
  ADD FOREIGN KEY (lam) REFERENCES terms;
  -- FOREIGN KEY for app.fun and app.arg?

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

-- convert tabular representation of a term into JSON
CREATE FUNCTION term_to_json(t term) RETURNS jsonb AS
$$
  SELECT r
  FROM (SELECT terms.i, terms.lam, terms.app
        FROM terms AS terms
        WHERE terms.id = t) AS t(i,lam,app),
  LATERAL (
    
    SELECT jsonb_build_object('i', i)
    WHERE t.i IS NOT NULL

      UNION ALL

    SELECT jsonb_build_object('lam', term_to_json(t.lam))
    WHERE t.lam IS NOT NULL
    
      UNION ALL

    SELECT jsonb_build_object('app', jsonb_build_object('fun', term_to_json(fun), 'arg', term_to_json(arg)))
    FROM (SELECT (t.app).*) AS _(fun, arg)
    WHERE t.app IS NOT NULL
  ) AS _(r)
$$
LANGUAGE SQL VOLATILE;

DROP SEQUENCE IF EXISTS env_keys;
CREATE SEQUENCE env_keys START 1;

-- we use the PG Hashtable extension to model environments
-- It has a key columns (id) and two value columns
-- holding the variable's associated closure and a pointer to the next closure 
-- A table row corresponds to a closure. An environment can be seen as a stack of closures.
-- Hence, linking multiple closures to environments is done via the self-reference in column 'next'.

SELECT prepareHT(1, 1, null::env, null :: closure, null :: env);

-- pop n closures from environmet e and return the remaining environment
CREATE FUNCTION pop(e env, n int) RETURNS env AS
$$
  WITH RECURSIVE r(e, n) AS (
    SELECT e, n

      UNION ALL
    
    SELECT next_env, r.n - 1
    FROM r,
    LATERAL lookupHT(1, false, r.e) AS _(_ env, __ closure, next_env env)
    WHERE r.n > 0
  )
  SELECT r.e
  FROM r
  WHERE r.n = 0
$$
LANGUAGE SQL VOLATILE;

-- return new empty environment
CREATE FUNCTION empty_env() RETURNS env AS 
$$
  SELECT nextval('env_keys')
$$
LANGUAGE SQL VOLATILE;

-- push a closure c onto an environment e
CREATE FUNCTION push(e env, c closure) RETURNS env AS
$$
  SELECT new_env
  FROM empty_env() AS new_env, 
  LATERAL insertToHT(1, true, new_env, c, e);
$$
LANGUAGE SQL VOLATILE;

/*
SELECT empty_env();
SELECT empty_env();
SELECT load_term('{"i": 8}');
SELECT push(1,row(1,2));
SELECT push(3,row(1,2));
DELETE FROM environments AS e WHERE e.id = 1;
SELECT 1;
*/