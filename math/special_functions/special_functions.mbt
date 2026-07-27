/// Special Mathematical Functions — Gamma, Erf, Bessel, and related functions.
///
/// This package provides high-accuracy implementations of special functions
/// used in statistics, physics, and engineering:
/// - **Gamma function** (Lanczos approximation, accuracy ~1e-15)
/// - **Log-Gamma** (for large arguments and to avoid overflow)
/// - **Beta function** B(a, b) = Γ(a)Γ(b)/Γ(a+b)
/// - **Error function** erf and complementary erfc (Abramowitz & Stegun 7.1.26)
/// - **Normal distribution** CDF and PDF
/// - **Bessel function** J₀ (first kind, order 0)
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

///|
/// Square root of 2π, precomputed for the normal distribution PDF.
const SQRT_2PI : Double = 2.50662827463100050241

// ---------------------------------------------------------------------------
// Gamma function (Lanczos approximation)
// ---------------------------------------------------------------------------

///|
/// Lanczos approximation parameter g (g = 7, n = 9 coefficients).
const LANCZOS_G : Double = 7.0

///|
/// Initialize Lanczos coefficients (g = 7, n = 9).
///
/// These are the standard coefficients from Numerical Recipes (3rd ed.).
/// The approximation is:
///   Γ(z+1) ≈ √(2π) (z+g+0.5)^(z+0.5) e^{-(z+g+0.5)} A_g(z)
/// where A_g(z) = c_0 + Σ c_i / (z+i).
fn init_lanczos() -> FixedArray[Double] {
  let c = FixedArray::make(9, 0.0)
  c[0] = 0.99999999999980993
  c[1] = 676.5203681218851
  c[2] = -1259.1392167224028
  c[3] = 771.32342877765313
  c[4] = -176.61502916214059
  c[5] = 12.507343278686905
  c[6] = -0.13857109526572012
  c[7] = 9.9843695780195716e-6
  c[8] = 1.5056327351493116e-7
  c
}

///|
/// Euler's Gamma function using the Lanczos approximation.
///
/// Γ(z) is the continuous extension of the factorial: Γ(n) = (n-1)! for
/// positive integers n. For z < 0.5, the reflection formula is used:
/// Γ(z)Γ(1-z) = π / sin(πz).
///
/// ## Accuracy
/// Relative error < 1e-15 for Re(z) > 0.
pub fn gamma(x : Double) -> Double {
  if x < 0.5 {
    // Reflection formula: Γ(z) = π / (sin(πz) * Γ(1-z))
    let pi_z = @math.PI * x
    return @math.PI / (@math.sin(pi_z) * gamma(1.0 - x))
  }
  let c = init_lanczos()
  let z = x - 1.0
  let mut a = c[0]
  for i = 1; i < 9; i = i + 1 {
    a = a + c[i] / (z + i.to_double())
  }
  let t = z + LANCZOS_G + 0.5
  (2.0 * @math.PI).sqrt() * @math.pow(t, z + 0.5) * @math.exp(-t) * a
}

///|
/// Natural logarithm of the absolute value of the Gamma function.
///
/// Uses the Lanczos approximation for the log, which avoids overflow for
/// large arguments.
pub fn lgamma(x : Double) -> Double {
  if x < 0.5 {
    // Use reflection: ln|Γ(z)| = ln(π / |sin(πz) * Γ(1-z)|)
    let pi_z = @math.PI * x
    let sin_val = @math.sin(pi_z)
    let log_sin = @math.ln(sin_val.abs())
    return @math.ln(@math.PI) - log_sin - lgamma(1.0 - x)
  }
  let c = init_lanczos()
  let z = x - 1.0
  let mut a = c[0]
  for i = 1; i < 9; i = i + 1 {
    a = a + c[i] / (z + i.to_double())
  }
  let t = z + LANCZOS_G + 0.5
  0.5 * @math.ln(2.0 * @math.PI) + (z + 0.5) * @math.ln(t) - t + @math.ln(a)
}

///|
/// Beta function B(a, b) = Γ(a) * Γ(b) / Γ(a + b).
///
/// For integer arguments: B(a, b) = (a-1)!(b-1)! / (a+b-1)!.
pub fn beta(a : Double, b : Double) -> Double {
  gamma(a) * gamma(b) / gamma(a + b)
}

// ---------------------------------------------------------------------------
// Error function (Abramowitz & Stegun 7.1.26)
// ---------------------------------------------------------------------------

///|
/// Error function erf(x).
///
/// Uses the Abramowitz & Stegun 7.1.26 approximation, which has a maximum
/// absolute error of 1.5×10⁻⁷. For x = 0, returns exactly 0.
///
/// erf(0) = 0, erf(∞) = 1, erf(-x) = -erf(x).
pub fn erf(x : Double) -> Double {
  if x == 0.0 {
    return 0.0
  }
  if x < 0.0 {
    return -erf(-x)
  }
  // For very large x, erf → 1.
  if x > 6.0 {
    return 1.0
  }
  // A&S 7.1.26 coefficients.
  let a1 = 0.254829592
  let a2 = -0.284496736
  let a3 = 1.421413741
  let a4 = -1.453152027
  let a5 = 1.061405429
  let p = 0.3275911
  let t = 1.0 / (1.0 + p * x)
  let y = 1.0 -
    ((((a5 * t + a4) * t + a3) * t + a2) * t + a1) * t * @math.exp(-x * x)
  y
}

///|
/// Complementary error function erfc(x) = 1 - erf(x).
pub fn erfc(x : Double) -> Double {
  1.0 - erf(x)
}

// ---------------------------------------------------------------------------
// Normal distribution
// ---------------------------------------------------------------------------

///|
/// Standard normal PDF: φ(x) = (1/√(2π)) * exp(-x²/2).
///
/// Returns 0.0 when the exponential underflows (|x| ≳ 27 for Double).
pub fn normal_pdf(x : Double) -> Double {
  let exponent = -x * x / 2.0
  if exponent < -745.0 {
    // exp(-745) ≈ 5e-324, the smallest positive Double. Beyond this,
    // the result underflows to zero.
    return 0.0
  }
  @math.exp(exponent) / SQRT_2PI
}

///|
/// Standard normal CDF: Φ(x) = 0.5 * (1 + erf(x / √2)).
///
/// Φ(0) = 0.5, Φ(1.96) ≈ 0.975, Φ(-1.96) ≈ 0.025.
pub fn normal_cdf(x : Double) -> Double {
  0.5 * (1.0 + erf(x / 2.0.sqrt()))
}

// ---------------------------------------------------------------------------
// Bessel function J₀ (first kind, order 0)
// ---------------------------------------------------------------------------

///|
/// Bessel function of the first kind, order 0: J₀(x).
///
/// Uses polynomial approximations from Numerical Recipes (accuracy ~1e-8):
/// - For |x| < 8: rational polynomial approximation.
/// - For |x| ≥ 8: asymptotic expansion with sqrt(2/(πx)) factor.
pub fn bessel_j0(x : Double) -> Double {
  let ax = x.abs()
  if ax == 0.0 {
    return 1.0 // J0(0) = 1 exactly
  }
  if ax < 8.0 {
    // Rational polynomial approximation for |x| < 8.
    let y = x * x
    let ans1 = 57568490574.0 +
      y *
      (
        -13362590354.0 +
        y *
        (
          651619640.7 +
          y * (-11214424.18 + y * (77392.33017 + y * -184.9052456))
        )
      )
    let ans2 = 57568490411.0 +
      y *
      (
        1029532985.0 +
        y * (9494680.718 + y * (59272.64853 + y * (267.8532712 + y * 1.0)))
      )
    ans1 / ans2
  } else {
    // Asymptotic expansion for |x| >= 8.
    let z = 8.0 / ax
    let y = z * z
    let xx = ax - 0.785398164
    let ans1 = 1.0 +
      y *
      (
        -0.1098628627e-2 +
        y * (0.2734510407e-4 + y * (-0.2073370639e-5 + y * 0.2093887211e-6))
      )
    let ans2 = -0.1562499995e-1 +
      y *
      (
        0.1430488765e-3 +
        y * (-0.6911147651e-5 + y * (0.7621095161e-6 - y * 0.934935152e-7))
      )
    0.636619772 / ax.sqrt() * (@math.cos(xx) * ans1 - z * @math.sin(xx) * ans2)
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "gamma: integer values" {
  // Γ(1) = 0! = 1
  assert_true((gamma(1.0) - 1.0).abs() < 1.0e-10)
  // Γ(2) = 1! = 1
  assert_true((gamma(2.0) - 1.0).abs() < 1.0e-10)
  // Γ(3) = 2! = 2
  assert_true((gamma(3.0) - 2.0).abs() < 1.0e-10)
  // Γ(4) = 3! = 6
  assert_true((gamma(4.0) - 6.0).abs() < 1.0e-10)
  // Γ(5) = 4! = 24
  assert_true((gamma(5.0) - 24.0).abs() < 1.0e-10)
  // Γ(6) = 5! = 120
  assert_true((gamma(6.0) - 120.0).abs() < 1.0e-8)
}

///|
test "gamma: half-integer values" {
  // Γ(0.5) = sqrt(π)
  assert_true((gamma(0.5) - @math.PI.sqrt()).abs() < 1.0e-10)
  // Γ(1.5) = 0.5 * sqrt(π)
  assert_true((gamma(1.5) - 0.5 * @math.PI.sqrt()).abs() < 1.0e-10)
  // Γ(2.5) = 0.75 * sqrt(π)
  assert_true((gamma(2.5) - 0.75 * @math.PI.sqrt()).abs() < 1.0e-10)
  // Γ(3.5) = 1.875 * sqrt(π) = 15/8 * sqrt(π)
  assert_true((gamma(3.5) - 1.875 * @math.PI.sqrt()).abs() < 1.0e-10)
}

///|
test "gamma: negative values via reflection" {
  // Γ(-0.5) = -2*sqrt(π)
  assert_true((gamma(-0.5) - -2.0 * @math.PI.sqrt()).abs() < 1.0e-8)
  // Γ(-1.5) = 4/3 * sqrt(π)
  assert_true((gamma(-1.5) - 4.0 / 3.0 * @math.PI.sqrt()).abs() < 1.0e-8)
}

///|
test "lgamma: positive values" {
  // ln(Γ(5)) = ln(24)
  assert_true((lgamma(5.0) - @math.ln(24.0)).abs() < 1.0e-10)
  // ln(Γ(0.5)) = ln(sqrt(π))
  assert_true((lgamma(0.5) - @math.ln(@math.PI.sqrt())).abs() < 1.0e-10)
}

///|
test "beta: known values" {
  // B(1,1) = 1
  assert_true((beta(1.0, 1.0) - 1.0).abs() < 1.0e-10)
  // B(2,2) = 1/6
  assert_true((beta(2.0, 2.0) - 1.0 / 6.0).abs() < 1.0e-10)
  // B(0.5, 0.5) = π
  assert_true((beta(0.5, 0.5) - @math.PI).abs() < 1.0e-8)
}

///|
test "erf: known values" {
  // erf(0) = 0 (exact special case)
  assert_true(erf(0.0).abs() < 1.0e-10)
  // erf(1) ≈ 0.8427007929 (A&S accuracy ~1.5e-7)
  assert_true((erf(1.0) - 0.8427007929).abs() < 1.0e-6)
  // erf(-1) = -erf(1)
  assert_true((erf(-1.0) - -0.8427007929).abs() < 1.0e-6)
  // erf(2) ≈ 0.9953222650
  assert_true((erf(2.0) - 0.9953222650).abs() < 1.0e-6)
}

///|
test "erfc: complementarity" {
  assert_true((erfc(0.0) - 1.0).abs() < 1.0e-10)
  assert_true((erfc(1.0) - (1.0 - 0.8427007929)).abs() < 1.0e-6)
  assert_true((erfc(1.0) + erf(1.0) - 1.0).abs() < 1.0e-6)
}

///|
test "normal_cdf: known values" {
  // Φ(0) = 0.5 (exact via erf(0) = 0 special case)
  assert_true((normal_cdf(0.0) - 0.5).abs() < 1.0e-10)
  // Φ(1.96) ≈ 0.975
  assert_true((normal_cdf(1.96) - 0.975).abs() < 1.0e-4)
  // Φ(-1.96) ≈ 0.025
  assert_true((normal_cdf(-1.96) - 0.025).abs() < 1.0e-4)
  // Symmetry: Φ(-x) = 1 - Φ(x)
  assert_true((normal_cdf(1.0) + normal_cdf(-1.0) - 1.0).abs() < 1.0e-6)
}

///|
test "normal_pdf: known values" {
  // φ(0) = 1/sqrt(2π)
  assert_true((normal_pdf(0.0) - 1.0 / (2.0 * @math.PI).sqrt()).abs() < 1.0e-10)
  // φ is symmetric
  assert_true((normal_pdf(1.5) - normal_pdf(-1.5)).abs() < 1.0e-10)
  // φ(x) >= 0 for all x (underflows to 0 for extreme values)
  assert_true(normal_pdf(-100.0) >= 0.0)
  // For moderate x, φ(x) > 0
  assert_true(normal_pdf(-10.0) > 0.0)
}

///|
test "bessel_j0: known values" {
  // J0(0) = 1 (exact special case)
  assert_true((bessel_j0(0.0) - 1.0).abs() < 1.0e-10)
  // J0(π) ≈ -0.3042421776 (Numerical Recipes accuracy ~1e-8)
  assert_true((bessel_j0(@math.PI) - -0.3042421776).abs() < 1.0e-6)
  // J0 is even: J0(-x) = J0(x)
  assert_true((bessel_j0(5.0) - bessel_j0(-5.0)).abs() < 1.0e-10)
  // J0(1) ≈ 0.7651976866
  assert_true((bessel_j0(1.0) - 0.7651976866).abs() < 1.0e-6)
}
