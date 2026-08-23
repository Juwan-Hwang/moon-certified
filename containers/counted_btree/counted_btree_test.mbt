// White-box tests for CountedBTree.
// NOTE: Simplified impl only inserts while the root leaf has n < 3 (max 3 keys);
// overflow is silently ignored. `select(rank)` returns the key at that rank
// (0-indexed), while `rank(key)` returns the count of elements < key.

///|
fn unwrap_int(opt : Int?) -> Int {
  match opt {
    Some(v) => v
    None => abort("expected Some, got None")
  }
}

///|
fn expect_none_int(opt : Int?) -> Unit {
  match opt {
    Some(_) => abort("expected None, got Some")
    None => ()
  }
}

///|
test "counted_btree_empty" {
  let t = CountedBTree::new()
  assert_eq(t.size, 0)
  expect_none_int(t.search(1))
  // select out of bounds would abort; just check search surface here
  assert_eq(t.rank(1), 0)
}

///|
test "counted_btree_insert_search" {
  let t = CountedBTree::new()
  t.insert(10, 100)
  assert_eq(t.size, 1)
  assert_eq(unwrap_int(t.search(10)), 100)
  expect_none_int(t.search(99))
}

///|
test "counted_btree_insert_update" {
  let t = CountedBTree::new()
  t.insert(20, 200)
  t.insert(20, 222)
  assert_eq(t.size, 1)
  assert_eq(unwrap_int(t.search(20)), 222)
}

///|
test "counted_btree_select_and_rank" {
  let t = CountedBTree::new()
  // 3 distinct keys (capacity limit)
  t.insert(30, 300)
  t.insert(10, 100)
  t.insert(20, 200)
  assert_eq(t.size, 3)
  // select returns the key at the given rank
  assert_eq(t.select(0), 10)
  assert_eq(t.select(1), 20)
  assert_eq(t.select(2), 30)
  // rank returns the number of elements strictly less than key
  assert_eq(t.rank(5), 0)
  assert_eq(t.rank(10), 0)
  assert_eq(t.rank(15), 1)
  assert_eq(t.rank(20), 1)
  assert_eq(t.rank(25), 2)
  assert_eq(t.rank(30), 2)
  assert_eq(t.rank(35), 3)
  // search still resolves values at each key
  assert_eq(unwrap_int(t.search(10)), 100)
  assert_eq(unwrap_int(t.search(20)), 200)
  assert_eq(unwrap_int(t.search(30)), 300)
}

///|
test "counted_btree_at_capacity" {
  // Insert exactly the 3-key capacity and verify all survive.
  let t = CountedBTree::new()
  for i = 0; i < 3; i = i + 1 {
    t.insert(i, i * 10)
  }
  assert_eq(t.size, 3)
  for i = 0; i < 3; i = i + 1 {
    assert_eq(unwrap_int(t.search(i)), i * 10)
    assert_eq(t.select(i), i)
  }
  assert_eq(t.rank(0), 0)
  assert_eq(t.rank(2), 2)
  assert_eq(t.rank(3), 3)
}
