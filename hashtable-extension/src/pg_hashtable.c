#include "postgres.h"

#include "fmgr.h"
#include "utils/builtins.h"
#include "parser/parser.h"
#include "parser/analyze.h"
#include "nodes/print.h"
#include "nodes/makefuncs.h"

#include "catalog/pg_type.h"
#include "catalog/pg_collation.h"

#include "funcapi.h"
#include "miscadmin.h"
#include "nodes/nodeFuncs.h"

#include "utils/syscache.h"
#include "executor/spi_priv.h"
#include "tcop/utility.h"
#include "nodes/readfuncs.h"

#include "optimizer/planner.h"

#include "utils/snapmgr.h"

#include "access/hash.h"

#include "utils/memutils.h"

#include "utils/tuplestore.h"
#include "access/htup_details.h"

#include "nodes/pg_list.h"
#include "utils/typcache.h"

#include "deleteTupleHashEntry.h"


#ifdef PG_MODULE_MAGIC
PG_MODULE_MAGIC;
#endif

typedef struct PgHashTableData
{
  int            table_id;
  TupleHashTable table;
  TupleDesc      desc;
  Oid           *types;
  int            n_key_cols;
  int            nargs;
  int            length;
} PgHashTableData;
typedef struct PgHashTableData *PgHashTable;
PgHashTable *tables = NULL;

typedef struct PgHashTablesMemory
{
  PgHashTable *tables;
  int          reserved;
  int          used;
} PgHashTablesMemory;
typedef struct PgHashTablesMemory PgHashTablesMem;
PgHashTablesMem *tables_mem = NULL;

void _PG_init(void);
void _PG_fini(void);

void _PG_init(void)
{
  tables = (PgHashTable *) MemoryContextAlloc(TopMemoryContext, sizeof(PgHashTable) * 3);

  tables_mem = (PgHashTablesMem *) MemoryContextAlloc(TopMemoryContext, sizeof(PgHashTablesMem) * 1);
  tables_mem->tables = tables;
  tables_mem->reserved = 3;
  tables_mem->used = 0;
}

void _PG_fini(void)
{

}

// -----------------------------------------------------------------------------

/* http://big-elephants.com/2015-10/writing-postgres-extensions-part-i/
 * https://doxygen.postgresql.org/nodeRecursiveunion_8c_source.html
 *   - build_hash_table
 *   - LookupTupleHashEntry
 */


void dynamic_allocation(int space);

void dynamic_allocation(int space)
{
  PgHashTable *more_tables;
  int table_count;

  more_tables = (PgHashTable *) MemoryContextAlloc(TopMemoryContext, sizeof(PgHashTable) * space);

  table_count = tables_mem->used;

  for (int i = 0; i < table_count; i++)
  {
      more_tables[i] = tables[i];
  }

  tables_mem->tables = more_tables;
  tables_mem->reserved = space;
}

PG_FUNCTION_INFO_V1(prepareHT);

Datum prepareHT(PG_FUNCTION_ARGS)
{
  Datum *args;
  Oid *types;
  bool *nulls;
  int table_id;
  int n_key_cols;
  int nargs;
  List *namesList = NIL;
  List *typesList = NIL;
  List *typmodsList = NIL;
  List *collationsList = NIL;
  TupleDesc desc;
  Oid *eqfunctions;
  FmgrInfo *hashfunctions;
  Oid *collations;
  AttrNumber *key;
  TupleHashTable table;
  int table_count;
  int reserved;
  bool found_table = false;

  MemoryContextSwitchTo(TopMemoryContext);

  table_id = PG_GETARG_INT32(0);
  n_key_cols = PG_GETARG_INT32(1);

  // fetch argument values to build the array
  nargs = extract_variadic_args(fcinfo, 2, true, &args, &types, &nulls);

  for(int i = 0; i < nargs; i++) {
    char *name = "c"; // Rename?
    namesList = lappend(namesList, makeString(name));
    typesList = lappend_oid(typesList, types[i]);
    typmodsList = lappend_int(typmodsList, 0);
    collationsList = lappend_oid(collationsList, InvalidOid);
  }

  desc = BuildDescFromLists(namesList, typesList, typmodsList, collationsList);

  MemoryContextSwitchTo(TopMemoryContext);

  key = palloc(sizeof(AttrNumber) * n_key_cols);
  for (int i = 0; i < n_key_cols; i++){
    key[i] = i+1;
  }

  eqfunctions = palloc(sizeof(Oid) * n_key_cols);
  hashfunctions = palloc(sizeof(FmgrInfo) * n_key_cols);
  collations = palloc(sizeof(Oid) * n_key_cols);

  for(int i = 0; i < n_key_cols; i++) {
    HeapTuple tp;
    Form_pg_type typtup;
    TypeCacheEntry *typ = lookup_type_cache(types[i], TYPECACHE_EQ_OPR
                                                      | TYPECACHE_HASH_PROC
                                                      | TYPECACHE_EQ_OPR_FINFO
                                                      | TYPECACHE_HASH_PROC_FINFO
                                                      | TYPECACHE_HASH_EXTENDED_PROC_FINFO);
    tp = SearchSysCache1(TYPEOID, ObjectIdGetDatum(typ->type_id));
    typtup = (Form_pg_type) GETSTRUCT(tp);
    eqfunctions[i] = typ->eq_opr_finfo.fn_oid;
    if(typ->hash_proc_finfo.fn_oid == InvalidOid) {
      ReleaseSysCache(tp);
      elog(ERROR, "Type '%s' is not hashable.", NameStr(typtup->typname));
    }
    hashfunctions[i] = typ->hash_proc_finfo;
    collations[i] = typ->typcollation;
    ReleaseSysCache(tp);
  }

  table = BuildTupleHashTableExt(NULL,
                                 desc,
                                 n_key_cols,
                                 key,
                                 eqfunctions,
                                 hashfunctions,
                                 collations,
                                 1,
                                 0,
                                 TopMemoryContext,
                                 TopMemoryContext,
                                 TopMemoryContext,
                                 false);

  table_count = tables_mem->used;

  for (int i = 0; i < table_count; i++)
  {
    if (table_id == tables[i]->table_id){
        tables[i]->table = table;
        tables[i]->desc = desc;
        tables[i]->types = types;
        tables[i]->n_key_cols = n_key_cols;
        tables[i]->nargs = nargs;
        tables[i]->length = 0;
        found_table = true;
    }
  }

  if (!found_table){

    reserved = tables_mem->reserved;
    if (table_count >= reserved){
        dynamic_allocation(reserved + 3);
    }

    tables[table_count] = palloc(sizeof(PgHashTableData)*1);
    tables[table_count]->table_id = table_id;
    tables[table_count]->table = table;
    tables[table_count]->desc = desc;
    tables[table_count]->types = types;
    tables[table_count]->n_key_cols = n_key_cols;
    tables[table_count]->nargs = nargs;
    tables[table_count]->length = 0;

    tables_mem->used += 1;
  }

  PG_RETURN_VOID();
}


PG_FUNCTION_INFO_V1(insertToHT);

Datum insertToHT(PG_FUNCTION_ARGS)
{
  TupleHashTable table;
  TupleDesc desc;
  Oid *types;
  bool found_table = false;
  Datum *args;
  Oid *argtypes;
  bool *nulls;
  int nargs;
  int table_id;
  int index;
  int length;
  TupleTableSlot *slot;
  HeapTuple tup;
  bool isnew;
  TupleHashEntry entry;
  int table_count = tables_mem->used;
  bool override = PG_GETARG_BOOL(1);

  MemoryContextSwitchTo(TopMemoryContext);

  table_id = PG_GETARG_INT32(0);

  for (int i = 0; i < table_count; i++)
  {
    if (table_id == tables[i]->table_id){
        table = tables[i]->table;
        desc = tables[i]->desc;
        types = tables[i]->types;
        length = tables[i]->length;
        index = i;
        found_table = true;
        break;
    }
  }

  if (!found_table){
    elog(ERROR, "Table not found");
  }

  nargs = extract_variadic_args(fcinfo, 2, true, &args, &argtypes, &nulls);

  for (int i = 0; i < nargs; i++)
  {
    if(argtypes[i] != types[i]) {
      elog(ERROR, "Types do not match. %d <> %d", argtypes[i], types[i]);
    }
  }

  slot = MakeSingleTupleTableSlot(CreateTupleDescCopy(desc), &TTSOpsHeapTuple);
  tup = heap_form_tuple(desc, args, nulls);
  ExecStoreHeapTuple(tup, slot, InvalidBuffer);

  isnew = false;

  #if PG_VERSION_NUM < 130000
  entry = LookupTupleHashEntry(table, slot, &isnew);
  #elif PG_VERSION_NUM >= 130000
  entry = LookupTupleHashEntry(table, slot, &isnew, NULL);
  #endif

  // enables overwriting
  if(override && !isnew) {
    //  bool DeleteTupleHashEntry(TupleHashTable hashtable, TupleTableSlot *slot)
    DeleteTupleHashEntry(table, slot);

    #if PG_VERSION_NUM < 130000
    entry = LookupTupleHashEntry(table, slot, &isnew);
    #elif PG_VERSION_NUM >= 130000
    entry = LookupTupleHashEntry(table, slot, &isnew, NULL);
    #endif

    // entry->firstTuple = ExecCopySlotMinimalTuple(slot);
    MemoryContextSwitchTo(TopMemoryContext);
  }
  else {
    tables[index]->length = length+1;
  }

  PG_RETURN_VOID();
}


PG_FUNCTION_INFO_V1(lookupHT);

Datum lookupHT(PG_FUNCTION_ARGS)
{
  ReturnSetInfo *rsinfo = (ReturnSetInfo *) fcinfo->resultinfo;
  int table_id;
  TupleHashTable table;
  TupleDesc desc;
  Oid *types;
  bool found_table = false;
  int nargs;
  int n_key_cols;
  Datum *args;
  Oid *argtypes;
  bool *nulls;
  Datum *args_padded;
  bool *nulls_padded;
  TupleTableSlot *slot;
  HeapTuple tup;
  TupleHashEntry entry;
  TupleTableSlot *slot_min_tup;
  Tuplestorestate *store;
  int table_count = tables_mem->used;
  bool upsert = PG_GETARG_BOOL(1);
  bool isnew = false;
  int argcount;
  MemoryContext old;

  old = MemoryContextSwitchTo(TopMemoryContext);

  table_id = PG_GETARG_INT32(0);

  for (int i = 0; i < table_count; i++)
  {
    if (table_id == tables[i]->table_id){
        table = tables[i]->table;
        desc = tables[i]->desc;
        types = tables[i]->types;
        nargs = tables[i]->nargs;
        n_key_cols = tables[i]->n_key_cols;
        found_table = true;
        break;
    }
  }

  MemoryContextSwitchTo(old);

  if (!found_table){
    elog(ERROR, "Table not found");
  }

  args_padded = palloc(sizeof(Datum) * nargs);
  nulls_padded = palloc(sizeof(bool) * nargs);

  /* check to see if caller supports us returning a tuplestore */
  if (rsinfo == NULL || !IsA(rsinfo, ReturnSetInfo))
    ereport(ERROR,
        (errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
         errmsg("set-valued function called in context that cannot accept a set")));
  if (!(rsinfo->allowedModes & SFRM_Materialize))
    ereport(ERROR,
        (errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
         errmsg("materialize mode required, but it is not allowed in this context")));

  /* Build a tuple descriptor for our result type */
  // if (get_call_result_type(fcinfo, NULL, &desc) != TYPEFUNC_COMPOSITE)
  //     ereport(ERROR,
  //             (errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
  //             errmsg("function returning record called in context that cannot accept type record")));


  argcount = extract_variadic_args(fcinfo, 2, true, &args, &argtypes, &nulls);

  for (int i = 0; i < n_key_cols; i++)
  {
    if(argtypes[i] != types[i]) {
      elog(ERROR, "Types do not match. %d <> %d", argtypes[i], types[i]);
    }
  }

  for (int i = 0; i < nargs; i++)
  {
    if(i < argcount || i < n_key_cols) {
      args_padded[i] = args[i];
      nulls_padded[i] = nulls[i];
    } else {
      args_padded[i] = 0;
      nulls_padded[i] = true;
    }
  }

  slot = MakeSingleTupleTableSlot(CreateTupleDescCopy(desc), &TTSOpsHeapTuple);
  tup = heap_form_tuple(desc, args_padded, nulls_padded);
  ExecStoreHeapTuple(tup, slot, InvalidBuffer);
  #if PG_VERSION_NUM < 130000
  if(upsert) {
    entry = LookupTupleHashEntry(table, slot, &isnew);
  } else {
    entry = LookupTupleHashEntry(table, slot, NULL);
  }
  #elif PG_VERSION_NUM >= 130000
  if(upsert) {
    entry = LookupTupleHashEntry(table, slot, &isnew, NULL);
  } else {
    entry = LookupTupleHashEntry(table, slot, NULL, NULL);
  }
  #endif
  slot_min_tup = MakeSingleTupleTableSlot(CreateTupleDescCopy(desc), & TTSOpsMinimalTuple);

  MemoryContextSwitchTo(TopMemoryContext);
  store = tuplestore_begin_heap(false, false, work_mem);

  if(entry != NULL) {
    MemoryContextSwitchTo(TopMemoryContext);
    ExecStoreMinimalTuple(entry->firstTuple, slot_min_tup, true);
    slot_getallattrs(slot_min_tup);
    MemoryContextSwitchTo(old);
    tuplestore_puttupleslot(store, slot_min_tup);
  }

  rsinfo->setResult = store;
  rsinfo->returnMode = SFRM_Materialize;
  /* make sure we have a persistent copy of the result tupdesc */
  rsinfo->setDesc = CreateTupleDescCopy(desc);

  return (Datum) 0;
}

PG_FUNCTION_INFO_V1(lookupHT2);

Datum lookupHT2(PG_FUNCTION_ARGS)
{
  int table_id;
  TupleHashTable table;
  TupleDesc desc;
  Oid *types;
  bool found_table = false;
  int nargs;
  int n_key_cols;
  Datum *args;
  Oid *argtypes;
  bool *nulls;
  Datum *args_padded;
  bool *nulls_padded;
  TupleTableSlot *slot;
  HeapTuple tup;
  TupleHashEntry entry;
  TupleTableSlot *slot_min_tup;
  bool upsert = PG_GETARG_BOOL(1);
  bool isnew = false;
  int argcount;

  ReturnSetInfo *rsinfo = (ReturnSetInfo *) fcinfo->resultinfo;

  table_id = PG_GETARG_INT32(0);

  for (int i = 0; i < tables_mem->used; i++)
  {
    if (table_id == tables[i]->table_id){
        table = tables[i]->table;
        desc = tables[i]->desc;
        types = tables[i]->types;
        nargs = tables[i]->nargs;
        n_key_cols = tables[i]->n_key_cols;
        found_table = true;
        break;
    }
  }

  if (!found_table){
    elog(ERROR, "Table not found");
  }

  args_padded = palloc(sizeof(Datum) * nargs);
  nulls_padded = palloc(sizeof(bool) * nargs);

  /* check to see if caller supports us returning a tuplestore */
  // if (rsinfo == NULL || !IsA(rsinfo, ReturnSetInfo))
  //   ereport(ERROR,
  //       (errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
  //        errmsg("set-valued function called in context that cannot accept a set")));
  // if (!(rsinfo->allowedModes & SFRM_Materialize))
  //   ereport(ERROR,
  //       (errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
  //        errmsg("materialize mode required, but it is not allowed in this context")));

  /* Build a tuple descriptor for our result type */
  // if (get_call_result_type(fcinfo, NULL, &desc) != TYPEFUNC_COMPOSITE)
  //     ereport(ERROR,
  //             (errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
  //             errmsg("function returning record called in context that cannot accept type record")));


  argcount = extract_variadic_args(fcinfo, 2, true, &args, &argtypes, &nulls);

  for (int i = 0; i < n_key_cols; i++)
  {
    if(argtypes[i] != types[i]) {
      elog(ERROR, "Types do not match. %d <> %d", argtypes[i], types[i]);
    }
  }

  for (int i = 0; i < nargs; i++)
  {
    if(i < argcount || i < n_key_cols) {
      args_padded[i] = args[i];
      nulls_padded[i] = nulls[i];
    } else {
      args_padded[i] = 0;
      nulls_padded[i] = true;
    }
  }

  slot = MakeSingleTupleTableSlot(CreateTupleDescCopy(desc), &TTSOpsHeapTuple);
  tup = heap_form_tuple(desc, args_padded, nulls_padded);
  ExecStoreHeapTuple(tup, slot, InvalidBuffer);

  #if PG_VERSION_NUM < 130000
  if(upsert) {
    entry = LookupTupleHashEntry(table, slot, &isnew);
  } else {
    entry = LookupTupleHashEntry(table, slot, NULL);
  }
  #elif PG_VERSION_NUM >= 130000
  if(upsert) {
    entry = LookupTupleHashEntry(table, slot, &isnew, NULL);
  } else {
    entry = LookupTupleHashEntry(table, slot, NULL, NULL);
  }
  #endif

  slot_min_tup = MakeSingleTupleTableSlot(CreateTupleDescCopy(desc), & TTSOpsMinimalTuple);

  MemoryContextSwitchTo(TopMemoryContext);

  if(entry != NULL) {
    // ExecStoreMinimalTuple(entry->firstTuple, slot_min_tup, false);
    // slot_getallattrs(slot_min_tup);
    // tuplestore_puttupleslot(store, slot_min_tup);
    tup = heap_tuple_from_minimal_tuple(entry->firstTuple);
    assign_record_type_typmod(desc);
    PG_RETURN_DATUM(heap_copy_tuple_as_datum(tup, desc));
  }

  // rsinfo->setResult = store;
  // rsinfo->returnMode = SFRM_Materialize;
  // /* make sure we have a persistent copy of the result tupdesc */
  // rsinfo->setDesc = CreateTupleDescCopy(desc);

  return (Datum) 0;
}


PG_FUNCTION_INFO_V1(removeFromHT);

Datum removeFromHT(PG_FUNCTION_ARGS)
{
  int table_id;
  TupleHashTable table;
  TupleDesc desc;
  Oid *types;
  int index;
  int length;
  bool found_table = false;
  int nargs;
  int n_key_cols;
  Datum *args;
  Oid *argtypes;
  bool *nulls;
  Datum *args_padded;
  bool *nulls_padded;
  TupleTableSlot *slot;
  HeapTuple tup;
  bool existed;
  int table_count = tables_mem->used;

  MemoryContextSwitchTo(TopMemoryContext);

  table_id = PG_GETARG_INT32(0);

  for (int i = 0; i < table_count; i++)
  {
    if (table_id == tables[i]->table_id){
        table = tables[i]->table;
        desc = tables[i]->desc;
        types = tables[i]->types;
        nargs = tables[i]->nargs;
        n_key_cols = tables[i]->n_key_cols;
        length = tables[i]->length;
        index = i;
        found_table = true;
        break;
    }
  }

  if (!found_table){
    elog(ERROR, "Table not found");
  }

  args_padded = palloc(sizeof(Datum) * nargs);
  nulls_padded = palloc(sizeof(bool) * nargs);

  extract_variadic_args(fcinfo, 1, true, &args, &argtypes, &nulls);

  for (int i = 0; i < n_key_cols; i++)
  {
    if(argtypes[i] != types[i]) {
      elog(ERROR, "Types do not match. %d <> %d", argtypes[i], types[i]);
    }
  }

  for (int i = 0; i < nargs; i++)
  {
    if(i < n_key_cols) {
      args_padded[i] = args[i];
      nulls_padded[i] = nulls[i];
    } else {
      args_padded[i] = 0;
      nulls_padded[i] = true;
    }
  }

  slot = MakeSingleTupleTableSlot(CreateTupleDescCopy(desc), &TTSOpsHeapTuple);
  tup = heap_form_tuple(desc, args_padded, nulls_padded);
  ExecStoreHeapTuple(tup, slot, InvalidBuffer);

  existed = DeleteTupleHashEntry(table, slot);

  MemoryContextSwitchTo(TopMemoryContext);

  if (existed) {
    tables[index]->length = length-1;
  }

  PG_RETURN_VOID();
}


PG_FUNCTION_INFO_V1(scanHT);

Datum scanHT(PG_FUNCTION_ARGS)
{
  Tuplestorestate *store;
  TupleTableSlot *slot_min_tup;
  TupleHashTable table;
  TupleDesc desc;
  TupleHashIterator hashiter;
  bool done = false;
  TupleHashEntry entry;
  int table_count = tables_mem->used;

  ReturnSetInfo *rsinfo = (ReturnSetInfo *) fcinfo->resultinfo;

  int table_id = PG_GETARG_INT32(0);
  bool found_table = false;

  for (int i = 0; i < table_count; i++)
  {
    if (table_id == tables[i]->table_id){
        table = tables[i]->table;
        desc = tables[i]->desc;
        found_table = true;
        break;
    }
  }

  if (!found_table){
    elog(ERROR, "Table not found");
  }

  /* check to see if caller supports us returning a tuplestore */
  if (rsinfo == NULL || !IsA(rsinfo, ReturnSetInfo))
    ereport(ERROR,
        (errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
         errmsg("set-valued function called in context that cannot accept a set")));
  if (!(rsinfo->allowedModes & SFRM_Materialize))
    ereport(ERROR,
        (errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
         errmsg("materialize mode required, but it is not allowed in this context")));

  /* Build a tuple descriptor for our result type */
  // if (get_call_result_type(fcinfo, NULL, &desc) != TYPEFUNC_COMPOSITE)
  //     ereport(ERROR,
  //             (errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
  //             errmsg("function returning record called in context that cannot accept type record")));

  MemoryContextSwitchTo(TopMemoryContext);
  store = tuplestore_begin_heap(false, false, work_mem);
  slot_min_tup = MakeSingleTupleTableSlot(CreateTupleDescCopy(desc), & TTSOpsMinimalTuple);

  InitTupleHashIterator(table, &hashiter);

  while(!done) {
    entry = ScanTupleHashTable(table, &hashiter);

    if(entry != NULL) {
      ExecStoreMinimalTuple(entry->firstTuple, slot_min_tup, false);
      slot_getallattrs(slot_min_tup);
      tuplestore_puttupleslot(store, slot_min_tup);
    } else {
      done = true;
    }
  }
  rsinfo->setResult = store;
  rsinfo->returnMode = SFRM_Materialize;
  /* make sure we have a persistent copy of the result tupdesc */
  rsinfo->setDesc = CreateTupleDescCopy(desc);

  MemoryContextSwitchTo(TopMemoryContext);

  return (Datum) 0;
}


PG_FUNCTION_INFO_V1(lengthHT);

Datum lengthHT(PG_FUNCTION_ARGS)
{
  bool found_table = false;
  int table_id;
  int table_count = tables_mem->used;

  MemoryContextSwitchTo(TopMemoryContext);

  table_id = PG_GETARG_INT32(0);

  for (int i = 0; i < table_count; i++)
  {
    if (table_id == tables[i]->table_id){
        PG_RETURN_INT32(tables[i]->length);
        found_table = true;
        break;
    }
  }

  if (!found_table){
    elog(ERROR, "Table not found");
  }

  PG_RETURN_INT32(-1);
}
