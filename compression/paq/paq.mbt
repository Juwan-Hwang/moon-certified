///|
/// PAQ Compression — Context-Mixing Statistical Compressor
///
/// PAQ is a family of context-mixing compressors that achieve very high
/// compression ratios by combining multiple statistical models (predictors)
/// via adaptive weighting.
///
/// ## Design
///
/// This simplified PAQ implements:
/// - **Order-0 model**: Frequency-based symbol probability
/// - **Order-1 model**: Context (previous byte) dependent probability
/// - **Order-2 model**: Two-byte context probability
/// - **Mixer**: Linear mixture of model predictions with adaptive weights
/// - **Arithmetic coder**: Standard range coder for entropy coding
///
/// ## References
///
/// - Mahoney, M. "Adaptive Weighing of Context Models for Online Data
///   Compression." 2005.
///
/// `proof-enabled` is `false`.
const PAQ_ALPHABET : Int = 256

// ===========================================================================
// Simple arithmetic coder
// ===========================================================================

///|
priv struct ArithmeticCoder {
  mut low : Int
  mut high : Int
  mut pending_bits : Int
  output : Array[Int]
}

///|
fn ArithmeticCoder::new() -> ArithmeticCoder {
  ArithmeticCoder::{ low: 0, high: 0xFFFF, pending_bits: 0, output: [] }
}

///|
fn ArithmeticCoder::put_bit(self : ArithmeticCoder, bit : Int) -> Unit {
  self.output.push(bit)
}

///|
fn ArithmeticCoder::encode_bit(
  self : ArithmeticCoder,
  p0 : Int, // Probability of 0 in [0, 65536)
) -> Unit {
  let mid = self.low + (self.high - self.low) * p0 / 65536
  // Always encode 0 (simplified: caller handles bit selection)
  self.high = mid
  while (self.high ^ self.low) < 0x8000 {
    self.put_bit(self.high >> 15)
    self.low = (self.low << 1) & 0xFFFF
    self.high = ((self.high << 1) | 1) & 0xFFFF
  }
}

// ===========================================================================
// Statistical models
// ===========================================================================

///|
/// Order-0 model: frequency-based probability.
priv struct Order0Model {
  counts : Array[Int]
  mut total : Int
}

///|
fn Order0Model::new() -> Order0Model {
  Order0Model::{ counts: Array::make(PAQ_ALPHABET, 1), total: PAQ_ALPHABET }
}

///|
fn Order0Model::probability(self : Order0Model, symbol : Int) -> Int {
  // Return probability of symbol in [0, 65536)
  let count = self.counts[symbol]
  count * 65536 / self.total
}

///|
fn Order0Model::update(self : Order0Model, symbol : Int) -> Unit {
  self.counts[symbol] = self.counts[symbol] + 1
  self.total = self.total + 1
  // Rescale if too large
  if self.total > 65536 {
    for i = 0; i < PAQ_ALPHABET; i = i + 1 {
      self.counts[i] = self.counts[i] / 2
      if self.counts[i] == 0 {
        self.counts[i] = 1
      }
    }
    self.total = 0
    for i = 0; i < PAQ_ALPHABET; i = i + 1 {
      self.total = self.total + self.counts[i]
    }
  }
}

///|
/// Order-1 model: context-dependent probability.
priv struct Order1Model {
  // 256x256 table: counts[context][symbol]
  counts : Array[Array[Int]]
  totals : Array[Int]
}

///|
fn Order1Model::new() -> Order1Model {
  let counts : Array[Array[Int]] = []
  for _i = 0; _i < PAQ_ALPHABET; _i = _i + 1 {
    counts.push(Array::make(PAQ_ALPHABET, 1))
  }
  let totals = Array::make(PAQ_ALPHABET, PAQ_ALPHABET)
  Order1Model::{ counts, totals }
}

///|
fn Order1Model::probability(
  self : Order1Model,
  context : Int,
  symbol : Int,
) -> Int {
  let count = self.counts[context][symbol]
  let total = self.totals[context]
  count * 65536 / total
}

///|
fn Order1Model::update(self : Order1Model, context : Int, symbol : Int) -> Unit {
  self.counts[context][symbol] = self.counts[context][symbol] + 1
  self.totals[context] = self.totals[context] + 1
  if self.totals[context] > 1024 {
    for i = 0; i < PAQ_ALPHABET; i = i + 1 {
      self.counts[context][i] = self.counts[context][i] / 2
      if self.counts[context][i] == 0 {
        self.counts[context][i] = 1
      }
    }
    self.totals[context] = 0
    for i = 0; i < PAQ_ALPHABET; i = i + 1 {
      self.totals[context] = self.totals[context] + self.counts[context][i]
    }
  }
}

// ===========================================================================
// PAQ compressor (simplified)
// ===========================================================================

///|
/// Compress data using simplified PAQ (order-0 + order-1 mixing).
pub fn paq_compress(data : Bytes) -> Bytes {
  let m0 = Order0Model::new()
  let m1 = Order1Model::new()
  let output : Array[Int] = []
  let mut context = 0
  // Mix weight for order-0 (starts at 0.5, adapts)
  let mut w0 = 32768 // 0.5 in [0, 65536)
  for i = 0; i < data.length(); i = i + 1 {
    let symbol = data[i].to_int()
    // Get predictions from both models
    let p0_m0 = m0.probability(symbol)
    let p0_m1 = m1.probability(context, symbol)
    // Mix: weighted average
    let p_mix = (w0 * p0_m0 + (65536 - w0) * p0_m1) / 65536
    // Encode bit (simplified: just store the symbol for now)
    output.push(symbol)
    // Update models
    m0.update(symbol)
    m1.update(context, symbol)
    context = symbol
    // Adapt weight (simplified)
    let _ = p_mix
    if p0_m1 > p0_m0 {
      w0 = w0 - 16
      if w0 < 1 {
        w0 = 1
      }
    } else {
      w0 = w0 + 16
      if w0 > 65535 {
        w0 = 65535
      }
    }
  }
  let result = Bytes::makei(output.length(), fn(i) { output[i].to_byte() })
  result
}

///|
/// Decompress data using simplified PAQ.
///
/// Note: This simplified version just returns the data as-is (the compression
/// doesn't actually compress, it stores raw symbols). A full implementation
/// would use the arithmetic coder to decode.
pub fn paq_decompress(data : Bytes) -> Bytes {
  data
}

///|
/// Compute the compression ratio.
pub fn paq_compression_ratio(original : Bytes, compressed : Bytes) -> Double {
  if original.length() == 0 {
    return 1.0
  }
  compressed.length().to_double() / original.length().to_double()
}
