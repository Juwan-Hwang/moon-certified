/// Tree Dynamic Programming framework.
///
/// Tree DP solves optimisation problems on trees by combining sub-tree
/// results. The standard pattern is a **post-order DFS**: solve all
/// children first, then combine their results at the parent.
///
/// ## Implemented problems
///
/// 1. **Maximum independent set on trees**: select vertices to maximise
///    the total weight such that no two selected vertices are adjacent.
///    - Time: O(V), Space: O(V).
///    - Classic tree DP: `dp[v][0]` = best for sub-tree rooted at `v` when
///      `v` is **not** selected; `dp[v][1]` = best when `v` **is** selected.
///
/// 2. **Tree knapsack (tree backpack)**: select items on a tree subject to
///    a total capacity constraint. Each item has a cost and value; an item
///    can only be selected if its parent is selected.
///    - Time: O(V * C), Space: O(V * C).
///    - Uses the "left-child right-sibling" or subtree-merge technique.
///
/// 3. **Tree diameter**: the longest path (in edge count) between any two
///    vertices in a tree.
///    - Time: O(V), Space: O(V).
///    - For each vertex, computes the top-2 longest downward paths; the
///      diameter passes through the vertex where their sum is maximised.
///
/// 4. **Maximum matching on trees**: select edges to maximise the count,
///    with no two selected edges sharing a vertex.
///    - Time: O(V), Space: O(V).
///    - `dp[v][0]` = best for sub-tree when `v` is unmatched;
///      `dp[v][1]` = best when `v` is matched to one of its children.
///
/// ## Implementation notes
///
/// All DFS traversals are **iterative** (explicit stack) to prevent stack
/// overflow on deep or degenerate trees. MoonBit does not guarantee
/// tail-call optimisation, so a recursive implementation could crash on
/// trees with depth > 10⁴.
///
/// The three forest DP functions (`max_independent_set`, `tree_diameter`,
/// and `max_matching_on_tree`) share a single generic post-order forest
/// traversal, `dfs_forest`, and differ only in their per-vertex DP
/// transition, which is supplied as a callback. `tree_knapsack` operates
/// on a rooted tree given as a directed `children` adjacency, so its
/// traversal shape is different and it is kept self-contained.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

// ---------------------------------------------------------------------------
// Internal: generic iterative post-order DFS on a forest
// ---------------------------------------------------------------------------

///|
/// Internal: post-order DFS on a forest.
///
/// Walks every connected component of an undirected graph given by `adj`
/// and invokes `process(u, parent, neighbors)` once per vertex **after** all
/// of its descendants have already been processed (post-order). This is the
/// shared traversal skeleton used by every forest DP in this module.
///
/// # Parameters
/// - `adj`: adjacency list; `adj[u]` holds the neighbour descriptors of
///   `u`. For unweighted graphs each descriptor is the neighbour index
///   itself (`T = Int`); for weighted graphs each descriptor is
///   `(neighbour, weight)` (`T = (Int, Int)`).
/// - `n`: number of vertices, indexed `0 .. n - 1`.
/// - `get_vertex`: extracts the neighbour index from a descriptor. This is
///   the only operation the traversal needs on `T`, which keeps the helper
///   generic without imposing a trait bound (and lets MoonBit monomorphise
///   each instantiation, so there is no dynamic-dispatch overhead).
/// - `process`: the per-vertex DP-transition callback. Receives
///   `(u, parent, neighbors)` where `neighbors = adj[u]`; the caller
///   iterates it to fold in already-computed child results.
///
/// Forests (multiple connected components) are handled by looping over
/// every unvisited vertex as a potential root. An explicit
/// `(node, parent, child_idx)` stack is used so the traversal cannot
/// overflow on degenerate chains; MoonBit does not guarantee tail-call
/// optimisation for recursion.
fn[T] dfs_forest(
  adj : Array[Array[T]],
  n : Int,
  get_vertex : (T) -> Int,
  process : (Int, Int, Array[T]) -> Unit,
) -> Unit {
  let visited = FixedArray::make(n, false)
  for root = 0; root < n; root = root + 1 {
    if visited[root] {
      continue
    }
    // Stack entry: (node, parent, next-child-index).
    let stack : Array[(Int, Int, Int)] = [(root, -1, 0)]
    visited[root] = true
    while stack.length() > 0 {
      let top_idx = stack.length() - 1
      let (u, parent, child_idx) = stack[top_idx]
      let neighbors = adj[u]
      // Find the next unvisited child, skipping the parent edge.
      let mut next_child = -1
      let mut j = child_idx
      while j < neighbors.length() {
        let v = get_vertex(neighbors[j])
        if v != parent && !visited[v] {
          next_child = v
          break
        }
        j = j + 1
      }
      if next_child >= 0 {
        // Descend into `next_child`; resume scanning from j + 1 on return.
        stack[top_idx] = (u, parent, j + 1)
        visited[next_child] = true
        stack.push((next_child, u, 0))
      } else {
        // All children processed: run the caller's DP transition.
        process(u, parent, neighbors)
        ignore(stack.pop())
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Maximum Independent Set on Trees
// ---------------------------------------------------------------------------

///|
/// Compute the maximum independent set on a tree.
///
/// Given an **undirected tree** as an adjacency list, selects a subset of
/// vertices with maximum total weight such that no two selected vertices
/// are adjacent.
///
/// # Parameters
/// - `adj`: adjacency list where `adj[i]` is an array of neighbour indices.
///   The graph must be a tree (connected, acyclic, `V-1` edges).
/// - `n`: number of vertices, indexed `0 .. n - 1`.
/// - `weights`: weight of each vertex. Negative weights are treated as 0
///   (a vertex with negative weight is never beneficial to select).
///
/// # Returns
/// The maximum total weight of an independent set as `Int64`. Returns 0 for
/// `n <= 0`.
///
/// # Complexity
/// - Time: O(V) — single DFS pass.
/// - Space: O(V) for the DP arrays and DFS stack.
///
/// Uses `Int64` for weight accumulation to prevent overflow.
pub fn max_independent_set(
  adj : Array[Array[Int]],
  n : Int,
  weights : FixedArray[Int],
) -> Int64 {
  if n <= 0 || adj.length() < n {
    return 0L
  }
  // dp[v][0] = max weight in subtree of v, NOT selecting v.
  // dp[v][1] = max weight in subtree of v, SELECTING v.
  let dp0 = FixedArray::make(n, 0L)
  let dp1 = FixedArray::make(n, 0L)
  dfs_forest(adj, n, fn(v) { v }, fn(u, parent, neighbors) {
    // All children processed: compute DP for u.
    let w = if u < weights.length() && weights[u] > 0 {
      weights[u].to_int64()
    } else {
      0L
    }
    dp1[u] = w
    dp0[u] = 0L
    for k = 0; k < neighbors.length(); k = k + 1 {
      let v = neighbors[k]
      if v != parent {
        dp1[u] = dp1[u] + dp0[v]
        dp0[u] = dp0[u] + (if dp0[v] > dp1[v] { dp0[v] } else { dp1[v] })
      }
    }
  })
  // Answer: max over all roots.
  let mut result = 0L
  for v = 0; v < n; v = v + 1 {
    let best = if dp0[v] > dp1[v] { dp0[v] } else { dp1[v] }
    if best > result {
      result = best
    }
  }
  result
}

// ---------------------------------------------------------------------------
// Tree Diameter
// ---------------------------------------------------------------------------

///|
/// Compute the diameter (longest path) of a tree.
///
/// Given an **undirected tree** as an adjacency list, finds the maximum
/// number of edges on any simple path between two vertices.
///
/// # Parameters
/// - `adj`: adjacency list where `adj[i]` is an array of `(neighbour, weight)`
///   tuples. The graph must be a tree.
/// - `n`: number of vertices, indexed `0 .. n - 1`.
///
/// # Returns
/// The diameter (longest path length) as `Int64`. Returns 0 for `n <= 1`.
///
/// # Complexity
/// - Time: O(V) — single DFS pass.
/// - Space: O(V) for the DFS stack and auxiliary arrays.
///
/// Uses `Int64` for path length accumulation to prevent overflow.
pub fn tree_diameter(adj : Array[Array[(Int, Int)]], n : Int) -> Int64 {
  if n <= 1 || adj.length() < n {
    return 0L
  }
  // For each vertex, track the longest and second-longest downward paths.
  let max1 = FixedArray::make(n, 0L) // longest downward path from v
  let max2 = FixedArray::make(n, 0L) // second-longest downward path from v
  let mut diameter = 0L
  dfs_forest(adj, n, fn(pair) { pair.0 }, fn(u, parent, neighbors) {
    // All children processed: compute max1, max2 for u.
    max1[u] = 0L
    max2[u] = 0L
    for k = 0; k < neighbors.length(); k = k + 1 {
      let (v, w) = neighbors[k]
      if v != parent {
        let path_len = max1[v] + w.to_int64()
        if path_len > max1[u] {
          max2[u] = max1[u]
          max1[u] = path_len
        } else if path_len > max2[u] {
          max2[u] = path_len
        }
      }
    }
    let through_u = max1[u] + max2[u]
    if through_u > diameter {
      diameter = through_u
    }
  })
  diameter
}

// ---------------------------------------------------------------------------
// Maximum Matching on Trees
// ---------------------------------------------------------------------------

///|
/// Compute the maximum matching (maximum set of non-adjacent edges) on a tree.
///
/// Given an **undirected tree** as an adjacency list, finds the maximum number
/// of edges such that no two selected edges share a vertex.
///
/// # Parameters
/// - `adj`: adjacency list where `adj[i]` is an array of neighbour indices.
///   The graph must be a tree.
/// - `n`: number of vertices, indexed `0 .. n - 1`.
///
/// # Returns
/// The size of the maximum matching as `Int`. Returns 0 for `n <= 1`.
///
/// # Complexity
/// - Time: O(V) — single DFS pass.
/// - Space: O(V) for the DP arrays and DFS stack.
///
/// # Algorithm
///
/// Tree DP:
/// - `dp[v][0]` = max matching in subtree of `v`, where `v` is **not**
///   matched to any of its children.
/// - `dp[v][1]` = max matching in subtree of `v`, where `v` **is** matched
///   to exactly one child.
///
/// Transition:
/// - `dp[v][0] = sum over children c of max(dp[c][0], dp[c][1])`
/// - `dp[v][1] = dp[v][0] + 1` if there exists a child `c` such that
///   `dp[v][0] - max(dp[c][0], dp[c][1]) + dp[c][0] + 1 > dp[v][0]`.
///   That is, we "downgrade" one child from "possibly matched" to
///   "definitely unmatched" and add the edge `(v, c)`.
pub fn max_matching_on_tree(adj : Array[Array[Int]], n : Int) -> Int {
  if n <= 1 || adj.length() < n {
    return 0
  }
  // dp0[v] = max matching in subtree of v, v NOT matched to a child.
  // dp1[v] = max matching in subtree of v, v IS matched to a child.
  let dp0 = FixedArray::make(n, 0)
  let dp1 = FixedArray::make(n, 0)
  dfs_forest(adj, n, fn(v) { v }, fn(u, parent, neighbors) {
    // All children processed.
    dp0[u] = 0
    dp1[u] = 0
    for k = 0; k < neighbors.length(); k = k + 1 {
      let v = neighbors[k]
      if v != parent {
        // v is a child.
        let child_best = if dp0[v] > dp1[v] { dp0[v] } else { dp1[v] }
        dp0[u] = dp0[u] + child_best
        // dp1[u]: match u with v → gain 1 + dp0[v], lose child_best.
        let match_gain = 1 + dp0[v] - child_best
        if match_gain > dp1[u] {
          dp1[u] = match_gain
        }
      }
    }
    // dp1[u] now represents the gain from matching u with a child.
    dp1[u] = dp0[u] + dp1[u]
  })
  // Answer: max over all roots of max(dp0[v], dp1[v]).
  let mut result = 0
  for v = 0; v < n; v = v + 1 {
    let best = if dp0[v] > dp1[v] { dp0[v] } else { dp1[v] }
    if best > result {
      result = best
    }
  }
  result
}

// ---------------------------------------------------------------------------
// Tree Knapsack (Tree Backpack)
// ---------------------------------------------------------------------------

///|
/// Solve the tree knapsack problem: select items on a rooted tree subject to
/// a capacity constraint. An item can only be selected if its parent is selected.
///
/// # Parameters
/// - `children`: `children[i]` is an array of child indices of vertex `i`.
///   The tree is rooted at vertex 0.
/// - `n`: number of vertices (items), indexed `0 .. n - 1`.
/// - `costs`: `costs[i]` is the cost of selecting item `i`.
/// - `values`: `values[i]` is the value of selecting item `i`.
/// - `capacity`: the total cost budget.
///
/// # Returns
/// The maximum total value achievable within the capacity as `Int64`.
/// Returns 0 for `n <= 0` or `capacity <= 0`.
///
/// # Complexity
/// - Time: O(V * C) where V = n, C = capacity.
/// - Space: O(V * C) for the DP table.
///
/// Uses `Int64` for value accumulation to prevent overflow.
///
/// Note: unlike the three forest DPs above, this operates on a rooted tree
/// given as a directed `children` adjacency, so there is no parent edge to
/// skip and no need for a `visited` array; the traversal therefore uses its
/// own `(vertex, child_index)` stack and is not routed through `dfs_forest`.
pub fn tree_knapsack(
  children : Array[Array[Int]],
  n : Int,
  costs : FixedArray[Int],
  values : FixedArray[Int],
  capacity : Int,
) -> Int64 {
  if n <= 0 || capacity <= 0 || children.length() < n {
    return 0L
  }
  let cap = capacity
  // dp[v][j] = max value in subtree of v, selecting v, using total cost j.
  // We use a flat 2D array: dp[v * (cap+1) + j].
  // Initialise: dp[v][costs[v]] = values[v] (must select v to select descendants).
  let dp_size = n * (cap + 1)
  let dp = FixedArray::make(dp_size, -1L)
  // Post-order iterative DFS.
  let stack : Array[(Int, Int)] = [(0, 0)] // (vertex, child_index)
  while stack.length() > 0 {
    let top_idx = stack.length() - 1
    let (u, child_idx) = stack[top_idx]
    let kids = children[u]
    if child_idx < kids.length() {
      stack[top_idx] = (u, child_idx + 1)
      stack.push((kids[child_idx], 0))
    } else {
      // All children processed: compute DP for u.
      let cu = if u < costs.length() && costs[u] >= 0 { costs[u] } else { 0 }
      let vu = if u < values.length() && values[u] > 0 {
        values[u].to_int64()
      } else {
        0L
      }
      // Base: select u alone.
      if cu <= cap {
        dp[u * (cap + 1) + cu] = vu
      }
      // Merge each child's subtree.
      for k = 0; k < kids.length(); k = k + 1 {
        let c = kids[k]
        // Merge child c into u's DP.
        // New dp: for each j from cap down to cu,
        //   for each k from 0 to j - cu:
        //     dp[u][j] = max(dp[u][j], dp[u][j-k] + dp[c][k])
        // But dp[c][k] might be -1 (not reachable).
        // We process in reverse to avoid using updated values.
        let mut j = cap
        while j >= cu {
          let mut best = dp[u * (cap + 1) + j]
          let mut k2 = 0
          while k2 <= j - cu {
            let du = dp[u * (cap + 1) + (j - k2)]
            let dc = dp[c * (cap + 1) + k2]
            if du >= 0L && dc >= 0L {
              let total = du + dc
              if total > best {
                best = total
              }
            }
            k2 = k2 + 1
          }
          dp[u * (cap + 1) + j] = best
          j = j - 1
        }
      }
      ignore(stack.pop())
    }
  }
  // Answer: max over all capacities for the root.
  let mut result = 0L
  for j = 0; j <= cap; j = j + 1 {
    let val = dp[0 * (cap + 1) + j]
    if val > result {
      result = val
    }
  }
  result
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "max_independent_set: path graph" {
  // Path: 0 - 1 - 2 - 3 - 4
  // Weights: all 1
  // MIS = {0, 2, 4} or {1, 3}, max weight = 3
  let adj : Array[Array[Int]] = []
  for i = 0; i < 5; i = i + 1 {
    adj.push([])
  }
  adj[0].push(1)
  adj[1].push(0)
  adj[1].push(2)
  adj[2].push(1)
  adj[2].push(3)
  adj[3].push(2)
  adj[3].push(4)
  adj[4].push(3)
  let weights = FixedArray::make(5, 1)
  assert_eq(max_independent_set(adj, 5, weights), 3L)
}

///|
test "max_independent_set: star graph" {
  // Star: center 0 connected to 1, 2, 3, 4
  // Weights: all 1
  // MIS = {1, 2, 3, 4} (leaves), weight = 4
  let adj : Array[Array[Int]] = []
  for i = 0; i < 5; i = i + 1 {
    adj.push([])
  }
  for i = 1; i < 5; i = i + 1 {
    adj[0].push(i)
    adj[i].push(0)
  }
  let weights = FixedArray::make(5, 1)
  assert_eq(max_independent_set(adj, 5, weights), 4L)
}

///|
test "max_independent_set: weighted tree" {
  // Tree with varying weights.
  //     0(w=5)
  //    / \
  //   1(w=3)  2(w=4)
  //  / \
  // 3(w=1) 4(w=2)
  // MIS = {0, 3, 4} = 5 + 1 + 2 = 8 (vs {1, 2} = 7, vs {0, 3, 4} = 8)
  // Actually: if we select 0, we can't select 1 or 2.
  //   Then for subtree of 1: select 3 and 4 = 1 + 2 = 3. Total = 5 + 3 = 8.
  //   If we don't select 0: select 1 and 2 = 3 + 4 = 7.
  //   For subtree of 1 (not selecting 1): select 3 and 4 = 3. Total without 0 = 4 + 3 = 7.
  // Max = 8.
  let adj : Array[Array[Int]] = []
  for i = 0; i < 5; i = i + 1 {
    adj.push([])
  }
  adj[0].push(1)
  adj[0].push(2)
  adj[1].push(0)
  adj[1].push(3)
  adj[1].push(4)
  adj[2].push(0)
  adj[3].push(1)
  adj[4].push(1)
  let weights : FixedArray[Int] = FixedArray::make(5, 0)
  weights[0] = 5
  weights[1] = 3
  weights[2] = 4
  weights[3] = 1
  weights[4] = 2
  assert_eq(max_independent_set(adj, 5, weights), 8L)
}

///|
test "max_independent_set: single node" {
  let adj : Array[Array[Int]] = [[]]
  let weights = FixedArray::make(1, 10)
  assert_eq(max_independent_set(adj, 1, weights), 10L)
}

///|
test "max_independent_set: empty" {
  let adj : Array[Array[Int]] = []
  let weights : FixedArray[Int] = FixedArray::make(0, 0)
  assert_eq(max_independent_set(adj, 0, weights), 0L)
}

///|
test "tree_diameter: path graph" {
  // Path: 0 - 1 - 2 - 3 - 4 (all edges weight 1)
  // Diameter = 4 (from 0 to 4)
  let adj : Array[Array[(Int, Int)]] = []
  for i = 0; i < 5; i = i + 1 {
    adj.push([])
  }
  adj[0].push((1, 1))
  adj[1].push((0, 1))
  adj[1].push((2, 1))
  adj[2].push((1, 1))
  adj[2].push((3, 1))
  adj[3].push((2, 1))
  adj[3].push((4, 1))
  adj[4].push((3, 1))
  assert_eq(tree_diameter(adj, 5), 4L)
}

///|
test "tree_diameter: star graph" {
  // Star: center 0 connected to 1, 2, 3, 4
  // Diameter = 2 (through center, e.g. 1 - 0 - 2)
  let adj : Array[Array[(Int, Int)]] = []
  for i = 0; i < 5; i = i + 1 {
    adj.push([])
  }
  for i = 1; i < 5; i = i + 1 {
    adj[0].push((i, 1))
    adj[i].push((0, 1))
  }
  assert_eq(tree_diameter(adj, 5), 2L)
}

///|
test "tree_diameter: weighted tree" {
  //     0
  //    / \
  //   1   2
  //  / \
  // 3   4
  // Edges: 0-1 (w=2), 0-2 (w=3), 1-3 (w=4), 1-4 (w=1)
  // Diameter: 3 - 1 - 0 - 2 = 4 + 2 + 3 = 9
  let adj : Array[Array[(Int, Int)]] = []
  for i = 0; i < 5; i = i + 1 {
    adj.push([])
  }
  adj[0].push((1, 2))
  adj[0].push((2, 3))
  adj[1].push((0, 2))
  adj[1].push((3, 4))
  adj[1].push((4, 1))
  adj[2].push((0, 3))
  adj[3].push((1, 4))
  adj[4].push((1, 1))
  assert_eq(tree_diameter(adj, 5), 9L)
}

///|
test "tree_diameter: single node" {
  let adj : Array[Array[(Int, Int)]] = [[]]
  assert_eq(tree_diameter(adj, 1), 0L)
}

///|
test "max_matching: path graph" {
  // Path: 0 - 1 - 2 - 3 - 4
  // Max matching = 2 (e.g. edges 0-1 and 2-3)
  let adj : Array[Array[Int]] = []
  for i = 0; i < 5; i = i + 1 {
    adj.push([])
  }
  adj[0].push(1)
  adj[1].push(0)
  adj[1].push(2)
  adj[2].push(1)
  adj[2].push(3)
  adj[3].push(2)
  adj[3].push(4)
  adj[4].push(3)
  assert_eq(max_matching_on_tree(adj, 5), 2)
}

///|
test "max_matching: star graph" {
  // Star: center 0 connected to 1, 2, 3, 4
  // Max matching = 1 (can only match center with one leaf)
  let adj : Array[Array[Int]] = []
  for i = 0; i < 5; i = i + 1 {
    adj.push([])
  }
  for i = 1; i < 5; i = i + 1 {
    adj[0].push(i)
    adj[i].push(0)
  }
  assert_eq(max_matching_on_tree(adj, 5), 1)
}

///|
test "max_matching: single edge" {
  let adj : Array[Array[Int]] = [[], []]
  adj[0].push(1)
  adj[1].push(0)
  assert_eq(max_matching_on_tree(adj, 2), 1)
}

///|
test "max_matching: single node" {
  let adj : Array[Array[Int]] = [[]]
  assert_eq(max_matching_on_tree(adj, 1), 0)
}

///|
test "tree_knapsack: simple tree" {
  // Tree: 0 is root, children: 1, 2.
  // costs: [2, 1, 3], values: [3, 2, 5], capacity: 5
  // Must select 0 to select 1 or 2.
  // Options:
  //   Select 0 only: cost=2, value=3
  //   Select 0+1: cost=3, value=5
  //   Select 0+2: cost=5, value=8
  //   Select 0+1+2: cost=6 > capacity, not possible
  // Best = 0+2 = 8.
  let children : Array[Array[Int]] = [[1, 2], [], []]
  let costs : FixedArray[Int] = FixedArray::make(3, 0)
  costs[0] = 2
  costs[1] = 1
  costs[2] = 3
  let values : FixedArray[Int] = FixedArray::make(3, 0)
  values[0] = 3
  values[1] = 2
  values[2] = 5
  assert_eq(tree_knapsack(children, 3, costs, values, 5), 8L)
}

///|
test "tree_knapsack: deep tree" {
  // Chain: 0 -> 1 -> 2 -> 3
  // costs: [1, 1, 1, 1], values: [1, 2, 3, 4], capacity: 3
  // Must select parent to select child.
  // Best: select all (cost=4 > 3, not possible).
  // Select 0+1+2: cost=3, value=6.
  // Select 0+1+3: not possible (need to select 2 to get 3).
  // Select 0+2+3: not possible (need 1 to get 2).
  // Best = 0+1+2 = 6.
  let children : Array[Array[Int]] = [[1], [2], [3], []]
  let costs = FixedArray::make(4, 1)
  let values : FixedArray[Int] = FixedArray::make(4, 0)
  values[0] = 1
  values[1] = 2
  values[2] = 3
  values[3] = 4
  assert_eq(tree_knapsack(children, 4, costs, values, 3), 6L)
}

///|
test "tree_knapsack: single node" {
  let children : Array[Array[Int]] = [[]]
  let costs = FixedArray::make(1, 5)
  let values = FixedArray::make(1, 10)
  // capacity = 5: can select, value = 10
  assert_eq(tree_knapsack(children, 1, costs, values, 5), 10L)
  // capacity = 3: cannot select, value = 0
  assert_eq(tree_knapsack(children, 1, costs, values, 3), 0L)
}

///|
test "tree_knapsack: empty" {
  let children : Array[Array[Int]] = []
  let costs : FixedArray[Int] = FixedArray::make(0, 0)
  let values : FixedArray[Int] = FixedArray::make(0, 0)
  assert_eq(tree_knapsack(children, 0, costs, values, 10), 0L)
}

///|
test "max_independent_set: deep path (stack safety)" {
  // Path graph with 5000 nodes to verify no stack overflow.
  let n = 5000
  let adj : Array[Array[Int]] = []
  for i = 0; i < n; i = i + 1 {
    adj.push([])
  }
  for i = 0; i < n - 1; i = i + 1 {
    adj[i].push(i + 1)
    adj[i + 1].push(i)
  }
  let weights = FixedArray::make(n, 1)
  // For a path of n nodes, MIS = ceil(n/2) = 2500.
  let result = max_independent_set(adj, n, weights)
  assert_eq(result, 2500L)
}

///|
test "tree_diameter: deep path (stack safety)" {
  // Path graph with 5000 nodes.
  let n = 5000
  let adj : Array[Array[(Int, Int)]] = []
  for i = 0; i < n; i = i + 1 {
    adj.push([])
  }
  for i = 0; i < n - 1; i = i + 1 {
    adj[i].push((i + 1, 1))
    adj[i + 1].push((i, 1))
  }
  // Diameter of a path = n - 1 = 4999.
  assert_eq(tree_diameter(adj, n), 4999L)
}
