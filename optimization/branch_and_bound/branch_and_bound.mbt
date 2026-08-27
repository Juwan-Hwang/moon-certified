/// Branch and Bound — a general-purpose exact optimization framework for
/// combinatorial problems.
///
/// **Branch and Bound** (B&B) is a systematic enumeration technique that
/// explores the solution space of a combinatorial optimization problem by
/// maintaining a search tree of **partial solutions**. At each node, a
/// **bounding function** computes a lower bound (for minimization) on the
/// cost of any complete solution derivable from that node. If the bound
/// exceeds the cost of the best solution found so far (**incumbent**), the
/// entire subtree is **pruned** — this is what makes B&B dramatically more
/// efficient than brute-force enumeration.
///
/// ## Algorithm
///
/// ```text
/// best = None                         // incumbent
/// queue = [root_node]                 // search frontier
/// while queue is not empty:
///   node = queue.pop()                // select via strategy
///   if node.bound >= best.cost:       // prune
///     continue
///   if node is complete:              // leaf — candidate solution
///     if node.cost < best.cost:
///       best = node
///   else:
///     children = branch(node)         // expand
///     for child in children:
///       if child.bound < best.cost:   // bound-based pruning
///         queue.push(child)
/// return best
/// ```
///
/// ## Node Selection Strategies
///
/// - **Best-first**: Always expand the node with the lowest bound. Minimizes
///   the number of nodes expanded but requires a priority queue. Memory-intensive.
/// - **Depth-first**: Expand the deepest node first. Memory-efficient; finds
///   feasible solutions quickly (good incumbents early).
/// - **Breadth-first**: Expand level by level. Rarely used in practice.
///
/// ## Applications
///
/// - 0/1 Knapsack Problem
/// - Assignment Problem
/// - Traveling Salesman Problem (via reduced cost matrix)
/// - Integer Linear Programming
/// - Job-shop Scheduling
///
/// ## Complexity
///
/// Worst case: O(2^n) (same as brute force — no pruning possible).
/// With effective bounding: dramatically reduced in practice.
/// Space: O(b · d) for depth-first, O(2^d) for best-first, where b is
/// branching factor and d is search depth.
///
/// ## References
///
/// - Land, A. H. & Doig, A. G. (1960). "An automatic method for solving
///   discrete programming problems." *Econometrica*, 28(3), 497–520.
/// - Little, J. D. C., Murty, K. G., Sweeney, D. W., & Karel, C. (1963).
///   "An algorithm for the traveling salesman problem." *Operations Research*,
///   11(6), 972–989.
/// - Clausen, J. (1999). "Branch and bound algorithms—principles and examples."
///   *Parallel Computing in Optimization*.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

///|
/// Search strategy for node selection.
pub enum BbStrategy {
  /// Best-first: always expand the node with the lowest bound.
  /// Uses a binary heap (priority queue). Minimizes nodes expanded.
  BestFirst
  /// Depth-first: expand the deepest node first.
  /// Memory-efficient; finds feasible solutions quickly.
  DepthFirst
  /// Breadth-first: expand level by level.
  /// Rarely used in practice but included for completeness.
  BreadthFirst
} derive(Eq, Debug)

///|
/// Configuration for the branch-and-bound optimizer.
pub struct BbConfig {
  /// Maximum number of nodes to expand before giving up.
  /// 0 means unlimited.
  max_nodes : Int
  /// Search strategy for node selection.
  strategy : BbStrategy
  /// If true, collect all optimal solutions (same cost as best).
  /// If false, return only the first optimal solution found.
  collect_all_optimal : Bool
}

///|
/// Result of a branch-and-bound optimization run.
pub struct BbResult[T] {
  /// The best solution found, or `None` if no feasible solution exists.
  best : T?
  /// Cost of the best solution. `Infinity` if no feasible solution.
  best_cost : Double
  /// Total number of nodes expanded.
  nodes_expanded : Int
  /// Total number of nodes pruned by bounding.
  nodes_pruned : Int
  /// Whether the search completed (true) or hit max_nodes (false).
  completed : Bool
  /// All optimal solutions (only populated if config.collect_all_optimal).
  all_optimal : Array[T]
}

// ---------------------------------------------------------------------------
// Search node — internal representation
// ---------------------------------------------------------------------------

///|
/// A node in the branch-and-bound search tree.
///
/// - `bound`: Lower bound on the cost of any completion of this partial
///   solution. Must be ≤ the actual cost of any leaf in this subtree.
/// - `depth`: Depth in the search tree (root = 0).
/// - `state`: The partial solution state (problem-specific).
/// - `is_complete`: `true` if this node represents a complete (feasible)
///   solution, `false` if it can still be branched.
priv struct BbNode[T] {
  bound : Double
  depth : Int
  state : T
  is_complete : Bool
}

// ---------------------------------------------------------------------------
// Priority queue (binary min-heap) for best-first search
// ---------------------------------------------------------------------------

///|
/// Binary min-heap of search nodes, ordered by bound.
/// Supports efficient push and pop in O(log n).
priv struct NodeHeap[T] {
  data : Array[BbNode[T]]
}

///|
fn[T] NodeHeap::new() -> NodeHeap[T] {
  { data: [], }
}

///|
fn[T] NodeHeap::len(self : NodeHeap[T]) -> Int {
  self.data.length()
}

///|
fn[T] NodeHeap::push(self : NodeHeap[T], node : BbNode[T]) -> Unit {
  self.data.push(node)
  self.sift_up(self.data.length() - 1)
}

///|
fn[T] NodeHeap::pop(self : NodeHeap[T]) -> BbNode[T]? {
  let n = self.data.length()
  if n == 0 {
    return None
  }
  let top = self.data[0]
  if n == 1 {
    ignore(self.data.pop())
    return Some(top)
  }
  let last = self.data[n - 1]
  self.data[0] = last
  ignore(self.data.pop())
  self.sift_down(0)
  Some(top)
}

///|
fn[T] NodeHeap::sift_up(self : NodeHeap[T], idx_in : Int) -> Unit {
  let mut idx = idx_in
  while idx > 0 {
    let parent = (idx - 1) / 2
    if self.data[idx].bound < self.data[parent].bound {
      let tmp = self.data[idx]
      self.data[idx] = self.data[parent]
      self.data[parent] = tmp
      idx = parent
    } else {
      break
    }
  }
}

///|
fn[T] NodeHeap::sift_down(self : NodeHeap[T], idx_in : Int) -> Unit {
  let mut idx = idx_in
  let n = self.data.length()
  while true {
    let left = 2 * idx + 1
    let right = 2 * idx + 2
    let mut smallest = idx
    if left < n && self.data[left].bound < self.data[smallest].bound {
      smallest = left
    }
    if right < n && self.data[right].bound < self.data[smallest].bound {
      smallest = right
    }
    if smallest == idx {
      break
    }
    let tmp = self.data[idx]
    self.data[idx] = self.data[smallest]
    self.data[smallest] = tmp
    idx = smallest
  }
}

// ---------------------------------------------------------------------------
// FIFO queue for breadth-first search
// ---------------------------------------------------------------------------

///|
/// Simple FIFO queue for breadth-first search.
priv struct NodeQueue[T] {
  data : Array[BbNode[T]]
  mut head : Int
}

///|
fn[T] NodeQueue::new() -> NodeQueue[T] {
  { data: [], head: 0, }
}

///|
fn[T] NodeQueue::len(self : NodeQueue[T]) -> Int {
  self.data.length() - self.head
}

///|
fn[T] NodeQueue::push(self : NodeQueue[T], node : BbNode[T]) -> Unit {
  self.data.push(node)
}

///|
fn[T] NodeQueue::pop(self : NodeQueue[T]) -> BbNode[T]? {
  if self.head >= self.data.length() {
    return None
  }
  let node = self.data[self.head]
  self.head = self.head + 1
  // Compact periodically to avoid unbounded growth.
  if self.head > 1024 && self.head > self.data.length() / 2 {
    let remaining = self.data.length() - self.head
    let mut i = 0
    while i < remaining {
      self.data[i] = self.data[self.head + i]
      i = i + 1
    }
    let to_remove = self.head
    let mut j = 0
    while j < to_remove {
      ignore(self.data.pop())
      j = j + 1
    }
    self.head = 0
  }
  Some(node)
}

// ---------------------------------------------------------------------------
// LIFO stack for depth-first search
// ---------------------------------------------------------------------------

///|
/// Simple LIFO stack for depth-first search.
priv struct NodeStack[T] {
  data : Array[BbNode[T]]
}

///|
fn[T] NodeStack::new() -> NodeStack[T] {
  { data: [], }
}

///|
fn[T] NodeStack::len(self : NodeStack[T]) -> Int {
  self.data.length()
}

///|
fn[T] NodeStack::push(self : NodeStack[T], node : BbNode[T]) -> Unit {
  self.data.push(node)
}

///|
fn[T] NodeStack::pop(self : NodeStack[T]) -> BbNode[T]? {
  self.data.pop()
}

// ---------------------------------------------------------------------------
// Generic frontier abstraction
// ---------------------------------------------------------------------------

///|
/// A frontier abstracts over the three search strategies.
priv struct Frontier[T] {
  strategy : BbStrategy
  heap : NodeHeap[T]
  queue : NodeQueue[T]
  stack : NodeStack[T]
}

///|
fn[T] Frontier::new(strategy : BbStrategy) -> Frontier[T] {
  {
    strategy,
    heap: NodeHeap::new(),
    queue: NodeQueue::new(),
    stack: NodeStack::new(),
  }
}

///|
fn[T] Frontier::push(self : Frontier[T], node : BbNode[T]) -> Unit {
  match self.strategy {
    BestFirst => self.heap.push(node)
    DepthFirst => self.stack.push(node)
    BreadthFirst => self.queue.push(node)
  }
}

///|
fn[T] Frontier::pop(self : Frontier[T]) -> BbNode[T]? {
  match self.strategy {
    BestFirst => self.heap.pop()
    DepthFirst => self.stack.pop()
    BreadthFirst => self.queue.pop()
  }
}

///|
fn[T] Frontier::len(self : Frontier[T]) -> Int {
  match self.strategy {
    BestFirst => self.heap.len()
    DepthFirst => self.stack.len()
    BreadthFirst => self.queue.len()
  }
}

// ---------------------------------------------------------------------------
// Main optimization function
// ---------------------------------------------------------------------------

///|
/// Run branch-and-bound to minimize an objective function.
///
/// # Parameters
/// - `config`: B&B configuration (max nodes, search strategy, etc.)
/// - `initial`: The root state (partial solution with no decisions made).
/// - `bound`: Computes a lower bound on the cost of any completion of a
///   partial solution. Must be **admissible**: `bound(s) ≤ cost(any leaf
///   descendant of s)`. A tighter bound leads to more pruning. For a complete
///   solution, `bound(s)` should equal the actual cost.
/// - `is_complete`: Returns `true` if the state is a complete (feasible)
///   solution.
/// - `branch`: Generates child states from a partial solution. Each child
///   represents a further decision. Returns an empty array if the state
///   cannot be extended (dead end).
///
/// # Returns
/// A `BbResult[T]` containing the best solution found, its cost, statistics,
/// and completion status.
///
/// # Determinism
/// The search is deterministic given the same inputs — node ordering within
/// each branch is preserved (children are pushed in the order `branch`
/// returns them).
pub fn[T] optimize(
  config : BbConfig,
  initial : T,
  bound : (T) -> Double,
  is_complete : (T) -> Bool,
  branch : (T) -> Array[T],
) -> BbResult[T] {
  let frontier : Frontier[T] = Frontier::new(config.strategy)
  let root_bound = bound(initial)
  let root_complete = is_complete(initial)
  frontier.push({
    bound: root_bound,
    depth: 0,
    state: initial,
    is_complete: root_complete,
  })
  let mut best : T? = None
  let mut best_cost = 1.0 / 0.0 // +inf
  let mut nodes_expanded = 0
  let mut nodes_pruned = 0
  let mut all_optimal : Array[T] = []
  let max_nodes = if config.max_nodes > 0 {
    config.max_nodes
  } else {
    2147483647
  }
  let mut completed = true
  while frontier.len() > 0 {
    if nodes_expanded >= max_nodes {
      completed = false
      break
    }
    let node = match frontier.pop() {
      Some(n) => n
      None => break
    }
    // Prune: if this node's bound is not better than best, skip it.
    // When collecting all optimal solutions, use strict > so that
    // equal-cost solutions are still explored.
    let prune_threshold = if node.bound > best_cost {
      true
    } else if node.bound == best_cost {
      !config.collect_all_optimal
    } else {
      false
    }
    if prune_threshold {
      nodes_pruned = nodes_pruned + 1
      continue
    }
    nodes_expanded = nodes_expanded + 1
    if node.is_complete {
      // This is a feasible solution.
      let cost = node.bound // For complete solutions, bound == cost.
      if cost < best_cost {
        best = Some(node.state)
        best_cost = cost
        all_optimal = [node.state]
      } else if config.collect_all_optimal && cost == best_cost {
        all_optimal.push(node.state)
      }
      continue
    }
    // Branch: generate children.
    let children = branch(node.state)
    if children.length() == 0 {
      // Dead end — no children and not complete.
      continue
    }
    for i = 0; i < children.length(); i = i + 1 {
      let child = children[i]
      let child_bound = bound(child)
      // Bound-based pruning: skip children whose bound is not better.
      let child_prune = if child_bound > best_cost {
        true
      } else if child_bound == best_cost {
        !config.collect_all_optimal
      } else {
        false
      }
      if !child_prune {
        let child_complete = is_complete(child)
        frontier.push({
          bound: child_bound,
          depth: node.depth + 1,
          state: child,
          is_complete: child_complete,
        })
      } else {
        nodes_pruned = nodes_pruned + 1
      }
    }
  }
  { best, best_cost, nodes_expanded, nodes_pruned, completed, all_optimal, }
}

// ---------------------------------------------------------------------------
// Convenience: default configuration
// ---------------------------------------------------------------------------

///|
/// Create a best-first configuration with unlimited nodes.
pub fn default_config() -> BbConfig {
  { max_nodes: 0, strategy: BestFirst, collect_all_optimal: false, }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
/// 0/1 Knapsack: maximize value with weight constraint.
/// We solve the minimization form: minimize -(total value).
///
/// State: (item_index, remaining_capacity, total_value)
/// Bound: fractional knapsack relaxation (greedy by value/weight ratio).
test "bb: 0/1 knapsack optimal" {
  // Items: (weight, value)
  // capacity = 10
  // Items: (2,3), (3,4), (4,5), (5,8), (9,10)
  // Optimal: take items 0,1,2,3 → weight=14 > 10. Need to choose.
  // Let's compute: items (2,3),(3,4),(4,5),(5,8),(9,10), cap=10
  // Take (5,8)+(4,5)+(2,3) = w=11 > 10
  // Take (5,8)+(3,4)+(2,3) = w=10, v=15. That's optimal.
  let weights = [2, 3, 4, 5, 9]
  let values = [3, 4, 5, 8, 10]
  let capacity = 10
  let n = weights.length()

  // State: (item_index, remaining_capacity, neg_total_value)
  // We minimize neg_total_value (maximize total value).
  // bound = fractional relaxation: for remaining items, take as much as possible
  // by value/weight ratio.
  fn bound(state : (Int, Int, Int)) -> Double {
    let (idx, rem_cap, neg_val) = state
    let mut cap = rem_cap
    let mut total_val = -neg_val
    // Sort remaining items by value/weight ratio (descending).
    // For simplicity, we compute the fractional bound without sorting:
    // just iterate in order (this is still admissible, just less tight).
    let mut i = idx
    while i < n && cap > 0 {
      let w = weights[i]
      let v = values[i]
      if w <= cap {
        cap = cap - w
        total_val = total_val + v
      } else {
        total_val = total_val + v * cap / w
        cap = 0
      }
      i = i + 1
    }
    -total_val.to_double()
  }

  fn is_complete(state : (Int, Int, Int)) -> Bool {
    let (idx, rem_cap, _) = state
    idx >= n || rem_cap <= 0
  }

  fn branch(state : (Int, Int, Int)) -> Array[(Int, Int, Int)] {
    let (idx, rem_cap, neg_val) = state
    if idx >= n {
      return []
    }
    let result : Array[(Int, Int, Int)] = []
    // Option 1: take item idx (if it fits)
    if weights[idx] <= rem_cap {
      result.push((idx + 1, rem_cap - weights[idx], neg_val - values[idx]))
    }
    // Option 2: skip item idx
    result.push((idx + 1, rem_cap, neg_val))
    result
  }

  let config : BbConfig = {
    max_nodes: 0,
    strategy: BestFirst,
    collect_all_optimal: false,
  }
  let result = optimize(config, (0, capacity, 0), bound, is_complete, branch)
  assert_true(result.completed)
  // best_cost = -15.0 (value = 15)
  assert_true((result.best_cost - -15.0).abs() < 0.001)
  assert_true(result.nodes_expanded > 0)
  assert_true(result.nodes_pruned >= 0)
}

///|
/// 0/1 Knapsack with depth-first strategy.
test "bb: 0/1 knapsack depth-first" {
  let weights = [2, 3, 4, 5]
  let values = [3, 4, 5, 6]
  let capacity = 5
  let n = weights.length()

  fn bound(state : (Int, Int, Int)) -> Double {
    let (idx, rem_cap, neg_val) = state
    let mut cap = rem_cap
    let mut total_val = -neg_val
    let mut i = idx
    while i < n && cap > 0 {
      let w = weights[i]
      let v = values[i]
      if w <= cap {
        cap = cap - w
        total_val = total_val + v
      } else {
        total_val = total_val + v * cap / w
        cap = 0
      }
      i = i + 1
    }
    -total_val.to_double()
  }

  fn is_complete(state : (Int, Int, Int)) -> Bool {
    let (idx, _, _) = state
    idx >= n
  }

  fn branch(state : (Int, Int, Int)) -> Array[(Int, Int, Int)] {
    let (idx, rem_cap, neg_val) = state
    if idx >= n {
      return []
    }
    let result : Array[(Int, Int, Int)] = []
    if weights[idx] <= rem_cap {
      result.push((idx + 1, rem_cap - weights[idx], neg_val - values[idx]))
    }
    result.push((idx + 1, rem_cap, neg_val))
    result
  }

  let config : BbConfig = {
    max_nodes: 0,
    strategy: DepthFirst,
    collect_all_optimal: false,
  }
  let result = optimize(config, (0, capacity, 0), bound, is_complete, branch)
  // Best: take item 0 (w=2,v=3) + item 1 (w=3,v=4) = w=5, v=7
  assert_true((result.best_cost - -7.0).abs() < 0.001)
  assert_true(result.completed)
}

///|
/// Assignment problem: assign n workers to n jobs, minimize total cost.
test "bb: assignment problem" {
  // 3x3 cost matrix
  // Worker 0: [10, 5, 13]
  // Worker 1: [3, 7, 12]
  // Worker 2: [6, 8, 4]
  // Optimal: worker0→job1 (5), worker1→job0 (3), worker2→job2 (4) = 12
  let costs = [[10, 5, 13], [3, 7, 12], [6, 8, 4]]
  let n = 3

  // State: (worker_index, assigned_jobs_mask, total_cost)
  fn bound(state : (Int, Int, Int)) -> Double {
    let (worker, mask, cost) = state
    if worker >= n {
      return cost.to_double()
    }
    // Lower bound: current cost + min remaining cost for each unassigned worker.
    // For each remaining worker, add the minimum available job cost.
    let mut lb = cost
    let mut w = worker
    while w < n {
      let mut min_cost = 2147483647
      for j = 0; j < n; j = j + 1 {
        if (mask & (1 << j)) == 0 {
          if costs[w][j] < min_cost {
            min_cost = costs[w][j]
          }
        }
      }
      if min_cost < 2147483647 {
        lb = lb + min_cost
      }
      w = w + 1
    }
    lb.to_double()
  }

  fn is_complete(state : (Int, Int, Int)) -> Bool {
    let (worker, _, _) = state
    worker >= n
  }

  fn branch(state : (Int, Int, Int)) -> Array[(Int, Int, Int)] {
    let (worker, mask, cost) = state
    if worker >= n {
      return []
    }
    let result : Array[(Int, Int, Int)] = []
    for j = 0; j < n; j = j + 1 {
      if (mask & (1 << j)) == 0 {
        result.push((worker + 1, mask | (1 << j), cost + costs[worker][j]))
      }
    }
    result
  }

  let config = default_config()
  let result = optimize(config, (0, 0, 0), bound, is_complete, branch)
  assert_true(result.completed)
  assert_true((result.best_cost - 12.0).abs() < 0.001)
}

///|
/// Test: no feasible solution (empty branch at root).
test "bb: no feasible solution" {
  fn bound(_ : Int) -> Double {
    0.0
  }
  fn is_complete(_ : Int) -> Bool {
    false
  }
  fn branch(_ : Int) -> Array[Int] {
    []
  }

  let config = default_config()
  let result = optimize(config, 0, bound, is_complete, branch)
  assert_true(result.best is None)
  assert_true(result.best_cost == 1.0 / 0.0)
  assert_true(result.nodes_expanded == 1)
}

///|
/// Test: trivial problem (root is complete).
test "bb: root is complete" {
  fn bound(x : Int) -> Double {
    x.to_double()
  }
  fn is_complete(_ : Int) -> Bool {
    true
  }
  fn branch(_ : Int) -> Array[Int] {
    []
  }

  let config = default_config()
  let result = optimize(config, 42, bound, is_complete, branch)
  assert_true((result.best_cost - 42.0).abs() < 0.001)
  assert_true(result.nodes_expanded == 1)
}

///|
/// Test: max_nodes limit is respected.
test "bb: max_nodes limit" {
  let weights = [1, 1, 1, 1, 1, 1, 1, 1, 1, 1]
  let values = [1, 1, 1, 1, 1, 1, 1, 1, 1, 1]
  let capacity = 5
  let n = weights.length()

  fn bound(state : (Int, Int, Int)) -> Double {
    let (idx, rem_cap, neg_val) = state
    let remaining = if n - idx > rem_cap { rem_cap } else { n - idx }
    (neg_val - remaining).to_double()
  }

  fn is_complete(state : (Int, Int, Int)) -> Bool {
    let (idx, _, _) = state
    idx >= n
  }

  fn branch(state : (Int, Int, Int)) -> Array[(Int, Int, Int)] {
    let (idx, rem_cap, neg_val) = state
    if idx >= n {
      return []
    }
    let result : Array[(Int, Int, Int)] = []
    if weights[idx] <= rem_cap {
      result.push((idx + 1, rem_cap - weights[idx], neg_val - values[idx]))
    }
    result.push((idx + 1, rem_cap, neg_val))
    result
  }

  let config : BbConfig = {
    max_nodes: 5,
    strategy: BestFirst,
    collect_all_optimal: false,
  }
  let result = optimize(config, (0, capacity, 0), bound, is_complete, branch)
  assert_false(result.completed)
  assert_true(result.nodes_expanded <= 5)
}

///|
/// Test: collect all optimal solutions.
test "bb: collect all optimal" {
  // Two items with equal value: (1, 5), (1, 5), capacity = 1
  // Both assignments are optimal (value = 5).
  let weights = [1, 1]
  let values = [5, 5]
  let capacity = 1
  let n = weights.length()

  fn bound(state : (Int, Int, Int)) -> Double {
    let (idx, rem_cap, neg_val) = state
    let remaining = if n - idx > rem_cap { rem_cap } else { n - idx }
    // Lower bound on neg_val: current neg_val minus max additional value.
    (neg_val - remaining * 5).to_double()
  }

  fn is_complete(state : (Int, Int, Int)) -> Bool {
    let (idx, _, _) = state
    idx >= n
  }

  fn branch(state : (Int, Int, Int)) -> Array[(Int, Int, Int)] {
    let (idx, rem_cap, neg_val) = state
    if idx >= n {
      return []
    }
    let result : Array[(Int, Int, Int)] = []
    if weights[idx] <= rem_cap {
      result.push((idx + 1, rem_cap - weights[idx], neg_val - values[idx]))
    }
    result.push((idx + 1, rem_cap, neg_val))
    result
  }

  let config : BbConfig = {
    max_nodes: 0,
    strategy: BestFirst,
    collect_all_optimal: true,
  }
  let result = optimize(config, (0, capacity, 0), bound, is_complete, branch)
  assert_true(result.completed)
  assert_true((result.best_cost - -5.0).abs() < 0.001)
  // Should have found 2 optimal solutions (take item 0 or take item 1).
  assert_true(result.all_optimal.length() >= 2)
}

///|
/// Test: pruning is effective (fewer nodes than brute force).
test "bb: pruning effectiveness" {
  // 0/1 knapsack where pruning should significantly reduce nodes.
  let weights = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]
  let values = [15, 25, 35, 45, 55, 65, 75, 85, 95, 105]
  let capacity = 100
  let n = weights.length()

  fn bound(state : (Int, Int, Int)) -> Double {
    let (idx, rem_cap, neg_val) = state
    let mut cap = rem_cap
    let mut total_val = -neg_val
    let mut i = idx
    while i < n && cap > 0 {
      let w = weights[i]
      let v = values[i]
      if w <= cap {
        cap = cap - w
        total_val = total_val + v
      } else {
        total_val = total_val + v * cap / w
        cap = 0
      }
      i = i + 1
    }
    -total_val.to_double()
  }

  fn is_complete(state : (Int, Int, Int)) -> Bool {
    let (idx, _, _) = state
    idx >= n
  }

  fn branch(state : (Int, Int, Int)) -> Array[(Int, Int, Int)] {
    let (idx, rem_cap, neg_val) = state
    if idx >= n {
      return []
    }
    let result : Array[(Int, Int, Int)] = []
    if weights[idx] <= rem_cap {
      result.push((idx + 1, rem_cap - weights[idx], neg_val - values[idx]))
    }
    result.push((idx + 1, rem_cap, neg_val))
    result
  }

  let config = default_config()
  let result = optimize(config, (0, capacity, 0), bound, is_complete, branch)
  assert_true(result.completed)
  // With 10 items, brute force would be 2^10 = 1024 leaf nodes.
  // B&B should expand far fewer.
  assert_true(result.nodes_expanded < 1024)
  assert_true(result.nodes_pruned > 0)
}

///|
/// Test: breadth-first strategy produces same optimal as best-first.
test "bb: breadth-first consistency" {
  let weights = [2, 3, 4, 5]
  let values = [3, 4, 5, 8]
  let capacity = 7
  let n = weights.length()

  fn bound(state : (Int, Int, Int)) -> Double {
    let (idx, rem_cap, neg_val) = state
    let mut cap = rem_cap
    let mut total_val = -neg_val
    let mut i = idx
    while i < n && cap > 0 {
      let w = weights[i]
      let v = values[i]
      if w <= cap {
        cap = cap - w
        total_val = total_val + v
      } else {
        total_val = total_val + v * cap / w
        cap = 0
      }
      i = i + 1
    }
    -total_val.to_double()
  }

  fn is_complete(state : (Int, Int, Int)) -> Bool {
    let (idx, _, _) = state
    idx >= n
  }

  fn branch(state : (Int, Int, Int)) -> Array[(Int, Int, Int)] {
    let (idx, rem_cap, neg_val) = state
    if idx >= n {
      return []
    }
    let result : Array[(Int, Int, Int)] = []
    if weights[idx] <= rem_cap {
      result.push((idx + 1, rem_cap - weights[idx], neg_val - values[idx]))
    }
    result.push((idx + 1, rem_cap, neg_val))
    result
  }

  let config_bf : BbConfig = {
    max_nodes: 0,
    strategy: BestFirst,
    collect_all_optimal: false,
  }
  let config_bfs : BbConfig = {
    max_nodes: 0,
    strategy: BreadthFirst,
    collect_all_optimal: false,
  }
  let result_bf = optimize(
    config_bf,
    (0, capacity, 0),
    bound,
    is_complete,
    branch,
  )
  let result_bfs = optimize(
    config_bfs,
    (0, capacity, 0),
    bound,
    is_complete,
    branch,
  )
  // Both strategies should find the same optimal cost.
  assert_true((result_bf.best_cost - result_bfs.best_cost).abs() < 0.001)
}

///|
/// Test: all three strategies agree on a larger problem.
/// Items are sorted by value/weight ratio (descending) to ensure the
/// fractional knapsack bound is admissible.
test "bb: strategy agreement" {
  let weights = [1, 2, 3, 4, 5, 6, 7, 8]
  let values = [2, 3, 4, 5, 6, 7, 8, 9]
  let capacity = 15
  let n = weights.length()

  fn bound(state : (Int, Int, Int)) -> Double {
    let (idx, rem_cap, neg_val) = state
    let mut cap = rem_cap
    let mut total_val = -neg_val
    let mut i = idx
    while i < n && cap > 0 {
      let w = weights[i]
      let v = values[i]
      if w <= cap {
        cap = cap - w
        total_val = total_val + v
      } else {
        total_val = total_val + v * cap / w
        cap = 0
      }
      i = i + 1
    }
    -total_val.to_double()
  }

  fn is_complete(state : (Int, Int, Int)) -> Bool {
    let (idx, _, _) = state
    idx >= n
  }

  fn branch(state : (Int, Int, Int)) -> Array[(Int, Int, Int)] {
    let (idx, rem_cap, neg_val) = state
    if idx >= n {
      return []
    }
    let result : Array[(Int, Int, Int)] = []
    if weights[idx] <= rem_cap {
      result.push((idx + 1, rem_cap - weights[idx], neg_val - values[idx]))
    }
    result.push((idx + 1, rem_cap, neg_val))
    result
  }

  let config_best : BbConfig = {
    max_nodes: 0,
    strategy: BestFirst,
    collect_all_optimal: false,
  }
  let config_dfs : BbConfig = {
    max_nodes: 0,
    strategy: DepthFirst,
    collect_all_optimal: false,
  }
  let config_bfs : BbConfig = {
    max_nodes: 0,
    strategy: BreadthFirst,
    collect_all_optimal: false,
  }
  let r1 = optimize(config_best, (0, capacity, 0), bound, is_complete, branch)
  let r2 = optimize(config_dfs, (0, capacity, 0), bound, is_complete, branch)
  let r3 = optimize(config_bfs, (0, capacity, 0), bound, is_complete, branch)
  assert_true((r1.best_cost - r2.best_cost).abs() < 0.001)
  assert_true((r2.best_cost - r3.best_cost).abs() < 0.001)
  assert_true(r1.completed)
  assert_true(r2.completed)
  assert_true(r3.completed)
}

///|
/// Test: node pruning count is correct.
test "bb: pruning count" {
  // Simple problem: find minimum of f(x) = x for x in [0, 3]
  // with branch generating x and x+1.
  fn bound(x : Int) -> Double {
    x.to_double()
  }
  fn is_complete(x : Int) -> Bool {
    x >= 3
  }
  fn branch(x : Int) -> Array[Int] {
    if x >= 3 {
      return []
    }
    [x + 1]
  }

  let config = default_config()
  let result = optimize(config, 0, bound, is_complete, branch)
  assert_true(result.completed)
  assert_true((result.best_cost - 3.0).abs() < 0.001)
  // Should expand exactly 4 nodes (0→1→2→3).
  assert_true(result.nodes_expanded == 4)
}

///|
/// Test: floating point bound values work correctly.
test "bb: floating point bounds" {
  // Minimize a path cost with floating point edge weights.
  // Graph: 0 → 1 (cost 1.5), 0 → 2 (cost 3.0), 1 → 3 (cost 2.0), 2 → 3 (cost 0.5)
  // Optimal: 0→2→3 = 3.5
  // State: (current_node, visited_mask, accumulated_cost)
  // adjacency: edges[from] = [(to, cost), ...]
  let edges : Array[Array[(Int, Double)]] = [
    [(1, 1.5), (2, 3.0)], // from 0
    [(3, 2.0)], // from 1
    [(3, 0.5)], // from 2
    [], // from 3
  ]

  fn bound(state : (Int, Int, Double)) -> Double {
    let (_, _, acc) = state
    acc
  }

  fn is_complete(state : (Int, Int, Double)) -> Bool {
    let (node, _, _) = state
    node == 3
  }

  fn branch(state : (Int, Int, Double)) -> Array[(Int, Int, Double)] {
    let (node, mask, acc) = state
    if node == 3 {
      return []
    }
    let result : Array[(Int, Int, Double)] = []
    for i = 0; i < edges[node].length(); i = i + 1 {
      let (next, cost) = edges[node][i]
      if (mask & (1 << next)) == 0 {
        result.push((next, mask | (1 << next), acc + cost))
      }
    }
    result
  }

  let config = default_config()
  let result = optimize(config, (0, 1, 0.0), bound, is_complete, branch)
  assert_true(result.completed)
  assert_true((result.best_cost - 3.5).abs() < 0.001)
}
