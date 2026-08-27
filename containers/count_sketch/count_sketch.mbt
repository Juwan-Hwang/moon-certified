/// Count-Sketch — probabilistic frequency estimation for data streams.
///
/// Count-Sketch is a sublinear-space data structure for estimating the
/// frequency (number of occurrences) of items in a data stream. Unlike
/// Count-Min Sketch which always overestimates, Count-Sketch uses signed
/// counters (±1 hash) and takes the **median** of `d` estimates, producing
/// an **unbiased** estimator with variance proportional to `1/d`.
///
/// ## Algorithm
///
/// Maintain a `d × w` table of counters. For each update `(key, c)`:
/// 1. For each row `i`, compute bucket index `h_i(key) % w` and sign `s_i(key) ∈ {+1, -1}`.
/// 2. Add `s_i(key) * c` to `table[i][h_i(key) % w]`.
///
/// To estimate the frequency of `key`, compute the median of
/// `s_i(key) * table[i][h_i(key) % w]` across all `d` rows.
///
/// ## Complexity
/// - Update:  O(d) time.
/// - Estimate: O(d) time.
/// - Space:   O(d × w) counters.
///
/// ## Guarantees
/// With width `w = O(1/ε²)` and depth `d = O(log(1/δ))`, the estimate is
/// within `ε ||f||₂` of the true frequency with probability `1 - δ`.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

///|
/// The Count-Sketch data structure.
pub struct CountSketch {
  priv table : FixedArray[FixedArray[Int64]]
  priv width : Int
  priv depth : Int
  priv hash_fn : (String) -> Int
}

///|
/// Create a new Count-Sketch with the given dimensions.
///
/// - `width`: number of buckets per row (larger → lower variance).
/// - `depth`: number of rows (larger → higher confidence).
/// - `hash_fn`: hash function mapping keys to integers.
pub fn new(width : Int, depth : Int, hash_fn : (String) -> Int) -> CountSketch {
  let w = if width < 1 { 1 } else { width }
  let d = if depth < 1 { 1 } else { depth }
  let table = FixedArray::makei(d, fn(_) { FixedArray::make(w, 0L) })
  { table, width: w, depth: d, hash_fn, }
}

///|
/// Internal: compute bucket index and sign for row `row` and key `key`.
///
/// Uses double-hashing: `h_i = (h1 + i * h2) % width`, `s_i = 1 if (h1 >> 31) & 1 == 0 else -1`.
fn compute_bucket_sign(
  cs : CountSketch,
  row : Int,
  key : String,
) -> (Int, Int64) {
  let h = @hash_utils.fmix64(
    (cs.hash_fn)(key).to_int64() ^ (row.to_int64() * 0x9E3779B97F4A7C15L),
  )
  let unsigned_h = h.reinterpret_as_uint64()
  let bucket = (unsigned_h % cs.width.to_uint64())
    .reinterpret_as_int64()
    .to_int()
  let sign = if ((unsigned_h >> 63) & 1UL) == 0UL { 1L } else { -1L }
  (bucket, sign)
}

///|
/// Update the sketch: add `count` to the frequency of `key`.
pub fn update(cs : CountSketch, key : String, count : Int64) -> Unit {
  for i = 0; i < cs.depth; i = i + 1 {
    let (bucket, sign) = compute_bucket_sign(cs, i, key)
    cs.table[i][bucket] = cs.table[i][bucket] + sign * count
  }
}

///|
/// Estimate the frequency of `key`.
///
/// Returns the median of the `depth` row estimates. The estimate is
/// unbiased: E[estimate] = true frequency.
pub fn estimate(cs : CountSketch, key : String) -> Int64 {
  let estimates = Array::make(cs.depth, 0L)
  for i = 0; i < cs.depth; i = i + 1 {
    let (bucket, sign) = compute_bucket_sign(cs, i, key)
    estimates[i] = sign * cs.table[i][bucket]
  }
  // Sort and return median.
  estimates.sort_by(fn(a, b) { if a < b { -1 } else if a > b { 1 } else { 0 } })
  estimates[cs.depth / 2]
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "count_sketch: single item" {
  let cs = new(100, 7, fn(s) { @hash_utils.poly31_hash(s) })
  update(cs, "hello", 5L)
  assert_eq(estimate(cs, "hello"), 5L)
}

///|
test "count_sketch: multiple items" {
  let cs = new(200, 9, fn(s) { @hash_utils.poly31_hash(s) })
  update(cs, "a", 10L)
  update(cs, "b", 20L)
  update(cs, "c", 30L)
  assert_eq(estimate(cs, "a"), 10L)
  assert_eq(estimate(cs, "b"), 20L)
  assert_eq(estimate(cs, "c"), 30L)
}

///|
test "count_sketch: zero for unseen key" {
  let cs = new(100, 7, fn(s) { @hash_utils.poly31_hash(s) })
  update(cs, "a", 5L)
  let est = estimate(cs, "b")
  assert_true(est >= -5L && est <= 5L)
}

///|
test "count_sketch: repeated updates accumulate" {
  let cs = new(200, 9, fn(s) { @hash_utils.poly31_hash(s) })
  for i = 0; i < 100; i = i + 1 {
    update(cs, "key", 1L)
  }
  assert_eq(estimate(cs, "key"), 100L)
}

///|
test "count_sketch: negative count" {
  let cs = new(100, 7, fn(s) { @hash_utils.poly31_hash(s) })
  update(cs, "x", 10L)
  update(cs, "x", -3L)
  assert_eq(estimate(cs, "x"), 7L)
}

///|
test "count_sketch: heavy hitters vs light items" {
  let cs = new(500, 11, fn(s) { @hash_utils.poly31_hash(s) })
  // Heavy hitter.
  for i = 0; i < 1000; i = i + 1 {
    update(cs, "heavy", 1L)
  }
  // Light items.
  for i = 0; i < 10; i = i + 1 {
    update(cs, "light" + i.to_string(), 1L)
  }
  let heavy_est = estimate(cs, "heavy")
  assert_true(heavy_est >= 990L && heavy_est <= 1010L)
}

///|
test "count_sketch: empty sketch" {
  let cs = new(100, 5, fn(s) { @hash_utils.poly31_hash(s) })
  assert_eq(estimate(cs, "nothing"), 0L)
}
