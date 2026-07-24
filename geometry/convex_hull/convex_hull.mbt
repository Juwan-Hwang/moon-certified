/// Convex hull of a set of 2D integer points via the Graham scan.
///
/// 1. Pick the pivot: the lowest-y point (ties broken by lowest x). Because
///    every other point has y >= pivot.y, no point lies on the ray "behind"
///    the pivot, which avoids the classic opposite-ray collinearity pitfall.
/// 2. Sort the points by polar angle around the pivot (counterclockwise);
///    points on the same ray are ordered by distance, nearest first.
/// 3. Scan left to right, maintaining a stack of hull candidates. For each
///    point, pop while the top two stack points and the new point make a
///    non-left turn (cross product <= 0); this also discards collinear
///    interior points, keeping only the extreme vertices. A final
///    wrap-around cleanup removes a collinear tail touching the first vertex.
///
/// The cross product `(a-o) x (b-o)` is positive for a counterclockwise turn,
/// negative for clockwise, and zero for collinear points.
///
/// Returns hull vertices in counterclockwise order. Degenerate inputs yield
/// 0-2 points; non-degenerate inputs (>= 3 non-collinear points) yield >= 3.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

// Point, point, cross, and dist2 are imported from @geometry_utils.
// This eliminates the code duplication that previously existed across all
// geometry packages. The single source of truth is geometry_utils.mbt.

/// Convenience constructor — delegates to @geometry_utils.point.
pub fn point(x : Int, y : Int) -> @geometry_utils.Point {
  @geometry_utils.point(x, y)
}

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

/// Comparator: ascending polar angle (CCW) around `pivot`; collinear points
/// are ordered by distance, nearest first. Returns a negative value when `a`
/// should precede `b`.
fn cmp_point(pivot : @geometry_utils.Point, a : @geometry_utils.Point, b : @geometry_utils.Point) -> Int {
  let c = @geometry_utils.cross(pivot, a, b)
  if c != 0 {
    -c
  } else {
    // Collinear: nearer first. dist2 returns Int64 to avoid overflow.
    let da = @geometry_utils.dist2(pivot, a)
    let db = @geometry_utils.dist2(pivot, b)
    if da < db {
      -1
    } else if da > db {
      1
    } else {
      0
    }
  }
}

/// Stable merge sort of `pts[lo, hi)` by comparator `cmp`, using `tmp` as
/// scratch space. Sorts in place.
fn msort_point(
  pts : FixedArray[@geometry_utils.Point],
  tmp : FixedArray[@geometry_utils.Point],
  lo : Int,
  hi : Int,
  cmp : (@geometry_utils.Point, @geometry_utils.Point) -> Int,
) -> Unit {
  let len = hi - lo
  if len <= 1 {
    return
  }
  let mid = lo + len / 2
  msort_point(pts, tmp, lo, mid, cmp)
  msort_point(pts, tmp, mid, hi, cmp)
  let mut i = lo
  let mut j = mid
  for k = lo; k < hi; k = k + 1 {
    if j >= hi || (i < mid && cmp(pts[i], pts[j]) <= 0) {
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

/// Compute the convex hull of `points` (Graham scan).
///
/// Returns the hull vertices in counterclockwise order.
pub fn convex_hull(points : Array[@geometry_utils.Point]) -> Array[@geometry_utils.Point] {
  let n = points.length()
  if n == 0 {
    return []
  }
  if n == 1 {
    return [points[0]]
  }
  // Mutable FixedArray copy so we can sort in place.
  let pts : FixedArray[@geometry_utils.Point] = FixedArray::makei(n, fn(i) { points[i] })
  // Pivot: lowest y, then lowest x.
  let mut pivot_idx = 0
  for i = 1; i < n; i = i + 1 {
    let pi = pts[pivot_idx]
    let ci = pts[i]
    if ci.y < pi.y || (ci.y == pi.y && ci.x < pi.x) {
      pivot_idx = i
    }
  }
  let pivot = pts[pivot_idx]
  let cmp = fn(a : @geometry_utils.Point, b : @geometry_utils.Point) -> Int {
    cmp_point(pivot, a, b)
  }
  let tmp : FixedArray[@geometry_utils.Point] = FixedArray::make(n, pivot)
  msort_point(pts, tmp, 0, n, cmp)
  // Deduplicate: remove consecutive identical points. Three identical points
  // would otherwise survive the Graham scan (cross == 0 is popped, but the
  // new point is still pushed), yielding duplicate hull vertices.
  let dedup : FixedArray[@geometry_utils.Point] = FixedArray::make(n, pivot)
  dedup[0] = pts[0]
  let mut dn = 1
  for i = 1; i < n; i = i + 1 {
    if pts[i].x != dedup[dn - 1].x || pts[i].y != dedup[dn - 1].y {
      dedup[dn] = pts[i]
      dn = dn + 1
    }
  }
  // Graham scan with an explicit stack (FixedArray + size counter).
  let stack : FixedArray[@geometry_utils.Point] = FixedArray::make(dn, pivot)
  let mut size = 0
  for i = 0; i < dn; i = i + 1 {
    let p = dedup[i]
    while size >= 2 && @geometry_utils.cross(stack[size - 2], stack[size - 1], p) <= 0 {
      size = size - 1
    }
    stack[size] = p
    size = size + 1
  }
  // Wrap-around cleanup: drop a collinear tail touching the first vertex.
  while size >= 3 && @geometry_utils.cross(stack[size - 2], stack[size - 1], stack[0]) <= 0 {
    size = size - 1
  }
  let result : Array[@geometry_utils.Point] = []
  for i = 0; i < size; i = i + 1 {
    result.push(stack[i])
  }
  result
}

// ---------------------------------------------------------------------------
// Helpers for tests
// ---------------------------------------------------------------------------

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
    if @geometry_utils.cross(o, a, b) <= 0 {
      return false
    }
  }
  true
}

/// True iff every point of `points` lies on or inside `hull`.
fn all_inside_or_on(points : Array[@geometry_utils.Point], hull : Array[@geometry_utils.Point]) -> Bool {
  let m = hull.length()
  if m == 0 {
    return points.length() == 0
  }
  if m == 1 {
    let h = hull[0]
    for i = 0; i < points.length(); i = i + 1 {
      let p = points[i]
      if p.x != h.x || p.y != h.y {
        return false
      }
    }
    return true
  }
  if m == 2 {
    let a = hull[0]
    let b = hull[1]
    let lo_x = min2(a.x, b.x)
    let hi_x = max2(a.x, b.x)
    let lo_y = min2(a.y, b.y)
    let hi_y = max2(a.y, b.y)
    for i = 0; i < points.length(); i = i + 1 {
      let p = points[i]
      if @geometry_utils.cross(a, b, p) != 0 {
        return false
      }
      if p.x < lo_x || p.x > hi_x || p.y < lo_y || p.y > hi_y {
        return false
      }
    }
    return true
  }
  // m >= 3: every point must be on the left of (or on) every CCW edge.
  for i = 0; i < points.length(); i = i + 1 {
    let p = points[i]
    for j = 0; j < m; j = j + 1 {
      let a = hull[j]
      let b = hull[(j + 1) % m]
      if @geometry_utils.cross(a, b, p) < 0 {
        return false
      }
    }
  }
  true
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "convex_hull: triangle" {
  let pts : Array[@geometry_utils.Point] = [@geometry_utils.point(0, 0), @geometry_utils.point(2, 0), @geometry_utils.point(0, 2)]
  let hull = convex_hull(pts)
  assert_eq(hull.length(), 3)
  assert_true(is_convex_ccw(hull))
  assert_true(all_inside_or_on(pts, hull))
}

test "convex_hull: square" {
  let pts : Array[@geometry_utils.Point] = [
    @geometry_utils.point(0, 0), @geometry_utils.point(2, 0), @geometry_utils.point(2, 2), @geometry_utils.point(0, 2),
  ]
  let hull = convex_hull(pts)
  assert_eq(hull.length(), 4)
  assert_true(is_convex_ccw(hull))
  assert_true(all_inside_or_on(pts, hull))
}

test "convex_hull: collinear points" {
  let pts : Array[@geometry_utils.Point] = [
    @geometry_utils.point(0, 0), @geometry_utils.point(1, 0), @geometry_utils.point(2, 0), @geometry_utils.point(3, 0),
  ]
  let hull = convex_hull(pts)
  assert_eq(hull.length(), 2)
  // Extremes only (order is not asserted, just the set).
  let x0 = hull[0].x
  let x1 = hull[1].x
  assert_true((x0 == 0 && x1 == 3) || (x0 == 3 && x1 == 0))
  assert_true(all_inside_or_on(pts, hull))
}

test "convex_hull: single point" {
  let pts : Array[@geometry_utils.Point] = [@geometry_utils.point(3, 3)]
  let hull = convex_hull(pts)
  assert_eq(hull.length(), 1)
  assert_eq(hull[0].x, 3)
  assert_eq(hull[0].y, 3)
}

test "convex_hull: three identical points" {
  // All three points are the same — the hull should be a single point, not
  // two duplicate points.
  let pts : Array[@geometry_utils.Point] = [
    @geometry_utils.point(5, 5), @geometry_utils.point(5, 5), @geometry_utils.point(5, 5),
  ]
  let hull = convex_hull(pts)
  assert_eq(hull.length(), 1)
  assert_eq(hull[0].x, 5)
  assert_eq(hull[0].y, 5)
}

test "convex_hull: duplicate points among distinct ones" {
  // Mix of duplicates and distinct points.
  let pts : Array[@geometry_utils.Point] = [
    @geometry_utils.point(0, 0), @geometry_utils.point(0, 0),
    @geometry_utils.point(4, 0), @geometry_utils.point(0, 4),
    @geometry_utils.point(4, 0),
  ]
  let hull = convex_hull(pts)
  assert_eq(hull.length(), 3)
  assert_true(is_convex_ccw(hull))
  assert_true(all_inside_or_on(pts, hull))
}

test "convex_hull: two points" {
  let pts : Array[@geometry_utils.Point] = [@geometry_utils.point(0, 0), @geometry_utils.point(1, 1)]
  let hull = convex_hull(pts)
  assert_eq(hull.length(), 2)
  assert_true(all_inside_or_on(pts, hull))
}

test "convex_hull: convex polygon with interior point" {
  let pts : Array[@geometry_utils.Point] = [
    @geometry_utils.point(0, 0), @geometry_utils.point(4, 0), @geometry_utils.point(5, 2), @geometry_utils.point(2, 4), @geometry_utils.point(0, 3),
    @geometry_utils.point(2, 2), // interior
  ]
  let hull = convex_hull(pts)
  assert_eq(hull.length(), 5)
  assert_true(is_convex_ccw(hull))
  assert_true(all_inside_or_on(pts, hull))
}

test "convex_hull: square with center removed" {
  let pts : Array[@geometry_utils.Point] = [
    @geometry_utils.point(0, 0), @geometry_utils.point(4, 0), @geometry_utils.point(4, 4), @geometry_utils.point(0, 4), @geometry_utils.point(2, 2),
  ]
  let hull = convex_hull(pts)
  assert_eq(hull.length(), 4)
  assert_true(is_convex_ccw(hull))
  assert_true(all_inside_or_on(pts, hull))
}

test "convex_hull: random 50 points" {
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
  assert_true(is_convex_ccw(hull))
  assert_true(all_inside_or_on(pts, hull))
}

test "convex_hull: hull is strictly convex (all turns CCW)" {
  // Square corners plus edge midpoints plus an interior point.
  let pts : Array[@geometry_utils.Point] = [
    @geometry_utils.point(0, 0), @geometry_utils.point(6, 0), @geometry_utils.point(6, 6), @geometry_utils.point(0, 6),
    @geometry_utils.point(3, 0), @geometry_utils.point(6, 3), @geometry_utils.point(3, 6), @geometry_utils.point(0, 3), // edge midpoints
    @geometry_utils.point(3, 3), // interior
  ]
  let hull = convex_hull(pts)
  assert_eq(hull.length(), 4)
  assert_true(is_convex_ccw(hull))
  // Every consecutive triple must be a strictly left turn.
  let m = hull.length()
  for i = 0; i < m; i = i + 1 {
    let o = hull[i]
    let a = hull[(i + 1) % m]
    let b = hull[(i + 2) % m]
    assert_true(@geometry_utils.cross(o, a, b) > 0)
  }
  assert_true(all_inside_or_on(pts, hull))
}
