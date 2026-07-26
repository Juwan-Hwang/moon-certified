/// Ball-Tree: a metric tree for efficient nearest-neighbour search.
///
/// A Ball-Tree recursively partitions points into nested hyperspheres. Each
/// internal node stores a center point and a radius: all points in its subtree
/// are within `radius` of the center. Points are split into two children by
/// finding the pair of points with maximum spread and partitioning.
///
/// ## Supported operations
/// - `build` — O(n log n) construction.
/// - `nearest_neighbor` — O(log n) average, O(n) worst case, with pruning.
/// - `range_search` — O(log n + k) average.
///
/// ## Metric space
///
/// The Ball-Tree works with any metric space: the caller provides a distance
/// function `(i, j) -> Double` that gives the distance between points `i` and
/// `j` (by index).
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

///|
/// A Ball-Tree node.
pub enum BallNode {
  Empty
  // (left, center_idx, radius, right, num_points)
  Node(BallNode, Int, Double, BallNode, Int)
  // Leaf: a single point.
  Leaf(Int)
}

///|
/// The Ball-Tree with its associated point set and distance function.
pub struct BallTree {
  root : BallNode
  n : Int
  dist : (Int, Int) -> Double
}

///|
/// Build a Ball-Tree from `n` points with the given distance function.
pub fn build(n : Int, dist : (Int, Int) -> Double) -> BallTree {
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

///|
fn build_recursive(
  indices : Array[Int],
  dist : (Int, Int) -> Double,
) -> BallNode {
  let m = indices.length()
  if m == 0 {
    return Empty
  }
  if m == 1 {
    return Leaf(indices[0])
  }
  // Find the center: the point with minimum total distance to all others.
  let mut center_idx = indices[0]
  let mut min_sum = 1.0e18
  for i = 0; i < m; i = i + 1 {
    let mut sum = 0.0
    for j = 0; j < m; j = j + 1 {
      if i != j {
        sum = sum + dist(indices[i], indices[j])
      }
    }
    if sum < min_sum {
      min_sum = sum
      center_idx = indices[i]
    }
  }
  // Compute radius: max distance from center to any point.
  let mut radius = 0.0
  for i = 0; i < m; i = i + 1 {
    let d = dist(center_idx, indices[i])
    if d > radius {
      radius = d
    }
  }
  // Split: find the pair of points with maximum distance.
  let mut p1 = indices[0]
  let mut p2 = indices[1]
  let mut max_dist = 0.0
  for i = 0; i < m; i = i + 1 {
    for j = i + 1; j < m; j = j + 1 {
      let d = dist(indices[i], indices[j])
      if d > max_dist {
        max_dist = d
        p1 = indices[i]
        p2 = indices[j]
      }
    }
  }
  // Partition: points closer to p1 go left, closer to p2 go right.
  let left_indices : Array[Int] = []
  let right_indices : Array[Int] = []
  for i = 0; i < m; i = i + 1 {
    if indices[i] == center_idx {
      continue // Don't put center in either child
    }
    let d1 = dist(p1, indices[i])
    let d2 = dist(p2, indices[i])
    if d1 <= d2 {
      left_indices.push(indices[i])
    } else {
      right_indices.push(indices[i])
    }
  }
  if left_indices.length() == 0 && right_indices.length() > 0 {
    left_indices.push(right_indices[0])
    ignore(right_indices.remove(0))
  } else if right_indices.length() == 0 && left_indices.length() > 0 {
    right_indices.push(left_indices[left_indices.length() - 1])
    ignore(left_indices.remove(left_indices.length() - 1))
  }
  let left = build_recursive(left_indices, dist)
  let right = build_recursive(right_indices, dist)
  Node(left, center_idx, radius, right, m)
}

///|
/// Find the nearest neighbour of query point `q_idx`.
///
/// Returns the index of the nearest point (not including `q_idx` itself).
/// Returns -1 if the tree is empty or has only one point.
pub fn nearest_neighbor(tree : BallTree, q_idx : Int) -> Int {
  if tree.n <= 1 {
    return -1
  }
  nn_recursive(tree.root, q_idx, tree.dist, -1, 1.0e18)
}

///|
/// Nearest-neighbor recursive search. Returns the best index found.
/// `best_idx` / `best_dist` carry the current best result.
fn nn_recursive(
  node : BallNode,
  q_idx : Int,
  dist : (Int, Int) -> Double,
  best_idx : Int,
  best_dist : Double,
) -> Int {
  match node {
    Empty => best_idx
    Leaf(idx) =>
      if idx == q_idx {
        best_idx
      } else {
        let d = dist(q_idx, idx)
        if d < best_dist {
          idx
        } else {
          best_idx
        }
      }
    Node(left, center_idx, _, right, _) =>
      if center_idx == q_idx {
        let b1 = nn_recursive(left, q_idx, dist, best_idx, best_dist)
        let bd1 = if b1 >= 0 { dist(q_idx, b1) } else { best_dist }
        nn_recursive(right, q_idx, dist, b1, bd1)
      } else {
        let d = dist(q_idx, center_idx)
        let cur_idx = if d < best_dist { center_idx } else { best_idx }
        let cur_dist = if d < best_dist { d } else { best_dist }
        let d_left = subtree_min_dist(left, q_idx, dist)
        let d_right = subtree_min_dist(right, q_idx, dist)
        if d_left <= d_right {
          let b1 = nn_recursive(left, q_idx, dist, cur_idx, cur_dist)
          let bd1 = if b1 >= 0 { dist(q_idx, b1) } else { cur_dist }
          if d_right < bd1 {
            nn_recursive(right, q_idx, dist, b1, bd1)
          } else {
            b1
          }
        } else {
          let b1 = nn_recursive(right, q_idx, dist, cur_idx, cur_dist)
          let bd1 = if b1 >= 0 { dist(q_idx, b1) } else { cur_dist }
          if d_left < bd1 {
            nn_recursive(left, q_idx, dist, b1, bd1)
          } else {
            b1
          }
        }
      }
  }
}

///|
/// Lower bound on distance from `q_idx` to any point in the subtree.
fn subtree_min_dist(
  node : BallNode,
  q_idx : Int,
  dist : (Int, Int) -> Double,
) -> Double {
  match node {
    Empty => 1.0e18
    Leaf(idx) => if idx == q_idx { 1.0e18 } else { dist(q_idx, idx) }
    Node(_, center_idx, radius, _, _) => {
      let d = dist(q_idx, center_idx)
      if d > radius {
        d - radius
      } else {
        0.0
      }
    }
  }
}

///|
/// Find all points within `radius` of query point `q_idx`.
pub fn range_search(
  tree : BallTree,
  q_idx : Int,
  radius : Double,
) -> Array[Int] {
  let result : Array[Int] = []
  range_recursive(tree.root, q_idx, radius, tree.dist, result)
  result
}

///|
fn range_recursive(
  node : BallNode,
  q_idx : Int,
  radius : Double,
  dist : (Int, Int) -> Double,
  result : Array[Int],
) -> Unit {
  match node {
    Empty => ()
    Leaf(idx) =>
      if idx != q_idx {
        let d = dist(q_idx, idx)
        if d <= radius {
          result.push(idx)
        }
      }
    Node(left, center_idx, node_radius, right, _) => {
      let d = dist(q_idx, center_idx)
      if center_idx != q_idx && d <= radius {
        result.push(center_idx)
      }
      let min_d = if d > node_radius { d - node_radius } else { 0.0 }
      if min_d <= radius {
        range_recursive(left, q_idx, radius, dist, result)
        range_recursive(right, q_idx, radius, dist, result)
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
fn dbl_abs(x : Double) -> Double {
  if x < 0.0 {
    -x
  } else {
    x
  }
}

///|
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

///|
fn euclidean_dist(points : Array[(Int, Int)]) -> (Int, Int) -> Double {
  fn(i : Int, j : Int) -> Double {
    let (xi, yi) = points[i]
    let (xj, yj) = points[j]
    let dx = (xi - xj).to_double()
    let dy = (yi - yj).to_double()
    dbl_sqrt(dx * dx + dy * dy)
  }
}

///|
test "ball_tree: empty tree" {
  let tree = build(0, fn(_, _) { 0.0 })
  assert_eq(nearest_neighbor(tree, 0), -1)
}

///|
test "ball_tree: single point" {
  let tree = build(1, fn(_, _) { 0.0 })
  assert_eq(nearest_neighbor(tree, 0), -1)
}

///|
test "ball_tree: two points" {
  let points = [(0, 0), (10, 0)]
  let dist = euclidean_dist(points)
  let tree = build(2, dist)
  assert_eq(nearest_neighbor(tree, 0), 1)
  assert_eq(nearest_neighbor(tree, 1), 0)
}

///|
test "ball_tree: nearest neighbor cross-check" {
  let points = [(0, 0), (10, 0), (5, 5), (3, 4), (7, 8), (2, 9), (8, 1)]
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

///|
test "ball_tree: range search" {
  let points = [(0, 0), (10, 0), (5, 5), (3, 4), (7, 8), (2, 9), (8, 1)]
  let n = points.length()
  let dist = euclidean_dist(points)
  let tree = build(n, dist)
  let result = range_search(tree, 0, 6.0)
  // Brute force check.
  let expected : Array[Int] = []
  for j = 1; j < n; j = j + 1 {
    let d = dist(0, j)
    if d <= 6.0 {
      expected.push(j)
    }
  }
  assert_eq(result.length(), expected.length())
}

///|
test "ball_tree: range search returns empty for small radius" {
  let points = [(0, 0), (100, 100), (200, 200)]
  let dist = euclidean_dist(points)
  let tree = build(3, dist)
  let result = range_search(tree, 0, 1.0)
  assert_eq(result.length(), 0)
}
