/// Monotone-queue DP -- sliding window maximum and fixed-length max-sum.
///
/// A monotone deque maintains indices whose corresponding values are in
/// decreasing order. Each element is pushed and popped at most once, so
/// the amortized cost per element is O(1).
///
/// ## Complexity
/// - `sliding_window_max`: O(n) time, O(n) space.
/// - `max_sum_subarray`:   O(n) time, O(1) space.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

///|
/// Maximum of every contiguous window of size `k`.
///
/// Returns an empty array for invalid inputs (`k <= 0`, `k > n`, or `n == 0`).
pub fn sliding_window_max(arr : Array[Int], k : Int) -> Array[Int] {
  let n = arr.length()
  if n == 0 || k <= 0 || k > n {
    return []
  }
  let result : Array[Int] = []
  // Deque of indices with decreasing values (front = current max).
  let deque = FixedArray::make(n, 0)
  let mut head = 0
  let mut tail = 0 // exclusive end
  for i = 0; i < n; i = i + 1 {
    // Evict from the back any index whose value is <= arr[i].
    while tail > head && arr[deque[tail - 1]] <= arr[i] {
      tail = tail - 1
    }
    deque[tail] = i
    tail = tail + 1
    // Evict from the front if the index fell out of the window.
    if deque[head] <= i - k {
      head = head + 1
    }
    if i >= k - 1 {
      result.push(arr[deque[head]])
    }
  }
  result
}

///|
/// Maximum sum of any contiguous subarray of length exactly `k`.
///
/// Returns `0` for invalid inputs (`k <= 0`, `k > n`, or `n == 0`).
pub fn max_sum_subarray(arr : Array[Int], k : Int) -> Int {
  let n = arr.length()
  if n == 0 || k <= 0 || k > n {
    return 0
  }
  let mut sum = 0
  for i = 0; i < k; i = i + 1 {
    sum = sum + arr[i]
  }
  let mut best = sum
  for i = k; i < n; i = i + 1 {
    sum = sum + arr[i] - arr[i - k]
    if sum > best {
      best = sum
    }
  }
  best
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "sliding_window_max: standard" {
  let arr = [1, 3, -1, -3, 5, 3, 6, 7]
  assert_eq(sliding_window_max(arr, 3), [3, 3, 5, 5, 6, 7])
}

///|
test "sliding_window_max: window size one" {
  assert_eq(sliding_window_max([5, 3, 4], 1), [5, 3, 4])
}

///|
test "max_sum_subarray: ascending array" {
  assert_eq(max_sum_subarray([1, 2, 3, 4, 5], 2), 9)
}

///|
test "max_sum_subarray: mixed signs" {
  assert_eq(max_sum_subarray([-1, 2, 3, -4, 5], 2), 5)
}
