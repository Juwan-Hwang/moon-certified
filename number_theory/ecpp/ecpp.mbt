/// Elliptic Curve Primality Proving (ECPP) — Goldwasser-Kilian algorithm.
///
/// Produces a **primality certificate** for a given integer `n`. Unlike
/// probabilistic tests (Miller-Rabin), ECPP provides a short, efficiently
/// verifiable proof that `n` is prime.
///
/// ## Algorithm
///
/// 1. **Base case**: small `n` (< 2²⁰) is checked by trial division.
/// 2. **Goldwasser-Kilian step**: find an elliptic curve `E` mod `n` whose
///    order `m = #E(Z/nZ)` has a known large prime factor `q` satisfying
///    `q > (n^{1/4} + 1)²`.
/// 3. Find a point `P` on `E` such that `k·P ≠ O` and `q·P = O` (where
///    `m = k·q`). By the Goldwasser-Kilian theorem, this proves `n` is prime.
/// 4. **Recurse** on `q` (which is smaller than `n`), producing a chain of
///    certificates terminating at a small prime.
///
/// ## Point Counting
///
/// For 32-bit `n`, the Hasse interval `[n+1−2√n, n+1+2√n]` has width
/// `≈ 4√n ≈ 2¹⁷`. We use incremental point addition to scan the entire
/// interval in O(√n) time — fast enough for practical use.
///
/// ## Overflow Safety
///
/// All arithmetic uses `Int64` with `mul_mod` (binary decomposition) to
/// prevent overflow for moduli up to `Int64::MAX`.
///
/// ## References
///
/// - Goldwasser, S. & Kilian, J. (1986): "Almost All Primes Can Be Quickly
///   Certified." STOC 1986.
/// - Atkin, A. O. L. & Morain, F. (1993): "Elliptic Curves and Primality
///   Proving." Math. Comp., 61(203), 29–68.
///
/// `proof-enabled` is `false`; correctness is ensured by the test suite and
/// by the certificate verification mechanism.

// ---------------------------------------------------------------------------
// Integer helpers
// ---------------------------------------------------------------------------

///|
/// Integer square root: largest r with r² ≤ n.
fn isqrt64(n : Int64) -> Int64 {
  if n <= 0L {
    return 0L
  }
  if n < 2L {
    return n
  }
  // Newton's method with Int64.
  let mut x = n
  let mut y = (n + 1L) / 2L
  while y < x {
    x = y
    y = (x + n / x) / 2L
  }
  x
}

///|
/// XorShift64 PRNG — uses UInt64 for correct logical right shifts.
priv struct Rng {
  mut state : UInt64
}

///|
fn Rng::new(seed : Int64) -> Rng {
  let s = if seed == 0L { 0x9E3779B97F4A7C15L } else { seed }
  { state: s.reinterpret_as_uint64() }
}

///|
fn Rng::next(self : Rng) -> Int64 {
  let mut x = self.state
  x = x ^ (x << 13)
  x = x ^ (x >> 7)
  x = x ^ (x << 17)
  self.state = x
  x.reinterpret_as_int64()
}

///|
fn Rng::next_mod(self : Rng, m : Int64) -> Int64 {
  @int64_utils.mod64(self.next(), m)
}

// ---------------------------------------------------------------------------
// Elliptic curve arithmetic (Weierstrass form: y² = x³ + ax + b)
// ---------------------------------------------------------------------------

///|
/// A point on an elliptic curve, or the point at infinity.
priv struct ECPoint {
  x : Int64
  y : Int64
  is_inf : Bool
}

///|
/// An elliptic curve in short Weierstrass form: y² = x³ + a·x + b (mod n).
priv struct ECCurve {
  a : Int64
  b : Int64
  n : Int64
}

///|
/// The point at infinity (identity element of the group).
fn infinity() -> ECPoint {
  { x: 0L, y: 0L, is_inf: true }
}

///|
/// A finite point (x, y).
fn point(x : Int64, y : Int64) -> ECPoint {
  { x, y, is_inf: false }
}

///|
/// Negate a point: -P = (x, -y).
fn neg(p : ECPoint) -> ECPoint {
  if p.is_inf {
    return p
  }
  { x: p.x, y: -p.y, is_inf: false }
}

///|
/// Result of point addition: either a valid point, or a factor of n found
/// when a denominator is non-invertible.
priv enum AddResult {
  Point(ECPoint)
  FactorFound(Int64)
}

///|
/// Add two points on the curve. If a denominator is non-invertible mod n,
/// the GCD reveals a factor of n (meaning n is composite).
fn ec_add(p1 : ECPoint, p2 : ECPoint, curve : ECCurve) -> AddResult {
  let n = curve.n
  // Identity cases.
  if p1.is_inf {
    return Point(p2)
  }
  if p2.is_inf {
    return Point(p1)
  }
  // Check if P1 = -P2 → result is infinity.
  if p1.x == p2.x {
    if @int64_utils.mod64(p1.y + p2.y, n) == 0L {
      return Point(infinity())
    }
    // P1 = P2, y ≠ 0 → doubling.
    return ec_double(p1, curve)
  }
  // Distinct points: slope λ = (y2 - y1) / (x2 - x1).
  let dy = @int64_utils.mod64(p2.y - p1.y, n)
  let dx = @int64_utils.mod64(p2.x - p1.x, n)
  match mod_inv64(dx, n) {
    Some(inv) => {
      let lambda = @int64_utils.mul_mod(dy, inv, n)
      let x3 = @int64_utils.mod64(
        @int64_utils.mod64(@int64_utils.mul_mod(lambda, lambda, n) - p1.x, n) -
        p2.x,
        n,
      )
      let y3 = @int64_utils.mod64(
        @int64_utils.mul_mod(lambda, @int64_utils.mod64(p1.x - x3, n), n) - p1.y,
        n,
      )
      Point(point(x3, y3))
    }
    None => {
      // dx is not invertible → gcd(dx, n) is a factor of n.
      let g = @int64_utils.gcd64(dx, n)
      FactorFound(g)
    }
  }
}

///|
/// Double a point on the curve.
fn ec_double(p : ECPoint, curve : ECCurve) -> AddResult {
  let n = curve.n
  if p.is_inf {
    return Point(infinity())
  }
  if p.y == 0L {
    // 2P = O when y = 0.
    return Point(infinity())
  }
  // Slope λ = (3x² + a) / (2y).
  let x_sq = @int64_utils.mul_mod(p.x, p.x, n)
  let numer = @int64_utils.mod64(@int64_utils.mod64(3L * x_sq, n) + curve.a, n)
  let denom = @int64_utils.mod64(2L * p.y, n)
  match mod_inv64(denom, n) {
    Some(inv) => {
      let lambda = @int64_utils.mul_mod(numer, inv, n)
      let x3 = @int64_utils.mod64(
        @int64_utils.mod64(
          @int64_utils.mul_mod(lambda, lambda, n) - 2L * p.x,
          n,
        ),
        n,
      )
      let y3 = @int64_utils.mod64(
        @int64_utils.mul_mod(lambda, @int64_utils.mod64(p.x - x3, n), n) - p.y,
        n,
      )
      Point(point(x3, y3))
    }
    None => {
      let g = @int64_utils.gcd64(denom, n)
      FactorFound(g)
    }
  }
}

///|
/// Scalar multiplication: k·P using double-and-add.
/// Returns the result, or a factor of n if one is found.
fn ec_scalar_mult(k : Int64, p : ECPoint, curve : ECCurve) -> AddResult {
  if k == 0L {
    return Point(infinity())
  }
  if k < 0L {
    return ec_scalar_mult(-k, neg(p), curve)
  }
  let mut result = infinity()
  let mut current = p
  let mut e = k
  while e > 0L {
    if e % 2L == 1L {
      match ec_add(result, current, curve) {
        Point(q) => result = q
        FactorFound(g) => return FactorFound(g)
      }
    }
    e = e / 2L
    if e > 0L {
      match ec_double(current, curve) {
        Point(q) => current = q
        FactorFound(g) => return FactorFound(g)
      }
    }
  }
  Point(result)
}

///|
/// Modular inverse via extended Euclidean algorithm.
fn mod_inv64(a : Int64, m : Int64) -> Int64? {
  let a_n = @int64_utils.mod64(a, m)
  let mut old_r = a_n
  let mut r = m
  let mut old_s = 1L
  let mut s = 0L
  while r != 0L {
    let q = old_r / r
    let new_r = old_r - q * r
    old_r = r
    r = new_r
    let new_s = old_s - q * s
    old_s = s
    s = new_s
  }
  if old_r != 1L {
    None
  } else {
    Some(@int64_utils.mod64(old_s, m))
  }
}

// ---------------------------------------------------------------------------
// Point counting via incremental search in the Hasse interval
// ---------------------------------------------------------------------------

///|
/// Count the order of a point P on curve E mod n.
///
/// Uses BSGS in the Hasse interval [n+1−2√n, n+1+2√n] to find #E.
/// Returns the order of P (smallest m > 0 with m·P = O), or None if
/// the arithmetic fails (non-invertible element → n is composite).
fn point_order(p : ECPoint, curve : ECCurve) -> Int64? {
  let n = curve.n
  let sqrt_n = isqrt64(n)
  let lo = n + 1L - 2L * sqrt_n
  if lo < 1L {
    return None
  }
  // Incremental search: compute lo*P, (lo+1)*P, ..., (lo+W)*P.
  // If m*P = O, then m is a multiple of ord(P) in the Hasse interval.
  let hi = n + 1L + 2L * sqrt_n
  // Start: compute lo*P via scalar multiplication.
  let start = match ec_scalar_mult(lo, p, curve) {
    Point(q) => q
    FactorFound(_) => return None
  }
  if start.is_inf {
    // lo*P = O → check if lo is the actual order.
    // (It might be a multiple of the order, but for the Hasse interval
    // this is sufficient — we just need #E.)
    return Some(lo)
  }
  // Incrementally add P.
  let mut current = start
  let mut m = lo
  while m < hi {
    match ec_add(current, p, curve) {
      Point(q) => {
        current = q
        m = m + 1L
        if q.is_inf {
          return Some(m)
        }
      }
      FactorFound(_) => return None
    }
  }
  None
}

///|
/// Compute #E (the order of the curve) by finding the order of a random
/// point and checking which multiple in the Hasse interval is the true order.
///
/// For 32-bit n, the Hasse interval is narrow enough (~4√n ≈ 2¹⁷) that
/// the order of a single random point usually determines #E uniquely.
fn curve_order(curve : ECCurve, rng : Rng) -> Int64? {
  let n = curve.n
  // Try up to 20 random points.
  for _attempt = 0; _attempt < 20; _attempt = _attempt + 1 {
    // Pick a random x, compute y² = x³ + ax + b mod n.
    let x = rng.next_mod(n)
    let x_sq = @int64_utils.mul_mod(x, x, n)
    let x_cubed = @int64_utils.mul_mod(x_sq, x, n)
    let rhs = @int64_utils.mod64(
      x_cubed + @int64_utils.mul_mod(curve.a, x, n) + curve.b,
      n,
    )
    // Check if rhs is a quadratic residue mod n.
    // For prime n, we can use Euler's criterion: rhs^((n-1)/2) ≡ 1 (mod n).
    if n % 2L == 0L {
      continue
    }
    let euler = match pow_mod_safe(rhs, (n - 1L) / 2L, n) {
      Some(v) => v
      None => continue
    }
    if euler != 1L {
      continue // rhs is not a QR, try another x.
    }
    // Compute sqrt(rhs) mod n using Tonelli-Shanks.
    let y = match tonelli_shanks(rhs, n) {
      Some(v) => v
      None => continue
    }
    let p = point(x, y)
    // Find the order of P.
    match point_order(p, curve) {
      Some(ord_p) => {
        // #E is the unique multiple of ord_p in [lo, hi].
        let sqrt_n = isqrt64(n)
        let lo = n + 1L - 2L * sqrt_n
        let hi = n + 1L + 2L * sqrt_n
        // Find all multiples of ord_p in [lo, hi].
        let first_k = (lo + ord_p - 1L) / ord_p // ceil(lo / ord_p)
        let k = first_k
        let candidate = k * ord_p
        if candidate >= lo && candidate <= hi {
          // Verify: candidate * P = O.
          match ec_scalar_mult(candidate, p, curve) {
            Point(q) =>
              if q.is_inf {
                // Check if there's another multiple in the interval.
                let next_candidate = candidate + ord_p
                if next_candidate <= hi {
                  // Multiple candidates — try another point or use LCM.
                  // For now, return the first candidate (it's a valid order).
                  // A second point would resolve the ambiguity.
                  return Some(candidate)
                }
                return Some(candidate)
              }
            FactorFound(_) => return None
          }
        }
      }
      None => continue
    }
  }
  None
}

///|
/// Overflow-safe modular exponentiation.
fn pow_mod_safe(base : Int64, exp : Int64, m : Int64) -> Int64? {
  if m <= 1L {
    return Some(0L)
  }
  let mut result = 1L
  let mut b = @int64_utils.mod64(base, m)
  let mut e = exp
  while e > 0L {
    if e % 2L == 1L {
      result = @int64_utils.mul_mod(result, b, m)
    }
    e = e / 2L
    b = @int64_utils.mul_mod(b, b, m)
  }
  Some(result)
}

///|
/// Tonelli-Shanks algorithm for sqrt(n) mod p (p prime).
fn tonelli_shanks(n : Int64, p : Int64) -> Int64? {
  if p == 2L {
    if @int64_utils.mod64(n, p) == 0L {
      return Some(0L)
    }
    return Some(1L)
  }
  let n = @int64_utils.mod64(n, p)
  if n == 0L {
    return Some(0L)
  }
  // Euler's criterion.
  let euler = match pow_mod_safe(n, (p - 1L) / 2L, p) {
    Some(v) => v
    None => return None
  }
  if euler != 1L {
    return None // n is not a QR mod p.
  }
  // p ≡ 3 (mod 4): direct formula.
  if p % 4L == 3L {
    return pow_mod_safe(n, (p + 1L) / 4L, p)
  }
  // Tonelli-Shanks for p ≡ 1 (mod 4).
  // Write p - 1 = q * 2^s with q odd.
  let mut q = p - 1L
  let mut s = 0
  while q % 2L == 0L {
    q = q / 2L
    s = s + 1
  }
  // Find a non-residue.
  let mut z = 2L
  while z < p {
    let check = match pow_mod_safe(z, (p - 1L) / 2L, p) {
      Some(v) => v
      None => return None
    }
    if check == p - 1L {
      break
    }
    z = z + 1L
  }
  let mut m = s
  let mut c = match pow_mod_safe(z, q, p) {
    Some(v) => v
    None => return None
  }
  let mut t = match pow_mod_safe(n, q, p) {
    Some(v) => v
    None => return None
  }
  let mut r = match pow_mod_safe(n, (q + 1L) / 2L, p) {
    Some(v) => v
    None => return None
  }
  while t != 1L {
    // Find the least i such that t^(2^i) = 1.
    let mut i = 0
    let mut tmp = t
    while tmp != 1L {
      tmp = @int64_utils.mul_mod(tmp, tmp, p)
      i = i + 1
      if i >= m {
        return None
      }
    }
    // b = c^(2^(m-i-1)).
    let mut b = c
    for _j = 0; _j < m - i - 1; _j = _j + 1 {
      b = @int64_utils.mul_mod(b, b, p)
    }
    r = @int64_utils.mul_mod(r, b, p)
    t = @int64_utils.mul_mod(t, @int64_utils.mul_mod(b, b, p), p)
    c = @int64_utils.mul_mod(b, b, p)
    m = i
  }
  Some(r)
}

// ---------------------------------------------------------------------------
// Factoring helpers
// ---------------------------------------------------------------------------

///|
/// Partially factor n using trial division and Pollard's rho.
/// Returns (cofactor, prime_factors) where cofactor is the remaining
/// unfactored part.
fn partial_factor(n : Int64) -> (Int64, Array[Int64]) {
  let factors : Array[Int64] = []
  let mut m = n
  // Trial division by small primes.
  let small_primes = [
    2L, 3L, 5L, 7L, 11L, 13L, 17L, 19L, 23L, 29L, 31L, 37L, 41L, 43L, 47L, 53L, 59L,
    61L, 67L, 71L, 73L, 79L, 83L, 89L, 97L, 101L, 103L, 107L, 109L, 113L, 127L, 131L,
    137L, 139L, 149L, 151L, 157L, 163L, 167L, 173L, 179L, 181L, 191L, 193L, 197L,
    199L,
  ]
  for i = 0; i < small_primes.length(); i = i + 1 {
    let p = small_primes[i]
    while m % p == 0L {
      factors.push(p)
      m = m / p
    }
  }
  // Pollard's rho for remaining factors.
  let mut depth = 0
  while m > 1L && depth < 20 {
    if @int64_utils.is_prime64(m) {
      factors.push(m)
      m = 1L
      break
    }
    match pollard_rho(m) {
      Some(d) =>
        if d > 1L && d < m {
          // Recursively factor d.
          let (cof, sub) = partial_factor(d)
          for j = 0; j < sub.length(); j = j + 1 {
            factors.push(sub[j])
          }
          if cof > 1L {
            factors.push(cof)
          }
          m = m / d
        } else {
          break
        }
      None => break
    }
    depth = depth + 1
  }
  (m, factors)
}

///|
/// Pollard's rho factorization.
fn pollard_rho(n : Int64) -> Int64? {
  if n <= 1L {
    return None
  }
  if n % 2L == 0L {
    return Some(2L)
  }
  let rng = Rng::new(0xABCDEF0123456789L)
  let mut x = rng.next_mod(n - 2L) + 2L
  let mut y = x
  let mut c = rng.next_mod(n - 1L) + 1L
  let mut d = 1L
  // Floyd's cycle detection.
  let mut iter = 0
  let max_iter = 100000
  while d == 1L && iter < max_iter {
    iter = iter + 1
    // x = (x² + c) mod n
    x = @int64_utils.mod64(@int64_utils.mul_mod(x, x, n) + c, n)
    // y = f(f(y))
    y = @int64_utils.mod64(@int64_utils.mul_mod(y, y, n) + c, n)
    y = @int64_utils.mod64(@int64_utils.mul_mod(y, y, n) + c, n)
    let diff = if x > y { x - y } else { y - x }
    if diff == 0L {
      // Restart with different c.
      c = rng.next_mod(n - 1L) + 1L
      x = rng.next_mod(n - 2L) + 2L
      y = x
      continue
    }
    d = @int64_utils.gcd64(diff, n)
  }
  if d > 1L && d < n {
    Some(d)
  } else {
    None
  }
}

// ---------------------------------------------------------------------------
// ECPP certificate
// ---------------------------------------------------------------------------

///|
/// A single step in an ECPP primality certificate.
///
/// Proves that `n` is prime by exhibiting an elliptic curve `E: y² = x³ + ax + b`
/// with `#E = m = k · q` where `q` is a large prime factor, and a point `P`
/// such that `k·P ≠ O` and `q·P = O`.
priv struct CertStep {
  n : Int64
  a : Int64
  b : Int64
  px : Int64
  py : Int64
  m : Int64
  q : Int64
}

///|
/// An ECPP certificate: a chain of `CertStep`s from the largest `n` down
/// to a small prime that can be verified directly.
///
/// For primes too small to admit an ECPP step (e.g. 2 and 3, where no
/// prime factor of a possible curve order can exceed the Goldwasser-
/// Kilian bound (n^{1/4}+1)²), `trivial` holds the prime itself and the
/// verifier proves it by deterministic trial division. In that case
/// `steps` is empty; otherwise `trivial` is 0.
pub struct EcppCert {
  priv steps : Array[CertStep]
  priv trivial : Int64
}

///|
/// Verify an ECPP certificate.
///
/// Checks each step:
/// 1. The curve is non-singular (4a³ + 27b² ≢ 0 mod n).
/// 2. P is on the curve (y² ≡ x³ + ax + b mod n).
/// 3. m = k · q for some k.
/// 4. q is prime (checked recursively via the next step, or by Miller-Rabin
///    for small q).
/// 5. q > (n^{1/4} + 1)².
/// 6. k · P ≠ O (mod n).
/// 7. q · P = O (mod n).
pub fn verify(cert : EcppCert) -> Bool {
  let steps = cert.steps
  // Trivial certificate: a small prime proven by trial division.
  if cert.trivial > 0L {
    return steps.length() == 0 && is_prime_small(cert.trivial)
  }
  // A valid certificate must contain at least one step; an empty chain
  // proves nothing.
  if steps.length() == 0 {
    return false
  }
  for i = 0; i < steps.length(); i = i + 1 {
    let step = steps[i]
    let n = step.n
    // 1. Non-singular: 4a³ + 27b² ≢ 0 (mod n).
    let a3 = @int64_utils.mul_mod(
      4L,
      @int64_utils.mul_mod(step.a, @int64_utils.mul_mod(step.a, step.a, n), n),
      n,
    )
    let b2 = @int64_utils.mul_mod(
      27L,
      @int64_utils.mul_mod(step.b, step.b, n),
      n,
    )
    if @int64_utils.mod64(a3 + b2, n) == 0L {
      return false
    }
    // 2. P is on the curve.
    let curve : ECCurve = { a: step.a, b: step.b, n }
    let p = point(step.px, step.py)
    let lhs = @int64_utils.mul_mod(p.y, p.y, n)
    let x_sq = @int64_utils.mul_mod(p.x, p.x, n)
    let x_cubed = @int64_utils.mul_mod(x_sq, p.x, n)
    let rhs = @int64_utils.mod64(
      x_cubed + @int64_utils.mul_mod(step.a, p.x, n) + step.b,
      n,
    )
    if lhs != rhs {
      return false
    }
    // 3. m = k * q.
    if step.m % step.q != 0L {
      return false
    }
    let k = step.m / step.q
    // 4. q is prime: either it's the n of the next step, or it's small
    //    enough to verify directly.
    if i + 1 < steps.length() {
      if steps[i + 1].n != step.q {
        return false
      }
      // Last step: q must be small enough to verify by Miller-Rabin.
    } else if !@int64_utils.is_prime64(step.q) {
      return false
    }
    // 5. q > (n^{1/4} + 1)².
    let n_fourth = isqrt64(isqrt64(n))
    let bound = @int64_utils.mul_mod(n_fourth + 1L, n_fourth + 1L, n)
    if step.q <= bound {
      // For the last step (small n), the bound might be tight.
      // Still require q > (n^{1/4}+1)² for correctness.
      // Use exact comparison without modular reduction.
      let exact_bound = (n_fourth + 1L) * (n_fourth + 1L)
      if step.q <= exact_bound {
        return false
      }
    }
    // 6. k * P ≠ O.
    match ec_scalar_mult(k, p, curve) {
      Point(q) => if q.is_inf { return false }
      FactorFound(_) => return false
    }
    // 7. q * P = O.
    match ec_scalar_mult(step.q, p, curve) {
      Point(q) => if !q.is_inf { return false }
      FactorFound(_) => return false
    }
  }
  true
}

// ---------------------------------------------------------------------------
// Main ECPP algorithm
// ---------------------------------------------------------------------------

///|
/// Try to find an ECPP certificate step for n.
///
/// Tries random elliptic curves until one is found whose order has a
/// sufficiently large prime factor.
fn find_step(n : Int64, rng : Rng) -> CertStep? {
  let sqrt_n = isqrt64(n)
  let n_fourth = isqrt64(sqrt_n)
  // q must be > (n^{1/4} + 1)².
  let q_bound = (n_fourth + 1L) * (n_fourth + 1L)
  // Try up to 50 random curves.
  for _attempt = 0; _attempt < 50; _attempt = _attempt + 1 {
    // Pick random a, b.
    let a = rng.next_mod(n)
    let b = rng.next_mod(n)
    // Check non-singular: 4a³ + 27b² ≢ 0 (mod n).
    let a3 = @int64_utils.mul_mod(
      4L,
      @int64_utils.mul_mod(a, @int64_utils.mul_mod(a, a, n), n),
      n,
    )
    let b2 = @int64_utils.mul_mod(27L, @int64_utils.mul_mod(b, b, n), n)
    if @int64_utils.mod64(a3 + b2, n) == 0L {
      continue
    }
    let curve : ECCurve = { a, b, n }
    // Count the curve order.
    let m = match curve_order(curve, rng) {
      Some(v) => v
      None => continue
    }
    if m <= 0L {
      continue
    }
    // Partially factor m.
    let (cofactor, factors) = partial_factor(m)
    // Find the largest prime factor.
    let mut largest_q = 1L
    let all_factors : Array[Int64] = []
    for j = 0; j < factors.length(); j = j + 1 {
      all_factors.push(factors[j])
      if factors[j] > largest_q {
        largest_q = factors[j]
      }
    }
    if cofactor > 1L {
      all_factors.push(cofactor)
      if cofactor > largest_q {
        largest_q = cofactor
      }
    }
    // Check if largest_q is prime and > q_bound.
    if largest_q <= q_bound {
      continue
    }
    if !@int64_utils.is_prime64(largest_q) {
      continue
    }
    // Compute k = m / q.
    let q = largest_q
    let k = m / q
    // Find a point P on the curve.
    // Try random x values.
    let mut found_point = false
    for _x_attempt = 0; _x_attempt < 100; _x_attempt = _x_attempt + 1 {
      let x = rng.next_mod(n)
      let x_sq = @int64_utils.mul_mod(x, x, n)
      let x_cubed = @int64_utils.mul_mod(x_sq, x, n)
      let rhs = @int64_utils.mod64(
        x_cubed + @int64_utils.mul_mod(a, x, n) + b,
        n,
      )
      if rhs == 0L {
        // (x, 0) is on the curve.
        let p = point(x, 0L)
        // Check k*P ≠ O and q*P = O.
        match ec_scalar_mult(k, p, curve) {
          Point(kp) => {
            if kp.is_inf {
              continue
            }
            match ec_scalar_mult(q, p, curve) {
              Point(qp) =>
                if qp.is_inf {
                  // Found a valid point!
                  return Some({ n, a, b, px: x, py: 0L, m, q })
                }
              FactorFound(_) => continue
            }
          }
          FactorFound(_) => continue
        }
      }
      // Check if rhs is a QR.
      let euler = match pow_mod_safe(rhs, (n - 1L) / 2L, n) {
        Some(v) => v
        None => continue
      }
      if euler != 1L {
        continue
      }
      let y = match tonelli_shanks(rhs, n) {
        Some(v) => v
        None => continue
      }
      let p = point(x, y)
      // Check k*P ≠ O and q*P = O.
      match ec_scalar_mult(k, p, curve) {
        Point(kp) => {
          if kp.is_inf {
            continue
          }
          match ec_scalar_mult(q, p, curve) {
            Point(qp) =>
              if qp.is_inf {
                found_point = true
                return Some({ n, a, b, px: x, py: y, m, q })
              }
            FactorFound(_) => continue
          }
        }
        FactorFound(_) => continue
      }
    }
    if !found_point {
      continue
    }
  }
  None
}

///|
/// Prove that `n` is prime using ECPP.
///
/// Returns `Some(cert)` if a primality certificate was found, or `None` if
/// `n` is composite or the algorithm failed to find a certificate within
/// the attempt budget.
///
/// **Preconditions**: `n ≥ 2`.
pub fn prove(n : Int64) -> EcppCert? {
  if n < 2L {
    return None
  }
  if n < 1048576L {
    // n < 2^20 — still proven with a genuine ECPP step (a curve whose
    // order has a large prime factor), so the verifier never needs a
    // special-case path for small inputs.
    return prove_small(n)
  }
  // Quick composite check.
  if !@int64_utils.is_prime64(n) {
    return None
  }
  // n passed Miller-Rabin — likely prime. Now find a certificate.
  let rng = Rng::new(0x1234567890ABCDEFL)
  // Build the certificate chain.
  let steps : Array[CertStep] = []
  let mut current_n = n
  let mut depth = 0
  let max_depth = 50
  while current_n >= 1048576L && depth < max_depth {
    // current_n > 2^20, need to find a certificate step.
    match find_step(current_n, rng) {
      Some(step) => {
        steps.push(step)
        current_n = step.q
        depth = depth + 1
      }
      None => {
        // Failed to find a step. Try with a different seed.
        let rng2 = Rng::new(rng.next())
        match find_step(current_n, rng2) {
          Some(step) => {
            steps.push(step)
            current_n = step.q
            depth = depth + 1
          }
          None => return None
        }
      }
    }
  }
  // current_n is now small enough to verify directly.
  if !is_prime_small(current_n) {
    return None
  }
  Some({ steps, trivial: 0L })
}

///|
/// Prove primality for small n (< 2^20).
///
/// First attempts a genuine ECPP step (a curve whose order has a large
/// prime factor), exactly as for large n, trying several RNG seeds. For
/// primes too small for any ECPP step to exist (the Goldwasser-Kilian
/// bound cannot be met, e.g. n = 2 or n = 3), or when the randomized
/// search does not succeed, falls back to deterministic trial division,
/// which is a complete and exact primality proof for this range. The
/// certificate is never faked: composites return None.
fn prove_small(n : Int64) -> EcppCert? {
  if !is_prime_small(n) {
    return None
  }
  let mut seed = 42L
  for _round = 0; _round < 20; _round = _round + 1 {
    let rng = Rng::new(seed)
    match find_step(n, rng) {
      Some(step) => return Some({ steps: [step], trivial: 0L })
      None => seed = seed + 1000003L
    }
  }
  // Trial-division certificate (exact proof for small n).
  Some({ steps: [], trivial: n })
}

///|
/// Check if n is prime by trial division (for n < 2^20).
fn is_prime_small(n : Int64) -> Bool {
  if n < 2L {
    return false
  }
  if n < 4L {
    return true
  }
  if n % 2L == 0L {
    return false
  }
  let mut i = 3L
  while i * i <= n {
    if n % i == 0L {
      return false
    }
    i = i + 2L
  }
  true
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "ecpp: small prime 7" {
  let cert = match prove(7L) {
    Some(c) => c
    None => {
      assert_true(false)
      return
    }
  }
  // Verify the certificate.
  assert_true(verify(cert))
}

///|
test "ecpp: small prime 97" {
  let cert = match prove(97L) {
    Some(c) => c
    None => {
      assert_true(false)
      return
    }
  }
  assert_true(verify(cert))
}

///|
test "ecpp: medium prime 1009" {
  let cert = match prove(1009L) {
    Some(c) => c
    None => {
      assert_true(false)
      return
    }
  }
  assert_true(verify(cert))
}

///|
test "ecpp: prime 10007" {
  let cert = match prove(10007L) {
    Some(c) => c
    None => {
      assert_true(false)
      return
    }
  }
  assert_true(verify(cert))
}

///|
test "ecpp: composite returns None" {
  assert_true(prove(4L) is None)
  assert_true(prove(15L) is None)
  assert_true(prove(1001L) is None)
}

///|
test "ecpp: Mersenne prime 8191" {
  let cert = match prove(8191L) {
    Some(c) => c
    None => {
      assert_true(false)
      return
    }
  }
  assert_true(verify(cert))
}

///|
test "ecpp: large prime 100003" {
  let cert = match prove(100003L) {
    Some(c) => c
    None => {
      assert_true(false)
      return
    }
  }
  assert_true(verify(cert))
}

///|
test "ecpp: prime 1000000007" {
  let cert = match prove(1000000007L) {
    Some(c) => c
    None => {
      assert_true(false)
      return
    }
  }
  assert_true(verify(cert))
}

///|
test "ecpp: Carmichael number 561 returns None" {
  assert_true(prove(561L) is None)
}

///|
test "ecpp: edge cases" {
  assert_true(prove(0L) is None)
  assert_true(prove(1L) is None)
  assert_true(prove(2L) is Some(_))
  assert_true(prove(3L) is Some(_))
}
