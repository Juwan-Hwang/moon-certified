/// Shared hash and numeric utility functions for probabilistic data structures.
///
/// This package consolidates the `fmix64` finalizer (MurmurHash3's avalanche
/// step) that was previously duplicated across `count_min_sketch` and
/// `hyperloglog`. Keeping it in one place ensures bug fixes propagate to all
/// consumers and reduces binary size.
///
/// Also provides `next_pow2` (round up to the next power of 2) and
/// `string_hash` (polynomial rolling hash with DJB2 constants) which are
/// used across multiple container implementations.
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

///|
/// Round up `n` to the next power of 2.
///
/// Returns 1 for n ≤ 1. Useful for sizing hash table buckets and ring
/// buffers to a power of 2 so that modulo can be replaced with `& (cap - 1)`.
///
/// This is a thin delegation to `@utils.next_pow2`: the canonical
/// bit-twiddling implementation lives in the shared `utils` module and is
/// kept in a single place to avoid divergence.
pub fn next_pow2(n : Int) -> Int {
  @utils.next_pow2(n)
}

///|
/// DJB2 string hash — a classic, well-distributed string hash function.
///
/// Uses the polynomial `h = h * 33 + c` with initial value 5381.
/// This is the same algorithm used by the original DJB hash.
pub fn string_hash(s : String) -> Int {
  let mut h = 5381
  for i = 0; i < s.length(); i = i + 1 {
    h = h * 33 + s[i].to_int()
  }
  h
}

///|
/// Polynomial string hash with multiplier 31 (Java `String.hashCode` style).
///
/// Uses `h = h * 31 + c` with initial value 0. This is the same algorithm
/// used by Java's `String.hashCode()`, making it useful for compatibility
/// with Java-based systems.
pub fn poly31_hash(s : String) -> Int {
  let mut h = 0
  for i = 0; i < s.length(); i = i + 1 {
    h = h * 31 + s[i].to_int()
  }
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

///|
test "hash_utils: next_pow2" {
  assert_eq(next_pow2(0), 1)
  assert_eq(next_pow2(1), 1)
  assert_eq(next_pow2(2), 2)
  assert_eq(next_pow2(3), 4)
  assert_eq(next_pow2(5), 8)
  assert_eq(next_pow2(8), 8)
  assert_eq(next_pow2(9), 16)
  assert_eq(next_pow2(100), 128)
  assert_eq(next_pow2(1024), 1024)
  assert_eq(next_pow2(1025), 2048)
}

///|
test "hash_utils: string_hash determinism" {
  assert_eq(string_hash("hello"), string_hash("hello"))
  assert_true(string_hash("hello") != string_hash("world"))
  assert_true(string_hash("") != string_hash("a"))
}

///|
test "hash_utils: poly31_hash determinism" {
  assert_eq(poly31_hash("hello"), poly31_hash("hello"))
  assert_true(poly31_hash("hello") != poly31_hash("world"))
  assert_true(poly31_hash("") != poly31_hash("a"))
}

///|
test "hash_utils: string_hash distribution" {
  // Different strings should produce different hashes (with high probability).
  let strings = ["a", "b", "ab", "ba", "abc", "xyz", "hello", "world"]
  let hashes : Array[Int] = []
  for i = 0; i < strings.length(); i = i + 1 {
    hashes.push(string_hash(strings[i]))
  }
  // Check all are unique.
  for i = 0; i < hashes.length(); i = i + 1 {
    for j = i + 1; j < hashes.length(); j = j + 1 {
      assert_true(hashes[i] != hashes[j])
    }
  }
}
