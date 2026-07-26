/// Network Flow with Lower and Upper Bounds.
///
/// Extends standard max-flow to handle edges that have both a **lower bound**
/// (minimum required flow) and an **upper bound** (capacity). This is essential
/// for production scheduling, resource allocation, and feasibility checking.
///
/// ## Algorithm
///
/// The standard technique transforms bounded flow into an unbounded problem
/// by introducing a **super source** and **super sink**:
///
/// 1. For each edge `e = (u, v)` with bounds `[lo, hi]`, create a regular
///    edge with capacity `hi - lo` and record `excess[u] -= lo, excess[v] += lo`.
/// 2. Add edges from super source `S` to vertices with `excess > 0`.
/// 3. Add edges from vertices with `excess < 0` to super sink `T`.
/// 4. Run max-flow from `S` to `T`. If all super-source edges are saturated,
///    the bounded flow is feasible.
///
/// For **bounded max-flow**, after feasibility, the t→s edge is removed and
/// additional max-flow is pushed from `s` to `t` on the **residual network**
/// (reusing the same edge array from the feasibility phase, so the feasibility
/// flow is preserved).
///
/// ## Complexity
/// - Time: O(V² · E) for Dinic-based max-flow.
/// - Space: O(V + E).
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

///|
/// A bounded edge: flow must be in `[lower, upper]`.
pub struct BoundedEdge {
  from : Int
  to : Int
  lower : Int
  upper : Int
}

///|
/// Construct a [`BoundedEdge`].
pub fn bounded_edge(
  from : Int,
  to : Int,
  lower : Int,
  upper : Int,
) -> BoundedEdge {
  { from, to, lower, upper }
}

///|
/// Internal mutable edge for Dinic.
priv struct MEdge {
  to : Int
  mut cap : Int // residual capacity
}

///|
/// Result of a bounded flow computation.
pub struct BoundedFlowResult {
  priv feasible : Bool
  priv total_flow : Int
  priv n : Int
  priv edge_flows : FixedArray[Int] // Actual flow on each original edge
}

///|
/// Whether the bounded flow is feasible.
pub fn is_feasible(r : BoundedFlowResult) -> Bool {
  r.feasible
}

///|
/// The actual flow on edge `i` (0-indexed into the original edge list).
///
/// Returns the **real** flow (lower bound + additional flow pushed through
/// the edge), NOT just the lower bound.
pub fn edge_flow(r : BoundedFlowResult, i : Int) -> Int {
  if i < 0 || i >= r.edge_flows.length() {
    return 0
  }
  r.edge_flows[i]
}

///|
/// Total flow from source to sink (for bounded max-flow).
pub fn total_flow(r : BoundedFlowResult) -> Int {
  r.total_flow
}

///|
/// Number of vertices in the flow network.
pub fn vertex_count(r : BoundedFlowResult) -> Int {
  r.n
}

// ---------------------------------------------------------------------------
// Dinic max-flow (internal, returns edge array for flow extraction)
// ---------------------------------------------------------------------------

///|
/// Dinic context: edges + adjacency list + level/iter arrays.
priv struct DinicCtx {
  edges : Array[MEdge]
  head : FixedArray[Array[Int]] // head[v] = list of edge indices from v
  level : FixedArray[Int]
  iter : FixedArray[Int]
  n : Int
}

///|
/// Build the Dinic flow network from capacity edges.
/// Returns the DinicCtx with the edge array.
fn build_ctx(n : Int, edges : Array[(Int, Int, Int)]) -> DinicCtx {
  let m = edges.length()
  let edge_arr : Array[MEdge] = []
  let head : FixedArray[Array[Int]] = FixedArray::makei(n, fn(_i) { [] })
  for i = 0; i < m; i = i + 1 {
    let (u, v, c) = edges[i]
    edge_arr.push(MEdge::{ to: v, cap: c })
    edge_arr.push(MEdge::{ to: u, cap: 0 })
    head[u].push(2 * i)
    head[v].push(2 * i + 1)
  }
  {
    edges: edge_arr,
    head,
    level: FixedArray::make(n, -1),
    iter: FixedArray::make(n, 0),
    n,
  }
}

///|
fn bfs_level(ctx : DinicCtx, s : Int, t : Int) -> Bool {
  for i = 0; i < ctx.n; i = i + 1 {
    ctx.level[i] = -1
  }
  ctx.level[s] = 0
  let queue : Array[Int] = [s]
  let mut front = 0
  while front < queue.length() {
    let u = queue[front]
    front = front + 1
    for idx = 0; idx < ctx.head[u].length(); idx = idx + 1 {
      let eid = ctx.head[u][idx]
      let e = ctx.edges[eid]
      if e.cap > 0 && ctx.level[e.to] == -1 {
        ctx.level[e.to] = ctx.level[u] + 1
        queue.push(e.to)
      }
    }
  }
  ctx.level[t] != -1
}

///|
fn dfs_dinic(ctx : DinicCtx, u : Int, t : Int, f : Int) -> Int {
  if u == t {
    return f
  }
  let mut flow = 0
  let mut pushed = f
  while ctx.iter[u] < ctx.head[u].length() && pushed > 0 {
    let eid = ctx.head[u][ctx.iter[u]]
    let e = ctx.edges[eid]
    if e.cap > 0 && ctx.level[e.to] == ctx.level[u] + 1 {
      let d = dfs_dinic(
        ctx,
        e.to,
        t,
        if pushed < e.cap {
          pushed
        } else {
          e.cap
        },
      )
      if d > 0 {
        ctx.edges[eid].cap = ctx.edges[eid].cap - d
        ctx.edges[eid ^ 1].cap = ctx.edges[eid ^ 1].cap + d
        pushed = pushed - d
        flow = flow + d
      } else {
        ctx.level[e.to] = -1
      }
    }
    ctx.iter[u] = ctx.iter[u] + 1
  }
  flow
}

///|
/// Run Dinic max-flow from `s` to `t` on the given context.
/// Modifies the context's edge array (residual capacities).
/// Returns the total flow.
fn dinic_run(ctx : DinicCtx, s : Int, t : Int) -> Int {
  if s == t {
    return 0
  }
  let mut total = 0
  while bfs_level(ctx, s, t) {
    for i = 0; i < ctx.n; i = i + 1 {
      ctx.iter[i] = 0
    }
    let mut f = dfs_dinic(ctx, s, t, 2147483647)
    while f > 0 {
      total = total + f
      f = dfs_dinic(ctx, s, t, 2147483647)
    }
  }
  total
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

///|
/// Check if a feasible flow exists satisfying all edge bounds.
///
/// # Parameters
/// - `n`: number of vertices.
/// - `bounded_edges`: the bounded edges.
/// - `s`: source vertex (or -1 for circulation feasibility).
/// - `t`: sink vertex (or -1 for circulation feasibility).
///
/// # Returns
/// A [`BoundedFlowResult`] indicating feasibility and the **actual** edge flows
/// (lower bound + additional flow pushed through each edge).
pub fn feasible_flow(
  n : Int,
  bounded_edges : FixedArray[BoundedEdge],
  s : Int,
  t : Int,
) -> BoundedFlowResult {
  let m = bounded_edges.length()
  if n <= 0 || m == 0 {
    return BoundedFlowResult::{
      feasible: true,
      total_flow: 0,
      n: 0,
      edge_flows: FixedArray::make(0, 0),
    }
  }
  // Super source S = n, super sink T = n+1.
  let sn = n + 2
  let ss = n
  let st = n + 1
  let excess = FixedArray::make(n, 0)
  let net_edges : Array[(Int, Int, Int)] = []
  let edge_lower = FixedArray::make(m, 0)
  // Track which network edge index corresponds to each original edge.
  // original_edge_idx[i] = index in net_edges for the i-th bounded edge.
  let orig_edge_idx : Array[Int] = []
  for i = 0; i < m; i = i + 1 {
    let e = bounded_edges[i]
    if e.lower > e.upper || e.from < 0 || e.from >= n || e.to < 0 || e.to >= n {
      return BoundedFlowResult::{
        feasible: false,
        total_flow: 0,
        n: 0,
        edge_flows: FixedArray::make(0, 0),
      }
    }
    net_edges.push((e.from, e.to, e.upper - e.lower))
    orig_edge_idx.push(net_edges.length() - 1)
    excess[e.from] = excess[e.from] - e.lower
    excess[e.to] = excess[e.to] + e.lower
    edge_lower[i] = e.lower
  }
  // If s and t are specified, add an edge t→s with infinite capacity
  // to convert to a circulation problem.
  if s >= 0 && t >= 0 && s < n && t < n {
    net_edges.push((t, s, 2147483647))
  } else {
    // Add a dummy edge that we'll ignore.
    net_edges.push((0, 0, 0))
  }
  // Add super source/sink edges for excess.
  let mut required_total = 0
  for v = 0; v < n; v = v + 1 {
    if excess[v] > 0 {
      net_edges.push((ss, v, excess[v]))
      required_total = required_total + excess[v]
    } else if excess[v] < 0 {
      net_edges.push((v, st, -excess[v]))
    }
  }
  // Build and run Dinic.
  let ctx = build_ctx(sn, net_edges)
  let flow = dinic_run(ctx, ss, st)
  let feasible = flow >= required_total
  // Extract actual edge flows: actual = lower + (initial_cap - residual_cap)
  // = lower + (upper - lower - residual) = lower + flow_pushed_through_edge
  // flow_pushed = initial_cap - current_cap (the forward edge's consumed capacity)
  let edge_flows = FixedArray::make(m, 0)
  for i = 0; i < m; i = i + 1 {
    let net_idx = orig_edge_idx[i]
    // Forward edge is at index 2*net_idx in the edges array.
    let fwd_edge = ctx.edges[2 * net_idx]
    let initial_cap = bounded_edges[i].upper - bounded_edges[i].lower
    let flow_pushed = initial_cap - fwd_edge.cap
    edge_flows[i] = edge_lower[i] + flow_pushed
  }
  BoundedFlowResult::{ feasible, total_flow: flow, n, edge_flows }
}

///|
/// Compute the maximum flow from `s` to `t` with lower and upper bounds.
///
/// After checking feasibility, this computes the additional max-flow that
/// can be pushed through the residual network. The total flow includes
/// both the feasibility flow and the additional max-flow.
///
/// The **actual edge flows** returned are the real flows (lower + additional),
/// and the **total_flow** is the sum of lower bounds on the s-t cut plus
/// the additional flow pushed.
pub fn bounded_max_flow(
  n : Int,
  bounded_edges : FixedArray[BoundedEdge],
  s : Int,
  t : Int,
) -> BoundedFlowResult {
  let m = bounded_edges.length()
  if n <= 0 || m == 0 {
    return BoundedFlowResult::{
      feasible: true,
      total_flow: 0,
      n: 0,
      edge_flows: FixedArray::make(0, 0),
    }
  }
  // Build the full network with t→s edge for circulation feasibility.
  let sn = n + 2
  let ss = n
  let st = n + 1
  let excess = FixedArray::make(n, 0)
  let net_edges : Array[(Int, Int, Int)] = []
  let edge_lower = FixedArray::make(m, 0)
  let orig_edge_idx : Array[Int] = []
  for i = 0; i < m; i = i + 1 {
    let e = bounded_edges[i]
    if e.lower > e.upper || e.from < 0 || e.from >= n || e.to < 0 || e.to >= n {
      return BoundedFlowResult::{
        feasible: false,
        total_flow: 0,
        n: 0,
        edge_flows: FixedArray::make(0, 0),
      }
    }
    net_edges.push((e.from, e.to, e.upper - e.lower))
    orig_edge_idx.push(net_edges.length() - 1)
    excess[e.from] = excess[e.from] - e.lower
    excess[e.to] = excess[e.to] + e.lower
    edge_lower[i] = e.lower
  }
  // t→s edge for circulation.
  let ts_edge_idx = net_edges.length()
  net_edges.push((t, s, 2147483647))
  // Super source/sink edges.
  let mut required_total = 0
  for v = 0; v < n; v = v + 1 {
    if excess[v] > 0 {
      net_edges.push((ss, v, excess[v]))
      required_total = required_total + excess[v]
    } else if excess[v] < 0 {
      net_edges.push((v, st, -excess[v]))
    }
  }
  // Build context and run feasibility max-flow.
  let ctx = build_ctx(sn, net_edges)
  let feas_flow = dinic_run(ctx, ss, st)
  let feasible = feas_flow >= required_total
  if !feasible {
    return BoundedFlowResult::{
      feasible: false,
      total_flow: 0,
      n,
      edge_flows: FixedArray::make(m, 0),
    }
  }
  // Remove the t→s edge by setting its capacity to 0.
  // The t→s edge is at index 2*ts_edge_idx (forward) and 2*ts_edge_idx+1 (reverse).
  // Set both to 0 so no more flow can go through it.
  ctx.edges[2 * ts_edge_idx].cap = 0
  ctx.edges[2 * ts_edge_idx + 1].cap = 0
  // Now run additional max-flow from s to t on the residual network.
  // This reuses the same context, so the feasibility flow is preserved.
  let _additional = dinic_run(ctx, s, t)
  // Extract actual edge flows from the residual network.
  let edge_flows = FixedArray::make(m, 0)
  for i = 0; i < m; i = i + 1 {
    let net_idx = orig_edge_idx[i]
    let fwd_edge = ctx.edges[2 * net_idx]
    let initial_cap = bounded_edges[i].upper - bounded_edges[i].lower
    let flow_pushed = initial_cap - fwd_edge.cap
    edge_flows[i] = edge_lower[i] + flow_pushed
  }
  // Total flow from s to t = flow on the (removed) t→s edge before removal.
  // We can compute it as: sum of flows on edges leaving s minus flows entering s
  // (excluding the t→s reverse edge).
  // A simpler approach: total = sum of (edge_flows on edges out of s) - sum of
  // (edge_flows on edges into s from non-t vertices).
  // But the most direct: total flow = additional + (feasibility flow on s-t path).
  // The feasibility flow on s-t path = flow that was going through the t→s edge.
  // Since we set it to 0, we lost that info. Let's compute it differently.
  // Total flow from s to t = net outflow from s = sum of flows on edges (s, v) - sum of flows on edges (v, s).
  let mut total_s_out = 0
  let mut total_s_in = 0
  for i = 0; i < m; i = i + 1 {
    let e = bounded_edges[i]
    if e.from == s {
      total_s_out = total_s_out + edge_flows[i]
    }
    if e.to == s {
      total_s_in = total_s_in + edge_flows[i]
    }
  }
  let total = total_s_out - total_s_in
  BoundedFlowResult::{ feasible: true, total_flow: total, n, edge_flows }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "bounded_flow: feasible circulation" {
  // Simple cycle: 0→1 [1,3], 1→0 [1,3]. Always feasible.
  let n = 2
  let edges = FixedArray::make(2, bounded_edge(0, 0, 0, 0))
  edges[0] = bounded_edge(0, 1, 1, 3)
  edges[1] = bounded_edge(1, 0, 1, 3)
  let result = feasible_flow(n, edges, -1, -1)
  assert_true(is_feasible(result))
}

///|
test "bounded_flow: infeasible circulation" {
  // 0→1 [5,10], 1→0 [1,3]. Need 5 on 0→1 but only 3 back. Infeasible.
  let n = 2
  let edges = FixedArray::make(2, bounded_edge(0, 0, 0, 0))
  edges[0] = bounded_edge(0, 1, 5, 10)
  edges[1] = bounded_edge(1, 0, 1, 3)
  let result = feasible_flow(n, edges, -1, -1)
  assert_false(is_feasible(result))
}

///|
test "bounded_flow: feasible s-t flow" {
  // 0→1 [2,5], 1→2 [2,5]. s=0, t=2. Feasible.
  let n = 3
  let edges = FixedArray::make(2, bounded_edge(0, 0, 0, 0))
  edges[0] = bounded_edge(0, 1, 2, 5)
  edges[1] = bounded_edge(1, 2, 2, 5)
  let result = feasible_flow(n, edges, 0, 2)
  assert_true(is_feasible(result))
}

///|
test "bounded_flow: infeasible s-t flow" {
  // 0→1 [5,10], 1→2 [1,3]. Lower bound on 0→1 exceeds capacity of 1→2.
  let n = 3
  let edges = FixedArray::make(2, bounded_edge(0, 0, 0, 0))
  edges[0] = bounded_edge(0, 1, 5, 10)
  edges[1] = bounded_edge(1, 2, 1, 3)
  let result = feasible_flow(n, edges, 0, 2)
  assert_false(is_feasible(result))
}

///|
test "bounded_flow: simple path feasibility" {
  // Single edge 0→1 [0, 10]. Feasible.
  let n = 2
  let edges = FixedArray::make(1, bounded_edge(0, 1, 0, 10))
  let result = feasible_flow(n, edges, 0, 1)
  assert_true(is_feasible(result))
}

///|
test "bounded_flow: triangle feasibility" {
  // 0→1 [1,3], 1→2 [1,3], 0→2 [1,3]. s=0, t=2.
  let n = 3
  let edges = FixedArray::make(3, bounded_edge(0, 0, 0, 0))
  edges[0] = bounded_edge(0, 1, 1, 3)
  edges[1] = bounded_edge(1, 2, 1, 3)
  edges[2] = bounded_edge(0, 2, 1, 3)
  let result = feasible_flow(n, edges, 0, 2)
  assert_true(is_feasible(result))
}

///|
test "bounded_flow: edge_flow returns actual flow not lower bound" {
  // 0→1 [3,10], 1→2 [3,10]. s=0, t=2.
  // Feasible flow must send at least 3 on each edge.
  // Actual flow should be >= 3, not just 3.
  let n = 3
  let edges = FixedArray::make(2, bounded_edge(0, 0, 0, 0))
  edges[0] = bounded_edge(0, 1, 3, 10)
  edges[1] = bounded_edge(1, 2, 3, 10)
  let result = feasible_flow(n, edges, 0, 2)
  assert_true(is_feasible(result))
  // Each edge must carry at least its lower bound.
  assert_true(edge_flow(result, 0) >= 3)
  assert_true(edge_flow(result, 1) >= 3)
  // Flows must not exceed upper bounds.
  assert_true(edge_flow(result, 0) <= 10)
  assert_true(edge_flow(result, 1) <= 10)
  // Flow conservation: flow on edge 0 == flow on edge 1.
  assert_eq(edge_flow(result, 0), edge_flow(result, 1))
}

///|
test "bounded_flow: edge_flow respects bounds with nonzero lower" {
  // 0→1 [5,8], 1→2 [5,8], 0→2 [0,3]. s=0, t=2.
  // The actual flow must be in [5,8] for edges 0 and 1.
  let n = 3
  let edges = FixedArray::make(3, bounded_edge(0, 0, 0, 0))
  edges[0] = bounded_edge(0, 1, 5, 8)
  edges[1] = bounded_edge(1, 2, 5, 8)
  edges[2] = bounded_edge(0, 2, 0, 3)
  let result = feasible_flow(n, edges, 0, 2)
  assert_true(is_feasible(result))
  // Verify bounds on each edge.
  assert_true(edge_flow(result, 0) >= 5)
  assert_true(edge_flow(result, 0) <= 8)
  assert_true(edge_flow(result, 1) >= 5)
  assert_true(edge_flow(result, 1) <= 8)
  assert_true(edge_flow(result, 2) >= 0)
  assert_true(edge_flow(result, 2) <= 3)
}

///|
test "bounded_max_flow: simple path" {
  // 0→1 [0,10], 1→2 [0,10]. Max flow = 10.
  let n = 3
  let edges = FixedArray::make(2, bounded_edge(0, 0, 0, 0))
  edges[0] = bounded_edge(0, 1, 0, 10)
  edges[1] = bounded_edge(1, 2, 0, 10)
  let result = bounded_max_flow(n, edges, 0, 2)
  assert_true(is_feasible(result))
  assert_eq(total_flow(result), 10)
}

///|
test "bounded_max_flow: bottleneck edge" {
  // 0→1 [0,10], 1→2 [0,5]. Max flow = 5.
  let n = 3
  let edges = FixedArray::make(2, bounded_edge(0, 0, 0, 0))
  edges[0] = bounded_edge(0, 1, 0, 10)
  edges[1] = bounded_edge(1, 2, 0, 5)
  let result = bounded_max_flow(n, edges, 0, 2)
  assert_true(is_feasible(result))
  assert_eq(total_flow(result), 5)
}

///|
test "bounded_max_flow: with nonzero lower bounds" {
  // 0→1 [3,10], 1→2 [3,10]. Max flow = 10.
  // Total flow must be at least 3 (lower bound) and at most 10 (upper bound).
  let n = 3
  let edges = FixedArray::make(2, bounded_edge(0, 0, 0, 0))
  edges[0] = bounded_edge(0, 1, 3, 10)
  edges[1] = bounded_edge(1, 2, 3, 10)
  let result = bounded_max_flow(n, edges, 0, 2)
  assert_true(is_feasible(result))
  // Max flow should be 10 (the upper bound).
  assert_eq(total_flow(result), 10)
  // Each edge should carry exactly 10.
  assert_eq(edge_flow(result, 0), 10)
  assert_eq(edge_flow(result, 1), 10)
}

///|
test "bounded_max_flow: infeasible returns false" {
  // 0→1 [5,10], 1→2 [1,3]. Lower bound 5 > capacity 3. Infeasible.
  let n = 3
  let edges = FixedArray::make(2, bounded_edge(0, 0, 0, 0))
  edges[0] = bounded_edge(0, 1, 5, 10)
  edges[1] = bounded_edge(1, 2, 1, 3)
  let result = bounded_max_flow(n, edges, 0, 2)
  assert_false(is_feasible(result))
}

///|
test "bounded_max_flow: parallel paths" {
  // 0→1 [0,5], 0→2 [0,5], 1→3 [0,5], 2→3 [0,5]. Max flow = 10.
  let n = 4
  let edges = FixedArray::make(4, bounded_edge(0, 0, 0, 0))
  edges[0] = bounded_edge(0, 1, 0, 5)
  edges[1] = bounded_edge(0, 2, 0, 5)
  edges[2] = bounded_edge(1, 3, 0, 5)
  edges[3] = bounded_edge(2, 3, 0, 5)
  let result = bounded_max_flow(n, edges, 0, 3)
  assert_true(is_feasible(result))
  assert_eq(total_flow(result), 10)
}
