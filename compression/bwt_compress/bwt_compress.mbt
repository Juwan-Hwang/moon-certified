/// BWT-based Compression — Burrows-Wheeler Transform + MTF + Huffman.
///
/// This module assembles a self-contained BWT (operating directly on raw
/// bytes, no sentinel character) with Move-to-Front coding and Huffman
/// coding to create a complete BWT-based compressor, conceptually similar
/// to bzip2's pipeline:
///
/// 1. **BWT**: Reorders data so that similar bytes cluster together.
///    Uses the **primary index** approach — no sentinel is inserted, so
///    the transform works correctly with all 256 byte values.
/// 2. **MTF** (Move-to-Front): Converts local symbol clustering into a
///    skewed distribution of small integers (many zeros), which Huffman
///    can compress efficiently.
/// 3. **Huffman**: Entropy-codes the MTF output. The Huffman tree is
///    **serialized** into the compressed stream so that decompression
///    can reconstruct it without any assumptions about the data distribution.
///
/// ## Format
///
/// ```text
/// [4-byte original_length (big-endian)]
/// [4-byte primary_index  (big-endian)]
/// [4-byte tree_bit_count (big-endian)]
/// [tree_packed_bytes ...]              — ceil(tree_bit_count / 8) bytes
/// [4-byte data_bit_count (big-endian)]
/// [data_packed_bytes ...]              — ceil(data_bit_count / 8) bytes
/// ```
///
/// The tree is serialized via pre-order traversal (see `huffman.serialize_tree`):
/// - `0` bit → internal node (left child, then right child)
/// - `1` bit → leaf, followed by 8 bits for the byte value (MSB first)
///
/// ## Complexity
///
/// - `compress`: O(n² log n) for BWT suffix sort + O(n) for MTF + O(n) for Huffman.
/// - `decompress`: O(n) for Huffman + O(n) for MTF + O(n log n) for BWT inverse.
///
/// ## References
///
/// - Burrows, M. and Wheeler, D. (1994): "A Block-sorting Lossless Data
///   Compression Algorithm"
/// - Fenwick, P. (1996): "Block Sorting Text Compression"
///
/// Not formally verified. Correctness is ensured by the test suite.

// ---------------------------------------------------------------------------
// Sentinel-free BWT operating on raw bytes
// ---------------------------------------------------------------------------

///|
/// Encode bytes using the Burrows-Wheeler Transform (no sentinel).
///
/// Returns `(last_column, primary_index)` where `primary_index` is the row
/// in the sorted rotation matrix that corresponds to the original string.
/// This is the standard production approach and handles all 256 byte values.
fn bwt_encode_bytes(data : Bytes) -> (Bytes, Int) {
  let n = data.length()
  if n == 0 {
    return (b"", 0)
  }
  if n == 1 {
    return (data, 0)
  }
  // Build rotation indices and sort them by cyclic comparison.
  let sa : Array[Int] = []
  for i = 0; i < n; i = i + 1 {
    sa.push(i)
  }
  sa.sort_by(fn(i, j) {
    for k = 0; k < n; k = k + 1 {
      let a = data[(i + k) % n].to_int()
      let b = data[(j + k) % n].to_int()
      if a != b {
        return a.compare(b)
      }
    }
    0
  })
  // Last column: L[i] = data[(sa[i] - 1 + n) % n]
  // Primary index: row where sa[i] == 0
  let bwt : Array[Byte] = Array::make(n, b'\x00')
  let mut primary = 0
  for i = 0; i < n; i = i + 1 {
    bwt[i] = data[(sa[i] - 1 + n) % n]
    if sa[i] == 0 {
      primary = i
    }
  }
  (Bytes::from_array(bwt), primary)
}

///|
/// Decode BWT using LF-mapping with the primary index (no sentinel).
fn bwt_decode_bytes(bwt : Bytes, primary : Int) -> Bytes {
  let n = bwt.length()
  if n == 0 {
    return b""
  }
  if n == 1 {
    return bwt
  }
  // Count occurrences of each byte value.
  let counts = FixedArray::make(256, 0)
  for i = 0; i < n; i = i + 1 {
    counts[bwt[i].to_int()] = counts[bwt[i].to_int()] + 1
  }
  // C[c] = number of bytes strictly less than c (prefix sums).
  let c_table = FixedArray::make(256, 0)
  let mut total = 0
  for c = 0; c < 256; c = c + 1 {
    c_table[c] = total
    total = total + counts[c]
  }
  // Compute rank: number of occurrences of bwt[i] in bwt[0..i).
  let rank = Array::make(n, 0)
  let occ = FixedArray::make(256, 0)
  for i = 0; i < n; i = i + 1 {
    let c = bwt[i].to_int()
    rank[i] = occ[c]
    occ[c] = occ[c] + 1
  }
  // Reconstruct: starting at primary, walk LF-mapping.
  // result[n-1-k] = L[LF^k(primary)]
  let result : Array[Byte] = Array::make(n, b'\x00')
  let mut idx = primary
  for k = 0; k < n; k = k + 1 {
    result[n - 1 - k] = bwt[idx]
    idx = c_table[bwt[idx].to_int()] + rank[idx]
  }
  Bytes::from_array(result)
}

// ---------------------------------------------------------------------------
// Move-to-Front (MTF) transform
// ---------------------------------------------------------------------------

///|
/// Apply Move-to-Front transform to a byte array.
///
/// Maintains a list of all 256 byte values. For each input byte, outputs
/// its current position in the list, then moves it to the front.
fn mtf_encode(data : Bytes) -> Bytes {
  let table : Array[Byte] = Array::make(256, b'\x00')
  for i = 0; i < 256; i = i + 1 {
    table[i] = i.to_byte()
  }
  let result : Array[Byte] = Array::make(data.length(), b'\x00')
  for i = 0; i < data.length(); i = i + 1 {
    let b = data[i]
    let mut pos = 0
    for j = 0; j < 256; j = j + 1 {
      if table[j] == b {
        pos = j
        break
      }
    }
    result[i] = pos.to_byte()
    for j = pos; j > 0; j = j - 1 {
      table[j] = table[j - 1]
    }
    table[0] = b
  }
  Bytes::from_array(result)
}

///|
/// Inverse Move-to-Front transform.
fn mtf_decode(data : Bytes) -> Bytes {
  let table : Array[Byte] = Array::make(256, b'\x00')
  for i = 0; i < 256; i = i + 1 {
    table[i] = i.to_byte()
  }
  let result : Array[Byte] = Array::make(data.length(), b'\x00')
  for i = 0; i < data.length(); i = i + 1 {
    let pos = data[i].to_int()
    let b = table[pos]
    result[i] = b
    for j = pos; j > 0; j = j - 1 {
      table[j] = table[j - 1]
    }
    table[0] = b
  }
  Bytes::from_array(result)
}

// ---------------------------------------------------------------------------
// BWT compression pipeline
// ---------------------------------------------------------------------------

///|
/// Compress data using BWT + MTF + Huffman.
///
/// The compressed format is self-contained: it includes the serialized
/// Huffman tree so that `decompress` can reconstruct it exactly.
///
/// Returns the compressed byte array.
pub fn compress(data : Bytes) -> Bytes {
  if data.length() == 0 {
    return Bytes::from_array([
      b'\x00', b'\x00', b'\x00', b'\x00', // orig_len = 0
      b'\x00', b'\x00', b'\x00', b'\x00', // primary_index = 0
      b'\x00', b'\x00', b'\x00', b'\x00', // tree_bit_count = 0
      b'\x00', b'\x00', b'\x00', b'\x00', // data_bit_count = 0
    ])
  }
  // Apply sentinel-free BWT.
  let (bwt_data, primary) = bwt_encode_bytes(data)
  // Apply MTF.
  let mtf_data = mtf_encode(bwt_data)
  // Build Huffman tree from MTF output and encode.
  let freq = @huffman.build_freq_table(mtf_data)
  let tree = @huffman.build_tree_from_freq(freq)
  let encoded = @huffman.encode_byte(tree, mtf_data)
  let packed = pack_bits(encoded)
  // Serialize the Huffman tree.
  let tree_bits = @huffman.serialize_tree_bit_count(tree)
  let tree_packed = @huffman.serialize_tree(tree)
  // Build output.
  let result : Array[Byte] = []
  let len = data.length()
  // [4-byte original length, big-endian]
  result.push(((len >> 24) & 0xFF).to_byte())
  result.push(((len >> 16) & 0xFF).to_byte())
  result.push(((len >> 8) & 0xFF).to_byte())
  result.push((len & 0xFF).to_byte())
  // [4-byte primary index, big-endian]
  result.push(((primary >> 24) & 0xFF).to_byte())
  result.push(((primary >> 16) & 0xFF).to_byte())
  result.push(((primary >> 8) & 0xFF).to_byte())
  result.push((primary & 0xFF).to_byte())
  // [4-byte tree bit count, big-endian]
  result.push(((tree_bits >> 24) & 0xFF).to_byte())
  result.push(((tree_bits >> 16) & 0xFF).to_byte())
  result.push(((tree_bits >> 8) & 0xFF).to_byte())
  result.push((tree_bits & 0xFF).to_byte())
  // [tree packed bytes]
  for i = 0; i < tree_packed.length(); i = i + 1 {
    result.push(tree_packed[i])
  }
  // [4-byte data bit count, big-endian]
  let valid_bits = encoded.length()
  result.push(((valid_bits >> 24) & 0xFF).to_byte())
  result.push(((valid_bits >> 16) & 0xFF).to_byte())
  result.push(((valid_bits >> 8) & 0xFF).to_byte())
  result.push((valid_bits & 0xFF).to_byte())
  // [data packed bytes]
  for i = 0; i < packed.length(); i = i + 1 {
    result.push(packed[i])
  }
  Bytes::from_array(result)
}

///|
/// Decompress BWT-compressed data.
///
/// Reads the serialized Huffman tree from the stream and uses it to decode
/// the data, ensuring exact round-trip correctness.
///
/// Returns the original byte array, or `None` if the data is corrupt.
pub fn decompress(data : Bytes) -> Bytes? {
  // Minimum: 4 (orig_len) + 4 (primary) + 4 (tree_bits) + 4 (data_bits) = 16 bytes.
  if data.length() < 16 {
    return None
  }
  // Read original length.
  let orig_len = (data[0].to_int() << 24) |
    (data[1].to_int() << 16) |
    (data[2].to_int() << 8) |
    data[3].to_int()
  if orig_len == 0 {
    return Some(b"")
  }
  if orig_len < 0 {
    return None
  }
  // Read primary index.
  let primary = (data[4].to_int() << 24) |
    (data[5].to_int() << 16) |
    (data[6].to_int() << 8) |
    data[7].to_int()
  if primary < 0 || primary >= orig_len {
    return None
  }
  // Read tree bit count.
  let tree_bit_count = (data[8].to_int() << 24) |
    (data[9].to_int() << 16) |
    (data[10].to_int() << 8) |
    data[11].to_int()
  if tree_bit_count < 0 {
    return None
  }
  // Calculate tree byte count.
  let tree_byte_count = (tree_bit_count + 7) / 8
  // Check we have enough data for the tree + data bit count header.
  let tree_end = 12 + tree_byte_count
  if data.length() < tree_end + 4 {
    return None
  }
  // Extract and deserialize the Huffman tree.
  let tree_packed : Array[Byte] = Array::make(tree_byte_count, b'\x00')
  for i = 0; i < tree_byte_count; i = i + 1 {
    tree_packed[i] = data[12 + i]
  }
  let tree = match @huffman.deserialize_tree(
    Bytes::from_array(tree_packed),
    tree_bit_count,
  ) {
    None => return None
    Some(t) => t
  }
  // Read data bit count.
  let data_bit_count = (data[tree_end].to_int() << 24) |
    (data[tree_end + 1].to_int() << 16) |
    (data[tree_end + 2].to_int() << 8) |
    data[tree_end + 3].to_int()
  if data_bit_count < 0 {
    return None
  }
  // Calculate data byte count.
  let data_byte_count = (data_bit_count + 7) / 8
  let data_start = tree_end + 4
  if data.length() < data_start + data_byte_count {
    return None
  }
  // Extract packed data.
  let packed : Array[Byte] = Array::make(data_byte_count, b'\x00')
  for i = 0; i < data_byte_count; i = i + 1 {
    packed[i] = data[data_start + i]
  }
  // Unpack bits.
  let bits = unpack_bits(Bytes::from_array(packed), data_bit_count)
  // Decode using the deserialized Huffman tree.
  let mtf_data = @huffman.decode_byte(tree, bits)
  // After BWT, the data length equals orig_len (no sentinel).
  if mtf_data.length() != orig_len {
    return None
  }
  // Inverse MTF.
  let bwt_data = mtf_decode(mtf_data)
  // Inverse BWT using primary index.
  let result = bwt_decode_bytes(bwt_data, primary)
  Some(result)
}

// ---------------------------------------------------------------------------
// Bit packing utilities
// ---------------------------------------------------------------------------

///|
/// Pack an array of bools (bits) into bytes (MSB first).
fn pack_bits(bits : Array[Bool]) -> Bytes {
  let byte_len = (bits.length() + 7) / 8
  let result : Array[Byte] = Array::make(byte_len, b'\x00')
  for i = 0; i < bits.length(); i = i + 1 {
    if bits[i] {
      result[i / 8] = result[i / 8] | (1 << (7 - (i % 8))).to_byte()
    }
  }
  Bytes::from_array(result)
}

///|
/// Unpack bytes into an array of bools (MSB first).
fn unpack_bits(data : Bytes, count : Int) -> Array[Bool] {
  let result : Array[Bool] = Array::make(count, false)
  for i = 0; i < count; i = i + 1 {
    let byte = data[i / 8]
    result[i] = (byte & (1 << (7 - (i % 8))).to_byte()) != b'\x00'
  }
  result
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "bwt_compress: BWT bytes round-trip" {
  let inputs = [
    Bytes::from_array([b'\x42']),
    Bytes::from_array([b'\x41', b'\x42', b'\x41', b'\x43', b'\x41']),
    Bytes::from_array([b'\x00', b'\x01', b'\x02', b'\x03']),
    Bytes::from_array([b'\xFF', b'\x00', b'\x80', b'\x7F']),
  ]
  for i = 0; i < inputs.length(); i = i + 1 {
    let (encoded, primary) = bwt_encode_bytes(inputs[i])
    let decoded = bwt_decode_bytes(encoded, primary)
    assert_eq(decoded.length(), inputs[i].length())
    for j = 0; j < inputs[i].length(); j = j + 1 {
      assert_eq(decoded[j], inputs[i][j])
    }
  }
}

///|
test "bwt_compress: MTF round-trip" {
  let arr : Array[Byte] = [b'\x41', b'\x42', b'\x41', b'\x43', b'\x41']
  let data = Bytes::from_array(arr)
  let encoded = mtf_encode(data)
  let decoded = mtf_decode(encoded)
  assert_eq(decoded.length(), data.length())
  for i = 0; i < data.length(); i = i + 1 {
    assert_eq(decoded[i], data[i])
  }
}

///|
test "bwt_compress: pack/unpack bits" {
  let bits : Array[Bool] = [true, false, true, true, false, false, true, false, true]
  let packed = pack_bits(bits)
  let unpacked = unpack_bits(packed, bits.length())
  assert_eq(unpacked.length(), bits.length())
  for i = 0; i < bits.length(); i = i + 1 {
    assert_eq(unpacked[i], bits[i])
  }
}

///|
test "bwt_compress: compress/decompress empty" {
  let data = Bytes::make(0, b'\x00')
  let compressed = compress(data)
  let decompressed = decompress(compressed)
  assert_true(decompressed is Some(_))
  let d = decompressed.unwrap()
  assert_eq(d.length(), 0)
}

///|
test "bwt_compress: compress/decompress single byte" {
  let data = Bytes::from_array([b'\x42'])
  let compressed = compress(data)
  let decompressed = decompress(compressed).unwrap()
  assert_eq(decompressed.length(), 1)
  assert_eq(decompressed[0], b'\x42')
}

///|
test "bwt_compress: compress/decompress text" {
  let text = "Hello, World! This is a test of BWT compression."
  let arr : Array[Byte] = []
  for c in text.iter() {
    arr.push(c.to_int().to_byte())
  }
  let data = Bytes::from_array(arr)
  let compressed = compress(data)
  let decompressed = decompress(compressed).unwrap()
  assert_eq(decompressed.length(), data.length())
  for i = 0; i < data.length(); i = i + 1 {
    assert_eq(decompressed[i], data[i])
  }
}

///|
test "bwt_compress: compress/decompress repetitive data" {
  let arr : Array[Byte] = Array::make(100, b'\x41')
  let data = Bytes::from_array(arr)
  let compressed = compress(data)
  assert_true(compressed.length() < data.length())
  let decompressed = decompress(compressed).unwrap()
  assert_eq(decompressed.length(), data.length())
  for i = 0; i < data.length(); i = i + 1 {
    assert_eq(decompressed[i], data[i])
  }
}

///|
test "bwt_compress: compress/decompress binary data" {
  let arr : Array[Byte] = Array::make(256, b'\x00')
  for i = 0; i < 256; i = i + 1 {
    arr[i] = i.to_byte()
  }
  let data = Bytes::from_array(arr)
  let compressed = compress(data)
  let decompressed = decompress(compressed).unwrap()
  assert_eq(decompressed.length(), data.length())
  for i = 0; i < data.length(); i = i + 1 {
    assert_eq(decompressed[i], data[i])
  }
}

///|
test "bwt_compress: compress/decompress random-looking data" {
  let arr : Array[Byte] = [
    b'\xFF', b'\x00', b'\x80', b'\x7F', b'\xFE', b'\x01', b'\x81', b'\x7E',
    b'\xFD', b'\x02', b'\x82', b'\x7D', b'\xFC', b'\x03', b'\x83', b'\x7C',
    b'\xFB', b'\x04', b'\x84', b'\x7B', b'\xFA', b'\x05', b'\x85', b'\x7A',
    b'\xF9', b'\x06', b'\x86', b'\x79', b'\xF8', b'\x07', b'\x87', b'\x78',
  ]
  let data = Bytes::from_array(arr)
  let compressed = compress(data)
  let decompressed = decompress(compressed).unwrap()
  assert_eq(decompressed.length(), data.length())
  for i = 0; i < data.length(); i = i + 1 {
    assert_eq(decompressed[i], data[i])
  }
}

///|
test "bwt_compress: corrupt data returns None" {
  // Too short.
  assert_true(decompress(Bytes::from_array([b'\x01', b'\x02'])) is None)
  // Valid header but truncated data.
  let bad = Bytes::from_array([
    b'\x00', b'\x00', b'\x00', b'\x10', // orig_len = 16
    b'\x00', b'\x00', b'\x00', b'\x00', // primary_index = 0
    b'\x00', b'\x00', b'\x00', b'\x00', // tree_bit_count = 0
    // Missing data bit count and data.
  ])
  assert_true(decompress(bad) is None)
}
