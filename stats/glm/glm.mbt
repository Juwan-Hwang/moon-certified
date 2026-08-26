/// Generalized Linear Models — IRLS Fitting and Inference.
///
/// This module provides production-grade fitting of Generalized Linear Models
/// via Iteratively Reweighted Least Squares (IRLS), also known as Fisher scoring.
///
/// ## Supported Families
///
/// - **Gaussian**: Identity link (ordinary linear regression).
/// - **Bernoulli**: Logit link (logistic regression) or probit link.
/// - **Poisson**: Log link (count data regression).
/// - **Gamma**: Inverse or log link (positive continuous data).
///
/// ## Algorithm
///
/// IRLS iteratively solves weighted least squares problems:
///
/// 1. Initialize μ = y (adjusted for family/link).
/// 2. Compute η = g(μ), the linear predictor.
/// 3. Compute working weights W and working response z.
/// 4. Solve (XᵀWX)β = XᵀWz via Cholesky decomposition.
/// 5. Update η = Xβ, μ = g⁻¹(η).
/// 6. Repeat until deviance converges.
///
/// ## Inference
///
/// - Standard errors from the diagonal of (XᵀWX)⁻¹.
/// - Deviance, null deviance, and pseudo-R² (McFadden).
/// - AIC and BIC for model comparison.
/// - Log-likelihood of the fitted model.
///
/// ## References
///
/// - Nelder, J. A. & Wedderburn, R. W. M. "Generalized Linear Models,"
///   J. Royal Stat. Soc. A, 135(3), 370–384, 1972.
/// - McCullagh, P. & Nelder, J. A. "Generalized Linear Models," 2nd ed.,
///   Chapman & Hall, 1989.
/// - Hastie, T., Tibshirani, R. & Friedman, J. "The Elements of Statistical
///   Learning," Springer, 2009, Ch. 4.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Enums: Family and Link
// ---------------------------------------------------------------------------

///|
/// Exponential family distribution for the response variable.
pub enum GLMFamily {
  Gaussian // Normal distribution, y ∈ ℝ
  Bernoulli // Binary, y ∈ {0, 1}
  Poisson // Count, y ∈ {0, 1, 2, ...}
  Gamma // Positive continuous, y > 0
} derive(Eq, Debug)

///|
/// Link function g(μ) connecting the mean to the linear predictor.
///
/// The canonical (default) link for each family is:
/// - Gaussian → Identity
/// - Bernoulli → Logit
/// - Poisson → Log
/// - Gamma → Inverse
pub enum GLMLink {
  Identity // g(μ) = μ
  Log // g(μ) = ln(μ)
  Logit // g(μ) = ln(μ / (1 - μ))
  Inverse // g(μ) = 1 / μ
  Probit // g(μ) = Φ⁻¹(μ)
} derive(Eq, Debug)

// ---------------------------------------------------------------------------
// Result struct
// ---------------------------------------------------------------------------

///|
/// Result of fitting a GLM.
pub struct GLMResult {
  /// Fitted coefficients β₀, β₁, …, βₚ (length p+1, including intercept).
  coefficients : FixedArray[Double]
  /// Number of parameters (p+1, including intercept).
  n_params : Int
  /// Number of observations.
  n_obs : Int
  /// Family used.
  family : GLMFamily
  /// Link used.
  link : GLMLink
  /// Residual deviance: D = 2 * (ℓ_sat - ℓ_model).
  deviance : Double
  /// Null deviance (intercept-only model).
  null_deviance : Double
  /// Log-likelihood of the fitted model.
  log_likelihood : Double
  /// Estimated dispersion φ (σ² for Gaussian, 1/ν for Gamma; 1 otherwise).
  dispersion : Double
  /// Akaike Information Criterion: -2ℓ + 2k.
  aic : Double
  /// Bayesian Information Criterion: -2ℓ + k*ln(n).
  bic : Double
  /// McFadden pseudo-R²: 1 - D / D_null.
  pseudo_r_squared : Double
  /// Fitted values μ̂ = g⁻¹(Xβ) (length n).
  fitted_values : FixedArray[Double]
  /// Pearson residuals: (y - μ̂) / sqrt(V(μ̂)) (length n).
  residuals : FixedArray[Double]
  /// Standard errors of the coefficients (length p+1).
  standard_errors : FixedArray[Double]
  /// Number of IRLS iterations until convergence.
  iterations : Int
  /// Whether the algorithm converged.
  converged : Bool
}

// ---------------------------------------------------------------------------
// Link function helpers
// ---------------------------------------------------------------------------

///|
/// Small constant to prevent log(0) and division by zero.
let glm_epsilon : Double = 1.0e-10

///|
/// Link function g(μ): maps the mean to the linear predictor.
fn link_apply(link : GLMLink, mu : Double) -> Double {
  match link {
    Identity => mu
    Log => if mu <= glm_epsilon { @math.ln(glm_epsilon) } else { @math.ln(mu) }
    Logit => {
      let m = if mu < glm_epsilon {
        glm_epsilon
      } else if mu > 1.0 - glm_epsilon {
        1.0 - glm_epsilon
      } else {
        mu
      }
      @math.ln(m / (1.0 - m))
    }
    Inverse => if mu.abs() < glm_epsilon { 1.0 / glm_epsilon } else { 1.0 / mu }
    Probit => {
      // Φ⁻¹(μ) via inverse erf: Φ⁻¹(p) = sqrt(2) * erf⁻¹(2p - 1)
      // We compute erf⁻¹ numerically via the rational approximation.
      let p = if mu < glm_epsilon {
        glm_epsilon
      } else if mu > 1.0 - glm_epsilon {
        1.0 - glm_epsilon
      } else {
        mu
      }
      inverse_normal_cdf(p)
    }
  }
}

///|
/// Inverse link function g⁻¹(η): maps the linear predictor to the mean.
fn link_inverse(link : GLMLink, eta : Double) -> Double {
  match link {
    Identity => eta
    Log =>
      if eta > 700.0 {
        1.0e308
      } else if eta < -700.0 {
        0.0
      } else {
        @math.exp(eta)
      }
    Logit =>
      // sigmoid(η) = 1 / (1 + exp(-η))
      if eta > 35.0 {
        1.0
      } else if eta < -35.0 {
        0.0
      } else {
        1.0 / (1.0 + @math.exp(-eta))
      }
    Inverse =>
      if eta.abs() < glm_epsilon {
        1.0 / glm_epsilon
      } else {
        1.0 / eta
      }
    Probit =>
      // Φ(η) = 0.5 * (1 + erf(η / sqrt(2)))
      @special_functions.normal_cdf(eta)
  }
}

///|
/// Derivative of the inverse link: dμ/dη = 1 / g'(μ).
///
/// Computed directly from the link function's derivative.
fn dmu_deta(link : GLMLink, eta : Double) -> Double {
  match link {
    Identity => 1.0
    Log =>
      // μ = exp(η), dμ/dη = exp(η) = μ
      if eta > 700.0 {
        1.0e308
      } else if eta < -700.0 {
        0.0
      } else {
        @math.exp(eta)
      }
    Logit => {
      // μ = sigmoid(η), dμ/dη = μ * (1 - μ)
      let mu = link_inverse(Logit, eta)
      mu * (1.0 - mu)
    }
    Inverse =>
      // μ = 1/η, dμ/dη = -1/η²
      if eta.abs() < glm_epsilon {
        0.0
      } else {
        -1.0 / (eta * eta)
      }
    Probit =>
      // μ = Φ(η), dμ/dη = φ(η) = normal_pdf(η)
      @special_functions.normal_pdf(eta)
  }
}

// ---------------------------------------------------------------------------
// Variance function
// ---------------------------------------------------------------------------

///|
/// Variance function V(μ) for each family.
///
/// - Gaussian: V(μ) = 1
/// - Bernoulli: V(μ) = μ(1 - μ)
/// - Poisson: V(μ) = μ
/// - Gamma: V(μ) = μ²
fn variance_function(family : GLMFamily, mu : Double) -> Double {
  match family {
    Gaussian => 1.0
    Bernoulli => {
      let m = if mu < glm_epsilon {
        glm_epsilon
      } else if mu > 1.0 - glm_epsilon {
        1.0 - glm_epsilon
      } else {
        mu
      }
      m * (1.0 - m)
    }
    Poisson => if mu < glm_epsilon { glm_epsilon } else { mu }
    Gamma => if mu < glm_epsilon { glm_epsilon * glm_epsilon } else { mu * mu }
  }
}

// ---------------------------------------------------------------------------
// Deviance and log-likelihood
// ---------------------------------------------------------------------------

///|
/// Compute the deviance for a single observation.
///
/// Deviance D = 2 * Σ (ℓ(y_i, y_i) - ℓ(y_i, μ̂_i))
fn deviance_component(family : GLMFamily, y : Double, mu : Double) -> Double {
  let m = if mu < glm_epsilon { glm_epsilon } else { mu }
  match family {
    Gaussian => (y - mu) * (y - mu)
    Bernoulli => {
      // D_i = 2 * [y * ln(y/μ) + (1-y) * ln((1-y)/(1-μ))]
      let y_safe = if y < glm_epsilon { glm_epsilon } else { y }
      let one_minus_y = if y > 1.0 - glm_epsilon {
        glm_epsilon
      } else {
        1.0 - y
      }
      let one_minus_mu = if m > 1.0 - glm_epsilon {
        glm_epsilon
      } else {
        1.0 - m
      }
      2.0 *
      (
        y * @math.ln(y_safe / m) +
        one_minus_y * @math.ln(one_minus_y / one_minus_mu)
      )
    }
    Poisson =>
      // D_i = 2 * [y * ln(y/μ) - (y - μ)]
      if y < glm_epsilon {
        2.0 * m
      } else {
        2.0 * (y * @math.ln(y / m) - (y - m))
      }
    Gamma => {
      // D_i = -2 * [ln(y/μ) - (y - μ)/μ]
      let y_safe = if y < glm_epsilon { glm_epsilon } else { y }
      -2.0 * (@math.ln(y_safe / m) - (y - m) / m)
    }
  }
}

///|
/// Log-likelihood of the fitted model at the maximum-likelihood dispersion.
///
/// - **Gaussian**: σ² is the MLE σ̂² = SSE/n, giving the exact normal
///   log-likelihood -n/2·(ln(2π) + ln σ̂² + 1).
/// - **Bernoulli / Poisson**: the dispersion is fixed at 1 and the
///   per-observation log-likelihoods are summed.
/// - **Gamma**: the shape ν = 1/φ is estimated by maximizing the profile
///   log-likelihood (Newton iteration on ln(ν) - ψ(ν) = s, Lawless 1987),
///   giving the exact Gamma log-likelihood.
///
/// Returns (log-likelihood, dispersion φ).
fn model_log_likelihood(
  family : GLMFamily,
  y : FixedArray[Double],
  mu : FixedArray[Double],
  n : Int,
) -> (Double, Double) {
  match family {
    Gaussian => {
      // MLE of σ² and the exact normal log-likelihood.
      let mut sse = 0.0
      for i = 0; i < n; i = i + 1 {
        let d = y[i] - mu[i]
        sse = sse + d * d
      }
      let sigma2 = if sse < glm_epsilon { glm_epsilon } else { sse / n.to_double() }
      let ll = -0.5 * n.to_double() *
        (@math.ln(2.0 * @math.PI) + @math.ln(sigma2) + 1.0)
      (ll, sigma2)
    }
    Gamma => {
      // Estimate the shape ν = 1/φ via the profile likelihood.
      let nu = gamma_shape_mle(y, mu, n)
      let ln_nu = @math.ln(nu)
      let lgamma_nu = @special_functions.lgamma(nu)
      let mut ll = 0.0
      for i = 0; i < n; i = i + 1 {
        let m = if mu[i] < glm_epsilon { glm_epsilon } else { mu[i] }
        let yy = if y[i] < glm_epsilon { glm_epsilon } else { y[i] }
        // ln f(y; μ, ν) = ν·ln(ν/μ) + (ν-1)·ln(y) - ν·y/μ - ln Γ(ν) - ln(y)
        ll = ll +
          nu * ln_nu -
          nu * @math.ln(m) +
          (nu - 1.0) * @math.ln(yy) -
          nu * yy / m -
          lgamma_nu -
          @math.ln(yy)
      }
      (ll, 1.0 / nu)
    }
    Bernoulli | Poisson => {
      let mut ll = 0.0
      for i = 0; i < n; i = i + 1 {
        ll = ll + loglik_component(family, y[i], mu[i])
      }
      (ll, 1.0)
    }
  }
}

///|
/// Maximum-likelihood shape parameter ν of the Gamma family.
///
/// For z_i = y_i/μ_i the profile score equation is
/// ln(ν) - ψ(ν) = s with s = ln(mean z) - mean(ln z) ≥ 0 (Jensen).
/// The initial estimate is Minka's (2002) closed-form approximation and
/// Newton iterations refine it to machine precision.
fn gamma_shape_mle(
  y : FixedArray[Double],
  mu : FixedArray[Double],
  n : Int,
) -> Double {
  let mut mean_z = 0.0
  let mut mean_ln_z = 0.0
  for i = 0; i < n; i = i + 1 {
    let m = if mu[i] < glm_epsilon { glm_epsilon } else { mu[i] }
    let yy = if y[i] < glm_epsilon { glm_epsilon } else { y[i] }
    let z = yy / m
    mean_z = mean_z + z
    mean_ln_z = mean_ln_z + @math.ln(z)
  }
  mean_z = mean_z / n.to_double()
  mean_ln_z = mean_ln_z / n.to_double()
  let s = @math.ln(mean_z) - mean_ln_z
  if s < 1.0e-14 {
    // Degenerate: y ≈ μ everywhere, variance ≈ 0, shape → ∞.
    return 1.0e12
  }
  // Minka (2002) initial estimate.
  let mut nu = (3.0 - s + ((s - 3.0) * (s - 3.0) + 24.0 * s).sqrt()) /
    (12.0 * s)
  // Newton: f(ν) = ln ν - ψ(ν) - s, f'(ν) = 1/ν - ψ₁(ν) < 0.
  for _ in 0..<100 {
    let f = @math.ln(nu) - @special_functions.digamma(nu) - s
    let fp = 1.0 / nu - @special_functions.trigamma(nu)
    if fp.abs() < glm_epsilon {
      break
    }
    let step = f / fp
    let next = nu - step
    nu = if next > 0.0 { next } else { nu / 2.0 }
    if step.abs() < 1.0e-12 * nu {
      break
    }
  }
  nu
}

///|
/// Per-observation log-likelihood for families with fixed dispersion φ = 1
/// (Bernoulli and Poisson).
fn loglik_component(family : GLMFamily, y : Double, mu : Double) -> Double {
  let m = if mu < glm_epsilon {
    glm_epsilon
  } else if mu > 1.0 - glm_epsilon && family == Bernoulli {
    1.0 - glm_epsilon
  } else {
    mu
  }
  match family {
    Bernoulli => {
      // ln f(y) = y * ln(μ) + (1-y) * ln(1-μ)
      let one_minus_m = if m > 1.0 - glm_epsilon {
        glm_epsilon
      } else {
        1.0 - m
      }
      let y_safe = if y < glm_epsilon { 0.0 } else { y }
      let one_minus_y_safe = if y > 1.0 - glm_epsilon { 0.0 } else { 1.0 - y }
      y_safe * @math.ln(m) + one_minus_y_safe * @math.ln(one_minus_m)
    }
    _ =>
      // ln f(y) = y * ln(μ) - μ - ln(y!)
      if y < 0.5 {
        -m
      } else {
        let y_int = y.to_int()
        let log_y_fact = @special_functions.lgamma(y_int.to_double() + 1.0)
        y * @math.ln(m) - m - log_y_fact
      }
  }
}

// ---------------------------------------------------------------------------
// Inverse normal CDF (for probit link)
// ---------------------------------------------------------------------------

///|
/// Inverse normal CDF: Φ⁻¹(p) computed via the Beasley-Springer-Moro algorithm.
///
/// Accuracy: |error| < 1e-9 for p ∈ (1e-10, 1 - 1e-10).
fn inverse_normal_cdf(p : Double) -> Double {
  if p <= 0.0 {
    return -37.0 // effectively -infinity
  }
  if p >= 1.0 {
    return 37.0
  }
  let p_low = 0.02425
  let p_high = 1.0 - p_low
  if p < p_low {
    // Rational approximation for the lower tail.
    let q = (-2.0 * @math.ln(p)).sqrt()
    return -((
        (
          (
            ((0.0000011979 * q + 0.0000446328) * q + 0.0010692069) * q +
            0.0154898467
          ) *
          q +
          0.0964561526
        ) *
        q +
        0.2726286649
      ) *
      q +
      1.0) /
      (
        (
          (
            (
              ((0.0000147582 * q + 0.0003281942) * q + 0.0039767178) * q +
              0.0294147002
            ) *
            q +
            0.1265684684
          ) *
          q +
          0.3653317468
        ) *
        q +
        1.0
      ) *
      q
  }
  if p > p_high {
    // Rational approximation for the upper tail (by symmetry).
    let q = (-2.0 * @math.ln(1.0 - p)).sqrt()
    return (
        (
          (
            (
              ((0.0000011979 * q + 0.0000446328) * q + 0.0010692069) * q +
              0.0154898467
            ) *
            q +
            0.0964561526
          ) *
          q +
          0.2726286649
        ) *
        q +
        1.0
      ) /
      (
        (
          (
            (
              ((0.0000147582 * q + 0.0003281942) * q + 0.0039767178) * q +
              0.0294147002
            ) *
            q +
            0.1265684684
          ) *
          q +
          0.3653317468
        ) *
        q +
        1.0
      ) *
      q
  }
  // Rational approximation for the central region.
  let q = p - 0.5
  let r = q * q
  -((
    (
      (
        ((0.0003191747 * r + 0.0012629429) * r + 0.0071988996) * r +
        0.0330955232
      ) *
      r +
      0.0900724395
    ) *
    r +
    0.1846357203
  ) *
  r +
  0.2726286649) *
  q /
  (
    (
      (
        (
          ((0.0006905311 * r + 0.0033721437) * r + 0.0249286166) * r +
          0.0981597031
        ) *
        r +
        0.2950377081
      ) *
      r +
      0.6366197726
    ) *
    r +
    1.0
  )
}

// ---------------------------------------------------------------------------
// Matrix helpers (for X'WX operations)
// ---------------------------------------------------------------------------

///|
/// Compute X' * W * X where W is diagonal (weights array).
///
/// X is n × k (row-major), W is length n. Result is k × k (row-major).
fn xtwx(
  x : FixedArray[Double],
  w : FixedArray[Double],
  n : Int,
  k : Int,
) -> FixedArray[Double] {
  let result = FixedArray::make(k * k, 0.0)
  for i = 0; i < k; i = i + 1 {
    for j = 0; j < k; j = j + 1 {
      let mut sum = 0.0
      for obs = 0; obs < n; obs = obs + 1 {
        sum = sum + w[obs] * x[obs * k + i] * x[obs * k + j]
      }
      result[i * k + j] = sum
    }
  }
  result
}

///|
/// Compute X' * W * z where W is diagonal.
///
/// X is n × k, W and z are length n. Result is length k.
fn xtwz(
  x : FixedArray[Double],
  w : FixedArray[Double],
  z : FixedArray[Double],
  n : Int,
  k : Int,
) -> FixedArray[Double] {
  let result = FixedArray::make(k, 0.0)
  for i = 0; i < k; i = i + 1 {
    let mut sum = 0.0
    for obs = 0; obs < n; obs = obs + 1 {
      sum = sum + w[obs] * x[obs * k + i] * z[obs]
    }
    result[i] = sum
  }
  result
}

///|
/// Compute X * beta (matrix-vector multiply). X is n × k, beta is length k.
fn xbeta(
  x : FixedArray[Double],
  beta : FixedArray[Double],
  n : Int,
  k : Int,
) -> FixedArray[Double] {
  let result = FixedArray::make(n, 0.0)
  for obs = 0; obs < n; obs = obs + 1 {
    let mut sum = 0.0
    for j = 0; j < k; j = j + 1 {
      sum = sum + x[obs * k + j] * beta[j]
    }
    result[obs] = sum
  }
  result
}

// ---------------------------------------------------------------------------
// Main fitting function
// ---------------------------------------------------------------------------

///|
/// Maximum number of IRLS iterations.
let max_irls_iterations : Int = 100

///|
/// Convergence threshold for deviance change.
let irls_tolerance : Double = 1.0e-10

///|
/// Fit a Generalized Linear Model using IRLS (Fisher scoring).
///
/// ## Parameters
///
/// - `x`: Design matrix of shape n × k (row-major). The first column should
///   be all 1s if an intercept is desired.
/// - `y`: Response vector of length n.
/// - `n`: Number of observations.
/// - `k`: Number of parameters (including intercept if present).
/// - `family`: Exponential family distribution.
/// - `link`: Link function. If the canonical link is desired, use the
///   appropriate `canonical_link` helper.
///
/// ## Returns
///
/// `None` if the design matrix is degenerate or if IRLS fails to converge
/// numerically (e.g., perfect separation in logistic regression).
pub fn fit_glm(
  x : FixedArray[Double],
  y : FixedArray[Double],
  n : Int,
  k : Int,
  family : GLMFamily,
  link : GLMLink,
) -> GLMResult? {
  if n < 2 || k < 1 || x.length() != n * k || y.length() != n {
    return None
  }
  // Initialize mu based on family.
  let mu = FixedArray::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    match family {
      Gaussian => mu[i] = y[i]
      Bernoulli =>
        // Initialize with (y + 0.5) / 2 to avoid 0 and 1.
        mu[i] = (y[i] + 0.5) / 2.0
      Poisson => mu[i] = if y[i] < 0.1 { 0.1 } else { y[i] }
      Gamma => mu[i] = if y[i] < glm_epsilon { glm_epsilon } else { y[i] }
    }
  }
  // Initialize eta = g(mu).
  let eta = FixedArray::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    eta[i] = link_apply(link, mu[i])
  }
  let beta = FixedArray::make(k, 0.0)
  let mut prev_deviance = 1.0e308
  let mut converged = false
  let mut iter = 0
  while iter < max_irls_iterations {
    iter = iter + 1
    // Compute working weights and working response.
    let w = FixedArray::make(n, 0.0)
    let z = FixedArray::make(n, 0.0)
    for i = 0; i < n; i = i + 1 {
      let dmu = dmu_deta(link, eta[i])
      let dmu_safe = if dmu.abs() < glm_epsilon {
        if dmu >= 0.0 {
          glm_epsilon
        } else {
          -glm_epsilon
        }
      } else {
        dmu
      }
      let vmu = variance_function(family, mu[i])
      let vmu_safe = if vmu < glm_epsilon { glm_epsilon } else { vmu }
      w[i] = dmu_safe * dmu_safe / vmu_safe
      z[i] = eta[i] + (y[i] - mu[i]) / dmu_safe
    }
    // Solve (X'WX) beta = X'Wz via Cholesky.
    let xtwx_mat = xtwx(x, w, n, k)
    let xtwz_vec = xtwz(x, w, z, n, k)
    match @cholesky.decompose(xtwx_mat, k) {
      Some(chol) => {
        let new_beta = @cholesky.solve(chol, xtwz_vec)
        // Update beta.
        for j = 0; j < k; j = j + 1 {
          beta[j] = new_beta[j]
        }
        // Update eta and mu.
        let new_eta = xbeta(x, beta, n, k)
        for i = 0; i < n; i = i + 1 {
          eta[i] = new_eta[i]
          mu[i] = link_inverse(link, eta[i])
        }
      }
      None => {
        // X'WX is not PD — try ridge regularization as a fallback.
        let ridge = 1.0e-8
        for j = 0; j < k; j = j + 1 {
          xtwx_mat[j * k + j] = xtwx_mat[j * k + j] + ridge
        }
        match @cholesky.decompose(xtwx_mat, k) {
          Some(chol) => {
            let new_beta = @cholesky.solve(chol, xtwz_vec)
            for j = 0; j < k; j = j + 1 {
              beta[j] = new_beta[j]
            }
            let new_eta = xbeta(x, beta, n, k)
            for i = 0; i < n; i = i + 1 {
              eta[i] = new_eta[i]
              mu[i] = link_inverse(link, eta[i])
            }
          }
          None => return None
        }
      }
    }
    // Compute deviance.
    let mut dev = 0.0
    for i = 0; i < n; i = i + 1 {
      dev = dev + deviance_component(family, y[i], mu[i])
    }
    // Check convergence.
    if (prev_deviance - dev).abs() < irls_tolerance * (dev.abs() + 0.1) {
      converged = true
      prev_deviance = dev
      break
    }
    prev_deviance = dev
  }
  // Compute final statistics.
  let mut final_deviance = 0.0
  let fitted = FixedArray::make(n, 0.0)
  let resid = FixedArray::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    fitted[i] = mu[i]
    final_deviance = final_deviance + deviance_component(family, y[i], mu[i])
    let vmu = variance_function(family, mu[i])
    let vmu_safe = if vmu < glm_epsilon { glm_epsilon } else { vmu }
    resid[i] = (y[i] - mu[i]) / vmu_safe.sqrt()
  }
  // Log-likelihood at the MLE of the dispersion parameter.
  let (final_loglik, dispersion) = model_log_likelihood(family, y, mu, n)
  // Compute null deviance (intercept-only model).
  let mut y_mean = 0.0
  for i = 0; i < n; i = i + 1 {
    y_mean = y_mean + y[i]
  }
  y_mean = y_mean / n.to_double()
  // For Bernoulli, adjust mean to avoid 0/1.
  match family {
    Bernoulli => {
      if y_mean < glm_epsilon {
        y_mean = glm_epsilon
      }
      if y_mean > 1.0 - glm_epsilon {
        y_mean = 1.0 - glm_epsilon
      }
    }
    Poisson => if y_mean < glm_epsilon { y_mean = glm_epsilon }
    Gamma => if y_mean < glm_epsilon { y_mean = glm_epsilon }
    _ => ()
  }
  let mut null_dev = 0.0
  for i = 0; i < n; i = i + 1 {
    null_dev = null_dev + deviance_component(family, y[i], y_mean)
  }
  // Compute standard errors: sqrt(diag((X'WX)^{-1})).
  let std_errors = FixedArray::make(k, 0.0)
  let w_final = FixedArray::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    let dmu = dmu_deta(link, eta[i])
    let vmu = variance_function(family, mu[i])
    let vmu_safe = if vmu < glm_epsilon { glm_epsilon } else { vmu }
    w_final[i] = dmu * dmu / vmu_safe
  }
  let xtwx_final = xtwx(x, w_final, n, k)
  match @cholesky.decompose(xtwx_final, k) {
    Some(chol) => {
      let inv = @cholesky.inverse(chol)
      for j = 0; j < k; j = j + 1 {
        let var_val = inv[j * k + j]
        std_errors[j] = if var_val > 0.0 { var_val.sqrt() } else { 0.0 }
      }
    }
    None =>
      // If X'WX is singular, set SE to infinity.
      for j = 0; j < k; j = j + 1 {
        std_errors[j] = 1.0e308
      }
  }
  // Pseudo-R² (McFadden).
  let pseudo_r2 = if null_dev.abs() < glm_epsilon {
    1.0
  } else {
    1.0 - final_deviance / null_dev
  }
  // AIC = -2*ℓ + 2*k, BIC = -2*ℓ + k*ln(n). Families with an estimated
  // dispersion (Gaussian, Gamma) count the dispersion as an extra parameter,
  // consistent with R's AIC for glm fits.
  let aic_params = match family {
    Gaussian | Gamma => k + 1
    _ => k
  }
  let aic = -2.0 * final_loglik + 2.0 * aic_params.to_double()
  let bic = -2.0 * final_loglik + aic_params.to_double() * @math.ln(n.to_double())
  Some({
    coefficients: beta,
    n_params: k,
    n_obs: n,
    family,
    link,
    deviance: final_deviance,
    null_deviance: null_dev,
    log_likelihood: final_loglik,
    dispersion,
    aic,
    bic,
    pseudo_r_squared: pseudo_r2,
    fitted_values: fitted,
    residuals: resid,
    standard_errors: std_errors,
    iterations: iter,
    converged,
  })
}

// ---------------------------------------------------------------------------
// Prediction
// ---------------------------------------------------------------------------

///|
/// Predict the mean response μ = g⁻¹(Xβ) for new observations.
///
/// - `result`: A fitted GLM result.
/// - `x_new`: New design matrix of shape m × k (row-major).
/// - `m`: Number of new observations.
///
/// Returns the predicted mean for each observation (length m).
pub fn predict(
  result : GLMResult,
  x_new : FixedArray[Double],
  m : Int,
) -> FixedArray[Double]? {
  if x_new.length() != m * result.n_params {
    return None
  }
  let eta = xbeta(x_new, result.coefficients, m, result.n_params)
  let mu = FixedArray::make(m, 0.0)
  for i = 0; i < m; i = i + 1 {
    mu[i] = link_inverse(result.link, eta[i])
  }
  Some(mu)
}

// ---------------------------------------------------------------------------
// Convenience: canonical link
// ---------------------------------------------------------------------------

///|
/// Get the canonical link function for a given family.
///
/// - Gaussian → Identity
/// - Bernoulli → Logit
/// - Poisson → Log
/// - Gamma → Inverse
pub fn canonical_link(family : GLMFamily) -> GLMLink {
  match family {
    Gaussian => Identity
    Bernoulli => Logit
    Poisson => Log
    Gamma => Inverse
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "glm: linear regression (Gaussian, identity)" {
  // y = 1 + 2*x, no noise.
  // x = [0, 1, 2, 3, 4], y = [1, 3, 5, 7, 9]
  let n = 5
  let k = 2
  let x = FixedArray::make(10, 0.0)
  for i = 0; i < n; i = i + 1 {
    x[i * 2] = 1.0 // intercept
    x[i * 2 + 1] = i.to_double() // x
  }
  let y = FixedArray::make(5, 0.0)
  y[0] = 1.0
  y[1] = 3.0
  y[2] = 5.0
  y[3] = 7.0
  y[4] = 9.0
  match fit_glm(x, y, n, k, Gaussian, Identity) {
    Some(result) => {
      assert_true(result.converged)
      // intercept ≈ 1, slope ≈ 2
      assert_true((result.coefficients[0] - 1.0).abs() < 1.0e-8)
      assert_true((result.coefficients[1] - 2.0).abs() < 1.0e-8)
      // Perfect fit → deviance ≈ 0
      assert_true(result.deviance < 1.0e-10)
      // R² ≈ 1
      assert_true((result.pseudo_r_squared - 1.0).abs() < 1.0e-8)
    }
    None => assert_true(false)
  }
}

///|
test "glm: logistic regression (Bernoulli, logit)" {
  // Simple logistic: y = 1 when x > 0, y = 0 when x < 0.
  // x = [-2, -1, 0, 1, 2], y = [0, 0, 1, 1, 1]
  let n = 5
  let k = 2
  let x = FixedArray::make(10, 0.0)
  x[0] = 1.0
  x[1] = -2.0
  x[2] = 1.0
  x[3] = -1.0
  x[4] = 1.0
  x[5] = 0.0
  x[6] = 1.0
  x[7] = 1.0
  x[8] = 1.0
  x[9] = 2.0
  let y = FixedArray::make(5, 0.0)
  y[0] = 0.0
  y[1] = 0.0
  y[2] = 1.0
  y[3] = 1.0
  y[4] = 1.0
  match fit_glm(x, y, n, k, Bernoulli, Logit) {
    Some(result) => {
      assert_true(result.converged)
      // The slope should be positive (higher x → higher P(y=1)).
      assert_true(result.coefficients[1] > 0.0)
      // Fitted probabilities should be monotonic in x.
      let preds = FixedArray::make(5, 0.0)
      for i = 0; i < 5; i = i + 1 {
        let eta = result.coefficients[0] + result.coefficients[1] * x[i * 2 + 1]
        preds[i] = 1.0 / (1.0 + @math.exp(-eta))
      }
      assert_true(preds[0] < preds[4])
      assert_true(preds[0] < preds[2])
      assert_true(preds[2] < preds[4])
    }
    None => assert_true(false)
  }
}

///|
test "glm: Poisson regression" {
  // Simulate Poisson: λ = exp(0.5 + 0.3*x)
  // x = [0, 1, 2, 3], y = [1, 2, 4, 8] (rounded exp values)
  let n = 4
  let k = 2
  let x = FixedArray::make(8, 0.0)
  x[0] = 1.0
  x[1] = 0.0
  x[2] = 1.0
  x[3] = 1.0
  x[4] = 1.0
  x[5] = 2.0
  x[6] = 1.0
  x[7] = 3.0
  let y = FixedArray::make(4, 0.0)
  y[0] = 1.0
  y[1] = 2.0
  y[2] = 4.0
  y[3] = 8.0
  match fit_glm(x, y, n, k, Poisson, Log) {
    Some(result) => {
      assert_true(result.converged)
      // Slope should be positive (higher x → higher count).
      assert_true(result.coefficients[1] > 0.0)
      // Fitted values should be positive.
      for i = 0; i < n; i = i + 1 {
        assert_true(result.fitted_values[i] > 0.0)
      }
    }
    None => assert_true(false)
  }
}

///|
test "glm: Gaussian with noise" {
  // y = 2 + 0.5*x + noise, check approximate recovery.
  // x = [0, 2, 4, 6, 8, 10], y = [2.1, 3.0, 3.9, 5.1, 6.0, 6.9]
  let n = 6
  let k = 2
  let x = FixedArray::make(12, 0.0)
  x[0] = 1.0
  x[1] = 0.0
  x[2] = 1.0
  x[3] = 2.0
  x[4] = 1.0
  x[5] = 4.0
  x[6] = 1.0
  x[7] = 6.0
  x[8] = 1.0
  x[9] = 8.0
  x[10] = 1.0
  x[11] = 10.0
  let y = FixedArray::make(6, 0.0)
  y[0] = 2.1
  y[1] = 3.0
  y[2] = 3.9
  y[3] = 5.1
  y[4] = 6.0
  y[5] = 6.9
  match fit_glm(x, y, n, k, Gaussian, Identity) {
    Some(result) => {
      assert_true(result.converged)
      // intercept ≈ 2, slope ≈ 0.5
      assert_true((result.coefficients[0] - 2.0).abs() < 0.2)
      assert_true((result.coefficients[1] - 0.5).abs() < 0.05)
      // Standard errors should be positive.
      assert_true(result.standard_errors[0] > 0.0)
      assert_true(result.standard_errors[1] > 0.0)
    }
    None => assert_true(false)
  }
}

///|
test "glm: prediction on new data" {
  // Fit linear, then predict.
  let n = 4
  let k = 2
  let x = FixedArray::make(8, 0.0)
  x[0] = 1.0
  x[1] = 0.0
  x[2] = 1.0
  x[3] = 1.0
  x[4] = 1.0
  x[5] = 2.0
  x[6] = 1.0
  x[7] = 3.0
  let y = FixedArray::make(4, 0.0)
  y[0] = 1.0
  y[1] = 2.0
  y[2] = 3.0
  y[3] = 4.0
  match fit_glm(x, y, n, k, Gaussian, Identity) {
    Some(result) => {
      // Predict for x = [5, 6]
      let x_new = FixedArray::make(4, 0.0)
      x_new[0] = 1.0
      x_new[1] = 5.0
      x_new[2] = 1.0
      x_new[3] = 6.0
      match predict(result, x_new, 2) {
        Some(preds) => {
          // y = 1 + x, so y(5)=6, y(6)=7
          assert_true((preds[0] - 6.0).abs() < 1.0e-8)
          assert_true((preds[1] - 7.0).abs() < 1.0e-8)
        }
        None => assert_true(false)
      }
    }
    None => assert_true(false)
  }
}

///|
test "glm: AIC and BIC" {
  // AIC and BIC should be computed and satisfy basic properties.
  let n = 5
  let k = 2
  let x = FixedArray::make(10, 0.0)
  for i = 0; i < n; i = i + 1 {
    x[i * 2] = 1.0
    x[i * 2 + 1] = i.to_double()
  }
  let y = FixedArray::make(5, 0.0)
  y[0] = 1.0
  y[1] = 3.0
  y[2] = 5.0
  y[3] = 7.0
  y[4] = 9.0
  match fit_glm(x, y, n, k, Gaussian, Identity) {
    Some(result) => {
      // Gaussian estimates σ², so the dispersion counts as one extra
      // parameter in AIC/BIC (as in R's glm).
      let p = k + 1
      // AIC = -2*ll + 2*p
      let expected_aic = -2.0 * result.log_likelihood + 2.0 * p.to_double()
      assert_true((result.aic - expected_aic).abs() < 1.0e-6)
      // BIC = -2*ll + p*ln(n)
      let expected_bic = -2.0 * result.log_likelihood +
        p.to_double() * @math.ln(n.to_double())
      assert_true((result.bic - expected_bic).abs() < 1.0e-6)
      // Exact fit here: residuals ≈ 0, so the Gaussian log-likelihood is
      // very large and the dispersion estimate near zero.
      assert_true(result.dispersion >= 0.0)
      assert_true(result.dispersion < 1.0e-6)
    }
    None => assert_true(false)
  }
}

///|
test "glm: canonical link" {
  assert_eq(canonical_link(Gaussian), Identity)
  assert_eq(canonical_link(Bernoulli), Logit)
  assert_eq(canonical_link(Poisson), Log)
  assert_eq(canonical_link(Gamma), Inverse)
}

///|
test "glm: logistic perfect separation handled" {
  // Perfect separation: y=0 for x<0, y=1 for x>0.
  // This should still converge (or at least not crash).
  let n = 4
  let k = 2
  let x = FixedArray::make(8, 0.0)
  x[0] = 1.0
  x[1] = -10.0
  x[2] = 1.0
  x[3] = -1.0
  x[4] = 1.0
  x[5] = 1.0
  x[6] = 1.0
  x[7] = 10.0
  let y = FixedArray::make(4, 0.0)
  y[0] = 0.0
  y[1] = 0.0
  y[2] = 1.0
  y[3] = 1.0
  // Should return Some result (possibly with large coefficients).
  match fit_glm(x, y, n, k, Bernoulli, Logit) {
    Some(result) =>
      // Coefficients should be very large (steep sigmoid).
      assert_true(result.coefficients[1] > 0.0)
    None => assert_true(false)
  }
}

///|
test "glm: Gamma regression" {
  // Gamma with log link: μ = exp(a + b*x)
  // x = [1, 2, 3, 4], y = [exp(1), exp(1.5), exp(2), exp(2.5)]
  let n = 4
  let k = 2
  let x = FixedArray::make(8, 0.0)
  x[0] = 1.0
  x[1] = 1.0
  x[2] = 1.0
  x[3] = 2.0
  x[4] = 1.0
  x[5] = 3.0
  x[6] = 1.0
  x[7] = 4.0
  let y = FixedArray::make(4, 0.0)
  y[0] = @math.exp(1.0)
  y[1] = @math.exp(1.5)
  y[2] = @math.exp(2.0)
  y[3] = @math.exp(2.5)
  match fit_glm(x, y, n, k, Gamma, Log) {
    Some(result) => {
      // Fitted values should be positive and close to y.
      for i = 0; i < n; i = i + 1 {
        assert_true(result.fitted_values[i] > 0.0)
      }
      // Slope should be positive.
      assert_true(result.coefficients[1] > 0.0)
    }
    None => assert_true(false)
  }
}

///|
test "glm: multivariate regression (3 predictors)" {
  // y = 1 + 2*x1 - 1*x2 + 0.5*x3, with non-collinear predictors.
  let n = 8
  let k = 4
  let x = FixedArray::make(32, 0.0)
  // Design matrix: [1, x1, x2, x3]
  let x1_vals = [1.0, 2.0, 3.0, 1.0, 5.0, 6.0, 2.0, 4.0]
  let x2_vals = [3.0, 1.0, 4.0, 5.0, 2.0, 3.0, 6.0, 2.0]
  let x3_vals = [2.0, 3.0, 1.0, 4.0, 5.0, 2.0, 3.0, 6.0]
  for i = 0; i < n; i = i + 1 {
    x[i * 4] = 1.0
    x[i * 4 + 1] = x1_vals[i]
    x[i * 4 + 2] = x2_vals[i]
    x[i * 4 + 3] = x3_vals[i]
  }
  let y = FixedArray::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    y[i] = 1.0 + 2.0 * x1_vals[i] - 1.0 * x2_vals[i] + 0.5 * x3_vals[i]
  }
  match fit_glm(x, y, n, k, Gaussian, Identity) {
    Some(result) => {
      assert_true(result.converged)
      assert_true((result.coefficients[0] - 1.0).abs() < 1.0e-6)
      assert_true((result.coefficients[1] - 2.0).abs() < 1.0e-6)
      assert_true((result.coefficients[2] - -1.0).abs() < 1.0e-6)
      assert_true((result.coefficients[3] - 0.5).abs() < 1.0e-6)
    }
    None => assert_true(false)
  }
}

///|
test "glm: deviance is non-negative" {
  let n = 5
  let k = 2
  let x = FixedArray::make(10, 0.0)
  for i = 0; i < n; i = i + 1 {
    x[i * 2] = 1.0
    x[i * 2 + 1] = i.to_double()
  }
  let y = FixedArray::make(5, 0.0)
  y[0] = 1.0
  y[1] = 3.0
  y[2] = 5.0
  y[3] = 7.0
  y[4] = 9.0
  match fit_glm(x, y, n, k, Gaussian, Identity) {
    Some(result) => {
      assert_true(result.deviance >= -1.0e-10)
      assert_true(result.null_deviance >= -1.0e-10)
    }
    None => assert_true(false)
  }
}

///|
test "glm: probit link basic" {
  // Probit regression: similar to logistic but uses normal CDF.
  let n = 5
  let k = 2
  let x = FixedArray::make(10, 0.0)
  x[0] = 1.0
  x[1] = -2.0
  x[2] = 1.0
  x[3] = -1.0
  x[4] = 1.0
  x[5] = 0.0
  x[6] = 1.0
  x[7] = 1.0
  x[8] = 1.0
  x[9] = 2.0
  let y = FixedArray::make(5, 0.0)
  y[0] = 0.0
  y[1] = 0.0
  y[2] = 1.0
  y[3] = 1.0
  y[4] = 1.0
  match fit_glm(x, y, n, k, Bernoulli, Probit) {
    Some(result) => {
      assert_true(result.converged)
      assert_true(result.coefficients[1] > 0.0)
      // Fitted values should be in [0, 1].
      for i = 0; i < n; i = i + 1 {
        assert_true(result.fitted_values[i] >= 0.0)
        assert_true(result.fitted_values[i] <= 1.0)
      }
    }
    None => assert_true(false)
  }
}

///|
test "glm: residuals sum to zero for Gaussian" {
  // For OLS (Gaussian + identity), residuals should sum to ~0.
  let n = 6
  let k = 2
  let x = FixedArray::make(12, 0.0)
  for i = 0; i < n; i = i + 1 {
    x[i * 2] = 1.0
    x[i * 2 + 1] = i.to_double()
  }
  let y = FixedArray::make(6, 0.0)
  y[0] = 1.0
  y[1] = 2.5
  y[2] = 4.1
  y[3] = 5.9
  y[4] = 7.2
  y[5] = 8.8
  match fit_glm(x, y, n, k, Gaussian, Identity) {
    Some(result) => {
      let mut resid_sum = 0.0
      for i = 0; i < n; i = i + 1 {
        resid_sum = resid_sum + (y[i] - result.fitted_values[i])
      }
      assert_true(resid_sum.abs() < 1.0e-8)
    }
    None => assert_true(false)
  }
}

///|
test "glm: invalid input returns None" {
  // Mismatched dimensions.
  let x = FixedArray::make(4, 1.0)
  let y = FixedArray::make(3, 1.0)
  match fit_glm(x, y, 3, 2, Gaussian, Identity) {
    Some(_) => assert_true(false)
    None => assert_true(true)
  }
}
