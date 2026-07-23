/// LRU (Least Recently Used) Cache.
///
/// Stores key-value pairs with a fixed capacity. On access (get or put),
/// the accessed entry is moved to the most-recently-used position. When
/// capacity is exceeded, the least-recently-used entry is evicted.
///
/// Implementation: doubly linked list + flat array (linear scan).
/// - The doubly linked list maintains recency order (head = LRU, tail = MRU).
/// - A flat array stores (key, value) entries for O(n) lookup by key.
/// - List operations (move-to-tail, remove-head) are O(1).
/// - Key lookup is O(n) in the worst case, but the doubly linked list
///   ensures that list manipulation is always O(1) regardless of capacity.
///
/// For small to medium capacities (≤ 10⁴), this is efficient in practice.
/// For very large caches, a true hash map would be needed, but MoonBit's
/// standard library `Map` requires `Hash` trait which limits generic use.
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
  /// Index of the head (LRU) node, -1 if empty.
  mut head : Int
  /// Index of the tail (MRU) node, -1 if empty.
  mut tail : Int
  /// Number of entries currently in the cache.
  mut count : Int
  /// Maximum number of entries.
  capacity : Int
}

/// Create an empty LRU cache with the given capacity.
/// A capacity of 0 means no entries can be stored.
pub fn[K, V] new(capacity : Int) -> LRUCache[K, V] {
  { nodes: [], head: -1, tail: -1, count: 0, capacity }
}

/// Number of entries currently in the cache.
pub fn[K, V] size(cache : LRUCache[K, V]) -> Int {
  cache.count
}

/// Find the index of the node with the given key. O(n) scan.
fn[K, V] find_index(
  cache : LRUCache[K, V],
  key : K,
  eq_fn : (K, K) -> Bool,
) -> Int {
  for i = 0; i < cache.nodes.length(); i = i + 1 {
    if eq_fn(cache.nodes[i].key, key) {
      return i
    }
  }
  -1
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
/// the value. On miss, returns None. O(n) for key lookup, O(1) for list update.
pub fn[K, V] get(
  cache : LRUCache[K, V],
  key : K,
  eq_fn : (K, K) -> Bool,
) -> V? {
  let idx = find_index(cache, key, eq_fn)
  if idx < 0 {
    return None
  }
  move_to_tail(cache, idx)
  Some(cache.nodes[idx].val)
}

/// Insert or update a key-value pair. On update, moves the entry to MRU.
/// On insert when at capacity, evicts the LRU entry first.
/// O(n) for key lookup, O(1) for list manipulation.
pub fn[K, V] put(
  cache : LRUCache[K, V],
  key : K,
  value : V,
  eq_fn : (K, K) -> Bool,
) -> Unit {
  if cache.capacity <= 0 {
    return
  }
  let idx = find_index(cache, key, eq_fn)
  if idx >= 0 {
    // Key exists: update value and move to tail.
    cache.nodes[idx].val = value
    move_to_tail(cache, idx)
    return
  }
  // New key
  if cache.count >= cache.capacity {
    // Evict LRU (head): reuse the head node's slot.
    let head_idx = cache.head
    detach(cache, head_idx)
    // Reuse the slot for the new entry
    cache.nodes[head_idx].key = key
    cache.nodes[head_idx].val = value
    attach_tail(cache, head_idx)
  } else {
    // Append a new node
    let new_idx = cache.nodes.length()
    cache.nodes.push({ key, val: value, prev: -1, next: -1 })
    attach_tail(cache, new_idx)
    cache.count = cache.count + 1
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
  assert_eq(size(cache), 2)
}

test "lru: ordering after multiple gets" {
  let cache : LRUCache[Int, Int] = new(3)
  put(cache, 1, 10, fn(a, b) { a == b })
  put(cache, 2, 20, fn(a, b) { a == b })
  put(cache, 3, 30, fn(a, b) { a == b })
  let _ = get(cache, 1, fn(a, b) { a == b }) // order: 2, 3, 1
  let _ = get(cache, 2, fn(a, b) { a == b }) // order: 3, 1, 2
  put(cache, 4, 40, fn(a, b) { a == b })    // evicts 3 (LRU)
  assert_true(get(cache, 3, fn(a, b) { a == b }) is None)
  assert_eq(get(cache, 1, fn(a, b) { a == b }), Some(10))
  assert_eq(get(cache, 2, fn(a, b) { a == b }), Some(20))
  assert_eq(get(cache, 4, fn(a, b) { a == b }), Some(40))
}

test "lru: stress test 100 operations" {
  let cache : LRUCache[Int, Int] = new(10)
  for i = 0; i < 10; i = i + 1 {
    put(cache, i, i * 10, fn(a, b) { a == b })
  }
  assert_eq(size(cache), 10)
  for i = 0; i < 10; i = i + 2 {
    let _ = get(cache, i, fn(a, b) { a == b })
  }
  for i = 10; i < 20; i = i + 1 {
    put(cache, i, i * 10, fn(a, b) { a == b })
  }
  assert_eq(size(cache), 10)
  for i = 10; i < 20; i = i + 1 {
    assert_eq(get(cache, i, fn(a, b) { a == b }), Some(i * 10))
  }
  for i = 0; i < 10; i = i + 1 {
    assert_true(get(cache, i, fn(a, b) { a == b }) is None)
  }
}
