/// Portfolio Optimization — Markowitz, Efficient Frontier, Black-Litterman.
///
/// Modern portfolio theory, pioneered by Harry Markowitz (1952), provides
/// a mathematical framework for assembling a portfolio of assets such
/// that the expected return is maximised for a given level of risk.
/// This module implements:
///
/// - **Minimum-variance portfolio**: the weights that minimise total
///   portfolio variance `w'Σw` subject to `Σw = 1`.
/// - **Maximum Sharpe (tangency) portfolio**: the portfolio on the
///   efficient frontier with the highest Sharpe ratio.
/// - **Efficient frontier**: the set of optimal portfolios for each
///   target return level.
/// - **Black-Litterman model**: combines the market equilibrium with
///   investor views to produce posterior expected returns.
///
/// ## Markowitz Formulas
///
/// ### Minimum Variance
/// `w_min = Σ⁻¹·1 / (1'·Σ⁻¹·1)`
///
/// ### Maximum Sharpe (tangency)
/// `w_tan = Σ⁻¹·(μ − r_f·1) / (1'·Σ⁻¹·(μ − r_f·1))`
///
/// ### Efficient Frontier (target return μₜ)
/// minimise `w'Σw` s.t. `w'μ = μₜ`, `Σw = 1`
///
/// ## Black-Litterman Model
///
/// 1. **Equilibrium returns**: `Π = δ·Σ·w_mkt`
/// 2. **Posterior returns**:
///    `E[R] = Π + τΣP'(PτΣP' + Ω)⁻¹(Q − PΠ)`
/// 3. Optimise using posterior returns in place of historical means.
///
/// ## Constraints
///
/// Unconstrained solutions (sum-to-1 only) have closed forms. For
/// long-only constraints (w ≥ 0) the `project_to_simplex` function
/// clamps negative weights and renormalises — a fast heuristic.
///
/// ## References
///
/// - H. Markowitz. "Portfolio Selection." Journal of Finance, 1952.
/// - F. Black, R. Litterman. "Global Portfolio Optimization."
///   Financial Analysts Journal, 1991.
/// - R. C. Merton. "An Analytic Derivation of the Efficient Portfolio
///   Frontier." Journal of Financial and Quantitative Analysis, 1972.
///
/// `proof-enabled` is `false`; correctness is backed by test vectors.

// ---------------------------------------------------------------------------
// Matrix Helpers (flat row-major Double arrays)
// ---------------------------------------------------------------------------

///|
/// Matrix-vector multiply: `y = A · x` where A is `rows × cols`.
fn mat_vec_mul(
  a : Array[Double],
  rows : Int,
  cols : Int,
  x : Array[Double],
) -> Array[Double] {
  let y : Array[Double] = Array::make(rows, 0.0)
  for i = 0; i < rows; i = i + 1 {
    let mut s = 0.0
    for j = 0; j < cols; j = j + 1 {
      s = s + a[i * cols + j] * x[j]
    }
    y[i] = s
  }
  y
}

///|
/// Matrix-matrix multiply: `C = A · B` where A is `m×k`, B is `k×n`.
fn mat_mul(
  a : Array[Double],
  b : Array[Double],
  m : Int,
  k : Int,
  n : Int,
) -> Array[Double] {
  let c : Array[Double] = Array::make(m * n, 0.0)
  for i = 0; i < m; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      let mut s = 0.0
      for l = 0; l < k; l = l + 1 {
        s = s + a[i * k + l] * b[l * n + j]
      }
      c[i * n + j] = s
    }
  }
  c
}

///|
/// Transpose an `m × n` matrix.
fn mat_transpose(a : Array[Double], m : Int, n : Int) -> Array[Double] {
  let t : Array[Double] = Array::make(m * n, 0.0)
  for i = 0; i < m; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      t[j * m + i] = a[i * n + j]
    }
  }
  t
}

///|
/// Invert an `n × n` matrix via Gauss-Jordan elimination with partial
/// pivoting. Returns `None` (as an all-zeros matrix) if singular.
fn mat_inverse(a : Array[Double], n : Int) -> Array[Double] {
  // Build augmented matrix [A | I].
  let aug : Array[Double] = Array::make(n * 2 * n, 0.0)
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      aug[i * 2 * n + j] = a[i * n + j]
    }
    aug[i * 2 * n + n + i] = 1.0
  }
  let cols = 2 * n
  for col = 0; col < n; col = col + 1 {
    // Partial pivoting.
    let mut max_row = col
    let mut max_val = aug[col * cols + col].abs()
    for row = col + 1; row < n; row = row + 1 {
      let val = aug[row * cols + col].abs()
      if val > max_val {
        max_val = val
        max_row = row
      }
    }
    if max_row != col {
      for j = 0; j < cols; j = j + 1 {
        let tmp = aug[col * cols + j]
        aug[col * cols + j] = aug[max_row * cols + j]
        aug[max_row * cols + j] = tmp
      }
    }
    let pivot = aug[col * cols + col]
    if pivot.abs() < 1.0e-15 {
      // Singular — return zeros.
      return Array::make(n * n, 0.0)
    }
    // Scale pivot row.
    for j = 0; j < cols; j = j + 1 {
      aug[col * cols + j] = aug[col * cols + j] / pivot
    }
    // Eliminate other rows.
    for row = 0; row < n; row = row + 1 {
      if row != col {
        let factor = aug[row * cols + col]
        if factor != 0.0 {
          for j = col; j < cols; j = j + 1 {
            aug[row * cols + j] = aug[row * cols + j] -
              factor * aug[col * cols + j]
          }
        }
      }
    }
  }
  // Extract inverse from right half.
  let inv : Array[Double] = Array::make(n * n, 0.0)
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      inv[i * n + j] = aug[i * cols + n + j]
    }
  }
  inv
}

///|
/// Dot product of two vectors.
fn vec_dot(a : Array[Double], b : Array[Double]) -> Double {
  let n = a.length()
  let mut s = 0.0
  for i = 0; i < n; i = i + 1 {
    s = s + a[i] * b[i]
  }
  s
}

///|
/// Sum of vector elements.
fn vec_sum(a : Array[Double]) -> Double {
  let mut s = 0.0
  for i = 0; i < a.length(); i = i + 1 {
    s = s + a[i]
  }
  s
}

// ---------------------------------------------------------------------------
// Statistics
// ---------------------------------------------------------------------------

///|
/// Compute the mean return vector from a returns matrix.
///
/// - `returns`: `returns[asset][time]` — each inner array is the time
///   series of returns for one asset.
/// - `n`: Number of assets.
///
/// Returns an array of length `n` with the mean return per asset.
pub fn mean_returns(returns : Array[Array[Double]]) -> Array[Double] {
  let n = returns.length()
  let means : Array[Double] = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    let series = returns[i]
    let t = series.length()
    if t > 0 {
      let mut s = 0.0
      for j = 0; j < t; j = j + 1 {
        s = s + series[j]
      }
      means[i] = s / t.to_double()
    }
  }
  means
}

///|
/// Compute the `n × n` covariance matrix from a returns matrix.
///
/// Uses sample covariance (denominator `T − 1`).
///
/// - `returns`: `returns[asset][time]`.
/// - `n`: Number of assets.
///
/// Returns a flat `n × n` row-major covariance matrix.
pub fn covariance_matrix(
  returns : Array[Array[Double]],
  n : Int,
) -> Array[Double] {
  let cov : Array[Double] = Array::make(n * n, 0.0)
  let means = mean_returns(returns)
  let t = if n > 0 { returns[0].length() } else { 0 }
  if t < 2 {
    return cov
  }
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      let mut s = 0.0
      for k = 0; k < t; k = k + 1 {
        s = s + (returns[i][k] - means[i]) * (returns[j][k] - means[j])
      }
      cov[i * n + j] = s / (t - 1).to_double()
    }
  }
  cov
}

///|
/// Compute portfolio variance `w'Σw`.
pub fn portfolio_variance(
  weights : Array[Double],
  cov : Array[Double],
  n : Int,
) -> Double {
  let mut variance = 0.0
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      variance = variance + weights[i] * cov[i * n + j] * weights[j]
    }
  }
  if variance < 0.0 {
    0.0
  } else {
    variance
  }
}

///|
/// Compute portfolio expected return `w'μ`.
pub fn portfolio_return(
  weights : Array[Double],
  means : Array[Double],
) -> Double {
  vec_dot(weights, means)
}

// ---------------------------------------------------------------------------
// Portfolio Optimisation
// ---------------------------------------------------------------------------

///|
/// Minimum-variance portfolio (unconstrained, sum-to-1).
///
/// `w = Σ⁻¹·1 / (1'·Σ⁻¹·1)`
///
/// - `cov`: `n × n` covariance matrix (flat row-major).
/// - `n`: Number of assets.
///
/// Returns the weight vector of length `n`.
pub fn min_variance_portfolio(cov : Array[Double], n : Int) -> Array[Double] {
  let inv = mat_inverse(cov, n)
  let ones : Array[Double] = Array::make(n, 1.0)
  let inv_ones = mat_vec_mul(inv, n, n, ones)
  let denom = vec_sum(inv_ones)
  if denom.abs() < 1.0e-15 {
    return Array::make(n, 1.0 / n.to_double())
  }
  let w : Array[Double] = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    w[i] = inv_ones[i] / denom
  }
  w
}

///|
/// Maximum Sharpe ratio (tangency) portfolio.
///
/// `w = Σ⁻¹·(μ − r_f·1) / (1'·Σ⁻¹·(μ − r_f·1))`
///
/// - `means`: Expected return vector.
/// - `cov`: `n × n` covariance matrix.
/// - `n`: Number of assets.
/// - `risk_free_rate`: Risk-free rate `r_f`.
pub fn max_sharpe_portfolio(
  means : Array[Double],
  cov : Array[Double],
  n : Int,
  risk_free_rate : Double,
) -> Array[Double] {
  let inv = mat_inverse(cov, n)
  let excess : Array[Double] = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    excess[i] = means[i] - risk_free_rate
  }
  let inv_excess = mat_vec_mul(inv, n, n, excess)
  let denom = vec_sum(inv_excess)
  if denom.abs() < 1.0e-15 {
    return Array::make(n, 1.0 / n.to_double())
  }
  let w : Array[Double] = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    w[i] = inv_excess[i] / denom
  }
  w
}

///|
/// Efficient frontier portfolio for a target return.
///
/// Minimises `w'Σw` subject to `w'μ = target_return` and `w'1 = 1`.
/// Uses the closed-form solution:
///
/// `w = Σ⁻¹·[λ₁·μ + λ₂·1]`
///
/// where `λ₁` and `λ₂` are Lagrange multipliers solved from the
/// constraint system.
///
/// - `means`: Expected return vector.
/// - `cov`: `n × n` covariance matrix.
/// - `n`: Number of assets.
/// - `target_return`: Desired portfolio return.
pub fn efficient_frontier_portfolio(
  means : Array[Double],
  cov : Array[Double],
  n : Int,
  target_return : Double,
) -> Array[Double] {
  let inv = mat_inverse(cov, n)
  // Compute the three scalar quantities needed.
  let inv_mu = mat_vec_mul(inv, n, n, means)
  let ones : Array[Double] = Array::make(n, 1.0)
  let inv_ones = mat_vec_mul(inv, n, n, ones)
  let a = vec_dot(means, inv_mu) // μ'Σ⁻¹μ
  let b = vec_dot(means, inv_ones) // μ'Σ⁻¹1 = 1'Σ⁻¹μ
  let _c = vec_sum(inv_ones) // 1'Σ⁻¹1
  let c = vec_sum(inv_ones)
  let det = a * c - b * b
  if det.abs() < 1.0e-15 {
    return Array::make(n, 1.0 / n.to_double())
  }
  // λ₁ = (c·μₜ − b) / det, λ₂ = (a − b·μₜ) / det
  let lambda1 = (c * target_return - b) / det
  let lambda2 = (a - b * target_return) / det
  let w : Array[Double] = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    w[i] = lambda1 * inv_mu[i] + lambda2 * inv_ones[i]
  }
  w
}

///|
/// Generate the efficient frontier as a set of (return, volatility)
/// points.
///
/// Scans `num_points` target returns from the minimum-return to the
/// maximum-return asset and computes the optimal portfolio for each.
///
/// Returns an array of `(return, volatility)` tuples sorted by
/// return.
pub fn efficient_frontier(
  means : Array[Double],
  cov : Array[Double],
  n : Int,
  num_points : Int,
) -> Array[(Double, Double)] {
  if n == 0 || num_points <= 0 {
    return []
  }
  let mut min_ret = means[0]
  let mut max_ret = means[0]
  for i = 1; i < n; i = i + 1 {
    if means[i] < min_ret {
      min_ret = means[i]
    }
    if means[i] > max_ret {
      max_ret = means[i]
    }
  }
  let frontier : Array[(Double, Double)] = []
  for p = 0; p < num_points; p = p + 1 {
    let target = if num_points == 1 {
      (min_ret + max_ret) / 2.0
    } else {
      min_ret +
      (max_ret - min_ret) * p.to_double() / (num_points - 1).to_double()
    }
    let w = efficient_frontier_portfolio(means, cov, n, target)
    let ret = portfolio_return(w, means)
    let variance = portfolio_variance(w, cov, n)
    let vol = if variance > 0.0 { variance.sqrt() } else { 0.0 }
    frontier.push((ret, vol))
  }
  frontier
}

///|
/// Project weights onto the simplex {w ≥ 0, Σw = 1}.
///
/// Clamps negative weights to zero and renormalises. If all weights
/// are non-positive, returns equal weights.
pub fn project_to_simplex(weights : Array[Double]) -> Array[Double] {
  let n = weights.length()
  let w : Array[Double] = Array::make(n, 0.0)
  let mut sum = 0.0
  for i = 0; i < n; i = i + 1 {
    w[i] = if weights[i] > 0.0 { weights[i] } else { 0.0 }
    sum = sum + w[i]
  }
  if sum <= 0.0 {
    // All non-positive: return equal weights.
    for i = 0; i < n; i = i + 1 {
      w[i] = 1.0 / n.to_double()
    }
  } else {
    for i = 0; i < n; i = i + 1 {
      w[i] = w[i] / sum
    }
  }
  w
}

// ---------------------------------------------------------------------------
// Black-Litterman Model
// ---------------------------------------------------------------------------

///|
/// Compute Black-Litterman posterior expected returns.
///
/// Combines the market-equilibrium prior with investor views:
///
/// `E[R] = Π + τΣP'(PτΣP' + Ω)⁻¹(Q − PΠ)`
///
/// where:
/// - `Π = δ·Σ·w_mkt` is the equilibrium return vector.
/// - `P` is the `k × n` picking matrix (each row is a view).
/// - `Q` is the `k`-vector of view returns.
/// - `Ω` is the `k × k` view-uncertainty matrix.
/// - `τ` is the scalar confidence in the prior.
///
/// - `market_weights`: Current market portfolio weights (length `n`).
/// - `cov`: `n × n` covariance matrix.
/// - `risk_aversion`: Risk aversion coefficient `δ`.
/// - `tau`: Confidence scalar `τ` (typically 0.025–0.05).
/// - `p`: `k × n` picking matrix (flat row-major).
/// - `q`: `k`-vector of view returns.
/// - `omega`: `k × k` view covariance matrix.
/// - `n`: Number of assets.
/// - `k`: Number of views.
///
/// Returns the posterior expected return vector of length `n`.
pub fn black_litterman_returns(
  market_weights : Array[Double],
  cov : Array[Double],
  risk_aversion : Double,
  tau : Double,
  p : Array[Double],
  q : Array[Double],
  omega : Array[Double],
  n : Int,
  k : Int,
) -> Array[Double] {
  // Equilibrium returns: Π = δ · Σ · w_mkt
  let pi = mat_vec_mul(cov, n, n, market_weights)
  for i = 0; i < n; i = i + 1 {
    pi[i] = risk_aversion * pi[i]
  }
  // τΣ
  let tau_cov : Array[Double] = Array::make(n * n, 0.0)
  for i = 0; i < n * n; i = i + 1 {
    tau_cov[i] = tau * cov[i]
  }
  // PτΣ (k × n)
  let p_tau = mat_mul(p, tau_cov, k, n, n)
  // PτΣP' (k × k)
  let p_transpose = mat_transpose(p, k, n)
  let ptp = mat_mul(p_tau, p_transpose, k, n, k)
  // PτΣP' + Ω
  let m : Array[Double] = Array::make(k * k, 0.0)
  for i = 0; i < k * k; i = i + 1 {
    m[i] = ptp[i] + omega[i]
  }
  // (PτΣP' + Ω)^(-1)
  let m_inv = mat_inverse(m, k)
  // Q - PΠ (k-vector)
  let p_pi = mat_vec_mul(p, k, n, pi) // P·Π
  let diff : Array[Double] = Array::make(k, 0.0)
  for i = 0; i < k; i = i + 1 {
    diff[i] = q[i] - p_pi[i]
  }
  // (PτΣP' + Ω)^(-1) · (Q - PΠ) (k-vector)
  let adj = mat_vec_mul(m_inv, k, k, diff)
  // τΣP' · adj (n-vector)
  let tau_cov_p_transpose = mat_mul(tau_cov, p_transpose, n, n, k)
  let posterior_adj = mat_vec_mul(tau_cov_p_transpose, n, k, adj)
  // E[R] = Π + posterior_adj
  let er : Array[Double] = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    er[i] = pi[i] + posterior_adj[i]
  }
  er
}

///|
/// Full Black-Litterman optimisation: compute posterior returns and
/// then find the maximum Sharpe portfolio.
///
/// Returns the optimal portfolio weights.
pub fn black_litterman_portfolio(
  market_weights : Array[Double],
  cov : Array[Double],
  risk_aversion : Double,
  tau : Double,
  p : Array[Double],
  q : Array[Double],
  omega : Array[Double],
  n : Int,
  k : Int,
  risk_free_rate : Double,
) -> Array[Double] {
  let posterior = black_litterman_returns(
    market_weights, cov, risk_aversion, tau, p, q, omega, n, k,
  )
  max_sharpe_portfolio(posterior, cov, n, risk_free_rate)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "covariance: symmetric matrix" {
  let returns : Array[Array[Double]] = [
    [0.01, 0.02, -0.01, 0.03],
    [0.02, -0.01, 0.03, 0.01],
  ]
  let cov = covariance_matrix(returns, 2)
  // Covariance matrix should be symmetric.
  assert_true((cov[0] - cov[3]).abs() < 1.0e-10)
  // Diagonal elements should be positive (variance).
  assert_true(cov[0] > 0.0)
  assert_true(cov[3] > 0.0)
}

///|
test "mean_returns: correct values" {
  let returns : Array[Array[Double]] = [[0.01, 0.02, 0.03], [0.04, 0.05, 0.06]]
  let means = mean_returns(returns)
  assert_true((means[0] - 0.02).abs() < 1.0e-10)
  assert_true((means[1] - 0.05).abs() < 1.0e-10)
}

///|
test "min_variance: two assets" {
  // Asset 1: σ=15%, Asset 2: σ=10%, ρ=0.3
  // σ₁²=0.0225, σ₂²=0.01, σ₁₂=0.0045
  let cov = [0.0225, 0.0045, 0.0045, 0.01]
  let w = min_variance_portfolio(cov, 2)
  // w₁ = (σ₂² − σ₁₂) / (σ₁² + σ₂² − 2σ₁₂)
  //    = (0.01 − 0.0045) / (0.0225 + 0.01 − 0.009)
  //    = 0.0055 / 0.0235 ≈ 0.2340
  let expected_w1 = 0.0055 / 0.0235
  assert_true((w[0] - expected_w1).abs() < 1.0e-6)
  assert_true((w[1] - (1.0 - expected_w1)).abs() < 1.0e-6)
  // Weights sum to 1.
  assert_true((w[0] + w[1] - 1.0).abs() < 1.0e-10)
}

///|
test "min_variance: weights sum to one" {
  let cov = [0.04, 0.01, 0.005, 0.01, 0.09, 0.02, 0.005, 0.02, 0.06]
  let w = min_variance_portfolio(cov, 3)
  assert_true((w[0] + w[1] + w[2] - 1.0).abs() < 1.0e-8)
}

///|
test "min_variance: lower variance than equal weight" {
  let cov = [0.04, 0.01, 0.005, 0.01, 0.09, 0.02, 0.005, 0.02, 0.06]
  let w_min = min_variance_portfolio(cov, 3)
  let w_equal = [1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0]
  let var_min = portfolio_variance(w_min, cov, 3)
  let var_equal = portfolio_variance(w_equal, cov, 3)
  assert_true(var_min <= var_equal + 1.0e-10)
}

///|
test "max_sharpe: two assets" {
  // μ₁=10%, μ₂=5%, σ₁=15%, σ₂=10%, ρ=0.3, rf=2%
  let means = [0.10, 0.05]
  let cov = [0.0225, 0.0045, 0.0045, 0.01]
  let w = max_sharpe_portfolio(means, cov, 2, 0.02)
  // Weights sum to 1.
  assert_true((w[0] + w[1] - 1.0).abs() < 1.0e-8)
  // Higher-return asset gets more weight than min-variance.
  let w_min = min_variance_portfolio(cov, 2)
  assert_true(w[0] > w_min[0])
}

///|
test "max_sharpe: weights sum to one" {
  let means = [0.08, 0.12, 0.06]
  let cov = [0.04, 0.01, 0.005, 0.01, 0.09, 0.02, 0.005, 0.02, 0.06]
  let w = max_sharpe_portfolio(means, cov, 3, 0.03)
  assert_true((w[0] + w[1] + w[2] - 1.0).abs() < 1.0e-8)
}

///|
test "efficient_frontier: two assets" {
  let means = [0.10, 0.05]
  let cov = [0.0225, 0.0045, 0.0045, 0.01]
  let frontier = efficient_frontier(means, cov, 2, 10)
  assert_eq(frontier.length(), 10)
  // Volatility should be positive at all points.
  for i = 0; i < 10; i = i + 1 {
    let (_, vol) = frontier[i]
    assert_true(vol > 0.0)
  }
  // First point should have lower return than last.
  let (ret_first, _) = frontier[0]
  let (ret_last, _) = frontier[9]
  assert_true(ret_first <= ret_last + 1.0e-10)
}

///|
test "efficient_frontier: minimum variance point" {
  // The minimum-variance portfolio should be on the frontier.
  let means = [0.10, 0.05]
  let cov = [0.0225, 0.0045, 0.0045, 0.01]
  let w_min = min_variance_portfolio(cov, 2)
  let var_min = portfolio_variance(w_min, cov, 2)
  // Any frontier portfolio should have variance >= min variance.
  let frontier = efficient_frontier(means, cov, 2, 20)
  for i = 0; i < 20; i = i + 1 {
    let (_, vol) = frontier[i]
    let variance = vol * vol
    assert_true(variance >= var_min - 1.0e-8)
  }
}

///|
test "project_to_simplex: clamps negatives" {
  let w = project_to_simplex([0.3, -0.2, 0.5])
  // After clamping: [0.3, 0, 0.5], sum = 0.8 → [0.375, 0, 0.625]
  assert_true((w[0] - 0.375).abs() < 1.0e-10)
  assert_true(w[1].abs() < 1.0e-10)
  assert_true((w[2] - 0.625).abs() < 1.0e-10)
  assert_true((w[0] + w[1] + w[2] - 1.0).abs() < 1.0e-10)
}

///|
test "project_to_simplex: all negative returns equal" {
  let w = project_to_simplex([-0.1, -0.2, -0.3])
  assert_true((w[0] - 1.0 / 3.0).abs() < 1.0e-10)
  assert_true((w[1] - 1.0 / 3.0).abs() < 1.0e-10)
  assert_true((w[2] - 1.0 / 3.0).abs() < 1.0e-10)
}

///|
test "black_litterman: posterior shifts toward views" {
  // Two assets, market weights 60/40.
  let w_mkt = [0.6, 0.4]
  let cov = [0.04, 0.01, 0.01, 0.0225]
  let delta = 2.5
  let tau = 0.05
  // View: asset 1 will return 15% (absolute view).
  let p = [1.0, 0.0] // k=1, n=2
  let q = [0.15]
  // Ω = τ * P * Σ * P' (standard choice)
  let omega = [
    tau *
    (
      p[0] * cov[0] * p[0] +
      p[0] * cov[1] * p[1] +
      p[1] * cov[2] * p[0] +
      p[1] * cov[3] * p[1]
    ),
  ]
  let posterior = black_litterman_returns(
    w_mkt, cov, delta, tau, p, q, omega, 2, 1,
  )
  // Equilibrium return for asset 1.
  let pi1 = delta * (cov[0] * w_mkt[0] + cov[1] * w_mkt[1])
  // Posterior should shift toward the view (15%).
  assert_true(posterior[0] > pi1)
  assert_true(posterior[0] < 0.15)
}

///|
test "black_litterman: portfolio weights sum to one" {
  let w_mkt = [0.5, 0.3, 0.2]
  let cov = [0.04, 0.01, 0.005, 0.01, 0.09, 0.02, 0.005, 0.02, 0.06]
  let delta = 2.5
  let tau = 0.05
  // View: asset 1 outperforms asset 2 by 5%.
  let p = [1.0, -1.0, 0.0] // k=1, n=3
  let q = [0.05]
  // Ω = τ * P * Σ * P'
  let p_sigma_p = p[0] * cov[0] * p[0] +
    p[0] * cov[1] * p[1] +
    p[0] * cov[2] * p[2] +
    p[1] * cov[3] * p[0] +
    p[1] * cov[4] * p[1] +
    p[1] * cov[5] * p[2] +
    p[2] * cov[6] * p[0] +
    p[2] * cov[7] * p[1] +
    p[2] * cov[8] * p[2]
  let omega = [tau * p_sigma_p]
  let w = black_litterman_portfolio(
    w_mkt, cov, delta, tau, p, q, omega, 3, 1, 0.02,
  )
  assert_true((w[0] + w[1] + w[2] - 1.0).abs() < 1.0e-6)
}
