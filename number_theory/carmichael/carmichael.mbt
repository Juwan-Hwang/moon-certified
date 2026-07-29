/// Carmichael lambda function λ(n).
///
/// The Carmichael function λ(n) is the smallest positive integer m such that
/// a^m ≡ 1 (mod n) for every integer a coprime to n. Equivalently, it is the
/// exponent of the multiplicative group (ℤ/nℤ)× — the least common multiple
/// of the multiplicative orders of all elements.
///
/// **Formula.** Let n = ∏ p_i^{e_i} be the prime factorisation of n.
///   λ(n) = lcm( λ(p_1^{e_1}), …, λ(p_k^{e_k}) )
/// where the function on prime powers is:
///   λ(2)      = 1
///   λ(4)      = 2
///   λ(2^e)    = 2^{e−2}             for e ≥ 3
///   λ(p^e)    = p^{e−1} · (p − 1)    for odd primes p
///
/// **Relation to Euler's totient.** λ(n) divides φ(n) for all n; they coincide
/// when (ℤ/nℤ)× is cyclic, i.e. for n ∈ {1, 2, 4, p^e, 2·p^e} (odd prime p).
///
/// **Carmichael numbers.** A composite n with λ(n) | (n − 1) is a Carmichael
/// number — it passes the Fermat primality test for every coprime base.
///
/// **Reference.**
/// - R. D. Carmichael, "On composite numbers p which satisfy the Fermat
///   congruence a^{p−1} ≡ 1 (mod p)", Amer. Math. Monthly 19, 22–27 (1912).
/// - J. S. Frame, "A short proof of a theorem of Carmichael", Bull. AMS 45
///   (1939).
/// - Handbook of Applied Cryptography (Menezes, van Oorschot, Vanstone),
///   Algorithm 2.143.
///
/// **Complexity.** O(√n) — dominated by trial-division factorisation.
///
/// **Overflow safety.** All intermediate values are at most n (the lcm of any
/// subset of prime-power lambdas divides λ(n) ≤ n), so every computation
/// stays within the 32-bit `Int` range. The trial-division bound `p ≤ m / p`
/// avoids overflow that `p * p ≤ m` would risk.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below,
/// which includes exponent-order verification and cross-checks with φ(n).

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

///|
/// Greatest common divisor of two non-negative integers (Euclidean algorithm).
fn igcd(a : Int, b : Int) -> Int {
  let mut x = a
  let mut y = b
  while y != 0 {
    let t = x % y
    x = y
    y = t
  }
  x
}

///|
/// Least common multiple of two non-negative integers.
///
/// Computed as `a / gcd(a, b) * b` (division first) so that the intermediate
/// value never exceeds the true lcm, which is always ≤ λ(n) ≤ n.
fn ilcm(a : Int, b : Int) -> Int {
  if a == 0 || b == 0 {
    return 0
  }
  a / igcd(a, b) * b
}

///|
/// Carmichael lambda of a single prime power p^e.
///
/// - λ(2) = 1,  λ(4) = 2,  λ(2^e) = 2^{e−2} for e ≥ 3.
/// - λ(p^e) = p^{e−1} · (p − 1) for odd primes p.
fn lambda_prime_power(p : Int, e : Int) -> Int {
  if p == 2 {
    if e == 1 {
      1
    } else if e == 2 {
      2
    } else {
      // e ≥ 3: λ(2^e) = 2^{e−2}.  2^{e−2} ≤ 2^e ≤ n, so no overflow.
      1 << (e - 2)
    }
  } else {
    // p^{e−1} accumulated by repeated multiplication; the result
    // p^{e−1}(p−1) = p^e − p^{e−1} < p^e ≤ n, so no overflow.
    let mut pe1 = 1
    for _i = 0; _i < e - 1; _i = _i + 1 {
      pe1 = pe1 * p
    }
    pe1 * (p - 1)
  }
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

///|
/// Compute the Carmichael function λ(n).
///
/// Returns the smallest positive integer m such that a^m ≡ 1 (mod n) for
/// every a with gcd(a, n) = 1. For n ≤ 0 the result is 0 (undefined domain);
/// λ(1) = 1.
///
/// **Algorithm.** Trial-division factorisation of n into prime powers,
/// evaluation of λ on each prime power, and reduction via lcm.
pub fn carmichael(n : Int) -> Int {
  if n <= 0 {
    return 0
  }
  if n == 1 {
    return 1
  }
  let mut result = 1
  let mut m = n
  // --- Extract factor 2^e -----------------------------------------------
  if m % 2 == 0 {
    let mut e = 0
    while m % 2 == 0 {
      e = e + 1
      m = m / 2
    }
    result = ilcm(result, lambda_prime_power(2, e))
  }
  // --- Extract odd prime factors ----------------------------------------
  // Bound p ≤ m / p (not p * p ≤ m) to avoid overflow.
  let mut p = 3
  while p <= m / p {
    if m % p == 0 {
      let mut e = 0
      while m % p == 0 {
        e = e + 1
        m = m / p
      }
      result = ilcm(result, lambda_prime_power(p, e))
    }
    p = p + 2
  }
  // --- Remaining m > 1 is a prime with exponent 1 ------------------------
  if m > 1 {
    result = ilcm(result, lambda_prime_power(m, 1))
  }
  result
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "carmichael: required values" {
  assert_eq(carmichael(8), 2) // λ(2^3) = 2^{3−2} = 2
  assert_eq(carmichael(12), 2) // λ(4·3) = lcm(2, 2) = 2
  assert_eq(carmichael(15), 4) // λ(3·5) = lcm(2, 4) = 4
  assert_eq(carmichael(561), 80) // λ(3·11·17) = lcm(2, 10, 16) = 80
}

///|
test "carmichael: powers of two" {
  assert_eq(carmichael(2), 1) // λ(2) = 1
  assert_eq(carmichael(4), 2) // λ(4) = 2
  assert_eq(carmichael(8), 2) // λ(8) = 2^{3−2} = 2
  assert_eq(carmichael(16), 4) // λ(16) = 2^{4−2} = 4
  assert_eq(carmichael(32), 8) // λ(32) = 2^{5−2} = 8
  assert_eq(carmichael(64), 16) // λ(64) = 2^{6−2} = 16
  assert_eq(carmichael(128), 32) // λ(128) = 2^{7−2} = 32
  assert_eq(carmichael(256), 64) // λ(256) = 2^{8−2} = 64
}

///|
test "carmichael: odd prime powers" {
  assert_eq(carmichael(3), 2) // λ(3) = 3^0·2 = 2
  assert_eq(carmichael(9), 6) // λ(9) = 3^1·2 = 6
  assert_eq(carmichael(27), 18) // λ(27) = 3^2·2 = 18
  assert_eq(carmichael(81), 54) // λ(81) = 3^3·2 = 54
  assert_eq(carmichael(5), 4) // λ(5) = 5^0·4 = 4
  assert_eq(carmichael(25), 20) // λ(25) = 5^1·4 = 20
  assert_eq(carmichael(125), 100) // λ(125) = 5^2·4 = 100
  assert_eq(carmichael(7), 6) // λ(7) = 7^0·6 = 6
  assert_eq(carmichael(49), 42) // λ(49) = 7^1·6 = 42
  assert_eq(carmichael(11), 10) // λ(11) = 11^0·10 = 10
  assert_eq(carmichael(121), 110) // λ(121) = 11^1·10 = 110
}

///|
test "carmichael: edge cases" {
  assert_eq(carmichael(1), 1)
  assert_eq(carmichael(0), 0)
  assert_eq(carmichael(-5), 0)
}

///|
test "carmichael: divides Euler totient" {
  // λ(n) must divide φ(n) for all n ≥ 1.  φ is computed by brute force.
  let cases = [
    2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 15, 20, 24, 30, 561, 1105, 1729,
  ]
  for i = 0; i < cases.length(); i = i + 1 {
    let n = cases[i]
    let lam = carmichael(n)
    // Brute-force φ(n): count integers in [1, n] coprime to n.
    let mut phi = 0
    for a = 1; a <= n; a = a + 1 {
      if igcd(a, n) == 1 {
        phi = phi + 1
      }
    }
    // λ(n) | φ(n)
    assert_eq(phi % lam, 0)
  }
}

///|
test "carmichael: exponent property a^lambda ≡ 1 (mod n)" {
  // For every a coprime to n, a^{λ(n)} ≡ 1 (mod n).
  // This is the defining property of the Carmichael function.
  let cases = [3, 5, 7, 8, 9, 12, 15, 20, 24, 561, 1105, 1729]
  for i = 0; i < cases.length(); i = i + 1 {
    let n = cases[i]
    let lam = carmichael(n)
    for a = 1; a < n; a = a + 1 {
      if igcd(a, n) == 1 {
        // Compute a^{lam} mod n via binary exponentiation.
        let mut result = 1
        let mut base = a % n
        let mut e = lam
        while e > 0 {
          if e % 2 == 1 {
            result = result * base % n
          }
          base = base * base % n
          e = e / 2
        }
        assert_eq(result % n, 1)
      }
    }
  }
}

///|
test "carmichael: Carmichael numbers have lambda | (n−1)" {
  // A Carmichael number n satisfies λ(n) | (n − 1), causing it to
  // pass the Fermat test for every coprime base.
  let carmichael_nums = [561, 1105, 1729, 2465, 2821, 6601]
  for i = 0; i < carmichael_nums.length(); i = i + 1 {
    let n = carmichael_nums[i]
    let lam = carmichael(n)
    assert_eq((n - 1) % lam, 0)
  }
}

///|
test "carmichael: lambda equals phi for cyclic groups" {
  // (Z/nZ)+ is cyclic for n ∈ {1, 2, 4, p^e, 2p^e} (odd prime p),
  // so λ(n) = φ(n) for these n.
  assert_eq(carmichael(1), 1) // φ(1) = 1
  assert_eq(carmichael(2), 1) // φ(2) = 1
  assert_eq(carmichael(4), 2) // φ(4) = 2
  assert_eq(carmichael(9), 6) // φ(9) = 6
  assert_eq(carmichael(27), 18) // φ(27) = 18
  assert_eq(carmichael(25), 20) // φ(25) = 20
  assert_eq(carmichael(6), 2) // φ(6) = 2, 6 = 2·3
  assert_eq(carmichael(10), 4) // φ(10) = 4, 10 = 2·5
  assert_eq(carmichael(14), 6) // φ(14) = 6, 14 = 2·7
}

///|
test "carmichael: lambda < phi for non-cyclic groups" {
  // For n with ≥ 2 odd prime factors or 2^e (e ≥ 3), the group is
  // non-cyclic and λ(n) < φ(n).
  assert_eq(carmichael(8), 2) // φ(8) = 4 > 2
  assert_eq(carmichael(15), 4) // φ(15) = 8 > 4
  assert_eq(carmichael(21), 6) // φ(21) = 12 > 6
  assert_eq(carmichael(105), 12) // φ(105) = 48 > 12
}
