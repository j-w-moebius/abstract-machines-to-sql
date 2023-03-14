DROP TABLE IF EXISTS root_terms;
DROP TABLE IF EXISTS terms;
DROP TABLE IF EXISTS raw;

DROP TYPE IF EXISTS primitive;

CREATE TYPE primitive AS ENUM('apply');

-- The self-referencing table terms holds all globally existing terms.
-- invariant: After filling it with load_term, it doesn't change.
CREATE TABLE terms (id integer PRIMARY KEY, t UNION(lit int, var text, lam STRUCT(ide text, body integer), app STRUCT(fun integer, arg integer)));

-- holds references all terms in table terms that are root_terms
CREATE TABLE root_terms(id integer PRIMARY KEY, term integer REFERENCES terms(id));

DROP SEQUENCE IF EXISTS env_keys;
CREATE SEQUENCE env_keys START 1;

CREATE TABLE raw (id integer PRIMARY KEY, lit integer, var text, lam_ide text, lam_body integer, app_fun integer, app_arg integer);