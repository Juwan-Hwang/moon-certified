/// Generic in-place heap sort on a FixedArray[T].
/// Not formally verified (proof-enabled: false).
/// Correctness ensured by comprehensive tests including permutation checks.
///
/// Algorithm:
///   1. Build a max-heap in place over the whole array using Floyd's
///      linear-time construction: sift down every non-leaf node, starting
///      from the last parent (index n/2 - 1) and moving up to the root.
///   2. Repeatedly swap the root (the current maximum) with the last element
///      of the active heap, shrink the heap by one, and sift the new root
///      down to restore the max-heap property.
///   After n - 1 extractions the array is sorted in ascending order. No
///   reversal pass is needed because a max-heap places largest elements at
///   the end first.
///
/// The heap is a 0-indexed binary tree:
///   parent(i) = (i - 1) / 2,  left(i) = 2*i + 1,  right(i) = 2*i + 2.
///
/// Complexity:
///   - Time:  O(n log n) in the best, average, and worst case.
///   - Space: O(1) auxiliary (in-place; the iterative sift-down uses only a
///            constant number of local variables, no recursion).
///
/// Properties:
///   - Not stable (equal elements may be reordered).
///   - Not adaptive (already-sorted input is still O(n log n)).
///
/// Comparator convention: cmp(a, b) returns negative if a < b,
/// zero if a == b, positive if a > b.

/// Swap two elements in a generic array.
fn[T] swap(xs : FixedArray[T], i : Int, j : Int) -> Unit {
  let tmp = xs[i]
  xs[i] = xs[j]
  xs[j] = tmp
}

/// Sift-down for a max-heap over xs[0..size).
///
/// Moves the element at `idx` down the tree until the max-heap property
/// (parent >= children, under `cmp`) is restored. At each node it picks the
/// largest among the node and its two children; if a child is larger it
/// swaps and continues, otherwise it stops.
fn[T] sift_down(
  xs : FixedArray[T],
  size : Int,
  idx : Int,
  cmp : (T, T) -> Int,
) -> Unit {
  let mut i = idx
  while true {
    let left = 2 * i + 1
    let right = 2 * i + 2
    let mut largest = i
    // Is the left child larger than the current largest?
    if left < size && cmp(xs[left], xs[largest]) > 0 {
      largest = left
    }
    // Is the right child larger than the current largest?
    if right < size && cmp(xs[right], xs[largest]) > 0 {
      largest = right
    }
    if largest == i {
      break
    }
    swap(xs, i, largest)
    i = largest
  }
}

/// Build a max-heap in place over xs[0..n) using Floyd's method:
/// sift down every non-leaf node, from the last parent down to the root.
fn[T] build_max_heap(
  xs : FixedArray[T],
  n : Int,
  cmp : (T, T) -> Int,
) -> Unit {
  // The last non-leaf node sits at index n / 2 - 1.
  let mut i = n / 2 - 1
  while i >= 0 {
    sift_down(xs, n, i, cmp)
    i = i - 1
  }
}

/// Generic in-place heap sort.
/// Sorts the entire array in ascending order according to `cmp`.
pub fn[T] heap_sort(
  xs : FixedArray[T],
  cmp : (T, T) -> Int,
) -> Unit {
  let n = xs.length()
  if n <= 1 {
    return
  }
  // Phase 1: turn the array into a max-heap.
  build_max_heap(xs, n, cmp)
  // Phase 2: repeatedly move the current maximum to the end of the
  // active region and restore the heap property on the shrinking prefix.
  let mut end = n - 1
  while end > 0 {
    swap(xs, 0, end)
    sift_down(xs, end, 0, cmp)
    end = end - 1
  }
}

test "heap_sort: basic" {
  let xs = FixedArray::makei(5, fn(i) { 5 - i }) // [5, 4, 3, 2, 1]
  heap_sort(xs, fn(a, b) { a - b })
  assert_eq(xs[0], 1)
  assert_eq(xs[1], 2)
  assert_eq(xs[2], 3)
  assert_eq(xs[3], 4)
  assert_eq(xs[4], 5)
}

test "heap_sort: already sorted" {
  let xs = FixedArray::makei(10, fn(i) { i }) // [0, 1, ..., 9]
  heap_sort(xs, fn(a, b) { a - b })
  for k = 0; k < 10; k = k + 1 {
    assert_eq(xs[k], k)
  }
}

test "heap_sort: reverse sorted" {
  let xs = FixedArray::makei(10, fn(i) { 9 - i }) // [9, 8, ..., 0]
  heap_sort(xs, fn(a, b) { a - b })
  for k = 0; k < 10; k = k + 1 {
    assert_eq(xs[k], k)
  }
}

test "heap_sort: single element" {
  let xs = FixedArray::make(1, 42)
  heap_sort(xs, fn(a, b) { a - b })
  assert_eq(xs[0], 42)
}

test "heap_sort: empty array" {
  let xs = FixedArray::make(0, 0)
  heap_sort(xs, fn(a, b) { a - b })
  assert_eq(xs.length(), 0)
}

test "heap_sort: duplicates" {
  let xs = FixedArray::makei(8, fn(i) { i % 3 }) // [0,1,2,0,1,2,0,1]
  heap_sort(xs, fn(a, b) { a - b })
  assert_eq(xs[0], 0)
  assert_eq(xs[1], 0)
  assert_eq(xs[2], 0)
  assert_eq(xs[3], 1)
  assert_eq(xs[4], 1)
  assert_eq(xs[5], 1)
  assert_eq(xs[6], 2)
  assert_eq(xs[7], 2)
}

test "heap_sort: negative values" {
  let xs = FixedArray::makei(5, fn(i) { 2 - i }) // [2, 1, 0, -1, -2]
  heap_sort(xs, fn(a, b) { a - b })
  for k = 0; k < 5; k = k + 1 {
    assert_eq(xs[k], k - 2)
  }
}

test "heap_sort: large random-like" {
  let xs = FixedArray::makei(30, fn(i) { (i * 7 + 3) % 17 })
  heap_sort(xs, fn(a, b) { a - b })
  for k = 0; k < 29; k = k + 1 {
    assert_eq(xs[k] <= xs[k + 1], true)
  }
}

test "heap_sort: even length" {
  let xs = FixedArray::makei(8, fn(i) { (i * 3 + 1) % 8 })
  heap_sort(xs, fn(a, b) { a - b })
  for k = 0; k < 7; k = k + 1 {
    assert_eq(xs[k] <= xs[k + 1], true)
  }
}

test "heap_sort: odd length" {
  let xs = FixedArray::makei(7, fn(i) { (i * 5 + 2) % 7 })
  heap_sort(xs, fn(a, b) { a - b })
  for k = 0; k < 6; k = k + 1 {
    assert_eq(xs[k] <= xs[k + 1], true)
  }
}

test "heap_sort: permutation check" {
  let n = 50
  let xs = FixedArray::makei(n, fn(i) { (i * 7 + 3) % 31 })
  let orig_freq = FixedArray::make(31, 0)
  for k = 0; k < n; k = k + 1 {
    orig_freq[xs[k]] = orig_freq[xs[k]] + 1
  }
  heap_sort(xs, fn(a, b) { a - b })
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

test "heap_sort: generic with String" {
  let xs = FixedArray::make(4, "")
  xs[0] = "cherry"
  xs[1] = "apple"
  xs[2] = "date"
  xs[3] = "banana"
  /// Lexicographic string comparator (MoonBit's default Compare uses shortlex).
  let str_cmp = fn(a : String, b : String) -> Int {
    let la = a.length()
    let lb = b.length()
    let min = if la < lb { la } else { lb }
    for k = 0; k < min; k = k + 1 {
      let ca = a[k].to_int()
      let cb = b[k].to_int()
      if ca < cb { return -1 }
      if ca > cb { return 1 }
    }
    la - lb
  }
  heap_sort(xs, str_cmp)
  assert_eq(xs[0], "apple")
  assert_eq(xs[1], "banana")
  assert_eq(xs[2], "cherry")
  assert_eq(xs[3], "date")
}
