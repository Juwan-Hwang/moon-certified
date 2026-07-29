/// ECDSA test suite.
///
/// Tests include:
/// 1. RFC 6979 Appendix A.2.5 known-answer test vectors (P-256/SHA-256)
/// 2. Round-trip sign/verify tests
/// 3. Negative tests (wrong message, wrong key, invalid signatures)

// ---------------------------------------------------------------------------
// Helper: hex string → Bytes
// ---------------------------------------------------------------------------

fn hex2bytes(s : String) -> Bytes {
  @hex.decode(s).unwrap()
}

// ---------------------------------------------------------------------------
// RFC 6979 Appendix A.2.5 Test Vectors (P-256, SHA-256)
// ---------------------------------------------------------------------------

test "rfc6979 A.2.5: public key derivation" {
  let sk = hex2bytes(
    "c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721",
  )
  let expected_pk = hex2bytes(
    "04" +
    "60fed4ba255a9d31c961eb74c6356d68c049b8923b61fa6ce669622e60f29fb6" +
    "7903fe1008b8bc99a41ae9e95628bc64f2f1b20c2d7e9f5177a3c294d4462299",
  )
  let pk = derive_public_key(sk)
  assert_eq(@hex.encode(pk), @hex.encode(expected_pk))
}

test "rfc6979 A.2.5: sign 'sample'" {
  let sk = hex2bytes(
    "c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721",
  )
  let pk = derive_public_key(sk)
  // Message "sample"
  let msg = Bytes::from_array([
    b'\x73', b'\x61', b'\x6d', b'\x70', b'\x6c', b'\x65',
  ])
  let expected_r = hex2bytes(
    "efd48b2aacb6a8fd1140dd9cd45e81d69d2c877b56aaf991c34d0ea84eaf3716",
  )
  let expected_s = hex2bytes(
    "f7cb1c942d657c41d436c7a1b6e29f65f3e900dbb9aff4064dc4ab2f843acda8",
  )
  let expected_sig = hex2bytes(
    "efd48b2aacb6a8fd1140dd9cd45e81d69d2c877b56aaf991c34d0ea84eaf3716" +
    "f7cb1c942d657c41d436c7a1b6e29f65f3e900dbb9aff4064dc4ab2f843acda8",
  )
  let sig = sign(sk, msg)
  assert_eq(@hex.encode(sig), @hex.encode(expected_sig))
  // Verify the signature
  assert_true(verify(pk, msg, sig))
  // Also verify individual r and s values (extract from 64-byte sig)
  let r_actual : Array[Byte] = []
  let s_actual : Array[Byte] = []
  for i = 0; i < 32; i = i + 1 {
    r_actual.push(sig[i])
  }
  for i = 0; i < 32; i = i + 1 {
    s_actual.push(sig[32 + i])
  }
  assert_eq(@hex.encode(Bytes::from_array(r_actual)), @hex.encode(expected_r))
  assert_eq(@hex.encode(Bytes::from_array(s_actual)), @hex.encode(expected_s))
}

test "rfc6979 A.2.5: sign 'test'" {
  let sk = hex2bytes(
    "c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721",
  )
  let pk = derive_public_key(sk)
  // Message "test"
  let msg = Bytes::from_array([b'\x74', b'\x65', b'\x73', b'\x74'])
  let expected_sig = hex2bytes(
    "f1abb023518351cd71d881567b1ea663ed3efcf6c5132b354f28d3b0b7d38367" +
    "019f4113742a2b14bd25926b49c649155f267e60d3814b4c0cc84250e46f0083",
  )
  let sig = sign(sk, msg)
  assert_eq(@hex.encode(sig), @hex.encode(expected_sig))
  assert_true(verify(pk, msg, sig))
}

// ---------------------------------------------------------------------------
// Round-trip tests
// ---------------------------------------------------------------------------

test "ecdsa: sign and verify round-trip" {
  let sk = hex2bytes(
    "c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721",
  )
  let pk = derive_public_key(sk)
  let msg = Bytes::from_array([b'\x68', b'\x65', b'\x6c', b'\x6c', b'\x6f'])
  let sig = sign(sk, msg)
  assert_true(sig.length() == 64)
  assert_true(verify(pk, msg, sig))
}

test "ecdsa: deterministic signatures" {
  let sk = hex2bytes(
    "c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721",
  )
  let msg = Bytes::from_array([b'\x64', b'\x65', b'\x74', b'\x65', b'\x72'])
  let sig1 = sign(sk, msg)
  let sig2 = sign(sk, msg)
  assert_true(@hex.encode(sig1) == @hex.encode(sig2))
}

test "ecdsa: verify with wrong message fails" {
  let sk = hex2bytes(
    "c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721",
  )
  let pk = derive_public_key(sk)
  let msg = Bytes::from_array([b'\x68', b'\x65', b'\x6c', b'\x6c', b'\x6f'])
  let sig = sign(sk, msg)
  assert_true(verify(pk, msg, sig))
  let other_msg = Bytes::from_array([b'\x77', b'\x6f', b'\x72', b'\x6c', b'\x64'])
  assert_false(verify(pk, other_msg, sig))
}

test "ecdsa: verify with wrong public key fails" {
  let sk1 = hex2bytes(
    "c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721",
  )
  let sk2 = hex2bytes(
    "0000000000000000000000000000000000000000000000000000000000000001",
  )
  let msg = Bytes::from_array([b'\x74', b'\x65', b'\x73', b'\x74'])
  let pk1 = derive_public_key(sk1)
  let pk2 = derive_public_key(sk2)
  let sig = sign(sk1, msg)
  assert_true(verify(pk1, msg, sig))
  assert_false(verify(pk2, msg, sig))
}

test "ecdsa: empty message sign and verify" {
  let sk = hex2bytes(
    "c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721",
  )
  let pk = derive_public_key(sk)
  let msg = Bytes::from_array([])
  let sig = sign(sk, msg)
  assert_true(sig.length() == 64)
  assert_true(verify(pk, msg, sig))
}

test "ecdsa: signature size is 64 bytes" {
  let sk = hex2bytes(
    "c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721",
  )
  let msg = Bytes::from_array([b'\x61'])
  let sig = sign(sk, msg)
  assert_true(sig.length() == 64)
}

test "ecdsa: public key size is 65 bytes" {
  let sk = hex2bytes(
    "c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721",
  )
  let pk = derive_public_key(sk)
  assert_true(pk.length() == 65)
  assert_eq(pk[0], b'\x04')
}

test "ecdsa: verify rejects invalid signature length" {
  let sk = hex2bytes(
    "c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721",
  )
  let pk = derive_public_key(sk)
  let msg = Bytes::from_array([b'\x61'])
  let short_sig = Bytes::make(32, b'\x00')
  assert_false(verify(pk, msg, short_sig))
}

test "ecdsa: verify rejects invalid public key length" {
  let sk = hex2bytes(
    "c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721",
  )
  let msg = Bytes::from_array([b'\x61'])
  let sig = sign(sk, msg)
  let short_pk = Bytes::make(33, b'\x00')
  assert_false(verify(short_pk, msg, sig))
}

test "ecdsa: verify rejects tampered signature" {
  let sk = hex2bytes(
    "c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721",
  )
  let pk = derive_public_key(sk)
  let msg = Bytes::from_array([b'\x61'])
  let sig = sign(sk, msg)
  // Flip a bit in the signature
  let tampered : Array[Byte] = []
  for i = 0; i < 64; i = i + 1 {
    if i == 0 {
      tampered.push((sig[i].to_int() ^ 0x01).to_byte())
    } else {
      tampered.push(sig[i])
    }
  }
  assert_false(verify(pk, msg, Bytes::from_array(tampered)))
}
