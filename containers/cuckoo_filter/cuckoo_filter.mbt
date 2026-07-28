/// Cuckoo filter for probabilistic set membership testing with deletion.
///
/// Unlike a Bloom filter, a cuckoo filter stores a small **fingerprint** of
/// each element (not just bits) in one of two candidate buckets, so a present
/// element can be located and removed. It uses **partial-key cuckoo hashing**
/// (Fan et al., 2014): the fingerprint `f` of a key is stored in either bucket
/// `i1` or bucket `i2`, where
///   i1 = hash(key) mod num_buckets
///   i2 = i1 XOR hash(f)
/// Because XOR is self-inverse, `i1 = i2 XOR hash(f)` too, so the *alternate*
/// bucket of any fingerprint can be recomputed from the fingerprint alone —
/// this is what lets a kicked fingerprint be relocated without its original
/// key.
///
/// For the XOR trick to be a true involution (so a second kick returns a
/// fingerprint to a findable bucket), the bucket count is rounded up to a
/// power of two and indexing uses bit-masking. Then
///   alt(i, f) = (i XOR hash(f)) AND (num_buckets - 1)
/// satisfies `alt(alt(i, f), f) = i` exactly, since masking commutes with XOR
/// on the low bits and clears the sign.
///
/// Insertion conflict resolution is standard cuckoo kicking: when both
/// candidate buckets of a fingerprint are full, a victim slot is chosen at
/// random, its occupant is evicted and re-inserted into its own alternate
/// bucket, and so on. Kicking is bounded by `CF_MAX_KICKS` (500); exhausting
/// it reports the table as full (`add` returns `false`).
///
/// Properties:
/// - No false negatives (a present element is always found), *unless* an
///   `add` failure has displaced a previously inserted fingerprint — a known
///   cuckoo-filter trade-off signalled by `add` returning `false`.
/// - False positives are possible: a non-member whose fingerprint collides
///   with a stored one and hashes into one of its two buckets is reported
///   present. With 32-bit fingerprints the rate is negligible.
/// - `remove` deletes *one* occurrence of a key. Removing a non-member that
///   falsely tests positive can delete an unrelated entry — only delete keys
///   you have actually added.
///
/// Complexity (expected):
/// - `add`      — O(1) amortised, O(CF_MAX_KICKS) worst case
/// - `contains` — O(bucket_size)
/// - `remove`   — O(bucket_size)
/// - `size`     — O(1)
///
/// Not formally verified. Correctness is ensured by the comprehensive test
/// suite below.

// ---------------------------------------------------------------------------
// Data structure
// ---------------------------------------------------------------------------

///|
/// A cuckoo filter.
///
/// - `buckets` is a `capacity`-element `FixedArray`, each entry a
///   `bucket_size`-element `FixedArray[Int]` of fingerprints. A slot holds `0`
///   when empty, so fingerprints are forced non-zero by [`make_fingerprint`].
///   Each bucket array is allocated independently (via `makei`) so the buckets
///   do not alias a shared inner array.
/// - `capacity` is the bucket count, always a power of two (rounded up from
///   the user's request) so the XOR alternate-index is an exact involution.
/// - `bucket_size` is the fingerprints per bucket (b = 4 is typical).
/// - `count` is the number of successful inserts minus successful deletes.
/// - `rng` is the mutable LCG state used to pick random victim slots.
pub struct CuckooFilter {
  priv buckets : FixedArray[FixedArray[Int]]
  priv capacity : Int
  priv bucket_size : Int
  priv mut count : Int
  priv mut rng : Int
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

///|
/// Seed for the index hash `hash(key)`. `0x5bd1e995` is the MurmurHash2
/// mixing constant; it fits in a positive 32-bit `Int`.
const CF_INDEX_SEED : Int = 0x5bd1e995

///|
/// Seed for the fingerprint hash. Distinct from `CF_INDEX_SEED` so the index
/// and fingerprint of a key are effectively independent.
const CF_FP_SEED : Int = 0x1b873593

///|
/// Avalanche mixing constant (same one used by the bloom filter in this
/// collection). `0x45d9f3b = 73_260_923` is an odd multiplier, so it is
/// coprime to `2^32` and preserves full period when iterated.
const CF_MIX : Int = 0x45d9f3b

///|
/// Fixed LCG seed so every default filter behaves deterministically and
/// independently of test execution order.
const CF_RNG_SEED : Int = 0x1A2B3C4D

///|
/// Maximum number of cuckoo kicks per insert before declaring the table full.
/// 500 is the value used by the original cuckoo filter paper.
const CF_MAX_KICKS : Int = 500

// ---------------------------------------------------------------------------
// Hashing
// ---------------------------------------------------------------------------

///|
/// Polynomial rolling hash with a seed, followed by avalanche mixing.
///   h = seed; for each byte b: h = h * 31 + b
/// then xor-shift-multiply. The avalanche step decorrelates seed-varied
/// hashes and diffuses high bits into low bits so masking to a bucket index
/// keeps good distribution.
///
/// Uses **unsigned** right shift in the avalanche (via `reinterpret_as_uint`)
/// to avoid sign-extension when `h` is negative — the same rationale as the
/// bloom filter's `hash`.
fn hash_key(key : String, seed : Int) -> Int {
  let mut h = seed
  for i = 0; i < key.length(); i = i + 1 {
    h = h * 31 + key[i].to_int()
  }
  h = h ^ (h.reinterpret_as_uint() >> 16).reinterpret_as_int()
  h = h * CF_MIX
  h = h ^ (h.reinterpret_as_uint() >> 16).reinterpret_as_int()
  h
}

///|
/// Avalanche-mix a fingerprint integer into a well-distributed `Int`.
///
/// This is the "partial key" hash: it depends only on the fingerprint `f`,
/// not on the original key, which is precisely what allows a kicked
/// fingerprint to recompute its alternate bucket.
fn hash_fp(f : Int) -> Int {
  let mut h = f
  h = h ^ (h.reinterpret_as_uint() >> 16).reinterpret_as_int()
  h = h * CF_MIX
  h = h ^ (h.reinterpret_as_uint() >> 16).reinterpret_as_int()
  h
}

///|
/// Fingerprint of a key: a non-zero `Int`.
///
/// `0` is reserved as the empty-slot marker, so a hash that avalanches to `0`
/// is mapped to `1`. Two keys colliding here is the sole source of false
/// positives; with the full 32-bit `Int` this is astronomically rare.
fn make_fingerprint(key : String) -> Int {
  let f = hash_key(key, CF_FP_SEED)
  if f == 0 {
    1
  } else {
    f
  }
}

// ---------------------------------------------------------------------------
// Indexing
// ---------------------------------------------------------------------------

///|
/// Primary bucket index of `key`: the masked index hash. Because `capacity`
/// is a power of two, `& (capacity - 1)` is a non-negative modulo that also
/// clears the sign bit of a negative hash.
fn index1(cf : CuckooFilter, key : String) -> Int {
  hash_key(key, CF_INDEX_SEED) & (cf.capacity - 1)
}

///|
/// Alternate bucket index of a fingerprint stored at index `i`.
///
///   alt(i, f) = (i XOR hash(f)) AND (capacity - 1)
///
/// Involutivity: masking commutes with XOR on the low bits, so
/// `alt(alt(i, f), f) = i`. This guarantees a kicked fingerprint always lands
/// in one of its two valid buckets and remains findable.
fn alt_index(i : Int, f : Int, capacity : Int) -> Int {
  (i ^ hash_fp(f)) & (capacity - 1)
}

// ---------------------------------------------------------------------------
// Random victim selection (inline LCG, Lemire range mapping)
// ---------------------------------------------------------------------------

///|
/// Advance the LCG one step and map the result uniformly into `[0, m)`.
///
/// Lemire's method `(state * m) >> 31` uses the high bits of the state,
/// avoiding the poor low-bit correlations of an LCG. The `Int64` intermediate
/// prevents `state * m` from overflowing 32-bit `Int` for large `m`.
fn rand_below(cf : CuckooFilter, m : Int) -> Int {
  cf.rng = @utils.lcg_next(cf.rng)
  ((cf.rng.to_int64() * m.to_int64()) >> 31).to_int()
}

// ---------------------------------------------------------------------------
// Bucket slot helpers
// ---------------------------------------------------------------------------

///|
/// Place `f` in the first empty (`0`) slot of bucket `i`. Returns `true` if
/// placed, `false` if the bucket is full.
fn try_insert(cf : CuckooFilter, i : Int, f : Int) -> Bool {
  let bucket = cf.buckets[i]
  for j = 0; j < cf.bucket_size; j = j + 1 {
    if bucket[j] == 0 {
      bucket[j] = f
      return true
    }
  }
  false
}

///|
/// Return `true` if fingerprint `f` is present in bucket `i`.
fn find_in_bucket(cf : CuckooFilter, i : Int, f : Int) -> Bool {
  let bucket = cf.buckets[i]
  for j = 0; j < cf.bucket_size; j = j + 1 {
    if bucket[j] == f {
      return true
    }
  }
  false
}

///|
/// Remove the first occurrence of fingerprint `f` from bucket `i` (set the
/// slot back to `0`). Returns `true` if an occurrence was removed.
fn remove_from_bucket(cf : CuckooFilter, i : Int, f : Int) -> Bool {
  let bucket = cf.buckets[i]
  for j = 0; j < cf.bucket_size; j = j + 1 {
    if bucket[j] == f {
      bucket[j] = 0
      return true
    }
  }
  false
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

///|
/// Create a cuckoo filter with `capacity` buckets, each holding `bucket_size`
/// fingerprints.
///
/// The bucket count is rounded **up to the next power of two** so that the XOR
/// alternate-index is an exact involution (see [`alt_index`]); this is the
/// standard cuckoo-filter construction. `bucket_size = 4` is a typical choice.
/// Non-positive arguments are clamped to safe defaults.
pub fn new(capacity : Int, bucket_size : Int) -> CuckooFilter {
  let cap = @hash_utils.next_pow2(if capacity > 0 { capacity } else { 1 })
  let bs = if bucket_size > 0 { bucket_size } else { 4 }
  // `makei` allocates each bucket's inner array independently, so the buckets
  // never alias one shared array (which `make(cap, inner)` would do).
  let buckets = FixedArray::makei(cap, fn(_i) { FixedArray::make(bs, 0) })
  {
    buckets,
    capacity: cap,
    bucket_size: bs,
    count: 0,
    rng: @utils.fresh_seed(CF_RNG_SEED),
  }
}

///|
/// Insert `key` into the filter. Returns `false` if the table is too full
/// (the 500-kick budget was exhausted).
///
/// On conflict, a random victim fingerprint is evicted and re-inserted into
/// its own alternate bucket (cuckoo kicking). If `add` returns `false`, a
/// previously inserted fingerprint may have been displaced in the process —
/// a known cuckoo-filter trade-off; the caller should grow the filter.
/// `size` is not adjusted on failure because the displaced entry may be
/// either the new key or an existing one and the two cannot be distinguished
/// from the fingerprint alone.
///
/// Adding the same key twice stores two independent copies (so `remove` must
/// be called twice to clear it).
pub fn add(cf : CuckooFilter, key : String) -> Bool {
  let f = make_fingerprint(key)
  let i1 = index1(cf, key)
  let i2 = alt_index(i1, f, cf.capacity)
  if try_insert(cf, i1, f) {
    cf.count = cf.count + 1
    return true
  }
  if try_insert(cf, i2, f) {
    cf.count = cf.count + 1
    return true
  }
  // Cuckoo kicking: start from a random one of the two candidate buckets.
  let mut i = if rand_below(cf, 2) == 0 { i1 } else { i2 }
  let mut fp = f
  for kicks = 0; kicks < CF_MAX_KICKS; kicks = kicks + 1 {
    // Evict a random slot in bucket i and install the in-flight fingerprint.
    let slot = rand_below(cf, cf.bucket_size)
    let tmp = cf.buckets[i][slot]
    cf.buckets[i][slot] = fp
    fp = tmp
    // The evicted fingerprint's alternate bucket is its only other home.
    i = alt_index(i, fp, cf.capacity)
    if try_insert(cf, i, fp) {
      cf.count = cf.count + 1
      return true
    }
  }
  false
}

///|
/// Check whether `key` might be in the filter. False positives are possible
/// (fingerprint collision); false negatives are impossible for keys that were
/// added and not displaced by a failed `add`.
pub fn contains(cf : CuckooFilter, key : String) -> Bool {
  let f = make_fingerprint(key)
  let i1 = index1(cf, key)
  let i2 = alt_index(i1, f, cf.capacity)
  find_in_bucket(cf, i1, f) || find_in_bucket(cf, i2, f)
}

///|
/// Remove one occurrence of `key` from the filter. Returns `true` if an
/// occurrence was found and deleted, `false` if the key was not present.
///
/// Only delete keys you have actually added: removing a non-member that
/// falsely tests positive (fingerprint collision) will silently delete an
/// unrelated entry, turning it into a false negative.
pub fn remove(cf : CuckooFilter, key : String) -> Bool {
  let f = make_fingerprint(key)
  let i1 = index1(cf, key)
  let i2 = alt_index(i1, f, cf.capacity)
  if remove_from_bucket(cf, i1, f) {
    cf.count = cf.count - 1
    return true
  }
  if remove_from_bucket(cf, i2, f) {
    cf.count = cf.count - 1
    return true
  }
  false
}

///|
/// Number of items currently stored (successful inserts minus successful
/// deletes). O(1).
pub fn size(cf : CuckooFilter) -> Int {
  cf.count
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "cuckoo: basic add and contains" {
  let cf = new(100, 4)
  assert_true(add(cf, "hello"))
  assert_true(add(cf, "world"))
  assert_true(contains(cf, "hello"))
  assert_true(contains(cf, "world"))
  assert_false(contains(cf, "missing"))
  assert_eq(size(cf), 2)
}

///|
test "cuckoo: remove existing item" {
  let cf = new(100, 4)
  assert_true(add(cf, "apple"))
  assert_true(add(cf, "banana"))
  assert_true(contains(cf, "apple"))
  assert_true(remove(cf, "apple"))
  assert_false(contains(cf, "apple"))
  // The untouched key is still present.
  assert_true(contains(cf, "banana"))
  assert_eq(size(cf), 1)
}

///|
test "cuckoo: remove non-existent item" {
  let cf = new(100, 4)
  assert_true(add(cf, "apple"))
  // A key never added is not removable.
  assert_false(remove(cf, "missing"))
  assert_eq(size(cf), 1)
  // Removing from an empty filter is also a no-op.
  let cf2 = new(100, 4)
  assert_false(remove(cf2, "anything"))
  assert_eq(size(cf2), 0)
}

///|
test "cuckoo: no false negatives" {
  let cf = new(1000, 4)
  let words = [
    "alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta", "theta", "iota",
    "kappa", "lambda", "mu", "nu", "xi", "omicron", "pi",
  ]
  for i = 0; i < words.length(); i = i + 1 {
    assert_true(add(cf, words[i]))
  }
  // Every inserted key must be found (no false negatives).
  for i = 0; i < words.length(); i = i + 1 {
    assert_true(contains(cf, words[i]))
  }
  assert_eq(size(cf), words.length())
}

///|
test "cuckoo: false positive rate is reasonable" {
  // 2000 buckets rounded up to 2048, 4 slots each => 8192 slots. With 32-bit
  // fingerprints the per-query false-positive probability is on the order of
  // 2 * bucket_size * load / 2^32, far below 10% for any reasonable load.
  let cf = new(2000, 4)
  for i = 0; i < 1000; i = i + 1 {
    assert_true(add(cf, "member_" + i.to_string()))
  }
  let mut false_positives = 0
  let total = 2000
  for i = 0; i < total; i = i + 1 {
    if contains(cf, "nonmember_" + i.to_string()) {
      false_positives = false_positives + 1
    }
  }
  let rate = false_positives.to_double() / total.to_double()
  // Requirement: under 10%.
  assert_true(rate < 0.10)
}

///|
test "cuckoo: duplicate add" {
  let cf = new(100, 4)
  assert_true(add(cf, "dup"))
  assert_true(add(cf, "dup"))
  // Two inserts occupy two slots; `size` reflects both copies.
  assert_eq(size(cf), 2)
  assert_true(contains(cf, "dup"))
  // Removing one copy leaves the other, so the key is still present.
  assert_true(remove(cf, "dup"))
  assert_true(contains(cf, "dup"))
  assert_eq(size(cf), 1)
  // Removing the second copy finally clears the key.
  assert_true(remove(cf, "dup"))
  assert_false(contains(cf, "dup"))
  assert_eq(size(cf), 0)
}

///|
test "cuckoo: large number of items" {
  // 1000 items in a 2000-bucket (=> 2048) filter, 4 slots per bucket: ~12%
  // load, well within capacity, so every insert must succeed.
  let cf = new(2000, 4)
  let mut all_added = true
  for i = 0; i < 1000; i = i + 1 {
    let ok = add(cf, "key_" + i.to_string())
    if !ok {
      all_added = false
    }
  }
  assert_true(all_added)
  assert_eq(size(cf), 1000)
  // No false negatives for any of the 1000 inserted keys.
  for i = 0; i < 1000; i = i + 1 {
    assert_true(contains(cf, "key_" + i.to_string()))
  }
}

///|
test "cuckoo: insert returns false when nearly full" {
  // Tiny filter: 8 buckets * 2 slots = 16 slots. Inserting far more distinct
  // keys than slots must eventually exhaust the 500-kick budget and fail.
  let cf = new(8, 2)
  let mut failed = false
  for i = 0; i < 1000; i = i + 1 {
    let ok = add(cf, "k_" + i.to_string())
    if !ok {
      failed = true
      break
    }
  }
  assert_true(failed)
}
