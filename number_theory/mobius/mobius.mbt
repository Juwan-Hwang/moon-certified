/// Möbius function and Möbius inversion.
///
/// ## Möbius Function
///
/// The Möbius function `μ(n)` is defined as:
/// - `μ(1) = 1`
/// - `μ(n) = 0` if `n` has a squared prime factor (i.e., is not square-free)
/// - `μ(n) = (-1)^k` if `n` is the product of `k` distinct primes
///
/// ## Möbius Inversion
///
/// If `f(n) = Σ_{d|n} g(d)`, then `g(n) = Σ_{d|n} μ(d) · f(n/d)`.
///
/// ## Algorithms
///
/// 1. **Single value** `μ(n)`: factorise `n` by trial division; if any prime
///    appears with exponent ≥ 2, return 0; otherwise return `(-1)^k`.
/// 2. **Sieve** `μ(1..n)`: linear sieve producing all values in O(n).
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

// ---------------------------------------------------------------------------
// Möbius function (single value)
// ---------------------------------------------------------------------------

///|
/// Compute the Möbius function `μ(n)`.
///
/// Returns:
/// - `1` if `n = 1`
/// - `(-1)^k` if `n` is a product of `k` distinct primes
/// - `0` if `n` has a squared prime factor
///
/// # Complexity
/// O(√n) via trial division.
pub fn mobius(n : Int) -> Int {
  if n <= 0 {
    return 0
  }
  if n == 1 {
    return 1
  }
  let mut m = n
  let mut count = 0
  let mut p = 2
  while p * p <= m {
    if m % p == 0 {
      m = m / p
      if m % p == 0 {
        return 0 // squared factor
      }
      count = count + 1
    }
    p = p + 1
  }
  if m > 1 {
    count = count + 1
  }
  if count % 2 == 0 {
    1
  } else {
    -1
  }
}

// ---------------------------------------------------------------------------
// Möbius sieve
// ---------------------------------------------------------------------------

///|
/// Sieve the Möbius function for all `n` in `[1, N]`.
///
/// Returns a `FixedArray[Int]` of length `N+1` where index `i` holds `μ(i)`.
///
/// # Complexity
/// O(N) using a linear sieve.
pub fn mobius_sieve(n : Int) -> FixedArray[Int] {
  if n < 1 {
    return FixedArray::make(0, 0)
  }
  let mu = FixedArray::make(n + 1, 0)
  mu[1] = 1
  let primes : Array[Int] = []
  let is_composite = FixedArray::make(n + 1, false)
  for i = 2; i <= n; i = i + 1 {
    if !is_composite[i] {
      primes.push(i)
      mu[i] = -1
    }
    for j = 0; j < primes.length() && i * primes[j] <= n; j = j + 1 {
      let p = primes[j]
      is_composite[i * p] = true
      if i % p == 0 {
        mu[i * p] = 0 // p^2 divides i*p
        break
      } else {
        mu[i * p] = -mu[i]
      }
    }
  }
  mu
}

// ---------------------------------------------------------------------------
// Möbius inversion
// ---------------------------------------------------------------------------

///|
/// Given `f(d)` for all divisors `d` of `n`, compute `g(n) = Σ μ(d)·f(n/d)`.
///
/// This is the Möbius inversion formula: if `f(n) = Σ_{d|n} g(d)`, then
/// `g(n) = Σ_{d|n} μ(d) · f(n/d)`.
///
/// The caller provides `f` as a function from `Int` to `Int`.
///
/// # Complexity
/// O(√n) for divisor enumeration + O(√n) for μ computation per divisor.
pub fn mobius_invert(n : Int, f : (Int) -> Int) -> Int {
  if n <= 0 {
    return 0
  }
  let mut result = 0
  let mut d = 1
  while d * d <= n {
    if n % d == 0 {
      let d1 = d
      let d2 = n / d
      result = result + mobius(d1) * f(n / d1)
      if d2 != d1 {
        result = result + mobius(d2) * f(n / d2)
      }
    }
    d = d + 1
  }
  result
}

// ---------------------------------------------------------------------------
// Euler's totient via Möbius
// ---------------------------------------------------------------------------

///|
/// Compute Euler's totient `φ(n)` using the Möbius function:
/// `φ(n) = Σ_{d|n} μ(d) · (n/d)`.
///
/// This is an alternative to the direct computation; it's provided to
/// demonstrate the Möbius inversion identity.
pub fn euler_totient_mobius(n : Int) -> Int {
  if n <= 0 {
    return 0
  }
  mobius_invert(n, fn(d) { d })
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "mobius: basic values" {
  assert_eq(mobius(1), 1)
  assert_eq(mobius(2), -1) // prime
  assert_eq(mobius(3), -1) // prime
  assert_eq(mobius(4), 0) // 2^2
  assert_eq(mobius(5), -1) // prime
  assert_eq(mobius(6), 1) // 2*3, two primes
  assert_eq(mobius(7), -1) // prime
  assert_eq(mobius(8), 0) // 2^3
  assert_eq(mobius(9), 0) // 3^2
  assert_eq(mobius(10), 1) // 2*5
  assert_eq(mobius(11), -1) // prime
  assert_eq(mobius(12), 0) // 2^2*3
  assert_eq(mobius(30), -1) // 2*3*5, three primes
  assert_eq(mobius(210), 1) // 2*3*5*7, four primes
}

///|
test "mobius: zero and negative" {
  assert_eq(mobius(0), 0)
  assert_eq(mobius(-5), 0)
}

///|
test "mobius_sieve: first 30 values" {
  let mu = mobius_sieve(30)
  // Verify against known values.
  assert_eq(mu[1], 1)
  assert_eq(mu[2], -1)
  assert_eq(mu[6], 1)
  assert_eq(mu[30], -1)
  assert_eq(mu[12], 0)
  for i = 1; i <= 30; i = i + 1 {
    assert_eq(mu[i], mobius(i))
  }
}

///|
test "mobius_sieve: stress test 1000" {
  let n = 1000
  let mu = mobius_sieve(n)
  for i = 1; i <= n; i = i + 1 {
    assert_eq(mu[i], mobius(i))
  }
}

///|
test "mobius_invert: Euler's totient" {
  // φ(n) = Σ_{d|n} μ(d) * (n/d) = Σ_{d|n} μ(d) * f(n/d)
  // where f(n) = n.
  assert_eq(euler_totient_mobius(1), 1)
  assert_eq(euler_totient_mobius(7), 6)
  assert_eq(euler_totient_mobius(12), 4)
  assert_eq(euler_totient_mobius(36), 12)
}

///|
test "mobius_invert: identity" {
  // If f(n) = Σ_{d|n} g(d), then g(n) = Σ_{d|n} μ(d) * f(n/d).
  // Test: g(n) = 1 for all n → f(n) = d(n) (number of divisors).
  // Then mobius_invert(n, f) should recover g(n) = 1.
  let num_divisors = fn(n : Int) -> Int {
    let mut count = 0
    let mut d = 1
    while d * d <= n {
      if n % d == 0 {
        count = count + 1
        if d * d != n {
          count = count + 1
        }
      }
      d = d + 1
    }
    count
  }
  for n = 1; n <= 50; n = n + 1 {
    // mobius_invert with f = num_divisors should give 1 (the original g).
    let result = mobius_invert(n, num_divisors)
    assert_eq(result, 1)
  }
}

///|
test "mobius: prime powers" {
  // μ(p) = -1 for prime p
  assert_eq(mobius(13), -1)
  assert_eq(mobius(17), -1)
  assert_eq(mobius(19), -1)
  // μ(p^2) = 0
  assert_eq(mobius(4), 0)
  assert_eq(mobius(9), 0)
  assert_eq(mobius(25), 0)
  assert_eq(mobius(49), 0)
}

///|
test "mobius: squarefree numbers" {
  // Squarefree numbers have μ = ±1.
  // 6 = 2*3 → μ = 1
  assert_eq(mobius(6), 1)
  // 30 = 2*3*5 → μ = -1
  assert_eq(mobius(30), -1)
  // 42 = 2*3*7 → μ = -1
  assert_eq(mobius(42), -1)
  // 70 = 2*5*7 → μ = -1
  assert_eq(mobius(70), -1)
  // 210 = 2*3*5*7 → μ = 1
  assert_eq(mobius(210), 1)
}

///|
test "mobius_sieve: edge cases" {
  let mu0 = mobius_sieve(0)
  assert_eq(mu0.length(), 0)
  let mu1 = mobius_sieve(1)
  assert_eq(mu1.length(), 2)
  assert_eq(mu1[1], 1)
}
