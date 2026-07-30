/// Arithmetic Coding — a high-entropy entropy encoding technique.
///
/// Arithmetic coding achieves compression rates arbitrarily close to the
/// Shannon entropy of the source, outperforming Huffman coding which is
/// limited to 1 bit per symbol of overhead.
///
/// ## Algorithm
///
/// Uses 32-bit integer arithmetic with renormalisation, following the
/// classic Witten-Neal-Cleary (WNC) implementation (CACM 1987). The
/// interval [low, high] is narrowed with each symbol. Renormalisation
/// shifts out matching top bits and handles the straddle (underflow) case
/// by subtracting QUARTER and deferring output via pending bits.
///
/// ## Frequency Model
///
/// Uses an adaptive order-0 frequency model with 257 symbols (0-255 byte
/// values plus an end-of-stream marker). Both encoder and decoder start
/// with a uniform distribution (frequency 1 per symbol) and update
/// identically after each symbol, ensuring perfect synchronisation
/// without transmitting the model.
///
/// ## Complexity
///
/// - `compress`: O(n × σ) where n = data.length(), σ = 257 (model update).
/// - `decompress`: O(n × σ) output size.
/// - Space: O(σ) for the frequency table, σ = 257.
///
/// ## References
///
/// - Witten, Neal, Cleary (1987): "Arithmetic Coding for Data Compression"
/// - Bell, Cleary, Witten (1990): "Text Compression", Chapter 5
///
/// Not formally verified. Correctness is ensured by the test suite.

// ---------------------------------------------------------------------------
// Constants (WNC precision parameters)
// ---------------------------------------------------------------------------

///|
/// Number of symbols: 256 byte values + 1 EOF marker.
const NUM_SYMBOLS : Int = 257

///|
/// EOF symbol value (the 257th symbol, index 256).
const EOF_SYMBOL : Int = 256

///|
/// Number of bits of precision for the code range.
const CODE_BITS : Int = 32

///|
/// Top of the code range: 2^31.
const HALF : UInt = 0x80000000U

///|
/// Quarter of the code range: 2^30.
const QUARTER : UInt = 0x40000000U

///|
/// Three-quarters of the code range: 3 × 2^30.
const THREE_QUARTER : UInt = 0xC0000000U

// ---------------------------------------------------------------------------
// Frequency model
// ---------------------------------------------------------------------------

///|
/// Cumulative frequency model for arithmetic coding.
priv struct FreqModel {
  freq : Array[Int]
  cum : Array[Int]
  mut total : Int
}

///|
/// Build an adaptive frequency model (uniform initial distribution).
fn new_model() -> FreqModel {
  let freq = Array::make(NUM_SYMBOLS, 1)
  let cum = Array::make(NUM_SYMBOLS + 1, 0)
  let mut total = 0
  for i = 0; i < NUM_SYMBOLS; i = i + 1 {
    cum[i] = total
    total = total + freq[i]
  }
  cum[NUM_SYMBOLS] = total
  { freq, cum, total }
}

///|
/// Update the frequency model after encoding/decoding a symbol.
fn update_model(model : FreqModel, sym : Int) -> Unit {
  model.freq[sym] = model.freq[sym] + 1
  model.total = model.total + 1
  let mut t = 0
  for i = 0; i < NUM_SYMBOLS; i = i + 1 {
    model.cum[i] = t
    t = t + model.freq[i]
  }
  model.cum[NUM_SYMBOLS] = t
}

// ---------------------------------------------------------------------------
// Bit I/O
// ---------------------------------------------------------------------------

///|
/// Bit-by-bit output writer.
priv struct BitWriter {
  buffer : Array[Byte]
  mut current : UInt
  mut bit_count : Int
}

///|
fn new_writer() -> BitWriter {
  { buffer: [], current: 0U, bit_count: 0 }
}

///|
fn write_bit(w : BitWriter, bit : UInt) -> Unit {
  w.current = (w.current << 1) | (bit & 1U)
  w.bit_count = w.bit_count + 1
  if w.bit_count == 8 {
    w.buffer.push(w.current.to_byte())
    w.current = 0U
    w.bit_count = 0
  }
}

///|
fn flush_writer(w : BitWriter) -> Unit {
  if w.bit_count > 0 {
    w.current = w.current << (8 - w.bit_count)
    w.buffer.push(w.current.to_byte())
    w.current = 0U
    w.bit_count = 0
  }
}

///|
/// Bit-by-bit input reader.
priv struct BitReader {
  data : Bytes
  mut pos : Int
  mut current : UInt
  mut bit_count : Int
}

///|
fn new_reader(data : Bytes) -> BitReader {
  { data, pos: 0, current: 0U, bit_count: 0 }
}

///|
fn read_bit(r : BitReader) -> UInt {
  if r.bit_count == 0 {
    if r.pos < r.data.length() {
      r.current = r.data[r.pos].to_uint()
      r.pos = r.pos + 1
      r.bit_count = 8
    } else {
      r.current = 0U
      r.bit_count = 8
    }
  }
  r.bit_count = r.bit_count - 1
  (r.current >> r.bit_count) & 1U
}

// ---------------------------------------------------------------------------
// Encoder state (mutable struct for passing to helpers)
// ---------------------------------------------------------------------------

///|
/// Mutable encoder state: interval [low, high] plus pending bits.
priv struct EncState {
  writer : BitWriter
  mut low : UInt
  mut high : UInt
  mut pending : Int
}

// ---------------------------------------------------------------------------
// Arithmetic encoder
// ---------------------------------------------------------------------------

///|
/// Compress `data` using arithmetic coding with an adaptive model.
///
/// Returns the compressed byte array. The first 4 bytes are the original
/// length (big-endian), followed by the arithmetic-coded bitstream.
pub fn compress(data : Bytes) -> Bytes {
  let model = new_model()
  let st : EncState = {
    writer: new_writer(),
    low: 0U,
    high: 0xFFFFFFFFU,
    pending: 0
  }
  // Encode each data byte
  for i = 0; i < data.length(); i = i + 1 {
    let sym = data[i].to_int()
    encode_symbol(st, model, sym)
    update_model(model, sym)
  }
  // Encode EOF symbol
  encode_symbol(st, model, EOF_SYMBOL)
  // Flush: output one final bit to resolve any pending straddle
  st.pending = st.pending + 1
  if st.low < QUARTER {
    output_bit(st, 0U)
  } else {
    output_bit(st, 1U)
  }
  flush_writer(st.writer)
  // Prepend 4-byte original length
  let len = data.length()
  let result : Array[Byte] = []
  result.push(((len >> 24) & 0xFF).to_byte())
  result.push(((len >> 16) & 0xFF).to_byte())
  result.push(((len >> 8) & 0xFF).to_byte())
  result.push((len & 0xFF).to_byte())
  for i = 0; i < st.writer.buffer.length(); i = i + 1 {
    result.push(st.writer.buffer[i])
  }
  Bytes::from_array(result)
}

///|
/// Output a bit followed by all pending complement bits.
fn output_bit(st : EncState, bit : UInt) -> Unit {
  write_bit(st.writer, bit)
  while st.pending > 0 {
    write_bit(st.writer, bit ^ 1U)
    st.pending = st.pending - 1
  }
}

///|
/// Encode a single symbol using the WNC arithmetic coding algorithm.
fn encode_symbol(st : EncState, model : FreqModel, sym : Int) -> Unit {
  // Narrow the interval [low, high] to the symbol's subrange.
  // Use UInt64 for intermediate multiplication to avoid 32-bit overflow.
  let range = (st.high - st.low).to_uint64() + 1UL
  let total = model.total.to_uint64()
  let new_high = st.low.to_uint64() +
    (range * model.cum[sym + 1].to_uint64()) / total - 1UL
  let new_low = st.low.to_uint64() +
    (range * model.cum[sym].to_uint64()) / total
  st.high = new_high.to_uint()
  st.low = new_low.to_uint()
  // Renormalise (WNC algorithm)
  let mut done = false
  while !done {
    if st.high < HALF {
      // Both top bits are 0: output 0, shift
      output_bit(st, 0U)
      st.low = st.low << 1
      st.high = (st.high << 1) | 1U
    } else if st.low >= HALF {
      // Both top bits are 1: output 1, subtract HALF, shift
      output_bit(st, 1U)
      st.low = (st.low - HALF) << 1
      st.high = ((st.high - HALF) << 1) | 1U
    } else if st.low >= QUARTER && st.high < THREE_QUARTER {
      // Straddle: subtract QUARTER, defer output, shift
      st.pending = st.pending + 1
      st.low = (st.low - QUARTER) << 1
      st.high = ((st.high - QUARTER) << 1) | 1U
    } else {
      done = true
    }
  }
}

// ---------------------------------------------------------------------------
// Arithmetic decoder
// ---------------------------------------------------------------------------

///|
/// Decompress arithmetic-coded data.
///
/// Returns the original byte array, or `None` if the data is corrupt.
pub fn decompress(data : Bytes) -> Bytes? {
  if data.length() < 4 {
    return None
  }
  let orig_len = (data[0].to_int() << 24) |
    (data[1].to_int() << 16) |
    (data[2].to_int() << 8) |
    data[3].to_int()
  if orig_len < 0 {
    return None
  }
  let reader = new_reader(Bytes::from_array({
    let arr : Array[Byte] = []
    for i = 4; i < data.length(); i = i + 1 {
      arr.push(data[i])
    }
    arr
  }))
  let model = new_model()
  let mut low : UInt = 0U
  let mut high : UInt = 0xFFFFFFFFU
  let mut code : UInt = 0U
  // Read initial 32 bits
  for _i = 0; _i < CODE_BITS; _i = _i + 1 {
    code = (code << 1) | read_bit(reader)
  }
  let result : Array[Byte] = []
  let mut count = 0
  while count < orig_len {
    // Compute current value and find the matching symbol
    let range = (high - low).to_uint64() + 1UL
    let total = model.total.to_uint64()
    let value = (((code - low + 1U).to_uint64()) * total - 1UL) / range
    // Binary search for the symbol
    let mut lo_idx = 0
    let mut hi_idx = NUM_SYMBOLS
    while lo_idx < hi_idx {
      let mid = (lo_idx + hi_idx) / 2
      if model.cum[mid + 1].to_uint64() <= value {
        lo_idx = mid + 1
      } else {
        hi_idx = mid
      }
    }
    let sym = lo_idx
    if sym == EOF_SYMBOL {
      break
    }
    if sym >= 256 {
      return None
    }
    result.push(sym.to_byte())
    count = count + 1
    // Narrow the interval (same as encoder)
    let new_high = low.to_uint64() +
      (range * model.cum[sym + 1].to_uint64()) / total - 1UL
    let new_low = low.to_uint64() +
      (range * model.cum[sym].to_uint64()) / total
    high = new_high.to_uint()
    low = new_low.to_uint()
    // Renormalise (must match encoder exactly)
    let mut done = false
    while !done {
      if high < HALF {
        low = low << 1
        high = (high << 1) | 1U
        code = (code << 1) | read_bit(reader)
      } else if low >= HALF {
        low = (low - HALF) << 1
        high = ((high - HALF) << 1) | 1U
        code = ((code - HALF) << 1) | read_bit(reader)
      } else if low >= QUARTER && high < THREE_QUARTER {
        low = (low - QUARTER) << 1
        high = ((high - QUARTER) << 1) | 1U
        code = ((code - QUARTER) << 1) | read_bit(reader)
      } else {
        done = true
      }
    }
    // Update adaptive model (must match encoder exactly)
    update_model(model, sym)
  }
  Some(Bytes::from_array(result))
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "arithmetic: round-trip simple text" {
  let data = @utils.string_to_bytes("hello world")
  let compressed = compress(data)
  let decompressed = match decompress(compressed) {
    None => fail("decompression failed")
    Some(d) => d
  }
  assert_eq(decompressed.length(), data.length())
  for i = 0; i < data.length(); i = i + 1 {
    assert_eq(decompressed[i], data[i])
  }
}

///|
test "arithmetic: round-trip repetitive data" {
  let data = @utils.string_to_bytes("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
  let compressed = compress(data)
  assert_true(compressed.length() < data.length())
  let decompressed = match decompress(compressed) {
    None => fail("decompression failed")
    Some(d) => d
  }
  assert_eq(decompressed.length(), data.length())
  for i = 0; i < data.length(); i = i + 1 {
    assert_eq(decompressed[i], data[i])
  }
}

///|
test "arithmetic: round-trip empty data" {
  let data = Bytes::make(0, b'\x00')
  let compressed = compress(data)
  let decompressed = match decompress(compressed) {
    None => fail("decompression failed")
    Some(d) => d
  }
  assert_eq(decompressed.length(), 0)
}

///|
test "arithmetic: round-trip binary data" {
  let data : Array[Byte] = []
  for i = 0; i < 256; i = i + 1 {
    data.push(i.to_byte())
  }
  let bytes = Bytes::from_array(data)
  let compressed = compress(bytes)
  let decompressed = match decompress(compressed) {
    None => fail("decompression failed")
    Some(d) => d
  }
  assert_eq(decompressed.length(), bytes.length())
  for i = 0; i < bytes.length(); i = i + 1 {
    assert_eq(decompressed[i], bytes[i])
  }
}

///|
test "arithmetic: round-trip random-looking data" {
  let data = @utils.string_to_bytes("The quick brown fox jumps over the lazy dog. 1234567890!")
  let compressed = compress(data)
  let decompressed = match decompress(compressed) {
    None => fail("decompression failed")
    Some(d) => d
  }
  assert_eq(decompressed.length(), data.length())
  for i = 0; i < data.length(); i = i + 1 {
    assert_eq(decompressed[i], data[i])
  }
}
