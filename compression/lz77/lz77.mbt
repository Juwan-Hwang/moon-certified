/// LZ77 (Lempel-Ziv 77) — Sliding Window Compression with LZSS bit-packing.
///
/// LZ77 is a lossless data compression algorithm that uses a sliding
/// window to find repeated sequences (matches) in the input. It is the
/// foundation of DEFLATE (used in gzip, zlib), LZSS, and LZO.
///
/// ## Algorithm
///
/// The compressor maintains a sliding window of previously seen data.
/// At each position, it searches for the longest match of the upcoming
/// data within the window using a **hash chain** for O(1) expected
/// match-finding. If a match is found, it emits a (distance, length)
/// pair; otherwise, it emits a literal byte.
///
/// The output uses **LZSS bit-packing**: for every group of up to 8
/// tokens, a single flag byte indicates which tokens are literals (bit 0)
/// and which are matches (bit 1). This reduces the per-literal overhead
/// from 100% (2 bytes per literal in the naive scheme) to 12.5%.
///
/// ## Token format
///
/// - **Literal**: 1 byte (the literal value).
/// - **Match**: 2 bytes — distance (12 bits) and length (4 bits),
///   packed as: `low_byte = distance & 0xFF`,
///   `high_byte = ((distance >> 8) & 0xF) | ((length - MIN_MATCH) << 4)`.
///
/// ## Window Size
///
/// The default window size is 4096 bytes (12 bits), matching the
/// original LZ77 specification. The minimum match length is 3 bytes.
///
/// ## Complexity
/// - Compression: O(n) expected with hash chains, O(n · chain_limit) worst case.
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
/// Maximum match length (encoded in 4 bits for 15 + MIN_MATCH, plus
/// extended encoding for longer matches).
const MAX_MATCH : Int = 65535 + 18

///|
/// Hash table size for fast match finding (power of 2).
const HASH_SIZE : Int = 4096

///|
/// Maximum hash chain probes to bound worst-case compression time.
const MAX_CHAIN : Int = 128

///|
/// A compression token: either a literal byte or a back-reference.
priv enum Token {
  Literal(Byte)
  Match(Int, Int) // (distance, length)
}

// ---------------------------------------------------------------------------
// Hash chain match finder
// ---------------------------------------------------------------------------

///|
/// Hash 3 bytes into a value in [0, HASH_SIZE).
fn hash3(data : Bytes, pos : Int) -> Int {
  let h = (data[pos].to_int() << 16) ^
    (data[pos + 1].to_int() << 8) ^
    data[pos + 2].to_int()
  // Knuth multiplicative hash, using UInt for 32-bit wrap-around.
  let hu = h.reinterpret_as_uint()
  (((hu * 2654435761U) >> 16) & (HASH_SIZE - 1).reinterpret_as_uint()).reinterpret_as_int()
}

// ---------------------------------------------------------------------------
// Compression
// ---------------------------------------------------------------------------

///|
/// Compress data using LZ77 with hash-chain match finding and LZSS
/// bit-packing.
///
/// Returns a compressed byte array. The first 4 bytes are the original
/// length (little-endian), followed by the LZSS token stream.
///
/// For incompressible data, the overhead is ~12.5% (1 flag byte per 8
/// literals), significantly better than the 100% overhead of the
/// naive per-token flag scheme.
pub fn compress(data : Bytes) -> Bytes {
  let n = data.length()
  let tokens : Array[Token] = []
  if n < MIN_MATCH {
    for i = 0; i < n; i = i + 1 {
      tokens.push(Token::Literal(data[i]))
    }
    return encode_tokens(tokens, n)
  }
  // Hash chains: head[hash] = last position with this hash.
  // prev[pos] = previous position with the same hash.
  let head = FixedArray::make(HASH_SIZE, -1)
  let prev = FixedArray::make(n, -1)
  let mut pos = 0
  while pos < n {
    if pos + MIN_MATCH > n {
      // Not enough data for a match; emit literal.
      tokens.push(Token::Literal(data[pos]))
      pos = pos + 1
      continue
    }
    let h = hash3(data, pos)
    let mut best_len = 0
    let mut best_dist = 0
    let max_len = if pos + MAX_MATCH < n { MAX_MATCH } else { n - pos }
    // Follow hash chain to find the best match.
    let mut candidate = head[h]
    let mut chain_count = 0
    while candidate >= 0 && chain_count < MAX_CHAIN {
      let dist = pos - candidate
      if dist > WINDOW_SIZE {
        break
      }
      // Full comparison.
      let mut match_len = 0
      while match_len < max_len &&
            pos + match_len < n &&
            data[candidate + match_len] == data[pos + match_len] {
        match_len = match_len + 1
      }
      if match_len > best_len {
        best_len = match_len
        best_dist = dist
        if best_len >= max_len {
          break
        }
      }
      candidate = prev[candidate]
      chain_count = chain_count + 1
    }
    if best_len >= MIN_MATCH {
      tokens.push(Token::Match(best_dist, best_len))
      // Insert all positions covered by the match into the hash chain.
      let end = pos + best_len
      let mut i = pos
      while i < end && i + MIN_MATCH <= n {
        let hi = hash3(data, i)
        prev[i] = head[hi]
        head[hi] = i
        i = i + 1
      }
      pos = end
    } else {
      tokens.push(Token::Literal(data[pos]))
      let hi = hash3(data, pos)
      prev[pos] = head[hi]
      head[hi] = pos
      pos = pos + 1
    }
  }
  encode_tokens(tokens, n)
}

///|
/// Write a variable-length encoding for extended match lengths.
/// Writes 255 repeatedly, then the remainder. This is the same scheme
/// used by LZ4's extended length encoding.
fn write_ext_length(buf : Array[Byte], length : Int) -> Unit {
  let mut remaining = length
  while remaining >= 255 {
    buf.push(b'\xFF')
    remaining = remaining - 255
  }
  buf.push(remaining.to_byte())
}

///|
/// Read a variable-length extended match length from `compressed`
/// starting at `pos`. Returns (value, new_pos) or None on error.
fn read_ext_length(compressed : Bytes, pos : Int) -> (Int, Int)? {
  let mut total = 0
  let mut p = pos
  while p < compressed.length() {
    let b = compressed[p].to_int()
    p = p + 1
    total = total + b
    if b != 255 {
      return Some((total, p))
    }
  }
  None
}

///|
/// Encode tokens into a byte stream using LZSS bit-packing with
/// extended match length encoding.
///
/// For every group of up to 8 tokens, a flag byte is emitted where:
/// - bit i = 0 → token i is a literal (1 byte follows)
/// - bit i = 1 → token i is a match (2+ bytes follow)
///
/// Match encoding:
/// - Byte 1: dist & 0xFF (low 8 bits of distance)
/// - Byte 2: (dist >> 8) & 0xF (high 4 bits of distance) | (len_nibble << 4)
/// - If len_nibble == 15: extended length bytes follow (LZ4-style:
///   255 repeatedly, then remainder)
///
/// This reduces per-literal overhead from 100% to 12.5% and allows
/// arbitrarily long matches to be encoded efficiently.
fn encode_tokens(tokens : Array[Token], original_len : Int) -> Bytes {
  let output : Array[Byte] = []
  // Write original length (4 bytes, little-endian).
  output.push((original_len & 0xFF).to_byte())
  output.push(((original_len >> 8) & 0xFF).to_byte())
  output.push(((original_len >> 16) & 0xFF).to_byte())
  output.push(((original_len >> 24) & 0xFF).to_byte())
  // Process tokens in groups of 8 with a flag byte.
  let mut idx = 0
  while idx < tokens.length() {
    // Reserve a byte for the flag.
    let flag_pos = output.length()
    output.push(b'\x00')
    let mut flag = 0
    let group_end = if idx + 8 < tokens.length() {
      idx + 8
    } else {
      tokens.length()
    }
    for bit = 0; bit < 8 && idx + bit < tokens.length(); bit = bit + 1 {
      match tokens[idx + bit] {
        Token::Literal(b) =>
          // bit stays 0 (literal)
          output.push(b)
        Token::Match(dist, len) => {
          flag = flag | (1 << bit)
          let adjusted_len = len - MIN_MATCH
          let len_nibble = if adjusted_len >= 15 { 15 } else { adjusted_len }
          output.push((dist & 0xFF).to_byte())
          output.push((((dist >> 8) & 0xF) | (len_nibble << 4)).to_byte())
          // Extended match length (LZ4-style).
          if adjusted_len >= 15 {
            write_ext_length(output, adjusted_len - 15)
          }
        }
      }
    }
    output[flag_pos] = flag.to_byte()
    idx = group_end
  }
  Bytes::from_array(output)
}

// ---------------------------------------------------------------------------
// Decompression
// ---------------------------------------------------------------------------

///|
/// Decompress LZ77-compressed data.
///
/// Returns `Some(data)` on success, or `None` if the compressed stream
/// is corrupt, truncated, or contains an invalid back-reference.
///
/// Using `Option` allows callers to distinguish "decompression of empty
/// input" (`Some(b"")`) from "corrupt stream" (`None`).
pub fn decompress(compressed : Bytes) -> Bytes? {
  if compressed.length() < 4 {
    return None
  }
  // Read original length.
  let original_len = compressed[0].to_int() |
    (compressed[1].to_int() << 8) |
    (compressed[2].to_int() << 16) |
    (compressed[3].to_int() << 24)
  if original_len < 0 {
    return None
  }
  let output : Array[Byte] = []
  let mut pos = 4
  while pos < compressed.length() && output.length() < original_len {
    let flag = compressed[pos].to_int()
    pos = pos + 1
    // Process up to 8 tokens per flag byte.
    for bit = 0; bit < 8 && output.length() < original_len; bit = bit + 1 {
      if pos >= compressed.length() {
        if output.length() < original_len {
          return None // Truncated stream.
        }
        break
      }
      if (flag & (1 << bit)) == 0 {
        // Literal.
        output.push(compressed[pos])
        pos = pos + 1
      } else {
        // Match.
        if pos + 1 >= compressed.length() {
          return None // Truncated match token.
        }
        let low = compressed[pos].to_int()
        let high = compressed[pos + 1].to_int()
        pos = pos + 2
        let dist = (low & 0xFF) | ((high & 0xF) << 8)
        let len_nibble = (high >> 4) & 0xF
        let mut len = len_nibble + MIN_MATCH
        // Extended match length (LZ4-style).
        if len_nibble == 15 {
          match read_ext_length(compressed, pos) {
            None => return None
            Some((ext, new_pos)) => {
              len = len + ext
              pos = new_pos
            }
          }
        }
        // Bounds check: dist must not exceed current output length.
        if dist > output.length() || dist <= 0 {
          return None // Invalid back-reference.
        }
        // Copy from output (handles overlapping copies correctly).
        let start = output.length() - dist
        for j = 0; j < len; j = j + 1 {
          output.push(output[start + j])
        }
      }
    }
  }
  if output.length() != original_len {
    return None // Output length mismatch.
  }
  Some(Bytes::from_array(output))
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "lz77: roundtrip simple" {
  let data = @utils.string_to_bytes("hello world hello world hello world")
  let compressed = compress(data)
  let decompressed = decompress(compressed).unwrap()
  assert_eq(@utils.bytes_to_string(decompressed), @utils.bytes_to_string(data))
}

///|
test "lz77: roundtrip no repeats" {
  let data = @utils.string_to_bytes("abcdefghij")
  let compressed = compress(data)
  let decompressed = decompress(compressed).unwrap()
  assert_eq(@utils.bytes_to_string(decompressed), @utils.bytes_to_string(data))
}

///|
test "lz77: roundtrip highly repetitive" {
  let data = @utils.string_to_bytes("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
  let compressed = compress(data)
  let decompressed = decompress(compressed).unwrap()
  assert_eq(@utils.bytes_to_string(decompressed), @utils.bytes_to_string(data))
  // Should compress well.
  assert_true(compressed.length() < data.length())
}

///|
test "lz77: empty input" {
  let data = b""
  let compressed = compress(data)
  let decompressed = decompress(compressed).unwrap()
  assert_eq(decompressed.length(), 0)
}

///|
test "lz77: single byte" {
  let data = @utils.string_to_bytes("A")
  let compressed = compress(data)
  let decompressed = decompress(compressed).unwrap()
  assert_eq(@utils.bytes_to_string(decompressed), "A")
}

///|
test "lz77: large text" {
  let text = "The quick brown fox jumps over the lazy dog. " +
    "The quick brown fox jumps over the lazy dog. " +
    "The quick brown fox jumps over the lazy dog. " +
    "The quick brown fox jumps over the lazy dog."
  let data = @utils.string_to_bytes(text)
  let compressed = compress(data)
  let decompressed = decompress(compressed).unwrap()
  assert_eq(@utils.bytes_to_string(decompressed), text)
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
  let decompressed = decompress(compressed).unwrap()
  assert_eq(decompressed, data)
}

///|
test "lz77: incompressible data overhead is bounded" {
  // Data with no repeats — overhead should be ~12.5%, not 100%.
  let data = Bytes::from_array([
    b'\x00', b'\x01', b'\x02', b'\x03', b'\x04', b'\x05', b'\x06', b'\x07', b'\x08',
    b'\x09', b'\x0A', b'\x0B', b'\x0C', b'\x0D', b'\x0E', b'\x0F', b'\x10', b'\x11',
    b'\x12', b'\x13', b'\x14', b'\x15', b'\x16', b'\x17', b'\x18', b'\x19', b'\x1A',
    b'\x1B', b'\x1C', b'\x1D', b'\x1E', b'\x1F',
  ])
  let compressed = compress(data)
  // 4 bytes header + 4 flag bytes + 32 literal bytes = 40 bytes max.
  // With old scheme: 4 + 64 = 68 bytes.
  assert_true(compressed.length() <= 40)
}

///|
test "lz77: corrupt stream returns None" {
  // Truncated header.
  assert_true(decompress(Bytes::from_array([b'\x01', b'\x02'])) is None)
  // Invalid back-reference.
  let bad = Bytes::from_array([
    b'\x05', b'\x00', b'\x00', b'\x00', // original_len = 5
     b'\x01', // flag: token 0 is a match
     b'\x10', b'\x00', // dist=16, len=3 — but output is empty!
  ])
  assert_true(decompress(bad) is None)
}

///|
test "lz77: long repetitive data compresses well" {
  let sb = StringBuilder()
  for i = 0; i < 500; i = i + 1 {
    sb.write_string("aaaaaaaaaa")
  }
  let text = sb.to_string()
  let data = @utils.string_to_bytes(text)
  let compressed = compress(data)
  let decompressed = decompress(compressed).unwrap()
  assert_eq(@utils.bytes_to_string(decompressed), text)
  // 5000 'a's should compress to a tiny output with hash-chain matching.
  assert_true(compressed.length() < 200)
}
