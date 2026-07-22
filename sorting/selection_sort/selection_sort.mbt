/// In-place selection sort on a FixedArray[Int].
///
/// Verification: loop bounds are formally verified (no out-of-bounds access).
/// The sortedness postcondition (fully_sorted) is not formally verified due to
/// MoonBit proof system limitation: array mutation causes Z3 to lose
/// quantified invariants. Correctness is ensured by 8 tests.
///
/// Algorithm: For each position i from 0 to n-1, find the minimum
/// element in the unsorted suffix xs[i..n) and swap it with xs[i].
pub fn selection_sort(
  xs : FixedArray[Int],
) -> Unit {
  let n = xs.length()
  if n <= 1 {
    return
  }
  for i = 0; i < n; {
    let min_idx = for j = i, best = i; j < n; {
      if xs[j] < xs[best] {
        continue j + 1, j
      } else {
        continue j + 1, best
      }
    } nobreak {
      best
    } where {
      proof_invariant: 0 <= j,
      proof_invariant: j <= n,
      proof_invariant: 0 <= best,
      proof_invariant: best < n,
    }
    let tmp = xs[i]
    xs[i] = xs[min_idx]
    xs[min_idx] = tmp
    continue i + 1
  } nobreak {
    ()
  } where {
    proof_invariant: 0 <= i,
    proof_invariant: i <= n,
  }
}

test "selection_sort: basic" {
  let xs = FixedArray::makei(5, fn(i) { 5 - i })  // [5, 4, 3, 2, 1]
  selection_sort(xs)
  assert_eq(xs[0], 1)
  assert_eq(xs[1], 2)
  assert_eq(xs[2], 3)
  assert_eq(xs[3], 4)
  assert_eq(xs[4], 5)
}

test "selection_sort: already sorted" {
  let xs = FixedArray::makei(5, fn(i) { i })  // [0, 1, 2, 3, 4]
  selection_sort(xs)
  for k = 0; k < 5; k = k + 1 {
    assert_eq(xs[k], k)
  }
}

test "selection_sort: reverse sorted" {
  let xs = FixedArray::makei(10, fn(i) { 9 - i })  // [9, 8, ..., 0]
  selection_sort(xs)
  for k = 0; k < 10; k = k + 1 {
    assert_eq(xs[k], k)
  }
}

test "selection_sort: single element" {
  let xs = FixedArray::make(1, 42)
  selection_sort(xs)
  assert_eq(xs[0], 42)
}

test "selection_sort: empty array" {
  let xs = FixedArray::make(0, 0)
  selection_sort(xs)
  assert_eq(xs.length(), 0)
}

test "selection_sort: duplicates" {
  let xs = FixedArray::makei(8, fn(i) { i % 3 })  // [0,1,2,0,1,2,0,1]
  selection_sort(xs)
  assert_eq(xs[0], 0)
  assert_eq(xs[1], 0)
  assert_eq(xs[2], 0)
  assert_eq(xs[3], 1)
  assert_eq(xs[4], 1)
  assert_eq(xs[5], 1)
  assert_eq(xs[6], 2)
  assert_eq(xs[7], 2)
}

test "selection_sort: negative values" {
  let xs = FixedArray::makei(5, fn(i) { i - 2 })  // [-2, -1, 0, 1, 2]
  selection_sort(xs)
  for k = 0; k < 5; k = k + 1 {
    assert_eq(xs[k], k - 2)
  }
}

test "selection_sort: large random-like" {
  let xs = FixedArray::makei(20, fn(i) { (i * 7 + 3) % 13 })
  selection_sort(xs)
  for k = 0; k < 19; k = k + 1 {
    assert_eq(xs[k] <= xs[k + 1], true)
  }
}
