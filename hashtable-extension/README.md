# PG Hashtable
Written by Denis Hirn.
## Setup
When postgres is installed manually, run
```bash
$ make
$ make install
```
in `src`.
When postgres is installed via apt, just install
```bash
$ sudo apt-get -y install postgresql-server-dev-13
```
before you do
```bash
$ make
$ sudo make install
```

Now you can run
```bash
$ psql -c "CREATE EXTENSION pg_hashtable"
```

## Usage
```sql
SELECT prepareHT(1, 3, NULL :: integer, NULL :: integer, NULL :: integer, NULL :: integer);

#  prepareht
# -----------
#
# (1 row)
```
The first argument separates the hash tables from each other, the second is the
number of key columns.

```sql
SELECT * FROM lookupHT(1, false, 1, 2, 4) AS _(location integer, tuid1 integer, tuid2 integer, tuidout integer);
#  location | tuid1 | tuid2 | tuidout
# ----------+-------+-------+---------
# (0 rows)
```

The first argument identifies the hash table to look in, the second states,
whether an element should be written on lookup, or not.
```sql
SELECT * FROM lookupHT(1, true, 1, 2, 4, 42) AS _(location integer, tuid1 integer, tuid2 integer, tuidout integer);
#  location | tuid1 | tuid2 | tuidout
# ----------+-------+-------+---------
#         1 |     2 |     4 |      42
# (1 row)

SELECT * FROM scanHT(1) AS _(location integer, tuid1 integer, tuid2 integer, tuidout integer);
#  location | tuid1 | tuid2 | tuidout
# ----------+-------+-------+---------
#         1 |     2 |     4 |      42
# (1 row)
```
