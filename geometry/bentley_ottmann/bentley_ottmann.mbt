/// Segment intersection via brute-force O(n²) pairwise testing.
///
/// A true Bentley-Ottmann sweep-line implementation uses a balanced BST to
/// achieve O((n + k) log n) where k is the number of intersections. This
/// module uses the simpler O(n²) approach — testing every pair of segments —
/// which is correct and sufficient for small inputs.
///
/// Each segment is (x1, y1, x2, y2). Returns all intersection points.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

fn segment_intersect(
  x1 : Double, y1 : Double, x2 : Double, y2 : Double,
  x3 : Double, y3 : Double, x4 : Double, y4 : Double,
) -> (Double, Double)? {
  let denom = (x2 - x1) * (y4 - y3) - (y2 - y1) * (x4 - x3)
  if denom.abs() < 1.0e-12 {
    None // parallel or collinear
  } else {
    let t = ((x3 - x1) * (y4 - y3) - (y3 - y1) * (x4 - x3)) / denom
    let u = ((x3 - x1) * (y2 - y1) - (y3 - y1) * (x2 - x1)) / denom
    if t >= 0.0 && t <= 1.0 && u >= 0.0 && u <= 1.0 {
      Some((x1 + t * (x2 - x1), y1 + t * (y2 - y1)))
    } else {
      None
    }
  }
}

pub fn find_intersections(
  segments : Array[(Double, Double, Double, Double)],
) -> Array[(Double, Double)] {
  let result : Array[(Double, Double)] = []
  let n = segments.length()
  for i = 0; i < n; i = i + 1 {
    let (ax1, ay1, ax2, ay2) = segments[i]
    for j = i + 1; j < n; j = j + 1 {
      let (bx1, by1, bx2, by2) = segments[j]
      match segment_intersect(ax1, ay1, ax2, ay2, bx1, by1, bx2, by2) {
        Some(pt) => result.push(pt)
        None => ()
      }
    }
  }
  result
}

test "bentley_ottmann: crossing segments" {
  let segs = [(0.0, 0.0, 2.0, 2.0), (0.0, 2.0, 2.0, 0.0)]
  let pts = find_intersections(segs)
  assert_eq(pts.length(), 1)
  let (x, y) = pts[0]
  assert_true((x - 1.0).abs() < 1.0e-10)
  assert_true((y - 1.0).abs() < 1.0e-10)
}

test "bentley_ottmann: no intersections" {
  let segs = [(0.0, 0.0, 1.0, 1.0), (3.0, 3.0, 4.0, 4.0)]
  let pts = find_intersections(segs)
  assert_eq(pts.length(), 0)
}

test "bentley_ottmann: multiple crossings" {
  let segs = [
    (0.0, 0.0, 4.0, 4.0),
    (0.0, 4.0, 4.0, 0.0),
    (0.0, 2.0, 4.0, 2.0),
  ]
  let pts = find_intersections(segs)
  // All three pairs cross at (2, 2).
  assert_eq(pts.length(), 3)
  for i = 0; i < 3; i = i + 1 {
    let (x, y) = pts[i]
    assert_true((x - 2.0).abs() < 1.0e-10)
    assert_true((y - 2.0).abs() < 1.0e-10)
  }
}
