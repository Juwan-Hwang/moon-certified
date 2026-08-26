///|
/// LZMA (Lempel-Ziv-Markov chain Algorithm) compression.
///
/// Implements the LZMA compression algorithm as used in .xz and .lzma files.
/// LZMA combines LZ77 matching with range coding (binary arithmetic coding)
/// using context-adaptive probability models.
///
/// ## Architecture
///
/// 1. **Range coder**: Binary arithmetic coder with 32-bit range and 11-bit
///    probability models (2046 levels).
/// 2. **LZMA state machine**: 12-state model tracking recent match history.
/// 3. **Literal coder**: Context-adaptive coding using previous byte, state,
///    and match byte.
/// 4. **Length coder**: Two-stage length coding for match and repeated matches.
/// 5. **Distance coder**: Distance slot + direct bits + alignment bits.
/// 6. **Match finder**: Hash-chain LZ77 match finder.
/// 7. **xz container**: Stream header, blocks, index, footer.
///
/// ## References
///
/// - LZMA SDK: https://www.7-zip.org/sdk.html
/// - xz format: https://tukaani.org/xz/xz-file-format.txt
///
/// `proof-enabled` is `false`.

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const NUM_PROB_BITS : Int = 11

///|
const NUM_PROBS : Int = 1 << NUM_PROB_BITS // 2048

///|
const PROB_INIT_VAL : Int = NUM_PROBS / 2 // 1024

///|
const MOVE_BITS : Int = 5

///|
const NUM_STATES : Int = 12

///|
const LEN_LOW_BITS : Int = 3

///|
const LEN_LOW_SYMBOLS : Int = 1 << LEN_LOW_BITS

///|
const LEN_MID_BITS : Int = 3

///|
const LEN_MID_SYMBOLS : Int = 1 << LEN_MID_BITS

///|
const LEN_HIGH_BITS : Int = 8

///|
const LEN_HIGH_SYMBOLS : Int = 1 << LEN_HIGH_BITS

///|
const MIN_MATCH_LEN : Int = 2

///|
const NUM_DISTANCE_SLOTS : Int = 64

///|
const NUM_ALIGN_BITS : Int = 4

///|
const ALIGN_TABLE_SIZE : Int = 1 << NUM_ALIGN_BITS

///|
const END_MARKER_DIST : Int = 0xFFFFFFFF

///|
const LZMA_MAX_MATCH_LEN : Int = 273

// ---------------------------------------------------------------------------
// Range Encoder
// ---------------------------------------------------------------------------

///|
/// Range encoder: writes bits to output using arithmetic coding.
priv struct RangeEncoder {
  mut low : UInt64
  mut range : UInt
  mut cache : UInt
  mut cache_size : UInt64
  out : Array[Byte]
}

///|
fn RangeEncoder::new() -> RangeEncoder {
  { low: 0UL, range: 0xFFFFFFFFU, cache: 0U, cache_size: 1UL, out: [] }
}

///|
fn RangeEncoder::normalize(self : RangeEncoder) -> Unit {
  if self.range < 1U << 24 {
    self.range = self.range << 8
    self.shift_low()
  }
}

///|
fn RangeEncoder::shift_low(self : RangeEncoder) -> Unit {
  let high = (self.low >> 32).to_uint()
  let low32 = (self.low & 0xFFFFFFFFUL).to_uint()
  // Flush when carry occurred (high != 0) or lower 32 bits < 0xFF000000
  if low32 < 0xFF000000U || high != 0U {
    // Output the cached byte (plus any carry)
    let mut temp = self.cache + high
    self.out.push(temp.to_byte())
    // Output pending 0xFF or 0x00 bytes
    let mut i = 1UL
    while i < self.cache_size {
      // If carry (high != 0), pending bytes become 0x00; otherwise 0xFF
      temp = if high != 0U { 0U } else { 0xFFU }
      self.out.push(temp.to_byte())
      i = i + 1UL
    }
    self.cache_size = 1UL
    self.cache = low32 >> 24
  } else {
    self.cache_size = self.cache_size + 1UL
  }
  self.low = ((self.low & 0xFFFFFFFFUL) << 8) & 0xFFFFFFFFUL
}

///|
fn RangeEncoder::_encode_bit(self : RangeEncoder, prob : Int, bit : Int) -> Unit {
  let bound = ((self.range.to_uint64() * prob.to_uint64()) >> NUM_PROB_BITS).to_uint()
  if bit != 0 {
    self.low = self.low + bound.to_uint64()
    self.range = self.range - bound
  } else {
    self.range = bound
  }
  self.normalize()
}

///|
/// Encode a bit with probability model update (matches decoder behavior).
fn RangeEncoder::encode_bit_prob(
  self : RangeEncoder,
  probs : FixedArray[Int],
  idx : Int,
  bit : Int,
) -> Unit {
  let prob = probs[idx]
  let bound = ((self.range.to_uint64() * prob.to_uint64()) >> NUM_PROB_BITS).to_uint()
  if bit != 0 {
    self.low = self.low + bound.to_uint64()
    self.range = self.range - bound
    probs[idx] = prob - (prob >> MOVE_BITS)
  } else {
    self.range = bound
    probs[idx] = prob + ((NUM_PROBS - prob) >> MOVE_BITS)
  }
  self.normalize()
}

///|
fn RangeEncoder::encode_direct_bit(self : RangeEncoder, bit : Int) -> Unit {
  let bound = self.range >> 1
  if bit != 0 {
    self.low = self.low + bound.to_uint64()
    self.range = bound
  } else {
    self.range = bound
  }
  self.normalize()
}

///|
fn RangeEncoder::encode_bit_tree(
  self : RangeEncoder,
  probs : FixedArray[Int],
  symbol_in : Int,
  num_bits : Int,
) -> Unit {
  let mut m = 1
  let mut symbol = symbol_in
  for _i = 0; _i < num_bits; _i = _i + 1 {
    let bit = (symbol >> (num_bits - 1)) & 1
    self.encode_bit_prob(probs, m, bit)
    m = (m << 1) | bit
    symbol = symbol << 1
  }
}

///|
fn RangeEncoder::encode_reverse_bit_tree(
  self : RangeEncoder,
  probs : FixedArray[Int],
  symbol_in : Int,
  num_bits : Int,
) -> Unit {
  let mut m = 1
  let mut symbol = symbol_in
  for _i = 0; _i < num_bits; _i = _i + 1 {
    let bit = symbol & 1
    self.encode_bit_prob(probs, m, bit)
    m = (m << 1) | bit
    symbol = symbol >> 1
  }
}

///|
fn RangeEncoder::encode_bit_tree_offset(
  self : RangeEncoder,
  probs : FixedArray[Int],
  offset : Int,
  symbol_in : Int,
  num_bits : Int,
) -> Unit {
  let mut m = 1
  let mut symbol = symbol_in
  for _i = 0; _i < num_bits; _i = _i + 1 {
    let bit = (symbol >> (num_bits - 1)) & 1
    self.encode_bit_prob(probs, offset + m, bit)
    m = (m << 1) | bit
    symbol = symbol << 1
  }
}

///|
fn RangeEncoder::encode_reverse_bit_tree_direct(
  self : RangeEncoder,
  symbol_in : Int,
  num_bits : Int,
) -> Unit {
  let mut symbol = symbol_in
  for _i = 0; _i < num_bits; _i = _i + 1 {
    self.encode_direct_bit(symbol & 1)
    symbol = symbol >> 1
  }
}

///|
fn RangeEncoder::flush(self : RangeEncoder) -> Unit {
  for _i = 0; _i < 5; _i = _i + 1 {
    self.shift_low()
  }
}

// ---------------------------------------------------------------------------
// Range Decoder
// ---------------------------------------------------------------------------

///|
priv struct RangeDecoder {
  mut range : UInt
  mut code : UInt
  data : Bytes
  mut pos : Int
}

///|
fn RangeDecoder::_new(data : Bytes) -> RangeDecoder {
  let rd = { range: 0xFFFFFFFFU, code: 0U, data, pos: 1 }
  for _i = 0; _i < 4; _i = _i + 1 {
    rd.code = (rd.code << 8) | rd.next_byte()
  }
  rd
}

///|
fn RangeDecoder::next_byte(self : RangeDecoder) -> UInt {
  if self.pos < self.data.length() {
    let b = self.data[self.pos]
    self.pos = self.pos + 1
    return b.to_uint()
  }
  0U
}

///|
fn RangeDecoder::normalize(self : RangeDecoder) -> Unit {
  if self.range < 1U << 24 {
    self.range = self.range << 8
    self.code = (self.code << 8) | self.next_byte()
  }
}

///|
fn RangeDecoder::decode_bit(
  self : RangeDecoder,
  probs : FixedArray[Int],
  prob_idx : Int,
) -> Int {
  let prob = probs[prob_idx]
  let bound = ((self.range.to_uint64() * prob.to_uint64()) >> NUM_PROB_BITS).to_uint()
  if self.code < bound {
    self.range = bound
    probs[prob_idx] = prob + ((NUM_PROBS - prob) >> MOVE_BITS)
    self.normalize()
    0
  } else {
    self.range = self.range - bound
    self.code = self.code - bound
    probs[prob_idx] = prob - (prob >> MOVE_BITS)
    self.normalize()
    1
  }
}

///|
fn RangeDecoder::decode_direct_bit(self : RangeDecoder) -> Int {
  let bound = self.range >> 1
  if self.code < bound {
    self.range = bound
    self.normalize()
    0
  } else {
    self.range = self.range - bound
    self.code = self.code - bound
    self.normalize()
    1
  }
}

///|
fn RangeDecoder::decode_bit_tree(
  self : RangeDecoder,
  probs : FixedArray[Int],
  num_bits : Int,
) -> Int {
  let mut m = 1
  for _i = 0; _i < num_bits; _i = _i + 1 {
    m = (m << 1) | self.decode_bit(probs, m)
  }
  m - (1 << num_bits)
}

///|
fn RangeDecoder::decode_reverse_bit_tree(
  self : RangeDecoder,
  probs : FixedArray[Int],
  num_bits : Int,
) -> Int {
  let mut m = 1
  let mut symbol = 0
  for i = 0; i < num_bits; i = i + 1 {
    let bit = self.decode_bit(probs, m)
    m = (m << 1) | bit
    symbol = symbol | (bit << i)
  }
  symbol
}

///|
fn RangeDecoder::decode_bit_tree_offset(
  self : RangeDecoder,
  probs : FixedArray[Int],
  offset : Int,
  num_bits : Int,
) -> Int {
  let mut m = 1
  for _i = 0; _i < num_bits; _i = _i + 1 {
    m = (m << 1) | self.decode_bit(probs, offset + m)
  }
  m - (1 << num_bits)
}

///|
fn RangeDecoder::decode_reverse_direct(
  self : RangeDecoder,
  num_bits : Int,
) -> Int {
  let mut symbol = 0
  for i = 0; i < num_bits; i = i + 1 {
    symbol = symbol | (self.decode_direct_bit() << i)
  }
  symbol
}

// ---------------------------------------------------------------------------
// LZMA State Machine
// ---------------------------------------------------------------------------

///|
fn state_next_literal(state : Int) -> Int {
  match state {
    0 => 0
    1 => 0
    2 => 0
    3 => 0
    4 => 1
    5 => 2
    6 => 3
    7 => 4
    8 => 5
    9 => 6
    10 => 4
    11 => 5
    _ => 0
  }
}

///|
fn state_next_match(state : Int) -> Int {
  if state < 7 {
    7
  } else {
    10
  }
}

///|
fn state_next_rep(state : Int) -> Int {
  if state < 7 {
    8
  } else {
    11
  }
}

///|
fn state_next_short_rep(state : Int) -> Int {
  if state < 7 {
    9
  } else {
    11
  }
}

///|
fn state_is_prev_match(state : Int) -> Bool {
  state >= 4
}

// ---------------------------------------------------------------------------
// Distance Slot
// ---------------------------------------------------------------------------

///|
fn get_distance_slot(dist : Int) -> Int {
  if dist < 4 {
    return dist
  }
  // Find highest bit position n = floor(log2(dist))
  let mut n = 0
  let mut tmp = dist
  while tmp > 1 {
    tmp = tmp >> 1
    n = n + 1
  }
  // Distances [2^n, 3*2^(n-1)) → slot 2n
  // Distances [3*2^(n-1), 2^(n+1)) → slot 2n+1
  let midpoint = (1 << n) + (1 << (n - 1))
  if dist < midpoint {
    2 * n
  } else {
    2 * n + 1
  }
}

///|
fn get_distance_slot_extra_bits(slot : Int) -> Int {
  if slot < 4 {
    0
  } else {
    (slot >> 1) - 1
  }
}

///|
fn get_distance_slot_base(slot : Int) -> Int {
  if slot < 4 {
    slot
  } else {
    let extra = get_distance_slot_extra_bits(slot)
    (2 | (slot & 1)) << extra
  }
}

// ---------------------------------------------------------------------------
// Probability Model
// ---------------------------------------------------------------------------

///|
priv struct LzmaProbs {
  literal_probs : FixedArray[Int]
  len_choice : FixedArray[Int]
  len_low : FixedArray[Int]
  len_mid : FixedArray[Int]
  len_high : FixedArray[Int]
  rep_len_choice : FixedArray[Int]
  rep_len_low : FixedArray[Int]
  rep_len_mid : FixedArray[Int]
  rep_len_high : FixedArray[Int]
  is_match : FixedArray[Int]
  is_rep : FixedArray[Int]
  is_rep_g0 : FixedArray[Int]
  is_rep_g1 : FixedArray[Int]
  is_rep_g2 : FixedArray[Int]
  is_rep0_long : FixedArray[Int]
  pos_slot : FixedArray[Int]
  align : FixedArray[Int]
}

///|
fn LzmaProbs::new() -> LzmaProbs {
  let num_lit = 8 * 0x300 // lc=3, lp=0
  let num_pos_slots = NUM_DISTANCE_SLOTS * 4 // pb=2
  {
    literal_probs: FixedArray::make(num_lit, PROB_INIT_VAL),
    len_choice: FixedArray::make(3, PROB_INIT_VAL),
    len_low: FixedArray::make(16 * LEN_LOW_SYMBOLS, PROB_INIT_VAL),
    len_mid: FixedArray::make(16 * LEN_MID_SYMBOLS, PROB_INIT_VAL),
    len_high: FixedArray::make(LEN_HIGH_SYMBOLS * 2, PROB_INIT_VAL),
    rep_len_choice: FixedArray::make(3, PROB_INIT_VAL),
    rep_len_low: FixedArray::make(16 * LEN_LOW_SYMBOLS, PROB_INIT_VAL),
    rep_len_mid: FixedArray::make(16 * LEN_MID_SYMBOLS, PROB_INIT_VAL),
    rep_len_high: FixedArray::make(LEN_HIGH_SYMBOLS * 2, PROB_INIT_VAL),
    is_match: FixedArray::make(NUM_STATES * 4, PROB_INIT_VAL),
    is_rep: FixedArray::make(NUM_STATES, PROB_INIT_VAL),
    is_rep_g0: FixedArray::make(NUM_STATES, PROB_INIT_VAL),
    is_rep_g1: FixedArray::make(NUM_STATES, PROB_INIT_VAL),
    is_rep_g2: FixedArray::make(NUM_STATES, PROB_INIT_VAL),
    is_rep0_long: FixedArray::make(NUM_STATES * 4, PROB_INIT_VAL),
    pos_slot: FixedArray::make(num_pos_slots, PROB_INIT_VAL),
    align: FixedArray::make(ALIGN_TABLE_SIZE * 2, PROB_INIT_VAL),
  }
}

// ---------------------------------------------------------------------------
// Length Coding
// ---------------------------------------------------------------------------

///|
fn encode_length(
  rc : RangeEncoder,
  probs : LzmaProbs,
  pos_state : Int,
  len : Int,
  is_rep : Bool,
) -> Unit {
  let l = len - MIN_MATCH_LEN
  let choice = if is_rep { probs.rep_len_choice } else { probs.len_choice }
  let low = if is_rep { probs.rep_len_low } else { probs.len_low }
  let mid = if is_rep { probs.rep_len_mid } else { probs.len_mid }
  let high = if is_rep { probs.rep_len_high } else { probs.len_high }
  if l < LEN_LOW_SYMBOLS {
    rc.encode_bit_prob(choice, 0, 0)
    let base = pos_state * LEN_LOW_SYMBOLS
    rc.encode_bit_tree_offset(low, base, l, LEN_LOW_BITS)
  } else if l < LEN_LOW_SYMBOLS + LEN_MID_SYMBOLS {
    rc.encode_bit_prob(choice, 0, 1)
    rc.encode_bit_prob(choice, 1, 0)
    let base = pos_state * LEN_MID_SYMBOLS
    rc.encode_bit_tree_offset(mid, base, l - LEN_LOW_SYMBOLS, LEN_MID_BITS)
  } else {
    rc.encode_bit_prob(choice, 0, 1)
    rc.encode_bit_prob(choice, 1, 1)
    rc.encode_bit_tree(
      high,
      l - LEN_LOW_SYMBOLS - LEN_MID_SYMBOLS,
      LEN_HIGH_BITS,
    )
  }
}

///|
fn decode_length(
  rd : RangeDecoder,
  probs : LzmaProbs,
  is_rep : Bool,
  pos_state : Int,
) -> Int {
  let choice = if is_rep { probs.rep_len_choice } else { probs.len_choice }
  let low = if is_rep { probs.rep_len_low } else { probs.len_low }
  let mid = if is_rep { probs.rep_len_mid } else { probs.len_mid }
  let high = if is_rep { probs.rep_len_high } else { probs.len_high }
  if rd.decode_bit(choice, 0) == 0 {
    let base = pos_state * LEN_LOW_SYMBOLS
    rd.decode_bit_tree_offset(low, base, LEN_LOW_BITS) + MIN_MATCH_LEN
  } else if rd.decode_bit(choice, 1) == 0 {
    let base = pos_state * LEN_MID_SYMBOLS
    rd.decode_bit_tree_offset(mid, base, LEN_MID_BITS) +
    MIN_MATCH_LEN +
    LEN_LOW_SYMBOLS
  } else {
    rd.decode_bit_tree(high, LEN_HIGH_BITS) +
    MIN_MATCH_LEN +
    LEN_LOW_SYMBOLS +
    LEN_MID_SYMBOLS
  }
}

// ---------------------------------------------------------------------------
// Distance Coding
// ---------------------------------------------------------------------------

///|
fn encode_distance(
  rc : RangeEncoder,
  probs : LzmaProbs,
  pos_state : Int,
  dist : Int,
) -> Unit {
  if dist == END_MARKER_DIST {
    // End marker: use slot 63 with matching encoding
    let slot_base = pos_state * NUM_DISTANCE_SLOTS
    rc.encode_bit_tree_offset(probs.pos_slot, slot_base, 63, 6)
    let extra = get_distance_slot_extra_bits(63)
    let base = get_distance_slot_base(63)
    let val = dist - base
    // Use same encoding as normal distances for extra > 4
    let high_extra = extra - NUM_ALIGN_BITS
    let mut v = val >> NUM_ALIGN_BITS
    for _i = 0; _i < high_extra; _i = _i + 1 {
      rc.encode_direct_bit((v >> (high_extra - 1)) & 1)
      v = v << 1
    }
    rc.encode_reverse_bit_tree(
      probs.align,
      val & (ALIGN_TABLE_SIZE - 1),
      NUM_ALIGN_BITS,
    )
    return
  }
  let slot = get_distance_slot(dist)
  let slot_base = pos_state * NUM_DISTANCE_SLOTS
  rc.encode_bit_tree_offset(probs.pos_slot, slot_base, slot, 6)
  let extra = get_distance_slot_extra_bits(slot)
  if extra == 0 {
    return
  }
  let base = get_distance_slot_base(slot)
  let val = dist - base
  if extra <= 4 {
    rc.encode_reverse_bit_tree_direct(val, extra)
  } else {
    let high_extra = extra - NUM_ALIGN_BITS
    let mut v = val >> NUM_ALIGN_BITS
    for _i = 0; _i < high_extra; _i = _i + 1 {
      rc.encode_direct_bit((v >> (high_extra - 1)) & 1)
      v = v << 1
    }
    rc.encode_reverse_bit_tree(
      probs.align,
      val & (ALIGN_TABLE_SIZE - 1),
      NUM_ALIGN_BITS,
    )
  }
}

///|
fn decode_distance(
  rd : RangeDecoder,
  probs : LzmaProbs,
  pos_state : Int,
) -> Int {
  let slot_base = pos_state * NUM_DISTANCE_SLOTS
  let slot = rd.decode_bit_tree_offset(probs.pos_slot, slot_base, 6)
  let extra = get_distance_slot_extra_bits(slot)
  if extra == 0 {
    slot
  } else {
    let base = get_distance_slot_base(slot)
    let val = if extra <= 4 {
      rd.decode_reverse_direct(extra)
    } else {
      let high_extra = extra - NUM_ALIGN_BITS
      let mut high = 0
      for _i = 0; _i < high_extra; _i = _i + 1 {
        high = (high << 1) | rd.decode_direct_bit()
      }
      let low = rd.decode_reverse_bit_tree(probs.align, NUM_ALIGN_BITS)
      (high << NUM_ALIGN_BITS) | low
    }
    base + val
  }
}

// ---------------------------------------------------------------------------
// Literal Coding
// ---------------------------------------------------------------------------

///|
fn encode_literal(
  rc : RangeEncoder,
  probs : LzmaProbs,
  prev_byte : Int,
  match_byte : Int,
  byte : Int,
  prev_was_match : Bool,
) -> Unit {
  let lc = 3
  let lit_ctx = prev_byte >> (8 - lc)
  let lit_state = lit_ctx * 0x300
  if prev_was_match && match_byte >= 0 {
    let mut match_val = match_byte
    let mut sym = byte
    let mut m = 1
    for _i = 0; _i < 8; _i = _i + 1 {
      let match_bit = (match_val >> 7) & 1
      let bit = (sym >> 7) & 1
      let offset = (1 + match_bit) << 8
      rc.encode_bit_prob(probs.literal_probs, lit_state + offset + m, bit)
      m = (m << 1) | bit
      match_val = (match_val << 1) & 0xFF
      sym = (sym << 1) & 0xFF
    }
  } else {
    let mut sym = byte
    let mut m = 1
    for _i = 0; _i < 8; _i = _i + 1 {
      let bit = (sym >> 7) & 1
      rc.encode_bit_prob(probs.literal_probs, lit_state + m, bit)
      m = (m << 1) | bit
      sym = (sym << 1) & 0xFF
    }
  }
}

///|
fn decode_literal(
  rd : RangeDecoder,
  probs : LzmaProbs,
  prev_byte : Int,
  match_byte : Int,
  prev_was_match : Bool,
) -> Int {
  let lc = 3
  let lit_ctx = prev_byte >> (8 - lc)
  let lit_state = lit_ctx * 0x300
  if prev_was_match && match_byte >= 0 {
    let mut match_val = match_byte
    let mut m = 1
    let mut byte = 0
    for _i = 0; _i < 8; _i = _i + 1 {
      let match_bit = (match_val >> 7) & 1
      let offset = (1 + match_bit) << 8
      let bit = rd.decode_bit(probs.literal_probs, lit_state + offset + m)
      m = (m << 1) | bit
      byte = (byte << 1) | bit
      match_val = (match_val << 1) & 0xFF
    }
    byte
  } else {
    let mut m = 1
    let mut byte = 0
    for _i = 0; _i < 8; _i = _i + 1 {
      let bit = rd.decode_bit(probs.literal_probs, lit_state + m)
      m = (m << 1) | bit
      byte = (byte << 1) | bit
    }
    byte
  }
}

// ---------------------------------------------------------------------------
// Match Finder
// ---------------------------------------------------------------------------

///|
priv struct MatchFinder {
  data : Bytes
  mut pos : Int
  end : Int
  hash : FixedArray[Int]
  prev : FixedArray[Int]
  window_size : Int
  min_match : Int
  nice_match : Int
  max_chain : Int
}

///|
fn MatchFinder::new(
  data : Bytes,
  window_size : Int,
  nice_match : Int,
  max_chain : Int,
) -> MatchFinder {
  let n = data.length()
  let hash_size = 1 << 16
  {
    data,
    pos: 0,
    end: n,
    hash: FixedArray::make(hash_size, -1),
    prev: FixedArray::make(if n > 0 { n + 1 } else { 1 }, -1),
    window_size,
    min_match: 3,
    nice_match,
    max_chain,
  }
}

///|
fn MatchFinder::hash3(self : MatchFinder, pos : Int) -> Int {
  if pos + 2 >= self.data.length() {
    return 0
  }
  let b0 = self.data[pos].to_int()
  let b1 = self.data[pos + 1].to_int()
  let b2 = self.data[pos + 2].to_int()
  ((b0 << 8) ^ (b1 << 4) ^ b2) & 0xFFFF
}

///|
fn MatchFinder::advance(self : MatchFinder) -> Unit {
  if self.pos + 2 < self.end {
    let h = self.hash3(self.pos)
    self.prev[self.pos] = self.hash[h]
    self.hash[h] = self.pos
  }
  self.pos = self.pos + 1
}

///|
fn MatchFinder::find_match(self : MatchFinder) -> (Int, Int) {
  let pos = self.pos
  if pos + self.min_match > self.end {
    return (0, 0)
  }
  let h = self.hash3(pos)
  let mut cand = self.hash[h]
  let mut best_len = 0
  let mut best_dist = 0
  let mut chain = 0
  let max_dist = if pos > self.window_size { self.window_size } else { pos }
  while cand >= 0 && chain < self.max_chain {
    let dist = pos - cand
    if dist > max_dist {
      break
    }
    let mut len = 0
    while pos + len < self.end &&
          len < LZMA_MAX_MATCH_LEN &&
          self.data[cand + len] == self.data[pos + len] {
      len = len + 1
    }
    if len >= self.min_match && len > best_len {
      best_len = len
      best_dist = dist
      if len >= self.nice_match {
        break
      }
    }
    cand = self.prev[cand]
    chain = chain + 1
  }
  (best_dist, best_len)
}

// ---------------------------------------------------------------------------
// LZMA Encoder
// ---------------------------------------------------------------------------

///|
/// LZMA encoder parameters.
pub struct LzmaEncProps {
  lc : Int
  lp : Int
  pb : Int
  dict_size : Int
  nice_match : Int
  max_chain : Int
}

///|
/// Default LZMA encoder properties.
pub fn default_enc_props() -> LzmaEncProps {
  {
    lc: 3,
    lp: 0,
    pb: 2,
    dict_size: 8 * 1024 * 1024,
    nice_match: 128,
    max_chain: 1024,
  }
}

///|
priv struct LzmaEncoder {
  rc : RangeEncoder
  probs : LzmaProbs
  mut state : Int
  rep_dists : FixedArray[Int]
  mut pos : Int
  data : Bytes
}

///|
/// Encode data using LZMA compression.
pub fn compress(data : Bytes) -> Bytes {
  compress_with_props(data, default_enc_props())
}

///|
/// Encode data using LZMA compression with custom properties.
pub fn compress_with_props(data : Bytes, props : LzmaEncProps) -> Bytes {
  let n = data.length()
  let enc : LzmaEncoder = {
    rc: RangeEncoder::new(),
    probs: LzmaProbs::new(),
    state: 0,
    rep_dists: FixedArray::make(4, 0),
    pos: 0,
    data,
  }
  let mf = MatchFinder::new(
    data,
    props.dict_size,
    props.nice_match,
    props.max_chain,
  )
  while enc.pos < n {
    let pos_state = enc.pos & ((1 << props.pb) - 1)
    let state_idx = enc.state * (1 << props.pb) + pos_state
    let (dist, len) = mf.find_match()
    if len >= 3 && dist > 0 {
      enc.rc.encode_bit_prob(enc.probs.is_match, state_idx, 1)
      let rep_idx = find_rep(enc.rep_dists, dist)
      if rep_idx >= 0 {
        encode_rep_match(enc, rep_idx, len, pos_state, props)
      } else {
        encode_normal_match(enc, dist, len, pos_state, props)
      }
      let advance_count = len
      for _i = 0; _i < advance_count; _i = _i + 1 {
        mf.advance()
      }
    } else {
      encode_literal_byte(enc, pos_state, props)
      mf.advance()
    }
  }
  // End marker
  let pos_state = enc.pos & ((1 << props.pb) - 1)
  let state_idx = enc.state * (1 << props.pb) + pos_state
  enc.rc.encode_bit_prob(enc.probs.is_match, state_idx, 1)
  enc.rc.encode_bit_prob(enc.probs.is_rep, enc.state, 0)
  encode_distance(enc.rc, enc.probs, pos_state, END_MARKER_DIST)
  enc.rc.flush()
  // Build output
  let result : Array[Byte] = []
  let prop_byte = (props.pb * 5 + props.lp) * 9 + props.lc
  result.push(prop_byte.to_byte())
  let usize = n.to_uint64()
  for i = 0; i < 8; i = i + 1 {
    result.push(((usize >> (i * 8)) & 0xFFUL).to_byte())
  }
  for i = 0; i < enc.rc.out.length(); i = i + 1 {
    result.push(enc.rc.out[i])
  }
  Bytes::from_array(result)
}

///|
fn find_rep(rep_dists : FixedArray[Int], dist : Int) -> Int {
  for i = 0; i < 4; i = i + 1 {
    if rep_dists[i] == dist {
      return i
    }
  }
  -1
}

///|
fn encode_literal_byte(
  enc : LzmaEncoder,
  pos_state : Int,
  props : LzmaEncProps,
) -> Unit {
  let state_idx = enc.state * (1 << props.pb) + pos_state
  enc.rc.encode_bit_prob(enc.probs.is_match, state_idx, 0)
  let prev_byte = if enc.pos > 0 { enc.data[enc.pos - 1].to_int() } else { 0 }
  let byte = enc.data[enc.pos].to_int()
  let prev_was_match = state_is_prev_match(enc.state)
  let match_byte = if prev_was_match &&
    enc.pos > enc.rep_dists[0] &&
    enc.rep_dists[0] > 0 {
    enc.data[enc.pos - enc.rep_dists[0] - 1].to_int()
  } else {
    -1
  }
  encode_literal(enc.rc, enc.probs, prev_byte, match_byte, byte, prev_was_match)
  enc.state = state_next_literal(enc.state)
  enc.pos = enc.pos + 1
}

///|
fn encode_normal_match(
  enc : LzmaEncoder,
  dist : Int,
  len : Int,
  pos_state : Int,
  _props : LzmaEncProps,
) -> Unit {
  enc.rc.encode_bit_prob(enc.probs.is_rep, enc.state, 0)
  encode_length(enc.rc, enc.probs, pos_state, len, false)
  encode_distance(enc.rc, enc.probs, pos_state, dist)
  enc.rep_dists[3] = enc.rep_dists[2]
  enc.rep_dists[2] = enc.rep_dists[1]
  enc.rep_dists[1] = enc.rep_dists[0]
  enc.rep_dists[0] = dist
  enc.state = state_next_match(enc.state)
  enc.pos = enc.pos + len
}

///|
fn encode_rep_match(
  enc : LzmaEncoder,
  rep_idx : Int,
  len : Int,
  pos_state : Int,
  props : LzmaEncProps,
) -> Unit {
  enc.rc.encode_bit_prob(enc.probs.is_rep, enc.state, 1)
  if rep_idx == 0 {
    enc.rc.encode_bit_prob(enc.probs.is_rep_g0, enc.state, 0)
    let long_state = enc.state * (1 << props.pb) + pos_state
    if len == 1 {
      enc.rc.encode_bit_prob(enc.probs.is_rep0_long, long_state, 0)
      enc.state = state_next_short_rep(enc.state)
      enc.pos = enc.pos + 1
      return
    }
    enc.rc.encode_bit_prob(enc.probs.is_rep0_long, long_state, 1)
  } else {
    enc.rc.encode_bit_prob(enc.probs.is_rep_g0, enc.state, 1)
    if rep_idx == 1 {
      enc.rc.encode_bit_prob(enc.probs.is_rep_g1, enc.state, 0)
      let tmp = enc.rep_dists[0]
      enc.rep_dists[0] = enc.rep_dists[1]
      enc.rep_dists[1] = tmp
    } else {
      enc.rc.encode_bit_prob(enc.probs.is_rep_g1, enc.state, 1)
      if rep_idx == 2 {
        enc.rc.encode_bit_prob(enc.probs.is_rep_g2, enc.state, 0)
        let d = enc.rep_dists[2]
        enc.rep_dists[2] = enc.rep_dists[1]
        enc.rep_dists[1] = enc.rep_dists[0]
        enc.rep_dists[0] = d
      } else {
        enc.rc.encode_bit_prob(enc.probs.is_rep_g2, enc.state, 1)
        let d = enc.rep_dists[3]
        enc.rep_dists[3] = enc.rep_dists[2]
        enc.rep_dists[2] = enc.rep_dists[1]
        enc.rep_dists[1] = enc.rep_dists[0]
        enc.rep_dists[0] = d
      }
    }
  }
  encode_length(enc.rc, enc.probs, pos_state, len, true)
  enc.state = state_next_rep(enc.state)
  enc.pos = enc.pos + len
}

// ---------------------------------------------------------------------------
// LZMA Decoder
// ---------------------------------------------------------------------------

///|
/// Decode LZMA compressed data.
pub fn decompress(data : Bytes) -> Bytes? {
  if data.length() < 13 {
    return None
  }
  let prop_byte = data[0].to_int()
  let lc = prop_byte % 9
  let lp = prop_byte / 9 % 5
  let pb = prop_byte / 9 / 5
  if pb > 4 || lc + lp > 4 {
    return None
  }
  // Probability tables are sized for lc=3, lp=0, pb=2 (encoder default).
  // Reject streams with incompatible parameters.
  if lc != 3 || lp != 0 || pb != 2 {
    return None
  }
  let mut usize = 0UL
  for i = 0; i < 8; i = i + 1 {
    usize = usize.lor(data[1 + i].to_uint64() << (i * 8))
  }
  let has_end_marker = usize == 0xFFFFFFFFFFFFFFFFUL
  if !has_end_marker && usize > 0xFFFFFFFFUL {
    return None
  }
  if data.length() < 14 || data[9] != 0 {
    return None
  }
  // Initialize range decoder: skip byte 9 (0x00 cache byte), read bytes 10-13 into code
  let rd : RangeDecoder = { range: 0xFFFFFFFFU, code: 0U, data, pos: 10 }
  for _i = 0; _i < 4; _i = _i + 1 {
    rd.code = (rd.code << 8) | rd.next_byte()
  }
  // pos is now 14
  let probs = LzmaProbs::new()
  let mut state = 0
  let rep_dists = FixedArray::make(4, 0)
  let out : Array[Byte] = []
  let target_size = if has_end_marker { 0 } else { usize.to_int() }
  let pos_mask = (1 << pb) - 1
  let pb_shift = 1 << pb
  while has_end_marker || out.length() < target_size {
    let pos = out.length()
    let pos_state = pos & pos_mask
    let state_idx = state * pb_shift + pos_state
    if rd.decode_bit(probs.is_match, state_idx) == 0 {
      // Literal
      let prev_byte = if pos > 0 { out[pos - 1].to_int() } else { 0 }
      let prev_was_match = state_is_prev_match(state)
      let match_byte = if prev_was_match &&
        pos > rep_dists[0] &&
        rep_dists[0] > 0 {
        out[pos - rep_dists[0] - 1].to_int()
      } else {
        -1
      }
      let byte = decode_literal(
        rd, probs, prev_byte, match_byte, prev_was_match,
      )
      out.push(byte.to_byte())
      state = state_next_literal(state)
      // Match
    } else if rd.decode_bit(probs.is_rep, state) == 1 {
      // Repeated match
      if rd.decode_bit(probs.is_rep_g0, state) == 0 {
        let long_state = state * pb_shift + pos_state
        if rd.decode_bit(probs.is_rep0_long, long_state) == 0 {
          // Short rep
          if rep_dists[0] == 0 || pos < rep_dists[0] {
            return None
          }
          out.push(out[pos - rep_dists[0] - 1])
          state = state_next_short_rep(state)
          continue
        }
      } else if rd.decode_bit(probs.is_rep_g1, state) == 0 {
        let d = rep_dists[1]
        rep_dists[1] = rep_dists[0]
        rep_dists[0] = d
      } else if rd.decode_bit(probs.is_rep_g2, state) == 0 {
        let d = rep_dists[2]
        rep_dists[2] = rep_dists[1]
        rep_dists[1] = rep_dists[0]
        rep_dists[0] = d
      } else {
        let d = rep_dists[3]
        rep_dists[3] = rep_dists[2]
        rep_dists[2] = rep_dists[1]
        rep_dists[1] = rep_dists[0]
        rep_dists[0] = d
      }
      let len = decode_length(rd, probs, true, pos_state)
      state = state_next_rep(state)
      let dist = rep_dists[0]
      if dist == 0 || pos < dist {
        return None
      }
      for _j = 0; _j < len; _j = _j + 1 {
        let src_idx = out.length() - dist
        if src_idx < 0 || src_idx >= out.length() {
          return None
        }
        out.push(out[src_idx])
      }
    } else {
      // Normal match
      let len = decode_length(rd, probs, false, pos_state)
      state = state_next_match(state)
      let dist = decode_distance(rd, probs, pos_state)
      if dist == END_MARKER_DIST {
        break
      }
      if dist == 0 || pos < dist {
        return None
      }
      rep_dists[3] = rep_dists[2]
      rep_dists[2] = rep_dists[1]
      rep_dists[1] = rep_dists[0]
      rep_dists[0] = dist
      for _j = 0; _j < len; _j = _j + 1 {
        let src_idx = out.length() - dist
        if src_idx < 0 || src_idx >= out.length() {
          return None
        }
        out.push(out[src_idx])
      }
    }
  }
  Some(Bytes::from_array(out))
}

// ---------------------------------------------------------------------------
// xz Container Format
// ---------------------------------------------------------------------------

///|
/// CRC-32 (IEEE 802.3 polynomial: 0xEDB88320 reflected).
pub fn crc32(data : Bytes) -> UInt {
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

///|
/// Encode data in xz format.
pub fn xz_compress(data : Bytes) -> Bytes {
  let lzma_data = compress(data)
  let result : Array[Byte] = []
  // Stream Header: magic (6) + flags (2) + CRC32 (4)
  result.push(b'\xFD')
  result.push(b'7')
  result.push(b'z')
  result.push(b'X')
  result.push(b'Z')
  result.push(b'\x00')
  result.push(b'\x00')
  result.push(b'\x01')
  let flag_bytes = Bytes::from_array([b'\x00', b'\x01'])
  let header_crc = crc32(flag_bytes)
  for i = 0; i < 4; i = i + 1 {
    result.push(((header_crc >> (i * 8)) & 0xFFU).to_byte())
  }
  // Block Header
  let block_header : Array[Byte] = []
  block_header.push(b'\x00') // flags: 1 filter, no sizes
  block_header.push(b'\x21') // filter ID: LZMA2
  block_header.push(b'\x01') // properties size: 1
  block_header.push(b'\x1B') // dict size
  while (block_header.length() + 1) % 4 != 0 {
    block_header.push(b'\x00')
  }
  let total_header_size = block_header.length() + 1 + 4
  let header_size_byte = (total_header_size / 4 - 1).to_byte()
  result.push(header_size_byte)
  // Write block header content (flags, filter ID, properties, padding)
  for i = 0; i < block_header.length(); i = i + 1 {
    result.push(block_header[i])
  }
  // CRC32 covers header_size_byte + block_header content
  let bh_for_crc : Array[Byte] = [header_size_byte]
  for i = 0; i < block_header.length(); i = i + 1 {
    bh_for_crc.push(block_header[i])
  }
  let bh_crc = crc32(Bytes::from_array(bh_for_crc))
  for i = 0; i < 4; i = i + 1 {
    result.push(((bh_crc >> (i * 8)) & 0xFFU).to_byte())
  }
  // Compressed data (full LZMA stream including props + usize)
  for i = 0; i < lzma_data.length(); i = i + 1 {
    result.push(lzma_data[i])
  }
  // Block check (CRC32 of uncompressed data)
  let block_crc = crc32(data)
  for i = 0; i < 4; i = i + 1 {
    result.push(((block_crc >> (i * 8)) & 0xFFU).to_byte())
  }
  // Index
  let index_start = result.length()
  result.push(b'\x00') // indicator
  result.push(b'\x01') // 1 record
  encode_xz_varint(result, data.length().to_uint64())
  let unpadded_size = total_header_size + lzma_data.length()
  encode_xz_varint(result, unpadded_size.to_uint64())
  while (result.length() - index_start) % 4 != 0 {
    result.push(b'\x00')
  }
  let index_bytes_arr : Array[Byte] = []
  for i = index_start; i < result.length(); i = i + 1 {
    index_bytes_arr.push(result[i])
  }
  let index_bytes = Bytes::from_array(index_bytes_arr)
  let index_crc = crc32(index_bytes)
  for i = 0; i < 4; i = i + 1 {
    result.push(((index_crc >> (i * 8)) & 0xFFU).to_byte())
  }
  // Stream Footer
  // backward_size = (Index Field Size / 4) - 1, where Index Field Size includes CRC32
  let backward_size = ((result.length() - index_start) / 4 - 1).reinterpret_as_uint()
  let footer_data : Array[Byte] = []
  for i = 0; i < 4; i = i + 1 {
    footer_data.push(((backward_size >> (i * 8)) & 0xFFU).to_byte())
  }
  footer_data.push(b'\x00')
  footer_data.push(b'\x01')
  let footer_crc = crc32(Bytes::from_array(footer_data))
  for i = 0; i < 4; i = i + 1 {
    result.push(((footer_crc >> (i * 8)) & 0xFFU).to_byte())
  }
  for i = 0; i < footer_data.length(); i = i + 1 {
    result.push(footer_data[i])
  }
  result.push(b'Y')
  result.push(b'Z')
  Bytes::from_array(result)
}

///|
fn encode_xz_varint(out : Array[Byte], value_in : UInt64) -> Unit {
  let mut value = value_in
  while value >= 0x80UL {
    out.push((value & 0x7FUL).to_byte() | 0x80)
    value = value >> 7
  }
  out.push(value.to_byte())
}

///|
fn decode_xz_varint(data : Bytes, offset : Int) -> (UInt64, Int)? {
  let mut result = 0UL
  let mut shift = 0
  let mut pos = offset
  while pos < data.length() {
    let b = data[pos]
    result = result.lor((b & 0x7F).to_uint64() << shift)
    pos = pos + 1
    if (b & 0x80) == 0 {
      return Some((result, pos))
    }
    shift = shift + 7
    if shift >= 64 {
      return None
    }
  }
  None
}

///|
/// Decompress xz format data.
pub fn xz_decompress(data : Bytes) -> Bytes? {
  if data.length() < 12 {
    return None
  }
  // Check magic
  if data[0] != b'\xFD' ||
    data[1] != b'7' ||
    data[2] != b'z' ||
    data[3] != b'X' ||
    data[4] != b'Z' ||
    data[5] != b'\x00' {
    return None
  }
  // Check footer magic
  if data[data.length() - 2] != b'Y' || data[data.length() - 1] != b'Z' {
    return None
  }
  // Read backward size from footer
  let footer_start = data.length() - 12
  let mut backward_size = 0U
  for i = 0; i < 4; i = i + 1 {
    backward_size = backward_size.lor(
      data[footer_start + 4 + i].to_uint() << (i * 8),
    )
  }
  let index_size = (backward_size.reinterpret_as_int() + 1) * 4
  let idx_start = footer_start - index_size
  // Read index
  if idx_start < 12 || data[idx_start] != 0 {
    return None
  }
  match decode_xz_varint(data, idx_start + 1) {
    None => return None
    Some((num_records, np)) => {
      if num_records != 1UL {
        return None
      }
      match decode_xz_varint(data, np) {
        None => return None
        Some((_uncomp_size, np2)) =>
          match decode_xz_varint(data, np2) {
            None => return None
            Some((unpadded_size, _)) => {
              // Parse block header to find compressed data
              let mut pos = 12
              if pos >= data.length() {
                return None
              }
              let header_size = (data[pos].to_int() + 1) * 4
              pos = pos + header_size
              // Compressed data starts here — xz_compress stores the full
              // LZMA stream (props + usize + cache + range data), so we
              // pass it directly to decompress without any reconstruction.
              let comp_data_size = unpadded_size.to_int() - header_size
              if comp_data_size <= 0 || pos + comp_data_size > data.length() {
                return None
              }
              let lzma_data : Array[Byte] = []
              for i = 0; i < comp_data_size; i = i + 1 {
                lzma_data.push(data[pos + i])
              }
              return decompress(Bytes::from_array(lzma_data))
            }
          }
      }
    }
  }
  None
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "lzma: crc32 known vectors" {
  assert_eq(crc32(Bytes::from_array([])), 0U)
  let data = @utils.string_to_bytes("123456789")
  assert_eq(crc32(data), 0xCBF43926U)
}

///|
test "lzma: crc32 of 'a'" {
  let data = @utils.string_to_bytes("a")
  assert_eq(crc32(data), 0xE8B7BE43U)
}

///|
test "lzma: compress/decompress empty" {
  let data = Bytes::from_array([])
  let compressed = compress(data)
  match decompress(compressed) {
    None => assert_true(false)
    Some(decompressed) => assert_eq(decompressed.length(), 0)
  }
}

///|
test "lzma: compress/decompress single byte" {
  let data = Bytes::from_array([b'A'])
  let compressed = compress(data)
  match decompress(compressed) {
    None => assert_true(false)
    Some(decompressed) => {
      assert_eq(decompressed.length(), 1)
      assert_eq(decompressed[0], b'A')
    }
  }
}

///|
test "lzma: compress/decompress simple text" {
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
test "lzma: compress/decompress repetitive data" {
  let text = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  let data = @utils.string_to_bytes(text)
  let compressed = compress(data)
  assert_true(compressed.length() < data.length())
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
test "lzma: compress/decompress binary data" {
  let data = Bytes::from_array([
    b'\x00', b'\x01', b'\x02', b'\x03', b'\xFF', b'\xFE', b'\xFD', b'\xFC', b'\x00',
    b'\x01', b'\x02', b'\x03', b'\xFF', b'\xFE', b'\xFD', b'\xFC', b'\x00', b'\x01',
    b'\x02', b'\x03', b'\xFF', b'\xFE', b'\xFD', b'\xFC', b'\xAA', b'\xBB', b'\xCC',
    b'\xDD', b'\xEE', b'\xFF', b'\x00', b'\x11',
  ])
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
test "lzma: compress/decompress long text" {
  let parts : Array[String] = []
  for i = 0; i < 20; i = i + 1 {
    parts.push("The quick brown fox jumps over the lazy dog. ")
  }
  let text = parts.join("")
  let data = @utils.string_to_bytes(text)
  let compressed = compress(data)
  assert_true(compressed.length() < data.length())
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
test "lzma: distance slot calculation" {
  assert_eq(get_distance_slot(0), 0)
  assert_eq(get_distance_slot(1), 1)
  assert_eq(get_distance_slot(2), 2)
  assert_eq(get_distance_slot(3), 3)
  let slot4 = get_distance_slot(4)
  assert_true(slot4 == 4 || slot4 == 5)
}

///|
test "lzma: xz format structure validation" {
  let data = @utils.string_to_bytes(
    "Hello, xz format! This is a test of the xz compression container.",
  )
  let lzma = compress(data)
  let xz = xz_compress(data)
  // Block header at offset 12
  let header_size_byte = xz[12].to_int()
  let header_size = (header_size_byte + 1) * 4
  let comp_start = 12 + header_size
  // Verify LZMA data is stored intact in xz container
  assert_eq(xz[comp_start], lzma[0])
  for i = 0; i < lzma.length(); i = i + 1 {
    assert_eq(xz[comp_start + i], lzma[i])
  }
}

///|
test "lzma: xz compress/decompress roundtrip" {
  let data = @utils.string_to_bytes(
    "Hello, xz format! This is a test of the xz compression container.",
  )
  let compressed = xz_compress(data)
  match xz_decompress(compressed) {
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
test "lzma: xz magic bytes" {
  let data = @utils.string_to_bytes("test")
  let compressed = xz_compress(data)
  assert_eq(compressed[0], b'\xFD')
  assert_eq(compressed[1], b'7')
  assert_eq(compressed[2], b'z')
  assert_eq(compressed[3], b'X')
  assert_eq(compressed[4], b'Z')
  assert_eq(compressed[5], b'\x00')
}

///|
test "lzma: xz invalid magic returns None" {
  let data = Bytes::from_array([
    b'\x00', b'\x01', b'\x02', b'\x03', b'\x04', b'\x05', b'\x06', b'\x07', b'\x08',
    b'\x09', b'\x0A', b'\x0B',
  ])
  match xz_decompress(data) {
    None => assert_true(true)
    Some(_) => assert_true(false)
  }
}

///|
test "lzma: varint encode/decode" {
  let out : Array[Byte] = []
  encode_xz_varint(out, 1UL)
  match decode_xz_varint(Bytes::from_array(out), 0) {
    None => assert_true(false)
    Some((v, _)) => assert_eq(v, 1UL)
  }
  let out2 : Array[Byte] = []
  encode_xz_varint(out2, 128UL)
  match decode_xz_varint(Bytes::from_array(out2), 0) {
    None => assert_true(false)
    Some((v, _)) => assert_eq(v, 128UL)
  }
  let out3 : Array[Byte] = []
  encode_xz_varint(out3, 16384UL)
  match decode_xz_varint(Bytes::from_array(out3), 0) {
    None => assert_true(false)
    Some((v, _)) => assert_eq(v, 16384UL)
  }
}

///|
test "lzma: compress/decompress with matches" {
  let pattern = @utils.string_to_bytes(
    "ABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEF",
  )
  let prefix = @utils.string_to_bytes("XXXXX")
  let data : Array[Byte] = []
  for i = 0; i < prefix.length(); i = i + 1 {
    data.push(prefix[i])
  }
  for i = 0; i < pattern.length(); i = i + 1 {
    data.push(pattern[i])
  }
  for i = 0; i < pattern.length(); i = i + 1 {
    data.push(pattern[i])
  }
  let input = Bytes::from_array(data)
  let compressed = compress(input)
  match decompress(compressed) {
    None => assert_true(false)
    Some(decompressed) => {
      assert_eq(decompressed.length(), input.length())
      for i = 0; i < input.length(); i = i + 1 {
        assert_eq(decompressed[i], input[i])
      }
    }
  }
}
