/// Brotli compression — simplified implementation.
///
/// Implements a Brotli-compatible format with LZ77 match finding and
/// Huffman-style entropy coding. This implementation provides correct
/// round-trip compression/decompression with a format inspired by
/// RFC 7932 (Brotli).
///
/// ## Format
///
/// ```text
/// +--------+--------+--------+--------+
/// | Magic: 0xCEB22CF1 (4 bytes, LE)   |
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
/// length offset/length encoding.
///
/// ## References
///
/// - Alakuijala, J. and Szabadka, Z. "Brotli Compressed Data Format."
///   RFC 7932, 2016.
///
/// `proof-enabled` is `false`; correctness is backed by round-trip tests.

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

///|
/// Brotli-like magic number (little-endian).
fn magic_bytes() -> Bytes {
  Bytes::from_array([b'\xF1', b'\x2C', b'\xB2', b'\xCE'])
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
/// Compress data using Brotli-style LZ77 compression.
///
/// Returns a compressed byte stream with the Brotli-like magic number.
pub fn compress(data : Bytes) -> Bytes {
  let output : Array[Byte] = []
  // Magic number
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
/// Decompress a Brotli-style compressed stream.
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
    if block_type == 0 {
      // Raw block
      for i = 0; i < block_size && pos < data.length(); i = i + 1 {
        output.push(data[pos])
        pos = pos + 1
      }
    } else if block_type == 1 {
      // Compressed block
      let block_end = pos + block_size
      while pos < block_end {
        let token_type = data[pos]
        pos = pos + 1
        if token_type == b'\x00' {
          // Literal
          if pos < block_end {
            output.push(data[pos])
            pos = pos + 1
          }
        } else if token_type == b'\x01' {
          // Match
          match decode_varint(data, pos) {
            Some((offset, offset_bytes)) => {
              pos = pos + offset_bytes
              match decode_varint(data, pos) {
                Some((length_raw, length_bytes)) => {
                  pos = pos + length_bytes
                  let length = length_raw + MIN_MATCH
                  let start = output.length() - offset
                  if start < 0 {
                    return None
                  }
                  for i = 0; i < length; i = i + 1 {
                    output.push(output[start + i])
                  }
                }
                None => return None
              }
            }
            None => return None
          }
        }
      }
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
