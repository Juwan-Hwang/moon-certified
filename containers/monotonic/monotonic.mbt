/// Monotonic queue and stack data structures.
///
/// A **monotonic stack** maintains elements in monotonically increasing or
/// decreasing order, enabling O(n) computation of "next greater element",
/// "next smaller element", and similar problems.
///
/// A **monotonic deque** (double-ended queue) extends this to sliding-window
/// problems: for each window of size `k`, it can find the minimum or maximum
/// in O(1) amortised time, giving O(n) total for all windows.
///
/// ## Use cases
///
/// - **Sliding window minimum/maximum**: stock prices, temperature ranges,
///   bandwidth monitoring.
/// - **Next greater/smaller element**: stock span problem, daily temperatures.
/// - **Largest rectangle in histogram**: the classic monotonic-stack problem.
/// - **Stock span**: consecutive days with price ≤ today's price.
///
/// ## Complexity
///
/// - **Monotonic stack**: O(n) — each element is pushed and popped at most once.
/// - **Monotonic deque**: O(n) — each element is added and removed at most once.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

// ---------------------------------------------------------------------------
// Monotonic Stack
// ---------------------------------------------------------------------------

///|
/// A monotonic stack that maintains elements in non-decreasing or
/// non-increasing order.
///
/// - When `increasing` is `true`: the stack is maintained in non-decreasing
///   order (bottom to top). Pushing a smaller element pops all larger elements.
/// - When `increasing` is `false`: the stack is maintained in non-increasing
///   order. Pushing a larger element pops all smaller elements.
///
/// All fields are **package-private**; external callers interact through
/// methods only.
pub struct MonotonicStack {
  priv data : Array[(Int, Int)] // (value, index) pairs
  priv increasing : Bool // true = non-decreasing, false = non-increasing
}

///|
/// Create an empty monotonic stack.
///
/// - `increasing = true`: the stack maintains a non-decreasing sequence.
///   Pushing `v` pops all elements `> v` (strictly greater), keeping `≤ v`.
/// - `increasing = false`: the stack maintains a non-increasing sequence.
///   Pushing `v` pops all elements `< v` (strictly less), keeping `≥ v`.
fn MonotonicStack::new(increasing : Bool) -> MonotonicStack {
  { data: [], increasing }
}

///|
/// Push `(value, index)` onto the stack, popping all elements that violate
/// the monotonicity condition.
///
/// Returns the array of popped `(value, index)` pairs, in the order they
/// were popped (top of stack first). This allows callers to compute
/// "next greater/smaller element" for each popped element.
fn MonotonicStack::push(
  self : MonotonicStack,
  value : Int,
  index : Int,
) -> Array[(Int, Int)] {
  let popped : Array[(Int, Int)] = []
  while self.data.length() > 0 {
    let top_idx = self.data.length() - 1
    let (top_val, _) = self.data[top_idx]
    let should_pop = if self.increasing {
      // Non-decreasing: pop elements strictly greater than `value`.
      top_val > value
    } else {
      // Non-increasing: pop elements strictly less than `value`.
      top_val < value
    }
    if should_pop {
      popped.push(self.data[top_idx])
      ignore(self.data.pop())
    } else {
      break
    }
  }
  self.data.push((value, index))
  popped
}

///|
/// Peek at the top of the stack without removing it.
/// Returns `None` if the stack is empty.
pub fn MonotonicStack::peek(self : MonotonicStack) -> (Int, Int)? {
  if self.data.length() == 0 {
    None
  } else {
    Some(self.data[self.data.length() - 1])
  }
}

///|
/// Number of elements in the stack.
pub fn MonotonicStack::len(self : MonotonicStack) -> Int {
  self.data.length()
}

// ---------------------------------------------------------------------------
// Public API: Next Greater / Smaller Element
// ---------------------------------------------------------------------------

///|
/// For each element in `arr`, find the index of the next element to its right
/// that is strictly greater.
///
/// Returns a `FixedArray[Int]` where `result[i]` is the index of the next
/// greater element, or `-1` if no such element exists.
///
/// # Complexity
/// - Time: O(n) — each element is pushed and popped at most once.
/// - Space: O(n) for the stack.
///
/// # Example
/// ```
/// arr = [3, 1, 4, 1, 5, 9, 2, 6]
/// result = [2, 2, 4, 4, 5, -1, 7, -1]
/// //          3→4  1→4  4→5  1→5  5→9  9→-   2→6  6→-
/// ```
pub fn next_greater_element(arr : FixedArray[Int]) -> FixedArray[Int] {
  let n = arr.length()
  let result = FixedArray::make(n, -1)
  // Use a decreasing stack (non-increasing). When we encounter a value
  // greater than the top, we've found the "next greater" for the top.
  let stack = MonotonicStack::new(false) // non-increasing
  for i = 0; i < n; i = i + 1 {
    let popped = stack.push(arr[i], i)
    for j = 0; j < popped.length(); j = j + 1 {
      let (_, idx) = popped[j]
      result[idx] = i
    }
  }
  result
}

///|
/// For each element in `arr`, find the index of the next element to its right
/// that is strictly smaller.
///
/// Returns a `FixedArray[Int]` where `result[i]` is the index of the next
/// smaller element, or `-1` if no such element exists.
///
/// # Complexity
/// - Time: O(n)
/// - Space: O(n)
pub fn next_smaller_element(arr : FixedArray[Int]) -> FixedArray[Int] {
  let n = arr.length()
  let result = FixedArray::make(n, -1)
  // Use an increasing stack. When we encounter a value smaller than the top,
  // we've found the "next smaller" for the top.
  let stack = MonotonicStack::new(true) // non-decreasing
  for i = 0; i < n; i = i + 1 {
    let popped = stack.push(arr[i], i)
    for j = 0; j < popped.length(); j = j + 1 {
      let (_, idx) = popped[j]
      result[idx] = i
    }
  }
  result
}

// ---------------------------------------------------------------------------
// Public API: Sliding Window
// ---------------------------------------------------------------------------

///|
/// For each sliding window of size `k` over `arr`, compute the minimum.
///
/// Returns a `FixedArray[Int]` of length `n - k + 1` where `result[i]` is
/// `min(arr[i], arr[i+1], ..., arr[i+k-1])`.
///
/// Returns an empty array if `k <= 0` or `k > n`.
///
/// # Complexity
/// - Time: O(n) — each element is added and removed from the deque at most once.
/// - Space: O(k) for the deque.
///
/// # Algorithm
///
/// Uses a monotonic deque that stores indices in increasing order of their
/// values. The front of the deque always holds the index of the minimum
/// element in the current window. When the front falls outside the window,
/// it is removed. When a new element is smaller than elements at the back,
/// those are removed (they can never be the minimum in any future window
/// that includes the new element).
pub fn sliding_window_minimum(
  arr : FixedArray[Int],
  k : Int,
) -> FixedArray[Int] {
  let n = arr.length()
  if k <= 0 || k > n || n == 0 {
    return FixedArray::make(0, 0)
  }
  let result = FixedArray::make(n - k + 1, 0)
  // Deque stores indices, values are non-decreasing from front to back.
  let deque : Array[Int] = []
  let mut front = 0 // pointer to front of deque (avoid Array::shift O(n))
  for i = 0; i < n; i = i + 1 {
    // Remove elements from the back that are >= current element.
    while deque.length() > front {
      let back_idx = deque.length() - 1
      if arr[deque[back_idx]] >= arr[i] {
        ignore(deque.pop())
      } else {
        break
      }
    }
    deque.push(i)
    // Remove the front if it's outside the window.
    while deque[front] <= i - k {
      front = front + 1
    }
    // Record the minimum when the window is full.
    if i >= k - 1 {
      result[i - k + 1] = arr[deque[front]]
    }
  }
  result
}

///|
/// For each sliding window of size `k` over `arr`, compute the maximum.
///
/// Returns a `FixedArray[Int]` of length `n - k + 1` where `result[i]` is
/// `max(arr[i], arr[i+1], ..., arr[i+k-1])`.
///
/// Returns an empty array if `k <= 0` or `k > n`.
///
/// # Complexity
/// - Time: O(n)
/// - Space: O(k)
pub fn sliding_window_maximum(
  arr : FixedArray[Int],
  k : Int,
) -> FixedArray[Int] {
  let n = arr.length()
  if k <= 0 || k > n || n == 0 {
    return FixedArray::make(0, 0)
  }
  let result = FixedArray::make(n - k + 1, 0)
  // Deque stores indices, values are non-increasing from front to back.
  let deque : Array[Int] = []
  let mut front = 0
  for i = 0; i < n; i = i + 1 {
    // Remove elements from the back that are <= current element.
    while deque.length() > front {
      let back_idx = deque.length() - 1
      if arr[deque[back_idx]] <= arr[i] {
        ignore(deque.pop())
      } else {
        break
      }
    }
    deque.push(i)
    // Remove the front if it's outside the window.
    while deque[front] <= i - k {
      front = front + 1
    }
    // Record the maximum when the window is full.
    if i >= k - 1 {
      result[i - k + 1] = arr[deque[front]]
    }
  }
  result
}

// ---------------------------------------------------------------------------
// Public API: Largest Rectangle in Histogram
// ---------------------------------------------------------------------------

///|
/// Compute the area of the largest rectangle in a histogram.
///
/// Given `heights[i]` = height of bar `i`, finds the maximum rectangular area
/// that can be formed by consecutive bars.
///
/// # Example
/// ```
/// heights = [2, 1, 5, 6, 2, 3]
/// // The largest rectangle uses bars 2-3 (heights 5,6) with height 5:
/// // area = 5 * 2 = 10.
/// ```
///
/// # Complexity
/// - Time: O(n) — each bar is pushed and popped at most once.
/// - Space: O(n) for the stack.
///
/// # Algorithm
///
/// Uses a monotonic increasing stack. For each bar, when a shorter bar is
/// encountered, the taller bars on the stack are popped and their maximum
/// rectangle area is computed (width = distance from current position to
/// the bar before the popped bar in the stack).
///
/// Uses `Int64` for the area computation to prevent overflow for large
/// heights and widths.
pub fn largest_rectangle_area(heights : FixedArray[Int]) -> Int64 {
  let n = heights.length()
  if n == 0 {
    return 0L
  }
  // Stack of indices into `heights`. The heights at these indices are
  // maintained in non-decreasing order (monotonic increasing stack).
  let indices : Array[Int] = []
  let mut max_area = 0L
  // Process all bars plus a sentinel (height 0) to flush the stack at the end.
  for i = 0; i <= n; i = i + 1 {
    let h = if i < n { heights[i] } else { 0 }
    // Pop bars that are taller than the current bar; each popped bar's
    // rectangle extends from the previous stack entry to the current index.
    while indices.length() > 0 {
      let top = indices[indices.length() - 1]
      if heights[top] < h {
        break
      }
      ignore(indices.pop())
      let width = if indices.length() == 0 {
        i // spans from 0 to i-1
      } else {
        i - indices[indices.length() - 1] - 1
      }
      let area = heights[top].to_int64() * width.to_int64()
      if area > max_area {
        max_area = area
      }
    }
    if i < n {
      indices.push(i)
    }
  }
  max_area
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "next_greater: basic" {
  let arr = FixedArray::makei(8, fn(i) { [3, 1, 4, 1, 5, 9, 2, 6][i] })
  let result = next_greater_element(arr)
  // 3→4(idx2), 1→4(idx2), 4→5(idx4), 1→5(idx4), 5→9(idx5), 9→-1, 2→6(idx7), 6→-1
  assert_eq(result[0], 2)
  assert_eq(result[1], 2)
  assert_eq(result[2], 4)
  assert_eq(result[3], 4)
  assert_eq(result[4], 5)
  assert_eq(result[5], -1)
  assert_eq(result[6], 7)
  assert_eq(result[7], -1)
}

///|
test "next_greater: strictly increasing" {
  let arr = FixedArray::makei(5, fn(i) { i }) // [0,1,2,3,4]
  let result = next_greater_element(arr)
  // Each element's next greater is the next index.
  assert_eq(result[0], 1)
  assert_eq(result[1], 2)
  assert_eq(result[2], 3)
  assert_eq(result[3], 4)
  assert_eq(result[4], -1) // last element has no next greater
}

///|
test "next_greater: strictly decreasing" {
  let arr = FixedArray::makei(5, fn(i) { 4 - i }) // [4,3,2,1,0]
  let result = next_greater_element(arr)
  // No next greater for any element.
  for i = 0; i < 5; i = i + 1 {
    assert_eq(result[i], -1)
  }
}

///|
test "next_greater: all same" {
  let arr = FixedArray::make(5, 7)
  let result = next_greater_element(arr)
  // No strictly greater element exists.
  for i = 0; i < 5; i = i + 1 {
    assert_eq(result[i], -1)
  }
}

///|
test "next_greater: empty" {
  let arr : FixedArray[Int] = FixedArray::make(0, 0)
  let result = next_greater_element(arr)
  assert_eq(result.length(), 0)
}

///|
test "next_smaller: basic" {
  let arr = FixedArray::makei(6, fn(i) { [3, 1, 4, 1, 5, 2][i] })
  let result = next_smaller_element(arr)
  // 3→1(idx1), 1→-1, 4→1(idx3), 1→-1, 5→2(idx5), 2→-1
  assert_eq(result[0], 1)
  assert_eq(result[1], -1)
  assert_eq(result[2], 3)
  assert_eq(result[3], -1)
  assert_eq(result[4], 5)
  assert_eq(result[5], -1)
}

///|
test "sliding_window_min: basic" {
  let arr = FixedArray::makei(8, fn(i) { [1, 3, -1, -3, 5, 3, 6, 7][i] })
  let result = sliding_window_minimum(arr, 3)
  // Windows: [1,3,-1]=-1, [3,-1,-3]=-3, [-1,-3,5]=-3, [-3,5,3]=-3,
  //          [5,3,6]=3, [3,6,7]=3
  assert_eq(result.length(), 6)
  assert_eq(result[0], -1)
  assert_eq(result[1], -3)
  assert_eq(result[2], -3)
  assert_eq(result[3], -3)
  assert_eq(result[4], 3)
  assert_eq(result[5], 3)
}

///|
test "sliding_window_min: k=1" {
  let arr = FixedArray::makei(5, fn(i) { i }) // [0,1,2,3,4]
  let result = sliding_window_minimum(arr, 1)
  assert_eq(result.length(), 5)
  for i = 0; i < 5; i = i + 1 {
    assert_eq(result[i], i)
  }
}

///|
test "sliding_window_min: k=n" {
  let arr = FixedArray::makei(5, fn(i) { 5 - i }) // [5,4,3,2,1]
  let result = sliding_window_minimum(arr, 5)
  assert_eq(result.length(), 1)
  assert_eq(result[0], 1) // min of all
}

///|
test "sliding_window_min: invalid k" {
  let arr = FixedArray::makei(5, fn(i) { i })
  assert_eq(sliding_window_minimum(arr, 0).length(), 0)
  assert_eq(sliding_window_minimum(arr, 6).length(), 0)
}

///|
test "sliding_window_min: all same" {
  let arr = FixedArray::make(6, 42)
  let result = sliding_window_minimum(arr, 3)
  assert_eq(result.length(), 4)
  for i = 0; i < 4; i = i + 1 {
    assert_eq(result[i], 42)
  }
}

///|
test "sliding_window_max: basic" {
  let arr = FixedArray::makei(8, fn(i) { [1, 3, -1, -3, 5, 3, 6, 7][i] })
  let result = sliding_window_maximum(arr, 3)
  // Windows: [1,3,-1]=3, [3,-1,-3]=3, [-1,-3,5]=5, [-3,5,3]=5,
  //          [5,3,6]=6, [3,6,7]=7
  assert_eq(result.length(), 6)
  assert_eq(result[0], 3)
  assert_eq(result[1], 3)
  assert_eq(result[2], 5)
  assert_eq(result[3], 5)
  assert_eq(result[4], 6)
  assert_eq(result[5], 7)
}

///|
test "sliding_window_max: k=1" {
  let arr = FixedArray::makei(5, fn(i) { i })
  let result = sliding_window_maximum(arr, 1)
  assert_eq(result.length(), 5)
  for i = 0; i < 5; i = i + 1 {
    assert_eq(result[i], i)
  }
}

///|
test "sliding_window_max: k=n" {
  let arr = FixedArray::makei(5, fn(i) { i })
  let result = sliding_window_maximum(arr, 5)
  assert_eq(result.length(), 1)
  assert_eq(result[0], 4) // max of all
}

///|
test "largest_rectangle: basic" {
  let heights = FixedArray::makei(6, fn(i) { [2, 1, 5, 6, 2, 3][i] })
  // The largest rectangle uses bars 2-3 (heights 5,6) with height 5:
  // area = 5 * 2 = 10.
  assert_eq(largest_rectangle_area(heights), 10L)
}

///|
test "largest_rectangle: single bar" {
  let heights = FixedArray::make(1, 5)
  assert_eq(largest_rectangle_area(heights), 5L)
}

///|
test "largest_rectangle: all same" {
  let heights = FixedArray::make(5, 3)
  // All bars height 3, width 5: area = 15.
  assert_eq(largest_rectangle_area(heights), 15L)
}

///|
test "largest_rectangle: strictly increasing" {
  let heights = FixedArray::makei(5, fn(i) { i + 1 }) // [1,2,3,4,5]
  // The best rectangle is 3*3=9 (bars 2,3,4 with height 3).
  // Or 5*1=5, 4*2=8, 3*3=9, 2*4=8, 1*5=5. Max is 9.
  assert_eq(largest_rectangle_area(heights), 9L)
}

///|
test "largest_rectangle: empty" {
  let heights : FixedArray[Int] = FixedArray::make(0, 0)
  assert_eq(largest_rectangle_area(heights), 0L)
}

///|
test "largest_rectangle: two bars" {
  let heights = FixedArray::make(2, 0)
  // All zero heights: area = 0.
  assert_eq(largest_rectangle_area(heights), 0L)
  let heights2 = FixedArray::make(2, 4)
  // Both height 4, width 2: area = 8.
  assert_eq(largest_rectangle_area(heights2), 8L)
}

///|
test "largest_rectangle: large values (overflow check)" {
  // Heights near Int32::max, width 3.
  let heights = FixedArray::make(3, 2000000000)
  // Area = 2000000000 * 3 = 6000000000, which overflows Int32 but fits Int64.
  assert_eq(largest_rectangle_area(heights), 6000000000L)
}
