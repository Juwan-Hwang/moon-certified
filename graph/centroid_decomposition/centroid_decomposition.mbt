/// Centroid Decomposition for divide-and-conquer on trees.
///
/// The centroid of a tree is a vertex whose removal splits the tree into
/// subtrees each of size at most n/2. Repeatedly finding centroids and
/// removing them produces the **centroid tree**, a rooted tree of depth
/// O(log n). This enables efficient divide-and-conquer algorithms for
/// path counting, distance queries, and other tree problems.
///
/// ## Algorithm
///
/// 1. Compute subtree sizes via a DFS.
/// 2. Find the centroid: walk down from the root, always moving to the
///    child whose subtree is larger than n/2. The vertex where no child
///    subtree exceeds n/2 is the centroid.
/// 3. Remove the centroid (mark it as removed), and recursively decompose
///    each remaining subtree.
///
/// ## Properties
///
/// - The centroid tree has depth O(log n).
/// - Any path in the original tree passes through O(log n) centroids.
/// - This makes it suitable for centroid-decomposition-based algorithms
///   (e.g., counting paths of length k).
///
/// ## Complexity
///
/// - Construction: O(n log n) (each level is O(n), depth is O(log n)).
/// - Path queries using centroid decomposition: O(n log² n) preprocessing,
///   O(log² n) per query.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

///|
/// Centroid Decomposition of a tree.
pub struct CentroidDecomp {
  n : Int
  /// centroid_parent[v] = parent of v in the centroid tree, or -1 for the
  /// root centroid.
  centroid_parent : FixedArray[Int]
  /// centroid_depth[v] = depth of v in the centroid tree (root has depth 0).
  centroid_depth : FixedArray[Int]
  /// The root centroid of the decomposition.
  root : Int
}

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

///|
/// Build the centroid decomposition of a tree.
///
/// # Parameters
/// - `adj`: adjacency list of the undirected tree.
/// - `n`: number of vertices, indexed `0 .. n - 1`.
///
/// # Returns
/// A [`CentroidDecomp`] with the centroid tree parent and depth arrays.
pub fn build(adj : Array[Array[Int]], n : Int) -> CentroidDecomp {
  if n == 0 {
    return {
      n: 0,
      centroid_parent: FixedArray::make(0, 0),
      centroid_depth: FixedArray::make(0, 0),
      root: -1,
    }
  }
  let centroid_parent = FixedArray::make(n, -1)
  let centroid_depth = FixedArray::make(n, 0)
  let removed = FixedArray::make(n, false)
  let size = FixedArray::make(n, 0)

  let mut root_centroid = -1
  // We process each connected component.
  // Start with the entire tree.
  let call_stack : Array[(Int, Int)] = [(0, -1)] // (component_start, centroid_parent)
  while call_stack.length() > 0 {
    let (start, c_parent) = call_stack[call_stack.length() - 1]
    let _ = call_stack.pop()
    // BFS to collect all vertices in this component (not removed).
    let component : Array[Int] = []
    let bfs_queue : Array[Int] = [start]
    let in_component = FixedArray::make(n, false)
    while bfs_queue.length() > 0 {
      let v = bfs_queue[0]
      ignore(bfs_queue.remove(0))
      if removed[v] || in_component[v] {
        continue
      }
      in_component[v] = true
      component.push(v)
      for idx = 0; idx < adj[v].length(); idx = idx + 1 {
        let u = adj[v][idx]
        if !removed[u] && !in_component[u] {
          bfs_queue.push(u)
        }
      }
    }
    if component.length() == 0 {
      continue
    }
    // Compute sizes via iterative DFS.
    let comp_size = component.length()
    for i = 0; i < component.length(); i = i + 1 {
      size[component[i]] = 1
    }
    // Post-order DFS to compute subtree sizes.
    let dfs_stack : Array[Int] = [start]
    let visited = FixedArray::make(n, false)
    visited[start] = true
    let post_order : Array[Int] = []
    let parent_in_comp = FixedArray::make(n, -1)
    while dfs_stack.length() > 0 {
      let v = dfs_stack[dfs_stack.length() - 1]
      let mut has_unvisited = false
      for idx = 0; idx < adj[v].length(); idx = idx + 1 {
        let u = adj[v][idx]
        if !removed[u] && !visited[u] {
          visited[u] = true
          parent_in_comp[u] = v
          dfs_stack.push(u)
          has_unvisited = true
          break
        }
      }
      if !has_unvisited {
        let _ = dfs_stack.pop()
        post_order.push(v)
      }
    }
    // Process in post-order to compute sizes.
    for i = 0; i < post_order.length(); i = i + 1 {
      let v = post_order[i]
      for idx = 0; idx < adj[v].length(); idx = idx + 1 {
        let u = adj[v][idx]
        if u != parent_in_comp[v] && !removed[u] {
          size[v] = size[v] + size[u]
        }
      }
    }
    // Find centroid: walk from start towards the heavy child.
    let mut centroid = start
    let mut found = false
    while !found {
      found = true
      for idx = 0; idx < adj[centroid].length(); idx = idx + 1 {
        let u = adj[centroid][idx]
        if !removed[u] && u != parent_in_comp[centroid] {
          if size[u] > comp_size / 2 {
            // Move to the heavy child.
            // Need to update sizes: the new root's size becomes comp_size - old size.
            centroid = u
            found = false
            break
          }
        }
      }
    }
    // Mark centroid as removed.
    removed[centroid] = true
    centroid_parent[centroid] = c_parent
    if c_parent == -1 {
      root_centroid = centroid
      centroid_depth[centroid] = 0
    } else {
      centroid_depth[centroid] = centroid_depth[c_parent] + 1
    }
    // Recurse on each subtree.
    for idx = 0; idx < adj[centroid].length(); idx = idx + 1 {
      let u = adj[centroid][idx]
      if !removed[u] {
        call_stack.push((u, centroid))
      }
    }
  }

  { n, centroid_parent, centroid_depth, root: root_centroid }
}

// ---------------------------------------------------------------------------
// Utility: collect all vertices in the centroid subtree rooted at `c`
// ---------------------------------------------------------------------------

///|
/// Collect all vertices in the centroid subtree rooted at centroid `c`.
/// This is the set of vertices for which `c` is an ancestor in the centroid tree.
pub fn centroid_subtree(
  _adj : Array[Array[Int]],
  cd : CentroidDecomp,
  c : Int,
) -> Array[Int] {
  let result : Array[Int] = [c]
  let stack : Array[Int] = [c]
  while stack.length() > 0 {
    let v = stack[stack.length() - 1]
    let _ = stack.pop()
    for i = 0; i < cd.n; i = i + 1 {
      if cd.centroid_parent[i] == v {
        result.push(i)
        stack.push(i)
      }
    }
  }
  result
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "centroid: single vertex" {
  let adj : Array[Array[Int]] = [[]]
  let cd = build(adj, 1)
  assert_eq(cd.root, 0)
  assert_eq(cd.centroid_parent[0], -1)
  assert_eq(cd.centroid_depth[0], 0)
}

///|
test "centroid: path of 3 (0-1-2)" {
  let adj : Array[Array[Int]] = [[1], [0, 2], [1]]
  let cd = build(adj, 3)
  // The centroid should be vertex 1 (middle vertex)
  assert_eq(cd.root, 1)
  // Depth of root is 0, children have depth 1
  assert_eq(cd.centroid_depth[1], 0)
  assert_true(cd.centroid_depth[0] == 1 || cd.centroid_depth[2] == 1)
  // Max depth is O(log n) = O(log 3) ≈ 2
  let mut max_depth = 0
  for i = 0; i < 3; i = i + 1 {
    if cd.centroid_depth[i] > max_depth {
      max_depth = cd.centroid_depth[i]
    }
  }
  assert_true(max_depth <= 2)
}

///|
test "centroid: star graph" {
  // 0 connected to 1, 2, 3, 4
  let adj : Array[Array[Int]] = [[1, 2, 3, 4], [0], [0], [0], [0]]
  let cd = build(adj, 5)
  // The centroid should be vertex 0 (center of star)
  assert_eq(cd.root, 0)
  assert_eq(cd.centroid_depth[0], 0)
  // All leaves should be children of 0
  for i = 1; i < 5; i = i + 1 {
    assert_eq(cd.centroid_parent[i], 0)
    assert_eq(cd.centroid_depth[i], 1)
  }
}

///|
test "centroid: balanced binary tree" {
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
  let cd = build(adj, 7)
  // Depth should be O(log n) = O(log 7) ≈ 3
  let mut max_depth = 0
  for i = 0; i < 7; i = i + 1 {
    if cd.centroid_depth[i] > max_depth {
      max_depth = cd.centroid_depth[i]
    }
  }
  assert_true(max_depth <= 3)
  // Every vertex (except root) has a valid parent
  for i = 0; i < 7; i = i + 1 {
    if i != cd.root {
      assert_true(cd.centroid_parent[i] != -1)
      assert_true(cd.centroid_parent[i] >= 0 && cd.centroid_parent[i] < 7)
    }
  }
}

///|
test "centroid: path of 10 (depth O(log n))" {
  // Linear path: 0-1-2-...-9
  let n = 10
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
  let cd = build(adj, n)
  // Depth should be O(log n)
  let mut max_depth = 0
  for i = 0; i < n; i = i + 1 {
    if cd.centroid_depth[i] > max_depth {
      max_depth = cd.centroid_depth[i]
    }
  }
  assert_true(max_depth <= 4) // ceil(log2(10)) ≈ 4
}

///|
test "centroid: path of 1000 (stress test)" {
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
  let cd = build(adj, n)
  // Depth should be O(log n) = O(log 1000) ≈ 10
  let mut max_depth = 0
  for i = 0; i < n; i = i + 1 {
    if cd.centroid_depth[i] > max_depth {
      max_depth = cd.centroid_depth[i]
    }
  }
  assert_true(max_depth <= 15) // generous bound for O(log n)
  // Every vertex is reachable from root in the centroid tree
  let mut count = 0
  for i = 0; i < n; i = i + 1 {
    if cd.centroid_parent[i] != -1 || i == cd.root {
      count = count + 1
    }
  }
  assert_eq(count, n)
}

///|
test "centroid: empty graph" {
  let cd = build([], 0)
  assert_eq(cd.root, -1)
}

///|
test "centroid: two vertices" {
  let adj : Array[Array[Int]] = [[1], [0]]
  let cd = build(adj, 2)
  assert_true(cd.root == 0 || cd.root == 1)
  // The other vertex is a child
  let other = if cd.root == 0 { 1 } else { 0 }
  assert_eq(cd.centroid_parent[other], cd.root)
  assert_eq(cd.centroid_depth[other], 1)
}
