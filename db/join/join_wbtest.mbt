// White-box tests for db/join
//
// Exercises every public join algorithm: hash_join, nested_loop_join,
// merge_join, semi_join, anti_join. Includes basic correctness, edge
// cases (empty inputs, no-match, one-to-many), and out-of-bounds key
// handling.

///|
fn arr_eq(a : Array[Int], b : Array[Int]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i = 0; i < a.length(); i = i + 1 {
    if !(a[i] == b[i]) {
      return false
    }
  }
  true
}

///|
fn contains_row(rows : Array[Row], r : Row) -> Bool {
  for x in rows {
    if arr_eq(x.values, r.values) {
      return true
    }
  }
  false
}

///|
fn assert_row_multiset_eq(
  actual : Array[Row],
  expected : Array[Row],
) -> Unit raise {
  assert_eq(actual.length(), expected.length())
  for e in expected {
    assert_true(contains_row(actual, e))
  }
}

///|
fn row(values : Array[Int]) -> Row {
  { values, }
}

// ---------------------------------------------------------------------------
// hash_join
// ---------------------------------------------------------------------------

///|
test "hash_join_basic" {
  let left = [row([1, 10]), row([2, 20]), row([3, 30])]
  let right = [row([1, 100]), row([2, 200])]
  let result = hash_join(left, right, 0, 0)
  assert_row_multiset_eq(result, [row([1, 10, 1, 100]), row([2, 20, 2, 200])])
}

///|
test "hash_join_one_to_many" {
  let left = [row([1, 10])]
  let right = [row([1, 100]), row([1, 200]), row([1, 300])]
  let result = hash_join(left, right, 0, 0)
  assert_row_multiset_eq(result, [
    row([1, 10, 1, 100]),
    row([1, 10, 1, 200]),
    row([1, 10, 1, 300]),
  ])
}

///|
test "hash_join_no_match" {
  let left = [row([1, 10]), row([2, 20])]
  let right = [row([5, 500]), row([6, 600])]
  let result = hash_join(left, right, 0, 0)
  assert_eq(result.length(), 0)
}

///|
test "hash_join_empty_left" {
  let left : Array[Row] = []
  let right = [row([1, 100])]
  let result = hash_join(left, right, 0, 0)
  assert_eq(result.length(), 0)
}

///|
test "hash_join_empty_right" {
  let left = [row([1, 10])]
  let right : Array[Row] = []
  let result = hash_join(left, right, 0, 0)
  assert_eq(result.length(), 0)
}

///|
test "hash_join_nonzero_key_column" {
  let left = [row([0, 1, 10])] // join key at index 1 == 1
  let right = [row([9, 1, 100])] // join key at index 1 == 1
  let result = hash_join(left, right, 1, 1)
  assert_row_multiset_eq(result, [row([0, 1, 10, 9, 1, 100])])
}

///|
test "hash_join_left_key_out_of_bounds_skipped" {
  // left row [1] has length 1, so left_key=1 is out of bounds -> skipped.
  let left = [row([1]), row([2, 20])]
  let right = [row([1, 100]), row([2, 200])]
  let result = hash_join(left, right, 1, 0)
  // only left row [2,20] (key 20) is hashed; no right key matches 20
  assert_eq(result.length(), 0)
}

// ---------------------------------------------------------------------------
// nested_loop_join
// ---------------------------------------------------------------------------

///|
test "nested_loop_join_basic" {
  let outer = [row([1, 10]), row([2, 20])]
  let inner = [row([1, 100]), row([2, 200]), row([3, 300])]
  let result = nested_loop_join(outer, inner, 0, 0)
  assert_row_multiset_eq(result, [row([1, 10, 1, 100]), row([2, 20, 2, 200])])
}

///|
test "nested_loop_join_one_to_many" {
  let outer = [row([1, 10])]
  let inner = [row([1, 100]), row([1, 200])]
  let result = nested_loop_join(outer, inner, 0, 0)
  assert_row_multiset_eq(result, [row([1, 10, 1, 100]), row([1, 10, 1, 200])])
}

///|
test "nested_loop_join_no_match" {
  let outer = [row([1, 10]), row([2, 20])]
  let inner = [row([5, 500])]
  let result = nested_loop_join(outer, inner, 0, 0)
  assert_eq(result.length(), 0)
}

///|
test "nested_loop_join_empty_outer" {
  let outer : Array[Row] = []
  let inner = [row([1, 100])]
  let result = nested_loop_join(outer, inner, 0, 0)
  assert_eq(result.length(), 0)
}

///|
test "nested_loop_join_empty_inner" {
  let outer = [row([1, 10])]
  let inner : Array[Row] = []
  let result = nested_loop_join(outer, inner, 0, 0)
  assert_eq(result.length(), 0)
}

///|
test "nested_loop_join_outer_key_oob_skipped" {
  let outer = [row([1]), row([2, 20])] // outer[0] too short for key 1
  let inner = [row([1, 100]), row([2, 200])]
  let result = nested_loop_join(outer, inner, 1, 0)
  // outer[0] skipped; outer[1] key 20 has no inner match
  assert_eq(result.length(), 0)
}

///|
test "nested_loop_join_inner_key_oob_skipped" {
  let outer = [row([1, 10])]
  let inner = [row([1]), row([2, 200])] // inner[0] too short for key 1
  let result = nested_loop_join(outer, inner, 0, 1)
  assert_eq(result.length(), 0)
}

// ---------------------------------------------------------------------------
// merge_join (requires inputs sorted on the join key)
// ---------------------------------------------------------------------------

///|
test "merge_join_basic" {
  let left = [row([1, 10]), row([2, 20]), row([3, 30])]
  let right = [row([1, 100]), row([3, 300])]
  let result = merge_join(left, right, 0, 0)
  assert_row_multiset_eq(result, [row([1, 10, 1, 100]), row([3, 30, 3, 300])])
}

///|
test "merge_join_no_overlap" {
  let left = [row([1, 10]), row([2, 20])]
  let right = [row([5, 500]), row([6, 600])]
  let result = merge_join(left, right, 0, 0)
  assert_eq(result.length(), 0)
}

///|
test "merge_join_empty" {
  let left : Array[Row] = []
  let right = [row([1, 100])]
  let result = merge_join(left, right, 0, 0)
  assert_eq(result.length(), 0)
}

///|
test "merge_join_short_key_breaks" {
  // left[0] has length 1 but left_key=1 -> loop breaks immediately,
  // returning no rows.
  let left = [row([1]), row([2, 20])]
  let right = [row([1, 100])]
  let result = merge_join(left, right, 1, 0)
  assert_eq(result.length(), 0)
}

// ---------------------------------------------------------------------------
// semi_join
// ---------------------------------------------------------------------------

///|
test "semi_join_basic" {
  let left = [row([1, 10]), row([2, 20]), row([3, 30])]
  let right = [row([2, 200]), row([3, 300])]
  let result = semi_join(left, right, 0, 0)
  assert_row_multiset_eq(result, [row([2, 20]), row([3, 30])])
}

///|
test "semi_join_none" {
  let left = [row([1, 10]), row([2, 20])]
  let right = [row([5, 500])]
  let result = semi_join(left, right, 0, 0)
  assert_eq(result.length(), 0)
}

///|
test "semi_join_empty_left" {
  let left : Array[Row] = []
  let right = [row([1, 100])]
  let result = semi_join(left, right, 0, 0)
  assert_eq(result.length(), 0)
}

// ---------------------------------------------------------------------------
// anti_join
// ---------------------------------------------------------------------------

///|
test "anti_join_basic" {
  let left = [row([1, 10]), row([2, 20]), row([3, 30])]
  let right = [row([2, 200])]
  let result = anti_join(left, right, 0, 0)
  assert_row_multiset_eq(result, [row([1, 10]), row([3, 30])])
}

///|
test "anti_join_all_match" {
  let left = [row([1, 10]), row([2, 20])]
  let right = [row([1, 100]), row([2, 200]), row([3, 300])]
  let result = anti_join(left, right, 0, 0)
  assert_eq(result.length(), 0)
}

///|
test "anti_join_empty_right" {
  let left = [row([1, 10]), row([2, 20])]
  let right : Array[Row] = []
  let result = anti_join(left, right, 0, 0)
  assert_row_multiset_eq(result, [row([1, 10]), row([2, 20])])
}
