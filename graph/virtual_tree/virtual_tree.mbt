/// Virtual Tree (虚树) construction via LCA + binary lifting.
///
/// Given a rooted tree `T` and a subset `S` of its vertices, the **virtual
/// tree** of `S` is the smallest rooted tree on a vertex set `S' ⊇ S` such
/// that for every pair `u, v ∈ S`, the ancestor-descendant relationship
/// between `u` and `v` in the virtual tree matches that in `T`. Concretely,
/// each edge of the virtual tree corresponds to a path in `T` along which no
/// other vertex of `S'` lies.
///
/// The vertex set `S'` is the **LCA-closure** of `S`: it is `S` together
/// with `LCA(S[i], S[i+1])` for every pair of vertices that are consecutive
/// in DFS-entry order. A classical result shows that this set is closed under
/// `LCA` and has size at most `2|S| - 1`, so the virtual tree has at most
/// `2|S| - 1` vertices and `2|S| - 2` edges.
///
/// Virtual trees are the standard tool for running tree DP on a *small*
/// subset of vertices of a *large* tree: after `O(n log n)` preprocessing
/// for LCA, each query costs only `O(|S| log |S|)` instead of `O(n)`.
///
/// ## Algorithm
///
/// 1. **Preprocessing** ([`build`]): an iterative DFS computes, for every
///    vertex, its DFS entry/exit times (`tin`/`tout`), its `depth`, and its
///    parent. A binary-lifting table `up[k][v]` (the `2^k`-th ancestor of
///    `v`) is then built so that LCA queries run in `O(log n)`. The root is
///    its own sentinel ancestor (`up[k][root] = root`), matching the
///    convention of the sibling `graph/lca` package.
///
/// 2. **Virtual-tree query** ([`build_virtual`]):
///    - Sort `S` by `tin`.
///    - Form `S' = S ∪ { LCA(S[i], S[i+1]) }`, sort by `tin`, and remove
///      duplicates.
///    - Build the tree with a stack that maintains the right-most path of the
///      virtual tree. For each new vertex `v`, let `l = LCA(v, stack.top())`;
///      pop completed branches, insert `l` if it lies strictly between the
///      top two stack vertices, then push `v`. Remaining stack edges are
///      emitted at the end.
///
/// The DFS is **iterative** (an explicit stack with a per-vertex neighbour
/// cursor) to avoid stack overflow on deep trees.
///
/// ## Complexity
///
/// - `build`           — `O(n log n)` time and space.
/// - `build_virtual`   — `O(|S| log |S|)` (dominated by the sort; the LCA
///   queries are `O(|S| log n)` and the stack pass is `O(|S|)`).
/// - `lca`             — `O(log n)`.
/// - `is_ancestor`     — `O(1)`.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

///|
/// Preprocessed tree capable of answering virtual-tree queries.
///
/// Built once per tree with [`build`]; reuse it for every
/// [`build_virtual`] query on subsets of the same tree.
pub struct VirtualTreeBuilder {
  priv up : Array[FixedArray[Int]] // up[k][v] = 2^k-th ancestor of v (root is its own sentinel)
  priv depth : FixedArray[Int] // depth[v] = distance (in edges) from the root
  priv tin : FixedArray[Int] // tin[v] = DFS entry time of v
  priv tout : FixedArray[Int] // tout[v] = DFS exit time of v
  priv log_n : Int // number of levels in the binary-lifting table
  n : Int // number of vertices in the original tree
  root : Int // the root vertex
}

///|
/// A virtual tree over a subset of vertices.
///
/// - `vertices[i]` is the `i`-th virtual vertex (an original vertex id),
///   sorted by DFS entry time. `vertices[0]` is the root of the virtual tree
///   (the LCA of all selected vertices) and is also stored in `root`.
/// - `adj[i]` is the **undirected** adjacency list of `vertices[i]` within
///   the virtual tree, given as original vertex ids. Each virtual edge
///   appears in both endpoints' lists, so the whole structure is a tree with
///   `vertices.length() - 1` edges.
///
/// To run bottom-up DP, iterate `i` from `vertices.length() - 1` down to `0`
/// (reverse DFS-entry order): a vertex is always visited after its
/// descendants. To distinguish a parent from a child among `adj[i]`, use
/// [`is_ancestor`] on the original builder.
pub struct VirtualTree {
  adj : Array[Array[Int]] // adj[i] = neighbours (original ids) of vertices[i]
  vertices : Array[Int] // virtual vertices (original ids), sorted by tin
  root : Int // = vertices[0], the root of the virtual tree
}

// ---------------------------------------------------------------------------
// Preprocessing
// ---------------------------------------------------------------------------

///|
/// Build the LCA / DFS-order preprocessing for a tree.
///
/// # Parameters
/// - `adj`: adjacency list of the undirected tree (`adj[v]` lists the
///   neighbours of `v`; each edge must appear in both directions).
/// - `root`: the root vertex (`0 <= root < n`).
/// - `n`: number of vertices, indexed `0 .. n - 1`.
///
/// # Returns
/// A [`VirtualTreeBuilder`] holding the DFS times, depths and binary-lifting
/// table. Pass it to [`build_virtual`] for each subset query.
pub fn build(
  adj : Array[Array[Int]],
  root : Int,
  n : Int,
) -> VirtualTreeBuilder {
  if n <= 0 {
    return {
      up: [],
      depth: FixedArray::make(0, 0),
      tin: FixedArray::make(0, 0),
      tout: FixedArray::make(0, 0),
      log_n: 0,
      n: 0,
      root: -1,
    }
  }
  let log_n = if n == 1 { 1 } else { ilog2(n) + 1 }
  let tin = FixedArray::make(n, 0)
  let tout = FixedArray::make(n, 0)
  let depth = FixedArray::make(n, 0)
  let parent = FixedArray::make(n, -1)
  let cursor = FixedArray::make(n, 0) // next neighbour index to examine for each vertex
  let visited = FixedArray::make(n, false)
  // --- Iterative DFS: assign tin/depth/parent on entry, tout on exit. ---
  // The timer advances only on entry, so `tin` is a permutation of 0..n-1
  // (a clean DFS-order index). At exit, `tout[v] = timer` is the entry time
  // that would be assigned next; hence w is a descendant of v (inclusive)
  // iff `tin[v] <= tin[w] && tout[w] <= tout[v]`. The root is its own
  // sentinel ancestor, so up[k][root] = root for all k.
  visited[root] = true
  parent[root] = root
  depth[root] = 0
  tin[root] = 0
  let mut timer = 1
  let stack : Array[Int] = [root]
  while stack.length() > 0 {
    let v = stack[stack.length() - 1]
    let mut descended = false
    // Advance v's neighbour cursor to the next unvisited neighbour.
    while cursor[v] < adj[v].length() {
      let u = adj[v][cursor[v]]
      cursor[v] = cursor[v] + 1
      if !visited[u] {
        visited[u] = true
        parent[u] = v
        depth[u] = depth[v] + 1
        tin[u] = timer
        timer = timer + 1
        stack.push(u)
        descended = true
        break
      }
    }
    if !descended {
      // All neighbours processed: v is finished.
      tout[v] = timer
      let _ = stack.pop()
    }
  }
  // --- Binary-lifting table: up[k][v] = 2^k-th ancestor of v. ---
  let up : Array[FixedArray[Int]] = []
  for k = 0; k < log_n; k = k + 1 {
    up.push(FixedArray::make(n, -1))
  }
  for v = 0; v < n; v = v + 1 {
    up[0][v] = parent[v]
  }
  for k = 1; k < log_n; k = k + 1 {
    for v = 0; v < n; v = v + 1 {
      up[k][v] = up[k - 1][up[k - 1][v]]
    }
  }
  { up, depth, tin, tout, log_n, n, root, }
}

///|
/// Floor of log2 for `n >= 1` (position of the highest set bit).
fn ilog2(n : Int) -> Int {
  let mut r = 0
  let mut m = n
  while m > 1 {
    r = r + 1
    m = m >> 1
  }
  r
}

// ---------------------------------------------------------------------------
// Virtual-tree construction
// ---------------------------------------------------------------------------

///|
/// Build the virtual tree of a subset of vertices.
///
/// # Parameters
/// - `vt`: a builder obtained from [`build`] for the original tree.
/// - `vertices`: the selected subset `S` (any order; duplicates are allowed
///   and collapsed). Every element must satisfy `0 <= v < vt.n`.
///
/// # Returns
/// A [`VirtualTree`] whose `vertices` are sorted by DFS entry time and whose
/// `adj` is the undirected adjacency list (original vertex ids). The root is
/// `vertices[0]`, i.e. the LCA of all selected vertices.
///
/// # Complexity
/// `O(|S| log |S|)`.
pub fn build_virtual(
  vt : VirtualTreeBuilder,
  vertices_in : Array[Int],
) -> VirtualTree {
  let k = vertices_in.length()
  if k == 0 {
    return { adj: [], vertices: [], root: -1, }
  }
  // Work on a copy sorted by DFS entry time.
  let verts : Array[Int] = []
  for i = 0; i < k; i = i + 1 {
    verts.push(vertices_in[i])
  }
  verts.sort_by(fn(a, b) { vt.tin[a] - vt.tin[b] })
  // S' = S ∪ { LCA(S[i], S[i+1]) }.  Because S' is LCA-closed, every LCA
  // needed by the stack pass below already belongs to S'.
  let nodes : Array[Int] = [verts[0]]
  for i = 0; i < k - 1; i = i + 1 {
    nodes.push(lca(vt, verts[i], verts[i + 1]))
    nodes.push(verts[i + 1])
  }
  // Sort S' by tin and drop duplicates (equal ids share a tin, so they are
  // adjacent after sorting).
  nodes.sort_by(fn(a, b) { vt.tin[a] - vt.tin[b] })
  let uniq : Array[Int] = [nodes[0]]
  for i = 1; i < nodes.length(); i = i + 1 {
    if nodes[i] != nodes[i - 1] {
      uniq.push(nodes[i])
    }
  }
  let m = uniq.length()
  // Position of each virtual vertex within `uniq` (original id -> index).
  let pos = FixedArray::make(vt.n, -1)
  for i = 0; i < m; i = i + 1 {
    pos[uniq[i]] = i
  }
  let adj : Array[Array[Int]] = []
  for i = 0; i < m; i = i + 1 {
    let row : Array[Int] = []
    adj.push(row)
  }
  // --- Stack-based construction over the right-most path. ---
  // The stack holds original ids along the current right-most path of the
  // virtual tree, root at the bottom. For each new vertex v, l = LCA(v, top)
  // is guaranteed to lie in `uniq`; we close finished branches, splice in `l`
  // if it sits strictly between the top two stack vertices, then push v.
  let stack : Array[Int] = [uniq[0]]
  for i = 1; i < m; i = i + 1 {
    let v = uniq[i]
    let l = lca(vt, v, stack[stack.length() - 1])
    // Close branches whose join is at least as deep as l.
    while stack.length() >= 2 &&
          vt.depth[stack[stack.length() - 2]] >= vt.depth[l] {
      let a = stack[stack.length() - 2]
      let b = stack[stack.length() - 1]
      adj[pos[a]].push(b)
      adj[pos[b]].push(a)
      let _ = stack.pop()
    }
    // If l sits strictly between the top and the vertex below it, splice l in.
    if vt.depth[stack[stack.length() - 1]] > vt.depth[l] {
      let b = stack[stack.length() - 1]
      adj[pos[l]].push(b)
      adj[pos[b]].push(l)
      let _ = stack.pop()
      stack.push(l)
    }
    stack.push(v)
  }
  // Emit the remaining edges along the right-most path.
  while stack.length() >= 2 {
    let a = stack[stack.length() - 2]
    let b = stack[stack.length() - 1]
    adj[pos[a]].push(b)
    adj[pos[b]].push(a)
    let _ = stack.pop()
  }
  { adj, vertices: uniq, root: uniq[0], }
}

// ---------------------------------------------------------------------------
// Query utilities
// ---------------------------------------------------------------------------

///|
/// Lowest common ancestor of `u` and `v` in the original tree.
///
/// Returns `-1` if either index is out of range; returns `u` if `u == v`.
/// Runs in `O(log n)`.
pub fn lca(vt : VirtualTreeBuilder, u_in : Int, v_in : Int) -> Int {
  let n = vt.n
  if u_in < 0 || u_in >= n || v_in < 0 || v_in >= n {
    return -1
  }
  let mut a = u_in
  let mut b = v_in
  // Equalise depths: lift the deeper vertex by their depth difference.
  if vt.depth[a] < vt.depth[b] {
    let tmp = a
    a = b
    b = tmp
  }
  let diff = vt.depth[a] - vt.depth[b]
  let mut k = 0
  let mut d = diff
  while d > 0 {
    if (d & 1) == 1 {
      a = vt.up[k][a]
    }
    d = d >> 1
    k = k + 1
  }
  if a == b {
    return a
  }
  // Lift both together from the largest power of two downwards.
  for k = vt.log_n - 1; k >= 0; k = k - 1 {
    if vt.up[k][a] != vt.up[k][b] {
      a = vt.up[k][a]
      b = vt.up[k][b]
    }
  }
  vt.up[0][a]
}

///|
/// Depth of vertex `v` (distance in edges from the root). `O(1)`.
pub fn depth_of(vt : VirtualTreeBuilder, v : Int) -> Int {
  if v < 0 || v >= vt.n {
    return -1
  }
  vt.depth[v]
}

///|
/// DFS entry time of vertex `v`. `O(1)`.
pub fn tin_of(vt : VirtualTreeBuilder, v : Int) -> Int {
  if v < 0 || v >= vt.n {
    return -1
  }
  vt.tin[v]
}

///|
/// DFS exit time of vertex `v`. `O(1)`.
pub fn tout_of(vt : VirtualTreeBuilder, v : Int) -> Int {
  if v < 0 || v >= vt.n {
    return -1
  }
  vt.tout[v]
}

///|
/// Whether `u` is an ancestor of `v` in the original tree (inclusive: a
/// vertex is its own ancestor). `O(1)`.
pub fn is_ancestor(vt : VirtualTreeBuilder, u : Int, v : Int) -> Bool {
  if u < 0 || u >= vt.n || v < 0 || v >= vt.n {
    return false
  }
  vt.tin[u] <= vt.tin[v] && vt.tout[u] >= vt.tout[v]
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
/// Build an undirected adjacency list from an edge list.
fn make_adj(n : Int, edges : Array[(Int, Int)]) -> Array[Array[Int]] {
  let adj : Array[Array[Int]] = []
  for i = 0; i < n; i = i + 1 {
    let row : Array[Int] = []
    adj.push(row)
  }
  for i = 0; i < edges.length(); i = i + 1 {
    let (u, v) = edges[i]
    adj[u].push(v)
    adj[v].push(u)
  }
  adj
}

///|
/// Index of original id `v` within a virtual tree's `vertices`, or `-1`.
fn vt_index(vt : VirtualTree, v : Int) -> Int {
  for i = 0; i < vt.vertices.length(); i = i + 1 {
    if vt.vertices[i] == v {
      return i
    }
  }
  -1
}

///|
/// Whether the undirected edge `{u, v}` exists in a virtual tree.
fn has_edge(vt : VirtualTree, u : Int, v : Int) -> Bool {
  let i = vt_index(vt, u)
  if i < 0 {
    return false
  }
  for j = 0; j < vt.adj[i].length(); j = j + 1 {
    if vt.adj[i][j] == v {
      return true
    }
  }
  false
}

///|
/// Number of undirected edges in a virtual tree.
fn edge_count(vt : VirtualTree) -> Int {
  let mut total = 0
  for i = 0; i < vt.adj.length(); i = i + 1 {
    total = total + vt.adj[i].length()
  }
  // Each undirected edge is stored in both adjacency lists.
  total / 2
}

///|
test "virtual_tree: builder lca utilities" {
  //       0
  //      / \
  //     1   2
  //    / \
  //   3   4
  let adj = make_adj(5, [(0, 1), (0, 2), (1, 3), (1, 4)])
  let vt = build(adj, 0, 5)
  assert_eq(lca(vt, 3, 4), 1)
  assert_eq(lca(vt, 3, 2), 0)
  assert_eq(lca(vt, 0, 4), 0)
  assert_eq(lca(vt, 3, 3), 3)
  assert_eq(lca(vt, -1, 0), -1)
  assert_eq(lca(vt, 0, 5), -1)
  assert_eq(depth_of(vt, 0), 0)
  assert_eq(depth_of(vt, 3), 2)
  assert_eq(depth_of(vt, -1), -1)
  // tin is a permutation of 0..n-1.
  let seen = FixedArray::make(5, false)
  for i = 0; i < 5; i = i + 1 {
    let t = tin_of(vt, i)
    assert_true(t >= 0 && t < 5)
    assert_false(seen[t])
    seen[t] = true
  }
  assert_true(is_ancestor(vt, 0, 4))
  assert_true(is_ancestor(vt, 1, 4))
  assert_false(is_ancestor(vt, 4, 1))
  assert_false(is_ancestor(vt, 3, 4))
  assert_true(is_ancestor(vt, 3, 3))
  assert_false(is_ancestor(vt, -1, 0))
}

///|
test "virtual_tree: simple tree" {
  //       0
  //      /|\
  //     1 2 3
  //    / \
  //   4   5
  //  DFS order (tin): 0,1,4,5,2,3
  let adj = make_adj(6, [(0, 1), (0, 2), (0, 3), (1, 4), (1, 5)])
  let vt = build(adj, 0, 6)
  let res = build_virtual(vt, [4, 5, 3])
  // S' = {4,5,3} ∪ {LCA(4,5)=1, LCA(5,3)=0} = {0,1,3,4,5}
  assert_eq(res.vertices.length(), 5)
  assert_eq(res.root, 0)
  assert_eq(vt_index(res, 2), -1) // 2 is not selected and is not an LCA
  for v in [0, 1, 3, 4, 5] {
    assert_true(vt_index(res, v) >= 0)
  }
  assert_true(has_edge(res, 0, 1))
  assert_true(has_edge(res, 1, 4))
  assert_true(has_edge(res, 1, 5))
  assert_true(has_edge(res, 0, 3))
  assert_false(has_edge(res, 0, 4))
  assert_false(has_edge(res, 4, 5))
  assert_eq(edge_count(res), 4) // 5 vertices -> 4 edges
  // Vertex-count bound: |S'| <= 2|S| - 1.
  assert_true(res.vertices.length() <= 2 * 3 - 1)
}

///|
test "virtual_tree: path graph" {
  // 0 - 1 - 2 - 3 - 4
  let adj = make_adj(5, [(0, 1), (1, 2), (2, 3), (3, 4)])
  let vt = build(adj, 0, 5)
  let res = build_virtual(vt, [0, 2, 4])
  // LCAs (0,2)=0 and (2,4)=2 are already in S, so S' = {0,2,4}.
  assert_eq(res.vertices.length(), 3)
  assert_eq(res.root, 0)
  assert_true(has_edge(res, 0, 2))
  assert_true(has_edge(res, 2, 4))
  assert_false(has_edge(res, 0, 4))
  assert_eq(edge_count(res), 2)
}

///|
test "virtual_tree: star graph" {
  // 0 is the centre; 1,2,3,4 are leaves.
  let adj = make_adj(5, [(0, 1), (0, 2), (0, 3), (0, 4)])
  let vt = build(adj, 0, 5)
  let res = build_virtual(vt, [1, 3, 4])
  // LCA of any two leaves is the centre 0, which is added once.
  assert_eq(res.vertices.length(), 4)
  assert_eq(res.root, 0)
  assert_true(has_edge(res, 0, 1))
  assert_true(has_edge(res, 0, 3))
  assert_true(has_edge(res, 0, 4))
  assert_false(has_edge(res, 1, 3))
  assert_eq(edge_count(res), 3)
}

///|
test "virtual_tree: all vertices selected" {
  //       0
  //      /|\
  //     1 2 3
  //    / \
  //   4   5
  let adj = make_adj(6, [(0, 1), (0, 2), (0, 3), (1, 4), (1, 5)])
  let vt = build(adj, 0, 6)
  let res = build_virtual(vt, [0, 1, 2, 3, 4, 5])
  // Selecting every vertex yields the original tree.
  assert_eq(res.vertices.length(), 6)
  assert_eq(res.root, 0)
  assert_true(has_edge(res, 0, 1))
  assert_true(has_edge(res, 0, 2))
  assert_true(has_edge(res, 0, 3))
  assert_true(has_edge(res, 1, 4))
  assert_true(has_edge(res, 1, 5))
  assert_eq(edge_count(res), 5)
}

///|
test "virtual_tree: single vertex" {
  let adj = make_adj(6, [(0, 1), (0, 2), (0, 3), (1, 4), (1, 5)])
  let vt = build(adj, 0, 6)
  let res = build_virtual(vt, [3])
  assert_eq(res.vertices.length(), 1)
  assert_eq(res.vertices[0], 3)
  assert_eq(res.root, 3)
  assert_eq(edge_count(res), 0)
}

///|
test "virtual_tree: empty selection" {
  let adj = make_adj(5, [(0, 1), (1, 2), (2, 3), (3, 4)])
  let vt = build(adj, 0, 5)
  let res = build_virtual(vt, [])
  assert_eq(res.vertices.length(), 0)
  assert_eq(res.adj.length(), 0)
  assert_eq(res.root, -1)
}

///|
test "virtual_tree: two sibling leaves" {
  //       0
  //      /|\
  //     1 2 3
  //    / \
  //   4   5
  let adj = make_adj(6, [(0, 1), (0, 2), (0, 3), (1, 4), (1, 5)])
  let vt = build(adj, 0, 6)
  let res = build_virtual(vt, [4, 5])
  // LCA(4,5) = 1 is inserted as the root of the virtual tree.
  assert_eq(res.vertices.length(), 3)
  assert_eq(res.root, 1)
  assert_true(has_edge(res, 1, 4))
  assert_true(has_edge(res, 1, 5))
  assert_eq(edge_count(res), 2)
  // |S'| == 2|S| - 1 hits the upper bound.
  assert_eq(res.vertices.length(), 2 * 2 - 1)
}

///|
test "virtual_tree: larger tree" {
  //         0
  //       /   \
  //      1     2
  //     / \   / \
  //    3   4 5   6
  //   / \
  //  7   8
  //  DFS order (tin): 0,1,3,7,8,4,2,5,6
  let adj = make_adj(9, [
    (0, 1),
    (0, 2),
    (1, 3),
    (1, 4),
    (2, 5),
    (2, 6),
    (3, 7),
    (3, 8),
  ])
  let vt = build(adj, 0, 9)
  let s = [7, 8, 5, 6]
  let res = build_virtual(vt, s)
  // |S| = 4, so |S'| <= 2*4 - 1 = 7; here the bound is tight.
  assert_true(res.vertices.length() <= 2 * s.length() - 1)
  assert_eq(res.vertices.length(), 7)
  assert_eq(res.root, 0)
  //        0
  //       / \
  //      3   2
  //     / \ / \
  //    7  8 5  6
  assert_true(has_edge(res, 0, 3))
  assert_true(has_edge(res, 3, 7))
  assert_true(has_edge(res, 3, 8))
  assert_true(has_edge(res, 0, 2))
  assert_true(has_edge(res, 2, 5))
  assert_true(has_edge(res, 2, 6))
  assert_eq(edge_count(res), 6) // 7 vertices -> 6 edges
  // The virtual root is the LCA of all selected vertices.
  let mut expected_root = s[0]
  for i = 1; i < s.length(); i = i + 1 {
    expected_root = lca(vt, expected_root, s[i])
  }
  assert_eq(res.root, expected_root)
  // Every virtual edge connects an ancestor-descendant pair in T.
  for i = 0; i < res.vertices.length(); i = i + 1 {
    let u = res.vertices[i]
    for j = 0; j < res.adj[i].length(); j = j + 1 {
      let w = res.adj[i][j]
      assert_true(is_ancestor(vt, u, w) || is_ancestor(vt, w, u))
    }
  }
}

///|
test "virtual_tree: edges preserve ancestry" {
  //         0
  //       /   \
  //      1     2
  //     / \   / \
  //    3   4 5   6
  //   / \
  //  7   8
  let adj = make_adj(9, [
    (0, 1),
    (0, 2),
    (1, 3),
    (1, 4),
    (2, 5),
    (2, 6),
    (3, 7),
    (3, 8),
  ])
  let vt = build(adj, 0, 9)
  let res = build_virtual(vt, [7, 4, 5, 6])
  //        0
  //       / \
  //      1   2
  //     / \ / \
  //    7  4 5  6
  assert_eq(res.vertices.length(), 7)
  assert_eq(res.root, 0)
  assert_true(has_edge(res, 0, 1))
  assert_true(has_edge(res, 1, 7))
  assert_true(has_edge(res, 1, 4))
  assert_true(has_edge(res, 0, 2))
  assert_true(has_edge(res, 2, 5))
  assert_true(has_edge(res, 2, 6))
  assert_eq(edge_count(res), 6)
  for i = 0; i < res.vertices.length(); i = i + 1 {
    let u = res.vertices[i]
    for j = 0; j < res.adj[i].length(); j = j + 1 {
      let w = res.adj[i][j]
      assert_true(is_ancestor(vt, u, w) || is_ancestor(vt, w, u))
    }
  }
}

///|
test "virtual_tree: input order independence" {
  // The result must not depend on the order of the input subset.
  let adj = make_adj(9, [
    (0, 1),
    (0, 2),
    (1, 3),
    (1, 4),
    (2, 5),
    (2, 6),
    (3, 7),
    (3, 8),
  ])
  let vt = build(adj, 0, 9)
  let s1 = [7, 8, 5, 6]
  let s2 = [6, 5, 8, 7]
  let r1 = build_virtual(vt, s1)
  let r2 = build_virtual(vt, s2)
  assert_eq(r1.vertices.length(), r2.vertices.length())
  assert_eq(r1.root, r2.root)
  for i = 0; i < r1.vertices.length(); i = i + 1 {
    assert_eq(r1.vertices[i], r2.vertices[i])
  }
  assert_eq(edge_count(r1), edge_count(r2))
}

///|
test "virtual_tree: duplicates collapsed" {
  let adj = make_adj(6, [(0, 1), (0, 2), (0, 3), (1, 4), (1, 5)])
  let vt = build(adj, 0, 6)
  let res = build_virtual(vt, [4, 4, 5, 5, 5])
  assert_eq(res.vertices.length(), 3) // {4, 5, LCA(4,5)=1}
  assert_eq(res.root, 1)
  assert_eq(edge_count(res), 2)
}

///|
test "virtual_tree: deep chain (no stack overflow)" {
  // A chain of 1000 nodes; the iterative DFS must not overflow.
  let n = 1000
  let edges : Array[(Int, Int)] = []
  for i = 0; i < n - 1; i = i + 1 {
    edges.push((i, i + 1))
  }
  let adj = make_adj(n, edges)
  let vt = build(adj, 0, n)
  assert_eq(depth_of(vt, 999), 999)
  assert_eq(lca(vt, 0, 999), 0)
  assert_eq(lca(vt, 10, 500), 10)
  // Select every other node: LCA(2k, 2k+2) = 2k is already in S, so S' = S.
  let s : Array[Int] = []
  for i = 0; i < n; i = i + 2 {
    s.push(i)
  }
  let res = build_virtual(vt, s)
  assert_true(res.vertices.length() <= 2 * s.length() - 1)
  assert_eq(res.vertices.length(), s.length())
  assert_eq(res.root, 0)
  assert_eq(edge_count(res), s.length() - 1) // a path 0-2-4-...-998
  // Adjacency of an interior virtual vertex 2k (0 < 2k < 998) is {2k-2, 2k+2}.
  for idx = 1; idx < s.length() - 1; idx = idx + 1 {
    let v = s[idx]
    assert_true(has_edge(res, v, v - 2))
    assert_true(has_edge(res, v, v + 2))
  }
}

///|
test "virtual_tree: balanced binary tree" {
  // Complete binary tree of depth 3 (15 nodes); node i has children 2i+1, 2i+2.
  let n = 15
  let edges : Array[(Int, Int)] = []
  for i = 0; i < 7; i = i + 1 {
    edges.push((i, 2 * i + 1))
    edges.push((i, 2 * i + 2))
  }
  let adj = make_adj(n, edges)
  let vt = build(adj, 0, n)
  // Select all leaves of the right subtree plus one left leaf.
  let res = build_virtual(vt, [7, 11, 13, 14])
  assert_true(res.vertices.length() <= 2 * 4 - 1)
  assert_eq(res.root, 0) // LCA(7, 14) = 0
  // Every edge preserves ancestry and the root is the overall LCA.
  let mut overall = 7
  for v in [11, 13, 14] {
    overall = lca(vt, overall, v)
  }
  assert_eq(res.root, overall)
  for i = 0; i < res.vertices.length(); i = i + 1 {
    let u = res.vertices[i]
    for j = 0; j < res.adj[i].length(); j = j + 1 {
      let w = res.adj[i][j]
      assert_true(is_ancestor(vt, u, w) || is_ancestor(vt, w, u))
    }
  }
  // The virtual tree is itself a tree: |E| = |V| - 1.
  assert_eq(edge_count(res), res.vertices.length() - 1)
}
