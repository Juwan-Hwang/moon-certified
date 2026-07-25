/// Knuth optimisation for dynamic programming.
///
/// For DP problems of the form
///
/// ```text
///   dp[i][j] = min_{i < k < j} { dp[i][k] + dp[k][j] } + cost(i, j)
/// ```
///
/// if the cost function satisfies the **quadrangle inequality** (QI) and is
/// **monotone** on the lattice of intervals:
///
/// - QI: `cost(a, c) + cost(b, d) <= cost(a, d) + cost(b, c)` for `a <= b <= c <= d`.
/// - Monotonicity: `cost(b, c) <= cost(a, d)` for `a <= b <= c <= d`.
///
/// then the optimal split point `opt(i, j)` is monotonic:
///
/// ```text
///   opt(i, j-1) <= opt(i, j) <= opt(i+1, j)
/// ```
///
/// This reduces the transition from O(n²) per state to O(n) amortised, giving
/// an overall O(n²) DP instead of O(n³).
///
/// ## Algorithm
///
/// We fill the DP table in order of increasing interval length. For each
/// interval `[i, j]`, we only search `k` in `[opt(i, j-1), opt(i+1, j)]`,
/// which is a narrow window guaranteed to contain the optimal split.
///
/// ## Complexity
///
/// - Time: O(n²) — the total search across all intervals is O(n²) because
///   the search windows telescope.
/// - Space: O(n²) for the DP and opt tables.
///
/// ## Requirement
///
/// The caller must verify that `cost` satisfies the quadrangle inequality.
/// If it does not, the result may be incorrect.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

/// Solve the interval DP with Knuth optimisation.
///
/// Computes `dp[i][j] = min_{i<k<j} { dp[i][k] + dp[k][j] } + cost(i, j)`
/// for all `0 <= i < j <= n-1`, where `dp[i][i] = 0` (base case).
///
/// # Parameters
/// - `n`: the number of elements. Must be >= 2.
/// - `cost`: callback `(i, j) -> Int64` computing `cost(i, j)` for `i < j`.
///   Must satisfy the quadrangle inequality and monotonicity.
///
/// # Returns
/// The DP table as a flat `Int64` array of size `n * n` (row-major), where
/// `dp[i * n + j]` is the optimal cost for interval `[i, j]`. Returns an
/// empty array for `n < 2`.
pub fn solve(
  n : Int,
  cost : (Int, Int) -> Int64,
) -> FixedArray[Int64] {
  if n < 2 {
    return FixedArray::make(0, 0L)
  }
  // dp[i][j] stored in flat array: dp[i * n + j]
  let dp = FixedArray::make(n * n, 0L)
  // opt[i][j]: optimal split point k for interval [i, j].
  let opt = FixedArray::make(n * n, 0)
  // Base case: dp[i][i] = 0 (already zero).
  // For intervals of length 2 (j = i+1): dp[i][i+1] = cost(i, i+1), opt = i.
  for i = 0; i < n - 1; i = i + 1 {
    dp[i * n + (i + 1)] = cost(i, i + 1)
    opt[i * n + (i + 1)] = i
  }
  // Fill by increasing interval length.
  for len = 3; len <= n; len = len + 1 {
    for i = 0; i + len - 1 < n; i = i + 1 {
      let j = i + len - 1
      // Search k in [opt[i][j-1], opt[i+1][j]], clamped to valid range
      // [i+1, j-1] since k must satisfy i < k < j.
      let raw_lo = opt[i * n + (j - 1)]
      let raw_hi = opt[(i + 1) * n + j]
      let k_lo = if raw_lo < i + 1 { i + 1 } else { raw_lo }
      let k_hi = if raw_hi > j - 1 { j - 1 } else { raw_hi }
      let mut best_val : Int64 = 0L
      let mut best_k = k_lo
      let mut found = false
      for k = k_lo; k <= k_hi; k = k + 1 {
        let val = dp[i * n + k] + dp[k * n + j]
        if !found || val < best_val {
          best_val = val
          best_k = k
          found = true
        }
      }
      dp[i * n + j] = best_val + cost(i, j)
      opt[i * n + j] = best_k
    }
  }
  dp
}

/// Convenience: return only `dp[0][n-1]` (the answer for the full interval).
pub fn solve_full(n : Int, cost : (Int, Int) -> Int64) -> Int64 {
  if n < 2 {
    return 0L
  }
  let dp = solve(n, cost)
  dp[0 * n + (n - 1)]
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "knuth: matrix chain multiplication" {
  // Classic example: matrix chain multiplication.
  // Matrices with dimensions p = [10, 100, 5, 50] (3 matrices).
  // cost(i, j) = p[i] * p[j] * ... actually for MCM, cost(i, j) is the cost
  // of multiplying the chain, which is p[i-1]*p[k]*p[j].
  // For Knuth DP: dp[i][j] = min_{k} dp[i][k]+dp[k+1][j] + p[i-1]*p[k]*p[j].
  // This doesn't fit the exact form dp[i][k]+dp[k][j]+cost(i,j).
  // Let's use a different cost that satisfies QI.
  //
  // Example: optimal binary search tree.
  // Keys with frequencies; cost(i,j) = sum of frequencies in [i..j].
  let freq = [3, 1, 4, 1, 5]
  let n = freq.length()
  // cost(i, j) = sum of freq[i..j].
  let cost_fn = fn(i : Int, j : Int) -> Int64 {
    let mut s = 0L
    for k = i; k <= j; k = k + 1 {
      s = s + freq[k].to_int64()
    }
    s
  }
  let result = solve(n, cost_fn)
  // dp[0][4] = optimal BST cost.
  // Brute force check.
  let brute = compute_brute(n, cost_fn)
  assert_eq(result[0 * n + (n - 1)], brute[0 * n + (n - 1)])
}

test "knuth: n=2" {
  let cost_fn = fn(i : Int, j : Int) -> Int64 { (i + j).to_int64() }
  let result = solve(2, cost_fn)
  assert_eq(result[0 * 2 + 1], 1L) // cost(0, 1) = 0+1 = 1
}

test "knuth: n<2 returns empty" {
  let cost_fn = fn(_ : Int, _ : Int) -> Int64 { 0L }
  let result = solve(1, cost_fn)
  assert_eq(result.length(), 0)
}

test "knuth: cross-check with brute force (n=6)" {
  // Use a cost function that satisfies QI: cost(i, j) = sum of weights[i..j].
  let weights = [2, 3, 1, 4, 2, 5]
  let n = weights.length()
  let cost_fn = fn(i : Int, j : Int) -> Int64 {
    let mut s = 0L
    for k = i; k <= j; k = k + 1 {
      s = s + weights[k].to_int64()
    }
    s
  }
  let knuth_result = solve(n, cost_fn)
  let brute_result = compute_brute(n, cost_fn)
  for i = 0; i < n; i = i + 1 {
    for j = i; j < n; j = j + 1 {
      assert_eq(knuth_result[i * n + j], brute_result[i * n + j])
    }
  }
}

test "knuth: cross-check with brute force (n=8)" {
  let weights = [5, 2, 8, 3, 6, 1, 4, 7]
  let n = weights.length()
  let cost_fn = fn(i : Int, j : Int) -> Int64 {
    let mut s = 0L
    for k = i; k <= j; k = k + 1 {
      s = s + weights[k].to_int64()
    }
    s
  }
  let knuth_result = solve(n, cost_fn)
  let brute_result = compute_brute(n, cost_fn)
  for i = 0; i < n; i = i + 1 {
    for j = i; j < n; j = j + 1 {
      assert_eq(knuth_result[i * n + j], brute_result[i * n + j])
    }
  }
}

test "knuth: solve_full convenience" {
  let weights = [1, 2, 3]
  let n = weights.length()
  let cost_fn = fn(i : Int, j : Int) -> Int64 {
    let mut s = 0L
    for k = i; k <= j; k = k + 1 {
      s = s + weights[k].to_int64()
    }
    s
  }
  let full = solve_full(n, cost_fn)
  let dp = solve(n, cost_fn)
  assert_eq(full, dp[0 * n + (n - 1)])
}

// ---------------------------------------------------------------------------
// Brute-force reference implementation for cross-checking.
// ---------------------------------------------------------------------------

fn compute_brute(n : Int, cost : (Int, Int) -> Int64) -> FixedArray[Int64] {
  let dp = FixedArray::make(n * n, 0L)
  for len = 2; len <= n; len = len + 1 {
    for i = 0; i + len - 1 < n; i = i + 1 {
      let j = i + len - 1
      let mut best = 999999999999L
      for k = i + 1; k < j; k = k + 1 {
        let val = dp[i * n + k] + dp[k * n + j]
        if val < best {
          best = val
        }
      }
      if best == 999999999999L {
        best = 0L // len == 2: no split needed
      }
      dp[i * n + j] = best + cost(i, j)
    }
  }
  dp
}
