/// Huffman encoding and decoding.
///
/// A production-grade Huffman coder that builds an optimal prefix-free code
/// from a frequency table and uses it to compress strings and raw byte
/// sequences into bit arrays (`Array[Bool]`), then decompress them back.
///
/// # Algorithm
///
/// 1. The input text is converted to **UTF-8 bytes**, and a frequency table
///    over all 256 possible byte values is built.
/// 2. A **binary min-heap** (priority queue) stores leaf nodes keyed by
///    frequency. The two lowest-frequency nodes are repeatedly extracted
///    and merged into a new internal node whose frequency is their sum.
///    This continues until a single tree remains.
/// 3. The tree is traversed to build a **256-entry code table**: each leaf
///    receives a unique bit sequence (`false` = go left, `true` = go right).
/// 4. **Encoding** replaces every byte with its code. **Decoding** walks the
///    tree from the root, emitting a byte each time a leaf is reached, then
///    resetting to the root.
///
/// # Consistency between String and Bytes APIs
///
/// `build_tree` converts the input string to UTF-8 before counting
/// frequencies. Consequently:
///
/// - `encode(tree, s)` and `encode_byte(tree, utf8_bytes(s))` produce
///   identical bit sequences.
/// - `decode_byte(tree, encode(tree, s))` yields the UTF-8 bytes of `s`.
///
/// This makes the string and byte-level APIs fully interoperable: a tree
/// built from a string can encode/decode the same data at either level.
///
/// # Edge cases
///
/// - **Empty input**: the tree has no root; encoding produces no bits;
///   decoding produces no bytes.
/// - **Single unique byte**: the tree is a single leaf. Each bit in the
///   encoded stream decodes to one copy of that byte (code length = 1).
///
/// # Complexity
///
/// - `build_tree` — O(n + k log k) where n is the input length and k
///   is the number of distinct byte values (at most 256).
/// - `encode` / `encode_byte` — O(n) where n is the input length.
/// - `decode` / `decode_byte` — O(m) where m is the number of bits.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

///|
/// Internal Huffman tree node.
///
/// - `Leaf(byte)` — a leaf carrying a byte value (0–255).
/// - `Internal(left, right)` — `left` is traversed on bit `false` (0),
///   `right` on bit `true` (1).
enum HNode {
  Leaf(Int)
  Internal(HNode, HNode)
}

///|
/// Huffman code tree.
///
/// - `root` — the root node, or `None` for an empty tree (empty input).
/// - `codes` — a 256-entry lookup table mapping byte values to their
///   Huffman codes. Each code is an `Array[Bool]` where `false` = 0-bit
///   and `true` = 1-bit.
///
/// All fields are **package-private**; external callers interact exclusively
/// through `build_tree`, `encode`, `decode`, `encode_byte`, and `decode_byte`.
pub struct HuffmanTree {
  priv root : HNode?
  priv codes : FixedArray[Array[Bool]]
}

// ---------------------------------------------------------------------------
// Min-heap (priority queue) for tree construction
// ---------------------------------------------------------------------------

///|
/// Heap entry: frequency, insertion order (for deterministic tie-breaking),
/// and the tree node it carries.
priv struct HeapItem {
  freq : Int
  order : Int
  node : HNode
}

///|
/// Min-heap comparison: primary key is frequency, secondary key is insertion
/// order (FIFO). This ensures deterministic tree construction even when
/// multiple nodes share the same frequency.
fn heap_less(a : HeapItem, b : HeapItem) -> Bool {
  if a.freq != b.freq {
    a.freq < b.freq
  } else {
    a.order < b.order
  }
}

///|
/// Sift up at index `idx` to restore the min-heap invariant.
fn sift_up(heap : Array[HeapItem], idx : Int) -> Unit {
  let mut i = idx
  while i > 0 {
    let parent = (i - 1) / 2
    if heap_less(heap[i], heap[parent]) {
      let tmp = heap[i]
      heap[i] = heap[parent]
      heap[parent] = tmp
      i = parent
    } else {
      break
    }
  }
}

///|
/// Sift down at index `idx` to restore the min-heap invariant.
fn sift_down(heap : Array[HeapItem], idx : Int) -> Unit {
  let mut i = idx
  let n = heap.length()
  while true {
    let left = 2 * i + 1
    let right = 2 * i + 2
    let mut best = i
    if left < n && heap_less(heap[left], heap[best]) {
      best = left
    }
    if right < n && heap_less(heap[right], heap[best]) {
      best = right
    }
    if best == i {
      break
    }
    let tmp = heap[i]
    heap[i] = heap[best]
    heap[best] = tmp
    i = best
  }
}

///|
/// Push an item onto the min-heap. O(log n).
fn heap_push(heap : Array[HeapItem], item : HeapItem) -> Unit {
  heap.push(item)
  sift_up(heap, heap.length() - 1)
}

///|
/// Pop and return the minimum item. O(log n).
/// Precondition: the heap is non-empty.
fn heap_pop(heap : Array[HeapItem]) -> HeapItem {
  let n = heap.length()
  let top = heap[0]
  heap[0] = heap[n - 1]
  ignore(heap.pop())
  if heap.length() > 0 {
    sift_down(heap, 0)
  }
  top
}

// ---------------------------------------------------------------------------
// UTF-8 helpers
// ---------------------------------------------------------------------------

///|
/// Convert a MoonBit `String` to its UTF-8 byte representation as `Bytes`.
/// Delegates to `@utils.string_to_bytes` to avoid code duplication.
fn string_to_utf8(text : String) -> Bytes {
  @utils.string_to_bytes(text)
}

///|
/// Decode UTF-8 `Bytes` back to a MoonBit `String`.
/// Delegates to `@utils.bytes_to_string` to avoid code duplication.
fn utf8_to_string(bytes : Bytes) -> String {
  @utils.bytes_to_string(bytes)
}

// ---------------------------------------------------------------------------
// Frequency table
// ---------------------------------------------------------------------------

///|
/// Build a 256-entry frequency table from a byte sequence.
/// Entry `i` contains the count of byte value `i` in the input.
fn build_freq_table(bytes : Bytes) -> FixedArray[Int] {
  let freq = FixedArray::make(256, 0)
  let n = bytes.length()
  for i = 0; i < n; i = i + 1 {
    let b = bytes[i].to_int()
    freq[b] = freq[b] + 1
  }
  freq
}

// ---------------------------------------------------------------------------
// Tree construction
// ---------------------------------------------------------------------------

///|
/// Build a Huffman tree from input text.
///
/// The text is converted to UTF-8 bytes, a frequency table is built over
/// those bytes, and a Huffman tree is constructed using a min-heap: the two
/// lowest-frequency nodes are repeatedly merged until a single tree remains.
///
/// The resulting tree can be used with `encode`, `decode`, `encode_byte`,
/// and `decode_byte`. A tree built from string `s` can encode/decode both
/// `s` itself (via the string API) and the raw UTF-8 bytes of `s` (via the
/// byte API).
pub fn build_tree(text : String) -> HuffmanTree {
  let bytes = string_to_utf8(text)
  let freq = build_freq_table(bytes)
  build_tree_from_freq(freq)
}

///|
/// Build a Huffman tree from a 256-entry frequency table.
fn build_tree_from_freq(freq : FixedArray[Int]) -> HuffmanTree {
  // Collect non-zero frequency bytes into a min-heap.
  let heap : Array[HeapItem] = []
  let mut order = 0
  for b = 0; b < 256; b = b + 1 {
    if freq[b] > 0 {
      heap_push(heap, { freq: freq[b], order, node: Leaf(b) })
      order = order + 1
    }
  }
  // Edge case: empty input — no symbols.
  if heap.length() == 0 {
    let empty : Array[Bool] = []
    return { root: None, codes: FixedArray::make(256, empty) }
  }
  // Edge case: single unique symbol — assign a 1-bit code so that
  // decoding works (each bit decodes to one copy of the byte).
  if heap.length() == 1 {
    let only = heap_pop(heap)
    let empty : Array[Bool] = []
    let codes = FixedArray::make(256, empty)
    match only.node {
      Leaf(b) => codes[b] = [false]
      _ =>
        // Internal node as the only entry should not happen because we
        // only push Leaf nodes into the initial heap. Return an empty
        // code table as a safe fallback.
        return { root: None, codes: FixedArray::make(256, []) }
    }
    return { root: Some(only.node), codes }
  }
  // Standard Huffman construction: merge two smallest until one tree remains.
  while heap.length() > 1 {
    let a = heap_pop(heap)
    let b = heap_pop(heap)
    let merged : HNode = Internal(a.node, b.node)
    heap_push(heap, { freq: a.freq + b.freq, order, node: merged })
    order = order + 1
  }
  let root = heap_pop(heap).node
  // Build the code table by traversing the tree.
  let empty : Array[Bool] = []
  let codes = FixedArray::make(256, empty)
  build_codes(root, [], codes)
  { root: Some(root), codes }
}

///|
/// Recursively traverse the tree to populate the code table.
/// `prefix` is a mutable accumulator: bits are pushed before descending
/// and popped after returning, so it is shared across the entire traversal.
fn build_codes(
  node : HNode,
  prefix : Array[Bool],
  codes : FixedArray[Array[Bool]],
) -> Unit {
  match node {
    Leaf(b) => {
      // Snapshot the current prefix into a fresh array.
      let code : Array[Bool] = []
      for j = 0; j < prefix.length(); j = j + 1 {
        code.push(prefix[j])
      }
      codes[b] = code
    }
    Internal(left, right) => {
      prefix.push(false)
      build_codes(left, prefix, codes)
      ignore(prefix.pop())
      prefix.push(true)
      build_codes(right, prefix, codes)
      ignore(prefix.pop())
    }
  }
}

// ---------------------------------------------------------------------------
// Encoding
// ---------------------------------------------------------------------------

///|
/// Encode a string to a sequence of bits using the Huffman tree.
///
/// The string is converted to UTF-8 bytes, and each byte is replaced by its
/// Huffman code. Returns an `Array[Bool]` where `false` = 0-bit and
/// `true` = 1-bit.
pub fn encode(tree : HuffmanTree, text : String) -> Array[Bool] {
  let bytes = string_to_utf8(text)
  encode_bytes(tree, bytes)
}

///|
/// Encode raw bytes to a sequence of bits using the Huffman tree.
///
/// Every byte in `data` must have a non-empty code in the tree (i.e. it must
/// have been present in the text used to build the tree). Bytes with empty
/// codes are silently skipped, which would cause data loss on round-trip.
pub fn encode_byte(tree : HuffmanTree, data : Bytes) -> Array[Bool] {
  encode_bytes(tree, data)
}

///|
/// Internal: encode a byte sequence to bits by looking up each byte's code.
fn encode_bytes(tree : HuffmanTree, bytes : Bytes) -> Array[Bool] {
  let bits : Array[Bool] = []
  let n = bytes.length()
  for i = 0; i < n; i = i + 1 {
    let b = bytes[i].to_int()
    let code = tree.codes[b]
    let m = code.length()
    for j = 0; j < m; j = j + 1 {
      bits.push(code[j])
    }
  }
  bits
}

// ---------------------------------------------------------------------------
// Packed byte stream encoding / decoding
// ---------------------------------------------------------------------------

///|
/// Encode a string to a **packed byte stream** using the Huffman tree.
///
/// Unlike `encode` (which returns `Array[Bool]` with one machine word per
/// bit), this function packs bits LSB-first into bytes, producing a compact
/// representation suitable for actual compression. The first 4 bytes of the
/// output are the **bit count** (little-endian UInt32), so the decoder knows
/// exactly how many bits are valid (the final byte may be zero-padded).
pub fn encode_packed(tree : HuffmanTree, text : String) -> Bytes {
  let bytes = string_to_utf8(text)
  encode_packed_bytes(tree, bytes)
}

///|
/// Encode raw bytes to a **packed byte stream** using the Huffman tree.
pub fn encode_packed_bytes(tree : HuffmanTree, data : Bytes) -> Bytes {
  let bits = encode_bytes(tree, data)
  pack_bits(bits)
}

///|
/// Decode a **packed byte stream** back to a string using the Huffman tree.
pub fn decode_packed(tree : HuffmanTree, packed : Bytes) -> String {
  let bytes = decode_packed_bytes(tree, packed)
  utf8_to_string(bytes)
}

///|
/// Decode a **packed byte stream** back to raw bytes using the Huffman tree.
pub fn decode_packed_bytes(tree : HuffmanTree, packed : Bytes) -> Bytes {
  if packed.length() < 4 {
    return b""
  }
  let bit_count = packed[0].to_int() |
    (packed[1].to_int() << 8) |
    (packed[2].to_int() << 16) |
    (packed[3].to_int() << 24)
  let bits = unpack_bits(packed, 4, bit_count)
  decode_bytes(tree, bits)
}

///|
/// Pack an `Array[Bool]` into a compact `Bytes` with a 4-byte LE bit-count
/// header. Bits are packed LSB-first within each byte.
fn pack_bits(bits : Array[Bool]) -> Bytes {
  let total_bits = bits.length()
  let output : Array[Byte] = []
  // 4-byte LE bit count header.
  output.push((total_bits & 0xFF).to_byte())
  output.push(((total_bits >> 8) & 0xFF).to_byte())
  output.push(((total_bits >> 16) & 0xFF).to_byte())
  output.push(((total_bits >> 24) & 0xFF).to_byte())
  // Pack bits LSB-first.
  let mut current : Int = 0
  let mut count : Int = 0
  for i = 0; i < total_bits; i = i + 1 {
    if bits[i] {
      current = current | (1 << count)
    }
    count = count + 1
    if count == 8 {
      output.push(current.to_byte())
      current = 0
      count = 0
    }
  }
  if count > 0 {
    output.push(current.to_byte())
  }
  Bytes::from_array(output)
}

///|
/// Unpack `bit_count` bits from `data` starting at byte offset `start`.
/// Returns an `Array[Bool]` where `false` = 0-bit, `true` = 1-bit.
fn unpack_bits(data : Bytes, start : Int, bit_count : Int) -> Array[Bool] {
  let bits : Array[Bool] = []
  for i = 0; i < bit_count; i = i + 1 {
    let byte_idx = start + i / 8
    let bit_idx = i % 8
    if byte_idx < data.length() {
      bits.push(((data[byte_idx].to_int() >> bit_idx) & 1) == 1)
    } else {
      bits.push(false)
    }
  }
  bits
}

// ---------------------------------------------------------------------------
// Decoding
// ---------------------------------------------------------------------------

///|
/// Decode a sequence of bits back to a string using the Huffman tree.
///
/// The bits are walked through the tree: `false` goes left, `true` goes
/// right. Each time a leaf is reached, the corresponding byte is emitted
/// and the walk resets to the root. The resulting bytes are interpreted as
/// UTF-8 and converted to a string.
pub fn decode(tree : HuffmanTree, bits : Array[Bool]) -> String {
  let bytes = decode_bytes(tree, bits)
  utf8_to_string(bytes)
}

///|
/// Decode a sequence of bits back to raw bytes using the Huffman tree.
pub fn decode_byte(tree : HuffmanTree, bits : Array[Bool]) -> Bytes {
  decode_bytes(tree, bits)
}

///|
/// Internal: decode a bit sequence to bytes by walking the tree.
fn decode_bytes(tree : HuffmanTree, bits : Array[Bool]) -> Bytes {
  let result : Array[Byte] = []
  match tree.root {
    None => b""
    Some(root) =>
      match root {
        Leaf(b) => {
          // Single-leaf tree: each bit decodes to one copy of the byte.
          let byte = b.to_byte()
          for i = 0; i < bits.length(); i = i + 1 {
            result.push(byte)
          }
          Bytes::from_array(result)
        }
        Internal(_, _) => {
          let mut node = root
          for i = 0; i < bits.length(); i = i + 1 {
            node = match node {
              Internal(left, right) => if bits[i] { right } else { left }
              Leaf(b) => {
                // Leaf reached mid-walk: emit the byte and restart from root.
                result.push(b.to_byte())
                root
              }
            }
            match node {
              Leaf(b) => {
                result.push(b.to_byte())
                node = root
              }
              _ => ()
            }
          }
          Bytes::from_array(result)
        }
      }
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "Huffman: empty string round-trip" {
  let tree = build_tree("")
  let bits = encode(tree, "")
  assert_eq(bits.length(), 0)
  assert_eq(decode(tree, bits), "")
}

///|
test "Huffman: single character" {
  let tree = build_tree("a")
  let bits = encode(tree, "a")
  assert_eq(bits.length(), 1)
  assert_eq(decode(tree, bits), "a")
}

///|
test "Huffman: repeated single character" {
  let tree = build_tree("aaaaa")
  let bits = encode(tree, "aaaaa")
  // Single unique byte -> 1 bit per occurrence.
  assert_eq(bits.length(), 5)
  assert_eq(decode(tree, bits), "aaaaa")
}

///|
test "Huffman: hello world round-trip" {
  let text = "hello world"
  let tree = build_tree(text)
  let bits = encode(tree, text)
  assert_eq(decode(tree, bits), text)
}

///|
test "Huffman: abracadabra round-trip" {
  let text = "abracadabra"
  let tree = build_tree(text)
  let bits = encode(tree, text)
  assert_eq(decode(tree, bits), text)
}

///|
test "Huffman: UTF-8 text round-trip" {
  let text = "你好，世界！Hello World!"
  let tree = build_tree(text)
  let bits = encode(tree, text)
  assert_eq(decode(tree, bits), text)
}

///|
test "Huffman: byte-level round-trip" {
  let text = "hello world"
  let tree = build_tree(text)
  let data = b"hello world"
  let bits = encode_byte(tree, data)
  let decoded = decode_byte(tree, bits)
  assert_eq(decoded, data)
}

///|
test "Huffman: byte-level with subset" {
  let text = "the quick brown fox jumps over the lazy dog"
  let tree = build_tree(text)
  let data = b"fox"
  let bits = encode_byte(tree, data)
  let decoded = decode_byte(tree, bits)
  assert_eq(decoded, data)
}

///|
test "Huffman: consistency between string and byte API" {
  let text = "hello world"
  let tree = build_tree(text)
  // Encoding via the string API, then decoding via the byte API should
  // yield the UTF-8 bytes of the original string.
  let bits = encode(tree, text)
  let bytes = decode_byte(tree, bits)
  assert_eq(bytes, b"hello world")
}

///|
test "Huffman: compression ratio" {
  // Frequencies: a=5, b=4, c=2, d=1
  // Expected Huffman codes (with FIFO tie-breaking):
  //   a: 0         (1 bit)
  //   b: 11        (2 bits)
  //   c: 101       (3 bits)
  //   d: 100       (3 bits)
  // Total: 5*1 + 4*2 + 2*3 + 1*3 = 22 bits
  let text = "aaaaabbbbccd"
  let tree = build_tree(text)
  let bits = encode(tree, text)
  assert_eq(bits.length(), 22)
  // Raw size would be 12 bytes * 8 = 96 bits.
  assert_true(bits.length() < 96)
  assert_eq(decode(tree, bits), text)
}

///|
test "Huffman: large text round-trip" {
  let sb = StringBuilder()
  for i = 0; i < 100; i = i + 1 {
    sb.write_string("the quick brown fox jumps over the lazy dog. ")
  }
  let text = sb.to_string()
  let tree = build_tree(text)
  let bits = encode(tree, text)
  assert_eq(decode(tree, bits), text)
  // Encoded size should be significantly smaller than raw.
  assert_true(bits.length() < text.length() * 8)
}

///|
test "Huffman: all same bytes round-trip" {
  let data = b"aaaa"
  // Build tree from the corresponding string.
  let tree = build_tree("aaaa")
  let bits = encode_byte(tree, data)
  // Single unique byte -> 1 bit per occurrence.
  assert_eq(bits.length(), 4)
  let decoded = decode_byte(tree, bits)
  assert_eq(decoded, data)
}

///|
test "Huffman: single byte round-trip" {
  let tree = build_tree("x")
  let data = b"x"
  let bits = encode_byte(tree, data)
  assert_eq(bits.length(), 1)
  let decoded = decode_byte(tree, bits)
  assert_eq(decoded, data)
}

///|
test "Huffman: empty bytes round-trip" {
  let tree = build_tree("")
  let bits = encode_byte(tree, b"")
  assert_eq(bits.length(), 0)
  let decoded = decode_byte(tree, bits)
  assert_eq(decoded, b"")
}

///|
test "Huffman: more frequent bytes have shorter codes" {
  // 'a' has the highest frequency, so it should get the shortest code.
  let text = "aaaaabbbbccd"
  let tree = build_tree(text)
  let bits_a = encode_byte(tree, b"a")
  let bits_d = encode_byte(tree, b"d")
  // 'a' (freq 5) should have a shorter code than 'd' (freq 1).
  assert_true(bits_a.length() <= bits_d.length())
  assert_true(bits_a.length() < bits_d.length())
}

///|
test "Huffman: prefix-free property (no code is a prefix of another)" {
  // Build a tree with diverse frequencies.
  let text = "abracadabra"
  let tree = build_tree(text)
  // Encode each unique character individually and verify that no
  // code is a prefix of another. This is guaranteed by the tree
  // structure but we verify it empirically.
  let unique_bytes = b"abcd"
  let codes : Array[Array[Bool]] = []
  for i = 0; i < unique_bytes.length(); i = i + 1 {
    let b = unique_bytes[i].to_int()
    codes.push(tree.codes[b])
  }
  // Check all pairs: no code is a prefix of another.
  for i = 0; i < codes.length(); i = i + 1 {
    for j = 0; j < codes.length(); j = j + 1 {
      if i != j {
        let ci = codes[i]
        let cj = codes[j]
        let mut is_prefix = true
        if ci.length() > cj.length() {
          is_prefix = false
        } else {
          for k = 0; k < ci.length(); k = k + 1 {
            if ci[k] != cj[k] {
              is_prefix = false
              break
            }
          }
        }
        assert_true(!is_prefix)
      }
    }
  }
}

///|
test "Huffman: mixed ASCII and non-ASCII round-trip" {
  let text = "ABCabc123你好世界!@#$%^&*()"
  let tree = build_tree(text)
  let bits = encode(tree, text)
  assert_eq(decode(tree, bits), text)
}

///|
test "Huffman: binary data round-trip via byte API" {
  // Build the tree from a string that covers every byte value appearing in
  // the test data below, so that all bytes have non-empty codes.
  let text = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789, !"
  let tree = build_tree(text)
  let data = b"Hello, World! 123"
  let bits = encode_byte(tree, data)
  let decoded = decode_byte(tree, bits)
  assert_eq(decoded, data)
}

///|
test "Huffman: deterministic tree construction" {
  // The same input should always produce the same encoding.
  let text = "abracadabra"
  let tree1 = build_tree(text)
  let tree2 = build_tree(text)
  let bits1 = encode(tree1, text)
  let bits2 = encode(tree2, text)
  assert_eq(bits1.length(), bits2.length())
  for i = 0; i < bits1.length(); i = i + 1 {
    assert_eq(bits1[i], bits2[i])
  }
}

///|
test "Huffman: packed round-trip (hello world)" {
  let text = "hello world"
  let tree = build_tree(text)
  let packed = encode_packed(tree, text)
  let decoded = decode_packed(tree, packed)
  assert_eq(decoded, text)
  // Packed should be smaller than raw bytes.
  assert_true(packed.length() < text.length())
}

///|
test "Huffman: packed round-trip (empty)" {
  let tree = build_tree("")
  let packed = encode_packed(tree, "")
  let decoded = decode_packed(tree, packed)
  assert_eq(decoded, "")
}

///|
test "Huffman: packed round-trip (single char)" {
  let tree = build_tree("a")
  let packed = encode_packed(tree, "a")
  let decoded = decode_packed(tree, packed)
  assert_eq(decoded, "a")
}

///|
test "Huffman: packed round-trip (UTF-8)" {
  let text = "你好，世界！Hello World!"
  let tree = build_tree(text)
  let packed = encode_packed(tree, text)
  let decoded = decode_packed(tree, packed)
  assert_eq(decoded, text)
}

///|
test "Huffman: packed round-trip (large text)" {
  let sb = StringBuilder()
  for i = 0; i < 200; i = i + 1 {
    sb.write_string("the quick brown fox jumps over the lazy dog. ")
  }
  let text = sb.to_string()
  let tree = build_tree(text)
  let packed = encode_packed(tree, text)
  let decoded = decode_packed(tree, packed)
  assert_eq(decoded, text)
  // Huffman coding on English text typically achieves ~60% compression.
  assert_true(packed.length() < text.length())
}

///|
test "Huffman: packed byte API round-trip" {
  let text = "the quick brown fox jumps over the lazy dog"
  let tree = build_tree(text)
  let data = b"fox jumps"
  let packed = encode_packed_bytes(tree, data)
  let decoded = decode_packed_bytes(tree, packed)
  assert_eq(decoded, data)
}

///|
test "Huffman: packed is smaller than Array[Bool]" {
  let text = "aaaaabbbbccd"
  let tree = build_tree(text)
  let bits = encode(tree, text)
  let packed = encode_packed(tree, text)
  // Array[Bool] uses ~8 bytes per bit (one Bool per word).
  // Packed uses ~1 bit per bit. So packed should be much smaller.
  assert_true(packed.length() < bits.length())
}
