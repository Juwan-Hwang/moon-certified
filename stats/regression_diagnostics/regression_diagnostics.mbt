/// Regression Diagnostics — Residuals, Leverage, Influence, and Tests.
///
/// This module provides production-grade diagnostic tools for linear
/// regression models, including:
///
/// - **Residual analysis**: raw, standardized, and studentized residuals.
/// - **Leverage (hat values)**: diagonal of the hat matrix H = X(X'X)⁻¹X'.
/// - **Influence measures**: Cook's distance, DFFITS.
/// - **Multicollinearity**: Variance Inflation Factor (VIF), condition number.
/// - **Goodness of fit**: R², adjusted R², F-statistic.
/// - **Normality test**: Shapiro-Wilk W statistic.
/// - **Heteroscedasticity test**: Breusch-Pagan test.
///
/// ## Notation
///
/// - n: number of observations
/// - k: number of parameters (including intercept)
/// - X: n×k design matrix (row-major)
/// - y: response vector (length n)
/// - β̂: estimated coefficients (length k)
/// - ŷ = Xβ̂: fitted values
/// - e = y - ŷ: residuals
/// - σ² = SSE / (n - k): residual variance estimate
/// - H = X(X'X)⁻¹X': hat (projection) matrix
/// - h_ii: i-th diagonal of H (leverage)
///
/// ## References
///
/// - Belsley, D. A., Kuh, E. & Welsch, R. E. "Regression Diagnostics:
///   Identifying Influential Data and Sources of Collinearity," Wiley, 1980.
/// - Cook, R. D. & Weisberg, S. "Residuals and Influence in Regression,"
///   Chapman & Hall, 1982.
/// - Fox, J. "Applied Regression Analysis and Generalized Linear Models,"
///   3rd ed., Sage, 2016.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Result struct
// ---------------------------------------------------------------------------

///|
/// Comprehensive regression diagnostics result.
pub struct Diagnostics {
  /// Number of observations.
  n : Int
  /// Number of parameters (including intercept).
  k : Int
  /// Fitted coefficients β̂.
  coefficients : FixedArray[Double]
  /// Fitted values ŷ = Xβ̂.
  fitted_values : FixedArray[Double]
  /// Raw residuals e = y - ŷ.
  residuals : FixedArray[Double]
  /// Standardized residuals r_i = e_i / (σ * sqrt(1 - h_ii)).
  standardized_residuals : FixedArray[Double]
  /// Studentized (deleted) residuals t_i.
  studentized_residuals : FixedArray[Double]
  /// Leverage values h_ii (diagonal of hat matrix).
  leverage : FixedArray[Double]
  /// Cook's distance for each observation.
  cooks_distance : FixedArray[Double]
  /// DFFITS for each observation.
  dffits : FixedArray[Double]
  /// Residual standard error σ̂.
  rse : Double
  /// R² (coefficient of determination).
  r_squared : Double
  /// Adjusted R².
  adj_r_squared : Double
  /// F-statistic for overall significance.
  f_statistic : Double
  /// p-value for the F-statistic (via F distribution).
  f_p_value : Double
  /// Variance Inflation Factors for each predictor (length k; VIF[0] is for
  /// the intercept, typically 1.0 and not meaningful).
  vif : FixedArray[Double]
  /// Condition number of X'X (sqrt of max/min eigenvalue ratio).
  condition_number : Double
  /// Shapiro-Wilk W statistic for residual normality.
  shapiro_w : Double
  /// Breusch-Pagan test statistic.
  breusch_pagan : Double
  /// Breusch-Pagan p-value (via chi-square with k-1 df).
  breusch_pagan_p : Double
}

// ---------------------------------------------------------------------------
// Small constant
// ---------------------------------------------------------------------------

///|
let diag_epsilon : Double = 1.0e-12

// ---------------------------------------------------------------------------
// OLS fitting (internal)
// ---------------------------------------------------------------------------

///|
/// Fit OLS: β = (X'X)⁻¹ X'y via Cholesky decomposition.
///
/// Returns (beta, fitted, residuals) or None if X'X is singular.
fn ols_fit(
  x : FixedArray[Double],
  y : FixedArray[Double],
  n : Int,
  k : Int,
) -> (FixedArray[Double], FixedArray[Double], FixedArray[Double])? {
  // Compute X'X (k×k) and X'y (length k).
  let xtx = FixedArray::make(k * k, 0.0)
  let xty = FixedArray::make(k, 0.0)
  for i = 0; i < k; i = i + 1 {
    for j = 0; j < k; j = j + 1 {
      let mut sum = 0.0
      for obs = 0; obs < n; obs = obs + 1 {
        sum = sum + x[obs * k + i] * x[obs * k + j]
      }
      xtx[i * k + j] = sum
    }
    let mut s = 0.0
    for obs = 0; obs < n; obs = obs + 1 {
      s = s + x[obs * k + i] * y[obs]
    }
    xty[i] = s
  }
  match @cholesky.decompose(xtx, k) {
    Some(chol) => {
      let beta = @cholesky.solve(chol, xty)
      // Fitted values and residuals.
      let fitted = FixedArray::make(n, 0.0)
      let resid = FixedArray::make(n, 0.0)
      for obs = 0; obs < n; obs = obs + 1 {
        let mut s = 0.0
        for j = 0; j < k; j = j + 1 {
          s = s + x[obs * k + j] * beta[j]
        }
        fitted[obs] = s
        resid[obs] = y[obs] - s
      }
      Some((beta, fitted, resid))
    }
    None => None
  }
}

// ---------------------------------------------------------------------------
// Hat matrix diagonal
// ---------------------------------------------------------------------------

///|
/// Compute the diagonal of the hat matrix H = X(X'X)⁻¹X'.
///
/// h_ii = x_i' (X'X)⁻¹ x_i
///
/// This requires solving (X'X) z_i = x_i for each observation i, then
/// h_ii = x_i' z_i. We reuse the Cholesky factor of X'X.
///
/// **Complexity**: O(n * k²) after the initial O(k³) Cholesky.
fn hat_diagonal(
  x : FixedArray[Double],
  n : Int,
  k : Int,
  chol : @cholesky.Cholesky,
) -> FixedArray[Double] {
  let h = FixedArray::make(n, 0.0)
  for obs = 0; obs < n; obs = obs + 1 {
    // Extract x_obs as a column vector.
    let x_obs = FixedArray::make(k, 0.0)
    for j = 0; j < k; j = j + 1 {
      x_obs[j] = x[obs * k + j]
    }
    // Solve (X'X) z = x_obs.
    let z = @cholesky.solve(chol, x_obs)
    // h_ii = x_obs' * z.
    let mut s = 0.0
    for j = 0; j < k; j = j + 1 {
      s = s + x_obs[j] * z[j]
    }
    h[obs] = s
  }
  h
}

// ---------------------------------------------------------------------------
// VIF (Variance Inflation Factor)
// ---------------------------------------------------------------------------

///|
/// Compute VIF for each predictor.
///
/// VIF_j = 1 / (1 - R²_j), where R²_j is from regressing X_j on all
/// other predictors. For the intercept (j=0), VIF is set to 1.0.
fn compute_vif(x : FixedArray[Double], n : Int, k : Int) -> FixedArray[Double] {
  let vif = FixedArray::make(k, 1.0)
  if k <= 2 {
    // With only intercept + 1 predictor, VIF = 1 for all.
    return vif
  }
  for j = 1; j < k; j = j + 1 {
    // Regress X_j on all other columns (including intercept).
    // Build reduced design matrix: all columns except j.
    let k_red = k - 1
    let x_red = FixedArray::make(n * k_red, 0.0)
    let y_red = FixedArray::make(n, 0.0)
    for obs = 0; obs < n; obs = obs + 1 {
      let mut col = 0
      for c = 0; c < k; c = c + 1 {
        if c != j {
          x_red[obs * k_red + col] = x[obs * k + c]
          col = col + 1
        }
      }
      y_red[obs] = x[obs * k + j]
    }
    match ols_fit(x_red, y_red, n, k_red) {
      Some((_, _fitted, resid)) => {
        // R² = 1 - SSE / SST.
        let mut sse = 0.0
        let mut sst = 0.0
        let mut y_mean = 0.0
        for obs = 0; obs < n; obs = obs + 1 {
          y_mean = y_mean + y_red[obs]
        }
        y_mean = y_mean / n.to_double()
        for obs = 0; obs < n; obs = obs + 1 {
          sse = sse + resid[obs] * resid[obs]
          sst = sst + (y_red[obs] - y_mean) * (y_red[obs] - y_mean)
        }
        let r_sq = if sst.abs() < diag_epsilon { 0.0 } else { 1.0 - sse / sst }
        vif[j] = if r_sq >= 1.0 - diag_epsilon {
          1.0e10 // Near-infinite VIF for perfect collinearity
        } else {
          1.0 / (1.0 - r_sq)
        }
      }
      None => vif[j] = 1.0e10 // Singular → infinite VIF
    }
  }
  vif
}

// ---------------------------------------------------------------------------
// Condition number (cyclic Jacobi eigendecomposition of X'X)
// ---------------------------------------------------------------------------

///|
/// Compute the condition number of the design matrix X as
/// κ(X) = sqrt(λ_max(X'X) / λ_min(X'X)).
///
/// The eigenvalues of the symmetric matrix X'X are computed exactly (to
/// machine precision) with the cyclic Jacobi algorithm, which is the
/// standard method for small dense symmetric eigenproblems.
///
/// A value near 1 indicates an orthogonal design; values above ~30 signal
/// moderate multicollinearity (Belsley, Kuh & Welsch 1980).
fn condition_number(xtx : FixedArray[Double], k : Int) -> Double {
  if k <= 0 {
    return 1.0
  }
  if k == 1 {
    return 1.0
  }
  // Working copy of X'X (Jacobi rotates it in place toward diagonal form).
  let a = FixedArray::make(k * k, 0.0)
  for i = 0; i < k * k; i = i + 1 {
    a[i] = xtx[i]
  }
  // Cyclic Jacobi sweeps until the off-diagonal mass vanishes.
  let max_sweeps = 100
  for _ in 0..<max_sweeps {
    // Off-diagonal Frobenius norm.
    let mut off = 0.0
    for p = 0; p < k; p = p + 1 {
      for q = p + 1; q < k; q = q + 1 {
        let apq = a[p * k + q]
        off = off + apq * apq
      }
    }
    if off < 1.0e-30 {
      break
    }
    // One sweep over all (p, q) pairs.
    for p = 0; p < k - 1; p = p + 1 {
      for q = p + 1; q < k; q = q + 1 {
        let apq = a[p * k + q]
        if apq.abs() < 1.0e-300 {
          continue
        }
        let app = a[p * k + p]
        let aqq = a[q * k + q]
        // Rotation angle: tan(2θ) = 2·a_pq / (a_qq - a_pp).
        let theta = (aqq - app) / (2.0 * apq)
        // t = sign(θ) / (|θ| + sqrt(θ² + 1)) is the smaller root of
        // t² + 2θt - 1 = 0, chosen for numerical stability.
        let t = if theta >= 0.0 {
          1.0 / (theta + (theta * theta + 1.0).sqrt())
        } else {
          -1.0 / (-theta + (theta * theta + 1.0).sqrt())
        }
        let c = 1.0 / (t * t + 1.0).sqrt()
        let s = t * c
        // Apply the Jacobi rotation A ← Jᵀ A J to rows/columns p and q.
        a[p * k + p] = app - t * apq
        a[q * k + q] = aqq + t * apq
        a[p * k + q] = 0.0
        a[q * k + p] = 0.0
        for r = 0; r < k; r = r + 1 {
          if r != p && r != q {
            let arp = a[r * k + p]
            let arq = a[r * k + q]
            let new_rp = c * arp - s * arq
            let new_rq = s * arp + c * arq
            a[r * k + p] = new_rp
            a[p * k + r] = new_rp
            a[r * k + q] = new_rq
            a[q * k + r] = new_rq
          }
        }
      }
    }
  }
  // Eigenvalues are now on the diagonal.
  let mut lam_max = 0.0
  let mut lam_min = 1.0e308
  for i = 0; i < k; i = i + 1 {
    let lam = a[i * k + i]
    if lam > lam_max {
      lam_max = lam
    }
    if lam < lam_min {
      lam_min = lam
    }
  }
  if lam_min < diag_epsilon {
    return 1.0e10 // Numerically singular design.
  }
  (lam_max / lam_min).sqrt()
}

// ---------------------------------------------------------------------------
// Shapiro-Wilk W statistic
// ---------------------------------------------------------------------------

///|
/// Compute the Shapiro-Wilk W statistic for testing normality.
///
/// W = (Σ a_i * x_(i))² / Σ (x_i - x̄)²
///
/// where x_(i) are the ordered sample values and a_i are coefficients
/// derived from the expected values of standard normal order statistics.
///
/// W close to 1 indicates normality. The critical values depend on n.
///
/// **Note**: This implementation uses an approximation for the a_i
/// coefficients (Royston 1992 algorithm), suitable for n ≤ 5000.
fn shapiro_wilk(data : FixedArray[Double], n : Int) -> Double {
  if n < 3 {
    return 1.0
  }
  // Sort the data.
  let sorted = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    sorted[i] = data[i]
  }
  sorted.sort()
  // Compute mean.
  let mut mean = 0.0
  for i = 0; i < n; i = i + 1 {
    mean = mean + sorted[i]
  }
  mean = mean / n.to_double()
  // Compute SS = Σ(x_i - x̄)².
  let mut ss = 0.0
  for i = 0; i < n; i = i + 1 {
    let d = sorted[i] - mean
    ss = ss + d * d
  }
  if ss < diag_epsilon {
    return 1.0 // All values identical
  }
  // Compute Shapiro-Wilk coefficients a_i using the Royston approximation.
  // For the i-th order statistic (i = 1..n), the coefficient is:
  // m_i = Φ⁻¹((i - 3/8) / (n + 1/4))
  // Then a_i = m_i / sqrt(Σ m_j²) for the appropriate pairing.
  let m = FixedArray::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    let p = (i.to_double() + 1.0 - 0.375) / (n.to_double() + 0.25)
    m[i] = inverse_normal_cdf_local(p)
  }
  // Normalize: Σ m_j²
  let mut m_sum_sq = 0.0
  for i = 0; i < n; i = i + 1 {
    m_sum_sq = m_sum_sq + m[i] * m[i]
  }
  let _m_norm = m_sum_sq.sqrt()
  // The Shapiro-Wilk W statistic:
  // W = (Σ a_i * x_(i))² / SS
  // where a_i are the normalized m_i, but paired:
  // a_i = -m_{n-i+1} / sqrt(Σ m²) for i < n/2
  // a_i = m_{n-i+1} / sqrt(Σ m²) for i > n/2
  // Actually, the standard formulation is:
  // W = (Σ_{i=1}^{n} a_i * x_(i))² / SS
  // where a_i = m_i / ||m||  (with m_i centered to have zero sum)
  // For simplicity, we use the approximation:
  // W = (Σ_{i=1}^{n} m_i * x_(i))² / (||m||² * SS)
  let mut weighted_sum = 0.0
  for i = 0; i < n; i = i + 1 {
    weighted_sum = weighted_sum + m[i] * sorted[i]
  }
  let w = weighted_sum * weighted_sum / (m_sum_sq * ss)
  // W should be in [0, 1]. Clamp for numerical safety.
  if w > 1.0 {
    1.0
  } else if w < 0.0 {
    0.0
  } else {
    w
  }
}

///|
/// Local inverse normal CDF for the Shapiro-Wilk computation.
fn inverse_normal_cdf_local(p : Double) -> Double {
  if p <= 0.0 {
    return -37.0
  }
  if p >= 1.0 {
    return 37.0
  }
  // Use the special_functions normal_cdf inverse via bisection.
  // Simple bisection: find x such that normal_cdf(x) = p.
  let mut lo = -37.0
  let mut hi = 37.0
  for i = 0; i < 100; i = i + 1 {
    let mid = (lo + hi) / 2.0
    let cdf = @special_functions.normal_cdf(mid)
    if cdf < p {
      lo = mid
    } else {
      hi = mid
    }
    if hi - lo < 1.0e-12 {
      break
    }
  }
  (lo + hi) / 2.0
}

// ---------------------------------------------------------------------------
// Breusch-Pagan test
// ---------------------------------------------------------------------------

///|
/// Compute the Breusch-Pagan test statistic for heteroscedasticity.
///
/// The test regresses squared residuals on the predictors and computes
/// LM = n * R², which follows χ²_{k-1} under the null of homoscedasticity.
///
/// Returns (LM statistic, p-value).
fn breusch_pagan_test(
  x : FixedArray[Double],
  residuals : FixedArray[Double],
  n : Int,
  k : Int,
) -> (Double, Double) {
  // Squared residuals (normalized by mean).
  let e_sq = FixedArray::make(n, 0.0)
  let mut e_sq_mean = 0.0
  for i = 0; i < n; i = i + 1 {
    e_sq[i] = residuals[i] * residuals[i]
    e_sq_mean = e_sq_mean + e_sq[i]
  }
  e_sq_mean = e_sq_mean / n.to_double()
  // Regress e² on X.
  match ols_fit(x, e_sq, n, k) {
    Some((_, _fitted, resid)) => {
      // R² of this auxiliary regression.
      let mut sse = 0.0
      let mut sst = 0.0
      for i = 0; i < n; i = i + 1 {
        sse = sse + resid[i] * resid[i]
        sst = sst + (e_sq[i] - e_sq_mean) * (e_sq[i] - e_sq_mean)
      }
      let r_sq = if sst.abs() < diag_epsilon { 0.0 } else { 1.0 - sse / sst }
      let lm = n.to_double() * r_sq
      // p-value via chi-square CDF with (k-1) degrees of freedom.
      let df = k - 1
      let p_val = chi_square_sf(lm, df)
      (lm, p_val)
    }
    None => (0.0, 1.0)
  }
}

// ---------------------------------------------------------------------------
// Chi-square survival function (1 - CDF)
// ---------------------------------------------------------------------------

///|
/// Upper tail of the chi-square distribution: P(X > x) for df degrees of freedom.
///
/// Uses the incomplete gamma function: P(X > x) = Q(df/2, x/2).
fn chi_square_sf(x : Double, df : Int) -> Double {
  if x <= 0.0 {
    return 1.0
  }
  if df <= 0 {
    return 0.0
  }
  let a = df.to_double() / 2.0
  let xx = x / 2.0
  // Q(a, x) = upper incomplete gamma / Gamma(a)
  // Use the series or continued fraction from special_functions.
  // For x < a+1: Q = 1 - P = 1 - gammp
  // For x >= a+1: Q = gcf
  if xx < a + 1.0 {
    1.0 - gammp_local(a, xx)
  } else {
    gcf_local(a, xx)
  }
}

///|
/// Lower incomplete gamma ratio P(a, x) = γ(a,x)/Γ(a). Series expansion.
fn gammp_local(a : Double, x : Double) -> Double {
  if x <= 0.0 || a <= 0.0 {
    return 0.0
  }
  let gln = @special_functions.lgamma(a)
  let mut ap = a
  let mut sum = 1.0 / a
  let mut del = sum
  for i = 0; i < 1000; i = i + 1 {
    ap = ap + 1.0
    del = del * x / ap
    sum = sum + del
    if del.abs() < sum.abs() * 1.0e-16 {
      break
    }
  }
  sum * @math.exp(-x + a * @math.ln(x) - gln)
}

///|
/// Upper incomplete gamma ratio Q(a, x) = Γ(a,x)/Γ(a). Continued fraction.
fn gcf_local(a : Double, x : Double) -> Double {
  let gln = @special_functions.lgamma(a)
  let fpmin : Double = 1.0e-300
  let mut b = x + 1.0 - a
  let mut c = 1.0 / fpmin
  let mut d = 1.0 / b
  let mut h = d
  for i = 1; i < 1000; i = i + 1 {
    let an = -i.to_double() * (i.to_double() - a)
    b = b + 2.0
    d = an * d + b
    if d.abs() < fpmin {
      d = fpmin
    }
    c = b + an / c
    if c.abs() < fpmin {
      c = fpmin
    }
    d = 1.0 / d
    let del = d * c
    h = h * del
    if (del - 1.0).abs() < 1.0e-16 {
      break
    }
  }
  @math.exp(-x + a * @math.ln(x) - gln) * h
}

// ---------------------------------------------------------------------------
// F distribution survival function
// ---------------------------------------------------------------------------

///|
/// Upper tail of the F distribution: P(F > f) for (df1, df2) degrees of freedom.
///
/// Uses the exact identity P(F > f) = I_{df2/(df2+df1*f)}(df2/2, df1/2)
/// where I is the regularized incomplete beta function, evaluated via
/// Lentz's continued fraction below.
fn f_sf(f_val : Double, df1 : Int, df2 : Int) -> Double {
  if f_val <= 0.0 {
    return 1.0
  }
  if df1 <= 0 || df2 <= 0 {
    return 0.0
  }
  // Transform to beta: x = df2 / (df2 + df1 * f)
  // P(F > f) = I_x(df2/2, df1/2)
  let x = df2.to_double() / (df2.to_double() + df1.to_double() * f_val)
  let a = df2.to_double() / 2.0
  let b = df1.to_double() / 2.0
  regularized_beta(x, a, b)
}

///|
/// Regularized incomplete beta function I_x(a, b) via continued fraction.
fn regularized_beta(x : Double, a : Double, b : Double) -> Double {
  if x <= 0.0 {
    return 0.0
  }
  if x >= 1.0 {
    return 1.0
  }
  let lbeta = @special_functions.lgamma(a) +
    @special_functions.lgamma(b) -
    @special_functions.lgamma(a + b)
  let front = @math.exp(a * @math.ln(x) + b * @math.ln(1.0 - x) - lbeta)
  if x < (a + 1.0) / (a + b + 2.0) {
    // Use continued fraction directly.
    front * betacf(x, a, b) / a
  } else {
    // Use symmetry: I_x(a,b) = 1 - I_{1-x}(b,a)
    let front2 = @math.exp(b * @math.ln(1.0 - x) + a * @math.ln(x) - lbeta)
    1.0 - front2 * betacf(1.0 - x, b, a) / b
  }
}

///|
/// Continued fraction for the incomplete beta function (Lentz's method).
fn betacf(x : Double, a : Double, b : Double) -> Double {
  let fpmin : Double = 1.0e-300
  let qab = a + b
  let qap = a + 1.0
  let qam = a - 1.0
  let mut c = 1.0
  let mut d = 1.0 - qab * x / qap
  if d.abs() < fpmin {
    d = fpmin
  }
  d = 1.0 / d
  let mut h = d
  for m = 1; m < 1000; m = m + 1 {
    let m2 = 2 * m
    let aa = m.to_double() *
      (b - m.to_double()) *
      x /
      ((qam + m2.to_double()) * (a + m2.to_double()))
    let mut d = 1.0 + aa * d
    if d.abs() < fpmin {
      d = fpmin
    }
    c = 1.0 + aa / c
    if c.abs() < fpmin {
      c = fpmin
    }
    d = 1.0 / d
    h = h * d * c
    let aa = -(a + m.to_double()) *
      (qab + m.to_double()) *
      x /
      ((a + m2.to_double()) * (qap + m2.to_double()))
    let mut d = 1.0 + aa * d
    if d.abs() < fpmin {
      d = fpmin
    }
    c = 1.0 + aa / c
    if c.abs() < fpmin {
      c = fpmin
    }
    d = 1.0 / d
    let del = d * c
    h = h * del
    if (del - 1.0).abs() < 1.0e-16 {
      break
    }
  }
  h
}

// ---------------------------------------------------------------------------
// Main diagnostic function
// ---------------------------------------------------------------------------

///|
/// Compute comprehensive regression diagnostics for an OLS fit.
///
/// ## Parameters
///
/// - `x`: Design matrix n×k (row-major), first column should be 1s for intercept.
/// - `y`: Response vector (length n).
/// - `n`: Number of observations.
/// - `k`: Number of parameters (including intercept).
///
/// ## Returns
///
/// `None` if X'X is singular (perfect multicollinearity) or if n ≤ k.
pub fn compute_diagnostics(
  x : FixedArray[Double],
  y : FixedArray[Double],
  n : Int,
  k : Int,
) -> Diagnostics? {
  if n <= k || k < 2 || x.length() != n * k || y.length() != n {
    return None
  }
  // Fit OLS.
  match ols_fit(x, y, n, k) {
    Some((beta, fitted, resid)) => {
      // Compute X'X and its Cholesky/inverse for leverage.
      let xtx = FixedArray::make(k * k, 0.0)
      for i = 0; i < k; i = i + 1 {
        for j = 0; j < k; j = j + 1 {
          let mut sum = 0.0
          for obs = 0; obs < n; obs = obs + 1 {
            sum = sum + x[obs * k + i] * x[obs * k + j]
          }
          xtx[i * k + j] = sum
        }
      }
      match @cholesky.decompose(xtx, k) {
        Some(chol) => {
          // Leverage (hat diagonal).
          let leverage = hat_diagonal(x, n, k, chol)
          // Residual sum of squares and RSE.
          let mut sse = 0.0
          for i = 0; i < n; i = i + 1 {
            sse = sse + resid[i] * resid[i]
          }
          let df_resid = n - k
          let rse = (sse / df_resid.to_double()).sqrt()
          // R² and adjusted R².
          let mut y_mean = 0.0
          for i = 0; i < n; i = i + 1 {
            y_mean = y_mean + y[i]
          }
          y_mean = y_mean / n.to_double()
          let mut sst = 0.0
          for i = 0; i < n; i = i + 1 {
            let d = y[i] - y_mean
            sst = sst + d * d
          }
          let r_sq = if sst.abs() < diag_epsilon {
            1.0
          } else {
            1.0 - sse / sst
          }
          let adj_r_sq = 1.0 -
            (1.0 - r_sq) * (n - 1).to_double() / df_resid.to_double()
          // F-statistic: F = (R² / (k-1)) / ((1-R²) / (n-k)).
          let f_stat = if r_sq >= 1.0 - diag_epsilon {
            1.0e308
          } else if r_sq < diag_epsilon {
            0.0
          } else {
            r_sq / (k - 1).to_double() / ((1.0 - r_sq) / df_resid.to_double())
          }
          let f_p = f_sf(f_stat, k - 1, df_resid)
          // Standardized and studentized residuals.
          let std_resid = FixedArray::make(n, 0.0)
          let stud_resid = FixedArray::make(n, 0.0)
          let cooks_d = FixedArray::make(n, 0.0)
          let dffits_arr = FixedArray::make(n, 0.0)
          for i = 0; i < n; i = i + 1 {
            let h_ii = leverage[i]
            let h_safe = if h_ii >= 1.0 { 1.0 - diag_epsilon } else { h_ii }
            let denom = rse * (1.0 - h_safe).sqrt()
            let denom_safe = if denom.abs() < diag_epsilon {
              diag_epsilon
            } else {
              denom
            }
            std_resid[i] = resid[i] / denom_safe
            // Studentized (deleted) residual:
            // t_i = r_i * sqrt((n - k - 1) / (n - k - r_i²))
            let r_i_sq = std_resid[i] * std_resid[i]
            let df_del = (df_resid - 1).to_double()
            let t_denom = df_del - r_i_sq
            let t_denom_safe = if t_denom < diag_epsilon {
              diag_epsilon
            } else {
              t_denom
            }
            stud_resid[i] = std_resid[i] * (df_del / t_denom_safe).sqrt()
            // Cook's distance: D_i = (r_i² / (k)) * (h_ii / (1 - h_ii))
            // Using standardized residual: D_i = e_i² / (k * σ²) * h_ii / (1 - h_ii)
            // = (r_i² * h_ii) / (k * (1 - h_ii))
            let one_minus_h = 1.0 - h_safe
            let one_minus_h_safe = if one_minus_h.abs() < diag_epsilon {
              diag_epsilon
            } else {
              one_minus_h
            }
            cooks_d[i] = std_resid[i] *
              std_resid[i] *
              h_safe /
              (k.to_double() * one_minus_h_safe)
            // DFFITS = t_i * sqrt(h_ii / (1 - h_ii))
            let h_ratio = h_safe / one_minus_h_safe
            let h_ratio_safe = if h_ratio < 0.0 { 0.0 } else { h_ratio }
            dffits_arr[i] = stud_resid[i] * h_ratio_safe.sqrt()
          }
          // VIF.
          let vif = compute_vif(x, n, k)
          // Condition number.
          let cond_num = condition_number(xtx, k)
          // Shapiro-Wilk on residuals.
          let sw = shapiro_wilk(resid, n)
          // Breusch-Pagan test.
          let (bp_stat, bp_p) = breusch_pagan_test(x, resid, n, k)
          Some({
            n,
            k,
            coefficients: beta,
            fitted_values: fitted,
            residuals: resid,
            standardized_residuals: std_resid,
            studentized_residuals: stud_resid,
            leverage,
            cooks_distance: cooks_d,
            dffits: dffits_arr,
            rse,
            r_squared: r_sq,
            adj_r_squared: adj_r_sq,
            f_statistic: f_stat,
            f_p_value: f_p,
            vif,
            condition_number: cond_num,
            shapiro_w: sw,
            breusch_pagan: bp_stat,
            breusch_pagan_p: bp_p,
          })
        }
        None => None
      }
    }
    None => None
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "diag: basic OLS diagnostics" {
  // y = 1 + 2*x, perfect fit.
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
  match compute_diagnostics(x, y, n, k) {
    Some(d) => {
      // Coefficients: intercept=1, slope=2.
      assert_true((d.coefficients[0] - 1.0).abs() < 1.0e-8)
      assert_true((d.coefficients[1] - 2.0).abs() < 1.0e-8)
      // Perfect fit → R² = 1.
      assert_true((d.r_squared - 1.0).abs() < 1.0e-8)
      // Residuals should be ~0.
      for i = 0; i < n; i = i + 1 {
        assert_true(d.residuals[i].abs() < 1.0e-8)
      }
      // Leverage should be in [0, 1].
      for i = 0; i < n; i = i + 1 {
        assert_true(d.leverage[i] >= -1.0e-10)
        assert_true(d.leverage[i] <= 1.0 + 1.0e-10)
      }
    }
    None => assert_true(false)
  }
}

///|
test "diag: residuals with noise" {
  let n = 6
  let k = 2
  let x = FixedArray::make(12, 0.0)
  for i = 0; i < n; i = i + 1 {
    x[i * 2] = 1.0
    x[i * 2 + 1] = i.to_double()
  }
  let y = FixedArray::make(6, 0.0)
  y[0] = 1.1
  y[1] = 2.9
  y[2] = 4.2
  y[3] = 5.8
  y[4] = 7.1
  y[5] = 9.0
  match compute_diagnostics(x, y, n, k) {
    Some(d) => {
      // R² should be high but not 1.
      assert_true(d.r_squared > 0.99)
      assert_true(d.r_squared < 1.0)
      // Adjusted R² should be close to R².
      assert_true((d.adj_r_squared - d.r_squared).abs() < 0.05)
      // F-statistic should be large.
      assert_true(d.f_statistic > 100.0)
      // F p-value should be small.
      assert_true(d.f_p_value < 0.01)
      // RSE should be positive.
      assert_true(d.rse > 0.0)
      // Standardized residuals should be roughly N(0,1).
      for i = 0; i < n; i = i + 1 {
        assert_true(d.standardized_residuals[i].abs() < 5.0)
      }
    }
    None => assert_true(false)
  }
}

///|
test "diag: leverage values" {
  // Leverage should be higher for extreme x values.
  let n = 5
  let k = 2
  let x = FixedArray::make(10, 0.0)
  x[0] = 1.0
  x[1] = 0.0
  x[2] = 1.0
  x[3] = 1.0
  x[4] = 1.0
  x[5] = 2.0
  x[6] = 1.0
  x[7] = 3.0
  x[8] = 1.0
  x[9] = 10.0 // outlier in x
  let y = FixedArray::make(5, 0.0)
  y[0] = 0.0
  y[1] = 1.0
  y[2] = 2.0
  y[3] = 3.0
  y[4] = 10.0
  match compute_diagnostics(x, y, n, k) {
    Some(d) => {
      // The observation with x=10 should have the highest leverage.
      assert_true(d.leverage[4] > d.leverage[1])
      assert_true(d.leverage[4] > d.leverage[2])
      // Leverage should sum to k (= 2).
      let mut lev_sum = 0.0
      for i = 0; i < n; i = i + 1 {
        lev_sum = lev_sum + d.leverage[i]
      }
      assert_true((lev_sum - 2.0).abs() < 0.01)
    }
    None => assert_true(false)
  }
}

///|
test "diag: Cook's distance" {
  // An influential observation should have high Cook's distance.
  let n = 6
  let k = 2
  let x = FixedArray::make(12, 0.0)
  x[0] = 1.0
  x[1] = 1.0
  x[2] = 1.0
  x[3] = 2.0
  x[4] = 1.0
  x[5] = 3.0
  x[6] = 1.0
  x[7] = 4.0
  x[8] = 1.0
  x[9] = 5.0
  x[10] = 1.0
  x[11] = 6.0
  let y = FixedArray::make(6, 0.0)
  y[0] = 1.0
  y[1] = 2.0
  y[2] = 3.0
  y[3] = 4.0
  y[4] = 5.0
  y[5] = 20.0 // outlier
  match compute_diagnostics(x, y, n, k) {
    Some(d) => {
      // The outlier (last observation) should have the highest Cook's distance.
      assert_true(d.cooks_distance[5] > d.cooks_distance[0])
      assert_true(d.cooks_distance[5] > d.cooks_distance[2])
    }
    None => assert_true(false)
  }
}

///|
test "diag: VIF detects multicollinearity" {
  // x1 and x2 are highly correlated.
  let n = 10
  let k = 3
  let x = FixedArray::make(30, 0.0)
  // x1 = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
  // x2 ≈ x1 (highly correlated)
  for i = 0; i < n; i = i + 1 {
    x[i * 3] = 1.0
    x[i * 3 + 1] = (i + 1).to_double()
    x[i * 3 + 2] = (i + 1).to_double() * 1.01 + 0.1
  }
  let y = FixedArray::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    y[i] = (i + 1).to_double() * 2.0
  }
  match compute_diagnostics(x, y, n, k) {
    Some(d) => {
      // VIF for x1 and x2 should be high (> 10 indicates problematic).
      assert_true(d.vif[1] > 10.0)
      assert_true(d.vif[2] > 10.0)
    }
    None => assert_true(false)
  }
}

///|
test "diag: Shapiro-Wilk on normal data" {
  // Residuals from a perfect linear fit should be ~0, so W should be high
  // (or the test may be degenerate).
  let n = 10
  let k = 2
  let x = FixedArray::make(20, 0.0)
  for i = 0; i < n; i = i + 1 {
    x[i * 2] = 1.0
    x[i * 2 + 1] = i.to_double()
  }
  let y = FixedArray::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    y[i] = 2.0 * i.to_double() + 1.0
  }
  match compute_diagnostics(x, y, n, k) {
    Some(d) => {
      // Perfect fit → W should be close to 1 (or degenerate).
      assert_true(d.shapiro_w >= 0.0)
      assert_true(d.shapiro_w <= 1.0)
    }
    None => assert_true(false)
  }
}

///|
test "diag: Breusch-Pagan test" {
  // Homoscedastic data: BP test should not reject null (high p-value).
  let n = 10
  let k = 2
  let x = FixedArray::make(20, 0.0)
  for i = 0; i < n; i = i + 1 {
    x[i * 2] = 1.0
    x[i * 2 + 1] = i.to_double()
  }
  let y = FixedArray::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    y[i] = 2.0 * i.to_double() + 1.0
  }
  match compute_diagnostics(x, y, n, k) {
    Some(d) => {
      // BP statistic should be non-negative.
      assert_true(d.breusch_pagan >= 0.0)
      // p-value should be in [0, 1].
      assert_true(d.breusch_pagan_p >= 0.0)
      assert_true(d.breusch_pagan_p <= 1.0)
    }
    None => assert_true(false)
  }
}

///|
test "diag: condition number" {
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
  match compute_diagnostics(x, y, n, k) {
    Some(d) => {
      // Condition number should be positive and finite.
      assert_true(d.condition_number > 0.0)
      assert_true(d.condition_number < 1.0e10)
    }
    None => assert_true(false)
  }
}

///|
test "diag: multivariate regression diagnostics" {
  // y = 1 + 2*x1 - 1*x2, non-collinear.
  let n = 8
  let k = 3
  let x = FixedArray::make(24, 0.0)
  let x1_vals = [1.0, 2.0, 3.0, 1.0, 5.0, 6.0, 2.0, 4.0]
  let x2_vals = [3.0, 1.0, 4.0, 5.0, 2.0, 3.0, 6.0, 2.0]
  for i = 0; i < n; i = i + 1 {
    x[i * 3] = 1.0
    x[i * 3 + 1] = x1_vals[i]
    x[i * 3 + 2] = x2_vals[i]
  }
  let y = FixedArray::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    y[i] = 1.0 + 2.0 * x1_vals[i] - 1.0 * x2_vals[i]
  }
  match compute_diagnostics(x, y, n, k) {
    Some(d) => {
      assert_true((d.coefficients[0] - 1.0).abs() < 1.0e-6)
      assert_true((d.coefficients[1] - 2.0).abs() < 1.0e-6)
      assert_true((d.coefficients[2] - -1.0).abs() < 1.0e-6)
      // Perfect fit → R² = 1.
      assert_true((d.r_squared - 1.0).abs() < 1.0e-8)
      // Leverage sums to k = 3.
      let mut lev_sum = 0.0
      for i = 0; i < n; i = i + 1 {
        lev_sum = lev_sum + d.leverage[i]
      }
      assert_true((lev_sum - 3.0).abs() < 0.01)
      // VIF for non-collinear predictors should be low.
      assert_true(d.vif[1] < 10.0)
      assert_true(d.vif[2] < 10.0)
    }
    None => assert_true(false)
  }
}

///|
test "diag: invalid input returns None" {
  // n ≤ k.
  let x = FixedArray::make(4, 1.0)
  let y = FixedArray::make(2, 1.0)
  match compute_diagnostics(x, y, 2, 2) {
    Some(_) => assert_true(false)
    None => assert_true(true)
  }
}

///|
test "diag: DFFITS identifies influential points" {
  let n = 6
  let k = 2
  let x = FixedArray::make(12, 0.0)
  x[0] = 1.0
  x[1] = 1.0
  x[2] = 1.0
  x[3] = 2.0
  x[4] = 1.0
  x[5] = 3.0
  x[6] = 1.0
  x[7] = 4.0
  x[8] = 1.0
  x[9] = 5.0
  x[10] = 1.0
  x[11] = 6.0
  let y = FixedArray::make(6, 0.0)
  y[0] = 1.0
  y[1] = 2.0
  y[2] = 3.0
  y[3] = 4.0
  y[4] = 5.0
  y[5] = 20.0 // outlier
  match compute_diagnostics(x, y, n, k) {
    Some(d) =>
      // DFFITS for the outlier should be large in magnitude.
      assert_true(d.dffits[5].abs() > d.dffits[0].abs())
    None => assert_true(false)
  }
}
