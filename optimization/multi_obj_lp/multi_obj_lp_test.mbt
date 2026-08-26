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
test "solve_molp_weighted_sum: equal weights reaches the LP optimum" {
  let problem = make_problem()
  let sol = solve_molp_weighted_sum(problem, [0.5, 0.5])
  // Combined objective is 2x + 1.5y with x + y ≤ 10, x, y ≥ 0, whose
  // unique optimum is (x, y) = (10, 0) with value 20.
  assert_true((sol.x[0] - 10.0).abs() < 1.0e-6)
  assert_true(sol.x[1].abs() < 1.0e-6)
  assert_true((sol.objective_values[0] - 10.0).abs() < 1.0e-6)
  assert_true((sol.objective_values[1] - 30.0).abs() < 1.0e-6)
}

///|
test "solve_molp_weighted_sum: weight [0, 1] prefers the second objective" {
  let problem = make_problem()
  let sol = solve_molp_weighted_sum(problem, [0.0, 1.0])
  // max 3x + y s.t. x + y ≤ 10 → (x, y) = (10, 0), value 30.
  assert_true((sol.x[0] - 10.0).abs() < 1.0e-6)
  assert_true((sol.objective_values[1] - 30.0).abs() < 1.0e-6)
}

///|
test "solve_lp: two-constraint vertex" {
  // max x + y s.t. x ≤ 4, y ≤ 6, x, y ≥ 0 → (4, 6), value 10.
  let x = solve_lp([1.0, 1.0], [[1.0, 0.0], [0.0, 1.0]], [4.0, 6.0])
  assert_true((x[0] - 4.0).abs() < 1.0e-6)
  assert_true((x[1] - 6.0).abs() < 1.0e-6)
}

///|
test "solve_lp: negative rhs handled via Big-M" {
  // max x s.t. x ≤ 5, -x ≤ -3 (i.e. x ≥ 3), x ≥ 0 → x = 5.
  let x = solve_lp([1.0], [[1.0], [-1.0]], [5.0, -3.0])
  assert_true((x[0] - 5.0).abs() < 1.0e-6)
}

///|
test "solve_lp: infeasible returns zero vector" {
  // x ≤ -1 with x ≥ 0 is infeasible.
  let x = solve_lp([1.0], [[1.0]], [-1.0])
  assert_true(x[0].abs() < 1.0e-9)
}

///|
test "solve_lp: unbounded returns zero vector" {
  // max x with no binding constraint is unbounded.
  let x = solve_lp([1.0], [[0.0]], [10.0])
  assert_true(x[0].abs() < 1.0e-9)
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
  // main objective x + 2y maximized under x + y ≤ 10 and 3x + y ≥ 5.
  // Optimum: (0, 10) with value 20 satisfies the epsilon constraint.
  assert_true(sol.x[0].abs() < 1.0e-6)
  assert_true((sol.x[1] - 10.0).abs() < 1.0e-6)
  assert_true((sol.objective_values[0] - 20.0).abs() < 1.0e-6)
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
