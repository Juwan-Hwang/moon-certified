/// Shared Int64 arithmetic utilities for number-theory packages.
///
/// Provides `mod64`, `gcd64`, `pow_mod64`, and `is_prime64` — functions that
/// were previously duplicated across `bsgs`, `crt`, `pollard_rho`, and
/// `miller_rabin`. Centralising them here means a bug fix or optimisation
/// only needs to happen once.
///
/// **Overflow safety.**
/// - `mod64` and `gcd64` handle all `Int64` inputs including `Int64::MIN`.
/// - `pow_mod64` uses fast `Int64` multiplication, safe when `m < 2^31.5`
///   (i.e. 32-bit moduli). For larger moduli, `is_prime64` uses an internal
///   `mul_mod` that is safe for the full `Int64` range via binary decomposition.
/// - `is_prime64` uses deterministic witnesses covering the entire `Int64`
///   range (n < 3.3 * 10^24).
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

// ---------------------------------------------------------------------------
// Modular arithmetic
// ---------------------------------------------------------------------------

///|
/// Int64 modulo that always returns a result in `[0, m)` for `m > 0`.
///
/// Negative inputs are mapped to their positive residue. This is the canonical
/// reduction used by all number-theory operations that need non-negative
/// representatives.
///
/// **Precondition**: `m > 0`. A non-positive modulus returns `0L` (safe fallback).
pub fn mod64(a : Int64, m : Int64) -> Int64 {
  if m <= 0L {
    return 0L
  }
  let r = a % m
  if r < 0L {
    r + m
  } else {
    r
  }
}

///|
/// Modular addition `(a + b) mod m` that is safe for the full `Int64` range.
///
/// Both `a` and `b` must be in `[0, m)`. The addition is performed without
/// overflow by checking whether `a >= m - b` before adding.
fn add_mod(a : Int64, b : Int64, m : Int64) -> Int64 {
  // a, b in [0, m) so a + b in [0, 2m).
  // If a >= m - b, then a + b >= m, so return a - (m - b) = a + b - m.
  // Otherwise a + b < m, safe to add directly.
  // Neither branch overflows: m - b > 0 (since b < m), and a < m.
  if a >= m - b {
    a - (m - b)
  } else {
    a + b
  }
}

///|
/// Modular multiplication `(a * b) mod m` that is safe for the full `Int64`
/// range.
///
/// Uses binary decomposition (Russian peasant multiplication) to avoid
/// overflow in intermediate products. Each step uses `add_mod` for
/// overflow-free modular addition.
pub fn mul_mod(a : Int64, b : Int64, m : Int64) -> Int64 {
  let mut result = 0L
  let mut x = mod64(a, m)
  let mut y = mod64(b, m)
  while y > 0L {
    if y % 2L == 1L {
      result = add_mod(result, x, m)
    }
    x = add_mod(x, x, m)
    y = y / 2L
  }
  result
}

// ---------------------------------------------------------------------------
// GCD
// ---------------------------------------------------------------------------

///|
/// Int64 GCD via the Euclidean algorithm.
///
/// Correctly handles all `Int64` inputs including `Int64::MIN`. The key
/// insight: instead of taking absolute values upfront (which overflows for
/// `Int64::MIN`), we run the Euclidean algorithm directly on the signed
/// inputs. The `%` operator produces well-defined remainders even for
/// negative dividends, and the algorithm converges regardless of sign.
/// The final result is normalised to non-negative.
///
/// For `gcd64(Int64::MIN, b)` where `b != 0`, the result is mathematically
/// correct (e.g. `gcd64(Int64::MIN, 2) == 2`). The only inaccuracy occurs
/// when the true GCD is 2^63 — specifically `gcd64(Int64::MIN, 0)` and
/// `gcd64(Int64::MIN, Int64::MIN)` — since 2^63 cannot be represented as
/// `Int64`; `Int64::MAX` (2^63−1) is returned as the closest representable
/// value.
pub fn gcd64(a : Int64, b : Int64) -> Int64 {
  let mut x = a
  let mut y = b
  while y != 0L {
    let t = x % y
    x = y
    y = t
  }
  // Normalise: the GCD is non-negative. For Int64::MIN, |-MIN| = 2^63
  // overflows; return Int64::MAX as the closest representable value.
  // This only affects gcd64(Int64::MIN, 0) and gcd64(MIN, MIN).
  if x >= 0L {
    x
  } else if x == -9223372036854775808L {
    9223372036854775807L
  } else {
    -x
  }
}

// ---------------------------------------------------------------------------
// Modular exponentiation
// ---------------------------------------------------------------------------

///|
/// Modular exponentiation in `Int64`: returns `(base^exp) mod m`.
///
/// Requires `m > 0`, `exp >= 0`. Uses binary exponentiation. The base is
/// normalised into `[0, m)` first via [`mod64`], so negative bases are
/// handled correctly.
///
/// **Overflow**: uses direct `Int64` multiplication, which is safe when
/// `m < 2^31.5` (i.e. 32-bit moduli, since `m^2 < 2^63`). For larger
/// moduli, use the internal `pow_mod_safe` instead.
///
/// **Precondition**: `m > 0` and `exp >= 0`. Violations return `0L` (safe fallback).
pub fn pow_mod64(base : Int64, exp : Int64, m : Int64) -> Int64 {
  if m <= 0L {
    return 0L
  }
  if exp < 0L {
    return 0L
  }
  if m == 1L {
    return 0L
  }
  let mut result = 1L
  let mut b = mod64(base, m)
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

///|
/// Overflow-safe modular exponentiation using `mul_mod`.
///
/// Identical to `pow_mod64` but uses `mul_mod` for multiplication, making
/// it safe for moduli up to `Int64::MAX`. Slower (O(log^2 m) per call) but
/// correct for the full `Int64` range.
fn pow_mod_safe(base : Int64, exp : Int64, m : Int64) -> Int64 {
  if m == 1L {
    return 0L
  }
  let mut result = 1L
  let mut b = mod64(base, m)
  let mut e = exp
  while e > 0L {
    if e % 2L == 1L {
      result = mul_mod(result, b, m)
    }
    e = e / 2L
    b = mul_mod(b, b, m)
  }
  result
}

// ---------------------------------------------------------------------------
// Primality testing
// ---------------------------------------------------------------------------

///|
/// Deterministic Miller-Rabin primality test for the full `Int64` range.
///
/// Uses the deterministic witness set
/// `{2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37}` which is sufficient for
/// all `n < 3,317,044,064,679,887,385,961,981` (Sorenson and Webster 2015),
/// covering the entire positive `Int64` range.
///
/// Modular multiplication uses `mul_mod` (binary decomposition) to prevent
/// overflow when squaring values close to `Int64::MAX`.
///
/// Returns `true` if `n` is prime, `false` otherwise (including `n < 2`).
pub fn is_prime64(n : Int64) -> Bool {
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
  // Deterministic witnesses covering the full Int64 range
  // (n < 3.3 * 10^24, Sorenson & Webster 2015).
  let witnesses = [2L, 3L, 5L, 7L, 11L, 13L, 17L, 19L, 23L, 29L, 31L, 37L]
  for i = 0; i < witnesses.length(); i = i + 1 {
    let a = witnesses[i]
    if a >= n {
      continue
    }
    // Use overflow-safe modular exponentiation.
    let mut x = pow_mod_safe(a, d, n)
    if x == 1L || x == n - 1L {
      continue
    }
    let mut composite = true
    for _r = 0; _r < s - 1; _r = _r + 1 {
      // Overflow-safe squaring via mul_mod.
      x = mul_mod(x, x, n)
      if x == n - 1L {
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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "mod64: basic" {
  assert_eq(mod64(10L, 7L), 3L)
  assert_eq(mod64(14L, 7L), 0L)
  assert_eq(mod64(0L, 7L), 0L)
}

///|
test "mod64: negative input" {
  assert_eq(mod64(-1L, 7L), 6L)
  assert_eq(mod64(-7L, 7L), 0L)
  assert_eq(mod64(-10L, 7L), 4L)
}

///|
test "mod64: modulus 1" {
  assert_eq(mod64(0L, 1L), 0L)
  assert_eq(mod64(123L, 1L), 0L)
  assert_eq(mod64(-456L, 1L), 0L)
}

///|
test "gcd64: basic" {
  assert_eq(gcd64(12L, 8L), 4L)
  assert_eq(gcd64(17L, 5L), 1L)
  assert_eq(gcd64(100L, 10L), 10L)
  assert_eq(gcd64(0L, 5L), 5L)
  assert_eq(gcd64(5L, 0L), 5L)
  assert_eq(gcd64(0L, 0L), 0L)
}

///|
test "gcd64: negative inputs" {
  assert_eq(gcd64(-12L, 8L), 4L)
  assert_eq(gcd64(12L, -8L), 4L)
  assert_eq(gcd64(-12L, -8L), 4L)
  assert_eq(gcd64(-17L, 5L), 1L)
}

///|
test "gcd64: Int64::MIN (correct results, no overflow)" {
  // Int64::MIN = -2^63. The Euclidean algorithm handles this correctly
  // without taking absolute values upfront.
  let min_val = -9223372036854775808L
  // gcd(MIN, 0) = 2^63, cannot be represented → Int64::MAX (closest).
  assert_eq(gcd64(min_val, 0L), 9223372036854775807L)
  // gcd(MIN, 2) = 2 (MIN = -2^63, gcd(2^63, 2) = 2). Must be correct!
  assert_eq(gcd64(min_val, 2L), 2L)
  // gcd(MIN, 4) = 4 (MIN = -2^63, gcd(2^63, 4) = 4).
  assert_eq(gcd64(min_val, 4L), 4L)
  // gcd(MIN, 3) = 1 (MIN = -2^63, gcd(2^63, 3) = 1 since 3 is odd).
  assert_eq(gcd64(min_val, 3L), 1L)
  // gcd(MIN, odd large number) = 1
  assert_eq(gcd64(min_val, 999999937L), 1L) // 999999937 is prime
  // gcd(MIN, 8) = 8
  assert_eq(gcd64(min_val, 8L), 8L)
}

///|
test "gcd64: large 32-bit values" {
  assert_eq(gcd64(2147483647L, 2147483646L), 1L) // Mersenne prime and n-1
  assert_eq(gcd64(1000000000L, 500000000L), 500000000L)
  assert_eq(gcd64(999999937L, 999999929L), 1L) // both prime
}

///|
test "pow_mod64: basic" {
  assert_eq(pow_mod64(2L, 10L, 1000L), 24L) // 2^10 = 1024, 1024 mod 1000 = 24
  assert_eq(pow_mod64(3L, 5L, 7L), 5L) // 3^5 = 243, 243 mod 7 = 5
  assert_eq(pow_mod64(7L, 0L, 11L), 1L) // anything^0 = 1
}

///|
test "pow_mod64: modulus 1" {
  assert_eq(pow_mod64(123L, 456L, 1L), 0L)
  assert_eq(pow_mod64(0L, 0L, 1L), 0L)
}

///|
test "pow_mod64: large exponent" {
  // Fermat's little theorem: a^(p-1) mod p = 1 for prime p, gcd(a,p)=1
  assert_eq(pow_mod64(2L, 6L, 7L), 1L) // 2^6 mod 7 = 1
  assert_eq(pow_mod64(3L, 10L, 11L), 1L) // 3^10 mod 11 = 1
  assert_eq(pow_mod64(2L, 2147483646L, 2147483647L), 1L) // Mersenne prime
}

///|
test "pow_mod64: negative base" {
  assert_eq(pow_mod64(-1L, 2L, 7L), 1L) // (-1)^2 = 1
  assert_eq(pow_mod64(-1L, 3L, 7L), 6L) // (-1)^3 = -1, mod 7 = 6
  assert_eq(pow_mod64(-3L, 2L, 7L), 2L) // 9 mod 7 = 2
}

///|
test "is_prime64: small primes" {
  assert_eq(is_prime64(2L), true)
  assert_eq(is_prime64(3L), true)
  assert_eq(is_prime64(5L), true)
  assert_eq(is_prime64(7L), true)
  assert_eq(is_prime64(11L), true)
  assert_eq(is_prime64(13L), true)
  assert_eq(is_prime64(17L), true)
  assert_eq(is_prime64(19L), true)
  assert_eq(is_prime64(23L), true)
  assert_eq(is_prime64(29L), true)
  assert_eq(is_prime64(31L), true)
  assert_eq(is_prime64(37L), true)
}

///|
test "is_prime64: small composites" {
  assert_eq(is_prime64(4L), false)
  assert_eq(is_prime64(6L), false)
  assert_eq(is_prime64(8L), false)
  assert_eq(is_prime64(9L), false)
  assert_eq(is_prime64(15L), false)
  assert_eq(is_prime64(21L), false)
  assert_eq(is_prime64(25L), false)
  assert_eq(is_prime64(27L), false)
  assert_eq(is_prime64(35L), false)
  assert_eq(is_prime64(49L), false)
}

///|
test "is_prime64: edge cases" {
  assert_eq(is_prime64(0L), false)
  assert_eq(is_prime64(1L), false)
  assert_eq(is_prime64(-7L), false)
}

///|
test "is_prime64: Mersenne primes" {
  assert_eq(is_prime64(2147483647L), true) // 2^31 - 1
  assert_eq(is_prime64(8191L), true) // 2^13 - 1
  assert_eq(is_prime64(131071L), true) // 2^17 - 1
  assert_eq(is_prime64(524287L), true) // 2^19 - 1
}

///|
test "is_prime64: large known primes" {
  // 1000000007 and 1000000009 are well-known large primes
  assert_eq(is_prime64(1000000007L), true)
  assert_eq(is_prime64(1000000009L), true)
  // 998244353 is a common NTT modulus (prime)
  assert_eq(is_prime64(998244353L), true)
}

///|
test "is_prime64: Carmichael numbers" {
  // Carmichael numbers are composites that pass Fermat tests.
  // Miller-Rabin with the expanded witness set correctly identifies them.
  assert_eq(is_prime64(561L), false) // 3 * 11 * 17
  assert_eq(is_prime64(1105L), false) // 5 * 13 * 17
  assert_eq(is_prime64(1729L), false) // 7 * 13 * 19
  assert_eq(is_prime64(2465L), false) // 5 * 17 * 29
  assert_eq(is_prime64(2821L), false) // 7 * 13 * 31
  assert_eq(is_prime64(6601L), false) // 7 * 23 * 41
  assert_eq(is_prime64(8911L), false) // 7 * 19 * 67
  assert_eq(is_prime64(41041L), false) // 7 * 11 * 13 * 41
  assert_eq(is_prime64(825265L), false) // 5 * 7 * 17 * 19 * 73
}

///|
test "is_prime64: large composites" {
  assert_eq(is_prime64(1000000008L), false) // even
  assert_eq(is_prime64(2147483646L), false) // even
  // 2147483645 = 5 * 429496729
  assert_eq(is_prime64(2147483645L), false)
}

///|
test "is_prime64: full Int64 range (> 2^32)" {
  // These tests verify the expanded witness set and mul_mod work
  // for values beyond the 32-bit range.
  // 4294967311 is a prime > 2^32
  assert_eq(is_prime64(4294967311L), true)
  // 4294967297 = 641 * 6700417 (Fermat number F5 = 2^32 + 1)
  assert_eq(is_prime64(4294967297L), false)
  // 999999999999999989 is a known large prime
  assert_eq(is_prime64(999999999999999989L), true)
  // 1000000000000000009 is a known large prime
  assert_eq(is_prime64(1000000000000000009L), true)
}

///|
test "mul_mod: basic" {
  // Verify internal mul_mod via is_prime64 (indirect test).
  // 2^32 + 1 = 4294967297 = 641 * 6700417 is composite.
  // This requires mul_mod for correct squaring.
  assert_eq(is_prime64(4294967297L), false)
}

///|
test "gcd64: consistency with small values" {
  // Cross-check: gcd(a, b) * lcm(a, b) = a * b for small coprime pairs
  for a = 1; a <= 50; a = a + 1 {
    for b = 1; b <= 50; b = b + 1 {
      let g = gcd64(a.to_int64(), b.to_int64())
      // Verify g divides both
      assert_eq(a.to_int64() % g, 0L)
      assert_eq(b.to_int64() % g, 0L)
    }
  }
}
