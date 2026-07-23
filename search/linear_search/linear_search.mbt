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

/// Generic linear search. Not formally verified (opaque comparator).
/// Returns Some(index) of the first element equal to key, None if not found.
///
/// Equality is determined by cmp(a, b) == 0.
pub fn[T] search_generic(
  xs : FixedArray[T],
  key : T,
  cmp : (T, T) -> Int,
) -> Int? {
  for i = 0; i < xs.length(); {
    if cmp(xs[i], key) == 0 {
      break Some(i)
    }
    continue i + 1
  } nobreak {
    None
  }
}

test "linear_search: found" {
  let xs = FixedArray::makei(5, fn(i) { i * 3 }) // [0, 3, 6, 9, 12]
  assert_eq(search(xs, 6), Some(2))
  assert_eq(search(xs, 0), Some(0))
  assert_eq(search(xs, 12), Some(4))
}

test "linear_search: not found" {
  let xs = FixedArray::makei(5, fn(i) { i * 3 })
  assert_eq(search(xs, 1), None)
  assert_eq(search(xs, 5), None)
  assert_eq(search(xs, 13), None)
}

test "linear_search: empty array" {
  let xs : FixedArray[Int] = FixedArray::make(0, 0)
  assert_eq(search(xs, 42), None)
}

test "linear_search: duplicates" {
  let xs = FixedArray::makei(6, fn(i) { if i < 3 { 1 } else { 2 } }) // [1,1,1,2,2,2]
  let result = search(xs, 1)
  // Should return the first occurrence
  match result {
    Some(idx) => assert_eq(idx < 3, true)
    None => abort("should find 1")
  }
}

test "linear_search_generic: Int found" {
  let xs = FixedArray::makei(5, fn(i) { i * 3 }) // [0, 3, 6, 9, 12]
  assert_eq(search_generic(xs, 6, fn(a, b) { a - b }), Some(2))
  assert_eq(search_generic(xs, 0, fn(a, b) { a - b }), Some(0))
}

test "linear_search_generic: Int not found" {
  let xs = FixedArray::makei(5, fn(i) { i * 3 })
  assert_true(search_generic(xs, 5, fn(a, b) { a - b }) is None)
}

test "linear_search_generic: empty array" {
  let xs : FixedArray[Int] = FixedArray::make(0, 0)
  assert_true(search_generic(xs, 42, fn(a, b) { a - b }) is None)
}

test "linear_search_generic: String" {
  let xs = FixedArray::make(4, "")
  xs[0] = "red"
  xs[1] = "green"
  xs[2] = "blue"
  xs[3] = "yellow"
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
  assert_eq(search_generic(xs, "blue", str_cmp), Some(2))
  assert_true(search_generic(xs, "purple", str_cmp) is None)
}
