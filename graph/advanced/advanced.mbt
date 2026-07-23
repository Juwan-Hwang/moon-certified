/// Advanced shortest-path algorithms: Bellman-Ford (single-source with
/// negative weights) and Floyd-Warshall (all-pairs).
///
/// Graphs use the same adjacency-matrix convention as the `dijkstra` package:
/// `graph[i * n + j]` is the weight of edge `i -> j`, or `0` when no edge
/// exists. A weight of `0` therefore always means "no edge".
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below,
/// including a cross-check between the two algorithms.

/// Bellman-Ford: shortest paths from `src`, handling negative weights.
///
/// `graph` is an `n * n` adjacency matrix where `graph[i * n + j]` is the
/// edge weight or `0` if there is no edge. Returns a `FixedArray[Int]` of
/// distances from `src`; unreachable vertices are reported as `-1`. Returns
/// an empty array if a negative cycle is reachable from `src`.
///
/// A `reachable` table is carried alongside the distance table so that `-1`
/// (the unreachable marker) never collides with a legitimate negative
/// shortest distance. Relaxation runs for at most `n - 1` passes with an
/// early exit once a pass makes no change; one further pass detects any
/// negative cycle reachable from the source.
pub fn bellman_ford(
  graph : FixedArray[Int],
  n : Int,
  src : Int,
) -> FixedArray[Int] {
  if n <= 0 || src < 0 || src >= n || graph.length() < n * n {
    return FixedArray::make(0, 0)
  }
  let dist = FixedArray::make(n, 0)
  let reachable = FixedArray::make(n, false)
  dist[src] = 0
  reachable[src] = true
  // At most n-1 relaxation passes suffice when no negative cycle exists.
  // Early-exit as soon as a full pass makes no change.
  for pass = 0; pass < n - 1; pass = pass + 1 {
    let mut updated = false
    for u = 0; u < n; u = u + 1 {
      if reachable[u] {
        let du = dist[u]
        for v = 0; v < n; v = v + 1 {
          let w = graph[u * n + v]
          if w != 0 {
            let nd = du + w
            if !reachable[v] || nd < dist[v] {
              dist[v] = nd
              reachable[v] = true
              updated = true
            }
          }
        }
      }
    }
    if !updated {
      break
    }
  }
  // Detection pass: if any edge from a reachable vertex can still relax a
  // reachable vertex, a negative cycle is reachable from src.
  for u = 0; u < n; u = u + 1 {
    if reachable[u] {
      let du = dist[u]
      for v = 0; v < n; v = v + 1 {
        let w = graph[u * n + v]
        if w != 0 && reachable[v] && du + w < dist[v] {
          return FixedArray::make(0, 0)
        }
      }
    }
  }
  // Materialise the result, mapping unreachable vertices to -1.
  let result = FixedArray::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    result[i] = if reachable[i] { dist[i] } else { -1 }
  }
  result
}

/// Floyd-Warshall: all-pairs shortest paths.
///
/// `graph` is an `n * n` adjacency matrix where `graph[i * n + j]` is the
/// edge weight or `0` if there is no edge. Returns an `n * n` array where
/// `result[i * n + j]` is the shortest distance from `i` to `j`; unreachable
/// pairs are reported as `-1`. Returns an empty array if a negative cycle
/// exists anywhere in the graph.
///
/// A large sentinel is used internally for "no path yet". The diagonal is
/// initialised to `0` (the cost of the empty walk); a negative self-loop is
/// seeded onto the diagonal so that, after relaxation, any negative value on
/// the diagonal signals a negative cycle.
pub fn floyd_warshall(graph : FixedArray[Int], n : Int) -> FixedArray[Int] {
  if n <= 0 || graph.length() < n * n {
    return FixedArray::make(0, 0)
  }
  let inf = 1000000000
  let dist = FixedArray::make(n * n, inf)
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      if i == j {
        dist[i * n + j] = 0
        // A negative self-loop is itself a negative cycle; seed it so the
        // diagonal check below fires. Positive self-loops are dominated by 0.
        let w = graph[i * n + i]
        if w != 0 && w < 0 {
          dist[i * n + j] = w
        }
      } else {
        let w = graph[i * n + j]
        if w != 0 {
          dist[i * n + j] = w
        }
      }
    }
  }
  // Classic triple loop: try routing i -> j through each intermediate k.
  // The `!= inf` guards prevent the sentinel from being added (which could
  // overflow) and skip pairs that have no path yet.
  for k = 0; k < n; k = k + 1 {
    for i = 0; i < n; i = i + 1 {
      let dik = dist[i * n + k]
      if dik != inf {
        for j = 0; j < n; j = j + 1 {
          let dkj = dist[k * n + j]
          if dkj != inf {
            let nd = dik + dkj
            if nd < dist[i * n + j] {
              dist[i * n + j] = nd
            }
          }
        }
      }
    }
  }
  // Any negative value on the diagonal means a vertex can reach itself with
  // negative total cost: a negative cycle.
  for i = 0; i < n; i = i + 1 {
    if dist[i * n + i] < 0 {
      return FixedArray::make(0, 0)
    }
  }
  // Map the sentinel back to -1 for unreachable pairs.
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      if dist[i * n + j] == inf {
        dist[i * n + j] = -1
      }
    }
  }
  dist
}

// ---------------------------------------------------------------------------
// Bellman-Ford tests
// ---------------------------------------------------------------------------

test "bellman_ford: basic path graph" {
  let n = 4
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 1
  graph[1 * n + 0] = 1
  graph[1 * n + 2] = 2
  graph[2 * n + 1] = 2
  graph[2 * n + 3] = 3
  graph[3 * n + 2] = 3
  let dist = bellman_ford(graph, n, 0)
  assert_eq(dist[0], 0)
  assert_eq(dist[1], 1)
  assert_eq(dist[2], 3)
  assert_eq(dist[3], 6)
}

test "bellman_ford: negative weights, no cycle" {
  let n = 3
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 4
  graph[0 * n + 2] = 5
  graph[1 * n + 2] = -3
  let dist = bellman_ford(graph, n, 0)
  assert_eq(dist[0], 0)
  assert_eq(dist[1], 4)
  assert_eq(dist[2], 1) // 0 -> 1 -> 2 = 4 + (-3) = 1
}

test "bellman_ford: unreachable vertices" {
  let n = 3
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 5
  graph[1 * n + 0] = 5
  let dist = bellman_ford(graph, n, 0)
  assert_eq(dist[0], 0)
  assert_eq(dist[1], 5)
  assert_eq(dist[2], -1)
}

test "bellman_ford: negative cycle detection" {
  // 0 -> 1 (1), 1 -> 2 (-3), 2 -> 1 (-3): cycle 1->2->1 has weight -6.
  let n = 3
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 1
  graph[1 * n + 2] = -3
  graph[2 * n + 1] = -3
  let dist = bellman_ford(graph, n, 0)
  assert_eq(dist.length(), 0)
}

test "bellman_ford: negative cycle unreachable from src is not reported" {
  // Standard Bellman-Ford only flags negative cycles reachable from src.
  let n = 4
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 2 // src 0 reaches only {0, 1}
  // Negative cycle confined to {2, 3}, unreachable from 0.
  graph[2 * n + 3] = -1
  graph[3 * n + 2] = -1
  let dist = bellman_ford(graph, n, 0)
  assert_eq(dist.length(), n)
  assert_eq(dist[0], 0)
  assert_eq(dist[1], 2)
  assert_eq(dist[2], -1)
  assert_eq(dist[3], -1)
}

test "bellman_ford: single node" {
  let graph = FixedArray::make(1, 0)
  let dist = bellman_ford(graph, 1, 0)
  assert_eq(dist.length(), 1)
  assert_eq(dist[0], 0)
}

test "bellman_ford: shorter path through intermediate" {
  let n = 3
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 1
  graph[1 * n + 0] = 1
  graph[1 * n + 2] = 1
  graph[2 * n + 1] = 1
  graph[0 * n + 2] = 5
  graph[2 * n + 0] = 5
  let dist = bellman_ford(graph, n, 0)
  assert_eq(dist[2], 2) // 0 -> 1 -> 2 = 2 < direct 5
}

test "bellman_ford: directed graph" {
  let n = 3
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 2
  graph[1 * n + 2] = 3
  let dist = bellman_ford(graph, n, 0)
  assert_eq(dist[0], 0)
  assert_eq(dist[1], 2)
  assert_eq(dist[2], 5)
  let dist1 = bellman_ford(graph, n, 1)
  assert_eq(dist1[0], -1)
  assert_eq(dist1[2], 3)
}

test "bellman_ford: disconnected graph" {
  let n = 4
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 2
  graph[1 * n + 0] = 2
  // Vertices 2 and 3 form a separate component.
  graph[2 * n + 3] = 4
  graph[3 * n + 2] = 4
  let dist = bellman_ford(graph, n, 0)
  assert_eq(dist[0], 0)
  assert_eq(dist[1], 2)
  assert_eq(dist[2], -1)
  assert_eq(dist[3], -1)
}

// ---------------------------------------------------------------------------
// Floyd-Warshall tests
// ---------------------------------------------------------------------------

test "floyd_warshall: basic path graph" {
  let n = 4
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 1
  graph[1 * n + 0] = 1
  graph[1 * n + 2] = 2
  graph[2 * n + 1] = 2
  graph[2 * n + 3] = 3
  graph[3 * n + 2] = 3
  let d = floyd_warshall(graph, n)
  assert_eq(d.length(), n * n)
  assert_eq(d[0 * n + 0], 0)
  assert_eq(d[0 * n + 1], 1)
  assert_eq(d[0 * n + 2], 3)
  assert_eq(d[0 * n + 3], 6)
  assert_eq(d[3 * n + 0], 6)
  assert_eq(d[2 * n + 2], 0)
}

test "floyd_warshall: with negative edges" {
  let n = 3
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 4
  graph[0 * n + 2] = 5
  graph[1 * n + 2] = -3
  let d = floyd_warshall(graph, n)
  assert_eq(d[0 * n + 0], 0)
  assert_eq(d[0 * n + 1], 4)
  assert_eq(d[0 * n + 2], 1) // via 1
  assert_eq(d[1 * n + 2], -3)
  assert_eq(d[1 * n + 0], -1) // unreachable in this directed graph
  assert_eq(d[2 * n + 0], -1)
  assert_eq(d[2 * n + 1], -1)
}

test "floyd_warshall: negative cycle" {
  let n = 3
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 1
  graph[1 * n + 2] = -3
  graph[2 * n + 1] = -3
  let d = floyd_warshall(graph, n)
  assert_eq(d.length(), 0)
}

test "floyd_warshall: single node" {
  let graph = FixedArray::make(1, 0)
  let d = floyd_warshall(graph, 1)
  assert_eq(d.length(), 1)
  assert_eq(d[0], 0)
}

test "floyd_warshall: disconnected graph" {
  let n = 3
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 2
  graph[1 * n + 0] = 2
  // Vertex 2 is isolated.
  let d = floyd_warshall(graph, n)
  assert_eq(d[0 * n + 1], 2)
  assert_eq(d[1 * n + 0], 2)
  assert_eq(d[0 * n + 2], -1)
  assert_eq(d[2 * n + 0], -1)
  assert_eq(d[1 * n + 2], -1)
  assert_eq(d[2 * n + 1], -1)
  assert_eq(d[2 * n + 2], 0)
}

test "floyd_warshall: complete graph K3" {
  let n = 3
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 1
  graph[1 * n + 0] = 1
  graph[1 * n + 2] = 1
  graph[2 * n + 1] = 1
  graph[0 * n + 2] = 5
  graph[2 * n + 0] = 5
  let d = floyd_warshall(graph, n)
  // All pairs reachable; shortest 0->2 and 2->0 go via 1 (cost 2).
  assert_eq(d[0 * n + 2], 2)
  assert_eq(d[2 * n + 0], 2)
  assert_eq(d[0 * n + 1], 1)
  for i = 0; i < n; i = i + 1 {
    assert_eq(d[i * n + i], 0)
  }
}

test "floyd_warshall: directed graph" {
  let n = 3
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 2
  graph[1 * n + 2] = 3
  let d = floyd_warshall(graph, n)
  assert_eq(d[0 * n + 1], 2)
  assert_eq(d[1 * n + 2], 3)
  assert_eq(d[0 * n + 2], 5)
  assert_eq(d[1 * n + 0], -1)
  assert_eq(d[2 * n + 0], -1)
  assert_eq(d[2 * n + 1], -1)
}

test "bellman_ford and floyd_warshall agree" {
  // On a graph with no negative cycle, the single-source row from
  // floyd_warshall must match bellman_ford exactly.
  let n = 4
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 2
  graph[1 * n + 2] = -1
  graph[2 * n + 3] = 4
  graph[3 * n + 0] = 1
  graph[0 * n + 3] = 10
  let bf = bellman_ford(graph, n, 0)
  let fw = floyd_warshall(graph, n)
  assert_eq(fw.length(), n * n) // no negative cycle
  for j = 0; j < n; j = j + 1 {
    assert_eq(bf[j], fw[0 * n + j])
  }
}
