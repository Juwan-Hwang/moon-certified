/// Counting Bloom Filter.
///
/// A counting bloom filter is a probabilistic data structure that extends
/// the standard bloom filter by using counters instead of single bits.
/// This allows element removal while maintaining O(k) time complexity.
///
/// ## Properties
///
/// - False positives are possible (but tunable)
/// - False negatives are NOT possible
/// - Supports add, remove, and contains operations
/// - Space-efficient: O(m) where m is the filter size
///
/// ## References
///
/// - Fan, B., Andersen, O.G., Kaminsky, M., Mitzenmacher, M.D.
///   "Cuckoo Filter: Practically Better Than Bloom." 2014.
/// - Bonomi, F. et al. "An Improved Construction for Counting Bloom Filters."
///
/// `proof-enabled` is `false`.

///|
/// A counting bloom filter with configurable number of hash functions
/// and counter width.
pub struct CountingBloomFilter {
  priv counters : Array[Int]
  priv num_hashes : Int
  priv num_bits : Int
  priv mut count : Int // approximate number of elements
}

///|
/// Create a new counting bloom filter.
/// `expected_elements` is the estimated number of elements to store.
/// `false_positive_rate` is the desired false positive probability.
pub fn new(expected_elements : Int, false_positive_rate : Double) -> CountingBloomFilter {
  // Calculate optimal parameters
  // m = -n * ln(p) / (ln(2)^2)
  // k = (m/n) * ln(2)
  let ln2 = 0.6931471805599453
  let n = if expected_elements < 1 { 100 } else { expected_elements }
  let p = if false_positive_rate <= 0.0 || false_positive_rate >= 1.0 { 0.01 } else { false_positive_rate }
  let m = ((-(n.to_double()) * @math.ln(p)) / (ln2 * ln2)).to_int() + 1
  let k = ((m.to_double() / n.to_double()) * ln2).to_int() + 1
  let bits = if m < 8 { 8 } else { m }
  { counters: Array::make(bits, 0), num_hashes: if k < 1 { 1 } else { k }, num_bits: bits, count: 0 }
}

///|
/// Double hashing: combine two hash values to produce k hash functions.
/// Uses h_i(x) = (h1(x) + i * h2(x)) mod m
fn double_hash(key : String, i : Int, m : Int) -> Int {
  let h1 = hash_fn(key, 0)
  let h2 = hash_fn(key, 1)
  let result = (h1 + i * h2) % m
  if result < 0 { result + m } else { result }
}

///|
/// Simple string hash with seed.
fn hash_fn(s : String, seed : Int) -> Int {
  let mut hash = seed
  for ch in s {
    hash = hash * 31 + ch.to_int()
  }
  if hash < 0 { -hash } else { hash }
}

///|
/// Add an element to the counting bloom filter.
pub fn add(cbf : CountingBloomFilter, key : String) -> Unit {
  for i = 0; i < cbf.num_hashes; i = i + 1 {
    let idx = double_hash(key, i, cbf.num_bits)
    cbf.counters[idx] = cbf.counters[idx] + 1
  }
  cbf.count = cbf.count + 1
}

///|
/// Remove an element from the counting bloom filter.
/// Warning: removing an element that was never added can cause
/// false negatives for other elements.
pub fn remove(cbf : CountingBloomFilter, key : String) -> Unit {
  for i = 0; i < cbf.num_hashes; i = i + 1 {
    let idx = double_hash(key, i, cbf.num_bits)
    if cbf.counters[idx] > 0 {
      cbf.counters[idx] = cbf.counters[idx] - 1
    }
  }
  if cbf.count > 0 {
    cbf.count = cbf.count - 1
  }
}

///|
/// Check if an element might be in the filter.
/// Returns true if the element is possibly present (may be false positive).
/// Returns false if the element is definitely not present.
pub fn contains(cbf : CountingBloomFilter, key : String) -> Bool {
  for i = 0; i < cbf.num_hashes; i = i + 1 {
    let idx = double_hash(key, i, cbf.num_bits)
    if cbf.counters[idx] == 0 {
      return false
    }
  }
  true
}

///|
/// Get the approximate number of elements.
pub fn count(cbf : CountingBloomFilter) -> Int {
  cbf.count
}

///|
/// Reset the filter to empty.
pub fn clear(cbf : CountingBloomFilter) -> Unit {
  for i = 0; i < cbf.num_bits; i = i + 1 {
    cbf.counters[i] = 0
  }
  cbf.count = 0
}

///|
test "counting_bloom: add and contains" {
  let cbf = new(100, 0.01)
  add(cbf, "hello")
  add(cbf, "world")
  assert_true(contains(cbf, "hello"))
  assert_true(contains(cbf, "world"))
  assert_false(contains(cbf, "missing"))
}

///|
test "counting_bloom: remove" {
  let cbf = new(100, 0.01)
  add(cbf, "apple")
  add(cbf, "banana")
  assert_true(contains(cbf, "apple"))
  remove(cbf, "apple")
  assert_false(contains(cbf, "apple"))
  assert_true(contains(cbf, "banana"))
}

///|
test "counting_bloom: count tracking" {
  let cbf = new(100, 0.01)
  assert_eq(count(cbf), 0)
  add(cbf, "a")
  add(cbf, "b")
  add(cbf, "c")
  assert_eq(count(cbf), 3)
  remove(cbf, "b")
  assert_eq(count(cbf), 2)
}

///|
test "counting_bloom: no false negatives" {
  let cbf = new(50, 0.01)
  let items = ["item1", "item2", "item3", "item4", "item5"]
  for i = 0; i < items.length(); i = i + 1 {
    add(cbf, items[i])
  }
  for i = 0; i < items.length(); i = i + 1 {
    assert_true(contains(cbf, items[i]))
  }
}
