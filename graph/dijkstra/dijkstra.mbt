/// Dijkstra's shortest path algorithm.
/// Graph is represented as an adjacency matrix of non-negative weights.
/// graph[i * n + j] is the weight of edge i->j, or 0 if no edge.
/// Uses simple O(n^2) implementation (no priority queue needed for dense graphs).

/// Nonlinear arithmetic lemma: for 0 <= u < n, 0 <= v < n, 0 < n,
/// and n*n <= len, u*n + v < len holds. Z3 cannot prove this
/// automatically because it involves variable multiplication.
/// Declared as proof_axiomatized so the verifier assumes the
/// contract without discharging it.
pub fn graph_index_bound(
  u : Int,
  n : Int,
  v : Int,
  len : Int,
) -> Unit where {
  proof_axiomatized: true,
  proof_require: 0 <= u,
  proof_require: u < n,
  proof_require: 0 <= v,
  proof_require: v < n,
  proof_require: 0 < n,
  proof_require: n * n <= len,
  proof_ensure: u * n + v < len,
} {
  // proof_axiomatized: contract assumed without proof.
}

/// Compute shortest distances from src to all other nodes.
/// Returns a FixedArray[Int] where dist[i] is the shortest distance
/// from src to i, or -1 if unreachable.
///
/// Verification: array bounds and result length are formally verified.
/// Uses for-loop accumulator pattern instead of let mut to enable Z3
/// to track variable bounds across iterations.
pub fn dijkstra(
  graph : FixedArray[Int],
  n : Int,
  src : Int,
) -> FixedArray[Int] where {
  proof_require: 0 <= src && src < n,
  proof_require: 0 < n,
  proof_require: n * n <= graph.length(),
  proof_ensure: result => result.length() == n,
} {
  let dist = FixedArray::make(n, -1)
  let visited = FixedArray::make(n, 0)
  dist[src] = 0
  for step = 0; step < n; {
    // Find unvisited node with minimum distance using accumulator pattern
    let u = for i = 0, best = -1, best_dist = -1; i < n; {
      if visited[i] == 0 && dist[i] >= 0 {
        if best == -1 || dist[i] < best_dist {
          continue i + 1, i, dist[i]
        }
      }
      continue i + 1, best, best_dist
    } nobreak {
      best
    } where {
      proof_invariant: 0 <= i,
      proof_invariant: i <= n,
      proof_invariant: -1 <= best,
      proof_invariant: best < n,
    }
    if u == -1 {
      break
    }
    visited[u] = 1
    for v = 0; v < n; {
      graph_index_bound(u, n, v, graph.length())
      let weight = graph[u * n + v]
      if weight > 0 && visited[v] == 0 {
        let new_dist = dist[u] + weight
        if dist[v] == -1 || new_dist < dist[v] {
          dist[v] = new_dist
        }
      }
      continue v + 1
    } nobreak {
      ()
    } where {
      proof_invariant: 0 <= v,
      proof_invariant: v <= n,
    }
    continue step + 1
  } nobreak {
    ()
  } where {
    proof_invariant: 0 <= step,
    proof_invariant: step <= n,
  }
  dist
}

/// Compute shortest distance from src to dst.
/// Returns the distance, or -1 if unreachable or inputs are invalid.
pub fn shortest_path(
  graph : FixedArray[Int],
  n : Int,
  src : Int,
  dst : Int,
) -> Int {
  if n <= 0 || src < 0 || src >= n || dst < 0 || dst >= n {
    return -1
  }
  let dist = dijkstra(graph, n, src)
  dist[dst]
}

test "dijkstra: single node" {
  let graph = FixedArray::make(1, 0)
  let dist = dijkstra(graph, 1, 0)
  assert_eq(dist[0], 0)
}

test "dijkstra: path graph" {
  let n = 4
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 1
  graph[1 * n + 0] = 1
  graph[1 * n + 2] = 2
  graph[2 * n + 1] = 2
  graph[2 * n + 3] = 3
  graph[3 * n + 2] = 3
  let dist = dijkstra(graph, n, 0)
  assert_eq(dist[0], 0)
  assert_eq(dist[1], 1)
  assert_eq(dist[2], 3)
  assert_eq(dist[3], 6)
}

test "dijkstra: unreachable node" {
  let n = 3
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 5
  graph[1 * n + 0] = 5
  let dist = dijkstra(graph, n, 0)
  assert_eq(dist[0], 0)
  assert_eq(dist[1], 5)
  assert_eq(dist[2], -1)
}

test "dijkstra: shorter path through intermediate" {
  let n = 3
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 1
  graph[1 * n + 0] = 1
  graph[1 * n + 2] = 1
  graph[2 * n + 1] = 1
  graph[0 * n + 2] = 3
  graph[2 * n + 0] = 3
  let dist = dijkstra(graph, n, 0)
  assert_eq(dist[2], 2)
}

test "dijkstra: complete graph" {
  let n = 3
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 1
  graph[1 * n + 0] = 1
  graph[1 * n + 2] = 1
  graph[2 * n + 1] = 1
  graph[0 * n + 2] = 5
  graph[2 * n + 0] = 5
  let dist = dijkstra(graph, n, 0)
  assert_eq(dist[0], 0)
  assert_eq(dist[1], 1)
  assert_eq(dist[2], 2)
}

test "dijkstra: directed graph" {
  let n = 3
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 2
  graph[1 * n + 2] = 3
  let dist = dijkstra(graph, n, 0)
  assert_eq(dist[0], 0)
  assert_eq(dist[1], 2)
  assert_eq(dist[2], 5)
  let dist1 = dijkstra(graph, n, 1)
  assert_eq(dist1[0], -1)
  assert_eq(dist1[2], 3)
}

test "shortest_path: basic" {
  let n = 4
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 1
  graph[1 * n + 2] = 2
  graph[2 * n + 3] = 3
  graph[1 * n + 0] = 1
  graph[2 * n + 1] = 2
  graph[3 * n + 2] = 3
  assert_eq(shortest_path(graph, n, 0, 3), 6)
  assert_eq(shortest_path(graph, n, 0, 0), 0)
}

test "shortest_path: unreachable" {
  let n = 3
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 5
  assert_eq(shortest_path(graph, n, 0, 2), -1)
}

test "dijkstra: star graph" {
  let n = 5
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 1
  graph[1 * n + 0] = 1
  graph[0 * n + 2] = 1
  graph[2 * n + 0] = 1
  graph[0 * n + 3] = 1
  graph[3 * n + 0] = 1
  graph[0 * n + 4] = 1
  graph[4 * n + 0] = 1
  let dist = dijkstra(graph, n, 0)
  for k = 0; k < 5; k = k + 1 {
    assert_eq(dist[k], if k == 0 { 0 } else { 1 })
  }
}
