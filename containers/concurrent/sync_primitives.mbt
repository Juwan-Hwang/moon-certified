/// Synchronization Primitives — RwLock, Semaphore, ConditionVariable.
///
/// **⚠️ WARNING: NOT thread-safe.** MoonBit currently targets WebAssembly
/// and JavaScript, which are single-threaded. These primitives provide the
/// **API surface** and **state tracking** of standard synchronization
/// primitives, but they cannot perform real blocking or atomic operations.
///
/// ## Purpose
///
/// 1. **API compatibility**: Code written against these interfaces will
///    compile and run correctly in single-threaded MoonBit, and can be
///    upgraded to real primitives when multi-threading support arrives.
///
/// 2. **State tracking**: The primitives track reader/writer counts,
///    permit counts, and signal state — useful for testing, debugging,
///    and asserting correctness of concurrent algorithms.
///
/// 3. **Future-proofing**: When MoonBit gains native threads, these
///    implementations can be replaced with CAS-based or OS-level
///    primitives without breaking the public API.
///
/// ## Implemented primitives
///
/// - **`RwLock[T]`**: Reader-Writer lock. Multiple concurrent readers,
///   exclusive writer. `read` returns a snapshot; `with_write` mutates
///   under exclusive access.
///
/// - **`Semaphore`**: Counting semaphore with a fixed number of permits.
///   `try_acquire` / `release` manage the permit count.
///
/// - **`ConditionVariable`**: Signal/broadcast mechanism for coordination.
///   Records pending signals; `wait` is non-blocking (returns immediately).
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// RwLock[T]: Reader-Writer Lock
// ---------------------------------------------------------------------------

///|
/// A reader-writer lock protecting a value of type `T`.
///
/// Multiple readers can hold the lock simultaneously (`read`), but only
/// one writer can hold it exclusively (`with_write`). Writers block
/// readers and vice versa.
///
/// In single-threaded MoonBit, `read` and `with_write` always succeed
/// immediately — there is no contention. The lock tracks the reader
/// count and writer state for debugging and future threading support.
///
/// ## Pattern
///
/// ```moonbit nocheck
/// let lock = RwLock::new(42)
/// // Read
/// let v = RwLock::read(lock)
/// // Write
/// RwLock::with_write(lock, fn(v) { v + 1 })
/// ```
///
/// ## Invariants (tracked but not enforced in single-threaded mode)
///
/// - `writer` is `true` ⟹ `readers == 0`
/// - `readers > 0` ⟹ `writer == false`
/// - `writer` is `true` ⟹ no other writer
pub struct RwLock[T] {
  priv mut value : T
  priv mut readers : Int
  priv mut writer : Bool
}

///|
/// Create a new `RwLock` protecting `value`.
pub fn[T] RwLock::new(value : T) -> RwLock[T] {
  { value, readers: 0, writer: false, }
}

///|
/// Acquire a read lock and return a copy of the protected value.
///
/// In single-threaded MoonBit, this always succeeds immediately and
/// increments the reader count. The caller should call `read_unlock`
/// when done, or use `with_read` for automatic cleanup.
pub fn[T] RwLock::read(lock : RwLock[T]) -> T {
  lock.readers = lock.readers + 1
  lock.value
}

///|
/// Release a read lock.
pub fn[T] RwLock::read_unlock(lock : RwLock[T]) -> Unit {
  if lock.readers > 0 {
    lock.readers = lock.readers - 1
  }
}

///|
/// Acquire a read lock, execute `f` with the value, then release.
/// This is the recommended pattern for short read operations.
pub fn[T] RwLock::with_read(lock : RwLock[T], f : (T) -> Unit) -> Unit {
  let v = RwLock::read(lock)
  f(v)
  RwLock::read_unlock(lock)
}

///|
/// Try to acquire a write lock. Returns `false` if the lock is held
/// (by a reader or another writer). In single-threaded MoonBit, this
/// always returns `true` unless the lock is already held.
pub fn[T] RwLock::try_write(lock : RwLock[T]) -> Bool {
  if lock.writer || lock.readers > 0 {
    false
  } else {
    lock.writer = true
    true
  }
}

///|
/// Release a write lock.
pub fn[T] RwLock::write_unlock(lock : RwLock[T]) -> Unit {
  lock.writer = false
}

///|
/// Acquire a write lock, execute `f` to transform the protected value,
/// then release the lock. This is the recommended pattern for write
/// operations.
pub fn[T] RwLock::with_write(lock : RwLock[T], f : (T) -> T) -> Unit {
  // In single-threaded mode, we can always acquire.
  // For correctness tracking, mark as held.
  let was_writer = lock.writer
  lock.writer = true
  lock.value = f(lock.value)
  lock.writer = was_writer
}

///|
/// Directly set the protected value (acquires write lock internally).
pub fn[T] RwLock::set(lock : RwLock[T], value : T) -> Unit {
  RwLock::with_write(lock, fn(_) { value })
}

///|
/// Get the current reader count (for debugging/testing).
pub fn[T] RwLock::reader_count(lock : RwLock[T]) -> Int {
  lock.readers
}

///|
/// Check if a writer currently holds the lock.
pub fn[T] RwLock::is_write_locked(lock : RwLock[T]) -> Bool {
  lock.writer
}

// ---------------------------------------------------------------------------
// Semaphore: Counting Semaphore
// ---------------------------------------------------------------------------

///|
/// A counting semaphore with a fixed maximum number of permits.
///
/// Permits are acquired with `try_acquire` (non-blocking) and released
/// with `release`. The semaphore tracks the available permit count.
///
/// In single-threaded MoonBit, `try_acquire` returns `false` when no
/// permits are available — there is no blocking `acquire` since nothing
/// can release a permit while the current task is running.
///
/// ## Use cases
///
/// - Rate limiting (e.g., limit concurrent "logical" operations)
/// - Resource pooling (e.g., connection pool size)
/// - Backpressure signaling
pub struct Semaphore {
  priv mut permits : Int
  priv max_permits : Int
}

///|
/// Create a semaphore with `count` initial (and maximum) permits.
/// If `count` is negative, it is clamped to 0.
pub fn Semaphore::new(count : Int) -> Semaphore {
  let c = if count < 0 { 0 } else { count }
  { permits: c, max_permits: c, }
}

///|
/// Try to acquire one permit. Returns `false` if no permits are available.
pub fn Semaphore::try_acquire(sem : Semaphore) -> Bool {
  if sem.permits > 0 {
    sem.permits = sem.permits - 1
    true
  } else {
    false
  }
}

///|
/// Try to acquire `n` permits. Returns `false` if fewer than `n` permits
/// are available. If `n` is 0, always returns `true`.
pub fn Semaphore::try_acquire_n(sem : Semaphore, n : Int) -> Bool {
  if n <= 0 {
    return true
  }
  if sem.permits >= n {
    sem.permits = sem.permits - n
    true
  } else {
    false
  }
}

///|
/// Release one permit. Always increments the available count.
///
/// Note: in standard semaphore semantics (e.g., Java's `j.u.c.Semaphore`),
/// `release` can push the permit count above the initial maximum. This
/// allows dynamic permit growth (e.g., producer adding items to a pool).
/// The caller is responsible for balanced acquire/release.
pub fn Semaphore::release(sem : Semaphore) -> Unit {
  sem.permits = sem.permits + 1
}

///|
/// Release `n` permits. Always increments the available count by `n`.
pub fn Semaphore::release_n(sem : Semaphore, n : Int) -> Unit {
  if n <= 0 {
    return
  }
  sem.permits = sem.permits + n
}

///|
/// Number of currently available permits.
pub fn Semaphore::available(sem : Semaphore) -> Int {
  sem.permits
}

///|
/// Maximum number of permits this semaphore was created with.
pub fn Semaphore::max_permits(sem : Semaphore) -> Int {
  sem.max_permits
}

// ---------------------------------------------------------------------------
// ConditionVariable: Signal/Broadcast Coordination
// ---------------------------------------------------------------------------

///|
/// A condition variable for coordinating logical tasks.
///
/// In a multi-threaded environment, a condition variable allows threads
/// to wait until a condition becomes true, with `signal` waking one
/// waiter and `broadcast` waking all waiters.
///
/// In single-threaded MoonBit, `wait` cannot block (nothing can signal
/// while the current task is running). Instead, this implementation
/// **records signals** so that code can check whether a signal was
/// received since the last check. This is useful for:
///
/// - Testing concurrent algorithm logic
/// - Implementing event-driven patterns in async code
/// - Future upgrading to real blocking when threads are available
///
/// ## Pattern
///
/// ```moonbit nocheck
/// let cv = ConditionVariable::new()
/// // ... some condition becomes true ...
/// ConditionVariable::signal(cv)
/// // Check if signaled
/// if ConditionVariable::consume_signal(cv) {
///   // handle signal
/// }
/// ```
pub struct ConditionVariable {
  priv mut pending_signals : Int
  priv mut total_signals : Int
  priv mut total_broadcasts : Int
}

///|
/// Create a new condition variable with no pending signals.
pub fn ConditionVariable::new() -> ConditionVariable {
  { pending_signals: 0, total_signals: 0, total_broadcasts: 0, }
}

///|
/// Signal one waiter. If no one is waiting, the signal is recorded
/// as pending. A subsequent `consume_signal` will return `true`.
pub fn ConditionVariable::signal(cv : ConditionVariable) -> Unit {
  cv.pending_signals = cv.pending_signals + 1
  cv.total_signals = cv.total_signals + 1
}

///|
/// Broadcast to all waiters. Equivalent to signaling `count` times.
/// Records a broadcast event for testing/debugging.
pub fn ConditionVariable::broadcast(cv : ConditionVariable) -> Unit {
  cv.pending_signals = cv.pending_signals + 1
  cv.total_signals = cv.total_signals + 1
  cv.total_broadcasts = cv.total_broadcasts + 1
}

///|
/// Consume one pending signal. Returns `true` if a signal was pending
/// (and decrements the pending count), `false` otherwise.
///
/// This is the single-threaded equivalent of `wait` — instead of
/// blocking, it checks whether a signal has been received since the
/// last `consume_signal` call.
pub fn ConditionVariable::consume_signal(cv : ConditionVariable) -> Bool {
  if cv.pending_signals > 0 {
    cv.pending_signals = cv.pending_signals - 1
    true
  } else {
    false
  }
}

///|
/// Number of unconsumed signals.
pub fn ConditionVariable::pending(cv : ConditionVariable) -> Int {
  cv.pending_signals
}

///|
/// Total number of signals ever sent (including broadcasts).
pub fn ConditionVariable::total_signals_sent(cv : ConditionVariable) -> Int {
  cv.total_signals
}

///|
/// Total number of broadcasts ever sent.
pub fn ConditionVariable::total_broadcasts_sent(cv : ConditionVariable) -> Int {
  cv.total_broadcasts
}

///|
/// Reset all counters to zero.
pub fn ConditionVariable::reset(cv : ConditionVariable) -> Unit {
  cv.pending_signals = 0
  cv.total_signals = 0
  cv.total_broadcasts = 0
}

// ---------------------------------------------------------------------------
// Tests: RwLock
// ---------------------------------------------------------------------------

///|
test "rwlock: basic read" {
  let lock : RwLock[Int] = RwLock::new(42)
  assert_eq(RwLock::read(lock), 42)
  assert_eq(RwLock::reader_count(lock), 1)
  RwLock::read_unlock(lock)
  assert_eq(RwLock::reader_count(lock), 0)
}

///|
test "rwlock: with_read auto-unlock" {
  let lock : RwLock[String] = RwLock::new("hello")
  let mut captured = ""
  RwLock::with_read(lock, fn(v) { captured = v })
  assert_eq(captured, "hello")
  assert_eq(RwLock::reader_count(lock), 0)
}

///|
test "rwlock: with_write mutation" {
  let lock : RwLock[Int] = RwLock::new(10)
  RwLock::with_write(lock, fn(v) { v + 5 })
  assert_eq(RwLock::read(lock), 15)
  RwLock::read_unlock(lock)
}

///|
test "rwlock: set value" {
  let lock : RwLock[Int] = RwLock::new(0)
  RwLock::set(lock, 99)
  assert_eq(RwLock::read(lock), 99)
  RwLock::read_unlock(lock)
}

///|
test "rwlock: try_write succeeds when unlocked" {
  let lock : RwLock[Int] = RwLock::new(1)
  assert_true(RwLock::try_write(lock))
  assert_true(RwLock::is_write_locked(lock))
  RwLock::write_unlock(lock)
  assert_false(RwLock::is_write_locked(lock))
}

///|
test "rwlock: try_write fails when readers present" {
  let lock : RwLock[Int] = RwLock::new(1)
  ignore(RwLock::read(lock))
  assert_false(RwLock::try_write(lock))
  RwLock::read_unlock(lock)
  assert_true(RwLock::try_write(lock))
  RwLock::write_unlock(lock)
}

///|
test "rwlock: multiple readers" {
  let lock : RwLock[Int] = RwLock::new(7)
  ignore(RwLock::read(lock))
  ignore(RwLock::read(lock))
  ignore(RwLock::read(lock))
  assert_eq(RwLock::reader_count(lock), 3)
  RwLock::read_unlock(lock)
  RwLock::read_unlock(lock)
  RwLock::read_unlock(lock)
  assert_eq(RwLock::reader_count(lock), 0)
}

///|
test "rwlock: generic type" {
  let lock : RwLock[Array[Int]] = RwLock::new([1, 2, 3])
  RwLock::with_write(lock, fn(arr) {
    arr.push(4)
    arr
  })
  let v = RwLock::read(lock)
  assert_eq(v.length(), 4)
  RwLock::read_unlock(lock)
}

// ---------------------------------------------------------------------------
// Tests: Semaphore
// ---------------------------------------------------------------------------

///|
test "semaphore: initial state" {
  let sem = Semaphore::new(3)
  assert_eq(Semaphore::available(sem), 3)
  assert_eq(Semaphore::max_permits(sem), 3)
}

///|
test "semaphore: acquire and release" {
  let sem = Semaphore::new(2)
  assert_true(Semaphore::try_acquire(sem))
  assert_eq(Semaphore::available(sem), 1)
  assert_true(Semaphore::try_acquire(sem))
  assert_eq(Semaphore::available(sem), 0)
  assert_false(Semaphore::try_acquire(sem))
  Semaphore::release(sem)
  assert_eq(Semaphore::available(sem), 1)
}

///|
test "semaphore: try_acquire_n" {
  let sem = Semaphore::new(5)
  assert_true(Semaphore::try_acquire_n(sem, 3))
  assert_eq(Semaphore::available(sem), 2)
  assert_false(Semaphore::try_acquire_n(sem, 5))
  assert_eq(Semaphore::available(sem), 2)
  assert_true(Semaphore::try_acquire_n(sem, 2))
  assert_eq(Semaphore::available(sem), 0)
}

///|
test "semaphore: release_n exceeds initial max" {
  let sem = Semaphore::new(3)
  ignore(Semaphore::try_acquire_n(sem, 3))
  assert_eq(Semaphore::available(sem), 0)
  // Release can push above initial max (standard Java Semaphore behavior)
  Semaphore::release_n(sem, 5)
  assert_eq(Semaphore::available(sem), 5)
}

///|
test "semaphore: zero permits" {
  let sem = Semaphore::new(0)
  assert_eq(Semaphore::available(sem), 0)
  assert_false(Semaphore::try_acquire(sem))
  Semaphore::release(sem)
  assert_eq(Semaphore::available(sem), 1)
  assert_true(Semaphore::try_acquire(sem))
}

///|
test "semaphore: negative count clamped" {
  let sem = Semaphore::new(-5)
  assert_eq(Semaphore::available(sem), 0)
  assert_eq(Semaphore::max_permits(sem), 0)
}

///|
test "semaphore: try_acquire_n with zero" {
  let sem = Semaphore::new(1)
  assert_true(Semaphore::try_acquire_n(sem, 0))
  assert_eq(Semaphore::available(sem), 1)
}

// ---------------------------------------------------------------------------
// Tests: ConditionVariable
// ---------------------------------------------------------------------------

///|
test "condvar: signal and consume" {
  let cv = ConditionVariable::new()
  assert_false(ConditionVariable::consume_signal(cv))
  ConditionVariable::signal(cv)
  assert_true(ConditionVariable::consume_signal(cv))
  assert_false(ConditionVariable::consume_signal(cv))
}

///|
test "condvar: multiple signals" {
  let cv = ConditionVariable::new()
  ConditionVariable::signal(cv)
  ConditionVariable::signal(cv)
  ConditionVariable::signal(cv)
  assert_eq(ConditionVariable::pending(cv), 3)
  assert_true(ConditionVariable::consume_signal(cv))
  assert_true(ConditionVariable::consume_signal(cv))
  assert_eq(ConditionVariable::pending(cv), 1)
  assert_true(ConditionVariable::consume_signal(cv))
  assert_eq(ConditionVariable::pending(cv), 0)
}

///|
test "condvar: broadcast" {
  let cv = ConditionVariable::new()
  ConditionVariable::broadcast(cv)
  assert_eq(ConditionVariable::pending(cv), 1)
  assert_eq(ConditionVariable::total_broadcasts_sent(cv), 1)
  assert_eq(ConditionVariable::total_signals_sent(cv), 1)
  assert_true(ConditionVariable::consume_signal(cv))
}

///|
test "condvar: total counters" {
  let cv = ConditionVariable::new()
  ConditionVariable::signal(cv)
  ConditionVariable::signal(cv)
  ConditionVariable::broadcast(cv)
  ConditionVariable::signal(cv)
  assert_eq(ConditionVariable::total_signals_sent(cv), 4)
  assert_eq(ConditionVariable::total_broadcasts_sent(cv), 1)
  assert_eq(ConditionVariable::pending(cv), 4)
}

///|
test "condvar: reset" {
  let cv = ConditionVariable::new()
  ConditionVariable::signal(cv)
  ConditionVariable::broadcast(cv)
  ConditionVariable::reset(cv)
  assert_eq(ConditionVariable::pending(cv), 0)
  assert_eq(ConditionVariable::total_signals_sent(cv), 0)
  assert_eq(ConditionVariable::total_broadcasts_sent(cv), 0)
}

///|
test "condvar: no signal initially" {
  let cv = ConditionVariable::new()
  assert_eq(ConditionVariable::pending(cv), 0)
  assert_eq(ConditionVariable::total_signals_sent(cv), 0)
  assert_eq(ConditionVariable::total_broadcasts_sent(cv), 0)
  assert_false(ConditionVariable::consume_signal(cv))
}
