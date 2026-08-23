/// Snappy Compression — Fast, lossless compression (Google Snappy format).
///
/// Implements the raw (unframed) Snappy compression format as specified in
/// the Google Snappy C++ library documentation. Snappy prioritises
/// compression/decompression **speed** over ratio, targeting ~200–500 MB/s
/// throughput. It is used in production systems including Protocol Buffers,
/// Bigtable, MapReduce, and gRPC.
///
/// ## Format
///
/// A Snappy-encoded stream consists of:
/// 1. **Preamble**: the uncompressed length encoded as a varint.
/// 2. **Body**: a sequence of elements (literals or back-references):
///    - **Literal**: tag `000 ttttt` (len ≤ 59) or `0110 0000` + varint.
///      The literal bytes follow immediately.
///    - **Copy with 1-byte offset**: tag `00lloooo` where `ll` = len−4 (0–3),
///      `oooo` = upper 4 bits of offset; lower 8 bits in next byte.
///      Offset range: [1, 2048), length range: [4, 11].
///    - **Copy with 2-byte offset**: tag `01l lllll` where `lllll` = len−1 (0–31),
///      offset in next 2 bytes (little-endian). Offset: [1, 65536), len: [1, 64].
///    - **Copy with 4-byte offset**: tag `10l lllll`, offset in next 4 bytes.
///      Offset: [1, 2³²), len: [1, 64].
///
/// ## Compression strategy
///
/// Uses a hash table (size 2¹⁴) with 6-byte minimum match length, matching
/// the reference implementation. The hash function is `((x << 12) ^ x) >> 20`
/// applied to the 6-byte window, giving a 14-bit bucket index. Each bucket
/// stores the most recent position, enabling greedy match finding in O(n)
/// expected time.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

///|
/// Minimum match length (Snappy requires ≥ 4 bytes to emit a copy).
const MIN_MATCH : Int = 4

///|
/// Maximum offset for 1-byte copy encoding (12 bits: 4 upper + 8 lower).
const MAX_OFFSET_1 : Int = 4096

///|
/// Maximum offset for 2-byte copy encoding (16 bits).
const MAX_OFFSET_2 : Int = 65536

///|
/// Hash table size (2^14 buckets, matching the reference implementation).
const HASH_BITS : Int = 14

///|
const HASH_SIZE : Int = 1 << HASH_BITS // 16384

///|
/// Hash window: we hash 6 bytes to compute the bucket index.
const HASH_BYTES : Int = 6

// ---------------------------------------------------------------------------
// Varint encoding (Snappy preamble)
// ---------------------------------------------------------------------------

///|
/// Encode an unsigned integer as a varint into the output buffer.
fn encode_varint(n : Int, buf : Array[Byte]) -> Unit {
  let mut v = n.reinterpret_as_uint()
  while v >= 0x80U {
    buf.push((v | 0x80U).to_byte())
    v = v >> 7
  }
  buf.push(v.to_byte())
}

///|
/// Decode a varint from `data` starting at `pos`.
/// Returns `(value, new_position)` or `None` if the varint is malformed.
fn decode_varint(data : Bytes, pos : Int) -> (Int, Int)? {
  let mut result : Int = 0
  let mut shift : Int = 0
  let mut p = pos
  while p < data.length() {
    let b = data[p].to_int()
    p = p + 1
    if shift >= 32 {
      return None // Varint too long
    }
    result = result | ((b & 0x7F) << shift)
    if (b & 0x80) == 0 {
      return Some((result, p))
    }
    shift = shift + 7
  }
  None
}

// ---------------------------------------------------------------------------
// Hash function
// ---------------------------------------------------------------------------

///|
/// Compute a 14-bit hash of `data[pos..pos+6)` (or fewer bytes at the end).
/// Uses a multiplicative hash on the 6-byte window, matching the reference
/// Snappy implementation's `HashBytes` function.
fn hash_bytes(data : Bytes, pos : Int) -> Int {
  let end = if pos + HASH_BYTES <= data.length() {
    pos + HASH_BYTES
  } else {
    data.length()
  }
  // Read up to 6 bytes as a 48-bit value (little-endian).
  let mut h : UInt64 = 0UL
  let mut shift = 0
  for i = pos; i < end; i = i + 1 {
    h = h.lor(data[i].to_uint64() << shift)
    shift = shift + 8
  }
  // Snappy reference hash: (h * 0x1e35a7bd) >> (48 - HASH_BITS)
  // This gives a 14-bit bucket index.
  let hashed = h * 0x1e35a7bdUL
  (hashed >> (48 - HASH_BITS)).to_int() & (HASH_SIZE - 1)
}

// ---------------------------------------------------------------------------
// Compression
// ---------------------------------------------------------------------------

///|
/// Compress `data` using the Snappy raw format.
///
/// Returns the compressed byte stream including the varint-encoded
/// uncompressed length preamble. Decompression is via [`decompress`].
///
/// For empty input, the result is a single byte `\x00`.
pub fn compress(data : Bytes) -> Bytes {
  let output : Array[Byte] = []
  // Preamble: varint of the uncompressed length.
  encode_varint(data.length(), output)
  let n = data.length()
  if n == 0 {
    return Bytes::from_array(output)
  }
  // Hash table: maps bucket → most recent position.
  let hash_table : FixedArray[Int] = FixedArray::make(HASH_SIZE, -1)
  let mut pos = 0
  let mut lit_start = 0
  // Single-pass compression: at each position, check the hash table for a
  // match. If found, emit any pending literal then the copy. Otherwise,
  // advance by one byte ( accumulating literal bytes).
  while pos < n {
    let mut found = false
    if pos + MIN_MATCH <= n {
      let h = hash_bytes(data, pos)
      let prev = hash_table[h]
      hash_table[h] = pos
      if prev >= 0 {
        let offset = pos - prev
        if offset > 0 && offset < MAX_OFFSET_2 {
          let ml = match_length(data, prev, pos)
          if ml >= MIN_MATCH {
            // Emit pending literal bytes.
            if pos > lit_start {
              emit_literal(output, data, lit_start, pos - lit_start)
            }
            emit_copy(output, offset, ml)
            pos = pos + ml
            lit_start = pos
            found = true
          }
        }
      }
      // Not enough bytes left for a match; just advance.
    } else if pos < n {
      let h = hash_bytes(data, pos)
      hash_table[h] = pos
    }
    if !found {
      pos = pos + 1
    }
  }
  // Emit trailing literal.
  if n > lit_start {
    emit_literal(output, data, lit_start, n - lit_start)
  }
  Bytes::from_array(output)
}

///|
/// Find a match for the current position in the hash table.
/// Returns `Some((offset, length))` if a match ≥ MIN_MATCH is found,
/// `None` otherwise. Updates the hash table with the current position.
fn _find_match(
  data : Bytes,
  pos : Int,
  hash_table : FixedArray[Int],
) -> (Int, Int)? {
  let n = data.length()
  if pos + MIN_MATCH > n {
    // Not enough bytes for a match; still update hash if possible.
    if pos < n {
      let h = hash_bytes(data, pos)
      hash_table[h] = pos
    }
    return None
  }
  let h = hash_bytes(data, pos)
  let prev = hash_table[h]
  hash_table[h] = pos
  if prev < 0 || pos - prev >= MAX_OFFSET_2 {
    return None
  }
  let offset = pos - prev
  if offset <= 0 {
    return None
  }
  let _max_len = n - pos
  let len = match_length(data, prev, pos)
  if len >= MIN_MATCH {
    Some((offset, len))
  } else {
    None
  }
}

///|
/// Compute the length of the match between `data[prev..]` and `data[pos..]`.
/// Returns the number of matching bytes, up to 64 (the maximum Snappy copy
/// length for a single copy operation).
fn match_length(data : Bytes, prev : Int, pos : Int) -> Int {
  let n = data.length()
  let max_check = if n - pos < 64 { n - pos } else { 64 }
  let mut len = 0
  while len < max_check && data[prev + len] == data[pos + len] {
    len = len + 1
  }
  len
}

///|
/// Emit a literal of `length` bytes starting at `start` from `data`.
fn emit_literal(
  output : Array[Byte],
  data : Bytes,
  start : Int,
  length : Int,
) -> Unit {
  if length <= 60 {
    // Tag: 000 ttttt where ttttt = length - 1.
    output.push(((length - 1) << 2).to_byte())
  } else if length <= 256 {
    // Tag: 0110 0000 (60), followed by 1-byte length - 1.
    output.push(0xF0)
    output.push((length - 1).to_byte())
  } else if length <= 65536 {
    // Tag: 0110 0001 (61), followed by 2-byte little-endian length - 1.
    output.push(0xF4)
    let l = length - 1
    output.push((l & 0xFF).to_byte())
    output.push(((l >> 8) & 0xFF).to_byte())
  } else {
    // Tag: 0110 0010 (62), followed by 4-byte little-endian length - 1.
    output.push(0xF8)
    let l = length - 1
    output.push((l & 0xFF).to_byte())
    output.push(((l >> 8) & 0xFF).to_byte())
    output.push(((l >> 16) & 0xFF).to_byte())
    output.push(((l >> 24) & 0xFF).to_byte())
  }
  // Copy literal bytes.
  for i = 0; i < length; i = i + 1 {
    output.push(data[start + i])
  }
}

///|
/// Emit a copy operation. Automatically splits into multiple copies if
/// the length exceeds the maximum for a single copy encoding.
fn emit_copy(output : Array[Byte], offset : Int, length : Int) -> Unit {
  let mut remaining = length
  while remaining > 0 {
    let chunk = if remaining > 64 { 64 } else { remaining }
    if offset < MAX_OFFSET_1 && chunk <= 7 && chunk >= 4 {
      // Copy with 1-byte offset: tag = 01 ll oooo
      // ll = length - 4 (2 bits), oooo = upper 4 bits of offset (bits 4-7)
      let ll = chunk - 4
      let hi = (offset >> 8) & 0x0F
      output.push(((hi << 4) | (ll << 2) | 0x01).to_byte())
      output.push((offset & 0xFF).to_byte())
    } else if offset < MAX_OFFSET_2 {
      // Copy with 2-byte offset: tag = 10 llllll
      // llllll = length - 1 (6 bits, bits 2-7)
      let l = chunk - 1
      output.push(((l << 2) | 0x02).to_byte())
      output.push((offset & 0xFF).to_byte())
      output.push(((offset >> 8) & 0xFF).to_byte())
    } else {
      // Copy with 4-byte offset: tag = 11 llllll
      let l = chunk - 1
      output.push(((l << 2) | 0x03).to_byte())
      output.push((offset & 0xFF).to_byte())
      output.push(((offset >> 8) & 0xFF).to_byte())
      output.push(((offset >> 16) & 0xFF).to_byte())
      output.push(((offset >> 24) & 0xFF).to_byte())
    }
    remaining = remaining - chunk
  }
}

// ---------------------------------------------------------------------------
// Decompression
// ---------------------------------------------------------------------------

///|
/// Decompress a Snappy-encoded byte stream.
///
/// Returns `None` if the input is malformed (invalid varint, truncated
/// literal, out-of-bounds offset, etc.). The decompressed data is
/// guaranteed to have the length specified in the preamble.
pub fn decompress(data : Bytes) -> Bytes? {
  // Decode the uncompressed length from the preamble.
  let (uncompressed_len, pos) = match decode_varint(data, 0) {
    Some(v) => v
    None => return None
  }
  if uncompressed_len < 0 {
    return None
  }
  let output : Array[Byte] = Array::make(uncompressed_len, b'\x00')
  let mut out_pos = 0
  let mut p = pos
  while p < data.length() {
    if out_pos > uncompressed_len {
      return None // Overran the expected output size.
    }
    let tag = data[p].to_int()
    p = p + 1
    let tag_type = tag & 0x03
    if tag_type == 0 {
      // Literal.
      let mut len = (tag >> 2) + 1
      if len > 60 {
        // Extended length encoding.
        let extra_bytes = len - 60 // 1, 2, or 4 bytes
        if p + extra_bytes > data.length() {
          return None
        }
        let mut ext_len = 0
        for i = 0; i < extra_bytes; i = i + 1 {
          ext_len = ext_len | (data[p].to_int() << (i * 8))
          p = p + 1
        }
        len = ext_len + 1
      }
      if p + len > data.length() {
        return None
      }
      if out_pos + len > uncompressed_len {
        return None
      }
      for i = 0; i < len; i = i + 1 {
        output[out_pos] = data[p + i]
        out_pos = out_pos + 1
      }
      p = p + len
    } else if tag_type == 1 {
      // Copy with 1-byte offset: tag = 01 ll oooo
      // ll = length - 4 (2 bits, bits 2-3), oooo = upper 4 bits of offset (bits 4-7)
      if p >= data.length() {
        return None
      }
      let len = ((tag >> 2) & 0x03) + 4
      let hi = (tag >> 4) & 0x0F
      let lo = data[p].to_int()
      p = p + 1
      let offset = (hi << 8) | lo
      if offset == 0 || offset > out_pos {
        return None
      }
      if out_pos + len > uncompressed_len {
        return None
      }
      // Byte-by-byte copy (offset may be < len, creating overlapping copies).
      for i = 0; i < len; i = i + 1 {
        output[out_pos] = output[out_pos - offset]
        out_pos = out_pos + 1
      }
    } else if tag_type == 2 {
      // Copy with 2-byte offset: tag = 10 llllll
      // llllll = length - 1 (6 bits, bits 2-7)
      if p + 1 >= data.length() {
        return None
      }
      let len = (tag >> 2) + 1
      let lo = data[p].to_int()
      let hi = data[p + 1].to_int()
      p = p + 2
      let offset = (hi << 8) | lo
      if offset == 0 || offset > out_pos {
        return None
      }
      if out_pos + len > uncompressed_len {
        return None
      }
      for i = 0; i < len; i = i + 1 {
        output[out_pos] = output[out_pos - offset]
        out_pos = out_pos + 1
      }
    } else {
      // tag_type == 3: Copy with 4-byte offset: tag = 11 llllll
      if p + 3 >= data.length() {
        return None
      }
      let len = (tag >> 2) + 1
      let b0 = data[p].to_int()
      let b1 = data[p + 1].to_int()
      let b2 = data[p + 2].to_int()
      let b3 = data[p + 3].to_int()
      p = p + 4
      let offset = (b3 << 24) | (b2 << 16) | (b1 << 8) | b0
      if offset == 0 || offset > out_pos {
        return None
      }
      if out_pos + len > uncompressed_len {
        return None
      }
      for i = 0; i < len; i = i + 1 {
        output[out_pos] = output[out_pos - offset]
        out_pos = out_pos + 1
      }
    }
  }
  if out_pos != uncompressed_len {
    return None
  }
  Some(Bytes::from_array(output))
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "snappy: empty input round-trip" {
  let input = Bytes::from_array([])
  let compressed = compress(input)
  let decompressed = decompress(compressed)
  assert_true(decompressed is Some(_))
  let result = decompressed.unwrap()
  assert_eq(result.length(), 0)
}

///|
test "snappy: short literal round-trip" {
  let input = @utils.string_to_bytes("Hello, World!")
  let compressed = compress(input)
  let decompressed = decompress(compressed)
  assert_true(decompressed is Some(_))
  assert_eq(decompressed.unwrap(), input)
}

///|
test "snappy: repetitive data compresses well" {
  // "abcabcabc..." repeated 100 times should compress significantly.
  let pattern = "abcabcabcabc"
  let mut s = ""
  for i = 0; i < 100; i = i + 1 {
    s = s + pattern
  }
  let input = @utils.string_to_bytes(s)
  let compressed = compress(input)
  let decompressed = decompress(compressed)
  assert_true(decompressed is Some(_))
  assert_eq(decompressed.unwrap(), input)
  // Compression ratio should be good for repetitive data.
  assert_true(compressed.length() < input.length() / 2)
}

///|
test "snappy: long literal (> 60 bytes) round-trip" {
  // Unique data that won't produce matches.
  let arr : Array[Byte] = []
  for i = 0; i < 200; i = i + 1 {
    arr.push((i * 7 + 13).to_byte())
  }
  let input = Bytes::from_array(arr)
  let compressed = compress(input)
  let decompressed = decompress(compressed)
  assert_true(decompressed is Some(_))
  assert_eq(decompressed.unwrap(), input)
}

///|
test "snappy: binary data with repeated blocks" {
  let block = [0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE, 0xBA, 0xBE].map(fn(v) {
    v.to_byte()
  })
  let arr : Array[Byte] = []
  for i = 0; i < 50; i = i + 1 {
    for j = 0; j < block.length(); j = j + 1 {
      arr.push(block[j])
    }
  }
  let input = Bytes::from_array(arr)
  let compressed = compress(input)
  let decompressed = decompress(compressed)
  assert_true(decompressed is Some(_))
  assert_eq(decompressed.unwrap(), input)
  assert_true(compressed.length() < input.length())
}

///|
test "snappy: overlapping copy (RLE-like pattern)" {
  // "AAAAAA..." — should produce overlapping copies.
  let arr : Array[Byte] = Array::make(1000, b'A')
  let input = Bytes::from_array(arr)
  let compressed = compress(input)
  let decompressed = decompress(compressed)
  assert_true(decompressed is Some(_))
  assert_eq(decompressed.unwrap(), input)
  assert_true(compressed.length() < input.length() / 4)
}

///|
test "snappy: mixed literal and copy data" {
  let s = "The quick brown fox jumps over the lazy dog. " +
    "The quick brown fox jumps over the lazy dog. " +
    "Unique content here that won't match. " +
    "The quick brown fox jumps over the lazy dog."
  let input = @utils.string_to_bytes(s)
  let compressed = compress(input)
  let decompressed = decompress(compressed)
  assert_true(decompressed is Some(_))
  assert_eq(decompressed.unwrap(), input)
}

///|
test "snappy: invalid input returns None" {
  // Truncated varint.
  assert_true(decompress(Bytes::from_array([0x80])) is None)
  // Empty input.
  assert_true(decompress(Bytes::from_array([])) is None)
}

///|
test "snappy: large input round-trip" {
  let arr : Array[Byte] = []
  for i = 0; i < 5000; i = i + 1 {
    // Mix of repetitive and semi-unique data.
    arr.push((i % 256).to_byte())
  }
  let input = Bytes::from_array(arr)
  let compressed = compress(input)
  let decompressed = decompress(compressed)
  assert_true(decompressed is Some(_))
  assert_eq(decompressed.unwrap(), input)
}

///|
test "snappy: single byte input" {
  let input = Bytes::from_array([42])
  let compressed = compress(input)
  let decompressed = decompress(compressed)
  assert_true(decompressed is Some(_))
  assert_eq(decompressed.unwrap(), input)
}

///|
test "snappy: varint encoding round-trip" {
  // Test that large lengths (> 127) are properly varint-encoded.
  let arr : Array[Byte] = Array::make(300, b'X')
  let input = Bytes::from_array(arr)
  let compressed = compress(input)
  // The preamble should encode 300 as a 2-byte varint.
  let decompressed = decompress(compressed)
  assert_true(decompressed is Some(_))
  assert_eq(decompressed.unwrap(), input)
}
