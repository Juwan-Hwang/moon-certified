/// Point-in-Polygon Test (Ray Casting / Winding Number).
///
/// Determines whether a point is inside a polygon using the ray-casting
/// algorithm (even-odd rule). Works for both convex and concave polygons.
///
/// ## Algorithm
///
/// Cast a horizontal ray from the test point to the right. Count the
/// number of polygon edges crossed. If odd, the point is inside; if
/// even, outside.
///
/// ## Complexity
/// - Time:  O(n) where n = number of vertices.
/// - Space: O(1).
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

///|
/// Check if point (px, py) is inside the polygon defined by vertices.
///
/// The polygon is given as a list of (x, y) vertices in order
/// (either CW or CCW). The algorithm handles both convex and concave
/// polygons, and correctly handles edge cases (point on edge, point at
/// vertex, degenerate edges).
///
/// Returns:
/// - `true` if the point is strictly inside.
/// - `false` if the point is outside or exactly on the boundary.
pub fn point_in_polygon(
  px : Int,
  py : Int,
  polygon : Array[(Int, Int)],
) -> Bool {
  let n = polygon.length()
  if n < 3 {
    return false
  }
  // Boundary points are not "inside" — check first for consistent behavior.
  if point_on_polygon_boundary(px, py, polygon) {
    return false
  }
  let mut inside = false
  let mut j = n - 1
  for i = 0; i < n; i = i + 1 {
    let (xi, yi) = polygon[i]
    let (xj, yj) = polygon[j]
    // Check if the edge (j→i) crosses the horizontal ray from (px,py) going right.
    // Condition: one endpoint is above the ray, the other at or below.
    if (yi > py) != (yj > py) {
      // Compute the x-coordinate of the intersection.
      let dx = xj - xi
      let dy = yj - yi
      if dy != 0 {
        let x_intersect = xi.to_double() +
          (py - yi).to_double() / dy.to_double() * dx.to_double()
        if px.to_double() < x_intersect {
          inside = !inside
        }
      }
    }
    j = i
  }
  inside
}

///|
/// Check if point (px, py) is on the boundary of the polygon.
pub fn point_on_polygon_boundary(
  px : Int,
  py : Int,
  polygon : Array[(Int, Int)],
) -> Bool {
  let n = polygon.length()
  if n < 2 {
    return false
  }
  for i = 0; i < n; i = i + 1 {
    let (x1, y1) = polygon[i]
    let (x2, y2) = polygon[(i + 1) % n]
    if on_segment_int(x1, y1, x2, y2, px, py) {
      return true
    }
  }
  false
}

///|
/// Check if point (px,py) lies on segment (x1,y1)-(x2,y2).
fn on_segment_int(
  x1 : Int,
  y1 : Int,
  x2 : Int,
  y2 : Int,
  px : Int,
  py : Int,
) -> Bool {
  // Cross product must be zero (colinear).
  let cross = (px - x1) * (y2 - y1) - (py - y1) * (x2 - x1)
  if cross != 0 {
    return false
  }
  // Must be within bounding box.
  px >= min2(x1, x2) &&
  px <= max2(x1, x2) &&
  py >= min2(y1, y2) &&
  py <= max2(y1, y2)
}

///|
fn min2(a : Int, b : Int) -> Int {
  if a < b {
    a
  } else {
    b
  }
}

///|
fn max2(a : Int, b : Int) -> Int {
  if a > b {
    a
  } else {
    b
  }
}

///|
/// Compute the signed area of a polygon.
/// Positive for CCW, negative for CW.
pub fn polygon_signed_area(polygon : Array[(Int, Int)]) -> Double {
  let n = polygon.length()
  if n < 3 {
    return 0.0
  }
  let mut area = 0.0
  for i = 0; i < n; i = i + 1 {
    let (xi, yi) = polygon[i]
    let (xj, yj) = polygon[(i + 1) % n]
    area = area +
      (xi.to_double() * yj.to_double() - xj.to_double() * yi.to_double())
  }
  area / 2.0
}

///|
/// Compute the area (absolute) of a polygon.
pub fn polygon_area(polygon : Array[(Int, Int)]) -> Double {
  let a = polygon_signed_area(polygon)
  if a < 0.0 {
    -a
  } else {
    a
  }
}

///|
/// Compute the centroid of a polygon.
pub fn polygon_centroid(polygon : Array[(Int, Int)]) -> (Double, Double) {
  let n = polygon.length()
  if n < 3 {
    return (0.0, 0.0)
  }
  let mut cx = 0.0
  let mut cy = 0.0
  let mut area = 0.0
  for i = 0; i < n; i = i + 1 {
    let (xi, yi) = polygon[i]
    let (xj, yj) = polygon[(i + 1) % n]
    let cross = xi.to_double() * yj.to_double() -
      xj.to_double() * yi.to_double()
    area = area + cross
    cx = cx + (xi.to_double() + xj.to_double()) * cross
    cy = cy + (yi.to_double() + yj.to_double()) * cross
  }
  area = area / 2.0
  if area == 0.0 {
    return (0.0, 0.0)
  }
  (cx / (6.0 * area), cy / (6.0 * area))
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "point_in_polygon: square contains center" {
  let square = [(0, 0), (10, 0), (10, 10), (0, 10)]
  assert_true(point_in_polygon(5, 5, square))
}

///|
test "point_in_polygon: square outside" {
  let square = [(0, 0), (10, 0), (10, 10), (0, 10)]
  assert_false(point_in_polygon(15, 5, square))
  assert_false(point_in_polygon(-1, 5, square))
  assert_false(point_in_polygon(5, -1, square))
}

///|
test "point_in_polygon: concave polygon" {
  // L-shaped polygon
  let l = [(0, 0), (4, 0), (4, 2), (2, 2), (2, 4), (0, 4)]
  // Inside the L
  assert_true(point_in_polygon(1, 1, l))
  assert_true(point_in_polygon(3, 1, l))
  // Inside the cut-out area (outside)
  assert_false(point_in_polygon(3, 3, l))
}

///|
test "point_in_polygon: triangle" {
  let tri = [(0, 0), (10, 0), (5, 10)]
  assert_true(point_in_polygon(5, 3, tri))
  assert_false(point_in_polygon(0, 5, tri))
}

///|
test "point_in_polygon: boundary" {
  let square = [(0, 0), (10, 0), (10, 10), (0, 10)]
  // Point on edge — ray casting returns false (on boundary is not "inside").
  assert_false(point_in_polygon(5, 0, square))
  // But boundary check should return true.
  assert_true(point_on_polygon_boundary(5, 0, square))
  assert_true(point_on_polygon_boundary(0, 0, square))
  assert_false(point_on_polygon_boundary(5, 5, square))
}

///|
test "point_in_polygon: polygon area" {
  let square = [(0, 0), (4, 0), (4, 4), (0, 4)]
  assert_eq(polygon_area(square), 16.0)
  let tri = [(0, 0), (6, 0), (0, 4)]
  assert_eq(polygon_area(tri), 12.0)
}

///|
test "point_in_polygon: centroid" {
  let square = [(0, 0), (4, 0), (4, 4), (0, 4)]
  let (cx, cy) = polygon_centroid(square)
  assert_eq(cx, 2.0)
  assert_eq(cy, 2.0)
}

///|
test "point_in_polygon: degenerate" {
  let degenerate : Array[(Int, Int)] = [(0, 0), (1, 1)]
  assert_false(point_in_polygon(0, 0, degenerate))
}
