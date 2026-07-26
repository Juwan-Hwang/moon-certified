/// Fisher-Yates (Knuth) shuffle.
///
/// The classic in-place algorithm for producing a uniformly random
/// permutation of a `FixedArray[T]`. Also known as the Knuth shuffle, it is
/// the reference algorithm for unbiased shuffling: every one of the n!
/// permutations is generated with exactly equal probability 1/n!.
///
/// Algorithm (Durstenfeld's 1964 in-place variant, the form popularised by
/// Knuth in TAOCP Vol. 2):
///   for i = n - 1 down to 1:
///       j <- random integer uniformly in [0, i]   // inclusive
///       swap xs[i] and xs[j]
/// At step `i` the element destined for position `i` is chosen uniformly from
/// the `i + 1` elements still floating in `xs[0..i]` and then fixed in place.
/// The product of these uniform choices is exactly 1/n!, hence the result is
/// unbiased.
///
/// Randomness is injected by a caller-supplied `rng : () -> Int` returning a
/// non-negative integer; the chosen index is `rng() % (i + 1)`. The default
/// generator built by `make_lcg` is a small linear congruential generator
/// (LCG) with full period 2^31 — multiplier 1103515245 (≡ 1 mod 4) and
/// increment 12345 (odd), satisfying the Hull-Dobell conditions — the same
/// generator used by `reservoir_sampling`, `skip_list`, and `treap` elsewhere
/// in this collection.
///
/// `shuffle_int` is a convenience wrapper that shuffles an `Int` array with a
/// default-seeded LCG, so a single call is deterministic and reproducible;
/// pass `fisher_yates_shuffle` a `make_lcg(seed)` closure for an independently
/// seeded shuffle.
///
/// Complexity:
///   - Time:  O(n)
///   - Space: O(1) auxiliary (in-place; the RNG closure holds one Int of state)
///
/// Properties:
///   - Uniform: every permutation equally likely (given a uniform `rng`).
///   - In-place: no allocation proportional to n.
///   - Not stable.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite, which
/// includes an all-elements-preserved (permutation) check and a chi-square
/// uniformity check over many runs.

// ---------------------------------------------------------------------------
// Internal LCG (Linear Congruential Generator)
// ---------------------------------------------------------------------------

///|
/// LCG multiplier (≡ 1 mod 4) and increment (odd). Together with the
/// `& 0x7FFFFFFF` mask they yield a full-period generator mod 2^31
/// (Hull-Dobell theorem). Because the mask keeps only the low 31 bits, the
/// recurrence is correct mod 2^31 regardless of any wraparound in the wider
/// `Int` product `state * lcg_a + lcg_c`.
let lcg_a : Int = 1103515245

///|
let lcg_c : Int = 12345

///|
/// Default LCG seed. Any fixed non-zero value makes the default `shuffle_int`
/// deterministic and independent of test execution order.
let default_seed : Int = 0x1A2B3C4D

///|
/// Internal mutable LCG state. A private reference type so that a closure can
/// hold on to it and advance it across calls.
priv struct Lcg {
  mut state : Int
}

///|
/// Create an LCG whose state is the seed masked to 31 bits (always
/// non-negative, even for negative or wrapped seeds).
fn Lcg::new(seed : Int) -> Lcg {
  { state: seed & 0x7FFFFFFF }
}

///|
/// Advance the LCG one step and return the new state, a non-negative `Int` in
/// [0, 2^31).
fn Lcg::next(self : Lcg) -> Int {
  self.state = (self.state * lcg_a + lcg_c) & 0x7FFFFFFF
  self.state
}

///|
/// Build a closure-based LCG seeded with `seed`.
///
/// The returned `() -> Int` advances the LCG on each call and yields a
/// non-negative `Int` in [0, 2^31). Distinct closures hold independent state,
/// so they produce independent streams. This is the default RNG used by
/// `shuffle_int` and the recommended way to feed `fisher_yates_shuffle` when
/// no custom generator is needed.
pub fn make_lcg(seed : Int) -> () -> Int {
  let rng = Lcg::new(seed)
  fn() { rng.next() }
}

// ---------------------------------------------------------------------------
// Fisher-Yates shuffle
// ---------------------------------------------------------------------------

///|
/// Swap two elements of a generic array in place.
fn[T] swap(xs : FixedArray[T], i : Int, j : Int) -> Unit {
  let tmp = xs[i]
  xs[i] = xs[j]
  xs[j] = tmp
}

///|
/// Shuffle a `FixedArray[T]` in place using the Fisher-Yates (Knuth)
/// algorithm.
///
/// `rng` must return a non-negative `Int` on each call; the index chosen at
/// step `i` is `(rng() >> 16) % (i + 1)`, uniform over `[0, i]` for a
/// uniform `rng`. The upper 15 bits of the RNG output are used because LCGs
/// have weak low-order bits (Knuth, TAOCP Vol. 2 §3.2.1.1). Arrays of
/// length 0 or 1 are returned unchanged.
pub fn[T] fisher_yates_shuffle(xs : FixedArray[T], rng : () -> Int) -> Unit {
  let n = xs.length()
  if n <= 1 {
    return
  }
  // Walk from the last element down to the second. At each step pick a
  // uniformly random element from the still-unshuffled prefix [0..i] and swap
  // it into position i, fixing it in place.
  let mut i = n - 1
  while i > 0 {
    // Use the high bits of the RNG output to avoid LCG low-bit weakness.
    let j = (rng() >> 16) % (i + 1)
    swap(xs, i, j)
    i = i - 1
  }
}

///|
/// Convenience: shuffle an `Int` array in place using the default-seeded LCG.
///
/// Equivalent to `fisher_yates_shuffle(xs, make_lcg(default_seed))`. The fixed
/// seed makes a single call fully deterministic and reproducible; for an
/// independently seeded shuffle call `fisher_yates_shuffle` directly with a
/// `make_lcg(seed)` closure.
pub fn shuffle_int(xs : FixedArray[Int]) -> Unit {
  fisher_yates_shuffle(xs, make_lcg(default_seed))
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "fisher_yates: basic shuffle" {
  let xs = FixedArray::makei(10, fn(i) { i }) // [0, 1, ..., 9]
  fisher_yates_shuffle(xs, make_lcg(42))
  // Every element must still be a valid index, and collectively they must
  // form a permutation of [0, 10).
  let present = FixedArray::make(10, false)
  for k = 0; k < 10; k = k + 1 {
    assert_true(xs[k] >= 0 && xs[k] < 10)
    present[xs[k]] = true
  }
  for k = 0; k < 10; k = k + 1 {
    assert_true(present[k])
  }
  // A 10-element shuffle with a decent RNG is overwhelmingly likely to move
  // something (P(identity) = 1/10! ≈ 2.8e-7); this guards against a no-op.
  let mut moved = false
  for k = 0; k < 10; k = k + 1 {
    if xs[k] != k {
      moved = true
    }
  }
  assert_true(moved)
}

///|
test "fisher_yates: all elements preserved (permutation)" {
  let n = 100
  let xs = FixedArray::makei(n, fn(i) { (i * 7 + 3) % 97 })
  // Record the original multiset via a frequency table.
  let orig_freq = FixedArray::make(97, 0)
  for k = 0; k < n; k = k + 1 {
    orig_freq[xs[k]] = orig_freq[xs[k]] + 1
  }
  fisher_yates_shuffle(xs, make_lcg(0xC0FFEE))
  // The shuffled array must be a permutation: same length, same frequencies.
  assert_eq(xs.length(), n)
  let new_freq = FixedArray::make(97, 0)
  for k = 0; k < n; k = k + 1 {
    assert_true(xs[k] >= 0 && xs[k] < 97)
    new_freq[xs[k]] = new_freq[xs[k]] + 1
  }
  for k = 0; k < 97; k = k + 1 {
    assert_eq(orig_freq[k], new_freq[k])
  }
}

///|
test "fisher_yates: empty array" {
  let xs = FixedArray::make(0, 0)
  fisher_yates_shuffle(xs, make_lcg(1))
  assert_eq(xs.length(), 0)
}

///|
test "fisher_yates: single element" {
  let xs = FixedArray::make(1, 42)
  fisher_yates_shuffle(xs, make_lcg(1))
  assert_eq(xs[0], 42)
}

///|
test "fisher_yates: two elements" {
  let xs = FixedArray::make(2, 0)
  xs[0] = 10
  xs[1] = 20
  fisher_yates_shuffle(xs, make_lcg(7))
  // The result must be one of the two valid permutations of {10, 20}.
  assert_true((xs[0] == 10 && xs[1] == 20) || (xs[0] == 20 && xs[1] == 10))
}

///|
test "fisher_yates: shuffle_int convenience" {
  let xs = FixedArray::makei(20, fn(i) { i })
  shuffle_int(xs)
  let present = FixedArray::make(20, false)
  for k = 0; k < 20; k = k + 1 {
    assert_true(xs[k] >= 0 && xs[k] < 20)
    present[xs[k]] = true
  }
  for k = 0; k < 20; k = k + 1 {
    assert_true(present[k])
  }
}

///|
test "fisher_yates: reproducible with same seed" {
  let xs1 = FixedArray::makei(15, fn(i) { i })
  let xs2 = FixedArray::makei(15, fn(i) { i })
  fisher_yates_shuffle(xs1, make_lcg(123))
  fisher_yates_shuffle(xs2, make_lcg(123))
  for k = 0; k < 15; k = k + 1 {
    assert_eq(xs1[k], xs2[k])
  }
}

///|
test "fisher_yates: uniform distribution (histogram / chi-square)" {
  // Shuffle a 6-element array many times with distinct seeds and count how
  // often each value lands in each position. A uniform shuffle makes every
  // (position, value) pair appear with probability 1/6; we check the
  // histogram is flat via a chi-square statistic.
  let n = 6
  let runs = 60000
  // hist[pos * n + value] = number of times `value` appeared at `pos`.
  let hist = FixedArray::make(n * n, 0)
  // Use a single LCG with a well-mixed seed so that consecutive shuffles
  // draw from uncorrelated parts of the stream.
  let master_rng = make_lcg(0xDEADBEEF)
  for r = 0; r < runs; r = r + 1 {
    let xs = FixedArray::makei(n, fn(i) { i })
    fisher_yates_shuffle(xs, master_rng)
    for pos = 0; pos < n; pos = pos + 1 {
      hist[pos * n + xs[pos]] = hist[pos * n + xs[pos]] + 1
    }
  }
  // Expected count for each (pos, value) cell = runs / n.
  let expected = runs / n
  let mut chi2 = 0.0
  for pos = 0; pos < n; pos = pos + 1 {
    for value = 0; value < n; value = value + 1 {
      let diff = hist[pos * n + value] - expected
      chi2 = chi2 + diff.to_double() * diff.to_double() / expected.to_double()
    }
  }
  // df = n * (n - 1) = 30; mean ~30, std ~sqrt(60) ≈ 7.75. The threshold 120
  // is ~12 sigma above the mean (false-positive negligible) yet far below the
  // chi2 of any biased implementation, which reaches into the hundreds+.
  assert_true(chi2 < 120.0)
}

///|
test "fisher_yates: generic with String" {
  let xs = FixedArray::make(5, "")
  xs[0] = "cherry"
  xs[1] = "apple"
  xs[2] = "elderberry"
  xs[3] = "date"
  xs[4] = "banana"
  fisher_yates_shuffle(xs, make_lcg(2024))
  assert_eq(xs.length(), 5)
  // Sorting the shuffled array lexicographically must reproduce the sorted
  // original multiset. This verifies the shuffle is a permutation and
  // exercises @test_utils.str_cmp as the comparator.
  let sorted_orig = FixedArray::make(5, "")
  sorted_orig[0] = "apple"
  sorted_orig[1] = "banana"
  sorted_orig[2] = "cherry"
  sorted_orig[3] = "date"
  sorted_orig[4] = "elderberry"
  xs.sort_by(@test_utils.str_cmp)
  for k = 0; k < 5; k = k + 1 {
    assert_true(@test_utils.str_cmp(xs[k], sorted_orig[k]) == 0)
  }
}
