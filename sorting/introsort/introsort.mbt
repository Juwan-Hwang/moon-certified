///|
/// Introsort (Introspective Sort) — Musser 1997.
///
/// The hybrid sorting algorithm used in C++ STL `std::sort`. It combines
/// quicksort's average-case speed with heapsort's worst-case guarantee:
///
/// 1. Start with quicksort (using median-of-three pivot).
/// 2. When recursion depth exceeds 2×log₂(n), switch to heapsort.
/// 3. For small partitions (< 16 elements), use insertion sort.
///
/// This gives O(n log n) worst-case while maintaining quicksort's
/// excellent cache performance in practice.
///
/// ## Complexity
/// - Time:  O(n log n) worst, average, and best.
/// - Space: O(log n) for recursion.
/// - Not stable.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.
const INSERTION_THRESHOLD : Int = 16

///|
/// Sort `xs` in-place using Introsort.
pub fn[T] introsort(xs : FixedArray[T], cmp : (T, T) -> Int) -> Unit {
  let n = xs.length()
  if n < 2 {
    return
  }
  let max_depth = 2 * ilog2(n)
  introsort_impl(xs, 0, n - 1, max_depth, cmp)
}

///|
/// Compute floor(log2(n)) for n >= 1.
fn ilog2(n : Int) -> Int {
  let mut k = 0
  let mut m = n
  while m > 1 {
    m = m >> 1
    k = k + 1
  }
  k
}

///|
/// Swap two elements.
fn[T] swap(xs : FixedArray[T], i : Int, j : Int) -> Unit {
  let tmp = xs[i]
  xs[i] = xs[j]
  xs[j] = tmp
}

///|
/// Median-of-three: sort xs[lo], xs[mid], xs[hi] and return mid.
fn[T] median3(
  xs : FixedArray[T],
  lo : Int,
  hi : Int,
  cmp : (T, T) -> Int,
) -> Int {
  let mid = lo + (hi - lo) / 2
  if cmp(xs[lo], xs[mid]) > 0 {
    swap(xs, lo, mid)
  }
  if cmp(xs[lo], xs[hi]) > 0 {
    swap(xs, lo, hi)
  }
  if cmp(xs[mid], xs[hi]) > 0 {
    swap(xs, mid, hi)
  }
  mid
}

///|
/// Recursive introsort implementation.
fn[T] introsort_impl(
  xs : FixedArray[T],
  lo : Int,
  hi : Int,
  depth : Int,
  cmp : (T, T) -> Int,
) -> Unit {
  if hi - lo < INSERTION_THRESHOLD {
    insertion_sort(xs, lo, hi, cmp)
    return
  }
  if depth == 0 {
    heapsort(xs, lo, hi, cmp)
    return
  }
  // Partition using median-of-three pivot.
  let pivot_idx = median3(xs, lo, hi, cmp)
  // Move pivot to hi-1.
  swap(xs, pivot_idx, hi - 1)
  let pivot = xs[hi - 1]
  let mut i = lo
  let mut j = hi - 1
  while true {
    i = i + 1
    while cmp(xs[i], pivot) < 0 {
      i = i + 1
    }
    j = j - 1
    while cmp(xs[j], pivot) > 0 {
      j = j - 1
    }
    if i >= j {
      break
    }
    swap(xs, i, j)
  }
  // Restore pivot.
  swap(xs, i, hi - 1)
  // Recurse.
  introsort_impl(xs, lo, i - 1, depth - 1, cmp)
  introsort_impl(xs, i + 1, hi, depth - 1, cmp)
}

///|
/// Insertion sort for small ranges.
fn[T] insertion_sort(
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

///|
/// Sift-down for heapsort.
fn[T] sift_down(
  xs : FixedArray[T],
  start : Int,
  end : Int,
  root : Int,
  cmp : (T, T) -> Int,
) -> Unit {
  let mut r = root
  while true {
    let left = start + 2 * (r - start) + 1
    let right = left + 1
    let mut largest = r
    if left <= end && cmp(xs[left], xs[largest]) > 0 {
      largest = left
    }
    if right <= end && cmp(xs[right], xs[largest]) > 0 {
      largest = right
    }
    if largest == r {
      break
    }
    swap(xs, r, largest)
    r = largest
  }
}

///|
/// Heapsort for [lo, hi].
fn[T] heapsort(
  xs : FixedArray[T],
  lo : Int,
  hi : Int,
  cmp : (T, T) -> Int,
) -> Unit {
  let n = hi - lo + 1
  let mut i = lo + n / 2 - 1
  while i >= lo {
    sift_down(xs, lo, hi, i, cmp)
    i = i - 1
  }
  let mut end = hi
  while end > lo {
    swap(xs, lo, end)
    sift_down(xs, lo, end - 1, lo, cmp)
    end = end - 1
  }
}

///|
/// Convenience: sort Int array ascending.
pub fn sort_int(xs : FixedArray[Int]) -> Unit {
  introsort(xs, fn(a, b) { a - b })
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "introsort: empty" {
  let xs = FixedArray::make(0, 0)
  sort_int(xs)
  assert_eq(xs.length(), 0)
}

///|
test "introsort: single" {
  let xs = FixedArray::make(1, 42)
  sort_int(xs)
  assert_eq(xs[0], 42)
}

///|
test "introsort: sorted" {
  let xs = FixedArray::makei(100, fn(i) { i })
  sort_int(xs)
  for i = 0; i < 100; i = i + 1 {
    assert_eq(xs[i], i)
  }
}

///|
test "introsort: reverse" {
  let xs = FixedArray::makei(100, fn(i) { 99 - i })
  sort_int(xs)
  for i = 0; i < 100; i = i + 1 {
    assert_eq(xs[i], i)
  }
}

///|
test "introsort: random" {
  let xs = FixedArray::makei(500, fn(i) { (i * 37 + 13) % 503 })
  sort_int(xs)
  for i = 0; i < 499; i = i + 1 {
    assert_true(xs[i] <= xs[i + 1])
  }
}

///|
test "introsort: duplicates" {
  let xs = FixedArray::makei(100, fn(i) { i % 7 })
  sort_int(xs)
  for i = 0; i < 99; i = i + 1 {
    assert_true(xs[i] <= xs[i + 1])
  }
}

///|
test "introsort: all same" {
  let xs = FixedArray::make(50, 7)
  sort_int(xs)
  for i = 0; i < 50; i = i + 1 {
    assert_eq(xs[i], 7)
  }
}

///|
test "introsort: permutation check" {
  let n = 200
  let xs = FixedArray::makei(n, fn(i) { (i * 73 + 17) % n })
  let freq = FixedArray::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    freq[xs[i]] = freq[xs[i]] + 1
  }
  sort_int(xs)
  for i = 0; i < n - 1; i = i + 1 {
    assert_true(xs[i] <= xs[i + 1])
  }
  let freq2 = FixedArray::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    freq2[xs[i]] = freq2[xs[i]] + 1
  }
  for i = 0; i < n; i = i + 1 {
    assert_eq(freq[i], freq2[i])
  }
}

///|
test "introsort: string" {
  let xs = FixedArray::make(5, "")
  xs[0] = "cherry"
  xs[1] = "apple"
  xs[2] = "date"
  xs[3] = "banana"
  xs[4] = "elderberry"
  introsort(xs, @test_utils.str_cmp)
  assert_eq(xs[0], "apple")
  assert_eq(xs[1], "banana")
  assert_eq(xs[2], "cherry")
  assert_eq(xs[3], "date")
  assert_eq(xs[4], "elderberry")
}
