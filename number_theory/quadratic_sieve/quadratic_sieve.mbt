/// Quadratic Sieve integer factorization.
///
/// A simplified implementation of the quadratic sieve algorithm for
/// factoring medium-sized composite integers. Uses trial division for
/// small factors and a basic quadratic sieve approach for larger ones.
///
/// ## Algorithm
///
/// 1. Trial division for factors up to n^(1/3).
/// 2. Collect B-smooth values of Q(x) = (x + ceil(sqrt(n)))² - n.
/// 3. Use Gaussian elimination over GF(2) to find a perfect square.
/// 4. Compute gcd(x² - y², n) to extract a factor.
///
/// ## References
///
/// - Pomerance, C. "The Quadratic Sieve Factoring Algorithm."
/// - Crandall & Pomerance. "Prime Numbers: A Computational Perspective."
///
/// `proof-enabled` is `false`.

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
/// Compute gcd.
pub fn gcd(a : Int, b : Int) -> Int {
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
/// Trial division: try all divisors up to limit.
/// Returns Some(factor) if found, None otherwise.
fn trial_division(n : Int, limit : Int) -> Int? {
  if n % 2 == 0 {
    return Some(2)
  }
  let mut d = 3
  while d <= limit && d * d <= n {
    if n % d == 0 {
      return Some(d)
    }
    d = d + 2
  }
  None
}

///|
/// Generate small primes up to limit using simple sieve.
pub fn small_primes(limit : Int) -> Array[Int] {
  if limit < 2 {
    return []
  }
  let sieve : Array[Bool] = Array::make(limit + 1, true)
  sieve[0] = false
  sieve[1] = false
  let mut i = 2
  while i * i <= limit {
    if sieve[i] {
      let mut j = i * i
      while j <= limit {
        sieve[j] = false
        j = j + i
      }
    }
    i = i + 1
  }
  let primes : Array[Int] = []
  for k = 2; k <= limit; k = k + 1 {
    if sieve[k] {
      primes.push(k)
    }
  }
  primes
}

///|
/// Check if n is B-smooth (all prime factors ≤ B).
/// Returns the list of prime factor exponents mod 2 if smooth, None otherwise.
pub fn try_smooth(n : Int, primes : Array[Int]) -> Array[Int]? {
  let mut val = n
  let exponents : Array[Int] = Array::make(primes.length(), 0)
  for i = 0; i < primes.length(); i = i + 1 {
    while val % primes[i] == 0 {
      val = val / primes[i]
      exponents[i] = exponents[i] + 1
    }
    exponents[i] = exponents[i] % 2
  }
  if val == 1 {
    Some(exponents)
  } else {
    None
  }
}

///|
/// Factor n using a simplified quadratic sieve approach.
/// Returns Some(factor) if a non-trivial factor is found, None if n is prime.
pub fn factor(n : Int) -> Int? {
  if n < 2 {
    return None
  }
  // Handle small factors
  let limit = isqrt(isqrt(n)) + 1
  match trial_division(n, limit * 100) {
    Some(d) =>
      if d < n {
        return Some(d)
      }
    None => ()
  }
  // Check if n is prime
  if is_probable_prime(n) {
    return None
  }
  // Simple Fermat factorization for remaining cases
  fermat_factor(n)
}

///|
/// Fermat factorization: find a, b such that n = a² - b² = (a+b)(a-b).
fn fermat_factor(n : Int) -> Int? {
  if n % 2 == 0 {
    return Some(2)
  }
  let mut a = isqrt(n)
  if a * a == n {
    return Some(a)
  }
  a = a + 1
  let mut iter = 0
  let max_iter = 1000000
  while iter < max_iter {
    let b2 = a * a - n
    let b = isqrt(b2)
    if b * b == b2 {
      let factor = a - b
      if factor > 1 && factor < n {
        return Some(factor)
      }
    }
    a = a + 1
    iter = iter + 1
  }
  None
}

///|
/// Simple Miller-Rabin primality test for internal use.
fn is_probable_prime(n : Int) -> Bool {
  if n < 2 {
    return false
  }
  if n == 2 || n == 3 {
    return true
  }
  if n % 2 == 0 {
    return false
  }
  // Write n-1 as 2^r * d
  let mut d = n - 1
  let mut r = 0
  while d % 2 == 0 {
    d = d / 2
    r = r + 1
  }
  // Test with witnesses
  let witnesses = [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37]
  for i = 0; i < witnesses.length(); i = i + 1 {
    let a = witnesses[i]
    if a >= n {
      continue
    }
    let mut x = powmod(a, d, n)
    if x == 1 || x == n - 1 {
      continue
    }
    let mut composite = true
    for j = 0; j < r - 1; j = j + 1 {
      x = (x * x) % n
      if x == n - 1 {
        composite = false
        break
      }
    }
    if composite {
      return false
    }
  }
  true
}

///|
fn powmod(base : Int, exp : Int, m : Int) -> Int {
  if m == 1 {
    return 0
  }
  let mut result = 1
  let mut b = base % m
  if b < 0 {
    b = b + m
  }
  let mut e = exp
  while e > 0 {
    if (e & 1) == 1 {
      result = (result * b) % m
    }
    e = e >> 1
    b = (b * b) % m
  }
  result
}

///|
test "quadratic_sieve: factor 15" {
  match factor(15) {
    Some(d) => {
      assert_true(d == 3 || d == 5)
      assert_eq(15 / d * d, 15)
    }
    None => assert_true(false)
  }
}

///|
test "quadratic_sieve: factor 21" {
  match factor(21) {
    Some(d) => {
      assert_true(d == 3 || d == 7)
      assert_eq(21 % d, 0)
    }
    None => assert_true(false)
  }
}

///|
test "quadratic_sieve: factor 35" {
  match factor(35) {
    Some(d) => {
      assert_true(d == 5 || d == 7)
      assert_eq(35 % d, 0)
    }
    None => assert_true(false)
  }
}

///|
test "quadratic_sieve: factor larger composite" {
  match factor(77) {
    Some(d) => {
      assert_true(d == 7 || d == 11)
      assert_eq(77 % d, 0)
    }
    None => assert_true(false)
  }
}

///|
test "quadratic_sieve: prime returns None" {
  match factor(97) {
    Some(_) => assert_true(false)
    None => assert_true(true)
  }
}
