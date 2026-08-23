/// Probability Distributions — PDF, CDF, and PMF for common distributions.
///
/// This package provides density and mass functions for the most widely used
/// continuous and discrete probability distributions:
///
/// - **Normal** (Gaussian): PDF and CDF with arbitrary mean and standard
///   deviation. The CDF delegates to `@special_functions.erf` via the standard
///   normal CDF, inheriting its ~1.5×10⁻⁷ accuracy.
/// - **Exponential**: PDF and CDF parameterised by rate λ.
/// - **Binomial**: PMF for `k` successes in `n` Bernoulli trials. Uses
///   `lgamma` to compute the binomial coefficient in log-space, avoiding
///   overflow for large `n`.
/// - **Poisson**: PMF for `k` events with rate λ. Also computed in log-space.
/// - **Beta**: PDF on [0, 1] with shape parameters `a` and `b`.
///
/// ## Edge-case policy
///
/// Functions return `0.0` for inputs outside the support of the distribution
/// (e.g. negative `x` for the exponential, `x` outside [0, 1] for the beta).
/// They also return `0.0` when parameters are invalid (e.g. `std ≤ 0`).
/// No function calls `abort`; callers receive a finite `Double` in every case.
///
/// ## Accuracy
///
/// The normal CDF inherits the Abramowitz & Stegun 7.1.26 accuracy of
/// `@special_functions.erf` (~1.5×10⁻⁷). The binomial and Poisson PMFs use
/// `@special_functions.lgamma` (Lanczos, ~1e-15 relative error), so their
/// dominant error source is the final `exp` rounding.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

///|
/// Square root of 2π, precomputed.
let sqrt_2pi : Double = 2.50662827463100050241

// ---------------------------------------------------------------------------
// Normal (Gaussian) distribution
// ---------------------------------------------------------------------------

///|
/// Probability density function of the normal distribution
/// N(mean, std²).
///
/// ```
/// f(x) = 1 / (σ·√(2π)) · exp(−(x − μ)² / (2σ²))
/// ```
///
/// Returns `0.0` when `std ≤ 0` (degenerate / invalid). When the exponent
/// underflows (|x − μ| ≳ 27·σ for Double), the result is correctly `0.0`.
pub fn normal_pdf(x : Double, mean : Double, std : Double) -> Double {
  if std <= 0.0 {
    return 0.0
  }
  let z = (x - mean) / std
  let exponent = -0.5 * z * z
  if exponent < -745.0 {
    return 0.0 // exp(−745) ≈ 5e-324; below this the result underflows to 0.
  }
  @math.exp(exponent) / (std * sqrt_2pi)
}

///|
/// Cumulative distribution function of the normal distribution
/// N(mean, std²).
///
/// ```
/// F(x) = 0.5 · (1 + erf((x − μ) / (σ·√2)))
/// ```
///
/// Delegates to `@special_functions.normal_cdf` after standardising, so the
/// accuracy is that of the A&S 7.1.26 erf approximation (~1.5×10⁻⁷).
///
/// Returns `0.0` when `std ≤ 0`.
pub fn normal_cdf(x : Double, mean : Double, std : Double) -> Double {
  if std <= 0.0 {
    return 0.0
  }
  @special_functions.normal_cdf((x - mean) / std)
}

// ---------------------------------------------------------------------------
// Exponential distribution
// ---------------------------------------------------------------------------

///|
/// Probability density function of the exponential distribution with rate
/// `rate` (λ).
///
/// ```
/// f(x) = λ · exp(−λx)   for x ≥ 0, λ > 0
/// f(x) = 0              otherwise
/// ```
///
/// Returns `0.0` when `rate ≤ 0`.
pub fn exponential_pdf(x : Double, rate : Double) -> Double {
  if rate <= 0.0 || x < 0.0 {
    return 0.0
  }
  let exponent = -rate * x
  if exponent < -745.0 {
    return 0.0
  }
  rate * @math.exp(exponent)
}

///|
/// Cumulative distribution function of the exponential distribution with
/// rate `rate` (λ).
///
/// ```
/// F(x) = 1 − exp(−λx)   for x ≥ 0, λ > 0
/// F(x) = 0              otherwise
/// ```
///
/// Returns `0.0` when `rate ≤ 0`.
pub fn exponential_cdf(x : Double, rate : Double) -> Double {
  if rate <= 0.0 || x < 0.0 {
    return 0.0
  }
  let exponent = -rate * x
  if exponent < -745.0 {
    return 1.0 // exp(−large) → 0, so CDF → 1.
  }
  1.0 - @math.exp(exponent)
}

// ---------------------------------------------------------------------------
// Binomial distribution
// ---------------------------------------------------------------------------

///|
/// Probability mass function of the binomial distribution B(n, p).
///
/// ```
/// P(X = k) = C(n, k) · p^k · (1−p)^(n−k)
/// ```
///
/// The binomial coefficient is computed in log-space via `lgamma` to avoid
/// overflow for large `n`:
///
/// ```
/// ln C(n, k) = lgamma(n+1) − lgamma(k+1) − lgamma(n−k+1)
/// ```
///
/// Returns `0.0` for out-of-range `k` (k < 0 or k > n), invalid `p`
/// (p < 0 or p > 1), or `n < 0`.
pub fn binomial_pmf(k : Int, n : Int, p : Double) -> Double {
  if n < 0 || k < 0 || k > n || p < 0.0 || p > 1.0 {
    return 0.0
  }
  // Boundary cases: p = 0 or p = 1.
  if p == 0.0 {
    return if k == 0 { 1.0 } else { 0.0 }
  }
  if p == 1.0 {
    return if k == n { 1.0 } else { 0.0 }
  }
  let log_p = @math.ln(p)
  let log_1mp = @math.ln(1.0 - p)
  let log_coeff = @special_functions.lgamma(n.to_double() + 1.0) -
    @special_functions.lgamma(k.to_double() + 1.0) -
    @special_functions.lgamma((n - k).to_double() + 1.0)
  let log_pmf = log_coeff +
    k.to_double() * log_p +
    (n - k).to_double() * log_1mp
  @math.exp(log_pmf)
}

// ---------------------------------------------------------------------------
// Poisson distribution
// ---------------------------------------------------------------------------

///|
/// Probability mass function of the Poisson distribution with rate `lambda`
/// (λ).
///
/// ```
/// P(X = k) = λ^k · exp(−λ) / k!
/// ```
///
/// Computed in log-space to avoid overflow:
///
/// ```
/// ln P = k·ln(λ) − λ − lgamma(k+1)
/// ```
///
/// Returns `0.0` when `lambda < 0` or `k < 0`. For `lambda = 0` the
/// distribution is a point mass at 0: P(0) = 1, P(k>0) = 0.
pub fn poisson_pmf(k : Int, lambda : Double) -> Double {
  if k < 0 || lambda < 0.0 {
    return 0.0
  }
  if lambda == 0.0 {
    return if k == 0 { 1.0 } else { 0.0 }
  }
  let log_pmf = k.to_double() * @math.ln(lambda) -
    lambda -
    @special_functions.lgamma(k.to_double() + 1.0)
  @math.exp(log_pmf)
}

// ---------------------------------------------------------------------------
// Beta distribution
// ---------------------------------------------------------------------------

///|
/// Probability density function of the beta distribution Beta(a, b).
///
/// ```
/// f(x) = x^(a−1) · (1−x)^(b−1) / B(a, b)
/// ```
///
/// where `B(a, b) = Γ(a)·Γ(b) / Γ(a+b)` is the beta function.
///
/// Computed in log-space via `lgamma` for numerical stability:
///
/// ```
/// ln f = (a−1)·ln(x) + (b−1)·ln(1−x) + lgamma(a+b) − lgamma(a) − lgamma(b)
/// ```
///
/// Returns `0.0` when `x` is outside (0, 1), or when `a ≤ 0` or `b ≤ 0`.
/// At the boundaries `x = 0` and `x = 1` the density is 0 when the
/// corresponding shape parameter exceeds 1 (the integrable case).
pub fn beta_pdf(x : Double, a : Double, b : Double) -> Double {
  if a <= 0.0 || b <= 0.0 || x <= 0.0 || x >= 1.0 {
    return 0.0
  }
  let log_pdf = (a - 1.0) * @math.ln(x) +
    (b - 1.0) * @math.ln(1.0 - x) +
    @special_functions.lgamma(a + b) -
    @special_functions.lgamma(a) -
    @special_functions.lgamma(b)
  @math.exp(log_pdf)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "normal_pdf: standard normal at zero" {
  // φ(0; 0, 1) = 1/√(2π) ≈ 0.3989422804
  let expected = 1.0 / (2.0 * @math.PI).sqrt()
  assert_true((normal_pdf(0.0, 0.0, 1.0) - expected).abs() < 1.0e-10)
}

///|
test "normal_pdf: symmetry around the mean" {
  let pdf_pos = normal_pdf(1.5, 0.0, 1.0)
  let pdf_neg = normal_pdf(-1.5, 0.0, 1.0)
  assert_true((pdf_pos - pdf_neg).abs() < 1.0e-10)
}

///|
test "normal_pdf: shift and scale" {
  // N(5, 2²) at x=5 should equal N(0, 1) at x=0.
  let shifted = normal_pdf(5.0, 5.0, 2.0)
  let standard = normal_pdf(0.0, 0.0, 1.0)
  // f(5; 5, 2) = 1/(2·√(2π)) · exp(0) = 1/(2·√(2π))
  let expected = 1.0 / (2.0 * sqrt_2pi)
  assert_true((shifted - expected).abs() < 1.0e-10)
  // The peak of N(5, 2²) is half the peak of N(0, 1) (because σ doubles).
  assert_true((shifted - standard / 2.0).abs() < 1.0e-10)
}

///|
test "normal_pdf: invalid std returns zero" {
  assert_true(normal_pdf(0.0, 0.0, 0.0) == 0.0)
  assert_true(normal_pdf(0.0, 0.0, -1.0) == 0.0)
}

///|
test "normal_cdf: known values" {
  // Φ(0; 0, 1) = 0.5
  assert_true((normal_cdf(0.0, 0.0, 1.0) - 0.5).abs() < 1.0e-6)
  // Φ(1.96; 0, 1) ≈ 0.975
  assert_true((normal_cdf(1.96, 0.0, 1.0) - 0.975).abs() < 1.0e-4)
  // Φ(−1.96; 0, 1) ≈ 0.025
  assert_true((normal_cdf(-1.96, 0.0, 1.0) - 0.025).abs() < 1.0e-4)
}

///|
test "normal_cdf: shift and scale" {
  // Φ((x−μ)/σ; 0, 1) == Φ(x; μ, σ)
  let val = normal_cdf(3.0, 1.0, 2.0)
  let standardised = @special_functions.normal_cdf((3.0 - 1.0) / 2.0)
  assert_true((val - standardised).abs() < 1.0e-10)
}

///|
test "normal_cdf: symmetry" {
  // Φ(−x) = 1 − Φ(x) for the standard normal.
  let pos = normal_cdf(1.0, 0.0, 1.0)
  let neg = normal_cdf(-1.0, 0.0, 1.0)
  assert_true((pos + neg - 1.0).abs() < 1.0e-6)
}

///|
test "exponential_pdf: known values" {
  // f(0; 1) = 1 · exp(0) = 1
  assert_true((exponential_pdf(0.0, 1.0) - 1.0).abs() < 1.0e-10)
  // f(1; 1) = exp(−1) ≈ 0.3678794412
  assert_true((exponential_pdf(1.0, 1.0) - @math.exp(-1.0)).abs() < 1.0e-10)
  // f(2; 0.5) = 0.5 · exp(−1) ≈ 0.1839397206
  let expected = 0.5 * @math.exp(-1.0)
  assert_true((exponential_pdf(2.0, 0.5) - expected).abs() < 1.0e-10)
}

///|
test "exponential_pdf: negative x returns zero" {
  assert_true(exponential_pdf(-1.0, 1.0) == 0.0)
}

///|
test "exponential_cdf: known values" {
  // F(0; 1) = 0
  assert_true((exponential_cdf(0.0, 1.0) - 0.0).abs() < 1.0e-10)
  // F(1; 1) = 1 − exp(−1) ≈ 0.6321205588
  let expected = 1.0 - @math.exp(-1.0)
  assert_true((exponential_cdf(1.0, 1.0) - expected).abs() < 1.0e-10)
  // As x → ∞, F → 1
  assert_true((exponential_cdf(50.0, 1.0) - 1.0).abs() < 1.0e-10)
}

///|
test "exponential_cdf: negative x returns zero" {
  assert_true(exponential_cdf(-1.0, 1.0) == 0.0)
}

///|
test "binomial_pmf: fair coin" {
  // B(1, 0.5): P(0) = 0.5, P(1) = 0.5
  assert_true((binomial_pmf(0, 1, 0.5) - 0.5).abs() < 1.0e-10)
  assert_true((binomial_pmf(1, 1, 0.5) - 0.5).abs() < 1.0e-10)
}

///|
test "binomial_pmf: sums to one" {
  // B(10, 0.3): all PMF values should sum to 1.
  let mut total = 0.0
  for k = 0; k <= 10; k = k + 1 {
    total = total + binomial_pmf(k, 10, 0.3)
  }
  assert_true((total - 1.0).abs() < 1.0e-6)
}

///|
test "binomial_pmf: known value" {
  // B(5, 0.5): P(2) = C(5,2) · 0.5^5 = 10/32 = 0.3125
  assert_true((binomial_pmf(2, 5, 0.5) - 0.3125).abs() < 1.0e-10)
  // B(4, 0.25): P(1) = C(4,1) · 0.25 · 0.75^3 = 4 · 0.25 · 0.421875 = 0.421875
  assert_true((binomial_pmf(1, 4, 0.25) - 0.421875).abs() < 1.0e-10)
}

///|
test "binomial_pmf: out of range" {
  assert_true(binomial_pmf(-1, 5, 0.5) == 0.0)
  assert_true(binomial_pmf(6, 5, 0.5) == 0.0)
  // p = 0: only k=0 has probability 1.
  assert_true(binomial_pmf(0, 5, 0.0) == 1.0)
  assert_true(binomial_pmf(1, 5, 0.0) == 0.0)
}

///|
test "poisson_pmf: known values" {
  // P(0; 1) = exp(−1) ≈ 0.3678794412
  assert_true((poisson_pmf(0, 1.0) - @math.exp(-1.0)).abs() < 1.0e-10)
  // P(1; 1) = 1 · exp(−1) / 1! = exp(−1)
  assert_true((poisson_pmf(1, 1.0) - @math.exp(-1.0)).abs() < 1.0e-10)
  // P(2; 1) = 1² · exp(−1) / 2! = exp(−1) / 2
  assert_true((poisson_pmf(2, 1.0) - @math.exp(-1.0) / 2.0).abs() < 1.0e-10)
}

///|
test "poisson_pmf: sums to one" {
  // Poisson(3): sum over k=0..30 should be ≈ 1.
  let mut total = 0.0
  for k = 0; k <= 30; k = k + 1 {
    total = total + poisson_pmf(k, 3.0)
  }
  assert_true((total - 1.0).abs() < 1.0e-6)
}

///|
test "poisson_pmf: zero lambda" {
  assert_true(poisson_pmf(0, 0.0) == 1.0)
  assert_true(poisson_pmf(1, 0.0) == 0.0)
}

///|
test "beta_pdf: uniform distribution" {
  // Beta(1, 1) is uniform on [0, 1]: f(x) = 1.
  assert_true((beta_pdf(0.5, 1.0, 1.0) - 1.0).abs() < 1.0e-10)
  assert_true((beta_pdf(0.3, 1.0, 1.0) - 1.0).abs() < 1.0e-10)
}

///|
test "beta_pdf: known value" {
  // Beta(2, 2): f(x) = 6·x·(1−x). f(0.5) = 6 · 0.25 = 1.5.
  assert_true((beta_pdf(0.5, 2.0, 2.0) - 1.5).abs() < 1.0e-10)
  // Beta(2, 5): f(0.3) = 30 · 0.3 · 0.7^4 = 30 · 0.3 · 0.2401 = 2.1609
  let expected = 30.0 * 0.3 * 0.2401
  assert_true((beta_pdf(0.3, 2.0, 5.0) - expected).abs() < 1.0e-6)
}

///|
test "beta_pdf: outside support" {
  assert_true(beta_pdf(0.0, 2.0, 2.0) == 0.0)
  assert_true(beta_pdf(1.0, 2.0, 2.0) == 0.0)
  assert_true(beta_pdf(-0.1, 2.0, 2.0) == 0.0)
  assert_true(beta_pdf(1.1, 2.0, 2.0) == 0.0)
}

// ---------------------------------------------------------------------------
// Student's t-distribution
// ---------------------------------------------------------------------------

///|
/// Probability density function of the Student's t-distribution with
/// `df` degrees of freedom.
///
/// ```
/// f(x) = Γ((df+1)/2) / (√(df·π) · Γ(df/2)) · (1 + x²/df)^(−(df+1)/2)
/// ```
///
/// Returns `0.0` when `df ≤ 0`.
pub fn student_t_pdf(x : Double, df : Double) -> Double {
  if df <= 0.0 {
    return 0.0
  }
  let log_num = @special_functions.lgamma((df + 1.0) / 2.0)
  let log_den = @special_functions.lgamma(df / 2.0) +
    0.5 * @math.ln(df * @math.PI)
  let log_body = -((df + 1.0) / 2.0) * @math.ln(1.0 + x * x / df)
  @math.exp(log_num - log_den + log_body)
}

///|
/// Cumulative distribution function of the Student's t-distribution with
/// `df` degrees of freedom.
///
/// Uses the regularized incomplete beta function:
/// For t > 0: CDF = 1 - 0.5 * I_{df/(df+t²)}(df/2, 1/2)
/// For t ≤ 0: CDF = 0.5 * I_{df/(df+t²)}(df/2, 1/2)
///
/// Returns `0.5` at `x = 0` (by symmetry). Returns `0.0` when `df ≤ 0`.
pub fn student_t_cdf(x : Double, df : Double) -> Double {
  if df <= 0.0 {
    return 0.0
  }
  if x == 0.0 {
    return 0.5
  }
  // Compute the regularized incomplete beta function I_x(a, b)
  // where x = df / (df + t²), a = df/2, b = 1/2.
  let t2 = x * x
  let z = df / (df + t2)
  let a = df / 2.0
  let b = 0.5
  let ibeta = regularized_incomplete_beta(z, a, b)
  if x > 0.0 {
    1.0 - 0.5 * ibeta
  } else {
    0.5 * ibeta
  }
}

// ---------------------------------------------------------------------------
// Chi-square distribution
// ---------------------------------------------------------------------------

///|
/// Probability density function of the chi-square distribution with
/// `k` degrees of freedom.
///
/// ```
/// f(x) = x^(k/2−1) · e^(−x/2) / (2^(k/2) · Γ(k/2))
/// ```
///
/// Returns `0.0` when `x ≤ 0` or `k ≤ 0`.
pub fn chi_square_pdf(x : Double, k : Double) -> Double {
  if x <= 0.0 || k <= 0.0 {
    return 0.0
  }
  let log_pdf = (k / 2.0 - 1.0) * @math.ln(x) -
    x / 2.0 -
    k / 2.0 * @math.ln(2.0) -
    @special_functions.lgamma(k / 2.0)
  @math.exp(log_pdf)
}

///|
/// Cumulative distribution function of the chi-square distribution with
/// `k` degrees of freedom.
///
/// Uses the regularized lower incomplete gamma function:
/// ```
/// F(x; k) = P(k/2, x/2) = γ(k/2, x/2) / Γ(k/2)
/// ```
///
/// Returns `0.0` when `x ≤ 0` or `k ≤ 0`.
pub fn chi_square_cdf(x : Double, k : Double) -> Double {
  if x <= 0.0 || k <= 0.0 {
    return 0.0
  }
  regularized_lower_incomplete_gamma(k / 2.0, x / 2.0)
}

// ---------------------------------------------------------------------------
// F-distribution
// ---------------------------------------------------------------------------

///|
/// Probability density function of the F-distribution with
/// `d1` and `d2` degrees of freedom.
///
/// ```
/// f(x) = ( (d1·x)^d1 · d2^d2 / (d1·x + d2)^(d1+d2) )^(1/2) /
///        ( x · B(d1/2, d2/2) )
/// ```
///
/// Returns `0.0` when `x ≤ 0`, `d1 ≤ 0`, or `d2 ≤ 0`.
pub fn f_pdf(x : Double, d1 : Double, d2 : Double) -> Double {
  if x <= 0.0 || d1 <= 0.0 || d2 <= 0.0 {
    return 0.0
  }
  let log_pdf = d1 / 2.0 * @math.ln(d1 * x) +
    d2 / 2.0 * @math.ln(d2) -
    (d1 + d2) / 2.0 * @math.ln(d1 * x + d2) -
    @math.ln(x) -
    (
      @special_functions.lgamma(d1 / 2.0) +
      @special_functions.lgamma(d2 / 2.0) -
      @special_functions.lgamma((d1 + d2) / 2.0)
    )
  @math.exp(log_pdf)
}

///|
/// Cumulative distribution function of the F-distribution.
///
/// Uses the regularized incomplete beta function:
/// ```
/// F(x; d1, d2) = I_{d1·x / (d1·x + d2)}(d1/2, d2/2)
/// ```
///
/// Returns `0.0` when `x ≤ 0`, `d1 ≤ 0`, or `d2 ≤ 0`.
pub fn f_cdf(x : Double, d1 : Double, d2 : Double) -> Double {
  if x <= 0.0 || d1 <= 0.0 || d2 <= 0.0 {
    return 0.0
  }
  let z = d1 * x / (d1 * x + d2)
  regularized_incomplete_beta(z, d1 / 2.0, d2 / 2.0)
}

// ---------------------------------------------------------------------------
// Gamma distribution
// ---------------------------------------------------------------------------

///|
/// Probability density function of the gamma distribution with
/// shape `k` and scale `θ`.
///
/// ```
/// f(x) = x^(k−1) · e^(−x/θ) / (θ^k · Γ(k))
/// ```
///
/// Returns `0.0` when `x ≤ 0`, `k ≤ 0`, or `θ ≤ 0`.
pub fn gamma_pdf(x : Double, k : Double, theta : Double) -> Double {
  if x <= 0.0 || k <= 0.0 || theta <= 0.0 {
    return 0.0
  }
  let log_pdf = (k - 1.0) * @math.ln(x) -
    x / theta -
    k * @math.ln(theta) -
    @special_functions.lgamma(k)
  @math.exp(log_pdf)
}

///|
/// Cumulative distribution function of the gamma distribution with
/// shape `k` and scale `θ`.
///
/// Uses the regularized lower incomplete gamma function:
/// ```
/// F(x; k, θ) = P(k, x/θ) = γ(k, x/θ) / Γ(k)
/// ```
///
/// Returns `0.0` when `x ≤ 0`, `k ≤ 0`, or `θ ≤ 0`.
pub fn gamma_cdf(x : Double, k : Double, theta : Double) -> Double {
  if x <= 0.0 || k <= 0.0 || theta <= 0.0 {
    return 0.0
  }
  regularized_lower_incomplete_gamma(k, x / theta)
}

// ---------------------------------------------------------------------------
// Internal: Regularized incomplete beta and gamma functions
// ---------------------------------------------------------------------------

///|
/// Regularized lower incomplete gamma function P(a, x) = γ(a, x) / Γ(a).
///
/// Uses the series expansion for x < a+1 and continued fraction for x ≥ a+1
/// (Numerical Recipes §6.2).
fn regularized_lower_incomplete_gamma(a : Double, x : Double) -> Double {
  if x < 0.0 || a <= 0.0 {
    return 0.0
  }
  if x == 0.0 {
    return 0.0
  }
  if x < a + 1.0 {
    // Series expansion.
    let mut term = 1.0 / a
    let mut sum = term
    let mut n = 1
    while n < 200 {
      term = term * x / (a + n.to_double())
      sum = sum + term
      if term.abs() < sum.abs() * 1.0e-15 {
        break
      }
      n = n + 1
    }
    sum * @math.exp(-x + a * @math.ln(x) - @special_functions.lgamma(a))
  } else {
    // Continued fraction (Lentz's method).
    let mut f = 1.0e-30
    let mut c = 1.0e-30
    let mut d = 0.0
    let mut i = 1
    while i < 200 {
      let an = if i == 1 { 0.0 } else { i.to_double() - 1.0 - a }
      let denom = an + x
      if denom.abs() < 1.0e-30 {
        d = 1.0e-30
      } else {
        d = denom
      }
      d = 1.0 / d
      let delta = d * c
      f = f * delta
      if (delta - 1.0).abs() < 1.0e-15 {
        break
      }
      c = 1.0 / (an + x)
      let b_an = i.to_double()
      let denom2 = b_an + x
      if denom2.abs() < 1.0e-30 {
        d = 1.0e-30
      } else {
        d = 1.0 / denom2
      }
      d = d * b_an
      let delta2 = d * c
      f = f * delta2
      if (delta2 - 1.0).abs() < 1.0e-15 {
        break
      }
      c = 1.0 / (b_an + x)
      i = i + 2
    }
    1.0 - f * @math.exp(-x + a * @math.ln(x) - @special_functions.lgamma(a))
  }
}

///|
/// Regularized incomplete beta function I_x(a, b).
///
/// Uses the continued fraction representation (Numerical Recipes §6.4).
fn regularized_incomplete_beta(x : Double, a : Double, b : Double) -> Double {
  if x <= 0.0 {
    return 0.0
  }
  if x >= 1.0 {
    return 1.0
  }
  if a <= 0.0 || b <= 0.0 {
    return 0.0
  }
  let lbeta = @special_functions.lgamma(a + b) -
    @special_functions.lgamma(a) -
    @special_functions.lgamma(b)
  let front = @math.exp(lbeta + a * @math.ln(x) + b * @math.ln(1.0 - x))
  // Use symmetry: I_x(a,b) = 1 - I_{1-x}(b,a) for x > (a+1)/(a+b+2).
  if x < (a + 1.0) / (a + b + 2.0) {
    // Continued fraction gives I_x directly.
    front * beta_continued_fraction(x, a, b) / a
  } else {
    // Use complement.
    let front2 = @math.exp(lbeta + b * @math.ln(1.0 - x) + a * @math.ln(x))
    1.0 - front2 * beta_continued_fraction(1.0 - x, b, a) / b
  }
}

///|
/// Continued fraction for the incomplete beta function (Lentz's method).
fn beta_continued_fraction(x : Double, a : Double, b : Double) -> Double {
  let mut f = 1.0e-30
  let mut c = 1.0e-30
  let mut d = 0.0
  let mut i = 0
  while i < 300 {
    let m = i.to_double()
    let numerator = if i == 0 {
      1.0
    } else if i % 2 == 0 {
      m * (b - m) * x / ((a + 2.0 * m - 1.0) * (a + 2.0 * m))
    } else {
      -((a + m) * (a + b + m) * x) / ((a + 2.0 * m) * (a + 2.0 * m + 1.0))
    }
    let denom = 1.0 + numerator
    if denom.abs() < 1.0e-30 {
      d = 1.0e-30
    } else {
      d = 1.0 / denom
    }
    let delta = d * c
    f = f * delta
    if (delta - 1.0).abs() < 1.0e-15 {
      break
    }
    c = 1.0 + numerator
    if c.abs() < 1.0e-30 {
      c = 1.0e-30
    }
    i = i + 1
  }
  f
}

// ---------------------------------------------------------------------------
// Tests for new distributions
// ---------------------------------------------------------------------------

///|
test "student_t_pdf: at zero" {
  // t(1) at 0: f(0) = Γ(1) / (√(π) · Γ(0.5)) = 1 / (√π · √π) = 1/π ≈ 0.3183
  let expected = 1.0 / @math.PI
  assert_true((student_t_pdf(0.0, 1.0) - expected).abs() < 1.0e-6)
}

///|
test "student_t_pdf: symmetry" {
  let df = 5.0
  let pos = student_t_pdf(1.5, df)
  let neg = student_t_pdf(-1.5, df)
  assert_true((pos - neg).abs() < 1.0e-10)
}

///|
test "student_t_pdf: convergence to normal" {
  // With large df, t-distribution approaches normal.
  let df = 1000.0
  let t_val = student_t_pdf(1.0, df)
  let normal_val = normal_pdf(1.0, 0.0, 1.0)
  assert_true((t_val - normal_val).abs() < 0.01)
}

///|
test "student_t_cdf: at zero" {
  assert_true((student_t_cdf(0.0, 1.0) - 0.5).abs() < 1.0e-10)
  assert_true((student_t_cdf(0.0, 10.0) - 0.5).abs() < 1.0e-10)
}

///|
test "student_t_cdf: symmetry" {
  let df = 5.0
  let pos = student_t_cdf(1.5, df)
  let neg = student_t_cdf(-1.5, df)
  assert_true((pos + neg - 1.0).abs() < 1.0e-6)
}

///|
test "chi_square_pdf: known value" {
  // χ²(2) at x=1: f(1) = e^(-1/2) / 2 ≈ 0.30327
  let expected = @math.exp(-0.5) / 2.0
  assert_true((chi_square_pdf(1.0, 2.0) - expected).abs() < 1.0e-6)
}

///|
test "chi_square_pdf: invalid inputs" {
  assert_true(chi_square_pdf(-1.0, 2.0) == 0.0)
  assert_true(chi_square_pdf(1.0, 0.0) == 0.0)
  assert_true(chi_square_pdf(0.0, 2.0) == 0.0)
}

///|
test "chi_square_cdf: at zero" {
  assert_true(chi_square_cdf(0.0, 2.0) == 0.0)
}

///|
test "chi_square_cdf: known value" {
  // χ²(2) CDF at x=2: F(2) = 1 - e^(-1) ≈ 0.6321
  let expected = 1.0 - @math.exp(-1.0)
  assert_true((chi_square_cdf(2.0, 2.0) - expected).abs() < 1.0e-6)
}

///|
test "f_pdf: positive for valid inputs" {
  assert_true(f_pdf(1.0, 5.0, 10.0) > 0.0)
}

///|
test "f_pdf: invalid inputs" {
  assert_true(f_pdf(-1.0, 5.0, 10.0) == 0.0)
  assert_true(f_pdf(1.0, 0.0, 10.0) == 0.0)
  assert_true(f_pdf(1.0, 5.0, 0.0) == 0.0)
}

///|
test "f_cdf: at zero" {
  assert_true(f_cdf(0.0, 5.0, 10.0) == 0.0)
}

///|
test "f_cdf: increases with x" {
  let cdf1 = f_cdf(0.5, 5.0, 10.0)
  let cdf2 = f_cdf(1.0, 5.0, 10.0)
  let cdf3 = f_cdf(2.0, 5.0, 10.0)
  assert_true(cdf1 < cdf2)
  assert_true(cdf2 < cdf3)
}

///|
test "gamma_pdf: known value" {
  // Gamma(k=1, θ=1) = Exponential(1): f(1) = e^(-1) ≈ 0.3679
  let expected = @math.exp(-1.0)
  assert_true((gamma_pdf(1.0, 1.0, 1.0) - expected).abs() < 1.0e-6)
}

///|
test "gamma_pdf: invalid inputs" {
  assert_true(gamma_pdf(-1.0, 1.0, 1.0) == 0.0)
  assert_true(gamma_pdf(1.0, 0.0, 1.0) == 0.0)
  assert_true(gamma_pdf(1.0, 1.0, 0.0) == 0.0)
}

///|
test "gamma_cdf: at zero" {
  assert_true(gamma_cdf(0.0, 1.0, 1.0) == 0.0)
}

///|
test "gamma_cdf: known value" {
  // Gamma(k=1, θ=1) = Exponential(1): F(1) = 1 - e^(-1) ≈ 0.6321
  let expected = 1.0 - @math.exp(-1.0)
  assert_true((gamma_cdf(1.0, 1.0, 1.0) - expected).abs() < 1.0e-6)
}
