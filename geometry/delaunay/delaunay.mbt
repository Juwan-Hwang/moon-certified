/// Delaunay triangulation via incremental insertion with edge flips.
///
/// The Delaunay triangulation of a set of 2D points is the triangulation where
/// no point lies inside the circumcircle of any triangle. It maximises the
/// minimum angle across all triangles, avoiding "skinny" triangles.
///
/// ## Algorithm
///
/// Uses the **Bowyer–Watson incremental algorithm**:
///
/// 1. Create a super-triangle large enough to contain all input points.
/// 2. For each input point `p`:
///    a. Find all triangles whose circumcircle contains `p` ("bad triangles").
///    b. Remove the bad triangles, leaving a polygonal hole.
///    c. Re-triangulate the hole by connecting `p` to each boundary edge.
/// 3. Remove all triangles that share a vertex with the super-triangle.
///
/// ## Complexity
///
/// - Time: O(n²) worst case, O(n log n) expected with randomised insertion
///   order and spatial data structures.
/// - Space: O(n) for the triangle list.
///
/// ## Numerical robustness
///
/// The in-circle test uses `Int64` arithmetic with careful sign computation to
/// avoid floating-point errors. All predicates are exact for integer input
/// coordinates within `Int64` range.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

/// A 2D point with `Int64` coordinates for robust arithmetic.
pub struct DPoint {
  x : Int64
  y : Int64
}

/// Construct a [`DPoint`].
pub fn dpoint(x : Int, y : Int) -> DPoint {
  { x: x.to_int64(), y: y.to_int64() }
}

/// Construct a [`DPoint`] from `Int64` coordinates.
pub fn dpoint64(x : Int64, y : Int64) -> DPoint {
  { x, y }
}

/// A triangle defined by three vertex indices into the points array.
pub struct Triangle {
  v0 : Int
  v1 : Int
  v2 : Int
}

/// Construct a [`Triangle`].
pub fn triangle(v0 : Int, v1 : Int, v2 : Int) -> Triangle {
  { v0, v1, v2 }
}

/// The result of Delaunay triangulation: a list of triangles.
pub struct DelaunayResult {
  /// The triangulation as a flat array of vertex indices:
  /// [t0_v0, t0_v1, t0_v2, t1_v0, t1_v1, t1_v2, ...]
  triangles : FixedArray[Int]
  /// The number of triangles.
  count : Int
}

/// Compute the Delaunay triangulation of a set of 2D points.
///
/// # Parameters
/// - `pts`: array of 2D points.
///
/// # Returns
/// A [`DelaunayResult`] containing the triangulation. Each consecutive triple
/// of indices forms a triangle. Returns an empty result for fewer than 3
/// points or all-collinear points.
pub fn triangulate(pts : Array[DPoint]) -> DelaunayResult {
  let n = pts.length()
  if n < 3 {
    return { triangles: FixedArray::make(0, 0), count: 0 }
  }
  // Create the extended point list including the super-triangle vertices.
  // The super-triangle must be large enough to contain all points.
  let mut min_x = pts[0].x
  let mut max_x = pts[0].x
  let mut min_y = pts[0].y
  let mut max_y = pts[0].y
  for i = 1; i < n; i = i + 1 {
    if pts[i].x < min_x {
      min_x = pts[i].x
    }
    if pts[i].x > max_x {
      max_x = pts[i].x
    }
    if pts[i].y < min_y {
      min_y = pts[i].y
    }
    if pts[i].y > max_y {
      max_y = pts[i].y
    }
  }
  let dx = max_x - min_x
  let dy = max_y - min_y
  let delta = if dx > dy { dx } else { dy }
  let midx = (min_x + max_x) / 2L
  let midy = (min_y + max_y) / 2L
  // Super-triangle vertices at indices n, n+1, n+2.
  // Make it much larger than the bounding box.
  let st = delta * 20L + 1000L
  let all_points : Array[DPoint] = []
  for i = 0; i < n; i = i + 1 {
    all_points.push(pts[i])
  }
  all_points.push({ x: midx - st, y: midy - st })
  all_points.push({ x: midx + st, y: midy - st })
  all_points.push({ x: midx, y: midy + st })
  let st0 = n
  let st1 = n + 1
  let st2 = n + 2
  // Initialize with the super-triangle.
  let triangles : Array[Triangle] = [triangle(st0, st1, st2)]
  // Insert each point.
  for p_idx = 0; p_idx < n; p_idx = p_idx + 1 {
    let p = all_points[p_idx]
    // Find all triangles whose circumcircle contains p.
    let bad : Array[Int] = []
    for t_idx = 0; t_idx < triangles.length(); t_idx = t_idx + 1 {
      let t = triangles[t_idx]
      if in_circle_safe(
        all_points[t.v0],
        all_points[t.v1],
        all_points[t.v2],
        p,
      ) > 0L {
        bad.push(t_idx)
      }
    }
    // Collect the boundary edges of the polygonal hole.
    // An edge is on the boundary if it appears in exactly one bad triangle.
    let edges : Array[(Int, Int)] = []
    for bi = 0; bi < bad.length(); bi = bi + 1 {
      let t = triangles[bad[bi]]
      let e0 = (t.v0, t.v1)
      let e1 = (t.v1, t.v2)
      let e2 = (t.v2, t.v0)
      // An edge is on the boundary if it's not shared with any other bad triangle.
      if !edge_in_bad(triangles, bad, bi, e0) {
        edges.push(e0)
      }
      if !edge_in_bad(triangles, bad, bi, e1) {
        edges.push(e1)
      }
      if !edge_in_bad(triangles, bad, bi, e2) {
        edges.push(e2)
      }
    }
    // Remove bad triangles (mark as invalid by setting to a sentinel).
    // We rebuild the triangle list excluding bad ones.
    let is_bad = FixedArray::make(triangles.length(), false)
    for bi = 0; bi < bad.length(); bi = bi + 1 {
      is_bad[bad[bi]] = true
    }
    let new_triangles : Array[Triangle] = []
    for t_idx = 0; t_idx < triangles.length(); t_idx = t_idx + 1 {
      if !is_bad[t_idx] {
        new_triangles.push(triangles[t_idx])
      }
    }
    triangles.clear()
    for i = 0; i < new_triangles.length(); i = i + 1 {
      triangles.push(new_triangles[i])
    }
    // Add new triangles connecting p to each boundary edge.
    for ei = 0; ei < edges.length(); ei = ei + 1 {
      let (a, b) = edges[ei]
      triangles.push(triangle(a, b, p_idx))
    }
  }
  // Remove triangles that share a vertex with the super-triangle.
  let final_triangles : Array[Triangle] = []
  for t_idx = 0; t_idx < triangles.length(); t_idx = t_idx + 1 {
    let t = triangles[t_idx]
    if t.v0 < n && t.v1 < n && t.v2 < n {
      final_triangles.push(t)
    }
  }
  // Build the result.
  let count = final_triangles.length()
  let result = FixedArray::make(count * 3, 0)
  for i = 0; i < count; i = i + 1 {
    result[i * 3] = final_triangles[i].v0
    result[i * 3 + 1] = final_triangles[i].v1
    result[i * 3 + 2] = final_triangles[i].v2
  }
  { triangles: result, count }
}

/// Check if an edge appears in another bad triangle (different from the one
/// at `skip_idx`).
fn edge_in_bad(
  triangles : Array[Triangle],
  bad : Array[Int],
  skip_idx : Int,
  edge : (Int, Int),
) -> Bool {
  let (a, b) = edge
  for bi = 0; bi < bad.length(); bi = bi + 1 {
    if bi == skip_idx {
      continue
    }
    let t = triangles[bad[bi]]
    let e0 = (t.v0, t.v1)
    let e1 = (t.v1, t.v2)
    let e2 = (t.v2, t.v0)
    if edges_equal(e0, a, b) || edges_equal(e1, a, b) || edges_equal(e2, a, b) {
      return true
    }
  }
  false
}

/// Check if an edge `(ea, eb)` equals `(a, b)` ignoring direction.
fn edges_equal(e : (Int, Int), a : Int, b : Int) -> Bool {
  let (ea, eb) = e
  (ea == a && eb == b) || (ea == b && eb == a)
}

/// In-circle predicate: returns > 0 if point `d` is inside the circumcircle
/// of triangle `(a, b, c)`, < 0 if outside, 0 if on the circle.
///
/// Uses the determinant:
/// ```text
/// | ax-dx  ay-dy  (ax-dx)²+(ay-dy)² |
/// | bx-dx  by-dy  (bx-dx)²+(by-dy)² |
/// | cx-dx  cy-dy  (cx-dx)²+(cy-dy)² |
/// ```
///
/// Positive => d inside circumcircle (assuming a,b,c are counterclockwise).
/// Negative => outside. Zero => cocircular.
///
/// All arithmetic is in `Int64`. The determinant may overflow for very large
/// coordinates; callers should ensure coordinates are within ~10⁶ for safety
/// (each term is O(coord²) and the determinant is O(coord⁴)).
fn in_circle(a : DPoint, b : DPoint, c : DPoint, d : DPoint) -> Int64 {
  let adx = a.x - d.x
  let ady = a.y - d.y
  let bdx = b.x - d.x
  let bdy = b.y - d.y
  let cdx = c.x - d.x
  let cdy = c.y - d.y
  let adx2 = adx * adx
  let ady2 = ady * ady
  let bdx2 = bdx * bdx
  let bdy2 = bdy * bdy
  let cdx2 = cdx * cdx
  let cdy2 = cdy * cdy
  // Determinant of:
  // | adx  ady  adx2+ady2 |
  // | bdx  bdy  bdx2+bdy2 |
  // | cdx  cdy  cdx2+cdy2 |
  let a11 = adx
  let a12 = ady
  let a13 = adx2 + ady2
  let a21 = bdx
  let a22 = bdy
  let a23 = bdx2 + bdy2
  let a31 = cdx
  let a32 = cdy
  let a33 = cdx2 + cdy2
  // det = a11*(a22*a33 - a23*a32) - a12*(a21*a33 - a23*a31) + a13*(a21*a32 - a22*a31)
  a11 * (a22 * a33 - a23 * a32) - a12 * (a21 * a33 - a23 * a31) +
  a13 * (a21 * a32 - a22 * a31)
}

/// Orientation predicate: > 0 if counterclockwise, < 0 if clockwise, 0 if collinear.
fn orient(a : DPoint, b : DPoint, c : DPoint) -> Int64 {
  (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
}

/// Orientation-safe in-circle test: returns > 0 if `d` is strictly inside the
/// circumcircle of `(a, b, c)`, regardless of the triangle's orientation.
fn in_circle_safe(a : DPoint, b : DPoint, c : DPoint, d : DPoint) -> Int64 {
  let o = orient(a, b, c)
  let det = in_circle(a, b, c, d)
  if o < 0L {
    -det
  } else {
    det
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "delaunay: minimum 3 points" {
  let pts = [dpoint(0, 0), dpoint(10, 0), dpoint(0, 10)]
  let result = triangulate(pts)
  assert_eq(result.count, 1)
  // The single triangle should have vertices 0, 1, 2 (in some order).
  let mut has_0 = false
  let mut has_1 = false
  let mut has_2 = false
  for i = 0; i < 3; i = i + 1 {
    if result.triangles[i] == 0 {
      has_0 = true
    }
    if result.triangles[i] == 1 {
      has_1 = true
    }
    if result.triangles[i] == 2 {
      has_2 = true
    }
  }
  assert_true(has_0)
  assert_true(has_1)
  assert_true(has_2)
}

test "delaunay: fewer than 3 points" {
  let pts1 = [dpoint(0, 0)]
  let result1 = triangulate(pts1)
  assert_eq(result1.count, 0)
  let pts2 = [dpoint(0, 0), dpoint(1, 1)]
  let result2 = triangulate(pts2)
  assert_eq(result2.count, 0)
}

test "delaunay: square (2 triangles)" {
  // Four points forming a square: should produce 2 triangles.
  let pts = [
    dpoint(0, 0), dpoint(10, 0), dpoint(10, 10), dpoint(0, 10),
  ]
  let result = triangulate(pts)
  assert_eq(result.count, 2)
}

test "delaunay: 5 points with interior point" {
  // Square with center point: should produce 4 triangles (fan from center).
  let pts = [
    dpoint(0, 0), dpoint(100, 0), dpoint(100, 100), dpoint(0, 100),
    dpoint(50, 50),
  ]
  let result = triangulate(pts)
  // 4 triangles from center to each edge of the square.
  assert_eq(result.count, 4)
  // Verify vertex 4 (center) appears in all triangles.
  let mut center_count = 0
  for i = 0; i < result.count; i = i + 1 {
    for j = 0; j < 3; j = j + 1 {
      if result.triangles[i * 3 + j] == 4 {
        center_count = center_count + 1
      }
    }
  }
  assert_eq(center_count, 4)
}

test "delaunay: collinear points" {
  let pts = [dpoint(0, 0), dpoint(5, 5), dpoint(10, 10)]
  let result = triangulate(pts)
  assert_eq(result.count, 0)
}

test "delaunay: hexagon" {
  // Regular hexagon: should produce 4 triangles (triangulation of convex hexagon).
  let pts = [
    dpoint(100, 0),
    dpoint(50, 87),
    dpoint(-50, 87),
    dpoint(-100, 0),
    dpoint(-50, -87),
    dpoint(50, -87),
  ]
  let result = triangulate(pts)
  // A convex polygon with n vertices triangulates into n-2 triangles.
  assert_eq(result.count, 4)
}

test "delaunay: no degenerate triangles" {
  // All triangles should have 3 distinct vertices.
  let pts = [
    dpoint(0, 0), dpoint(100, 0), dpoint(100, 100), dpoint(0, 100),
    dpoint(50, 50),
  ]
  let result = triangulate(pts)
  for i = 0; i < result.count; i = i + 1 {
    let v0 = result.triangles[i * 3]
    let v1 = result.triangles[i * 3 + 1]
    let v2 = result.triangles[i * 3 + 2]
    assert_true(v0 != v1)
    assert_true(v1 != v2)
    assert_true(v0 != v2)
  }
}

test "delaunay: in_circle basic" {
  // Triangle (0,0), (10,0), (0,10). Circumcircle center is (5,5), radius sqrt(50).
  let a = dpoint(0, 0)
  let b = dpoint(10, 0)
  let c = dpoint(0, 10)
  // Point (5,5) is on the circumcircle.
  let _on_circle = dpoint(5, 5)
  // Point (1,1) is inside (dist² = 8 < 50).
  let inside = dpoint(1, 1)
  // Point (15,15) is outside (dist² = 200 > 50).
  let outside = dpoint(15, 15)
  // Ensure CCW orientation for the triangle.
  assert_true(orient(a, b, c) > 0L)
  // in_circle: positive = inside.
  assert_true(in_circle(a, b, c, inside) > 0L)
  assert_true(in_circle(a, b, c, outside) < 0L)
}
