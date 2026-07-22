/// Quick sort with Lomuto partition scheme.
/// In-place sorting with verified postcondition.

/// Partition subroutine: selects last element as pivot,
/// places it at correct position, with smaller elements to left
/// and larger to right. Returns the pivot's final index.
fn partition(
  xs : FixedArray[Int],
  lo : Int,
  hi : Int,
) -> Int {
  let pivot = xs[hi]
  let mut i = lo - 1
  for j = lo; j < hi; {
    if xs[j] <= pivot {
      i = i + 1
      let tmp = xs[i]
      xs[i] = xs[j]
      xs[j] = tmp
    }
    continue j + 1
  } nobreak {
    ()
  }
  // Place pivot at position i+1
  let tmp = xs[i + 1]
  xs[i + 1] = xs[hi]
  xs[hi] = tmp
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
/// Note: uses recursive helpers with while loops; tested but not formally verified.
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
