/// Gomory-Hu Tree: all-pairs minimum cut in O(n) max-flow computations.
///
/// A Gomory-Hu tree of an undirected graph G = (V, E) is a weighted tree
/// T = (V, E_T) on the same vertex set such that:
///
///   1. For every pair (u, v), the minimum s-t cut value in G equals the
///      minimum edge weight on the unique path from u to v in T.
///   2. The two components of T obtained by removing the minimum-weight edge
///      on the u-v path give a minimum s-t cut in G.
///
/// This allows answering all-pairs min-cut queries in O(n) time per query
/// (tree path traversal) after O(n) max-flow precomputation, instead of
/// the naive O(n²) max-flow computations.
///
/// ## Algorithm
///
/// Uses the standard Gomory-Hu construction (Gomory and Hu, 1961):
///
///   1. Initialise a tree where every vertex v > 0 has `parent[v] = 0`.
///   2. For each vertex s = 1 .. n-1:
///      a. Let t = parent[s].
///      b. Compute max-flow f(s, t) in the original graph G.
///      c. Let S = set of vertices reachable from s in the residual graph.
///      d. Set `weight[s] = f(s, t)` (tree edge s -- parent[s]).
///      e. For every vertex v > s with parent[v] == t:
///         if v ∈ S, set parent[v] = s (re-parent v under s).
///   3. The tree is defined by parent[] and weight[] arrays.
///
/// ## Complexity
///
/// - Construction: O(n · MF(n, m)) where MF is the max-flow time.
///   With Edmonds-Karp (used here via `@max_flow`): O(n · V · E²).
/// - Query: O(n) per query (BFS/DFS on the tree).
/// - Space: O(n) for the tree + O(n²) for the flow graph copy.
///
/// ## Overflow safety
///
/// Flow values are returned as `Int64` from `@max_flow.max_flow`, preventing
/// overflow when total flow exceeds 32-bit range. Tree edge weights are
/// stored as `Int64`.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// A Gomory-Hu tree: a weighted tree on the same vertex set as the input
/// graph, where the minimum edge weight on the path between u and v equals
/// the min-cut value between u and v in the original graph.
pub struct GomoryHuTree {
  priv parent : FixedArray[Int] // parent[v] = tree parent of v (-1 for root)
  priv weight : FixedArray[Int64] // weight[v] = capacity of edge (v, parent[v])
  priv n : Int
}

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

/// Build the Gomory-Hu tree of an undirected graph.
///
/// # Parameters
/// - `graph`: `n × n` adjacency matrix. `graph[i * n + j]` is the capacity
///   of edge i → j. For an undirected graph, set both `graph[i*n+j]` and
///   `graph[j*n+i]` to the same capacity. A capacity of 0 means no edge.
/// - `n`: number of vertices, indexed `0 .. n - 1`.
///
/// # Returns
/// `Some(GomoryHuTree)` for valid inputs. Returns `None` for `n <= 0` or
/// `graph.length() < n * n`.
///
/// # Complexity
/// O(n · V · E²) using Edmonds-Karp for each of the n-1 max-flow calls.
pub fn build(
  graph : FixedArray[Int],
  n : Int,
) -> GomoryHuTree? {
  if n <= 0 || graph.length() < n * n {
    return None
  }
  // parent[v]: tree parent of v. Root is vertex 0 (parent = -1).
  // Initially, all vertices v >= 1 have parent[v] = 0.
  let parent = FixedArray::make(n, 0)
  parent[0] = -1
  // weight[v]: capacity of tree edge (v, parent[v]).
  let weight = FixedArray::make(n, 0L)
  // For each s = 1 .. n-1, compute max-flow(s, parent[s]) and update the tree.
  for s = 1; s < n; s = s + 1 {
    let t = parent[s]
    // Compute max flow from s to t. We use the original graph each time
    // (Gomory-Hu requires the original capacities, not a contracted graph
    // when using the Gusfield simplification, which avoids explicit graph
    // contraction).
    let flow = match @max_flow.max_flow(graph, n, s, t) {
      Some(f) => f
      None => 0L // Should not happen for valid s != t
    }
    weight[s] = flow
    // Find the min-cut: S = vertices reachable from s in the residual graph.
    // We need to re-run BFS on the residual to find S. Since max_flow doesn't
    // expose the residual, we recompute it here.
    // To avoid code duplication with max_flow, we re-derive the residual:
    // run max_flow's internal BFS logic ourselves.
    let s_side = find_reachable(graph, n, s, t)
    // Re-parent: for each v > s with parent[v] == t and v in S, set parent[v] = s.
    for v = s + 1; v < n; v = v + 1 {
      if parent[v] == t && s_side[v] {
        parent[v] = s
      }
    }
  }
  Some({ parent, weight, n })
}

/// After computing max-flow(s, t), find all vertices reachable from s in the
/// residual graph. These vertices form the "s side" of the min-cut.
///
/// We recompute the residual by running max-flow internally and tracking
/// the residual. To avoid modifying the caller's graph, we copy it.
fn find_reachable(
  graph : FixedArray[Int],
  n : Int,
  src : Int,
  sink : Int,
) -> FixedArray[Bool] {
  // Build the residual graph by copying original capacities.
  let residual = FixedArray::make(n * n, 0)
  for i = 0; i < n * n; i = i + 1 {
    residual[i] = graph[i]
  }
  // Run Edmonds-Karp to saturate the residual.
  let parent_arr = FixedArray::make(n, -1)
  let visited = FixedArray::make(n, false)
  let queue = FixedArray::make(n, 0)
  let int_max = 2147483647
  while bfs_path(residual, n, src, sink, parent_arr, visited, queue) {
    // Find bottleneck.
    let mut path_flow = int_max
    let mut v = sink
    while v != src {
      let u = parent_arr[v]
      let cap = residual[u * n + v]
      if cap < path_flow {
        path_flow = cap
      }
      v = u
    }
    // Augment.
    v = sink
    while v != src {
      let u = parent_arr[v]
      residual[u * n + v] = residual[u * n + v] - path_flow
      residual[v * n + u] = residual[v * n + u] + path_flow
      v = u
    }
  }
  // BFS from src in the residual to find reachable vertices.
  let reachable = FixedArray::make(n, false)
  let q2 = FixedArray::make(n, 0)
  let mut head = 0
  let mut tail = 0
  q2[tail] = src
  tail = tail + 1
  reachable[src] = true
  while head < tail {
    let u = q2[head]
    head = head + 1
    for v = 0; v < n; v = v + 1 {
      if !reachable[v] && residual[u * n + v] > 0 {
        reachable[v] = true
        q2[tail] = v
        tail = tail + 1
      }
    }
  }
  reachable
}

/// BFS augmenting path (same logic as max_flow's bfs_augmenting_path,
/// duplicated here to access the residual after augmentation).
fn bfs_path(
  residual : FixedArray[Int],
  n : Int,
  src : Int,
  sink : Int,
  parent : FixedArray[Int],
  visited : FixedArray[Bool],
  queue : FixedArray[Int],
) -> Bool {
  for i = 0; i < n; i = i + 1 {
    visited[i] = false
    parent[i] = -1
  }
  let mut head = 0
  let mut tail = 0
  queue[tail] = src
  tail = tail + 1
  visited[src] = true
  parent[src] = -1
  while head < tail {
    let u = queue[head]
    head = head + 1
    for v = 0; v < n; v = v + 1 {
      if !visited[v] && residual[u * n + v] > 0 {
        visited[v] = true
        parent[v] = u
        if v == sink {
          return true
        }
        queue[tail] = v
        tail = tail + 1
      }
    }
  }
  false
}

// ---------------------------------------------------------------------------
// Queries
// ---------------------------------------------------------------------------

/// Compute the minimum cut value between vertices `u` and `v`.
///
/// This traverses the tree path from `u` to `v` and returns the minimum
/// edge weight along that path, which equals the min-cut in the original
/// graph.
///
/// # Complexity
/// O(n) per query (BFS on the tree).
///
/// Returns `Int64::MAX` if u == v or either is out of bounds.
pub fn min_cut(tree : GomoryHuTree, u : Int, v : Int) -> Int64 {
  let n = tree.n
  if u < 0 || u >= n || v < 0 || v >= n || u == v {
    return 9223372036854775807L
  }
  // BFS from u to v on the tree, tracking the minimum edge weight.
  // Build adjacency list from parent/weight arrays.
  let adj_head = FixedArray::make(n, -1)
  let adj_to = FixedArray::make(2 * n, 0)
  let adj_w = FixedArray::make(2 * n, 0L)
  let adj_next = FixedArray::make(2 * n, 0)
  let mut edge_idx = 0
  for i = 1; i < n; i = i + 1 {
    let p = tree.parent[i]
    if p >= 0 {
      // Edge i -> p
      adj_to[edge_idx] = p
      adj_w[edge_idx] = tree.weight[i]
      adj_next[edge_idx] = adj_head[i]
      adj_head[i] = edge_idx
      edge_idx = edge_idx + 1
      // Edge p -> i
      adj_to[edge_idx] = i
      adj_w[edge_idx] = tree.weight[i]
      adj_next[edge_idx] = adj_head[p]
      adj_head[p] = edge_idx
      edge_idx = edge_idx + 1
    }
  }
  // BFS from u to find v, tracking minimum edge weight on the path.
  let visited = FixedArray::make(n, false)
  let min_w = FixedArray::make(n, 9223372036854775807L)
  let queue = FixedArray::make(n, 0)
  let mut head = 0
  let mut tail = 0
  queue[tail] = u
  tail = tail + 1
  visited[u] = true
  min_w[u] = 9223372036854775807L
  while head < tail {
    let cur = queue[head]
    head = head + 1
    if cur == v {
      return min_w[v]
    }
    let mut e = adj_head[cur]
    while e != -1 {
      let nxt = adj_to[e]
      if !visited[nxt] {
        visited[nxt] = true
        let w = if min_w[cur] < adj_w[e] { min_w[cur] } else { adj_w[e] }
        min_w[nxt] = w
        queue[tail] = nxt
        tail = tail + 1
      }
      e = adj_next[e]
    }
  }
  9223372036854775807L // v not reachable (shouldn't happen in a tree)
}

/// The parent of vertex `v` in the Gomory-Hu tree. Vertex 0 is the root
/// (parent = -1). For v >= 1, parent[v] is the tree parent.
pub fn parent_of(tree : GomoryHuTree, v : Int) -> Int {
  if v < 0 || v >= tree.n {
    return -1
  }
  tree.parent[v]
}

/// The weight of the tree edge between `v` and `parent(v)`.
pub fn edge_weight(tree : GomoryHuTree, v : Int) -> Int64 {
  if v < 0 || v >= tree.n {
    return 0L
  }
  tree.weight[v]
}

/// Number of vertices in the tree.
pub fn vertex_count(tree : GomoryHuTree) -> Int {
  tree.n
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "gomory_hu: triangle graph" {
  // Triangle: 0-1 (3), 1-2 (4), 0-2 (5)
  let n = 3
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 3; graph[1 * n + 0] = 3
  graph[1 * n + 2] = 4; graph[2 * n + 1] = 4
  graph[0 * n + 2] = 5; graph[2 * n + 0] = 5
  let tree = match build(graph, n) {
    Some(t) => t
    None => abort("expected tree")
  }
  // min-cut(0, 1) should be 3 (direct edge 0-1, or path 0-2-1 = min(5,4)=4)
  // Actually min-cut = min over all cuts. For triangle, min(0,1) cut = 3.
  // But in the tree, the path 0-1 gives the correct min-cut.
  // The exact value depends on tree structure. Let's verify correctness:
  // min-cut(0,1): separate {0} from {1,2} → cut edges 0-1(3) + 0-2(5) = 8
  //              or {0,2} from {1} → 0-1(3) + 2-1(4) = 7
  //              So min(0,1) = 7
  // min-cut(0,2): {0} from {1,2} → 0-1(3) + 0-2(5) = 8
  //              {0,1} from {2} → 0-2(5) + 1-2(4) = 9
  //              So min(0,2) = 8
  // min-cut(1,2): {1} from {0,2} → 1-0(3) + 1-2(4) = 7
  //              {0,1} from {2} → 0-2(5) + 1-2(4) = 9
  //              So min(1,2) = 7
  // Cross-check with direct max_flow
  let mc01 = min_cut(tree, 0, 1)
  let mc02 = min_cut(tree, 0, 2)
  let mc12 = min_cut(tree, 1, 2)
  // Verify against max_flow
  assert_eq(mc01, @max_flow.max_flow(graph, n, 0, 1).unwrap())
  assert_eq(mc02, @max_flow.max_flow(graph, n, 0, 2).unwrap())
  assert_eq(mc12, @max_flow.max_flow(graph, n, 1, 2).unwrap())
}

test "gomory_hu: path graph" {
  // Path: 0 - 1 - 2 - 3, each edge capacity 10
  let n = 4
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 10; graph[1 * n + 0] = 10
  graph[1 * n + 2] = 10; graph[2 * n + 1] = 10
  graph[2 * n + 3] = 10; graph[3 * n + 2] = 10
  let tree = match build(graph, n) {
    Some(t) => t
    None => abort("expected tree")
  }
  // On a path, min-cut(0, 3) = 10 (bottleneck edge)
  assert_eq(min_cut(tree, 0, 3), 10L)
  assert_eq(min_cut(tree, 0, 2), 10L)
  assert_eq(min_cut(tree, 1, 3), 10L)
  assert_eq(min_cut(tree, 0, 1), 10L)
  // Cross-check with max_flow
  for u = 0; u < n; u = u + 1 {
    for v = u + 1; v < n; v = v + 1 {
      let expected = @max_flow.max_flow(graph, n, u, v).unwrap()
      assert_eq(min_cut(tree, u, v), expected)
    }
  }
}

test "gomory_hu: star graph" {
  // Star: center 0, leaves 1,2,3. Each edge capacity 5.
  let n = 4
  let graph = FixedArray::make(n * n, 0)
  for i = 1; i < n; i = i + 1 {
    graph[0 * n + i] = 5
    graph[i * n + 0] = 5
  }
  let tree = match build(graph, n) {
    Some(t) => t
    None => abort("expected tree")
  }
  // min-cut between two leaves = 5 (cutting either edge to center suffices)
  assert_eq(min_cut(tree, 1, 2), 5L)
  assert_eq(min_cut(tree, 1, 3), 5L)
  assert_eq(min_cut(tree, 2, 3), 5L)
  // min-cut from center to any leaf = 5
  assert_eq(min_cut(tree, 0, 1), 5L)
  // Cross-check
  for u = 0; u < n; u = u + 1 {
    for v = u + 1; v < n; v = v + 1 {
      let expected = @max_flow.max_flow(graph, n, u, v).unwrap()
      assert_eq(min_cut(tree, u, v), expected)
    }
  }
}

test "gomory_hu: complete graph K4" {
  // K4: all edges capacity 1
  let n = 4
  let graph = FixedArray::make(n * n, 0)
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      if i != j {
        graph[i * n + j] = 1
      }
    }
  }
  let tree = match build(graph, n) {
    Some(t) => t
    None => abort("expected tree")
  }
  // In K4, min-cut(u, v) = 3 (isolating one vertex cuts 3 edges)
  for u = 0; u < n; u = u + 1 {
    for v = u + 1; v < n; v = v + 1 {
      assert_eq(min_cut(tree, u, v), 3L)
    }
  }
}

test "gomory_hu: disconnected graph" {
  // Two components: {0, 1} and {2, 3}
  let n = 4
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 5; graph[1 * n + 0] = 5
  graph[2 * n + 3] = 3; graph[3 * n + 2] = 3
  let tree = match build(graph, n) {
    Some(t) => t
    None => abort("expected tree")
  }
  // Within component: correct min-cut
  assert_eq(min_cut(tree, 0, 1), 5L)
  assert_eq(min_cut(tree, 2, 3), 3L)
  // Across components: 0 (disconnected, no flow)
  assert_eq(min_cut(tree, 0, 2), 0L)
  assert_eq(min_cut(tree, 1, 3), 0L)
}

test "gomory_hu: single vertex" {
  let graph = FixedArray::make(1, 0)
  let tree = match build(graph, 1) {
    Some(t) => t
    None => abort("expected tree")
  }
  assert_eq(vertex_count(tree), 1)
  assert_eq(parent_of(tree, 0), -1)
}

test "gomory_hu: two vertices" {
  let n = 2
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 7; graph[1 * n + 0] = 7
  let tree = match build(graph, n) {
    Some(t) => t
    None => abort("expected tree")
  }
  assert_eq(min_cut(tree, 0, 1), 7L)
  assert_eq(parent_of(tree, 1), 0)
  assert_eq(edge_weight(tree, 1), 7L)
}

test "gomory_hu: cross-check with max_flow on random graph" {
  // 6-vertex graph with pseudo-random capacities.
  let n = 6
  let graph = FixedArray::make(n * n, 0)
  let mut st = 42
  for i = 0; i < n; i = i + 1 {
    for j = i + 1; j < n; j = j + 1 {
      st = (st * 31 + 7) % 1000
      let cap = st % 10 + 1
      graph[i * n + j] = cap
      graph[j * n + i] = cap
    }
  }
  let tree = match build(graph, n) {
    Some(t) => t
    None => abort("expected tree")
  }
  // Verify all pairs against max_flow.
  for u = 0; u < n; u = u + 1 {
    for v = u + 1; v < n; v = v + 1 {
      let expected = @max_flow.max_flow(graph, n, u, v).unwrap()
      let actual = min_cut(tree, u, v)
      assert_eq(actual, expected)
    }
  }
}

test "gomory_hu: invalid inputs" {
  assert_true(build(FixedArray::make(0, 0), 0) is None)
  assert_true(build(FixedArray::make(2, 0), 2) is None) // too small
}
