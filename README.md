# Implementing Abstract Machines in SQL

Work in progress for my Bachelor's thesis.

So far, includes:
- PostgreSQL:
  - Vanilla PostgreSQL implentations:
    - SECD machine     (1)
    - Krivine machine  (2)
  - Implentations relying on the `hashtables` extension:
    - SECD machine     (3)
    - Krivine machine  (4)
- DuckDB:
  - SECD machine       (5)

## Term sets

| #        | Term depth | Evaluation steps| Number of terms |
|----------|------------|-----------------|-----------------|
| 1        | 100-1000   | 1-25            | 100             |
| 2        | 100-1000   | 25-200          | 100             |
| 3        | 100-1000   | 200-1000        | 100             |