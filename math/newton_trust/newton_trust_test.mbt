/// Comprehensive tests for Newton's Method with Trust Region.

///|
/// Simple quadratic: f(x) = x^2, grad = [2x], hess = [[2]]
fn quad_f(x : Array[Double]) -> Double {
  x[0] * x[0]
}

///|
fn quad_grad(x : Array[Double]) -> Array[Double] {
  [2.0 * x[0]]
}

///|
fn quad_hess(_x : Array[Double]) -> Array[Array[Double]] {
  [[2.0]]
}

///|
/// Two-dimensional: f(x,y) = (x-3)^2 + (y-5)^2
fn dist_f(x : Array[Double]) -> Double {
  (x[0] - 3.0) * (x[0] - 3.0) + (x[1] - 5.0) * (x[1] - 5.0)
}

///|
fn dist_grad(x : Array[Double]) -> Array[Double] {
  [2.0 * (x[0] - 3.0), 2.0 * (x[1] - 5.0)]
}

///|
fn dist_hess(_x : Array[Double]) -> Array[Array[Double]] {
  [[2.0, 0.0], [0.0, 2.0]]
}

// ===========================================================================
// Default parameters tests
// ===========================================================================

///|
test "default_params: sensible defaults" {
  let p = default_params()
  assert_eq(p.max_iter, 200)
  assert_true(p.grad_tol > 0.0 && p.grad_tol < 1.0)
  assert_true(p.step_tol > 0.0)
  assert_true(p.init_radius > 0.0)
  assert_true(p.max_radius > p.init_radius)
  assert_true(p.eta > 0.0 && p.eta < 1.0)
}

// ===========================================================================
// Convergence tests
// ===========================================================================

///|
test "newton_trust: converges on 1D quadratic" {
  let params = default_params()
  let result = newton_trust_region(quad_f, quad_grad, quad_hess, [10.0], params)
  assert_true(result.converged)
  assert_true(result.x[0].abs() < 0.1)
}

///|
test "newton_trust: converges on 2D quadratic" {
  let params = default_params()
  let result = newton_trust_region(
    dist_f,
    dist_grad,
    dist_hess,
    [0.0, 0.0],
    params,
  )
  assert_true(result.converged)
  assert_true((result.x[0] - 3.0).abs() < 0.5)
  assert_true((result.x[1] - 5.0).abs() < 0.5)
}

///|
test "newton_trust: starts at optimum" {
  let params = default_params()
  let result = newton_trust_region(quad_f, quad_grad, quad_hess, [0.0], params)
  assert_true(result.converged)
  assert_eq(result.iterations, 0)
  assert_true(result.x[0].abs() < 1.0e-6)
}

///|
test "newton_trust: gradient norm is small on convergence" {
  let params = default_params()
  let result = newton_trust_region(quad_f, quad_grad, quad_hess, [5.0], params)
  assert_true(result.gradient_norm < 1.0)
}

///|
test "newton_trust: fval decreases from initial" {
  let params = default_params()
  let x0 = [10.0]
  let f0 = quad_f(x0)
  let result = newton_trust_region(quad_f, quad_grad, quad_hess, x0, params)
  assert_true(result.fval < f0)
}

///|
test "newton_trust: from negative starting point" {
  let params = default_params()
  let result = newton_trust_region(
    quad_f,
    quad_grad,
    quad_hess,
    [-10.0],
    params,
  )
  assert_true(result.converged)
  assert_true(result.x[0].abs() < 0.5)
}

// ===========================================================================
// Trust region parameter tests
// ===========================================================================

///|
test "newton_trust: small max_iter limits iterations" {
  let params = TrustRegionParams::new(1, 1.0e-8, 1.0e-10, 1.0, 1.0e10, 0.1)
  let result = newton_trust_region(quad_f, quad_grad, quad_hess, [10.0], params)
  assert_true(result.iterations <= 1)
}

///|
test "newton_trust: large init_radius" {
  let params = TrustRegionParams::new(200, 1.0e-8, 1.0e-10, 1.0e8, 1.0e10, 0.1)
  let result = newton_trust_region(quad_f, quad_grad, quad_hess, [1.0], params)
  // Should still make progress
  assert_true(result.fval <= quad_f([1.0]))
}

// ===========================================================================
// Result structure tests
// ===========================================================================

///|
test "newton_trust: result has correct dimension" {
  let params = default_params()
  let result = newton_trust_region(
    dist_f,
    dist_grad,
    dist_hess,
    [1.0, 2.0],
    params,
  )
  assert_eq(result.x.length(), 2)
}

///|
test "newton_trust: result fval is non-negative for quadratic" {
  let params = default_params()
  let result = newton_trust_region(quad_f, quad_grad, quad_hess, [3.0], params)
  assert_true(result.fval >= -0.001)
}

///|
test "newton_trust: iterations is non-negative" {
  let params = default_params()
  let result = newton_trust_region(quad_f, quad_grad, quad_hess, [1.0], params)
  assert_true(result.iterations >= 0)
}

///|
test "newton_trust: gradient_norm is non-negative" {
  let params = default_params()
  let result = newton_trust_region(
    dist_f,
    dist_grad,
    dist_hess,
    [0.0, 0.0],
    params,
  )
  assert_true(result.gradient_norm >= 0.0)
}
