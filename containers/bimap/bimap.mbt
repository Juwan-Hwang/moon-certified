/// Bidirectional Map (BiMap).
///
/// A bidirectional map that provides O(1) lookup in both directions:
/// key → value and value → key. Each value must be unique (no two keys
/// can map to the same value).
///
/// ## References
///
/// - Common data structure in functional programming and compiler design.
///
/// `proof-enabled` is `false`.

///|
/// A bidirectional map between String keys and String values.
pub struct BiMap {
  priv forward : Map[String, String]
  priv backward : Map[String, String]
}

///|
/// Create a new empty BiMap.
pub fn new() -> BiMap {
  { forward: {}, backward: {} }
}

///|
/// Insert a key-value pair. If either the key or value already exists,
/// the old associations are removed.
pub fn insert(bm : BiMap, key : String, value : String) -> Unit {
  // Remove old forward association
  match bm.forward.get(key) {
    Some(old_val) => bm.backward.remove(old_val)
    None => ()
  }
  // Remove old backward association
  match bm.backward.get(value) {
    Some(old_key) => bm.forward.remove(old_key)
    None => ()
  }
  bm.forward.set(key, value)
  bm.backward.set(value, key)
}

///|
/// Look up a value by key. Returns Some(value) or None.
pub fn get_by_key(bm : BiMap, key : String) -> String? {
  bm.forward.get(key)
}

///|
/// Look up a key by value. Returns Some(key) or None.
pub fn get_by_value(bm : BiMap, value : String) -> String? {
  bm.backward.get(value)
}

///|
/// Remove a key-value pair by key.
pub fn remove_by_key(bm : BiMap, key : String) -> Unit {
  match bm.forward.get(key) {
    Some(val) => {
      bm.forward.remove(key)
      bm.backward.remove(val)
    }
    None => ()
  }
}

///|
/// Remove a key-value pair by value.
pub fn remove_by_value(bm : BiMap, value : String) -> Unit {
  match bm.backward.get(value) {
    Some(key) => {
      bm.backward.remove(value)
      bm.forward.remove(key)
    }
    None => ()
  }
}

///|
/// Get the number of entries.
pub fn size(bm : BiMap) -> Int {
  bm.forward.length()
}

///|
/// Check if a key exists.
pub fn contains_key(bm : BiMap, key : String) -> Bool {
  bm.forward.contains(key)
}

///|
/// Check if a value exists.
pub fn contains_value(bm : BiMap, value : String) -> Bool {
  bm.backward.contains(value)
}

///|
/// Get all keys.
pub fn keys(bm : BiMap) -> Array[String] {
  let result : Array[String] = []
  for key in bm.forward.keys() {
    result.push(key)
  }
  result
}

///|
/// Get all values.
pub fn values(bm : BiMap) -> Array[String] {
  let result : Array[String] = []
  for val in bm.backward.keys() {
    result.push(val)
  }
  result
}

///|
test "bimap: insert and lookup" {
  let bm = new()
  insert(bm, "a", "apple")
  insert(bm, "b", "banana")
  assert_eq(get_by_key(bm, "a"), Some("apple"))
  assert_eq(get_by_value(bm, "banana"), Some("b"))
  assert_eq(get_by_key(bm, "c"), None)
  assert_eq(get_by_value(bm, "cherry"), None)
}

///|
test "bimap: update replaces old" {
  let bm = new()
  insert(bm, "a", "apple")
  insert(bm, "a", "apricot")
  assert_eq(get_by_key(bm, "a"), Some("apricot"))
  assert_false(contains_value(bm, "apple"))
  assert_eq(size(bm), 1)
}

///|
test "bimap: value uniqueness enforced" {
  let bm = new()
  insert(bm, "a", "shared")
  insert(bm, "b", "shared")
  assert_eq(get_by_key(bm, "a"), None)
  assert_eq(get_by_key(bm, "b"), Some("shared"))
  assert_eq(get_by_value(bm, "shared"), Some("b"))
}

///|
test "bimap: remove" {
  let bm = new()
  insert(bm, "x", "xray")
  insert(bm, "y", "yankee")
  remove_by_key(bm, "x")
  assert_false(contains_key(bm, "x"))
  assert_false(contains_value(bm, "xray"))
  assert_eq(size(bm), 1)
  remove_by_value(bm, "yankee")
  assert_eq(size(bm), 0)
}
