/// Generic merge sort implementation.
/// Uses a recursive top-down approach with an auxiliary buffer.
///
/// Not formally verified (recursive helpers + while loops).
/// Correctness ensured by comprehensive tests including permutation checks.
///
/// Comparator convention: cmp(a, b) returns negative if a < b,
/// zero if a == b, positive if a > b.

/// Merge two sorted halves xs[lo..mid) and xs[mid..hi) into sorted output.
/// Uses auxiliary buffer `buf` for temporary storage.
fn[T] merge(
  xs : FixedArray[T],
  buf : FixedArray[T],
  lo : Int,
  mid : Int,
  hi : Int,
  cmp : (T, T) -> Int,
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
    if i < mid && (j >= hi || cmp(buf[i], buf[j]) <= 0) {
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
fn[T] merge_sort_range(
  xs : FixedArray[T],
  buf : FixedArray[T],
  lo : Int,
  hi : Int,
  cmp : (T, T) -> Int,
) -> Unit {
  if hi - lo <= 1 {
    return
  }
  let mid = lo + (hi - lo) / 2
  merge_sort_range(xs, buf, lo, mid, cmp)
  merge_sort_range(xs, buf, mid, hi, cmp)
  merge(xs, buf, lo, mid, hi, cmp)
}

/// Top-level merge sort. Sorts the entire array in ascending order
/// according to the provided comparator.
pub fn[T] merge_sort(
  xs : FixedArray[T],
  cmp : (T, T) -> Int,
) -> Unit {
  let n = xs.length()
  if n <= 1 {
    return
  }
  // Safe: n >= 2 here, so xs[0] exists. The buffer is overwritten
  // by merge before being read, so the initial value doesn't matter.
  let buf : FixedArray[T] = FixedArray::make(n, xs[0])
  merge_sort_range(xs, buf, 0, n, cmp)
}

test "merge_sort: basic" {
  let xs = FixedArray::makei(5, fn(i) { 5 - i }) // [5,4,3,2,1]
  merge_sort(xs, fn(a, b) { a - b })
  for k = 0; k < 5; k = k + 1 {
    assert_eq(xs[k], k + 1)
  }
}

test "merge_sort: already sorted" {
  let xs = FixedArray::makei(10, fn(i) { i })
  merge_sort(xs, fn(a, b) { a - b })
  for k = 0; k < 10; k = k + 1 {
    assert_eq(xs[k], k)
  }
}

test "merge_sort: reverse sorted" {
  let xs = FixedArray::makei(10, fn(i) { 9 - i })
  merge_sort(xs, fn(a, b) { a - b })
  for k = 0; k < 10; k = k + 1 {
    assert_eq(xs[k], k)
  }
}

test "merge_sort: single element" {
  let xs = FixedArray::make(1, 42)
  merge_sort(xs, fn(a, b) { a - b })
  assert_eq(xs[0], 42)
}

test "merge_sort: empty array" {
  let xs = FixedArray::make(0, 0)
  merge_sort(xs, fn(a, b) { a - b })
  assert_eq(xs.length(), 0)
}

test "merge_sort: duplicates" {
  let xs = FixedArray::makei(8, fn(i) { i % 3 }) // [0,1,2,0,1,2,0,1]
  merge_sort(xs, fn(a, b) { a - b })
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
  let xs = FixedArray::makei(5, fn(i) { 2 - i }) // [2,1,0,-1,-2]
  merge_sort(xs, fn(a, b) { a - b })
  for k = 0; k < 5; k = k + 1 {
    assert_eq(xs[k], k - 2)
  }
}

test "merge_sort: all equal" {
  let xs = FixedArray::make(6, 7)
  merge_sort(xs, fn(a, b) { a - b })
  for k = 0; k < 6; k = k + 1 {
    assert_eq(xs[k], 7)
  }
}

test "merge_sort: two elements" {
  let xs = FixedArray::makei(2, fn(i) { 1 - i }) // [1, 0]
  merge_sort(xs, fn(a, b) { a - b })
  assert_eq(xs[0], 0)
  assert_eq(xs[1], 1)
}

test "merge_sort: large random-like" {
  let xs = FixedArray::makei(30, fn(i) { (i * 7 + 3) % 17 })
  merge_sort(xs, fn(a, b) { a - b })
  for k = 0; k < 29; k = k + 1 {
    assert_eq(xs[k] <= xs[k + 1], true)
  }
}

test "merge_sort: even length" {
  let xs = FixedArray::makei(8, fn(i) { (i * 3 + 1) % 8 })
  merge_sort(xs, fn(a, b) { a - b })
  for k = 0; k < 7; k = k + 1 {
    assert_eq(xs[k] <= xs[k + 1], true)
  }
}

test "merge_sort: odd length" {
  let xs = FixedArray::makei(7, fn(i) { (i * 5 + 2) % 7 })
  merge_sort(xs, fn(a, b) { a - b })
  for k = 0; k < 6; k = k + 1 {
    assert_eq(xs[k] <= xs[k + 1], true)
  }
}

test "merge_sort: permutation check" {
  let n = 50
  let xs = FixedArray::makei(n, fn(i) { (i * 7 + 3) % 31 })
  let orig_freq = FixedArray::make(31, 0)
  for k = 0; k < n; k = k + 1 {
    orig_freq[xs[k]] = orig_freq[xs[k]] + 1
  }
  merge_sort(xs, fn(a, b) { a - b })
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

test "merge_sort: generic with String" {
  let xs = FixedArray::make(5, "")
  xs[0] = "banana"
  xs[1] = "date"
  xs[2] = "apple"
  xs[3] = "elderberry"
  xs[4] = "cherry"
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
  merge_sort(xs, str_cmp)
  assert_eq(xs[0], "apple")
  assert_eq(xs[1], "banana")
  assert_eq(xs[2], "cherry")
  assert_eq(xs[3], "date")
  assert_eq(xs[4], "elderberry")
}

test "merge_sort: stability" {
  // Stability: when two elements compare as equal, their relative order
  // from the original array is preserved. We test this by sorting (key, tag)
  // pairs using a comparator that only looks at the key, then checking that
  // tags within each key group are in ascending order.
  let xs = FixedArray::make(10, (0, 0))
  // Keys: 3, 1, 3, 2, 1, 3, 2, 1, 2, 3 (3 groups of 3,1,2)
  xs[0] = (3, 0)
  xs[1] = (1, 1)
  xs[2] = (3, 2)
  xs[3] = (2, 3)
  xs[4] = (1, 4)
  xs[5] = (3, 5)
  xs[6] = (2, 6)
  xs[7] = (1, 7)
  xs[8] = (2, 8)
  xs[9] = (3, 9)
  // Compare only by key (first element).
  let key_cmp = fn(a : (Int, Int), b : (Int, Int)) -> Int {
    a.0 - b.0
  }
  merge_sort(xs, key_cmp)
  // Keys should be sorted: 1,1,1, 2,2,2, 3,3,3,3
  assert_eq(xs[0].0, 1)
  assert_eq(xs[1].0, 1)
  assert_eq(xs[2].0, 1)
  assert_eq(xs[3].0, 2)
  assert_eq(xs[4].0, 2)
  assert_eq(xs[5].0, 2)
  assert_eq(xs[6].0, 3)
  assert_eq(xs[7].0, 3)
  assert_eq(xs[8].0, 3)
  assert_eq(xs[9].0, 3)
  // Tags within each key group must be in ascending order (stability).
  // Key 1 group: tags should be 1, 4, 7 (original order)
  assert_eq(xs[0].1, 1)
  assert_eq(xs[1].1, 4)
  assert_eq(xs[2].1, 7)
  // Key 2 group: tags should be 3, 6, 8
  assert_eq(xs[3].1, 3)
  assert_eq(xs[4].1, 6)
  assert_eq(xs[5].1, 8)
  // Key 3 group: tags should be 0, 2, 5, 9
  assert_eq(xs[6].1, 0)
  assert_eq(xs[7].1, 2)
  assert_eq(xs[8].1, 5)
  assert_eq(xs[9].1, 9)
}
