/// Shared Int64 arithmetic utilities for number-theory packages.
///
/// Provides `mod64`, `gcd64`, `pow_mod64`, and `is_prime64` — functions that
/// were previously duplicated across `bsgs`, `crt`, `pollard_rho`, and
/// `miller_rabin`. Centralising them here means a bug fix or optimisation
/// only needs to happen once.
///
/// **Overflow safety.** All arithmetic is in `Int64`. Because every modulus is
/// a 32-bit `Int` (< 2^31), every intermediate product stays below
/// m^2 < 2^62 < 2^63, so no `Int64` overflow can occur.
///
/// `proof-enabled` is `false`; correctness is backed by the test suites in
/// the consuming packages.

/// Int64 modulo that always returns a result in `[0, m)` for `m > 0`.
///
/// Negative inputs are mapped to their positive residue. This is the canonical
/// reduction used by all number-theory operations that need non-negative
/// representatives.
pub fn mod64(a : Int64, m : Int64) -> Int64 {
  let r = a % m
  if r < 0L {
    r + m
  } else {
    r
  }
}

/// Int64 GCD via the Euclidean algorithm. Inputs are taken in absolute value.
pub fn gcd64(a : Int64, b : Int64) -> Int64 {
  let mut x = if a < 0L { -a } else { a }
  let mut y = if b < 0L { -b } else { b }
  while y != 0L {
    let t = x % y
    x = y
    y = t
  }
  x
}

/// Modular exponentiation in `Int64`: returns `(base^exp) mod m`.
///
/// Requires `m > 0`, `exp >= 0`. Uses binary exponentiation. The base is
/// normalised into `[0, m)` first via [`mod64`], so negative bases are
/// handled correctly. For 32-bit moduli every intermediate product stays
/// below `m^2 < 2^62`.
pub fn pow_mod64(base : Int64, exp : Int64, m : Int64) -> Int64 {
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

/// Deterministic Miller-Rabin primality test for the full `Int64` range
/// relevant to 32-bit `Int` inputs.
///
/// For `n < 2^31` (the full positive range of 32-bit `Int`), the witness set
/// `{2, 7, 61}` suffices (Jaeschke 1993). Returns `true` if `n` is prime,
/// `false` otherwise (including `n < 2`).
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
  let witnesses = [2L, 7L, 61L]
  for i = 0; i < 3; i = i + 1 {
    let a = witnesses[i]
    if a >= n {
      continue
    }
    let mut x = pow_mod64(a, d, n)
    if x == 1L || x == n - 1L {
      continue
    }
    let mut composite = true
    for _r = 0; _r < s - 1; _r = _r + 1 {
      x = x * x % n
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
