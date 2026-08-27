/// van Emde Boas (vEB) Tree — O(log log U) priority queue for bounded universe.
///
/// The van Emde Boas tree supports insert, delete, successor, predecessor,
/// minimum, and maximum operations in **O(log log U)** time, where U is the
/// size of the universe {0, 1, ..., U-1}.
///
/// ## Key Idea
///
/// The universe {0, ..., U-1} is split into sqrt(U) "clusters" of size sqrt(U)
/// each. A recursive vEB structure stores:
/// - `min` / `max`: the minimum and maximum elements (min is NOT stored in clusters)
/// - `summary`: a vEB tree of size sqrt(U) tracking which clusters are non-empty
/// - `cluster[i]`: a vEB tree of size sqrt(U) for cluster i
///
/// Operations recurse on the summary (to find the right cluster) and on a
/// single cluster, giving the recurrence T(U) = T(sqrt(U)) + O(1) = O(log log U).
///
/// ## Complexity
///
/// - **Space**: O(U)
/// - **Time**: O(log log U) per operation.
///
/// ## References
///
/// - van Emde Boas, P. (1977): "Preserving Order in a Forest in Less Than
///   Logarithmic Time." FOCS.
/// - CLRS, 3rd ed., Chapter 20: "van Emde Boas Trees."
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// vEB Tree
// ---------------------------------------------------------------------------

///|
/// A van Emde Boas tree node.
///
/// For `bits <= 1` (universe <= 2), we use only min/max (base case).
/// For larger universes, we split into sqrt(U) clusters recursively.
struct VEBNode {
  bits : Int // log2(universe_size)
  mut min : Int // -1 if empty
  mut max : Int // -1 if empty
  summary : VEBNode? // None for bits <= 1 (leaf level)
  clusters : Array[VEBNode?] // size sqrt(universe), None for bits <= 1
}

///|
/// A van Emde Boas tree supporting integers in {0, 1, ..., U-1}.
///
/// Construct with `VEBTree::new(universe_size)`. The universe size is
/// rounded up to the next power of 2.
pub struct VEBTree {
  root : VEBNode
  universe : Int
}

///|
/// Create a new vEB tree with universe size `u`.
///
/// `u` is rounded up to the next power of 2.
pub fn VEBTree::new(u : Int) -> VEBTree {
  let universe = next_power_of_2(u)
  let bits = log2_int(universe)
  { root: build_node(bits), universe, }
}

///|
fn build_node(bits : Int) -> VEBNode {
  if bits <= 1 {
    // Base case: universe size 2, only min/max needed.
    { bits, min: -1, max: -1, summary: None, clusters: [], }
  } else {
    let sub_bits = bits / 2
    let cluster_count = 1 << (bits - sub_bits) // = 2^(high_bits)
    let clusters : Array[VEBNode?] = Array::make(cluster_count, None)
    let summary = build_node(bits - sub_bits)
    { bits, min: -1, max: -1, summary: Some(summary), clusters, }
  }
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

///|
/// Insert a value into the vEB tree. O(log log U).
pub fn insert(tree : VEBTree, x : Int) -> Unit {
  if x < 0 || x >= tree.universe {
    return
  }
  veb_insert(tree.root, x)
}

///|
/// Delete a value from the vEB tree. O(log log U).
pub fn delete(tree : VEBTree, x : Int) -> Unit {
  if x < 0 || x >= tree.universe {
    return
  }
  veb_delete(tree.root, x)
}

///|
/// Check whether `x` is in the vEB tree. O(log log U).
pub fn contains(tree : VEBTree, x : Int) -> Bool {
  if x < 0 || x >= tree.universe {
    return false
  }
  veb_contains(tree.root, x)
}

///|
/// Find the successor of `x` (smallest element > x). O(log log U).
pub fn successor(tree : VEBTree, x : Int) -> Int? {
  if x < -1 || x >= tree.universe {
    return None
  }
  veb_successor(tree.root, x)
}

///|
/// Find the predecessor of `x` (largest element < x). O(log log U).
pub fn predecessor(tree : VEBTree, x : Int) -> Int? {
  if x <= 0 || x > tree.universe {
    return None
  }
  veb_predecessor(tree.root, x)
}

///|
/// Get the minimum element, or `None` if empty. O(1).
pub fn minimum(tree : VEBTree) -> Int? {
  if tree.root.min == -1 {
    None
  } else {
    Some(tree.root.min)
  }
}

///|
/// Get the maximum element, or `None` if empty. O(1).
pub fn maximum(tree : VEBTree) -> Int? {
  if tree.root.max == -1 {
    None
  } else {
    Some(tree.root.max)
  }
}

///|
/// Check if the tree is empty. O(1).
pub fn is_empty(tree : VEBTree) -> Bool {
  tree.root.min == -1
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

///|
fn high(node : VEBNode, x : Int) -> Int {
  x >> (node.bits / 2)
}

///|
fn low(node : VEBNode, x : Int) -> Int {
  x & ((1 << (node.bits / 2)) - 1)
}

///|
fn index(node : VEBNode, h : Int, l : Int) -> Int {
  (h << (node.bits / 2)) | l
}

// ---------------------------------------------------------------------------
// Recursive operations
// ---------------------------------------------------------------------------

///|
fn veb_insert(node : VEBNode, x_val : Int) -> Unit {
  let mut x = x_val
  if node.min == -1 {
    node.min = x
    node.max = x
    return
  }
  if x < node.min {
    let old_min = node.min
    node.min = x
    x = old_min
  } else if x > node.max {
    node.max = x
  }
  if x == node.min {
    return
  }
  if node.bits <= 1 {
    return
  }
  let h = high(node, x)
  let l = low(node, x)
  match node.clusters[h] {
    None => {
      let cluster = build_node(node.bits / 2)
      veb_insert(cluster, l)
      node.clusters[h] = Some(cluster)
      match node.summary {
        Some(s) => veb_insert(s, h)
        None => ()
      }
    }
    Some(cluster) => veb_insert(cluster, l)
  }
}

///|
fn veb_delete(node : VEBNode, x_val : Int) -> Unit {
  let mut x = x_val
  if node.min == -1 {
    return
  }
  if node.min == node.max {
    if node.min == x {
      node.min = -1
      node.max = -1
    }
    return
  }
  if node.bits <= 1 {
    // Two elements: min=0, max=1 (or vice versa, but min < max always)
    if x == node.min {
      node.min = node.max
    } else if x == node.max {
      node.max = node.min
    }
    return
  }
  if x == node.min {
    // Replace min with the minimum element from the first non-empty cluster.
    match node.summary {
      Some(s) => {
        if s.min == -1 {
          node.min = node.max
          return
        }
        let first_cluster = s.min
        match node.clusters[first_cluster] {
          Some(cluster) => {
            node.min = index(node, first_cluster, cluster.min)
            x = node.min
          }
          None => return
        }
      }
      None => return
    }
  }
  // Delete x from its cluster.
  let h = high(node, x)
  let l = low(node, x)
  match node.clusters[h] {
    Some(cluster) => {
      veb_delete(cluster, l)
      if cluster.min == -1 {
        match node.summary {
          Some(s) => veb_delete(s, h)
          None => ()
        }
        node.clusters[h] = None
      }
    }
    None => ()
  }
  // Update max if needed.
  if x == node.max {
    match node.summary {
      Some(s) =>
        if s.max == -1 {
          node.max = node.min
        } else {
          match node.clusters[s.max] {
            Some(cluster) => node.max = index(node, s.max, cluster.max)
            None => node.max = node.min
          }
        }
      None => node.max = node.min
    }
  }
}

///|
fn veb_contains(node : VEBNode, x : Int) -> Bool {
  if node.min == -1 {
    return false
  }
  if x == node.min || x == node.max {
    return true
  }
  if node.bits <= 1 {
    return false
  }
  let h = high(node, x)
  let l = low(node, x)
  match node.clusters[h] {
    Some(cluster) => veb_contains(cluster, l)
    None => false
  }
}

///|
fn veb_successor(node : VEBNode, x : Int) -> Int? {
  if node.min == -1 {
    return None
  }
  if x < node.min {
    return Some(node.min)
  }
  if node.bits <= 1 {
    if x < node.max {
      return Some(node.max)
    }
    return None
  }
  let h = high(node, x)
  let l = low(node, x)
  let max_low = match node.clusters[h] {
    Some(cluster) => if cluster.max == -1 { -1 } else { cluster.max }
    None => -1
  }
  if max_low != -1 && l < max_low {
    match node.clusters[h] {
      Some(cluster) =>
        match veb_successor(cluster, l) {
          Some(s) => return Some(index(node, h, s))
          None => ()
        }
      None => ()
    }
  }
  match node.summary {
    Some(s) =>
      match veb_successor(s, h) {
        Some(next_cluster) =>
          match node.clusters[next_cluster] {
            Some(cluster) => return Some(index(node, next_cluster, cluster.min))
            None => return None
          }
        None => ()
      }
    None => ()
  }
  None
}

///|
fn veb_predecessor(node : VEBNode, x : Int) -> Int? {
  if node.min == -1 {
    return None
  }
  if x > node.max {
    return Some(node.max)
  }
  if node.bits <= 1 {
    if x > node.min {
      return Some(node.min)
    }
    return None
  }
  let h = high(node, x)
  let l = low(node, x)
  let min_low = match node.clusters[h] {
    Some(cluster) => if cluster.min == -1 { -1 } else { cluster.min }
    None => -1
  }
  if min_low != -1 && l > min_low {
    match node.clusters[h] {
      Some(cluster) =>
        match veb_predecessor(cluster, l) {
          Some(p) => return Some(index(node, h, p))
          None => ()
        }
      None => ()
    }
  }
  match node.summary {
    Some(s) =>
      match veb_predecessor(s, h) {
        Some(prev_cluster) =>
          match node.clusters[prev_cluster] {
            Some(cluster) => return Some(index(node, prev_cluster, cluster.max))
            None => return None
          }
        None => ()
      }
    None => ()
  }
  // min is NOT stored in any cluster (CLRS §20.3). If no cluster predecessor
  // was found via the summary, node.min itself may be the predecessor.
  if x > node.min {
    return Some(node.min)
  }
  None
}

// ---------------------------------------------------------------------------
// Utilities
// ---------------------------------------------------------------------------

///|
fn next_power_of_2(n : Int) -> Int {
  if n <= 1 {
    return 1
  }
  let mut p = 1
  while p < n {
    p = p * 2
  }
  p
}

///|
fn log2_int(n : Int) -> Int {
  let mut bits = 0
  let mut v = n
  while v > 1 {
    v = v >> 1
    bits = bits + 1
  }
  bits
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "veb: insert and contains" {
  let tree = VEBTree::new(256)
  insert(tree, 5)
  insert(tree, 10)
  insert(tree, 100)
  insert(tree, 200)
  assert_true(contains(tree, 5))
  assert_true(contains(tree, 10))
  assert_true(contains(tree, 100))
  assert_true(contains(tree, 200))
  assert_false(contains(tree, 0))
  assert_false(contains(tree, 50))
  assert_false(contains(tree, 255))
}

///|
test "veb: min and max" {
  let tree = VEBTree::new(1024)
  assert_true(is_empty(tree))
  insert(tree, 50)
  assert_false(is_empty(tree))
  assert_eq(minimum(tree), Some(50))
  assert_eq(maximum(tree), Some(50))
  insert(tree, 10)
  assert_eq(minimum(tree), Some(10))
  assert_eq(maximum(tree), Some(50))
  insert(tree, 500)
  assert_eq(minimum(tree), Some(10))
  assert_eq(maximum(tree), Some(500))
}

///|
test "veb: successor" {
  let tree = VEBTree::new(256)
  insert(tree, 5)
  insert(tree, 50)
  insert(tree, 100)
  insert(tree, 200)
  assert_eq(successor(tree, 0), Some(5))
  assert_eq(successor(tree, 5), Some(50))
  assert_eq(successor(tree, 49), Some(50))
  assert_eq(successor(tree, 50), Some(100))
  assert_eq(successor(tree, 100), Some(200))
  assert_eq(successor(tree, 200), None)
  assert_eq(successor(tree, 250), None)
}

///|
test "veb: predecessor" {
  let tree = VEBTree::new(256)
  insert(tree, 5)
  insert(tree, 50)
  insert(tree, 100)
  insert(tree, 200)
  assert_eq(predecessor(tree, 256), Some(200))
  assert_eq(predecessor(tree, 200), Some(100))
  assert_eq(predecessor(tree, 150), Some(100))
  assert_eq(predecessor(tree, 100), Some(50))
  assert_eq(predecessor(tree, 50), Some(5))
  assert_eq(predecessor(tree, 5), None)
  assert_eq(predecessor(tree, 1), None)
}

///|
test "veb: delete single element" {
  let tree = VEBTree::new(256)
  insert(tree, 42)
  assert_true(contains(tree, 42))
  delete(tree, 42)
  assert_false(contains(tree, 42))
  assert_true(is_empty(tree))
}

///|
test "veb: delete and reinsert" {
  let tree = VEBTree::new(256)
  insert(tree, 10)
  insert(tree, 20)
  insert(tree, 30)
  delete(tree, 20)
  assert_false(contains(tree, 20))
  assert_true(contains(tree, 10))
  assert_true(contains(tree, 30))
  assert_eq(successor(tree, 10), Some(30))
  assert_eq(predecessor(tree, 30), Some(10))
  insert(tree, 20)
  assert_true(contains(tree, 20))
  assert_eq(successor(tree, 10), Some(20))
}

///|
test "veb: delete all" {
  let tree = VEBTree::new(256)
  let vals = [5, 100, 50, 200, 150, 75, 25]
  for i = 0; i < vals.length(); i = i + 1 {
    insert(tree, vals[i])
  }
  for i = 0; i < vals.length(); i = i + 1 {
    delete(tree, vals[i])
  }
  assert_true(is_empty(tree))
}

///|
test "veb: delete min" {
  let tree = VEBTree::new(256)
  insert(tree, 10)
  insert(tree, 20)
  insert(tree, 30)
  delete(tree, 10)
  assert_eq(minimum(tree), Some(20))
  assert_true(contains(tree, 20))
  assert_true(contains(tree, 30))
  assert_false(contains(tree, 10))
}

///|
test "veb: delete max" {
  let tree = VEBTree::new(256)
  insert(tree, 10)
  insert(tree, 20)
  insert(tree, 30)
  delete(tree, 30)
  assert_eq(maximum(tree), Some(20))
  assert_true(contains(tree, 10))
  assert_true(contains(tree, 20))
  assert_false(contains(tree, 30))
}

///|
test "veb: large universe stress test" {
  let tree = VEBTree::new(65536)
  let vals = [1, 100, 1000, 10000, 50000, 65535, 42, 999, 33333]
  for i = 0; i < vals.length(); i = i + 1 {
    insert(tree, vals[i])
  }
  for i = 0; i < vals.length(); i = i + 1 {
    assert_true(contains(tree, vals[i]))
  }
  assert_eq(minimum(tree), Some(1))
  assert_eq(maximum(tree), Some(65535))
  let mut cur = -1
  let expected = [1, 42, 100, 999, 1000, 10000, 33333, 50000, 65535]
  for i = 0; i < expected.length(); i = i + 1 {
    match successor(tree, cur) {
      Some(s) => {
        assert_eq(s, expected[i])
        cur = s
      }
      None => assert_true(false)
    }
  }
  assert_eq(successor(tree, cur), None)
}

///|
test "veb: sequential insert and delete" {
  let tree = VEBTree::new(256)
  for i = 0; i < 100; i = i + 1 {
    insert(tree, i)
  }
  assert_eq(minimum(tree), Some(0))
  assert_eq(maximum(tree), Some(99))
  for i = 0; i < 100; i = i + 2 {
    delete(tree, i)
  }
  for i = 1; i < 100; i = i + 2 {
    assert_true(contains(tree, i))
  }
  for i = 0; i < 100; i = i + 2 {
    assert_false(contains(tree, i))
  }
  assert_eq(minimum(tree), Some(1))
  assert_eq(maximum(tree), Some(99))
}

///|
test "veb: empty tree operations" {
  let tree = VEBTree::new(256)
  assert_true(is_empty(tree))
  assert_eq(minimum(tree), None)
  assert_eq(maximum(tree), None)
  assert_eq(successor(tree, 5), None)
  assert_eq(predecessor(tree, 5), None)
  assert_false(contains(tree, 5))
  delete(tree, 42)
  assert_true(is_empty(tree))
}

///|
test "veb: duplicate insert" {
  let tree = VEBTree::new(256)
  insert(tree, 42)
  insert(tree, 42)
  insert(tree, 42)
  assert_true(contains(tree, 42))
  assert_eq(minimum(tree), Some(42))
  assert_eq(maximum(tree), Some(42))
  delete(tree, 42)
  assert_false(contains(tree, 42))
  assert_true(is_empty(tree))
}

///|
test "veb: small universe" {
  let tree = VEBTree::new(16)
  insert(tree, 3)
  insert(tree, 7)
  insert(tree, 15)
  insert(tree, 0)
  assert_eq(minimum(tree), Some(0))
  assert_eq(maximum(tree), Some(15))
  assert_eq(successor(tree, 3), Some(7))
  assert_eq(predecessor(tree, 15), Some(7))
  delete(tree, 7)
  assert_eq(successor(tree, 3), Some(15))
  assert_eq(predecessor(tree, 15), Some(3))
}

///|
test "veb: non-power-of-2 universe" {
  let tree = VEBTree::new(100)
  insert(tree, 50)
  insert(tree, 99)
  assert_true(contains(tree, 50))
  assert_true(contains(tree, 99))
  assert_eq(minimum(tree), Some(50))
  assert_eq(maximum(tree), Some(99))
  assert_eq(successor(tree, 50), Some(99))
}

///|
test "veb: interleaved operations" {
  let tree = VEBTree::new(1024)
  insert(tree, 100)
  insert(tree, 500)
  insert(tree, 200)
  assert_eq(successor(tree, 100), Some(200))
  delete(tree, 200)
  assert_eq(successor(tree, 100), Some(500))
  insert(tree, 300)
  assert_eq(successor(tree, 100), Some(300))
  assert_eq(successor(tree, 300), Some(500))
  delete(tree, 100)
  assert_eq(minimum(tree), Some(300))
  insert(tree, 50)
  assert_eq(minimum(tree), Some(50))
}
