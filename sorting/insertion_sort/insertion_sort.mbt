/// Generic in-place insertion sort on a FixedArray[T].
/// Not formally verified (proof-enabled: false).
/// Correctness ensured by comprehensive tests including permutation checks.
///
/// Algorithm: For each position i from 1 to n-1, insert xs[i] into the
/// sorted prefix xs[0..i) by shifting larger elements right.
///
/// Comparator convention: cmp(a, b) returns negative if a < b,
/// zero if a == b, positive if a > b.
pub fn[T] insertion_sort(
  xs : FixedArray[T],
  cmp : (T, T) -> Int,
) -> Unit {
  let n = xs.length()
  if n <= 1 {
    return
  }
  for i = 1; i < n; {
    let key = xs[i]
    let pos = for j = i - 1; j >= 0; {
      if cmp(xs[j], key) > 0 {
        xs[j + 1] = xs[j]
        continue j - 1
      } else {
        break j
      }
    } nobreak {
      -1
    }
    xs[pos + 1] = key
    continue i + 1
  } nobreak {
    ()
  }
}

test "insertion_sort: basic" {
  let xs = FixedArray::makei(5, fn(i) { 5 - i }) // [5, 4, 3, 2, 1]
  insertion_sort(xs, fn(a, b) { a - b })
  assert_eq(xs[0], 1)
  assert_eq(xs[1], 2)
  assert_eq(xs[2], 3)
  assert_eq(xs[3], 4)
  assert_eq(xs[4], 5)
}

test "insertion_sort: already sorted" {
  let xs = FixedArray::makei(5, fn(i) { i }) // [0, 1, 2, 3, 4]
  insertion_sort(xs, fn(a, b) { a - b })
  for k = 0; k < 5; k = k + 1 {
    assert_eq(xs[k], k)
  }
}

test "insertion_sort: reverse sorted" {
  let xs = FixedArray::makei(10, fn(i) { 9 - i }) // [9, 8, ..., 0]
  insertion_sort(xs, fn(a, b) { a - b })
  for k = 0; k < 10; k = k + 1 {
    assert_eq(xs[k], k)
  }
}

test "insertion_sort: single element" {
  let xs = FixedArray::make(1, 42)
  insertion_sort(xs, fn(a, b) { a - b })
  assert_eq(xs[0], 42)
}

test "insertion_sort: empty array" {
  let xs = FixedArray::make(0, 0)
  insertion_sort(xs, fn(a, b) { a - b })
  assert_eq(xs.length(), 0)
}

test "insertion_sort: duplicates" {
  let xs = FixedArray::makei(8, fn(i) { i % 3 }) // [0,1,2,0,1,2,0,1]
  insertion_sort(xs, fn(a, b) { a - b })
  assert_eq(xs[0], 0)
  assert_eq(xs[1], 0)
  assert_eq(xs[2], 0)
  assert_eq(xs[3], 1)
  assert_eq(xs[4], 1)
  assert_eq(xs[5], 1)
  assert_eq(xs[6], 2)
  assert_eq(xs[7], 2)
}

test "insertion_sort: negative values" {
  let xs = FixedArray::makei(5, fn(i) { i - 2 }) // [-2, -1, 0, 1, 2]
  insertion_sort(xs, fn(a, b) { a - b })
  for k = 0; k < 5; k = k + 1 {
    assert_eq(xs[k], k - 2)
  }
}

test "insertion_sort: all equal" {
  let xs = FixedArray::make(6, 7)
  insertion_sort(xs, fn(a, b) { a - b })
  for k = 0; k < 6; k = k + 1 {
    assert_eq(xs[k], 7)
  }
}

test "insertion_sort: two elements" {
  let xs = FixedArray::makei(2, fn(i) { 1 - i }) // [1, 0]
  insertion_sort(xs, fn(a, b) { a - b })
  assert_eq(xs[0], 0)
  assert_eq(xs[1], 1)
}

test "insertion_sort: large random-like" {
  let xs = FixedArray::makei(20, fn(i) { (i * 7 + 3) % 13 })
  insertion_sort(xs, fn(a, b) { a - b })
  for k = 0; k < 19; k = k + 1 {
    assert_eq(xs[k] <= xs[k + 1], true)
  }
}

test "insertion_sort: permutation check" {
  let n = 50
  let xs = FixedArray::makei(n, fn(i) { (i * 7 + 3) % 31 })
  let orig_freq = FixedArray::make(31, 0)
  for k = 0; k < n; k = k + 1 {
    orig_freq[xs[k]] = orig_freq[xs[k]] + 1
  }
  insertion_sort(xs, fn(a, b) { a - b })
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

test "insertion_sort: generic with String" {
  let xs = FixedArray::make(4, "")
  xs[0] = "date"
  xs[1] = "apple"
  xs[2] = "cherry"
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
  insertion_sort(xs, str_cmp)
  assert_eq(xs[0], "apple")
  assert_eq(xs[1], "banana")
  assert_eq(xs[2], "cherry")
  assert_eq(xs[3], "date")
}
