/// Binary heap operations on a FixedArray[Int].
///
/// The heap uses 0-indexed binary tree:
///   parent(i) = (i-1)/2, left(i) = 2*i+1, right(i) = 2*i+2.
///
/// Min-heap by default. heap_sort uses max-heap internally.
/// All public functions validate inputs and return safe values on error:
/// - heap_push returns -1 if the array is full (size >= capacity)
/// - heap_pop returns (None, size) if the heap is empty, (Some(val), new_size) on success
/// - build_heap and heap_sort handle empty/single-element arrays
///
/// Not formally verified (while loops with mutable state).
/// Correctness ensured by comprehensive tests including permutation checks.

/// ---------------------------------------------------------------------------
/// Encapsulated heap API
///
/// `Heap` bundles the backing `FixedArray[Int]` together with the current
/// `size`, so callers no longer have to track the size manually.  Every
/// method delegates to the low-level free functions below, which remain
/// available for backward compatibility.
/// ---------------------------------------------------------------------------

/// A min-heap backed by a fixed-capacity array.
///
/// - `data` holds the elements in heap order (0-indexed binary tree).
/// - `size` is the number of live elements; slots `>= size` are unused.
///
/// The struct is **package-private** (not `pub`): external callers interact
/// exclusively through methods (`heap_push`, `heap_pop`, `heap_peek`, etc.),
/// preventing direct mutation of the backing array that could break the heap
/// invariant. The low-level free functions (`heap_push`, `heap_pop`,
/// `build_heap`, `heap_sort`) remain public for callers that need direct
/// `FixedArray[Int]` manipulation.
struct Heap {
  data : FixedArray[Int]
  mut size : Int
}

/// Create an empty `Heap` with the given fixed `capacity`.
/// All slots are zero-initialised; `size` starts at 0.
pub fn heap_new(capacity : Int) -> Heap {
  { data: FixedArray::make(capacity, 0), size: 0 }
}

/// Push `val` onto the heap.
/// Returns `Some(())` on success, `None` if the backing array is full.
pub fn Heap::heap_push(self : Heap, val : Int) -> Unit? {
  match heap_push(self.data, self.size, val) {
    Some(new_size) => {
      self.size = new_size
      Some(())
    }
    None => None
  }
}

/// Pop and return the minimum element.
/// Returns `Some(min)` on success, `None` when the heap is empty.
pub fn Heap::heap_pop(self : Heap) -> Int? {
  let (result, new_size) = heap_pop(self.data, self.size)
  match result {
    Some(_) => {
      self.size = new_size
      result
    }
    None => None
  }
}

/// Heapify the backing array in place.
/// `size` is set to the heapified length reported by `build_heap`.
pub fn Heap::heap_build(self : Heap) -> Unit {
  self.size = build_heap(self.data)
}

/// Number of elements currently in the heap.
pub fn Heap::heap_size(self : Heap) -> Int {
  self.size
}

/// Maximum number of elements the heap can hold.
pub fn Heap::heap_capacity(self : Heap) -> Int {
  self.data.length()
}

/// `true` when the heap holds no elements.
pub fn Heap::heap_is_empty(self : Heap) -> Bool {
  self.size == 0
}

/// Peek at the minimum element without removing it.
/// Returns `None` when the heap is empty.
pub fn Heap::heap_peek(self : Heap) -> Int? {
  if self.size == 0 {
    None
  } else {
    Some(self.data[0])
  }
}

/// ---------------------------------------------------------------------------
/// Generic heap API with dynamic resizing and decrease_key
///
/// `HeapG[T]` is a generic binary heap supporting any comparable type. Unlike
/// the fixed-capacity `Heap` above, `HeapG` automatically grows its backing
/// array when full, and provides `decrease_key` for use in Dijkstra-style
/// algorithms where a vertex's priority must be lowered.
/// ---------------------------------------------------------------------------

/// A generic binary heap with dynamic resizing.
///
/// - `data` holds elements in heap order (0-indexed binary tree).
/// - `size` is the number of live elements.
/// - `compare(a, b)` returns negative if `a` should be above `b` in the heap
///   (e.g. `< 0` for min-heap, `> 0` for max-heap).
///
/// The struct is **package-private**: external callers interact through
/// methods only, preventing direct mutation that could break the heap
/// invariant.
pub struct HeapG[T] {
  priv data : Array[T]
  priv mut size : Int
  priv compare : (T, T) -> Int
}

/// Create an empty `HeapG[T]` with the given comparator.
///
/// `compare(a, b)` should return `< 0` if `a` has higher priority than `b`
/// (min-heap: `a < b`), `0` if equal, `> 0` otherwise.
///
/// The backing `Array` grows automatically as elements are pushed.
pub fn[T] HeapG::new(compare : (T, T) -> Int) -> HeapG[T] {
  { data: [], size: 0, compare }
}

/// Number of elements in the heap. O(1).
pub fn[T] HeapG::len(self : HeapG[T]) -> Int {
  self.size
}

/// `true` when the heap is empty. O(1).
pub fn[T] HeapG::is_empty(self : HeapG[T]) -> Bool {
  self.size == 0
}

/// Peek at the top element without removing it.
/// Returns `None` when the heap is empty. O(1).
pub fn[T] HeapG::peek(self : HeapG[T]) -> T? {
  if self.size == 0 {
    None
  } else {
    Some(self.data[0])
  }
}

/// Push `val` onto the heap. The backing `Array` grows automatically.
/// Always succeeds (unlike the fixed-capacity `Heap`). O(log n) amortised.
pub fn[T] HeapG::push(self : HeapG[T], val : T) -> Unit {
  self.data.push(val)
  self.size = self.size + 1
  self.sift_up(self.size - 1)
}

/// Pop and return the top element.
/// Returns `None` when the heap is empty. O(log n).
pub fn[T] HeapG::pop(self : HeapG[T]) -> T? {
  if self.size == 0 {
    return None
  }
  let top = self.data[0]
  // Move last element to root, then shrink and sift down.
  let last = self.data[self.size - 1]
  ignore(self.data.pop())
  self.size = self.size - 1
  if self.size > 0 {
    self.data[0] = last
    self.sift_down(0)
  }
  Some(top)
}

/// Decrease the key of the element at index `idx` to `new_val`.
///
/// After setting `data[idx] = new_val`, sifts up to restore the heap
/// invariant. This is the standard operation used in Dijkstra's algorithm
/// when a vertex's tentative distance is reduced.
///
/// Returns `None` if `idx` is out of bounds. Otherwise returns `Some(())`.
///
/// **Precondition**: `new_val` must have higher or equal priority than the
/// current value at `idx` (i.e., `compare(new_val, old_val) <= 0` for a
/// min-heap). If this is violated, the heap invariant will be broken.
pub fn[T] HeapG::decrease_key(self : HeapG[T], idx : Int, new_val : T) -> Unit? {
  if idx < 0 || idx >= self.size {
    return None
  }
  self.data[idx] = new_val
  self.sift_up(idx)
  Some(())
}

/// Remove and return the element at index `idx`.
///
/// Moves the last element into position `idx`, then restores the heap
/// invariant by sifting in whichever direction is needed.
/// Returns `None` if `idx` is out of bounds. O(log n).
pub fn[T] HeapG::remove(self : HeapG[T], idx : Int) -> T? {
  if idx < 0 || idx >= self.size {
    return None
  }
  let val = self.data[idx]
  // Move last element to position idx.
  let last = self.data[self.size - 1]
  ignore(self.data.pop())
  self.size = self.size - 1
  if idx < self.size {
    self.data[idx] = last
    // Need to sift both up and down to restore invariant.
    self.sift_up(idx)
    self.sift_down(idx)
  }
  Some(val)
}

/// Sift up from position `idx` to restore the heap invariant.
/// Assumes all positions except `idx` satisfy the invariant.
fn[T] HeapG::sift_up(self : HeapG[T], idx : Int) -> Unit {
  let mut i = idx
  while i > 0 {
    let parent = (i - 1) / 2
    if (self.compare)(self.data[i], self.data[parent]) < 0 {
      let tmp = self.data[i]
      self.data[i] = self.data[parent]
      self.data[parent] = tmp
      i = parent
    } else {
      break
    }
  }
}

/// Sift down from position `idx` to restore the heap invariant.
/// Assumes all positions except `idx` satisfy the invariant.
fn[T] HeapG::sift_down(self : HeapG[T], idx : Int) -> Unit {
  let mut i = idx
  while true {
    let left = 2 * i + 1
    let right = 2 * i + 2
    let mut best = i
    if left < self.size && (self.compare)(self.data[left], self.data[best]) < 0 {
      best = left
    }
    if right < self.size && (self.compare)(self.data[right], self.data[best]) < 0 {
      best = right
    }
    if best == i {
      break
    }
    let tmp = self.data[i]
    self.data[i] = self.data[best]
    self.data[best] = tmp
    i = best
  }
}

/// Swap two elements in an array.
fn swap(xs : FixedArray[Int], i : Int, j : Int) -> Unit {
  let tmp = xs[i]
  xs[i] = xs[j]
  xs[j] = tmp
}

/// Sift down with a custom comparison function.
/// `should_swap(a, b)` returns true if a should be above b in the heap.
/// This unifies min-heap (a < b) and max-heap (a > b) into one function.
fn sift_down_cmp(
  xs : FixedArray[Int],
  size : Int,
  idx : Int,
  should_swap : (Int, Int) -> Bool,
) -> Unit {
  if idx < 0 || size <= 0 || idx >= size {
    return
  }
  let mut i = idx
  while true {
    let left = 2 * i + 1
    let right = 2 * i + 2
    let mut target = i
    if left < size && should_swap(xs[left], xs[target]) {
      target = left
    }
    if right < size && should_swap(xs[right], xs[target]) {
      target = right
    }
    if target == i {
      break
    }
    swap(xs, i, target)
    i = target
  }
}

/// Sift up with a custom comparison function.
fn sift_up_cmp(
  xs : FixedArray[Int],
  size : Int,
  idx : Int,
  should_swap : (Int, Int) -> Bool,
) -> Unit {
  if idx < 0 || idx >= size {
    return
  }
  let mut i = idx
  while i > 0 {
    let parent = (i - 1) / 2
    if should_swap(xs[i], xs[parent]) {
      swap(xs, i, parent)
      i = parent
    } else {
      break
    }
  }
}

/// Build a min-heap from an arbitrary array (in-place).
/// Returns the heap size (= array length).
pub fn build_heap(xs : FixedArray[Int]) -> Int {
  let n = xs.length()
  if n <= 1 {
    return n
  }
  let mut i = n / 2 - 1
  while i >= 0 {
    sift_down_cmp(xs, n, i, fn(a, b) { a < b })
    i = i - 1
  }
  n
}

/// Push a value onto the min-heap. Returns Some(new_size) on success, None if full.
pub fn heap_push(
  xs : FixedArray[Int],
  size : Int,
  val : Int,
) -> Int? {
  let capacity = xs.length()
  if size < 0 || size >= capacity {
    return None
  }
  xs[size] = val
  sift_up_cmp(xs, size + 1, size, fn(a, b) { a < b })
  Some(size + 1)
}

/// Pop the minimum element from the heap.
/// Returns (Some(min_val), new_size) on success, (None, size) if heap is empty.
/// The new_size is always returned so callers don't need to manually track it.
pub fn heap_pop(
  xs : FixedArray[Int],
  size : Int,
) -> (Int?, Int) {
  if size <= 0 {
    return (None, 0)
  }
  let min_val = xs[0]
  xs[0] = xs[size - 1]
  sift_down_cmp(xs, size - 1, 0, fn(a, b) { a < b })
  (Some(min_val), size - 1)
}

/// Heap sort: sorts the array in ascending order using a max-heap.
/// Builds a max-heap, then repeatedly swaps the root (max) to the end
/// and restores the heap property on the reduced prefix.
/// No reversal pass needed (unlike a min-heap approach).
pub fn heap_sort(xs : FixedArray[Int]) -> Unit {
  let n = xs.length()
  if n <= 1 {
    return
  }
  // Build max-heap: sift each non-leaf node down using > comparison
  let mut i = n / 2 - 1
  while i >= 0 {
    sift_down_cmp(xs, n, i, fn(a, b) { a > b })
    i = i - 1
  }
  // Extract max to end, shrink heap
  let mut end = n - 1
  while end > 0 {
    swap(xs, 0, end)
    sift_down_cmp(xs, end, 0, fn(a, b) { a > b })
    end = end - 1
  }
}

test "build_heap: basic" {
  let xs = FixedArray::makei(6, fn(i) { 6 - i })  // [6,5,4,3,2,1]
  let size = build_heap(xs)
  assert_eq(size, 6)
  assert_eq(xs[0], 1)
}

test "build_heap: already heap" {
  let xs = FixedArray::make(4, 0)
  xs[0] = 1
  xs[1] = 3
  xs[2] = 2
  xs[3] = 4
  let size = build_heap(xs)
  assert_eq(size, 4)
  assert_eq(xs[0], 1)
}

test "heap_push: basic" {
  let xs = FixedArray::make(10, 0)
  xs[0] = 5
  let mut size = 1
  size = heap_push(xs, size, 3).unwrap()
  assert_eq(xs[0], 3)
  size = heap_push(xs, size, 1).unwrap()
  assert_eq(xs[0], 1)
  size = heap_push(xs, size, 7).unwrap()
  assert_eq(xs[0], 1)
}

test "heap_push: overflow" {
  let xs = FixedArray::make(2, 0)
  xs[0] = 5
  let size = heap_push(xs, 1, 3)  // fills capacity
  assert_eq(size.unwrap(), 2)
  let overflow = heap_push(xs, 2, 99)  // full!
  assert_true(overflow is None)
}

test "heap_pop: basic" {
  let xs = FixedArray::make(5, 0)
  xs[0] = 1
  xs[1] = 3
  xs[2] = 2
  xs[3] = 5
  xs[4] = 4
  let (result, new_size) = heap_pop(xs, 5)
  assert_true(result is Some(_))
  assert_eq(result.unwrap(), 1)
  assert_eq(new_size, 4)
}

test "heap_pop: empty" {
  let xs = FixedArray::make(5, 0)
  let (result, new_size) = heap_pop(xs, 0)
  assert_true(result is None)
  assert_eq(new_size, 0)
}

test "heap_pop: interleave push" {
  let xs = FixedArray::make(20, 0)
  let mut size = 0
  size = heap_push(xs, size, 5).unwrap()
  size = heap_push(xs, size, 3).unwrap()
  size = heap_push(xs, size, 8).unwrap()
  size = heap_push(xs, size, 1).unwrap()
  size = heap_push(xs, size, 9).unwrap()
  let (r1, s1) = heap_pop(xs, size)
  assert_eq(r1.unwrap(), 1)
  size = s1
  size = heap_push(xs, size, 2).unwrap()
  let (r2, s2) = heap_pop(xs, size)
  assert_eq(r2.unwrap(), 2)
  size = s2
  let (r3, s3) = heap_pop(xs, size)
  assert_eq(r3.unwrap(), 3)
  size = s3
  let (r4, s4) = heap_pop(xs, size)
  assert_eq(r4.unwrap(), 5)
  size = s4
  let (r5, s5) = heap_pop(xs, size)
  assert_eq(r5.unwrap(), 8)
  size = s5
  let (r6, _) = heap_pop(xs, size)
  assert_eq(r6.unwrap(), 9)
}

test "heap_sort: basic" {
  let xs = FixedArray::makei(6, fn(i) { 6 - i })  // [6,5,4,3,2,1]
  heap_sort(xs)
  assert_eq(xs[0], 1)
  assert_eq(xs[1], 2)
  assert_eq(xs[2], 3)
  assert_eq(xs[3], 4)
  assert_eq(xs[4], 5)
  assert_eq(xs[5], 6)
}

test "heap_sort: already sorted" {
  let xs = FixedArray::makei(5, fn(i) { i })
  heap_sort(xs)
  for k = 0; k < 5; k = k + 1 {
    assert_eq(xs[k], k)
  }
}

test "heap_sort: empty" {
  let xs = FixedArray::make(0, 0)
  heap_sort(xs)
  assert_eq(xs.length(), 0)
}

test "heap_sort: duplicates" {
  let xs = FixedArray::makei(8, fn(i) { i % 3 })
  heap_sort(xs)
  for k = 0; k < 7; k = k + 1 {
    assert_eq(xs[k] <= xs[k + 1], true)
  }
}

test "heap_sort: single" {
  let xs = FixedArray::make(1, 42)
  heap_sort(xs)
  assert_eq(xs[0], 42)
}

test "heap_sort: permutation check" {
  let n = 50
  let xs = FixedArray::makei(n, fn(i) { (i * 7 + 3) % 31 })
  let orig_freq = FixedArray::make(31, 0)
  for k = 0; k < n; k = k + 1 {
    orig_freq[xs[k]] = orig_freq[xs[k]] + 1
  }
  heap_sort(xs)
  for k = 0; k < n - 1; k = k + 1 {
    assert_true(xs[k] <= xs[k + 1])
  }
  let sorted_freq = FixedArray::make(31, 0)
  for k = 0; k < n; k = k + 1 {
    sorted_freq[xs[k]] = sorted_freq[xs[k]] + 1
  }
  for k = 0; k < 31; k = k + 1 {
    assert_eq(orig_freq[k], sorted_freq[k])
  }
}

test "Heap: encapsulated push and pop" {
  let h = heap_new(10)
  assert_true(h.heap_is_empty())
  assert_true(h.heap_push(5) is Some(_))
  assert_true(h.heap_push(3) is Some(_))
  assert_true(h.heap_push(7) is Some(_))
  assert_eq(h.heap_size(), 3)
  assert_eq(h.heap_peek(), Some(3))
  assert_eq(h.heap_pop(), Some(3))
  assert_eq(h.heap_pop(), Some(5))
  assert_eq(h.heap_pop(), Some(7))
  assert_true(h.heap_is_empty())
}

test "Heap: build from array" {
  let h = heap_new(6)
  // Copy values into heap
  let vals = [6, 5, 4, 3, 2, 1]
  for k = 0; k < 6; k = k + 1 {
    h.data[k] = vals[k]
  }
  h.size = 6
  h.heap_build()
  assert_eq(h.heap_peek(), Some(1))
  assert_eq(h.heap_pop(), Some(1))
  assert_eq(h.heap_pop(), Some(2))
}

test "Heap: interleave operations" {
  let h = heap_new(20)
  let _ = h.heap_push(5)
  let _ = h.heap_push(3)
  let _ = h.heap_push(8)
  let _ = h.heap_push(1)
  let _ = h.heap_push(9)
  assert_eq(h.heap_pop(), Some(1))
  let _ = h.heap_push(2)
  assert_eq(h.heap_pop(), Some(2))
  assert_eq(h.heap_pop(), Some(3))
  assert_eq(h.heap_pop(), Some(5))
  assert_eq(h.heap_pop(), Some(8))
  assert_eq(h.heap_pop(), Some(9))
  assert_true(h.heap_is_empty())
  assert_true(h.heap_pop() is None)
}

test "Heap: push to full returns None" {
  let h = heap_new(2)
  assert_true(h.heap_push(5) is Some(_))
  assert_true(h.heap_push(3) is Some(_))
  // Heap is now full
  assert_true(h.heap_push(7) is None)
  // Verify heap state unchanged
  assert_eq(h.heap_size(), 2)
  assert_eq(h.heap_peek(), Some(3))
}

// ---------------------------------------------------------------------------
// HeapG[T] tests
// ---------------------------------------------------------------------------

test "HeapG: min-heap basic push and pop" {
  let h = HeapG::new(fn(a : Int, b : Int) { a - b })
  assert_true(h.is_empty())
  h.push(5)
  h.push(3)
  h.push(7)
  h.push(1)
  h.push(9)
  assert_eq(h.len(), 5)
  assert_eq(h.peek(), Some(1))
  assert_eq(h.pop(), Some(1))
  assert_eq(h.pop(), Some(3))
  assert_eq(h.pop(), Some(5))
  assert_eq(h.pop(), Some(7))
  assert_eq(h.pop(), Some(9))
  assert_true(h.is_empty())
  assert_true(h.pop() is None)
}

test "HeapG: max-heap via reversed comparator" {
  let h = HeapG::new(fn(a : Int, b : Int) { b - a })
  h.push(5)
  h.push(3)
  h.push(8)
  h.push(1)
  assert_eq(h.peek(), Some(8))
  assert_eq(h.pop(), Some(8))
  assert_eq(h.pop(), Some(5))
  assert_eq(h.pop(), Some(3))
  assert_eq(h.pop(), Some(1))
}

test "HeapG: dynamic resizing (push beyond initial capacity)" {
  let h = HeapG::new(fn(a : Int, b : Int) { a - b })
  // Push 100 elements to trigger multiple resizes.
  for i = 0; i < 100; i = i + 1 {
    h.push((i * 37 + 13) % 1000)
  }
  assert_eq(h.len(), 100)
  // Verify sorted output by extracting all.
  let mut prev = -1
  for i = 0; i < 100; i = i + 1 {
    let val = h.pop().unwrap()
    assert_true(val >= prev)
    prev = val
  }
  assert_true(h.is_empty())
}

test "HeapG: decrease_key (Dijkstra-style)" {
  // Simulate Dijkstra: push (dist, vertex) tuples, then decrease_key a vertex.
  let h = HeapG::new(fn(a : (Int, Int), b : (Int, Int)) { a.0 - b.0 })
  h.push((10, 1))
  h.push((5, 2))
  h.push((20, 3))
  // Vertex 3 is at index 2 (depends on heap layout). After decrease_key,
  // it should move up.
  let _ = h.decrease_key(2, (3, 3))
  // Now the order should be: (3,3), (5,2), (10,1)
  let r0 = h.pop().unwrap()
  assert_eq(r0.0, 3)
  let r1 = h.pop().unwrap()
  assert_eq(r1.0, 5)
  let r2 = h.pop().unwrap()
  assert_eq(r2.0, 10)
}

test "HeapG: decrease_key out of bounds returns None" {
  let h = HeapG::new(fn(a : Int, b : Int) { a - b })
  h.push(5)
  assert_true(h.decrease_key(5, 1) is None)
  assert_true(h.decrease_key(-1, 1) is None)
  assert_true(h.decrease_key(0, 3) is Some(_))
}

test "HeapG: remove by index" {
  let h = HeapG::new(fn(a : Int, b : Int) { a - b })
  h.push(5)
  h.push(3)
  h.push(8)
  h.push(1)
  h.push(9)
  // Remove element at index 0 (the min, which is 1).
  let removed = h.remove(0).unwrap()
  assert_eq(removed, 1)
  assert_eq(h.len(), 4)
  // Remaining elements should still form a valid heap.
  let mut prev = -1
  while !h.is_empty() {
    let v = h.pop().unwrap()
    assert_true(v >= prev)
    prev = v
  }
}

test "HeapG: remove out of bounds returns None" {
  let h = HeapG::new(fn(a : Int, b : Int) { a - b })
  h.push(5)
  assert_true(h.remove(5) is None)
  assert_true(h.remove(-1) is None)
}

test "HeapG: interleave push and pop" {
  let h = HeapG::new(fn(a : Int, b : Int) { a - b })
  h.push(5)
  h.push(3)
  h.push(8)
  h.push(1)
  assert_eq(h.pop(), Some(1))
  h.push(2)
  assert_eq(h.pop(), Some(2))
  assert_eq(h.pop(), Some(3))
  h.push(0)
  assert_eq(h.pop(), Some(0))
  assert_eq(h.pop(), Some(5))
  assert_eq(h.pop(), Some(8))
  assert_true(h.is_empty())
}

test "HeapG: large stress test (1000 elements)" {
  let h = HeapG::new(fn(a : Int, b : Int) { a - b })
  // Push elements in reverse order.
  for i = 0; i < 1000; i = i + 1 {
    h.push(999 - i)
  }
  // Verify they come out sorted.
  for i = 0; i < 1000; i = i + 1 {
    assert_eq(h.pop(), Some(i))
  }
  assert_true(h.is_empty())
}

test "HeapG: duplicate elements" {
  let h = HeapG::new(fn(a : Int, b : Int) { a - b })
  h.push(5)
  h.push(5)
  h.push(5)
  h.push(3)
  h.push(3)
  assert_eq(h.pop(), Some(3))
  assert_eq(h.pop(), Some(3))
  assert_eq(h.pop(), Some(5))
  assert_eq(h.pop(), Some(5))
  assert_eq(h.pop(), Some(5))
}

test "HeapG: single element" {
  let h = HeapG::new(fn(a : Int, b : Int) { a - b })
  h.push(42)
  assert_eq(h.len(), 1)
  assert_eq(h.peek(), Some(42))
  assert_eq(h.pop(), Some(42))
  assert_true(h.is_empty())
  assert_true(h.peek() is None)
}

test "HeapG: empty heap operations" {
  let h = HeapG::new(fn(a : Int, b : Int) { a - b })
  assert_true(h.is_empty())
  assert_eq(h.len(), 0)
  assert_true(h.peek() is None)
  assert_true(h.pop() is None)
}
