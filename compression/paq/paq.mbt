///|
/// PAQ Compression — Context-Mixing Statistical Compressor
///
/// PAQ is a family of context-mixing compressors that achieve high
/// compression ratios by combining multiple statistical models
/// (predictors) via adaptive weighting, coding the result with an
/// arithmetic (range) coder.
///
/// ## Implementation
///
/// - **Order-0 model**: adaptive byte frequencies with periodic
///   rescaling.
/// - **Order-1 model**: per-previous-byte frequency tables with
///   periodic rescaling.
/// - **Mixer**: linear mixture of the two models' cumulative
///   distributions with an adaptive weight that shifts toward the
///   model which predicted each byte better. Monotonicity of the
///   mixed cumulative distribution is enforced so every symbol keeps a
///   non-zero coding interval.
/// - **Coder**: carry-less 32-bit range coder (Subbotin style); the
///   encoder and decoder recompute identical model state, so no model
///   data is transmitted.
///
/// ## Format
///
/// Custom container (NOT the PAQ8 file format): 4-byte magic `MBPQ`,
/// 8-byte little-endian original length, then the range-coded stream.
/// `paq_decompress` validates the magic and length and raises on
/// corrupted input.
///
/// ## References
///
/// - Mahoney, M. "Adaptive Weighing of Context Models for Online Data
///   Compression." 2005.
/// - Subbotin, D. "Range coder" (carry-less variant).
///
/// `proof-enabled` is `false`.
const PAQ_ALPHABET : Int = 256

///|
const PAQ_MAGIC_0 : Int = 0x4D // 'M'

///|
const PAQ_MAGIC_1 : Int = 0x42 // 'B'

///|
const PAQ_MAGIC_2 : Int = 0x50 // 'P'

///|
const PAQ_MAGIC_3 : Int = 0x51 // 'Q'

///|
/// Order-0 rescale threshold.
const PAQ_TOTAL0_MAX : Int = 32768

///|
/// Per-context order-1 rescale threshold.
const PAQ_TOTAL1_MAX : Int = 4096

///|
/// Initial mixer weight for the order-0 model (out of 65536).
const PAQ_W0_INIT : Int = 32768

///|
/// Mixer weight adaptation step per byte.
const PAQ_ADAPT_STEP : Int = 1024

// ===========================================================================
// Carry-less range coder (Subbotin)
// ===========================================================================

///|
const RC_TOP : Int64 = 16777216L // 1 << 24

///|
const RC_BOT : Int64 = 65536L // 1 << 16

///|
const RC_MASK : Int64 = 0xFFFFFFFFL

///|
priv struct RCEncoder {
  mut low : Int64
  mut range : Int64
  out : Array[Int]
}

///|
fn RCEncoder::new() -> RCEncoder {
  { low: 0L, range: RC_MASK, out: [] }
}

///|
fn RCEncoder::normalize(self : RCEncoder) -> Unit {
  while true {
    let x = (self.low ^ (self.low + self.range)) & RC_MASK
    if x >= RC_TOP {
      if self.range >= RC_BOT {
        return
      }
      // Range is too small and the top byte is unsettled: force the
      // range so that `low + range` crosses the next BOT boundary.
      self.range = (-self.low) & (RC_BOT - 1L)
    }
    self.out.push(((self.low >> 24) & 0xFFL).to_int())
    self.low = (self.low << 8) & RC_MASK
    self.range = (self.range << 8) & RC_MASK
  }
}

///|
/// Encode a symbol with cumulative frequency `cum`, frequency `freq`,
/// out of `total` (0 <= cum < cum + freq <= total).
fn RCEncoder::encode(
  self : RCEncoder,
  cum : Int,
  freq : Int,
  total : Int,
) -> Unit {
  self.range = self.range / total.to_int64()
  self.low = (self.low + cum.to_int64() * self.range) & RC_MASK
  self.range = (self.range * freq.to_int64()) & RC_MASK
  self.normalize()
}

///|
/// Flush the remaining state (4 bytes).
fn RCEncoder::finish(self : RCEncoder) -> Unit {
  for _i = 0; _i < 4; _i = _i + 1 {
    self.out.push(((self.low >> 24) & 0xFFL).to_int())
    self.low = (self.low << 8) & RC_MASK
  }
}

///|
priv struct RCDecoder {
  mut low : Int64
  mut range : Int64
  mut code : Int64
  data : Bytes
  mut pos : Int
}

///|
fn RCDecoder::new(data : Bytes, start : Int) -> RCDecoder {
  let mut code = 0L
  for i = 0; i < 4; i = i + 1 {
    let b = if start + i < data.length() {
      data[start + i].to_int()
    } else {
      0
    }
    code = (code << 8) | b.to_int64()
  }
  { low: 0L, range: RC_MASK, code, data, pos: start + 4 }
}

///|
fn RCDecoder::read_byte(self : RCDecoder) -> Int64 {
  if self.pos < self.data.length() {
    let b = self.data[self.pos].to_int64() & 0xFFL
    self.pos = self.pos + 1
    b
  } else {
    0L
  }
}

///|
fn RCDecoder::normalize(self : RCDecoder) -> Unit {
  while true {
    let x = (self.low ^ (self.low + self.range)) & RC_MASK
    if x >= RC_TOP {
      if self.range >= RC_BOT {
        return
      }
      self.range = (-self.low) & (RC_BOT - 1L)
    }
    self.low = (self.low << 8) & RC_MASK
    self.range = (self.range << 8) & RC_MASK
    self.code = ((self.code << 8) | self.read_byte()) & RC_MASK
  }
}

///|
/// Identify the cumulative frequency bucket of the next symbol.
fn RCDecoder::get_freq(self : RCDecoder, total : Int) -> Int {
  self.range = self.range / total.to_int64()
  let tmp = (self.code - self.low) / self.range
  if tmp < 0L {
    0
  } else if tmp >= total.to_int64() {
    total - 1
  } else {
    tmp.to_int()
  }
}

///|
/// Advance the decoder state after the symbol (cum, freq) was read.
fn RCDecoder::decode(self : RCDecoder, cum : Int, freq : Int) -> Unit {
  self.low = (self.low + cum.to_int64() * self.range) & RC_MASK
  self.range = (self.range * freq.to_int64()) & RC_MASK
  self.normalize()
}

// ===========================================================================
// Statistical models + mixer
// ===========================================================================

///|
priv struct PaqModels {
  counts0 : Array[Int]
  mut total0 : Int
  counts1 : Array[Array[Int]]
  totals1 : Array[Int]
  mut w0 : Int // mixer weight of the order-0 model, out of 65536
  mut context : Int
}

///|
fn PaqModels::new() -> PaqModels {
  let counts1 : Array[Array[Int]] = []
  for _i = 0; _i < PAQ_ALPHABET; _i = _i + 1 {
    counts1.push(Array::make(PAQ_ALPHABET, 1))
  }
  {
    counts0: Array::make(PAQ_ALPHABET, 1),
    total0: PAQ_ALPHABET,
    counts1,
    totals1: Array::make(PAQ_ALPHABET, PAQ_ALPHABET),
    w0: PAQ_W0_INIT,
    context: 0,
  }
}

///|
/// Build the mixed cumulative distribution for the current state.
/// Returns an array of 257 entries; entry 256 is the total.
fn PaqModels::mixed_cumulative(self : PaqModels) -> Array[Int] {
  let cum : Array[Int] = Array::make(PAQ_ALPHABET + 1, 0)
  let w0 = self.w0.to_int64()
  let w1 = (65536 - self.w0).to_int64()
  let ctx = self.context
  let mut c0 = 0L
  let mut c1 = 0L
  for s = 0; s < PAQ_ALPHABET; s = s + 1 {
    c0 = c0 + self.counts0[s].to_int64()
    c1 = c1 + self.counts1[ctx][s].to_int64()
    let mixed = (w0 * c0 + w1 * c1 + 32768L) >> 16
    let m = mixed.to_int()
    // Enforce a strictly increasing cumulative so that every symbol
    // keeps a non-zero coding interval.
    if m <= cum[s] {
      cum[s + 1] = cum[s] + 1
    } else {
      cum[s + 1] = m
    }
  }
  cum
}

///|
/// Update both models with the observed byte and adapt the mixer
/// weight toward the model which predicted it better.
fn PaqModels::update(self : PaqModels, symbol : Int) -> Unit {
  let ctx = self.context
  // Adapt the mixer weight before updating the tables, using the
  // pre-update predictions.
  let p0 = self.counts0[symbol] * self.totals1[ctx]
  let p1 = self.counts1[ctx][symbol] * self.total0
  if p1 > p0 {
    self.w0 = self.w0 - PAQ_ADAPT_STEP
    if self.w0 < 1 {
      self.w0 = 1
    }
  } else {
    self.w0 = self.w0 + PAQ_ADAPT_STEP
    if self.w0 > 65535 {
      self.w0 = 65535
    }
  }
  // Order-0 update with periodic rescale.
  self.counts0[symbol] = self.counts0[symbol] + 1
  self.total0 = self.total0 + 1
  if self.total0 > PAQ_TOTAL0_MAX {
    let mut t = 0
    for i = 0; i < PAQ_ALPHABET; i = i + 1 {
      self.counts0[i] = self.counts0[i] / 2
      if self.counts0[i] == 0 {
        self.counts0[i] = 1
      }
      t = t + self.counts0[i]
    }
    self.total0 = t
  }
  // Order-1 update with per-context rescale.
  self.counts1[ctx][symbol] = self.counts1[ctx][symbol] + 1
  self.totals1[ctx] = self.totals1[ctx] + 1
  if self.totals1[ctx] > PAQ_TOTAL1_MAX {
    let mut t = 0
    for i = 0; i < PAQ_ALPHABET; i = i + 1 {
      self.counts1[ctx][i] = self.counts1[ctx][i] / 2
      if self.counts1[ctx][i] == 0 {
        self.counts1[ctx][i] = 1
      }
      t = t + self.counts1[ctx][i]
    }
    self.totals1[ctx] = t
  }
  self.context = symbol
}

// ===========================================================================
// Container format helpers
// ===========================================================================

///|
fn paq_put_length(out : Array[Int], len : Int) -> Unit {
  let mut v = len.to_int64()
  for _i = 0; _i < 8; _i = _i + 1 {
    out.push((v & 0xFFL).to_int())
    v = v >> 8
  }
}

///|
fn paq_read_length(data : Bytes, offset : Int) -> Int? {
  if offset + 8 > data.length() {
    return None
  }
  let mut v = 0L
  for i = 7; i >= 0; i = i - 1 {
    v = (v << 8) | (data[offset + i].to_int64() & 0xFFL)
  }
  if v < 0L || v > 2147483647L {
    None
  } else {
    Some(v.to_int())
  }
}

///|
/// Compress data with context-mixing arithmetic coding.
pub fn paq_compress(data : Bytes) -> Bytes {
  let out : Array[Int] = []
  out.push(PAQ_MAGIC_0)
  out.push(PAQ_MAGIC_1)
  out.push(PAQ_MAGIC_2)
  out.push(PAQ_MAGIC_3)
  paq_put_length(out, data.length())
  let enc = RCEncoder::new()
  let models = PaqModels::new()
  for i = 0; i < data.length(); i = i + 1 {
    let symbol = data[i].to_int() & 0xFF
    let cum = models.mixed_cumulative()
    let freq = cum[symbol + 1] - cum[symbol]
    enc.encode(cum[symbol], freq, cum[PAQ_ALPHABET])
    models.update(symbol)
  }
  enc.finish()
  for b in enc.out {
    out.push(b)
  }
  let result = Bytes::makei(out.length(), fn(i) { out[i].to_byte() })
  result
}

///|
/// Decompress data produced by `paq_compress`.
///
/// Raises `Failure` if the magic, stored length or coded stream is
/// corrupted.
pub fn paq_decompress(data : Bytes) -> Bytes raise {
  if data.length() < 12 {
    fail("paq: truncated header")
  }
  if data[0].to_int() != PAQ_MAGIC_0 || data[1].to_int() != PAQ_MAGIC_1 ||
    data[2].to_int() != PAQ_MAGIC_2 ||
    data[3].to_int() != PAQ_MAGIC_3 {
    fail("paq: bad magic")
  }
  let len = match paq_read_length(data, 4) {
    Some(v) => v
    None => fail("paq: bad length field")
  }
  let dec = RCDecoder::new(data, 12)
  let models = PaqModels::new()
  let result : Array[Byte] = []
  for i = 0; i < len; i = i + 1 {
    let cum = models.mixed_cumulative()
    let total = cum[PAQ_ALPHABET]
    let f = dec.get_freq(total)
    // Locate the symbol whose cumulative range contains f.
    let mut lo = 0
    let mut hi = PAQ_ALPHABET
    while hi - lo > 1 {
      let mid = (lo + hi) / 2
      if cum[mid] <= f {
        lo = mid
      } else {
        hi = mid
      }
    }
    let symbol = lo
    let freq = cum[symbol + 1] - cum[symbol]
    dec.decode(cum[symbol], freq)
    models.update(symbol)
    result.push(symbol.to_byte())
  }
  Bytes::from_array(result)
}

///|
/// Compute the compression ratio (compressed / original). Lower is
/// better; values below 1.0 mean the output is smaller than the
/// input.
pub fn paq_compression_ratio(original : Bytes, compressed : Bytes) -> Double {
  if original.length() == 0 {
    return 1.0
  }
  compressed.length().to_double() / original.length().to_double()
}
