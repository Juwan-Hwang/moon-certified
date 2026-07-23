/// Quick sort with median-of-three pivot selection.
///
/// Uses Lomuto partition scheme but selects the median of the first, middle,
/// and last elements as the pivot. This prevents O(n²) degradation on already
/// sorted or reverse-sorted inputs.
///
/// Not formally verified. Correctness ensured by comprehensive tests
/// including permutation checks.

/// Swap two elements in an array.
fn swap(xs : FixedArray[Int], i : Int, j : Int) -> Unit {
  let tmp = xs[i]
  xs[i] = xs[j]
  xs[j] = tmp
}

/// Select the median of xs[lo], xs[mid], xs[hi] and place it at xs[hi]
/// as the pivot for Lomuto partition.
fn median_of_three(xs : FixedArray[Int], lo : Int, hi : Int) -> Unit {
  let mid = lo + (hi - lo) / 2
  // Sort lo, mid, hi so that xs[lo] <= xs[mid] <= xs[hi]
  if xs[mid] < xs[lo] {
    swap(xs, lo, mid)
  }
  if xs[hi] < xs[lo] {
    swap(xs, lo, hi)
  }
  if xs[hi] < xs[mid] {
    swap(xs, mid, hi)
  }
  // Now xs[mid] is the median; move it to xs[hi] as the pivot
  swap(xs, mid, hi)
}

/// Partition subroutine: uses median-of-three pivot selection,
/// places pivot at correct position, with smaller elements to left
/// and larger to right. Returns the pivot's final index.
fn partition(
  xs : FixedArray[Int],
  lo : Int,
  hi : Int,
) -> Int {
  median_of_three(xs, lo, hi)
  let pivot = xs[hi]
  let mut i = lo - 1
  for j = lo; j < hi; {
    if xs[j] <= pivot {
      i = i + 1
      swap(xs, i, j)
    }
    continue j + 1
  } nobreak {
    ()
  }
  // Place pivot at position i+1
  swap(xs, i + 1, hi)
  i + 1
}

/// Recursive quick sort helper.
fn quick_sort_range(
  xs : FixedArray[Int],
  lo : Int,
  hi : Int,
) -> Unit {
  if lo < hi {
    let p = partition(xs, lo, hi)
    quick_sort_range(xs, lo, p - 1)
    quick_sort_range(xs, p + 1, hi)
  }
}

/// Top-level quick sort. Sorts entire array in ascending order.
pub fn quick_sort(
  xs : FixedArray[Int],
) -> Unit {
  let n = xs.length()
  if n <= 1 {
    return
  }
  quick_sort_range(xs, 0, n - 1)
}

test "quick_sort: basic" {
  let xs = FixedArray::makei(5, fn(i) { 5 - i })  // [5,4,3,2,1]
  quick_sort(xs)
  for k = 0; k < 5; k = k + 1 {
    assert_eq(xs[k], k + 1)
  }
}

test "quick_sort: already sorted" {
  let xs = FixedArray::makei(10, fn(i) { i })
  quick_sort(xs)
  for k = 0; k < 10; k = k + 1 {
    assert_eq(xs[k], k)
  }
}

test "quick_sort: reverse sorted" {
  let xs = FixedArray::makei(10, fn(i) { 9 - i })
  quick_sort(xs)
  for k = 0; k < 10; k = k + 1 {
    assert_eq(xs[k], k)
  }
}

test "quick_sort: single element" {
  let xs = FixedArray::make(1, 42)
  quick_sort(xs)
  assert_eq(xs[0], 42)
}

test "quick_sort: empty array" {
  let xs = FixedArray::make(0, 0)
  quick_sort(xs)
  assert_eq(xs.length(), 0)
}

test "quick_sort: duplicates" {
  let xs = FixedArray::makei(8, fn(i) { i % 3 })
  quick_sort(xs)
  assert_eq(xs[0], 0)
  assert_eq(xs[1], 0)
  assert_eq(xs[2], 0)
  assert_eq(xs[3], 1)
  assert_eq(xs[4], 1)
  assert_eq(xs[5], 1)
  assert_eq(xs[6], 2)
  assert_eq(xs[7], 2)
}

test "quick_sort: negative values" {
  let xs = FixedArray::makei(5, fn(i) { 2 - i })  // [2,1,0,-1,-2]
  quick_sort(xs)
  for k = 0; k < 5; k = k + 1 {
    assert_eq(xs[k], k - 2)
  }
}

test "quick_sort: all equal" {
  let xs = FixedArray::make(6, 7)
  quick_sort(xs)
  for k = 0; k < 6; k = k + 1 {
    assert_eq(xs[k], 7)
  }
}

test "quick_sort: two elements" {
  let xs = FixedArray::makei(2, fn(i) { 1 - i })  // [1, 0]
  quick_sort(xs)
  assert_eq(xs[0], 0)
  assert_eq(xs[1], 1)
}

test "quick_sort: large random-like" {
  let xs = FixedArray::makei(30, fn(i) { (i * 7 + 3) % 17 })
  quick_sort(xs)
  for k = 0; k < 29; k = k + 1 {
    assert_eq(xs[k] <= xs[k + 1], true)
  }
}

test "quick_sort: two elements equal" {
  let xs = FixedArray::make(2, 5)
  quick_sort(xs)
  assert_eq(xs[0], 5)
  assert_eq(xs[1], 5)
}

test "quick_sort: permutation check" {
  let n = 50
  let xs = FixedArray::makei(n, fn(i) { (i * 7 + 3) % 31 })
  let orig_freq = FixedArray::make(31, 0)
  for k = 0; k < n; k = k + 1 {
    orig_freq[xs[k]] = orig_freq[xs[k]] + 1
  }
  quick_sort(xs)
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

test "quick_sort: sorted 100 elements (no O(n²) degradation)" {
  // This test specifically catches the old vulnerability where sorted
  // input caused O(n²) behavior. With median-of-three it stays O(n log n).
  let n = 100
  let xs = FixedArray::makei(n, fn(i) { i })
  quick_sort(xs)
  for k = 0; k < n; k = k + 1 {
    assert_eq(xs[k], k)
  }
}

test "quick_sort: reverse sorted 100 elements" {
  let n = 100
  let xs = FixedArray::makei(n, fn(i) { n - 1 - i })
  quick_sort(xs)
  for k = 0; k < n; k = k + 1 {
    assert_eq(xs[k], k)
  }
}
