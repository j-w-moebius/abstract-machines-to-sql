//#include <execnodes.h>
//#include <tuptable.h>
//#include <htup_details.h>


static bool DeleteTupleHashEntry(TupleHashTable hashtable, TupleTableSlot *slot) {
  MemoryContext oldContext;
  MinimalTuple key;
  bool existed;
  key = NULL;

  /* Need to run the hash functions in short-lived context */
  oldContext = MemoryContextSwitchTo(hashtable->tempcxt);

  /* set up data needed by hash and match functions */
  hashtable->inputslot = slot;
  hashtable->in_hash_funcs = hashtable->tab_hash_funcs;
  hashtable->cur_eq_func = hashtable->tab_eq_func;

  existed = tuplehash_delete(hashtable->hashtab, key);

  MemoryContextSwitchTo(oldContext);
  return existed;
}