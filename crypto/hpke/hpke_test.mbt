// Tests for crypto/hpke — RFC 9180 Base mode over DHKEM(X25519) +
// HKDF-SHA256 + ChaCha20Poly1305 / AES-128-GCM.

///|
fn hpke_seed(n : Int) -> Bytes {
  let arr : Array[Byte] = []
  for i = 0; i < 40; i = i + 1 {
    arr.push(((n * 131 + i * 17 + 3) & 0xFF).to_byte())
  }
  Bytes::from_array(arr)
}

///|
test "hpke_roundtrip_chacha20poly1305" {
  let config = hpke_default_config()
  let (sk_r, pk_r) = hpke_generate_keypair(hpke_seed(1))
  // The recipient key is a real random key (the old toy only worked
  // with an all-zero private key).
  let mut all_zero = true
  for i = 0; i < sk_r.length(); i = i + 1 {
    if sk_r[i].to_int() != 0 {
      all_zero = false
    }
  }
  assert_eq(all_zero, false)
  let info = b"hpke test info"
  let aad = b"associated data"
  let pt = b"attack at dawn"
  let (enc, sender) = hpke_setup_base_sender(config, pk_r, info, hpke_seed(2))
  let ct = hpke_seal(sender, aad, pt)
  let receiver = hpke_setup_base_receiver(config, enc, sk_r, info)
  match hpke_open(receiver, aad, ct) {
    Some(out) => assert_eq(out, pt)
    None => fail("hpke_open failed on a valid ciphertext")
  }
}

///|
test "hpke_roundtrip_aes128gcm" {
  let config = HpkeConfig::new(
    HPKE_KEM_DHKEM_X25519,
    HPKE_KDF_HKDF_SHA256,
    HPKE_AEAD_AES128GCM,
  )
  let (sk_r, pk_r) = hpke_generate_keypair(hpke_seed(3))
  let (enc, sender) = hpke_setup_base_sender(config, pk_r, b"", hpke_seed(4))
  let ct = hpke_seal(sender, b"meta", b"gcm payload")
  let receiver = hpke_setup_base_receiver(config, enc, sk_r, b"")
  match hpke_open(receiver, b"meta", ct) {
    Some(out) => assert_eq(out, b"gcm payload")
    None => fail("hpke_open failed for AES-128-GCM")
  }
}

///|
test "hpke_wrong_recipient_key_fails" {
  let config = hpke_default_config()
  let (_sk_r, pk_r) = hpke_generate_keypair(hpke_seed(5))
  let (sk_wrong, _) = hpke_generate_keypair(hpke_seed(6))
  let (enc, sender) = hpke_setup_base_sender(config, pk_r, b"ctx", hpke_seed(7))
  let ct = hpke_seal(sender, b"", b"secret")
  // Decapsulating with a different private key must not yield the
  // plaintext: the KEM shared secret differs, so AEAD auth fails.
  let receiver = hpke_setup_base_receiver(config, enc, sk_wrong, b"ctx")
  assert_eq(hpke_open(receiver, b"", ct), None)
}

///|
test "hpke_authentication_properties" {
  let config = hpke_default_config()
  let (sk_r, pk_r) = hpke_generate_keypair(hpke_seed(8))
  let (enc, sender) = hpke_setup_base_sender(
    config,
    pk_r,
    b"info",
    hpke_seed(9),
  )
  let ct = hpke_seal(sender, b"aad", b"payload")
  // Tampered ciphertext.
  let tampered = ct.to_array()
  tampered[0] = (tampered[0].to_int() ^ 0x01).to_byte()
  let r1 = hpke_setup_base_receiver(config, enc, sk_r, b"info")
  assert_eq(hpke_open(r1, b"aad", Bytes::from_array(tampered)), None)
  // Wrong AAD.
  let r2 = hpke_setup_base_receiver(config, enc, sk_r, b"info")
  assert_eq(hpke_open(r2, b"other aad", ct), None)
  // Wrong info (key schedule context).
  let r3 = hpke_setup_base_receiver(config, enc, sk_r, b"other info")
  assert_eq(hpke_open(r3, b"aad", ct), None)
}

///|
test "hpke_sequence_advances" {
  let config = hpke_default_config()
  let (sk_r, pk_r) = hpke_generate_keypair(hpke_seed(10))
  let (enc, sender) = hpke_setup_base_sender(config, pk_r, b"", hpke_seed(11))
  let ct1 = hpke_seal(sender, b"", b"first")
  let ct2 = hpke_seal(sender, b"", b"second")
  // Distinct nonces => distinct ciphertexts for distinct plaintexts,
  // and in-order open succeeds.
  let receiver = hpke_setup_base_receiver(config, enc, sk_r, b"")
  assert_eq(hpke_open(receiver, b"", ct1), Some(b"first"))
  assert_eq(hpke_open(receiver, b"", ct2), Some(b"second"))
  // Out-of-order delivery fails authentication (nonce mismatch).
  let receiver2 = hpke_setup_base_receiver(config, enc, sk_r, b"")
  assert_eq(hpke_open(receiver2, b"", ct2), None)
}

///|
test "hpke_export_matches_both_sides" {
  let config = hpke_default_config()
  let (sk_r, pk_r) = hpke_generate_keypair(hpke_seed(12))
  let (enc, sender) = hpke_setup_base_sender(
    config,
    pk_r,
    b"export test",
    hpke_seed(13),
  )
  let receiver = hpke_setup_base_receiver(config, enc, sk_r, b"export test")
  let s1 = hpke_export_sender(sender, 32, b"app-context")
  let s2 = hpke_export_receiver(receiver, 32, b"app-context")
  assert_eq(s1, s2)
  assert_eq(s1.length(), 32)
  // Different export context yields a different secret.
  let s3 = hpke_export_sender(sender, 32, b"other")
  assert_true(s1 != s3)
}

///|
fn hpke_sender_setup_fails(
  config : HpkeConfig,
  pk : Bytes,
  info : Bytes,
  seed : Bytes,
) -> Bool {
  let r = Some(hpke_setup_base_sender(config, pk, info, seed)) catch {
    _ => None
  }
  match r {
    Some(_) => false
    None => true
  }
}

///|
test "hpke_rejects_malformed_inputs" {
  let config = hpke_default_config()
  let (sk_r, pk_r) = hpke_generate_keypair(hpke_seed(14))
  assert_eq(hpke_sender_setup_fails(config, b"short", b"", hpke_seed(15)), true)
  let r2 = Some(
    hpke_setup_base_receiver(config, Bytes::make(10, b'\x00'), sk_r, b""),
  ) catch {
    _ => None
  }
  match r2 {
    Some(_) => fail("malformed enc accepted")
    None => ()
  }
  let bad = HpkeConfig::new(
    0xFFFF,
    HPKE_KDF_HKDF_SHA256,
    HPKE_AEAD_CHACHA20POLY1305,
  )
  assert_eq(hpke_sender_setup_fails(bad, pk_r, b"", hpke_seed(16)), true)
}
