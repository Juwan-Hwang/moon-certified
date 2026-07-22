/// Graph traversal algorithms on adjacency-matrix representation.
/// Graph is represented as a FixedArray[Int] of size n*n, where
/// graph[i * n + j] == 1 means there is an edge from i to j.

/// BFS traversal from a source node.
/// Returns the number of reachable nodes (including source).
/// Uses a simple queue implemented with two pointers.
pub fn bfs_count(
  graph : FixedArray[Int],
  n : Int,
  src : Int,
) -> Int where {
  proof_require: 0 <= src && src < n,
  proof_ensure: result => visited_count_ok(n, result),
} {
  let visited = FixedArray::make(n, 0)
  let queue = FixedArray::make(n, 0)
  visited[src] = 1
  queue[0] = src
  let mut head = 0
  let mut tail = 1
  let mut count = 1
  while head < tail {
    let u = queue[head]
    head = head + 1
    for v = 0; v < n; {
      if graph[u * n + v] != 0 && visited[v] == 0 {
        visited[v] = 1
        queue[tail] = v
        tail = tail + 1
        count = count + 1
      }
      continue v + 1
    } nobreak {
      ()
    }
  }
  count
}

/// BFS shortest path from src to all reachable nodes.
/// Returns a FixedArray[Int] of size n where dist[i] is the shortest
/// distance from src to i, or -1 if unreachable.
pub fn bfs_distances(
  graph : FixedArray[Int],
  n : Int,
  src : Int,
) -> FixedArray[Int] {
  let dist = FixedArray::make(n, -1)
  let queue = FixedArray::make(n, 0)
  dist[src] = 0
  queue[0] = src
  let mut head = 0
  let mut tail = 1
  while head < tail {
    let u = queue[head]
    head = head + 1
    for v = 0; v < n; {
      if graph[u * n + v] != 0 && dist[v] == -1 {
        dist[v] = dist[u] + 1
        queue[tail] = v
        tail = tail + 1
      }
      continue v + 1
    } nobreak {
      ()
    }
  }
  dist
}

/// Check if there is a path from src to dst using BFS.
pub fn has_path(
  graph : FixedArray[Int],
  n : Int,
  src : Int,
  dst : Int,
) -> Bool {
  if src == dst {
    return true
  }
  let dist = bfs_distances(graph, n, src)
  dist[dst] != -1
}

/// DFS traversal to count reachable nodes.
/// Uses iterative DFS with a stack.
pub fn dfs_count(
  graph : FixedArray[Int],
  n : Int,
  src : Int,
) -> Int {
  let visited = FixedArray::make(n, 0)
  let stack = FixedArray::make(n, 0)
  visited[src] = 1
  stack[0] = src
  let mut top = 1
  let mut count = 1
  while top > 0 {
    top = top - 1
    let u = stack[top]
    for v = 0; v < n; {
      if graph[u * n + v] != 0 && visited[v] == 0 {
        visited[v] = 1
        stack[top] = v
        top = top + 1
        count = count + 1
      }
      continue v + 1
    } nobreak {
      ()
    }
  }
  count
}

test "bfs_count: single node" {
  let graph = FixedArray::make(1, 0)  // no edges, 1 node
  assert_eq(bfs_count(graph, 1, 0), 1)
}

test "bfs_count: path graph" {
  // 0 -> 1 -> 2 -> 3
  let n = 4
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 1
  graph[1 * n + 2] = 1
  graph[2 * n + 3] = 1
  assert_eq(bfs_count(graph, n, 0), 4)
  assert_eq(bfs_count(graph, n, 2), 2)
}

test "bfs_count: disconnected" {
  // 0 -> 1, 2 -> 3 (disconnected)
  let n = 4
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 1
  graph[2 * n + 3] = 1
  assert_eq(bfs_count(graph, n, 0), 2)
  assert_eq(bfs_count(graph, n, 2), 2)
  assert_eq(bfs_count(graph, n, 3), 1)
}

test "bfs_count: complete graph" {
  let n = 4
  let graph = FixedArray::makei(n * n, fn(i) {
    let row = i / n
    let col = i % n
    if row != col { 1 } else { 0 }
  })
  assert_eq(bfs_count(graph, n, 0), 4)
}

test "bfs_distances: path graph" {
  // 0 -> 1 -> 2 -> 3
  let n = 4
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 1
  graph[1 * n + 2] = 1
  graph[2 * n + 3] = 1
  let dist = bfs_distances(graph, n, 0)
  assert_eq(dist[0], 0)
  assert_eq(dist[1], 1)
  assert_eq(dist[2], 2)
  assert_eq(dist[3], 3)
}

test "bfs_distances: unreachable" {
  // 0 -> 1, 2 is isolated
  let n = 3
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 1
  let dist = bfs_distances(graph, n, 0)
  assert_eq(dist[0], 0)
  assert_eq(dist[1], 1)
  assert_eq(dist[2], -1)
}

test "bfs_distances: star graph" {
  // 0 connected to 1, 2, 3
  let n = 4
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 1
  graph[0 * n + 2] = 1
  graph[0 * n + 3] = 1
  let dist = bfs_distances(graph, n, 0)
  assert_eq(dist[0], 0)
  assert_eq(dist[1], 1)
  assert_eq(dist[2], 1)
  assert_eq(dist[3], 1)
}

test "has_path: connected" {
  let n = 3
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 1
  graph[1 * n + 2] = 1
  assert_eq(has_path(graph, n, 0, 2), true)
}

test "has_path: disconnected" {
  let n = 3
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 1
  assert_eq(has_path(graph, n, 0, 2), false)
}

test "has_path: same node" {
  let n = 3
  let graph = FixedArray::make(n * n, 0)
  assert_eq(has_path(graph, n, 1, 1), true)
}

test "dfs_count: path graph" {
  let n = 4
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 1
  graph[1 * n + 2] = 1
  graph[2 * n + 3] = 1
  assert_eq(dfs_count(graph, n, 0), 4)
}

test "dfs_count: disconnected" {
  let n = 4
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 1
  graph[2 * n + 3] = 1
  assert_eq(dfs_count(graph, n, 0), 2)
}

test "dfs_count: complete graph" {
  let n = 4
  let graph = FixedArray::makei(n * n, fn(i) {
    let row = i / n
    let col = i % n
    if row != col { 1 } else { 0 }
  })
  assert_eq(dfs_count(graph, n, 0), 4)
}

test "bfs_count: cycle" {
  // 0 -> 1 -> 2 -> 0
  let n = 3
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 1
  graph[1 * n + 2] = 1
  graph[2 * n + 0] = 1
  assert_eq(bfs_count(graph, n, 0), 3)
}

test "bfs_distances: cycle distances" {
  // 0 -> 1 -> 2 -> 0
  let n = 3
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 1
  graph[1 * n + 2] = 1
  graph[2 * n + 0] = 1
  let dist = bfs_distances(graph, n, 0)
  assert_eq(dist[0], 0)
  assert_eq(dist[1], 1)
  assert_eq(dist[2], 2)
}
