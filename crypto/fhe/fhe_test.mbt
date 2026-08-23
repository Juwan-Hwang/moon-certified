///|
/// Comprehensive tests for FHE (Fully Homomorphic Encryption) — LWE scheme.

// ===========================================================================
// Key generation tests
// ===========================================================================

test "lwe_keygen: produces correct dimension" {
  let sk = lwe_keygen(42)
  assert_eq(sk.s.length(), 16) // LWE_N = 16
}

///|
test "lwe_keygen: small secret coefficients" {
  let sk = lwe_keygen(42)
  for v in sk.s {
    assert_true(v >= -3 && v <= 3) // LWE_NOISE_BOUND = 3
  }
}

///|
test "lwe_keygen: deterministic with same seed" {
  let sk1 = lwe_keygen(123)
  let sk2 = lwe_keygen(123)
  assert_eq(sk1.s, sk2.s)
}

///|
test "lwe_keygen: different seeds produce different keys" {
  let sk1 = lwe_keygen(1)
  let sk2 = lwe_keygen(2)
  assert_true(sk1.s != sk2.s)
}

// ===========================================================================
// Encrypt / Decrypt round-trip tests
// ===========================================================================

///|
test "lwe_encrypt_decrypt: zero message" {
  let sk = lwe_keygen(42)
  let ct = lwe_encrypt(sk, 0, 100)
  let result = lwe_decrypt(sk, ct)
  assert_eq(result, 0)
}

///|
test "lwe_encrypt_decrypt: positive message" {
  let sk = lwe_keygen(42)
  let ct = lwe_encrypt(sk, 5, 100)
  let result = lwe_decrypt(sk, ct)
  assert_eq(result, 5)
}

///|
test "lwe_encrypt_decrypt: negative message" {
  let sk = lwe_keygen(42)
  let ct = lwe_encrypt(sk, -3, 100)
  let result = lwe_decrypt(sk, ct)
  assert_eq(result, -3)
}

///|
test "lwe_encrypt_decrypt: large positive" {
  let sk = lwe_keygen(42)
  let ct = lwe_encrypt(sk, 30, 100)
  let result = lwe_decrypt(sk, ct)
  assert_eq(result, 30)
}

///|
test "lwe_encrypt_decrypt: large negative" {
  let sk = lwe_keygen(42)
  let ct = lwe_encrypt(sk, -30, 100)
  let result = lwe_decrypt(sk, ct)
  assert_eq(result, -30)
}

///|
test "lwe_encrypt_decrypt: multiple values" {
  let sk = lwe_keygen(999)
  for m in [0, 1, -1, 10, -10, 25, -25, 30, -30] {
    let ct = lwe_encrypt(sk, m, 200)
    assert_eq(lwe_decrypt(sk, ct), m)
  }
}

///|
test "lwe_encrypt: ciphertext dimension matches key" {
  let sk = lwe_keygen(42)
  let ct = lwe_encrypt(sk, 7, 100)
  assert_eq(ct.a.length(), 16)
}

// ===========================================================================
// Homomorphic addition tests
// ===========================================================================

///|
test "lwe_add: homomorphic addition of plaintexts" {
  let sk = lwe_keygen(42)
  let ct1 = lwe_encrypt(sk, 10, 100)
  let ct2 = lwe_encrypt(sk, 20, 200)
  let ct_sum = lwe_add(ct1, ct2)
  let result = lwe_decrypt(sk, ct_sum)
  assert_eq(result, 30)
}

///|
test "lwe_add: addition with zero" {
  let sk = lwe_keygen(42)
  let ct1 = lwe_encrypt(sk, 15, 100)
  let ct2 = lwe_encrypt(sk, 0, 200)
  let ct_sum = lwe_add(ct1, ct2)
  assert_eq(lwe_decrypt(sk, ct_sum), 15)
}

///|
test "lwe_add: addition of negatives" {
  let sk = lwe_keygen(42)
  let ct1 = lwe_encrypt(sk, -5, 100)
  let ct2 = lwe_encrypt(sk, -10, 200)
  let ct_sum = lwe_add(ct1, ct2)
  assert_eq(lwe_decrypt(sk, ct_sum), -15)
}

///|
test "lwe_add: chain of additions" {
  let sk = lwe_keygen(42)
  let ct = lwe_encrypt(sk, 1, 100)
  let mut acc = ct
  for i = 0; i < 5; i = i + 1 {
    acc = lwe_add(acc, lwe_encrypt(sk, 2, 300 + i))
  }
  // 1 + 2*5 = 11
  assert_eq(lwe_decrypt(sk, acc), 11)
}

// ===========================================================================
// Homomorphic subtraction tests
// ===========================================================================

///|
test "lwe_sub: homomorphic subtraction" {
  let sk = lwe_keygen(42)
  let ct1 = lwe_encrypt(sk, 30, 100)
  let ct2 = lwe_encrypt(sk, 12, 200)
  let ct_diff = lwe_sub(ct1, ct2)
  assert_eq(lwe_decrypt(sk, ct_diff), 18)
}

///|
test "lwe_sub: subtraction yielding negative" {
  let sk = lwe_keygen(42)
  let ct1 = lwe_encrypt(sk, 5, 100)
  let ct2 = lwe_encrypt(sk, 15, 200)
  let ct_diff = lwe_sub(ct1, ct2)
  assert_eq(lwe_decrypt(sk, ct_diff), -10)
}

///|
test "lwe_sub: self subtraction yields zero" {
  let sk = lwe_keygen(42)
  let ct1 = lwe_encrypt(sk, 42, 100)
  let ct2 = lwe_encrypt(sk, 42, 100)
  let ct_diff = lwe_sub(ct1, ct2)
  assert_eq(lwe_decrypt(sk, ct_diff), 0)
}

// ===========================================================================
// Homomorphic scalar multiplication tests
// ===========================================================================

///|
test "lwe_mul_scalar: multiply by positive" {
  let sk = lwe_keygen(42)
  let ct = lwe_encrypt(sk, 7, 100)
  let ct_scaled = lwe_mul_scalar(ct, 3)
  assert_eq(lwe_decrypt(sk, ct_scaled), 21)
}

///|
test "lwe_mul_scalar: multiply by zero" {
  let sk = lwe_keygen(42)
  let ct = lwe_encrypt(sk, 7, 100)
  let ct_scaled = lwe_mul_scalar(ct, 0)
  assert_eq(lwe_decrypt(sk, ct_scaled), 0)
}

///|
test "lwe_mul_scalar: multiply by negative" {
  let sk = lwe_keygen(42)
  let ct = lwe_encrypt(sk, 7, 100)
  let ct_scaled = lwe_mul_scalar(ct, -2)
  assert_eq(lwe_decrypt(sk, ct_scaled), -14)
}

///|
test "lwe_mul_scalar: multiply by one" {
  let sk = lwe_keygen(42)
  let ct = lwe_encrypt(sk, 7, 100)
  let ct_scaled = lwe_mul_scalar(ct, 1)
  assert_eq(lwe_decrypt(sk, ct_scaled), 7)
}

// ===========================================================================
// Homomorphic negation tests
// ===========================================================================

///|
test "lwe_negate: negate positive" {
  let sk = lwe_keygen(42)
  let ct = lwe_encrypt(sk, 15, 100)
  let ct_neg = lwe_negate(ct)
  assert_eq(lwe_decrypt(sk, ct_neg), -15)
}

///|
test "lwe_negate: negate negative" {
  let sk = lwe_keygen(42)
  let ct = lwe_encrypt(sk, -8, 100)
  let ct_neg = lwe_negate(ct)
  assert_eq(lwe_decrypt(sk, ct_neg), 8)
}

///|
test "lwe_negate: negate zero" {
  let sk = lwe_keygen(42)
  let ct = lwe_encrypt(sk, 0, 100)
  let ct_neg = lwe_negate(ct)
  assert_eq(lwe_decrypt(sk, ct_neg), 0)
}

///|
test "lwe_negate: double negation" {
  let sk = lwe_keygen(42)
  let ct = lwe_encrypt(sk, 5, 100)
  let ct_neg2 = lwe_negate(lwe_negate(ct))
  assert_eq(lwe_decrypt(sk, ct_neg2), 5)
}

// ===========================================================================
// Combined homomorphic operations tests
// ===========================================================================

///|
test "lwe_combined: add then subtract" {
  let sk = lwe_keygen(42)
  let ct1 = lwe_encrypt(sk, 20, 100)
  let ct2 = lwe_encrypt(sk, 5, 200)
  let ct3 = lwe_encrypt(sk, 3, 300)
  // (20 + 5) - 3 = 22
  let result = lwe_sub(lwe_add(ct1, ct2), ct3)
  assert_eq(lwe_decrypt(sk, result), 22)
}

///|
test "lwe_combined: scale then add" {
  let sk = lwe_keygen(42)
  let ct1 = lwe_encrypt(sk, 3, 100)
  let ct2 = lwe_encrypt(sk, 4, 200)
  // 3*2 + 4*3 = 18
  let result = lwe_add(lwe_mul_scalar(ct1, 2), lwe_mul_scalar(ct2, 3))
  assert_eq(lwe_decrypt(sk, result), 18)
}

///|
test "lwe_combined: negate then add" {
  let sk = lwe_keygen(42)
  let ct1 = lwe_encrypt(sk, 10, 100)
  let ct2 = lwe_encrypt(sk, 3, 200)
  // 10 + (-3) = 7
  let result = lwe_add(ct1, lwe_negate(ct2))
  assert_eq(lwe_decrypt(sk, result), 7)
}
