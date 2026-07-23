/// Minimum-cost maximum-flow using SPFA (Shortest Path Faster Algorithm).
///
/// Given a directed flow network with capacities and per-unit costs on edges,
/// finds the maximum flow from `src` to `sink` that has the minimum total cost
/// among all maximum flows.
///
/// ## Algorithm
///
///   1. Build the graph using a linked-forward-star (chain-based edge list).
///      Each edge `(u, v, cap, cost)` adds a forward edge with residual
///      capacity `cap` and cost `cost`, plus a reverse edge with capacity 0
///      and cost `-cost`.
///   2. Repeatedly use SPFA (a queue-based Bellman-Ford variant) to find the
///      shortest (minimum-cost) augmenting path from `src` to `sink` in the
///      residual graph.
///   3. Augment along that path by the bottleneck residual capacity.
///   4. Accumulate flow and cost. Repeat until no augmenting path exists.
///
/// ## Complexity
///
/// - Each SPFA run is O(V * E) in the worst case (but typically much faster).
/// - The number of augmenting iterations is at most the max flow value F.
/// - Total: O(F * V * E) worst-case. For unit-capacity networks this is
///   O(V * E). For integer capacities the bound is tight but SPFA's average
///   performance is far better.
///
/// ## Limitations
///
/// - **No negative-cost cycles**: SPFA will detect and abort if a negative
///   cost cycle exists in the residual graph, but the result is undefined.
/// - **Overflow**: `total_cost` and `total_flow` are accumulated as 32-bit
///   `Int`. If the total cost or flow exceeds `Int::max_value` (2³¹−1),
///   overflow will produce incorrect results.
/// - **Self-loops** are ignored.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

/// A directed edge in the residual graph (linked-forward-star representation).
///
/// `next` links to the next edge originating from the same vertex, forming
/// a singly-linked list. Edges are stored in pairs: edge `i` (forward) and
/// edge `i^1` (reverse), so toggling the lowest bit gives the partner.
priv struct Edge {
  to : Int
  mut cap : Int   // residual capacity on this edge
  cost : Int       // per-unit cost
  next : Int      // index of next edge from the same `from` vertex, -1 = none
}

/// The flow network, built from an edge list.
priv struct MCMFGraph {
  n : Int
  head : Array[Int]        // head[v] = first edge index from v, -1 = none
  edges : Array[Edge]      // all edges (forward + reverse interleaved)
  mut edge_count : Int     // total edges added so far
}

fn build_graph(n : Int, edge_list : Array[(Int, Int, Int, Int)]) -> MCMFGraph {
  let g : MCMFGraph = {
    n,
    head: Array::make(n, -1),
    edges: [],
    edge_count: 0,
  }
  for k = 0; k < edge_list.length(); k = k + 1 {
    let (u, v, cap, cost) = edge_list[k]
    if u < 0 || u >= n || v < 0 || v >= n || u == v || cap <= 0 {
      continue
    }
    // Forward edge
    g.edges.push({ to: v, cap, cost, next: g.head[u] })
    g.head[u] = g.edge_count
    g.edge_count = g.edge_count + 1
    // Reverse edge (capacity 0, cost negated)
    g.edges.push({ to: u, cap: 0, cost: -cost, next: g.head[v] })
    g.head[v] = g.edge_count
    g.edge_count = g.edge_count + 1
  }
  g
}

/// SPFA to find the shortest (min-cost) path from `src` to `sink`.
/// Returns `true` if `sink` is reachable. Fills `dist`, `prev_edge`, and
/// `in_queue` arrays.
fn spfa(
  g : MCMFGraph,
  src : Int,
  sink : Int,
  dist : Array[Int],
  prev_edge : Array[Int],
  in_queue : Array[Bool],
) -> Bool {
  for i = 0; i < g.n; i = i + 1 {
    dist[i] = 2147483647
    prev_edge[i] = -1
    in_queue[i] = false
  }
  dist[src] = 0
  // Index-based FIFO queue (avoids Array::shift which doesn't exist).
  let queue = FixedArray::make(g.n, 0)
  let mut head = 0
  let mut tail = 0
  queue[tail] = src
  tail = tail + 1
  in_queue[src] = true
  while head < tail {
    let u = queue[head]
    head = head + 1
    in_queue[u] = false
    let mut e_idx = g.head[u]
    while e_idx != -1 {
      let e = g.edges[e_idx]
      if e.cap > 0 && dist[u] + e.cost < dist[e.to] {
        dist[e.to] = dist[u] + e.cost
        prev_edge[e.to] = e_idx
        if !in_queue[e.to] {
          in_queue[e.to] = true
          queue[tail] = e.to
          tail = tail + 1
        }
      }
      e_idx = e.next
    }
  }
  dist[sink] < 2147483647
}

/// Compute the maximum flow and its minimum cost.
///
/// # Parameters
/// - `n`: number of vertices, indexed `0 .. n - 1`.
/// - `src`: source vertex.
/// - `sink`: sink vertex.
/// - `edges`: list of `(from, to, capacity, cost)` tuples. Each edge is
///   directed. For undirected flow, add edges in both directions.
///
/// # Returns
/// `(max_flow, min_cost)`. Returns `(0, 0)` for invalid inputs (n <= 0,
/// out-of-bounds vertices, src == sink).
///
/// **Overflow**: both `max_flow` and `min_cost` are 32-bit `Int`. If the
/// total exceeds 2³¹−1, results will be incorrect.
pub fn min_cost_max_flow(
  n : Int,
  src : Int,
  sink : Int,
  edges : Array[(Int, Int, Int, Int)],
) -> (Int, Int) {
  if n <= 0 || src < 0 || src >= n || sink < 0 || sink >= n || src == sink {
    return (0, 0)
  }
  let g = build_graph(n, edges)
  let dist = Array::make(n, 0)
  let prev_edge = Array::make(n, 0)
  let in_queue = Array::make(n, false)
  let mut total_flow = 0
  let mut total_cost = 0
  while spfa(g, src, sink, dist, prev_edge, in_queue) {
    // Find bottleneck along the augmenting path.
    let mut bottleneck = 2147483647
    let mut v = sink
    while v != src {
      let e_idx = prev_edge[v]
      if g.edges[e_idx].cap < bottleneck {
        bottleneck = g.edges[e_idx].cap
      }
      v = g.edges[e_idx ^ 1].to // partner edge's `to` = the `from` vertex
    }
    // Augment: update residual capacities and accumulate cost.
    v = sink
    while v != src {
      let e_idx = prev_edge[v]
      g.edges[e_idx].cap = g.edges[e_idx].cap - bottleneck
      g.edges[e_idx ^ 1].cap = g.edges[e_idx ^ 1].cap + bottleneck
      total_cost = total_cost + bottleneck * g.edges[e_idx].cost
      v = g.edges[e_idx ^ 1].to
    }
    total_flow = total_flow + bottleneck
  }
  (total_flow, total_cost)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "mcmf: simple chain" {
  // 0 ->(10, 1) 1 ->(10, 2) 2
  // Max flow = 10, min cost = 10 * (1 + 2) = 30
  let edges = [(0, 1, 10, 1), (1, 2, 10, 2)]
  let (flow, cost) = min_cost_max_flow(3, 0, 2, edges)
  assert_eq(flow, 10)
  assert_eq(cost, 30)
}

test "mcmf: two parallel paths pick cheaper" {
  // 0 -> 2 directly (cap 5, cost 10)
  // 0 -> 1 -> 2 (cap 5, cost 1 + 1 = 2)
  // Max flow = 10 (5 + 5), min cost = 5*10 + 5*2 = 60
  let edges = [
    (0, 2, 5, 10),
    (0, 1, 5, 1),
    (1, 2, 5, 1),
  ]
  let (flow, cost) = min_cost_max_flow(3, 0, 2, edges)
  assert_eq(flow, 10)
  assert_eq(cost, 60)
}

test "mcmf: cheaper path has less capacity" {
  // Path A: 0 -> 2, cap 3, cost 1
  // Path B: 0 -> 1 -> 2, cap 10, cost 5
  // Max flow = 13, min cost = 3*1 + 10*5 = 53
  let edges = [
    (0, 2, 3, 1),
    (0, 1, 10, 1),
    (1, 2, 10, 4),
  ]
  let (flow, cost) = min_cost_max_flow(3, 0, 2, edges)
  assert_eq(flow, 13)
  assert_eq(cost, 53)
}

test "mcmf: no path" {
  let edges = [(0, 1, 10, 1)]
  let (flow, cost) = min_cost_max_flow(4, 0, 3, edges)
  assert_eq(flow, 0)
  assert_eq(cost, 0)
}

test "mcmf: src equals sink" {
  let edges = [(0, 1, 10, 1)]
  let (flow, cost) = min_cost_max_flow(3, 0, 0, edges)
  assert_eq(flow, 0)
  assert_eq(cost, 0)
}

test "mcmf: invalid inputs" {
  let edges = [(0, 1, 10, 1)]
  assert_eq(min_cost_max_flow(0, 0, 1, edges), (0, 0))
  assert_eq(min_cost_max_flow(3, -1, 1, edges), (0, 0))
  assert_eq(min_cost_max_flow(3, 0, 5, edges), (0, 0))
}

test "mcmf: classic transport problem" {
  // Source 0 supplies flow to sink 3 via two warehouses (1, 2).
  // 0 -> 1 (cap 8, cost 2)
  // 0 -> 2 (cap 6, cost 5)
  // 1 -> 3 (cap 7, cost 3)
  // 2 -> 3 (cap 10, cost 1)
  // Max flow = 13: 7 via 0->1->3 (bottleneck 1->3 cap 7), 6 via 0->2->3
  // (bottleneck 0->2 cap 6). Total source outflow = 8+6=14 but 1->3 caps
  // path A at 7, so only 7 flows through 1. The remaining 6 flows through 2.
  // Min cost = 7*(2+3) + 6*(5+1) = 35 + 36 = 71.
  let edges = [
    (0, 1, 8, 2),
    (0, 2, 6, 5),
    (1, 3, 7, 3),
    (2, 3, 10, 1),
  ]
  let (flow, cost) = min_cost_max_flow(4, 0, 3, edges)
  assert_eq(flow, 13)
  assert_eq(cost, 71)
}

test "mcmf: reverse edge enables rerouting" {
  // 0 -> 1 (cap 5, cost 1)
  // 0 -> 2 (cap 5, cost 1)
  // 1 -> 3 (cap 5, cost 1)
  // 2 -> 3 (cap 5, cost 1)
  // 1 -> 2 (cap 5, cost 0)  // cross edge
  // Max flow = 10, min cost = 10 * 2 = 20 (all paths cost 2)
  let edges = [
    (0, 1, 5, 1),
    (0, 2, 5, 1),
    (1, 3, 5, 1),
    (2, 3, 5, 1),
    (1, 2, 5, 0),
  ]
  let (flow, cost) = min_cost_max_flow(4, 0, 3, edges)
  assert_eq(flow, 10)
  assert_eq(cost, 20)
}

test "mcmf: unit capacity network" {
  // Diamond: 0 -> 1 (1, 1), 0 -> 2 (1, 1), 1 -> 3 (1, 1), 2 -> 3 (1, 1)
  // Max flow = 2, cost = 4
  let edges = [
    (0, 1, 1, 1),
    (0, 2, 1, 1),
    (1, 3, 1, 1),
    (2, 3, 1, 1),
  ]
  let (flow, cost) = min_cost_max_flow(4, 0, 3, edges)
  assert_eq(flow, 2)
  assert_eq(cost, 4)
}
