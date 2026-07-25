/// Maximum clique finding using the Bron-Kerbosch algorithm with pivoting.
///
/// A **clique** is a subset of vertices in an undirected graph such that every
/// two distinct vertices are adjacent (i.e., a complete subgraph). A
/// **maximum clique** is a clique of the largest possible size.
///
/// Finding the maximum clique is NP-hard, but the Bron-Kerbosch algorithm
/// with pivoting efficiently enumerates all maximal cliques in practice.
///
/// ## Algorithm
///
/// The Bron-Kerbosch algorithm is a backtracking search:
///
/// ```
/// BronKerbosch(R, P, X):
///   if P and X are both empty: report R as a maximal clique
///   choose a pivot u from P ∪ X
///   for each v in P \ N(u):
///     BronKerbosch(R ∪ {v}, P ∩ N(v), X ∩ N(v))
///     P := P \ {v}
///     X := X ∪ {v}
/// ```
///
/// The **pivot** heuristic reduces the number of recursive calls by skipping
/// vertices that are neighbors of the pivot (they will be found in deeper
/// recursive calls).
///
/// ## Complexity
///
/// - Worst case: O(3^(V/3)) — but much faster in practice with pivoting.
/// - Space: O(V^2) for the adjacency matrix.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Graph representation
// ---------------------------------------------------------------------------

/// An undirected graph using a bit-set adjacency matrix.
///
/// `adj[i]` is a bit-set where bit `j` is set iff there is an edge between
/// `i` and `j`. Uses `Int` bitmasks, supporting up to 60 vertices.
pub struct Graph {
  n : Int
  adj : Array[Int] // bit-set adjacency: adj[i] has bit j set iff edge (i, j)
}

/// Create a new empty graph with `n` vertices.
///
/// `n` must be at most 60 (limited by Int bit-width).
pub fn new_graph(n : Int) -> Graph {
  { n, adj: Array::make(n, 0) }
}

/// Add an undirected edge between `u` and `v`.
pub fn add_edge(graph : Graph, u : Int, v : Int) -> Unit {
  if u == v {
    return
  }
  graph.adj[u] = graph.adj[u] | (1 << v)
  graph.adj[v] = graph.adj[v] | (1 << u)
}

/// Check if there is an edge between `u` and `v`.
pub fn has_edge(graph : Graph, u : Int, v : Int) -> Bool {
  (graph.adj[u] & (1 << v)) != 0
}

// ---------------------------------------------------------------------------
// Bron-Kerbosch with pivoting
// ---------------------------------------------------------------------------

/// Mutable state for the Bron-Kerbosch search.
priv struct SearchState {
  adj : Array[Int]
  mut best_size : Int
  best_clique : Array[Int]
  current : Array[Int]
}

/// Count the number of set bits in an Int (population count).
fn popcount(x : Int) -> Int {
  let mut count = 0
  let mut v = x
  while v != 0 {
    count = count + (v & 1)
    v = v >> 1
  }
  count
}

/// Find the lowest set bit position, or -1 if none.
fn lowest_bit(x : Int) -> Int {
  if x == 0 {
    return -1
  }
  let mut pos = 0
  let mut v = x
  while (v & 1) == 0 {
    v = v >> 1
    pos = pos + 1
  }
  pos
}

/// Bron-Kerbosch recursive search with pivoting.
///
/// Parameters:
/// - `r`: current clique (bit-set of vertices in the clique)
/// - `p`: candidate vertices (bit-set)
/// - `x`: excluded vertices (bit-set)
fn bron_kerbosch(
  state : SearchState,
  r_size : Int,
  p : Int,
  x : Int,
) -> Unit {
  // If P and X are both empty, R is a maximal clique.
  if p == 0 && x == 0 {
    if r_size > state.best_size {
      state.best_size = r_size
      // Save the clique.
      state.best_clique.clear()
      // Extract vertices from r... but we don't track r as a bit-set.
      // Instead, we track it via the current array.
      for i = 0; i < state.current.length(); i = i + 1 {
        state.best_clique.push(state.current[i])
      }
    }
    return
  }
  // Pruning: if |R| + |P| <= best_size, no better clique can be found.
  if r_size + popcount(p) <= state.best_size {
    return
  }
  // Choose pivot u from P ∪ X (the vertex with max degree in P).
  let union = p | x
  let pivot = lowest_bit(union)
  // Candidates: P \ N(pivot) = P & ~N(pivot)
  // In MoonBit, ~ is not available, so we use: A & ~B == A ^ (A & B)
  let p_candidates = p ^ (p & state.adj[pivot])
  // Iterate over candidates.
  let mut v_list = p_candidates
  while v_list != 0 {
    let v = lowest_bit(v_list)
    v_list = v_list & (v_list - 1) // remove v
    let neighbors = state.adj[v]
    state.current.push(v)
    bron_kerbosch(
      state,
      r_size + 1,
      p & neighbors,
      x & neighbors,
    )
    // Remove v from current.
    state.current.remove(state.current.length() - 1) |> ignore
  }
}

/// Find the size of the maximum clique in the graph.
///
/// Returns 0 for an empty graph, or 1 for a graph with no edges
/// (each vertex is a clique of size 1).
pub fn max_clique_size(graph : Graph) -> Int {
  let n = graph.n
  if n == 0 {
    return 0
  }
  let state : SearchState = {
    adj: graph.adj,
    best_size: 0,
    best_clique: [],
    current: [],
  }
  // Start with all vertices as candidates.
  let mut all_vertices = 0
  for i = 0; i < n; i = i + 1 {
    all_vertices = all_vertices | (1 << i)
  }
  bron_kerbosch(state, 0, all_vertices, 0)
  state.best_size
}

/// Find the vertices of a maximum clique.
///
/// Returns an array of vertex indices forming a maximum clique.
pub fn find_max_clique(graph : Graph) -> Array[Int] {
  let n = graph.n
  if n == 0 {
    return []
  }
  let state : SearchState = {
    adj: graph.adj,
    best_size: 0,
    best_clique: [],
    current: [],
  }
  let mut all_vertices = 0
  for i = 0; i < n; i = i + 1 {
    all_vertices = all_vertices | (1 << i)
  }
  bron_kerbosch(state, 0, all_vertices, 0)
  state.best_clique
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "max_clique: empty graph" {
  let g = new_graph(0)
  assert_eq(max_clique_size(g), 0)
}

test "max_clique: no edges" {
  let g = new_graph(5)
  assert_eq(max_clique_size(g), 1)
}

test "max_clique: single edge" {
  let g = new_graph(2)
  add_edge(g, 0, 1)
  assert_eq(max_clique_size(g), 2)
}

test "max_clique: triangle" {
  let g = new_graph(3)
  add_edge(g, 0, 1)
  add_edge(g, 1, 2)
  add_edge(g, 0, 2)
  assert_eq(max_clique_size(g), 3)
}

test "max_clique: K4" {
  let g = new_graph(4)
  add_edge(g, 0, 1)
  add_edge(g, 0, 2)
  add_edge(g, 0, 3)
  add_edge(g, 1, 2)
  add_edge(g, 1, 3)
  add_edge(g, 2, 3)
  assert_eq(max_clique_size(g), 4)
}

test "max_clique: two triangles" {
  // 0-1-2 form a triangle, 3-4-5 form a triangle, connected by edge 2-3.
  let g = new_graph(6)
  // Triangle 1
  add_edge(g, 0, 1)
  add_edge(g, 1, 2)
  add_edge(g, 0, 2)
  // Triangle 2
  add_edge(g, 3, 4)
  add_edge(g, 4, 5)
  add_edge(g, 3, 5)
  // Bridge
  add_edge(g, 2, 3)
  assert_eq(max_clique_size(g), 3)
}

test "max_clique: path graph" {
  // 0-1-2-3-4, max clique = 2 (any edge)
  let g = new_graph(5)
  add_edge(g, 0, 1)
  add_edge(g, 1, 2)
  add_edge(g, 2, 3)
  add_edge(g, 3, 4)
  assert_eq(max_clique_size(g), 2)
}

test "max_clique: K4 plus extras" {
  // K4 on vertices 0,1,2,3 plus vertex 4 connected only to 0.
  let g = new_graph(5)
  add_edge(g, 0, 1)
  add_edge(g, 0, 2)
  add_edge(g, 0, 3)
  add_edge(g, 1, 2)
  add_edge(g, 1, 3)
  add_edge(g, 2, 3)
  add_edge(g, 0, 4)
  assert_eq(max_clique_size(g), 4)
}

test "max_clique: complete graph K5" {
  let g = new_graph(5)
  for i = 0; i < 5; i = i + 1 {
    for j = i + 1; j < 5; j = j + 1 {
      add_edge(g, i, j)
    }
  }
  assert_eq(max_clique_size(g), 5)
}

test "max_clique: find max clique" {
  // Triangle 0-1-2, plus vertex 3 connected to 0 and 1.
  // Max clique: {0, 1, 2} or {0, 1, 3} → size 3
  let g = new_graph(4)
  add_edge(g, 0, 1)
  add_edge(g, 1, 2)
  add_edge(g, 0, 2)
  add_edge(g, 0, 3)
  add_edge(g, 1, 3)
  let clique = find_max_clique(g)
  assert_eq(clique.length(), 3)
  // Verify it's a valid clique.
  for i = 0; i < clique.length(); i = i + 1 {
    for j = i + 1; j < clique.length(); j = j + 1 {
      assert_true(has_edge(g, clique[i], clique[j]))
    }
  }
}

test "max_clique: pentagon" {
  // Pentagon (5-cycle): no triangles, max clique = 2
  let g = new_graph(5)
  add_edge(g, 0, 1)
  add_edge(g, 1, 2)
  add_edge(g, 2, 3)
  add_edge(g, 3, 4)
  add_edge(g, 4, 0)
  assert_eq(max_clique_size(g), 2)
}

test "max_clique: complex graph" {
  // Graph with two K3's sharing one vertex, plus an extra edge.
  // Vertices: 0,1,2 (triangle), 0,3,4 (triangle), 5-6 edge.
  // Max clique = 3
  let g = new_graph(7)
  add_edge(g, 0, 1)
  add_edge(g, 1, 2)
  add_edge(g, 0, 2)
  add_edge(g, 0, 3)
  add_edge(g, 3, 4)
  add_edge(g, 0, 4)
  add_edge(g, 5, 6)
  assert_eq(max_clique_size(g), 3)
}
