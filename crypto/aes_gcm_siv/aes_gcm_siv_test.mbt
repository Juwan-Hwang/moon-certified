///|
/// AES-GCM-SIV (RFC 8452) white-box tests.
///
/// Tests: encrypt/decrypt roundtrip for various plaintext lengths and key
/// sizes, AEAD tamper/key/AAD/nonce mismatch detection (decrypt returns None),
/// short-ciphertext rejection, and nonce-reuse determinism.
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
test "aes_gcm_siv: encrypt-decrypt roundtrip (AES-128, 32-byte pt)" {
  let key = Bytes::make(16, b'\x42')
  let nonce = Bytes::make(12, b'\x01')
  let aad = Bytes::make(8, b'\xAA')
  let pt = Bytes::make(32, b'\x55')
  let ct = aes_gcm_siv_encrypt(key, nonce, aad, pt)
  assert_eq(ct.length(), 32 + 16)
  let decrypted = aes_gcm_siv_decrypt(key, nonce, aad, ct)
  assert_true(decrypted != None)
  assert_true(bytes_eq(decrypted.unwrap(), pt))
}

///|
test "aes_gcm_siv: empty plaintext roundtrip (AES-256)" {
  let key = Bytes::make(32, b'\x99')
  let nonce = Bytes::make(12, b'\x03')
  let aad = Bytes::make(4, b'\xFF')
  let pt = Bytes::make(0, b'\x00')
  let ct = aes_gcm_siv_encrypt(key, nonce, aad, pt)
  assert_eq(ct.length(), 16)
  let decrypted = aes_gcm_siv_decrypt(key, nonce, aad, ct)
  assert_true(decrypted != None)
  assert_eq(decrypted.unwrap().length(), 0)
}

///|
test "aes_gcm_siv: single byte plaintext" {
  let key = Bytes::make(16, b'\x11')
  let nonce = Bytes::make(12, b'\x02')
  let aad = Bytes::make(0, b'\x00')
  let pt = Bytes::make(1, b'\x07')
  let ct = aes_gcm_siv_encrypt(key, nonce, aad, pt)
  assert_eq(ct.length(), 17)
  let decrypted = aes_gcm_siv_decrypt(key, nonce, aad, ct)
  assert_true(decrypted != None)
  assert_true(bytes_eq(decrypted.unwrap(), pt))
}

///|
test "aes_gcm_siv: multi-block plaintext (48 bytes)" {
  let key = Bytes::make(32, b'\x22')
  let nonce = Bytes::make(12, b'\x04')
  let aad = Bytes::make(13, b'\xCC')
  let pt = Bytes::make(48, b'\xAB')
  let ct = aes_gcm_siv_encrypt(key, nonce, aad, pt)
  assert_eq(ct.length(), 48 + 16)
  let decrypted = aes_gcm_siv_decrypt(key, nonce, aad, ct)
  assert_true(decrypted != None)
  assert_true(bytes_eq(decrypted.unwrap(), pt))
}

///|
test "aes_gcm_siv: wrong key fails to decrypt" {
  let key = Bytes::make(16, b'\x42')
  let wrong_key = Bytes::make(16, b'\x43')
  let nonce = Bytes::make(12, b'\x01')
  let aad = Bytes::make(8, b'\xAA')
  let pt = Bytes::make(16, b'\x55')
  let ct = aes_gcm_siv_encrypt(key, nonce, aad, pt)
  let decrypted = aes_gcm_siv_decrypt(wrong_key, nonce, aad, ct)
  assert_true(decrypted == None)
}

///|
test "aes_gcm_siv: wrong aad fails to decrypt" {
  let key = Bytes::make(16, b'\x42')
  let nonce = Bytes::make(12, b'\x01')
  let aad = Bytes::make(8, b'\xAA')
  let wrong_aad = Bytes::make(8, b'\xAB')
  let pt = Bytes::make(16, b'\x55')
  let ct = aes_gcm_siv_encrypt(key, nonce, aad, pt)
  let decrypted = aes_gcm_siv_decrypt(key, nonce, wrong_aad, ct)
  assert_true(decrypted == None)
}

///|
test "aes_gcm_siv: wrong nonce fails to decrypt" {
  let key = Bytes::make(16, b'\x42')
  let nonce = Bytes::make(12, b'\x01')
  let wrong_nonce = Bytes::make(12, b'\x02')
  let aad = Bytes::make(8, b'\xAA')
  let pt = Bytes::make(16, b'\x55')
  let ct = aes_gcm_siv_encrypt(key, nonce, aad, pt)
  let decrypted = aes_gcm_siv_decrypt(key, wrong_nonce, aad, ct)
  assert_true(decrypted == None)
}

///|
test "aes_gcm_siv: tampered ciphertext (payload) fails" {
  let key = Bytes::make(16, b'\x42')
  let nonce = Bytes::make(12, b'\x01')
  let aad = Bytes::make(8, b'\xAA')
  let pt = Bytes::make(32, b'\x55')
  let ct = aes_gcm_siv_encrypt(key, nonce, aad, pt)
  // Flip a bit in the encrypted payload region (not the tag)
  let tampered : Array[Byte] = []
  for i = 0; i < ct.length(); i = i + 1 {
    if i == 0 {
      tampered.push((ct[i].to_int() ^ 0x01).to_byte())
    } else {
      tampered.push(ct[i])
    }
  }
  let decrypted = aes_gcm_siv_decrypt(
    key,
    nonce,
    aad,
    Bytes::from_array(tampered),
  )
  assert_true(decrypted == None)
}

///|
test "aes_gcm_siv: tampered tag fails" {
  let key = Bytes::make(16, b'\x42')
  let nonce = Bytes::make(12, b'\x01')
  let aad = Bytes::make(8, b'\xAA')
  let pt = Bytes::make(32, b'\x55')
  let ct = aes_gcm_siv_encrypt(key, nonce, aad, pt)
  let tampered : Array[Byte] = []
  for i = 0; i < ct.length(); i = i + 1 {
    if i == ct.length() - 1 {
      tampered.push((ct[i].to_int() ^ 0x01).to_byte())
    } else {
      tampered.push(ct[i])
    }
  }
  let decrypted = aes_gcm_siv_decrypt(
    key,
    nonce,
    aad,
    Bytes::from_array(tampered),
  )
  assert_true(decrypted == None)
}

///|
test "aes_gcm_siv: short ciphertext rejected" {
  let key = Bytes::make(16, b'\x42')
  let nonce = Bytes::make(12, b'\x01')
  let aad = Bytes::make(8, b'\xAA')
  let ct = Bytes::make(8, b'\x00')
  let decrypted = aes_gcm_siv_decrypt(key, nonce, aad, ct)
  assert_true(decrypted == None)
}

///|
test "aes_gcm_siv: nonce reuse is deterministic" {
  let key = Bytes::make(16, b'\x42')
  let nonce = Bytes::make(12, b'\x01')
  let aad = Bytes::make(8, b'\xAA')
  let pt = Bytes::make(32, b'\x55')
  let ct1 = aes_gcm_siv_encrypt(key, nonce, aad, pt)
  let ct2 = aes_gcm_siv_encrypt(key, nonce, aad, pt)
  // Nonce-misuse-resistant AEAD is deterministic for fixed (key, nonce, aad, pt)
  assert_true(bytes_eq(ct1, ct2))
}
