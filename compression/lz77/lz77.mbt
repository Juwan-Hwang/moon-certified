/// LZ77 (Lempel-Ziv 77) — Sliding Window Compression.
///
/// LZ77 is a lossless data compression algorithm that uses a sliding
/// window to find repeated sequences (matches) in the input. It is the
/// foundation of DEFLATE (used in gzip, zlib), LZSS, and LZO.
///
/// ## Algorithm
///
/// The compressor maintains a sliding window of previously seen data.
/// At each position, it searches for the longest match of the upcoming
/// data within the window. If a match is found, it emits a (distance,
/// length) pair; otherwise, it emits a literal byte.
///
/// The output is a sequence of tokens:
/// - Literal: a single byte.
/// - Match: (distance, length) — copy `length` bytes from `distance`
///   bytes back in the output.
///
/// ## Window Size
///
/// The default window size is 4096 bytes (12 bits), matching the
/// original LZ77 specification. The minimum match length is 3 bytes.
///
/// ## Complexity
/// - Compression: O(n * w) where n = input length, w = window size.
/// - Decompression: O(n).
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

///|
/// Default sliding window size (bytes).
const WINDOW_SIZE : Int = 4096

///|
/// Minimum match length to emit a (distance, length) pair.
const MIN_MATCH : Int = 3

///|
/// Maximum match length (encoded in 4 bits for 15 + MIN_MATCH).
const MAX_MATCH : Int = 18

///|
/// A compression token: either a literal byte or a back-reference.
priv enum Token {
  Literal(Byte)
  Match(Int, Int) // (distance, length)
}

///|
/// Encode a single UTF-8 code point into the buffer.
fn utf8_encode(cp : UInt, buf : Array[Byte]) -> Unit {
  if cp <= 0x7FU {
    buf.push(cp.to_byte())
  } else if cp <= 0x7FFU {
    buf.push((0xC0U | (cp >> 6)).to_byte())
    buf.push((0x80U | (cp & 0x3FU)).to_byte())
  } else if cp <= 0xFFFFU {
    buf.push((0xE0U | (cp >> 12)).to_byte())
    buf.push((0x80U | ((cp >> 6) & 0x3FU)).to_byte())
    buf.push((0x80U | (cp & 0x3FU)).to_byte())
  } else {
    buf.push((0xF0U | (cp >> 18)).to_byte())
    buf.push((0x80U | ((cp >> 12) & 0x3FU)).to_byte())
    buf.push((0x80U | ((cp >> 6) & 0x3FU)).to_byte())
    buf.push((0x80U | (cp & 0x3FU)).to_byte())
  }
}

///|
/// Convert a MoonBit String to UTF-8 Bytes.
fn string_to_bytes(s : String) -> Bytes {
  let buf : Array[Byte] = []
  for c in s.iter() {
    utf8_encode(c.to_uint(), buf)
  }
  Bytes::from_array(buf)
}

///|
/// Convert Bytes (assumed UTF-8) to a MoonBit String.
fn bytes_to_string(bytes : Bytes) -> String {
  let buf = StringBuilder()
  let n = bytes.length()
  let mut i = 0
  while i < n {
    let b0 = bytes[i].to_uint()
    let mut cp = b0
    let mut extra = 0
    if b0 <= 0x7FU {
      cp = b0
      extra = 0
    } else if (b0 & 0xE0U) == 0xC0U {
      cp = b0 & 0x1FU
      extra = 1
    } else if (b0 & 0xF0U) == 0xE0U {
      cp = b0 & 0x0FU
      extra = 2
    } else if (b0 & 0xF8U) == 0xF0U {
      cp = b0 & 0x07U
      extra = 3
    } else {
      // Invalid byte — emit replacement.
      buf.write_char('\u{FFFD}')
      i = i + 1
      continue
    }
    let mut j = 1
    while j <= extra && i + j < n {
      let bj = bytes[i + j].to_uint()
      if (bj & 0xC0U) != 0x80U {
        break
      }
      cp = (cp << 6) | (bj & 0x3FU)
      j = j + 1
    }
    buf.write_char(cp.reinterpret_as_int().unsafe_to_char())
    i = i + extra + 1
  }
  buf.to_string()
}

///|
/// Compress data using LZ77 with the default window size.
///
/// Returns a compressed byte array. The first 4 bytes are the original
/// length (little-endian), followed by the token stream. Each token
/// starts with a flag byte:
/// - 0x00: next byte is a literal.
/// - 0x01: next 2 bytes are (distance, length) — distance is 12 bits,
///   length is 4 bits (packed as: high_byte = distance >> 4,
///   low_byte = ((distance & 0xF) << 4) | (length - MIN_MATCH)).
pub fn compress(data : Bytes) -> Bytes {
  let n = data.length()
  let tokens : Array[Token] = []
  let mut pos = 0
  while pos < n {
    // Search for the longest match in the window.
    let window_start = if pos > WINDOW_SIZE { pos - WINDOW_SIZE } else { 0 }
    let mut best_len = 0
    let mut best_dist = 0
    let max_len = if pos + MAX_MATCH < n { MAX_MATCH } else { n - pos }
    if max_len >= MIN_MATCH {
      let mut search_pos = window_start
      while search_pos < pos {
        // Check match starting at search_pos.
        let mut match_len = 0
        while match_len < max_len &&
              pos + match_len < n &&
              data[search_pos + match_len] == data[pos + match_len] {
          match_len = match_len + 1
        }
        if match_len >= MIN_MATCH && match_len > best_len {
          best_len = match_len
          best_dist = pos - search_pos
          if match_len >= max_len {
            break // Can't do better
          }
        }
        search_pos = search_pos + 1
      }
    }
    if best_len >= MIN_MATCH {
      tokens.push(Token::Match(best_dist, best_len))
      pos = pos + best_len
    } else {
      tokens.push(Token::Literal(data[pos]))
      pos = pos + 1
    }
  }
  // Encode tokens to bytes.
  encode_tokens(tokens, n)
}

///|
/// Encode tokens into a byte stream.
fn encode_tokens(tokens : Array[Token], original_len : Int) -> Bytes {
  let output : Array[Byte] = []
  // Write original length (4 bytes, little-endian).
  output.push((original_len & 0xFF).to_byte())
  output.push(((original_len >> 8) & 0xFF).to_byte())
  output.push(((original_len >> 16) & 0xFF).to_byte())
  output.push(((original_len >> 24) & 0xFF).to_byte())
  // Write each token.
  for i = 0; i < tokens.length(); i = i + 1 {
    match tokens[i] {
      Token::Literal(b) => {
        output.push(b'\x00') // literal flag
        output.push(b)
      }
      Token::Match(dist, len) => {
        output.push(b'\x01') // match flag
        // Pack distance (12 bits) and length (4 bits) into 2 bytes.
        let adjusted_len = len - MIN_MATCH
        output.push((dist & 0xFF).to_byte()) // low 8 bits of distance
        output.push((((dist >> 8) & 0xF) | (adjusted_len << 4)).to_byte()) // high 4 bits of distance + 4 bits of length
      }
    }
  }
  Bytes::from_array(output)
}

///|
/// Decompress LZ77-compressed data.
///
/// Returns the original uncompressed data.
pub fn decompress(compressed : Bytes) -> Bytes {
  if compressed.length() < 4 {
    return b""
  }
  // Read original length.
  let original_len = compressed[0].to_int() |
    (compressed[1].to_int() << 8) |
    (compressed[2].to_int() << 16) |
    (compressed[3].to_int() << 24)
  let output : Array[Byte] = []
  let mut pos = 4
  while pos < compressed.length() && output.length() < original_len {
    let flag = compressed[pos].to_int()
    pos = pos + 1
    if flag == 0x00 {
      // Literal.
      if pos < compressed.length() {
        output.push(compressed[pos])
        pos = pos + 1
      }
    } else if flag == 0x01 {
      // Match.
      if pos + 1 < compressed.length() {
        let low = compressed[pos].to_int()
        let high = compressed[pos + 1].to_int()
        pos = pos + 2
        let dist = (low & 0xFF) | ((high & 0xF) << 8)
        let len = ((high >> 4) & 0xF) + MIN_MATCH
        // Copy from output.
        let start = output.length() - dist
        for j = 0; j < len; j = j + 1 {
          output.push(output[start + j])
        }
      }
    }
  }
  Bytes::from_array(output)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "lz77: roundtrip simple" {
  let data = string_to_bytes("hello world hello world hello world")
  let compressed = compress(data)
  let decompressed = decompress(compressed)
  assert_eq(bytes_to_string(decompressed), bytes_to_string(data))
}

///|
test "lz77: roundtrip no repeats" {
  let data = string_to_bytes("abcdefghij")
  let compressed = compress(data)
  let decompressed = decompress(compressed)
  assert_eq(bytes_to_string(decompressed), bytes_to_string(data))
}

///|
test "lz77: roundtrip highly repetitive" {
  let data = string_to_bytes("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
  let compressed = compress(data)
  let decompressed = decompress(compressed)
  assert_eq(bytes_to_string(decompressed), bytes_to_string(data))
  // Should compress well.
  assert_true(compressed.length() < data.length())
}

///|
test "lz77: empty input" {
  let data = b""
  let compressed = compress(data)
  let decompressed = decompress(compressed)
  assert_eq(decompressed.length(), 0)
}

///|
test "lz77: single byte" {
  let data = string_to_bytes("A")
  let compressed = compress(data)
  let decompressed = decompress(compressed)
  assert_eq(bytes_to_string(decompressed), "A")
}

///|
test "lz77: large text" {
  let text = "The quick brown fox jumps over the lazy dog. " +
    "The quick brown fox jumps over the lazy dog. " +
    "The quick brown fox jumps over the lazy dog. " +
    "The quick brown fox jumps over the lazy dog."
  let data = string_to_bytes(text)
  let compressed = compress(data)
  let decompressed = decompress(compressed)
  assert_eq(bytes_to_string(decompressed), text)
  // Should achieve good compression ratio.
  assert_true(compressed.length() < data.length())
}

///|
test "lz77: binary data" {
  let data = Bytes::from_array([
    b'\x00', b'\x01', b'\x02', b'\x03', b'\x00', b'\x01', b'\x02', b'\x03', b'\x00',
    b'\x01', b'\x02', b'\x03', b'\xFF', b'\xFE', b'\xFD',
  ])
  let compressed = compress(data)
  let decompressed = decompress(compressed)
  assert_eq(decompressed, data)
}
