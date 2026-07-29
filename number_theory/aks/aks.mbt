/// AKS (Agrawal-Kayal-Saxena) Primality Test.
///
/// The first deterministic polynomial-time primality test. For input n,
/// it correctly determines whether n is prime in O(log^6 n) time.
///
/// ## Algorithm
///
/// 1. If n = a^b for a > 0, b > 1, return composite.
/// 2. Find smallest r such that ord_r(n) > log²(n).
/// 3. If 1 < gcd(a, n) < n for some a ≤ r, return composite.
/// 4. If n ≤ r, return prime.
/// 5. For a = 1 to floor(sqrt(φ(r)) · log n), check
///    (x + a)^n ≡ x^n + a (mod n, x^r - 1).
/// 6. Return prime.
///
/// ## References
///
/// - Agrawal, Kayal, Saxena. "PRIMES is in P." Annals of Math., 2004.
///
/// `proof-enabled` is `false`.

///|
/// Compute gcd.
fn gcd(a : Int, b : Int) -> Int {
  let mut x = if a < 0 { -a } else { a }
  let mut y = if b < 0 { -b } else { b }
  while y > 0 {
    let t = x % y
    x = y
    y = t
  }
  x
}

///|
/// Integer square root.
fn isqrt(n : Int) -> Int {
  if n <= 0 {
    return 0
  }
  let mut x = n
  let mut y = (n + 1) / 2
  while y < x {
    x = y
    y = (x + n / x) / 2
  }
  x
}

///|
/// Check if n is a perfect power. Returns (base, exp) if n = base^exp.
fn is_perfect_power(n : Int) -> Bool {
  if n < 4 {
    return false
  }
  let log_n = if n > 1 { 1 + ilog2(n) } else { 1 }
  for exp = 2; exp <= log_n; exp = exp + 1 {
    // Binary search for integer exp-th root
    let mut lo = 2
    let mut hi = n
    while lo <= hi {
      let mid = (lo + hi) / 2
      let val = ipow(mid, exp)
      if val == n {
        return true
      }
      if val < 0 || val > n {
        hi = mid - 1
      } else {
        lo = mid + 1
      }
    }
  }
  false
}

///|
/// Integer power (for small values).
fn ipow(base : Int, exp : Int) -> Int {
  let mut result = 1
  let mut b = base
  let mut e = exp
  while e > 0 {
    if (e & 1) == 1 {
      result = result * b
    }
    e = e >> 1
    if e > 0 {
      b = b * b
    }
  }
  result
}

///|
/// Integer log2.
fn ilog2(n : Int) -> Int {
  let mut x = n
  let mut r = 0
  while x > 1 {
    x = x >> 1
    r = r + 1
  }
  r
}

///|
/// Compute n^k mod m using repeated squaring.

///|
/// Compute the multiplicative order of n mod r (smallest k > 0 with n^k ≡ 1 mod r).
fn multiplicative_order(n : Int, r : Int) -> Int {
  if gcd(n, r) != 1 {
    return 0
  }
  let mut k = 1
  let mut val = n % r
  while val != 1 {
    val = (val * (n % r)) % r
    k = k + 1
    if k > r {
      return r + 1 // order doesn't exist or > r
    }
  }
  k
}

///|
/// Euler's totient function.
fn euler_phi(n : Int) -> Int {
  let mut result = n
  let mut m = n
  let mut p = 2
  while p * p <= m {
    if m % p == 0 {
      while m % p == 0 {
        m = m / p
      }
      result = result - result / p
    }
    p = p + 1
  }
  if m > 1 {
    result = result - result / m
  }
  result
}

///|
/// Polynomial coefficients mod n, represented as arrays.
/// (x + a)^n mod (n, x^r - 1) check.
/// We represent polynomials as arrays of coefficients mod n.
fn poly_mul_mod(
  a : Array[Int],
  b : Array[Int],
  n : Int,
  r : Int,
) -> Array[Int] {
  let result : Array[Int] = Array::make(r, 0)
  for i = 0; i < a.length(); i = i + 1 {
    for j = 0; j < b.length(); j = j + 1 {
      let idx = (i + j) % r
      result[idx] = (result[idx] + a[i] * b[j]) % n
    }
  }
  result
}

///|
/// Compute (x + a)^n mod (n, x^r - 1) using repeated squaring.
fn poly_pow_mod(a : Int, n : Int, r : Int) -> Array[Int] {
  // Start with (x + a)
  let mut base : Array[Int] = Array::make(r, 0)
  base[0] = a % n
  if r > 1 {
    base[1] = 1
  }
  let mut result : Array[Int] = Array::make(r, 0)
  result[0] = 1 // 1
  let mut e = n
  while e > 0 {
    if (e & 1) == 1 {
      result = poly_mul_mod(result, base, n, r)
    }
    e = e >> 1
    if e > 0 {
      base = poly_mul_mod(base, base, n, r)
    }
  }
  result
}

///|
/// AKS primality test. Returns true if n is prime.
///
/// Note: For practical use, Miller-Rabin is faster. AKS is included
/// for completeness as the only deterministic polynomial-time test.
pub fn is_prime_aks(n : Int) -> Bool {
  if n < 2 {
    return false
  }
  if n == 2 || n == 3 {
    return true
  }
  if n % 2 == 0 {
    return false
  }
  // Step 1: Check if n is a perfect power
  if is_perfect_power(n) {
    return false
  }
  // Step 2: Find smallest r such that ord_r(n) > log²(n)
  let log2_n = ilog2(n)
  let log2_n_sq = log2_n * log2_n
  let mut r = 2
  while r < n {
    if gcd(n, r) != 1 {
      // Step 3: Check gcd
      if r > 1 && r < n {
        return false
      }
      r = r + 1
      continue
    }
    let ord = multiplicative_order(n, r)
    if ord > log2_n_sq {
      break
    }
    r = r + 1
  }
  // Step 4: If n <= r, n is prime
  if n <= r {
    return true
  }
  // Step 3 (again): Check gcd for all a <= r
  for a = 2; a <= r; a = a + 1 {
    let g = gcd(a, n)
    if g > 1 && g < n {
      return false
    }
  }
  // Step 5: Check (x + a)^n ≡ x^n + a (mod n, x^r - 1)
  let limit = isqrt(euler_phi(r)) * log2_n
  if limit < 1 {
    return true
  }
  for a = 1; a <= limit; a = a + 1 {
    let lhs = poly_pow_mod(a, n, r)
    // x^n + a mod (x^r - 1) = x^(n mod r) + a
    let rhs : Array[Int] = Array::make(r, 0)
    rhs[n % r] = 1
    rhs[0] = a % n
    // Compare
    let mut equal = true
    for i = 0; i < r; i = i + 1 {
      if lhs[i] != rhs[i] {
        equal = false
        break
      }
    }
    if !equal {
      return false
    }
  }
  true
}

///|
test "aks: small primes" {
  assert_true(is_prime_aks(2))
  assert_true(is_prime_aks(3))
  assert_true(is_prime_aks(5))
  assert_true(is_prime_aks(7))
  assert_true(is_prime_aks(11))
  assert_true(is_prime_aks(13))
  assert_true(is_prime_aks(17))
  assert_true(is_prime_aks(19))
  assert_true(is_prime_aks(23))
  assert_true(is_prime_aks(29))
  assert_true(is_prime_aks(31))
}

///|
test "aks: composites" {
  assert_false(is_prime_aks(4))
  assert_false(is_prime_aks(6))
  assert_false(is_prime_aks(8))
  assert_false(is_prime_aks(9))
  assert_false(is_prime_aks(15))
  assert_false(is_prime_aks(21))
  assert_false(is_prime_aks(25))
  assert_false(is_prime_aks(27))
  assert_false(is_prime_aks(35))
  assert_false(is_prime_aks(49))
}

///|
test "aks: edge cases" {
  assert_false(is_prime_aks(0))
  assert_false(is_prime_aks(1))
  assert_false(is_prime_aks(-5))
}

///|
test "aks: larger primes" {
  assert_true(is_prime_aks(37))
  assert_true(is_prime_aks(41))
  assert_true(is_prime_aks(43))
  assert_true(is_prime_aks(47))
  assert_false(is_prime_aks(51))
  assert_false(is_prime_aks(57))
}
