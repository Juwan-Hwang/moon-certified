///|
/// Suurballe's algorithm for finding two edge-disjoint shortest paths.
///
/// Given a directed graph with non-negative edge weights, Suurballe's
/// algorithm finds two paths from `src` to `dst` that share no edges and
/// have minimum total weight.  The algorithm works in three phases:
///
/// 1. **First Dijkstra**: Compute shortest distances `d(s, v)` from `src`
///    and reconstruct the shortest path `P1` from `src` to `dst`.
///
/// 2. **Graph transformation**: Modify edge weights to
///    `w'(u, v) = w(u, v) + d(s, u) - d(s, v)` (all non-negative), then
///    reverse edges on `P1` and negate their modified weights.  This
///    creates a residual graph where the second path can "undo" edges
///    used by `P1`.
///
/// 3. **Second Dijkstra**: Find shortest path `P2` in the residual graph.
///    Remove edges common to both `P1` and reversed-`P2` (they cancel),
///    yielding two edge-disjoint paths.
///
/// ## Complexity
///
/// O((V + E) log V) — two Dijkstra runs plus O(E) graph transformation.
///
/// ## References
///
/// - Suurballe, J. W. (1974): "Disjoint paths in a network." Networks 4(2).
/// - Bhandari, R. (1999): "Survivable Networks: Algorithms for Diverse
///   Routing." Springer.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.
const INF_I64 : Int64 = 9223372036854775807L

// ---------------------------------------------------------------------------
// Dijkstra with predecessor tracking
// ---------------------------------------------------------------------------

///|
/// Result of a Dijkstra run: distances and predecessors.
priv struct DijkstraResult {
  dist : FixedArray[Int64]
  prev : FixedArray[Int] // -1 = no predecessor (source or unreachable)
}

///|
/// Run Dijkstra from `src`, returning distances and predecessors.
///
/// `graph[i]` is an array of `(neighbor, weight)` pairs.
fn dijkstra_with_path(
  graph : Array[Array[(Int, Int)]],
  n : Int,
  src : Int,
) -> DijkstraResult {
  let dist = FixedArray::make(n, INF_I64)
  let prev = FixedArray::make(n, -1)
  let visited = FixedArray::make(n, false)
  dist[src] = 0L
  let heap = @graph_utils.MinHeap::new()
  @graph_utils.MinHeap::push(heap, 0L, src)
  while @graph_utils.MinHeap::len(heap) > 0 {
    match @graph_utils.MinHeap::pop(heap) {
      Some({ dist: d, vertex: u }) =>
        if !visited[u] {
          visited[u] = true
          for j = 0; j < graph[u].length(); j = j + 1 {
            let (v, w) = graph[u][j]
            if v >= 0 && v < n && !visited[v] {
              let nd = d + w.to_int64()
              if nd < dist[v] {
                dist[v] = nd
                prev[v] = u
                @graph_utils.MinHeap::push(heap, nd, v)
              }
            }
          }
        }
      None => break
    }
  }
  { dist, prev }
}

///|
/// Reconstruct the shortest path from `src` to `dst` using predecessors.
fn reconstruct_path(prev : FixedArray[Int], dst : Int) -> Array[Int]? {
  let path : Array[Int] = []
  let mut cur = dst
  let mut steps = 0
  let limit = prev.length() + 1
  while cur != -1 && steps < limit {
    path.push(cur)
    if prev[cur] == -1 {
      // cur is either src or unreachable
      break
    }
    cur = prev[cur]
    steps = steps + 1
  }
  if steps >= limit {
    return None // cycle detected (shouldn't happen)
  }
  // Reverse path to get src → dst order
  let reversed : Array[Int] = []
  for i = path.length() - 1; i >= 0; i = i - 1 {
    reversed.push(path[i])
  }
  Some(reversed)
}

// ---------------------------------------------------------------------------
// Suurballe's algorithm
// ---------------------------------------------------------------------------

///|
/// Result of Suurballe's algorithm: two edge-disjoint paths.
pub struct SuurballeResult {
  path1 : Array[Int]
  path2 : Array[Int]
  total_weight : Int
}

///|
/// Find two edge-disjoint paths from `src` to `dst` with minimum total weight.
///
/// `graph[i]` is an array of `(neighbor, weight)` pairs.  All weights must
/// be non-negative.  Returns `None` if `dst` is unreachable from `src` or
/// if no two edge-disjoint paths exist.
///
/// The returned paths share no directed edges.  `path1` and `path2` are
/// each arrays of vertex indices from `src` to `dst`.
pub fn suurballe(
  graph : Array[Array[(Int, Int)]],
  n : Int,
  src : Int,
  dst : Int,
) -> SuurballeResult? {
  if n <= 0 || src < 0 || src >= n || dst < 0 || dst >= n || src == dst {
    return None
  }
  // --- Phase 1: First Dijkstra ---
  let d1 = dijkstra_with_path(graph, n, src)
  if d1.dist[dst] == INF_I64 {
    return None // dst unreachable
  }
  let p1_opt = reconstruct_path(d1.prev, dst)
  let p1 = match p1_opt {
    Some(p) => p
    None => return None
  }
  // Verify p1 starts at src
  if p1[0] != src {
    return None
  }

  // --- Phase 2: Build residual graph ---
  // Modified weights: w'(u, v) = w(u, v) + d(s, u) - d(s, v)
  // All modified weights are non-negative (triangle inequality).
  // For edges on P1, reverse them and negate the modified weight.
  //
  // We represent the residual graph as an adjacency list where each edge
  // stores (neighbor, modified_weight).  Original edges keep their modified
  // weight; reversed P1 edges get the negated modified weight (which is
  // ≤ 0, but only appears for reversed edges).
  //
  // Since Dijkstra requires non-negative weights, we use the modified weights
  // for original edges (which are ≥ 0) and handle reversed P1 edges specially.
  //
  // Actually, the standard approach: the reversed edges have w' = -(original w'),
  // which can be negative.  But since all modified weights on P1 are 0
  // (because P1 is a shortest path, so w'(u,v) = 0 for edges on P1),
  // the reversed edges also have weight 0.  So all edges in the residual
  // graph have non-negative modified weights!
  //
  // This is the key insight: w'(u,v) = w(u,v) + d(s,u) - d(s,v) = 0 for
  // edges on the shortest path, so reversed edges have weight -0 = 0.

  // Build a set of edges on P1 for quick lookup
  // Key: (from_vertex, to_vertex) → true if on P1
  let p1_edges : Array[(Int, Int)] = []
  for i = 0; i < p1.length() - 1; i = i + 1 {
    p1_edges.push((p1[i], p1[i + 1]))
  }

  // Build residual graph
  // For each original edge (u, v, w):
  //   - If (u, v) is on P1: add reversed edge (v, u) with modified weight 0
  //   - Else: add edge (u, v) with modified weight w'(u, v) = w + d(s,u) - d(s,v)
  let residual : Array[Array[(Int, Int)]] = Array::makei(n, fn(_) { [] })
  for u = 0; u < n; u = u + 1 {
    if d1.dist[u] == INF_I64 {
      continue
    }
    for j = 0; j < graph[u].length(); j = j + 1 {
      let (v, w) = graph[u][j]
      if v < 0 || v >= n || d1.dist[v] == INF_I64 {
        continue
      }
      // Check if (u, v) is on P1
      let mut on_p1 = false
      for k = 0; k < p1_edges.length(); k = k + 1 {
        let (pu, pv) = p1_edges[k]
        if pu == u && pv == v {
          on_p1 = true
          break
        }
      }
      if on_p1 {
        // Reverse the edge: (v, u) with weight 0
        residual[v].push((u, 0))
      } else {
        // Keep original direction with modified weight
        let w_mod = w.to_int64() + d1.dist[u] - d1.dist[v]
        let w_mod_int = if w_mod < 0L { 0 } else { w_mod.to_int() }
        residual[u].push((v, w_mod_int))
      }
    }
  }

  // --- Phase 3: Second Dijkstra on residual graph ---
  let d2 = dijkstra_with_path(residual, n, src)
  if d2.dist[dst] == INF_I64 {
    return None // No second path exists
  }
  let p2_opt = reconstruct_path(d2.prev, dst)
  let p2 = match p2_opt {
    Some(p) => p
    None => return None
  }
  if p2[0] != src {
    return None
  }

  // --- Phase 4: Combine paths ---
  // P2 may use some reversed P1 edges.  When P2 uses a reversed edge (v, u)
  // that was originally (u, v) on P1, it means P1 and P2 share that edge
  // in opposite directions.  These cancel out.
  //
  // The standard combination:
  // 1. Build a multiset of directed edges from P1 and P2
  // 2. Remove pairs of (u,v) in P1 and (v,u) in P2 (cancellations)
  // 3. The remaining edges form two edge-disjoint paths

  // Collect edges from P1 and P2
  let p1_edge_list : Array[(Int, Int)] = []
  for i = 0; i < p1.length() - 1; i = i + 1 {
    p1_edge_list.push((p1[i], p1[i + 1]))
  }
  let p2_edge_list : Array[(Int, Int)] = []
  for i = 0; i < p2.length() - 1; i = i + 1 {
    p2_edge_list.push((p2[i], p2[i + 1]))
  }

  // Cancel common edges (opposite directions)
  let p1_remaining : Array[(Int, Int)] = []
  let p2_cancelled : Array[Bool] = Array::make(p2_edge_list.length(), false)
  for i = 0; i < p1_edge_list.length(); i = i + 1 {
    let (u, v) = p1_edge_list[i]
    let mut cancelled = false
    for j = 0; j < p2_edge_list.length(); j = j + 1 {
      if !p2_cancelled[j] {
        let (u2, v2) = p2_edge_list[j]
        if u2 == v && v2 == u {
          // Cancel: P1 has (u,v), P2 has (v,u)
          p2_cancelled[j] = true
          cancelled = true
          break
        }
      }
    }
    if !cancelled {
      p1_remaining.push((u, v))
    }
  }

  // Collect remaining P2 edges
  let p2_remaining : Array[(Int, Int)] = []
  for j = 0; j < p2_edge_list.length(); j = j + 1 {
    if !p2_cancelled[j] {
      p2_remaining.push(p2_edge_list[j])
    }
  }

  // Build adjacency from remaining edges and extract two paths
  // The remaining edges form a graph where each vertex (except src, dst)
  // has in-degree = out-degree.  src has out-degree 2, dst has in-degree 2.
  // We can trace two paths from src to dst.
  let all_edges : Array[(Int, Int)] = []
  for i = 0; i < p1_remaining.length(); i = i + 1 {
    all_edges.push(p1_remaining[i])
  }
  for i = 0; i < p2_remaining.length(); i = i + 1 {
    all_edges.push(p2_remaining[i])
  }

  // Build adjacency list from remaining edges with consumption pointers.
  let adj : Array[Array[Int]] = Array::makei(n, fn(_) { [] })
  for i = 0; i < all_edges.length(); i = i + 1 {
    let (u, v) = all_edges[i]
    adj[u].push(v)
  }
  // Index pointer per vertex: next unconsumed edge.
  let edge_ptr = Array::make(n, 0)

  // Trace two paths from src to dst
  let path1 = trace_path(adj, edge_ptr, n, src, dst)
  let path2 = trace_path(adj, edge_ptr, n, src, dst)

  if path1.length() == 0 || path2.length() == 0 {
    return None
  }

  // Compute total weight using original graph weights
  let weight_map : Array[Array[(Int, Int)]] = graph
  let mut total = 0
  for p_idx = 0; p_idx < 2; p_idx = p_idx + 1 {
    let path = if p_idx == 0 { path1 } else { path2 }
    for i = 0; i < path.length() - 1; i = i + 1 {
      let u = path[i]
      let v = path[i + 1]
      let mut found = false
      for j = 0; j < weight_map[u].length(); j = j + 1 {
        let (nv, w) = weight_map[u][j]
        if nv == v {
          total = total + w
          found = true
          break
        }
      }
      if !found {
        // Edge not found in original graph (shouldn't happen for valid paths)
        return None
      }
    }
  }

  Some({ path1, path2, total_weight: total })
}

///|
/// Trace a path from src to dst using edges from the adjacency list,
/// consuming each edge via an index pointer (no O(n) removal).
fn trace_path(
  adj : Array[Array[Int]],
  edge_ptr : Array[Int],
  n : Int,
  src : Int,
  dst : Int,
) -> Array[Int] {
  let path : Array[Int] = []
  let mut cur = src
  let mut steps = 0
  while cur != dst && steps < n * 2 {
    path.push(cur)
    if edge_ptr[cur] >= adj[cur].length() {
      // Dead end — no more unconsumed edges from this vertex
      break
    }
    let next = adj[cur][edge_ptr[cur]]
    edge_ptr[cur] = edge_ptr[cur] + 1
    cur = next
    steps = steps + 1
  }
  if cur == dst {
    path.push(dst)
  } else {
    // Failed to reach dst
    path.clear()
  }
  path
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "suurballe: two edge-disjoint paths in diamond graph" {
  // Graph: 0 → 1 → 3, 0 → 2 → 3, plus 0 → 3 direct
  //        Two disjoint paths: 0→1→3 and 0→2→3
  let n = 4
  let graph : Array[Array[(Int, Int)]] = [[], [], [], []]
  graph[0].push((1, 1))
  graph[0].push((2, 1))
  graph[0].push((3, 10))
  graph[1].push((3, 1))
  graph[2].push((3, 1))
  let result = suurballe(graph, n, 0, 3)
  assert_true(result is Some(_))
  match result {
    Some(r) => {
      assert_eq(r.path1.length(), 3) // 0 → ? → 3
      assert_eq(r.path2.length(), 3) // 0 → ? → 3
      assert_eq(r.path1[0], 0)
      assert_eq(r.path2[0], 0)
      assert_eq(r.path1[r.path1.length() - 1], 3)
      assert_eq(r.path2[r.path2.length() - 1], 3)
      assert_eq(r.total_weight, 4) // 1+1 + 1+1 = 4
      // Paths should use different intermediate vertices
      assert_true(r.path1[1] != r.path2[1])
    }
    None => assert_true(false)
  }
}

///|
test "suurballe: no two disjoint paths" {
  // Graph: 0 → 1 → 2 (only one path, no alternative)
  let n = 3
  let graph : Array[Array[(Int, Int)]] = [[], [], []]
  graph[0].push((1, 1))
  graph[1].push((2, 1))
  let result = suurballe(graph, n, 0, 2)
  assert_true(result is None)
}

///|
test "suurballe: paths share no edges" {
  // Graph with multiple paths
  let n = 5
  let graph : Array[Array[(Int, Int)]] = [[], [], [], [], []]
  graph[0].push((1, 2))
  graph[0].push((2, 3))
  graph[1].push((3, 2))
  graph[2].push((3, 2))
  graph[3].push((4, 1))
  graph[1].push((4, 10))
  graph[2].push((4, 10))
  let result = suurballe(graph, n, 0, 4)
  assert_true(result is Some(_))
  match result {
    Some(r) => {
      // Verify edge disjointness
      let edges1 : Array[(Int, Int)] = []
      for i = 0; i < r.path1.length() - 1; i = i + 1 {
        edges1.push((r.path1[i], r.path1[i + 1]))
      }
      for i = 0; i < r.path2.length() - 1; i = i + 1 {
        let e = (r.path2[i], r.path2[i + 1])
        for j = 0; j < edges1.length(); j = j + 1 {
          assert_true(edges1[j] != e)
        }
      }
    }
    None => assert_true(false)
  }
}

///|
test "suurballe: same source and destination" {
  let n = 3
  let graph : Array[Array[(Int, Int)]] = [[], [], []]
  graph[0].push((1, 1))
  graph[1].push((2, 1))
  let result = suurballe(graph, n, 0, 0)
  assert_true(result is None)
}

///|
test "suurballe: unreachable destination" {
  let n = 3
  let graph : Array[Array[(Int, Int)]] = [[], [], []]
  graph[0].push((1, 1))
  // Vertex 2 is isolated
  let result = suurballe(graph, n, 0, 2)
  assert_true(result is None)
}

///|
test "suurballe: minimum total weight" {
  // Graph where greedy would pick a bad second path
  // 0 → 1 (w=1), 0 → 2 (w=1)
  // 1 → 3 (w=1), 2 → 3 (w=1)
  // 1 → 2 (w=1) [shortcut]
  // Optimal: 0→1→3 (w=2) and 0→2→3 (w=2), total=4
  let n = 4
  let graph : Array[Array[(Int, Int)]] = [[], [], [], []]
  graph[0].push((1, 1))
  graph[0].push((2, 1))
  graph[1].push((3, 1))
  graph[2].push((3, 1))
  graph[1].push((2, 1))
  let result = suurballe(graph, n, 0, 3)
  assert_true(result is Some(_))
  match result {
    Some(r) => assert_eq(r.total_weight, 4)
    None => assert_true(false)
  }
}

///|
test "suurballe: larger graph with detour" {
  // 0 → 1 → 2 → 3 → 4 (main path)
  // 0 → 5 → 4 (alternative)
  // 1 → 5, 5 → 2 (cross edges)
  let n = 6
  let graph : Array[Array[(Int, Int)]] = [[], [], [], [], [], []]
  graph[0].push((1, 1))
  graph[0].push((5, 3))
  graph[1].push((2, 1))
  graph[1].push((5, 1))
  graph[2].push((3, 1))
  graph[5].push((2, 1))
  graph[5].push((4, 2))
  graph[3].push((4, 1))
  let result = suurballe(graph, n, 0, 4)
  assert_true(result is Some(_))
  match result {
    Some(r) => {
      // Both paths should reach from 0 to 4
      assert_eq(r.path1[0], 0)
      assert_eq(r.path1[r.path1.length() - 1], 4)
      assert_eq(r.path2[0], 0)
      assert_eq(r.path2[r.path2.length() - 1], 4)
      // Verify edge disjointness
      let edges1 : Array[(Int, Int)] = []
      for i = 0; i < r.path1.length() - 1; i = i + 1 {
        edges1.push((r.path1[i], r.path1[i + 1]))
      }
      for i = 0; i < r.path2.length() - 1; i = i + 1 {
        let e = (r.path2[i], r.path2[i + 1])
        for j = 0; j < edges1.length(); j = j + 1 {
          assert_true(edges1[j] != e)
        }
      }
    }
    None => assert_true(false)
  }
}

///|
test "suurballe: equal weight parallel paths" {
  // Two completely separate paths with equal weight
  // Path 1: 0→1→2→4 (w=5+5+5=15), Path 2: 0→3→4 (w=5+5=10)
  // Total = 25
  let n = 5
  let graph : Array[Array[(Int, Int)]] = [[], [], [], [], []]
  graph[0].push((1, 5))
  graph[0].push((3, 5))
  graph[1].push((2, 5))
  graph[2].push((4, 5))
  graph[3].push((4, 5))
  let result = suurballe(graph, n, 0, 4)
  assert_true(result is Some(_))
  match result {
    Some(r) => {
      assert_eq(r.total_weight, 25) // 5+5+5 + 5+5 = 25
      // Verify edge disjointness
      let edges1 : Array[(Int, Int)] = []
      for i = 0; i < r.path1.length() - 1; i = i + 1 {
        edges1.push((r.path1[i], r.path1[i + 1]))
      }
      for i = 0; i < r.path2.length() - 1; i = i + 1 {
        let e = (r.path2[i], r.path2[i + 1])
        for j = 0; j < edges1.length(); j = j + 1 {
          assert_true(edges1[j] != e)
        }
      }
    }
    None => assert_true(false)
  }
}

///|
test "suurballe: invalid parameters" {
  let graph : Array[Array[(Int, Int)]] = [[], []]
  graph[0].push((1, 1))
  assert_true(suurballe(graph, 2, -1, 1) is None)
  assert_true(suurballe(graph, 2, 0, -1) is None)
  assert_true(suurballe(graph, 0, 0, 1) is None)
}

///|
test "suurballe: single edge bottleneck" {
  // 0 → 1 → 2, 0 → 1 is the only way to leave 0
  // Can't have two edge-disjoint paths
  let n = 3
  let graph : Array[Array[(Int, Int)]] = [[], [], []]
  graph[0].push((1, 1))
  graph[1].push((2, 1))
  graph[1].push((2, 2)) // parallel edge (different weight)
  let result = suurballe(graph, n, 0, 2)
  // Only one edge from 0 to 1, so no two edge-disjoint paths
  assert_true(result is None)
}

///|
test "suurballe: cycle graph" {
  // 0 → 1 → 2 → 0 (cycle)
  // Two disjoint paths from 0 to 2: 0→1→2 and 0→2 (direct)
  let n = 3
  let graph : Array[Array[(Int, Int)]] = [[], [], []]
  graph[0].push((1, 1))
  graph[0].push((2, 5))
  graph[1].push((2, 1))
  graph[2].push((0, 1))
  let result = suurballe(graph, n, 0, 2)
  assert_true(result is Some(_))
  match result {
    Some(r) => assert_eq(r.total_weight, 7) // 1+1 + 5 = 7
    None => assert_true(false)
  }
}
