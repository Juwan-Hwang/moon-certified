/// Minimum Cost Flow — Successive Shortest Path (SSP) algorithm.
///
/// The SSP algorithm solves the minimum cost flow (MCF) problem on a
/// directed graph by iteratively augmenting flow along the shortest path
/// from a supply node to a demand node in the residual graph.
///
/// ## Problem
/// Given a directed graph with:
/// - Per-arc cost `c` and capacity `cap`
/// - Per-node supply `b` (positive = source, negative = sink)
///
/// Find a flow `f` that satisfies:
/// - `0 ≤ f[e] ≤ cap[e]` for each arc
/// - `Σ outflow - Σ inflow = b[v]` for each node
/// - Minimises `Σ f[e] * c[e]`
///
/// ## Algorithm
/// 1. Build a residual graph: each arc (u,v,cost,cap) generates a forward
///    edge and a reverse edge with negated cost.
/// 2. Initialise excess[v] = supply[v] for each node.
/// 3. While there exists a node s with excess > 0:
///    a. Run SPFA (Shortest Path Faster Algorithm) from s to find the
///       shortest paths to all nodes in the residual graph.
///    b. Find a reachable node t with excess < 0.
///    c. Compute the bottleneck = min(excess[s], -excess[t], min residual
///       capacity along the path).
///    d. Augment flow along the path and update excesses.
/// 4. If all excesses are zero, the flow is feasible and optimal.
///    Otherwise, the problem is infeasible.
///
/// SPFA handles negative-cost arcs correctly and is the method of choice
/// when the graph may contain negative costs.
///
/// ## Complexity
/// - Time: O(S × n × m) where S is total supply, n is nodes, m is arcs.
///   Pseudo-polynomial but very efficient for moderate supply values.
/// - Space: O(n + m)
///
/// ## Overflow safety
/// All costs and flows use `Int64` to prevent overflow on large networks.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

///|
/// Result of a minimum cost flow computation.
pub struct MCFResult {
  /// Total cost of the minimum cost flow.
  total_cost : Int64
  /// Flow on each arc (same order as the input arcs).
  flows : FixedArray[Int64]
}

// ---------------------------------------------------------------------------
// Main algorithm
// ---------------------------------------------------------------------------

///|
/// Compute the minimum cost flow.
///
/// # Parameters
/// - `n`: number of nodes (0-indexed: 0 .. n-1).
/// - `arcs_u`: from-node of each arc.
/// - `arcs_v`: to-node of each arc.
/// - `arcs_cost`: per-unit cost of each arc.
/// - `arcs_cap`: capacity of each arc (upper bound).
/// - `supply`: supply/demand for each node. Positive = source, negative = sink.
///   Must sum to 0 for feasibility.
///
/// # Returns
/// `Some(MCFResult)` with total cost and per-arc flows, or `None` if
/// infeasible (supply imbalance or no feasible flow exists).
pub fn min_cost_flow(
  n : Int,
  arcs_u : FixedArray[Int],
  arcs_v : FixedArray[Int],
  arcs_cost : FixedArray[Int],
  arcs_cap : FixedArray[Int],
  supply : FixedArray[Int],
) -> MCFResult? {
  if n <= 0 {
    return Some(MCFResult::{ total_cost: 0L, flows: FixedArray::make(0, 0L) })
  }
  // Check supply balance.
  let mut total_supply = 0L
  for i = 0; i < n; i = i + 1 {
    total_supply = total_supply + supply[i].to_int64()
  }
  if total_supply != 0L {
    return None
  }
  let m = arcs_u.length()
  if m == 0 {
    // No arcs: feasible only if all supplies are zero.
    for i = 0; i < n; i = i + 1 {
      if supply[i] != 0 {
        return None
      }
    }
    return Some(MCFResult::{ total_cost: 0L, flows: FixedArray::make(0, 0L) })
  }
  // Build residual graph.
  // Each arc i generates:
  //   forward edge 2*i:   u → v, cost = c, cap = cap
  //   reverse edge 2*i+1: v → u, cost = -c, cap = 0
  // Paired edges are accessed via XOR: e ^ 1.
  let num_edges = 2 * m
  let edge_to = FixedArray::make(num_edges, 0)
  let edge_cost = FixedArray::make(num_edges, 0L)
  let edge_cap = FixedArray::make(num_edges, 0L)
  let edge_flow = FixedArray::make(num_edges, 0L)
  // Adjacency list: adj[u] = list of edge indices leaving u.
  let adj : Array[Array[Int]] = Array::makei(n, fn(_i) { [] })
  for i = 0; i < m; i = i + 1 {
    let u = arcs_u[i]
    let v = arcs_v[i]
    let c = arcs_cost[i].to_int64()
    let cap = arcs_cap[i].to_int64()
    let fwd = 2 * i
    let rev = 2 * i + 1
    edge_to[fwd] = v
    edge_cost[fwd] = c
    edge_cap[fwd] = cap
    edge_to[rev] = u
    edge_cost[rev] = -c
    edge_cap[rev] = 0L
    adj[u].push(fwd)
    adj[v].push(rev)
  }
  // Excess: positive = supply to push out, negative = demand to fill.
  let excess = FixedArray::makei(n, fn(i) { supply[i].to_int64() })
  // SSP main loop.
  let inf = 9223372036854775807L
  let max_iter = n * m + 1000
  let mut iter = 0
  while iter < max_iter {
    iter = iter + 1
    // Find a source node with positive excess.
    let mut src = -1
    for i = 0; i < n; i = i + 1 {
      if excess[i] > 0L {
        src = i
        break
      }
    }
    if src < 0 {
      break // All excesses satisfied — optimal.
    }
    // Run SPFA from src to find shortest paths in the residual graph.
    let dist = FixedArray::make(n, inf)
    let in_queue = FixedArray::make(n, false)
    let cnt = FixedArray::make(n, 0)
    let prev_edge = FixedArray::make(n, -1)
    let queue : Array[Int] = [src]
    dist[src] = 0L
    in_queue[src] = true
    cnt[src] = 1
    let mut negative_cycle = false
    while queue.length() > 0 {
      let u = queue[0]
      ignore(queue.remove(0))
      in_queue[u] = false
      let edges = adj[u]
      for eidx = 0; eidx < edges.length(); eidx = eidx + 1 {
        let e = edges[eidx]
        let residual = edge_cap[e] - edge_flow[e]
        if residual <= 0L {
          continue
        }
        let v = edge_to[e]
        let nd = dist[u] + edge_cost[e]
        if nd < dist[v] {
          dist[v] = nd
          prev_edge[v] = e
          if !in_queue[v] {
            cnt[v] = cnt[v] + 1
            if cnt[v] > n {
              negative_cycle = true
              break
            }
            in_queue[v] = true
            queue.push(v)
          }
        }
      }
      if negative_cycle {
        break
      }
    }
    if negative_cycle {
      return None // Negative cycle detected — infeasible.
    }
    // Find a sink node with negative excess reachable from src.
    let mut sink = -1
    for i = 0; i < n; i = i + 1 {
      if excess[i] < 0L && dist[i] < inf {
        sink = i
        break
      }
    }
    if sink < 0 {
      return None // No reachable sink — infeasible.
    }
    // Find bottleneck: min of source excess, -sink excess, min residual
    // capacity along the path from src to sink.
    let mut bottleneck = excess[src]
    if -excess[sink] < bottleneck {
      bottleneck = -excess[sink]
    }
    // Walk the path from sink back to src via prev_edge.
    let mut v = sink
    while v != src {
      let e = prev_edge[v]
      if e < 0 {
        return None // Path broken — should not happen.
      }
      let residual = edge_cap[e] - edge_flow[e]
      if residual < bottleneck {
        bottleneck = residual
      }
      // The edge e goes from u to v. Its reverse edge e^1 goes from v to u.
      // So edge_to[e ^ 1] = u, the previous node in the path.
      v = edge_to[e ^ 1]
    }
    if bottleneck <= 0L {
      return None // Degenerate — should not happen.
    }
    // Augment flow along the path.
    v = sink
    while v != src {
      let e = prev_edge[v]
      edge_flow[e] = edge_flow[e] + bottleneck
      edge_flow[e ^ 1] = edge_flow[e ^ 1] - bottleneck
      v = edge_to[e ^ 1]
    }
    // Update excesses.
    excess[src] = excess[src] - bottleneck
    excess[sink] = excess[sink] + bottleneck
  }
  // Check feasibility: all excesses must be zero.
  for i = 0; i < n; i = i + 1 {
    if excess[i] != 0L {
      return None
    }
  }
  // Extract real arc flows (forward edges only) and compute total cost.
  let real_flows = FixedArray::makei(m, fn(i) { edge_flow[2 * i] })
  let mut total_cost = 0L
  for i = 0; i < m; i = i + 1 {
    total_cost = total_cost + real_flows[i] * arcs_cost[i].to_int64()
  }
  Some(MCFResult::{ total_cost, flows: real_flows })
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "min_cost_flow: simple 2-node flow" {
  // Node 0: supply 5, Node 1: demand 5
  // Arc 0→1: cost 3, cap 10
  let result = min_cost_flow(
    2,
    FixedArray::make(1, 0),
    FixedArray::make(1, 1),
    FixedArray::make(1, 3),
    FixedArray::make(1, 10),
    FixedArray::makei(2, fn(i) { if i == 0 { 5 } else { -5 } }),
  )
  assert_true(result is Some(_))
  match result {
    Some(r) => {
      assert_eq(r.total_cost, 15L) // 5 * 3
      assert_eq(r.flows[0], 5L)
    }
    None => assert_true(false)
  }
}

///|
test "min_cost_flow: two paths" {
  // Node 0: supply 10, Node 2: demand 10
  // Arc 0: 0→1, cost 1, cap 10
  // Arc 1: 1→2, cost 1, cap 10
  // Arc 2: 0→2, cost 5, cap 10
  // Optimal: send all through 0→1→2 (cost 2 per unit = 20 total)
  let u = FixedArray::makei(3, fn(i) {
    match i {
      0 => 0
      1 => 1
      _ => 0
    }
  })
  let v = FixedArray::makei(3, fn(i) {
    match i {
      0 => 1
      1 => 2
      _ => 2
    }
  })
  let c = FixedArray::makei(3, fn(i) {
    match i {
      0 => 1
      1 => 1
      _ => 5
    }
  })
  let cap = FixedArray::makei(3, fn(_i) { 10 })
  let sup = FixedArray::makei(3, fn(i) {
    if i == 0 {
      10
    } else if i == 2 {
      -10
    } else {
      0
    }
  })
  let result = min_cost_flow(3, u, v, c, cap, sup)
  assert_true(result is Some(_))
  match result {
    Some(r) => {
      assert_eq(r.total_cost, 20L)
      assert_eq(r.flows[0], 10L)
      assert_eq(r.flows[1], 10L)
      assert_eq(r.flows[2], 0L)
    }
    None => assert_true(false)
  }
}

///|
test "min_cost_flow: capacity constrained" {
  // Node 0: supply 10, Node 2: demand 10
  // Arc 0: 0→1, cost 1, cap 4
  // Arc 1: 1→2, cost 1, cap 4
  // Arc 2: 0→2, cost 5, cap 10
  // Optimal: 4 through 0→1→2 (cost 2*4=8), 6 through 0→2 (cost 5*6=30) = 38
  let u = FixedArray::makei(3, fn(i) {
    match i {
      0 => 0
      1 => 1
      _ => 0
    }
  })
  let v = FixedArray::makei(3, fn(i) {
    match i {
      0 => 1
      1 => 2
      _ => 2
    }
  })
  let c = FixedArray::makei(3, fn(i) {
    match i {
      0 => 1
      1 => 1
      _ => 5
    }
  })
  let cap = FixedArray::makei(3, fn(i) {
    match i {
      0 => 4
      1 => 4
      _ => 10
    }
  })
  let sup = FixedArray::makei(3, fn(i) {
    if i == 0 {
      10
    } else if i == 2 {
      -10
    } else {
      0
    }
  })
  let result = min_cost_flow(3, u, v, c, cap, sup)
  assert_true(result is Some(_))
  match result {
    Some(r) => {
      assert_eq(r.total_cost, 38L)
      assert_eq(r.flows[0], 4L)
      assert_eq(r.flows[1], 4L)
      assert_eq(r.flows[2], 6L)
    }
    None => assert_true(false)
  }
}

///|
test "min_cost_flow: infeasible supply" {
  let result = min_cost_flow(
    2,
    FixedArray::make(1, 0),
    FixedArray::make(1, 1),
    FixedArray::make(1, 1),
    FixedArray::make(1, 10),
    FixedArray::makei(2, fn(i) { if i == 0 { 5 } else { 0 } }),
  )
  assert_true(result is None)
}

///|
test "min_cost_flow: single node no arcs" {
  let result = min_cost_flow(
    1,
    FixedArray::make(0, 0),
    FixedArray::make(0, 0),
    FixedArray::make(0, 0),
    FixedArray::make(0, 0),
    FixedArray::make(1, 0),
  )
  assert_true(result is Some(_))
  match result {
    Some(r) => assert_eq(r.total_cost, 0L)
    None => assert_true(false)
  }
}

///|
test "min_cost_flow: empty graph" {
  let result = min_cost_flow(
    0,
    FixedArray::make(0, 0),
    FixedArray::make(0, 0),
    FixedArray::make(0, 0),
    FixedArray::make(0, 0),
    FixedArray::make(0, 0),
  )
  assert_true(result is Some(_))
}

///|
test "min_cost_flow: negative cost arc" {
  // Node 0: supply 3, Node 2: demand 3
  // Arc 0: 0→1, cost -2, cap 5  (negative cost is fine)
  // Arc 1: 1→2, cost 1, cap 5
  // Optimal: send 3 through 0→1→2 (cost -2+1 = -1 per unit = -3 total)
  let u = FixedArray::makei(2, fn(i) {
    match i {
      0 => 0
      _ => 1
    }
  })
  let v = FixedArray::makei(2, fn(i) {
    match i {
      0 => 1
      _ => 2
    }
  })
  let c = FixedArray::makei(2, fn(i) {
    match i {
      0 => -2
      _ => 1
    }
  })
  let cap = FixedArray::makei(2, fn(_i) { 5 })
  let sup = FixedArray::makei(3, fn(i) {
    if i == 0 {
      3
    } else if i == 2 {
      -3
    } else {
      0
    }
  })
  let result = min_cost_flow(3, u, v, c, cap, sup)
  assert_true(result is Some(_))
  match result {
    Some(r) => {
      assert_eq(r.total_cost, -3L)
      assert_eq(r.flows[0], 3L)
      assert_eq(r.flows[1], 3L)
    }
    None => assert_true(false)
  }
}

///|
test "min_cost_flow: multiple sources and sinks" {
  // Nodes: 0 (supply 5), 1 (supply 3), 2 (demand 4), 3 (demand 4)
  // Arc 0: 0→2, cost 1, cap 10
  // Arc 1: 0→3, cost 3, cap 10
  // Arc 2: 1→2, cost 2, cap 10
  // Arc 3: 1→3, cost 1, cap 10
  // Optimal:
  //   0→2: 5 (cost 5), 1→3: 3 (cost 3), need 1 more to node 2
  //   1→2: 1 (cost 2) — but 1 has only 3 supply, all used on 1→3
  //   Actually: send 4 to node 2 and 4 to node 3
  //   0→2: 4 (cost 4), 0→3: 1 (cost 3)
  //   1→3: 3 (cost 3)
  //   Total: 4 + 3 + 3 = 10
  //   Or: 0→2: 5, 1→2: 0, 0→3: 0, 1→3: 3, need 1 more for node 2
  //   → 1→2: 1 (cost 2), 1→3: 2 (cost 2) → 5+2+2 = 9... wait
  //   Actually optimal: 0→2:5 (5), 1→2:0, 0→3:0, 1→3:3 (3), need 1 more for node 2
  //   1→2:1 (2) → but 1 has supply 3, 1+2=3 ✓
  //   → total: 5 + 2 + 3 = 10... no
  //   Let me recompute: 0→2 cost1 * 5 = 5, 1→3 cost1 * 3 = 3, 1→2 cost2 * 1 = 2 → no wait 1→2 has cost 2
  //   Actually: 1→3 cost 1 * 3 = 3, 1→2 cost 2 * 0 = 0, need 4 for node 2
  //   0→2 cost 1 * 4 = 4, 0→3 cost 3 * 1 = 3, total = 4 + 3 + 3 = 10
  //   Or: 0→2 cost 1 * 5 = 5, 0→3 cost 3 * 0 = 0, 1→3 cost 1 * 3 = 3, 1→2 cost 2 * 1 = 2
  //   But node 2 gets 5+1=6 > 4, too much.
  //   So: 0→2:4, 0→3:1, 1→2:0, 1→3:3 → 4+3+3=10
  //   Or: 0→2:5, 0→3:0, 1→2:0, 1→3:3 → node 2 gets 5 (too much, demand 4)
  //   So must be: 0→2:4, 0→3:1, 1→3:3, 1→2:0 → total 4+3+0+3=10
  //   Or: 0→2:4, 0→3:1, 1→2:0, 1→3:3 → cost = 4*1 + 1*3 + 0*2 + 3*1 = 10
  //   Another option: 0→2:4, 0→3:1, 1→2:0, 1→3:3 → 10
  //   Or: 0→2:5, 1→2:-1 (reverse)? No, that doesn't make sense.
  //   OK the optimal is 10.
  let u = FixedArray::makei(4, fn(i) {
    match i {
      0 => 0
      1 => 0
      2 => 1
      _ => 1
    }
  })
  let v = FixedArray::makei(4, fn(i) {
    match i {
      0 => 2
      1 => 3
      2 => 2
      _ => 3
    }
  })
  let c = FixedArray::makei(4, fn(i) {
    match i {
      0 => 1
      1 => 3
      2 => 2
      _ => 1
    }
  })
  let cap = FixedArray::makei(4, fn(_i) { 10 })
  let sup = FixedArray::makei(4, fn(i) {
    match i {
      0 => 5
      1 => 3
      2 => -4
      _ => -4
    }
  })
  let result = min_cost_flow(4, u, v, c, cap, sup)
  assert_true(result is Some(_))
  match result {
    Some(r) => assert_eq(r.total_cost, 10L)
    None => assert_true(false)
  }
}

///|
test "min_cost_flow: zero supply feasible" {
  // All supplies zero — trivially feasible with zero flow.
  let result = min_cost_flow(
    3,
    FixedArray::makei(2, fn(i) { i }),
    FixedArray::makei(2, fn(i) { i + 1 }),
    FixedArray::makei(2, fn(_i) { 1 }),
    FixedArray::makei(2, fn(_i) { 10 }),
    FixedArray::make(3, 0),
  )
  assert_true(result is Some(_))
  match result {
    Some(r) => {
      assert_eq(r.total_cost, 0L)
      assert_eq(r.flows[0], 0L)
      assert_eq(r.flows[1], 0L)
    }
    None => assert_true(false)
  }
}
