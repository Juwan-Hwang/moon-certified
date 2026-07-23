/// LRU (Least Recently Used) Cache with O(1) amortized operations.
///
/// Stores key-value pairs with a fixed capacity. On access (get or put),
/// the accessed entry is moved to the most-recently-used position. When
/// capacity is exceeded, the least-recently-used entry is evicted.
///
/// Implementation: hash map + doubly linked list.
/// - The doubly linked list maintains recency order (head = LRU, tail = MRU).
/// - A hash map (`@hash_table.HashTable[K, Int]`) maps keys to node indices,
///   providing O(1) amortized key lookup.
/// - All operations (get, put) are O(1) amortized.
///
/// Not formally verified. Correctness ensured by comprehensive tests.

/// A node in the doubly linked list of cache entries.
///
/// Public so that `LRUCache` (a public type) may reference it; the fields
/// remain package-private, so the type is opaque to external users.
pub struct LruNode[K, V] {
  mut key : K
  mut val : V
  mut prev : Int  // index of previous node, -1 for head
  mut next : Int  // index of next node, -1 for tail
}

pub struct LRUCache[K, V] {
  /// Flat array of all allocated nodes (indices used as pointers).
  nodes : Array[LruNode[K, V]]
  /// Hash map: key → node index, for O(1) amortized key lookup.
  index : @hash_table.HashTable[K, Int]
  /// Index of the head (LRU) node, -1 if empty.
  mut head : Int
  /// Index of the tail (MRU) node, -1 if empty.
  mut tail : Int
  /// Number of entries currently in the cache.
  mut count : Int
  /// Maximum number of entries.
  capacity : Int
  /// Hash function for key lookup.
  hash_fn : (K) -> Int
  /// Equality function for key comparison.
  eq_fn : (K, K) -> Bool
}

/// Create an empty LRU cache with the given capacity.
///
/// `hash_fn` maps keys to integers for hash table indexing.
/// `eq_fn` checks key equality.
/// A capacity of 0 means no entries can be stored.
pub fn[K, V] new(
  capacity : Int,
  hash_fn : (K) -> Int,
  eq_fn : (K, K) -> Bool,
) -> LRUCache[K, V] {
  let cap = if capacity > 0 { capacity } else { 1 }
  {
    nodes: [],
    index: @hash_table.new(cap * 2 + 1),
    head: -1,
    tail: -1,
    count: 0,
    capacity,
    hash_fn,
    eq_fn,
  }
}

/// Number of entries currently in the cache.
pub fn[K, V] size(cache : LRUCache[K, V]) -> Int {
  cache.count
}

/// Detach a node from the doubly linked list.
fn[K, V] detach(cache : LRUCache[K, V], idx : Int) -> Unit {
  let node = cache.nodes[idx]
  if node.prev >= 0 {
    cache.nodes[node.prev].next = node.next
  } else {
    cache.head = node.next
  }
  if node.next >= 0 {
    cache.nodes[node.next].prev = node.prev
  } else {
    cache.tail = node.prev
  }
  cache.nodes[idx].prev = -1
  cache.nodes[idx].next = -1
}

/// Attach a node at the tail (MRU position).
fn[K, V] attach_tail(cache : LRUCache[K, V], idx : Int) -> Unit {
  if cache.tail >= 0 {
    cache.nodes[idx].prev = cache.tail
    cache.nodes[idx].next = -1
    cache.nodes[cache.tail].next = idx
    cache.tail = idx
  } else {
    // List was empty
    cache.head = idx
    cache.tail = idx
    cache.nodes[idx].prev = -1
    cache.nodes[idx].next = -1
  }
}

/// Move an existing node to the tail (MRU position). O(1).
fn[K, V] move_to_tail(cache : LRUCache[K, V], idx : Int) -> Unit {
  if cache.tail == idx {
    return  // Already at tail
  }
  detach(cache, idx)
  attach_tail(cache, idx)
}

/// Look up a key. On hit, moves the entry to MRU position and returns
/// the value. On miss, returns None. O(1) amortized.
pub fn[K, V] get(
  cache : LRUCache[K, V],
  key : K,
) -> V? {
  match @hash_table.get(cache.index, key, cache.hash_fn, cache.eq_fn) {
    None => None
    Some(idx) => {
      move_to_tail(cache, idx)
      Some(cache.nodes[idx].val)
    }
  }
}

/// Insert or update a key-value pair. On update, moves the entry to MRU.
/// On insert when at capacity, evicts the LRU entry first.
/// O(1) amortized.
pub fn[K, V] put(
  cache : LRUCache[K, V],
  key : K,
  value : V,
) -> Unit {
  if cache.capacity <= 0 {
    return
  }
  match @hash_table.get(cache.index, key, cache.hash_fn, cache.eq_fn) {
    Some(idx) => {
      // Key exists: update value and move to tail.
      cache.nodes[idx].val = value
      move_to_tail(cache, idx)
    }
    None => {
      // New key
      if cache.count >= cache.capacity {
        // Evict LRU (head): reuse the head node's slot.
        let head_idx = cache.head
        // Remove old key from hash map.
        let _ = @hash_table.remove(
          cache.index, cache.nodes[head_idx].key, cache.hash_fn, cache.eq_fn,
        )
        detach(cache, head_idx)
        // Reuse the slot for the new entry
        cache.nodes[head_idx].key = key
        cache.nodes[head_idx].val = value
        attach_tail(cache, head_idx)
        // Insert new key→index mapping.
        @hash_table.insert(
          cache.index, key, head_idx, cache.hash_fn, cache.eq_fn,
        )
      } else {
        // Append a new node
        let new_idx = cache.nodes.length()
        cache.nodes.push({ key, val: value, prev: -1, next: -1 })
        attach_tail(cache, new_idx)
        cache.count = cache.count + 1
        @hash_table.insert(
          cache.index, key, new_idx, cache.hash_fn, cache.eq_fn,
        )
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

/// Simple identity hash for Int keys.
fn int_hash(k : Int) -> Int {
  k
}

fn int_eq(a : Int, b : Int) -> Bool {
  a == b
}

test "lru: basic get and put" {
  let cache : LRUCache[Int, String] = new(3, int_hash, int_eq)
  put(cache, 1, "one")
  put(cache, 2, "two")
  put(cache, 3, "three")
  assert_eq(get(cache, 1), Some("one"))
  assert_eq(get(cache, 2), Some("two"))
  assert_eq(get(cache, 3), Some("three"))
  assert_eq(size(cache), 3)
}

test "lru: eviction order" {
  let cache : LRUCache[Int, Int] = new(2, int_hash, int_eq)
  put(cache, 1, 10)
  put(cache, 2, 20)
  put(cache, 3, 30) // evicts 1 (LRU)
  assert_true(get(cache, 1) is None)
  assert_eq(get(cache, 2), Some(20))
  assert_eq(get(cache, 3), Some(30))
  assert_eq(size(cache), 2)
}

test "lru: update existing key" {
  let cache : LRUCache[Int, String] = new(2, int_hash, int_eq)
  put(cache, 1, "old")
  put(cache, 2, "two")
  put(cache, 1, "new") // update, not evict
  assert_eq(size(cache), 2)
  // 1 is now MRU (updated), 2 is LRU; adding 3 evicts 2.
  put(cache, 3, "three")
  assert_true(get(cache, 2) is None)
  assert_eq(get(cache, 1), Some("new"))
  assert_eq(get(cache, 3), Some("three"))
}

test "lru: capacity 1" {
  let cache : LRUCache[Int, Int] = new(1, int_hash, int_eq)
  put(cache, 1, 100)
  assert_eq(get(cache, 1), Some(100))
  put(cache, 2, 200) // evicts 1
  assert_true(get(cache, 1) is None)
  assert_eq(get(cache, 2), Some(200))
  assert_eq(size(cache), 1)
}

test "lru: capacity 0" {
  let cache : LRUCache[Int, Int] = new(0, int_hash, int_eq)
  put(cache, 1, 100)
  assert_eq(size(cache), 0)
  assert_true(get(cache, 1) is None)
}

test "lru: non-existent key" {
  let cache : LRUCache[Int, Int] = new(3, int_hash, int_eq)
  put(cache, 1, 10)
  put(cache, 2, 20)
  assert_true(get(cache, 99) is None)
  assert_eq(size(cache), 2)
}

test "lru: ordering after multiple gets" {
  let cache : LRUCache[Int, Int] = new(3, int_hash, int_eq)
  put(cache, 1, 10)
  put(cache, 2, 20)
  put(cache, 3, 30)
  let _ = get(cache, 1) // order: 2, 3, 1
  let _ = get(cache, 2) // order: 3, 1, 2
  put(cache, 4, 40)    // evicts 3 (LRU)
  assert_true(get(cache, 3) is None)
  assert_eq(get(cache, 1), Some(10))
  assert_eq(get(cache, 2), Some(20))
  assert_eq(get(cache, 4), Some(40))
}

test "lru: stress test 100 operations" {
  let cache : LRUCache[Int, Int] = new(10, int_hash, int_eq)
  for i = 0; i < 10; i = i + 1 {
    put(cache, i, i * 10)
  }
  assert_eq(size(cache), 10)
  for i = 0; i < 10; i = i + 2 {
    let _ = get(cache, i)
  }
  for i = 10; i < 20; i = i + 1 {
    put(cache, i, i * 10)
  }
  assert_eq(size(cache), 10)
  for i = 10; i < 20; i = i + 1 {
    assert_eq(get(cache, i), Some(i * 10))
  }
  for i = 0; i < 10; i = i + 1 {
    assert_true(get(cache, i) is None)
  }
}

test "lru: string keys with custom hash" {
  let str_hash = fn(s : String) -> Int {
    let mut h = 0
    for i = 0; i < s.length(); i = i + 1 {
      h = h * 31 + s[i].to_int()
    }
    h
  }
  let str_eq = fn(a : String, b : String) -> Bool { a == b }
  let cache : LRUCache[String, Int] = new(3, str_hash, str_eq)
  put(cache, "apple", 1)
  put(cache, "banana", 2)
  put(cache, "cherry", 3)
  assert_eq(get(cache, "banana"), Some(2))
  put(cache, "date", 4) // evicts "apple" (LRU)
  assert_true(get(cache, "apple") is None)
  assert_eq(get(cache, "date"), Some(4))
}
