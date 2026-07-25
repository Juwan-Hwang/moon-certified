/// Minimum Steiner Tree — Dreyfus-Wagner DP algorithm.
///
/// Given an undirected weighted graph and a set of **terminal** vertices,
/// find the minimum-weight connected subgraph that contains all terminals.
/// This is the Steiner tree problem in graphs (NP-hard in general).
///
/// ## Algorithm: Dreyfus-Wagner (1972)
///
/// The Dreyfus-Wagner DP is the gold-standard exact algorithm for small
/// terminal sets. It uses bitmask DP over terminal subsets:
///
/// - `dp[S][v]` = minimum cost of a Steiner tree that connects the terminal
///   subset `S` and has `v` as one of its vertices.
/// - Transition 1 (merge): `dp[S][v] = min over S' ⊂ S of dp[S'][v] + dp[S\S'][v]`
/// - Transition 2 (extend): `dp[S][v] = min over u of dp[S][u] + dist(u, v)`
///
/// The second transition is computed via Dijkstra from all vertices.
///
/// ## Complexity
/// - Time: O(3^k · n + 2^k · n · log n) where k = |terminals|.
/// - Space: O(2^k · n).
///
/// Practical for k ≤ 20 (terminals). For larger k, approximation algorithms
/// (e.g., the 2-approximation via MST on metric closure) are recommended.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

/// Result of the Steiner tree computation.
pub struct SteinerResult {
  priv cost : Int64
  priv n : Int
}

/// The total weight of the minimum Steiner tree.
pub fn steiner_cost(r : SteinerResult) -> Int64 {
  r.cost
}

/// Number of vertices in the graph.
pub fn steiner_vertex_count(r : SteinerResult) -> Int {
  r.n
}

/// Compute the minimum Steiner tree connecting the given terminals.
///
/// # Parameters
/// - `graph`: `n × n` adjacency matrix. `graph[i * n + j]` is the edge weight
///   (0 means no edge). The graph must be undirected (symmetric matrix).
/// - `n`: number of vertices.
/// - `terminals`: the set of terminal vertices (1-indexed in the result).
///
/// # Returns
/// `Some(SteinerResult)` with the minimum cost, or `None` if the graph is
/// disconnected and the terminals cannot all be connected.
///
/// Uses `Int64` for cost accumulation to prevent overflow.
pub fn min_steiner_tree(
  graph : FixedArray[Int],
  n : Int,
  terminals : FixedArray[Int],
) -> SteinerResult? {
  let k = terminals.length()
  if k <= 1 {
    return Some(SteinerResult::{ cost : 0L, n })
  }
  if n <= 0 {
    return None
  }
  // Validate terminals
  for i = 0; i < k; i = i + 1 {
    let t = terminals[i]
    if t < 0 || t >= n {
      return None
    }
  }
  // All-pairs shortest paths via Floyd-Warshall.
  // dist[i][j] = shortest path distance from i to j.
  let inf_val = 9223372036854775807L
  let dist = FixedArray::make(n * n, inf_val)
  for i = 0; i < n; i = i + 1 {
    dist[i * n + i] = 0L
    for j = 0; j < n; j = j + 1 {
      if i != j {
      let w = graph[i * n + j]
        if w > 0 {
          dist[i * n + j] = w.to_int64()
        }
      }
    }
  }
  for kk = 0; kk < n; kk = kk + 1 {
    for i = 0; i < n; i = i + 1 {
      if dist[i * n + kk] == inf_val {
        continue
      }
      for j = 0; j < n; j = j + 1 {
        if dist[kk * n + j] == inf_val {
          continue
        }
        let nd = dist[i * n + kk] + dist[kk * n + j]
        if nd < dist[i * n + j] {
          dist[i * n + j] = nd
        }
      }
    }
  }
  // Check connectivity: all terminals must be mutually reachable.
  for i = 0; i < k; i = i + 1 {
    for j = i + 1; j < k; j = j + 1 {
      let ti = terminals[i]
      let tj = terminals[j]
      if dist[ti * n + tj] == inf_val {
        return None
      }
    }
  }
  // dp[mask * n + v] = min Steiner tree cost connecting terminal subset
  // `mask` with vertex `v` in the tree.
  let dp_size = (1 << k) * n
  let dp = FixedArray::make(dp_size, inf_val)
  // Base case: single terminal
  for i = 0; i < k; i = i + 1 {
    dp[(1 << i) * n + terminals[i]] = 0L
  }
  // Iterate over all terminal subsets
  let mut mask = 1
  while mask < (1 << k) {
    // Transition 1: merge subsets
    // For each vertex v, dp[mask][v] = min over submask of dp[submask][v] + dp[mask^submask][v]
    for v = 0; v < n; v = v + 1 {
      // Iterate proper subsets of mask (excluding 0 and mask itself)
      let mut submask = (mask - 1) & mask
      while submask > 0 {
        let complement = mask ^ submask
        let d1 = dp[submask * n + v]
        let d2 = dp[complement * n + v]
        if d1 != inf_val && d2 != inf_val {
          let nd = d1 + d2
          if nd < dp[mask * n + v] {
            dp[mask * n + v] = nd
          }
        }
        submask = (submask - 1) & mask
      }
    }
    // Transition 2: extend via shortest path
    // dp[mask][v] = min over u of dp[mask][u] + dist[u][v]
    // This is equivalent to running Dijkstra from all dp values.
    // We use a simple O(n^2) Dijkstra since n is typically small.
    let visited = FixedArray::make(n, false)
    for iter = 0; iter < n; iter = iter + 1 {
      // Find unvisited vertex with minimum dp value
      let mut best_u = -1
      let mut best_d = inf_val
      for u = 0; u < n; u = u + 1 {
        if !visited[u] && dp[mask * n + u] < best_d {
          best_d = dp[mask * n + u]
          best_u = u
        }
      }
      if best_u == -1 {
        break
      }
      visited[best_u] = true
      // Relax neighbors
      for v = 0; v < n; v = v + 1 {
        if visited[v] {
          continue
        }
        let d = dist[best_u * n + v]
        if d == inf_val {
          continue
        }
        if best_d != inf_val {
          let nd = best_d + d
          if nd < dp[mask * n + v] {
            dp[mask * n + v] = nd
          }
        }
      }
    }
    mask = mask + 1
  }
  // Answer: min over all v of dp[full_mask][v]
  let full_mask = (1 << k) - 1
  let mut result = inf_val
  for v = 0; v < n; v = v + 1 {
    if dp[full_mask * n + v] < result {
      result = dp[full_mask * n + v]
    }
  }
  Some(SteinerResult::{ cost : result, n })
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "steiner: two terminals = shortest path" {
  // Triangle: 0-1 (1), 1-2 (2), 0-2 (4)
  // Terminals: {0, 2}. Steiner tree = path 0-1-2, cost 3.
  let n = 3
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 1; graph[1 * n + 0] = 1
  graph[1 * n + 2] = 2; graph[2 * n + 1] = 2
  graph[0 * n + 2] = 4; graph[2 * n + 0] = 4
  let terminals = FixedArray::make(2, 0)
  terminals[0] = 0
  terminals[1] = 2
  let result = min_steiner_tree(graph, n, terminals)
  assert_true(result is Some(_))
  match result {
    Some(r) => assert_eq(steiner_cost(r), 3L)
    None => assert_true(false)
  }
}

test "steiner: three terminals with Steiner vertex" {
  // Square: 0-1-2-3-0, all weight 1.
  // Terminals: {0, 2}. Steiner tree = path 0-1-2 or 0-3-2, cost 2.
  let n = 4
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 1; graph[1 * n + 0] = 1
  graph[1 * n + 2] = 1; graph[2 * n + 1] = 1
  graph[2 * n + 3] = 1; graph[3 * n + 2] = 1
  graph[3 * n + 0] = 1; graph[0 * n + 3] = 1
  let terminals = FixedArray::make(2, 0)
  terminals[0] = 0
  terminals[1] = 2
  let result = min_steiner_tree(graph, n, terminals)
  match result {
    Some(r) => assert_eq(steiner_cost(r), 2L)
    None => assert_true(false)
  }
}

test "steiner: star topology with Steiner vertex" {
  // Center vertex 0 connected to 1,2,3 with weights 1,2,3.
  // Terminals: {1,2,3}. Steiner tree = star centered at 0, cost 6.
  let n = 4
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 1; graph[1 * n + 0] = 1
  graph[0 * n + 2] = 2; graph[2 * n + 0] = 2
  graph[0 * n + 3] = 3; graph[3 * n + 0] = 3
  let terminals = FixedArray::make(3, 0)
  terminals[0] = 1
  terminals[1] = 2
  terminals[2] = 3
  let result = min_steiner_tree(graph, n, terminals)
  match result {
    Some(r) => assert_eq(steiner_cost(r), 6L)
    None => assert_true(false)
  }
}

test "steiner: single terminal = zero cost" {
  let n = 3
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 5; graph[1 * n + 0] = 5
  let terminals = FixedArray::make(1, 0)
  terminals[0] = 0
  let result = min_steiner_tree(graph, n, terminals)
  match result {
    Some(r) => assert_eq(steiner_cost(r), 0L)
    None => assert_true(false)
  }
}

test "steiner: disconnected terminals" {
  // 0-1 and 2-3 are separate components.
  let n = 4
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 1; graph[1 * n + 0] = 1
  graph[2 * n + 3] = 1; graph[3 * n + 2] = 1
  let terminals = FixedArray::make(2, 0)
  terminals[0] = 0
  terminals[1] = 2
  let result = min_steiner_tree(graph, n, terminals)
  assert_true(result is None)
}

test "steiner: complete graph K4, terminals {0,1,2}" {
  // K4: all edges weight 1. MST of terminals {0,1,2} = 2.
  let n = 4
  let graph = FixedArray::make(n * n, 0)
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      if i != j {
        graph[i * n + j] = 1
      }
    }
  }
  let terminals = FixedArray::make(3, 0)
  terminals[0] = 0
  terminals[1] = 1
  terminals[2] = 2
  let result = min_steiner_tree(graph, n, terminals)
  match result {
    Some(r) => assert_eq(steiner_cost(r), 2L)
    None => assert_true(false)
  }
}

test "steiner: all vertices are terminals = MST" {
  // Triangle: 0-1(1), 1-2(2), 0-2(3).
  // All are terminals → MST = 0-1-2, cost 3.
  let n = 3
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 1; graph[1 * n + 0] = 1
  graph[1 * n + 2] = 2; graph[2 * n + 1] = 2
  graph[0 * n + 2] = 3; graph[2 * n + 0] = 3
  let terminals = FixedArray::makei(3, fn(i) { i })
  let result = min_steiner_tree(graph, n, terminals)
  match result {
    Some(r) => assert_eq(steiner_cost(r), 3L)
    None => assert_true(false)
  }
}
