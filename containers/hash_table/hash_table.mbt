/// Generic hash table using open addressing with linear probing.
///
/// The table stores arbitrary key-value pairs `(K, V)`.  Because MoonBit
/// cannot derive equality or hashing for arbitrary types, every public
/// operation receives an explicit `hash_fn : (K) -> Int` and
/// `eq_fn : (K, K) -> Bool`.  This keeps the data structure fully generic
/// and lets callers plug in whatever strategy they need (identity vs.
/// structural equality, custom hash seeds, etc.).
///
/// Design:
/// - **Open addressing** with **linear probing** (step = 1).
/// - **Tombstones** mark deleted slots so that probe chains for keys
///   inserted *before* a deletion remain intact.
/// - **Wrap-around probing**: `(idx + 1) % capacity` continues from slot 0
///   when the end of the array is reached.
/// - **Automatic resize**: when the load factor (`count / capacity`) would
///   exceed 0.7 after an insertion, the table doubles in capacity and
///   rehashes all live entries.  Tombstones are discarded during rehash.
/// - All struct fields are `mut` so that `_resize` can swap in new arrays
///   and `insert` / `remove` can update `count` in place.
///
/// Not formally verified.  Correctness is ensured by comprehensive tests.
///
/// Time complexity (average): O(1) for `insert`, `get`, `remove`, `contains`.
/// Worst-case (all keys collide): O(n).

/// A hash table mapping keys of type `K` to values of type `V`.
///
/// Each slot can be in one of three states:
/// - **Empty**: `occupied[i] == false && tombstone[i] == false`
///   Probing stops here.
/// - **Live**: `occupied[i] == true`
///   `keys[i]` and `vals[i]` hold the entry.
/// - **Tombstone**: `tombstone[i] == true`
///   A previously live slot that was deleted.  Probing continues past it;
///   it can be reused by a future `insert`.
pub struct HashTable[K, V] {
  mut keys : FixedArray[K?]
  mut vals : FixedArray[V?]
  mut occupied : FixedArray[Bool]
  mut tombstone : FixedArray[Bool]
  mut count : Int
  mut capacity : Int
}

/// Map a hash value into `[0, capacity)` handling negative results.
/// MoonBit's `%` follows truncated division (sign follows dividend), so
/// we add `capacity` before the final modulo to guarantee non-negativity.
fn _slot(capacity : Int, h : Int) -> Int {
  ((h % capacity) + capacity) % capacity
}

/// Create an empty `HashTable` with the given initial capacity.
/// `capacity` must be > 0; if a non-positive value is passed, it defaults to 1.
pub fn[K, V] new(capacity : Int) -> HashTable[K, V] {
  let cap = if capacity > 0 { capacity } else { 1 }
  {
    keys: FixedArray::make(cap, None),
    vals: FixedArray::make(cap, None),
    occupied: FixedArray::make(cap, false),
    tombstone: FixedArray::make(cap, false),
    count: 0,
    capacity: cap,
  }
}

/// Internal insert / update **without** resize checking.
///
/// Probes from the hash index, updating an existing key if found, or
/// inserting at the first tombstone (if any) or the first empty slot.
/// Returns `true` on success, `false` if the table is completely full of
/// live entries and tombstones (the caller should resize).
fn[K, V] _put(
  ht : HashTable[K, V],
  key : K,
  value : V,
  hash_fn : (K) -> Int,
  eq_fn : (K, K) -> Bool,
) -> Bool {
  let start = _slot(ht.capacity, hash_fn(key))
  let mut idx = start
  let mut first_tomb = -1
  // Probe through live and tombstone slots
  while ht.occupied[idx] || ht.tombstone[idx] {
    if ht.occupied[idx] {
      match ht.keys[idx] {
        Some(k) =>
          if eq_fn(k, key) {
            ht.vals[idx] = Some(value)
            return true // update existing
          }
        None => ()
      }
    } else if first_tomb == -1 {
      first_tomb = idx // remember first reusable tombstone
    }
    idx = (idx + 1) % ht.capacity
    if idx == start {
      break // wrapped around — table is full
    }
  }
  // Insert at the first tombstone (preferred) or the empty slot we stopped at
  let pos = if first_tomb != -1 { first_tomb } else { idx }
  if ht.occupied[pos] {
    return false // no empty slot and no tombstone — truly full
  }
  ht.keys[pos] = Some(key)
  ht.vals[pos] = Some(value)
  ht.occupied[pos] = true
  ht.tombstone[pos] = false
  ht.count = ht.count + 1
  true
}

/// Rehash all live entries into a fresh array of `new_cap` slots.
/// Tombstones are discarded (not re-inserted), which compacts the table.
fn[K, V] _resize(
  ht : HashTable[K, V],
  new_cap : Int,
  hash_fn : (K) -> Int,
  eq_fn : (K, K) -> Bool,
) -> Unit {
  let old_keys = ht.keys
  let old_vals = ht.vals
  let old_occ = ht.occupied
  let old_cap = ht.capacity
  ht.keys = FixedArray::make(new_cap, None)
  ht.vals = FixedArray::make(new_cap, None)
  ht.occupied = FixedArray::make(new_cap, false)
  ht.tombstone = FixedArray::make(new_cap, false)
  ht.capacity = new_cap
  ht.count = 0
  for i = 0; i < old_cap; i = i + 1 {
    if old_occ[i] {
      match (old_keys[i], old_vals[i]) {
        (Some(k), Some(v)) => ignore(_put(ht, k, v, hash_fn, eq_fn))
        _ => ()
      }
    }
  }
}

/// Insert or update a key-value pair.
///
/// If `key` already exists, its value is replaced.  Otherwise a new entry
/// is created.  When the load factor would exceed 0.7, the table first
/// tries to compact (rehash to the same capacity, discarding tombstones).
/// If compaction alone doesn't bring the load factor below 0.7, the table
/// doubles in capacity. This avoids unnecessary memory growth when the
/// table has many deleted entries.
pub fn[K, V] insert(
  ht : HashTable[K, V],
  key : K,
  value : V,
  hash_fn : (K) -> Int,
  eq_fn : (K, K) -> Bool,
) -> Unit {
  // If adding a new entry would push load factor above 0.7, first try
  // compacting (rehash to same capacity to clear tombstones).
  if (ht.count + 1) * 10 > ht.capacity * 7 {
    // Compact first: rehash to same capacity, clearing tombstones.
    _resize(ht, ht.capacity, hash_fn, eq_fn)
    // If still above threshold after compaction, double capacity.
    if (ht.count + 1) * 10 > ht.capacity * 7 {
      _resize(ht, ht.capacity * 2, hash_fn, eq_fn)
    }
  }
  let ok = _put(ht, key, value, hash_fn, eq_fn)
  if !ok {
    // Table was full of tombstones: compact to same capacity, then retry.
    _resize(ht, ht.capacity, hash_fn, eq_fn)
    let ok2 = _put(ht, key, value, hash_fn, eq_fn)
    if !ok2 {
      // Still full after compaction: double capacity and retry.
      _resize(ht, ht.capacity * 2, hash_fn, eq_fn)
      let _ = _put(ht, key, value, hash_fn, eq_fn)
    }
  }
}

/// Look up the value associated with `key`.
/// Returns `Some(v)` if found, `None` otherwise.
pub fn[K, V] get(
  ht : HashTable[K, V],
  key : K,
  hash_fn : (K) -> Int,
  eq_fn : (K, K) -> Bool,
) -> V? {
  let start = _slot(ht.capacity, hash_fn(key))
  let mut idx = start
  while ht.occupied[idx] || ht.tombstone[idx] {
    if ht.occupied[idx] {
      match ht.keys[idx] {
        Some(k) =>
          if eq_fn(k, key) {
            return ht.vals[idx]
          }
        None => ()
      }
    }
    idx = (idx + 1) % ht.capacity
    if idx == start {
      return None // wrapped around
    }
  }
  None // hit an empty slot
}

/// Remove the entry for `key`, marking its slot as a tombstone.
/// Returns `true` if the key was found and removed, `false` otherwise.
pub fn[K, V] remove(
  ht : HashTable[K, V],
  key : K,
  hash_fn : (K) -> Int,
  eq_fn : (K, K) -> Bool,
) -> Bool {
  let start = _slot(ht.capacity, hash_fn(key))
  let mut idx = start
  while ht.occupied[idx] || ht.tombstone[idx] {
    if ht.occupied[idx] {
      match ht.keys[idx] {
        Some(k) =>
          if eq_fn(k, key) {
            ht.keys[idx] = None
            ht.vals[idx] = None
            ht.occupied[idx] = false
            ht.tombstone[idx] = true
            ht.count = ht.count - 1
            return true
          }
        None => ()
      }
    }
    idx = (idx + 1) % ht.capacity
    if idx == start {
      return false
    }
  }
  false
}

/// Check whether `key` is present in the table.
pub fn[K, V] contains(
  ht : HashTable[K, V],
  key : K,
  hash_fn : (K) -> Int,
  eq_fn : (K, K) -> Bool,
) -> Bool {
  get(ht, key, hash_fn, eq_fn) is Some(_)
}

/// Return the number of live entries.
pub fn[K, V] size(ht : HashTable[K, V]) -> Int {
  ht.count
}

// ---------------------------------------------------------------------------
// Encapsulated HashTable (String -> Int)
// ---------------------------------------------------------------------------
//
// The free functions above require every `insert` / `get` / `remove` call to
// pass `hash_fn` and `eq_fn` explicitly.  A caller that accidentally uses
// different functions across operations will silently corrupt the table.
//
// `StringHashTable` stores the hash and equality functions once, at
// construction time, and exposes `hashtable_*` operations that supply them
// automatically.  This eliminates the risk of inconsistent hash functions.
// It delegates to the existing, well-tested generic `HashTable[String, Int]`,
// so the open-addressing / linear-probing / resize behaviour is reused
// rather than duplicated.

/// An encapsulated hash table mapping `String` keys to `Int` values.
///
/// The `hash_fn` and `eq_fn` are bound at construction and reused for every
/// operation, so callers can never accidentally mix mismatched functions.
pub struct StringHashTable {
  inner : HashTable[String, Int]
  hash_fn : (String) -> Int
  eq_fn : (String, String) -> Bool
}

/// Create a new `StringHashTable` with the given capacity, hash function,
/// and equality function.
///
/// The hash and equality functions are stored in the struct, so callers
/// never need to pass them again.  This eliminates the risk of using
/// inconsistent hash functions across operations.
pub fn hashtable_new(
  capacity : Int,
  hash_fn : (String) -> Int,
  eq_fn : (String, String) -> Bool,
) -> StringHashTable {
  { inner: new(capacity), hash_fn, eq_fn }
}

/// Convenience constructor with a default polynomial string hash and
/// structural string equality.
pub fn hashtable_new_default(capacity : Int) -> StringHashTable {
  hashtable_new(
    capacity,
    fn(s) {
      let mut h = 0
      for i = 0; i < s.length(); i = i + 1 {
        h = h * 31 + s[i].to_int()
      }
      h
    },
    fn(a, b) { a == b },
  )
}

/// Insert or update a key-value pair, using the bound hash/eq functions.
pub fn hashtable_insert(ht : StringHashTable, key : String, value : Int) -> Unit {
  insert(ht.inner, key, value, ht.hash_fn, ht.eq_fn)
}

/// Look up the value associated with `key`, using the bound hash/eq functions.
pub fn hashtable_get(ht : StringHashTable, key : String) -> Int? {
  get(ht.inner, key, ht.hash_fn, ht.eq_fn)
}

/// Remove the entry for `key`, using the bound hash/eq functions.
/// Returns `true` if the key was found and removed, `false` otherwise.
pub fn hashtable_remove(ht : StringHashTable, key : String) -> Bool {
  remove(ht.inner, key, ht.hash_fn, ht.eq_fn)
}

/// Return the number of live entries.
pub fn hashtable_size(ht : StringHashTable) -> Int {
  size(ht.inner)
}

/// Check whether `key` is present, using the bound hash/eq functions.
pub fn hashtable_contains(ht : StringHashTable, key : String) -> Bool {
  contains(ht.inner, key, ht.hash_fn, ht.eq_fn)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "basic insert and get" {
  let ht : HashTable[Int, String] = new(16)
  let h = fn(x : Int) { x }
  let e = fn(a : Int, b : Int) { a == b }
  insert(ht, 1, "one", h, e)
  insert(ht, 2, "two", h, e)
  insert(ht, 3, "three", h, e)
  assert_eq(get(ht, 1, h, e).unwrap(), "one")
  assert_eq(get(ht, 2, h, e).unwrap(), "two")
  assert_eq(get(ht, 3, h, e).unwrap(), "three")
  assert_eq(size(ht), 3)
}

test "update existing key" {
  let ht : HashTable[Int, String] = new(8)
  let h = fn(x : Int) { x }
  let e = fn(a : Int, b : Int) { a == b }
  insert(ht, 10, "old", h, e)
  assert_eq(get(ht, 10, h, e).unwrap(), "old")
  assert_eq(size(ht), 1)
  insert(ht, 10, "new", h, e)
  assert_eq(get(ht, 10, h, e).unwrap(), "new")
  assert_eq(size(ht), 1) // count unchanged on update
}

test "remove existing key" {
  let ht : HashTable[Int, String] = new(8)
  let h = fn(x : Int) { x }
  let e = fn(a : Int, b : Int) { a == b }
  insert(ht, 5, "five", h, e)
  insert(ht, 10, "ten", h, e)
  assert_eq(remove(ht, 5, h, e), true)
  assert_true(get(ht, 5, h, e) is None)
  assert_eq(get(ht, 10, h, e).unwrap(), "ten") // other entry unaffected
  assert_eq(size(ht), 1)
}

test "remove non-existing key returns false" {
  let ht : HashTable[Int, String] = new(8)
  let h = fn(x : Int) { x }
  let e = fn(a : Int, b : Int) { a == b }
  insert(ht, 1, "one", h, e)
  assert_eq(remove(ht, 99, h, e), false)
  assert_eq(size(ht), 1)
  assert_eq(remove(ht, 99, h, e), false) // still false on empty table region
}

test "get non-existing key returns None" {
  let ht : HashTable[Int, String] = new(8)
  let h = fn(x : Int) { x }
  let e = fn(a : Int, b : Int) { a == b }
  insert(ht, 1, "one", h, e)
  assert_true(get(ht, 2, h, e) is None)
  assert_true(get(ht, 0, h, e) is None)
  // Get on empty table
  let ht2 : HashTable[Int, String] = new(4)
  assert_true(get(ht2, 1, h, e) is None)
}

test "collision handling: all keys hash to same slot" {
  let ht : HashTable[Int, String] = new(16)
  // Force every key into slot 0 — linear probing must chain them
  let h = fn(_x : Int) { 0 }
  let e = fn(a : Int, b : Int) { a == b }
  insert(ht, 100, "a", h, e)
  insert(ht, 200, "b", h, e)
  insert(ht, 300, "c", h, e)
  assert_eq(get(ht, 100, h, e).unwrap(), "a")
  assert_eq(get(ht, 200, h, e).unwrap(), "b")
  assert_eq(get(ht, 300, h, e).unwrap(), "c")
  assert_eq(size(ht), 3)
  // Verify they are chained in consecutive slots (0, 1, 2)
  assert_eq(ht.keys[0], Some(100))
  assert_eq(ht.keys[1], Some(200))
  assert_eq(ht.keys[2], Some(300))
}

test "resize when load factor exceeds 0.7" {
  let ht : HashTable[Int, Int] = new(4)
  let h = fn(x : Int) { x }
  let e = fn(a : Int, b : Int) { a == b }
  // capacity 4: resize triggers when (count+1)*10 > 4*7 = 28, i.e. count >= 2
  insert(ht, 1, 10, h, e)
  insert(ht, 2, 20, h, e)
  assert_eq(ht.capacity, 4) // not yet resized
  insert(ht, 3, 30, h, e) // triggers resize to 8
  assert_eq(ht.capacity, 8)
  assert_eq(size(ht), 3)
  // All entries still retrievable after rehash
  assert_eq(get(ht, 1, h, e).unwrap(), 10)
  assert_eq(get(ht, 2, h, e).unwrap(), 20)
  assert_eq(get(ht, 3, h, e).unwrap(), 30)
}

test "large dataset: 200 entries with insert, get, remove" {
  let ht : HashTable[Int, Int] = new(8)
  let h = fn(x : Int) { x }
  let e = fn(a : Int, b : Int) { a == b }
  for i = 0; i < 200; i = i + 1 {
    insert(ht, i, i * 10, h, e)
  }
  assert_eq(size(ht), 200)
  for i = 0; i < 200; i = i + 1 {
    assert_eq(get(ht, i, h, e).unwrap(), i * 10)
  }
  // Remove first 100
  for i = 0; i < 100; i = i + 1 {
    assert_eq(remove(ht, i, h, e), true)
  }
  assert_eq(size(ht), 100)
  // Removed keys are gone
  for i = 0; i < 100; i = i + 1 {
    assert_true(get(ht, i, h, e) is None)
  }
  // Remaining keys still intact
  for i = 100; i < 200; i = i + 1 {
    assert_eq(get(ht, i, h, e).unwrap(), i * 10)
  }
  // Re-insert a removed key
  insert(ht, 0, 999, h, e)
  assert_eq(get(ht, 0, h, e).unwrap(), 999)
  assert_eq(size(ht), 101)
}

test "string keys with polynomial hash" {
  let ht : HashTable[String, Int] = new(16)
  let h = fn(s : String) {
    let mut v = 0
    for i = 0; i < s.length(); i = i + 1 {
      v = 31 * v + s[i].to_int()
    }
    v
  }
  let e = fn(a : String, b : String) { a == b }
  insert(ht, "apple", 1, h, e)
  insert(ht, "banana", 2, h, e)
  insert(ht, "cherry", 3, h, e)
  insert(ht, "date", 4, h, e)
  assert_eq(get(ht, "apple", h, e).unwrap(), 1)
  assert_eq(get(ht, "banana", h, e).unwrap(), 2)
  assert_eq(get(ht, "cherry", h, e).unwrap(), 3)
  assert_eq(get(ht, "date", h, e).unwrap(), 4)
  assert_true(get(ht, "grape", h, e) is None)
  // Update
  insert(ht, "apple", 100, h, e)
  assert_eq(get(ht, "apple", h, e).unwrap(), 100)
  // Remove
  assert_eq(remove(ht, "banana", h, e), true)
  assert_true(get(ht, "banana", h, e) is None)
  assert_eq(size(ht), 3)
}

test "size tracking after insert and remove" {
  let ht : HashTable[Int, Int] = new(8)
  let h = fn(x : Int) { x }
  let e = fn(a : Int, b : Int) { a == b }
  assert_eq(size(ht), 0)
  insert(ht, 1, 10, h, e)
  insert(ht, 2, 20, h, e)
  assert_eq(size(ht), 2)
  insert(ht, 1, 11, h, e) // update — no size change
  assert_eq(size(ht), 2)
  assert_eq(remove(ht, 1, h, e), true)
  assert_eq(size(ht), 1)
  assert_eq(remove(ht, 2, h, e), true)
  assert_eq(size(ht), 0)
  assert_eq(remove(ht, 2, h, e), false) // already removed
  assert_eq(size(ht), 0)
  // Insert after removing all
  insert(ht, 3, 30, h, e)
  assert_eq(size(ht), 1)
}

test "contains check" {
  let ht : HashTable[Int, String] = new(8)
  let h = fn(x : Int) { x }
  let e = fn(a : Int, b : Int) { a == b }
  assert_eq(contains(ht, 1, h, e), false)
  insert(ht, 1, "one", h, e)
  insert(ht, 2, "two", h, e)
  assert_eq(contains(ht, 1, h, e), true)
  assert_eq(contains(ht, 2, h, e), true)
  assert_eq(contains(ht, 3, h, e), false)
  assert_eq(remove(ht, 1, h, e), true)
  assert_eq(contains(ht, 1, h, e), false)
  assert_eq(contains(ht, 2, h, e), true)
}

test "wrap-around probing verification" {
  let ht : HashTable[Int, Int] = new(8)
  // All keys hash to slot 7 (the last slot), forcing wrap-around to 0, 1, 2...
  let h = fn(_x : Int) { 7 }
  let e = fn(a : Int, b : Int) { a == b }
  insert(ht, 10, 100, h, e) // slot 7
  insert(ht, 20, 200, h, e) // wraps to slot 0
  insert(ht, 30, 300, h, e) // wraps to slot 1
  insert(ht, 40, 400, h, e) // wraps to slot 2
  assert_eq(size(ht), 4)
  // Verify physical placement
  assert_eq(ht.keys[7], Some(10))
  assert_eq(ht.keys[0], Some(20))
  assert_eq(ht.keys[1], Some(30))
  assert_eq(ht.keys[2], Some(40))
  // Lookup wraps correctly
  assert_eq(get(ht, 10, h, e).unwrap(), 100)
  assert_eq(get(ht, 20, h, e).unwrap(), 200)
  assert_eq(get(ht, 30, h, e).unwrap(), 300)
  assert_eq(get(ht, 40, h, e).unwrap(), 400)
  // Remove from the middle of the probe chain
  assert_eq(remove(ht, 20, h, e), true)
  assert_true(ht.tombstone[0]) // slot 0 is now a tombstone
  // Keys before and after the tombstone are still reachable
  assert_eq(get(ht, 10, h, e).unwrap(), 100)
  assert_eq(get(ht, 30, h, e).unwrap(), 300)
  assert_eq(get(ht, 40, h, e).unwrap(), 400)
  // Re-insert reuses the tombstone slot
  insert(ht, 50, 500, h, e)
  assert_eq(ht.keys[0], Some(50)) // reused tombstone
  assert_eq(ht.tombstone[0], false)
  assert_eq(size(ht), 4)
}

test "tombstone reuse after deletion" {
  let ht : HashTable[Int, String] = new(16)
  let h = fn(_x : Int) { 5 } // all collide at slot 5
  let e = fn(a : Int, b : Int) { a == b }
  insert(ht, 1, "a", h, e) // slot 5
  insert(ht, 2, "b", h, e) // slot 6
  insert(ht, 3, "c", h, e) // slot 7
  assert_eq(remove(ht, 2, h, e), true) // slot 6 becomes tombstone
  insert(ht, 4, "d", h, e) // should reuse slot 6 (tombstone)
  assert_eq(ht.keys[6], Some(4))
  assert_eq(ht.tombstone[6], false)
  assert_eq(get(ht, 4, h, e).unwrap(), "d")
  assert_eq(get(ht, 1, h, e).unwrap(), "a")
  assert_eq(get(ht, 3, h, e).unwrap(), "c")
}

test "get after resize with collisions" {
  let ht : HashTable[Int, Int] = new(4)
  let h = fn(_x : Int) { 3 } // all collide
  let e = fn(a : Int, b : Int) { a == b }
  // Insert enough to force at least one resize
  for i = 0; i < 10; i = i + 1 {
    insert(ht, i, i * 2, h, e)
  }
  assert_eq(size(ht), 10)
  assert_true(ht.capacity >= 16) // resized at least once
  for i = 0; i < 10; i = i + 1 {
    assert_eq(get(ht, i, h, e).unwrap(), i * 2)
  }
  // Remove and re-add
  for i = 0; i < 5; i = i + 1 {
    assert_eq(remove(ht, i, h, e), true)
  }
  assert_eq(size(ht), 5)
  for i = 5; i < 10; i = i + 1 {
    assert_eq(get(ht, i, h, e).unwrap(), i * 2)
  }
}

test "single entry edge case" {
  let ht : HashTable[Int, String] = new(1)
  let h = fn(x : Int) { x }
  let e = fn(a : Int, b : Int) { a == b }
  insert(ht, 42, "answer", h, e) // triggers resize (capacity 1 → 2 → ...)
  assert_eq(get(ht, 42, h, e).unwrap(), "answer")
  assert_eq(size(ht), 1)
  assert_true(ht.capacity > 1)
  assert_eq(remove(ht, 42, h, e), true)
  assert_true(get(ht, 42, h, e) is None)
  assert_eq(size(ht), 0)
}

test "HashTable: encapsulated insert and get" {
  let ht = hashtable_new_default(16)
  hashtable_insert(ht, "apple", 1)
  hashtable_insert(ht, "banana", 2)
  hashtable_insert(ht, "cherry", 3)
  assert_eq(hashtable_get(ht, "apple"), Some(1))
  assert_eq(hashtable_get(ht, "banana"), Some(2))
  assert_eq(hashtable_get(ht, "cherry"), Some(3))
  assert_true(hashtable_get(ht, "grape") is None)
  assert_eq(hashtable_size(ht), 3)
}

test "HashTable: encapsulated contains" {
  let ht = hashtable_new_default(8)
  hashtable_insert(ht, "key", 42)
  assert_true(hashtable_contains(ht, "key"))
  assert_false(hashtable_contains(ht, "missing"))
}

test "HashTable: encapsulated remove" {
  let ht = hashtable_new_default(8)
  hashtable_insert(ht, "a", 1)
  hashtable_insert(ht, "b", 2)
  assert_true(hashtable_remove(ht, "a"))
  assert_false(hashtable_contains(ht, "a"))
  assert_true(hashtable_contains(ht, "b"))
  assert_eq(hashtable_size(ht), 1)
}

test "HashTable: custom hash function" {
  // Use a simple identity hash for testing
  let ht = hashtable_new(16, fn(s) { s.length() }, fn(a, b) { a == b })
  hashtable_insert(ht, "ab", 10)
  hashtable_insert(ht, "cd", 20)
  assert_eq(hashtable_get(ht, "ab"), Some(10))
  assert_eq(hashtable_get(ht, "cd"), Some(20))
}
