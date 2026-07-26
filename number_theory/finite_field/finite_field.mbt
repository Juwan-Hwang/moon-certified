/// Finite field arithmetic: GF(p) and GF(p^n) operations.
///
/// A finite field (Galois field) is a field with a finite number of elements.
/// There are two types:
///
/// - **Prime fields** GF(p): the field of integers modulo a prime p.
/// - **Extension fields** GF(p^n): the field of polynomials over GF(p) modulo
///   an irreducible polynomial of degree n.
///
/// This module provides:
///
/// 1. **GF(p) arithmetic**: addition, subtraction, multiplication, inversion,
///    and exponentiation modulo a prime p. All operations use `Int64` to
///    prevent overflow.
///
/// 2. **GF(2^n) arithmetic**: binary extension fields using polynomial basis.
///    These are widely used in cryptography (AES, elliptic curves, error-
///    correcting codes). Elements are represented as bit vectors (Int64), and
///    multiplication uses carry-less multiplication with modular reduction.
///
/// ## Complexity
///
/// - GF(p) addition/subtraction: O(1).
/// - GF(p) multiplication: O(1).
/// - GF(p) inversion (Fermat's little theorem): O(log p) exponentiations.
/// - GF(2^n) multiplication: O(n) bit operations.
/// - GF(2^n) inversion: O(n) via extended Euclidean or exponentiation.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

// ---------------------------------------------------------------------------
// GF(p): Prime field arithmetic
// ---------------------------------------------------------------------------

///|
/// A prime field GF(p) with modulus `p`.
pub struct PrimeField {
  p : Int64
}

///|
/// Create a prime field GF(p).
///
/// **Precondition**: `p` must be a prime. The constructor does not verify
/// primality for performance; use `@miller_rabin` for verification.
pub fn prime_field(p : Int64) -> PrimeField {
  { p, }
}

///|
/// Add two elements in GF(p).
pub fn pf_add(f : PrimeField, a : Int64, b : Int64) -> Int64 {
  let r = a + b
  let p = f.p
  if r >= p {
    r - p
  } else {
    r
  }
}

///|
/// Subtract two elements in GF(p): returns `(a - b) mod p`.
pub fn pf_sub(f : PrimeField, a : Int64, b : Int64) -> Int64 {
  let p = f.p
  let r = a - b
  if r < 0L {
    r + p
  } else {
    r
  }
}

///|
/// Multiply two elements in GF(p): returns `(a * b) mod p`.
pub fn pf_mul(f : PrimeField, a : Int64, b : Int64) -> Int64 {
  // Use modular multiplication to avoid overflow.
  // Since a, b < p and p can be up to ~2^31, we need Int64 mul_mod.
  mod_mul(a, b, f.p)
}

///|
/// Compute the multiplicative inverse of `a` in GF(p).
///
/// Returns `a^{-1} mod p` via Fermat's little theorem:
/// `a^{p-2} mod p`.
///
/// Returns 0 if `a == 0` (0 has no inverse).
pub fn pf_inv(f : PrimeField, a : Int64) -> Int64 {
  if a == 0L {
    return 0L
  }
  pow_mod(a, f.p - 2L, f.p)
}

///|
/// Divide `a` by `b` in GF(p): returns `a * b^{-1} mod p`.
///
/// Returns 0 if `b == 0`.
pub fn pf_div(f : PrimeField, a : Int64, b : Int64) -> Int64 {
  if b == 0L {
    return 0L
  }
  pf_mul(f, a, pf_inv(f, b))
}

///|
/// Exponentiate: `base^exp mod p`.
pub fn pf_pow(f : PrimeField, base : Int64, exp : Int64) -> Int64 {
  pow_mod(base, exp, f.p)
}

///|
/// Check if `a` is a quadratic residue in GF(p).
///
/// Uses Euler's criterion: `a` is a QR iff `a^{(p-1)/2} == 1 mod p`.
pub fn pf_is_quadratic_residue(f : PrimeField, a : Int64) -> Bool {
  if a == 0L {
    return true
  }
  let p = f.p
  let exp = (p - 1L) / 2L
  pow_mod(a, exp, p) == 1L
}

// ---------------------------------------------------------------------------
// GF(2^n): Binary extension field arithmetic
// ---------------------------------------------------------------------------

///|
/// A binary extension field GF(2^n) defined by an irreducible polynomial.
///
/// Elements are represented as `Int64` bit vectors: bit `i` corresponds to
/// the coefficient of x^i. The irreducible polynomial is also stored as an
/// `Int64` bit vector (the low n+1 bits, with the leading 1 for x^n).
pub struct BinaryField {
  /// The irreducible polynomial (with the x^n term included).
  mod_poly : Int64
  /// The degree n.
  n : Int
}

///|
/// Create a binary extension field GF(2^n) from an irreducible polynomial.
///
/// # Parameters
/// - `mod_poly`: the irreducible polynomial as a bit vector. Bit `i` is the
///   coefficient of x^i. Must include the leading term (bit `n` must be set).
/// - `n`: the degree of the field.
pub fn binary_field(mod_poly : Int64, n : Int) -> BinaryField {
  { mod_poly, n }
}

///|
/// Create GF(2^8) with the AES irreducible polynomial x^8 + x^4 + x^3 + x + 1.
pub fn aes_field() -> BinaryField {
  // x^8 + x^4 + x^3 + x + 1 = 0b100011011 = 0x11B = 283
  binary_field(0x11BL, 8)
}

///|
/// Add two elements in GF(2^n): XOR.
pub fn bf_add(_f : BinaryField, a : Int64, b : Int64) -> Int64 {
  a ^ b
}

///|
/// Subtract two elements in GF(2^n): same as addition (XOR).
pub fn bf_sub(f : BinaryField, a : Int64, b : Int64) -> Int64 {
  bf_add(f, a, b)
}

///|
/// Multiply two elements in GF(2^n) using shift-and-reduce.
///
/// Performs carry-less multiplication followed by modular reduction by the
/// irreducible polynomial.
pub fn bf_mul(f : BinaryField, a : Int64, b : Int64) -> Int64 {
  let mut result = 0L
  let mut x = a
  let mut y = b
  let mask = (1L << f.n) - 1L
  let mut i = 0
  while i < f.n && y != 0L {
    if (y & 1L) != 0L {
      result = result ^ x
    }
    x = x << 1
    if (x & (1L << f.n)) != 0L {
      x = x ^ f.mod_poly
    }
    x = x & mask
    y = y >> 1
    i = i + 1
  }
  result
}

///|
/// Compute the multiplicative inverse of `a` in GF(2^n).
///
/// Uses exponentiation: `a^{2^n - 2}` (Fermat's little theorem for GF(2^n)).
///
/// Returns 0 if `a == 0`.
pub fn bf_inv(f : BinaryField, a : Int64) -> Int64 {
  if a == 0L {
    return 0L
  }
  // a^{2^n - 2} = a^{2^n - 2}
  let exp = (1L << f.n) - 2L
  bf_pow(f, a, exp)
}

///|
/// Exponentiate in GF(2^n): `base^exp`.
pub fn bf_pow(f : BinaryField, base : Int64, exp : Int64) -> Int64 {
  let mut result = 1L
  let mut b = base
  let mut e = exp
  while e > 0L {
    if (e & 1L) != 0L {
      result = bf_mul(f, result, b)
    }
    b = bf_mul(f, b, b)
    e = e >> 1
  }
  result
}

///|
/// Divide `a` by `b` in GF(2^n): `a * b^{-1}`.
pub fn bf_div(f : BinaryField, a : Int64, b : Int64) -> Int64 {
  if b == 0L {
    return 0L
  }
  bf_mul(f, a, bf_inv(f, b))
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

///|
/// Modular multiplication: (a * b) mod m, avoiding overflow.
fn mod_mul(a : Int64, b : Int64, m : Int64) -> Int64 {
  let mut result = 0L
  let mut x = a % m
  let mut y = b % m
  if x < 0L {
    x = x + m
  }
  if y < 0L {
    y = y + m
  }
  while y > 0L {
    if (y & 1L) != 0L {
      result = (result + x) % m
    }
    x = x * 2L % m
    y = y >> 1
  }
  result
}

///|
/// Modular exponentiation: base^exp mod m.
fn pow_mod(base : Int64, exp : Int64, m : Int64) -> Int64 {
  let mut result = 1L
  let mut b = base % m
  let mut e = exp
  if b < 0L {
    b = b + m
  }
  while e > 0L {
    if (e & 1L) != 0L {
      result = mod_mul(result, b, m)
    }
    b = mod_mul(b, b, m)
    e = e >> 1
  }
  result
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "gf: prime field addition" {
  let f = prime_field(7L)
  // (3 + 5) mod 7 = 1
  assert_eq(pf_add(f, 3L, 5L), 1L)
  // (6 + 6) mod 7 = 5
  assert_eq(pf_add(f, 6L, 6L), 5L)
  // (0 + 3) mod 7 = 3
  assert_eq(pf_add(f, 0L, 3L), 3L)
}

///|
test "gf: prime field subtraction" {
  let f = prime_field(7L)
  // (3 - 5) mod 7 = 5
  assert_eq(pf_sub(f, 3L, 5L), 5L)
  // (0 - 1) mod 7 = 6
  assert_eq(pf_sub(f, 0L, 1L), 6L)
}

///|
test "gf: prime field multiplication" {
  let f = prime_field(7L)
  // (3 * 4) mod 7 = 12 mod 7 = 5
  assert_eq(pf_mul(f, 3L, 4L), 5L)
  // (6 * 6) mod 7 = 36 mod 7 = 1
  assert_eq(pf_mul(f, 6L, 6L), 1L)
}

///|
test "gf: prime field inverse" {
  let f = prime_field(7L)
  // 3^{-1} mod 7 = 5 (since 3*5 = 15 = 2*7+1)
  assert_eq(pf_inv(f, 3L), 5L)
  // 1^{-1} mod 7 = 1
  assert_eq(pf_inv(f, 1L), 1L)
  // 6^{-1} mod 7 = 6 (since 6*6 = 36 = 5*7+1)
  assert_eq(pf_inv(f, 6L), 6L)
  // 0^{-1} = 0 (no inverse)
  assert_eq(pf_inv(f, 0L), 0L)
}

///|
test "gf: prime field division" {
  let f = prime_field(7L)
  // 6 / 3 = 6 * 5 = 30 mod 7 = 2
  assert_eq(pf_div(f, 6L, 3L), 2L)
  // 1 / 1 = 1
  assert_eq(pf_div(f, 1L, 1L), 1L)
}

///|
test "gf: prime field exponentiation" {
  let f = prime_field(7L)
  // 2^3 mod 7 = 8 mod 7 = 1
  assert_eq(pf_pow(f, 2L, 3L), 1L)
  // 3^5 mod 7 = 243 mod 7 = 5
  assert_eq(pf_pow(f, 3L, 5L), 5L)
}

///|
test "gf: quadratic residue" {
  let f = prime_field(7L)
  // QRs mod 7: {1, 2, 4} (1^2=1, 2^2=4, 3^2=2, 4^2=2, 5^2=4, 6^2=1)
  assert_true(pf_is_quadratic_residue(f, 1L))
  assert_true(pf_is_quadratic_residue(f, 2L))
  assert_true(pf_is_quadratic_residue(f, 4L))
  assert_false(pf_is_quadratic_residue(f, 3L))
  assert_false(pf_is_quadratic_residue(f, 5L))
  assert_false(pf_is_quadratic_residue(f, 6L))
}

///|
test "gf: large prime field" {
  // Use a large prime.
  let f = prime_field(1000000007L)
  // Test modular multiplication doesn't overflow.
  let a = 999999999L
  let b = 999999999L
  let product = pf_mul(f, a, b)
  let inv = pf_inv(f, a)
  // a * a^{-1} = 1
  assert_eq(pf_mul(f, a, inv), 1L)
  // Verify product is in range.
  assert_true(product >= 0L && product < 1000000007L)
}

// --- GF(2^n) tests ---

///|
test "gf: binary field addition (XOR)" {
  let f = aes_field()
  assert_eq(bf_add(f, 0x57L, 0x83L), 0xD4L) // 0x57 ^ 0x83 = 0xD4
}

///|
test "gf: binary field multiplication" {
  let f = aes_field()
  // 0x57 * 0x83 in GF(2^8) with AES polynomial = 0xC1
  assert_eq(bf_mul(f, 0x57L, 0x83L), 0xC1L)
  // 0x02 * 0x01 = 0x02
  assert_eq(bf_mul(f, 0x02L, 0x01L), 0x02L)
  // 0x03 * 0x03 = 0x05 (x+1)^2 = x^2+1 = 0b101 = 5
  assert_eq(bf_mul(f, 0x03L, 0x03L), 0x05L)
}

///|
test "gf: binary field identity" {
  let f = aes_field()
  // 1 * a = a
  assert_eq(bf_mul(f, 0x01L, 0xABL), 0xABL)
  // 0 * a = 0
  assert_eq(bf_mul(f, 0x00L, 0xABL), 0x00L)
}

///|
test "gf: binary field inverse" {
  let f = aes_field()
  // a * a^{-1} = 1
  let a = 0x57L
  let inv = bf_inv(f, a)
  assert_eq(bf_mul(f, a, inv), 0x01L)
  // 1^{-1} = 1
  assert_eq(bf_inv(f, 0x01L), 0x01L)
  // 0^{-1} = 0
  assert_eq(bf_inv(f, 0x00L), 0x00L)
}

///|
test "gf: binary field exponentiation" {
  let f = aes_field()
  // 0x02^8 = 0x01 in GF(2^8) (Fermat's little theorem)
  // Actually 0x02^255 = 1, but let's test a simpler case.
  // 0x03^2 = 0x05
  assert_eq(bf_pow(f, 0x03L, 2L), 0x05L)
  // 0x01^100 = 1
  assert_eq(bf_pow(f, 0x01L, 100L), 0x01L)
}

///|
test "gf: binary field division" {
  let f = aes_field()
  // a / b = a * b^{-1}
  let a = 0x57L
  let b = 0x83L
  let quotient = bf_div(f, a, b)
  // Verify: quotient * b = a
  assert_eq(bf_mul(f, quotient, b), a)
}

///|
test "gf: binary field Fermat's theorem" {
  let f = aes_field()
  // a^{2^n - 1} = 1 for any nonzero a in GF(2^n)
  // 2^8 - 1 = 255
  let a = 0x53L
  let result = bf_pow(f, a, 255L)
  assert_eq(result, 0x01L)
}

///|
test "gf: binary field GF(2^4)" {
  // GF(2^4) with irreducible polynomial x^4 + x + 1 = 0b10011 = 19
  let f = binary_field(0b10011L, 4)
  // 3 * 3 = x^2 + 2x + 1 → x^2 + 1 = 0b0101 = 5
  assert_eq(bf_mul(f, 0b0011L, 0b0011L), 0b0101L)
  // 3 * 5 = 15 → reduce: x^3+x^2+x+1 → need to reduce if >= 2^4
  // Actually 3*5 = (x+1)(x^2+1) = x^3+x^2+x+1 = 0b1111 = 15
  // 15 < 16 so no reduction needed.
  assert_eq(bf_mul(f, 0b0011L, 0b0101L), 0b1111L)
  // 3 * 7 = (x+1)(x^2+x+1) = x^3+x^2+x+x^2+x+1 = x^3+1 = 0b1001 = 9
  assert_eq(bf_mul(f, 0b0011L, 0b0111L), 0b1001L)
  // Inverse: 3 * 3^{-1} = 1
  let inv = bf_inv(f, 0b0011L)
  assert_eq(bf_mul(f, 0b0011L, inv), 0b0001L)
}
