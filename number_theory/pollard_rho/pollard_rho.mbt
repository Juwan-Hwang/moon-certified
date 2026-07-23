/// Pollard-Rho integer factorization.
///
/// Finds a non-trivial factor of a composite number `n > 1`. Combined with
/// a primality test (Miller-Rabin, duplicated here for self-containment), it
/// provides a complete integer factorization routine.
///
/// **Algorithm.** Uses Floyd's cycle detection on the polynomial sequence
///   x₀ = 2, x_{i+1} = (xᵢ² + c) mod n.
/// At each step, compute d = gcd(|x − y|, n). If 1 < d < n, d is a factor.
/// If d == n, the attempt failed; retry with a different constant c.
///
/// **Complexity.** Expected O(√p) iterations where p is the smallest prime
/// factor of n, i.e. O(n^{1/4}) in the worst case.
///
/// **Overflow safety.** All arithmetic is in `Int64`. Since n < 2^31,
/// x² < 2^62 < 2^63, so no `Int64` overflow can occur.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

// ---------------------------------------------------------------------------
// Int64 helpers (self-contained)
// ---------------------------------------------------------------------------

/// Int64 GCD (Euclidean algorithm). Inputs are taken in absolute value.
fn gcd64(a : Int64, b : Int64) -> Int64 {
  let mut x = if a < 0L { -a } else { a }
  let mut y = if b < 0L { -b } else { b }
  while y != 0L {
    let t = x % y
    x = y
    y = t
  }
  x
}

/// Modular exponentiation in `Int64`: returns (base^exp) mod m.
fn pow_mod64(base : Int64, exp : Int64, m : Int64) -> Int64 {
  let mut result = 1L
  let mut b = base % m
  if b < 0L {
    b = b + m
  }
  let mut e = exp
  while e > 0L {
    if e % 2L == 1L {
      result = result * b % m
    }
    e = e / 2L
    b = b * b % m
  }
  result
}

// ---------------------------------------------------------------------------
// Miller-Rabin primality test (deterministic for Int range)
// ---------------------------------------------------------------------------

/// Single Miller-Rabin round for witness `a`.
/// `d` and `s` satisfy n - 1 = d * 2^s with d odd, n odd >= 5.
fn witness_passes(a : Int64, d : Int64, s : Int, n : Int64) -> Bool {
  let a_mod = a % n
  if a_mod == 0L {
    return true
  }
  let mut x = pow_mod64(a_mod, d, n)
  if x == 1L || x == n - 1L {
    return true
  }
  for _r = 0; _r < s - 1; _r = _r + 1 {
    x = x * x % n
    if x == n - 1L {
      return true
    }
  }
  false
}

/// Deterministic Miller-Rabin primality test.
///
/// For n < 2^31 (the full positive range of 32-bit `Int`), the witness set
/// {2, 7, 61} suffices (Jaeschke 1993). Returns `true` if `n` is prime,
/// `false` otherwise (including n < 2).
fn is_prime64(n : Int64) -> Bool {
  if n < 2L {
    return false
  }
  if n == 2L || n == 3L {
    return true
  }
  if n % 2L == 0L {
    return false
  }
  // Write n - 1 = d * 2^s with d odd.
  let mut d = n - 1L
  let mut s = 0
  while d % 2L == 0L {
    d = d / 2L
    s = s + 1
  }
  let witnesses = [2L, 7L, 61L]
  for i = 0; i < 3; i = i + 1 {
    if !witness_passes(witnesses[i], d, s, n) {
      return false
    }
  }
  true
}

// ---------------------------------------------------------------------------
// Pollard-Rho core
// ---------------------------------------------------------------------------

/// One iteration of the Pollard-Rho sequence: f(x) = (x² + c) mod n.
fn prho_f(x : Int64, c : Int64, n : Int64) -> Int64 {
  (x * x + c) % n
}

/// Attempt to find a non-trivial factor of n using Pollard-Rho with the
/// given constants c (polynomial offset) and x0 (starting value).
///
/// Uses Floyd's cycle detection: tortoise advances 1 step, hare 2 steps.
/// Returns a factor d with 1 < d < n, or n if the attempt failed.
fn prho_find(n : Int64, c : Int64, x0 : Int64) -> Int64 {
  let mut tortoise = x0
  let mut hare = x0
  let mut d = 1L
  while d == 1L {
    tortoise = prho_f(tortoise, c, n)
    hare = prho_f(prho_f(hare, c, n), c, n)
    let diff = if tortoise > hare {
      tortoise - hare
    } else {
      hare - tortoise
    }
    if diff == 0L {
      // Cycle found without a factor; this attempt failed.
      return n
    }
    d = gcd64(diff, n)
  }
  d
}

/// Find one non-trivial factor of `n`.
///
/// `n` must be a composite number greater than 1 (check with `is_prime64`
/// before calling). Returns `Some(d)` with a factor `d` satisfying
/// `1 < d < n`. Returns `None` when `n <= 1`, when `n` is prime (it has no
/// non-trivial factor), or if all attempts fail (extremely unlikely for
/// composite `n`).
pub fn pollard_rho(n : Int) -> Int? {
  if n <= 1 {
    return None
  }
  // 2 is prime: no non-trivial factor exists.
  if n == 2 {
    return None
  }
  // Any even n > 2 has 2 as a non-trivial factor.
  if n % 2 == 0 {
    return Some(2)
  }
  let n64 = n.to_int64()
  // Try several values of c and x0. Using a fixed list avoids dependence on
  // a random number generator while still covering diverse failure modes.
  let constants = [1L, 2L, 3L, 5L, 7L, 11L, 13L, 17L, 19L, 23L, 29L, 31L]
  for i = 0; i < constants.length(); i = i + 1 {
    let d = prho_find(n64, constants[i], 2L)
    if d != 1L && d != n64 {
      return Some(d.to_int())
    }
    // Retry with a different starting value for this c.
    let d2 = prho_find(n64, constants[i], 3L)
    if d2 != 1L && d2 != n64 {
      return Some(d2.to_int())
    }
  }
  None // Should not happen for genuine composites
}

/// Factorize `n` into its prime factors (with multiplicity), in ascending order.
///
/// Returns an empty array for n < 2. For n >= 2, returns the complete list
/// of prime factors whose product equals n.
///
/// **Algorithm.** Trial division for small primes (≤ 100), then Pollard-Rho
/// with Miller-Rabin primality checking for large factors. Recursively
/// factors any composite cofactors found by Pollard-Rho.
pub fn factorize(n : Int) -> Array[Int] {
  let result : Array[Int] = []
  if n < 2 {
    return result
  }
  let mut m = n
  // Trial division for small primes.
  let small_primes = [
    2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61, 67,
    71, 73, 79, 83, 89, 97,
  ]
  for i = 0; i < small_primes.length(); i = i + 1 {
    let p = small_primes[i]
    while m % p == 0 {
      result.push(p)
      m = m / p
    }
  }
  if m == 1 {
    return result
  }
  // m is now free of factors ≤ 97. Factor the remaining cofactor.
  factor_rec(m, result)
  // Sort the result (trial-division factors are already ascending, but
  // Pollard-Rho may find larger factors first).
  // Simple insertion sort (result is typically short).
  let len = result.length()
  for i = 1; i < len; i = i + 1 {
    let key = result[i]
    let mut j = i - 1
    while j >= 0 && result[j] > key {
      result[j + 1] = result[j]
      j = j - 1
    }
    result[j + 1] = key
  }
  result
}

/// Recursively factor a cofactor `m` (all factors > 97) into `result`.
fn factor_rec(m : Int, result : Array[Int]) -> Unit {
  if m == 1 {
    return
  }
  if is_prime64(m.to_int64()) {
    result.push(m)
    return
  }
  // m is composite; find a factor with Pollard-Rho.
  match pollard_rho(m) {
    Some(d) => {
      factor_rec(d, result)
      factor_rec(m / d, result)
    }
    None => result.push(m)
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "pollard_rho: even number returns 2" {
  assert_eq(pollard_rho(100), Some(2))
  assert_eq(pollard_rho(6), Some(2))
  assert_eq(pollard_rho(2147483646), Some(2))
}

test "pollard_rho: semiprime 15 = 3 * 5" {
  let d = pollard_rho(15).unwrap()
  assert_true(d == 3 || d == 5)
  assert_eq(15 / d * d, 15) // d divides 15
}

test "pollard_rho: semiprime 49 = 7 * 7" {
  let d = pollard_rho(49).unwrap()
  assert_eq(d, 7)
}

test "pollard_rho: large semiprime" {
  // 10007 * 10009 = 100160063
  let n = 100160063
  let d = pollard_rho(n).unwrap()
  assert_true(d != 1 && d != n)
  assert_eq(n % d, 0)
  assert_true(d == 10007 || d == 10009)
}

test "pollard_rho: product of two large primes" {
  // 46337 * 46327 = 2146654199 (< 2^31)
  let n = 2146654199
  let d = pollard_rho(n).unwrap()
  assert_true(d != 1 && d != n)
  assert_eq(n % d, 0)
}

test "pollard_rho: Carmichael number 561 = 3 * 11 * 17" {
  let d = pollard_rho(561).unwrap()
  assert_true(d != 1 && d != 561)
  assert_eq(561 % d, 0)
}

test "pollard_rho: n <= 1 returns None" {
  assert_true(pollard_rho(0) is None)
  assert_true(pollard_rho(1) is None)
  assert_true(pollard_rho(-5) is None)
}

test "pollard_rho: prime returns None (no non-trivial factor)" {
  // A prime has no non-trivial factor; the result must be None rather than
  // a value indistinguishable from a real factor.
  assert_true(pollard_rho(2) is None)
  assert_true(pollard_rho(3) is None)
  assert_true(pollard_rho(7) is None)
  assert_true(pollard_rho(13) is None)
  assert_true(pollard_rho(97) is None)
}

test "is_prime64: small primes" {
  assert_eq(is_prime64(2L), true)
  assert_eq(is_prime64(3L), true)
  assert_eq(is_prime64(5L), true)
  assert_eq(is_prime64(7L), true)
  assert_eq(is_prime64(11L), true)
}

test "is_prime64: small composites" {
  assert_eq(is_prime64(4L), false)
  assert_eq(is_prime64(6L), false)
  assert_eq(is_prime64(9L), false)
  assert_eq(is_prime64(15L), false)
}

test "is_prime64: Mersenne prime" {
  assert_eq(is_prime64(2147483647L), true)
}

test "is_prime64: Carmichael numbers" {
  assert_eq(is_prime64(561L), false)
  assert_eq(is_prime64(1105L), false)
  assert_eq(is_prime64(1729L), false)
}

test "factorize: prime number" {
  let f = factorize(17)
  assert_eq(f.length(), 1)
  assert_eq(f[0], 17)
}

test "factorize: power of 2" {
  let f = factorize(1024)
  assert_eq(f.length(), 10)
  for i = 0; i < 10; i = i + 1 {
    assert_eq(f[i], 2)
  }
}

test "factorize: semiprime" {
  let f = factorize(15)
  assert_eq(f.length(), 2)
  assert_eq(f[0], 3)
  assert_eq(f[1], 5)
}

test "factorize: perfect square of prime" {
  let f = factorize(49)
  assert_eq(f.length(), 2)
  assert_eq(f[0], 7)
  assert_eq(f[1], 7)
}

test "factorize: 561 = 3 * 11 * 17" {
  let f = factorize(561)
  assert_eq(f.length(), 3)
  assert_eq(f[0], 3)
  assert_eq(f[1], 11)
  assert_eq(f[2], 17)
}

test "factorize: large semiprime 100160063" {
  let f = factorize(100160063)
  assert_eq(f.length(), 2)
  assert_eq(f[0], 10007)
  assert_eq(f[1], 10009)
}

test "factorize: product of two large primes" {
  let n = 2146654199 // 46337 * 46327
  let f = factorize(n)
  assert_eq(f.length(), 2)
  assert_eq(f[0], 46327)
  assert_eq(f[1], 46337)
}

test "factorize: one" {
  let f = factorize(1)
  assert_eq(f.length(), 0)
}

test "factorize: zero and negative" {
  assert_eq(factorize(0).length(), 0)
  assert_eq(factorize(-5).length(), 0)
}

test "factorize: factorial" {
  // 10! = 3628800 = 2^8 * 3^4 * 5^2 * 7
  let f = factorize(3628800)
  let mut product = 1
  for i = 0; i < f.length(); i = i + 1 {
    product = product * f[i]
  }
  assert_eq(product, 3628800)
  // Verify ascending order.
  for i = 1; i < f.length(); i = i + 1 {
    assert_true(f[i] >= f[i - 1])
  }
}

test "factorize: large prime stays as single factor" {
  let f = factorize(2147483647) // Mersenne prime M31
  assert_eq(f.length(), 1)
  assert_eq(f[0], 2147483647)
}

test "factorize: product verified for various n" {
  let cases = [12, 100, 999, 123456, 999983, 1048576]
  for i = 0; i < cases.length(); i = i + 1 {
    let n = cases[i]
    let f = factorize(n)
    let mut product = 1
    for j = 0; j < f.length(); j = j + 1 {
      product = product * f[j]
    }
    assert_eq(product, n)
    // Every factor should be prime.
    for j = 0; j < f.length(); j = j + 1 {
      assert_eq(is_prime64(f[j].to_int64()), true)
    }
  }
}
