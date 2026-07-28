/// Lock-Free Queue — Michael-Scott Algorithm (Single-Threaded Simulation)
/// ========================================================================
///
/// This module implements the **Michael-Scott lock-free queue**, the
/// de-facto industry-standard non-blocking MPMC (multi-producer
/// multi-consumer) queue algorithm:
///
///   Maged M. Michael, Michael L. Scott.
///   "Simple, Fast, and Practical Non-Blocking and Blocking Concurrent
///    Queue Algorithms."
///   PODC 1996.
///
/// ## Algorithm overview
///
/// The queue is a singly-linked list with a **sentinel (dummy) head node**:
///
/// ```text
///   head -> [dummy] -> [A] -> [B] -> NULL
///                                ^
///                              tail
/// ```
///
/// - `head` always points to a dummy node whose value is meaningless.
/// - `head.next` is the first live element.
/// - `tail` points to the last node.
/// - The queue is empty iff `head == tail` (i.e. `head.next == NULL`).
///
/// ### Enqueue(item) -> Bool
///   1. Allocate a free node `n` with `n.value = item`, `n.next = NULL`.
///   2. **CAS#1**: `tail.next: NULL -> n`.  (Link the new node.)
///   3. **CAS#2**: `tail: old_tail -> n`.  (Advance tail. Best-effort;
///      a helping thread may do this. In single-threaded mode it always
///      succeeds immediately.)
///
/// ### Dequeue() -> T?
///   1. If `head == tail` (empty), return `None`.
///   2. Read `value = head.next.value`.
///   3. **CAS#4**: `head: old_head -> head.next`.  (Swing head forward.)
///   4. Free the old dummy node.  Return `value`.
///
/// All CAS sites are atomic compare-and-swap operations in a real
/// multi-threaded implementation. In this simulation they always succeed
/// (see "Concurrency model" below).
///
/// ## Concurrency model
///
/// MoonBit currently compiles to WebAssembly / JavaScript, which are
/// **single-threaded** execution environments. There is no native
/// compare-and-swap (CAS) or atomic primitive in the language.
///
/// This implementation is a **faithful single-threaded simulation**:
/// - The data-structure layout, pointer choreography, and operation
///   sequence exactly match the Michael-Scott algorithm.
/// - Each CAS site is explicitly marked (`CAS#k`) and counted via
///   `cas_count`, so the algorithm's atomic-operation profile can be
///   observed and tested.
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
/// ## Bounded capacity (production optimisation)
///
/// Unlike the original (unbounded) Michael-Scott queue, this implementation
/// is **bounded**: nodes are pre-allocated from a fixed `FixedArray`-backed
/// pool (a "free list"). This is the standard production optimisation that
/// eliminates per-operation heap allocation and provides deterministic
/// memory usage. `enqueue` returns `false` when the pool is exhausted.
///
/// ## Time complexity
///
/// | Operation | Complexity |
/// |-----------|-----------|
/// | enqueue   | O(1)      |
/// | dequeue   | O(1)      |
/// | size      | O(1)      |
/// | is_empty  | O(1)      |
/// | is_full   | O(1)      |
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Data structure
// ---------------------------------------------------------------------------

///|
/// A bounded Michael-Scott lock-free queue (single-threaded simulation).
///
/// Internally, nodes live in a pre-allocated pool of `capacity + 1` slots
/// (the "+1" is the permanent sentinel). Three parallel `FixedArray`s
/// store the value, the next-pointer, and the free-list bookkeeping so
/// that **no per-operation heap allocation** occurs.
///
/// Pointer indices use `-1` to represent `NULL` (the end of a chain).
///
/// Field invariants:
/// - `free_top == capacity - count`  (free-list size mirrors live count)
/// - `head` and `tail` are always valid node indices (0 .. capacity)
/// - `nexts[tail] == -1`  (tail is always the last node)
/// - `count` live elements sit between `head` (exclusive) and `tail`
pub struct LockFreeQueue[T] {
  // --- node pool (fixed-size, never resized) ---
  priv values : FixedArray[T?] // values[i] = value of node i; None = empty
  priv nexts : FixedArray[Int] // nexts[i] = next node index; -1 = NULL
  // --- free list (LIFO stack of recycled node indices) ---
  priv free_stack : FixedArray[Int] // stack buffer
  priv mut free_top : Int // number of free indices currently in the stack
  // --- queue pointers (indices into the pool) ---
  priv mut head : Int // sentinel (dummy) node index
  priv mut tail : Int // last node index
  // --- bookkeeping ---
  priv mut count : Int // number of live elements
  priv mut cas_count : Int // total simulated CAS operations (diagnostic)
  priv capacity : Int // max live elements
}

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

///|
/// Create a bounded lock-free queue with the given `capacity`.
///
/// `capacity` is the maximum number of elements the queue can hold
/// simultaneously. A negative value is clamped to `0` (a queue that can
/// never hold elements). Internally, `capacity + 1` nodes are
/// pre-allocated: one permanent sentinel + `capacity` element slots.
///
/// All operations are O(1).
pub fn[T] lock_free_queue_new(capacity : Int) -> LockFreeQueue[T] {
  let cap = if capacity < 0 { 0 } else { capacity }
  let node_count = cap + 1 // +1 for the permanent sentinel
  // Node 0 is the initial sentinel; nodes 1..cap start on the free list.
  let values : FixedArray[T?] = FixedArray::make(node_count, None)
  let nexts = FixedArray::make(node_count, -1)
  // Free list: pre-load indices 1, 2, ..., cap (LIFO order).
  let free_stack = FixedArray::make(cap, 0)
  for i = 0; i < cap; i = i + 1 {
    free_stack[i] = i + 1
  }
  {
    values,
    nexts,
    free_stack,
    free_top: cap,
    head: 0,
    tail: 0,
    count: 0,
    cas_count: 0,
    capacity: cap,
  }
}

// ---------------------------------------------------------------------------
// Enqueue
// ---------------------------------------------------------------------------

///|
/// Enqueue `item` at the tail of the queue.
///
/// Returns `true` on success, `false` if the queue is full (no free node
/// available in the pool).
///
/// Simulated CAS sites (see module docs):
/// - **CAS#1** — link `tail.next` from NULL to the new node.
/// - **CAS#2** — advance `tail` to the new node.
///
/// O(1).
pub fn[T] lock_free_queue_enqueue(q : LockFreeQueue[T], item : T) -> Bool {
  // Step 1: allocate a free node from the pool (LIFO pop).
  if q.free_top == 0 {
    return false // pool exhausted → queue is full
  }
  q.free_top = q.free_top - 1
  let node = q.free_stack[q.free_top]
  // Initialise the new node.
  q.values[node] = Some(item)
  q.nexts[node] = -1 // NULL
  // Step 2 (CAS#1): link the current tail to the new node.
  //   Real CAS: cas(&tail.next, NULL, node)
  //   Single-threaded: tail.next is always NULL here (tail is the last
  //   node), so the CAS trivially succeeds.
  q.cas_count = q.cas_count + 1
  q.nexts[q.tail] = node
  // Step 3 (CAS#2): advance tail to the new node.
  //   Real CAS: cas(&tail, old_tail, node)
  //   In the original algorithm this is best-effort — a concurrent
  //   dequeueing thread may advance tail for us. Single-threaded: always
  //   succeeds.
  q.cas_count = q.cas_count + 1
  q.tail = node
  q.count = q.count + 1
  true
}

// ---------------------------------------------------------------------------
// Dequeue
// ---------------------------------------------------------------------------

///|
/// Dequeue and return the front element.
///
/// Returns `Some(item)` on success, `None` if the queue is empty.
///
/// Simulated CAS site (see module docs):
/// - **CAS#4** — swing `head` from the old sentinel to `head.next`.
///
/// O(1).
pub fn[T] lock_free_queue_dequeue(q : LockFreeQueue[T]) -> T? {
  // Step 1: check emptiness. The queue is empty iff head == tail, which
  // means head.next == NULL (no live element after the sentinel).
  if q.head == q.tail {
    return None
  }
  // Step 2: read the first live node and its value.
  let first = q.nexts[q.head] // guaranteed != -1 because head != tail
  let value = q.values[first]
  // Clear the slot so we don't retain a reference to the dequeued value.
  // The node `first` becomes the new sentinel; its value is meaningless.
  q.values[first] = None
  // Step 3 (CAS#4): swing head forward to `first`.
  //   Real CAS: cas(&head, old_head, first)
  //   Single-threaded: always succeeds.
  q.cas_count = q.cas_count + 1
  let old_head = q.head
  q.head = first
  // Step 4: recycle the old sentinel node back to the free pool (LIFO push).
  q.free_stack[q.free_top] = old_head
  q.free_top = q.free_top + 1
  q.count = q.count - 1
  value
}

// ---------------------------------------------------------------------------
// Queries
// ---------------------------------------------------------------------------

///|
/// Number of elements currently in the queue. O(1).
pub fn[T] lock_free_queue_size(q : LockFreeQueue[T]) -> Int {
  q.count
}

///|
/// True if the queue holds no elements. O(1).
///
/// Uses the algorithmically correct check `head == tail` (rather than
/// `count == 0`) to stay faithful to the Michael-Scott algorithm, which
/// does not maintain a count in a real lock-free setting.
pub fn[T] lock_free_queue_is_empty(q : LockFreeQueue[T]) -> Bool {
  q.head == q.tail
}

///|
/// True if the queue cannot accept more elements. O(1).
///
/// Uses the algorithmically correct check `free_top == 0` (the node pool
/// is exhausted), which is equivalent to `count == capacity`.
pub fn[T] lock_free_queue_is_full(q : LockFreeQueue[T]) -> Bool {
  q.free_top == 0
}

///|
/// Maximum number of elements the queue can hold. O(1).
pub fn[T] lock_free_queue_capacity(q : LockFreeQueue[T]) -> Int {
  q.capacity
}

///|
/// Total number of simulated CAS operations performed so far. O(1).
///
/// This is a diagnostic counter that records every compare-and-swap site
/// executed by `enqueue` and `dequeue`. In single-threaded mode every CAS
/// succeeds, so the count grows linearly with the number of operations:
/// - each successful `enqueue` performs 2 CAS (link + tail-advance);
/// - each successful `dequeue` performs 1 CAS (head-swing);
/// - a failed `enqueue` (full) or `dequeue` (empty) performs 0 CAS.
pub fn[T] lock_free_queue_cas_count(q : LockFreeQueue[T]) -> Int {
  q.cas_count
}

// ---------------------------------------------------------------------------
// Unified API aliases
// ---------------------------------------------------------------------------

///|
/// Alias for `lock_free_queue_enqueue` — unified `push` naming.
///
/// The `containers/` directory uses a mix of `push`/`pop` (RingBuffer,
/// TreiberStack) and `enqueue`/`dequeue` (LockFreeQueue, MPMCQueue).
/// This alias allows callers to use `push`/`pop` uniformly across all
/// queue types. The `enqueue`/`dequeue` names are retained for backward
/// compatibility and algorithm-specific documentation.
pub fn[T] lock_free_queue_push(q : LockFreeQueue[T], item : T) -> Bool {
  lock_free_queue_enqueue(q, item)
}

///|
/// Alias for `lock_free_queue_dequeue` — unified `pop` naming.
pub fn[T] lock_free_queue_pop(q : LockFreeQueue[T]) -> T? {
  lock_free_queue_dequeue(q)
}

// ---------------------------------------------------------------------------
// Tests: basic operations
// ---------------------------------------------------------------------------

///|
test "lock_free_queue: basic enqueue and dequeue" {
  let q : LockFreeQueue[Int] = lock_free_queue_new(4)
  assert_true(lock_free_queue_is_empty(q))
  assert_eq(lock_free_queue_size(q), 0)
  assert_eq(lock_free_queue_dequeue(q), None)
  // Enqueue two elements.
  assert_true(lock_free_queue_enqueue(q, 10))
  assert_true(lock_free_queue_enqueue(q, 20))
  assert_false(lock_free_queue_is_empty(q))
  assert_eq(lock_free_queue_size(q), 2)
  // Dequeue in FIFO order.
  assert_eq(lock_free_queue_dequeue(q), Some(10))
  assert_eq(lock_free_queue_dequeue(q), Some(20))
  assert_true(lock_free_queue_is_empty(q))
  assert_eq(lock_free_queue_dequeue(q), None)
}

///|
test "lock_free_queue: FIFO ordering over many elements" {
  let q : LockFreeQueue[Int] = lock_free_queue_new(100)
  for i = 0; i < 50; i = i + 1 {
    assert_true(lock_free_queue_enqueue(q, i * 2))
  }
  assert_eq(lock_free_queue_size(q), 50)
  for i = 0; i < 50; i = i + 1 {
    assert_eq(lock_free_queue_dequeue(q), Some(i * 2))
  }
  assert_true(lock_free_queue_is_empty(q))
}

// ---------------------------------------------------------------------------
// Tests: capacity and full/empty states
// ---------------------------------------------------------------------------

///|
test "lock_free_queue: full queue rejects enqueue" {
  let q : LockFreeQueue[Int] = lock_free_queue_new(3)
  assert_false(lock_free_queue_is_full(q))
  assert_true(lock_free_queue_enqueue(q, 1))
  assert_true(lock_free_queue_enqueue(q, 2))
  assert_true(lock_free_queue_enqueue(q, 3))
  assert_true(lock_free_queue_is_full(q))
  assert_eq(lock_free_queue_size(q), 3)
  assert_eq(lock_free_queue_capacity(q), 3)
  // Queue is full — enqueue must fail.
  assert_false(lock_free_queue_enqueue(q, 99))
  assert_eq(lock_free_queue_size(q), 3)
  // Free one slot, then enqueue succeeds.
  assert_eq(lock_free_queue_dequeue(q), Some(1))
  assert_false(lock_free_queue_is_full(q))
  assert_true(lock_free_queue_enqueue(q, 99))
  assert_true(lock_free_queue_is_full(q))
}

///|
test "lock_free_queue: empty queue dequeue returns None" {
  let q : LockFreeQueue[String] = lock_free_queue_new(2)
  assert_true(lock_free_queue_is_empty(q))
  assert_eq(lock_free_queue_dequeue(q), None)
  assert_eq(lock_free_queue_dequeue(q), None)
  assert_true(lock_free_queue_enqueue(q, "a"))
  assert_eq(lock_free_queue_dequeue(q), Some("a"))
  assert_eq(lock_free_queue_dequeue(q), None)
  assert_true(lock_free_queue_is_empty(q))
}

// ---------------------------------------------------------------------------
// Tests: interleaved operations and wraparound
// ---------------------------------------------------------------------------

///|
test "lock_free_queue: interleaved enqueue and dequeue" {
  let q : LockFreeQueue[Int] = lock_free_queue_new(3)
  assert_true(lock_free_queue_enqueue(q, 1))
  assert_eq(lock_free_queue_dequeue(q), Some(1))
  assert_true(lock_free_queue_enqueue(q, 2))
  assert_true(lock_free_queue_enqueue(q, 3))
  assert_eq(lock_free_queue_dequeue(q), Some(2))
  assert_true(lock_free_queue_enqueue(q, 4))
  assert_true(lock_free_queue_enqueue(q, 5))
  assert_true(lock_free_queue_is_full(q))
  assert_false(lock_free_queue_enqueue(q, 6))
  assert_eq(lock_free_queue_dequeue(q), Some(3))
  assert_eq(lock_free_queue_dequeue(q), Some(4))
  assert_eq(lock_free_queue_dequeue(q), Some(5))
  assert_true(lock_free_queue_is_empty(q))
}

///|
test "lock_free_queue: wraparound stress (recycled nodes)" {
  // Capacity 2 but we process 100 elements through the queue, exercising
  // node recycling / free-list reuse heavily.
  let q : LockFreeQueue[Int] = lock_free_queue_new(2)
  for i = 0; i < 100; i = i + 1 {
    assert_true(lock_free_queue_enqueue(q, i))
    assert_eq(lock_free_queue_dequeue(q), Some(i))
  }
  assert_true(lock_free_queue_is_empty(q))
  assert_eq(lock_free_queue_size(q), 0)
}

///|
test "lock_free_queue: drain and refill" {
  let q : LockFreeQueue[Int] = lock_free_queue_new(5)
  // Fill.
  for i = 0; i < 5; i = i + 1 {
    assert_true(lock_free_queue_enqueue(q, i))
  }
  assert_true(lock_free_queue_is_full(q))
  // Drain.
  for i = 0; i < 5; i = i + 1 {
    assert_eq(lock_free_queue_dequeue(q), Some(i))
  }
  assert_true(lock_free_queue_is_empty(q))
  // Refill — free list must have been fully restored.
  for i = 0; i < 5; i = i + 1 {
    assert_true(lock_free_queue_enqueue(q, i + 100))
  }
  assert_true(lock_free_queue_is_full(q))
  for i = 0; i < 5; i = i + 1 {
    assert_eq(lock_free_queue_dequeue(q), Some(i + 100))
  }
  assert_true(lock_free_queue_is_empty(q))
}

// ---------------------------------------------------------------------------
// Tests: edge cases (capacity 0 and 1)
// ---------------------------------------------------------------------------

///|
test "lock_free_queue: capacity 0 holds nothing" {
  let q : LockFreeQueue[Int] = lock_free_queue_new(0)
  assert_eq(lock_free_queue_capacity(q), 0)
  assert_true(lock_free_queue_is_empty(q))
  assert_true(lock_free_queue_is_full(q))
  assert_false(lock_free_queue_enqueue(q, 1))
  assert_eq(lock_free_queue_dequeue(q), None)
  assert_eq(lock_free_queue_size(q), 0)
}

///|
test "lock_free_queue: capacity 1 ping-pong" {
  let q : LockFreeQueue[Int] = lock_free_queue_new(1)
  assert_eq(lock_free_queue_capacity(q), 1)
  assert_true(lock_free_queue_is_empty(q))
  assert_false(lock_free_queue_is_full(q))
  // Enqueue one — now full.
  assert_true(lock_free_queue_enqueue(q, 42))
  assert_true(lock_free_queue_is_full(q))
  assert_false(lock_free_queue_is_empty(q))
  // Cannot enqueue while full.
  assert_false(lock_free_queue_enqueue(q, 99))
  // Dequeue — now empty again.
  assert_eq(lock_free_queue_dequeue(q), Some(42))
  assert_true(lock_free_queue_is_empty(q))
  assert_false(lock_free_queue_is_full(q))
  // Can enqueue again (node was recycled).
  assert_true(lock_free_queue_enqueue(q, 77))
  assert_eq(lock_free_queue_dequeue(q), Some(77))
  assert_true(lock_free_queue_is_empty(q))
}

///|
test "lock_free_queue: negative capacity clamped to 0" {
  let q : LockFreeQueue[Int] = lock_free_queue_new(-5)
  assert_eq(lock_free_queue_capacity(q), 0)
  assert_true(lock_free_queue_is_full(q))
  assert_false(lock_free_queue_enqueue(q, 1))
}

// ---------------------------------------------------------------------------
// Tests: generic element types
// ---------------------------------------------------------------------------

///|
test "lock_free_queue: string elements" {
  let q : LockFreeQueue[String] = lock_free_queue_new(3)
  assert_true(lock_free_queue_enqueue(q, "alpha"))
  assert_true(lock_free_queue_enqueue(q, "beta"))
  assert_true(lock_free_queue_enqueue(q, "gamma"))
  assert_eq(lock_free_queue_dequeue(q), Some("alpha"))
  assert_eq(lock_free_queue_dequeue(q), Some("beta"))
  assert_eq(lock_free_queue_dequeue(q), Some("gamma"))
}

///|
test "lock_free_queue: tuple elements" {
  let q : LockFreeQueue[(Int, String)] = lock_free_queue_new(2)
  assert_true(lock_free_queue_enqueue(q, (1, "one")))
  assert_true(lock_free_queue_enqueue(q, (2, "two")))
  assert_eq(lock_free_queue_dequeue(q), Some((1, "one")))
  assert_eq(lock_free_queue_dequeue(q), Some((2, "two")))
}

///|
test "lock_free_queue: boolean elements" {
  let q : LockFreeQueue[Bool] = lock_free_queue_new(3)
  assert_true(lock_free_queue_enqueue(q, true))
  assert_true(lock_free_queue_enqueue(q, false))
  assert_true(lock_free_queue_enqueue(q, true))
  assert_eq(lock_free_queue_dequeue(q), Some(true))
  assert_eq(lock_free_queue_dequeue(q), Some(false))
  assert_eq(lock_free_queue_dequeue(q), Some(true))
}

// ---------------------------------------------------------------------------
// Tests: CAS operation counting
// ---------------------------------------------------------------------------

///|
test "lock_free_queue: cas count matches algorithm" {
  let q : LockFreeQueue[Int] = lock_free_queue_new(3)
  // Fresh queue: no CAS yet.
  assert_eq(lock_free_queue_cas_count(q), 0)
  // Each enqueue = 2 CAS (link + tail-advance).
  ignore(lock_free_queue_enqueue(q, 1))
  assert_eq(lock_free_queue_cas_count(q), 2)
  ignore(lock_free_queue_enqueue(q, 2))
  assert_eq(lock_free_queue_cas_count(q), 4)
  // Each dequeue = 1 CAS (head-swing).
  ignore(lock_free_queue_dequeue(q))
  assert_eq(lock_free_queue_cas_count(q), 5)
  ignore(lock_free_queue_dequeue(q))
  assert_eq(lock_free_queue_cas_count(q), 6)
  // Failed dequeue (empty) = 0 CAS.
  ignore(lock_free_queue_dequeue(q))
  assert_eq(lock_free_queue_cas_count(q), 6)
  // Failed enqueue (full) = 0 CAS.
  ignore(lock_free_queue_enqueue(q, 10))
  ignore(lock_free_queue_enqueue(q, 11))
  ignore(lock_free_queue_enqueue(q, 12))
  assert_eq(lock_free_queue_cas_count(q), 12) // 6 + 3 enqueues * 2
  assert_false(lock_free_queue_enqueue(q, 99)) // full
  assert_eq(lock_free_queue_cas_count(q), 12) // no change
}

// ---------------------------------------------------------------------------
// Tests: size consistency
// ---------------------------------------------------------------------------

///|
test "lock_free_queue: size tracks count through mixed operations" {
  let q : LockFreeQueue[Int] = lock_free_queue_new(10)
  let mut expected = 0
  for round = 0; round < 5; round = round + 1 {
    // Enqueue 3.
    for i = 0; i < 3; i = i + 1 {
      assert_true(lock_free_queue_enqueue(q, round * 10 + i))
      expected = expected + 1
      assert_eq(lock_free_queue_size(q), expected)
    }
    // Dequeue 2.
    for j = 0; j < 2; j = j + 1 {
      ignore(lock_free_queue_dequeue(q))
      expected = expected - 1
      assert_eq(lock_free_queue_size(q), expected)
    }
  }
  // After 5 rounds: +15 -10 = 5 elements remain.
  assert_eq(lock_free_queue_size(q), 5)
  // Remaining elements in FIFO order: 31, 32, 40, 41, 42.
  // (Each round enqueues 3 and dequeues 2, so the 3rd element of rounds
  // 3-4 survives along with the 2nd and 3rd of round 3.)
  assert_eq(lock_free_queue_dequeue(q), Some(31))
  assert_eq(lock_free_queue_dequeue(q), Some(32))
  assert_eq(lock_free_queue_dequeue(q), Some(40))
  assert_eq(lock_free_queue_dequeue(q), Some(41))
  assert_eq(lock_free_queue_dequeue(q), Some(42))
  assert_true(lock_free_queue_is_empty(q))
}

// ---------------------------------------------------------------------------
// Tests: large-scale correctness
// ---------------------------------------------------------------------------

///|
test "lock_free_queue: large batch FIFO correctness" {
  let n = 500
  let q : LockFreeQueue[Int] = lock_free_queue_new(n)
  // Enqueue all.
  for i = 0; i < n; i = i + 1 {
    assert_true(lock_free_queue_enqueue(q, i))
  }
  assert_true(lock_free_queue_is_full(q))
  // Dequeue all and verify order.
  for i = 0; i < n; i = i + 1 {
    assert_eq(lock_free_queue_dequeue(q), Some(i))
  }
  assert_true(lock_free_queue_is_empty(q))
  // CAS count: n enqueues * 2 + n dequeues * 1 = 3n.
  assert_eq(lock_free_queue_cas_count(q), n * 3)
}

///|
test "lock_free_queue: bounded producer-consumer simulation" {
  // Simulate a producer-consumer pipeline with a small buffer:
  // produce 200 items, consuming along the way, never exceeding capacity.
  let cap = 8
  let q : LockFreeQueue[Int] = lock_free_queue_new(cap)
  let mut produced = 0
  let mut consumed = 0
  for i = 0; i < 200; i = i + 1 {
    // Produce (if room).
    if lock_free_queue_enqueue(q, i) {
      produced = produced + 1
    }
    // Consume every other iteration.
    if i % 2 == 1 {
      match lock_free_queue_dequeue(q) {
        Some(_) => consumed = consumed + 1
        None => ()
      }
    }
    // Size must never exceed capacity.
    assert_true(lock_free_queue_size(q) <= cap)
  }
  // Drain remaining.
  while !lock_free_queue_is_empty(q) {
    ignore(lock_free_queue_dequeue(q))
    consumed = consumed + 1
  }
  assert_eq(produced, consumed)
}
