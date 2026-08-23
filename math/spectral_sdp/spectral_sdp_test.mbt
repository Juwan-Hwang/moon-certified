/// Comprehensive tests for Spectral SDP solver.

///|
/// Helper: create a simple SDP problem with one constraint.
/// Minimize c·x subject to a·x = b, where x is n×n symmetric.
fn make_simple_problem() -> SdpProblem {
  // n=2, m=1
  // Constraint: x[0][0] + x[1][1] = 1 (trace constraint)
  // Objective: minimize x[0][0] (so c = [[1,0],[0,0]])
  SdpProblem::new(
    [[1.0, 0.0], [0.0, 0.0]],
    [[[1.0, 0.0], [0.0, 1.0]]],
    [1.0],
    2,
    1,
  )
}

// ===========================================================================
// SdpProblem construction tests
// ===========================================================================

///|
test "sdp_solve: trivial problem with zero iterations" {
  let problem = make_simple_problem()
  let sol = sdp_solve(problem, 0)
  // With 0 iterations, x should be all zeros
  assert_eq(sol.x[0][0], 0.0)
  assert_eq(sol.x[0][1], 0.0)
  assert_eq(sol.x[1][0], 0.0)
  assert_eq(sol.x[1][1], 0.0)
  // Objective = 0 (all zeros)
  assert_true(sol.objective.abs() < 1.0e-10)
}

///|
test "sdp_solve: satisfies constraint after convergence" {
  let problem = make_simple_problem()
  let sol = sdp_solve(problem, 1000)
  // Check constraint: x[0][0] + x[1][1] ≈ 1
  let trace = sol.x[0][0] + sol.x[1][1]
  assert_true((trace - 1.0).abs() < 0.01)
}

///|
test "sdp_solve: objective is computed correctly" {
  let problem = make_simple_problem()
  let sol = sdp_solve(problem, 100)
  // Objective = c[0][0]*x[0][0] + c[0][1]*x[0][1] + c[1][0]*x[1][0] + c[1][1]*x[1][1]
  // = 1*x[0][0] + 0 + 0 + 0 = x[0][0]
  let expected_obj = sol.x[0][0]
  assert_true((sol.objective - expected_obj).abs() < 1.0e-10)
}

///|
test "sdp_solve: violation decreases with more iterations" {
  let problem = make_simple_problem()
  let sol_few = sdp_solve(problem, 1)
  let sol_many = sdp_solve(problem, 100)
  assert_true(sol_many.violation <= sol_few.violation + 1.0e-10)
}

///|
test "sdp_solve: multiple constraints" {
  // n=2, m=2
  // Constraint 1: x[0][0] = 1
  // Constraint 2: x[1][1] = 1
  let problem = SdpProblem::new(
    [[0.0, 0.0], [0.0, 0.0]],
    [[[1.0, 0.0], [0.0, 0.0]], [[0.0, 0.0], [0.0, 1.0]]],
    [1.0, 1.0],
    2,
    2,
  )
  let sol = sdp_solve(problem, 1000)
  assert_true((sol.x[0][0] - 1.0).abs() < 0.01)
  assert_true((sol.x[1][1] - 1.0).abs() < 0.01)
}

///|
test "sdp_solve: 3x3 problem" {
  // n=3, m=1: trace(x) = 3
  let problem = SdpProblem::new(
    [[1.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]],
    [[[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]]],
    [3.0],
    3,
    1,
  )
  let sol = sdp_solve(problem, 500)
  let trace = sol.x[0][0] + sol.x[1][1] + sol.x[2][2]
  assert_true((trace - 3.0).abs() < 0.05)
}

///|
test "sdp_solve: zero RHS" {
  let problem = SdpProblem::new(
    [[1.0, 0.0], [0.0, 0.0]],
    [[[1.0, 0.0], [0.0, 1.0]]],
    [0.0],
    2,
    1,
  )
  let sol = sdp_solve(problem, 100)
  // With b=0, the solution should be near zero
  assert_true(sol.x[0][0].abs() < 0.01)
  assert_true(sol.x[1][1].abs() < 0.01)
}

///|
test "sdp_solve: solution y has correct length" {
  let problem = make_simple_problem()
  let sol = sdp_solve(problem, 10)
  assert_eq(sol.y.length(), problem.m)
}

///|
test "sdp_solve: violation is non-negative" {
  let problem = make_simple_problem()
  let sol = sdp_solve(problem, 10)
  assert_true(sol.violation >= 0.0)
}

///|
test "sdp_solve: solution x is n×n" {
  let problem = make_simple_problem()
  let sol = sdp_solve(problem, 10)
  assert_eq(sol.x.length(), problem.n)
  for row in sol.x {
    assert_eq(row.length(), problem.n)
  }
}
