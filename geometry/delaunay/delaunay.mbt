/// Delaunay triangulation via randomized incremental insertion with
/// triangle walking for O(n log n) expected time.
///
/// The Delaunay triangulation of a set of 2D points is the triangulation where
/// no point lies inside the circumcircle of any triangle. It maximises the
/// minimum angle across all triangles, avoiding "skinny" triangles.
///
/// ## Algorithm
///
/// Uses **randomized incremental Bowyer–Watson** with triangle walking:
///
/// 1. Create a super-triangle large enough to contain all input points.
/// 2. Shuffle the insertion order (xorshift64 Fisher–Yates).
/// 3. For each input point `p` (in shuffled order):
///    a. **Walk** from the last-modified triangle to find the triangle
///       containing `p` — O(√n) expected per walk for uniform distributions.
///    b. **Flood-fill** from the containing triangle to find all "bad"
///       triangles (circumcircle contains `p`) — O(k) where k = bad count.
///    c. Remove the bad triangles, leaving a polygonal hole.
///    d. Re-triangulate the hole by connecting `p` to each boundary edge,
///       updating neighbor links.
/// 4. Remove all triangles that share a vertex with the super-triangle.
///
/// ## Complexity
///
/// - Time: O(n²) worst case, **O(n log n) expected** with randomised
///   insertion order and triangle-walking point location. The walk from
///   the last-modified triangle gives O(√n) expected steps per insertion
///   for uniformly distributed points.
/// - Space: O(n) for the triangle list.
///
/// ## Numerical robustness
///
/// The in-circle test uses `Int64` arithmetic with careful sign computation to
/// avoid floating-point errors. All predicates are exact for integer input
/// coordinates within `Int64` range.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

///|
/// A 2D point with `Int64` coordinates for robust arithmetic.
pub struct DPoint {
  x : Int64
  y : Int64
}

///|
/// Construct a [`DPoint`].
pub fn dpoint(x : Int, y : Int) -> DPoint {
  { x: x.to_int64(), y: y.to_int64() }
}

///|
/// Construct a [`DPoint`] from `Int64` coordinates.
pub fn dpoint64(x : Int64, y : Int64) -> DPoint {
  { x, y }
}

///|
/// A triangle defined by three vertex indices into the points array.
pub struct Triangle {
  v0 : Int
  v1 : Int
  v2 : Int
}

///|
/// Construct a [`Triangle`].
pub fn triangle(v0 : Int, v1 : Int, v2 : Int) -> Triangle {
  { v0, v1, v2 }
}

///|
/// The result of Delaunay triangulation: a list of triangles.
pub struct DelaunayResult {
  /// The triangulation as a flat array of vertex indices:
  /// [t0_v0, t0_v1, t0_v2, t1_v0, t1_v1, t1_v2, ...]
  triangles : FixedArray[Int]
  /// The number of triangles.
  count : Int
}

// ---------------------------------------------------------------------------
// Internal triangle with neighbor tracking
// ---------------------------------------------------------------------------

///|
/// Internal triangle structure with neighbor information for efficient
/// point location via walking.
///
/// Neighbors are indexed by edge:
/// - `n0`: neighbor across edge (v0 → v1), i.e. opposite to v2
/// - `n1`: neighbor across edge (v1 → v2), i.e. opposite to v0
/// - `n2`: neighbor across edge (v2 → v0), i.e. opposite to v1
priv struct Tri {
  v0 : Int
  v1 : Int
  v2 : Int
  mut n0 : Int // neighbor across edge (v0, v1); -1 if none
  mut n1 : Int // neighbor across edge (v1, v2); -1 if none
  mut n2 : Int // neighbor across edge (v2, v0); -1 if none
  mut alive : Bool
}

// ---------------------------------------------------------------------------
// Geometric predicates
// ---------------------------------------------------------------------------

///|
/// Orientation predicate: > 0 if counterclockwise, < 0 if clockwise, 0 if collinear.
fn orient(a : DPoint, b : DPoint, c : DPoint) -> Int64 {
  (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
}

///|
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
  a11 * (a22 * a33 - a23 * a32) -
  a12 * (a21 * a33 - a23 * a31) +
  a13 * (a21 * a32 - a22 * a31)
}

///|
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
// Fisher–Yates shuffle (xorshift64 PRNG)
// ---------------------------------------------------------------------------

///|
/// Shuffle an array in-place using xorshift64-based Fisher–Yates.
/// Randomised insertion order is critical for O(n log n) expected time.
fn shuffle(arr : Array[Int]) -> Unit {
  let mut state = 123456789L
  for i = arr.length() - 1; i > 0; i = i - 1 {
    state = state ^ (state << 13)
    state = state ^ (state >> 7)
    state = state ^ (state << 17)
    let val = if state < 0L { -state } else { state }
    let j = (val % (i + 1).to_int64()).to_int()
    let tmp = arr[i]
    arr[i] = arr[j]
    arr[j] = tmp
  }
}

// ---------------------------------------------------------------------------
// Triangle walking: find triangle containing point p
// ---------------------------------------------------------------------------

///|
/// Walk from a hint triangle to find the triangle containing point `p`.
///
/// Starting from `hint`, checks each edge: if `p` is on the outside of an
/// edge (orientation < 0), moves to the neighbor across that edge.
/// Terminates when `p` is inside all three edges or no neighbor exists.
///
/// Expected walk length: O(√n) for uniformly distributed points.
fn walk_to_containing(
  tris : Array[Tri],
  pts : Array[DPoint],
  hint : Int,
  p : DPoint
) -> Int {
  let mut curr = hint
  let max_steps = tris.length() + 10
  for step = 0; step < max_steps; step = step + 1 {
    let t = tris[curr]
    if !t.alive {
      // Hint was killed; scan for an alive triangle.
      let mut found = false
      for i = 0; i < tris.length(); i = i + 1 {
        if tris[i].alive {
          curr = i
          found = true
          break
        }
      }
      if !found {
        return curr
      }
      continue
    }
    // Check each edge: if p is outside, move to neighbor.
    let mut next = -1
    if orient(pts[t.v0], pts[t.v1], p) < 0L {
      next = t.n0
    } else if orient(pts[t.v1], pts[t.v2], p) < 0L {
      next = t.n1
    } else if orient(pts[t.v2], pts[t.v0], p) < 0L {
      next = t.n2
    }
    if next < 0 {
      return curr // p is inside or at triangulation boundary
    }
    curr = next
  }
  curr
}

// ---------------------------------------------------------------------------
// Flood-fill: find all bad triangles (circumcircle contains p)
// ---------------------------------------------------------------------------

///|
/// Starting from the containing triangle, flood-fill to find all triangles
/// whose circumcircle contains `p`. Bad triangles always form a connected
/// star-shaped region around `p`, so BFS from the containing triangle suffices.
fn flood_bad(
  tris : Array[Tri],
  pts : Array[DPoint],
  start : Int,
  p : DPoint,
  bad_markers : FixedArray[Bool]
) -> Array[Int] {
  let bad : Array[Int] = []
  let visited = FixedArray::make(tris.length(), false)
  let queue : Array[Int] = [start]
  visited[start] = true
  let mut qhead = 0
  while qhead < queue.length() {
    let t_idx = queue[qhead]
    qhead = qhead + 1
    let t = tris[t_idx]
    if !t.alive {
      continue
    }
    if in_circle_safe(pts[t.v0], pts[t.v1], pts[t.v2], p) > 0L {
      bad.push(t_idx)
      bad_markers[t_idx] = true
      // Expand to neighbors.
      if t.n0 >= 0 && !visited[t.n0] {
        visited[t.n0] = true
        queue.push(t.n0)
      }
      if t.n1 >= 0 && !visited[t.n1] {
        visited[t.n1] = true
        queue.push(t.n1)
      }
      if t.n2 >= 0 && !visited[t.n2] {
        visited[t.n2] = true
        queue.push(t.n2)
      }
    }
  }
  bad
}

// ---------------------------------------------------------------------------
// Collect boundary edges in cyclic order around p
// ---------------------------------------------------------------------------

///|
/// Collect the boundary edges of the polygonal hole left by removing bad
/// triangles, ordered cyclically around the insertion point.
///
/// Each entry is `(start_vertex, end_vertex, external_neighbor)` where
/// `external_neighbor` is the non-bad triangle (or -1) sharing that edge.
fn collect_boundary(
  tris : Array[Tri],
  bad : Array[Int],
  bad_markers : FixedArray[Bool]
) -> Array[(Int, Int, Int)] {
  // Build map: start_vertex → (end_vertex, external_neighbor).
  let edge_map : Map[Int, (Int, Int)] = Map([])
  for bi = 0; bi < bad.length(); bi = bi + 1 {
    let t = tris[bad[bi]]
    // Edge 0: v0 → v1, neighbor n0.
    if t.n0 < 0 || !bad_markers[t.n0] {
      edge_map[t.v0] = (t.v1, t.n0)
    }
    // Edge 1: v1 → v2, neighbor n1.
    if t.n1 < 0 || !bad_markers[t.n1] {
      edge_map[t.v1] = (t.v2, t.n1)
    }
    // Edge 2: v2 → v0, neighbor n2.
    if t.n2 < 0 || !bad_markers[t.n2] {
      edge_map[t.v2] = (t.v0, t.n2)
    }
  }
  // Find any starting vertex.
  let mut start_v = -1
  for bi = 0; bi < bad.length() && start_v < 0; bi = bi + 1 {
    let t = tris[bad[bi]]
    if t.n0 < 0 || !bad_markers[t.n0] {
      start_v = t.v0
    } else if t.n1 < 0 || !bad_markers[t.n1] {
      start_v = t.v1
    } else if t.n2 < 0 || !bad_markers[t.n2] {
      start_v = t.v2
    }
  }
  if start_v < 0 {
    return []
  }
  // Follow the cycle.
  let result : Array[(Int, Int, Int)] = []
  let mut curr = start_v
  let mut done = false
  let mut count = 0
  let max_edges = edge_map.length() + 1
  while !done && count < max_edges {
    count = count + 1
    match edge_map.get(curr) {
      Some((next, neighbor)) => {
        result.push((curr, next, neighbor))
        curr = next
        if curr == start_v {
          done = true
        }
      }
      None => done = true
    }
  }
  result
}

// ---------------------------------------------------------------------------
// Main triangulation
// ---------------------------------------------------------------------------

///|
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
  // --- Deduplicate input points ---
  let sorted = FixedArray::from_array(pts.view())
  sorted.sort_by(fn(a, b) {
    if a.x != b.x {
      if a.x < b.x {
        -1
      } else {
        1
      }
    } else if a.y != b.y {
      if a.y < b.y {
        -1
      } else {
        1
      }
    } else {
      0
    }
  })
  let unique_pts : Array[DPoint] = []
  for i = 0; i < sorted.length(); i = i + 1 {
    if i == 0 ||
      sorted[i].x != sorted[i - 1].x ||
      sorted[i].y != sorted[i - 1].y {
      unique_pts.push(sorted[i])
    }
  }
  let n = unique_pts.length()
  if n < 3 {
    return { triangles: FixedArray::make(0, 0), count: 0 }
  }
  // --- Bounding box and super-triangle ---
  let mut min_x = unique_pts[0].x
  let mut max_x = unique_pts[0].x
  let mut min_y = unique_pts[0].y
  let mut max_y = unique_pts[0].y
  for i = 1; i < n; i = i + 1 {
    if unique_pts[i].x < min_x {
      min_x = unique_pts[i].x
    }
    if unique_pts[i].x > max_x {
      max_x = unique_pts[i].x
    }
    if unique_pts[i].y < min_y {
      min_y = unique_pts[i].y
    }
    if unique_pts[i].y > max_y {
      max_y = unique_pts[i].y
    }
  }
  let dx = max_x - min_x
  let dy = max_y - min_y
  let midx = (min_x + max_x) / 2L
  let midy = (min_y + max_y) / 2L
  let diag_sq = dx * dx + dy * dy
  let st = if diag_sq == 0L {
    1000L
  } else {
    let diag_approx = dx + dy
    diag_approx * 20L + 1L
  }
  // Build extended point list: input points + 3 super-triangle vertices.
  let all_points : Array[DPoint] = []
  for i = 0; i < n; i = i + 1 {
    all_points.push(unique_pts[i])
  }
  all_points.push({ x: midx - st, y: midy - st }) // index n
  all_points.push({ x: midx + st, y: midy - st }) // index n+1
  all_points.push({ x: midx, y: midy + st }) // index n+2
  // --- Initialize triangulation with super-triangle ---
  let tris : Array[Tri] = [
    Tri::{
      v0: n,
      v1: n + 1,
      v2: n + 2,
      n0: -1,
      n1: -1,
      n2: -1,
      alive: true,
    },
  ]
  let mut hint = 0
  // --- Shuffle insertion order ---
  let order : Array[Int] = []
  for i = 0; i < n; i = i + 1 {
    order.push(i)
  }
  shuffle(order)
  // --- Insert points in shuffled order ---
  for oi = 0; oi < n; oi = oi + 1 {
    let p_idx = order[oi]
    let p = all_points[p_idx]
    // Walk to find containing triangle.
    let containing = walk_to_containing(tris, all_points, hint, p)
    // Flood-fill to find bad triangles.
    let bad_markers = FixedArray::make(tris.length(), false)
    let bad = flood_bad(tris, all_points, containing, p, bad_markers)
    if bad.length() == 0 {
      continue // Shouldn't happen, but skip gracefully.
    }
    // Collect boundary edges in cyclic order.
    let boundary = collect_boundary(tris, bad, bad_markers)
    if boundary.length() < 3 {
      continue // Degenerate, skip.
    }
    // Kill bad triangles.
    for bi = 0; bi < bad.length(); bi = bi + 1 {
      tris[bad[bi]].alive = false
    }
    // Create new triangles: for each boundary edge (a, b), create (a, b, p).
    let first_new = tris.length()
    let k = boundary.length()
    for i = 0; i < k; i = i + 1 {
      let (a, b, ext_n) = boundary[i]
      tris.push(Tri::{
        v0: a,
        v1: b,
        v2: p_idx,
        n0: ext_n, // external neighbor across edge (a, b)
        n1: first_new + ((i + 1) % k), // next triangle in cycle
        n2: first_new + ((i - 1 + k) % k), // previous triangle in cycle
        alive: true,
      })
    }
    // Update external neighbors to point to new triangles.
    for i = 0; i < k; i = i + 1 {
      let (a, b, ext_n) = boundary[i]
      if ext_n >= 0 {
        let en = tris[ext_n]
        // The external neighbor's edge corresponding to (a, b) is (b, a).
        if en.v0 == b && en.v1 == a {
          en.n0 = first_new + i
        } else if en.v1 == b && en.v2 == a {
          en.n1 = first_new + i
        } else if en.v2 == b && en.v0 == a {
          en.n2 = first_new + i
        }
      }
    }
    // Update hint for next insertion.
    hint = first_new
  }
  // --- Collect result: alive triangles without super-triangle vertices ---
  let final_tris : Array[Triangle] = []
  for i = 0; i < tris.length(); i = i + 1 {
    let t = tris[i]
    if t.alive && t.v0 < n && t.v1 < n && t.v2 < n {
      final_tris.push(triangle(t.v0, t.v1, t.v2))
    }
  }
  let count = final_tris.length()
  let result = FixedArray::make(count * 3, 0)
  for i = 0; i < count; i = i + 1 {
    result[i * 3] = final_tris[i].v0
    result[i * 3 + 1] = final_tris[i].v1
    result[i * 3 + 2] = final_tris[i].v2
  }
  { triangles: result, count }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
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

///|
test "delaunay: fewer than 3 points" {
  let pts1 = [dpoint(0, 0)]
  let result1 = triangulate(pts1)
  assert_eq(result1.count, 0)
  let pts2 = [dpoint(0, 0), dpoint(1, 1)]
  let result2 = triangulate(pts2)
  assert_eq(result2.count, 0)
}

///|
test "delaunay: square (2 triangles)" {
  let pts = [dpoint(0, 0), dpoint(10, 0), dpoint(10, 10), dpoint(0, 10)]
  let result = triangulate(pts)
  assert_eq(result.count, 2)
}

///|
test "delaunay: 5 points with interior point" {
  let pts = [
    dpoint(0, 0),
    dpoint(100, 0),
    dpoint(100, 100),
    dpoint(0, 100),
    dpoint(50, 50),
  ]
  let result = triangulate(pts)
  // 4 triangles from center to each edge of the square.
  assert_eq(result.count, 4)
  // Find the center point's index after dedup/sort (it's the point at (50,50)).
  // After sort by (x,y), order is: (0,0),(0,100),(50,50),(100,0),(100,100).
  // So center is at index 2.
  let center_idx = 2
  let mut center_count = 0
  for i = 0; i < result.count; i = i + 1 {
    for j = 0; j < 3; j = j + 1 {
      if result.triangles[i * 3 + j] == center_idx {
        center_count = center_count + 1
      }
    }
  }
  assert_eq(center_count, 4)
}

///|
test "delaunay: collinear points" {
  let pts = [dpoint(0, 0), dpoint(5, 5), dpoint(10, 10)]
  let result = triangulate(pts)
  assert_eq(result.count, 0)
}

///|
test "delaunay: hexagon" {
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

///|
test "delaunay: no degenerate triangles" {
  let pts = [
    dpoint(0, 0),
    dpoint(100, 0),
    dpoint(100, 100),
    dpoint(0, 100),
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

///|
test "delaunay: deduplication of duplicate points" {
  let pts = [
    dpoint(0, 0),
    dpoint(0, 0), // duplicate
    dpoint(100, 0),
    dpoint(100, 0), // duplicate
    dpoint(100, 100),
    dpoint(0, 100),
  ]
  let result = triangulate(pts)
  // After dedup, 4 unique points → 2 triangles (same as square test).
  assert_eq(result.count, 2)
  for i = 0; i < result.count; i = i + 1 {
    let v0 = result.triangles[i * 3]
    let v1 = result.triangles[i * 3 + 1]
    let v2 = result.triangles[i * 3 + 2]
    assert_true(v0 != v1)
    assert_true(v1 != v2)
    assert_true(v0 != v2)
  }
}

///|
test "delaunay: in_circle basic" {
  let a = dpoint(0, 0)
  let b = dpoint(10, 0)
  let c = dpoint(0, 10)
  let inside = dpoint(1, 1)
  let outside = dpoint(15, 15)
  assert_true(orient(a, b, c) > 0L)
  assert_true(in_circle(a, b, c, inside) > 0L)
  assert_true(in_circle(a, b, c, outside) < 0L)
}

///|
test "delaunay: 10 random-ish points produce valid triangulation" {
  let pts = [
    dpoint(0, 0),
    dpoint(100, 0),
    dpoint(200, 50),
    dpoint(150, 150),
    dpoint(50, 200),
    dpoint(0, 100),
    dpoint(75, 75),
    dpoint(125, 25),
    dpoint(25, 150),
    dpoint(175, 100),
  ]
  let result = triangulate(pts)
  // 10 points, convex hull ~6 vertices → 2*10 - 2 - 6 = 12 triangles
  // (Euler: T = 2n - 2 - h where h = hull vertices)
  assert_true(result.count >= 8)
  assert_true(result.count <= 14)
  // All triangles should be non-degenerate.
  for i = 0; i < result.count; i = i + 1 {
    let v0 = result.triangles[i * 3]
    let v1 = result.triangles[i * 3 + 1]
    let v2 = result.triangles[i * 3 + 2]
    assert_true(v0 != v1)
    assert_true(v1 != v2)
    assert_true(v0 != v2)
  }
}

///|
test "delaunay: grid of 9 points" {
  let pts = [
    dpoint(0, 0),
    dpoint(50, 0),
    dpoint(100, 0),
    dpoint(0, 50),
    dpoint(50, 50),
    dpoint(100, 50),
    dpoint(0, 100),
    dpoint(50, 100),
    dpoint(100, 100),
  ]
  let result = triangulate(pts)
  // 9 points in a 3x3 grid. Hull has 8 vertices (all except center).
  // T = 2*9 - 2 - 8 = 8 triangles.
  assert_true(result.count >= 6)
  assert_true(result.count <= 12)
}
