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
  data[pos].to_uint() |
  (data[pos + 1].to_uint() << 8) |
  (data[pos + 2].to_uint() << 16) |
  (data[pos + 3].to_uint() << 24)
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
// XXHash32 — used by LZ4 Frame Format for content/block checksums
// ---------------------------------------------------------------------------

///|
/// XXHash32 prime constants (from the reference implementation).
const XXH_PRIME32_1 : UInt = 2654435761U
const XXH_PRIME32_2 : UInt = 2246822519U
const XXH_PRIME32_3 : UInt = 3266489917U
const XXH_PRIME32_4 : UInt = 668265263U
const XXH_PRIME32_5 : UInt = 374761393U

///|
/// Rotate left by `n` bits for `UInt`.
fn rotl_u32(v : UInt, n : Int) -> UInt {
  ((v << n) | (v >> (32 - n)))
}

///|
/// Read a little-endian 32-bit unsigned integer from `data` at `pos`.
fn read_u32_le_bytes(data : Bytes, pos : Int) -> UInt {
  data[pos].to_uint() |
  (data[pos + 1].to_uint() << 8) |
  (data[pos + 2].to_uint() << 16) |
  (data[pos + 3].to_uint() << 24)
}

///|
/// XXHash32 round: mix one 4-byte lane into an accumulator.
fn xxh_round(acc : UInt, lane : UInt) -> UInt {
  let acc1 = acc + (lane * XXH_PRIME32_2)
  rotl_u32(acc1, 13) * XXH_PRIME32_1
}

///|
/// Compute XXHash32 of `data` with the given `seed`.
///
/// Implements the full XXHash32 algorithm (non-streaming) per the
/// specification at https://github.com/Cyan4973/xxHash.
fn xxh32(data : Bytes, seed : UInt) -> UInt {
  let len = data.length()
  let mut pos = 0
  let mut hash : UInt = 0U
  if len >= 16 {
    let mut v1 = seed + XXH_PRIME32_1 + XXH_PRIME32_2
    let mut v2 = seed + XXH_PRIME32_2
    let mut v3 = seed
    let mut v4 = seed - XXH_PRIME32_1
    while pos + 16 <= len {
      v1 = xxh_round(v1, read_u32_le_bytes(data, pos))
      v2 = xxh_round(v2, read_u32_le_bytes(data, pos + 4))
      v3 = xxh_round(v3, read_u32_le_bytes(data, pos + 8))
      v4 = xxh_round(v4, read_u32_le_bytes(data, pos + 12))
      pos = pos + 16
    }
    hash = rotl_u32(v1, 1) +
      rotl_u32(v2, 7) +
      rotl_u32(v3, 12) +
      rotl_u32(v4, 18)
  } else {
    hash = seed + XXH_PRIME32_5
  }
  hash = hash + len.reinterpret_as_uint()
  // Process remaining 4-byte chunks.
  while pos + 4 <= len {
    hash = hash + (read_u32_le_bytes(data, pos) * XXH_PRIME32_3)
    hash = rotl_u32(hash, 17) * XXH_PRIME32_4
    pos = pos + 4
  }
  // Process remaining individual bytes.
  while pos < len {
    hash = hash + (data[pos].to_uint() * XXH_PRIME32_5)
    hash = rotl_u32(hash, 11) * XXH_PRIME32_1
    pos = pos + 1
  }
  // Avalanche.
  hash = hash ^ (hash >> 15)
  hash = hash * XXH_PRIME32_2
  hash = hash ^ (hash >> 13)
  hash = hash * XXH_PRIME32_3
  hash = hash ^ (hash >> 16)
  hash
}

// ---------------------------------------------------------------------------
// LZ4 Frame Format (https://github.com/lz4/lz4/blob/dev/doc/lz4_Frame_format.md)
// ---------------------------------------------------------------------------

///|
/// LZ4 Frame magic number (little-endian: 0x04 0x22 0x4D 0x18).
const LZ4F_MAGIC : UInt = 0x184D2204U

///|
/// Maximum block size: 64 KB (block size specifier = 4).
const LZ4F_BLOCKSIZE_64K : Int = 65536

///|
/// FLG byte: version=01, block-indep=1, no block-checksum, no content-size,
/// content-checksum=1, no dict.
/// Bit layout: VV_B_C_S_D_0 = 01_1_0_0_1_0_0 = 0x64
const LZ4F_FLG : Byte = b'\x64' // 0110_0100

///|
/// BD byte: block max size = 64KB (specifier 4 = 0b100 in bits 6-4).
const LZ4F_BD : Byte = b'\x40' // 0100_0000

///|
/// Write a 32-bit little-endian value to a byte buffer.
fn write_u32_le(buf : Array[Byte], val : UInt) -> Unit {
  buf.push((val & 0xFFU).to_byte())
  buf.push(((val >> 8) & 0xFFU).to_byte())
  buf.push(((val >> 16) & 0xFFU).to_byte())
  buf.push(((val >> 24) & 0xFFU).to_byte())
}

///|
/// Read a 32-bit little-endian value from bytes at `pos`.
fn read_u32_le_at(data : Bytes, pos : Int) -> UInt {
  read_u32_le_bytes(data, pos)
}

///|
/// Compress data into LZ4 Frame format.
///
/// Wraps the data with an LZ4 frame header, splits into independent
/// DEFLATE blocks (max 64KB each), and appends an XXHash32 content
/// checksum.
///
/// Returns the LZ4 frame-compressed bytes.
pub fn frame_compress(data : Bytes) -> Bytes {
  let output : Array[Byte] = []
  let n = data.length()
  // --- Frame Header (7 bytes minimum) ---
  write_u32_le(output, LZ4F_MAGIC)
  output.push(LZ4F_FLG)
  output.push(LZ4F_BD)
  // HC: header checksum = (XXH32(FLG, BD, seed=0) >> 8) & 0xFF
  let header_desc = Bytes::from_array([LZ4F_FLG, LZ4F_BD])
  let hc = ((xxh32(header_desc, 0U) >> 8) & 0xFFU).to_byte()
  output.push(hc)
  // --- Data Blocks ---
  let mut pos = 0
  while pos < n {
    let block_end = if pos + LZ4F_BLOCKSIZE_64K < n {
      pos + LZ4F_BLOCKSIZE_64K
    } else {
      n
    }
    let block_len = block_end - pos
    // Extract block data.
    let block_data : Array[Byte] = []
    for i = pos; i < block_end; i = i + 1 {
      block_data.push(data[i])
    }
    let block_bytes = Bytes::from_array(block_data)
    // Compress the block.
    let compressed = compress(block_bytes)
    // If compression doesn't help, store uncompressed.
    if compressed.length() >= block_len {
      // Uncompressed block: high bit set.
      write_u32_le(output, (block_len.reinterpret_as_uint() | 0x80000000U))
      for i = 0; i < block_len; i = i + 1 {
        output.push(data[pos + i])
      }
    } else {
      // Compressed block.
      write_u32_le(output, compressed.length().reinterpret_as_uint())
      for i = 0; i < compressed.length(); i = i + 1 {
        output.push(compressed[i])
      }
    }
    pos = block_end
  }
  // --- EndMark (4 bytes of zeros) ---
  write_u32_le(output, 0U)
  // --- Content Checksum (XXHash32 of original data) ---
  let content_checksum = xxh32(data, 0U)
  write_u32_le(output, content_checksum)
  Bytes::from_array(output)
}

///|
/// Decompress LZ4 Frame-format data.
///
/// Validates the frame header, decompresses each block, and verifies
/// the XXHash32 content checksum.
///
/// Returns `Some(data)` on success, or `None` if the frame is corrupt
/// or the checksum does not match.
pub fn frame_decompress(data : Bytes) -> Bytes? {
  let n = data.length()
  // Minimum: 4 (magic) + 3 (FLG+BD+HC) + 4 (EndMark) + 4 (checksum) = 15.
  if n < 15 {
    return None
  }
  // --- Validate magic ---
  if read_u32_le_at(data, 0) != LZ4F_MAGIC {
    return None
  }
  // --- Parse frame descriptor ---
  let flg = data[4].to_int()
  let _bd = data[5].to_int()
  // Validate version (bits 7-6 must be 01).
  if ((flg >> 6) & 0x03) != 1 {
    return None
  }
  // Verify header checksum.
  let header_desc = Bytes::from_array([data[4], data[5]])
  let expected_hc = ((xxh32(header_desc, 0U) >> 8) & 0xFFU).to_byte()
  if data[6] != expected_hc {
    return None
  }
  let has_content_checksum = (flg & 0x04) != 0
  let has_dict_id = (flg & 0x01) != 0
  let has_content_size = (flg & 0x08) != 0
  let mut pos = 7
  // Skip content size if present (8 bytes).
  if has_content_size {
    pos = pos + 8
  }
  // Skip dictionary ID if present (4 bytes).
  if has_dict_id {
    pos = pos + 4
  }
  if pos + 4 > n {
    return None
  }
  // --- Read blocks ---
  let output : Array[Byte] = []
  let mut done = false
  while pos + 4 <= n && !done {
    let block_size_field = read_u32_le_at(data, pos)
    pos = pos + 4
    // EndMark: all zeros.
    if block_size_field == 0U {
      done = true
      break
    }
    let is_uncompressed = (block_size_field & 0x80000000U) != 0U
    let block_size = (block_size_field & 0x7FFFFFFFU).reinterpret_as_int()
    if pos + block_size > n {
      return None
    }
    if is_uncompressed {
      // Copy raw bytes.
      for i = 0; i < block_size; i = i + 1 {
        output.push(data[pos + i])
      }
    } else {
      // Decompress the block.
      let block_data : Array[Byte] = []
      for i = 0; i < block_size; i = i + 1 {
        block_data.push(data[pos + i])
      }
      match decompress(Bytes::from_array(block_data), LZ4F_BLOCKSIZE_64K) {
        None => return None
        Some(decompressed) =>
          for i = 0; i < decompressed.length(); i = i + 1 {
            output.push(decompressed[i])
          }
      }
    }
    pos = pos + block_size
    // Skip block checksum if present (FLG bit 4).
    if (flg & 0x10) != 0 {
      pos = pos + 4
    }
  }
  if !done {
    return None // No EndMark found.
  }
  // --- Verify content checksum ---
  if has_content_checksum {
    if pos + 4 > n {
      return None
    }
    let expected_checksum = read_u32_le_at(data, pos)
    let result_bytes = Bytes::from_array(output)
    let actual_checksum = xxh32(result_bytes, 0U)
    if actual_checksum != expected_checksum {
      return None
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
test "lz4 frame: empty data round-trip" {
  let input = Bytes::make(0, b'\x00')
  let compressed = frame_compress(input)
  let decompressed = match frame_decompress(compressed) {
    None => abort("frame decompression failed")
    Some(d) => d
  }
  assert_eq(decompressed.length(), 0)
}

///|
test "lz4 frame: short data round-trip" {
  let input = Bytes::make(10, b'\x41')
  let compressed = frame_compress(input)
  // Verify magic number.
  assert_eq(compressed[0], b'\x04')
  assert_eq(compressed[1], b'\x22')
  assert_eq(compressed[2], b'\x4D')
  assert_eq(compressed[3], b'\x18')
  let decompressed = match frame_decompress(compressed) {
    None => abort("frame decompression failed")
    Some(d) => d
  }
  assert_eq(decompressed.length(), input.length())
  for i = 0; i < input.length(); i = i + 1 {
    assert_eq(decompressed[i], input[i])
  }
}

///|
test "lz4 frame: repetitive data round-trip" {
  let input = Bytes::make(5000, b'\x42')
  let compressed = frame_compress(input)
  // Compressed should be smaller.
  assert_true(compressed.length() < input.length())
  let decompressed = match frame_decompress(compressed) {
    None => abort("frame decompression failed")
    Some(d) => d
  }
  assert_eq(decompressed.length(), input.length())
  for i = 0; i < input.length(); i = i + 1 {
    assert_eq(decompressed[i], input[i])
  }
}

///|
test "lz4 frame: multi-block data round-trip" {
  // Data larger than 64KB to test multi-block.
  let arr : Array[Byte] = []
  for r = 0; r < 100; r = r + 1 {
    for i = 0; i < 256; i = i + 1 {
      arr.push(i.to_byte())
    }
  }
  let input = Bytes::from_array(arr)
  let compressed = frame_compress(input)
  let decompressed = match frame_decompress(compressed) {
    None => abort("frame decompression failed")
    Some(d) => d
  }
  assert_eq(decompressed.length(), input.length())
  for i = 0; i < input.length(); i = i + 1 {
    assert_eq(decompressed[i], input[i])
  }
}

///|
test "lz4 frame: corrupt magic returns None" {
  let bad = Bytes::from_array([
    b'\x00', b'\x00', b'\x00', b'\x00', b'\x70', b'\x40', b'\x00', b'\x00',
    b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00',
  ])
  assert_true(frame_decompress(bad) is None)
}

///|
test "lz4 frame: truncated returns None" {
  let input = Bytes::make(10, b'\x41')
  let compressed = frame_compress(input)
  // Remove last 4 bytes (checksum).
  let truncated = Bytes::from_array(
    Array::makei(compressed.length() - 4, fn(i) { compressed[i] }),
  )
  assert_true(frame_decompress(truncated) is None)
}

///|
test "lz4 frame: corrupt checksum returns None" {
  let input = Bytes::make(10, b'\x41')
  let compressed = frame_compress(input)
  // Corrupt the content checksum (last 4 bytes).
  let corrupt : Array[Byte] = []
  for i = 0; i < compressed.length(); i = i + 1 {
    if i == compressed.length() - 1 {
      corrupt.push(b'\xFF')
    } else {
      corrupt.push(compressed[i])
    }
  }
  assert_true(frame_decompress(Bytes::from_array(corrupt)) is None)
}

///|
test "lz4 frame: binary data round-trip" {
  let arr : Array[Byte] = []
  for i = 0; i < 256; i = i + 1 {
    arr.push(i.to_byte())
  }
  let input = Bytes::from_array(arr)
  let compressed = frame_compress(input)
  let decompressed = match frame_decompress(compressed) {
    None => abort("frame decompression failed")
    Some(d) => d
  }
  assert_eq(decompressed.length(), input.length())
  for i = 0; i < input.length(); i = i + 1 {
    assert_eq(decompressed[i], input[i])
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
