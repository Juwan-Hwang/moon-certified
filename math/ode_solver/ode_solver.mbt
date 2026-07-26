/// ODE Solvers — Runge-Kutta methods for initial value problems.
///
/// Solves dy/dt = f(t, y) with y(t₀) = y₀ over an interval [t₀, t₁].
/// Includes classical RK4 (4th order), adaptive RK45 (Dormand-Prince),
/// and the simpler Euler and midpoint methods.
///
/// ## Complexity
/// - Time:  O(n) for n steps, with n ∝ 1/h for fixed step.
/// - Space: O(1) per step.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

/// Classical 4th-order Runge-Kutta method (fixed step size).
///
/// Returns the final value y(t₁). Uses `n_steps` equally spaced steps.
pub fn rk4(
  f : (Double, Double) -> Double,
  t0 : Double,
  y0 : Double,
  t1 : Double,
  n_steps : Int,
) -> Double {
  if n_steps <= 0 {
    return y0
  }
  let h = (t1 - t0) / n_steps.to_double()
  let mut t = t0
  let mut y = y0
  for _ in 0..<n_steps {
    let k1 = f(t, y)
    let k2 = f(t + h / 2.0, y + h / 2.0 * k1)
    let k3 = f(t + h / 2.0, y + h / 2.0 * k2)
    let k4 = f(t + h, y + h * k3)
    y = y + h / 6.0 * (k1 + 2.0 * k2 + 2.0 * k3 + k4)
    t = t + h
  }
  y
}

/// RK4 returning the full trajectory at each step.
pub fn rk4_trajectory(
  f : (Double, Double) -> Double,
  t0 : Double,
  y0 : Double,
  t1 : Double,
  n_steps : Int,
) -> Array[(Double, Double)] {
  let result : Array[(Double, Double)] = []
  if n_steps <= 0 {
    result.push((t0, y0))
    return result
  }
  let h = (t1 - t0) / n_steps.to_double()
  let mut t = t0
  let mut y = y0
  result.push((t, y))
  for _ in 0..<n_steps {
    let k1 = f(t, y)
    let k2 = f(t + h / 2.0, y + h / 2.0 * k1)
    let k3 = f(t + h / 2.0, y + h / 2.0 * k2)
    let k4 = f(t + h, y + h * k3)
    y = y + h / 6.0 * (k1 + 2.0 * k2 + 2.0 * k3 + k4)
    t = t + h
    result.push((t, y))
  }
  result
}

/// Explicit Euler method (1st order). Returns final value.
pub fn euler_method(
  f : (Double, Double) -> Double,
  t0 : Double,
  y0 : Double,
  t1 : Double,
  n_steps : Int,
) -> Double {
  if n_steps <= 0 {
    return y0
  }
  let h = (t1 - t0) / n_steps.to_double()
  let mut t = t0
  let mut y = y0
  for _ in 0..<n_steps {
    y = y + h * f(t, y)
    t = t + h
  }
  y
}

/// Midpoint method (2nd order). Returns final value.
pub fn midpoint_method(
  f : (Double, Double) -> Double,
  t0 : Double,
  y0 : Double,
  t1 : Double,
  n_steps : Int,
) -> Double {
  if n_steps <= 0 {
    return y0
  }
  let h = (t1 - t0) / n_steps.to_double()
  let mut t = t0
  let mut y = y0
  for _ in 0..<n_steps {
    let k1 = f(t, y)
    let k2 = f(t + h / 2.0, y + h / 2.0 * k1)
    y = y + h * k2
    t = t + h
  }
  y
}

/// Adaptive RK45 (Dormand-Prince) with error control.
///
/// Uses 4th/5th order embedded pair to estimate error and adjust
/// step size. Returns the final value y(t₁).
pub fn rk45_adaptive(
  f : (Double, Double) -> Double,
  t0 : Double,
  y0 : Double,
  t1 : Double,
  tol : Double,
) -> Double {
  let mut t = t0
  let mut y = y0
  let mut h = (t1 - t0) / 100.0 // Initial step size.
  let direction = if t1 > t0 { 1.0 } else { -1.0 }
  h = h * direction
  let max_iter = 10000
  let mut iter = 0
  while (direction > 0.0 && t < t1) || (direction < 0.0 && t > t1) {
    if iter > max_iter {
      break
    }
    iter = iter + 1
    // Don't overshoot.
    if direction > 0.0 && t + h > t1 {
      h = t1 - t
    } else if direction < 0.0 && t + h < t1 {
      h = t1 - t
    }
    // Dormand-Prince Butcher tableau coefficients.
    let c2 = 1.0 / 5.0
    let c3 = 3.0 / 10.0
    let c4 = 4.0 / 5.0
    let c5 = 8.0 / 9.0
    let k1 = f(t, y)
    let k2 = f(t + c2 * h, y + h * (1.0 / 5.0) * k1)
    let k3 = f(
      t + c3 * h,
      y + h * (3.0 / 40.0 * k1 + 9.0 / 40.0 * k2),
    )
    let k4 = f(
      t + c4 * h,
      y + h * (44.0 / 45.0 * k1 - 56.0 / 15.0 * k2 + 32.0 / 9.0 * k3),
    )
    let k5 = f(
      t + c5 * h,
      y +
      h *
      (
        19372.0 / 6561.0 * k1 - 25360.0 / 2187.0 * k2 + 64448.0 / 6561.0 * k3 - 212.0 / 729.0 * k4
      ),
    )
    let k6 = f(
      t + h,
      y +
      h *
      (
        9017.0 / 3168.0 * k1 - 355.0 / 33.0 * k2 + 46732.0 / 5247.0 * k3 + 49.0 / 176.0 * k4 -
        5103.0 / 18656.0 * k5
      ),
    )
    // 5th order solution.
    let y5 = y +
    h *
    (
      35.0 / 384.0 * k1 + 500.0 / 1113.0 * k3 + 125.0 / 192.0 * k4 - 2187.0 / 6784.0 * k5 +
      11.0 / 84.0 * k6
    )
    // 4th order solution (for error estimation).
    let k7 = f(t + h, y5)
    let y4 = y +
    h *
    (
      5179.0 / 57600.0 * k1 + 7571.0 / 16695.0 * k3 + 393.0 / 640.0 * k4 - 92097.0 / 339200.0 * k5 +
      187.0 / 2100.0 * k6 + 1.0 / 40.0 * k7
    )
    let error = (y5 - y4).abs()
    if error <= tol || h.abs() < 0.000000000000001 {
      t = t + h
      y = y5
      // Increase step size.
      if error > 0 {
        let factor = 0.9 * (tol / error).pow(0.2)
        h = h * (if factor > 5.0 { 5.0 } else { factor })
      } else {
        h = h * 2.0
      }
    } else {
      // Decrease step size.
      let factor = 0.9 * (tol / error).pow(0.2)
      h = h * (if factor < 0.1 { 0.1 } else { factor })
    }
  }
  y
}

/// Helper: double power for fractional exponent.
fn Double::pow(self : Double, e : Double) -> Double {
  @math.exp(e * @math.ln(self))
}

/// Helper: double abs.
fn Double::abs(self : Double) -> Double {
  if self < 0.0 { -self } else { self }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "rk4: exponential growth dy/dt = y" {
  // dy/dt = y, y(0) = 1 → y(t) = e^t
  let result = rk4(fn(_, y) { y }, 0.0, 1.0, 1.0, 100)
  let expected = @math.exp(1.0)
  assert_true((result - expected).abs() < 0.000001)
}

test "rk4: linear dy/dt = 1" {
  // dy/dt = 1, y(0) = 0 → y(t) = t
  let result = rk4(fn(t, _) { t * 0.0 + 1.0 }, 0.0, 0.0, 5.0, 100)
  assert_true((result - 5.0).abs() < 0.0000000001)
}

test "euler: exponential growth" {
  // dy/dt = y, y(0) = 1 → y(1) = e ≈ 2.718
  let result = euler_method(fn(_, y) { y }, 0.0, 1.0, 1.0, 1000)
  let expected = @math.exp(1.0)
  assert_true((result - expected).abs() < 0.01)
}

test "midpoint: exponential growth" {
  let result = midpoint_method(fn(_, y) { y }, 0.0, 1.0, 1.0, 100)
  let expected = @math.exp(1.0)
  assert_true((result - expected).abs() < 0.0001)
}

test "rk4_trajectory: returns all points" {
  let traj = rk4_trajectory(fn(t, _) { t }, 0.0, 0.0, 1.0, 10)
  assert_eq(traj.length(), 11)
  assert_eq(traj[0], (0.0, 0.0))
  assert_true((traj[10].0 - 1.0).abs() < 0.0000000001)
}

test "rk45_adaptive: exponential growth" {
  let result = rk45_adaptive(fn(_, y) { y }, 0.0, 1.0, 1.0, 0.00000001)
  let expected = @math.exp(1.0)
  assert_true((result - expected).abs() < 0.000001)
}
