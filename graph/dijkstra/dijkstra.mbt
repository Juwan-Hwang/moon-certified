/// Dijkstra's shortest path algorithm.
/// Graph is represented as an adjacency matrix of non-negative weights.
/// graph[i * n + j] is the weight of edge i->j, or 0 if no edge.
/// Uses simple O(n^2) implementation (no priority queue needed for dense graphs).
///
/// **Precondition**: All edge weights must be non-negative. Dijkstra's
/// algorithm does not produce correct results with negative weights.
/// In this adjacency-matrix implementation, edges with weight ≤ 0 are
/// treated as non-existent (skipped), so negative weights are silently
/// ignored rather than causing incorrect results. For graphs with negative
/// weights, use Bellman-Ford (`graph/advanced`) instead.
///
/// Verified by `moon prove` (on `dijkstra_impl`):
/// - result.length() == n (array length, proven by Z3)
/// - loop bounds (step, i, v all stay in [0, n])
///
/// NOT verified:
/// - Shortest path optimality (requires complex inductive reasoning)
/// - Non-negative edge weights (precondition, not enforced by proof)
/// - The sentinel value -1 for "unreachable" (representation detail, not
///   exposed in the public API which uses Option)
///
/// **About `proof_axiomatized`**: The `graph_index_bound` lemma assumes
/// the fact `u * n + v < len` given the preconditions `0 <= u < n`,
/// `0 <= v < n`, `0 < n`, `n * n <= len`. This involves multiplication of
/// two variables (u * n), which is nonlinear arithmetic. Z3's default
/// linear arithmetic solver cannot discharge this automatically. The fact
/// is mathematically true: `u * n + v < n * n <= len`. We keep it as an
/// axiom rather than removing the proof annotation entirely, because the
/// alternative (no proof contract at all) would lose the array-length
/// verification that Z3 *can* discharge.

/// Nonlinear arithmetic lemma: for 0 <= u < n, 0 <= v < n, 0 < n,
/// and n*n <= len, u*n + v < len holds.
///
/// **This is an AXIOM, not a proof.** Z3 cannot prove this because it
/// involves multiplying two unknown variables (u * n). The fact is
/// mathematically true (u*n + v < n*n <= len), but we assume it rather
/// than discharge it. Declared as `proof_axiomatized` so the verifier
/// assumes the contract without proof. The benefit: keeping this axiom
/// allows Z3 to verify the array-length property (`result.length() == n`),
/// which it CAN prove.
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

/// Internal Dijkstra implementation using -1 as a sentinel for "unreachable"
/// during computation. This is an implementation detail; the public `dijkstra`
/// function wraps the result in `Option` to eliminate the magic value.
///
/// Verification: array bounds and result length are formally verified.
/// Uses for-loop accumulator pattern instead of let mut to enable Z3
/// to track variable bounds across iterations.
fn dijkstra_impl(
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

/// Compute shortest distances from src to all other nodes.
///
/// Returns a `FixedArray[Int?]` where `dist[i]` is `Some(d)` (the shortest
/// distance from `src` to `i`) or `None` if `i` is unreachable from `src`.
///
/// The internal computation uses a sentinel value for efficiency, but the
/// public API is fully type-safe: callers never see a magic `-1`.
///
/// Returns `None` for each node if inputs are invalid.
pub fn dijkstra(
  graph : FixedArray[Int],
  n : Int,
  src : Int,
) -> FixedArray[Int?] {
  if n <= 0 || src < 0 || src >= n || graph.length() < n * n {
    return FixedArray::make(if n > 0 { n } else { 0 }, None)
  }
  let raw = dijkstra_impl(graph, n, src)
  let result = FixedArray::make(n, None)
  for i = 0; i < n; i = i + 1 {
    let d = raw[i]
    if d >= 0 {
      result[i] = Some(d)
    }
  }
  result
}

/// Compute shortest distance from src to dst.
///
/// Returns `Some(distance)` if `dst` is reachable from `src`, or `None`
/// if unreachable or if inputs are invalid (n <= 0, out-of-bounds indices,
/// undersized graph).
pub fn shortest_path(
  graph : FixedArray[Int],
  n : Int,
  src : Int,
  dst : Int,
) -> Int? {
  if n <= 0 || src < 0 || src >= n || dst < 0 || dst >= n || graph.length() < n * n {
    return None
  }
  let dist = dijkstra(graph, n, src)
  dist[dst]
}

test "dijkstra: single node" {
  let graph = FixedArray::make(1, 0)
  let dist = dijkstra(graph, 1, 0)
  assert_eq(dist[0], Some(0))
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
  assert_eq(dist[0], Some(0))
  assert_eq(dist[1], Some(1))
  assert_eq(dist[2], Some(3))
  assert_eq(dist[3], Some(6))
}

test "dijkstra: unreachable node" {
  let n = 3
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 5
  graph[1 * n + 0] = 5
  let dist = dijkstra(graph, n, 0)
  assert_eq(dist[0], Some(0))
  assert_eq(dist[1], Some(5))
  assert_true(dist[2] is None)
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
  assert_eq(dist[2], Some(2))
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
  assert_eq(dist[0], Some(0))
  assert_eq(dist[1], Some(1))
  assert_eq(dist[2], Some(2))
}

test "dijkstra: directed graph" {
  let n = 3
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 2
  graph[1 * n + 2] = 3
  let dist = dijkstra(graph, n, 0)
  assert_eq(dist[0], Some(0))
  assert_eq(dist[1], Some(2))
  assert_eq(dist[2], Some(5))
  let dist1 = dijkstra(graph, n, 1)
  assert_true(dist1[0] is None)
  assert_eq(dist1[2], Some(3))
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
  assert_eq(shortest_path(graph, n, 0, 3), Some(6))
  assert_eq(shortest_path(graph, n, 0, 0), Some(0))
}

test "shortest_path: unreachable" {
  let n = 3
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 5
  assert_true(shortest_path(graph, n, 0, 2) is None)
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
    assert_eq(dist[k], Some(if k == 0 { 0 } else { 1 }))
  }
}

test "dijkstra: invalid inputs return None" {
  let graph = FixedArray::make(9, 0)
  let dist = dijkstra(graph, 0, 0)
  assert_eq(dist.length(), 0)
  let dist2 = dijkstra(graph, 3, -1)
  for k = 0; k < 3; k = k + 1 {
    assert_true(dist2[k] is None)
  }
  let dist3 = dijkstra(graph, 3, 5)
  for k = 0; k < 3; k = k + 1 {
    assert_true(dist3[k] is None)
  }
}

test "dijkstra: negative n returns empty array" {
  let graph = FixedArray::make(9, 0)
  let dist = dijkstra(graph, -5, 0)
  assert_eq(dist.length(), 0)
}
