DROP TABLE IF EXISTS terms;
DROP TABLE IF EXISTS raw;
DROP TABLE IF EXISTS root_terms;

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

CREATE TABLE raw (id integer PRIMARY KEY, lit integer, var text, lam_ide text, lam_body integer, app_fun integer, app_arg integer);

CREATE TABLE root_terms(id integer REFERENCES terms(id));