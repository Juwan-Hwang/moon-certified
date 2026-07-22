/// Topological sort using Kahn's algorithm (BFS-based).
/// Graph is represented as an adjacency matrix: graph[i * n + j] == 1
/// means there is a directed edge from i to j.
/// Returns a FixedArray of size n with a valid topological ordering,
/// or a FixedArray of size 0 if the graph contains a cycle.

/// Compute in-degree of each node from the adjacency matrix.
fn compute_in_degrees(graph : FixedArray[Int], n : Int) -> FixedArray[Int] {
  let in_deg = FixedArray::make(n, 0)
  for i = 0; i < n; {
    for j = 0; j < n; {
      if graph[i * n + j] != 0 {
        in_deg[j] = in_deg[j] + 1
      }
      continue j + 1
    } nobreak {
      ()
    }
    continue i + 1
  } nobreak {
    ()
  }
  in_deg
}

/// Topological sort using Kahn's algorithm.
/// Returns a FixedArray of size n containing a valid topological ordering,
/// or a FixedArray of size 0 if the graph contains a cycle or n <= 0.
pub fn topo_sort(graph : FixedArray[Int], n : Int) -> FixedArray[Int] {
  if n <= 0 || graph.length() < n * n {
    return FixedArray::make(0, 0)
  }
  let in_deg = compute_in_degrees(graph, n)
  let result = FixedArray::make(n, 0)
  let queue = FixedArray::make(n, 0)
  let mut head = 0
  let mut tail = 0
  // Enqueue all nodes with in-degree 0
  for i = 0; i < n; {
    if in_deg[i] == 0 {
      queue[tail] = i
      tail = tail + 1
    }
    continue i + 1
  } nobreak {
    ()
  }
  // Process queue (Kahn's algorithm)
  let mut idx = 0
  while head < tail {
    let u = queue[head]
    head = head + 1
    result[idx] = u
    idx = idx + 1
    // Decrease in-degree of all neighbors; enqueue new zero-in-degree nodes
    for v = 0; v < n; {
      if graph[u * n + v] != 0 {
        in_deg[v] = in_deg[v] - 1
        if in_deg[v] == 0 {
          queue[tail] = v
          tail = tail + 1
        }
      }
      continue v + 1
    } nobreak {
      ()
    }
  }
  // If not all nodes were processed, a cycle exists
  if idx < n {
    return FixedArray::make(0, 0)
  }
  result
}

test "topo_sort: DAG" {
  // 0 -> 1 -> 3
  // 0 -> 2 -> 3
  let n = 4
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 1
  graph[0 * n + 2] = 1
  graph[1 * n + 3] = 1
  graph[2 * n + 3] = 1
  let result = topo_sort(graph, n)
  assert_eq(result.length(), n)
  // 0 must come before 1, 2, 3; 3 must come last
  assert_eq(result[0], 0)
  assert_eq(result[n - 1], 3)
}

test "topo_sort: cyclic graph returns empty" {
  // 0 -> 1 -> 2 -> 0
  let n = 3
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 1
  graph[1 * n + 2] = 1
  graph[2 * n + 0] = 1
  let result = topo_sort(graph, n)
  assert_eq(result.length(), 0)
}

test "topo_sort: single node" {
  let n = 1
  let graph = FixedArray::make(n * n, 0)
  let result = topo_sort(graph, n)
  assert_eq(result.length(), 1)
  assert_eq(result[0], 0)
}

test "topo_sort: linear chain" {
  // 0 -> 1 -> 2 -> 3 -> 4
  let n = 5
  let graph = FixedArray::make(n * n, 0)
  for i = 0; i < n - 1; i = i + 1 {
    graph[i * n + (i + 1)] = 1
  }
  let result = topo_sort(graph, n)
  assert_eq(result.length(), n)
  // Linear chain has exactly one valid ordering
  for i = 0; i < n; i = i + 1 {
    assert_eq(result[i], i)
  }
}

test "topo_sort: diamond" {
  //   0
  //  / \
  // 1   2
  //  \ /
  //   3
  let n = 4
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 1
  graph[0 * n + 2] = 1
  graph[1 * n + 3] = 1
  graph[2 * n + 3] = 1
  let result = topo_sort(graph, n)
  assert_eq(result.length(), n)
  // 0 must be first, 3 must be last
  assert_eq(result[0], 0)
  assert_eq(result[n - 1], 3)
}

test "topo_sort: disconnected DAG" {
  // 0 -> 1, 2 -> 3 (disconnected components)
  let n = 4
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 1
  graph[2 * n + 3] = 1
  let result = topo_sort(graph, n)
  assert_eq(result.length(), n)
  // 0 before 1, 2 before 3
  let mut pos0 = -1
  let mut pos1 = -1
  let mut pos2 = -1
  let mut pos3 = -1
  for i = 0; i < n; i = i + 1 {
    if result[i] == 0 { pos0 = i }
    if result[i] == 1 { pos1 = i }
    if result[i] == 2 { pos2 = i }
    if result[i] == 3 { pos3 = i }
  }
  assert_eq(pos0 < pos1, true)
  assert_eq(pos2 < pos3, true)
}

test "topo_sort: invalid n returns empty" {
  let graph = FixedArray::make(0, 0)
  assert_eq(topo_sort(graph, 0).length(), 0)
  assert_eq(topo_sort(graph, -1).length(), 0)
}

test "topo_sort: self-loop is a cycle" {
  let n = 2
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 0] = 1 // self-loop on node 0
  let result = topo_sort(graph, n)
  assert_eq(result.length(), 0)
}

test "topo_sort: complete DAG" {
  // Complete DAG: edges i->j for all i < j
  let n = 5
  let graph = FixedArray::makei(n * n, fn(i) {
    let row = i / n
    let col = i % n
    if row < col { 1 } else { 0 }
  })
  let result = topo_sort(graph, n)
  assert_eq(result.length(), n)
  // The only valid ordering is 0, 1, 2, 3, 4
  for i = 0; i < n; i = i + 1 {
    assert_eq(result[i], i)
  }
}

test "topo_sort: no edges" {
  let n = 5
  let graph = FixedArray::make(n * n, 0)
  let result = topo_sort(graph, n)
  assert_eq(result.length(), n)
  // All nodes have in-degree 0; verify all are present
  let seen = FixedArray::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    seen[result[i]] = 1
  }
  for i = 0; i < n; i = i + 1 {
    assert_eq(seen[i], 1)
  }
}

test "topo_sort: larger DAG" {
  // 0 -> 1, 0 -> 2, 1 -> 3, 2 -> 3, 3 -> 4, 1 -> 4
  let n = 5
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 1
  graph[0 * n + 2] = 1
  graph[1 * n + 3] = 1
  graph[2 * n + 3] = 1
  graph[3 * n + 4] = 1
  graph[1 * n + 4] = 1
  let result = topo_sort(graph, n)
  assert_eq(result.length(), n)
  assert_eq(result[0], 0)
  assert_eq(result[n - 1], 4)
}

test "topo_sort: two-node cycle" {
  // 0 -> 1 -> 0
  let n = 2
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 1
  graph[1 * n + 0] = 1
  let result = topo_sort(graph, n)
  assert_eq(result.length(), 0)
}
