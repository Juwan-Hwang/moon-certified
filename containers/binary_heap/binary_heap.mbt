/// Min-heap operations on a FixedArray[Int].
/// The heap uses 0-indexed binary tree: parent(i) = (i-1)/2, left(i) = 2*i+1, right(i) = 2*i+2.
/// Note: sift_up/sift_down use while loops and are tested but not formally verified.
/// build_heap/heap_push/heap_pop delegate to them and are likewise tested-only.

/// Sift up from position idx to restore heap property.
pub fn sift_up(xs : FixedArray[Int], idx : Int) -> Unit {
  let mut i = idx
  while i > 0 {
    let parent = (i - 1) / 2
    if xs[i] < xs[parent] {
      let tmp = xs[i]
      xs[i] = xs[parent]
      xs[parent] = tmp
      i = parent
    } else {
      break
    }
  }
}

/// Sift down from position idx within heap of given size.
pub fn sift_down(xs : FixedArray[Int], size : Int, idx : Int) -> Unit {
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
    let tmp = xs[i]
    xs[i] = xs[smallest]
    xs[smallest] = tmp
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
  for i = (n / 2) - 1; i >= 0; {
    sift_down(xs, n, i)
    continue i - 1
  } nobreak {
    ()
  }
  n
}

/// Push a value onto the heap. Returns new size.
/// Assumes the array has capacity (xs.length() > old size).
pub fn heap_push(
  xs : FixedArray[Int],
  size : Int,
  val : Int,
) -> Int {
  xs[size] = val
  sift_up(xs, size)
  size + 1
}

/// Pop the minimum element from the heap. Returns the popped value.
pub fn heap_pop(
  xs : FixedArray[Int],
  size : Int,
) -> Int {
  let min_val = xs[0]
  xs[0] = xs[size - 1]
  sift_down(xs, size - 1, 0)
  min_val
}

/// Heap sort: sorts the array in ascending order using a min-heap.
pub fn heap_sort(xs : FixedArray[Int]) -> Unit {
  let n = xs.length()
  if n <= 1 {
    return
  }
  let _ = build_heap(xs)
  for end = n - 1; end > 0; {
    let tmp = xs[0]
    xs[0] = xs[end]
    xs[end] = tmp
    sift_down(xs, end, 0)
    continue end - 1
  } nobreak {
    ()
  }
  // After extraction, array is in descending order (min-heap).
  // Reverse to get ascending order.
  for i = 0, j = n - 1; i < j; {
    let tmp = xs[i]
    xs[i] = xs[j]
    xs[j] = tmp
    continue i + 1, j - 1
  } nobreak {
    ()
  }
}

test "sift_up: basic" {
  let xs = FixedArray::make(5, 0)
  xs[0] = 3
  xs[1] = 1
  xs[2] = 5
  xs[3] = 2
  xs[4] = 4
  sift_up(xs, 1)
  assert_eq(xs[0], 1)
  assert_eq(xs[1], 3)
}

test "sift_down: basic" {
  let xs = FixedArray::make(5, 0)
  xs[0] = 5
  xs[1] = 3
  xs[2] = 1
  xs[3] = 4
  xs[4] = 2
  sift_down(xs, 5, 0)
  assert_eq(xs[0], 1)
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

test "heap_pop: basic" {
  let xs = FixedArray::make(5, 0)
  xs[0] = 1
  xs[1] = 3
  xs[2] = 2
  xs[3] = 5
  xs[4] = 4
  let size = 5
  let min_val = heap_pop(xs, size)
  assert_eq(min_val, 1)
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
