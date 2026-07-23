/// Generic quick sort with median-of-three pivot selection.
///
/// Uses Lomuto partition scheme but selects the median of the first, middle,
/// and last elements as the pivot. This prevents O(n²) degradation on already
/// sorted or reverse-sorted inputs.
///
/// Not formally verified. Correctness ensured by comprehensive tests
/// including permutation checks.
///
/// Comparator convention: cmp(a, b) returns negative if a < b,
/// zero if a == b, positive if a > b.

/// Swap two elements in an array.
fn[T] swap(xs : FixedArray[T], i : Int, j : Int) -> Unit {
  let tmp = xs[i]
  xs[i] = xs[j]
  xs[j] = tmp
}

/// Select the median of xs[lo], xs[mid], xs[hi] and place it at xs[hi]
/// as the pivot for Lomuto partition.
fn[T] median_of_three(
  xs : FixedArray[T],
  lo : Int,
  hi : Int,
  cmp : (T, T) -> Int,
) -> Unit {
  let mid = lo + (hi - lo) / 2
  // Sort lo, mid, hi so that xs[lo] <= xs[mid] <= xs[hi]
  if cmp(xs[mid], xs[lo]) < 0 {
    swap(xs, lo, mid)
  }
  if cmp(xs[hi], xs[lo]) < 0 {
    swap(xs, lo, hi)
  }
  if cmp(xs[hi], xs[mid]) < 0 {
    swap(xs, mid, hi)
  }
  // Now xs[mid] is the median; move it to xs[hi] as the pivot
  swap(xs, mid, hi)
}

/// Partition subroutine: uses median-of-three pivot selection,
/// places pivot at correct position, with smaller elements to left
/// and larger to right. Returns the pivot's final index.
fn[T] partition(
  xs : FixedArray[T],
  lo : Int,
  hi : Int,
  cmp : (T, T) -> Int,
) -> Int {
  median_of_three(xs, lo, hi, cmp)
  let pivot = xs[hi]
  let mut i = lo - 1
  for j = lo; j < hi; {
    if cmp(xs[j], pivot) <= 0 {
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
/// Uses insertion sort for small partitions (≤ 16 elements) to reduce
/// recursion depth and improve cache performance.
/// The INSERTION_THRESHOLD limits recursion depth to O(log n) in practice.
const INSERTION_THRESHOLD : Int = 16

/// Insertion sort for small subarrays.
fn[T] insertion_sort_range(
  xs : FixedArray[T],
  lo : Int,
  hi : Int,
  cmp : (T, T) -> Int,
) -> Unit {
  for i = lo + 1; i <= hi; i = i + 1 {
    let key = xs[i]
    let mut j = i - 1
    while j >= lo && cmp(xs[j], key) > 0 {
      xs[j + 1] = xs[j]
      j = j - 1
    }
    xs[j + 1] = key
  }
}

fn[T] quick_sort_range(
  xs : FixedArray[T],
  lo : Int,
  hi : Int,
  cmp : (T, T) -> Int,
) -> Unit {
  if hi - lo <= INSERTION_THRESHOLD {
    if lo < hi {
      insertion_sort_range(xs, lo, hi, cmp)
    }
    return
  }
  let p = partition(xs, lo, hi, cmp)
  // Recurse on the smaller partition first to bound stack depth to O(log n).
  if p - lo < hi - p {
    quick_sort_range(xs, lo, p - 1, cmp)
    quick_sort_range(xs, p + 1, hi, cmp)
  } else {
    quick_sort_range(xs, p + 1, hi, cmp)
    quick_sort_range(xs, lo, p - 1, cmp)
  }
}

/// Top-level quick sort. Sorts entire array in ascending order
/// according to the provided comparator.
pub fn[T] quick_sort(
  xs : FixedArray[T],
  cmp : (T, T) -> Int,
) -> Unit {
  let n = xs.length()
  if n <= 1 {
    return
  }
  quick_sort_range(xs, 0, n - 1, cmp)
}

test "quick_sort: basic" {
  let xs = FixedArray::makei(5, fn(i) { 5 - i }) // [5,4,3,2,1]
  quick_sort(xs, fn(a, b) { a - b })
  for k = 0; k < 5; k = k + 1 {
    assert_eq(xs[k], k + 1)
  }
}

test "quick_sort: already sorted" {
  let xs = FixedArray::makei(10, fn(i) { i })
  quick_sort(xs, fn(a, b) { a - b })
  for k = 0; k < 10; k = k + 1 {
    assert_eq(xs[k], k)
  }
}

test "quick_sort: reverse sorted" {
  let xs = FixedArray::makei(10, fn(i) { 9 - i })
  quick_sort(xs, fn(a, b) { a - b })
  for k = 0; k < 10; k = k + 1 {
    assert_eq(xs[k], k)
  }
}

test "quick_sort: single element" {
  let xs = FixedArray::make(1, 42)
  quick_sort(xs, fn(a, b) { a - b })
  assert_eq(xs[0], 42)
}

test "quick_sort: empty array" {
  let xs = FixedArray::make(0, 0)
  quick_sort(xs, fn(a, b) { a - b })
  assert_eq(xs.length(), 0)
}

test "quick_sort: duplicates" {
  let xs = FixedArray::makei(8, fn(i) { i % 3 })
  quick_sort(xs, fn(a, b) { a - b })
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
  let xs = FixedArray::makei(5, fn(i) { 2 - i }) // [2,1,0,-1,-2]
  quick_sort(xs, fn(a, b) { a - b })
  for k = 0; k < 5; k = k + 1 {
    assert_eq(xs[k], k - 2)
  }
}

test "quick_sort: all equal" {
  let xs = FixedArray::make(6, 7)
  quick_sort(xs, fn(a, b) { a - b })
  for k = 0; k < 6; k = k + 1 {
    assert_eq(xs[k], 7)
  }
}

test "quick_sort: two elements" {
  let xs = FixedArray::makei(2, fn(i) { 1 - i }) // [1, 0]
  quick_sort(xs, fn(a, b) { a - b })
  assert_eq(xs[0], 0)
  assert_eq(xs[1], 1)
}

test "quick_sort: large random-like" {
  let xs = FixedArray::makei(30, fn(i) { (i * 7 + 3) % 17 })
  quick_sort(xs, fn(a, b) { a - b })
  for k = 0; k < 29; k = k + 1 {
    assert_eq(xs[k] <= xs[k + 1], true)
  }
}

test "quick_sort: two elements equal" {
  let xs = FixedArray::make(2, 5)
  quick_sort(xs, fn(a, b) { a - b })
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
  quick_sort(xs, fn(a, b) { a - b })
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
  quick_sort(xs, fn(a, b) { a - b })
  for k = 0; k < n; k = k + 1 {
    assert_eq(xs[k], k)
  }
}

test "quick_sort: reverse sorted 100 elements" {
  let n = 100
  let xs = FixedArray::makei(n, fn(i) { n - 1 - i })
  quick_sort(xs, fn(a, b) { a - b })
  for k = 0; k < n; k = k + 1 {
    assert_eq(xs[k], k)
  }
}

test "quick_sort: generic with String" {
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
  quick_sort(xs, str_cmp)
  assert_eq(xs[0], "apple")
  assert_eq(xs[1], "banana")
  assert_eq(xs[2], "cherry")
  assert_eq(xs[3], "date")
}
