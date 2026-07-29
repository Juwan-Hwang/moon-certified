/// Polygon Boolean Operations — intersection, union, difference.
///
/// This package provides Boolean set operations on polygons using the
/// Sutherland-Hodgman clipping algorithm for convex clip windows.
///
/// ## Operations
/// - **Intersection** `A ∩ B`: the region inside both A and B.
///   Requires B to be convex (A may be non-convex).
/// - **Union** `A ∪ B`: the region inside A or B (or both).
///   Requires both A and B to be convex.
/// - **Difference** `A - B`: the region inside A but not inside B.
///   Requires B to be convex (A may be non-convex).
///
/// ## Convexity
///
/// The `is_convex` function checks whether a polygon is convex.
/// Callers should validate input convexity when the operation requires it.
///
/// ## Complexity
/// - Time: O(n * m) where n = |A|, m = |B|.
/// - Space: O(n + m).
///
/// ## Limitations
///
/// - Sutherland-Hodgman produces correct results when the **clip** polygon
///   (B) is convex. The subject polygon (A) may be non-convex for
///   intersection and difference, but the output may contain degenerate
///   edges connecting disconnected components.
/// - Union requires both polygons to be convex and overlapping for a
///   correct single-polygon result. Non-overlapping polygons return A.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

///|
/// A 2D point with Double coordinates.
pub struct Point {
  x : Double
  y : Double
}

///|
/// Construct a point.
pub fn point(x : Double, y : Double) -> Point {
  { x, y }
}

///|
/// A polygon represented as a list of vertices in counter-clockwise order.
pub type Polygon = Array[Point]

///|
/// Construct a point from Int coordinates.
pub fn ipoint(x : Int, y : Int) -> Point {
  { x: x.to_double(), y: y.to_double() }
}

// ---------------------------------------------------------------------------
// Geometry helpers
// ---------------------------------------------------------------------------

///|
/// Cross product of vectors (a→b) and (a→c).
fn cross(a : Point, b : Point, c : Point) -> Double {
  (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
}

///|
/// Check if a point is inside (left of or on) a CCW edge.
fn is_inside(p : Point, edge_start : Point, edge_end : Point) -> Bool {
  cross(edge_start, edge_end, p) >= 0.0
}

///|
/// Compute the intersection of a line segment with an edge.
fn line_intersection(
  p1 : Point,
  p2 : Point,
  edge_start : Point,
  edge_end : Point,
) -> Point {
  let dx = edge_end.x - edge_start.x
  let dy = edge_end.y - edge_start.y
  let denom = (p2.x - p1.x) * dy - (p2.y - p1.y) * dx
  let t = if denom.abs() < 1.0e-15 {
    0.0
  } else {
    ((edge_start.x - p1.x) * dy - (edge_start.y - p1.y) * dx) / denom
  }
  { x: p1.x + t * (p2.x - p1.x), y: p1.y + t * (p2.y - p1.y) }
}

///|
/// Check if a polygon is convex (vertices in CCW order).
///
/// A polygon is convex if all cross products at consecutive vertices
/// have the same sign (all ≥ 0 for CCW convex).
pub fn is_convex(poly : Array[Point]) -> Bool {
  let n = poly.length()
  if n < 3 {
    return false
  }
  let mut has_pos = false
  let mut has_neg = false
  for i = 0; i < n; i = i + 1 {
    let prev = poly[(i + n - 1) % n]
    let curr = poly[i]
    let next = poly[(i + 1) % n]
    let c = cross(prev, curr, next)
    if c > 1.0e-10 {
      has_pos = true
    } else if c < -1.0e-10 {
      has_neg = true
    }
  }
  // Convex if all turns are the same direction.
  !(has_pos && has_neg)
}

///|
/// Check if a point is inside a convex polygon (CCW).
fn point_in_convex_polygon(p : Point, poly : Array[Point]) -> Bool {
  let n = poly.length()
  for i = 0; i < n; i = i + 1 {
    if !is_inside(p, poly[i], poly[(i + 1) % n]) {
      return false
    }
  }
  true
}

// ---------------------------------------------------------------------------
// Sutherland-Hodgman clipping
// ---------------------------------------------------------------------------

///|
/// Sutherland-Hodgman polygon clipping: clip `subject` against the convex
/// `clip` polygon. The `inside_test` function determines which side is kept.
fn sutherland_hodgman_clip(
  subject : Array[Point],
  clip : Array[Point],
  inside_test : (Point, Point, Point) -> Bool,
) -> Array[Point] {
  let output = Array::copy(subject)
  let clip_n = clip.length()
  for i = 0; i < clip_n; i = i + 1 {
    if output.length() == 0 {
      return []
    }
    let edge_start = clip[i]
    let edge_end = clip[(i + 1) % clip_n]
    let input = Array::copy(output)
    output.clear()
    let input_n = input.length()
    for j = 0; j < input_n; j = j + 1 {
      let current = input[j]
      let prev = input[(j + input_n - 1) % input_n]
      let current_inside = inside_test(current, edge_start, edge_end)
      let prev_inside = inside_test(prev, edge_start, edge_end)
      if current_inside {
        if !prev_inside {
          output.push(line_intersection(prev, current, edge_start, edge_end))
        }
        output.push(current)
      } else if prev_inside {
        output.push(line_intersection(prev, current, edge_start, edge_end))
      }
    }
  }
  output
}

// ---------------------------------------------------------------------------
// Boolean operations
// ---------------------------------------------------------------------------

///|
/// Compute the intersection of two polygons A ∩ B.
///
/// B must be convex. A may be non-convex (Sutherland-Hodgman handles
/// non-convex subjects with convex clip windows).
pub fn intersection(a : Array[Point], b : Array[Point]) -> Array[Point] {
  sutherland_hodgman_clip(a, b, is_inside)
}

// ---------------------------------------------------------------------------
// Weiler-Atherton boundary tracing for difference and union
// ---------------------------------------------------------------------------

///|
/// An edge-edge crossing point with metadata.
priv struct Crossing {
  pt : Point
  a_edge : Int // edge index in A
  b_edge : Int // edge index in B
  t_a : Double // parameter along A edge (0..1)
  t_b : Double // parameter along B edge (0..1)
}

///|
/// A vertex in an augmented vertex list (original vertex or crossing).
priv struct AugPt {
  pt : Point
  crossing_id : Int // -1 for original vertex, otherwise index into crossings
}

///|
/// Compute the intersection of two line segments with parameters.
/// Returns (point, t_along_a, t_along_b) or None.
fn segment_intersection_param(
  a1 : Point,
  a2 : Point,
  b1 : Point,
  b2 : Point,
) -> (Point, Double, Double)? {
  let d1x = a2.x - a1.x
  let d1y = a2.y - a1.y
  let d2x = b2.x - b1.x
  let d2y = b2.y - b1.y
  let denom = d1x * d2y - d1y * d2x
  if denom.abs() < 1.0e-15 {
    return None
  }
  let t = ((b1.x - a1.x) * d2y - (b1.y - a1.y) * d2x) / denom
  let u = ((b1.x - a1.x) * d1y - (b1.y - a1.y) * d1x) / denom
  if t < -1.0e-9 || t > 1.0 + 1.0e-9 || u < -1.0e-9 || u > 1.0 + 1.0e-9 {
    return None
  }
  Some(({ x: a1.x + t * d1x, y: a1.y + t * d1y }, t, u))
}

///|
/// Find all edge-edge crossings between polygons A and B.
fn find_crossings(a : Array[Point], b : Array[Point]) -> Array[Crossing] {
  let crossings : Array[Crossing] = []
  for ia = 0; ia < a.length(); ia = ia + 1 {
    let a1 = a[ia]
    let a2 = a[(ia + 1) % a.length()]
    for ib = 0; ib < b.length(); ib = ib + 1 {
      let b1 = b[ib]
      let b2 = b[(ib + 1) % b.length()]
      match segment_intersection_param(a1, a2, b1, b2) {
        None => ()
        Some((pt, t_a, t_b)) =>
          crossings.push({ pt, a_edge: ia, b_edge: ib, t_a, t_b })
      }
    }
  }
  crossings
}

///|
/// Build an augmented vertex list that inserts crossing points at the
/// correct positions along each edge of the polygon.
fn build_augmented(
  poly : Array[Point],
  crossings : Array[Crossing],
  is_a : Bool,
) -> Array[AugPt] {
  let n = poly.length()
  let aug : Array[AugPt] = []
  for i = 0; i < n; i = i + 1 {
    // Add the original vertex.
    aug.push({ pt: poly[i], crossing_id: -1 })
    // Collect crossings on this edge.
    let edge_cs : Array[(Int, Double)] = []
    for ci = 0; ci < crossings.length(); ci = ci + 1 {
      let c = crossings[ci]
      let edge = if is_a { c.a_edge } else { c.b_edge }
      let t = if is_a { c.t_a } else { c.t_b }
      if edge == i {
        edge_cs.push((ci, t))
      }
    }
    // Sort by parameter along the edge.
    edge_cs.sort_by(fn(x, y) {
      let (_, tx) = x
      let (_, ty) = y
      if tx < ty {
        -1
      } else if tx > ty {
        1
      } else {
        0
      }
    })
    // Insert sorted crossings.
    for j = 0; j < edge_cs.length(); j = j + 1 {
      let (ci, _) = edge_cs[j]
      aug.push({ pt: crossings[ci].pt, crossing_id: ci })
    }
  }
  aug
}

///|
/// Build a mapping from crossing_id to index in the augmented list.
fn build_crossing_map(aug : Array[AugPt], num_crossings : Int) -> Array[Int] {
  let map = Array::make(num_crossings, -1)
  for i = 0; i < aug.length(); i = i + 1 {
    let cid = aug[i].crossing_id
    if cid >= 0 {
      map[cid] = i
    }
  }
  map
}

///|
/// Trace the boundary of a Boolean operation using the Weiler-Atherton
/// algorithm.
///
/// - `b_reverse = true`  → difference (A \ B): walk B in reverse
/// - `b_reverse = false` → union (A ∪ B): walk B forward
fn trace_boolean(
  a : Array[Point],
  b : Array[Point],
  b_reverse : Bool,
) -> Array[Point] {
  let a_n = a.length()
  let b_n = b.length()
  if a_n < 3 {
    return Array::copy(b)
  }
  if b_n < 3 {
    return Array::copy(a)
  }
  // Find all edge-edge crossings.
  let crossings = find_crossings(a, b)
  let num_crossings = crossings.length()
  // Handle no crossings: containment or disjoint.
  if num_crossings == 0 {
    let mut a_in_b = true
    for i = 0; i < a_n; i = i + 1 {
      if !point_in_convex_polygon(a[i], b) {
        a_in_b = false
        break
      }
    }
    if a_in_b {
      return if b_reverse { [] } else { Array::copy(b) }
    }
    let mut b_in_a = true
    for i = 0; i < b_n; i = i + 1 {
      if !point_in_convex_polygon(b[i], a) {
        b_in_a = false
        break
      }
    }
    if b_in_a {
      return Array::copy(a)
    }
    // Disjoint: return A.
    return Array::copy(a)
  }
  if num_crossings < 2 {
    return Array::copy(a)
  }
  // Build augmented vertex lists with crossings inserted.
  let aug_a = build_augmented(a, crossings, true)
  let aug_b = build_augmented(b, crossings, false)
  let map_a = build_crossing_map(aug_a, num_crossings)
  let map_b = build_crossing_map(aug_b, num_crossings)
  let aug_a_len = aug_a.length()
  let aug_b_len = aug_b.length()
  // Find a starting A vertex outside B.
  let mut start = -1
  for i = 0; i < aug_a_len; i = i + 1 {
    if aug_a[i].crossing_id < 0 && !point_in_convex_polygon(aug_a[i].pt, b) {
      start = i
      break
    }
  }
  if start < 0 {
    // All A vertices inside B.
    return if b_reverse { [] } else { Array::copy(b) }
  }
  // Trace boundary.
  let result : Array[Point] = []
  let mut on_a = true
  let mut idx = start
  let max_steps = 2 * (aug_a_len + aug_b_len) + 10
  let mut steps = 0
  let mut done = false
  result.push(aug_a[start].pt)
  while !done && steps < max_steps {
    steps = steps + 1
    // Advance to next position.
    if !on_a && b_reverse {
      let aug_len = aug_b_len
      idx = (idx - 1 + aug_len) % aug_len
    } else {
      let aug_len = if on_a { aug_a_len } else { aug_b_len }
      idx = (idx + 1) % aug_len
    }
    // Check if we've returned to start on A.
    if on_a && idx == start {
      done = true
      break
    }
    let aug = if on_a { aug_a } else { aug_b }
    let curr = aug[idx]
    if curr.crossing_id >= 0 {
      // Hit a crossing: add it and switch polygons.
      result.push(curr.pt)
      if on_a {
        on_a = false
        idx = map_b[curr.crossing_id]
      } else {
        on_a = true
        idx = map_a[curr.crossing_id]
      }
    } else {
      // Original vertex: check if it should be kept.
      let inside_other = if on_a {
        point_in_convex_polygon(curr.pt, b)
      } else {
        point_in_convex_polygon(curr.pt, a)
      }
      let keep = if on_a {
        !inside_other // Both ops: keep A vertices outside B.
      } else if b_reverse {
        inside_other // Difference: keep B vertices inside A.
      } else {
        !inside_other // Union: keep B vertices outside A.
      }
      if keep {
        result.push(curr.pt)
      }
    }
  }
  // Remove duplicate closing point if present.
  let n = result.length()
  if n > 1 {
    let first = result[0]
    let last = result[n - 1]
    if (first.x - last.x).abs() < 1.0e-9 && (first.y - last.y).abs() < 1.0e-9 {
      ignore(result.pop())
    }
  }
  result
}

///|
/// Compute the difference A - B (region in A but not in B).
///
/// B must be convex. Uses the Weiler-Atherton algorithm: walks A's
/// boundary outside B, and when entering B, follows B's boundary in
/// reverse (cutting around the removed region).
pub fn difference(a : Array[Point], b : Array[Point]) -> Array[Point] {
  trace_boolean(a, b, true)
}

///|
/// Compute the union A ∪ B (region in A or B or both).
///
/// Both A and B must be convex for a correct single-polygon result.
/// Uses the Weiler-Atherton algorithm: walks A's boundary outside B,
/// and when entering B, follows B's boundary forward (going around
/// B's exterior).
pub fn union(a : Array[Point], b : Array[Point]) -> Array[Point] {
  trace_boolean(a, b, false)
}

///|
/// Compute the area of a polygon (shoelace formula).
pub fn area(poly : Array[Point]) -> Double {
  let n = poly.length()
  if n < 3 {
    return 0.0
  }
  let mut sum = 0.0
  for i = 0; i < n; i = i + 1 {
    let j = (i + 1) % n
    sum = sum + poly[i].x * poly[j].y - poly[j].x * poly[i].y
  }
  sum.abs() / 2.0
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "polygon_boolean: square intersection" {
  let sq1 = [ipoint(0, 0), ipoint(4, 0), ipoint(4, 4), ipoint(0, 4)]
  let sq2 = [ipoint(2, 2), ipoint(6, 2), ipoint(6, 6), ipoint(2, 6)]
  let result = intersection(sq1, sq2)
  assert_true(result.length() >= 3)
  let a = area(result)
  assert_true((a - 4.0).abs() < 0.001)
}

///|
test "polygon_boolean: identical squares" {
  let sq = [ipoint(0, 0), ipoint(4, 0), ipoint(4, 4), ipoint(0, 4)]
  let result = intersection(sq, Array::copy(sq))
  let a = area(result)
  assert_true((a - 16.0).abs() < 0.001)
}

///|
test "polygon_boolean: no overlap" {
  let sq1 = [ipoint(0, 0), ipoint(2, 0), ipoint(2, 2), ipoint(0, 2)]
  let sq2 = [ipoint(5, 5), ipoint(7, 5), ipoint(7, 7), ipoint(5, 7)]
  let result = intersection(sq1, sq2)
  assert_eq(result.length(), 0)
}

///|
test "polygon_boolean: contained square" {
  let outer = [ipoint(0, 0), ipoint(10, 0), ipoint(10, 10), ipoint(0, 10)]
  let inner = [ipoint(2, 2), ipoint(4, 2), ipoint(4, 4), ipoint(2, 4)]
  let result = intersection(outer, inner)
  let a = area(result)
  assert_true((a - 4.0).abs() < 0.001)
}

///|
test "polygon_boolean: triangle intersection" {
  let tri1 = [ipoint(0, 0), ipoint(4, 0), ipoint(2, 4)]
  let tri2 = [ipoint(0, 0), ipoint(4, 0), ipoint(2, 4)]
  let result = intersection(tri1, tri2)
  let a = area(result)
  assert_true((a - 8.0).abs() < 0.01)
}

///|
test "polygon_boolean: is_convex" {
  let square = [ipoint(0, 0), ipoint(4, 0), ipoint(4, 4), ipoint(0, 4)]
  assert_true(is_convex(square))
  // L-shaped (non-convex) polygon.
  let l_shape = [
    ipoint(0, 0), ipoint(2, 0), ipoint(2, 1), ipoint(4, 1),
    ipoint(4, 4), ipoint(0, 4),
  ]
  assert_false(is_convex(l_shape))
  // Triangle is convex.
  let tri = [ipoint(0, 0), ipoint(4, 0), ipoint(2, 4)]
  assert_true(is_convex(tri))
}

///|
test "polygon_boolean: difference of overlapping squares" {
  let a = [ipoint(0, 0), ipoint(4, 0), ipoint(4, 4), ipoint(0, 4)]
  let b = [ipoint(2, 2), ipoint(6, 2), ipoint(6, 6), ipoint(2, 6)]
  let result = difference(a, b)
  // A \ B: area of A (16) - area of overlap (4) = 12
  let a_result = area(result)
  assert_true((a_result - 12.0).abs() < 0.01)
}

///|
test "polygon_boolean: difference with no overlap" {
  let a = [ipoint(0, 0), ipoint(4, 0), ipoint(4, 4), ipoint(0, 4)]
  let b = [ipoint(5, 5), ipoint(7, 5), ipoint(7, 7), ipoint(5, 7)]
  let result = difference(a, b)
  // No overlap: result = A.
  let a_result = area(result)
  assert_true((a_result - 16.0).abs() < 0.001)
}

///|
test "polygon_boolean: difference where B contains A" {
  let a = [ipoint(2, 2), ipoint(4, 2), ipoint(4, 4), ipoint(2, 4)]
  let b = [ipoint(0, 0), ipoint(10, 0), ipoint(10, 10), ipoint(0, 10)]
  let result = difference(a, b)
  // B contains A: result should be empty.
  assert_eq(result.length(), 0)
}

///|
test "polygon_boolean: union of overlapping squares" {
  let a = [ipoint(0, 0), ipoint(4, 0), ipoint(4, 4), ipoint(0, 4)]
  let b = [ipoint(2, 2), ipoint(6, 2), ipoint(6, 6), ipoint(2, 6)]
  let result = union(a, b)
  // A ∪ B: area of A (16) + area of B (16) - overlap (4) = 28
  let a_result = area(result)
  assert_true((a_result - 28.0).abs() < 0.5)
}

///|
test "polygon_boolean: union where A contains B" {
  let a = [ipoint(0, 0), ipoint(10, 0), ipoint(10, 10), ipoint(0, 10)]
  let b = [ipoint(2, 2), ipoint(4, 2), ipoint(4, 4), ipoint(2, 4)]
  let result = union(a, b)
  // A contains B: union = A.
  let a_result = area(result)
  assert_true((a_result - 100.0).abs() < 0.001)
}

///|
test "polygon_boolean: union of disjoint polygons" {
  let a = [ipoint(0, 0), ipoint(2, 0), ipoint(2, 2), ipoint(0, 2)]
  let b = [ipoint(5, 5), ipoint(7, 5), ipoint(7, 7), ipoint(5, 7)]
  let result = union(a, b)
  // Disjoint: returns A (limitation of single-polygon representation).
  let a_result = area(result)
  assert_true((a_result - 4.0).abs() < 0.001)
}
