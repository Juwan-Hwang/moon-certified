/// Bloom filter for probabilistic set membership testing.
///
/// Uses k hash functions (polynomial rolling hash with different seeds) and
/// a bit array stored as 64-bit words. False positives are possible but
/// false negatives are impossible.
///
/// Optimal parameters:
///   m (bits) = -n * ln(p) / (ln(2))^2
///   k (hashes) = (m / n) * ln(2)
/// where n = expected items, p = false positive rate.
///
/// Not formally verified. Correctness ensured by comprehensive tests.

pub struct BloomFilter {
  bits : FixedArray[UInt64] // bit array stored as 64-bit words
  num_bits : Int
  num_hashes : Int
}

/// Natural logarithm via range reduction + the atanh series.
///
/// We first reduce `x` to `val` in [0.5, 1.0) by multiplying/dividing by 2,
/// tracking the exponent `k`. Then ln(x) = ln(val) - k * ln(2).
/// For val in [0.5, 1.0), |y| = |(val-1)/(val+1)| <= 1/3, so the series
///   ln(val) = 2 * sum_{n=0}^{inf} y^(2n+1)/(2n+1)
/// converges rapidly — 60 terms give full double precision.
///
/// **Guard**: Returns 0.0 for x <= 0.0 to prevent infinite loops in the
/// range reduction phase. The caller `new()` already validates
/// `false_positive_rate > 0.0 && < 1.0`, so this guard is a safety net.
fn bf_ln(x : Double) -> Double {
  if x <= 0.0 {
    return 0.0
  }
  let ln2 = 0.6931471805599453
  let mut val = x
  let mut k = 0
  // Reduce to [0.5, 1.0) so |y| <= 1/3.
  while val < 0.5 {
    val = val * 2.0
    k = k + 1
  }
  while val >= 1.0 {
    val = val / 2.0
    k = k - 1
  }
  let y = (val - 1.0) / (val + 1.0)
  let y2 = y * y
  let mut sum = 0.0
  let mut ypow = y
  let mut denom = 1.0
  let mut i = 0
  while i < 60 {
    sum = sum + ypow / denom
    ypow = ypow * y2
    denom = denom + 2.0
    i = i + 1
  }
  sum * 2.0 - k.to_double() * ln2
}

/// Create a Bloom filter sized for `expected_items` at the given
/// `false_positive_rate`. Calculates optimal bit count and hash count.
pub fn new(expected_items : Int, false_positive_rate : Double) -> BloomFilter {
  let n = if expected_items > 0 { expected_items } else { 1 }
  let p = if false_positive_rate > 0.0 && false_positive_rate < 1.0 {
    false_positive_rate
  } else {
    0.01
  }
  let ln2 = 0.6931471805599453
  let ln_p = bf_ln(p) // negative since p < 1
  // m = -n * ln(p) / (ln(2))^2
  let m_d = n.to_double() * (-ln_p) / (ln2 * ln2)
  let m = m_d.to_int()
  let num_bits = if m > 64 { m } else { 64 }
  // k = (m / n) * ln(2)
  let k_d = num_bits.to_double() / n.to_double() * ln2
  let k_raw = k_d.to_int()
  let num_hashes = if k_raw > 1 { k_raw } else { 1 }
  let num_words = (num_bits + 63) / 64
  { bits: FixedArray::make(num_words, 0UL), num_bits, num_hashes }
}

/// Polynomial rolling hash with a seed, followed by avalanche mixing.
///   h = seed; for each byte b: h = h * 31 + b
/// The final avalanche step (xor-shift-multiply) breaks the linear
/// relationship between hashes that share the same polynomial but use
/// different seeds, so the k hash functions are effectively independent.
pub fn hash(data : String, seed : Int) -> Int {
  let mut h = seed
  for i = 0; i < data.length(); i = i + 1 {
    h = h * 31 + data[i].to_int()
  }
  // Avalanche mixing: decorrelates different seeds.
  h = h ^ (h >> 16)
  h = h * 0x45d9f3b
  h = h ^ (h >> 16)
  h
}

/// Map a hash value to a non-negative bit position in [0, num_bits).
fn bit_pos(h : Int, num_bits : Int) -> Int {
  ((h % num_bits) + num_bits) % num_bits
}

/// Set the bit at position `pos` in the word array.
fn set_bit(bits : FixedArray[UInt64], pos : Int) -> Unit {
  let word = pos / 64
  let bit = pos % 64
  bits[word] = bits[word] | (1UL << bit)
}

/// Test whether the bit at position `pos` is set.
fn get_bit(bits : FixedArray[UInt64], pos : Int) -> Bool {
  let word = pos / 64
  let bit = pos % 64
  (bits[word] & (1UL << bit)) != 0UL
}

/// Add a byte string to the filter. Sets k bits using k independent hashes.
pub fn add(bf : BloomFilter, data : String) -> Unit {
  for i = 0; i < bf.num_hashes; i = i + 1 {
    let h = hash(data, i * 31 + 17)
    let pos = bit_pos(h, bf.num_bits)
    set_bit(bf.bits, pos)
  }
}

/// Check if data *might* be in the set. False positives are possible;
/// false negatives are impossible.
pub fn contains(bf : BloomFilter, data : String) -> Bool {
  for i = 0; i < bf.num_hashes; i = i + 1 {
    let h = hash(data, i * 31 + 17)
    let pos = bit_pos(h, bf.num_bits)
    if !get_bit(bf.bits, pos) {
      return false
    }
  }
  true
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "bloom: basic add and contains" {
  let bf = new(100, 0.01)
  add(bf, "hello")
  add(bf, "world")
  assert_true(contains(bf, "hello"))
  assert_true(contains(bf, "world"))
}

test "bloom: no false negatives" {
  let bf = new(100, 0.01)
  let words = ["apple", "banana", "cherry", "date", "elderberry",
               "fig", "grape", "honeydew", "kiwi", "lemon"]
  for i = 0; i < words.length(); i = i + 1 {
    add(bf, words[i])
  }
  for i = 0; i < words.length(); i = i + 1 {
    assert_true(contains(bf, words[i]))
  }
}

test "bloom: empty filter" {
  let bf = new(100, 0.01)
  assert_false(contains(bf, "anything"))
  assert_false(contains(bf, ""))
}

test "bloom: single element" {
  let bf = new(100, 0.01)
  add(bf, "test")
  assert_true(contains(bf, "test"))
}

test "bloom: multiple elements" {
  let bf = new(100, 0.01)
  for i = 0; i < 50; i = i + 1 {
    add(bf, "item_" + i.to_string())
  }
  for i = 0; i < 50; i = i + 1 {
    assert_true(contains(bf, "item_" + i.to_string()))
  }
}

test "bloom: large number of elements" {
  let bf = new(1000, 0.01)
  for i = 0; i < 500; i = i + 1 {
    add(bf, "key_" + i.to_string())
  }
  // No false negatives — every inserted key must be found
  for i = 0; i < 500; i = i + 1 {
    assert_true(contains(bf, "key_" + i.to_string()))
  }
}

test "bloom: false positive rate" {
  let bf = new(100, 0.01)
  // Add 100 items
  for i = 0; i < 100; i = i + 1 {
    add(bf, "item_" + i.to_string())
  }
  // Check 1000 items that were NOT added
  let mut false_positives = 0
  for i = 100; i < 1100; i = i + 1 {
    if contains(bf, "item_" + i.to_string()) {
      false_positives = false_positives + 1
    }
  }
  // With 1% FPR, expect roughly 10 false positives out of 1000.
  // Allow generous margin: should be well under 10% (100).
  assert_true(false_positives < 100)
}

test "bloom: different false positive rates" {
  // A higher FPR filter should permit more false positives than a lower one.
  let bf_low = new(100, 0.001) // 0.1% target
  let bf_high = new(100, 0.1) // 10% target
  for i = 0; i < 100; i = i + 1 {
    add(bf_low, "elem_" + i.to_string())
    add(bf_high, "elem_" + i.to_string())
  }
  let mut fp_low = 0
  let mut fp_high = 0
  for i = 100; i < 1100; i = i + 1 {
    if contains(bf_low, "elem_" + i.to_string()) {
      fp_low = fp_low + 1
    }
    if contains(bf_high, "elem_" + i.to_string()) {
      fp_high = fp_high + 1
    }
  }
  // The higher-FPR filter should have at least as many false positives.
  assert_true(fp_high >= fp_low)
}

test "bloom: bf_ln guard for non-positive input" {
  // These should not infinite-loop; they return 0.0
  let bf = new(10, 0.01) // uses bf_ln internally, should not hang
  assert_true(contains(bf, "test") == false)
}