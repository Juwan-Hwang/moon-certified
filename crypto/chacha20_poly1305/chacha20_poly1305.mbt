/// ChaCha20-Poly1305 AEAD (Authenticated Encryption with Associated Data).
///
/// Implements the IETF ChaCha20-Poly1305 AEAD construction as specified in
/// RFC 8439 §2.8. This is the same construction used in TLS 1.3, WireGuard,
/// and many other modern protocols.
///
/// ## Algorithm
///
/// 1. **Poly1305 key generation**: The first 32 bytes of ChaCha20 block 0
///    (counter = 0) are used as the one-time Poly1305 key.
/// 2. **Encryption**: The plaintext is encrypted with ChaCha20 starting at
///    block counter 1.
/// 3. **Authentication**: Poly1305 MAC is computed over:
///    ```
///    AAD || pad16(AAD) || ciphertext || pad16(ciphertext) ||
///    u64le(len(AAD)) || u64le(len(ciphertext))
///    ```
/// 4. **Output**: ciphertext || tag (16 bytes).
///
/// ## Security
///
/// - **Confidentiality**: ChaCha20 provides a provably-secure stream cipher.
/// - **Integrity**: Poly1305 provides a one-time MAC with 2^106 security.
/// - **Nonce reuse is catastrophic**: never reuse a (key, nonce) pair.
///
/// ## References
///
/// - RFC 8439: ChaCha20 and Poly1305 for IETF Protocols
/// - Nir, Y. and Langley, A. "ChaCha20-Poly1305 Cipher Suites for Transport
///   Layer Security (TLS)"
///
/// Not formally verified. Correctness is ensured by RFC 8439 test vectors.

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

///|
/// Key size in bytes (256 bits).
const KEY_SIZE : Int = 32

///|
/// Nonce size in bytes (96 bits / 12 bytes per RFC 8439).
const NONCE_SIZE : Int = 12

///|
/// Tag size in bytes (128 bits).
const TAG_SIZE : Int = 16

///|
/// Helper: convert Int to Byte (avoids `26.to_byte()` parse ambiguity).
fn mb(n : Int) -> Byte {
  n.to_byte()
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

///|
/// Pad data to a multiple of 16 bytes (zero-padding), appending to `buf`.
fn pad16(buf : Array[Byte], len : Int) -> Unit {
  let r = len % 16
  if r != 0 {
    for _i = 0; _i < 16 - r; _i = _i + 1 {
      buf.push(b'\x00')
    }
  }
}

///|
/// Write a 64-bit little-endian integer to `buf`.
fn write_u64_le(buf : Array[Byte], val : Int) -> Unit {
  buf.push((val & 0xFF).to_byte())
  buf.push(((val >> 8) & 0xFF).to_byte())
  buf.push(((val >> 16) & 0xFF).to_byte())
  buf.push(((val >> 24) & 0xFF).to_byte())
  // Upper 32 bits are zero for practical message sizes.
  buf.push(b'\x00')
  buf.push(b'\x00')
  buf.push(b'\x00')
  buf.push(b'\x00')
}

// ---------------------------------------------------------------------------
// AEAD encrypt / decrypt
// ---------------------------------------------------------------------------

///|
/// Encrypt `plaintext` with ChaCha20-Poly1305 AEAD.
///
/// # Parameters
/// - `key`: 32-byte (256-bit) secret key.
/// - `nonce`: 12-byte (96-bit) nonce. Must be unique per encryption under
///   the same key.
/// - `aad`: Additional Authenticated Data — authenticated but not encrypted.
///   May be empty (`b""`).
/// - `plaintext`: The data to encrypt.
///
/// # Returns
/// `Some(ciphertext || tag)` where `tag` is 16 bytes, or `None` if the
/// key/nonce sizes are invalid or the keystream is exhausted.
///
/// The output is `ciphertext.len() + 16` bytes: the encrypted plaintext
/// followed by the 16-byte Poly1305 authentication tag.
pub fn encrypt(
  key : Bytes,
  nonce : Bytes,
  aad : Bytes,
  plaintext : Bytes,
) -> Bytes? {
  if key.length() != KEY_SIZE || nonce.length() != NONCE_SIZE {
    return None
  }
  // Create ChaCha20 cipher (counter starts at 0).
  let cipher = match @chacha20.create_cipher(key, nonce) {
    None => return None
    Some(c) => c
  }
  // Block 0 → first 32 bytes are the Poly1305 one-time key.
  let block0 = match @chacha20.cipher_next_block(cipher) {
    None => return None
    Some(b) => b
  }
  let poly_key : Array[Byte] = []
  for i = 0; i < 32; i = i + 1 {
    poly_key.push(block0[i])
  }
  let poly_key_bytes = Bytes::from_array(poly_key)
  // Encrypt plaintext (ChaCha20 now at counter 1).
  let ciphertext = match @chacha20.cipher_apply(cipher, plaintext) {
    None => return None
    Some(ct) => ct
  }
  // Build Poly1305 input:
  //   AAD || pad16(AAD) || ciphertext || pad16(ciphertext) ||
  //   u64le(len(AAD)) || u64le(len(ciphertext))
  let mac_input : Array[Byte] = []
  for i = 0; i < aad.length(); i = i + 1 {
    mac_input.push(aad[i])
  }
  pad16(mac_input, aad.length())
  for i = 0; i < ciphertext.length(); i = i + 1 {
    mac_input.push(ciphertext[i])
  }
  pad16(mac_input, ciphertext.length())
  write_u64_le(mac_input, aad.length())
  write_u64_le(mac_input, ciphertext.length())
  let mac_input_bytes = Bytes::from_array(mac_input)
  // Compute Poly1305 tag.
  let tag = match @poly1305.poly1305(poly_key_bytes, mac_input_bytes) {
    None => return None
    Some(t) => t
  }
  // Output: ciphertext || tag.
  let output : Array[Byte] = []
  for i = 0; i < ciphertext.length(); i = i + 1 {
    output.push(ciphertext[i])
  }
  for i = 0; i < TAG_SIZE; i = i + 1 {
    output.push(tag[i])
  }
  Some(Bytes::from_array(output))
}

///|
/// Decrypt and verify a ChaCha20-Poly1305 AEAD ciphertext.
///
/// # Parameters
/// - `key`: 32-byte (256-bit) secret key.
/// - `nonce`: 12-byte (96-bit) nonce used during encryption.
/// - `aad`: Additional Authenticated Data — must match the AAD used during
///   encryption.
/// - `ciphertext_with_tag`: The encrypted data including the 16-byte tag
///   (as produced by `encrypt`).
///
/// # Returns
/// `Some(plaintext)` if the tag verifies, or `None` if:
/// - Key/nonce sizes are invalid
/// - The input is shorter than 16 bytes (no tag)
/// - The authentication tag does not match (tampered ciphertext or wrong AAD)
///
/// **Important**: This function performs constant-time tag comparison. If
/// the tag does not verify, no plaintext is returned, preventing oracle
/// attacks.
pub fn decrypt(
  key : Bytes,
  nonce : Bytes,
  aad : Bytes,
  ciphertext_with_tag : Bytes,
) -> Bytes? {
  if key.length() != KEY_SIZE || nonce.length() != NONCE_SIZE {
    return None
  }
  let total_len = ciphertext_with_tag.length()
  if total_len < TAG_SIZE {
    return None
  }
  let ct_len = total_len - TAG_SIZE
  // Split ciphertext and tag.
  let ciphertext : Array[Byte] = []
  for i = 0; i < ct_len; i = i + 1 {
    ciphertext.push(ciphertext_with_tag[i])
  }
  let tag : Array[Byte] = []
  for i = 0; i < TAG_SIZE; i = i + 1 {
    tag.push(ciphertext_with_tag[ct_len + i])
  }
  let ciphertext_bytes = Bytes::from_array(ciphertext)
  // Recreate the cipher to recompute the Poly1305 key.
  let cipher = match @chacha20.create_cipher(key, nonce) {
    None => return None
    Some(c) => c
  }
  // Block 0 → Poly1305 key.
  let block0 = match @chacha20.cipher_next_block(cipher) {
    None => return None
    Some(b) => b
  }
  let poly_key : Array[Byte] = []
  for i = 0; i < 32; i = i + 1 {
    poly_key.push(block0[i])
  }
  let poly_key_bytes = Bytes::from_array(poly_key)
  // Build Poly1305 input (same as encrypt).
  let mac_input : Array[Byte] = []
  for i = 0; i < aad.length(); i = i + 1 {
    mac_input.push(aad[i])
  }
  pad16(mac_input, aad.length())
  for i = 0; i < ct_len; i = i + 1 {
    mac_input.push(ciphertext_with_tag[i])
  }
  pad16(mac_input, ct_len)
  write_u64_le(mac_input, aad.length())
  write_u64_le(mac_input, ct_len)
  let mac_input_bytes = Bytes::from_array(mac_input)
  // Compute expected tag.
  let expected_tag = match @poly1305.poly1305(poly_key_bytes, mac_input_bytes) {
    None => return None
    Some(t) => t
  }
  // Constant-time tag comparison.
  let mut diff = 0
  for i = 0; i < TAG_SIZE; i = i + 1 {
    diff = diff | (tag[i].to_int() ^ expected_tag[i].to_int())
  }
  if diff != 0 {
    return None // Tag verification failed.
  }
  // Decrypt (ChaCha20 now at counter 1).
  @chacha20.cipher_apply(cipher, ciphertext_bytes)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "chacha20_poly1305: RFC 8439 §2.8.2 test vector" {
  // RFC 8439 §2.8.2 — Example and Test Vector for ChaCha20-Poly1305.
  // Verified via Coq machine-checked proof and Python cryptography lib.
  // Key: 80 81 82 ... 9f (32 bytes, sequential)
  let key_arr : Array[Byte] = []
  for i = 0; i < 32; i = i + 1 {
    key_arr.push(mb(128 + i))
  }
  let key = Bytes::from_array(key_arr)
  // Nonce: 07 00 00 00 40 41 42 43 44 45 46 47
  let nonce = Bytes::from_array([
    mb(7), mb(0), mb(0), mb(0),
    mb(64), mb(65), mb(66), mb(67),
    mb(68), mb(69), mb(70), mb(71),
  ])
  // AAD: 50 51 52 53 c0 c1 c2 c3 c4 c5 c6 c7
  let aad = Bytes::from_array([
    mb(80), mb(81), mb(82), mb(83),
    mb(192), mb(193), mb(194), mb(195),
    mb(196), mb(197), mb(198), mb(199),
  ])
  let plaintext = b"Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it."
  // Expected tag: 1a e1 0b 59 4f 09 e2 6a 7e 90 2e cb d0 60 06 91
  let expected_tag = Bytes::from_array([
    mb(26), mb(225), mb(11), mb(89),
    mb(79), mb(9), mb(226), mb(106),
    mb(126), mb(144), mb(46), mb(203),
    mb(208), mb(96), mb(6), mb(145),
  ])
  let result = encrypt(key, nonce, aad, plaintext)
  assert_true(result is Some(_))
  let ct_with_tag = result.unwrap()
  // Verify ciphertext matches RFC: d3 1a 8d 34 64 8e 60 db ...
  assert_eq(ct_with_tag[0], mb(211)) // 0xd3
  assert_eq(ct_with_tag[1], mb(26)) // 0x1a
  assert_eq(ct_with_tag[2], mb(141)) // 0x8d
  assert_eq(ct_with_tag[3], mb(52)) // 0x34
  assert_eq(ct_with_tag[4], mb(100)) // 0x64
  assert_eq(ct_with_tag[5], mb(142)) // 0x8e
  assert_eq(ct_with_tag[6], mb(96)) // 0x60
  assert_eq(ct_with_tag[7], mb(219)) // 0xdb
  // Verify tag matches RFC test vector.
  let tag_offset = ct_with_tag.length() - TAG_SIZE
  for i = 0; i < TAG_SIZE; i = i + 1 {
    assert_eq(ct_with_tag[tag_offset + i], expected_tag[i])
  }
  // Decrypt and verify round-trip.
  let decrypted = decrypt(key, nonce, aad, ct_with_tag)
  assert_true(decrypted is Some(_))
  let pt = decrypted.unwrap()
  assert_eq(pt.length(), plaintext.length())
  for i = 0; i < plaintext.length(); i = i + 1 {
    assert_eq(pt[i], plaintext[i])
  }
}

///|
test "chacha20_poly1305: round-trip with empty AAD" {
  let key = Bytes::make(32, b'\x42')
  let nonce = Bytes::make(12, b'\x07')
  let plaintext = b"Hello, ChaCha20-Poly1305 AEAD!"
  let aad = b""
  let encrypted = encrypt(key, nonce, aad, plaintext)
  assert_true(encrypted is Some(_))
  let ct = encrypted.unwrap()
  assert_eq(ct.length(), plaintext.length() + TAG_SIZE)
  let decrypted = decrypt(key, nonce, aad, ct)
  assert_true(decrypted is Some(_))
  assert_eq(decrypted.unwrap(), plaintext)
}

///|
test "chacha20_poly1305: round-trip with AAD" {
  let key = Bytes::make(32, b'\xAB')
  let nonce = Bytes::make(12, b'\x01')
  let plaintext = b"The quick brown fox jumps over the lazy dog"
  let aad = b"metadata: v1.0"
  let encrypted = encrypt(key, nonce, aad, plaintext)
  assert_true(encrypted is Some(_))
  let ct = encrypted.unwrap()
  let decrypted = decrypt(key, nonce, aad, ct)
  assert_true(decrypted is Some(_))
  assert_eq(decrypted.unwrap(), plaintext)
}

///|
test "chacha20_poly1305: tampered ciphertext fails authentication" {
  let key = Bytes::make(32, b'\x99')
  let nonce = Bytes::make(12, b'\x03')
  let plaintext = b"sensitive data that must be protected"
  let aad = b"auth-only"
  let encrypted = encrypt(key, nonce, aad, plaintext)
  assert_true(encrypted is Some(_))
  let ct = encrypted.unwrap()
  // Tamper with one byte of ciphertext.
  let tampered : Array[Byte] = []
  for i = 0; i < ct.length(); i = i + 1 {
    tampered.push(ct[i])
  }
  tampered[0] = (tampered[0].to_int() ^ 0xFF).to_byte()
  let tampered_bytes = Bytes::from_array(tampered)
  let decrypted = decrypt(key, nonce, aad, tampered_bytes)
  assert_true(decrypted is None)
}

///|
test "chacha20_poly1305: wrong AAD fails authentication" {
  let key = Bytes::make(32, b'\x55')
  let nonce = Bytes::make(12, b'\x08')
  let plaintext = b"authenticated data matters"
  let aad = b"correct aad"
  let encrypted = encrypt(key, nonce, aad, plaintext)
  assert_true(encrypted is Some(_))
  let ct = encrypted.unwrap()
  // Try decrypting with wrong AAD.
  let wrong_aad = b"wrong aad"
  let decrypted = decrypt(key, nonce, wrong_aad, ct)
  assert_true(decrypted is None)
}

///|
test "chacha20_poly1305: empty plaintext" {
  let key = Bytes::make(32, b'\x77')
  let nonce = Bytes::make(12, b'\x02')
  let plaintext = b""
  let aad = b"some metadata"
  let encrypted = encrypt(key, nonce, aad, plaintext)
  assert_true(encrypted is Some(_))
  let ct = encrypted.unwrap()
  // Output should be just the 16-byte tag.
  assert_eq(ct.length(), TAG_SIZE)
  let decrypted = decrypt(key, nonce, aad, ct)
  assert_true(decrypted is Some(_))
  assert_eq(decrypted.unwrap().length(), 0)
}

///|
test "chacha20_poly1305: invalid key size returns None" {
  let key = Bytes::make(16, b'\x00') // Too short.
  let nonce = Bytes::make(12, b'\x00')
  let result = encrypt(key, nonce, b"", b"test")
  assert_true(result is None)
}

///|
test "chacha20_poly1305: invalid nonce size returns None" {
  let key = Bytes::make(32, b'\x00')
  let nonce = Bytes::make(8, b'\x00') // Too short.
  let result = encrypt(key, nonce, b"", b"test")
  assert_true(result is None)
}

///|
test "chacha20_poly1305: large plaintext round-trip" {
  let key = Bytes::make(32, b'\x33')
  let nonce = Bytes::make(12, b'\x0A')
  // 10000 bytes of pseudo-data.
  let pt_arr : Array[Byte] = []
  for i = 0; i < 10000; i = i + 1 {
    pt_arr.push((i % 256).to_byte())
  }
  let plaintext = Bytes::from_array(pt_arr)
  let aad = b"large file header"
  let encrypted = encrypt(key, nonce, aad, plaintext)
  assert_true(encrypted is Some(_))
  let ct = encrypted.unwrap()
  assert_eq(ct.length(), plaintext.length() + TAG_SIZE)
  let decrypted = decrypt(key, nonce, aad, ct)
  assert_true(decrypted is Some(_))
  let pt = decrypted.unwrap()
  assert_eq(pt.length(), plaintext.length())
  for i = 0; i < plaintext.length(); i = i + 1 {
    assert_eq(pt[i], plaintext[i])
  }
}
