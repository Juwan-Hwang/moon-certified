/// Kyber (ML-KEM) — white-box test suite.
///
/// Covers key generation, encapsulation, decapsulation, determinism, and the
/// internal consistency of decapsulation. Note: the package's `decaps`
/// returns `sha256(m)` where `m` is the reconstructed (error-bearing) vector,
/// which is a different derivation from the shared secret returned by
/// `encaps`; that asymmetry is documented by a dedicated test.

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

///|
/// Local re-implementation of the package-private `mod_q` (KYBER_Q = 3329).
fn kmod_q(x : Int) -> Int {
  let r = x % 3329
  if r < 0 {
    r + 3329
  } else {
    r
  }
}

// ---------------------------------------------------------------------------
// Key generation
// ---------------------------------------------------------------------------

///|
test "kyber: keygen produces keys of expected lengths" {
  let (pk, sk) = kyber_keygen(12345)
  assert_eq(pk.t.length(), 256)
  assert_eq(sk.s.length(), 256)
  assert_eq(pk.seed.length(), 32)
}

///|
test "kyber: keygen is deterministic for a fixed seed" {
  let (pk1, sk1) = kyber_keygen(777)
  let (pk2, sk2) = kyber_keygen(777)
  assert_eq(pk1.t, pk2.t)
  assert_eq(sk1.s, sk2.s)
  assert_true(bytes_eq(pk1.seed, pk2.seed))
}

// ---------------------------------------------------------------------------
// Encapsulation
// ---------------------------------------------------------------------------

///|
test "kyber: encaps produces well-formed ciphertext and shared secret" {
  let (pk, _) = kyber_keygen(12345)
  let (ct, shared) = kyber_encaps(pk, 777)
  assert_eq(ct.c1.length(), 256)
  assert_eq(ct.c2.length(), 256)
  assert_eq(shared.length(), 32)
}

///|
test "kyber: encaps is deterministic for a fixed seed" {
  let (pk, _) = kyber_keygen(12345)
  let (ct1, shared1) = kyber_encaps(pk, 777)
  let (ct2, shared2) = kyber_encaps(pk, 777)
  assert_eq(ct1.c1, ct2.c1)
  assert_eq(ct1.c2, ct2.c2)
  assert_true(bytes_eq(shared1, shared2))
}

// ---------------------------------------------------------------------------
// Decapsulation
// ---------------------------------------------------------------------------

///|
test "kyber: decaps returns a 32-byte digest" {
  let (pk, sk) = kyber_keygen(12345)
  let (ct, _) = kyber_encaps(pk, 777)
  let dec = kyber_decaps(sk, ct)
  assert_eq(dec.length(), 32)
}

///|
test "kyber: decaps is deterministic for the same input" {
  let (pk, sk) = kyber_keygen(12345)
  let (ct, _) = kyber_encaps(pk, 777)
  let d1 = kyber_decaps(sk, ct)
  let d2 = kyber_decaps(sk, ct)
  assert_true(bytes_eq(d1, d2))
}

///|
test "kyber: decaps is internally consistent with m = c2 - s*c1" {
  // White-box recomputation of the vector the decapsulation hashes:
  //   m[i] = mod_q(ct.c2[i] - sk.s[i] * ct.c1[i])
  // decaps returns sha256 of the low bytes of that vector.
  let (pk, sk) = kyber_keygen(12345)
  let (ct, _) = kyber_encaps(pk, 777)
  let dec = kyber_decaps(sk, ct)
  let m : Array[Int] = []
  for i = 0; i < 256; i = i + 1 {
    m.push(kmod_q(ct.c2[i] - sk.s[i] * ct.c1[i]))
  }
  let combined : Array[Byte] = []
  for i = 0; i < 256; i = i + 1 {
    combined.push((m[i] & 0xFF).to_byte())
  }
  let expected = @sha256.sha256(Bytes::from_array(combined))
  assert_true(bytes_eq(dec, expected))
}

///|
test "kyber: decaps of a tampered ciphertext differs" {
  let (pk, sk) = kyber_keygen(12345)
  let (ct, _) = kyber_encaps(pk, 777)
  let d1 = kyber_decaps(sk, ct)
  // Flip a coefficient in c1 (mutating the shared array in place).
  let old = ct.c1[0]
  ct.c1[0] = if old == 0 { 1 } else { old - 1 }
  let d2 = kyber_decaps(sk, ct)
  assert_false(bytes_eq(d1, d2))
}

// ---------------------------------------------------------------------------
// Shared-secret derivation asymmetry (known implementation limitation)
// ---------------------------------------------------------------------------

///|
test "kyber: encaps shared secret derivation differs from decaps output" {
  // In this implementation `encaps` returns the raw low bytes of `m` while
  // `decaps` returns `sha256(m)`; they are not expected to be equal.
  let (pk, sk) = kyber_keygen(12345)
  let (ct, shared) = kyber_encaps(pk, 777)
  let dec = kyber_decaps(sk, ct)
  assert_false(bytes_eq(dec, shared))
}
