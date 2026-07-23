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

/// Generic max element. Returns index of the maximum element.
/// Not formally verified (opaque comparator).
///
/// Requires: xs is non-empty.
/// Comparator convention: cmp(a, b) returns negative if a < b,
/// zero if a == b, positive if a > b.
pub fn[T] max_element_generic(
  xs : FixedArray[T],
  cmp : (T, T) -> Int,
) -> Int {
  for i = 1, best = 0; i < xs.length(); {
    if cmp(xs[i], xs[best]) > 0 {
      continue i + 1, i
    } else {
      continue i + 1, best
    }
  } nobreak {
    best
  }
}

test "max_element: basic" {
  let xs = FixedArray::makei(5, fn(i) { i }) // [0, 1, 2, 3, 4]
  assert_eq(max_element(xs), 4)
}

test "max_element: first element" {
  let xs = FixedArray::makei(4, fn(i) { 10 - i }) // [10, 9, 8, 7]
  assert_eq(max_element(xs), 0)
}

test "max_element: duplicates" {
  let xs = FixedArray::make(5, 7) // [7, 7, 7, 7, 7]
  let result = max_element(xs)
  assert_eq(xs[result], 7)
}

test "max_element: negative values" {
  let xs = FixedArray::makei(3, fn(i) { -(i + 1) }) // [-1, -2, -3]
  assert_eq(max_element(xs), 0)
}

test "max_element_generic: Int" {
  let xs = FixedArray::makei(5, fn(i) { i }) // [0, 1, 2, 3, 4]
  assert_eq(max_element_generic(xs, fn(a, b) { a - b }), 4)
  let xs2 = FixedArray::makei(4, fn(i) { 10 - i }) // [10, 9, 8, 7]
  assert_eq(max_element_generic(xs2, fn(a, b) { a - b }), 0)
}

test "max_element_generic: String" {
  let xs = FixedArray::make(3, "")
  xs[0] = "apple"
  xs[1] = "cherry"
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
  assert_eq(max_element_generic(xs, str_cmp), 1)
}
