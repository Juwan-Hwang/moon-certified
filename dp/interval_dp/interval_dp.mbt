/// Interval Dynamic Programming framework.
///
/// Interval DP solves problems on sequences where the answer for a range
/// `[l, r)` can be computed by combining answers for smaller sub-ranges.
/// The standard template iterates over interval length, then left endpoint,
/// then split point:
///
/// ```text
/// for len = 2; len <= n; len++:
///   for l = 0; l + len <= n; l++:
///     r = l + len
///     for k = l + 1; k < r; k++:
///       dp[l][r] = min/max(dp[l][r], dp[l][k] + dp[k][r] + cost)
/// ```
///
/// ## Implemented problems
///
/// 1. **Matrix chain multiplication**: Given a chain of matrices with
///    dimensions `p[0..n]`, find the minimum number of scalar multiplications
///    needed to compute the product `M_0 * M_1 * ... * M_{n-1}`.
///    - Time: O(n³), Space: O(n²).
///    - Also returns the optimal parenthesisation.
///
/// 2. **Optimal binary search tree**: Given sorted keys with search
///    frequencies, build a BST that minimises the expected search cost.
///    - Time: O(n³), Space: O(n²).
///
/// 3. **Burst balloons**: Given `n` balloons with values, maximise coins
///    collected by bursting them one at a time (each burst earns
///    `left * balloon * right` coins).
///    - Time: O(n³), Space: O(n²).
///
/// 4. **Stone merge**: Given `n` piles of stones, find the minimum cost to
///    merge all piles into one (merging cost = sum of pile sizes).
///    - Time: O(n³), Space: O(n²).
///    - Uses `Int64` for accumulation to prevent overflow.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

// ---------------------------------------------------------------------------
// Helper: 2D array creation
// ---------------------------------------------------------------------------

/// Create a 2D array (array of arrays) with the given dimensions and default value.
fn[T] make2d(rows : Int, cols : Int, default : T) -> Array[Array[T]] {
  let result : Array[Array[T]] = []
  for i = 0; i < rows; i = i + 1 {
    let row : Array[T] = Array::make(cols, default)
    result.push(row)
  }
  result
}

// ---------------------------------------------------------------------------
// Matrix Chain Multiplication
// ---------------------------------------------------------------------------

/// Result of matrix chain multiplication optimisation.
///
/// - `min_cost`: the minimum number of scalar multiplications needed.
///   Uses `Int64` to prevent overflow for large chains.
/// - `parenthesization`: a string like `((A0(A1A2))A3)` describing the
///   optimal evaluation order.
pub struct MatrixChainResult {
  min_cost : Int64
  parenthesization : String
}

/// Compute the optimal matrix chain multiplication order.
///
/// # Parameters
/// - `dims`: matrix dimensions. Matrix `i` has dimensions
///   `dims[i] × dims[i+1]` for `i = 0, ..., n-1` where `n = dims.length() - 1`.
///   All dimensions must be positive.
///
/// # Returns
/// A `MatrixChainResult` with the minimum multiplication count and the
/// optimal parenthesisation string. Returns a zero-cost result for chains
/// of 0 or 1 matrices.
///
/// # Complexity
/// - Time: O(n³)
/// - Space: O(n²)
///
/// Uses `Int64` for cost accumulation to prevent overflow.
pub fn matrix_chain(dims : FixedArray[Int]) -> MatrixChainResult {
  let n = dims.length() - 1
  if n <= 0 {
    return { min_cost: 0L, parenthesization: "" }
  }
  if n == 1 {
    return { min_cost: 0L, parenthesization: "A0" }
  }
  // dp[i][j] = minimum cost to multiply matrices i..j (inclusive).
  let dp = make2d(n, n, 0L)
  // split[i][j] = optimal split point k (multiply i..k-1 and k..j).
  let split = make2d(n, n, 0)
  // Chain length from 2 to n.
  let mut chain_len = 2
  while chain_len <= n {
    let mut i = 0
    while i + chain_len - 1 < n {
      let j = i + chain_len - 1
      dp[i][j] = 9223372036854775807L // Int64::MAX
      let mut k = i + 1
      while k <= j {
        // Cost = cost(i, k-1) + cost(k, j) + dims[i] * dims[k] * dims[j+1]
        let cost = dp[i][k - 1] + dp[k][j] +
          dims[i].to_int64() * dims[k].to_int64() * dims[j + 1].to_int64()
        if cost < dp[i][j] {
          dp[i][j] = cost
          split[i][j] = k
        }
        k = k + 1
      }
      i = i + 1
    }
    chain_len = chain_len + 1
  }
  {
    min_cost: dp[0][n - 1],
    parenthesization: build_parenthesization(split, 0, n - 1),
  }
}

/// Recursively build the parenthesisation string from the split table.
fn build_parenthesization(
  split : Array[Array[Int]],
  i : Int,
  j : Int,
) -> String {
  if i == j {
    return "A" + i.to_string()
  }
  let k = split[i][j]
  "(" + build_parenthesization(split, i, k - 1) +
    build_parenthesization(split, k, j) + ")"
}

// ---------------------------------------------------------------------------
// Optimal Binary Search Tree
// ---------------------------------------------------------------------------

/// Compute the minimum expected search cost for an optimal BST.
///
/// Given `n` sorted keys with search frequencies `freq[i]`, finds the BST
/// structure that minimises the total expected search cost (sum of
/// `depth * frequency` for each key).
///
/// # Parameters
/// - `freq`: search frequencies for keys `0, 1, ..., n-1`. Must be
///   non-negative integers.
///
/// # Returns
/// The minimum total cost as `Int64`. Returns 0 for `n <= 0`.
///
/// # Complexity
/// - Time: O(n³)
/// - Space: O(n²)
pub fn optimal_bst(freq : FixedArray[Int]) -> Int64 {
  let n = freq.length()
  if n <= 0 {
    return 0L
  }
  // dp[i][j] = minimum cost for keys i..j (inclusive).
  let dp = make2d(n, n, 0L)
  // Prefix sums of frequencies for O(1) range sum queries.
  let prefix = Array::make(n + 1, 0L)
  for i = 0; i < n; i = i + 1 {
    prefix[i + 1] = prefix[i] + freq[i].to_int64()
  }
  // Base case: single key.
  for i = 0; i < n; i = i + 1 {
    dp[i][i] = freq[i].to_int64()
  }
  // Chain length from 2 to n.
  let mut chain_len = 2
  while chain_len <= n {
    let mut i = 0
    while i + chain_len - 1 < n {
      let j = i + chain_len - 1
      dp[i][j] = 9223372036854775807L
      let freq_sum = prefix[j + 1] - prefix[i]
      let mut k = i
      while k <= j {
        let left = if k > i { dp[i][k - 1] } else { 0L }
        let right = if k < j { dp[k + 1][j] } else { 0L }
        let cost = left + right + freq_sum
        if cost < dp[i][j] {
          dp[i][j] = cost
        }
        k = k + 1
      }
      i = i + 1
    }
    chain_len = chain_len + 1
  }
  dp[0][n - 1]
}

// ---------------------------------------------------------------------------
// Burst Balloons
// ---------------------------------------------------------------------------

/// Maximise coins from bursting `n` balloons.
///
/// Given `n` balloons with values `nums[i]`, you burst them one at a time.
/// When you burst balloon `i`, you earn `nums[left] * nums[i] * nums[right]`
/// coins, where `left` and `right` are the nearest unburst balloons on each
/// side. After bursting, the balloon is removed.
///
/// # Parameters
/// - `nums`: values of the balloons. All values should be non-negative.
///
/// # Returns
/// The maximum coins collectible as `Int64`. Returns 0 for empty input.
///
/// # Complexity
/// - Time: O(n³)
/// - Space: O(n²)
///
/// Uses `Int64` for coin accumulation to prevent overflow.
pub fn burst_balloons(nums : FixedArray[Int]) -> Int64 {
  let n = nums.length()
  if n == 0 {
    return 0L
  }
  // Add sentinel balloons with value 1 at both ends.
  let m = n + 2
  let vals = FixedArray::make(m, 1)
  for i = 0; i < n; i = i + 1 {
    vals[i + 1] = nums[i]
  }
  // dp[i][j] = max coins from bursting balloons in (i, j) open interval.
  let dp = make2d(m, m, 0L)
  let mut gap = 2
  while gap < m {
    let mut i = 0
    while i + gap < m {
      let j = i + gap
      let mut k = i + 1
      while k < j {
        let coins = dp[i][k] + dp[k][j] +
          vals[i].to_int64() * vals[k].to_int64() * vals[j].to_int64()
        if coins > dp[i][j] {
          dp[i][j] = coins
        }
        k = k + 1
      }
      i = i + 1
    }
    gap = gap + 1
  }
  dp[0][m - 1]
}

// ---------------------------------------------------------------------------
// Stone Merge (Minimum Cost)
// ---------------------------------------------------------------------------

/// Find the minimum cost to merge all stone piles into one.
///
/// Given `n` piles of stones, you repeatedly merge two adjacent piles into
/// one, with cost equal to the sum of their sizes. The goal is to minimise
/// the total merge cost.
///
/// # Parameters
/// - `stones`: sizes of the piles. All sizes should be positive.
///
/// # Returns
/// The minimum total merge cost as `Int64`. Returns 0 for empty input.
///
/// # Complexity
/// - Time: O(n³)
/// - Space: O(n²)
///
/// Uses `Int64` for cost accumulation to prevent overflow.
pub fn merge_stones(stones : FixedArray[Int]) -> Int64 {
  let n = stones.length()
  if n <= 1 {
    return 0L
  }
  // dp[i][j] = minimum cost to merge piles i..j (inclusive) into one.
  let dp = make2d(n, n, 0L)
  // Prefix sums for O(1) range sum queries.
  let prefix = Array::make(n + 1, 0L)
  for i = 0; i < n; i = i + 1 {
    prefix[i + 1] = prefix[i] + stones[i].to_int64()
  }
  let mut chain_len = 2
  while chain_len <= n {
    let mut i = 0
    while i + chain_len - 1 < n {
      let j = i + chain_len - 1
      dp[i][j] = 9223372036854775807L
      let range_sum = prefix[j + 1] - prefix[i]
      let mut k = i + 1
      while k <= j {
        let cost = dp[i][k - 1] + dp[k][j] + range_sum
        if cost < dp[i][j] {
          dp[i][j] = cost
        }
        k = k + 1
      }
      i = i + 1
    }
    chain_len = chain_len + 1
  }
  dp[0][n - 1]
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "matrix_chain: basic" {
  // Matrices: A0(10×100), A1(100×5), A2(5×50)
  // Optimal: (A0*A1)*A2 = 10*100*5 + 10*5*50 = 5000 + 2500 = 7500
  // Suboptimal: A0*(A1*A2) = 100*5*50 + 10*100*50 = 25000 + 50000 = 75000
  let dims = FixedArray::make(4, 0)
  dims[0] = 10
  dims[1] = 100
  dims[2] = 5
  dims[3] = 50
  let result = matrix_chain(dims)
  assert_eq(result.min_cost, 7500L)
}

test "matrix_chain: two matrices" {
  let dims = FixedArray::make(3, 0)
  dims[0] = 10
  dims[1] = 20
  dims[2] = 30
  let result = matrix_chain(dims)
  // Only one way: A0 * A1 = 10*20*30 = 6000
  // Non-trivial split is wrapped in parentheses.
  assert_eq(result.min_cost, 6000L)
  assert_eq(result.parenthesization, "(A0A1)")
}

test "matrix_chain: single matrix" {
  let dims = FixedArray::make(2, 0)
  dims[0] = 10
  dims[1] = 20
  let result = matrix_chain(dims)
  assert_eq(result.min_cost, 0L)
  assert_eq(result.parenthesization, "A0")
}

test "matrix_chain: empty" {
  let dims : FixedArray[Int] = FixedArray::make(0, 0)
  let result = matrix_chain(dims)
  assert_eq(result.min_cost, 0L)
  assert_eq(result.parenthesization, "")
}

test "matrix_chain: classic example" {
  // CLRS example: dims = [30, 35, 15, 5, 10, 20, 25]
  // Expected minimum: 15125
  let dims = FixedArray::make(7, 0)
  dims[0] = 30
  dims[1] = 35
  dims[2] = 15
  dims[3] = 5
  dims[4] = 10
  dims[5] = 20
  dims[6] = 25
  let result = matrix_chain(dims)
  assert_eq(result.min_cost, 15125L)
}

test "matrix_chain: overflow protection" {
  // Large dimensions that would overflow Int32 when multiplied.
  let dims = FixedArray::make(4, 0)
  dims[0] = 100000
  dims[1] = 100000
  dims[2] = 100000
  dims[3] = 100000
  let result = matrix_chain(dims)
  // 3 matrices of 100000x100000: each split costs 100000^3 = 10^15,
  // total = 2 * 10^15 (fits in Int64, overflows Int32)
  assert_eq(result.min_cost, 2000000000000000L)
}

test "optimal_bst: single key" {
  let freq = FixedArray::make(1, 5)
  assert_eq(optimal_bst(freq), 5L)
}

test "optimal_bst: two keys" {
  // Keys: 0 (freq 1), 1 (freq 2)
  // Optimal: key 1 as root, key 0 as left child.
  // Cost = 1*2 + 2*1 = 4
  let freq = FixedArray::make(2, 0)
  freq[0] = 1
  freq[1] = 2
  assert_eq(optimal_bst(freq), 4L)
}

test "optimal_bst: three keys" {
  // Keys: 0 (freq 4), 1 (freq 2), 2 (freq 6)
  // Brute force (depth starts at 1 for root):
  // root = key 0, right = optimal(1,2):
  //   cost = 0 + dp[1][2] + sum = 0 + 10 + 12 = 22
  // root = key 1, left = key 0, right = key 2:
  //   cost = dp[0][0] + dp[2][2] + sum = 4 + 6 + 12 = 22
  // root = key 2, left = optimal(0,1):
  //   cost = dp[0][1] + 0 + sum = 8 + 0 + 12 = 20
  // So optimal is 20.
  let freq = FixedArray::make(3, 0)
  freq[0] = 4
  freq[1] = 2
  freq[2] = 6
  assert_eq(optimal_bst(freq), 20L)
}

test "optimal_bst: equal frequencies" {
  let freq = FixedArray::make(4, 1)
  // All frequencies equal: optimal is a balanced tree.
  // With 4 keys, a balanced tree has depths 1, 2, 2, 3.
  // Cost = 1*1 + 1*2 + 1*2 + 1*3 = 8
  assert_eq(optimal_bst(freq), 8L)
}

test "optimal_bst: empty" {
  let freq : FixedArray[Int] = FixedArray::make(0, 0)
  assert_eq(optimal_bst(freq), 0L)
}

test "burst_balloons: basic" {
  // nums = [3, 1, 5, 8]
  // Optimal order: burst 1 (coins = 3*1*5=15),
  //   burst 5 (coins = 3*5*8=120), burst 3 (coins = 1*3*8=24),
  //   burst 8 (coins = 1*8*1=8). Total = 15+120+24+8 = 167.
  let nums = FixedArray::make(4, 0)
  nums[0] = 3
  nums[1] = 1
  nums[2] = 5
  nums[3] = 8
  assert_eq(burst_balloons(nums), 167L)
}

test "burst_balloons: single balloon" {
  let nums = FixedArray::make(1, 5)
  // Burst the only balloon: coins = 1 * 5 * 1 = 5
  assert_eq(burst_balloons(nums), 5L)
}

test "burst_balloons: two balloons" {
  let nums = FixedArray::make(2, 0)
  nums[0] = 3
  nums[1] = 5
  // Burst 3 first: 1*3*5=15, then 5: 1*5*1=5. Total=20.
  // Burst 5 first: 3*5*1=15, then 3: 1*3*1=3. Total=18.
  // Max = 20.
  assert_eq(burst_balloons(nums), 20L)
}

test "burst_balloons: empty" {
  let nums : FixedArray[Int] = FixedArray::make(0, 0)
  assert_eq(burst_balloons(nums), 0L)
}

test "burst_balloons: zeros" {
  let nums = FixedArray::make(3, 0)
  // All zeros: every burst earns 0 coins.
  assert_eq(burst_balloons(nums), 0L)
}

test "merge_stones: basic" {
  // stones = [3, 4, 5]
  // Merge 3+4=7 (cost 7), then 7+5=12 (cost 12). Total = 19.
  // Or: Merge 4+5=9 (cost 9), then 3+9=12 (cost 12). Total = 21.
  // Min = 19.
  let stones = FixedArray::make(3, 0)
  stones[0] = 3
  stones[1] = 4
  stones[2] = 5
  assert_eq(merge_stones(stones), 19L)
}

test "merge_stones: two piles" {
  let stones = FixedArray::make(2, 0)
  stones[0] = 3
  stones[1] = 5
  // Only one merge: 3+5 = 8, cost = 8.
  assert_eq(merge_stones(stones), 8L)
}

test "merge_stones: single pile" {
  let stones = FixedArray::make(1, 5)
  assert_eq(merge_stones(stones), 0L) // no merge needed
}

test "merge_stones: empty" {
  let stones : FixedArray[Int] = FixedArray::make(0, 0)
  assert_eq(merge_stones(stones), 0L)
}

test "merge_stones: equal sizes" {
  let stones = FixedArray::make(4, 1)
  // All size 1: any merge order gives the same cost.
  // Merge 1+1=2, 1+1=2, then 2+2=4. Total = 2+2+4 = 8.
  assert_eq(merge_stones(stones), 8L)
}

test "merge_stones: large values (overflow check)" {
  let stones = FixedArray::make(3, 0)
  stones[0] = 1000000000
  stones[1] = 1000000000
  stones[2] = 1000000000
  // Merge 1e9 + 1e9 = 2e9 (cost 2e9), then 2e9 + 1e9 = 3e9 (cost 3e9).
  // Total = 5e9, which overflows Int32 but fits Int64.
  assert_eq(merge_stones(stones), 5000000000L)
}
