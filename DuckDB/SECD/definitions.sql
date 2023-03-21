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


-- import raw terms from CSV file
COPY raw FROM 'terms.csv';

-- copy data from table 'raw' into table 'terms', converting it to correct types
-- separate INSERT statements avoid cumbersome casts

INSERT INTO terms (
  SELECT id, r.lit
  FROM raw AS r
  WHERE r.lit IS NOT NULL
);

INSERT INTO terms (
  SELECT id, r.var
  FROM raw AS r
  WHERE r.var IS NOT NULL
);

INSERT INTO terms (
  SELECT id, union_value(lam := {'ide': r.lam_ide, 'body': r.lam_body})
  FROM raw AS r
  WHERE r.lam_ide IS NOT NULL
);

INSERT INTO terms (
  SELECT id, union_value(app := {'fun': r.app_fun, 'arg': r.app_arg})
  FROM raw AS r
  WHERE r.app_fun IS NOT NULL
);

COPY root_terms FROM 'root_terms.csv';