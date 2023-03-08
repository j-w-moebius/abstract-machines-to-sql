DROP TABLE IF EXISTS terms, root_terms;

-- The self-referencing table terms holds all globally existing terms.
-- invariant: After filling it with load_term, it doesn't change.

-- Term = I Int           (De Bruijn Index)
--      | Lam Term        (Lambda with body)
--      | App Term Term   (Application with fun and arg)

CREATE TABLE terms (id integer PRIMARY KEY, i int, lam integer, app_fun integer, app_arg integer);

CREATE TABLE root_terms (id integer PRIMARY KEY, term integer REFERENCES terms);

--ALTER TABLE terms
--  ADD FOREIGN KEY (lam) REFERENCES terms,
--  ADD FOREIGN KEY (app_fun) REFERENCES terms,
--  ADD FOREIGN KEY (app_arg) REFERENCES terms;

COPY terms FROM 'terms.csv' CSV;
COPY root_terms FROM 'root_terms.csv' CSV;