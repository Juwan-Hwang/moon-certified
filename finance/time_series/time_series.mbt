/// Time Series Analysis — ARIMA, GARCH, ADF, Cointegration.
///
/// This module implements core time-series econometrics tools used in
/// quantitative finance for modelling returns, forecasting volatility,
/// and testing for stationarity and long-run equilibrium relationships.
///
/// ## ARIMA(p,d,q)
///
/// An ARIMA model combines autoregressive (AR), differencing (I), and
/// moving-average (MA) components:
///
/// - **AR(p)**: `y_t = c + φ₁·y_{t-1} + … + φ_p·y_{t-p} + ε_t`
/// - **I(d)**: Apply d-th order differencing to achieve stationarity.
/// - **MA(q)**: `y_t = ε_t + θ₁·ε_{t-1} + … + θ_q·ε_{t-q}`
///
/// AR and MA coefficients are estimated via the **Hannan-Rissanen
/// two-step method**: (1) fit a long AR model to obtain estimated
/// residuals ε̂_t, then (2) run OLS of y_t on
/// [1, y_{t-1},…,y_{t-p}, ε̂_{t-1},…,ε̂_{t-q}] to get consistent
/// estimates of both AR (φ) and MA (θ) parameters. Forecasting
/// inverts the differencing to recover predictions in the original
/// scale, and uses both AR and MA terms in the forecast recurrence.
///
/// ## GARCH(1,1)
///
/// The Generalized Autoregressive Conditional Heteroskedasticity model
/// captures volatility clustering in financial returns:
///
/// `σ²_t = ω + α·ε²_{t-1} + β·σ²_{t-1}`
///
/// Parameters are estimated by maximizing the Gaussian log-likelihood
/// using coordinate descent, with the constraint `α + β < 1`.
///
/// ## Augmented Dickey-Fuller (ADF) Test
///
/// Tests the null hypothesis that a unit root is present in a time
/// series (i.e., the series is non-stationary):
///
/// `Δy_t = α + γ·y_{t-1} + Σ δ_i·Δy_{t-i} + ε_t`
///
/// H₀: γ = 0 (unit root) vs H₁: γ < 0 (stationary).
/// The test statistic is the t-ratio on γ̂. Critical values follow
/// the Dickey-Fuller distribution (non-standard). With a constant
/// and no trend, the asymptotic 5% critical value is approximately
/// −2.86.
///
/// ## Engle-Granger Cointegration Test
///
/// Two-step procedure:
/// 1. Regress y on x to obtain OLS residuals `u_t`.
/// 2. Apply ADF test (without constant) to the residuals.
///
/// If the residuals are stationary, the series are cointegrated.
/// The 5% critical value for two variables is approximately −3.34.
///
/// ## References
///
/// - G. E. P. Box, G. M. Jenkins. "Time Series Analysis: Forecasting
///   and Control." Holden-Day, 1970.
/// - T. Bollerslev. "Generalized Autoregressive Conditional
///   Heteroskedasticity." Journal of Econometrics, 1986.
/// - D. A. Dickey, W. A. Fuller. "Distribution of the Estimators for
///   Autoregressive Time Series with a Unit Root." JASA, 1979.
/// - R. F. Engle, C. W. J. Granger. "Co-Integration and Error
///   Correction: Representation, Estimation, and Testing."
///   Econometrica, 1987.
/// - J. D. Hamilton. "Time Series Analysis." Princeton, 1994.
///
/// `proof-enabled` is `false`; correctness is backed by test vectors.

// ---------------------------------------------------------------------------
// Internal Helpers
// ---------------------------------------------------------------------------

///|
/// Arithmetic mean of a Double array.
fn mean(data : Array[Double]) -> Double {
  let n = data.length()
  if n == 0 {
    return 0.0
  }
  let mut s = 0.0
  for i = 0; i < n; i = i + 1 {
    s = s + data[i]
  }
  s / n.to_double()
}

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
/// Invert an `n × n` matrix via Gauss-Jordan elimination with partial
/// pivoting. Returns an all-zeros matrix if singular.
fn mat_inverse(a : Array[Double], n : Int) -> Array[Double] {
  let width = 2 * n
  let aug : Array[Double] = Array::make(n * width, 0.0)
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      aug[i * width + j] = a[i * n + j]
    }
    aug[i * width + n + i] = 1.0
  }
  for col = 0; col < n; col = col + 1 {
    // Partial pivoting.
    let mut max_row = col
    let mut max_val = aug[col * width + col].abs()
    for row = col + 1; row < n; row = row + 1 {
      let val = aug[row * width + col].abs()
      if val > max_val {
        max_val = val
        max_row = row
      }
    }
    if max_row != col {
      for j = 0; j < width; j = j + 1 {
        let tmp = aug[col * width + j]
        aug[col * width + j] = aug[max_row * width + j]
        aug[max_row * width + j] = tmp
      }
    }
    let pivot = aug[col * width + col]
    if pivot.abs() < 1.0e-15 {
      return Array::make(n * n, 0.0)
    }
    for j = 0; j < width; j = j + 1 {
      aug[col * width + j] = aug[col * width + j] / pivot
    }
    for row = 0; row < n; row = row + 1 {
      if row != col {
        let factor = aug[row * width + col]
        if factor != 0.0 {
          for j = col; j < width; j = j + 1 {
            aug[row * width + j] = aug[row * width + j] -
              factor * aug[col * width + j]
          }
        }
      }
    }
  }
  let inv : Array[Double] = Array::make(n * n, 0.0)
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      inv[i * n + j] = aug[i * width + n + j]
    }
  }
  inv
}

// ---------------------------------------------------------------------------
// Ordinary Least Squares
// ---------------------------------------------------------------------------

///|
/// OLS regression result (internal).
priv struct OLSResult {
  coefficients : Array[Double] // length k
  t_statistics : Array[Double] // length k
  r_squared : Double
}

///|
/// Fit an OLS regression `y = X·β + ε` via the normal equations
/// `β = (X'X)⁻¹·X'y`.
///
/// - `x`: Design matrix, flat row-major `n × k`.
/// - `y`: Response vector of length `n`.
/// - `n`: Number of observations.
/// - `k`: Number of regressors (including constant if present).
///
/// Returns coefficients, t-statistics, and R².
fn ols(x : Array[Double], y : Array[Double], n : Int, k : Int) -> OLSResult {
  // X'X  (k × k)
  let xtx : Array[Double] = Array::make(k * k, 0.0)
  for i = 0; i < k; i = i + 1 {
    for j = 0; j < k; j = j + 1 {
      let mut s = 0.0
      for t = 0; t < n; t = t + 1 {
        s = s + x[t * k + i] * x[t * k + j]
      }
      xtx[i * k + j] = s
    }
  }
  // X'y  (k-vector)
  let xty : Array[Double] = Array::make(k, 0.0)
  for i = 0; i < k; i = i + 1 {
    let mut s = 0.0
    for t = 0; t < n; t = t + 1 {
      s = s + x[t * k + i] * y[t]
    }
    xty[i] = s
  }
  // β = (X'X)⁻¹ X'y
  let xtx_inv = mat_inverse(xtx, k)
  let beta = mat_vec_mul(xtx_inv, k, k, xty)
  // Residuals and RSS.
  let mut rss = 0.0
  for t = 0; t < n; t = t + 1 {
    let mut pred = 0.0
    for j = 0; j < k; j = j + 1 {
      pred = pred + x[t * k + j] * beta[j]
    }
    let e = y[t] - pred
    rss = rss + e * e
  }
  // Total sum of squares (for R²).
  let y_mean = mean(y)
  let mut tss = 0.0
  for t = 0; t < n; t = t + 1 {
    let d = y[t] - y_mean
    tss = tss + d * d
  }
  let r_sq = if tss > 0.0 { 1.0 - rss / tss } else { 0.0 }
  // Standard errors and t-statistics.
  // σ² = RSS / (n − k)
  let dof = n - k
  let sigma2 = if dof > 0 { rss / dof.to_double() } else { 0.0 }
  // Var(β) = σ² · (X'X)⁻¹
  // SE(β_j) = sqrt(Var(β)[j][j])
  let t_stats : Array[Double] = Array::make(k, 0.0)
  for j = 0; j < k; j = j + 1 {
    let v = sigma2 * xtx_inv[j * k + j]
    let se = if v > 0.0 { v.sqrt() } else { 0.0 }
    t_stats[j] = if se > 0.0 { beta[j] / se } else { 0.0 }
  }
  { coefficients: beta, t_statistics: t_stats, r_squared: r_sq, }
}

// ---------------------------------------------------------------------------
// Differencing
// ---------------------------------------------------------------------------

///|
/// Apply d-th order differencing to a time series.
///
/// - `data`: Original time series.
/// - `order`: Order of differencing `d` (0 returns a copy).
///
/// Returns the differenced series of length `n − d`.
pub fn difference(data : Array[Double], order : Int) -> Array[Double] {
  if order <= 0 {
    return Array::copy(data)
  }
  let mut result = Array::copy(data)
  for d = 0; d < order; d = d + 1 {
    let m = result.length()
    if m < 2 {
      return []
    }
    let diff : Array[Double] = Array::make(m - 1, 0.0)
    for i = 1; i < m; i = i + 1 {
      diff[i - 1] = result[i] - result[i - 1]
    }
    result = diff
  }
  result
}

// ---------------------------------------------------------------------------
// AR(p) Model
// ---------------------------------------------------------------------------

///|
/// Fitted AR(p) model.
///
/// `y_t = intercept + φ₁·y_{t-1} + … + φ_p·y_{t-p} + ε_t`
pub struct ARModel {
  phi : Array[Double] // AR coefficients [φ₁, …, φ_p]
  intercept : Double // Constant term c
  p : Int // AR order
}

///|
/// Fit an AR(p) model via ordinary least squares.
///
/// Constructs the design matrix with lagged values and solves the
/// normal equations.
///
/// - `data`: Time series of length `n` (must have `n > p + 1`).
/// - `p`: AR order (number of lags).
///
/// Returns the fitted `ARModel`.
pub fn fit_ar(data : Array[Double], p : Int) -> ARModel {
  let n = data.length()
  if p <= 0 || n < p + 2 {
    return { phi: [], intercept: mean(data), p: 0, }
  }
  let n_obs = n - p
  let k = p + 1 // intercept + p AR terms
  let x : Array[Double] = Array::make(n_obs * k, 0.0)
  let y : Array[Double] = Array::make(n_obs, 0.0)
  for i = 0; i < n_obs; i = i + 1 {
    let t = p + i // index of y_t in original data
    x[i * k] = 1.0 // constant
    for j = 0; j < p; j = j + 1 {
      x[i * k + 1 + j] = data[t - 1 - j] // y_{t-1}, y_{t-2}, …
    }
    y[i] = data[t]
  }
  let result = ols(x, y, n_obs, k)
  let phi : Array[Double] = Array::make(p, 0.0)
  for j = 0; j < p; j = j + 1 {
    phi[j] = result.coefficients[1 + j]
  }
  { phi, intercept: result.coefficients[0], p, }
}

///|
/// Forecast future values using an AR(p) model.
///
/// Iteratively applies the AR recurrence, substituting forecasted
/// values for lagged terms once actual data is exhausted.
///
/// - `model`: Fitted AR model.
/// - `data`: Recent history (at least `p` values).
/// - `steps`: Number of steps to forecast.
///
/// Returns an array of length `steps`.
pub fn forecast_ar(
  model : ARModel,
  data : Array[Double],
  steps : Int,
) -> Array[Double] {
  let p = model.p
  if steps <= 0 {
    return []
  }
  // Buffer of last p values (actual → forecasted).
  let buf : Array[Double] = Array::make(p, 0.0)
  let n = data.length()
  for i = 0; i < p; i = i + 1 {
    let idx = n - p + i
    buf[i] = if idx >= 0 { data[idx] } else { 0.0 }
  }
  let forecasts : Array[Double] = Array::make(steps, 0.0)
  for s = 0; s < steps; s = s + 1 {
    let mut y = model.intercept
    for j = 0; j < p; j = j + 1 {
      y = y + model.phi[j] * buf[p - 1 - j]
    }
    forecasts[s] = y
    // Slide window.
    for j = 0; j < p - 1; j = j + 1 {
      buf[j] = buf[j + 1]
    }
    if p > 0 {
      buf[p - 1] = y
    }
  }
  forecasts
}

// ---------------------------------------------------------------------------
// ARIMA(p,d,q) Model — with full MA(q) estimation via Hannan-Rissanen
// ---------------------------------------------------------------------------

///|
/// Fitted ARIMA(p,d,q) model.
///
/// The AR component is estimated on the d-th differenced series.
/// MA coefficients `theta` are estimated via the **Hannan-Rissanen
/// two-step method**: first fit a long AR model to obtain estimated
/// residuals, then run OLS of y_t on [y_{t-1},…,y_{t-p}, ε̂_{t-1},…,ε̂_{t-q}]
/// to get consistent estimates of both AR and MA parameters.
///
/// Forecasting uses both AR and MA components:
/// `ŷ_{T+h} = c + Σφᵢ·ŷ_{T+h-i} + Σθⱼ·ε̂_{T+h-j}`
/// where future innovations (h > j) are set to their expected value of 0.
pub struct ARIMAModel {
  ar_model : ARModel
  theta : Array[Double] // MA coefficients [θ₁, …, θ_q]
  d : Int // differencing order
  q : Int // MA order
  residuals : Array[Double] // Last max(q,1) residuals from fitting (for forecasting)
}

///|
/// Fit an ARIMA(p,d,q) model with full MA estimation.
///
/// Uses the Hannan-Rissanen two-step method:
///
/// 1. Difference the data `d` times to achieve stationarity.
/// 2. Fit a long AR(max(p+q, n/4)) model to obtain estimated residuals `ε̂_t`.
/// 3. Build design matrix [1, y_{t-1},…,y_{t-p}, ε̂_{t-1},…,ε̂_{t-q}] and
///    run OLS to get AR coefficients φ, MA coefficients θ, and intercept c.
/// 4. Compute final residuals from the full ARMA(p,q) model.
///
/// - `data`: Original time series.
/// - `p`: AR order.
/// - `d`: Differencing order.
/// - `q`: MA order (0 = pure ARIMA(p,d,0)).
///
/// Returns the fitted `ARIMAModel`.
pub fn fit_arima(data : Array[Double], p : Int, d : Int, q : Int) -> ARIMAModel {
  let diff_data = difference(data, d)
  let n = diff_data.length()
  // Degenerate cases: no data or pure AR (q == 0).
  if n < p + q + 5 || q <= 0 {
    let ar_model = fit_ar(diff_data, p)
    // Compute residuals for the AR model.
    let resid = compute_ar_residuals(ar_model, diff_data)
    { ar_model, theta: [], d, q, residuals: resid, }
  } else {
    // --- Step 1: Long AR to get estimated residuals ---
    let long_ar_order = if p + q + 10 < n / 4 { p + q + 10 } else { p + q + 3 }
    let long_ar_order = if long_ar_order >= n { n - 2 } else { long_ar_order }
    let long_ar_order = if long_ar_order < 1 { 1 } else { long_ar_order }
    let long_model = fit_ar(diff_data, long_ar_order)
    let eps_hat = compute_ar_residuals(long_model, diff_data)
    // --- Step 2: OLS on [1, y_{t-1},…,y_{t-p}, ε̂_{t-1},…,ε̂_{t-q}] ---
    // We need t from max(p, q) to n-1 (0-indexed in diff_data).
    let start = if p > q { p } else { q }
    let n_obs = n - start
    if n_obs < p + q + 2 {
      // Not enough data for Hannan-Rissanen, fall back to AR-only.
      let ar_model = fit_ar(diff_data, p)
      let resid = compute_ar_residuals(ar_model, diff_data)
      { ar_model, theta: [], d, q, residuals: resid, }
    } else {
      let k = 1 + p + q // intercept + AR terms + MA terms
      let x : Array[Double] = Array::make(n_obs * k, 0.0)
      let y_resp : Array[Double] = Array::make(n_obs, 0.0)
      for i = 0; i < n_obs; i = i + 1 {
        let t = start + i
        x[i * k] = 1.0 // constant
        for j = 0; j < p; j = j + 1 {
          x[i * k + 1 + j] = diff_data[t - 1 - j] // y_{t-1-j}
        }
        for j = 0; j < q; j = j + 1 {
          x[i * k + 1 + p + j] = eps_hat[t - 1 - j] // ε̂_{t-1-j}
        }
        y_resp[i] = diff_data[t]
      }
      let result = ols(x, y_resp, n_obs, k)
      // Extract AR and MA coefficients.
      let phi : Array[Double] = Array::make(p, 0.0)
      for j = 0; j < p; j = j + 1 {
        phi[j] = result.coefficients[1 + j]
      }
      let theta : Array[Double] = Array::make(q, 0.0)
      for j = 0; j < q; j = j + 1 {
        theta[j] = result.coefficients[1 + p + j]
      }
      let ar_model : ARModel = { phi, intercept: result.coefficients[0], p, }
      // --- Step 3: Compute final residuals from ARMA(p,q) model ---
      let resid = compute_arma_residuals(ar_model, theta, diff_data)
      { ar_model, theta, d, q, residuals: resid, }
    }
  }
}

///|
/// Compute residuals from an AR(p) model.
///
/// `ε_t = y_t − (intercept + Σφᵢ·y_{t-i})`
fn compute_ar_residuals(model : ARModel, data : Array[Double]) -> Array[Double] {
  let n = data.length()
  let p = model.p
  if n == 0 {
    return []
  }
  let resid : Array[Double] = Array::make(n, 0.0)
  for t = 0; t < n; t = t + 1 {
    let mut pred = model.intercept
    for j = 0; j < p; j = j + 1 {
      let idx = t - 1 - j
      if idx >= 0 {
        pred = pred + model.phi[j] * data[idx]
      }
    }
    resid[t] = data[t] - pred
  }
  resid
}

///|
/// Compute residuals from an ARMA(p,q) model.
///
/// `ε_t = y_t − intercept − Σφᵢ·y_{t-i} − Σθⱼ·ε_{t-j}`
///
/// Computed recursively: ε_0 assumes no past residuals (set to 0).
fn compute_arma_residuals(
  ar_model : ARModel,
  theta : Array[Double],
  data : Array[Double],
) -> Array[Double] {
  let n = data.length()
  let p = ar_model.p
  let q = theta.length()
  if n == 0 {
    return []
  }
  let resid : Array[Double] = Array::make(n, 0.0)
  for t = 0; t < n; t = t + 1 {
    let mut pred = ar_model.intercept
    // AR terms
    for j = 0; j < p; j = j + 1 {
      let idx = t - 1 - j
      if idx >= 0 {
        pred = pred + ar_model.phi[j] * data[idx]
      }
    }
    // MA terms: use previously computed residuals
    for j = 0; j < q; j = j + 1 {
      let idx = t - 1 - j
      if idx >= 0 {
        pred = pred + theta[j] * resid[idx]
      }
    }
    resid[t] = data[t] - pred
  }
  resid
}

///|
/// Integrate differenced forecasts back to the original scale.
///
/// Given forecasts of the d-th difference, recursively undo the
/// differencing using the last values at each integration level.
fn integrate_forecasts(
  forecasts : Array[Double],
  data : Array[Double],
  d : Int,
) -> Array[Double] {
  if d == 0 {
    return Array::copy(forecasts)
  }
  // Store last value at each level of differencing.
  // levels[0] = last value of original data
  // levels[1] = last value of first difference
  // …
  // levels[d-1] = last value of (d-1)-th difference
  let levels : Array[Double] = Array::make(d, 0.0)
  let mut current = Array::copy(data)
  for level = 0; level < d; level = level + 1 {
    if current.length() > 0 {
      levels[level] = current[current.length() - 1]
    }
    let m = current.length()
    if m < 2 {
      current = []
    } else {
      let diff : Array[Double] = Array::make(m - 1, 0.0)
      for i = 1; i < m; i = i + 1 {
        diff[i - 1] = current[i] - current[i - 1]
      }
      current = diff
    }
  }
  // Integrate from level d−1 down to 0.
  let result = Array::copy(forecasts)
  for level = d - 1; level >= 0; level = level - 1 {
    let mut cum = levels[level]
    for i = 0; i < result.length(); i = i + 1 {
      cum = cum + result[i]
      result[i] = cum
    }
  }
  result
}

///|
/// Forecast future values using an ARIMA model with MA component.
///
/// The forecast uses both AR and MA terms:
/// `ŷ_{T+h} = c + Σ_{i=1}^{p} φᵢ·ŷ_{T+h-i} + Σ_{j=1}^{q} θⱼ·ε̂_{T+h-j}`
///
/// - For h ≤ i: `ŷ_{T+h-i}` is the actual differenced value.
/// - For h > i: `ŷ_{T+h-i}` is a previous forecast.
/// - For h ≤ j: `ε̂_{T+h-j}` is the in-sample residual.
/// - For h > j: `ε̂_{T+h-j}` = 0 (expected future innovation).
///
/// Steps:
/// 1. Difference the input data `d` times.
/// 2. Forecast the differenced series with ARMA(p,q).
/// 3. Integrate the forecasts back to the original scale.
///
/// - `model`: Fitted ARIMA model.
/// - `data`: Recent history of the original series.
/// - `steps`: Number of steps to forecast.
pub fn forecast_arima(
  model : ARIMAModel,
  data : Array[Double],
  steps : Int,
) -> Array[Double] {
  if steps <= 0 {
    return []
  }
  let diff_data = difference(data, model.d)
  let p = model.ar_model.p
  let q = model.q
  // Buffer of recent differenced values (actual → forecasted).
  let buf : Array[Double] = Array::make(p, 0.0)
  let n = diff_data.length()
  for i = 0; i < p; i = i + 1 {
    let idx = n - p + i
    buf[i] = if idx >= 0 { diff_data[idx] } else { 0.0 }
  }
  // Buffer of recent residuals (from in-sample fitting).
  // We need the last q residuals.
  let resid_buf : Array[Double] = Array::make(q, 0.0)
  let n_resid = model.residuals.length()
  for j = 0; j < q; j = j + 1 {
    let idx = n_resid - q + j
    resid_buf[j] = if idx >= 0 { model.residuals[idx] } else { 0.0 }
  }
  let forecasts : Array[Double] = Array::make(steps, 0.0)
  for s = 0; s < steps; s = s + 1 {
    let mut y = model.ar_model.intercept
    // AR terms: φᵢ · y_{T+h-i}
    for j = 0; j < p; j = j + 1 {
      y = y + model.ar_model.phi[j] * buf[p - 1 - j]
    }
    // MA terms: θⱼ · ε_{T+h-j}
    // For step s, we need residuals at lags 1..q relative to T+s.
    // Lag j relative to T+s means index s - j in our forecast residual buffer.
    // s - j < 0 means it's an in-sample residual; s - j ≥ 0 means future (= 0).
    for j = 0; j < q; j = j + 1 {
      let lag = j + 1 // θ₁ corresponds to ε_{t-1}
      let resid_idx = s - lag
      if resid_idx < 0 {
        // In-sample residual: resid_buf[q - 1 + resid_idx] = resid_buf[q - 1 - lag + s]
        let buf_idx = q - 1 + resid_idx
        if buf_idx >= 0 {
          y = y + model.theta[j] * resid_buf[buf_idx]
        }
      }
      // Future innovations are 0 — no contribution.
    }
    forecasts[s] = y
    // Slide AR buffer.
    for j = 0; j < p - 1; j = j + 1 {
      buf[j] = buf[j + 1]
    }
    if p > 0 {
      buf[p - 1] = y
    }
  }
  integrate_forecasts(forecasts, data, model.d)
}

// ---------------------------------------------------------------------------
// GARCH(1,1) Model
// ---------------------------------------------------------------------------

///|
/// Fitted GARCH(1,1) model.
///
/// `σ²_t = ω + α·ε²_{t-1} + β·σ²_{t-1}`
///
/// The long-run (unconditional) variance is
/// `σ² = ω / (1 − α − β)`.
pub struct GARCHModel {
  omega : Double
  alpha : Double
  beta : Double
  long_run_variance : Double
}

///|
/// Gaussian log-likelihood for GARCH(1,1).
///
/// `L = −½ Σ [ln(2π) + ln(σ²_t) + ε²_t / σ²_t]`
///
/// The conditional variance is initialised at the sample variance
/// and evolved recursively.
fn garch_log_likelihood(
  residuals : Array[Double],
  omega : Double,
  alpha : Double,
  beta : Double,
) -> Double {
  let n = residuals.length()
  if n == 0 {
    return 0.0
  }
  // Sample variance for initialisation.
  let mut var0 = 0.0
  for i = 0; i < n; i = i + 1 {
    var0 = var0 + residuals[i] * residuals[i]
  }
  var0 = var0 / n.to_double()
  if var0 <= 0.0 {
    return -1.0e300
  }
  let ln2pi = @math.ln(2.0 * @math.PI)
  let mut sigma2 = var0
  let mut ll = 0.0
  for t = 0; t < n; t = t + 1 {
    if t > 0 {
      sigma2 = omega +
        alpha * residuals[t - 1] * residuals[t - 1] +
        beta * sigma2
    }
    if sigma2 <= 0.0 {
      return -1.0e300
    }
    ll = ll -
      0.5 * (ln2pi + @math.ln(sigma2) + residuals[t] * residuals[t] / sigma2)
  }
  ll
}

///|
/// Fit a GARCH(1,1) model by maximising the Gaussian log-likelihood.
///
/// Uses coordinate descent: at each iteration, try perturbing each
/// parameter (ω, α, β) by ±step; accept if the log-likelihood
/// improves and stationarity constraints hold (ω > 0, α ≥ 0, β ≥ 0,
/// α + β < 1). When no parameter improves, halve all step sizes.
///
/// - `returns`: Time series of returns.
/// - `max_iter`: Maximum optimisation iterations.
///
/// Returns the fitted `GARCHModel`.
pub fn fit_garch(returns : Array[Double], max_iter : Int) -> GARCHModel {
  let n = returns.length()
  if n < 5 {
    return { omega: 0.0, alpha: 0.0, beta: 0.0, long_run_variance: 0.0, }
  }
  // Demean returns to obtain residuals.
  let mu = mean(returns)
  let residuals : Array[Double] = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    residuals[i] = returns[i] - mu
  }
  // Sample variance.
  let mut var_sum = 0.0
  for i = 0; i < n; i = i + 1 {
    var_sum = var_sum + residuals[i] * residuals[i]
  }
  let variance = var_sum / n.to_double()
  if variance <= 0.0 {
    return { omega: 0.0, alpha: 0.0, beta: 0.0, long_run_variance: 0.0, }
  }
  // Initial parameters.
  let mut omega = 0.1 * variance
  let mut alpha = 0.1
  let mut beta = 0.8
  let mut best_ll = garch_log_likelihood(residuals, omega, alpha, beta)
  // Step sizes.
  let mut step_omega = 0.05 * variance
  let mut step_alpha = 0.05
  let mut step_beta = 0.05
  for iter = 0; iter < max_iter; iter = iter + 1 {
    let mut improved = false
    // Perturb omega (both directions).
    let omega_up = omega + step_omega
    if omega_up > 0.0 {
      let ll = garch_log_likelihood(residuals, omega_up, alpha, beta)
      if ll > best_ll {
        omega = omega_up
        best_ll = ll
        improved = true
      }
    }
    let omega_dn = omega - step_omega
    if omega_dn > 0.0 {
      let ll = garch_log_likelihood(residuals, omega_dn, alpha, beta)
      if ll > best_ll {
        omega = omega_dn
        best_ll = ll
        improved = true
      }
    }
    // Perturb alpha.
    let alpha_up = alpha + step_alpha
    if alpha_up >= 0.0 && alpha_up + beta < 0.999 {
      let ll = garch_log_likelihood(residuals, omega, alpha_up, beta)
      if ll > best_ll {
        alpha = alpha_up
        best_ll = ll
        improved = true
      }
    }
    let alpha_dn = alpha - step_alpha
    if alpha_dn >= 0.0 {
      let ll = garch_log_likelihood(residuals, omega, alpha_dn, beta)
      if ll > best_ll {
        alpha = alpha_dn
        best_ll = ll
        improved = true
      }
    }
    // Perturb beta.
    let beta_up = beta + step_beta
    if beta_up >= 0.0 && alpha + beta_up < 0.999 {
      let ll = garch_log_likelihood(residuals, omega, alpha, beta_up)
      if ll > best_ll {
        beta = beta_up
        best_ll = ll
        improved = true
      }
    }
    let beta_dn = beta - step_beta
    if beta_dn >= 0.0 {
      let ll = garch_log_likelihood(residuals, omega, alpha, beta_dn)
      if ll > best_ll {
        beta = beta_dn
        best_ll = ll
        improved = true
      }
    }
    if improved == false {
      step_omega = step_omega * 0.5
      step_alpha = step_alpha * 0.5
      step_beta = step_beta * 0.5
      if step_omega < variance * 1.0e-10 &&
        step_alpha < 1.0e-10 &&
        step_beta < 1.0e-10 {
        break
      }
    }
  }
  let lr_var = if alpha + beta < 0.999 {
    omega / (1.0 - alpha - beta)
  } else {
    variance
  }
  { omega, alpha, beta, long_run_variance: lr_var, }
}

///|
/// Forecast conditional variance using a GARCH(1,1) model.
///
/// The variance recursion is:
/// `σ²_{t+h} = ω + α·ε²_{t+h-1} + β·σ²_{t+h-1}`
///
/// For h > 1, expected future residuals are zero, so the forecast
/// simplifies to:
/// `σ²_{t+h} = ω + (α + β)·σ²_{t+h-1}`
///
/// This converges to the long-run variance `ω / (1 − α − β)`.
///
/// - `model`: Fitted GARCH model.
/// - `last_residual`: The most recent residual `ε_t`.
/// - `last_variance`: The most recent conditional variance `σ²_t`.
/// - `steps`: Number of steps to forecast.
pub fn garch_forecast(
  model : GARCHModel,
  last_residual : Double,
  last_variance : Double,
  steps : Int,
) -> Array[Double] {
  if steps <= 0 {
    return []
  }
  let forecasts : Array[Double] = Array::make(steps, 0.0)
  // Step 1: uses actual last residual.
  let mut sigma2 = model.omega +
    model.alpha * last_residual * last_residual +
    model.beta * last_variance
  if sigma2 < 0.0 {
    sigma2 = 0.0
  }
  forecasts[0] = sigma2
  // Steps 2..: expected residual = 0.
  for h = 1; h < steps; h = h + 1 {
    sigma2 = model.omega + (model.alpha + model.beta) * sigma2
    if sigma2 < 0.0 {
      sigma2 = 0.0
    }
    forecasts[h] = sigma2
  }
  forecasts
}

// ---------------------------------------------------------------------------
// Augmented Dickey-Fuller Test
// ---------------------------------------------------------------------------

///|
/// Result of an ADF unit-root test.
pub struct ADFResult {
  test_statistic : Double // t-ratio on γ̂
  critical_value_5pct : Double // asymptotic 5% critical value
  is_stationary : Bool // true if test stat < critical value
  lag_order : Int // number of lagged differences used
}

///|
/// Run the Augmented Dickey-Fuller test (with constant, no trend).
///
/// Regression:
/// `Δy_t = α + γ·y_{t-1} + Σ_{i=1}^{p} δ_i·Δy_{t-i} + ε_t`
///
/// The null hypothesis is `γ = 0` (unit root). The test statistic is
/// the t-ratio on γ̂. If the statistic is more negative than the
/// critical value, the null is rejected and the series is deemed
/// stationary.
///
/// - `data`: Time series to test.
/// - `max_lags`: Number of lagged differences `p`. If negative, a
///   Schwert-criterion default is used.
///
/// Returns the `ADFResult`.
pub fn adf_test(data : Array[Double], max_lags : Int) -> ADFResult {
  let n = data.length()
  if n < 5 {
    return {
      test_statistic: 0.0,
      critical_value_5pct: -2.86,
      is_stationary: false,
      lag_order: 0,
    }
  }
  // First differences: dy[i] = y[i+1] − y[i]
  let n_diff = n - 1
  let dy : Array[Double] = Array::make(n_diff, 0.0)
  for i = 0; i < n_diff; i = i + 1 {
    dy[i] = data[i + 1] - data[i]
  }
  // Determine lag order p.
  let p = if max_lags < 0 {
    // Schwert criterion: floor(12 * (n/100)^0.25)
    let sc = 12.0 * @math.pow(n.to_double() / 100.0, 0.25)
    let p_sc = @math.floor(sc).to_int()
    if p_sc > n - 5 {
      n - 5
    } else {
      p_sc
    }
  } else if max_lags > n - 5 {
    n - 5
  } else {
    max_lags
  }
  let p = if p < 0 { 0 } else { p }
  // Build design matrix.
  // Observations: t = p+1, …, n−1  →  n_obs = n − p − 1
  // Columns: [1, y_{t-1}, Δy_{t-1}, …, Δy_{t-p}]  →  k = p + 2
  let n_obs = n - p - 1
  let k = p + 2
  if n_obs < k + 1 {
    return {
      test_statistic: 0.0,
      critical_value_5pct: -2.86,
      is_stationary: false,
      lag_order: p,
    }
  }
  let x : Array[Double] = Array::make(n_obs * k, 0.0)
  let y_resp : Array[Double] = Array::make(n_obs, 0.0)
  for i = 0; i < n_obs; i = i + 1 {
    x[i * k] = 1.0 // constant
    x[i * k + 1] = data[p + i] // y_{t-1}
    for j = 1; j <= p; j = j + 1 {
      x[i * k + 1 + j] = dy[p + i - j] // Δy_{t-j}
    }
    y_resp[i] = dy[p + i] // Δy_t
  }
  let result = ols(x, y_resp, n_obs, k)
  // γ is coefficient index 1 (on y_{t-1}).
  let t_stat = result.t_statistics[1]
  let cv = -2.86 // asymptotic 5% critical value (constant, no trend)
  {
    test_statistic: t_stat,
    critical_value_5pct: cv,
    is_stationary: t_stat < cv,
    lag_order: p,
  }
}

// ---------------------------------------------------------------------------
// Engle-Granger Cointegration Test
// ---------------------------------------------------------------------------

///|
/// Result of an Engle-Granger cointegration test.
pub struct CointegrationResult {
  test_statistic : Double // ADF t-ratio on residuals
  critical_value_5pct : Double // EG 5% critical value
  is_cointegrated : Bool // true if stat < critical value
  hedge_ratio : Double // OLS β from y = α + β·x + u
}

///|
/// Run the Engle-Granger two-step cointegration test.
///
/// 1. Regress `y` on `x` (with constant) and extract residuals.
/// 2. Run an ADF test (without constant) on the residuals.
///
/// If the residual series is stationary, `y` and `x` are
/// cointegrated — they share a long-run equilibrium relationship.
///
/// - `y`: Dependent series.
/// - `x`: Independent series (same length as `y`).
///
/// Returns the `CointegrationResult`.
pub fn cointegration_test(
  y : Array[Double],
  x : Array[Double],
) -> CointegrationResult {
  let n = y.length()
  if n < 10 || n != x.length() {
    return {
      test_statistic: 0.0,
      critical_value_5pct: -3.34,
      is_cointegrated: false,
      hedge_ratio: 0.0,
    }
  }
  // Step 1: OLS regression y = α + β·x + u
  let design : Array[Double] = Array::make(n * 2, 0.0)
  for t = 0; t < n; t = t + 1 {
    design[t * 2] = 1.0
    design[t * 2 + 1] = x[t]
  }
  let reg = ols(design, y, n, 2)
  let alpha = reg.coefficients[0]
  let beta = reg.coefficients[1]
  // Residuals.
  let residuals : Array[Double] = Array::make(n, 0.0)
  for t = 0; t < n; t = t + 1 {
    residuals[t] = y[t] - alpha - beta * x[t]
  }
  // Step 2: ADF on residuals (no constant, 1 lag by default).
  let m = residuals.length()
  let n_diff = m - 1
  let du : Array[Double] = Array::make(n_diff, 0.0)
  for i = 0; i < n_diff; i = i + 1 {
    du[i] = residuals[i + 1] - residuals[i]
  }
  // Use 1 lag.
  let p = 1
  let n_obs = m - p - 1
  let k = p + 1 // no constant: u_{t-1} + Δu_{t-1}
  if n_obs < k + 2 {
    return {
      test_statistic: 0.0,
      critical_value_5pct: -3.34,
      is_cointegrated: false,
      hedge_ratio: beta,
    }
  }
  let x_adf : Array[Double] = Array::make(n_obs * k, 0.0)
  let y_adf : Array[Double] = Array::make(n_obs, 0.0)
  for i = 0; i < n_obs; i = i + 1 {
    x_adf[i * k] = residuals[p + i] // u_{t-1}
    for j = 1; j <= p; j = j + 1 {
      x_adf[i * k + j] = du[p + i - j] // Δu_{t-j}
    }
    y_adf[i] = du[p + i] // Δu_t
  }
  let result = ols(x_adf, y_adf, n_obs, k)
  // γ is coefficient index 0 (on u_{t-1}).
  let t_stat = result.t_statistics[0]
  // EG 5% critical value for 2 variables: −3.34
  let cv = -3.34
  {
    test_statistic: t_stat,
    critical_value_5pct: cv,
    is_cointegrated: t_stat < cv,
    hedge_ratio: beta,
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "difference: first and second order" {
  let data = [1.0, 4.0, 9.0, 16.0, 25.0]
  let d1 = difference(data, 1)
  assert_eq(d1.length(), 4)
  assert_true((d1[0] - 3.0).abs() < 1.0e-10)
  assert_true((d1[1] - 5.0).abs() < 1.0e-10)
  assert_true((d1[2] - 7.0).abs() < 1.0e-10)
  assert_true((d1[3] - 9.0).abs() < 1.0e-10)
  let d2 = difference(data, 2)
  assert_eq(d2.length(), 3)
  assert_true((d2[0] - 2.0).abs() < 1.0e-10)
  assert_true((d2[1] - 2.0).abs() < 1.0e-10)
  assert_true((d2[2] - 2.0).abs() < 1.0e-10)
}

///|
test "difference: order zero returns copy" {
  let data = [3.0, 7.0, 2.0]
  let d0 = difference(data, 0)
  assert_eq(d0.length(), 3)
  assert_true((d0[0] - 3.0).abs() < 1.0e-10)
  assert_true((d0[1] - 7.0).abs() < 1.0e-10)
  assert_true((d0[2] - 2.0).abs() < 1.0e-10)
}

///|
test "ar: fit AR(1) recovers coefficient" {
  // Generate AR(1): y_t = 0.5 * y_{t-1} + noise
  let n = 300
  let data : Array[Double] = Array::make(n, 0.0)
  let mut y = 0.0
  for i = 0; i < n; i = i + 1 {
    let t = i.to_double()
    // Pseudo-random noise in [−0.1, 0.1]
    let hash = @math.sin(t * 12.9898) * 43758.5453
    let noise = (hash - @math.floor(hash) - 0.5) * 0.2
    y = 0.5 * y + noise
    data[i] = y
  }
  let model = fit_ar(data, 1)
  // Coefficient should be close to 0.5.
  assert_true((model.phi[0] - 0.5).abs() < 0.15)
  // Intercept should be close to 0.
  assert_true(model.intercept.abs() < 0.05)
}

///|
test "ar: forecast converges to mean for stationary process" {
  // AR(1) with phi = 0.3, intercept = 5.0
  // Long-run mean = intercept / (1 - phi) = 5.0 / 0.7 ≈ 7.14
  let model : ARModel = { phi: [0.3], intercept: 5.0, p: 1, }
  let data = [10.0, 8.0]
  let forecasts = forecast_ar(model, data, 20)
  // Forecasts should converge toward 7.14.
  let long_run_mean = 5.0 / (1.0 - 0.3)
  // Last forecast should be close to the long-run mean.
  assert_true((forecasts[19] - long_run_mean).abs() < 1.0)
  // Forecasts should be monotonically approaching the mean.
  let diff_first = (forecasts[0] - long_run_mean).abs()
  let diff_last = (forecasts[19] - long_run_mean).abs()
  assert_true(diff_last < diff_first)
}

///|
test "arima: forecast integrates differenced series" {
  // Linear trend: y_t = 2*t → first difference is constant 2.0
  let data : Array[Double] = Array::make(20, 0.0)
  for i = 0; i < 20; i = i + 1 {
    data[i] = 2.0 * i.to_double()
  }
  // ARIMA(0,1,0): difference once, no AR terms.
  let model = fit_arima(data, 0, 1, 0)
  let forecasts = forecast_arima(model, data, 5)
  // The first difference is constant 2.0, so each forecast should
  // increase by 2.0 from the last data point.
  let last_val = data[19]
  assert_true((forecasts[0] - (last_val + 2.0)).abs() < 1.0e-6)
  assert_true((forecasts[1] - (last_val + 4.0)).abs() < 1.0e-6)
  assert_true((forecasts[4] - (last_val + 10.0)).abs() < 1.0e-6)
}

///|
test "arima: MA(1) coefficients are estimated" {
  // Generate MA(1): y_t = ε_t + 0.5·ε_{t-1}
  let n = 500
  let data : Array[Double] = Array::make(n, 0.0)
  let mut prev_eps = 0.0
  for i = 0; i < n; i = i + 1 {
    let t = i.to_double()
    let hash = @math.sin(t * 12.9898) * 43758.5453
    let eps = (hash - @math.floor(hash) - 0.5) * 2.0
    data[i] = eps + 0.5 * prev_eps
    prev_eps = eps
  }
  let model = fit_arima(data, 0, 0, 1)
  // q should be 1.
  assert_eq(model.q, 1)
  // theta should have 1 element.
  assert_eq(model.theta.length(), 1)
  // MA coefficient should be in a reasonable range around 0.5.
  assert_true(model.theta[0] > 0.0)
  assert_true(model.theta[0] < 1.0)
}

///|
test "arima: ARMA(1,1) forecast uses MA component" {
  // Generate ARMA(1,1): y_t = 0.4·y_{t-1} + ε_t + 0.3·ε_{t-1}
  let n = 500
  let data : Array[Double] = Array::make(n, 0.0)
  let mut prev_y = 0.0
  let mut prev_eps = 0.0
  for i = 0; i < n; i = i + 1 {
    let t = i.to_double()
    let hash = @math.sin(t * 7.3137) * 9999.0
    let eps = (hash - @math.floor(hash) - 0.5) * 1.0
    let y = 0.4 * prev_y + eps + 0.3 * prev_eps
    data[i] = y
    prev_y = y
    prev_eps = eps
  }
  let model = fit_arima(data, 1, 0, 1)
  // Both AR and MA should be estimated.
  assert_eq(model.ar_model.p, 1)
  assert_eq(model.q, 1)
  assert_eq(model.theta.length(), 1)
  // AR coefficient should be positive and less than 1.
  assert_true(model.ar_model.phi[0] > 0.0)
  assert_true(model.ar_model.phi[0] < 1.0)
  // Forecast should produce finite values.
  let forecasts = forecast_arima(model, data, 10)
  assert_eq(forecasts.length(), 10)
  for i = 0; i < 10; i = i + 1 {
    assert_true(forecasts[i].abs() < 100.0)
  }
}

///|
test "arima: MA(2) model fits and forecasts" {
  // Generate MA(2): y_t = ε_t + 0.4·ε_{t-1} + 0.2·ε_{t-2}
  let n = 500
  let data : Array[Double] = Array::make(n, 0.0)
  let mut eps1 = 0.0
  let mut eps2 = 0.0
  for i = 0; i < n; i = i + 1 {
    let t = i.to_double()
    let hash = @math.sin(t * 3.7331) * 7777.0
    let eps = (hash - @math.floor(hash) - 0.5) * 1.5
    data[i] = eps + 0.4 * eps1 + 0.2 * eps2
    eps2 = eps1
    eps1 = eps
  }
  let model = fit_arima(data, 0, 0, 2)
  assert_eq(model.q, 2)
  assert_eq(model.theta.length(), 2)
  // Forecasts should converge toward 0 (unconditional mean for zero-intercept MA).
  let forecasts = forecast_arima(model, data, 20)
  assert_eq(forecasts.length(), 20)
  // MA forecasts should decay toward the mean after q steps.
  // After step 2, no MA contribution → forecast should be close to intercept.
  assert_true(forecasts[5].abs() < 5.0)
}

///|
test "arima: q=0 falls back to AR-only" {
  // Pure AR(1) data with q=0 should work identically to fit_ar.
  let n = 300
  let data : Array[Double] = Array::make(n, 0.0)
  let mut y = 0.0
  for i = 0; i < n; i = i + 1 {
    let t = i.to_double()
    let hash = @math.sin(t * 5.5115) * 3333.0
    let noise = (hash - @math.floor(hash) - 0.5) * 0.3
    y = 0.6 * y + noise
    data[i] = y
  }
  let model = fit_arima(data, 1, 0, 0)
  assert_eq(model.q, 0)
  assert_eq(model.theta.length(), 0)
  // Should still produce valid forecasts.
  let forecasts = forecast_arima(model, data, 5)
  assert_eq(forecasts.length(), 5)
  // AR(1) with phi=0.6 should produce converging forecasts.
  assert_true(forecasts[0].abs() < 100.0)
}

///|
test "adf: stationary AR(1) is rejected" {
  // Generate stationary AR(1): y_t = 0.3 * y_{t-1} + noise
  let n = 200
  let data : Array[Double] = Array::make(n, 0.0)
  let mut y = 0.0
  for i = 0; i < n; i = i + 1 {
    let t = i.to_double()
    let hash = @math.sin(t * 7.123) * 1000.0
    let noise = (hash - @math.floor(hash) - 0.5) * 0.5
    y = 0.3 * y + noise
    data[i] = y
  }
  let result = adf_test(data, 1)
  // Stationary series should have a very negative test statistic.
  assert_true(result.test_statistic < -2.86)
  assert_true(result.is_stationary)
}

///|
test "adf: random walk is not rejected" {
  // Generate random walk: y_t = y_{t-1} + noise
  let n = 200
  let data : Array[Double] = Array::make(n, 0.0)
  let mut y = 0.0
  for i = 0; i < n; i = i + 1 {
    let t = i.to_double()
    let hash = @math.sin(t * 5.678) * 1000.0
    let noise = (hash - @math.floor(hash) - 0.5) * 0.5
    y = y + noise
    data[i] = y
  }
  let result = adf_test(data, 1)
  // Random walk should not be rejected as stationary.
  assert_true(result.test_statistic > -2.86 || result.is_stationary == false)
}

///|
test "garch: fitted parameters in valid range" {
  // Generate GARCH(1,1) data: ω=0.1, α=0.15, β=0.8
  let n = 500
  let returns : Array[Double] = Array::make(n, 0.0)
  let omega_true = 0.1
  let alpha_true = 0.15
  let beta_true = 0.8
  let mut sigma2 = omega_true / (1.0 - alpha_true - beta_true)
  let mut prev_eps = 0.0
  for i = 0; i < n; i = i + 1 {
    let t = i.to_double()
    let hash = @math.sin(t * 3.14159) * 9999.0
    let noise = (hash - @math.floor(hash) - 0.5) * 2.0
    sigma2 = omega_true + alpha_true * prev_eps * prev_eps + beta_true * sigma2
    let eps = noise * sigma2.sqrt()
    returns[i] = eps
    prev_eps = eps
  }
  let model = fit_garch(returns, 200)
  // Parameters should be in valid range.
  assert_true(model.omega > 0.0)
  assert_true(model.alpha >= 0.0)
  assert_true(model.beta >= 0.0)
  assert_true(model.alpha + model.beta < 0.999)
  assert_true(model.long_run_variance > 0.0)
}

///|
test "garch: forecast converges to long-run variance" {
  let model : GARCHModel = {
    omega: 0.1,
    alpha: 0.15,
    beta: 0.8,
    long_run_variance: 0.1 / (1.0 - 0.15 - 0.8),
  }
  let forecasts = garch_forecast(model, 0.5, 0.3, 50)
  // Long-run variance = 0.1 / 0.05 = 2.0
  let lr_var = 2.0
  // Last forecast should converge toward lr_var.
  assert_true((forecasts[49] - lr_var).abs() < 0.5)
}

///|
test "cointegration: cointegrated series detected" {
  // Generate cointegrated series:
  // x is a random walk, y = 2*x + stationary noise
  let n = 200
  let x : Array[Double] = Array::make(n, 0.0)
  let y : Array[Double] = Array::make(n, 0.0)
  let mut x_val = 0.0
  for i = 0; i < n; i = i + 1 {
    let t = i.to_double()
    let hash1 = @math.sin(t * 9.876) * 1000.0
    let rw_noise = (hash1 - @math.floor(hash1) - 0.5) * 0.5
    x_val = x_val + rw_noise
    x[i] = x_val
    let hash2 = @math.sin(t * 4.321) * 1000.0
    let stat_noise = (hash2 - @math.floor(hash2) - 0.5) * 0.3
    y[i] = 2.0 * x_val + stat_noise
  }
  let result = cointegration_test(y, x)
  // Hedge ratio should be close to 2.0.
  assert_true((result.hedge_ratio - 2.0).abs() < 0.3)
  // Should detect cointegration.
  assert_true(result.is_cointegrated)
}

///|
test "cointegration: independent random walks not cointegrated" {
  // Two independent random walks
  let n = 200
  let x : Array[Double] = Array::make(n, 0.0)
  let y : Array[Double] = Array::make(n, 0.0)
  let mut x_val = 0.0
  let mut y_val = 0.0
  for i = 0; i < n; i = i + 1 {
    let t = i.to_double()
    let hash1 = @math.sin(t * 11.223) * 1000.0
    let n1 = (hash1 - @math.floor(hash1) - 0.5) * 0.5
    x_val = x_val + n1
    x[i] = x_val
    let hash2 = @math.sin(t * 33.445) * 1000.0
    let n2 = (hash2 - @math.floor(hash2) - 0.5) * 0.5
    y_val = y_val + n2
    y[i] = y_val
  }
  let result = cointegration_test(y, x)
  // Should not detect cointegration (or at least the statistic
  // should be less negative than for truly cointegrated series).
  assert_true(result.is_cointegrated == false)
}

///|
test "ols: linear regression recovers coefficients" {
  // y = 2 + 3*x + noise
  let n = 100
  let x : Array[Double] = Array::make(n * 2, 0.0)
  let y : Array[Double] = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    let xv = i.to_double() * 0.1
    x[i * 2] = 1.0
    x[i * 2 + 1] = xv
    y[i] = 2.0 + 3.0 * xv
  }
  let result = ols(x, y, n, 2)
  assert_true((result.coefficients[0] - 2.0).abs() < 1.0e-6)
  assert_true((result.coefficients[1] - 3.0).abs() < 1.0e-6)
  assert_true((result.r_squared - 1.0).abs() < 1.0e-6)
}
