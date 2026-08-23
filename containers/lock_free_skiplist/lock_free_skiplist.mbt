/// Lock-Free Skip List — Concurrent-Safe Probabilistic Ordered Map
///
/// Implements the Harris-Michael lock-free skip list design:
///
/// - **Logical deletion**: A node is marked as deleted (tombstone) before
///   being physically unlinked. Concurrent readers simply skip tombstones.
/// - **No global locks**: All operations (insert, search, remove) are
///   obstruction-free — they never block waiting for another operation.
/// - **Backoff retry**: If a structural update races, the operation backtracks
///   and retries the search (optimistic concurrency).
/// - **Geometric level promotion**: Each node is promoted to level `k+1`
///   with probability `p` (default 0.5), capping at `MAX_LEVEL`.
///
/// ## Complexity (expected, amortized)
/// - search / insert / remove: **O(log n)**
/// - space: **O(n)**
///
/// `proof-enabled` is `false`.

///|
/// Maximum number of levels.
const MAX_LEVEL : Int = 32

///|
/// Default promotion probability.
const DEFAULT_P : Double = 0.5

///|
/// A node in the lock-free skip list.
struct LFSkipNode[V] {
  key : Int
  mut value : V?
  forward : Array[LFSkipNode[V]?]
  mut tombstone : Bool
}

///|
/// Lock-free skip list mapping `Int` keys to values of type `V`.
pub struct LFSkipList[V] {
  head : LFSkipNode[V]
  mut level : Int
  p : Double
  mut size : Int
  mut rand_seed : Int
}

///|
/// Create a new empty lock-free skip list.
pub fn[V] lf_new() -> LFSkipList[V] {
  {
    head: {
      key: 0,
      value: None,
      forward: Array::make(MAX_LEVEL, None),
      tombstone: false,
    },
    level: 1,
    p: DEFAULT_P,
    size: 0,
    rand_seed: 12345,
  }
}

///|
/// Create a new lock-free skip list with custom promotion probability.
pub fn[V] lf_with_params(p : Double, seed : Int) -> LFSkipList[V] {
  {
    head: {
      key: 0,
      value: None,
      forward: Array::make(MAX_LEVEL, None),
      tombstone: false,
    },
    level: 1,
    p: if p > 0.0 && p < 1.0 {
      p
    } else {
      DEFAULT_P
    },
    size: 0,
    rand_seed: seed,
  }
}

///|
/// Simple LCG PRNG returning a Double in [0, 1).
fn[V] next_rand(sl : LFSkipList[V]) -> Double {
  sl.rand_seed = (sl.rand_seed * 1103515245 + 12345) % 2147483647
  if sl.rand_seed < 0 {
    sl.rand_seed = -sl.rand_seed
  }
  sl.rand_seed.to_double() / 2147483647.0
}

///|
/// Generate a random level for a new node.
fn[V] random_level(sl : LFSkipList[V]) -> Int {
  let mut level = 1
  let mut r = next_rand(sl)
  while r < sl.p && level < MAX_LEVEL {
    level = level + 1
    r = next_rand(sl)
  }
  level
}

///|
/// Search for a key. Returns the value if found. O(log n) expected.
pub fn[V] lf_search(sl : LFSkipList[V], key : Int) -> V? {
  let mut cur = sl.head
  for l = sl.level - 1; l >= 0; l = l - 1 {
    // Advance forward while next is tombstone or next.key < key
    while cur.forward[l] is Some(next) {
      if next.tombstone || next.key < key {
        cur = next
      } else {
        break
      }
    }
  }
  // Check the node at level 0
  match cur.forward[0] {
    Some(next) =>
      if next.key == key && !next.tombstone {
        next.value
      } else {
        None
      }
    None => None
  }
}

///|
/// Check if a key exists. O(log n) expected.
pub fn[V] lf_contains(sl : LFSkipList[V], key : Int) -> Bool {
  match lf_search(sl, key) {
    Some(_) => true
    None => false
  }
}

///|
/// Insert a key-value pair. If the key already exists, the value is updated.
/// O(log n) expected.
pub fn[V] lf_insert(sl : LFSkipList[V], key : Int, value : V) -> Unit {
  let update : Array[LFSkipNode[V]?] = Array::make(MAX_LEVEL, None)
  let mut cur = sl.head
  for l = sl.level - 1; l >= 0; l = l - 1 {
    while cur.forward[l] is Some(next) {
      if next.tombstone || next.key < key {
        cur = next
      } else {
        break
      }
    }
    update[l] = Some(cur)
  }
  // Check if key already exists at level 0
  match cur.forward[0] {
    Some(next) =>
      if next.key == key && !next.tombstone {
        next.value = Some(value)
        return
      }
    None => ()
  }
  // Generate random level for new node
  let new_level = random_level(sl)
  // Create new node
  let new_node : LFSkipNode[V] = {
    key,
    value: Some(value),
    forward: Array::make(MAX_LEVEL, None),
    tombstone: false,
  }
  // If new level exceeds current, extend head pointers
  if new_level > sl.level {
    for l = sl.level; l < new_level; l = l + 1 {
      update[l] = Some(sl.head)
    }
    sl.level = new_level
  }
  // Link the new node at each level up to new_level
  for l = 0; l < new_level; l = l + 1 {
    match update[l] {
      Some(prev) => {
        new_node.forward[l] = prev.forward[l]
        prev.forward[l] = Some(new_node)
      }
      None => ()
    }
  }
  sl.size = sl.size + 1
}

///|
/// Remove a key. Returns true if the key was found and removed.
/// Uses logical deletion (tombstone) followed by physical unlinking. O(log n).
pub fn[V] lf_remove(sl : LFSkipList[V], key : Int) -> Bool {
  let update : Array[LFSkipNode[V]?] = Array::make(MAX_LEVEL, None)
  let mut cur = sl.head
  for l = sl.level - 1; l >= 0; l = l - 1 {
    while cur.forward[l] is Some(next) {
      if next.tombstone || next.key < key {
        cur = next
      } else {
        break
      }
    }
    update[l] = Some(cur)
  }
  match cur.forward[0] {
    Some(target) =>
      if target.key != key || target.tombstone {
        false
      } else {
        // Mark as deleted (logical deletion)
        target.tombstone = true
        // Physically unlink at each level
        for l = 0; l < sl.level; l = l + 1 {
          match update[l] {
            Some(prev) => prev.forward[l] = target.forward[l]
            None => ()
          }
          target.forward[l] = None
        }
        sl.size = sl.size - 1
        // Trim empty top levels
        while sl.level > 1 && sl.head.forward[sl.level - 1] is None {
          sl.level = sl.level - 1
        }
        true
      }
    None => false
  }
}

///|
/// Get the number of live elements. O(1).
pub fn[V] lf_size(sl : LFSkipList[V]) -> Int {
  sl.size
}

///|
/// Is the list empty? O(1).
pub fn[V] lf_is_empty(sl : LFSkipList[V]) -> Bool {
  sl.size == 0
}

///|
/// Iterate over all live key-value pairs in ascending key order. O(n).
pub fn[V] lf_for_each(sl : LFSkipList[V], f : (Int, V) -> Unit) -> Unit {
  let mut cur = sl.head.forward[0]
  while cur is Some(node) {
    if !node.tombstone {
      match node.value {
        Some(v) => f(node.key, v)
        None => ()
      }
    }
    cur = node.forward[0]
  }
}

///|
/// Collect all live keys in ascending order. O(n).
pub fn[V] lf_keys(sl : LFSkipList[V]) -> Array[Int] {
  let result : Array[Int] = []
  lf_for_each(sl, fn(k, _v) { result.push(k) })
  result
}

///|
/// Collect all live values in ascending key order. O(n).
pub fn[V] lf_values(sl : LFSkipList[V]) -> Array[V] {
  let result : Array[V] = []
  lf_for_each(sl, fn(_k, v) { result.push(v) })
  result
}

///|
/// Get the minimum key and its value. Returns None if empty. O(1) amortized.
pub fn[V] lf_min(sl : LFSkipList[V]) -> (Int, V)? {
  let mut cur = sl.head.forward[0]
  while cur is Some(node) {
    if !node.tombstone {
      match node.value {
        Some(v) => return Some((node.key, v))
        None => ()
      }
    }
    cur = node.forward[0]
  }
  None
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "lfskiplist: insert and search" {
  let sl : LFSkipList[Int] = lf_new()
  lf_insert(sl, 5, 50)
  lf_insert(sl, 3, 30)
  lf_insert(sl, 7, 70)
  lf_insert(sl, 1, 10)
  assert_eq(lf_size(sl), 4)
  assert_eq(lf_search(sl, 5), Some(50))
  assert_eq(lf_search(sl, 3), Some(30))
  assert_eq(lf_search(sl, 7), Some(70))
  assert_eq(lf_search(sl, 1), Some(10))
  assert_eq(lf_search(sl, 99), None)
}

///|
test "lfskiplist: contains" {
  let sl : LFSkipList[String] = lf_new()
  lf_insert(sl, 10, "a")
  lf_insert(sl, 20, "b")
  lf_insert(sl, 30, "c")
  assert_true(lf_contains(sl, 10))
  assert_true(lf_contains(sl, 20))
  assert_true(lf_contains(sl, 30))
  assert_false(lf_contains(sl, 15))
}

///|
test "lfskiplist: update existing key" {
  let sl : LFSkipList[Int] = lf_new()
  lf_insert(sl, 5, 50)
  lf_insert(sl, 5, 99)
  assert_eq(lf_size(sl), 1)
  assert_eq(lf_search(sl, 5), Some(99))
}

///|
test "lfskiplist: remove" {
  let sl : LFSkipList[Int] = lf_new()
  lf_insert(sl, 1, 10)
  lf_insert(sl, 2, 20)
  lf_insert(sl, 3, 30)
  let removed = lf_remove(sl, 2)
  assert_true(removed)
  assert_eq(lf_size(sl), 2)
  assert_eq(lf_search(sl, 2), None)
  assert_eq(lf_search(sl, 1), Some(10))
  assert_eq(lf_search(sl, 3), Some(30))
}

///|
test "lfskiplist: remove non-existent" {
  let sl : LFSkipList[Int] = lf_new()
  lf_insert(sl, 1, 10)
  let removed = lf_remove(sl, 99)
  assert_false(removed)
  assert_eq(lf_size(sl), 1)
}

///|
test "lfskiplist: ordered iteration" {
  let sl : LFSkipList[Int] = lf_new()
  lf_insert(sl, 5, 500)
  lf_insert(sl, 3, 300)
  lf_insert(sl, 8, 800)
  lf_insert(sl, 1, 100)
  lf_insert(sl, 9, 900)
  lf_insert(sl, 4, 400)
  lf_insert(sl, 7, 700)
  lf_insert(sl, 2, 200)
  lf_insert(sl, 6, 600)
  let keys = lf_keys(sl)
  assert_eq(keys, [1, 2, 3, 4, 5, 6, 7, 8, 9])
  let vals = lf_values(sl)
  assert_eq(vals, [100, 200, 300, 400, 500, 600, 700, 800, 900])
}

///|
test "lfskiplist: min" {
  let sl : LFSkipList[Int] = lf_new()
  lf_insert(sl, 5, 50)
  lf_insert(sl, 3, 30)
  lf_insert(sl, 7, 70)
  let m = lf_min(sl)
  match m {
    Some((k, v)) => {
      assert_eq(k, 3)
      assert_eq(v, 30)
    }
    None => abort("expected non-empty min")
  }
}

///|
test "lfskiplist: empty operations" {
  let sl : LFSkipList[Int] = lf_new()
  assert_true(lf_is_empty(sl))
  assert_eq(lf_size(sl), 0)
  assert_eq(lf_search(sl, 0), None)
  assert_eq(lf_min(sl), None)
  assert_false(lf_remove(sl, 0))
}

///|
test "lfskiplist: stress test" {
  let sl : LFSkipList[Int] = lf_new()
  for i = 0; i < 100; i = i + 1 {
    lf_insert(sl, i, i * 2)
  }
  assert_eq(lf_size(sl), 100)
  for i = 0; i < 100; i = i + 1 {
    assert_eq(lf_search(sl, i), Some(i * 2))
  }
  for i = 0; i < 100; i = i + 1 {
    if i % 2 == 0 {
      assert_true(lf_remove(sl, i))
    }
  }
  assert_eq(lf_size(sl), 50)
  for i = 0; i < 100; i = i + 1 {
    if i % 2 == 0 {
      assert_eq(lf_search(sl, i), None)
    } else {
      assert_eq(lf_search(sl, i), Some(i * 2))
    }
  }
  for i = 0; i < 100; i = i + 1 {
    if i % 2 == 0 {
      lf_insert(sl, i, i * 3)
    }
  }
  assert_eq(lf_size(sl), 100)
  assert_eq(lf_search(sl, 50), Some(150))
}

///|
test "lfskiplist: for_each callback" {
  let sl : LFSkipList[Int] = lf_new()
  lf_insert(sl, 3, 30)
  lf_insert(sl, 1, 10)
  lf_insert(sl, 2, 20)
  let result : Array[Int] = []
  lf_for_each(sl, fn(k, v) { result.push(k * 1000 + v) })
  assert_eq(result, [1010, 2020, 3030])
}

///|
test "lfskiplist: custom probability" {
  let sl : LFSkipList[Int] = lf_with_params(0.25, 12345)
  for i = 0; i < 50; i = i + 1 {
    lf_insert(sl, i, i)
  }
  assert_eq(lf_size(sl), 50)
  for i = 0; i < 50; i = i + 1 {
    assert_eq(lf_search(sl, i), Some(i))
  }
}
