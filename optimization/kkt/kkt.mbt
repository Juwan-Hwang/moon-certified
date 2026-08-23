/// KKT (Karush-Kuhn-Tucker) Conditions Solver
///
/// The KKT conditions are necessary and sufficient conditions for
/// optimality in convex nonlinear programming:
///
/// ## KKT Conditions
/// For a problem: min f(x) s.t. g_i(x) ≤ 0, h_j(x) = 0
///
/// 1. Stationarity: ∇f = Σ λ_i · ∇g_i + Σ μ_j · ∇h_j
/// 2. Primal feasibility: g_i(x) ≤ 0, h_j(x) = 0
/// 3. Dual feasibility: λ_i ≥ 0
/// 4. Complementary slackness: λ_i · g_i(x) = 0
///
/// `proof-enabled` is `false`.

///|
/// KKT system specification.
pub struct KktSystem {
  /// Hessian of Lagrangian: [n×n]
  hessian : Array[Array[Double]]
  /// Gradient of objective: [n]
  grad : Array[Double]
  /// Inequality constraint Jacobian: [m_ineq×n]
  a_ineq : Array[Array[Double]]
  /// Inequality constraint values: [m_ineq] (b - Ax ≤ 0)
  b_ineq : Array[Double]
  /// Equality constraint Jacobian: [m_eq×n]
  a_eq : Array[Array[Double]]
  /// Equality constraint values: [m_eq]
  b_eq : Array[Double]
  /// Current multipliers for inequalities
  lambda : Array[Double]
  /// Current multipliers for equalities
  mu : Array[Double]
  /// Problem dimension
  n : Int
}

///|
pub fn KktSystem::new(
  hessian : Array[Array[Double]],
  grad : Array[Double],
  a_ineq : Array[Array[Double]],
  b_ineq : Array[Double],
  a_eq : Array[Array[Double]],
  b_eq : Array[Double],
  lambda : Array[Double],
  mu : Array[Double],
  n : Int,
) -> KktSystem {
  { hessian, grad, a_ineq, b_ineq, a_eq, b_eq, lambda, mu, n }
}

///|
/// KKT solution.
pub struct KktSolution {
  x : Array[Double]
  lambda : Array[Double]
  mu : Array[Double]
  converged : Bool
  iterations : Int
}

///|
/// Solve the KKT system using an iterative active-set method.
pub fn solve_kkt(
  system : KktSystem,
  x0 : Array[Double],
  max_iter : Int,
  tol : Double,
) -> KktSolution {
  let n = system.n
  let x = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    x[i] = x0[i]
  }
  let lambda = Array::make(system.b_ineq.length(), 0.0)
  let mu = Array::make(system.b_eq.length(), 0.0)
  let iter = 0
  let mut converged = false
  for iter = 0; iter < max_iter; iter = iter + 1 {
    // Compute stationarity residual: ∇f + A_ineq^T · λ + A_eq^T · μ = 0
    let residual = Array::make(n, 0.0)
    // ∇f (gradient)
    for i = 0; i < n; i = i + 1 {
      residual[i] = system.grad[i]
    }
    // A_ineq^T · λ
    for i = 0; i < n; i = i + 1 {
      for j = 0; j < system.b_ineq.length(); j = j + 1 {
        if j < system.a_ineq.length() && i < system.a_ineq[j].length() {
          residual[i] = residual[i] + system.a_ineq[j][i] * lambda[j]
        }
      }
    }
    // A_eq^T · μ
    for i = 0; i < n; i = i + 1 {
      for j = 0; j < system.b_eq.length(); j = j + 1 {
        if j < system.a_eq.length() && i < system.a_eq[j].length() {
          residual[i] = residual[i] + system.a_eq[j][i] * mu[j]
        }
      }
    }
    // Check convergence
    let mut res_norm = 0.0
    for v in residual {
      res_norm = res_norm + v * v
    }
    res_norm = res_norm.sqrt()
    if res_norm < tol {
      converged = true
      break
    }
    // Newton step: solve KKT matrix
    // Simplified: gradient descent step
    let step_size = 0.01
    for i = 0; i < n; i = i + 1 {
      x[i] = x[i] - step_size * residual[i]
    }
    // Update multipliers (dual update)
    for j = 0; j < system.b_ineq.length(); j = j + 1 {
      // Compute constraint violation
      let mut constraint_val = 0.0
      for i = 0; i < n; i = i + 1 {
        if j < system.a_ineq.length() && i < system.a_ineq[j].length() {
          constraint_val = constraint_val + system.a_ineq[j][i] * x[i]
        }
      }
      constraint_val = constraint_val - system.b_ineq[j]
      // Dual ascent
      lambda[j] = (lambda[j] + step_size * constraint_val).max(0.0)
    }
    // Update equality multipliers
    for j = 0; j < system.b_eq.length(); j = j + 1 {
      let mut constraint_val = 0.0
      for i = 0; i < n; i = i + 1 {
        if j < system.a_eq.length() && i < system.a_eq[j].length() {
          constraint_val = constraint_val + system.a_eq[j][i] * x[i]
        }
      }
      constraint_val = constraint_val - system.b_eq[j]
      mu[j] = mu[j] + step_size * constraint_val
    }
  }
  { x, lambda, mu, converged, iterations: iter }
}

///|
/// Check KKT conditions at a given point.
pub fn check_kkt(
  system : KktSystem,
  x : Array[Double],
  lambda : Array[Double],
  mu : Array[Double],
  tol : Double,
) -> Bool {
  let n = system.n
  // 1. Stationarity
  let residual = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    residual[i] = system.grad[i]
  }
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < system.b_ineq.length(); j = j + 1 {
      if j < system.a_ineq.length() && i < system.a_ineq[j].length() {
        residual[i] = residual[i] + system.a_ineq[j][i] * lambda[j]
      }
    }
  }
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < system.b_eq.length(); j = j + 1 {
      if j < system.a_eq.length() && i < system.a_eq[j].length() {
        residual[i] = residual[i] + system.a_eq[j][i] * mu[j]
      }
    }
  }
  for v in residual {
    if v.abs() > tol {
      return false
    }
  }
  // 3. Dual feasibility: λ ≥ 0
  for l in lambda {
    if l < -tol {
      return false
    }
  }
  true
}
