///|
/// Comprehensive tests for DSA (Digital Signature Algorithm).

// ===========================================================================
// Key generation tests
// ===========================================================================

test "dsa_keygen: basic key generation" {
  let (sk, pk) = dsa_keygen(123)
  assert_true(sk.x >= 1 && sk.x < 5003)
  assert_true(pk.y >= 1 && pk.y < 10007)
  let expected_y = mod_pow_test(4, sk.x, 10007)
  assert_eq(pk.y, expected_y)
}

///|
test "dsa_keygen: different secrets produce different keys" {
  let (sk1, pk1) = dsa_keygen(100)
  let (sk2, pk2) = dsa_keygen(200)
  assert_true(sk1.x != sk2.x)
  assert_true(pk1.y != pk2.y)
}

///|
test "dsa_keygen: secret larger than q is reduced" {
  let (sk, _) = dsa_keygen(5005) // 5005 % 5003 = 2
  assert_eq(sk.x, 2)
}

///|
test "dsa_keygen: deterministic" {
  let (sk1, pk1) = dsa_keygen(42)
  let (sk2, pk2) = dsa_keygen(42)
  assert_eq(sk1.x, sk2.x)
  assert_eq(pk1.y, pk2.y)
}

// ===========================================================================
// Sign and verify round-trip tests
// ===========================================================================

///|
test "dsa_sign_verify: basic round-trip" {
  let (sk, pk) = dsa_keygen(123)
  let msg = Bytes::from_array([0xAB, 0xCD])
  let sig = dsa_sign(sk, msg, 456)
  assert_eq(dsa_verify(pk, msg, sig), true)
}

///|
test "dsa_sign_verify: different messages" {
  let (sk, pk) = dsa_keygen(123)
  let msg1 = Bytes::from_array([0xAB, 0xCD])
  let msg2 = Bytes::from_array([0x04, 0x03])
  let sig1 = dsa_sign(sk, msg1, 456)
  assert_eq(dsa_verify(pk, msg1, sig1), true)
  assert_eq(dsa_verify(pk, msg2, sig1), false)
}

///|
test "dsa_sign_verify: empty message" {
  let (sk, pk) = dsa_keygen(77)
  let msg = Bytes::from_array([])
  let sig = dsa_sign(sk, msg, 55)
  assert_eq(dsa_verify(pk, msg, sig), true)
}

///|
test "dsa_sign_verify: single byte message" {
  let (sk, pk) = dsa_keygen(88)
  let msg = Bytes::from_array([0x42])
  let sig = dsa_sign(sk, msg, 66)
  assert_eq(dsa_verify(pk, msg, sig), true)
}

///|
test "dsa_sign_verify: signature components in range" {
  let (sk, _) = dsa_keygen(123)
  let msg = Bytes::from_array([0xAA, 0xBB])
  let sig = dsa_sign(sk, msg, 456)
  assert_true(sig.r >= 1 && sig.r < 5003)
  assert_true(sig.s >= 1 && sig.s < 5003)
}

///|
test "dsa_sign_verify: wrong key fails verification" {
  let (sk1, _) = dsa_keygen(111)
  let (_, pk2) = dsa_keygen(222)
  let msg = Bytes::from_array([0x01, 0x02])
  let sig = dsa_sign(sk1, msg, 333)
  assert_eq(dsa_verify(pk2, msg, sig), false)
}

///|
test "dsa_sign_verify: tampered signature fails" {
  let (sk, pk) = dsa_keygen(123)
  let msg = Bytes::from_array([0x01, 0x02])
  let sig = dsa_sign(sk, msg, 456)
  let tampered = DsaSignature::new(sig.r, (sig.s + 1) % 5003)
  assert_eq(dsa_verify(pk, msg, tampered), false)
}

///|
test "dsa_sign_verify: different nonces produce different signatures" {
  let (sk, pk) = dsa_keygen(123)
  let msg = Bytes::from_array([0xAA, 0xBB])
  let sig1 = dsa_sign(sk, msg, 456)
  let sig2 = dsa_sign(sk, msg, 789)
  assert_true(sig1.r != sig2.r || sig1.s != sig2.s)
  assert_eq(dsa_verify(pk, msg, sig1), true)
  assert_eq(dsa_verify(pk, msg, sig2), true)
}

///|
test "dsa_sign_verify: r out of range fails" {
  let (sk, pk) = dsa_keygen(123)
  let msg = Bytes::from_array([0x01])
  let sig = dsa_sign(sk, msg, 456)
  assert_eq(dsa_verify(pk, msg, DsaSignature::new(0, sig.s)), false)
  assert_eq(dsa_verify(pk, msg, DsaSignature::new(5003, sig.s)), false)
}

///|
test "dsa_sign_verify: s out of range fails" {
  let (sk, pk) = dsa_keygen(123)
  let msg = Bytes::from_array([0x01])
  let sig = dsa_sign(sk, msg, 456)
  assert_eq(dsa_verify(pk, msg, DsaSignature::new(sig.r, 0)), false)
  assert_eq(dsa_verify(pk, msg, DsaSignature::new(sig.r, 5003)), false)
}

///|
test "dsa_sign_verify: multiple key pairs and messages" {
  for secret in [10, 50, 100, 500, 1000, 2000, 4000] {
    let (sk, pk) = dsa_keygen(secret)
    let msg_arr : Array[Byte] = [(secret & 0xFF).to_byte(), 0x77]
    let msg = Bytes::from_array(msg_arr)
    let k = if secret % 2 == 0 { secret + 1 } else { secret + 2 }
    let sig = dsa_sign(sk, msg, k)
    assert_eq(dsa_verify(pk, msg, sig), true)
  }
}

// ===========================================================================
// ECDSA variant tests
// ===========================================================================

///|
test "ecdsa_variant_sign_verify: round-trip" {
  let private_key = 123
  let public_key = mod_pow_test(4, private_key, 10007)
  let msg = Bytes::from_array([0x12, 0x34])
  let (r, s) = ecdsa_variant_sign(private_key, msg, 456)
  assert_eq(ecdsa_variant_verify(public_key, msg, r, s), true)
}

///|
test "ecdsa_variant_sign_verify: wrong message fails" {
  let private_key = 99
  let public_key = mod_pow_test(4, private_key, 10007)
  let msg1 = Bytes::from_array([0xAA, 0xBB])
  let msg2 = Bytes::from_array([0x00, 0x11])
  let (r, s) = ecdsa_variant_sign(private_key, msg1, 77)
  assert_eq(ecdsa_variant_verify(public_key, msg1, r, s), true)
  assert_eq(ecdsa_variant_verify(public_key, msg2, r, s), false)
}

///|
test "ecdsa_variant_sign_verify: wrong public key fails" {
  let private_key = 42
  let public_key = mod_pow_test(4, private_key, 10007)
  let wrong_pk = mod_pow_test(4, 99, 10007)
  let msg = Bytes::from_array([0x01, 0x02])
  let (r, s) = ecdsa_variant_sign(private_key, msg, 55)
  assert_eq(ecdsa_variant_verify(public_key, msg, r, s), true)
  assert_eq(ecdsa_variant_verify(wrong_pk, msg, r, s), false)
}

///|
test "ecdsa_variant_sign_verify: r and s in range" {
  let private_key = 77
  let msg = Bytes::from_array([0xFF, 0xEE])
  let (r, s) = ecdsa_variant_sign(private_key, msg, 88)
  assert_true(r >= 1 && r < 5003)
  assert_true(s >= 1 && s < 5003)
}

///|
test "ecdsa_variant_sign_verify: r out of range fails" {
  let private_key = 42
  let public_key = mod_pow_test(4, private_key, 10007)
  let msg = Bytes::from_array([0x01])
  let (_, s) = ecdsa_variant_sign(private_key, msg, 55)
  assert_eq(ecdsa_variant_verify(public_key, msg, 0, s), false)
  assert_eq(ecdsa_variant_verify(public_key, msg, 5003, s), false)
}

// Helper: mod_pow for test verification

///|
fn mod_pow_test(base : Int, exp : Int, m : Int) -> Int {
  if m == 1 {
    return 0
  }
  let mut result = 1
  let mut b = base % m
  if b < 0 {
    b = b + m
  }
  let mut e = exp
  while e > 0 {
    if (e & 1) == 1 {
      result = result * b % m
    }
    e = e >> 1
    b = b * b % m
  }
  result
}
