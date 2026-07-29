/// X25519 test suite.
///
/// Tests include:
/// 1. RFC 7748 §5.2 scalar multiplication test vectors
/// 2. RFC 7748 §6.1 Diffie-Hellman key exchange test vectors
/// 3. Property-based round-trip tests

// ---------------------------------------------------------------------------
// Helper: hex string → Bytes
// ---------------------------------------------------------------------------

fn hex2bytes(s : String) -> Bytes {
  @hex.decode(s).unwrap()
}

// ---------------------------------------------------------------------------
// RFC 7748 §5.2 Test Vectors (scalar multiplication)
// ---------------------------------------------------------------------------

test "rfc7748 §5.2 vector 1" {
  let scalar = hex2bytes(
    "a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4",
  )
  let u = hex2bytes(
    "e6db6867583030db3594c1a424b15f7c726624ec26b3353b10a903a6d0ab1c4c",
  )
  let expected = hex2bytes(
    "c3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552",
  )
  let result = x25519(scalar, u)
  assert_eq(@hex.encode(result), @hex.encode(expected))
}

test "rfc7748 §5.2 vector 2" {
  let scalar = hex2bytes(
    "4b66e9d4d1b4673c5ad22691957d6af5c11b6421e0ea01d42ca4169e7918ba0d",
  )
  let u = hex2bytes(
    "e5210f12786811d3f4b7959d0538ae2c31dbe7106fc03c3efc4cd549c715a493",
  )
  let expected = hex2bytes(
    "95cbde9476e8907d7aade45cb4b873f88b595a68799fa152e6f8f7647aac7957",
  )
  let result = x25519(scalar, u)
  assert_eq(@hex.encode(result), @hex.encode(expected))
}

// ---------------------------------------------------------------------------
// RFC 7748 §6.1 Diffie-Hellman Key Exchange Test Vectors
// ---------------------------------------------------------------------------

test "rfc7748 §6.1 DH key exchange" {
  let alice_private = hex2bytes(
    "77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a",
  )
  let alice_public = hex2bytes(
    "8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a",
  )
  let bob_private = hex2bytes(
    "5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb",
  )
  let bob_public = hex2bytes(
    "de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f",
  )
  let expected_shared = hex2bytes(
    "4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742",
  )

  // Alice's public key derivation
  let alice_pk = derive_public_key(alice_private)
  assert_eq(@hex.encode(alice_pk), @hex.encode(alice_public))

  // Bob's public key derivation
  let bob_pk = derive_public_key(bob_private)
  assert_eq(@hex.encode(bob_pk), @hex.encode(bob_public))

  // Shared secret from Alice's side
  let alice_shared = shared_secret(alice_private, bob_public)
  assert_eq(@hex.encode(alice_shared), @hex.encode(expected_shared))

  // Shared secret from Bob's side
  let bob_shared = shared_secret(bob_private, alice_public)
  assert_eq(@hex.encode(bob_shared), @hex.encode(expected_shared))

  // Both sides compute the same shared secret
  assert_eq(@hex.encode(alice_shared), @hex.encode(bob_shared))
}

// ---------------------------------------------------------------------------
// Property tests
// ---------------------------------------------------------------------------

test "x25519: base point is u=9" {
  let bp = base_point()
  assert_eq(bp.length(), 32)
  assert_eq(bp[0], b'\x09')
  for i = 1; i < 32; i = i + 1 {
    assert_eq(bp[i], b'\x00')
  }
}

test "x25519: public key is 32 bytes" {
  let sk = Bytes::make(32, b'\x01')
  let pk = derive_public_key(sk)
  assert_eq(pk.length(), 32)
}

test "x25519: shared secret symmetry" {
  let alice_sk = hex2bytes(
    "77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a",
  )
  let bob_sk = hex2bytes(
    "5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb",
  )
  let alice_pk = derive_public_key(alice_sk)
  let bob_pk = derive_public_key(bob_sk)
  let s1 = shared_secret(alice_sk, bob_pk)
  let s2 = shared_secret(bob_sk, alice_pk)
  assert_eq(@hex.encode(s1), @hex.encode(s2))
}

test "x25519: different keys produce different shared secrets" {
  let sk1 = Bytes::make(32, b'\x01')
  let sk2 = Bytes::make(32, b'\x02')
  let pk1 = derive_public_key(sk1)
  let pk2 = derive_public_key(sk2)
  let s1 = shared_secret(sk1, pk2)
  let s2 = shared_secret(sk2, pk1)
  // Cross-shared secrets should match
  assert_eq(@hex.encode(s1), @hex.encode(s2))
  // But shared secret with self differs from cross
  let s_self = shared_secret(sk1, pk1)
  assert_true(@hex.encode(s_self) != @hex.encode(s1))
}

test "x25519: clamping is idempotent" {
  let sk = hex2bytes(
    "a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4",
  )
  let result1 = x25519(sk, base_point())
  // Applying x25519 on an already-clamped scalar gives the same result
  let clamped_sk = hex2bytes(
    "a446e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449a44",
  )
  let result2 = x25519(clamped_sk, base_point())
  assert_eq(@hex.encode(result1), @hex.encode(result2))
}
