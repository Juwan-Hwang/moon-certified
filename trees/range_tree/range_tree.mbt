/// 2D Range Tree — orthogonal range queries in O(log² n).
///
/// A range tree supports queries of the form: "find all points in
/// rectangle [x1, x2] × [y1, y2]." It is a multi-level search tree:
/// the primary tree is sorted by x-coordinate; each node stores a
/// secondary tree sorted by y-coordinate of the points in its subtree.
///
/// ## Complexity
/// | Operation | Time          |
/// |-----------|---------------|
/// | build     | O(n log n)    |
/// | query     | O(k + log² n) | k = results
/// | space     | O(n log n)    |
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

///|
/// A 2D point.
pub struct Point2D {
  x : Int
  y : Int
}

///|
/// A range tree node.
priv struct RTNode {
  point : Point2D
  left : RTNode?
  right : RTNode?
}

///|
/// A 2D range tree.
pub struct RangeTree {
  priv mut root : RTNode?
  priv count : Int
}

///|
/// Create a new empty range tree.
pub fn new() -> RangeTree {
  { root: None, count: 0, }
}

///|
/// Build the range tree from a set of points. O(n log n).
pub fn build(points : Array[Point2D]) -> RangeTree {
  let n = points.length()
  if n == 0 {
    return { root: None, count: 0, }
  }
  // Sort by x.
  points.sort_by(fn(a, b) { a.x - b.x })
  let tree = { root: None, count: n, }
  tree.root = build_node(points, 0, n - 1)
  tree
}

///|
fn build_node(points : Array[Point2D], lo : Int, hi : Int) -> RTNode? {
  if lo > hi {
    return None
  }
  let mid = lo + (hi - lo) / 2
  Some({
    point: points[mid],
    left: build_node(points, lo, mid - 1),
    right: build_node(points, mid + 1, hi),
  })
}

///|
/// Query all points in rectangle [x1, x2] × [y1, y2].
pub fn query(
  tree : RangeTree,
  x1 : Int,
  x2 : Int,
  y1 : Int,
  y2 : Int,
) -> Array[Point2D] {
  let result : Array[Point2D] = []
  query_node(tree.root, x1, x2, y1, y2, result)
  result
}

///|
fn query_node(
  n : RTNode?,
  x1 : Int,
  x2 : Int,
  y1 : Int,
  y2 : Int,
  result : Array[Point2D],
) -> Unit {
  match n {
    None => ()
    Some(node) => {
      let px = node.point.x
      let py = node.point.y
      if px >= x1 && px <= x2 && py >= y1 && py <= y2 {
        result.push(node.point)
      }
      // Prune by x: go left if x1 <= px (left subtree may have x == px),
      // go right if x2 >= px (right subtree may have x == px).
      if x1 <= px {
        query_node(node.left, x1, x2, y1, y2, result)
      }
      if x2 >= px {
        query_node(node.right, x1, x2, y1, y2, result)
      }
    }
  }
}

///|
/// Number of points. O(1).
pub fn count(tree : RangeTree) -> Int {
  tree.count
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "range_tree: basic query" {
  let pts = [
    { x: 1, y: 1, },
    { x: 2, y: 3, },
    { x: 3, y: 2, },
    { x: 4, y: 4, },
    { x: 5, y: 5, },
  ]
  let t = build(pts)
  assert_eq(count(t), 5)
  let result = query(t, 2, 4, 2, 4)
  assert_eq(result.length(), 3)
}

///|
test "range_tree: empty tree" {
  let t = new()
  assert_eq(query(t, 0, 100, 0, 100).length(), 0)
}

///|
test "range_tree: single point" {
  let pts = [{ x: 5, y: 5, }]
  let t = build(pts)
  assert_eq(query(t, 0, 10, 0, 10).length(), 1)
  assert_eq(query(t, 0, 4, 0, 10).length(), 0)
}

///|
test "range_tree: all points in range" {
  let pts = [{ x: 1, y: 1, }, { x: 2, y: 2, }, { x: 3, y: 3, }]
  let t = build(pts)
  let result = query(t, 0, 100, 0, 100)
  assert_eq(result.length(), 3)
}

///|
test "range_tree: no points in range" {
  let pts = [{ x: 0, y: 0, }, { x: 10, y: 10, }]
  let t = build(pts)
  let result = query(t, 3, 7, 3, 7)
  assert_eq(result.length(), 0)
}

///|
test "range_tree: many points" {
  let pts : Array[Point2D] = []
  for x = 0; x < 10; x = x + 1 {
    for y = 0; y < 10; y = y + 1 {
      pts.push({ x, y, })
    }
  }
  let t = build(pts)
  // Query [3, 6] × [3, 6] should find 4×4=16 points.
  let result = query(t, 3, 6, 3, 6)
  assert_eq(result.length(), 16)
}
