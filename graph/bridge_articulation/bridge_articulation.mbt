/// Tarjan's bridge and articulation point (cut vertex) finding algorithm.
///
/// Given an **undirected** graph as an adjacency list, finds:
/// - **Articulation points** (cut vertices): vertices whose removal increases
///   the number of connected components.
/// - **Bridges**: edges whose removal increases the number of connected
///   components.
///
/// ## Algorithm
///
/// Uses Tarjan's single-pass DFS with discovery times and low-link values:
/// - `disc[v]` = the time vertex `v` was first visited.
/// - `low[v]` = the minimum `disc` reachable from `v` using at most one
///   back-edge in the DFS tree (tree edges + one back-edge).
///
/// A vertex `u` is an articulation point if:
/// 1. It is the DFS root and has ≥ 2 children in the DFS tree, or
/// 2. It is not the root and has a child `v` with `low[v] >= disc[u]`.
///
/// An edge `(u, v)` is a bridge if `v` is a child of `u` in the DFS tree
/// and `low[v] > disc[u]` (strictly greater — equal would mean `v` can
/// reach `u` via a back-edge, so removing `(u,v)` doesn't disconnect).
///
/// ## Complexity
///
/// - Time: O(V + E) — single DFS pass.
/// - Space: O(V + E) for the adjacency list and DFS state.
///
/// ## Implementation notes
///
/// The DFS is **iterative** (explicit stack) to prevent stack overflow on
/// large or degenerate graphs. MoonBit does not guarantee tail-call
/// optimisation, so a recursive implementation could crash on graphs with
/// long paths.
///
/// Self-loops and multi-edges are handled correctly:
/// - Self-loops are never bridges (removing them doesn't disconnect anything).
/// - Multi-edges: if there are two or more edges between `u` and `v`, none of
///   them is a bridge (the other edge keeps the pair connected).
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

///|
/// Result of bridge/articulation-point computation.
///
/// - `articulation_points`: a `FixedArray[Int]` of vertex indices that are
///   cut vertices, sorted ascending.
/// - `bridges`: a `FixedArray[(Int, Int)]` of `(u, v)` pairs where `u < v`,
///   sorted lexicographically.
pub struct BridgeArtResult {
  articulation_points : FixedArray[Int]
  bridges : FixedArray[(Int, Int)]
}

// ---------------------------------------------------------------------------
// Internal state
// ---------------------------------------------------------------------------

///|
priv struct BridgeState {
  adj : Array[Array[Int]]
  mut timer : Int
  disc : FixedArray[Int] // -1 = unvisited
  low : FixedArray[Int]
  parent : FixedArray[Int] // -1 = root, -2 = unset
  is_articulation : FixedArray[Bool]
  root_children : FixedArray[Int] // children count for root vertex
  bridges : Array[(Int, Int)]
}

///|
fn BridgeState::new(adj : Array[Array[Int]], n : Int) -> BridgeState {
  {
    adj,
    timer: 0,
    disc: FixedArray::make(n, -1),
    low: FixedArray::make(n, 0),
    parent: FixedArray::make(n, -2),
    is_articulation: FixedArray::make(n, false),
    root_children: FixedArray::make(n, 0),
    bridges: [],
  }
}

// ---------------------------------------------------------------------------
// Iterative DFS
// ---------------------------------------------------------------------------

///|
/// Iterative Tarjan DFS from `start`.
///
/// Uses an explicit stack of `(vertex, next_neighbor_index, parent_vertex,
/// parent_edge_skipped)` entries. Each entry represents a vertex currently
/// being explored, along with the index of the next neighbor to visit. When
/// all neighbors are processed, the vertex is popped and its low-link value
/// propagates to the parent.
///
/// Multi-edges (parallel edges between the same pair of vertices) are handled
/// by skipping exactly one edge back to the parent — the reverse of the tree
/// edge we arrived on — and treating any additional edges to the parent as
/// back-edges. This is tracked with the `parent_edge_skipped` flag, which is
/// correct where the classic `v != parent` test fails (that test skips *all*
/// parallel edges to the parent, misclassifying them as bridges).
fn dfs(state : BridgeState, start : Int) -> Unit {
  // Stack entries: (vertex, next_neighbor_index, parent_vertex, parent_edge_skipped).
  // `parent_edge_skipped` records whether we have already skipped the single
  // reverse tree-edge back to the parent; further edges to the parent are
  // parallel edges and treated as back-edges (so they are not bridges).
  let stack : Array[(Int, Int, Int, Bool)] = [(start, 0, -1, false)]
  state.disc[start] = state.timer
  state.low[start] = state.timer
  state.timer = state.timer + 1
  state.parent[start] = -1
  while stack.length() > 0 {
    let top_idx = stack.length() - 1
    let (u, next_j, par, skipped) = stack[top_idx]
    let neighbors = state.adj[u]
    if next_j < neighbors.length() {
      let v = neighbors[next_j]
      if state.disc[v] == -1 {
        // Tree edge: visit v. Advance u past this neighbor.
        state.disc[v] = state.timer
        state.low[v] = state.timer
        state.timer = state.timer + 1
        state.parent[v] = u
        if u == start {
          state.root_children[start] = state.root_children[start] + 1
        }
        stack[top_idx] = (u, next_j + 1, par, skipped)
        stack.push((v, 0, u, false))
      } else if v == par && !skipped {
        // Reverse of the tree edge we arrived on: skip it exactly once.
        // Any *additional* edge to the parent is a parallel edge and is
        // handled by the back-edge branch below.
        stack[top_idx] = (u, next_j + 1, par, true)
      } else {
        // Back-edge: a parallel edge to the parent (beyond the first), a
        // self-loop, or an edge to another already-visited vertex.
        if state.disc[v] < state.low[u] {
          state.low[u] = state.disc[v]
        }
        stack[top_idx] = (u, next_j + 1, par, skipped)
      }
    } else {
      // All neighbors processed: pop and propagate low to parent.
      ignore(stack.pop())
      if par >= 0 {
        // Propagate low value to parent.
        if state.low[u] < state.low[par] {
          state.low[par] = state.low[u]
        }
        // Check articulation point condition (non-root).
        if par != start && state.low[u] >= state.disc[par] {
          state.is_articulation[par] = true
        }
        // Check bridge condition.
        if state.low[u] > state.disc[par] {
          let bridge = if par < u { (par, u) } else { (u, par) }
          state.bridges.push(bridge)
        }
      }
    }
  }
  // Check root articulation condition.
  if state.root_children[start] >= 2 {
    state.is_articulation[start] = true
  }
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

///|
/// Find all articulation points and bridges in an undirected graph.
///
/// # Parameters
/// - `adj`: adjacency list where `adj[i]` is an array of neighbor indices.
///   The graph must be undirected: if `j` appears in `adj[i]`, then `i`
///   should appear in `adj[j]`. Self-loops are allowed but are never bridges.
/// - `n`: number of vertices, indexed `0 .. n - 1`.
///
/// # Returns
/// A `BridgeArtResult` containing sorted arrays of articulation points and
/// bridges. Returns empty arrays for `n <= 0`.
///
/// # Complexity
/// - Time: O(V + E)
/// - Space: O(V + E)
///
/// The DFS is iterative (explicit stack), so it handles graphs with long
/// paths without stack overflow.
pub fn find_bridges_and_articulations(
  adj : Array[Array[Int]],
  n : Int,
) -> BridgeArtResult {
  if n <= 0 || adj.length() < n {
    return {
      articulation_points: FixedArray::make(0, 0),
      bridges: FixedArray::make(0, (0, 0)),
    }
  }
  let state = BridgeState::new(adj, n)
  for v = 0; v < n; v = v + 1 {
    if state.disc[v] == -1 {
      dfs(state, v)
    }
  }
  // Collect articulation points (sorted).
  let art_list : Array[Int] = []
  for v = 0; v < n; v = v + 1 {
    if state.is_articulation[v] {
      art_list.push(v)
    }
  }
  // Sort bridges lexicographically.
  // Simple insertion sort (lists are typically short).
  let bs = state.bridges
  for i = 1; i < bs.length(); i = i + 1 {
    let key = bs[i]
    let mut j = i - 1
    while j >= 0 {
      let (ju, jv) = bs[j]
      let (ku, kv) = key
      if ju > ku || (ju == ku && jv > kv) {
        bs[j + 1] = bs[j]
        j = j - 1
      } else {
        break
      }
    }
    bs[j + 1] = key
  }
  {
    articulation_points: FixedArray::makei(art_list.length(), fn(i) {
      art_list[i]
    }),
    bridges: FixedArray::makei(bs.length(), fn(i) { bs[i] }),
  }
}

///|
/// Find only articulation points (cut vertices) in an undirected graph.
///
/// Convenience wrapper around `find_bridges_and_articulations` that returns
/// just the articulation points.
pub fn find_articulation_points(
  adj : Array[Array[Int]],
  n : Int,
) -> FixedArray[Int] {
  find_bridges_and_articulations(adj, n).articulation_points
}

///|
/// Find only bridges in an undirected graph.
///
/// Convenience wrapper around `find_bridges_and_articulations` that returns
/// just the bridges.
pub fn find_bridges(adj : Array[Array[Int]], n : Int) -> FixedArray[(Int, Int)] {
  find_bridges_and_articulations(adj, n).bridges
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "bridge_art: single node" {
  let adj : Array[Array[Int]] = [[]]
  let result = find_bridges_and_articulations(adj, 1)
  assert_eq(result.articulation_points.length(), 0)
  assert_eq(result.bridges.length(), 0)
}

///|
test "bridge_art: two nodes connected by single edge (bridge)" {
  // 0 -- 1: the edge is a bridge, neither node is an articulation point
  // (removing either node from a 2-node graph leaves a single node,
  // which is still connected).
  let adj : Array[Array[Int]] = [[1], [0]]
  let result = find_bridges_and_articulations(adj, 2)
  assert_eq(result.articulation_points.length(), 0)
  assert_eq(result.bridges.length(), 1)
  assert_eq(result.bridges[0], (0, 1))
}

///|
test "bridge_art: simple path 0-1-2 (articulation at 1, two bridges)" {
  // 0 -- 1 -- 2
  // Vertex 1 is an articulation point (removing it disconnects 0 and 2).
  // Both edges (0,1) and (1,2) are bridges.
  let adj : Array[Array[Int]] = [[1], [0, 2], [1]]
  let result = find_bridges_and_articulations(adj, 3)
  assert_eq(result.articulation_points.length(), 1)
  assert_eq(result.articulation_points[0], 1)
  assert_eq(result.bridges.length(), 2)
  assert_eq(result.bridges[0], (0, 1))
  assert_eq(result.bridges[1], (1, 2))
}

///|
test "bridge_art: triangle (no bridges, no articulation points)" {
  // 0 -- 1
  // |    |
  // 2 ----
  // Every pair is connected by two paths; removing any edge or vertex
  // keeps the graph connected.
  let adj : Array[Array[Int]] = [[1, 2], [0, 2], [0, 1]]
  let result = find_bridges_and_articulations(adj, 3)
  assert_eq(result.articulation_points.length(), 0)
  assert_eq(result.bridges.length(), 0)
}

///|
test "bridge_art: star graph (center is articulation, all edges are bridges)" {
  //   1
  //   |
  // 0-2-3
  //   |
  //   4
  // Vertex 2 is an articulation point; all 4 edges are bridges.
  let n = 5
  let adj : Array[Array[Int]] = [[], [], [], [], []]
  adj[0].push(2)
  adj[2].push(0)
  adj[1].push(2)
  adj[2].push(1)
  adj[3].push(2)
  adj[2].push(3)
  adj[4].push(2)
  adj[2].push(4)
  let result = find_bridges_and_articulations(adj, n)
  assert_eq(result.articulation_points.length(), 1)
  assert_eq(result.articulation_points[0], 2)
  assert_eq(result.bridges.length(), 4)
}

///|
test "bridge_art: disconnected graph" {
  // Component 1: 0 -- 1 (bridge)
  // Component 2: 2 -- 3 -- 4 -- 2 (triangle, no bridges/articulations)
  let n = 5
  let adj : Array[Array[Int]] = [[], [], [], [], []]
  adj[0].push(1)
  adj[1].push(0)
  adj[2].push(3)
  adj[2].push(4)
  adj[3].push(2)
  adj[3].push(4)
  adj[4].push(2)
  adj[4].push(3)
  let result = find_bridges_and_articulations(adj, n)
  assert_eq(result.articulation_points.length(), 0)
  assert_eq(result.bridges.length(), 1)
  assert_eq(result.bridges[0], (0, 1))
}

///|
test "bridge_art: multi-edge (parallel edges are not bridges)" {
  // 0 == 1 (two edges between 0 and 1)
  // Neither edge is a bridge (removing one still connects 0 and 1).
  let adj : Array[Array[Int]] = [[1, 1], [0, 0]]
  let result = find_bridges_and_articulations(adj, 2)
  assert_eq(result.bridges.length(), 0)
  assert_eq(result.articulation_points.length(), 0)
}

///|
test "bridge_art: self-loop is not a bridge" {
  // 0 has a self-loop, 0 -- 1
  let adj : Array[Array[Int]] = [[0, 1], [0]]
  let result = find_bridges_and_articulations(adj, 2)
  // The edge (0,1) is a bridge; the self-loop is not.
  assert_eq(result.bridges.length(), 1)
  assert_eq(result.bridges[0], (0, 1))
}

///|
test "bridge_art: chain of 5 nodes" {
  // 0 -- 1 -- 2 -- 3 -- 4
  // Nodes 1, 2, 3 are articulation points; all 4 edges are bridges.
  let n = 5
  let adj : Array[Array[Int]] = [[], [], [], [], []]
  for i = 0; i < n - 1; i = i + 1 {
    adj[i].push(i + 1)
    adj[i + 1].push(i)
  }
  let result = find_bridges_and_articulations(adj, n)
  assert_eq(result.articulation_points.length(), 3)
  assert_eq(result.articulation_points[0], 1)
  assert_eq(result.articulation_points[1], 2)
  assert_eq(result.articulation_points[2], 3)
  assert_eq(result.bridges.length(), 4)
}

///|
test "bridge_art: complete graph K4 (no bridges, no articulation)" {
  // Fully connected: removing any edge or vertex keeps it connected.
  let n = 4
  let adj : Array[Array[Int]] = [[], [], [], []]
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      if i != j {
        adj[i].push(j)
      }
    }
  }
  let result = find_bridges_and_articulations(adj, n)
  assert_eq(result.articulation_points.length(), 0)
  assert_eq(result.bridges.length(), 0)
}

///|
test "bridge_art: two triangles connected by a bridge" {
  // Triangle 0-1-2-0, bridge 2-3, triangle 3-4-5-3
  // Vertex 2 and 3 are articulation points; edge (2,3) is a bridge.
  let n = 6
  let adj : Array[Array[Int]] = [[], [], [], [], [], []]
  // First triangle: 0-1, 1-2, 2-0
  adj[0].push(1)
  adj[0].push(2)
  adj[1].push(0)
  adj[1].push(2)
  adj[2].push(0)
  adj[2].push(1)
  // Bridge: 2-3
  adj[2].push(3)
  adj[3].push(2)
  // Second triangle: 3-4, 4-5, 5-3
  adj[3].push(4)
  adj[3].push(5)
  adj[4].push(3)
  adj[4].push(5)
  adj[5].push(3)
  adj[5].push(4)
  let result = find_bridges_and_articulations(adj, n)
  assert_eq(result.articulation_points.length(), 2)
  assert_eq(result.articulation_points[0], 2)
  assert_eq(result.articulation_points[1], 3)
  assert_eq(result.bridges.length(), 1)
  assert_eq(result.bridges[0], (2, 3))
}

///|
test "bridge_art: invalid n returns empty" {
  let adj : Array[Array[Int]] = []
  let result = find_bridges_and_articulations(adj, 0)
  assert_eq(result.articulation_points.length(), 0)
  assert_eq(result.bridges.length(), 0)
}

///|
test "bridge_art: large path (stack safety)" {
  // Chain of 5000 nodes: tests that the iterative DFS doesn't overflow.
  let n = 5000
  let adj : Array[Array[Int]] = []
  for _i = 0; _i < n; _i = _i + 1 {
    adj.push([])
  }
  for i = 0; i < n - 1; i = i + 1 {
    adj[i].push(i + 1)
    adj[i + 1].push(i)
  }
  let result = find_bridges_and_articulations(adj, n)
  // All edges are bridges; all interior nodes are articulation points.
  assert_eq(result.bridges.length(), n - 1)
  assert_eq(result.articulation_points.length(), n - 2)
  // Verify first and last articulation points.
  assert_eq(result.articulation_points[0], 1)
  assert_eq(result.articulation_points[n - 3], n - 2)
}

///|
test "find_articulation_points: convenience wrapper" {
  let adj : Array[Array[Int]] = [[1, 2], [0, 2], [0, 1, 3], [2]]
  // Triangle 0-1-2, edge 2-3
  // Vertex 2 is an articulation point (removing it isolates 3).
  let arts = find_articulation_points(adj, 4)
  assert_eq(arts.length(), 1)
  assert_eq(arts[0], 2)
}

///|
test "find_bridges: convenience wrapper" {
  let adj : Array[Array[Int]] = [[1, 2], [0, 2], [0, 1, 3], [2]]
  let bridges = find_bridges(adj, 4)
  assert_eq(bridges.length(), 1)
  assert_eq(bridges[0], (2, 3))
}
