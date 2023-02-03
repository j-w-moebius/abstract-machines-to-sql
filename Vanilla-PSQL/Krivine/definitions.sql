DROP TYPE IF EXISTS term,env,closure,stack,lam,app,machine_state,env_entry,rule CASCADE;
DROP TABLE IF EXISTS terms, root_terms;

CREATE DOMAIN term AS integer;
CREATE DOMAIN env AS integer;
CREATE TYPE closure AS (t term, e env);    -- Closure = (Term, Env)
CREATE DOMAIN stack AS closure[];

CREATE TYPE machine_state AS (t term, s stack, e env);
CREATE TYPE env_entry AS (id env, c closure, next env);

-- An enum type for the rules which can be applied by the Krivine machine.
-- Roughly corresponding to those presented on the Wikipedia page.
CREATE TYPE rule AS ENUM('1', '2', '3', '4');

DROP SEQUENCE IF EXISTS env_keys;
CREATE SEQUENCE env_keys START 1;

CREATE TYPE app AS (fun term, arg term);

-- The self-referencing table terms holds all globally existing terms.
-- invariant: After filling it with load_term, it doesn't change.

-- Term = I Int           (De Bruijn Index)
--      | Lam Term        (Lambda with body)
--      | App Term Term   (Application with fun and arg)

CREATE TABLE terms (id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY, i int, lam term, app app);

CREATE TABLE root_terms(id integer PRIMARY KEY, term integer REFERENCES terms);

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