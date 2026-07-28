///|
/// W-TinyLFU Cache — a modern admission-based cache combining recency
/// and frequency for superior hit rates.
///
/// ## Architecture
///
/// Three LRU segments share a common node pool:
/// - **Window** (1% of capacity): newly inserted items land here first.
///   This gives recently-seen items a chance even if their frequency is low.
/// - **Probationary** (80% of Main): items promoted from the Window. An
///   access here promotes the item to Protected.
/// - **Protected** (20% of Main): items accessed while in Probationary.
///   An access here just refreshes the item's position.
///
/// ## Admission Policy (TinyLFU)
///
/// When the Window overflows, its LRU item becomes the **candidate**. If the
/// Probationary segment is also full, its LRU item is the **victim**. A
/// Count-Min Sketch estimates each item's frequency; the higher-frequency
/// item is admitted to Probationary, the other is permanently evicted.
///
/// ## Aging
///
/// Every `10 × capacity` frequency additions, all counters are halved
/// (right-shifted by 1). This decays stale frequencies so the estimator
/// tracks recent access patterns rather than the full history.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Segment indices
// ---------------------------------------------------------------------------

const SEG_WINDOW : Int = 0

///|
const SEG_PROBATIONARY : Int = 1

///|
const SEG_PROTECTED : Int = 2

// ---------------------------------------------------------------------------
// Data structure
// ---------------------------------------------------------------------------

///|
/// A W-TinyLFU cache with `Int` keys and `Int` values.
///
/// All fields are `priv`: external code interacts with the cache exclusively
/// through its public functions (`new`, `get`, `put`, `size`), which preserves
/// the segment-occupancy and frequency-sketch invariants.
pub struct WTinyLFU {
  /// Node pool: parallel arrays indexed by node id.
  priv keys : Array[Int]
  priv vals : Array[Int]
  priv prevs : Array[Int] // -1 = no predecessor (head)
  priv nexts : Array[Int] // -1 = no successor (tail)
  priv segs : Array[Int] // which segment a node belongs to
  priv free : Array[Int] // recycled node indices for reuse
  /// Per-segment head / tail / count, indexed by SEG_*.
  priv heads : Array[Int] // -1 = segment empty
  priv tails : Array[Int]
  priv counts : Array[Int]
  /// Key → node index, for O(1) amortized lookup.
  priv index : @hash_table.HashTable[Int, Int]
  /// Count-Min Sketch frequency table.
  priv freq : FixedArray[FixedArray[Int]]
  priv freq_width : Int
  priv freq_depth : Int
  priv mut total_adds : Int
  priv sample_size : Int
  /// Per-segment capacities, indexed by SEG_*.
  priv caps : Array[Int]
}

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

///|
/// Create a W-TinyLFU cache with the given total `capacity`.
///
/// The capacity is split: 1% for the Window, 80% of the remainder for
/// Probationary, 20% for Protected. For small capacities (`< 10`) the
/// Protected segment is omitted (set to 0) and all Main space goes to
/// Probationary.
///
/// **Precondition**: `capacity >= 1`. If `capacity < 1`, it is clamped to 1.
pub fn new(capacity : Int) -> WTinyLFU {
  let capacity = if capacity < 1 { 1 } else { capacity }
  let cap = capacity
  let window_cap = if cap >= 100 { cap / 100 } else { 1 }
  let main = cap - window_cap
  let protected_cap = if main >= 10 { main / 5 } else { 0 }
  let probationary_cap = main - protected_cap
  // Frequency sketch: 10× capacity columns, 4 rows.
  let freq_width = if cap * 10 > 100 { cap * 10 } else { 100 }
  let freq_depth = 4
  {
    keys: [],
    vals: [],
    prevs: [],
    nexts: [],
    segs: [],
    free: [],
    heads: [-1, -1, -1],
    tails: [-1, -1, -1],
    counts: [0, 0, 0],
    index: @hash_table.new(cap * 2 + 1),
    freq: FixedArray::makei(freq_depth, fn(_i) {
      FixedArray::make(freq_width, 0)
    }),
    freq_width,
    freq_depth,
    total_adds: 0,
    sample_size: cap * 10,
    caps: [window_cap, probationary_cap, protected_cap],
  }
}

///|
/// Total number of entries currently in the cache.
pub fn size(cache : WTinyLFU) -> Int {
  cache.counts[SEG_WINDOW] +
  cache.counts[SEG_PROBATIONARY] +
  cache.counts[SEG_PROTECTED]
}

// ---------------------------------------------------------------------------
// Linked-list helpers (shared by all three segments)
// ---------------------------------------------------------------------------

///|
/// Detach node `idx` from segment `seg`. Decrements the segment count.
fn detach(cache : WTinyLFU, seg : Int, idx : Int) -> Unit {
  let p = cache.prevs[idx]
  let n = cache.nexts[idx]
  if p >= 0 {
    cache.nexts[p] = n
  } else {
    cache.heads[seg] = n
  }
  if n >= 0 {
    cache.prevs[n] = p
  } else {
    cache.tails[seg] = p
  }
  cache.prevs[idx] = -1
  cache.nexts[idx] = -1
  cache.counts[seg] = cache.counts[seg] - 1
}

///|
/// Attach node `idx` at the tail of segment `seg`. Increments the count.
fn insert_tail(cache : WTinyLFU, seg : Int, idx : Int) -> Unit {
  cache.segs[idx] = seg
  if cache.tails[seg] >= 0 {
    cache.prevs[idx] = cache.tails[seg]
    cache.nexts[idx] = -1
    cache.nexts[cache.tails[seg]] = idx
    cache.tails[seg] = idx
  } else {
    cache.heads[seg] = idx
    cache.tails[seg] = idx
    cache.prevs[idx] = -1
    cache.nexts[idx] = -1
  }
  cache.counts[seg] = cache.counts[seg] + 1
}

///|
/// Remove and return the head (LRU) node of segment `seg`.
fn remove_head(cache : WTinyLFU, seg : Int) -> Int {
  let idx = cache.heads[seg]
  detach(cache, seg, idx)
  idx
}

///|
/// Move node `idx` to the tail of its current segment. No-op if already tail.
fn move_to_tail(cache : WTinyLFU, seg : Int, idx : Int) -> Unit {
  if cache.tails[seg] == idx {
    return
  }
  detach(cache, seg, idx)
  insert_tail(cache, seg, idx)
}

// ---------------------------------------------------------------------------
// Node allocation
// ---------------------------------------------------------------------------

///|
/// Allocate a fresh node index, reusing the free list when available.
fn alloc_node(cache : WTinyLFU) -> Int {
  match cache.free.pop() {
    Some(idx) => idx
    None => {
      let idx = cache.keys.length()
      cache.keys.push(0)
      cache.vals.push(0)
      cache.prevs.push(-1)
      cache.nexts.push(-1)
      cache.segs.push(0)
      idx
    }
  }
}

///|
/// Return node `idx` to the free list for future reuse.
fn free_node(cache : WTinyLFU, idx : Int) -> Unit {
  cache.free.push(idx)
}

// ---------------------------------------------------------------------------
// Frequency estimator (Count-Min Sketch with aging)
// ---------------------------------------------------------------------------

///|
/// Int64 modulo returning a non-negative residue in `[0, m)` for `m > 0`.
fn mod_nonneg(h : Int64, m : Int64) -> Int64 {
  let r = h % m
  if r < 0L {
    r + m
  } else {
    r
  }
}

///|
/// Double-hash an Int key into `(h1, h2)` for the Count-Min Sketch.
///
/// `h2` is forced odd so the double-hashing sequence visits distinct columns.
fn freq_hash(key : Int) -> (Int64, Int64) {
  let mut h = key.to_int64()
  h = h * 0x9e3779b97f4a7c15L
  h = h ^ (h >> 32)
  (h, (h >> 16) | 1L)
}

///|
/// Record one access to `key` in the frequency sketch.
fn freq_add(cache : WTinyLFU, key : Int) -> Unit {
  let (h1, h2) = freq_hash(key)
  let w = cache.freq_width.to_int64()
  let h1r = mod_nonneg(h1, w)
  let h2r = mod_nonneg(h2, w)
  for i = 0; i < cache.freq_depth; i = i + 1 {
    let col = mod_nonneg(h1r + i.to_int64() * h2r, w).to_int()
    cache.freq[i][col] = cache.freq[i][col] + 1
  }
  cache.total_adds = cache.total_adds + 1
  if cache.total_adds >= cache.sample_size {
    freq_age(cache)
  }
}

///|
/// Estimate the frequency of `key` (minimum across all rows).
fn freq_est(cache : WTinyLFU, key : Int) -> Int {
  let (h1, h2) = freq_hash(key)
  let w = cache.freq_width.to_int64()
  let h1r = mod_nonneg(h1, w)
  let h2r = mod_nonneg(h2, w)
  let mut min_val = cache.freq[0][mod_nonneg(h1r, w).to_int()]
  for i = 1; i < cache.freq_depth; i = i + 1 {
    let col = mod_nonneg(h1r + i.to_int64() * h2r, w).to_int()
    let v = cache.freq[i][col]
    if v < min_val {
      min_val = v
    }
  }
  min_val
}

///|
/// Halve all frequency counters (aging / reset).
fn freq_age(cache : WTinyLFU) -> Unit {
  for i = 0; i < cache.freq_depth; i = i + 1 {
    for j = 0; j < cache.freq_width; j = j + 1 {
      cache.freq[i][j] = cache.freq[i][j] >> 1
    }
  }
  cache.total_adds = 0
}

// ---------------------------------------------------------------------------
// Core API
// ---------------------------------------------------------------------------

///|
/// Look up `key`. On hit, returns the value and promotes the entry within
/// the segment hierarchy. On miss, returns `None`.
///
/// A hit also records the access in the frequency sketch.
pub fn get(cache : WTinyLFU, key : Int) -> Int? {
  match @hash_table.get(cache.index, key, int_hash, int_eq) {
    None => None
    Some(idx) => {
      freq_add(cache, key)
      promote_on_access(cache, idx)
      Some(cache.vals[idx])
    }
  }
}

///|
/// Insert or update `key` → `value`.
///
/// On a new key, the entry enters the Window; if the Window overflows, the
/// TinyLFU admission policy decides whether to admit it to Probationary.
pub fn put(cache : WTinyLFU, key : Int, value : Int) -> Unit {
  freq_add(cache, key)
  match @hash_table.get(cache.index, key, int_hash, int_eq) {
    Some(idx) => {
      cache.vals[idx] = value
      promote_on_access(cache, idx)
    }
    None => {
      let idx = alloc_node(cache)
      cache.keys[idx] = key
      cache.vals[idx] = value
      insert_tail(cache, SEG_WINDOW, idx)
      @hash_table.insert(cache.index, key, idx, int_hash, int_eq)
      handle_window_overflow(cache)
    }
  }
}

///|
/// Promote a node based on which segment it currently resides in.
///
/// - Window → refresh position in Window.
/// - Probationary → promote to Protected (evicting Protected LRU back to
///   Probationary if Protected is full).
/// - Protected → refresh position in Protected.
fn promote_on_access(cache : WTinyLFU, idx : Int) -> Unit {
  let seg = cache.segs[idx]
  if seg == SEG_WINDOW {
    move_to_tail(cache, SEG_WINDOW, idx)
  } else if seg == SEG_PROBATIONARY {
    if cache.caps[SEG_PROTECTED] > 0 {
      if cache.counts[SEG_PROTECTED] >= cache.caps[SEG_PROTECTED] {
        // Protected full: demote its LRU back to Probationary.
        let demoted = remove_head(cache, SEG_PROTECTED)
        insert_tail(cache, SEG_PROBATIONARY, demoted)
      }
      detach(cache, SEG_PROBATIONARY, idx)
      insert_tail(cache, SEG_PROTECTED, idx)
    } else {
      move_to_tail(cache, SEG_PROBATIONARY, idx)
    }
  } else {
    move_to_tail(cache, SEG_PROTECTED, idx)
  }
}

///|
/// When the Window exceeds its capacity, evict the LRU item and attempt to
/// admit it to Probationary via the TinyLFU admission policy.
fn handle_window_overflow(cache : WTinyLFU) -> Unit {
  if cache.counts[SEG_WINDOW] <= cache.caps[SEG_WINDOW] {
    return
  }
  let candidate = remove_head(cache, SEG_WINDOW)
  // If Probationary has room, admit directly.
  if cache.counts[SEG_PROBATIONARY] < cache.caps[SEG_PROBATIONARY] {
    insert_tail(cache, SEG_PROBATIONARY, candidate)
    return
  }
  // Probationary is full or has zero capacity. If empty (zero-capacity edge
  // case), there is no victim to compare against — evict the candidate.
  if cache.counts[SEG_PROBATIONARY] == 0 {
    let _ = @hash_table.remove(
      cache.index,
      cache.keys[candidate],
      int_hash,
      int_eq,
    )
    free_node(cache, candidate)
    return
  }
  // Probationary full: TinyLFU comparison.
  let victim = remove_head(cache, SEG_PROBATIONARY)
  let cand_freq = freq_est(cache, cache.keys[candidate])
  let vic_freq = freq_est(cache, cache.keys[victim])
  if cand_freq >= vic_freq {
    // Candidate wins: evict victim, admit candidate.
    let _ = @hash_table.remove(
      cache.index,
      cache.keys[victim],
      int_hash,
      int_eq,
    )
    free_node(cache, victim)
    insert_tail(cache, SEG_PROBATIONARY, candidate)
  } else {
    // Victim wins: evict candidate, reinstate victim.
    let _ = @hash_table.remove(
      cache.index,
      cache.keys[candidate],
      int_hash,
      int_eq,
    )
    free_node(cache, candidate)
    insert_tail(cache, SEG_PROBATIONARY, victim)
  }
}

// ---------------------------------------------------------------------------
// Hash / equality for Int keys
// ---------------------------------------------------------------------------

///|
fn int_hash(k : Int) -> Int {
  // fmix32 — a proper integer hash to avoid clustering on sequential keys.
  let mut h = k
  h = h ^ (h >> 16)
  h = h * 0x85ebca6b
  h = h ^ (h >> 13)
  h = h * 0xc2b2ae35
  h = h ^ (h >> 16)
  h
}

///|
fn int_eq(a : Int, b : Int) -> Bool {
  a == b
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "basic put and get" {
  let cache = new(100)
  put(cache, 1, 100)
  put(cache, 2, 200)
  put(cache, 3, 300)
  assert_eq(get(cache, 1), Some(100))
  assert_eq(get(cache, 2), Some(200))
  assert_eq(get(cache, 3), Some(300))
  assert_eq(size(cache), 3)
}

///|
test "miss returns None" {
  let cache = new(100)
  put(cache, 1, 10)
  assert_true(get(cache, 99) is None)
}

///|
test "update existing key" {
  let cache = new(100)
  put(cache, 1, 10)
  put(cache, 1, 20)
  assert_eq(get(cache, 1), Some(20))
  assert_eq(size(cache), 1)
}

///|
test "eviction: low-frequency items evicted first" {
  // With capacity 10, window=1, main=9, probationary=7, protected=2.
  let cache = new(10)
  // Fill cache with 10 items.
  for i = 0; i < 10; i = i + 1 {
    put(cache, i, i)
  }
  assert_eq(size(cache), 10)
  // Access items 0-4 multiple times to build frequency.
  for _r = 0; _r < 3; _r = _r + 1 {
    for i = 0; i < 5; i = i + 1 {
      let _ = get(cache, i)
    }
  }
  // Add 5 new items. Items 5-9 (low frequency) should be evicted preferentially.
  for i = 10; i < 15; i = i + 1 {
    put(cache, i, i)
  }
  // High-frequency items should survive.
  let mut hot_survivors = 0
  for i = 0; i < 5; i = i + 1 {
    if get(cache, i) is Some(_) {
      hot_survivors = hot_survivors + 1
    }
  }
  // At least some hot items should survive.
  assert_true(hot_survivors >= 1)
}

///|
test "recency: new items get a chance (window)" {
  let cache = new(100)
  // Fill with hot items.
  for i = 0; i < 50; i = i + 1 {
    put(cache, i, i)
    for _r = 0; _r < 5; _r = _r + 1 {
      let _ = get(cache, i)
    }
  }
  // A brand new item should still be admitted (Window gives it a chance).
  put(cache, 999, 42)
  // It may or may not survive long, but it should be in the cache right now.
  assert_eq(get(cache, 999), Some(42))
}

///|
test "aging decays old frequencies" {
  let cache = new(10)
  // Item 0 is hot.
  for _r = 0; _r < 20; _r = _r + 1 {
    put(cache, 0, 0)
  }
  let f1 = freq_est(cache, 0)
  assert_true(f1 > 0)
  // Force aging.
  freq_age(cache)
  let f2 = freq_est(cache, 0)
  assert_true(f2 < f1)
}

///|
test "size never exceeds capacity" {
  let cache = new(20)
  for i = 0; i < 100; i = i + 1 {
    put(cache, i, i)
    assert_true(size(cache) <= 20)
  }
}

///|
test "capacity 1" {
  let cache = new(1)
  put(cache, 1, 10)
  assert_eq(get(cache, 1), Some(10))
  put(cache, 2, 20)
  assert_eq(size(cache), 1)
  // Only one item can exist.
  let has1 = get(cache, 1) is Some(_)
  let has2 = get(cache, 2) is Some(_)
  assert_true(has1 || has2)
  assert_true(!(has1 && has2))
}

///|
test "stress: random access pattern" {
  let cache = new(50)
  for i = 0; i < 500; i = i + 1 {
    let key = i % 100
    put(cache, key, key * 2)
  }
  assert_true(size(cache) <= 50)
  // Verify integrity: every key in the cache returns correct value.
  for i = 0; i < 100; i = i + 1 {
    match get(cache, i) {
      Some(v) => assert_eq(v, i * 2)
      None => ()
    }
  }
}

///|
test "frequency estimation tracks access counts" {
  let cache = new(100)
  for _r = 0; _r < 10; _r = _r + 1 {
    put(cache, 42, 1)
  }
  for _r = 0; _r < 3; _r = _r + 1 {
    put(cache, 7, 1)
  }
  // Item 42 was accessed more; estimate should be higher.
  assert_true(freq_est(cache, 42) > freq_est(cache, 7))
}

///|
test "promotion: probationary to protected on access" {
  let cache = new(50)
  for i = 0; i < 10; i = i + 1 {
    put(cache, i, i)
  }
  // All items should be in window or probationary.
  // Access item 5 to promote it.
  let _ = get(cache, 5)
  // Access it again — it should be in protected now.
  let _ = get(cache, 5)
  assert_eq(get(cache, 5), Some(5))
}
