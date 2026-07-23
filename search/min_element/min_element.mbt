/// Find the index of the minimum element in a non-empty array.
/// Verified: the returned index is valid and xs[result] <= xs[k] for all k.
pub fn min_element(
  xs : FixedArray[Int],
) -> Int where {
  proof_require: 0 < xs.length(),
  proof_ensure: result => min_ok(xs, result),
} {
  for i = 1, best = 0; i < xs.length(); {
    if xs[i] < xs[best] {
      proof_assert xs[i] < xs[best]
      continue i + 1, i
    } else {
      proof_assert xs[best] <= xs[i]
      continue i + 1, best
    }
  } nobreak {
    best
  } where {
    proof_invariant: 0 <= i,
    proof_invariant: i <= xs.length(),
    proof_invariant: 0 <= best,
    proof_invariant: best < i,
    proof_invariant: ∀ k : Int, (0 <= k) && (k < i) → xs[best] <= xs[k],
    proof_reasoning: (
      #| The loop maintains `best` as the index of the minimum element
      #| in the prefix `xs[0..i)`.
      #|
      #| At each step, if `xs[i] < xs[best]`, the new best is `i`.
      #| Otherwise, `best` stays the same since `xs[best] <= xs[i]`.
      #|
      #| When the loop exits, `i == xs.length()`, so `best` is the
      #| index of the minimum over the entire array.
    ),
  }
}

/// Generic min element. Returns index of the minimum element, or None if empty.
/// Not formally verified (opaque comparator).
///
/// Comparator convention: cmp(a, b) returns negative if a < b,
/// zero if a == b, positive if a > b.
pub fn[T] min_element_generic(
  xs : FixedArray[T],
  cmp : (T, T) -> Int,
) -> Int? {
  if xs.length() == 0 {
    return None
  }
  for i = 1, best = 0; i < xs.length(); {
    if cmp(xs[i], xs[best]) < 0 {
      continue i + 1, i
    } else {
      continue i + 1, best
    }
  } nobreak {
    Some(best)
  }
}

test "min_element: basic" {
  let xs = FixedArray::makei(5, fn(i) { 10 - i }) // [10, 9, 8, 7, 6]
  assert_eq(min_element(xs), 4)
}

test "min_element: first element" {
  let xs = FixedArray::makei(4, fn(i) { i }) // [0, 1, 2, 3]
  assert_eq(min_element(xs), 0)
}

test "min_element: all equal" {
  let xs = FixedArray::make(5, 3) // [3, 3, 3, 3, 3]
  let result = min_element(xs)
  assert_eq(xs[result], 3)
}

test "min_element: negative and positive" {
  let xs = FixedArray::makei(4, fn(i) { i - 2 }) // [-2, -1, 0, 1]
  assert_eq(min_element(xs), 0)
}

test "min_element_generic: Int" {
  let xs = FixedArray::makei(5, fn(i) { 10 - i }) // [10, 9, 8, 7, 6]
  assert_eq(min_element_generic(xs, fn(a, b) { a - b }).unwrap(), 4)
  let xs2 = FixedArray::makei(4, fn(i) { i }) // [0, 1, 2, 3]
  assert_eq(min_element_generic(xs2, fn(a, b) { a - b }).unwrap(), 0)
}

test "min_element_generic: String" {
  let xs = FixedArray::make(3, "")
  xs[0] = "cherry"
  xs[1] = "apple"
  xs[2] = "banana"
  /// Lexicographic string comparator (MoonBit's default Compare uses shortlex).
  let str_cmp = fn(a : String, b : String) -> Int {
    let la = a.length()
    let lb = b.length()
    let min = if la < lb { la } else { lb }
    for k = 0; k < min; k = k + 1 {
      let ca = a[k].to_int()
      let cb = b[k].to_int()
      if ca < cb { return -1 }
      if ca > cb { return 1 }
    }
    la - lb
  }
  assert_eq(min_element_generic(xs, str_cmp).unwrap(), 1)
}

test "min_element_generic: empty array returns None" {
  let xs : FixedArray[Int] = FixedArray::make(0, 0)
  assert_true(min_element_generic(xs, fn(a, b) { a - b }) is None)
}
