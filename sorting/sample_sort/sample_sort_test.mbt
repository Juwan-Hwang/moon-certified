///|
test "sample_sort_empty" {
  let result = sample_sort([])
  assert_eq(result.length(), 0)
}

///|
test "sample_sort_single" {
  let result = sample_sort([42])
  assert_eq(result, [42])
}

///|
test "sample_sort_small" {
  let result = sample_sort([3, 1, 2])
  assert_eq(result, [1, 2, 3])
}

///|
test "sample_sort_sorted" {
  let result = sample_sort([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
  assert_eq(result, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
}

///|
test "sample_sort_reverse" {
  let result = sample_sort([10, 9, 8, 7, 6, 5, 4, 3, 2, 1])
  assert_eq(result, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
}

///|
test "sample_sort_duplicates" {
  let result = sample_sort([5, 3, 5, 1, 5, 3, 1, 5, 3, 1])
  assert_eq(result, [1, 1, 1, 3, 3, 3, 5, 5, 5, 5])
}

///|
test "sample_sort_large" {
  let arr : Array[Int] = []
  for i = 0; i < 1000; i = i + 1 {
    arr.push((i * 37 + 13) % 1000)
  }
  let result = sample_sort(arr)
  assert_eq(result.length(), 1000)
  for i = 0; i < 999; i = i + 1 {
    assert_true(result[i] <= result[i + 1])
  }
}

///|
test "sample_sort_all_same" {
  let arr : Array[Int] = Array::make(500, 42)
  let result = sample_sort(arr)
  assert_eq(result.length(), 500)
  for i = 0; i < 500; i = i + 1 {
    assert_eq(result[i], 42)
  }
}

///|
test "sample_sort_double" {
  let arr : Array[Double] = [3.14, 1.41, 2.72, 0.58, 1.73]
  let result = sample_sort_double(arr)
  assert_eq(result.length(), 5)
  assert_true(result[0] <= result[1])
  assert_true(result[1] <= result[2])
  assert_true(result[2] <= result[3])
  assert_true(result[3] <= result[4])
}

///|
test "sample_sort_negative" {
  let result = sample_sort([5, -3, 0, -1, 4, -2, 3, -4, 1, -5, 2])
  assert_eq(result, [-5, -4, -3, -2, -1, 0, 1, 2, 3, 4, 5])
}

///|
test "sample_sort_stress" {
  let arr : Array[Int] = []
  for i = 0; i < 5000; i = i + 1 {
    arr.push((i * 7919 + 31) % 10000)
  }
  let result = sample_sort(arr)
  assert_eq(result.length(), 5000)
  for i = 0; i < 4999; i = i + 1 {
    assert_true(result[i] <= result[i + 1])
  }
}
