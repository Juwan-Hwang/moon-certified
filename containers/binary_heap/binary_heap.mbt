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
