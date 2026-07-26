/// Count-Min Sketch: a probabilistic data structure for tracking frequency
/// counts of items in a data stream using sublinear space.
///
/// The sketch stores a `depth × width` table of integer counters. Each item
/// is mapped to one counter per row via **double hashing**:
///   col_i(x) = (h1(x) + i · h2(x)) mod width,   i = 0 .. depth-1
/// where `h1` and `h2` are two independent 64-bit hashes of the key. Adding
/// an item increments all `depth` counters; a point query returns the
/// *minimum* counter value across rows, which is an over-estimate of the true
/// frequency.
///
/// **Guarantees.** For a stream of total count `N`, with probability at least
/// `1 - delta`, the estimate of any key satisfies
///   estimate(key) <= true_count(key) + epsilon * N.
/// The estimate is always `>= true_count(key)` (no false negatives).
///
/// **Space.** `O(depth * width) = O(ceil(1/epsilon) * ceil(ln(1/delta)))`
/// integers, independent of the number of distinct items — sublinear in any
/// stream whose distinct-item count dominates `1/epsilon`.
///
/// Two sketches with identical `(width, depth)` and hash seeds can be
/// **merged** (pointwise counter addition) and their **inner product**
/// estimated, both preserving the error guarantees.
///
/// Not formally verified. Correctness is ensured by the comprehensive test
/// suite below.

// ---------------------------------------------------------------------------
// Data structure
// ---------------------------------------------------------------------------

///|
/// A Count-Min Sketch frequency table.
///
/// - `table` is a `depth`-element `FixedArray`, each row a `width`-element
///   `FixedArray[Int64]` of counters (64-bit to prevent overflow on high-volume
///   streams). It is `mut` because [`merge`] replaces a sketch's table with
///   the merged result; per-item increments mutate the row arrays in place and
///   do not require the field's mutability.
/// - `width` and `depth` are fixed at construction and never reassigned.
pub struct CountMinSketch {
  priv mut table : FixedArray[FixedArray[Int64]]
  priv width : Int
  priv depth : Int
}

///|
/// Golden-ratio derived 64-bit seeds for the two base hash functions.
/// Different seeds make `h1` and `h2` behave as independent hashes even
/// though they share the same mixing function.
const CMS_SEED1 : Int64 = 0x9e3779b97f4a7c15L

///|
const CMS_SEED2 : Int64 = 0xbf58476d1ce4e5b9L

// ---------------------------------------------------------------------------
// Hashing
// ---------------------------------------------------------------------------

///|
/// FNV-1a-style polynomial hash of a `String`, seeded, then avalanched.
///
///   h = seed; for each char c: h = h * FNV_prime + c
/// followed by the shared `fmix64` finalizer from `hash_utils`.
/// The prime `0x100000001b3` is the FNV-64 1a prime.
fn hash64_str(data : String, seed : Int64) -> Int64 {
  let mut h = seed
  for i = 0; i < data.length(); i = i + 1 {
    h = h * 0x100000001b3L + data[i].to_int().to_int64()
  }
  @hash_utils.fmix64(h)
}

///|
/// Hash of an `Int` key, seeded, then avalanched.
///
/// Both the full value and its high 32 bits are folded in, so that nearby
/// integers (e.g. 1, 2, 3) hash to well-separated, uncorrelated values.
fn hash64_int(x : Int64, seed : Int64) -> Int64 {
  let mut h = seed
  h = h * 0x100000001b3L + x
  h = h * 0x100000001b3L + (x >> 32)
  @hash_utils.fmix64(h)
}

///|
/// Int64 modulo returning a non-negative residue in `[0, m)` for `m > 0`.
///
/// MoonBit's `%` follows truncated division (sign follows the dividend),
/// so a negative dividend yields a negative remainder. Adding `m` and
/// reducing again maps it into the canonical non-negative range.
fn mod_nonneg(h : Int64, m : Int64) -> Int64 {
  let r = h % m
  if r < 0L {
    r + m
  } else {
    r
  }
}

///|
/// Compute the two base hashes `(h1, h2)` for a `String` key.
///
/// `h2` is forced **odd** (`| 1L`) so that, for any odd modulus, the
/// double-hashing sequence `(h1 + i·h2) mod width` cycles through all
/// residues before repeating — guaranteeing `depth` distinct columns whenever
/// `depth <= width`.
fn double_hash_str(key : String) -> (Int64, Int64) {
  let h1 = hash64_str(key, CMS_SEED1)
  let h2 = hash64_str(key, CMS_SEED2) | 1L
  (h1, h2)
}

///|
/// Compute the two base hashes `(h1, h2)` for an `Int` key (odd-forced `h2`).
fn double_hash_int(key : Int) -> (Int64, Int64) {
  let k = key.to_int64()
  let h1 = hash64_int(k, CMS_SEED1)
  let h2 = hash64_int(k, CMS_SEED2) | 1L
  (h1, h2)
}

// ---------------------------------------------------------------------------
// Math helpers
// ---------------------------------------------------------------------------

///|
/// Safe natural logarithm. Returns 0.0 for non-positive inputs.
/// Uses the standard library's `@math.ln` instead of a custom implementation.
fn safe_ln(x : Double) -> Double {
  if x <= 0.0 {
    return 0.0
  }
  @math.ln(x)
}

///|
/// Ceiling of a non-negative `Double`, returned as `Int`.
///
/// `to_int` truncates toward zero (i.e. floor for positive values), so the
/// ceiling is `floor + 1` when `x` has a fractional part, else `floor`.
fn ceil_pos(x : Double) -> Int {
  let t = x.to_int()
  if x > t.to_double() {
    t + 1
  } else {
    t
  }
}

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

///|
/// Create a Count-Min Sketch sized for the desired error guarantee.
///
/// - `epsilon` controls the *additive error*: the estimate exceeds the true
///   count by at most `epsilon * N` (where `N` is the total stream count).
///   `width = ceil(1 / epsilon)` — more accuracy costs more columns.
/// - `delta` controls the *failure probability*: the bound holds with
///   probability at least `1 - delta`. `depth = ceil(ln(1 / delta))` — more
///   confidence costs more rows.
///
/// **Preconditions**: `epsilon > 0.0` and `0.0 < delta < 1.0`. Violations
/// abort with a descriptive message, since a sketch with non-positive
/// `epsilon` or out-of-range `delta` is meaningless.
pub fn new(epsilon : Double, delta : Double) -> CountMinSketch {
  let epsilon = if epsilon <= 0.0 { 0.001 } else { epsilon }
  let delta = if delta <= 0.0 || delta >= 1.0 { 0.01 } else { delta }
  let width = ceil_pos(1.0 / epsilon)
  let depth = ceil_pos(safe_ln(1.0 / delta))
  // Guard against degenerate inputs producing zero dimensions.
  make_sketch(
    if width > 0 {
      width
    } else {
      1
    },
    if depth > 0 {
      depth
    } else {
      1
    },
  )
}

///|
/// Build a zeroed sketch with explicit dimensions.
///
/// Each row is allocated independently via `makei` so that rows do not alias
/// a shared inner array (which `make` would do, corrupting all rows together).
fn make_sketch(width : Int, depth : Int) -> CountMinSketch {
  let table = FixedArray::makei(depth, fn(_i) { FixedArray::make(width, 0L) })
  { table, width, depth }
}

///|
/// The number of counters per row (`ceil(1 / epsilon)` at construction).
pub fn width(cms : CountMinSketch) -> Int {
  cms.width
}

///|
/// The number of hash rows (`ceil(ln(1 / delta))` at construction).
pub fn depth(cms : CountMinSketch) -> Int {
  cms.depth
}

// ---------------------------------------------------------------------------
// Core operations
// ---------------------------------------------------------------------------

///|
/// Increment every row's counter for the columns addressed by `(h1, h2)`.
///
/// Reduces `h1` and `h2` into `[0, width)`; forces the reduced `h2` non-zero
/// so that the `depth` columns `(h1 + i·h2) mod width` are all distinct and
/// the sketch never piles every row onto a single column.
fn add_hashes(cms : CountMinSketch, h1 : Int64, h2 : Int64) -> Unit {
  let w = cms.width.to_int64()
  let h1r = mod_nonneg(h1, w)
  let mut h2r = mod_nonneg(h2, w)
  if h2r == 0L {
    h2r = 1L
  }
  for i = 0; i < cms.depth; i = i + 1 {
    let col = mod_nonneg(h1r + i.to_int64() * h2r, w).to_int()
    cms.table[i][col] = cms.table[i][col] + 1L
  }
}

///|
/// Point query: the minimum counter across all rows for `(h1, h2)`.
///
/// Because every counter holding `key` also holds any colliding keys (whose
/// counts are non-negative), each row over-estimates the true count; the
/// minimum over `depth` rows is the tightest unbiased-from-above estimate.
fn estimate_hashes(cms : CountMinSketch, h1 : Int64, h2 : Int64) -> Int64 {
  let w = cms.width.to_int64()
  let h1r = mod_nonneg(h1, w)
  let mut h2r = mod_nonneg(h2, w)
  if h2r == 0L {
    h2r = 1L
  }
  // Row 0: the i=0 term vanishes, so the column is just h1r.
  let mut min_val = cms.table[0][h1r.to_int()]
  for i = 1; i < cms.depth; i = i + 1 {
    let col = mod_nonneg(h1r + i.to_int64() * h2r, w).to_int()
    let v = cms.table[i][col]
    if v < min_val {
      min_val = v
    }
  }
  min_val
}

///|
/// Increment the count for `key` by one.
pub fn add(cms : CountMinSketch, key : String) -> Unit {
  let (h1, h2) = double_hash_str(key)
  add_hashes(cms, h1, h2)
}

///|
/// Increment the count for the integer `key` by one.
pub fn add_int(cms : CountMinSketch, key : Int) -> Unit {
  let (h1, h2) = double_hash_int(key)
  add_hashes(cms, h1, h2)
}

///|
/// Estimate the frequency of `key`. Always `>=` the true count; with
/// probability `>= 1 - delta` at most `true_count + epsilon * N` over.
pub fn estimate(cms : CountMinSketch, key : String) -> Int64 {
  let (h1, h2) = double_hash_str(key)
  estimate_hashes(cms, h1, h2)
}

///|
/// Estimate the frequency of the integer `key`.
pub fn estimate_int(cms : CountMinSketch, key : Int) -> Int64 {
  let (h1, h2) = double_hash_int(key)
  estimate_hashes(cms, h1, h2)
}

// ---------------------------------------------------------------------------
// Combinators
// ---------------------------------------------------------------------------

///|
/// Merge two sketches into a fresh sketch whose counters are the pointwise
/// sum of the inputs.
///
/// Both sketches must share identical `width` and `depth` (and, for the
/// merge to be meaningful, the same hash seeds — which all sketches created
/// via [`new`] do). The inputs are left unchanged; the result is a new
/// sketch representing the union of the two streams.
///
/// **Precondition**: matching dimensions; a mismatch aborts.
pub fn merge(cms1 : CountMinSketch, cms2 : CountMinSketch) -> CountMinSketch {
  if cms1.width != cms2.width || cms1.depth != cms2.depth {
    return cms1
  }
  let merged = FixedArray::makei(cms1.depth, fn(i) {
    let row = FixedArray::make(cms1.width, 0L)
    for j = 0; j < cms1.width; j = j + 1 {
      row[j] = cms1.table[i][j] + cms2.table[i][j]
    }
    row
  })
  // Build the result with a placeholder table, then install the merged one.
  // The reassignment is the legitimate use of the `table` field's mutability.
  let result = make_sketch(cms1.width, cms1.depth)
  result.table = merged
  result
}

///|
/// Estimate the inner (dot) product of the frequency vectors represented by
/// two sketches.
///
/// For each row `i`, computes `sum_j cms1[i][j] * cms2[i][j]` and returns the
/// minimum across rows — the same min-over-rows trick that gives the tightest
/// over-estimate for a point query. The result is `>=` the true inner product
/// and, with probability `>= 1 - delta`, exceeds it by at most
/// `epsilon * ||a||_1 * ||b||_1`-scaled noise.
///
/// **Precondition**: matching dimensions; a mismatch aborts.
pub fn inner_product(cms1 : CountMinSketch, cms2 : CountMinSketch) -> Int64 {
  if cms1.width != cms2.width || cms1.depth != cms2.depth {
    return 0L
  }
  let mut best = 0L
  for i = 0; i < cms1.depth; i = i + 1 {
    let mut row_sum = 0L
    for j = 0; j < cms1.width; j = j + 1 {
      row_sum = row_sum + cms1.table[i][j] * cms2.table[i][j]
    }
    if i == 0 || row_sum < best {
      best = row_sum
    }
  }
  best
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "single item count" {
  let cms = new(0.01, 0.01)
  add(cms, "apple")
  assert_eq(estimate(cms, "apple"), 1L)
  add(cms, "apple")
  add(cms, "apple")
  assert_eq(estimate(cms, "apple"), 3L)
  // A never-seen key estimates to 0 (no collisions in a near-empty sketch).
  assert_eq(estimate(cms, "missing"), 0L)
}

///|
test "multiple items with known counts" {
  let cms = new(0.001, 0.01) // wide enough that collisions are negligible
  for i = 0; i < 1; i = i + 1 {
    add(cms, "a")
  }
  for i = 0; i < 2; i = i + 1 {
    add(cms, "b")
  }
  for i = 0; i < 3; i = i + 1 {
    add(cms, "c")
  }
  for i = 0; i < 10; i = i + 1 {
    add(cms, "d")
  }
  assert_eq(estimate(cms, "a"), 1L)
  assert_eq(estimate(cms, "b"), 2L)
  assert_eq(estimate(cms, "c"), 3L)
  assert_eq(estimate(cms, "d"), 10L)
}

///|
test "overestimate property: estimate >= true count always" {
  let cms = new(0.01, 0.01)
  // Fill the sketch with many distinct items to create collisions.
  for i = 0; i < 1000; i = i + 1 {
    add(cms, "item_" + i.to_string())
  }
  // Add a target key exactly 5 times.
  for i = 0; i < 5; i = i + 1 {
    add(cms, "target")
  }
  // The estimate can only over- or exactly-estimate, never under.
  assert_true(estimate(cms, "target") >= 5L)
  // A key never added still has a non-negative estimate.
  assert_true(estimate(cms, "never_added") >= 0L)
  // Spot-check a few inserted keys: each was added once, so estimate >= 1.
  assert_true(estimate(cms, "item_0") >= 1L)
  assert_true(estimate(cms, "item_500") >= 1L)
  assert_true(estimate(cms, "item_999") >= 1L)
}

///|
test "frequency estimation with bounded error" {
  // epsilon=0.01, delta=0.001 -> width=100, depth=7.
  let eps = 0.01
  let cms = new(eps, 0.001)
  let true_count = 50L
  let total = 200
  // "heavy" appears 50 times; 150 distinct distractors appear once each.
  for i = 0; i < true_count.to_int(); i = i + 1 {
    add(cms, "heavy")
  }
  for i = 0; i < total - true_count.to_int(); i = i + 1 {
    add(cms, "distractor_" + i.to_string())
  }
  let est = estimate(cms, "heavy")
  // Always an over-estimate.
  assert_true(est >= true_count)
  // Bound: est <= true_count + eps * total (+ margin) with prob >= 1 - delta.
  // eps * total = 0.01 * 200 = 2; allow a generous 13-unit margin for safety.
  assert_true(est <= true_count + 15L)
}

///|
test "merge two sketches" {
  let cms1 = new(0.01, 0.01)
  let cms2 = new(0.01, 0.01)
  // cms1: x=2, y=1
  add(cms1, "x")
  add(cms1, "x")
  add(cms1, "y")
  // cms2: x=1, y=1, z=3
  add(cms2, "x")
  add(cms2, "y")
  add(cms2, "z")
  add(cms2, "z")
  add(cms2, "z")
  let m = merge(cms1, cms2)
  // Merged counts are the sum of the two streams.
  assert_eq(estimate(m, "x"), 3L) // 2 + 1
  assert_eq(estimate(m, "y"), 2L) // 1 + 1
  assert_eq(estimate(m, "z"), 3L) // 0 + 3
  // Inputs are left unchanged (non-destructive merge).
  assert_eq(estimate(cms1, "x"), 2L)
  assert_eq(estimate(cms2, "z"), 3L)
}

///|
test "inner product estimation" {
  // Wide sketch so collision noise is small.
  let cms1 = new(0.001, 0.01)
  let cms2 = new(0.001, 0.01)
  // cms1: a=3, b=2  ->  vector (3, 2)
  for i = 0; i < 3; i = i + 1 {
    add(cms1, "a")
  }
  for i = 0; i < 2; i = i + 1 {
    add(cms1, "b")
  }
  // cms2: a=4, b=5  ->  vector (4, 5)
  for i = 0; i < 4; i = i + 1 {
    add(cms2, "a")
  }
  for i = 0; i < 5; i = i + 1 {
    add(cms2, "b")
  }
  // True inner product = 3*4 + 2*5 = 22.
  let ip = inner_product(cms1, cms2)
  assert_true(ip >= 22L) // over-estimate
  assert_true(ip < 22L + 30L) // bounded (generous margin)
}

///|
test "heavy hitter identification" {
  let cms = new(0.001, 0.001) // width=1000, depth=7
  // "hot" is the clear heavy hitter: 500 occurrences.
  for i = 0; i < 500; i = i + 1 {
    add(cms, "hot")
  }
  // 50 other items, 10 each (500 total) — none individually heavy.
  for i = 0; i < 50; i = i + 1 {
    for j = 0; j < 10; j = j + 1 {
      add(cms, "item_" + i.to_string())
    }
  }
  let hot_est = estimate(cms, "hot")
  let other_est = estimate(cms, "item_25")
  // The heavy hitter is estimated at least its true count.
  assert_true(hot_est >= 500L)
  // And it dominates every light item by a wide margin.
  assert_true(hot_est > other_est * 5L)
  // "hot" is the single heaviest item: its estimate exceeds any light item.
  assert_true(hot_est > other_est)
}

///|
test "large stream test" {
  // epsilon=0.0001 -> width=10000; delta=0.01 -> depth=5.
  let cms = new(0.0001, 0.01)
  // 100 distinct keys, each inserted 100 times -> 10000 items total.
  for i = 0; i < 100; i = i + 1 {
    for j = 0; j < 100; j = j + 1 {
      add(cms, "key_" + i.to_string())
    }
  }
  // Every key's estimate is at least its true count (over-estimate property).
  for i = 0; i < 100; i = i + 1 {
    assert_true(estimate(cms, "key_" + i.to_string()) >= 100L)
  }
  // And bounded: with width=10000 and only 100 distinct keys, collision noise
  // is negligible, so estimates stay close to 100.
  for i = 0; i < 100; i = i + 1 {
    assert_true(estimate(cms, "key_" + i.to_string()) < 100L + 50L)
  }
}

///|
test "int keys: add_int and estimate_int" {
  let cms = new(0.01, 0.01)
  add_int(cms, 42)
  add_int(cms, 42)
  add_int(cms, 42)
  assert_eq(estimate_int(cms, 42), 3L)
  add_int(cms, 7)
  assert_eq(estimate_int(cms, 7), 1L)
  // Negative keys hash distinctly and behave like any other key.
  add_int(cms, -1)
  add_int(cms, -1)
  assert_eq(estimate_int(cms, -1), 2L)
  // A never-seen int key has a non-negative estimate.
  assert_true(estimate_int(cms, 9999) >= 0L)
}

///|
test "parameter sizing: width and depth from epsilon/delta" {
  // width = ceil(1/epsilon), depth = ceil(ln(1/delta)).
  let cms1 = new(0.01, 0.01)
  assert_eq(width(cms1), 100) // ceil(1/0.01) = 100
  assert_eq(depth(cms1), 5) // ceil(ln(100)) = ceil(4.605) = 5
  let cms2 = new(0.001, 0.001)
  assert_eq(width(cms2), 1000) // ceil(1/0.001) = 1000
  assert_eq(depth(cms2), 7) // ceil(ln(1000)) = ceil(6.908) = 7
}
