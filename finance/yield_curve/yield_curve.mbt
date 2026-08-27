/// Yield Curve — term structure of interest rates with interpolation and
/// Nelson-Siegel fitting.
///
/// This module provides a production-grade yield curve implementation
/// supporting:
///
/// - **Bootstrapping**: Extract zero rates from market instruments
///   (zero-coupon bonds, coupon-bearing bonds).
/// - **Interpolation**: Linear, log-linear, and natural cubic spline
///   interpolation of zero rates or discount factors.
/// - **Forward rates**: Instantaneous and simple forward rates.
/// - **Discount factors**: Present value of a future cash flow.
/// - **Nelson-Siegel model**: Parametric yield curve fitting with
///   β₁ (level), β₂ (slope), β₃ (curvature), and λ₁ (decay).
/// - **Nelson-Siegel-Svensson model**: Extended 6-parameter model with
///   additional β₄ and λ₂.
///
/// ## Conventions
///
/// - Rates are expressed as **continuously compounded** annual rates.
/// - Times are in **years** (actual/365 or ACT/365 day count).
/// - `df(t) = exp(-r(t) · t)` where `r(t)` is the zero rate at time `t`.
///
/// ## References
///
/// - Nelson, C. R. & Siegel, A. F. (1987). "Parsimonious Modeling of Yield
///   Curves." *Journal of Business* 60(4), 473–489.
/// - Svensson, L. E. O. (1994). "Estimating and Interpreting Forward
///   Interest Rates: Sweden 1992–1994." *IMF Working Paper* WP/94/114.
/// - Hagan, P. S. & West, G. (2006). "Interpolation Methods for Curve
///   Construction." *Applied Mathematical Finance* 13(2), 89–129.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Yield Curve data structure
// ---------------------------------------------------------------------------

///|
/// Interpolation method for the yield curve.
pub enum InterpMethod {
  /// Linear interpolation of zero rates.
  Linear
  /// Log-linear interpolation of discount factors.
  LogLinear
  /// Natural cubic spline interpolation of zero rates.
  CubicSpline
}

///|
/// A yield curve storing tenors (in years) and continuously compounded
/// zero rates.
///
/// The curve supports interpolation at arbitrary maturities and conversion
/// between zero rates, discount factors, and forward rates.
pub struct YieldCurve {
  /// Sorted tenors (years)
  priv tenors : Array[Double]
  /// Continuously compounded zero rates at each tenor
  priv zero_rates : Array[Double]
  /// Interpolation method
  priv interp : InterpMethod
  /// Cubic spline second derivatives (precomputed for CubicSpline method)
  priv spline_seconds : Array[Double]
}

///|
/// Create a yield curve from sorted tenors and zero rates using linear
/// interpolation.
///
/// Tenors must be strictly increasing and non-negative. Zero rates are
/// continuously compounded annual rates.
pub fn yield_curve_linear(
  tenors : Array[Double],
  zero_rates : Array[Double],
) -> YieldCurve {
  yield_curve_make(tenors, zero_rates, Linear)
}

///|
/// Create a yield curve from sorted tenors and zero rates using log-linear
/// interpolation (interpolates log of discount factors linearly).
pub fn yield_curve_log_linear(
  tenors : Array[Double],
  zero_rates : Array[Double],
) -> YieldCurve {
  yield_curve_make(tenors, zero_rates, LogLinear)
}

///|
/// Create a yield curve from sorted tenors and zero rates using natural
/// cubic spline interpolation of zero rates.
pub fn yield_curve_cubic_spline(
  tenors : Array[Double],
  zero_rates : Array[Double],
) -> YieldCurve {
  yield_curve_make(tenors, zero_rates, CubicSpline)
}

///|
/// Internal: create a yield curve with the given interpolation method.
fn yield_curve_make(
  tenors : Array[Double],
  zero_rates : Array[Double],
  interp_method : InterpMethod,
) -> YieldCurve {
  let n = tenors.length()
  if n != zero_rates.length() || n < 1 {
    abort(
      "yield_curve_make: tenors and zero_rates must have equal length ≥ 1",
    )
  }
  // Validate strictly increasing tenors
  for i = 1; i < n; i = i + 1 {
    if tenors[i] <= tenors[i - 1] {
      abort("yield_curve_make: tenors must be strictly increasing")
    }
  }
  // Compute spline second derivatives if needed
  let spline_seconds = match interp_method {
    CubicSpline => natural_cubic_spline_seconds(tenors, zero_rates)
    _ => Array::make(n, 0.0)
  }
  {
    tenors: Array::copy(tenors),
    zero_rates: Array::copy(zero_rates),
    interp: interp_method,
    spline_seconds,
  }
}

// ---------------------------------------------------------------------------
// Natural cubic spline computation
// ---------------------------------------------------------------------------

///|
/// Compute the second derivatives for a natural cubic spline.
///
/// A natural cubic spline has second derivative = 0 at both endpoints.
/// The system of equations is solved using the Thomas algorithm (tridiagonal
/// matrix solver) in O(n) time.
fn natural_cubic_spline_seconds(
  xs : Array[Double],
  ys : Array[Double],
) -> Array[Double] {
  let n = xs.length()
  if n <= 1 {
    return Array::make(n, 0.0)
  }
  if n == 2 {
    return [0.0, 0.0]
  }
  // Set up the tridiagonal system for natural spline
  // h[i] = xs[i+1] - xs[i]
  let h : Array[Double] = Array::make(n - 1, 0.0)
  for i = 0; i < n - 1; i = i + 1 {
    h[i] = xs[i + 1] - xs[i]
  }
  // alpha[i] = 3/h[i] * (ys[i+1] - ys[i]) - 3/h[i-1] * (ys[i] - ys[i-1])
  // for i = 1..n-2
  let alpha : Array[Double] = Array::make(n, 0.0)
  for i = 1; i < n - 1; i = i + 1 {
    alpha[i] = 3.0 / h[i] * (ys[i + 1] - ys[i]) -
      3.0 / h[i - 1] * (ys[i] - ys[i - 1])
  }
  // Thomas algorithm: solve tridiagonal system
  // l[i], mu[i], z[i]
  let l : Array[Double] = Array::make(n, 0.0)
  let mu : Array[Double] = Array::make(n, 0.0)
  let z : Array[Double] = Array::make(n, 0.0)
  l[0] = 1.0
  mu[0] = 0.0
  z[0] = 0.0
  for i = 1; i < n - 1; i = i + 1 {
    l[i] = 2.0 * (xs[i + 1] - xs[i - 1]) - h[i - 1] * mu[i - 1]
    mu[i] = h[i] / l[i]
    z[i] = (alpha[i] - h[i - 1] * z[i - 1]) / l[i]
  }
  l[n - 1] = 1.0
  z[n - 1] = 0.0
  let c : Array[Double] = Array::make(n, 0.0)
  c[n - 1] = 0.0
  let mut j = n - 2
  while j >= 0 {
    c[j] = z[j] - mu[j] * c[j + 1]
    j = j - 1
  }
  c
}

// ---------------------------------------------------------------------------
// Interpolation
// ---------------------------------------------------------------------------

///|
/// Find the index `i` such that `tenors[i] <= t < tenors[i+1]`.
/// Returns -1 if `t < tenors[0]`, or `n-1` if `t >= tenors[n-1]`.
fn find_segment(tenors : Array[Double], t : Double) -> Int {
  let n = tenors.length()
  if n == 0 || t < tenors[0] {
    return -1
  }
  if t >= tenors[n - 1] {
    return n - 1
  }
  // Binary search
  let mut lo = 0
  let mut hi = n - 1
  while hi - lo > 1 {
    let mid = (lo + hi) / 2
    if tenors[mid] <= t {
      lo = mid
    } else {
      hi = mid
    }
  }
  lo
}

///|
/// Interpolate the zero rate at time `t`.
///
/// For `t` before the first tenor, the first zero rate is returned (flat
/// extrapolation). For `t` after the last tenor, the last zero rate is
/// returned.
pub fn yield_curve_zero_rate(curve : YieldCurve, t : Double) -> Double {
  let n = curve.tenors.length()
  if n == 0 {
    return 0.0
  }
  if t <= curve.tenors[0] {
    return curve.zero_rates[0]
  }
  if t >= curve.tenors[n - 1] {
    return curve.zero_rates[n - 1]
  }
  let i = find_segment(curve.tenors, t)
  if i < 0 {
    return curve.zero_rates[0]
  }
  match curve.interp {
    Linear => {
      let t0 = curve.tenors[i]
      let t1 = curve.tenors[i + 1]
      let r0 = curve.zero_rates[i]
      let r1 = curve.zero_rates[i + 1]
      // Linear interpolation: r = r0 + (r1 - r0) * (t - t0) / (t1 - t0)
      r0 + (r1 - r0) * (t - t0) / (t1 - t0)
    }
    LogLinear => {
      // Log-linear interpolation of discount factors:
      // df(t) = df0^((t1-t)/(t1-t0)) * df1^((t-t0)/(t1-t0))
      // Since df = exp(-r*t), we have:
      // -r(t)*t = w0 * (-r0*t0) + w1 * (-r1*t1)
      // r(t) = (w0 * r0 * t0 + w1 * r1 * t1) / t
      let t0 = curve.tenors[i]
      let t1 = curve.tenors[i + 1]
      let r0 = curve.zero_rates[i]
      let r1 = curve.zero_rates[i + 1]
      let w0 = (t1 - t) / (t1 - t0)
      let w1 = (t - t0) / (t1 - t0)
      (w0 * r0 * t0 + w1 * r1 * t1) / t
    }
    CubicSpline => {
      let t0 = curve.tenors[i]
      let t1 = curve.tenors[i + 1]
      let r0 = curve.zero_rates[i]
      let r1 = curve.zero_rates[i + 1]
      let c0 = curve.spline_seconds[i]
      let c1 = curve.spline_seconds[i + 1]
      let h = t1 - t0
      let a = (t1 - t) / h
      let b = (t - t0) / h
      a * r0 +
      b * r1 +
      ((a * a - 1.0) * a * c0 + (b * b - 1.0) * b * c1) * (h * h) / 6.0
    }
  }
}

///|
/// Compute the discount factor at time `t`.
///
/// `df(t) = exp(-r(t) · t)` where `r(t)` is the interpolated zero rate.
pub fn yield_curve_discount_factor(curve : YieldCurve, t : Double) -> Double {
  if t <= 0.0 {
    return 1.0
  }
  let r = yield_curve_zero_rate(curve, t)
  @math.exp(-r * t)
}

///|
/// Compute the **instantaneous forward rate** at time `t`.
///
/// `f(t) = r(t) + t · dr/dt`
///
/// For linear interpolation, `dr/dt` is the slope of the segment.
/// For log-linear, `f(t) = (w0·r0·t0 + w1·r1·t1) / t² · t0 + ...` (simplified).
/// For cubic spline, the derivative is computed analytically.
pub fn yield_curve_forward_rate(curve : YieldCurve, t : Double) -> Double {
  let n = curve.tenors.length()
  if n == 0 || t <= 0.0 {
    return 0.0
  }
  // For flat extrapolation regions, forward = zero rate
  if t <= curve.tenors[0] {
    return curve.zero_rates[0]
  }
  if t >= curve.tenors[n - 1] {
    return curve.zero_rates[n - 1]
  }
  let i = find_segment(curve.tenors, t)
  if i < 0 {
    return curve.zero_rates[0]
  }
  let r = yield_curve_zero_rate(curve, t)
  match curve.interp {
    Linear => {
      let t0 = curve.tenors[i]
      let t1 = curve.tenors[i + 1]
      let r0 = curve.zero_rates[i]
      let r1 = curve.zero_rates[i + 1]
      let slope = (r1 - r0) / (t1 - t0)
      r + t * slope
    }
    LogLinear => {
      // r(t) = (w0 * r0 * t0 + w1 * r1 * t1) / t
      // where w0 = (t1-t)/(t1-t0), w1 = (t-t0)/(t1-t0)
      // f(t) = r(t) + t * dr/dt
      // dr/dt = d/dt [(w0 * r0 * t0 + w1 * r1 * t1) / t]
      // This is complex; use numerical differentiation
      let eps = 1.0e-6
      let r_plus = yield_curve_zero_rate(curve, t + eps)
      let r_minus = yield_curve_zero_rate(curve, t - eps)
      let dr_dt = (r_plus - r_minus) / (2.0 * eps)
      r + t * dr_dt
    }
    CubicSpline => {
      // Spline derivative at t
      let t0 = curve.tenors[i]
      let t1 = curve.tenors[i + 1]
      let r0 = curve.zero_rates[i]
      let r1 = curve.zero_rates[i + 1]
      let c0 = curve.spline_seconds[i]
      let c1 = curve.spline_seconds[i + 1]
      let h = t1 - t0
      let a = (t1 - t) / h
      let b = (t - t0) / h
      // dr/dt = (r1 - r0)/h - ((3a²-1)*c0 - (3b²-1)*c1) * h / 6
      let dr_dt = (r1 - r0) / h -
        ((3.0 * a * a - 1.0) * c0 - (3.0 * b * b - 1.0) * c1) * h / 6.0
      r + t * dr_dt
    }
  }
}

///|
/// Compute the **simple forward rate** between times `t1` and `t2`
/// (continuously compounded).
///
/// `f(t1, t2) = (r(t2) · t2 - r(t1) · t1) / (t2 - t1)`
pub fn yield_curve_forward_rate_simple(
  curve : YieldCurve,
  t1 : Double,
  t2 : Double,
) -> Double {
  if t2 <= t1 {
    return 0.0
  }
  let r1 = yield_curve_zero_rate(curve, t1)
  let r2 = yield_curve_zero_rate(curve, t2)
  (r2 * t2 - r1 * t1) / (t2 - t1)
}

// ---------------------------------------------------------------------------
// Accessors
// ---------------------------------------------------------------------------

///|
/// Return the number of tenor points in the curve.
pub fn yield_curve_size(curve : YieldCurve) -> Int {
  curve.tenors.length()
}

///|
/// Return the tenor at index `i`.
pub fn yield_curve_tenor(curve : YieldCurve, i : Int) -> Double {
  curve.tenors[i]
}

///|
/// Return the zero rate at index `i`.
pub fn yield_curve_zero_rate_at(curve : YieldCurve, i : Int) -> Double {
  curve.zero_rates[i]
}

///|
/// Return the interpolation method.
pub fn yield_curve_method(curve : YieldCurve) -> InterpMethod {
  curve.interp
}

// ---------------------------------------------------------------------------
// Bootstrapping from market instruments
// ---------------------------------------------------------------------------

///|
/// Bootstrap zero rates from zero-coupon bond prices.
///
/// Each instrument is a (maturity, price) pair where price is the present
/// value of 1 paid at maturity. The zero rate is:
/// `r = -ln(price) / maturity`
pub fn bootstrap_from_zero_coupon_bonds(
  maturities : Array[Double],
  prices : Array[Double],
) -> YieldCurve {
  let n = maturities.length()
  let zero_rates : Array[Double] = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    if maturities[i] > 0.0 && prices[i] > 0.0 {
      zero_rates[i] = -@math.ln(prices[i]) / maturities[i]
    } else {
      zero_rates[i] = 0.0
    }
  }
  yield_curve_linear(maturities, zero_rates)
}

///|
/// Bootstrap zero rates from coupon-bearing bond prices.
///
/// Given a set of bonds with known maturities, coupon rates, and prices,
/// sequentially extract the zero rate at each maturity by discounting
/// all previous cash flows using already-bootstrapped rates.
///
/// Each bond pays `coupon_rate` annually and returns principal at maturity.
pub fn bootstrap_from_coupon_bonds(
  maturities : Array[Double],
  coupon_rates : Array[Double],
  prices : Array[Double],
) -> YieldCurve {
  let n = maturities.length()
  let zero_rates : Array[Double] = Array::make(n, 0.0)
  let bootstrapped_tenors : Array[Double] = []
  let bootstrapped_rates : Array[Double] = []
  for i = 0; i < n; i = i + 1 {
    let t = maturities[i]
    let coupon = coupon_rates[i]
    let price = prices[i]
    // Build a temporary curve from already-bootstrapped rates
    let mut pv = 0.0
    // Discount each annual coupon using bootstrapped rates
    let mut year = 1.0
    while year < t {
      let r = if bootstrapped_tenors.length() > 0 {
        interpolate_from_sorted(bootstrapped_tenors, bootstrapped_rates, year)
      } else {
        0.0
      }
      pv = pv + coupon * @math.exp(-r * year)
      year = year + 1.0
    }
    // The final cash flow is coupon + principal (assume principal = 1.0)
    let final_cf = coupon + 1.0
    // price = pv + final_cf * exp(-r_i * t)
    // r_i = -ln((price - pv) / final_cf) / t
    let remaining = price - pv
    if remaining > 0.0 && final_cf > 0.0 && t > 0.0 {
      zero_rates[i] = -@math.ln(remaining / final_cf) / t
    } else {
      zero_rates[i] = 0.0
    }
    bootstrapped_tenors.push(t)
    bootstrapped_rates.push(zero_rates[i])
  }
  yield_curve_linear(maturities, zero_rates)
}

///|
/// Linear interpolation from sorted arrays (helper for bootstrapping).
fn interpolate_from_sorted(
  xs : Array[Double],
  ys : Array[Double],
  x : Double,
) -> Double {
  let n = xs.length()
  if n == 0 {
    return 0.0
  }
  if x <= xs[0] {
    return ys[0]
  }
  if x >= xs[n - 1] {
    return ys[n - 1]
  }
  let i = find_segment(xs, x)
  if i < 0 {
    return ys[0]
  }
  let x0 = xs[i]
  let x1 = xs[i + 1]
  let y0 = ys[i]
  let y1 = ys[i + 1]
  y0 + (y1 - y0) * (x - x0) / (x1 - x0)
}

// ---------------------------------------------------------------------------
// Nelson-Siegel model
// ---------------------------------------------------------------------------

///|
/// Nelson-Siegel model parameters.
pub struct NSParams {
  /// Level (long-term rate)
  beta1 : Double
  /// Slope (short-term component)
  beta2 : Double
  /// Curvature (medium-term component)
  beta3 : Double
  /// Decay parameter (time scale)
  lambda1 : Double
}

///|
/// Construct Nelson-Siegel model parameters.
pub fn ns_params(
  beta1 : Double,
  beta2 : Double,
  beta3 : Double,
  lambda1 : Double,
) -> NSParams {
  { beta1, beta2, beta3, lambda1, }
}

///|
/// Evaluate the Nelson-Siegel yield at maturity `tau`.
///
/// `y(τ) = β₁ + β₂ · [(1 - e^(-τ/λ)) / (τ/λ)] + β₃ · [(1 - e^(-τ/λ)) / (τ/λ) - e^(-τ/λ)]`
///
/// For `τ → 0`: `y → β₁ + β₂`
/// For `τ → ∞`: `y → β₁`
pub fn nelson_siegel_eval(params : NSParams, tau : Double) -> Double {
  if tau <= 0.0 {
    return params.beta1 + params.beta2
  }
  let lam = params.lambda1
  if lam <= 0.0 {
    return params.beta1
  }
  let x = tau / lam
  let exp_neg = @math.exp(-x)
  let factor1 = (1.0 - exp_neg) / x
  let factor2 = factor1 - exp_neg
  params.beta1 + params.beta2 * factor1 + params.beta3 * factor2
}

///|
/// Create a yield curve from Nelson-Siegel parameters.
///
/// Generates a dense grid of tenors (0.25 to 30 years) and evaluates the
/// NS model at each point.
pub fn nelson_siegel_curve(params : NSParams) -> YieldCurve {
  let tenors : Array[Double] = []
  let rates : Array[Double] = []
  // Generate tenors: 0.25, 0.5, 1, 2, 3, 5, 7, 10, 15, 20, 30
  let grid = [0.25, 0.5, 1.0, 2.0, 3.0, 5.0, 7.0, 10.0, 15.0, 20.0, 30.0]
  for i = 0; i < grid.length(); i = i + 1 {
    tenors.push(grid[i])
    rates.push(nelson_siegel_eval(params, grid[i]))
  }
  yield_curve_cubic_spline(tenors, rates)
}

///|
/// Fit Nelson-Siegel parameters to observed market rates using a simple
/// grid search over λ (decay parameter) and ordinary least squares for
/// β parameters.
///
/// This is a practical approach: for each candidate λ, the NS model is
/// linear in β₁, β₂, β₃, so we can solve the OLS system analytically.
/// The best λ is selected by minimizing the sum of squared residuals.
pub fn nelson_siegel_fit(
  tenors : Array[Double],
  rates : Array[Double],
) -> NSParams {
  let n = tenors.length()
  if n == 0 {
    return { beta1: 0.0, beta2: 0.0, beta3: 0.0, lambda1: 1.0, }
  }
  // Grid search over lambda
  let mut best_lambda = 1.0
  let mut best_sse = 1.0e300
  let mut best_betas = (0.0, 0.0, 0.0)
  // Try lambda values from 0.1 to 10.0
  let lam_grid = [
    0.1, 0.2, 0.3, 0.5, 0.7, 1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0, 7.0, 10.0,
  ]
  for li = 0; li < lam_grid.length(); li = li + 1 {
    let lam = lam_grid[li]
    // Build the design matrix columns: [1, factor1(tau_i/lam), factor2(tau_i/lam)]
    // Solve normal equations: A^T A beta = A^T y
    let mut a11 = 0.0
    let mut a12 = 0.0
    let mut a13 = 0.0
    let mut a22 = 0.0
    let mut a23 = 0.0
    let mut a33 = 0.0
    let mut b1 = 0.0
    let mut b2 = 0.0
    let mut b3 = 0.0
    for i = 0; i < n; i = i + 1 {
      let tau = tenors[i]
      let y = rates[i]
      let x = tau / lam
      let exp_neg = @math.exp(-x)
      let f1 = if x > 0.0 { (1.0 - exp_neg) / x } else { 1.0 }
      let f2 = f1 - exp_neg
      a11 = a11 + 1.0
      a12 = a12 + f1
      a13 = a13 + f2
      a22 = a22 + f1 * f1
      a23 = a23 + f1 * f2
      a33 = a33 + f2 * f2
      b1 = b1 + y
      b2 = b2 + y * f1
      b3 = b3 + y * f2
    }
    // Solve 3x3 system using Cramer's rule
    let det = a11 * (a22 * a33 - a23 * a23) -
      a12 * (a12 * a33 - a23 * a13) +
      a13 * (a12 * a23 - a22 * a13)
    if det.abs() < 1.0e-15 {
      continue
    }
    let beta1 = (
        b1 * (a22 * a33 - a23 * a23) -
        a12 * (b2 * a33 - a23 * b3) +
        a13 * (b2 * a23 - a22 * b3)
      ) /
      det
    let beta2 = (
        a11 * (b2 * a33 - a23 * b3) -
        b1 * (a12 * a33 - a23 * a13) +
        a13 * (a12 * b3 - b2 * a13)
      ) /
      det
    let beta3 = (
        a11 * (a22 * b3 - b2 * a23) -
        a12 * (a12 * b3 - b2 * a13) +
        b1 * (a12 * a23 - a22 * a13)
      ) /
      det
    // Compute SSE
    let mut sse = 0.0
    for i = 0; i < n; i = i + 1 {
      let tau = tenors[i]
      let pred = nelson_siegel_eval({ beta1, beta2, beta3, lambda1: lam, }, tau)
      let resid = rates[i] - pred
      sse = sse + resid * resid
    }
    if sse < best_sse {
      best_sse = sse
      best_lambda = lam
      best_betas = (beta1, beta2, beta3)
    }
  }
  {
    beta1: best_betas.0,
    beta2: best_betas.1,
    beta3: best_betas.2,
    lambda1: best_lambda,
  }
}

// ---------------------------------------------------------------------------
// Nelson-Siegel-Svensson model (6 parameters)
// ---------------------------------------------------------------------------

///|
/// Nelson-Siegel-Svensson model parameters.
pub struct NSSParams {
  beta1 : Double
  beta2 : Double
  beta3 : Double
  beta4 : Double
  lambda1 : Double
  lambda2 : Double
}

///|
/// Construct Nelson-Siegel-Svensson model parameters.
pub fn nss_params(
  beta1 : Double,
  beta2 : Double,
  beta3 : Double,
  beta4 : Double,
  lambda1 : Double,
  lambda2 : Double,
) -> NSSParams {
  { beta1, beta2, beta3, beta4, lambda1, lambda2, }
}

///|
/// Evaluate the Nelson-Siegel-Svensson yield at maturity `tau`.
///
/// `y(τ) = β₁ + β₂·f₁(τ,λ₁) + β₃·g₁(τ,λ₁) + β₄·g₂(τ,λ₂)`
///
/// where `f₁ = (1-e^{-τ/λ})/(τ/λ)` and `g = f₁ - e^{-τ/λ}`.
pub fn nss_eval(params : NSSParams, tau : Double) -> Double {
  if tau <= 0.0 {
    return params.beta1 + params.beta2
  }
  let x1 = tau / params.lambda1
  let exp1 = @math.exp(-x1)
  let f1 = (1.0 - exp1) / x1
  let g1 = f1 - exp1
  let x2 = tau / params.lambda2
  let exp2 = @math.exp(-x2)
  let f2 = (1.0 - exp2) / x2
  let g2 = f2 - exp2
  params.beta1 + params.beta2 * f1 + params.beta3 * g1 + params.beta4 * g2
}

///|
/// Create a yield curve from NSS parameters.
pub fn nss_curve(params : NSSParams) -> YieldCurve {
  let grid = [0.25, 0.5, 1.0, 2.0, 3.0, 5.0, 7.0, 10.0, 15.0, 20.0, 30.0]
  let tenors : Array[Double] = []
  let rates : Array[Double] = []
  for i = 0; i < grid.length(); i = i + 1 {
    tenors.push(grid[i])
    rates.push(nss_eval(params, grid[i]))
  }
  yield_curve_cubic_spline(tenors, rates)
}
