/// ML-KEM (FIPS 203) — white-box test suite.
///
/// Covers parameter sets, key generation, encapsulation, decapsulation,
/// serialization round-trips, implicit rejection, and negative cases
/// (wrong secret key, tampered ciphertext).

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

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
fn bytes_to_arr(b : Bytes) -> Array[Byte] {
  let a : Array[Byte] = []
  for i = 0; i < b.length(); i = i + 1 {
    a.push(b[i])
  }
  a
}

// ---------------------------------------------------------------------------
// NTT sanity (negacyclic convolution)
// ---------------------------------------------------------------------------

///|
test "kyber: NTT round-trips" {
  let f = Array::make(256, 0)
  for i = 0; i < 256; i = i + 1 {
    f[i] = (i * i * 7 + 3 * i + 1) % 3329
  }
  let orig = Array::make(256, 0)
  for i = 0; i < 256; i = i + 1 {
    orig[i] = f[i]
  }
  ntt(f)
  ntt_inv(f)
  assert_eq(f, orig)
}

///|
test "kyber: NTT multiplication equals schoolbook negacyclic product" {
  let f = Array::make(256, 0)
  let g = Array::make(256, 0)
  for i = 0; i < 256; i = i + 1 {
    f[i] = (i * 13 + 5) % 3329
    g[i] = (i * i + 2 * i + 7) % 3329
  }
  let got = poly_mul(f, g)
  // Schoolbook negacyclic reference: h[(i+j) mod 256], sign flipped on wrap.
  let want = Array::make(256, 0)
  for i = 0; i < 256; i = i + 1 {
    for j = 0; j < 256; j = j + 1 {
      let k = i + j
      let coef = (f[i] * g[j]) % 3329
      if k < 256 {
        want[k] = want[k] + coef
      } else {
        want[k - 256] = want[k - 256] - coef
      }
    }
  }
  for i = 0; i < 256; i = i + 1 {
    want[i] = want[i] % 3329
    if want[i] < 0 {
      want[i] = want[i] + 3329
    }
  }
  assert_eq(got, want)
}

///|
test "kyber: compress/decompress round-trip stays within error bound" {
  // |Decompress_d(Compress_d(x)) - x| <= q / 2^{d+1}
  for d in [1, 4, 5, 10, 11, 12] {
    for x in [0, 1, 832, 1664, 1665, 2497, 3328] {
      let r = decompress(compress(x, d), d)
      let mut err = r - x
      if err < 0 {
        err = -err
      }
      if err > 3329 / 2 {
        err = 3329 - err
      }
      let bound = 3329 / (2 * (1 << d)) + 1
      assert_true(err <= bound)
    }
  }
}

///|
test "kyber: K-PKE encrypt/decrypt round-trip (white-box)" {
  let params = ml_kem_512()
  let derived = @sha3.sha3_512(Bytes::from_array([b'\x01']))
  let d_arr : Array[Byte] = []
  for i = 0; i < 32; i = i + 1 {
    d_arr.push(derived[i])
  }
  let d = Bytes::from_array(d_arr)
  let (s_hat, t_hat, rho) = kpke_keygen(params, d)
  let m_bits = Array::make(32, b'\x00')
  for i = 0; i < 32; i = i + 1 {
    m_bits[i] = ((i * 37) % 256).to_byte()
  }
  let r_seed = @sha3.shake256(Bytes::from_array([b'\x02']), 32)
  let (u, v) = kpke_encrypt(params, t_hat, rho, m_bits, r_seed)
  let dec = kpke_decrypt(params, s_hat, u, v)
  assert_eq(dec, m_bits)
}

///|
test "kyber: K-PKE decryption bilinear identity holds exactly (no noise)" {
  let params = ml_kem_512()
  let derived = @sha3.sha3_512(Bytes::from_array([b'\x01']))
  let d_arr : Array[Byte] = []
  for i = 0; i < 32; i = i + 1 {
    d_arr.push(derived[i])
  }
  let d = Bytes::from_array(d_arr)
  let (s_hat, _, rho, clean) = kpke_keygen_full(params, d)
  let r_seed = @sha3.shake256(Bytes::from_array([b'\x02']), 32)
  assert_eq(kpke_debug_bilinear(params, s_hat, clean, rho, r_seed), 0)
}

// ---------------------------------------------------------------------------
// Key generation and sizes
// ---------------------------------------------------------------------------

///|
test "kyber: public key serializes to FIPS 203 size (768: 1184 bytes)" {
  let (pk, _) = mlkem_keygen(ml_kem_768(), 42)
  assert_eq(pk.t_hat.length(), 3)
  assert_eq(pk.rho.length(), 32)
  assert_eq(kyber_pk_to_bytes(pk).length(), 384 * 3 + 32)
}

///|
test "kyber: keygen is deterministic for a fixed seed" {
  let (pk1, sk1) = kyber_keygen(777)
  let (pk2, sk2) = kyber_keygen(777)
  assert_true(bytes_eq(kyber_pk_to_bytes(pk1), kyber_pk_to_bytes(pk2)))
  assert_true(bytes_eq(sk1.z, sk2.z))
  assert_true(bytes_eq(sk1.h, sk2.h))
}

///|
test "kyber: different seeds give different keys" {
  let (pk1, _) = kyber_keygen(1)
  let (pk2, _) = kyber_keygen(2)
  assert_false(bytes_eq(kyber_pk_to_bytes(pk1), kyber_pk_to_bytes(pk2)))
}

// ---------------------------------------------------------------------------
// Shared-secret agreement (the property the fake implementation lacked)
// ---------------------------------------------------------------------------

///|
test "kyber: encaps and decaps agree on the shared secret (all params)" {
  for params in [ml_kem_512(), ml_kem_768(), ml_kem_1024()] {
    let (pk, sk) = mlkem_keygen(params, 12345)
    let (ct, shared) = kyber_encaps(pk, 777)
    let dec = kyber_decaps(sk, ct)
    assert_eq(shared.length(), 32)
    assert_true(bytes_eq(shared, dec))
  }
}

///|
test "kyber: agreement holds across many independent sessions" {
  for s in [1, 2, 3, 100, 999999] {
    let (pk, sk) = kyber_keygen(s)
    let (ct, shared) = kyber_encaps(pk, s + 1)
    let dec = kyber_decaps(sk, ct)
    assert_true(bytes_eq(shared, dec))
  }
}

// ---------------------------------------------------------------------------
// Serialization
// ---------------------------------------------------------------------------

///|
test "kyber: ciphertext serialize/parse round-trip preserves decapsulation" {
  let params = ml_kem_768()
  let (pk, sk) = mlkem_keygen(params, 555)
  let (ct, shared) = kyber_encaps(pk, 666)
  let wire = kyber_ct_to_bytes(ct)
  // 32*k*du + 32*dv = 32*3*10 + 32*4 = 1088 bytes for ML-KEM-768.
  assert_eq(wire.length(), 1088)
  let ct2 = kyber_ct_from_bytes(params, wire)
  let dec = kyber_decaps(sk, ct2)
  assert_true(bytes_eq(shared, dec))
}

///|
test "kyber: ciphertext sizes match FIPS 203" {
  let (pk512, _) = mlkem_keygen(ml_kem_512(), 1)
  let (ct512, _) = kyber_encaps(pk512, 1)
  assert_eq(kyber_ct_to_bytes(ct512).length(), 768)
  let (pk1024, _) = mlkem_keygen(ml_kem_1024(), 1)
  let (ct1024, _) = kyber_encaps(pk1024, 1)
  assert_eq(kyber_ct_to_bytes(ct1024).length(), 1568)
}

// ---------------------------------------------------------------------------
// Negative cases
// ---------------------------------------------------------------------------

///|
test "kyber: tampered ciphertext triggers implicit rejection" {
  let params = ml_kem_768()
  let (pk, sk) = mlkem_keygen(params, 12345)
  let (ct, shared) = kyber_encaps(pk, 777)
  // Tamper at the wire level (flip one byte of the compressed u part).
  let wire = bytes_to_arr(kyber_ct_to_bytes(ct))
  wire[100] = (wire[100].to_int() ^ 0x01).to_byte()
  let ct2 = kyber_ct_from_bytes(params, Bytes::from_array(wire))
  let dec = kyber_decaps(sk, ct2)
  assert_eq(dec.length(), 32)
  assert_false(bytes_eq(dec, shared))
}

///|
test "kyber: tampered v part triggers implicit rejection" {
  let params = ml_kem_768()
  let (pk, sk) = mlkem_keygen(params, 12345)
  let (ct, shared) = kyber_encaps(pk, 777)
  // v starts at byte 960 for ML-KEM-768 (3*320 u-bytes).
  let wire = bytes_to_arr(kyber_ct_to_bytes(ct))
  wire[1000] = (wire[1000].to_int() ^ 0x01).to_byte()
  let ct2 = kyber_ct_from_bytes(params, Bytes::from_array(wire))
  let dec = kyber_decaps(sk, ct2)
  assert_false(bytes_eq(dec, shared))
}

///|
test "kyber: NTT multiplication homomorphism (white-box diagnostic)" {
  assert_eq(kyber_debug_homomorphism(3), 0)
}

///|
test "kyber: decapsulation with the wrong secret key disagrees" {
  let (pk, _) = kyber_keygen(12345)
  let (_, sk_wrong) = kyber_keygen(54321)
  let (ct, shared) = kyber_encaps(pk, 777)
  let dec = kyber_decaps(sk_wrong, ct)
  assert_false(bytes_eq(dec, shared))
}

///|
test "kyber: encaps to different public keys yields different secrets" {
  let (pk1, sk1) = kyber_keygen(111)
  let (pk2, _) = kyber_keygen(222)
  let (ct1, shared1) = kyber_encaps(pk1, 333)
  let (_, shared2) = kyber_encaps(pk2, 333)
  assert_false(bytes_eq(shared1, shared2))
  // Sanity: the honest path still agrees.
  assert_true(bytes_eq(shared1, kyber_decaps(sk1, ct1)))
}
