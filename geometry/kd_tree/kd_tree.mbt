/// KD-Tree: k-dimensional tree for 2D spatial indexing.
///
/// A space-partitioning data structure that recursively splits the point set
/// along alternating axes (x, y, x, y, ...). At each level, the median point
/// (by the current axis) becomes the node, and left/right subtrees are built
/// from the two halves.
///
/// **Supported operations.**
/// - `build`         — O(n log² n) construction (sort at each level)
/// - `nearest_neighbor` — O(log n) average, O(n) worst case, with pruning
/// - `range_search`  — O(√n + k) average, where k is the result count
/// - `size`          — O(1) (cached at construction)
///
/// **Overflow safety.** Squared distances use Int64. Coordinates up to
/// ~3037000499 per axis are safe (product < Int64::max).
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

/// A 2D point with integer coordinates.
pub struct Point {
  x : Int
  y : Int
}

/// Construct a [`Point`].
pub fn point(x : Int, y : Int) -> Point {
  { x, y }
}

/// KD-Tree node. `Empty` is the empty tree; `Node(left, pt, right, sz)`
/// stores the point, subtrees, and cached subtree size.
pub enum KDNode {
  Empty
  Node(KDNode, Point, KDNode, Int) // (left, point, right, size)
}

/// Construct an empty KD-Tree.
pub fn empty() -> KDNode {
  Empty
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Squared Euclidean distance (Int64 to prevent overflow).
fn dist2(a : Point, b : Point) -> Int64 {
  let dx = a.x.to_int64() - b.x.to_int64()
  let dy = a.y.to_int64() - b.y.to_int64()
  dx * dx + dy * dy
}

/// Merge sort of a Point subarray by the given axis (0 = x, 1 = y).
fn msort_points(
  pts : Array[Point],
  lo : Int,
  hi : Int,
  tmp : Array[Point],
  axis : Int,
) -> Unit {
  let len = hi - lo
  if len <= 1 {
    return
  }
  let mid = lo + len / 2
  msort_points(pts, lo, mid, tmp, axis)
  msort_points(pts, mid, hi, tmp, axis)
  let mut i = lo
  let mut j = mid
  for k = lo; k < hi; k = k + 1 {
    if j >= hi || (i < mid && le_axis(pts[i], pts[j], axis)) {
      tmp[k] = pts[i]
      i = i + 1
    } else {
      tmp[k] = pts[j]
      j = j + 1
    }
  }
  for k = lo; k < hi; k = k + 1 {
    pts[k] = tmp[k]
  }
}

/// True if `a` should come before `b` when sorted by the given axis.
fn le_axis(a : Point, b : Point, axis : Int) -> Bool {
  if axis == 0 {
    a.x <= b.x
  } else {
    a.y <= b.y
  }
}

// ---------------------------------------------------------------------------
// Build
// ---------------------------------------------------------------------------

/// Recursively build the KD-Tree from `pts[lo, hi)`.
fn build_rec(
  pts : Array[Point],
  lo : Int,
  hi : Int,
  depth : Int,
  tmp : Array[Point],
) -> KDNode {
  if lo >= hi {
    return Empty
  }
  let axis = depth % 2
  msort_points(pts, lo, hi, tmp, axis)
  let mid = lo + (hi - lo) / 2
  let left = build_rec(pts, lo, mid, depth + 1, tmp)
  let right = build_rec(pts, mid + 1, hi, depth + 1, tmp)
  let sz = (mid - lo) + (hi - mid - 1) + 1
  Node(left, pts[mid], right, sz)
}

/// Build a KD-Tree from an array of points.
///
/// The input array is copied internally, so the caller's array is not modified.
pub fn build(points : Array[Point]) -> KDNode {
  let n = points.length()
  if n == 0 {
    return Empty
  }
  let pts : Array[Point] = []
  for i = 0; i < n; i = i + 1 {
    pts.push(points[i])
  }
  let tmp : Array[Point] = []
  for i = 0; i < n; i = i + 1 {
    tmp.push(points[0])
  }
  build_rec(pts, 0, n, 0, tmp)
}

// ---------------------------------------------------------------------------
// Nearest neighbor
// ---------------------------------------------------------------------------

/// Recursively search for the nearest neighbor of `target`.
///
/// `best` is the current best point (or `None`), `best_d` is its squared
/// distance to the target. Returns the updated best point and distance.
fn nearest_rec(
  node : KDNode,
  target : Point,
  depth : Int,
  best : Point?,
  best_d : Int64,
) -> (Point?, Int64) {
  match node {
    Empty => (best, best_d)
    Node(left, pt, right, _) => {
      // Distance from target to current node's point.
      let d = dist2(pt, target)
      let (cur_best, cur_d) = if best is None || d < best_d {
        (Some(pt), d)
      } else {
        (best, best_d)
      }
      // Determine which subtree is "near" (same side as target).
      let axis = depth % 2
      let diff = if axis == 0 {
        target.x.to_int64() - pt.x.to_int64()
      } else {
        target.y.to_int64() - pt.y.to_int64()
      }
      let (near, far) = if diff <= 0L {
        (left, right)
      } else {
        (right, left)
      }
      // Search the near subtree first.
      let (b1, d1) = nearest_rec(near, target, depth + 1, cur_best, cur_d)
      // Only search the far subtree if the splitting plane is closer
      // than the current best.
      let plane_d = diff * diff
      if plane_d < d1 {
        nearest_rec(far, target, depth + 1, b1, d1)
      } else {
        (b1, d1)
      }
    }
  }
}

/// Find the nearest neighbor of `target` in the KD-Tree.
///
/// Returns `Some(point)` if the tree is non-empty, `None` otherwise.
pub fn nearest_neighbor(tree : KDNode, target : Point) -> Point? {
  let (best, _) = nearest_rec(tree, target, 0, None, 9223372036854775807L)
  best
}

// ---------------------------------------------------------------------------
// Range search
// ---------------------------------------------------------------------------

/// Recursively collect all points within the axis-aligned bounding box
/// [lo.x, hi.x] × [lo.y, hi.y].
fn range_rec(
  node : KDNode,
  lo : Point,
  hi : Point,
  depth : Int,
  result : Array[Point],
) -> Unit {
  match node {
    Empty => ()
    Node(left, pt, right, _) => {
      // Check if current point is within range.
      if pt.x >= lo.x && pt.x <= hi.x && pt.y >= lo.y && pt.y <= hi.y {
        result.push(pt)
      }
      let axis = depth % 2
      if axis == 0 {
        // Split by x: left subtree has points with x <= pt.x.
        if lo.x <= pt.x {
          range_rec(left, lo, hi, depth + 1, result)
        }
        if pt.x <= hi.x {
          range_rec(right, lo, hi, depth + 1, result)
        }
      } else {
        // Split by y: left subtree has points with y <= pt.y.
        if lo.y <= pt.y {
          range_rec(left, lo, hi, depth + 1, result)
        }
        if pt.y <= hi.y {
          range_rec(right, lo, hi, depth + 1, result)
        }
      }
    }
  }
}

/// Find all points within the axis-aligned bounding box [lo, hi] (inclusive).
///
/// Returns an array of points, possibly empty.
pub fn range_search(tree : KDNode, lo : Point, hi : Point) -> Array[Point] {
  let result : Array[Point] = []
  range_rec(tree, lo, hi, 0, result)
  result
}

// ---------------------------------------------------------------------------
// Utility
// ---------------------------------------------------------------------------

/// Return the number of points stored in the KD-Tree. O(1).
pub fn size(tree : KDNode) -> Int {
  match tree {
    Empty => 0
    Node(_, _, _, sz) => sz
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "kd_tree: build and size" {
  let pts = [point(3, 6), point(17, 15), point(13, 15), point(6, 12), point(9, 1), point(2, 7), point(10, 19)]
  let tree = build(pts)
  assert_eq(size(tree), 7)
}

test "kd_tree: empty tree" {
  let tree = build([])
  assert_eq(size(tree), 0)
  assert_true(nearest_neighbor(tree, point(0, 0)) is None)
  assert_eq(range_search(tree, point(0, 0), point(10, 10)).length(), 0)
}

test "kd_tree: single point" {
  let tree = build([point(5, 5)])
  assert_eq(size(tree), 1)
  let nn = nearest_neighbor(tree, point(0, 0))
  assert_true(nn is Some(_))
  let p = nn.unwrap()
  assert_eq(p.x, 5)
  assert_eq(p.y, 5)
}

test "kd_tree: nearest neighbor basic" {
  let pts = [point(2, 3), point(5, 4), point(9, 6), point(4, 7), point(8, 1), point(7, 2)]
  let tree = build(pts)
  let nn = nearest_neighbor(tree, point(6, 3)).unwrap()
  // Both (5,4) and (7,2) are at distance²=2 from (6,3); either is valid.
  let d2 = (nn.x - 6) * (nn.x - 6) + (nn.y - 3) * (nn.y - 3)
  assert_eq(d2, 2)
}

test "kd_tree: nearest neighbor exact match" {
  let pts = [point(2, 3), point(5, 4), point(9, 6), point(4, 7)]
  let tree = build(pts)
  let nn = nearest_neighbor(tree, point(5, 4)).unwrap()
  assert_eq(nn.x, 5)
  assert_eq(nn.y, 4)
}

test "kd_tree: nearest neighbor vs brute force" {
  let pts = [
    point(1, 1), point(2, 5), point(3, 3), point(4, 2), point(5, 5),
    point(6, 1), point(7, 4), point(8, 6), point(9, 8), point(10, 3),
  ]
  let tree = build(pts)
  let targets = [point(3, 4), point(7, 2), point(5, 7), point(0, 0), point(11, 11)]
  for i = 0; i < targets.length(); i = i + 1 {
    let t = targets[i]
    let nn = nearest_neighbor(tree, t).unwrap()
    // Brute force nearest neighbor
    let mut best_pt = pts[0]
    let mut best_d = 9223372036854775807L
    for j = 0; j < pts.length(); j = j + 1 {
      let dx = pts[j].x.to_int64() - t.x.to_int64()
      let dy = pts[j].y.to_int64() - t.y.to_int64()
      let d = dx * dx + dy * dy
      if d < best_d {
        best_d = d
        best_pt = pts[j]
      }
    }
    assert_eq(nn.x, best_pt.x)
    assert_eq(nn.y, best_pt.y)
  }
}

test "kd_tree: range search basic" {
  let pts = [
    point(1, 1), point(2, 5), point(3, 3), point(4, 2), point(5, 5),
    point(6, 1), point(7, 4), point(8, 6), point(9, 8), point(10, 3),
  ]
  let tree = build(pts)
  let result = range_search(tree, point(3, 2), point(7, 5))
  // Points in [3,7] × [2,5]: (3,3), (4,2), (5,5), (7,4)
  assert_eq(result.length(), 4)
  // Verify all results are in range.
  for i = 0; i < result.length(); i = i + 1 {
    let p = result[i]
    assert_true(p.x >= 3 && p.x <= 7)
    assert_true(p.y >= 2 && p.y <= 5)
  }
}

test "kd_tree: range search entire plane" {
  let pts = [point(1, 1), point(2, 5), point(3, 3), point(4, 2)]
  let tree = build(pts)
  let result = range_search(tree, point(-100, -100), point(100, 100))
  assert_eq(result.length(), 4)
}

test "kd_tree: range search empty" {
  let pts = [point(1, 1), point(2, 5), point(3, 3)]
  let tree = build(pts)
  let result = range_search(tree, point(100, 100), point(200, 200))
  assert_eq(result.length(), 0)
}

test "kd_tree: range search single point" {
  let pts = [point(5, 5), point(1, 1), point(9, 9)]
  let tree = build(pts)
  let result = range_search(tree, point(5, 5), point(5, 5))
  assert_eq(result.length(), 1)
  assert_eq(result[0].x, 5)
  assert_eq(result[0].y, 5)
}

test "kd_tree: duplicate points" {
  let pts = [point(3, 3), point(3, 3), point(3, 3)]
  let tree = build(pts)
  assert_eq(size(tree), 3)
  let result = range_search(tree, point(0, 0), point(10, 10))
  assert_eq(result.length(), 3)
  let nn = nearest_neighbor(tree, point(0, 0)).unwrap()
  assert_eq(nn.x, 3)
  assert_eq(nn.y, 3)
}

test "kd_tree: collinear points" {
  let pts = [point(0, 0), point(1, 0), point(2, 0), point(3, 0), point(4, 0)]
  let tree = build(pts)
  assert_eq(size(tree), 5)
  let nn = nearest_neighbor(tree, point(2, 1)).unwrap()
  assert_eq(nn.x, 2)
  assert_eq(nn.y, 0)
}

test "kd_tree: nearest neighbor with large coordinates" {
  let pts = [
    point(1000000, 2000000), point(3000000, 1000000), point(500000, 500000),
  ]
  let tree = build(pts)
  let nn = nearest_neighbor(tree, point(900000, 1800000)).unwrap()
  assert_eq(nn.x, 1000000)
  assert_eq(nn.y, 2000000)
}

test "kd_tree: random nearest neighbor" {
  // Generate 50 random points and verify nearest neighbor against brute force.
  let pts : Array[Point] = []
  let mut st = 42
  for i = 0; i < 50; i = i + 1 {
    st = (st * 31 + 7) % 1000003
    let x = st % 100
    st = (st * 31 + 7) % 1000003
    let y = st % 100
    pts.push(point(x, y))
  }
  let tree = build(pts)
  let targets = [point(50, 50), point(0, 0), point(99, 99), point(25, 75)]
  for i = 0; i < targets.length(); i = i + 1 {
    let t = targets[i]
    let nn = nearest_neighbor(tree, t).unwrap()
    let mut best_pt = pts[0]
    let mut best_d = 9223372036854775807L
    for j = 0; j < pts.length(); j = j + 1 {
      let dx = pts[j].x.to_int64() - t.x.to_int64()
      let dy = pts[j].y.to_int64() - t.y.to_int64()
      let d = dx * dx + dy * dy
      if d < best_d {
        best_d = d
        best_pt = pts[j]
      }
    }
    assert_eq(nn.x, best_pt.x)
    assert_eq(nn.y, best_pt.y)
  }
}
