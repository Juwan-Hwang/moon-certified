/// Sparse Table: O(1) range-minimum (or range-maximum) queries.
///
/// Preprocesses an array in O(n log n) time and space, then answers range
/// queries in O(1). The operation must be **idempotent** (e.g. min, max, gcd);
/// range-sum queries are not supported because they cannot overlap.
///
/// The table stores `st[k][i]` = result of combining the range
/// `[i, i + 2^k - 1]`. A query `[l, r]` is answered by splitting into two
/// overlapping halves of length `2^k` where `k = floor(log2(r - l + 1))`.
///
/// Complexity:
/// - `build(arr, cmp)` — O(n log n) time, O(n log n) space.
/// - `query(l, r)`     — O(1).
///
/// Limitations:
/// - The underlying array is immutable once the table is built.
/// - `cmp(a, b)` must return the "preferred" value: for range-min use
///   `(a, b) => if a <= b { a } else { b }`; for range-max use the opposite.
/// - Query indices `l` and `r` must satisfy `0 ≤ l ≤ r < n`. Invalid ranges
///   return `None`.

/// Sparse table for idempotent range queries.
///
/// `table[k]` holds the combined values for all windows of length `2^k`.
/// `log2_table[i]` = floor(log2(i)) for O(1) log2 lookup.
pub struct SparseTable[T] {
  table : Array[Array[T]]
  log2_table : FixedArray[Int]
  length : Int
  combine : (T, T) -> T
}

/// Build a sparse table over `arr` using the idempotent `combine` function.
///
/// `combine` must be associative and idempotent: `combine(x, x) == x`.
/// For range-min queries, pass `(a, b) => if a <= b { a } else { b }`.
pub fn[T] build(
  arr : Array[T],
  combine : (T, T) -> T,
) -> SparseTable[T] {
  let n = arr.length()
  if n == 0 {
    return { table: [], log2_table: FixedArray::make(1, 0), length: 0, combine }
  }
  // Precompute floor(log2) for all possible lengths
  let log2_table = FixedArray::make(n + 1, 0)
  for i = 2; i <= n; i = i + 1 {
    log2_table[i] = log2_table[i / 2] + 1
  }
  let k = log2_table[n] + 1
  // table[k][i] = combine over [i, i + 2^k - 1]
  let table = []
  // Level 0: single elements
  let level0 = []
  for i = 0; i < n; i = i + 1 {
    level0.push(arr[i])
  }
  table.push(level0)
  // Level j: combine two halves of length 2^(j-1)
  for j = 1; j < k; j = j + 1 {
    let prev = table[j - 1]
    let half = 1 << (j - 1) // 2^(j-1)
    let level = []
    let limit = n - (1 << j) + 1 // last valid start index
    for i = 0; i < limit; i = i + 1 {
      level.push(combine(prev[i], prev[i + half]))
    }
    table.push(level)
  }
  { table, log2_table, length: n, combine }
}

/// Query the combined value over the range `[l, r]` (inclusive, 0-indexed).
/// Returns `None` if `l > r`, `l < 0`, or `r >= length`.
///
/// The two overlapping windows are:
///   `[l, l + 2^k - 1]` and `[r - 2^k + 1, r]`
/// where `k = floor(log2(r - l + 1))`. Because `combine` is idempotent,
/// the overlap does not affect the result.
pub fn[T] query(st : SparseTable[T], l : Int, r : Int) -> T? {
  let n = st.length
  if l < 0 || r >= n || l > r {
    return None
  }
  let len = r - l + 1
  let k = st.log2_table[len]
  let left = st.table[k][l]
  let right = st.table[k][r - (1 << k) + 1]
  Some((st.combine)(left, right))
}

/// Return the number of elements in the table. O(1).
pub fn[T] size(st : SparseTable[T]) -> Int {
  st.length
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn min_of(a : Int, b : Int) -> Int {
  if a <= b { a } else { b }
}

fn max_of(a : Int, b : Int) -> Int {
  if a >= b { a } else { b }
}

fn gcd_of(a : Int, b : Int) -> Int {
  if b == 0 { a } else { gcd_of(b, a % b) }
}

test "sparse_table: range minimum query" {
  let arr = [7, 2, 3, 0, 5, 10, 3, 12, 5]
  let st = build(arr, min_of)
  assert_eq(query(st, 0, 8), Some(0))
  assert_eq(query(st, 0, 3), Some(0))
  assert_eq(query(st, 4, 7), Some(3))
  assert_eq(query(st, 1, 1), Some(2))
  assert_eq(query(st, 0, 0), Some(7))
  assert_eq(query(st, 5, 5), Some(10))
}

test "sparse_table: range maximum query" {
  let arr = [7, 2, 3, 0, 5, 10, 3, 12, 5]
  let st = build(arr, max_of)
  assert_eq(query(st, 0, 8), Some(12))
  assert_eq(query(st, 0, 3), Some(7))
  assert_eq(query(st, 4, 7), Some(12))
  assert_eq(query(st, 1, 4), Some(5))
}

test "sparse_table: single element" {
  let arr = [42]
  let st = build(arr, min_of)
  assert_eq(query(st, 0, 0), Some(42))
  assert_eq(query(st, 0, 1), None) // out of range
}

test "sparse_table: empty array" {
  let arr : Array[Int] = []
  let st = build(arr, min_of)
  assert_eq(size(st), 0)
  assert_eq(query(st, 0, 0), None)
}

test "sparse_table: two elements" {
  let arr = [5, 3]
  let st = build(arr, min_of)
  assert_eq(query(st, 0, 1), Some(3))
  assert_eq(query(st, 0, 0), Some(5))
  assert_eq(query(st, 1, 1), Some(3))
}

test "sparse_table: power-of-two length" {
  let arr = [8, 7, 6, 5, 4, 3, 2, 1]
  let st = build(arr, min_of)
  for l = 0; l < 8; l = l + 1 {
    for r = l; r < 8; r = r + 1 {
      let expected = match query(st, l, r) {
        Some(v) => v
        None => abort("expected Some")
      }
      // Brute force check
      let mut brute = arr[l]
      for i = l + 1; i <= r; i = i + 1 {
        brute = min_of(brute, arr[i])
      }
      assert_eq(expected, brute)
    }
  }
}

test "sparse_table: all same elements" {
  let arr = [5, 5, 5, 5, 5]
  let st = build(arr, min_of)
  assert_eq(query(st, 0, 4), Some(5))
  assert_eq(query(st, 2, 3), Some(5))
}

test "sparse_table: ascending array" {
  let arr = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
  let st = build(arr, min_of)
  assert_eq(query(st, 0, 9), Some(1))
  assert_eq(query(st, 3, 7), Some(4))
  assert_eq(query(st, 9, 9), Some(10))
}

test "sparse_table: descending array" {
  let arr = [10, 9, 8, 7, 6, 5, 4, 3, 2, 1]
  let st = build(arr, min_of)
  assert_eq(query(st, 0, 9), Some(1))
  assert_eq(query(st, 0, 4), Some(6))
  assert_eq(query(st, 5, 9), Some(1))
}

test "sparse_table: large random brute-force check" {
  let arr = [73, 41, 92, 15, 88, 27, 64, 3, 56, 31, 97, 22, 49, 10, 68]
  let st = build(arr, min_of)
  let n = arr.length()
  for l = 0; l < n; l = l + 1 {
    for r = l; r < n; r = r + 1 {
      let mut brute = arr[l]
      for i = l + 1; i <= r; i = i + 1 {
        brute = min_of(brute, arr[i])
      }
      assert_eq(query(st, l, r), Some(brute))
    }
  }
}

test "sparse_table: invalid queries" {
  let arr = [1, 2, 3]
  let st = build(arr, min_of)
  assert_eq(query(st, -1, 2), None)
  assert_eq(query(st, 0, 3), None)
  assert_eq(query(st, 2, 1), None)
}

test "sparse_table: gcd query" {
  let arr = [12, 18, 24, 36, 8]
  let st = build(arr, gcd_of)
  assert_eq(query(st, 0, 4), Some(gcd_of(gcd_of(gcd_of(gcd_of(12, 18), 24), 36), 8)))
  assert_eq(query(st, 0, 1), Some(6))
  assert_eq(query(st, 2, 4), Some(4))
}

test "sparse_table: large array performance" {
  // Build table for 1000 elements and verify all queries
  let n = 1000
  let arr = []
  for i = 0; i < n; i = i + 1 {
    arr.push((i * 37 + 11) % 997)
  }
  let st = build(arr, min_of)
  // Spot-check a few ranges
  assert_true(query(st, 0, 999) is Some(_))
  assert_true(query(st, 500, 750) is Some(_))
  assert_true(query(st, 0, 0) is Some(_))
  assert_true(query(st, 999, 999) is Some(_))
}
