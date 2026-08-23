/// Tests for Bézier curve evaluation and operations.

///|
test "bezier: linear curve (degree 1) endpoints" {
  let cps = [dpoint(0.0, 0.0), dpoint(10.0, 20.0)]
  // B(0) = P0, B(1) = P1
  let p0 = bezier_eval_de_casteljau(cps, 0.0)
  assert_true((p0.x - 0.0).abs() < 1.0e-10)
  assert_true((p0.y - 0.0).abs() < 1.0e-10)
  let p1 = bezier_eval_de_casteljau(cps, 1.0)
  assert_true((p1.x - 10.0).abs() < 1.0e-10)
  assert_true((p1.y - 20.0).abs() < 1.0e-10)
}

///|
test "bezier: linear curve midpoint" {
  let cps = [dpoint(0.0, 0.0), dpoint(10.0, 20.0)]
  let mid = bezier_eval_de_casteljau(cps, 0.5)
  assert_true((mid.x - 5.0).abs() < 1.0e-10)
  assert_true((mid.y - 10.0).abs() < 1.0e-10)
}

///|
test "bezier: quadratic curve endpoints" {
  let cps = [dpoint(0.0, 0.0), dpoint(5.0, 10.0), dpoint(10.0, 0.0)]
  let p0 = bezier_eval_de_casteljau(cps, 0.0)
  assert_true((p0.x - 0.0).abs() < 1.0e-10)
  assert_true((p0.y - 0.0).abs() < 1.0e-10)
  let p2 = bezier_eval_de_casteljau(cps, 1.0)
  assert_true((p2.x - 10.0).abs() < 1.0e-10)
  assert_true((p2.y - 0.0).abs() < 1.0e-10)
}

///|
test "bezier: quadratic curve midpoint" {
  let cps = [dpoint(0.0, 0.0), dpoint(5.0, 10.0), dpoint(10.0, 0.0)]
  // B(0.5) = 0.25*P0 + 0.5*P1 + 0.25*P2 = (5, 5)
  let mid = bezier_eval_de_casteljau(cps, 0.5)
  assert_true((mid.x - 5.0).abs() < 1.0e-10)
  assert_true((mid.y - 5.0).abs() < 1.0e-10)
}

///|
test "bezier: cubic curve endpoints" {
  let cps = [
    dpoint(0.0, 0.0),
    dpoint(1.0, 3.0),
    dpoint(3.0, 3.0),
    dpoint(4.0, 0.0),
  ]
  let p0 = bezier_eval_de_casteljau(cps, 0.0)
  assert_true((p0.x - 0.0).abs() < 1.0e-10)
  assert_true((p0.y - 0.0).abs() < 1.0e-10)
  let p3 = bezier_eval_de_casteljau(cps, 1.0)
  assert_true((p3.x - 4.0).abs() < 1.0e-10)
  assert_true((p3.y - 0.0).abs() < 1.0e-10)
}

///|
test "bezier: cubic curve midpoint" {
  let cps = [
    dpoint(0.0, 0.0),
    dpoint(0.0, 3.0),
    dpoint(3.0, 3.0),
    dpoint(3.0, 0.0),
  ]
  // B(0.5) = (1/8)P0 + (3/8)P1 + (3/8)P2 + (1/8)P3
  // x = 0 + 0 + 9/8 + 3/8 = 12/8 = 1.5
  // y = 0 + 9/8 + 9/8 + 0 = 18/8 = 2.25
  let mid = bezier_eval_de_casteljau(cps, 0.5)
  assert_true((mid.x - 1.5).abs() < 1.0e-10)
  assert_true((mid.y - 2.25).abs() < 1.0e-10)
}

///|
test "bezier: de Casteljau matches Bernstein" {
  let cps = [
    dpoint(0.0, 0.0),
    dpoint(1.0, 3.0),
    dpoint(3.0, 3.0),
    dpoint(4.0, 0.0),
  ]
  for i in 0..<=20 {
    let t = i.to_double() / 20.0
    let p1 = bezier_eval_de_casteljau(cps, t)
    let p2 = bezier_eval_bernstein(cps, t)
    assert_true((p1.x - p2.x).abs() < 1.0e-8)
    assert_true((p1.y - p2.y).abs() < 1.0e-8)
  }
}

///|
test "bezier: quadratic convenience wrapper" {
  let p0 = dpoint(0.0, 0.0)
  let p1 = dpoint(5.0, 10.0)
  let p2 = dpoint(10.0, 0.0)
  let cps = [p0, p1, p2]
  for i in 0..<=10 {
    let t = i.to_double() / 10.0
    let pa = bezier_quad(p0, p1, p2, t)
    let pb = bezier_eval_de_casteljau(cps, t)
    assert_true((pa.x - pb.x).abs() < 1.0e-10)
    assert_true((pa.y - pb.y).abs() < 1.0e-10)
  }
}

///|
test "bezier: cubic convenience wrapper" {
  let cps = [
    dpoint(0.0, 0.0),
    dpoint(0.0, 3.0),
    dpoint(3.0, 3.0),
    dpoint(3.0, 0.0),
  ]
  for i in 0..<=10 {
    let t = i.to_double() / 10.0
    let pa = bezier_cubic(cps[0], cps[1], cps[2], cps[3], t)
    let pb = bezier_eval_de_casteljau(cps, t)
    assert_true((pa.x - pb.x).abs() < 1.0e-10)
    assert_true((pa.y - pb.y).abs() < 1.0e-10)
  }
}

///|
test "bezier: single control point" {
  let cps = [dpoint(5.0, 7.0)]
  let p = bezier_eval_de_casteljau(cps, 0.5)
  assert_true((p.x - 5.0).abs() < 1.0e-10)
  assert_true((p.y - 7.0).abs() < 1.0e-10)
}

///|
test "bezier: empty control points" {
  let cps : Array[DPoint] = []
  let p = bezier_eval_de_casteljau(cps, 0.5)
  assert_true((p.x - 0.0).abs() < 1.0e-10)
  assert_true((p.y - 0.0).abs() < 1.0e-10)
}

///|
test "bezier: first derivative of linear curve" {
  // Linear curve P0=(0,0), P1=(10,20), derivative is constant (10,20)
  let cps = [dpoint(0.0, 0.0), dpoint(10.0, 20.0)]
  let d = bezier_eval_derivative(cps, 0.5)
  assert_true((d.x - 10.0).abs() < 1.0e-10)
  assert_true((d.y - 20.0).abs() < 1.0e-10)
}

///|
test "bezier: first derivative of cubic at endpoints" {
  // Cubic: P0=(0,0), P1=(1,3), P2=(3,3), P3=(4,0)
  // B'(0) = 3*(P1-P0) = (3, 9)
  // B'(1) = 3*(P3-P2) = (3, -9)
  let cps = [
    dpoint(0.0, 0.0),
    dpoint(1.0, 3.0),
    dpoint(3.0, 3.0),
    dpoint(4.0, 0.0),
  ]
  let d0 = bezier_eval_derivative(cps, 0.0)
  assert_true((d0.x - 3.0).abs() < 1.0e-10)
  assert_true((d0.y - 9.0).abs() < 1.0e-10)
  let d1 = bezier_eval_derivative(cps, 1.0)
  assert_true((d1.x - 3.0).abs() < 1.0e-10)
  assert_true((d1.y - -9.0).abs() < 1.0e-10)
}

///|
test "bezier: derivative control points" {
  let cps = [
    dpoint(0.0, 0.0),
    dpoint(1.0, 3.0),
    dpoint(3.0, 3.0),
    dpoint(4.0, 0.0),
  ]
  let dcps = bezier_derivative_control_points(cps)
  assert_eq(dcps.length(), 3)
  // Q0 = 3*(P1-P0) = (3, 9)
  assert_true((dcps[0].x - 3.0).abs() < 1.0e-10)
  assert_true((dcps[0].y - 9.0).abs() < 1.0e-10)
  // Q1 = 3*(P2-P1) = (6, 0)
  assert_true((dcps[1].x - 6.0).abs() < 1.0e-10)
  assert_true((dcps[1].y - 0.0).abs() < 1.0e-10)
  // Q2 = 3*(P3-P2) = (3, -9)
  assert_true((dcps[2].x - 3.0).abs() < 1.0e-10)
  assert_true((dcps[2].y - -9.0).abs() < 1.0e-10)
}

///|
test "bezier: second derivative of cubic at t=0" {
  // B''(0) = n(n-1) * (P2 - 2*P1 + P0) = 6*(3-2, 3-6+0) = 6*(1, -3)
  let cps = [
    dpoint(0.0, 0.0),
    dpoint(1.0, 3.0),
    dpoint(3.0, 3.0),
    dpoint(4.0, 0.0),
  ]
  let d2 = bezier_eval_nth_derivative(cps, 2, 0.0)
  assert_true((d2.x - 6.0).abs() < 1.0e-10)
  assert_true((d2.y - -18.0).abs() < 1.0e-10)
}

///|
test "bezier: nth derivative exceeds degree" {
  let cps = [
    dpoint(0.0, 0.0),
    dpoint(1.0, 3.0),
    dpoint(3.0, 3.0),
    dpoint(4.0, 0.0),
  ]
  // 4th derivative of degree-3 curve is zero
  let d = bezier_eval_nth_derivative(cps, 4, 0.5)
  assert_true((d.x - 0.0).abs() < 1.0e-10)
  assert_true((d.y - 0.0).abs() < 1.0e-10)
}

///|
test "bezier: degree elevation preserves curve" {
  // Start with a quadratic
  let cps = [dpoint(0.0, 0.0), dpoint(5.0, 10.0), dpoint(10.0, 0.0)]
  let elevated = bezier_elevate_degree(cps)
  // Should have 4 control points
  assert_eq(elevated.length(), 4)
  // Endpoints should be preserved
  assert_true((elevated[0].x - 0.0).abs() < 1.0e-10)
  assert_true((elevated[0].y - 0.0).abs() < 1.0e-10)
  assert_true((elevated[3].x - 10.0).abs() < 1.0e-10)
  assert_true((elevated[3].y - 0.0).abs() < 1.0e-10)
  // The elevated curve should produce the same points
  for i in 0..<=10 {
    let t = i.to_double() / 10.0
    let p1 = bezier_eval_de_casteljau(cps, t)
    let p2 = bezier_eval_de_casteljau(elevated, t)
    assert_true((p1.x - p2.x).abs() < 1.0e-8)
    assert_true((p1.y - p2.y).abs() < 1.0e-8)
  }
}

///|
test "bezier: degree elevation linear" {
  // Linear: P0=(0,0), P1=(10,20)
  // Elevated: Q0=(0,0), Q1=(5,10), Q2=(10,20)
  let cps = [dpoint(0.0, 0.0), dpoint(10.0, 20.0)]
  let elevated = bezier_elevate_degree(cps)
  assert_eq(elevated.length(), 3)
  assert_true((elevated[0].x - 0.0).abs() < 1.0e-10)
  assert_true((elevated[0].y - 0.0).abs() < 1.0e-10)
  assert_true((elevated[1].x - 5.0).abs() < 1.0e-10)
  assert_true((elevated[1].y - 10.0).abs() < 1.0e-10)
  assert_true((elevated[2].x - 10.0).abs() < 1.0e-10)
  assert_true((elevated[2].y - 20.0).abs() < 1.0e-10)
}

///|
test "bezier: subdivision preserves curve" {
  let cps = [
    dpoint(0.0, 0.0),
    dpoint(1.0, 3.0),
    dpoint(3.0, 3.0),
    dpoint(4.0, 0.0),
  ]
  let t = 0.3
  let (left, right) = bezier_subdivide(cps, t)
  // Both sub-curves should have same degree
  assert_eq(left.length(), cps.length())
  assert_eq(right.length(), cps.length())
  // Left curve starts at B(0), right curve ends at B(1)
  let p_start = bezier_eval_de_casteljau(left, 0.0)
  let p_end = bezier_eval_de_casteljau(right, 1.0)
  assert_true((p_start.x - cps[0].x).abs() < 1.0e-10)
  assert_true((p_start.y - cps[0].y).abs() < 1.0e-10)
  assert_true((p_end.x - cps[3].x).abs() < 1.0e-10)
  assert_true((p_end.y - cps[3].y).abs() < 1.0e-10)
  // Left curve at t=1 should equal right curve at t=0
  // which equals original at t=0.3
  let p_split_left = bezier_eval_de_casteljau(left, 1.0)
  let p_split_right = bezier_eval_de_casteljau(right, 0.0)
  let p_orig = bezier_eval_de_casteljau(cps, t)
  assert_true((p_split_left.x - p_orig.x).abs() < 1.0e-10)
  assert_true((p_split_left.y - p_orig.y).abs() < 1.0e-10)
  assert_true((p_split_right.x - p_orig.x).abs() < 1.0e-10)
  assert_true((p_split_right.y - p_orig.y).abs() < 1.0e-10)
  // Verify left sub-curve matches original on [0, t]
  // To sample left on [0, t], we evaluate left at s ∈ [0,1]
  // which corresponds to original at t*s
  for i in 0..<=10 {
    let s = i.to_double() / 10.0
    let pl = bezier_eval_de_casteljau(left, s)
    let po = bezier_eval_de_casteljau(cps, t * s)
    assert_true((pl.x - po.x).abs() < 1.0e-8)
    assert_true((pl.y - po.y).abs() < 1.0e-8)
  }
  // Verify right sub-curve matches original on [t, 1]
  for i in 0..<=10 {
    let s = i.to_double() / 10.0
    let pr = bezier_eval_de_casteljau(right, s)
    let orig_t = t + s * (1.0 - t)
    let po = bezier_eval_de_casteljau(cps, orig_t)
    assert_true((pr.x - po.x).abs() < 1.0e-8)
    assert_true((pr.y - po.y).abs() < 1.0e-8)
  }
}

///|
test "bezier: subdivision at 0 and 1" {
  let cps = [dpoint(0.0, 0.0), dpoint(5.0, 10.0), dpoint(10.0, 0.0)]
  // Subdivide at t=0: left is just P0, right is the full curve
  let (left0, right0) = bezier_subdivide(cps, 0.0)
  assert_eq(left0.length(), 3)
  assert_eq(right0.length(), 3)
  assert_true((left0[0].x - 0.0).abs() < 1.0e-10)
  assert_true((left0[0].y - 0.0).abs() < 1.0e-10)
  // Subdivide at t=1: left is the full curve, right is just P_n
  let (left1, right1) = bezier_subdivide(cps, 1.0)
  assert_eq(left1.length(), 3)
  assert_eq(right1.length(), 3)
  assert_true((right1[0].x - 10.0).abs() < 1.0e-10)
  assert_true((right1[0].y - 0.0).abs() < 1.0e-10)
}

///|
test "bezier: arc length of linear curve" {
  // Line from (0,0) to (3,4): length = 5
  let cps = [dpoint(0.0, 0.0), dpoint(3.0, 4.0)]
  let len = bezier_arc_length_default(cps)
  assert_true((len - 5.0).abs() < 1.0e-6)
}

///|
test "bezier: arc length of zero-length curve" {
  let cps = [dpoint(5.0, 5.0)]
  let len = bezier_arc_length_default(cps)
  assert_true((len - 0.0).abs() < 1.0e-10)
}

///|
test "bezier: arc length of quadratic" {
  // Quadratic: P0=(0,0), P1=(1,0), P2=(2,0) — straight line along x-axis
  // Length should be exactly 2.0
  let cps = [dpoint(0.0, 0.0), dpoint(1.0, 0.0), dpoint(2.0, 0.0)]
  let len = bezier_arc_length_default(cps)
  assert_true((len - 2.0).abs() < 1.0e-6)
}

///|
test "bezier: arc length of semicircle approximation" {
  // A cubic Bézier approximating a quarter circle of radius 1
  // Control points for quarter circle (kappa = 0.5522847498...)
  let kappa = 0.5522847498
  let cps = [
    dpoint(1.0, 0.0),
    dpoint(1.0, kappa),
    dpoint(kappa, 1.0),
    dpoint(0.0, 1.0),
  ]
  let len = bezier_arc_length_default(cps)
  // Quarter circle arc length = pi/2 ≈ 1.5707963...
  // Bézier approximation should be close
  assert_true((len - 1.5707963).abs() < 0.01)
}

///|
test "bezier: generate points count" {
  let cps = [dpoint(0.0, 0.0), dpoint(5.0, 10.0), dpoint(10.0, 0.0)]
  let pts = bezier_generate_points(cps, 50)
  assert_eq(pts.length(), 50)
  // First point should be P0
  assert_true((pts[0].x - 0.0).abs() < 1.0e-10)
  assert_true((pts[0].y - 0.0).abs() < 1.0e-10)
  // Last point should be P_n
  assert_true((pts[49].x - 10.0).abs() < 1.0e-10)
  assert_true((pts[49].y - 0.0).abs() < 1.0e-10)
}

///|
test "bezier: generate single point" {
  let cps = [dpoint(3.0, 7.0), dpoint(10.0, 20.0)]
  let pts = bezier_generate_points(cps, 1)
  assert_eq(pts.length(), 1)
  // Single point should be B(0) = P0
  assert_true((pts[0].x - 3.0).abs() < 1.0e-10)
  assert_true((pts[0].y - 7.0).abs() < 1.0e-10)
}

///|
test "bezier: Hermite to Bézier conversion" {
  // P0=(0,0), P1=(3,0), T0=(3,0), T1=(3,0)
  // B0 = (0,0), B1 = (1,0), B2 = (2,0), B3 = (3,0)
  let bps = hermite_to_bezier(
    dpoint(0.0, 0.0),
    dpoint(3.0, 0.0),
    dpoint(3.0, 0.0),
    dpoint(3.0, 0.0),
  )
  assert_eq(bps.length(), 4)
  assert_true((bps[0].x - 0.0).abs() < 1.0e-10)
  assert_true((bps[0].y - 0.0).abs() < 1.0e-10)
  assert_true((bps[1].x - 1.0).abs() < 1.0e-10)
  assert_true((bps[1].y - 0.0).abs() < 1.0e-10)
  assert_true((bps[2].x - 2.0).abs() < 1.0e-10)
  assert_true((bps[2].y - 0.0).abs() < 1.0e-10)
  assert_true((bps[3].x - 3.0).abs() < 1.0e-10)
  assert_true((bps[3].y - 0.0).abs() < 1.0e-10)
}

///|
test "bezier: bounding box of linear curve" {
  let cps = [dpoint(0.0, 0.0), dpoint(10.0, 20.0)]
  let (min_pt, max_pt) = bezier_bounding_box(cps)
  assert_true((min_pt.x - 0.0).abs() < 0.1)
  assert_true((min_pt.y - 0.0).abs() < 0.1)
  assert_true((max_pt.x - 10.0).abs() < 0.1)
  assert_true((max_pt.y - 20.0).abs() < 0.1)
}

///|
test "bezier: bounding box of curved Bézier" {
  // Quadratic: P0=(0,0), P1=(5,10), P2=(10,0)
  // The curve bulges upward; y max is 5.0 (at t=0.5)
  let cps = [dpoint(0.0, 0.0), dpoint(5.0, 10.0), dpoint(10.0, 0.0)]
  let (min_pt, max_pt) = bezier_bounding_box(cps)
  assert_true((min_pt.x - 0.0).abs() < 0.1)
  assert_true((min_pt.y - 0.0).abs() < 0.1)
  assert_true((max_pt.x - 10.0).abs() < 0.1)
  assert_true((max_pt.y - 5.0).abs() < 0.1) // max y is 5.0 at t=0.5
}

///|
test "bezier: high-degree curve de Casteljau stability" {
  // A degree-10 curve — Bernstein form might lose precision,
  // but de Casteljau should be stable
  let cps = [
    dpoint(0.0, 0.0),
    dpoint(1.0, 2.0),
    dpoint(2.0, 1.0),
    dpoint(3.0, 3.0),
    dpoint(4.0, 0.0),
    dpoint(5.0, 2.0),
    dpoint(6.0, 1.0),
    dpoint(7.0, 3.0),
    dpoint(8.0, 0.0),
    dpoint(9.0, 2.0),
    dpoint(10.0, 0.0),
  ]
  // Endpoints
  let p0 = bezier_eval_de_casteljau(cps, 0.0)
  assert_true((p0.x - 0.0).abs() < 1.0e-8)
  assert_true((p0.y - 0.0).abs() < 1.0e-8)
  let p1 = bezier_eval_de_casteljau(cps, 1.0)
  assert_true((p1.x - 10.0).abs() < 1.0e-8)
  assert_true((p1.y - 0.0).abs() < 1.0e-8)
  // de Casteljau and Bernstein should still agree within tolerance
  let p_dc = bezier_eval_de_casteljau(cps, 0.5)
  let p_br = bezier_eval_bernstein(cps, 0.5)
  assert_true((p_dc.x - p_br.x).abs() < 1.0e-6)
  assert_true((p_dc.y - p_br.y).abs() < 1.0e-6)
}

///|
test "bezier: repeated degree elevation" {
  let cps = [dpoint(0.0, 0.0), dpoint(10.0, 0.0)]
  // Elevate 3 times: degree 1 → 2 → 3 → 4
  let mut current = cps
  for _ in 0..<3 {
    current = bezier_elevate_degree(current)
  }
  assert_eq(current.length(), 5)
  // Still represents the same line from (0,0) to (10,0)
  for i in 0..<=10 {
    let t = i.to_double() / 10.0
    let p = bezier_eval_de_casteljau(current, t)
    assert_true((p.x - 10.0 * t).abs() < 1.0e-6)
    assert_true((p.y - 0.0).abs() < 1.0e-6)
  }
}

///|
test "bezier: subdivision recursively" {
  // Recursively subdivide and verify points are still on the original curve
  let cps = [
    dpoint(0.0, 0.0),
    dpoint(1.0, 3.0),
    dpoint(3.0, 3.0),
    dpoint(4.0, 0.0),
  ]
  let (left, _right) = bezier_subdivide(cps, 0.5)
  let (ll, lr) = bezier_subdivide(left, 0.5)
  // left(s) maps to original at t = 0.5 * s
  // ll(s) maps to left at t = 0.5 * s, which maps to original at t = 0.5 * 0.5 * s = 0.25 * s
  // So ll(0.5) = B(0.25 * 0.5) = B(0.125)
  let p_ll = bezier_eval_de_casteljau(ll, 0.5)
  let p_orig = bezier_eval_de_casteljau(cps, 0.125)
  assert_true((p_ll.x - p_orig.x).abs() < 1.0e-8)
  assert_true((p_ll.y - p_orig.y).abs() < 1.0e-8)
  // lr(s) maps to left at t = 0.5 + 0.5 * s, which maps to original at t = 0.5 * (0.5 + 0.5 * s) = 0.25 + 0.25 * s
  // So lr(0.5) = B(0.25 + 0.25 * 0.5) = B(0.375)
  let p_lr = bezier_eval_de_casteljau(lr, 0.5)
  let p_orig2 = bezier_eval_de_casteljau(cps, 0.375)
  assert_true((p_lr.x - p_orig2.x).abs() < 1.0e-8)
  assert_true((p_lr.y - p_orig2.y).abs() < 1.0e-8)
}
