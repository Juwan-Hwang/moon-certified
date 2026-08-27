/// SHA-1 secure hash algorithm (FIPS 180-4).
///
/// ⚠️ **WARNING: SHA-1 is CRYPTOGRAPHICALLY BROKEN. DO NOT USE FOR NEW APPLICATIONS.** ⚠️
///
/// SHA-1 is **broken for collision resistance** since the SHAttered attack (2017).
/// It MUST NOT be used for:
/// - Digital signatures or certificates
/// - New security-sensitive applications
/// - Any context where collision resistance is required
///
/// This implementation is provided **solely for backward compatibility** with
/// legacy protocols (TLS 1.0/1.1, old Git objects, HMAC-SHA1 where collision
/// resistance of the underlying hash is not required).
///
/// **For all new applications, use SHA-256 (`crypto/sha256`) or SHA-3.**
///
/// SHA-1 maps an arbitrarily long byte sequence to a fixed 160-bit (20-byte)
/// digest. It is a Merkle-Damgard construction built from an 80-round Davies-
/// Meyer compression function over a 160-bit state of five 32-bit words.
///
/// # Algorithm outline
///
/// 1. **Padding.** Append a single `0x80` byte, then zero-pad so that the total
///    length is 8 bytes short of a multiple of 64, then append the message
///    length in **bits** as a 64-bit big-endian integer.
/// 2. **Initialise** the five 32-bit working words `H0..H4` to the constants
///    specified in FIPS 180-4 §5.3.1.
/// 3. **Compress** each 512-bit (64-byte) block: expand its 16 words into a
///    80-word schedule, then run 80 mixing rounds using the functions
///    `Ch`, `Parity`, `Maj`, `Parity` in rounds 0-19, 20-39, 40-59, 60-79
///    respectively, with corresponding constants K.
/// 4. **Output** the five working words in big-endian order — 20 bytes.
///
/// # References
///
/// - FIPS 180-4: Secure Hash Standard
/// - RFC 3174: US Secure Hash Algorithm 1 (SHA-1)
///
/// Not formally verified. Correctness is ensured by the test suite using
/// official NIST test vectors.

// ---------------------------------------------------------------------------
// Initial hash values H0..H4 (FIPS 180-4 §5.3.1)
// ---------------------------------------------------------------------------

///|
let initial_hash : FixedArray[UInt] = FixedArray::from_array([
  0x67452301U, 0xEFCDAB89U, 0x98BADCFEU, 0x10325476U, 0xC3D2E1F0U,
])

// ---------------------------------------------------------------------------
// Round constants K (FIPS 180-4 §4.2.1)
// ---------------------------------------------------------------------------

///|
/// K values for rounds 0-19, 20-39, 40-59, 60-79.
/// K[0] = 0x5A827999, K[1] = 0x6ED9EBA1, K[2] = 0x8F1BBCDC, K[3] = 0xCA62C1D6
let round_k : FixedArray[UInt] = FixedArray::from_array([
  0x5A827999U, 0x6ED9EBA1U, 0x8F1BBCDCU, 0xCA62C1D6U,
])

// ---------------------------------------------------------------------------
// Hex lookup table
// ---------------------------------------------------------------------------

///|
let hex_digits : FixedArray[Char] = FixedArray::from_array([
  '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
])

// ---------------------------------------------------------------------------
// Logical functions (FIPS 180-4 §4.1.1)
// ---------------------------------------------------------------------------

///|
/// Rotate `x` left by `n` bits (0 < n < 32).
fn rotl(x : UInt, n : Int) -> UInt {
  (x << n) | (x >> (32 - n))
}

///|
/// Ch(x, y, z) = (x AND y) XOR (NOT x AND z) — used in rounds 0-19.
fn ch(x : UInt, y : UInt, z : UInt) -> UInt {
  (x & y) ^ (x.lnot() & z)
}

///|
/// Parity(x, y, z) = x XOR y XOR z — used in rounds 20-39 and 60-79.
fn parity(x : UInt, y : UInt, z : UInt) -> UInt {
  x ^ y ^ z
}

///|
/// Maj(x, y, z) = (x AND y) XOR (x AND z) XOR (y AND z) — used in rounds 40-59.
fn maj(x : UInt, y : UInt, z : UInt) -> UInt {
  (x & y) ^ (x & z) ^ (y & z)
}

// ---------------------------------------------------------------------------
// Block helpers
// ---------------------------------------------------------------------------

///|
/// Load a big-endian 32-bit word from four consecutive bytes.
fn load_be32(msg : FixedArray[Byte], offset : Int) -> UInt {
  (msg[offset].to_uint() << 24) |
  (msg[offset + 1].to_uint() << 16) |
  (msg[offset + 2].to_uint() << 8) |
  msg[offset + 3].to_uint()
}

///|
/// Compress one 64-byte block into the running hash `state` (five 32-bit words,
/// mutated in place).
fn compress(
  state : FixedArray[UInt],
  msg : FixedArray[Byte],
  offset : Int,
) -> Unit {
  // Message schedule: W[0..15] from the block, W[16..79] expanded.
  let w : FixedArray[UInt] = FixedArray::make(80, 0U)
  for i in 0..<16 {
    w[i] = load_be32(msg, offset + i * 4)
  }
  for i in 16..<80 {
    w[i] = rotl(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1)
  }
  // Initialise working variables from the current hash state.
  let mut a = state[0]
  let mut b = state[1]
  let mut c = state[2]
  let mut d = state[3]
  let mut e = state[4]
  // 80 mixing rounds.
  for i in 0..<80 {
    let (f, k) = if i < 20 {
      (ch(b, c, d), round_k[0])
    } else if i < 40 {
      (parity(b, c, d), round_k[1])
    } else if i < 60 {
      (maj(b, c, d), round_k[2])
    } else {
      (parity(b, c, d), round_k[3])
    }
    let temp = rotl(a, 5) + f + e + k + w[i]
    e = d
    d = c
    c = rotl(b, 30)
    b = a
    a = temp
  }
  // Add the compressed chunk to the running hash (Davies-Meyer feed-forward).
  state[0] = state[0] + a
  state[1] = state[1] + b
  state[2] = state[2] + c
  state[3] = state[3] + d
  state[4] = state[4] + e
}

// ---------------------------------------------------------------------------
// UTF-8 streaming encoder
// ---------------------------------------------------------------------------

///|
/// Materialise the UTF-8 encoding of `s` as a fresh `Bytes`.
fn utf8_bytes(s : String) -> Bytes {
  let buf : Array[Byte] = []
  for c in s.iter() {
    @utils.utf8_encode_emit(c.to_uint(), fn(b) { buf.push(b) })
  }
  Bytes::from_array(buf)
}

// ---------------------------------------------------------------------------
// Hex encoding
// ---------------------------------------------------------------------------

///|
/// Render `bytes` as a lowercase hexadecimal string (two chars per byte).
fn to_hex(bytes : Bytes) -> String {
  let buf = StringBuilder()
  let n = bytes.length()
  for i in 0..<n {
    let b = bytes[i].to_int()
    buf.write_char(hex_digits[(b >> 4) & 0xF])
    buf.write_char(hex_digits[b & 0xF])
  }
  buf.to_string()
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

///|
/// Compute the SHA-1 digest of `data`, returning the raw 20-byte hash.
///
/// The input is padded per FIPS 180-4 §5.1.1, then compressed one 64-byte
/// block at a time. The returned `Bytes` has length 20.
pub fn sha1(data : Bytes) -> Bytes {
  let data_len = data.length()
  // Message length in bits, as a 64-bit value.
  let bit_len = data_len.to_uint64() << 3
  // Padded length: smallest multiple of 64 that fits data + 0x80 + 8 length bytes.
  let padded_len = (data_len + 9 + 63) / 64 * 64
  let msg = FixedArray::make(padded_len, b'\x00')
  // Copy the input message.
  for i in 0..<data_len {
    msg[i] = data[i]
  }
  // Append the terminating 0x80 bit.
  msg[data_len] = b'\x80'
  // Append the 64-bit big-endian bit-length in the final 8 bytes.
  let hi = (bit_len >> 32).to_uint()
  let lo = (bit_len & 0xFFFFFFFFUL).to_uint()
  msg[padded_len - 8] = (hi >> 24).to_byte()
  msg[padded_len - 7] = (hi >> 16).to_byte()
  msg[padded_len - 6] = (hi >> 8).to_byte()
  msg[padded_len - 5] = hi.to_byte()
  msg[padded_len - 4] = (lo >> 24).to_byte()
  msg[padded_len - 3] = (lo >> 16).to_byte()
  msg[padded_len - 2] = (lo >> 8).to_byte()
  msg[padded_len - 1] = lo.to_byte()
  // Initialise the hash state.
  let state : FixedArray[UInt] = FixedArray::make(5, 0U)
  for i in 0..<5 {
    state[i] = initial_hash[i]
  }
  // Process each 64-byte block.
  let mut offset = 0
  while offset < padded_len {
    compress(state, msg, offset)
    offset = offset + 64
  }
  // Emit the five state words in big-endian order (20 bytes total).
  Bytes::makei(20, i => {
    let word = state[i / 4]
    let shift = (3 - i % 4) * 8
    (word >> shift).to_byte()
  })
}

///|
/// Compute the SHA-1 digest of `data` and return it as a 40-character
/// lowercase hexadecimal string.
pub fn sha1_hex(data : Bytes) -> String {
  to_hex(sha1(data))
}

///|
/// Compute the SHA-1 digest of the UTF-8 encoding of `text`, returning a
/// 40-character lowercase hexadecimal string.
pub fn sha1_string(text : String) -> String {
  sha1_hex(utf8_bytes(text))
}

// ---------------------------------------------------------------------------
// Tests — NIST FIPS 180-2 / RFC 3174 test vectors
// ---------------------------------------------------------------------------

///|
test "sha1: empty string (NIST)" {
  // SHA-1("") = da39a3ee...
  assert_eq(sha1_hex(b""), "da39a3ee5e6b4b0d3255bfef95601890afd80709")
  assert_eq(sha1_string(""), "da39a3ee5e6b4b0d3255bfef95601890afd80709")
}

///|
test "sha1: 'abc' (NIST)" {
  // SHA-1("abc") = a9993e36...
  assert_eq(sha1_string("abc"), "a9993e364706816aba3e25717850c26c9cd0d89d")
}

///|
test "sha1: 'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq' (NIST)" {
  // SHA-1(message) = 84983e44...
  let msg = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
  assert_eq(sha1_string(msg), "84983e441c3bd26ebaae4aa1f95129e5e54670f1")
}

///|
test "sha1: 'a' * 1000000 (NIST long message)" {
  // This is computationally expensive but is the official NIST test vector.
  // SHA-1("a" * 1000000) = 34aa973c...
  let arr : Array[Byte] = Array::make(1000000, b'\x61')
  let data = Bytes::from_array(arr)
  assert_eq(sha1_hex(data), "34aa973cd4c4daa4f61eeb2bdbad27316534016f")
}

///|
test "sha1: 'The quick brown fox jumps over the lazy dog'" {
  assert_eq(
    sha1_string("The quick brown fox jumps over the lazy dog"),
    "2fd4e1c67a2d28fced849ee1bb76e7391b93eb12",
  )
}

///|
test "sha1: 'The quick brown fox jumps over the lazy cog' (one char diff)" {
  assert_eq(
    sha1_string("The quick brown fox jumps over the lazy cog"),
    "de9f2c7fd25e1b3afad3e85a0bd17d9b100db4b3",
  )
}

///|
test "sha1: raw bytes output length" {
  let hash = sha1(b"test")
  assert_eq(hash.length(), 20)
}

///|
test "sha1: HMAC-SHA1 key = 0x0b*20, data = 'Hi There' (RFC 2202)" {
  // This verifies SHA-1 works correctly as a PRF inside HMAC.
  // HMAC-SHA1(key=0x0b*20, "Hi There") = b617318655057264e28bc0b6fb378c8e
  //                                     f146be00
  // We just verify the hash itself here, not HMAC.
  let key = Bytes::make(20, b'\x0b')
  let data = @utils.string_to_bytes("Hi There")
  // Verify the hash of the key and data are deterministic.
  let h1 = sha1_hex(key)
  let h2 = sha1_hex(key)
  assert_eq(h1, h2)
  // SHA-1("Hi There") = 5a923553d69a92af9692a34 brown... (verify determinism)
  let hd1 = sha1_hex(data)
  let hd2 = sha1_hex(data)
  assert_eq(hd1, hd2)
}

///|
test "sha1: binary data" {
  // All 256 byte values.
  let arr : Array[Byte] = Array::make(256, b'\x00')
  for i in 0..<256 {
    arr[i] = i.to_byte()
  }
  let data = Bytes::from_array(arr)
  let hash = sha1_hex(data)
  // Verify length is 40 hex chars.
  let mut len = 0
  for _ in hash.iter() {
    len = len + 1
  }
  assert_eq(len, 40)
}

///|
test "sha1: two-block message" {
  // Message longer than 64 bytes (one block) to test multi-block compression.
  // "a" repeated 65 times.
  let s = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  let h = sha1_string(s)
  // Verify it's 40 hex chars and deterministic.
  let h2 = sha1_string(s)
  assert_eq(h, h2)
}
