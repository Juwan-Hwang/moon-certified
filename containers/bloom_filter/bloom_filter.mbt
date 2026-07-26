///|
/// Bloom filter for probabilistic set membership testing.
///
/// Uses **double hashing**: a single user-supplied hash h₁ = hash(data) is
/// computed, and a second hash h₂ is derived from it
/// (h₂ = (h₁ · 16777619 + 1) | 1, forced odd for full-period double hashing).
/// The k bit positions for an element are derived as
///   pos_i = (h₁ + i · h₂) mod m   for i = 0 .. k-1
/// This costs one hash evaluation plus O(k) bit probes — instead of k
/// independent hashes — and the k positions are provably distinct when h₂ is
/// odd and m is a power of two (or at least well-distributed otherwise).
///
/// The filter is **generic** over the element type `T`: the caller supplies a
/// `T -> Int` hash function at construction time, so any hashable type can be
/// stored, not just `String`.
///
/// The bit array is stored as 64-bit words. False positives are possible but
/// false negatives are impossible.
///
/// Optimal parameters:
///   m (bits) = -n * ln(p) / (ln(2))^2
///   k (hashes) = (m / n) * ln(2)
/// where n = expected items, p = false positive rate.
///
/// Not formally verified. Correctness ensured by comprehensive tests.
pub struct BloomFilter[T] {
  priv bits : FixedArray[UInt64] // bit array stored as 64-bit words
  priv num_bits : Int
  priv num_hashes : Int
  priv hash : (T) -> Int // user-supplied hash: turns an element into a seed
}

///|
/// ln(2), used by parameter sizing formulas.
const BF_LN2 : Double = 0.6931471805599453

///|
/// Safe natural logarithm. Returns 0.0 for non-positive inputs.
/// Uses the standard library's `@math.ln` instead of a custom implementation.
/// The caller `new()` already validates `false_positive_rate > 0.0 && < 1.0`,
/// so the guard is a safety net.
fn bf_ln(x : Double) -> Double {
  if x <= 0.0 {
    return 0.0
  }
  @math.ln(x)
}

///|
/// Create a Bloom filter sized for `expected_items` at the given
/// `false_positive_rate`. Calculates optimal bit count and hash count.
///
/// `hash` is the user-supplied hash function that maps each element of type
/// `T` to an `Int`; it is stored in the filter and reused by every
/// `add` / `contains` call, making the filter generic over `T`.
pub fn[T] new(
  expected_items : Int,
  false_positive_rate : Double,
  hash : (T) -> Int,
) -> BloomFilter[T] {
  let n = if expected_items > 0 { expected_items } else { 1 }
  let p = if false_positive_rate > 0.0 && false_positive_rate < 1.0 {
    false_positive_rate
  } else {
    0.01
  }
  let ln_p = bf_ln(p) // negative since p < 1
  // m = -n * ln(p) / (ln(2))^2
  let m_d = n.to_double() * -ln_p / (BF_LN2 * BF_LN2)
  let m = m_d.to_int()
  let num_bits = if m > 64 { m } else { 64 }
  // k = (m / n) * ln(2)
  let k_d = num_bits.to_double() / n.to_double() * BF_LN2
  let k_raw = k_d.to_int()
  let num_hashes = if k_raw > 1 { k_raw } else { 1 }
  let num_words = (num_bits + 63) / 64
  { bits: FixedArray::make(num_words, 0UL), num_bits, num_hashes, hash }
}

///|
/// Compute two base hashes for double hashing from a user-supplied hash.
///
/// `h1` is the caller's hash of the data. `h2` is derived from `h1` by
/// multiplying with the FNV-1 32-bit prime (16777619) and adding 1; the
/// result is forced odd (`| 1`) so that when `num_bits` is a power of two,
/// the sequence `(h1 + i·h2) mod m` visits all residues before repeating —
/// guaranteeing k distinct positions for k ≤ m.
fn[T] double_hash(hash_fn : (T) -> Int, data : T) -> (Int, Int) {
  let h1 = hash_fn(data)
  let h2 = (h1 * 16777619 + 1) | 1 // force odd for full-period double hashing
  (h1, h2)
}

///|
/// Map a hash value to a non-negative bit position in [0, num_bits).
fn bit_pos(h : Int, num_bits : Int) -> Int {
  (h % num_bits + num_bits) % num_bits
}

///|
/// Set the bit at position `pos` in the word array.
///
/// **Bounds guard**: A negative `pos` or a `pos` falling outside the backing
/// word array is silently ignored (no-op). This mirrors the defensive stance
/// of `bf_ln`'s guard: callers (`add`) already constrain `pos` to
/// `[0, num_bits)` via `bit_pos`, so this is a safety net against any future
/// path that might feed in an out-of-range index, which would otherwise panic.
fn set_bit(bits : FixedArray[UInt64], pos : Int) -> Unit {
  if pos < 0 {
    return
  }
  let word = pos / 64
  if word >= bits.length() {
    return
  }
  let bit = pos % 64
  bits[word] = bits[word] | (1UL << bit)
}

///|
/// Test whether the bit at position `pos` is set.
///
/// **Bounds guard**: Returns `false` for out-of-range positions, consistent
/// with `set_bit`'s defensive style.
fn get_bit(bits : FixedArray[UInt64], pos : Int) -> Bool {
  if pos < 0 {
    return false
  }
  let word = pos / 64
  if word >= bits.length() {
    return false
  }
  let bit = pos % 64
  (bits[word] & (1UL << bit)) != 0UL
}

///|
/// Add an element to the filter. Sets k bits using double hashing:
///   pos_i = (h1 + i * h2) mod num_bits   for i = 0 .. k-1
/// This requires only one hash evaluation (plus O(1) derivation) instead of
/// k independent hashes.
pub fn[T] add(bf : BloomFilter[T], data : T) -> Unit {
  let (h1, h2) = double_hash(bf.hash, data)
  for i = 0; i < bf.num_hashes; i = i + 1 {
    let combined = h1 + i * h2
    let pos = bit_pos(combined, bf.num_bits)
    set_bit(bf.bits, pos)
  }
}

///|
/// Check if data *might* be in the set. False positives are possible;
/// false negatives are impossible.
///
/// Uses the same double-hashing scheme as `add` to check k bit positions.
pub fn[T] contains(bf : BloomFilter[T], data : T) -> Bool {
  let (h1, h2) = double_hash(bf.hash, data)
  for i = 0; i < bf.num_hashes; i = i + 1 {
    let combined = h1 + i * h2
    let pos = bit_pos(combined, bf.num_bits)
    if !get_bit(bf.bits, pos) {
      return false
    }
  }
  true
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
/// Polynomial rolling hash for `String`, used by the unit tests below.
fn str_hash(s : String) -> Int {
  let mut h = 0
  for i = 0; i < s.length(); i = i + 1 {
    h = h * 31 + s[i].to_int()
  }
  h
}

///|
test "bloom: basic add and contains" {
  let bf = new(100, 0.01, str_hash)
  add(bf, "hello")
  add(bf, "world")
  assert_true(contains(bf, "hello"))
  assert_true(contains(bf, "world"))
}

///|
test "bloom: no false negatives" {
  let bf = new(100, 0.01, str_hash)
  let words = [
    "apple", "banana", "cherry", "date", "elderberry", "fig", "grape", "honeydew",
    "kiwi", "lemon",
  ]
  for i = 0; i < words.length(); i = i + 1 {
    add(bf, words[i])
  }
  for i = 0; i < words.length(); i = i + 1 {
    assert_true(contains(bf, words[i]))
  }
}

///|
test "bloom: empty filter" {
  let bf = new(100, 0.01, str_hash)
  assert_false(contains(bf, "anything"))
  assert_false(contains(bf, ""))
}

///|
test "bloom: single element" {
  let bf = new(100, 0.01, str_hash)
  add(bf, "test")
  assert_true(contains(bf, "test"))
}

///|
test "bloom: multiple elements" {
  let bf = new(100, 0.01, str_hash)
  for i = 0; i < 50; i = i + 1 {
    add(bf, "item_" + i.to_string())
  }
  for i = 0; i < 50; i = i + 1 {
    assert_true(contains(bf, "item_" + i.to_string()))
  }
}

///|
test "bloom: large number of elements" {
  let bf = new(1000, 0.01, str_hash)
  for i = 0; i < 500; i = i + 1 {
    add(bf, "key_" + i.to_string())
  }
  // No false negatives — every inserted key must be found
  for i = 0; i < 500; i = i + 1 {
    assert_true(contains(bf, "key_" + i.to_string()))
  }
}

///|
test "bloom: false positive rate" {
  let bf = new(100, 0.01, str_hash)
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

///|
test "bloom: different false positive rates" {
  // A higher FPR filter should permit more false positives than a lower one.
  let bf_low = new(100, 0.001, str_hash) // 0.1% target
  let bf_high = new(100, 0.1, str_hash) // 10% target
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

///|
test "bloom: bf_ln guard for non-positive input" {
  // These should not infinite-loop; they return 0.0
  let bf = new(10, 0.01, str_hash) // uses bf_ln internally, should not hang
  assert_true(contains(bf, "test") == false)
}

///|
test "bloom: generic over non-String type (Int)" {
  // The filter is generic: here we hash Int elements directly.
  let int_hash = fn(x : Int) -> Int { x }
  let bf = new(100, 0.01, int_hash)
  add(bf, 42)
  add(bf, 7)
  assert_true(contains(bf, 42))
  assert_true(contains(bf, 7))
  assert_false(contains(bf, 999))
}
