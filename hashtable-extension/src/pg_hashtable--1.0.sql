SET search_path = public;

CREATE OR REPLACE FUNCTION prepareHT(tableID int, nkeycols int, VARIADIC "any")
RETURNS VOID
AS '$libdir/pg_hashtable','prepareHT'
LANGUAGE C VOLATILE;

CREATE OR REPLACE FUNCTION insertToHT(tableID int, override boolean, VARIADIC "any")
RETURNS VOID
AS '$libdir/pg_hashtable','insertToHT'
LANGUAGE C VOLATILE;

CREATE OR REPLACE FUNCTION removeFromHT(tableID int, VARIADIC "any")
RETURNS VOID
AS '$libdir/pg_hashtable','removeFromHT'
LANGUAGE C VOLATILE;

CREATE OR REPLACE FUNCTION lookupHT(tableID int, upsert boolean, VARIADIC "any")
RETURNS SETOF record
AS '$libdir/pg_hashtable','lookupHT'
LANGUAGE C VOLATILE ROWS 1;

CREATE OR REPLACE FUNCTION lookupHT2(tableID int, upsert boolean, VARIADIC "any")
RETURNS record
AS '$libdir/pg_hashtable','lookupHT2'
LANGUAGE C VOLATILE;

CREATE OR REPLACE FUNCTION scanHT(tableID int)
RETURNS SETOF record
AS '$libdir/pg_hashtable','scanHT'
LANGUAGE C VOLATILE;

CREATE OR REPLACE FUNCTION lengthHT(tableID int)
RETURNS int
AS '$libdir/pg_hashtable','lengthHT'
LANGUAGE C VOLATILE;
