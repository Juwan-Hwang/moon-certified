/// Skip List: a probabilistic data structure for ordered key-value storage.
///
/// A skip list layered sorted linked lists on top of one another. The bottom
/// level (level 0) is a singly linked list of every entry in ascending key
/// order. Each higher level is a "express lane" that skips over roughly half
/// of the nodes of the level below it. Searching starts at the top level and
/// drops down one level whenever the next node would overshoot the target,
/// yielding O(log n) expected search/insert/delete time.
///
/// The number of levels a node participates in is decided probabilistically at
/// insertion time: each node is promoted to the next level with probability
/// 0.5 (a geometric distribution with mean 2). The maximum level is capped at
/// 32, which is sufficient for 2^32 elements.
///
/// Randomness is provided by a tiny inline LCG (linear congruential generator)
/// — `state = state * 1103515245 + 12345 (mod 2^31)` — seeded from a counter
/// stored in the struct. No standard-library random source is required, which
/// keeps the package self-contained and deterministic across runs.
///
/// Complexity (expected, with high probability):
/// - `insert`  — O(log n)
/// - `search`  — O(log n)
/// - `delete`  — O(log n)
/// - `size`    — O(1)        (cached count)
/// - `inorder` — O(n)        (walks the level-0 linked list)
///
/// Limitations:
/// - Keys and values are both `Int`; the structure is not generic.
/// - The LCG is not cryptographically secure; it exists only to spread node
///   heights. Correctness does not depend on the quality of the randomness —
///   a pathologically bad RNG only degrades performance toward O(n), never
///   breaks the sorted-list invariant.
/// - Not thread-safe; all mutation goes through `&self`.
///
/// Not formally verified. Correctness is ensured by the comprehensive test
/// suite below, including large pseudo-random insertions and full deletion.

/// The maximum number of levels any node may occupy.
const MAX_LEVEL : Int = 32

/// A single skip-list node.
///
/// `forward[i]` is the next node at level `i`, or `None` at the end of that
/// level. A node occupies levels `0 .. forward.length() - 1`; the array length
/// is exactly the node's height. The sentinel `header` node always carries a
/// full `MAX_LEVEL`-slot `forward` array so that every level has an entry point.
pub struct SkipNode {
  key : Int
  mut value : Int
  forward : FixedArray[SkipNode?]
}

/// An ordered map from `Int` keys to `Int` values, implemented as a skip list.
///
/// `header` is a sentinel whose `forward` array links the head of every level.
/// `level` tracks the highest level currently in use (always >= 1). `count`
/// caches the number of live entries so `size` is O(1). `rng` holds the LCG
/// state used to draw random node heights.
pub struct SkipList {
  header : SkipNode
  mut level : Int
  mut count : Int
  mut rng : Int
}

/// Create an empty skip list.
pub fn SkipList::new() -> SkipList {
  {
    header: { key: 0, value: 0, forward: FixedArray::make(MAX_LEVEL, None) },
    level: 1,
    count: 0,
    // A non-zero seed; any fixed value makes the sequence deterministic.
    rng: 0x12345678,
  }
}

/// Advance the LCG and draw a random node height in `[1, MAX_LEVEL]`.
///
/// Each bit of the random word independently promotes the height by one with
/// probability 0.5, producing a geometric distribution with mean ~2. The
/// lowest bit of this LCG has period 2, so we start consuming from bit 1 for
/// slightly better spread; this is a quality tweak, not a correctness concern.
fn SkipList::rand_level(self : SkipList) -> Int {
  self.rng = (self.rng * 1103515245 + 12345) & 0x7FFFFFFF
  let mut lvl = 1
  let mut bits = self.rng >> 1
  while lvl < MAX_LEVEL && (bits & 1) == 1 {
    lvl = lvl + 1
    bits = bits >> 1
  }
  lvl
}

/// Walk down from the top level, recording the predecessor of `key` at every
/// level into `update`. On return, `update[i]` is the rightmost node at level
/// `i` whose successor has a key `>= key`, and the function also returns the
/// level-0 successor (the first node with key `>= key`, or `None`).
fn SkipList::find_path(
  self : SkipList,
  key : Int,
  update : FixedArray[SkipNode],
) -> SkipNode? {
  let mut current = self.header
  for i = self.level - 1; i >= 0; i = i - 1 {
    let mut advancing = true
    while advancing {
      match current.forward[i] {
        Some(node) =>
          if node.key < key {
            current = node
          } else {
            advancing = false
          }
        None => advancing = false
      }
    }
    update[i] = current
  }
  current.forward[0]
}

/// Insert or update a key-value pair.
///
/// If `key` already exists, its value is replaced and the count is unchanged.
/// Otherwise a new node is created at a random height and spliced into every
/// level it spans. Expected O(log n).
pub fn SkipList::insert(self : SkipList, key : Int, value : Int) -> Unit {
  let update = FixedArray::make(MAX_LEVEL, self.header)
  match self.find_path(key, update) {
    Some(node) =>
      if node.key == key {
        // Duplicate key: update the stored value in place.
        node.value = value
        return
      }
    None => ()
  }
  // New entry. Draw a height and splice the node in.
  let new_level = self.rand_level()
  let new_node : SkipNode = { key, value, forward: FixedArray::make(new_level, None) }
  if new_level > self.level {
    // Levels above the current top link directly from the header.
    for i = self.level; i < new_level; i = i + 1 {
      update[i] = self.header
    }
    self.level = new_level
  }
  for i = 0; i < new_level; i = i + 1 {
    new_node.forward[i] = update[i].forward[i]
    update[i].forward[i] = Some(new_node)
  }
  self.count = self.count + 1
}

/// Look up the value associated with `key`. Returns `Some(v)` if present,
/// `None` otherwise. Expected O(log n).
///
/// Unlike `insert`/`delete`, a pure lookup needs no predecessor path, so it
/// walks the list directly without allocating an `update` array — only the
/// traversal cursor is touched.
pub fn SkipList::search(self : SkipList, key : Int) -> Int? {
  let mut current = self.header
  for i = self.level - 1; i >= 0; i = i - 1 {
    let mut advancing = true
    while advancing {
      match current.forward[i] {
        Some(node) =>
          if node.key < key {
            current = node
          } else {
            advancing = false
          }
        None => advancing = false
      }
    }
  }
  // After dropping to level 0, `current.forward[0]` is the first node with
  // key >= `key`; it is a hit iff that key is exactly `key`.
  match current.forward[0] {
    Some(node) => if node.key == key { Some(node.value) } else { None }
    None => None
  }
}

/// Remove the entry for `key`. Returns `true` if the key was present and
/// removed, `false` if it was not found. Expected O(log n).
pub fn SkipList::delete(self : SkipList, key : Int) -> Bool {
  let update = FixedArray::make(MAX_LEVEL, self.header)
  match self.find_path(key, update) {
    None => false
    Some(node) =>
      if node.key != key {
        false
      } else {
        // Unlink `node` from every level it occupies. By the skip-list
        // invariant, `update[i].forward[i]` is `node` for every level `i`
        // that `node` spans, so re-pointing past `node` there is correct.
        let node_level = node.forward.length()
        for i = 0; i < node_level; i = i + 1 {
          update[i].forward[i] = node.forward[i]
        }
        self.count = self.count - 1
        // Shrink empty top levels so future searches start as high as possible.
        while self.level > 1 {
          match self.header.forward[self.level - 1] {
            None => self.level = self.level - 1
            Some(_) => break
          }
        }
        true
      }
  }
}

/// Number of entries currently stored. O(1).
pub fn SkipList::size(self : SkipList) -> Int {
  self.count
}

/// Return all entries in ascending key order as a `FixedArray[(Int, Int)]`.
/// The level-0 linked list is already sorted, so this is a single linear walk.
/// O(n).
pub fn SkipList::inorder(self : SkipList) -> FixedArray[(Int, Int)] {
  let result : Array[(Int, Int)] = []
  let mut current = self.header.forward[0]
  let mut go = true
  while go {
    match current {
      Some(node) => {
        result.push((node.key, node.value))
        current = node.forward[0]
      }
      None => go = false
    }
  }
  FixedArray::from_array(result.view())
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "skiplist: basic insert and search" {
  let sl = SkipList::new()
  sl.insert(5, 50)
  sl.insert(3, 30)
  sl.insert(7, 70)
  assert_eq(sl.search(5), Some(50))
  assert_eq(sl.search(3), Some(30))
  assert_eq(sl.search(7), Some(70))
  assert_true(sl.search(1) is None)
  assert_true(sl.search(9) is None)
  assert_eq(sl.size(), 3)
}

test "skiplist: delete" {
  let sl = SkipList::new()
  sl.insert(5, 50)
  sl.insert(3, 30)
  sl.insert(7, 70)
  assert_eq(sl.delete(7), true)
  assert_true(sl.search(7) is None)
  assert_eq(sl.search(5), Some(50))
  assert_eq(sl.search(3), Some(30))
  assert_eq(sl.size(), 2)
  // Deleting again returns false.
  assert_eq(sl.delete(7), false)
  assert_eq(sl.size(), 2)
}

test "skiplist: duplicate key update" {
  let sl = SkipList::new()
  sl.insert(10, 100)
  sl.insert(10, 200)
  sl.insert(10, 300)
  assert_eq(sl.search(10), Some(300))
  assert_eq(sl.size(), 1)
  // Inorder reflects the latest value, with a single entry.
  let arr = sl.inorder()
  assert_eq(arr.length(), 1)
  assert_eq(arr[0], (10, 300))
}

test "skiplist: sequential insert" {
  let sl = SkipList::new()
  for k = 1; k <= 50; k = k + 1 {
    sl.insert(k, k * k)
  }
  assert_eq(sl.size(), 50)
  for k = 1; k <= 50; k = k + 1 {
    assert_eq(sl.search(k), Some(k * k))
  }
  assert_true(sl.search(0) is None)
  assert_true(sl.search(51) is None)
}

test "skiplist: reverse insert" {
  let sl = SkipList::new()
  for k = 50; k >= 1; k = k - 1 {
    sl.insert(k, k * k)
  }
  assert_eq(sl.size(), 50)
  for k = 1; k <= 50; k = k + 1 {
    assert_eq(sl.search(k), Some(k * k))
  }
}

test "skiplist: large random insert" {
  let sl = SkipList::new()
  let n = 200
  // A pseudo-random permutation of 0 .. n-1.
  for k = 0; k < n; k = k + 1 {
    let key = (k * 37 + 11) % n
    sl.insert(key, key * 2)
  }
  assert_eq(sl.size(), n)
  // Every key 0 .. n-1 must be present with its value.
  for k = 0; k < n; k = k + 1 {
    assert_eq(sl.search(k), Some(k * 2))
  }
  // Inorder must be strictly sorted by key.
  let arr = sl.inorder()
  assert_eq(arr.length(), n)
  for k = 0; k < n; k = k + 1 {
    assert_eq(arr[k].0, k)
    assert_eq(arr[k].1, k * 2)
  }
}

test "skiplist: size tracking" {
  let sl = SkipList::new()
  assert_eq(sl.size(), 0)
  sl.insert(1, 1)
  assert_eq(sl.size(), 1)
  sl.insert(2, 2)
  sl.insert(3, 3)
  assert_eq(sl.size(), 3)
  sl.insert(2, 22) // update, no size change
  assert_eq(sl.size(), 3)
  assert_eq(sl.delete(2), true)
  assert_eq(sl.size(), 2)
  assert_eq(sl.delete(2), false) // already gone
  assert_eq(sl.size(), 2)
}

test "skiplist: inorder is sorted" {
  let sl = SkipList::new()
  let vals = [5, 3, 7, 1, 4, 6, 8, 2]
  for k = 0; k < 8; k = k + 1 {
    sl.insert(vals[k], vals[k])
  }
  let arr = sl.inorder()
  assert_eq(arr.length(), 8)
  for k = 0; k < 8; k = k + 1 {
    assert_eq(arr[k].0, k + 1)
  }
  // Explicitly verify strict ascending order of keys.
  for k = 1; k < 8; k = k + 1 {
    assert_true(arr[k - 1].0 < arr[k].0)
  }
}

test "skiplist: delete non-existent key" {
  let sl = SkipList::new()
  for k = 1; k <= 10; k = k + 1 {
    sl.insert(k, k)
  }
  assert_eq(sl.delete(99), false)
  assert_eq(sl.delete(0), false)
  assert_eq(sl.size(), 10)
  // Tree is unchanged.
  for k = 1; k <= 10; k = k + 1 {
    assert_eq(sl.search(k), Some(k))
  }
}

test "skiplist: delete all elements" {
  let sl = SkipList::new()
  for k = 1; k <= 20; k = k + 1 {
    sl.insert(k, k)
  }
  assert_eq(sl.size(), 20)
  // Delete in a different order than insertion.
  for k = 20; k >= 1; k = k - 1 {
    assert_eq(sl.delete(k), true)
    assert_eq(sl.size(), k - 1)
    assert_true(sl.search(k) is None)
    // Remaining smaller keys are still present.
    for j = 1; j < k; j = j + 1 {
      assert_eq(sl.search(j), Some(j))
    }
  }
  assert_eq(sl.size(), 0)
  assert_eq(sl.inorder().length(), 0)
}

test "skiplist: empty tree operations" {
  let sl = SkipList::new()
  assert_eq(sl.size(), 0)
  assert_true(sl.search(1) is None)
  assert_eq(sl.delete(1), false)
  assert_eq(sl.inorder().length(), 0)
}

test "skiplist: reinsert after deletion" {
  let sl = SkipList::new()
  sl.insert(7, 70)
  assert_eq(sl.delete(7), true)
  assert_true(sl.search(7) is None)
  sl.insert(7, 777)
  assert_eq(sl.search(7), Some(777))
  assert_eq(sl.size(), 1)
}

test "skiplist: interleave insert and delete" {
  let sl = SkipList::new()
  sl.insert(5, 50)
  sl.insert(3, 30)
  sl.insert(7, 70)
  assert_eq(sl.delete(3), true)
  sl.insert(1, 10)
  sl.insert(9, 90)
  assert_eq(sl.delete(7), true)
  assert_eq(sl.delete(5), true)
  assert_eq(sl.size(), 2)
  assert_eq(sl.search(1), Some(10))
  assert_eq(sl.search(9), Some(90))
  assert_true(sl.search(5) is None)
  // Inorder still sorted after churn.
  let arr = sl.inorder()
  assert_eq(arr[0].0, 1)
  assert_eq(arr[1].0, 9)
}
