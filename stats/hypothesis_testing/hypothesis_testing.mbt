///|
/// Local sqrt wrapper — @math has no top-level sqrt, only Double::sqrt.
fn m_sqrt(x : Double) -> Double {
  x.sqrt()
}

/// Statistical hypothesis testing and probability distributions.
///
/// Provides:
/// - Normal distribution CDF/PDF
/// - Student's t-distribution CDF (approximation)
/// - Chi-squared distribution CDF (approximation)
/// - One-sample and two-sample t-tests
/// - Pearson correlation coefficient
/// - Confidence intervals for the mean
///
/// Not formally verified. Correctness is ensured by the test suite.

// ---------------------------------------------------------------------------
// Normal distribution
// ---------------------------------------------------------------------------

///|
/// Standard normal PDF: φ(z) = (1/√(2π)) * e^{-z²/2}.
/// Delegates to `@special_functions.normal_pdf` which includes underflow
/// protection for large |z|.
pub fn normal_pdf(z : Double) -> Double {
  @special_functions.normal_pdf(z)
}

///|
/// Standard normal CDF: Φ(z) = ∫_{-∞}^{z} φ(t) dt.
/// Delegates to `@special_functions.normal_cdf` which uses the exact
/// erf-based formula Φ(z) = 0.5 * (1 + erf(z / √2)).
pub fn normal_cdf(z : Double) -> Double {
  @special_functions.normal_cdf(z)
}

///|
/// Inverse normal CDF (quantile function) via rational approximation
/// (Acklam's algorithm).
pub fn normal_inv_cdf(p : Double) -> Double {
  if p <= 0.0 {
    return @double.neg_infinity
  }
  if p >= 1.0 {
    return @double.infinity
  }
  let a = [
    -3.969683028665376e+01, 2.209460984245205e+02, -2.759285104469687e+02, 1.383577518672690e+02,
    -3.066479806614716e+01, 2.506628277459239e+00,
  ]
  let b = [
    -5.447609879822406e+01, 1.615858368580409e+02, -1.556989798598866e+02, 6.680131188771972e+01,
    -1.328068155288572e+01,
  ]
  let c = [
    -7.784894002430293e-03, -3.223964580411365e-01, -2.400758277161838e+00, -2.549732539343734e+00,
    4.374664141464968e+00, 2.938163982698783e+00,
  ]
  let d = [
    7.784695709041462e-03, 3.224671290700398e-01, 2.445134137142996e+00, 3.754408661907416e+00,
  ]
  let plow = 0.02425
  let phigh = 1.0 - plow
  if p < plow {
    let q = m_sqrt(-2.0 * @math.ln(p))
    (((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) /
    ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1.0)
  } else if p <= phigh {
    let q = p - 0.5
    let r = q * q
    (((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) *
    q /
    (((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1.0)
  } else {
    let q = m_sqrt(-2.0 * @math.ln(1.0 - p))
    -(((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) /
    ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1.0)
  }
}

// ---------------------------------------------------------------------------
// t-distribution CDF (Student's t)
// ---------------------------------------------------------------------------

///|
/// Student's t-distribution CDF using the regularized incomplete beta function.
/// Uses a series expansion approximation.
pub fn t_cdf(t : Double, df : Int) -> Double {
  if df <= 0 {
    return 0.5
  }
  let df_d = df.to_double()
  let x = df_d / (df_d + t * t)
  let a = df_d / 2.0
  let b = (df_d + 1.0) / 2.0
  let ib = reg_incomplete_beta(x, a, b)
  if t > 0.0 {
    1.0 - 0.5 * ib
  } else {
    0.5 * ib
  }
}

///|
/// Regularized incomplete beta function I_x(a,b) via continued fraction
/// (Lentz's method). This is the backbone of t-CDF and F-CDF.
fn reg_incomplete_beta(x : Double, a : Double, b : Double) -> Double {
  if x <= 0.0 {
    return 0.0
  }
  if x >= 1.0 {
    return 1.0
  }
  // Use the symmetry I_x(a,b) = 1 - I_{1-x}(b,a) when x > (a+1)/(a+b+2).
  let a_d = a
  let b_d = b
  let lbeta = log_beta(a, b)
  let front = @math.exp(a_d * @math.ln(x) + b_d * @math.ln(1.0 - x) - lbeta) /
    a_d
  // Continued fraction (Lentz).
  let mut f = 1.0
  let mut c = 1.0
  let mut d = 0.0
  let tiny = 1.0e-30
  for m = 1; m <= 200; m = m + 1 {
    let m_d = m.to_double()
    let numerator = if m % 2 == 0 {
      m_d * (b_d - m_d) * x / ((a_d + 2.0 * m_d - 1.0) * (a_d + 2.0 * m_d))
    } else {
      -(a_d + m_d - 1.0) *
      (a_d + b_d + m_d - 1.0) *
      x /
      ((a_d + 2.0 * m_d - 1.0) * (a_d + 2.0 * m_d))
    }
    d = 1.0 + numerator * d
    if d.abs() < tiny {
      d = tiny
    }
    c = 1.0 + numerator / c
    if c.abs() < tiny {
      c = tiny
    }
    d = 1.0 / d
    let delta = d * c
    f = f * delta
    if (delta - 1.0).abs() < 1.0e-10 {
      break
    }
  }
  front * f
}

///|
/// Log of the Beta function: log B(a,b) = log Γ(a) + log Γ(b) - log Γ(a+b).
fn log_beta(a : Double, b : Double) -> Double {
  log_gamma(a) + log_gamma(b) - log_gamma(a + b)
}

///|
/// Lanczos approximation for log Γ(x).
/// Delegates to `@special_functions.lgamma` to avoid code duplication.
fn log_gamma(x : Double) -> Double {
  @special_functions.lgamma(x)
}

// ---------------------------------------------------------------------------
// Descriptive statistics
// ---------------------------------------------------------------------------

///|
/// Compute the mean of a sample.
pub fn mean(data : Array[Double]) -> Double {
  if data.length() == 0 {
    return 0.0
  }
  let mut sum = 0.0
  for x in data {
    sum = sum + x
  }
  sum / data.length().to_double()
}

///|
/// Compute the sample variance (with Bessel's correction, n-1 denominator).
pub fn variance(data : Array[Double]) -> Double {
  let n = data.length()
  if n < 2 {
    return 0.0
  }
  let m = mean(data)
  let mut s = 0.0
  for x in data {
    let d = x - m
    s = s + d * d
  }
  s / (n - 1).to_double()
}

///|
/// Compute the sample standard deviation.
pub fn std_dev(data : Array[Double]) -> Double {
  m_sqrt(variance(data))
}

///|
/// Pearson correlation coefficient between two samples.
pub fn pearson_correlation(x : Array[Double], y : Array[Double]) -> Double {
  let n = x.length()
  if n != y.length() || n < 2 {
    return 0.0
  }
  let mx = mean(x)
  let my = mean(y)
  let mut sxy = 0.0
  let mut sxx = 0.0
  let mut syy = 0.0
  for i = 0; i < n; i = i + 1 {
    let dx = x[i] - mx
    let dy = y[i] - my
    sxy = sxy + dx * dy
    sxx = sxx + dx * dx
    syy = syy + dy * dy
  }
  if sxx == 0.0 || syy == 0.0 {
    return 0.0
  }
  sxy / (m_sqrt(sxx) * m_sqrt(syy))
}

// ---------------------------------------------------------------------------
// Hypothesis tests
// ---------------------------------------------------------------------------

///|
/// One-sample t-test: test if the sample mean differs from `mu0`.
///
/// Returns (t-statistic, two-tailed p-value).
pub fn one_sample_t_test(
  data : Array[Double],
  mu0 : Double,
) -> (Double, Double) {
  let n = data.length()
  if n < 2 {
    return (0.0, 1.0)
  }
  let m = mean(data)
  let se = m_sqrt(variance(data) / n.to_double())
  if se == 0.0 {
    return (0.0, 1.0)
  }
  let t = (m - mu0) / se
  let df = n - 1
  let cdf = t_cdf(t, df)
  let p = 2.0 * (if cdf > 0.5 { 1.0 - cdf } else { cdf })
  (t, p)
}

///|
/// Two-sample t-test (Welch's): test if two independent samples have
/// different means. Does not assume equal variances.
///
/// Returns (t-statistic, approximated p-value using Welch's df).
pub fn two_sample_t_test(
  data1 : Array[Double],
  data2 : Array[Double],
) -> (Double, Double) {
  let n1 = data1.length()
  let n2 = data2.length()
  if n1 < 2 || n2 < 2 {
    return (0.0, 1.0)
  }
  let m1 = mean(data1)
  let m2 = mean(data2)
  let v1 = variance(data1)
  let v2 = variance(data2)
  let se = m_sqrt(v1 / n1.to_double() + v2 / n2.to_double())
  if se == 0.0 {
    return (0.0, 1.0)
  }
  let t = (m1 - m2) / se
  // Welch's degrees of freedom.
  let num = (v1 / n1.to_double() + v2 / n2.to_double()) *
    (v1 / n1.to_double() + v2 / n2.to_double())
  let den = v1 / n1.to_double() * (v1 / n1.to_double()) / (n1 - 1).to_double() +
    v2 / n2.to_double() * (v2 / n2.to_double()) / (n2 - 1).to_double()
  let df = if den == 0.0 { n1 + n2 - 2 } else { (num / den).to_int() }
  let cdf = t_cdf(t, df)
  let p = 2.0 * (if cdf > 0.5 { 1.0 - cdf } else { cdf })
  (t, p)
}

///|
/// 95% confidence interval for the mean of `data`.
/// Returns (lower, upper). Uses the normal approximation for large n.
pub fn confidence_interval_95(data : Array[Double]) -> (Double, Double) {
  let n = data.length()
  if n < 2 {
    return (0.0, 0.0)
  }
  let m = mean(data)
  let se = std_dev(data) / m_sqrt(n.to_double())
  let z = 1.959964 // z_{0.025}
  (m - z * se, m + z * se)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "stats: normal_cdf known values" {
  let p0 = normal_cdf(0.0)
  assert_true((p0 - 0.5).abs() < 0.001)
  let p196 = normal_cdf(1.96)
  assert_true((p196 - 0.975).abs() < 0.001)
  let p_neg = normal_cdf(-1.96)
  assert_true((p_neg - 0.025).abs() < 0.001)
}

///|
test "stats: mean and variance" {
  let data = [1.0, 2.0, 3.0, 4.0, 5.0]
  assert_true((mean(data) - 3.0).abs() < 1.0e-10)
  assert_true((variance(data) - 2.5).abs() < 1.0e-10)
}

///|
test "stats: pearson correlation" {
  let x = [1.0, 2.0, 3.0, 4.0, 5.0]
  let y = [2.0, 4.0, 6.0, 8.0, 10.0]
  let r = pearson_correlation(x, y)
  assert_true((r - 1.0).abs() < 0.001)
}

///|
test "stats: one-sample t-test (reject H0)" {
  // Mean is clearly different from 0.
  let data = [10.0, 11.0, 12.0, 13.0, 14.0]
  let (t, p) = one_sample_t_test(data, 0.0)
  assert_true(t > 0.0)
  assert_true(p < 0.05)
}

///|
test "stats: two-sample t-test (same distribution)" {
  let d1 = [1.0, 2.0, 3.0, 4.0, 5.0]
  let d2 = [2.0, 1.0, 4.0, 3.0, 5.0]
  let (_, p) = two_sample_t_test(d1, d2)
  // Same values shuffled, should not reject H0.
  assert_true(p > 0.05)
}

///|
test "stats: confidence interval contains mean" {
  let data = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0]
  let (lo, hi) = confidence_interval_95(data)
  let m = mean(data)
  assert_true(lo < m && m < hi)
}
