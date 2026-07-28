/// Bootstrap Resampling — Non-parametric statistical inference.
///
/// The bootstrap (Efron, 1979) is a resampling technique for estimating
/// the sampling distribution of a statistic by repeatedly resampling with
/// replacement from the observed data. It makes no distributional
/// assumptions and is widely used when analytical formulas are unavailable
/// or unreliable (small samples, non-normal data, complex statistics).
///
/// ## Methods
///
/// - **Percentile interval**: the α/2 and 1−α/2 quantiles of the
///   bootstrap distribution. Simple and widely used; can be biased for
///   skewed distributions.
/// - **Basic interval**: flips the percentile bias by reflecting around
///   the point estimate. Better for symmetric statistics.
/// - **BCa interval** (bias-corrected and accelerated): adjusts for both
///   bias and skewness. This is the recommended default (Efron & Tibshirani
/// 1993, §14) and has second-order accuracy.
///
/// ## PRNG
///
/// Uses SplitMix64 (via `@utils.SplitMix64`) for reproducible resampling.
/// Callers should supply a non-deterministic seed when randomness matters.
///
/// ## Complexity
///
/// - Each resample: O(n) to draw + O(cost(statistic)) to evaluate.
/// - Total: O(B × (n + cost(statistic))) for B bootstrap replicates.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

///|
/// Local sqrt wrapper.
fn m_sqrt(x : Double) -> Double {
  x.sqrt()
}

///|
/// Resample `data` with replacement, writing into `out`.
/// Uses the PRNG to draw indices uniformly in `[0, n)`.
fn resample(rng : @utils.SplitMix64, data : Array[Double], out : Array[Double]) -> Unit {
  let n = data.length()
  for i = 0; i < n; i = i + 1 {
    let u = rng.next_double()
    let idx = (u * n.to_double()).to_int()
    let idx = if idx >= n { n - 1 } else { idx }
    out[i] = data[idx]
  }
}

///|
/// Compute the α-quantile of a sorted array.
/// Uses linear interpolation (same convention as `@descriptive.quantile`).
fn quantile_sorted(sorted : Array[Double], alpha : Double) -> Double {
  let n = sorted.length()
  if n == 0 {
    return @double.not_a_number
  }
  if n == 1 {
    return sorted[0]
  }
  let pos = alpha * (n - 1).to_double()
  let lo = pos.to_int()
  let hi = if lo + 1 < n { lo + 1 } else { lo }
  let frac = pos - lo.to_double()
  sorted[lo] * (1.0 - frac) + sorted[hi] * frac
}

///|
/// Compute the jackknife leave-one-out estimates for the acceleration
/// constant `a` used in BCa intervals.
///
/// Returns the acceleration constant:
/// `a = Σ(θ̄_jack − θ_{(i)})³ / [6 × (Σ(θ̄_jack − θ_{(i)})²)^{3/2}]`
///
/// `statistic` is applied to each leave-one-out subsample.
fn jackknife_acceleration(
  data : Array[Double],
  statistic : (Array[Double]) -> Double,
) -> Double {
  let n = data.length()
  if n < 3 {
    return 0.0
  }
  let jack_estimates : Array[Double] = Array::make(n, 0.0)
  let sub : Array[Double] = Array::make(n - 1, 0.0)
  for i = 0; i < n; i = i + 1 {
    // Build leave-one-out sample.
    let mut k = 0
    for j = 0; j < n; j = j + 1 {
      if j != i {
        sub[k] = data[j]
        k = k + 1
      }
    }
    jack_estimates[i] = statistic(sub)
  }
  // Mean of jackknife estimates.
  let mut sum = 0.0
  for i = 0; i < n; i = i + 1 {
    sum = sum + jack_estimates[i]
  }
  let mean_jack = sum / n.to_double()
  // Compute numerator and denominator.
  let mut num = 0.0
  let mut den = 0.0
  for i = 0; i < n; i = i + 1 {
    let diff = mean_jack - jack_estimates[i]
    let d2 = diff * diff
    let d3 = d2 * diff
    num = num + d3
    den = den + d2
  }
  if den == 0.0 {
    return 0.0
  }
  num / (6.0 * den * m_sqrt(den))
}

// ---------------------------------------------------------------------------
// Public API: Percentile bootstrap
// ---------------------------------------------------------------------------

///|
/// Bootstrap percentile confidence interval for an arbitrary statistic.
///
/// Resamples `data` B times with replacement, computes `statistic` on each
/// resample, and returns the `confidence`-level percentile interval
/// (α/2 and 1−α/2 quantiles of the bootstrap distribution).
///
/// Parameters:
/// - `data`: the original sample.
/// - `statistic`: function computing the statistic of interest.
/// - `confidence`: confidence level in `(0, 1)`, e.g. `0.95`.
/// - `seed`: PRNG seed for reproducibility.
/// - `n_bootstrap`: number of bootstrap resamples (B). Typical: 1000–10000.
///
/// Returns `(lower, upper)`. Returns `(NaN, NaN)` for invalid inputs.
pub fn percentile_ci(
  data : Array[Double],
  statistic : (Array[Double]) -> Double,
  confidence : Double,
  seed : UInt64,
  n_bootstrap : Int,
) -> (Double, Double) {
  let n = data.length()
  if n < 2 || n_bootstrap < 10 || confidence <= 0.0 || confidence >= 1.0 {
    return (@double.not_a_number, @double.not_a_number)
  }
  let rng = @utils.SplitMix64::new(seed)
  let resample_buf : Array[Double] = Array::make(n, 0.0)
  let estimates : Array[Double] = Array::make(n_bootstrap, 0.0)
  for b = 0; b < n_bootstrap; b = b + 1 {
    resample(rng, data, resample_buf)
    estimates[b] = statistic(resample_buf)
  }
  // Sort to compute quantiles.
  estimates.sort_by(fn(a, b) {
    if a < b {
      -1
    } else if a > b {
      1
    } else {
      0
    }
  })
  let alpha = 1.0 - confidence
  let lo = quantile_sorted(estimates, alpha / 2.0)
  let hi = quantile_sorted(estimates, 1.0 - alpha / 2.0)
  (lo, hi)
}

///|
/// Bootstrap percentile confidence interval for the mean.
///
/// Convenience wrapper around `percentile_ci` with `statistic = @descriptive.mean`.
pub fn mean_percentile_ci(
  data : Array[Double],
  confidence : Double,
  seed : UInt64,
  n_bootstrap : Int,
) -> (Double, Double) {
  percentile_ci(data, fn(d) { @descriptive.mean(d) }, confidence, seed, n_bootstrap)
}

///|
/// Bootstrap percentile confidence interval for the median.
///
/// Convenience wrapper around `percentile_ci` with `statistic = @descriptive.median`.
pub fn median_percentile_ci(
  data : Array[Double],
  confidence : Double,
  seed : UInt64,
  n_bootstrap : Int,
) -> (Double, Double) {
  percentile_ci(data, fn(d) { @descriptive.median(d) }, confidence, seed, n_bootstrap)
}

// ---------------------------------------------------------------------------
// Public API: BCa (bias-corrected and accelerated) bootstrap
// ---------------------------------------------------------------------------

///|
/// BCa (bias-corrected and accelerated) bootstrap confidence interval.
///
/// This is the recommended bootstrap CI method (Efron & Tibshirani 1993,
/// §14.3). It adjusts the percentile interval for both bias (via the
/// proportion of bootstrap estimates below the original estimate) and
/// skewness (via the jackknife acceleration constant), achieving
/// second-order accuracy.
///
/// Parameters: same as `percentile_ci`.
///
/// Returns `(lower, upper)`. Returns `(NaN, NaN)` for invalid inputs.
/// Falls back to the percentile interval when the BCa adjustment is
/// degenerate (e.g. all bootstrap estimates are identical).
pub fn bca_ci(
  data : Array[Double],
  statistic : (Array[Double]) -> Double,
  confidence : Double,
  seed : UInt64,
  n_bootstrap : Int,
) -> (Double, Double) {
  let n = data.length()
  if n < 3 || n_bootstrap < 10 || confidence <= 0.0 || confidence >= 1.0 {
    return (@double.not_a_number, @double.not_a_number)
  }
  let theta_hat = statistic(data)
  let rng = @utils.SplitMix64::new(seed)
  let resample_buf : Array[Double] = Array::make(n, 0.0)
  let estimates : Array[Double] = Array::make(n_bootstrap, 0.0)
  for b = 0; b < n_bootstrap; b = b + 1 {
    resample(rng, data, resample_buf)
    estimates[b] = statistic(resample_buf)
  }
  // Sort bootstrap estimates.
  estimates.sort_by(fn(a, b) {
    if a < b {
      -1
    } else if a > b {
      1
    } else {
      0
    }
  })
  // Bias correction factor z₀.
  // z₀ = Φ⁻¹(#{θ*_b < θ_hat} / B)
  let mut count_below = 0
  for b = 0; b < n_bootstrap; b = b + 1 {
    if estimates[b] < theta_hat {
      count_below = count_below + 1
    }
  }
  let prop_below = count_below.to_double() / n_bootstrap.to_double()
  // If prop_below is 0 or 1, z₀ is ±∞ — fall back to percentile.
  if prop_below <= 0.0 || prop_below >= 1.0 {
    let alpha = 1.0 - confidence
    return (
      quantile_sorted(estimates, alpha / 2.0),
      quantile_sorted(estimates, 1.0 - alpha / 2.0),
    )
  }
  // Φ⁻¹ via normal_inv_cdf — use a rational approximation (Acklam).
  let z0 = normal_inv_cdf_approx(prop_below)
  // Acceleration constant via jackknife.
  let a = jackknife_acceleration(data, statistic)
  let alpha = 1.0 - confidence
  let z_lo = normal_inv_cdf_approx(alpha / 2.0)
  let z_hi = normal_inv_cdf_approx(1.0 - alpha / 2.0)
  // BCa adjusted quantile levels:
  // α₁ = Φ(z₀ + (z₀ + z_α/2) / (1 − a(z₀ + z_α/2)))
  // α₂ = Φ(z₀ + (z₀ + z_{1-α/2}) / (1 − a(z₀ + z_{1-α/2})))
  let denom_lo = 1.0 - a * (z0 + z_lo)
  let denom_hi = 1.0 - a * (z0 + z_hi)
  let alpha1 = if denom_lo == 0.0 {
    alpha / 2.0
  } else {
    normal_cdf_approx(z0 + (z0 + z_lo) / denom_lo)
  }
  let alpha2 = if denom_hi == 0.0 {
    1.0 - alpha / 2.0
  } else {
    normal_cdf_approx(z0 + (z0 + z_hi) / denom_hi)
  }
  // Clamp to [0, 1].
  let alpha1 = if alpha1 < 0.0 {
    0.0
  } else if alpha1 > 1.0 {
    1.0
  } else {
    alpha1
  }
  let alpha2 = if alpha2 < 0.0 {
    0.0
  } else if alpha2 > 1.0 {
    1.0
  } else {
    alpha2
  }
  let lo = quantile_sorted(estimates, alpha1)
  let hi = quantile_sorted(estimates, alpha2)
  (lo, hi)
}

///|
/// BCa bootstrap confidence interval for the mean.
///
/// Convenience wrapper around `bca_ci` with `statistic = @descriptive.mean`.
pub fn mean_bca_ci(
  data : Array[Double],
  confidence : Double,
  seed : UInt64,
  n_bootstrap : Int,
) -> (Double, Double) {
  bca_ci(data, fn(d) { @descriptive.mean(d) }, confidence, seed, n_bootstrap)
}

///|
/// BCa bootstrap confidence interval for the median.
///
/// Convenience wrapper around `bca_ci` with `statistic = @descriptive.median`.
pub fn median_bca_ci(
  data : Array[Double],
  confidence : Double,
  seed : UInt64,
  n_bootstrap : Int,
) -> (Double, Double) {
  bca_ci(data, fn(d) { @descriptive.median(d) }, confidence, seed, n_bootstrap)
}

// ---------------------------------------------------------------------------
// Normal CDF and inverse CDF (Acklam's algorithm)
// Used internally for BCa to avoid cross-package dependency on hypothesis_testing.
// ---------------------------------------------------------------------------

///|
/// Standard normal CDF approximation via the erf formula.
/// Φ(z) = 0.5 * (1 + erf(z / √2))
/// Uses Abramowitz & Stegun 7.1.26 (accuracy ~1.5×10⁻⁷).
fn normal_cdf_approx(z : Double) -> Double {
  let sqrt2 = 1.4142135623730951
  let x = z / sqrt2
  // A&S 7.1.26: erf(x) for x >= 0
  let sign = if x < 0.0 { -1.0 } else { 1.0 }
  let ax = x.abs()
  let t = 1.0 / (1.0 + 0.3275911 * ax)
  let poly = t * (0.254829592 +
    t * (-0.284496736 +
      t * (1.421413741 +
        t * (-1.453152027 + t * 1.061405429))))
  let erf_val = sign * (1.0 - poly * @math.exp(-ax * ax))
  0.5 * (1.0 + erf_val)
}

///|
/// Inverse standard normal CDF (quantile function) via Acklam's algorithm.
/// Accuracy: relative error < 1.15×10⁻⁹ in the range [10⁻¹⁵, 1 − 10⁻¹⁵].
fn normal_inv_cdf_approx(p : Double) -> Double {
  if p <= 0.0 {
    return @double.neg_infinity
  }
  if p >= 1.0 {
    return @double.infinity
  }
  let a = [
    -3.969683028665376e+01, 2.209460984245205e+02, -2.759285104469687e+02,
    1.383577518672690e+02, -3.066479806614716e+01, 2.506628277459239e+00,
  ]
  let b = [
    -5.447609879822406e+01, 1.615858368580409e+02, -1.556989798598866e+02,
    6.680131188771972e+01, -1.328068155288572e+01,
  ]
  let c = [
    -7.784894002430293e-03, -3.223964580411365e-01, -2.400758277161838e+00,
    -2.549732539343734e+00, 4.374664141464968e+00, 2.938163982698783e+00,
  ]
  let d = [
    7.784695709041462e-03, 3.224671290700398e-01, 2.445134137142996e+00,
    3.754408661907416e+00,
  ]
  let plow = 0.02425
  let phigh = 1.0 - plow
  if p < plow {
    let q = m_sqrt(-2.0 * @math.ln(p))
    -(((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) /
    ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1.0)
  } else if p <= phigh {
    let q = p - 0.5
    let r = q * q
    (((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) *
    q /
    (((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1.0)
  } else {
    let q = m_sqrt(-2.0 * @math.ln(1.0 - p))
    (((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) /
    ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1.0)
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "bootstrap: mean percentile CI contains sample mean" {
  let data = [
    10.0, 12.0, 11.0, 13.0, 10.5, 11.5, 12.5, 10.8, 11.2, 12.0, 11.3, 10.9,
    12.1, 11.7, 10.6,
  ]
  let (lo, hi) = mean_percentile_ci(data, 0.95, 42UL, 2000)
  let m = @descriptive.mean(data)
  assert_true(lo < m)
  assert_true(hi > m)
  assert_true(hi > lo)
}

///|
test "bootstrap: median percentile CI" {
  let data = [
    10.0, 12.0, 11.0, 13.0, 10.5, 11.5, 12.5, 10.8, 11.2, 12.0, 11.3, 10.9,
    12.1, 11.7, 10.6,
  ]
  let (lo, hi) = median_percentile_ci(data, 0.95, 42UL, 2000)
  let med = @descriptive.median(data)
  assert_true(lo <= med)
  assert_true(hi >= med)
  assert_true(hi >= lo)
}

///|
test "bootstrap: BCa CI for mean" {
  let data = [
    10.0, 12.0, 11.0, 13.0, 10.5, 11.5, 12.5, 10.8, 11.2, 12.0, 11.3, 10.9,
    12.1, 11.7, 10.6,
  ]
  let (lo, hi) = mean_bca_ci(data, 0.95, 42UL, 2000)
  let m = @descriptive.mean(data)
  assert_true(lo < m)
  assert_true(hi > m)
  assert_true(hi > lo)
}

///|
test "bootstrap: BCa CI for median" {
  let data = [
    10.0, 12.0, 11.0, 13.0, 10.5, 11.5, 12.5, 10.8, 11.2, 12.0, 11.3, 10.9,
    12.1, 11.7, 10.6,
  ]
  let (lo, hi) = median_bca_ci(data, 0.95, 42UL, 2000)
  assert_true(hi > lo)
}

///|
test "bootstrap: wider confidence gives wider interval" {
  let data = [
    10.0, 12.0, 11.0, 13.0, 10.5, 11.5, 12.5, 10.8, 11.2, 12.0, 11.3, 10.9,
    12.1, 11.7, 10.6,
  ]
  let (lo95, hi95) = mean_percentile_ci(data, 0.95, 42UL, 2000)
  let (lo99, hi99) = mean_percentile_ci(data, 0.99, 42UL, 2000)
  assert_true(lo99 <= lo95)
  assert_true(hi99 >= hi95)
}

///|
test "bootstrap: reproducible with same seed" {
  let data = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0]
  let (lo1, hi1) = mean_percentile_ci(data, 0.95, 123UL, 1000)
  let (lo2, hi2) = mean_percentile_ci(data, 0.95, 123UL, 1000)
  assert_true((lo1 - lo2).abs() < 1.0e-10)
  assert_true((hi1 - hi2).abs() < 1.0e-10)
}

///|
test "bootstrap: different seeds give different results" {
  let data = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0]
  let (lo1, _hi1) = mean_percentile_ci(data, 0.95, 123UL, 1000)
  let (lo2, _hi2) = mean_percentile_ci(data, 0.95, 456UL, 1000)
  // Different seeds should almost certainly give different lower bounds.
  assert_true((lo1 - lo2).abs() > 1.0e-6)
}

///|
test "bootstrap: invalid inputs return NaN" {
  let (lo, hi) = mean_percentile_ci([], 0.95, 42UL, 1000)
  assert_true(lo.is_nan())
  assert_true(hi.is_nan())
  let (lo2, hi2) = mean_percentile_ci([1.0], 0.95, 42UL, 1000)
  assert_true(lo2.is_nan())
  assert_true(hi2.is_nan())
}

///|
test "bootstrap: custom statistic (variance)" {
  let data = [
    5.0, 7.0, 6.0, 8.0, 5.5, 6.5, 7.5, 5.8, 6.2, 7.0, 6.3, 5.9, 7.1, 6.7, 5.6,
  ]
  let (lo, hi) = percentile_ci(
    data,
    fn(d) { @descriptive.variance(d) },
    0.95,
    42UL,
    2000,
  )
  let v = @descriptive.variance(data)
  assert_true(lo < v)
  assert_true(hi > v)
  assert_true(hi > lo)
}
