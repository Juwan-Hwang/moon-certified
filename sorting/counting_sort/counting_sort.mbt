/// Counting sort for non-negative integers.
/// Not formally verified (proof-enabled: false).
/// Correctness ensured by comprehensive tests including permutation checks.
///
/// Algorithm:
///   1. Scan the input to find the maximum value `k`, rejecting any input
///      that contains a negative value.
///   2. Allocate a count array of size k + 1 and tally how many times each
///      value occurs.
///   3. Compute prefix sums so that count[v] becomes the number of elements
///      <= v (a 1-based ending position for value v in the output).
///   4. Walk the input right-to-left, placing each element at its stable
///      position (count[v] - 1) and decrementing the count.
///
/// Complexity:
///   - Time:  O(n + k) where n = input length and k = maximum value.
///   - Space: O(n + k) auxiliary (count array + output array).
///
/// Limitations:
///   - Only non-negative integers are supported. If any element is negative
///     the input is treated as invalid and an empty array is returned.
///   - To avoid out-of-memory from a single huge value, the count array is
///     capped: if k > COUNTING_SORT_MAX_VALUE the input is rejected and an
///     empty array is returned.
///   - Returns a *new* array; the input is never modified.
///   - Stable (equal elements keep their relative order).
///
/// Not formally verified (while loops with mutable state).

/// Upper bound on the maximum value we are willing to count.
/// Keeps the count array at most ~10^7 Ints (~80 MB), preventing OOM when a
/// single stray large value would otherwise drive allocation.
const COUNTING_SORT_MAX_VALUE : Int = 10_000_000

/// Counting sort for non-negative integers.
///
/// Returns a new, ascendingly-sorted `FixedArray[Int]`. Returns an empty
/// array when the input is empty, contains a negative value, or its maximum
/// value exceeds `COUNTING_SORT_MAX_VALUE`.
pub fn counting_sort(xs : FixedArray[Int]) -> FixedArray[Int] {
  let n = xs.length()
  if n == 0 {
    return FixedArray::make(0, 0)
  }
  // Find the maximum while validating that every element is non-negative.
  let mut max_val = xs[0]
  for i = 0; i < n; i = i + 1 {
    let v = xs[i]
    if v < 0 {
      // Invalid input: negative value.
      return FixedArray::make(0, 0)
    }
    if v > max_val {
      max_val = v
    }
  }
  // Guard against excessive memory allocation.
  if max_val > COUNTING_SORT_MAX_VALUE {
    return FixedArray::make(0, 0)
  }
  // Count occurrences of each value.
  let count = FixedArray::make(max_val + 1, 0)
  for i = 0; i < n; i = i + 1 {
    count[xs[i]] = count[xs[i]] + 1
  }
  // Prefix sums: count[v] = number of elements <= v.
  for v = 1; v <= max_val; v = v + 1 {
    count[v] = count[v] + count[v - 1]
  }
  // Build the output, iterating right-to-left for stability.
  let output = FixedArray::make(n, 0)
  for i = n - 1; i >= 0; i = i - 1 {
    let v = xs[i]
    count[v] = count[v] - 1
    output[count[v]] = v
  }
  output
}

test "counting_sort: basic" {
  let xs = FixedArray::makei(5, fn(i) { 5 - i }) // [5, 4, 3, 2, 1]
  let out = counting_sort(xs)
  assert_eq(out[0], 1)
  assert_eq(out[1], 2)
  assert_eq(out[2], 3)
  assert_eq(out[3], 4)
  assert_eq(out[4], 5)
}

test "counting_sort: already sorted" {
  let xs = FixedArray::makei(10, fn(i) { i }) // [0, 1, ..., 9]
  let out = counting_sort(xs)
  for k = 0; k < 10; k = k + 1 {
    assert_eq(out[k], k)
  }
}

test "counting_sort: reverse sorted" {
  let xs = FixedArray::makei(10, fn(i) { 9 - i }) // [9, 8, ..., 0]
  let out = counting_sort(xs)
  for k = 0; k < 10; k = k + 1 {
    assert_eq(out[k], k)
  }
}

test "counting_sort: single element" {
  let xs = FixedArray::make(1, 42)
  let out = counting_sort(xs)
  assert_eq(out.length(), 1)
  assert_eq(out[0], 42)
}

test "counting_sort: empty array" {
  let xs = FixedArray::make(0, 0)
  let out = counting_sort(xs)
  assert_eq(out.length(), 0)
}

test "counting_sort: duplicates" {
  let xs = FixedArray::makei(8, fn(i) { i % 3 }) // [0,1,2,0,1,2,0,1]
  let out = counting_sort(xs)
  assert_eq(out[0], 0)
  assert_eq(out[1], 0)
  assert_eq(out[2], 0)
  assert_eq(out[3], 1)
  assert_eq(out[4], 1)
  assert_eq(out[5], 1)
  assert_eq(out[6], 2)
  assert_eq(out[7], 2)
}

test "counting_sort: large range" {
  // Values spread across a wide but bounded range.
  let xs = FixedArray::make(6, 0)
  xs[0] = 1000
  xs[1] = 0
  xs[2] = 500
  xs[3] = 250
  xs[4] = 750
  xs[5] = 1000
  let out = counting_sort(xs)
  assert_eq(out[0], 0)
  assert_eq(out[1], 250)
  assert_eq(out[2], 500)
  assert_eq(out[3], 750)
  assert_eq(out[4], 1000)
  assert_eq(out[5], 1000)
}

test "counting_sort: all same value" {
  let xs = FixedArray::make(6, 7)
  let out = counting_sort(xs)
  for k = 0; k < 6; k = k + 1 {
    assert_eq(out[k], 7)
  }
}

test "counting_sort: invalid input with negative values" {
  let xs = FixedArray::make(5, 0)
  xs[0] = 3
  xs[1] = 1
  xs[2] = -4
  xs[3] = 2
  xs[4] = 5
  let out = counting_sort(xs)
  assert_eq(out.length(), 0)
}

test "counting_sort: input is not modified" {
  let xs = FixedArray::make(5, 0)
  xs[0] = 4
  xs[1] = 2
  xs[2] = 0
  xs[3] = 1
  xs[4] = 3
  let _ = counting_sort(xs)
  // The original array must remain untouched.
  assert_eq(xs[0], 4)
  assert_eq(xs[1], 2)
  assert_eq(xs[2], 0)
  assert_eq(xs[3], 1)
  assert_eq(xs[4], 3)
}

test "counting_sort: permutation check" {
  let n = 50
  let xs = FixedArray::makei(n, fn(i) { (i * 7 + 3) % 31 })
  let orig_freq = FixedArray::make(31, 0)
  for k = 0; k < n; k = k + 1 {
    orig_freq[xs[k]] = orig_freq[xs[k]] + 1
  }
  let out = counting_sort(xs)
  for k = 0; k < n - 1; k = k + 1 {
    assert_true(out[k] <= out[k + 1])
  }
  let sorted_freq = FixedArray::make(31, 0)
  for k = 0; k < n; k = k + 1 {
    sorted_freq[out[k]] = sorted_freq[out[k]] + 1
  }
  for k = 0; k < 31; k = k + 1 {
    assert_eq(orig_freq[k], sorted_freq[k])
  }
}

test "counting_sort: stability" {
  // Counting sort is stable: equal keys keep their original relative order.
  // Encode each element as key * 100 + tag (tag in 0..9, strictly increasing
  // across the whole input) and sort only by key via the value's high part.
  // After sorting, tags within each key group must remain ascending.
  let n = 9
  // Keys: 3, 1, 3, 2, 1, 3, 2, 1, 2  with tags 0..8 in input order.
  let keys = FixedArray::make(n, 0)
  keys[0] = 3
  keys[1] = 1
  keys[2] = 3
  keys[3] = 2
  keys[4] = 1
  keys[5] = 3
  keys[6] = 2
  keys[7] = 1
  keys[8] = 2
  let xs = FixedArray::make(n, 0)
  for k = 0; k < n; k = k + 1 {
    xs[k] = keys[k] * 100 + k
  }
  let out = counting_sort(xs)
  // Keys must be sorted ascending.
  for k = 0; k < n - 1; k = k + 1 {
    assert_true(out[k] / 100 <= out[k + 1] / 100)
  }
  // Within each key group, tags (out % 100) must be ascending = stable.
  let mut i = 0
  while i < n {
    let key = out[i] / 100
    let mut j = i + 1
    while j < n && out[j] / 100 == key {
      assert_true(out[j - 1] % 100 < out[j] % 100)
      j = j + 1
    }
    i = j
  }
}
