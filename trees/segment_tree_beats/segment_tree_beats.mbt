///|
/// Segment Tree Beats (ji driver segment tree) for range chmin/chmax/sum queries.
///
/// An advanced segment tree that supports:
/// - **Range chmin**: `a[i] = min(a[i], x)` for all `i` in `[l, r]`
/// - **Range chmax**: `a[i] = max(a[i], x)` for all `i` in `[l, r]`
/// - **Range add**: `a[i] += x` for all `i` in `[l, r]`
/// - **Range sum**: `sum(a[l..r])`
///
/// ## Algorithm
///
/// The key idea is to maintain for each node the **maximum** (`max1`), **second
/// maximum** (`max2`), **minimum** (`min1`), **second minimum** (`min2`),
/// the count of max/min elements, and lazy tags for chmin, chmax, and add.
///
/// When a chmin operation is applied:
/// - If `x >= max1`, no change needed (nothing decreases).
/// - If `max2 < x < max1`, only the maximum values change to `x`; update
///   `max1` and the lazy chmin tag.
/// - Otherwise (`x <= max2`), recurse into children.
///
/// This "beat" condition bounds the number of tag changes to O(n log n)
/// amortised across all operations, giving O(log² n) per operation in the
/// worst case (but O(log n) amortised for many practical inputs).
///
/// ## Complexity
///
/// - Build: O(n)
/// - Range chmin/chmax: O(log² n) worst case, O(log n) amortised
/// - Range add: O(log n)
/// - Range sum: O(log n)
///
/// All values are stored as `Int64` to prevent overflow on sums.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const NEG_INF : Int64 = -9223372036854775808L

///|
const POS_INF : Int64 = 9223372036854775807L

// ---------------------------------------------------------------------------
// Node structure
// ---------------------------------------------------------------------------

///|
/// A node in the Segment Tree Beats.
///
/// Each node covers a range `[lo, hi]` and maintains:
/// - `sum`: the sum of all values in the range
/// - `max1`: the maximum value
/// - `max2`: the second maximum (or NEG_INF if all values are equal)
/// - `max_cnt`: the number of elements equal to `max1`
/// - `min1`: the minimum value
/// - `min2`: the second minimum (or POS_INF if all values are equal)
/// - `min_cnt`: the number of elements equal to `min1`
/// - `len`: the range length
/// - Lazy tags: `laz_add`, `laz_chmin`, `laz_chmax`
struct Node {
  mut sum : Int64
  mut max1 : Int64
  mut max2 : Int64
  mut max_cnt : Int64
  mut min1 : Int64
  mut min2 : Int64
  mut min_cnt : Int64
  mut len : Int64
  mut laz_add : Int64
  mut laz_chmin : Int64 // applied chmin value (POS_INF = no pending chmin)
  mut laz_chmax : Int64 // applied chmax value (NEG_INF = no pending chmax)
}

///|
fn make_node() -> Node {
  {
    sum: 0L,
    max1: NEG_INF,
    max2: NEG_INF,
    max_cnt: 0L,
    min1: POS_INF,
    min2: POS_INF,
    min_cnt: 0L,
    len: 0L,
    laz_add: 0L,
    laz_chmin: POS_INF,
    laz_chmax: NEG_INF,
  }
}

// ---------------------------------------------------------------------------
// Segment Tree Beats
// ---------------------------------------------------------------------------

///|
/// A Segment Tree Beats supporting range chmin, chmax, add, and sum queries.
pub struct SegBeats {
  n : Int
  tree : FixedArray[Node]
}

///|
/// Build a Segment Tree Beats from an initial `Int64` array.
pub fn build(arr : FixedArray[Int64], n : Int) -> SegBeats {
  // FixedArray::make(size, val) evaluates val once and shares the reference
  // across all slots. Since Node is a reference type, this would make every
  // tree entry alias the same mutable object. Using makei ensures each slot
  // gets a distinct Node.
  let tree = FixedArray::makei(4 * n + 4, fn(_i) { make_node() })
  let sb = { n, tree }
  if n > 0 {
    build_rec(sb, 1, 0, n - 1, arr)
  }
  sb
}

///|
fn build_rec(
  sb : SegBeats,
  node : Int,
  lo : Int,
  hi : Int,
  arr : FixedArray[Int64],
) -> Unit {
  sb.tree[node].len = (hi - lo + 1).to_int64()
  if lo == hi {
    let v = arr[lo]
    sb.tree[node].sum = v
    sb.tree[node].max1 = v
    sb.tree[node].max2 = NEG_INF
    sb.tree[node].max_cnt = 1L
    sb.tree[node].min1 = v
    sb.tree[node].min2 = POS_INF
    sb.tree[node].min_cnt = 1L
    return
  }
  let mid = (lo + hi) / 2
  build_rec(sb, node * 2, lo, mid, arr)
  build_rec(sb, node * 2 + 1, mid + 1, hi, arr)
  pull_up(sb, node)
}

///|
/// Combine two children into the parent.
fn pull_up(sb : SegBeats, node : Int) -> Unit {
  let l = sb.tree[node * 2]
  let r = sb.tree[node * 2 + 1]
  sb.tree[node].sum = l.sum + r.sum
  sb.tree[node].len = l.len + r.len

  // Merge max1, max2, max_cnt.
  if l.max1 == r.max1 {
    sb.tree[node].max1 = l.max1
    sb.tree[node].max_cnt = l.max_cnt + r.max_cnt
    sb.tree[node].max2 = if l.max2 > r.max2 { l.max2 } else { r.max2 }
  } else if l.max1 > r.max1 {
    sb.tree[node].max1 = l.max1
    sb.tree[node].max_cnt = l.max_cnt
    sb.tree[node].max2 = if l.max2 > r.max1 { l.max2 } else { r.max1 }
  } else {
    sb.tree[node].max1 = r.max1
    sb.tree[node].max_cnt = r.max_cnt
    sb.tree[node].max2 = if r.max2 > l.max1 { r.max2 } else { l.max1 }
  }

  // Merge min1, min2, min_cnt.
  if l.min1 == r.min1 {
    sb.tree[node].min1 = l.min1
    sb.tree[node].min_cnt = l.min_cnt + r.min_cnt
    sb.tree[node].min2 = if l.min2 < r.min2 { l.min2 } else { r.min2 }
  } else if l.min1 < r.min1 {
    sb.tree[node].min1 = l.min1
    sb.tree[node].min_cnt = l.min_cnt
    sb.tree[node].min2 = if l.min2 < r.min1 { l.min2 } else { r.min1 }
  } else {
    sb.tree[node].min1 = r.min1
    sb.tree[node].min_cnt = r.min_cnt
    sb.tree[node].min2 = if r.min2 < l.min1 { r.min2 } else { l.min1 }
  }
}

///|
/// Apply an additive lazy tag to a node.
fn apply_add(sb : SegBeats, node : Int, v : Int64) -> Unit {
  let n = sb.tree[node]
  n.sum = n.sum + v * n.len
  n.max1 = n.max1 + v
  if n.max2 != NEG_INF {
    n.max2 = n.max2 + v
  }
  n.min1 = n.min1 + v
  if n.min2 != POS_INF {
    n.min2 = n.min2 + v
  }
  n.laz_add = n.laz_add + v
  // Pending chmin/chmax shift with the add.
  if n.laz_chmin != POS_INF {
    n.laz_chmin = n.laz_chmin + v
  }
  if n.laz_chmax != NEG_INF {
    n.laz_chmax = n.laz_chmax + v
  }
}

///|
/// Apply a chmin lazy tag to a node (decrease all values equal to max1 to x).
fn apply_chmin(sb : SegBeats, node : Int, x : Int64) -> Unit {
  let n = sb.tree[node]
  if x >= n.max1 {
    return
  }
  // x < max1. If x <= max2, we must recurse (break the beat).
  // Here we only handle the case x > max2 (safe to apply).
  if x <= n.max2 {
    return // need to recurse
  }
  // Update sum: old max1 values become x.
  n.sum = n.sum - n.max_cnt * (n.max1 - x)
  // If max1 == min1 (all elements equal), also update min1.
  if n.max1 == n.min1 {
    n.min1 = x
  } else if n.max1 == n.min2 {
    n.min2 = x
  }
  n.max1 = x
  n.laz_chmin = x
  // Tag interaction: if a pending chmax tag exceeds x, clamp it.
  // When both tags are present with laz_chmin < laz_chmax (which only
  // occurs when all values in the node are equal), the push_down order
  // would determine the result. By clamping laz_chmax to x, both tags
  // agree on the final value, making push_down order irrelevant.
  if n.laz_chmax != NEG_INF && x < n.laz_chmax {
    n.laz_chmax = x
  }
}

///|
/// Apply a chmax lazy tag to a node (increase all values equal to min1 to x).
fn apply_chmax(sb : SegBeats, node : Int, x : Int64) -> Unit {
  let n = sb.tree[node]
  if x <= n.min1 {
    return
  }
  if x >= n.min2 {
    return // need to recurse
  }
  n.sum = n.sum + n.min_cnt * (x - n.min1)
  if n.min1 == n.max1 {
    n.max1 = x
  } else if n.min1 == n.max2 {
    n.max2 = x
  }
  n.min1 = x
  n.laz_chmax = x
  // Tag interaction: if a pending chmin tag is below x, raise it.
  // Symmetric to the clamping in apply_chmin: when both tags are present
  // with laz_chmin < laz_chmax, raising laz_chmin to x makes both tags
  // agree, ensuring push_down order doesn't matter.
  if n.laz_chmin != POS_INF && x > n.laz_chmin {
    n.laz_chmin = x
  }
}

///|
/// Push lazy tags down to children.
fn push_down(sb : SegBeats, node : Int) -> Unit {
  let n = sb.tree[node]
  // Apply add first.
  if n.laz_add != 0L {
    apply_add(sb, node * 2, n.laz_add)
    apply_add(sb, node * 2 + 1, n.laz_add)
    n.laz_add = 0L
  }
  // Apply chmin.
  if n.laz_chmin != POS_INF {
    apply_chmin(sb, node * 2, n.laz_chmin)
    apply_chmin(sb, node * 2 + 1, n.laz_chmin)
    n.laz_chmin = POS_INF
  }
  // Apply chmax.
  if n.laz_chmax != NEG_INF {
    apply_chmax(sb, node * 2, n.laz_chmax)
    apply_chmax(sb, node * 2 + 1, n.laz_chmax)
    n.laz_chmax = NEG_INF
  }
}

// ---------------------------------------------------------------------------
// Public operations
// ---------------------------------------------------------------------------

///|
/// Range sum query on `[ql, qr]` (0-indexed, inclusive).
pub fn range_sum(sb : SegBeats, ql : Int, qr : Int) -> Int64 {
  range_sum_rec(sb, 1, 0, sb.n - 1, ql, qr)
}

///|
fn range_sum_rec(
  sb : SegBeats,
  node : Int,
  lo : Int,
  hi : Int,
  ql : Int,
  qr : Int,
) -> Int64 {
  if ql > hi || qr < lo {
    return 0L
  }
  if ql <= lo && hi <= qr {
    return sb.tree[node].sum
  }
  push_down(sb, node)
  let mid = (lo + hi) / 2
  range_sum_rec(sb, node * 2, lo, mid, ql, qr) +
  range_sum_rec(sb, node * 2 + 1, mid + 1, hi, ql, qr)
}

///|
/// Range chmin: set `a[i] = min(a[i], x)` for all `i` in `[ql, qr]`.
pub fn range_chmin(sb : SegBeats, ql : Int, qr : Int, x : Int64) -> Unit {
  range_chmin_rec(sb, 1, 0, sb.n - 1, ql, qr, x)
}

///|
fn range_chmin_rec(
  sb : SegBeats,
  node : Int,
  lo : Int,
  hi : Int,
  ql : Int,
  qr : Int,
  x : Int64,
) -> Unit {
  if ql > hi || qr < lo || x >= sb.tree[node].max1 {
    return
  }
  if ql <= lo && hi <= qr && x > sb.tree[node].max2 {
    apply_chmin(sb, node, x)
    return
  }
  push_down(sb, node)
  let mid = (lo + hi) / 2
  range_chmin_rec(sb, node * 2, lo, mid, ql, qr, x)
  range_chmin_rec(sb, node * 2 + 1, mid + 1, hi, ql, qr, x)
  pull_up(sb, node)
}

///|
/// Range chmax: set `a[i] = max(a[i], x)` for all `i` in `[ql, qr]`.
pub fn range_chmax(sb : SegBeats, ql : Int, qr : Int, x : Int64) -> Unit {
  range_chmax_rec(sb, 1, 0, sb.n - 1, ql, qr, x)
}

///|
fn range_chmax_rec(
  sb : SegBeats,
  node : Int,
  lo : Int,
  hi : Int,
  ql : Int,
  qr : Int,
  x : Int64,
) -> Unit {
  if ql > hi || qr < lo || x <= sb.tree[node].min1 {
    return
  }
  if ql <= lo && hi <= qr && x < sb.tree[node].min2 {
    apply_chmax(sb, node, x)
    return
  }
  push_down(sb, node)
  let mid = (lo + hi) / 2
  range_chmax_rec(sb, node * 2, lo, mid, ql, qr, x)
  range_chmax_rec(sb, node * 2 + 1, mid + 1, hi, ql, qr, x)
  pull_up(sb, node)
}

///|
/// Range add: add `x` to all `a[i]` for `i` in `[ql, qr]`.
pub fn range_add(sb : SegBeats, ql : Int, qr : Int, x : Int64) -> Unit {
  range_add_rec(sb, 1, 0, sb.n - 1, ql, qr, x)
}

///|
fn range_add_rec(
  sb : SegBeats,
  node : Int,
  lo : Int,
  hi : Int,
  ql : Int,
  qr : Int,
  x : Int64,
) -> Unit {
  if ql > hi || qr < lo {
    return
  }
  if ql <= lo && hi <= qr {
    apply_add(sb, node, x)
    return
  }
  push_down(sb, node)
  let mid = (lo + hi) / 2
  range_add_rec(sb, node * 2, lo, mid, ql, qr, x)
  range_add_rec(sb, node * 2 + 1, mid + 1, hi, ql, qr, x)
  pull_up(sb, node)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "beats: basic range sum" {
  let arr = FixedArray::make(5, 0L)
  for i = 0; i < 5; i = i + 1 {
    arr[i] = (i + 1).to_int64()
  }
  let sb = build(arr, 5)
  // Sum of [0..4] = 1+2+3+4+5 = 15
  assert_eq(range_sum(sb, 0, 4), 15L)
  // Sum of [1..3] = 2+3+4 = 9
  assert_eq(range_sum(sb, 1, 3), 9L)
}

///|
test "beats: range add" {
  let arr = FixedArray::make(5, 0L)
  for i = 0; i < 5; i = i + 1 {
    arr[i] = (i + 1).to_int64()
  }
  let sb = build(arr, 5)
  range_add(sb, 0, 4, 10L)
  // Now all values are 11..15, sum = 65
  assert_eq(range_sum(sb, 0, 4), 65L)
  range_add(sb, 1, 3, 5L)
  // 11 + 17 + 18 + 19 + 15 = 80
  assert_eq(range_sum(sb, 0, 4), 80L)
}

///|
test "beats: range chmin" {
  let arr = FixedArray::make(5, 0L)
  for i = 0; i < 5; i = i + 1 {
    arr[i] = (i * 2 + 2).to_int64() // [2, 4, 6, 8, 10]
  }
  let sb = build(arr, 5)
  // chmin all to 5: [2, 4, 5, 5, 5], sum = 21
  range_chmin(sb, 0, 4, 5L)
  assert_eq(range_sum(sb, 0, 4), 21L)
  // chmin all to 3: [2, 3, 3, 3, 3], sum = 14
  range_chmin(sb, 0, 4, 3L)
  assert_eq(range_sum(sb, 0, 4), 14L)
}

///|
test "beats: range chmax" {
  let arr = FixedArray::make(5, 0L)
  for i = 0; i < 5; i = i + 1 {
    arr[i] = (i * 2 + 2).to_int64() // [2, 4, 6, 8, 10]
  }
  let sb = build(arr, 5)
  // chmax all to 5: [5, 5, 6, 8, 10], sum = 34
  range_chmax(sb, 0, 4, 5L)
  assert_eq(range_sum(sb, 0, 4), 34L)
  // chmax all to 7: [7, 7, 7, 8, 10], sum = 39
  range_chmax(sb, 0, 4, 7L)
  assert_eq(range_sum(sb, 0, 4), 39L)
}

///|
test "beats: mixed operations" {
  let arr = FixedArray::make(5, 0L)
  for i = 0; i < 5; i = i + 1 {
    arr[i] = 10L
  }
  let sb = build(arr, 5)
  // All 10s. chmax [0..2] to 15: [15, 15, 15, 10, 10], sum = 65
  range_chmax(sb, 0, 2, 15L)
  assert_eq(range_sum(sb, 0, 4), 65L)
  // chmin all to 12: [12, 12, 12, 10, 10], sum = 56
  range_chmin(sb, 0, 4, 12L)
  assert_eq(range_sum(sb, 0, 4), 56L)
  // add 5 to [3..4]: [12, 12, 12, 15, 15], sum = 66
  range_add(sb, 3, 4, 5L)
  assert_eq(range_sum(sb, 0, 4), 66L)
  // chmin all to 13: [12, 12, 12, 13, 13], sum = 62
  range_chmin(sb, 0, 4, 13L)
  assert_eq(range_sum(sb, 0, 4), 62L)
}

///|
test "beats: chmin on subrange" {
  let arr = FixedArray::make(6, 0L)
  for i = 0; i < 6; i = i + 1 {
    arr[i] = (i + 1).to_int64() // [1,2,3,4,5,6]
  }
  let sb = build(arr, 6)
  // chmin [2..4] to 3: [1,2,3,3,3,6], sum = 18
  range_chmin(sb, 2, 4, 3L)
  assert_eq(range_sum(sb, 0, 5), 18L)
  assert_eq(range_sum(sb, 2, 4), 9L)
}

///|
test "beats: chmax on subrange" {
  let arr = FixedArray::make(6, 0L)
  for i = 0; i < 6; i = i + 1 {
    arr[i] = (i + 1).to_int64() // [1,2,3,4,5,6]
  }
  let sb = build(arr, 6)
  // chmax [0..2] to 5: [5,5,5,4,5,6], sum = 30
  range_chmax(sb, 0, 2, 5L)
  assert_eq(range_sum(sb, 0, 5), 30L)
}

///|
test "beats: stress test against brute force" {
  let n = 100
  let arr = FixedArray::make(n, 0L)
  for i = 0; i < n; i = i + 1 {
    arr[i] = ((i * 7 + 3) % 50).to_int64()
  }
  let sb = build(arr, n)
  // Brute force array.
  let brute = FixedArray::make(n, 0L)
  for i = 0; i < n; i = i + 1 {
    brute[i] = arr[i]
  }
  // Run 50 operations and verify sum after each.
  for op = 0; op < 50; op = op + 1 {
    let l = (op * 7 + 3) % n
    let r = (op * 13 + 11) % n
    let (ql, qr) = if l <= r { (l, r) } else { (r, l) }
    match op % 3 {
      0 => {
        // chmin
        let x = ((op * 5 + 7) % 50).to_int64()
        range_chmin(sb, ql, qr, x)
        for i = ql; i <= qr; i = i + 1 {
          if brute[i] > x {
            brute[i] = x
          }
        }
      }
      1 => {
        // chmax
        let x = ((op * 5 + 7) % 50).to_int64()
        range_chmax(sb, ql, qr, x)
        for i = ql; i <= qr; i = i + 1 {
          if brute[i] < x {
            brute[i] = x
          }
        }
      }
      _ => {
        // add
        let x = ((op * 3 + 1) % 20).to_int64()
        range_add(sb, ql, qr, x)
        for i = ql; i <= qr; i = i + 1 {
          brute[i] = brute[i] + x
        }
      }
    }
    // Verify sum on a few ranges.
    for check = 0; check < 3; check = check + 1 {
      let cl = (check * 11 + op * 3) % n
      let cr = (check * 17 + op * 5) % n
      let (cl2, cr2) = if cl <= cr { (cl, cr) } else { (cr, cl) }
      let mut brute_sum = 0L
      for i = cl2; i <= cr2; i = i + 1 {
        brute_sum = brute_sum + brute[i]
      }
      assert_eq(range_sum(sb, cl2, cr2), brute_sum)
    }
  }
}

///|
test "beats: single element" {
  let arr = FixedArray::make(1, 0L)
  arr[0] = 42L
  let sb = build(arr, 1)
  assert_eq(range_sum(sb, 0, 0), 42L)
  range_chmin(sb, 0, 0, 30L)
  assert_eq(range_sum(sb, 0, 0), 30L)
  range_chmax(sb, 0, 0, 50L)
  assert_eq(range_sum(sb, 0, 0), 50L)
}
