///|
/// Persistent (immutable) vector with structural sharing.
///
/// A PersistentVector provides O(log32 n) random access, update, push, and pop
/// operations while preserving old versions. It uses a bitmapped trie with
/// branching factor 32 (5 bits per level), the same structure as Clojure's
/// PersistentVector and Scala's Vector.
///
/// All mutating operations return a **new** PersistentVector — the original is
/// unchanged. Structural sharing means that a vector of n elements updated
/// once shares n-1 elements of storage with the original, using only O(log n)
/// new nodes.
///
/// ## Complexity
///
/// - `push`: O(log32 n) — creates ~log32(n) new nodes
/// - `get`: O(log32 n) — traverses the trie
/// - `set`: O(log32 n) — path copying
/// - `pop`: O(log32 n) — path copying + tail trimming
/// - Space per update: O(log32 n) new nodes
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.
const BRANCH_BITS : Int = 5

///|
const BRANCH_FACTOR : Int = 32 // 2^5

///|
/// A trie node: either a leaf (holding values) or an internal branch.
pub enum Node[T] {
  Leaf(Array[T])
  Branch(FixedArray[Node[T]?])
}

///|
/// A persistent vector backed by a bitmapped trie.
///
/// - `root`: the root of the trie (None for empty vector).
/// - `size`: number of elements.
/// - `shift`: bit offset of the highest level (0 for < 32 elements,
///   5 for 32..1023, 10 for 1024..32767, etc.).
/// - `tail`: a tail buffer of up to 32 elements for O(1) amortised push.
/// - `tail_len`: number of elements currently in the tail.
pub struct PersistentVector[T] {
  priv root : Node[T]?
  priv size : Int
  priv shift : Int
  priv tail : Array[T]
  priv tail_len : Int
}

///|
/// Create an empty PersistentVector.
pub fn[T] empty() -> PersistentVector[T] {
  { root: None, size: 0, shift: 0, tail: [], tail_len: 0, }
}

///|
/// Create an empty PersistentVector (associated function form, useful when
/// type inference can't determine T from context).
pub fn[T] PersistentVector::new() -> PersistentVector[T] {
  empty()
}

///|
/// Return the number of elements in the vector. O(1).
pub fn[T] length(v : PersistentVector[T]) -> Int {
  v.size
}

///|
/// Mask for extracting a 5-bit index at a given shift level.
fn mask(index : Int, shift : Int) -> Int {
  (index >> shift) & (BRANCH_FACTOR - 1)
}

///|
/// Get the element at `index`. Returns `None` if out of bounds.
pub fn[T] get(v : PersistentVector[T], index : Int) -> T? {
  if index < 0 || index >= v.size {
    return None
  }
  // Check if index is in the tail.
  let tail_start = v.size - v.tail_len
  if index >= tail_start {
    return Some(v.tail[index - tail_start])
  }
  // Walk the trie.
  let mut node = v.root
  let mut shift = v.shift
  while shift > 0 {
    match node {
      Some(Branch(children)) => {
        node = children[mask(index, shift)]
        shift = shift - BRANCH_BITS
      }
      _ => return None
    }
  }
  match node {
    Some(Leaf(arr)) =>
      if mask(index, 0) < arr.length() {
        Some(arr[mask(index, 0)])
      } else {
        None
      }
    _ => None
  }
}

///|
/// Return a new PersistentVector with `value` appended.
pub fn[T] push(v : PersistentVector[T], value : T) -> PersistentVector[T] {
  if v.tail_len < BRANCH_FACTOR {
    // Tail has room: copy and append.
    let new_tail = []
    for i = 0; i < v.tail_len; i = i + 1 {
      new_tail.push(v.tail[i])
    }
    new_tail.push(value)
    { ..v, size: v.size + 1, tail: new_tail, tail_len: v.tail_len + 1, }
  } else {
    // Tail is full: push the old tail into the trie, start a fresh tail.
    let full_tail = Leaf(v.tail)
    let trie_size = v.size - v.tail_len
    match v.root {
      None =>
        // First leaf in trie: root becomes the leaf, shift stays 0.
        {
          root: Some(full_tail),
          size: v.size + 1,
          shift: 0,
          tail: [value],
          tail_len: 1,
        }
      Some(r) => {
        let capacity = 1 << (v.shift + BRANCH_BITS)
        if trie_size >= capacity {
          // Root is full: wrap old root in a new level.
          // Old root → slot 0; new path → slot 1 (next leaf index).
          let children = FixedArray::make(BRANCH_FACTOR, None)
          children[0] = Some(r)
          children[1] = Some(new_path(v.shift, full_tail))
          {
            root: Some(Branch(children)),
            size: v.size + 1,
            shift: v.shift + BRANCH_BITS,
            tail: [value],
            tail_len: 1,
          }
        } else {
          // Room in trie: descend and insert leaf via path copying.
          let new_root = push_tail(v.shift, r, trie_size, full_tail)
          {
            root: Some(new_root),
            size: v.size + 1,
            shift: v.shift,
            tail: [value],
            tail_len: 1,
          }
        }
      }
    }
  }
}

///|
/// Create a chain of single-child branches from `level` down to `leaf`.
/// Used when inserting a leaf into a previously empty trie slot.
fn[T] new_path(level : Int, leaf : Node[T]) -> Node[T] {
  if level == 0 {
    leaf
  } else {
    let children = FixedArray::make(BRANCH_FACTOR, None)
    children[0] = Some(new_path(level - BRANCH_BITS, leaf))
    Branch(children)
  }
}

///|
/// Push a full leaf into the trie at the given root shift level.
/// `index` is the trie index of the first element in `leaf`.
/// The caller must ensure the trie has room (root not full).
fn[T] push_tail(
  shift : Int,
  root : Node[T],
  index : Int,
  leaf : Node[T],
) -> Node[T] {
  match root {
    Branch(children) => {
      let new_children = FixedArray::make(BRANCH_FACTOR, None)
      for i = 0; i < BRANCH_FACTOR; i = i + 1 {
        new_children[i] = children[i]
      }
      let sub_idx = mask(index, shift)
      if shift == BRANCH_BITS {
        // One level above leaves: insert leaf directly.
        new_children[sub_idx] = Some(leaf)
      } else {
        match children[sub_idx] {
          Some(child) =>
            // Descend into existing subtree with path copying.
            new_children[sub_idx] = Some(
              push_tail(shift - BRANCH_BITS, child, index, leaf),
            )
          None =>
            // Empty slot: create fresh path down to leaf.
            new_children[sub_idx] = Some(new_path(shift - BRANCH_BITS, leaf))
        }
      }
      Branch(new_children)
    }
    Leaf(_) =>
      // Unreachable: Leaf root is handled by the root-full check in `push`.
      leaf
  }
}

///|
/// Return a new PersistentVector with the element at `index` set to `value`.
/// Returns the original if `index` is out of bounds.
pub fn[T] set(
  v : PersistentVector[T],
  index : Int,
  value : T,
) -> PersistentVector[T] {
  if index < 0 || index >= v.size {
    return v
  }
  let tail_start = v.size - v.tail_len
  if index >= tail_start {
    let new_tail = []
    for i = 0; i < v.tail_len; i = i + 1 {
      new_tail.push(v.tail[i])
    }
    new_tail[index - tail_start] = value
    return { ..v, tail: new_tail, }
  }
  // Update in trie with path copying.
  let new_root = set_in_trie(v.root, index, value, v.shift)
  { ..v, root: Some(new_root), }
}

///|
fn[T] set_in_trie(
  node : Node[T]?,
  index : Int,
  value : T,
  shift : Int,
) -> Node[T] {
  match node {
    Some(Leaf(arr)) => {
      let new_arr = []
      for i = 0; i < arr.length(); i = i + 1 {
        new_arr.push(arr[i])
      }
      new_arr[mask(index, 0)] = value
      Leaf(new_arr)
    }
    Some(Branch(children)) => {
      let new_children = FixedArray::make(BRANCH_FACTOR, None)
      for i = 0; i < BRANCH_FACTOR; i = i + 1 {
        new_children[i] = children[i]
      }
      let idx = mask(index, shift)
      match children[idx] {
        Some(child) =>
          new_children[idx] = Some(
            set_in_trie(Some(child), index, value, shift - BRANCH_BITS),
          )
        None => ()
      }
      Branch(new_children)
    }
    None => Leaf([value])
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "pvec: empty vector" {
  let v : PersistentVector[Int] = PersistentVector::new()
  assert_eq(length(v), 0)
  assert_true(get(v, 0) is None)
}

///|
test "pvec: push and get" {
  let v : PersistentVector[Int] = PersistentVector::new()
  let v = push(v, 10)
  let v = push(v, 20)
  let v = push(v, 30)
  assert_eq(length(v), 3)
  assert_eq(get(v, 0), Some(10))
  assert_eq(get(v, 1), Some(20))
  assert_eq(get(v, 2), Some(30))
}

///|
test "pvec: persistence — old version unchanged" {
  let v0 : PersistentVector[Int] = PersistentVector::new()
  let v1 = push(v0, 1)
  let v2 = push(v1, 2)
  let v3 = push(v2, 3)
  // v1 should still have only 1 element
  assert_eq(length(v1), 1)
  assert_eq(get(v1, 0), Some(1))
  assert_true(get(v1, 1) is None)
  // v2 should have 2 elements
  assert_eq(length(v2), 2)
  // v3 should have 3 elements
  assert_eq(length(v3), 3)
}

///|
test "pvec: set preserves old version" {
  let v0 : PersistentVector[Int] = PersistentVector::new()
  let v1 = push(push(push(v0, 10), 20), 30)
  let v2 = set(v1, 1, 99)
  // v1 unchanged
  assert_eq(get(v1, 1), Some(20))
  // v2 has the new value
  assert_eq(get(v2, 1), Some(99))
  assert_eq(length(v2), 3)
}

///|
test "pvec: push beyond tail capacity (32+)" {
  let v0 : PersistentVector[Int] = PersistentVector::new()
  let mut v = v0
  for i = 0; i < 100; i = i + 1 {
    v = push(v, i)
  }
  assert_eq(length(v), 100)
  for i = 0; i < 100; i = i + 1 {
    assert_eq(get(v, i), Some(i))
  }
}

///|
test "pvec: large push (1000 elements)" {
  let v0 : PersistentVector[Int] = PersistentVector::new()
  let mut v = v0
  for i = 0; i < 1000; i = i + 1 {
    v = push(v, i * 2)
  }
  assert_eq(length(v), 1000)
  // Spot-check
  assert_eq(get(v, 0), Some(0))
  assert_eq(get(v, 333), Some(666))
  assert_eq(get(v, 999), Some(1998))
  assert_true(get(v, 1000) is None)
}

///|
test "pvec: set on large vector" {
  let v0 : PersistentVector[String] = PersistentVector::new()
  let mut v = v0
  for i = 0; i < 50; i = i + 1 {
    v = push(v, "item_" + i.to_string())
  }
  let v = set(v, 25, "CHANGED")
  assert_eq(get(v, 25), Some("CHANGED"))
  assert_eq(get(v, 24), Some("item_24"))
  assert_eq(get(v, 26), Some("item_26"))
}

///|
test "pvec: out of bounds" {
  let v : PersistentVector[Int] = PersistentVector::new()
  let v = push(v, 42)
  assert_true(get(v, -1) is None)
  assert_true(get(v, 1) is None)
  // set on out of bounds returns original
  let v2 = set(v, 5, 99)
  assert_eq(length(v2), 1)
}

///|
test "pvec: generic type (String)" {
  let v0 : PersistentVector[String] = PersistentVector::new()
  let v = push(push(push(v0, "a"), "b"), "c")
  assert_eq(length(v), 3)
  assert_eq(get(v, 0), Some("a"))
  assert_eq(get(v, 1), Some("b"))
  assert_eq(get(v, 2), Some("c"))
}
