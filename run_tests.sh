testID=$1
case $testID in 
   1) #Vanilla Postgres SECD
      psql -p $PSQL_PORT -q -f SECD/secd.sql
      psql -p $PSQL_PORT -c "SELECT r.* FROM root_terms AS _(t), LATERAL evaluate(t) AS r;"
      ;;
   2) # Vanilla Postgres Krivine
      psql -p $PSQL_PORT -q -f Krivine/krivine.sql
      psql -p $PSQL_PORT -c "SELECT r.* FROM root_terms AS _(t), LATERAL evaluate(t) AS r;"
      ;;
   3) # DuckDB SECD
     psql -p $PSQL_PORT -q -f SECD/secd.sql
     psql -p $PSQL_PORT -q -c "\copy (SELECT id, lit, var, (lam).ide, (lam).body, (app).fun, (app).arg FROM terms) TO 'terms.csv' CSV; \copy (TABLE root_terms) TO 'root_terms.csv' CSV;"
     ./duckdb -c ".read DuckDB/secd.sql; SELECT r.* FROM root_terms AS _(t), LATERAL evaluate(t) AS r;"
     ;;
esac