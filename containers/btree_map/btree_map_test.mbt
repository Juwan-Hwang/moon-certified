// White-box tests for BTreeMap.
// NOTE: This is a simplified B-tree implementation. `insert` only succeeds while
// the root stays a leaf with n < 5 (i.e. at most 5 keys); overflow is silently
// ignored. `remove` only works on a leaf root. Tests stay within these limits.

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
fn unwrap_pair(opt : (Int, Int)?) -> (Int, Int) {
  match opt {
    Some(v) => v
    None => abort("expected Some pair, got None")
  }
}

///|
test "btree_map_empty" {
  let m = BTreeMap::new()
  assert_eq(m.size, 0)
  expect_none_int(m.get(1))
  assert_eq(m.to_array(), [])
  assert_true(m.first() is None)
  assert_true(m.last() is None)
}

///|
test "btree_map_insert_single" {
  let m = BTreeMap::new()
  m.insert(42, 420)
  assert_eq(m.size, 1)
  assert_eq(unwrap_int(m.get(42)), 420)
  expect_none_int(m.get(0))
  assert_eq(unwrap_pair(m.first()), (42, 420))
  assert_eq(unwrap_pair(m.last()), (42, 420))
}

///|
test "btree_map_insert_update" {
  let m = BTreeMap::new()
  m.insert(7, 70)
  m.insert(7, 77)
  // Update keeps size, changes value
  assert_eq(m.size, 1)
  assert_eq(unwrap_int(m.get(7)), 77)
}

///|
test "btree_map_insert_multiple_sorted" {
  let m = BTreeMap::new()
  // 5 distinct keys (capacity limit of simplified root leaf)
  m.insert(3, 30)
  m.insert(1, 10)
  m.insert(4, 40)
  m.insert(5, 50)
  m.insert(9, 90)
  assert_eq(m.size, 5)
  assert_eq(m.to_array(), [(1, 10), (3, 30), (4, 40), (5, 50), (9, 90)])
  // in-order traversal is sorted
  assert_eq(unwrap_pair(m.first()), (1, 10))
  assert_eq(unwrap_pair(m.last()), (9, 90))
  // every key resolves to its value
  assert_eq(unwrap_int(m.get(3)), 30)
  assert_eq(unwrap_int(m.get(1)), 10)
  assert_eq(unwrap_int(m.get(4)), 40)
  assert_eq(unwrap_int(m.get(5)), 50)
  assert_eq(unwrap_int(m.get(9)), 90)
  expect_none_int(m.get(2))
}

///|
test "btree_map_remove" {
  let m = BTreeMap::new()
  m.insert(3, 30)
  m.insert(1, 10)
  m.insert(4, 40)
  m.insert(5, 50)
  m.insert(9, 90)
  let removed = m.remove(4)
  assert_true(removed)
  assert_eq(m.size, 4)
  expect_none_int(m.get(4))
  assert_eq(m.to_array(), [(1, 10), (3, 30), (5, 50), (9, 90)])
  // removing a non-existent key returns false and is a no-op
  let removed2 = m.remove(100)
  assert_false(removed2)
  assert_eq(m.size, 4)
}

///|
test "btree_map_remove_first_and_last" {
  let m = BTreeMap::new()
  m.insert(3, 30)
  m.insert(1, 10)
  m.insert(4, 40)
  let _ = m.remove(1)
  assert_eq(unwrap_pair(m.first()), (3, 30))
  let _ = m.remove(4)
  assert_eq(unwrap_pair(m.last()), (3, 30))
  let _ = m.remove(3)
  assert_eq(m.size, 0)
  assert_true(m.first() is None)
  assert_true(m.last() is None)
  assert_eq(m.to_array(), [])
}

///|
test "btree_map_all_at_capacity" {
  // Insert exactly the 5-key capacity and verify nothing is lost.
  let m = BTreeMap::new()
  for i = 0; i < 5; i = i + 1 {
    m.insert(i * 2, i)
  }
  assert_eq(m.size, 5)
  for i = 0; i < 5; i = i + 1 {
    assert_eq(unwrap_int(m.get(i * 2)), i)
  }
}
