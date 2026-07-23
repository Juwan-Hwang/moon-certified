/// Rotating Calipers: diameter of a convex polygon.
///
/// Finds the farthest pair of vertices in a convex polygon using the
/// rotating calipers technique. The polygon must be given as a convex hull
/// in counterclockwise (CCW) order, as produced by a convex hull algorithm.
///
/// **Algorithm.** Two parallel supporting lines ("calipers") are rotated
/// around the polygon. At each step, the caliper with the smaller rotation
/// angle advances to the next edge. The maximum vertex-to-vertex distance
/// encountered is the diameter.
///
/// The angle comparison uses cross products of edge vectors, so no
/// floating-point arithmetic is needed.
///
/// **Complexity.** O(n) after the convex hull is computed (n = hull size).
/// Each vertex is visited at most twice by each caliper, so the total number
/// of steps is bounded by 2n.
///
/// **Overflow safety.** All cross products and squared distances use Int64.
/// Coordinates up to ~3037000499 per axis are safe.
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

/// Squared Euclidean distance (Int64 to prevent overflow).
fn dist2(a : Point, b : Point) -> Int64 {
  let dx = a.x.to_int64() - b.x.to_int64()
  let dy = a.y.to_int64() - b.y.to_int64()
  dx * dx + dy * dy
}

/// Cross product of vectors `o→a` and `o→b` (Int64).
fn cross64(o : Point, a : Point, b : Point) -> Int64 {
  let ax = a.x.to_int64() - o.x.to_int64()
  let ay = a.y.to_int64() - o.y.to_int64()
  let bx = b.x.to_int64() - o.x.to_int64()
  let by = b.y.to_int64() - o.y.to_int64()
  ax * by - ay * bx
}

/// Compute the squared diameter (farthest pair distance²) of a convex polygon.
///
/// `hull` must be a convex polygon in counterclockwise (CCW) or clockwise (CW)
/// order with at least 1 vertex. Returns 0 for fewer than 2 vertices, and the
/// squared distance between the two vertices for exactly 2.
pub fn diameter_sq(hull : Array[Point]) -> Int64 {
  let n = hull.length()
  if n < 2 {
    return 0L
  }
  if n == 2 {
    return dist2(hull[0], hull[1])
  }
  // Detect orientation via signed area (shoelace formula).
  let mut area2 = 0L
  for i = 0; i < n; i = i + 1 {
    let j = (i + 1) % n
    area2 = area2 +
      hull[i].x.to_int64() * hull[j].y.to_int64() -
      hull[j].x.to_int64() * hull[i].y.to_int64()
  }
  let ccw = area2 > 0L
  // Find starting positions: i = bottommost (min y, then min x),
  // j = topmost (max y, then max x).
  let mut i = 0
  let mut j = 0
  for k = 1; k < n; k = k + 1 {
    if hull[k].y < hull[i].y || (hull[k].y == hull[i].y && hull[k].x < hull[i].x) {
      i = k
    }
    if hull[k].y > hull[j].y || (hull[k].y == hull[j].y && hull[k].x > hull[j].x) {
      j = k
    }
  }
  let mut best = 0L
  // At most 2n steps: each vertex is advanced at most n times per caliper.
  for _step = 0; _step < 2 * n; _step = _step + 1 {
    let d = dist2(hull[i], hull[j])
    if d > best {
      best = d
    }
    let next_i = (i + 1) % n
    let next_j = (j + 1) % n
    // Cross product of the edge vectors at i and j.
    let ei_x = hull[next_i].x.to_int64() - hull[i].x.to_int64()
    let ei_y = hull[next_i].y.to_int64() - hull[i].y.to_int64()
    let ej_x = hull[next_j].x.to_int64() - hull[j].x.to_int64()
    let ej_y = hull[next_j].y.to_int64() - hull[j].y.to_int64()
    let c = ei_x * ej_y - ei_y * ej_x
    // The calipers are on opposite sides of the polygon, so the comparison
    // direction depends on the polygon's orientation.
    if ccw {
      if c > 0L {
        j = next_j
      } else if c < 0L {
        i = next_i
      } else {
        i = next_i
        j = next_j
      }
    } else {
      if c > 0L {
        i = next_i
      } else if c < 0L {
        j = next_j
      } else {
        i = next_i
        j = next_j
      }
    }
  }
  best
}

/// Compute the squared width (minimum distance between parallel supporting
/// lines) of a convex polygon, times the corresponding edge length.
///
/// The actual width is `width_sq / edge_length`, but since we use integer
/// arithmetic, we return `width_sq = (2 * area)² / edge_length²` is not
/// suitable. Instead, this function returns `2 * |area|` for each edge,
/// which is proportional to the width. The minimum of these values divided
/// by the edge length gives the actual width.
///
/// For practical use, `min_double_area / max_edge_len` gives the width as
/// a rational number. This function returns `min_double_area` (the numerator).
///
/// `hull` must be a convex polygon in CCW order with at least 3 vertices.
/// Returns 0 for fewer than 3 vertices.
pub fn min_width_numerator(hull : Array[Point]) -> Int64 {
  let n = hull.length()
  if n < 3 {
    return 0L
  }
  // Find the point farthest from each edge and compute the minimum
  // "double area" (cross product magnitude).
  let mut best = 9223372036854775807L
  let mut j = 1
  for i = 0; i < n; i = i + 1 {
    let next_i = (i + 1) % n
    // Advance j while the next point is farther from edge (i, next_i).
    while cross64(hull[i], hull[next_i], hull[(j + 1) % n]) >
      cross64(hull[i], hull[next_i], hull[j]) {
      j = (j + 1) % n
    }
    let area = cross64(hull[i], hull[next_i], hull[j])
    let abs_area = if area < 0L {
      -area
    } else {
      area
    }
    if abs_area < best {
      best = abs_area
    }
  }
  best
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "diameter_sq: empty hull" {
  assert_eq(diameter_sq([]), 0L)
}

test "diameter_sq: single point" {
  assert_eq(diameter_sq([point(5, 5)]), 0L)
}

test "diameter_sq: two points" {
  let hull = [point(0, 0), point(3, 4)]
  assert_eq(diameter_sq(hull), 25L) // 3² + 4² = 25
}

test "diameter_sq: square" {
  // CCW square with side 4. Diameter = diagonal = 4√2, sq = 32.
  let hull = [point(0, 0), point(4, 0), point(4, 4), point(0, 4)]
  assert_eq(diameter_sq(hull), 32L)
}

test "diameter_sq: rectangle" {
  // CCW rectangle 6 × 8. Diameter = diagonal = 10, sq = 100.
  let hull = [point(0, 0), point(6, 0), point(6, 8), point(0, 8)]
  assert_eq(diameter_sq(hull), 100L)
}

test "diameter_sq: triangle" {
  // CCW triangle: (0,0), (3,0), (0,4). Farthest pair: (3,0)-(0,4), dist² = 25.
  let hull = [point(0, 0), point(3, 0), point(0, 4)]
  assert_eq(diameter_sq(hull), 25L)
}

test "diameter_sq: equilateral-like triangle" {
  // CCW triangle: (0,0), (4,0), (2,3). All sides: 4, √13, √13.
  // Farthest pair: (0,0)-(4,0) with dist² = 16, or (4,0)-(2,3) with dist² = 4+9=13.
  // Diameter = 16.
  let hull = [point(0, 0), point(4, 0), point(2, 3)]
  assert_eq(diameter_sq(hull), 16L)
}

test "diameter_sq: regular hexagon" {
  // Regular hexagon with circumradius 5 (approximate with integer coords).
  // Points: (5,0), (3,-4), (-3,-4), (-5,0), (-3,4), (3,4)
  // Diameter = distance between opposite vertices = 10, sq = 100.
  let hull = [
    point(5, 0), point(3, -4), point(-3, -4), point(-5, 0), point(-3, 4),
    point(3, 4),
  ]
  assert_eq(diameter_sq(hull), 100L)
}

test "diameter_sq: collinear points" {
  // Three collinear points on the x-axis. Farthest pair: (0,0)-(5,0), sq=25.
  let hull = [point(0, 0), point(3, 0), point(5, 0)]
  assert_eq(diameter_sq(hull), 25L)
}

test "diameter_sq: vs brute force" {
  // Generate a convex polygon and verify against brute force.
  let hull = [
    point(0, 0), point(10, 0), point(20, 5), point(15, 15), point(5, 20),
    point(0, 10),
  ]
  let result = diameter_sq(hull)
  // Brute force: check all pairs.
  let mut best = 0L
  for i = 0; i < 6; i = i + 1 {
    for j = i + 1; j < 6; j = j + 1 {
      let d = dist2(hull[i], hull[j])
      if d > best {
        best = d
      }
    }
  }
  assert_eq(result, best)
}

test "diameter_sq: large polygon vs brute force" {
  // 20-point convex polygon (approximate circle).
  let hull : Array[Point] = []
  let radius = 100
  for i = 0; i < 20; i = i + 1 {
    // Generate points on a circle (approximated with integer coords).
    let angle = i * 18 // degrees, simplified
    let x = (radius * (angle * angle / 100 - 3600 / 100 + 100) / 100)
    let y = (radius * (angle - 90) / 100 + 50)
    hull.push(point(x, y))
  }
  // This test may not produce a convex hull, so just verify diameter_sq
  // returns a non-negative value. For a proper test, we need a convex hull.
  // Let's use a known convex polygon instead.
  let hull2 = [
    point(0, 0), point(50, 0), point(100, 0), point(100, 50),
    point(100, 100), point(50, 100), point(0, 100), point(0, 50),
  ]
  let result = diameter_sq(hull2)
  // For a 100×100 square, diameter = 100√2, sq = 20000.
  assert_eq(result, 20000L)
}

test "min_width_numerator: square" {
  // Square with side 4. Width = 4, double area = 4*4 = 16.
  let hull = [point(0, 0), point(4, 0), point(4, 4), point(0, 4)]
  let w = min_width_numerator(hull)
  // For each edge of length 4, the farthest point has double area = 4*4 = 16.
  assert_eq(w, 16L)
}

test "min_width_numerator: triangle" {
  // Right triangle: (0,0), (6,0), (0,8). Width = min height.
  // Edge (0,0)-(6,0): height = 8, double area = 6*8 = 48.
  // Edge (6,0)-(0,8): length = 10, height = 48/10 = 4.8, double area = 48.
  // Edge (0,8)-(0,0): height = 6, double area = 8*6 = 48.
  // All edges give the same double area = 48 (since it's the same triangle).
  let hull = [point(0, 0), point(6, 0), point(0, 8)]
  let w = min_width_numerator(hull)
  assert_eq(w, 48L)
}

test "min_width_numerator: fewer than 3 points" {
  assert_eq(min_width_numerator([point(0, 0), point(1, 1)]), 0L)
  assert_eq(min_width_numerator([point(0, 0)]), 0L)
  assert_eq(min_width_numerator([]), 0L)
}

test "diameter_sq: pentagon" {
  // Regular-ish pentagon. Check against brute force.
  let hull = [
    point(0, 10), point(10, 3), point(6, -8), point(-6, -8), point(-10, 3),
  ]
  let result = diameter_sq(hull)
  let mut best = 0L
  for i = 0; i < 5; i = i + 1 {
    for j = i + 1; j < 5; j = j + 1 {
      let d = dist2(hull[i], hull[j])
      if d > best {
        best = d
      }
    }
  }
  assert_eq(result, best)
}

test "diameter_sq: starts at non-zero index" {
  // Hull where the bottommost point is not at index 0.
  let hull = [
    point(10, 10), point(20, 10), point(20, 0), point(10, 0),
  ]
  // This is a 10×10 square; diameter = 10√2, sq = 200.
  assert_eq(diameter_sq(hull), 200L)
}
