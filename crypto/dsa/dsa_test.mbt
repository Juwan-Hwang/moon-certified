///|
/// Comprehensive tests for DSA (Digital Signature Algorithm).

// ===========================================================================
// Key generation tests
// ===========================================================================

///|
test "dsa_keygen: basic key generation" {
  let (sk, pk) = dsa_keygen(@bigint.from_int_value(123))
  let one = @bigint.one()
  assert_true(@bigint.compare(sk.x, one) >= 0)
  assert_true(@bigint.compare(sk.x, dsa_q) < 0)
  // y = g^x mod p
  let expected_y = match @bigint.mod_pow(dsa_g, sk.x, dsa_p) {
    Some(v) => v
    None => @bigint.zero()
  }
  assert_true(@bigint.equal(pk.y, expected_y))
}

///|
test "dsa_keygen: different secrets produce different keys" {
  let (sk1, pk1) = dsa_keygen(@bigint.from_int_value(100))
  let (sk2, pk2) = dsa_keygen(@bigint.from_int_value(200))
  assert_false(@bigint.equal(sk1.x, sk2.x))
  assert_false(@bigint.equal(pk1.y, pk2.y))
}

///|
test "dsa_keygen: deterministic" {
  let (sk1, pk1) = dsa_keygen(@bigint.from_int_value(42))
  let (sk2, pk2) = dsa_keygen(@bigint.from_int_value(42))
  assert_true(@bigint.equal(sk1.x, sk2.x))
  assert_true(@bigint.equal(pk1.y, pk2.y))
}

// ===========================================================================
// Sign and verify round-trip tests
// ===========================================================================

///|
test "dsa_sign_verify: basic round-trip" {
  let (sk, pk) = dsa_keygen(@bigint.from_int_value(123))
  let msg = b"Hello, DSA!"
  let sig = dsa_sign(sk, msg)
  assert_true(dsa_verify(pk, msg, sig))
}

///|
test "dsa_sign_verify: different messages" {
  let (sk, pk) = dsa_keygen(@bigint.from_int_value(123))
  let msg1 = b"message one"
  let msg2 = b"message two"
  let sig = dsa_sign(sk, msg1)
  assert_true(dsa_verify(pk, msg1, sig))
  assert_false(dsa_verify(pk, msg2, sig))
}

///|
test "dsa_sign_verify: empty message" {
  let (sk, pk) = dsa_keygen(@bigint.from_int_value(77))
  let msg = b""
  let sig = dsa_sign(sk, msg)
  assert_true(dsa_verify(pk, msg, sig))
}

///|
test "dsa_sign_verify: wrong key fails verification" {
  let (sk1, _) = dsa_keygen(@bigint.from_int_value(111))
  let (_, pk2) = dsa_keygen(@bigint.from_int_value(222))
  let msg = b"test message"
  let sig = dsa_sign(sk1, msg)
  assert_false(dsa_verify(pk2, msg, sig))
}

///|
test "dsa_sign_verify: tampered signature fails" {
  let (sk, pk) = dsa_keygen(@bigint.from_int_value(123))
  let msg = b"message"
  let sig = dsa_sign(sk, msg)
  let tampered = DsaSignature::new(sig.r, @bigint.add(sig.s, @bigint.one()))
  assert_false(dsa_verify(pk, msg, tampered))
}

///|
test "dsa_sign_verify: deterministic signatures (RFC 6979)" {
  let (sk, _) = dsa_keygen(@bigint.from_int_value(123))
  let sig1 = dsa_sign(sk, b"message")
  let sig2 = dsa_sign(sk, b"message")
  assert_true(@bigint.equal(sig1.r, sig2.r))
  assert_true(@bigint.equal(sig1.s, sig2.s))
}

///|
test "dsa_sign_verify: r and s in range" {
  let (sk, _) = dsa_keygen(@bigint.from_int_value(123))
  let sig = dsa_sign(sk, b"test message")
  let one = @bigint.one()
  assert_true(@bigint.compare(sig.r, one) >= 0)
  assert_true(@bigint.compare(sig.r, dsa_q) < 0)
  assert_true(@bigint.compare(sig.s, one) >= 0)
  assert_true(@bigint.compare(sig.s, dsa_q) < 0)
}

///|
test "dsa_sign_verify: r out of range fails" {
  let (sk, pk) = dsa_keygen(@bigint.from_int_value(123))
  let msg = b"test"
  let sig = dsa_sign(sk, msg)
  assert_false(dsa_verify(pk, msg, DsaSignature::new(@bigint.zero(), sig.s)))
  assert_false(dsa_verify(pk, msg, DsaSignature::new(dsa_q, sig.s)))
}

///|
test "dsa_sign_verify: s out of range fails" {
  let (sk, pk) = dsa_keygen(@bigint.from_int_value(123))
  let msg = b"test"
  let sig = dsa_sign(sk, msg)
  assert_false(dsa_verify(pk, msg, DsaSignature::new(sig.r, @bigint.zero())))
  assert_false(dsa_verify(pk, msg, DsaSignature::new(sig.r, dsa_q)))
}

///|
test "dsa_sign_verify: multiple key pairs and messages" {
  for secret_int in [10, 50, 100, 500, 1000] {
    let (sk, pk) = dsa_keygen(@bigint.from_int_value(secret_int))
    let msg = b"test message for DSA"
    let sig = dsa_sign(sk, msg)
    assert_true(dsa_verify(pk, msg, sig))
  }
}
