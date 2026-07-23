/// Sparse graph using adjacency-list representation.
///
/// Provides O(V + E) space, in contrast to the O(V²) adjacency-matrix
/// graphs used by the `bfs_dfs`, `dijkstra`, and `advanced` packages.
/// This representation is essential for sparse graphs (e.g., road networks,
/// social graphs) where E << V².
///
/// The graph stores directed weighted edges. For undirected graphs, add
/// each edge in both directions.
///
/// All functions return `Option` types for error cases — no magic values.

/// A directed weighted edge: `to` is the destination, `weight` the cost.
pub struct Edge {
  to : Int
  weight : Int
}

/// Adjacency-list graph. `adj[v]` holds all outgoing edges from vertex `v`.
///
/// Create with `new(n)` then add edges with `add_edge`. The number of
/// vertices is fixed at construction; edges are mutable.
pub struct Graph {
  n : Int
  adj : FixedArray[Array[Edge]]
}

/// Create a new graph with `n` vertices and no edges.
pub fn new(n : Int) -> Graph {
  // Each vertex gets its own independent Array; using makei ensures no
  // shared reference (FixedArray::make(n, []) would alias one array).
  let adj : FixedArray[Array[Edge]] = FixedArray::makei(n, fn(_) { [] })
  { n, adj }
}

/// Number of vertices in the graph.
pub fn num_vertices(g : Graph) -> Int {
  g.n
}

/// Count total number of edges.
pub fn num_edges(g : Graph) -> Int {
  let mut total = 0
  for v = 0; v < g.n; {
    total = total + g.adj[v].length()
    continue v + 1
  } nobreak {
    total
  }
}

/// Add a directed edge from `u` to `v` with the given `weight`.
///
/// Returns `false` (without modifying the graph) if `u` or `v` is
/// out of bounds. Otherwise appends the edge and returns `true`.
pub fn add_edge(g : Graph, u : Int, v : Int, weight : Int) -> Bool {
  if u < 0 || u >= g.n || v < 0 || v >= g.n {
    return false
  }
  g.adj[u].push({ to: v, weight })
  true
}

/// Add an undirected edge (both directions).
pub fn add_undirected_edge(g : Graph, u : Int, v : Int, weight : Int) -> Bool {
  let ok1 = add_edge(g, u, v, weight)
  let ok2 = add_edge(g, v, u, weight)
  ok1 && ok2
}

/// Get all outgoing edges from vertex `v`.
/// Returns `None` if `v` is out of bounds.
pub fn neighbors(g : Graph, v : Int) -> Array[Edge]? {
  if v < 0 || v >= g.n {
    return None
  }
  Some(g.adj[v])
}

// ---------------------------------------------------------------------------
// BFS traversal
// ---------------------------------------------------------------------------

/// Count vertices reachable from `src` (including `src` itself) via BFS.
/// Returns `None` for invalid `src`.
pub fn bfs_count(g : Graph, src : Int) -> Int? {
  if src < 0 || src >= g.n {
    return None
  }
  let visited = FixedArray::make(g.n, false)
  let queue = FixedArray::make(g.n, 0)
  visited[src] = true
  queue[0] = src
  let mut head = 0
  let mut tail = 1
  let mut count = 1
  while head < tail {
    let u = queue[head]
    head = head + 1
    for i = 0; i < g.adj[u].length(); i = i + 1 {
      let v = g.adj[u][i].to
      if !visited[v] {
        visited[v] = true
        queue[tail] = v
        tail = tail + 1
        count = count + 1
      }
    }
  }
  Some(count)
}

/// Compute shortest-path hop counts from `src` to all vertices via BFS.
///
/// Returns `Some(dist)` where `dist[i]` is `Some(hops)` if reachable, or
/// `None` if unreachable. Returns `None` (outer) for invalid `src`.
pub fn bfs_distances(g : Graph, src : Int) -> FixedArray[Int?]? {
  if src < 0 || src >= g.n {
    return None
  }
  let result : FixedArray[Int?] = FixedArray::make(g.n, None)
  let queue = FixedArray::make(g.n, 0)
  result[src] = Some(0)
  queue[0] = src
  let mut head = 0
  let mut tail = 1
  while head < tail {
    let u = queue[head]
    head = head + 1
    let du = result[u].unwrap()
    for i = 0; i < g.adj[u].length(); i = i + 1 {
      let v = g.adj[u][i].to
      if result[v] is None {
        result[v] = Some(du + 1)
        queue[tail] = v
        tail = tail + 1
      }
    }
  }
  Some(result)
}

/// Check whether `dst` is reachable from `src`.
/// Returns `false` for invalid vertices or no path.
pub fn has_path(g : Graph, src : Int, dst : Int) -> Bool {
  if src < 0 || src >= g.n || dst < 0 || dst >= g.n {
    return false
  }
  if src == dst {
    return true
  }
  let visited = FixedArray::make(g.n, false)
  let queue = FixedArray::make(g.n, 0)
  visited[src] = true
  queue[0] = src
  let mut head = 0
  let mut tail = 1
  while head < tail {
    let u = queue[head]
    head = head + 1
    for i = 0; i < g.adj[u].length(); i = i + 1 {
      let v = g.adj[u][i].to
      if v == dst {
        return true
      }
      if !visited[v] {
        visited[v] = true
        queue[tail] = v
        tail = tail + 1
      }
    }
  }
  false
}

// ---------------------------------------------------------------------------
// DFS traversal
// ---------------------------------------------------------------------------

/// Count vertices reachable from `src` via iterative DFS.
/// Returns `None` for invalid `src`.
pub fn dfs_count(g : Graph, src : Int) -> Int? {
  if src < 0 || src >= g.n {
    return None
  }
  let visited = FixedArray::make(g.n, false)
  let stack = FixedArray::make(g.n, 0)
  visited[src] = true
  stack[0] = src
  let mut top = 1
  let mut count = 1
  while top > 0 {
    top = top - 1
    let u = stack[top]
    for i = 0; i < g.adj[u].length(); i = i + 1 {
      let v = g.adj[u][i].to
      if !visited[v] {
        visited[v] = true
        stack[top] = v
        top = top + 1
        count = count + 1
      }
    }
  }
  Some(count)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "adj_list: create and add edges" {
  let g = new(5)
  assert_eq(num_vertices(g), 5)
  assert_eq(num_edges(g), 0)
  assert_eq(add_edge(g, 0, 1, 10), true)
  assert_eq(add_edge(g, 0, 2, 20), true)
  assert_eq(add_edge(g, 1, 3, 30), true)
  assert_eq(num_edges(g), 3)
}

test "adj_list: invalid edges rejected" {
  let g = new(3)
  assert_eq(add_edge(g, 0, 1, 5), true)
  assert_eq(add_edge(g, -1, 1, 5), false)
  assert_eq(add_edge(g, 0, 3, 5), false)
  assert_eq(add_edge(g, 0, -1, 5), false)
  assert_eq(num_edges(g), 1)
}

test "adj_list: undirected edges" {
  let g = new(4)
  assert_eq(add_undirected_edge(g, 0, 1, 5), true)
  assert_eq(num_edges(g), 2)
  let n0 = neighbors(g, 0).unwrap()
  assert_eq(n0.length(), 1)
  assert_eq(n0[0].to, 1)
  let n1 = neighbors(g, 1).unwrap()
  assert_eq(n1.length(), 1)
  assert_eq(n1[0].to, 0)
}

test "adj_list: neighbors" {
  let g = new(4)
  let _ = add_edge(g, 1, 0, 5)
  let _ = add_edge(g, 1, 2, 3)
  let _ = add_edge(g, 1, 3, 7)
  let n = neighbors(g, 1).unwrap()
  assert_eq(n.length(), 3)
  assert_eq(n[0].to, 0)
  assert_eq(n[1].to, 2)
  assert_eq(n[2].to, 3)
  assert_eq(n[0].weight, 5)
  assert_eq(n[1].weight, 3)
  assert_eq(n[2].weight, 7)
  assert_true(neighbors(g, 5) is None)
}

test "adj_list: bfs_count path graph" {
  let g = new(4)
  let _ = add_edge(g, 0, 1, 1)
  let _ = add_edge(g, 1, 2, 1)
  let _ = add_edge(g, 2, 3, 1)
  assert_eq(bfs_count(g, 0), Some(4))
  assert_eq(bfs_count(g, 2), Some(2))
  assert_eq(bfs_count(g, 3), Some(1))
}

test "adj_list: bfs_count disconnected" {
  let g = new(4)
  let _ = add_edge(g, 0, 1, 1)
  let _ = add_edge(g, 2, 3, 1)
  assert_eq(bfs_count(g, 0), Some(2))
  assert_eq(bfs_count(g, 2), Some(2))
  assert_eq(bfs_count(g, 3), Some(1))
}

test "adj_list: bfs_count invalid src" {
  let g = new(3)
  assert_true(bfs_count(g, -1) is None)
  assert_true(bfs_count(g, 3) is None)
}

test "adj_list: bfs_distances" {
  let g = new(4)
  let _ = add_edge(g, 0, 1, 1)
  let _ = add_edge(g, 0, 2, 1)
  let _ = add_edge(g, 1, 3, 1)
  let dist = bfs_distances(g, 0).unwrap()
  assert_eq(dist[0], Some(0))
  assert_eq(dist[1], Some(1))
  assert_eq(dist[2], Some(1))
  assert_eq(dist[3], Some(2))
}

test "adj_list: bfs_distances unreachable" {
  let g = new(3)
  let _ = add_edge(g, 0, 1, 1)
  let dist = bfs_distances(g, 0).unwrap()
  assert_eq(dist[0], Some(0))
  assert_eq(dist[1], Some(1))
  assert_true(dist[2] is None)
}

test "adj_list: bfs_distances invalid src" {
  let g = new(3)
  assert_true(bfs_distances(g, -1) is None)
  assert_true(bfs_distances(g, 5) is None)
}

test "adj_list: has_path" {
  let g = new(4)
  let _ = add_edge(g, 0, 1, 1)
  let _ = add_edge(g, 1, 2, 1)
  assert_eq(has_path(g, 0, 2), true)
  assert_eq(has_path(g, 2, 0), false)
  assert_eq(has_path(g, 0, 0), true)
  assert_eq(has_path(g, 0, 3), false)
}

test "adj_list: has_path invalid" {
  let g = new(3)
  let _ = add_edge(g, 0, 1, 1)
  assert_eq(has_path(g, -1, 0), false)
  assert_eq(has_path(g, 0, 5), false)
  assert_eq(has_path(g, 5, 5), false)
}

test "adj_list: dfs_count" {
  let g = new(5)
  let _ = add_edge(g, 0, 1, 1)
  let _ = add_edge(g, 0, 2, 1)
  let _ = add_edge(g, 1, 3, 1)
  let _ = add_edge(g, 3, 4, 1)
  assert_eq(dfs_count(g, 0), Some(5))
  assert_eq(dfs_count(g, 2), Some(1))
  assert_eq(dfs_count(g, 4), Some(1))
}

test "adj_list: dfs_count invalid" {
  let g = new(3)
  assert_true(dfs_count(g, -1) is None)
  assert_true(dfs_count(g, 3) is None)
}

test "adj_list: cycle" {
  let g = new(3)
  let _ = add_edge(g, 0, 1, 1)
  let _ = add_edge(g, 1, 2, 1)
  let _ = add_edge(g, 2, 0, 1)
  assert_eq(bfs_count(g, 0), Some(3))
  assert_eq(dfs_count(g, 0), Some(3))
  assert_eq(has_path(g, 0, 2), true)
  assert_eq(has_path(g, 2, 0), true)
}

test "adj_list: single node" {
  let g = new(1)
  assert_eq(bfs_count(g, 0), Some(1))
  assert_eq(dfs_count(g, 0), Some(1))
  assert_eq(has_path(g, 0, 0), true)
  let dist = bfs_distances(g, 0).unwrap()
  assert_eq(dist[0], Some(0))
}

test "adj_list: complete graph K4" {
  let g = new(4)
  for i = 0; i < 4; i = i + 1 {
    for j = 0; j < 4; j = j + 1 {
      if i != j {
        let _ = add_edge(g, i, j, 1)
      }
    }
  }
  assert_eq(num_edges(g), 12)
  assert_eq(bfs_count(g, 0), Some(4))
  assert_eq(dfs_count(g, 0), Some(4))
  let dist = bfs_distances(g, 0).unwrap()
  for i = 0; i < 4; i = i + 1 {
    assert_eq(dist[i], Some(if i == 0 { 0 } else { 1 }))
  }
}

test "adj_list: star graph" {
  let g = new(4)
  let _ = add_undirected_edge(g, 0, 1, 1)
  let _ = add_undirected_edge(g, 0, 2, 1)
  let _ = add_undirected_edge(g, 0, 3, 1)
  assert_eq(bfs_count(g, 0), Some(4))
  let dist = bfs_distances(g, 0).unwrap()
  assert_eq(dist[0], Some(0))
  assert_eq(dist[1], Some(1))
  assert_eq(dist[2], Some(1))
  assert_eq(dist[3], Some(1))
}

test "adj_list: sparse graph space efficiency" {
  // A sparse graph with 1000 vertices and ~999 edges uses far less
  // memory than a 1000x1000 adjacency matrix (1M entries).
  let g = new(1000)
  for i = 0; i < 999; i = i + 1 {
    let _ = add_edge(g, i, i + 1, 1)
  }
  assert_eq(num_edges(g), 999)
  assert_eq(bfs_count(g, 0), Some(1000))
  let dist = bfs_distances(g, 0).unwrap()
  assert_eq(dist[999], Some(999))
}

test "adj_list: weighted edges preserved" {
  let g = new(3)
  let _ = add_edge(g, 0, 1, 42)
  let _ = add_edge(g, 1, 2, -7)
  let n0 = neighbors(g, 0).unwrap()
  assert_eq(n0[0].weight, 42)
  let n1 = neighbors(g, 1).unwrap()
  assert_eq(n1[0].weight, -7)
}

test "adj_list: self-loop" {
  let g = new(2)
  let _ = add_edge(g, 0, 0, 1)
  let _ = add_edge(g, 0, 1, 1)
  assert_eq(bfs_count(g, 0), Some(2))
  assert_eq(has_path(g, 0, 0), true)
}

test "adj_list: parallel edges" {
  let g = new(2)
  let _ = add_edge(g, 0, 1, 5)
  let _ = add_edge(g, 0, 1, 3)
  assert_eq(num_edges(g), 2)
  let n = neighbors(g, 0).unwrap()
  assert_eq(n.length(), 2)
}

test "adj_list: bfs_distances consistent with has_path" {
  let g = new(5)
  let _ = add_edge(g, 0, 1, 1)
  let _ = add_edge(g, 1, 2, 1)
  let _ = add_edge(g, 3, 4, 1)
  let dist = bfs_distances(g, 0).unwrap()
  for k = 0; k < 5; k = k + 1 {
    let reachable = dist[k] is Some(_)
    assert_eq(has_path(g, 0, k), reachable)
  }
}
