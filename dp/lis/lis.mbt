/// Longest Increasing Subsequence (LIS) on `FixedArray[Int]`.
///
/// Implements the classic O(n log n) patience-sorting / binary-search
/// algorithm. `tails[k]` stores the index (into `xs`) of the smallest tail
/// element of every increasing subsequence of length `k + 1` discovered so far.
/// For each input element we binary-search the `tails` array to find where it
/// belongs, keeping `tails` sorted by value. The final length of the longest
/// strictly-increasing subsequence is the number of filled `tails` slots.
///
/// `lis_sequence` additionally records, for every element, the index of its
/// predecessor in the best subsequence ending at that element, then walks the
/// chain back from the optimal tail to reconstruct one actual LIS.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

/// Length of the longest strictly-increasing subsequence of `xs`.
///
/// Returns 0 for an empty array. Runs in O(n log n) time, O(n) space.
pub fn lis_length(xs : FixedArray[Int]) -> Int {
  let n = xs.length()
  if n == 0 {
    return 0
  }
  // tails[k] = index into xs of the smallest tail of an IS of length k+1.
  let tails = FixedArray::make(n, 0)
  let mut len = 0
  for i = 0; i < n; i = i + 1 {
    let x = xs[i]
    // Binary search: first slot k in [0, len) whose tail value is >= x.
    // Strictly-increasing means equal values replace (they do not extend).
    let mut lo = 0
    let mut hi = len
    while lo < hi {
      let mid = (lo + hi) / 2
      if xs[tails[mid]] < x {
        lo = mid + 1
      } else {
        hi = mid
      }
    }
    tails[lo] = i
    if lo == len {
      len = len + 1
    }
  }
  len
}

/// Reconstruct one longest strictly-increasing subsequence of `xs`.
///
/// Returns the values (not indices) of an actual LIS, in increasing order.
/// Empty input yields an empty array. Runs in O(n log n) time, O(n) space.
pub fn lis_sequence(xs : FixedArray[Int]) -> FixedArray[Int] {
  let n = xs.length()
  if n == 0 {
    return FixedArray::make(0, 0)
  }
  let tails = FixedArray::make(n, 0)
  // prev[i] = predecessor index of xs[i] in the best IS ending at i (-1 = root).
  let prev = FixedArray::make(n, -1)
  let mut len = 0
  for i = 0; i < n; i = i + 1 {
    let x = xs[i]
    let mut lo = 0
    let mut hi = len
    while lo < hi {
      let mid = (lo + hi) / 2
      if xs[tails[mid]] < x {
        lo = mid + 1
      } else {
        hi = mid
      }
    }
    if lo > 0 {
      prev[i] = tails[lo - 1]
    }
    tails[lo] = i
    if lo == len {
      len = len + 1
    }
  }
  // Walk the predecessor chain back from the optimal tail.
  let result = FixedArray::make(len, 0)
  let mut k = tails[len - 1]
  let mut j = len - 1
  while j >= 0 {
    result[j] = xs[k]
    k = prev[k]
    j = j - 1
  }
  result
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

/// Check that `seq` is a strictly-increasing subsequence of `xs`.
fn is_valid_subsequence(xs : FixedArray[Int], seq : FixedArray[Int]) -> Bool {
  let n = xs.length()
  let m = seq.length()
  if m == 0 {
    return n == 0
  }
  for i = 1; i < m; i = i + 1 {
    if seq[i] <= seq[i - 1] {
      return false
    }
  }
  let mut j = 0
  for i = 0; i < n; i = i + 1 {
    if j < m && xs[i] == seq[j] {
      j = j + 1
    }
  }
  j == m
}

test "lis_length: basic" {
  // [10,9,2,5,3,7,101,18] -> LIS length 4 ([2,3,7,101] or [2,5,7,101]).
  let xs = FixedArray::make(8, 0)
  xs[0] = 10
  xs[1] = 9
  xs[2] = 2
  xs[3] = 5
  xs[4] = 3
  xs[5] = 7
  xs[6] = 101
  xs[7] = 18
  assert_eq(lis_length(xs), 4)
}

test "lis_length: empty" {
  let xs = FixedArray::make(0, 0)
  assert_eq(lis_length(xs), 0)
}

test "lis_length: single element" {
  let xs = FixedArray::make(1, 0)
  xs[0] = 42
  assert_eq(lis_length(xs), 1)
}

test "lis_length: all increasing" {
  let xs = FixedArray::makei(5, fn(i) { i + 1 }) // [1,2,3,4,5]
  assert_eq(lis_length(xs), 5)
}

test "lis_length: all decreasing" {
  let xs = FixedArray::makei(5, fn(i) { 5 - i }) // [5,4,3,2,1]
  assert_eq(lis_length(xs), 1)
}

test "lis_length: all equal" {
  let xs = FixedArray::make(4, 7) // [7,7,7,7]
  assert_eq(lis_length(xs), 1)
}

test "lis_length: with duplicates" {
  // [1,3,3,2] -> strictly-increasing LIS length 2 ([1,3] or [1,2]).
  let xs = FixedArray::make(4, 0)
  xs[0] = 1
  xs[1] = 3
  xs[2] = 3
  xs[3] = 2
  assert_eq(lis_length(xs), 2)
}

test "lis_length: large random 100 elements" {
  let xs = FixedArray::makei(100, fn(i) { (i * 37 + 11) % 97 })
  let l = lis_length(xs)
  assert_true(l >= 1)
  assert_true(l <= 100)
}

test "lis_sequence: basic reconstruction" {
  let xs = FixedArray::make(8, 0)
  xs[0] = 10
  xs[1] = 9
  xs[2] = 2
  xs[3] = 5
  xs[4] = 3
  xs[5] = 7
  xs[6] = 101
  xs[7] = 18
  let seq = lis_sequence(xs)
  assert_eq(seq.length(), 4)
  assert_true(is_valid_subsequence(xs, seq))
}

test "lis_sequence: empty returns empty" {
  let xs = FixedArray::make(0, 0)
  let seq = lis_sequence(xs)
  assert_eq(seq.length(), 0)
}

test "lis_sequence: single element" {
  let xs = FixedArray::make(1, 0)
  xs[0] = 42
  let seq = lis_sequence(xs)
  assert_eq(seq.length(), 1)
  assert_eq(seq[0], 42)
  assert_true(is_valid_subsequence(xs, seq))
}

test "lis_sequence: all increasing" {
  let xs = FixedArray::makei(5, fn(i) { i + 1 })
  let seq = lis_sequence(xs)
  assert_eq(seq.length(), 5)
  assert_true(is_valid_subsequence(xs, seq))
}

test "lis_sequence: all equal" {
  let xs = FixedArray::make(4, 7)
  let seq = lis_sequence(xs)
  assert_eq(seq.length(), 1)
  assert_true(is_valid_subsequence(xs, seq))
}

test "lis_sequence: length matches lis_length" {
  let xs = FixedArray::makei(100, fn(i) { (i * 37 + 11) % 97 })
  let seq = lis_sequence(xs)
  assert_eq(seq.length(), lis_length(xs))
  assert_true(is_valid_subsequence(xs, seq))
}
