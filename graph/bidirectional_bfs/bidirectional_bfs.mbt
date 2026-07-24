/// Bidirectional BFS for unweighted shortest paths in directed or undirected
/// graphs.
///
/// Finds the shortest path length (number of hops) between two vertices by
/// running two breadth-first searches simultaneously — one forward from `src`
/// following outgoing edges, and one backward from `dst` following **incoming**
/// edges (i.e. on the transposed graph) — and stopping as soon as the two
/// search frontiers meet.
///
/// The graph is an adjacency list: `graph[i]` is an `Array` of `(neighbor,
/// weight)` pairs. The weight component is **ignored**; every edge is treated
/// as a single hop. For undirected graphs, add each edge in both directions.
///
/// ## Directed graph support
///
/// The forward BFS explores `graph[i]` (outgoing edges from `i`). The backward
/// BFS explores the **transposed** graph (incoming edges to each vertex). This
/// ensures correct results for both directed and undirected graphs. Without
/// transposition, a directed graph could produce false "meetings" at vertices
/// that are reachable from both `src` and `dst` via outgoing edges but do not
/// lie on any `src`-to-`dst` path.
///
/// ## Why it is faster
///
/// A standard BFS from `src` explores `O(b^d)` vertices, where `b` is the
/// branching factor and `d` the source-to-target distance. Bidirectional BFS
/// explores two cones of depth `~d/2`, so it visits roughly `O(b^(d/2))`
/// vertices — a dramatic reduction when `d` is large.
///
/// ## Correctness
///
/// Both searches expand one whole BFS level at a time, always advancing the
/// side with the *smaller* frontier (a standard optimization that never
/// violates BFS ordering). Each vertex's distance is fixed the instant it is
/// discovered, so when a vertex is found by one search that the other has
/// already reached, the path `src -> v -> dst` has length `dist_a[v] +
/// dist_b[v]`. The first level at which any such meeting occurs yields the
/// shortest path: any vertex not yet visited by the opposite search has a
/// strictly greater distance on that side, so it cannot produce a shorter
/// total. Within a single level, several vertices may meet; the minimum over
/// them is returned.
///
/// ## Returns
///
/// `Some(length)` — the shortest hop count — or `None` when no path exists or
/// the input is invalid (`n <= 0`, `src`/`dst` out of range, `graph` too
/// small). `src == dst` returns `Some(0)`.
///
/// ## Complexity
///
/// Time `O(b^(d/2))` in practice (worst case `O(V + E)`), space `O(V + E)`
/// (the transposed graph is built in O(E) time and space).
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

/// Build the transposed graph: `tgraph[i]` contains `(j, w)` for every edge
/// `j -> i` with weight `w` in the original `graph`.
fn build_transpose(
  graph : Array[Array[(Int, Int)]],
  n : Int
) -> Array[Array[(Int, Int)]] {
  let tgraph : Array[Array[(Int, Int)]] = []
  for _i = 0; _i < n; _i = _i + 1 {
    tgraph.push([])
  }
  for u = 0; u < n; u = u + 1 {
    for j = 0; j < graph[u].length(); j = j + 1 {
      let (v, w) = graph[u][j]
      if v >= 0 && v < n {
        tgraph[v].push((u, w))
      }
    }
  }
  tgraph
}

/// Expand one BFS level from the side whose queue is `q` (indexed by `head`),
/// recording distances in `dist_this` and checking the opposite side's
/// `dist_other` for a meeting.
///
/// Returns `(meeting_distance?, new_head)`: the shortest meeting distance found
/// in this level (or `None` if the two searches did not meet), and the updated
/// head index into `q` after consuming this level's vertices.
///
/// `dist` arrays use `-1` for "unvisited"; hop counts are always `>= 0`, so
/// `-1` is an unambiguous sentinel.
fn expand_level(
  adj : Array[Array[(Int, Int)]],
  n : Int,
  q : Array[Int],
  head : Int,
  dist_this : FixedArray[Int],
  dist_other : FixedArray[Int],
) -> (Int?, Int) {
  let level_size = q.length() - head
  let mut pos = head
  let mut best : Int = -1
  for _k = 0; _k < level_size; _k = _k + 1 {
    let u = q[pos]
    pos = pos + 1
    let neighbors = adj[u]
    for j = 0; j < neighbors.length(); j = j + 1 {
      let (v, _) = neighbors[j]
      if v >= 0 && v < n {
        if dist_this[v] == -1 {
          dist_this[v] = dist_this[u] + 1
          q.push(v)
          // Meeting: the opposite search already reached v.
          if dist_other[v] != -1 {
            let cand = dist_this[v] + dist_other[v]
            if best == -1 || cand < best {
              best = cand
            }
          }
        }
      }
    }
  }
  if best == -1 {
    (None, pos)
  } else {
    (Some(best), pos)
  }
}

/// Compute the shortest unweighted path length between `src` and `dst`.
///
/// `graph[i]` is an `Array` of `(neighbor, weight)` pairs; weights are ignored.
/// Returns `Some(hops)` or `None` (no path / invalid input). `src == dst`
/// returns `Some(0)`.
pub fn bidirectional_bfs(
  graph : Array[Array[(Int, Int)]],
  n : Int,
  src : Int,
  dst : Int,
) -> Int? {
  if n <= 0 || graph.length() < n {
    return None
  }
  if src < 0 || src >= n || dst < 0 || dst >= n {
    return None
  }
  if src == dst {
    return Some(0)
  }
  // Build the transposed graph for the backward search. The forward search
  // follows outgoing edges (graph); the backward search follows incoming
  // edges (tgraph). This makes the algorithm correct for both directed and
  // undirected graphs.
  let tgraph = build_transpose(graph, n)
  let dist_a = FixedArray::make(n, -1) // distances from src (forward)
  let dist_b = FixedArray::make(n, -1) // distances from dst (backward)
  dist_a[src] = 0
  dist_b[dst] = 0
  // Index-based queues: `head` advances as nodes are consumed, `push` appends.
  let qa : Array[Int] = [src]
  let qb : Array[Int] = [dst]
  let mut head_a = 0
  let mut head_b = 0
  // Advance level by level, always expanding the smaller frontier.
  while head_a < qa.length() && head_b < qb.length() {
    let size_a = qa.length() - head_a
    let size_b = qb.length() - head_b
    if size_a <= size_b {
      let (result, new_head) = expand_level(graph, n, qa, head_a, dist_a, dist_b)
      head_a = new_head
      match result {
        Some(d) => return Some(d)
        None => ()
      }
    } else {
      // Backward search uses the transposed graph.
      let (result, new_head) = expand_level(tgraph, n, qb, head_b, dist_b, dist_a)
      head_b = new_head
      match result {
        Some(d) => return Some(d)
        None => ()
      }
    }
  }
  None
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "bidirectional_bfs: basic path" {
  // Undirected chain 0 - 1 - 2 - 3 - 4.
  let n = 5
  let graph : Array[Array[(Int, Int)]] = [[], [], [], [], []]
  for i = 0; i < n - 1; i = i + 1 {
    graph[i].push((i + 1, 1))
    graph[i + 1].push((i, 1))
  }
  assert_eq(bidirectional_bfs(graph, n, 0, 4), Some(4))
  assert_eq(bidirectional_bfs(graph, n, 0, 2), Some(2))
  assert_eq(bidirectional_bfs(graph, n, 1, 3), Some(2))
}

test "bidirectional_bfs: no path" {
  // Two disconnected components: {0,1} and {2,3}.
  let n = 4
  let graph : Array[Array[(Int, Int)]] = [[], [], [], []]
  graph[0].push((1, 1))
  graph[1].push((0, 1))
  graph[2].push((3, 1))
  graph[3].push((2, 1))
  assert_true(bidirectional_bfs(graph, n, 0, 3) is None)
  assert_true(bidirectional_bfs(graph, n, 1, 2) is None)
}

test "bidirectional_bfs: src equals dst" {
  let n = 3
  let graph : Array[Array[(Int, Int)]] = [[], [], []]
  graph[0].push((1, 1))
  graph[1].push((0, 1))
  assert_eq(bidirectional_bfs(graph, n, 0, 0), Some(0))
  assert_eq(bidirectional_bfs(graph, n, 2, 2), Some(0))
}

test "bidirectional_bfs: single edge" {
  let n = 2
  let graph : Array[Array[(Int, Int)]] = [[], []]
  graph[0].push((1, 1))
  graph[1].push((0, 1))
  assert_eq(bidirectional_bfs(graph, n, 0, 1), Some(1))
  assert_eq(bidirectional_bfs(graph, n, 1, 0), Some(1))
}

test "bidirectional_bfs: chain" {
  // Undirected chain of 10 nodes.
  let n = 10
  let graph : Array[Array[(Int, Int)]] = []
  for i = 0; i < n; i = i + 1 {
    graph.push([])
  }
  for i = 0; i < n - 1; i = i + 1 {
    graph[i].push((i + 1, 1))
    graph[i + 1].push((i, 1))
  }
  assert_eq(bidirectional_bfs(graph, n, 0, 9), Some(9))
  assert_eq(bidirectional_bfs(graph, n, 0, 5), Some(5))
  assert_eq(bidirectional_bfs(graph, n, 3, 7), Some(4))
}

test "bidirectional_bfs: star graph" {
  // Center 0 connected to leaves 1, 2, 3, 4.
  let n = 5
  let graph : Array[Array[(Int, Int)]] = [[], [], [], [], []]
  for i = 1; i < n; i = i + 1 {
    graph[0].push((i, 1))
    graph[i].push((0, 1))
  }
  // Leaf to leaf must pass through the center: distance 2.
  assert_eq(bidirectional_bfs(graph, n, 1, 3), Some(2))
  assert_eq(bidirectional_bfs(graph, n, 2, 4), Some(2))
  // Center to leaf: distance 1.
  assert_eq(bidirectional_bfs(graph, n, 0, 4), Some(1))
}

test "bidirectional_bfs: disconnected" {
  // 0 - 1 - 2 - 3 chain, plus isolated 4.
  let n = 5
  let graph : Array[Array[(Int, Int)]] = [[], [], [], [], []]
  for i = 0; i < 3; i = i + 1 {
    graph[i].push((i + 1, 1))
    graph[i + 1].push((i, 1))
  }
  assert_eq(bidirectional_bfs(graph, n, 0, 3), Some(3))
  assert_true(bidirectional_bfs(graph, n, 0, 4) is None)
  assert_true(bidirectional_bfs(graph, n, 4, 4) is Some(0))
}

test "bidirectional_bfs: directed graph" {
  // Directed chain 0 -> 1 -> 2 -> 3.
  let n = 4
  let graph : Array[Array[(Int, Int)]] = [[], [], [], []]
  graph[0].push((1, 1))
  graph[1].push((2, 1))
  graph[2].push((3, 1))
  assert_eq(bidirectional_bfs(graph, n, 0, 3), Some(3))
  // Reverse direction: no path.
  assert_true(bidirectional_bfs(graph, n, 3, 0) is None)
}

test "bidirectional_bfs: directed graph no false meeting" {
  // Edges: 0->1, 2->1, 1->3. Query 0->2 must return None because 0 cannot
  // reach 2 in this directed graph. Previously the backward search followed
  // outgoing edges (not incoming), causing a false "meeting" at node 1.
  let n = 4
  let graph : Array[Array[(Int, Int)]] = [[], [], [], []]
  graph[0].push((1, 1))
  graph[2].push((1, 1))
  graph[1].push((3, 1))
  assert_true(bidirectional_bfs(graph, n, 0, 2) is None)
  // 0 -> 1 -> 3 is a valid path of length 2.
  assert_eq(bidirectional_bfs(graph, n, 0, 3), Some(2))
  // 2 -> 1 -> 3 is also valid.
  assert_eq(bidirectional_bfs(graph, n, 2, 3), Some(2))
}

test "bidirectional_bfs: complete graph K4" {
  let n = 4
  let graph : Array[Array[(Int, Int)]] = []
  for i = 0; i < n; i = i + 1 {
    graph.push([])
  }
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      if i != j {
        graph[i].push((j, 1))
      }
    }
  }
  // Every distinct pair is one hop apart.
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      if i == j {
        assert_eq(bidirectional_bfs(graph, n, i, j), Some(0))
      } else {
        assert_eq(bidirectional_bfs(graph, n, i, j), Some(1))
      }
    }
  }
}

test "bidirectional_bfs: weights are ignored" {
  // Same topology as the basic path but with arbitrary weights.
  let n = 5
  let graph : Array[Array[(Int, Int)]] = [[], [], [], [], []]
  graph[0].push((1, 100))
  graph[1].push((0, 100))
  graph[1].push((2, 1))
  graph[2].push((1, 1))
  graph[2].push((3, 42))
  graph[3].push((2, 42))
  graph[3].push((4, 7))
  graph[4].push((3, 7))
  // Hop count is 4 regardless of weights.
  assert_eq(bidirectional_bfs(graph, n, 0, 4), Some(4))
}

test "bidirectional_bfs: meeting in the middle" {
  // Two paths from 0 to 5 of different hop lengths; BFS picks the shorter.
  //   Short: 0 - 3 - 5           (2 hops)
  //   Long:  0 - 1 - 2 - 4 - 5   (4 hops)
  let n = 6
  let graph : Array[Array[(Int, Int)]] = [[], [], [], [], [], []]
  let undirected = fn(u : Int, v : Int) -> Unit {
    graph[u].push((v, 1))
    graph[v].push((u, 1))
  }
  undirected(0, 3)
  undirected(3, 5)
  undirected(0, 1)
  undirected(1, 2)
  undirected(2, 4)
  undirected(4, 5)
  assert_eq(bidirectional_bfs(graph, n, 0, 5), Some(2))
}

test "bidirectional_bfs: grid 5x5 corner to corner" {
  // 5x5 grid (undirected), source (0,0)=0, target (4,4)=24.
  let size = 5
  let n = size * size
  let graph : Array[Array[(Int, Int)]] = []
  for i = 0; i < n; i = i + 1 {
    graph.push([])
  }
  for r = 0; r < size; r = r + 1 {
    for c = 0; c < size; c = c + 1 {
      let id = r * size + c
      if c + 1 < size {
        graph[id].push((id + 1, 1))
        graph[id + 1].push((id, 1))
      }
      if r + 1 < size {
        graph[id].push((id + size, 1))
        graph[id + size].push((id, 1))
      }
    }
  }
  // Manhattan distance from (0,0) to (4,4) = 8.
  assert_eq(bidirectional_bfs(graph, n, 0, 24), Some(8))
}

test "bidirectional_bfs: invalid input" {
  let graph : Array[Array[(Int, Int)]] = [[]]
  assert_true(bidirectional_bfs(graph, 0, 0, 0) is None) // n = 0
  assert_true(bidirectional_bfs(graph, 1, -1, 0) is None) // src < 0
  assert_true(bidirectional_bfs(graph, 1, 0, 1) is None) // dst >= n
  assert_true(bidirectional_bfs(graph, 1, 1, 0) is None) // src >= n
  // graph too small for n
  let small : Array[Array[(Int, Int)]] = [[], []]
  assert_true(bidirectional_bfs(small, 5, 0, 1) is None)
}
