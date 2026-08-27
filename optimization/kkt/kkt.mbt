/// KKT (Karush-Kuhn-Tucker) Conditions Solver
///
/// The KKT conditions are necessary and sufficient conditions for
/// optimality in convex nonlinear programming:
///
/// ## KKT Conditions
/// For the convex quadratic program
///
/// min ½·xᵀHx + gᵀx s.t. Aᵢx ≤ bᵢ, Aₑx = bₑ
///
/// 1. Stationarity: Hx + g + Aᵢᵀλ + Aₑᵀμ = 0
/// 2. Primal feasibility: Aᵢx ≤ bᵢ, Aₑx = bₑ
/// 3. Dual feasibility: λ ≥ 0
/// 4. Complementary slackness: λᵢ · (Aᵢx - bᵢ)ᵢ = 0
///
/// `solve_kkt` solves the system with a primal-dual path-following
/// interior-point method: slack variables s ≥ 0 turn the inequalities into
/// Aᵢx + s = bᵢ, the perturbed complementarity condition Λs = τe is solved
/// by Newton steps, and the centering parameter τ → 0 drives the iterate
/// to the exact KKT point. The Newton direction comes from the augmented
/// (symmetric, indefinite) KKT system, solved by Gaussian elimination with
/// partial pivoting plus a small regularization for singular Hessians.
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
  /// Inequality constraint values: [m_ineq] (Aᵢx ≤ bᵢ)
  b_ineq : Array[Double]
  /// Equality constraint Jacobian: [m_eq×n]
  a_eq : Array[Array[Double]]
  /// Equality constraint values: [m_eq] (Aₑx = bₑ)
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
/// Small constant keeping slacks and multipliers strictly interior.
let kkt_interior : Double = 1.0e-6

///|
/// Solve a dense linear system M·z = r by Gaussian elimination with partial
/// pivoting. Returns None if the matrix is numerically singular.
fn solve_linear(
  m : Array[Array[Double]],
  r : Array[Double],
  dim : Int,
) -> Array[Double]? {
  // Work on copies so the caller's data is untouched.
  let a : Array[Array[Double]] = []
  for i = 0; i < dim; i = i + 1 {
    let row = Array::make(dim + 1, 0.0)
    for j = 0; j < dim; j = j + 1 {
      row[j] = m[i][j]
    }
    row[dim] = r[i]
    a.push(row)
  }
  // Forward elimination with partial pivoting.
  for col = 0; col < dim; col = col + 1 {
    let mut piv = col
    for i = col + 1; i < dim; i = i + 1 {
      if a[i][col].abs() > a[piv][col].abs() {
        piv = i
      }
    }
    if a[piv][col].abs() < 1.0e-14 {
      return None
    }
    if piv != col {
      let tmp = a[col]
      a[col] = a[piv]
      a[piv] = tmp
    }
    let inv = 1.0 / a[col][col]
    for i = col + 1; i < dim; i = i + 1 {
      let f = a[i][col] * inv
      if f != 0.0 {
        for j = col; j < dim + 1; j = j + 1 {
          a[i][j] = a[i][j] - f * a[col][j]
        }
      }
    }
  }
  // Back substitution.
  let z = Array::make(dim, 0.0)
  for i = dim - 1; i >= 0; i = i - 1 {
    let mut sum = a[i][dim]
    for j = i + 1; j < dim; j = j + 1 {
      sum = sum - a[i][j] * z[j]
    }
    z[i] = sum / a[i][i]
  }
  Some(z)
}

///|
/// Solve the KKT system of the convex quadratic program
///
/// min ½·xᵀHx + gᵀx s.t. Aᵢx ≤ bᵢ, Aₑx = bₑ
///
/// with a primal-dual path-following interior-point method. The Newton
/// direction (dx, dμ) solves the augmented system
///
/// (H + Aᵢᵀ·diag(λ/s)·Aᵢ)·dx + Aₑᵀ·dμ = -r_d - Aᵢᵀ·w,   Aₑ·dx = -r_pe
///
/// after eliminating the slack and inequality-multiplier updates, where
/// r_d, r_pe are the dual and equality residuals and w carries the
/// perturbed complementarity term τ - Λs. Fraction-to-the-boundary step
/// sizes keep s > 0 and λ > 0, and the centering target τ shrinks the
/// duality gap sᵀλ/m geometrically.
pub fn solve_kkt(
  system : KktSystem,
  x0 : Array[Double],
  max_iter : Int,
  tol : Double,
) -> KktSolution {
  let n = system.n
  let mi = system.b_ineq.length()
  let me = system.b_eq.length()
  let x = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    x[i] = x0[i]
  }
  // Strictly positive multipliers and slacks.
  let lambda = Array::make(mi, 1.0)
  let s = Array::make(mi, 0.0)
  for j = 0; j < mi; j = j + 1 {
    let mut slack = system.b_ineq[j]
    for i = 0; i < n; i = i + 1 {
      slack = slack - system.a_ineq[j][i] * x[i]
    }
    s[j] = if slack > kkt_interior { slack } else { kkt_interior }
  }
  let mu = Array::make(me, 0.0)
  // Regularization for singular/indefinite reduced Hessians.
  let mut h_max = 1.0
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      if system.hessian[i][j].abs() > h_max {
        h_max = system.hessian[i][j].abs()
      }
    }
  }
  let reg = 1.0e-9 * h_max
  let sigma = 0.2 // Centering parameter.
  let boundary = 0.995 // Fraction-to-the-boundary factor.
  let dim = n + me
  let mut converged = false
  let mut iter = 0
  while iter < max_iter {
    iter = iter + 1
    // Residuals: dual, equality primal, inequality primal.
    let r_d = Array::make(n, 0.0)
    for i = 0; i < n; i = i + 1 {
      let mut v = system.grad[i]
      for jj = 0; jj < n; jj = jj + 1 {
        v = v + system.hessian[i][jj] * x[jj]
      }
      for j = 0; j < mi; j = j + 1 {
        v = v + system.a_ineq[j][i] * lambda[j]
      }
      for j = 0; j < me; j = j + 1 {
        v = v + system.a_eq[j][i] * mu[j]
      }
      r_d[i] = v
    }
    let r_pe = Array::make(me, 0.0)
    for j = 0; j < me; j = j + 1 {
      let mut v = -system.b_eq[j]
      for i = 0; i < n; i = i + 1 {
        v = v + system.a_eq[j][i] * x[i]
      }
      r_pe[j] = v
    }
    let r_pi = Array::make(mi, 0.0)
    for j = 0; j < mi; j = j + 1 {
      let mut v = s[j] - system.b_ineq[j]
      for i = 0; i < n; i = i + 1 {
        v = v + system.a_ineq[j][i] * x[i]
      }
      r_pi[j] = v
    }
    // Overall residual norm and duality gap.
    let mut res2 = 0.0
    for v in r_d {
      res2 = res2 + v * v
    }
    for v in r_pe {
      res2 = res2 + v * v
    }
    for v in r_pi {
      res2 = res2 + v * v
    }
    let mut gap = 0.0
    for j = 0; j < mi; j = j + 1 {
      gap = gap + s[j] * lambda[j]
    }
    let gap_norm = if mi > 0 { gap / mi.to_double() } else { 0.0 }
    if res2.sqrt() < tol && gap_norm < tol {
      converged = true
      break
    }
    let tau = sigma * gap_norm
    // Build the augmented KKT system.
    let big = Array::make(dim, Array::make(dim, 0.0))
    let rhs = Array::make(dim, 0.0)
    for i = 0; i < n; i = i + 1 {
      let row = Array::make(dim, 0.0)
      for jj = 0; jj < n; jj = jj + 1 {
        row[jj] = system.hessian[i][jj]
      }
      row[i] = row[i] + reg
      big[i] = row
    }
    // H + Aᵢᵀ·diag(λ/s)·Aᵢ block.
    for j = 0; j < mi; j = j + 1 {
      let coef = lambda[j] / s[j]
      for i = 0; i < n; i = i + 1 {
        let aji = system.a_ineq[j][i]
        if aji != 0.0 {
          for jj = 0; jj < n; jj = jj + 1 {
            big[i][jj] = big[i][jj] + coef * aji * system.a_ineq[j][jj]
          }
        }
      }
    }
    // Equality blocks: Aₑ in rows n.. and Aₑᵀ in columns n..
    for j = 0; j < me; j = j + 1 {
      for i = 0; i < n; i = i + 1 {
        big[n + j][i] = system.a_eq[j][i]
        big[i][n + j] = system.a_eq[j][i]
      }
    }
    // Right-hand side: -r_d - Aᵢᵀ·w with wⱼ = (τ - λⱼsⱼ + λⱼ·r_piⱼ)/sⱼ.
    for i = 0; i < n; i = i + 1 {
      let mut v = -r_d[i]
      for j = 0; j < mi; j = j + 1 {
        let w = (tau - lambda[j] * s[j] + lambda[j] * r_pi[j]) / s[j]
        v = v - system.a_ineq[j][i] * w
      }
      rhs[i] = v
    }
    for j = 0; j < me; j = j + 1 {
      rhs[n + j] = -r_pe[j]
    }
    // Solve for (dx, dμ).
    let step = match solve_linear(big, rhs, dim) {
      Some(z) => z
      None => break // Singular KKT system: no Newton direction.
    }
    let dx = Array::make(n, 0.0)
    for i = 0; i < n; i = i + 1 {
      dx[i] = step[i]
    }
    // Recover ds and dλ.
    let ds = Array::make(mi, 0.0)
    let dl = Array::make(mi, 0.0)
    for j = 0; j < mi; j = j + 1 {
      let mut adi = 0.0
      for i = 0; i < n; i = i + 1 {
        adi = adi + system.a_ineq[j][i] * dx[i]
      }
      ds[j] = -r_pi[j] - adi
      dl[j] = (tau - lambda[j] * s[j] + lambda[j] * r_pi[j]) / s[j] +
        lambda[j] / s[j] * adi
    }
    // Fraction-to-the-boundary step sizes.
    let mut alpha_p = 1.0
    for j = 0; j < mi; j = j + 1 {
      if ds[j] < 0.0 {
        let limit = -boundary * s[j] / ds[j]
        if limit < alpha_p {
          alpha_p = limit
        }
      }
    }
    let mut alpha_d = 1.0
    for j = 0; j < mi; j = j + 1 {
      if dl[j] < 0.0 {
        let limit = -boundary * lambda[j] / dl[j]
        if limit < alpha_d {
          alpha_d = limit
        }
      }
    }
    for i = 0; i < n; i = i + 1 {
      x[i] = x[i] + alpha_p * dx[i]
    }
    for j = 0; j < mi; j = j + 1 {
      s[j] = s[j] + alpha_p * ds[j]
      lambda[j] = lambda[j] + alpha_d * dl[j]
    }
    for j = 0; j < me; j = j + 1 {
      mu[j] = mu[j] + alpha_d * step[n + j]
    }
  }
  { x, lambda, mu, converged, iterations: iter }
}

///|
/// Check all four KKT conditions at a given point (x, λ, μ):
///
/// 1. Stationarity: ‖Hx + g + Aᵢᵀλ + Aₑᵀμ‖∞ ≤ tol
/// 2. Primal feasibility: Aᵢx ≤ bᵢ + tol and ‖Aₑx - bₑ‖∞ ≤ tol
/// 3. Dual feasibility: λᵢ ≥ -tol
/// 4. Complementary slackness: |λᵢ · (Aᵢx - bᵢ)ᵢ| ≤ tol
pub fn check_kkt(
  system : KktSystem,
  x : Array[Double],
  lambda : Array[Double],
  mu : Array[Double],
  tol : Double,
) -> Bool {
  let n = system.n
  // 1. Stationarity: Hx + g + Aᵢᵀλ + Aₑᵀμ = 0.
  for i = 0; i < n; i = i + 1 {
    let mut v = system.grad[i]
    for jj = 0; jj < n; jj = jj + 1 {
      v = v + system.hessian[i][jj] * x[jj]
    }
    for j = 0; j < system.b_ineq.length(); j = j + 1 {
      if j < system.a_ineq.length() && i < system.a_ineq[j].length() {
        v = v + system.a_ineq[j][i] * lambda[j]
      }
    }
    for j = 0; j < system.b_eq.length(); j = j + 1 {
      if j < system.a_eq.length() && i < system.a_eq[j].length() {
        v = v + system.a_eq[j][i] * mu[j]
      }
    }
    if v.abs() > tol {
      return false
    }
  }
  // 2. Primal feasibility.
  for j = 0; j < system.b_ineq.length(); j = j + 1 {
    if j < system.a_ineq.length() {
      let mut v = -system.b_ineq[j]
      for i = 0; i < n; i = i + 1 {
        if i < system.a_ineq[j].length() {
          v = v + system.a_ineq[j][i] * x[i]
        }
      }
      if v > tol {
        return false
      }
      // 4. Complementary slackness: λᵢ · (Aᵢx - bᵢ)ᵢ = 0.
      if j < lambda.length() && (lambda[j] * v).abs() > tol {
        return false
      }
    }
  }
  for j = 0; j < system.b_eq.length(); j = j + 1 {
    if j < system.a_eq.length() {
      let mut v = -system.b_eq[j]
      for i = 0; i < n; i = i + 1 {
        if i < system.a_eq[j].length() {
          v = v + system.a_eq[j][i] * x[i]
        }
      }
      if v.abs() > tol {
        return false
      }
    }
  }
  // 3. Dual feasibility: λ ≥ 0.
  for l in lambda {
    if l < -tol {
      return false
    }
  }
  true
}
