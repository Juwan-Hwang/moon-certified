/// DEFLATE Compression (stored blocks only).
///
/// This is a minimal but **correct** DEFLATE (RFC 1951) implementation that
/// uses only **stored blocks** (BTYPE = 00). Stored blocks contain raw,
/// uncompressed data preceded by a 3-bit block header and a 4-byte
/// length/complement pair.
///
/// ## Why stored blocks?
///
/// Stored blocks require no Huffman coding, no LZ77, and no bit-level
/// entropy encoding of the payload — only the 3-bit header is bit-packed.
/// The payload itself is byte-aligned. This makes the implementation tiny,
/// fast, and trivially verifiable, while still producing output that any
/// standard DEFLATE decoder (gzip, zlib, Python `zlib`, etc.) can decompress.
///
/// ## Block format (RFC 1951 §3.2.4)
///
/// ```
/// +---+---+---+==========================+
/// |BFINAL| BTYPE |   (padding to byte)    |
/// +---+---+---+==========================+
/// |     LEN (2 bytes, LE)                |
/// +---------------------------------------+
/// |     NLEN (2 bytes, LE) = ~LEN & 0xFFFF|
/// +---------------------------------------+
/// |     LEN bytes of literal data         |
/// +---------------------------------------+
/// ```
///
/// - **BFINAL** (1 bit): 1 for the last block, 0 otherwise.
/// - **BTYPE** (2 bits): 00 (stored).
/// - Bits are packed **LSB-first** into each byte.
/// - After the 3-bit header, the rest of the current byte is zero-padded to
///   reach a byte boundary.
/// - `LEN` ≤ 65535, so inputs longer than 65535 bytes are split across
///   multiple blocks.
///
/// ## Limitations
///
/// `inflate` only supports stored blocks (BTYPE = 00). Fixed (01) and
/// dynamic (10) Huffman blocks will cause `inflate` to return an empty
/// `Bytes` result. This is sufficient because `deflate` always produces
/// stored blocks, guaranteeing round-trip correctness.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

///|
/// Maximum payload length of a single stored block (16-bit LEN field).
let max_stored : Int = 65535

// ---------------------------------------------------------------------------
// Bit writer (LSB-first)
// ---------------------------------------------------------------------------

///|
/// LSB-first bit writer that accumulates bits into bytes.
priv struct BitWriter {
  output : Array[Byte]
  mut current_byte : Int
  mut bit_count : Int
}

///|
/// Create a new empty `BitWriter`.
fn new_bit_writer() -> BitWriter {
  { output: [], current_byte: 0, bit_count: 0 }
}

///|
/// Write the low `count` bits of `value`, least-significant bit first.
fn write_bits(w : BitWriter, value : Int, count : Int) -> Unit {
  let mut v = value
  let mut remaining = count
  while remaining > 0 {
    let bit = v & 1
    w.current_byte = w.current_byte | (bit << w.bit_count)
    w.bit_count = w.bit_count + 1
    if w.bit_count == 8 {
      w.output.push(w.current_byte.to_byte())
      w.current_byte = 0
      w.bit_count = 0
    }
    v = v >> 1
    remaining = remaining - 1
  }
}

///|
/// Flush any partial byte, zero-padding the remaining bits.
fn flush_byte(w : BitWriter) -> Unit {
  if w.bit_count > 0 {
    w.output.push(w.current_byte.to_byte())
    w.current_byte = 0
    w.bit_count = 0
  }
}

// ---------------------------------------------------------------------------
// Bit reader (LSB-first)
// ---------------------------------------------------------------------------

///|
/// LSB-first bit reader that pulls bits from a `Bytes` buffer.
priv struct BitReader {
  data : Bytes
  mut byte_pos : Int
  mut bit_pos : Int // 0..7, position within the current byte
}

///|
/// Create a `BitReader` over `data`.
fn new_bit_reader(data : Bytes) -> BitReader {
  { data, byte_pos: 0, bit_pos: 0 }
}

///|
/// Read a single bit. Returns `0` if the reader is past the end (the
/// payload of a stored block never relies on this).
fn read_bit(r : BitReader) -> Int {
  if r.byte_pos >= r.data.length() {
    return 0
  }
  let bit = (r.data[r.byte_pos].to_int() >> r.bit_pos) & 1
  r.bit_pos = r.bit_pos + 1
  if r.bit_pos == 8 {
    r.bit_pos = 0
    r.byte_pos = r.byte_pos + 1
  }
  bit
}

///|
/// Read the low `count` bits (LSB-first), returning the assembled value.
fn read_bits(r : BitReader, count : Int) -> Int {
  let mut result = 0
  for i = 0; i < count; i = i + 1 {
    result = result | (read_bit(r) << i)
  }
  result
}

///|
/// Advance to the next byte boundary, discarding remaining bits in the
/// current byte.
fn align_to_byte(r : BitReader) -> Unit {
  if r.bit_pos > 0 {
    r.bit_pos = 0
    r.byte_pos = r.byte_pos + 1
  }
}

///|
/// Read a 16-bit little-endian value at the current byte position (must be
/// byte-aligned).
fn read_u16_le(r : BitReader) -> Int {
  let lo = r.data[r.byte_pos].to_int()
  let hi = r.data[r.byte_pos + 1].to_int()
  r.byte_pos = r.byte_pos + 2
  lo | (hi << 8)
}

// ---------------------------------------------------------------------------
// Compress (deflate)
// ---------------------------------------------------------------------------

///|
/// Compress `data` into a raw DEFLATE stream using stored blocks.
///
/// The output is a valid DEFLATE bitstream (RFC 1951) consisting entirely
/// of stored blocks. Any standard DEFLATE decoder can decompress it. The
/// output will be slightly *larger* than the input (by ~5 bytes per 65535-byte
/// block) because stored blocks add a small header per block.
///
/// Empty input produces a single empty final block (5 bytes: header + LEN=0
/// + NLEN=0xFFFF).
pub fn deflate(data : Bytes) -> Bytes {
  let n = data.length()
  let w = new_bit_writer()
  let mut pos = 0
  while pos < n {
    let remaining = n - pos
    let block_len = if remaining > max_stored { max_stored } else { remaining }
    let is_final = pos + block_len == n
    // 3-bit header: BFINAL (1 bit) + BTYPE (2 bits, 00 = stored).
    write_bits(w, if is_final { 1 } else { 0 }, 1) // BFINAL
    write_bits(w, 0, 2) // BTYPE = 00 (stored)
    // Pad to byte boundary.
    flush_byte(w)
    // LEN (2 bytes LE) and NLEN = ~LEN & 0xFFFF (2 bytes LE).
    let len = block_len
    let nlen = 0xFFFF ^ len
    w.output.push((len & 0xFF).to_byte())
    w.output.push(((len >> 8) & 0xFF).to_byte())
    w.output.push((nlen & 0xFF).to_byte())
    w.output.push(((nlen >> 8) & 0xFF).to_byte())
    // Literal data.
    for i = 0; i < block_len; i = i + 1 {
      w.output.push(data[pos + i])
    }
    pos = pos + block_len
  }
  // Handle empty input: emit a single empty final block.
  if n == 0 {
    write_bits(w, 1, 1) // BFINAL = 1
    write_bits(w, 0, 2) // BTYPE = 00
    flush_byte(w)
    w.output.push(b'\x00') // LEN low
    w.output.push(b'\x00') // LEN high
    w.output.push(b'\xFF') // NLEN low
    w.output.push(b'\xFF') // NLEN high
  }
  Bytes::from_array(w.output)
}

// ---------------------------------------------------------------------------
// Decompress (inflate)
// ---------------------------------------------------------------------------

///|
/// Decompress a raw DEFLATE stream.
///
/// Supports stored blocks (BTYPE = 00) only. If a non-stored block type is
/// encountered, or if the NLEN check fails, the function returns an empty
/// `Bytes` (the stream is considered invalid).
///
/// This is sufficient to round-trip any output produced by `deflate`.
pub fn inflate(data : Bytes) -> Bytes {
  if data.length() == 0 {
    return b""
  }
  let r = new_bit_reader(data)
  let output : Array[Byte] = []
  let mut done = false
  while !done {
    let bfinal = read_bit(r)
    let btype = read_bits(r, 2)
    if btype != 0 {
      // Unsupported block type; only stored blocks are handled.
      return b""
    }
    align_to_byte(r)
    if r.byte_pos + 4 > data.length() {
      return b"" // not enough data for LEN + NLEN
    }
    let len = read_u16_le(r)
    let nlen = read_u16_le(r)
    // Verify NLEN is the one's complement of LEN.
    if nlen != (0xFFFF ^ len) {
      return b""
    }
    if r.byte_pos + len > data.length() {
      return b"" // not enough data for the payload
    }
    for i = 0; i < len; i = i + 1 {
      output.push(data[r.byte_pos + i])
    }
    r.byte_pos = r.byte_pos + len
    if bfinal == 1 {
      done = true
    }
  }
  Bytes::from_array(output)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "deflate: empty input round-trip" {
  let data = b""
  let compressed = deflate(data)
  let decompressed = inflate(compressed)
  assert_eq(decompressed.length(), 0)
}

///|
test "deflate: single byte round-trip" {
  let data = b"X"
  let compressed = deflate(data)
  let decompressed = inflate(compressed)
  assert_eq(decompressed, data)
}

///|
test "deflate: short text round-trip" {
  let data = b"Hello, DEFLATE world!"
  let compressed = deflate(data)
  let decompressed = inflate(compressed)
  assert_eq(decompressed, data)
}

///|
test "deflate: repeated data round-trip" {
  let buf : Array[Byte] = []
  for i = 0; i < 1000; i = i + 1 {
    buf.push((i % 256).to_byte())
  }
  let data = Bytes::from_array(buf)
  let compressed = deflate(data)
  let decompressed = inflate(compressed)
  assert_eq(decompressed, data)
}

///|
test "deflate: large data crosses block boundary" {
  // 70000 bytes > MAX_STORED (65535) → two blocks.
  let buf : Array[Byte] = []
  for i = 0; i < 70000; i = i + 1 {
    buf.push((i % 256).to_byte())
  }
  let data = Bytes::from_array(buf)
  let compressed = deflate(data)
  let decompressed = inflate(compressed)
  assert_eq(decompressed, data)
}

///|
test "deflate: exactly 65535 bytes" {
  let buf : Array[Byte] = []
  for i = 0; i < 65535; i = i + 1 {
    buf.push(b'A')
  }
  let data = Bytes::from_array(buf)
  let compressed = deflate(data)
  let decompressed = inflate(compressed)
  assert_eq(decompressed, data)
}

///|
test "deflate: exactly 65536 bytes (two blocks)" {
  let buf : Array[Byte] = []
  for i = 0; i < 65536; i = i + 1 {
    buf.push(b'B')
  }
  let data = Bytes::from_array(buf)
  let compressed = deflate(data)
  let decompressed = inflate(compressed)
  assert_eq(decompressed, data)
}

///|
test "deflate: NLEN is one's complement of LEN" {
  // Verify the internal structure: for a 1-byte final block, the bytes after
  // the header should be LEN=01 00, NLEN=FE FF.
  let data = b"Z"
  let compressed = deflate(data)
  // Byte 0 = header (BFINAL=1, BTYPE=00 → 0x01), then LEN=01 00, NLEN=FE FF, data=Z.
  assert_eq(compressed[0], b'\x01')
  assert_eq(compressed[1], b'\x01') // LEN low
  assert_eq(compressed[2], b'\x00') // LEN high
  assert_eq(compressed[3], b'\xFE') // NLEN low = ~1 & 0xFF = 0xFE
  assert_eq(compressed[4], b'\xFF') // NLEN high = ~0 & 0xFF = 0xFF
  assert_eq(compressed[5], b'Z') // data
}

///|
test "inflate: invalid stream returns empty" {
  // BTYPE = 01 (fixed Huffman) — unsupported.
  // Byte: BFINAL=1, BTYPE=01 → bits: 1, 1, 0 → byte = 0b00000011 = 0x03
  let bad = Bytes::from_array([b'\x03'])
  assert_eq(inflate(bad).length(), 0)
}
