/// Generic Double-Ended Queue (Deque) — Ring Buffer Implementation.
///
/// A deque (double-ended queue) allows insertion and removal at both
/// ends in O(1) amortized time. This implementation uses a growable
/// circular buffer, similar to Rust's `VecDeque` and Java's
/// `ArrayDeque`.
///
/// ## Complexity
/// - push_front / push_back: O(1) amortized.
/// - pop_front / pop_back: O(1).
/// - get / set: O(1).
/// - len / is_empty: O(1).
/// - Space: O(capacity).
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

///|
/// Initial capacity (must be a power of 2 for efficient masking).
const INITIAL_CAPACITY : Int = 8

///|
/// A growable double-ended queue backed by a ring buffer.
pub struct Deque[T] {
  priv mut buf : FixedArray[T?]
  priv mut head : Int // Index of the front element.
  priv mut tail : Int // Index one past the back element.
  priv mut len : Int
  priv mut mask : Int // capacity - 1, for fast modulo.
}

///|
/// Create an empty deque.
pub fn[T] deque_new() -> Deque[T] {
  {
    buf: FixedArray::make(INITIAL_CAPACITY, None),
    head: 0,
    tail: 0,
    len: 0,
    mask: INITIAL_CAPACITY - 1,
  }
}

///|
/// Create an empty deque with at least the given capacity.
pub fn[T] deque_with_capacity(capacity : Int) -> Deque[T] {
  let mut cap = if capacity < 2 { 2 } else { capacity }
  let mut p = 1
  while p < cap {
    p = p * 2
  }
  cap = p
  { buf: FixedArray::make(cap, None), head: 0, tail: 0, len: 0, mask: cap - 1 }
}

///|
/// Number of elements in the deque. O(1).
pub fn[T] deque_len(d : Deque[T]) -> Int {
  d.len
}

///|
/// True if the deque is empty. O(1).
pub fn[T] deque_is_empty(d : Deque[T]) -> Bool {
  d.len == 0
}

///|
/// Push an element to the back of the deque. O(1) amortized.
pub fn[T] deque_push_back(d : Deque[T], item : T) -> Unit {
  if d.len == d.buf.length() {
    deque_grow(d)
  }
  d.buf[d.tail] = Some(item)
  d.tail = (d.tail + 1) & d.mask
  d.len = d.len + 1
}

///|
/// Push an element to the front of the deque. O(1) amortized.
pub fn[T] deque_push_front(d : Deque[T], item : T) -> Unit {
  if d.len == d.buf.length() {
    deque_grow(d)
  }
  d.head = (d.head - 1 + d.buf.length()) & d.mask
  d.buf[d.head] = Some(item)
  d.len = d.len + 1
}

///|
/// Pop an element from the back of the deque. O(1).
/// Returns None if the deque is empty.
pub fn[T] deque_pop_back(d : Deque[T]) -> T? {
  if d.len == 0 {
    return None
  }
  d.tail = (d.tail - 1 + d.buf.length()) & d.mask
  let item = d.buf[d.tail]
  d.buf[d.tail] = None
  d.len = d.len - 1
  item
}

///|
/// Pop an element from the front of the deque. O(1).
/// Returns None if the deque is empty.
pub fn[T] deque_pop_front(d : Deque[T]) -> T? {
  if d.len == 0 {
    return None
  }
  let item = d.buf[d.head]
  d.buf[d.head] = None
  d.head = (d.head + 1) & d.mask
  d.len = d.len - 1
  item
}

///|
/// Peek at the front element without removing it. O(1).
pub fn[T] deque_front(d : Deque[T]) -> T? {
  if d.len == 0 {
    None
  } else {
    d.buf[d.head]
  }
}

///|
/// Peek at the back element without removing it. O(1).
pub fn[T] deque_back(d : Deque[T]) -> T? {
  if d.len == 0 {
    None
  } else {
    let idx = (d.tail - 1 + d.buf.length()) & d.mask
    d.buf[idx]
  }
}

///|
/// Get the element at logical index `i` (0-based from front). O(1).
pub fn[T] deque_get(d : Deque[T], i : Int) -> T? {
  if i < 0 || i >= d.len {
    return None
  }
  d.buf[(d.head + i) & d.mask]
}

///|
/// Set the element at logical index `i` (0-based from front). O(1).
/// Returns the old value, or None if the index is out of bounds.
pub fn[T] deque_set(d : Deque[T], i : Int, item : T) -> T? {
  if i < 0 || i >= d.len {
    return None
  }
  let idx = (d.head + i) & d.mask
  let old = d.buf[idx]
  d.buf[idx] = Some(item)
  old
}

///|
/// Clear all elements from the deque. O(n).
pub fn[T] deque_clear(d : Deque[T]) -> Unit {
  for i = 0; i < d.buf.length(); i = i + 1 {
    d.buf[i] = None
  }
  d.head = 0
  d.tail = 0
  d.len = 0
}

///|
/// Convert the deque to an array (front to back order). O(n).
pub fn[T] deque_to_array(d : Deque[T]) -> Array[T] {
  let result : Array[T] = []
  for i = 0; i < d.len; i = i + 1 {
    match d.buf[(d.head + i) & d.mask] {
      Some(v) => result.push(v)
      None => ()
    }
  }
  result
}

///|
/// Grow the internal buffer to double capacity.
fn[T] deque_grow(d : Deque[T]) -> Unit {
  let old_cap = d.buf.length()
  let new_cap = old_cap * 2
  let new_buf = FixedArray::make(new_cap, None)
  for i = 0; i < d.len; i = i + 1 {
    new_buf[i] = d.buf[(d.head + i) & d.mask]
  }
  d.buf = new_buf
  d.head = 0
  d.tail = d.len
  d.mask = new_cap - 1
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "deque: push and pop back" {
  let d : Deque[Int] = deque_new()
  deque_push_back(d, 1)
  deque_push_back(d, 2)
  deque_push_back(d, 3)
  assert_eq(deque_len(d), 3)
  assert_eq(deque_pop_back(d), Some(3))
  assert_eq(deque_pop_back(d), Some(2))
  assert_eq(deque_pop_back(d), Some(1))
  assert_eq(deque_pop_back(d), None)
  assert_true(deque_is_empty(d))
}

///|
test "deque: push and pop front" {
  let d : Deque[Int] = deque_new()
  deque_push_front(d, 1)
  deque_push_front(d, 2)
  deque_push_front(d, 3)
  assert_eq(deque_pop_front(d), Some(3))
  assert_eq(deque_pop_front(d), Some(2))
  assert_eq(deque_pop_front(d), Some(1))
  assert_eq(deque_pop_front(d), None)
}

///|
test "deque: mixed push front and back" {
  let d : Deque[Int] = deque_new()
  deque_push_back(d, 2)
  deque_push_front(d, 1)
  deque_push_back(d, 3)
  deque_push_front(d, 0)
  // Deque should be: [0, 1, 2, 3]
  assert_eq(deque_pop_front(d), Some(0))
  assert_eq(deque_pop_front(d), Some(1))
  assert_eq(deque_pop_front(d), Some(2))
  assert_eq(deque_pop_front(d), Some(3))
}

///|
test "deque: peek front and back" {
  let d : Deque[Int] = deque_new()
  deque_push_back(d, 10)
  deque_push_back(d, 20)
  assert_eq(deque_front(d), Some(10))
  assert_eq(deque_back(d), Some(20))
  ignore(deque_pop_front(d))
  assert_eq(deque_front(d), Some(20))
}

///|
test "deque: get and set" {
  let d : Deque[Int] = deque_new()
  deque_push_back(d, 10)
  deque_push_back(d, 20)
  deque_push_back(d, 30)
  assert_eq(deque_get(d, 0), Some(10))
  assert_eq(deque_get(d, 1), Some(20))
  assert_eq(deque_get(d, 2), Some(30))
  assert_eq(deque_get(d, 3), None)
  ignore(deque_set(d, 1, 200))
  assert_eq(deque_get(d, 1), Some(200))
}

///|
test "deque: grow on overflow" {
  let d : Deque[Int] = deque_new()
  for i = 0; i < 100; i = i + 1 {
    deque_push_back(d, i)
  }
  assert_eq(deque_len(d), 100)
  for i = 0; i < 100; i = i + 1 {
    assert_eq(deque_pop_front(d), Some(i))
  }
}

///|
test "deque: wrap around" {
  let d : Deque[Int] = deque_new()
  for round = 0; round < 5; round = round + 1 {
    deque_push_back(d, round)
    assert_eq(deque_pop_front(d), Some(round))
  }
  assert_true(deque_is_empty(d))
}

///|
test "deque: generic strings" {
  let d : Deque[String] = deque_new()
  deque_push_back(d, "hello")
  deque_push_back(d, "world")
  assert_eq(deque_pop_back(d), Some("world"))
  assert_eq(deque_pop_back(d), Some("hello"))
}

///|
test "deque: to array" {
  let d : Deque[Int] = deque_new()
  deque_push_back(d, 3)
  deque_push_front(d, 1)
  deque_push_back(d, 4)
  deque_push_front(d, 0)
  deque_push_back(d, 5)
  let arr = deque_to_array(d)
  assert_eq(arr, [0, 1, 3, 4, 5])
}

///|
test "deque: clear" {
  let d : Deque[Int] = deque_new()
  deque_push_back(d, 1)
  deque_push_back(d, 2)
  deque_clear(d)
  assert_true(deque_is_empty(d))
  assert_eq(deque_pop_front(d), None)
}

///|
test "deque: with capacity" {
  let d : Deque[Int] = deque_with_capacity(100)
  for i = 0; i < 50; i = i + 1 {
    deque_push_back(d, i)
  }
  assert_eq(deque_len(d), 50)
  for i = 0; i < 50; i = i + 1 {
    assert_eq(deque_pop_front(d), Some(i))
  }
}
