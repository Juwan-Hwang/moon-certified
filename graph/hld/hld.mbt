/// Heavy-Light Decomposition (HLD) for tree path queries.
///
/// Decomposes a rooted tree into a set of vertex-disjoint chains such that
/// any root-to-leaf path intersects at most O(log n) chains. This enables
/// path queries (sum, min, max, ...) and path updates to be performed in
/// O(log² n) by mapping each chain segment to a range in an underlying
/// segment tree or Fenwick tree.
///
/// ## Algorithm
///
/// 1. **First DFS** (iterative): compute subtree sizes and identify the
///    heavy child (the child with the largest subtree) of each vertex.
/// 2. **Second DFS** (iterative): assign positions in DFS order. Starting
///    from the root, follow the heavy child to form a chain; the top of
///    each chain is a "light child" of some ancestor. Vertices are numbered
///    so that each chain occupies a contiguous range.
///
/// ## Properties
///
/// - `pos[v]`: the position of `v` in the linearised order (0-indexed).
/// - `head[v]`: the topmost vertex of the chain containing `v`.
/// - `parent[v]`: the parent of `v` (or `-1` for the root).
/// - `depth[v]`: the depth of `v` (root has depth 0).
///
/// Any path from `u` to `v` (via LCA) traverses at most O(log n) chains.
///
/// ## Complexity
///
/// - Construction: O(V + E) (two DFS traversals).
/// - Path query: O(log² V) with a segment tree, O(log V) with a Fenwick tree.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

///|
/// Heavy-Light Decomposition of a rooted tree.
pub struct HLD {
  n : Int
  parent : FixedArray[Int] // parent[v] = parent of v, -1 for root
  depth : FixedArray[Int] // depth[v] = depth of v, 0 for root
  heavy : FixedArray[Int] // heavy[v] = heavy child of v, -1 if leaf
  head : FixedArray[Int] // head[v] = top of the chain containing v
  pos : FixedArray[Int] // pos[v] = position in the linearised order
  size : FixedArray[Int] // size[v] = subtree size of v
}

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

///|
/// Build the Heavy-Light Decomposition of a tree.
///
/// # Parameters
/// - `adj`: adjacency list of the undirected tree.
/// - `root`: the root vertex (0-indexed).
/// - `n`: number of vertices.
///
/// # Returns
/// An [`HLD`] struct with all decomposition arrays filled.
pub fn build(adj : Array[Array[Int]], root : Int, n : Int) -> HLD {
  let parent = FixedArray::make(n, -1)
  let depth = FixedArray::make(n, 0)
  let heavy = FixedArray::make(n, -1)
  let head = FixedArray::make(n, root)
  let pos = FixedArray::make(n, 0)
  let size = FixedArray::make(n, 1)

  // --- First DFS: compute subtree sizes and heavy children (iterative). ---
  // Post-order processing using an explicit stack.
  let stack : Array[Int] = [root]
  let order : Array[Int] = [] // post-order traversal order
  let visited = FixedArray::make(n, false)
  visited[root] = true

  while stack.length() > 0 {
    let v = stack[stack.length() - 1]
    let mut has_unvisited = false
    for idx = 0; idx < adj[v].length(); idx = idx + 1 {
      let u = adj[v][idx]
      if !visited[u] {
        visited[u] = true
        parent[u] = v
        depth[u] = depth[v] + 1
        stack.push(u)
        has_unvisited = true
        break
      }
    }
    if !has_unvisited {
      let _ = stack.pop()
      order.push(v)
    }
  }

  // Process in post-order: compute sizes and identify heavy children.
  for i = 0; i < order.length(); i = i + 1 {
    let v = order[i]
    let mut max_size = 0
    for idx = 0; idx < adj[v].length(); idx = idx + 1 {
      let u = adj[v][idx]
      if u != parent[v] {
        size[v] = size[v] + size[u]
        if size[u] > max_size {
          max_size = size[u]
          heavy[v] = u
        }
      }
    }
  }

  // --- Second DFS: assign positions and chain heads (iterative). ---
  let mut cur_pos = 0
  // Process vertices in pre-order, following heavy edges first.
  let stack2 : Array[Int] = [root]
  while stack2.length() > 0 {
    let v = stack2[stack2.length() - 1]
    let _ = stack2.pop()
    pos[v] = cur_pos
    cur_pos = cur_pos + 1
    // Push light children first (so they're processed after the heavy chain).
    let light_children : Array[Int] = []
    for idx = 0; idx < adj[v].length(); idx = idx + 1 {
      let u = adj[v][idx]
      if u != parent[v] && u != heavy[v] {
        light_children.push(u)
      }
    }
    // Push light children (in reverse so they maintain order).
    for i = light_children.length() - 1; i >= 0; i = i - 1 {
      head[light_children[i]] = light_children[i]
      stack2.push(light_children[i])
    }
    // Push heavy child last (so it's processed next).
    if heavy[v] != -1 {
      head[heavy[v]] = head[v]
      stack2.push(heavy[v])
    }
  }

  { n, parent, depth, heavy, head, pos, size }
}

// ---------------------------------------------------------------------------
// Path decomposition
// ---------------------------------------------------------------------------

///|
/// A range `[l, r]` (inclusive) in the linearised order corresponding to a
/// chain segment on the path between two vertices.
pub struct PathSegment {
  l : Int
  r : Int
}

///|
/// Decompose the path from `u` to `v` into a sequence of contiguous ranges
/// in the linearised order. Each range corresponds to a chain segment.
///
/// The ranges are returned in order from `u` towards `v`. The caller can
/// use these ranges to query/update an underlying segment tree.
///
/// # Complexity
/// O(log n) segments.
pub fn path_segments(hld : HLD, u_in : Int, v_in : Int) -> Array[PathSegment] {
  let segments : Array[PathSegment] = []
  let mut u = u_in
  let mut v = v_in
  while hld.head[u] != hld.head[v] {
    if hld.depth[hld.head[u]] < hld.depth[hld.head[v]] {
      // Swap so u is always deeper.
      let tmp = u
      u = v
      v = tmp
    }
    // Add segment from head[u] to u.
    segments.push({ l: hld.pos[hld.head[u]], r: hld.pos[u] })
    u = hld.parent[hld.head[u]]
  }
  // Now u and v are on the same chain.
  if hld.depth[u] > hld.depth[v] {
    let tmp = u
    u = v
    v = tmp
  }
  segments.push({ l: hld.pos[u], r: hld.pos[v] })
  segments
}

///|
/// Decompose the path from `u` to `v` into segments, with each segment
/// oriented consistently from `u` towards `v`. This version returns segments
/// where `l <= r` always, and the direction is tracked separately.
///
/// Returns `(segments, reversed_segments)` where `segments` are from `u`'s
/// side and `reversed_segments` are from `v`'s side (to be processed in
/// reverse order).
pub fn path_directed(
  hld : HLD,
  u_in : Int,
  v_in : Int,
) -> (Array[PathSegment], Array[PathSegment]) {
  let u_segs : Array[PathSegment] = []
  let v_segs : Array[PathSegment] = []
  let mut u = u_in
  let mut v = v_in
  while hld.head[u] != hld.head[v] {
    if hld.depth[hld.head[u]] >= hld.depth[hld.head[v]] {
      u_segs.push({ l: hld.pos[hld.head[u]], r: hld.pos[u] })
      u = hld.parent[hld.head[u]]
    } else {
      v_segs.push({ l: hld.pos[hld.head[v]], r: hld.pos[v] })
      v = hld.parent[hld.head[v]]
    }
  }
  // Same chain now.
  if hld.depth[u] <= hld.depth[v] {
    u_segs.push({ l: hld.pos[u], r: hld.pos[v] })
  } else {
    u_segs.push({ l: hld.pos[v], r: hld.pos[u] })
  }
  (u_segs, v_segs)
}

///|
/// Get the range `[pos[v], pos[v] + size[v] - 1]` corresponding to the
/// entire subtree of `v`. This is a single contiguous range because the
/// HLD linearisation is a DFS order.
pub fn subtree_range(hld : HLD, v : Int) -> PathSegment {
  { l: hld.pos[v], r: hld.pos[v] + hld.size[v] - 1 }
}

///|
/// Compute the LCA (lowest common ancestor) of `u` and `v` using the HLD.
///
/// # Complexity
/// O(log n).
pub fn lca(hld : HLD, u_in : Int, v_in : Int) -> Int {
  let mut u = u_in
  let mut v = v_in
  while hld.head[u] != hld.head[v] {
    if hld.depth[hld.head[u]] < hld.depth[hld.head[v]] {
      let tmp = u
      u = v
      v = tmp
    }
    u = hld.parent[hld.head[u]]
  }
  if hld.depth[u] < hld.depth[v] {
    u
  } else {
    v
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "hld: simple chain" {
  // 0 - 1 - 2 - 3 - 4 (linear tree, root = 0)
  let adj : Array[Array[Int]] = [[1], [0, 2], [1, 3], [2, 4], [3]]
  let hld = build(adj, 0, 5)
  assert_eq(hld.parent[0], -1)
  assert_eq(hld.parent[1], 0)
  assert_eq(hld.depth[0], 0)
  assert_eq(hld.depth[4], 4)
  // Heavy child of 0 should be 1 (only child)
  assert_eq(hld.heavy[0], 1)
  // All on the same chain, head = root = 0
  assert_eq(hld.head[0], 0)
  assert_eq(hld.head[4], 0)
}

///|
test "hld: balanced binary tree" {
  //       0
  //      / \
  //     1   2
  //    / \ / \
  //   3  4 5  6
  let adj : Array[Array[Int]] = [
    [1, 2],
    [0, 3, 4],
    [0, 5, 6],
    [1],
    [1],
    [2],
    [2],
  ]
  let hld = build(adj, 0, 7)
  assert_eq(hld.size[0], 7)
  assert_eq(hld.size[1], 3)
  assert_eq(hld.size[2], 3)
  // Root's heavy child is either 1 or 2 (both have size 3)
  assert_true(hld.heavy[0] == 1 || hld.heavy[0] == 2)
  // pos values are unique and in [0, 7)
  let seen = FixedArray::make(7, false)
  for i = 0; i < 7; i = i + 1 {
    assert_true(hld.pos[i] >= 0 && hld.pos[i] < 7)
    assert_false(seen[hld.pos[i]])
    seen[hld.pos[i]] = true
  }
}

///|
test "hld: path segments on chain" {
  // Linear tree: 0-1-2-3-4
  let adj : Array[Array[Int]] = [[1], [0, 2], [1, 3], [2, 4], [3]]
  let hld = build(adj, 0, 5)
  // Path from 0 to 4 should be a single segment
  let segs = path_segments(hld, 0, 4)
  assert_eq(segs.length(), 1)
  assert_eq(segs[0].l, 0)
  assert_eq(segs[0].r, 4)
}

///|
test "hld: path segments on balanced tree" {
  //       0
  //      / \
  //     1   2
  //    / \
  //   3   4
  let adj : Array[Array[Int]] = [[1, 2], [0, 3, 4], [0], [1], [1]]
  let hld = build(adj, 0, 5)
  // Path from 3 to 2 should traverse at most 2 chains
  let segs = path_segments(hld, 3, 2)
  assert_true(segs.length() <= 3) // O(log n) bound
  // Verify segments cover the full path
}

///|
test "hld: LCA" {
  //       0
  //      / \
  //     1   2
  //    / \
  //   3   4
  let adj : Array[Array[Int]] = [[1, 2], [0, 3, 4], [0], [1], [1]]
  let hld = build(adj, 0, 5)
  assert_eq(lca(hld, 3, 4), 1)
  assert_eq(lca(hld, 3, 2), 0)
  assert_eq(lca(hld, 0, 4), 0)
  assert_eq(lca(hld, 3, 3), 3)
}

///|
test "hld: subtree range" {
  //       0
  //      / \
  //     1   2
  //    / \
  //   3   4
  let adj : Array[Array[Int]] = [[1, 2], [0, 3, 4], [0], [1], [1]]
  let hld = build(adj, 0, 5)
  let r0 = subtree_range(hld, 0)
  assert_eq(r0.r - r0.l + 1, 5) // entire tree
  let r1 = subtree_range(hld, 1)
  assert_eq(r1.r - r1.l + 1, 3) // subtree {1, 3, 4}
}

///|
test "hld: star graph" {
  // 0 is center, connected to 1, 2, 3, 4
  let adj : Array[Array[Int]] = [[1, 2, 3, 4], [0], [0], [0], [0]]
  let hld = build(adj, 0, 5)
  assert_eq(hld.size[0], 5)
  // Each leaf has size 1
  for i = 1; i < 5; i = i + 1 {
    assert_eq(hld.size[i], 1)
    assert_eq(hld.depth[i], 1)
  }
}

///|
test "hld: deep chain (1000 nodes)" {
  let n = 1000
  let adj : Array[Array[Int]] = []
  for i = 0; i < n; i = i + 1 {
    let edges : Array[Int] = []
    if i > 0 {
      edges.push(i - 1)
    }
    if i + 1 < n {
      edges.push(i + 1)
    }
    adj.push(edges)
  }
  let hld = build(adj, 0, n)
  assert_eq(hld.size[0], n)
  // Path from 0 to 999 should be a single segment (all on one chain)
  let segs = path_segments(hld, 0, n - 1)
  assert_eq(segs.length(), 1)
}

///|
test "hld: positions are a valid permutation" {
  //       0
  //      /|\
  //     1 2 3
  //    / \
  //   4   5
  let adj : Array[Array[Int]] = [[1, 2, 3], [0, 4, 5], [0], [0], [1], [1]]
  let hld = build(adj, 0, 6)
  let seen = FixedArray::make(6, false)
  for i = 0; i < 6; i = i + 1 {
    let p = hld.pos[i]
    assert_true(p >= 0 && p < 6)
    assert_false(seen[p])
    seen[p] = true
  }
}
