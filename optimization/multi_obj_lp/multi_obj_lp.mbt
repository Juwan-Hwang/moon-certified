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
  { objectives, constraints, rhs, n_vars, n_objectives, n_constraints, }
}

///|
/// LP solution.
pub struct LpSolution {
  x : Array[Double]
  objective_values : Array[Double]
}

///|
/// Solve a single-objective LP with the simplex method:
///
/// max c·x s.t. A·x ≤ b, x ≥ 0
///
/// The problem is put in standard form with slack variables. Rows with a
/// negative right-hand side are multiplied by -1 and receive a surplus and
/// an artificial variable; artificial variables are driven out with the
/// Big-M method. Bland's rule (smallest-subscript pivoting) is used for
/// both entering and leaving variables, which guarantees termination
/// without cycling.
///
/// Returns the optimal vertex, or the zero vector if the LP is unbounded
/// or infeasible.
pub fn solve_lp(
  c : Array[Double],
  a : Array[Array[Double]],
  b : Array[Double],
) -> Array[Double] {
  let n = c.length()
  let m = b.length()
  let zero = Array::make(n, 0.0)
  if n == 0 || m == 0 {
    return zero
  }
  // Count rows that need an artificial variable (b < 0 after negation).
  let mut n_art = 0
  for i = 0; i < m; i = i + 1 {
    if b[i] < 0.0 {
      n_art = n_art + 1
    }
  }
  let cols = n + m + n_art
  let tab : Array[Array[Double]] = []
  let basis = Array::make(m, 0)
  let mut next_art = n + m
  for i = 0; i < m; i = i + 1 {
    let row = Array::make(cols + 1, 0.0)
    if b[i] >= 0.0 {
      for j = 0; j < n; j = j + 1 {
        row[j] = a[i][j]
      }
      row[n + i] = 1.0
      basis[i] = n + i
      row[cols] = b[i]
    } else {
      // Multiply by -1: (-aᵢ)·x ≥ -bᵢ becomes (-aᵢ)·x - sᵢ + tᵢ = -bᵢ
      // with a non-negative right-hand side.
      for j = 0; j < n; j = j + 1 {
        row[j] = -a[i][j]
      }
      row[n + i] = -1.0
      row[next_art] = 1.0
      basis[i] = next_art
      next_art = next_art + 1
      row[cols] = -b[i]
    }
    tab.push(row)
  }
  // Objective row: reduced costs -cⱼ for decision variables and a Big-M
  // penalty for each artificial variable.
  let obj = Array::make(cols + 1, 0.0)
  for j = 0; j < n; j = j + 1 {
    obj[j] = -c[j]
  }
  let big_m = 1.0e7
  for k = 0; k < n_art; k = k + 1 {
    obj[n + m + k] = big_m
  }
  // Eliminate the basic artificial variables from the objective row.
  for i = 0; i < m; i = i + 1 {
    if basis[i] >= n + m {
      let coef = obj[basis[i]]
      if coef != 0.0 {
        for jj = 0; jj < cols + 1; jj = jj + 1 {
          obj[jj] = obj[jj] - coef * tab[i][jj]
        }
      }
    }
  }
  // Simplex iterations.
  let eps = 1.0e-9
  let max_iter = 1000 * (cols + 1)
  let mut iter = 0
  while iter < max_iter {
    iter = iter + 1
    // Entering variable: smallest index with a negative reduced cost.
    let mut pcol = -1
    for j = 0; j < cols; j = j + 1 {
      if pcol < 0 && obj[j] < -eps {
        pcol = j
      }
    }
    if pcol < 0 {
      break // All reduced costs non-negative: optimal.
    }
    // Leaving variable: minimum ratio test, ties broken by smallest basis
    // index (Bland's rule).
    let mut prow = -1
    let mut best_ratio = 0.0
    for i = 0; i < m; i = i + 1 {
      let aij = tab[i][pcol]
      if aij > eps {
        let ratio = tab[i][cols] / aij
        if prow < 0 ||
          ratio < best_ratio - eps ||
          (ratio <= best_ratio + eps && basis[i] < basis[prow]) {
          prow = i
          best_ratio = ratio
        }
      }
    }
    if prow < 0 {
      return zero // Unbounded LP.
    }
    // Pivot on (prow, pcol).
    let piv = tab[prow][pcol]
    for jj = 0; jj < cols + 1; jj = jj + 1 {
      tab[prow][jj] = tab[prow][jj] / piv
    }
    for i = 0; i < m; i = i + 1 {
      if i != prow && tab[i][pcol] != 0.0 {
        let f = tab[i][pcol]
        for jj = 0; jj < cols + 1; jj = jj + 1 {
          tab[i][jj] = tab[i][jj] - f * tab[prow][jj]
        }
      }
    }
    let fobj = obj[pcol]
    if fobj != 0.0 {
      for jj = 0; jj < cols + 1; jj = jj + 1 {
        obj[jj] = obj[jj] - fobj * tab[prow][jj]
      }
    }
    basis[prow] = pcol
  }
  // A positive artificial basic variable means the LP is infeasible.
  for i = 0; i < m; i = i + 1 {
    if basis[i] >= n + m && tab[i][cols] > eps {
      return zero
    }
  }
  // Read the optimal vertex from the basis.
  let x = Array::make(n, 0.0)
  for i = 0; i < m; i = i + 1 {
    if basis[i] < n {
      x[basis[i]] = tab[i][cols]
    }
  }
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
  { x, objective_values: obj_values, }
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
  { x, objective_values: obj_values, }
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
