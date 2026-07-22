/// Min-heap operations on a FixedArray[Int].
///
/// The heap uses 0-indexed binary tree:
///   parent(i) = (i-1)/2, left(i) = 2*i+1, right(i) = 2*i+2.
///
/// All public functions validate inputs and return safe values on error:
/// - heap_push returns -1 if the array is full (size >= capacity)
/// - heap_pop returns None if the heap is empty (size <= 0)
/// - sift_up / sift_down are no-ops on invalid indices
///
/// Not formally verified (while loops with mutable state).
/// Correctness ensured by comprehensive tests including permutation checks.

/// Swap two elements in an array.
fn swap(xs : FixedArray[Int], i : Int, j : Int) -> Unit {
  let tmp = xs[i]
  xs[i] = xs[j]
  xs[j] = tmp
}

/// Sift up from position idx to restore min-heap property.
/// No-op if idx is out of bounds. Internal helper.
fn sift_up(xs : FixedArray[Int], size : Int, idx : Int) -> Unit {
  if idx < 0 || idx >= size {
    return
  }
  let mut i = idx
  while i > 0 {
    let parent = (i - 1) / 2
    if xs[i] < xs[parent] {
      swap(xs, i, parent)
      i = parent
    } else {
      break
    }
  }
}

/// Sift down from position idx within heap of given size.
/// No-op if idx is out of bounds or size <= 0. Internal helper.
fn sift_down(xs : FixedArray[Int], size : Int, idx : Int) -> Unit {
  if idx < 0 || size <= 0 || idx >= size {
    return
  }
  let mut i = idx
  while true {
    let left = 2 * i + 1
    let right = 2 * i + 2
    let mut smallest = i
    if left < size && xs[left] < xs[smallest] {
      smallest = left
    }
    if right < size && xs[right] < xs[smallest] {
      smallest = right
    }
    if smallest == i {
      break
    }
    swap(xs, i, smallest)
    i = smallest
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
    sift_down(xs, n, i)
    i = i - 1
  }
  n
}

/// Push a value onto the heap. Returns new size on success, or -1 if full.
pub fn heap_push(
  xs : FixedArray[Int],
  size : Int,
  val : Int,
) -> Int {
  let capacity = xs.length()
  if size < 0 || size >= capacity {
    return -1
  }
  xs[size] = val
  sift_up(xs, size + 1, size)
  size + 1
}

/// Pop the minimum element from the heap.
/// Returns Some(min_val) on success, None if heap is empty.
pub fn heap_pop(
  xs : FixedArray[Int],
  size : Int,
) -> Int? {
  if size <= 0 {
    return None
  }
  let min_val = xs[0]
  xs[0] = xs[size - 1]
  sift_down(xs, size - 1, 0)
  Some(min_val)
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
    sift_down_max(xs, n, i)
    i = i - 1
  }
  // Extract max to end, shrink heap
  let mut end = n - 1
  while end > 0 {
    swap(xs, 0, end)
    sift_down_max(xs, end, 0)
    end = end - 1
  }
}

/// Sift down for max-heap (internal helper for heap_sort).
fn sift_down_max(xs : FixedArray[Int], size : Int, idx : Int) -> Unit {
  let mut i = idx
  while true {
    let left = 2 * i + 1
    let right = 2 * i + 2
    let mut largest = i
    if left < size && xs[left] > xs[largest] {
      largest = left
    }
    if right < size && xs[right] > xs[largest] {
      largest = right
    }
    if largest == i {
      break
    }
    swap(xs, i, largest)
    i = largest
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
  size = heap_push(xs, size, 3)
  assert_eq(xs[0], 3)
  size = heap_push(xs, size, 1)
  assert_eq(xs[0], 1)
  size = heap_push(xs, size, 7)
  assert_eq(xs[0], 1)
}

test "heap_push: overflow" {
  let xs = FixedArray::make(2, 0)
  xs[0] = 5
  let size = heap_push(xs, 1, 3)  // fills capacity
  assert_eq(size, 2)
  let overflow = heap_push(xs, 2, 99)  // full!
  assert_eq(overflow, -1)
}

test "heap_pop: basic" {
  let xs = FixedArray::make(5, 0)
  xs[0] = 1
  xs[1] = 3
  xs[2] = 2
  xs[3] = 5
  xs[4] = 4
  let result = heap_pop(xs, 5)
  assert_true(result is Some(_))
  assert_eq(result.unwrap(), 1)
}

test "heap_pop: empty" {
  let xs = FixedArray::make(5, 0)
  let result = heap_pop(xs, 0)
  assert_true(result is None)
}

test "heap_pop: interleave push" {
  let xs = FixedArray::make(20, 0)
  let mut size = 0
  size = heap_push(xs, size, 5)
  size = heap_push(xs, size, 3)
  size = heap_push(xs, size, 8)
  size = heap_push(xs, size, 1)
  size = heap_push(xs, size, 9)
  assert_eq(heap_pop(xs, size).unwrap(), 1)
  size = size - 1
  size = heap_push(xs, size, 2)
  assert_eq(heap_pop(xs, size).unwrap(), 2)
  size = size - 1
  assert_eq(heap_pop(xs, size).unwrap(), 3)
  size = size - 1
  assert_eq(heap_pop(xs, size).unwrap(), 5)
  size = size - 1
  assert_eq(heap_pop(xs, size).unwrap(), 8)
  size = size - 1
  assert_eq(heap_pop(xs, size).unwrap(), 9)
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
  // Verify that sorted output is a permutation of input,
  // not just that it's sorted.
  let n = 50
  let xs = FixedArray::makei(n, fn(i) { (i * 7 + 3) % 31 })
  // Count original frequencies
  let orig_freq = FixedArray::make(31, 0)
  for k = 0; k < n; k = k + 1 {
    orig_freq[xs[k]] = orig_freq[xs[k]] + 1
  }
  heap_sort(xs)
  // Verify sorted
  for k = 0; k < n - 1; k = k + 1 {
    assert_true(xs[k] <= xs[k + 1])
  }
  // Verify permutation: same frequencies
  let sorted_freq = FixedArray::make(31, 0)
  for k = 0; k < n; k = k + 1 {
    sorted_freq[xs[k]] = sorted_freq[xs[k]] + 1
  }
  for k = 0; k < 31; k = k + 1 {
    assert_eq(orig_freq[k], sorted_freq[k])
  }
}
