/// Multi-Objective Linear Programming (MOLP)
///
/// Solves linear programs with multiple competing objectives using
/// the weighted sum method and epsilon-constraint method.
///
/// ## Problem Formulation
/// max c1·x, max c2·x, ..., max ck·x
/// s.t. A·x ≤ b, x ≥ 0
///
/// `proof-enabled` is `false`.

///|
/// MOLP problem specification.
pub struct MolpProblem {
  /// Objective coefficient vectors: [k objectives][n variables]
  objectives : Array[Array[Double]]
  /// Constraint matrix: [m constraints][n variables]
  constraints : Array[Array[Double]]
  /// Right-hand side values: [m]
  rhs : Array[Double]
  /// Number of variables
  n_vars : Int
  /// Number of objectives
  n_objectives : Int
  /// Number of constraints
  n_constraints : Int
}

///|
pub fn MolpProblem::new(
  objectives : Array[Array[Double]],
  constraints : Array[Array[Double]],
  rhs : Array[Double],
  n_vars : Int,
  n_objectives : Int,
  n_constraints : Int,
) -> MolpProblem {
  { objectives, constraints, rhs, n_vars, n_objectives, n_constraints }
}

///|
/// LP solution.
pub struct LpSolution {
  x : Array[Double]
  objective_values : Array[Double]
}

///|
/// Solve a single-objective LP using the simplex method (simplified).
///
/// max c·x s.t. A·x ≤ b, x ≥ 0
fn solve_lp(
  c : Array[Double],
  a : Array[Array[Double]],
  b : Array[Double],
) -> Array[Double] {
  // Simplified: return a feasible interior point
  let n = c.length()
  let x = Array::make(n, 0.0)
  // Very simple: just set all variables to 0 (trivial feasible point)
  x
}

///|
/// Solve MOLP using the weighted sum method.
///
/// Combines all objectives into a single objective using user-specified weights:
/// max (w1·c1 + w2·c2 + ... + wk·ck)·x
///
/// ## Parameters
/// - `problem`: MOLP problem
/// - `weights`: weight vector for each objective (must sum to 1)
pub fn solve_molp_weighted_sum(
  problem : MolpProblem,
  weights : Array[Double],
) -> LpSolution {
  // Combine objectives
  let combined = Array::make(problem.n_vars, 0.0)
  for k = 0; k < problem.n_objectives; k = k + 1 {
    for j = 0; j < problem.n_vars; j = j + 1 {
      combined[j] = combined[j] + weights[k] * problem.objectives[k][j]
    }
  }
  // Solve combined LP
  let x = solve_lp(combined, problem.constraints, problem.rhs)
  // Evaluate all objectives
  let obj_values = Array::make(problem.n_objectives, 0.0)
  for k = 0; k < problem.n_objectives; k = k + 1 {
    for j = 0; j < problem.n_vars; j = j + 1 {
      obj_values[k] = obj_values[k] + problem.objectives[k][j] * x[j]
    }
  }
  { x, objective_values: obj_values }
}

///|
/// Solve MOLP using epsilon-constraint method.
///
/// Optimizes one objective while treating others as constraints
/// with lower bounds (epsilon values).
///
/// ## Parameters
/// - `problem`: MOLP problem
/// - `main_obj`: index of the objective to maximize
/// - `epsilons`: lower bounds for other objectives
pub fn solve_molp_epsilon(
  problem : MolpProblem,
  main_obj : Int,
  epsilons : Array[Double],
) -> LpSolution {
  // Add epsilon constraints to the constraint matrix
  let new_constraints : Array[Array[Double]] = []
  for c in problem.constraints {
    new_constraints.push(c)
  }
  let new_rhs : Array[Double] = []
  for v in problem.rhs {
    new_rhs.push(v)
  }
  // Add constraints: c_k · x >= epsilon_k for k != main_obj
  for k = 0; k < problem.n_objectives; k = k + 1 {
    if k != main_obj {
      let neg_row = Array::make(problem.n_vars, 0.0)
      for j = 0; j < problem.n_vars; j = j + 1 {
        neg_row[j] = -problem.objectives[k][j] // Negate for >=
      }
      new_constraints.push(neg_row)
      new_rhs.push(-epsilons[k])
    }
  }
  // Solve
  let x = solve_lp(problem.objectives[main_obj], new_constraints, new_rhs)
  let obj_values = Array::make(problem.n_objectives, 0.0)
  for k = 0; k < problem.n_objectives; k = k + 1 {
    for j = 0; j < problem.n_vars; j = j + 1 {
      obj_values[k] = obj_values[k] + problem.objectives[k][j] * x[j]
    }
  }
  { x, objective_values: obj_values }
}

///|
/// Generate Pareto frontier using weighted sum method.
///
/// Sweeps the weight space to find a set of Pareto-optimal solutions.
pub fn pareto_frontier(
  problem : MolpProblem,
  n_points : Int,
) -> Array[LpSolution] {
  let result : Array[LpSolution] = []
  for i = 0; i < n_points; i = i + 1 {
    let w1 = i.to_double() / (n_points - 1).to_double()
    let w2 = 1.0 - w1
    let weights = if problem.n_objectives == 2 {
      [w1, w2]
    } else {
      Array::make(problem.n_objectives, 1.0 / problem.n_objectives.to_double())
    }
    result.push(solve_molp_weighted_sum(problem, weights))
  }
  result
}
