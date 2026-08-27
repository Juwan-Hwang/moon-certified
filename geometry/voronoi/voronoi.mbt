/// Voronoi diagram construction via Delaunay triangulation dual.
///
/// The Voronoi diagram of a set of points partitions the plane into cells,
/// where each cell consists of all points closer to one site than to any
/// other. The Voronoi diagram is the geometric dual of the Delaunay
/// triangulation: each Voronoi vertex is the circumcenter of a Delaunay
/// triangle, and each Voronoi edge connects the circumcenters of two adjacent
/// Delaunay triangles.
///
/// ## Algorithm
///
/// 1. Compute the Delaunay triangulation of the input points.
/// 2. For each Delaunay triangle, compute its circumcenter (a Voronoi vertex).
/// 3. For each pair of adjacent Delaunay triangles (sharing an edge), add a
///    Voronoi edge connecting their circumcenters.
///
/// ## Complexity
///
/// - Time: O(n log n) expected for the Delaunay triangulation (randomized
///   incremental Bowyer–Watson with triangle walking) + O(n) for dual
///   construction using an edge hash map.
/// - Space: O(n) for the Voronoi diagram.
///
/// ## Limitations
///
/// - Voronoi vertices are computed as floating-point (`Double`) coordinates
///   because circumcenters generally have non-integer coordinates.
/// - Unbounded cells (cells at the convex hull boundary) produce open Voronoi
///   edges. This implementation reports the Voronoi vertices and edges that
///   are fully determined by the Delaunay triangulation; unbounded edges are
///   reported as half-edges (from a vertex towards infinity).
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

/// Import the Delaunay triangulation module.
/// (We use @delaunay as a sibling package.)

///|
/// A Voronoi vertex (circumcenter of a Delaunay triangle).
pub struct VVertex {
  x : Double
  y : Double
}

///|
/// A Voronoi edge connecting two Voronoi vertices.
/// If `is_bounded` is `false`, the edge extends to infinity from `v0` in the
/// direction of `(dx, dy)`.
pub struct VEdge {
  v0 : Int // Index into the vertex array.
  v1 : Int // Index into the vertex array, or -1 if unbounded.
  is_bounded : Bool
  // For unbounded edges: direction towards infinity.
  dx : Double
  dy : Double
}

///|
/// The Voronoi diagram: vertices and edges.
pub struct VoronoiDiagram {
  vertices : Array[VVertex]
  edges : Array[VEdge]
  /// Number of input sites.
  num_sites : Int
}

///|
/// Absolute value of a double ( avoids depending on `@math.abs`).
fn dbl_abs(x : Double) -> Double {
  if x < 0.0 {
    -x
  } else {
    x
  }
}

///|
/// Compute a canonical hash key for an undirected edge `(a, b)`.
///
/// The key is identical regardless of vertex order, so `edge_key(3, 7)` equals
/// `edge_key(7, 3)`. Vertex indices are packed into a single `Int64` via
/// `(min * 2³² + max)`, which is safe for any realistic input (vertex indices
/// up to 2³¹ − 1).
fn edge_key(a : Int, b : Int) -> Int64 {
  let (lo, hi) = if a < b { (a, b) } else { (b, a) }
  lo.to_int64() * 4294967296L + hi.to_int64()
}

///|
/// Compute the Voronoi diagram of a set of 2D points.
///
/// Internally computes the Delaunay triangulation and constructs its dual.
///
/// # Parameters
/// - `points`: array of 2D points as `@delaunay.DPoint`.
///
/// # Returns
/// A [`VoronoiDiagram`] containing all Voronoi vertices and edges.
pub fn compute(points : Array[@delaunay.DPoint]) -> VoronoiDiagram {
  let n = points.length()
  if n < 3 {
    return { vertices: [], edges: [], num_sites: n, }
  }
  // Step 1: Compute Delaunay triangulation.
  let delaunay_result = @delaunay.triangulate(points)
  if delaunay_result.count == 0 {
    return { vertices: [], edges: [], num_sites: n, }
  }
  // Step 2: For each Delaunay triangle, compute the circumcenter.
  let vertices : Array[VVertex] = []
  // Map from triangle index to vertex index.
  let tri_to_vertex : FixedArray[Int] = FixedArray::make(
    delaunay_result.count,
    -1,
  )
  for i = 0; i < delaunay_result.count; i = i + 1 {
    let v0 = delaunay_result.triangles[i * 3]
    let v1 = delaunay_result.triangles[i * 3 + 1]
    let v2 = delaunay_result.triangles[i * 3 + 2]
    let p0 = points[v0]
    let p1 = points[v1]
    let p2 = points[v2]
    let cc = circumcenter(p0, p1, p2)
    tri_to_vertex[i] = vertices.length()
    vertices.push(cc)
  }
  // Step 3: Find adjacent triangles using an edge hash map — O(T) expected.
  //
  // Each Delaunay triangle has 3 edges. An edge shared by two triangles
  // produces a bounded Voronoi edge (connecting their circumcenters).
  // An edge appearing in only one triangle is on the convex hull boundary,
  // producing an unbounded Voronoi edge.
  //
  // Single pass: for each edge, if it's already in the map we found a shared
  // edge — create a bounded Voronoi edge and remove it from the map. After
  // processing all triangles, remaining map entries are boundary edges.
  let edges : Array[VEdge] = []
  let edge_map : Map[Int64, (Int, Int, Int)] = Map([])
  for i = 0; i < delaunay_result.count; i = i + 1 {
    let i0 = delaunay_result.triangles[i * 3]
    let i1 = delaunay_result.triangles[i * 3 + 1]
    let i2 = delaunay_result.triangles[i * 3 + 2]
    let tri_edges = [(i0, i1), (i1, i2), (i2, i0)]
    for ei = 0; ei < 3; ei = ei + 1 {
      let (a, b) = tri_edges[ei]
      let key = edge_key(a, b)
      match edge_map.get(key) {
        Some((prev_tri, _, _)) => {
          // Shared edge: connect the two circumcenters.
          edges.push({
            v0: tri_to_vertex[prev_tri],
            v1: tri_to_vertex[i],
            is_bounded: true,
            dx: 0.0,
            dy: 0.0,
          })
          edge_map.remove(key)
        }
        None => edge_map[key] = (i, a, b)
      }
    }
  }
  // Remaining edges in edge_map are boundary edges (convex hull).
  // Each produces an unbounded Voronoi edge extending to infinity.
  for k in edge_map.keys() {
    match edge_map.get(k) {
      Some((tri_idx, a, b)) => {
        let cc = vertices[tri_to_vertex[tri_idx]]
        let midx = (points[a].x + points[b].x).to_double() / 2.0
        let midy = (points[a].y + points[b].y).to_double() / 2.0
        // Direction: from midpoint to circumcenter, extended to infinity.
        let dx = cc.x - midx
        let dy = cc.y - midy
        edges.push({
          v0: tri_to_vertex[tri_idx],
          v1: -1,
          is_bounded: false,
          dx,
          dy,
        })
      }
      None => continue
    }
  }
  { vertices, edges, num_sites: n, }
}

///|
/// Compute the circumcenter of a triangle defined by three points.
///
/// The circumcenter is the center of the circle passing through all three
/// vertices. It is the intersection of the perpendicular bisectors of any two
/// edges.
///
/// Uses `Double` arithmetic because the circumcenter generally has
/// non-integer coordinates.
fn circumcenter(
  a : @delaunay.DPoint,
  b : @delaunay.DPoint,
  c : @delaunay.DPoint,
) -> VVertex {
  let ax = a.x.to_double()
  let ay = a.y.to_double()
  let bx = b.x.to_double()
  let by = b.y.to_double()
  let cx = c.x.to_double()
  let cy = c.y.to_double()
  let d = 2.0 * (ax * (by - cy) + bx * (cy - ay) + cx * (ay - by))
  if dbl_abs(d) < 1.0e-20 {
    // Collinear: return a degenerate point.
    return { x: 0.0, y: 0.0, }
  }
  let ux = (
      (ax * ax + ay * ay) * (by - cy) +
      (bx * bx + by * by) * (cy - ay) +
      (cx * cx + cy * cy) * (ay - by)
    ) /
    d
  let uy = (
      (ax * ax + ay * ay) * (cx - bx) +
      (bx * bx + by * by) * (ax - cx) +
      (cx * cx + cy * cy) * (bx - ax)
    ) /
    d
  { x: ux, y: uy, }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "voronoi: fewer than 3 points" {
  let pts = [@delaunay.dpoint(0, 0)]
  let vd = compute(pts)
  assert_eq(vd.vertices.length(), 0)
  assert_eq(vd.edges.length(), 0)
}

///|
test "voronoi: triangle produces one vertex" {
  let pts = [
    @delaunay.dpoint(0, 0),
    @delaunay.dpoint(100, 0),
    @delaunay.dpoint(0, 100),
  ]
  let vd = compute(pts)
  // One Delaunay triangle -> one Voronoi vertex (circumcenter at (50, 50)).
  assert_eq(vd.vertices.length(), 1)
  // The circumcenter of (0,0), (100,0), (0,100) is (50, 50).
  assert_true(dbl_abs(vd.vertices[0].x - 50.0) < 0.001)
  assert_true(dbl_abs(vd.vertices[0].y - 50.0) < 0.001)
}

///|
test "voronoi: square produces two vertices" {
  let pts = [
    @delaunay.dpoint(0, 0),
    @delaunay.dpoint(100, 0),
    @delaunay.dpoint(100, 100),
    @delaunay.dpoint(0, 100),
  ]
  let vd = compute(pts)
  // Two Delaunay triangles -> two Voronoi vertices.
  assert_eq(vd.vertices.length(), 2)
  // The circumcenter of both triangles should be (50, 50) (center of square).
  for i = 0; i < vd.vertices.length(); i = i + 1 {
    assert_true(dbl_abs(vd.vertices[i].x - 50.0) < 0.001)
    assert_true(dbl_abs(vd.vertices[i].y - 50.0) < 0.001)
  }
}

///|
test "voronoi: bounded edges connect vertices" {
  let pts = [
    @delaunay.dpoint(0, 0),
    @delaunay.dpoint(100, 0),
    @delaunay.dpoint(100, 100),
    @delaunay.dpoint(0, 100),
  ]
  let vd = compute(pts)
  // At least one bounded edge (the shared edge between the two triangles).
  let mut has_bounded = false
  for i = 0; i < vd.edges.length(); i = i + 1 {
    if vd.edges[i].is_bounded {
      has_bounded = true
    }
  }
  assert_true(has_bounded)
}

///|
test "voronoi: unbounded edges at boundary" {
  // A triangle has all 3 edges on the convex hull boundary -> 3 unbounded edges.
  let pts = [
    @delaunay.dpoint(0, 0),
    @delaunay.dpoint(100, 0),
    @delaunay.dpoint(0, 100),
  ]
  let vd = compute(pts)
  let mut unbounded_count = 0
  for i = 0; i < vd.edges.length(); i = i + 1 {
    if !vd.edges[i].is_bounded {
      unbounded_count = unbounded_count + 1
    }
  }
  // All 3 edges are on the convex hull -> 3 unbounded Voronoi edges.
  assert_eq(unbounded_count, 3)
}

///|
test "voronoi: circumcenter of right triangle" {
  // Right triangle with right angle at origin.
  // Circumcenter = midpoint of hypotenuse = (50, 50).
  let a = @delaunay.dpoint(0, 0)
  let b = @delaunay.dpoint(100, 0)
  let c = @delaunay.dpoint(0, 100)
  let cc = circumcenter(a, b, c)
  assert_true(dbl_abs(cc.x - 50.0) < 0.001)
  assert_true(dbl_abs(cc.y - 50.0) < 0.001)
}

///|
test "voronoi: collinear points produce no triangles" {
  let pts = [
    @delaunay.dpoint(0, 0),
    @delaunay.dpoint(50, 50),
    @delaunay.dpoint(100, 100),
  ]
  let vd = compute(pts)
  assert_eq(vd.vertices.length(), 0)
}
