// White-box tests for MassTree.
// NOTE: Simplified impl inserts into a single root leaf; `insert` only succeeds
// while the leaf has count < 8 (max 8 keys); overflow is silently ignored.
// `to_array` always returns entries in sorted key order.

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
test "mass_tree_empty" {
  let t = MassTree::new()
  assert_eq(t.size, 0)
  expect_none_int(t.search(1))
  assert_eq(t.to_array(), [])
  assert_false(t.delete(1))
}

///|
test "mass_tree_insert_search" {
  let t = MassTree::new()
  t.insert(5, 50)
  assert_eq(t.size, 1)
  assert_eq(unwrap_int(t.search(5)), 50)
  expect_none_int(t.search(99))
}

///|
test "mass_tree_insert_update" {
  let t = MassTree::new()
  t.insert(3, 30)
  t.insert(3, 33)
  assert_eq(t.size, 1)
  assert_eq(unwrap_int(t.search(3)), 33)
}

///|
test "mass_tree_insert_multiple_sorted" {
  let t = MassTree::new()
  // 8 distinct keys (capacity limit of the simplified leaf root)
  t.insert(5, 50)
  t.insert(3, 30)
  t.insert(8, 80)
  t.insert(1, 10)
  t.insert(9, 90)
  t.insert(2, 20)
  t.insert(7, 70)
  t.insert(4, 40)
  assert_eq(t.size, 8)
  assert_eq(t.to_array(), [
    (1, 10),
    (2, 20),
    (3, 30),
    (4, 40),
    (5, 50),
    (7, 70),
    (8, 80),
    (9, 90),
  ])
  // every key resolves to its value
  for i = 1; i <= 9; i = i + 1 {
    if i != 6 {
      assert_eq(unwrap_int(t.search(i)), i * 10)
    } else {
      expect_none_int(t.search(6))
    }
  }
}

///|
test "mass_tree_delete" {
  let t = MassTree::new()
  t.insert(5, 50)
  t.insert(3, 30)
  t.insert(8, 80)
  t.insert(1, 10)
  assert_eq(t.size, 4)
  assert_true(t.delete(3))
  assert_eq(t.size, 3)
  expect_none_int(t.search(3))
  assert_eq(t.to_array(), [(1, 10), (5, 50), (8, 80)])
  // delete missing -> false, no-op
  assert_false(t.delete(100))
  assert_eq(t.size, 3)
  // delete all, empties the tree
  assert_true(t.delete(1))
  assert_true(t.delete(5))
  assert_true(t.delete(8))
  assert_eq(t.size, 0)
  assert_eq(t.to_array(), [])
}

///|
test "mass_tree_first_last_via_array" {
  let t = MassTree::new()
  t.insert(5, 50)
  t.insert(3, 30)
  t.insert(8, 80)
  let arr = t.to_array()
  assert_eq(arr[0], (3, 30)) // min
  assert_eq(arr[arr.length() - 1], (8, 80)) // max
}

///|
test "mass_tree_at_capacity" {
  // Insert exactly the 8-key capacity; nothing lost, all searchable.
  let t = MassTree::new()
  for i = 0; i < 8; i = i + 1 {
    t.insert(i, i * 100)
  }
  assert_eq(t.size, 8)
  for i = 0; i < 8; i = i + 1 {
    assert_eq(unwrap_int(t.search(i)), i * 100)
  }
}
