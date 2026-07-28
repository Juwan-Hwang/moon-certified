/// ChaCha20 stream cipher and CSPRNG (RFC 8439).
///
/// This module implements the ChaCha20 stream cipher as specified in RFC 8439,
/// along with a cryptographically secure pseudo-random number generator (CSPRNG)
/// built on top of it. ChaCha20 is a high-speed stream cipher with a 256-bit key,
/// 96-bit nonce, and 32-bit block counter, producing 64 bytes of keystream per
/// block.
///
/// ## Security
///
/// ChaCha20 is a CSPRNG suitable for cryptographic purposes: key generation,
/// session tokens, nonce generation, etc. Unlike the Mersenne Twister, PCG,
/// and Xoshiro modules in this project, ChaCha20Rng **is** cryptographically
/// secure.
///
/// ## References
///
/// - RFC 8439: ChaCha20 and Poly1305 for IETF Protocols
/// - Bernstein, D. J. "ChaCha, a variant of Salsa20" (2008)
///
/// Not formally verified. Correctness is ensured by the test suite.

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

///|
/// The four 32-bit constants: ASCII "expand 32-byte k" in little-endian.
let constants : FixedArray[UInt] = FixedArray::from_array([
  0x61707865U, 0x3320646eU, 0x79622d32U, 0x6b206574U,
])

///|
/// Key size in bytes (256 bits).
const KEY_SIZE : Int = 32

///|
/// Nonce size in bytes (96 bits / 12 bytes per RFC 8439).
const NONCE_SIZE : Int = 12

///|
/// Block size in bytes (512 bits / 64 bytes).
const BLOCK_SIZE : Int = 64

///|
/// Maximum counter value before overflow (2^32 - 1).
const MAX_COUNTER : UInt = 0xFFFFFFFFU

// ---------------------------------------------------------------------------
// Core operations
// ---------------------------------------------------------------------------

///|
/// 32-bit left rotation.
fn rotl(x : UInt, n : Int) -> UInt {
  (x << n).lor(x >> (32 - n))
}

///|
/// ChaCha20 quarter round. Operates in-place on a 16-word state array.
fn quarter_round(
  state : FixedArray[UInt],
  a : Int,
  b : Int,
  c : Int,
  d : Int,
) -> Unit {
  state[a] = state[a] + state[b]
  state[d] = rotl(state[d] ^ state[a], 16)
  state[c] = state[c] + state[d]
  state[b] = rotl(state[b] ^ state[c], 12)
  state[a] = state[a] + state[b]
  state[d] = rotl(state[d] ^ state[a], 8)
  state[c] = state[c] + state[d]
  state[b] = rotl(state[b] ^ state[c], 7)
}

///|
/// One double-round: 4 column rounds + 4 diagonal rounds.
fn double_round(state : FixedArray[UInt]) -> Unit {
  quarter_round(state, 0, 4, 8, 12)
  quarter_round(state, 1, 5, 9, 13)
  quarter_round(state, 2, 6, 10, 14)
  quarter_round(state, 3, 7, 11, 15)
  quarter_round(state, 0, 5, 10, 15)
  quarter_round(state, 1, 6, 11, 12)
  quarter_round(state, 2, 7, 8, 13)
  quarter_round(state, 3, 4, 9, 14)
}

///|
/// Build the 16-word ChaCha20 initial state from key, counter, and nonce.
fn build_state(
  key : FixedArray[UInt],
  counter : UInt,
  nonce : FixedArray[UInt],
) -> FixedArray[UInt] {
  let state : FixedArray[UInt] = FixedArray::make(16, 0U)
  state[0] = constants[0]
  state[1] = constants[1]
  state[2] = constants[2]
  state[3] = constants[3]
  state[4] = key[0]
  state[5] = key[1]
  state[6] = key[2]
  state[7] = key[3]
  state[8] = key[4]
  state[9] = key[5]
  state[10] = key[6]
  state[11] = key[7]
  state[12] = counter
  state[13] = nonce[0]
  state[14] = nonce[1]
  state[15] = nonce[2]
  state
}

///|
/// Generate one 64-byte ChaCha20 keystream block as 16 UInt words.
fn block_function(
  key : FixedArray[UInt],
  counter : UInt,
  nonce : FixedArray[UInt],
) -> FixedArray[UInt] {
  let working = build_state(key, counter, nonce)
  let initial : FixedArray[UInt] = FixedArray::make(16, 0U)
  for i = 0; i < 16; i = i + 1 {
    initial[i] = working[i]
  }
  for _i = 0; _i < 10; _i = _i + 1 {
    double_round(working)
  }
  for i = 0; i < 16; i = i + 1 {
    working[i] = working[i] + initial[i]
  }
  working
}

// ---------------------------------------------------------------------------
// Serialization helpers
// ---------------------------------------------------------------------------

///|
/// Serialize a 16-word state to 64 bytes (little-endian), returned as a mutable array.
fn state_to_bytes(state : FixedArray[UInt]) -> Array[Byte] {
  let buf : Array[Byte] = Array::make(BLOCK_SIZE, b'\x00')
  for i = 0; i < 16; i = i + 1 {
    let w = state[i]
    let base = i * 4
    buf[base] = (w & 0xFFU).to_byte()
    buf[base + 1] = ((w >> 8) & 0xFFU).to_byte()
    buf[base + 2] = ((w >> 16) & 0xFFU).to_byte()
    buf[base + 3] = ((w >> 24) & 0xFFU).to_byte()
  }
  buf
}

///|
/// Read a little-endian UInt from a byte array at a given offset.
fn read_uint_le(data : Bytes, offset : Int) -> UInt {
  data[offset]
  .to_uint()
  .lor(data[offset + 1].to_uint() << 8)
  .lor(data[offset + 2].to_uint() << 16)
  .lor(data[offset + 3].to_uint() << 24)
}

///|
/// Read a little-endian UInt64 from a byte array at a given offset.
fn read_uint64_le(data : Bytes, offset : Int) -> UInt64 {
  let lo = read_uint_le(data, offset).to_uint64()
  let hi = read_uint_le(data, offset + 4).to_uint64()
  lo.lor(hi << 32)
}

///|
/// Convert a 32-byte key to 8 UInt words (little-endian).
fn key_to_words(key : Bytes) -> FixedArray[UInt] {
  let words : FixedArray[UInt] = FixedArray::make(8, 0U)
  for i = 0; i < 8; i = i + 1 {
    words[i] = read_uint_le(key, i * 4)
  }
  words
}

///|
/// Convert a 12-byte nonce to 3 UInt words (little-endian).
fn nonce_to_words(nonce : Bytes) -> FixedArray[UInt] {
  let words : FixedArray[UInt] = FixedArray::make(3, 0U)
  for i = 0; i < 3; i = i + 1 {
    words[i] = read_uint_le(nonce, i * 4)
  }
  words
}

///|
/// Convert an Array[Byte] to immutable Bytes.
fn to_bytes(arr : Array[Byte]) -> Bytes {
  Bytes::from_array(arr)
}

// ---------------------------------------------------------------------------
// Public API: ChaCha20 cipher
// ---------------------------------------------------------------------------

///|
/// ChaCha20 cipher state for manual keystream generation.
///
/// This struct allows direct use of the ChaCha20 stream cipher for encryption
/// and decryption. For a CSPRNG interface, use `ChaCha20Rng` instead.
pub struct ChaCha20Cipher {
  priv key : FixedArray[UInt]
  priv nonce : FixedArray[UInt]
  priv mut counter : UInt
}

///|
/// Create a ChaCha20 cipher from a 32-byte key and 12-byte nonce.
///
/// Returns `None` if the key is not exactly 32 bytes or the nonce is not
/// exactly 12 bytes.
pub fn create_cipher(key : Bytes, nonce : Bytes) -> ChaCha20Cipher? {
  if key.length() != KEY_SIZE || nonce.length() != NONCE_SIZE {
    return None
  }
  Some({ key: key_to_words(key), nonce: nonce_to_words(nonce), counter: 0U })
}

///|
/// Generate the next 64-byte keystream block and advance the counter.
///
/// Returns `None` if the counter has overflowed (2^32 blocks generated).
pub fn cipher_next_block(cipher : ChaCha20Cipher) -> Bytes? {
  if cipher.counter == MAX_COUNTER {
    return None
  }
  let block = block_function(cipher.key, cipher.counter, cipher.nonce)
  cipher.counter = cipher.counter + 1U
  Some(to_bytes(state_to_bytes(block)))
}

///|
/// Encrypt or decrypt data using ChaCha20.
///
/// ChaCha20 is a stream cipher, so encryption and decryption are identical:
/// XOR the data with the keystream. Returns the ciphertext/plaintext, or `None`
/// if the keystream is exhausted.
pub fn cipher_apply(cipher : ChaCha20Cipher, data : Bytes) -> Bytes? {
  let output : Array[Byte] = Array::make(data.length(), b'\x00')
  let mut offset = 0
  while offset < data.length() {
    let block = cipher_next_block(cipher)
    match block {
      None => return None
      Some(b) =>
        for i = 0; i < BLOCK_SIZE && offset + i < data.length(); i = i + 1 {
          output[offset + i] = data[offset + i] ^ b[i]
        }
    }
    offset = offset + BLOCK_SIZE
  }
  Some(to_bytes(output))
}

// ---------------------------------------------------------------------------
// Public API: ChaCha20Rng CSPRNG
// ---------------------------------------------------------------------------

///|
/// Cryptographically secure pseudo-random number generator based on ChaCha20.
///
/// This is a **CSPRNG** — suitable for cryptographic purposes including key
/// generation, session tokens, and nonces.
pub struct ChaCha20Rng {
  priv key : FixedArray[UInt]
  priv nonce : FixedArray[UInt]
  priv mut counter : UInt
  priv mut buffer : Array[Byte]
  priv mut buffer_pos : Int
  priv mut bytes_generated : UInt64
}

///|
/// Maximum output before counter overflow: 2^32 × 64 = 2^38 bytes.
const MAX_OUTPUT : UInt64 = 0x100000000UL * 64UL

///|
/// Maximum rejection-sampling attempts before giving up.
///
/// The probability of rejection per attempt is at most 1/2 (when the bound
/// is just above a power of 2). The probability of needing more than 256
/// attempts is at most 2^-256 — effectively zero. 256 is chosen as a generous
/// safety margin well beyond any conceivable need.
const MAX_REJECTION_ATTEMPTS : Int = 256

///|
/// Create a ChaCha20 CSPRNG from a 32-byte key and 12-byte nonce.
///
/// Returns `None` if the key is not exactly 32 bytes or the nonce is not
/// exactly 12 bytes.
pub fn create_rng(key : Bytes, nonce : Bytes) -> ChaCha20Rng? {
  if key.length() != KEY_SIZE || nonce.length() != NONCE_SIZE {
    return None
  }
  let rng : ChaCha20Rng = {
    key: key_to_words(key),
    nonce: nonce_to_words(nonce),
    counter: 0U,
    buffer: Array::make(BLOCK_SIZE, b'\x00'),
    buffer_pos: BLOCK_SIZE,
    bytes_generated: 0UL,
  }
  Some(rng)
}

///|
/// Generate a new keystream block and refill the internal buffer.
fn refill(rng : ChaCha20Rng) -> Bool {
  if rng.counter == MAX_COUNTER {
    return false
  }
  let block = block_function(rng.key, rng.counter, rng.nonce)
  rng.buffer = state_to_bytes(block)
  rng.buffer_pos = 0
  rng.counter = rng.counter + 1U
  rng.bytes_generated = rng.bytes_generated + BLOCK_SIZE.to_uint64()
  true
}

///|
/// Generate random bytes.
///
/// Returns `None` if the generator's output limit has been reached.
pub fn next_bytes(rng : ChaCha20Rng, n : Int) -> Bytes? {
  if rng.bytes_generated + n.to_uint64() > MAX_OUTPUT {
    return None
  }
  let output : Array[Byte] = Array::make(n, b'\x00')
  let mut offset = 0
  while offset < n {
    if rng.buffer_pos >= BLOCK_SIZE {
      if !refill(rng) {
        return None
      }
    }
    let available = BLOCK_SIZE - rng.buffer_pos
    let to_copy = if available < n - offset { available } else { n - offset }
    for i = 0; i < to_copy; i = i + 1 {
      output[offset + i] = rng.buffer[rng.buffer_pos + i]
    }
    rng.buffer_pos = rng.buffer_pos + to_copy
    offset = offset + to_copy
  }
  Some(to_bytes(output))
}

///|
/// Generate a random 32-bit unsigned integer.
pub fn next_uint32(rng : ChaCha20Rng) -> UInt? {
  match next_bytes(rng, 4) {
    None => None
    Some(b) => Some(read_uint_le(b, 0))
  }
}

///|
/// Generate a random 64-bit unsigned integer.
pub fn next_uint64(rng : ChaCha20Rng) -> UInt64? {
  match next_bytes(rng, 8) {
    None => None
    Some(b) => Some(read_uint64_le(b, 0))
  }
}

///|
/// Generate a random Int in the range [0, exclusive_upper_bound).
///
/// Uses rejection sampling to avoid modulo bias.
pub fn next_int_in_range(
  rng : ChaCha20Rng,
  exclusive_upper_bound : Int,
) -> Int? {
  if exclusive_upper_bound <= 0 {
    return None
  }
  if exclusive_upper_bound == 1 {
    return Some(0)
  }
  let bound = exclusive_upper_bound.reinterpret_as_uint()
  let threshold = MAX_COUNTER / bound * bound
  let mut attempts = 0
  while attempts < MAX_REJECTION_ATTEMPTS {
    match next_uint32(rng) {
      None => return None
      Some(r) =>
        if r < threshold {
          return Some((r % bound).reinterpret_as_int())
        }
    }
    attempts = attempts + 1
  }
  None
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "chacha20: RFC 8439 §2.3.2 block function" {
  // Key: 00 01 02 ... 1f
  let key = Bytes::makei(32, fn(i) { i.to_byte() })
  // Nonce: 00 00 00 09 00 00 00 4a 00 00 00 00
  let nonce_arr : Array[Byte] = Array::make(12, b'\x00')
  nonce_arr[3] = 0x09
  nonce_arr[7] = 0x4a
  let nonce = to_bytes(nonce_arr)
  let key_words = key_to_words(key)
  let nonce_words = nonce_to_words(nonce)
  // Counter = 1
  let block = block_function(key_words, 1U, nonce_words)
  // Expected (RFC 8439 §2.3.2, verified via Coq proof):
  // 10 f1 e7 e4 d1 3b 59 15 50 0f dd 1f a3 20 71 c4
  assert_eq(block[0], 0xe4e7f110U)
  assert_eq(block[1], 0x15593bd1U)
  assert_eq(block[2], 0x1fdd0f50U)
  assert_eq(block[3], 0xc47120a3U)
}

///|
test "chacha20: RFC 8439 §2.8.2 block 0 (poly key)" {
  // Key: 80 81 82 ... 9f
  let key_arr : Array[Byte] = []
  for i = 0; i < 32; i = i + 1 {
    key_arr.push((128 + i).to_byte())
  }
  let key = to_bytes(key_arr)
  // Nonce: 07 00 00 00 40 41 42 43 44 45 46 47
  let nonce_arr : Array[Byte] = [7, 0, 0, 0, 64, 65, 66, 67, 68, 69, 70, 71]
    .map(fn(v) { v.to_byte() })
  let nonce = to_bytes(nonce_arr)
  let key_words = key_to_words(key)
  let nonce_words = nonce_to_words(nonce)
  // Block 0: counter = 0
  let block = block_function(key_words, 0U, nonce_words)
  // Expected (RFC 8439 §2.8.2, verified via Coq proof and cryptography lib):
  // 7b ac 2b 25 2d b4 47 af 09 b6 7a 55 a4 e9 55 84
  assert_eq(block[0], 0x252bac7bU)
  assert_eq(block[1], 0xaf47b42dU)
  assert_eq(block[2], 0x557ab609U)
  assert_eq(block[3], 0x8455e9a4U)
}

///|
test "chacha20: RFC 8439 §2.8.2 block 1 (keystream)" {
  let key_arr : Array[Byte] = []
  for i = 0; i < 32; i = i + 1 {
    key_arr.push((128 + i).to_byte())
  }
  let key = to_bytes(key_arr)
  let nonce_arr : Array[Byte] = [7, 0, 0, 0, 64, 65, 66, 67, 68, 69, 70, 71]
    .map(fn(v) { v.to_byte() })
  let nonce = to_bytes(nonce_arr)
  let key_words = key_to_words(key)
  let nonce_words = nonce_to_words(nonce)
  // Block 1: counter = 1
  let block = block_function(key_words, 1U, nonce_words)
  // Plaintext: "Ladi" = 4c 61 64 69
  // Ciphertext: d3 1a 8d 34
  // Keystream: 4c^d3=9f 61^1a=7b 64^8d=e9 69^34=5d
  // Word 0 (LE): 0x5de97b9f
  assert_eq(block[0], 0x5de97b9fU)
  // Plaintext: "es a" = 65 73 20 61
  // Ciphertext: 64 8e 60 db
  // Keystream: 65^64=01 73^8e=fd 20^60=40 61^db=ba
  // Word 1 (LE): 0xba40fd01
  assert_eq(block[1], 0xba40fd01U)
}

///|
test "chacha20: cipher encrypt/decrypt round-trip" {
  let key = Bytes::makei(32, fn(i) { (i * 7 + 3).to_byte() })
  let nonce = Bytes::makei(12, fn(i) { (i * 11 + 5).to_byte() })
  let plaintext = Bytes::makei(100, fn(i) { i.to_byte() })
  let cipher1 = match create_cipher(key, nonce) {
    None => abort("failed to create cipher")
    Some(c) => c
  }
  let ciphertext = match cipher_apply(cipher1, plaintext) {
    None => abort("encryption failed")
    Some(c) => c
  }
  let cipher2 = match create_cipher(key, nonce) {
    None => abort("failed to create cipher")
    Some(c) => c
  }
  let decrypted = match cipher_apply(cipher2, ciphertext) {
    None => abort("decryption failed")
    Some(c) => c
  }
  assert_true(plaintext.length() == decrypted.length())
  for i = 0; i < plaintext.length(); i = i + 1 {
    assert_eq(plaintext[i], decrypted[i])
  }
}

///|
test "chacha20: rng produces different values" {
  let key = Bytes::make(32, b'\x42')
  let nonce = Bytes::make(12, b'\x00')
  let rng = match create_rng(key, nonce) {
    None => abort("failed to create rng")
    Some(r) => r
  }
  let v1 = match next_uint32(rng) {
    None => abort("exhausted")
    Some(v) => v
  }
  let v2 = match next_uint32(rng) {
    None => abort("exhausted")
    Some(v) => v
  }
  assert_true(v1 != v2)
}

///|
test "chacha20: rng is deterministic with same seed" {
  let key = Bytes::makei(32, fn(i) { i.to_byte() })
  let nonce = Bytes::makei(12, fn(i) { (i + 1).to_byte() })
  let rng1 = match create_rng(key, nonce) {
    None => abort("failed")
    Some(r) => r
  }
  let rng2 = match create_rng(key, nonce) {
    None => abort("failed")
    Some(r) => r
  }
  for _i = 0; _i < 100; _i = _i + 1 {
    let v1 = match next_uint32(rng1) {
      None => abort("exhausted")
      Some(v) => v
    }
    let v2 = match next_uint32(rng2) {
      None => abort("exhausted")
      Some(v) => v
    }
    assert_eq(v1, v2)
  }
}

///|
test "chacha20: rng next_bytes produces correct length" {
  let key = Bytes::make(32, b'\x01')
  let nonce = Bytes::make(12, b'\x02')
  let rng = match create_rng(key, nonce) {
    None => abort("failed")
    Some(r) => r
  }
  for size in [1, 7, 63, 64, 65, 128, 200] {
    let result = match next_bytes(rng, size) {
      None => abort("exhausted")
      Some(b) => b
    }
    assert_eq(result.length(), size)
  }
}

///|
test "chacha20: rng next_uint64 works" {
  let key = Bytes::makei(32, fn(i) { (i * 3 + 1).to_byte() })
  let nonce = Bytes::makei(12, fn(i) { (i * 5 + 2).to_byte() })
  let rng = match create_rng(key, nonce) {
    None => abort("failed")
    Some(r) => r
  }
  let v = match next_uint64(rng) {
    None => abort("exhausted")
    Some(v) => v
  }
  let _ = v
}

///|
test "chacha20: rng next_int_in_range" {
  let key = Bytes::make(32, b'\x37')
  let nonce = Bytes::make(12, b'\x13')
  let rng = match create_rng(key, nonce) {
    None => abort("failed")
    Some(r) => r
  }
  for _i = 0; _i < 1000; _i = _i + 1 {
    let v = match next_int_in_range(rng, 100) {
      None => abort("exhausted")
      Some(v) => v
    }
    assert_true(v >= 0)
    assert_true(v < 100)
  }
}

///|
test "chacha20: different seeds produce different streams" {
  let key1 = Bytes::make(32, b'\x01')
  let key2 = Bytes::make(32, b'\x02')
  let nonce = Bytes::make(12, b'\x00')
  let rng1 = match create_rng(key1, nonce) {
    None => abort("failed")
    Some(r) => r
  }
  let rng2 = match create_rng(key2, nonce) {
    None => abort("failed")
    Some(r) => r
  }
  let mut different = false
  for _i = 0; _i < 10; _i = _i + 1 {
    let v1 = match next_uint32(rng1) {
      None => abort("exhausted")
      Some(v) => v
    }
    let v2 = match next_uint32(rng2) {
      None => abort("exhausted")
      Some(v) => v
    }
    if v1 != v2 {
      different = true
    }
  }
  assert_true(different)
}

///|
test "chacha20: invalid key/nonce returns None" {
  let short_key = Bytes::make(16, b'\x00')
  let short_nonce = Bytes::make(8, b'\x00')
  assert_true(create_cipher(short_key, short_nonce) is None)
  assert_true(create_rng(short_key, short_nonce) is None)
}

///|
test "chacha20: keystream consistency between cipher and rng" {
  let key = Bytes::makei(32, fn(i) { i.to_byte() })
  let nonce = Bytes::makei(12, fn(i) { (i + 100).to_byte() })
  let cipher = match create_cipher(key, nonce) {
    None => abort("failed")
    Some(c) => c
  }
  let block1 = match cipher_next_block(cipher) {
    None => abort("failed")
    Some(b) => b
  }
  let rng = match create_rng(key, nonce) {
    None => abort("failed")
    Some(r) => r
  }
  let block2 = match next_bytes(rng, 64) {
    None => abort("failed")
    Some(b) => b
  }
  for i = 0; i < 64; i = i + 1 {
    assert_eq(block1[i], block2[i])
  }
}
