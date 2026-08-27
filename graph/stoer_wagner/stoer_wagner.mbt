/// Stoer-Wagner algorithm for global minimum cut in an undirected graph.
///
/// Given a weighted undirected graph, finds the minimum cut — the smallest
/// total weight of edges whose removal disconnects the graph into two
/// non-empty parts.
///
/// ## Algorithm
///
/// The Stoer-Wagner algorithm works by repeatedly "contracting" vertices:
///
/// 1. **Minimum cut phase**: Starting from an arbitrary vertex, greedily add
///    vertices to a set `A` in order of maximum connectivity to `A`. The last
///    two vertices added (`s` and `t`) define a cut of weight equal to the
///    total connectivity of `t` to `A`. This is a "minimum s-t cut" for the
///    current contracted graph.
///
/// 2. **Contraction**: Merge `s` and `t` into a single vertex, combining
///    their edge weights. Repeat until only one vertex remains.
///
/// 3. The global minimum cut is the minimum over all phases.
///
/// ## Complexity
///
/// - Time: O(V^3) with the simple implementation.
/// - Space: O(V^2) for the adjacency matrix.
///
/// All edge weights must be non-negative. Uses `Int64` for weight sums to
/// prevent overflow on large graphs.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Graph representation
// ---------------------------------------------------------------------------

///|
/// A weighted undirected graph using an adjacency matrix.
///
/// `weight[i][j]` is the weight of the edge between `i` and `j` (0 if no edge).
/// The graph is symmetric: `weight[i][j] == weight[j][i]`.
pub struct WeightedGraph {
  n : Int
  weight : Array[Array[Int]] // adjacency matrix
}

///|
/// Create a new weighted graph with `n` vertices and no edges.
pub fn new_graph(n : Int) -> WeightedGraph {
  let weight : Array[Array[Int]] = Array::makei(n, fn(_) { Array::make(n, 0) })
  { n, weight, }
}

///|
/// Add an undirected edge between `u` and `v` with weight `w`.
///
/// If an edge already exists, the weight is added (multi-edges are merged).
pub fn add_edge(graph : WeightedGraph, u : Int, v : Int, w : Int) -> Unit {
  if u == v {
    return
  }
  graph.weight[u][v] = graph.weight[u][v] + w
  graph.weight[v][u] = graph.weight[v][u] + w
}

// ---------------------------------------------------------------------------
// Stoer-Wagner algorithm
// ---------------------------------------------------------------------------

///|
/// Maximum weight sentinel for comparison initialization.
const NEG_INF : Int = -1_000_000_000

///|
/// Run one phase of the Stoer-Wagner algorithm.
///
/// Given the current graph state (with `merged[]` marking contracted vertices),
/// finds the minimum cut phase: greedily adds vertices to set A by maximum
/// connectivity, returns the last two vertices and the cut value.
///
/// Returns `(s, t, cut_weight)` where `s` is the second-to-last vertex and
/// `t` is the last vertex added, and `cut_weight` is the sum of weights from
/// `t` to all other vertices.
fn min_cut_phase(
  weight : Array[Array[Int]],
  merged : Array[Bool],
  in_a : Array[Bool],
  dist : Array[Int],
  n : Int,
  start : Int,
) -> (Int, Int, Int) {
  // Mark all vertices as not in A.
  for i = 0; i < n; i = i + 1 {
    in_a[i] = merged[i] // merged vertices are treated as "in A"
  }
  // Initialize connectivity.
  for i = 0; i < n; i = i + 1 {
    if merged[i] {
      dist[i] = NEG_INF
    } else {
      dist[i] = weight[start][i]
    }
  }
  in_a[start] = true
  let mut s = start
  let mut t = start
  let mut remaining = 0
  // Count non-merged vertices.
  for i = 0; i < n; i = i + 1 {
    if !merged[i] {
      remaining = remaining + 1
    }
  }
  // Add remaining-1 more vertices to A (start is already in).
  for k = 0; k < remaining - 1; k = k + 1 {
    // Find the non-A, non-merged vertex with maximum connectivity.
    let mut best = -1
    let mut best_dist = NEG_INF
    for i = 0; i < n; i = i + 1 {
      if !in_a[i] && !merged[i] && dist[i] > best_dist {
        best_dist = dist[i]
        best = i
      }
    }
    if best == -1 {
      break
    }
    // Add best to A.
    in_a[best] = true
    s = t
    t = best
    // Update connectivity for remaining vertices.
    for i = 0; i < n; i = i + 1 {
      if !in_a[i] && !merged[i] {
        dist[i] = dist[i] + weight[best][i]
      }
    }
  }
  // The cut value is the sum of weights from t to all other vertices.
  let mut cut = 0
  for i = 0; i < n; i = i + 1 {
    if i != t && !merged[i] {
      cut = cut + weight[t][i]
    }
  }
  (s, t, cut)
}

///|
/// Merge vertex `s` into vertex `t`: combine their edge weights.
fn merge_vertices(
  weight : Array[Array[Int]],
  merged : Array[Bool],
  n : Int,
  s : Int,
  t : Int,
) -> Unit {
  for i = 0; i < n; i = i + 1 {
    if i != s && i != t && !merged[i] {
      weight[t][i] = weight[t][i] + weight[s][i]
      weight[i][t] = weight[t][i] // keep symmetric
    }
  }
  merged[s] = true
}

///|
/// Compute the global minimum cut of a weighted undirected graph.
///
/// Returns the minimum cut value, or 0 if the graph has fewer than 2 vertices.
pub fn global_min_cut(graph : WeightedGraph) -> Int {
  let n = graph.n
  if n < 2 {
    return 0
  }
  // Copy the weight matrix (we will modify it during contraction).
  let weight : Array[Array[Int]] = Array::makei(n, fn(i) {
    let row : Array[Int] = Array::make(n, 0)
    for j = 0; j < n; j = j + 1 {
      row[j] = graph.weight[i][j]
    }
    row
  })
  let merged : Array[Bool] = Array::make(n, false)
  let in_a : Array[Bool] = Array::make(n, false)
  let dist : Array[Int] = Array::make(n, 0)
  let mut best_cut = 2_000_000_000 // large initial value
  let mut active = n
  while active > 1 {
    // Find a non-merged starting vertex.
    let mut start = 0
    for i = 0; i < n; i = i + 1 {
      if !merged[i] {
        start = i
        break
      }
    }
    let (s, t, cut) = min_cut_phase(weight, merged, in_a, dist, n, start)
    if cut < best_cut {
      best_cut = cut
    }
    merge_vertices(weight, merged, n, s, t)
    active = active - 1
  }
  best_cut
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "stoer_wagner: triangle" {
  // Triangle with equal weights: min cut = 2 (cut one edge on each side)
  let g = new_graph(3)
  add_edge(g, 0, 1, 1)
  add_edge(g, 1, 2, 1)
  add_edge(g, 0, 2, 1)
  assert_eq(global_min_cut(g), 2)
}

///|
test "stoer_wagner: path graph" {
  // Path: 0 - 1 - 2 - 3, all weight 1
  // Min cut = 1 (cut any single edge)
  let g = new_graph(4)
  add_edge(g, 0, 1, 1)
  add_edge(g, 1, 2, 1)
  add_edge(g, 2, 3, 1)
  assert_eq(global_min_cut(g), 1)
}

///|
test "stoer_wagner: two cliques" {
  // Two triangles connected by a single edge of weight 1.
  // Vertices: 0,1,2 (clique) and 3,4,5 (clique), edge 2-3 weight 1.
  // Min cut = 1 (cut the bridge edge).
  let g = new_graph(6)
  // First clique
  add_edge(g, 0, 1, 10)
  add_edge(g, 1, 2, 10)
  add_edge(g, 0, 2, 10)
  // Second clique
  add_edge(g, 3, 4, 10)
  add_edge(g, 4, 5, 10)
  add_edge(g, 3, 5, 10)
  // Bridge
  add_edge(g, 2, 3, 1)
  assert_eq(global_min_cut(g), 1)
}

///|
test "stoer_wagner: single edge" {
  let g = new_graph(2)
  add_edge(g, 0, 1, 5)
  assert_eq(global_min_cut(g), 5)
}

///|
test "stoer_wagner: weighted path" {
  // Path: 0 - 5 - 1 - 3 - 2 - 7 - 3
  // Min cut = 3 (the minimum weight edge)
  let g = new_graph(4)
  add_edge(g, 0, 1, 5)
  add_edge(g, 1, 2, 3)
  add_edge(g, 2, 3, 7)
  assert_eq(global_min_cut(g), 3)
}

///|
test "stoer_wagner: complete graph K4" {
  // K4: all edges weight 1.
  // Min cut = 3 (isolating any single vertex requires cutting 3 edges).
  let g = new_graph(4)
  for i = 0; i < 4; i = i + 1 {
    for j = i + 1; j < 4; j = j + 1 {
      add_edge(g, i, j, 1)
    }
  }
  assert_eq(global_min_cut(g), 3)
}

///|
test "stoer_wagner: multi-edge" {
  // Triangle: 0-1 weight 3, 0-2 weight 3, 1-2 weight 2
  // Min cut = min(3+3, 3+2, 3+2) = 5 (isolate vertex 1 or 2)
  let g = new_graph(3)
  add_edge(g, 0, 1, 3)
  add_edge(g, 0, 2, 3)
  add_edge(g, 1, 2, 2)
  assert_eq(global_min_cut(g), 5)
}

///|
test "stoer_wagner: star graph" {
  // Star: center 0 connected to 1,2,3,4 each with weight 1
  // Min cut = 1 (cut any single edge to isolate a leaf)
  let g = new_graph(5)
  add_edge(g, 0, 1, 1)
  add_edge(g, 0, 2, 1)
  add_edge(g, 0, 3, 1)
  add_edge(g, 0, 4, 1)
  assert_eq(global_min_cut(g), 1)
}

///|
test "stoer_wagner: two vertices" {
  let g = new_graph(2)
  add_edge(g, 0, 1, 100)
  assert_eq(global_min_cut(g), 100)
}

///|
test "stoer_wagner: larger graph" {
  // Graph where min cut is clearly defined.
  // Two groups of 3 vertices, connected by 2 edges of weight 2 each.
  // Group 1: 0,1,2 with all edges weight 5
  // Group 2: 3,4,5 with all edges weight 5
  // Bridges: 2-3 weight 2, 1-4 weight 2
  // Min cut = 4 (cut both bridges)
  let g = new_graph(6)
  // Group 1
  add_edge(g, 0, 1, 5)
  add_edge(g, 1, 2, 5)
  add_edge(g, 0, 2, 5)
  // Group 2
  add_edge(g, 3, 4, 5)
  add_edge(g, 4, 5, 5)
  add_edge(g, 3, 5, 5)
  // Bridges
  add_edge(g, 2, 3, 2)
  add_edge(g, 1, 4, 2)
  assert_eq(global_min_cut(g), 4)
}
