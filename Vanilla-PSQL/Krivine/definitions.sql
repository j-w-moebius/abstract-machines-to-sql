DROP TYPE IF EXISTS term,env,closure,stack,lam,app,machine_state,env_entry CASCADE;
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

CREATE TYPE machine_state AS (t term, s stack, e env);
CREATE TYPE env_entry AS (id env, c closure, parent env);

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


-- import terms from JSON representatin in to table 'terms'
INSERT INTO root_terms (
  SELECT term_id, term
  FROM input_terms_krivine AS _(set_id, term_id, t), load_term(t) AS __(term)
  WHERE set_id = :term_set
);