-- add terms from temporary JSON file and delete those who evaluate too quickly or take too long

\copy raw(t) FROM 'Generation/krivine_terms.json';

INSERT INTO input_terms_krivine(set_id, term_id, t) (
    SELECT :i, id, t
    FROM raw AS _(id, t)
    LIMIT :n
);

DELETE FROM raw;
ALTER TABLE raw ALTER term_id RESTART;

\i Generation/krivine_interrupt.sql

INSERT INTO root_terms (
  SELECT term_id, term
  FROM input_terms_krivine AS _(set_id, term_id, t), load_term(t) AS __(term)
  WHERE set_id = :i
);

DELETE FROM input_terms_krivine AS t
WHERE t.set_id = :i
  AND t.term_id IN (
    SELECT id
    FROM root_terms AS __(id,t), LATERAL evaluate_interrupt(t, :max) AS r(v, n)
    WHERE r IS NULL
       OR r.n < :min
  );

SELECT COUNT(*)
FROM input_terms_krivine;