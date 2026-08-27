/// Borůvka's Minimum Spanning Tree algorithm.
///
/// Borůvka's algorithm builds a minimum spanning forest by repeatedly finding,
/// for every connected component simultaneously, the cheapest outgoing edge and
/// adding it to the MST. This "parallel" flavour makes it the algorithm of
/// choice for distributed MST computation and is the historical ancestor of
/// modern filtering heuristics (e.g. filtered Kruskal).
///
/// # Algorithm
///
/// 1. Start with each vertex in its own component (Union-Find).
/// 2. In each of at most ⌈log₂ V⌉ rounds:
///    a. For every component, scan all edges incident to its vertices and
///       record the cheapest edge that crosses to a *different* component.
///    b. Add all cheapest-crossing edges to the MST and union their endpoints.
/// 3. Repeat until no component has an outgoing edge (the forest is complete).
///
/// Each round halves the number of components in the worst case (at least one
/// edge merges two components, and every component picks at least one), giving
/// O(log V) rounds. Each round scans all E edges, so the total is O(E log V).
///
/// # Comparison with Kruskal / Prim
///
/// - Kruskal sorts all edges: O(E log E), best when E is small.
/// - Prim with a binary heap: O(E log V), best for dense graphs.
/// - Borůvka: O(E log V), best when edge scanning can be parallelised across
///   components — each round's "cheapest outgoing edge" search is independent
///   per component.
///
/// # Overflow
///
/// `total_weight` is accumulated as `Int64` to prevent overflow. Individual
/// edge weights remain `Int`.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

// ---------------------------------------------------------------------------
// Edge type — shared with kruskal but re-declared for package independence.
// ---------------------------------------------------------------------------

///|
/// A weighted undirected edge between vertex `from` and vertex `to`.
pub struct Edge {
  from : Int
  to : Int
  weight : Int
}

///|
/// Construct an [`Edge`].
pub fn edge(from : Int, to : Int, weight : Int) -> Edge {
  { from, to, weight, }
}

// ---------------------------------------------------------------------------
// Borůvka MST
// ---------------------------------------------------------------------------

///|
/// Compute the Minimum Spanning Tree (forest) of an undirected graph using
/// Borůvka's algorithm.
///
/// # Parameters
/// - `edges`: the weighted undirected edges of the graph. Self-loops (from==to)
///   are silently skipped. The input array is not modified.
/// - `n`: the number of vertices, indexed `0 .. n - 1`. Edges whose endpoints
///   fall outside this range are silently ignored.
///
/// # Returns
/// `(mst_edges, total_weight)` where `mst_edges` are the selected edges and
/// `total_weight` is their summed weight as `Int64`. For a connected graph the
/// result has exactly `n - 1` edges; for a disconnected graph it is a spanning
/// forest. Returns an empty array and weight `0L` when `n <= 0` or there are no
/// edges.
pub fn boruvka_mst(
  edges : FixedArray[Edge],
  n : Int,
) -> (FixedArray[Edge], Int64) {
  if n <= 0 || edges.length() == 0 {
    return (FixedArray::make(0, edge(0, 0, 0)), 0L)
  }
  let uf = @union_find.new(n)
  let num_edges = edges.length()
  // Pre-filter: keep only edges with valid, distinct endpoints.
  // This avoids repeated range checks in the hot loop.
  let valid_edges : Array[Edge] = []
  for i = 0; i < num_edges; i = i + 1 {
    let e = edges[i]
    if e.from >= 0 && e.from < n && e.to >= 0 && e.to < n && e.from != e.to {
      valid_edges.push(e)
    }
  }
  let m = valid_edges.length()
  if m == 0 {
    return (FixedArray::make(0, edge(0, 0, 0)), 0L)
  }
  // MST edges buffer — at most n-1 edges.
  let mst_edges : Array[Edge] = []
  let mut total : Int64 = 0L
  // For each round: find the cheapest outgoing edge for every component.
  // cheapest_comp[i] = index into valid_edges of cheapest outgoing edge for
  // the component whose root is i (only valid for actual roots).
  let cheapest_comp : FixedArray[Int] = FixedArray::make(n, -1)
  let num_components = @union_find.count(uf)
  let mut active_components = num_components
  // Each round at least halves the components, so at most ceil(log2(n)) rounds.
  // Guard with an explicit iteration bound to be safe.
  while active_components > 1 {
    // Reset cheapest for this round.
    for i = 0; i < n; i = i + 1 {
      cheapest_comp[i] = -1
    }
    // Scan all valid edges to find cheapest outgoing edge per component.
    for i = 0; i < m; i = i + 1 {
      let e = valid_edges[i]
      let root_u = match @union_find.find(uf, e.from) {
        Some(r) => r
        None => continue
      }
      let root_v = match @union_find.find(uf, e.to) {
        Some(r) => r
        None => continue
      }
      if root_u == root_v {
        continue // internal edge, skip
      }
      // Update cheapest for root_u's component (if this edge is cheaper).
      let cur_u = cheapest_comp[root_u]
      if cur_u == -1 || e.weight < valid_edges[cur_u].weight {
        cheapest_comp[root_u] = i
      }
      // Update cheapest for root_v's component.
      let cur_v = cheapest_comp[root_v]
      if cur_v == -1 || e.weight < valid_edges[cur_v].weight {
        cheapest_comp[root_v] = i
      }
    }
    // Collect the cheapest edges found (deduplicate by edge index).
    let mut any_added = false
    for i = 0; i < n; i = i + 1 {
      let ei = cheapest_comp[i]
      if ei == -1 {
        continue
      }
      // Verify the edge still crosses components (may have been merged by a
      // parallel edge in this round).
      let e = valid_edges[ei]
      let root_u = match @union_find.find(uf, e.from) {
        Some(r) => r
        None => continue
      }
      let root_v = match @union_find.find(uf, e.to) {
        Some(r) => r
        None => continue
      }
      if root_u == root_v {
        continue // already merged via another edge this round
      }
      // Add to MST.
      mst_edges.push(e)
      total = total + e.weight.to_int64()
      ignore(@union_find.union(uf, e.from, e.to))
      any_added = true
    }
    if !any_added {
      break // no progress — remaining components are disconnected
    }
    active_components = @union_find.count(uf)
  }
  // Convert to FixedArray.
  let result = FixedArray::makei(mst_edges.length(), fn(i) { mst_edges[i] })
  (result, total)
}

///|
/// Convenience wrapper around [`boruvka_mst`] that returns only the total
/// weight of the minimum spanning forest.
pub fn mst_weight(edges : FixedArray[Edge], n : Int) -> Int64 {
  let (_, w) = boruvka_mst(edges, n)
  w
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "boruvka: simple connected graph (triangle)" {
  // 0--1 (1)
  // |  /
  // 2      (1-2: 2, 0-2: 3)
  // MST = {0-1, 1-2}, weight 3.
  let edges = FixedArray::make(3, edge(0, 0, 0))
  edges[0] = edge(0, 1, 1)
  edges[1] = edge(1, 2, 2)
  edges[2] = edge(0, 2, 3)
  let (mst, w) = boruvka_mst(edges, 3)
  assert_eq(mst.length(), 2)
  assert_eq(w, 3L)
}

///|
test "boruvka: disconnected graph yields a forest" {
  // Two components: {0,1} and {2,3}. 4 nodes but only 2 MST edges.
  let edges = FixedArray::make(2, edge(0, 0, 0))
  edges[0] = edge(0, 1, 5)
  edges[1] = edge(2, 3, 10)
  let (mst, w) = boruvka_mst(edges, 4)
  assert_eq(mst.length(), 2)
  assert_eq(w, 15L)
}

///|
test "boruvka: single vertex" {
  let edges = FixedArray::make(0, edge(0, 0, 0))
  let (mst, w) = boruvka_mst(edges, 1)
  assert_eq(mst.length(), 0)
  assert_eq(w, 0L)
}

///|
test "boruvka: empty graph (n=0)" {
  let edges = FixedArray::make(0, edge(0, 0, 0))
  let (mst, w) = boruvka_mst(edges, 0)
  assert_eq(mst.length(), 0)
  assert_eq(w, 0L)
}

///|
test "boruvka: single edge" {
  let edges = FixedArray::make(1, edge(0, 0, 0))
  edges[0] = edge(0, 1, 7)
  let (mst, w) = boruvka_mst(edges, 2)
  assert_eq(mst.length(), 1)
  assert_eq(w, 7L)
}

///|
test "boruvka: self-loops ignored" {
  let edges = FixedArray::make(3, edge(0, 0, 0))
  edges[0] = edge(0, 0, 1) // self-loop, should be ignored
  edges[1] = edge(0, 1, 3)
  edges[2] = edge(1, 1, 2) // self-loop, should be ignored
  let (mst, w) = boruvka_mst(edges, 2)
  assert_eq(mst.length(), 1)
  assert_eq(w, 3L)
}

///|
test "boruvka: edges out of range ignored" {
  let edges = FixedArray::make(3, edge(0, 0, 0))
  edges[0] = edge(0, 1, 3)
  edges[1] = edge(0, 5, 1) // out of range
  edges[2] = edge(-1, 1, 2) // out of range
  let (mst, w) = boruvka_mst(edges, 2)
  assert_eq(mst.length(), 1)
  assert_eq(w, 3L)
}

///|
test "boruvka: complete graph K4" {
  // K4 with 4 vertices, 6 edges.
  // Vertices: 0, 1, 2, 3
  // Edge weights:
  //   0-1: 1, 0-2: 2, 0-3: 3
  //   1-2: 4, 1-3: 5, 2-3: 6
  // MST = {0-1, 0-2, 0-3}, weight = 1+2+3 = 6
  let edges = FixedArray::make(6, edge(0, 0, 0))
  edges[0] = edge(0, 1, 1)
  edges[1] = edge(0, 2, 2)
  edges[2] = edge(0, 3, 3)
  edges[3] = edge(1, 2, 4)
  edges[4] = edge(1, 3, 5)
  edges[5] = edge(2, 3, 6)
  let (mst, w) = boruvka_mst(edges, 4)
  assert_eq(mst.length(), 3) // n-1 edges
  assert_eq(w, 6L)
}

///|
test "boruvka: star graph" {
  // Star centered at 0: 0-1(1), 0-2(2), 0-3(3), 0-4(4)
  // MST = all edges, weight = 1+2+3+4 = 10
  let edges = FixedArray::make(4, edge(0, 0, 0))
  edges[0] = edge(0, 1, 1)
  edges[1] = edge(0, 2, 2)
  edges[2] = edge(0, 3, 3)
  edges[3] = edge(0, 4, 4)
  let (mst, w) = boruvka_mst(edges, 5)
  assert_eq(mst.length(), 4)
  assert_eq(w, 10L)
}

///|
test "boruvka: equal weight edges" {
  // All edges weight 1 — any spanning tree is optimal.
  // K4: 6 edges, all weight 1. MST has 3 edges, weight 3.
  let edges = FixedArray::make(6, edge(0, 0, 0))
  edges[0] = edge(0, 1, 1)
  edges[1] = edge(0, 2, 1)
  edges[2] = edge(0, 3, 1)
  edges[3] = edge(1, 2, 1)
  edges[4] = edge(1, 3, 1)
  edges[5] = edge(2, 3, 1)
  let (mst, w) = boruvka_mst(edges, 4)
  assert_eq(mst.length(), 3)
  assert_eq(w, 3L)
}

///|
test "boruvka: negative weight edges" {
  // Graph with negative edge weights.
  //   0-1: -5, 0-2: 1, 1-2: 3
  // MST = {0-1, 0-2}, weight = -5 + 1 = -4
  let edges = FixedArray::make(3, edge(0, 0, 0))
  edges[0] = edge(0, 1, -5)
  edges[1] = edge(0, 2, 1)
  edges[2] = edge(1, 2, 3)
  let (mst, w) = boruvka_mst(edges, 3)
  assert_eq(mst.length(), 2)
  assert_eq(w, -4L)
}

///|
test "boruvka: large graph 100 nodes" {
  // Build a path graph 0-1-2-...-99 with weight = vertex index.
  // Plus some cross edges to make it interesting.
  let edges : Array[Edge] = []
  for i = 0; i < 99; i = i + 1 {
    edges.push(edge(i, i + 1, i + 1))
  }
  // Add some cross edges (should not be in MST as they have higher weights).
  edges.push(edge(0, 50, 1000))
  edges.push(edge(10, 90, 2000))
  let edge_arr = FixedArray::makei(edges.length(), fn(i) { edges[i] })
  let (mst, w) = boruvka_mst(edge_arr, 100)
  assert_eq(mst.length(), 99) // n-1
  // Path MST weight = 1 + 2 + ... + 99 = 4950
  assert_eq(w, 4950L)
}

///|
test "boruvka: multiple components with cross edges" {
  // Component 1: {0, 1, 2}, Component 2: {3, 4, 5}
  // Within comp1: 0-1(1), 1-2(2), 0-2(10)
  // Within comp2: 3-4(1), 4-5(2), 3-5(10)
  // Cross: 2-3(100)
  // MST = {0-1, 1-2, 3-4, 4-5, 2-3}, weight = 1+2+1+2+100 = 106
  let edges = FixedArray::make(7, edge(0, 0, 0))
  edges[0] = edge(0, 1, 1)
  edges[1] = edge(1, 2, 2)
  edges[2] = edge(0, 2, 10)
  edges[3] = edge(3, 4, 1)
  edges[4] = edge(4, 5, 2)
  edges[5] = edge(3, 5, 10)
  edges[6] = edge(2, 3, 100)
  let (mst, w) = boruvka_mst(edges, 6)
  assert_eq(mst.length(), 5) // n-1 = 5
  assert_eq(w, 106L)
}

///|
test "boruvka: agrees with kruskal on random graph" {
  // Build a graph and verify Borůvka and Kruskal give the same MST weight.
  // Use a simple LCG for deterministic pseudo-random edge generation.
  let n = 20
  let edges : Array[Edge] = []
  let mut state = 42
  for i = 0; i < n; i = i + 1 {
    for j = i + 1; j < n; j = j + 1 {
      // LCG: generate weight in [1, 100]
      state = (state * 1103515245 + 12345) & 0x7FFFFFFF
      let w = state % 100 + 1
      edges.push(edge(i, j, w))
    }
  }
  let edge_arr = FixedArray::makei(edges.length(), fn(i) { edges[i] })
  let (boruvka_mst_edges, boruvka_w) = boruvka_mst(edge_arr, n)
  // Kruskal uses its own Edge type, so convert.
  let kruskal_edges = FixedArray::makei(edge_arr.length(), fn(i) {
    @kruskal.edge(edge_arr[i].from, edge_arr[i].to, edge_arr[i].weight)
  })
  let (_, kruskal_w) = @kruskal.kruskal_mst(kruskal_edges, n)
  // Both should select n-1 edges for a complete graph.
  assert_eq(boruvka_mst_edges.length(), n - 1)
  // Both should give the same total weight.
  assert_eq(boruvka_w, kruskal_w.to_int64())
}

///|
test "boruvka: duplicate edges (parallel edges)" {
  // Two edges between 0 and 1 with different weights.
  // Borůvka should pick the cheaper one.
  let edges = FixedArray::make(3, edge(0, 0, 0))
  edges[0] = edge(0, 1, 10)
  edges[1] = edge(0, 1, 3) // cheaper parallel edge
  edges[2] = edge(1, 2, 5)
  let (mst, w) = boruvka_mst(edges, 3)
  assert_eq(mst.length(), 2)
  assert_eq(w, 8L) // 3 + 5
}

///|
test "boruvka: mst_weight convenience function" {
  let edges = FixedArray::make(3, edge(0, 0, 0))
  edges[0] = edge(0, 1, 1)
  edges[1] = edge(1, 2, 2)
  edges[2] = edge(0, 2, 3)
  assert_eq(mst_weight(edges, 3), 3L)
}
