/// Topological sort using Kahn's algorithm (BFS-based) on an adjacency list.
///
/// Produces a linear ordering of the vertices of a directed acyclic graph
/// (DAG) such that for every directed edge `u -> v`, `u` appears before `v`
/// in the ordering. If the graph contains a cycle, no valid ordering exists.
///
/// The graph is an adjacency list: `graph[i]` is an `Array` of `(neighbor,
/// weight)` pairs, so `graph[i][j] = (v, w)` means a directed edge `i -> v`
/// with weight `w`. The weight is **ignored** — topological sort only cares
/// about edge direction, not edge cost.
///
/// ## Algorithm (Kahn's)
///
///   1. Compute the in-degree of every vertex by scanning all adjacency lists.
///   2. Initialize a FIFO queue with all vertices whose in-degree is 0.
///   3. Repeatedly dequeue a vertex `u`, append it to the result, and decrement
///      the in-degree of each of `u`'s neighbors. When a neighbor's in-degree
///      reaches 0, enqueue it.
///   4. If the result contains all `n` vertices, a valid topological order was
///      found. Otherwise, the graph contains at least one cycle.
///
/// ## Complexity
///
/// - Time: `O(V + E)` — each vertex is enqueued/dequeued once, and each edge
///   is examined exactly once when its source vertex is processed.
/// - Space: `O(V)` for the in-degree array, queue, and result.
///
/// ## Limitations
///
/// - The graph must be a DAG for `topo_sort` to return `Some(...)`. Cycles
///   cause `None`.
/// - Self-loops (`i -> i`) are cycles and are correctly detected.
/// - The ordering is not unique; any valid topological order may be returned.
///   The specific order depends on the order in which zero-in-degree vertices
///   are enqueued (here, lowest index first).
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

/// Compute the in-degree of every vertex from the adjacency list.
///
/// `in_deg[v]` counts how many edges point *into* `v`. Out-of-range neighbor
/// indices are silently skipped (defensive, though well-formed graphs should
/// not produce them).
fn compute_in_degrees(
  graph : Array[Array[(Int, Int)]],
  n : Int,
) -> FixedArray[Int] {
  let in_deg = FixedArray::make(n, 0)
  for u = 0; u < n; u = u + 1 {
    let neighbors = graph[u]
    for j = 0; j < neighbors.length(); j = j + 1 {
      let (v, _) = neighbors[j]
      if v >= 0 && v < n {
        in_deg[v] = in_deg[v] + 1
      }
    }
  }
  in_deg
}

/// Compute a topological ordering of a directed graph using Kahn's algorithm.
///
/// `graph[i]` is an `Array` of `(neighbor, weight)` pairs; weights are ignored.
///
/// Returns `Some(order)` where `order` is a `FixedArray[Int]` of length `n`
/// containing a valid topological ordering, or `None` if the graph contains a
/// cycle or the input is invalid (`n <= 0`, `graph` too small).
///
/// Using `Option` (rather than an empty array) eliminates the ambiguity
/// between "cycle detected" and "valid empty result".
pub fn topo_sort(
  graph : Array[Array[(Int, Int)]],
  n : Int,
) -> FixedArray[Int]? {
  if n <= 0 || graph.length() < n {
    return None
  }
  let in_deg = compute_in_degrees(graph, n)
  let result = FixedArray::make(n, 0)
  // Index-based FIFO queue backed by a FixedArray (no Array::shift overhead).
  let queue = FixedArray::make(n, 0)
  let mut head = 0
  let mut tail = 0
  // Enqueue all vertices with in-degree 0 (seeds of the topological order).
  for i = 0; i < n; i = i + 1 {
    if in_deg[i] == 0 {
      queue[tail] = i
      tail = tail + 1
    }
  }
  // Process the queue: dequeue a vertex, append to result, relax its edges.
  let mut idx = 0
  while head < tail {
    let u = queue[head]
    head = head + 1
    result[idx] = u
    idx = idx + 1
    // Decrement in-degree of each neighbor; enqueue newly-zero vertices.
    let neighbors = graph[u]
    for j = 0; j < neighbors.length(); j = j + 1 {
      let (v, _) = neighbors[j]
      if v >= 0 && v < n {
        in_deg[v] = in_deg[v] - 1
        if in_deg[v] == 0 {
          queue[tail] = v
          tail = tail + 1
        }
      }
    }
  }
  // If not all vertices were processed, a cycle exists.
  if idx < n {
    return None
  }
  Some(result)
}

/// Check whether the directed graph contains a cycle.
///
/// `graph[i]` is an `Array` of `(neighbor, weight)` pairs; weights are ignored.
/// Returns `true` if a cycle exists (including self-loops), `false` if the
/// graph is a valid DAG. Returns `false` for invalid input (`n <= 0`, `graph`
/// too small), since a degenerate input cannot contain a meaningful cycle.
///
/// Internally delegates to `topo_sort`: a cycle exists exactly when Kahn's
/// algorithm cannot place all vertices.
pub fn has_cycle(
  graph : Array[Array[(Int, Int)]],
  n : Int,
) -> Bool {
  if n <= 0 || graph.length() < n {
    return false
  }
  match topo_sort(graph, n) {
    Some(_) => false
    None => true
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "topo_sort: linear DAG" {
  // 0 -> 1 -> 2 -> 3 -> 4
  let n = 5
  let graph : Array[Array[(Int, Int)]] = [[], [], [], [], []]
  for i = 0; i < n - 1; i = i + 1 {
    graph[i].push((i + 1, 1))
  }
  let result = topo_sort(graph, n).unwrap()
  assert_eq(result.length(), n)
  // A linear chain has exactly one valid ordering.
  for i = 0; i < n; i = i + 1 {
    assert_eq(result[i], i)
  }
}

test "topo_sort: branching DAG" {
  //     0
  //    / \
  //   1   2
  //    \ /
  //     3
  //    / \
  //   4   5
  let n = 6
  let graph : Array[Array[(Int, Int)]] = [[], [], [], [], [], []]
  graph[0].push((1, 1))
  graph[0].push((2, 1))
  graph[1].push((3, 1))
  graph[2].push((3, 1))
  graph[3].push((4, 1))
  graph[3].push((5, 1))
  let result = topo_sort(graph, n).unwrap()
  assert_eq(result.length(), n)
  // 0 must come first, 4 and 5 must come after 3.
  assert_eq(result[0], 0)
  // Verify ordering constraints: 0 < 1, 0 < 2, 1 < 3, 2 < 3, 3 < 4, 3 < 5.
  let pos = FixedArray::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    pos[result[i]] = i
  }
  assert_true(pos[0] < pos[1])
  assert_true(pos[0] < pos[2])
  assert_true(pos[1] < pos[3])
  assert_true(pos[2] < pos[3])
  assert_true(pos[3] < pos[4])
  assert_true(pos[3] < pos[5])
}

test "topo_sort: cycle detection" {
  // 0 -> 1 -> 2 -> 0 (3-cycle)
  let n = 3
  let graph : Array[Array[(Int, Int)]] = [[], [], []]
  graph[0].push((1, 1))
  graph[1].push((2, 1))
  graph[2].push((0, 1))
  assert_true(topo_sort(graph, n) is None)
  assert_eq(has_cycle(graph, n), true)
}

test "topo_sort: single node" {
  let graph : Array[Array[(Int, Int)]] = [[]]
  let result = topo_sort(graph, 1).unwrap()
  assert_eq(result.length(), 1)
  assert_eq(result[0], 0)
  assert_eq(has_cycle(graph, 1), false)
}

test "topo_sort: disconnected DAG" {
  // Component A: 0 -> 1, Component B: 2 -> 3
  let n = 4
  let graph : Array[Array[(Int, Int)]] = [[], [], [], []]
  graph[0].push((1, 1))
  graph[2].push((3, 1))
  let result = topo_sort(graph, n).unwrap()
  assert_eq(result.length(), n)
  // 0 before 1, 2 before 3 (within each component).
  let pos = FixedArray::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    pos[result[i]] = i
  }
  assert_true(pos[0] < pos[1])
  assert_true(pos[2] < pos[3])
  assert_eq(has_cycle(graph, n), false)
}

test "topo_sort: complex DAG" {
  //       0
  //      / \
  //     1   2
  //    / \   \
  //   3   4   5
  //    \ /   /
  //     6   /
  //      \ /
  //       7
  let n = 8
  let graph : Array[Array[(Int, Int)]] = [
    [], [], [], [], [], [], [], [],
  ]
  graph[0].push((1, 1))
  graph[0].push((2, 1))
  graph[1].push((3, 1))
  graph[1].push((4, 1))
  graph[2].push((5, 1))
  graph[3].push((6, 1))
  graph[4].push((6, 1))
  graph[5].push((7, 1))
  graph[6].push((7, 1))
  let result = topo_sort(graph, n).unwrap()
  assert_eq(result.length(), n)
  // Verify all edge constraints.
  let pos = FixedArray::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    pos[result[i]] = i
  }
  assert_true(pos[0] < pos[1])
  assert_true(pos[0] < pos[2])
  assert_true(pos[1] < pos[3])
  assert_true(pos[1] < pos[4])
  assert_true(pos[2] < pos[5])
  assert_true(pos[3] < pos[6])
  assert_true(pos[4] < pos[6])
  assert_true(pos[5] < pos[7])
  assert_true(pos[6] < pos[7])
  assert_eq(has_cycle(graph, n), false)
}

test "topo_sort: self-loop is a cycle" {
  let n = 2
  let graph : Array[Array[(Int, Int)]] = [[], []]
  graph[0].push((0, 1)) // self-loop on vertex 0
  assert_true(topo_sort(graph, n) is None)
  assert_eq(has_cycle(graph, n), true)
}

test "topo_sort: two-node cycle" {
  // 0 -> 1 -> 0
  let n = 2
  let graph : Array[Array[(Int, Int)]] = [[], []]
  graph[0].push((1, 1))
  graph[1].push((0, 1))
  assert_true(topo_sort(graph, n) is None)
  assert_eq(has_cycle(graph, n), true)
}

test "topo_sort: no edges" {
  // All vertices isolated: any permutation is a valid topological order.
  let n = 5
  let graph : Array[Array[(Int, Int)]] = [[], [], [], [], []]
  let result = topo_sort(graph, n).unwrap()
  assert_eq(result.length(), n)
  // Every vertex must appear exactly once.
  let seen = FixedArray::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    seen[result[i]] = 1
  }
  for i = 0; i < n; i = i + 1 {
    assert_eq(seen[i], 1)
  }
  assert_eq(has_cycle(graph, n), false)
}

test "topo_sort: diamond DAG" {
  //   0
  //  / \
  // 1   2
  //  \ /
  //   3
  let n = 4
  let graph : Array[Array[(Int, Int)]] = [[], [], [], []]
  graph[0].push((1, 1))
  graph[0].push((2, 1))
  graph[1].push((3, 1))
  graph[2].push((3, 1))
  let result = topo_sort(graph, n).unwrap()
  assert_eq(result.length(), n)
  assert_eq(result[0], 0) // 0 has no predecessors
  assert_eq(result[n - 1], 3) // 3 has no successors
}

test "topo_sort: weights are ignored" {
  // Same diamond as above but with arbitrary weights.
  let n = 4
  let graph : Array[Array[(Int, Int)]] = [[], [], [], []]
  graph[0].push((1, 99))
  graph[0].push((2, 42))
  graph[1].push((3, 7))
  graph[2].push((3, 1000))
  let result = topo_sort(graph, n).unwrap()
  assert_eq(result.length(), n)
  assert_eq(result[0], 0)
  assert_eq(result[n - 1], 3)
}

test "topo_sort: cycle with extra nodes" {
  // 0 -> 1 -> 2 -> 3 -> 1  (cycle: 1 -> 2 -> 3 -> 1)
  // 0 is outside the cycle but feeds into it.
  let n = 4
  let graph : Array[Array[(Int, Int)]] = [[], [], [], []]
  graph[0].push((1, 1))
  graph[1].push((2, 1))
  graph[2].push((3, 1))
  graph[3].push((1, 1))
  assert_true(topo_sort(graph, n) is None)
  assert_eq(has_cycle(graph, n), true)
}

test "topo_sort: partial cycle detection" {
  // 0 -> 1 -> 2 (DAG), plus 3 -> 4 -> 3 (cycle).
  let n = 5
  let graph : Array[Array[(Int, Int)]] = [[], [], [], [], []]
  graph[0].push((1, 1))
  graph[1].push((2, 1))
  graph[3].push((4, 1))
  graph[4].push((3, 1))
  assert_true(topo_sort(graph, n) is None)
  assert_eq(has_cycle(graph, n), true)
}

test "topo_sort: invalid input" {
  assert_true(topo_sort([], 0) is None) // n = 0
  assert_true(topo_sort([], -1) is None) // n < 0
  // graph too small for n
  let small : Array[Array[(Int, Int)]] = [[], []]
  assert_true(topo_sort(small, 5) is None)
  // has_cycle returns false for invalid input (no meaningful cycle).
  assert_eq(has_cycle([], 0), false)
  assert_eq(has_cycle(small, 5), false)
}

test "topo_sort: complete DAG" {
  // Complete DAG: edges i -> j for all i < j.
  // The only valid topological ordering is 0, 1, 2, ..., n-1.
  let n = 6
  let graph : Array[Array[(Int, Int)]] = []
  for i = 0; i < n; i = i + 1 {
    graph.push([])
  }
  for i = 0; i < n; i = i + 1 {
    for j = i + 1; j < n; j = j + 1 {
      graph[i].push((j, 1))
    }
  }
  let result = topo_sort(graph, n).unwrap()
  assert_eq(result.length(), n)
  for i = 0; i < n; i = i + 1 {
    assert_eq(result[i], i)
  }
  assert_eq(has_cycle(graph, n), false)
}

test "topo_sort: larger linear chain" {
  let n = 100
  let graph : Array[Array[(Int, Int)]] = []
  for i = 0; i < n; i = i + 1 {
    graph.push([])
  }
  for i = 0; i < n - 1; i = i + 1 {
    graph[i].push((i + 1, 1))
  }
  let result = topo_sort(graph, n).unwrap()
  assert_eq(result.length(), n)
  for i = 0; i < n; i = i + 1 {
    assert_eq(result[i], i)
  }
}
