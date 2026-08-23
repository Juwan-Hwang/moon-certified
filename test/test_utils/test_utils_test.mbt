///|
test "str_cmp: equal strings" {
  assert_eq(str_cmp("hello", "hello"), 0)
}

///|
test "str_cmp: less than" {
  assert_true(str_cmp("abc", "abd") < 0)
}

///|
test "str_cmp: greater than" {
  assert_true(str_cmp("abd", "abc") > 0)
}

///|
test "str_cmp: empty string" {
  assert_true(str_cmp("", "a") < 0)
  assert_true(str_cmp("a", "") > 0)
  assert_eq(str_cmp("", ""), 0)
}

///|
test "str_cmp: different lengths" {
  assert_true(str_cmp("ab", "abc") < 0)
  assert_true(str_cmp("abc", "ab") > 0)
}

///|
test "expect_some: returns value" {
  let v = expect_some(Some(42), "should be Some")
  assert_eq(v, 42)
}

///|
test "expect_some: fails on None" {
  let n : Int? = None
  let threw = try {
    let _ = @test_utils.expect_some(n, "should fail")
    false
  } catch {
    Failure(_) => true
  }
  assert_true(threw)
}

///|
test "expect_none: passes on None" {
  let n : Int? = None
  expect_none(n, "should be None")
}

///|
test "expect_none: fails on Some" {
  let threw = try {
    let _ = @test_utils.expect_none(Some(1), "should fail")
    false
  } catch {
    Failure(_) => true
  }
  assert_true(threw)
}
