/// Quadratic residue and modular square root (Tonelli-Shanks algorithm).
///
/// Given a prime `p` and an integer `a`, determines whether `a` is a
/// quadratic residue mod `p` (i.e., whether `x² ≡ a (mod p)` has a solution)
/// and, if so, computes `x`.
///
/// ## Algorithm
///
/// 1. **Euler's criterion**: `a` is a quadratic residue mod `p` iff
///    `a^((p-1)/2) ≡ 1 (mod p)`. If the result is `p-1`, `a` is a non-residue.
///    `a ≡ 0` is a trivial residue (`x = 0`).
///
/// 2. **Tonelli-Shanks**: For `p ≡ 1 (mod 4)`:
///    - Write `p - 1 = Q · 2^S` with `Q` odd.
///    - Find a quadratic non-residue `z` by trial.
///    - Set `c = z^Q`, `R = a^((Q+1)/2)`, `t = a^Q`, `M = S`.
///    - Loop: if `t ≡ 1`, `R` is the answer. Otherwise find the least `i`
///      such that `t^(2^i) ≡ 1`. Set `b = c^(2^(M-i-1))`, update
///      `R = R·b`, `t = t·b²`, `c = b²`, `M = i`.
///
/// 3. For `p ≡ 3 (mod 4)`: the simple formula `x = a^((p+1)/4) mod p` works.
///
/// ## Complexity
///
/// - Euler's criterion: O(log p) modular multiplications.
/// - Tonelli-Shanks: O(log² p) worst case (expected O(log p) with a good `z`).
/// - Finding `z`: O(√p / log p) expected (half of all residues are non-residues).
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

// ---------------------------------------------------------------------------
// Euler's criterion
// ---------------------------------------------------------------------------

///|
/// Compute the Legendre symbol `(a / p)` for odd prime `p`.
///
/// Returns:
/// - `0` if `a ≡ 0 (mod p)` (a is divisible by p)
/// - `1` if `a` is a quadratic residue mod `p`
/// - `-1` if `a` is a quadratic non-residue mod `p`
///
/// Uses Euler's criterion: `(a / p) = a^((p-1)/2) mod p`.
pub fn legendre(a : Int64, p : Int64) -> Int {
  let a_mod = @int64_utils.mod64(a, p)
  if a_mod == 0L {
    return 0
  }
  let exp = (p - 1L) / 2L
  let r = @int64_utils.pow_mod64(a_mod, exp, p)
  if r == 1L {
    1
  } else {
    -1 // r == p - 1
  }
}

///|
/// Check if `a` is a quadratic residue modulo the odd prime `p`.
pub fn is_quadratic_residue(a : Int64, p : Int64) -> Bool {
  legendre(a, p) >= 0
}

// ---------------------------------------------------------------------------
// Tonelli-Shanks
// ---------------------------------------------------------------------------

///|
/// Compute the modular square root `x` such that `x² ≡ a (mod p)`,
/// where `p` is an odd prime.
///
/// Returns `Some(x)` if a solution exists (i.e., `a` is a quadratic residue),
/// `None` otherwise. When `Some(x)` is returned, both `x` and `p - x` are
/// valid square roots.
///
/// # Special cases
/// - `a ≡ 0 (mod p)`: returns `Some(0)`.
/// - `p = 2`: returns `Some(a mod 2)`.
/// - `p ≡ 3 (mod 4)`: uses the simple formula `a^((p+1)/4) mod p`.
pub fn sqrt_mod(a : Int64, p : Int64) -> Int64? {
  if p == 2L {
    return Some(@int64_utils.mod64(a, p))
  }
  let a_mod = @int64_utils.mod64(a, p)
  if a_mod == 0L {
    return Some(0L)
  }
  // Check Euler's criterion.
  if legendre(a_mod, p) == -1 {
    return None
  }
  // p ≡ 3 (mod 4): simple case.
  if p % 4L == 3L {
    let exp = (p + 1L) / 4L
    return Some(@int64_utils.pow_mod64(a_mod, exp, p))
  }
  // General case: Tonelli-Shanks.
  // Write p - 1 = Q * 2^S with Q odd.
  let mut q = p - 1L
  let mut s = 0
  while q % 2L == 0L {
    q = q / 2L
    s = s + 1
  }
  // Find a quadratic non-residue z.
  let mut z = 2L
  while legendre(z, p) != -1 {
    z = z + 1L
  }
  let mut m = s
  let mut c = @int64_utils.pow_mod64(z, q, p)
  let mut t = @int64_utils.pow_mod64(a_mod, q, p)
  let mut r = @int64_utils.pow_mod64(a_mod, (q + 1L) / 2L, p)
  while t != 1L {
    // Find the least i such that t^(2^i) = 1.
    let mut i = 0
    let mut tmp = t
    while tmp != 1L {
      tmp = @int64_utils.mul_mod(tmp, tmp, p)
      i = i + 1
      if i >= m {
        // Should not happen if a is a QR, but guard against infinite loop.
        return None
      }
    }
    // b = c^(2^(m-i-1)): square c exactly (m - i - 1) times.
    let mut b = c
    for j = 0; j < m - i - 1; j = j + 1 {
      b = @int64_utils.mul_mod(b, b, p)
    }
    r = @int64_utils.mul_mod(r, b, p)
    t = @int64_utils.mul_mod(t, @int64_utils.mul_mod(b, b, p), p)
    c = @int64_utils.mul_mod(b, b, p)
    m = i
  }
  Some(r)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "legendre: basic" {
  // 1 is always a QR.
  assert_eq(legendre(1L, 7L), 1)
  // 2 is a QR mod 7 (3^2 = 9 ≡ 2).
  assert_eq(legendre(2L, 7L), 1)
  // 3 is not a QR mod 7.
  assert_eq(legendre(3L, 7L), -1)
  // 0 mod p.
  assert_eq(legendre(0L, 7L), 0)
  // 2 is not a QR mod 5.
  assert_eq(legendre(2L, 5L), -1)
  // 4 is a QR mod 5 (2^2 = 4).
  assert_eq(legendre(4L, 5L), 1)
}

///|
test "sqrt_mod: p ≡ 3 (mod 4)" {
  // p = 7: QRs are 0,1,2,4. sqrt(2) mod 7 = 3 or 4 (3^2=9≡2, 4^2=16≡2)
  let r = sqrt_mod(2L, 7L)
  assert_true(r is Some(_))
  match r {
    Some(x) => assert_eq(@int64_utils.mul_mod(x, x, 7L), 2L)
    None => abort("expected Some")
  }
  // sqrt(1) mod 7 = 1 or 6.
  match sqrt_mod(1L, 7L) {
    Some(x) => assert_eq(@int64_utils.mul_mod(x, x, 7L), 1L)
    None => abort("expected Some")
  }
  // sqrt(4) mod 7 = 2 or 5.
  match sqrt_mod(4L, 7L) {
    Some(x) => assert_eq(@int64_utils.mul_mod(x, x, 7L), 4L)
    None => abort("expected Some")
  }
  // 3 is not a QR mod 7.
  assert_true(sqrt_mod(3L, 7L) is None)
}

///|
test "sqrt_mod: p ≡ 1 (mod 4)" {
  // p = 5: QRs are 0,1,4. sqrt(4) mod 5 = 2 or 3.
  let r = sqrt_mod(4L, 5L)
  match r {
    Some(x) => assert_eq(@int64_utils.mul_mod(x, x, 5L), 4L)
    None => abort("expected Some")
  }
  // 2 is not a QR mod 5.
  assert_true(sqrt_mod(2L, 5L) is None)
  // p = 13: QRs are 0,1,3,4,9,10,12.
  // sqrt(10) mod 13 = 6 or 7 (6^2=36≡10, 7^2=49≡10).
  match sqrt_mod(10L, 13L) {
    Some(x) => assert_eq(@int64_utils.mul_mod(x, x, 13L), 10L)
    None => abort("expected Some")
  }
  // 2 is not a QR mod 13.
  assert_true(sqrt_mod(2L, 13L) is None)
}

///|
test "sqrt_mod: a = 0" {
  assert_eq(sqrt_mod(0L, 7L), Some(0L))
  assert_eq(sqrt_mod(0L, 13L), Some(0L))
}

///|
test "sqrt_mod: large prime" {
  // p = 1000000007 (prime, p ≡ 3 mod 4)
  let p = 1000000007L
  // 4 is a QR; sqrt(4) = 2 or p-2.
  match sqrt_mod(4L, p) {
    Some(x) => assert_eq(@int64_utils.mul_mod(x, x, p), 4L)
    None => abort("expected Some")
  }
}

///|
test "sqrt_mod: all QRs mod 7" {
  let p = 7L
  for a = 0L; a < p; a = a + 1L {
    match sqrt_mod(a, p) {
      Some(x) => assert_eq(@int64_utils.mul_mod(x, x, p), a)
      None =>
        // a is not a QR.
        assert_eq(legendre(a, p), -1)
    }
  }
}

///|
test "sqrt_mod: all QRs mod 13" {
  let p = 13L
  for a = 0L; a < p; a = a + 1L {
    match sqrt_mod(a, p) {
      Some(x) => assert_eq(@int64_utils.mul_mod(x, x, p), a)
      None => assert_eq(legendre(a, p), -1)
    }
  }
}

///|
test "sqrt_mod: stress test all primes up to 100" {
  // Test sqrt for all residues of primes up to 100.
  let primes = [
    3L, 5L, 7L, 11L, 13L, 17L, 19L, 23L, 29L, 31L, 37L, 41L, 43L, 47L, 53L, 59L,
    61L, 67L, 71L, 73L, 79L, 83L, 89L, 97L,
  ]
  for pi = 0; pi < primes.length(); pi = pi + 1 {
    let p = primes[pi]
    for a = 0L; a < p; a = a + 1L {
      match sqrt_mod(a, p) {
        Some(x) =>
          // Verify x^2 ≡ a (mod p).
          assert_eq(@int64_utils.mul_mod(x, x, p), a)
        None =>
          // a is not a QR.
          assert_eq(legendre(a, p), -1)
      }
    }
  }
}

///|
test "is_quadratic_residue: basic" {
  assert_true(is_quadratic_residue(1L, 7L))
  assert_true(is_quadratic_residue(2L, 7L))
  assert_false(is_quadratic_residue(3L, 7L))
  assert_true(is_quadratic_residue(0L, 7L))
}

///|
test "legendre: p = 2" {
  // p = 2 is a special case (not handled by Euler's criterion).
  // legendre(1, 2) should still work via the function (a mod p = 1, exp = 0,
  // 1^0 = 1).
  assert_eq(legendre(1L, 2L), 1)
}
