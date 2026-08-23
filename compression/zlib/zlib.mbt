/// ZLIB Container Format (RFC 1950).
///
/// A production-grade ZLIB encoder and decoder that wraps DEFLATE
/// compressed data with a minimal header and Adler-32 checksum.
///
/// ## Format
///
/// ```text
/// +---+---+=============================+---+---+---+---+
/// |CMF|FLG|     DEFLATE compressed data |    ADLER32    |
/// +---+---+=============================+---+---+---+---+
/// ```
///
/// - **CMF**: Compression Method and Flags. Low 4 bits = CM (8 = DEFLATE),
///   high 4 bits = CINFO (7 = 32K window).
/// - **FLG**: Flags byte. Bits 0-4 = FCHECK (makes CMF*256+FLG divisible by
///   31), bit 5 = FDICT (0 = no dictionary), bits 6-7 = FLEVEL (0 = fastest).
/// - **ADLER32**: Adler-32 checksum of the **uncompressed** data (big-endian).
///
/// ## References
///
/// - Deutsch, P. and Gailly, J-L. "ZLIB Compressed Data Format Specification
///   version 3.3", RFC 1950, 1996.
/// - Deutsch, P. "DEFLATE Compressed Data Format Specification version 1.3",
///   RFC 1951, 1996.
///
/// Not formally verified. Correctness is ensured by the test suite.

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

///|
/// CMF byte: CM=8 (DEFLATE), CINFO=7 (32K window) → 0x78.
const ZLIB_CMF : Byte = b'\x78'

///|
/// FLG byte: FLEVEL=0, FDICT=0, FCHECK=9 → (0x78 * 256 + FLG) % 31 == 0.
/// 0x7800 % 31 = 0, so FCHECK = 0 works. We use FCHECK=1 (FLG=0x01) to
/// match the common "fastest" compression level marker used by zlib.
/// (0x78 * 256 + 0x01) = 30721, 30721 % 31 = 0. ✓
const ZLIB_FLG : Byte = b'\x01'

// ---------------------------------------------------------------------------
// Adler-32 checksum (RFC 1950 §8)
// ---------------------------------------------------------------------------

///|
/// Compute the Adler-32 checksum of `data`.
///
/// The Adler-32 checksum consists of two 16-bit modular sums:
/// - `s1` = 1 + sum of all bytes, mod 65521
/// - `s2` = sum of all `s1` values, mod 65521
///
/// The result is `(s2 << 16) | s1`, a 32-bit unsigned value stored big-endian
/// in the zlib trailer.
///
/// ## Complexity
///
/// O(n) where n = data.length(). The loop processes one byte at a time,
/// reducing mod 65521 at most every 5552 bytes (the largest N such that
/// 5552 × 255 < 2^32 − 65521), avoiding overflow in 32-bit arithmetic.
pub fn adler32(data : Bytes) -> UInt {
  let mut s1 : UInt = 1U
  let mut s2 : UInt = 0U
  let modulus : UInt = 65521U
  let block_size : Int = 5552 // Max bytes before s2 could overflow 32 bits
  let mut i = 0
  while i < data.length() {
    let end = if i + block_size < data.length() {
      i + block_size
    } else {
      data.length()
    }
    while i < end {
      s1 = (s1 + data[i].to_uint()) % modulus
      s2 = (s2 + s1) % modulus
      i = i + 1
    }
  }
  (s2 << 16) | s1
}

// ---------------------------------------------------------------------------
// ZLIB compression
// ---------------------------------------------------------------------------

///|
/// Compress `data` into a ZLIB stream (RFC 1950).
///
/// The output is: CMF(1) + FLG(1) + DEFLATE(n) + ADLER32(4).
///
/// Returns the compressed byte array, or `None` if compression fails
/// (indicates an internal DEFLATE error — should not occur for valid input).
pub fn compress(data : Bytes) -> Bytes? {
  let deflated = @deflate.deflate(data)
  let checksum = adler32(data)
  let result : Array[Byte] = []
  result.push(ZLIB_CMF)
  result.push(ZLIB_FLG)
  for i = 0; i < deflated.length(); i = i + 1 {
    result.push(deflated[i])
  }
  // Adler-32 in big-endian
  result.push(((checksum >> 24) & 0xFFU).to_byte())
  result.push(((checksum >> 16) & 0xFFU).to_byte())
  result.push(((checksum >> 8) & 0xFFU).to_byte())
  result.push((checksum & 0xFFU).to_byte())
  Some(Bytes::from_array(result))
}

///|
/// Decompress a ZLIB stream (RFC 1950).
///
/// Validates the header, inflates the DEFLATE data, and verifies the
/// Adler-32 checksum. Returns `None` if the stream is corrupt, the
/// checksum does not match, or the compression method is unsupported.
pub fn decompress(data : Bytes) -> Bytes? {
  // Minimum: 2-byte header + 4-byte Adler-32 = 6 bytes.
  if data.length() < 6 {
    return None
  }
  let cmf = data[0]
  let flg = data[1]
  // Check compression method (low 4 bits of CMF): must be 8 (DEFLATE).
  if (cmf & 0x0F) != b'\x08' {
    return None
  }
  // Check CINFO (high 4 bits of CMF): must be ≤ 7.
  if cmf >> 4 > b'\x07' {
    return None
  }
  // Check FCHECK: (CMF * 256 + FLG) must be divisible by 31.
  let check_val = cmf.to_int() * 256 + flg.to_int()
  if check_val % 31 != 0 {
    return None
  }
  // Check FDICT (bit 5 of FLG): not supported.
  if (flg & 0x20) != b'\x00' {
    return None
  }
  // Extract DEFLATE data (between header and 4-byte Adler-32 trailer).
  let deflate_arr : Array[Byte] = Array::make(data.length() - 6, b'\x00')
  for i = 0; i < data.length() - 6; i = i + 1 {
    deflate_arr[i] = data[2 + i]
  }
  let deflate_data = Bytes::from_array(deflate_arr)
  // Inflate.
  let inflated = match @deflate.inflate(deflate_data) {
    None => return None
    Some(d) => d
  }
  // Extract and verify Adler-32 trailer (big-endian).
  let trailer_offset = data.length() - 4
  let expected : UInt = (data[trailer_offset].to_uint() << 24) |
    (data[trailer_offset + 1].to_uint() << 16) |
    (data[trailer_offset + 2].to_uint() << 8) |
    data[trailer_offset + 3].to_uint()
  let actual = adler32(inflated)
  if expected != actual {
    return None
  }
  Some(inflated)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "zlib: adler32 known vectors" {
  // RFC 1950 / Wikipedia test vectors
  assert_eq(adler32(Bytes::make(0, b'\x00')), 1U)
  // "a" → s1=98, s2=98 → (98 << 16) | 98 = 0x00620062
  let a = Bytes::make(1, b'\x61')
  assert_eq(adler32(a), 0x00620062U)
  // "abc" → s1=295, s2=589 → (589 << 16) | 295 = 0x024d0127
  let abc = @utils.string_to_bytes("abc")
  assert_eq(adler32(abc), 0x024d0127U)
}

///|
test "zlib: compress and decompress round-trip" {
  let data = @utils.string_to_bytes(
    "Hello, ZLIB! This is a test of zlib compression.",
  )
  let compressed = match compress(data) {
    None => fail("compression failed")
    Some(c) => c
  }
  // Compressed should have 2-byte header + DEFLATE + 4-byte Adler-32
  assert_true(compressed.length() >= 6)
  assert_eq(compressed[0], ZLIB_CMF)
  assert_eq(compressed[1], ZLIB_FLG)
  let decompressed = match decompress(compressed) {
    None => fail("decompression failed")
    Some(d) => d
  }
  assert_eq(decompressed.length(), data.length())
  for i = 0; i < data.length(); i = i + 1 {
    assert_eq(decompressed[i], data[i])
  }
}

///|
test "zlib: round-trip empty data" {
  let data = Bytes::make(0, b'\x00')
  let compressed = match compress(data) {
    None => fail("compression failed")
    Some(c) => c
  }
  let decompressed = match decompress(compressed) {
    None => fail("decompression failed")
    Some(d) => d
  }
  assert_eq(decompressed.length(), 0)
}

///|
test "zlib: round-trip large repetitive data" {
  // 10KB of repetitive data — should compress well
  let data = Bytes::make(10000, b'\x41')
  let compressed = match compress(data) {
    None => fail("compression failed")
    Some(c) => c
  }
  assert_true(compressed.length() < data.length())
  let decompressed = match decompress(compressed) {
    None => fail("decompression failed")
    Some(d) => d
  }
  assert_eq(decompressed.length(), data.length())
  for i = 0; i < data.length(); i = i + 1 {
    assert_eq(decompressed[i], data[i])
  }
}

///|
test "zlib: corrupt header rejected" {
  let data = @utils.string_to_bytes("test")
  let compressed = compress(data).unwrap()
  // Corrupt the CMF byte
  let bad : Array[Byte] = []
  bad.push(b'\x00') // Wrong CM
  bad.push(compressed[1])
  for i = 2; i < compressed.length(); i = i + 1 {
    bad.push(compressed[i])
  }
  assert_true(decompress(Bytes::from_array(bad)) is None)
}

///|
test "zlib: corrupt checksum rejected" {
  let data = @utils.string_to_bytes("test data for checksum")
  let compressed = compress(data).unwrap()
  // Corrupt the last byte (Adler-32)
  let bad : Array[Byte] = []
  for i = 0; i < compressed.length() - 1; i = i + 1 {
    bad.push(compressed[i])
  }
  bad.push(b'\x00') // Wrong checksum byte
  assert_true(decompress(Bytes::from_array(bad)) is None)
}

///|
test "zlib: FDICT not supported" {
  let data = @utils.string_to_bytes("test")
  let compressed = compress(data).unwrap()
  // Set FDICT bit
  let bad : Array[Byte] = []
  bad.push(compressed[0])
  bad.push(compressed[1] | b'\x20')
  for i = 2; i < compressed.length(); i = i + 1 {
    bad.push(compressed[i])
  }
  assert_true(decompress(Bytes::from_array(bad)) is None)
}
