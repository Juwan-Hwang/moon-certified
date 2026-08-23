/// Zstd-inspired LZ77 compression — custom format (NOT RFC 8478 compatible).
///
/// **WARNING**: This is NOT a standard Zstd implementation. It does NOT produce
/// `.zst` files that can be decompressed by the zstd command-line tool or any
/// RFC 8478 compliant decoder. The format uses a custom magic number and a
/// simplified LZ77+token-stream encoding without FSE, Huffman, or multi-block
/// types. Use this only for internal round-trip compression within MoonBit.
///
/// For production Zstd compression, use the official `zstd` library via FFI.
///
/// ## Custom frame format
///
/// ```text
/// +--------+--------+--------+--------+
/// | Custom magic 0x5A4C424D ("MBLZ")  |
/// +--------+--------+--------+--------+
/// | Frame header (5 bytes)            |
/// |  - Content size (4 bytes, LE)     |
/// |  - Flags (1 byte)                 |
/// +--------+--------+--------+--------+
/// | Blocks...                         |
/// +--------+--------+--------+--------+
/// ```
///
/// Each block:
/// - 1 byte block type (0=raw, 1=RLE, 2=compressed)
/// - 3 bytes block size (LE)
/// - Block data
///
/// Compressed blocks use LZ77 with a 4-byte minimum match and a 16-bit
/// offset, encoded as a simple token stream (not FSE/Huffman).
///
/// ## Why not RFC 8478?
///
/// A full RFC 8478 implementation requires FSE (Finite State Entropy) encoding,
/// Huffman tree descriptions, multi-block frame descriptors, dictionary
/// support, and content checksums. This simplified format only provides
/// LZ77 match finding with a token-stream serialization.
///
/// `proof-enabled` is `false`; correctness is backed by round-trip tests.

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

///|
/// Custom magic number: "MBLZ" (MoonBit LZ). Intentionally NOT 0xFD2FB528
/// to avoid being mistaken for standard Zstd.
fn magic_bytes() -> Bytes {
  Bytes::from_array([b'\x4D', b'\x42', b'\x4C', b'\x5A'])
}

///|
/// Minimum match length for LZ77.
const MIN_MATCH : Int = 4

///|
/// Maximum offset (16-bit).
const MAX_OFFSET : Int = 65535

///|
/// Hash table size (power of 2).
const HASH_SIZE : Int = 16384

// ---------------------------------------------------------------------------
// LZ77 token types
// ---------------------------------------------------------------------------

///|
priv enum Token {
  Literal(Byte)
  Match(Int, Int)
}

// ---------------------------------------------------------------------------
// Hash table and match finding
// ---------------------------------------------------------------------------

///|
fn hash4(data : Bytes, pos : Int) -> Int {
  let h = (data[pos].to_int64() << 24) |
    (data[pos + 1].to_int64() << 16) |
    (data[pos + 2].to_int64() << 8) |
    data[pos + 3].to_int64()
  (((h * 2654435761L) >> 18) & (HASH_SIZE - 1).to_int64()).to_int()
}

///|
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
  let max_len = if data.length() - pos < 255 + MIN_MATCH {
    data.length() - pos
  } else {
    255 + MIN_MATCH
  }
  while len < max_len && data[candidate + len] == data[pos + len] {
    len = len + 1
  }
  if len >= MIN_MATCH {
    (pos - candidate, len)
  } else {
    (0, 0)
  }
}

///|
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
// Public API
// ---------------------------------------------------------------------------

///|
/// Compress data using Zstd-inspired LZ77 compression.
///
/// **WARNING**: Output uses a custom magic number and is NOT compatible with
/// the standard Zstd format (RFC 8478). Do not write the output to `.zst`
/// files expecting standard tools to decompress them.
pub fn compress(data : Bytes) -> Bytes {
  let output : Array[Byte] = []
  // Custom magic number (NOT 0xFD2FB528)
  for i = 0; i < 4; i = i + 1 {
    output.push(magic_bytes()[i])
  }
  // Frame header: content size (4 bytes LE) + flags (1 byte)
  let content_size = data.length()
  output.push((content_size & 0xFF).to_byte())
  output.push(((content_size >> 8) & 0xFF).to_byte())
  output.push(((content_size >> 16) & 0xFF).to_byte())
  output.push(((content_size >> 24) & 0xFF).to_byte())
  output.push(b'\x00') // flags: no checksum, single block
  // Special case: empty data
  if data.length() == 0 {
    output.push(b'\x00') // block type: raw
    output.push(b'\x00')
    output.push(b'\x00')
    output.push(b'\x00')
    return Bytes::from_array(output)
  }
  // LZ77 compress
  let tokens = lz77_compress(data)
  // Build symbol stream: encode tokens as a byte stream
  // Literal: type=0, then 1 byte literal
  // Match: type=1, then offset_lo, offset_hi, length-MIN_MATCH
  let symbol_stream : Array[Byte] = []
  for i = 0; i < tokens.length(); i = i + 1 {
    match tokens[i] {
      Literal(b) => {
        symbol_stream.push(b'\x00')
        symbol_stream.push(b)
      }
      Match(offset, length) => {
        symbol_stream.push(b'\x01')
        symbol_stream.push((offset & 0xFF).to_byte())
        symbol_stream.push(((offset >> 8) & 0xFF).to_byte())
        symbol_stream.push((length - MIN_MATCH).to_byte())
      }
    }
  }
  // Check if compression actually helps
  if symbol_stream.length() >= data.length() {
    // Use raw block instead
    output.push(b'\x00') // block type: raw
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
  output.push(b'\x02') // block type: compressed
  let block_size = symbol_stream.length()
  output.push((block_size & 0xFF).to_byte())
  output.push(((block_size >> 8) & 0xFF).to_byte())
  output.push(((block_size >> 16) & 0xFF).to_byte())
  for i = 0; i < symbol_stream.length(); i = i + 1 {
    output.push(symbol_stream[i])
  }
  Bytes::from_array(output)
}

///|
/// Decompress a custom-format compressed stream.
///
/// **WARNING**: This only decompresses data produced by `compress()` in this
/// module. It cannot decompress standard Zstd (.zst) files.
pub fn decompress(data : Bytes) -> Bytes? {
  if data.length() < 9 {
    return None
  }
  for i = 0; i < 4; i = i + 1 {
    if data[i] != magic_bytes()[i] {
      return None
    }
  }
  // Read frame header
  let content_size = data[4].to_int() |
    (data[5].to_int() << 8) |
    (data[6].to_int() << 16) |
    (data[7].to_int() << 24)
  let mut pos = 9
  let output : Array[Byte] = []
  // Read blocks
  while pos < data.length() && output.length() < content_size {
    if pos + 4 > data.length() {
      break
    }
    let block_type = data[pos].to_int()
    let block_size = data[pos + 1].to_int() |
      (data[pos + 2].to_int() << 8) |
      (data[pos + 3].to_int() << 16)
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
    } else if block_type == 2 {
      // Compressed block: symbol stream
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
          if pos + 3 > block_end {
            return None
          }
          let offset = data[pos].to_int() | (data[pos + 1].to_int() << 8)
          let length = data[pos + 2].to_int() + MIN_MATCH
          pos = pos + 3
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
            // In overlapping LZ77, start+i may reference bytes we just pushed,
            // which is valid. But we must ensure start+i is within bounds.
            let src_idx = start + i
            if src_idx < 0 || src_idx >= output.length() {
              return None
            }
            output.push(output[src_idx])
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
test "zstd: round-trip empty" {
  let data = Bytes::make(0, b'\x00')
  let compressed = compress(data)
  match decompress(compressed) {
    Some(decompressed) => assert_eq(decompressed.length(), 0)
    None => assert_true(false)
  }
}

///|
test "zstd: round-trip short text" {
  let data = @utils.string_to_bytes("Hello, World!")
  let compressed = compress(data)
  match decompress(compressed) {
    Some(decompressed) => assert_eq(decompressed, data)
    None => assert_true(false)
  }
}

///|
test "zstd: round-trip repetitive" {
  let s = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC"
  let data = @utils.string_to_bytes(s)
  let compressed = compress(data)
  assert_true(compressed.length() < data.length())
  match decompress(compressed) {
    Some(decompressed) => assert_eq(decompressed, data)
    None => assert_true(false)
  }
}

///|
test "zstd: round-trip binary data" {
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
test "zstd: round-trip long text" {
  let s_part = "The quick brown fox jumps over the lazy dog. "
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
test "zstd: invalid magic" {
  let bad = Bytes::from_array([
    b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00',
  ])
  match decompress(bad) {
    Some(_) => assert_true(false)
    None => assert_true(true)
  }
}

///|
test "zstd: does not use standard zstd magic" {
  let data = @utils.string_to_bytes("test")
  let compressed = compress(data)
  // Verify we do NOT use the standard Zstd magic 0xFD2FB528 (LE: 28 B5 2F FD)
  assert_true(
    !(compressed[0] == b'\x28' &&
    compressed[1] == b'\xB5' &&
    compressed[2] == b'\x2F' &&
    compressed[3] == b'\xFD'),
  )
}

///|
test "zstd: single byte" {
  let data = Bytes::from_array([b'\x42'])
  let compressed = compress(data)
  match decompress(compressed) {
    Some(decompressed) => assert_eq(decompressed, data)
    None => assert_true(false)
  }
}

///|
test "zstd: all same byte" {
  let data = Bytes::make(1000, b'\xAA')
  let compressed = compress(data)
  assert_true(compressed.length() < data.length())
  match decompress(compressed) {
    Some(decompressed) => assert_eq(decompressed, data)
    None => assert_true(false)
  }
}

///|
test "zstd: malformed compressed data returns None" {
  // Valid magic but truncated block
  let mb = magic_bytes()
  let bad = Bytes::from_array([
    mb[0],
    mb[1],
    mb[2],
    mb[3],
    b'\x10',
    b'\x00',
    b'\x00',
    b'\x00',
    b'\x00',
    b'\x02',
    b'\xFF',
    b'\xFF',
    b'\xFF',
  ])
  match decompress(bad) {
    Some(_) => assert_true(false)
    None => assert_true(true)
  }
}
