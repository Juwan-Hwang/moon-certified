/// Maximum flow using Dinic's algorithm.
///
/// Given a directed flow network with capacities on edges, finds the maximum
/// flow from `src` to `sink`. Dinic's algorithm improves on Edmonds-Karp by
/// building a *level graph* (via BFS) in each phase and finding a *blocking
/// flow* (via DFS) — the maximum flow after which no augmenting path exists
/// in the current level graph.
///
/// ## Algorithm
///
///   1. Build the graph using a linked-forward-star (chain-based edge list).
///      Each edge `(u, v, cap)` adds a forward edge with residual capacity
///      `cap` and a reverse edge with capacity 0. Edges are stored in pairs:
///      edge `i` (forward) and edge `i^1` (reverse), so toggling the lowest
///      bit gives the partner.
///   2. **BFS phase**: compute `level[v]` = shortest distance (in hops) from
///      `src` to `v` in the residual graph. If `sink` is unreachable, stop.
///   3. **DFS phase**: find a blocking flow using DFS that only traverses
///      edges `(u, v)` where `level[v] == level[u] + 1`. The *current-arc
///      optimization* (`cur[]` array) ensures each edge is examined at most
///      once per phase, giving O(E) work per phase.
///   4. Repeat BFS + DFS until `sink` is unreachable.
///
/// ## Complexity
///
/// - O(V²E) for general graphs.
/// - O(E·√V) for unit-capacity networks (e.g., bipartite matching).
/// - Space: O(V + E) via the linked-forward-star representation.
///
/// ## Overflow safety
///
/// All capacities and flow accumulation use `Int64`, supporting total flows
/// up to 2⁶³ − 1. This avoids the overflow risk of 32-bit `Int` accumulation
/// present in the `max_flow` (Edmonds-Karp) package.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.
///
/// ## Limitations
///
/// - Self-loops (`u == v`) and non-positive capacities are silently ignored.
/// - The DFS is recursive; extremely deep level graphs (depth > ~10⁴) may
///   cause stack overflow. For such cases, an iterative DFS is preferable.

/// Sentinel representing "infinite capacity" for the initial DFS flow bound.
/// Using `Int64::max_value` means the flow is bounded only by actual edge
/// capacities. Total flow accumulation cannot overflow `Int64` as long as
/// the sum of all capacities fits in `Int64`.
let int64_max : Int64 = 9223372036854775807L

/// A directed edge in the residual graph (linked-forward-star representation).
///
/// `next` links to the next edge originating from the same vertex, forming
/// a singly-linked list. Edges are stored in pairs: edge `i` (forward) and
/// edge `i^1` (reverse), so toggling the lowest bit gives the partner.
priv struct Edge {
  to : Int
  mut cap : Int64 // residual capacity on this edge
  next : Int // index of next edge from the same `from` vertex, -1 = none
}

/// The flow network, built from an edge list.
priv struct DinicGraph {
  n : Int
  head : Array[Int] // head[v] = first edge index from v, -1 = none
  edges : Array[Edge] // all edges (forward + reverse interleaved)
  mut edge_count : Int // total edges added so far
}

/// Build the residual graph from an edge list.
///
/// For each valid edge `(u, v, cap)`, adds a forward edge (capacity `cap`)
/// and a reverse edge (capacity 0). Invalid edges (out-of-bounds vertices,
/// self-loops, non-positive capacity) are silently skipped.
fn build_graph(n : Int, edge_list : Array[(Int, Int, Int64)]) -> DinicGraph {
  let g : DinicGraph = {
    n,
    head: Array::make(n, -1),
    edges: [],
    edge_count: 0,
  }
  for k = 0; k < edge_list.length(); k = k + 1 {
    let (u, v, cap) = edge_list[k]
    if u < 0 || u >= n || v < 0 || v >= n || u == v || cap <= 0L {
      continue
    }
    // Forward edge: capacity `cap`, linked to the current head of u's list.
    g.edges.push({ to: v, cap, next: g.head[u] })
    g.head[u] = g.edge_count
    g.edge_count = g.edge_count + 1
    // Reverse edge: capacity 0, linked to the current head of v's list.
    g.edges.push({ to: u, cap: 0L, next: g.head[v] })
    g.head[v] = g.edge_count
    g.edge_count = g.edge_count + 1
  }
  g
}

/// BFS to build the level graph.
///
/// Computes `level[v]` = shortest hop-distance from `src` to `v` in the
/// residual graph (edges with positive residual capacity only). Unreachable
/// vertices get level -1. Returns `true` if `sink` is reachable.
fn bfs(
  g : DinicGraph,
  src : Int,
  sink : Int,
  level : FixedArray[Int],
) -> Bool {
  for i = 0; i < g.n; i = i + 1 {
    level[i] = -1
  }
  // Index-based BFS queue (avoids Array::shift overhead).
  let queue = FixedArray::make(g.n, 0)
  let mut head = 0
  let mut tail = 0
  queue[tail] = src
  tail = tail + 1
  level[src] = 0
  while head < tail {
    let u = queue[head]
    head = head + 1
    let mut e_idx = g.head[u]
    while e_idx != -1 {
      let e = g.edges[e_idx]
      if level[e.to] < 0 && e.cap > 0L {
        level[e.to] = level[u] + 1
        queue[tail] = e.to
        tail = tail + 1
      }
      e_idx = e.next
    }
  }
  level[sink] >= 0
}

/// Minimum of two `Int64` values.
fn min64(a : Int64, b : Int64) -> Int64 {
  if a < b { a } else { b }
}

/// DFS to find blocking flow in the level graph, with current-arc optimization.
///
/// Attempts to push at most `flow` units from `u` toward `sink`, using only
/// edges `(u, v)` where `level[v] == level[u] + 1`. Returns the amount
/// actually pushed.
///
/// The `cur` array tracks the next edge to try for each vertex. Once an edge
/// is exhausted (capacity 0) or leads to a dead end, `cur[u]` advances past
/// it, so it is never re-examined within the same phase. This guarantees
/// O(E) total edge examinations per phase.
fn dfs(
  g : DinicGraph,
  u : Int,
  sink : Int,
  flow : Int64,
  level : FixedArray[Int],
  cur : FixedArray[Int],
) -> Int64 {
  if u == sink {
    return flow
  }
  let mut pushed = 0L
  let mut e_idx = cur[u]
  while e_idx != -1 {
    let e = g.edges[e_idx]
    if level[e.to] == level[u] + 1 && e.cap > 0L {
      let tr = dfs(g, e.to, sink, min64(flow - pushed, e.cap), level, cur)
      if tr > 0L {
        g.edges[e_idx].cap = g.edges[e_idx].cap - tr
        g.edges[e_idx ^ 1].cap = g.edges[e_idx ^ 1].cap + tr
        pushed = pushed + tr
        if pushed == flow {
          // The current edge may still have remaining capacity; keep it as
          // the starting point for the next DFS call in this phase.
          cur[u] = e_idx
          return pushed
        }
      }
    }
    // Edge exhausted, dead end, or downstream saturated: advance.
    e_idx = e.next
    cur[u] = e_idx
  }
  pushed
}

/// Compute the maximum flow from `src` to `sink` in a flow network.
///
/// # Parameters
/// - `n`: number of vertices, indexed `0 .. n - 1`.
/// - `src`: source vertex.
/// - `sink`: sink (target) vertex.
/// - `edges`: list of `(from, to, capacity)` tuples. Each edge is directed.
///   For undirected flow, add edges in both directions.
///
/// # Returns
/// The maximum flow value as `Int64`. Returns `0L` for invalid inputs
/// (n <= 0, out-of-bounds vertices, `src == sink`).
///
/// **Overflow safety**: all capacities and flow accumulation use `Int64`,
/// supporting total flows up to 2⁶³ − 1.
pub fn max_flow(
  n : Int,
  src : Int,
  sink : Int,
  edges : Array[(Int, Int, Int64)],
) -> Int64 {
  if n <= 0 || src < 0 || src >= n || sink < 0 || sink >= n || src == sink {
    return 0L
  }
  let g = build_graph(n, edges)
  let level = FixedArray::make(n, 0)
  let cur = FixedArray::make(n, 0)
  let mut total_flow = 0L
  while bfs(g, src, sink, level) {
    // Reset current-arc pointers to the head of each adjacency list.
    for i = 0; i < n; i = i + 1 {
      cur[i] = g.head[i]
    }
    // Repeatedly find augmenting flows in the level graph until the
    // blocking flow is exhausted (DFS returns 0).
    let mut pushed = dfs(g, src, sink, int64_max, level, cur)
    while pushed > 0L {
      total_flow = total_flow + pushed
      pushed = dfs(g, src, sink, int64_max, level, cur)
    }
  }
  total_flow
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "dinic: simple chain" {
  // 0 -> 1 -> 2 -> 3, each with capacity 10
  let edges = [(0, 1, 10L), (1, 2, 10L), (2, 3, 10L)]
  assert_eq(max_flow(4, 0, 3, edges), 10L)
}

test "dinic: two parallel paths" {
  // 0 -> 1 (10), 0 -> 2 (5), 1 -> 3 (5), 2 -> 3 (10)
  // Max flow = 5 + 5 = 10
  let edges = [(0, 1, 10L), (0, 2, 5L), (1, 3, 5L), (2, 3, 10L)]
  assert_eq(max_flow(4, 0, 3, edges), 10L)
}

test "dinic: bottleneck" {
  // 0 -> 1 (20), 1 -> 2 (5), 2 -> 3 (20)
  // Bottleneck is 1->2 with capacity 5
  let edges = [(0, 1, 20L), (1, 2, 5L), (2, 3, 20L)]
  assert_eq(max_flow(4, 0, 3, edges), 5L)
}

test "dinic: no path" {
  // 0 and 3 are disconnected
  let edges = [(0, 1, 10L), (2, 3, 10L)]
  assert_eq(max_flow(4, 0, 3, edges), 0L)
}

test "dinic: single edge" {
  let edges = [(0, 1, 7L)]
  assert_eq(max_flow(2, 0, 1, edges), 7L)
}

test "dinic: classic CLRS example" {
  // CLRS Figure 26.1: s=0, t=5
  // Edges: s->1(16), s->2(13), 1->3(12), 2->1(4), 2->4(14),
  //        3->2(9), 3->t(20), 4->3(7), 4->t(4)
  let edges = [
    (0, 1, 16L),
    (0, 2, 13L),
    (1, 3, 12L),
    (2, 1, 4L),
    (2, 4, 14L),
    (3, 2, 9L),
    (3, 5, 20L),
    (4, 3, 7L),
    (4, 5, 4L),
  ]
  assert_eq(max_flow(6, 0, 5, edges), 23L)
}

test "dinic: undirected graph (bidirectional edges)" {
  // 0 <-> 1 <-> 2, each direction capacity 10
  let edges = [
    (0, 1, 10L),
    (1, 0, 10L),
    (1, 2, 10L),
    (2, 1, 10L),
  ]
  assert_eq(max_flow(3, 0, 2, edges), 10L)
}

test "dinic: self-loop ignored" {
  let edges = [
    (0, 0, 100L), // self-loop, should be ignored
    (0, 1, 10L),
    (1, 2, 10L),
  ]
  assert_eq(max_flow(3, 0, 2, edges), 10L)
}

test "dinic: parallel edges" {
  // Two edges from 0 to 1 with capacities 3 and 7.
  // Total capacity from 0 to 1 = 10.
  let edges = [(0, 1, 3L), (0, 1, 7L), (1, 2, 10L)]
  assert_eq(max_flow(3, 0, 2, edges), 10L)
}

test "dinic: invalid inputs" {
  let edges = [(0, 1, 10L)]
  assert_eq(max_flow(0, 0, 1, edges), 0L) // n = 0
  assert_eq(max_flow(3, -1, 1, edges), 0L) // src < 0
  assert_eq(max_flow(3, 3, 1, edges), 0L) // src >= n
  assert_eq(max_flow(3, 0, -1, edges), 0L) // sink < 0
  assert_eq(max_flow(3, 0, 3, edges), 0L) // sink >= n
  assert_eq(max_flow(3, 1, 1, edges), 0L) // src == sink
}

test "dinic: large layered graph" {
  // 4-layer network: src -> L1(40) -> L2(40) -> L3(40) -> sink
  // Each layer is fully connected to the next with capacity 1.
  // Max flow = 40 (limited by source/sink edge count).
  let w = 40
  let n = 2 + 3 * w // src + 3 layers + sink = 122
  let edges : Array[(Int, Int, Int64)] = []
  // src -> L1
  for i = 0; i < w; i = i + 1 {
    edges.push((0, 1 + i, 1L))
  }
  // L1 -> L2
  for i = 0; i < w; i = i + 1 {
    for j = 0; j < w; j = j + 1 {
      edges.push((1 + i, 1 + w + j, 1L))
    }
  }
  // L2 -> L3
  for i = 0; i < w; i = i + 1 {
    for j = 0; j < w; j = j + 1 {
      edges.push((1 + w + i, 1 + 2 * w + j, 1L))
    }
  }
  // L3 -> sink
  for i = 0; i < w; i = i + 1 {
    edges.push((1 + 2 * w + i, n - 1, 1L))
  }
  assert_eq(max_flow(n, 0, n - 1, edges), 40L)
}

test "dinic: int64 large capacity" {
  // Capacities exceed Int32 max (2^31 - 1 = 2,147,483,647).
  // A chain with capacity 3,000,000,000 on each edge.
  // Max flow = 3,000,000,000, which overflows 32-bit Int.
  let edges = [
    (0, 1, 3000000000L),
    (1, 2, 3000000000L),
  ]
  assert_eq(max_flow(3, 0, 2, edges), 3000000000L)
}
