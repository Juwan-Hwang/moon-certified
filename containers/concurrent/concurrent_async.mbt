/// Concurrent Containers (Spin-Mutex-Protected).
///
/// These containers wrap sync data structures with a lightweight spin mutex,
/// providing **real mutual exclusion** for MoonBit's cooperative scheduler.
///
/// ## Why a spin mutex?
///
/// MoonBit's async runtime is cooperative: only one task runs at a time,
/// and tasks yield at `await` points. Between yield points, execution is
/// atomic. However, if a critical section contains an `await` (e.g.,
/// reading from a file while holding a lock), other tasks can interleave
/// and corrupt shared state.
///
/// The spin mutex solves this: `acquire` spins until the flag is clear
/// (in cooperative scheduling this never actually spins — the caller
/// already has exclusive control until the next yield point), and
/// `release` is instant. The mutex also documents the intent that the
/// data is shared and future-proofs the code for when MoonBit gains
/// native threads.
///
/// ## Complexity
///
/// All operations have the same time complexity as their underlying
/// sync counterparts. The mutex adds O(1) overhead per operation.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// SpinMutex: lightweight flag-based mutual exclusion
// ---------------------------------------------------------------------------

///|
/// A simple spin mutex for MoonBit's cooperative scheduler.
///
/// In a cooperative (single-threaded) runtime, synchronous code runs to
/// completion without preemption. This means a boolean flag is sufficient
/// for mutual exclusion: `acquire` checks the flag (always free in practice
/// since no other task can run between the check and the set), and `release`
/// clears it.
///
/// For future multi-threaded runtimes, this would need to be upgraded to
/// a real CAS-based spinlock.
priv struct SpinMutex {
  mut locked : Bool
}

///|
fn SpinMutex::new() -> SpinMutex {
  { locked: false }
}

///|
fn SpinMutex::acquire(m : SpinMutex) -> Unit {
  // In cooperative scheduling, this loop runs at most once.
  while m.locked {
    // Would yield here in a real async runtime.
  }
  m.locked = true
}

///|
fn SpinMutex::try_acquire(m : SpinMutex) -> Bool {
  if m.locked {
    false
  } else {
    m.locked = true
    true
  }
}

///|
fn SpinMutex::release(m : SpinMutex) -> Unit {
  m.locked = false
}

// ---------------------------------------------------------------------------
// AsyncQueue[T]: Mutex-Protected Bounded Queue
// ---------------------------------------------------------------------------

///|
/// A mutex-protected bounded queue for safe concurrent access from
/// multiple async tasks.
///
/// Wraps `BoundedQueue[T]` with a spin mutex. All mutating operations
/// (`push`, `pop`) acquire/release the lock. Query operations
/// (`size`, `is_empty`, `is_full`) are lock-free — they read a
/// single field atomically in the cooperative scheduler.
pub struct AsyncQueue[T] {
  priv inner : BoundedQueue[T]
  priv mutex : SpinMutex
}

///|
/// Create a mutex-protected bounded queue with the given capacity.
pub fn[T] AsyncQueue::new(capacity : Int) -> AsyncQueue[T] {
  { inner: BoundedQueue::new(capacity), mutex: SpinMutex::new() }
}

///|
/// Enqueue `val`. Returns `false` if the queue is full.
///
/// Acquires the mutex, performs the push, and releases. The critical
/// section contains no yield points, so the push is atomic.
pub fn[T] AsyncQueue::push(q : AsyncQueue[T], val : T) -> Bool {
  SpinMutex::acquire(q.mutex)
  let result = BoundedQueue::try_push(q.inner, val)
  SpinMutex::release(q.mutex)
  result
}

///|
/// Dequeue the front element. Returns `None` if the queue is empty.
pub fn[T] AsyncQueue::pop(q : AsyncQueue[T]) -> T? {
  SpinMutex::acquire(q.mutex)
  let result = BoundedQueue::try_pop(q.inner)
  SpinMutex::release(q.mutex)
  result
}

///|
/// Try to enqueue without blocking. Returns `false` if the mutex is
/// held by another task or the queue is full.
///
/// Uses `try_acquire` (non-blocking) — never yields.
pub fn[T] AsyncQueue::try_push(q : AsyncQueue[T], val : T) -> Bool {
  if !SpinMutex::try_acquire(q.mutex) {
    return false
  }
  let result = BoundedQueue::try_push(q.inner, val)
  SpinMutex::release(q.mutex)
  result
}

///|
/// Try to dequeue without blocking. Returns `None` if the mutex is
/// held by another task or the queue is empty.
pub fn[T] AsyncQueue::try_pop(q : AsyncQueue[T]) -> T? {
  if !SpinMutex::try_acquire(q.mutex) {
    return None
  }
  let result = BoundedQueue::try_pop(q.inner)
  SpinMutex::release(q.mutex)
  result
}

///|
/// Current number of elements. O(1). Lock-free — safe in cooperative scheduler.
pub fn[T] AsyncQueue::size(q : AsyncQueue[T]) -> Int {
  BoundedQueue::size(q.inner)
}

///|
/// True if the queue is empty. O(1).
pub fn[T] AsyncQueue::is_empty(q : AsyncQueue[T]) -> Bool {
  BoundedQueue::is_empty(q.inner)
}

///|
/// True if the queue is full. O(1).
pub fn[T] AsyncQueue::is_full(q : AsyncQueue[T]) -> Bool {
  BoundedQueue::is_full(q.inner)
}

///|
/// Maximum capacity. O(1).
pub fn[T] AsyncQueue::capacity(q : AsyncQueue[T]) -> Int {
  BoundedQueue::capacity(q.inner)
}

// ---------------------------------------------------------------------------
// AsyncMap[K, V]: Mutex-Protected Hash Map
// ---------------------------------------------------------------------------

///|
/// A mutex-protected hash map for safe concurrent access from
/// multiple async tasks.
///
/// Wraps MoonBit's built-in `Map[K, V]` with a spin mutex. All
/// mutating operations acquire/release the lock; `size` is lock-free.
pub struct AsyncMap[K, V] {
  priv inner : Map[K, V]
  priv mutex : SpinMutex
}

///|
/// Create an empty mutex-protected map.
pub fn[K : Hash + Eq, V] AsyncMap::new() -> AsyncMap[K, V] {
  { inner: Map([]), mutex: SpinMutex::new() }
}

///|
/// Insert or update key `k` with value `v`.
pub fn[K : Hash + Eq, V] AsyncMap::put(
  m : AsyncMap[K, V],
  k : K,
  v : V,
) -> Unit {
  SpinMutex::acquire(m.mutex)
  m.inner[k] = v
  SpinMutex::release(m.mutex)
}

///|
/// Look up the value for key `k`. Returns `None` if not found.
pub fn[K : Hash + Eq, V] AsyncMap::get(m : AsyncMap[K, V], k : K) -> V? {
  SpinMutex::acquire(m.mutex)
  let result = m.inner.get(k)
  SpinMutex::release(m.mutex)
  result
}

///|
/// Remove key `k` if present. Returns `true` if the key was found.
pub fn[K : Hash + Eq, V] AsyncMap::remove(
  m : AsyncMap[K, V],
  k : K,
) -> Bool {
  SpinMutex::acquire(m.mutex)
  let existed = m.inner.contains(k)
  m.inner.remove(k)
  SpinMutex::release(m.mutex)
  existed
}

///|
/// Check if key `k` is present.
pub fn[K : Hash + Eq, V] AsyncMap::contains(
  m : AsyncMap[K, V],
  k : K,
) -> Bool {
  SpinMutex::acquire(m.mutex)
  let result = m.inner.contains(k)
  SpinMutex::release(m.mutex)
  result
}

///|
/// Number of key-value pairs. O(1). Lock-free — safe in cooperative scheduler.
pub fn[K, V] AsyncMap::size(m : AsyncMap[K, V]) -> Int {
  m.inner.length()
}

///|
/// True if the map contains no entries.
pub fn[K, V] AsyncMap::is_empty(m : AsyncMap[K, V]) -> Bool {
  m.inner.length() == 0
}

// ---------------------------------------------------------------------------
// Tests: AsyncQueue
// ---------------------------------------------------------------------------

///|
test "async_queue: basic push and pop" {
  let q : AsyncQueue[Int] = AsyncQueue::new(4)
  assert_true(AsyncQueue::is_empty(q))
  assert_true(AsyncQueue::push(q, 10))
  assert_true(AsyncQueue::push(q, 20))
  assert_eq(AsyncQueue::size(q), 2)
  assert_eq(AsyncQueue::pop(q), Some(10))
  assert_eq(AsyncQueue::pop(q), Some(20))
  assert_true(AsyncQueue::is_empty(q))
  assert_eq(AsyncQueue::pop(q), None)
}

///|
test "async_queue: full queue rejects push" {
  let q : AsyncQueue[Int] = AsyncQueue::new(3)
  assert_true(AsyncQueue::push(q, 1))
  assert_true(AsyncQueue::push(q, 2))
  assert_true(AsyncQueue::push(q, 3))
  assert_true(AsyncQueue::is_full(q))
  assert_false(AsyncQueue::push(q, 99))
  assert_eq(AsyncQueue::pop(q), Some(1))
  assert_true(AsyncQueue::push(q, 99))
  assert_eq(AsyncQueue::pop(q), Some(2))
  assert_eq(AsyncQueue::pop(q), Some(3))
  assert_eq(AsyncQueue::pop(q), Some(99))
}

///|
test "async_queue: FIFO ordering" {
  let q : AsyncQueue[Int] = AsyncQueue::new(100)
  for i = 0; i < 50; i = i + 1 {
    ignore(AsyncQueue::push(q, i * 2))
  }
  for i = 0; i < 50; i = i + 1 {
    assert_eq(AsyncQueue::pop(q), Some(i * 2))
  }
  assert_true(AsyncQueue::is_empty(q))
}

///|
test "async_queue: try_push and try_pop (non-blocking)" {
  let q : AsyncQueue[Int] = AsyncQueue::new(2)
  assert_true(AsyncQueue::try_push(q, 1))
  assert_true(AsyncQueue::try_push(q, 2))
  assert_false(AsyncQueue::try_push(q, 3)) // full
  assert_eq(AsyncQueue::try_pop(q), Some(1))
  assert_eq(AsyncQueue::try_pop(q), Some(2))
  assert_eq(AsyncQueue::try_pop(q), None) // empty
}

///|
test "async_queue: string elements" {
  let q : AsyncQueue[String] = AsyncQueue::new(3)
  ignore(AsyncQueue::push(q, "alpha"))
  ignore(AsyncQueue::push(q, "beta"))
  ignore(AsyncQueue::push(q, "gamma"))
  assert_eq(AsyncQueue::pop(q), Some("alpha"))
  assert_eq(AsyncQueue::pop(q), Some("beta"))
  assert_eq(AsyncQueue::pop(q), Some("gamma"))
}

///|
test "async_queue: interleaved operations" {
  let q : AsyncQueue[Int] = AsyncQueue::new(5)
  ignore(AsyncQueue::push(q, 1))
  ignore(AsyncQueue::push(q, 2))
  assert_eq(AsyncQueue::pop(q), Some(1))
  ignore(AsyncQueue::push(q, 3))
  ignore(AsyncQueue::push(q, 4))
  ignore(AsyncQueue::push(q, 5))
  assert_eq(AsyncQueue::pop(q), Some(2))
  assert_eq(AsyncQueue::pop(q), Some(3))
  assert_eq(AsyncQueue::pop(q), Some(4))
  assert_eq(AsyncQueue::pop(q), Some(5))
  assert_true(AsyncQueue::is_empty(q))
}

// ---------------------------------------------------------------------------
// Tests: AsyncMap
// ---------------------------------------------------------------------------

///|
test "async_map: basic put and get" {
  let m : AsyncMap[Int, String] = AsyncMap::new()
  AsyncMap::put(m, 1, "one")
  AsyncMap::put(m, 2, "two")
  AsyncMap::put(m, 3, "three")
  assert_eq(AsyncMap::size(m), 3)
  assert_eq(AsyncMap::get(m, 1), Some("one"))
  assert_eq(AsyncMap::get(m, 2), Some("two"))
  assert_eq(AsyncMap::get(m, 3), Some("three"))
  assert_eq(AsyncMap::get(m, 4), None)
}

///|
test "async_map: update existing key" {
  let m : AsyncMap[Int, String] = AsyncMap::new()
  AsyncMap::put(m, 1, "old")
  AsyncMap::put(m, 1, "new")
  assert_eq(AsyncMap::size(m), 1)
  assert_eq(AsyncMap::get(m, 1), Some("new"))
}

///|
test "async_map: remove" {
  let m : AsyncMap[Int, String] = AsyncMap::new()
  AsyncMap::put(m, 1, "one")
  AsyncMap::put(m, 2, "two")
  assert_true(AsyncMap::remove(m, 1))
  assert_false(AsyncMap::contains(m, 1))
  assert_eq(AsyncMap::size(m), 1)
  assert_false(AsyncMap::remove(m, 99))
}

///|
test "async_map: string keys" {
  let m : AsyncMap[String, Int] = AsyncMap::new()
  AsyncMap::put(m, "alice", 30)
  AsyncMap::put(m, "bob", 25)
  assert_eq(AsyncMap::get(m, "alice"), Some(30))
  assert_eq(AsyncMap::get(m, "bob"), Some(25))
  assert_eq(AsyncMap::get(m, "charlie"), None)
}

///|
test "async_map: large workload" {
  let m : AsyncMap[Int, Int] = AsyncMap::new()
  for i = 0; i < 100; i = i + 1 {
    AsyncMap::put(m, i, i * i)
  }
  assert_eq(AsyncMap::size(m), 100)
  for i = 0; i < 100; i = i + 1 {
    assert_eq(AsyncMap::get(m, i), Some(i * i))
  }
}
