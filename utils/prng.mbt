/// Shared PRNG (Pseudo-Random Number Generator) utilities.
///
/// Provides `SplitMix64` and `XorShift64` — two high-quality, fast 64-bit
/// PRNGs that are used across multiple algorithm packages. Centralising
/// these implementations eliminates code duplication and ensures consistent
/// statistical properties.
///
/// ## SplitMix64
///
/// A splittable PRNG with excellent statistical quality (passes BigCrush).
/// Used for seeding other PRNGs and for general-purpose shuffling where
/// unpredictability is not required.
///
/// Reference: Sebastiano Vigna, "Further scramblings of Marsaglia's xorshift
/// generators" (2014).
///
/// ## XorShift64
///
/// A fast xorshift generator with period 2^64 - 1. Used in Monte Carlo
/// simulations and hash table initialisation where speed matters more than
/// the highest statistical quality.
///
/// Reference: George Marsaglia, "Xorshift RNGs" (2003).

// ---------------------------------------------------------------------------
// SplitMix64
// ---------------------------------------------------------------------------

///|
/// SplitMix64 PRNG state — a single 64-bit word.
///
/// Create with [`SplitMix64::new`] and advance with [`SplitMix64::next_u64`]
/// or [`SplitMix64::next_double`].
pub struct SplitMix64 {
  priv mut state : UInt64
}

///|
/// Create a SplitMix64 PRNG seeded with `seed`.
///
/// A seed of 0 is valid; the first call to `next_u64` will return a
/// non-zero value due to the mixing function.
pub fn SplitMix64::new(seed : UInt64) -> SplitMix64 {
  { state: seed }
}

///|
/// Advance the PRNG and return the next 64-bit pseudo-random value.
pub fn SplitMix64::next_u64(self : SplitMix64) -> UInt64 {
  self.state = self.state + 0x9E3779B97F4A7C15UL
  let mut z = self.state
  z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9UL
  z = (z ^ (z >> 27)) * 0x94D049BB133111EBUL
  z = z ^ (z >> 31)
  z
}

///|
/// Advance the PRNG and return a `Double` uniformly distributed in [0, 1).
///
/// Uses the top 53 bits of the 64-bit output to produce a full-precision
/// `Double` mantissa.
pub fn SplitMix64::next_double(self : SplitMix64) -> Double {
  let v = self.next_u64()
  // Use top 53 bits for full Double precision (2^53 = 9007199254740992).
  (v >> 11).reinterpret_as_int64().to_double() * (1.0 / 9007199254740992.0)
}

// ---------------------------------------------------------------------------
// SplitMix64 — standalone Int64 variant (for packages that store Int64 state)
// ---------------------------------------------------------------------------

///|
/// SplitMix64 golden ratio constant.
const SPLITMIX64_GOLDEN : Int64 = 0x9E3779B97F4A7C15L

///|
/// One step of the SplitMix64 PRNG using `Int64` state.
///
/// Returns `(new_state, output)` where `new_state` is the advanced state
/// (old state + golden ratio) and `output` is the scrambled 64-bit value.
/// Callers store `new_state` back into their state field.
///
/// This function exists so that packages using `Int64` state fields can
/// share the SplitMix64 algorithm without duplicating the mixing constants
/// and scramble logic.
pub fn splitmix64_next(state : Int64) -> (Int64, Int64) {
  let new_state = state + SPLITMIX64_GOLDEN
  // Operate in UInt64 for correct logical (zero-filling) right shifts.
  let mut z = new_state.reinterpret_as_uint64()
  z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9UL
  z = (z ^ (z >> 27)) * 0x94D049BB133111EBUL
  z = z ^ (z >> 31)
  (new_state, z.reinterpret_as_int64())
}

///|
/// One step of SplitMix64 returning a `Double` in [0, 1).
///
/// Returns `(new_state, output)` where `new_state` is the advanced state
/// and `output` is a `Double` uniformly distributed in [0, 1).
pub fn splitmix64_next_double(state : Int64) -> (Int64, Double) {
  let (new_state, z) = splitmix64_next(state)
  // Use top 53 bits for full Double precision (logical shift via UInt64).
  let d = (z.reinterpret_as_uint64() >> 11).reinterpret_as_int64().to_double() *
    (1.0 / 9007199254740992.0)
  (new_state, d)
}

// ---------------------------------------------------------------------------
// XorShift64
// ---------------------------------------------------------------------------

///|
/// XorShift64 PRNG state — a single 64-bit word that must be non-zero.
///
/// Create with [`XorShift64::new`] and advance with [`XorShift64::next_u64`]
/// or [`XorShift64::next_double`].
pub struct XorShift64 {
  priv mut state : UInt64
}

///|
/// Create a XorShift64 PRNG seeded with `seed`.
///
/// A seed of 0 is replaced with a default non-zero seed to avoid the
/// degenerate all-zero state.
pub fn XorShift64::new(seed : UInt64) -> XorShift64 {
  { state: if seed == 0UL { 0xDEADBEEFCAFEBABEUL } else { seed } }
}

///|
/// Advance the PRNG and return the next 64-bit pseudo-random value.
///
/// Uses the classic Marsaglia sequence: `x ^= x << 13; x ^= x >> 7; x ^= x << 17`.
pub fn XorShift64::next_u64(self : XorShift64) -> UInt64 {
  let mut x = self.state
  x = x ^ (x << 13)
  x = x ^ (x >> 7)
  x = x ^ (x << 17)
  self.state = x
  x
}

///|
/// Advance the PRNG and return a `Double` uniformly distributed in [0, 1).
pub fn XorShift64::next_double(self : XorShift64) -> Double {
  let v = self.next_u64()
  // Use top 53 bits for full Double precision (2^53 = 9007199254740992).
  (v >> 11).reinterpret_as_int64().to_double() * (1.0 / 9007199254740992.0)
}

// ---------------------------------------------------------------------------
// XorShift64 — standalone Int64 variant (for packages that store Int64 state)
// ---------------------------------------------------------------------------

///|
/// One step of the XorShift64 PRNG using `Int64` state.
///
/// Returns the new state after applying the classic Marsaglia sequence
/// `x ^= x << 13; x ^= x >> 7; x ^= x << 17`. The caller stores the
/// returned value back into their state field.
pub fn xorshift64_next(state : Int64) -> Int64 {
  let mut x = state
  x = x ^ (x << 13)
  x = x ^ (x >> 7)
  x = x ^ (x << 17)
  x
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "prng: SplitMix64 determinism" {
  let rng = SplitMix64::new(42UL)
  let v1 = rng.next_u64()
  let v2 = rng.next_u64()
  // Same seed → same sequence.
  let rng2 = SplitMix64::new(42UL)
  assert_eq(rng2.next_u64(), v1)
  assert_eq(rng2.next_u64(), v2)
  // Consecutive values differ.
  assert_true(v1 != v2)
}

///|
test "prng: SplitMix64 uniformity" {
  let rng = SplitMix64::new(12345UL)
  let mut below_half = 0
  let total = 10000
  for i = 0; i < total; i = i + 1 {
    let d = rng.next_double()
    assert_true(d >= 0.0 && d < 1.0)
    if d < 0.5 {
      below_half = below_half + 1
    }
  }
  // Should be roughly 50% — allow generous tolerance for a statistical test.
  assert_true(below_half > 4500 && below_half < 5500)
}

///|
test "prng: XorShift64 determinism" {
  let rng = XorShift64::new(42UL)
  let v1 = rng.next_u64()
  let v2 = rng.next_u64()
  let rng2 = XorShift64::new(42UL)
  assert_eq(rng2.next_u64(), v1)
  assert_eq(rng2.next_u64(), v2)
  assert_true(v1 != v2)
}

///|
test "prng: XorShift64 zero seed handled" {
  let rng = XorShift64::new(0UL)
  // Should not produce all zeros.
  let v = rng.next_u64()
  assert_true(v != 0UL)
}

///|
test "prng: XorShift64 uniformity" {
  let rng = XorShift64::new(99999UL)
  let mut below_half = 0
  let total = 10000
  for i = 0; i < total; i = i + 1 {
    let d = rng.next_double()
    assert_true(d >= 0.0 && d < 1.0)
    if d < 0.5 {
      below_half = below_half + 1
    }
  }
  assert_true(below_half > 4500 && below_half < 5500)
}
