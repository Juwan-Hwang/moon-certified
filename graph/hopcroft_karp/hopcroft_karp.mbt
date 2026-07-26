/// Hopcroft-Karp algorithm for maximum cardinality bipartite matching.
///
/// Given a bipartite graph with left vertices `{0, 1, ..., n-1}` and right
/// vertices `{0, 1, ..., m-1}`, finds a matching of maximum size in
/// O(E * sqrt(V)) time, where V = n + m and E is the number of edges.
///
/// ## Algorithm
///
/// The algorithm works in phases. Each phase consists of:
///
/// 1. **BFS**: Build a layered graph of alternating paths starting from
///    unmatched left vertices. `dist[u]` stores the BFS distance from the
///    nearest unmatched left vertex to `u`. Right vertices at the minimum
///    distance to an unmatched right vertex are "on the frontier".
///
/// 2. **DFS**: Find a maximal set of vertex-disjoint shortest augmenting
///    paths using the layered graph. Augment along each path found.
///
/// Each phase increases the length of the shortest augmenting path, so
/// there are at most O(sqrt(V)) phases, each taking O(E) time.
///
/// ## Complexity
///
/// - Time: O(E * sqrt(V))
/// - Space: O(V + E)
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Bipartite graph representation
// ---------------------------------------------------------------------------

///|
/// A bipartite graph with left vertices `{0..n-1}` and right vertices `{0..m-1}`.
///
/// Edges are stored as adjacency lists for the left side.
pub struct BipartiteGraph {
  n : Int // number of left vertices
  m : Int // number of right vertices
  adj : Array[Array[Int]] // adj[u] = list of right vertices adjacent to left u
}

///|
/// Create an empty bipartite graph with `n` left and `m` right vertices.
pub fn new_graph(n : Int, m : Int) -> BipartiteGraph {
  let adj : Array[Array[Int]] = Array::makei(n, fn(_) { [] })
  { n, m, adj }
}

///|
/// Add an edge from left vertex `u` to right vertex `v`.
pub fn add_edge(graph : BipartiteGraph, u : Int, v : Int) -> Unit {
  graph.adj[u].push(v)
}

// ---------------------------------------------------------------------------
// Hopcroft-Karp algorithm
// ---------------------------------------------------------------------------

///|
/// INF sentinel for "unreachable" in BFS distances.
const INF : Int = 1_000_000_000

///|
/// BFS: compute distances from unmatched left vertices.
///
/// Returns `true` if at least one unmatched right vertex is reachable
/// (i.e., an augmenting path exists).
///
/// `dist_left[u]` = BFS layer of left vertex `u` (INF if unreachable).
/// `dist_right[v]` = BFS layer of right vertex `v` (INF if unreachable).
fn bfs(
  graph : BipartiteGraph,
  match_l : Array[Int],
  match_r : Array[Int],
  dist_left : Array[Int],
  dist_right : Array[Int],
) -> Bool {
  let n = graph.n
  let m = graph.m
  // Queue for BFS.
  let queue : Array[Int] = []
  // Initialize distances.
  for u = 0; u < n; u = u + 1 {
    dist_left[u] = INF
  }
  for v = 0; v < m; v = v + 1 {
    dist_right[v] = INF
  }
  // Enqueue all unmatched left vertices with distance 0.
  for u = 0; u < n; u = u + 1 {
    if match_l[u] == -1 {
      dist_left[u] = 0
      queue.push(u)
    }
  }
  let mut found = false
  let mut head = 0
  while head < queue.length() {
    let u = queue[head]
    head = head + 1
    for i = 0; i < graph.adj[u].length(); i = i + 1 {
      let v = graph.adj[u][i]
      // If v is matched, explore its match.
      let mu = match_r[v]
      if mu != -1 && dist_left[mu] == INF {
        dist_left[mu] = dist_left[u] + 2
        dist_right[v] = dist_left[u] + 1
        queue.push(mu)
      } else if mu == -1 {
        // v is unmatched — we found an augmenting path endpoint.
        dist_right[v] = dist_left[u] + 1
        found = true
      }
    }
  }
  found
}

///|
/// DFS: find augmenting paths using the BFS layering.
///
/// Returns `true` if an augmenting path was found from `u`.
fn dfs(
  graph : BipartiteGraph,
  u : Int,
  match_l : Array[Int],
  match_r : Array[Int],
  dist_left : Array[Int],
  dist_right : Array[Int],
) -> Bool {
  for i = 0; i < graph.adj[u].length(); i = i + 1 {
    let v = graph.adj[u][i]
    // Only follow edges that respect the BFS layering.
    if dist_right[v] == dist_left[u] + 1 {
      let mu = match_r[v]
      if mu == -1 {
        // v is unmatched — augment!
        match_l[u] = v
        match_r[v] = u
        dist_right[v] = INF // mark as used
        return true
      }
    }
  }
  // Try to extend through matched edges.
  for i = 0; i < graph.adj[u].length(); i = i + 1 {
    let v = graph.adj[u][i]
    if dist_right[v] == dist_left[u] + 1 {
      let mu = match_r[v]
      if mu != -1 && dist_left[mu] == dist_left[u] + 2 {
        dist_right[v] = INF // mark edge as used
        if dfs(graph, mu, match_l, match_r, dist_left, dist_right) {
          match_l[u] = v
          match_r[v] = u
          return true
        }
      }
    }
  }
  false
}

///|
/// Compute the maximum cardinality matching of a bipartite graph.
///
/// Returns the matching size and the assignment arrays:
/// - `match_l[u]` = right vertex matched to left `u` (or -1 if unmatched)
/// - `match_r[v]` = left vertex matched to right `v` (or -1 if unmatched)
pub fn max_matching(graph : BipartiteGraph) -> (Int, Array[Int], Array[Int]) {
  let n = graph.n
  let m = graph.m
  let match_l : Array[Int] = Array::make(n, -1)
  let match_r : Array[Int] = Array::make(m, -1)
  let dist_left : Array[Int] = Array::make(n, INF)
  let dist_right : Array[Int] = Array::make(m, INF)
  let mut matching_size = 0
  while bfs(graph, match_l, match_r, dist_left, dist_right) {
    for u = 0; u < n; u = u + 1 {
      if match_l[u] == -1 {
        if dfs(graph, u, match_l, match_r, dist_left, dist_right) {
          matching_size = matching_size + 1
        }
      }
    }
  }
  (matching_size, match_l, match_r)
}

///|
/// Compute only the size of the maximum matching (convenience wrapper).
pub fn max_matching_size(graph : BipartiteGraph) -> Int {
  let (size, _, _) = max_matching(graph)
  size
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "hopcroft_karp: simple matching" {
  // Left: 0, 1, 2   Right: 0, 1, 2
  // Edges: 0-0, 0-1, 1-1, 1-2, 2-2
  // Max matching: {0-0, 1-1, 2-2} or {0-1, 1-2, 2-?} → size 3
  let g = new_graph(3, 3)
  add_edge(g, 0, 0)
  add_edge(g, 0, 1)
  add_edge(g, 1, 1)
  add_edge(g, 1, 2)
  add_edge(g, 2, 2)
  assert_eq(max_matching_size(g), 3)
}

///|
test "hopcroft_karp: no edges" {
  let g = new_graph(3, 3)
  assert_eq(max_matching_size(g), 0)
}

///|
test "hopcroft_karp: single edge" {
  let g = new_graph(1, 1)
  add_edge(g, 0, 0)
  assert_eq(max_matching_size(g), 1)
}

///|
test "hopcroft_karp: star graph" {
  // Left: 0, 1, 2   Right: 0
  // All left vertices connect to right 0.
  // Max matching: only one can match → size 1
  let g = new_graph(3, 1)
  add_edge(g, 0, 0)
  add_edge(g, 1, 0)
  add_edge(g, 2, 0)
  assert_eq(max_matching_size(g), 1)
}

///|
test "hopcroft_karp: complete bipartite" {
  // K_{3,3}: every left connects to every right.
  // Max matching = 3 (perfect matching).
  let g = new_graph(3, 3)
  for u = 0; u < 3; u = u + 1 {
    for v = 0; v < 3; v = v + 1 {
      add_edge(g, u, v)
    }
  }
  assert_eq(max_matching_size(g), 3)
}

///|
test "hopcroft_karp: asymmetric" {
  // Left: 0, 1   Right: 0, 1, 2
  // Edges: 0-0, 0-2, 1-1, 1-2
  // Max matching: {0-0, 1-1} or {0-2, 1-1} → size 2
  let g = new_graph(2, 3)
  add_edge(g, 0, 0)
  add_edge(g, 0, 2)
  add_edge(g, 1, 1)
  add_edge(g, 1, 2)
  assert_eq(max_matching_size(g), 2)
}

///|
test "hopcroft_karp: matching assignment" {
  // Left: 0, 1   Right: 0, 1
  // Edges: 0-0, 0-1, 1-0
  // Max matching: {0-1, 1-0} → size 2
  let g = new_graph(2, 2)
  add_edge(g, 0, 0)
  add_edge(g, 0, 1)
  add_edge(g, 1, 0)
  let (size, match_l, _) = max_matching(g)
  assert_eq(size, 2)
  // Verify: each left vertex is matched.
  for u = 0; u < 2; u = u + 1 {
    assert_true(match_l[u] != -1)
  }
}

///|
test "hopcroft_karp: larger graph" {
  // Left: 0..4   Right: 0..4
  // A "chain" pattern: 0-0, 0-1, 1-1, 1-2, 2-2, 2-3, 3-3, 3-4, 4-4
  // Max matching = 5
  let g = new_graph(5, 5)
  for u = 0; u < 5; u = u + 1 {
    add_edge(g, u, u)
    if u + 1 < 5 {
      add_edge(g, u, u + 1)
    }
  }
  assert_eq(max_matching_size(g), 5)
}

///|
test "hopcroft_karp: disconnected" {
  // Two components: {0-0, 1-1} and {2-2, 3-3}
  let g = new_graph(4, 4)
  add_edge(g, 0, 0)
  add_edge(g, 1, 1)
  add_edge(g, 2, 2)
  add_edge(g, 3, 3)
  assert_eq(max_matching_size(g), 4)
}
