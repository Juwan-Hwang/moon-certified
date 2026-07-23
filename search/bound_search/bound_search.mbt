/// Generic binary search bounds.
///
/// Provides lower_bound, upper_bound, and generic binary search
/// on sorted arrays of any comparable type.
///
/// All functions assume the input array is sorted in ascending order
/// according to the provided comparator. If the array is not sorted,
/// behavior is undefined.

/// Lower bound: first index where xs[i] >= target.
/// Returns xs.length() if all elements are smaller than target.
/// Returns -1 for empty array.
pub fn[T] lower_bound(
  xs : FixedArray[T],
  target : T,
  cmp : (T, T) -> Int,
) -> Int {
  let n = xs.length()
  if n == 0 {
    return -1
  }
  let mut lo = 0
  let mut hi = n
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    if cmp(xs[mid], target) < 0 {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  lo
}

/// Upper bound: first index where xs[i] > target.
/// Returns xs.length() if all elements are <= target.
/// Returns -1 for empty array.
pub fn[T] upper_bound(
  xs : FixedArray[T],
  target : T,
  cmp : (T, T) -> Int,
) -> Int {
  let n = xs.length()
  if n == 0 {
    return -1
  }
  let mut lo = 0
  let mut hi = n
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    if cmp(xs[mid], target) <= 0 {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  lo
}

/// Generic binary search: returns Some(index) if found, None otherwise.
pub fn[T] binary_search_generic(
  xs : FixedArray[T],
  target : T,
  cmp : (T, T) -> Int,
) -> Int? {
  let n = xs.length()
  if n == 0 {
    return None
  }
  let mut lo = 0
  let mut hi = n - 1
  while lo <= hi {
    let mid = lo + (hi - lo) / 2
    let c = cmp(xs[mid], target)
    if c == 0 {
      return Some(mid)
    } else if c < 0 {
      lo = mid + 1
    } else {
      hi = mid - 1
    }
  }
  None
}

test "lower_bound: basic" {
  let xs = FixedArray::makei(5, fn(i) { i + 1 })  // [1,2,3,4,5]
  assert_eq(lower_bound(xs, 3, fn(a, b) { a - b }), 2)
  assert_eq(lower_bound(xs, 1, fn(a, b) { a - b }), 0)
  assert_eq(lower_bound(xs, 5, fn(a, b) { a - b }), 4)
  assert_eq(lower_bound(xs, 0, fn(a, b) { a - b }), 0)
  assert_eq(lower_bound(xs, 6, fn(a, b) { a - b }), 5)
}

test "lower_bound: with duplicates" {
  let xs = FixedArray::makei(8, fn(i) { i / 3 })  // [0,0,0,1,1,1,2,2]
  assert_eq(lower_bound(xs, 1, fn(a, b) { a - b }), 3)
  assert_eq(lower_bound(xs, 0, fn(a, b) { a - b }), 0)
  assert_eq(lower_bound(xs, 2, fn(a, b) { a - b }), 6)
}

test "upper_bound: basic" {
  let xs = FixedArray::makei(5, fn(i) { i + 1 })  // [1,2,3,4,5]
  assert_eq(upper_bound(xs, 3, fn(a, b) { a - b }), 3)
  assert_eq(upper_bound(xs, 5, fn(a, b) { a - b }), 5)
  assert_eq(upper_bound(xs, 0, fn(a, b) { a - b }), 0)
}

test "upper_bound: with duplicates" {
  let xs = FixedArray::makei(8, fn(i) { i / 3 })  // [0,0,0,1,1,1,2,2]
  assert_eq(upper_bound(xs, 1, fn(a, b) { a - b }), 6)
  assert_eq(upper_bound(xs, 0, fn(a, b) { a - b }), 3)
}

test "binary_search_generic: found" {
  let xs = FixedArray::makei(10, fn(i) { i })
  assert_true(binary_search_generic(xs, 5, fn(a, b) { a - b }) is Some(_))
  assert_eq(binary_search_generic(xs, 5, fn(a, b) { a - b }).unwrap(), 5)
}

test "binary_search_generic: not found" {
  let xs = FixedArray::makei(10, fn(i) { i })
  assert_true(binary_search_generic(xs, 20, fn(a, b) { a - b }) is None)
}

test "bound_search: empty array" {
  let xs = FixedArray::make(0, 0)
  assert_eq(lower_bound(xs, 5, fn(a, b) { a - b }), -1)
  assert_eq(upper_bound(xs, 5, fn(a, b) { a - b }), -1)
  assert_true(binary_search_generic(xs, 5, fn(a, b) { a - b }) is None)
}

test "bound_search: single element" {
  let xs = FixedArray::make(1, 5)
  assert_eq(lower_bound(xs, 5, fn(a, b) { a - b }), 0)
  assert_eq(lower_bound(xs, 3, fn(a, b) { a - b }), 0)
  assert_eq(lower_bound(xs, 7, fn(a, b) { a - b }), 1)
  assert_eq(upper_bound(xs, 5, fn(a, b) { a - b }), 1)
}

test "bound_search: all same elements" {
  let xs = FixedArray::make(5, 7)
  assert_eq(lower_bound(xs, 7, fn(a, b) { a - b }), 0)
  assert_eq(upper_bound(xs, 7, fn(a, b) { a - b }), 5)
  assert_eq(lower_bound(xs, 5, fn(a, b) { a - b }), 0)
  assert_eq(upper_bound(xs, 9, fn(a, b) { a - b }), 5)
}

test "bound_search: generic with String" {
  let words = FixedArray::make(4, "")
  words[0] = "apple"
  words[1] = "banana"
  words[2] = "cherry"
  words[3] = "date"
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
  assert_eq(lower_bound(words, "banana", str_cmp), 1)
  assert_eq(upper_bound(words, "banana", str_cmp), 2)
  assert_true(binary_search_generic(words, "date", str_cmp) is Some(_))
  assert_true(binary_search_generic(words, "grape", str_cmp) is None)
}

test "bound_search: reverse comparator" {
  let xs = FixedArray::makei(5, fn(i) { 5 - i })  // [5,4,3,2,1] "sorted" with reverse cmp
  // With reverse comparator, lower_bound finds first where xs[i] <= target
  assert_eq(lower_bound(xs, 3, fn(a, b) { b - a }), 2)
}
