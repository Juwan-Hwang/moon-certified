/// Shared hash and numeric utility functions for probabilistic data structures.
///
/// This package consolidates the `fmix64` finalizer (MurmurHash3's avalanche
/// step) that was previously duplicated across `count_min_sketch` and
/// `hyperloglog`. Keeping it in one place ensures bug fixes propagate to all
/// consumers and reduces binary size.
///
/// ## fmix64
///
/// The MurmurHash3 fmix64 finalizer — a fast, high-quality avalanche function
/// that maps a 64-bit integer to a well-distributed 64-bit integer. It uses
/// three xor-shift-multiply rounds with constants derived from the MurmurHash3
/// author's experiments. The function is fully reversible (bijective) and
/// passes the SMHasher test suite with near-zero bias.
///
/// Reference: Austin Appleby, *MurmurHash3*, 2008.
/// https://github.com/aappleby/smhasher

///|
/// MurmurHash3 fmix64 finalizer.
///
/// Applies three xor-shift-multiply rounds to avalanche all input bits into
/// all output bits. This is the standard finalizer used by MurmurHash3 to
/// eliminate patterns in the upper bits of FNV-1a / polynomial hashes.
///
/// Constants: 0xff51afd7ed558ccd and 0xc4ceb9fe1a85ec53 are the recommended
/// values from the MurmurHash3 reference implementation.
pub fn fmix64(input : Int64) -> Int64 {
  let mut h = input
  h = h ^ (h.reinterpret_as_uint64() >> 33).reinterpret_as_int64()
  h = h * 0xff51afd7ed558ccdL
  h = h ^ (h.reinterpret_as_uint64() >> 33).reinterpret_as_int64()
  h = h * 0xc4ceb9fe1a85ec53L
  h = h ^ (h.reinterpret_as_uint64() >> 33).reinterpret_as_int64()
  h
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "hash_utils: fmix64 known values" {
  // fmix64(0) should be 0 (all bits cleared, no avalanche from zero).
  assert_eq(fmix64(0L), 0L)
  // fmix64 is bijective: different inputs produce different outputs.
  assert_true(fmix64(1L) != fmix64(2L))
  assert_true(fmix64(1L) != fmix64(0L))
  // Avalanche: changing one input bit should change ~50% of output bits.
  let h1 = fmix64(0x12345678ABCDEF01L)
  let h2 = fmix64(0x12345678ABCDEF00L) // differ in 1 bit
  let diff = (h1 ^ h2).reinterpret_as_uint64()
  // Count set bits — should be roughly 32 (50% of 64).
  let mut bits = 0
  let mut v = diff
  for i = 0; i < 64; i = i + 1 {
    if (v & 1UL) != 0UL {
      bits = bits + 1
    }
    v = v >> 1
  }
  // Allow [15, 49] to account for statistical variation.
  assert_true(bits >= 15 && bits <= 49)
}

///|
test "hash_utils: fmix64 determinism" {
  // Same input always produces same output.
  assert_eq(fmix64(42L), fmix64(42L))
  assert_eq(fmix64(-1L), fmix64(-1L))
}
