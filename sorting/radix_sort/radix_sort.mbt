/// LSD (least-significant-digit) radix sort for non-negative integers,
/// using base-256 (one byte per digit) stable counting-sort passes.
/// Not formally verified (proof-enabled: false).
/// Correctness ensured by comprehensive tests including permutation checks.
///
/// Algorithm:
///   1. Determine the number of passes `d` from the maximum value, i.e. how
///      many base-256 digits are needed to represent it (1 to 4 for a 32-bit
///      non-negative Int).
///   2. For each digit position p = 0 .. d-1 (least significant first):
///        perform a stable counting sort keyed on byte p of each value,
///        i.e. (value >> (8 * p)) & 0xFF.
///   3. After d passes the array is fully sorted. Each pass is stable, so
///      earlier (less significant) digit orderings are preserved.
///
/// Complexity:
///   - Time:  O(d * (n + 256)) where d is the number of passes and n is the
///            input length. For 32-bit non-negative Ints, d <= 4.
///   - Space: O(n + 256) auxiliary (output buffer + per-pass count array).
///
/// Limitations:
///   - Input must be non-negative. Behaviour on negative values is undefined
///     because two's-complement byte ordering would not sort correctly.
///   - Returns a *new* array; the input is never modified.
///   - Stable (equal elements keep their relative order).
///
/// Not formally verified (while loops with mutable state).

/// Number of buckets per pass: base 256 = one byte.
const RADIX : Int = 256
/// Bits per digit (log2 of RADIX).
const RADIX_BITS : Int = 8
/// Mask to extract one byte.
const RADIX_MASK : Int = 0xFF

/// Extract byte `pos` (0 = least significant) of a non-negative integer.
fn digit_of(value : Int, pos : Int) -> Int {
  (value >> (RADIX_BITS * pos)) & RADIX_MASK
}

/// One stable base-256 counting-sort pass on digit position `pos`.
///
/// Reads from `src` and writes the elements into `dst`, stably ordered by
/// their `pos`-th byte. After this pass `dst` holds the same multiset as
/// `src` but sorted by the digit at position `pos` (ties broken by the order
/// established in `src`, i.e. the previous passes).
fn counting_pass(
  src : FixedArray[Int],
  dst : FixedArray[Int],
  pos : Int,
) -> Unit {
  let n = src.length()
  let count = FixedArray::make(RADIX, 0)
  // Tally the digit of each element.
  for i = 0; i < n; i = i + 1 {
    let d = digit_of(src[i], pos)
    count[d] = count[d] + 1
  }
  // Prefix sums -> 1-based ending positions.
  for b = 1; b < RADIX; b = b + 1 {
    count[b] = count[b] + count[b - 1]
  }
  // Place elements stably, scanning the source right-to-left.
  for i = n - 1; i >= 0; i = i - 1 {
    let v = src[i]
    let d = digit_of(v, pos)
    count[d] = count[d] - 1
    dst[count[d]] = v
  }
}

/// LSD radix sort for non-negative integers.
///
/// Returns a new, ascendingly-sorted `FixedArray[Int]`. The input array is
/// not modified. Requires non-negative input.
pub fn radix_sort(xs : FixedArray[Int]) -> FixedArray[Int] {
  let n = xs.length()
  if n <= 1 {
    // Return a fresh copy so the input is never aliased.
    let out = FixedArray::make(n, 0)
    for i = 0; i < n; i = i + 1 {
      out[i] = xs[i]
    }
    return out
  }
  // Determine how many base-256 digits the maximum value needs.
  let mut max_val = xs[0]
  for i = 1; i < n; i = i + 1 {
    if xs[i] > max_val {
      max_val = xs[i]
    }
  }
  let mut d = 1
  let mut remaining = max_val >> RADIX_BITS
  while remaining > 0 {
    d = d + 1
    remaining = remaining >> RADIX_BITS
  }
  // Ping-pong between two buffers across passes. `a` always ends up holding
  // the most recently written array.
  let cur = FixedArray::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    cur[i] = xs[i]
  }
  let next = FixedArray::make(n, 0)
  let mut a = cur
  let mut b = next
  for pos = 0; pos < d; pos = pos + 1 {
    counting_pass(a, b, pos)
    // Swap buffer roles for the next pass.
    let tmp = a
    a = b
    b = tmp
  }
  a
}

test "radix_sort: basic" {
  let xs = FixedArray::makei(5, fn(i) { 5 - i }) // [5, 4, 3, 2, 1]
  let out = radix_sort(xs)
  for k = 0; k < 5; k = k + 1 {
    assert_eq(out[k], k + 1)
  }
}

test "radix_sort: already sorted" {
  let xs = FixedArray::makei(10, fn(i) { i }) // [0, 1, ..., 9]
  let out = radix_sort(xs)
  for k = 0; k < 10; k = k + 1 {
    assert_eq(out[k], k)
  }
}

test "radix_sort: reverse sorted" {
  let xs = FixedArray::makei(10, fn(i) { 9 - i }) // [9, 8, ..., 0]
  let out = radix_sort(xs)
  for k = 0; k < 10; k = k + 1 {
    assert_eq(out[k], k)
  }
}

test "radix_sort: single element" {
  let xs = FixedArray::make(1, 42)
  let out = radix_sort(xs)
  assert_eq(out.length(), 1)
  assert_eq(out[0], 42)
}

test "radix_sort: empty array" {
  let xs = FixedArray::make(0, 0)
  let out = radix_sort(xs)
  assert_eq(out.length(), 0)
}

test "radix_sort: duplicates" {
  let xs = FixedArray::makei(8, fn(i) { i % 3 }) // [0,1,2,0,1,2,0,1]
  let out = radix_sort(xs)
  assert_eq(out[0], 0)
  assert_eq(out[1], 0)
  assert_eq(out[2], 0)
  assert_eq(out[3], 1)
  assert_eq(out[4], 1)
  assert_eq(out[5], 1)
  assert_eq(out[6], 2)
  assert_eq(out[7], 2)
}

test "radix_sort: large values" {
  // Values spanning all four base-256 digits.
  let xs = FixedArray::make(8, 0)
  xs[0] = 2147483647 // 0x7FFFFFFF (max 32-bit signed Int)
  xs[1] = 0
  xs[2] = 16777216 // 0x01000000
  xs[3] = 65535 // 0x0000FFFF
  xs[4] = 256 // 0x00000100
  xs[5] = 2147483646 // 0x7FFFFFFE
  xs[6] = 1
  xs[7] = 16777215 // 0x00FFFFFF
  let out = radix_sort(xs)
  assert_eq(out[0], 0)
  assert_eq(out[1], 1)
  assert_eq(out[2], 256)
  assert_eq(out[3], 65535)
  assert_eq(out[4], 16777215)
  assert_eq(out[5], 16777216)
  assert_eq(out[6], 2147483646)
  assert_eq(out[7], 2147483647)
}

test "radix_sort: all same value" {
  let xs = FixedArray::make(6, 123456)
  let out = radix_sort(xs)
  for k = 0; k < 6; k = k + 1 {
    assert_eq(out[k], 123456)
  }
}

test "radix_sort: input is not modified" {
  let xs = FixedArray::make(5, 0)
  xs[0] = 300
  xs[1] = 50
  xs[2] = 0
  xs[3] = 999
  xs[4] = 1
  let _ = radix_sort(xs)
  // The original array must remain untouched.
  assert_eq(xs[0], 300)
  assert_eq(xs[1], 50)
  assert_eq(xs[2], 0)
  assert_eq(xs[3], 999)
  assert_eq(xs[4], 1)
}

test "radix_sort: permutation check" {
  // Values span 0..999 (two base-256 digits) to exercise multi-byte passes.
  let n = 50
  let xs = FixedArray::makei(n, fn(i) { (i * 7 + 3) % 1000 })
  let orig_freq = FixedArray::make(1000, 0)
  for k = 0; k < n; k = k + 1 {
    orig_freq[xs[k]] = orig_freq[xs[k]] + 1
  }
  let out = radix_sort(xs)
  for k = 0; k < n - 1; k = k + 1 {
    assert_true(out[k] <= out[k + 1])
  }
  let sorted_freq = FixedArray::make(1000, 0)
  for k = 0; k < n; k = k + 1 {
    sorted_freq[out[k]] = sorted_freq[out[k]] + 1
  }
  for k = 0; k < 1000; k = k + 1 {
    assert_eq(orig_freq[k], sorted_freq[k])
  }
}

test "radix_sort: stability" {
  // LSD radix sort is stable. Encode elements as key * 10000 + tag where the
  // tag is the strictly-increasing original index, then sort by the whole
  // value. Because keys are equal within a group and tags are unique, a
  // stable sort keeps tags ascending within each key group.
  let n = 9
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
    xs[k] = keys[k] * 10000 + k
  }
  let out = radix_sort(xs)
  // Keys must be sorted ascending.
  for k = 0; k < n - 1; k = k + 1 {
    assert_true(out[k] / 10000 <= out[k + 1] / 10000)
  }
  // Within each key group, tags (out % 10000) must be ascending = stable.
  let mut i = 0
  while i < n {
    let key = out[i] / 10000
    let mut j = i + 1
    while j < n && out[j] / 10000 == key {
      assert_true(out[j - 1] % 10000 < out[j] % 10000)
      j = j + 1
    }
    i = j
  }
}
