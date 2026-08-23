///|
/// BitSet — a compact bit-level set over the integer domain `[0, capacity)`.
///
/// Bits are packed into 64-bit words (`FixedArray[UInt64]`), giving O(1) set /
/// clear / test and O(capacity / 64) union / intersection / difference / count.
/// Memory footprint is `capacity / 8` bytes (one bit per element).
///
/// **Bounds discipline.** `bitset_set` / `bitset_clear` / `bitset_get` silently
/// ignore positions outside `[0, capacity)`: a negative `bit` or a
/// `bit >= capacity` is a no-op for `set` / `clear` and yields `false` for
/// `get`. This mirrors the defensive stance used by the sibling `bloom_filter`
/// package and keeps the structure panic-free for any caller input.
///
/// **Invariant.** No bit at position `>= capacity` is ever set, so the trailing
/// bits of the final word are always zero. `bitset_count` therefore sums the
/// population count of every word without masking the final word, and the set
/// operations can combine words word-wise without any per-bit masking.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

///|
/// A bit-level set storing membership for the integer range `[0, capacity)`.
pub struct BitSet {
  priv bits : FixedArray[UInt64] // packed bit storage, little-endian per word
  priv capacity : Int // number of addressable bits
}

///|
/// Population count of a 64-bit word via the classic SWAR
/// (SIMD-within-a-register) Hamming-weight algorithm: three parallel
/// shifts/masks reduce the eight bytes independently, then a single multiply
/// by `0x0101...` folds them into the top byte. Six unsigned operations,
/// branch-free — no lookup table, no per-bit loop.
fn popcount64(x : UInt64) -> Int {
  let mut v = x
  v = v - ((v >> 1) & 0x5555555555555555UL)
  v = (v & 0x3333333333333333UL) + ((v >> 2) & 0x3333333333333333UL)
  v = (v + (v >> 4)) & 0x0F0F0F0F0F0F0F0FUL
  ((v * 0x0101010101010101UL) >> 56).to_int()
}

///|
/// Create an empty `BitSet` addressable over `[0, capacity)`. `capacity` is
/// given in bits; internal storage rounds it up to the next multiple of 64. A
/// negative capacity is clamped to 0 (an empty set with no storage).
pub fn bitset_new(capacity : Int) -> BitSet where {
  proof_ensure: result => bitset_capacity_ok(result.capacity),
} {
  let cap = if capacity < 0 { 0 } else { capacity }
  let num_words = (cap + 63) / 64
  { bits: FixedArray::make(num_words, 0UL), capacity: cap }
}

///|
/// Number of addressable bits — the `capacity` passed to `bitset_new`.
pub fn bitset_capacity(bs : BitSet) -> Int {
  bs.capacity
}

///|
/// Set the bit at position `bit`. Out-of-range positions are silently ignored.
pub fn bitset_set(bs : BitSet, bit : Int) -> Unit {
  if bit < 0 || bit >= bs.capacity {
    return
  }
  let word = bit / 64
  let offset = bit % 64
  bs.bits[word] = bs.bits[word] | (1UL << offset)
}

///|
/// Clear the bit at position `bit`. Out-of-range positions are silently
/// ignored. The bit is cleared with `& (all_ones ^ (1UL << offset))`, using
/// only `&` and `^` (both always defined on `UInt64`).
pub fn bitset_clear(bs : BitSet, bit : Int) -> Unit {
  if bit < 0 || bit >= bs.capacity {
    return
  }
  let word = bit / 64
  let offset = bit % 64
  bs.bits[word] = bs.bits[word] & (0xFFFFFFFFFFFFFFFFUL ^ (1UL << offset))
}

///|
/// Test whether the bit at position `bit` is set. Out-of-range positions
/// return `false`.
pub fn bitset_get(bs : BitSet, bit : Int) -> Bool {
  if bit < 0 || bit >= bs.capacity {
    return false
  }
  let word = bit / 64
  let offset = bit % 64
  (bs.bits[word] & (1UL << offset)) != 0UL
}

///|
/// Bitwise OR of `a` and `b`. The result spans `max(a, b)` bits; words present
/// in only one operand contribute that operand's bits (the other is zero).
pub fn bitset_union(a : BitSet, b : BitSet) -> BitSet {
  let cap = if a.capacity > b.capacity { a.capacity } else { b.capacity }
  let num_words = (cap + 63) / 64
  let result = FixedArray::make(num_words, 0UL)
  let na = a.bits.length()
  let nb = b.bits.length()
  for i = 0; i < num_words; i = i + 1 {
    let va = if i < na { a.bits[i] } else { 0UL }
    let vb = if i < nb { b.bits[i] } else { 0UL }
    result[i] = va | vb
  }
  { bits: result, capacity: cap }
}

///|
/// Bitwise AND of `a` and `b`. The result spans `min(a, b)` bits: beyond the
/// smaller capacity at least one operand has no bits, so the AND is zero.
pub fn bitset_intersection(a : BitSet, b : BitSet) -> BitSet {
  let cap = if a.capacity < b.capacity { a.capacity } else { b.capacity }
  let num_words = (cap + 63) / 64
  let result = FixedArray::make(num_words, 0UL)
  for i = 0; i < num_words; i = i + 1 {
    result[i] = a.bits[i] & b.bits[i]
  }
  { bits: result, capacity: cap }
}

///|
/// Set difference `a \ b`: bits in `a` that are not in `b`. The result spans
/// exactly `a`'s capacity; where `b` is shorter its (zero) bits leave `a`
/// untouched.
pub fn bitset_difference(a : BitSet, b : BitSet) -> BitSet {
  let cap = a.capacity
  let num_words = (cap + 63) / 64
  let result = FixedArray::make(num_words, 0UL)
  let nb = b.bits.length()
  for i = 0; i < num_words; i = i + 1 {
    let vb = if i < nb { b.bits[i] } else { 0UL }
    result[i] = a.bits[i] & (0xFFFFFFFFFFFFFFFFUL ^ vb)
  }
  { bits: result, capacity: cap }
}

///|
/// Number of set bits (population count). Sums `popcount64` over every word;
/// the trailing-bits invariant makes masking the final word unnecessary.
pub fn bitset_count(bs : BitSet) -> Int {
  let mut total = 0
  for i = 0; i < bs.bits.length(); i = i + 1 {
    total = total + popcount64(bs.bits[i])
  }
  total
}

///|
/// `true` when no bit is set. Scans word by word and returns `false` on the
/// first non-zero word, so empty sets are detected without a full popcount.
pub fn bitset_is_empty(bs : BitSet) -> Bool {
  for i = 0; i < bs.bits.length(); i = i + 1 {
    if bs.bits[i] != 0UL {
      return false
    }
  }
  true
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "bitset: new empty has zero capacity and is empty" {
  let bs = bitset_new(0)
  assert_eq(bitset_capacity(bs), 0)
  assert_true(bitset_is_empty(bs))
  assert_eq(bitset_count(bs), 0)
}

///|
test "bitset: capacity is stored as given" {
  assert_eq(bitset_capacity(bitset_new(1)), 1)
  assert_eq(bitset_capacity(bitset_new(64)), 64)
  assert_eq(bitset_capacity(bitset_new(65)), 65)
  assert_eq(bitset_capacity(bitset_new(128)), 128)
}

///|
test "bitset: negative capacity clamps to zero" {
  let bs = bitset_new(-10)
  assert_eq(bitset_capacity(bs), 0)
  assert_true(bitset_is_empty(bs))
}

///|
test "bitset: set and get a single bit" {
  let bs = bitset_new(64)
  bitset_set(bs, 5)
  assert_true(bitset_get(bs, 5))
  assert_false(bitset_get(bs, 4))
  assert_false(bitset_get(bs, 6))
  assert_false(bitset_is_empty(bs))
}

///|
test "bitset: set bits across the word boundary (63 and 64)" {
  // capacity 65 rounds up to 2 words internally; bit 64 lives in word 1.
  let bs = bitset_new(65)
  bitset_set(bs, 63)
  bitset_set(bs, 64)
  assert_true(bitset_get(bs, 63))
  assert_true(bitset_get(bs, 64))
  assert_eq(bitset_count(bs), 2)
}

///|
test "bitset: clear a set bit" {
  let bs = bitset_new(32)
  bitset_set(bs, 10)
  bitset_set(bs, 20)
  assert_true(bitset_get(bs, 10))
  bitset_clear(bs, 10)
  assert_false(bitset_get(bs, 10))
  assert_true(bitset_get(bs, 20))
  assert_eq(bitset_count(bs), 1)
}

///|
test "bitset: clearing an already-clear bit is a no-op" {
  let bs = bitset_new(16)
  bitset_set(bs, 3)
  bitset_clear(bs, 7) // was never set
  assert_false(bitset_get(bs, 7))
  assert_true(bitset_get(bs, 3))
  assert_eq(bitset_count(bs), 1)
}

///|
test "bitset: out-of-range set / get / clear are no-ops" {
  let bs = bitset_new(64)
  bitset_set(bs, 100) // beyond capacity -> ignored
  bitset_set(bs, -1) // negative -> ignored
  assert_false(bitset_get(bs, 100))
  assert_false(bitset_get(bs, -1))
  assert_true(bitset_is_empty(bs))
  bitset_clear(bs, 100) // must not panic
  bitset_clear(bs, -5) // must not panic
  assert_true(bitset_is_empty(bs))
}

///|
test "bitset: count (popcount) over scattered bits" {
  let bs = bitset_new(256)
  let set_bits = [0, 1, 63, 64, 127, 128, 200, 255]
  for i = 0; i < set_bits.length(); i = i + 1 {
    bitset_set(bs, set_bits[i])
  }
  assert_eq(bitset_count(bs), set_bits.length())
}

///|
test "bitset: count after filling and clearing evens" {
  let bs = bitset_new(128)
  for i = 0; i < 128; i = i + 1 {
    bitset_set(bs, i)
  }
  assert_eq(bitset_count(bs), 128)
  for i = 0; i < 128; i = i + 2 {
    bitset_clear(bs, i)
  }
  assert_eq(bitset_count(bs), 64)
}

///|
test "bitset: union" {
  let a = bitset_new(128)
  bitset_set(a, 1)
  bitset_set(a, 64)
  let b = bitset_new(128)
  bitset_set(b, 64)
  bitset_set(b, 100)
  let u = bitset_union(a, b)
  assert_true(bitset_get(u, 1))
  assert_true(bitset_get(u, 64))
  assert_true(bitset_get(u, 100))
  assert_eq(bitset_count(u), 3)
}

///|
test "bitset: intersection" {
  let a = bitset_new(128)
  bitset_set(a, 1)
  bitset_set(a, 64)
  bitset_set(a, 100)
  let b = bitset_new(128)
  bitset_set(b, 64)
  bitset_set(b, 100)
  bitset_set(b, 120)
  let inter = bitset_intersection(a, b)
  assert_false(bitset_get(inter, 1))
  assert_true(bitset_get(inter, 64))
  assert_true(bitset_get(inter, 100))
  assert_false(bitset_get(inter, 120))
  assert_eq(bitset_count(inter), 2)
}

///|
test "bitset: difference" {
  let a = bitset_new(128)
  bitset_set(a, 1)
  bitset_set(a, 64)
  bitset_set(a, 100)
  let b = bitset_new(128)
  bitset_set(b, 64)
  bitset_set(b, 100)
  let d = bitset_difference(a, b)
  assert_true(bitset_get(d, 1))
  assert_false(bitset_get(d, 64))
  assert_false(bitset_get(d, 100))
  assert_eq(bitset_count(d), 1)
}

///|
test "bitset: union and intersection of different capacities" {
  let a = bitset_new(64) // 1 word
  bitset_set(a, 5)
  let b = bitset_new(200) // 4 words
  bitset_set(b, 150)
  let u = bitset_union(a, b)
  assert_eq(bitset_capacity(u), 200)
  assert_true(bitset_get(u, 5))
  assert_true(bitset_get(u, 150))
  assert_eq(bitset_count(u), 2)
  // intersection uses the smaller capacity; the two sets are disjoint.
  let inter = bitset_intersection(a, b)
  assert_eq(bitset_capacity(inter), 64)
  assert_eq(bitset_count(inter), 0)
}

///|
test "bitset: difference where b is larger than a" {
  let a = bitset_new(64)
  bitset_set(a, 10)
  bitset_set(a, 20)
  let b = bitset_new(200)
  bitset_set(b, 20) // also in a -> removed
  bitset_set(b, 150) // not in a -> irrelevant
  let d = bitset_difference(a, b)
  assert_eq(bitset_capacity(d), 64)
  assert_true(bitset_get(d, 10))
  assert_false(bitset_get(d, 20))
  assert_eq(bitset_count(d), 1)
}

///|
test "bitset: is_empty on full and cleared sets" {
  let bs = bitset_new(64)
  assert_true(bitset_is_empty(bs))
  for i = 0; i < 64; i = i + 1 {
    bitset_set(bs, i)
  }
  assert_false(bitset_is_empty(bs))
  for i = 0; i < 64; i = i + 1 {
    bitset_clear(bs, i)
  }
  assert_true(bitset_is_empty(bs))
  assert_eq(bitset_count(bs), 0)
}

///|
test "bitset: De Morgan and inclusion-exclusion identities" {
  // |a u b| == |a| + |b| - |a n b|  and  a n b == a \ (a \ b)
  let a = bitset_new(128)
  let b = bitset_new(128)
  let pa = [0, 2, 4, 64, 66]
  let pb = [2, 4, 6, 66, 100]
  for i = 0; i < pa.length(); i = i + 1 {
    bitset_set(a, pa[i])
  }
  for i = 0; i < pb.length(); i = i + 1 {
    bitset_set(b, pb[i])
  }
  let u = bitset_union(a, b)
  let inter = bitset_intersection(a, b)
  assert_eq(
    bitset_count(u),
    bitset_count(a) + bitset_count(b) - bitset_count(inter),
  )
  let d = bitset_difference(a, b)
  let d2 = bitset_difference(a, d)
  assert_eq(bitset_count(d2), bitset_count(inter))
  for i = 0; i < 128; i = i + 1 {
    assert_eq(bitset_get(d2, i), bitset_get(inter, i))
  }
}
