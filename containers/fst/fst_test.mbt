// White-box tests for Fst (Finite State Transducer).
// `build` takes an array of (String, Int) pairs and constructs a trie-like
// automaton. `search` returns the value for a known key or None. `keys`
// lists all stored keys.

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
test "fst_empty" {
  let f = Fst::build([])
  assert_eq(f.keys(), [])
  expect_none_int(f.search("anything"))
}

///|
test "fst_build_search" {
  let f = Fst::build([("apple", 1), ("banana", 2), ("cherry", 3)])
  assert_eq(unwrap_int(f.search("apple")), 1)
  assert_eq(unwrap_int(f.search("banana")), 2)
  assert_eq(unwrap_int(f.search("cherry")), 3)
  expect_none_int(f.search("grape"))
  expect_none_int(f.search("app"))
  expect_none_int(f.search(""))
}

///|
test "fst_keys_sorted" {
  // Keys inserted in sorted order -> DFS yields them in sorted order.
  let f = Fst::build([("apple", 1), ("banana", 2), ("cherry", 3)])
  assert_eq(f.keys(), ["apple", "banana", "cherry"])
  assert_eq(f.keys().length(), 3)
}

///|
test "fst_prefix_keys" {
  // A key that is a prefix of another, and shared prefixes.
  let f = Fst::build([("cat", 1), ("category", 2), ("dog", 3)])
  assert_eq(unwrap_int(f.search("cat")), 1)
  assert_eq(unwrap_int(f.search("category")), 2)
  assert_eq(unwrap_int(f.search("dog")), 3)
  expect_none_int(f.search("ca"))
  expect_none_int(f.search("categor"))
  let ks = f.keys()
  assert_eq(ks.length(), 3)
  assert_true(ks.contains("cat"))
  assert_true(ks.contains("category"))
  assert_true(ks.contains("dog"))
}

///|
test "fst_update_same_key" {
  // Re-building with the same key last wins for its value.
  let f = Fst::build([("key", 1), ("key", 9)])
  assert_eq(unwrap_int(f.search("key")), 9)
  assert_eq(f.keys().length(), 1)
}

///|
test "fst_single_char_key" {
  let f = Fst::build([("a", 10), ("b", 20), ("ab", 30)])
  assert_eq(unwrap_int(f.search("a")), 10)
  assert_eq(unwrap_int(f.search("b")), 20)
  assert_eq(unwrap_int(f.search("ab")), 30)
  expect_none_int(f.search("c"))
}
