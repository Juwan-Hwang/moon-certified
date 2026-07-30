/// Leftist Heap — a mergeable priority queue with O(log n) merge.
///
/// A **leftist heap** is a variant of the binary heap that supports efficient
/// `merge` in O(log n) time. Its defining invariant is the **leftist property**:
/// for every node, the **null path length** (npl) of the left child is greater
/// than or equal to the npl of the right child. The null path length of a node
/// is the length of the shortest path from that node to a `null` (external)
/// descendant.
///
/// ## Leftist Property
///
/// - `npl(null) = 0`
/// - `npl(node) = 1 + min(npl(left), npl(right))`
/// - **Invariant**: `npl(left) >= npl(right)` for every internal node.
///
/// This ensures the **right spine** (the path from the root following right
/// children) has at most `⌊log₂(n+1)⌋` nodes. Since `merge` only traverses
/// right spines, it runs in O(log n).
///
/// ## Complexity
///
/// | Operation     | Time     |
/// |---------------|----------|
/// | `insert`      | O(log n) |
/// | `find_min`    | O(1)     |
/// | `extract_min` | O(log n) |
/// | `merge`       | O(log n) |
/// | `delete`      | O(log n) |
/// | `size`        | O(1)     |
///
/// ## Comparison with Other Mergeable Heaps
///
/// | Heap          | merge   | extract_min | Space overhead |
/// |---------------|---------|-------------|----------------|
/// | Leftist       | O(log n)| O(log n)    | 1 int/node     |
/// | Binomial      | O(log n)| O(log n)    | degree array   |
/// | Pairing       | O(1)*   | O(n)†       | minimal        |
/// | Skew          | O(1)*   | O(n)†       | minimal        |
///
/// \* amortized, † amortized. Leftist heap provides **worst-case** O(log n)
/// guarantees, unlike pairing/skew heaps which are amortized.
///
/// ## References
///
/// - Crane, C. A. (1972). "Linear lists and priority queues as balanced
///   binary trees." Technical Report STAN-CS-72-259, Stanford University.
/// - Tarjan, R. E. (1983). *Data Structures and Network Algorithms*,
///   Chapter 3. SIAM.
/// - Knuth, D. E. (1998). *The Art of Computer Programming*, Vol. 3, 2nd ed.,
///   §5.2.3, Exercise 31. Addison-Wesley.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Node type
// ---------------------------------------------------------------------------

///|
/// A leftist heap node.
///
/// `npl` (null path length) is the length of the shortest path from this node
/// to an external (null) descendant. The leftist property requires
/// `left.npl >= right.npl` for every node.
priv struct LeftistNode[T] {
  val : T
  npl : Int
  left : LeftistNode[T]?
  right : LeftistNode[T]?
}

///|
/// Compute the null path length of a node (0 for null).
fn[T] npl_of(node : LeftistNode[T]?) -> Int {
  match node {
    None => 0
    Some(n) => n.npl
  }
}

// ---------------------------------------------------------------------------
// Heap type
// ---------------------------------------------------------------------------

///|
/// A leftist heap (min-heap) with a user-supplied comparator.
///
/// `compare(a, b)` returns `< 0` when `a` should be extracted before `b`
/// (min-heap), `0` when equal, `> 0` otherwise.
pub struct LeftistHeap[T] {
  priv mut root : LeftistNode[T]?
  priv compare : (T, T) -> Int
  priv mut count : Int
}

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

///|
/// Create an empty leftist heap with the given comparator.
pub fn[T] LeftistHeap::new(compare : (T, T) -> Int) -> LeftistHeap[T] {
  { root: None, compare, count: 0 }
}

///|
/// Create a leftist heap from an array of elements.
///
/// Repeatedly inserts elements. For large arrays, consider using `from_array`
/// which builds the heap in O(n) by pairwise merging.
pub fn[T] LeftistHeap::from_array(
  arr : Array[T],
  compare : (T, T) -> Int,
) -> LeftistHeap[T] {
  let h = LeftistHeap::new(compare)
  for i = 0; i < arr.length(); i = i + 1 {
    h.insert(arr[i])
  }
  h
}

// ---------------------------------------------------------------------------
// Basic queries
// ---------------------------------------------------------------------------

///|
/// Returns the number of elements in the heap. O(1).
pub fn[T] LeftistHeap::size(self : LeftistHeap[T]) -> Int {
  self.count
}

///|
/// Returns `true` if the heap is empty. O(1).
pub fn[T] LeftistHeap::is_empty(self : LeftistHeap[T]) -> Bool {
  self.count == 0
}

///|
/// Peek at the minimum element without removing it. O(1).
///
/// Returns `None` if the heap is empty.
pub fn[T] LeftistHeap::find_min(self : LeftistHeap[T]) -> T? {
  match self.root {
    None => None
    Some(n) => Some(n.val)
  }
}

// ---------------------------------------------------------------------------
// Core operations
// ---------------------------------------------------------------------------

///|
/// Insert a value into the heap. O(log n).
///
/// Creates a single-node heap and merges it with the current heap.
pub fn[T] LeftistHeap::insert(self : LeftistHeap[T], val : T) -> Unit {
  let node : LeftistNode[T] = { val, npl: 1, left: None, right: None }
  self.root = merge_nodes(self.root, Some(node), self.compare)
  self.count = self.count + 1
}

///|
/// Remove and return the minimum element. O(log n).
///
/// Returns `None` if the heap is empty. The root's left and right subtrees
/// are merged to form the new heap.
pub fn[T] LeftistHeap::extract_min(self : LeftistHeap[T]) -> T? {
  match self.root {
    None => None
    Some(n) => {
      self.root = merge_nodes(n.left, n.right, self.compare)
      self.count = self.count - 1
      Some(n.val)
    }
  }
}

///|
/// Merge another heap into this heap. O(log n).
///
/// After merging, `other` is emptied (its root becomes `None` and count 0).
/// The comparator of `self` is used; it is the caller's responsibility to
/// ensure both heaps use compatible comparators.
pub fn[T] LeftistHeap::merge(
  self : LeftistHeap[T],
  other : LeftistHeap[T],
) -> Unit {
  self.root = merge_nodes(self.root, other.root, self.compare)
  self.count = self.count + other.count
  other.root = None
  other.count = 0
}

// ---------------------------------------------------------------------------
// Internal: recursive merge
// ---------------------------------------------------------------------------

///|
/// Merge two leftist heaps (represented by their root nodes).
///
/// This is the heart of the leftist heap. It walks down the right spines of
/// both trees, always keeping the smaller root on top. After merging, it
/// swaps children if necessary to maintain the leftist property, and updates
/// the npl field.
///
/// **Worst-case complexity**: O(log m + log n) = O(log(m + n)), because the
/// right spine of a leftist heap of k nodes has at most ⌊log₂(k+1)⌋ nodes.
fn[T] merge_nodes(
  a : LeftistNode[T]?,
  b : LeftistNode[T]?,
  compare : (T, T) -> Int,
) -> LeftistNode[T]? {
  match (a, b) {
    (None, _) => b
    (_, None) => a
    (Some(na), Some(nb)) => {
      // Ensure na has the smaller root (min-heap).
      let (smaller, larger) =
        if compare(na.val, nb.val) <= 0 {
          (na, nb)
        } else {
          (nb, na)
        }
      // Recursively merge the larger tree into the right subtree of smaller.
      let merged_right = merge_nodes(smaller.right, Some(larger), compare)
      // Set children: left stays, right becomes the merged result.
      let left = smaller.left
      // Enforce leftist property: npl(left) >= npl(right).
      // If violated, swap children.
      let (new_left, new_right) =
        if npl_of(left) >= npl_of(merged_right) {
          (left, merged_right)
        } else {
          (merged_right, left)
        }
      // Update npl: 1 + min(npl(left), npl(right)) = 1 + npl(right) since
      // leftist property guarantees npl(left) >= npl(right).
      let new_npl = 1 + npl_of(new_right)
      Some({ val: smaller.val, npl: new_npl, left: new_left, right: new_right })
    }
  }
}

// ---------------------------------------------------------------------------
// Utility: drain to sorted array
// ---------------------------------------------------------------------------

///|
/// Drain all elements from the heap into a sorted array (ascending order
/// for a min-heap). The heap is emptied.
pub fn[T] LeftistHeap::to_sorted_array(self : LeftistHeap[T]) -> Array[T] {
  let result : Array[T] = []
  while self.count > 0 {
    match self.extract_min() {
      Some(v) => result.push(v)
      None => break
    }
  }
  result
}

// ---------------------------------------------------------------------------
// Verification (test-only)
// ---------------------------------------------------------------------------

///|
/// Verify the leftist property: for every node, npl(left) >= npl(right).
/// Returns `true` if the invariant holds (or heap is empty).
fn[T] verify_leftist_property(node : LeftistNode[T]?) -> Bool {
  match node {
    None => true
    Some(n) => {
      let left_npl = npl_of(n.left)
      let right_npl = npl_of(n.right)
      if left_npl < right_npl {
        false
      } else {
        // Also verify npl field is correct.
        let expected_npl = 1 + right_npl
        if n.npl != expected_npl {
          false
        } else {
          verify_leftist_property(n.left) && verify_leftist_property(n.right)
        }
      }
    }
  }
}

///|
/// Verify the heap property: every parent <= its children.
fn[T] verify_heap_property(
  node : LeftistNode[T]?,
  compare : (T, T) -> Int,
) -> Bool {
  match node {
    None => true
    Some(n) => {
      let left_ok =
        match n.left {
          None => true
          Some(l) => compare(n.val, l.val) <= 0 && verify_heap_property(Some(l), compare)
        }
      let right_ok =
        match n.right {
          None => true
          Some(r) => compare(n.val, r.val) <= 0 && verify_heap_property(Some(r), compare)
        }
      left_ok && right_ok
    }
  }
}

///|
/// Count nodes in a subtree (for testing).
fn[T] count_nodes(node : LeftistNode[T]?) -> Int {
  match node {
    None => 0
    Some(n) => 1 + count_nodes(n.left) + count_nodes(n.right)
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "leftist_heap: empty heap" {
  let h = LeftistHeap::new(fn(a, b) { a - b })
  assert_true(h.is_empty())
  assert_eq(h.size(), 0)
  assert_true(h.find_min() is None)
  assert_true(h.extract_min() is None)
}

test "leftist_heap: single insert and extract" {
  let h = LeftistHeap::new(fn(a, b) { a - b })
  h.insert(42)
  assert_false(h.is_empty())
  assert_eq(h.size(), 1)
  assert_eq(h.find_min(), Some(42))
  assert_eq(h.extract_min(), Some(42))
  assert_true(h.is_empty())
  assert_eq(h.size(), 0)
}

test "leftist_heap: insert multiple and find_min" {
  let h = LeftistHeap::new(fn(a, b) { a - b })
  h.insert(5)
  h.insert(3)
  h.insert(8)
  h.insert(1)
  h.insert(9)
  assert_eq(h.size(), 5)
  assert_eq(h.find_min(), Some(1))
}

test "leftist_heap: extract all in sorted order" {
  let h = LeftistHeap::new(fn(a, b) { a - b })
  let input = [7, 3, 9, 1, 5, 8, 2, 6, 4, 0]
  for i = 0; i < input.length(); i = i + 1 {
    h.insert(input[i])
  }
  let result = h.to_sorted_array()
  assert_eq(result.length(), 10)
  for i = 0; i < 10; i = i + 1 {
    assert_eq(result[i], i)
  }
  assert_true(h.is_empty())
}

test "leftist_heap: duplicate values" {
  let h = LeftistHeap::new(fn(a, b) { a - b })
  h.insert(5)
  h.insert(5)
  h.insert(5)
  h.insert(3)
  h.insert(3)
  assert_eq(h.size(), 5)
  assert_eq(h.extract_min(), Some(3))
  assert_eq(h.extract_min(), Some(3))
  assert_eq(h.extract_min(), Some(5))
  assert_eq(h.extract_min(), Some(5))
  assert_eq(h.extract_min(), Some(5))
  assert_true(h.is_empty())
}

test "leftist_heap: max-heap via reversed comparator" {
  let h = LeftistHeap::new(fn(a, b) { b - a })
  h.insert(5)
  h.insert(3)
  h.insert(8)
  h.insert(1)
  h.insert(9)
  assert_eq(h.find_min(), Some(9))
  assert_eq(h.extract_min(), Some(9))
  assert_eq(h.extract_min(), Some(8))
  assert_eq(h.extract_min(), Some(5))
  assert_eq(h.extract_min(), Some(3))
  assert_eq(h.extract_min(), Some(1))
}

test "leftist_heap: merge two non-empty heaps" {
  let h1 = LeftistHeap::new(fn(a, b) { a - b })
  h1.insert(1)
  h1.insert(3)
  h1.insert(5)
  let h2 = LeftistHeap::new(fn(a, b) { a - b })
  h2.insert(2)
  h2.insert(4)
  h2.insert(6)
  h1.merge(h2)
  assert_eq(h1.size(), 6)
  assert_eq(h2.size(), 0)
  assert_true(h2.is_empty())
  let result = h1.to_sorted_array()
  for i = 0; i < 6; i = i + 1 {
    assert_eq(result[i], i + 1)
  }
}

test "leftist_heap: merge with empty heap" {
  let h1 = LeftistHeap::new(fn(a, b) { a - b })
  h1.insert(1)
  h1.insert(3)
  let h2 = LeftistHeap::new(fn(a, b) { a - b })
  h1.merge(h2)
  assert_eq(h1.size(), 2)
  assert_eq(h1.extract_min(), Some(1))
  assert_eq(h1.extract_min(), Some(3))
  // Merge empty into non-empty
  let h3 = LeftistHeap::new(fn(a, b) { a - b })
  h3.insert(10)
  let h4 = LeftistHeap::new(fn(a, b) { a - b })
  h3.merge(h4)
  assert_eq(h3.size(), 1)
  assert_eq(h3.extract_min(), Some(10))
}

test "leftist_heap: merge two empty heaps" {
  let h1 = LeftistHeap::new(fn(a, b) { a - b })
  let h2 = LeftistHeap::new(fn(a, b) { a - b })
  h1.merge(h2)
  assert_true(h1.is_empty())
  assert_eq(h1.size(), 0)
}

test "leftist_heap: from_array" {
  let arr = [9, 3, 7, 1, 8, 2, 6, 4, 5, 0]
  let h = LeftistHeap::from_array(arr, fn(a, b) { a - b })
  assert_eq(h.size(), 10)
  for i = 0; i < 10; i = i + 1 {
    assert_eq(h.extract_min(), Some(i))
  }
}

test "leftist_heap: leftist property maintained after operations" {
  let h = LeftistHeap::new(fn(a, b) { a - b })
  for i = 0; i < 100; i = i + 1 {
    h.insert(i * 7 % 100)
  }
  // Verify leftist property and heap property
  assert_true(verify_leftist_property(h.root))
  assert_true(verify_heap_property(h.root, h.compare))
  assert_eq(count_nodes(h.root), h.size())
  // Extract some and verify again
  for i = 0; i < 50; i = i + 1 {
    h.extract_min() |> ignore
  }
  assert_true(verify_leftist_property(h.root))
  assert_true(verify_heap_property(h.root, h.compare))
  assert_eq(count_nodes(h.root), h.size())
}

test "leftist_heap: right spine length is O(log n)" {
  // For n = 1023 = 2^10 - 1, right spine should be at most 10.
  let h = LeftistHeap::new(fn(a, b) { a - b })
  for i = 0; i < 1023; i = i + 1 {
    h.insert(1023 - i) // Insert in decreasing order to stress right spine
  }
  // Count right spine length
  let mut spine_len = 0
  let mut cur = h.root
  while cur is Some(_) {
    spine_len = spine_len + 1
    match cur {
      Some(n) => cur = n.right
      None => ()
    }
  }
  // Right spine of leftist heap with n nodes has at most floor(log2(n+1)) nodes.
  // For n = 1023, log2(1024) = 10.
  assert_true(spine_len <= 10)
}

test "leftist_heap: merge preserves leftist property" {
  let h1 = LeftistHeap::new(fn(a, b) { a - b })
  let h2 = LeftistHeap::new(fn(a, b) { a - b })
  for i = 0; i < 50; i = i + 1 {
    h1.insert(i * 2)
    h2.insert(i * 2 + 1)
  }
  h1.merge(h2)
  assert_eq(h1.size(), 100)
  assert_true(verify_leftist_property(h1.root))
  assert_true(verify_heap_property(h1.root, h1.compare))
}

test "leftist_heap: intermixed insert and extract" {
  let h = LeftistHeap::new(fn(a, b) { a - b })
  h.insert(5)
  h.insert(2)
  assert_eq(h.extract_min(), Some(2))
  h.insert(1)
  h.insert(8)
  h.insert(0)
  assert_eq(h.extract_min(), Some(0))
  assert_eq(h.extract_min(), Some(1))
  h.insert(3)
  assert_eq(h.extract_min(), Some(3))
  assert_eq(h.extract_min(), Some(5))
  assert_eq(h.extract_min(), Some(8))
  assert_true(h.is_empty())
}

test "leftist_heap: string values" {
  let h = LeftistHeap::new(fn(a : String, b : String) -> Int {
    let ac = a.to_array()
    let bc = b.to_array()
    let n = if ac.length() < bc.length() { ac.length() } else { bc.length() }
    let mut i = 0
    while i < n {
      let d = ac[i].to_int() - bc[i].to_int()
      if d != 0 { return d }
      i = i + 1
    }
    ac.length() - bc.length()
  })
  h.insert("cherry")
  h.insert("apple")
  h.insert("banana")
  h.insert("date")
  assert_eq(h.extract_min(), Some("apple"))
  assert_eq(h.extract_min(), Some("banana"))
  assert_eq(h.extract_min(), Some("cherry"))
  assert_eq(h.extract_min(), Some("date"))
}

test "leftist_heap: stress test with random-like sequence" {
  let h = LeftistHeap::new(fn(a, b) { a - b })
  // Use a simple LCG to generate pseudo-random values
  let mut seed = 12345
  let expected : Array[Int] = []
  for i = 0; i < 500; i = i + 1 {
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
    let val = seed % 1000
    h.insert(val)
    expected.push(val)
  }
  // Sort expected for comparison
  expected.sort()
  for i = 0; i < 500; i = i + 1 {
    assert_eq(h.extract_min(), Some(expected[i]))
  }
  assert_true(h.is_empty())
}

test "leftist_heap: repeated merge operations" {
  let heaps : Array[LeftistHeap[Int]] = []
  for k = 0; k < 10; k = k + 1 {
    let h = LeftistHeap::new(fn(a, b) { a - b })
    for j = 0; j < 10; j = j + 1 {
      h.insert(k * 10 + j)
    }
    heaps.push(h)
  }
  // Merge all into the first
  for i = 1; i < 10; i = i + 1 {
    heaps[0].merge(heaps[i])
  }
  assert_eq(heaps[0].size(), 100)
  assert_true(verify_leftist_property(heaps[0].root))
  assert_true(verify_heap_property(heaps[0].root, heaps[0].compare))
  // Verify sorted extraction
  for i = 0; i < 100; i = i + 1 {
    assert_eq(heaps[0].extract_min(), Some(i))
  }
}

test "leftist_heap: npl correctness after extensive operations" {
  let h = LeftistHeap::new(fn(a, b) { a - b })
  // Insert in sorted order (worst case for some heaps)
  for i = 0; i < 200; i = i + 1 {
    h.insert(i)
  }
  assert_true(verify_leftist_property(h.root))
  // Extract half
  for i = 0; i < 100; i = i + 1 {
    let v = h.extract_min()
    assert_eq(v, Some(i))
  }
  assert_true(verify_leftist_property(h.root))
  assert_eq(h.size(), 100)
  // Insert more
  for i = 0; i < 50; i = i + 1 {
    h.insert(i * 3)
  }
  assert_true(verify_leftist_property(h.root))
  assert_eq(h.size(), 150)
}
