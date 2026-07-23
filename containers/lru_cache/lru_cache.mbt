/// LRU (Least Recently Used) Cache.
///
/// Stores key-value pairs with a fixed capacity. On access (get or put),
/// the accessed entry is moved to the most-recently-used position. When
/// capacity is exceeded, the least-recently-used entry is evicted.
///
/// Implementation: two parallel arrays (keys and vals) ordered by recency.
/// Front = LRU, back = MRU. O(n) per operation.
///
/// Not formally verified. Correctness ensured by comprehensive tests.

pub struct LRUCache[K, V] {
  keys : Array[K]
  vals : Array[V]
  capacity : Int
}

/// Create an empty LRU cache with the given capacity.
/// A capacity of 0 means no entries can be stored.
pub fn[K, V] new(capacity : Int) -> LRUCache[K, V] {
  { keys: [], vals: [], capacity }
}

/// Number of entries currently in the cache.
pub fn[K, V] size(cache : LRUCache[K, V]) -> Int {
  cache.keys.length()
}

/// Look up a key. On hit, moves the entry to MRU position and returns
/// the value. On miss, returns None.
pub fn[K, V] get(
  cache : LRUCache[K, V],
  key : K,
  eq_fn : (K, K) -> Bool,
) -> V? {
  let n = cache.keys.length()
  let mut found = -1
  for i = 0; i < n; i = i + 1 {
    if eq_fn(cache.keys[i], key) {
      found = i
      break
    }
  }
  if found < 0 {
    return None
  }
  // Move to end (MRU): shift left, put at back
  let k = cache.keys[found]
  let v = cache.vals[found]
  for i = found; i < n - 1; i = i + 1 {
    cache.keys[i] = cache.keys[i + 1]
    cache.vals[i] = cache.vals[i + 1]
  }
  cache.keys[n - 1] = k
  cache.vals[n - 1] = v
  Some(v)
}

/// Insert or update a key-value pair. On update, moves the entry to MRU.
/// On insert when at capacity, evicts the LRU entry first.
pub fn[K, V] put(
  cache : LRUCache[K, V],
  key : K,
  value : V,
  eq_fn : (K, K) -> Bool,
) -> Unit {
  let n = cache.keys.length()
  // Check if key already exists
  let mut found = -1
  for i = 0; i < n; i = i + 1 {
    if eq_fn(cache.keys[i], key) {
      found = i
      break
    }
  }
  if found >= 0 {
    // Update value and move to end
    let k = cache.keys[found]
    for i = found; i < n - 1; i = i + 1 {
      cache.keys[i] = cache.keys[i + 1]
      cache.vals[i] = cache.vals[i + 1]
    }
    cache.keys[n - 1] = k
    cache.vals[n - 1] = value
    return
  }
  // New key
  if cache.capacity <= 0 {
    return
  }
  if n >= cache.capacity {
    // Evict LRU (front): shift left, put new at end
    for i = 0; i < n - 1; i = i + 1 {
      cache.keys[i] = cache.keys[i + 1]
      cache.vals[i] = cache.vals[i + 1]
    }
    cache.keys[n - 1] = key
    cache.vals[n - 1] = value
  } else {
    cache.keys.push(key)
    cache.vals.push(value)
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "lru: basic get and put" {
  let cache : LRUCache[Int, String] = new(3)
  put(cache, 1, "one", fn(a, b) { a == b })
  put(cache, 2, "two", fn(a, b) { a == b })
  put(cache, 3, "three", fn(a, b) { a == b })
  assert_eq(get(cache, 1, fn(a, b) { a == b }), Some("one"))
  assert_eq(get(cache, 2, fn(a, b) { a == b }), Some("two"))
  assert_eq(get(cache, 3, fn(a, b) { a == b }), Some("three"))
  assert_eq(size(cache), 3)
}

test "lru: eviction order" {
  let cache : LRUCache[Int, Int] = new(2)
  put(cache, 1, 10, fn(a, b) { a == b })
  put(cache, 2, 20, fn(a, b) { a == b })
  put(cache, 3, 30, fn(a, b) { a == b }) // evicts 1 (LRU)
  assert_true(get(cache, 1, fn(a, b) { a == b }) is None)
  assert_eq(get(cache, 2, fn(a, b) { a == b }), Some(20))
  assert_eq(get(cache, 3, fn(a, b) { a == b }), Some(30))
  assert_eq(size(cache), 2)
}

test "lru: update existing key" {
  let cache : LRUCache[Int, String] = new(2)
  put(cache, 1, "old", fn(a, b) { a == b })
  put(cache, 2, "two", fn(a, b) { a == b })
  put(cache, 1, "new", fn(a, b) { a == b }) // update, not evict
  assert_eq(size(cache), 2)
  // 1 is now MRU (updated), 2 is LRU; adding 3 evicts 2.
  // (No get calls here — get would change the LRU order.)
  put(cache, 3, "three", fn(a, b) { a == b })
  assert_true(get(cache, 2, fn(a, b) { a == b }) is None)
  assert_eq(get(cache, 1, fn(a, b) { a == b }), Some("new"))
  assert_eq(get(cache, 3, fn(a, b) { a == b }), Some("three"))
}

test "lru: capacity 1" {
  let cache : LRUCache[Int, Int] = new(1)
  put(cache, 1, 100, fn(a, b) { a == b })
  assert_eq(get(cache, 1, fn(a, b) { a == b }), Some(100))
  put(cache, 2, 200, fn(a, b) { a == b }) // evicts 1
  assert_true(get(cache, 1, fn(a, b) { a == b }) is None)
  assert_eq(get(cache, 2, fn(a, b) { a == b }), Some(200))
  assert_eq(size(cache), 1)
}

test "lru: capacity 0" {
  let cache : LRUCache[Int, Int] = new(0)
  put(cache, 1, 100, fn(a, b) { a == b })
  assert_eq(size(cache), 0)
  assert_true(get(cache, 1, fn(a, b) { a == b }) is None)
}

test "lru: non-existent key" {
  let cache : LRUCache[Int, Int] = new(3)
  put(cache, 1, 10, fn(a, b) { a == b })
  put(cache, 2, 20, fn(a, b) { a == b })
  assert_true(get(cache, 99, fn(a, b) { a == b }) is None)
  assert_eq(size(cache), 2) // size unchanged after miss
}

test "lru: ordering after multiple gets" {
  let cache : LRUCache[Int, Int] = new(3)
  put(cache, 1, 10, fn(a, b) { a == b })
  put(cache, 2, 20, fn(a, b) { a == b })
  put(cache, 3, 30, fn(a, b) { a == b })
  // Access 1 -> order: 2, 3, 1
  let _ = get(cache, 1, fn(a, b) { a == b })
  // Access 2 -> order: 3, 1, 2
  let _ = get(cache, 2, fn(a, b) { a == b })
  // Insert 4 -> evicts 3 (LRU)
  put(cache, 4, 40, fn(a, b) { a == b })
  assert_true(get(cache, 3, fn(a, b) { a == b }) is None)
  assert_eq(get(cache, 1, fn(a, b) { a == b }), Some(10))
  assert_eq(get(cache, 2, fn(a, b) { a == b }), Some(20))
  assert_eq(get(cache, 4, fn(a, b) { a == b }), Some(40))
}

test "lru: stress test 100 operations" {
  let cache : LRUCache[Int, Int] = new(10)
  // Insert 0..9
  for i = 0; i < 10; i = i + 1 {
    put(cache, i, i * 10, fn(a, b) { a == b })
  }
  assert_eq(size(cache), 10)
  // Access every other element to change LRU order
  for i = 0; i < 10; i = i + 2 {
    let _ = get(cache, i, fn(a, b) { a == b })
  }
  // After gets, order is: 1,3,5,7,9,0,2,4,6,8
  // Insert 10..19, each evicting the current LRU
  for i = 10; i < 20; i = i + 1 {
    put(cache, i, i * 10, fn(a, b) { a == b })
  }
  assert_eq(size(cache), 10)
  // Cache should now contain 10..19
  for i = 10; i < 20; i = i + 1 {
    assert_eq(get(cache, i, fn(a, b) { a == b }), Some(i * 10))
  }
  // Old elements 0..9 should all be gone
  for i = 0; i < 10; i = i + 1 {
    assert_true(get(cache, i, fn(a, b) { a == b }) is None)
  }
}
