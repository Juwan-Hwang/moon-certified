/// HyperLogLog: probabilistic cardinality estimation.
///
/// HyperLogLog counts the number of *distinct* elements in a data stream using
/// only `O(2^p)` 6-bit registers, while keeping the relative standard error
/// near `1.04 / sqrt(2^p)` — roughly 0.8% at `p = 14`.
///
/// **Algorithm.** Each element is hashed to 64 bits. The low `p` bits select a
/// register; the remaining `64 - p` bits determine that register's value as
/// `1 + (number of leading zeros)` — the position of the leftmost 1-bit. A
/// register always stores the *maximum* rank ever observed for its bucket, so
/// duplicate insertions are idempotent. Cardinality is estimated from the
/// harmonic mean of the registers:
///   E = alpha_m * m^2 / sum_j 2^(-M[j])      (m = 2^p)
/// with two corrections:
///   - *small range* (linear counting): when `E <= 2.5 * m` and some registers
///     are still zero, `E = m * ln(m / V)` is far more accurate for small
///     cardinalities, where `V` is the number of zero registers.
///   - *large range*: when `E` approaches the 64-bit hash space `2^64`, hash
///     collisions bias the estimate downward, so
///     `E = -2^64 * ln(1 - E / 2^64)`. (With 64-bit hashes this only matters
///     near `2^64 / 30 ≈ 6.1e18`, so it is effectively unreachable in practice
///     but included for completeness.)
///
/// **Hashing.** Input is hashed with FNV-1a (64-bit offset basis and prime)
/// and then passed through MurmurHash3's `fmix64` avalanche finalizer. The
/// avalanche step is essential: it diffuses the linear structure of FNV so
/// that the low `p` bits (register index) and the high bits (rank) are
/// effectively independent and uniformly distributed.
///
/// **Merge.** Two sketches with identical precision are merged by taking the
/// pointwise maximum of their registers — exactly the state that observing the
/// union of both streams would have produced.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

// ---------------------------------------------------------------------------
// Data structure
// ---------------------------------------------------------------------------

///|
/// A HyperLogLog cardinality sketch.
///
/// - `registers` is a `m = 2^precision`-element `FixedArray[Int]`. Each entry
///   is a 6-bit counter (value in `[0, 65 - precision]`); element mutation of
///   the array does not require the field to be `mut`.
/// - `precision` is `p`; `m` is `2^p`, cached to avoid recomputation.
pub struct HyperLogLog {
  priv registers : FixedArray[Int]
  priv precision : Int
  priv m : Int
}

///|
/// 2^64 as a `Double`, the size of the 64-bit hash space. Used only by the
/// (effectively unreachable) large-range correction.
const HLL_TWO_POW_64 : Double = 1.8446744073709552e19

///|
/// FNV-1a 64-bit offset basis and prime.
const HLL_FNV_OFFSET : Int64 = 0xcbf29ce484222325L

///|
const HLL_FNV_PRIME : Int64 = 0x100000001b3L

// ---------------------------------------------------------------------------
// Hashing: FNV-1a + shared fmix64 avalanche (from hash_utils)
// ---------------------------------------------------------------------------

///|
/// FNV-1a 64-bit hash of a `String`, then avalanched.
///
///   h = offset_basis
///   for each char c: h = (h XOR c) * prime
///   return @hash_utils.fmix64(h)
///
/// Each character's code point is folded in with XOR (the FNV-1a variant)
/// rather than addition (FNV-1), then multiplied by the FNV prime.
fn fnv1a_64(data : String) -> Int64 {
  let mut h = HLL_FNV_OFFSET
  for i = 0; i < data.length(); i = i + 1 {
    h = (h ^ data[i].to_int().to_int64()) * HLL_FNV_PRIME
  }
  @hash_utils.fmix64(h)
}

///|
/// FNV-1a 64-bit hash of an `Int` key, then avalanched.
///
/// Both the value and its high 32 bits are folded in so that nearby integers
/// (1, 2, 3, …) hash to well-separated, uncorrelated 64-bit values.
fn fnv1a_64_int(x : Int) -> Int64 {
  let k = x.to_int64()
  let mut h = HLL_FNV_OFFSET
  h = (h ^ k) * HLL_FNV_PRIME
  h = (h ^ (k >> 32)) * HLL_FNV_PRIME
  @hash_utils.fmix64(h)
}

// ---------------------------------------------------------------------------
// Math helper: safe natural logarithm
// ---------------------------------------------------------------------------

///|
/// Safe natural logarithm. Returns 0.0 for non-positive inputs.
/// Uses the standard library's `@math.ln` instead of a custom implementation.
fn hll_ln(x : Double) -> Double {
  if x <= 0.0 {
    return 0.0
  }
  @math.ln(x)
}

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

///|
/// Create a HyperLogLog with `2^precision` registers.
///
/// `precision` (a.k.a. `p`) controls the memory/accuracy trade-off: memory is
/// `2^p` registers and the relative standard error is `~1.04 / sqrt(2^p)`.
///
/// **Precondition**: `4 <= precision <= 16`. Violations are clamped to the
/// nearest valid bound. `p < 4` gives too few registers for the bias constants
/// to apply; `p > 16` is capped to keep the register array at most 65536.
pub fn new(precision : Int) -> HyperLogLog {
  let precision = if precision < 4 {
    4
  } else if precision > 16 {
    16
  } else {
    precision
  }
  let m = 1 << precision
  { registers: FixedArray::make(m, 0), precision, m, }
}

// ---------------------------------------------------------------------------
// Core operations
// ---------------------------------------------------------------------------

///|
/// Split a 64-bit hash into a register index and a rank.
///
/// - `idx` = low `p` bits of `h` (a value in `[0, 2^p)`).
/// - `rank` = `1 +` the number of leading zeros in the upper `64 - p` bits.
///
/// The rank is computed with a single unsigned right shift by `p` (zero-filling
/// the top `p` bits) followed by the hardware `clz` of the resulting 64-bit
/// word. Because the top `p` bits are now zero, `clz >= p`, so
/// `rank = clz - p + 1` ranges over `[1, 65 - p]`. When the remaining bits are
/// all zero, `clz = 64` and `rank = 65 - p`.
fn idx_rank(h : Int64, precision : Int) -> (Int, Int) {
  let mask : Int64 = (1L << precision) - 1L
  let idx = (h & mask).to_int()
  let lz = (h.reinterpret_as_uint64() >> precision).clz()
  (idx, lz - precision + 1)
}

///|
/// Update the register selected by `h` with its rank, keeping the maximum.
fn add_hashed(hll : HyperLogLog, h : Int64) -> Unit {
  let (idx, rank) = idx_rank(h, hll.precision)
  let regs = hll.registers
  if rank > regs[idx] {
    regs[idx] = rank
  }
}

///|
/// Add a `String` key to the sketch.
pub fn add(hll : HyperLogLog, key : String) -> Unit {
  add_hashed(hll, fnv1a_64(key))
}

///|
/// Add an `Int` key to the sketch.
pub fn add_int(hll : HyperLogLog, key : Int) -> Unit {
  add_hashed(hll, fnv1a_64_int(key))
}

// ---------------------------------------------------------------------------
// Estimation
// ---------------------------------------------------------------------------

///|
/// Bias-correction constant `alpha_m` for the harmonic-mean estimator.
///
///   m = 16  -> 0.673
///   m = 32  -> 0.697
///   m = 64  -> 0.709
///   otherwise -> 0.7213 / (1 + 1.079 / m)
///
/// The three small-`m` constants are the exact tabulated values from the
/// HyperLogLog paper; the formula is the asymptotic approximation accurate for
/// `m >= 128`.
fn alpha_m(m : Int) -> Double {
  if m == 16 {
    0.673
  } else if m == 32 {
    0.697
  } else if m == 64 {
    0.709
  } else {
    0.7213 / (1.0 + 1.079 / m.to_double())
  }
}

///|
/// Estimate the number of distinct elements observed so far.
///
/// Applies the standard HyperLogLog pipeline: the raw harmonic-mean estimate,
/// then small-range (linear counting) correction when the sketch is sparse,
/// then large-range correction near the 64-bit hash-space limit.
pub fn estimate(hll : HyperLogLog) -> Double {
  let m = hll.m
  let md = m.to_double()
  // Precompute 2^(-k) for k = 0..64 so the summation loop is a plain lookup.
  // Registers hold values in [0, 65 - precision] <= 61, well within range.
  let pow2_neg = FixedArray::make(65, 1.0)
  for k = 1; k < 65; k = k + 1 {
    pow2_neg[k] = pow2_neg[k - 1] * 0.5
  }
  let mut sum = 0.0
  let mut zeros = 0
  for j = 0; j < m; j = j + 1 {
    let r = hll.registers[j]
    sum = sum + pow2_neg[r]
    if r == 0 {
      zeros = zeros + 1
    }
  }
  // Empty sketch: every register is zero, so no element has been observed.
  // Returning 0.0 directly avoids the floating-point noise that the series
  // approximation in `hll_ln` introduces for ln(1.0) (= m * ln(m / m)).
  if zeros == m {
    return 0.0
  }
  let mut e = alpha_m(m) * md * md / sum
  // Small range: linear counting is more accurate while registers are sparse.
  if e <= 2.5 * md && zeros > 0 {
    e = md * hll_ln(md / zeros.to_double())
  }
  // Large range: correct for collisions as E approaches 2^64.
  if e > HLL_TWO_POW_64 / 30.0 {
    e = -HLL_TWO_POW_64 * hll_ln(1.0 - e / HLL_TWO_POW_64)
  }
  e
}

// ---------------------------------------------------------------------------
// Merge
// ---------------------------------------------------------------------------

///|
/// Merge two sketches of identical precision into a fresh sketch.
///
/// Each register of the result is the maximum of the corresponding input
/// registers — the state that observing the union of both streams would have
/// produced. The inputs are left unchanged.
///
/// Returns `None` if the precisions differ, indicating the sketches cannot
/// be merged. The caller should ensure both sketches were created with the
/// same `precision` parameter.
pub fn merge(hll1 : HyperLogLog, hll2 : HyperLogLog) -> HyperLogLog? {
  if hll1.precision != hll2.precision {
    return None
  }
  let m = hll1.m
  let merged = FixedArray::make(m, 0)
  for j = 0; j < m; j = j + 1 {
    let a = hll1.registers[j]
    let b = hll2.registers[j]
    merged[j] = if a > b { a } else { b }
  }
  Some({ registers: merged, precision: hll1.precision, m, })
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "hll: empty estimate is zero" {
  let hll = new(14)
  let est = estimate(hll)
  // With no elements every register is zero: linear counting gives
  // m * ln(m / m) = m * ln(1) = 0.
  assert_true(est == 0.0)
}

///|
test "hll: single element" {
  let hll = new(14)
  add(hll, "only")
  let est = estimate(hll)
  // Exactly one register is non-zero, so V = m - 1 and linear counting gives
  // m * ln(m / (m - 1)) ≈ 1.0.
  assert_true(est > 0.5)
  assert_true(est < 1.5)
}

///|
test "hll: multiple distinct elements within 10%" {
  let hll = new(14)
  for i = 0; i < 1000; i = i + 1 {
    add(hll, "item_" + i.to_string())
  }
  let est = estimate(hll)
  // 1000 distinct, p=14 -> linear counting, ~1.2% std error.
  assert_true(est > 900.0)
  assert_true(est < 1100.0)
}

///|
test "hll: duplicate elements do not increase count" {
  let hll = new(14)
  add(hll, "duplicate")
  let e1 = estimate(hll)
  for i = 0; i < 999; i = i + 1 {
    add(hll, "duplicate")
  }
  let e2 = estimate(hll)
  // Still approximately one distinct element.
  assert_true(e2 < 1.5)
  // Re-adding the same key only ever takes a per-register maximum, so the
  // estimate cannot increase.
  assert_true(e2 <= e1)
}

///|
test "hll: large stream of 10000 distinct within 5%" {
  let hll = new(14)
  for i = 0; i < 10000; i = i + 1 {
    add(hll, "key_" + i.to_string())
  }
  let est = estimate(hll)
  // 10000 distinct, p=14 -> linear counting, ~1.2% std error.
  assert_true(est > 9500.0)
  assert_true(est < 10500.0)
}

///|
test "hll: merge two sketches" {
  let hll1 = new(14)
  let hll2 = new(14)
  for i = 0; i < 500; i = i + 1 {
    add(hll1, "a_" + i.to_string())
  }
  for i = 0; i < 500; i = i + 1 {
    add(hll2, "b_" + i.to_string())
  }
  let merged = merge(hll1, hll2)
  let est = match merged {
    Some(m) => estimate(m)
    None => 0.0
  }
  // 1000 distinct total (disjoint halves); within 10%.
  assert_true(est > 900.0)
  assert_true(est < 1100.0)
  // Non-destructive: inputs keep their own counts.
  let e1 = estimate(hll1)
  let e2 = estimate(hll2)
  assert_true(e1 > 450.0)
  assert_true(e1 < 550.0)
  assert_true(e2 > 450.0)
  assert_true(e2 < 550.0)
}

///|
test "hll: different precision levels" {
  let precisions = [4, 8, 12, 14, 16]
  for pi = 0; pi < precisions.length(); pi = pi + 1 {
    let p = precisions[pi]
    let hll = new(p)
    for i = 0; i < 1000; i = i + 1 {
      add(hll, "key_" + i.to_string())
    }
    let est = estimate(hll)
    // Every precision yields a sane, positive estimate in the right order of
    // magnitude. p=4 (m=16) is inherently noisy (~26% std error), so the band
    // is generous; higher precisions are far tighter (see the dedicated
    // accuracy tests).
    assert_true(est > 100.0)
    assert_true(est < 5000.0)
  }
}

///|
test "hll: int key support" {
  let hll = new(14)
  for i = 0; i < 1000; i = i + 1 {
    add_int(hll, i)
  }
  // Re-adding some ints must not change the distinct count.
  for i = 0; i < 100; i = i + 1 {
    add_int(hll, i)
  }
  let est = estimate(hll)
  // 1000 distinct ints; within 10%.
  assert_true(est > 900.0)
  assert_true(est < 1100.0)
}

///|
test "hll: raw harmonic-mean estimator for large cardinality" {
  // p=12 -> m=4096, small-range threshold 2.5*m = 10240. With 20000 distinct
  // the raw estimate exceeds the threshold, so the harmonic-mean estimator
  // (not linear counting) is exercised. Standard error ~1.04/sqrt(4096) ≈ 1.6%.
  let hll = new(12)
  for i = 0; i < 20000; i = i + 1 {
    add(hll, "elem_" + i.to_string())
  }
  let est = estimate(hll)
  assert_true(est > 18000.0)
  assert_true(est < 22000.0)
}

///|
test "hll: precision out of range clamped" {
  // new clamps precision to [4, 16]; out-of-range values are clamped.
  let _low = new(2)
  let _high = new(20)
  assert_true(_low.m == 16)
  assert_true(_high.m == 65536)
}
