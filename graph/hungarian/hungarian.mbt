/// Hungarian algorithm for maximum-weight bipartite matching.
///
/// Given an `n × n` cost matrix where `cost[i][j]` is the cost of matching
/// left vertex `i` to right vertex `j`, finds a perfect matching that
/// maximises the total weight (or minimises total cost).
///
/// ## Algorithm
///
/// Uses the Kuhn-Munkres algorithm with potential (dual variable)
/// maintenance. The potentials `u[]` and `v[]` satisfy the complementary
/// slackness condition `u[i] + v[j] <= cost[i][j]` for all `i, j`. An edge
/// is "tight" when `u[i] + v[j] == cost[i][j]`. The algorithm grows a
/// matching on tight edges, adjusting potentials when stuck.
///
/// ## Complexity
///
/// O(n³) time, O(n²) space. For n ≤ 500 this runs in well under a second.
///
/// ## API
///
/// - `max_weight_matching(cost)` — returns `Some((total, assignment))` where
///   `total` is the maximum total weight and `assignment[i]` is the right
///   vertex matched to left vertex `i`. Returns `None` for invalid input.
/// - `min_cost_matching(cost)` — same but minimises total cost.
///
/// All arithmetic uses `Int64` to prevent overflow for large cost values.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Core algorithm
// ---------------------------------------------------------------------------

/// Maximum-weight perfect bipartite matching.
///
/// `cost` is a flat `n × n` matrix in row-major order. Returns
/// `Some((total_weight, assignment))` where `assignment[i]` is the right
/// vertex assigned to left vertex `i`. Returns `None` if `n <= 0` or the
/// matrix is too small.
pub fn max_weight_matching(
  cost : FixedArray[Int64],
  n : Int
) -> (Int64, FixedArray[Int])? {
  if n <= 0 || cost.length() < n * n {
    return None
  }
  // For max weight: negate costs and run min cost, then negate the result.
  let neg_cost = FixedArray::make(n * n, 0L)
  for i = 0; i < n * n; i = i + 1 {
    neg_cost[i] = -cost[i]
  }
  match min_cost_matching_core(neg_cost, n) {
    None => None
    Some((min_total, assignment)) => {
      Some((-min_total, assignment))
    }
  }
}

/// Minimum-cost perfect bipartite matching.
///
/// `cost` is a flat `n × n` matrix in row-major order. Returns
/// `Some((total_cost, assignment))` where `assignment[i]` is the right
/// vertex assigned to left vertex `i`. Returns `None` for invalid input.
pub fn min_cost_matching(
  cost : FixedArray[Int64],
  n : Int
) -> (Int64, FixedArray[Int])? {
  if n <= 0 || cost.length() < n * n {
    return None
  }
  min_cost_matching_core(cost, n)
}

/// Core Kuhn-Munkres algorithm (minimum cost variant).
fn min_cost_matching_core(
  cost : FixedArray[Int64],
  n : Int
) -> (Int64, FixedArray[Int])? {
  // Use 1-indexed arrays for cleaner indexing.
  // u[1..n] = left potentials, v[1..n] = right potentials.
  // p[1..n] = right-to-left matching (p[j] = left vertex matched to j).
  let u = Array::make(n + 1, 0L)
  let v = Array::make(n + 1, 0L)
  let p = Array::make(n + 1, 0)
  let way = Array::make(n + 1, 0)
  for i = 1; i <= n; i = i + 1 {
    p[0] = i // virtual column 0 is matched to row i
    let minv = Array::make(n + 1, 9223372036854775807L)
    let used = Array::make(n + 1, false)
    let mut j = 0
    while true {
      used[j] = true
      let i0 = p[j]
      let mut delta = 9223372036854775807L
      let mut j1 = -1
      for k = 1; k <= n; k = k + 1 {
        if !used[k] {
          // cost is 0-indexed: cost[(i0-1)*n + (k-1)]
          let cur = cost[(i0 - 1) * n + (k - 1)] - u[i0] - v[k]
          if cur < minv[k] {
            minv[k] = cur
            way[k] = j
          }
          if minv[k] < delta {
            delta = minv[k]
            j1 = k
          }
        }
      }
      for k = 0; k <= n; k = k + 1 {
        if used[k] {
          u[p[k]] = u[p[k]] + delta
          v[k] = v[k] - delta
        } else {
          minv[k] = minv[k] - delta
        }
      }
      j = j1
      if p[j] == 0 {
        break
      }
    }
    // Augment: follow the way array back.
    while j != 0 {
      let j1 = way[j]
      p[j] = p[j1]
      j = j1
    }
  }
  // Build assignment: result[i] = right vertex matched to left i (0-indexed).
  let assignment = FixedArray::make(n, 0)
  let mut total = 0L
  for j = 1; j <= n; j = j + 1 {
    let i = p[j] - 1 // 0-indexed left vertex
    assignment[i] = j - 1 // 0-indexed right vertex
    total = total + cost[i * n + (j - 1)]
  }
  Some((total, assignment))
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "hungarian: 1x1 min cost" {
  let cost : FixedArray[Int64] = [5L]
  let (total, assign) = min_cost_matching(cost, 1).unwrap()
  assert_eq(total, 5L)
  assert_eq(assign[0], 0)
}

test "hungarian: 1x1 max weight" {
  let cost : FixedArray[Int64] = [5L]
  let (total, assign) = max_weight_matching(cost, 1).unwrap()
  assert_eq(total, 5L)
  assert_eq(assign[0], 0)
}

test "hungarian: 2x2 min cost" {
  // Cost matrix:
  // [1, 2]
  // [3, 4]
  // Min cost: assign 0->0, 1->1 = 1+4 = 5
  // Or: assign 0->1, 1->0 = 2+3 = 5 (same)
  let cost : FixedArray[Int64] = [1L, 2L, 3L, 4L]
  let (total, assign) = min_cost_matching(cost, 2).unwrap()
  assert_eq(total, 5L)
  // Verify it's a valid matching.
  assert_true(assign[0] != assign[1])
}

test "hungarian: 2x2 max weight" {
  // Weight matrix:
  // [1, 2]
  // [3, 4]
  // Max weight: assign 0->1, 1->0 = 2+3 = 5
  // Or: assign 0->0, 1->1 = 1+4 = 5 (same)
  let cost : FixedArray[Int64] = [1L, 2L, 3L, 4L]
  let (total, assign) = max_weight_matching(cost, 2).unwrap()
  assert_eq(total, 5L)
  assert_true(assign[0] != assign[1])
}

test "hungarian: 3x3 min cost" {
  // Classic assignment problem.
  // [10, 5, 13]
  // [3, 7, 9]
  // [6, 8, 2]
  // Optimal: 0->1 (5), 1->0 (3), 2->2 (2) = 10
  let cost : FixedArray[Int64] = [
    10L, 5L, 13L,
    3L, 7L, 9L,
    6L, 8L, 2L,
  ]
  let (total, assign) = min_cost_matching(cost, 3).unwrap()
  assert_eq(total, 10L)
  assert_eq(assign[0], 1) // 0 -> 1 (cost 5)
  assert_eq(assign[1], 0) // 1 -> 0 (cost 3)
  assert_eq(assign[2], 2) // 2 -> 2 (cost 2)
}

test "hungarian: 3x3 max weight" {
  // Same matrix but maximised.
  // [10, 5, 13]
  // [3, 7, 9]
  // [6, 8, 2]
  // Optimal: 0->0 (10), 1->2 (9), 2->1 (8) = 27
  let cost : FixedArray[Int64] = [
    10L, 5L, 13L,
    3L, 7L, 9L,
    6L, 8L, 2L,
  ]
  let (total, assign) = max_weight_matching(cost, 3).unwrap()
  assert_eq(total, 27L)
  assert_eq(assign[0], 0) // 0 -> 0 (weight 10)
  assert_eq(assign[1], 2) // 1 -> 2 (weight 9)
  assert_eq(assign[2], 1) // 2 -> 1 (weight 8)
}

test "hungarian: 4x4 min cost" {
  // Classic problem from CLRS.
  // [9, 2, 7, 8]
  // [6, 4, 3, 7]
  // [5, 8, 1, 8]
  // [7, 6, 9, 4]
  // Optimal: 0->1 (2), 1->0 (6), 2->2 (1), 3->3 (4) = 13
  let cost : FixedArray[Int64] = [
    9L, 2L, 7L, 8L,
    6L, 4L, 3L, 7L,
    5L, 8L, 1L, 8L,
    7L, 6L, 9L, 4L,
  ]
  let (total, assign) = min_cost_matching(cost, 4).unwrap()
  assert_eq(total, 13L)
  // Verify it's a perfect matching (all distinct).
  let seen = FixedArray::make(4, false)
  for i = 0; i < 4; i = i + 1 {
    assert_true(assign[i] >= 0 && assign[i] < 4)
    assert_eq(seen[assign[i]], false)
    seen[assign[i]] = true
  }
  // Verify total matches the assignment.
  let mut verify = 0L
  for i = 0; i < 4; i = i + 1 {
    verify = verify + cost[i * 4 + assign[i]]
  }
  assert_eq(verify, total)
}

test "hungarian: invalid input" {
  let cost : FixedArray[Int64] = []
  assert_true(min_cost_matching(cost, 0) is None)
  assert_true(max_weight_matching(cost, 0) is None)
}

test "hungarian: symmetric matrix" {
  // All costs equal — any perfect matching is optimal.
  let n = 4
  let cost = FixedArray::make(n * n, 7L)
  let (total, assign) = min_cost_matching(cost, n).unwrap()
  assert_eq(total, (7 * n).to_int64())
  let seen = FixedArray::make(n, false)
  for i = 0; i < n; i = i + 1 {
    assert_true(assign[i] >= 0 && assign[i] < n)
    assert_eq(seen[assign[i]], false)
    seen[assign[i]] = true
  }
}

test "hungarian: 5x5 random verify" {
  // 5x5 matrix, verify against brute force.
  let n = 5
  let cost : FixedArray[Int64] = [
    3L, 8L, 2L, 9L, 1L,
    7L, 4L, 6L, 3L, 5L,
    2L, 7L, 9L, 4L, 8L,
    6L, 3L, 1L, 8L, 7L,
    5L, 9L, 4L, 2L, 6L,
  ]
  let (total, _) = min_cost_matching(cost, n).unwrap()
  // Brute force: try all permutations.
  let mut best = 9223372036854775807L
  // Simple: try all 5! = 120 permutations.
  for a = 0; a < 5; a = a + 1 {
    for b = 0; b < 5; b = b + 1 {
      if b == a { continue }
      for c = 0; c < 5; c = c + 1 {
        if c == a || c == b { continue }
        for d = 0; d < 5; d = d + 1 {
          if d == a || d == b || d == c { continue }
          let e = 10 - a - b - c - d
          let t = cost[a] + cost[5 + b] + cost[10 + c] + cost[15 + d] + cost[20 + e]
          if t < best {
            best = t
          }
        }
      }
    }
  }
  assert_eq(total, best)
}
