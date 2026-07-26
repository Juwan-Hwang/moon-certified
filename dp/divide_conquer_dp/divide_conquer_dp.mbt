/// Divide and Conquer dynamic programming optimisation.
///
/// For DP problems of the form
///
/// ```text
///   dp[i][j] = min_{k < j} { dp[i-1][k] + cost(k+1, j) }
/// ```
///
/// where `opt(i, j-1) <= opt(i, j) <= opt(i, j+1)` (the optimal split point is
/// monotonic in `j`), the divide-and-conquer optimisation reduces the
/// transition from O(m²) to O(m log m) per row `i`.
///
/// ## Algorithm
///
/// For each row `i`, we recursively compute `dp[i][mid]` by:
/// 1. First computing `dp[i-1][*]` for all relevant positions.
/// 2. For the current range `[lo, hi]` with mid-point `mid`, iterate `k` only
///    over `[opt_lo, opt_hi]` (the known bounds on the optimal split).
/// 3. Recurse on `[lo, mid-1]` with `opt_hi = opt(mid)` and
///    `[mid+1, hi]` with `opt_lo = opt(mid)`.
///
/// ## Complexity
///
/// - Time: O(m log m) per row, O(n * m log m) total.
/// - Space: O(m) for the DP arrays.
///
/// ## Monotonicity requirement
///
/// The caller must verify that the cost function satisfies the quadrangle
/// inequality (Monge property), which guarantees monotonicity of the optimal
/// split point. If this property does not hold, the result is incorrect.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

///|
/// Compute one row of the DP using divide-and-conquer optimisation.
///
/// Given `prev` (the `dp[i-1]` array of length `m`), computes `dp[i]` where
///
/// ```text
///   dp[i][j] = min_{k in [0, j-1]} { prev[k] + cost(k+1, j) }
/// ```
///
/// and the optimal `k` is monotonic in `j`.
///
/// # Parameters
/// - `prev`: the previous row `dp[i-1]`, length `m`. `prev[k]` is the best
///   cost using the first `k` groups.
/// - `m`: the number of columns (positions).
/// - `cost`: a callback `(l, j) -> Int64` computing `cost(l, j)` which
///   represents the cost of placing elements `[l, j]` in one group.
///   Must satisfy the quadrangle inequality.
///
/// # Returns
/// The current row `dp[i]` as an `Int64` array of length `m`.
pub fn[T] solve_row(
  prev : FixedArray[T],
  m : Int,
  cost : (Int, Int) -> T,
  add : (T, T) -> T,
  compare : (T, T) -> Int,
  identity : T,
) -> FixedArray[T] {
  if m == 0 {
    return FixedArray::make(0, identity)
  }
  let dp = FixedArray::make(m, identity)
  // dp[j] = min_{k in [0, j-1]} prev[k] + cost(k+1, j)
  // We also need to handle k=j (cost(0..j) as a single group), which means
  // prev[0] contribution... actually let's define it clearly:
  // dp[j] = min over k from 0 to j-1 of: prev[k] + cost(k, j-1)
  // where cost(k, j-1) is the cost of the group [k, j-1].
  // But the exact semantics depend on the problem. Let's use the standard:
  // dp[j] = min_{0 <= k < j} { prev[k] + cost(k+1, j) }
  // where cost(l, r) is the cost of group [l, r] inclusive.
  // For j=0, dp[0] = prev[0] (or some base case).
  // We'll use: dp[j] = min_{k in [0, j]} { prev[k] + cost(k, j-1) }
  // with the convention cost(k, j-1) where k <= j-1, and for k=j, cost=0.
  // Actually, the most common formulation is:
  // dp[i][j] = min_{k < j} { dp[i-1][k] + C(k+1, j) }
  // So dp[j] depends on prev[k] for k < j, plus cost(k+1, j).
  // Let's implement exactly that.
  // Base: dp[0] = prev[0] (no split possible, or identity cost).
  // For j >= 1: dp[j] = min_{k=0..j-1} { prev[k] + cost(k+1, j) }
  // But we also need the option of "all in one group" which is prev[0] + cost(1, j).
  // Actually prev[0] is dp[i-1][0] which is typically 0 or the base case.
  // Let's also handle k=j meaning dp[i-1][j] + cost(j+1, j) = prev[j] + 0 (empty cost).
  // But cost(j+1, j) for empty range should be identity. We'll let the caller
  // handle this by having cost(l, r) return identity for l > r.
  // For simplicity and correctness, let's define:
  // dp[j] = min_{k=0..j} { prev[k] + cost(k, j-1) }
  // where cost(k, j-1) for k <= j-1 is the group cost, and for k = j it's identity (empty group).
  // This way dp[0] = prev[0] + cost(0, -1) = prev[0] + identity.
  // Hmm, this is getting complicated. Let me use the simplest standard form:
  // dp[j] = min_{k=0..j-1} { prev[k] + cost(k, j) }
  // where cost(k, j) covers the range [k, j-1] (i.e., elements k through j-1).
  // And dp[0] = identity (base case, no elements).
  // Actually, the most flexible approach: let the caller define the cost function
  // and we just do the D&C optimization.
  dp[0] = identity
  // For j >= 1, compute dp[j] = min_{k=0..j-1} prev[k] + cost(k, j)
  // where cost(k, j) is the cost of assigning [k, j-1] to one group.
  // The optimal k is monotonic: opt(j-1) <= opt(j) <= opt(j+1).
  // We use D&C: compute dp for range [lo, hi] with known opt in [opt_lo, opt_hi].
  solve_range(dp, prev, 1, m - 1, 0, m - 1, cost, add, compare, identity)
  dp
}

///|
fn[T] solve_range(
  dp : FixedArray[T],
  prev : FixedArray[T],
  lo : Int,
  hi : Int,
  opt_lo : Int,
  opt_hi : Int,
  cost : (Int, Int) -> T,
  add : (T, T) -> T,
  compare : (T, T) -> Int,
  identity : T,
) -> Unit {
  if lo > hi {
    return
  }
  let mid = (lo + hi) / 2
  // Find optimal k for mid, searching in [opt_lo, min(mid-1, opt_hi)].
  let search_hi = if mid - 1 < opt_hi { mid - 1 } else { opt_hi }
  let mut best_k = opt_lo
  let mut best_val = identity
  let mut found = false
  for k = opt_lo; k <= search_hi; k = k + 1 {
    let c = cost(k, mid)
    let val = add(prev[k], c)
    if !found || compare(val, best_val) < 0 {
      best_val = val
      best_k = k
      found = true
    }
  }
  if found {
    dp[mid] = best_val
  }
  // Recurse left: [lo, mid-1], opt_hi = best_k
  solve_range(
    dp,
    prev,
    lo,
    mid - 1,
    opt_lo,
    best_k,
    cost,
    add,
    compare,
    identity,
  )
  // Recurse right: [mid+1, hi], opt_lo = best_k
  solve_range(
    dp,
    prev,
    mid + 1,
    hi,
    best_k,
    opt_hi,
    cost,
    add,
    compare,
    identity,
  )
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "dnc_dp: basic partition" {
  // Partition array [1,2,3,4] into 2 groups to minimize sum of group costs.
  // cost(k, j) = sum of elements [k, j-1] squared.
  // prev = [0, 0, 0, 0] (1 group, cost 0 for first group assignment)
  // Actually let's use a concrete example:
  // Partition [3, 1, 4, 1, 5] into groups; minimize sum of (group_sum)^2.
  // prev[0] = 0 (no elements assigned yet)
  // dp[j] = min_{k<j} prev[k] + (sum[k..j-1])^2
  let arr = [3, 1, 4, 1, 5]
  let m = arr.length()
  // prev = [0, 0, 0, 0, 0] (start: everything has 0 base cost)
  let prev = FixedArray::make(m + 1, 0L)
  // cost(k, j) = (sum of arr[k..j-1])^2
  let cost_fn = fn(k : Int, j : Int) -> Int64 {
    let mut s = 0L
    for i = k; i < j; i = i + 1 {
      s = s + arr[i].to_int64()
    }
    s * s
  }
  let dp = solve_row(
    prev,
    m + 1,
    cost_fn,
    fn(a : Int64, b : Int64) -> Int64 { a + b },
    fn(a : Int64, b : Int64) -> Int {
      if a < b {
        -1
      } else if a > b {
        1
      } else {
        0
      }
    },
    0L,
  )
  // dp[j] = min cost to partition first j elements into groups.
  // dp[0] = 0
  // dp[1] = prev[0] + cost(0,1) = 0 + 3^2 = 9
  // dp[2] = min(prev[0]+cost(0,2), prev[1]+cost(1,2)) = min(0+16, 0+1) = 1
  // dp[3] = min(prev[0]+cost(0,3), prev[1]+cost(1,3), prev[2]+cost(2,3))
  //       = min(0+64, 0+25, 0+16) = 16
  // dp[4] = min(0+81, 0+36, 0+25, 0+1) = 1
  // dp[5] = min(0+196, 0+81, 0+100, 0+36, 0+25) = 25
  assert_eq(dp[0], 0L)
  assert_eq(dp[1], 9L)
  assert_eq(dp[2], 1L)
  assert_eq(dp[3], 16L)
  assert_eq(dp[4], 1L)
  assert_eq(dp[5], 25L)
}

///|
test "dnc_dp: single element" {
  let prev = FixedArray::make(2, 0L)
  let cost_fn = fn(k : Int, j : Int) -> Int64 {
    (j - k).to_int64() * (j - k).to_int64()
  }
  let dp = solve_row(
    prev,
    2,
    cost_fn,
    fn(a : Int64, b : Int64) -> Int64 { a + b },
    fn(a : Int64, b : Int64) -> Int {
      if a < b {
        -1
      } else if a > b {
        1
      } else {
        0
      }
    },
    0L,
  )
  assert_eq(dp[0], 0L)
  assert_eq(dp[1], 1L) // cost(0, 1) = 1^2 = 1
}

///|
test "dnc_dp: cross-check with brute force" {
  // Generate a random-ish array and verify D&C matches brute force.
  let arr = [7, 3, 8, 2, 5, 1, 9, 4, 6]
  let m = arr.length()
  // prev = prefix sums of arr (as if prev[k] = sum of first k elements)
  // Actually, let's just use prev = [0, 0, ..., 0] and cost = (sum)^2.
  let prev = FixedArray::make(m + 1, 0L)
  let cost_fn = fn(k : Int, j : Int) -> Int64 {
    let mut s = 0L
    for i = k; i < j; i = i + 1 {
      s = s + arr[i].to_int64()
    }
    s * s
  }
  let dnc_result = solve_row(
    prev,
    m + 1,
    cost_fn,
    fn(a : Int64, b : Int64) -> Int64 { a + b },
    fn(a : Int64, b : Int64) -> Int {
      if a < b {
        -1
      } else if a > b {
        1
      } else {
        0
      }
    },
    0L,
  )
  // Brute force O(m^2).
  let brute = FixedArray::make(m + 1, 0L)
  brute[0] = 0L
  for j = 1; j <= m; j = j + 1 {
    let mut best = 999999999999L
    for k = 0; k < j; k = k + 1 {
      let c = cost_fn(k, j)
      let val = prev[k] + c
      if val < best {
        best = val
      }
    }
    brute[j] = best
  }
  for j = 0; j <= m; j = j + 1 {
    assert_eq(dnc_result[j], brute[j])
  }
}

///|
test "dnc_dp: multi-row dp" {
  // Partition [1,2,3,4,5] into at most 3 groups to minimize sum of (sum)^2.
  let arr = [1, 2, 3, 4, 5]
  let m = arr.length()
  let cost_fn = fn(k : Int, j : Int) -> Int64 {
    let mut s = 0L
    for i = k; i < j; i = i + 1 {
      s = s + arr[i].to_int64()
    }
    s * s
  }
  // prev[0] = 0 (empty prefix costs nothing); prev[j>0] = INF (can't
  // partition j elements into 0 groups). Each solve_row adds one group.
  let inf = 999999999999L
  let mut prev = FixedArray::make(m + 1, inf)
  prev[0] = 0L
  let add_fn = fn(a : Int64, b : Int64) -> Int64 { a + b }
  let cmp_fn = fn(a : Int64, b : Int64) -> Int {
    if a < b {
      -1
    } else if a > b {
      1
    } else {
      0
    }
  }
  // 3 rows (at most 3 groups).
  for row = 0; row < 3; row = row + 1 {
    prev = solve_row(prev, m + 1, cost_fn, add_fn, cmp_fn, 0L)
  }
  // After 3 rows, dp[5] should be the minimum cost to partition [1,2,3,4,5]
  // into at most 3 groups minimizing sum of squared group sums.
  // Row 0 (1 group):  dp[5] = 225 = (1+2+3+4+5)^2
  // Row 1 (2 groups): dp[5] = 117 = min over splits
  // Row 2 (3 groups): dp[5] = 77 = {1,2,3},{4},{5} => 36+16+25 = 77
  assert_eq(prev[m], 77L)
}
