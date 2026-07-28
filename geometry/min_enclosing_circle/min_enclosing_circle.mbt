///|
/// Minimum enclosing circle via Welzl's algorithm (randomized, expected O(n)).
/// Uses a fixed-seed LCG Fisher-Yates shuffle for reproducibility.
/// `proof-enabled` is `false`; correctness is backed by the test suite.
pub struct Circle {
  cx : Double
  cy : Double
  r : Double
}

///|
fn dist2(ax : Double, ay : Double, bx : Double, by : Double) -> Double {
  let dx = ax - bx
  let dy = ay - by
  dx * dx + dy * dy
}

///|
fn in_circle(c : Circle, px : Double, py : Double) -> Bool {
  dist2(c.cx, c.cy, px, py) <= c.r * c.r + 1.0e-10
}

///|
fn circle_two(ax : Double, ay : Double, bx : Double, by : Double) -> Circle {
  {
    cx: (ax + bx) / 2.0,
    cy: (ay + by) / 2.0,
    r: dist2(ax, ay, bx, by).sqrt() / 2.0,
  }
}

///|
fn circle_three(
  ax : Double,
  ay : Double,
  bx : Double,
  by : Double,
  cx : Double,
  cy : Double,
) -> Circle {
  let d = 2.0 * (ax * (by - cy) + bx * (cy - ay) + cx * (ay - by))
  if d.abs() < 1.0e-12 {
    let dab = dist2(ax, ay, bx, by)
    let dac = dist2(ax, ay, cx, cy)
    let dbc = dist2(bx, by, cx, cy)
    if dab >= dac && dab >= dbc {
      circle_two(ax, ay, bx, by)
    } else if dac >= dbc {
      circle_two(ax, ay, cx, cy)
    } else {
      circle_two(bx, by, cx, cy)
    }
  } else {
    let a2 = ax * ax + ay * ay
    let b2 = bx * bx + by * by
    let c2 = cx * cx + cy * cy
    let ux = (a2 * (by - cy) + b2 * (cy - ay) + c2 * (ay - by)) / d
    let uy = (a2 * (cx - bx) + b2 * (ax - cx) + c2 * (bx - ax)) / d
    { cx: ux, cy: uy, r: dist2(ux, uy, ax, ay).sqrt() }
  }
}

///|
pub fn min_enclosing_circle(points : Array[(Double, Double)]) -> Circle {
  let n = points.length()
  if n == 0 {
    return { cx: 0.0, cy: 0.0, r: 0.0 }
  }
  let pts = points.copy()
  let mut seed = 42
  for i = n - 1; i > 0; i = i - 1 {
    seed = @utils.lcg_next(seed)
    let j = seed % (i + 1)
    let tmp = pts[i]
    pts[i] = pts[j]
    pts[j] = tmp
  }
  let (x0, y0) = pts[0]
  let mut c = { cx: x0, cy: y0, r: 0.0 }
  for i = 1; i < n; i = i + 1 {
    let (px, py) = pts[i]
    if !in_circle(c, px, py) {
      c = { cx: px, cy: py, r: 0.0 }
      for j = 0; j < i; j = j + 1 {
        let (qx, qy) = pts[j]
        if !in_circle(c, qx, qy) {
          c = circle_two(px, py, qx, qy)
          for k = 0; k < j; k = k + 1 {
            let (rx, ry) = pts[k]
            if !in_circle(c, rx, ry) {
              c = circle_three(px, py, qx, qy, rx, ry)
            }
          }
        }
      }
    }
  }
  c
}

///|
test "min_enclosing_circle: single point" {
  let c = min_enclosing_circle([(3.0, 4.0)])
  assert_true((c.cx - 3.0).abs() < 1.0e-10)
  assert_true((c.cy - 4.0).abs() < 1.0e-10)
  assert_true(c.r < 1.0e-10)
}

///|
test "min_enclosing_circle: triangle" {
  let c = min_enclosing_circle([(0.0, 0.0), (3.0, 0.0), (0.0, 4.0)])
  assert_true((c.cx - 1.5).abs() < 1.0e-10)
  assert_true((c.cy - 2.0).abs() < 1.0e-10)
  assert_true((c.r - 2.5).abs() < 1.0e-10)
}

///|
test "min_enclosing_circle: many points" {
  let pts = [
    (1.0, 0.0),
    (0.0, 1.0),
    (-1.0, 0.0),
    (0.0, -1.0),
    (0.5, 0.5),
    (-0.3, -0.3),
    (0.0, 0.0),
  ]
  let c = min_enclosing_circle(pts)
  assert_true(c.cx.abs() < 1.0e-10)
  assert_true(c.cy.abs() < 1.0e-10)
  assert_true((c.r - 1.0).abs() < 1.0e-10)
}
