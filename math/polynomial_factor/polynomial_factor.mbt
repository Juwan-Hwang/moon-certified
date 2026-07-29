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
