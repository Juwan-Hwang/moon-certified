/// Work-Stealing Deque — Chase-Lev Algorithm (Single-Threaded Simulation).
///
/// **WARNING: NOT thread-safe.** MoonBit does not provide CAS
/// (compare-and-swap) or other atomic primitives. The original Chase-Lev
/// algorithm relies on CAS for safe concurrent stealing; without it, this
/// implementation is single-threaded only. Concurrent access from multiple
/// threads will cause data races and corruption.
///
/// A work-stealing deque allows a worker thread to push/pop from one end
/// (LIFO) while other threads steal from the other end (FIFO). This is
/// the core data structure for task-parallel runtime schedulers
/// (Cilk, Intel TBB, Rust's Rayon, Java ForkJoinPool).
///
/// ## Algorithm
///
/// The Chase-Lev deque uses a circular array with two indices:
/// - `bottom`: points past the last pushed item (owner pushes/pops here).
/// - `top`: points to the first stealable item (thieves steal here).
///
/// The original algorithm has the owner do push/pop without
/// synchronization while thieves use CAS. Because MoonBit lacks CAS, this
/// implementation omits all synchronization and is correct only in a
/// single-threaded context, where all operations are trivially safe.
///
/// ## Complexity
/// - push/pop/steal: O(1) amortized.
/// - Space: O(capacity).
///
/// Reference: D. Chase, Y. Lev, "Dynamic Circular Work-Stealing Deque"
/// (SPAA 2005).
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

///|
/// A bounded work-stealing deque (Chase-Lev).
pub struct WorkStealingDeque[T] {
  priv mut buffer : FixedArray[T?]
  priv mut bottom : Int
  priv mut top : Int
  priv mut mask : Int
}

///|
/// Create a work-stealing deque with the given capacity.
/// Capacity is rounded up to the next power of 2.
pub fn[T] ws_deque_new(capacity : Int) -> WorkStealingDeque[T] {
  let mut cap = if capacity < 2 { 2 } else { capacity }
  let mut p = 1
  while p < cap {
    p = p * 2
  }
  cap = p
  { buffer: FixedArray::make(cap, None), bottom: 0, top: 0, mask: cap - 1, }
}

///|
/// Push an item onto the bottom (owner's end). O(1) amortized.
///
/// If the buffer is full, grows it to double capacity.
pub fn[T] ws_deque_push(q : WorkStealingDeque[T], item : T) -> Unit {
  let mut b = q.bottom
  let t = q.top
  // Check if buffer is full (bottom - top == capacity).
  if b - t >= q.buffer.length() {
    ws_deque_grow(q)
    b = q.bottom // re-read after growth relocated elements
  }
  q.buffer[b & q.mask] = Some(item)
  q.bottom = b + 1
}

///|
/// Grow the internal buffer to double capacity.
fn[T] ws_deque_grow(q : WorkStealingDeque[T]) -> Unit {
  let old_cap = q.buffer.length()
  let new_cap = old_cap * 2
  let new_buf = FixedArray::make(new_cap, None)
  // Copy existing elements in order from top to bottom.
  let t = q.top
  let size = q.bottom - t
  for i = 0; i < size; i = i + 1 {
    new_buf[i] = q.buffer[(t + i) & q.mask]
  }
  q.buffer = new_buf
  q.mask = new_cap - 1
  q.top = 0
  q.bottom = size
}

///|
/// Pop an item from the bottom (owner's end, LIFO). O(1).
/// Returns None if the deque is empty.
pub fn[T] ws_deque_pop(q : WorkStealingDeque[T]) -> T? {
  let b = q.bottom - 1
  q.bottom = b
  let t = q.top
  if t <= b {
    let item = q.buffer[b & q.mask]
    if t == b {
      // Last element — must update top to prevent race with steal.
      q.top = t + 1
      q.bottom = t + 1
    }
    item
  } else {
    // Empty.
    q.bottom = t
    None
  }
}

///|
/// Steal an item from the top (thief's end, FIFO). O(1).
/// Returns None if the deque is empty.
pub fn[T] ws_deque_steal(q : WorkStealingDeque[T]) -> T? {
  let t = q.top
  let b = q.bottom
  if t >= b {
    return None
  }
  let item = q.buffer[t & q.mask]
  q.top = t + 1
  item
}

///|
/// Number of items. O(1).
pub fn[T] ws_deque_size(q : WorkStealingDeque[T]) -> Int {
  let b = q.bottom
  let t = q.top
  if b > t {
    b - t
  } else {
    0
  }
}

///|
/// True if the deque is empty. O(1).
pub fn[T] ws_deque_is_empty(q : WorkStealingDeque[T]) -> Bool {
  q.top >= q.bottom
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "ws_deque: push and pop (LIFO)" {
  let q : WorkStealingDeque[Int] = ws_deque_new(8)
  ws_deque_push(q, 1)
  ws_deque_push(q, 2)
  ws_deque_push(q, 3)
  assert_eq(ws_deque_pop(q), Some(3))
  assert_eq(ws_deque_pop(q), Some(2))
  assert_eq(ws_deque_pop(q), Some(1))
  assert_eq(ws_deque_pop(q), None)
}

///|
test "ws_deque: steal from top (FIFO)" {
  let q : WorkStealingDeque[Int] = ws_deque_new(8)
  ws_deque_push(q, 1)
  ws_deque_push(q, 2)
  ws_deque_push(q, 3)
  assert_eq(ws_deque_steal(q), Some(1))
  assert_eq(ws_deque_steal(q), Some(2))
  assert_eq(ws_deque_steal(q), Some(3))
  assert_eq(ws_deque_steal(q), None)
}

///|
test "ws_deque: interleave push, pop, steal" {
  let q : WorkStealingDeque[Int] = ws_deque_new(8)
  ws_deque_push(q, 10)
  ws_deque_push(q, 20)
  ws_deque_push(q, 30)
  // Steal from top -> 10
  assert_eq(ws_deque_steal(q), Some(10))
  // Pop from bottom -> 30
  assert_eq(ws_deque_pop(q), Some(30))
  // Push more
  ws_deque_push(q, 40)
  // Steal -> 20
  assert_eq(ws_deque_steal(q), Some(20))
  // Pop -> 40
  assert_eq(ws_deque_pop(q), Some(40))
  assert_true(ws_deque_is_empty(q))
}

///|
test "ws_deque: wrap-around" {
  let q : WorkStealingDeque[Int] = ws_deque_new(4)
  for round = 0; round < 3; round = round + 1 {
    for i = 0; i < 3; i = i + 1 {
      ws_deque_push(q, round * 10 + i)
    }
    for i = 0; i < 3; i = i + 1 {
      assert_eq(ws_deque_pop(q), Some(round * 10 + (2 - i)))
    }
  }
  assert_true(ws_deque_is_empty(q))
}

///|
test "ws_deque: size tracking" {
  let q : WorkStealingDeque[Int] = ws_deque_new(8)
  assert_eq(ws_deque_size(q), 0)
  ws_deque_push(q, 1)
  ws_deque_push(q, 2)
  assert_eq(ws_deque_size(q), 2)
  ignore(ws_deque_steal(q))
  assert_eq(ws_deque_size(q), 1)
  ignore(ws_deque_pop(q))
  assert_eq(ws_deque_size(q), 0)
}

///|
test "ws_deque: generic" {
  let q : WorkStealingDeque[String] = ws_deque_new(4)
  ws_deque_push(q, "a")
  ws_deque_push(q, "b")
  assert_eq(ws_deque_pop(q), Some("b"))
  assert_eq(ws_deque_steal(q), Some("a"))
}

///|
test "ws_deque: grow on overflow" {
  let q : WorkStealingDeque[Int] = ws_deque_new(4)
  // Push more items than initial capacity — should grow, not lose data.
  for i = 0; i < 20; i = i + 1 {
    ws_deque_push(q, i)
  }
  assert_eq(ws_deque_size(q), 20)
  // Pop should return in LIFO order.
  for i = 19; i >= 0; i = i - 1 {
    assert_eq(ws_deque_pop(q), Some(i))
  }
  assert_true(ws_deque_is_empty(q))
}

///|
test "ws_deque: grow with steal + pop mix" {
  let q : WorkStealingDeque[Int] = ws_deque_new(4)
  ws_deque_push(q, 1)
  ws_deque_push(q, 2)
  ws_deque_push(q, 3)
  ws_deque_push(q, 4)
  // Steal one, then push more to trigger growth.
  assert_eq(ws_deque_steal(q), Some(1))
  ws_deque_push(q, 5)
  ws_deque_push(q, 6)
  assert_eq(ws_deque_size(q), 5)
  // Verify all items present.
  assert_eq(ws_deque_steal(q), Some(2))
  assert_eq(ws_deque_pop(q), Some(6))
  assert_eq(ws_deque_pop(q), Some(5))
  assert_eq(ws_deque_pop(q), Some(4))
  assert_eq(ws_deque_pop(q), Some(3))
}
