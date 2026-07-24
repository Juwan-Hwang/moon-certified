/// Segment Operations: intersection tests and point-in-polygon.
///
/// Uses exact-integer orientation tests (cross products) to avoid
/// floating-point precision issues. All coordinates are `Int`.
///
/// Algorithms:
/// - `segments_intersect`: O(1) orientation-based test.
/// - `point_in_polygon`: O(n) ray-casting with even-odd rule.
/// - `point_on_segment`: O(1) orientation + bounding-box test.
/// - `polygon_area`: O(n) shoelace formula, exact for integer coordinates.
/// - `polygon_is_convex`: O(n) orientation check.
///
/// Limitations:
/// - All coordinates are `Int`; cross products use `Int64` to prevent overflow
///   for coordinates up to ~46340 (sqrt of Int32 max).
/// - The ray-casting algorithm counts boundary points as either inside or
///   outside depending on edge alignment (standard even-odd behaviour).

// @geometry_utils.Point and point are imported from @geometry_utils.
// This eliminates code duplication across geometry packages.

/// A line segment from `p` to `q`.
pub struct Segment {
  p : @geometry_utils.Point
  q : @geometry_utils.Point
}

/// Convenience constructor — delegates to @geometry_utils.point.
pub fn point(x : Int, y : Int) -> @geometry_utils.Point {
  @geometry_utils.point(x, y)
}

/// Construct a segment.
pub fn segment(p : @geometry_utils.Point, q : @geometry_utils.Point) -> Segment {
  { p, q }
}

/// Orientation of the triplet (O, A, B):
/// - `1`  = counterclockwise (left turn)
/// - `-1` = clockwise (right turn)
/// - `0`  = collinear
fn orientation(o : @geometry_utils.Point, a : @geometry_utils.Point, b : @geometry_utils.Point) -> Int {
  let c = @geometry_utils.cross64(o, a, b)
  if c > 0L { 1 } else if c < 0L { -1 } else { 0 }
}

/// Check if point `p` lies on segment `s` (assuming collinearity).
/// Tests bounding box containment.
fn on_segment_collinear(p : @geometry_utils.Point, s : Segment) -> Bool {
  let min_x = if s.p.x <= s.q.x { s.p.x } else { s.q.x }
  let max_x = if s.p.x >= s.q.x { s.p.x } else { s.q.x }
  let min_y = if s.p.y <= s.q.y { s.p.y } else { s.q.y }
  let max_y = if s.p.y >= s.q.y { s.p.y } else { s.q.y }
  p.x >= min_x && p.x <= max_x && p.y >= min_y && p.y <= max_y
}

/// Check if two line segments intersect (including endpoints and overlaps).
///
/// Returns `true` if the segments share any point. O(1) time.
pub fn segments_intersect(s1 : Segment, s2 : Segment) -> Bool {
  let o1 = orientation(s1.p, s1.q, s2.p)
  let o2 = orientation(s1.p, s1.q, s2.q)
  let o3 = orientation(s2.p, s2.q, s1.p)
  let o4 = orientation(s2.p, s2.q, s1.q)
  // General case: segments straddle each other
  if o1 != o2 && o3 != o4 {
    return true
  }
  // Special cases: collinear overlaps
  if o1 == 0 && on_segment_collinear(s2.p, s1) {
    return true
  }
  if o2 == 0 && on_segment_collinear(s2.q, s1) {
    return true
  }
  if o3 == 0 && on_segment_collinear(s1.p, s2) {
    return true
  }
  if o4 == 0 && on_segment_collinear(s1.q, s2) {
    return true
  }
  false
}

/// Check if point `p` lies on segment `s`. O(1).
pub fn point_on_segment(p : @geometry_utils.Point, s : Segment) -> Bool {
  orientation(s.p, s.q, p) == 0 && on_segment_collinear(p, s)
}

/// Check if a point is strictly inside a simple polygon using ray casting
/// (even-odd rule). The polygon is given as a list of vertices in order
/// (clockwise or counterclockwise). The polygon is assumed to be simple
/// (no self-intersections) and have at least 3 vertices.
///
/// A point exactly on the boundary is not guaranteed to be detected as
/// "inside" — use `point_on_polygon_boundary` for boundary checks.
///
/// O(n) time.
pub fn point_in_polygon(p : @geometry_utils.Point, polygon : Array[@geometry_utils.Point]) -> Bool {
  let n = polygon.length()
  if n < 3 {
    return false
  }
  let mut inside = false
  let mut j = n - 1
  for i = 0; i < n; i = i + 1 {
    let pi = polygon[i]
    let pj = polygon[j]
    // Check if the ray from p going right crosses edge pj->pi
    if (pi.y > p.y) != (pj.y > p.y) {
      // x_intersect = pj.x + (p.y - pj.y) / (pi.y - pj.y) * (pi.x - pj.x)
      // We need p.x < x_intersect.
      // cross = (p.y - pj.y) * (pi.x - pj.x) - (p.x - pj.x) * (pi.y - pj.y)
      // When dy > 0, we need cross > 0; when dy < 0, we need cross < 0.
      // Equivalently: sign(cross) == sign(dy), i.e., cross and dy have same sign.
      let dy = (pi.y - pj.y).to_int64()
      let cross = (p.y - pj.y).to_int64() * (pi.x - pj.x).to_int64() -
        (p.x - pj.x).to_int64() * dy
      if (dy > 0L && cross > 0L) || (dy < 0L && cross < 0L) {
        inside = !inside
      }
    }
    j = i
  }
  inside
}

/// Check if a point lies exactly on the boundary of the polygon. O(n).
pub fn point_on_polygon_boundary(p : @geometry_utils.Point, polygon : Array[@geometry_utils.Point]) -> Bool {
  let n = polygon.length()
  if n < 2 {
    return false
  }
  for i = 0; i < n; i = i + 1 {
    let j = if i == n - 1 { 0 } else { i + 1 }
    if point_on_segment(p, segment(polygon[i], polygon[j])) {
      return true
    }
  }
  false
}

/// Compute the signed area of a simple polygon using the shoelace formula.
///
/// Returns the area as `Int64` (twice the actual area, maintaining exact
/// precision). The sign indicates orientation: positive = counterclockwise,
/// negative = clockwise. To get the actual area, take `|result| / 2`.
///
/// O(n) time.
pub fn polygon_signed_area_2x(polygon : Array[@geometry_utils.Point]) -> Int64 {
  let n = polygon.length()
  if n < 3 {
    return 0L
  }
  let mut sum = 0L
  for i = 0; i < n; i = i + 1 {
    let j = if i == n - 1 { 0 } else { i + 1 }
    let xi = polygon[i].x.to_int64()
    let yi = polygon[i].y.to_int64()
    let xj = polygon[j].x.to_int64()
    let yj = polygon[j].y.to_int64()
    sum = sum + xi * yj - xj * yi
  }
  sum
}

/// Compute the absolute area of a simple polygon.
///
/// Uses the shoelace formula. The result is a `Double` because the area
/// may be a half-integer (e.g., a triangle with area 2.5).
///
/// O(n) time.
pub fn polygon_area(polygon : Array[@geometry_utils.Point]) -> Double {
  let area2 = polygon_signed_area_2x(polygon)
  // |area2| / 2.0
  let abs_area2 = if area2 < 0L { -area2 } else { area2 }
  abs_area2.to_double() / 2.0
}

/// Check if a simple polygon is convex. O(n).
///
/// The polygon is convex if all turns are in the same direction (all left
/// or all right, allowing collinear edges). The vertex order (CW or CCW)
/// is determined automatically.
pub fn polygon_is_convex(polygon : Array[@geometry_utils.Point]) -> Bool {
  let n = polygon.length()
  if n < 3 {
    return false
  }
  if n == 3 {
    return true
  }
  // Find the first non-zero orientation to determine expected sign
  let mut sign = 0
  for i = 0; i < n; i = i + 1 {
    let prev = polygon[if i == 0 { n - 1 } else { i - 1 }]
    let curr = polygon[i]
    let next = polygon[if i == n - 1 { 0 } else { i + 1 }]
    let o = orientation(prev, curr, next)
    if o != 0 {
      sign = o
      break
    }
  }
  if sign == 0 {
    // All points collinear
    return true
  }
  // Check all turns match sign (allowing 0 for collinear)
  for i = 0; i < n; i = i + 1 {
    let prev = polygon[if i == 0 { n - 1 } else { i - 1 }]
    let curr = polygon[i]
    let next = polygon[if i == n - 1 { 0 } else { i + 1 }]
    let o = orientation(prev, curr, next)
    if o != 0 && o != sign {
      return false
    }
  }
  true
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "segment_ops: crossing segments" {
  let s1 = segment(point(0, 0), point(4, 4))
  let s2 = segment(point(0, 4), point(4, 0))
  assert_true(segments_intersect(s1, s2))
}

test "segment_ops: non-crossing segments" {
  let s1 = segment(point(0, 0), point(2, 2))
  let s2 = segment(point(3, 3), point(5, 5))
  assert_false(segments_intersect(s1, s2))
}

test "segment_ops: collinear non-overlapping" {
  let s1 = segment(point(0, 0), point(2, 0))
  let s2 = segment(point(3, 0), point(5, 0))
  assert_false(segments_intersect(s1, s2))
}

test "segment_ops: collinear overlapping" {
  let s1 = segment(point(0, 0), point(4, 0))
  let s2 = segment(point(2, 0), point(6, 0))
  assert_true(segments_intersect(s1, s2))
}

test "segment_ops: endpoint touching" {
  let s1 = segment(point(0, 0), point(2, 2))
  let s2 = segment(point(2, 2), point(4, 0))
  assert_true(segments_intersect(s1, s2))
}

test "segment_ops: shared endpoint" {
  let s1 = segment(point(0, 0), point(2, 0))
  let s2 = segment(point(0, 0), point(0, 2))
  assert_true(segments_intersect(s1, s2))
}

test "segment_ops: T-junction" {
  let s1 = segment(point(0, 0), point(4, 0))
  let s2 = segment(point(2, -2), point(2, 2))
  assert_true(segments_intersect(s1, s2))
}

test "segment_ops: parallel segments" {
  let s1 = segment(point(0, 0), point(4, 0))
  let s2 = segment(point(0, 1), point(4, 1))
  assert_false(segments_intersect(s1, s2))
}

test "segment_ops: point on segment" {
  let s = segment(point(0, 0), point(6, 6))
  assert_true(point_on_segment(point(3, 3), s))
  assert_true(point_on_segment(point(0, 0), s))
  assert_true(point_on_segment(point(6, 6), s))
  assert_false(point_on_segment(point(7, 7), s))
  assert_false(point_on_segment(point(3, 4), s))
}

test "segment_ops: point on horizontal segment" {
  let s = segment(point(0, 5), point(10, 5))
  assert_true(point_on_segment(point(5, 5), s))
  assert_false(point_on_segment(point(5, 6), s))
  assert_false(point_on_segment(point(-1, 5), s))
  assert_false(point_on_segment(point(11, 5), s))
}

test "point_in_polygon: square interior" {
  let square = [point(0, 0), point(10, 0), point(10, 10), point(0, 10)]
  assert_true(point_in_polygon(point(5, 5), square))
  assert_false(point_in_polygon(point(-1, 5), square))
  assert_false(point_in_polygon(point(11, 5), square))
  assert_false(point_in_polygon(point(5, -1), square))
  assert_false(point_in_polygon(point(5, 11), square))
}

test "point_in_polygon: triangle interior" {
  let tri = [point(0, 0), point(10, 0), point(5, 10)]
  assert_true(point_in_polygon(point(5, 3), tri))
  assert_true(point_in_polygon(point(5, 1), tri))
  assert_false(point_in_polygon(point(0, 5), tri))
  assert_false(point_in_polygon(point(10, 5), tri))
  assert_false(point_in_polygon(point(5, 11), tri))
}

test "point_in_polygon: concave polygon" {
  // L-shaped polygon
  let poly = [
    point(0, 0), point(4, 0), point(4, 2), point(2, 2),
    point(2, 4), point(0, 4),
  ]
  assert_true(point_in_polygon(point(1, 1), poly))
  assert_true(point_in_polygon(point(3, 1), poly))
  assert_false(point_in_polygon(point(3, 3), poly)) // in the cut-out
  assert_true(point_in_polygon(point(1, 3), poly)) // in the left arm
}

test "point_in_polygon: clockwise square" {
  let square = [point(0, 0), point(0, 10), point(10, 10), point(10, 0)]
  assert_true(point_in_polygon(point(5, 5), square))
  assert_false(point_in_polygon(point(-1, -1), square))
}

test "point_in_polygon: large polygon" {
  // Convex hexagon centered at origin
  let hex = [
    point(100, 0), point(50, 87), point(-50, 87),
    point(-100, 0), point(-50, -87), point(50, -87),
  ]
  assert_true(point_in_polygon(point(0, 0), hex))
  assert_true(point_in_polygon(point(50, 0), hex))
  assert_false(point_in_polygon(point(101, 0), hex))
  assert_false(point_in_polygon(point(0, 88), hex))
}

test "point_in_polygon: degenerate (too few vertices)" {
  let degenerate = [point(0, 0), point(1, 1)]
  assert_false(point_in_polygon(point(0, 0), degenerate))
}

test "point_in_polygon: point on boundary" {
  let square = [point(0, 0), point(10, 0), point(10, 10), point(0, 10)]
  // Ray casting may or may not count boundary as inside,
  // but point_on_polygon_boundary should detect it
  assert_true(point_on_polygon_boundary(point(5, 0), square))
  assert_true(point_on_polygon_boundary(point(0, 5), square))
  assert_true(point_on_polygon_boundary(point(0, 0), square))
  assert_true(point_on_polygon_boundary(point(10, 10), square))
  assert_false(point_on_polygon_boundary(point(5, 5), square))
  assert_false(point_on_polygon_boundary(point(-1, 0), square))
}

test "polygon_area: unit square" {
  let square = [point(0, 0), point(1, 0), point(1, 1), point(0, 1)]
  assert_eq(polygon_area(square), 1.0)
}

test "polygon_area: larger square" {
  let square = [point(0, 0), point(10, 0), point(10, 10), point(0, 10)]
  assert_eq(polygon_area(square), 100.0)
}

test "polygon_area: triangle" {
  let tri = [point(0, 0), point(10, 0), point(5, 10)]
  assert_eq(polygon_area(tri), 50.0)
}

test "polygon_area: triangle half-integer" {
  let tri = [point(0, 0), point(3, 0), point(0, 1)]
  assert_eq(polygon_area(tri), 1.5)
}

test "polygon_area: clockwise gives same absolute area" {
  let tri_cw = [point(0, 0), point(0, 10), point(5, 0)]
  assert_eq(polygon_area(tri_cw), 25.0)
}

test "polygon_area: hexagon" {
  // Hexagon centered at origin (not regular, but integer coordinates)
  // Vertices: (2,0), (1,2), (-1,2), (-2,0), (-1,-2), (1,-2)
  let hex = [
    point(2, 0), point(1, 2), point(-1, 2),
    point(-2, 0), point(-1, -2), point(1, -2),
  ]
  let area = polygon_area(hex)
  assert_eq(area, 12.0)
}

test "polygon_area: degenerate" {
  let line = [point(0, 0), point(5, 5)]
  assert_eq(polygon_area(line), 0.0)
}

test "polygon_is_convex: convex square" {
  let square = [point(0, 0), point(10, 0), point(10, 10), point(0, 10)]
  assert_true(polygon_is_convex(square))
}

test "polygon_is_convex: concave L-shape" {
  let l_shape = [
    point(0, 0), point(4, 0), point(4, 2), point(2, 2),
    point(2, 4), point(0, 4),
  ]
  assert_false(polygon_is_convex(l_shape))
}

test "polygon_is_convex: convex pentagon" {
  let pent = [
    point(0, 0), point(4, 0), point(6, 3), point(3, 6), point(-1, 3),
  ]
  assert_true(polygon_is_convex(pent))
}

test "polygon_is_convex: triangle is always convex" {
  let tri = [point(0, 0), point(10, 0), point(5, 10)]
  assert_true(polygon_is_convex(tri))
}

test "polygon_is_convex: clockwise convex" {
  let square = [point(0, 0), point(0, 10), point(10, 10), point(10, 0)]
  assert_true(polygon_is_convex(square))
}

test "polygon_is_convex: collinear vertices" {
  let poly = [point(0, 0), point(5, 0), point(10, 0), point(10, 10), point(0, 10)]
  assert_true(polygon_is_convex(poly))
}

test "segment_ops: vertical and horizontal crossing" {
  let v = segment(point(5, 0), point(5, 10))
  let h = segment(point(0, 5), point(10, 5))
  assert_true(segments_intersect(v, h))
}

test "segment_ops: nearly touching" {
  let s1 = segment(point(0, 0), point(3, 3))
  let s2 = segment(point(3, 3), point(6, 0))
  assert_true(segments_intersect(s1, s2))
}

test "segment_ops: large coordinates" {
  // Coordinates near sqrt(Int32_MAX) ≈ 46340
  let s1 = segment(point(0, 0), point(40000, 40000))
  let s2 = segment(point(0, 40000), point(40000, 0))
  assert_true(segments_intersect(s1, s2))
}
