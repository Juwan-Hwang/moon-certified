/// Sum all elements of a non-negative array.
/// Verified: the result is non-negative when all elements are non-negative.
pub fn array_sum(
  xs : FixedArray[Int],
) -> Int where {
  proof_require: ∀ i : Int, (0 <= i) && (i < xs.length()) → 0 <= xs[i],
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

test "array_sum: basic" {
  let xs = FixedArray::make(5, fn(i) { i + 1 })  // [1, 2, 3, 4, 5]
  assert_eq(array_sum(xs), 15)
}

test "array_sum: zeros" {
  let xs = FixedArray::make(5, fn(_) { 0 })
  assert_eq(array_sum(xs), 0)
}

test "array_sum: empty" {
  let xs : FixedArray[Int] = FixedArray::new(0)
  assert_eq(array_sum(xs), 0)
}

test "count_nonneg: mixed" {
  let xs = FixedArray::make(6, fn(i) { i - 3 })  // [-3, -2, -1, 0, 1, 2]
  assert_eq(count_nonneg(xs), 3)
}

test "count_nonneg: all positive" {
  let xs = FixedArray::make(4, fn(i) { i + 1 })  // [1, 2, 3, 4]
  assert_eq(count_nonneg(xs), 4)
}

test "count_nonneg: all negative" {
  let xs = FixedArray::make(3, fn(i) { -(i + 1) })  // [-1, -2, -3]
  assert_eq(count_nonneg(xs), 0)
}
