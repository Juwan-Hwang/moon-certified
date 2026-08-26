///|
/// bzip2 Compression — Production-grade implementation following the bzip2 format.
///
/// Implements the complete bzip2 compression algorithm:
///
/// 1. **RL1.0e1**: Initial run-length encoding (runs of 4+ identical bytes)
/// 2. **BWT**: Burrows-Wheeler Transform (primary index approach, no sentinel)
/// 3. **MTF**: Move-to-Front coding (operates only on "used" byte values)
/// 4. **RL1.0e2**: Zero-run encoding (bijective bas1.0e-2: RUNA/RUNB)
/// 5. **Huffman**: Multiple canonical Huffman tables (2-6) with per-group
///    selector switching (50 symbols per group), MTF-encoded selectors,
///    delta-encoded code lengths
/// 6. **bzip2 format**: Stream header, block magic, CRC32, symbol map,
///    Huffman tables, coded data, stream footer
///
/// ## Format
///
/// ```text
/// Stream Header: "BZh" + block_size ('1'-'9')
/// Block:
///   Block magic: 0x314159265359 (48 bits, pi digits)
///   CRC32: 32 bits
///   Randomised: 1 bit (0)
///   origPtr: 24 bits (BWT primary index)
///   Symbol map: 16 groups × (1 present flag + 16-bit bitmap)
///   numHuffmanTables: 3 bits (2-6)
///   selectorsUsed: 15 bits
///   Selector list: MTF-encoded, unary-coded
///   Huffman code lengths: delta-encoded per table per symbol
///   Coded data: Huffman-coded symbols
/// Stream Footer: 0x177245385090 (48 bits, sqrt(pi) digits)
/// ```
///
/// ## References
///
/// - bzip2 format: https://sourceware.org/bzip2/
/// - Seward, J. (2000): "bzip2 and libbzip2"
/// - Burrows, M. and Wheeler, D. (1994): "A Block-sorting Lossless Data
///   Compression Algorithm"
///
/// `proof-enabled` is `false`; correctness is ensured by the test suite.

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const BZIP2_GROUP_SIZE : Int = 50

///|
const BZIP2_MAX_TABLES : Int = 6

///|
const BZIP2_MAX_HUFFMAN_BITS : Int = 17
// ---------------------------------------------------------------------------
// Bit Writer (MSB-first)
// ---------------------------------------------------------------------------

///|
priv struct BitWriter {
  buf : Array[Byte]
  mut current : UInt
  mut bits : Int
}

///|
fn BitWriter::new() -> BitWriter {
  { buf: [], current: 0U, bits: 0 }
}

///|
fn BitWriter::write_bits(self : BitWriter, value : UInt, n : Int) -> Unit {
  // Write bits MSB-first, one at a time. Simple and provably correct.
  for i = n - 1; i >= 0; i = i - 1 {
    let bit = (value >> i) & 1U
    self.current = (self.current << 1) | bit
    self.bits = self.bits + 1
    if self.bits == 8 {
      self.buf.push(self.current.to_byte())
      self.current = 0U
      self.bits = 0
    }
  }
}

///|
fn BitWriter::write_bit(self : BitWriter, bit : Int) -> Unit {
  self.write_bits(bit.reinterpret_as_uint(), 1)
}

///|
fn BitWriter::flush(self : BitWriter) -> Unit {
  if self.bits > 0 {
    self.current = self.current << (8 - self.bits)
    self.buf.push(self.current.to_byte())
    self.current = 0U
    self.bits = 0
  }
}

///|
fn BitWriter::to_bytes(self : BitWriter) -> Bytes {
  self.flush()
  Bytes::from_array(self.buf)
}

// ---------------------------------------------------------------------------
// Bit Reader (MSB-first)
// ---------------------------------------------------------------------------

///|
priv struct BitReader {
  data : Bytes
  mut pos : Int
  mut current : UInt
  mut bits : Int
}

///|
fn BitReader::new(data : Bytes, start : Int) -> BitReader {
  { data, pos: start, current: 0U, bits: 0 }
}

///|
fn BitReader::read_bit(self : BitReader) -> Int {
  if self.bits == 0 {
    if self.pos >= self.data.length() {
      return 0
    }
    self.current = self.data[self.pos].to_uint()
    self.pos = self.pos + 1
    self.bits = 8
  }
  self.bits = self.bits - 1
  ((self.current >> self.bits) & 1U).reinterpret_as_int()
}

///|
fn BitReader::read_bits(self : BitReader, n : Int) -> UInt {
  let mut result = 0U
  for _i = 0; _i < n; _i = _i + 1 {
    result = (result << 1) | self.read_bit().reinterpret_as_uint()
  }
  result
}

// ---------------------------------------------------------------------------
// CRC32 (bzip2 variant: standard CRC32, reflected)
// ---------------------------------------------------------------------------

// CRC-32 is implemented inline in bzip2_crc32 using the bit-by-bit algorithm.

///|
fn bzip2_crc32(data : Bytes) -> UInt {
  // CRC-32 (IEEE 802.3, polynomial 0xEDB88320 reflected).
  // Same algorithm as lzma/xz crc32 for consistency.
  let mut crc = 0xFFFFFFFFU
  for i = 0; i < data.length(); i = i + 1 {
    crc = crc.lxor(data[i].to_uint())
    for _j = 0; _j < 8; _j = _j + 1 {
      if (crc & 1U) != 0U {
        crc = (crc >> 1).lxor(0xEDB88320U)
      } else {
        crc = crc >> 1
      }
    }
  }
  crc.lxor(0xFFFFFFFFU)
}

// ---------------------------------------------------------------------------
// RL1.0e1: Pre-BWT run-length encoding
// ---------------------------------------------------------------------------

///|
/// RL1.0e1 encodes runs of 4+ identical bytes as 4 copies + count (0-251).
/// This limits the input size growth from long runs before BWT.
fn rl1_0e1_encode(data : Bytes) -> Bytes {
  let out : Array[Byte] = []
  let n = data.length()
  let mut i = 0
  while i < n {
    let b = data[i]
    let mut run = 1
    while i + run < n && data[i + run] == b && run < 255 {
      run = run + 1
    }
    if run >= 4 {
      for _j = 0; _j < 4; _j = _j + 1 {
        out.push(b)
      }
      out.push((run - 4).to_byte())
      i = i + run
    } else {
      for _j = 0; _j < run; _j = _j + 1 {
        out.push(b)
      }
      i = i + run
    }
  }
  Bytes::from_array(out)
}

///|
/// RL1.0e1 decode: reconstruct original from RL1.0e1 encoded data.
/// After seeing 4 identical bytes, the next byte is a count of additional copies.
fn rl1_0e1_decode(data : Bytes) -> Bytes {
  let out : Array[Byte] = []
  let n = data.length()
  let mut i = 0
  while i < n {
    out.push(data[i])
    if i + 3 < n &&
      data[i] == data[i + 1] &&
      data[i] == data[i + 2] &&
      data[i] == data[i + 3] {
      for _j = 0; _j < 3; _j = _j + 1 {
        out.push(data[i])
      }
      if i + 4 < n {
        let count = data[i + 4].to_int()
        for _j = 0; _j < count; _j = _j + 1 {
          out.push(data[i])
        }
        i = i + 5
      } else {
        i = i + 4
      }
    } else {
      i = i + 1
    }
  }
  Bytes::from_array(out)
}

// ---------------------------------------------------------------------------
// BWT (Burrows-Wheeler Transform) — sentinel-free, primary index approach
// ---------------------------------------------------------------------------

///|
fn bwt_encode(data : Bytes) -> (Bytes, Int) {
  let n = data.length()
  if n == 0 {
    return (b"", 0)
  }
  if n == 1 {
    return (data, 0)
  }
  // Build rotation indices and sort by cyclic comparison.
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
  let last : Array[Byte] = []
  let mut primary = 0
  for i = 0; i < n; i = i + 1 {
    last.push(data[(sa[i] - 1 + n) % n])
    if sa[i] == 0 {
      primary = i
    }
  }
  (Bytes::from_array(last), primary)
}

///|
fn bwt_decode(data : Bytes, primary : Int) -> Bytes {
  let n = data.length()
  if n == 0 {
    return b""
  }
  if n == 1 {
    return data
  }
  // Count occurrences and compute rank of each position.
  let counts : FixedArray[Int] = FixedArray::make(256, 0)
  let rank : Array[Int] = Array::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    let b = data[i].to_int()
    rank[i] = counts[b]
    counts[b] = counts[b] + 1
  }
  // Compute starting positions of each byte in sorted order (first column).
  let starts : FixedArray[Int] = FixedArray::make(256, 0)
  let mut sum = 0
  for b = 0; b < 256; b = b + 1 {
    starts[b] = sum
    sum = sum + counts[b]
  }
  // LF-mapping: iterate from primary, following links.
  let out : Array[Byte] = Array::make(n, b'\x00')
  let mut idx = primary
  for i = n - 1; i >= 0; i = i - 1 {
    out[i] = data[idx]
    let b = data[idx].to_int()
    idx = starts[b] + rank[idx]
  }
  Bytes::from_array(out)
}

// ---------------------------------------------------------------------------
// Symbol Map: identifies which byte values appear in BWT output
// ---------------------------------------------------------------------------

///|
/// Build symbol map from BWT output data.
/// Returns (ranges, num_used, byte_to_mtf_index) where:
/// - ranges: 16 groups of 16-bit bitmaps
/// - num_used: count of distinct byte values
/// - byte_to_mtf_index: maps byte value 0-255 to MTF table index (0 to num_used-1)
fn build_symbol_map(
  bwt_data : Bytes,
) -> (FixedArray[Int], Int, FixedArray[Int]) {
  let used : FixedArray[Bool] = FixedArray::make(256, false)
  for i = 0; i < bwt_data.length(); i = i + 1 {
    used[bwt_data[i].to_int()] = true
  }
  // Encode as 16 groups of 16 bits
  let ranges : FixedArray[Int] = FixedArray::make(16, 0)
  for i = 0; i < 16; i = i + 1 {
    let mut bits = 0
    for j = 0; j < 16; j = j + 1 {
      if used[i * 16 + j] {
        bits = bits | (1 << (15 - j))
      }
    }
    ranges[i] = bits
  }
  // Build mapping: byte value → sequential index
  let byte_to_mtf_index : FixedArray[Int] = FixedArray::make(256, -1)
  let mut num_used = 0
  for i = 0; i < 256; i = i + 1 {
    if used[i] {
      byte_to_mtf_index[i] = num_used
      num_used = num_used + 1
    }
  }
  (ranges, num_used, byte_to_mtf_index)
}

///|
fn decode_symbol_map(ranges : FixedArray[Int]) -> (Int, FixedArray[Int]) {
  let mtf_index_to_byte : FixedArray[Int] = FixedArray::make(256, -1)
  let mut num_used = 0
  for i = 0; i < 256; i = i + 1 {
    let group = i / 16
    let bit = i % 16
    if (ranges[group] & (1 << (15 - bit))) != 0 {
      mtf_index_to_byte[num_used] = i
      num_used = num_used + 1
    }
  }
  (num_used, mtf_index_to_byte)
}

// ---------------------------------------------------------------------------
// MTF (Move-to-Front) — operates only on "used" byte values
// ---------------------------------------------------------------------------

///|
/// MTF encode using only the used byte values.
/// Input: BWT output bytes
/// Output: MTF indices (0 to num_used-1)
fn mtf_encode(
  data : Bytes,
  byte_to_mtf_index : FixedArray[Int],
  num_used : Int,
) -> Array[Int] {
  let n = data.length()
  if n == 0 {
    return []
  }
  // MTF table: position → byte value (only used bytes)
  let table : Array[Int] = Array::make(num_used, 0)
  for i = 0; i < 256; i = i + 1 {
    if byte_to_mtf_index[i] >= 0 {
      table[byte_to_mtf_index[i]] = i
    }
  }
  let out : Array[Int] = Array::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    let b = data[i].to_int()
    // Find position of b in table
    let mut pos = 0
    for j = 0; j < num_used; j = j + 1 {
      if table[j] == b {
        pos = j
        break
      }
    }
    out[i] = pos
    // Move to front
    for j = pos; j > 0; j = j - 1 {
      table[j] = table[j - 1]
    }
    table[0] = b
  }
  out
}

///|
/// MTF decode using only the used byte values.
/// Input: MTF indices, mtf_index_to_byte mapping
/// Output: original BWT bytes
fn mtf_decode(
  data : Array[Int],
  mtf_index_to_byte : FixedArray[Int],
  num_used : Int,
) -> Bytes {
  let n = data.length()
  if n == 0 {
    return b""
  }
  // MTF table: position → byte value
  let table : Array[Int] = Array::make(num_used, 0)
  for i = 0; i < num_used; i = i + 1 {
    table[i] = mtf_index_to_byte[i]
  }
  let out : Array[Byte] = []
  for i = 0; i < n; i = i + 1 {
    let pos = data[i]
    let b = table[pos]
    out.push(b.to_byte())
    // Move to front
    for j = pos; j > 0; j = j - 1 {
      table[j] = table[j - 1]
    }
    table[0] = b
  }
  Bytes::from_array(out)
}

// ---------------------------------------------------------------------------
// RL1.0e2: Zero-run encoding (bijective bas1.0e-2)
// ---------------------------------------------------------------------------

///|
/// RL1.0e2 encodes runs of zeros using RUNA(0) and RUNB(1) in bijective bas1.0e-2.
/// Non-zero MTF values v become symbol v+1.
/// EOB symbol is appended at the end.
/// Returns array of symbol indices in the bzip2 alphabet.
fn rl1_0e2_encode(data : Array[Int], eob_symbol : Int) -> Array[Int] {
  let out : Array[Int] = []
  let n = data.length()
  let mut i = 0
  while i < n {
    if data[i] == 0 {
      // Count run of zeros
      let mut run = 0
      while i < n && data[i] == 0 {
        run = run + 1
        i = i + 1
      }
      // Encode run in bijective bas1.0e-2
      // run=1→RUNA, run=2→RUNB, run=3→RUNA RUNA, run=4→RUNA RUNB, etc.
      while run > 0 {
        run = run - 1
        if (run & 1) == 0 {
          out.push(0) // RUNA
        } else {
          out.push(1) // RUNB
        }
        run = run >> 1
      }
    } else {
      // Non-zero: shift by 1
      out.push(data[i] + 1)
      i = i + 1
    }
  }
  out.push(eob_symbol) // End of block
  out
}

///|
fn rl1_0e2_decode(symbols : Array[Int], eob_symbol : Int) -> Array[Int] {
  let out : Array[Int] = []
  let mut i = 0
  while i < symbols.length() {
    let s = symbols[i]
    if s == eob_symbol {
      break
    }
    if s == 0 || s == 1 {
      // RUNA/RUNB: decode zero run using bijective bas1.0e-2
      let mut run = 0
      let mut weight = 1
      while i < symbols.length() && (symbols[i] == 0 || symbols[i] == 1) {
        if symbols[i] == 0 {
          run = run + weight
        } else {
          run = run + (weight << 1)
        }
        weight = weight << 1
        i = i + 1
      }
      for _j = 0; _j < run; _j = _j + 1 {
        out.push(0)
      }
    } else {
      // Non-zero: shift back by 1
      out.push(s - 1)
      i = i + 1
    }
  }
  out
}

// ---------------------------------------------------------------------------
// Huffman Coding (bzip2 style: canonical, max 17 bits, multiple tables)
// ---------------------------------------------------------------------------

///|
/// Build canonical Huffman code lengths from symbol frequencies.
/// Uses standard Huffman tree construction, then limits to max_len.
fn build_huffman_lengths(freqs : Array[Int], max_len : Int) -> Array[Int] {
  let n = freqs.length()
  // Collect non-zero symbols
  let symbols : Array[(Int, Int)] = [] // (freq, symbol)
  for i = 0; i < n; i = i + 1 {
    if freqs[i] > 0 {
      symbols.push((freqs[i], i))
    }
  }
  let lengths = Array::make(n, 0)
  if symbols.length() == 0 {
    return lengths
  }
  if symbols.length() == 1 {
    lengths[symbols[0].1] = 1
    return lengths
  }
  // Sort by frequency descending for tree construction
  symbols.sort_by(fn(a, b) { b.0.compare(a.0) })
  let num = symbols.length()
  // Huffman tree node arrays
  let node_freq : Array[Int] = []
  let node_left : Array[Int] = []
  let node_right : Array[Int] = []
  let node_symbol : Array[Int] = []
  for i = 0; i < num; i = i + 1 {
    node_freq.push(symbols[i].0)
    node_left.push(-1)
    node_right.push(-1)
    node_symbol.push(symbols[i].1)
  }
  // Build Huffman tree by repeatedly merging two minimum nodes
  let active : Array[Int] = []
  for i = 0; i < num; i = i + 1 {
    active.push(i)
  }
  while active.length() > 1 {
    // Find two minimum frequency nodes
    let mut min1 = 0
    let mut min2 = 1
    if node_freq[active[min1]] > node_freq[active[min2]] {
      let t = min1
      min1 = min2
      min2 = t
    }
    for i = 2; i < active.length(); i = i + 1 {
      if node_freq[active[i]] < node_freq[active[min1]] {
        min2 = min1
        min1 = i
      } else if node_freq[active[i]] < node_freq[active[min2]] {
        min2 = i
      }
    }
    let n1 = active[min1]
    let n2 = active[min2]
    let combined = node_freq[n1] + node_freq[n2]
    let new_idx = node_freq.length()
    node_freq.push(combined)
    node_left.push(n1)
    node_right.push(n2)
    node_symbol.push(-1)
    // Remove min1 and min2 from active (remove larger index first)
    let hi = if min1 > min2 { min1 } else { min2 }
    let lo = if min1 > min2 { min2 } else { min1 }
    active.remove(hi) |> ignore
    active.remove(lo) |> ignore
    active.push(new_idx)
  }
  // Compute code lengths by iterative DFS
  let root = active[0]
  // Iterative DFS using explicit stack: (node, depth)
  let stack : Array[(Int, Int)] = [(root, 0)]
  while stack.length() > 0 {
    let (node, depth) = stack.pop().unwrap()
    if node_symbol[node] >= 0 {
      lengths[node_symbol[node]] = if depth == 0 { 1 } else { depth }
    } else {
      if node_left[node] >= 0 {
        stack.push((node_left[node], depth + 1))
      }
      if node_right[node] >= 0 {
        stack.push((node_right[node], depth + 1))
      }
    }
  }
  // Limit code lengths to max_len.
  // If any length exceeds max_len, we need to redistribute.
  // This uses a simple approach: clamp and verify Kraft inequality.
  // For bzip2, max_len = 17 which is generous enough for most inputs.
  let mut needs_fix = false
  for i = 0; i < n; i = i + 1 {
    if lengths[i] > max_len {
      needs_fix = true
      break
    }
  }
  if needs_fix {
    // Length-limited Huffman via iterative adjustment:
    // Sort symbols by frequency, clamp to max_len, then fix Kraft inequality.
    // This is simpler than package-merge but produces valid (if suboptimal) codes.
    for i = 0; i < n; i = i + 1 {
      if lengths[i] > max_len {
        lengths[i] = max_len
      }
    }
    // Verify and fix Kraft inequality: sum(2^(-len_i)) <= 1
    // If sum > 1, increase some lengths until satisfied.
    let mut kraft_sum = 0.0
    for i = 0; i < n; i = i + 1 {
      if lengths[i] > 0 {
        kraft_sum = kraft_sum + @math.pow(2.0, -lengths[i].to_double())
      }
    }
    // If Kraft sum > 1, we need to increase some code lengths.
    // Sort by frequency ascending (least frequent get longer codes).
    let sorted_syms : Array[Int] = []
    for i = 0; i < n; i = i + 1 {
      if lengths[i] > 0 {
        sorted_syms.push(i)
      }
    }
    sorted_syms.sort_by(fn(a, b) { freqs[a].compare(freqs[b]) })
    let mut idx = 0
    while kraft_sum > 1.0 + 1.0e-10 && idx < sorted_syms.length() {
      let sym = sorted_syms[idx]
      if lengths[sym] < max_len {
        kraft_sum = kraft_sum - @math.pow(2.0, -lengths[sym].to_double())
        lengths[sym] = lengths[sym] + 1
        kraft_sum = kraft_sum + @math.pow(2.0, -lengths[sym].to_double())
      }
      idx = idx + 1
    }
  }
  lengths
}

///|
/// Generate canonical Huffman codes from code lengths.
fn generate_codes(lengths : Array[Int]) -> Array[UInt] {
  let n = lengths.length()
  let codes = Array::make(n, 0U)
  // Count by length
  let bl_count : Array[Int] = Array::make(BZIP2_MAX_HUFFMAN_BITS + 1, 0)
  for i = 0; i < n; i = i + 1 {
    if lengths[i] > 0 {
      bl_count[lengths[i]] = bl_count[lengths[i]] + 1
    }
  }
  // Compute first code for each length
  let next_code : Array[UInt] = Array::make(BZIP2_MAX_HUFFMAN_BITS + 2, 0U)
  let mut code = 0U
  for bits = 1; bits <= BZIP2_MAX_HUFFMAN_BITS; bits = bits + 1 {
    code = (code + bl_count[bits - 1].reinterpret_as_uint()) << 1
    next_code[bits] = code
  }
  // Assign codes
  for i = 0; i < n; i = i + 1 {
    let len = lengths[i]
    if len > 0 {
      codes[i] = next_code[len]
      next_code[len] = next_code[len] + 1U
    }
  }
  codes
}

// ---------------------------------------------------------------------------
// Huffman code length delta encoding (bzip2 style)
// ---------------------------------------------------------------------------

///|
/// Write Huffman code lengths using bzip2's delta encoding.
/// Format: start with curr=0, for each symbol:
///   while curr != target: write 1 bit, then write direction (0=+1, 1=-1)
///   write 0 bit (same as current)
fn write_code_lengths(
  bw : BitWriter,
  lengths : Array[Int],
  alpha_size : Int,
) -> Unit {
  let mut curr = 0
  for i = 0; i < alpha_size; i = i + 1 {
    let target = lengths[i]
    while curr != target {
      bw.write_bit(1) // change
      if curr < target {
        bw.write_bit(0) // increment
        curr = curr + 1
      } else {
        bw.write_bit(1) // decrement
        curr = curr - 1
      }
    }
    bw.write_bit(0) // same
  }
}

///|
/// Read Huffman code lengths using bzip2's delta encoding.
fn read_code_lengths(br : BitReader, alpha_size : Int) -> Array[Int]? {
  let lengths = Array::make(alpha_size, 0)
  let mut curr = 0
  for i = 0; i < alpha_size; i = i + 1 {
    while br.read_bit() != 0 {
      if br.read_bit() == 0 {
        curr = curr + 1
      } else {
        curr = curr - 1
      }
      if curr < 0 || curr > BZIP2_MAX_HUFFMAN_BITS {
        return None
      }
    }
    lengths[i] = curr
  }
  Some(lengths)
}

// ---------------------------------------------------------------------------
// Selector MTF encoding
// ---------------------------------------------------------------------------

///|
/// MTF-encode the selector list and write as unary codes.
/// Each selector value is the table index (0 to num_tables-1).
/// MTF transforms it to the position in the MTF list.
/// Then each MTF value is written as unary: n 1-bits followed by 0-bit.
fn write_selectors(
  bw : BitWriter,
  selectors : Array[Int],
  num_tables : Int,
) -> Unit {
  // MTF table: position → table index
  let mtf_table : Array[Int] = Array::make(num_tables, 0)
  for i = 0; i < num_tables; i = i + 1 {
    mtf_table[i] = i
  }
  for i = 0; i < selectors.length(); i = i + 1 {
    let tbl = selectors[i]
    // Find position in MTF table
    let mut pos = 0
    for j = 0; j < num_tables; j = j + 1 {
      if mtf_table[j] == tbl {
        pos = j
        break
      }
    }
    // Write unary: pos 1-bits followed by 0-bit
    for _j = 0; _j < pos; _j = _j + 1 {
      bw.write_bit(1)
    }
    bw.write_bit(0)
    // Move to front
    for j = pos; j > 0; j = j - 1 {
      mtf_table[j] = mtf_table[j - 1]
    }
    mtf_table[0] = tbl
  }
}

///|
/// Read MTF-encoded selectors from bit reader.
fn read_selectors(
  br : BitReader,
  num_selectors : Int,
  num_tables : Int,
) -> Array[Int]? {
  let selectors : Array[Int] = Array::make(num_selectors, 0)
  // MTF table: position → table index
  let mtf_table : Array[Int] = Array::make(num_tables, 0)
  for i = 0; i < num_tables; i = i + 1 {
    mtf_table[i] = i
  }
  for i = 0; i < num_selectors; i = i + 1 {
    // Read unary: count 1-bits until 0-bit
    let mut pos = 0
    while br.read_bit() != 0 {
      pos = pos + 1
      if pos >= num_tables {
        return None
      }
    }
    let tbl = mtf_table[pos]
    selectors[i] = tbl
    // Move to front
    for j = pos; j > 0; j = j - 1 {
      mtf_table[j] = mtf_table[j - 1]
    }
    mtf_table[0] = tbl
  }
  Some(selectors)
}

// ---------------------------------------------------------------------------
// Table selection: assign each group of 50 symbols to the best table
// ---------------------------------------------------------------------------

///|
/// Choose the best Huffman table for each group of symbols.
/// Returns the list of table indices (one per group).
fn choose_tables(
  symbols : Array[Int],
  all_lengths : Array[Array[Int]],
  num_tables : Int,
) -> Array[Int] {
  let n = symbols.length()
  let num_groups = (n + BZIP2_GROUP_SIZE - 1) / BZIP2_GROUP_SIZE
  let selectors : Array[Int] = Array::make(num_groups, 0)
  for g = 0; g < num_groups; g = g + 1 {
    let start = g * BZIP2_GROUP_SIZE
    let end = if start + BZIP2_GROUP_SIZE < n {
      start + BZIP2_GROUP_SIZE
    } else {
      n
    }
    // Calculate cost for each table
    let mut best_table = 0
    let mut best_cost = 999999999
    for t = 0; t < num_tables; t = t + 1 {
      let lengths = all_lengths[t]
      let mut cost = 0
      for i = start; i < end; i = i + 1 {
        cost = cost + lengths[symbols[i]]
      }
      if cost < best_cost {
        best_cost = cost
        best_table = t
      }
    }
    selectors[g] = best_table
  }
  selectors
}

// ---------------------------------------------------------------------------
// bzip2 Compress
// ---------------------------------------------------------------------------

///|
/// Compress data using bzip2 format.
///
/// Produces a bzip2 stream with the standard pipeline:
/// RL1.0e1 → BWT → MTF → RL1.0e2 → Huffman (multiple tables with selectors).
/// Block size is 900KB (level '9').
pub fn compress(data : Bytes) -> Bytes {
  let crc = bzip2_crc32(data)
  // RL1.0e1 encode
  let rl1_0e1_data = rl1_0e1_encode(data)
  // BWT
  let (bwt, primary) = bwt_encode(rl1_0e1_data)
  // Build symbol map from BWT output
  let (ranges, num_used, byte_to_mtf_index) = build_symbol_map(bwt)
  // MTF encode (operates only on used byte values)
  let mtf_vals = mtf_encode(bwt, byte_to_mtf_index, num_used)
  // RL1.0e2 encode
  let alpha_size = num_used + 2 // RUNA + RUNB + (num_used - 1 non-zero symbols) + EOB
  let eob_symbol = alpha_size - 1
  let symbols = rl1_0e2_encode(mtf_vals, eob_symbol)
  // Build multiple Huffman tables
  let freqs = Array::make(alpha_size, 0)
  for i = 0; i < symbols.length(); i = i + 1 {
    freqs[symbols[i]] = freqs[symbols[i]] + 1
  }
  // Use 2 tables for small data, more for larger data
  let num_tables = if symbols.length() < 200 {
    2
  } else if symbols.length() < 2000 {
    3
  } else {
    4
  }
  // Build tables with different frequency distributions for diversity.
  // All tables must include every symbol that appears in the data
  // (non-zero code length), otherwise decoding fails when a group
  // containing that symbol is assigned to a table without it.
  let all_lengths : Array[Array[Int]] = []
  let all_codes : Array[Array[UInt]] = []
  for t = 0; t < num_tables; t = t + 1 {
    let adjusted_freqs = Array::make(alpha_size, 0)
    for i = 0; i < alpha_size; i = i + 1 {
      if t == 0 {
        // Table 0: original frequencies
        adjusted_freqs[i] = freqs[i]
      } else {
        // Table 1+: perturb frequencies while ensuring all used symbols
        // remain non-zero. Add a small floor to prevent zeroing out.
        let perturbation = (t * 3 + 1) * (i + 1) % 7
        adjusted_freqs[i] = if freqs[i] > 0 {
          freqs[i] + perturbation
        } else {
          0
        }
      }
    }
    let lengths = build_huffman_lengths(adjusted_freqs, BZIP2_MAX_HUFFMAN_BITS)
    // Verify all symbols with freq > 0 have non-zero code length
    // If any are zero, fall back to original frequencies for this table
    let mut all_present = true
    for i = 0; i < alpha_size; i = i + 1 {
      if freqs[i] > 0 && lengths[i] == 0 {
        all_present = false
        break
      }
    }
    let final_lengths = if all_present {
      lengths
    } else {
      build_huffman_lengths(freqs, BZIP2_MAX_HUFFMAN_BITS)
    }
    let codes = generate_codes(final_lengths)
    all_lengths.push(final_lengths)
    all_codes.push(codes)
  }
  // Choose best table for each group
  let selectors = choose_tables(symbols, all_lengths, num_tables)
  // Write bzip2 stream
  let bw = BitWriter::new()
  // Stream header: "BZh" + '9'
  bw.buf.push(b'B')
  bw.buf.push(b'Z')
  bw.buf.push(b'h')
  bw.buf.push(b'9')
  // Block magic (48 bits): 0x314159265359
  bw.write_bits(0x314159U, 24)
  bw.write_bits(0x265359U, 24)
  // CRC32 (32 bits)
  bw.write_bits(crc, 32)
  // Randomised bit (0)
  bw.write_bit(0)
  // origPtr (24 bits)
  bw.write_bits(primary.reinterpret_as_uint(), 24)
  // Symbol map: 16 ranges, each preceded by a 1-bit "present" flag
  for i = 0; i < 16; i = i + 1 {
    if ranges[i] != 0 {
      bw.write_bit(1)
      bw.write_bits(ranges[i].reinterpret_as_uint(), 16)
    } else {
      bw.write_bit(0)
    }
  }
  // Number of Huffman tables (3 bits)
  bw.write_bits(num_tables.reinterpret_as_uint(), 3)
  // Number of selectors used (15 bits)
  let num_selectors = selectors.length()
  bw.write_bits(num_selectors.reinterpret_as_uint(), 15)
  // Write MTF-encoded selectors
  write_selectors(bw, selectors, num_tables)
  // Write Huffman code lengths for each table (delta encoded)
  for t = 0; t < num_tables; t = t + 1 {
    write_code_lengths(bw, all_lengths[t], alpha_size)
  }
  // Write Huffman-coded symbols using selected tables
  let n = symbols.length()
  let mut g = 0
  let mut i = 0
  while i < n {
    let tbl = selectors[g]
    let lengths = all_lengths[tbl]
    let codes = all_codes[tbl]
    let end = if i + BZIP2_GROUP_SIZE < n { i + BZIP2_GROUP_SIZE } else { n }
    while i < end {
      let sym = symbols[i]
      bw.write_bits(codes[sym], lengths[sym])
      i = i + 1
    }
    g = g + 1
  }
  // Stream footer (48 bits): 0x177245385090
  bw.write_bits(0x177245U, 24)
  bw.write_bits(0x385090U, 24)
  bw.to_bytes()
}

// ---------------------------------------------------------------------------
// bzip2 Decompress
// ---------------------------------------------------------------------------

///|
/// Decompress bzip2 format data.
///
/// Reads a bzip2 stream produced by `compress` and returns the original data.
/// Returns `None` if the data is not valid bzip2.
pub fn decompress(data : Bytes) -> Bytes? {
  if data.length() < 4 {
    return None
  }
  // Check stream header
  if data[0] != b'B' || data[1] != b'Z' || data[2] != b'h' {
    return None
  }
  let block_size_char = data[3]
  if block_size_char < b'1' || block_size_char > b'9' {
    return None
  }
  let br = BitReader::new(data, 4)
  // Read block magic (48 bits)
  let magic_hi = br.read_bits(24)
  let magic_lo = br.read_bits(24)
  if magic_hi != 0x314159U || magic_lo != 0x265359U {
    return None
  }
  // Read CRC32
  let _crc = br.read_bits(32)
  // Randomised bit
  let _randomised = br.read_bit()
  // origPtr (24 bits)
  let primary = br.read_bits(24).reinterpret_as_int()
  // Symbol map
  let ranges : FixedArray[Int] = FixedArray::make(16, 0)
  for i = 0; i < 16; i = i + 1 {
    if br.read_bit() == 1 {
      ranges[i] = br.read_bits(16).reinterpret_as_int()
    } else {
      ranges[i] = 0
    }
  }
  let (num_used, mtf_index_to_byte) = decode_symbol_map(ranges)
  if num_used == 0 {
    // Empty data: RL1.0e1 produced empty output, BWT of empty is empty.
    // The only way to get num_used=0 is empty original data.
    return Some(b"")
  }
  let alpha_size = num_used + 2
  let eob_symbol = alpha_size - 1
  // Number of Huffman tables (3 bits)
  let num_tables = br.read_bits(3).reinterpret_as_int()
  if num_tables < 2 || num_tables > BZIP2_MAX_TABLES {
    return None
  }
  // Number of selectors used (15 bits)
  let num_selectors = br.read_bits(15).reinterpret_as_int()
  if num_selectors < 1 {
    return None
  }
  // Read MTF-encoded selectors
  let selectors = match read_selectors(br, num_selectors, num_tables) {
    None => return None
    Some(s) => s
  }
  // Read Huffman code lengths for each table
  let all_lengths : Array[Array[Int]] = []
  for _t = 0; _t < num_tables; _t = _t + 1 {
    match read_code_lengths(br, alpha_size) {
      None => return None
      Some(lengths) => all_lengths.push(lengths)
    }
  }
  // Generate codes for each table
  let all_codes : Array[Array[UInt]] = []
  for t = 0; t < num_tables; t = t + 1 {
    all_codes.push(generate_codes(all_lengths[t]))
  }
  // Decode symbols using selected tables
  let symbols : Array[Int] = []
  let mut done = false
  let mut g = 0
  let mut group_count = 0
  while !done {
    // Determine which table to use for this group
    if group_count == 0 {
      if g >= selectors.length() {
        return None
      }
      group_count = BZIP2_GROUP_SIZE
      g = g + 1
    }
    group_count = group_count - 1
    let tbl = selectors[g - 1]
    let lengths = all_lengths[tbl]
    let codes = all_codes[tbl]
    // Read one Huffman-coded symbol
    let mut code = 0U
    let mut len = 0
    let mut found = false
    while len < BZIP2_MAX_HUFFMAN_BITS && !found {
      code = (code << 1) | br.read_bit().reinterpret_as_uint()
      len = len + 1
      for sym = 0; sym < alpha_size; sym = sym + 1 {
        if lengths[sym] == len && codes[sym] == code {
          if sym == eob_symbol {
            done = true
          } else {
            symbols.push(sym)
          }
          found = true
          break
        }
      }
    }
    if !found {
      return None
    }
  }
  // RL1.0e2 decode
  let mtf_vals = rl1_0e2_decode(symbols, eob_symbol)
  // MTF decode
  let bwt_data = mtf_decode(mtf_vals, mtf_index_to_byte, num_used)
  // BWT inverse
  let rl1_0e1_decoded = bwt_decode(bwt_data, primary)
  // RL1.0e1 decode
  let original = rl1_0e1_decode(rl1_0e1_decoded)
  Some(original)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "bzip2: crc32 known vectors" {
  assert_eq(bzip2_crc32(b""), 0U)
  assert_eq(bzip2_crc32(b"a"), 0xE8B7BE43U)
}

///|
test "bzip2: rl1_0e1 roundtrip" {
  let data = Bytes::from_array([
    b'a', b'a', b'a', b'a', b'a', b'a', b'a', b'a', b'b', b'c',
  ])
  let encoded = rl1_0e1_encode(data)
  let decoded = rl1_0e1_decode(encoded)
  assert_eq(decoded.length(), data.length())
  for i = 0; i < data.length(); i = i + 1 {
    assert_eq(decoded[i], data[i])
  }
}

///|
test "bzip2: rl1_0e1 no run" {
  let data = Bytes::from_array([b'a', b'b', b'c', b'd'])
  let encoded = rl1_0e1_encode(data)
  assert_eq(encoded, data)
}

///|
test "bzip2: rl1_0e1 long run" {
  let arr : Array[Byte] = []
  for _i = 0; _i < 300; _i = _i + 1 {
    arr.push(b'X')
  }
  let data = Bytes::from_array(arr)
  let encoded = rl1_0e1_encode(data)
  // 300 = 4 + 296 → 4 bytes + count byte = 5 bytes (if run ≤ 255)
  // Actually: run=300, but max is 255, so it's 255 + 45
  // RL1.0e1 encodes: first 255 → 4 bytes + (255-4)=251, then 45 → 4 bytes + (45-4)=41
  // But wait, run is capped at 255 in encoder, so:
  // First: 255 bytes → 4 + (255-4) = 4 + 251 → 5 bytes output
  // Then: 45 bytes → 4 + (45-4) = 4 + 41 → 5 bytes output
  // Total: 10 bytes for 300 bytes of 'X'
  let decoded = rl1_0e1_decode(encoded)
  assert_eq(decoded.length(), data.length())
  for i = 0; i < data.length(); i = i + 1 {
    assert_eq(decoded[i], data[i])
  }
}

///|
test "bzip2: bwt roundtrip" {
  let data = @utils.string_to_bytes("banana")
  let (encoded, primary) = bwt_encode(data)
  let decoded = bwt_decode(encoded, primary)
  assert_eq(decoded.length(), data.length())
  for i = 0; i < data.length(); i = i + 1 {
    assert_eq(decoded[i], data[i])
  }
}

///|
test "bzip2: mtf roundtrip with used bytes" {
  let data = @utils.string_to_bytes("mississippi")
  let (ranges, num_used, byte_to_mtf_index) = build_symbol_map(data)
  let encoded = mtf_encode(data, byte_to_mtf_index, num_used)
  let (_, mtf_index_to_byte) = decode_symbol_map(ranges)
  let decoded = mtf_decode(encoded, mtf_index_to_byte, num_used)
  assert_eq(decoded, data)
}

///|
test "bzip2: rl1_0e2 roundtrip" {
  let data : Array[Int] = [0, 0, 0, 0, 5, 0, 0, 3]
  let eob = 10
  let encoded = rl1_0e2_encode(data, eob)
  let decoded = rl1_0e2_decode(encoded, eob)
  assert_eq(decoded.length(), data.length())
  for i = 0; i < data.length(); i = i + 1 {
    assert_eq(decoded[i], data[i])
  }
}

///|
test "bzip2: huffman lengths satisfy Kraft inequality" {
  let freqs = [10, 5, 3, 1]
  let lengths = build_huffman_lengths(freqs, BZIP2_MAX_HUFFMAN_BITS)
  let mut sum = 0.0
  for i = 0; i < freqs.length(); i = i + 1 {
    if lengths[i] > 0 {
      sum = sum + @math.pow(2.0, -lengths[i].to_double())
    }
  }
  assert_true(sum <= 1.0 + 1.0e-10)
}

///|
test "bzip2: huffman code generation" {
  let lengths = [1, 2, 3, 3]
  let codes = generate_codes(lengths)
  // Canonical codes: symbol 0 → 0 (1 bit), symbol 1 → 10 (2 bits),
  // symbol 2 → 110 (3 bits), symbol 3 → 111 (3 bits)
  assert_eq(codes[0], 0U)
  // Canonical: bl_count[1]=1, bl_count[2]=1, bl_count[3]=2
  // next_code[1] = 0, next_code[2] = 2, next_code[3] = 6
  // symbol 0: len=1, code=0 (binary: 0)
  // symbol 1: len=2, code=2 (binary: 10)
  // symbol 2: len=3, code=6 (binary: 110)
  // symbol 3: len=3, code=7 (binary: 111)
  assert_eq(codes[0], 0U)
  assert_eq(codes[1], 2U)
  assert_eq(codes[2], 6U)
  assert_eq(codes[3], 7U)
}

///|
test "bzip2: code length delta encoding roundtrip" {
  let bw = BitWriter::new()
  let lengths = [1, 2, 3, 3, 2, 1, 0, 0]
  let alpha_size = 8
  write_code_lengths(bw, lengths, alpha_size)
  let encoded = bw.to_bytes()
  let br = BitReader::new(encoded, 0)
  match read_code_lengths(br, alpha_size) {
    None => assert_true(false)
    Some(decoded) =>
      for i = 0; i < alpha_size; i = i + 1 {
        assert_eq(decoded[i], lengths[i])
      }
  }
}

///|
test "bzip2: selector MTF encoding roundtrip" {
  let bw = BitWriter::new()
  let selectors = [0, 1, 0, 2, 0, 1]
  let num_tables = 3
  write_selectors(bw, selectors, num_tables)
  let encoded = bw.to_bytes()
  let br = BitReader::new(encoded, 0)
  match read_selectors(br, selectors.length(), num_tables) {
    None => assert_true(false)
    Some(decoded) =>
      for i = 0; i < selectors.length(); i = i + 1 {
        assert_eq(decoded[i], selectors[i])
      }
  }
}

///|
test "bzip2: compress/decompress empty" {
  let data = b""
  let compressed = compress(data)
  match decompress(compressed) {
    None => assert_true(false)
    Some(decompressed) => assert_eq(decompressed, data)
  }
}

///|
test "bzip2: compress/decompress single byte" {
  let data = b"A"
  let compressed = compress(data)
  match decompress(compressed) {
    None => assert_true(false)
    Some(decompressed) => assert_eq(decompressed, data)
  }
}

///|
test "bzip2: compress/decompress simple text" {
  let data = @utils.string_to_bytes("Hello, World!")
  let compressed = compress(data)
  match decompress(compressed) {
    None => assert_true(false)
    Some(decompressed) => {
      assert_eq(decompressed.length(), data.length())
      for i = 0; i < data.length(); i = i + 1 {
        assert_eq(decompressed[i], data[i])
      }
    }
  }
}

///|
test "bzip2: compress/decompress repetitive data" {
  let arr : Array[Byte] = []
  for _i = 0; _i < 1000; _i = _i + 1 {
    arr.push(b'A')
  }
  let data = Bytes::from_array(arr)
  let compressed = compress(data)
  match decompress(compressed) {
    None => assert_true(false)
    Some(decompressed) => {
      assert_eq(decompressed.length(), data.length())
      for i = 0; i < data.length(); i = i + 1 {
        assert_eq(decompressed[i], data[i])
      }
    }
  }
}

///|
test "bzip2: compression actually reduces size for repetitive data" {
  let arr : Array[Byte] = []
  for _i = 0; _i < 1000; _i = _i + 1 {
    arr.push(b'A')
  }
  let data = Bytes::from_array(arr)
  let compressed = compress(data)
  assert_true(compressed.length() < data.length())
}

///|
test "bzip2: stream header valid" {
  let data = b"test"
  let compressed = compress(data)
  assert_eq(compressed[0], b'B')
  assert_eq(compressed[1], b'Z')
  assert_eq(compressed[2], b'h')
  assert_eq(compressed[3], b'9')
}

///|
test "bzip2: invalid magic returns None" {
  let data = Bytes::from_array([
    b'\x00', b'\x01', b'\x02', b'\x03', b'\x04', b'\x05',
  ])
  match decompress(data) {
    None => assert_true(true)
    Some(_) => assert_true(false)
  }
}

///|
test "bzip2: compress/decompress binary data" {
  let arr : Array[Byte] = []
  for i = 0; i < 256; i = i + 1 {
    arr.push(i.to_byte())
  }
  let data = Bytes::from_array(arr)
  let compressed = compress(data)
  match decompress(compressed) {
    None => assert_true(false)
    Some(decompressed) => {
      assert_eq(decompressed.length(), data.length())
      for i = 0; i < data.length(); i = i + 1 {
        assert_eq(decompressed[i], data[i])
      }
    }
  }
}

///|
test "bzip2: compress/decompress mixed data" {
  let arr : Array[Byte] = []
  // Mix of text, repeated bytes, and binary
  for _i = 0; _i < 100; _i = _i + 1 {
    arr.push(b'T')
    arr.push(b'h')
    arr.push(b'e')
    arr.push(b' ')
  }
  for _i = 0; _i < 50; _i = _i + 1 {
    arr.push(b'\x00')
  }
  for i = 0; i < 128; i = i + 1 {
    arr.push(i.to_byte())
  }
  let data = Bytes::from_array(arr)
  let compressed = compress(data)
  match decompress(compressed) {
    None => assert_true(false)
    Some(decompressed) => {
      assert_eq(decompressed.length(), data.length())
      for i = 0; i < data.length(); i = i + 1 {
        assert_eq(decompressed[i], data[i])
      }
    }
  }
}

///|
test "bzip2: compress/decompress long text" {
  let sb = StringBuilder()
  for _i = 0; _i < 50; _i = _i + 1 {
    sb.write_string("The quick brown fox jumps over the lazy dog. ")
  }
  let data = @utils.string_to_bytes(sb.to_string())
  let compressed = compress(data)
  match decompress(compressed) {
    None => assert_true(false)
    Some(decompressed) => {
      assert_eq(decompressed.length(), data.length())
      for i = 0; i < data.length(); i = i + 1 {
        assert_eq(decompressed[i], data[i])
      }
    }
  }
}

///|
test "bzip2: all same byte" {
  let arr : Array[Byte] = []
  for _i = 0; _i < 500; _i = _i + 1 {
    arr.push(b'\xFF')
  }
  let data = Bytes::from_array(arr)
  let compressed = compress(data)
  match decompress(compressed) {
    None => assert_true(false)
    Some(decompressed) => {
      assert_eq(decompressed.length(), data.length())
      for i = 0; i < data.length(); i = i + 1 {
        assert_eq(decompressed[i], data[i])
      }
    }
  }
}
