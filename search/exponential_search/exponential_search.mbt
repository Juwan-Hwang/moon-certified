/// Exponential search (a.k.a. galloping search) on a sorted array.
///
/// Exponential search first locates a range that must contain the target by
/// repeatedly doubling an index bound (1, 2, 4, 8, ...), then performs an
/// ordinary binary search within that bounded range. Because the range-finding
/// phase probes only O(log i) elements (where i is the target's index), the
/// method is especially effective on unbounded or very large arrays where the
/// target lies near the front.
///
/// Complexity: O(log n) overall -- O(log i) to find the range plus O(log i) to
/// binary search it, bounded by O(log n) since i <= n.
///
/// Limitations:
///   - The array MUST be sorted in ascending order; otherwise behavior is
///     undefined.
///   - Targets before the first element return `None` after a single gallop
///     step and a binary search of the head.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

/// Exponential search on a sorted `FixedArray[Int]`.
///
/// Returns `Some(index)` if `target` is present, otherwise `None`.
pub fn exponential_search(arr : FixedArray[Int], target : Int) -> Int? {
  let n = arr.length()
  if n == 0 {
    return None
  }
  if arr[0] == target {
    return Some(0)
  }
  // Gallop: double the bound until we overshoot the array end or reach an
  // element >= target. After the loop, the target -- if present -- must lie
  // in the index interval (bound/2, hi] (closed on both ends below).
  let mut bound = 1
  while bound < n && arr[bound] < target {
    bound = bound * 2
  }
  // The candidate range is [bound/2, min(bound, n-1)]. `bound/2` is the last
  // index known to hold a value < target (or 0 on the first iteration), and
  // `hi` is the first index at/after which values are >= target (or the final
  // element when the gallop ran past the array end).
  let lo = bound / 2
  let hi = if bound < n { bound } else { n - 1 }
  // Binary search within the identified range [lo, hi].
  let mut left = lo
  let mut right = hi
  while left <= right {
    let mid = left + (right - left) / 2
    if arr[mid] == target {
      return Some(mid)
    } else if arr[mid] < target {
      left = mid + 1
    } else {
      right = mid - 1
    }
  }
  None
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "exponential_search: basic" {
  let xs = FixedArray::makei(9, fn(i) { i }) // [0,1,2,3,4,5,6,7,8]
  assert_eq(exponential_search(xs, 5), Some(5))
  assert_eq(exponential_search(xs, 3), Some(3))
}

test "exponential_search: first element" {
  let xs = FixedArray::makei(10, fn(i) { i * 3 }) // [0,3,6,...,27]
  assert_eq(exponential_search(xs, 0), Some(0))
}

test "exponential_search: last element" {
  let xs = FixedArray::makei(10, fn(i) { i * 3 }) // [0,3,6,...,27]
  assert_eq(exponential_search(xs, 27), Some(9))
}

test "exponential_search: middle element" {
  let xs = FixedArray::makei(11, fn(i) { i }) // [0..10]
  assert_eq(exponential_search(xs, 5), Some(5))
}

test "exponential_search: not found" {
  let xs = FixedArray::makei(5, fn(i) { i * 2 }) // [0,2,4,6,8]
  assert_eq(exponential_search(xs, 1), None)
  assert_eq(exponential_search(xs, 5), None)
  assert_eq(exponential_search(xs, 7), None)
}

test "exponential_search: single element" {
  let xs = FixedArray::make(1, 42)
  assert_eq(exponential_search(xs, 42), Some(0))
  assert_eq(exponential_search(xs, 41), None)
  assert_eq(exponential_search(xs, 43), None)
}

test "exponential_search: empty array" {
  let xs : FixedArray[Int] = FixedArray::make(0, 0)
  assert_eq(exponential_search(xs, 42), None)
}

test "exponential_search: large array" {
  let xs = FixedArray::makei(2000, fn(i) { i }) // [0..1999]
  assert_eq(exponential_search(xs, 0), Some(0))
  assert_eq(exponential_search(xs, 1), Some(1))
  assert_eq(exponential_search(xs, 1024), Some(1024))
  assert_eq(exponential_search(xs, 1999), Some(1999))
  assert_eq(exponential_search(xs, 2000), None)
}

test "exponential_search: target beyond last element" {
  let xs = FixedArray::makei(8, fn(i) { i * 2 }) // [0,2,4,...,14]
  assert_eq(exponential_search(xs, 100), None)
  assert_eq(exponential_search(xs, 15), None)
}

test "exponential_search: target before first element" {
  let xs = FixedArray::makei(8, fn(i) { i + 10 }) // [10,11,...,17]
  assert_eq(exponential_search(xs, 5), None)
  assert_eq(exponential_search(xs, 9), None)
}

test "exponential_search: duplicates" {
  // [1,1,1,2,2,2,3,3] -- any matching index is acceptable.
  let xs = FixedArray::makei(8, fn(i) { i / 3 + 1 })
  let r = exponential_search(xs, 2)
  match r {
    Some(idx) => assert_eq(xs[idx], 2)
    None => abort("should find 2")
  }
}
