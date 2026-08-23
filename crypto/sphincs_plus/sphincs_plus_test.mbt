/// SPHINCS+ (SLH-DSA) — white-box test suite.
///
/// Covers key generation, deterministic signing, and WOTS+-based verification
/// including negative (tamper / wrong key) cases. The WOTS+ signature arrays
/// are mutated in place to exercise the negative paths without constructing the
/// (read-only in the test context) `SphincsSignature` struct directly.

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
test "sphincs: keygen returns root and seed of expected sizes" {
  let seed = Bytes::from_array([b'\x01', b'\x02', b'\x03', b'\x04'])
  let (pk, sk) = sphincs_keygen(seed)
  assert_eq(pk.seed.length(), 4)
  assert_eq(sk.seed.length(), 4)
  // root is a 16-byte hash (SPHINCS_N)
  assert_eq(pk.root.length(), 16)
}

///|
test "sphincs: keygen is deterministic for a fixed seed" {
  let seed = Bytes::from_array([b'\x01', b'\x02', b'\x03', b'\x04'])
  let (pk1, sk1) = sphincs_keygen(seed)
  let (pk2, sk2) = sphincs_keygen(seed)
  assert_true(bytes_eq(pk1.root, pk2.root))
  assert_true(bytes_eq(pk1.seed, pk2.seed))
  assert_true(bytes_eq(sk1.seed, sk2.seed))
}

// ---------------------------------------------------------------------------
// Round-trip sign / verify
// ---------------------------------------------------------------------------

///|
test "sphincs: sign and verify round-trip" {
  let seed = Bytes::from_array([b'\x01', b'\x02', b'\x03', b'\x04'])
  let (pk, sk) = sphincs_keygen(seed)
  let msg = Bytes::from_array([b'\x68', b'\x65', b'\x6c', b'\x6c', b'\x6f'])
  let sig = sphincs_sign(sk, msg)
  assert_true(sphincs_verify(pk, msg, sig))
}

///|
test "sphincs: empty message round-trip" {
  let seed = Bytes::from_array([b'\x0a', b'\x0b', b'\x0c', b'\x0d'])
  let (pk, sk) = sphincs_keygen(seed)
  let msg = Bytes::from_array([])
  let sig = sphincs_sign(sk, msg)
  assert_true(sphincs_verify(pk, msg, sig))
}

///|
test "sphincs: single byte message round-trip" {
  let seed = Bytes::from_array([b'\x11', b'\x22', b'\x33', b'\x44'])
  let (pk, sk) = sphincs_keygen(seed)
  let msg = Bytes::from_array([b'\x61'])
  let sig = sphincs_sign(sk, msg)
  assert_true(sphincs_verify(pk, msg, sig))
}

///|
test "sphincs: multi-byte message round-trip" {
  let seed = Bytes::from_array([b'\xaa', b'\xbb', b'\xcc', b'\xdd'])
  let (pk, sk) = sphincs_keygen(seed)
  let msg = Bytes::from_array([
    b'\x74', b'\x68', b'\x65', b'\x20', b'\x71', b'\x75', b'\x69', b'\x63', b'\x6b',
    b'\x20', b'\x62', b'\x72', b'\x6f', b'\x77', b'\x6e', b'\x20', b'\x66', b'\x6f',
    b'\x78',
  ])
  let sig = sphincs_sign(sk, msg)
  assert_true(sphincs_verify(pk, msg, sig))
}

// ---------------------------------------------------------------------------
// Determinism
// ---------------------------------------------------------------------------

///|
test "sphincs: signing is deterministic for a fixed key" {
  let seed = Bytes::from_array([b'\x01', b'\x02', b'\x03', b'\x04'])
  let (_, sk) = sphincs_keygen(seed)
  let msg = Bytes::from_array([b'\x74', b'\x65', b'\x73', b'\x74'])
  let s1 = sphincs_sign(sk, msg)
  let s2 = sphincs_sign(sk, msg)
  assert_eq(s1.idx, s2.idx)
  assert_eq(s1.wots_sig.sig.length(), s2.wots_sig.sig.length())
  for i = 0; i < s1.wots_sig.sig.length(); i = i + 1 {
    assert_true(bytes_eq(s1.wots_sig.sig[i], s2.wots_sig.sig[i]))
  }
}

// ---------------------------------------------------------------------------
// Negative tests
// ---------------------------------------------------------------------------

///|
test "sphincs: tampered message fails verification" {
  let seed = Bytes::from_array([b'\x01', b'\x02', b'\x03', b'\x04'])
  let (pk, sk) = sphincs_keygen(seed)
  let msg = Bytes::from_array([b'\x68', b'\x65', b'\x6c', b'\x6c', b'\x6f'])
  let sig = sphincs_sign(sk, msg)
  assert_true(sphincs_verify(pk, msg, sig))
  let tampered = Bytes::from_array([b'\x68', b'\x65', b'\x6c', b'\x6c', b'\x66'])
  assert_false(sphincs_verify(pk, tampered, sig))
}

///|
test "sphincs: tampered WOTS signature component fails verification" {
  let seed = Bytes::from_array([b'\x01', b'\x02', b'\x03', b'\x04'])
  let (pk, sk) = sphincs_keygen(seed)
  let msg = Bytes::from_array([b'\x68', b'\x65', b'\x6c', b'\x6c', b'\x6f'])
  let sig = sphincs_sign(sk, msg)
  assert_true(sphincs_verify(pk, msg, sig))
  // Replace the first WOTS+ signature component with a wrong 16-byte value.
  let wrong : Array[Byte] = []
  for i = 0; i < 16; i = i + 1 {
    wrong.push(b'\x00')
  }
  sig.wots_sig.sig[0] = Bytes::from_array(wrong)
  assert_false(sphincs_verify(pk, msg, sig))
}

///|
test "sphincs: verification against the wrong public key fails" {
  let seed1 = Bytes::from_array([b'\x01', b'\x02', b'\x03', b'\x04'])
  let seed2 = Bytes::from_array([b'\x05', b'\x06', b'\x07', b'\x08'])
  let (pk1, sk1) = sphincs_keygen(seed1)
  let (pk2, _) = sphincs_keygen(seed2)
  let msg = Bytes::from_array([b'\x68', b'\x65', b'\x6c', b'\x6c', b'\x6f'])
  let sig = sphincs_sign(sk1, msg)
  assert_true(sphincs_verify(pk1, msg, sig))
  assert_false(sphincs_verify(pk2, msg, sig))
}
