/// In-place selection sort on a FixedArray[Int].
/// Verified: after sorting, the entire array satisfies fully_sorted.
///
/// Algorithm: For each position i from 0 to n-1, find the minimum
/// element in the unsorted suffix xs[i..n) and swap it with xs[i].
pub fn selection_sort(
  xs : FixedArray[Int],
) -> Unit where {
  proof_ensure: fully_sorted(xs),
} {
  for i = 0; i < xs.length(); {
    // Find the index of the minimum element in xs[i..n)
    let min_idx = for j = i, best = i; j < xs.length(); {
      if xs[j] < xs[best] {
        continue j + 1, j
      } else {
        continue j + 1, best
      }
    } nobreak {
      best
    }
    // Swap xs[i] and xs[min_idx]
    let tmp = xs[i]
    xs[i] = xs[min_idx]
    xs[min_idx] = tmp
    continue i + 1
  } nobreak {
    ()
  } where {
    proof_invariant: 0 <= i,
    proof_invariant: i <= xs.length(),
    proof_invariant: sorted_range(xs, 0, i),
    proof_invariant: partitioned(xs, i),
    proof_reasoning: (
      #| The outer loop maintains two invariants:
      #| 1. xs[0..i) is sorted (sorted_range).
      #| 2. All elements in xs[0..i) are <= all elements in
      #|    xs[i..n) (partitioned).
      #|
      #| At each iteration, the inner loop finds min_idx, the index
      #| of the minimum element in xs[i..n). After swapping xs[i]
      #| with xs[min_idx], the element at position i becomes the
      #| minimum of the old xs[i..n).
      #|
      #| By the partitioned invariant, all elements in xs[0..i) are
      #| <= all elements in xs[i..n), hence <= the new xs[i]. This
      #| extends sorted_range from [0, i) to [0, i+1).
      #|
      #| The new xs[i] (the old minimum of [i..n)) is <= all
      #| remaining elements in xs[i+1..n), and elements in xs[0..i)
      #| remain <= elements in xs[i+1..n) by the old partitioned
      #| property. This maintains partitioned for i+1.
      #|
      #| When the outer loop completes, i == xs.length(), so the
      #| entire array is sorted (fully_sorted).
    ),
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
  // After sort: [0,0,0,1,1,1,2,2]
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
  // Verify sorted
  for k = 0; k < 19; k = k + 1 {
    assert_eq(xs[k] <= xs[k + 1], true)
  }
}
