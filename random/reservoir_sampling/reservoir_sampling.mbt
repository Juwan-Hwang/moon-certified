/// Reservoir Sampling (Algorithm R).
///
/// Selects `k` items uniformly at random from a stream of unknown length in
/// O(n) time and O(k) space, where `n` is the number of elements observed.
/// The stream need not fit in memory: only the `k`-slot reservoir is retained.
///
/// Algorithm R (Waterman):
///   1. Fill the reservoir with the first `k` items.
///   2. For each subsequent item — the `m`-th overall (m > k, 1-based) — draw a
///      random integer `j` uniformly from `[0, m)`. If `j < k`, replace
///      `reservoir[j]` with the new item.
///
/// The probability that the `m`-th item is admitted is `k / m`, and by
/// induction every one of the first `m` items is in the reservoir with
/// probability `k / m` after step `m`. At the end of an `n`-item stream each
/// element is present with probability exactly `k / n` — a uniform sample.
///
/// Randomness comes from a tiny inline linear congruential generator (LCG),
///   state = state * 1103515245 + 12345  (mod 2^31)
/// the same generator used by `skip_list` and `treap` elsewhere in this
/// collection. It is full-period (2^31) because the multiplier is `1 (mod 4)`
/// and the increment is odd (Hull–Dobell). Random indices are mapped into
/// `[0, m)` with Lemire's fast-range method `(state * m) >> 31`, which uses the
/// *high* bits of the state; this sidesteps the poor low-bit behaviour typical
/// of LCGs and keeps the selection probability within `~m / 2^31` of perfectly
/// uniform.
///
/// `new` seeds the LCG with a fixed constant so a given run is deterministic
/// and independent of test execution order. `with_seed` allows callers (and the
/// uniformity test below) to draw independent samples by varying the seed.
///
/// Complexity:
/// - `add`       — O(1) expected
/// - `add_many`  — O(len items)
/// - `result`    — O(k)
/// - `count`     — O(1)
///
/// Not formally verified. Correctness is ensured by the comprehensive test
/// suite below, including a chi-square uniformity check over 10 000 runs.

///|
/// Default LCG seed for `new`. Any fixed non-zero value makes every default
/// sampler deterministic; `with_seed` overrides it for reproducible variety.
let default_seed : Int = 0x1A2B3C4D

///|
/// A reservoir sampler holding up to `capacity` (k) items of type `T`.
///
/// `reservoir` stores the current sample, `seen` counts every element
/// observed (including those discarded), and `rng` is the mutable LCG state.
pub struct ReservoirSampler[T] {
  priv reservoir : Array[T]
  priv capacity : Int
  priv mut seen : Int
  priv mut rng : Int
}

///|
/// Create a sampler that maintains a sample of `capacity` items.
///
/// A `capacity <= 0` produces a sampler that tracks the count but never
/// retains any element (`result` is always empty).
pub fn[T] new(capacity : Int) -> ReservoirSampler[T] {
  with_seed(capacity, default_seed)
}

///|
/// Create a sampler with an explicit LCG `seed`.
///
/// Distinct seeds yield statistically independent samples, which is what the
/// uniformity test relies on to average selection frequencies over many runs.
pub fn[T] with_seed(capacity : Int, seed : Int) -> ReservoirSampler[T] {
  let cap = if capacity > 0 { capacity } else { 0 }
  {
    reservoir: [],
    capacity: cap,
    seen: 0,
    // Mask to 31 bits so the state is always non-negative regardless of the
    // sign of `seed` (callers may pass wrapped/negative seeds).
    rng: seed & 0x7FFFFFFF,
  }
}

///|
/// Advance the LCG one step and map the result uniformly into `[0, m)`.
///
/// Lemire's method `(state * m) >> 31` uses the high bits of `state`, avoiding
/// the low-bit correlations of an LCG. The `Int64` intermediate prevents the
/// `state * m` product from overflowing 32-bit `Int` for large `m`.
fn[T] rand_below(sampler : ReservoirSampler[T], m : Int) -> Int {
  sampler.rng = @utils.lcg_next(sampler.rng)
  ((sampler.rng.to_int64() * m.to_int64()) >> 31).to_int()
}

///|
/// Process one stream element. O(1) expected.
///
/// The first `capacity` elements fill the reservoir directly. Every later
/// element — the `m`-th seen, `m > capacity` — competes for a slot with
/// probability `capacity / m`.
pub fn[T] add(sampler : ReservoirSampler[T], item : T) -> Unit {
  let m = sampler.seen + 1
  if sampler.reservoir.length() < sampler.capacity {
    sampler.reservoir.push(item)
  } else if sampler.capacity > 0 {
    // Replacement phase: m is the 1-based index of the current item.
    let j = rand_below(sampler, m)
    if j < sampler.capacity {
      sampler.reservoir[j] = item
    }
  }
  sampler.seen = m
}

///|
/// Process a batch of stream elements in order. O(len items).
pub fn[T] add_many(sampler : ReservoirSampler[T], items : Array[T]) -> Unit {
  for i = 0; i < items.length(); i = i + 1 {
    add(sampler, items[i])
  }
}

///|
/// Return a copy of the sampled items. O(k).
///
/// A fresh `Array` is returned so callers cannot mutate the sampler's internal
/// reservoir through the result.
pub fn[T] result(sampler : ReservoirSampler[T]) -> Array[T] {
  let out : Array[T] = []
  for i = 0; i < sampler.reservoir.length(); i = i + 1 {
    out.push(sampler.reservoir[i])
  }
  out
}

///|
/// Number of stream elements observed so far. O(1).
pub fn[T] count(sampler : ReservoirSampler[T]) -> Int {
  sampler.seen
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "reservoir: empty stream" {
  let s : ReservoirSampler[Int] = new(5)
  assert_eq(count(s), 0)
  assert_eq(result(s).length(), 0)
}

///|
test "reservoir: stream shorter than capacity keeps all items" {
  let s : ReservoirSampler[Int] = new(5)
  add(s, 10)
  add(s, 20)
  add(s, 30)
  assert_eq(count(s), 3)
  let r = result(s)
  assert_eq(r.length(), 3)
  // Below capacity no replacement can occur, so every item is retained.
  let mut has10 = false
  let mut has20 = false
  let mut has30 = false
  for i = 0; i < r.length(); i = i + 1 {
    if r[i] == 10 {
      has10 = true
    }
    if r[i] == 20 {
      has20 = true
    }
    if r[i] == 30 {
      has30 = true
    }
  }
  assert_true(has10)
  assert_true(has20)
  assert_true(has30)
}

///|
test "reservoir: stream exactly capacity" {
  let s : ReservoirSampler[Int] = new(5)
  for i = 0; i < 5; i = i + 1 {
    add(s, i)
  }
  assert_eq(count(s), 5)
  let r = result(s)
  assert_eq(r.length(), 5)
  // With exactly capacity items the reservoir is the whole stream, in order.
  for i = 0; i < 5; i = i + 1 {
    assert_eq(r[i], i)
  }
}

///|
test "reservoir: stream longer than capacity" {
  let s : ReservoirSampler[Int] = new(3)
  for i = 0; i < 10; i = i + 1 {
    add(s, i)
  }
  assert_eq(count(s), 10)
  let r = result(s)
  assert_eq(r.length(), 3)
  // Every retained item must come from the stream [0, 10) and be distinct
  // (the stream has no duplicates, so neither can the reservoir).
  let present = FixedArray::make(10, false)
  for i = 0; i < r.length(); i = i + 1 {
    assert_true(r[i] >= 0 && r[i] < 10)
    assert_false(present[r[i]])
    present[r[i]] = true
  }
}

///|
test "reservoir: uniform distribution (chi-square)" {
  let n = 20
  let k = 5
  let runs = 10000
  let freq = FixedArray::make(n, 0)
  for r = 0; r < runs; r = r + 1 {
    // A distinct, well-spread seed per run yields independent samples.
    let s : ReservoirSampler[Int] = with_seed(k, @utils.lcg_next(r + 1))
    for i = 0; i < n; i = i + 1 {
      add(s, i)
    }
    let sample = result(s)
    for j = 0; j < sample.length(); j = j + 1 {
      freq[sample[j]] = freq[sample[j]] + 1
    }
  }
  // Total selections must equal runs * k.
  let mut total = 0
  for i = 0; i < n; i = i + 1 {
    total = total + freq[i]
  }
  assert_eq(total, runs * k)
  // Chi-square goodness of fit. Expected count per element = runs * k / n.
  let expected = runs * k / n
  let mut chi2 = 0.0
  for i = 0; i < n; i = i + 1 {
    let diff = freq[i] - expected
    chi2 = chi2 + diff.to_double() * diff.to_double() / expected.to_double()
  }
  // df = n - 1 = 19; a correct implementation gives chi2 ~ 19. The threshold
  // 80 is ~13 sigma above the mean (false-positive ~1e-15) yet far below the
  // chi2 of any biased implementation (which reaches into the hundreds+).
  assert_true(chi2 < 80.0)
}

///|
test "reservoir: count tracking" {
  let s : ReservoirSampler[Int] = new(4)
  assert_eq(count(s), 0)
  add(s, 1)
  assert_eq(count(s), 1)
  add(s, 2)
  add(s, 3)
  assert_eq(count(s), 3)
  add_many(s, [4, 5, 6, 7, 8])
  assert_eq(count(s), 8)
  add_many(s, [])
  assert_eq(count(s), 8)
}

///|
test "reservoir: large stream 100000 elements k=10" {
  let s : ReservoirSampler[Int] = new(10)
  for i = 0; i < 100000; i = i + 1 {
    add(s, i)
  }
  assert_eq(count(s), 100000)
  let r = result(s)
  assert_eq(r.length(), 10)
  // All sampled items are valid stream elements and mutually distinct.
  let present = FixedArray::make(100000, false)
  for i = 0; i < r.length(); i = i + 1 {
    assert_true(r[i] >= 0 && r[i] < 100000)
    assert_false(present[r[i]])
    present[r[i]] = true
  }
}

///|
test "reservoir: generic type with String keys" {
  let s : ReservoirSampler[String] = new(3)
  let words = ["alpha", "beta", "gamma", "delta", "epsilon", "zeta"]
  add_many(s, words)
  assert_eq(count(s), 6)
  let r = result(s)
  assert_eq(r.length(), 3)
  // Every retained item must be one of the input words.
  for i = 0; i < r.length(); i = i + 1 {
    let mut found = false
    for j = 0; j < words.length(); j = j + 1 {
      if r[i] == words[j] {
        found = true
      }
    }
    assert_true(found)
  }
}
