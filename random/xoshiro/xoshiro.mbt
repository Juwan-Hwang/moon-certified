/// xoshiro256** — Vigna & Blackman (2018).
///
/// A fast, high-quality PRNG from the xoshiro (XOR/shift/rotate) family.
/// It uses 256 bits of state and produces 64-bit outputs. It passes
/// BigCrush and is faster than the Mersenne Twister.
///
/// ## Algorithm
///
/// Uses four 64-bit state words. Each step applies a scrambling function
/// (starstar variant) and then advances the state via XOR-shift operations.
///
/// ## Complexity
/// - Time:  O(1) per output.
/// - Space: O(1) — 256 bits (4 × 64-bit words).
///
/// ## Quality
/// - Period: 2^256 − 1.
/// - Passes BigCrush (no systematic failures).
/// - Very fast: ~1 ns/output on modern hardware.
///
/// Reference: D. Blackman, S. Vigna, "Scrambled Linear Pseudorandom
/// Number Generators" (ACM TOMS, 2021).
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

///|
/// xoshiro256** generator state (4 × 64-bit words).
pub struct Xoshiro256 {
  priv mut s0 : UInt64
  priv mut s1 : UInt64
  priv mut s2 : UInt64
  priv mut s3 : UInt64
}

///|

///|
/// Create a new xoshiro256** generator seeded with `seed`.
///
/// Uses SplitMix64 (via @utils.SplitMix64) to expand the 64-bit seed into
/// four 64-bit state words, avoiding catastrophic seeding with all-zero
/// or sparse states.
pub fn new(seed : UInt64) -> Xoshiro256 {
  let rng = @utils.SplitMix64::new(seed)
  let w0 = rng.next_u64()
  let w1 = rng.next_u64()
  let w2 = rng.next_u64()
  let w3 = rng.next_u64()
  { s0: w0, s1: w1, s2: w2, s3: w3 }
}

///|
/// Left-rotate a 64-bit value by `n` bits.
fn rotl64(x : UInt64, n : Int) -> UInt64 {
  (x << n) | (x >> (64 - n))
}

///|
/// Generate the next 64-bit random number (xoshiro256** output function).
pub fn next(x : Xoshiro256) -> UInt64 {
  let result = rotl64(x.s1 * 5UL, 7) * 9UL
  let t = x.s1 << 17
  x.s2 = x.s2 ^ x.s0
  x.s3 = x.s3 ^ x.s1
  x.s1 = x.s1 ^ x.s2
  x.s0 = x.s0 ^ x.s3
  x.s2 = x.s2 ^ t
  x.s3 = rotl64(x.s3, 45)
  result
}

///|
/// Generate a random Int in [0, n).
pub fn next_int(x : Xoshiro256, n : Int) -> Int {
  if n <= 0 {
    return 0
  }
  let v = next(x)
  (v % n.to_uint64()).to_int()
}

///|
/// Generate a random Double in [0.0, 1.0).
pub fn next_double(x : Xoshiro256) -> Double {
  let v = next(x)
  (v >> 11).to_double() * (1.0 / 9007199254740992.0)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "xoshiro256: deterministic with same seed" {
  let r1 = new(42UL)
  let r2 = new(42UL)
  for _ in 0..<100 {
    assert_eq(next(r1), next(r2))
  }
}

///|
test "xoshiro256: different seeds produce different sequences" {
  let r1 = new(1UL)
  let r2 = new(2UL)
  let mut diff = 0
  for _ in 0..<100 {
    if next(r1) != next(r2) {
      diff = diff + 1
    }
  }
  assert_true(diff > 90)
}

///|
test "xoshiro256: next_int in range" {
  let rng = new(42UL)
  for _ in 0..<1000 {
    let v = next_int(rng, 100)
    assert_true(v >= 0 && v < 100)
  }
}

///|
test "xoshiro256: next_double in [0,1)" {
  let rng = new(42UL)
  for _ in 0..<1000 {
    let d = next_double(rng)
    assert_true(d >= 0.0 && d < 1.0)
  }
}

///|
test "xoshiro256: uniformity" {
  let rng = new(999UL)
  let bins = 10
  let n = 100000
  let hist = FixedArray::make(bins, 0)
  for _ in 0..<n {
    let v = next_int(rng, bins)
    hist[v] = hist[v] + 1
  }
  let expected = n / bins
  for i = 0; i < bins; i = i + 1 {
    let ratio = hist[i].to_double() / expected.to_double()
    assert_true(ratio > 0.9 && ratio < 1.1)
  }
}

///|
test "xoshiro256: no short period" {
  let rng = new(12345UL)
  let first = next(rng)
  let mut repeat = false
  for _ in 0..<100000 {
    if next(rng) == first {
      repeat = true
      break
    }
  }
  assert_false(repeat)
}

///|
test "xoshiro256: zero seed handled (SplitMix64 avoids all-zero state)" {
  let rng = new(0UL)
  // Should not produce all zeros.
  let v = next(rng)
  assert_true(v != 0UL)
}
