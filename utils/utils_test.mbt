///|
/// Comprehensive tests for shared utility functions.

// ===========================================================================
// str_cmp tests
// ===========================================================================

test "str_cmp: equal strings" {
  assert_eq(str_cmp("hello", "hello"), 0)
}

///|
test "str_cmp: first shorter" {
  assert_true(str_cmp("abc", "abcd") < 0)
}

///|
test "str_cmp: first longer" {
  assert_true(str_cmp("abcd", "abc") > 0)
}

///|
test "str_cmp: lexicographic order a < b" {
  assert_true(str_cmp("apple", "banana") < 0)
}

///|
test "str_cmp: lexicographic order b > a" {
  assert_true(str_cmp("banana", "apple") > 0)
}

///|
test "str_cmp: same prefix different next char" {
  assert_true(str_cmp("abc", "abd") < 0)
  assert_true(str_cmp("abd", "abc") > 0)
}

///|
test "str_cmp: empty strings" {
  assert_eq(str_cmp("", ""), 0)
}

///|
test "str_cmp: empty vs non-empty" {
  assert_true(str_cmp("", "a") < 0)
  assert_true(str_cmp("a", "") > 0)
}

///|
test "str_cmp: case sensitive" {
  assert_true(str_cmp("Apple", "apple") < 0)
  assert_true(str_cmp("apple", "Apple") > 0)
}

///|
test "str_cmp: differs from MoonBit default Compare" {
  // MoonBit's default Compare is shortlex (length-first),
  // but str_cmp is lexicographic (character-by-character).
  // Example: "b" vs "aa"
  //   shortlex: "b" < "aa" (length 1 < 2)
  //   lexicographic: "b" > "aa" ('b' > 'a')
  assert_true(str_cmp("b", "aa") > 0)
}

///|
test "str_cmp: single character strings" {
  assert_true(str_cmp("a", "b") < 0)
  assert_true(str_cmp("b", "a") > 0)
  assert_eq(str_cmp("a", "a"), 0)
}

///|
test "str_cmp: used as comparator for sorting" {
  let arr = FixedArray::make(4, "")
  arr[0] = "cherry"
  arr[1] = "apple"
  arr[2] = "date"
  arr[3] = "banana"
  // Simple insertion sort using str_cmp
  for i = 1; i < 4; i = i + 1 {
    let key = arr[i]
    let mut j = i - 1
    while j >= 0 && str_cmp(arr[j], key) > 0 {
      arr[j + 1] = arr[j]
      j = j - 1
    }
    arr[j + 1] = key
  }
  assert_eq(arr[0], "apple")
  assert_eq(arr[1], "banana")
  assert_eq(arr[2], "cherry")
  assert_eq(arr[3], "date")
}

// ===========================================================================
// swap_array tests
// ===========================================================================

///|
test "swap_array: basic swap" {
  let arr = [1, 2, 3, 4, 5]
  swap_array(arr, 0, 4)
  assert_eq(arr[0], 5)
  assert_eq(arr[4], 1)
}

///|
test "swap_array: swap with self" {
  let arr = [1, 2, 3]
  swap_array(arr, 1, 1)
  assert_eq(arr[1], 2)
}

///|
test "swap_array: adjacent elements" {
  let arr = [1, 2, 3]
  swap_array(arr, 0, 1)
  assert_eq(arr[0], 2)
  assert_eq(arr[1], 1)
}

///|
test "swap_array: string array" {
  let arr = ["hello", "world"]
  swap_array(arr, 0, 1)
  assert_eq(arr[0], "world")
  assert_eq(arr[1], "hello")
}

///|
test "swap_array: double array" {
  let arr = [1.5, 2.5, 3.5]
  swap_array(arr, 0, 2)
  assert_eq(arr[0], 3.5)
  assert_eq(arr[2], 1.5)
}

// ===========================================================================
// swap_fixed tests
// ===========================================================================

///|
test "swap_fixed: basic swap" {
  let arr = FixedArray::makei(5, fn(i) { i + 1 })
  swap_fixed(arr, 0, 4)
  assert_eq(arr[0], 5)
  assert_eq(arr[4], 1)
}

///|
test "swap_fixed: swap with self" {
  let arr = FixedArray::makei(3, fn(i) { i + 1 })
  swap_fixed(arr, 1, 1)
  assert_eq(arr[1], 2)
}

///|
test "swap_fixed: two elements" {
  let arr = FixedArray::make(2, 42)
  arr[0] = 10
  arr[1] = 20
  swap_fixed(arr, 0, 1)
  assert_eq(arr[0], 20)
  assert_eq(arr[1], 10)
}

///|
test "swap_fixed: string FixedArray" {
  let arr = FixedArray::make(3, "")
  arr[0] = "alpha"
  arr[1] = "beta"
  arr[2] = "gamma"
  swap_fixed(arr, 0, 2)
  assert_eq(arr[0], "gamma")
  assert_eq(arr[2], "alpha")
}

// ===========================================================================
// next_pow2 tests
// ===========================================================================

///|
test "next_pow2: power of two returns itself" {
  assert_eq(next_pow2(1), 1)
  assert_eq(next_pow2(2), 2)
  assert_eq(next_pow2(4), 4)
  assert_eq(next_pow2(8), 8)
  assert_eq(next_pow2(16), 16)
  assert_eq(next_pow2(1024), 1024)
}

///|
test "next_pow2: non-power rounds up" {
  assert_eq(next_pow2(3), 4)
  assert_eq(next_pow2(5), 8)
  assert_eq(next_pow2(7), 8)
  assert_eq(next_pow2(9), 16)
  assert_eq(next_pow2(15), 16)
  assert_eq(next_pow2(17), 32)
}

///|
test "next_pow2: zero returns 1" {
  assert_eq(next_pow2(0), 1)
}

///|
test "next_pow2: negative returns 1" {
  assert_eq(next_pow2(-1), 1)
  assert_eq(next_pow2(-100), 1)
}

///|
test "next_pow2: one returns 1" {
  assert_eq(next_pow2(1), 1)
}

///|
test "next_pow2: large values" {
  assert_eq(next_pow2(1023), 1024)
  assert_eq(next_pow2(1025), 2048)
  assert_eq(next_pow2(65536), 65536)
  assert_eq(next_pow2(65537), 131072)
}

// ===========================================================================
// approx_eq tests
// ===========================================================================

///|
test "approx_eq: equal values" {
  assert_eq(approx_eq(1.0, 1.0), true)
  assert_eq(approx_eq(0.0, 0.0), true)
  assert_eq(approx_eq(-1.0, -1.0), true)
}

///|
test "approx_eq: close values" {
  assert_eq(approx_eq(1.0, 1.0 + 1.0e-10), true)
  assert_eq(approx_eq(1.0, 1.0 - 1.0e-10), true)
}

///|
test "approx_eq: different values" {
  assert_eq(approx_eq(1.0, 2.0), false)
  assert_eq(approx_eq(0.0, 1.0), false)
  assert_eq(approx_eq(-1.0, 1.0), false)
}

///|
test "approx_eq: near zero" {
  assert_eq(approx_eq(0.0, 1.0e-8), true)
  assert_eq(approx_eq(0.0, 1.0e-5), false)
}

///|
test "approx_eq: large values" {
  assert_eq(approx_eq(1.0e10, 1.0e10 + 1.0), true)
  assert_eq(approx_eq(1.0e10, 1.0e10 + 100.0), true)
}

///|
test "approx_eq: negative near zero" {
  assert_eq(approx_eq(-1.0e-8, 0.0), true)
  assert_eq(approx_eq(-1.0e-5, 0.0), false)
}

///|
test "approx_eq: opposite signs near zero" {
  assert_eq(approx_eq(1.0e-9, -1.0e-9), true)
  assert_eq(approx_eq(1.0e-5, -1.0e-5), false)
}

// ===========================================================================
// fresh_seed tests
// ===========================================================================

///|
test "fresh_seed: returns positive value" {
  let s = fresh_seed(0x1A2B3C4D)
  assert_true(s > 0)
}

///|
test "fresh_seed: returns non-zero" {
  let s = fresh_seed(0)
  assert_true(s != 0)
}

///|
test "fresh_seed: consecutive calls return different values" {
  let s1 = fresh_seed(42)
  let s2 = fresh_seed(42)
  assert_true(s1 != s2)
}

///|
test "fresh_seed: fits in 31 bits" {
  let s = fresh_seed(0x7FFFFFFF)
  assert_true(s >= 1)
  assert_true(s <= 0x7FFFFFFF)
}
