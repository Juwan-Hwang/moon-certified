/// Merge sort implementation with verification annotations.
/// Uses a recursive top-down approach with an auxiliary buffer.

/// Merge two sorted halves xs[lo..mid) and xs[mid..hi) into sorted output.
/// Uses auxiliary buffer `buf` for temporary storage.
fn merge(
  xs : FixedArray[Int],
  buf : FixedArray[Int],
  lo : Int,
  mid : Int,
  hi : Int,
) -> Unit {
  // Copy to buffer
  for k = lo; k < hi; {
    buf[k] = xs[k]
    continue k + 1
  } nobreak {
    ()
  }
  let mut i = lo
  let mut j = mid
  let mut k = lo
  while k < hi {
    if i < mid && (j >= hi || buf[i] <= buf[j]) {
      xs[k] = buf[i]
      i = i + 1
    } else {
      xs[k] = buf[j]
      j = j + 1
    }
    k = k + 1
  }
}

/// Recursive merge sort helper.
fn merge_sort_range(
  xs : FixedArray[Int],
  buf : FixedArray[Int],
  lo : Int,
  hi : Int,
) -> Unit {
  if hi - lo <= 1 {
    return
  }
  let mid = lo + (hi - lo) / 2
  merge_sort_range(xs, buf, lo, mid)
  merge_sort_range(xs, buf, mid, hi)
  merge(xs, buf, lo, mid, hi)
}

/// Top-level merge sort. Sorts the entire array in ascending order.
/// Note: uses recursive helpers with while loops; tested but not formally verified.
pub fn merge_sort(
  xs : FixedArray[Int],
) -> Unit {
  let n = xs.length()
  if n <= 1 {
    return
  }
  let buf = FixedArray::make(n, 0)
  merge_sort_range(xs, buf, 0, n)
}

test "merge_sort: basic" {
  let xs = FixedArray::makei(5, fn(i) { 5 - i })  // [5,4,3,2,1]
  merge_sort(xs)
  for k = 0; k < 5; k = k + 1 {
    assert_eq(xs[k], k + 1)
  }
}

test "merge_sort: already sorted" {
  let xs = FixedArray::makei(10, fn(i) { i })
  merge_sort(xs)
  for k = 0; k < 10; k = k + 1 {
    assert_eq(xs[k], k)
  }
}

test "merge_sort: reverse sorted" {
  let xs = FixedArray::makei(10, fn(i) { 9 - i })
  merge_sort(xs)
  for k = 0; k < 10; k = k + 1 {
    assert_eq(xs[k], k)
  }
}

test "merge_sort: single element" {
  let xs = FixedArray::make(1, 42)
  merge_sort(xs)
  assert_eq(xs[0], 42)
}

test "merge_sort: empty array" {
  let xs = FixedArray::make(0, 0)
  merge_sort(xs)
  assert_eq(xs.length(), 0)
}

test "merge_sort: duplicates" {
  let xs = FixedArray::makei(8, fn(i) { i % 3 })  // [0,1,2,0,1,2,0,1]
  merge_sort(xs)
  assert_eq(xs[0], 0)
  assert_eq(xs[1], 0)
  assert_eq(xs[2], 0)
  assert_eq(xs[3], 1)
  assert_eq(xs[4], 1)
  assert_eq(xs[5], 1)
  assert_eq(xs[6], 2)
  assert_eq(xs[7], 2)
}

test "merge_sort: negative values" {
  let xs = FixedArray::makei(5, fn(i) { 2 - i })  // [2,1,0,-1,-2]
  merge_sort(xs)
  for k = 0; k < 5; k = k + 1 {
    assert_eq(xs[k], k - 2)
  }
}

test "merge_sort: all equal" {
  let xs = FixedArray::make(6, 7)
  merge_sort(xs)
  for k = 0; k < 6; k = k + 1 {
    assert_eq(xs[k], 7)
  }
}

test "merge_sort: two elements" {
  let xs = FixedArray::makei(2, fn(i) { 1 - i })  // [1, 0]
  merge_sort(xs)
  assert_eq(xs[0], 0)
  assert_eq(xs[1], 1)
}

test "merge_sort: large random-like" {
  let xs = FixedArray::makei(30, fn(i) { (i * 7 + 3) % 17 })
  merge_sort(xs)
  for k = 0; k < 29; k = k + 1 {
    assert_eq(xs[k] <= xs[k + 1], true)
  }
}

test "merge_sort: even length" {
  let xs = FixedArray::makei(8, fn(i) { (i * 3 + 1) % 8 })
  merge_sort(xs)
  for k = 0; k < 7; k = k + 1 {
    assert_eq(xs[k] <= xs[k + 1], true)
  }
}

test "merge_sort: odd length" {
  let xs = FixedArray::makei(7, fn(i) { (i * 5 + 2) % 7 })
  merge_sort(xs)
  for k = 0; k < 6; k = k + 1 {
    assert_eq(xs[k] <= xs[k + 1], true)
  }
}
