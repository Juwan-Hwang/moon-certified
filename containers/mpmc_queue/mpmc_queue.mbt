/// MPMC Bounded Queue — Vyukov's Algorithm (Single-Threaded Simulation)
/// ========================================================================
///
/// **⚠️ WARNING: NOT thread-safe.** Despite the "MPMC" name, this is a
/// single-threaded simulation. MoonBit compiles to Wasm/JS without atomic
/// primitives, so CAS always succeeds. **Do not use from multiple threads.**
///
/// This is a bounded MPMC queue based on the array-based ring buffer
/// design described by Dmitry Vyukov (used in Linux kernel, Intel TBB,
/// Folly). Unlike the Michael-Scott linked-list queue, this uses a
/// pre-allocated array with per-slot sequence numbers, achieving
/// better cache locality and no ABA problem.
///
/// ## Concurrency model
///
/// MoonBit currently compiles to WebAssembly / JavaScript, which are
/// **single-threaded** execution environments. There is no native
/// compare-and-swap (CAS) or atomic primitive in the language.
///
/// This implementation is a **faithful single-threaded simulation**:
/// - The data-structure layout, per-slot sequence numbers, and CAS
///   retry loops exactly match Vyukov's algorithm.
/// - Each CAS site is explicitly marked in the code, so the algorithm's
///   atomic-operation profile can be observed and tested.
/// - In single-threaded mode, every CAS trivially succeeds (no other
///   thread can have raced), so the queue is correct by construction.
///
/// When MoonBit gains multi-threading and atomics, upgrading this module
/// to a true lock-free queue requires only replacing the simulated CAS
/// sites with real atomic CAS — the public API and algorithm structure
/// stay identical.
///
/// ## Real concurrency today: spin mutex
///
/// For code that needs **actual mutual exclusion** in MoonBit's current
/// cooperative runtime, use the spin mutex from the `containers/concurrent`
/// module's `AsyncQueue[T]` for a production-grade mutex-protected queue
/// that works with MoonBit's cooperative scheduler.
///
/// ## Algorithm
///
/// Each slot in the ring buffer has a `sequence` number:
/// - If `sequence == pos`, the slot is ready for enqueue.
/// - If `sequence == pos + 1`, the slot is ready for dequeue.
///
/// ### Enqueue(item) -> Bool
///   1. Loop: `pos = tail`, `seq = slots[pos & mask].sequence`
///   2. If `seq == pos`: CAS `tail: pos -> pos+1`, then write item.
///   3. If `seq < pos`: queue is full, return false.
///
/// ### Dequeue() -> T?
///   1. Loop: `pos = head`, `seq = slots[pos & mask].sequence`
///   2. If `seq == pos + 1`: CAS `head: pos -> pos+1`, then read item.
///   3. If `seq < pos + 1`: queue is empty, return None.
///
/// In single-threaded mode, CAS always succeeds.
///
/// ## Complexity
/// - Time: O(1) enqueue and dequeue.
/// - Space: O(capacity) pre-allocated.
///
/// Reference: D. Vyukov, "Bounded MPMC queue"
/// (https://www.1024cores.net/home/lock-free-algorithms/queues/bounded-mpmc-queue)
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

///|
/// A bounded MPMC queue using Vyukov's algorithm (single-threaded simulation).
///
/// See the module-level documentation for the concurrency model and
/// upgrade path to real lock-free operation.
pub struct MPMCQueue[T] {
  priv buffer : FixedArray[T?]
  priv sequences : FixedArray[Int]
  priv mut head : Int
  priv mut tail : Int
  priv mask : Int
  priv capacity : Int
}

///|
/// Create a bounded MPMC queue with the given `capacity`.
///
/// Capacity is rounded up to the next power of two for O(1) modular
/// indexing. Negative capacity is clamped to 2.
pub fn[T] mpmc_queue_new(capacity : Int) -> MPMCQueue[T] {
  let mut cap = if capacity < 2 { 2 } else { capacity }
  // Round up to power of 2.
  let mut p = 1
  while p < cap {
    p = p * 2
  }
  cap = p
  let buffer : FixedArray[T?] = FixedArray::make(cap, None)
  let sequences = FixedArray::make(cap, 0)
  for i = 0; i < cap; i = i + 1 {
    sequences[i] = i
  }
  { buffer, sequences, head: 0, tail: 0, mask: cap - 1, capacity: cap }
}

///|
/// Try to enqueue `item`.
///
/// Returns `true` on success, `false` if the queue is full.
pub fn[T] mpmc_queue_enqueue(q : MPMCQueue[T], item : T) -> Bool {
  let mut pos = q.tail
  while true {
    let slot = pos & q.mask
    let seq = q.sequences[slot]
    let diff = seq - pos
    if diff == 0 {
      // CAS: tail: pos -> pos + 1
      q.tail = pos + 1
      q.buffer[slot] = Some(item)
      q.sequences[slot] = pos + 1
      return true
    } else if diff < 0 {
      // Queue is full.
      return false
    } else {
      // Another producer beat us; retry.
      pos = q.tail
    }
  }
  false // unreachable
}

///|
/// Try to dequeue an element.
///
/// Returns `Some(item)` on success, `None` if the queue is empty.
pub fn[T] mpmc_queue_dequeue(q : MPMCQueue[T]) -> T? {
  let mut pos = q.head
  while true {
    let slot = pos & q.mask
    let seq = q.sequences[slot]
    let diff = seq - (pos + 1)
    if diff == 0 {
      // CAS: head: pos -> pos + 1
      q.head = pos + 1
      let value = q.buffer[slot]
      q.buffer[slot] = None
      q.sequences[slot] = pos + q.capacity
      return value
    } else if diff < 0 {
      // Queue is empty.
      return None
    } else {
      // Another consumer beat us; retry.
      pos = q.head
    }
  }
  None // unreachable
}

///|
/// Number of elements currently in the queue. O(1).
pub fn[T] mpmc_queue_size(q : MPMCQueue[T]) -> Int {
  let t = q.tail
  let h = q.head
  // tail and head are monotonically increasing sequence numbers.
  // The actual element count is (tail - head), which correctly handles
  // wraparound because both are unbounded counters (not indices).
  if t >= h {
    t - h
  } else {
    // This should not happen in a correct single-threaded simulation,
    // but return 0 as a safe default.
    0
  }
}

///|
/// True if the queue is empty. O(1).
pub fn[T] mpmc_queue_is_empty(q : MPMCQueue[T]) -> Bool {
  q.head == q.tail
}

///|
/// Maximum capacity. O(1).
pub fn[T] mpmc_queue_capacity(q : MPMCQueue[T]) -> Int {
  q.capacity
}

// ---------------------------------------------------------------------------
// Unified API aliases
// ---------------------------------------------------------------------------

///|
/// Alias for `mpmc_queue_enqueue` — unified `push` naming.
///
/// The `containers/` directory uses a mix of `push`/`pop` (RingBuffer,
/// TreiberStack) and `enqueue`/`dequeue` (LockFreeQueue, MPMCQueue).
/// This alias allows callers to use `push`/`pop` uniformly across all
/// queue types.
pub fn[T] mpmc_queue_push(q : MPMCQueue[T], item : T) -> Bool {
  mpmc_queue_enqueue(q, item)
}

///|
/// Alias for `mpmc_queue_dequeue` — unified `pop` naming.
pub fn[T] mpmc_queue_pop(q : MPMCQueue[T]) -> T? {
  mpmc_queue_dequeue(q)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "mpmc_queue: basic enqueue and dequeue" {
  let q : MPMCQueue[Int] = mpmc_queue_new(4)
  assert_true(mpmc_queue_is_empty(q))
  assert_eq(mpmc_queue_dequeue(q), None)
  assert_true(mpmc_queue_enqueue(q, 10))
  assert_true(mpmc_queue_enqueue(q, 20))
  assert_eq(mpmc_queue_size(q), 2)
  assert_eq(mpmc_queue_dequeue(q), Some(10))
  assert_eq(mpmc_queue_dequeue(q), Some(20))
  assert_true(mpmc_queue_is_empty(q))
}

///|
test "mpmc_queue: FIFO order" {
  let q : MPMCQueue[Int] = mpmc_queue_new(100)
  for i = 0; i < 50; i = i + 1 {
    assert_true(mpmc_queue_enqueue(q, i))
  }
  for i = 0; i < 50; i = i + 1 {
    assert_eq(mpmc_queue_dequeue(q), Some(i))
  }
}

///|
test "mpmc_queue: full queue" {
  let q : MPMCQueue[Int] = mpmc_queue_new(4)
  assert_true(mpmc_queue_enqueue(q, 1))
  assert_true(mpmc_queue_enqueue(q, 2))
  assert_true(mpmc_queue_enqueue(q, 3))
  assert_true(mpmc_queue_enqueue(q, 4))
  // Queue should be full.
  assert_false(mpmc_queue_enqueue(q, 99))
  assert_eq(mpmc_queue_size(q), 4)
  assert_eq(mpmc_queue_dequeue(q), Some(1))
  assert_true(mpmc_queue_enqueue(q, 99))
}

///|
test "mpmc_queue: wrap-around" {
  let q : MPMCQueue[Int] = mpmc_queue_new(4)
  for i = 0; i < 3; i = i + 1 {
    assert_true(mpmc_queue_enqueue(q, i))
  }
  for i = 0; i < 3; i = i + 1 {
    assert_eq(mpmc_queue_dequeue(q), Some(i))
  }
  // Queue is empty but head/tail have wrapped.
  for i = 0; i < 3; i = i + 1 {
    assert_true(mpmc_queue_enqueue(q, 100 + i))
  }
  for i = 0; i < 3; i = i + 1 {
    assert_eq(mpmc_queue_dequeue(q), Some(100 + i))
  }
}

///|
test "mpmc_queue: generic with String" {
  let q : MPMCQueue[String] = mpmc_queue_new(4)
  ignore(mpmc_queue_enqueue(q, "hello"))
  ignore(mpmc_queue_enqueue(q, "world"))
  assert_eq(mpmc_queue_dequeue(q), Some("hello"))
  assert_eq(mpmc_queue_dequeue(q), Some("world"))
}

///|
test "mpmc_queue: interleave" {
  let q : MPMCQueue[Int] = mpmc_queue_new(8)
  ignore(mpmc_queue_enqueue(q, 1))
  ignore(mpmc_queue_enqueue(q, 2))
  assert_eq(mpmc_queue_dequeue(q), Some(1))
  ignore(mpmc_queue_enqueue(q, 3))
  assert_eq(mpmc_queue_dequeue(q), Some(2))
  ignore(mpmc_queue_enqueue(q, 4))
  assert_eq(mpmc_queue_dequeue(q), Some(3))
  assert_eq(mpmc_queue_dequeue(q), Some(4))
  assert_true(mpmc_queue_is_empty(q))
}

///|
test "mpmc_queue: capacity is power of 2" {
  let q : MPMCQueue[Int] = mpmc_queue_new(5)
  assert_eq(mpmc_queue_capacity(q), 8)
  let q2 : MPMCQueue[Int] = mpmc_queue_new(8)
  assert_eq(mpmc_queue_capacity(q2), 8)
}
