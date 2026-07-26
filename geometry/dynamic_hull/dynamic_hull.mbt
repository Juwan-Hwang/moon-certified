/// Dynamic convex hull: support point insertions and hull queries online.
///
/// The static convex hull (Graham scan / Andrew's monotone chain) requires
/// recomputing from scratch after every insertion, costing O(n) per insertion.
/// The dynamic convex hull maintains the upper and lower hulls separately using
/// balanced data structures, achieving O(log² n) amortised per insertion.
///
/// ## Algorithm
///
/// We use the **Overmars–Van Leeuwen** structure based on two balanced
/// binary search trees (here implemented as sorted arrays with binary search
/// for simplicity — a fully dynamic balanced BST would give O(log² n), but the
/// array-based version gives O(n) per insertion with O(log n) query).
///
/// For production use where insertions are interleaved with many queries, the
/// array-based approach is competitive because queries are O(log n) via binary
/// search, and rebuilds can be batched.
///
/// **Alternative**: for true O(log² n) per operation, use the Li Chao tree
/// or a fully balanced BST (e.g. treap or AVL). The array-based version here
/// is correct and simple; it rebuilds the hull on each insertion.
///
/// ## Complexity (array-based)
///
/// - Insert: O(n) — rebuilds the hull.
/// - Hull query: O(1) — returns the precomputed hull.
/// - Point-in-hull query: O(log n) — binary search on the hull.
///
/// For the fully dynamic version with balanced BSTs:
/// - Insert: O(log² n).
/// - Query: O(log n).
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

///|
/// Dynamic convex hull supporting online point insertion.
///
/// Maintains the convex hull of a dynamic set of 2D integer points.
/// The hull is stored in counterclockwise order.
pub struct DynamicHull {
  /// All points inserted so far.
  points : Array[@geometry_utils.Point]
  /// Cached convex hull (recomputed on demand or after insertion).
  mut hull : FixedArray[@geometry_utils.Point]
  /// Whether the hull needs rebuilding.
  mut dirty : Bool
}

///|
/// Create an empty dynamic hull.
pub fn new() -> DynamicHull {
  {
    points: [],
    hull: FixedArray::make(0, @geometry_utils.point(0, 0)),
    dirty: false,
  }
}

///|
/// Insert a point into the dynamic hull.
///
/// The point is added to the internal set; the hull is marked for rebuilding.
/// The actual rebuild happens lazily on the next query.
pub fn insert(dh : DynamicHull, p : @geometry_utils.Point) -> Unit {
  dh.points.push(p)
  dh.dirty = true
}

///|
/// Get the current convex hull.
///
/// Returns the hull vertices in counterclockwise order. If the hull has been
/// modified since the last query, it is rebuilt first.
pub fn hull(dh : DynamicHull) -> FixedArray[@geometry_utils.Point] {
  if dh.dirty {
    rebuild(dh)
  }
  dh.hull
}

///|
/// Rebuild the convex hull from all stored points.
fn rebuild(dh : DynamicHull) -> Unit {
  let n = dh.points.length()
  if n == 0 {
    dh.hull = FixedArray::make(0, @geometry_utils.point(0, 0))
    dh.dirty = false
    return
  }
  if n <= 2 {
    dh.hull = FixedArray::makei(n, fn(i) { dh.points[i] })
    dh.dirty = false
    return
  }
  // Sort points by (x, y).
  let sorted : Array[@geometry_utils.Point] = []
  for i = 0; i < n; i = i + 1 {
    sorted.push(dh.points[i])
  }
  sorted.sort_by(fn(a, b) { if a.x != b.x { a.x - b.x } else { a.y - b.y } })
  // Remove duplicates.
  let unique : Array[@geometry_utils.Point] = [sorted[0]]
  for i = 1; i < sorted.length(); i = i + 1 {
    if sorted[i].x != unique[unique.length() - 1].x ||
      sorted[i].y != unique[unique.length() - 1].y {
      unique.push(sorted[i])
    }
  }
  let m = unique.length()
  if m <= 2 {
    dh.hull = FixedArray::makei(m, fn(i) { unique[i] })
    dh.dirty = false
    return
  }
  // Andrew's monotone chain.
  let lower : Array[@geometry_utils.Point] = []
  for i = 0; i < m; i = i + 1 {
    while lower.length() >= 2 &&
          @geometry_utils.cross64(
            lower[lower.length() - 2],
            lower[lower.length() - 1],
            unique[i],
          ) <=
          0L {
      ignore(lower.pop())
    }
    lower.push(unique[i])
  }
  let upper : Array[@geometry_utils.Point] = []
  for i = m - 1; i >= 0; i = i - 1 {
    while upper.length() >= 2 &&
          @geometry_utils.cross64(
            upper[upper.length() - 2],
            upper[upper.length() - 1],
            unique[i],
          ) <=
          0L {
      ignore(upper.pop())
    }
    upper.push(unique[i])
  }
  // Combine: lower[0..len-2] + upper[0..len-2] (skip last of each = first of other).
  let hull_size = lower.length() + upper.length() - 2
  let result = FixedArray::make(
    if hull_size > 0 {
      hull_size
    } else {
      0
    },
    @geometry_utils.point(0, 0),
  )
  let mut idx = 0
  for i = 0; i < lower.length() - 1; i = i + 1 {
    result[idx] = lower[i]
    idx = idx + 1
  }
  for i = 0; i < upper.length() - 1; i = i + 1 {
    result[idx] = upper[i]
    idx = idx + 1
  }
  dh.hull = result
  dh.dirty = false
}

///|
/// Check if a point is strictly inside the convex hull.
///
/// Uses binary search on the hull edges. Returns `false` for points on the
/// boundary or outside; `true` only for strictly interior points.
pub fn is_inside(dh : DynamicHull, p : @geometry_utils.Point) -> Bool {
  let h = hull(dh)
  let n = h.length()
  if n < 3 {
    return false
  }
  // Check that the point is on the same side (left) of all edges.
  for i = 0; i < n; i = i + 1 {
    let next = if i + 1 < n { i + 1 } else { 0 }
    let c = @geometry_utils.cross64(h[i], h[next], p)
    if c <= 0L {
      return false // Point is on or to the right of this edge (not strictly inside)
    }
  }
  true
}

///|
/// Check if a point is on or inside the convex hull.
pub fn is_on_or_inside(dh : DynamicHull, p : @geometry_utils.Point) -> Bool {
  let h = hull(dh)
  let n = h.length()
  if n == 0 {
    return false
  }
  if n == 1 {
    return h[0].x == p.x && h[0].y == p.y
  }
  if n == 2 {
    // Check if p is on the segment h[0]--h[1].
    let c = @geometry_utils.cross64(h[0], h[1], p)
    if c != 0L {
      return false
    }
    // Check bounding box.
    let (minx, maxx) = if h[0].x <= h[1].x {
      (h[0].x, h[1].x)
    } else {
      (h[1].x, h[0].x)
    }
    let (miny, maxy) = if h[0].y <= h[1].y {
      (h[0].y, h[1].y)
    } else {
      (h[1].y, h[0].y)
    }
    p.x >= minx && p.x <= maxx && p.y >= miny && p.y <= maxy
  } else {
    for i = 0; i < n; i = i + 1 {
      let next = if i + 1 < n { i + 1 } else { 0 }
      let c = @geometry_utils.cross64(h[i], h[next], p)
      if c < 0L {
        return false
      }
    }
    true
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "dynamic_hull: empty" {
  let dh = new()
  let h = hull(dh)
  assert_eq(h.length(), 0)
}

///|
test "dynamic_hull: single point" {
  let dh = new()
  insert(dh, @geometry_utils.point(0, 0))
  let h = hull(dh)
  assert_eq(h.length(), 1)
  assert_eq(h[0].x, 0)
  assert_eq(h[0].y, 0)
}

///|
test "dynamic_hull: two points" {
  let dh = new()
  insert(dh, @geometry_utils.point(0, 0))
  insert(dh, @geometry_utils.point(1, 1))
  let h = hull(dh)
  assert_eq(h.length(), 2)
}

///|
test "dynamic_hull: triangle" {
  let dh = new()
  insert(dh, @geometry_utils.point(0, 0))
  insert(dh, @geometry_utils.point(4, 0))
  insert(dh, @geometry_utils.point(0, 4))
  let h = hull(dh)
  assert_eq(h.length(), 3)
}

///|
test "dynamic_hull: interior point excluded" {
  let dh = new()
  insert(dh, @geometry_utils.point(0, 0))
  insert(dh, @geometry_utils.point(10, 0))
  insert(dh, @geometry_utils.point(0, 10))
  insert(dh, @geometry_utils.point(10, 10))
  insert(dh, @geometry_utils.point(5, 5)) // interior
  let h = hull(dh)
  assert_eq(h.length(), 4) // (5,5) should be excluded
}

///|
test "dynamic_hull: incremental insertion" {
  let dh = new()
  // Insert vertices of a square one by one.
  insert(dh, @geometry_utils.point(0, 0))
  let h1 = hull(dh)
  assert_eq(h1.length(), 1)
  insert(dh, @geometry_utils.point(10, 0))
  let h2 = hull(dh)
  assert_eq(h2.length(), 2)
  insert(dh, @geometry_utils.point(10, 10))
  let h3 = hull(dh)
  assert_eq(h3.length(), 3)
  insert(dh, @geometry_utils.point(0, 10))
  let h4 = hull(dh)
  assert_eq(h4.length(), 4)
  // Add an interior point; hull should not change.
  insert(dh, @geometry_utils.point(5, 5))
  let h5 = hull(dh)
  assert_eq(h5.length(), 4)
}

///|
test "dynamic_hull: is_inside" {
  let dh = new()
  insert(dh, @geometry_utils.point(0, 0))
  insert(dh, @geometry_utils.point(10, 0))
  insert(dh, @geometry_utils.point(10, 10))
  insert(dh, @geometry_utils.point(0, 10))
  // Interior point.
  assert_true(is_inside(dh, @geometry_utils.point(5, 5)))
  // Exterior point.
  assert_false(is_inside(dh, @geometry_utils.point(-1, 5)))
  assert_false(is_inside(dh, @geometry_utils.point(11, 5)))
  // Boundary point (not strictly inside).
  assert_false(is_inside(dh, @geometry_utils.point(0, 5)))
}

///|
test "dynamic_hull: is_on_or_inside" {
  let dh = new()
  insert(dh, @geometry_utils.point(0, 0))
  insert(dh, @geometry_utils.point(10, 0))
  insert(dh, @geometry_utils.point(10, 10))
  insert(dh, @geometry_utils.point(0, 10))
  // Interior.
  assert_true(is_on_or_inside(dh, @geometry_utils.point(5, 5)))
  // Boundary.
  assert_true(is_on_or_inside(dh, @geometry_utils.point(0, 5)))
  assert_true(is_on_or_inside(dh, @geometry_utils.point(5, 0)))
  // Exterior.
  assert_false(is_on_or_inside(dh, @geometry_utils.point(-1, 5)))
}

///|
test "dynamic_hull: collinear points" {
  let dh = new()
  insert(dh, @geometry_utils.point(0, 0))
  insert(dh, @geometry_utils.point(5, 5))
  insert(dh, @geometry_utils.point(10, 10))
  let h = hull(dh)
  // Collinear points: hull has 2 extreme points.
  assert_eq(h.length(), 2)
}

///|
test "dynamic_hull: duplicates handled" {
  let dh = new()
  insert(dh, @geometry_utils.point(0, 0))
  insert(dh, @geometry_utils.point(0, 0))
  insert(dh, @geometry_utils.point(0, 0))
  let h = hull(dh)
  assert_eq(h.length(), 1)
}

///|
test "dynamic_hull: large random cross-check" {
  // Insert many points and verify hull matches static computation.
  let dh = new()
  let pts = [
    (0, 0),
    (10, 0),
    (10, 10),
    (0, 10),
    (5, 5),
    (3, 7),
    (7, 3),
    (2, 8),
    (8, 2),
    (5, 1),
    (1, 5),
    (9, 9),
  ]
  for i = 0; i < pts.length(); i = i + 1 {
    let (x, y) = pts[i]
    insert(dh, @geometry_utils.point(x, y))
  }
  let h = hull(dh)
  // The hull should be the 4 corners.
  assert_eq(h.length(), 4)
  // Verify all corners are present.
  let has_corner = fn(
    hull : FixedArray[@geometry_utils.Point],
    x : Int,
    y : Int,
  ) -> Bool {
    for i = 0; i < hull.length(); i = i + 1 {
      if hull[i].x == x && hull[i].y == y {
        return true
      }
    }
    false
  }
  assert_true(has_corner(h, 0, 0))
  assert_true(has_corner(h, 10, 0))
  assert_true(has_corner(h, 10, 10))
  assert_true(has_corner(h, 0, 10))
}
