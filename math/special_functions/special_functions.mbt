/// Special Mathematical Functions — Gamma, Erf, Bessel, and related functions.
///
/// This package provides high-accuracy implementations of special functions
/// used in statistics, physics, and engineering:
/// - **Gamma function** (Lanczos approximation, accuracy ~1e-15)
/// - **Log-Gamma** (for large arguments and to avoid overflow)
/// - **Beta function** B(a, b) = Γ(a)Γ(b)/Γ(a+b)
/// - **Error function** erf and complementary erfc (incomplete gamma, accuracy ~1e-15)
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
// Error function — full double precision via incomplete gamma function
// ---------------------------------------------------------------------------

///|
/// Regularized lower incomplete gamma function P(a, x) = γ(a, x) / Γ(a).
///
/// Uses series expansion for x < a+1 (fast convergence) and continued fraction
/// for x >= a+1 (Lentz's method). Achieves full double precision (~1e-15).
///
/// Reference: Numerical Recipes 3rd ed. §6.2.
fn gammp(a : Double, x : Double) -> Double {
  if x < 0.0 || a <= 0.0 {
    return 0.0
  }
  if x == 0.0 {
    return 0.0
  }
  if x < a + 1.0 {
    // Series representation: converges rapidly for x < a+1
    gser(a, x)
  } else {
    // Continued fraction: converges rapidly for x >= a+1
    1.0 - gcf(a, x)
  }
}

///|
/// Series representation of the lower incomplete gamma function.
///
/// γ(a, x) = x^a · e^(-x) · Σ_{n=0}^∞ Γ(a)/Γ(a+n+1) · x^n
fn gser(a : Double, x : Double) -> Double {
  let gln = lgamma(a)
  let mut ap = a
  let mut sum = 1.0 / a
  let mut del = sum
  for n = 0; n < 1000; n = n + 1 {
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
/// Continued fraction representation of the upper incomplete gamma function.
///
/// Uses Lentz's method (modified) for numerical stability.
/// Q(a, x) = Γ(a,x)/Γ(a) = e^(-x) · x^a · CF(a, x)
fn gcf(a : Double, x : Double) -> Double {
  let gln = lgamma(a)
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

///|
/// Error function erf(x).
///
/// Computes erf(x) = P(1/2, x²) using the regularized incomplete gamma
/// function, achieving full double precision (relative error < 1e-15).
///
/// This replaces the previous Abramowitz & Stegun 7.1.26 approximation
/// (1.5×10⁻⁷ error) with an exact implementation.
///
/// erf(0) = 0, erf(∞) = 1, erf(-x) = -erf(x).
pub fn erf(x : Double) -> Double {
  if x == 0.0 {
    return 0.0
  }
  if x < 0.0 {
    return -gammp(0.5, x * x)
  }
  gammp(0.5, x * x)
}

///|
/// Complementary error function erfc(x) = 1 - erf(x).
///
/// Computes erfc(x) = Q(1/2, x²) directly via the continued fraction
/// for x > 0.5, avoiding catastrophic cancellation that would occur
/// in 1 - erf(x) for large x.
pub fn erfc(x : Double) -> Double {
  if x == 0.0 {
    return 1.0
  }
  if x < 0.0 {
    return 1.0 + erf(-x)
  }
  // For x >= 0.5, compute Q(1/2, x²) directly (no cancellation)
  if x >= 0.5 {
    return gcf(0.5, x * x)
  }
  // For small x, 1 - erf(x) is safe
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
// Digamma and trigamma (polygamma functions of order 0 and 1)
// ---------------------------------------------------------------------------

///|
/// Digamma function ψ(x) = d/dx ln Γ(x).
///
/// Computed via the asymptotic expansion
/// ψ(x) = ln(x) - 1/(2x) - Σ_{k≥1} B_{2k} / (2k·x^{2k})
/// after shifting x upward with the recurrence ψ(x+1) = ψ(x) + 1/x until
/// x ≥ 8, where the expansion is accurate to machine precision. Negative
/// arguments use the reflection formula ψ(1 - x) - ψ(x) = π·tan(πx).
///
/// Returns 0.0 at the poles (non-positive integers).
pub fn digamma(x : Double) -> Double {
  if x.is_nan() {
    return x
  }
  if x <= 0.0 {
    // Reflection formula ψ(x) = ψ(1 - x) - π·tan(πx), with pole handling.
    let frac = x - x.floor()
    if frac.abs() < 1.0e-14 {
      return 0.0 // Non-positive integer pole: ψ → -∞; report 0 sentinel.
    }
    return digamma(1.0 - x) - @math.PI * @math.tan(@math.PI * x)
  }
  // Shift upward: ψ(x) = ψ(x + m) - Σ_{j=0}^{m-1} 1/(x + j).
  let mut result = 0.0
  let mut z = x
  while z < 8.0 {
    result = result - 1.0 / z
    z = z + 1.0
  }
  // Asymptotic expansion with Bernoulli numbers B2..B16.
  let inv = 1.0 / z
  let inv2 = inv * inv
  result = result +
    @math.ln(z) -
    0.5 * inv -
    inv2 *
      (
        1.0 / 12.0 -
        inv2 *
          (
            1.0 / 120.0 -
            inv2 * (1.0 / 252.0 - inv2 * (1.0 / 240.0 - inv2 * (1.0 / 132.0)))
          )
      )
  result
}

///|
/// Trigamma function ψ₁(x) = d²/dx² ln Γ(x) = d/dx ψ(x).
///
/// Computed via the asymptotic expansion
/// ψ₁(x) = 1/x + 1/(2x²) + Σ_{k≥1} B_{2k} / x^{2k+1}
/// after shifting with the recurrence ψ₁(x+1) = ψ₁(x) - 1/x² until x ≥ 12,
/// where the truncated expansion is accurate to ~1e-13. Negative arguments
/// use the reflection ψ₁(1 - x) + ψ₁(x) = π²/sin²(πx).
///
/// Returns 0.0 at the poles (non-positive integers).
pub fn trigamma(x : Double) -> Double {
  if x.is_nan() {
    return x
  }
  if x <= 0.0 {
    let frac = x - x.floor()
    if frac.abs() < 1.0e-14 {
      return 0.0 // Pole sentinel.
    }
    let s = @math.sin(@math.PI * x)
    return @math.PI * @math.PI / (s * s) - trigamma(1.0 - x)
  }
  // Shift upward: ψ₁(x) = ψ₁(x + m) + Σ_{j=0}^{m-1} 1/(x + j)².
  let mut result = 0.0
  let mut z = x
  while z < 12.0 {
    result = result + 1.0 / (z * z)
    z = z + 1.0
  }
  let inv = 1.0 / z
  let inv2 = inv * inv
  result +
  inv +
  0.5 * inv2 +
  inv * inv2 *
    (
      1.0 / 6.0 -
      inv2 * (1.0 / 30.0 - inv2 * (1.0 / 42.0 - inv2 * (1.0 / 30.0)))
    )
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
  assert_true(erf(0.0).abs() < 1.0e-15)
  // erf(1) = 0.8427007929497149 (full double precision)
  assert_true((erf(1.0) - 0.8427007929497149).abs() < 1.0e-14)
  // erf(-1) = -erf(1)
  assert_true((erf(-1.0) - -0.8427007929497149).abs() < 1.0e-14)
  // erf(2) = 0.9953222650189527
  assert_true((erf(2.0) - 0.9953222650189527).abs() < 1.0e-14)
  // erf(0.5) = 0.5204998778130465
  assert_true((erf(0.5) - 0.5204998778130465).abs() < 1.0e-14)
  // erf(3) = 0.9999779095030014
  assert_true((erf(3.0) - 0.9999779095030014).abs() < 1.0e-14)
  // erf(5) ≈ 0.9999999999984626
  assert_true((erf(5.0) - 0.9999999999984626).abs() < 1.0e-13)
  // erf(0.1) = 0.1124629160182849
  assert_true((erf(0.1) - 0.1124629160182849).abs() < 1.0e-14)
}

///|
test "erfc: complementarity" {
  assert_true((erfc(0.0) - 1.0).abs() < 1.0e-15)
  // erfc(1) = 1 - erf(1) = 0.1572992070502851
  assert_true((erfc(1.0) - 0.1572992070502851).abs() < 1.0e-14)
  // erfc + erf = 1
  assert_true((erfc(1.0) + erf(1.0) - 1.0).abs() < 1.0e-14)
  // erfc(2) = 0.0046777349810473
  assert_true((erfc(2.0) - 0.0046777349810473).abs() < 1.0e-14)
  // erfc(3) = 0.0000220904969986
  assert_true((erfc(3.0) - 0.0000220904969986).abs() < 1.0e-14)
  // erfc(-1) = 1 + erf(1) = 1.8427007929497149
  assert_true((erfc(-1.0) - 1.8427007929497149).abs() < 1.0e-14)
  // No catastrophic cancellation for large x
  assert_true((erfc(5.0) - 1.5374597944280349e-12).abs() < 1.0e-20)
}

///|
test "normal_cdf: known values" {
  // Φ(0) = 0.5
  assert_true((normal_cdf(0.0) - 0.5).abs() < 1.0e-15)
  // Φ(1.96) = 0.9750021048517795
  assert_true((normal_cdf(1.96) - 0.9750021048517795).abs() < 1.0e-13)
  // Φ(-1.96) = 0.02499789514822045
  assert_true((normal_cdf(-1.96) - 0.02499789514822045).abs() < 1.0e-13)
  // Φ(1) = 0.8413447460685429
  assert_true((normal_cdf(1.0) - 0.8413447460685429).abs() < 1.0e-13)
  // Symmetry: Φ(-x) = 1 - Φ(x)
  assert_true((normal_cdf(1.0) + normal_cdf(-1.0) - 1.0).abs() < 1.0e-14)
  // Φ(3) = 0.9986501019683699
  assert_true((normal_cdf(3.0) - 0.9986501019683699).abs() < 1.0e-13)
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

///|
test "digamma: known values" {
  // ψ(1) = -γ (Euler–Mascheroni constant)
  assert_true((digamma(1.0) - -0.5772156649015329).abs() < 1.0e-12)
  // ψ(2) = 1 - γ; ψ(3) = 1.5 - γ (recurrence)
  assert_true((digamma(2.0) - (1.0 - 0.5772156649015329)).abs() < 1.0e-12)
  assert_true((digamma(3.0) - (1.5 - 0.5772156649015329)).abs() < 1.0e-12)
  // ψ(0.5) = -γ - 2·ln(2)
  assert_true(
    (digamma(0.5) - (-0.5772156649015329 - 2.0 * @math.ln(2.0))).abs() < 1.0e-12,
  )
  // ψ(5.5) = ψ(1.5) + Σ 1/(k+0.5); ψ(1.5) = 2 - γ - 2·ln(2)
  let psi15 = 2.0 - 0.5772156649015329 - 2.0 * @math.ln(2.0)
  let psi55 = psi15 + 1.0 / 1.5 + 1.0 / 2.5 + 1.0 / 3.5 + 1.0 / 4.5
  assert_true((digamma(5.5) - psi55).abs() < 1.0e-12)
  // Reflection: ψ(-0.5) = ψ(1.5) - π·tan(-0.5π) = ψ(1.5) + π·tan(0.5π)… use
  // ψ(1.5) - ψ(0.5) = 2 and ψ(0.5) from above.
  assert_true((digamma(1.5) - psi15).abs() < 1.0e-12)
}

///|
test "trigamma: known values" {
  // ψ₁(1) = π²/6, ψ₁(0.5) = π²/2 (Basel sums)
  let pi2 = @math.PI * @math.PI
  assert_true((trigamma(1.0) - pi2 / 6.0).abs() < 1.0e-12)
  assert_true((trigamma(0.5) - pi2 / 2.0).abs() < 1.0e-12)
  // Recurrence: ψ₁(2) = π²/6 - 1, ψ₁(3) = π²/6 - 1.25
  assert_true((trigamma(2.0) - (pi2 / 6.0 - 1.0)).abs() < 1.0e-12)
  assert_true((trigamma(3.0) - (pi2 / 6.0 - 1.25)).abs() < 1.0e-12)
  // Consistency: ψ₁(x) ≈ (ψ(x + h) - ψ(x - h)) / (2h)
  let h = 1.0e-6
  let fd = (digamma(2.3 + h) - digamma(2.3 - h)) / (2.0 * h)
  assert_true((trigamma(2.3) - fd).abs() < 1.0e-7)
}
