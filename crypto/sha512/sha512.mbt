/// SHA-512 secure hash algorithm (FIPS 180-4).
///
/// SHA-512 maps an arbitrarily long byte sequence to a fixed 512-bit (64-byte)
/// digest. It uses 64-bit working variables and 80 rounds per block.
///
/// `proof-enabled` is `false`; correctness is backed by NIST test vectors.

///|
let k512 : FixedArray[UInt64] = FixedArray::from_array([
  0x428a2f98d728ae22UL, 0x7137449123ef65cdUL, 0xb5c0fbcfec4d3b2fUL, 0xe9b5dba58189dbbcUL,
  0x3956c25bf348b538UL, 0x59f111f1b605d019UL, 0x923f82a4af194f9bUL, 0xab1c5ed5da6d8118UL,
  0xd807aa98a3030242UL, 0x12835b0145706fbeUL, 0x243185be4ee4b28cUL, 0x550c7dc3d5ffb4e2UL,
  0x72be5d74f27b896fUL, 0x80deb1fe3b1696b1UL, 0x9bdc06a725c71235UL, 0xc19bf174cf692694UL,
  0xe49b69c19ef14ad2UL, 0xefbe4786384f25e3UL, 0x0fc19dc68b8cd5b5UL, 0x240ca1cc77ac9c65UL,
  0x2de92c6f592b0275UL, 0x4a7484aa6ea6e483UL, 0x5cb0a9dcbd41fbd4UL, 0x76f988da831153b5UL,
  0x983e5152ee66dfabUL, 0xa831c66d2db43210UL, 0xb00327c898fb213fUL, 0xbf597fc7beef0ee4UL,
  0xc6e00bf33da88fc2UL, 0xd5a79147930aa725UL, 0x06ca6351e003826fUL, 0x142929670a0e6e70UL,
  0x27b70a8546d22ffcUL, 0x2e1b21385c26c926UL, 0x4d2c6dfc5ac42aedUL, 0x53380d139d95b3dfUL,
  0x650a73548baf63deUL, 0x766a0abb3c77b2a8UL, 0x81c2c92e47edaee6UL, 0x92722c851482353bUL,
  0xa2bfe8a14cf10364UL, 0xa81a664bbc423001UL, 0xc24b8b70d0f89791UL, 0xc76c51a30654be30UL,
  0xd192e819d6ef5218UL, 0xd69906245565a910UL, 0xf40e35855771202aUL, 0x106aa07032bbd1b8UL,
  0x19a4c116b8d2d0c8UL, 0x1e376c085141ab53UL, 0x2748774cdf8eeb99UL, 0x34b0bcb5e19b48a8UL,
  0x391c0cb3c5c95a63UL, 0x4ed8aa4ae3418acbUL, 0x5b9cca4f7763e373UL, 0x682e6ff3d6b2b8a3UL,
  0x748f82ee5defb2fcUL, 0x78a5636f43172f60UL, 0x84c87814a1f0ab72UL, 0x8cc702081a6439ecUL,
  0x90befffa23631e28UL, 0xa4506cebde82bde9UL, 0xbef9a3f7b2c67915UL, 0xc67178f2e372532bUL,
  0xca273eceea26619cUL, 0xd186b8c721c0c207UL, 0xeada7dd6cde0eb1eUL, 0xf57d4f7fee6ed178UL,
  0x06f067aa72176fbaUL, 0x0a637dc5a2c898a6UL, 0x113f9804bef90daeUL, 0x1b710b35131c471bUL,
  0x28db77f523047d84UL, 0x32caab7b40c72493UL, 0x3c9ebe0a15c9bebcUL, 0x431d67c49c100d4cUL,
  0x4cc5d4becb3e42b6UL, 0x597f299cfc657e2aUL, 0x5fcb6fab3ad6faecUL, 0x6c44198c4a475817UL,
])

///|
let h512_init : FixedArray[UInt64] = FixedArray::from_array([
  0x6a09e667f3bcc908UL, 0xbb67ae8584caa73bUL, 0x3c6ef372fe94f82bUL, 0xa54ff53a5f1d36f1UL,
  0x510e527fade682d1UL, 0x9b05688c2b3e6c1fUL, 0x1f83d9abfb41bd6bUL, 0x5be0cd19137e2179UL,
])

///|
let hex_digits_512 : FixedArray[Char] = FixedArray::from_array([
  '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
])

///|
fn rotr64(x : UInt64, n : Int) -> UInt64 {
  (x >> n) | (x << (64 - n))
}

///|
fn ch64(x : UInt64, y : UInt64, z : UInt64) -> UInt64 {
  (x & y) ^ (x.lnot() & z)
}

///|
fn maj64(x : UInt64, y : UInt64, z : UInt64) -> UInt64 {
  (x & y) ^ (x & z) ^ (y & z)
}

///|
fn big_sigma0_64(x : UInt64) -> UInt64 {
  rotr64(x, 28) ^ rotr64(x, 34) ^ rotr64(x, 39)
}

///|
fn big_sigma1_64(x : UInt64) -> UInt64 {
  rotr64(x, 14) ^ rotr64(x, 18) ^ rotr64(x, 41)
}

///|
fn small_sigma0_64(x : UInt64) -> UInt64 {
  rotr64(x, 1) ^ rotr64(x, 8) ^ (x >> 7)
}

///|
fn small_sigma1_64(x : UInt64) -> UInt64 {
  rotr64(x, 19) ^ rotr64(x, 61) ^ (x >> 6)
}

///|
fn load_be64(msg : FixedArray[Byte], offset : Int) -> UInt64 {
  (msg[offset].to_uint64() << 56) |
  (msg[offset + 1].to_uint64() << 48) |
  (msg[offset + 2].to_uint64() << 40) |
  (msg[offset + 3].to_uint64() << 32) |
  (msg[offset + 4].to_uint64() << 24) |
  (msg[offset + 5].to_uint64() << 16) |
  (msg[offset + 6].to_uint64() << 8) |
  msg[offset + 7].to_uint64()
}

///|
fn compress512(
  state : FixedArray[UInt64],
  msg : FixedArray[Byte],
  offset : Int,
) -> Unit {
  let w : FixedArray[UInt64] = FixedArray::make(80, 0UL)
  for i in 0..<16 {
    w[i] = load_be64(msg, offset + i * 8)
  }
  for i in 16..<80 {
    w[i] = small_sigma1_64(w[i - 2]) +
      w[i - 7] +
      small_sigma0_64(w[i - 15]) +
      w[i - 16]
  }
  let mut a = state[0]
  let mut b = state[1]
  let mut c = state[2]
  let mut d = state[3]
  let mut e = state[4]
  let mut f = state[5]
  let mut g = state[6]
  let mut h = state[7]
  for i in 0..<80 {
    let t1 = h + big_sigma1_64(e) + ch64(e, f, g) + k512[i] + w[i]
    let t2 = big_sigma0_64(a) + maj64(a, b, c)
    h = g
    g = f
    f = e
    e = d + t1
    d = c
    c = b
    b = a
    a = t1 + t2
  }
  state[0] = state[0] + a
  state[1] = state[1] + b
  state[2] = state[2] + c
  state[3] = state[3] + d
  state[4] = state[4] + e
  state[5] = state[5] + f
  state[6] = state[6] + g
  state[7] = state[7] + h
}

///|
/// UTF-8 encode a string to Bytes.
fn utf8_bytes_512(s : String) -> Bytes {
  let buf : Array[Byte] = []
  for c in s.iter() {
    let cp = c.to_uint()
    if cp < 0x80U {
      buf.push(cp.to_byte())
    } else if cp < 0x800U {
      buf.push((0xC0U | (cp >> 6)).to_byte())
      buf.push((0x80U | (cp & 0x3FU)).to_byte())
    } else if cp < 0x10000U {
      buf.push((0xE0U | (cp >> 12)).to_byte())
      buf.push((0x80U | ((cp >> 6) & 0x3FU)).to_byte())
      buf.push((0x80U | (cp & 0x3FU)).to_byte())
    } else if cp <= 0x10FFFFU {
      buf.push((0xF0U | (cp >> 18)).to_byte())
      buf.push((0x80U | ((cp >> 12) & 0x3FU)).to_byte())
      buf.push((0x80U | ((cp >> 6) & 0x3FU)).to_byte())
      buf.push((0x80U | (cp & 0x3FU)).to_byte())
    }
  }
  Bytes::from_array(buf)
}

///|
fn to_hex_512(bytes : Bytes) -> String {
  let buf = StringBuilder()
  let n = bytes.length()
  for i in 0..<n {
    let b = bytes[i].to_int()
    buf.write_char(hex_digits_512[(b >> 4) & 0xF])
    buf.write_char(hex_digits_512[b & 0xF])
  }
  buf.to_string()
}

///|
/// Compute the SHA-512 digest of `data`, returning the raw 64-byte hash.
pub fn sha512(data : Bytes) -> Bytes {
  let data_len = data.length()
  let bit_len = data_len.to_uint64() << 3
  // Padded length: smallest multiple of 128 that fits data + 0x80 + 16 length bytes.
  let padded_len = (data_len + 17 + 127) / 128 * 128
  let msg = FixedArray::make(padded_len, b'\x00')
  for i in 0..<data_len {
    msg[i] = data[i]
  }
  msg[data_len] = b'\x80'
  // 128-bit big-endian length. High 64 bits are always 0 for practical inputs
  // (data length fits in Int, so bit_len < 2^34). The msg array is already
  // zero-initialized, so we only need to write the low 64 bits.
  let lo = bit_len
  // Store low 64 bits (bytes [padded_len-8 .. padded_len-1])
  msg[padded_len - 8] = (lo >> 56).to_byte()
  msg[padded_len - 7] = (lo >> 48).to_byte()
  msg[padded_len - 6] = (lo >> 40).to_byte()
  msg[padded_len - 5] = (lo >> 32).to_byte()
  msg[padded_len - 4] = (lo >> 24).to_byte()
  msg[padded_len - 3] = (lo >> 16).to_byte()
  msg[padded_len - 2] = (lo >> 8).to_byte()
  msg[padded_len - 1] = lo.to_byte()
  let state : FixedArray[UInt64] = FixedArray::make(8, 0UL)
  for i in 0..<8 {
    state[i] = h512_init[i]
  }
  let mut offset = 0
  while offset < padded_len {
    compress512(state, msg, offset)
    offset = offset + 128
  }
  Bytes::makei(64, i => {
    let word = state[i / 8]
    let shift = (7 - i % 8) * 8
    (word >> shift).to_byte()
  })
}

///|
/// Compute the SHA-512 digest of `data` and return it as a 128-character
/// lowercase hexadecimal string.
pub fn sha512_hex(data : Bytes) -> String {
  to_hex_512(sha512(data))
}

///|
/// Compute the SHA-512 digest of the UTF-8 encoding of `text`.
pub fn sha512_string(text : String) -> String {
  sha512_hex(utf8_bytes_512(text))
}

// ---------------------------------------------------------------------------
// Tests — NIST FIPS 180-4 test vectors
// ---------------------------------------------------------------------------

///|
test "sha512: empty string (NIST)" {
  assert_eq(
    sha512_hex(b""),
    "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e",
  )
}

///|
test "sha512: \"abc\" (NIST)" {
  assert_eq(
    sha512_hex(b"abc"),
    "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f",
  )
}

///|
test "sha512: string API matches bytes API" {
  let s = "Hello, World!"
  assert_eq(sha512_string(s), sha512_hex(b"Hello, World!"))
}

///|
test "sha512: raw digest length" {
  let raw = sha512(b"test")
  assert_eq(raw.length(), 64)
}
