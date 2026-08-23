///|
test "art_empty" {
  let tree = art_new()
  assert_eq(art_size(tree), 0)
  assert_true(art_get(tree, [1, 2, 3]) is None)
  assert_false(art_contains(tree, [1, 2, 3]))
}

///|
test "art_insert_get_single" {
  let tree = art_new()
  let key = string_to_bytes("hello")
  let _ = art_insert(tree, key, 42)
  assert_eq(art_size(tree), 1)
  assert_eq(art_get(tree, key), Some(42))
  assert_true(art_contains(tree, key))
}

///|
test "art_insert_update" {
  let tree = art_new()
  let key = string_to_bytes("test")
  let old = art_insert(tree, key, 1)
  assert_true(old is None)
  let old2 = art_insert(tree, key, 2)
  assert_eq(old2, Some(1))
  assert_eq(art_get(tree, key), Some(2))
  assert_eq(art_size(tree), 1)
}

///|
test "art_insert_multiple" {
  let tree = art_new()
  let _ = art_insert(tree, string_to_bytes("apple"), 1)
  let _ = art_insert(tree, string_to_bytes("banana"), 2)
  let _ = art_insert(tree, string_to_bytes("cherry"), 3)
  assert_eq(art_size(tree), 3)
  assert_eq(art_get(tree, string_to_bytes("apple")), Some(1))
  assert_eq(art_get(tree, string_to_bytes("banana")), Some(2))
  assert_eq(art_get(tree, string_to_bytes("cherry")), Some(3))
  assert_true(art_get(tree, string_to_bytes("grape")) is None)
}

///|
test "art_prefix_keys" {
  let tree = art_new()
  let _ = art_insert(tree, string_to_bytes("cat"), 1)
  let _ = art_insert(tree, string_to_bytes("category"), 2)
  assert_eq(art_size(tree), 2)
  assert_eq(art_get(tree, string_to_bytes("cat")), Some(1))
  assert_eq(art_get(tree, string_to_bytes("category")), Some(2))
  assert_true(art_get(tree, string_to_bytes("ca")) is None)
}

///|
test "art_common_prefix" {
  let tree = art_new()
  let _ = art_insert(tree, string_to_bytes("abcdef"), 1)
  let _ = art_insert(tree, string_to_bytes("abcxyz"), 2)
  assert_eq(art_size(tree), 2)
  assert_eq(art_get(tree, string_to_bytes("abcdef")), Some(1))
  assert_eq(art_get(tree, string_to_bytes("abcxyz")), Some(2))
}

///|
test "art_remove" {
  let tree = art_new()
  let _ = art_insert(tree, string_to_bytes("key1"), 10)
  let _ = art_insert(tree, string_to_bytes("key2"), 20)
  let _ = art_insert(tree, string_to_bytes("key3"), 30)
  let removed = art_remove(tree, string_to_bytes("key2"))
  assert_eq(removed, Some(20))
  assert_eq(art_size(tree), 2)
  assert_true(art_get(tree, string_to_bytes("key2")) is None)
  assert_eq(art_get(tree, string_to_bytes("key1")), Some(10))
  assert_eq(art_get(tree, string_to_bytes("key3")), Some(30))
}

///|
test "art_remove_nonexistent" {
  let tree = art_new()
  let _ = art_insert(tree, string_to_bytes("a"), 1)
  let removed = art_remove(tree, string_to_bytes("b"))
  assert_true(removed is None)
  assert_eq(art_size(tree), 1)
}

///|
test "art_remove_all" {
  let tree = art_new()
  let _ = art_insert(tree, string_to_bytes("x"), 1)
  let _ = art_insert(tree, string_to_bytes("y"), 2)
  let _ = art_remove(tree, string_to_bytes("x"))
  let _ = art_remove(tree, string_to_bytes("y"))
  assert_eq(art_size(tree), 0)
}

///|
test "art_iterate" {
  let tree = art_new()
  let _ = art_insert(tree, string_to_bytes("delta"), 4)
  let _ = art_insert(tree, string_to_bytes("alpha"), 1)
  let _ = art_insert(tree, string_to_bytes("charlie"), 3)
  let _ = art_insert(tree, string_to_bytes("bravo"), 2)
  let pairs = art_to_array(tree)
  assert_eq(pairs.length(), 4)
  assert_eq(bytes_to_string(pairs[0].0), "alpha")
  assert_eq(pairs[0].1, 1)
  assert_eq(bytes_to_string(pairs[1].0), "bravo")
  assert_eq(pairs[1].1, 2)
  assert_eq(bytes_to_string(pairs[2].0), "charlie")
  assert_eq(pairs[2].1, 3)
  assert_eq(bytes_to_string(pairs[3].0), "delta")
  assert_eq(pairs[3].1, 4)
}

///|
test "art_single_byte_keys" {
  let tree = art_new()
  for i = 0; i < 26; i = i + 1 {
    let _ = art_insert(tree, [65 + i], i)
  }
  assert_eq(art_size(tree), 26)
  for i = 0; i < 26; i = i + 1 {
    assert_eq(art_get(tree, [65 + i]), Some(i))
  }
}

///|
test "art_numeric_keys" {
  let tree = art_new()
  for i = 0; i < 256; i = i + 1 {
    let _ = art_insert(tree, [i], i * 10)
  }
  assert_eq(art_size(tree), 256)
  for i = 0; i < 256; i = i + 1 {
    assert_eq(art_get(tree, [i]), Some(i * 10))
  }
}

///|
test "art_long_keys" {
  let tree = art_new()
  let _ = art_insert(tree, string_to_bytes("aaaaaaaaaa"), 1)
  let _ = art_insert(tree, string_to_bytes("aaaaaabbbbb"), 2)
  let _ = art_insert(tree, string_to_bytes("aaaaaaccccc"), 3)
  assert_eq(art_get(tree, string_to_bytes("aaaaaaaaaa")), Some(1))
  assert_eq(art_get(tree, string_to_bytes("aaaaaabbbbb")), Some(2))
  assert_eq(art_get(tree, string_to_bytes("aaaaaaccccc")), Some(3))
}

///|
test "art_stress" {
  let tree = art_new()
  for i = 0; i < 200; i = i + 1 {
    let key = [i / 256, i % 256]
    let _ = art_insert(tree, key, i)
  }
  assert_eq(art_size(tree), 200)
  for i = 0; i < 200; i = i + 1 {
    let key = [i / 256, i % 256]
    assert_eq(art_get(tree, key), Some(i))
  }
  for i = 0; i < 100; i = i + 1 {
    let key = [i / 256, i % 256]
    let r = art_remove(tree, key)
    assert_eq(r, Some(i))
  }
  assert_eq(art_size(tree), 100)
  for i = 100; i < 200; i = i + 1 {
    let key = [i / 256, i % 256]
    assert_eq(art_get(tree, key), Some(i))
  }
}

///|
test "art_empty_key" {
  let tree = art_new()
  let key : Array[Int] = []
  let _ = art_insert(tree, key, 99)
  assert_eq(art_size(tree), 1)
  assert_eq(art_get(tree, []), Some(99))
}

///|
test "art_insert_remove_reinsert" {
  let tree = art_new()
  let _ = art_insert(tree, [1, 2, 3], 10)
  let _ = art_insert(tree, [1, 2, 4], 20)
  let _ = art_remove(tree, [1, 2, 3])
  let _ = art_remove(tree, [1, 2, 4])
  assert_eq(art_size(tree), 0)
  let _ = art_insert(tree, [1, 2, 3], 30)
  assert_eq(art_size(tree), 1)
  assert_eq(art_get(tree, [1, 2, 3]), Some(30))
}
