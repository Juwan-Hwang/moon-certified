/// Number-theory primitives: primality, the Sieve of Eratosthenes, the
/// extended Euclidean algorithm and modular inverses.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below,
/// which includes Bézout-identity and round-trip checks.

/// Sieve of Eratosthenes: find all primes up to `n` (inclusive).
///
/// Returns a `FixedArray[Int]` of primes in ascending order.
/// Returns an empty array for `n < 2`.
///
/// Uses an O(n log log n) sieve over a compact boolean composite table:
/// `is_composite[k]` is `true` exactly when `k` has a proper divisor and is
/// therefore not prime. The outer bound is written `p <= n / p` rather than
/// `p * p <= n` so it never overflows for large `n`.
pub fn sieve(n : Int) -> FixedArray[Int] {
  // Guard against n+1 overflow when n is near Int::MAX.
  // Reject unreasonably large inputs to prevent OOM:
  // n = 10^7 allocates ~10^7 booleans (~10–40 MB depending on runtime).
  // n = 10^9 would need ~1 GB and is rejected.
  if n < 2 || n > 10000000 {
    return FixedArray::make(0, 0)
  }
  let is_composite = FixedArray::make(n + 1, false)
  // Mark multiples of each prime p, starting from p*p. Smaller multiples of
  // p were already marked by p's own prime factors.
  let mut p = 2
  while p <= n / p {
    if !is_composite[p] {
      let mut multiple = p * p
      while multiple <= n {
        is_composite[multiple] = true
        multiple = multiple + p
      }
    }
    p = p + 1
  }
  // Two passes — count then fill — so the result array is exactly sized.
  let mut count = 0
  for k = 2; k <= n; k = k + 1 {
    if !is_composite[k] {
      count = count + 1
    }
  }
  let primes = FixedArray::make(count, 0)
  let mut idx = 0
  for k = 2; k <= n; k = k + 1 {
    if !is_composite[k] {
      primes[idx] = k
      idx = idx + 1
    }
  }
  primes
}

/// Check if `n` is prime. Returns `false` for `n < 2`.
///
/// Trial division by 2 and then by odd candidates up to `sqrt(n)`. The bound
/// is written `d <= n / d` to avoid overflow for `n` near `Int`'s range.
pub fn is_prime(n : Int) -> Bool {
  if n < 2 {
    return false
  }
  if n == 2 {
    return true
  }
  if n % 2 == 0 {
    return false
  }
  let mut d = 3
  while d <= n / d {
    if n % d == 0 {
      return false
    }
    d = d + 2
  }
  true
}

/// Extended Euclidean algorithm.
///
/// Returns `(gcd, x, y)` such that `a * x + b * y == gcd(a, b)`. Works for
/// any integer inputs, including negatives and zeros; the sign of the
/// returned gcd follows the sign of `a` (the standard iterative behaviour
/// under truncate-toward-zero division).
///
/// Implemented iteratively to avoid recursion-depth limits and to keep the
/// Bézout coefficients naturally in sync with the remainders: each step
/// advances `(old, cur)` to `(cur, old - q * cur)` simultaneously for the
/// remainder and both coefficients.
pub fn ext_gcd(a : Int, b : Int) -> (Int, Int, Int) {
  let mut old_r = a
  let mut r = b
  let mut old_s = 1
  let mut s = 0
  let mut old_t = 0
  let mut t = 1
  while r != 0 {
    let q = old_r / r
    let new_r = old_r - q * r
    old_r = r
    r = new_r
    let new_s = old_s - q * s
    old_s = s
    s = new_s
    let new_t = old_t - q * t
    old_t = t
    t = new_t
  }
  (old_r, old_s, old_t)
}

/// Modular inverse of `a` modulo `m`.
///
/// Returns `Some(x)` for the unique `x` in `[0, m)` with `a * x ≡ 1 (mod m)`,
/// or `None` if no inverse exists (i.e. `gcd(a, m) != 1`, or `m <= 1`).
///
/// Reduces `a` into `[0, m)` first so the extended Euclidean algorithm always
/// receives non-negative operands; this guarantees a positive gcd and makes
/// the final sign normalisation trivial.
pub fn mod_inverse(a : Int, m : Int) -> Int? {
  if m <= 1 {
    return None
  }
  let a_mod = a % m
  let a_norm = if a_mod < 0 { a_mod + m } else { a_mod }
  let (g, x, _) = ext_gcd(a_norm, m)
  if g != 1 {
    return None
  }
  let inv = x % m
  Some(if inv < 0 { inv + m } else { inv })
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "sieve: basic n=10" {
  let primes = sieve(10)
  assert_eq(primes.length(), 4)
  assert_eq(primes[0], 2)
  assert_eq(primes[1], 3)
  assert_eq(primes[2], 5)
  assert_eq(primes[3], 7)
}

test "sieve: n=2 yields a single prime" {
  let primes = sieve(2)
  assert_eq(primes.length(), 1)
  assert_eq(primes[0], 2)
}

test "sieve: n=100 has 25 primes" {
  let primes = sieve(100)
  assert_eq(primes.length(), 25)
  assert_eq(primes[0], 2)
  assert_eq(primes[24], 97)
  // Spot-check a few well-known primes by index.
  assert_eq(primes[3], 7)
  assert_eq(primes[10], 31)
  assert_eq(primes[20], 73)
}

test "sieve: n<2 returns empty" {
  assert_eq(sieve(1).length(), 0)
  assert_eq(sieve(0).length(), 0)
  assert_eq(sieve(-5).length(), 0)
}

test "sieve: agrees with is_prime up to 50" {
  let primes = sieve(50)
  let mut count = 0
  for k = 0; k <= 50; k = k + 1 {
    if is_prime(k) {
      count = count + 1
    }
  }
  assert_eq(primes.length(), count)
  for i = 0; i < primes.length(); i = i + 1 {
    assert_true(is_prime(primes[i]))
  }
}

test "is_prime: edge cases" {
  assert_eq(is_prime(0), false)
  assert_eq(is_prime(1), false)
  assert_eq(is_prime(2), true)
  assert_eq(is_prime(3), true)
  assert_eq(is_prime(4), false)
  assert_eq(is_prime(-7), false)
  assert_eq(is_prime(-1), false)
}

test "is_prime: small primes and composites" {
  assert_eq(is_prime(7), true)
  assert_eq(is_prime(9), false)
  assert_eq(is_prime(11), true)
  assert_eq(is_prime(25), false)
  assert_eq(is_prime(29), true)
  assert_eq(is_prime(49), false)
  assert_eq(is_prime(97), true)
  assert_eq(is_prime(100), false)
}

test "is_prime: perfect squares of primes" {
  // Squares of primes are composite; a buggy sqrt bound must still catch them.
  assert_eq(is_prime(121), false) // 11 * 11
  assert_eq(is_prime(169), false) // 13 * 13
  assert_eq(is_prime(289), false) // 17 * 17
}

test "ext_gcd: basic" {
  let (g, x, y) = ext_gcd(12, 8)
  assert_eq(g, 4)
  assert_eq(x, 1)
  assert_eq(y, -1)
  assert_eq(12 * x + 8 * y, 4)
}

test "ext_gcd: coprime" {
  let (g, x, y) = ext_gcd(7, 13)
  assert_eq(g, 1)
  assert_eq(7 * x + 13 * y, 1)
}

test "ext_gcd: one operand zero" {
  let (g0, x0, y0) = ext_gcd(5, 0)
  assert_eq(g0, 5)
  assert_eq(5 * x0 + 0 * y0, 5)
  let (g1, x1, y1) = ext_gcd(0, 5)
  assert_eq(g1, 5)
  assert_eq(0 * x1 + 5 * y1, 5)
}

test "ext_gcd: Bezout identity holds over many inputs" {
  // The defining invariant: a*x + b*y == g for all inputs.
  let cases = [
    (12, 8), (7, 13), (1071, 462), (0, 5), (5, 0), (1, 1), (100, 75),
    (17, 5), (5, 17), (270, 192),
  ]
  for i = 0; i < cases.length(); i = i + 1 {
    let (a, b) = cases[i]
    let (g, x, y) = ext_gcd(a, b)
    assert_eq(a * x + b * y, g)
  }
}

test "ext_gcd: negative inputs" {
  // Division truncates toward zero, so the gcd follows the sign of a.
  let (g, x, y) = ext_gcd(-12, 8)
  assert_eq(g, -4)
  assert_eq(x, 1)
  assert_eq(y, 1)
  assert_eq((-12) * x + 8 * y, g)
  let (g2, x2, y2) = ext_gcd(12, -8)
  assert_eq(g2, 4)
  assert_eq(x2, 1)
  assert_eq(y2, 1)
  assert_eq(12 * x2 + (-8) * y2, g2)
}

test "mod_inverse: basic" {
  assert_eq(mod_inverse(3, 7), Some(5)) // 3*5 = 15 = 1 (mod 7)
  assert_eq(mod_inverse(10, 17), Some(12)) // 10*12 = 120 = 1 (mod 17)
  assert_eq(mod_inverse(1, 5), Some(1))
  assert_eq(mod_inverse(2, 5), Some(3)) // 2*3 = 6 = 1 (mod 5)
}

test "mod_inverse: product is congruent to 1" {
  // a * mod_inverse(a, m) ≡ 1 (mod m) for coprime a, m.
  let cases = [(3, 7), (10, 17), (2, 5), (11, 26), (7, 100), (123, 997)]
  for i = 0; i < cases.length(); i = i + 1 {
    let (a, m) = cases[i]
    let inv = mod_inverse(a, m).unwrap()
    assert_true(inv >= 0)
    let prod = (a % m) * inv
    let residue = prod % m
    let norm = if residue < 0 { residue + m } else { residue }
    assert_eq(norm, 1)
  }
}

test "mod_inverse: no inverse when not coprime" {
  assert_true(mod_inverse(2, 4) is None) // gcd 2
  assert_true(mod_inverse(6, 9) is None) // gcd 3
  assert_true(mod_inverse(0, 7) is None) // a ≡ 0
  assert_true(mod_inverse(7, 7) is None) // a ≡ 0 (mod m)
}

test "mod_inverse: invalid modulus" {
  assert_true(mod_inverse(3, 1) is None)
  assert_true(mod_inverse(3, 0) is None)
  assert_true(mod_inverse(3, -5) is None)
}

test "mod_inverse: negative operand" {
  // -3 ≡ 4 (mod 7); inverse of 4 mod 7 is 2, since 4*2 = 8 ≡ 1.
  assert_eq(mod_inverse(-3, 7), Some(2))
  // 17 ≡ 3 (mod 7); inverse of 3 mod 7 is 5.
  assert_eq(mod_inverse(17, 7), Some(5))
}
