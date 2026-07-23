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

/// Generic binary search on a sorted array. Not formally verified
/// (opaque comparator prevents SMT reasoning).
///
/// Assumes the array is sorted in ascending order according to `cmp`.
/// Returns Some(index) if found, None if not found.
///
/// Comparator convention: cmp(a, b) returns negative if a < b,
/// zero if a == b, positive if a > b.
pub fn[T] search_generic(
  xs : FixedArray[T],
  key : T,
  cmp : (T, T) -> Int,
) -> Int? {
  let mut lo = 0
  let mut hi = xs.length()
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    let c = cmp(xs[mid], key)
    if c < 0 {
      lo = mid + 1
    } else if c > 0 {
      hi = mid
    } else {
      return Some(mid)
    }
  }
  None
}

test "binary_search: found" {
  let xs = FixedArray::makei(5, fn(i) { i * 2 }) // [0, 2, 4, 6, 8]
  assert_eq(search(xs, 4), Some(2))
  assert_eq(search(xs, 0), Some(0))
  assert_eq(search(xs, 8), Some(4))
}

test "binary_search: not found" {
  let xs = FixedArray::makei(5, fn(i) { i * 2 }) // [0, 2, 4, 6, 8]
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

test "binary_search_generic: Int found" {
  let xs = FixedArray::makei(5, fn(i) { i * 2 }) // [0, 2, 4, 6, 8]
  assert_eq(search_generic(xs, 4, fn(a, b) { a - b }), Some(2))
  assert_eq(search_generic(xs, 0, fn(a, b) { a - b }), Some(0))
  assert_eq(search_generic(xs, 8, fn(a, b) { a - b }), Some(4))
}

test "binary_search_generic: Int not found" {
  let xs = FixedArray::makei(5, fn(i) { i * 2 })
  assert_true(search_generic(xs, 1, fn(a, b) { a - b }) is None)
  assert_true(search_generic(xs, 9, fn(a, b) { a - b }) is None)
}

test "binary_search_generic: empty array" {
  let xs : FixedArray[Int] = FixedArray::make(0, 0)
  assert_true(search_generic(xs, 42, fn(a, b) { a - b }) is None)
}

test "binary_search_generic: String" {
  let xs = FixedArray::make(4, "")
  xs[0] = "apple"
  xs[1] = "banana"
  xs[2] = "cherry"
  xs[3] = "date"
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
  assert_eq(search_generic(xs, "cherry", str_cmp), Some(2))
  assert_true(search_generic(xs, "grape", str_cmp) is None)
}
