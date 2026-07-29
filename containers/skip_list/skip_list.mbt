/// Skip List — probabilistic ordered data structure.
///
/// A skip list is a linked list with multiple levels of "express lanes"
/// that allow O(log n) average-case search, insertion, and deletion.
/// Each element is promoted to higher levels with probability p (default 0.5).
///
/// ## Design
///
/// Uses a **sentinel header node** (not a data node) whose forward pointers
/// reference the first real node at each level. This is the standard Pugh
/// (1990) design and correctly handles insertion of keys smaller than any
/// existing key.
///
/// ## Performance
///
/// - Search: O(log n) expected
/// - Insert: O(log n) expected
/// - Delete: O(log n) expected
/// - Space: O(n) expected
///
/// ## References
///
/// - Pugh, W. "Skip lists: a probabilistic alternative to balanced trees."
///   Communications of the ACM, 1990.
///
/// `proof-enabled` is `false`.

///|
/// Maximum number of levels in the skip list.
const MAX_LEVEL : Int = 32

///|
/// Default probability for node promotion.
const DEFAULT_P : Double = 0.5

///|
/// A node in the skip list.
struct SkipNode[V] {
  key : Int
  mut value : V? // None for sentinel, Some(v) for data nodes
  forward : Array[SkipNode[V]?]
}

///|
/// A skip list mapping Int keys to values of type V.
///
/// The `head` field is a sentinel node that is always present;
/// it is not counted in `size` and its `key`/`value` are unused.
pub struct SkipList[V] {
  head : SkipNode[V]
  mut level : Int
  p : Double
  mut size : Int
  mut rand_seed : Int
}

///|
/// Create a new empty skip list.
pub fn[V] new() -> SkipList[V] {
  // Sentinel header: forward array has MAX_LEVEL slots, all None.
  // key and value are placeholders (never accessed by callers).
  {
    head: { key: 0, value: None, forward: Array::make(MAX_LEVEL, None) },
    level: 0,
    p: DEFAULT_P,
    size: 0,
    rand_seed: 12345,
  }
}

///|
/// Simple LCG random number generator returning a Double in [0, 1).
fn[V] next_rand(sl : SkipList[V]) -> Double {
  sl.rand_seed = (sl.rand_seed * 1103515245 + 12345) % 2147483647
  if sl.rand_seed < 0 {
    sl.rand_seed = -sl.rand_seed
  }
  sl.rand_seed.to_double() / 2147483647.0
}

///|
/// Generate a random level for a new node.
fn[V] random_level(sl : SkipList[V]) -> Int {
  let mut level = 0
  let mut r = next_rand(sl)
  while r < sl.p && level < MAX_LEVEL - 1 {
    level = level + 1
    r = next_rand(sl)
  }
  level
}

///|
/// Search for a key in the skip list. Returns Some(value) or None.
pub fn[V] search(sl : SkipList[V], key : Int) -> V? {
  let mut current = sl.head
  for i = sl.level; i >= 0; i = i - 1 {
    let mut advance = true
    while advance {
      advance = match current.forward[i] {
        None => false
        Some(next) =>
          if next.key < key {
            current = next
            true
          } else {
            false
          }
      }
    }
  }
  match current.forward[0] {
    None => None
    Some(node) => if node.key == key { node.value } else { None }
  }
}

///|
/// Insert a key-value pair into the skip list.
/// If the key already exists, updates the value.
pub fn[V] insert(sl : SkipList[V], key : Int, value : V) -> Unit {
  let update : Array[SkipNode[V]?] = Array::make(MAX_LEVEL, None)
  let mut current = sl.head
  for i = sl.level; i >= 0; i = i - 1 {
    let mut advance = true
    while advance {
      advance = match current.forward[i] {
        None => false
        Some(next) =>
          if next.key < key {
            current = next
            true
          } else {
            false
          }
      }
    }
    update[i] = Some(current)
  }
  // Check if key already exists — update value in place
  match current.forward[0] {
    Some(node) =>
      if node.key == key {
        node.value = Some(value)
        return
      }
    None => ()
  }
  // Create new node
  let new_level = random_level(sl)
  if new_level > sl.level {
    for i = sl.level + 1; i <= new_level; i = i + 1 {
      update[i] = Some(sl.head)
    }
    sl.level = new_level
  }
  let node : SkipNode[V] = {
    key,
    value: Some(value),
    forward: Array::make(new_level + 1, None),
  }
  for i = 0; i <= new_level; i = i + 1 {
    match update[i] {
      None => ()
      Some(prev) => {
        node.forward[i] = prev.forward[i]
        prev.forward[i] = Some(node)
      }
    }
  }
  sl.size = sl.size + 1
}

///|
/// Delete a key from the skip list.
pub fn[V] delete(sl : SkipList[V], key : Int) -> Unit {
  let update : Array[SkipNode[V]?] = Array::make(MAX_LEVEL, None)
  let mut current = sl.head
  for i = sl.level; i >= 0; i = i - 1 {
    let mut advance = true
    while advance {
      advance = match current.forward[i] {
        None => false
        Some(next) =>
          if next.key < key {
            current = next
            true
          } else {
            false
          }
      }
    }
    update[i] = Some(current)
  }
  match current.forward[0] {
    None => ()
    Some(node) =>
      if node.key == key {
        for i = 0; i <= sl.level; i = i + 1 {
          match update[i] {
            None => ()
            Some(prev) =>
              match prev.forward[i] {
                Some(n) =>
                  if n.key == key {
                    prev.forward[i] = n.forward[i]
                  }
                None => ()
              }
          }
        }
        // Adjust level
        while sl.level > 0 {
          match sl.head.forward[sl.level] {
            None => sl.level = sl.level - 1
            Some(_) => break
          }
        }
        sl.size = sl.size - 1
      }
  }
}

///|
/// Get the number of elements in the skip list.
pub fn[V] size(sl : SkipList[V]) -> Int {
  sl.size
}

///|
/// Get all keys in sorted order.
pub fn[V] keys(sl : SkipList[V]) -> Array[Int] {
  let result : Array[Int] = []
  let mut current = sl.head.forward[0]
  let mut cont = true
  while cont {
    cont = match current {
      None => false
      Some(node) => {
        result.push(node.key)
        current = node.forward[0]
        true
      }
    }
  }
  result
}

///|
test "skip_list: insert and search" {
  let sl : SkipList[Int] = new()
  insert(sl, 3, 30)
  insert(sl, 1, 10)
  insert(sl, 2, 20)
  assert_eq(search(sl, 1), Some(10))
  assert_eq(search(sl, 2), Some(20))
  assert_eq(search(sl, 3), Some(30))
  assert_eq(search(sl, 4), None)
  assert_eq(size(sl), 3)
}

///|
test "skip_list: delete" {
  let sl : SkipList[String] = new()
  insert(sl, 5, "five")
  insert(sl, 3, "three")
  insert(sl, 7, "seven")
  delete(sl, 3)
  assert_eq(search(sl, 3), None)
  assert_eq(search(sl, 5), Some("five"))
  assert_eq(search(sl, 7), Some("seven"))
  assert_eq(size(sl), 2)
}

///|
test "skip_list: update existing key" {
  let sl : SkipList[Int] = new()
  insert(sl, 1, 100)
  insert(sl, 1, 200)
  assert_eq(search(sl, 1), Some(200))
  assert_eq(size(sl), 1)
}

///|
test "skip_list: keys in order" {
  let sl : SkipList[Int] = new()
  insert(sl, 5, 0)
  insert(sl, 1, 0)
  insert(sl, 3, 0)
  insert(sl, 4, 0)
  insert(sl, 2, 0)
  let ks = keys(sl)
  assert_eq(ks, [1, 2, 3, 4, 5])
}
