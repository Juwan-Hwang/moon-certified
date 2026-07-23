/// Classic dynamic-programming algorithms on `FixedArray[Int]`.
///
/// Each algorithm builds a standard two-dimensional DP table laid out in a
/// flat `FixedArray` (row-major, index `i * cols + j`). All inputs are
/// validated; degenerate cases (empty arrays, zero capacity, mismatched
/// lengths, negative values) return a safe zero instead of panicking.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

/// Return the maximum of two integers.
fn max2(a : Int, b : Int) -> Int {
  if a >= b {
    a
  } else {
    b
  }
}

/// Return the minimum of two integers.
fn min2(a : Int, b : Int) -> Int {
  if a <= b {
    a
  } else {
    b
  }
}

// ---------------------------------------------------------------------------
// Longest Common Subsequence
// ---------------------------------------------------------------------------

/// Compute the length of the longest common subsequence of two arrays.
///
/// Standard O(n*m) time and space DP. `dp[i][j]` is the LCS length of
/// `a[0..i)` and `b[0..j)`; row 0 and column 0 (empty prefix) stay zero.
/// Empty arrays yield 0.
pub fn lcs(a : FixedArray[Int], b : FixedArray[Int]) -> Int {
  let n = a.length()
  let m = b.length()
  let cols = m + 1
  let dp = FixedArray::make((n + 1) * cols, 0)
  for i = 1; i <= n; i = i + 1 {
    for j = 1; j <= m; j = j + 1 {
      if a[i - 1] == b[j - 1] {
        dp[i * cols + j] = dp[(i - 1) * cols + (j - 1)] + 1
      } else {
        dp[i * cols + j] = max2(dp[(i - 1) * cols + j], dp[i * cols + (j - 1)])
      }
    }
  }
  dp[n * cols + m]
}

// ---------------------------------------------------------------------------
// Edit Distance (Levenshtein)
// ---------------------------------------------------------------------------

/// Compute the minimum edit distance between two arrays.
/// Operations: insert, delete, replace (each costs 1).
///
/// Standard O(n*m) DP. `dp[i][j]` is the edit distance between `a[0..i)` and
/// `b[0..j)`. Transforming to/from an empty prefix costs its own length
/// (pure inserts/deletes), so an empty array yields the length of the other.
pub fn edit_distance(a : FixedArray[Int], b : FixedArray[Int]) -> Int {
  let n = a.length()
  let m = b.length()
  let cols = m + 1
  let dp = FixedArray::make((n + 1) * cols, 0)
  // Base cases: aligning against an empty prefix costs its length.
  for i = 0; i <= n; i = i + 1 {
    dp[i * cols + 0] = i
  }
  for j = 0; j <= m; j = j + 1 {
    dp[0 * cols + j] = j
  }
  for i = 1; i <= n; i = i + 1 {
    for j = 1; j <= m; j = j + 1 {
      if a[i - 1] == b[j - 1] {
        // Last characters match: no extra cost beyond the prefixes.
        dp[i * cols + j] = dp[(i - 1) * cols + (j - 1)]
      } else {
        // delete a[i-1], insert b[j-1], or replace a[i-1] with b[j-1].
        let del = dp[(i - 1) * cols + j] + 1
        let ins = dp[i * cols + (j - 1)] + 1
        let rep = dp[(i - 1) * cols + (j - 1)] + 1
        dp[i * cols + j] = min2(min2(del, ins), rep)
      }
    }
  }
  dp[n * cols + m]
}

// ---------------------------------------------------------------------------
// 0/1 Knapsack
// ---------------------------------------------------------------------------

/// Solve 0/1 knapsack: max value with given weight capacity.
/// weights[i] and values[i] describe item i. Each item used at most once.
///
/// Standard O(n*capacity) DP. `dp[i][w]` is the best value achievable using
/// the first `i` items under capacity `w`; row 0 (no items) is all zero.
/// Returns 0 for invalid inputs: mismatched lengths, negative weights or
/// values, or negative capacity.
///
/// **Memory**: allocates `(n+1) * (capacity+1)` Int values. To prevent OOM,
/// rejects inputs where `n * capacity > 10^7` (≈40MB for Int32).
pub fn knapsack(
  weights : FixedArray[Int],
  values : FixedArray[Int],
  capacity : Int,
) -> Int {
  let n = weights.length()
  // Validate: matching lengths and non-negative weights, values, capacity.
  if n != values.length() || capacity < 0 {
    return 0
  }
  for i = 0; i < n; i = i + 1 {
    if weights[i] < 0 || values[i] < 0 {
      return 0
    }
  }
  // OOM protection: reject inputs that would allocate > 10^7 Int cells.
  // (n+1) * (capacity+1) > 10^7 means ~40MB+ of Int32 values.
  let dp_size = (n + 1) * (capacity + 1)
  if dp_size > 10000000 || dp_size < 0 {
    return 0
  }
  let cols = capacity + 1
  let dp = FixedArray::make(dp_size, 0)
  for i = 1; i <= n; i = i + 1 {
    let wi = weights[i - 1]
    let vi = values[i - 1]
    for w = 0; w <= capacity; w = w + 1 {
      // Best value leaving item i-1 out.
      let best = dp[(i - 1) * cols + w]
      if wi <= w {
        // Optionally take item i-1 when it fits.
        dp[i * cols + w] = max2(best, dp[(i - 1) * cols + (w - wi)] + vi)
      } else {
        dp[i * cols + w] = best
      }
    }
  }
  dp[n * cols + capacity]
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

// --- LCS --------------------------------------------------------------------

test "lcs: basic match" {
  let a = FixedArray::makei(5, fn(i) { i + 1 }) // [1,2,3,4,5]
  let b = FixedArray::make(3, 0)
  b[0] = 2
  b[1] = 4
  b[2] = 5 // [2,4,5]
  assert_eq(lcs(a, b), 3)
}

test "lcs: no match" {
  let a = FixedArray::makei(3, fn(i) { i + 1 }) // [1,2,3]
  let b = FixedArray::makei(3, fn(i) { i + 4 }) // [4,5,6]
  assert_eq(lcs(a, b), 0)
}

test "lcs: one empty" {
  let a = FixedArray::make(0, 0)
  let b = FixedArray::makei(3, fn(i) { i + 1 })
  assert_eq(lcs(a, b), 0)
  assert_eq(lcs(b, a), 0)
}

test "lcs: both empty" {
  let a = FixedArray::make(0, 0)
  let b = FixedArray::make(0, 0)
  assert_eq(lcs(a, b), 0)
}

test "lcs: full match" {
  let a = FixedArray::makei(3, fn(i) { i + 1 })
  let b = FixedArray::makei(3, fn(i) { i + 1 })
  assert_eq(lcs(a, b), 3)
}

test "lcs: partial match" {
  let a = FixedArray::makei(4, fn(i) { i + 1 }) // [1,2,3,4]
  let b = FixedArray::make(4, 0)
  b[0] = 1
  b[1] = 3
  b[2] = 4
  b[3] = 5 // [1,3,4,5]
  assert_eq(lcs(a, b), 3) // [1,3,4]
}

test "lcs: duplicates" {
  let a = FixedArray::make(5, 0)
  a[0] = 1
  a[1] = 1
  a[2] = 2
  a[3] = 2
  a[4] = 3 // [1,1,2,2,3]
  let b = FixedArray::make(4, 0)
  b[0] = 1
  b[1] = 2
  b[2] = 2
  b[3] = 3 // [1,2,2,3]
  assert_eq(lcs(a, b), 4) // [1,2,2,3]
}

// --- Edit distance ----------------------------------------------------------

test "edit_distance: identical arrays" {
  let a = FixedArray::makei(3, fn(i) { i + 1 })
  let b = FixedArray::makei(3, fn(i) { i + 1 })
  assert_eq(edit_distance(a, b), 0)
}

test "edit_distance: one empty" {
  let empty = FixedArray::make(0, 0)
  let other = FixedArray::makei(3, fn(i) { i + 1 })
  assert_eq(edit_distance(empty, other), 3)
  assert_eq(edit_distance(other, empty), 3)
}

test "edit_distance: both empty" {
  let empty = FixedArray::make(0, 0)
  assert_eq(edit_distance(empty, empty), 0)
}

test "edit_distance: completely different" {
  let a = FixedArray::makei(3, fn(i) { i + 1 }) // [1,2,3]
  let b = FixedArray::makei(3, fn(i) { i + 4 }) // [4,5,6]
  assert_eq(edit_distance(a, b), 3)
}

test "edit_distance: partial similarity" {
  let a = FixedArray::makei(4, fn(i) { i + 1 }) // [1,2,3,4]
  let b = FixedArray::make(3, 0)
  b[0] = 1
  b[1] = 2
  b[2] = 4 // [1,2,4]
  assert_eq(edit_distance(a, b), 1) // delete the 3
}

test "edit_distance: single element" {
  let one = FixedArray::make(1, 0)
  one[0] = 1
  let two = FixedArray::make(1, 0)
  two[0] = 2
  assert_eq(edit_distance(one, two), 1) // replace
  assert_eq(edit_distance(one, one), 0) // match
  assert_eq(edit_distance(one, FixedArray::make(0, 0)), 1) // delete
}

// --- Knapsack ---------------------------------------------------------------

test "knapsack: basic" {
  // (2,3), (3,4), (4,5); capacity 5 -> take items 0+1, weight 5, value 7.
  let weights = FixedArray::make(3, 0)
  weights[0] = 2
  weights[1] = 3
  weights[2] = 4
  let values = FixedArray::make(3, 0)
  values[0] = 3
  values[1] = 4
  values[2] = 5
  assert_eq(knapsack(weights, values, 5), 7)
}

test "knapsack: no fit" {
  // Every item heavier than capacity.
  let weights = FixedArray::makei(3, fn(i) { i + 5 }) // [5,6,7]
  let values = FixedArray::makei(3, fn(i) { (i + 1) * 10 }) // [10,20,30]
  assert_eq(knapsack(weights, values, 3), 0)
}

test "knapsack: exact fit" {
  // (2,4), (3,5); capacity 5 -> both fit exactly, value 9.
  let weights = FixedArray::make(2, 0)
  weights[0] = 2
  weights[1] = 3
  let values = FixedArray::make(2, 0)
  values[0] = 4
  values[1] = 5
  assert_eq(knapsack(weights, values, 5), 9)
}

test "knapsack: multiple optimal" {
  // Three unit-weight unit-value items, capacity 2: any pair gives value 2.
  let weights = FixedArray::make(3, 1)
  let values = FixedArray::make(3, 1)
  assert_eq(knapsack(weights, values, 2), 2)
}

test "knapsack: empty items" {
  let weights = FixedArray::make(0, 0)
  let values = FixedArray::make(0, 0)
  assert_eq(knapsack(weights, values, 10), 0)
}

test "knapsack: zero capacity" {
  let weights = FixedArray::makei(2, fn(i) { i + 2 }) // [2,3]
  let values = FixedArray::makei(2, fn(i) { (i + 1) * 4 }) // [4,8]
  assert_eq(knapsack(weights, values, 0), 0)
}

test "knapsack: invalid inputs" {
  // Mismatched lengths.
  let w1 = FixedArray::make(2, 1)
  let v1 = FixedArray::make(1, 1)
  assert_eq(knapsack(w1, v1, 5), 0)
  // Negative weight.
  let w2 = FixedArray::make(2, 0)
  w2[0] = -1
  w2[1] = 2
  let v2 = FixedArray::make(2, 1)
  assert_eq(knapsack(w2, v2, 5), 0)
  // Negative value.
  let w3 = FixedArray::make(2, 1)
  let v3 = FixedArray::make(2, 0)
  v3[0] = -3
  v3[1] = 4
  assert_eq(knapsack(w3, v3, 5), 0)
  // Negative capacity.
  let w4 = FixedArray::make(2, 1)
  let v4 = FixedArray::make(2, 1)
  assert_eq(knapsack(w4, v4, -1), 0)
}

test "knapsack: OOM protection" {
  // n * capacity > 10^7: should return 0 to prevent OOM.
  let w = FixedArray::make(10000, 1)
  let v = FixedArray::make(10000, 1)
  assert_eq(knapsack(w, v, 1000000), 0) // 10^4 * 10^6 = 10^10 > 10^7
}
