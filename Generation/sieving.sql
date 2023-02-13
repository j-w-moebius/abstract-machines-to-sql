-- add terms from temporary JSON file and delete those who evaluate too quickly or take too long

\copy raw(t) FROM 'Generation/secd_terms.json';

INSERT INTO input_terms_secd(set_id, term_id, t) (
    SELECT :i, id, t
    FROM raw AS _(id, t)
    LIMIT :n
);

DELETE FROM raw;
ALTER TABLE raw ALTER term_id RESTART;

\i Generation/secd_interrupt.sql

INSERT INTO root_terms (
  SELECT term_id, term
  FROM input_terms_secd AS _(set_id, term_id, t), load_term(t) AS __(term)
  WHERE set_id = :i
);

WITH deleted(id) AS (

DELETE FROM input_terms_secd AS t
WHERE t.set_id = :i
  AND t.term_id IN (
  SELECT id
  FROM root_terms AS __(id,t), LATERAL evaluate_interrupt(t, :max) AS r(v, n)
  WHERE r IS NULL
     OR r.n < :min
)
RETURNING t.term_id
)

SELECT COUNT(*)
FROM deleted;