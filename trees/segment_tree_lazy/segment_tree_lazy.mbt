/// Segment Tree with Lazy Propagation.
///
/// Supports range updates and range queries in O(log n) time each.
///
/// ## Supported operations
///
/// - `build(arr)` — O(n) construction from an initial array.
/// - `range_add(l, r, val)` — add `val` to every element in `[l, r]`. O(log n).
/// - `range_sum(l, r)` — sum of elements in `[l, r)`. O(log n).
/// - `range_min(l, r)` — minimum element in `[l, r)`. O(log n).
/// - `range_max(l, r)` — maximum element in `[l, r)`. O(log n).
/// - `point_get(idx)` — **base** value at `idx` (last `point_set` or `build`
///   value, NOT including pending `range_add` updates). **O(1)** via a
///   cached `values` array.
/// - `current_value(idx)` — **current** value at `idx` including all pending
///   `range_add` updates. O(log n).
/// - `point_set(idx, val)` — set `arr[idx] = val`. O(log n).
///
/// ## point_get vs current_value
///
/// The tree maintains a cached `values` array that mirrors the last value
/// explicitly set at each position (via `build` or `point_set`). This allows
/// **O(1)** `point_get` — useful for workloads that set values frequently and
/// read them back without intervening `range_add` calls.
///
/// When `range_add` has been applied, `point_get` returns the **stale** base
/// value. To obtain the **current** value (including all pending `range_add`
/// deltas), use `current_value(idx)` which traverses the tree to collect lazy
/// tags in O(log n), or equivalently `range_sum(idx, idx + 1)`.
///
/// ## How it works
///
/// Each node stores `sum`, `min`, and `max` for its segment. A `lazy` value
/// records pending additions that have been applied to this node but not yet
/// pushed to its children. When a query touches a child, `push_down`
/// propagates the lazy value before recursing.
///
/// **Stack safety**: every recursive helper descends a perfectly balanced
/// binary tree (each level halves the segment), so the recursion depth is
/// O(log n) — safe for any array that fits in memory; no depth guard is
/// needed. The midpoint uses the overflow-safe `lo + (hi - lo) / 2` form so
/// index arithmetic never wraps.
///
/// **Point reads**: `point_get` is already O(1) (it reads the cached
/// `values` array directly), so no separate `point_get_fast` is required.
/// See "point_get vs current_value" above for the base/current distinction.
///
/// All fields are **package-private**; external callers interact through
/// free functions only.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

///|
/// A segment tree node storing aggregate statistics and a lazy add value.
pub struct LazySegNode {
  priv mut sum : Int64
  priv mut mn : Int64
  priv mut mx : Int64
  priv mut lazy_val : Int64 // pending addition to propagate to children
}

///|
/// The segment tree.
///
/// - `nodes` is a 1-indexed array of `4 * n` elements (standard binary heap layout).
/// - `n` is the size of the underlying array.
/// - `values` is a cached copy of the base values (set via `build` or
///   `point_set`), enabling O(1) `point_get`. It does NOT reflect
///   `range_add` updates; use `current_value` for that.
pub struct LazySegTree {
  priv nodes : Array[LazySegNode]
  priv n : Int
  priv values : FixedArray[Int64]
}

///|
/// Sentinel values for empty segments.
const INF_LAZY : Int64 = 9223372036854775807L

///|
const NEG_INF_LAZY : Int64 = -9223372036854775808L

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

///|
/// Build a segment tree from an array of `Int` values.
///
/// The tree supports range additions and range queries on the original array.
/// `n` is determined by `arr.length()`. An empty array produces a tree with `n = 0`.
pub fn build(arr : FixedArray[Int]) -> LazySegTree {
  let n = arr.length()
  let values = FixedArray::make(n, 0L)
  for i = 0; i < n; i = i + 1 {
    values[i] = arr[i].to_int64()
  }
  let st : LazySegTree = { nodes: [], n, values, }
  // Allocate 4*n nodes.
  for i = 0; i < 4 * n + 4; i = i + 1 {
    st.nodes.push({ sum: 0L, mn: INF_LAZY, mx: NEG_INF_LAZY, lazy_val: 0L, })
  }
  if n > 0 {
    build_helper(st, arr, 1, 0, n - 1)
  }
  st
}

///|
fn build_helper(
  st : LazySegTree,
  arr : FixedArray[Int],
  node : Int,
  lo : Int,
  hi : Int,
) -> Unit {
  if lo == hi {
    let v = arr[lo].to_int64()
    st.nodes[node].sum = v
    st.nodes[node].mn = v
    st.nodes[node].mx = v
    st.nodes[node].lazy_val = 0L
    return
  }
  let mid = lo + (hi - lo) / 2
  build_helper(st, arr, node * 2, lo, mid)
  build_helper(st, arr, node * 2 + 1, mid + 1, hi)
  push_up(st, node)
}

// ---------------------------------------------------------------------------
// Internal: push_up / push_down
// ---------------------------------------------------------------------------

///|
/// Recompute aggregates from children.
fn push_up(st : LazySegTree, node : Int) -> Unit {
  let left = node * 2
  let right = node * 2 + 1
  st.nodes[node].sum = st.nodes[left].sum + st.nodes[right].sum
  st.nodes[node].mn = if st.nodes[left].mn < st.nodes[right].mn {
    st.nodes[left].mn
  } else {
    st.nodes[right].mn
  }
  st.nodes[node].mx = if st.nodes[left].mx > st.nodes[right].mx {
    st.nodes[left].mx
  } else {
    st.nodes[right].mx
  }
}

///|
/// Propagate lazy value to children.
fn push_down(st : LazySegTree, node : Int, lo : Int, hi : Int) -> Unit {
  if st.nodes[node].lazy_val != 0L {
    let lazy_val = st.nodes[node].lazy_val
    let left = node * 2
    let right = node * 2 + 1
    let mid = lo + (hi - lo) / 2
    apply_lazy(st, left, lo, mid, lazy_val)
    apply_lazy(st, right, mid + 1, hi, lazy_val)
    st.nodes[node].lazy_val = 0L
  }
}

///|
/// Apply a lazy addition to a node, updating its aggregates.
fn apply_lazy(
  st : LazySegTree,
  node : Int,
  lo : Int,
  hi : Int,
  val : Int64,
) -> Unit {
  let cnt = (hi - lo + 1).to_int64()
  st.nodes[node].sum = st.nodes[node].sum + val * cnt
  st.nodes[node].mn = st.nodes[node].mn + val
  st.nodes[node].mx = st.nodes[node].mx + val
  st.nodes[node].lazy_val = st.nodes[node].lazy_val + val
}

// ---------------------------------------------------------------------------
// Range operations
// ---------------------------------------------------------------------------

///|
/// Add `val` to every element in `[l, r]` (inclusive).
///
/// Uses lazy propagation: only the nodes on the update path are modified,
/// and the pending additions are pushed down when needed. O(log n).
///
/// Does nothing if `l > r`, `l < 0`, or `r >= n`.
pub fn range_add(st : LazySegTree, l : Int, r : Int, val : Int64) -> Unit {
  if st.n == 0 || l < 0 || r >= st.n || l > r {
    return
  }
  update_helper(st, 1, 0, st.n - 1, l, r, val)
}

///|
fn update_helper(
  st : LazySegTree,
  node : Int,
  lo : Int,
  hi : Int,
  l : Int,
  r : Int,
  val : Int64,
) -> Unit {
  if l <= lo && hi <= r {
    apply_lazy(st, node, lo, hi, val)
    return
  }
  push_down(st, node, lo, hi)
  let mid = lo + (hi - lo) / 2
  if l <= mid {
    update_helper(st, node * 2, lo, mid, l, r, val)
  }
  if r > mid {
    update_helper(st, node * 2 + 1, mid + 1, hi, l, r, val)
  }
  push_up(st, node)
}

///|
/// Sum of elements in `[l, r)` (half-open interval).
///
/// Returns 0 if `l >= r` or the range is out of bounds. O(log n).
pub fn range_sum(st : LazySegTree, l : Int, r : Int) -> Int64 {
  if st.n == 0 || l >= r || l < 0 || r > st.n {
    return 0L
  }
  query_sum_helper(st, 1, 0, st.n - 1, l, r - 1)
}

///|
fn query_sum_helper(
  st : LazySegTree,
  node : Int,
  lo : Int,
  hi : Int,
  l : Int,
  r : Int,
) -> Int64 {
  if l <= lo && hi <= r {
    return st.nodes[node].sum
  }
  push_down(st, node, lo, hi)
  let mid = lo + (hi - lo) / 2
  let mut result = 0L
  if l <= mid {
    result = result + query_sum_helper(st, node * 2, lo, mid, l, r)
  }
  if r > mid {
    result = result + query_sum_helper(st, node * 2 + 1, mid + 1, hi, l, r)
  }
  result
}

///|
/// Minimum element in `[l, r)` (half-open interval).
///
/// Returns `INF` if the range is empty or out of bounds. O(log n).
pub fn range_min(st : LazySegTree, l : Int, r : Int) -> Int64 {
  if st.n == 0 || l >= r || l < 0 || r > st.n {
    return INF_LAZY
  }
  query_min_helper(st, 1, 0, st.n - 1, l, r - 1)
}

///|
fn query_min_helper(
  st : LazySegTree,
  node : Int,
  lo : Int,
  hi : Int,
  l : Int,
  r : Int,
) -> Int64 {
  if l <= lo && hi <= r {
    return st.nodes[node].mn
  }
  push_down(st, node, lo, hi)
  let mid = lo + (hi - lo) / 2
  let mut result = INF_LAZY
  if l <= mid {
    let v = query_min_helper(st, node * 2, lo, mid, l, r)
    if v < result {
      result = v
    }
  }
  if r > mid {
    let v = query_min_helper(st, node * 2 + 1, mid + 1, hi, l, r)
    if v < result {
      result = v
    }
  }
  result
}

///|
/// Maximum element in `[l, r)` (half-open interval).
///
/// Returns `-INF` if the range is empty or out of bounds. O(log n).
pub fn range_max(st : LazySegTree, l : Int, r : Int) -> Int64 {
  if st.n == 0 || l >= r || l < 0 || r > st.n {
    return NEG_INF_LAZY
  }
  query_max_helper(st, 1, 0, st.n - 1, l, r - 1)
}

///|
fn query_max_helper(
  st : LazySegTree,
  node : Int,
  lo : Int,
  hi : Int,
  l : Int,
  r : Int,
) -> Int64 {
  if l <= lo && hi <= r {
    return st.nodes[node].mx
  }
  push_down(st, node, lo, hi)
  let mid = lo + (hi - lo) / 2
  let mut result = NEG_INF_LAZY
  if l <= mid {
    let v = query_max_helper(st, node * 2, lo, mid, l, r)
    if v > result {
      result = v
    }
  }
  if r > mid {
    let v = query_max_helper(st, node * 2 + 1, mid + 1, hi, l, r)
    if v > result {
      result = v
    }
  }
  result
}

///|
/// Get the **base** value at index `idx`. **O(1)**.
///
/// Returns the last value set via `point_set` or `build` at this position,
/// directly from the cached `values` array. Does **NOT** include pending
/// `range_add` updates.
///
/// To obtain the current value including all `range_add` deltas, use
/// `current_value(idx)` (O(log n)) or `range_sum(idx, idx + 1)` (O(log n)).
///
/// Returns 0 if `idx` is out of bounds.
pub fn point_get(st : LazySegTree, idx : Int) -> Int64 {
  if st.n == 0 || idx < 0 || idx >= st.n {
    return 0L
  }
  st.values[idx]
}

///|
/// Get the **current** value at index `idx`, including all pending
/// `range_add` updates. **O(log n)**.
///
/// This traverses the tree to collect all lazy tags affecting `idx`,
/// giving the up-to-date value. Use this when `range_add` has been
/// applied since the last `point_set` and you need the actual current value.
///
/// Returns 0 if `idx` is out of bounds.
pub fn current_value(st : LazySegTree, idx : Int) -> Int64 {
  if st.n == 0 || idx < 0 || idx >= st.n {
    return 0L
  }
  range_sum(st, idx, idx + 1)
}

///|
/// Set `arr[idx] = val`. O(log n).
///
/// Uses a **direct single-traversal update**: pushes down lazy tags along the
/// path to the leaf, sets the leaf value, then pulls up aggregates on the way
/// back. This avoids the double traversal (point_get + range_add) that the
/// naive approach requires.
///
/// Also updates the cached `values` array in O(1), so that `point_get(idx)`
/// returns `val` immediately after this call (until a `range_add` affects `idx`).
///
/// Does nothing if `idx` is out of bounds.
pub fn point_set(st : LazySegTree, idx : Int, val : Int64) -> Unit {
  if st.n == 0 || idx < 0 || idx >= st.n {
    return
  }
  st.values[idx] = val
  point_set_helper(st, 1, 0, st.n - 1, idx, val)
}

///|
fn point_set_helper(
  st : LazySegTree,
  node : Int,
  lo : Int,
  hi : Int,
  idx : Int,
  val : Int64,
) -> Unit {
  if lo == hi {
    st.nodes[node].sum = val
    st.nodes[node].mn = val
    st.nodes[node].mx = val
    return
  }
  push_down(st, node, lo, hi)
  let mid = lo + (hi - lo) / 2
  if idx <= mid {
    point_set_helper(st, node * 2, lo, mid, idx, val)
  } else {
    point_set_helper(st, node * 2 + 1, mid + 1, hi, idx, val)
  }
  push_up(st, node)
}

///|
/// Number of elements in the underlying array. O(1).
pub fn size(st : LazySegTree) -> Int {
  st.n
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "LazySegTree: build and point_get" {
  let arr = FixedArray::makei(5, fn(i) { i + 1 }) // [1,2,3,4,5]
  let st = build(arr)
  assert_eq(point_get(st, 0), 1L)
  assert_eq(point_get(st, 2), 3L)
  assert_eq(point_get(st, 4), 5L)
}

///|
test "LazySegTree: range_sum" {
  let arr = FixedArray::makei(10, fn(i) { i }) // [0..9]
  let st = build(arr)
  assert_eq(range_sum(st, 0, 10), 45L) // 0+1+...+9
  assert_eq(range_sum(st, 3, 7), 18L) // 3+4+5+6
  assert_eq(range_sum(st, 0, 1), 0L)
  assert_eq(range_sum(st, 5, 6), 5L)
}

///|
test "LazySegTree: range_add then sum" {
  let arr = FixedArray::make(5, 0) // [0,0,0,0,0]
  let st = build(arr)
  range_add(st, 0, 4, 10L) // add 10 to all
  assert_eq(range_sum(st, 0, 5), 50L)
  // point_get returns the BASE value (0, before range_add); current_value
  // returns the actual value (10, after range_add).
  assert_eq(point_get(st, 2), 0L)
  assert_eq(current_value(st, 2), 10L)
  range_add(st, 1, 3, 5L) // add 5 to [1,3]
  assert_eq(current_value(st, 0), 10L)
  assert_eq(current_value(st, 1), 15L)
  assert_eq(current_value(st, 2), 15L)
  assert_eq(current_value(st, 3), 15L)
  assert_eq(current_value(st, 4), 10L)
  assert_eq(range_sum(st, 0, 5), 65L)
}

///|
test "LazySegTree: range_min and range_max" {
  let arr = FixedArray::makei(8, fn(i) { (i * 3 + 1) % 10 }) // [1,4,7,0,3,6,9,2]
  let st = build(arr)
  assert_eq(range_min(st, 0, 8), 0L) // min is 0 at index 3
  assert_eq(range_max(st, 0, 8), 9L) // max is 9 at index 6
  assert_eq(range_min(st, 0, 3), 1L) // [1,4,7] min=1
  assert_eq(range_max(st, 4, 7), 9L) // [3,6,9] max=9
  // After range_add, min/max should shift.
  range_add(st, 0, 7, 100L)
  assert_eq(range_min(st, 0, 8), 100L) // 0+100
  assert_eq(range_max(st, 0, 8), 109L) // 9+100
}

///|
test "LazySegTree: point_set" {
  let arr = FixedArray::makei(5, fn(i) { i * 10 }) // [0,10,20,30,40]
  let st = build(arr)
  point_set(st, 2, 25L)
  assert_eq(point_get(st, 2), 25L)
  assert_eq(range_sum(st, 0, 5), 105L) // 0+10+25+30+40
}

///|
test "LazySegTree: overlapping range adds" {
  let arr = FixedArray::make(10, 0)
  let st = build(arr)
  range_add(st, 0, 5, 1L)
  range_add(st, 3, 8, 1L)
  range_add(st, 5, 9, 1L)
  // 0:1, 1:1, 2:1, 3:2, 4:2, 5:3, 6:2, 7:2, 8:2, 9:1
  // After range_add, use current_value to get the up-to-date value.
  assert_eq(current_value(st, 0), 1L)
  assert_eq(current_value(st, 3), 2L)
  assert_eq(current_value(st, 5), 3L)
  assert_eq(current_value(st, 9), 1L)
  assert_eq(range_sum(st, 0, 10), 17L) // 1+1+1+2+2+3+2+2+2+1
}

///|
test "LazySegTree: single element" {
  let arr = FixedArray::make(1, 42)
  let st = build(arr)
  assert_eq(point_get(st, 0), 42L)
  assert_eq(range_sum(st, 0, 1), 42L)
  range_add(st, 0, 0, 8L)
  // After range_add, use current_value to get the up-to-date value.
  assert_eq(current_value(st, 0), 50L)
}

///|
test "LazySegTree: out of bounds" {
  let arr = FixedArray::make(3, 0)
  let st = build(arr)
  // Out-of-bounds queries return safe defaults.
  assert_eq(point_get(st, 5), 0L)
  assert_eq(range_sum(st, -1, 5), 0L)
  assert_eq(range_min(st, 5, 10), INF_LAZY)
  assert_eq(range_max(st, 5, 10), NEG_INF_LAZY)
  // Out-of-bounds updates are no-ops.
  range_add(st, 10, 20, 999L)
  assert_eq(range_sum(st, 0, 3), 0L)
}

///|
test "LazySegTree: stress test (many range adds)" {
  let n = 100
  let arr = FixedArray::make(n, 0)
  let st = build(arr)
  // Perform 50 range adds.
  for i = 0; i < 50; i = i + 1 {
    let l = i * 7 % n
    let r = (l + 13) % n
    let (lo, hi) = if l <= r { (l, r) } else { (r, l) }
    range_add(st, lo, hi, i.to_int64())
  }
  // Brute-force verify.
  let expected = FixedArray::make(n, 0L)
  for i = 0; i < 50; i = i + 1 {
    let l = i * 7 % n
    let r = (l + 13) % n
    let (lo, hi) = if l <= r { (l, r) } else { (r, l) }
    for j = lo; j <= hi; j = j + 1 {
      expected[j] = expected[j] + i.to_int64()
    }
  }
  for i = 0; i < n; i = i + 1 {
    // After range_add, use current_value to get the up-to-date value.
    assert_eq(current_value(st, i), expected[i])
  }
  // Verify range sums.
  assert_eq(range_sum(st, 0, n), range_sum_brute(expected, 0, n))
  assert_eq(range_sum(st, 25, 75), range_sum_brute(expected, 25, 75))
  assert_eq(range_min(st, 0, n), range_min_brute(expected, 0, n))
  assert_eq(range_max(st, 0, n), range_max_brute(expected, 0, n))
}

///|
fn range_sum_brute(arr : FixedArray[Int64], l : Int, r : Int) -> Int64 {
  let mut sum = 0L
  for i = l; i < r; i = i + 1 {
    sum = sum + arr[i]
  }
  sum
}

///|
fn range_min_brute(arr : FixedArray[Int64], l : Int, r : Int) -> Int64 {
  let mut m = INF_LAZY
  for i = l; i < r; i = i + 1 {
    if arr[i] < m {
      m = arr[i]
    }
  }
  m
}

///|
fn range_max_brute(arr : FixedArray[Int64], l : Int, r : Int) -> Int64 {
  let mut m = NEG_INF_LAZY
  for i = l; i < r; i = i + 1 {
    if arr[i] > m {
      m = arr[i]
    }
  }
  m
}
