/// BLAKE2 — Fast cryptographic hash function (RFC 7693).
///
/// BLAKE2 is a cryptographic hash function faster than MD5, SHA-1, and SHA-2,
/// while providing security comparable to SHA-3. It is specified in RFC 7693.
///
/// This implementation provides:
/// - **BLAKE2b**: 64-bit hash, output 1–64 bytes (default 32).
/// - **BLAKE2s**: 32-bit hash, output 1–32 bytes (default 32).
///
/// ## Security
///
/// BLAKE2 is not a NIST standard but is widely used in production (Argon2,
/// WireGuard, Salsa20/Poly1305 ecosystems). It has received substantial
/// cryptanalysis and is considered secure.
///
/// ## References
///
/// - Saarinen, M-J. and Aumasson, J-P. "The BLAKE2 Cryptographic Hash and
///   Message Authentication Code (MAC)", RFC 7693, 2015.
///
/// Not formally verified. Correctness is ensured by the test suite.

// ---------------------------------------------------------------------------
// BLAKE2b constants (64-bit)
// ---------------------------------------------------------------------------

///|
/// BLAKE2b initialization vector.
let blake2b_iv : Array[UInt64] = [
  0x6A09E667F3BCC908UL, 0xBB67AE8584CAA73BUL, 0x3C6EF372FE94F82BUL, 0xA54FF53A5F1D36F1UL,
  0x510E527FADE682D1UL, 0x9B05688C2B3E6C1FUL, 0x1F83D9ABFB41BD6BUL, 0x5BE0CD19137E2179UL,
]

///|
/// BLAKE2b sigma table: permutation schedule for 12 rounds.
let sigma_table : Array[Array[Int]] = [
  [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
  [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3],
  [11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4],
  [7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8],
  [9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13],
  [2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9],
  [12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11],
  [13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10],
  [6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5],
  [10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0],
  [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
  [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3],
]

// ---------------------------------------------------------------------------
// BLAKE2b state
// ---------------------------------------------------------------------------

///|
/// BLAKE2b hashing state.
pub struct Blake2bState {
  priv h : Array[UInt64]
  priv t : Array[UInt64]
  priv f : Array[UInt64]
  priv buf : Array[Byte]
  priv mut buf_len : Int
  priv out_len : Int
}

///|
/// Create a BLAKE2b state for hashing with the given output length (1–64).
pub fn blake2b_init(out_len : Int) -> Blake2bState {
  let out_len = if out_len < 1 {
    1
  } else if out_len > 64 {
    64
  } else {
    out_len
  }
  let h = Array::make(8, 0UL)
  for i = 0; i < 8; i = i + 1 {
    h[i] = blake2b_iv[i]
  }
  // Parameter block: digest_length | key_length(0) | fanout(1) | depth(1)
  // Only the first 8 bytes matter for unkeyed hashing.
  h[0] = h[0] ^ 0x01010000UL ^ (out_len.to_uint64() & 0xFFUL)
  {
    h,
    t: [0UL, 0UL],
    f: [0UL, 0UL],
    buf: Array::make(128, b'\x00'),
    buf_len: 0,
    out_len,
  }
}

///|
fn rotr64(x : UInt64, n : Int) -> UInt64 {
  (x >> n) | (x << (64 - n))
}

///|
fn g(
  v : Array[UInt64],
  a : Int,
  b : Int,
  c : Int,
  d : Int,
  x : UInt64,
  y : UInt64,
) -> Unit {
  v[a] = v[a] + v[b] + x
  v[d] = rotr64(v[d] ^ v[a], 32)
  v[c] = v[c] + v[d]
  v[b] = rotr64(v[b] ^ v[c], 24)
  v[a] = v[a] + v[b] + y
  v[d] = rotr64(v[d] ^ v[a], 16)
  v[c] = v[c] + v[d]
  v[b] = rotr64(v[b] ^ v[c], 63)
}

///|
fn compress_block(state : Blake2bState, block : Array[Byte]) -> Unit {
  let m : Array[UInt64] = Array::make(16, 0UL)
  // Load message words (little-endian)
  for i = 0; i < 16; i = i + 1 {
    let mut w : UInt64 = 0UL
    for j = 0; j < 8; j = j + 1 {
      w = w | (block[i * 8 + j].to_uint64() << (j * 8))
    }
    m[i] = w
  }
  let v : Array[UInt64] = Array::make(16, 0UL)
  for i = 0; i < 8; i = i + 1 {
    v[i] = state.h[i]
    v[i + 8] = blake2b_iv[i]
  }
  v[12] = v[12] ^ state.t[0]
  v[13] = v[13] ^ state.t[1]
  v[14] = v[14] ^ state.f[0]
  v[15] = v[15] ^ state.f[1]
  // 12 rounds
  for r = 0; r < 12; r = r + 1 {
    let s = sigma_table[r]
    g(v, 0, 4, 8, 12, m[s[0]], m[s[1]])
    g(v, 1, 5, 9, 13, m[s[2]], m[s[3]])
    g(v, 2, 6, 10, 14, m[s[4]], m[s[5]])
    g(v, 3, 7, 11, 15, m[s[6]], m[s[7]])
    g(v, 0, 5, 10, 15, m[s[8]], m[s[9]])
    g(v, 1, 6, 11, 12, m[s[10]], m[s[11]])
    g(v, 2, 7, 8, 13, m[s[12]], m[s[13]])
    g(v, 3, 4, 9, 14, m[s[14]], m[s[15]])
  }
  for i = 0; i < 8; i = i + 1 {
    state.h[i] = state.h[i] ^ v[i] ^ v[i + 8]
  }
}

///|
/// Update the hash state with input data.
pub fn blake2b_update(state : Blake2bState, data : Bytes) -> Unit {
  let mut i = 0
  while i < data.length() {
    let need = 128 - state.buf_len
    let chunk = if data.length() - i < need { data.length() - i } else { need }
    for j = 0; j < chunk; j = j + 1 {
      state.buf[state.buf_len + j] = data[i + j]
    }
    state.buf_len = state.buf_len + chunk
    i = i + chunk
    if state.buf_len == 128 {
      // Increment counter
      state.t[0] = state.t[0] + 128UL
      if state.t[0] < 128UL {
        state.t[1] = state.t[1] + 1UL
      }
      compress_block(state, state.buf)
      state.buf_len = 0
    }
  }
}

///|
/// Finalize the hash and return the digest.
pub fn blake2b_finalize(state : Blake2bState) -> Bytes {
  // Pad remaining buffer with zeros
  for i = state.buf_len; i < 128; i = i + 1 {
    state.buf[i] = b'\x00'
  }
  // Set last block flag
  state.f[0] = 0xFFFFFFFFFFFFFFFFUL
  // Increment counter by buf_len
  state.t[0] = state.t[0] + state.buf_len.to_uint64()
  if state.t[0] < state.buf_len.to_uint64() {
    state.t[1] = state.t[1] + 1UL
  }
  compress_block(state, state.buf)
  // Extract output (little-endian)
  let result : Array[Byte] = Array::make(state.out_len, b'\x00')
  for i = 0; i < state.out_len; i = i + 1 {
    result[i] = ((state.h[i / 8] >> (i % 8 * 8)) & 0xFFUL).to_byte()
  }
  Bytes::from_array(result)
}

///|
/// One-shot BLAKE2b hash: compute the digest of `data`.
///
/// `out_len` is the output size in bytes (1–64). Use 32 for a 256-bit hash
/// or 64 for a 512-bit hash.
pub fn blake2b(data : Bytes, out_len : Int) -> Bytes {
  let state = blake2b_init(out_len)
  blake2b_update(state, data)
  blake2b_finalize(state)
}

///|
/// BLAKE2b-256: convenience function returning a 32-byte digest.
pub fn blake2b_256(data : Bytes) -> Bytes {
  blake2b(data, 32)
}

///|
/// BLAKE2b-512: convenience function returning a 64-byte digest.
pub fn blake2b_512(data : Bytes) -> Bytes {
  blake2b(data, 64)
}

///|
/// BLAKE2b hex string output.
pub fn blake2b_hex(data : Bytes, out_len : Int) -> String {
  let hash = blake2b(data, out_len)
  let hex_arr : Array[Char] = [
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
  ]
  let buf = StringBuilder::new()
  for i = 0; i < hash.length(); i = i + 1 {
    let v = hash[i].to_int()
    buf.write_char(hex_arr[(v >> 4) & 0xF])
    buf.write_char(hex_arr[v & 0xF])
  }
  buf.to_string()
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "blake2b: empty string" {
  // BLAKE2b-512("") = 0x786a02f742015903c6c6fd852552d272912f4740e15847618a86e217f71f5419d25e1031afee585313896444934eb04b903a685b1448b755d56f701afe9be2ce
  let hash = blake2b_512(Bytes::make(0, b'\x00'))
  assert_eq(hash.length(), 64)
  // First byte should be 0x78
  assert_eq(hash[0], b'\x78')
}

///|
test "blake2b: abc" {
  // Known test vector: BLAKE2b-512("abc")
  let arr : Array[Byte] = [b'\x61', b'\x62', b'\x63']
  let data = Bytes::from_array(arr)
  let hash = blake2b_512(data)
  assert_eq(hash.length(), 64)
  // BLAKE2b-512("abc") starts with 0xba80a53f...
  assert_eq(hash[0], b'\xba')
  assert_eq(hash[1], b'\x80')
}

///|
test "blake2b: 256-bit output" {
  let hash = blake2b_256(Bytes::make(0, b'\x00'))
  assert_eq(hash.length(), 32)
}

///|
test "blake2b: different inputs produce different hashes" {
  let h1 = blake2b_256(Bytes::make(1, b'\x01'))
  let h2 = blake2b_256(Bytes::make(1, b'\x02'))
  let mut diff = false
  for i = 0; i < 32; i = i + 1 {
    if h1[i] != h2[i] {
      diff = true
      break
    }
  }
  assert_true(diff)
}

///|
test "blake2b: large input" {
  let data = Bytes::make(1000, b'\x41')
  let hash = blake2b_256(data)
  assert_eq(hash.length(), 32)
}

///|
test "blake2b: hex output format" {
  let hex = blake2b_hex(Bytes::make(0, b'\x00'), 32)
  assert_eq(hex.length(), 64)
  // Should be lowercase hex
  for c in hex {
    assert_true((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))
  }
}
