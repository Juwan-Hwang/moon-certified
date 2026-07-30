/// GZIP Container Format (RFC 1952).
///
/// A production-grade GZIP encoder and decoder that wraps DEFLATE
/// compressed data with the standard GZIP header and trailer.
///
/// ## Format
///
/// ```text
/// +---+---+---+---+=============================+---+---+---+---+
/// |ID1|ID2|CM |FLG|     MTIME(4) XFL OS           |     DEFLATE  |
/// +---+---+---+---+=============================+---+---+---+---+
/// ... (optional FEXTRA, FNAME, FCOMMENT, FHCRC) ...
/// +=============================+---+---+---+---+---+---+---+---+
/// |          DEFLATE data       |          CRC32(4)    |  ISIZE(4) |
/// +=============================+---+---+---+---+---+---+---+---+
/// ```
///
/// - **ID1, ID2**: Magic bytes 0x1f, 0x8b.
/// - **CM**: Compression method (8 = DEFLATE).
/// - **FLG**: Flags byte (this implementation uses FLG=0, no optional fields).
/// - **MTIME**: Modification time (0 = not set).
/// - **XFL**: Extra flags (0 = default).
/// - **OS**: Operating system (255 = unknown).
/// - **CRC32**: CRC-32 (ISO-HDLC) of the **uncompressed** data.
/// - **ISIZE**: Uncompressed size modulo 2^32.
///
/// ## References
///
/// - Deutsch, P. "GZIP file format specification version 4.3", RFC 1952, 1996.
/// - Deutsch, P. "DEFLATE Compressed Data Format Specification version 1.3",
///   RFC 1951, 1996.
///
/// Not formally verified. Correctness is ensured by the test suite.

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

///|
/// GZIP magic byte 1.
const GZIP_ID1 : Byte = b'\x1f'

///|
/// GZIP magic byte 2.
const GZIP_ID2 : Byte = b'\x8b'

///|
/// Compression method: DEFLATE.
const GZIP_CM_DEFLATE : Byte = b'\x08'

///|
/// Flag: no optional fields.
const GZIP_FLG_NONE : Byte = b'\x00'

///|
/// Extra flags: default compression.
const GZIP_XFL_DEFAULT : Byte = b'\x00'

///|
/// Operating system: unknown.
const GZIP_OS_UNKNOWN : Byte = b'\xFF'

///|
/// GZIP header size in bytes (10 bytes: ID1, ID2, CM, FLG, MTIME(4), XFL, OS).
const GZIP_HEADER_SIZE : Int = 10

///|
/// GZIP trailer size in bytes (8 bytes: CRC32(4), ISIZE(4)).
const GZIP_TRAILER_SIZE : Int = 8

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

///|
/// Write a 32-bit unsigned integer in little-endian to a byte buffer.
fn write_u32_le(buf : Array[Byte], val : UInt) -> Unit {
  buf.push((val & 0xFFU).to_byte())
  buf.push(((val >> 8) & 0xFFU).to_byte())
  buf.push(((val >> 16) & 0xFFU).to_byte())
  buf.push(((val >> 24) & 0xFFU).to_byte())
}

///|
/// Read a 32-bit unsigned integer in little-endian from bytes.
fn read_u32_le(data : Bytes, pos : Int) -> UInt {
  (data[pos].to_uint()) |
  (data[pos + 1].to_uint() << 8) |
  (data[pos + 2].to_uint() << 16) |
  (data[pos + 3].to_uint() << 24)
}

///|
/// Convert `Bytes` to `FixedArray[Byte]` for CRC computation.
fn bytes_to_fixed(b : Bytes) -> FixedArray[Byte] {
  let n = b.length()
  let fa = FixedArray::make(n, b'\x00')
  for i = 0; i < n; i = i + 1 {
    fa[i] = b[i]
  }
  fa
}

// ---------------------------------------------------------------------------
// Public API: Compression
// ---------------------------------------------------------------------------

///|
/// Compress data into GZIP format (RFC 1952).
///
/// Wraps the input with a GZIP header (10 bytes), DEFLATE-compresses the
/// data, and appends a CRC-32 + original-size trailer (8 bytes).
///
/// Returns the GZIP-compressed bytes. For empty input, returns a valid
/// GZIP stream containing zero bytes of data.
pub fn gzip_compress(data : Bytes) -> Bytes {
  let output : Array[Byte] = []
  // --- Header (10 bytes) ---
  output.push(GZIP_ID1)
  output.push(GZIP_ID2)
  output.push(GZIP_CM_DEFLATE)
  output.push(GZIP_FLG_NONE)
  // MTIME = 0 (4 bytes, little-endian)
  output.push(b'\x00')
  output.push(b'\x00')
  output.push(b'\x00')
  output.push(b'\x00')
  output.push(GZIP_XFL_DEFAULT)
  output.push(GZIP_OS_UNKNOWN)
  // --- DEFLATE compressed data ---
  let deflated = @deflate.deflate(data)
  for i = 0; i < deflated.length(); i = i + 1 {
    output.push(deflated[i])
  }
  // --- Trailer (8 bytes) ---
  // CRC-32 of the original (uncompressed) data.
  let crc = @crc.crc32(bytes_to_fixed(data))
  write_u32_le(output, crc)
  // ISIZE: original size mod 2^32.
  let isize = (data.length().reinterpret_as_uint() & 0xFFFFFFFFU)
  write_u32_le(output, isize)
  Bytes::from_array(output)
}

// ---------------------------------------------------------------------------
// Public API: Decompression
// ---------------------------------------------------------------------------

///|
/// Decompress GZIP-format data (RFC 1952).
///
/// Validates the GZIP header, inflates the DEFLATE stream, and verifies
/// the CRC-32 and size trailer.
///
/// Returns `Some(data)` on success, or `None` if:
/// - The header is invalid (wrong magic, unsupported CM).
/// - The DEFLATE stream is corrupt.
/// - The CRC-32 does not match.
/// - The ISIZE does not match the decompressed size.
pub fn gzip_decompress(data : Bytes) -> Bytes? {
  let n = data.length()
  // Minimum valid GZIP: 10-byte header + DEFLATE + 8-byte trailer.
  if n < GZIP_HEADER_SIZE + GZIP_TRAILER_SIZE {
    return None
  }
  // --- Validate header ---
  if data[0] != GZIP_ID1 || data[1] != GZIP_ID2 {
    return None
  }
  if data[2] != GZIP_CM_DEFLATE {
    return None // Only DEFLATE (CM=8) is supported.
  }
  let flg = data[3].to_int()
  let mut pos = GZIP_HEADER_SIZE
  // --- Parse optional fields based on FLG ---
  // FEXTRA (bit 2)
  if (flg & 0x04) != 0 {
    if pos + 2 > n {
      return None
    }
    let xlen = data[pos].to_int() | (data[pos + 1].to_int() << 8)
    pos = pos + 2 + xlen
    if pos > n {
      return None
    }
  }
  // FNAME (bit 3): zero-terminated string
  if (flg & 0x08) != 0 {
    let mut found = false
    while pos < n {
      if data[pos] == b'\x00' {
        pos = pos + 1
        found = true
        break
      }
      pos = pos + 1
    }
    if !found {
      return None
    }
  }
  // FCOMMENT (bit 4): zero-terminated string
  if (flg & 0x10) != 0 {
    let mut found = false
    while pos < n {
      if data[pos] == b'\x00' {
        pos = pos + 1
        found = true
        break
      }
      pos = pos + 1
    }
    if !found {
      return None
    }
  }
  // FHCRC (bit 1): 2-byte header CRC
  if (flg & 0x02) != 0 {
    if pos + 2 > n {
      return None
    }
    pos = pos + 2
  }
  // --- Extract DEFLATE data ---
  // The trailer is the last 8 bytes.
  let trailer_start = n - GZIP_TRAILER_SIZE
  if pos > trailer_start {
    return None
  }
  let deflate_data : Array[Byte] = []
  for i = pos; i < trailer_start; i = i + 1 {
    deflate_data.push(data[i])
  }
  // --- Inflate ---
  let inflated = match @deflate.inflate(Bytes::from_array(deflate_data)) {
    None => return None
    Some(d) => d
  }
  // --- Verify CRC-32 ---
  let expected_crc = read_u32_le(data, trailer_start)
  let actual_crc = @crc.crc32(bytes_to_fixed(inflated))
  if actual_crc != expected_crc {
    return None
  }
  // --- Verify ISIZE ---
  let expected_size = read_u32_le(data, trailer_start + 4)
  let actual_size = inflated.length().reinterpret_as_uint() & 0xFFFFFFFFU
  if actual_size != expected_size {
    return None
  }
  Some(inflated)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "gzip: empty data round-trip" {
  let input = Bytes::make(0, b'\x00')
  let compressed = gzip_compress(input)
  let decompressed = match gzip_decompress(compressed) {
    None => fail("decompression failed")
    Some(d) => d
  }
  assert_eq(decompressed.length(), 0)
}

///|
test "gzip: short text round-trip" {
  let input = @utils.string_to_bytes("Hello, GZIP World!")
  let compressed = gzip_compress(input)
  // Verify header magic.
  assert_eq(compressed[0], b'\x1f')
  assert_eq(compressed[1], b'\x8b')
  assert_eq(compressed[2], b'\x08')
  let decompressed = match gzip_decompress(compressed) {
    None => fail("decompression failed")
    Some(d) => d
  }
  assert_eq(decompressed.length(), input.length())
  for i = 0; i < input.length(); i = i + 1 {
    assert_eq(decompressed[i], input[i])
  }
}

///|
test "gzip: repetitive data round-trip" {
  let input = Bytes::make(1000, b'\x41')
  let compressed = gzip_compress(input)
  // Compressed should be smaller for repetitive data.
  assert_true(compressed.length() < input.length())
  let decompressed = match gzip_decompress(compressed) {
    None => fail("decompression failed")
    Some(d) => d
  }
  assert_eq(decompressed.length(), input.length())
  for i = 0; i < input.length(); i = i + 1 {
    assert_eq(decompressed[i], input[i])
  }
}

///|
test "gzip: binary data round-trip" {
  let arr : Array[Byte] = []
  for i = 0; i < 256; i = i + 1 {
    arr.push(i.to_byte())
  }
  let input = Bytes::from_array(arr)
  let compressed = gzip_compress(input)
  let decompressed = match gzip_decompress(compressed) {
    None => fail("decompression failed")
    Some(d) => d
  }
  assert_eq(decompressed.length(), input.length())
  for i = 0; i < input.length(); i = i + 1 {
    assert_eq(decompressed[i], input[i])
  }
}

///|
test "gzip: unicode text round-trip" {
  let input = @utils.string_to_bytes("日本語テスト αβγδ 🚀🎉")
  let compressed = gzip_compress(input)
  let decompressed = match gzip_decompress(compressed) {
    None => fail("decompression failed")
    Some(d) => d
  }
  assert_eq(decompressed.length(), input.length())
  for i = 0; i < input.length(); i = i + 1 {
    assert_eq(decompressed[i], input[i])
  }
}

///|
test "gzip: invalid magic returns None" {
  let bad = Bytes::from_array([b'\x00', b'\x00', b'\x08', b'\x00'])
  assert_true(gzip_decompress(bad) is None)
}

///|
test "gzip: truncated data returns None" {
  let input = Bytes::make(10, b'\x41')
  let compressed = gzip_compress(input)
  // Truncate by removing the trailer.
  let truncated = Bytes::from_array(
    Array::makei(compressed.length() - 4, fn(i) { compressed[i] }),
  )
  assert_true(gzip_decompress(truncated) is None)
}

///|
test "gzip: CRC mismatch returns None" {
  let input = Bytes::make(10, b'\x41')
  let compressed = gzip_compress(input)
  // Corrupt the CRC (4 bytes before the last 4 bytes = ISIZE).
  let corrupt : Array[Byte] = []
  for i = 0; i < compressed.length(); i = i + 1 {
    if i == compressed.length() - 8 {
      corrupt.push(b'\xFF')
    } else {
      corrupt.push(compressed[i])
    }
  }
  assert_true(gzip_decompress(Bytes::from_array(corrupt)) is None)
}

///|
test "gzip: large data round-trip" {
  let arr : Array[Byte] = []
  for r = 0; r < 100; r = r + 1 {
    for i = 0; i < 256; i = i + 1 {
      arr.push(i.to_byte())
    }
  }
  let input = Bytes::from_array(arr)
  let compressed = gzip_compress(input)
  assert_true(compressed.length() < input.length())
  let decompressed = match gzip_decompress(compressed) {
    None => fail("decompression failed")
    Some(d) => d
  }
  assert_eq(decompressed.length(), input.length())
  for i = 0; i < input.length(); i = i + 1 {
    assert_eq(decompressed[i], input[i])
  }
}
