/// TTL (Time-To-Live) Cache with logical-clock-based expiration.
///
/// Each entry expires a fixed number of *ticks* after it was inserted. Because
/// MoonBit has no real-time clock available to library code, time is a purely
/// logical counter: the caller advances it with `tick`. Expiration is checked
/// *lazily* on `get` (a single key) and *eagerly* on `tick` (the whole map).
///
/// - Storage: a MoonBit `Map[K, Entry[V]]` gives O(1) amortized access.
/// - Capacity: fixed at construction. When a brand-new key would exceed
///   capacity, the entry with the smallest insertion time is evicted first.
/// - TTL = 0 means "already expired": such an entry is never observable via
///   `get` and is not counted by `size`.
///
/// **Overflow safety**: the logical clock and all timestamps use `Int64`
/// internally, preventing overflow even after ~9.2 × 10¹⁸ ticks. The public
/// API accepts `Int` for `ttl` and `delta` parameters (typical values are
/// small), but internally stores them as `Int64`.
///
/// Not formally verified. Correctness is ensured by the test suite below.
///
/// Time complexity (average): O(1) for `get` / `put` / `remove`;
/// `tick` and `size` are O(n) in the number of live entries because they walk
/// the map (to evict / to count non-expired entries).

///|
/// A single cache entry: the stored value plus its bookkeeping timestamps.
///
/// `expires_at`   — the logical tick at which the entry becomes stale
///                  (`clock >= expires_at` means expired).
/// `inserted_at`  — the logical tick at which the entry was last `put`;
///                  used to pick the victim when capacity is exceeded.
pub struct Entry[V] {
  priv value : V
  priv expires_at : Int64
  priv inserted_at : Int64
}

///|
/// A TTL cache mapping keys of type `K` to values of type `V`.
///
/// `K` must implement the built-in `Hash` and `Eq` traits (required by MoonBit's
/// `Map`). `V` is unrestricted.
pub struct TtlCache[K, V] {
  /// Maximum number of live entries. Fixed at construction.
  priv capacity : Int
  /// Number of ticks an entry lives after being `put` (Int64 to prevent overflow).
  priv ttl : Int64
  /// Current logical time; advanced by `tick` (Int64 to prevent overflow).
  priv mut clock : Int64
  /// Live entries keyed by `K`.
  priv mut entries : Map[K, Entry[V]]
}

///|
/// Create a new TTL cache with the given fixed `capacity` and `ttl` (in ticks).
///
/// A non-positive `capacity` yields a cache that silently stores nothing.
/// A non-positive `ttl` yields entries that are immediately expired.
pub fn[K : Hash + Eq, V] new(capacity : Int, ttl : Int) -> TtlCache[K, V] {
  { capacity, ttl: ttl.to_int64(), clock: 0L, entries: Map([]) }
}

///|
/// Insert or update an entry.
///
/// On update, the value is replaced and the entry's expiration is refreshed to
/// `clock + ttl`. On insert, if the cache is at capacity, the oldest entry (by
/// insertion time) is evicted first. Inserting into a non-positive-capacity
/// cache is a no-op.
pub fn[K : Hash + Eq, V] put(
  cache : TtlCache[K, V],
  key : K,
  value : V,
) -> Unit {
  if cache.capacity <= 0 {
    return
  }
  let now = cache.clock
  if !cache.entries.contains(key) && cache.entries.length() >= cache.capacity {
    evict_oldest(cache)
  }
  cache.entries[key] = { value, expires_at: now + cache.ttl, inserted_at: now }
}

///|
/// Look up `key`.
///
/// Returns `Some(v)` if the entry exists and has not expired; `None` otherwise.
/// An expired entry is removed lazily on access.
pub fn[K : Hash + Eq, V] get(cache : TtlCache[K, V], key : K) -> V? {
  match cache.entries.get(key) {
    Some(entry) =>
      if entry.expires_at <= cache.clock {
        let _ = cache.entries.remove(key)
        None
      } else {
        Some(entry.value)
      }
    None => None
  }
}

///|
/// Remove the entry for `key`, if any.
pub fn[K : Hash + Eq, V] remove(cache : TtlCache[K, V], key : K) -> Unit {
  let _ = cache.entries.remove(key)
}

///|
/// Advance the logical clock by `delta` ticks, then eagerly evict every
/// entry whose TTL has expired.
pub fn[K : Hash + Eq, V] tick(cache : TtlCache[K, V], delta : Int) -> Unit {
  cache.clock = cache.clock + delta.to_int64()
  evict_expired(cache)
}

///|
/// Number of non-expired entries currently held.
///
/// This walks the map and counts entries with `expires_at > clock`; it does not
/// mutate the cache. Expired-but-not-yet-evicted entries are not counted.
pub fn[K, V] size(cache : TtlCache[K, V]) -> Int {
  let now = cache.clock
  let mut count = 0
  for _k, entry in cache.entries {
    if entry.expires_at > now {
      count = count + 1
    }
  }
  count
}

///|
/// Remove every entry. The logical clock is left untouched (time is not
/// rewound).
pub fn[K : Hash + Eq, V] clear(cache : TtlCache[K, V]) -> Unit {
  cache.entries = Map([])
}

///|
/// Remove every entry whose `expires_at` is at or before the current clock.
fn[K : Hash + Eq, V] evict_expired(cache : TtlCache[K, V]) -> Unit {
  let now = cache.clock
  let expired : Array[K] = []
  for k, entry in cache.entries {
    if entry.expires_at <= now {
      expired.push(k)
    }
  }
  for k in expired {
    let _ = cache.entries.remove(k)
  }
}

///|
/// Evict the single entry with the smallest `inserted_at` (the oldest).
/// Ties are broken by insertion order, since `Map` preserves insertion order.
fn[K : Hash + Eq, V] evict_oldest(cache : TtlCache[K, V]) -> Unit {
  if cache.entries.length() == 0 {
    return
  }
  let mut victim : K? = None
  let mut oldest_time = 0L
  let mut first = true
  for k, entry in cache.entries {
    if first || entry.inserted_at < oldest_time {
      oldest_time = entry.inserted_at
      victim = Some(k)
      first = false
    }
  }
  match victim {
    Some(k) => {
      let _ = cache.entries.remove(k)
    }
    None => ()
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "ttl: basic put and get" {
  let c : TtlCache[Int, String] = new(3, 5)
  put(c, 1, "one")
  put(c, 2, "two")
  assert_eq(get(c, 1), Some("one"))
  assert_eq(get(c, 2), Some("two"))
  assert_true(get(c, 3) is None)
  assert_eq(size(c), 2)
}

///|
test "ttl: expired entry returns None after tick" {
  let c : TtlCache[Int, String] = new(3, 3)
  put(c, 1, "one") // expires_at = 3
  assert_eq(get(c, 1), Some("one"))
  tick(c, 2) // clock = 2: still alive
  assert_eq(get(c, 1), Some("one"))
  tick(c, 1) // clock = 3: now expired
  assert_true(get(c, 1) is None)
  assert_eq(size(c), 0)
}

///|
test "ttl: update existing key" {
  let c : TtlCache[Int, String] = new(3, 5)
  put(c, 1, "old")
  put(c, 1, "new")
  assert_eq(get(c, 1), Some("new"))
  assert_eq(size(c), 1)
}

///|
test "ttl: remove entry" {
  let c : TtlCache[Int, String] = new(3, 5)
  put(c, 1, "one")
  put(c, 2, "two")
  remove(c, 1)
  assert_true(get(c, 1) is None)
  assert_eq(get(c, 2), Some("two"))
  assert_eq(size(c), 1)
}

///|
test "ttl: capacity eviction evicts oldest" {
  let c : TtlCache[Int, String] = new(2, 100)
  put(c, 1, "one") // inserted_at = 0
  tick(c, 1) // clock = 1
  put(c, 2, "two") // inserted_at = 1
  tick(c, 1) // clock = 2
  put(c, 3, "three") // inserted_at = 2; at capacity -> evict oldest (1)
  assert_true(get(c, 1) is None)
  assert_eq(get(c, 2), Some("two"))
  assert_eq(get(c, 3), Some("three"))
  assert_eq(size(c), 2)
}

///|
test "ttl: clear" {
  let c : TtlCache[Int, String] = new(3, 5)
  put(c, 1, "a")
  put(c, 2, "b")
  clear(c)
  assert_eq(size(c), 0)
  assert_true(get(c, 1) is None)
  put(c, 3, "c") // still usable after clear
  assert_eq(get(c, 3), Some("c"))
}

///|
test "ttl: size after expiration" {
  let c : TtlCache[Int, Int] = new(5, 3)
  put(c, 1, 10)
  put(c, 2, 20)
  put(c, 3, 30)
  assert_eq(size(c), 3)
  tick(c, 3) // all expire
  assert_eq(size(c), 0)
  // Partial expiration: only some entries expire.
  let c2 : TtlCache[Int, Int] = new(5, 3)
  put(c2, 1, 10) // expires_at = 3
  tick(c2, 1) // clock = 1
  put(c2, 2, 20) // expires_at = 4
  tick(c2, 2) // clock = 3: key 1 expired, key 2 alive
  assert_eq(size(c2), 1)
  assert_true(get(c2, 1) is None)
  assert_eq(get(c2, 2), Some(20))
}

///|
test "ttl: multiple ticks accumulate" {
  let c : TtlCache[Int, String] = new(5, 5)
  put(c, 1, "v") // expires_at = 5
  tick(c, 2) // clock = 2
  assert_eq(get(c, 1), Some("v"))
  tick(c, 2) // clock = 4
  assert_eq(get(c, 1), Some("v")) // still alive (4 < 5)
  tick(c, 1) // clock = 5
  assert_true(get(c, 1) is None) // expired (5 >= 5)
  assert_eq(size(c), 0)
}

///|
test "ttl: ttl 0 means immediate expiration" {
  let c : TtlCache[Int, String] = new(3, 0)
  put(c, 1, "instant") // expires_at = 0
  assert_true(get(c, 1) is None) // expired immediately, no tick needed
  assert_eq(size(c), 0)
  tick(c, 5) // advancing time cannot revive it
  assert_true(get(c, 1) is None)
  assert_eq(size(c), 0)
}

///|
test "ttl: string keys and mixed ttl" {
  let c : TtlCache[String, Int] = new(3, 4)
  put(c, "apple", 1) // expires_at = 4
  tick(c, 2) // clock = 2
  put(c, "banana", 2) // expires_at = 6
  tick(c, 2) // clock = 4: "apple" expired, "banana" alive
  assert_true(get(c, "apple") is None)
  assert_eq(get(c, "banana"), Some(2))
}
