///|
/// Risk Management — VaR, CVaR, and Stress Testing.
///
/// Value at Risk (VaR) and Conditional Value at Risk (CVaR, also known
/// as Expected Shortfall) are the most widely used risk measures in
/// financial risk management. They quantify the potential loss of a
/// portfolio over a given time horizon at a specified confidence level.
///
/// ## VaR Methods
///
/// - **Historical VaR**: Uses empirical distribution of returns
/// - **Parametric (Variance-Covariance) VaR**: Assumes normal distribution
/// - **Cornish-Fisher VaR**: Adjusts for skewness and kurtosis
///
/// ## CVaR (Expected Shortfall)
///
/// CVaR is the expected loss given that the loss exceeds the VaR
/// threshold. It is a coherent risk measure (subadditive), unlike VaR.
///
/// ## References
///
/// - P. Jorion. "Value at Risk." 3rd ed., McGraw-Hill, 2007.
/// - R. T. Rockafellar, S. Uryasev. "Optimization of Conditional
///   Value-at-Risk." Journal of Risk, 2000.
/// - Basel Committee on Banking Supervision. "Minimum Capital Requirements
///   for Market Risk." BCBS 457, 2019.
///
/// `proof-enabled` is `false`; correctness is backed by test vectors.

// @math.sqrt is unavailable in MoonBit stdlib; use Double::sqrt method.
fn sqrt(x : Double) -> Double {
  x.sqrt()
}

// ---------------------------------------------------------------------------
// Normal distribution helpers
// ---------------------------------------------------------------------------

///|
/// Standard normal CDF using Abramowitz-Stegun approximation.
pub fn normal_cdf(x : Double) -> Double {
  if x < -10.0 {
    return 0.0
  }
  if x > 10.0 {
    return 1.0
  }
  0.5 * (1.0 + erf(x / 1.4142135623730951))
}

///|
/// Inverse standard normal CDF using the Beasley-Springer-Moro algorithm.
/// Accurate to ~1e-9 for the central region.
fn normal_inv_cdf(p : Double) -> Double {
  if p <= 0.0 {
    return -37.0
  }
  if p >= 1.0 {
    return 37.0
  }
  // Beasley-Springer-Moro approximation
  let a : FixedArray[Double] = FixedArray::make(8, 0.0)
  a[0] = -3.969683028665376e+01
  a[1] = 2.209460984245205e+02
  a[2] = -2.759285104469687e+02
  a[3] = 1.383577518672690e+02
  a[4] = -3.066479806614716e+01
  a[5] = 2.506628277459239e+00
  let b : FixedArray[Double] = FixedArray::make(8, 0.0)
  b[0] = -5.447609879822406e+01
  b[1] = 1.615858368580409e+02
  b[2] = -1.556989798598866e+02
  b[3] = 6.680131188771972e+01
  b[4] = -1.328068155288572e+01
  let c : FixedArray[Double] = FixedArray::make(8, 0.0)
  c[0] = -7.784894002430293e-03
  c[1] = -3.223964580411365e-01
  c[2] = -2.400758277161838e+00
  c[3] = -2.549732539343734e+00
  c[4] = 4.374664141464968e+00
  c[5] = 2.938163982698783e+00
  let d : FixedArray[Double] = FixedArray::make(8, 0.0)
  d[0] = 7.784695709041462e-03
  d[1] = 3.224671290700398e-01
  d[2] = 2.445134137142996e+00
  d[3] = 3.754408661907416e+00
  let p_low = 0.02425
  let p_high = 1.0 - p_low
  if p < p_low {
    let q = sqrt(-2.0 * @math.ln(p))
    let num = ((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q +
      c[5]
    let den = (((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1.0
    return num / den
  }
  if p <= p_high {
    let q = p - 0.5
    let r = q * q
    let num = (
        ((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]
      ) *
      q
    let den = ((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1.0
    return num / den
  }
  let q = sqrt(-2.0 * @math.ln(1.0 - p))
  let num = ((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]
  let den = (((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1.0
  -(num / den)
}

///|
/// Error function (Abramowitz-Stegun 7.1.26).
fn erf(x : Double) -> Double {
  let sign = if x < 0.0 { -1.0 } else { 1.0 }
  let ax = if x < 0.0 { -x } else { x }
  let a1 = 0.254829592
  let a2 = -0.284496736
  let a3 = 1.421413741
  let a4 = -1.453152027
  let a5 = 1.061405429
  let p = 0.3275911
  let t = 1.0 / (1.0 + p * ax)
  let y = 1.0 -
    ((((a5 * t + a4) * t + a3) * t + a2) * t + a1) * t * @math.exp(-ax * ax)
  sign * y
}

// ---------------------------------------------------------------------------
// Statistical helpers
// ---------------------------------------------------------------------------

///|
/// Compute the mean of an array of returns.
fn mean(returns : Array[Double]) -> Double {
  if returns.length() == 0 {
    return 0.0
  }
  let mut sum = 0.0
  for i = 0; i < returns.length(); i = i + 1 {
    sum = sum + returns[i]
  }
  sum / returns.length().to_double()
}

///|
/// Compute the standard deviation of an array of returns (sample, n-1).
fn std_dev(returns : Array[Double]) -> Double {
  let n = returns.length()
  if n < 2 {
    return 0.0
  }
  let m = mean(returns)
  let mut sq_sum = 0.0
  for i = 0; i < n; i = i + 1 {
    let diff = returns[i] - m
    sq_sum = sq_sum + diff * diff
  }
  sqrt(sq_sum / (n - 1).to_double())
}

///|
/// Compute skewness of returns.
fn skewness(returns : Array[Double]) -> Double {
  let n = returns.length()
  if n < 3 {
    return 0.0
  }
  let m = mean(returns)
  let s = std_dev(returns)
  if s == 0.0 {
    return 0.0
  }
  let mut sum = 0.0
  for i = 0; i < n; i = i + 1 {
    let z = (returns[i] - m) / s
    sum = sum + z * z * z
  }
  n.to_double() / ((n - 1) * (n - 2)).to_double() * sum
}

///|
/// Compute excess kurtosis of returns.
fn kurtosis(returns : Array[Double]) -> Double {
  let n = returns.length()
  if n < 4 {
    return 0.0
  }
  let m = mean(returns)
  let s = std_dev(returns)
  if s == 0.0 {
    return 0.0
  }
  let mut sum = 0.0
  for i = 0; i < n; i = i + 1 {
    let z = (returns[i] - m) / s
    sum = sum + z * z * z * z
  }
  let k = n.to_double() *
    (n + 1).to_double() /
    ((n - 1) * (n - 2) * (n - 3)).to_double() *
    sum -
    3.0 *
    (n - 1).to_double() *
    (n - 1).to_double() /
    ((n - 2) * (n - 3)).to_double()
  k
}

///|
/// Sort an array (simple insertion sort for moderate sizes).
fn sort_desc(arr : Array[Double]) -> Array[Double] {
  let result = Array::copy(arr)
  let n = result.length()
  for i = 1; i < n; i = i + 1 {
    let key = result[i]
    let mut j = i - 1
    while j >= 0 && result[j] < key {
      result[j + 1] = result[j]
      j = j - 1
    }
    result[j + 1] = key
  }
  result
}

// ---------------------------------------------------------------------------
// Parametric (Variance-Covariance) VaR
// ---------------------------------------------------------------------------

///|
/// Parametric VaR assuming normally distributed returns.
///
/// - `mean`: Expected return (period).
/// - `std_dev`: Standard deviation of returns (period).
/// - `confidence`: Confidence level (e.g. 0.95, 0.99).
/// - `portfolio_value`: Current portfolio value.
///
/// Returns the VaR as a positive number representing potential loss.
pub fn parametric_var(
  mean : Double,
  std_dev : Double,
  confidence : Double,
  portfolio_value : Double,
) -> Double {
  let z = normal_inv_cdf(1.0 - confidence)
  let var_return = -(mean + z * std_dev)
  if var_return > 0.0 {
    portfolio_value * var_return
  } else {
    0.0
  }
}

///|
/// Parametric VaR with time scaling (square root of time rule).
///
/// - `daily_mean`: Daily expected return.
/// - `daily_std`: Daily standard deviation.
/// - `confidence`: Confidence level (e.g. 0.99).
/// - `horizon_days`: Time horizon in trading days.
/// - `portfolio_value`: Current portfolio value.
pub fn parametric_var_scaled(
  daily_mean : Double,
  daily_std : Double,
  confidence : Double,
  horizon_days : Int,
  portfolio_value : Double,
) -> Double {
  let z = normal_inv_cdf(1.0 - confidence)
  let scaled_mean = daily_mean * horizon_days.to_double()
  let scaled_std = daily_std * sqrt(horizon_days.to_double())
  let var_return = -(scaled_mean + z * scaled_std)
  if var_return > 0.0 {
    portfolio_value * var_return
  } else {
    0.0
  }
}

// ---------------------------------------------------------------------------
// Historical VaR
// ---------------------------------------------------------------------------

///|
/// Historical VaR using the empirical distribution of returns.
///
/// - `returns`: Array of historical returns (e.g. daily returns).
/// - `confidence`: Confidence level (e.g. 0.95, 0.99).
/// - `portfolio_value`: Current portfolio value.
///
/// Returns the VaR as a positive number.
pub fn historical_var(
  returns : Array[Double],
  confidence : Double,
  portfolio_value : Double,
) -> Double {
  let n = returns.length()
  if n == 0 {
    return 0.0
  }
  let sorted = sort_desc(returns)
  // The VaR is the loss at the (1-confidence) quantile.
  let index = ((1.0 - confidence) * n.to_double()).to_int()
  let idx = if index >= n { n - 1 } else if index < 0 { 0 } else { index }
  // sorted is descending, so the worst returns are at the end.
  // The (1-c) quantile is at position n - idx from the start.
  let worst_idx = if idx == 0 { n - 1 } else { n - idx }
  let var_return = -sorted[worst_idx]
  if var_return > 0.0 {
    portfolio_value * var_return
  } else {
    0.0
  }
}

// ---------------------------------------------------------------------------
// Cornish-Fisher VaR
// ---------------------------------------------------------------------------

///|
/// Cornish-Fisher VaR adjusting for skewness and kurtosis.
///
/// The Cornish-Fisher expansion modifies the z-score to account for
/// non-normality in the return distribution:
///
/// `z_cf = z + (z²-1)/6 · S + (z³-3z)/24 · (K-3) - (2z³-5z)/36 · S²`
///
/// where S is skewness and K is kurtosis.
pub fn cornish_fisher_var(
  returns : Array[Double],
  confidence : Double,
  portfolio_value : Double,
) -> Double {
  let n = returns.length()
  if n < 4 {
    return historical_var(returns, confidence, portfolio_value)
  }
  let m = mean(returns)
  let s = std_dev(returns)
  let sk = skewness(returns)
  let ku = kurtosis(returns)
  let z = normal_inv_cdf(1.0 - confidence)
  // Cornish-Fisher expansion
  let z2 = z * z
  let z3 = z2 * z
  let cf_adj = (z2 - 1.0) * sk / 6.0 +
    (z3 - 3.0 * z) * ku / 24.0 -
    (2.0 * z3 - 5.0 * z) * sk * sk / 36.0
  let z_cf = z + cf_adj
  let var_return = -(m + z_cf * s)
  if var_return > 0.0 {
    portfolio_value * var_return
  } else {
    0.0
  }
}

// ---------------------------------------------------------------------------
// CVaR (Expected Shortfall)
// ---------------------------------------------------------------------------

///|
/// Parametric CVaR (Expected Shortfall) assuming normal distribution.
///
/// CVaR_α = -mean + σ · φ(z_α) / (1 - α)
///
/// where z_α is the (1-α) quantile and φ is the normal PDF.
pub fn parametric_cvar(
  mean : Double,
  std_dev : Double,
  confidence : Double,
  portfolio_value : Double,
) -> Double {
  let z = normal_inv_cdf(1.0 - confidence)
  let phi_z = 0.3989422804014327 * @math.exp(-0.5 * z * z)
  let es_return = -(mean - std_dev * phi_z / (1.0 - confidence))
  if es_return > 0.0 {
    portfolio_value * es_return
  } else {
    0.0
  }
}

///|
/// Historical CVaR (Expected Shortfall).
///
/// Computes the average loss beyond the VaR threshold.
pub fn historical_cvar(
  returns : Array[Double],
  confidence : Double,
  portfolio_value : Double,
) -> Double {
  let n = returns.length()
  if n == 0 {
    return 0.0
  }
  let sorted = sort_desc(returns)
  let num_tail = ((1.0 - confidence) * n.to_double()).to_int()
  let tail_count = if num_tail < 1 {
    1
  } else if num_tail > n {
    n
  } else {
    num_tail
  }
  // Average the worst tail_count returns (at the end of descending sorted array)
  let mut sum = 0.0
  for i = 0; i < tail_count; i = i + 1 {
    sum = sum + sorted[n - 1 - i]
  }
  let avg_return = -sum / tail_count.to_double()
  if avg_return > 0.0 {
    portfolio_value * avg_return
  } else {
    0.0
  }
}

// ---------------------------------------------------------------------------
// Stress Testing
// ---------------------------------------------------------------------------

///|
/// Stress test: apply a scenario shock to portfolio.
///
/// - `positions`: Array of (weight, return_shock) pairs.
/// - `portfolio_value`: Current portfolio value.
///
/// Returns the portfolio loss under the stress scenario.
pub fn stress_test_loss(
  positions : Array[(Double, Double)],
  portfolio_value : Double,
) -> Double {
  let mut total_shock = 0.0
  for i = 0; i < positions.length(); i = i + 1 {
    let (weight, shock) = positions[i]
    total_shock = total_shock + weight * shock
  }
  let loss = -total_shock * portfolio_value
  if loss > 0.0 {
    loss
  } else {
    0.0
  }
}

///|
/// Monte Carlo VaR using simulated returns.
///
/// - `simulated_returns`: Pre-generated simulated returns (e.g. from
///   a Monte Carlo simulation).
/// - `confidence`: Confidence level.
/// - `portfolio_value`: Current portfolio value.
pub fn monte_carlo_var(
  simulated_returns : Array[Double],
  confidence : Double,
  portfolio_value : Double,
) -> Double {
  historical_var(simulated_returns, confidence, portfolio_value)
}

///|
/// Monte Carlo CVaR using simulated returns.
pub fn monte_carlo_cvar(
  simulated_returns : Array[Double],
  confidence : Double,
  portfolio_value : Double,
) -> Double {
  historical_cvar(simulated_returns, confidence, portfolio_value)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "variance: parametric variance basic" {
  // 1-day 95% VaR with mean=0, std=0.01, portfolio=$1M
  let variance = parametric_var(0.0, 0.01, 0.95, 1_000_000.0)
  // z_0.05 ≈ -1.645, so VaR ≈ 1.645% * $1M ≈ $16,450
  assert_true(variance > 16000.0 && variance < 17000.0)
}

///|
test "variance: parametric variance 99%" {
  let var_95 = parametric_var(0.0, 0.01, 0.95, 1_000_000.0)
  let var_99 = parametric_var(0.0, 0.01, 0.99, 1_000_000.0)
  // 99% VaR should be larger than 95% VaR
  assert_true(var_99 > var_95)
}

///|
test "variance: time scaling" {
  let var_1d = parametric_var_scaled(0.0, 0.01, 0.99, 1, 1_000_000.0)
  let var_10d = parametric_var_scaled(0.0, 0.01, 0.99, 10, 1_000_000.0)
  // 10-day VaR ≈ √10 * 1-day VaR
  let expected_ratio = sqrt(10.0)
  let actual_ratio = var_10d / var_1d
  assert_true((actual_ratio - expected_ratio).abs() < 0.01)
}

///|
test "variance: historical variance" {
  let returns : Array[Double] = []
  for i = 0; i < 100; i = i + 1 {
    // Simulate: 95% of returns are 0, 5% are -0.05
    if i < 5 {
      returns.push(-0.05)
    } else {
      returns.push(0.0)
    }
  }
  let variance = historical_var(returns, 0.95, 1_000_000.0)
  // The 5th percentile should be -0.05
  assert_true((variance - 50000.0).abs() < 1000.0)
}

///|
test "variance: cvar >= variance" {
  let returns : Array[Double] = []
  for i = 0; i < 100; i = i + 1 {
    if i < 5 {
      returns.push(-0.05 - i.to_double() * 0.001)
    } else {
      returns.push(0.0)
    }
  }
  let variance = historical_var(returns, 0.95, 1_000_000.0)
  let cvar = historical_cvar(returns, 0.95, 1_000_000.0)
  // CVaR should be >= VaR
  assert_true(cvar >= variance)
}

///|
test "variance: parametric cvar > parametric variance" {
  let variance = parametric_var(0.0, 0.01, 0.99, 1_000_000.0)
  let cvar = parametric_cvar(0.0, 0.01, 0.99, 1_000_000.0)
  assert_true(cvar > variance)
}

///|
test "variance: stress test" {
  // 60% equity (shock -20%), 40% bonds (shock -5%)
  let positions : Array[(Double, Double)] = [(0.6, -0.20), (0.4, -0.05)]
  let loss = stress_test_loss(positions, 1_000_000.0)
  // 0.6 * 0.20 + 0.4 * 0.05 = 0.14 = $140,000
  assert_true((loss - 140000.0).abs() < 1.0)
}

///|
test "variance: cornish-fisher adjusts for skewness" {
  // Create negatively skewed returns
  let returns : Array[Double] = []
  for i = 0; i < 100; i = i + 1 {
    if i < 10 {
      returns.push(-0.03)
    } else {
      returns.push(0.005)
    }
  }
  let cf_var = cornish_fisher_var(returns, 0.95, 1_000_000.0)
  let hist_var = historical_var(returns, 0.95, 1_000_000.0)
  // Both should be positive
  assert_true(cf_var > 0.0)
  assert_true(hist_var > 0.0)
}

///|
test "variance: empty returns" {
  let empty : Array[Double] = []
  assert_true(historical_var(empty, 0.95, 1000.0) == 0.0)
  assert_true(historical_cvar(empty, 0.95, 1000.0) == 0.0)
}

///|
test "variance: variance with positive mean reduces risk" {
  let var_zero_mean = parametric_var(0.0, 0.01, 0.95, 1_000_000.0)
  let var_pos_mean = parametric_var(0.001, 0.01, 0.95, 1_000_000.0)
  assert_true(var_pos_mean < var_zero_mean)
}

///|
test "variance: monte carlo variance equals historical" {
  let returns : Array[Double] = []
  for i = 0; i < 200; i = i + 1 {
    returns.push(-0.01 + i.to_double() / 100.0)
  }
  let mc_var = monte_carlo_var(returns, 0.95, 1_000_000.0)
  let hist_var = historical_var(returns, 0.95, 1_000_000.0)
  assert_true((mc_var - hist_var).abs() < 0.001)
}
