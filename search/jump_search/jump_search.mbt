/// Jump Search (Block Search) — O(√n) search on sorted arrays.
///
/// Jumps ahead by √n steps to find the block containing the target,
/// then performs a linear search within that block. Stable: finds the
/// first occurrence of duplicates.
///
/// ## Complexity
/// - Time:  O(√n).
/// - Space: O(1).
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

/// Find the first occurrence of `target` in a sorted array.
/// Returns `Some(index)` if found, `None` otherwise.
pub fn jump_search(arr : Array[Int], target : Int) -> Int? {
  let n = arr.length()
  if n == 0 {
    return None
  }
  let step = isqrt(n)
  // Jump ahead to find the block.
  let mut prev = 0
  let mut curr = step
  while curr < n && arr[curr] < target {
    prev = curr
    curr = curr + step
  }
  // Linear search within [prev, min(curr+1, n)) — include curr.
  let end = if curr < n { curr + 1 } else { n }
  for i = prev; i < end; i = i + 1 {
    if arr[i] == target {
      return Some(i)
    }
    if arr[i] > target {
      return None
    }
  }
  None
}

/// Integer square root (floor).
fn isqrt(n : Int) -> Int {
  if n <= 0 {
    return 0
  }
  let mut x = n
  let mut y = (x + 1) / 2
  while y < x {
    x = y
    y = (x + n / x) / 2
  }
  x
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "jump_search: found" {
  let arr = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
  for i = 0; i < 10; i = i + 1 {
    assert_eq(jump_search(arr, i), Some(i))
  }
}

test "jump_search: not found" {
  let arr = [1, 3, 5, 7, 9]
  assert_eq(jump_search(arr, 0), None)
  assert_eq(jump_search(arr, 4), None)
  assert_eq(jump_search(arr, 10), None)
}

test "jump_search: empty" {
  let arr : Array[Int] = []
  assert_eq(jump_search(arr, 5), None)
}

test "jump_search: single" {
  assert_eq(jump_search([5], 5), Some(0))
  assert_eq(jump_search([5], 3), None)
}

test "jump_search: duplicates finds first" {
  let arr = [1, 2, 2, 2, 3, 4, 4, 5]
  assert_eq(jump_search(arr, 2), Some(1))
  assert_eq(jump_search(arr, 4), Some(5))
}

test "jump_search: large array" {
  let arr : Array[Int] = []
  for i = 0; i < 1000; i = i + 1 {
    arr.push(i * 2)
  }
  assert_eq(jump_search(arr, 500), Some(250))
  assert_eq(jump_search(arr, 501), None)
}
