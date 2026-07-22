/// Find the index of the maximum element in a non-empty array.
/// Verified: the returned index is valid and xs[result] >= xs[k] for all k.
pub fn max_element(
  xs : FixedArray[Int],
) -> Int where {
  proof_require: 0 < xs.length(),
  proof_ensure: result => max_ok(xs, result),
} {
  for i = 1, best = 0; i < xs.length(); {
    if xs[i] > xs[best] {
      proof_assert xs[i] > xs[best]
      continue i + 1, i
    } else {
      proof_assert xs[i] <= xs[best]
      continue i + 1, best
    }
  } nobreak {
    best
  } where {
    proof_invariant: 0 <= i,
    proof_invariant: i <= xs.length(),
    proof_invariant: 0 <= best,
    proof_invariant: best < i,
    proof_invariant: ∀ k : Int, (0 <= k) && (k < i) → xs[k] <= xs[best],
    proof_reasoning: (
      #| The loop maintains `best` as the index of the maximum element
      #| in the prefix `xs[0..i)`.
      #|
      #| At each step, if `xs[i] > xs[best]`, the new best is `i`.
      #| Otherwise, `best` stays the same since `xs[i] <= xs[best]`.
      #|
      #| When the loop exits, `i == xs.length()`, so `best` is the
      #| index of the maximum over the entire array.
    ),
  }
}

test "max_element: basic" {
  let xs = FixedArray::make(5, fn(i) { i })  // [0, 1, 2, 3, 4]
  assert_eq(max_element(xs), 4)
}

test "max_element: first element" {
  let xs = FixedArray::make(4, fn(i) { 10 - i })  // [10, 9, 8, 7]
  assert_eq(max_element(xs), 0)
}

test "max_element: duplicates" {
  let xs = FixedArray::make(5, fn(_) { 7 })  // [7, 7, 7, 7, 7]
  let result = max_element(xs)
  assert_eq(xs[result], 7)
}

test "max_element: negative values" {
  let xs = FixedArray::make(3, fn(i) { -(i + 1) })  // [-1, -2, -3]
  assert_eq(max_element(xs), 0)
}
