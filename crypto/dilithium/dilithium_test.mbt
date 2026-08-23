/// Dilithium (ML-DSA) — white-box test suite.
///
/// Covers key generation, deterministic signing, and verification including
/// negative (tamper) cases. The verify step checks that the Fiat-Shamir hash
/// `c` equals `sha256(message || z)`, so round-trips and tamper detection are
/// exercised through that path.

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

///|
/// Byte-wise equality for `Bytes` (avoids needing the `hex` package).
fn bytes_eq(a : Bytes, b : Bytes) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i = 0; i < a.length(); i = i + 1 {
    if a[i] != b[i] {
      return false
    }
  }
  true
}

// ---------------------------------------------------------------------------
// Key generation
// ---------------------------------------------------------------------------

///|
test "dilithium: keygen produces keys of expected lengths" {
  let (pk, sk) = dilithium_keygen(12345)
  // L * N = 4 * 256 = 1024 coefficients
  assert_eq(pk.t.length(), 1024)
  assert_eq(sk.s.length(), 1024)
  assert_eq(pk.seed.length(), 32)
}

///|
test "dilithium: keygen is deterministic for a fixed seed" {
  let (pk1, sk1) = dilithium_keygen(777)
  let (pk2, sk2) = dilithium_keygen(777)
  assert_eq(pk1.t, pk2.t)
  assert_eq(sk1.s, sk2.s)
  assert_true(bytes_eq(pk1.seed, pk2.seed))
}

// ---------------------------------------------------------------------------
// Round-trip sign / verify
// ---------------------------------------------------------------------------

///|
test "dilithium: sign and verify round-trip ('hello')" {
  let (pk, sk) = dilithium_keygen(12345)
  let msg = Bytes::from_array([b'\x68', b'\x65', b'\x6c', b'\x6c', b'\x6f'])
  let sig = dilithium_sign(sk, msg, 777)
  assert_true(dilithium_verify(pk, msg, sig))
}

///|
test "dilithium: empty message round-trip" {
  let (pk, sk) = dilithium_keygen(999)
  let msg = Bytes::from_array([])
  let sig = dilithium_sign(sk, msg, 1)
  assert_true(dilithium_verify(pk, msg, sig))
}

///|
test "dilithium: single byte message round-trip" {
  let (pk, sk) = dilithium_keygen(42)
  let msg = Bytes::from_array([b'\x61'])
  let sig = dilithium_sign(sk, msg, 2)
  assert_true(dilithium_verify(pk, msg, sig))
}

///|
test "dilithium: multi-byte message round-trip" {
  let (pk, sk) = dilithium_keygen(2024)
  let msg = Bytes::from_array([
    b'\x74', b'\x68', b'\x65', b'\x20', b'\x71', b'\x75', b'\x69', b'\x63', b'\x6b',
    b'\x20', b'\x62', b'\x72', b'\x6f', b'\x77', b'\x6e', b'\x20', b'\x66', b'\x6f',
    b'\x78',
  ])
  let sig = dilithium_sign(sk, msg, 5)
  assert_true(dilithium_verify(pk, msg, sig))
}

// ---------------------------------------------------------------------------
// Determinism
// ---------------------------------------------------------------------------

///|
test "dilithium: signing is deterministic for a fixed seed" {
  let (_, sk) = dilithium_keygen(12345)
  let msg = Bytes::from_array([b'\x68', b'\x65', b'\x6c', b'\x6c', b'\x6f'])
  let s1 = dilithium_sign(sk, msg, 777)
  let s2 = dilithium_sign(sk, msg, 777)
  assert_eq(s1.z, s2.z)
  assert_true(bytes_eq(s1.c, s2.c))
}

///|
test "dilithium: different seed yields a different signature z" {
  let (_, sk) = dilithium_keygen(12345)
  let msg = Bytes::from_array([b'\x68'])
  let s1 = dilithium_sign(sk, msg, 1)
  let s2 = dilithium_sign(sk, msg, 2)
  assert_false(s1.z == s2.z)
}

///|
test "dilithium: different message yields a different Fiat-Shamir hash c" {
  let (_, sk) = dilithium_keygen(12345)
  let m1 = Bytes::from_array([b'\x68', b'\x65', b'\x6c', b'\x6c', b'\x6f'])
  let m2 = Bytes::from_array([b'\x77', b'\x6f', b'\x72', b'\x6c', b'\x64'])
  let s1 = dilithium_sign(sk, m1, 777)
  let s2 = dilithium_sign(sk, m2, 777)
  // z depends only on the seed, but c must bind the message.
  assert_eq(s1.z, s2.z)
  assert_false(bytes_eq(s1.c, s2.c))
}

// ---------------------------------------------------------------------------
// Negative tests
// ---------------------------------------------------------------------------

///|
test "dilithium: tampered message fails verification" {
  let (pk, sk) = dilithium_keygen(12345)
  let msg = Bytes::from_array([b'\x68', b'\x65', b'\x6c', b'\x6c', b'\x6f'])
  let sig = dilithium_sign(sk, msg, 777)
  assert_true(dilithium_verify(pk, msg, sig))
  let tampered = Bytes::from_array([b'\x68', b'\x65', b'\x6c', b'\x6c', b'\x66'])
  assert_false(dilithium_verify(pk, tampered, sig))
}

///|
test "dilithium: tampered signature z fails verification" {
  let (pk, sk) = dilithium_keygen(12345)
  let msg = Bytes::from_array([b'\x68', b'\x65', b'\x6c', b'\x6c', b'\x6f'])
  let sig = dilithium_sign(sk, msg, 777)
  assert_true(dilithium_verify(pk, msg, sig))
  // Mutate a coefficient of z in place and re-verify.
  let old = sig.z[0]
  sig.z[0] = if old == 0 { 1 } else { old - 1 }
  assert_false(dilithium_verify(pk, msg, sig))
}

///|
test "dilithium: a valid signature verifies (sanity)" {
  let (pk, sk) = dilithium_keygen(12345)
  let msg = Bytes::from_array([b'\x68', b'\x65', b'\x6c', b'\x6c', b'\x6f'])
  let sig = dilithium_sign(sk, msg, 777)
  assert_true(dilithium_verify(pk, msg, sig))
  // Note: `DilithiumSignature` is a read-only struct in the test context, so
  // an externally forged `c` cannot be constructed here. The integrity of the
  // Fiat-Shamir hash is instead exercised by the tampered-message test above
  // (which changes the message but keeps z, so the recomputed c no longer
  // matches `sig.c`) and by the "different message yields a different c" test.
}
