/// Maximum flow using Dinic's algorithm.
///
/// Given a directed flow network with capacities on edges, finds the maximum
/// flow from `src` to `sink`. Dinic's algorithm improves on Edmonds-Karp by
/// building a *level graph* (via BFS) in each phase and finding *blocking
/// flow* (via iterative DFS) — the maximum flow after which no augmenting
/// path exists in the current level graph.
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
///   3. **DFS phase**: find augmenting paths using an **iterative** DFS that
///      only traverses edges `(u, v)` where `level[v] == level[u] + 1`. The
///      *current-arc optimization* (`cur[]` array) ensures each edge is
///      examined at most once per phase.
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
/// up to 2⁶³ − 1.
///
/// ## Stack safety
///
/// The DFS is **iterative** (explicit path tracing, no recursion). This
/// prevents stack overflow on adversarial inputs that create deep level
/// graphs (depth > 10⁴), which is a production safety requirement.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.
///
/// ## Limitations
///
/// - Self-loops (`u == v`) and non-positive capacities are silently ignored.

///|
/// Sentinel representing "infinite capacity" for the bottleneck search.
let int64_max : Int64 = 9223372036854775807L

///|
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

///|
/// The flow network, built from an edge list.
priv struct DinicGraph {
  n : Int
  head : Array[Int] // head[v] = first edge index from v, -1 = none
  edges : Array[Edge] // all edges (forward + reverse interleaved)
  mut edge_count : Int // total edges added so far
}

///|
/// Build the residual graph from an edge list.
///
/// For each valid edge `(u, v, cap)`, adds a forward edge (capacity `cap`)
/// and a reverse edge (capacity 0). Invalid edges (out-of-bounds vertices,
/// self-loops, non-positive capacity) are silently skipped.
fn build_graph(n : Int, edge_list : Array[(Int, Int, Int64)]) -> DinicGraph {
  let g : DinicGraph = { n, head: Array::make(n, -1), edges: [], edge_count: 0 }
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

///|
/// BFS to build the level graph.
///
/// Computes `level[v]` = shortest hop-distance from `src` to `v` in the
/// residual graph (edges with positive residual capacity only). Unreachable
/// vertices get level -1. Returns `true` if `sink` is reachable.
fn bfs(g : DinicGraph, src : Int, sink : Int, level : FixedArray[Int]) -> Bool {
  for i = 0; i < g.n; i = i + 1 {
    level[i] = -1
  }
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

///|
/// Iterative DFS that finds augmenting paths and pushes flow.
///
/// Uses the "repeated single-path" strategy within the level graph: find one
/// augmenting path from `src` to `sink`, push the bottleneck flow along it,
/// and repeat until no more paths exist in the current level graph.
///
/// **Stack safety**: this is entirely iterative (no recursion). The path is
/// traced using `path_v[]` and `path_e[]` arrays of size `n+1`, so the maximum
/// "depth" is bounded by `n` (the number of vertices). This prevents stack
/// overflow on adversarial inputs.
///
/// **Current-arc optimization**: the `cur[]` array tracks the next edge to
/// try for each vertex. Once an edge is exhausted (capacity 0) or leads to
/// a dead end (all downstream paths exhausted), `cur[u]` advances past it.
/// This ensures each edge is examined at most once per phase, giving O(VE)
/// total work per phase.
fn find_and_push_paths(
  g : DinicGraph,
  src : Int,
  sink : Int,
  level : FixedArray[Int],
  cur : FixedArray[Int],
) -> Int64 {
  if src == sink {
    return 0L
  }
  // Path tracing arrays. path_v[i] = vertex at position i in the path.
  // path_e[i] = edge index used to reach path_v[i] from path_v[i-1].
  // path_e[0] is unused (src has no incoming edge).
  let path_v = FixedArray::make(g.n + 1, 0)
  let path_e = FixedArray::make(g.n + 1, 0)
  let mut path_len = 1
  path_v[0] = src
  let mut total_pushed = 0L

  while path_len > 0 {
    let u = path_v[path_len - 1]

    if u == sink {
      // Found a path from src to sink. Find the bottleneck (minimum
      // residual capacity along the path).
      let mut bottleneck = int64_max
      for i = 1; i < path_len; i = i + 1 {
        let cap = g.edges[path_e[i]].cap
        if cap < bottleneck {
          bottleneck = cap
        }
      }
      // Push flow: decrease forward edges, increase reverse edges.
      for i = 1; i < path_len; i = i + 1 {
        let e_idx = path_e[i]
        g.edges[e_idx].cap = g.edges[e_idx].cap - bottleneck
        g.edges[e_idx ^ 1].cap = g.edges[e_idx ^ 1].cap + bottleneck
      }
      total_pushed = total_pushed + bottleneck

      // Backtrack to the vertex just before the first saturated edge.
      // The saturated edge's source vertex has its cur[] advanced past it,
      // so we don't re-examine it. Edges before the first saturated one
      // still have capacity and may be reused.
      let mut new_len = path_len
      for i = 1; i < path_len; i = i + 1 {
        if g.edges[path_e[i]].cap == 0L {
          // Edge from path_v[i-1] to path_v[i] is saturated.
          // Advance cur[path_v[i-1]] past this edge.
          let src_v = path_v[i - 1]
          cur[src_v] = g.edges[path_e[i]].next
          new_len = i
          break
        }
      }
      path_len = new_len
      continue
    }

    // Try to advance from u along an admissible edge.
    let mut advanced = false
    while cur[u] != -1 {
      let e = g.edges[cur[u]]
      if level[e.to] == level[u] + 1 && e.cap > 0L {
        // Admissible edge found: extend the path.
        path_v[path_len] = e.to
        path_e[path_len] = cur[u]
        path_len = path_len + 1
        advanced = true
        break
      }
      // Edge not admissible (wrong level or no capacity): skip it.
      cur[u] = e.next
    }

    if !advanced {
      // Dead end at u: all edges from u in the level graph are exhausted.
      // Backtrack and advance the parent's cur past the edge to u, since
      // u is now a dead end and re-entering it would be wasted work.
      path_len = path_len - 1
      if path_len > 0 {
        // The edge used to reach u is path_e[path_len] (u was at position
        // path_len before the decrement). Advance the parent's cur past it.
        let edge_to_u = path_e[path_len]
        let parent_v = path_v[path_len - 1]
        cur[parent_v] = g.edges[edge_to_u].next
      }
    }
  }

  total_pushed
}

///|
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
/// `Some(flow)` for valid inputs, where `flow` is the maximum flow value as
/// `Int64`. A valid flow of `0L` means `src` and `sink` are disconnected.
///
/// `None` for invalid inputs: `n <= 0`, out-of-bounds vertices, or
/// `src == sink`.
///
/// **Overflow safety**: all capacities and flow accumulation use `Int64`,
/// supporting total flows up to 2⁶³ − 1.
///
/// **Stack safety**: the DFS uses iterative path tracing (no recursion), so
/// it is safe for adversarial inputs that create deep level graphs.
pub fn max_flow(
  n : Int,
  src : Int,
  sink : Int,
  edges : Array[(Int, Int, Int64)],
) -> Int64? {
  if n <= 0 || src < 0 || src >= n || sink < 0 || sink >= n || src == sink {
    return None
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
    // Find all augmenting paths in this level graph (blocking flow).
    let mut pushed = find_and_push_paths(g, src, sink, level, cur)
    while pushed > 0L {
      total_flow = total_flow + pushed
      pushed = find_and_push_paths(g, src, sink, level, cur)
    }
  }
  Some(total_flow)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "dinic: simple chain" {
  let edges = [(0, 1, 10L), (1, 2, 10L), (2, 3, 10L)]
  assert_eq(max_flow(4, 0, 3, edges), Some(10L))
}

///|
test "dinic: two parallel paths" {
  let edges = [(0, 1, 10L), (0, 2, 5L), (1, 3, 5L), (2, 3, 10L)]
  assert_eq(max_flow(4, 0, 3, edges), Some(10L))
}

///|
test "dinic: bottleneck" {
  let edges = [(0, 1, 20L), (1, 2, 5L), (2, 3, 20L)]
  assert_eq(max_flow(4, 0, 3, edges), Some(5L))
}

///|
test "dinic: no path" {
  let edges = [(0, 1, 10L), (2, 3, 10L)]
  assert_eq(max_flow(4, 0, 3, edges), Some(0L))
}

///|
test "dinic: single edge" {
  let edges = [(0, 1, 7L)]
  assert_eq(max_flow(2, 0, 1, edges), Some(7L))
}

///|
test "dinic: classic CLRS example" {
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
  assert_eq(max_flow(6, 0, 5, edges), Some(23L))
}

///|
test "dinic: undirected graph (bidirectional edges)" {
  let edges = [(0, 1, 10L), (1, 0, 10L), (1, 2, 10L), (2, 1, 10L)]
  assert_eq(max_flow(3, 0, 2, edges), Some(10L))
}

///|
test "dinic: self-loop ignored" {
  let edges = [(0, 0, 100L), (0, 1, 10L), (1, 2, 10L)]
  assert_eq(max_flow(3, 0, 2, edges), Some(10L))
}

///|
test "dinic: parallel edges" {
  let edges = [(0, 1, 3L), (0, 1, 7L), (1, 2, 10L)]
  assert_eq(max_flow(3, 0, 2, edges), Some(10L))
}

///|
test "dinic: invalid inputs return None" {
  let edges = [(0, 1, 10L)]
  assert_true(max_flow(0, 0, 1, edges) is None)
  assert_true(max_flow(3, -1, 1, edges) is None)
  assert_true(max_flow(3, 3, 1, edges) is None)
  assert_true(max_flow(3, 0, -1, edges) is None)
  assert_true(max_flow(3, 0, 3, edges) is None)
  assert_true(max_flow(3, 1, 1, edges) is None)
}

///|
test "dinic: large layered graph" {
  let w = 40
  let n = 2 + 3 * w
  let edges : Array[(Int, Int, Int64)] = []
  for i = 0; i < w; i = i + 1 {
    edges.push((0, 1 + i, 1L))
  }
  for i = 0; i < w; i = i + 1 {
    for j = 0; j < w; j = j + 1 {
      edges.push((1 + i, 1 + w + j, 1L))
    }
  }
  for i = 0; i < w; i = i + 1 {
    for j = 0; j < w; j = j + 1 {
      edges.push((1 + w + i, 1 + 2 * w + j, 1L))
    }
  }
  for i = 0; i < w; i = i + 1 {
    edges.push((1 + 2 * w + i, n - 1, 1L))
  }
  assert_eq(max_flow(n, 0, n - 1, edges), Some(40L))
}

///|
test "dinic: int64 large capacity" {
  let edges = [(0, 1, 3000000000L), (1, 2, 3000000000L)]
  assert_eq(max_flow(3, 0, 2, edges), Some(3000000000L))
}

///|
test "dinic: deep chain 2000 nodes (stack safety)" {
  // A chain of 2000 nodes tests that the iterative DFS doesn't stack overflow.
  // With a recursive DFS, this could overflow on some MoonBit configurations.
  let n = 2000
  let edges : Array[(Int, Int, Int64)] = []
  for i = 0; i < n - 1; i = i + 1 {
    edges.push((i, i + 1, 1L))
  }
  assert_eq(max_flow(n, 0, n - 1, edges), Some(1L))
}
