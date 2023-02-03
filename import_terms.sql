-- import terms from JSON files into tables input_terms_secd and input_terms_krivine

DROP TABLE IF EXISTS input_terms_secd, input_terms_krivine,raw;

CREATE TABLE raw(t jsonb);
CREATE TABLE input_terms_secd (set_id integer, t jsonb);
CREATE TABLE input_terms_krivine (set_id integer, t jsonb);

\copy raw FROM 'term-sets/1/secd.json';

INSERT INTO input_terms_secd(set_id, t) (
    SELECT 1, t
    FROM raw AS _(t)
);

DELETE FROM raw;

\copy raw FROM 'term-sets/1/krivine.json';

INSERT INTO input_terms_krivine(set_id, t) (
    SELECT 1, t
    FROM raw AS _(t)
);

DELETE FROM raw;

\copy raw FROM 'term-sets/2/secd.json';

INSERT INTO input_terms_secd(set_id, t) (
    SELECT 2, t
    FROM raw AS _(t)
);

DELETE FROM raw;

\copy raw FROM 'term-sets/2/krivine.json';

INSERT INTO input_terms_krivine(set_id, t) (
    SELECT 2, t
    FROM raw AS _(t)
);

DELETE FROM raw;