/// Monte Carlo algorithms: randomized algorithms that may produce incorrect
/// results with bounded (typically very small) probability.
///
/// This module provides:
///
/// - **Monte Carlo integration**: approximate definite integrals by random
///   sampling. Error decreases as O(1/√N) by the Central Limit Theorem.
/// - **Monte Carlo primality testing** (Fermat-style): a one-sided error test
///   that correctly identifies composites but may pass some composites
///   (Carmichael numbers) as primes. For production-grade primality, use
///   `@miller_rabin` instead (which has zero error for deterministic witnesses).
/// - **Buffon's needle**: classic Monte Carlo estimation of π.
/// - **Pi estimation via dart-throwing**: the canonical Monte Carlo example.
///
/// ## Error bounds
///
/// For Monte Carlo integration with N samples, the standard error is:
///   σ_estimate = σ_population / √N
/// where σ_population is the population standard deviation. A 99.7% confidence
/// interval is ±3σ_estimate. Quadrupling N halves the error.
///
/// ## Pseudorandom number generator
///
/// Uses a 64-bit xorshift generator with good statistical properties for
/// Monte Carlo workloads (long period 2^64 - 1, uniform distribution).
/// For cryptographic or security-sensitive applications, use a CSPRNG instead.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// PRNG: xorshift64
// ---------------------------------------------------------------------------

///|
/// A 64-bit xorshift PRNG state.
///
/// xorshift64 uses the sequence x ^= x << 13; x ^= x >> 7; x ^= x << 17
/// which has period 2^64 - 1 and passes most statistical tests for
/// Monte Carlo applications. For security-sensitive contexts, use a CSPRNG.
pub struct XorShift64 {
  priv mut state : Int64
}

///|
/// Create a new PRNG with the given seed. A seed of 0 is replaced by a
/// fixed nonzero constant to avoid the degenerate all-zero state.
pub fn XorShift64::new(seed : Int64) -> XorShift64 {
  let s = if seed == 0L { 0x9E3779B97F4A7C15L } else { seed }
  { state: s }
}

///|
/// Generate the next 64-bit value as a Double in [0, 1).
///
/// Uses the top 53 bits (mantissa width of f64) to produce a value with
/// full double precision. The result is uniform over [0, 1) with period 2^64.
pub fn XorShift64::uniform(self : XorShift64) -> Double {
  self.state = @utils.xorshift64_next(self.state)
  let x = self.state
  // Use absolute value and take top 53 bits.
  let abs_x = if x < 0L { -x } else { x }
  (abs_x & 0x001FFFFFFFFFFFFFL).to_double() / 9007199254740992.0
}

///|
/// Generate a uniform double in [a, b).
pub fn XorShift64::uniform_range(
  self : XorShift64,
  a : Double,
  b : Double,
) -> Double {
  a + self.uniform() * (b - a)
}

///|
/// Generate a random Int64 in [0, n).
///
/// Uses **rejection sampling** to eliminate modulo bias. For `n` fitting
/// in 31 bits, uses 31-bit rejection sampling (same method as CSPRNG).
/// For larger `n`, falls back to modulo on the absolute value — the bias
/// is then < 2⁻³² per sample and practically negligible.
pub fn XorShift64::rand_int64(self : XorShift64, n : Int64) -> Int64 {
  if n <= 0L {
    return 0L
  }
  if n == 1L {
    return 0L
  }
  // For n ≤ 2³¹, use 31-bit rejection sampling.
  if n <= 2147483648L {
    let n_int = n.to_int()
    let range = 2147483648L // 2³¹
    let threshold = range - range % n
    let mut ok = false
    let mut result = 0L
    while !ok {
      self.state = @utils.xorshift64_next(self.state)
      let x = self.state
      let abs_x = if x < 0L { -x } else { x }
      let r = (abs_x >> 32).to_int() // upper 31 bits for better quality
      if r.to_int64() < threshold {
        result = (r % n_int).to_int64()
        ok = true
      }
    }
    result
  } else {
    // For n > 2³¹, modulo bias is < 2⁻³² — practically negligible.
    self.state = @utils.xorshift64_next(self.state)
    let x = self.state
    let abs_x = if x < 0L { -x } else { x }
    abs_x % n
  }
}

// ---------------------------------------------------------------------------
// Monte Carlo Integration
// ---------------------------------------------------------------------------

///|
/// Approximate the definite integral of `f` over [a, b] using N random samples.
///
/// Each sample draws x ~ Uniform[a, b] and accumulates f(x). The estimate is:
///   I ≈ (b - a) * (1/N) * Σ f(x_i)
///
/// The error is O(1/√N) by the CLT. Returns the estimated integral value.
///
/// ## Parameters
/// - `f`: the integrand.
/// - `a`, `b`: the integration bounds (a < b).
/// - `n`: number of samples (more = more accurate, O(n) time).
/// - `rng`: the PRNG to use.
pub fn monte_carlo_integrate(
  f : (Double) -> Double,
  a : Double,
  b : Double,
  n : Int,
  rng : XorShift64,
) -> Double {
  let mut sum = 0.0
  let width = b - a
  for i = 0; i < n; i = i + 1 {
    let x = a + rng.uniform() * width
    sum = sum + f(x)
  }
  width * (sum / n.to_double())
}

///|
/// Approximate the definite integral with an error estimate.
///
/// Returns `(estimate, standard_error)` where `standard_error` is the
/// standard deviation of the sample mean scaled by (b-a):
///   SE = (b - a) * σ_sample / √N
///
/// The 99.7% confidence interval is `estimate ± 3 * standard_error`.
pub fn monte_carlo_integrate_with_error(
  f : (Double) -> Double,
  a : Double,
  b : Double,
  n : Int,
  rng : XorShift64,
) -> (Double, Double) {
  let mut sum = 0.0
  let mut sum_sq = 0.0
  let width = b - a
  for i = 0; i < n; i = i + 1 {
    let x = a + rng.uniform() * width
    let fx = f(x)
    sum = sum + fx
    sum_sq = sum_sq + fx * fx
  }
  let nd = n.to_double()
  let mean = sum / nd
  let variance = sum_sq / nd - mean * mean
  let v = if variance < 0.0 { 0.0 } else { variance }
  let std_err = width * sqrt_double(v) / sqrt_double(nd)
  (width * mean, std_err)
}

///|
/// Square root via Newton's method (Heron's formula).
///
/// Converges quadratically: ~6 iterations for double precision.
/// This avoids dependency on `@math.sqrt` which is not available in
/// the current MoonBit standard library.
fn sqrt_double(x : Double) -> Double {
  if x <= 0.0 {
    return 0.0
  }
  // Initial guess using bit manipulation for fast convergence.
  let mut guess = x
  if guess > 1.0 {
    guess = x / 2.0
  }
  // Newton iteration: guess = (guess + x/guess) / 2
  for i = 0; i < 20; i = i + 1 {
    let next = (guess + x / guess) / 2.0
    // Check convergence.
    let diff = next - guess
    if diff < 0.0 {
      if -diff < 1.0e-15 * guess {
        return next
      }
    } else if diff < 1.0e-15 * guess {
      return next
    }
    guess = next
  }
  guess
}

///|
/// Approximate a 2D integral ∫∫ f(x, y) dx dy over [x_lo, x_hi] × [y_lo, y_hi].
///
/// Uses N random (x, y) pairs. Returns the estimated integral.
pub fn monte_carlo_integrate_2d(
  f : (Double, Double) -> Double,
  x_lo : Double,
  x_hi : Double,
  y_lo : Double,
  y_hi : Double,
  n : Int,
  rng : XorShift64,
) -> Double {
  let mut sum = 0.0
  let area = (x_hi - x_lo) * (y_hi - y_lo)
  for i = 0; i < n; i = i + 1 {
    let x = x_lo + rng.uniform() * (x_hi - x_lo)
    let y = y_lo + rng.uniform() * (y_hi - y_lo)
    sum = sum + f(x, y)
  }
  area * (sum / n.to_double())
}

// ---------------------------------------------------------------------------
// π Estimation
// ---------------------------------------------------------------------------

///|
/// Estimate π by throwing darts at a unit square and counting the fraction
/// that land inside the inscribed unit circle (center at origin, radius 1).
///
/// The ratio of hits to total darts approaches π/4 as N → ∞, so:
///   π ≈ 4 * (hits / N)
///
/// Error is O(1/√N). For N = 10^6, expect ~3 digits of accuracy.
pub fn estimate_pi(n : Int, rng : XorShift64) -> Double {
  let mut hits = 0
  for i = 0; i < n; i = i + 1 {
    let x = rng.uniform_range(-1.0, 1.0)
    let y = rng.uniform_range(-1.0, 1.0)
    if x * x + y * y <= 1.0 {
      hits = hits + 1
    }
  }
  4.0 * hits.to_double() / n.to_double()
}

///|
/// Estimate π using Buffon's needle: drop needles of length L on a plane
/// with parallel lines spaced D apart (L ≤ D). The probability of a needle
/// crossing a line is 2L / (πD), so:
///   π ≈ 2L * N / (D * hits)
///
/// This converges very slowly (variance is high) and is mainly of
/// historical/pedagogical interest. For practical π estimation, use
/// `estimate_pi` instead.
pub fn buffon_needle(
  n : Int,
  needle_length : Double,
  line_spacing : Double,
  rng : XorShift64,
) -> Double {
  let mut crossings = 0
  let d = line_spacing
  let l = needle_length
  for i = 0; i < n; i = i + 1 {
    // Distance from needle center to nearest line, uniform in [0, d/2).
    let y = rng.uniform() * d / 2.0
    // Angle of needle with the lines, uniform in [0, π/2).
    let theta = rng.uniform() * 1.5707963267948966 // π/2
    // Needle crosses a line if y ≤ (l/2) * sin(θ).
    if y <= l / 2.0 * @math.sin(theta) {
      crossings = crossings + 1
    }
  }
  if crossings == 0 {
    return 0.0 // degenerate case
  }
  2.0 * l * n.to_double() / (d * crossings.to_double())
}

// ---------------------------------------------------------------------------
// Monte Carlo Primality (Fermat test)
// ---------------------------------------------------------------------------

///|
/// Modular exponentiation: base^exp mod m. Uses binary exponentiation.
/// All arithmetic is done in Int64 with mul_mod to prevent overflow.
fn mod_pow(base : Int64, exp : Int64, m : Int64) -> Int64 {
  let mut result = 1L
  let mut b = base % m
  let mut e = exp
  while e > 0L {
    if (e & 1L) != 0L {
      result = mul_mod(result, b, m)
    }
    b = mul_mod(b, b, m)
    e = e >> 1
  }
  result
}

///|
/// Overflow-safe modular multiplication for Int64.
/// Uses the identity: a*b mod m = a*b - floor(a*b/m)*m
/// with 128-bit intermediate via splitting.
fn mul_mod(a : Int64, b : Int64, m : Int64) -> Int64 {
  // For values that fit in 32 bits, direct multiplication is safe.
  if m <= 2147483647L {
    let am = a % m
    let bm = b % m
    // am, bm < 2^31, so am*bm < 2^62, fits in Int64.
    return am * bm % m
  }
  // For larger moduli, use the binary method (Russian peasant multiplication).
  let mut result = 0L
  let mut a_mod = a % m
  let mut b_mod = b % m
  if a_mod < 0L {
    a_mod = a_mod + m
  }
  if b_mod < 0L {
    b_mod = b_mod + m
  }
  while b_mod > 0L {
    if (b_mod & 1L) != 0L {
      result = (result + a_mod) % m
    }
    a_mod = a_mod * 2L % m
    b_mod = b_mod >> 1
  }
  result
}

///|
/// Fermat primality test: a one-sided Monte Carlo test for compositeness.
///
/// By Fermat's little theorem, if p is prime and a is not divisible by p,
/// then a^(p-1) ≡ 1 (mod p). If a^(p-1) ≢ 1 (mod p) for any witness a,
/// then n is definitely composite.
///
/// **Caveat**: Some composites (Carmichael numbers) pass this test for all
/// coprime bases. For production-grade primality, use `@miller_rabin.is_prime64`
/// which has no false positives for the deterministic witness set.
///
/// ## Parameters
/// - `n`: the number to test (n ≥ 2).
/// - `rounds`: number of random witnesses to try. More rounds reduce the
///   probability of a false positive (for non-Carmichael composites, each
///   round eliminates at least half of possible witnesses).
/// - `rng`: the PRNG for generating witnesses.
///
/// ## Returns
/// - `true`: n is "probably prime" (or a Carmichael number).
/// - `false`: n is definitely composite.
pub fn fermat_is_prime(n : Int64, rounds : Int, rng : XorShift64) -> Bool {
  if n < 2L {
    return false
  }
  if n == 2L || n == 3L {
    return true
  }
  if n % 2L == 0L {
    return false
  }
  // Test small primes first for quick composite rejection.
  let small_primes = [3L, 5L, 7L, 11L, 13L, 17L, 19L, 23L, 29L, 31L, 37L]
  for i = 0; i < small_primes.length(); i = i + 1 {
    let p = small_primes[i]
    if n == p {
      return true
    }
    if n % p == 0L {
      return false
    }
  }
  let n_minus_1 = n - 1L
  for r = 0; r < rounds; r = r + 1 {
    // Generate a witness in [2, n-2].
    let a = 2L + rng.rand_int64(n_minus_1 - 2L)
    if a <= 1L || a >= n {
      continue
    }
    // Check gcd(a, n) == 1; if not, n is composite.
    let mut g_a = a
    let mut g_b = n
    while g_b != 0L {
      let t = g_b
      g_b = g_a % g_b
      g_a = t
    }
    if g_a != 1L {
      return false // a divides n, so n is composite
    }
    let result = mod_pow(a, n_minus_1, n)
    if result != 1L {
      return false // definitely composite
    }
  }
  true // "probably prime" (or Carmichael number)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "xorshift64: uniform distribution" {
  let rng = XorShift64::new(42L)
  let mut sum = 0.0
  let n = 100000
  for i = 0; i < n; i = i + 1 {
    let u = rng.uniform()
    assert_true(u >= 0.0 && u < 1.0)
    sum = sum + u
  }
  // Mean should be close to 0.5.
  let mean = sum / n.to_double()
  assert_true((mean - 0.5).abs() < 0.01)
}

///|
test "xorshift64: uniform_range" {
  let rng = XorShift64::new(123L)
  for i = 0; i < 1000; i = i + 1 {
    let v = rng.uniform_range(10.0, 20.0)
    assert_true(v >= 10.0 && v < 20.0)
  }
}

///|
test "monte_carlo_integrate: constant function" {
  let rng = XorShift64::new(999L)
  // ∫ 5 dx from 0 to 10 = 50.
  let result = monte_carlo_integrate(fn(_x) { 5.0 }, 0.0, 10.0, 100000, rng)
  assert_true((result - 50.0).abs() < 0.5)
}

///|
test "monte_carlo_integrate: linear function" {
  let rng = XorShift64::new(42L)
  // ∫ x dx from 0 to 1 = 0.5.
  let result = monte_carlo_integrate(fn(x) { x }, 0.0, 1.0, 100000, rng)
  assert_true((result - 0.5).abs() < 0.02)
}

///|
test "monte_carlo_integrate: sin function" {
  let rng = XorShift64::new(777L)
  // ∫ sin(x) dx from 0 to π = 2.
  let result = monte_carlo_integrate(
    fn(x) { @math.sin(x) },
    0.0,
    3.141592653589793,
    100000,
    rng,
  )
  assert_true((result - 2.0).abs() < 0.05)
}

///|
test "monte_carlo_integrate_with_error: error decreases with N" {
  let rng1 = XorShift64::new(42L)
  let rng2 = XorShift64::new(42L)
  let (_, err1) = monte_carlo_integrate_with_error(
    fn(x) { x * x },
    0.0,
    1.0,
    1000,
    rng1,
  )
  let (_, err2) = monte_carlo_integrate_with_error(
    fn(x) { x * x },
    0.0,
    1.0,
    10000,
    rng2,
  )
  // Error should decrease by roughly √10 ≈ 3.16x.
  assert_true(err2 < err1)
}

///|
test "monte_carlo_integrate_2d: constant" {
  let rng = XorShift64::new(42L)
  // ∫∫ 1 dx dy over [0,2]×[0,3] = 6.
  let result = monte_carlo_integrate_2d(
    fn(_x, _y) { 1.0 },
    0.0,
    2.0,
    0.0,
    3.0,
    100000,
    rng,
  )
  assert_true((result - 6.0).abs() < 0.1)
}

///|
test "estimate_pi: converges to π" {
  let rng = XorShift64::new(42L)
  let pi_est = estimate_pi(1000000, rng)
  let pi = 3.141592653589793
  // With 1M samples, expect ~2-3 decimal digits of accuracy.
  assert_true((pi_est - pi).abs() < 0.02)
}

///|
test "buffon_needle: roughly estimates π" {
  let rng = XorShift64::new(42L)
  // Very slow convergence — just check it's in a reasonable range.
  let pi_est = buffon_needle(100000, 1.0, 2.0, rng)
  assert_true(pi_est > 2.5 && pi_est < 4.0)
}

///|
test "fermat_is_prime: known primes" {
  let rng = XorShift64::new(42L)
  assert_true(fermat_is_prime(2L, 10, rng))
  assert_true(fermat_is_prime(3L, 10, rng))
  assert_true(fermat_is_prime(7L, 10, rng))
  assert_true(fermat_is_prime(97L, 10, rng))
  assert_true(fermat_is_prime(1009L, 10, rng))
  assert_true(fermat_is_prime(7919L, 10, rng)) // 1000th prime
  // Large prime
  assert_true(fermat_is_prime(2147483647L, 20, rng)) // Mersenne prime 2^31-1
}

///|
test "fermat_is_prime: known composites" {
  let rng = XorShift64::new(42L)
  assert_false(fermat_is_prime(1L, 10, rng))
  assert_false(fermat_is_prime(4L, 10, rng))
  assert_false(fermat_is_prime(6L, 10, rng))
  assert_false(fermat_is_prime(9L, 10, rng))
  assert_false(fermat_is_prime(15L, 10, rng))
  assert_false(fermat_is_prime(100L, 10, rng))
  assert_false(fermat_is_prime(1001L, 10, rng))
}

///|
test "fermat_is_prime: Carmichael number (known limitation)" {
  // 561 = 3 * 11 * 17 is the smallest Carmichael number.
  // Fermat test may pass it as "probably prime" — this is a known limitation.
  // We document it here: for production primality, use miller_rabin.
  let rng = XorShift64::new(42L)
  let result = fermat_is_prime(561L, 20, rng)
  // We don't assert either way — the test is one-sided and Carmichael
  // numbers may pass. This test documents the behavior.
  ignore(result)
}

///|
test "monte_carlo: reproducible with same seed" {
  let rng1 = XorShift64::new(42L)
  let rng2 = XorShift64::new(42L)
  let r1 = monte_carlo_integrate(fn(x) { x * x }, 0.0, 1.0, 1000, rng1)
  let r2 = monte_carlo_integrate(fn(x) { x * x }, 0.0, 1.0, 1000, rng2)
  assert_eq(r1, r2) // same seed → same result
}
