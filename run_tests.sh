#!/bin/bash

# requires variable PSQL_PORT to be set to the port on which postgres is running
test=$1
case $test in 
   1) #Vanilla Postgres SECD
      psql -p $PSQL_PORT -q -f Vanilla-PSQL/SECD/secd.sql
      psql -p $PSQL_PORT -o out.txt -c "SELECT id,n FROM root_terms AS _(id,t), LATERAL evaluate(t) AS r(_,n);"
      ;;
   2) # Vanilla Postgres Krivine
      psql -p $PSQL_PORT -q -f Vanilla-PSQL/Krivine/krivine.sql
      psql -p $PSQL_PORT -o out.txt -c "SELECT id,n FROM root_terms AS _(id,t), LATERAL evaluate(t) AS r(_,n);"
      ;;
   3) #Hashtable Postgres SECD
      psql -p $PSQL_PORT -o out.txt -q -c "\i Hashtables/SECD/secd.sql" -c "SELECT id,n FROM root_terms AS _(id,t), LATERAL evaluate(t) AS r(_,n);"
      ;;
   4) #Hashtable Postgres Krivine
      psql -p $PSQL_PORT -o out.txt -q -c "\i Hashtables/Krivine/krivine.sql" -c "SELECT id,n FROM root_terms AS _(id,t), LATERAL evaluate(t) AS r(_,n);"
      ;;
#   5) # DuckDB SECD (not working yet due to missing DuckDB features)
#     psql -p $PSQL_PORT -q -f Vanilla-PSQL/SECD/secd.sql
#     psql -p $PSQL_PORT -q -c "\copy (SELECT id, lit, var, (lam).ide, (lam).body, (app).fun, (app).arg FROM terms) TO 'terms.csv' CSV;"
#    psql -p $PSQL_PORT -q -c "\copy (TABLE root_terms) TO 'root_terms.csv' CSV;"
#     ./duckdb_cli -c ".output out.txt" -c ".read DuckDB/SECD/secd.sql" -c "SELECT id,evaluate(t) FROM root_terms AS _(id,t);"
#     ;;
esac
