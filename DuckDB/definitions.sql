DROP TABLE IF EXISTS terms;

DROP TYPE IF EXISTS primitive;
DROP TYPE IF EXISTS machine_state;
DROP TYPE IF EXISTS rule;

CREATE TYPE primitive AS ENUM('apply');

-- An enum type for the rules which can be applied by the SECD machine.
-- Roughly corresponding to those presented by Danvy.
CREATE TYPE rule AS ENUM('1', '2', '3', '4', '5', '6', '7');

-- A single environment entry consists of:
-- id: The environment's identifier
-- name: The name of a variable
-- val: The value to which this variable is bound in environment id

-- The self-referencing table terms holds all globally existing terms.
-- invariant: After filling it with load_term, it doesn't change.

-- The object language consits of terms, which are defined in the following way
-- (corresponding to lambda calculus extended with integer literals):
-- Term = Lit Int         (Integer literal)
--      | Var Text        (Variable)
--      | Lam Text Term   (Lambda abstraction with variable and body)
--      | App Term Term   (Application with fun and arg)
CREATE TABLE terms (id integer PRIMARY KEY, t UNION(lit int, var text, lam STRUCT(ide text, body integer), app STRUCT(fun integer, arg integer)));

DROP SEQUENCE IF EXISTS env_keys;
CREATE SEQUENCE env_keys START 1;

DROP SEQUENCE IF EXISTS term_keys;
CREATE SEQUENCE term_keys START 1;

-- (lambda x.x) 42
/*
INSERT INTO terms VALUES
  (nextval('term_keys'), UNION_VALUE(var := 'x')),
  (nextval('term_keys'), UNION_VALUE(lam := row('x',1))),
  (nextval('term_keys'), UNION_VALUE(lit := 42)),
  (nextval('term_keys'), UNION_VALUE(app := row(2,3)));
/*
-- lambda 42
INSERT INTO terms VALUES
  (nextval('term_keys'), UNION_VALUE(lit := 42)),
  (nextval('term_keys'), UNION_VALUE(lam := row('x',1)));
/*
-- lit
INSERT INTO terms VALUES
  (nextval('term_keys'), UNION_VALUE(lit := 1));
*/
-- ((λx.(λy.(x y))) (λx.x)) 1 --> 1
INSERT INTO terms VALUES
  (nextval('term_keys'), UNION_VALUE(var := 'x')),
  (nextval('term_keys'), UNION_VALUE(var := 'y')),
  (nextval('term_keys'), UNION_VALUE(app := row(1,2))),
  (nextval('term_keys'), UNION_VALUE(lam := row('y',3))),
  (nextval('term_keys'), UNION_VALUE(lam := row('x',4))),
  (nextval('term_keys'), UNION_VALUE(var := 'x')),
  (nextval('term_keys'), UNION_VALUE(lam := row('x',6))),
  (nextval('term_keys'), UNION_VALUE(app := row(5,7))),
  (nextval('term_keys'), UNION_VALUE(lit := 1)),
  (nextval('term_keys'), UNION_VALUE(app := row(8,9)))
/*
-- load a term from JSON into tabular representation in table terms
CREATE OR REPLACE FUNCTION load_term(t) AS
  INSERT INTO terms(id, lit, var, lam, app) (
    SELECT nextval('term_keys'), new.*
      FROM jsonb_each(t) AS _(type, content),
          LATERAL (

            SELECT UNION_VALUE(lit := lit)
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
  RETURNING id;
*/