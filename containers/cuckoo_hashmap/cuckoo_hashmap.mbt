/// Cuckoo Hashing — O(1) worst-case lookup hash table.
///
/// Uses two hash functions and two tables. On insertion, if both slots
/// are occupied, evicts an existing element and re-inserts it (cuckoo behavior).
/// If the eviction chain exceeds a threshold, the table is resized.
///
/// ## Performance
///
/// - Lookup: O(1) worst case (check exactly 2 positions)
/// - Insert: O(1) amortized
/// - Delete: O(1) worst case
/// - Space: O(n)
///
/// ## References
///
/// - Pagh, R. and Rodler, F.F. "Cuckoo Hashing." J. Algorithms, 2004.
///
/// `proof-enabled` is `false`.

///|
/// Maximum number of eviction attempts before resizing.
const MAX_KICKS : Int = 500

///|
/// A hash table entry.
struct Entry[V] {
  key : String
  mut value : V
}

///|
/// Cuckoo hash map with String keys.
pub struct CuckooHashMap[V] {
  priv mut table1 : Array[Entry[V]?]
  priv mut table2 : Array[Entry[V]?]
  priv mut capacity : Int
  priv mut size : Int
}

///|
/// Create a new cuckoo hash map with initial capacity.
pub fn[V] new(capacity : Int) -> CuckooHashMap[V] {
  let cap = if capacity < 16 { 16 } else { next_power_of_2(capacity) }
  {
    table1: Array::make(cap, None),
    table2: Array::make(cap, None),
    capacity: cap,
    size: 0,
  }
}

///|
/// Find the next power of 2 >= n.
fn next_power_of_2(n : Int) -> Int {
  let mut p = 1
  while p < n {
    p = p << 1
  }
  p
}

///|
/// Hash function 1.
fn hash1(key : String, capacity : Int) -> Int {
  let mut hash = 0
  for ch in key {
    hash = hash * 31 + ch.to_int()
  }
  let h = if hash < 0 { -hash } else { hash }
  h % capacity
}

///|
/// Hash function 2.
fn hash2(key : String, capacity : Int) -> Int {
  let mut hash = 0
  for ch in key {
    hash = hash * 37 + ch.to_int()
  }
  let h = if hash < 0 { -hash } else { hash }
  (h.to_int64() * 2654435761L % capacity.to_int64()).to_int()
}

///|
/// Insert a key-value pair.
pub fn[V] insert(map : CuckooHashMap[V], key : String, value : V) -> Unit {
  // Check if key already exists
  let i1 = hash1(key, map.capacity)
  match map.table1[i1] {
    Some(e) =>
      if e.key == key {
        e.value = value
        return
      }
    None => ()
  }
  let i2 = hash2(key, map.capacity)
  match map.table2[i2] {
    Some(e) =>
      if e.key == key {
        e.value = value
        return
      }
    None => ()
  }
  // Need to insert new entry
  if map.size >= map.capacity {
    resize(map)
  }
  let mut cur_key = key
  let mut cur_val = value
  for kick = 0; kick < MAX_KICKS; kick = kick + 1 {
    let pos1 = hash1(cur_key, map.capacity)
    match map.table1[pos1] {
      None => {
        map.table1[pos1] = Some({ key: cur_key, value: cur_val, })
        map.size = map.size + 1
        return
      }
      Some(existing) => {
        // Evict
        map.table1[pos1] = Some({ key: cur_key, value: cur_val, })
        cur_key = existing.key
        cur_val = existing.value
      }
    }
    let pos2 = hash2(cur_key, map.capacity)
    match map.table2[pos2] {
      None => {
        map.table2[pos2] = Some({ key: cur_key, value: cur_val, })
        map.size = map.size + 1
        return
      }
      Some(existing) => {
        map.table2[pos2] = Some({ key: cur_key, value: cur_val, })
        cur_key = existing.key
        cur_val = existing.value
      }
    }
  }
  // Too many kicks, resize and retry
  resize(map)
  insert(map, cur_key, cur_val)
}

///|
/// Resize the hash table (double capacity and rehash all entries).
fn[V] resize(map : CuckooHashMap[V]) -> Unit {
  let old_t1 = map.table1
  let old_t2 = map.table2
  let old_cap = map.capacity
  map.capacity = old_cap * 2
  map.table1 = Array::make(map.capacity, None)
  map.table2 = Array::make(map.capacity, None)
  map.size = 0
  for i = 0; i < old_cap; i = i + 1 {
    match old_t1[i] {
      None => ()
      Some(e) => insert(map, e.key, e.value)
    }
    match old_t2[i] {
      None => ()
      Some(e) => insert(map, e.key, e.value)
    }
  }
}

///|
/// Search for a key. Returns Some(value) or None.
pub fn[V] search(map : CuckooHashMap[V], key : String) -> V? {
  let i1 = hash1(key, map.capacity)
  match map.table1[i1] {
    Some(e) => if e.key == key { return Some(e.value) }
    None => ()
  }
  let i2 = hash2(key, map.capacity)
  match map.table2[i2] {
    Some(e) => if e.key == key { return Some(e.value) }
    None => ()
  }
  None
}

///|
/// Delete a key. Returns true if the key was found and removed.
pub fn[V] delete(map : CuckooHashMap[V], key : String) -> Bool {
  let i1 = hash1(key, map.capacity)
  match map.table1[i1] {
    Some(e) =>
      if e.key == key {
        map.table1[i1] = None
        map.size = map.size - 1
        return true
      }
    None => ()
  }
  let i2 = hash2(key, map.capacity)
  match map.table2[i2] {
    Some(e) =>
      if e.key == key {
        map.table2[i2] = None
        map.size = map.size - 1
        return true
      }
    None => ()
  }
  false
}

///|
/// Get the number of elements.
pub fn[V] size(map : CuckooHashMap[V]) -> Int {
  map.size
}

///|
test "cuckoo_hashmap: insert and search" {
  let m : CuckooHashMap[Int] = new(16)
  insert(m, "one", 1)
  insert(m, "two", 2)
  insert(m, "three", 3)
  assert_eq(search(m, "one"), Some(1))
  assert_eq(search(m, "two"), Some(2))
  assert_eq(search(m, "three"), Some(3))
  assert_eq(search(m, "four"), None)
}

///|
test "cuckoo_hashmap: update existing" {
  let m : CuckooHashMap[Int] = new(16)
  insert(m, "key", 100)
  insert(m, "key", 200)
  assert_eq(search(m, "key"), Some(200))
  assert_eq(size(m), 1)
}

///|
test "cuckoo_hashmap: delete" {
  let m : CuckooHashMap[String] = new(16)
  insert(m, "a", "apple")
  insert(m, "b", "banana")
  assert_true(delete(m, "a"))
  assert_eq(search(m, "a"), None)
  assert_eq(search(m, "b"), Some("banana"))
  assert_false(delete(m, "c"))
}

///|
test "cuckoo_hashmap: many insertions" {
  let m : CuckooHashMap[Int] = new(16)
  for i = 0; i < 100; i = i + 1 {
    insert(m, "key" + i.to_string(), i)
  }
  for i = 0; i < 100; i = i + 1 {
    assert_eq(search(m, "key" + i.to_string()), Some(i))
  }
  assert_eq(size(m), 100)
}
