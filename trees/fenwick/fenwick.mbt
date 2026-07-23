/// Fenwick Tree (Binary Indexed Tree).
///
/// Supports point updates and prefix-sum queries in O(log n). Internally the
/// tree is 1-indexed: `tree[i]` stores the partial sum of the range
/// `(i - lowbit(i), i]`. The public API is also 1-indexed — position `1`
/// corresponds to the first element of the source array.
///
/// `build` runs in O(n) by first copying the input and then propagating each
/// cell's value to its parent in a single bottom-up pass.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below,
/// including brute-force cross-checks on large arrays.

/// 1-indexed Fenwick tree. `tree` has length `n + 1`; index 0 is unused.
pub struct Fenwick {
  tree : FixedArray[Int]
  n : Int
}

/// Build a Fenwick tree from a 0-indexed array in O(n).
///
/// Element `arr[i]` becomes internal position `i + 1`.
pub fn build(arr : FixedArray[Int]) -> Fenwick {
  let n = arr.length()
  let tree = FixedArray::make(n + 1, 0)
  // Copy the input into 1-indexed positions.
  for i = 1; i <= n; i = i + 1 {
    tree[i] = arr[i - 1]
  }
  // Propagate each cell to its parent in one bottom-up pass.
  for i = 1; i <= n; i = i + 1 {
    let j = i + (i & (-i))
    if j <= n {
      tree[j] = tree[j] + tree[i]
    }
  }
  { tree, n }
}

/// Add `delta` to the element at 1-indexed position `idx`.
/// No-op when `idx` is out of bounds (`idx < 1` or `idx > n`).
pub fn update(ft : Fenwick, idx : Int, delta : Int) -> Unit {
  if idx < 1 || idx > ft.n {
    return
  }
  let mut i = idx
  while i <= ft.n {
    ft.tree[i] = ft.tree[i] + delta
    i = i + (i & (-i))
  }
}

/// Prefix sum of positions `[1, idx]`.
/// Returns `0` when `idx <= 0`. For `idx > n` the sum is clamped to `[1, n]`.
pub fn query(ft : Fenwick, idx : Int) -> Int {
  if idx <= 0 {
    return 0
  }
  let mut i = idx
  if i > ft.n {
    i = ft.n
  }
  let mut sum = 0
  while i > 0 {
    sum = sum + ft.tree[i]
    i = i - (i & (-i))
  }
  sum
}

/// Inclusive sum of positions `[l, r]`.
/// Returns `0` for empty or entirely out-of-bounds ranges. Otherwise the
/// bounds are clamped to `[1, n]` before computing `query(r) - query(l - 1)`.
pub fn range_query(ft : Fenwick, l : Int, r : Int) -> Int {
  if l > r || r < 1 || l > ft.n {
    return 0
  }
  let cl = if l < 1 { 1 } else { l }
  let cr = if r > ft.n { ft.n } else { r }
  query(ft, cr) - query(ft, cl - 1)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "fenwick: build and query full range" {
  let arr = FixedArray::makei(5, fn(i) { i + 1 }) // [1, 2, 3, 4, 5]
  let ft = build(arr)
  assert_eq(query(ft, 5), 15)
}

test "fenwick: query single element" {
  let arr = FixedArray::makei(5, fn(i) { i + 1 }) // [1, 2, 3, 4, 5]
  let ft = build(arr)
  assert_eq(query(ft, 1), 1) // prefix [1,1]
  assert_eq(query(ft, 3), 6) // prefix [1,3] = 1+2+3
  assert_eq(query(ft, 5), 15) // prefix [1,5] = 1+2+3+4+5
}

test "fenwick: point update" {
  let arr = FixedArray::makei(5, fn(i) { i + 1 }) // [1, 2, 3, 4, 5]
  let ft = build(arr)
  update(ft, 3, 10) // arr[2] = 3 + 10 = 13
  assert_eq(query(ft, 3), 16) // 1 + 2 + 13
  assert_eq(query(ft, 5), 25) // 1 + 2 + 13 + 4 + 5
}

test "fenwick: range query" {
  let arr = FixedArray::makei(5, fn(i) { i + 1 }) // [1, 2, 3, 4, 5]
  let ft = build(arr)
  assert_eq(range_query(ft, 1, 5), 15)
  assert_eq(range_query(ft, 2, 4), 9) // 2 + 3 + 4
  assert_eq(range_query(ft, 3, 3), 3) // single element
}

test "fenwick: single element array" {
  let arr = FixedArray::make(1, 42)
  let ft = build(arr)
  assert_eq(query(ft, 1), 42)
  assert_eq(query(ft, 0), 0)
  update(ft, 1, 8)
  assert_eq(query(ft, 1), 50)
}

test "fenwick: negative values" {
  let arr = FixedArray::make(4, 0)
  arr[0] = -1
  arr[1] = -2
  arr[2] = 3
  arr[3] = -4
  let ft = build(arr)
  assert_eq(query(ft, 4), -4) // -1 + -2 + 3 + -4
  assert_eq(query(ft, 2), -3) // -1 + -2
  assert_eq(range_query(ft, 3, 4), -1) // 3 + -4
  assert_eq(range_query(ft, 1, 3), 0) // -1 + -2 + 3
}

test "fenwick: large array with brute-force cross-check" {
  let n = 100
  let arr = FixedArray::makei(n, fn(i) { (i * 3 + 7) % 17 - 5 })
  let ft = build(arr)
  // Full range
  let mut expected_total = 0
  for i = 0; i < n; i = i + 1 {
    expected_total = expected_total + arr[i]
  }
  assert_eq(query(ft, n), expected_total)
  // Cross-check prefix sums and range sums against brute force.
  for start = 0; start < n; start = start + 7 {
    for end = start; end < n; end = end + 11 {
      let mut expected = 0
      for k = start; k <= end; k = k + 1 {
        expected = expected + arr[k]
      }
      assert_eq(range_query(ft, start + 1, end + 1), expected)
    }
  }
}

test "fenwick: multiple updates" {
  // [1, 2, 3, 4, 5] after updates: [101, 2, 53, 4, 205]
  let arr = FixedArray::makei(5, fn(i) { i + 1 })
  let ft = build(arr)
  update(ft, 1, 100)
  update(ft, 5, 200)
  update(ft, 3, 50)
  assert_eq(query(ft, 1), 101)
  assert_eq(range_query(ft, 5, 5), 205)
  assert_eq(range_query(ft, 3, 3), 53)
  assert_eq(query(ft, 5), 365) // 101 + 2 + 53 + 4 + 205
  assert_eq(range_query(ft, 1, 5), 365)
  assert_eq(range_query(ft, 2, 4), 59) // 2 + 53 + 4
}

test "fenwick: query idx <= 0 returns 0" {
  let arr = FixedArray::makei(5, fn(i) { i + 1 })
  let ft = build(arr)
  assert_eq(query(ft, 0), 0)
  assert_eq(query(ft, -1), 0)
  assert_eq(query(ft, -100), 0)
}

test "fenwick: query idx > n clamps to full range" {
  let arr = FixedArray::makei(5, fn(i) { i + 1 })
  let ft = build(arr)
  assert_eq(query(ft, 6), 15)
  assert_eq(query(ft, 100), 15)
}

test "fenwick: update out of bounds is no-op" {
  let arr = FixedArray::makei(5, fn(i) { i + 1 })
  let ft = build(arr)
  update(ft, 0, 999)
  update(ft, 6, 999)
  update(ft, -1, 999)
  assert_eq(query(ft, 5), 15) // unchanged
}

test "fenwick: range query edge cases" {
  let arr = FixedArray::makei(5, fn(i) { i + 1 })
  let ft = build(arr)
  // l > r
  assert_eq(range_query(ft, 3, 1), 0)
  assert_eq(range_query(ft, 5, 2), 0)
  // entirely below range
  assert_eq(range_query(ft, -2, 0), 0)
  // entirely above range
  assert_eq(range_query(ft, 6, 10), 0)
  // clamped range
  assert_eq(range_query(ft, 0, 3), 6) // 1 + 2 + 3
  assert_eq(range_query(ft, 3, 10), 12) // 3 + 4 + 5
}

test "fenwick: empty array" {
  let arr : FixedArray[Int] = FixedArray::make(0, 0)
  let ft = build(arr)
  assert_eq(query(ft, 1), 0)
  assert_eq(range_query(ft, 1, 1), 0)
  update(ft, 1, 42) // no-op, should not crash
  assert_eq(query(ft, 1), 0)
}

test "fenwick: update then query consistency" {
  let n = 50
  let arr = FixedArray::makei(n, fn(i) { i + 1 })
  let ft = build(arr)
  // Apply the same updates to a brute-force array and compare.
  let brute = FixedArray::makei(n, fn(i) { i + 1 })
  for k = 0; k < n; k = k + 1 {
    let delta = (k * 7 + 3) % 11 - 5
    update(ft, k + 1, delta)
    brute[k] = brute[k] + delta
  }
  for i = 1; i <= n; i = i + 1 {
    let mut expected = 0
    for j = 1; j <= i; j = j + 1 {
      expected = expected + brute[j - 1]
    }
    assert_eq(query(ft, i), expected)
  }
}
