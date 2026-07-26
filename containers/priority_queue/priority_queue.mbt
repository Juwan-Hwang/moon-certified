/// Generic priority queue with dynamic resizing.
///
/// A binary heap-based priority queue supporting any element type with a
/// user-supplied comparator. Unlike the fixed-capacity `Heap` in
/// `containers/binary_heap`, this module provides:
///
/// - **Dynamic resizing**: the backing array grows automatically; no capacity
///   limit is imposed on the caller.
/// - **Indexed access**: each pushed element receives a unique integer handle
///   that survives relocation, enabling O(log n) priority updates
///   (`change_priority`) and removal by handle (`remove_at`).
/// - **Build-from-slice**: construct a heap from an existing array in O(n)
///   via Floyd's heapify, instead of O(n log n) repeated pushes.
///
/// The comparator `compare(a, b)` returns:
/// - `< 0` when `a` has higher priority than `b` (min-heap: `a < b`)
/// - `0` when equal
/// - `> 0` when `a` has lower priority
///
/// **Complexity**:
/// - `push` — O(log n) amortised (O(n) when the backing array needs to grow)
/// - `pop` — O(log n)
/// - `peek` — O(1)
/// - `change_priority` — O(log n)
/// - `remove_at` — O(log n)
/// - `build` — O(n)
///
/// All fields are **package-private**; external callers interact exclusively
/// through methods, preventing invariant violations.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Internal types
// ---------------------------------------------------------------------------

///|
/// A single heap entry: the value plus its index in the backing array
/// (for reverse-lookup from the handle map).
struct PQEntry[T] {
  mut val : T
  mut heap_idx : Int // current position in the heap array
  entry_idx : Int // stable index into `entries` (for O(1) freeing in `pop`)
}

///|
/// Handle returned to the caller for each pushed element.
/// The handle is an index into `entries`; it never changes even when the
/// element moves within the heap.
pub struct PQHandle {
  priv entry_idx : Int
}

///|
/// The priority queue.
///
/// - `heap` is a dense array of `PQEntry` references in heap order.
/// - `entries` stores all entries (including freed slots marked by
///   `heap_idx = -1`).
/// - `compare` determines priority ordering.
/// - `free_list` recycles entry slots from removed elements.
pub struct PriorityQueue[T] {
  priv heap : Array[PQEntry[T]]
  priv entries : Array[PQEntry[T]]
  priv compare : (T, T) -> Int
  priv free_list : Array[Int]
}

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

///|
/// Create an empty priority queue.
///
/// `compare(a, b)` returns `< 0` if `a` has higher priority than `b`
/// (min-heap: `a < b`), `0` if equal, `> 0` otherwise.
pub fn[T] PriorityQueue::new(compare : (T, T) -> Int) -> PriorityQueue[T] {
  { heap: [], entries: [], compare, free_list: [] }
}

///|
/// Build a priority queue from an existing array in O(n) time.
///
/// Each element receives a handle. The input array is consumed (not modified).
pub fn[T] PriorityQueue::from_array(
  compare : (T, T) -> Int,
  arr : Array[T],
) -> PriorityQueue[T] {
  let pq : PriorityQueue[T] = { heap: [], entries: [], compare, free_list: [] }
  for i = 0; i < arr.length(); i = i + 1 {
    let entry : PQEntry[T] = { val: arr[i], heap_idx: i, entry_idx: i }
    pq.entries.push(entry)
    pq.heap.push(entry)
  }
  // Floyd heapify: sift down from the last non-leaf to the root.
  let n = pq.heap.length()
  let mut i = n / 2
  while i > 0 {
    i = i - 1
    pq.sift_down(i)
  }
  pq
}

// ---------------------------------------------------------------------------
// Core operations
// ---------------------------------------------------------------------------

///|
/// Number of elements in the queue. O(1).
pub fn[T] PriorityQueue::len(self : PriorityQueue[T]) -> Int {
  self.heap.length()
}

///|
/// `true` when the queue is empty. O(1).
pub fn[T] PriorityQueue::is_empty(self : PriorityQueue[T]) -> Bool {
  self.heap.length() == 0
}

///|
/// Peek at the highest-priority element without removing it.
/// Returns `None` when the queue is empty. O(1).
pub fn[T] PriorityQueue::peek(self : PriorityQueue[T]) -> T? {
  if self.heap.length() == 0 {
    None
  } else {
    Some(self.heap[0].val)
  }
}

///|
/// Push `val` onto the queue. Returns a handle for later priority updates.
/// O(log n) amortised.
pub fn[T] PriorityQueue::push(self : PriorityQueue[T], val : T) -> PQHandle {
  let entry_idx = if self.free_list.length() > 0 {
    let idx = self.free_list.pop().unwrap()
    self.entries[idx] = { val, heap_idx: self.heap.length(), entry_idx: idx }
    idx
  } else {
    let idx = self.entries.length()
    let entry : PQEntry[T] = {
      val,
      heap_idx: self.heap.length(),
      entry_idx: idx,
    }
    self.entries.push(entry)
    idx
  }
  self.heap.push(self.entries[entry_idx])
  self.sift_up(self.heap.length() - 1)
  { entry_idx, }
}

///|
/// Pop and return the highest-priority element.
/// Returns `None` when the queue is empty. O(log n).
pub fn[T] PriorityQueue::pop(self : PriorityQueue[T]) -> T? {
  let n = self.heap.length()
  if n == 0 {
    return None
  }
  let top = self.heap[0].val
  // Mark the entry as freed.
  let top_entry_idx = self.heap[0].entry_idx
  self.entries[top_entry_idx].heap_idx = -1
  self.free_list.push(top_entry_idx)
  // Move last element to root and sift down.
  let last = self.heap[n - 1]
  ignore(self.heap.pop())
  if self.heap.length() > 0 {
    self.heap[0] = last
    last.heap_idx = 0
    self.sift_down(0)
  }
  Some(top)
}

// ---------------------------------------------------------------------------
// Indexed operations
// ---------------------------------------------------------------------------

///|
/// Change the priority of the element identified by `handle` to `new_val`.
///
/// After updating the value, the element is sifted up or down as needed to
/// restore the heap invariant. This is the standard operation used in
/// Dijkstra's algorithm when a vertex's tentative distance is reduced.
///
/// Returns `Some(())` on success, `None` if the handle is stale (the element
/// was already popped or removed).
///
/// **Precondition**: `new_val` must have higher-or-equal priority than the
/// current value (i.e. `compare(new_val, old_val) <= 0` for a min-heap when
/// decreasing the key). If this is violated, the heap invariant may break.
/// For arbitrary updates, use `set_value` instead.
pub fn[T] PriorityQueue::change_priority(
  self : PriorityQueue[T],
  handle : PQHandle,
  new_val : T,
) -> Unit? {
  let idx = handle.entry_idx
  if idx < 0 || idx >= self.entries.length() {
    return None
  }
  let entry = self.entries[idx]
  if entry.heap_idx < 0 {
    return None // stale handle
  }
  // Update the value.
  entry.val = new_val
  // Try sifting up first (for decreased keys in a min-heap).
  self.sift_up(entry.heap_idx)
  // Then try sifting down (for increased keys in a min-heap).
  self.sift_down(entry.heap_idx)
  Some(())
}

///|
/// Set the value of the element identified by `handle` to `new_val`,
/// then restore the heap invariant. Works for both increases and decreases.
///
/// Returns `None` if the handle is stale.
pub fn[T] PriorityQueue::set_value(
  self : PriorityQueue[T],
  handle : PQHandle,
  new_val : T,
) -> Unit? {
  self.change_priority(handle, new_val)
}

///|
/// Remove the element identified by `handle` from the queue.
///
/// Returns `Some(val)` on success, `None` if the handle is stale.
/// O(log n).
pub fn[T] PriorityQueue::remove_at(
  self : PriorityQueue[T],
  handle : PQHandle,
) -> T? {
  let idx = handle.entry_idx
  if idx < 0 || idx >= self.entries.length() {
    return None
  }
  let entry = self.entries[idx]
  let h_idx = entry.heap_idx
  if h_idx < 0 {
    return None // stale
  }
  let val = entry.val
  let n = self.heap.length()
  // Move last element into the vacated slot.
  let last = self.heap[n - 1]
  ignore(self.heap.pop())
  // Mark the entry as freed.
  entry.heap_idx = -1
  self.free_list.push(idx)
  if h_idx < self.heap.length() {
    self.heap[h_idx] = last
    last.heap_idx = h_idx
    self.sift_up(h_idx)
    self.sift_down(h_idx)
  }
  Some(val)
}

///|
/// Get the current value of the element identified by `handle`.
/// Returns `None` if the handle is stale. O(1).
pub fn[T] PriorityQueue::get_value(
  self : PriorityQueue[T],
  handle : PQHandle,
) -> T? {
  let idx = handle.entry_idx
  if idx < 0 || idx >= self.entries.length() {
    return None
  }
  let entry = self.entries[idx]
  if entry.heap_idx < 0 {
    return None
  }
  Some(entry.val)
}

///|
/// Remove all elements. O(n).
pub fn[T] PriorityQueue::clear(self : PriorityQueue[T]) -> Unit {
  self.heap.clear()
  self.entries.clear()
  self.free_list.clear()
}

// ---------------------------------------------------------------------------
// Internal: sift up / sift down
// ---------------------------------------------------------------------------

///|
fn[T] PriorityQueue::sift_up(self : PriorityQueue[T], idx : Int) -> Unit {
  let mut i = idx
  while i > 0 {
    let parent = (i - 1) / 2
    if (self.compare)(self.heap[i].val, self.heap[parent].val) < 0 {
      // Swap heap entries and update their heap_idx.
      let tmp = self.heap[i]
      self.heap[i] = self.heap[parent]
      self.heap[parent] = tmp
      self.heap[i].heap_idx = i
      self.heap[parent].heap_idx = parent
      i = parent
    } else {
      break
    }
  }
}

///|
fn[T] PriorityQueue::sift_down(self : PriorityQueue[T], idx : Int) -> Unit {
  let mut i = idx
  let n = self.heap.length()
  while true {
    let left = 2 * i + 1
    let right = 2 * i + 2
    let mut best = i
    if left < n && (self.compare)(self.heap[left].val, self.heap[best].val) < 0 {
      best = left
    }
    if right < n &&
      (self.compare)(self.heap[right].val, self.heap[best].val) < 0 {
      best = right
    }
    if best == i {
      break
    }
    // Swap and update indices.
    let tmp = self.heap[i]
    self.heap[i] = self.heap[best]
    self.heap[best] = tmp
    self.heap[i].heap_idx = i
    self.heap[best].heap_idx = best
    i = best
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "PriorityQueue: min-heap basic push and pop" {
  let pq = PriorityQueue::new(fn(a : Int, b : Int) { a - b })
  assert_true(pq.is_empty())
  let _ = pq.push(5)
  let _ = pq.push(3)
  let _ = pq.push(7)
  let _ = pq.push(1)
  let _ = pq.push(9)
  assert_eq(pq.len(), 5)
  assert_eq(pq.peek(), Some(1))
  assert_eq(pq.pop(), Some(1))
  assert_eq(pq.pop(), Some(3))
  assert_eq(pq.pop(), Some(5))
  assert_eq(pq.pop(), Some(7))
  assert_eq(pq.pop(), Some(9))
  assert_true(pq.is_empty())
  assert_true(pq.pop() is None)
}

///|
test "PriorityQueue: max-heap via reversed comparator" {
  let pq = PriorityQueue::new(fn(a : Int, b : Int) { b - a })
  let _ = pq.push(5)
  let _ = pq.push(3)
  let _ = pq.push(8)
  let _ = pq.push(1)
  assert_eq(pq.peek(), Some(8))
  assert_eq(pq.pop(), Some(8))
  assert_eq(pq.pop(), Some(5))
  assert_eq(pq.pop(), Some(3))
  assert_eq(pq.pop(), Some(1))
}

///|
test "PriorityQueue: build from array (O(n) heapify)" {
  let arr = [9, 3, 7, 1, 5, 8, 2, 6, 4, 0]
  let pq = PriorityQueue::from_array(fn(a : Int, b : Int) { a - b }, arr)
  assert_eq(pq.len(), 10)
  for i = 0; i < 10; i = i + 1 {
    assert_eq(pq.pop(), Some(i))
  }
}

///|
test "PriorityQueue: change_priority (Dijkstra-style decrease-key)" {
  let pq = PriorityQueue::new(fn(a : (Int, Int), b : (Int, Int)) { a.0 - b.0 })
  let _ = pq.push((10, 1))
  let _ = pq.push((5, 2))
  let h3 = pq.push((20, 3))
  // Decrease vertex 3's distance from 20 to 3.
  let _ = pq.change_priority(h3, (3, 3))
  assert_eq(pq.pop().unwrap().0, 3) // (3, 3)
  assert_eq(pq.pop().unwrap().0, 5) // (5, 2)
  assert_eq(pq.pop().unwrap().0, 10) // (10, 1)
}

///|
test "PriorityQueue: change_priority increase (sift down)" {
  let pq = PriorityQueue::new(fn(a : Int, b : Int) { a - b })
  let h0 = pq.push(1)
  let _ = pq.push(5)
  let _ = pq.push(10)
  // Increase the root's value from 1 to 100.
  let _ = pq.change_priority(h0, 100)
  assert_eq(pq.peek(), Some(5))
  assert_eq(pq.pop(), Some(5))
  assert_eq(pq.pop(), Some(10))
  assert_eq(pq.pop(), Some(100))
}

///|
test "PriorityQueue: remove by handle" {
  let pq = PriorityQueue::new(fn(a : Int, b : Int) { a - b })
  let _ = pq.push(5)
  let h2 = pq.push(3)
  let _ = pq.push(8)
  let _ = pq.push(1)
  let _ = pq.push(9)
  let removed = pq.remove_at(h2).unwrap()
  assert_eq(removed, 3)
  assert_eq(pq.len(), 4)
  // Remaining should come out sorted.
  assert_eq(pq.pop(), Some(1))
  assert_eq(pq.pop(), Some(5))
  assert_eq(pq.pop(), Some(8))
  assert_eq(pq.pop(), Some(9))
}

///|
test "PriorityQueue: stale handle returns None" {
  let pq = PriorityQueue::new(fn(a : Int, b : Int) { a - b })
  let h = pq.push(5)
  let _ = pq.pop()
  assert_true(pq.change_priority(h, 1) is None)
  assert_true(pq.remove_at(h) is None)
  assert_true(pq.get_value(h) is None)
}

///|
test "PriorityQueue: get_value" {
  let pq = PriorityQueue::new(fn(a : Int, b : Int) { a - b })
  let h = pq.push(42)
  assert_eq(pq.get_value(h), Some(42))
  let _ = pq.pop()
  assert_true(pq.get_value(h) is None)
}

///|
test "PriorityQueue: large stress test (1000 elements)" {
  let pq = PriorityQueue::new(fn(a : Int, b : Int) { a - b })
  for i = 0; i < 1000; i = i + 1 {
    let _ = pq.push(999 - i)
  }
  for i = 0; i < 1000; i = i + 1 {
    assert_eq(pq.pop(), Some(i))
  }
  assert_true(pq.is_empty())
}

///|
test "PriorityQueue: interleave push and pop" {
  let pq = PriorityQueue::new(fn(a : Int, b : Int) { a - b })
  let _ = pq.push(5)
  let _ = pq.push(3)
  let _ = pq.push(8)
  let _ = pq.push(1)
  assert_eq(pq.pop(), Some(1))
  let _ = pq.push(2)
  assert_eq(pq.pop(), Some(2))
  assert_eq(pq.pop(), Some(3))
  let _ = pq.push(0)
  assert_eq(pq.pop(), Some(0))
  assert_eq(pq.pop(), Some(5))
  assert_eq(pq.pop(), Some(8))
  assert_true(pq.is_empty())
}

///|
test "PriorityQueue: handle survives relocation" {
  let pq = PriorityQueue::new(fn(a : Int, b : Int) { a - b })
  let h = pq.push(100) // lowest priority (max value in min-heap)
  let _ = pq.push(10)
  let _ = pq.push(20)
  let _ = pq.push(5)
  // Pop several elements; the handle should still be valid.
  let _ = pq.pop() // 5
  let _ = pq.pop() // 10
  // Change the priority of the remaining element.
  let _ = pq.change_priority(h, 1)
  assert_eq(pq.peek(), Some(1))
  let _ = pq.pop() // 1
  assert_eq(pq.pop(), Some(20))
}

///|
test "PriorityQueue: slot recycling" {
  let pq = PriorityQueue::new(fn(a : Int, b : Int) { a - b })
  let handles : Array[PQHandle] = []
  for i = 0; i < 10; i = i + 1 {
    handles.push(pq.push(i))
  }
  // Remove half.
  for i = 0; i < 10; i = i + 2 {
    let _ = pq.remove_at(handles[i])
  }
  // Push more; slots should be recycled.
  for i = 0; i < 5; i = i + 1 {
    let _ = pq.push(100 + i)
  }
  // All should come out sorted.
  let mut prev = -1
  while !pq.is_empty() {
    let v = pq.pop().unwrap()
    assert_true(v >= prev)
    prev = v
  }
}

///|
test "PriorityQueue: clear" {
  let pq = PriorityQueue::new(fn(a : Int, b : Int) { a - b })
  let _ = pq.push(1)
  let _ = pq.push(2)
  pq.clear()
  assert_true(pq.is_empty())
  assert_eq(pq.len(), 0)
}

///|
test "PriorityQueue: duplicate elements" {
  let pq = PriorityQueue::new(fn(a : Int, b : Int) { a - b })
  let _ = pq.push(5)
  let _ = pq.push(5)
  let _ = pq.push(5)
  let _ = pq.push(3)
  let _ = pq.push(3)
  assert_eq(pq.pop(), Some(3))
  assert_eq(pq.pop(), Some(3))
  assert_eq(pq.pop(), Some(5))
  assert_eq(pq.pop(), Some(5))
  assert_eq(pq.pop(), Some(5))
}

///|
test "PriorityQueue: string elements" {
  let pq = PriorityQueue::new(fn(a : String, b : String) {
    if a < b {
      -1
    } else if a > b {
      1
    } else {
      0
    }
  })
  let _ = pq.push("banana")
  let _ = pq.push("apple")
  let _ = pq.push("cherry")
  assert_eq(pq.pop(), Some("apple"))
  assert_eq(pq.pop(), Some("banana"))
  assert_eq(pq.pop(), Some("cherry"))
}
