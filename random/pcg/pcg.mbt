/// PCG (Permuted Congruential Generator) — O'Neill 2014.
///
/// PCG is a family of fast, statistically excellent PRNGs that outperform
/// the Mersenne Twister in quality while using far less state (128 bits).
/// It passes BigCrush and PractRand with no failures.
///
/// ## Algorithm
///
/// PCG uses a linear congruential generator (LCG) for state transition,
/// but applies a non-linear permutation (output function) to produce
/// high-quality output bits. This separates state evolution from output
/// generation, fixing the main weakness of traditional LCGs.
///
/// ## Complexity
/// - Time:  O(1) per output.
/// - Space: O(1) — just two 64-bit words (state + stream).
///
/// ## Quality
/// - Period: 2^64.
/// - Passes BigCrush and PractRand.
/// - Multiple streams: each `stream` parameter gives an independent sequence.
///
/// Reference: Melissa E. O'Neill, "PCG, A Family of Simple Fast
/// Space-Efficient Statistically Good Algorithms for Random Number
/// Generation" (2014).
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

///|
/// PCG32 generator state.
///
/// Uses 64-bit state with 32-bit output via the PCG-XSH-RR scheme.
/// Default multiplier and increment follow the PCG reference.
pub struct PCG32 {
  priv mut state : UInt64
  priv increment : UInt64
}

///|
/// Default multiplier for 64-bit LCG state transition.
let pcg_mult : UInt64 = 6364136223846793005UL

///|
/// Default increment for the default stream (odd, as required).
let pcg_default_inc : UInt64 = 1442695040888963407UL

///|
/// Create a new PCG32 with the given seed and stream.
///
/// `seed` sets the initial state; `stream` selects which independent
/// stream to use (must be odd for full-period; even values are forced odd).
pub fn new(seed : UInt64, stream : UInt64) -> PCG32 {
  let inc = (stream << 1) | 1UL
  let pcg = { state: 0UL, increment: inc }
  // Initialize: state = 0; next(); state += seed; next();
  pcg.state = pcg.state * pcg_mult + pcg.increment
  pcg.state = pcg.state + seed
  pcg.state = pcg.state * pcg_mult + pcg.increment
  pcg
}

///|
/// Create a PCG32 with a default stream.
pub fn new_default(seed : UInt64) -> PCG32 {
  new(seed, pcg_default_inc)
}

///|
/// Generate the next 32-bit random number using PCG-XSH-RR.
pub fn next(pcg : PCG32) -> UInt {
  let oldstate = pcg.state
  // State transition: state = state * mult + inc
  pcg.state = oldstate * pcg_mult + pcg.increment
  // Output function: XSH-RR (xor-shift, random rotation)
  let xorshifted = ((oldstate >> 18) ^ oldstate) >> 27
  let rot = (oldstate >> 59).to_int()
  let result = (xorshifted >> rot) | (xorshifted << (-rot & 31))
  // Take low 32 bits
  (result & 0xFFFFFFFFUL).to_uint()
}

///|
/// Generate a random Int in [0, n).
///
/// Uses **rejection sampling** on a 31-bit range to eliminate the modulo
/// bias present in `v % n`. The top bit of the 32-bit output is masked
/// to produce a non-negative Int in [0, 2³¹).
pub fn next_int(pcg : PCG32, n : Int) -> Int {
  if n <= 0 {
    return 0
  }
  if n == 1 {
    return 0
  }
  // Rejection sampling: threshold = largest multiple of n ≤ 2³¹.
  let range = 2147483648L // 2³¹
  let n64 = n.to_int64()
  let threshold = range - (range % n64)
  let mut ok = false
  let mut r = 0
  while !ok {
    r = (next(pcg) >> 1).reinterpret_as_int()
    if r.to_int64() < threshold {
      ok = true
    }
  }
  r % n
}

///|
/// Generate a random Double in [0.0, 1.0).
pub fn next_double(pcg : PCG32) -> Double {
  let v = next(pcg)
  v.to_double() * (1.0 / 4294967296.0)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "pcg32: deterministic with same seed" {
  let r1 = new_default(42UL)
  let r2 = new_default(42UL)
  for _ in 0..<100 {
    assert_eq(next(r1), next(r2))
  }
}

///|
test "pcg32: different seeds produce different sequences" {
  let r1 = new_default(1UL)
  let r2 = new_default(2UL)
  let mut diff = 0
  for _ in 0..<100 {
    if next(r1) != next(r2) {
      diff = diff + 1
    }
  }
  assert_true(diff > 90)
}

///|
test "pcg32: different streams produce different sequences" {
  let r1 = new(42UL, 1UL)
  let r2 = new(42UL, 2UL)
  let mut diff = 0
  for _ in 0..<100 {
    if next(r1) != next(r2) {
      diff = diff + 1
    }
  }
  assert_true(diff > 90)
}

///|
test "pcg32: next_int in range" {
  let rng = new_default(42UL)
  for _ in 0..<1000 {
    let v = next_int(rng, 100)
    assert_true(v >= 0 && v < 100)
  }
}

///|
test "pcg32: next_double in [0,1)" {
  let rng = new_default(42UL)
  for _ in 0..<1000 {
    let d = next_double(rng)
    assert_true(d >= 0.0 && d < 1.0)
  }
}

///|
test "pcg32: uniformity" {
  let rng = new_default(999UL)
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
test "pcg32: no short period" {
  let rng = new_default(12345UL)
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
