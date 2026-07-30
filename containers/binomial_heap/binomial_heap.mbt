/// Binomial Heap — a mergeable priority queue with O(log n) operations.
///
/// A **binomial heap** is a collection of **binomial trees** that satisfies the
/// **heap property**: every node's key ≤ its children's keys (min-heap). It
/// supports efficient `merge` (union of two heaps) in O(log n), which is its
/// primary advantage over a binary heap.
///
/// ## Binomial Trees
///
/// A binomial tree B_k is defined recursively:
/// - B_0 is a single node.
/// - B_k is formed by linking two B_{k−1} trees: one becomes the leftmost
///   child of the other's root.
///
/// B_k has exactly 2^k nodes and height k. The root has k children with
/// degrees 0, 1, …, k−1 (left to right).
///
/// ## Heap Structure
///
/// A binomial heap maintains at most one tree of each degree, analogous to
/// binary representation: a heap of n elements has trees corresponding to the
/// 1-bits of n. For example, n = 13 = 1101₂ uses trees B_0, B_2, B_3.
///
/// ## Complexity
///
/// | Operation     | Time     |
/// |---------------|----------|
/// | `insert`      | O(log n) |
/// | `find_min`    | O(log n) |
/// | `extract_min` | O(log n) |
/// | `merge`       | O(log n) |
/// | `size`        | O(1)     |
///
/// ## References
///
/// - Vuillemin, J. (1978). "A data structure for manipulating priority queues."
///   *Communications of the ACM*, 21(4), 309–315.
/// - Cormen, T. H. et al. (2009). *Introduction to Algorithms*, 3rd ed.,
///   Chapter 19.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Node type
// ---------------------------------------------------------------------------

///|
/// A binomial tree node.
///
/// `children` stores the children in **decreasing** order of degree
/// (k−1, k−2, …, 0), matching the CLRS convention where the leftmost child
/// has the highest degree.
priv struct BinomialNode[T] {
  val : T
  degree : Int
  children : Array[BinomialNode[T]]
}

// ---------------------------------------------------------------------------
// Heap type
// ---------------------------------------------------------------------------

///|
/// A binomial heap (min-heap) with a user-supplied comparator.
///
/// `compare(a, b)` returns `< 0` when `a` should be extracted before `b`
/// (min-heap), `0` when equal, `> 0` otherwise.
pub struct BinomialHeap[T] {
  priv mut roots : Array[BinomialNode[T]] // ordered by increasing degree
  priv compare : (T, T) -> Int
  priv mut count : Int
}

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

///|
/// Create an empty binomial heap with the given comparator.
pub fn[T] new(compare : (T, T) -> Int) -> BinomialHeap[T] {
  { roots: [], compare, count: 0 }
}

// ---------------------------------------------------------------------------
// Queries
// ---------------------------------------------------------------------------

///|
/// Return the number of elements in the heap. O(1).
pub fn[T] size(heap : BinomialHeap[T]) -> Int {
  heap.count
}

///|
/// Check whether the heap is empty. O(1).
pub fn[T] is_empty(heap : BinomialHeap[T]) -> Bool {
  heap.count == 0
}

///|
/// Return the minimum element without removing it.
///
/// Returns `None` if the heap is empty.
///
/// Time: O(log n) — scans the root list.
pub fn[T] find_min(heap : BinomialHeap[T]) -> T? {
  if heap.roots.length() == 0 {
    return None
  }
  let mut min_node = heap.roots[0]
  for i = 1; i < heap.roots.length(); i = i + 1 {
    if (heap.compare)(heap.roots[i].val, min_node.val) < 0 {
      min_node = heap.roots[i]
    }
  }
  Some(min_node.val)
}

// ---------------------------------------------------------------------------
// Internal: link two trees of the same degree
// ---------------------------------------------------------------------------

///|
/// Link two B_k trees to form a B_{k+1} tree.
/// The root with the larger key becomes a child of the root with the smaller key.
fn[T] link(
  t1 : BinomialNode[T],
  t2 : BinomialNode[T],
  compare : (T, T) -> Int,
) -> BinomialNode[T] {
  if compare(t1.val, t2.val) <= 0 {
    // t1 becomes root, t2 becomes its leftmost child.
    t1.children.push(t2)
    { val: t1.val, degree: t1.degree + 1, children: t1.children }
  } else {
    t2.children.push(t1)
    { val: t2.val, degree: t2.degree + 1, children: t2.children }
  }
}

// ---------------------------------------------------------------------------
// Internal: merge two root lists by degree
// ---------------------------------------------------------------------------

///|
/// Merge two root lists (both ordered by increasing degree) into one,
/// combining trees of equal degree (like binary addition with carry).
fn[T] merge_roots(
  r1 : Array[BinomialNode[T]],
  r2 : Array[BinomialNode[T]],
  compare : (T, T) -> Int,
) -> Array[BinomialNode[T]] {
  let result : Array[BinomialNode[T]] = []
  let mut i = 0
  let mut j = 0
  // Carry from a previous link operation.
  let mut carry : BinomialNode[T]? = None
  while i < r1.length() || j < r2.length() || carry is Some(_) {
    // Determine the current degree and collect all trees of that degree.
    let trees : Array[BinomialNode[T]] = []
    // Add carry if it exists.
    match carry {
      Some(c) => trees.push(c)
      None => ()
    }
    carry = None
    // Add from r1 if degree matches.
    if i < r1.length() {
      if trees.length() == 0 || r1[i].degree == trees[0].degree {
        trees.push(r1[i])
        i = i + 1
      } else if r1[i].degree < trees[0].degree {
        trees.push(r1[i])
        i = i + 1
      }
    }
    // Add from r2 if degree matches.
    if j < r2.length() && trees.length() > 0 {
      if r2[j].degree == trees[0].degree {
        trees.push(r2[j])
        j = j + 1
      }
    } else if j < r2.length() && trees.length() == 0 {
      trees.push(r2[j])
      j = j + 1
    }
    // Process collected trees.
    if trees.length() == 1 {
      result.push(trees[0])
    } else if trees.length() == 2 {
      // Link two trees of the same degree → carry.
      carry = Some(link(trees[0], trees[1], compare))
    } else if trees.length() == 3 {
      // Link two, carry the result, and keep one in result.
      carry = Some(link(trees[0], trees[1], compare))
      result.push(trees[2])
    }
  }
  result
}

// ---------------------------------------------------------------------------
// Mutations
// ---------------------------------------------------------------------------

///|
/// Insert a value into the heap. O(log n).
pub fn[T] insert(heap : BinomialHeap[T], val : T) -> Unit {
  let node : BinomialNode[T] = { val, degree: 0, children: [] }
  let single : Array[BinomialNode[T]] = [node]
  heap.roots = merge_roots(heap.roots, single, heap.compare)
  heap.count = heap.count + 1
}

///|
/// Remove and return the minimum element.
///
/// Returns `None` if the heap is empty.
///
/// Time: O(log n).
pub fn[T] extract_min(heap : BinomialHeap[T]) -> T? {
  if heap.roots.length() == 0 {
    return None
  }
  // Find the root with minimum value.
  let mut min_idx = 0
  for i = 1; i < heap.roots.length(); i = i + 1 {
    if (heap.compare)(heap.roots[i].val, heap.roots[min_idx].val) < 0 {
      min_idx = i
    }
  }
  let min_node = heap.roots[min_idx]
  // Remove min_node from roots.
  let remaining : Array[BinomialNode[T]] = []
  for i = 0; i < heap.roots.length(); i = i + 1 {
    if i != min_idx {
      remaining.push(heap.roots[i])
    }
  }
  // The children of min_node form a valid heap (reversed to get increasing degree).
  let children : Array[BinomialNode[T]] = []
  for i = min_node.children.length() - 1; i >= 0; i = i - 1 {
    children.push(min_node.children[i])
  }
  heap.roots = merge_roots(remaining, children, heap.compare)
  heap.count = heap.count - 1
  Some(min_node.val)
}

///|
/// Merge another heap into this heap. The other heap is consumed (left empty).
///
/// Time: O(log n).
pub fn[T] merge(heap : BinomialHeap[T], other : BinomialHeap[T]) -> Unit {
  // Note: we assume both heaps use the same comparator (enforced by caller).
  heap.roots = merge_roots(heap.roots, other.roots, heap.compare)
  heap.count = heap.count + other.count
  other.roots.clear()
  other.count = 0
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "binomial_heap: insert and find_min" {
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
test "binomial_heap: extract_min" {
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
test "binomial_heap: extract_min on empty" {
  let h = new(fn(a : Int, b : Int) -> Int { a - b })
  assert_eq(extract_min(h), None)
  assert_eq(find_min(h), None)
}

///|
test "binomial_heap: merge two heaps" {
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
  // Extract all from merged heap — should be in sorted order.
  for i = 1; i <= 6; i = i + 1 {
    assert_eq(extract_min(h1), Some(i))
  }
}

///|
test "binomial_heap: duplicate keys" {
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
test "binomial_heap: max-heap via reversed comparator" {
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
test "binomial_heap: large sequential insert and extract" {
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
test "binomial_heap: reverse order insert" {
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
test "binomial_heap: interleave insert and extract" {
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
test "binomial_heap: merge with empty" {
  let h1 = new(fn(a : Int, b : Int) -> Int { a - b })
  let h2 = new(fn(a : Int, b : Int) -> Int { a - b })
  insert(h1, 1)
  insert(h1, 3)
  merge(h1, h2) // merge with empty
  assert_eq(size(h1), 2)
  assert_eq(extract_min(h1), Some(1))
  assert_eq(extract_min(h1), Some(3))
}

///|
test "binomial_heap: merge empty into non-empty" {
  let h1 = new(fn(a : Int, b : Int) -> Int { a - b })
  let h2 = new(fn(a : Int, b : Int) -> Int { a - b })
  insert(h2, 1)
  insert(h2, 3)
  merge(h1, h2) // merge non-empty into empty
  assert_eq(size(h1), 2)
  assert_eq(extract_min(h1), Some(1))
  assert_eq(extract_min(h1), Some(3))
}

///|
test "binomial_heap: string elements" {
  let h = new(fn(a : String, b : String) -> Int {
    // Lexicographic comparison.
    let r = a.compare(b)
    r
  })
  insert(h, "banana")
  insert(h, "apple")
  insert(h, "cherry")
  assert_eq(find_min(h), Some("apple"))
  assert_eq(extract_min(h), Some("apple"))
  assert_eq(extract_min(h), Some("banana"))
  assert_eq(extract_min(h), Some("cherry"))
}

///|
test "binomial_heap: stress test with merge" {
  let h1 = new(fn(a : Int, b : Int) -> Int { a - b })
  let h2 = new(fn(a : Int, b : Int) -> Int { a - b })
  // Insert evens into h1, odds into h2.
  for i = 0; i < 50; i = i + 1 {
    insert(h1, i * 2)
    insert(h2, i * 2 + 1)
  }
  merge(h1, h2)
  assert_eq(size(h1), 100)
  // Extract all — should be 0..99 in order.
  for i = 0; i < 100; i = i + 1 {
    assert_eq(extract_min(h1), Some(i))
  }
}

///|
test "binomial_heap: single element" {
  let h = new(fn(a : Int, b : Int) -> Int { a - b })
  insert(h, 42)
  assert_eq(size(h), 1)
  assert_eq(find_min(h), Some(42))
  assert_eq(extract_min(h), Some(42))
  assert_eq(extract_min(h), None)
  assert_true(is_empty(h))
}
