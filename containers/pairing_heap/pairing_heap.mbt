/// Pairing Heap — a simple, self-adjusting mergeable priority queue.
///
/// A **pairing heap** is a tree-based heap where each node stores a value and
/// a list of children. The heap property requires every node's value ≤ its
/// children's values (min-heap). Pairing heaps are prized for their simplicity
/// and excellent practical performance.
///
/// ## Operations
///
/// The core operation is **meld** (merge two trees): compare the two roots,
/// attach the larger as the leftmost child of the smaller. This is O(1).
///
/// `extract_min` removes the root and reassembles the children via the
/// **two-pass merge** (pairing):
/// 1. **Left-to-right pass**: meld children in pairs (child[0] with child[1],
///    child[2] with child[3], …).
/// 2. **Right-to-left pass**: meld the resulting trees from right to left.
///
/// ## Amortized Complexity
///
/// | Operation     | Amortized   | Notes |
/// |---------------|-------------|-------|
/// | `insert`      | O(1)        | meld with root |
/// | `find_min`    | O(1)        | root value |
/// | `extract_min` | O(log n)    | two-pass merge |
/// | `merge`       | O(1)        | meld roots |
///
/// The exact theoretical complexity of pairing heaps was an open problem for
/// decades. It is now known that `extract_min` is O(log n) amortized, but
/// `decrease_key` is not O(1) as originally conjectured (Fredman, 1999).
/// In practice, pairing heaps often outperform Fibonacci heaps due to lower
/// constant factors.
///
/// ## References
///
/// - Fredman, M. L., Sedgewick, R., Sleator, D. D., & Tarjan, R. E. (1986).
///   "The pairing heap: a new form of self-adjusting heap."
///   *Algorithmica*, 1(1), 111–129.
/// - Fredman, M. L. (1999). "On the efficiency of pairing heaps and related
///   data structures." *JACM*, 46(4), 473–501.
/// - Weiss, M. A. (2007). *Data Structures and Algorithm Analysis in C++*,
///   3rd ed., Section 11.4.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Node type
// ---------------------------------------------------------------------------

///|
/// A pairing heap tree node.
///
/// `children` is an unordered list of child nodes. The first child is the
/// most recently melded (leftmost), but the order has no semantic significance.
priv struct PairingNode[T] {
  val : T
  children : Array[PairingNode[T]]
}

// ---------------------------------------------------------------------------
// Heap type
// ---------------------------------------------------------------------------

///|
/// A pairing heap (min-heap) with a user-supplied comparator.
///
/// `compare(a, b)` returns `< 0` when `a` should be extracted before `b`
/// (min-heap), `0` when equal, `> 0` otherwise.
pub struct PairingHeap[T] {
  priv mut root : PairingNode[T]?
  priv compare : (T, T) -> Int
  priv mut count : Int
}

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

///|
/// Create an empty pairing heap with the given comparator.
pub fn[T] new(compare : (T, T) -> Int) -> PairingHeap[T] {
  { root: None, compare, count: 0, }
}

// ---------------------------------------------------------------------------
// Queries
// ---------------------------------------------------------------------------

///|
/// Return the number of elements. O(1).
pub fn[T] size(heap : PairingHeap[T]) -> Int {
  heap.count
}

///|
/// Check whether the heap is empty. O(1).
pub fn[T] is_empty(heap : PairingHeap[T]) -> Bool {
  heap.count == 0
}

///|
/// Return the minimum element without removing it. O(1).
///
/// Returns `None` if the heap is empty.
pub fn[T] find_min(heap : PairingHeap[T]) -> T? {
  match heap.root {
    None => None
    Some(node) => Some(node.val)
  }
}

// ---------------------------------------------------------------------------
// Internal: meld two trees
// ---------------------------------------------------------------------------

///|
/// Meld two trees: the root with the larger value becomes a child of the
/// root with the smaller value. O(1).
fn[T] meld(
  a : PairingNode[T],
  b : PairingNode[T],
  compare : (T, T) -> Int,
) -> PairingNode[T] {
  if compare(a.val, b.val) <= 0 {
    a.children.push(b)
    a
  } else {
    b.children.push(a)
    b
  }
}

// ---------------------------------------------------------------------------
// Internal: two-pass merge of children
// ---------------------------------------------------------------------------

///|
/// Perform the two-pass merge on a list of child nodes.
///
/// 1. Left-to-right: meld children in pairs.
/// 2. Right-to-left: meld the results.
fn[T] merge_pairs(
  children : Array[PairingNode[T]],
  compare : (T, T) -> Int,
) -> PairingNode[T]? {
  let n = children.length()
  if n == 0 {
    return None
  }
  if n == 1 {
    return Some(children[0])
  }
  // First pass: left-to-right pairing.
  let paired : Array[PairingNode[T]] = []
  let mut i = 0
  while i + 1 < n {
    paired.push(meld(children[i], children[i + 1], compare))
    i = i + 2
  }
  // If odd number of children, the last one carries over unpaired.
  if i < n {
    paired.push(children[i])
  }
  // Second pass: right-to-left meld.
  let mut result = paired[paired.length() - 1]
  for k = paired.length() - 2; k >= 0; k = k - 1 {
    result = meld(paired[k], result, compare)
  }
  Some(result)
}

// ---------------------------------------------------------------------------
// Mutations
// ---------------------------------------------------------------------------

///|
/// Insert a value into the heap. O(1) amortized.
pub fn[T] insert(heap : PairingHeap[T], val : T) -> Unit {
  let node : PairingNode[T] = { val, children: [], }
  match heap.root {
    None => heap.root = Some(node)
    Some(r) => heap.root = Some(meld(r, node, heap.compare))
  }
  heap.count = heap.count + 1
}

///|
/// Remove and return the minimum element.
///
/// Returns `None` if the heap is empty.
///
/// Time: O(log n) amortized.
pub fn[T] extract_min(heap : PairingHeap[T]) -> T? {
  match heap.root {
    None => None
    Some(root) => {
      heap.root = merge_pairs(root.children, heap.compare)
      heap.count = heap.count - 1
      Some(root.val)
    }
  }
}

///|
/// Merge another heap into this heap. The other heap is consumed (left empty).
///
/// Time: O(1).
pub fn[T] merge(heap : PairingHeap[T], other : PairingHeap[T]) -> Unit {
  match (heap.root, other.root) {
    (None, None) => ()
    (
      None,
      // heap is empty, take other's root.
      Some(_),
    ) => {
      heap.root = other.root
      heap.count = other.count
      other.root = None
      other.count = 0
    }
    (Some(_), None) => ()
    (
      Some(r1),
      // Both non-empty: meld the roots.
      Some(r2),
    ) => {
      heap.root = Some(meld(r1, r2, heap.compare))
      heap.count = heap.count + other.count
      other.root = None
      other.count = 0
    }
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "pairing_heap: insert and find_min" {
  let h = new(fn(a : Int, b : Int) -> Int { a - b })
  insert(h, 5)
  insert(h, 3)
  insert(h, 8)
  insert(h, 1)
  insert(h, 4)
  assert_eq(size(h), 5)
  assert_eq(find_min(h), Some(1))
}

///|
test "pairing_heap: extract_min" {
  let h = new(fn(a : Int, b : Int) -> Int { a - b })
  insert(h, 5)
  insert(h, 3)
  insert(h, 8)
  insert(h, 1)
  insert(h, 4)
  assert_eq(extract_min(h), Some(1))
  assert_eq(extract_min(h), Some(3))
  assert_eq(extract_min(h), Some(4))
  assert_eq(extract_min(h), Some(5))
  assert_eq(extract_min(h), Some(8))
  assert_eq(extract_min(h), None)
  assert_true(is_empty(h))
}

///|
test "pairing_heap: extract_min on empty" {
  let h = new(fn(a : Int, b : Int) -> Int { a - b })
  assert_eq(extract_min(h), None)
  assert_eq(find_min(h), None)
}

///|
test "pairing_heap: merge two heaps" {
  let h1 = new(fn(a : Int, b : Int) -> Int { a - b })
  let h2 = new(fn(a : Int, b : Int) -> Int { a - b })
  insert(h1, 1)
  insert(h1, 3)
  insert(h1, 5)
  insert(h2, 2)
  insert(h2, 4)
  insert(h2, 6)
  merge(h1, h2)
  assert_eq(size(h1), 6)
  assert_eq(size(h2), 0)
  for i = 1; i <= 6; i = i + 1 {
    assert_eq(extract_min(h1), Some(i))
  }
}

///|
test "pairing_heap: duplicate keys" {
  let h = new(fn(a : Int, b : Int) -> Int { a - b })
  insert(h, 5)
  insert(h, 5)
  insert(h, 5)
  assert_eq(size(h), 3)
  assert_eq(extract_min(h), Some(5))
  assert_eq(extract_min(h), Some(5))
  assert_eq(extract_min(h), Some(5))
  assert_eq(extract_min(h), None)
}

///|
test "pairing_heap: max-heap via reversed comparator" {
  let h = new(fn(a : Int, b : Int) -> Int { b - a })
  insert(h, 5)
  insert(h, 3)
  insert(h, 8)
  insert(h, 1)
  assert_eq(find_min(h), Some(8))
  assert_eq(extract_min(h), Some(8))
  assert_eq(extract_min(h), Some(5))
  assert_eq(extract_min(h), Some(3))
  assert_eq(extract_min(h), Some(1))
}

///|
test "pairing_heap: large sequential insert and extract" {
  let h = new(fn(a : Int, b : Int) -> Int { a - b })
  let n = 200
  for i = 0; i < n; i = i + 1 {
    insert(h, i)
  }
  assert_eq(size(h), n)
  for i = 0; i < n; i = i + 1 {
    assert_eq(extract_min(h), Some(i))
  }
  assert_true(is_empty(h))
}

///|
test "pairing_heap: reverse order insert" {
  let h = new(fn(a : Int, b : Int) -> Int { a - b })
  let n = 100
  for i = n - 1; i >= 0; i = i - 1 {
    insert(h, i)
  }
  for i = 0; i < n; i = i + 1 {
    assert_eq(extract_min(h), Some(i))
  }
}

///|
test "pairing_heap: interleave insert and extract" {
  let h = new(fn(a : Int, b : Int) -> Int { a - b })
  insert(h, 10)
  insert(h, 5)
  assert_eq(extract_min(h), Some(5))
  insert(h, 3)
  insert(h, 7)
  assert_eq(extract_min(h), Some(3))
  assert_eq(extract_min(h), Some(7))
  insert(h, 1)
  assert_eq(extract_min(h), Some(1))
  assert_eq(extract_min(h), Some(10))
  assert_eq(extract_min(h), None)
}

///|
test "pairing_heap: merge with empty" {
  let h1 = new(fn(a : Int, b : Int) -> Int { a - b })
  let h2 = new(fn(a : Int, b : Int) -> Int { a - b })
  insert(h1, 1)
  insert(h1, 3)
  merge(h1, h2)
  assert_eq(size(h1), 2)
  assert_eq(extract_min(h1), Some(1))
  assert_eq(extract_min(h1), Some(3))
}

///|
test "pairing_heap: merge empty into non-empty" {
  let h1 = new(fn(a : Int, b : Int) -> Int { a - b })
  let h2 = new(fn(a : Int, b : Int) -> Int { a - b })
  insert(h2, 1)
  insert(h2, 3)
  merge(h1, h2)
  assert_eq(size(h1), 2)
  assert_eq(extract_min(h1), Some(1))
  assert_eq(extract_min(h1), Some(3))
}

///|
test "pairing_heap: string elements" {
  let h = new(fn(a : String, b : String) -> Int { a.compare(b) })
  insert(h, "banana")
  insert(h, "apple")
  insert(h, "cherry")
  assert_eq(find_min(h), Some("apple"))
  assert_eq(extract_min(h), Some("apple"))
  assert_eq(extract_min(h), Some("banana"))
  assert_eq(extract_min(h), Some("cherry"))
}

///|
test "pairing_heap: stress test with merge" {
  let h1 = new(fn(a : Int, b : Int) -> Int { a - b })
  let h2 = new(fn(a : Int, b : Int) -> Int { a - b })
  for i = 0; i < 50; i = i + 1 {
    insert(h1, i * 2)
    insert(h2, i * 2 + 1)
  }
  merge(h1, h2)
  assert_eq(size(h1), 100)
  for i = 0; i < 100; i = i + 1 {
    assert_eq(extract_min(h1), Some(i))
  }
}

///|
test "pairing_heap: single element" {
  let h = new(fn(a : Int, b : Int) -> Int { a - b })
  insert(h, 42)
  assert_eq(size(h), 1)
  assert_eq(find_min(h), Some(42))
  assert_eq(extract_min(h), Some(42))
  assert_eq(extract_min(h), None)
  assert_true(is_empty(h))
}

///|
test "pairing_heap: merge two empty heaps" {
  let h1 = new(fn(a : Int, b : Int) -> Int { a - b })
  let h2 = new(fn(a : Int, b : Int) -> Int { a - b })
  merge(h1, h2)
  assert_eq(size(h1), 0)
  assert_eq(size(h2), 0)
  assert_eq(extract_min(h1), None)
}

///|
test "pairing_heap: random-ish pattern" {
  // Insert in a non-trivial pattern to test tree structure.
  let h = new(fn(a : Int, b : Int) -> Int { a - b })
  let vals = [42, 17, 99, 3, 55, 1, 88, 23, 66, 12]
  for i = 0; i < vals.length(); i = i + 1 {
    insert(h, vals[i])
  }
  // Extract should yield sorted order.
  let sorted = [1, 3, 12, 17, 23, 42, 55, 66, 88, 99]
  for i = 0; i < sorted.length(); i = i + 1 {
    assert_eq(extract_min(h), Some(sorted[i]))
  }
  assert_true(is_empty(h))
}
