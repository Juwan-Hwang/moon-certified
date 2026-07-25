/// Vantage Point Tree (VP-Tree) for metric space search.
///
/// A VP-Tree partitions points based on distance from a chosen "vantage
/// point." At each node, one point is selected as the vantage point; remaining
/// points are split into "near" (inside) and "far" (outside) groups based on
/// whether their distance to the vantage point is below or above a threshold
/// (typically the median distance).
///
/// ## Supported operations
/// - `build` — O(n log n) construction.
/// - `nearest_neighbor` — O(log n) average, O(n) worst case, with pruning.
/// - `range_search` — O(log n + k) average.
///
/// ## Advantages over KD-Tree
///
/// VP-Trees work with **any metric space**, not just Euclidean coordinates.
/// They are particularly effective for high-dimensional data or non-Euclidean
/// metrics (e.g., edit distance, Hamming distance).
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

/// VP-Tree node.
pub enum VPNode {
  Empty
  // (vantage_idx, threshold, left_near, right_far)
  Node(Int, Double, VPNode, VPNode)
}

/// The VP-Tree.
pub struct VPTree {
  root : VPNode
  n : Int
  dist : (Int, Int) -> Double
}

/// Build a VP-Tree from `n` points with the given metric distance function.
pub fn build(n : Int, dist : (Int, Int) -> Double) -> VPTree {
  if n == 0 {
    return { root: Empty, n: 0, dist }
  }
  let indices : Array[Int] = []
  for i = 0; i < n; i = i + 1 {
    indices.push(i)
  }
  let root = build_recursive(indices, dist)
  { root, n, dist }
}

fn build_recursive(
  indices : Array[Int],
  dist : (Int, Int) -> Double,
) -> VPNode {
  let m = indices.length()
  if m == 0 {
    return Empty
  }
  if m == 1 {
    // Leaf: just the vantage point with no children.
    return Node(indices[0], 0.0, Empty, Empty)
  }
  // Select vantage point: use the first point (simple strategy).
  // A better strategy would be to pick the point with maximum spread.
  let vp = indices[0]
  // Compute distances from vp to all other points.
  let others : Array[(Int, Double)] = []
  for i = 1; i < m; i = i + 1 {
    others.push((indices[i], dist(vp, indices[i])))
  }
  // Sort by distance.
  others.sort_by(fn(a, b) {
    if a.1 < b.1 {
      -1
    } else if a.1 > b.1 {
      1
    } else {
      0
    }
  })
  // Threshold: median distance.
  let mid = others.length() / 2
  let threshold = if others.length() > 0 {
    others[mid].1
  } else {
    0.0
  }
  // Split: near (distance <= threshold) go left, far go right.
  let near : Array[Int] = []
  let far : Array[Int] = []
  for i = 0; i < others.length(); i = i + 1 {
    if i <= mid {
      near.push(others[i].0)
    } else {
      far.push(others[i].0)
    }
  }
  let left = build_recursive(near, dist)
  let right = build_recursive(far, dist)
  Node(vp, threshold, left, right)
}

/// Find the nearest neighbour of query point `q_idx`.
///
/// Returns the index of the nearest point (not including `q_idx` itself).
/// Returns -1 if the tree is empty or has only one point.
pub fn nearest_neighbor(tree : VPTree, q_idx : Int) -> Int {
  if tree.n <= 1 {
    return -1
  }
  nn_recursive(tree.root, q_idx, tree.dist, -1, 1.0e18)
}

fn nn_recursive(
  node : VPNode,
  q_idx : Int,
  dist : (Int, Int) -> Double,
  best_idx : Int,
  best_dist : Double,
) -> Int {
  match node {
    Empty => best_idx
    Node(vp, threshold, left, right) =>
      if vp == q_idx {
        // Query is the vantage point; search both children.
        let b1 = nn_recursive(left, q_idx, dist, best_idx, best_dist)
        let bd1 = if b1 >= 0 { dist(q_idx, b1) } else { best_dist }
        nn_recursive(right, q_idx, dist, b1, bd1)
      } else {
        let d = dist(q_idx, vp)
        // Update best if vp is closer.
        let cur_idx = if d < best_dist { vp } else { best_idx }
        let cur_dist = if d < best_dist { d } else { best_dist }
        // Decide which child to search first.
        // If d <= threshold, query is "near"; search left first.
        if d <= threshold {
          let b1 = nn_recursive(left, q_idx, dist, cur_idx, cur_dist)
          let bd1 = if b1 >= 0 { dist(q_idx, b1) } else { cur_dist }
          // Prune: only search right if |d - threshold| < best_dist.
          if threshold - d < bd1 {
            nn_recursive(right, q_idx, dist, b1, bd1)
          } else {
            b1
          }
        } else {
          // Query is "far"; search right first.
          let b1 = nn_recursive(right, q_idx, dist, cur_idx, cur_dist)
          let bd1 = if b1 >= 0 { dist(q_idx, b1) } else { cur_dist }
          if d - threshold < bd1 {
            nn_recursive(left, q_idx, dist, b1, bd1)
          } else {
            b1
          }
        }
      }
  }
}

/// Find all points within `radius` of query point `q_idx`.
pub fn range_search(
  tree : VPTree,
  q_idx : Int,
  radius : Double,
) -> Array[Int] {
  let result : Array[Int] = []
  range_recursive(tree.root, q_idx, radius, tree.dist, result)
  result
}

fn range_recursive(
  node : VPNode,
  q_idx : Int,
  radius : Double,
  dist : (Int, Int) -> Double,
  result : Array[Int],
) -> Unit {
  match node {
    Empty => ()
    Node(vp, threshold, left, right) => {
      if vp != q_idx {
        let d = dist(q_idx, vp)
        if d <= radius {
          result.push(vp)
        }
      }
      // Prune: only search children if they could contain points within radius.
      // A point in the "near" subtree has distance to vp <= threshold.
      // If |d - threshold| <= radius, the near subtree might contain results.
      let d = if vp != q_idx {
        dist(q_idx, vp)
      } else {
        0.0
      }
      // Near subtree: points with dist(vp, p) <= threshold.
      // By triangle inequality: dist(q, p) >= |dist(q, vp) - dist(vp, p)|.
      // For near subtree: dist(vp, p) <= threshold, so
      // dist(q, p) >= dist(q, vp) - threshold = d - threshold.
      // If d - threshold > radius, no near point can be within radius.
      if d - threshold <= radius {
        range_recursive(left, q_idx, radius, dist, result)
      }
      // Far subtree: points with dist(vp, p) > threshold.
      // dist(q, p) >= threshold - dist(q, vp) = threshold - d.
      // If threshold - d > radius, no far point can be within radius.
      if threshold - d <= radius {
        range_recursive(right, q_idx, radius, dist, result)
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn dbl_abs(x : Double) -> Double {
  if x < 0.0 { -x } else { x }
}

fn dbl_sqrt(x : Double) -> Double {
  if x <= 0.0 {
    return 0.0
  }
  let mut r = x
  let mut i = 0
  while i < 64 {
    r = (r + x / r) / 2.0
    i = i + 1
  }
  r
}

fn euclidean_dist(points : Array[(Int, Int)]) -> (Int, Int) -> Double {
  fn(i : Int, j : Int) -> Double {
    let (xi, yi) = points[i]
    let (xj, yj) = points[j]
    let dx = (xi - xj).to_double()
    let dy = (yi - yj).to_double()
    dbl_sqrt(dx * dx + dy * dy)
  }
}

test "vp_tree: empty tree" {
  let tree = build(0, fn(_, _) { 0.0 })
  assert_eq(nearest_neighbor(tree, 0), -1)
}

test "vp_tree: single point" {
  let tree = build(1, fn(_, _) { 0.0 })
  assert_eq(nearest_neighbor(tree, 0), -1)
}

test "vp_tree: two points" {
  let points = [(0, 0), (10, 0)]
  let dist = euclidean_dist(points)
  let tree = build(2, dist)
  assert_eq(nearest_neighbor(tree, 0), 1)
  assert_eq(nearest_neighbor(tree, 1), 0)
}

test "vp_tree: nearest neighbor cross-check" {
  let points = [
    (0, 0), (10, 0), (5, 5), (3, 4), (7, 8), (2, 9), (8, 1),
  ]
  let n = points.length()
  let dist = euclidean_dist(points)
  let tree = build(n, dist)
  for q = 0; q < n; q = q + 1 {
    let tree_nn = nearest_neighbor(tree, q)
    let mut _bf_nn = -1
    let mut bf_dist = 1.0e18
    for j = 0; j < n; j = j + 1 {
      if j != q {
        let d = dist(q, j)
        if d < bf_dist {
          bf_dist = d
          _bf_nn = j
        }
      }
    }
    let tree_dist = if tree_nn >= 0 { dist(q, tree_nn) } else { 1.0e18 }
    assert_true(dbl_abs(tree_dist - bf_dist) < 0.001)
  }
}

test "vp_tree: range search cross-check" {
  let points = [
    (0, 0), (10, 0), (5, 5), (3, 4), (7, 8), (2, 9), (8, 1),
  ]
  let n = points.length()
  let dist = euclidean_dist(points)
  let tree = build(n, dist)
  let result = range_search(tree, 0, 6.0)
  // Brute force.
  let expected : Array[Int] = []
  for j = 1; j < n; j = j + 1 {
    if dist(0, j) <= 6.0 {
      expected.push(j)
    }
  }
  assert_eq(result.length(), expected.length())
}

test "vp_tree: range search empty for small radius" {
  let points = [(0, 0), (100, 100), (200, 200)]
  let dist = euclidean_dist(points)
  let tree = build(3, dist)
  let result = range_search(tree, 0, 1.0)
  assert_eq(result.length(), 0)
}
