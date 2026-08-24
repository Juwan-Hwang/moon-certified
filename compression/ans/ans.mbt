///|
/// ANS — Asymmetric Numeral Systems entropy coding.
///
/// ANS is a modern entropy coding technique that achieves compression ratios
/// close to the Shannon entropy limit, similar to arithmetic coding, but with
/// coding speeds approaching Huffman coding. It was invented by Jarek Duda
/// (2014) and is used in production compressors such as Facebook's zstd
/// (via FSE), Apple's LZFSE, and CRAM (genomics).
///
/// This module implements two variants:
///
/// - **rANS (range ANS)**: Uses a single 32-bit integer state and arithmetic
///   operations. Byte-wise renormalisation keeps the state within register.
///   rANS is simpler and slightly more compact; it is the preferred variant
///   for software decoders.
///
/// - **tANS (table ANS / FSE)**: Uses precomputed state-transition tables
///   for O(1) encode/decode with no division. This is the variant used in
///   zstd's FSE (Finite State Entropy).
///
/// ## Wire Format
///
/// Both variants share the same framing:
/// ```text
/// [4B] magic 0x414E5300 ("ANS\0")
/// [1B] variant (0=rANS, 1=tANS)
/// [4B] original_length (LE uint32)
/// [2B] scale_bits (LE uint16)
/// [1B] alphabet_size
/// [alphabet_size × 3B] symbol byte + normalised freq (LE uint16)
/// [4B] final_state (rANS) or initial_state (tANS)
/// [4B] payload_size
/// [payload_size] compressed data
/// ```
///
/// ## References
///
/// - Duda, J. (2014): "Asymmetric Numeral Systems: Entropy Coding Combining
///   Speed of Huffman Coding with Compression Rate of Arithmetic Coding."
/// - ryg_rans: https://github.com/rygorous/ryg_rans
/// - FSE: https://github.com/Cyan4973/FiniteStateEntropy
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

let ans_magic : UInt = 0x414E5300U

///|
let variant_rans : Byte = b'\x00'

///|
let variant_tans : Byte = b'\x01'

///|
let rans_l : UInt = 0x800000U // 1 << 23

///|
let default_scale_bits : Int = 14

///|
let max_alphabet : Int = 256

// ---------------------------------------------------------------------------
// Frequency table
// ---------------------------------------------------------------------------

///|
/// Normalised frequency table for ANS coding.
pub struct FreqTable {
  freqs : Array[Int]
  cum : Array[Int]
  total : Int
  scale_bits : Int
  alphabet : Array[Int]
}

///|
/// Build a normalised frequency table from raw data.
///
/// Counts symbol occurrences, then normalises to a power-of-2 total
/// (`M = 2^scale_bits`) using the FSE-style normalisation algorithm.
pub fn build_freq_table(data : Array[Byte], scale_bits : Int) -> FreqTable {
  let sb = if scale_bits < 4 {
    default_scale_bits
  } else if scale_bits > 20 {
    20
  } else {
    scale_bits
  }
  let m = 1 << sb
  let counts = Array::make(max_alphabet, 0)
  let mut total = 0
  for i = 0; i < data.length(); i = i + 1 {
    let s = data[i].to_int()
    counts[s] = counts[s] + 1
    total = total + 1
  }
  let alphabet : Array[Int] = []
  for i = 0; i < max_alphabet; i = i + 1 {
    if counts[i] > 0 {
      alphabet.push(i)
    }
  }
  if alphabet.is_empty() {
    let freqs = Array::make(max_alphabet, 0)
    freqs[0] = m
    let cum = Array::make(max_alphabet, 0)
    return { freqs, cum, total: m, scale_bits: sb, alphabet: [0] }
  }
  if alphabet.length() == 1 {
    let freqs = Array::make(max_alphabet, 0)
    freqs[alphabet[0]] = m
    let cum = Array::make(max_alphabet, 0)
    return { freqs, cum, total: m, scale_bits: sb, alphabet }
  }
  let norm = Array::make(max_alphabet, 0)
  let mut remaining = m
  let errors : Array[(Int, Double)] = []
  for i = 0; i < alphabet.length(); i = i + 1 {
    let s = alphabet[i]
    let v = (counts[s] * m + total / 2) / total
    let v = if v == 0 { 1 } else { v }
    norm[s] = v
    remaining = remaining - v
    let desired = counts[s].to_double() * m.to_double() / total.to_double()
    errors.push((s, desired - v.to_double()))
  }
  // Sort errors descending by error magnitude.
  for i = 1; i < errors.length(); i = i + 1 {
    let (sv, ev) = errors[i]
    let mut k = i - 1
    while k >= 0 {
      let (_, ek) = errors[k]
      if ek < ev {
        errors[k + 1] = errors[k]
        k = k - 1
      } else {
        break
      }
    }
    errors[k + 1] = (sv, ev)
  }
  // Distribute remaining slots.
  let mut idx = 0
  while remaining > 0 && idx < errors.length() {
    let s = errors[idx].0
    norm[s] = norm[s] + 1
    remaining = remaining - 1
    idx = idx + 1
    if idx >= errors.length() {
      idx = 0
    }
  }
  idx = errors.length() - 1
  while remaining < 0 && idx >= 0 {
    let s = errors[idx].0
    if norm[s] > 1 {
      norm[s] = norm[s] - 1
      remaining = remaining + 1
    }
    idx = idx - 1
  }
  let cum = Array::make(max_alphabet, 0)
  let mut acc = 0
  for i = 0; i < max_alphabet; i = i + 1 {
    cum[i] = acc
    acc = acc + norm[i]
  }
  { freqs: norm, cum, total: m, scale_bits: sb, alphabet }
}

// ---------------------------------------------------------------------------
// Bit I/O (LSB-first)
// ---------------------------------------------------------------------------

///|
priv struct BitWriter {
  bytes : Array[Byte]
  mut bit_buf : UInt
  mut bit_count : Int
}

///|
fn bw_new() -> BitWriter {
  { bytes: [], bit_buf: 0U, bit_count: 0 }
}

///|
fn bw_write_bits(w : BitWriter, value : UInt, nbits : Int) -> Unit {
  w.bit_buf = w.bit_buf | (value << w.bit_count)
  w.bit_count = w.bit_count + nbits
  while w.bit_count >= 8 {
    w.bytes.push((w.bit_buf & 0xFFU).to_byte())
    w.bit_buf = w.bit_buf >> 8
    w.bit_count = w.bit_count - 8
  }
}

///|
fn bw_flush(w : BitWriter) -> Unit {
  if w.bit_count > 0 {
    w.bytes.push((w.bit_buf & 0xFFU).to_byte())
    w.bit_buf = 0U
    w.bit_count = 0
  }
}

///|
priv struct BitReader {
  bytes : Array[Byte]
  mut pos : Int
  mut bit_buf : UInt
  mut bit_count : Int
}

///|
fn br_new(bytes : Array[Byte]) -> BitReader {
  { bytes, pos: 0, bit_buf: 0U, bit_count: 0 }
}

///|
fn br_read_bits(r : BitReader, nbits : Int) -> UInt {
  while r.bit_count < nbits {
    if r.pos < r.bytes.length() {
      r.bit_buf = r.bit_buf | (r.bytes[r.pos].to_uint() << r.bit_count)
      r.pos = r.pos + 1
    }
    r.bit_count = r.bit_count + 8
  }
  let result = r.bit_buf & ((1U << nbits) - 1U)
  r.bit_buf = r.bit_buf >> nbits
  r.bit_count = r.bit_count - nbits
  result
}

// ---------------------------------------------------------------------------
// Byte-stream helpers
// ---------------------------------------------------------------------------

///|
fn write_u32_le(buf : Array[Byte], val : UInt) -> Unit {
  buf.push((val & 0xFFU).to_byte())
  buf.push(((val >> 8) & 0xFFU).to_byte())
  buf.push(((val >> 16) & 0xFFU).to_byte())
  buf.push(((val >> 24) & 0xFFU).to_byte())
}

///|
fn read_u32_le(buf : Array[Byte], pos : Int) -> UInt {
  buf[pos].to_uint() |
  (buf[pos + 1].to_uint() << 8) |
  (buf[pos + 2].to_uint() << 16) |
  (buf[pos + 3].to_uint() << 24)
}

///|
fn write_u16_le(buf : Array[Byte], val : Int) -> Unit {
  buf.push((val & 0xFF).to_byte())
  buf.push(((val >> 8) & 0xFF).to_byte())
}

///|
fn read_u16_le(buf : Array[Byte], pos : Int) -> Int {
  buf[pos].to_int() | (buf[pos + 1].to_int() << 8)
}

// ---------------------------------------------------------------------------
// rANS encoder
// ---------------------------------------------------------------------------

///|
/// Compress data using rANS (range ANS) entropy coding.
///
/// The encoder processes symbols in reverse order with a 32-bit state and
/// byte-wise renormalisation.  Renormalisation bytes are written forward;
/// the decoder reads them backward (LIFO).
pub fn rans_compress(data : Array[Byte]) -> Array[Byte] {
  let n = data.length()
  if n == 0 {
    return []
  }
  let ft = build_freq_table(data, default_scale_bits)
  let sb = ft.scale_bits
  let m = ft.total.reinterpret_as_uint()
  let mut x = rans_l
  let renorm_buf : Array[Byte] = []
  let mut i = n - 1
  while i >= 0 {
    let s = data[i].to_int()
    let freq = ft.freqs[s].reinterpret_as_uint()
    let c = ft.cum[s].reinterpret_as_uint()
    // Renormalise: emit bytes until x < x_max
    let x_max = (rans_l >> sb << 8) * freq
    while x >= x_max {
      renorm_buf.push((x & 0xFFU).to_byte())
      x = x >> 8
    }
    // Encode: x = (x / freq) * M + cum + (x % freq)
    x = x / freq * m + c + x % freq
    i = i - 1
  }
  let output : Array[Byte] = []
  write_u32_le(output, ans_magic)
  output.push(variant_rans)
  write_u32_le(output, n.reinterpret_as_uint())
  write_u16_le(output, sb)
  // Store alphabet_size - 1 as a byte (0-255 maps to 1-256 symbols)
  output.push((ft.alphabet.length() - 1).to_byte())
  for i = 0; i < ft.alphabet.length(); i = i + 1 {
    let s = ft.alphabet[i]
    output.push(s.to_byte())
    write_u16_le(output, ft.freqs[s])
  }
  write_u32_le(output, x)
  write_u32_le(output, renorm_buf.length().reinterpret_as_uint())
  for i = 0; i < renorm_buf.length(); i = i + 1 {
    output.push(renorm_buf[i])
  }
  output
}

// ---------------------------------------------------------------------------
// rANS decoder
// ---------------------------------------------------------------------------

///|
/// Decompress data produced by `rans_compress`.
///
/// The decoder reads renormalisation bytes backward (LIFO order) to
/// correctly reverse the encoder's forward byte emission.
pub fn rans_decompress(data : Array[Byte]) -> Array[Byte] {
  if data.length() < 18 {
    return []
  }
  let mut pos = 0
  let magic = read_u32_le(data, pos)
  pos = pos + 4
  if magic != ans_magic {
    return []
  }
  let variant = data[pos]
  pos = pos + 1
  if variant != variant_rans {
    return []
  }
  let orig_len = read_u32_le(data, pos).reinterpret_as_int()
  pos = pos + 4
  let sb = read_u16_le(data, pos)
  pos = pos + 2
  let alpha_size = data[pos].to_int() + 1 // stored as siz1.0e-1 (0-255 → 1-256)
  pos = pos + 1
  if alpha_size == 0 || alpha_size > max_alphabet {
    return []
  }
  let freqs = Array::make(max_alphabet, 0)
  let alphabet : Array[Int] = []
  for i = 0; i < alpha_size; i = i + 1 {
    let s = data[pos].to_int()
    pos = pos + 1
    let f = read_u16_le(data, pos)
    pos = pos + 2
    freqs[s] = f
    alphabet.push(s)
  }
  let m = 1 << sb
  let cum = Array::make(max_alphabet, 0)
  let mut acc = 0
  for i = 0; i < max_alphabet; i = i + 1 {
    cum[i] = acc
    acc = acc + freqs[i]
  }
  let mut x = read_u32_le(data, pos)
  pos = pos + 4
  let renorm_size = read_u32_le(data, pos).reinterpret_as_int()
  pos = pos + 4
  let renorm_buf : Array[Byte] = []
  for i = 0; i < renorm_size; i = i + 1 {
    renorm_buf.push(data[pos])
    pos = pos + 1
  }
  let mu = m.reinterpret_as_uint()
  let mask = mu - 1U
  let output : Array[Byte] = []
  // Read renormalisation bytes backward (LIFO) — the encoder writes forward,
  // so the decoder must consume from the end.
  let mut renorm_pos = renorm_buf.length()
  for _i = 0; _i < orig_len; _i = _i + 1 {
    let slot = x & mask
    let s = binary_search_symbol(
      slot.reinterpret_as_int(),
      cum,
      freqs,
      alphabet,
    )
    let freq = freqs[s].reinterpret_as_uint()
    let c = cum[s].reinterpret_as_uint()
    // Decode: x = freq * (x >> sb) + (x & mask) - cum
    x = freq * (x >> sb) + (x & mask) - c
    // Renormalise: read bytes backward until x >= rans_l
    while x < rans_l && renorm_pos > 0 {
      renorm_pos = renorm_pos - 1
      x = (x << 8) | renorm_buf[renorm_pos].to_uint()
    }
    output.push(s.to_byte())
  }
  output
}

///|
/// Binary search for the symbol whose cumulative range contains `slot`.
fn binary_search_symbol(
  slot : Int,
  cum : Array[Int],
  freqs : Array[Int],
  alphabet : Array[Int],
) -> Int {
  let mut lo = 0
  let mut hi = alphabet.length() - 1
  while lo < hi {
    let mid = (lo + hi) / 2
    let s = alphabet[mid]
    if cum[s] + freqs[s] <= slot {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  alphabet[lo]
}

// ---------------------------------------------------------------------------
// tANS (table ANS / FSE)
// ---------------------------------------------------------------------------

///|
/// Decoding table entry: for each state x' in [1, L], stores the symbol,
/// number of bits to read, and the base for reconstructing the previous state.
priv struct TansDecodeEntry {
  symbol : Int
  num_bits : Int
  base : Int // previous_state = base + bits_read
}

///|
/// Encoding table entry: for each (symbol, state) pair, stores the number
/// of bits to emit, the bit value, and the next state.
priv struct TansEncodeEntry {
  num_bits : Int
  bits_val : Int
  next_state : Int
}

///|
priv struct TansTable {
  table_size : Int
  decode_table : Array[TansDecodeEntry] // 1-indexed: decode_table[state]
  encode_table : Array[Array[TansEncodeEntry]] // encode_table[symbol][stat1.0e-1]
}

///|
/// Build the tANS state table from a frequency table.
///
/// Uses the FSE spread function (`step = (L>>1) + (L>>3) + 3`, which is
/// always odd and therefore coprime to L = 2^tableLog) to assign symbols
/// to states, then constructs decode and encode tables.
///
/// ## Decode table
///
/// For each state x' in [1, L], the symbol s = symbol_of[x'] and its
/// position `pos` within symbol s's state set (0-indexed, in [0, f-1])
/// determine:
/// - `k = bit_length((L - pos - 1) / f)` — bits to read
/// - `base = pos + 1` — previous state when q=0
/// - Decode: `x = base + read_bits(k) * f`
///
/// ## Encode table
///
/// For symbol s and state x in [1, L]:
/// - `q = (x - 1) / f`, `r = (x - 1) % f`
/// - `k = bit_length((L - r - 1) / f)` — same k as decode for this r
/// - `bits_val = q`, `next_state` = the (r+1)-th state of symbol s
///
/// The encode and decode k values match because both use the same r
/// (position within the symbol's state set), and q < 2^k is guaranteed
/// since q ≤ (L−r−1)/f.
fn build_tans_table(ft : FreqTable) -> TansTable {
  let _tb = ft.scale_bits
  let ts = ft.total // L = 2^tb
  let alphabet = ft.alphabet
  let freqs = ft.freqs

  // --- Spread: assign symbols to states [1..ts] using FSE-style distribution ---
  // FSE_TABLESTEP = (L>>1) + (L>>3) + 3 — always odd, hence coprime to L (power of 2).
  let symbol_of = Array::make(ts + 1, -1)
  let step = (ts >> 1) + (ts >> 3) + 3
  let mut p = 0
  for ai = 0; ai < alphabet.length(); ai = ai + 1 {
    let s = alphabet[ai]
    for _j = 0; _j < freqs[s]; _j = _j + 1 {
      while symbol_of[p + 1] != -1 {
        p = (p + step) % ts
      }
      symbol_of[p + 1] = s
      p = (p + step) % ts
    }
  }
  // Fill any remaining (shouldn't happen if freqs sum to ts, but be safe)
  for i = 1; i <= ts; i = i + 1 {
    if symbol_of[i] == -1 {
      symbol_of[i] = alphabet[0]
    }
  }

  // --- Build position lookup: for each state x', its 0-indexed position
  //     within its symbol's state set ---
  let sym_pos = Array::make(ts + 1, 0)
  let pos_ctr = Array::make(max_alphabet, 0)
  for x_prime = 1; x_prime <= ts; x_prime = x_prime + 1 {
    let s = symbol_of[x_prime]
    sym_pos[x_prime] = pos_ctr[s]
    pos_ctr[s] = pos_ctr[s] + 1
  }

  // --- Build reverse lookup: for each symbol s, the list of states ---
  let sym_states : Array[Array[Int]] = Array::make(max_alphabet, [])
  for x_prime = 1; x_prime <= ts; x_prime = x_prime + 1 {
    sym_states[symbol_of[x_prime]].push(x_prime)
  }

  // --- Build decode table ---
  let decode_table : Array[TansDecodeEntry] = Array::make(ts + 1, {
    symbol: 0,
    num_bits: 0,
    base: 0,
  })
  for x_prime = 1; x_prime <= ts; x_prime = x_prime + 1 {
    let s = symbol_of[x_prime]
    let f = freqs[s]
    let r = sym_pos[x_prime] // 0-indexed position within symbol's states, in [0, f-1]
    let q_max = (ts - r - 1) / f
    let k = bit_length(q_max)
    let base = r + 1
    decode_table[x_prime] = { symbol: s, num_bits: k, base }
  }

  // --- Build encode table from decode table ---
  // For each decode entry (x', s, k, base):
  //   For each possible bits value q in [0, 2^k):
  //     x = base + q * f  (previous state)
  //     If x is in [1, ts], set encode_table[s][x] = (k, q, x')
  let encode_table : Array[Array[TansEncodeEntry]] = Array::make(
    max_alphabet,
    Array::make(0, { num_bits: 0, bits_val: 0, next_state: 0 }),
  )
  for s = 0; s < max_alphabet; s = s + 1 {
    if freqs[s] > 0 {
      encode_table[s] = Array::make(ts + 1, {
        num_bits: 0,
        bits_val: 0,
        next_state: 0,
      })
    }
  }
  for x_prime = 1; x_prime <= ts; x_prime = x_prime + 1 {
    let entry = decode_table[x_prime]
    let s = entry.symbol
    let k = entry.num_bits
    let base = entry.base
    let f = freqs[s]
    let pow_k = 1 << k
    for q = 0; q < pow_k; q = q + 1 {
      let x = base + q * f
      if x >= 1 && x <= ts {
        if encode_table[s][x].next_state == 0 {
          encode_table[s][x] = { num_bits: k, bits_val: q, next_state: x_prime }
        }
      }
    }
  }
  // Fill any gaps using the direct formula
  for s = 0; s < max_alphabet; s = s + 1 {
    if freqs[s] > 0 {
      let f = freqs[s]
      for x = 1; x <= ts; x = x + 1 {
        if encode_table[s][x].next_state == 0 {
          let q = (x - 1) / f
          let r = (x - 1) % f
          let q_max = (ts - r - 1) / f
          let k = bit_length(q_max)
          // x' is the (r+1)-th state assigned to symbol s
          let x_prime = sym_states[s][r]
          encode_table[s][x] = { num_bits: k, bits_val: q, next_state: x_prime }
        }
      }
    }
  }
  { table_size: ts, decode_table, encode_table }
}

///|
/// Compute floor(log2(n)) + 1 for n > 0, 0 for n = 0.
fn bit_length(n : Int) -> Int {
  if n <= 0 {
    return 0
  }
  let mut bits = 0
  let mut v = n
  while v > 0 {
    bits = bits + 1
    v = v >> 1
  }
  bits
}

///|
/// Compress data using tANS (table ANS / FSE) entropy coding.
///
/// The encoder processes symbols in reverse order (last symbol first),
/// collecting bit operations.  Bits are then written to the bitstream in
/// reverse order so that the decoder — which reads forward — encounters
/// the first symbol's bits first.  This is the standard FSE approach:
/// the encoder's reverse symbol processing combined with reversed bit
/// emission yields a forward-readable bitstream.
pub fn tans_compress(data : Array[Byte]) -> Array[Byte] {
  let n = data.length()
  if n == 0 {
    return []
  }
  let ft = build_freq_table(data, default_scale_bits)
  let table = build_tans_table(ft)
  let ts = table.table_size
  let mut state = ts // initial state = L (max state)
  // Collect bit operations in encode order (reverse symbol order).
  let bit_ops : Array[(Int, UInt)] = []
  let mut i = n - 1
  while i >= 0 {
    let s = data[i].to_int()
    let entry = table.encode_table[s][state]
    bit_ops.push((entry.num_bits, entry.bits_val.reinterpret_as_uint()))
    state = entry.next_state
    i = i - 1
  }
  // Write bits in reverse order so the decoder can read forward.
  let bw = bw_new()
  for j = bit_ops.length() - 1; j >= 0; j = j - 1 {
    let (nbits, val) = bit_ops[j]
    if nbits > 0 {
      bw_write_bits(bw, val, nbits)
    }
  }
  bw_flush(bw)
  let output : Array[Byte] = []
  write_u32_le(output, ans_magic)
  output.push(variant_tans)
  write_u32_le(output, n.reinterpret_as_uint())
  write_u16_le(output, ft.scale_bits)
  // Store alphabet_size - 1 as a byte (0-255 maps to 1-256 symbols)
  output.push((ft.alphabet.length() - 1).to_byte())
  for i = 0; i < ft.alphabet.length(); i = i + 1 {
    let s = ft.alphabet[i]
    output.push(s.to_byte())
    write_u16_le(output, ft.freqs[s])
  }
  write_u32_le(output, state.reinterpret_as_uint())
  write_u32_le(output, bw.bytes.length().reinterpret_as_uint())
  for i = 0; i < bw.bytes.length(); i = i + 1 {
    output.push(bw.bytes[i])
  }
  output
}

///|
/// Decompress data produced by `tans_compress`.
pub fn tans_decompress(data : Array[Byte]) -> Array[Byte] {
  if data.length() < 18 {
    return []
  }
  let mut pos = 0
  let magic = read_u32_le(data, pos)
  pos = pos + 4
  if magic != ans_magic {
    return []
  }
  let variant = data[pos]
  pos = pos + 1
  if variant != variant_tans {
    return []
  }
  let orig_len = read_u32_le(data, pos).reinterpret_as_int()
  pos = pos + 4
  let sb = read_u16_le(data, pos)
  pos = pos + 2
  let alpha_size = data[pos].to_int() + 1 // stored as siz1.0e-1 (0-255 → 1-256)
  pos = pos + 1
  if alpha_size == 0 || alpha_size > max_alphabet {
    return []
  }
  let freqs = Array::make(max_alphabet, 0)
  let alphabet : Array[Int] = []
  for i = 0; i < alpha_size; i = i + 1 {
    let s = data[pos].to_int()
    pos = pos + 1
    let f = read_u16_le(data, pos)
    pos = pos + 2
    freqs[s] = f
    alphabet.push(s)
  }
  let m = 1 << sb
  let cum = Array::make(max_alphabet, 0)
  let mut acc = 0
  for i = 0; i < max_alphabet; i = i + 1 {
    cum[i] = acc
    acc = acc + freqs[i]
  }
  let ft : FreqTable = { freqs, cum, total: m, scale_bits: sb, alphabet }
  let table = build_tans_table(ft)
  let mut state = read_u32_le(data, pos).reinterpret_as_int()
  pos = pos + 4
  let comp_size = read_u32_le(data, pos).reinterpret_as_int()
  pos = pos + 4
  let comp_data : Array[Byte] = []
  for i = 0; i < comp_size; i = i + 1 {
    comp_data.push(data[pos])
    pos = pos + 1
  }
  let br = br_new(comp_data)
  let output : Array[Byte] = []
  for _i = 0; _i < orig_len; _i = _i + 1 {
    if state < 1 || state > table.table_size {
      return output // safety: invalid state
    }
    let entry = table.decode_table[state]
    let s = entry.symbol
    let k = entry.num_bits
    let q = if k > 0 { br_read_bits(br, k).reinterpret_as_int() } else { 0 }
    state = entry.base + q * freqs[s]
    output.push(s.to_byte())
  }
  output
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "rans: empty input" {
  let result = rans_compress([])
  assert_true(result.length() == 0)
  let decompressed = rans_decompress(result)
  assert_true(decompressed.length() == 0)
}

///|
test "rans: single byte" {
  let data = [b'\x41']
  let compressed = rans_compress(data)
  let decompressed = rans_decompress(compressed)
  assert_true(decompressed.length() == 1)
  assert_true(decompressed[0] == b'\x41')
}

///|
test "rans: two bytes" {
  let data : Array[Byte] = [b'\x00', b'\x01']
  let compressed = rans_compress(data)
  let decompressed = rans_decompress(compressed)
  assert_true(decompressed.length() == data.length())
  for i = 0; i < data.length(); i = i + 1 {
    assert_true(decompressed[i] == data[i])
  }
}

///|
test "rans: uniform data" {
  let data : Array[Byte] = []
  for i = 0; i < 100; i = i + 1 {
    data.push((i % 4).to_byte())
  }
  let compressed = rans_compress(data)
  let decompressed = rans_decompress(compressed)
  assert_true(decompressed.length() == data.length())
  for i = 0; i < data.length(); i = i + 1 {
    assert_true(decompressed[i] == data[i])
  }
}

///|
test "rans: text data" {
  let text = "The quick brown fox jumps over the lazy dog"
  let data : Array[Byte] = []
  for i = 0; i < text.length(); i = i + 1 {
    data.push(text[i].to_byte())
  }
  let compressed = rans_compress(data)
  let decompressed = rans_decompress(compressed)
  assert_true(decompressed.length() == data.length())
  for i = 0; i < data.length(); i = i + 1 {
    assert_true(decompressed[i] == data[i])
  }
}

///|
test "rans: highly skewed distribution" {
  let data : Array[Byte] = []
  for i = 0; i < 200; i = i + 1 {
    if i % 10 < 9 {
      data.push(b'A')
    } else {
      data.push(b'B')
    }
  }
  let compressed = rans_compress(data)
  let decompressed = rans_decompress(compressed)
  assert_true(decompressed.length() == data.length())
  for i = 0; i < data.length(); i = i + 1 {
    assert_true(decompressed[i] == data[i])
  }
}

///|
test "rans: all same byte" {
  let data : Array[Byte] = []
  for i = 0; i < 50; i = i + 1 {
    data.push(b'\xFF')
  }
  let compressed = rans_compress(data)
  let decompressed = rans_decompress(compressed)
  assert_true(decompressed.length() == data.length())
  for i = 0; i < data.length(); i = i + 1 {
    assert_true(decompressed[i] == data[i])
  }
}

///|
test "rans: binary data all byte values" {
  let data : Array[Byte] = []
  for i = 0; i < 256; i = i + 1 {
    data.push(i.to_byte())
  }
  let compressed = rans_compress(data)
  let decompressed = rans_decompress(compressed)
  assert_true(decompressed.length() == data.length())
  for i = 0; i < data.length(); i = i + 1 {
    assert_true(decompressed[i] == data[i])
  }
}

///|
test "rans: large random-ish data" {
  let data : Array[Byte] = []
  let mut seed = 12345U
  for i = 0; i < 500; i = i + 1 {
    seed = seed * 1103515245U + 12345U
    data.push((seed >> 16).to_byte())
  }
  let compressed = rans_compress(data)
  let decompressed = rans_decompress(compressed)
  assert_true(decompressed.length() == data.length())
  for i = 0; i < data.length(); i = i + 1 {
    assert_true(decompressed[i] == data[i])
  }
}

///|
test "tans: empty input" {
  let result = tans_compress([])
  assert_true(result.length() == 0)
  let decompressed = tans_decompress(result)
  assert_true(decompressed.length() == 0)
}

///|
test "tans: single byte" {
  let data = [b'\x42']
  let compressed = tans_compress(data)
  let decompressed = tans_decompress(compressed)
  assert_true(decompressed.length() == 1)
  assert_true(decompressed[0] == b'\x42')
}

///|
test "tans: uniform data" {
  let data : Array[Byte] = []
  for i = 0; i < 100; i = i + 1 {
    data.push((i % 4).to_byte())
  }
  let compressed = tans_compress(data)
  let decompressed = tans_decompress(compressed)
  assert_true(decompressed.length() == data.length())
  for i = 0; i < data.length(); i = i + 1 {
    assert_true(decompressed[i] == data[i])
  }
}

///|
test "tans: text data" {
  let text = "Hello World! This is a test of tANS compression."
  let data : Array[Byte] = []
  for i = 0; i < text.length(); i = i + 1 {
    data.push(text[i].to_byte())
  }
  let compressed = tans_compress(data)
  let decompressed = tans_decompress(compressed)
  assert_true(decompressed.length() == data.length())
  for i = 0; i < data.length(); i = i + 1 {
    assert_true(decompressed[i] == data[i])
  }
}

///|
test "tans: highly skewed distribution" {
  let data : Array[Byte] = []
  for i = 0; i < 200; i = i + 1 {
    if i % 10 < 9 {
      data.push(b'A')
    } else {
      data.push(b'B')
    }
  }
  let compressed = tans_compress(data)
  let decompressed = tans_decompress(compressed)
  assert_true(decompressed.length() == data.length())
  for i = 0; i < data.length(); i = i + 1 {
    assert_true(decompressed[i] == data[i])
  }
}

///|
test "tans: all same byte" {
  let data : Array[Byte] = []
  for i = 0; i < 50; i = i + 1 {
    data.push(b'\xAA')
  }
  let compressed = tans_compress(data)
  let decompressed = tans_decompress(compressed)
  assert_true(decompressed.length() == data.length())
  for i = 0; i < data.length(); i = i + 1 {
    assert_true(decompressed[i] == data[i])
  }
}

///|
test "tans: binary data all byte values" {
  let data : Array[Byte] = []
  for i = 0; i < 256; i = i + 1 {
    data.push(i.to_byte())
  }
  let compressed = tans_compress(data)
  let decompressed = tans_decompress(compressed)
  assert_true(decompressed.length() == data.length())
  for i = 0; i < data.length(); i = i + 1 {
    assert_true(decompressed[i] == data[i])
  }
}

///|
test "tans: large random-ish data" {
  let data : Array[Byte] = []
  let mut seed = 67890U
  for i = 0; i < 500; i = i + 1 {
    seed = seed * 1103515245U + 12345U
    data.push((seed >> 16).to_byte())
  }
  let compressed = tans_compress(data)
  let decompressed = tans_decompress(compressed)
  assert_true(decompressed.length() == data.length())
  for i = 0; i < data.length(); i = i + 1 {
    assert_true(decompressed[i] == data[i])
  }
}

///|
test "freq_table: empty input" {
  let ft = build_freq_table([], 14)
  assert_true(ft.total == 16384)
  assert_true(ft.alphabet.length() == 1)
}

///|
test "freq_table: single symbol" {
  let data : Array[Byte] = [b'A', b'A', b'A']
  let ft = build_freq_table(data, 14)
  assert_true(ft.alphabet.length() == 1)
  assert_true(ft.freqs[65] == ft.total)
}

///|
test "freq_table: normalised total is power of 2" {
  let data : Array[Byte] = []
  for i = 0; i < 100; i = i + 1 {
    data.push((i % 7).to_byte())
  }
  let ft = build_freq_table(data, 14)
  assert_true(ft.total == 1 << 14)
  let mut sum = 0
  for i = 0; i < ft.freqs.length(); i = i + 1 {
    sum = sum + ft.freqs[i]
  }
  assert_true(sum == ft.total)
}

///|
test "rans: invalid magic returns empty" {
  let bad : Array[Byte] = [b'\x00', b'\x00', b'\x00', b'\x00', b'\x00']
  let result = rans_decompress(bad)
  assert_true(result.length() == 0)
}

///|
test "tans: invalid magic returns empty" {
  let bad : Array[Byte] = [b'\x00', b'\x00', b'\x00', b'\x00', b'\x01']
  let result = tans_decompress(bad)
  assert_true(result.length() == 0)
}

///|
test "rans: compression ratio for skewed data" {
  let data : Array[Byte] = []
  for i = 0; i < 1000; i = i + 1 {
    if i % 100 < 99 {
      data.push(b'A')
    } else {
      data.push(b'B')
    }
  }
  let compressed = rans_compress(data)
  // Should compress well: 1000 bytes of mostly 'A' should be much smaller
  assert_true(compressed.length() < data.length())
}

///|
test "tans: compression ratio for skewed data" {
  let data : Array[Byte] = []
  for i = 0; i < 1000; i = i + 1 {
    if i % 100 < 99 {
      data.push(b'A')
    } else {
      data.push(b'B')
    }
  }
  let compressed = tans_compress(data)
  assert_true(compressed.length() < data.length())
}

///|
test "rans: two symbol data" {
  let data : Array[Byte] = []
  for i = 0; i < 100; i = i + 1 {
    data.push(if i % 2 == 0 { b'\x00' } else { b'\x01' })
  }
  let compressed = rans_compress(data)
  let decompressed = rans_decompress(compressed)
  assert_true(decompressed.length() == data.length())
  for i = 0; i < data.length(); i = i + 1 {
    assert_true(decompressed[i] == data[i])
  }
}

///|
test "tans: two symbol data" {
  let data : Array[Byte] = []
  for i = 0; i < 100; i = i + 1 {
    data.push(if i % 2 == 0 { b'\x00' } else { b'\x01' })
  }
  let compressed = tans_compress(data)
  let decompressed = tans_decompress(compressed)
  assert_true(decompressed.length() == data.length())
  for i = 0; i < data.length(); i = i + 1 {
    assert_true(decompressed[i] == data[i])
  }
}
