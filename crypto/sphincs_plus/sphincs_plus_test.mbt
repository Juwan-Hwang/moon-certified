// Tests for crypto/sphincs_plus — SLH-DSA (SPHINCS+) stateless hash-based
// signatures, SHAKE256 "128f" shape.

///|
fn spx_seed(n : Int) -> Bytes {
  let arr : Array[Byte] = []
  let mut i = 0
  while i < 48 {
    arr.push(((n * 97 + i * 31 + 11) & 0xFF).to_byte())
    i = i + 1
  }
  Bytes::from_array(arr)
}

///|
fn spx_msg(s : String) -> Bytes {
  let arr : Array[Byte] = []
  let mut i = 0
  while i < s.length() {
    arr.push(s[i].to_int().to_byte())
    i = i + 1
  }
  Bytes::from_array(arr)
}

///|
test "sphincs: keygen produces well-formed keys" {
  let (pk, sk) = sphincs_keygen(spx_seed(1))
  assert_eq(pk.seed.length(), 16)
  assert_eq(pk.root.length(), 16)
  assert_eq(sk.seed.length(), 16)
  assert_eq(sk.prf.length(), 16)
  // The public key must not contain the secret seed or PRF key, and the
  // pk embedded in sk must match the returned pk.
  let pk_bytes = sphincs_pk_to_bytes(pk)
  assert_false(spx_bytes_eq_pub(spx_slice_off(pk_bytes, 0, 16), sk.seed))
  assert_false(spx_bytes_eq_pub(spx_slice_off(pk_bytes, 16, 16), sk.seed))
  assert_false(spx_bytes_eq_pub(spx_slice_off(pk_bytes, 0, 16), sk.prf))
  assert_true(spx_bytes_eq_pub(pk_bytes, sphincs_pk_to_bytes(sk.pk)))
}

///|
fn spx_slice_off(b : Bytes, off : Int, len : Int) -> Bytes {
  let arr : Array[Byte] = []
  let mut i = 0
  while i < len {
    arr.push(b[off + i])
    i = i + 1
  }
  Bytes::from_array(arr)
}

///|
fn spx_bytes_eq_pub(a : Bytes, b : Bytes) -> Bool {
  if a.length() != b.length() {
    return false
  }
  let mut i = 0
  while i < a.length() {
    if a[i] != b[i] {
      return false
    }
    i = i + 1
  }
  true
}

///|
test "sphincs: sign/verify round-trip and determinism" {
  let (pk, sk) = sphincs_keygen(spx_seed(2))
  let m = spx_msg("slh-dsa test message")
  let sig = sphincs_sign(sk, m)
  assert_true(sphincs_verify(pk, m, sig))
  // Deterministic signing (opt_rand = pk).
  let sig2 = sphincs_sign(sk, m)
  assert_true(spx_bytes_eq_pub(sig.data, sig2.data))
  // Signature size: R + FORS + hypertree blocks.
  assert_eq(sig.data.length(), 16 + 14 * 13 * 16 + 22 * (35 + 3) * 16)
}

///|
test "sphincs: tampered message is rejected" {
  let (pk, sk) = sphincs_keygen(spx_seed(3))
  let m = spx_msg("original")
  let sig = sphincs_sign(sk, m)
  assert_false(sphincs_verify(pk, spx_msg("originak"), sig))
}

///|
test "sphincs: tampered signature is rejected" {
  let (pk, sk) = sphincs_keygen(spx_seed(4))
  let m = spx_msg("tamper me")
  let sig = sphincs_sign(sk, m)
  let arr : Array[Byte] = []
  let mut i = 0
  while i < sig.data.length() {
    arr.push(sig.data[i])
    i = i + 1
  }
  // Flip one bit in the FORS section.
  arr[100] = (arr[100].to_int() ^ 0x01).to_byte()
  assert_false(
    sphincs_verify(pk, m, sphincs_sig_from_bytes(Bytes::from_array(arr))),
  )
  // Truncated signature is rejected.
  assert_false(
    sphincs_verify(pk, m, sphincs_sig_from_bytes(spx_slice_test(sig.data, 100))),
  )
}

///|
fn spx_slice_test(b : Bytes, len : Int) -> Bytes {
  let arr : Array[Byte] = []
  let mut i = 0
  while i < len {
    arr.push(b[i])
    i = i + 1
  }
  Bytes::from_array(arr)
}

///|
test "sphincs: verification with a different public key fails" {
  let (_, sk) = sphincs_keygen(spx_seed(5))
  let (pk_other, _) = sphincs_keygen(spx_seed(6))
  let m = spx_msg("binding")
  let sig = sphincs_sign(sk, m)
  assert_false(sphincs_verify(pk_other, m, sig))
}
