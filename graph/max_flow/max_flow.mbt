/// Maximum flow using the Edmonds-Karp algorithm (BFS-based Ford-Fulkerson).
///
/// Uses an adjacency matrix representation: `graph[i * n + j]` is the
/// capacity of the directed edge from `i` to `j`. A capacity of 0 means
/// no edge exists. The graph is treated as directed; for undirected flow
/// networks, add edges in both directions.
///
/// Edmonds-Karp is Ford-Fulkerson with BFS to find augmenting paths.
/// This guarantees O(VE²) time complexity regardless of capacity magnitudes,
/// avoiding the potential pseudo-polynomial blowup of naive Ford-Fulkerson
/// with DFS.
///
/// Returns `Some(flow)` for valid inputs, or `None` for invalid inputs
/// (n <= 0, out-of-bounds vertices, src == sink, negative capacities, or
/// graph array too small). Returning `Option` distinguishes invalid input
/// from a valid flow of 0 (which occurs when no augmenting path exists).
///
/// `total_flow` is accumulated in `Int64` to prevent overflow: the sum of all
/// augmenting path flows can exceed `Int::max_value` (2³¹−1) in networks with
/// many high-capacity edges. Individual edge capacities remain `Int` (bounded
/// by `Int::max_value`), but their sum uses 64-bit arithmetic.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.
///
/// Time complexity: O(VE²)

///|
/// BFS to find an augmenting path from `src` to `sink` in the residual graph.
///
/// `residual` is an `n × n` matrix of residual capacities.
/// `parent` is filled with the predecessor of each vertex on the path
/// (-1 for unreached vertices). Returns `true` if `sink` is reachable.
fn bfs_augmenting_path(
  residual : FixedArray[Int],
  n : Int,
  src : Int,
  sink : Int,
  parent : FixedArray[Int],
) -> Bool {
  let visited = FixedArray::make(n, false)
  // Simple index-based BFS queue (avoids Array::shift overhead).
  let queue = FixedArray::make(n, 0)
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

///|
/// Compute the maximum flow from `src` to `sink` in a flow network.
///
/// `graph` is an `n × n` adjacency matrix where `graph[i * n + j]` is the
/// capacity of the edge `i → j`. Capacity 0 means no edge.
///
/// Returns `Some(flow)` for valid inputs, where `flow` is the maximum flow
/// value as `Int64`. A valid flow of `0L` means the source and sink are
/// disconnected (no augmenting path exists).
///
/// Returns `None` for invalid inputs: `n <= 0`, out-of-bounds `src` or
/// `sink`, `src == sink`, `graph.length() < n * n`, or any negative capacity
/// in the graph.
///
/// `total_flow` is accumulated in `Int64` to prevent overflow when the sum
/// of augmenting path flows exceeds 32-bit `Int` range.
pub fn max_flow(
  graph : FixedArray[Int],
  n : Int,
  src : Int,
  sink : Int,
) -> Int64? {
  if n <= 0 || src < 0 || src >= n || sink < 0 || sink >= n || src == sink {
    return None
  }
  if graph.length() < n * n {
    return None
  }
  // Input validation: capacities must be non-negative. A negative entry is an
  // input error that breaks the augmenting-path invariant (`residual > 0`),
  // which could yield an incorrect (or non-terminating-looking) flow. Return
  // None to clearly signal invalid input (distinct from Some(0L) which means
  // a valid graph with no augmenting path).
  for i = 0; i < n * n; i = i + 1 {
    if graph[i] < 0 {
      return None
    }
  }
  // Copy capacities into the residual graph (original capacities are
  // consumed during augmentation; we must not mutate the caller's array).
  let residual = FixedArray::make(n * n, 0)
  for i = 0; i < n * n; i = i + 1 {
    residual[i] = graph[i]
  }
  let parent = FixedArray::make(n, -1)
  let mut total_flow = 0L
  // Repeatedly find the shortest augmenting path (BFS) and push flow.
  while bfs_augmenting_path(residual, n, src, sink, parent) {
    // Find the bottleneck (minimum residual capacity) along the path.
    // `@int.MAX_VALUE` acts as the sentinel "infinity": it is larger than any
    // real residual capacity, so the first edge clamps `path_flow` to a
    // genuine capacity value.
    let mut path_flow = @int.MAX_VALUE
    let mut v = sink
    while v != src {
      let u = parent[v]
      let cap = residual[u * n + v]
      if cap < path_flow {
        path_flow = cap
      }
      v = u
    }
    // Update residual capacities along the path:
    //   - Forward edge: decrease by path_flow (capacity consumed)
    //   - Reverse edge: increase by path_flow (flow can be "undone")
    v = sink
    while v != src {
      let u = parent[v]
      residual[u * n + v] = residual[u * n + v] - path_flow
      residual[v * n + u] = residual[v * n + u] + path_flow
      v = u
    }
    total_flow = total_flow + path_flow.to_int64()
  }
  Some(total_flow)
}

// ---------------------------------------------------------------------------
// Adjacency-list based max flow (O(V+E) space, efficient for sparse graphs)
// ---------------------------------------------------------------------------

///|
/// A directed edge in a flow network with residual capacity tracking.
///
/// Each edge stores its destination vertex, current residual capacity,
/// and the index of its reverse edge in the destination's adjacency list.
/// The reverse edge allows flow to be "undone" during augmentation.
priv struct FlowEdge {
  to : Int // destination vertex
  mut cap : Int // residual capacity (mutated during augmentation)
  rev : Int // index of reverse edge in adj[to]
}

///|
/// A flow network using adjacency-list representation.
///
/// Uses O(V + E) space instead of O(V²) for the matrix-based API.
/// Efficient for sparse graphs where E ≪ V².
pub struct FlowGraph {
  priv adj : Array[Array[FlowEdge]] // adj[u] = edges from u
  priv n : Int // number of vertices
}

///|
/// Create an empty flow graph with `n` vertices.
///
/// Each vertex gets its own independent adjacency list. Using
/// `Array::make(n, [])` would share a single array among all vertices
/// (reference type aliasing), so we push separate empty arrays.
pub fn flow_graph(n : Int) -> FlowGraph {
  let adj : Array[Array[FlowEdge]] = []
  for _ in 0..<n {
    adj.push([])
  }
  { adj, n }
}

///|
/// Add a directed edge `from → to` with the given capacity.
///
/// Automatically creates a reverse edge `to → from` with capacity 0
/// (needed for residual graph augmentation). The reverse edge's `rev`
/// field points back to this edge, and vice versa.
///
/// For undirected flow networks, call this once per direction.
pub fn add_edge(graph : FlowGraph, from : Int, to : Int, cap : Int) -> Unit {
  if from < 0 || from >= graph.n || to < 0 || to >= graph.n || from == to {
    return
  }
  // Forward edge: capacity = cap, rev points to the reverse edge in adj[to].
  let fwd = { to, cap, rev: graph.adj[to].length() }
  // Reverse edge: capacity = 0 (no initial flow), rev points to fwd in adj[from].
  let rev = { to: from, cap: 0, rev: graph.adj[from].length() }
  graph.adj[from].push(fwd)
  graph.adj[to].push(rev)
}

///|
/// BFS to find an augmenting path in an adjacency-list residual graph.
///
/// Fills `parent_edge` with (vertex, edge_index) pairs so we can trace
/// the path and update residual capacities. Returns true if sink is reachable.
fn bfs_adj_list(
  graph : FlowGraph,
  src : Int,
  sink : Int,
  parent_v : FixedArray[Int],
  parent_e : FixedArray[Int],
) -> Bool {
  let n = graph.n
  let visited = FixedArray::make(n, false)
  let queue = FixedArray::make(n, 0)
  let mut head = 0
  let mut tail = 0
  queue[tail] = src
  tail = tail + 1
  visited[src] = true
  parent_v[src] = -1
  while head < tail {
    let u = queue[head]
    head = head + 1
    let edges = graph.adj[u]
    for i = 0; i < edges.length(); i = i + 1 {
      let e = edges[i]
      if !visited[e.to] && e.cap > 0 {
        visited[e.to] = true
        parent_v[e.to] = u
        parent_e[e.to] = i
        if e.to == sink {
          return true
        }
        queue[tail] = e.to
        tail = tail + 1
      }
    }
  }
  false
}

///|
/// Compute the maximum flow using an adjacency-list graph.
///
/// This is the recommended API for sparse graphs: it uses O(V + E) space
/// instead of O(V²) for the matrix-based `max_flow` function, and BFS
/// iterates only over actual edges rather than all V vertices.
///
/// - `graph`: A `FlowGraph` built with `flow_graph` and `add_edge`.
/// - `src`: Source vertex.
/// - `sink`: Sink vertex.
///
/// Returns `Some(flow)` as `Int64`, or `None` for invalid inputs
/// (n <= 0, out-of-bounds, src == sink).
///
/// Time complexity: O(VE²) — same Edmonds-Karp algorithm, but with
/// better constant factors on sparse graphs.
pub fn max_flow_adj_list(graph : FlowGraph, src : Int, sink : Int) -> Int64? {
  let n = graph.n
  if n <= 0 || src < 0 || src >= n || sink < 0 || sink >= n || src == sink {
    return None
  }
  // Validate no negative capacities.
  for u = 0; u < n; u = u + 1 {
    for e in graph.adj[u] {
      if e.cap < 0 {
        return None
      }
    }
  }
  let parent_v = FixedArray::make(n, -1)
  let parent_e = FixedArray::make(n, -1)
  let mut total_flow = 0L
  while bfs_adj_list(graph, src, sink, parent_v, parent_e) {
    // Find bottleneck along the path.
    // NOTE: Must read cap through array indexing, not a local copy,
    // because FlowEdge is a value type (struct) — a local variable
    // would be a copy and mutations would not propagate back.
    let mut path_flow = @int.MAX_VALUE
    let mut v = sink
    while v != src {
      let u = parent_v[v]
      let cap = graph.adj[u][parent_e[v]].cap
      if cap < path_flow {
        path_flow = cap
      }
      v = u
    }
    // Update residual capacities along the path.
    // Direct array indexing ensures mutations persist (struct is value type).
    v = sink
    while v != src {
      let u = parent_v[v]
      let edge_idx = parent_e[v]
      let rev_idx = graph.adj[u][edge_idx].rev
      graph.adj[u][edge_idx].cap = graph.adj[u][edge_idx].cap - path_flow
      graph.adj[v][rev_idx].cap = graph.adj[v][rev_idx].cap + path_flow
      v = u
    }
    total_flow = total_flow + path_flow.to_int64()
  }
  Some(total_flow)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "max_flow: simple chain" {
  // 0 -> 1 -> 2 -> 3, each with capacity 10
  let n = 4
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 10
  graph[1 * n + 2] = 10
  graph[2 * n + 3] = 10
  assert_eq(max_flow(graph, n, 0, 3), Some(10L))
}

///|
test "max_flow: two parallel paths" {
  // 0 -> 1 (10), 0 -> 2 (5), 1 -> 3 (5), 2 -> 3 (10)
  // Max flow = 5 + 5 = 10
  let n = 4
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 10
  graph[0 * n + 2] = 5
  graph[1 * n + 3] = 5
  graph[2 * n + 3] = 10
  assert_eq(max_flow(graph, n, 0, 3), Some(10L))
}

///|
test "max_flow: bottleneck" {
  // 0 -> 1 (20), 1 -> 2 (5), 2 -> 3 (20)
  // Bottleneck is 1->2 with capacity 5
  let n = 4
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 20
  graph[1 * n + 2] = 5
  graph[2 * n + 3] = 20
  assert_eq(max_flow(graph, n, 0, 3), Some(5L))
}

///|
test "max_flow: no path" {
  // 0 and 3 are disconnected; valid graph but max flow is 0.
  // This is distinct from invalid input (which returns None).
  let n = 4
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 10
  graph[2 * n + 3] = 10
  assert_eq(max_flow(graph, n, 0, 3), Some(0L))
}

///|
test "max_flow: negative capacity returns None" {
  // Negative capacities are an invalid input. Return None to signal the
  // error, distinct from Some(0L) which means a valid graph with no path.
  let n = 3
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = -5
  graph[1 * n + 2] = 10
  assert_true(max_flow(graph, n, 0, 2) is None)
  // A single negative entry anywhere is enough to reject the whole input.
  let graph2 = FixedArray::make(n * n, 0)
  graph2[0 * n + 1] = 10
  graph2[1 * n + 2] = 10
  graph2[2 * n + 0] = -1
  assert_true(max_flow(graph2, n, 0, 2) is None)
}

///|
test "max_flow: single edge" {
  let n = 2
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 7
  assert_eq(max_flow(graph, n, 0, 1), Some(7L))
}

///|
test "max_flow: classic CLRS example" {
  // CLRS Figure 26.1: s=0, t=5
  // Edges: s->1(16), s->2(13), 1->3(12), 2->1(4), 2->4(14),
  //        3->2(9), 3->t(20), 4->3(7), 4->t(4)
  let n = 6
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 16
  graph[0 * n + 2] = 13
  graph[1 * n + 3] = 12
  graph[2 * n + 1] = 4
  graph[2 * n + 4] = 14
  graph[3 * n + 2] = 9
  graph[3 * n + 5] = 20
  graph[4 * n + 3] = 7
  graph[4 * n + 5] = 4
  assert_eq(max_flow(graph, n, 0, 5), Some(23L))
}

///|
test "max_flow: undirected graph (bidirectional edges)" {
  // 0 <-> 1 <-> 2, each direction capacity 10
  let n = 3
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 10
  graph[1 * n + 0] = 10
  graph[1 * n + 2] = 10
  graph[2 * n + 1] = 10
  assert_eq(max_flow(graph, n, 0, 2), Some(10L))
}

///|
test "max_flow: self-loop ignored" {
  let n = 3
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 0] = 100 // self-loop, should be ignored
  graph[0 * n + 1] = 10
  graph[1 * n + 2] = 10
  assert_eq(max_flow(graph, n, 0, 2), Some(10L))
}

///|
test "max_flow: adding edge increases flow" {
  // 0 -> 1 (10), 1 -> 3 (5), 0 -> 2 (5), 2 -> 3 (10)
  // Without cross edge: max flow = 10 (5 via 0->1->3, 5 via 0->2->3)
  let n = 4
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 10
  graph[1 * n + 3] = 5
  graph[0 * n + 2] = 5
  graph[2 * n + 3] = 10
  assert_eq(max_flow(graph, n, 0, 3), Some(10L))
  // Add cross edge 1 -> 2 (5): now 0->1->2->3 carries additional 5
  // Total: 0->1->3 (5) + 0->1->2->3 (5) + 0->2->3 (5) = 15
  graph[1 * n + 2] = 5
  assert_eq(max_flow(graph, n, 0, 3), Some(15L))
}

///|
test "max_flow: invalid inputs return None" {
  let n = 3
  let graph = FixedArray::make(n * n, 0)
  assert_true(max_flow(graph, 0, 0, 2) is None) // n = 0
  assert_true(max_flow(graph, n, -1, 2) is None) // src < 0
  assert_true(max_flow(graph, n, 3, 2) is None) // src >= n
  assert_true(max_flow(graph, n, 0, -1) is None) // sink < 0
  assert_true(max_flow(graph, n, 0, 3) is None) // sink >= n
  assert_true(max_flow(graph, n, 1, 1) is None) // src == sink
  // graph too small for n
  assert_true(max_flow(FixedArray::make(4, 0), n, 0, 2) is None)
}

///|
test "max_flow: large chain 100 nodes" {
  let n = 100
  let graph = FixedArray::make(n * n, 0)
  for i = 0; i < n - 1; i = i + 1 {
    graph[i * n + (i + 1)] = 10
  }
  assert_eq(max_flow(graph, n, 0, n - 1), Some(10L))
}

///|
test "max_flow: capacity not mutated" {
  let n = 3
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 5
  graph[1 * n + 2] = 5
  let _ = max_flow(graph, n, 0, 2)
  // Original capacities should be unchanged
  assert_eq(graph[0 * n + 1], 5)
  assert_eq(graph[1 * n + 2], 5)
  assert_eq(graph[1 * n + 0], 0) // reverse edge was 0
}

///|
test "max_flow_adj_list: simple chain" {
  let g = flow_graph(4)
  add_edge(g, 0, 1, 10)
  add_edge(g, 1, 2, 10)
  add_edge(g, 2, 3, 10)
  assert_eq(max_flow_adj_list(g, 0, 3), Some(10L))
}

///|
test "max_flow_adj_list: CLRS example" {
  let g = flow_graph(6)
  add_edge(g, 0, 1, 16)
  add_edge(g, 0, 2, 13)
  add_edge(g, 1, 3, 12)
  add_edge(g, 2, 1, 4)
  add_edge(g, 2, 4, 14)
  add_edge(g, 3, 2, 9)
  add_edge(g, 3, 5, 20)
  add_edge(g, 4, 3, 7)
  add_edge(g, 4, 5, 4)
  assert_eq(max_flow_adj_list(g, 0, 5), Some(23L))
}

///|
test "max_flow_adj_list: no path" {
  let g = flow_graph(4)
  add_edge(g, 0, 1, 10)
  add_edge(g, 2, 3, 10)
  assert_eq(max_flow_adj_list(g, 0, 3), Some(0L))
}

///|
test "max_flow_adj_list: invalid inputs" {
  let g = flow_graph(3)
  add_edge(g, 0, 1, 10)
  add_edge(g, 1, 2, 10)
  assert_true(max_flow_adj_list(g, -1, 2) is None)
  assert_true(max_flow_adj_list(g, 3, 2) is None)
  assert_true(max_flow_adj_list(g, 1, 1) is None)
}

///|
test "max_flow_adj_list: sparse graph 200 nodes" {
  // A sparse chain of 200 nodes — would need 40K entries in matrix form
  // but only 200 edges in adjacency-list form.
  let n = 200
  let g = flow_graph(n)
  for i = 0; i < n - 1; i = i + 1 {
    add_edge(g, i, i + 1, 10)
  }
  assert_eq(max_flow_adj_list(g, 0, n - 1), Some(10L))
}

///|
test "max_flow_adj_list: parallel paths" {
  let g = flow_graph(4)
  add_edge(g, 0, 1, 10)
  add_edge(g, 0, 2, 5)
  add_edge(g, 1, 3, 5)
  add_edge(g, 2, 3, 10)
  assert_eq(max_flow_adj_list(g, 0, 3), Some(10L))
}
