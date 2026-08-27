/// Weighted Random Sampling algorithms.
///
/// Provides production-grade weighted sampling algorithms:
///
/// 1. **Alias Method**: O(n) preprocessing, O(1) per-sample. The industry
///    standard for repeated sampling from a fixed discrete distribution.
/// 2. **Weighted Reservoir Sampling (A-Res)**: O(k log n) streaming weighted
///    reservoir sampling without replacement.
///
/// ## PRNG
///
/// Reservoir sampling uses **SplitMix64**, a high-quality PRNG with full
/// 64-bit state and excellent statistical properties. The seed is a caller-
/// supplied parameter — callers should use a non-deterministic seed (e.g.
/// derived from system entropy) when statistical randomness is required.
///
/// ## Complexity
/// - Alias Method: O(n) build, O(1) per draw.
/// - Weighted Reservoir: O(k log n) for k items from n.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// SplitMix64 PRNG — delegates to @utils to avoid code duplication
// ---------------------------------------------------------------------------

///|
/// SplitMix64 PRNG state — a single `Int64` that produces high-quality
/// pseudo-random values with full period (2^64) and good statistical
/// properties (passes BigCrush). This is the same generator used by
/// `std::default_random_engine` in many standard libraries.
priv struct SplitMix64 {
  mut state : Int64
}

///|
/// Create a SplitMix64 PRNG seeded with `seed`.
fn splitmix64_new(seed : Int64) -> SplitMix64 {
  { state: seed, }
}

///|
/// Next uniform double in [0, 1).
fn splitmix64_next_double(rng : SplitMix64) -> Double {
  let (new_state, d) = @utils.splitmix64_next_double(rng.state)
  rng.state = new_state
  d
}

// ---------------------------------------------------------------------------
// Alias Method (O(1) per-sample after O(n) preprocessing)
// ---------------------------------------------------------------------------

///|
/// Alias table for O(1) weighted sampling.
pub struct AliasTable {
  priv prob : FixedArray[Double]
  priv alias_idx : FixedArray[Int]
  priv n : Int
}

///|
/// Build an alias table from weights.
///
/// # Parameters
/// - `weights`: non-negative weights. Need not be normalized.
///
/// After building, each `draw()` call takes O(1) time.
pub fn build_alias(weights : FixedArray[Double]) -> AliasTable {
  let n = weights.length()
  if n == 0 {
    return AliasTable::{
      prob: FixedArray::make(0, 0.0),
      alias_idx: FixedArray::make(0, 0),
      n: 0,
    }
  }
  // Normalize weights to sum = n.
  let mut total = 0.0
  for i = 0; i < n; i = i + 1 {
    total = total + weights[i]
  }
  if total <= 0.0 {
    // All weights zero: uniform distribution.
    let prob = FixedArray::makei(n, fn(_i) { 1.0 })
    let alias_idx = FixedArray::makei(n, fn(i) { i })
    return AliasTable::{ prob, alias_idx, n, }
  }
  let scale = n.to_double() / total
  let prob = FixedArray::makei(n, fn(i) { weights[i] * scale })
  let alias_idx = FixedArray::makei(n, fn(i) { i })
  // Partition into small (< 1) and large (>= 1).
  let small : Array[Int] = []
  let large : Array[Int] = []
  for i = 0; i < n; i = i + 1 {
    if prob[i] < 1.0 {
      small.push(i)
    } else {
      large.push(i)
    }
  }
  // Merge.
  while small.length() > 0 && large.length() > 0 {
    let s = small[small.length() - 1]
    ignore(small.pop())
    let l = large[large.length() - 1]
    ignore(large.pop())
    alias_idx[s] = l
    prob[l] = prob[l] + prob[s] - 1.0
    if prob[l] < 1.0 {
      small.push(l)
    } else {
      large.push(l)
    }
  }
  // Any remaining should have prob ≈ 1.0 (floating point).
  AliasTable::{ prob, alias_idx, n, }
}

///|
/// Draw a sample from the alias table using a uniform random `r` in [0, 1).
pub fn alias_draw(table : AliasTable, r : Double) -> Int {
  if table.n == 0 {
    return -1
  }
  let idx = (r * table.n.to_double()).to_int()
  let i = if idx >= table.n { table.n - 1 } else { idx }
  let frac = r * table.n.to_double() - i.to_double()
  if frac < table.prob[i] {
    i
  } else {
    table.alias_idx[i]
  }
}

// ---------------------------------------------------------------------------
// Weighted Reservoir Sampling (A-Res algorithm by Efraimidis & Spirakis)
// ---------------------------------------------------------------------------

///|
/// Sample k items from a stream of weighted items without replacement.
///
/// Uses the A-Res algorithm: for each item, generate a key = u^(1/w) where
/// u is uniform [0,1) and w is the weight. Keep the k items with largest keys.
///
/// # Parameters
/// - `weights`: weight of each item.
/// - `k`: number of items to sample.
/// - `seed`: 64-bit seed for the internal SplitMix64 PRNG. Use a
///   non-deterministic value for statistical applications.
///
/// # Returns
/// Array of selected item indices, sorted ascending.
pub fn weighted_reservoir_sample(
  weights : FixedArray[Double],
  k : Int,
  seed : Int64,
) -> FixedArray[Int] {
  let n = weights.length()
  if k <= 0 || n == 0 {
    return FixedArray::make(0, 0)
  }
  if k >= n {
    return FixedArray::makei(n, fn(i) { i })
  }
  let rng = splitmix64_new(seed)
  // Use a min-heap of size k, keyed by the transformed priority.
  //
  // A-Res key = u^(1/w) where u ~ Uniform(0,1). We keep the k items with
  // the LARGEST keys (heaviest items).  Taking -ln transforms this to:
  //   key' = -ln(u^(1/w)) = ln(u) / w
  // Since u ∈ (0,1), ln(u) < 0, so key' is negative.
  // Larger original key → smaller |key'| → key' closer to 0 (larger).
  // A min-heap that replaces the minimum when a new key is LARGER keeps
  // the k LARGEST key' values = k heaviest items. ✓
  let heap_vals = FixedArray::make(k, 0.0)
  let heap_idxs = FixedArray::make(k, 0)
  let mut heap_size = 0
  for i = 0; i < n; i = i + 1 {
    let u = splitmix64_next_double(rng)
    let w = weights[i]
    if w <= 0.0 {
      continue
    }
    // Guard against u == 0 (would cause log(0) = -inf).
    let u_safe = if u > 0.0 { u } else { 1.0e-300 }
    let key = @math.ln(u_safe) / w
    if heap_size < k {
      // Insert into heap.
      heap_vals[heap_size] = key
      heap_idxs[heap_size] = i
      heap_size = heap_size + 1
      // Sift up.
      let mut child = heap_size - 1
      while child > 0 {
        let parent = (child - 1) / 2
        if heap_vals[parent] > heap_vals[child] {
          let tmp_v = heap_vals[parent]
          heap_vals[parent] = heap_vals[child]
          heap_vals[child] = tmp_v
          let tmp_i = heap_idxs[parent]
          heap_idxs[parent] = heap_idxs[child]
          heap_idxs[child] = tmp_i
          child = parent
        } else {
          break
        }
      }
    } else if key > heap_vals[0] {
      // Replace minimum.
      heap_vals[0] = key
      heap_idxs[0] = i
      // Sift down.
      let mut pos = 0
      while true {
        let left = 2 * pos + 1
        let right = 2 * pos + 2
        let mut smallest = pos
        if left < heap_size && heap_vals[left] < heap_vals[smallest] {
          smallest = left
        }
        if right < heap_size && heap_vals[right] < heap_vals[smallest] {
          smallest = right
        }
        if smallest == pos {
          break
        }
        let tmp_v = heap_vals[pos]
        heap_vals[pos] = heap_vals[smallest]
        heap_vals[smallest] = tmp_v
        let tmp_i = heap_idxs[pos]
        heap_idxs[pos] = heap_idxs[smallest]
        heap_idxs[smallest] = tmp_i
        pos = smallest
      }
    }
  }
  // Return selected indices (sorted for consistency).
  let result = FixedArray::makei(heap_size, fn(i) { heap_idxs[i] })
  result.sort_by(fn(a, b) { a - b })
  result
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "alias: uniform distribution" {
  let weights = FixedArray::make(4, 1.0)
  let table = build_alias(weights)
  // Each item should have prob ≈ 1.0.
  for i = 0; i < 4; i = i + 1 {
    assert_true(table.prob[i] >= 0.99 && table.prob[i] <= 1.01)
  }
}

///|
test "alias: draw returns valid index" {
  let weights = FixedArray::make(3, 0.0)
  weights[0] = 1.0
  weights[1] = 2.0
  weights[2] = 3.0
  let table = build_alias(weights)
  for i = 0; i < 100; i = i + 1 {
    let r = (i.to_double() + 0.5) / 100.0
    let idx = alias_draw(table, r)
    assert_true(idx >= 0 && idx < 3)
  }
}

///|
test "alias: single item" {
  let weights = FixedArray::make(1, 5.0)
  let table = build_alias(weights)
  assert_eq(alias_draw(table, 0.0), 0)
  assert_eq(alias_draw(table, 0.5), 0)
  assert_eq(alias_draw(table, 0.99), 0)
}

///|
test "weighted_reservoir: sample size k" {
  let weights = FixedArray::make(10, 1.0)
  let result = weighted_reservoir_sample(weights, 3, 42L)
  assert_eq(result.length(), 3)
  // All indices should be valid and unique.
  for i = 0; i < 3; i = i + 1 {
    assert_true(result[i] >= 0 && result[i] < 10)
  }
  assert_true(result[0] != result[1])
  assert_true(result[1] != result[2])
}

///|
test "weighted_reservoir: k >= n returns all" {
  let weights = FixedArray::make(5, 1.0)
  let result = weighted_reservoir_sample(weights, 10, 42L)
  assert_eq(result.length(), 5)
}

///|
test "weighted_reservoir: k = 0 returns empty" {
  let weights = FixedArray::make(5, 1.0)
  let result = weighted_reservoir_sample(weights, 0, 42L)
  assert_eq(result.length(), 0)
}

///|
test "weighted_reservoir: weighted bias" {
  // Item 0 has weight 1000, others have weight 1.
  // Item 0 should almost always be selected.
  let weights = FixedArray::make(10, 1.0)
  weights[0] = 1000.0
  let mut count_0 = 0
  for trial = 0; trial < 100; trial = trial + 1 {
    let result = weighted_reservoir_sample(weights, 1, trial.to_int64())
    if result[0] == 0 {
      count_0 = count_0 + 1
    }
  }
  // Should be selected almost every time (allow for rare misses).
  assert_true(count_0 > 90)
}

///|
test "weighted_reservoir: different seeds produce different results" {
  let weights = FixedArray::makei(100, fn(i) { (i + 1).to_double() })
  let r1 = weighted_reservoir_sample(weights, 5, 42L)
  let r2 = weighted_reservoir_sample(weights, 5, 999L)
  // With 100 items and k=5, different seeds should almost certainly
  // produce different selections.
  let mut different = false
  for i = 0; i < 5; i = i + 1 {
    if r1[i] != r2[i] {
      different = true
      break
    }
  }
  assert_true(different)
}
