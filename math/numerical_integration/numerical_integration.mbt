/// Numerical Integration — trapezoidal and Simpson's rules.
///
/// Provides adaptive and non-adaptive quadrature methods for computing
/// definite integrals of real-valued functions. Includes composite
/// trapezoidal rule, Simpson's 1/3 rule, and adaptive Simpson with
/// Richardson extrapolation for error control.
///
/// ## Complexity
/// - Time:  O(n) for n subintervals.
/// - Space: O(1) (non-adaptive), O(log(1/ε)) (adaptive).
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

///|
/// Helper: absolute value of double.
fn absd(x : Double) -> Double {
  if x < 0.0 {
    -x
  } else {
    x
  }
}

///|
/// Composite trapezoidal rule: ∫[a,b] f(x) dx.
///
/// Uses `n` subintervals. Error ∝ O(1/n²).
pub fn trapezoidal(
  f : (Double) -> Double,
  a : Double,
  b : Double,
  n : Int,
) -> Double {
  if n <= 0 {
    return 0.0
  }
  let h = (b - a) / n.to_double()
  let mut sum = (f(a) + f(b)) / 2.0
  for i = 1; i < n; i = i + 1 {
    sum = sum + f(a + i.to_double() * h)
  }
  sum * h
}

///|
/// Composite Simpson's 1/3 rule: ∫[a,b] f(x) dx.
///
/// `n` must be even. Uses parabolic approximation. Error ∝ O(1/n⁴).
pub fn simpsons_rule(
  f : (Double) -> Double,
  a : Double,
  b : Double,
  n : Int,
) -> Double {
  if n <= 0 {
    return 0.0
  }
  // Ensure n is even.
  let n = if n % 2 != 0 { n + 1 } else { n }
  let h = (b - a) / n.to_double()
  let mut sum = f(a) + f(b)
  // Odd indices: weight 4.
  for i = 1; i < n; i = i + 2 {
    sum = sum + 4.0 * f(a + i.to_double() * h)
  }
  // Even indices: weight 2.
  for i = 2; i < n; i = i + 2 {
    sum = sum + 2.0 * f(a + i.to_double() * h)
  }
  sum * h / 3.0
}

///|
/// Adaptive Simpson's rule with error control.
///
/// Recursively subdivides intervals where the error estimate exceeds
/// `tol`. Uses Richardson extrapolation: error ≈ |S(a,b) - S(a,m) - S(m,b)| / 15.
pub fn adaptive_simpson(
  f : (Double) -> Double,
  a : Double,
  b : Double,
  tol : Double,
) -> Double {
  let m = (a + b) / 2.0
  let whole = simpsons_3pt(f, a, b, m)
  adaptive_simpson_recursive(f, a, b, m, whole, tol, 0)
}

///|
fn adaptive_simpson_recursive(
  f : (Double) -> Double,
  a : Double,
  b : Double,
  m : Double,
  whole : Double,
  tol : Double,
  depth : Int,
) -> Double {
  if depth > 50 {
    return whole
  }
  let lm = (a + m) / 2.0
  let rm = (m + b) / 2.0
  let left = simpsons_3pt(f, a, m, lm)
  let right = simpsons_3pt(f, m, b, rm)
  let delta = left + right - whole
  if absd(delta) <= 15.0 * tol {
    return left + right + delta / 15.0
  }
  let half_tol = tol / 2.0
  adaptive_simpson_recursive(f, a, m, lm, left, half_tol, depth + 1) +
  adaptive_simpson_recursive(f, m, b, rm, right, half_tol, depth + 1)
}

///|
fn simpsons_3pt(
  f : (Double) -> Double,
  a : Double,
  b : Double,
  m : Double,
) -> Double {
  (b - a) / 6.0 * (f(a) + 4.0 * f(m) + f(b))
}

///|
/// Romberg integration — Richardson extrapolation on trapezoidal rule.
///
/// Computes increasingly accurate estimates by combining trapezoidal
/// approximations at different step sizes. `levels` = number of
/// extrapolation levels (typically 5-10).
pub fn romberg(
  f : (Double) -> Double,
  a : Double,
  b : Double,
  levels : Int,
) -> Double {
  if levels <= 0 {
    return trapezoidal(f, a, b, 1)
  }
  // 2D table: R[i][j] stored at r[i * levels + j].
  let r = FixedArray::make(levels * levels, 0.0)
  r[0] = (b - a) / 2.0 * (f(a) + f(b))
  for i = 1; i < levels; i = i + 1 {
    let n = 1 << i
    let h = (b - a) / n.to_double()
    let mut sum = 0.0
    for k = 1; k <= n / 2; k = k + 1 {
      sum = sum + f(a + (2 * k - 1).to_double() * h)
    }
    r[i * levels] = r[(i - 1) * levels] / 2.0 + h * sum
    for j = 1; j <= i; j = j + 1 {
      let mut factor = 1.0
      for _ in 0..<j {
        factor = factor * 4.0
      }
      r[i * levels + j] = r[i * levels + j - 1] +
        (r[i * levels + j - 1] - r[(i - 1) * levels + j - 1]) / (factor - 1.0)
    }
  }
  r[(levels - 1) * levels + (levels - 1)]
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "trapezoidal: integrate x^2 from 0 to 1" {
  let result = trapezoidal(fn(x) { x * x }, 0.0, 1.0, 100)
  assert_true(absd(result - 0.333333) < 0.01)
}

///|
test "trapezoidal: integrate constant" {
  let result = trapezoidal(fn(_) { 3.0 }, 0.0, 5.0, 10)
  assert_eq(result, 15.0)
}

///|
test "simpsons_rule: integrate x^3 from 0 to 1" {
  let result = simpsons_rule(fn(x) { x * x * x }, 0.0, 1.0, 10)
  assert_true(absd(result - 0.25) < 0.0000000001)
}

///|
test "simpsons_rule: integrate sin" {
  let result = simpsons_rule(@math.sin, 0.0, 3.14159265358979, 100)
  assert_true(absd(result - 2.0) < 0.001)
}

///|
test "adaptive_simpson: integrate exp" {
  let result = adaptive_simpson(@math.exp, 0.0, 1.0, 0.00000001)
  assert_true(absd(result - 1.7182818) < 0.000001)
}

///|
test "romberg: integrate x^2" {
  let result = romberg(fn(x) { x * x }, 0.0, 1.0, 8)
  assert_true(absd(result - 1.0 / 3.0) < 0.0000000001)
}

///|
test "romberg: integrate x^4" {
  let result = romberg(fn(x) { x * x * x * x }, 0.0, 1.0, 8)
  assert_true(absd(result - 0.2) < 0.0000000001)
}
