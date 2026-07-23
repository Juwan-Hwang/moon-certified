/// Euler's Linear Sieve: generates all primes up to n in O(n) time.
///
/// Each composite number is crossed off exactly once — by its smallest prime
/// factor — guaranteeing optimal linear complexity. The sieve also records the
/// smallest prime factor (spf) for every integer ≤ n, enabling O(log n)
/// factorisation of any value up to n.
///
/// Complexity:
/// - `sieve(n)` — O(n) time, O(n) space.
/// - `factorize(x)` — O(log x) per call (requires `x ≤ n`).
///
/// Limitations:
/// - `n` must fit in `Int` and the resulting array of size `n + 1` must fit in
///   memory. For `n` near `Int::MAX` the allocation will fail.
/// - `factorize` returns `None` for `x < 2` or `x > n` (out of sieved range).

/// Result of an Euler sieve: the list of primes and the spf (smallest prime
/// factor) table.
///
/// `spf[i]` is the smallest prime factor of `i` for `i ≥ 2`; `spf[0]` and
/// `spf[1]` are `0` (sentinel, never used). `primes` is the ascending list of
/// all primes ≤ n.
pub struct EulerSieve {
  primes : FixedArray[Int]
  spf : FixedArray[Int] // smallest prime factor, 0 for 0 and 1
  limit : Int
}

/// Run the Euler linear sieve up to `n` (inclusive).
///
/// Returns a struct containing the sorted list of primes and the spf table.
/// Panics if `n < 2` (nothing to sieve) — callers should guard with `n ≥ 2`.
pub fn sieve(n : Int) -> EulerSieve {
  if n < 2 {
    return { primes: FixedArray::make(0, 0), spf: FixedArray::make(0, 0), limit: n }
  }
  let spf = FixedArray::make(n + 1, 0)
  // Upper bound on prime count: n / ln(n) * 1.26 ≈ n for small n; use n/3 + 8
  // which is a safe over-estimate for all n ≥ 2.
  let prime_cap = n / 3 + 8
  let primes_buf = FixedArray::make(prime_cap, 0)
  let mut count = 0
  for i = 2; i <= n; i = i + 1 {
    if spf[i] == 0 {
      // i is prime
      spf[i] = i
      primes_buf[count] = i
      count = count + 1
    }
    // For each prime p ≤ spf[i], mark p * i as composite with spf = p
    for j = 0; j < count; j = j + 1 {
      let p = primes_buf[j]
      let composite = p * i
      if composite > n {
        break
      }
      spf[composite] = p
      if p == spf[i] {
        break
      }
    }
  }
  // Trim primes array to actual count
  let primes = FixedArray::make(count, 0)
  for i = 0; i < count; i = i + 1 {
    primes[i] = primes_buf[i]
  }
  { primes, spf, limit: n }
}

/// Return the array of primes found by the sieve, in ascending order. O(1).
pub fn primes(s : EulerSieve) -> FixedArray[Int] {
  s.primes
}

/// Return the smallest prime factor of `x` (requires `2 ≤ x ≤ limit`).
/// Returns `None` if `x` is out of the sieved range.
pub fn smallest_prime_factor(s : EulerSieve, x : Int) -> Int? {
  if x < 2 || x > s.limit {
    return None
  }
  Some(s.spf[x])
}

/// Factorize `x` into a list of (prime, exponent) pairs, sorted by prime.
///
/// Requires `2 ≤ x ≤ limit` (the sieve's upper bound). Returns `None` for
/// out-of-range or invalid input. Runs in O(log x) time.
pub fn factorize(s : EulerSieve, x : Int) -> Array[(Int, Int)]? {
  if x < 2 || x > s.limit {
    return None
  }
  let result = []
  let mut m = x
  while m > 1 {
    let p = s.spf[m]
    let mut exp = 0
    while m % p == 0 {
      exp = exp + 1
      m = m / p
    }
    result.push((p, exp))
  }
  Some(result)
}

/// Check if `x` is prime (requires `2 ≤ x ≤ limit`).
/// Returns `false` for values outside the sieved range.
pub fn is_prime(s : EulerSieve, x : Int) -> Bool {
  if x < 2 || x > s.limit {
    return false
  }
  s.spf[x] == x
}

/// Count the number of primes ≤ n. O(1).
pub fn prime_count(s : EulerSieve) -> Int {
  s.primes.length()
}

/// Return the k-th prime (0-indexed). Returns `None` if k is out of range.
pub fn nth_prime(s : EulerSieve, k : Int) -> Int? {
  if k < 0 || k >= s.primes.length() {
    return None
  }
  Some(s.primes[k])
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "euler_sieve: basic primes up to 30" {
  let s = sieve(30)
  let ps = primes(s)
  assert_eq(ps.length(), 10)
  assert_eq(ps[0], 2)
  assert_eq(ps[1], 3)
  assert_eq(ps[2], 5)
  assert_eq(ps[3], 7)
  assert_eq(ps[4], 11)
  assert_eq(ps[5], 13)
  assert_eq(ps[6], 17)
  assert_eq(ps[7], 19)
  assert_eq(ps[8], 23)
  assert_eq(ps[9], 29)
}

test "euler_sieve: prime count matches known values" {
  assert_eq(prime_count(sieve(10)), 4)
  assert_eq(prime_count(sieve(100)), 25)
  assert_eq(prime_count(sieve(1000)), 168)
  assert_eq(prime_count(sieve(10000)), 1229)
}

test "euler_sieve: is_prime" {
  let s = sieve(100)
  assert_true(is_prime(s, 2))
  assert_true(is_prime(s, 97))
  assert_false(is_prime(s, 1))
  assert_false(is_prime(s, 100))
  assert_false(is_prime(s, 99))
  assert_false(is_prime(s, 101)) // out of range
}

test "euler_sieve: smallest prime factor" {
  let s = sieve(100)
  assert_eq(smallest_prime_factor(s, 2), Some(2))
  assert_eq(smallest_prime_factor(s, 12), Some(2))
  assert_eq(smallest_prime_factor(s, 49), Some(7))
  assert_eq(smallest_prime_factor(s, 97), Some(97))
  assert_eq(smallest_prime_factor(s, 1), None)
  assert_eq(smallest_prime_factor(s, 101), None) // out of range
}

test "euler_sieve: factorize" {
  let s = sieve(10000)
  let f = match factorize(s, 360) {
    Some(v) => v
    None => abort("expected factorization")
  }
  assert_eq(f.length(), 3)
  assert_eq(f[0], (2, 3))
  assert_eq(f[1], (3, 2))
  assert_eq(f[2], (5, 1))
}

test "euler_sieve: factorize prime" {
  let s = sieve(1000)
  let f = match factorize(s, 997) {
    Some(v) => v
    None => abort("expected factorization")
  }
  assert_eq(f.length(), 1)
  assert_eq(f[0], (997, 1))
}

test "euler_sieve: factorize power of 2" {
  let s = sieve(1024)
  let f = match factorize(s, 1024) {
    Some(v) => v
    None => abort("expected factorization")
  }
  assert_eq(f.length(), 1)
  assert_eq(f[0], (2, 10))
}

test "euler_sieve: nth_prime" {
  let s = sieve(100)
  assert_eq(nth_prime(s, 0), Some(2))
  assert_eq(nth_prime(s, 1), Some(3))
  assert_eq(nth_prime(s, 24), Some(97))
  assert_eq(nth_prime(s, 25), None) // out of range
  assert_eq(nth_prime(s, -1), None)
}

test "euler_sieve: sieve(1) returns empty" {
  let s = sieve(1)
  assert_eq(prime_count(s), 0)
  assert_false(is_prime(s, 1))
}

test "euler_sieve: sieve(2) returns single prime" {
  let s = sieve(2)
  assert_eq(prime_count(s), 1)
  assert_true(is_prime(s, 2))
  assert_false(is_prime(s, 3))
}

test "euler_sieve: cross-check with trial division" {
  let s = sieve(5000)
  // Verify every spf entry is correct
  for i = 2; i <= 5000; i = i + 1 {
    let p = s.spf[i]
    assert_true(p >= 2)
    assert_true(i % p == 0)
    // p must be prime
    assert_true(s.spf[p] == p)
    // No smaller prime divides i
    for j = 0; j < s.primes.length(); j = j + 1 {
      let q = s.primes[j]
      if q >= p {
        break
      }
      assert_true(i % q != 0)
    }
  }
}
