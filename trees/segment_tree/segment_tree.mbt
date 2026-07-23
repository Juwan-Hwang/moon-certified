///|
/// Segment tree for range sum queries on FixedArray[Int].
/// Supports point updates and range sum queries in O(log n).
///
/// Internal layout: 1-indexed array of size 4*n.
/// Node 1 covers [0, n); for node i covering [lo, hi):
///   left child  = 2*i   covering [lo, mid)
///   right child = 2*i+1 covering [mid, hi)
///   where mid = (lo + hi) / 2
///
/// All public functions validate inputs:
/// - query returns 0 for invalid or out-of-bounds ranges
/// - update is a no-op for out-of-bounds indices
///
/// Not formally verified. Correctness ensured by comprehensive tests
/// including brute-force cross-checks on large arrays.
pub struct SegmentTree {
  tree : FixedArray[Int]
  n : Int
}

///|
/// Recursively build the tree. Node covers [lo, hi).
fn build_helper(
  arr : FixedArray[Int],
  tree : FixedArray[Int],
  node : Int,
  lo : Int,
  hi : Int,
) -> Unit {
  if lo == hi - 1 {
    tree[node] = arr[lo]
  } else {
    let mid = (lo + hi) / 2
    build_helper(arr, tree, 2 * node, lo, mid)
    build_helper(arr, tree, 2 * node + 1, mid, hi)
    tree[node] = tree[2 * node] + tree[2 * node + 1]
  }
}

///|
/// Recursively query sum over [ql, qr) within node covering [lo, hi).
fn query_helper(
  tree : FixedArray[Int],
  node : Int,
  lo : Int,
  hi : Int,
  ql : Int,
  qr : Int,
) -> Int {
  if qr <= lo || hi <= ql {
    0
  } else if ql <= lo && hi <= qr {
    tree[node]
  } else {
    let mid = (lo + hi) / 2
    let left = query_helper(tree, 2 * node, lo, mid, ql, qr)
    let right = query_helper(tree, 2 * node + 1, mid, hi, ql, qr)
    left + right
  }
}

///|
/// Recursively update index idx within node covering [lo, hi).
fn update_helper(
  tree : FixedArray[Int],
  node : Int,
  lo : Int,
  hi : Int,
  idx : Int,
  val : Int,
) -> Unit {
  if lo == hi - 1 {
    tree[node] = val
  } else {
    let mid = (lo + hi) / 2
    if idx < mid {
      update_helper(tree, 2 * node, lo, mid, idx, val)
    } else {
      update_helper(tree, 2 * node + 1, mid, hi, idx, val)
    }
    tree[node] = tree[2 * node] + tree[2 * node + 1]
  }
}

///|
/// Build a segment tree from an array.
pub fn build(arr : FixedArray[Int]) -> SegmentTree {
  let n = arr.length()
  let tree = FixedArray::make(4 * n, 0)
  if n > 0 {
    build_helper(arr, tree, 1, 0, n)
  }
  SegmentTree::{ tree, n }
}

///|
/// Query the sum of elements in range [l, r) (0-indexed, half-open).
/// Returns 0 for invalid ranges.
pub fn query(st : SegmentTree, l : Int, r : Int) -> Int {
  if l < 0 || r > st.n || l >= r {
    return 0
  }
  query_helper(st.tree, 1, 0, st.n, l, r)
}

///|
/// Update the value at index idx to val.
/// No-op if idx is out of bounds.
pub fn update(st : SegmentTree, idx : Int, val : Int) -> Unit {
  if idx < 0 || idx >= st.n {
    return
  }
  update_helper(st.tree, 1, 0, st.n, idx, val)
}

// ===========================================================================
// Lazy Segment Tree (range add + range sum query)
//
// Supports O(log n) range updates (add a value to all elements in [l, r))
// and O(log n) range sum queries. The pending array defers updates until
// a query or update needs to access children.
// ===========================================================================

/// Lazy segment tree supporting range add updates and range sum queries.
///
/// `tree` stores the sum of each segment; `pending` stores pending additions
/// that haven't been pushed to children yet. Both arrays use the same
/// 1-indexed layout as `SegmentTree`.
pub struct LazySegTree {
  tree : FixedArray[Int]
  pending : FixedArray[Int]
  n : Int
}

/// Build a lazy segment tree from an array.
pub fn lazy_build(arr : FixedArray[Int]) -> LazySegTree {
  let n = arr.length()
  let tree = FixedArray::make(4 * n, 0)
  let pending = FixedArray::make(4 * n, 0)
  if n > 0 {
    lazy_build_helper(arr, tree, 1, 0, n)
  }
  LazySegTree::{ tree, pending, n }
}

fn lazy_build_helper(
  arr : FixedArray[Int],
  tree : FixedArray[Int],
  node : Int,
  lo : Int,
  hi : Int,
) -> Unit {
  if lo == hi - 1 {
    tree[node] = arr[lo]
  } else {
    let mid = (lo + hi) / 2
    lazy_build_helper(arr, tree, 2 * node, lo, mid)
    lazy_build_helper(arr, tree, 2 * node + 1, mid, hi)
    tree[node] = tree[2 * node] + tree[2 * node + 1]
  }
}

/// Push pending value to children.
fn lazy_push(
  tree : FixedArray[Int],
  pending : FixedArray[Int],
  node : Int,
  lo : Int,
  hi : Int,
) -> Unit {
  if pending[node] == 0 {
    return
  }
  let mid = (lo + hi) / 2
  let left = 2 * node
  let right = 2 * node + 1
  // Apply pending to left child.
  tree[left] = tree[left] + pending[node] * (mid - lo)
  pending[left] = pending[left] + pending[node]
  // Apply pending to right child.
  tree[right] = tree[right] + pending[node] * (hi - mid)
  pending[right] = pending[right] + pending[node]
  // Clear pending at this node.
  pending[node] = 0
}

/// Range add: add `val` to all elements in [l, r).
fn lazy_update_helper(
  tree : FixedArray[Int],
  pending : FixedArray[Int],
  node : Int,
  lo : Int,
  hi : Int,
  l : Int,
  r : Int,
  val : Int,
) -> Unit {
  if r <= lo || hi <= l {
    return
  }
  if l <= lo && hi <= r {
    tree[node] = tree[node] + val * (hi - lo)
    pending[node] = pending[node] + val
    return
  }
  lazy_push(tree, pending, node, lo, hi)
  let mid = (lo + hi) / 2
  lazy_update_helper(tree, pending, 2 * node, lo, mid, l, r, val)
  lazy_update_helper(tree, pending, 2 * node + 1, mid, hi, l, r, val)
  tree[node] = tree[2 * node] + tree[2 * node + 1]
}

/// Range sum query over [ql, qr).
fn lazy_query_helper(
  tree : FixedArray[Int],
  pending : FixedArray[Int],
  node : Int,
  lo : Int,
  hi : Int,
  ql : Int,
  qr : Int,
) -> Int {
  if qr <= lo || hi <= ql {
    return 0
  }
  if ql <= lo && hi <= qr {
    return tree[node]
  }
  lazy_push(tree, pending, node, lo, hi)
  let mid = (lo + hi) / 2
  let left = lazy_query_helper(tree, pending, 2 * node, lo, mid, ql, qr)
  let right = lazy_query_helper(tree, pending, 2 * node + 1, mid, hi, ql, qr)
  left + right
}

/// Add `val` to every element in range [l, r) (0-indexed, half-open).
/// No-op if the range is invalid or out of bounds.
pub fn lazy_update(st : LazySegTree, l : Int, r : Int, val : Int) -> Unit {
  if l < 0 || r > st.n || l >= r {
    return
  }
  lazy_update_helper(st.tree, st.pending, 1, 0, st.n, l, r, val)
}

/// Query the sum of elements in range [l, r) (0-indexed, half-open).
/// Returns 0 for invalid ranges.
pub fn lazy_query(st : LazySegTree, l : Int, r : Int) -> Int {
  if l < 0 || r > st.n || l >= r {
    return 0
  }
  lazy_query_helper(st.tree, st.pending, 1, 0, st.n, l, r)
}

///|
test "build and query full range" {
  let arr = FixedArray::makei(5, fn(i) { i + 1 }) // [1, 2, 3, 4, 5]
  let st = build(arr)
  assert_eq(query(st, 0, 5), 15)
}

///|
test "query single element" {
  let arr = FixedArray::makei(5, fn(i) { i + 1 }) // [1, 2, 3, 4, 5]
  let st = build(arr)
  assert_eq(query(st, 0, 1), 1)
  assert_eq(query(st, 2, 3), 3)
  assert_eq(query(st, 4, 5), 5)
}

///|
test "query sub-range" {
  let arr = FixedArray::makei(5, fn(i) { i + 1 }) // [1, 2, 3, 4, 5]
  let st = build(arr)
  assert_eq(query(st, 1, 4), 9) // 2 + 3 + 4
  assert_eq(query(st, 0, 3), 6) // 1 + 2 + 3
  assert_eq(query(st, 2, 5), 12) // 3 + 4 + 5
}

///|
test "update and re-query" {
  let arr = FixedArray::makei(5, fn(i) { i + 1 }) // [1, 2, 3, 4, 5]
  let st = build(arr)
  assert_eq(query(st, 2, 3), 3)
  update(st, 2, 10)
  assert_eq(query(st, 2, 3), 10)
  assert_eq(query(st, 0, 5), 22) // 1 + 2 + 10 + 4 + 5
}

///|
test "multiple updates" {
  let arr = FixedArray::makei(5, fn(i) { i + 1 }) // [1, 2, 3, 4, 5]
  let st = build(arr)
  update(st, 0, 100)
  update(st, 4, 200)
  update(st, 2, 50)
  assert_eq(query(st, 0, 1), 100)
  assert_eq(query(st, 4, 5), 200)
  assert_eq(query(st, 2, 3), 50)
  assert_eq(query(st, 0, 5), 356) // 100 + 2 + 50 + 4 + 200
}

///|
test "invalid range (l > r)" {
  let arr = FixedArray::makei(5, fn(i) { i + 1 })
  let st = build(arr)
  assert_eq(query(st, 3, 1), 0)
  assert_eq(query(st, 4, 2), 0)
  assert_eq(query(st, 5, 0), 0)
}

///|
test "out of bounds range" {
  let arr = FixedArray::makei(5, fn(i) { i + 1 })
  let st = build(arr)
  assert_eq(query(st, 0, 100), 0)
  assert_eq(query(st, -1, 3), 0)
  assert_eq(query(st, 3, 10), 0)
  // Update out of bounds is a no-op
  update(st, -1, 999)
  update(st, 100, 999)
  assert_eq(query(st, 0, 5), 15) // unchanged
}

///|
test "empty array" {
  let arr : FixedArray[Int] = FixedArray::make(0, 0)
  let st = build(arr)
  assert_eq(query(st, 0, 0), 0)
  assert_eq(query(st, 0, 1), 0)
  update(st, 0, 42) // no-op, should not crash
  assert_eq(query(st, 0, 0), 0)
}

///|
test "single element array" {
  let arr = FixedArray::make(1, 42)
  let st = build(arr)
  assert_eq(query(st, 0, 1), 42)
  assert_eq(query(st, 0, 0), 0)
  update(st, 0, 99)
  assert_eq(query(st, 0, 1), 99)
}

///|
test "negative values" {
  let arr = FixedArray::make(4, 0)
  arr[0] = -1
  arr[1] = -2
  arr[2] = 3
  arr[3] = -4
  let st = build(arr)
  assert_eq(query(st, 0, 4), -4) // -1 + -2 + 3 + -4
  assert_eq(query(st, 0, 2), -3) // -1 + -2
  assert_eq(query(st, 2, 4), -1) // 3 + -4
  assert_eq(query(st, 1, 3), 1) // -2 + 3
}

///|
test "large array (100 elements)" {
  let n = 100
  let arr = FixedArray::makei(n, fn(i) { i + 1 }) // [1, 2, ..., 100]
  let st = build(arr)
  // Full range: sum 1..100 = 5050
  assert_eq(query(st, 0, n), 5050)
  // Cross-check various sub-ranges against brute force
  for start = 0; start < n; start = start + 7 {
    for end = start + 1; end <= n; end = end + 11 {
      let mut expected = 0
      for k = start; k < end; k = k + 1 {
        expected = expected + arr[k]
      }
      assert_eq(query(st, start, end), expected)
    }
  }
  // Spot-check single elements
  for i = 0; i < n; i = i + 13 {
    assert_eq(query(st, i, i + 1), i + 1)
  }
}

///|
test "query after all elements updated" {
  let n = 50
  let arr = FixedArray::makei(n, fn(i) { i + 1 }) // [1, 2, ..., 50]
  let st = build(arr)
  // Update every element: arr[i] = (i + 1) * 10
  for i = 0; i < n; i = i + 1 {
    update(st, i, (i + 1) * 10)
  }
  // Verify full range
  let mut expected_total = 0
  for i = 0; i < n; i = i + 1 {
    expected_total = expected_total + (i + 1) * 10
  }
  assert_eq(query(st, 0, n), expected_total)
  // Cross-check sub-ranges against brute force
  for start = 0; start < n; start = start + 9 {
    for end = start + 1; end <= n; end = end + 7 {
      let mut expected = 0
      for k = start; k < end; k = k + 1 {
        expected = expected + (k + 1) * 10
      }
      assert_eq(query(st, start, end), expected)
    }
  }
  // Single elements
  for i = 0; i < n; i = i + 11 {
    assert_eq(query(st, i, i + 1), (i + 1) * 10)
  }
}

// ---------------------------------------------------------------------------
// Lazy Segment Tree tests
// ---------------------------------------------------------------------------

///|
test "lazy: build and query full range" {
  let arr = FixedArray::makei(5, fn(i) { i + 1 }) // [1, 2, 3, 4, 5]
  let st = lazy_build(arr)
  assert_eq(lazy_query(st, 0, 5), 15)
}

///|
test "lazy: range add then query" {
  let arr = FixedArray::makei(5, fn(i) { i + 1 }) // [1, 2, 3, 4, 5]
  let st = lazy_build(arr)
  // Add 10 to elements [1, 4): [1, 12, 13, 14, 5]
  lazy_update(st, 1, 4, 10)
  assert_eq(lazy_query(st, 0, 5), 45) // 1 + 12 + 13 + 14 + 5
  assert_eq(lazy_query(st, 0, 1), 1) // unchanged
  assert_eq(lazy_query(st, 1, 2), 12) // 2 + 10
  assert_eq(lazy_query(st, 3, 4), 14) // 4 + 10
  assert_eq(lazy_query(st, 4, 5), 5) // unchanged
}

///|
test "lazy: multiple range adds" {
  let arr = FixedArray::make(5, 0) // [0, 0, 0, 0, 0]
  let st = lazy_build(arr)
  lazy_update(st, 0, 3, 5) // [5, 5, 5, 0, 0]
  lazy_update(st, 2, 5, 3) // [5, 5, 8, 3, 3]
  assert_eq(lazy_query(st, 0, 5), 24)
  assert_eq(lazy_query(st, 0, 1), 5)
  assert_eq(lazy_query(st, 2, 3), 8)
  assert_eq(lazy_query(st, 3, 5), 6)
}

///|
test "lazy: add full range" {
  let arr = FixedArray::makei(5, fn(i) { i + 1 }) // [1, 2, 3, 4, 5]
  let st = lazy_build(arr)
  lazy_update(st, 0, 5, 100)
  // Every element +100: [101, 102, 103, 104, 105]
  assert_eq(lazy_query(st, 0, 5), 515)
  for i = 0; i < 5; i = i + 1 {
    assert_eq(lazy_query(st, i, i + 1), i + 101)
  }
}

///|
test "lazy: cross-check with brute force" {
  let n = 20
  let arr = FixedArray::makei(n, fn(i) { (i * 7 + 3) % 10 })
  let st = lazy_build(arr)
  // Brute-force array for comparison.
  let brute = FixedArray::makei(n, fn(i) { arr[i] })
  // Perform several range updates.
  lazy_update(st, 0, 10, 3)
  for i = 0; i < 10; i = i + 1 {
    brute[i] = brute[i] + 3
  }
  lazy_update(st, 5, 15, 7)
  for i = 5; i < 15; i = i + 1 {
    brute[i] = brute[i] + 7
  }
  lazy_update(st, 10, 20, 1)
  for i = 10; i < 20; i = i + 1 {
    brute[i] = brute[i] + 1
  }
  // Cross-check all sub-ranges.
  for l = 0; l < n; l = l + 1 {
    for r = l + 1; r <= n; r = r + 1 {
      let mut expected = 0
      for k = l; k < r; k = k + 1 {
        expected = expected + brute[k]
      }
      assert_eq(lazy_query(st, l, r), expected)
    }
  }
}

///|
test "lazy: invalid ranges" {
  let arr = FixedArray::makei(5, fn(i) { i + 1 })
  let st = lazy_build(arr)
  assert_eq(lazy_query(st, 3, 1), 0) // l > r
  assert_eq(lazy_query(st, -1, 3), 0) // l < 0
  assert_eq(lazy_query(st, 0, 100), 0) // r > n
  // Invalid update is no-op.
  lazy_update(st, 3, 1, 100)
  assert_eq(lazy_query(st, 0, 5), 15) // unchanged
}

///|
test "lazy: empty array" {
  let arr : FixedArray[Int] = FixedArray::make(0, 0)
  let st = lazy_build(arr)
  assert_eq(lazy_query(st, 0, 0), 0)
  lazy_update(st, 0, 0, 10) // no-op
  assert_eq(lazy_query(st, 0, 0), 0)
}
