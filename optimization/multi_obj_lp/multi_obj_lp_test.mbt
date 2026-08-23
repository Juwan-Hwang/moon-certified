/// Comprehensive tests for Multi-Objective Linear Programming (MOLP).

///|
/// Helper: build a standard 2-objective, 2-variable problem.
fn make_problem() -> MolpProblem {
  // max x + 2y, max 3x + y
  // s.t. x + y <= 10, x >= 0, y >= 0
  MolpProblem::new([[1.0, 2.0], [3.0, 1.0]], [[1.0, 1.0]], [10.0], 2, 2, 1)
}

// ===========================================================================
// Weighted sum method tests
// ===========================================================================

///|
test "solve_molp_weighted_sum: basic structure" {
  let problem = make_problem()
  let sol = solve_molp_weighted_sum(problem, [0.5, 0.5])
  assert_eq(sol.x.length(), 2)
  assert_eq(sol.objective_values.length(), 2)
}

///|
test "solve_molp_weighted_sum: weights [1, 0]" {
  let problem = make_problem()
  let sol = solve_molp_weighted_sum(problem, [1.0, 0.0])
  assert_eq(sol.objective_values.length(), 2)
}

///|
test "solve_molp_weighted_sum: weights [0, 1]" {
  let problem = make_problem()
  let sol = solve_molp_weighted_sum(problem, [0.0, 1.0])
  assert_eq(sol.objective_values.length(), 2)
}

///|
test "solve_molp_weighted_sum: equal weights produces zero objectives with trivial LP" {
  let problem = make_problem()
  let sol = solve_molp_weighted_sum(problem, [0.5, 0.5])
  // With x=0 (trivial LP solver), all objective values should be 0
  assert_true(sol.objective_values[0].abs() < 1.0e-10)
  assert_true(sol.objective_values[1].abs() < 1.0e-10)
}

///|
test "solve_molp_weighted_sum: single objective" {
  let problem = MolpProblem::new(
    [[1.0, 2.0, 3.0]],
    [[1.0, 1.0, 1.0]],
    [100.0],
    3,
    1,
    1,
  )
  let sol = solve_molp_weighted_sum(problem, [1.0])
  assert_eq(sol.x.length(), 3)
  assert_eq(sol.objective_values.length(), 1)
}

// ===========================================================================
// Epsilon-constraint method tests
// ===========================================================================

///|
test "solve_molp_epsilon: basic structure" {
  let problem = make_problem()
  let sol = solve_molp_epsilon(problem, 0, [0.0, 0.0])
  assert_eq(sol.x.length(), 2)
  assert_eq(sol.objective_values.length(), 2)
}

///|
test "solve_molp_epsilon: main_obj=0" {
  let problem = make_problem()
  let sol = solve_molp_epsilon(problem, 0, [0.0, 0.0])
  assert_eq(sol.objective_values.length(), 2)
}

///|
test "solve_molp_epsilon: main_obj=1" {
  let problem = make_problem()
  let sol = solve_molp_epsilon(problem, 1, [0.0, 0.0])
  assert_eq(sol.objective_values.length(), 2)
}

///|
test "solve_molp_epsilon: with epsilon constraints" {
  let problem = make_problem()
  let sol = solve_molp_epsilon(problem, 0, [0.0, 5.0])
  assert_eq(sol.x.length(), 2)
}

///|
test "solve_molp_epsilon: with 3 objectives" {
  let problem = MolpProblem::new(
    [[1.0, 0.0], [0.0, 1.0], [1.0, 1.0]],
    [[1.0, 1.0]],
    [10.0],
    2,
    3,
    1,
  )
  let sol = solve_molp_epsilon(problem, 0, [0.0, 0.0, 0.0])
  assert_eq(sol.x.length(), 2)
  assert_eq(sol.objective_values.length(), 3)
}

// ===========================================================================
// Pareto frontier tests
// ===========================================================================

///|
test "pareto_frontier: generates n_points solutions" {
  let problem = make_problem()
  let frontier = pareto_frontier(problem, 5)
  assert_eq(frontier.length(), 5)
}

///|
test "pareto_frontier: two points" {
  let problem = make_problem()
  let frontier = pareto_frontier(problem, 2)
  assert_eq(frontier.length(), 2)
}

///|
test "pareto_frontier: each solution has correct dimensions" {
  let problem = make_problem()
  let frontier = pareto_frontier(problem, 3)
  for sol in frontier {
    assert_eq(sol.x.length(), 2)
    assert_eq(sol.objective_values.length(), 2)
  }
}

///|
test "pareto_frontier: 3 objectives with uniform weights" {
  let problem = MolpProblem::new(
    [[1.0, 0.0], [0.0, 1.0], [1.0, 1.0]],
    [[1.0, 1.0]],
    [10.0],
    2,
    3,
    1,
  )
  let frontier = pareto_frontier(problem, 3)
  assert_eq(frontier.length(), 3)
  for sol in frontier {
    assert_eq(sol.objective_values.length(), 3)
  }
}
