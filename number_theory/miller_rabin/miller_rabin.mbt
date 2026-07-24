/// Miller-Rabin primality test.
///
/// A probabilistic primality test that, for bounded inputs, can be made fully
/// deterministic by testing a fixed set of witnesses. This implementation is
/// deterministic for the entire positive range of 32-bit `Int`.
///
/// **Algorithm.** Write n - 1 = d * 2^s with d odd. For a witness a, compute
/// x = a^d mod n. If x == 1 or x == n - 1, n passes for this witness.
/// Otherwise square x up to s - 1 times; if some square equals n - 1, n
/// passes. If none do, n is composite. If n passes for every witness, it is
/// prime.
///
/// **Determinism.** For n < 2^31 (the full positive range of 32-bit `Int`),
/// the witness set {2, 7, 61} suffices (Jaeschke 1993). The larger set
/// {2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37} suffices for n <
/// 3,317,044,064,679,887,385,961,981, far beyond `Int`'s range, so the smaller
/// set is used here.
///
/// **Complexity.** O(k * log n) modular multiplications with k = 3 witnesses.
///
/// **Overflow safety.** All modular exponentiation is performed in `Int64`.
/// Since n < 2^31, every intermediate product is below 2^62 < 2^63, so no
/// `Int64` overflow can occur.
///
/// The core `is_prime64` and `pow_mod64` functions are shared via
/// `@int64_utils` to avoid code duplication with `pollard_rho` and `bsgs`.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below,
/// which cross-checks against trial division and includes Carmichael numbers
/// and the largest 32-bit prime.

/// Test whether `n` is prime.
///
/// Returns `false` for `n < 2`, `true` for `n == 2` or `n == 3`, `false` for
/// even `n > 2`, and otherwise applies the deterministic Miller-Rabin test
/// with witnesses {2, 7, 61}, which is exact for all `n < 2^31`.
///
/// This delegates to `@int64_utils.is_prime64` to avoid duplicating the
/// Miller-Rabin implementation across packages.
pub fn is_prime(n : Int) -> Bool {
  @int64_utils.is_prime64(n.to_int64())
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

/// Trial-division primality test, independent of Miller-Rabin, used only to
/// cross-check `is_prime` in the test below.
fn is_prime_trial(n : Int) -> Bool {
  if n < 2 {
    return false
  }
  if n < 4 {
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

test "is_prime: small primes" {
  assert_eq(is_prime(2), true)
  assert_eq(is_prime(3), true)
  assert_eq(is_prime(5), true)
  assert_eq(is_prime(7), true)
  assert_eq(is_prime(11), true)
  assert_eq(is_prime(13), true)
}

test "is_prime: small composites" {
  assert_eq(is_prime(4), false)
  assert_eq(is_prime(6), false)
  assert_eq(is_prime(8), false)
  assert_eq(is_prime(9), false)
  assert_eq(is_prime(15), false)
  assert_eq(is_prime(21), false)
}

test "is_prime: zero and one are not prime" {
  assert_eq(is_prime(0), false)
  assert_eq(is_prime(1), false)
}

test "is_prime: negative numbers are not prime" {
  assert_eq(is_prime(-1), false)
  assert_eq(is_prime(-2), false)
  assert_eq(is_prime(-7), false)
  assert_eq(is_prime(-100), false)
}

test "is_prime: even numbers above two" {
  assert_eq(is_prime(100), false)
  assert_eq(is_prime(1000), false)
  assert_eq(is_prime(2147483646), false)
}

test "is_prime: perfect squares of primes" {
  // Squares of primes are composite; the test must still catch them.
  assert_eq(is_prime(121), false) // 11 * 11
  assert_eq(is_prime(169), false) // 13 * 13
  assert_eq(is_prime(289), false) // 17 * 17
  assert_eq(is_prime(841), false) // 29 * 29
}

test "is_prime: large prime near Int32 max" {
  // 2^31 - 1 = 2147483647 is a Mersenne prime (M31).
  assert_eq(is_prime(2147483647), true)
  // 2147483646 = 2 * 1073741823 is composite.
  assert_eq(is_prime(2147483646), false)
}

test "is_prime: odd composite near Int32 max" {
  // 2147483645 = 5 * 429496729; odd, so it exercises the full test path.
  assert_eq(is_prime(2147483645), false)
}

test "is_prime: more large primes" {
  assert_eq(is_prime(1000003), true)
  assert_eq(is_prime(9999991), true)
  assert_eq(is_prime(1299709), true)
  assert_eq(is_prime(2147483629), true)
}

test "is_prime: Carmichael numbers are composite" {
  // Carmichael numbers pass the Fermat test for every coprime base but are
  // composite; Miller-Rabin must still detect them.
  assert_eq(is_prime(561), false)
  assert_eq(is_prime(1105), false)
  assert_eq(is_prime(1729), false)
  assert_eq(is_prime(2465), false)
  assert_eq(is_prime(2821), false)
  assert_eq(is_prime(6601), false)
}

test "is_prime: agrees with trial division up to 5000" {
  for n = 0; n <= 5000; n = n + 1 {
    assert_eq(is_prime(n), is_prime_trial(n))
  }
}
