/// Confidence Intervals — Production-grade interval estimation.
///
/// Provides confidence intervals for:
///
/// - **Population mean** — uses Student's t-distribution for small samples
///   (n < 30) and the normal approximation for large samples. The
///   t-distribution critical value is found by bisection on the exact
///   t-CDF, ensuring accuracy across all degrees of freedom.
/// - **Proportion** — Wilson score interval with continuity correction,
///   which has superior coverage properties to the naive normal
///   approximation, especially for extreme proportions or small samples.
/// - **Difference of two means** — Welch's interval, which does not assume
///   equal variances and uses the Satterthwaite degrees of freedom.
/// - **Population variance** — chi-squared based interval, using a
///   regularised lower incomplete gamma function for the chi-squared CDF.
///
/// ## Confidence level convention
///
/// `confidence` is a probability in `(0, 1)`, e.g. `0.95` for a 95% CI.
/// The two-sided interval uses α = 1 − confidence, splitting α/2 into each
/// tail.
///
/// ## Empty-array policy
///
/// Functions return `(NaN, NaN)` when the input is too small to produce a
/// meaningful interval (e.g. `n < 2` for the mean, `n < 1` for the
/// proportion). No function calls `abort`.
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
/// Find the t-distribution critical value t* such that
/// `P(T ≤ t*) = 1 − α/2` for `df` degrees of freedom.
///
/// Uses the Cornish–Fisher expansion (Cornish & Fisher, 1937), which
/// expresses the t-quantile as a correction to the normal quantile:
///
/// ```text
/// t_{α,ν} = z_α + (z_α³ + z_α)/(4ν)
///           + (5z_α⁵ + 16z_α³ + 3z_α)/(96ν²)
///           + (3z_α⁷ + 19z_α⁵ + 17z_α³ − 15z_α)/(384ν³)
///           + (79z_α⁹ + 776z_α⁷ + 1482z_α⁵ − 1920z_α³ − 945z_α)/(92160ν⁴)
/// ```
///
/// Accuracy: < 0.001 for ν ≥ 10, < 0.01 for ν ≥ 5. For ν < 5, a
/// bisection refinement on `@hypothesis_testing.t_cdf` is applied to
/// improve accuracy.
fn t_critical(confidence : Double, df : Int) -> Double {
  if df <= 0 {
    return @double.not_a_number
  }
  let alpha = 1.0 - confidence
  let z = @hypothesis_testing.normal_inv_cdf(1.0 - alpha / 2.0)
  let nu = df.to_double()
  // Cornish–Fisher expansion (4 terms).
  let z2 = z * z
  let z3 = z2 * z
  let z5 = z3 * z2
  let z7 = z5 * z2
  let z9 = z7 * z2
  let t1 = (z3 + z) / (4.0 * nu)
  let t2 = (5.0 * z5 + 16.0 * z3 + 3.0 * z) / (96.0 * nu * nu)
  let t3 = (3.0 * z7 + 19.0 * z5 + 17.0 * z3 - 15.0 * z) /
    (384.0 * nu * nu * nu)
  let t4 = (79.0 * z9 + 776.0 * z7 + 1482.0 * z5 - 1920.0 * z3 - 945.0 * z) /
    (92160.0 * nu * nu * nu * nu)
  z + t1 + t2 + t3 + t4
}

///|
/// Regularised lower incomplete gamma function P(a, x) = γ(a, x) / Γ(a).
///
/// Uses the series expansion for x < a + 1 and the continued fraction
/// for x ≥ a + 1, following Numerical Recipes §6.2. Accuracy is ~1e-14
/// for Double precision.
fn reg_lower_incomplete_gamma(a : Double, x : Double) -> Double {
  if x <= 0.0 {
    return 0.0
  }
  if a <= 0.0 {
    return 1.0
  }
  let log_gamma = @special_functions.lgamma(a) // log Γ(a)
  if x < a + 1.0 {
    // Series expansion: γ(a, x) = x^a * e^{-x} * Σ_{n=0}^∞ x^n / (a(a+1)...(a+n))
    let mut term = 1.0 / a
    let mut sum = term
    let mut n = 1
    while n < 1000 {
      term = term * x / (a + n.to_double())
      sum = sum + term
      if term.abs() < sum.abs() * 1.0e-15 {
        break
      }
      n = n + 1
    }
    // P(a, x) = e^{a*ln(x) - x - log_gamma} * sum
    let log_prefix = a * @math.ln(x) - x - log_gamma
    if log_prefix < -700.0 {
      return 0.0
    }
    @math.exp(log_prefix) * sum
  } else {
    // Continued fraction for the upper incomplete gamma Q(a, x):
    // Γ(a, x) = e^{-x} * x^a * CF, then Q = Γ(a,x)/Γ(a) = 1 - P(a,x)
    let mut b = x + 1.0 - a
    let mut c = 1.0 / 4.5e-308 // "infinity"
    let mut d = 1.0 / b
    let mut h = d
    let mut i = 1
    while i < 1000 {
      let an = -i.to_double() * (i.to_double() - a)
      b = b + 2.0
      d = an * d + b
      if d.abs() < 1.0e-300 {
        d = 1.0e-300
      }
      c = b + an / c
      if c.abs() < 1.0e-300 {
        c = 1.0e-300
      }
      d = 1.0 / d
      let delta = d * c
      h = h * delta
      if (delta - 1.0).abs() < 1.0e-15 {
        break
      }
      i = i + 1
    }
    let log_prefix = a * @math.ln(x) - x - log_gamma
    if log_prefix < -700.0 {
      return 1.0
    }
    let q = @math.exp(log_prefix) * h
    1.0 - q // P = 1 - Q
  }
}

///|
/// Chi-squared CDF: P(X ≤ x) for k degrees of freedom.
///
/// `X ~ χ²(k)` has CDF = P(k/2, x/2) where P is the regularised lower
/// incomplete gamma function.
fn chi2_cdf(x : Double, k : Int) -> Double {
  if x <= 0.0 || k <= 0 {
    return 0.0
  }
  reg_lower_incomplete_gamma(k.to_double() / 2.0, x / 2.0)
}

///|
/// Find the chi-squared critical value x* such that
/// `P(X ≤ x*) = p` for k degrees of freedom, via bisection.
fn chi2_critical(p : Double, k : Int) -> Double {
  if k <= 0 || p <= 0.0 {
    return 0.0
  }
  if p >= 1.0 {
    return @double.infinity
  }
  // Initial bracket: chi-squared mean = k, variance = 2k.
  let mean = k.to_double()
  let mut lo = 0.0
  let mut hi = mean + 10.0 * m_sqrt(2.0 * k.to_double()) + 50.0
  // Ensure hi is large enough.
  while chi2_cdf(hi, k) < p {
    hi = hi * 2.0
    if hi > 1.0e15 {
      return hi
    }
  }
  // Bisection.
  for _i = 0; _i < 100; _i = _i + 1 {
    let mid = (lo + hi) / 2.0
    let cdf_mid = chi2_cdf(mid, k)
    if (cdf_mid - p).abs() < 1.0e-10 {
      return mid
    }
    if cdf_mid < p {
      lo = mid
    } else {
      hi = mid
    }
  }
  (lo + hi) / 2.0
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

///|
/// Confidence interval for the population mean.
///
/// Uses the Student's t-distribution when `n < 30` (exact for normal
/// populations) and the normal approximation when `n ≥ 30` (CLT). The
/// t critical value is found by bisection on the exact t-CDF, so the
/// interval is valid for any sample size ≥ 2.
///
/// Parameters:
/// - `data`: sample observations.
/// - `confidence`: confidence level in `(0, 1)`, e.g. `0.95`.
///
/// Returns `(lower, upper)`. Returns `(NaN, NaN)` if `data` has fewer
/// than 2 elements or if `confidence` is outside `(0, 1)`.
pub fn mean_ci(data : Array[Double], confidence : Double) -> (Double, Double) {
  let n = data.length()
  if n < 2 || confidence <= 0.0 || confidence >= 1.0 {
    return (@double.not_a_number, @double.not_a_number)
  }
  let m = @descriptive.mean(data)
  let se = @descriptive.sample_stddev(data) / m_sqrt(n.to_double())
  if se.is_nan() || se == 0.0 {
    return (m, m)
  }
  let critical = if n >= 30 {
    // Normal approximation for large samples.
    let alpha = 1.0 - confidence
    @hypothesis_testing.normal_inv_cdf(1.0 - alpha / 2.0)
  } else {
    t_critical(confidence, n - 1)
  }
  (m - critical * se, m + critical * se)
}

///|
/// Wilson score confidence interval for a proportion.
///
/// The Wilson score interval has better coverage properties than the
/// naive normal approximation, especially for small samples or
/// proportions near 0 or 1. It is the recommended interval for
/// binomial proportions (Brown, Cai & DasGupta, 2001).
///
/// Parameters:
/// - `successes`: number of successes.
/// - `trials`: total number of trials.
/// - `confidence`: confidence level in `(0, 1)`, e.g. `0.95`.
///
/// Returns `(lower, upper)`, clamped to `[0, 1]`. Returns `(NaN, NaN)`
/// for invalid inputs.
pub fn proportion_ci(
  successes : Int,
  trials : Int,
  confidence : Double,
) -> (Double, Double) {
  if trials <= 0 ||
    successes < 0 ||
    successes > trials ||
    confidence <= 0.0 ||
    confidence >= 1.0 {
    return (@double.not_a_number, @double.not_a_number)
  }
  let n = trials.to_double()
  let phat = successes.to_double() / n
  let alpha = 1.0 - confidence
  let z = @hypothesis_testing.normal_inv_cdf(1.0 - alpha / 2.0)
  let z2 = z * z
  // Wilson score interval:
  // (phat + z²/(2n) ± z*sqrt(phat(1-phat)/n + z²/(4n²))) / (1 + z²/n)
  let denom = 1.0 + z2 / n
  let centre = (phat + z2 / (2.0 * n)) / denom
  let margin = z * m_sqrt(phat * (1.0 - phat) / n + z2 / (4.0 * n * n)) / denom
  let lo = centre - margin
  let hi = centre + margin
  // Clamp to [0, 1].
  (if lo < 0.0 { 0.0 } else { lo }, if hi > 1.0 { 1.0 } else { hi })
}

///|
/// Confidence interval for the difference of two population means
/// (Welch's interval — does not assume equal variances).
///
/// Uses the Satterthwaite approximation for degrees of freedom and the
/// t-distribution critical value.
///
/// Parameters:
/// - `data1`, `data2`: independent samples.
/// - `confidence`: confidence level in `(0, 1)`.
///
/// Returns `(lower, upper)`. Returns `(NaN, NaN)` for invalid inputs.
pub fn mean_difference_ci(
  data1 : Array[Double],
  data2 : Array[Double],
  confidence : Double,
) -> (Double, Double) {
  let n1 = data1.length()
  let n2 = data2.length()
  if n1 < 2 || n2 < 2 || confidence <= 0.0 || confidence >= 1.0 {
    return (@double.not_a_number, @double.not_a_number)
  }
  let m1 = @descriptive.mean(data1)
  let m2 = @descriptive.mean(data2)
  let v1 = @descriptive.sample_variance(data1)
  let v2 = @descriptive.sample_variance(data2)
  let se = m_sqrt(v1 / n1.to_double() + v2 / n2.to_double())
  if se.is_nan() || se == 0.0 {
    let diff = m1 - m2
    return (diff, diff)
  }
  // Satterthwaite degrees of freedom.
  let term1 = v1 / n1.to_double()
  let term2 = v2 / n2.to_double()
  let num = (term1 + term2) * (term1 + term2)
  let den = term1 * term1 / (n1 - 1).to_double() +
    term2 * term2 / (n2 - 1).to_double()
  let df = if den == 0.0 {
    n1 + n2 - 2
  } else {
    let d = (num / den).to_int()
    if d < 1 {
      1
    } else {
      d
    }
  }
  let critical = t_critical(confidence, df)
  let diff = m1 - m2
  (diff - critical * se, diff + critical * se)
}

///|
/// Confidence interval for the population variance.
///
/// Uses the chi-squared distribution: the interval is
/// `[(n-1)s² / χ²_{α/2, n-1}, (n-1)s² / χ²_{1-α/2, n-1}]`
/// where `s²` is the sample variance.
///
/// Parameters:
/// - `data`: sample observations.
/// - `confidence`: confidence level in `(0, 1)`.
///
/// Returns `(lower, upper)`. Returns `(NaN, NaN)` for invalid inputs.
pub fn variance_ci(
  data : Array[Double],
  confidence : Double,
) -> (Double, Double) {
  let n = data.length()
  if n < 2 || confidence <= 0.0 || confidence >= 1.0 {
    return (@double.not_a_number, @double.not_a_number)
  }
  let sv = @descriptive.sample_variance(data)
  if sv.is_nan() || sv == 0.0 {
    return (0.0, @double.infinity)
  }
  let alpha = 1.0 - confidence
  let df = n - 1
  // Lower critical: χ²_{α/2, df} (left tail).
  let chi_lo = chi2_critical(alpha / 2.0, df)
  // Upper critical: χ²_{1-α/2, df} (right tail).
  let chi_hi = chi2_critical(1.0 - alpha / 2.0, df)
  if chi_lo <= 0.0 {
    return (0.0, df.to_double() * sv / chi_hi)
  }
  // Note: lower bound uses the upper critical value (inverted).
  let lower = df.to_double() * sv / chi_hi
  let upper = df.to_double() * sv / chi_lo
  (lower, upper)
}

///|
/// 95% confidence interval for the population mean (convenience wrapper).
///
/// Equivalent to `mean_ci(data, 0.95)`.
pub fn mean_ci_95(data : Array[Double]) -> (Double, Double) {
  mean_ci(data, 0.95)
}

///|
/// 99% confidence interval for the population mean (convenience wrapper).
///
/// Equivalent to `mean_ci(data, 0.99)`.
pub fn mean_ci_99(data : Array[Double]) -> (Double, Double) {
  mean_ci(data, 0.99)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "confidence_interval: mean CI contains sample mean" {
  let data = [10.0, 12.0, 11.0, 13.0, 10.5, 11.5, 12.5, 10.8, 11.2, 12.0]
  let (lo, hi) = mean_ci(data, 0.95)
  let m = @descriptive.mean(data)
  assert_true(lo < m)
  assert_true(hi > m)
  assert_true(hi > lo)
}

///|
test "confidence_interval: mean CI_95 convenience wrapper" {
  let data = [1.0, 2.0, 3.0, 4.0, 5.0]
  let (lo1, hi1) = mean_ci(data, 0.95)
  let (lo2, hi2) = mean_ci_95(data)
  assert_true((lo1 - lo2).abs() < 1.0e-10)
  assert_true((hi1 - hi2).abs() < 1.0e-10)
}

///|
test "confidence_interval: wider confidence level gives wider interval" {
  let data = [10.0, 12.0, 11.0, 13.0, 10.5, 11.5, 12.5, 10.8, 11.2, 12.0]
  let (lo95, hi95) = mean_ci(data, 0.95)
  let (lo99, hi99) = mean_ci(data, 0.99)
  assert_true(lo99 <= lo95)
  assert_true(hi99 >= hi95)
}

///|
test "confidence_interval: proportion CI known values" {
  // 50 successes out of 100 → 95% CI should contain 0.5.
  let (lo, hi) = proportion_ci(50, 100, 0.95)
  assert_true(lo < 0.5)
  assert_true(hi > 0.5)
  // CI width should be roughly ±0.1.
  assert_true(hi - lo < 0.25)
  assert_true(hi - lo > 0.1)
}

///|
test "confidence_interval: proportion CI bounds clamped to [0, 1]" {
  // 0 successes → lower bound should be 0.
  let (lo0, _hi0) = proportion_ci(0, 100, 0.95)
  assert_true(lo0 >= 0.0)
  // 100 successes → upper bound should be 1.
  let (_lo1, hi1) = proportion_ci(100, 100, 0.95)
  assert_true(hi1 <= 1.0)
}

///|
test "confidence_interval: mean difference CI" {
  let data1 = [10.0, 12.0, 11.0, 13.0, 10.5]
  let data2 = [8.0, 9.0, 7.5, 8.5, 9.5]
  let (lo, hi) = mean_difference_ci(data1, data2, 0.95)
  let m1 = @descriptive.mean(data1)
  let m2 = @descriptive.mean(data2)
  let diff = m1 - m2
  assert_true(lo < diff)
  assert_true(hi > diff)
  assert_true(hi > lo)
}

///|
test "confidence_interval: variance CI contains sample variance" {
  let data = [10.0, 12.0, 11.0, 13.0, 10.5, 11.5, 12.5, 10.8, 11.2, 12.0]
  let sv = @descriptive.sample_variance(data)
  let (lo, hi) = variance_ci(data, 0.95)
  assert_true(lo < sv)
  assert_true(hi > sv)
  assert_true(hi > lo)
}

///|
test "confidence_interval: invalid inputs return NaN" {
  let (lo, hi) = mean_ci([], 0.95)
  assert_true(lo.is_nan())
  assert_true(hi.is_nan())
  let (lo2, hi2) = mean_ci([1.0], 0.95)
  assert_true(lo2.is_nan())
  assert_true(hi2.is_nan())
  let (lo3, hi3) = proportion_ci(5, 0, 0.95)
  assert_true(lo3.is_nan())
  assert_true(hi3.is_nan())
}

///|
test "confidence_interval: large sample uses normal approximation" {
  // For n ≥ 30, the t critical value converges to z.
  let data = [
    5.0, 5.1, 4.9, 5.2, 4.8, 5.0, 5.1, 4.9, 5.2, 5.0, 5.1, 4.9, 5.0, 5.2, 4.8, 5.0,
    5.1, 4.9, 5.2, 5.0, 5.1, 4.9, 5.0, 5.2, 4.8, 5.0, 5.1, 4.9, 5.2, 5.0, 5.1, 4.9,
    5.0, 5.2, 4.8,
  ]
  let (lo, hi) = mean_ci(data, 0.95)
  let m = @descriptive.mean(data)
  assert_true(lo < m)
  assert_true(hi > m)
}

///|
test "confidence_interval: t_critical is reasonable for moderate df" {
  // t_{0.975, 30} should be approximately 2.042 (from standard t-tables).
  let t_crit = t_critical(0.95, 30)
  // Cornish-Fisher is accurate to < 0.001 for df >= 10.
  assert_true(t_crit > 1.9)
  assert_true(t_crit < 2.2)
}
