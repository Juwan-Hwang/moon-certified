/// Interpolation search on a sorted array of integers.
///
/// Interpolation search estimates the position of `target` by linear
/// interpolation, assuming the data is sorted and approximately uniformly
/// distributed. Where binary search always probes the midpoint, this method
/// probes the position proportional to where `target` falls between the
/// current range endpoints:
///
///     pos = lo + (target - arr[lo]) * (hi - lo) / (arr[hi] - arr[lo])
///
/// Complexity:
///   - Average: O(log log n) for uniformly distributed data.
///   - Worst case: O(n) for highly non-uniform data (e.g. exponential).
///
/// Limitations:
///   - The array MUST be sorted in ascending order; otherwise behavior is
///     undefined.
///   - Performance degrades toward linear for non-uniform distributions, but
///     the result remains correct.
///   - The interpolated probe is computed with Int64 arithmetic to avoid
///     overflow of `(target - arr[lo]) * (hi - lo)` for large arrays or large
///     values; this does not change the result, it only prevents wraparound.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

///|
/// Interpolation search on a sorted `FixedArray[Int]`.
///
/// Returns `Some(index)` if `target` is present, otherwise `None`.
/// Assumes the array is sorted in ascending order and the values are
/// approximately uniformly distributed for the advertised complexity.
pub fn interpolation_search(arr : FixedArray[Int], target : Int) -> Int? {
  let n = arr.length()
  if n == 0 {
    return None
  }
  let mut lo = 0
  let mut hi = n - 1
  // The search window is restricted to the value range [arr[lo], arr[hi]].
  // The loop guard also rejects targets outside that range, which cannot be
  // present in a sorted array, so they immediately fall through to `None`.
  while lo <= hi && target >= arr[lo] && target <= arr[hi] {
    // When the endpoints are equal, every element in the range is identical.
    // Division by `(arr[hi] - arr[lo])` would be zero; the loop guard already
    // guarantees `target == arr[lo]` here, so report a hit.
    if arr[lo] == arr[hi] {
      return Some(lo)
    }
    // Interpolated probe. Convert to Int64 BEFORE subtracting to prevent
    // Int32 overflow when arr[hi] and arr[lo] span a wide range (e.g.
    // [-2147483648, ..., 2147483647]). The subtraction itself is the
    // overflow risk, not the subsequent multiplication.
    let arr_hi_i64 = arr[hi].to_int64()
    let arr_lo_i64 = arr[lo].to_int64()
    let target_i64 = target.to_int64()
    let range = arr_hi_i64 - arr_lo_i64
    let numer = (target_i64 - arr_lo_i64) * (hi - lo).to_int64()
    let pos = lo + (numer / range).to_int()
    if arr[pos] == target {
      return Some(pos)
    } else if arr[pos] < target {
      lo = pos + 1
    } else {
      hi = pos - 1
    }
  }
  None
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "interpolation_search: basic" {
  let xs = FixedArray::makei(9, fn(i) { i }) // [0,1,2,3,4,5,6,7,8]
  assert_eq(interpolation_search(xs, 5), Some(5))
  assert_eq(interpolation_search(xs, 3), Some(3))
}

///|
test "interpolation_search: first element" {
  let xs = FixedArray::makei(10, fn(i) { i * 3 }) // [0,3,6,...,27]
  assert_eq(interpolation_search(xs, 0), Some(0))
}

///|
test "interpolation_search: last element" {
  let xs = FixedArray::makei(10, fn(i) { i * 3 }) // [0,3,6,...,27]
  assert_eq(interpolation_search(xs, 27), Some(9))
}

///|
test "interpolation_search: middle element" {
  let xs = FixedArray::makei(11, fn(i) { i }) // [0..10]
  assert_eq(interpolation_search(xs, 5), Some(5))
}

///|
test "interpolation_search: not found" {
  let xs = FixedArray::makei(5, fn(i) { i * 2 }) // [0,2,4,6,8]
  assert_eq(interpolation_search(xs, 1), None)
  assert_eq(interpolation_search(xs, 5), None)
  assert_eq(interpolation_search(xs, 9), None)
}

///|
test "interpolation_search: single element" {
  let xs = FixedArray::make(1, 42)
  assert_eq(interpolation_search(xs, 42), Some(0))
  assert_eq(interpolation_search(xs, 41), None)
  assert_eq(interpolation_search(xs, 43), None)
}

///|
test "interpolation_search: empty array" {
  let xs : FixedArray[Int] = FixedArray::make(0, 0)
  assert_eq(interpolation_search(xs, 42), None)
}

///|
test "interpolation_search: all same values" {
  let xs = FixedArray::make(6, 7) // [7,7,7,7,7,7]
  // Target present: some valid index is returned.
  let found = interpolation_search(xs, 7)
  match found {
    Some(idx) => assert_eq(xs[idx], 7)
    None => abort("should find 7")
  }
  // Targets outside the uniform value are absent.
  assert_eq(interpolation_search(xs, 6), None)
  assert_eq(interpolation_search(xs, 8), None)
}

///|
test "interpolation_search: large uniform array" {
  let xs = FixedArray::makei(1000, fn(i) { i * 2 }) // [0,2,4,...,1998]
  assert_eq(interpolation_search(xs, 0), Some(0))
  assert_eq(interpolation_search(xs, 1000), Some(500))
  assert_eq(interpolation_search(xs, 1998), Some(999))
  // Odd values are absent from this even-only array.
  assert_eq(interpolation_search(xs, 999), None)
  // Beyond the range.
  assert_eq(interpolation_search(xs, 2000), None)
  assert_eq(interpolation_search(xs, -1), None)
}

///|
test "interpolation_search: non-uniform array" {
  // Exponential growth: worst-case distribution, but the result must still be
  // correct even though complexity degrades toward O(n).
  let xs = FixedArray::makei(8, fn(i) {
    1 << i // [1,2,4,8,16,32,64,128]
  })
  assert_eq(interpolation_search(xs, 1), Some(0))
  assert_eq(interpolation_search(xs, 32), Some(5))
  assert_eq(interpolation_search(xs, 64), Some(6))
  assert_eq(interpolation_search(xs, 128), Some(7))
  assert_eq(interpolation_search(xs, 10), None)
  assert_eq(interpolation_search(xs, 200), None)
}

///|
test "interpolation_search: negative values" {
  let xs = FixedArray::makei(7, fn(i) { i - 3 }) // [-3,-2,-1,0,1,2,3]
  assert_eq(interpolation_search(xs, -3), Some(0))
  assert_eq(interpolation_search(xs, 0), Some(3))
  assert_eq(interpolation_search(xs, 3), Some(6))
  assert_eq(interpolation_search(xs, -4), None)
  assert_eq(interpolation_search(xs, 4), None)
}

///|
test "interpolation_search: wide value range (Int32 overflow regression)" {
  // Array spanning nearly the full Int32 range. The subtraction
  // arr[hi] - arr[lo] = 2147483646 - (-2147483648) = 4294967294 which
  // overflows Int32 but fits in Int64. This test verifies the fix.
  let xs : FixedArray[Int] = FixedArray::make(4, 0)
  xs[0] = -2147483648
  xs[1] = -715827882
  xs[2] = 715827883
  xs[3] = 2147483647
  assert_eq(interpolation_search(xs, -2147483648), Some(0))
  assert_eq(interpolation_search(xs, 2147483647), Some(3))
  assert_eq(interpolation_search(xs, -715827882), Some(1))
  assert_eq(interpolation_search(xs, 715827883), Some(2))
  assert_eq(interpolation_search(xs, 0), None)
}
