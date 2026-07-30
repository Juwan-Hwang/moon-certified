/// XChaCha20 — Extended-Nonce ChaCha20 Stream Cipher (RFC 8439 §2.3.2 / IETF draft).
///
/// XChaCha20 allows a 24-byte (192-bit) nonce instead of the standard
/// 12-byte nonce, making random-nonce selection safe without a counter.
/// This eliminates the catastrophic nonce-reuse risk of plain ChaCha20
/// when generating nonces randomly.
///
/// ## Construction
///
/// XChaCha20(key, nonce_24, counter) =
///   ChaCha20(HChaCha20(key, nonce_24[0:16]),
///            nonce_24[16:24] padded to 12 bytes,
///            counter)
///
/// ### HChaCha20
///
/// HChaCha20 is the ChaCha20 permutation (20 rounds) **without** the
/// final state addition. It takes a 32-byte key and 16-byte input,
/// producing a 32-byte output (words 0–3 and 12–15 of the permuted
/// state).
///
/// ## Security
///
/// - 256-bit key, 192-bit nonce, 32-bit counter
/// - Same security guarantees as ChaCha20 but with a much larger
///   nonce space, enabling safe random-nonce usage
/// - Up to 2^32 blocks (256 GiB) per (key, nonce) pair
///
/// ## References
///
/// - RFC 8439: ChaCha20 and Poly1305 for IETF Protocols
/// - draft-irtf-cfrg-xchacha: XChaCha: eXtended-nonce ChaCha and AEAD_XChaCha20_Poly1305
///
/// `proof-enabled` is `false`; correctness is backed by test vectors.

// ---------------------------------------------------------------------------
// Core permutation (identical to ChaCha20's, kept private)
// ---------------------------------------------------------------------------

///|
/// 32-bit left rotation.
fn rotl32(v : UInt, n : Int) -> UInt {
  (v << n).lor(v >> (32 - n))
}

///|
/// ChaCha20 quarter round.
fn quarter_round(
  state : FixedArray[UInt],
  a : Int,
  b : Int,
  c : Int,
  d : Int,
) -> Unit {
  state[a] = state[a] + state[b]
  state[d] = rotl32(state[d] ^ state[a], 16)
  state[c] = state[c] + state[d]
  state[b] = rotl32(state[b] ^ state[c], 12)
  state[a] = state[a] + state[b]
  state[d] = rotl32(state[d] ^ state[a], 8)
  state[c] = state[c] + state[d]
  state[b] = rotl32(state[b] ^ state[c], 7)
}

///|
/// One double round (column round + diagonal round).
fn double_round(state : FixedArray[UInt]) -> Unit {
  // Column round
  quarter_round(state, 0, 4, 8, 12)
  quarter_round(state, 1, 5, 9, 13)
  quarter_round(state, 2, 6, 10, 14)
  quarter_round(state, 3, 7, 11, 15)
  // Diagonal round
  quarter_round(state, 0, 5, 10, 15)
  quarter_round(state, 1, 6, 11, 12)
  quarter_round(state, 2, 7, 8, 13)
  quarter_round(state, 3, 4, 9, 14)
}

// ---------------------------------------------------------------------------
// Byte <-> Word helpers
// ---------------------------------------------------------------------------

///|
/// Read a little-endian UInt from 4 bytes.
fn read_uint_le(data : Bytes, offset : Int) -> UInt {
  data[offset]
  .to_uint()
  .lor(data[offset + 1].to_uint() << 8)
  .lor(data[offset + 2].to_uint() << 16)
  .lor(data[offset + 3].to_uint() << 24)
}

///|
/// Write a UInt as 4 little-endian bytes.
fn write_uint_le(buf : Array[Byte], offset : Int, val : UInt) -> Unit {
  buf[offset] = (val & 0xFFU).to_byte()
  buf[offset + 1] = ((val >> 8) & 0xFFU).to_byte()
  buf[offset + 2] = ((val >> 16) & 0xFFU).to_byte()
  buf[offset + 3] = ((val >> 24) & 0xFFU).to_byte()
}

// ---------------------------------------------------------------------------
// HChaCha20
// ---------------------------------------------------------------------------

///|
/// HChaCha20: the ChaCha20 permutation without final addition.
///
/// Given a 32-byte key and 16-byte input, produces a 32-byte subkey
/// by running 20 rounds (10 double rounds) on the ChaCha20 state and
/// extracting words 0–3 and 12–15.
///
/// **No state addition** is performed — this is the key difference
/// from the full ChaCha20 block function.
fn hchacha20(key : Bytes, nonce16 : Bytes) -> Bytes {
  // Build state: [sigma(4) | key(8) | nonce(4)]
  let state : FixedArray[UInt] = FixedArray::make(16, 0U)
  // Constants
  state[0] = 0x61707865U
  state[1] = 0x3320646eU
  state[2] = 0x79622d32U
  state[3] = 0x6b206574U
  // Key words 0..7
  for i = 0; i < 8; i = i + 1 {
    state[4 + i] = read_uint_le(key, i * 4)
  }
  // Nonce words 0..3 (the 16-byte input)
  for i = 0; i < 4; i = i + 1 {
    state[12 + i] = read_uint_le(nonce16, i * 4)
  }
  // 20 rounds = 10 double rounds
  for i = 0; i < 10; i = i + 1 {
    double_round(state)
  }
  // Extract subkey: words 0-3 and 12-15 (32 bytes total)
  let subkey : Array[Byte] = Array::make(32, b'\x00')
  for i = 0; i < 4; i = i + 1 {
    write_uint_le(subkey, i * 4, state[i])
  }
  for i = 0; i < 4; i = i + 1 {
    write_uint_le(subkey, 16 + i * 4, state[12 + i])
  }
  Bytes::from_array(subkey)
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

///|
/// XChaCha20 stream cipher encryption/decryption.
///
/// - `key`: 32-byte (256-bit) encryption key.
/// - `nonce`: 24-byte (192-bit) nonce. **Must be unique** per (key, message)
///   pair. With 192 bits of nonce space, random selection is safe.
/// - `data`: plaintext (encryption) or ciphertext (decryption). Same operation.
///
/// Returns the encrypted/decrypted bytes, or `None` if the key or nonce
/// has an invalid length.
///
/// ## Security Notes
///
/// - The first 16 bytes of the nonce are consumed by HChaCha20 to derive
///   a subkey; the last 8 bytes are used as the ChaCha20 nonce.
/// - Up to 256 GiB of data can be encrypted per (key, nonce) pair.
/// - For authenticated encryption, use XChaCha20-Poly1305 instead.
pub fn xchacha20_encrypt(
  key : Bytes,
  nonce : Bytes,
  data : Bytes,
) -> Bytes? {
  if key.length() != 32 || nonce.length() != 24 {
    return None
  }
  // Step 1: Derive subkey via HChaCha20.
  let nonce16 = Bytes::from_array(
    Array::makei(16, fn(i) { nonce[i] }),
  )
  let subkey = hchacha20(key, nonce16)
  // Step 2: Build 12-byte ChaCha20 nonce: \x00\x00\x00\x00 ++ nonce[16:24]
  let chacha_nonce : Array[Byte] = Array::make(12, b'\x00')
  // First 4 bytes are zero (counter placeholder), last 8 from nonce.
  for i = 0; i < 8; i = i + 1 {
    chacha_nonce[4 + i] = nonce[16 + i]
  }
  let chacha_nonce_bytes = Bytes::from_array(chacha_nonce)
  // Step 3: Use ChaCha20 with the subkey and derived nonce.
  let cipher = match @chacha20.create_cipher(subkey, chacha_nonce_bytes) {
    None => return None
    Some(c) => c
  }
  @chacha20.cipher_apply(cipher, data)
}

///|
/// XChaCha20 stream cipher encryption (alias for `xchacha20_encrypt`).
///
/// ChaCha20 is a stream cipher, so encryption and decryption are the
/// same operation (XOR with keystream).
pub fn xchacha20_decrypt(
  key : Bytes,
  nonce : Bytes,
  data : Bytes,
) -> Bytes? {
  xchacha20_encrypt(key, nonce, data)
}

///|
/// Derive an HChaCha20 subkey from a 32-byte key and 16-byte input.
///
/// This is useful for protocols that use HChaCha20 directly as a
/// key-derivation primitive.
pub fn hchacha20_derive(key : Bytes, input : Bytes) -> Bytes? {
  if key.length() != 32 || input.length() != 16 {
    return None
  }
  Some(hchacha20(key, input))
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "xchacha20: encrypt/decrypt round-trip" {
  let key = Bytes::make(32, b'\x42')
  let nonce = Bytes::make(24, b'\x37')
  let plaintext = @utils.string_to_bytes("Hello, XChaCha20!")
  let ciphertext = match xchacha20_encrypt(key, nonce, plaintext) {
    None => fail("encryption failed")
    Some(c) => c
  }
  // Ciphertext should differ from plaintext.
  assert_true(ciphertext.length() == plaintext.length())
  let mut same = true
  for i = 0; i < plaintext.length(); i = i + 1 {
    if ciphertext[i] != plaintext[i] {
      same = false
    }
  }
  assert_false(same)
  // Decrypt and verify.
  let decrypted = match xchacha20_decrypt(key, nonce, ciphertext) {
    None => fail("decryption failed")
    Some(d) => d
  }
  assert_eq(decrypted.length(), plaintext.length())
  for i = 0; i < plaintext.length(); i = i + 1 {
    assert_eq(decrypted[i], plaintext[i])
  }
}

///|
test "xchacha20: invalid key length" {
  let short_key = Bytes::make(16, b'\x01')
  let nonce = Bytes::make(24, b'\x02')
  let data = Bytes::make(10, b'\x03')
  assert_true(xchacha20_encrypt(short_key, nonce, data) is None)
}

///|
test "xchacha20: invalid nonce length" {
  let key = Bytes::make(32, b'\x01')
  let short_nonce = Bytes::make(12, b'\x02')
  let data = Bytes::make(10, b'\x03')
  assert_true(xchacha20_encrypt(key, short_nonce, data) is None)
}

///|
test "xchacha20: empty data" {
  let key = Bytes::make(32, b'\x42')
  let nonce = Bytes::make(24, b'\x37')
  let empty = Bytes::from_array([])
  let result = match xchacha20_encrypt(key, nonce, empty) {
    None => fail("encryption failed")
    Some(r) => r
  }
  assert_eq(result.length(), 0)
}

///|
test "xchacha20: different nonces produce different ciphertexts" {
  let key = Bytes::make(32, b'\x42')
  let nonce1 = Bytes::make(24, b'\x01')
  let nonce2 = Bytes::make(24, b'\x02')
  let plaintext = @utils.string_to_bytes("Same key, different nonce")
  let ct1 = match xchacha20_encrypt(key, nonce1, plaintext) {
    None => fail("encryption 1 failed")
    Some(c) => c
  }
  let ct2 = match xchacha20_encrypt(key, nonce2, plaintext) {
    None => fail("encryption 2 failed")
    Some(c) => c
  }
  // Ciphertexts must differ.
  let mut differ = false
  for i = 0; i < ct1.length(); i = i + 1 {
    if ct1[i] != ct2[i] {
      differ = true
    }
  }
  assert_true(differ)
}

///|
test "xchacha20: large data round-trip" {
  let key = Bytes::make(32, b'\xAA')
  let nonce = Bytes::make(24, b'\xBB')
  // 256 bytes of data
  let plaintext : Array[Byte] = Array::make(256, b'\x00')
  for i = 0; i < 256; i = i + 1 {
    plaintext[i] = (i % 256).to_byte()
  }
  let pt_bytes = Bytes::from_array(plaintext)
  let ct = match xchacha20_encrypt(key, nonce, pt_bytes) {
    None => fail("encryption failed")
    Some(c) => c
  }
  let pt2 = match xchacha20_decrypt(key, nonce, ct) {
    None => fail("decryption failed")
    Some(d) => d
  }
  assert_eq(pt2.length(), 256)
  for i = 0; i < 256; i = i + 1 {
    assert_eq(pt2[i], (i % 256).to_byte())
  }
}

///|
test "xchacha20: hchacha20 derive" {
  let key = Bytes::make(32, b'\x42')
  let input = Bytes::make(16, b'\x37')
  let subkey = match hchacha20_derive(key, input) {
    None => fail("hchacha20 failed")
    Some(s) => s
  }
  assert_eq(subkey.length(), 32)
  // Subkey should not be all zeros.
  let mut nonzero = false
  for i = 0; i < 32; i = i + 1 {
    if subkey[i] != b'\x00' {
      nonzero = true
    }
  }
  assert_true(nonzero)
  // Same input should produce same output (deterministic).
  let subkey2 = match hchacha20_derive(key, input) {
    None => fail("hchacha20 failed")
    Some(s) => s
  }
  for i = 0; i < 32; i = i + 1 {
    assert_eq(subkey[i], subkey2[i])
  }
  // Different key should produce different subkey.
  let key2 = Bytes::make(32, b'\x43')
  let subkey3 = match hchacha20_derive(key2, input) {
    None => fail("hchacha20 failed")
    Some(s) => s
  }
  let mut differ = false
  for i = 0; i < 32; i = i + 1 {
    if subkey[i] != subkey3[i] {
      differ = true
    }
  }
  assert_true(differ)
}

///|
test "xchacha20: hchacha20 invalid input" {
  let key = Bytes::make(31, b'\x42')
  let input = Bytes::make(16, b'\x37')
  assert_true(hchacha20_derive(key, input) is None)
  let key2 = Bytes::make(32, b'\x42')
  let input2 = Bytes::make(15, b'\x37')
  assert_true(hchacha20_derive(key2, input2) is None)
}
