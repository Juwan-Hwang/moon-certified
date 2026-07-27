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
