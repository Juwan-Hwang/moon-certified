/// Lowest Common Ancestor (LCA) via Binary Lifting.
///
/// Preprocesses a rooted tree in O(n log n) time and space, then answers
/// LCA queries in O(log n) each. The binary lifting table stores the
/// 2^k-th ancestor of every node, enabling efficient depth equalisation and
/// ancestor jumps.
///
/// Supports both single LCA queries and batch distance queries.
///
/// Complexity:
/// - `build(n, root, adj)` — O(n log n)
/// - `lca(u, v)`           — O(log n)
/// - `distance(u, v)`      — O(log n)
///
/// Limitations:
/// - The tree is assumed to be a connected, undirected tree with `n` nodes
///   numbered `0 .. n-1`.
/// - `root` must be a valid node index in `[0, n)`.
/// - `adj` must be the symmetric adjacency list (each edge appears in both
///   directions).
/// - After building, the adjacency list is no longer needed.

/// Binary Lifting LCA structure.
///
/// `up[k][v]` is the 2^k-th ancestor of node `v`, or `-1` if it doesn't exist.
/// `depth[v]` is the distance (in edges) from `v` to the root.
pub struct LCA {
  up : Array[FixedArray[Int]] // up[k][v] = 2^k-th ancestor of v, -1 if none
  depth : FixedArray[Int]
  log_n : Int
  n : Int
}

/// Build the LCA structure for a tree with `n` nodes rooted at `root`.
///
/// `adj` is the adjacency list where `adj[v]` is the list of neighbours of `v`.
/// The tree must be connected and undirected (edges appear in both directions).
pub fn build(
  n : Int,
  root : Int,
  adj : Array[Array[Int]],
) -> LCA {
  if n <= 0 {
    return { up: [], depth: FixedArray::make(0, 0), log_n: 0, n: 0 }
  }
  let log_n = if n == 1 { 1 } else { ilog2(n) + 1 }
  // Initialize depth
  let depth = FixedArray::make(n, -1)
  // Initialize up table
  let up = []
  for k = 0; k < log_n; k = k + 1 {
    up.push(FixedArray::make(n, -1))
  }
  // BFS to compute depth and up[0] (direct parent)
  depth[root] = 0
  up[0][root] = root // root's parent is itself (sentinel)
  let queue = FixedArray::make(n, 0)
  let mut head = 0
  let mut tail = 0
  queue[tail] = root
  tail = tail + 1
  while head < tail {
    let v = queue[head]
    head = head + 1
    let neighbors = adj[v]
    for i = 0; i < neighbors.length(); i = i + 1 {
      let u = neighbors[i]
      if depth[u] == -1 {
        depth[u] = depth[v] + 1
        up[0][u] = v
        queue[tail] = u
        tail = tail + 1
      }
    }
  }
  // Build the binary lifting table
  for k = 1; k < log_n; k = k + 1 {
    for v = 0; v < n; v = v + 1 {
      let mid = up[k - 1][v]
      if mid != -1 {
        up[k][v] = up[k - 1][mid]
      }
    }
  }
  { up, depth, log_n, n }
}

/// Integer log2 (floor). Returns the position of the highest set bit.
fn ilog2(n : Int) -> Int {
  let mut r = 0
  let mut m = n
  while m > 1 {
    r = r + 1
    m = m >> 1
  }
  r
}

/// Find the 2^k-th ancestor of node `v`. Returns `-1` if no such ancestor.
/// k must be ≥ 0.
pub fn ancestor(lca : LCA, v : Int, k : Int) -> Int {
  if v < 0 || v >= lca.n || k < 0 || k >= lca.log_n {
    return -1
  }
  lca.up[k][v]
}

/// Return the depth of node `v` (distance from root in edges). O(1).
pub fn depth_of(lca : LCA, v : Int) -> Int {
  if v < 0 || v >= lca.n {
    return -1
  }
  lca.depth[v]
}

/// Find the lowest common ancestor of nodes `u` and `v`.
///
/// Returns `-1` if either node is invalid. If `u == v`, returns `u`.
/// Runs in O(log n).
pub fn lca(l : LCA, u : Int, v : Int) -> Int {
  let n = l.n
  if u < 0 || u >= n || v < 0 || v >= n {
    return -1
  }
  let mut a = u
  let mut b = v
  // Equalise depths: bring the deeper node up
  if l.depth[a] < l.depth[b] {
    let tmp = a
    a = b
    b = tmp
  }
  let diff = l.depth[a] - l.depth[b]
  // Lift a by diff using binary representation
  let mut k = 0
  let mut d = diff
  while d > 0 {
    if (d & 1) == 1 {
      a = l.up[k][a]
    }
    d = d >> 1
    k = k + 1
  }
  // Now a and b are at the same depth
  if a == b {
    return a
  }
  // Lift both together from highest power down
  for k = l.log_n - 1; k >= 0; k = k - 1 {
    if l.up[k][a] != l.up[k][b] {
      a = l.up[k][a]
      b = l.up[k][b]
    }
  }
  // Now a and b are children of the LCA
  l.up[0][a]
}

/// Return the distance (number of edges) between nodes `u` and `v`.
/// Returns `-1` if either node is invalid.
/// Runs in O(log n) (one LCA query + two depth lookups).
pub fn distance(l : LCA, u : Int, v : Int) -> Int {
  let n = l.n
  if u < 0 || u >= n || v < 0 || v >= n {
    return -1
  }
  let w = lca(l, u, v)
  if w == -1 {
    return -1
  }
  l.depth[u] + l.depth[v] - 2 * l.depth[w]
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

/// Build adjacency list from edge list.
fn make_adj(n : Int, edges : Array[(Int, Int)]) -> Array[Array[Int]] {
  let adj = []
  for i = 0; i < n; i = i + 1 {
    adj.push([])
  }
  for i = 0; i < edges.length(); i = i + 1 {
    let (u, v) = edges[i]
    adj[u].push(v)
    adj[v].push(u)
  }
  adj
}

test "lca: simple tree" {
  //       0
  //      / \
  //     1   2
  //    / \
  //   3   4
  let adj = make_adj(5, [(0, 1), (0, 2), (1, 3), (1, 4)])
  let l = build(5, 0, adj)
  assert_eq(lca(l, 3, 4), 1)
  assert_eq(lca(l, 3, 2), 0)
  assert_eq(lca(l, 0, 0), 0)
  assert_eq(lca(l, 1, 2), 0)
  assert_eq(lca(l, 3, 3), 3)
  assert_eq(lca(l, 4, 2), 0)
}

test "lca: depth and distance" {
  let adj = make_adj(5, [(0, 1), (0, 2), (1, 3), (1, 4)])
  let l = build(5, 0, adj)
  assert_eq(depth_of(l, 0), 0)
  assert_eq(depth_of(l, 1), 1)
  assert_eq(depth_of(l, 2), 1)
  assert_eq(depth_of(l, 3), 2)
  assert_eq(depth_of(l, 4), 2)
  assert_eq(distance(l, 3, 4), 2) // 3 -> 1 -> 4
  assert_eq(distance(l, 3, 2), 3) // 3 -> 1 -> 0 -> 2
  assert_eq(distance(l, 0, 4), 2) // 0 -> 1 -> 4
  assert_eq(distance(l, 3, 3), 0)
}

test "lca: single node" {
  let adj : Array[Array[Int]] = [[]]
  let l = build(1, 0, adj)
  assert_eq(lca(l, 0, 0), 0)
  assert_eq(distance(l, 0, 0), 0)
  assert_eq(depth_of(l, 0), 0)
}

test "lca: chain (degenerate tree)" {
  // 0 - 1 - 2 - 3 - 4 - 5
  let adj = make_adj(6, [(0, 1), (1, 2), (2, 3), (3, 4), (4, 5)])
  let l = build(6, 0, adj)
  assert_eq(lca(l, 0, 5), 0)
  assert_eq(lca(l, 2, 4), 2)
  assert_eq(lca(l, 3, 5), 3)
  assert_eq(distance(l, 0, 5), 5)
  assert_eq(distance(l, 2, 4), 2)
}

test "lca: star tree" {
  //   0 is center, 1..5 are leaves
  let adj = make_adj(6, [(0, 1), (0, 2), (0, 3), (0, 4), (0, 5)])
  let l = build(6, 0, adj)
  for i = 1; i < 6; i = i + 1 {
    assert_eq(lca(l, i, 0), 0)
    for j = i + 1; j < 6; j = j + 1 {
      assert_eq(lca(l, i, j), 0)
      assert_eq(distance(l, i, j), 2)
    }
  }
}

test "lca: non-root root" {
  //       2
  //      / \
  //     0   3
  //    / \
  //   1   4
  let adj = make_adj(5, [(2, 0), (2, 3), (0, 1), (0, 4)])
  let l = build(5, 2, adj)
  assert_eq(lca(l, 1, 4), 0)
  assert_eq(lca(l, 1, 3), 2)
  assert_eq(lca(l, 0, 3), 2)
  assert_eq(depth_of(l, 2), 0)
  assert_eq(depth_of(l, 1), 2)
  assert_eq(distance(l, 1, 3), 3) // 1 -> 0 -> 2 -> 3
}

test "lca: ancestor queries" {
  let adj = make_adj(5, [(0, 1), (0, 2), (1, 3), (1, 4)])
  let l = build(5, 0, adj)
  assert_eq(ancestor(l, 3, 0), 1) // parent of 3
  assert_eq(ancestor(l, 3, 1), 0) // grandparent of 3
  assert_eq(ancestor(l, 4, 1), 0) // grandparent of 4
  assert_eq(ancestor(l, 0, 0), 0) // root's parent is itself
  assert_eq(ancestor(l, 2, 5), -1) // out of range k
}

test "lca: invalid nodes" {
  let adj = make_adj(5, [(0, 1), (0, 2), (1, 3), (1, 4)])
  let l = build(5, 0, adj)
  assert_eq(lca(l, -1, 0), -1)
  assert_eq(lca(l, 0, 5), -1)
  assert_eq(depth_of(l, -1), -1)
  assert_eq(distance(l, 0, -1), -1)
}

test "lca: larger tree" {
  //         0
  //       /   \
  //      1     2
  //     / \   / \
  //    3   4 5   6
  //   / \
  //  7   8
  let adj = make_adj(9, [
    (0, 1), (0, 2), (1, 3), (1, 4), (2, 5), (2, 6), (3, 7), (3, 8),
  ])
  let l = build(9, 0, adj)
  assert_eq(lca(l, 7, 8), 3)
  assert_eq(lca(l, 7, 4), 1)
  assert_eq(lca(l, 5, 6), 2)
  assert_eq(lca(l, 7, 6), 0)
  assert_eq(lca(l, 8, 5), 0)
  assert_eq(distance(l, 7, 6), 5) // 7->3->1->0->2->6
  assert_eq(distance(l, 7, 8), 2) // 7->3->8
  assert_eq(distance(l, 4, 5), 4) // 4->1->0->2->5
}

test "lca: balanced binary tree" {
  // Complete binary tree of depth 3 (15 nodes)
  // Node i has children 2i+1 and 2i+2
  let n = 15
  let edges = []
  for i = 0; i < 7; i = i + 1 {
    edges.push((i, 2 * i + 1))
    edges.push((i, 2 * i + 2))
  }
  let adj = make_adj(n, edges)
  let l = build(n, 0, adj)
  // LCA of two leaves under same parent
  assert_eq(lca(l, 7, 8), 3) // children of 3
  assert_eq(lca(l, 9, 10), 4) // children of 4
  // LCA of leaves from different subtrees
  assert_eq(lca(l, 7, 14), 0)
  assert_eq(lca(l, 11, 14), 2)
  // Distance checks
  assert_eq(distance(l, 7, 8), 2)
  assert_eq(distance(l, 7, 14), 6)
}

test "lca: deep tree stress" {
  // Build a tree: root 0, node i is child of i-1 (chain of 100)
  let n = 100
  let edges = []
  for i = 0; i < n - 1; i = i + 1 {
    edges.push((i, i + 1))
  }
  let adj = make_adj(n, edges)
  let l = build(n, 0, adj)
  // LCA of any two nodes in a chain is the shallower one
  assert_eq(lca(l, 10, 50), 10)
  assert_eq(lca(l, 50, 10), 10)
  assert_eq(lca(l, 0, 99), 0)
  assert_eq(lca(l, 99, 99), 99)
  assert_eq(distance(l, 0, 99), 99)
  assert_eq(distance(l, 10, 50), 40)
  // Depth check
  assert_eq(depth_of(l, 50), 50)
}
