/// Maximum flow using the Highest-Label Preflow-Push (HLPP) algorithm.
///
/// HLPP is a push-relabel algorithm that maintains a *preflow* (where inflow
/// ≥ outflow for each vertex) and progressively converts it to a maximum flow
/// by pushing excess from vertices with positive excess to neighbors at lower
/// height. The **highest-label selection rule** always processes the active
/// vertex with the greatest height label, which combined with the **gap
/// heuristic** yields O(V²√E) time complexity.
///
/// ## Algorithm
///
/// 1. **Initialize**: Set `h[src] = n`. Saturate all edges from `src` by
///    pushing their full capacity (creating excess at neighbors).
/// 2. **Main loop**: While there exists an active vertex `u` (excess > 0,
///    `u ≠ src, sink`) at the highest non-empty bucket:
///    - Try to push excess along **admissible** edges `(u → v)` where
///      `h[u] = h[v] + 1` and residual capacity > 0.
///    - If excess remains and no admissible edge exists, **relabel** `u`:
///      `h[u] = 1 + min(h[v])` over all `v` with residual capacity > 0.
///    - **Gap heuristic**: when `count[h_old]` drops to 0 for some `h_old < n`,
///      relabel all vertices with `h > h_old` to `n + 1`.
///    - If `u` still has excess and `h[u] < n + 1`, re-insert into bucket.
///
/// ## Optimizations
///
/// - **Highest-label bucket queue**: An array of linked lists indexed by
///   height provides O(1) access to the highest active vertex.
/// - **Gap heuristic**: When all vertices at height `h` vanish, all vertices
///   above `h` are lifted to `n+1`, effectively removing them from further
///   pushing.
/// - **Current-edge pointer**: Each vertex remembers its next edge to try,
///   avoiding re-scanning exhausted edges.
/// - **Int64 capacities**: All capacity and flow arithmetic uses `Int64`.
///
/// ## Complexity
///
/// - O(V²√E) — better than Dinic's O(V²E) for dense graphs.
/// - Space: O(V + E) via the linked-forward-star edge representation.
///
/// ## Stack safety
///
/// Fully iterative — no recursion is used.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

///|
/// Sentinel for "no vertex" / "no edge".
let nil : Int = -1

///|
/// A directed edge in the residual graph (linked-forward-star representation).
///
/// Edges are stored in pairs: edge `i` (forward) and edge `i ^ 1` (reverse),
/// so toggling the lowest bit gives the partner edge.
priv struct Edge {
  to : Int
  mut cap : Int64
  next : Int
}

///|
/// The flow network.
priv struct FlowGraph {
  head : Array[Int]
  edges : Array[Edge]
  mut edge_count : Int
}

///|
/// Build the residual graph from an edge list.
fn build_graph(n : Int, edge_list : Array[(Int, Int, Int64)]) -> FlowGraph {
  let g : FlowGraph = { head: Array::make(n, nil), edges: [], edge_count: 0 }
  for k = 0; k < edge_list.length(); k = k + 1 {
    let (u, v, cap) = edge_list[k]
    if u < 0 || u >= n || v < 0 || v >= n || u == v || cap <= 0L {
      continue
    }
    g.edges.push({ to: v, cap, next: g.head[u] })
    g.head[u] = g.edge_count
    g.edge_count = g.edge_count + 1
    g.edges.push({ to: u, cap: 0L, next: g.head[v] })
    g.head[v] = g.edge_count
    g.edge_count = g.edge_count + 1
  }
  g
}

///|
/// Compute the maximum flow from `src` to `sink` using HLPP.
///
/// # Parameters
/// - `n`: number of vertices (0 .. n-1).
/// - `src`: source vertex.
/// - `sink`: sink vertex.
/// - `edges`: edge list of `(from, to, capacity)` tuples. Capacities are
///   `Int64` for overflow safety.
///
/// # Returns
/// `Some(flow)` as `Int64` for valid inputs, or `None` for invalid inputs.
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

  // --- State ---
  let height = FixedArray::make(n, 0)
  let excess = FixedArray::make(n, 0L)
  let cur_edge = FixedArray::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    cur_edge[i] = g.head[i]
  }

  // Height frequency count for gap heuristic (max height = 2*n).
  let max_h = 2 * n + 2
  let height_count = FixedArray::make(max_h, 0)

  // Bucket queue: linked list of active vertices per height.
  let bucket_head = FixedArray::make(max_h, nil)
  let bucket_next = FixedArray::make(n, nil)
  let in_bucket = FixedArray::make(n, false)
  let mut highest = nil

  // --- Initialize ---
  height[src] = n
  height_count[n] = 1

  // Saturate all edges from source.
  let mut e = g.head[src]
  while e != nil {
    let cap = g.edges[e].cap
    if cap > 0L {
      let v = g.edges[e].to
      g.edges[e].cap = 0L
      g.edges[e ^ 1].cap = g.edges[e ^ 1].cap + cap
      excess[v] = excess[v] + cap
      if v != sink && v != src && !in_bucket[v] {
        let h = height[v]
        bucket_next[v] = bucket_head[h]
        bucket_head[h] = v
        in_bucket[v] = true
        if h > highest {
          highest = h
        }
      }
    }
    e = g.edges[e].next
  }

  // --- Main loop ---
  while highest >= 0 {
    // Find highest non-empty bucket.
    while highest >= 0 && bucket_head[highest] == nil {
      highest = highest - 1
    }
    if highest < 0 {
      break
    }

    // Pop vertex u from the highest bucket.
    let u = bucket_head[highest]
    bucket_head[highest] = bucket_next[u]
    in_bucket[u] = false

    // Try to push excess along admissible edges.
    while excess[u] > 0L {
      let mut found_admissible = false
      // Scan edges from current pointer.
      while cur_edge[u] != nil {
        let e_idx = cur_edge[u]
        let v = g.edges[e_idx].to
        if g.edges[e_idx].cap > 0L && height[u] == height[v] + 1 {
          found_admissible = true
          // Push min(excess[u], cap[e]).
          let push_amt = if excess[u] < g.edges[e_idx].cap {
            excess[u]
          } else {
            g.edges[e_idx].cap
          }
          g.edges[e_idx].cap = g.edges[e_idx].cap - push_amt
          g.edges[e_idx ^ 1].cap = g.edges[e_idx ^ 1].cap + push_amt
          excess[u] = excess[u] - push_amt
          excess[v] = excess[v] + push_amt
          // Add v to bucket if it becomes active.
          if v != src && v != sink && !in_bucket[v] && excess[v] > 0L {
            let hv = height[v]
            bucket_next[v] = bucket_head[hv]
            bucket_head[hv] = v
            in_bucket[v] = true
            if hv > highest {
              highest = hv
            }
          }
          if excess[u] == 0L {
            break
          }
        } else {
          // Edge not admissible — advance current pointer.
          cur_edge[u] = g.edges[e_idx].next
        }
      }
      if excess[u] == 0L {
        break
      }
      if !found_admissible && cur_edge[u] == nil {
        // All edges exhausted — relabel u.
        // Gap heuristic: check if old height bucket is now empty.
        let old_h = height[u]
        height_count[old_h] = height_count[old_h] - 1
        if old_h < n && height_count[old_h] == 0 {
          // Gap: lift all vertices with height > old_h and < n+1 to n+1.
          for w = 0; w < n; w = w + 1 {
            if w != src && w != sink && height[w] > old_h && height[w] < n + 1 {
              height_count[height[w]] = height_count[height[w]] - 1
              height[w] = n + 1
              height_count[n + 1] = height_count[n + 1] + 1
              cur_edge[w] = g.head[w]
            }
          }
        }
        // Compute new height: min(h[v]+1) over all v with cap > 0.
        let mut min_h = 2 * n + 1
        let mut e2 = g.head[u]
        while e2 != nil {
          if g.edges[e2].cap > 0L {
            let hv = height[g.edges[e2].to]
            if hv + 1 < min_h {
              min_h = hv + 1
            }
          }
          e2 = g.edges[e2].next
        }
        height[u] = min_h
        if min_h < max_h {
          height_count[min_h] = height_count[min_h] + 1
        }
        cur_edge[u] = g.head[u] // reset current edge
        // If height >= n+1, vertex can't push further.
        if height[u] >= n + 1 {
          break
        }
      }
    }

    // If u still has excess and valid height, re-bucket it.
    if excess[u] > 0L && height[u] < n + 1 {
      let hu = height[u]
      bucket_next[u] = bucket_head[hu]
      bucket_head[hu] = u
      in_bucket[u] = true
      if hu > highest {
        highest = hu
      }
    }
  }

  Some(excess[sink])
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "hlpp: simple chain" {
  let edges = [(0, 1, 10L), (1, 2, 10L), (2, 3, 10L)]
  assert_eq(max_flow(4, 0, 3, edges), Some(10L))
}

///|
test "hlpp: diamond network" {
  // 0 → 1 (10), 0 → 2 (10), 1 → 3 (10), 2 → 3 (10), 1 → 2 (1)
  let edges = [(0, 1, 10L), (0, 2, 10L), (1, 3, 10L), (2, 3, 10L), (1, 2, 1L)]
  assert_eq(max_flow(4, 0, 3, edges), Some(20L))
}

///|
test "hlpp: bottleneck" {
  // 0 → 1 (10), 1 → 2 (5), 1 → 3 (5), 2 → 4 (5), 3 → 4 (5)
  let edges = [(0, 1, 10L), (1, 2, 5L), (1, 3, 5L), (2, 4, 5L), (3, 4, 5L)]
  assert_eq(max_flow(5, 0, 4, edges), Some(10L))
}

///|
test "hlpp: multiple sources and sinks via super node" {
  // Super source 0 → real sources 1, 2 (cap 10 each)
  // Real sinks 3, 4 → super sink 5 (cap 10 each)
  // 1 → 3 (5), 1 → 4 (5), 2 → 3 (5), 2 → 4 (5)
  let edges = [
    (0, 1, 10L),
    (0, 2, 10L),
    (1, 3, 5L),
    (1, 4, 5L),
    (2, 3, 5L),
    (2, 4, 5L),
    (3, 5, 10L),
    (4, 5, 10L),
  ]
  assert_eq(max_flow(6, 0, 5, edges), Some(20L))
}

///|
test "hlpp: disconnected source and sink" {
  let edges = [(0, 1, 10L), (2, 3, 10L)]
  assert_eq(max_flow(4, 0, 3, edges), Some(0L))
}

///|
test "hlpp: reverse edges used" {
  // Classic example where reverse edges are needed for optimality.
  // 0 → 1 (10), 0 → 2 (10), 1 → 2 (5), 1 → 3 (5), 2 → 3 (10)
  // Max flow = 15: push 10 through 0→1→3 and 0→2→3, but 1→2→3 uses reverse.
  let edges = [(0, 1, 10L), (0, 2, 10L), (1, 2, 5L), (1, 3, 5L), (2, 3, 10L)]
  let result = max_flow(4, 0, 3, edges)
  match result {
    Some(f) => assert_true(f >= 15L && f <= 15L)
    None => abort("expected Some")
  }
}

///|
test "hlpp: invalid inputs" {
  assert_eq(max_flow(0, 0, 1, []), None)
  assert_eq(max_flow(4, -1, 3, []), None)
  assert_eq(max_flow(4, 0, 4, []), None)
  assert_eq(max_flow(4, 0, 0, []), None)
}

///|
test "hlpp: large capacity no overflow" {
  // Total flow = 3 * 2^40 ≈ 3.3 * 10^12, fits in Int64.
  let big_cap = 1099511627776L // 2^40
  let edges = [
    (0, 1, big_cap),
    (0, 2, big_cap),
    (0, 3, big_cap),
    (1, 4, big_cap),
    (2, 4, big_cap),
    (3, 4, big_cap),
  ]
  let result = max_flow(5, 0, 4, edges)
  match result {
    Some(f) => assert_eq(f, big_cap * 3L)
    None => abort("expected Some")
  }
}

///|
test "hlpp: medium graph known answer" {
  // A 6-vertex graph with a known max-flow of 23.
  // Constructed so that multiple augmenting paths and reverse edges are needed.
  //
  //   0 --(15)--> 1 --(12)--> 3 --(20)--> 5
  //   |           |           |
  //  (10)       (8)         (10)
  //   v           v           v
  //   2 --(10)--> 4 --(15)--> 5
  //   |           |
  //  (5)        (7)
  //   v           v
  //   4 --(15)--> 5
  let edges = [
    (0, 1, 15L),
    (0, 2, 10L),
    (1, 3, 12L),
    (1, 4, 8L),
    (2, 4, 10L),
    (2, 5, 5L),
    (3, 5, 20L),
    (4, 5, 15L),
    (4, 3, 7L),
  ]
  // Max flow: 0→1 sends 12 to 3 and 3 to 5, plus 0→2→4→5 (10+8=18 from 0).
  // 0 out capacity = 25. Sink in capacity = 5(2→5) + 20(3→5) + 15(4→5) = 40.
  // Min cut: {0} → {rest} = 25. So max flow = 25.
  let result = max_flow(6, 0, 5, edges)
  match result {
    Some(f) => assert_eq(f, 25L)
    None => abort("expected Some")
  }
}

///|
test "hlpp: dense graph stress" {
  // Complete graph K_10 with uniform capacity 5.
  // Max flow from 0 to 9 = min(9*5, 9*5) = 45 (9 parallel paths, each cap 5).
  let n = 10
  let edges : Array[(Int, Int, Int64)] = []
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      if i != j {
        edges.push((i, j, 5L))
      }
    }
  }
  let result = max_flow(n, 0, n - 1, edges)
  match result {
    Some(f) => assert_eq(f, 45L)
    None => abort("expected Some")
  }
}

///|
test "hlpp: graph with zero-capacity edges" {
  // Edges with zero capacity should be ignored.
  let edges = [(0, 1, 0L), (0, 1, 10L), (1, 2, 10L)]
  assert_eq(max_flow(3, 0, 2, edges), Some(10L))
}

///|
test "hlpp: self-loop ignored" {
  let edges = [(0, 0, 100L), (0, 1, 10L), (1, 2, 10L)]
  assert_eq(max_flow(3, 0, 2, edges), Some(10L))
}

///|
test "hlpp: parallel edges" {
  // Two parallel edges 0→1 with capacity 10 each should give max flow 20.
  let edges = [(0, 1, 10L), (0, 1, 10L), (1, 2, 20L)]
  assert_eq(max_flow(3, 0, 2, edges), Some(20L))
}
