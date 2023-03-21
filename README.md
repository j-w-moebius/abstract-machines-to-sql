# Implementing Abstract Machines in SQL

This repository contains some λ-calculus-interpreting abstract machines, implemented in `SQL` for my Bachelor's thesis.

The following DBMS were used:
- PostgreSQL:
  - Vanilla PostgreSQL implentations:
    - (1) SECD machine
    - (2) Krivine machine
  - Implentations relying on the `hashtables` extension:
    - (3) SECD machine
    - (4) Krivine machine
- DuckDB:
  - (5) SECD machine
- Umbra:
  - (6) Krivine machine

## Term sets

`term-sets` contains four generated test sets of λ-terms in `JSON` notation:

| #        | Term depth | Evaluation steps| Number of terms |
|----------|------------|-----------------|-----------------|
| 1        | 100-1000   | 1-25            | 100             |
| 2        | 100-1000   | 25-200          | 100             |
| 3        | 100-1000   | 200-1000        | 100             |
| 4        | 100-1000   | 1000-2000       | 100             |


## Requirements & Setup

Requirements:
  - `PostgreSQL >= 14.6`
  - `Umbra` installed in `~`

Setup:
  - run `$ export PSQL_PORT=p` , where `p` is the port on which Postgres is running on your machine (`5432` is default)
  - follow the instructions in `hashtable-extension/README.md` to install the hash table extension
  - run `$ psql -p $PSQL_PORT -c "\i import_terms.sql"`

## Running tests

To test machine implementation `m` (e.g., `2` for the Vanilla PostgreSQL Krivine machine) on term set `s`, simply run 
`./run_tests m s`

The evaluation result will be piped to `out.txt`.