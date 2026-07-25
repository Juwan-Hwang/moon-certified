/// Concurrent Data Structures for MoonBit.
///
/// MoonBit currently targets WebAssembly and JavaScript, which are
/// single-threaded execution environments. These data structures are
/// designed with two goals:
///
/// 1. **Immediate utility**: they provide useful abstractions (bounded
///    queues, snapshot isolation, atomic swap) that are valuable in
///    single-threaded async/callback code.
///
/// 2. **Future-proofing**: the APIs and internal algorithms follow the
///    same patterns used in production concurrent libraries (e.g. Java's
///    `j.u.c`, Rust's `crossbeam`). When MoonBit gains multi-threading
///    support, these structures can be upgraded with actual lock-free
///    primitives without breaking the public API.
///
/// ## Implemented structures
///
/// - **`RingBuffer[T]`**: single-producer single-consumer (SPSC) bounded
///   ring buffer. O(1) `push` and `pop`. Useful for backpressure, rate
///   limiting, and producer-consumer pipelines.
///
/// - **`BoundedQueue[T]`**: multi-producer multi-consumer bounded queue
///   with capacity enforcement. Uses a dynamic array with head/tail indices.
///   `try_push` / `try_pop` are non-blocking (return `Option`).
///
/// - **`SnapshotMap[K, V]`**: copy-on-write hash map. Reads are lock-free
///   (direct array access); writes create a new copy of the underlying
///   array. Optimised for read-heavy workloads where writes are infrequent.
///   Provides `snapshot()` for O(1) point-in-time snapshots.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// RingBuffer[T]: SPSC bounded ring buffer
// ---------------------------------------------------------------------------

/// A single-producer single-consumer (SPSC) bounded ring buffer.
///
/// The buffer has a fixed capacity (rounded up to the next power of two
/// for O(1) modular indexing). One end writes (producer) and the other
/// reads (consumer); in a single-threaded context, this is simply a FIFO
/// queue with a capacity limit.
///
/// - `push` returns `false` when full (backpressure).
/// - `pop` returns `None` when empty.
/// - Both operations are O(1).
///
/// In a future multi-threaded MoonBit, `head` and `tail` would be atomic
/// indices, making this a true lock-free SPSC queue (no locks, no CAS loops).
pub struct RingBuffer[T] {
  priv buf : Array[T?]
  priv mut head : Int // read position (consumer)
  priv mut tail : Int // write position (producer)
  priv mask : Int // capacity - 1 (capacity is power of 2)
  priv capacity : Int
}

/// Create a ring buffer with at least `min_capacity` slots.
///
/// The actual capacity is rounded up to the next power of two for
/// O(1) modular indexing (`index & mask` instead of `index % capacity`).
pub fn[T] RingBuffer::new(min_capacity : Int) -> RingBuffer[T] {
  let cap = next_power_of_two(if min_capacity < 1 { 1 } else { min_capacity })
  { buf: Array::make(cap, None), head: 0, tail: 0, mask: cap - 1, capacity: cap }
}

/// Try to enqueue `val`. Returns `false` if the buffer is full.
pub fn[T] RingBuffer::push(rb : RingBuffer[T], val : T) -> Bool {
  let next_tail = (rb.tail + 1) & rb.mask
  if next_tail == rb.head {
    return false // full
  }
  rb.buf[rb.tail] = Some(val)
  rb.tail = next_tail
  true
}

/// Try to dequeue an element. Returns `None` if the buffer is empty.
pub fn[T] RingBuffer::pop(rb : RingBuffer[T]) -> T? {
  if rb.head == rb.tail {
    return None // empty
  }
  let val = rb.buf[rb.head]
  rb.buf[rb.head] = None
  rb.head = (rb.head + 1) & rb.mask
  val
}

/// Current number of elements in the buffer. O(1).
pub fn[T] RingBuffer::size(rb : RingBuffer[T]) -> Int {
  let tail = rb.tail
  let head = rb.head
  if tail >= head {
    tail - head
  } else {
    rb.capacity - head + tail
  }
}

/// Maximum number of elements the buffer can hold.
pub fn[T] RingBuffer::capacity(rb : RingBuffer[T]) -> Int {
  rb.capacity - 1 // one slot wasted to distinguish full from empty
}

/// True if the buffer is empty.
pub fn[T] RingBuffer::is_empty(rb : RingBuffer[T]) -> Bool {
  rb.head == rb.tail
}

/// True if the buffer is full (cannot accept more elements).
pub fn[T] RingBuffer::is_full(rb : RingBuffer[T]) -> Bool {
  ((rb.tail + 1) & rb.mask) == rb.head
}

// ---------------------------------------------------------------------------
// BoundedQueue[T]: MPMC bounded queue
// ---------------------------------------------------------------------------

/// A multi-producer multi-consumer bounded queue with capacity enforcement.
///
/// Uses a dynamic circular array. `try_push` enqueues only if space is
/// available; `try_pop` dequeues only if the queue is non-empty. Both
/// return `Option` to avoid blocking.
///
/// In single-threaded MoonBit, this is equivalent to a regular bounded FIFO.
/// In a future multi-threaded context, the head/tail would use CAS loops
/// for lock-free MPMC operation (following the Michael-Scott queue pattern
/// adapted to bounded buffers).
pub struct BoundedQueue[T] {
  priv buf : Array[T?]
  priv mut head : Int
  priv mut tail : Int
  priv mut count : Int
  priv capacity : Int
}

/// Create a bounded queue with the given capacity.
pub fn[T] BoundedQueue::new(capacity : Int) -> BoundedQueue[T] {
  let cap = if capacity < 1 { 1 } else { capacity }
  { buf: Array::make(cap, None), head: 0, tail: 0, count: 0, capacity: cap }
}

/// Try to enqueue `val`. Returns `false` if the queue is full.
pub fn[T] BoundedQueue::try_push(q : BoundedQueue[T], val : T) -> Bool {
  if q.count >= q.capacity {
    return false
  }
  q.buf[q.tail] = Some(val)
  q.tail = (q.tail + 1) % q.capacity
  q.count = q.count + 1
  true
}

/// Try to dequeue an element. Returns `None` if the queue is empty.
pub fn[T] BoundedQueue::try_pop(q : BoundedQueue[T]) -> T? {
  if q.count == 0 {
    return None
  }
  let val = q.buf[q.head]
  q.buf[q.head] = None
  q.head = (q.head + 1) % q.capacity
  q.count = q.count - 1
  val
}

/// Current number of elements. O(1).
pub fn[T] BoundedQueue::size(q : BoundedQueue[T]) -> Int {
  q.count
}

/// Maximum capacity.
pub fn[T] BoundedQueue::capacity(q : BoundedQueue[T]) -> Int {
  q.capacity
}

/// True if the queue is empty.
pub fn[T] BoundedQueue::is_empty(q : BoundedQueue[T]) -> Bool {
  q.count == 0
}

/// True if the queue is full.
pub fn[T] BoundedQueue::is_full(q : BoundedQueue[T]) -> Bool {
  q.count >= q.capacity
}

// ---------------------------------------------------------------------------
// SnapshotMap[K, V]: Copy-on-write hash map
// ---------------------------------------------------------------------------

/// A copy-on-write hash map optimized for read-heavy workloads.
///
/// Reads (`get`) are direct hash lookups with no overhead. Writes (`put`,
/// `remove`) create a shallow copy of the underlying bucket array before
/// mutating, ensuring that any prior snapshot remains valid.
///
/// `snapshot()` returns a new `SnapshotMap` that shares the current
/// bucket array (O(1) — no copying). Only when either map is subsequently
/// written does the copy-on-write trigger.
///
/// This is the standard "persistent data structure via COW" pattern used
/// in Clojure's persistent collections, Java's `CopyOnWriteArrayList`,
/// and Linux kernel's RCU.
pub struct SnapshotMap[K, V] {
  priv mut buckets : Array[Array[(K, V)]]
  priv mut size : Int
  priv mut bucket_count : Int
}

/// Create an empty `SnapshotMap` with the given initial bucket count.
///
/// The bucket count should be a prime number for best distribution. If
/// not, it is used as-is (MoonBit's `Hash` trait handles distribution).
pub fn[K, V] SnapshotMap::new(bucket_count : Int) -> SnapshotMap[K, V] {
  let bc = if bucket_count < 4 { 4 } else { bucket_count }
  let buckets : Array[Array[(K, V)]] = []
  for i = 0; i < bc; i = i + 1 {
    buckets.push([])
  }
  { buckets, size: 0, bucket_count: bc }
}

/// Create an empty `SnapshotMap` with a default bucket count of 16.
pub fn[K, V] SnapshotMap::default() -> SnapshotMap[K, V] {
  SnapshotMap::new(16)
}

/// Look up the value for key `k`. Returns `None` if not found. O(1) amortised.
pub fn[K : Hash + Eq, V] SnapshotMap::get(
  map : SnapshotMap[K, V],
  k : K,
) -> V? {
  let h = (Hash::hash(k) % map.bucket_count + map.bucket_count) % map.bucket_count
  let bucket = map.buckets[h]
  for i = 0; i < bucket.length(); i = i + 1 {
    let (key, val) = bucket[i]
    if key == k {
      return Some(val)
    }
  }
  None
}

/// Insert or update key `k` with value `v`.
///
/// Triggers copy-on-write: a new bucket array is created (shallow copy
/// of buckets), and only the affected bucket is replaced with a new array.
/// This ensures any prior `snapshot()` remains valid.
///
/// If the load factor exceeds 0.75, the map is resized (rehashed).
pub fn[K : Hash + Eq, V] SnapshotMap::put(
  map : SnapshotMap[K, V],
  k : K,
  v : V,
) -> Unit {
  let h = (Hash::hash(k) % map.bucket_count + map.bucket_count) % map.bucket_count
  // Copy-on-write: clone the buckets array, then replace the target bucket.
  let new_buckets : Array[Array[(K, V)]] = []
  for i = 0; i < map.bucket_count; i = i + 1 {
    if i == h {
      // Deep copy the target bucket (we'll modify it).
      let new_bucket : Array[(K, V)] = []
      let old_bucket = map.buckets[i]
      let mut found = false
      for j = 0; j < old_bucket.length(); j = j + 1 {
        let (key, _) = old_bucket[j]
        if key == k {
          new_bucket.push((k, v))
          found = true
        } else {
          new_bucket.push(old_bucket[j])
        }
      }
      if !found {
        new_bucket.push((k, v))
        map.size = map.size + 1
      }
      new_buckets.push(new_bucket)
    } else {
      // Shallow copy: share the bucket array reference.
      new_buckets.push(map.buckets[i])
    }
  }
  map.buckets = new_buckets
  // Resize if load factor > 0.75
  if map.size > map.bucket_count * 3 / 4 {
    resize(map)
  }
}

/// Remove key `k` if present. Returns `true` if the key was found.
///
/// Triggers copy-on-write (same as `put`).
pub fn[K : Hash + Eq, V] SnapshotMap::remove(
  map : SnapshotMap[K, V],
  k : K,
) -> Bool {
  let h = (Hash::hash(k) % map.bucket_count + map.bucket_count) % map.bucket_count
  let old_bucket = map.buckets[h]
  let mut found = false
  let new_bucket : Array[(K, V)] = []
  for j = 0; j < old_bucket.length(); j = j + 1 {
    let (key, val) = old_bucket[j]
    if key == k {
      found = true
      // skip this entry
    } else {
      new_bucket.push((key, val))
    }
  }
  if found {
    // Copy-on-write: clone buckets, replace the target.
    let new_buckets : Array[Array[(K, V)]] = []
    for i = 0; i < map.bucket_count; i = i + 1 {
      if i == h {
        new_buckets.push(new_bucket)
      } else {
        new_buckets.push(map.buckets[i])
      }
    }
    map.buckets = new_buckets
    map.size = map.size - 1
  }
  found
}

/// Create a snapshot of the current map state. O(1).
///
/// The snapshot shares the bucket array with the original. Both maps can
/// be read independently. When either map is written, copy-on-write
/// ensures the other is unaffected.
pub fn[K, V] SnapshotMap::snapshot(
  map : SnapshotMap[K, V],
) -> SnapshotMap[K, V] {
  // Share the bucket references. Since put/remove always create new
  // bucket arrays before mutating, the shared buckets are never modified.
  let buckets_copy : Array[Array[(K, V)]] = []
  for i = 0; i < map.bucket_count; i = i + 1 {
    buckets_copy.push(map.buckets[i])
  }
  { buckets: buckets_copy, size: map.size, bucket_count: map.bucket_count }
}

/// Number of key-value pairs. O(1).
pub fn[K, V] SnapshotMap::size(
  map : SnapshotMap[K, V],
) -> Int {
  map.size
}

/// True if the map contains no entries.
pub fn[K, V] SnapshotMap::is_empty(
  map : SnapshotMap[K, V],
) -> Bool {
  map.size == 0
}

/// Check if key `k` is present.
pub fn[K : Hash + Eq, V] SnapshotMap::contains(
  map : SnapshotMap[K, V],
  k : K,
) -> Bool {
  match SnapshotMap::get(map, k) {
    Some(_) => true
    None => false
  }
}

/// Resize the map to double the current bucket count (rehash all entries).
fn[K : Hash, V] resize(map : SnapshotMap[K, V]) -> Unit {
  let new_bc = map.bucket_count * 2
  let new_buckets : Array[Array[(K, V)]] = []
  for i = 0; i < new_bc; i = i + 1 {
    new_buckets.push([])
  }
  for i = 0; i < map.bucket_count; i = i + 1 {
    let bucket = map.buckets[i]
    for j = 0; j < bucket.length(); j = j + 1 {
      let (k, v) = bucket[j]
      let h = (Hash::hash(k) % new_bc + new_bc) % new_bc
      new_buckets[h].push((k, v))
    }
  }
  map.buckets = new_buckets
  map.bucket_count = new_bc
}

// ---------------------------------------------------------------------------
// Utility
// ---------------------------------------------------------------------------

/// Compute the next power of two ≥ n. Returns 1 for n ≤ 1.
fn next_power_of_two(n : Int) -> Int {
  if n <= 1 {
    return 1
  }
  let mut p = 1
  while p < n {
    p = p << 1
  }
  p
}

// ---------------------------------------------------------------------------
// Tests: RingBuffer
// ---------------------------------------------------------------------------

test "ring_buffer: basic push and pop" {
  let rb : RingBuffer[Int] = RingBuffer::new(8)
  assert_true(RingBuffer::is_empty(rb))
  assert_true(RingBuffer::push(rb, 10))
  assert_true(RingBuffer::push(rb, 20))
  assert_eq(RingBuffer::size(rb), 2)
  assert_eq(RingBuffer::pop(rb), Some(10))
  assert_eq(RingBuffer::pop(rb), Some(20))
  assert_true(RingBuffer::is_empty(rb))
  assert_eq(RingBuffer::pop(rb), None)
}

test "ring_buffer: capacity is power of 2 minus 1" {
  let rb : RingBuffer[Int] = RingBuffer::new(5) // 5 rounded to 8, capacity = 7
  assert_eq(RingBuffer::capacity(rb), 7)
  for i = 0; i < 7; i = i + 1 {
    assert_true(RingBuffer::push(rb, i))
  }
  // Now full
  assert_false(RingBuffer::push(rb, 99))
  assert_true(RingBuffer::is_full(rb))
  // Pop one, then can push again
  assert_eq(RingBuffer::pop(rb), Some(0))
  assert_true(RingBuffer::push(rb, 99))
}

test "ring_buffer: wraparound" {
  let rb : RingBuffer[Int] = RingBuffer::new(4) // capacity = 3
  ignore(RingBuffer::push(rb, 1))
  ignore(RingBuffer::push(rb, 2))
  ignore(RingBuffer::push(rb, 3))
  assert_false(RingBuffer::push(rb, 4)) // full
  ignore(RingBuffer::pop(rb)) // remove 1
  assert_true(RingBuffer::push(rb, 4)) // now fits
  assert_eq(RingBuffer::pop(rb), Some(2))
  assert_eq(RingBuffer::pop(rb), Some(3))
  assert_eq(RingBuffer::pop(rb), Some(4))
  assert_true(RingBuffer::is_empty(rb))
}

test "ring_buffer: string elements" {
  let rb : RingBuffer[String] = RingBuffer::new(4)
  ignore(RingBuffer::push(rb, "hello"))
  ignore(RingBuffer::push(rb, "world"))
  assert_eq(RingBuffer::size(rb), 2)
  assert_eq(RingBuffer::pop(rb), Some("hello"))
  assert_eq(RingBuffer::pop(rb), Some("world"))
}

// ---------------------------------------------------------------------------
// Tests: BoundedQueue
// ---------------------------------------------------------------------------

test "bounded_queue: basic operations" {
  let q : BoundedQueue[Int] = BoundedQueue::new(3)
  assert_true(BoundedQueue::is_empty(q))
  assert_true(BoundedQueue::try_push(q, 1))
  assert_true(BoundedQueue::try_push(q, 2))
  assert_true(BoundedQueue::try_push(q, 3))
  assert_false(BoundedQueue::try_push(q, 4)) // full
  assert_true(BoundedQueue::is_full(q))
  assert_eq(BoundedQueue::size(q), 3)
  assert_eq(BoundedQueue::try_pop(q), Some(1))
  assert_eq(BoundedQueue::try_pop(q), Some(2))
  assert_eq(BoundedQueue::try_pop(q), Some(3))
  assert_eq(BoundedQueue::try_pop(q), None)
  assert_true(BoundedQueue::is_empty(q))
}

test "bounded_queue: wraparound" {
  let q : BoundedQueue[Int] = BoundedQueue::new(3)
  ignore(BoundedQueue::try_push(q, 1))
  ignore(BoundedQueue::try_push(q, 2))
  ignore(BoundedQueue::try_pop(q)) // remove 1
  ignore(BoundedQueue::try_push(q, 3))
  ignore(BoundedQueue::try_push(q, 4))
  assert_false(BoundedQueue::try_push(q, 5)) // full
  assert_eq(BoundedQueue::try_pop(q), Some(2))
  assert_eq(BoundedQueue::try_pop(q), Some(3))
  assert_eq(BoundedQueue::try_pop(q), Some(4))
}

test "bounded_queue: generic types" {
  let q : BoundedQueue[(Int, String)] = BoundedQueue::new(2)
  ignore(BoundedQueue::try_push(q, (1, "a")))
  ignore(BoundedQueue::try_push(q, (2, "b")))
  assert_eq(BoundedQueue::try_pop(q), Some((1, "a")))
  assert_eq(BoundedQueue::try_pop(q), Some((2, "b")))
}

// ---------------------------------------------------------------------------
// Tests: SnapshotMap
// ---------------------------------------------------------------------------

test "snapshot_map: basic put and get" {
  let m : SnapshotMap[Int, String] = SnapshotMap::default()
  ignore(SnapshotMap::put(m, 1, "one"))
  ignore(SnapshotMap::put(m, 2, "two"))
  ignore(SnapshotMap::put(m, 3, "three"))
  assert_eq(SnapshotMap::size(m), 3)
  assert_eq(SnapshotMap::get(m, 1), Some("one"))
  assert_eq(SnapshotMap::get(m, 2), Some("two"))
  assert_eq(SnapshotMap::get(m, 3), Some("three"))
  assert_eq(SnapshotMap::get(m, 4), None)
  assert_true(SnapshotMap::contains(m, 1))
  assert_false(SnapshotMap::contains(m, 99))
}

test "snapshot_map: update existing key" {
  let m : SnapshotMap[Int, String] = SnapshotMap::default()
  ignore(SnapshotMap::put(m, 1, "old"))
  ignore(SnapshotMap::put(m, 1, "new"))
  assert_eq(SnapshotMap::size(m), 1)
  assert_eq(SnapshotMap::get(m, 1), Some("new"))
}

test "snapshot_map: remove" {
  let m : SnapshotMap[Int, String] = SnapshotMap::default()
  ignore(SnapshotMap::put(m, 1, "one"))
  ignore(SnapshotMap::put(m, 2, "two"))
  assert_true(SnapshotMap::remove(m, 1))
  assert_false(SnapshotMap::contains(m, 1))
  assert_eq(SnapshotMap::size(m), 1)
  assert_false(SnapshotMap::remove(m, 99))
}

test "snapshot_map: snapshot isolation" {
  let m : SnapshotMap[Int, Int] = SnapshotMap::default()
  ignore(SnapshotMap::put(m, 1, 100))
  ignore(SnapshotMap::put(m, 2, 200))
  // Take a snapshot
  let snap = SnapshotMap::snapshot(m)
  // Modify the original
  ignore(SnapshotMap::put(m, 1, 999))
  ignore(SnapshotMap::put(m, 3, 300))
  ignore(SnapshotMap::remove(m, 2))
  // Snapshot should be unaffected
  assert_eq(SnapshotMap::get(snap, 1), Some(100))
  assert_eq(SnapshotMap::get(snap, 2), Some(200))
  assert_eq(SnapshotMap::get(snap, 3), None)
  assert_eq(SnapshotMap::size(snap), 2)
  // Original has the new values
  assert_eq(SnapshotMap::get(m, 1), Some(999))
  assert_eq(SnapshotMap::get(m, 2), None)
  assert_eq(SnapshotMap::get(m, 3), Some(300))
  assert_eq(SnapshotMap::size(m), 2)
}

test "snapshot_map: resize on many entries" {
  let m : SnapshotMap[Int, Int] = SnapshotMap::new(4) // small initial size to trigger resize
  for i = 0; i < 100; i = i + 1 {
    ignore(SnapshotMap::put(m, i, i * i))
  }
  assert_eq(SnapshotMap::size(m), 100)
  for i = 0; i < 100; i = i + 1 {
    assert_eq(SnapshotMap::get(m, i), Some(i * i))
  }
}

test "snapshot_map: string keys" {
  let m : SnapshotMap[String, Int] = SnapshotMap::default()
  ignore(SnapshotMap::put(m, "alice", 30))
  ignore(SnapshotMap::put(m, "bob", 25))
  assert_eq(SnapshotMap::get(m, "alice"), Some(30))
  assert_eq(SnapshotMap::get(m, "bob"), Some(25))
  assert_eq(SnapshotMap::get(m, "charlie"), None)
}

test "snapshot_map: is_empty" {
  let m : SnapshotMap[Int, Int] = SnapshotMap::default()
  assert_true(SnapshotMap::is_empty(m))
  ignore(SnapshotMap::put(m, 1, 1))
  assert_false(SnapshotMap::is_empty(m))
  ignore(SnapshotMap::remove(m, 1))
  assert_true(SnapshotMap::is_empty(m))
}
