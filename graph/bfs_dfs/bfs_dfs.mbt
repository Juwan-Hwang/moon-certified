/// Graph traversal algorithms on an adjacency-matrix representation.
///
/// The graph is a flat `FixedArray[Int]` of length `n * n`, indexed by
/// `graph[i * n + j]`; a non-zero entry denotes a directed edge `i -> j`.
///
/// Input validation policy:
///   - `bfs_count` / `dfs_count`  -> 0 (a valid count is always ≥ 1 since
///      the source reaches itself, so 0 unambiguously signals invalid input)
///   - `bfs_distances`            -> None (Option distinguishes "invalid
///      input" from a valid distance array)
///   - `has_path`                 -> false (safe default for "no path")
///
/// For `bfs_distances`, unreachable vertices are marked `-1` in the result
/// array. This is unambiguous because BFS hop counts are always ≥ 0.
///
/// This package has `proof-enabled: false`, so correctness is backed by the
/// test suite rather than by the MoonBit proof system.

/// Shared precondition check: `n` is a positive matrix dimension, `src` is a
/// valid node index, and `graph` is large enough to hold the full `n * n`
/// adjacency matrix. Returns `true` when the input is unacceptable.
fn invalid_input(
  graph : FixedArray[Int],
  n : Int,
  src : Int,
) -> Bool {
  n <= 0 || src < 0 || src >= n || graph.length() < n * n
}

/// Count the nodes reachable from `src` (including `src` itself) via BFS.
///
/// Returns 0 for invalid input. A valid count is always ≥ 1 (the source
/// itself), so 0 unambiguously signals an error. Time O(n^2), space O(n).
pub fn bfs_count(
  graph : FixedArray[Int],
  n : Int,
  src : Int,
) -> Int {
  if invalid_input(graph, n, src) {
    return 0
  }
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
    let mut v = 0
    while v < n {
      if graph[u * n + v] != 0 && visited[v] == 0 {
        visited[v] = 1
        queue[tail] = v
        tail = tail + 1
        count = count + 1
      }
      v = v + 1
    }
  }
  count
}

/// Compute shortest-path distances from `src` to every node via BFS.
///
/// Returns `Some(dist)` where `dist` is a `FixedArray[Int]` of length `n`
/// with `dist[i]` being the hop count from `src` to `i`, or `-1` when `i`
/// is unreachable. Returns `None` for invalid input.
///
/// The `-1` sentinel for unreachable is safe because BFS hop counts are
/// always non-negative. Time O(n^2), space O(n).
pub fn bfs_distances(
  graph : FixedArray[Int],
  n : Int,
  src : Int,
) -> FixedArray[Int]? {
  if invalid_input(graph, n, src) {
    return None
  }
  let dist = FixedArray::make(n, -1)
  let queue = FixedArray::make(n, 0)
  dist[src] = 0
  queue[0] = src
  let mut head = 0
  let mut tail = 1
  while head < tail {
    let u = queue[head]
    head = head + 1
    let mut v = 0
    while v < n {
      if graph[u * n + v] != 0 && dist[v] == -1 {
        dist[v] = dist[u] + 1
        queue[tail] = v
        tail = tail + 1
      }
      v = v + 1
    }
  }
  Some(dist)
}

/// Report whether `dst` is reachable from `src`.
///
/// Uses an early-exit BFS that returns `true` the moment `dst` is discovered,
/// without computing distances to the rest of the graph. A node is trivially
/// reachable from itself. Returns `false` for invalid input; validation runs
/// before the `src == dst` shortcut, so out-of-bounds self-paths are rejected.
pub fn has_path(
  graph : FixedArray[Int],
  n : Int,
  src : Int,
  dst : Int,
) -> Bool {
  if invalid_input(graph, n, src) || dst < 0 || dst >= n {
    return false
  }
  if src == dst {
    return true
  }
  let visited = FixedArray::make(n, 0)
  let queue = FixedArray::make(n, 0)
  visited[src] = 1
  queue[0] = src
  let mut head = 0
  let mut tail = 1
  while head < tail {
    let u = queue[head]
    head = head + 1
    let mut v = 0
    while v < n {
      if graph[u * n + v] != 0 && visited[v] == 0 {
        // `dst` is reachable and unvisited: discovered for the first time.
        if v == dst {
          return true
        }
        visited[v] = 1
        queue[tail] = v
        tail = tail + 1
      }
      v = v + 1
    }
  }
  false
}

/// Count the nodes reachable from `src` (including `src` itself) via iterative
/// DFS with an explicit stack. Returns 0 for invalid input.
/// Time O(n^2), space O(n).
pub fn dfs_count(
  graph : FixedArray[Int],
  n : Int,
  src : Int,
) -> Int {
  if invalid_input(graph, n, src) {
    return 0
  }
  let visited = FixedArray::make(n, 0)
  let stack = FixedArray::make(n, 0)
  visited[src] = 1
  stack[0] = src
  let mut top = 1
  let mut count = 1
  while top > 0 {
    top = top - 1
    let u = stack[top]
    let mut v = 0
    while v < n {
      if graph[u * n + v] != 0 && visited[v] == 0 {
        visited[v] = 1
        stack[top] = v
        top = top + 1
        count = count + 1
      }
      v = v + 1
    }
  }
  count
}

// ---------------------------------------------------------------------------
// Correctness tests on well-formed graphs.
// ---------------------------------------------------------------------------

test "bfs_count: single node" {
  let graph = FixedArray::make(1, 0) // no edges, 1 node
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

test "bfs_count: cycle" {
  // 0 -> 1 -> 2 -> 0
  let n = 3
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 1
  graph[1 * n + 2] = 1
  graph[2 * n + 0] = 1
  assert_eq(bfs_count(graph, n, 0), 3)
}

test "bfs_distances: path graph" {
  // 0 -> 1 -> 2 -> 3
  let n = 4
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 1
  graph[1 * n + 2] = 1
  graph[2 * n + 3] = 1
  let dist = bfs_distances(graph, n, 0).unwrap()
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
  let dist = bfs_distances(graph, n, 0).unwrap()
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
  let dist = bfs_distances(graph, n, 0).unwrap()
  assert_eq(dist[0], 0)
  assert_eq(dist[1], 1)
  assert_eq(dist[2], 1)
  assert_eq(dist[3], 1)
}

test "bfs_distances: cycle distances" {
  // 0 -> 1 -> 2 -> 0
  let n = 3
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 1
  graph[1 * n + 2] = 1
  graph[2 * n + 0] = 1
  let dist = bfs_distances(graph, n, 0).unwrap()
  assert_eq(dist[0], 0)
  assert_eq(dist[1], 1)
  assert_eq(dist[2], 2)
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

test "has_path: consistent with bfs_distances" {
  let n = 5
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 1
  graph[1 * n + 2] = 1
  graph[3 * n + 4] = 1
  let dist = bfs_distances(graph, n, 0).unwrap()
  for k = 0; k < n; k = k + 1 {
    assert_eq(has_path(graph, n, 0, k), dist[k] != -1)
  }
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

// ---------------------------------------------------------------------------
// Input validation tests.
// ---------------------------------------------------------------------------

test "bfs_count: invalid input returns 0" {
  let n = 3
  let graph = FixedArray::make(n * n, 0)
  // out-of-bounds src
  assert_eq(bfs_count(graph, n, -1), 0)
  assert_eq(bfs_count(graph, n, 3), 0)
  assert_eq(bfs_count(graph, n, 100), 0)
  // n == 0
  assert_eq(bfs_count(FixedArray::make(0, 0), 0, 0), 0)
  // graph too small for n (needs 9, given 4)
  assert_eq(bfs_count(FixedArray::make(4, 0), n, 0), 0)
}

test "bfs_distances: invalid input returns None" {
  let n = 3
  let graph = FixedArray::make(n * n, 0)
  // out-of-bounds src
  assert_true(bfs_distances(graph, n, -1) is None)
  assert_true(bfs_distances(graph, n, n) is None)
  // n == 0
  assert_true(bfs_distances(FixedArray::make(0, 0), 0, 0) is None)
  // graph too small for n
  assert_true(bfs_distances(FixedArray::make(4, 0), n, 0) is None)
}

test "dfs_count: invalid input returns 0" {
  let n = 3
  let graph = FixedArray::make(n * n, 0)
  // out-of-bounds src
  assert_eq(dfs_count(graph, n, -1), 0)
  assert_eq(dfs_count(graph, n, n), 0)
  // n == 0
  assert_eq(dfs_count(FixedArray::make(0, 0), 0, 0), 0)
  // graph too small for n
  assert_eq(dfs_count(FixedArray::make(4, 0), n, 0), 0)
}

test "has_path: out-of-bounds src returns false" {
  let n = 3
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 1
  assert_eq(has_path(graph, n, -1, 0), false)
  assert_eq(has_path(graph, n, n, 0), false)
  assert_eq(has_path(graph, n, 99, 1), false)
}

test "has_path: out-of-bounds dst returns false" {
  let n = 3
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 1
  assert_eq(has_path(graph, n, 0, -1), false)
  assert_eq(has_path(graph, n, 0, n), false)
  assert_eq(has_path(graph, n, 0, 99), false)
}

test "has_path: n=0 returns false" {
  assert_eq(has_path(FixedArray::make(0, 0), 0, 0, 0), false)
}

test "has_path: graph too small returns false" {
  // n=3 needs 9 entries; provide only 4
  assert_eq(has_path(FixedArray::make(4, 0), 3, 0, 1), false)
}

test "has_path: src==dst out of bounds returns false" {
  // Validation must run before the src==dst shortcut.
  let n = 3
  let graph = FixedArray::make(n * n, 0)
  assert_eq(has_path(graph, n, 5, 5), false)
  assert_eq(has_path(graph, n, -1, -1), false)
}

test "has_path: src==dst valid returns true" {
  // Even without a self-loop, a node is trivially reachable from itself.
  let n = 4
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 1
  graph[1 * n + 2] = 1
  assert_eq(has_path(graph, n, 0, 0), true)
  assert_eq(has_path(graph, n, 2, 2), true)
  assert_eq(has_path(graph, n, 3, 3), true)
}

// ---------------------------------------------------------------------------
// n=1 and self-loop edge cases.
// ---------------------------------------------------------------------------

test "bfs_distances: single node" {
  let graph = FixedArray::make(1, 0)
  let dist = bfs_distances(graph, 1, 0).unwrap()
  assert_eq(dist[0], 0)
}

test "dfs_count: single node" {
  let graph = FixedArray::make(1, 0)
  assert_eq(dfs_count(graph, 1, 0), 1)
}

test "has_path: n=1 self" {
  let graph = FixedArray::make(1, 0)
  assert_eq(has_path(graph, 1, 0, 0), true)
}

test "bfs_count: self-loop does not double count" {
  let n = 1
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 0] = 1 // self-loop
  assert_eq(bfs_count(graph, n, 0), 1)
}

test "bfs_distances: self-loop keeps distance 0" {
  let n = 1
  let graph = FixedArray::make(n * n, 0)
  graph[0] = 1 // self-loop
  let dist = bfs_distances(graph, n, 0).unwrap()
  assert_eq(dist[0], 0)
}

test "dfs_count: self-loop does not double count" {
  let n = 2
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 0] = 1 // self-loop on 0
  graph[0 * n + 1] = 1 // 0 -> 1
  graph[1 * n + 1] = 1 // self-loop on 1
  assert_eq(dfs_count(graph, n, 0), 2)
}

test "has_path: self-loop source" {
  // src has a self-loop; src==dst is a trivial path.
  let n = 3
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 0] = 1 // self-loop on 0
  assert_eq(has_path(graph, n, 0, 0), true)
}

test "has_path: self-loop does not block traversal" {
  let n = 3
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 0] = 1 // self-loop on 0
  graph[0 * n + 1] = 1 // 0 -> 1
  graph[1 * n + 2] = 1 // 1 -> 2
  assert_eq(has_path(graph, n, 0, 2), true)
  assert_eq(has_path(graph, n, 0, 1), true)
}
