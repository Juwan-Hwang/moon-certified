/// Binary search on a sorted array.
/// Returns Some(index) if found, None if not found.
/// Verified correct by moon prove: for all inputs satisfying the sorted
/// precondition, the returned result satisfies binary_search_ok.
pub fn search(
  xs : FixedArray[Int],
  key : Int,
) -> Int? where {
  proof_require: sorted(xs),
  proof_ensure: result => binary_search_ok(xs, key, result),
} {
  for i = 0, j = xs.length(); i < j; {
    let h = i + (j - i) / 2
    if xs[h] < key {
      proof_assert ∀ idx : Int,
        (0 <= idx) && (idx < h + 1) → xs[idx] < key
      continue h + 1, j
    } else if key < xs[h] {
      proof_assert ∀ idx : Int,
        (h <= idx) && (idx < xs.length()) → key < xs[idx]
      continue i, h
    } else {
      proof_assert xs[h] == key
      break Some(h)
    }
  } nobreak {
    None
  } where {
    proof_invariant: 0 <= i,
    proof_invariant: i <= j,
    proof_invariant: j <= xs.length(),
    proof_invariant: ∀ idx : Int, (0 <= idx) && (idx < i) → xs[idx] < key,
    proof_invariant: ∀ idx : Int, (j <= idx) && (idx < xs.length()) → key < xs[idx],
    proof_yield: res => binary_search_ok(xs, key, res),
    proof_reasoning: (
      #| The loop maintains a candidate window `[i, j)`.
      #| Every index before `i` is known to hold a value `< key`, and every
      #| index from `j` onward is known to hold a value `> key`.
      #|
      #| At midpoint `h` there are three cases:
      #| - `xs[h] < key`: move the left boundary to `h + 1`
      #| - `key < xs[h]`: move the right boundary to `h`
      #| - otherwise, the element at `h` is equal to `key`
      #|
      #| If the loop exits normally, the exclusion invariants cover the whole
      #| array, so no index can contain `key`.
    ),
  }
}

test "binary_search: found" {
  let xs = FixedArray::makei(5, fn(i) { i * 2 })  // [0, 2, 4, 6, 8]
  assert_eq(search(xs, 4), Some(2))
  assert_eq(search(xs, 0), Some(0))
  assert_eq(search(xs, 8), Some(4))
}

test "binary_search: not found" {
  let xs = FixedArray::makei(5, fn(i) { i * 2 })  // [0, 2, 4, 6, 8]
  assert_eq(search(xs, 1), None)
  assert_eq(search(xs, 5), None)
  assert_eq(search(xs, 9), None)
}

test "binary_search: empty array" {
  let xs : FixedArray[Int] = FixedArray::make(0, 0)
  assert_eq(search(xs, 42), None)
}

test "binary_search: single element" {
  let xs = FixedArray::make(1, 42)
  assert_eq(search(xs, 42), Some(0))
  assert_eq(search(xs, 41), None)
}
