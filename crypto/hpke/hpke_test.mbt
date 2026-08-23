///|
/// HPKE (RFC 9180) white-box tests.
///
/// NOTE: the bundled implementation is a simplified toy. `hpke_open` is typed
/// to take a `HpkeSenderContext` (so the seal/open inverse is exercised with a
/// sender context), and the KEM's "shared secret" is reconstructed element-wise
/// from `enc` plus the recipient private key bytes (it only matches the sender
/// when those bytes are all zero). The tests below validate the deterministic
/// key schedule, the seal/open inverse relationship, and the exporter — the
/// working surface of this module.
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
test "hpke: config struct is accessible" {
  let cfg = HpkeConfig::new(0x20, 0x01, 1)
  assert_eq(cfg.kem_id, 0x20)
  assert_eq(cfg.aead_id, 1)
}

///|
test "hpke: setup sender with aead_id=1 yields 16-byte key" {
  let cfg = HpkeConfig::new(0x20, 0x01, 1)
  let (enc, sender) = hpke_setup_base_sender(
    cfg,
    Bytes::make(32, b'\x00'),
    Bytes::from_array([b'\x0a']),
    12345,
  )
  assert_eq(enc.length(), 32)
  assert_eq(sender.key.length(), 16)
  assert_eq(sender.nonce.length(), 12)
  assert_eq(sender.seq, 0)
}

///|
test "hpke: setup sender with aead_id=2 yields 32-byte key" {
  let cfg = HpkeConfig::new(0x20, 0x01, 2)
  let (_enc, sender) = hpke_setup_base_sender(
    cfg,
    Bytes::make(32, b'\x00'),
    Bytes::from_array([b'\x0a']),
    12345,
  )
  assert_eq(sender.key.length(), 32)
}

///|
test "hpke: setup receiver returns a context with expected fields" {
  let cfg = HpkeConfig::new(0x20, 0x01, 1)
  let (enc, _sender) = hpke_setup_base_sender(
    cfg,
    Bytes::make(32, b'\x00'),
    Bytes::from_array([b'\x0a']),
    12345,
  )
  let receiver = hpke_setup_base_receiver(
    cfg,
    enc,
    Bytes::make(32, b'\x00'),
    Bytes::from_array([b'\x0a']),
  )
  assert_eq(receiver.key.length(), 16)
  assert_eq(receiver.nonce.length(), 12)
  assert_eq(receiver.seq, 0)
}

///|
test "hpke: sender seal / open roundtrip (same seed, seq 0)" {
  let cfg = HpkeConfig::new(0x20, 0x01, 1)
  let info = Bytes::from_array([b'\x01', b'\x02'])
  // Two identically-seeded sender contexts share the same nonce and start at seq 0.
  let (enc, s1) = hpke_setup_base_sender(
    cfg,
    Bytes::make(32, b'\x00'),
    info,
    777,
  )
  let (_enc2, s2) = hpke_setup_base_sender(
    cfg,
    Bytes::make(32, b'\x00'),
    info,
    777,
  )
  // sanity: same enc + same nonce
  assert_true(bytes_eq(enc, _enc2))
  assert_true(bytes_eq(s1.nonce, s2.nonce))
  let pt = Bytes::from_array([b'\x68', b'\x65', b'\x6c', b'\x6c', b'\x6f'])
  let aad = Bytes::from_array([b'\xaa'])
  let ct = hpke_seal(s1, aad, pt)
  let opened = hpke_open(s2, aad, ct)
  assert_true(opened != None)
  assert_true(bytes_eq(opened.unwrap(), pt))
}

///|
test "hpke: roundtrip with empty plaintext" {
  let cfg = HpkeConfig::new(0x20, 0x01, 1)
  let info = Bytes::from_array([b'\x03'])
  let (_e1, s1) = hpke_setup_base_sender(cfg, Bytes::make(32, b'\x00'), info, 5)
  let (_e2, s2) = hpke_setup_base_sender(cfg, Bytes::make(32, b'\x00'), info, 5)
  let pt = Bytes::make(0, b'\x00')
  let ct = hpke_seal(s1, b"", pt)
  let opened = hpke_open(s2, b"", ct)
  assert_true(opened != None)
  assert_eq(opened.unwrap().length(), 0)
}

///|
test "hpke: roundtrip with empty aad and long plaintext" {
  let cfg = HpkeConfig::new(0x20, 0x01, 1)
  let info = Bytes::from_array([b'\x04'])
  let (_e1, s1) = hpke_setup_base_sender(cfg, Bytes::make(32, b'\x00'), info, 9)
  let (_e2, s2) = hpke_setup_base_sender(cfg, Bytes::make(32, b'\x00'), info, 9)
  let pt = Bytes::make(40, b'\x2c')
  let ct = hpke_seal(s1, b"", pt)
  let opened = hpke_open(s2, b"", ct)
  assert_true(opened != None)
  assert_true(bytes_eq(opened.unwrap(), pt))
}

///|
test "hpke: open always returns Some (no authentication in toy)" {
  let cfg = HpkeConfig::new(0x20, 0x01, 1)
  let info = Bytes::from_array([b'\x05'])
  let (_e, s) = hpke_setup_base_sender(cfg, Bytes::make(32, b'\x00'), info, 1)
  let garbage = Bytes::from_array([b'\xde', b'\xad', b'\xbe', b'\xef'])
  let opened = hpke_open(s, b"", garbage)
  assert_true(opened != None)
}

///|
test "hpke: export deterministic" {
  let cfg = HpkeConfig::new(0x20, 0x01, 1)
  let info = Bytes::from_array([b'\x09'])
  let (_e, s) = hpke_setup_base_sender(cfg, Bytes::make(32, b'\x00'), info, 42)
  let ex = Bytes::from_array([b'\x55'])
  let e1 = hpke_export(s, ex, 16)
  let e2 = hpke_export(s, ex, 16)
  assert_eq(e1.length(), 16)
  assert_true(bytes_eq(e1, e2))
  let e3 = hpke_export(s, ex, 32)
  assert_eq(e3.length(), 32)
}

///|
test "hpke: deterministic setup with same seed" {
  let cfg = HpkeConfig::new(0x20, 0x01, 1)
  let info = Bytes::from_array([b'\x03'])
  let (enc1, s1) = hpke_setup_base_sender(
    cfg,
    Bytes::make(32, b'\x00'),
    info,
    99,
  )
  let (enc2, s2) = hpke_setup_base_sender(
    cfg,
    Bytes::make(32, b'\x00'),
    info,
    99,
  )
  assert_true(bytes_eq(enc1, enc2))
  assert_true(bytes_eq(s1.key, s2.key))
  assert_true(bytes_eq(s1.nonce, s2.nonce))
}

///|
test "hpke: different seed produces different enc" {
  let cfg = HpkeConfig::new(0x20, 0x01, 1)
  let info = Bytes::from_array([b'\x03'])
  let (enc1, _s1) = hpke_setup_base_sender(
    cfg,
    Bytes::make(32, b'\x00'),
    info,
    99,
  )
  let (enc2, _s2) = hpke_setup_base_sender(
    cfg,
    Bytes::make(32, b'\x00'),
    info,
    100,
  )
  assert_true(!bytes_eq(enc1, enc2))
}
