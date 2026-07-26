/// SMAWK Algorithm — row minima of a totally monotone matrix.
///
/// Given an `n × m` matrix `A` that is **totally monotone** — i.e., for any
/// `i₁ < i₂` and `j₁ < j₂`, if `A[i₁, j₁] > A[i₁, j₂]` then
/// `A[i₂, j₁] > A[i₂, j₂]` — the SMAWK algorithm finds the column index of
/// the minimum element in each row in **O(n + m)** time.
///
/// This is a key primitive for many DP optimisations:
/// - Divide-and-conquer DP when the opt table is monotone
/// - Knuth optimisation when the quadrangle inequality holds
/// - Aliens' trick (Lagrangian relaxation) inner DP
///
/// ## Algorithm
///
/// The algorithm consists of two phases:
/// 1. **Reduce**: process columns left-to-right, maintaining a stack of
///    "useful" columns. For each new column, pop while
///    `f(stack_size-1, top) > f(stack_size-1, j)`. This reduces columns from
///    `m` to at most `n`.
/// 2. **Search**: for each row, advance a pointer through the reduced columns
///    while the next column yields a smaller value. The total pointer movement
///    is O(n + m).
///
/// ## Complexity
/// - Time: O(n + m)
/// - Space: O(n + m)
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

/// Find the column index of the minimum element in each row of a totally
/// monotone matrix.
///
/// # Parameters
/// - `f`: a function `(row, col) -> Int` representing the matrix.
///   Must satisfy the total monotonicity property.
/// - `n`: number of rows.
/// - `m`: number of columns.
///
/// # Returns
/// An array `res` of length `n` where `res[i]` is the column index of the
/// minimum value in row `i`. For ties, the leftmost minimum is returned.
pub fn smawk_row_minima(
  f : (Int, Int) -> Int,
  n : Int,
  m : Int,
) -> FixedArray[Int] {
  if n == 0 || m == 0 {
    return FixedArray::make(0, 0)
  }
  let result = FixedArray::make(n, 0)

  // Phase 1: REDUCE — build a reduced column set of size ≤ n.
  // For each column j, pop from the stack while:
  //   f(stack_size - 1, stack_top) > f(stack_size - 1, j)
  // Then push j if stack has fewer than n entries.
  let cols : Array[Int] = []
  for j = 0; j < m; j = j + 1 {
    while cols.length() > 0 {
      let row = cols.length() - 1
      if f(row, cols[cols.length() - 1]) > f(row, j) {
        ignore(cols.pop())
      } else {
        break
      }
    }
    if cols.length() < n {
      cols.push(j)
    }
  }
  let rc = cols.length()

  // Phase 2: SEARCH — find row minima using the reduced columns.
  // For each row i, advance pointer while the next column is better.
  // The pointer is non-decreasing across rows (total monotonicity).
  let mut ptr = 0
  for i = 0; i < n; i = i + 1 {
    // Advance ptr while the next column gives a strictly smaller value.
    while ptr + 1 < rc && f(i, cols[ptr + 1]) < f(i, cols[ptr]) {
      ptr = ptr + 1
    }
    result[i] = cols[ptr]
  }
  result
}

/// Find the column index of the minimum element in each row of a totally
/// monotone matrix, where the matrix is given as a `FixedArray[FixedArray[Int]]`.
///
/// Convenience wrapper around [`smawk_row_minima`] for pre-materialised matrices.
pub fn smawk_matrix(
  matrix : FixedArray[FixedArray[Int]],
) -> FixedArray[Int] {
  let n = matrix.length()
  if n == 0 {
    return FixedArray::make(0, 0)
  }
  let m = matrix[0].length()
  if m == 0 {
    return FixedArray::make(0, 0)
  }
  smawk_row_minima(fn(i, j) { matrix[i][j] }, n, m)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "smawk: simple 3x3 identity" {
  // Totally monotone matrix (row minima move rightward):
  //   0  1  2
  // 0[1, 2, 3]  → min at col 0
  // 1[2, 1, 3]  → min at col 1
  // 2[3, 2, 1]  → min at col 2
  // Verification of total monotonicity:
  //   i1=1,i2=2, j1=0,j2=1: A[1,0]=2 > A[1,1]=1 → need A[2,0] > A[2,1] → 3 > 2 ✓
  //   All other pairs satisfy the condition trivially.
  let result = smawk_row_minima(
    fn(i, j) {
      match (i, j) {
        (0, 0) => 1; (0, 1) => 2; (0, 2) => 3
        (1, 0) => 2; (1, 1) => 1; (1, 2) => 3
        (2, 0) => 3; (2, 1) => 2; (2, 2) => 1
        (_, _) => 999
      }
    },
    3,
    3,
  )
  assert_eq(result[0], 0)
  assert_eq(result[1], 1)
  assert_eq(result[2], 2)
}

test "smawk: all same row" {
  // All values equal → leftmost minimum.
  let result = smawk_row_minima(fn(_i, _j) { 5 }, 3, 4)
  assert_eq(result[0], 0)
  assert_eq(result[1], 0)
  assert_eq(result[2], 0)
}

test "smawk: diagonal minimum" {
  // Matrix where diagonal is minimum:
  //   0  1  2  3
  // 0[0, 9, 9, 9]
  // 1[9, 0, 9, 9]
  // 2[9, 9, 0, 9]
  // 3[9, 9, 9, 0]
  let result = smawk_row_minima(
    fn(i, j) { if i == j { 0 } else { 9 } },
    4,
    4,
  )
  assert_eq(result[0], 0)
  assert_eq(result[1], 1)
  assert_eq(result[2], 2)
  assert_eq(result[3], 3)
}

test "smawk: monotone increasing" {
  // Matrix where f(i, j) = i + j (totally monotone).
  // Row i minimum is at column 0 for all rows.
  let result = smawk_row_minima(fn(i, j) { i + j }, 5, 5)
  for i = 0; i < 5; i = i + 1 {
    assert_eq(result[i], 0)
  }
}

test "smawk: more columns than rows" {
  // 2 rows, 5 columns.
  // f(i,j) = abs(j - target_i) where targets are [1, 3]
  // Row 0: min at j=1, Row 1: min at j=3
  let result = smawk_row_minima(
    fn(i, j) {
      let target = if i == 0 { 1 } else { 3 }
      let d = j - target
      if d < 0 { -d } else { d }
    },
    2,
    5,
  )
  assert_eq(result[0], 1)
  assert_eq(result[1], 3)
}

test "smawk: large Monge matrix" {
  // A Monge matrix: f(i,j) = i*j (convex, totally monotone).
  // Row i minimum: column 0 for all i (since i*j is increasing in j for i>0).
  let n = 100
  let m = 100
  let result = smawk_row_minima(fn(i, j) { i * j }, n, m)
  for i = 0; i < n; i = i + 1 {
    assert_eq(result[i], 0)
  }
}

test "smawk: matrix wrapper" {
  let matrix : FixedArray[FixedArray[Int]] = FixedArray::makei(3, fn(_i) {
    FixedArray::make(3, 0)
  })
  matrix[0][0] = 1; matrix[0][1] = 2; matrix[0][2] = 3
  matrix[1][0] = 3; matrix[1][1] = 1; matrix[1][2] = 2
  matrix[2][0] = 2; matrix[2][1] = 3; matrix[2][2] = 1
  let result = smawk_matrix(matrix)
  assert_eq(result[0], 0)
  assert_eq(result[1], 1)
  assert_eq(result[2], 2)
}

test "smawk: empty matrix" {
  let result = smawk_row_minima(fn(_i, _j) { 0 }, 0, 0)
  assert_eq(result.length(), 0)
}

test "smawk: single element" {
  let result = smawk_row_minima(fn(_i, _j) { 42 }, 1, 1)
  assert_eq(result.length(), 1)
  assert_eq(result[0], 0)
}

test "smawk: brute force cross-check" {
  // Generate a totally monotone matrix and compare with brute force.
  // f(i, j) = (i - j)^2 is totally monotone (convex).
  let n = 50
  let m = 80
  let result = smawk_row_minima(fn(i, j) {
    let d = i - j
    d * d
  }, n, m)
  // Brute force.
  for i = 0; i < n; i = i + 1 {
    let mut bf_best = 0
    let mut bf_val = (i - 0) * (i - 0)
    for j = 1; j < m; j = j + 1 {
      let v = (i - j) * (i - j)
      if v < bf_val {
        bf_val = v
        bf_best = j
      }
    }
    assert_eq(result[i], bf_best)
  }
}
