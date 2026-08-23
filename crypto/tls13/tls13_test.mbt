/// Comprehensive tests for TLS 1.3 Protocol (RFC 8446).

///|
/// Helper: create a Bytes of repeated byte value.
fn make_bytes(val : Int, n : Int) -> Bytes {
  Bytes::from_array(Array::make(n, val.to_byte()))
}

// ===========================================================================
// ClientHello tests
// ===========================================================================

///|
test "tls_client_hello: basic structure" {
  let random = make_bytes(0x42, 32)
  let key_share = Bytes::from_array([0x01, 0x02, 0x03, 0x04])
  let hello = tls_client_hello(
    random,
    [TlsCipherSuite::aes128_gcm_sha256()],
    key_share,
  )
  // Version 0x0304
  assert_eq(hello[0].to_int(), 0x03)
  assert_eq(hello[1].to_int(), 0x04)
  // 32 bytes of random
  for i = 0; i < 32; i = i + 1 {
    assert_eq(hello[2 + i].to_int(), 0x42)
  }
}

///|
test "tls_client_hello: multiple cipher suites" {
  let random = make_bytes(0x00, 32)
  let key_share = Bytes::from_array([])
  let hello = tls_client_hello(
    random,
    [
      TlsCipherSuite::aes128_gcm_sha256(),
      TlsCipherSuite::aes256_gcm_sha384(),
      TlsCipherSuite::chacha20_poly1305_sha256(),
    ],
    key_share,
  )
  // After version(2) + random(32) = 34 bytes, comes cipher suite count (2 bytes)
  let cs_count = (hello[34].to_int() << 8) | hello[35].to_int()
  assert_eq(cs_count, 3)
  // First cipher suite ID: AES_128_GCM_SHA256 = 0x1301
  let cs0 = (hello[36].to_int() << 8) | hello[37].to_int()
  assert_eq(cs0, 0x1301)
  let cs1 = (hello[38].to_int() << 8) | hello[39].to_int()
  assert_eq(cs1, 0x1302)
  let cs2 = (hello[40].to_int() << 8) | hello[41].to_int()
  assert_eq(cs2, 0x1303)
}

///|
test "tls_client_hello: short random is zero-padded" {
  let random = Bytes::from_array([0xFF])
  let key_share = Bytes::from_array([])
  let hello = tls_client_hello(
    random,
    [TlsCipherSuite::aes128_gcm_sha256()],
    key_share,
  )
  assert_eq(hello[2].to_int(), 0xFF)
}

///|
test "tls_client_hello: key share is included" {
  let random = make_bytes(0x00, 32)
  let key_share = Bytes::from_array([0xDE, 0xAD, 0xBE, 0xEF])
  let hello = tls_client_hello(
    random,
    [TlsCipherSuite::aes128_gcm_sha256()],
    key_share,
  )
  // Layout: version(2) + random(32) + cs_count(2) + cs(2) + ks_len(2) + ks_data
  let ks_len = (hello[38].to_int() << 8) | hello[39].to_int()
  assert_eq(ks_len, 4)
  assert_eq(hello[40].to_int(), 0xDE)
  assert_eq(hello[41].to_int(), 0xAD)
  assert_eq(hello[42].to_int(), 0xBE)
  assert_eq(hello[43].to_int(), 0xEF)
}

// ===========================================================================
// Key derivation tests
// ===========================================================================

///|
test "tls_derive_keys: produces 32-byte keys" {
  let shared = make_bytes(0x01, 32)
  let client_r = make_bytes(0x02, 32)
  let server_r = make_bytes(0x03, 32)
  let (ck, sk) = tls_derive_keys(shared, client_r, server_r)
  assert_eq(ck.length(), 32)
  assert_eq(sk.length(), 32)
}

///|
test "tls_derive_keys: different inputs produce different keys" {
  let shared = make_bytes(0x01, 32)
  let cr1 = make_bytes(0x02, 32)
  let cr2 = make_bytes(0x03, 32)
  let sr = make_bytes(0x04, 32)
  let (ck1, _) = tls_derive_keys(shared, cr1, sr)
  let (ck2, _) = tls_derive_keys(shared, cr2, sr)
  assert_true(ck1 != ck2)
}

///|
test "tls_derive_keys: client and server keys differ" {
  let shared = make_bytes(0xAA, 32)
  let cr = make_bytes(0xBB, 32)
  let sr = make_bytes(0xCC, 32)
  let (ck, sk) = tls_derive_keys(shared, cr, sr)
  assert_true(ck != sk)
}

///|
test "tls_derive_keys: deterministic with same inputs" {
  let shared = make_bytes(0x11, 32)
  let cr = make_bytes(0x22, 32)
  let sr = make_bytes(0x33, 32)
  let (ck1, sk1) = tls_derive_keys(shared, cr, sr)
  let (ck2, sk2) = tls_derive_keys(shared, cr, sr)
  assert_eq(ck1, ck2)
  assert_eq(sk1, sk2)
}

// ===========================================================================
// Record creation tests
// ===========================================================================

///|
test "tls_create_record: basic ApplicationData record" {
  let key = make_bytes(0x00, 16)
  let payload = Bytes::from_array([0x48, 0x49])
  let record = tls_create_record(
    TlsContentType::application_data(),
    payload,
    key,
    0,
  )
  assert_eq(record[0].to_int(), 23)
  assert_eq(record[1].to_int(), 0x03)
  assert_eq(record[2].to_int(), 0x04)
  let len = (record[3].to_int() << 8) | record[4].to_int()
  assert_eq(len, 2)
}

///|
test "tls_create_record: Handshake content type" {
  let key = make_bytes(0x00, 16)
  let payload = Bytes::from_array([0x01])
  let record = tls_create_record(TlsContentType::handshake(), payload, key, 0)
  assert_eq(record[0].to_int(), 22)
}

///|
test "tls_create_record: Alert content type" {
  let key = make_bytes(0x00, 16)
  let payload = Bytes::from_array([0x01, 0x00])
  let record = tls_create_record(TlsContentType::alert(), payload, key, 0)
  assert_eq(record[0].to_int(), 21)
}

///|
test "tls_create_record: ChangeCipherSpec content type" {
  let key = make_bytes(0x00, 16)
  let payload = Bytes::from_array([0x01])
  let record = tls_create_record(
    TlsContentType::change_cipher_spec(),
    payload,
    key,
    0,
  )
  assert_eq(record[0].to_int(), 20)
}

///|
test "tls_create_record: payload is encrypted (XOR with nonce)" {
  let key = make_bytes(0xFF, 16)
  let payload = Bytes::from_array([0x00, 0x00, 0x00, 0x00])
  let record = tls_create_record(
    TlsContentType::application_data(),
    payload,
    key,
    0,
  )
  assert_eq(record[5].to_int(), 0xFF)
}

///|
test "tls_create_record: different sequence numbers produce different ciphertext" {
  let key = make_bytes(0x00, 16)
  let payload = make_bytes(0x42, 17)
  let r1 = tls_create_record(
    TlsContentType::application_data(),
    payload,
    key,
    0,
  )
  let r2 = tls_create_record(
    TlsContentType::application_data(),
    payload,
    key,
    1,
  )
  assert_true(r1 != r2)
}

// ===========================================================================
// Record header parsing tests
// ===========================================================================

///|
test "tls_parse_record_header: valid header" {
  let key = make_bytes(0x00, 16)
  let payload = Bytes::from_array([0x01, 0x02, 0x03])
  let record = tls_create_record(
    TlsContentType::application_data(),
    payload,
    key,
    0,
  )
  let parsed = tls_parse_record_header(record)
  match parsed {
    Some((ct, ver, len)) => {
      assert_eq(ct, 23)
      assert_eq(ver, 0x0304)
      assert_eq(len, 3)
    }
    None => abort("expected Some")
  }
}

///|
test "tls_parse_record_header: too short returns None" {
  let data = Bytes::from_array([0x01, 0x02])
  assert_true(tls_parse_record_header(data) is None)
}

///|
test "tls_parse_record_header: empty data returns None" {
  let data = Bytes::from_array([])
  assert_true(tls_parse_record_header(data) is None)
}

///|
test "tls_parse_record_header: exactly 5 bytes" {
  let data = Bytes::from_array([22, 0x03, 0x04, 0x00, 0x10])
  let parsed = tls_parse_record_header(data)
  match parsed {
    Some((ct, ver, len)) => {
      assert_eq(ct, 22)
      assert_eq(ver, 0x0304)
      assert_eq(len, 16)
    }
    None => abort("expected Some")
  }
}

// ===========================================================================
// Round-trip: create + parse
// ===========================================================================

///|
test "tls_round_trip: create and parse header" {
  let key = make_bytes(0x42, 32)
  let payload = make_bytes(0x77, 100)
  let record = tls_create_record(TlsContentType::handshake(), payload, key, 7)
  let parsed = tls_parse_record_header(record)
  match parsed {
    Some((ct, ver, len)) => {
      assert_eq(ct, 22)
      assert_eq(ver, 0x0304)
      assert_eq(len, 100)
    }
    None => abort("expected Some")
  }
}
