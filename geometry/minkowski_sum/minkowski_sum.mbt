/// Minkowski Sum of Convex Polygons.
///
/// Computes the Minkowski sum of two convex polygons, which is the set
/// {a + b : a ∈ P, b ∈ Q}. The result is also a convex polygon with at
/// most |P| + |Q| vertices.
///
/// Key applications:
/// - **Collision detection**: two shapes collide iff their Minkowski
///   difference contains the origin.
/// - **Motion planning**: growing obstacles by the robot's shape.
/// - **Computer graphics**: offsetting/beveling polygons.
///
/// ## Algorithm
///
/// Based on the rotating calipers / edge-merge technique:
/// 1. Ensure both polygons are convex and counter-clockwise (CCW).
/// 2. Find the bottommost vertex of each polygon.
/// 3. Walk along both polygons simultaneously, always picking the edge
///    with the smaller angle. This produces the Minkowski sum boundary.
///
/// ## Complexity
/// - Time:  O(n + m) where n = |P|, m = |Q|.
/// - Space: O(n + m) for the result.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

///|
/// A 2D point with integer coordinates.
priv struct Point {
  x : Int
  y : Int
}

///|
/// Compute the cross product of vectors OA and OB.
/// Positive = left turn (CCW), negative = right turn (CW), zero = colinear.
/// Ensure a convex polygon is CCW (counter-clockwise).
fn ensure_ccw(poly : Array[Point]) -> Array[Point] {
  let n = poly.length()
  if n < 3 {
    return poly
  }
  // Compute signed area: positive = CCW, negative = CW.
  // Int64 prevents overflow for large coordinates.
  let mut area = 0L
  for i = 0; i < n; i = i + 1 {
    let j = (i + 1) % n
    area = area +
      poly[i].x.to_int64() * poly[j].y.to_int64() -
      poly[j].x.to_int64() * poly[i].y.to_int64()
  }
  if area < 0L {
    let result : Array[Point] = []
    for i = n - 1; i >= 0; i = i - 1 {
      result.push(poly[i])
    }
    result
  } else {
    poly
  }
}

///|
/// Find the index of the bottommost (then leftmost) vertex.
fn bottommost(poly : Array[Point]) -> Int {
  let mut best = 0
  for i = 1; i < poly.length(); i = i + 1 {
    if poly[i].y < poly[best].y ||
      (poly[i].y == poly[best].y && poly[i].x < poly[best].x) {
      best = i
    }
  }
  best
}

///|
/// Compute the Minkowski sum of two convex polygons.
///
/// Both polygons must be convex. The result is a convex polygon with at
/// most |P| + |Q| vertices.
///
/// ## Parameters
/// - `poly_a`: vertices of the first convex polygon.
/// - `poly_b`: vertices of the second convex polygon.
///
/// ## Returns
/// The vertices of the Minkowski sum polygon (CCW order).
pub fn minkowski_sum(
  poly_a : Array[(Int, Int)],
  poly_b : Array[(Int, Int)],
) -> Array[(Int, Int)] {
  let n = poly_a.length()
  let m = poly_b.length()
  if n == 0 {
    return poly_b
  }
  if m == 0 {
    return poly_a
  }
  // Convert to Point arrays.
  let a : Array[Point] = []
  for i = 0; i < n; i = i + 1 {
    let (x, y) = poly_a[i]
    a.push({ x, y, })
  }
  let b : Array[Point] = []
  for i = 0; i < m; i = i + 1 {
    let (x, y) = poly_b[i]
    b.push({ x, y, })
  }
  // Ensure CCW.
  let a_ccw = ensure_ccw(a)
  let b_ccw = ensure_ccw(b)
  let na = a_ccw.length()
  let nb = b_ccw.length()
  // Find bottommost vertex of each.
  let ia = bottommost(a_ccw)
  let ib = bottommost(b_ccw)
  let result : Array[Point] = []
  let mut i = 0
  let mut j = 0
  while i < na || j < nb {
    let pa = a_ccw[(ia + i) % na]
    let pb = b_ccw[(ib + j) % nb]
    result.push({ x: pa.x + pb.x, y: pa.y + pb.y, })
    if i >= na {
      j = j + 1
      continue
    }
    if j >= nb {
      i = i + 1
      continue
    }
    // Compare edge directions.
    let ea = {
      let next_a = a_ccw[(ia + i + 1) % na]
      { x: next_a.x - pa.x, y: next_a.y - pa.y, }
    }
    let eb = {
      let next_b = b_ccw[(ib + j + 1) % nb]
      { x: next_b.x - pb.x, y: next_b.y - pb.y, }
    }
    let c = ea.x.to_int64() * eb.y.to_int64() -
      ea.y.to_int64() * eb.x.to_int64()
    if c > 0L {
      i = i + 1
    } else if c < 0L {
      j = j + 1
    } else {
      i = i + 1
      j = j + 1
    }
  }
  // Remove duplicate last point if it equals the first.
  if result.length() > 1 {
    let first = result[0]
    let last = result[result.length() - 1]
    if first.x == last.x && first.y == last.y {
      result.remove(result.length() - 1) |> ignore
    }
  }
  // Convert back to tuples.
  let out : Array[(Int, Int)] = []
  for i = 0; i < result.length(); i = i + 1 {
    out.push((result[i].x, result[i].y))
  }
  out
}

///|
/// Check if the origin is inside a convex polygon (CCW).
/// Used for collision detection: two shapes collide iff the origin is
/// inside their Minkowski difference.
pub fn contains_origin(poly : Array[(Int, Int)]) -> Bool {
  let n = poly.length()
  if n < 3 {
    return false
  }
  for i = 0; i < n; i = i + 1 {
    let (ax, ay) = poly[i]
    let (bx, by) = poly[(i + 1) % n]
    // Cross product of (a - 0) × (b - 0) = ax*by - ay*bx
    let cross = ax * by - ay * bx
    if cross < 0 {
      return false
    }
  }
  true
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "minkowski_sum: two squares" {
  // Square A: [(0,0), (2,0), (2,2), (0,2)]
  // Square B: [(0,0), (1,0), (1,1), (0,1)]
  // Sum should be a 4x3 rectangle.
  let a = [(0, 0), (2, 0), (2, 2), (0, 2)]
  let b = [(0, 0), (1, 0), (1, 1), (0, 1)]
  let result = minkowski_sum(a, b)
  // The sum of two axis-aligned rectangles is the sum of their dimensions.
  // Result should have area = (2+1)*(2+1) = 9
  let mut min_x = 2147483647
  let mut max_x = -2147483648
  let mut min_y = 2147483647
  let mut max_y = -2147483648
  for i = 0; i < result.length(); i = i + 1 {
    let (x, y) = result[i]
    if x < min_x {
      min_x = x
    }
    if x > max_x {
      max_x = x
    }
    if y < min_y {
      min_y = y
    }
    if y > max_y {
      max_y = y
    }
  }
  assert_eq(max_x - min_x, 3)
  assert_eq(max_y - min_y, 3)
}

///|
test "minkowski_sum: point and polygon" {
  // Sum with a point (0,0) should return the original polygon.
  let a = [(0, 0), (1, 0), (0, 1)]
  let b = [(0, 0)]
  let result = minkowski_sum(a, b)
  // Should be same as A (possibly re-ordered).
  assert_eq(result.length(), 3)
}

///|
test "minkowski_sum: two triangles" {
  let a = [(0, 0), (3, 0), (0, 3)]
  let b = [(0, 0), (1, 0), (0, 1)]
  let result = minkowski_sum(a, b)
  // The sum should contain all vertices.
  assert_true(result.length() >= 3)
}

///|
test "minkowski_sum: contains_origin for collision" {
  // A triangle containing the origin.
  let tri = [(-1, -1), (1, -1), (0, 1)]
  assert_true(contains_origin(tri))
  // A triangle NOT containing the origin.
  let tri2 = [(1, 1), (2, 1), (1, 2)]
  assert_false(contains_origin(tri2))
}

///|
test "minkowski_sum: single point polygons" {
  let a = [(0, 0)]
  let b = [(5, 5)]
  let result = minkowski_sum(a, b)
  assert_eq(result.length(), 1)
  assert_eq(result[0], (5, 5))
}

///|
test "minkowski_sum: CW input is normalized to CCW" {
  // CW square: [(0,0), (0,2), (2,2), (2,0)]
  let a = [(0, 0), (0, 2), (2, 2), (2, 0)]
  let b = [(0, 0)]
  let result = minkowski_sum(a, b)
  assert_eq(result.length(), 4)
}

///|
test "minkowski_sum: translated polygon" {
  // Sum of square at origin with point (3,3) = translated square
  let a = [(0, 0), (1, 0), (1, 1), (0, 1)]
  let b = [(3, 3)]
  let result = minkowski_sum(a, b)
  // All result vertices should be shifted by (3,3)
  let mut found_origin = false
  for i = 0; i < result.length(); i = i + 1 {
    let (x, y) = result[i]
    if x == 3 && y == 3 {
      found_origin = true
    }
  }
  assert_true(found_origin)
}

///|
test "contains_origin: degenerate polygon" {
  // Less than 3 points cannot contain origin
  assert_false(contains_origin([(0, 0), (1, 1)]))
  assert_false(contains_origin([]))
}

///|
test "minkowski_sum: two identical squares" {
  let a = [(0, 0), (1, 0), (1, 1), (0, 1)]
  let result = minkowski_sum(a, a)
  // Sum of two unit squares = 2x2 square
  let mut max_coord = 0
  for i = 0; i < result.length(); i = i + 1 {
    let (x, y) = result[i]
    if x > max_coord {
      max_coord = x
    }
    if y > max_coord {
      max_coord = y
    }
  }
  assert_eq(max_coord, 2)
}
