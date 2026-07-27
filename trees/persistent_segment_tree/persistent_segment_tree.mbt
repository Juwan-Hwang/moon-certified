/// Persistent Segment Tree (Chairman Tree) — Versioned Range Queries.
///
/// A persistent segment tree preserves all historical versions of the
/// tree after each update, enabling queries on any past version without
/// modifying it. Each update creates O(log n) new nodes sharing structure
/// with the previous version.
///
/// ## Primary Use Case: Range K-th Element
///
/// Given an array, after O(n log n) preprocessing, queries "find the
/// k-th smallest element in subarray [l, r)" are answered in O(log n).
///
/// ## Algorithm
///
/// 1. Coordinate-compress the values.
/// 2. Build a persistent segment tree over the value range, inserting
///    elements one at a time. Each insertion creates a new version
///    (O(log n) new nodes per insertion).
/// 3. For a range k-th query on [l, r), use versions r and l to compute
///    the count difference in O(log n).
///
/// ## Complexity
/// - Build: O(n log n) time and space.
/// - Update (single element): O(log n) time and space.
/// - Query (k-th in range): O(log n).
/// - Space: O(n log n) total nodes.
///
/// Reference: Chinese IOI training material, "Chairman Tree".
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

///|
/// A node in the persistent segment tree.
priv struct PSTNode {
  mut left : Int // Index of left child (-1 = null)
  mut right : Int // Index of right child (-1 = null)
  count : Int // Number of elements in this subtree
}

///|
/// A persistent segment tree supporting versioned range count queries.
pub struct PersistentSegTree {
  priv nodes : Array[PSTNode]
  priv versions : Array[Int] // Root node index for each version
  priv val_range : Int // Number of distinct compressed values
}

///|
/// Create a persistent segment tree for values in [0, val_range).
pub fn new(val_range : Int) -> PersistentSegTree {
  let tree = { nodes: [], versions: [], val_range }
  // Version 0: empty tree (no insertions yet).
  let root = build_empty(tree, 0, val_range)
  tree.versions.push(root)
  tree
}

///|
/// Build an empty subtree covering [lo, hi). Returns node index.
fn build_empty(tree : PersistentSegTree, lo : Int, hi : Int) -> Int {
  let idx = tree.nodes.length()
  tree.nodes.push({ left: -1, right: -1, count: 0 })
  if hi - lo > 1 {
    let mid = (lo + hi) / 2
    tree.nodes[idx].left = build_empty(tree, lo, mid)
    tree.nodes[idx].right = build_empty(tree, mid, hi)
  }
  idx
}

///|
/// Insert value `val` (0-indexed compressed value) into the tree,
/// creating a new version. Returns the new version index.
pub fn insert(tree : PersistentSegTree, val : Int) -> Int {
  let prev_root = tree.versions[tree.versions.length() - 1]
  let new_root = insert_rec(tree, prev_root, 0, tree.val_range, val)
  tree.versions.push(new_root)
  tree.versions.length() - 1
}

///|
/// Recursive insertion: clone nodes along the path, increment count.
fn insert_rec(
  tree : PersistentSegTree,
  node : Int,
  lo : Int,
  hi : Int,
  val : Int,
) -> Int {
  let old = tree.nodes[node]
  let new_idx = tree.nodes.length()
  tree.nodes.push({ left: old.left, right: old.right, count: old.count + 1 })
  if hi - lo > 1 {
    let mid = (lo + hi) / 2
    if val < mid {
      tree.nodes[new_idx].left = insert_rec(tree, old.left, lo, mid, val)
    } else {
      tree.nodes[new_idx].right = insert_rec(tree, old.right, mid, hi, val)
    }
  }
  new_idx
}

///|
/// Query the k-th smallest element in versions [version_l, version_r).
/// (i.e., elements inserted from version_l to version_r - 1).
/// Returns the 0-indexed compressed value.
/// k is 1-based (k=1 returns the minimum).
pub fn query_kth(
  tree : PersistentSegTree,
  version_l : Int,
  version_r : Int,
  k : Int,
) -> Int? {
  if version_l < 0 ||
    version_r >= tree.versions.length() ||
    version_l >= version_r {
    return None
  }
  let root_l = tree.versions[version_l]
  let root_r = tree.versions[version_r]
  let total = tree.nodes[root_r].count - tree.nodes[root_l].count
  if k < 1 || k > total {
    return None
  }
  Some(query_kth_rec(tree, root_l, root_r, 0, tree.val_range, k))
}

///|
/// Recursive k-th query: descend the tree, using count differences
/// between version_r and version_l to determine direction.
fn query_kth_rec(
  tree : PersistentSegTree,
  node_l : Int,
  node_r : Int,
  lo : Int,
  hi : Int,
  k : Int,
) -> Int {
  if hi - lo == 1 {
    return lo
  }
  let mid = (lo + hi) / 2
  let left_l = tree.nodes[node_l].left
  let left_r = tree.nodes[node_r].left
  let left_count = tree.nodes[left_r].count - tree.nodes[left_l].count
  if k <= left_count {
    query_kth_rec(tree, left_l, left_r, lo, mid, k)
  } else {
    query_kth_rec(
      tree,
      tree.nodes[node_l].right,
      tree.nodes[node_r].right,
      mid,
      hi,
      k - left_count,
    )
  }
}

///|
/// Number of versions (including the empty version 0).
pub fn version_count(tree : PersistentSegTree) -> Int {
  tree.versions.length()
}

///|
/// Total number of elements inserted up to version v (inclusive).
pub fn count_at_version(tree : PersistentSegTree, v : Int) -> Int {
  if v < 0 || v >= tree.versions.length() {
    return 0
  }
  tree.nodes[tree.versions[v]].count
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "pst: basic k-th query" {
  // Array: [3, 1, 4, 1, 5]
  // Compressed: {1:0, 3:1, 4:2, 5:3}, val_range = 4
  let tree = new(4)
  // Insert in original order: 3, 1, 4, 1, 5
  // Compressed values: 1, 0, 2, 0, 3
  ignore(insert(tree, 1)) // v1: {3}
  ignore(insert(tree, 0)) // v2: {3, 1}
  ignore(insert(tree, 2)) // v3: {3, 1, 4}
  ignore(insert(tree, 0)) // v4: {3, 1, 4, 1}
  ignore(insert(tree, 3)) // v5: {3, 1, 4, 1, 5}
  // Query k-th in range [0, 5) (all elements): 1, 1, 3, 4, 5
  // Compressed: 0, 0, 1, 2, 3
  assert_eq(query_kth(tree, 0, 5, 1), Some(0)) // 1st smallest = 0 (value 1)
  assert_eq(query_kth(tree, 0, 5, 2), Some(0)) // 2nd smallest = 0 (value 1)
  assert_eq(query_kth(tree, 0, 5, 3), Some(1)) // 3rd smallest = 1 (value 3)
  assert_eq(query_kth(tree, 0, 5, 4), Some(2)) // 4th smallest = 2 (value 4)
  assert_eq(query_kth(tree, 0, 5, 5), Some(3)) // 5th smallest = 3 (value 5)
  assert_eq(query_kth(tree, 0, 5, 6), None) // out of range
}

///|
test "pst: subarray k-th query" {
  // Array: [5, 2, 8, 1, 9]
  // Compressed: {1:0, 2:1, 5:2, 8:3, 9:4}, val_range = 5
  let tree = new(5)
  ignore(insert(tree, 2)) // v1: {5}
  ignore(insert(tree, 1)) // v2: {5, 2}
  ignore(insert(tree, 3)) // v3: {5, 2, 8}
  ignore(insert(tree, 0)) // v4: {5, 2, 8, 1}
  ignore(insert(tree, 4)) // v5: {5, 2, 8, 1, 9}
  // Query k-th in range [2, 5) (elements 8, 1, 9):
  // Sorted: 1, 8, 9 → compressed: 0, 3, 4
  assert_eq(query_kth(tree, 2, 5, 1), Some(0)) // 1st = 0 (value 1)
  assert_eq(query_kth(tree, 2, 5, 2), Some(3)) // 2nd = 3 (value 8)
  assert_eq(query_kth(tree, 2, 5, 3), Some(4)) // 3rd = 4 (value 9)
}

///|
test "pst: count at version" {
  let tree = new(10)
  assert_eq(count_at_version(tree, 0), 0)
  ignore(insert(tree, 3))
  assert_eq(count_at_version(tree, 1), 1)
  ignore(insert(tree, 5))
  assert_eq(count_at_version(tree, 2), 2)
  ignore(insert(tree, 7))
  assert_eq(count_at_version(tree, 3), 3)
}

///|
test "pst: version count" {
  let tree = new(10)
  assert_eq(version_count(tree), 1)
  ignore(insert(tree, 1))
  assert_eq(version_count(tree), 2)
  ignore(insert(tree, 2))
  assert_eq(version_count(tree), 3)
}

///|
test "pst: single element" {
  let tree = new(5)
  ignore(insert(tree, 2))
  assert_eq(query_kth(tree, 0, 1, 1), Some(2))
  assert_eq(query_kth(tree, 0, 1, 2), None)
}

///|
test "pst: duplicate values" {
  let tree = new(3)
  ignore(insert(tree, 0))
  ignore(insert(tree, 0))
  ignore(insert(tree, 0))
  assert_eq(query_kth(tree, 0, 3, 1), Some(0))
  assert_eq(query_kth(tree, 0, 3, 2), Some(0))
  assert_eq(query_kth(tree, 0, 3, 3), Some(0))
  assert_eq(query_kth(tree, 0, 3, 4), None)
}

///|
test "pst: large scale" {
  let tree = new(100)
  for i = 0; i < 50; i = i + 1 {
    ignore(insert(tree, i * 7 % 100))
  }
  // Query the median of all 50 elements.
  let med = query_kth(tree, 0, 50, 25)
  assert_true(med is Some(_))
}
