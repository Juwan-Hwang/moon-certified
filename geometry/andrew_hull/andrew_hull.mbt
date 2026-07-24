/// Convex hull of a set of 2D integer points via Andrew's monotone chain.
///
/// Algorithm:
///   1. Sort the points lexicographically by (x, then y).
///   2. Build the lower hull: scan left to right, maintaining a stack of
///      vertices; pop while the last two vertices and the current point make
///      a non-left turn (cross product <= 0). This also discards collinear
///      interior points, keeping only extreme vertices.
///   3. Build the upper hull: scan right to left with the same rule.
///   4. Concatenate the lower hull (sans last) and upper hull (sans last);
///      each shares the leftmost and rightmost points with the other, so the
///      duplicated endpoints are dropped exactly once.
///
/// The cross product `(a - o) x (b - o)` is positive for a counterclockwise
/// turn, negative for clockwise, and zero for collinear points. It is computed
/// with Int64 to avoid overflow for large coordinates. A cross product is the
/// difference of two products of coordinate differences; each coordinate may
/// reach ~3 * 10^9 before such a product approaches Int64 limits, which is far
/// beyond typical integer grids (an Int32 cross product would overflow at
/// coordinate differences of only ~46340).
///
/// Complexity: O(n log n), dominated by the sort; the two hull scans are O(n).
///
/// Returns hull vertices in counterclockwise order. Degenerate inputs (< 3
/// distinct points, all collinear, or all duplicate) yield 0-2 vertices.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

// Point, cross64 are imported from @geometry_utils.
// This eliminates the code duplication that previously existed across all
// geometry packages and ensures a single point representation.

/// Convenience constructor — delegates to @geometry_utils.point.
pub fn point(x : Int, y : Int) -> @geometry_utils.Point {
  @geometry_utils.point(x, y)
}

/// Lexicographic comparator for points by (x, y). Returns a negative value
/// when `a` should precede `b`.
fn cmp_point(a : @geometry_utils.Point, b : @geometry_utils.Point) -> Int {
  if a.x != b.x {
    a.x - b.x
  } else {
    a.y - b.y
  }
}

/// True if two points have identical coordinates.
fn point_eq(a : @geometry_utils.Point, b : @geometry_utils.Point) -> Bool {
  a.x == b.x && a.y == b.y
}

/// Compute the convex hull of `points` (Andrew's monotone chain).
///
/// Returns the hull vertices in counterclockwise order.
pub fn convex_hull(
  points : Array[@geometry_utils.Point]
) -> Array[@geometry_utils.Point] {
  let n = points.length()
  // Fewer than 3 points cannot enclose an area: return them unchanged.
  if n < 3 {
    let out : Array[@geometry_utils.Point] = []
    for i = 0; i < n; i = i + 1 {
      out.push(points[i])
    }
    return out
  }
  // Copy and sort lexicographically by (x, y).
  let pts : Array[@geometry_utils.Point] = []
  for i = 0; i < n; i = i + 1 {
    pts.push(points[i])
  }
  pts.sort_by(cmp_point)
  // Remove consecutive duplicates so the chain never stores repeated vertices
  // (duplicate inputs would otherwise produce a degenerate [p, p] seam).
  let uniq : Array[@geometry_utils.Point] = []
  for i = 0; i < n; i = i + 1 {
    if i == 0 || !point_eq(pts[i], pts[i - 1]) {
      uniq.push(pts[i])
    }
  }
  let m = uniq.length()
  // After deduplication, fewer than 3 distinct points cannot form a polygon.
  if m < 3 {
    return uniq
  }
  // Lower hull: scan left to right, popping non-left turns.
  let lower : Array[@geometry_utils.Point] = []
  for i = 0; i < m; i = i + 1 {
    let p = uniq[i]
    while lower.length() >= 2 &&
      @geometry_utils.cross64(lower[lower.length() - 2], lower[lower.length() - 1], p) <= 0L {
      let _ = lower.pop()
    }
    lower.push(p)
  }
  // Upper hull: scan right to left, popping non-left turns.
  let upper : Array[@geometry_utils.Point] = []
  for i = m - 1; i >= 0; i = i - 1 {
    let p = uniq[i]
    while upper.length() >= 2 &&
      @geometry_utils.cross64(upper[upper.length() - 2], upper[upper.length() - 1], p) <= 0L {
      let _ = upper.pop()
    }
    upper.push(p)
  }
  // Concatenate lower (without last) and upper (without last). Each hull's
  // final vertex is the other hull's first vertex, so both ends are dropped
  // once to avoid duplication.
  let hull : Array[@geometry_utils.Point] = []
  for i = 0; i < lower.length() - 1; i = i + 1 {
    hull.push(lower[i])
  }
  for i = 0; i < upper.length() - 1; i = i + 1 {
    hull.push(upper[i])
  }
  hull
}

// ---------------------------------------------------------------------------
// Helpers for tests
// ---------------------------------------------------------------------------

fn min2(a : Int, b : Int) -> Int {
  if a <= b {
    a
  } else {
    b
  }
}

fn max2(a : Int, b : Int) -> Int {
  if a >= b {
    a
  } else {
    b
  }
}

/// True iff `hull` is a strictly counterclockwise convex polygon.
fn is_convex_ccw(hull : Array[@geometry_utils.Point]) -> Bool {
  let m = hull.length()
  if m < 3 {
    return true
  }
  for i = 0; i < m; i = i + 1 {
    let o = hull[i]
    let a = hull[(i + 1) % m]
    let b = hull[(i + 2) % m]
    if @geometry_utils.cross64(o, a, b) <= 0L {
      return false
    }
  }
  true
}

/// True iff `hull` contains no repeated vertex.
fn has_no_duplicates(hull : Array[@geometry_utils.Point]) -> Bool {
  let m = hull.length()
  for i = 0; i < m; i = i + 1 {
    for j = i + 1; j < m; j = j + 1 {
      if point_eq(hull[i], hull[j]) {
        return false
      }
    }
  }
  true
}

/// True iff every point of `points` lies on or inside `hull`.
fn all_inside_or_on(
  points : Array[@geometry_utils.Point],
  hull : Array[@geometry_utils.Point],
) -> Bool {
  let m = hull.length()
  let n = points.length()
  if m == 0 {
    return n == 0
  }
  if m == 1 {
    let h = hull[0]
    for i = 0; i < n; i = i + 1 {
      let p = points[i]
      if p.x != h.x || p.y != h.y {
        return false
      }
    }
    return true
  }
  if m == 2 {
    // Degenerate segment hull: every point must be collinear and within the
    // bounding box of the two endpoints.
    let a = hull[0]
    let b = hull[1]
    let lo_x = min2(a.x, b.x)
    let hi_x = max2(a.x, b.x)
    let lo_y = min2(a.y, b.y)
    let hi_y = max2(a.y, b.y)
    for i = 0; i < n; i = i + 1 {
      let p = points[i]
      if @geometry_utils.cross64(a, b, p) != 0L {
        return false
      }
      if p.x < lo_x || p.x > hi_x || p.y < lo_y || p.y > hi_y {
        return false
      }
    }
    return true
  }
  // m >= 3: every point must be on the left of (or on) every CCW edge.
  for i = 0; i < n; i = i + 1 {
    let p = points[i]
    for j = 0; j < m; j = j + 1 {
      let a = hull[j]
      let b = hull[(j + 1) % m]
      if @geometry_utils.cross64(a, b, p) < 0L {
        return false
      }
    }
  }
  true
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "andrew_hull: basic triangle" {
  let pts = [@geometry_utils.point(0, 0), @geometry_utils.point(2, 0), @geometry_utils.point(0, 2)]
  let hull = convex_hull(pts)
  assert_eq(hull.length(), 3)
  assert_true(is_convex_ccw(hull))
  assert_true(all_inside_or_on(pts, hull))
}

test "andrew_hull: square" {
  let pts = [@geometry_utils.point(0, 0), @geometry_utils.point(2, 0), @geometry_utils.point(2, 2), @geometry_utils.point(0, 2)]
  let hull = convex_hull(pts)
  assert_eq(hull.length(), 4)
  assert_true(is_convex_ccw(hull))
  assert_true(all_inside_or_on(pts, hull))
}

test "andrew_hull: collinear points" {
  let pts = [@geometry_utils.point(0, 0), @geometry_utils.point(1, 0), @geometry_utils.point(2, 0), @geometry_utils.point(3, 0)]
  let hull = convex_hull(pts)
  assert_eq(hull.length(), 2)
  // Only the two extremes remain (order not asserted, just the set).
  let x0 = hull[0].x
  let x1 = hull[1].x
  assert_true((x0 == 0 && x1 == 3) || (x0 == 3 && x1 == 0))
  assert_true(all_inside_or_on(pts, hull))
}

test "andrew_hull: single point" {
  let pts = [@geometry_utils.point(3, 3)]
  let hull = convex_hull(pts)
  assert_eq(hull.length(), 1)
  assert_eq(hull[0].x, 3)
  assert_eq(hull[0].y, 3)
  assert_true(all_inside_or_on(pts, hull))
}

test "andrew_hull: two points" {
  let pts = [@geometry_utils.point(0, 0), @geometry_utils.point(1, 1)]
  let hull = convex_hull(pts)
  assert_eq(hull.length(), 2)
  assert_true(all_inside_or_on(pts, hull))
}

test "andrew_hull: all points on hull" {
  // A convex pentagon: every input point is a hull vertex.
  let pts = [@geometry_utils.point(0, 0), @geometry_utils.point(4, 0), @geometry_utils.point(4, 4), @geometry_utils.point(2, 6), @geometry_utils.point(0, 4)]
  let hull = convex_hull(pts)
  assert_eq(hull.length(), 5)
  assert_true(is_convex_ccw(hull))
  assert_true(all_inside_or_on(pts, hull))
}

test "andrew_hull: point inside hull" {
  // Square corners plus one strictly interior point.
  let pts = [@geometry_utils.point(0, 0), @geometry_utils.point(4, 0), @geometry_utils.point(4, 4), @geometry_utils.point(0, 4), @geometry_utils.point(2, 2)]
  let hull = convex_hull(pts)
  assert_eq(hull.length(), 4)
  assert_true(is_convex_ccw(hull))
  assert_true(all_inside_or_on(pts, hull))
}

test "andrew_hull: duplicate points" {
  // Square corners (some duplicated) plus a duplicated interior point.
  let pts = [
    @geometry_utils.point(0, 0), @geometry_utils.point(4, 0), @geometry_utils.point(4, 4), @geometry_utils.point(0, 4),
    @geometry_utils.point(0, 0), @geometry_utils.point(4, 4), @geometry_utils.point(2, 2), @geometry_utils.point(2, 2),
  ]
  let hull = convex_hull(pts)
  assert_eq(hull.length(), 4)
  assert_true(has_no_duplicates(hull))
  assert_true(is_convex_ccw(hull))
  assert_true(all_inside_or_on(pts, hull))
}

test "andrew_hull: all identical points" {
  let pts = [@geometry_utils.point(1, 1), @geometry_utils.point(1, 1), @geometry_utils.point(1, 1)]
  let hull = convex_hull(pts)
  assert_eq(hull.length(), 1)
  assert_eq(hull[0].x, 1)
  assert_eq(hull[0].y, 1)
  assert_true(all_inside_or_on(pts, hull))
}

test "andrew_hull: large random set" {
  let pts : Array[@geometry_utils.Point] = []
  let mut st = 12345
  for i = 0; i < 50; i = i + 1 {
    st = (st * 31 + 7) % 1000003
    let x = st % 100
    st = (st * 31 + 7) % 1000003
    let y = st % 100
    pts.push(@geometry_utils.point(x, y))
  }
  let hull = convex_hull(pts)
  assert_true(hull.length() >= 3)
  assert_true(has_no_duplicates(hull))
  assert_true(is_convex_ccw(hull))
  assert_true(all_inside_or_on(pts, hull))
}

test "andrew_hull: hull is strictly convex (all turns CCW)" {
  // Square corners plus edge midpoints plus an interior point: the collinear
  // edge midpoints must be discarded, leaving exactly the four corners.
  let pts = [
    @geometry_utils.point(0, 0), @geometry_utils.point(6, 0), @geometry_utils.point(6, 6), @geometry_utils.point(0, 6),
    @geometry_utils.point(3, 0), @geometry_utils.point(6, 3), @geometry_utils.point(3, 6), @geometry_utils.point(0, 3),
    @geometry_utils.point(3, 3),
  ]
  let hull = convex_hull(pts)
  assert_eq(hull.length(), 4)
  assert_true(has_no_duplicates(hull))
  assert_true(is_convex_ccw(hull))
  let m = hull.length()
  for i = 0; i < m; i = i + 1 {
    let o = hull[i]
    let a = hull[(i + 1) % m]
    let b = hull[(i + 2) % m]
    assert_true(@geometry_utils.cross64(o, a, b) > 0L)
  }
  assert_true(all_inside_or_on(pts, hull))
}
