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
/// O(n*m) time, O(min(n,m)) space DP using a rolling array. Conceptually
/// `dp[i][j]` is the LCS length of `a[0..i)` and `b[0..j)`; row 0 and
/// column 0 (empty prefix) stay zero. Only a single row is kept, with the
/// shorter array as the inner dimension and one scalar holding the
/// diagonal `dp[i-1][j-1]`. Empty arrays yield `Some(0)`.
///
/// **Guard**: the DP still performs O(n*m) work, so inputs whose
/// `(n+1)*(m+1)` bound exceeds 10^7 are rejected, returning `None`. The
/// caller can distinguish a genuine zero-length LCS (`Some(0)`) from a
/// rejected input (`None`).
pub fn lcs(a : FixedArray[Int], b : FixedArray[Int]) -> Int? {
  let n = a.length()
  let m = b.length()
  // Work guard: the DP runs in O(n*m) time. Reject inputs whose
  // (n+1)*(m+1) work bound exceeds 10^7, returning None so the caller can
  // distinguish rejection from a genuine zero-length LCS.
  let work = (n + 1) * (m + 1)
  if work > 10000000 || work < 0 {
    return None
  }
  // Rolling array: outer loop over the longer array, inner loop over the
  // shorter one so the DP row has size min(n,m)+1.
  let (outer, inner) = if m <= n { (a, b) } else { (b, a) }
  let ni = outer.length()
  let nj = inner.length()
  let dp = FixedArray::make(nj + 1, 0) // row 0: all zeros (empty prefix)
  for i = 1; i <= ni; i = i + 1 {
    // diag = dp[i-1][j-1]; dp[0] stays 0 (empty prefix of inner).
    let mut diag = dp[0]
    for j = 1; j <= nj; j = j + 1 {
      let above = dp[j] // dp[i-1][j], saved before overwrite
      if outer[i - 1] == inner[j - 1] {
        dp[j] = diag + 1
      } else {
        // above = dp[i-1][j], dp[j-1] = dp[i][j-1] (already updated)
        dp[j] = max2(above, dp[j - 1])
      }
      diag = above
    }
  }
  Some(dp[nj])
}

// ---------------------------------------------------------------------------
// Edit Distance (Levenshtein)
// ---------------------------------------------------------------------------

/// Compute the minimum edit distance between two arrays.
/// Operations: insert, delete, replace (each costs 1).
///
/// O(n*m) time, O(min(n,m)) space DP using a rolling array. Conceptually
/// `dp[i][j]` is the edit distance between `a[0..i)` and `b[0..j)`.
/// Transforming to/from an empty prefix costs its own length (pure
/// inserts/deletes), so an empty array yields `Some` of the length of
/// the other. Only a single row is kept, with the shorter array as the
/// inner dimension and one scalar holding the diagonal `dp[i-1][j-1]`.
///
/// **Guard**: the DP still performs O(n*m) work, so inputs whose
/// `(n+1)*(m+1)` bound exceeds 10^7 are rejected, returning `None`. The
/// caller can distinguish a rejected input from a valid worst-case
/// distance by handling the `None` explicitly.
pub fn edit_distance(a : FixedArray[Int], b : FixedArray[Int]) -> Int? {
  let n = a.length()
  let m = b.length()
  // Work guard: the DP runs in O(n*m) time. Reject inputs whose
  // (n+1)*(m+1) work bound exceeds 10^7, returning None so the caller can
  // distinguish rejection from a valid worst-case distance.
  let work = (n + 1) * (m + 1)
  if work > 10000000 || work < 0 {
    return None
  }
  // Rolling array: outer loop over the longer array, inner loop over the
  // shorter one so the DP row has size min(n,m)+1.
  let (outer, inner) = if m <= n { (a, b) } else { (b, a) }
  let ni = outer.length()
  let nj = inner.length()
  let dp = FixedArray::make(nj + 1, 0)
  // Base row: dp[0][j] = j (edit distance from empty to inner[0..j)).
  for j = 0; j <= nj; j = j + 1 {
    dp[j] = j
  }
  for i = 1; i <= ni; i = i + 1 {
    // diag = dp[i-1][0]; then dp[0] = i (dp[i][0] = i: pure deletes).
    let mut diag = dp[0]
    dp[0] = i
    for j = 1; j <= nj; j = j + 1 {
      let above = dp[j] // dp[i-1][j], saved before overwrite
      if outer[i - 1] == inner[j - 1] {
        // Last characters match: no extra cost beyond the prefixes.
        dp[j] = diag
      } else {
        // del = above + 1, ins = dp[j-1] + 1 (left), rep = diag + 1
        dp[j] = min2(min2(above + 1, dp[j - 1] + 1), diag + 1)
      }
      diag = above
    }
  }
  Some(dp[nj])
}

// ---------------------------------------------------------------------------
// 0/1 Knapsack
// ---------------------------------------------------------------------------

/// Solve 0/1 knapsack: max value with given weight capacity.
/// weights[i] and values[i] describe item i. Each item used at most once.
///
/// Standard O(n*capacity) DP. `dp[i][w]` is the best value achievable using
/// the first `i` items under capacity `w`; row 0 (no items) is all zero.
///
/// **Memory**: allocates `(n+1) * (capacity+1)` Int values. To prevent OOM,
/// rejects inputs where `n * capacity > 10^7` (≈40MB for Int32), returning
/// `None`. The caller can distinguish a genuine zero-value result (`Some(0)`)
/// from a rejected input (`None`).
///
/// Returns `None` for invalid inputs: mismatched lengths, negative weights or
/// values, or negative capacity.
pub fn knapsack(
  weights : FixedArray[Int],
  values : FixedArray[Int],
  capacity : Int,
) -> Int? {
  let n = weights.length()
  // Validate: matching lengths and non-negative weights, values, capacity.
  if n != values.length() || capacity < 0 {
    return None
  }
  for i = 0; i < n; i = i + 1 {
    if weights[i] < 0 || values[i] < 0 {
      return None
    }
  }
  // OOM protection: reject inputs that would allocate > 10^7 Int cells.
  // (n+1) * (capacity+1) > 10^7 means ~40MB+ of Int32 values.
  let dp_size = (n + 1) * (capacity + 1)
  if dp_size > 10000000 || dp_size < 0 {
    return None
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
  Some(dp[n * cols + capacity])
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
  assert_eq(lcs(a, b), Some(3))
}

test "lcs: no match" {
  let a = FixedArray::makei(3, fn(i) { i + 1 }) // [1,2,3]
  let b = FixedArray::makei(3, fn(i) { i + 4 }) // [4,5,6]
  assert_eq(lcs(a, b), Some(0))
}

test "lcs: one empty" {
  let a = FixedArray::make(0, 0)
  let b = FixedArray::makei(3, fn(i) { i + 1 })
  assert_eq(lcs(a, b), Some(0))
  assert_eq(lcs(b, a), Some(0))
}

test "lcs: both empty" {
  let a = FixedArray::make(0, 0)
  let b = FixedArray::make(0, 0)
  assert_eq(lcs(a, b), Some(0))
}

test "lcs: full match" {
  let a = FixedArray::makei(3, fn(i) { i + 1 })
  let b = FixedArray::makei(3, fn(i) { i + 1 })
  assert_eq(lcs(a, b), Some(3))
}

test "lcs: partial match" {
  let a = FixedArray::makei(4, fn(i) { i + 1 }) // [1,2,3,4]
  let b = FixedArray::make(4, 0)
  b[0] = 1
  b[1] = 3
  b[2] = 4
  b[3] = 5 // [1,3,4,5]
  assert_eq(lcs(a, b), Some(3)) // [1,3,4]
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
  assert_eq(lcs(a, b), Some(4)) // [1,2,2,3]
}

test "lcs: OOM protection" {
  // (n+1)*(m+1) > 10^7: should return None to prevent OOM.
  let a = FixedArray::make(4000, 1)
  let b = FixedArray::make(4000, 1)
  assert_true(lcs(a, b) is None) // 4001 * 4001 > 10^7
}

// --- Edit distance ----------------------------------------------------------

test "edit_distance: identical arrays" {
  let a = FixedArray::makei(3, fn(i) { i + 1 })
  let b = FixedArray::makei(3, fn(i) { i + 1 })
  assert_eq(edit_distance(a, b), Some(0))
}

test "edit_distance: one empty" {
  let empty = FixedArray::make(0, 0)
  let other = FixedArray::makei(3, fn(i) { i + 1 })
  assert_eq(edit_distance(empty, other), Some(3))
  assert_eq(edit_distance(other, empty), Some(3))
}

test "edit_distance: both empty" {
  let empty = FixedArray::make(0, 0)
  assert_eq(edit_distance(empty, empty), Some(0))
}

test "edit_distance: completely different" {
  let a = FixedArray::makei(3, fn(i) { i + 1 }) // [1,2,3]
  let b = FixedArray::makei(3, fn(i) { i + 4 }) // [4,5,6]
  assert_eq(edit_distance(a, b), Some(3))
}

test "edit_distance: partial similarity" {
  let a = FixedArray::makei(4, fn(i) { i + 1 }) // [1,2,3,4]
  let b = FixedArray::make(3, 0)
  b[0] = 1
  b[1] = 2
  b[2] = 4 // [1,2,4]
  assert_eq(edit_distance(a, b), Some(1)) // delete the 3
}

test "edit_distance: single element" {
  let one = FixedArray::make(1, 0)
  one[0] = 1
  let two = FixedArray::make(1, 0)
  two[0] = 2
  assert_eq(edit_distance(one, two), Some(1)) // replace
  assert_eq(edit_distance(one, one), Some(0)) // match
  assert_eq(edit_distance(one, FixedArray::make(0, 0)), Some(1)) // delete
}

test "edit_distance: OOM protection" {
  // (n+1)*(m+1) > 10^7: should return None to prevent OOM.
  let a = FixedArray::make(4000, 1)
  let b = FixedArray::make(4000, 1)
  assert_true(edit_distance(a, b) is None) // 4001 * 4001 > 10^7
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
  assert_eq(knapsack(weights, values, 5), Some(7))
}

test "knapsack: no fit" {
  // Every item heavier than capacity.
  let weights = FixedArray::makei(3, fn(i) { i + 5 }) // [5,6,7]
  let values = FixedArray::makei(3, fn(i) { (i + 1) * 10 }) // [10,20,30]
  assert_eq(knapsack(weights, values, 3), Some(0))
}

test "knapsack: exact fit" {
  // (2,4), (3,5); capacity 5 -> both fit exactly, value 9.
  let weights = FixedArray::make(2, 0)
  weights[0] = 2
  weights[1] = 3
  let values = FixedArray::make(2, 0)
  values[0] = 4
  values[1] = 5
  assert_eq(knapsack(weights, values, 5), Some(9))
}

test "knapsack: multiple optimal" {
  // Three unit-weight unit-value items, capacity 2: any pair gives value 2.
  let weights = FixedArray::make(3, 1)
  let values = FixedArray::make(3, 1)
  assert_eq(knapsack(weights, values, 2), Some(2))
}

test "knapsack: empty items" {
  let weights = FixedArray::make(0, 0)
  let values = FixedArray::make(0, 0)
  assert_eq(knapsack(weights, values, 10), Some(0))
}

test "knapsack: zero capacity" {
  let weights = FixedArray::makei(2, fn(i) { i + 2 }) // [2,3]
  let values = FixedArray::makei(2, fn(i) { (i + 1) * 4 }) // [4,8]
  assert_eq(knapsack(weights, values, 0), Some(0))
}

test "knapsack: invalid inputs" {
  // Mismatched lengths.
  let w1 = FixedArray::make(2, 1)
  let v1 = FixedArray::make(1, 1)
  assert_eq(knapsack(w1, v1, 5), None)
  // Negative weight.
  let w2 = FixedArray::make(2, 0)
  w2[0] = -1
  w2[1] = 2
  let v2 = FixedArray::make(2, 1)
  assert_eq(knapsack(w2, v2, 5), None)
  // Negative value.
  let w3 = FixedArray::make(2, 1)
  let v3 = FixedArray::make(2, 0)
  v3[0] = -3
  v3[1] = 4
  assert_eq(knapsack(w3, v3, 5), None)
  // Negative capacity.
  let w4 = FixedArray::make(2, 1)
  let v4 = FixedArray::make(2, 1)
  assert_eq(knapsack(w4, v4, -1), None)
}

test "knapsack: OOM protection" {
  // n * capacity > 10^7: should return None to prevent OOM.
  let w = FixedArray::make(10000, 1)
  let v = FixedArray::make(10000, 1)
  assert_eq(knapsack(w, v, 1000000), None) // 10^4 * 10^6 = 10^10 > 10^7
}
