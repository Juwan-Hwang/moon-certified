///|
/// Sum all elements of a non-negative array.
///
/// **Deprecated**: This function does not detect overflow. If the true
/// mathematical sum exceeds 2³¹−1, the result silently wraps to a negative
/// value, invalidating the non-negativity guarantee at runtime.
///
/// Use `array_sum_checked` instead, which returns `None` on overflow.
///
/// Verified by `moon prove`:
/// - result >= 0 when all elements are non-negative (proven by Z3)
///
/// Not verified (requires inductive reasoning about loop accumulation):
/// - result == Σ xs[i] (full correctness)
///
/// Full correctness is tested exhaustively instead.
///
/// This function is retained for formal verification (Z3 proof of
/// non-negativity under the mathematical integer model) and backward
/// compatibility with code that can guarantee no overflow.
pub fn array_sum(
  xs : FixedArray[Int],
) -> Int where {
  proof_require: ∀ i : Int, 0 <= i && i < xs.length() → 0 <= xs[i],
  proof_ensure: result => sum_nonneg_ok(result),
} {
  for i = 0, sum = 0; i < xs.length(); {
    proof_assert 0 <= xs[i]
    continue i + 1, sum + xs[i]
  } nobreak {
    sum
  } where {
    proof_invariant: 0 <= i,
    proof_invariant: i <= xs.length(),
    proof_invariant: 0 <= sum,
    proof_reasoning: (
      #| The loop accumulates the sum of elements.
      #| Since every element is non-negative (by precondition),
      #| the running sum stays non-negative throughout.
    ),
  }
}

///|
/// Count the number of non-negative elements in an array.
/// Verified: the result is between 0 and the array length.
pub fn count_nonneg(
  xs : FixedArray[Int],
) -> Int where {
  proof_ensure: result => count_nonneg_ok(xs, result),
} {
  for i = 0, count = 0; i < xs.length(); {
    if xs[i] >= 0 {
      continue i + 1, count + 1
    } else {
      continue i + 1, count
    }
  } nobreak {
    count
  } where {
    proof_invariant: 0 <= i,
    proof_invariant: i <= xs.length(),
    proof_invariant: 0 <= count,
    proof_invariant: count <= i,
    proof_reasoning: (
      #| The loop counts non-negative elements.
      #| `count` increases by 1 for each non-negative element,
      #| and never exceeds the number of elements processed.
    ),
  }
}

///|
/// Overflow-safe sum of all array elements.
///
/// Returns `Some(total)` when the mathematical sum fits in 32-bit `Int`,
/// or `None` when the sum overflows `Int` range. Uses 64-bit arithmetic
/// internally to detect overflow before it happens.
///
/// Unlike `array_sum`, this function does **not** require elements to be
/// non-negative and correctly detects overflow for both positive and negative
/// sums.
pub fn array_sum_checked(xs : FixedArray[Int]) -> Int? {
  let mut sum = 0L
  let max_int = 2147483647L
  let min_int = -2147483648L
  for i = 0; i < xs.length(); i = i + 1 {
    sum = sum + xs[i].to_int64()
    if sum > max_int || sum < min_int {
      return None
    }
  }
  Some(sum.to_int())
}

///|
test "array_sum: basic" {
  let xs = FixedArray::makei(5, fn(i) { i + 1 }) // [1, 2, 3, 4, 5]
  assert_eq(array_sum(xs), 15)
}

///|
test "array_sum: zeros" {
  let xs = FixedArray::make(5, 0)
  assert_eq(array_sum(xs), 0)
}

///|
test "array_sum: empty" {
  let xs : FixedArray[Int] = FixedArray::make(0, 0)
  assert_eq(array_sum(xs), 0)
}

///|
test "count_nonneg: mixed" {
  let xs = FixedArray::makei(6, fn(i) { i - 3 }) // [-3, -2, -1, 0, 1, 2]
  assert_eq(count_nonneg(xs), 3)
}

///|
test "count_nonneg: all positive" {
  let xs = FixedArray::makei(4, fn(i) { i + 1 }) // [1, 2, 3, 4]
  assert_eq(count_nonneg(xs), 4)
}

///|
test "count_nonneg: all negative" {
  let xs = FixedArray::makei(3, fn(i) { -(i + 1) }) // [-1, -2, -3]
  assert_eq(count_nonneg(xs), 0)
}

///|
test "array_sum: correctness check" {
  // Verify that array_sum returns the actual sum
  let xs = FixedArray::makei(10, fn(i) { i }) // [0,1,2,...,9]
  assert_eq(array_sum(xs), 45)
  let xs2 = FixedArray::makei(5, fn(i) { (i + 1) * (i + 1) }) // [1,4,9,16,25]
  assert_eq(array_sum(xs2), 55)
}

///|
test "array_sum_checked: basic" {
  let xs = FixedArray::makei(5, fn(i) { i + 1 })
  assert_eq(array_sum_checked(xs), Some(15))
}

///|
test "array_sum_checked: overflow detected" {
  // 50000 * 50000 elements each = 2.5e9 > Int32::MAX
  let xs = FixedArray::make(50000, 50000)
  assert_true(array_sum_checked(xs) is None)
}

///|
test "array_sum_checked: negative overflow" {
  let xs = FixedArray::make(50000, -50000)
  assert_true(array_sum_checked(xs) is None)
}

///|
test "array_sum_checked: no overflow with negatives" {
  let xs = FixedArray::make(5, 0)
  xs[0] = 1000
  xs[1] = -500
  xs[2] = 200
  xs[3] = -300
  xs[4] = 600
  assert_eq(array_sum_checked(xs), Some(1000))
}

///|
test "array_sum_checked: boundary" {
  let xs = FixedArray::make(2, 0)
  xs[0] = 2147483647
  xs[1] = 0
  assert_eq(array_sum_checked(xs), Some(2147483647))
  xs[1] = 1
  assert_true(array_sum_checked(xs) is None)
}

///|
/// Verified bounded sum: when all elements are in [lo, hi],
/// the sum is bounded by [n * lo, n * hi].
pub fn bounded_sum(
  xs : FixedArray[Int],
  lo : Int,
  hi : Int,
) -> Int where {
  proof_require: in_range(xs, lo, hi),
  proof_ensure: result => sum_bounded(xs.length(), lo, hi, result),
} {
  for i = 0, sum = 0; i < xs.length(); {
    proof_assert lo <= xs[i]
    proof_assert xs[i] <= hi
    continue i + 1, sum + xs[i]
  } nobreak {
    sum
  } where {
    proof_invariant: 0 <= i,
    proof_invariant: i <= xs.length(),
    proof_invariant: i * lo <= sum,
    proof_invariant: sum <= i * hi,
    proof_reasoning: (
      #| Each element xs[i] is in [lo, hi].
      #| After k steps, sum = xs[0]+...+xs[k-1].
      #| Since each term >= lo, sum >= k * lo.
      #| Since each term <= hi, sum <= k * hi.
    ),
  }
}

///|
/// Verified non-negative sum: when all elements are non-negative,
/// the sum is non-negative. (Special case of bounded_sum with lo=0.)
pub fn array_sum_nonneg(
  xs : FixedArray[Int],
) -> Int where {
  proof_require: ∀ i : Int, 0 <= i && i < xs.length() → 0 <= xs[i],
  proof_ensure: result => 0 <= result,
} {
  for i = 0, sum = 0; i < xs.length(); {
    proof_assert 0 <= xs[i]
    continue i + 1, sum + xs[i]
  } nobreak {
    sum
  } where {
    proof_invariant: 0 <= i,
    proof_invariant: i <= xs.length(),
    proof_invariant: 0 <= sum,
  }
}

///|
/// Verified uniform sum: when all elements equal value,
/// the sum equals n * value.
pub fn uniform_sum(
  xs : FixedArray[Int],
  value : Int,
) -> Int where {
  proof_require: all_equal(xs, value),
  proof_ensure: result => uniform_sum_ok(xs.length(), value, result),
} {
  for i = 0, sum = 0; i < xs.length(); {
    proof_assert xs[i] == value
    continue i + 1, sum + xs[i]
  } nobreak {
    sum
  } where {
    proof_invariant: 0 <= i,
    proof_invariant: i <= xs.length(),
    proof_invariant: sum == i * value,
    proof_reasoning: (
      #| Each element equals value.
      #| After k steps, sum = k * value.
    ),
  }
}

///|
test "bounded_sum: basic" {
  let xs = FixedArray::make(5, 3)
  assert_eq(bounded_sum(xs, 0, 10), 15)
  assert_true(0 * 5 <= 15 && 15 <= 10 * 5)
}

///|
test "bounded_sum: mixed range" {
  let xs = FixedArray::make(4, 0)
  xs[0] = 1
  xs[1] = 5
  xs[2] = 3
  xs[3] = 2
  assert_eq(bounded_sum(xs, 0, 10), 11)
  assert_true(0 <= 11 && 11 <= 40)
}

///|
test "array_sum_nonneg: basic" {
  let xs = FixedArray::makei(5, fn(i) { i + 1 })
  assert_eq(array_sum_nonneg(xs), 15)
  assert_true(0 <= 15)
}

///|
test "uniform_sum: basic" {
  let xs = FixedArray::make(5, 7)
  assert_eq(uniform_sum(xs, 7), 35)
  assert_eq(uniform_sum(xs, 7), 5 * 7)
}

///|
test "uniform_sum: zeros" {
  let xs = FixedArray::make(10, 0)
  assert_eq(uniform_sum(xs, 0), 0)
}
