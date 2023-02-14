#!/bin/bash

# call with set_generation N MIN MAX
# generate N terms in 'krivine.json' (N <= 100)
# the generated terms all take a number of steps to be evaluated that lies between MIN and MAX

N=$1
MIN=$2
MAX=$3

psql -p $PSQL_PORT -c "DROP TABLE IF EXISTS input_terms_krivine,raw;"
psql -p $PSQL_PORT -c "CREATE TABLE raw(term_id integer GENERATED ALWAYS AS IDENTITY, t jsonb);"
psql -p $PSQL_PORT -c "CREATE TABLE input_terms_krivine (set_id integer, term_id integer, t jsonb);"

Generation/generator

I=1
C=0
while [ $C -lt $N ]
do
  let C=$(psql -qtA -p $PSQL_PORT -v i=$I -v n=$N -v min=$MIN -v max=$MAX -f Generation/krivine_sieving.sql | tail -1)
  let I=$I+1
done

psql -p $PSQL_PORT -c "\copy (SELECT t FROM input_terms_krivine AS _(set_id, term_id, t) ORDER BY set_id, term_id LIMIT $N) TO 'krivine.json';"
truncate -s -1 krivine.json # remove last newline