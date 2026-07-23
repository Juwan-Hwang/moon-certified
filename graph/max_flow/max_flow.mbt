/// Maximum flow using the Edmonds-Karp algorithm (BFS-based Ford-Fulkerson).
///
/// Uses an adjacency matrix representation: `graph[i * n + j]` is the
/// capacity of the directed edge from `i` to `j`. A capacity of 0 means
/// no edge exists. The graph is treated as directed; for undirected flow
/// networks, add edges in both directions.
///
/// Edmonds-Karp is Ford-Fulkerson with BFS to find augmenting paths.
/// This guarantees O(VE²) time complexity regardless of capacity magnitudes,
/// avoiding the potential pseudo-polynomial blowup of naive Ford-Fulkerson
/// with DFS.
///
/// Returns the maximum flow from `src` to `sink`. For invalid inputs
/// (n <= 0, out-of-bounds vertices, src == sink), returns 0.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.
///
/// Time complexity: O(VE²)

/// Sentinel value representing "infinite capacity" for the bottleneck search.
/// Using `Int::max_value` means the bottleneck is bounded by the largest
/// single edge capacity. Total flow accumulation in `total_flow` may
/// overflow if the sum of all augmenting path flows exceeds `Int::max_value`.
/// For typical graphs this is not a concern; for extreme cases, use Int64.
let int_max : Int = 2147483647

/// BFS to find an augmenting path from `src` to `sink` in the residual graph.
///
/// `residual` is an `n × n` matrix of residual capacities.
/// `parent` is filled with the predecessor of each vertex on the path
/// (-1 for unreached vertices). Returns `true` if `sink` is reachable.
fn bfs_augmenting_path(
  residual : FixedArray[Int],
  n : Int,
  src : Int,
  sink : Int,
  parent : FixedArray[Int],
) -> Bool {
  let visited = FixedArray::make(n, false)
  // Simple index-based BFS queue (avoids Array::shift overhead).
  let queue = FixedArray::make(n, 0)
  let mut head = 0
  let mut tail = 0
  queue[tail] = src
  tail = tail + 1
  visited[src] = true
  parent[src] = -1
  while head < tail {
    let u = queue[head]
    head = head + 1
    for v = 0; v < n; v = v + 1 {
      if !visited[v] && residual[u * n + v] > 0 {
        visited[v] = true
        parent[v] = u
        if v == sink {
          return true
        }
        queue[tail] = v
        tail = tail + 1
      }
    }
  }
  false
}

/// Compute the maximum flow from `src` to `sink` in a flow network.
///
/// `graph` is an `n × n` adjacency matrix where `graph[i * n + j]` is the
/// capacity of the edge `i → j`. Capacity 0 means no edge.
///
/// Returns the maximum flow value. Returns 0 for invalid inputs.
///
/// **Overflow note**: `total_flow` is accumulated as 32-bit `Int`. If the
/// sum of all augmenting path flows exceeds `Int::max_value` (2³¹−1),
/// the result will be incorrect due to integer overflow. For networks
/// with extremely large total flow, consider using 64-bit arithmetic.
pub fn max_flow(
  graph : FixedArray[Int],
  n : Int,
  src : Int,
  sink : Int,
) -> Int {
  if n <= 0 || src < 0 || src >= n || sink < 0 || sink >= n || src == sink {
    return 0
  }
  if graph.length() < n * n {
    return 0
  }
  // Copy capacities into the residual graph (original capacities are
  // consumed during augmentation; we must not mutate the caller's array).
  let residual = FixedArray::make(n * n, 0)
  for i = 0; i < n * n; i = i + 1 {
    residual[i] = graph[i]
  }
  let parent = FixedArray::make(n, -1)
  let mut total_flow = 0
  // Repeatedly find the shortest augmenting path (BFS) and push flow.
  while bfs_augmenting_path(residual, n, src, sink, parent) {
    // Find the bottleneck (minimum residual capacity) along the path.
    let mut path_flow = int_max
    let mut v = sink
    while v != src {
      let u = parent[v]
      let cap = residual[u * n + v]
      if cap < path_flow {
        path_flow = cap
      }
      v = u
    }
    // Update residual capacities along the path:
    //   - Forward edge: decrease by path_flow (capacity consumed)
    //   - Reverse edge: increase by path_flow (flow can be "undone")
    v = sink
    while v != src {
      let u = parent[v]
      residual[u * n + v] = residual[u * n + v] - path_flow
      residual[v * n + u] = residual[v * n + u] + path_flow
      v = u
    }
    total_flow = total_flow + path_flow
  }
  total_flow
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "max_flow: simple chain" {
  // 0 -> 1 -> 2 -> 3, each with capacity 10
  let n = 4
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 10
  graph[1 * n + 2] = 10
  graph[2 * n + 3] = 10
  assert_eq(max_flow(graph, n, 0, 3), 10)
}

test "max_flow: two parallel paths" {
  // 0 -> 1 (10), 0 -> 2 (5), 1 -> 3 (5), 2 -> 3 (10)
  // Max flow = 5 + 5 = 10
  let n = 4
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 10
  graph[0 * n + 2] = 5
  graph[1 * n + 3] = 5
  graph[2 * n + 3] = 10
  assert_eq(max_flow(graph, n, 0, 3), 10)
}

test "max_flow: bottleneck" {
  // 0 -> 1 (20), 1 -> 2 (5), 2 -> 3 (20)
  // Bottleneck is 1->2 with capacity 5
  let n = 4
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 20
  graph[1 * n + 2] = 5
  graph[2 * n + 3] = 20
  assert_eq(max_flow(graph, n, 0, 3), 5)
}

test "max_flow: no path" {
  // 0 and 3 are disconnected
  let n = 4
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 10
  graph[2 * n + 3] = 10
  assert_eq(max_flow(graph, n, 0, 3), 0)
}

test "max_flow: single edge" {
  let n = 2
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 7
  assert_eq(max_flow(graph, n, 0, 1), 7)
}

test "max_flow: classic CLRS example" {
  // CLRS Figure 26.1: s=0, t=5
  // Edges: s->1(16), s->2(13), 1->3(12), 2->1(4), 2->4(14),
  //        3->2(9), 3->t(20), 4->3(7), 4->t(4)
  let n = 6
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 16
  graph[0 * n + 2] = 13
  graph[1 * n + 3] = 12
  graph[2 * n + 1] = 4
  graph[2 * n + 4] = 14
  graph[3 * n + 2] = 9
  graph[3 * n + 5] = 20
  graph[4 * n + 3] = 7
  graph[4 * n + 5] = 4
  assert_eq(max_flow(graph, n, 0, 5), 23)
}

test "max_flow: undirected graph (bidirectional edges)" {
  // 0 <-> 1 <-> 2, each direction capacity 10
  let n = 3
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 10
  graph[1 * n + 0] = 10
  graph[1 * n + 2] = 10
  graph[2 * n + 1] = 10
  assert_eq(max_flow(graph, n, 0, 2), 10)
}

test "max_flow: self-loop ignored" {
  let n = 3
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 0] = 100 // self-loop, should be ignored
  graph[0 * n + 1] = 10
  graph[1 * n + 2] = 10
  assert_eq(max_flow(graph, n, 0, 2), 10)
}

test "max_flow: adding edge increases flow" {
  // 0 -> 1 (10), 1 -> 3 (5), 0 -> 2 (5), 2 -> 3 (10)
  // Without cross edge: max flow = 10 (5 via 0->1->3, 5 via 0->2->3)
  let n = 4
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 10
  graph[1 * n + 3] = 5
  graph[0 * n + 2] = 5
  graph[2 * n + 3] = 10
  assert_eq(max_flow(graph, n, 0, 3), 10)
  // Add cross edge 1 -> 2 (5): now 0->1->2->3 carries additional 5
  // Total: 0->1->3 (5) + 0->1->2->3 (5) + 0->2->3 (5) = 15
  graph[1 * n + 2] = 5
  assert_eq(max_flow(graph, n, 0, 3), 15)
}

test "max_flow: invalid inputs" {
  let n = 3
  let graph = FixedArray::make(n * n, 0)
  assert_eq(max_flow(graph, 0, 0, 2), 0) // n = 0
  assert_eq(max_flow(graph, n, -1, 2), 0) // src < 0
  assert_eq(max_flow(graph, n, 3, 2), 0) // src >= n
  assert_eq(max_flow(graph, n, 0, -1), 0) // sink < 0
  assert_eq(max_flow(graph, n, 0, 3), 0) // sink >= n
  assert_eq(max_flow(graph, n, 1, 1), 0) // src == sink
}

test "max_flow: large chain 100 nodes" {
  let n = 100
  let graph = FixedArray::make(n * n, 0)
  for i = 0; i < n - 1; i = i + 1 {
    graph[i * n + (i + 1)] = 10
  }
  assert_eq(max_flow(graph, n, 0, n - 1), 10)
}

test "max_flow: capacity not mutated" {
  let n = 3
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 5
  graph[1 * n + 2] = 5
  let _ = max_flow(graph, n, 0, 2)
  // Original capacities should be unchanged
  assert_eq(graph[0 * n + 1], 5)
  assert_eq(graph[1 * n + 2], 5)
  assert_eq(graph[1 * n + 0], 0) // reverse edge was 0
}
