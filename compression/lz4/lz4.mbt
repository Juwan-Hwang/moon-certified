/// LZ4 block format compression and decompression.
///
/// LZ4 is a lossless compression algorithm focused on speed. This module
/// implements the LZ4 block format (not the frame format), providing both
/// compression and decompression.
///
/// ## Algorithm overview
///
/// LZ4 encodes data as a sequence of blocks. Each block has:
///
/// 1. **Token** (1 byte): high nibble = literal length (0-15), low nibble = match
///    length (0-15). Both values are "minus the minimum": literal length minimum
///    is 0, match length minimum is 4 (the minimum match).
/// 2. **Extended literal length**: if literal length nibble == 15, additional
///    bytes follow. Each byte adds its value to the length. The encoding stops
///    when a byte < 255 is encountered.
/// 3. **Literals**: raw, uncompressed bytes copied to output.
/// 4. **Match offset** (2 bytes, little-endian): distance back in the output
///    to copy from. Minimum is 1.
/// 5. **Extended match length**: if match length nibble == 15, additional bytes
///    follow (same encoding as literal length).
///
/// The last block contains only literals (no match).
///
/// ## Hash table for compression
///
/// The compressor uses a hash table mapping 4-byte sequences to their most recent
/// position. When a hash collision is found, it checks whether the 4 bytes match.
/// If they do, it extends the match as far as possible.
///
/// ## References
///
/// - LZ4 specification: https://github.com/lz4/lz4/blob/dev/doc/lz4_Block_format.md
/// - Collet, Y. "LZ4: Extremely Fast Compression algorithm" (2011)
///
/// Not formally verified. Correctness is ensured by the test suite, including
/// round-trip tests on various data patterns.

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

///|
/// Minimum match length: 4 bytes.
const MIN_MATCH : Int = 4

///|
/// Maximum offset: 65535 (16-bit).
const MAX_OFFSET : Int = 65535

///|
/// Hash table size (power of 2 for fast masking).
const HASH_SIZE : Int = 1 << 16

///|
/// Hash mask.
const HASH_MASK : Int = HASH_SIZE - 1

///|
/// Maximum literal length encoding: 15 means "read more".
const MAX_NIBBLE : Int = 15

///|
/// Maximum value of extended length byte.
const MAX_LEN_BYTE : Int = 255

// ---------------------------------------------------------------------------
// Encoding helpers
// ---------------------------------------------------------------------------

///|
/// Write a variable-length encoding (for extended literal/match lengths).
/// Writes 255 repeatedly, then the remainder.
fn write_length(buf : Array[Byte], length : Int) -> Unit {
  let mut remaining = length
  while remaining >= MAX_LEN_BYTE {
    buf.push((255).to_byte())
    remaining = remaining - MAX_LEN_BYTE
  }
  buf.push(remaining.to_byte())
}

///|
/// Read a variable-length encoding from input starting at `pos`.
/// Returns (value, new_position) or None on error.
fn read_length(input : Bytes, pos : Int, end : Int) -> (Int, Int)? {
  let mut total = 0
  let mut p = pos
  while p < end {
    if p >= end {
      return None
    }
    let b = input[p].to_int()
    p = p + 1
    total = total + b
    if b != MAX_LEN_BYTE {
      return Some((total, p))
    }
  }
  None
}

///|
/// Read a little-endian 16-bit unsigned integer.
fn read_u16_le(data : Bytes, pos : Int) -> Int {
  data[pos].to_int() | (data[pos + 1].to_int() << 8)
}

///|
/// Write a little-endian 16-bit unsigned integer.
fn write_u16_le(buf : Array[Byte], val : Int) -> Unit {
  buf.push((val & 0xFF).to_byte())
  buf.push(((val >> 8) & 0xFF).to_byte())
}

///|
/// Read 4 bytes as a UInt for hashing.
fn read_u32_le(data : Bytes, pos : Int, end : Int) -> UInt {
  if pos + 4 > end {
    return 0U
  }
  data[pos]
  .to_uint()
  .lor(data[pos + 1].to_uint() << 8)
  .lor(data[pos + 2].to_uint() << 16)
  .lor(data[pos + 3].to_uint() << 24)
}

///|
/// Hash a 32-bit value to a table index.
fn hash_u32(v : UInt) -> Int {
  // Knuth multiplicative hash, then mask.
  let h = v.lor(0U) * 2654435761U
  ((h >> 16) & HASH_MASK.reinterpret_as_uint()).reinterpret_as_int()
}

///|
/// Check if 4 bytes at `pos1` and `pos2` match in `data`.
fn match_at(data : Bytes, pos1 : Int, pos2 : Int, end : Int) -> Bool {
  if pos2 + 4 > end {
    return false
  }
  data[pos1] == data[pos2] &&
  data[pos1 + 1] == data[pos2 + 1] &&
  data[pos1 + 2] == data[pos2 + 2] &&
  data[pos1 + 3] == data[pos2 + 3]
}

///|
/// Count matching bytes starting at the given positions.
///
/// Supports overlapping matches (where offset < match length): the decompressor
/// copies byte-by-byte, so a match at offset 1 on all-same data extends to the
/// end of the input. For non-overlapping matches, this reduces to a simple
/// comparison.
fn count_match(data : Bytes, src : Int, dst : Int, end : Int) -> Int {
  let offset = dst - src
  let mut len = 0
  while dst + len < end && data[src + len % offset] == data[dst + len] {
    len = len + 1
  }
  len
}

// ---------------------------------------------------------------------------
// Public API: Compression
// ---------------------------------------------------------------------------

///|
/// Compress data using LZ4 block format.
///
/// Returns the compressed data as `Bytes`. If the input is empty, returns
/// empty bytes.
pub fn compress(input : Bytes) -> Bytes {
  let n = input.length()
  if n == 0 {
    return Bytes::make(0, b'\x00')
  }
  let output : Array[Byte] = []
  // Hash table: maps hash → position in input.
  let hash_table : Array[Int] = Array::make(HASH_SIZE, -1)
  // Literal accumulation.
  let mut literal_start = 0
  let mut pos = 0
  while pos < n {
    let mut found_match = false
    // Only search for matches if we have at least 4 bytes left.
    if pos + MIN_MATCH <= n {
      let h = hash_u32(read_u32_le(input, pos, n))
      let candidate = hash_table[h]
      if candidate >= 0 &&
        pos - candidate <= MAX_OFFSET &&
        match_at(input, candidate, pos, n) {
        // Found a match. Extend it.
        let match_len = count_match(input, candidate, pos, n)
        let actual_match_len = match_len
        if actual_match_len >= MIN_MATCH {
          // Flush pending literals.
          let literal_len = pos - literal_start
          let match_offset = pos - candidate
          // Encode token.
          let lit_nibble = if literal_len >= MAX_NIBBLE {
            MAX_NIBBLE
          } else {
            literal_len
          }
          let match_nibble = if actual_match_len - MIN_MATCH >= MAX_NIBBLE {
            MAX_NIBBLE
          } else {
            actual_match_len - MIN_MATCH
          }
          output.push(((lit_nibble << 4) | match_nibble).to_byte())
          // Extended literal length.
          if literal_len >= MAX_NIBBLE {
            write_length(output, literal_len - MAX_NIBBLE)
          }
          // Literals.
          for i = 0; i < literal_len; i = i + 1 {
            output.push(input[literal_start + i])
          }
          // Match offset.
          write_u16_le(output, match_offset)
          // Extended match length.
          if actual_match_len - MIN_MATCH >= MAX_NIBBLE {
            write_length(output, actual_match_len - MIN_MATCH - MAX_NIBBLE)
          }
          // Update hash table for matched bytes.
          for i = 0; i < actual_match_len && pos + i + MIN_MATCH <= n; i = i + 1 {
            let hi = hash_u32(read_u32_le(input, pos + i, n))
            hash_table[hi] = pos + i
          }
          pos = pos + actual_match_len
          literal_start = pos
          found_match = true
        }
      }
    }
    if !found_match {
      // No match found. Update hash table and advance.
      if pos + MIN_MATCH <= n {
        let h = hash_u32(read_u32_le(input, pos, n))
        hash_table[h] = pos
      }
      pos = pos + 1
    }
  }
  // Flush remaining literals.
  let literal_len = n - literal_start
  if literal_len > 0 {
    let lit_nibble = if literal_len >= MAX_NIBBLE {
      MAX_NIBBLE
    } else {
      literal_len
    }
    output.push((lit_nibble << 4).to_byte())
    if literal_len >= MAX_NIBBLE {
      write_length(output, literal_len - MAX_NIBBLE)
    }
    for i = 0; i < literal_len; i = i + 1 {
      output.push(input[literal_start + i])
    }
  }
  Bytes::from_array(output)
}

// ---------------------------------------------------------------------------
// Public API: Decompression
// ---------------------------------------------------------------------------

///|
/// Decompress LZ4 block-format data.
///
/// Returns the original data, or `None` if the input is corrupt.
pub fn decompress(input : Bytes, max_output_size : Int) -> Bytes? {
  let n = input.length()
  if n == 0 {
    return Some(Bytes::make(0, b'\x00'))
  }
  let output : Array[Byte] = []
  let mut pos = 0
  while pos < n {
    // Read token.
    let token = input[pos].to_int()
    pos = pos + 1
    // Literal length (high nibble of token).
    let mut lit_len = token >> 4
    if lit_len == MAX_NIBBLE {
      match read_length(input, pos, n) {
        None => return None
        Some((ext, new_pos)) => {
          lit_len = lit_len + ext
          pos = new_pos
        }
      }
    }
    // Copy literals.
    if pos + lit_len > n {
      return None
    }
    for i = 0; i < lit_len; i = i + 1 {
      output.push(input[pos + i])
    }
    pos = pos + lit_len
    // If at end of input, this was the last block (literals only).
    if pos >= n {
      break
    }
    // Read match offset (2 bytes LE).
    if pos + 2 > n {
      return None
    }
    let offset = read_u16_le(input, pos)
    pos = pos + 2
    if offset == 0 {
      return None
    }
    // Match length (low nibble of token + 4).
    let mut match_len = (token & 0xF) + MIN_MATCH
    if (token & 0xF) == MAX_NIBBLE {
      match read_length(input, pos, n) {
        None => return None
        Some((ext, new_pos)) => {
          match_len = match_len + ext
          pos = new_pos
        }
      }
    }
    // Copy match from output.
    let out_len = output.length()
    if offset > out_len {
      return None
    }
    if output.length() + match_len > max_output_size {
      return None
    }
    for i = 0; i < match_len; i = i + 1 {
      let src_pos = out_len - offset + i
      if src_pos >= 0 && src_pos < output.length() {
        output.push(output[src_pos])
      } else {
        return None
      }
    }
  }
  Some(Bytes::from_array(output))
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "lz4: empty input" {
  let input = Bytes::make(0, b'\x00')
  let compressed = compress(input)
  let decompressed = match decompress(compressed, 0) {
    None => abort("decompression failed")
    Some(d) => d
  }
  assert_eq(decompressed.length(), 0)
}

///|
test "lz4: short literal" {
  let input = Bytes::make(5, b'\x41')
  let compressed = compress(input)
  let decompressed = match decompress(compressed, 100) {
    None => abort("decompression failed")
    Some(d) => d
  }
  assert_eq(decompressed.length(), input.length())
  for i = 0; i < input.length(); i = i + 1 {
    assert_eq(decompressed[i], input[i])
  }
}

///|
test "lz4: repetitive data" {
  let pattern = Bytes::makei(16, fn(i) { i.to_byte() })
  let input : Array[Byte] = []
  // Repeat the pattern many times.
  for _r = 0; _r < 50; _r = _r + 1 {
    for i = 0; i < 16; i = i + 1 {
      input.push(pattern[i])
    }
  }
  let input_bytes = Bytes::from_array(input)
  let compressed = compress(input_bytes)
  let decompressed = match decompress(compressed, input_bytes.length()) {
    None => abort("decompression failed")
    Some(d) => d
  }
  assert_eq(decompressed.length(), input_bytes.length())
  for i = 0; i < input_bytes.length(); i = i + 1 {
    assert_eq(decompressed[i], input_bytes[i])
  }
}

///|
test "lz4: long repeated sequence" {
  let input_bytes = Bytes::make(10000, b'\x42')
  let compressed = compress(input_bytes)
  let decompressed = match decompress(compressed, input_bytes.length()) {
    None => abort("decompression failed")
    Some(d) => d
  }
  assert_eq(decompressed.length(), input_bytes.length())
  for i = 0; i < input_bytes.length(); i = i + 1 {
    assert_eq(decompressed[i], input_bytes[i])
  }
}

///|
test "lz4: mixed data" {
  let input : Array[Byte] = []
  // Some literal data.
  for i = 0; i < 20; i = i + 1 {
    input.push(i.to_byte())
  }
  // Some repeated data.
  for _r = 0; _r < 30; _r = _r + 1 {
    for i = 0; i < 10; i = i + 1 {
      input.push((i * 3 + 1).to_byte())
    }
  }
  // More literal data.
  for i = 0; i < 15; i = i + 1 {
    input.push((200 + i).to_byte())
  }
  let input_bytes = Bytes::from_array(input)
  let compressed = compress(input_bytes)
  let decompressed = match decompress(compressed, input_bytes.length()) {
    None => abort("decompression failed")
    Some(d) => d
  }
  assert_eq(decompressed.length(), input_bytes.length())
  for i = 0; i < input_bytes.length(); i = i + 1 {
    assert_eq(decompressed[i], input_bytes[i])
  }
}

///|
test "lz4: compression ratio for repetitive data" {
  let input_bytes = Bytes::make(1000, b'\x00')
  let compressed = compress(input_bytes)
  // Compressed should be much smaller than input.
  assert_true(compressed.length() < input_bytes.length())
}

///|
test "lz4: incompressible data round-trips" {
  let input : Array[Byte] = []
  // Pseudo-random but deterministic data (unlikely to compress).
  let mut seed = 12345
  for i = 0; i < 200; i = i + 1 {
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
    input.push((seed & 0xFF).to_byte())
  }
  let input_bytes = Bytes::from_array(input)
  let compressed = compress(input_bytes)
  let decompressed = match decompress(compressed, input_bytes.length()) {
    None => abort("decompression failed")
    Some(d) => d
  }
  assert_eq(decompressed.length(), input_bytes.length())
  for i = 0; i < input_bytes.length(); i = i + 1 {
    assert_eq(decompressed[i], input_bytes[i])
  }
}

///|
test "lz4: overlapping match (RLE-like)" {
  // "AAAAA..." should use offset=1 to copy from previous byte.
  let input_bytes = Bytes::make(100, b'\x41')
  let compressed = compress(input_bytes)
  let decompressed = match decompress(compressed, input_bytes.length()) {
    None => abort("decompression failed")
    Some(d) => d
  }
  assert_eq(decompressed.length(), input_bytes.length())
  for i = 0; i < input_bytes.length(); i = i + 1 {
    assert_eq(decompressed[i], input_bytes[i])
  }
}

///|
test "lz4: large data with extended lengths" {
  // Create data that exceeds 255-byte literal runs.
  let input : Array[Byte] = []
  for i = 0; i < 300; i = i + 1 {
    input.push((i & 0xFF).to_byte())
  }
  // Then repeat to trigger matches.
  for _r = 0; _r < 20; _r = _r + 1 {
    for i = 0; i < 300; i = i + 1 {
      input.push((i & 0xFF).to_byte())
    }
  }
  let input_bytes = Bytes::from_array(input)
  let compressed = compress(input_bytes)
  let decompressed = match decompress(compressed, input_bytes.length()) {
    None => abort("decompression failed")
    Some(d) => d
  }
  assert_eq(decompressed.length(), input_bytes.length())
  for i = 0; i < input_bytes.length(); i = i + 1 {
    assert_eq(decompressed[i], input_bytes[i])
  }
}
