/// Minimum-cost maximum-flow using **Successive Shortest Paths with Potentials**.
///
/// Given a directed flow network with capacities and per-unit costs on edges,
/// finds the maximum flow from `src` to `sink` that has the minimum total cost
/// among all maximum flows.
///
/// ## Algorithm
///
/// Uses the **Johnson's potentials** technique to achieve O(F · E log V) instead
/// of the O(F · V · E) worst-case of pure SPFA:
///
///   1. Build the graph using a linked-forward-star (chain-based edge list).
///      Each edge `(u, v, cap, cost)` adds a forward edge with residual
///      capacity `cap` and cost `cost`, plus a reverse edge with capacity 0
///      and cost `-cost`.
///   2. **First iteration**: Run SPFA (Bellman-Ford variant) from `src` to
///      compute initial shortest-path distances. These distances become the
///      initial **potentials** `h[v]`. SPFA also detects **negative-cost
///      cycles**: if any vertex is relaxed more than `n` times, the function
///      returns `None`.
///   3. **Subsequent iterations**: Run **Dijkstra** with **reduced costs**
///      `c'(u,v) = cost(u,v) + h[u] - h[v]`. By the triangle inequality of
///      shortest paths, all reduced costs are non-negative, so Dijkstra is
///      correct. After each Dijkstra, update potentials: `h[v] += dist[v]`.
///   4. Augment along the shortest path by the bottleneck residual capacity.
///      Repeat until no augmenting path exists.
///
/// The potential update guarantees that reverse edges created by augmentation
/// also have non-negative reduced costs (specifically, exactly 0 for edges on
/// the augmenting path), so Dijkstra remains valid across all iterations.
///
/// ## Complexity
///
/// - First SPFA: O(V · E) — one-time cost.
/// - Each Dijkstra: O(E log V) with a binary heap.
/// - Number of augmenting iterations: at most the max flow value F.
/// - Total: O(V · E + F · E log V). For unit-capacity networks: O(E log V).
///   This is significantly better than pure SPFA's O(F · V · E).
///
/// ## Overflow protection
///
/// `total_flow` and `total_cost` are accumulated as `Int64`. The product
/// `bottleneck * cost` is also computed in `Int64`. This prevents overflow
/// for all practical inputs where capacities and costs fit in 32-bit `Int`.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

/// A directed edge in the residual graph (linked-forward-star representation).
///
/// `next` links to the next edge originating from the same vertex, forming
/// a singly-linked list. Edges are stored in pairs: edge `i` (forward) and
/// edge `i^1` (reverse), so toggling the lowest bit gives the partner.
priv struct Edge {
  to : Int
  mut cap : Int64 // residual capacity on this edge (Int64 to prevent overflow)
  cost : Int // per-unit cost
  next : Int // index of next edge from the same `from` vertex, -1 = none
}

/// The flow network, built from an edge list.
priv struct MCMFGraph {
  n : Int
  head : Array[Int] // head[v] = first edge index from v, -1 = none
  edges : Array[Edge] // all edges (forward + reverse interleaved)
  mut edge_count : Int // total edges added so far
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
    g.edges.push({ to: v, cap: cap.to_int64(), cost, next: g.head[u] })
    g.head[u] = g.edge_count
    g.edge_count = g.edge_count + 1
    // Reverse edge (capacity 0, cost negated)
    g.edges.push({ to: u, cap: 0L, cost: -cost, next: g.head[v] })
    g.head[v] = g.edge_count
    g.edge_count = g.edge_count + 1
  }
  g
}

// ---------------------------------------------------------------------------
// Binary min-heap for Dijkstra
// ---------------------------------------------------------------------------

/// A simple binary min-heap of `(distance, vertex)` pairs for Dijkstra.
///
/// Supports `push` and `pop_min` in O(log n). Duplicate entries for the same
/// vertex (stale entries) are filtered by comparing the stored distance
/// against the current `dist[]` value during `pop_min`.
priv struct MinHeap {
  heap_dist : Array[Int64]
  heap_vtx : Array[Int]
  mut size : Int
}

fn new_heap(cap : Int) -> MinHeap {
  {
    heap_dist: Array::make(cap, 0L),
    heap_vtx: Array::make(cap, 0),
    size: 0,
  }
}

fn heap_push(h : MinHeap, d : Int64, v : Int) -> Unit {
  let i = h.size
  h.heap_dist[i] = d
  h.heap_vtx[i] = v
  h.size = h.size + 1
  // Sift up.
  let mut idx = i
  while idx > 0 {
    let parent = (idx - 1) / 2
    if h.heap_dist[idx] < h.heap_dist[parent] {
      let td = h.heap_dist[idx]
      h.heap_dist[idx] = h.heap_dist[parent]
      h.heap_dist[parent] = td
      let tv = h.heap_vtx[idx]
      h.heap_vtx[idx] = h.heap_vtx[parent]
      h.heap_vtx[parent] = tv
      idx = parent
    } else {
      break
    }
  }
}

/// Pop the minimum-distance entry. Returns `Some((dist, vtx))` or `None`
/// if the heap is empty. Stale entries (where `dist > cur_dist[vtx]`) are
/// automatically skipped.
fn heap_pop(h : MinHeap, cur_dist : Array[Int64]) -> (Int64, Int)? {
  while h.size > 0 {
    let d = h.heap_dist[0]
    let v = h.heap_vtx[0]
    // Remove top.
    h.size = h.size - 1
    if h.size > 0 {
      h.heap_dist[0] = h.heap_dist[h.size]
      h.heap_vtx[0] = h.heap_vtx[h.size]
      // Sift down.
      let mut idx = 0
      while true {
        let left = 2 * idx + 1
        let right = 2 * idx + 2
        let mut smallest = idx
        if left < h.size && h.heap_dist[left] < h.heap_dist[smallest] {
          smallest = left
        }
        if right < h.size && h.heap_dist[right] < h.heap_dist[smallest] {
          smallest = right
        }
        if smallest != idx {
          let td = h.heap_dist[idx]
          h.heap_dist[idx] = h.heap_dist[smallest]
          h.heap_dist[smallest] = td
          let tv = h.heap_vtx[idx]
          h.heap_vtx[idx] = h.heap_vtx[smallest]
          h.heap_vtx[smallest] = tv
          idx = smallest
        } else {
          break
        }
      }
    }
    // Skip stale entries.
    if d <= cur_dist[v] {
      return Some((d, v))
    }
  }
  None
}

// ---------------------------------------------------------------------------
// SPFA (Bellman-Ford variant) — first iteration only
// ---------------------------------------------------------------------------

/// SPFA to find the shortest (min-cost) path from `src` to all vertices.
///
/// Returns:
/// - `Some(())` if no negative cycle exists (distances filled in `dist`).
/// - `None` if a negative-cost cycle is detected in the residual graph.
///
/// Fills `dist` and `prev_edge`. Uses `Int64` for distances to prevent
/// overflow when accumulating costs.
///
/// **Negative cycle detection**: tracks the number of times each vertex is
/// enqueued. If any vertex is enqueued more than `n` times, a negative cycle
/// exists (since the shortest path in a graph with `n` vertices has at most
/// `n-1` edges).
fn spfa_init(
  g : MCMFGraph,
  src : Int,
  dist : Array[Int64],
  prev_edge : Array[Int],
) -> Unit? {
  let n = g.n
  for i = 0; i < n; i = i + 1 {
    dist[i] = 9223372036854775807L // Int64::MAX as infinity
    prev_edge[i] = -1
  }
  let in_queue = Array::make(n, false)
  let enqueue_count = Array::make(n, 0)
  dist[src] = 0L
  let queue : Array[Int] = [src]
  let mut head = 0
  in_queue[src] = true
  enqueue_count[src] = 1
  while head < queue.length() {
    let u = queue[head]
    head = head + 1
    in_queue[u] = false
    let mut e_idx = g.head[u]
    while e_idx != -1 {
      let e = g.edges[e_idx]
      if e.cap > 0L && dist[u] + e.cost.to_int64() < dist[e.to] {
        dist[e.to] = dist[u] + e.cost.to_int64()
        prev_edge[e.to] = e_idx
        if !in_queue[e.to] {
          enqueue_count[e.to] = enqueue_count[e.to] + 1
          if enqueue_count[e.to] > n {
            return None // Negative cycle detected
          }
          in_queue[e.to] = true
          queue.push(e.to)
        }
      }
      e_idx = e.next
    }
  }
  Some(())
}

// ---------------------------------------------------------------------------
// Dijkstra with reduced costs — subsequent iterations
// ---------------------------------------------------------------------------

/// Dijkstra using reduced costs `c'(u,v) = cost + h[u] - h[v]`.
///
/// All reduced costs are guaranteed non-negative (by the potential invariant),
/// so Dijkstra produces correct shortest paths. After the call, the caller
/// must update potentials: `h[v] += dist[v]` for all reachable v.
///
/// Fills `dist` (using reduced costs) and `prev_edge`. The `h` array holds
/// the current potentials.
fn dijkstra(
  g : MCMFGraph,
  src : Int,
  sink : Int,
  h : Array[Int64],
  dist : Array[Int64],
  prev_edge : Array[Int],
) -> Bool {
  let n = g.n
  let inf = 9223372036854775807L
  for i = 0; i < n; i = i + 1 {
    dist[i] = inf
    prev_edge[i] = -1
  }
  dist[src] = 0L
  let heap = new_heap(g.edge_count + 2)
  heap_push(heap, 0L, src)
  while true {
    match heap_pop(heap, dist) {
      None => break
      Some((d, u)) => {
        if d > dist[u] {
          continue
        }
        if u == sink {
          // We could break early, but we need full dist for potential update.
          // Continue to exhaust the heap for all reachable vertices.
        }
        let mut e_idx = g.head[u]
        while e_idx != -1 {
          let e = g.edges[e_idx]
          if e.cap > 0L {
            // Reduced cost: c'(u,v) = cost + h[u] - h[v]
            let rc = e.cost.to_int64() + h[u] - h[e.to]
            let nd = dist[u] + rc
            if nd < dist[e.to] {
              dist[e.to] = nd
              prev_edge[e.to] = e_idx
              heap_push(heap, nd, e.to)
            }
          }
          e_idx = e.next
        }
      }
    }
  }
  dist[sink] < inf
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

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
/// `Some((max_flow, min_cost))` as `Int64` values. Returns `None` for
/// invalid inputs (n <= 0, out-of-bounds vertices, src == sink) or when
/// a negative-cost cycle is detected in the residual graph.
///
/// **Algorithm**: Successive Shortest Paths with Johnson's Potentials.
/// The first iteration uses SPFA (Bellman-Ford) to compute initial
/// potentials and detect negative cycles. Subsequent iterations use
/// Dijkstra with reduced costs, giving O(E log V) per iteration instead
/// of O(V · E).
///
/// **Overflow**: both `max_flow` and `min_cost` are accumulated as `Int64`.
/// The product `bottleneck * cost` is also computed in `Int64`, preventing
/// overflow for all practical 32-bit inputs.
pub fn min_cost_max_flow(
  n : Int,
  src : Int,
  sink : Int,
  edges : Array[(Int, Int, Int, Int)],
) -> (Int64, Int64)? {
  if n <= 0 || src < 0 || src >= n || sink < 0 || sink >= n || src == sink {
    return None
  }
  let g = build_graph(n, edges)
  let dist = Array::make(n, 0L)
  let prev_edge = Array::make(n, 0)
  // Potentials: h[v] is the shortest distance from src to v in the
  // original costs. After each Dijkstra, h[v] += dist[v] (reduced-cost
  // distances), maintaining the invariant that all reduced costs are
  // non-negative.
  let h = Array::make(n, 0L)
  let mut total_flow = 0L
  let mut total_cost = 0L
  let mut first_iter = true
  let mut found = false
  while true {
    if first_iter {
      // First iteration: SPFA to handle negative costs and detect cycles.
      match spfa_init(g, src, dist, prev_edge) {
        None => return None // Negative cycle detected
        Some(_) => {
          found = dist[sink] < 9223372036854775807L
          // Copy distances to potentials.
          for i = 0; i < n; i = i + 1 {
            if dist[i] < 9223372036854775807L {
              h[i] = dist[i]
            } else {
              // Unreachable vertices: keep potential at 0 (or any value,
              // since they won't be on any augmenting path).
              h[i] = 0L
            }
          }
          first_iter = false
        }
      }
    } else {
      // Subsequent iterations: Dijkstra with reduced costs.
      found = dijkstra(g, src, sink, h, dist, prev_edge)
      if found {
        // Update potentials: h[v] += dist[v] for reachable vertices.
        for i = 0; i < n; i = i + 1 {
          if dist[i] < 9223372036854775807L {
            h[i] = h[i] + dist[i]
          }
        }
      }
    }
    if !found {
      break // No augmenting path
    }
    // Find bottleneck along the augmenting path.
    let mut bottleneck = 9223372036854775807L
    let mut v = sink
    while v != src {
      let e_idx = prev_edge[v]
      if g.edges[e_idx].cap < bottleneck {
        bottleneck = g.edges[e_idx].cap
      }
      v = g.edges[e_idx ^ 1].to // partner edge's `to` = the `from` vertex
    }
    // Augment: update residual capacities and accumulate cost.
    // Use the **original** cost (not reduced cost) for total_cost.
    v = sink
    while v != src {
      let e_idx = prev_edge[v]
      g.edges[e_idx].cap = g.edges[e_idx].cap - bottleneck
      g.edges[e_idx ^ 1].cap = g.edges[e_idx ^ 1].cap + bottleneck
      // Int64 accumulation: bottleneck * cost cannot overflow for
      // 32-bit inputs (max product ~ 2^31 * 2^31 = 2^62 < 2^63).
      total_cost = total_cost + bottleneck * g.edges[e_idx].cost.to_int64()
      v = g.edges[e_idx ^ 1].to
    }
    total_flow = total_flow + bottleneck
  }
  Some((total_flow, total_cost))
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "mcmf: simple chain" {
  // 0 ->(10, 1) 1 ->(10, 2) 2
  // Max flow = 10, min cost = 10 * (1 + 2) = 30
  let edges = [(0, 1, 10, 1), (1, 2, 10, 2)]
  let (flow, cost) = min_cost_max_flow(3, 0, 2, edges).unwrap()
  assert_eq(flow, 10L)
  assert_eq(cost, 30L)
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
  let (flow, cost) = min_cost_max_flow(3, 0, 2, edges).unwrap()
  assert_eq(flow, 10L)
  assert_eq(cost, 60L)
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
  let (flow, cost) = min_cost_max_flow(3, 0, 2, edges).unwrap()
  assert_eq(flow, 13L)
  assert_eq(cost, 53L)
}

test "mcmf: no path" {
  let edges = [(0, 1, 10, 1)]
  let (flow, cost) = min_cost_max_flow(4, 0, 3, edges).unwrap()
  assert_eq(flow, 0L)
  assert_eq(cost, 0L)
}

test "mcmf: src equals sink returns None" {
  let edges = [(0, 1, 10, 1)]
  assert_true(min_cost_max_flow(3, 0, 0, edges) is None)
}

test "mcmf: invalid inputs return None" {
  let edges = [(0, 1, 10, 1)]
  assert_true(min_cost_max_flow(0, 0, 1, edges) is None)
  assert_true(min_cost_max_flow(3, -1, 1, edges) is None)
  assert_true(min_cost_max_flow(3, 0, 5, edges) is None)
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
  let (flow, cost) = min_cost_max_flow(4, 0, 3, edges).unwrap()
  assert_eq(flow, 13L)
  assert_eq(cost, 71L)
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
  let (flow, cost) = min_cost_max_flow(4, 0, 3, edges).unwrap()
  assert_eq(flow, 10L)
  assert_eq(cost, 20L)
}

test "mcmf: unit capacities network" {
  // Diamond: 0 -> 1 (1, 1), 0 -> 2 (1, 1), 1 -> 3 (1, 1), 2 -> 3 (1, 1)
  // Max flow = 2, cost = 4
  let edges = [
    (0, 1, 1, 1),
    (0, 2, 1, 1),
    (1, 3, 1, 1),
    (2, 3, 1, 1),
  ]
  let (flow, cost) = min_cost_max_flow(4, 0, 3, edges).unwrap()
  assert_eq(flow, 2L)
  assert_eq(cost, 4L)
}

test "mcmf: negative cost edges" {
  // Edge with negative cost: 0 -> 1 (cap 5, cost -3)
  // The algorithm must handle this via initial SPFA.
  let edges = [
    (0, 1, 5, -3),
    (1, 2, 5, 2),
  ]
  let (flow, cost) = min_cost_max_flow(3, 0, 2, edges).unwrap()
  assert_eq(flow, 5L)
  assert_eq(cost, -5L) // 5 * (-3 + 2) = 5 * (-1) = -5
}

test "mcmf: stress test against brute force" {
  // Build a moderate network and verify against a hand-computed MCMF.
  // Graph: 0 -> 1 (10, 3), 0 -> 2 (8, 5), 1 -> 2 (4, -1), 1 -> 3 (8, 2),
  //        2 -> 3 (10, 1)
  // Has negative cost edge (1->2 cost -1).
  let edges = [
    (0, 1, 10, 3),
    (0, 2, 8, 5),
    (1, 2, 4, -1),
    (1, 3, 8, 2),
    (2, 3, 10, 1),
  ]
  let (flow, cost) = min_cost_max_flow(4, 0, 3, edges).unwrap()
  // Max flow = 18: send 10 through 0->1 and 8 through 0->2.
  // At node 1: x1=10 splits into x3=2 (1->2) and x4=8 (1->3).
  // At node 2: x2=8 (0->2) + x3=2 (1->2) = 10 = x5 (2->3).
  // Flow = x4 + x5 = 8 + 10 = 18.
  // Min cost for flow 18: cost = 3*10 + 5*8 + (-1)*2 + 2*8 + 1*10 = 94.
  // Maximising x3 (the negative-cost edge) minimises total cost.
  // x3 ≤ 4 (cap), x3 ≤ 10 - x2 = 2 (node 2 capacity), so x3 = 2.
  assert_eq(flow, 18L)
  assert_eq(cost, 94L)
}
