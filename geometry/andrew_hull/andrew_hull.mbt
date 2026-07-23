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

/// 2D cross product of vectors `o->a` and `o->b`, computed in Int64 to avoid
/// overflow. Positive => `b` is counterclockwise from `a`; negative =>
/// clockwise; zero => collinear.
fn cross(o : (Int, Int), a : (Int, Int), b : (Int, Int)) -> Int64 {
  let ax = a.0.to_int64() - o.0.to_int64()
  let ay = a.1.to_int64() - o.1.to_int64()
  let bx = b.0.to_int64() - o.0.to_int64()
  let by = b.1.to_int64() - o.1.to_int64()
  ax * by - ay * bx
}

/// Lexicographic comparator for points by (x, y). Returns a negative value
/// when `a` should precede `b`.
fn cmp_point(a : (Int, Int), b : (Int, Int)) -> Int {
  if a.0 != b.0 {
    a.0 - b.0
  } else {
    a.1 - b.1
  }
}

/// Compute the convex hull of `points` (Andrew's monotone chain).
///
/// Returns the hull vertices in counterclockwise order as a `FixedArray`.
pub fn convex_hull(
  points : FixedArray[(Int, Int)]
) -> FixedArray[(Int, Int)] {
  let n = points.length()
  // Fewer than 3 points cannot enclose an area: return them unchanged.
  if n < 3 {
    let out : FixedArray[(Int, Int)] = FixedArray::make(n, (0, 0))
    for i = 0; i < n; i = i + 1 {
      out[i] = points[i]
    }
    return out
  }
  // Copy and sort lexicographically by (x, y).
  let pts : FixedArray[(Int, Int)] = FixedArray::make(n, (0, 0))
  for i = 0; i < n; i = i + 1 {
    pts[i] = points[i]
  }
  pts.sort_by(cmp_point)
  // Remove consecutive duplicates so the chain never stores repeated vertices
  // (duplicate inputs would otherwise produce a degenerate [p, p] seam).
  let uniq : FixedArray[(Int, Int)] = FixedArray::make(n, (0, 0))
  let mut m = 0
  for i = 0; i < n; i = i + 1 {
    if i == 0 || pts[i] != pts[i - 1] {
      uniq[m] = pts[i]
      m = m + 1
    }
  }
  // After deduplication, fewer than 3 distinct points cannot form a polygon.
  if m < 3 {
    let out : FixedArray[(Int, Int)] = FixedArray::make(m, (0, 0))
    for i = 0; i < m; i = i + 1 {
      out[i] = uniq[i]
    }
    return out
  }
  // Lower hull: scan left to right, popping non-left turns.
  let lower : FixedArray[(Int, Int)] = FixedArray::make(m, (0, 0))
  let mut lower_size = 0
  for i = 0; i < m; i = i + 1 {
    let p = uniq[i]
    while lower_size >= 2 &&
      cross(lower[lower_size - 2], lower[lower_size - 1], p) <= 0L {
      lower_size = lower_size - 1
    }
    lower[lower_size] = p
    lower_size = lower_size + 1
  }
  // Upper hull: scan right to left, popping non-left turns.
  let upper : FixedArray[(Int, Int)] = FixedArray::make(m, (0, 0))
  let mut upper_size = 0
  for i = m - 1; i >= 0; i = i - 1 {
    let p = uniq[i]
    while upper_size >= 2 &&
      cross(upper[upper_size - 2], upper[upper_size - 1], p) <= 0L {
      upper_size = upper_size - 1
    }
    upper[upper_size] = p
    upper_size = upper_size + 1
  }
  // Concatenate lower (without last) and upper (without last). Each hull's
  // final vertex is the other hull's first vertex, so both ends are dropped
  // once to avoid duplication.
  let hull_size = (lower_size - 1) + (upper_size - 1)
  let hull : FixedArray[(Int, Int)] = FixedArray::make(hull_size, (0, 0))
  let mut k = 0
  for i = 0; i < lower_size - 1; i = i + 1 {
    hull[k] = lower[i]
    k = k + 1
  }
  for i = 0; i < upper_size - 1; i = i + 1 {
    hull[k] = upper[i]
    k = k + 1
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

/// Build a `FixedArray` from an `Array`, for readable test inputs.
fn of_array(arr : Array[(Int, Int)]) -> FixedArray[(Int, Int)] {
  FixedArray::makei(arr.length(), fn(i) { arr[i] })
}

/// True iff `hull` is a strictly counterclockwise convex polygon.
fn is_convex_ccw(hull : FixedArray[(Int, Int)]) -> Bool {
  let m = hull.length()
  if m < 3 {
    return true
  }
  for i = 0; i < m; i = i + 1 {
    let o = hull[i]
    let a = hull[(i + 1) % m]
    let b = hull[(i + 2) % m]
    if cross(o, a, b) <= 0L {
      return false
    }
  }
  true
}

/// True iff `hull` contains no repeated vertex.
fn has_no_duplicates(hull : FixedArray[(Int, Int)]) -> Bool {
  let m = hull.length()
  for i = 0; i < m; i = i + 1 {
    for j = i + 1; j < m; j = j + 1 {
      if hull[i] == hull[j] {
        return false
      }
    }
  }
  true
}

/// True iff every point of `points` lies on or inside `hull`.
fn all_inside_or_on(
  points : FixedArray[(Int, Int)],
  hull : FixedArray[(Int, Int)],
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
      if p.0 != h.0 || p.1 != h.1 {
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
    let lo_x = min2(a.0, b.0)
    let hi_x = max2(a.0, b.0)
    let lo_y = min2(a.1, b.1)
    let hi_y = max2(a.1, b.1)
    for i = 0; i < n; i = i + 1 {
      let p = points[i]
      if cross(a, b, p) != 0L {
        return false
      }
      if p.0 < lo_x || p.0 > hi_x || p.1 < lo_y || p.1 > hi_y {
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
      if cross(a, b, p) < 0L {
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
  let pts = of_array([(0, 0), (2, 0), (0, 2)])
  let hull = convex_hull(pts)
  assert_eq(hull.length(), 3)
  assert_true(is_convex_ccw(hull))
  assert_true(all_inside_or_on(pts, hull))
}

test "andrew_hull: square" {
  let pts = of_array([(0, 0), (2, 0), (2, 2), (0, 2)])
  let hull = convex_hull(pts)
  assert_eq(hull.length(), 4)
  assert_true(is_convex_ccw(hull))
  assert_true(all_inside_or_on(pts, hull))
}

test "andrew_hull: collinear points" {
  let pts = of_array([(0, 0), (1, 0), (2, 0), (3, 0)])
  let hull = convex_hull(pts)
  assert_eq(hull.length(), 2)
  // Only the two extremes remain (order not asserted, just the set).
  let x0 = hull[0].0
  let x1 = hull[1].0
  assert_true((x0 == 0 && x1 == 3) || (x0 == 3 && x1 == 0))
  assert_true(all_inside_or_on(pts, hull))
}

test "andrew_hull: single point" {
  let pts = of_array([(3, 3)])
  let hull = convex_hull(pts)
  assert_eq(hull.length(), 1)
  assert_eq(hull[0], (3, 3))
  assert_true(all_inside_or_on(pts, hull))
}

test "andrew_hull: two points" {
  let pts = of_array([(0, 0), (1, 1)])
  let hull = convex_hull(pts)
  assert_eq(hull.length(), 2)
  assert_true(all_inside_or_on(pts, hull))
}

test "andrew_hull: all points on hull" {
  // A convex pentagon: every input point is a hull vertex.
  let pts = of_array([(0, 0), (4, 0), (4, 4), (2, 6), (0, 4)])
  let hull = convex_hull(pts)
  assert_eq(hull.length(), 5)
  assert_true(is_convex_ccw(hull))
  assert_true(all_inside_or_on(pts, hull))
}

test "andrew_hull: point inside hull" {
  // Square corners plus one strictly interior point.
  let pts = of_array([(0, 0), (4, 0), (4, 4), (0, 4), (2, 2)])
  let hull = convex_hull(pts)
  assert_eq(hull.length(), 4)
  assert_true(is_convex_ccw(hull))
  assert_true(all_inside_or_on(pts, hull))
}

test "andrew_hull: duplicate points" {
  // Square corners (some duplicated) plus a duplicated interior point.
  let pts = of_array([
    (0, 0), (4, 0), (4, 4), (0, 4), (0, 0), (4, 4), (2, 2), (2, 2),
  ])
  let hull = convex_hull(pts)
  assert_eq(hull.length(), 4)
  assert_true(has_no_duplicates(hull))
  assert_true(is_convex_ccw(hull))
  assert_true(all_inside_or_on(pts, hull))
}

test "andrew_hull: all identical points" {
  let pts = of_array([(1, 1), (1, 1), (1, 1)])
  let hull = convex_hull(pts)
  assert_eq(hull.length(), 1)
  assert_eq(hull[0], (1, 1))
  assert_true(all_inside_or_on(pts, hull))
}

test "andrew_hull: large random set" {
  let pts : Array[(Int, Int)] = []
  let mut st = 12345
  for i = 0; i < 50; i = i + 1 {
    st = (st * 31 + 7) % 1000003
    let x = st % 100
    st = (st * 31 + 7) % 1000003
    let y = st % 100
    pts.push((x, y))
  }
  let fa = of_array(pts)
  let hull = convex_hull(fa)
  assert_true(hull.length() >= 3)
  assert_true(has_no_duplicates(hull))
  assert_true(is_convex_ccw(hull))
  assert_true(all_inside_or_on(fa, hull))
}

test "andrew_hull: hull is strictly convex (all turns CCW)" {
  // Square corners plus edge midpoints plus an interior point: the collinear
  // edge midpoints must be discarded, leaving exactly the four corners.
  let pts = of_array([
    (0, 0), (6, 0), (6, 6), (0, 6),
    (3, 0), (6, 3), (3, 6), (0, 3), // edge midpoints (collinear)
    (3, 3), // interior
  ])
  let hull = convex_hull(pts)
  assert_eq(hull.length(), 4)
  assert_true(has_no_duplicates(hull))
  assert_true(is_convex_ccw(hull))
  let m = hull.length()
  for i = 0; i < m; i = i + 1 {
    let o = hull[i]
    let a = hull[(i + 1) % m]
    let b = hull[(i + 2) % m]
    assert_true(cross(o, a, b) > 0L)
  }
  assert_true(all_inside_or_on(pts, hull))
}
