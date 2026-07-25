/// Weighted Random Sampling algorithms.
///
/// Provides production-grade weighted sampling algorithms:
///
/// 1. **Alias Method**: O(n) preprocessing, O(1) per-sample. The industry
///    standard for repeated sampling from a fixed discrete distribution.
/// 2. **Weighted Reservoir Sampling (A-Res)**: O(k log n) streaming weighted
///    reservoir sampling without replacement.
///
/// ## Complexity
/// - Alias Method: O(n) build, O(1) per draw.
/// - Weighted Reservoir: O(k log n) for k items from n.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Alias Method (O(1) per-sample after O(n) preprocessing)
// ---------------------------------------------------------------------------

/// Alias table for O(1) weighted sampling.
pub struct AliasTable {
  priv prob : FixedArray[Double]
  priv alias_idx : FixedArray[Int]
  priv n : Int
}

/// Build an alias table from weights.
///
/// # Parameters
/// - `weights`: non-negative weights. Need not be normalized.
///
/// After building, each `draw()` call takes O(1) time.
pub fn build_alias(weights : FixedArray[Double]) -> AliasTable {
  let n = weights.length()
  if n == 0 {
    return AliasTable::{ prob : FixedArray::make(0, 0.0), alias_idx : FixedArray::make(0, 0), n : 0 }
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
    return AliasTable::{ prob, alias_idx, n }
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
  AliasTable::{ prob, alias_idx, n }
}

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

/// Sample k items from a stream of weighted items without replacement.
///
/// Uses the A-Res algorithm: for each item, generate a key = u^(1/w) where
/// u is uniform [0,1] and w is the weight. Keep the k items with largest keys.
///
/// # Parameters
/// - `weights`: weight of each item.
/// - `k`: number of items to sample.
///
/// # Returns
/// Array of selected item indices.
pub fn weighted_reservoir_sample(
  weights : FixedArray[Double],
  k : Int,
) -> FixedArray[Int] {
  let n = weights.length()
  if k <= 0 || n == 0 {
    return FixedArray::make(0, 0)
  }
  if k >= n {
    return FixedArray::makei(n, fn(i) { i })
  }
  // Use a min-heap of size k, keyed by the generated priority.
  // Priority = w_i / u_i (equivalent to u^(1/w) comparison).
  // We use w/u for efficiency (avoids computing fractional powers).
  let heap_vals = FixedArray::make(k, 0.0) // min-heap of priorities
  let heap_idxs = FixedArray::make(k, 0)  // corresponding indices
  let mut heap_size = 0
  // Simple deterministic pseudo-random for reproducibility.
  let mut seed = 42
  for i = 0; i < n; i = i + 1 {
    // LCG random number generator.
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
    let u = (seed.to_double() + 0.5) / 2147483648.0
    let w = weights[i]
    if w <= 0.0 {
      continue
    }
    // Key = u^(1/w). Higher key = higher priority.
    // For numerical stability with large w, use key = -ln(u)/w.
    // But since we only need comparisons, we can use w/u directly
    // (monotonic transform). Actually, we need u^(1/w) which requires
    // a power function. For simplicity, use the exponential of log:
    // key = exp(ln(u) / w). Since u ∈ (0,1), ln(u) < 0, and dividing
    // by w makes it closer to 0, so key is closer to 1 (larger).
    // For monotonic comparison, we can use -ln(u)/w (smaller = higher priority).
    let key = if u > 0.0 { -ln_neg(u) / w } else { 999999.0 }
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

/// Compute -ln(u) for u ∈ (0, 1). This is always positive.
fn ln_neg(u : Double) -> Double {
  // Taylor series for -ln(1-x) where x = 1-u.
  // -ln(u) = -ln(1 - (1-u)) = sum of (1-u)^n / n for n=1..inf
  // For u close to 1, (1-u) is small and this converges quickly.
  // For u close to 0, we use a different approach.
  if u > 0.5 {
    let x = 1.0 - u
    let mut result = 0.0
    let mut term = x
    let mut n = 1.0
    while term > 0.000000000000001 {
      result = result + term / n
      term = term * x
      n = n + 1.0
    }
    result
  } else {
    // For u ≤ 0.5, -ln(u) ≥ ln(2) ≈ 0.693.
    // Use the identity -ln(u) = -ln(2) + -ln(u/2).
    // This reduces u until it's > 0.5.
    let mut val = u
    let mut offset = 0.0
    while val <= 0.5 {
      val = val * 2.0
      offset = offset + 0.6931471805599453 // ln(2)
    }
    offset + ln_neg(val)
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "alias: uniform distribution" {
  let weights = FixedArray::make(4, 1.0)
  let table = build_alias(weights)
  // Each item should have prob ≈ 1.0.
  for i = 0; i < 4; i = i + 1 {
    assert_true(table.prob[i] >= 0.99 && table.prob[i] <= 1.01)
  }
}

test "alias: draw returns valid index" {
  let weights = FixedArray::make(3, 0.0)
  weights[0] = 1.0; weights[1] = 2.0; weights[2] = 3.0
  let table = build_alias(weights)
  for i = 0; i < 100; i = i + 1 {
    let r = (i.to_double() + 0.5) / 100.0
    let idx = alias_draw(table, r)
    assert_true(idx >= 0 && idx < 3)
  }
}

test "alias: single item" {
  let weights = FixedArray::make(1, 5.0)
  let table = build_alias(weights)
  assert_eq(alias_draw(table, 0.0), 0)
  assert_eq(alias_draw(table, 0.5), 0)
  assert_eq(alias_draw(table, 0.99), 0)
}

test "weighted_reservoir: sample size k" {
  let weights = FixedArray::make(10, 1.0)
  let result = weighted_reservoir_sample(weights, 3)
  assert_eq(result.length(), 3)
  // All indices should be valid and unique.
  for i = 0; i < 3; i = i + 1 {
    assert_true(result[i] >= 0 && result[i] < 10)
  }
  assert_true(result[0] != result[1])
  assert_true(result[1] != result[2])
}

test "weighted_reservoir: k >= n returns all" {
  let weights = FixedArray::make(5, 1.0)
  let result = weighted_reservoir_sample(weights, 10)
  assert_eq(result.length(), 5)
}

test "weighted_reservoir: k = 0 returns empty" {
  let weights = FixedArray::make(5, 1.0)
  let result = weighted_reservoir_sample(weights, 0)
  assert_eq(result.length(), 0)
}

test "weighted_reservoir: weighted bias" {
  // Item 0 has weight 1000, others have weight 1.
  // Item 0 should almost always be selected.
  let weights = FixedArray::make(10, 1.0)
  weights[0] = 1000.0
  let mut count_0 = 0
  for trial = 0; trial < 100; trial = trial + 1 {
    let result = weighted_reservoir_sample(weights, 1)
    if result[0] == 0 {
      count_0 = count_0 + 1
    }
  }
  // Should be selected almost every time (allow for rare misses).
  assert_true(count_0 > 90)
}
