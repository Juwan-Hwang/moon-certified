/// Tarjan's Strongly Connected Components algorithm.
///
/// Decomposes a directed graph into its strongly connected components (SCCs).
/// The graph is a flat `n * n` adjacency matrix where `graph[i * n + j] != 0`
/// means there is a directed edge `i -> j`.
///
/// Uses Tarjan's single-pass DFS with a single stack and two arrays (`index`
/// and `lowlink`). Time O(n + e) where e is the number of edges; space O(n).
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

/// Mutable algorithm state, threaded through the recursive DFS.
priv struct SccState {
  graph : FixedArray[Int]
  n : Int
  mut index_counter : Int
  indices : FixedArray[Int] // -1 = not yet visited
  lowlink : FixedArray[Int]
  on_stack : FixedArray[Bool]
  stack : FixedArray[Int]
  mut stack_top : Int
  result : Array[FixedArray[Int]]
}

fn new_state(graph : FixedArray[Int], n : Int) -> SccState {
  {
    graph,
    n,
    index_counter: 0,
    indices: FixedArray::make(n, -1),
    lowlink: FixedArray::make(n, 0),
    on_stack: FixedArray::make(n, false),
    stack: FixedArray::make(n, 0),
    stack_top: 0,
    result: [],
  }
}

/// Iterative DFS core of Tarjan's algorithm.
/// Uses an explicit stack to avoid recursion depth limits.
fn strongconnect(state : SccState, start : Int) -> Unit {
  // Stack of (vertex, next_neighbor_index) pairs.
  let dfs_stack : Array[(Int, Int)] = [(start, 0)]

  state.indices[start] = state.index_counter
  state.lowlink[start] = state.index_counter
  state.index_counter = state.index_counter + 1
  state.stack[state.stack_top] = start
  state.stack_top = state.stack_top + 1
  state.on_stack[start] = true

  while dfs_stack.length() > 0 {
    let top_idx = dfs_stack.length() - 1
    let (v, next_w) = dfs_stack[top_idx]
    if next_w < state.n {
      // Try neighbor next_w
      let w = next_w
      // Update the next neighbor to try
      dfs_stack[top_idx] = (v, next_w + 1)

      if state.graph[v * state.n + w] != 0 {
        if state.indices[w] == -1 {
          // Tree edge: push w onto DFS stack
          state.indices[w] = state.index_counter
          state.lowlink[w] = state.index_counter
          state.index_counter = state.index_counter + 1
          state.stack[state.stack_top] = w
          state.stack_top = state.stack_top + 1
          state.on_stack[w] = true
          dfs_stack.push((w, 0))
        } else if state.on_stack[w] {
          // Back/cross edge to node on stack
          if state.indices[w] < state.lowlink[v] {
            state.lowlink[v] = state.indices[w]
          }
        }
      }
    } else {
      // All neighbors of v explored: check if v is SCC root
      ignore(dfs_stack.pop())

      // If v has a parent in DFS tree, update parent's lowlink
      if dfs_stack.length() > 0 {
        let parent_idx = dfs_stack.length() - 1
        let (parent, _) = dfs_stack[parent_idx]
        if state.lowlink[v] < state.lowlink[parent] {
          state.lowlink[parent] = state.lowlink[v]
        }
      }

      // If v is the root of an SCC, pop the stack to collect the component.
      if state.lowlink[v] == state.indices[v] {
        let scc : Array[Int] = []
        let mut w = -1
        while w != v {
          state.stack_top = state.stack_top - 1
          w = state.stack[state.stack_top]
          state.on_stack[w] = false
          scc.push(w)
        }
        state.result.push(FixedArray::makei(scc.length(), fn(i) { scc[i] }))
      }
    }
  }
}

/// Compute the strongly connected components of a directed graph.
///
/// # Parameters
/// - `graph`: the `n * n` adjacency matrix. A non-zero `graph[i * n + j]`
///   denotes a directed edge `i -> j`.
/// - `n`: the number of vertices, indexed `0 .. n - 1`.
///
/// # Returns
/// A `FixedArray[FixedArray[Int]]` where each inner array is one SCC (a list
/// of vertex indices). SCCs appear in reverse topological order: if there is
/// an edge from SCC A to SCC B (A != B), then B appears before A. Returns an
/// empty outer array when `n <= 0` or the matrix is too small.
pub fn tarjan_scc(
  graph : FixedArray[Int],
  n : Int,
) -> FixedArray[FixedArray[Int]] {
  if n <= 0 || graph.length() < n * n {
    return FixedArray::make(0, FixedArray::make(0, 0))
  }
  let state = new_state(graph, n)
  for v = 0; v < n; v = v + 1 {
    if state.indices[v] == -1 {
      strongconnect(state, v)
    }
  }
  FixedArray::makei(state.result.length(), fn(i) { state.result[i] })
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

/// Return the index of the SCC containing vertex v, or -1 if not found.
fn scc_of(result : FixedArray[FixedArray[Int]], v : Int) -> Int {
  for i = 0; i < result.length(); i = i + 1 {
    let scc = result[i]
    for j = 0; j < scc.length(); j = j + 1 {
      if scc[j] == v {
        return i
      }
    }
  }
  -1
}

/// True when vertices a and b belong to the same SCC.
fn same_scc(result : FixedArray[FixedArray[Int]], a : Int, b : Int) -> Bool {
  scc_of(result, a) == scc_of(result, b)
}

/// Count the total number of vertices across all SCCs.
fn total_vertices(result : FixedArray[FixedArray[Int]]) -> Int {
  let mut total = 0
  for i = 0; i < result.length(); i = i + 1 {
    total = total + result[i].length()
  }
  total
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "scc: single node" {
  let graph = FixedArray::make(1, 0)
  let result = tarjan_scc(graph, 1)
  assert_eq(result.length(), 1)
  assert_eq(result[0].length(), 1)
  assert_eq(result[0][0], 0)
}

test "scc: DAG (each node its own SCC)" {
  // 0 -> 1 -> 2
  let n = 3
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 1
  graph[1 * n + 2] = 1
  let result = tarjan_scc(graph, n)
  assert_eq(result.length(), 3)
  assert_eq(total_vertices(result), 3)
  // No two distinct nodes share an SCC.
  assert_eq(same_scc(result, 0, 1), false)
  assert_eq(same_scc(result, 1, 2), false)
  assert_eq(same_scc(result, 0, 2), false)
}

test "scc: simple cycle" {
  // 0 -> 1 -> 2 -> 0
  let n = 3
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 1
  graph[1 * n + 2] = 1
  graph[2 * n + 0] = 1
  let result = tarjan_scc(graph, n)
  assert_eq(result.length(), 1)
  assert_eq(result[0].length(), 3)
  assert_eq(same_scc(result, 0, 1), true)
  assert_eq(same_scc(result, 1, 2), true)
  assert_eq(same_scc(result, 0, 2), true)
}

test "scc: two separate cycles" {
  // 0 -> 1 -> 0  and  2 -> 3 -> 2
  let n = 4
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 1
  graph[1 * n + 0] = 1
  graph[2 * n + 3] = 1
  graph[3 * n + 2] = 1
  let result = tarjan_scc(graph, n)
  assert_eq(result.length(), 2)
  assert_eq(total_vertices(result), 4)
  assert_eq(same_scc(result, 0, 1), true)
  assert_eq(same_scc(result, 2, 3), true)
  assert_eq(same_scc(result, 0, 2), false)
}

test "scc: complete graph" {
  // Every pair has edges both ways: one big SCC.
  let n = 4
  let graph = FixedArray::makei(n * n, fn(i) {
    let row = i / n
    let col = i % n
    if row != col { 1 } else { 0 }
  })
  let result = tarjan_scc(graph, n)
  assert_eq(result.length(), 1)
  assert_eq(result[0].length(), 4)
}

test "scc: disconnected components" {
  // Component A: 0 -> 1 -> 0 (cycle). Component B: 2 -> 3 (DAG).
  let n = 4
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 1
  graph[1 * n + 0] = 1
  graph[2 * n + 3] = 1
  let result = tarjan_scc(graph, n)
  assert_eq(result.length(), 3)
  assert_eq(total_vertices(result), 4)
  assert_eq(same_scc(result, 0, 1), true)
  assert_eq(same_scc(result, 2, 3), false)
}

test "scc: self-loop" {
  // A single node with a self-loop is still an SCC of size 1.
  let n = 1
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 0] = 1
  let result = tarjan_scc(graph, n)
  assert_eq(result.length(), 1)
  assert_eq(result[0].length(), 1)
  assert_eq(result[0][0], 0)
}

test "scc: self-loop among other nodes" {
  // 0 -> 0 (self-loop), 0 -> 1 -> 2 -> 1 (cycle between 1 and 2).
  let n = 3
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 0] = 1
  graph[0 * n + 1] = 1
  graph[1 * n + 2] = 1
  graph[2 * n + 1] = 1
  let result = tarjan_scc(graph, n)
  assert_eq(result.length(), 2)
  assert_eq(same_scc(result, 1, 2), true)
  assert_eq(same_scc(result, 0, 1), false)
  assert_eq(same_scc(result, 0, 2), false)
}

test "scc: invalid n returns empty" {
  let graph = FixedArray::make(9, 0)
  assert_eq(tarjan_scc(graph, 0).length(), 0)
  assert_eq(tarjan_scc(graph, -1).length(), 0)
}

test "scc: graph too small returns empty" {
  // n=3 needs 9 entries; provide only 4.
  let graph = FixedArray::make(4, 0)
  assert_eq(tarjan_scc(graph, 3).length(), 0)
}

test "scc: large graph (8 nodes, mixed structure)" {
  // 0 -> 1 -> 0        (cycle: {0, 1})
  // 1 -> 2 -> 3 -> 2   (cycle: {2, 3}, reachable from {0,1})
  // 4 -> 5 -> 6 -> 4   (cycle: {4, 5, 6}, disconnected from above)
  // 7 -> 4             (7 points into the second cycle)
  let n = 8
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 1
  graph[1 * n + 0] = 1
  graph[1 * n + 2] = 1
  graph[2 * n + 3] = 1
  graph[3 * n + 2] = 1
  graph[4 * n + 5] = 1
  graph[5 * n + 6] = 1
  graph[6 * n + 4] = 1
  graph[7 * n + 4] = 1
  let result = tarjan_scc(graph, n)
  assert_eq(result.length(), 4) // {0,1}, {2,3}, {4,5,6}, {7}
  assert_eq(total_vertices(result), 8)
  assert_eq(same_scc(result, 0, 1), true)
  assert_eq(same_scc(result, 2, 3), true)
  assert_eq(same_scc(result, 4, 5), true)
  assert_eq(same_scc(result, 5, 6), true)
  assert_eq(same_scc(result, 4, 6), true)
  // 7 is its own SCC.
  assert_eq(scc_of(result, 7) != scc_of(result, 4), true)
  assert_eq(same_scc(result, 0, 2), false)
  assert_eq(same_scc(result, 1, 4), false)
}

test "scc: reverse topological order" {
  // 0 -> 1 -> 2 -> 0 (cycle C1) and 3 -> 0 (3 reaches C1).
  // Tarjan emits SCCs in reverse topological order: {0,1,2} before {3}.
  let n = 4
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 1
  graph[1 * n + 2] = 1
  graph[2 * n + 0] = 1
  graph[3 * n + 0] = 1
  let result = tarjan_scc(graph, n)
  assert_eq(result.length(), 2)
  // The cycle SCC {0,1,2} must come before the singleton {3}.
  assert_eq(result[0].length(), 3)
  assert_eq(result[1].length(), 1)
}
