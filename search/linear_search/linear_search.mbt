/// Linear search on an unsorted array.
/// Returns Some(index) if found, None if not found.
/// Verified: for all inputs, the returned result satisfies linear_search_ok.
pub fn search(
  xs : FixedArray[Int],
  key : Int,
) -> Int? where {
  proof_ensure: result => linear_search_ok(xs, key, result),
} {
  for i = 0; i < xs.length(); {
    if xs[i] == key {
      proof_assert (0 <= i) && (i < xs.length())
      proof_assert xs[i] == key
      break Some(i)
    }
    continue i + 1
  } nobreak {
    None
  } where {
    proof_invariant: 0 <= i,
    proof_invariant: i <= xs.length(),
    proof_invariant: ∀ idx : Int, (0 <= idx) && (idx < i) → xs[idx] != key,
    proof_yield: res => linear_search_ok(xs, key, res),
    proof_reasoning: (
      #| The loop scans the array from left to right.
      #| At each position `i`, if `xs[i] == key`, we return `Some(i)`.
      #| Otherwise, we mark position `i` as checked and continue.
      #|
      #| The invariant states that every index before `i` has been
      #| checked and does not contain `key`.
      #|
      #| If the loop exits normally (i == length), every index has been
      #| checked, so `key` is not in the array → return `None`.
    ),
  }
}

test "linear_search: found" {
  let xs = FixedArray::make(5, fn(i) { i * 3 })  // [0, 3, 6, 9, 12]
  assert_eq(search(xs, 6), Some(2))
  assert_eq(search(xs, 0), Some(0))
  assert_eq(search(xs, 12), Some(4))
}

test "linear_search: not found" {
  let xs = FixedArray::make(5, fn(i) { i * 3 })
  assert_eq(search(xs, 1), None)
  assert_eq(search(xs, 5), None)
  assert_eq(search(xs, 13), None)
}

test "linear_search: empty array" {
  let xs : FixedArray[Int] = FixedArray::new(0)
  assert_eq(search(xs, 42), None)
}

test "linear_search: duplicates" {
  let xs = FixedArray::make(6, fn(i) { if i < 3 { 1 } else { 2 } })  // [1,1,1,2,2,2]
  let result = search(xs, 1)
  // Should return the first occurrence
  match result {
    Some(idx) => assert_eq(idx < 3, true)
    None => panic("should find 1")
  }
}
