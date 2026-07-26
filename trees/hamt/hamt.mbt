///|
/// Hash Array Mapped Trie (HAMT) — persistent key-value store.
///
/// A HAMT is a persistent (immutable) variant of a hash trie that uses
/// **bitmap indexing** to compress sparse nodes. Each internal node has at
/// most 32 children (for a 5-bit fan-out), but instead of a fixed 32-element
/// array, it stores a 32-bit bitmap where bit `i` is set iff child `i`
/// exists. The children are packed contiguously, saving memory.
///
/// ## Properties
///
/// - **Persistent**: insert and delete return new trees without modifying
///   the old one (structural sharing via path copying).
/// - **O(log₃₂ n)** expected depth — for n < 10⁹, depth ≤ 6.
/// - **Memory efficient**: sparse nodes use only the space they need.
/// - **Collision-safe**: true hash collisions (two different keys with the
///   same hash) are stored in a `Collision` node that linearly scans keys.
///
/// ## Algorithm
///
/// The hash is consumed 5 bits at a time (32-way branching). At each level:
/// - If the bit for the current 5-bit slice is set in the bitmap, the child
///   exists at position `popcount(bitmap & mask)` in the packed array.
/// - Otherwise, a new child is inserted by setting the bit and splicing the
///   new entry into the packed array.
///
/// When two different keys produce the same hash, a `Collision` node stores
/// all entries with that hash. Lookup does a linear scan within the
/// collision node — acceptable because true collisions are extremely rare
/// for a good 32-bit hash.
///
/// ## Complexity
///
/// - Insert: O(log₃₂ n) = O(1) amortised (depth ≤ 6 for n < 10⁹).
/// - Lookup: O(log₃₂ n).
/// - Delete: O(log₃₂ n).
/// - Space: O(n).
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const BITS : Int = 5

///|
const MASK : Int = 31 // 2^BITS - 1

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

///|
/// A persistent HAMT mapping `String` keys to `Int` values.
///
/// All operations return new trees; the original is never modified.
pub enum HAMT {
  Empty
  Leaf(String, Int)
  Node(Int, Array[HAMT]) // bitmap, packed children
  Collision(Int, Array[HAMT]) // hash, list of leaves with identical hash
}

// ---------------------------------------------------------------------------
// Hash function
// ---------------------------------------------------------------------------

///|
/// FNV-1a hash for strings, returning a 31-bit non-negative hash.
fn hash_str(s : String) -> Int {
  // FNV offset basis 2166136261 as signed 32-bit: -2128831035
  let mut h = -2128831035
  for i = 0; i < s.length(); i = i + 1 {
    h = h ^ s[i].to_int()
    h = h * 16777619 // FNV prime
  }
  // Use unsigned right shift to keep the hash non-negative (31 bits).
  (h.reinterpret_as_uint() >> 1).reinterpret_as_int()
}

///|
/// Extract the 5-bit slice at `level` (0 = least significant).
fn hash_slice(hash : Int, level : Int) -> Int {
  (hash >> (level * BITS)) & MASK
}

///|
/// Population count of the low `bits` bits of `x`.
fn popcount(x : Int) -> Int {
  let mut count = 0
  let mut v = x
  while v != 0 {
    count = count + (v & 1)
    v = v >> 1
  }
  count
}

// ---------------------------------------------------------------------------
// Core operations (persistent — return new trees)
// ---------------------------------------------------------------------------

///|
/// Insert `(key, value)` into the HAMT. Returns a new HAMT; the original
/// is unchanged.
pub fn insert(h : HAMT, key : String, value : Int) -> HAMT {
  insert_rec(h, key, value, hash_str(key), 0)
}

///|
fn insert_rec(
  h : HAMT,
  key : String,
  value : Int,
  hash : Int,
  level : Int,
) -> HAMT {
  match h {
    HAMT::Empty => HAMT::Leaf(key, value)
    HAMT::Leaf(k, v) =>
      if k == key {
        HAMT::Leaf(key, value) // replace
      } else {
        let k_hash = hash_str(k)
        if k_hash == hash {
          // True hash collision: both keys hash to the same value.
          // Store them in a Collision node.
          HAMT::Collision(hash, [HAMT::Leaf(k, v), HAMT::Leaf(key, value)])
        } else {
          // Different hashes: create a node and insert both leaves.
          split_two_leaves(k, v, k_hash, key, value, hash, level)
        }
      }
    HAMT::Collision(h0, leaves) =>
      if h0 == hash {
        // Same hash: check if key already exists; replace or append.
        let new_leaves : Array[HAMT] = []
        let mut found = false
        for i = 0; i < leaves.length(); i = i + 1 {
          match leaves[i] {
            HAMT::Leaf(k, _) =>
              if k == key {
                new_leaves.push(HAMT::Leaf(key, value))
                found = true
              } else {
                new_leaves.push(leaves[i])
              }
            _ => new_leaves.push(leaves[i])
          }
        }
        if !found {
          new_leaves.push(HAMT::Leaf(key, value))
        }
        HAMT::Collision(h0, new_leaves)
      } else {
        // Different hash from the collision node's hash: shouldn't happen
        // in normal operation (collision nodes are only reached when the
        // hash matches). Treat as a node split.
        split_collision_and_leaf(h0, leaves, key, value, hash, level)
      }
    HAMT::Node(bitmap, children) => {
      let idx = hash_slice(hash, level)
      let bit = 1 << idx
      if (bitmap & bit) != 0 {
        // Child exists at packed position.
        let pos = popcount(bitmap & (bit - 1))
        let child = children[pos]
        let new_child = insert_rec(child, key, value, hash, level + 1)
        let new_children : Array[HAMT] = []
        for i = 0; i < children.length(); i = i + 1 {
          if i == pos {
            new_children.push(new_child)
          } else {
            new_children.push(children[i])
          }
        }
        HAMT::Node(bitmap, new_children)
      } else {
        // Insert new child: set bit and splice into packed array.
        let pos = popcount(bitmap & (bit - 1))
        let new_bitmap = bitmap | bit
        let new_children : Array[HAMT] = []
        for i = 0; i < pos; i = i + 1 {
          new_children.push(children[i])
        }
        new_children.push(HAMT::Leaf(key, value))
        for i = pos; i < children.length(); i = i + 1 {
          new_children.push(children[i])
        }
        HAMT::Node(new_bitmap, new_children)
      }
    }
  }
}

///|
/// Split two leaves with different hashes into a node structure.
/// Recurses until the hash slices diverge, then creates a Node with both.
fn split_two_leaves(
  k1 : String,
  v1 : Int,
  h1 : Int,
  k2 : String,
  v2 : Int,
  h2 : Int,
  level : Int,
) -> HAMT {
  let s1 = hash_slice(h1, level)
  let s2 = hash_slice(h2, level)
  if s1 != s2 {
    // Slices differ at this level: create a Node with both leaves.
    let bit1 = 1 << s1
    let bit2 = 1 << s2
    let bitmap = bit1 | bit2
    let children : Array[HAMT] = []
    // Pack children in order of increasing slice index.
    if s1 < s2 {
      children.push(HAMT::Leaf(k1, v1))
      children.push(HAMT::Leaf(k2, v2))
    } else {
      children.push(HAMT::Leaf(k2, v2))
      children.push(HAMT::Leaf(k1, v1))
    }
    HAMT::Node(bitmap, children)
  } else {
    // Same slice at this level: recurse deeper.
    let child = split_two_leaves(k1, v1, h1, k2, v2, h2, level + 1)
    let bit = 1 << s1
    HAMT::Node(bit, [child])
  }
}

///|
/// Split a collision node and a new leaf into a node structure.
/// Used when a new key's hash differs from a collision node's hash.
fn split_collision_and_leaf(
  coll_hash : Int,
  coll_leaves : Array[HAMT],
  key : String,
  value : Int,
  hash : Int,
  level : Int,
) -> HAMT {
  let s1 = hash_slice(coll_hash, level)
  let s2 = hash_slice(hash, level)
  if s1 != s2 {
    let bit1 = 1 << s1
    let bit2 = 1 << s2
    let bitmap = bit1 | bit2
    let children : Array[HAMT] = []
    if s1 < s2 {
      children.push(HAMT::Collision(coll_hash, coll_leaves))
      children.push(HAMT::Leaf(key, value))
    } else {
      children.push(HAMT::Leaf(key, value))
      children.push(HAMT::Collision(coll_hash, coll_leaves))
    }
    HAMT::Node(bitmap, children)
  } else {
    let child = split_collision_and_leaf(
      coll_hash,
      coll_leaves,
      key,
      value,
      hash,
      level + 1,
    )
    let bit = 1 << s1
    HAMT::Node(bit, [child])
  }
}

///|
/// Look up `key` in the HAMT. Returns `Some(value)` or `None`.
pub fn get(h : HAMT, key : String) -> Int? {
  get_rec(h, key, hash_str(key), 0)
}

///|
fn get_rec(h : HAMT, key : String, hash : Int, level : Int) -> Int? {
  match h {
    HAMT::Empty => None
    HAMT::Leaf(k, v) => if k == key { Some(v) } else { None }
    HAMT::Collision(h0, leaves) =>
      if h0 == hash {
        let mut result = None
        for i = 0; i < leaves.length(); i = i + 1 {
          match leaves[i] {
            HAMT::Leaf(k, v) => if k == key { result = Some(v) }
            _ => ()
          }
        }
        result
      } else {
        None
      }
    HAMT::Node(bitmap, children) => {
      let idx = hash_slice(hash, level)
      let bit = 1 << idx
      if (bitmap & bit) == 0 {
        None
      } else {
        let pos = popcount(bitmap & (bit - 1))
        get_rec(children[pos], key, hash, level + 1)
      }
    }
  }
}

///|
/// Delete `key` from the HAMT. Returns a new HAMT.
pub fn delete(h : HAMT, key : String) -> HAMT {
  delete_rec(h, key, hash_str(key), 0)
}

///|
fn delete_rec(h : HAMT, key : String, hash : Int, level : Int) -> HAMT {
  match h {
    HAMT::Empty => HAMT::Empty
    HAMT::Leaf(k, _) => if k == key { HAMT::Empty } else { h }
    HAMT::Collision(h0, leaves) =>
      if h0 == hash {
        let new_leaves : Array[HAMT] = []
        for i = 0; i < leaves.length(); i = i + 1 {
          match leaves[i] {
            HAMT::Leaf(k, _) => if k != key { new_leaves.push(leaves[i]) }
            _ => new_leaves.push(leaves[i])
          }
        }
        if new_leaves.length() == 0 {
          HAMT::Empty
        } else if new_leaves.length() == 1 {
          new_leaves[0]
        } else {
          HAMT::Collision(h0, new_leaves)
        }
      } else {
        h
      }
    HAMT::Node(bitmap, children) => {
      let idx = hash_slice(hash, level)
      let bit = 1 << idx
      if (bitmap & bit) == 0 {
        h
      } else {
        let pos = popcount(bitmap & (bit - 1))
        let new_child = delete_rec(children[pos], key, hash, level + 1)
        match new_child {
          HAMT::Empty => {
            // Remove this child entirely.
            let new_bitmap = bitmap ^ bit
            if new_bitmap == 0 {
              HAMT::Empty
            } else {
              let new_children : Array[HAMT] = []
              for i = 0; i < children.length(); i = i + 1 {
                if i != pos {
                  new_children.push(children[i])
                }
              }
              // If only one child remains and it's a leaf, collapse.
              if new_children.length() == 1 {
                match new_children[0] {
                  HAMT::Leaf(k, v) => HAMT::Leaf(k, v)
                  _ => HAMT::Node(new_bitmap, new_children)
                }
              } else {
                HAMT::Node(new_bitmap, new_children)
              }
            }
          }
          _ => {
            let new_children : Array[HAMT] = []
            for i = 0; i < children.length(); i = i + 1 {
              if i == pos {
                new_children.push(new_child)
              } else {
                new_children.push(children[i])
              }
            }
            HAMT::Node(bitmap, new_children)
          }
        }
      }
    }
  }
}

///|
/// Create an empty HAMT.
pub fn empty() -> HAMT {
  HAMT::Empty
}

///|
/// Count the number of key-value pairs in the HAMT.
pub fn size(h : HAMT) -> Int {
  match h {
    HAMT::Empty => 0
    HAMT::Leaf(_, _) => 1
    HAMT::Collision(_, leaves) => {
      let mut total = 0
      for i = 0; i < leaves.length(); i = i + 1 {
        total = total + size(leaves[i])
      }
      total
    }
    HAMT::Node(_, children) => {
      let mut total = 0
      for i = 0; i < children.length(); i = i + 1 {
        total = total + size(children[i])
      }
      total
    }
  }
}

///|
/// Check if the HAMT is empty.
pub fn is_empty(h : HAMT) -> Bool {
  match h {
    HAMT::Empty => true
    _ => false
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "hamt: empty" {
  let h = empty()
  assert_true(is_empty(h))
  assert_eq(size(h), 0)
  assert_true(get(h, "foo") is None)
}

///|
test "hamt: single insert and get" {
  let h = insert(empty(), "hello", 42)
  assert_eq(get(h, "hello"), Some(42))
  assert_eq(size(h), 1)
  assert_false(is_empty(h))
}

///|
test "hamt: multiple inserts" {
  let h0 = empty()
  let h1 = insert(h0, "a", 1)
  let h2 = insert(h1, "b", 2)
  let h3 = insert(h2, "c", 3)
  assert_eq(get(h3, "a"), Some(1))
  assert_eq(get(h3, "b"), Some(2))
  assert_eq(get(h3, "c"), Some(3))
  assert_eq(get(h3, "d"), None)
  assert_eq(size(h3), 3)
  // Persistence: old versions unchanged.
  assert_eq(get(h1, "b"), None)
  assert_eq(get(h2, "c"), None)
}

///|
test "hamt: overwrite existing key" {
  let h0 = insert(empty(), "key", 10)
  let h1 = insert(h0, "key", 20)
  assert_eq(get(h1, "key"), Some(20))
  assert_eq(get(h0, "key"), Some(10)) // old version
  assert_eq(size(h1), 1)
}

///|
test "hamt: delete" {
  let h0 = insert(empty(), "a", 1)
  let h1 = insert(h0, "b", 2)
  let h2 = insert(h1, "c", 3)
  let h3 = delete(h2, "b")
  assert_eq(get(h3, "b"), None)
  assert_eq(get(h3, "a"), Some(1))
  assert_eq(get(h3, "c"), Some(3))
  assert_eq(size(h3), 2)
  // Persistence: h2 still has "b"
  assert_eq(get(h2, "b"), Some(2))
}

///|
test "hamt: delete non-existent key" {
  let h0 = insert(empty(), "a", 1)
  let h1 = delete(h0, "b")
  assert_eq(get(h1, "a"), Some(1))
  assert_eq(size(h1), 1)
}

///|
test "hamt: delete all" {
  let h0 = insert(empty(), "a", 1)
  let h1 = insert(h0, "b", 2)
  let h2 = delete(h1, "a")
  let h3 = delete(h2, "b")
  assert_true(is_empty(h3))
}

///|
test "hamt: stress test 1000 inserts" {
  let mut h = empty()
  for i = 0; i < 1000; i = i + 1 {
    h = insert(h, "key_" + i.to_string(), i)
  }
  assert_eq(size(h), 1000)
  // Verify all entries.
  for i = 0; i < 1000; i = i + 1 {
    assert_eq(get(h, "key_" + i.to_string()), Some(i))
  }
  // Delete half.
  for i = 0; i < 500; i = i + 1 {
    h = delete(h, "key_" + i.to_string())
  }
  assert_eq(size(h), 500)
  for i = 0; i < 500; i = i + 1 {
    assert_true(get(h, "key_" + i.to_string()) is None)
  }
  for i = 500; i < 1000; i = i + 1 {
    assert_eq(get(h, "key_" + i.to_string()), Some(i))
  }
}

///|
test "hamt: hash collision handling" {
  // Insert keys that may hash to the same value; the HAMT handles this
  // by falling back to key comparison at the leaf level.
  let h0 = insert(empty(), "aa", 1)
  let h1 = insert(h0, "ab", 2)
  let h2 = insert(h1, "ba", 3)
  let h3 = insert(h2, "bb", 4)
  assert_eq(get(h3, "aa"), Some(1))
  assert_eq(get(h3, "ab"), Some(2))
  assert_eq(get(h3, "ba"), Some(3))
  assert_eq(get(h3, "bb"), Some(4))
  assert_eq(size(h3), 4)
}

///|
test "hamt: persistence — all versions valid" {
  let h0 = insert(empty(), "x", 1)
  let h1 = insert(h0, "y", 2)
  let h2 = insert(h1, "z", 3)
  // All three versions must remain valid.
  assert_eq(get(h0, "x"), Some(1))
  assert_true(get(h0, "y") is None)
  assert_eq(get(h1, "x"), Some(1))
  assert_eq(get(h1, "y"), Some(2))
  assert_true(get(h1, "z") is None)
  assert_eq(get(h2, "x"), Some(1))
  assert_eq(get(h2, "y"), Some(2))
  assert_eq(get(h2, "z"), Some(3))
}

///|
test "hamt: delete and reinsert" {
  let h0 = insert(empty(), "a", 1)
  let h1 = delete(h0, "a")
  assert_true(is_empty(h1))
  let h2 = insert(h1, "a", 2)
  assert_eq(get(h2, "a"), Some(2))
  assert_eq(size(h2), 1)
}
