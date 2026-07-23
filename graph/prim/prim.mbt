/// Prim's Minimum Spanning Tree algorithm.
///
/// Builds a minimum-weight spanning tree of an undirected graph starting from
/// vertex 0. The graph is a flat `n * n` adjacency matrix where
/// `graph[i * n + j]` is the weight of the edge `i -- j`, or `0` when no edge
/// exists.
///
/// Uses the classic O(n^2) implementation (no priority queue), which is ideal
/// for dense adjacency-matrix graphs.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

/// Sentinel value meaning "no connecting edge known yet".
let inf : Int = 1000000000

/// Compute a minimum spanning tree (or forest) rooted at vertex 0.
///
/// # Parameters
/// - `graph`: the `n * n` adjacency matrix. The input is never modified.
/// - `n`: the number of vertices, indexed `0 .. n - 1`.
///
/// # Returns
/// `(parent, total_weight)` where `parent[i]` is the parent of vertex `i` in
/// the MST (`parent[0] = -1` as the root). Vertices unreachable from vertex 0
/// keep `parent[i] = -1`. `total_weight` is the sum of all selected edges.
/// Returns an empty array and weight `0` when `n <= 0` or the matrix is too
/// small.
pub fn prim_mst(graph : FixedArray[Int], n : Int) -> (FixedArray[Int], Int) {
  if n <= 0 || graph.length() < n * n {
    return (FixedArray::make(0, 0), 0)
  }
  let key = FixedArray::make(n, inf)
  let parent = FixedArray::make(n, -1)
  let in_mst = FixedArray::make(n, false)
  key[0] = 0
  let mut total = 0
  for step = 0; step < n; step = step + 1 {
    // Pick the unvisited vertex with the smallest connecting edge.
    let mut u = -1
    let mut best = inf
    for i = 0; i < n; i = i + 1 {
      if !in_mst[i] && key[i] < best {
        best = key[i]
        u = i
      }
    }
    // No reachable vertex remains: the graph is disconnected.
    if u == -1 {
      break
    }
    in_mst[u] = true
    if u != 0 {
      total = total + key[u]
    }
    // Relax every neighbour of u.
    for v = 0; v < n; v = v + 1 {
      let w = graph[u * n + v]
      if w != 0 && !in_mst[v] && w < key[v] {
        key[v] = w
        parent[v] = u
      }
    }
  }
  (parent, total)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "prim: basic triangle" {
  // 0--1 (1), 1--2 (2), 0--2 (3). MST = {0-1, 1-2}, weight 3.
  let n = 3
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 1
  graph[1 * n + 0] = 1
  graph[1 * n + 2] = 2
  graph[2 * n + 1] = 2
  graph[0 * n + 2] = 3
  graph[2 * n + 0] = 3
  let (parent, w) = prim_mst(graph, n)
  assert_eq(w, 3)
  assert_eq(parent[0], -1)
  assert_eq(parent[1], 0)
  assert_eq(parent[2], 1)
}

test "prim: single node" {
  let graph = FixedArray::make(1, 0)
  let (parent, w) = prim_mst(graph, 1)
  assert_eq(parent.length(), 1)
  assert_eq(parent[0], -1)
  assert_eq(w, 0)
}

test "prim: disconnected graph" {
  // Two components: {0,1} and {2,3}. Only {0,1} is reachable from 0.
  let n = 4
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 5
  graph[1 * n + 0] = 5
  graph[2 * n + 3] = 2
  graph[3 * n + 2] = 2
  let (parent, w) = prim_mst(graph, n)
  assert_eq(w, 5)
  assert_eq(parent[0], -1)
  assert_eq(parent[1], 0)
  // Vertices 2 and 3 are unreachable from 0.
  assert_eq(parent[2], -1)
  assert_eq(parent[3], -1)
}

test "prim: complete graph K4" {
  // K4: 6 edges. Three cheapest form the MST (1 + 2 + 3 = 6).
  let n = 4
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 1
  graph[1 * n + 0] = 1
  graph[0 * n + 2] = 2
  graph[2 * n + 0] = 2
  graph[0 * n + 3] = 3
  graph[3 * n + 0] = 3
  graph[1 * n + 2] = 4
  graph[2 * n + 1] = 4
  graph[1 * n + 3] = 5
  graph[3 * n + 1] = 5
  graph[2 * n + 3] = 6
  graph[3 * n + 2] = 6
  let (parent, w) = prim_mst(graph, n)
  assert_eq(w, 6)
  assert_eq(parent[0], -1)
  // Every non-root vertex must connect directly to 0 (cheapest edges).
  assert_eq(parent[1], 0)
  assert_eq(parent[2], 0)
  assert_eq(parent[3], 0)
}

test "prim: star topology" {
  // Center 0 linked to 1..4 with increasing weights.
  let n = 5
  let graph = FixedArray::make(n * n, 0)
  for i = 1; i < n; i = i + 1 {
    graph[0 * n + i] = i
    graph[i * n + 0] = i
  }
  let (parent, w) = prim_mst(graph, n)
  assert_eq(w, 10) // 1 + 2 + 3 + 4
  assert_eq(parent[0], -1)
  for i = 1; i < n; i = i + 1 {
    assert_eq(parent[i], 0)
  }
}

test "prim: line topology with heavy shortcut" {
  // Path 0-1-2-3-4 (weights 1..4) plus a heavy chord 0-4 (100).
  let n = 5
  let graph = FixedArray::make(n * n, 0)
  for i = 0; i < n - 1; i = i + 1 {
    graph[i * n + (i + 1)] = i + 1
    graph[(i + 1) * n + i] = i + 1
  }
  graph[0 * n + 4] = 100
  graph[4 * n + 0] = 100
  let (parent, w) = prim_mst(graph, n)
  assert_eq(w, 10) // 1 + 2 + 3 + 4
  assert_eq(parent[0], -1)
  assert_eq(parent[1], 0)
  assert_eq(parent[2], 1)
  assert_eq(parent[3], 2)
  assert_eq(parent[4], 3)
}

test "prim: equal weights (unit square)" {
  // Square with unit weights. MST has 3 edges, weight 3.
  let n = 4
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 1
  graph[1 * n + 0] = 1
  graph[1 * n + 2] = 1
  graph[2 * n + 1] = 1
  graph[2 * n + 3] = 1
  graph[3 * n + 2] = 1
  graph[3 * n + 0] = 1
  graph[0 * n + 3] = 1
  let (parent, w) = prim_mst(graph, n)
  assert_eq(w, 3)
  assert_eq(parent[0], -1)
}

test "prim: invalid n returns empty" {
  let graph = FixedArray::make(9, 0)
  let (parent, w) = prim_mst(graph, 0)
  assert_eq(parent.length(), 0)
  assert_eq(w, 0)
  let (parent2, w2) = prim_mst(graph, -3)
  assert_eq(parent2.length(), 0)
  assert_eq(w2, 0)
}

test "prim: graph too small returns empty" {
  // n=3 needs 9 entries; provide only 4.
  let graph = FixedArray::make(4, 0)
  let (parent, w) = prim_mst(graph, 3)
  assert_eq(parent.length(), 0)
  assert_eq(w, 0)
}

test "prim: large graph (10 nodes, line + chords)" {
  let n = 10
  let graph = FixedArray::make(n * n, 0)
  // 9 light line edges (weights 1..9) span all nodes.
  for i = 0; i < n - 1; i = i + 1 {
    graph[i * n + (i + 1)] = i + 1
    graph[(i + 1) * n + i] = i + 1
  }
  // 15 heavy chords (weight 100) that must be rejected.
  let chords = [
    (0, 2), (0, 3), (1, 3), (1, 4), (2, 4),
    (2, 5), (3, 5), (3, 6), (4, 6), (4, 7),
    (5, 7), (5, 8), (6, 8), (6, 9), (7, 9),
  ]
  for k = 0; k < chords.length(); k = k + 1 {
    let (a, b) = chords[k]
    graph[a * n + b] = 100
    graph[b * n + a] = 100
  }
  let (parent, w) = prim_mst(graph, n)
  assert_eq(w, 45) // 1 + 2 + ... + 9
  assert_eq(parent[0], -1)
  // Each vertex i >= 1 connects to i - 1 (cheapest line edge).
  for i = 1; i < n; i = i + 1 {
    assert_eq(parent[i], i - 1)
  }
}

test "prim: MST edges form a valid tree" {
  // A graph rich in cycles; every non-root vertex must have a parent in [0,n).
  let n = 5
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 2
  graph[1 * n + 0] = 2
  graph[1 * n + 2] = 3
  graph[2 * n + 1] = 3
  graph[2 * n + 3] = 1
  graph[3 * n + 2] = 1
  graph[3 * n + 4] = 4
  graph[4 * n + 3] = 4
  graph[0 * n + 4] = 9
  graph[4 * n + 0] = 9
  graph[1 * n + 4] = 7
  graph[4 * n + 1] = 7
  graph[0 * n + 3] = 8
  graph[3 * n + 0] = 8
  let (parent, _) = prim_mst(graph, n)
  assert_eq(parent[0], -1)
  for i = 1; i < n; i = i + 1 {
    let p = parent[i]
    assert_true(p >= 0 && p < n)
    assert_true(p != i)
  }
}
