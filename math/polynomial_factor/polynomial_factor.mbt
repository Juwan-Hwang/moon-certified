/// Polynomial factorization over rationals and integers.
///
/// Implements square-free factorization and distinct-degree factorization
/// for univariate polynomials with rational coefficients.
///
/// ## References
/// - Yun, D.Y.Y. "On square-free decomposition algorithms."
///   SYMSAC '76.
///
/// `proof-enabled` is `false`.

///|
/// Polynomial represented as coefficient array (ascending degree).
/// p(x) = coeffs[0] + coeffs[1]*x + ... + coeffs[n]*x^n

///|
/// Remove leading zero coefficients.
fn trim(p : Array[Double]) -> Array[Double] {
  let mut n = p.length()
  while n > 1 && p[n - 1].abs() < 1.0e-14 {
    n = n - 1
  }
  let result = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    result[i] = p[i]
  }
  result
}

///|
/// Polynomial GCD using the Euclidean algorithm.
pub fn poly_gcd(a : Array[Double], b : Array[Double]) -> Array[Double] {
  let mut p = trim(a)
  let mut q = trim(b)
  while q.length() > 1 || (q.length() == 1 && q[0].abs() > 1.0e-14) {
    let r = poly_mod(p, q)
    p = q
    q = r
  }
  // Normalize: make leading coefficient 1
  if p.length() > 0 && p[p.length() - 1].abs() > 1.0e-14 {
    let lead = p[p.length() - 1]
    for i = 0; i < p.length(); i = i + 1 {
      p[i] = p[i] / lead
    }
  }
  p
}

///|
/// Polynomial division: a / b = quotient, remainder.
/// Returns (quotient, remainder).
pub fn poly_divmod(a : Array[Double], b : Array[Double]) -> (Array[Double], Array[Double]) {
  let p = trim(a)
  let q = trim(b)
  let pn = p.length()
  let qn = q.length()
  if qn == 0 || (qn == 1 && q[0].abs() < 1.0e-14) {
    return (Array::make(0, 0.0), p)
  }
  if pn < qn {
    return ([0.0], p)
  }
  let quot_len = pn - qn + 1
  let quotient = Array::make(quot_len, 0.0)
  let rem = Array::make(pn, 0.0)
  for i = 0; i < pn; i = i + 1 {
    rem[i] = p[i]
  }
  for i = quot_len - 1; i >= 0; i = i - 1 {
    let lead = rem[i + qn - 1] / q[qn - 1]
    quotient[i] = lead
    for j = 0; j < qn; j = j + 1 {
      rem[i + j] = rem[i + j] - lead * q[j]
    }
  }
  let remainder = Array::make(qn - 1, 0.0)
  for i = 0; i < qn - 1; i = i + 1 {
    remainder[i] = rem[i]
  }
  (quotient, trim(remainder))
}

///|
/// Polynomial remainder: a mod b.
fn poly_mod(a : Array[Double], b : Array[Double]) -> Array[Double] {
  let (_, r) = poly_divmod(a, b)
  r
}

///|
/// Polynomial derivative.
pub fn poly_derivative(p : Array[Double]) -> Array[Double] {
  let n = p.length()
  if n <= 1 {
    return [0.0]
  }
  let result = Array::make(n - 1, 0.0)
  for i = 1; i < n; i = i + 1 {
    result[i - 1] = p[i] * i.to_double()
  }
  result
}

///|
/// Square-free factorization.
///
/// Returns list of (factor, multiplicity) pairs.
pub fn square_free_factorization(p : Array[Double]) -> Array[(Array[Double], Int)] {
  let f = trim(p)
  if f.length() <= 1 {
    return []
  }
  let f_prime = poly_derivative(f)
  let g = poly_gcd(f, f_prime)
  let (sqfree, _) = poly_divmod(f, g) // square-free part
  let result : Array[(Array[Double], Int)] = []
  let mut current_sqfree = sqfree
  let mut current_rem = g // product of f_i^(m_i-1)
  let mut k = 1
  while current_rem.length() > 1 {
    let h = poly_gcd(current_sqfree, current_rem)
    let (factor, _) = poly_divmod(current_sqfree, h)
    if factor.length() > 1 {
      result.push((trim(factor), k))
    }
    current_sqfree = h
    let (new_rem, _) = poly_divmod(current_rem, h)
    current_rem = new_rem
    k = k + 1
  }
  // Push remaining factor
  if current_sqfree.length() > 1 {
    result.push((trim(current_sqfree), k))
  }
  result
}

// ---------------------------------------------------------------------------
// Factorization over finite fields GF(p) — Cantor-Zassenhaus
// ---------------------------------------------------------------------------
// Polynomials over GF(p) use Array[Int] with coefficients in [0, p).
// Int64 intermediates prevent overflow for p up to ~2^31.
// Only odd primes are supported (p=2 requires trace-based splitting).

///|
/// Reduce a modulo p, returning a value in [0, p).
fn mod_pos(a : Int, p : Int) -> Int {
  let r = a % p
  if r < 0 { r + p } else { r }
}

///|
/// Modular inverse via extended Euclidean algorithm.
/// Returns x such that a*x ≡ 1 (mod p). Requires gcd(a, p) == 1.
fn mod_inv(a : Int, p : Int) -> Int {
  let mut old_r = mod_pos(a, p)
  let mut r = p
  let mut old_s = 1
  let mut s = 0
  while r != 0 {
    let q = old_r / r
    let tr = old_r - q * r
    old_r = r
    r = tr
    let ts = old_s - q * s
    old_s = s
    s = ts
  }
  mod_pos(old_s, p)
}

///|
/// Remove leading zero coefficients from a GF(p) polynomial.
fn trim_mod(poly : Array[Int], p : Int) -> Array[Int] {
  let len = poly.length()
  if len == 0 {
    return [0]
  }
  let mut n = len
  while n > 1 && mod_pos(poly[n - 1], p) == 0 {
    n = n - 1
  }
  let result = Array::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    result[i] = mod_pos(poly[i], p)
  }
  result
}

///|
/// Make a GF(p) polynomial monic (leading coefficient = 1).
fn make_monic_mod(f : Array[Int], p : Int) -> Array[Int] {
  let t = trim_mod(f, p)
  let n = t.length()
  if n <= 1 {
    return t
  }
  let inv_lead = mod_inv(t[n - 1], p)
  let result = Array::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    result[i] = mod_pos(t[i] * inv_lead, p)
  }
  result
}

///|
/// Polynomial multiplication over GF(p).
fn poly_mul_mod(a : Array[Int], b : Array[Int], p : Int) -> Array[Int] {
  let an = a.length()
  let bn = b.length()
  if (an == 1 && a[0] == 0) || (bn == 1 && b[0] == 0) {
    return [0]
  }
  let result = Array::make(an + bn - 1, 0)
  let p64 = p.to_int64()
  for i = 0; i < an; i = i + 1 {
    for j = 0; j < bn; j = j + 1 {
      let prod = (a[i].to_int64() * b[j].to_int64()) % p64
      result[i + j] = mod_pos(result[i + j] + prod.to_int(), p)
    }
  }
  trim_mod(result, p)
}

///|
/// Polynomial subtraction over GF(p): a - b.
fn poly_sub_mod(a : Array[Int], b : Array[Int], p : Int) -> Array[Int] {
  let an = a.length()
  let bn = b.length()
  let n = if an > bn { an } else { bn }
  let result = Array::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    let av = if i < an { a[i] } else { 0 }
    let bv = if i < bn { b[i] } else { 0 }
    result[i] = mod_pos(av - bv, p)
  }
  trim_mod(result, p)
}

///|
/// Polynomial division over GF(p): a / b = (quotient, remainder).
fn poly_divmod_mod(a : Array[Int], b : Array[Int], p : Int) -> (Array[Int], Array[Int]) {
  let aa = trim_mod(a, p)
  let bb = trim_mod(b, p)
  let pn = aa.length()
  let qn = bb.length()
  if qn == 0 || (qn == 1 && bb[0] == 0) {
    return ([0], aa)
  }
  if pn < qn {
    return ([0], aa)
  }
  let inv_lead = mod_inv(bb[qn - 1], p)
  let quot_len = pn - qn + 1
  let quotient = Array::make(quot_len, 0)
  let rem = Array::make(pn, 0)
  for i = 0; i < pn; i = i + 1 {
    rem[i] = aa[i]
  }
  for i = quot_len - 1; i >= 0; i = i - 1 {
    let lead = mod_pos(rem[i + qn - 1] * inv_lead, p)
    quotient[i] = lead
    for j = 0; j < qn; j = j + 1 {
      rem[i + j] = mod_pos(rem[i + j] - lead * bb[j], p)
    }
  }
  let remainder = Array::make(qn - 1, 0)
  for i = 0; i < qn - 1; i = i + 1 {
    remainder[i] = rem[i]
  }
  (quotient, trim_mod(remainder, p))
}

///|
/// Polynomial GCD over GF(p). Returns monic GCD.
fn poly_gcd_mod(a : Array[Int], b : Array[Int], p : Int) -> Array[Int] {
  let mut aa = trim_mod(a, p)
  let mut bb = trim_mod(b, p)
  while !(bb.length() == 1 && bb[0] == 0) {
    let (_, r) = poly_divmod_mod(aa, bb, p)
    aa = bb
    bb = r
  }
  make_monic_mod(aa, p)
}

///|
/// Compute base^exp mod f over GF(p) via repeated squaring.
fn poly_powmod_mod(
  base : Array[Int],
  exp : Int,
  f : Array[Int],
  p : Int
) -> Array[Int] {
  let (_, base_mod) = poly_divmod_mod(base, f, p)
  let mut current = base_mod
  let mut result = [1]
  let mut e = exp
  while e > 0 {
    if e % 2 == 1 {
      let prod = poly_mul_mod(result, current, p)
      let (_, r) = poly_divmod_mod(prod, f, p)
      result = r
    }
    e = e / 2
    if e > 0 {
      let prod = poly_mul_mod(current, current, p)
      let (_, r) = poly_divmod_mod(prod, f, p)
      current = r
    }
  }
  result
}

///|
/// Square-free factorization over GF(p).
/// Returns list of (factor, multiplicity) pairs where each factor is monic
/// and square-free. Handles the characteristic-p case where f' = 0 via
/// Frobenius (f(x) = g(x^p) ⟹ f = g^p).
fn square_free_factorization_mod(
  f : Array[Int],
  p : Int
) -> Array[(Array[Int], Int)] {
  let f_monic = make_monic_mod(f, p)
  let n = f_monic.length()
  if n <= 1 {
    return []
  }
  // Formal derivative f'(x) = sum i*a_i * x^(i-1)
  let f_prime = Array::make(n - 1, 0)
  for i = 1; i < n; i = i + 1 {
    f_prime[i - 1] = mod_pos(f_monic[i] * (i % p), p)
  }
  let f_prime_t = trim_mod(f_prime, p)
  // If f' = 0, then f(x) = g(x^p) and f = g^p (Frobenius endomorphism).
  if f_prime_t.length() == 1 && f_prime_t[0] == 0 {
    let g_len = (n - 1) / p + 1
    let g = Array::make(g_len, 0)
    for i = 0; i < g_len; i = i + 1 {
      g[i] = f_monic[i * p]
    }
    let sub = square_free_factorization_mod(g, p)
    let result : Array[(Array[Int], Int)] = []
    for i = 0; i < sub.length(); i = i + 1 {
      let (fac, mul) = sub[i]
      result.push((fac, mul * p))
    }
    return result
  }
  // Standard square-free factorization (Yun-style for char p).
  let g = poly_gcd_mod(f_monic, f_prime_t, p)
  let (sqfree, _) = poly_divmod_mod(f_monic, g, p)
  let result : Array[(Array[Int], Int)] = []
  let mut current_sqfree = sqfree
  let mut current_rem = g
  let mut k = 1
  while current_rem.length() > 1 {
    let h = poly_gcd_mod(current_sqfree, current_rem, p)
    let (factor, _) = poly_divmod_mod(current_sqfree, h, p)
    if factor.length() > 1 {
      result.push((factor, k))
    }
    current_sqfree = h
    let (new_rem, _) = poly_divmod_mod(current_rem, h, p)
    current_rem = new_rem
    k = k + 1
  }
  if current_sqfree.length() > 1 {
    result.push((current_sqfree, k))
  }
  result
}

///|
/// Distinct-degree factorization (DDF) over GF(p).
///
/// Input: monic square-free polynomial f.
/// Output: list of (g, d) where g is the product of all irreducible
/// factors of f of degree d.
///
/// Uses the fact that x^(p^d) - x is the product of all monic irreducible
/// polynomials over GF(p) whose degree divides d.
fn distinct_degree_factorization(
  f : Array[Int],
  p : Int
) -> Array[(Array[Int], Int)] {
  let result : Array[(Array[Int], Int)] = []
  let mut current = make_monic_mod(f, p)
  let x_poly : Array[Int] = [0, 1]
  // g = x^(p^d) mod current, built iteratively via Frobenius.
  let mut g = poly_powmod_mod(x_poly, p, current, p) // x^p mod f
  let mut d = 1
  while current.length() - 1 >= 2 * d {
    // gcd(current, g - x) extracts all irreducible factors of degree d.
    let g_minus_x = poly_sub_mod(g, x_poly, p)
    let h = poly_gcd_mod(current, g_minus_x, p)
    if h.length() > 1 {
      result.push((h, d))
      let (quo, _) = poly_divmod_mod(current, h, p)
      current = quo
      // Reduce g mod new current (valid since new_current | old_current).
      let (_, g_reduced) = poly_divmod_mod(g, current, p)
      g = g_reduced
    }
    d = d + 1
    // g = g^p mod current (advance to x^(p^(d+1))).
    g = poly_powmod_mod(g, p, current, p)
  }
  // Remaining factor (if degree > 0) is irreducible of degree deg(current).
  if current.length() > 1 {
    result.push((current, current.length() - 1))
  }
  result
}

///|
/// Compute a^((p^d - 1)/2) mod f over GF(p) for odd p.
///
/// Uses the norm map to avoid computing the large exponent (p^d-1)/2
/// directly: a^((p^d-1)/2) = prod_{i=0}^{d-1} (a^((p-1)/2))^(p^i),
/// since (p-1)/2 * sum_{i=0}^{d-1} p^i = (p^d - 1)/2.
fn norm_power(
  a : Array[Int],
  d : Int,
  f : Array[Int],
  p : Int
) -> Array[Int] {
  let half_exp = (p - 1) / 2
  let mut t = poly_powmod_mod(a, half_exp, f, p) // a^((p-1)/2) mod f
  let mut result = t
  for i = 1; i < d; i = i + 1 {
    t = poly_powmod_mod(t, p, f, p) // Frobenius: t -> t^p mod f
    let prod = poly_mul_mod(result, t, p)
    let (_, r) = poly_divmod_mod(prod, f, p)
    result = r
  }
  result
}

///|
/// Equal-degree factorization (Cantor-Zassenhaus) over GF(p) for odd p.
///
/// Splits a polynomial f (product of irreducible factors all of degree d)
/// into individual irreducible factors using random polynomial projections.
/// A non-trivial factor is found by computing gcd(f, a^((p^d-1)/2) - 1)
/// for random a, which splits the factors into two groups with ~50% probability.
///
/// Uses a deterministic LCG PRNG for reproducibility.
fn cantor_zassenhaus_split(
  f : Array[Int],
  d : Int,
  p : Int,
  seed : Int64
) -> Array[Array[Int]] {
  let n = f.length() - 1 // degree of f
  if n <= d {
    return [make_monic_mod(f, p)]
  }
  let p64 = p.to_int64()
  let mut rng = seed
  let mut attempts = 0
  while attempts < 200 {
    // Generate random polynomial a of degree < n.
    let a : Array[Int] = []
    for i = 0; i < n; i = i + 1 {
      rng = (rng * 6364136223846793005L + 1442695040888963407L) & 0x7FFFFFFFFFFFFFFFL
      a.push((rng % p64).to_int())
    }
    let a_t = trim_mod(a, p)
    if a_t.length() == 1 && a_t[0] == 0 {
      attempts = attempts + 1
      continue
    }
    // b = a^((p^d - 1)/2) mod f
    let b = norm_power(a_t, d, f, p)
    // gcd(f, b - 1) gives a non-trivial factor with ~50% probability.
    let one_poly : Array[Int] = [1]
    let b_minus_1 = poly_sub_mod(b, one_poly, p)
    let g = poly_gcd_mod(f, b_minus_1, p)
    if g.length() > 1 && g.length() < f.length() {
      let (quo, _) = poly_divmod_mod(f, g, p)
      let factors1 = cantor_zassenhaus_split(g, d, p, rng)
      let factors2 = cantor_zassenhaus_split(quo, d, p, rng + 7919L)
      let result : Array[Array[Int]] = []
      for i = 0; i < factors1.length(); i = i + 1 {
        result.push(factors1[i])
      }
      for i = 0; i < factors2.length(); i = i + 1 {
        result.push(factors2[i])
      }
      return result
    }
    attempts = attempts + 1
  }
  [make_monic_mod(f, p)]
}

///|
/// Factor a monic polynomial over GF(p) into irreducible factors.
///
/// Implements the complete factorization pipeline:
/// 1. Square-free factorization (Yun + Frobenius for char p)
/// 2. Distinct-degree factorization (DDF)
/// 3. Equal-degree factorization (Cantor-Zassenhaus)
///
/// ## Parameters
/// - `f`: polynomial coefficients in ascending degree order, over GF(p)
/// - `p`: odd prime modulus
///
/// ## Returns
/// List of monic irreducible factors (without multiplicities).
///
/// ## Limitations
/// - Only supports odd primes p (p=2 requires trace-based EDF).
/// - Coefficients must fit in Int (p < 2^31).
///
/// ## Example
/// ```
/// // x^2 - 1 = (x-1)(x+1) over GF(5)
/// factor_mod_p([4, 0, 1], 5) // returns [[4, 1], [1, 1]]
/// ```
pub fn factor_mod_p(f : Array[Int], p : Int) -> Array[Array[Int]] {
  let f_monic = make_monic_mod(f, p)
  if f_monic.length() <= 1 {
    return []
  }
  let sqfree_factors = square_free_factorization_mod(f_monic, p)
  let result : Array[Array[Int]] = []
  for i = 0; i < sqfree_factors.length(); i = i + 1 {
    let (sqfree, _) = sqfree_factors[i]
    let ddf_factors = distinct_degree_factorization(sqfree, p)
    for j = 0; j < ddf_factors.length(); j = j + 1 {
      let (g, d) = ddf_factors[j]
      let edf_factors = cantor_zassenhaus_split(
        g,
        d,
        p,
        42L + i.to_int64() * 100L + j.to_int64(),
      )
      for k = 0; k < edf_factors.length(); k = k + 1 {
        result.push(edf_factors[k])
      }
    }
  }
  result
}

test "polynomial_factor: gcd of coprime" {
  // gcd(x+1, x-1) = 1
  let g = poly_gcd([1.0, 1.0], [-1.0, 1.0])
  assert_true(g.length() == 1)
  assert_true((g[0] - 1.0).abs() < 1.0e-10)
}

test "polynomial_factor: gcd with common factor" {
  // gcd((x-1)*(x+2), (x-1)*(x-3)) = x-1
  // (x-1)*(x+2) = x^2 + x - 2
  // (x-1)*(x-3) = x^2 - 4x + 3
  let g = poly_gcd([-2.0, 1.0, 1.0], [3.0, -4.0, 1.0])
  // Should be x - 1 (i.e., [-1, 1])
  assert_eq(g.length(), 2)
  assert_true((g[0] + 1.0).abs() < 1.0e-10)
  assert_true((g[1] - 1.0).abs() < 1.0e-10)
}

test "polynomial_factor: derivative" {
  // d/dx(3x^3 + 2x^2 + x + 5) = 9x^2 + 4x + 1
  let d = poly_derivative([5.0, 1.0, 2.0, 3.0])
  assert_eq(d.length(), 3)
  assert_true((d[0] - 1.0).abs() < 1.0e-10)
  assert_true((d[1] - 4.0).abs() < 1.0e-10)
  assert_true((d[2] - 9.0).abs() < 1.0e-10)
}

test "polynomial_factor: divmod exact" {
  // (x^2 - 1) / (x - 1) = (x + 1), remainder 0
  let (q, r) = poly_divmod([-1.0, 0.0, 1.0], [-1.0, 1.0])
  assert_eq(q.length(), 2)
  assert_true((q[0] - 1.0).abs() < 1.0e-10)
  assert_true((q[1] - 1.0).abs() < 1.0e-10)
  assert_true(r.length() == 1)
  assert_true(r[0].abs() < 1.0e-10)
}

test "polynomial_factor: square-free of (x-1)^2" {
  // (x-1)^2 = x^2 - 2x + 1
  let factors = square_free_factorization([1.0, -2.0, 1.0])
  assert_eq(factors.length(), 1)
  let (f, m) = factors[0]
  assert_eq(m, 2)
  assert_true((f[0] + 1.0).abs() < 1.0e-10)
  assert_true((f[1] - 1.0).abs() < 1.0e-10)
}

test "polynomial_factor: square-free of (x-1)(x-2)" {
  // (x-1)(x-2) = x^2 - 3x + 2
  let factors = square_free_factorization([2.0, -3.0, 1.0])
  assert_eq(factors.length(), 1)
  let (_, m) = factors[0]
  assert_eq(m, 1)
}

// ---------------------------------------------------------------------------
// Cantor-Zassenhaus tests over GF(p)
// ---------------------------------------------------------------------------

/// Helper: multiply all factors together over GF(p).
fn poly_product(factors : Array[Array[Int]], p : Int) -> Array[Int] {
  let mut prod : Array[Int] = [1]
  for i = 0; i < factors.length(); i = i + 1 {
    prod = poly_mul_mod(prod, factors[i], p)
  }
  prod
}

test "polynomial_factor: factor x^2-1 mod 5" {
  // x^2 - 1 = (x-1)(x+1) over GF(5)
  let factors = factor_mod_p([4, 0, 1], 5)
  assert_eq(factors.length(), 2)
  let prod = poly_product(factors, 5)
  assert_eq(prod, [4, 0, 1])
}

test "polynomial_factor: factor x^2+1 mod 5" {
  // x^2 + 1 = (x-2)(x+2) over GF(5), since 2^2 = 4 ≡ -1 mod 5
  let factors = factor_mod_p([1, 0, 1], 5)
  assert_eq(factors.length(), 2)
  let prod = poly_product(factors, 5)
  assert_eq(prod, [1, 0, 1])
}

test "polynomial_factor: factor x^3-x mod 5" {
  // x^3 - x = x(x-1)(x+1) over GF(5)
  // x^3 - x = [0, 4, 0, 1] mod 5
  let factors = factor_mod_p([0, 4, 0, 1], 5)
  assert_eq(factors.length(), 3)
  let prod = poly_product(factors, 5)
  assert_eq(prod, [0, 4, 0, 1])
}

test "polynomial_factor: factor x^4-1 mod 5" {
  // x^4 - 1 = (x-1)(x+1)(x-2)(x+2) over GF(5)
  // x^4 - 1 = [4, 0, 0, 0, 1] mod 5
  let factors = factor_mod_p([4, 0, 0, 0, 1], 5)
  assert_eq(factors.length(), 4)
  let prod = poly_product(factors, 5)
  assert_eq(prod, [4, 0, 0, 0, 1])
}

test "polynomial_factor: irreducible x^2+x+1 mod 5" {
  // x^2 + x + 1 is irreducible over GF(5) (discriminant -3 ≡ 2, not a QR mod 5)
  let factors = factor_mod_p([1, 1, 1], 5)
  assert_eq(factors.length(), 1)
  assert_eq(factors[0], [1, 1, 1])
}

test "polynomial_factor: irreducible x^3+x+1 mod 5" {
  // x^3 + x + 1 is irreducible over GF(5) (no roots: f(0..4) ≠ 0)
  let factors = factor_mod_p([1, 1, 0, 1], 5)
  assert_eq(factors.length(), 1)
  assert_eq(factors[0], [1, 1, 0, 1])
}

test "polynomial_factor: repeated factor (x-1)^2*(x-2) mod 5" {
  // (x-1)^2 * (x-2) = x^3 + x^2 + 3 mod 5
  // factor_mod_p returns distinct irreducible factors (no multiplicities):
  // (x-1) and (x-2), product = (x-1)(x-2) = x^2 + 2x + 2 mod 5
  let factors = factor_mod_p([3, 0, 1, 1], 5)
  assert_eq(factors.length(), 2)
  let prod = poly_product(factors, 5)
  // (x-1)(x-2) = x^2 - 3x + 2 = [2, 2, 1] mod 5
  assert_eq(prod, [2, 2, 1])
}

test "polynomial_factor: factor mod 7" {
  // x^2 - 2 = (x-3)(x+3) over GF(7), since 3^2 = 9 ≡ 2 mod 7
  // x^2 - 2 = [5, 0, 1] mod 7
  let factors = factor_mod_p([5, 0, 1], 7)
  assert_eq(factors.length(), 2)
  let prod = poly_product(factors, 7)
  assert_eq(prod, [5, 0, 1])
}

test "polynomial_factor: factor mod 11" {
  // x^2 + 1 = (x-5)(x+5) over GF(11), since 5^2 = 25 ≡ 3... no
  // Actually 5^2 = 25 ≡ 3 mod 11, not -1.
  // -1 mod 11 = 10. Is 10 a QR mod 11? 10^((11-1)/2) = 10^5 mod 11.
  // 10^2 = 100 ≡ 1, so 10^5 = 10^4 * 10 = 1 * 10 = 10 ≡ -1. Not a QR.
  // So x^2 + 1 is irreducible mod 11.
  let factors = factor_mod_p([1, 0, 1], 11)
  assert_eq(factors.length(), 1)
  assert_eq(factors[0], [1, 0, 1])
}

test "polynomial_factor: factor degree-4 mod 7" {
  // x^4 - 1 = (x-1)(x+1)(x-6)(x+6) over GF(7)
  // since x^4 - 1 = (x^2-1)(x^2+1) and x^2+1 = (x-6)(x+6) mod 7
  // (6^2 = 36 ≡ 1 mod 7... no, 36 mod 7 = 1, so 6^2 ≡ 1, not -1)
  // Let me recalculate: -1 mod 7 = 6. 6^2 = 36 = 35+1 ≡ 1 mod 7. Not -1.
  // So x^2 + 1 is irreducible mod 7.
  // x^4 - 1 = (x^2-1)(x^2+1) = (x-1)(x+1)(x^2+1) over GF(7)
  // x^4 - 1 = [6, 0, 0, 0, 1] mod 7
  let factors = factor_mod_p([6, 0, 0, 0, 1], 7)
  // Should give 3 factors: (x-1), (x+1), (x^2+1)
  assert_eq(factors.length(), 3)
  let prod = poly_product(factors, 7)
  assert_eq(prod, [6, 0, 0, 0, 1])
}
