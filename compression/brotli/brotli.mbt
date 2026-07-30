/// Brotli-inspired LZ77 compression — custom format (NOT RFC 7932 compatible).
///
/// **WARNING**: This is NOT a standard Brotli implementation. It does NOT produce
/// `.br` files that can be decompressed by the brotli command-line tool or any
/// RFC 7932 compliant decoder. The format uses a custom magic number and a
/// simplified LZ77+varint encoding without context modeling, Huffman coding,
/// or static dictionaries. Use this only for internal round-trip compression
/// within MoonBit.
///
/// For production Brotli compression, use the official `brotli` library via FFI.
///
/// ## Custom frame format
///
/// ```text
/// +--------+--------+--------+--------+
/// | Custom magic 0x424C424D ("MBLB")  |
/// +--------+--------+--------+--------+
/// | Content size (4 bytes, LE)        |
/// +--------+--------+--------+--------+
/// | Blocks...                         |
/// +--------+--------+--------+--------+
/// ```
///
/// Each block:
/// - 1 byte block type (0=raw, 1=compressed)
/// - 3 bytes block size (LE)
/// - Block data
///
/// Compressed blocks use LZ77 with a 4-byte minimum match and variable-
/// length offset/length encoding (varint).
///
/// ## Why not RFC 7932?
///
/// A full RFC 7932 implementation requires context modeling, Huffman coding
/// with custom alphabets, static dictionaries, insert-and-copy commands,
/// and window-based streaming. This simplified format only provides LZ77
/// match finding with varint serialization.
///
/// `proof-enabled` is `false`; correctness is backed by round-trip tests.

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

///|
/// Custom magic number: "MBLB" (MoonBit LZ Brotli-inspired).
/// Intentionally NOT 0xCEB22CF1 to avoid confusion with any existing format.
fn magic_bytes() -> Bytes {
  Bytes::from_array([b'\x4D', b'\x42', b'\x4C', b'\x42'])
}

///|
/// Minimum match length.
const MIN_MATCH : Int = 4

///|
/// Maximum offset.
const MAX_OFFSET : Int = 65535

///|
/// Hash table size.
const HASH_SIZE : Int = 16384

// ---------------------------------------------------------------------------
// LZ77 token types
// ---------------------------------------------------------------------------

priv enum Token {
  Literal(Byte)
  Match(Int, Int)
}

// ---------------------------------------------------------------------------
// Hash table and match finding
// ---------------------------------------------------------------------------

fn hash4(data : Bytes, pos : Int) -> Int {
  let h = (data[pos].to_int64() << 24) | (data[pos + 1].to_int64() << 16) | (data[pos + 2].to_int64() << 8) | data[pos + 3].to_int64()
  (((h * 2654435761L) >> 18) & (HASH_SIZE - 1).to_int64()).to_int()
}

fn find_match(data : Bytes, pos : Int, hash_table : Array[Int]) -> (Int, Int) {
  if pos + MIN_MATCH > data.length() {
    return (0, 0)
  }
  let h = hash4(data, pos)
  let candidate = hash_table[h]
  hash_table[h] = pos
  if candidate < 0 || pos - candidate > MAX_OFFSET {
    return (0, 0)
  }
  let mut len = 0
  let max_len = if data.length() - pos < 255 + MIN_MATCH { data.length() - pos } else { 255 + MIN_MATCH }
  while len < max_len && data[candidate + len] == data[pos + len] {
    len = len + 1
  }
  if len >= MIN_MATCH {
    (pos - candidate, len)
  } else {
    (0, 0)
  }
}

fn lz77_compress(data : Bytes) -> Array[Token] {
  let tokens : Array[Token] = []
  let n = data.length()
  if n == 0 {
    return tokens
  }
  let hash_table : Array[Int] = Array::make(HASH_SIZE, -1)
  let mut pos = 0
  while pos < n {
    if pos + MIN_MATCH <= n {
      let (offset, length) = find_match(data, pos, hash_table)
      if length >= MIN_MATCH {
        tokens.push(Match(offset, length))
        for i = 1; i < length && pos + i + MIN_MATCH <= n; i = i + 1 {
          let h = hash4(data, pos + i)
          hash_table[h] = pos + i
        }
        pos = pos + length
        continue
      }
    }
    tokens.push(Literal(data[pos]))
    pos = pos + 1
  }
  tokens
}

// ---------------------------------------------------------------------------
// Variable-length integer encoding
// ---------------------------------------------------------------------------

/// Encode a non-negative integer as a variable-length byte sequence.
/// Uses continuation bits: high bit = 1 means more bytes follow.
fn encode_varint(value : Int, output : Array[Byte]) -> Unit {
  let mut v = value
  while v >= 128 {
    output.push(((v & 0x7F) | 0x80).to_byte())
    v = v >> 7
  }
  output.push(v.to_byte())
}

/// Decode a varint. Returns (value, bytes_consumed) or None.
fn decode_varint(data : Bytes, pos : Int) -> (Int, Int)? {
  let mut result = 0
  let mut shift = 0
  let mut p = pos
  while p < data.length() {
    let b = data[p].to_int()
    p = p + 1
    result = result | ((b & 0x7F) << shift)
    if (b & 0x80) == 0 {
      return Some((result, p - pos))
    }
    shift = shift + 7
    if shift >= 35 {
      return None
    }
  }
  None
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

///|
/// Compress data using Brotli-inspired LZ77 compression.
///
/// **WARNING**: Output uses a custom magic number and is NOT compatible with
/// the standard Brotli format (RFC 7932). Do not write the output to `.br`
/// files expecting standard tools to decompress them.
pub fn compress(data : Bytes) -> Bytes {
  let output : Array[Byte] = []
  // Custom magic number (NOT 0xCEB22CF1)
  for i = 0; i < 4; i = i + 1 {
    output.push(magic_bytes()[i])
  }
  // Content size (4 bytes LE)
  let content_size = data.length()
  output.push((content_size & 0xFF).to_byte())
  output.push(((content_size >> 8) & 0xFF).to_byte())
  output.push(((content_size >> 16) & 0xFF).to_byte())
  output.push(((content_size >> 24) & 0xFF).to_byte())
  // Empty data
  if data.length() == 0 {
    output.push(b'\x00') // raw block
    output.push(b'\x00')
    output.push(b'\x00')
    output.push(b'\x00')
    return Bytes::from_array(output)
  }
  // LZ77 compress
  let tokens = lz77_compress(data)
  // Build compressed stream
  // Token encoding:
  //   Literal: [0x00] [byte]
  //   Match: [0x01] [varint offset] [varint length-MIN_MATCH]
  let compressed_stream : Array[Byte] = []
  for i = 0; i < tokens.length(); i = i + 1 {
    match tokens[i] {
      Literal(b) => {
        compressed_stream.push(b'\x00')
        compressed_stream.push(b)
      }
      Match(offset, length) => {
        compressed_stream.push(b'\x01')
        encode_varint(offset, compressed_stream)
        encode_varint(length - MIN_MATCH, compressed_stream)
      }
    }
  }
  // Check if compression helps
  if compressed_stream.length() >= data.length() {
    // Raw block
    output.push(b'\x00')
    let block_size = data.length()
    output.push((block_size & 0xFF).to_byte())
    output.push(((block_size >> 8) & 0xFF).to_byte())
    output.push(((block_size >> 16) & 0xFF).to_byte())
    for i = 0; i < data.length(); i = i + 1 {
      output.push(data[i])
    }
    return Bytes::from_array(output)
  }
  // Compressed block
  output.push(b'\x01')
  let block_size = compressed_stream.length()
  output.push((block_size & 0xFF).to_byte())
  output.push(((block_size >> 8) & 0xFF).to_byte())
  output.push(((block_size >> 16) & 0xFF).to_byte())
  for i = 0; i < compressed_stream.length(); i = i + 1 {
    output.push(compressed_stream[i])
  }
  Bytes::from_array(output)
}

///|
/// Decompress a custom-format compressed stream.
///
/// **WARNING**: This only decompresses data produced by `compress()` in this
/// module. It cannot decompress standard Brotli (.br) files.
pub fn decompress(data : Bytes) -> Bytes? {
  if data.length() < 9 {
    return None
  }
  // Check magic
  for i = 0; i < 4; i = i + 1 {
    if data[i] != magic_bytes()[i] {
      return None
    }
  }
  // Read content size
  let content_size = data[4].to_int() | (data[5].to_int() << 8) | (data[6].to_int() << 16) | (data[7].to_int() << 24)
  let mut pos = 8
  let output : Array[Byte] = []
  // Read blocks
  while pos < data.length() && output.length() < content_size {
    if pos + 4 > data.length() {
      break
    }
    let block_type = data[pos].to_int()
    let block_size = data[pos + 1].to_int() | (data[pos + 2].to_int() << 8) | (data[pos + 3].to_int() << 16)
    pos = pos + 4
    // Boundary check: block_size must not exceed remaining data
    if block_size < 0 || pos + block_size > data.length() {
      return None
    }
    if block_type == 0 {
      // Raw block
      for i = 0; i < block_size; i = i + 1 {
        output.push(data[pos])
        pos = pos + 1
      }
    } else if block_type == 1 {
      // Compressed block
      let block_end = pos + block_size
      while pos < block_end {
        if pos >= data.length() {
          return None
        }
        let token_type = data[pos]
        pos = pos + 1
        if token_type == b'\x00' {
          // Literal
          if pos >= block_end {
            return None
          }
          output.push(data[pos])
          pos = pos + 1
        } else if token_type == b'\x01' {
          // Match
          match decode_varint(data, pos) {
            Some((offset, offset_bytes)) => {
              pos = pos + offset_bytes
              if pos > block_end {
                return None
              }
              match decode_varint(data, pos) {
                Some((length_raw, length_bytes)) => {
                  pos = pos + length_bytes
                  let length = length_raw + MIN_MATCH
                  // Boundary check: offset must be valid
                  if offset <= 0 || offset > output.length() {
                    return None
                  }
                  // Boundary check: length must be reasonable
                  if length <= 0 || length > 255 + MIN_MATCH {
                    return None
                  }
                  let start = output.length() - offset
                  for i = 0; i < length; i = i + 1 {
                    let src_idx = start + i
                    if src_idx < 0 || src_idx >= output.length() {
                      return None
                    }
                    output.push(output[src_idx])
                  }
                }
                None => return None
              }
            }
            None => return None
          }
        } else {
          // Unknown token type
          return None
        }
      }
    } else {
      // Unknown block type
      return None
    }
  }
  Some(Bytes::from_array(output))
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "brotli: round-trip empty" {
  let data = Bytes::make(0, b'\x00')
  let compressed = compress(data)
  match decompress(compressed) {
    Some(decompressed) => assert_eq(decompressed.length(), 0)
    None => assert_true(false)
  }
}

///|
test "brotli: round-trip short text" {
  let data = @utils.string_to_bytes("Hello, Brotli!")
  let compressed = compress(data)
  match decompress(compressed) {
    Some(decompressed) => assert_eq(decompressed, data)
    None => assert_true(false)
  }
}

///|
test "brotli: round-trip repetitive" {
  let s = "ABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABAB"
  let data = @utils.string_to_bytes(s)
  let compressed = compress(data)
  assert_true(compressed.length() < data.length())
  match decompress(compressed) {
    Some(decompressed) => assert_eq(decompressed, data)
    None => assert_true(false)
  }
}

///|
test "brotli: round-trip binary data" {
  let data : Array[Byte] = []
  for i = 0; i < 256; i = i + 1 {
    data.push(i.to_byte())
  }
  let data_bytes = Bytes::from_array(data)
  let compressed = compress(data_bytes)
  match decompress(compressed) {
    Some(decompressed) => assert_eq(decompressed, data_bytes)
    None => assert_true(false)
  }
}

///|
test "brotli: round-trip long text" {
  let s_part = "Brotli is a generic-purpose lossless compression algorithm. "
  let mut s = ""
  for i = 0; i < 50; i = i + 1 {
    s = s + s_part
  }
  let data = @utils.string_to_bytes(s)
  let compressed = compress(data)
  assert_true(compressed.length() < data.length())
  match decompress(compressed) {
    Some(decompressed) => assert_eq(decompressed, data)
    None => assert_true(false)
  }
}

///|
test "brotli: invalid magic" {
  let bad = Bytes::from_array([b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00'])
  match decompress(bad) {
    Some(_) => assert_true(false)
    None => assert_true(true)
  }
}

///|
test "brotli: does not use fake brotli magic" {
  let data = @utils.string_to_bytes("test")
  let compressed = compress(data)
  // Verify we do NOT use the fake magic 0xCEB22CF1 (LE: F1 2C B2 CE)
  assert_true(!(compressed[0] == b'\xF1' && compressed[1] == b'\x2C' && compressed[2] == b'\xB2' && compressed[3] == b'\xCE'))
}

///|
test "brotli: single byte" {
  let data = Bytes::from_array([b'\x42'])
  let compressed = compress(data)
  match decompress(compressed) {
    Some(decompressed) => assert_eq(decompressed, data)
    None => assert_true(false)
  }
}

///|
test "brotli: all same byte" {
  let data = Bytes::make(1000, b'\xBB')
  let compressed = compress(data)
  assert_true(compressed.length() < data.length())
  match decompress(compressed) {
    Some(decompressed) => assert_eq(decompressed, data)
    None => assert_true(false)
  }
}

///|
test "brotli: large data with patterns" {
  let mut s = ""
  for i = 0; i < 100; i = i + 1 {
    s = s + "pattern123pattern123pattern123pattern123"
  }
  let data = @utils.string_to_bytes(s)
  let compressed = compress(data)
  assert_true(compressed.length() < data.length())
  match decompress(compressed) {
    Some(decompressed) => assert_eq(decompressed, data)
    None => assert_true(false)
  }
}

///|
test "brotli: malformed compressed data returns None" {
  let mb = magic_bytes()
  // Valid magic but block_size exceeds remaining data
  let bad = Bytes::from_array([mb[0], mb[1], mb[2], mb[3], b'\x10', b'\x00', b'\x00', b'\x00', b'\x01', b'\xFF', b'\xFF', b'\xFF'])
  match decompress(bad) {
    Some(_) => assert_true(false)
    None => assert_true(true)
  }
}
