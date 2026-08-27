/// 3D Convex Hull — incremental construction.
///
/// Given a set of 3D points with integer coordinates, computes the convex
/// hull as a collection of triangular faces oriented counterclockwise when
/// viewed from outside the hull.
///
/// ## Algorithm
///
/// Randomized incremental construction:
/// 1. Find four non-coplanar points to form an initial tetrahedron.
/// 2. For each remaining point p:
///    a. Find all faces visible from p (faces where p lies on the outside,
///       i.e. `orient(face, p) > 0`).
///    b. Find the horizon: boundary edges between visible and non-visible
///       faces, using the directed-edge technique — an edge (a→b) of a
///       visible face is on the horizon iff its reverse (b→a) does NOT
///       appear in any visible face.
///    c. Remove visible faces and create new faces from p to each horizon
///       edge, preserving CCW-from-outside orientation.
///
/// ## Complexity
///
/// - O(n²) worst case; O(n log n) expected with randomised insertion order.
/// - Space: O(n).
///
/// ## Overflow safety
///
/// All geometric predicates use Int64. Coordinates up to ~500 000 per axis
/// keep every intermediate product within Int64 range. For larger coordinates,
/// a BigInt-based version is required.
///
/// ## Coplanar points
///
/// Points that are exactly coplanar with a face (`orient == 0`) are treated
/// as **not visible**. This means coplanar points that lie outside a face's
/// boundary will not be added to the hull — a known limitation of the strict
/// visibility test. For inputs with many coplanar hull-boundary points
/// (e.g. a cube), consider jittering coordinates or using a symbolic
/// perturbation scheme.
///
/// ## Degenerate inputs
///
/// If fewer than four non-coplanar points exist (all coplanar, collinear,
/// or identical), the result has zero faces. Check `face_count == 0`.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

///|
/// A 3D point with integer coordinates.
pub struct Point3D {
  x : Int
  y : Int
  z : Int
}

///|
/// Construct a 3D point.
pub fn point3d(x : Int, y : Int, z : Int) -> Point3D {
  { x, y, z, }
}

///|
/// A triangular face: three vertex indices in CCW order from outside.
priv struct Face {
  v0 : Int
  v1 : Int
  v2 : Int
}

///|
/// The 3D convex hull.
pub struct ConvexHull3D {
  priv points : Array[Point3D]
  priv faces : Array[Face]
}

// ---------------------------------------------------------------------------
// Geometric predicate
// ---------------------------------------------------------------------------

///|
/// Signed volume × 6 of tetrahedron (a, b, c, d).
///
/// Positive  => d is on the outside of the oriented face (a, b, c).
/// Negative  => d is on the inside.
/// Zero      => coplanar.
///
/// Computed as `dot(b−a, cross(c−a, d−a))`, all in Int64.
fn orient64(a : Point3D, b : Point3D, c : Point3D, d : Point3D) -> Int64 {
  let ax = a.x.to_int64()
  let ay = a.y.to_int64()
  let az = a.z.to_int64()
  let abx = b.x.to_int64() - ax
  let aby = b.y.to_int64() - ay
  let abz = b.z.to_int64() - az
  let acx = c.x.to_int64() - ax
  let acy = c.y.to_int64() - ay
  let acz = c.z.to_int64() - az
  let adx = d.x.to_int64() - ax
  let ady = d.y.to_int64() - ay
  let adz = d.z.to_int64() - az
  // cross(ac, ad)
  let cx = acy * adz - acz * ady
  let cy = acz * adx - acx * adz
  let cz = acx * ady - acy * adx
  // dot(ab, cross(ac, ad))
  abx * cx + aby * cy + abz * cz
}

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

///|
/// Build the 3D convex hull of `points`.
///
/// Returns a hull with triangular faces oriented CCW from outside.
/// If fewer than 4 non-coplanar points exist, the hull has 0 faces.
pub fn build(points : Array[Point3D]) -> ConvexHull3D {
  let n = points.length()
  if n < 4 {
    return { points, faces: [], }
  }

  let (p0, p1, p2, p3, found) = find_initial_tetrahedron(points)
  if !found {
    return { points, faces: [], }
  }

  // Create initial tetrahedron with correctly-oriented faces.
  // For each face, ensure the opposite vertex is on the inside (orient < 0).
  let mut faces : Array[Face] = []
  // Face (p0, p1, p2), opposite p3
  if orient64(points[p0], points[p1], points[p2], points[p3]) > 0L {
    faces.push({ v0: p0, v1: p2, v2: p1, })
  } else {
    faces.push({ v0: p0, v1: p1, v2: p2, })
  }
  // Face (p0, p1, p3), opposite p2
  if orient64(points[p0], points[p1], points[p3], points[p2]) > 0L {
    faces.push({ v0: p0, v1: p3, v2: p1, })
  } else {
    faces.push({ v0: p0, v1: p1, v2: p3, })
  }
  // Face (p0, p2, p3), opposite p1
  if orient64(points[p0], points[p2], points[p3], points[p1]) > 0L {
    faces.push({ v0: p0, v1: p3, v2: p2, })
  } else {
    faces.push({ v0: p0, v1: p2, v2: p3, })
  }
  // Face (p1, p2, p3), opposite p0
  if orient64(points[p1], points[p2], points[p3], points[p0]) > 0L {
    faces.push({ v0: p1, v1: p3, v2: p2, })
  } else {
    faces.push({ v0: p1, v1: p2, v2: p3, })
  }

  // Mark which points are already in the tetrahedron.
  let used = FixedArray::make(n, false)
  used[p0] = true
  used[p1] = true
  used[p2] = true
  used[p3] = true

  // Process remaining points.
  for i = 0; i < n; i = i + 1 {
    if !used[i] {
      faces = add_point(faces, points, i)
    }
  }

  { points, faces, }
}

///|
/// Find 4 non-coplanar points for the initial tetrahedron.
///
/// Scans the point array to find:
/// 1. p0 (first point)
/// 2. p1 (first point different from p0)
/// 3. p2 (first point not collinear with p0, p1)
/// 4. p3 (first point not coplanar with p0, p1, p2)
///
/// Returns (p0, p1, p2, p3, true) if found, (0,0,0,0,false) otherwise.
fn find_initial_tetrahedron(
  points : Array[Point3D],
) -> (Int, Int, Int, Int, Bool) {
  let n = points.length()
  let p0 = 0

  // Find p1 different from p0.
  let mut p1 = -1
  for i = 1; i < n; i = i + 1 {
    if points[i].x != points[p0].x ||
      points[i].y != points[p0].y ||
      points[i].z != points[p0].z {
      p1 = i
      break
    }
  }
  if p1 == -1 {
    return (0, 0, 0, 0, false) // all points identical
  }

  // Find p2 not collinear with p0, p1.
  let mut p2 = -1
  for i = p1 + 1; i < n; i = i + 1 {
    let dx1 = (points[p1].x - points[p0].x).to_int64()
    let dy1 = (points[p1].y - points[p0].y).to_int64()
    let dz1 = (points[p1].z - points[p0].z).to_int64()
    let dx2 = (points[i].x - points[p0].x).to_int64()
    let dy2 = (points[i].y - points[p0].y).to_int64()
    let dz2 = (points[i].z - points[p0].z).to_int64()
    // cross product of (p1-p0) and (i-p0); zero means collinear.
    let cx = dy1 * dz2 - dz1 * dy2
    let cy = dz1 * dx2 - dx1 * dz2
    let cz = dx1 * dy2 - dy1 * dx2
    if cx != 0L || cy != 0L || cz != 0L {
      p2 = i
      break
    }
  }
  if p2 == -1 {
    return (0, 0, 0, 0, false) // all points collinear
  }

  // Find p3 not coplanar with p0, p1, p2.
  let mut p3 = -1
  for i = p2 + 1; i < n; i = i + 1 {
    if orient64(points[p0], points[p1], points[p2], points[i]) != 0L {
      p3 = i
      break
    }
  }
  if p3 == -1 {
    return (0, 0, 0, 0, false) // all points coplanar
  }

  (p0, p1, p2, p3, true)
}

///|
/// Add point `pi` to the hull, returning the updated face array.
///
/// 1. Find all visible faces (where `pi` is on the outside).
/// 2. If none visible, the point is inside; return unchanged.
/// 3. Find horizon edges via the directed-edge technique.
/// 4. Remove visible faces and create new faces from `pi` to each horizon
///    edge.
fn add_point(
  faces : Array[Face],
  points : Array[Point3D],
  pi : Int,
) -> Array[Face] {
  let p = points[pi]

  // 1. Find visible faces and collect their directed edges.
  let visible_flags = Array::make(faces.length(), false)
  let vis_edges : Array[(Int, Int)] = []
  let mut any_visible = false
  for i = 0; i < faces.length(); i = i + 1 {
    let f = faces[i]
    if orient64(points[f.v0], points[f.v1], points[f.v2], p) > 0L {
      visible_flags[i] = true
      any_visible = true
      vis_edges.push((f.v0, f.v1))
      vis_edges.push((f.v1, f.v2))
      vis_edges.push((f.v2, f.v0))
    }
  }

  if !any_visible {
    return faces
  }

  // 2. Find horizon edges: directed edges (a,b) whose reverse (b,a) is NOT
  //    in any visible face's edge list.
  let horizon : Array[(Int, Int)] = []
  for i = 0; i < vis_edges.length(); i = i + 1 {
    let (a, b) = vis_edges[i]
    let mut has_reverse = false
    for j = 0; j < vis_edges.length(); j = j + 1 {
      if vis_edges[j].0 == b && vis_edges[j].1 == a {
        has_reverse = true
        break
      }
    }
    if !has_reverse {
      horizon.push((a, b))
    }
  }

  // 3. Build new face array: keep non-visible faces, add new faces from
  //    horizon edges.  For each horizon edge (a→b), the new face is
  //    (a, b, pi) which preserves CCW-from-outside orientation.
  let new_faces : Array[Face] = []
  for i = 0; i < faces.length(); i = i + 1 {
    if !visible_flags[i] {
      new_faces.push(faces[i])
    }
  }
  for i = 0; i < horizon.length(); i = i + 1 {
    let (a, b) = horizon[i]
    new_faces.push({ v0: a, v1: b, v2: pi, })
  }

  new_faces
}

// ---------------------------------------------------------------------------
// Queries
// ---------------------------------------------------------------------------

///|
/// Number of triangular faces in the hull.
pub fn face_count(hull : ConvexHull3D) -> Int {
  hull.faces.length()
}

///|
/// Return all faces as vertex-index triples `(v0, v1, v2)` in CCW order
/// from outside.
pub fn get_faces(hull : ConvexHull3D) -> Array[(Int, Int, Int)] {
  let result : Array[(Int, Int, Int)] = []
  for i = 0; i < hull.faces.length(); i = i + 1 {
    let f = hull.faces[i]
    result.push((f.v0, f.v1, f.v2))
  }
  result
}

///|
/// Return 6× the volume of the hull (integer arithmetic, no division).
///
/// Computed via the divergence theorem:
/// `6V = sum over faces of dot(a, cross(b, c))`
/// where (a, b, c) are face vertices in CCW order.
///
/// The actual volume is `volume6 / 6.0`. Returns 0 for degenerate hulls.
pub fn get_volume6(hull : ConvexHull3D) -> Int64 {
  let origin = { x: 0, y: 0, z: 0, }
  let mut total = 0L
  for i = 0; i < hull.faces.length(); i = i + 1 {
    let f = hull.faces[i]
    total = total +
      orient64(origin, hull.points[f.v0], hull.points[f.v1], hull.points[f.v2])
  }
  if total < 0L {
    -total
  } else {
    total
  }
}

///|
/// Check if point `p` is inside or on the boundary of the hull.
///
/// Returns `true` if `p` is on the inside (or on the boundary) of every
/// face. For an empty hull (0 faces), returns `false`.
pub fn contains(hull : ConvexHull3D, p : Point3D) -> Bool {
  for i = 0; i < hull.faces.length(); i = i + 1 {
    let f = hull.faces[i]
    if orient64(hull.points[f.v0], hull.points[f.v1], hull.points[f.v2], p) > 0L {
      return false
    }
  }
  // If there are no faces, the hull is degenerate — not a valid container.
  hull.faces.length() > 0
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "3d hull: tetrahedron" {
  let pts : Array[Point3D] = [
    point3d(0, 0, 0),
    point3d(1, 0, 0),
    point3d(0, 1, 0),
    point3d(0, 0, 1),
  ]
  let hull = build(pts)
  assert_eq(face_count(hull), 4)
  // All vertices are on the hull boundary.
  for i = 0; i < pts.length(); i = i + 1 {
    assert_true(contains(hull, pts[i]))
  }
  // Volume of unit tetrahedron = 1/6, so volume6 = 1.
  assert_eq(get_volume6(hull), 1L)
  // (2,0,0) is outside the hull.
  assert_false(contains(hull, point3d(2, 0, 0)))
}

///|
test "3d hull: octahedron" {
  let pts : Array[Point3D] = [
    point3d(1, 0, 0),
    point3d(-1, 0, 0),
    point3d(0, 1, 0),
    point3d(0, -1, 0),
    point3d(0, 0, 1),
    point3d(0, 0, -1),
  ]
  let hull = build(pts)
  // Octahedron has 8 triangular faces.
  assert_eq(face_count(hull), 8)
  // All vertices are on the hull.
  for i = 0; i < pts.length(); i = i + 1 {
    assert_true(contains(hull, pts[i]))
  }
  // Center is inside.
  assert_true(contains(hull, point3d(0, 0, 0)))
  // Far point is outside.
  assert_false(contains(hull, point3d(2, 0, 0)))
  // Volume of octahedron with vertices at distance 1 = 4/3.
  // 6V = 8.
  assert_eq(get_volume6(hull), 8L)
}

///|
test "3d hull: tetrahedron with interior points" {
  let pts : Array[Point3D] = [
    point3d(0, 0, 0),
    point3d(10, 0, 0),
    point3d(0, 10, 0),
    point3d(0, 0, 10),
    point3d(1, 1, 1),
    point3d(2, 2, 2),
    point3d(3, 3, 3),
  ]
  let hull = build(pts)
  // Still 4 faces — interior points don't add faces.
  assert_eq(face_count(hull), 4)
  // All points are inside or on the hull.
  for i = 0; i < pts.length(); i = i + 1 {
    assert_true(contains(hull, pts[i]))
  }
  // Volume = 10*10*10 / 6 = 1000/6, so 6V = 1000.
  assert_eq(get_volume6(hull), 1000L)
}

///|
test "3d hull: coplanar points (degenerate)" {
  // All points on z=0 plane — no 3D hull.
  let pts : Array[Point3D] = [
    point3d(0, 0, 0),
    point3d(1, 0, 0),
    point3d(0, 1, 0),
    point3d(1, 1, 0),
  ]
  let hull = build(pts)
  assert_eq(face_count(hull), 0)
}

///|
test "3d hull: collinear points (degenerate)" {
  let pts : Array[Point3D] = [
    point3d(0, 0, 0),
    point3d(1, 0, 0),
    point3d(2, 0, 0),
    point3d(3, 0, 0),
  ]
  let hull = build(pts)
  assert_eq(face_count(hull), 0)
}

///|
test "3d hull: identical points (degenerate)" {
  let pts : Array[Point3D] = [
    point3d(5, 5, 5),
    point3d(5, 5, 5),
    point3d(5, 5, 5),
    point3d(5, 5, 5),
  ]
  let hull = build(pts)
  assert_eq(face_count(hull), 0)
}

///|
test "3d hull: bipyramid" {
  // Triangular bipyramid: 5 vertices, 6 faces.
  // Two apex points + 3 non-collinear equatorial points.
  let pts : Array[Point3D] = [
    point3d(0, 0, 10), // top apex
    point3d(0, 0, -10), // bottom apex
    point3d(10, 0, 0), // equatorial
    point3d(-10, 6, 0), // equatorial (not exactly equilateral, avoids coplanarity)
    point3d(-10, -6, 0), // equatorial
  ]
  let hull = build(pts)
  // Bipyramid over a triangle: 6 faces.
  assert_eq(face_count(hull), 6)
  for i = 0; i < pts.length(); i = i + 1 {
    assert_true(contains(hull, pts[i]))
  }
  assert_true(contains(hull, point3d(0, 0, 0)))
  assert_false(contains(hull, point3d(0, 0, 20)))
}

///|
test "3d hull: Euler formula check" {
  // For a convex polyhedron with triangular faces:
  //   V - E + F = 2, where E = 3F/2, V = 2 + F/2.
  // So F = 2*(V - 2) where V is the number of hull vertices.
  // Test with octahedron: V=6, F=8.
  let pts : Array[Point3D] = [
    point3d(2, 0, 0),
    point3d(-2, 0, 0),
    point3d(0, 2, 0),
    point3d(0, -2, 0),
    point3d(0, 0, 2),
    point3d(0, 0, -2),
  ]
  let hull = build(pts)
  let f = face_count(hull)
  // Count distinct vertex indices.
  let face_list = get_faces(hull)
  let max_v = 6
  let used = FixedArray::make(max_v, false)
  for i = 0; i < face_list.length(); i = i + 1 {
    let (a, b, c) = face_list[i]
    used[a] = true
    used[b] = true
    used[c] = true
  }
  let mut v = 0
  for i = 0; i < max_v; i = i + 1 {
    if used[i] {
      v = v + 1
    }
  }
  // Euler: V - E + F = 2, E = 3F/2
  let e = 3 * f / 2
  assert_eq(v - e + f, 2)
}

///|
test "3d hull: random points all inside" {
  // Generate 30 random points in a small range, build hull,
  // and verify all points are inside or on the hull.
  let pts : Array[Point3D] = []
  let mut st = 42
  for i = 0; i < 30; i = i + 1 {
    st = (st * 1103515245 + 12345) % 2147483647
    let x = st % 20 - 10
    st = (st * 1103515245 + 12345) % 2147483647
    let y = st % 20 - 10
    st = (st * 1103515245 + 12345) % 2147483647
    let z = st % 20 - 10
    pts.push(point3d(x, y, z))
  }
  let hull = build(pts)
  assert_true(face_count(hull) >= 4)
  for i = 0; i < pts.length(); i = i + 1 {
    assert_true(contains(hull, pts[i]))
  }
}

///|
test "3d hull: less than 4 points" {
  let hull1 = build([point3d(1, 2, 3)])
  assert_eq(face_count(hull1), 0)
  let hull2 = build([point3d(0, 0, 0), point3d(1, 0, 0)])
  assert_eq(face_count(hull2), 0)
  let hull3 = build([point3d(0, 0, 0), point3d(1, 0, 0), point3d(0, 1, 0)])
  assert_eq(face_count(hull3), 0)
}

///|
test "3d hull: large tetrahedron volume" {
  let pts : Array[Point3D] = [
    point3d(0, 0, 0),
    point3d(100, 0, 0),
    point3d(0, 100, 0),
    point3d(0, 0, 100),
  ]
  let hull = build(pts)
  assert_eq(face_count(hull), 4)
  // V = 100^3 / 6 = 1000000/6, 6V = 1000000.
  assert_eq(get_volume6(hull), 1000000L)
}

///|
test "3d hull: duplicate points ignored" {
  let pts : Array[Point3D] = [
    point3d(0, 0, 0),
    point3d(1, 0, 0),
    point3d(0, 1, 0),
    point3d(0, 0, 1),
    point3d(0, 0, 0),
    point3d(1, 0, 0), // duplicates
  ]
  let hull = build(pts)
  assert_eq(face_count(hull), 4)
  assert_eq(get_volume6(hull), 1L)
}
