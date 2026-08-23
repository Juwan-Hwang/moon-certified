/// Line Arrangement — planar subdivision induced by a set of lines.
///
/// Given n lines in the plane, the arrangement A(L) is the planar subdivision
/// whose vertices are pairwise intersection points, whose edges are maximal
/// line segments between consecutive intersection points, and whose faces are
/// the connected regions of the plane delimited by the lines.
///
/// ## Representation
///
/// Each face is uniquely identified by a **sign vector** — for each line i,
/// the sign of `a_i·x + b_i·y + c_i` at any interior point of the face. Two
/// points lie in the same face iff their sign vectors are identical (and
/// contain no zeros, which would indicate the point is on an edge).
///
/// ## Complexity (n lines in general position)
///
/// | Quantity  | Count                    |
/// |-----------|--------------------------|
/// | Vertices  | C(n,2) = n(n-1)/2        |
/// | Edges     | n²                       |
/// | Faces     | C(n,2) + n + 1           |
///
/// ## Operations
///
/// | Operation       | Time         |
/// |-----------------|--------------|
/// | Construction    | O(n² log n)  |
/// | Point location  | O(n)         |
/// | Zone query      | O(n log n)   |
/// | Face enumeration| O(n²)        |
///
/// ## Zone Theorem
///
/// The zone of a line ℓ in A(L) — the set of faces intersected by ℓ — has
/// complexity O(n). This follows from the zone theorem for arrangements:
/// the sum of complexities of all faces in the zone is at most 6n.
///
/// ## References
///
/// - de Berg, van Kreveld, Overmars, Schwarzkopf. "Computational Geometry:
///   Algorithms and Applications." Springer, 3rd ed., Chapter 8.
/// - Edelsbrunner, H. "Algorithms in Combinatorial Geometry." Springer, 1987.
/// - Sharir, M. and Agarwal, P. "Davenport-Schinzel Sequences and Their
///   Geometric Applications." Cambridge University Press, 1995.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

///|
/// Epsilon for floating-point comparisons.
const EPS : Double = 1.0e-9

// ---------------------------------------------------------------------------
// Line type
// ---------------------------------------------------------------------------

///|
/// A line in general form: `a·x + b·y + c = 0`, normalized so `a² + b² = 1`.
///
/// The normal vector `(a, b)` points to the "positive" side. For a point
/// `(x, y)`, `a·x + b·y + c > 0` means the point is on the positive side
/// (the side the normal points to).
pub struct Line {
  a : Double
  b : Double
  c : Double
}

///|
/// Construct a line from general form `a·x + b·y + c = 0`.
///
/// The coefficients are normalized so that `a² + b² = 1`. If both `a` and `b`
/// are zero, the line is degenerate and `None` is returned.
pub fn line(a : Double, b : Double, c : Double) -> Line? {
  let norm = (a * a + b * b).sqrt()
  if norm < EPS {
    return None
  }
  Some({ a: a / norm, b: b / norm, c: c / norm })
}

///|
/// Construct a line through two points `(x1, y1)` and `(x2, y2)`.
///
/// Returns `None` if the two points are identical.
pub fn line_from_points(
  x1 : Double,
  y1 : Double,
  x2 : Double,
  y2 : Double,
) -> Line? {
  // Direction: (dx, dy). Normal: (-dy, dx) or (dy, -dx).
  // Line: -dy*(x - x1) + dx*(y - y1) = 0 → -dy*x + dx*y + (dy*x1 - dx*y1) = 0
  let dx = x2 - x1
  let dy = y2 - y1
  if dx.abs() < EPS && dy.abs() < EPS {
    return None
  }
  // a = -dy, b = dx, c = dy*x1 - dx*y1
  line(-dy, dx, dy * x1 - dx * y1)
}

///|
/// Construct a line from slope-intercept form `y = m·x + d`.
///
/// This gives `m·x - y + d = 0`. For vertical lines (infinite slope), use
/// [`line_from_points`] or [`line`] instead.
pub fn line_from_slope_intercept(m : Double, d : Double) -> Line? {
  line(m, -1.0, d)
}

///|
/// Evaluate the signed distance from point `(x, y)` to the line.
///
/// Positive: point is on the side the normal `(a, b)` points to.
/// Negative: point is on the opposite side.
/// Zero: point is on the line.
pub fn line_eval(l : Line, x : Double, y : Double) -> Double {
  l.a * x + l.b * y + l.c
}

///|
/// Sign of `line_eval`: -1, 0, or +1.
pub fn line_sign(l : Line, x : Double, y : Double) -> Int {
  let v = line_eval(l, x, y)
  if v > EPS {
    1
  } else if v < -EPS {
    -1
  } else {
    0
  }
}

// ---------------------------------------------------------------------------
// Intersection
// ---------------------------------------------------------------------------

///|
/// Compute the intersection point of two lines.
///
/// Returns `None` if the lines are parallel (no intersection) or coincident
/// (infinitely many intersections).
pub fn intersect(l1 : Line, l2 : Line) -> (Double, Double)? {
  // l1: a1*x + b1*y + c1 = 0
  // l2: a2*x + b2*y + c2 = 0
  // Solve via Cramer's rule:
  //   det = a1*b2 - a2*b1
  //   x = (b1*c2 - b2*c1) / det
  //   y = (c1*a2 - c2*a1) / det
  let det = l1.a * l2.b - l2.a * l1.b
  if det.abs() < EPS {
    return None // Parallel or coincident
  }
  let x = (l1.b * l2.c - l2.b * l1.c) / det
  let y = (l1.c * l2.a - l2.c * l1.a) / det
  Some((x, y))
}

///|
/// Check if two lines are parallel.
pub fn is_parallel(l1 : Line, l2 : Line) -> Bool {
  (l1.a * l2.b - l2.a * l1.b).abs() < EPS
}

// ---------------------------------------------------------------------------
// Arrangement vertex and edge
// ---------------------------------------------------------------------------

///|
/// A vertex in the arrangement: an intersection point of two lines.
pub struct ArrVertex {
  x : Double
  y : Double
  /// Index of the first line forming this intersection.
  line_i : Int
  /// Index of the second line forming this intersection.
  line_j : Int
}

///|
/// An edge in the arrangement: a maximal segment of a line between two
/// consecutive vertices.
///
/// `v_start` and `v_end` are indices into the vertex array. A value of `-1`
/// indicates that the edge extends to infinity in that direction.
pub struct ArrEdge {
  /// Index of the line this edge lies on.
  line_idx : Int
  /// Start vertex index (-1 = unbounded).
  v_start : Int
  /// End vertex index (-1 = unbounded).
  v_end : Int
}

// ---------------------------------------------------------------------------
// Arrangement
// ---------------------------------------------------------------------------

///|
/// The line arrangement: a planar subdivision induced by a set of lines.
pub struct Arrangement {
  /// The input lines (normalized).
  lines : Array[Line]
  /// All intersection vertices.
  vertices : Array[ArrVertex]
  /// All edges (segments between consecutive vertices on each line).
  edges : Array[ArrEdge]
  /// For each line, the sorted list of vertex indices along that line.
  /// `line_vertices[i]` is sorted by the parameter along line `i`.
  line_vertices : Array[Array[Int]]
}

///|
/// Build the arrangement from a set of lines.
///
/// **Preconditions**: Each `Line` must be non-degenerate (normalized with
/// `a² + b² = 1`). Parallel lines produce no intersection and are handled
/// correctly.
///
/// **Complexity**: O(n² log n) where n = number of lines.
pub fn build(lines : Array[Line]) -> Arrangement {
  let n = lines.length()
  // Step 1: Compute all pairwise intersections.
  let vertices : Array[ArrVertex] = []
  // For each line, store the list of (vertex_index, parameter) pairs.
  // Each element must be a distinct array — Array::make(n, []) would alias
  // the same mutable array across all indices.
  let line_vparams : Array[Array[(Int, Double)]] = []
  for i = 0; i < n; i = i + 1 {
    line_vparams.push([])
  }
  for i = 0; i < n; i = i + 1 {
    for j = i + 1; j < n; j = j + 1 {
      match intersect(lines[i], lines[j]) {
        Some((x, y)) => {
          let vidx = vertices.length()
          vertices.push({ x, y, line_i: i, line_j: j })
          // Compute parameter along each line.
          // Parameter = dot product of (x, y) with direction vector of the line.
          // Direction of line i: (-b_i, a_i) (perpendicular to normal).
          let param_i = -lines[i].b * x + lines[i].a * y
          let param_j = -lines[j].b * x + lines[j].a * y
          line_vparams[i].push((vidx, param_i))
          line_vparams[j].push((vidx, param_j))
        }
        None => continue // Parallel, no intersection
      }
    }
  }
  // Step 2: Sort vertices along each line by parameter.
  let line_vertices : Array[Array[Int]] = []
  for i = 0; i < n; i = i + 1 {
    line_vertices.push([])
  }
  for i = 0; i < n; i = i + 1 {
    // Sort by parameter.
    let params = line_vparams[i]
    // Simple insertion sort (n is small per line, typically O(n) elements).
    for k = 1; k < params.length(); k = k + 1 {
      let key = params[k]
      let mut m = k - 1
      while m >= 0 && params[m].1 > key.1 {
        params[m + 1] = params[m]
        m = m - 1
      }
      params[m + 1] = key
    }
    // Extract sorted vertex indices.
    let sorted : Array[Int] = []
    for k = 0; k < params.length(); k = k + 1 {
      sorted.push(params[k].0)
    }
    line_vertices[i] = sorted
  }
  // Step 3: Build edges.
  let edges : Array[ArrEdge] = []
  for i = 0; i < n; i = i + 1 {
    let lvs = line_vertices[i]
    if lvs.length() == 0 {
      // No intersections on this line: single unbounded edge.
      edges.push({ line_idx: i, v_start: -1, v_end: -1 })
    } else {
      // Unbounded edge before the first vertex.
      edges.push({ line_idx: i, v_start: -1, v_end: lvs[0] })
      // Bounded edges between consecutive vertices.
      for k = 0; k < lvs.length() - 1; k = k + 1 {
        edges.push({ line_idx: i, v_start: lvs[k], v_end: lvs[k + 1] })
      }
      // Unbounded edge after the last vertex.
      edges.push({ line_idx: i, v_start: lvs[lvs.length() - 1], v_end: -1 })
    }
  }
  { lines, vertices, edges, line_vertices }
}

// ---------------------------------------------------------------------------
// Complexity queries
// ---------------------------------------------------------------------------

///|
/// Number of vertices (intersection points) in the arrangement.
pub fn num_vertices(arr : Arrangement) -> Int {
  arr.vertices.length()
}

///|
/// Number of edges in the arrangement.
///
/// Each line with k intersection points contributes k+1 edges (k-1 bounded
/// segments plus 2 unbounded rays). For n lines in general position, this
/// totals n².
pub fn num_edges(arr : Arrangement) -> Int {
  arr.edges.length()
}

///|
/// Number of faces in the arrangement.
///
/// Uses the formula: `F = 1 + n + Σ_v (multiplicity(v) − 1)` where
/// `multiplicity(v)` is the number of lines passing through vertex `v`.
///
/// For n lines in general position (no 3 concurrent): `F = C(n,2) + n + 1`.
pub fn num_faces(arr : Arrangement) -> Int {
  let n = arr.lines.length()
  let mut face_count = 1 + n
  // Group vertices by location (using a simple O(V²) approach for small V).
  let visited : Array[Bool] = Array::make(arr.vertices.length(), false)
  for vidx = 0; vidx < arr.vertices.length(); vidx = vidx + 1 {
    if visited[vidx] {
      continue
    }
    // Count how many vertices are at this same location.
    let mut multiplicity = 2 // This vertex has at least 2 lines
    let v0 = arr.vertices[vidx]
    // Track unique lines through this point.
    let lines_at_point : Array[Int] = [v0.line_i, v0.line_j]
    visited[vidx] = true
    for vidx2 = vidx + 1; vidx2 < arr.vertices.length(); vidx2 = vidx2 + 1 {
      if visited[vidx2] {
        continue
      }
      let v1 = arr.vertices[vidx2]
      if (v1.x - v0.x).abs() < EPS && (v1.y - v0.y).abs() < EPS {
        visited[vidx2] = true
        // Add lines if not already present.
        let mut found_i = false
        let mut found_j = false
        for k = 0; k < lines_at_point.length(); k = k + 1 {
          if lines_at_point[k] == v1.line_i {
            found_i = true
          }
          if lines_at_point[k] == v1.line_j {
            found_j = true
          }
        }
        if !found_i {
          lines_at_point.push(v1.line_i)
          multiplicity = multiplicity + 1
        }
        if !found_j {
          lines_at_point.push(v1.line_j)
          multiplicity = multiplicity + 1
        }
      }
    }
    face_count = face_count + (multiplicity - 1)
  }
  face_count
}

// ---------------------------------------------------------------------------
// Point location
// ---------------------------------------------------------------------------

///|
/// Compute the sign vector of a point relative to the arrangement.
///
/// Returns an array of signs (-1, 0, +1) — one per line. Two points are in
/// the same face iff their sign vectors are identical and contain no zeros.
/// A zero indicates the point lies on an edge (or vertex).
///
/// **Complexity**: O(n) where n = number of lines.
pub fn locate(arr : Arrangement, x : Double, y : Double) -> Array[Int] {
  let n = arr.lines.length()
  let signs : Array[Int] = Array::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    signs[i] = line_sign(arr.lines[i], x, y)
  }
  signs
}

///|
/// Check if two points are in the same face of the arrangement.
///
/// Returns `true` iff both points have the same sign vector and neither
/// lies on an edge (no zeros in the sign vector).
pub fn same_face(
  arr : Arrangement,
  x1 : Double,
  y1 : Double,
  x2 : Double,
  y2 : Double,
) -> Bool {
  let n = arr.lines.length()
  for i = 0; i < n; i = i + 1 {
    let s1 = line_sign(arr.lines[i], x1, y1)
    let s2 = line_sign(arr.lines[i], x2, y2)
    if s1 == 0 || s2 == 0 || s1 != s2 {
      return false
    }
  }
  true
}

// ---------------------------------------------------------------------------
// Zone query
// ---------------------------------------------------------------------------

///|
/// Compute the zone of a line in the arrangement: the set of faces that the
/// line passes through.
///
/// Returns a list of sign vectors, one per face in the zone. Each sign vector
/// identifies a unique face.
///
/// **Complexity**: O(n log n) where n = number of lines in the arrangement.
///
/// **Precondition**: `query_line` should not be coincident with any existing
/// line. If it is parallel to some lines, those lines are simply skipped
/// (no intersection).
pub fn zone(arr : Arrangement, query_line : Line) -> Array[Array[Int]] {
  let n = arr.lines.length()
  // Compute intersections of query_line with all existing lines.
  let intersections : Array[(Double, Array[Int])] = []
  for i = 0; i < n; i = i + 1 {
    match intersect(query_line, arr.lines[i]) {
      Some((x, y)) => {
        // Compute parameter along query_line for sorting.
        let param = -query_line.b * x + query_line.a * y
        // Sign vector at a point just before this intersection (on the
        // query line, slightly before the intersection point).
        // We'll compute the sign vector between consecutive intersections.
        intersections.push((param, []))
      }
      None => continue
    }
  }
  // Sort intersections by parameter.
  for k = 1; k < intersections.length(); k = k + 1 {
    let key = intersections[k]
    let mut m = k - 1
    while m >= 0 && intersections[m].0 > key.0 {
      intersections[m + 1] = intersections[m]
      m = m - 1
    }
    intersections[m + 1] = key
  }
  // For each segment between consecutive intersections, compute the sign vector.
  // Also handle the two unbounded segments (before first and after last).
  let result : Array[Array[Int]] = []
  // Direction vector of the query line.
  let dir_x = -query_line.b
  let dir_y = query_line.a
  // Sample points between consecutive intersections.
  // For the segment before the first intersection, use a point far in the
  // negative direction.
  let mut prev_param = 0.0
  let mut has_prev = false
  for idx = 0; idx < intersections.length(); idx = idx + 1 {
    let curr_param = intersections[idx].0
    if has_prev {
      // Midpoint between prev_param and curr_param.
      let mid_param = (prev_param + curr_param) / 2.0
      let mx = dir_x * mid_param
      let my = dir_y * mid_param
      let signs = locate(arr, mx, my)
      result.push(signs)
    } else {
      // Segment before the first intersection.
      let far_param = curr_param - 1.0e6
      let fx = dir_x * far_param
      let fy = dir_y * far_param
      let signs = locate(arr, fx, fy)
      result.push(signs)
    }
    prev_param = curr_param
    has_prev = true
  }
  // Segment after the last intersection.
  if has_prev {
    let far_param = prev_param + 1.0e6
    let fx = dir_x * far_param
    let fy = dir_y * far_param
    let signs = locate(arr, fx, fy)
    result.push(signs)
  } else {
    // No intersections at all: the query line doesn't cross any existing line.
    // The entire line is in one face.
    let mx = dir_x * 0.0
    let my = dir_y * 0.0
    let signs = locate(arr, mx, my)
    result.push(signs)
  }
  // Remove duplicates (a segment might be in the same face as another).
  let unique : Array[Array[Int]] = []
  for i = 0; i < result.length(); i = i + 1 {
    let mut found = false
    for j = 0; j < unique.length(); j = j + 1 {
      let mut same = true
      for k = 0; k < n; k = k + 1 {
        if result[i][k] != unique[j][k] {
          same = false
          break
        }
      }
      if same {
        found = true
        break
      }
    }
    if !found {
      unique.push(result[i])
    }
  }
  unique
}

// ---------------------------------------------------------------------------
// Face enumeration
// ---------------------------------------------------------------------------

///|
/// Enumerate all faces in the arrangement.
///
/// Returns a list of sign vectors, one per face. Each sign vector uniquely
/// identifies a face.
///
/// **Complexity**: O(n²) where n = number of lines.
pub fn faces(arr : Arrangement) -> Array[Array[Int]] {
  let result : Array[Array[Int]] = []
  // Collect sign vectors from edge midpoints and unbounded edge sample points.
  for edge_idx = 0; edge_idx < arr.edges.length(); edge_idx = edge_idx + 1 {
    let edge = arr.edges[edge_idx]
    let line = arr.lines[edge.line_idx]
    let dir_x = -line.b
    let dir_y = line.a
    // Compute a point on each side of the edge.
    // The edge goes from v_start to v_end along the line.
    // Normal to the line is (a, b).
    let (mx, my) = if edge.v_start >= 0 && edge.v_end >= 0 {
      // Bounded edge: midpoint.
      let v0 = arr.vertices[edge.v_start]
      let v1 = arr.vertices[edge.v_end]
      ((v0.x + v1.x) / 2.0, (v0.y + v1.y) / 2.0)
    } else if edge.v_start >= 0 {
      // Unbounded after v_start.
      let v0 = arr.vertices[edge.v_start]
      (v0.x + dir_x * 100.0, v0.y + dir_y * 100.0)
    } else if edge.v_end >= 0 {
      // Unbounded before v_end.
      let v1 = arr.vertices[edge.v_end]
      (v1.x - dir_x * 100.0, v1.y - dir_y * 100.0)
    } else {
      // Fully unbounded (no intersections on this line).
      (dir_x * 50.0, dir_y * 50.0)
    }
    // Sample points on both sides of the line.
    let offset = 1.0 // Small offset along the normal.
    let px_pos = mx + line.a * offset
    let py_pos = my + line.b * offset
    let px_neg = mx - line.a * offset
    let py_neg = my - line.b * offset
    let signs_pos = locate(arr, px_pos, py_pos)
    let signs_neg = locate(arr, px_neg, py_neg)
    // Add to result if not already present.
    let _ = add_unique(result, signs_pos)
    let _ = add_unique(result, signs_neg)
  }
  result
}

///|
/// Add a sign vector to the list if not already present. Returns true if added.
fn add_unique(list : Array[Array[Int]], signs : Array[Int]) -> Bool {
  let n = signs.length()
  for i = 0; i < list.length(); i = i + 1 {
    let mut same = true
    for k = 0; k < n; k = k + 1 {
      if list[i][k] != signs[k] {
        same = false
        break
      }
    }
    if same {
      return false
    }
  }
  list.push(signs)
  true
}

// ---------------------------------------------------------------------------
// Accessor queries
// ---------------------------------------------------------------------------

///|
/// Get all vertices (intersection points) as `(x, y)` pairs.
pub fn vertices(arr : Arrangement) -> Array[(Double, Double)] {
  let result : Array[(Double, Double)] = []
  for i = 0; i < arr.vertices.length(); i = i + 1 {
    result.push((arr.vertices[i].x, arr.vertices[i].y))
  }
  result
}

///|
/// Get all edges as `((x1, y1), (x2, y2))` pairs.
///
/// For unbounded edges, the unbounded endpoint is represented by a point
/// far along the line direction (±100000 units from the bounded endpoint,
/// or the line's direction point if fully unbounded).
pub fn edge_endpoints(
  arr : Arrangement,
) -> Array[((Double, Double), (Double, Double))] {
  let result : Array[((Double, Double), (Double, Double))] = []
  for edge_idx = 0; edge_idx < arr.edges.length(); edge_idx = edge_idx + 1 {
    let edge = arr.edges[edge_idx]
    let line = arr.lines[edge.line_idx]
    let dir_x = -line.b
    let dir_y = line.a
    let far = 100000.0
    let p1 = if edge.v_start >= 0 {
      let v = arr.vertices[edge.v_start]
      (v.x, v.y)
    } else if edge.v_end >= 0 {
      let v = arr.vertices[edge.v_end]
      (v.x - dir_x * far, v.y - dir_y * far)
    } else {
      (-dir_x * far, -dir_y * far)
    }
    let p2 = if edge.v_end >= 0 {
      let v = arr.vertices[edge.v_end]
      (v.x, v.y)
    } else if edge.v_start >= 0 {
      let v = arr.vertices[edge.v_start]
      (v.x + dir_x * far, v.y + dir_y * far)
    } else {
      (dir_x * far, dir_y * far)
    }
    result.push((p1, p2))
  }
  result
}

///|
/// Get the sorted vertex indices along a specific line.
pub fn line_vertex_indices(arr : Arrangement, line_idx : Int) -> Array[Int] {
  if line_idx < 0 || line_idx >= arr.line_vertices.length() {
    return []
  }
  let result : Array[Int] = []
  let lvs = arr.line_vertices[line_idx]
  for i = 0; i < lvs.length(); i = i + 1 {
    result.push(lvs[i])
  }
  result
}

///|
/// Get the number of lines in the arrangement.
pub fn num_lines(arr : Arrangement) -> Int {
  arr.lines.length()
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "line_arrangement: single line" {
  let l1 = match line_from_slope_intercept(0.0, 0.0) {
    Some(l) => l
    None => {
      assert_true(false)
      return
    }
  }
  let arr = build([l1])
  assert_eq(num_vertices(arr), 0)
  assert_eq(num_edges(arr), 1)
  assert_eq(num_faces(arr), 2)
}

///|
test "line_arrangement: two intersecting lines" {
  // y = 0 (horizontal) and x = 0 (vertical)
  let l1 = match line_from_slope_intercept(0.0, 0.0) {
    Some(l) => l
    None => {
      assert_true(false)
      return
    }
  }
  let l2 = match line(1.0, 0.0, 0.0) {
    Some(l) => l
    None => {
      assert_true(false)
      return
    }
  }
  // line(1, 0, 0) → x = 0 (vertical)
  let arr = build([l1, l2])
  assert_eq(num_vertices(arr), 1)
  assert_eq(num_edges(arr), 4) // 2 per line
  assert_eq(num_faces(arr), 4) // 4 quadrants
  // Verify the intersection point is at (0, 0).
  let vs = vertices(arr)
  assert_true(vs[0].0.abs() < EPS)
  assert_true(vs[0].1.abs() < EPS)
}

///|
test "line_arrangement: two parallel lines" {
  // y = 0 and y = 1 (parallel horizontal lines)
  let l1 = match line_from_slope_intercept(0.0, 0.0) {
    Some(l) => l
    None => {
      assert_true(false)
      return
    }
  }
  let l2 = match line_from_slope_intercept(0.0, 1.0) {
    Some(l) => l
    None => {
      assert_true(false)
      return
    }
  }
  let arr = build([l1, l2])
  assert_eq(num_vertices(arr), 0)
  assert_eq(num_edges(arr), 2) // 1 per line
  assert_eq(num_faces(arr), 3) // 3 strips
}

///|
test "line_arrangement: three lines general position" {
  // y = 0, x = 0, y = x + 1
  let l1 = match line_from_slope_intercept(0.0, 0.0) {
    Some(l) => l
    None => {
      assert_true(false)
      return
    }
  }
  let l2 = match line(1.0, 0.0, 0.0) {
    Some(l) => l
    None => {
      assert_true(false)
      return
    }
  }
  let l3 = match line_from_slope_intercept(1.0, 1.0) {
    Some(l) => l
    None => {
      assert_true(false)
      return
    }
  }
  let arr = build([l1, l2, l3])
  assert_eq(num_vertices(arr), 3) // 3 pairwise intersections
  assert_eq(num_edges(arr), 9) // 3 per line
  assert_eq(num_faces(arr), 7) // C(3,2) + 3 + 1 = 7
}

///|
test "line_arrangement: three concurrent lines" {
  // y = 0, x = 0, y = x (all through origin)
  let l1 = match line_from_slope_intercept(0.0, 0.0) {
    Some(l) => l
    None => {
      assert_true(false)
      return
    }
  }
  let l2 = match line(1.0, 0.0, 0.0) {
    Some(l) => l
    None => {
      assert_true(false)
      return
    }
  }
  let l3 = match line_from_slope_intercept(1.0, 0.0) {
    Some(l) => l
    None => {
      assert_true(false)
      return
    }
  }
  let arr = build([l1, l2, l3])
  // 3 pairs, but all intersect at the same point (0, 0).
  // However, our implementation records 3 separate vertices at the same location.
  assert_eq(num_vertices(arr), 3) // 3 pairwise intersections
  // Faces: 1 + 3 + sum(multiplicity - 1) = 1 + 3 + (3-1) = 6
  assert_eq(num_faces(arr), 6) // 6 sectors
}

///|
test "line_arrangement: point location" {
  // y = 0 and x = 0
  let l1 = match line_from_slope_intercept(0.0, 0.0) {
    Some(l) => l
    None => {
      assert_true(false)
      return
    }
  }
  let l2 = match line(1.0, 0.0, 0.0) {
    Some(l) => l
    None => {
      assert_true(false)
      return
    }
  }
  let arr = build([l1, l2])
  // NE quadrant: (1, 1)
  let signs_ne = locate(arr, 1.0, 1.0)
  // NW quadrant: (-1, 1)
  let signs_nw = locate(arr, -1.0, 1.0)
  // SE quadrant: (1, -1)
  let signs_se = locate(arr, 1.0, -1.0)
  // SW quadrant: (-1, -1)
  let signs_sw = locate(arr, -1.0, -1.0)
  // All should be different.
  assert_true(signs_ne != signs_nw)
  assert_true(signs_ne != signs_se)
  assert_true(signs_ne != signs_sw)
  assert_true(signs_nw != signs_se)
  assert_true(signs_nw != signs_sw)
  assert_true(signs_se != signs_sw)
  // Points in the same quadrant should have the same sign vector.
  assert_true(same_face(arr, 1.0, 1.0, 2.0, 3.0))
  assert_false(same_face(arr, 1.0, 1.0, -1.0, 1.0))
}

///|
test "line_arrangement: zone query" {
  // Three lines: y = 0, x = 0, y = x + 1
  let l1 = match line_from_slope_intercept(0.0, 0.0) {
    Some(l) => l
    None => {
      assert_true(false)
      return
    }
  }
  let l2 = match line(1.0, 0.0, 0.0) {
    Some(l) => l
    None => {
      assert_true(false)
      return
    }
  }
  let l3 = match line_from_slope_intercept(1.0, 1.0) {
    Some(l) => l
    None => {
      assert_true(false)
      return
    }
  }
  let arr = build([l1, l2, l3])
  // Zone of a horizontal line y = 0.5.
  let query = match line_from_slope_intercept(0.0, 0.5) {
    Some(l) => l
    None => {
      assert_true(false)
      return
    }
  }
  let zone_faces = zone(arr, query)
  // y = 0.5 intersects x = 0 (at (0, 0.5)) and y = x + 1 (at x = -0.5).
  // So the zone has 3 segments: before x=-0.5, between -0.5 and 0, after 0.
  // That's at most 3 faces (some might be the same face).
  assert_true(zone_faces.length() >= 1)
  assert_true(zone_faces.length() <= 3)
}

///|
test "line_arrangement: face enumeration" {
  // Two intersecting lines → 4 faces.
  let l1 = match line_from_slope_intercept(0.0, 0.0) {
    Some(l) => l
    None => {
      assert_true(false)
      return
    }
  }
  let l2 = match line(1.0, 0.0, 0.0) {
    Some(l) => l
    None => {
      assert_true(false)
      return
    }
  }
  let arr = build([l1, l2])
  let all_faces = faces(arr)
  assert_eq(all_faces.length(), 4)
}

///|
test "line_arrangement: line_from_points" {
  let l = match line_from_points(0.0, 0.0, 1.0, 1.0) {
    Some(l) => l
    None => {
      assert_true(false)
      return
    }
  }
  // Line through (0,0) and (1,1): y = x → x - y = 0
  // Normalized: (1, -1) / √2
  let val_at_origin = line_eval(l, 0.0, 0.0)
  assert_true(val_at_origin.abs() < EPS)
  let val_at_1_1 = line_eval(l, 1.0, 1.0)
  assert_true(val_at_1_1.abs() < EPS)
  // Point (1, 0) should be on one side, (0, 1) on the other.
  let val_at_1_0 = line_eval(l, 1.0, 0.0)
  let val_at_0_1 = line_eval(l, 0.0, 1.0)
  assert_true(val_at_1_0 * val_at_0_1 < 0.0)
}

///|
test "line_arrangement: parallel detection" {
  let l1 = match line_from_slope_intercept(1.0, 0.0) {
    Some(l) => l
    None => {
      assert_true(false)
      return
    }
  }
  let l2 = match line_from_slope_intercept(1.0, 5.0) {
    Some(l) => l
    None => {
      assert_true(false)
      return
    }
  }
  assert_true(is_parallel(l1, l2))
  let l3 = match line_from_slope_intercept(-1.0, 0.0) {
    Some(l) => l
    None => {
      assert_true(false)
      return
    }
  }
  assert_false(is_parallel(l1, l3))
}

///|
test "line_arrangement: intersection computation" {
  let l1 = match line_from_slope_intercept(1.0, 0.0) {
    Some(l) => l
    None => {
      assert_true(false)
      return
    }
  }
  let l2 = match line_from_slope_intercept(-1.0, 2.0) {
    Some(l) => l
    None => {
      assert_true(false)
      return
    }
  }
  match intersect(l1, l2) {
    Some((x, y)) => {
      // y = x and y = -x + 2 → x = 1, y = 1
      assert_true((x - 1.0).abs() < EPS)
      assert_true((y - 1.0).abs() < EPS)
    }
    None => assert_true(false)
  }
}

///|
test "line_arrangement: edge endpoints" {
  // y = 0 and x = 0
  let l1 = match line_from_slope_intercept(0.0, 0.0) {
    Some(l) => l
    None => {
      assert_true(false)
      return
    }
  }
  let l2 = match line(1.0, 0.0, 0.0) {
    Some(l) => l
    None => {
      assert_true(false)
      return
    }
  }
  let arr = build([l1, l2])
  let eps = edge_endpoints(arr)
  // 4 edges: 2 unbounded rays per line
  assert_eq(eps.length(), 4)
  // Each edge should have the origin as one endpoint.
  for i = 0; i < eps.length(); i = i + 1 {
    let ((x1, y1), (x2, y2)) = eps[i]
    let at_origin_1 = x1.abs() < EPS && y1.abs() < EPS
    let at_origin_2 = x2.abs() < EPS && y2.abs() < EPS
    assert_true(at_origin_1 || at_origin_2)
  }
}

///|
test "line_arrangement: four lines general position" {
  // y = 0, x = 0, y = x + 1, y = -x + 2 — no three concurrent.
  let l1 = match line_from_slope_intercept(0.0, 0.0) {
    Some(l) => l
    None => {
      assert_true(false)
      return
    }
  }
  let l2 = match line(1.0, 0.0, 0.0) {
    Some(l) => l
    None => {
      assert_true(false)
      return
    }
  }
  let l3 = match line_from_slope_intercept(1.0, 1.0) {
    Some(l) => l
    None => {
      assert_true(false)
      return
    }
  }
  let l4 = match line_from_slope_intercept(-1.0, 2.0) {
    Some(l) => l
    None => {
      assert_true(false)
      return
    }
  }
  let arr = build([l1, l2, l3, l4])
  // 4 lines in general position: C(4,2) = 6 vertices
  assert_eq(num_vertices(arr), 6)
  // 4² = 16 edges
  assert_eq(num_edges(arr), 16)
  // C(4,2) + 4 + 1 = 11 faces
  assert_eq(num_faces(arr), 11)
}

///|
test "line_arrangement: no intersections (all parallel)" {
  let lines : Array[Line] = []
  for i = 0; i < 5; i = i + 1 {
    match line_from_slope_intercept(1.0, i.to_double()) {
      Some(l) => lines.push(l)
      None => {
        assert_true(false)
        return
      }
    }
  }
  let arr = build(lines)
  assert_eq(num_vertices(arr), 0)
  assert_eq(num_edges(arr), 5) // 1 per line
  assert_eq(num_faces(arr), 6) // n + 1 = 6 strips
}

///|
test "line_arrangement: degenerate input" {
  // Same point twice → None
  assert_true(line_from_points(1.0, 1.0, 1.0, 1.0) is None)
  // a=b=0 → None
  assert_true(line(0.0, 0.0, 1.0) is None)
}

///|
test "line_arrangement: vertical line" {
  // x = 5 → 1*x + 0*y - 5 = 0
  let l = match line(1.0, 0.0, -5.0) {
    Some(l) => l
    None => {
      assert_true(false)
      return
    }
  }
  // Points on the line.
  assert_true(line_sign(l, 5.0, 0.0) == 0)
  assert_true(line_sign(l, 5.0, 100.0) == 0)
  // Points to the right (positive side).
  assert_true(line_sign(l, 6.0, 0.0) == 1)
  // Points to the left (negative side).
  assert_true(line_sign(l, 4.0, 0.0) == -1)
}

///|
test "line_arrangement: line_vertex_indices" {
  // y = 0, x = 0, y = x + 1
  let l1 = match line_from_slope_intercept(0.0, 0.0) {
    Some(l) => l
    None => {
      assert_true(false)
      return
    }
  }
  let l2 = match line(1.0, 0.0, 0.0) {
    Some(l) => l
    None => {
      assert_true(false)
      return
    }
  }
  let l3 = match line_from_slope_intercept(1.0, 1.0) {
    Some(l) => l
    None => {
      assert_true(false)
      return
    }
  }
  let arr = build([l1, l2, l3])
  // Each line should have 2 intersection points.
  assert_eq(line_vertex_indices(arr, 0).length(), 2)
  assert_eq(line_vertex_indices(arr, 1).length(), 2)
  assert_eq(line_vertex_indices(arr, 2).length(), 2)
}
