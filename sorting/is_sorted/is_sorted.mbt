/// Check whether an array is sorted in non-decreasing order.
/// Verified: if the function returns true, the array satisfies array_sorted.
pub fn is_sorted(
  xs : FixedArray[Int],
) -> Bool where {
  proof_ensure: result => is_sorted_ok(xs, result),
} {
  for i = 0; i < xs.length() - 1; {
    if xs[i] > xs[i + 1] {
      proof_assert xs[i] > xs[i + 1]
      break false
    }
    proof_assert xs[i] <= xs[i + 1]
    continue i + 1
  } nobreak {
    true
  } where {
    proof_invariant: 0 <= i,
    proof_invariant: ∀ k : Int, (0 <= k) && (k < i) → xs[k] <= xs[k + 1],
    proof_yield: res => is_sorted_ok(xs, res),
    proof_reasoning: (
      #| The loop checks each adjacent pair (xs[i], xs[i+1]).
      #| If any pair is out of order (xs[i] > xs[i+1]), return false.
      #|
      #| The invariant states that all pairs before position i are in order.
      #|
      #| If the loop completes without finding an out-of-order pair,
      #| all adjacent pairs are ordered, which implies the array is sorted.
    ),
  }
}

test "is_sorted: sorted array" {
  let xs = FixedArray::make(5, fn(i) { i })  // [0, 1, 2, 3, 4]
  assert_eq(is_sorted(xs), true)
}

test "is_sorted: unsorted array" {
  let xs = FixedArray::make(5, fn(i) { 4 - i })  // [4, 3, 2, 1, 0]
  assert_eq(is_sorted(xs), false)
}

test "is_sorted: empty array" {
  let xs : FixedArray[Int] = FixedArray::new(0)
  assert_eq(is_sorted(xs), true)
}

test "is_sorted: single element" {
  let xs = FixedArray::make(1, fn(_) { 42 })
  assert_eq(is_sorted(xs), true)
}

test "is_sorted: with duplicates" {
  let xs = FixedArray::make(6, fn(i) { i / 2 })  // [0, 0, 1, 1, 2, 2]
  assert_eq(is_sorted(xs), true)
}
