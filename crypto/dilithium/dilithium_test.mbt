/// ML-DSA (FIPS 204) — white-box test suite.
///
/// Covers NTT correctness, key generation, signing, verification, and the
/// negative cases: forgery without the secret key must fail, wrong public
/// keys must reject, tampered messages/signatures must reject.

// ---------------------------------------------------------------------------
// NTT sanity
// ---------------------------------------------------------------------------

///|
test "dilithium: NTT round-trips" {
  let f = Array::make(256, 0)
  for i = 0; i < 256; i = i + 1 {
    f[i] = (i * i * 3 + 11 * i + 5) % 8380417
  }
  let orig = Array::make(256, 0)
  for i = 0; i < 256; i = i + 1 {
    orig[i] = f[i]
  }
  dsa_ntt(f)
  dsa_ntt_inv(f)
  assert_eq(f, orig)
}

///|
test "dilithium: probe e0 round-trip" {
  assert_eq(dsa_debug_roundtrip(0), [1, 0, 0, 0, 0, 0, 0, 0])
}

///|
test "dilithium: probe e1 round-trip" {
  let r = dsa_debug_roundtrip(1)
  assert_eq(r[0], 0)
  assert_eq(r[1], 1)
  assert_eq(r[2], 0)
}

///|
test "dilithium: probe e2 round-trip" {
  let r = dsa_debug_roundtrip(2)
  assert_eq(r[0], 0)
  assert_eq(r[1], 0)
  assert_eq(r[2], 1)
}

///|
fn dsa_pow(base : Int, exp : Int) -> Int {
  let q64 = 8380417L
  let mut b = base.to_int64() % q64
  let mut e = exp
  let mut acc = 1L
  while e > 0 {
    if (e & 1) == 1 {
      acc = (acc * b) % q64
    }
    b = (b * b) % q64
    e = e >> 1
  }
  acc.to_int()
}

///|
test "dilithium: probe NTT(e_1) structure" {
  // The partial NTT maps e_1 to a vector supported on odd indices only;
  // just check determinism and normalization here.
  let a = dsa_debug_ntt_e(1)
  let b = dsa_debug_ntt_e(1)
  assert_eq(a, b)
}

///|
test "dilithium: zeta table sanity" {
  // entries: [0, 1, 2, 3, 64, 127]; zeta = 1753^2 = 3073009 (order 256).
  let t = dsa_debug_zetas()
  assert_eq(t[0], 1)
  assert_eq(t[4], 3073009)
  // zeta^64 is a primitive 4th root of unity: its square is -1.
  assert_eq(dsa_pow(t[1], 2), 8380416)
  assert_eq(dsa_pow(t[2], 4), 8380416)
  assert_eq(dsa_pow(t[5], 256), 1)
}

///|
test "dilithium: root order (1753 has order 512, 1753^2 has order 256)" {
  assert_eq(dsa_pow(1753, 256), 8380416)
  assert_eq(dsa_pow(3073009, 128), 8380416)
  assert_eq(dsa_pow(3073009, 256), 1)
}

///|
test "dilithium: NTT multiplication equals schoolbook negacyclic product" {
  let f = Array::make(256, 0)
  let g = Array::make(256, 0)
  for i = 0; i < 256; i = i + 1 {
    f[i] = (i * 17 + 3) % 8380417
    g[i] = (i * i + 2 * i + 1) % 8380417
  }
  let got = dsa_poly_mul(f, g)
  let q64 = 8380417L
  let want = Array::make(256, 0L)
  for i = 0; i < 256; i = i + 1 {
    for j = 0; j < 256; j = j + 1 {
      let k = i + j
      let coef = (f[i].to_int64() * g[j].to_int64()) % q64
      if k < 256 {
        want[k] = want[k] + coef
      } else {
        want[k - 256] = want[k - 256] - coef
      }
    }
  }
  let want_int = Array::make(256, 0)
  for i = 0; i < 256; i = i + 1 {
    let mut w = want[i] % q64
    if w < 0L {
      w = w + q64
    }
    want_int[i] = w.to_int()
  }
  assert_eq(got, want_int)
}

// ---------------------------------------------------------------------------
// Sign / verify round-trip
// ---------------------------------------------------------------------------

///|
test "dilithium: decompose/low_bits boundary behavior" {
  let got = dsa_debug_lowbits([0, 1, 95231, 95232, 95233, 175162, 8380416], 190464)
  // q-1 = 44*alpha hits the special case: (r1, r0) = (0, r - q) = (0, -1).
  assert_eq(got, [0, 1, 95231, 95232, -95231, -15302, -1])
}

///|
test "dilithium: signing attempt norms stay in theoretical range" {
  let (_, sk) = mldsa_keygen(ml_dsa_44(), 41)
  let stats = mldsa_debug_sign_attempt(sk, msg("debug"))
  // [z_viol, z_max, r0_viol, r0_max, hint_count, g1-beta, g2-beta, alpha, g2, k, l]
  assert_true(stats[1] <= stats[7])
  assert_true(stats[3] <= stats[8])
  assert_true(stats[4] <= 256 * stats[9])
}

///|
fn msg(s : String) -> Bytes {
  let arr : Array[Byte] = []
  let mut i = 0
  while i < s.length() {
    arr.push(s[i].to_int().to_byte())
    i = i + 1
  }
  Bytes::from_array(arr)
}

///|
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
test "dilithium: sign/verify round-trip (ML-DSA-44)" {
  let (pk, sk) = mldsa_keygen(ml_dsa_44(), 42)
  let m = msg("moon-certified ML-DSA test message")
  let sig = dilithium_sign(sk, m, 7)
  assert_true(dilithium_verify(pk, m, sig))
}

///|
test "dilithium: sign/verify round-trip (ML-DSA-65)" {
  let (pk, sk) = mldsa_keygen(ml_dsa_65(), 43)
  let m = msg("another message")
  let sig = dilithium_sign(sk, m, 8)
  assert_true(dilithium_verify(pk, m, sig))
}

///|
test "dilithium: signing is deterministic for fixed (sk, m, nonce)" {
  let (_, sk) = mldsa_keygen(ml_dsa_44(), 44)
  let m = msg("determinism")
  let s1 = dilithium_sign(sk, m, 9)
  let s2 = dilithium_sign(sk, m, 9)
  assert_eq(s1.z, s2.z)
  assert_eq(s1.h, s2.h)
  assert_true(bytes_eq(s1.c_tilde, s2.c_tilde))
}

///|
test "dilithium: different nonces give different signatures" {
  let (_, sk) = mldsa_keygen(ml_dsa_44(), 45)
  let m = msg("nonce-dependence")
  let s1 = dilithium_sign(sk, m, 1)
  let s2 = dilithium_sign(sk, m, 2)
  assert_false(bytes_eq(s1.c_tilde, s2.c_tilde))
}

///|
test "dilithium: signature serialization round-trip" {
  let params = ml_dsa_44()
  let (pk, sk) = mldsa_keygen(params, 46)
  let m = msg("serialization")
  let sig = dilithium_sign(sk, m, 3)
  let wire = dilithium_sig_to_bytes(sig)
  match dilithium_sig_from_bytes(params, wire) {
    Some(sig2) => assert_true(dilithium_verify(pk, m, sig2))
    None => fail("signature round-trip parse failed")
  }
}

// ---------------------------------------------------------------------------
// Negative cases (the fake implementation failed all of these)
// ---------------------------------------------------------------------------

///|
test "dilithium: verification rejects a tampered message" {
  let (pk, sk) = mldsa_keygen(ml_dsa_44(), 46)
  let m = msg("original message")
  let sig = dilithium_sign(sk, m, 3)
  assert_false(dilithium_verify(pk, msg("original messagf"), sig))
}

///|
test "dilithium: verification rejects a tampered signature (z)" {
  let (pk, sk) = mldsa_keygen(ml_dsa_44(), 47)
  let m = msg("sig tamper")
  let sig = dilithium_sign(sk, m, 4)
  sig.z[0][0] = sig.z[0][0] + 1
  assert_false(dilithium_verify(pk, m, sig))
}

///|
test "dilithium: verification rejects a tampered c_tilde" {
  let params = ml_dsa_44()
  let (pk, sk) = mldsa_keygen(params, 48)
  let m = msg("ctilde tamper")
  let sig = dilithium_sign(sk, m, 5)
  let arr : Array[Byte] = []
  let wire = dilithium_sig_to_bytes(sig)
  for i = 0; i < wire.length(); i = i + 1 {
    arr.push(wire[i])
  }
  arr[0] = (arr[0].to_int() ^ 0x01).to_byte()
  match dilithium_sig_from_bytes(params, Bytes::from_array(arr)) {
    Some(sig2) => assert_false(dilithium_verify(pk, m, sig2))
    None => ()
  }
}

///|
test "dilithium: verification with the wrong public key fails" {
  let (_, sk) = mldsa_keygen(ml_dsa_44(), 49)
  let (pk_wrong, _) = mldsa_keygen(ml_dsa_44(), 50)
  let m = msg("wrong pk")
  let sig = dilithium_sign(sk, m, 6)
  assert_false(dilithium_verify(pk_wrong, m, sig))
}

///|
test "dilithium: signatures bind the public key (cross-key rejection)" {
  let (pk1, sk1) = mldsa_keygen(ml_dsa_44(), 51)
  let (_, sk2) = mldsa_keygen(ml_dsa_44(), 52)
  let m = msg("binding")
  let sig1 = dilithium_sign(sk1, m, 1)
  let sig2 = dilithium_sign(sk2, m, 1)
  assert_true(dilithium_verify(pk1, m, sig1))
  assert_false(dilithium_verify(pk1, m, sig2))
}

///|
test "dilithium: empty message round-trip" {
  let (pk, sk) = mldsa_keygen(ml_dsa_44(), 53)
  let m = Bytes::from_array([])
  let sig = dilithium_sign(sk, m, 2)
  assert_true(dilithium_verify(pk, m, sig))
}
