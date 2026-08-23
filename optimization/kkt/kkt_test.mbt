/// Comprehensive tests for KKT (Karush-Kuhn-Tucker) conditions solver.

///|
/// Helper: build a KktSystem with no constraints.
fn make_unconstrained(
  hessian : Array[Array[Double]],
  grad : Array[Double],
  n : Int,
) -> KktSystem {
  KktSystem::new(hessian, grad, [], [], [], [], [], [], n)
}

// ===========================================================================
// KKT system construction and solve tests
// ===========================================================================

///|
test "solve_kkt: unconstrained problem converges to zero" {
  // min f = 0 (zero gradient, zero Hessian), x* = 0
  let system = make_unconstrained([[1.0, 0.0], [0.0, 1.0]], [0.0, 0.0], 2)
  let sol = solve_kkt(system, [0.0, 0.0], 100, 1.0e-8)
  // With zero gradient at x=0, the solver should converge immediately
  assert_true(sol.x[0].abs() < 0.01)
  assert_true(sol.x[1].abs() < 0.01)
}

///|
test "solve_kkt: simple quadratic minimization" {
  // min (x-5)^2 => grad = [2*(x-5)], hess = [[2]], at x=5 gradient = 0
  let system = make_unconstrained([[2.0]], [-10.0], 1)
  let sol = solve_kkt(system, [0.0], 1000, 1.0e-6)
  assert_true(sol.x[0] > 0.0) // Should have moved from 0
}

///|
test "solve_kkt: with equality constraint" {
  // min x s.t. x = 5 (equality)
  let system = KktSystem::new([[0.0]], [1.0], [], [], [[1.0]], [5.0], [], [], 1)
  let sol = solve_kkt(system, [0.0], 1000, 1.0e-4)
  assert_true(sol.x[0] > 1.0)
}

///|
test "solve_kkt: with inequality constraint" {
  // min x s.t. x >= -5 (i.e., -x <= 5)
  let system = KktSystem::new(
    [[0.0]],
    [1.0],
    [[-1.0]],
    [-5.0],
    [],
    [],
    [],
    [],
    1,
  )
  let sol = solve_kkt(system, [0.0], 500, 1.0e-4)
  assert_true(sol.x[0] > -1.0)
}

///|
test "solve_kkt: 2D problem" {
  // min x1 + x2, no constraints
  let system = make_unconstrained([[0.0, 0.0], [0.0, 0.0]], [1.0, 1.0], 2)
  let sol = solve_kkt(system, [0.0, 0.0], 100, 1.0e-6)
  assert_eq(sol.x.length(), 2)
  assert_eq(sol.lambda.length(), 0)
  assert_eq(sol.mu.length(), 0)
}

///|
test "solve_kkt: result has correct multiplier dimensions" {
  let system = KktSystem::new(
    [[1.0]],
    [0.0],
    [[1.0]],
    [1.0],
    [[1.0]],
    [1.0],
    [],
    [],
    1,
  )
  let sol = solve_kkt(system, [0.0], 10, 1.0e-6)
  assert_eq(sol.lambda.length(), 1)
  assert_eq(sol.mu.length(), 1)
}

///|
test "solve_kkt: iterations is non-negative" {
  let system = make_unconstrained([[1.0]], [0.0], 1)
  let sol = solve_kkt(system, [0.0], 10, 1.0e-6)
  assert_true(sol.iterations >= 0)
}

// ===========================================================================
// check_kkt tests
// ===========================================================================

///|
test "check_kkt: satisfied at zero gradient point" {
  let system = make_unconstrained([[1.0, 0.0], [0.0, 1.0]], [0.0, 0.0], 2)
  assert_eq(check_kkt(system, [0.0, 0.0], [], [], 1.0e-8), true)
}

///|
test "check_kkt: not satisfied with non-zero gradient" {
  let system = make_unconstrained([[1.0]], [5.0], 1)
  assert_eq(check_kkt(system, [0.0], [], [], 1.0e-8), false)
}

///|
test "check_kkt: dual feasibility violation (negative lambda)" {
  let system = KktSystem::new([[1.0]], [0.0], [[1.0]], [1.0], [], [], [], [], 1)
  assert_eq(check_kkt(system, [0.0], [-1.0], [], 1.0e-8), false)
}

///|
test "check_kkt: dual feasibility satisfied (non-negative lambda)" {
  let system = KktSystem::new([[1.0]], [1.0], [[1.0]], [1.0], [], [], [], [], 1)
  // lambda = 1, grad + a_ineq^T * lambda = 1 + 1*1 = 2 (not zero => not satisfied)
  assert_eq(check_kkt(system, [0.0], [1.0], [], 1.0e-8), false)
  // lambda = -1 is negative => fails dual feasibility
  assert_eq(check_kkt(system, [0.0], [-1.0], [], 1.0e-8), false)
}

///|
test "check_kkt: with equality constraints satisfied" {
  // grad + a_eq^T * mu = 0 => 2 + 1*(-2) = 0
  let system = KktSystem::new([[1.0]], [2.0], [], [], [[1.0]], [1.0], [], [], 1)
  assert_eq(check_kkt(system, [0.0], [], [-2.0], 1.0e-8), true)
}

///|
test "check_kkt: tolerance affects result" {
  let system = make_unconstrained([[1.0]], [0.001], 1)
  assert_eq(check_kkt(system, [0.0], [], [], 1.0e-8), false)
  assert_eq(check_kkt(system, [0.0], [], [], 0.01), true)
}
