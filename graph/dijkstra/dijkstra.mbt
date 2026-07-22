/// Dijkstra's shortest path algorithm.
/// Graph is represented as an adjacency matrix of non-negative weights.
/// graph[i * n + j] is the weight of edge i->j, or 0 if no edge.
/// Uses simple O(n^2) implementation (no priority queue needed for dense graphs).

/// Compute shortest distances from src to all other nodes.
/// Returns a FixedArray[Int] where dist[i] is the shortest distance
/// from src to i, or -1 if unreachable.
pub fn dijkstra(
  graph : FixedArray[Int],
  n : Int,
  src : Int,
) -> FixedArray[Int] where {
  proof_require: 0 <= src && src < n,
  proof_require: n * n <= graph.length(),
  proof_ensure: result => all_dist_valid(result),
} {
  let dist = FixedArray::make(n, -1)
  let visited = FixedArray::make(n, 0)
  dist[src] = 0
  for step = 0; step < n; {
    let mut u = -1
    let mut min_dist = -1
    for i = 0; i < n; {
      if visited[i] == 0 && dist[i] >= 0 {
        if u == -1 || dist[i] < min_dist {
          u = i
          min_dist = dist[i]
        }
      }
      continue i + 1
    } nobreak {
      ()
    } where {
      proof_invariant: 0 <= i,
      proof_invariant: i <= n,
      proof_invariant: -1 <= u,
      proof_invariant: u < n,
    }
    if u == -1 {
      break
    }
    visited[u] = 1
    for v = 0; v < n; {
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
      proof_invariant: all_dist_valid(dist),
    }
    continue step + 1
  } nobreak {
    ()
  } where {
    proof_invariant: 0 <= step,
    proof_invariant: step <= n,
    proof_invariant: all_dist_valid(dist),
  }
  dist
}

/// Compute shortest distance from src to dst.
/// Returns the distance, or -1 if unreachable.
pub fn shortest_path(
  graph : FixedArray[Int],
  n : Int,
  src : Int,
  dst : Int,
) -> Int {
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
