/// Polynomial Interpolation — Lagrange, Newton, and linear methods.
///
/// Provides three interpolation schemes for constructing polynomials
/// that pass through given data points. Lagrange uses the direct basis,
/// Newton uses divided differences, and linear is the two-point special case.
///
/// ## Complexity
/// - Lagrange: O(n²) time, O(1) space.
/// - Newton:   O(n²) time, O(n) space.
/// - Linear:   O(1) time, O(1) space.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

///|
/// Lagrange polynomial interpolation through (x, y) points.
pub fn lagrange_interpolate(
  points : Array[(Double, Double)],
  x : Double,
) -> Double {
  let n = points.length()
  let mut result = 0.0
  for i = 0; i < n; i = i + 1 {
    let mut term = points[i].1
    for j = 0; j < n; j = j + 1 {
      if i != j {
        term = term * (x - points[j].0) / (points[i].0 - points[j].0)
      }
    }
    result = result + term
  }
  result
}

///|
/// Newton divided-difference interpolation through (x, y) points.
pub fn newton_interpolate(
  points : Array[(Double, Double)],
  x : Double,
) -> Double {
  let n = points.length()
  // In-place divided-difference table; coeff stores the top diagonal.
  let dd = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    dd[i] = points[i].1
  }
  let coeff = Array::make(n, 0.0)
  coeff[0] = dd[0]
  for j = 1; j < n; j = j + 1 {
    for i = 0; i < n - j; i = i + 1 {
      dd[i] = (dd[i + 1] - dd[i]) / (points[i + j].0 - points[i].0)
    }
    coeff[j] = dd[0]
  }
  // Evaluate Newton form: coeff[0] + coeff[1]*(x-x0) + ...
  let mut result = coeff[0]
  let mut term = 1.0
  for i = 1; i < n; i = i + 1 {
    term = term * (x - points[i - 1].0)
    result = result + coeff[i] * term
  }
  result
}

///|
/// Simple linear interpolation between two points.
pub fn linear_interpolate(
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
  x : Double,
) -> Double {
  y0 + (y1 - y0) * (x - x0) / (x1 - x0)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "exact polynomial fit" {
  // Points from y = x²: Lagrange recovers the polynomial exactly.
  let points = [(0.0, 0.0), (1.0, 1.0), (2.0, 4.0)]
  assert_eq(lagrange_interpolate(points, 1.5), 2.25)
}

///|
test "linear case" {
  let points = [(0.0, 0.0), (2.0, 6.0)]
  assert_eq(lagrange_interpolate(points, 1.0), 3.0)
}

///|
test "Newton equals Lagrange" {
  let points = [(0.0, 1.0), (1.0, 2.0), (2.0, 5.0), (3.0, 10.0)]
  let by_newton = newton_interpolate(points, 1.5)
  let by_lagrange = lagrange_interpolate(points, 1.5)
  assert_true((by_newton - by_lagrange).abs() < 0.0000000001)
}

///|
test "linear interpolate" {
  assert_eq(linear_interpolate(0.0, 0.0, 10.0, 100.0, 5.0), 50.0)
}

///|
test "interpolation: single point" {
  let points = [(5.0, 42.0)]
  assert_true((lagrange_interpolate(points, 5.0) - 42.0).abs() < 0.0000000001)
  assert_true((newton_interpolate(points, 5.0) - 42.0).abs() < 0.0000000001)
}

///|
test "interpolation: extrapolation beyond range" {
  // y = 2x from points (1,2) and (3,6)
  let points = [(1.0, 2.0), (3.0, 6.0)]
  assert_true((lagrange_interpolate(points, 10.0) - 20.0).abs() < 0.0000000001)
  assert_true((lagrange_interpolate(points, -5.0) + 10.0).abs() < 0.0000000001)
}

///|
test "interpolation: newton at data point" {
  let points = [(0.0, 1.0), (1.0, 4.0), (2.0, 9.0), (3.0, 16.0)]
  // At x=2, should return exactly y=9
  assert_true((newton_interpolate(points, 2.0) - 9.0).abs() < 0.0000000001)
}

///|
test "interpolation: negative coordinates" {
  let points = [(-3.0, 9.0), (-1.0, 1.0), (1.0, 1.0)]
  // y = x² through these points; at x=0, y=0
  assert_true(lagrange_interpolate(points, 0.0).abs() < 0.0000000001)
}

///|
test "interpolation: linear with negative slope" {
  assert_true(
    (linear_interpolate(0.0, 10.0, 5.0, -5.0, 2.0) - 4.0).abs() < 0.0000000001,
  )
}

///|
test "interpolation: cubic polynomial" {
  // y = x^3 through (0,0), (1,1), (2,8), (3,27)
  let points = [(0.0, 0.0), (1.0, 1.0), (2.0, 8.0), (3.0, 27.0)]
  let by_lagrange = lagrange_interpolate(points, 1.5)
  let by_newton = newton_interpolate(points, 1.5)
  // x=1.5 → 3.375
  assert_true((by_lagrange - 3.375).abs() < 0.0000000001)
  assert_true((by_newton - 3.375).abs() < 0.0000000001)
}
