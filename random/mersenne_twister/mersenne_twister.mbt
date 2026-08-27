///|
/// Mersenne Twister MT19937 — high-quality PRNG.
///
/// The Mersenne Twister is the default PRNG in Python, Ruby, R, and many
/// scientific computing environments. It has a period of 2^19937 − 1 and
/// passes most statistical randomness tests (Diehard, BigCrush).
///
/// ## Algorithm
///
/// Based on a twisted generalized feedback shift register (TGFSR). The
/// state is 624 32-bit words. Each output is temper-transformed.
///
/// ## Complexity
/// - Time:  O(1) amortized per output (624-word batch every 624 calls).
/// - Space: O(624) words of state.
///
/// ## Quality
/// - Period: 2^19937 − 1 (Mersenne prime).
/// - Equidistribution: 623-dimensional.
/// - Passes Diehard and most BigCrush tests.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.
pub struct MT19937 {
  priv mt : FixedArray[UInt]
  priv mut index : Int
}

///|
/// Create a new MT19937 PRNG seeded with `seed`.
pub fn new(seed : UInt) -> MT19937 {
  let mt = FixedArray::make(624, 0U)
  mt[0] = seed
  for i = 1; i < 624; i = i + 1 {
    let prev = mt[i - 1]
    mt[i] = 1812433253U * (prev ^ (prev >> 30)) + i.reinterpret_as_uint()
  }
  { mt, index: 624, }
}

///|
/// Generate the next 32-bit random number.
pub fn next(mt : MT19937) -> UInt {
  if mt.index >= 624 {
    twist(mt)
    mt.index = 0
  }
  let y = mt.mt[mt.index]
  mt.index = mt.index + 1
  // Tempering.
  let y1 = y ^ (y >> 11)
  let y2 = y1 ^ ((y1 << 7) & 0x9D2C5680U)
  let y3 = y2 ^ ((y2 << 15) & 0xEFC60000U)
  y3 ^ (y3 >> 18)
}

///|
/// Generate a random Int in [0, n).
///
/// Uses **rejection sampling** on a 31-bit range to eliminate the modulo
/// bias present in `v % n`. The top bit of the 32-bit output is masked
/// to produce a non-negative Int in [0, 2³¹).
pub fn next_int(mt : MT19937, n : Int) -> Int {
  if n <= 0 {
    return 0
  }
  if n == 1 {
    return 0
  }
  // Rejection sampling: threshold = largest multiple of n ≤ 2³¹.
  let range = 2147483648L // 2³¹
  let n64 = n.to_int64()
  let threshold = range - range % n64
  let mut ok = false
  let mut r = 0
  while !ok {
    r = (next(mt) >> 1).reinterpret_as_int()
    if r.to_int64() < threshold {
      ok = true
    }
  }
  r % n
}

///|
/// Generate a random Double in [0.0, 1.0).
pub fn next_double(mt : MT19937) -> Double {
  let a = (next(mt) >> 5).reinterpret_as_int()
  let b = (next(mt) >> 6).reinterpret_as_int()
  (a.to_double() * 67108864.0 + b.to_double()) * (1.0 / 9007199254740992.0)
}

///|
/// Twist (generate next 624 values).
fn twist(mt : MT19937) -> Unit {
  for i = 0; i < 624; i = i + 1 {
    let x = (mt.mt[i] & 0x80000000U) + (mt.mt[(i + 1) % 624] & 0x7FFFFFFFU)
    let mut xA = x >> 1
    if x % 2U != 0U {
      xA = xA ^ 0x9908B0DFU
    }
    mt.mt[i] = mt.mt[(i + 397) % 624] ^ xA
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "mt19937: deterministic with same seed" {
  let rng1 = new(5489U)
  let rng2 = new(5489U)
  for _ in 0..<100 {
    assert_eq(next(rng1), next(rng2))
  }
}

///|
test "mt19937: different seeds produce different sequences" {
  let rng1 = new(1U)
  let rng2 = new(2U)
  let mut diff = 0
  for _ in 0..<100 {
    if next(rng1) != next(rng2) {
      diff = diff + 1
    }
  }
  assert_true(diff > 90)
}

///|
test "mt19937: next_int in range" {
  let rng = new(42U)
  for _ in 0..<1000 {
    let v = next_int(rng, 100)
    assert_true(v >= 0 && v < 100)
  }
}

///|
test "mt19937: next_double in [0,1)" {
  let rng = new(42U)
  for _ in 0..<1000 {
    let d = next_double(rng)
    assert_true(d >= 0.0 && d < 1.0)
  }
}

///|
test "mt19937: known values (seed=5489)" {
  // Reference values from the original MT19937 implementation.
  let rng = new(5489U)
  let v0 = next(rng)
  let v1 = next(rng)
  let v2 = next(rng)
  // The first few values should be deterministic.
  assert_eq(v0, 3499211612U)
  assert_eq(v1, 581869302U)
  assert_eq(v2, 3890346734U)
}

///|
test "mt19937: period check (no immediate repeat)" {
  let rng = new(12345U)
  let first = next(rng)
  let mut different = true
  for _ in 0..<10000 {
    if next(rng) == first {
      different = false
      break
    }
  }
  assert_true(different)
}

///|
test "mt19937: uniformity" {
  let rng = new(999U)
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
