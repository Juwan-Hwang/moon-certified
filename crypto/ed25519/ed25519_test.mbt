///|
/// Ed25519 test suite.
///
/// Tests are organised in two groups:
/// 1. RFC 8032 §7.1 known-answer test vectors — verify byte-exact
///    agreement with the reference implementation.
/// 2. Property-based round-trip tests — sign/verify, determinism,
///    negative cases, and edge cases.

// ---------------------------------------------------------------------------
// Helper: hex string → Bytes
// ---------------------------------------------------------------------------

fn hex2bytes(s : String) -> Bytes {
  @hex.decode(s).unwrap()
}

// ---------------------------------------------------------------------------
// RFC 8032 §7.1 Test Vectors
// ---------------------------------------------------------------------------

///|
test "rfc8032 vector 1: empty message" {
  let sk = hex2bytes(
    "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60",
  )
  let expected_pk = hex2bytes(
    "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a",
  )
  let expected_sig = hex2bytes(
    "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155" +
    "5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b",
  )
  let msg = Bytes::from_array([])
  let pk = derive_public_key(sk)
  assert_eq(@hex.encode(pk), @hex.encode(expected_pk))
  let sig = sign(sk, msg)
  assert_eq(@hex.encode(sig), @hex.encode(expected_sig))
  assert_true(verify(pk, msg, sig))
}

///|
test "rfc8032 vector 2: one byte message" {
  let sk = hex2bytes(
    "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb",
  )
  let expected_pk = hex2bytes(
    "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c",
  )
  let msg = hex2bytes("72")
  let expected_sig = hex2bytes(
    "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da" +
    "085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00",
  )
  let pk = derive_public_key(sk)
  assert_eq(@hex.encode(pk), @hex.encode(expected_pk))
  let sig = sign(sk, msg)
  assert_eq(@hex.encode(sig), @hex.encode(expected_sig))
  assert_true(verify(pk, msg, sig))
}

///|
test "rfc8032 vector 3: two byte message" {
  let sk = hex2bytes(
    "c5aa8df43f9f837bedb7442f31dcb7b166d38535076f094b85ce3a2e0b4458f7",
  )
  let expected_pk = hex2bytes(
    "fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025",
  )
  let msg = hex2bytes("af82")
  let expected_sig = hex2bytes(
    "6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac" +
    "18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a",
  )
  let pk = derive_public_key(sk)
  assert_eq(@hex.encode(pk), @hex.encode(expected_pk))
  let sig = sign(sk, msg)
  assert_eq(@hex.encode(sig), @hex.encode(expected_sig))
  assert_true(verify(pk, msg, sig))
}

// ---------------------------------------------------------------------------
// Round-trip and property tests
// ---------------------------------------------------------------------------

///|
test "ed25519: sign and verify round-trip" {
  let sk = Bytes::from_array([
    b'\x01', b'\x02', b'\x03', b'\x04', b'\x05', b'\x06', b'\x07', b'\x08', b'\x09',
    b'\x0a', b'\x0b', b'\x0c', b'\x0d', b'\x0e', b'\x0f', b'\x10', b'\x11', b'\x12',
    b'\x13', b'\x14', b'\x15', b'\x16', b'\x17', b'\x18', b'\x19', b'\x1a', b'\x1b',
    b'\x1c', b'\x1d', b'\x1e', b'\x1f', b'\x20',
  ])
  let msg = Bytes::from_array([b'\x68', b'\x65', b'\x6c', b'\x6c', b'\x6f'])
  let pk = derive_public_key(sk)
  let sig = sign(sk, msg)
  assert_true(sig.length() == 64)
  assert_true(verify(pk, msg, sig))
}

///|
test "ed25519: verify with wrong message fails" {
  let sk = Bytes::from_array([
    b'\x01', b'\x02', b'\x03', b'\x04', b'\x05', b'\x06', b'\x07', b'\x08', b'\x09',
    b'\x0a', b'\x0b', b'\x0c', b'\x0d', b'\x0e', b'\x0f', b'\x10', b'\x11', b'\x12',
    b'\x13', b'\x14', b'\x15', b'\x16', b'\x17', b'\x18', b'\x19', b'\x1a', b'\x1b',
    b'\x1c', b'\x1d', b'\x1e', b'\x1f', b'\x20',
  ])
  let msg = Bytes::from_array([b'\x68', b'\x65', b'\x6c', b'\x6c', b'\x6f'])
  let pk = derive_public_key(sk)
  let sig = sign(sk, msg)
  assert_true(verify(pk, msg, sig))
  let other_msg = Bytes::from_array([
    b'\x77', b'\x6f', b'\x72', b'\x6c', b'\x64',
  ])
  assert_false(verify(pk, other_msg, sig))
}

///|
test "ed25519: verify with wrong public key fails" {
  let sk1 = Bytes::from_array([
    b'\x01', b'\x02', b'\x03', b'\x04', b'\x05', b'\x06', b'\x07', b'\x08', b'\x09',
    b'\x0a', b'\x0b', b'\x0c', b'\x0d', b'\x0e', b'\x0f', b'\x10', b'\x11', b'\x12',
    b'\x13', b'\x14', b'\x15', b'\x16', b'\x17', b'\x18', b'\x19', b'\x1a', b'\x1b',
    b'\x1c', b'\x1d', b'\x1e', b'\x1f', b'\x20',
  ])
  let sk2 = Bytes::from_array([
    b'\x21', b'\x22', b'\x23', b'\x24', b'\x25', b'\x26', b'\x27', b'\x28', b'\x29',
    b'\x2a', b'\x2b', b'\x2c', b'\x2d', b'\x2e', b'\x2f', b'\x30', b'\x31', b'\x32',
    b'\x33', b'\x34', b'\x35', b'\x36', b'\x37', b'\x38', b'\x39', b'\x3a', b'\x3b',
    b'\x3c', b'\x3d', b'\x3e', b'\x3f', b'\x40',
  ])
  let msg = Bytes::from_array([b'\x74', b'\x65', b'\x73', b'\x74'])
  let pk1 = derive_public_key(sk1)
  let pk2 = derive_public_key(sk2)
  let sig = sign(sk1, msg)
  assert_true(verify(pk1, msg, sig))
  assert_false(verify(pk2, msg, sig))
}

///|
test "ed25519: empty message sign and verify" {
  let sk = Bytes::from_array([
    b'\xaa', b'\xbb', b'\xcc', b'\xdd', b'\xee', b'\xff', b'\x00', b'\x11', b'\x22',
    b'\x33', b'\x44', b'\x55', b'\x66', b'\x77', b'\x88', b'\x99', b'\xaa', b'\xbb',
    b'\xcc', b'\xdd', b'\xee', b'\xff', b'\x00', b'\x11', b'\x22', b'\x33', b'\x44',
    b'\x55', b'\x66', b'\x77', b'\x88', b'\x99',
  ])
  let msg = Bytes::from_array([])
  let pk = derive_public_key(sk)
  let sig = sign(sk, msg)
  assert_true(sig.length() == 64)
  assert_true(verify(pk, msg, sig))
}

///|
test "ed25519: deterministic signatures" {
  let sk = Bytes::from_array([
    b'\x42', b'\x42', b'\x42', b'\x42', b'\x42', b'\x42', b'\x42', b'\x42', b'\x42',
    b'\x42', b'\x42', b'\x42', b'\x42', b'\x42', b'\x42', b'\x42', b'\x42', b'\x42',
    b'\x42', b'\x42', b'\x42', b'\x42', b'\x42', b'\x42', b'\x42', b'\x42', b'\x42',
    b'\x42', b'\x42', b'\x42', b'\x42', b'\x42',
  ])
  let msg = Bytes::from_array([b'\x64', b'\x65', b'\x74', b'\x65', b'\x72'])
  let sig1 = sign(sk, msg)
  let sig2 = sign(sk, msg)
  assert_true(@hex.encode(sig1) == @hex.encode(sig2))
}

///|
test "ed25519: signature size is 64 bytes" {
  let sk = Bytes::make(32, b'\x07')
  let msg = Bytes::from_array([b'\x61'])
  let sig = sign(sk, msg)
  assert_true(sig.length() == 64)
}

///|
test "ed25519: public key size is 32 bytes" {
  let sk = Bytes::make(32, b'\x08')
  let pk = derive_public_key(sk)
  assert_true(pk.length() == 32)
}

///|
test "ed25519: verify rejects invalid signature length" {
  let sk = Bytes::make(32, b'\x09')
  let pk = derive_public_key(sk)
  let msg = Bytes::from_array([b'\x61'])
  let short_sig = Bytes::make(32, b'\x00')
  assert_false(verify(pk, msg, short_sig))
}

///|
test "ed25519: verify rejects invalid public key length" {
  let sk = Bytes::make(32, b'\x0a')
  let msg = Bytes::from_array([b'\x61'])
  let sig = sign(sk, msg)
  let short_pk = Bytes::make(16, b'\x00')
  assert_false(verify(short_pk, msg, sig))
}

///|
test "ed25519: multi-block message (200 bytes)" {
  let sk = hex2bytes(
    "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60",
  )
  let pk = derive_public_key(sk)
  let long_msg : Array[Byte] = Array::make(200, b'\x00')
  for i = 0; i < 200; i = i + 1 {
    long_msg[i] = (i % 256).to_byte()
  }
  let msg = Bytes::from_array(long_msg)
  let sig = sign(sk, msg)
  assert_true(verify(pk, msg, sig))
  // Tamper last byte
  let tampered : Array[Byte] = Array::make(200, b'\x00')
  for i = 0; i < 199; i = i + 1 {
    tampered[i] = (i % 256).to_byte()
  }
  tampered[199] = b'\x01'
  assert_false(verify(pk, Bytes::from_array(tampered), sig))
}
