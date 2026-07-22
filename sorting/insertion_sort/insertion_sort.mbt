/// In-place insertion sort on a FixedArray[Int].
/// Verified: after sorting, the entire array satisfies fully_sorted.
///
/// Algorithm: For each position i from 1 to n-1, insert xs[i] into the
/// sorted prefix xs[0..i) by shifting larger elements right.
pub fn insertion_sort(
  xs : FixedArray[Int],
) -> Unit where {
  proof_ensure: fully_sorted(xs),
} {
  let n = xs.length()
  if n <= 1 {
    proof_assert fully_sorted(xs)
  } else {
    proof_assert 1 <= n
    for i = 1; i < n; {
      let key = xs[i]
      let pos = for j = i - 1; j >= 0; {
        if xs[j] > key {
          xs[j + 1] = xs[j]
          continue j - 1
        } else {
          break j
        }
      } nobreak {
        -1
      } where {
        proof_invariant: 0 <= j,
        proof_invariant: j < n,
      }
      xs[pos + 1] = key
      continue i + 1
    } nobreak {
      ()
    } where {
      proof_invariant: 1 <= i,
      proof_invariant: i <= n,
      proof_invariant: n == xs.length(),
      proof_invariant: sorted_range(xs, 0, i),
      proof_reasoning: (
        #| The outer loop maintains that xs[0..i) is sorted.
        #| For each element at position i, the inner loop shifts
        #| all elements greater than xs[i] one position to the right,
        #| then places xs[i] in the gap. This extends the sorted
        #| prefix from [0, i) to [0, i+1).
        #|
        #| When the outer loop completes, i == n,
        #| so the entire array is sorted.
      ),
    }
  }
}

test "insertion_sort: basic" {
  let xs = FixedArray::makei(5, fn(i) { 5 - i })  // [5, 4, 3, 2, 1]
  insertion_sort(xs)
  assert_eq(xs[0], 1)
  assert_eq(xs[1], 2)
  assert_eq(xs[2], 3)
  assert_eq(xs[3], 4)
  assert_eq(xs[4], 5)
}

test "insertion_sort: already sorted" {
  let xs = FixedArray::makei(5, fn(i) { i })  // [0, 1, 2, 3, 4]
  insertion_sort(xs)
  for k = 0; k < 5; k = k + 1 {
    assert_eq(xs[k], k)
  }
}

test "insertion_sort: reverse sorted" {
  let xs = FixedArray::makei(10, fn(i) { 9 - i })  // [9, 8, ..., 0]
  insertion_sort(xs)
  for k = 0; k < 10; k = k + 1 {
    assert_eq(xs[k], k)
  }
}

test "insertion_sort: single element" {
  let xs = FixedArray::make(1, 42)
  insertion_sort(xs)
  assert_eq(xs[0], 42)
}

test "insertion_sort: empty array" {
  let xs = FixedArray::make(0, 0)
  insertion_sort(xs)
  assert_eq(xs.length(), 0)
}

test "insertion_sort: duplicates" {
  let xs = FixedArray::makei(8, fn(i) { i % 3 })  // [0,1,2,0,1,2,0,1]
  insertion_sort(xs)
  assert_eq(xs[0], 0)
  assert_eq(xs[1], 0)
  assert_eq(xs[2], 0)
  assert_eq(xs[3], 1)
  assert_eq(xs[4], 1)
  assert_eq(xs[5], 1)
  assert_eq(xs[6], 2)
  assert_eq(xs[7], 2)
}

test "insertion_sort: negative values" {
  let xs = FixedArray::makei(5, fn(i) { i - 2 })  // [-2, -1, 0, 1, 2]
  insertion_sort(xs)
  for k = 0; k < 5; k = k + 1 {
    assert_eq(xs[k], k - 2)
  }
}

test "insertion_sort: all equal" {
  let xs = FixedArray::make(6, 7)
  insertion_sort(xs)
  for k = 0; k < 6; k = k + 1 {
    assert_eq(xs[k], 7)
  }
}

test "insertion_sort: two elements" {
  let xs = FixedArray::makei(2, fn(i) { 1 - i })  // [1, 0]
  insertion_sort(xs)
  assert_eq(xs[0], 0)
  assert_eq(xs[1], 1)
}

test "insertion_sort: large random-like" {
  let xs = FixedArray::makei(20, fn(i) { (i * 7 + 3) % 13 })
  insertion_sort(xs)
  for k = 0; k < 19; k = k + 1 {
    assert_eq(xs[k] <= xs[k + 1], true)
  }
}
