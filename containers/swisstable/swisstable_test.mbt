///|
test "swisstable_empty" {
  let t = new()
  assert_true(is_empty(t))
  assert_eq(size(t), 0)
  assert_eq(capacity(t), 16)
}

///|
test "swisstable_insert_get" {
  let t = new()
  let _ = insert(t, 42, 100)
  assert_eq(size(t), 1)
  assert_true(contains(t, 42))
  assert_true(get(t, 42) == Some(100))
  assert_true(get(t, 99) == None)
  assert_false(contains(t, 99))
}

///|
test "swisstable_insert_update" {
  let t = new()
  let _ = insert(t, 1, 10)
  let old = insert(t, 1, 20)
  assert_true(old == Some(10))
  assert_eq(size(t), 1)
  assert_true(get(t, 1) == Some(20))
}

///|
test "swisstable_remove" {
  let t = new()
  let _ = insert(t, 5, 50)
  let _ = insert(t, 10, 100)
  assert_eq(size(t), 2)
  let removed = remove(t, 5)
  assert_true(removed == Some(50))
  assert_eq(size(t), 1)
  assert_false(contains(t, 5))
  assert_true(contains(t, 10))
  // Remove non-existent
  let removed2 = remove(t, 999)
  assert_true(removed2 == None)
}

///|
test "swisstable_resize" {
  let t = new()
  let initial_cap = capacity(t)
  // Insert many items to trigger resize
  for i = 0; i < 100; i = i + 1 {
    let _ = insert(t, i, i * 2)
  }
  assert_eq(size(t), 100)
  assert_true(capacity(t) > initial_cap)
  // All items should be accessible
  for i = 0; i < 100; i = i + 1 {
    assert_true(get(t, i) == Some(i * 2))
  }
}

///|
test "swishtable_negative_keys" {
  let t = new()
  let _ = insert(t, -1, 1)
  let _ = insert(t, -100, 2)
  let _ = insert(t, 0, 3)
  assert_true(get(t, -1) == Some(1))
  assert_true(get(t, -100) == Some(2))
  assert_true(get(t, 0) == Some(3))
  assert_eq(size(t), 3)
}

///|
test "swisstable_clear" {
  let t = new()
  for i = 0; i < 20; i = i + 1 {
    let _ = insert(t, i, i)
  }
  assert_eq(size(t), 20)
  clear(t)
  assert_eq(size(t), 0)
  assert_true(is_empty(t))
  for i = 0; i < 20; i = i + 1 {
    assert_false(contains(t, i))
  }
}

///|
test "swisstable_keys_values" {
  let t = new()
  let _ = insert(t, 3, 30)
  let _ = insert(t, 1, 10)
  let _ = insert(t, 2, 20)
  let ks = keys(t)
  assert_eq(ks.length(), 3)
  let vs = values(t)
  assert_eq(vs.length(), 3)
}

///|
test "swisstable_for_each" {
  let t = new()
  let _ = insert(t, 1, 10)
  let _ = insert(t, 2, 20)
  let _ = insert(t, 3, 30)
  let sum : Array[Int] = [0]
  for_each(t, fn(_k, v) { sum[0] = sum[0] + v })
  assert_eq(sum[0], 60)
}

///|
test "swisstable_insert_remove_insert" {
  let t = new()
  let _ = insert(t, 1, 10)
  let _ = remove(t, 1)
  let _ = insert(t, 1, 20)
  assert_true(get(t, 1) == Some(20))
  assert_eq(size(t), 1)
}

///|
test "swisstable_stress" {
  let t = new()
  // Insert 1000 items
  for i = 0; i < 1000; i = i + 1 {
    let _ = insert(t, i, i * 3)
  }
  assert_eq(size(t), 1000)
  // Verify all
  for i = 0; i < 1000; i = i + 1 {
    assert_true(get(t, i) == Some(i * 3))
  }
  // Remove half
  for i = 0; i < 500; i = i + 1 {
    let _ = remove(t, i)
  }
  assert_eq(size(t), 500)
  // Verify remaining
  for i = 500; i < 1000; i = i + 1 {
    assert_true(get(t, i) == Some(i * 3))
  }
  // Re-insert removed
  for i = 0; i < 500; i = i + 1 {
    let _ = insert(t, i, i * 4)
  }
  assert_eq(size(t), 1000)
  for i = 0; i < 500; i = i + 1 {
    assert_true(get(t, i) == Some(i * 4))
  }
  for i = 500; i < 1000; i = i + 1 {
    assert_true(get(t, i) == Some(i * 3))
  }
}

///|
test "swisstable_load_factor" {
  let t = new_with_cap(32)
  for i = 0; i < 20; i = i + 1 {
    let _ = insert(t, i, i)
  }
  let lf = load_factor(t)
  assert_true(lf > 0.0 && lf < 1.0)
}

///|
test "swisstable_new_with_cap" {
  let t = new_with_cap(100)
  // Should round up to 128
  assert_true(capacity(t) >= 100)
  assert_true((capacity(t) & (capacity(t) - 1)) == 0) // Power of 2
}

///|
test "swisstable_collision_handling" {
  let t = new()
  // Insert keys that may hash to the same bucket
  let _ = insert(t, 0, 0)
  let _ = insert(t, 16, 16)
  let _ = insert(t, 32, 32)
  let _ = insert(t, 48, 48)
  assert_eq(size(t), 4)
  assert_true(get(t, 0) == Some(0))
  assert_true(get(t, 16) == Some(16))
  assert_true(get(t, 32) == Some(32))
  assert_true(get(t, 48) == Some(48))
}
