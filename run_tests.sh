#!/bin/bash

# before testing, run `\i import_terms.sql` in `psql` once

# requires variable PSQL_PORT to be set to the port on which postgres is running
testMachine=$1
testSet=$2
case $testMachine in 
   1) # Vanilla Postgres SECD
      psql -p $PSQL_PORT --variable=term_set=$testSet -q -f Vanilla-PSQL/SECD/secd.sql
      psql -p $PSQL_PORT -o out.txt -q -c "\timing on" -c "SELECT id,val,steps,env_size FROM root_terms AS _(id,t), LATERAL evaluate(t) AS r(val,steps,env_size);"
      ;;
   2) # Vanilla Postgres Krivine
      psql -p $PSQL_PORT --variable=term_set=$testSet -q -f Vanilla-PSQL/Krivine/krivine.sql
      psql -p $PSQL_PORT -o out.txt -q -c "\timing on" -c "SELECT id,val,steps,env_size FROM root_terms AS _(id,t), LATERAL evaluate(t) AS r(val,steps,env_size);"
      ;;
   3) # Hashtable Postgres SECD 
      #(hashtable is lost if set up in separate command)
      psql -p $PSQL_PORT --variable=term_set=$testSet -o out.txt -q -c "\i Hashtables/SECD/secd.sql" -c "\timing on" -c "SELECT id,val,steps FROM root_terms AS _(id,t), LATERAL evaluate(t) AS r(val,steps);"
      ;;
   4) # Hashtable Postgres Krivine
      psql -p $PSQL_PORT --variable=term_set=$testSet -o out.txt -q -c "\i Hashtables/Krivine/krivine.sql" -c "\timing on" -c "SELECT id,val,steps FROM root_terms AS _(id,t), LATERAL evaluate(t) AS r(val,steps);"
      ;;
   5) # DuckDB SECD 
      #(sed hack due to DuckDB forbidding the use of recursive CTEs in correlated subqueries)
     psql -p $PSQL_PORT --variable=term_set=$testSet -q -f Vanilla-PSQL/SECD/secd.sql
     psql -p $PSQL_PORT -q -c "\copy (SELECT id, lit, var, (lam).ide, (lam).body, (app).fun, (app).arg FROM terms ORDER BY id) TO 'terms.csv' CSV;"
     psql -p $PSQL_PORT -q -c "\copy (TABLE root_terms) TO 'root_terms.csv' CSV;"
     cat root_terms.csv | sed -e 's/\(.*\),\(.*\)/SELECT \1 AS id,val,n FROM evaluate(\2) AS _(val,n);/g' > duckdb_commands.sql
     ./duckdb_cli -c ".output out.txt" -c ".read DuckDB/SECD/secd.sql" -c ".timer on" -c ".read duckdb_commands.sql"
     ;;
   6) # Umbra Krivine
     psql -p $PSQL_PORT --variable=term_set=$testSet -q -f Vanilla-PSQL/Krivine/krivine.sql
     psql -p $PSQL_PORT -q -c "\copy (SELECT id, i, lam, (app).fun, (app).arg FROM terms ORDER BY id) TO 'terms.csv' CSV;"
     psql -p $PSQL_PORT -q -c "\copy (TABLE root_terms) TO 'root_terms.csv' CSV;"
     ~/umbra/bin/sql "" Umbra/Krivine/krivine.sql 

esac
