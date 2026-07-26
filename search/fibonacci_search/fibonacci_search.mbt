/// Fibonacci Search — O(log n) search on sorted arrays.
///
/// Uses Fibonacci numbers to divide the search space, avoiding the
/// division operator. Useful on architectures where division is
/// expensive. Works on sorted arrays.
///
/// ## Complexity
/// - Time:  O(log n).
/// - Space: O(1).
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

///|
/// Find the index of `target` in a sorted array.
/// Returns `Some(index)` if found, `None` otherwise.
pub fn fibonacci_search(arr : Array[Int], target : Int) -> Int? {
  let n = arr.length()
  if n == 0 {
    return None
  }
  // Find the smallest Fibonacci number >= n.
  let mut fib_m2 = 0 // (m-2)'th Fibonacci
  let mut fib_m1 = 1 // (m-1)'th Fibonacci
  let mut fib = 1 // m'th Fibonacci
  while fib < n {
    fib_m2 = fib_m1
    fib_m1 = fib
    fib = fib_m1 + fib_m2
  }
  // Marks the eliminated range.
  let mut offset = -1
  while fib > 1 {
    // Check if fib_m2 is a valid index.
    let i = if offset + fib_m2 < n - 1 { offset + fib_m2 } else { n - 1 }
    if arr[i] < target {
      fib = fib_m1
      fib_m1 = fib_m2
      fib_m2 = fib - fib_m1
      offset = i
    } else if arr[i] > target {
      fib = fib_m2
      fib_m1 = fib_m1 - fib_m2
      fib_m2 = fib - fib_m1
    } else {
      return Some(i)
    }
  }
  // Compare the last element.
  if fib_m1 == 1 && offset + 1 < n && arr[offset + 1] == target {
    return Some(offset + 1)
  }
  None
}

///|
/// Find the first index where `target` could be inserted (lower bound).
pub fn fibonacci_lower_bound(arr : Array[Int], target : Int) -> Int {
  let n = arr.length()
  if n == 0 {
    return 0
  }
  let mut fib_m2 = 0
  let mut fib_m1 = 1
  let mut fib = 1
  while fib < n {
    fib_m2 = fib_m1
    fib_m1 = fib
    fib = fib_m1 + fib_m2
  }
  let mut offset = -1
  while fib > 1 {
    let i = if offset + fib_m2 < n - 1 { offset + fib_m2 } else { n - 1 }
    if arr[i] < target {
      fib = fib_m1
      fib_m1 = fib_m2
      fib_m2 = fib - fib_m1
      offset = i
    } else {
      fib = fib_m2
      fib_m1 = fib_m1 - fib_m2
      fib_m2 = fib - fib_m1
    }
  }
  // Final check.
  let pos = offset + 1
  if pos < n && arr[pos] >= target {
    return pos
  }
  n
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "fibonacci_search: found" {
  let arr = [10, 22, 35, 40, 50, 60, 70, 80, 90, 100]
  assert_eq(fibonacci_search(arr, 10), Some(0))
  assert_eq(fibonacci_search(arr, 100), Some(9))
  assert_eq(fibonacci_search(arr, 50), Some(4))
  assert_eq(fibonacci_search(arr, 35), Some(2))
}

///|
test "fibonacci_search: not found" {
  let arr = [1, 3, 5, 7, 9]
  assert_eq(fibonacci_search(arr, 0), None)
  assert_eq(fibonacci_search(arr, 4), None)
  assert_eq(fibonacci_search(arr, 10), None)
}

///|
test "fibonacci_search: empty" {
  let arr : Array[Int] = []
  assert_eq(fibonacci_search(arr, 5), None)
}

///|
test "fibonacci_search: single element" {
  assert_eq(fibonacci_search([5], 5), Some(0))
  assert_eq(fibonacci_search([5], 3), None)
}

///|
test "fibonacci_search: duplicates" {
  let arr = [1, 2, 2, 2, 3, 4, 4, 5]
  let result = fibonacci_search(arr, 2)
  match result {
    Some(i) => assert_eq(arr[i], 2)
    None => assert_true(false)
  }
}

///|
test "fibonacci_search: lower_bound" {
  let arr = [1, 3, 5, 7, 9, 11]
  assert_eq(fibonacci_lower_bound(arr, 5), 2)
  assert_eq(fibonacci_lower_bound(arr, 4), 2)
  assert_eq(fibonacci_lower_bound(arr, 0), 0)
  assert_eq(fibonacci_lower_bound(arr, 12), 6)
}

///|
test "fibonacci_search: large array" {
  let arr : Array[Int] = []
  for i = 0; i < 1000; i = i + 1 {
    arr.push(i * 2)
  }
  assert_eq(fibonacci_search(arr, 500), Some(250))
  assert_eq(fibonacci_search(arr, 501), None)
}
