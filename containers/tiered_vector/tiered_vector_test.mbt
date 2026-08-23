///|
/// Tiered Vector tests
test "tiered_vector: basic push and get" {
  let tv = TieredVector::new(16)
  for i = 0; i < 10; i = i + 1 {
    tv.push_back(i * 10)
  }
  assert_eq(tv.size, 10)
  for i = 0; i < 10; i = i + 1 {
    assert_eq(tv.get(i), i * 10)
  }
}

///|
test "tiered_vector: set and get" {
  let tv = TieredVector::new(16)
  for i = 0; i < 8; i = i + 1 {
    tv.push_back(i)
  }
  tv.set(3, 99)
  tv.set(7, 77)
  assert_eq(tv.get(3), 99)
  assert_eq(tv.get(7), 77)
  assert_eq(tv.get(0), 0)
  assert_eq(tv.get(6), 6)
}

///|
test "tiered_vector: insert_at middle" {
  let tv = TieredVector::new(16)
  for i = 0; i < 6; i = i + 1 {
    tv.push_back(i)
  }
  tv.insert_at(3, 100)
  assert_eq(tv.size, 7)
  assert_eq(tv.get(0), 0)
  assert_eq(tv.get(1), 1)
  assert_eq(tv.get(2), 2)
  assert_eq(tv.get(3), 100)
  assert_eq(tv.get(4), 3)
  assert_eq(tv.get(5), 4)
  assert_eq(tv.get(6), 5)
}

///|
test "tiered_vector: insert_at front" {
  let tv = TieredVector::new(16)
  for i = 0; i < 4; i = i + 1 {
    tv.push_back(i)
  }
  tv.insert_at(0, 999)
  assert_eq(tv.size, 5)
  assert_eq(tv.get(0), 999)
  assert_eq(tv.get(1), 0)
  assert_eq(tv.get(4), 3)
}

///|
test "tiered_vector: insert_at back" {
  let tv = TieredVector::new(16)
  for i = 0; i < 4; i = i + 1 {
    tv.push_back(i)
  }
  tv.insert_at(4, 444)
  assert_eq(tv.size, 5)
  assert_eq(tv.get(3), 3)
  assert_eq(tv.get(4), 444)
}

///|
test "tiered_vector: remove_at middle" {
  let tv = TieredVector::new(16)
  for i = 0; i < 6; i = i + 1 {
    tv.push_back(i)
  }
  let removed = tv.remove_at(2)
  assert_eq(removed, 2)
  assert_eq(tv.size, 5)
  assert_eq(tv.get(0), 0)
  assert_eq(tv.get(1), 1)
  assert_eq(tv.get(2), 3)
  assert_eq(tv.get(3), 4)
  assert_eq(tv.get(4), 5)
}

///|
test "tiered_vector: remove_at front" {
  let tv = TieredVector::new(16)
  for i = 0; i < 5; i = i + 1 {
    tv.push_back(i)
  }
  let removed = tv.remove_at(0)
  assert_eq(removed, 0)
  assert_eq(tv.size, 4)
  assert_eq(tv.get(0), 1)
  assert_eq(tv.get(3), 4)
}

///|
test "tiered_vector: remove_at back" {
  let tv = TieredVector::new(16)
  for i = 0; i < 5; i = i + 1 {
    tv.push_back(i)
  }
  let removed = tv.remove_at(4)
  assert_eq(removed, 4)
  assert_eq(tv.size, 4)
  assert_eq(tv.get(3), 3)
}

///|
test "tiered_vector: stress test large" {
  let tv = TieredVector::new(100)
  for i = 0; i < 100; i = i + 1 {
    tv.push_back(i)
  }
  assert_eq(tv.size, 100)
  for i = 0; i < 100; i = i + 1 {
    assert_eq(tv.get(i), i)
  }
  // Remove half
  for _i = 0; _i < 50; _i = _i + 1 {
    let _ = tv.remove_at(0)
  }
  assert_eq(tv.size, 50)
  for i = 0; i < 50; i = i + 1 {
    assert_eq(tv.get(i), i + 50)
  }
}

///|
test "tiered_vector: to_array" {
  let tv = TieredVector::new(16)
  for i = 0; i < 10; i = i + 1 {
    tv.push_back(i * 3)
  }
  let arr = tv.to_array()
  assert_eq(arr.length(), 10)
  for i = 0; i < 10; i = i + 1 {
    assert_eq(arr[i], i * 3)
  }
}

///|
test "tiered_vector: cross tier boundary" {
  let tv = TieredVector::new(16)
  // tier_capacity = sqrt(16)+1 = 5
  // Push beyond first tier boundary
  for i = 0; i < 12; i = i + 1 {
    tv.push_back(i)
  }
  assert_eq(tv.size, 12)
  for i = 0; i < 12; i = i + 1 {
    assert_eq(tv.get(i), i)
  }
  // Insert at boundary
  tv.insert_at(5, 100)
  assert_eq(tv.get(5), 100)
  assert_eq(tv.get(6), 5)
  assert_eq(tv.size, 13)
  // Remove at boundary
  let _ = tv.remove_at(5)
  assert_eq(tv.get(5), 5)
  assert_eq(tv.size, 12)
}

///|
test "tiered_vector: empty edge case" {
  let tv = TieredVector::new(4)
  tv.push_back(42)
  assert_eq(tv.size, 1)
  assert_eq(tv.get(0), 42)
  let _ = tv.remove_at(0)
  assert_eq(tv.size, 0)
}
