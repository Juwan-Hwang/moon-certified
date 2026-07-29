/// Push-Relabel maximum flow algorithm (Goldberg-Tarjan).
///
/// Uses the "highest-label" relabel-to-front variant with gap heuristic.
/// Maintains a preflow and pushes excess flow toward the sink.
///
/// ## Performance
/// - O(V²√E) with highest-label selection
/// - O(V²E) with FIFO selection
///
/// ## References
/// - Goldberg, A.V. and Tarjan, R.E. "A new approach to the maximum-flow problem."
///   Journal of the ACM, 1988.
///
/// `proof-enabled` is `false`.

///|
/// Edge in the flow network.
struct PREdge {
  to : Int
  cap : Int
  mut flow : Int
  rev : Int // index of reverse edge in `to`'s adjacency list
}

///|
/// Push-Relabel max-flow solver.
///
/// Capacities are `Int`; total flow is accumulated in `Int64`.
pub struct PushRelabel {
  n : Int
  adj : Array[Array[PREdge]]
  height : Array[Int]
  excess : Array[Int64]
  count : Array[Int] // count of nodes at each height (for gap heuristic)
}

///|
/// Create a new PushRelabel solver for `n` vertices.
pub fn new(n : Int) -> PushRelabel {
  let adj : Array[Array[PREdge]] = []
  let height = []
  let excess = []
  let count_size = if n > 0 { 2 * n + 2 } else { 2 }
  let count = Array::make(count_size, 0)
  for i = 0; i < n; i = i + 1 {
    adj.push([])
    height.push(0)
    excess.push(0L)
  }
  { n, adj, height, excess, count }
}

///|
/// Add a directed edge from `u` to `v` with capacity `cap`.
/// A reverse edge with 0 capacity is added automatically.
pub fn PushRelabel::add_edge(self : PushRelabel, u : Int, v : Int, cap : Int) -> Unit {
  let forward = { to: v, cap, flow: 0, rev: self.adj[v].length() }
  let backward = { to: u, cap: 0, flow: 0, rev: self.adj[u].length() }
  self.adj[u].push(forward)
  self.adj[v].push(backward)
}

///|
/// Push flow from node `u` along edge index `idx`.
fn PushRelabel::push(self : PushRelabel, u : Int, idx : Int) -> Bool {
  let e = self.adj[u][idx]
  let d = e.cap - e.flow
  if d <= 0 || self.height[u] <= self.height[e.to] {
    return false
  }
  let amount = if self.excess[u] < d.to_int64() { self.excess[u] } else { d.to_int64() }
  self.adj[u][idx].flow = self.adj[u][idx].flow + amount.to_int()
  self.adj[e.to][e.rev].flow = self.adj[e.to][e.rev].flow - amount.to_int()
  self.excess[u] = self.excess[u] - amount
  self.excess[e.to] = self.excess[e.to] + amount
  true
}

///|
/// Relabel node `u`: increase its height to the minimum that allows a push.
fn PushRelabel::relabel(self : PushRelabel, u : Int) -> Unit {
  let mut min_h = 2 * self.n + 1
  for i = 0; i < self.adj[u].length(); i = i + 1 {
    let e = self.adj[u][i]
    if e.cap - e.flow > 0 && self.height[e.to] < min_h {
      min_h = self.height[e.to]
    }
  }
  if min_h < 2 * self.n + 1 {
    let old_h = self.height[u]
    self.height[u] = min_h + 1
    // Update gap count
    if old_h < self.n {
      self.count[old_h] = self.count[old_h] - 1
    }
    if self.height[u] < self.n {
      self.count[self.height[u]] = self.count[self.height[u]] + 1
    }
  }
}

///|
/// Gap heuristic: if no node exists at height `h < n`, all nodes with
/// height > h and < n can be set to n+1 (they can't reach sink).
fn PushRelabel::gap(self : PushRelabel, h : Int) -> Unit {
  if h >= self.n || self.count[h] > 0 {
    return
  }
  for i = 0; i < self.n; i = i + 1 {
    if i != 0 && i != self.n - 1 {
      if self.height[i] > h && self.height[i] < self.n {
        self.count[self.height[i]] = self.count[self.height[i]] - 1
        self.height[i] = self.n + 1
        self.count[self.n + 1] = self.count[self.n + 1] + 1
      }
    }
  }
}

///|
/// Discharge node `u`: push/relabel until excess is 0 or height increases.
fn PushRelabel::discharge(self : PushRelabel, u : Int, current : Array[Int]) -> Unit {
  while self.excess[u] > 0L {
    if current[u] >= self.adj[u].length() {
      let old_h = self.height[u]
      self.relabel(u)
      if self.height[u] > old_h && old_h < self.n {
        self.gap(old_h)
      }
      if self.height[u] >= 2 * self.n {
        break
      }
      current[u] = 0
    } else {
      if !self.push(u, current[u]) {
        current[u] = current[u] + 1
      }
    }
  }
}

///|
/// Compute maximum flow from `source` to `sink`.
///
/// Returns the max flow value as `Int64`.
/// Returns 0 for invalid inputs (n <= 0, source == sink, out of bounds).
pub fn PushRelabel::max_flow(self : PushRelabel, source : Int, sink : Int) -> Int64 {
  if self.n <= 0 || source < 0 || source >= self.n || sink < 0 || sink >= self.n || source == sink {
    return 0L
  }
  // Initialize heights and reset state
  for i = 0; i < self.n; i = i + 1 {
    self.height[i] = 0
    self.excess[i] = 0L
  }
  for i = 0; i < self.count.length(); i = i + 1 {
    self.count[i] = 0
  }
  self.height[source] = self.n
  // Initialize count array: all non-source nodes at height 0, source at height n
  self.count[0] = self.n - 1
  if self.n < self.count.length() {
    self.count[self.n] = 1
  }
  // Saturate edges from source
  for i = 0; i < self.adj[source].length(); i = i + 1 {
    let e = self.adj[source][i]
    let d = e.cap
    if d > 0 {
      self.adj[source][i].flow = d
      self.adj[e.to][e.rev].flow = -d
      self.excess[e.to] = self.excess[e.to] + d.to_int64()
    }
  }
  // Relabel-to-front
  let list : Array[Int] = []
  for i = 0; i < self.n; i = i + 1 {
    if i != source && i != sink {
      list.push(i)
    }
  }
  let current = Array::make(self.n, 0)
  let mut pos = 0
  while pos < list.length() {
    let u = list[pos]
    let old_height = self.height[u]
    self.discharge(u, current)
    if self.height[u] > old_height {
      // Move u to front
      let tmp = list[pos]
      for j = pos; j > 0; j = j - 1 {
        list[j] = list[j - 1]
      }
      list[0] = tmp
      pos = 0
    } else {
      pos = pos + 1
    }
  }
  self.excess[sink]
}
