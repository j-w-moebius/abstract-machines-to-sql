-- import terms from JSON files into tables input_terms_secd and input_terms_krivine

DROP TABLE IF EXISTS input_terms_secd, input_terms_krivine,raw;

CREATE TABLE raw(term_id integer GENERATED ALWAYS AS IDENTITY, t jsonb);
CREATE TABLE input_terms_secd (set_id integer, term_id integer, t jsonb);
CREATE TABLE input_terms_krivine (set_id integer, term_id integer, t jsonb);

\copy raw(t) FROM 'term-sets/1/secd.json';

INSERT INTO input_terms_secd(set_id, term_id, t) (
    SELECT 1, id, t
    FROM raw AS _(id, t)
);

DELETE FROM raw;
ALTER TABLE raw ALTER term_id RESTART;

\copy raw(t) FROM 'term-sets/1/krivine.json';

INSERT INTO input_terms_krivine(set_id, term_id, t) (
    SELECT 1, id, t
    FROM raw AS _(id, t)
);

DELETE FROM raw;
ALTER TABLE raw ALTER term_id RESTART;

\copy raw(t) FROM 'term-sets/2/secd.json';

INSERT INTO input_terms_secd(set_id, term_id, t) (
    SELECT 2, id, t
    FROM raw AS _(id, t)
);

DELETE FROM raw;
ALTER TABLE raw ALTER term_id RESTART;

\copy raw(t) FROM 'term-sets/2/krivine.json';

INSERT INTO input_terms_krivine(set_id, term_id, t) (
    SELECT 2, id, t
    FROM raw AS _(id, t)
);

DELETE FROM raw;
ALTER TABLE raw ALTER term_id RESTART;

\copy raw(t) FROM 'term-sets/3/secd.json';

INSERT INTO input_terms_secd(set_id, term_id, t) (
    SELECT 3, id, t
    FROM raw AS _(id, t)
);

DELETE FROM raw;
ALTER TABLE raw ALTER term_id RESTART;

\copy raw(t) FROM 'term-sets/3/krivine.json';

INSERT INTO input_terms_krivine(set_id, term_id, t) (
    SELECT 3, id, t
    FROM raw AS _(id, t)
);

DELETE FROM raw;
ALTER TABLE raw ALTER term_id RESTART;