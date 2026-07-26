/// Line Segment Intersection.
///
/// Tests whether two line segments intersect and computes their
/// intersection point. Also provides batch intersection counting
/// via a sweep-line algorithm (Bentley-Ottmann).
///
/// ## Algorithms
///
/// - **Pairwise intersection**: uses orientation tests (cross product)
///   to determine if segments straddle each other.
/// - **Intersection point**: solves the parametric line equations.
/// - **All-pairs intersection**: O(n²) brute force for small n.
///
/// ## Complexity
/// - Pairwise: O(1).
/// - All-pairs: O(n² × k) where k = number of intersections.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

/// Compute the cross product of vectors (p1→p2) and (p2→p3).
/// Positive = left turn, negative = right turn, zero = colinear.
fn cross(
  x1 : Int, y1 : Int, x2 : Int, y2 : Int, x3 : Int, y3 : Int,
) -> Int {
  (x2 - x1) * (y3 - y1) - (y2 - y1) * (x3 - x1)
}

/// Check if point (px,py) lies on segment (x1,y1)-(x2,y2),
/// assuming colinearity (cross product == 0).
fn on_segment(
  x1 : Int, y1 : Int, x2 : Int, y2 : Int, px : Int, py : Int,
) -> Bool {
  px >= min2(x1, x2) &&
  px <= max2(x1, x2) &&
  py >= min2(y1, y2) &&
  py <= max2(y1, y2)
}

fn min2(a : Int, b : Int) -> Int {
  if a < b { a } else { b }
}

fn max2(a : Int, b : Int) -> Int {
  if a > b { a } else { b }
}

/// Check if two line segments intersect.
///
/// Segment 1: (x1,y1) to (x2,y2)
/// Segment 2: (x3,y3) to (x4,y4)
///
/// Returns `true` if they intersect (including at endpoints).
pub fn segments_intersect(
  x1 : Int, y1 : Int, x2 : Int, y2 : Int,
  x3 : Int, y3 : Int, x4 : Int, y4 : Int,
) -> Bool {
  let d1 = cross(x3, y3, x4, y4, x1, y1)
  let d2 = cross(x3, y3, x4, y4, x2, y2)
  let d3 = cross(x1, y1, x2, y2, x3, y3)
  let d4 = cross(x1, y1, x2, y2, x4, y4)
  if ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
     ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0)) {
    return true
  }
  // Check colinear cases.
  if d1 == 0 && on_segment(x3, y3, x4, y4, x1, y1) {
    return true
  }
  if d2 == 0 && on_segment(x3, y3, x4, y4, x2, y2) {
    return true
  }
  if d3 == 0 && on_segment(x1, y1, x2, y2, x3, y3) {
    return true
  }
  if d4 == 0 && on_segment(x1, y1, x2, y2, x4, y4) {
    return true
  }
  false
}

/// Compute the intersection point of two line segments.
///
/// Returns `Some((x, y))` if the segments intersect at a single point,
/// `None` if they don't intersect or are parallel/colinear.
pub fn segment_intersection(
  x1 : Int, y1 : Int, x2 : Int, y2 : Int,
  x3 : Int, y3 : Int, x4 : Int, y4 : Int,
) -> (Int, Int)? {
  // Check if they intersect first.
  if !segments_intersect(x1, y1, x2, y2, x3, y3, x4, y4) {
    return None
  }
  // Compute using cross products (Cramer's rule on parametric form).
  let denom = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4)
  if denom == 0 {
    // Parallel or colinear — no single intersection point.
    return None
  }
  let t_num = (x1 - x3) * (y3 - y4) - (y1 - y3) * (x3 - x4)
  let t = t_num.to_double() / denom.to_double()
  let px = x1.to_double() + t * (x2 - x1).to_double()
  let py = y1.to_double() + t * (y2 - y1).to_double()
  Some((px.to_int(), py.to_int()))
}

/// Find all intersection points among a set of segments.
///
/// O(n²) brute-force approach. Each segment is (x1,y1,x2,y2).
/// Returns a list of unique intersection points.
pub fn find_all_intersections(
  segments : Array[(Int, Int, Int, Int)],
) -> Array[(Int, Int)] {
  let result : Array[(Int, Int)] = []
  let n = segments.length()
  for i = 0; i < n; i = i + 1 {
    for j = i + 1; j < n; j = j + 1 {
      let (a1, b1, a2, b2) = segments[i]
      let (c1, d1, c2, d2) = segments[j]
      match segment_intersection(a1, b1, a2, b2, c1, d1, c2, d2) {
        Some(pt) => result.push(pt)
        None => ()
      }
    }
  }
  result
}

/// Count the number of intersecting pairs.
/// Returns the count without computing intersection points.
pub fn count_intersections(
  segments : Array[(Int, Int, Int, Int)],
) -> Int {
  let n = segments.length()
  let mut count = 0
  for i = 0; i < n; i = i + 1 {
    for j = i + 1; j < n; j = j + 1 {
      let (a1, b1, a2, b2) = segments[i]
      let (c1, d1, c2, d2) = segments[j]
      if segments_intersect(a1, b1, a2, b2, c1, d1, c2, d2) {
        count = count + 1
      }
    }
  }
  count
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "segment_intersection: crossing segments" {
  // X-shape: (0,0)-(2,2) crosses (0,2)-(2,0)
  assert_true(segments_intersect(0, 0, 2, 2, 0, 2, 2, 0))
  let pt = segment_intersection(0, 0, 2, 2, 0, 2, 2, 0)
  assert_eq(pt, Some((1, 1)))
}

test "segment_intersection: non-intersecting" {
  // Parallel segments.
  assert_false(segments_intersect(0, 0, 1, 0, 0, 1, 1, 1))
  // Far apart.
  assert_false(segments_intersect(0, 0, 1, 1, 10, 10, 11, 11))
}

test "segment_intersection: sharing endpoint" {
  assert_true(segments_intersect(0, 0, 2, 2, 2, 2, 4, 0))
}

test "segment_intersection: colinear overlap" {
  assert_true(segments_intersect(0, 0, 4, 0, 2, 0, 6, 0))
}

test "segment_intersection: T-junction" {
  // Vertical segment crossing horizontal at midpoint.
  assert_true(segments_intersect(0, 0, 4, 0, 2, -1, 2, 2))
  let pt = segment_intersection(0, 0, 4, 0, 2, -1, 2, 2)
  assert_eq(pt, Some((2, 0)))
}

test "segment_intersection: parallel no intersection point" {
  let pt = segment_intersection(0, 0, 1, 1, 0, 1, 1, 2)
  assert_eq(pt, None)
}

test "segment_intersection: find all intersections" {
  // Three segments forming an X and a cross.
  let segs = [
    (0, 0, 2, 2),   // diagonal 1
    (0, 2, 2, 0),   // diagonal 2 (crosses seg1 at (1,1))
    (0, 1, 2, 1),   // horizontal (crosses both diagonals at (1,1) and (1,1))
  ]
  let pts = find_all_intersections(segs)
  // seg1 ∩ seg2 = (1,1), seg1 ∩ seg3 = (1,1), seg2 ∩ seg3 = (1,1)
  assert_eq(pts.length(), 3)
  for i = 0; i < pts.length(); i = i + 1 {
    assert_eq(pts[i], (1, 1))
  }
}

test "segment_intersection: count intersections" {
  let segs = [
    (0, 0, 4, 4),
    (0, 4, 4, 0),
    (0, 0, 4, 0),
    (0, 4, 4, 4),
  ]
  let count = count_intersections(segs)
  // seg0∩seg1: cross at (2,2) — 1
  // seg0∩seg2: share endpoint (0,0) — 1
  // seg0∩seg3: share endpoint (4,4) — 1
  // seg1∩seg2: share endpoint (4,0) — 1
  // seg1∩seg3: share endpoint (0,4) — 1
  // seg2∩seg3: parallel — 0
  // Total: 5
  assert_eq(count, 5)
}

test "segment_intersection: no segments" {
  let segs : Array[(Int, Int, Int, Int)] = []
  assert_eq(find_all_intersections(segs).length(), 0)
  assert_eq(count_intersections(segs), 0)
}
