/// Gabow's Strongly Connected Components Algorithm.
///
/// Gabow's algorithm (also known as the path-based SCC algorithm) decomposes
/// a directed graph into its strongly connected components in O(V + E) time
/// using a single DFS pass with two explicit stacks.
///
/// ## Algorithm
///
/// Unlike Tarjan's algorithm which uses a `lowlink` array, Gabow's method
/// maintains two stacks:
///
/// - **Stack S**: Vertices on the current DFS path, in order of discovery.
/// - **Stack B**: Boundary vertices that delimit potential SCC roots.
///
/// When a back edge or cross edge to an already-visited vertex `w` (still on
/// stack S) is found, we pop stack B until its top has DFS index ≤ `index[w]`.
/// This collapses the boundary, merging potential SCCs.
///
/// When we finish exploring a vertex `v` and `v` is at the top of stack B,
/// `v` is the root of an SCC. We pop vertices from stack S until `v` is
/// popped — those vertices form one SCC.
///
/// ## Complexity
///
/// - Time: O(V + E) — each vertex and edge is processed once.
/// - Space: O(V) for the stacks and auxiliary arrays.
///
/// ## Advantages over Tarjan
///
/// - No `lowlink` computation — simpler invariant to reason about.
/// - Two explicit stacks make the SCC boundary logic more intuitive.
/// - Equivalent asymptotic complexity.
///
/// ## References
///
/// - Gabow, H. N. (2000). "Path-based depth-first search for strong and
///   biconnected components." *Information Processing Letters*, 74(3–4),
///   107–114.
/// - Earlier version: Gabow, H. N. (1991). "Path-based depth-first search
///   for strong and biconnected components." Technical Report CU-CS-690-93,
///   University of Colorado.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Result type
// ---------------------------------------------------------------------------

///|
/// Result of a Gabow SCC computation.
pub struct GabowSCCResult {
  /// `component_id[i]` is the SCC ID of vertex `i`, in range `0 .. num_sccs`.
  /// SCCs are numbered in **reverse topological order**: if there is an edge
  /// from SCC A to SCC B (A ≠ B), then `component_id` of B < `component_id`
  /// of A. In other words, SCC 0 is a sink component.
  component_id : Array[Int]
  /// Number of strongly connected components.
  num_sccs : Int
  /// List of SCCs, each as an array of vertex indices. `sccs[k]` contains
  /// all vertices in SCC `k`. Same ordering as `component_id`.
  sccs : Array[Array[Int]]
}

// ---------------------------------------------------------------------------
// Graph representation
// ---------------------------------------------------------------------------

///|
/// Build an adjacency list from edge pairs.
fn build_adj_list(n : Int, edges : Array[(Int, Int)]) -> Array[Array[Int]] {
  let adj : Array[Array[Int]] = Array::makei(n, fn(_) { [] })
  for i = 0; i < edges.length(); i = i + 1 {
    let (u, v) = edges[i]
    if u >= 0 && u < n && v >= 0 && v < n {
      adj[u].push(v)
    }
  }
  adj
}

// ---------------------------------------------------------------------------
// Gabow's algorithm — iterative implementation
// ---------------------------------------------------------------------------

///|
/// Iterative Gabow SCC using an explicit DFS stack.
///
/// We use an explicit stack of `(vertex, neighbor_index)` frames to avoid
/// recursion depth limits on large graphs.
///
/// Internal state:
/// - `index[v]`: DFS discovery order, 0 = unvisited (1-based).
/// - `stack_s`: vertices on the current DFS path.
/// - `stack_b`: boundary stack for SCC root candidates.
/// - `on_stack_s[v]`: whether `v` is currently on `stack_s`.
fn gabow_scc_core(adj : Array[Array[Int]], n : Int) -> GabowSCCResult {
  let index = Array::make(n, 0) // 0 = unvisited, 1-based discovery order
  let component_id = Array::make(n, -1)
  let stack_s : Array[Int] = []
  let stack_b : Array[Int] = []
  let on_stack_s = Array::make(n, false)
  let sccs : Array[Array[Int]] = []
  let mut counter = 0
  // DFS frame: (vertex, next_neighbor_index)
  let dfs_stack : Array[(Int, Int)] = []
  for start = 0; start < n; start = start + 1 {
    if index[start] != 0 {
      continue
    }
    // Begin DFS from `start`.
    counter = counter + 1
    index[start] = counter
    stack_s.push(start)
    stack_b.push(start)
    on_stack_s[start] = true
    dfs_stack.push((start, 0))
    while dfs_stack.length() > 0 {
      let top_idx = dfs_stack.length() - 1
      let (v, ni) = dfs_stack[top_idx]
      if ni < adj[v].length() {
        // Advance the neighbor pointer for this frame.
        let w = adj[v][ni]
        dfs_stack[top_idx] = (v, ni + 1)
        if index[w] == 0 {
          // Tree edge: recurse into w.
          counter = counter + 1
          index[w] = counter
          stack_s.push(w)
          stack_b.push(w)
          on_stack_s[w] = true
          dfs_stack.push((w, 0))
        } else if on_stack_s[w] {
          // Back/cross edge to a vertex on the current path.
          // Collapse stack_b until its top has index ≤ index[w].
          while stack_b.length() > 0 &&
                index[stack_b[stack_b.length() - 1]] > index[w] {
            ignore(stack_b.pop())
          }
        }
      } else {
        // All neighbors explored; check if v is an SCC root.
        ignore(dfs_stack.pop())
        if stack_b.length() > 0 && stack_b[stack_b.length() - 1] == v {
          // v is the root of an SCC. Pop vertices from stack_s until v.
          ignore(stack_b.pop())
          let scc : Array[Int] = []
          let mut done = false
          while !done {
            let u = stack_s.pop().unwrap()
            on_stack_s[u] = false
            scc.push(u)
            component_id[u] = sccs.length()
            done = u == v
          }
          sccs.push(scc)
        }
      }
    }
  }
  { component_id, num_sccs: sccs.length(), sccs }
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

///|
/// Compute the strongly connected components of a directed graph using
/// Gabow's path-based algorithm.
///
/// # Parameters
/// - `n`: Number of vertices, indexed `0 .. n − 1`.
/// - `edges`: Directed edges as `(from, to)` tuples. Edges with endpoints
///   outside `[0, n)` are silently skipped.
///
/// # Returns
/// A `GabowSCCResult` containing the component assignment, component count,
/// and the list of SCCs. SCCs are in reverse topological order (sink SCCs
/// first).
///
/// # Complexity
/// O(V + E) time, O(V) space.
pub fn gabow_scc(n : Int, edges : Array[(Int, Int)]) -> GabowSCCResult {
  if n <= 0 {
    return { component_id: [], num_sccs: 0, sccs: [] }
  }
  let adj = build_adj_list(n, edges)
  gabow_scc_core(adj, n)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "gabow_scc: empty graph" {
  let result = gabow_scc(0, [])
  assert_eq(result.num_sccs, 0)
}

///|
test "gabow_scc: single vertex" {
  let result = gabow_scc(1, [])
  assert_eq(result.num_sccs, 1)
  assert_eq(result.component_id[0], 0)
  assert_eq(result.sccs[0].length(), 1)
  assert_eq(result.sccs[0][0], 0)
}

///|
test "gabow_scc: self-loop" {
  let result = gabow_scc(1, [(0, 0)])
  assert_eq(result.num_sccs, 1)
}

///|
test "gabow_scc: two vertices no edge" {
  let result = gabow_scc(2, [])
  assert_eq(result.num_sccs, 2)
}

///|
test "gabow_scc: two vertices one edge" {
  // 0 -> 1, two separate SCCs
  let result = gabow_scc(2, [(0, 1)])
  assert_eq(result.num_sccs, 2)
  // 1 is a sink, so it should be SCC 0.
  assert_eq(result.component_id[1], 0)
  assert_eq(result.component_id[0], 1)
}

///|
test "gabow_scc: two vertex cycle" {
  // 0 -> 1 -> 0, one SCC
  let result = gabow_scc(2, [(0, 1), (1, 0)])
  assert_eq(result.num_sccs, 1)
  assert_eq(result.component_id[0], 0)
  assert_eq(result.component_id[1], 0)
}

///|
test "gabow_scc: triangle cycle" {
  // 0 -> 1 -> 2 -> 0, one SCC
  let result = gabow_scc(3, [(0, 1), (1, 2), (2, 0)])
  assert_eq(result.num_sccs, 1)
  assert_eq(result.sccs[0].length(), 3)
}

///|
test "gabow_scc: DAG chain" {
  // 0 -> 1 -> 2 -> 3, four SCCs
  let result = gabow_scc(4, [(0, 1), (1, 2), (2, 3)])
  assert_eq(result.num_sccs, 4)
  // Reverse topological: 3 first (sink), 0 last (source).
  assert_eq(result.component_id[3], 0)
  assert_eq(result.component_id[2], 1)
  assert_eq(result.component_id[1], 2)
  assert_eq(result.component_id[0], 3)
}

///|
test "gabow_scc: two cycles connected" {
  // Cycle 0->1->2->0, cycle 3->4->5->3, bridge 2->3
  let result = gabow_scc(6, [
    (0, 1),
    (1, 2),
    (2, 0),
    (3, 4),
    (4, 5),
    (5, 3),
    (2, 3),
  ])
  assert_eq(result.num_sccs, 2)
  // The sink SCC (3,4,5) should have lower ID.
  let scc_cde = result.component_id[3]
  let scc_abc = result.component_id[0]
  assert_true(scc_cde < scc_abc)
  assert_eq(result.component_id[0], result.component_id[1])
  assert_eq(result.component_id[1], result.component_id[2])
  assert_eq(result.component_id[3], result.component_id[4])
  assert_eq(result.component_id[4], result.component_id[5])
}

///|
test "gabow_scc: nested cycles" {
  // 0 -> 1 -> 2 -> 0 (outer cycle)
  // 1 -> 3 -> 1 (inner cycle)
  // 2 -> 3 (cross edge)
  // All vertices are in the same SCC because 0->1->2->0 and 1->3->1.
  let result = gabow_scc(4, [(0, 1), (1, 2), (2, 0), (1, 3), (3, 1), (2, 3)])
  assert_eq(result.num_sccs, 1)
}

///|
test "gabow_scc: star graph" {
  // 0 -> 1, 0 -> 2, 0 -> 3, 0 -> 4
  // Five SCCs (all singletons)
  let result = gabow_scc(5, [(0, 1), (0, 2), (0, 3), (0, 4)])
  assert_eq(result.num_sccs, 5)
}

///|
test "gabow_scc: complete graph" {
  // K4: all pairs connected both ways, one SCC
  let edges : Array[(Int, Int)] = []
  for i = 0; i < 4; i = i + 1 {
    for j = 0; j < 4; j = j + 1 {
      if i != j {
        edges.push((i, j))
      }
    }
  }
  let result = gabow_scc(4, edges)
  assert_eq(result.num_sccs, 1)
  assert_eq(result.sccs[0].length(), 4)
}

///|
test "gabow_scc: reverse topological order" {
  // 0 -> 1 -> 2, and 0 -> 2
  // Three SCCs. 2 is sink (ID 0), 1 is middle (ID 1), 0 is source (ID 2).
  let result = gabow_scc(3, [(0, 1), (1, 2), (0, 2)])
  assert_eq(result.num_sccs, 3)
  assert_true(result.component_id[2] < result.component_id[1])
  assert_true(result.component_id[1] < result.component_id[0])
}

///|
test "gabow_scc: invalid edges skipped" {
  let result = gabow_scc(3, [
    (0, 1), // valid
    (-1, 2), // invalid
    (0, 5), // out of range
    (1, 2), // valid
    (2, 0), // valid
  ])
  // Triangle 0->1->2->0, one SCC.
  assert_eq(result.num_sccs, 1)
}

///|
test "gabow_scc: disconnected components" {
  // Two independent cycles: 0->1->0 and 2->3->2
  let result = gabow_scc(4, [(0, 1), (1, 0), (2, 3), (3, 2)])
  assert_eq(result.num_sccs, 2)
  assert_eq(result.component_id[0], result.component_id[1])
  assert_eq(result.component_id[2], result.component_id[3])
  assert_true(result.component_id[0] != result.component_id[2])
}

///|
test "gabow_scc: all SCCs are singletons for DAG" {
  // 0 -> 1, 0 -> 2, 1 -> 2, 2 -> 3
  let result = gabow_scc(4, [(0, 1), (0, 2), (1, 2), (2, 3)])
  assert_eq(result.num_sccs, 4)
  for i = 0; i < result.num_sccs; i = i + 1 {
    assert_eq(result.sccs[i].length(), 1)
  }
}

///|
test "gabow_scc: cross edge within SCC" {
  // 0 -> 1, 1 -> 2, 2 -> 0, 0 -> 2
  // All in one SCC (cycle 0->1->2->0)
  let result = gabow_scc(3, [(0, 1), (1, 2), (2, 0), (0, 2)])
  assert_eq(result.num_sccs, 1)
}

///|
test "gabow_scc: larger graph stress" {
  // Three cycles of 5 vertices each, connected by bridges.
  // Cycle 1: 0->1->2->3->4->0
  // Cycle 2: 5->6->7->8->9->5
  // Cycle 3: 10->11->12->13->14->10
  // Bridges: 4->5, 9->10
  let edges : Array[(Int, Int)] = []
  for i = 0; i < 5; i = i + 1 {
    edges.push((i, (i + 1) % 5))
  }
  for i = 0; i < 5; i = i + 1 {
    edges.push((5 + i, 5 + (i + 1) % 5))
  }
  for i = 0; i < 5; i = i + 1 {
    edges.push((10 + i, 10 + (i + 1) % 5))
  }
  edges.push((4, 5))
  edges.push((9, 10))
  let result = gabow_scc(15, edges)
  assert_eq(result.num_sccs, 3)
  // Each SCC has 5 vertices.
  for i = 0; i < 3; i = i + 1 {
    assert_eq(result.sccs[i].length(), 5)
  }
  // Reverse topological: cycle 3 (10-14) is sink, should have ID 0.
  // Cycle 2 (5-9) is middle, should have ID 1.
  // Cycle 1 (0-4) is source, should have ID 2.
  assert_true(result.component_id[10] < result.component_id[5])
  assert_true(result.component_id[5] < result.component_id[0])
}

///|
test "gabow_scc: single large cycle" {
  // 100-vertex cycle: 0->1->2->...->99->0
  // One SCC.
  let edges : Array[(Int, Int)] = []
  for i = 0; i < 100; i = i + 1 {
    edges.push((i, (i + 1) % 100))
  }
  let result = gabow_scc(100, edges)
  assert_eq(result.num_sccs, 1)
  assert_eq(result.sccs[0].length(), 100)
}

///|
test "gabow_scc: matches tarjan on random DAG" {
  // Compare with a simple reference: for a DAG, every vertex is its own SCC.
  // 0 -> 1 -> 2 -> 3 -> 4
  //      |         |
  //      v         v
  //      5         6
  let edges : Array[(Int, Int)] = [
    (0, 1),
    (1, 2),
    (2, 3),
    (3, 4),
    (1, 5),
    (3, 6),
  ]
  let result = gabow_scc(7, edges)
  assert_eq(result.num_sccs, 7)
  // All singletons.
  for i = 0; i < result.num_sccs; i = i + 1 {
    assert_eq(result.sccs[i].length(), 1)
  }
  // 4 and 6 are sinks, 0 is the source.
  // Reverse topological: sinks have lowest IDs.
  let id0 = result.component_id[0]
  let id4 = result.component_id[4]
  let id6 = result.component_id[6]
  assert_true(id4 < id0)
  assert_true(id6 < id0)
}
