///|
test "block_merge_sort_empty" {
  let arr : Array[Int] = []
  block_merge_sort(arr)
  assert_eq(arr.length(), 0)
}

///|
test "block_merge_sort_single" {
  let arr = [42]
  block_merge_sort(arr)
  assert_eq(arr, [42])
}

///|
test "block_merge_sort_small" {
  let arr = [3, 1, 2]
  block_merge_sort(arr)
  assert_eq(arr, [1, 2, 3])
}

///|
test "block_merge_sort_sorted" {
  let arr = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
  block_merge_sort(arr)
  assert_eq(arr, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
}

///|
test "block_merge_sort_reverse" {
  let arr = [10, 9, 8, 7, 6, 5, 4, 3, 2, 1]
  block_merge_sort(arr)
  assert_eq(arr, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
}

///|
test "block_merge_sort_duplicates" {
  let arr = [5, 3, 5, 1, 5, 3, 1, 5, 3, 1]
  block_merge_sort(arr)
  assert_eq(arr, [1, 1, 1, 3, 3, 3, 5, 5, 5, 5])
}

///|
test "block_merge_sort_large" {
  let arr : Array[Int] = []
  for i = 0; i < 1000; i = i + 1 {
    arr.push((i * 37 + 13) % 1000)
  }
  block_merge_sort(arr)
  assert_eq(arr.length(), 1000)
  for i = 0; i < 999; i = i + 1 {
    assert_true(arr[i] <= arr[i + 1])
  }
}

///|
test "block_merge_sort_all_same" {
  let arr : Array[Int] = Array::make(500, 42)
  block_merge_sort(arr)
  assert_eq(arr.length(), 500)
  for i = 0; i < 500; i = i + 1 {
    assert_eq(arr[i], 42)
  }
}

///|
test "block_merge_sort_double" {
  let arr : Array[Double] = [3.14, 1.41, 2.72, 0.58, 1.73]
  block_merge_sort_double(arr)
  assert_eq(arr.length(), 5)
  assert_true(arr[0] <= arr[1])
  assert_true(arr[1] <= arr[2])
  assert_true(arr[2] <= arr[3])
  assert_true(arr[3] <= arr[4])
}

///|
test "block_merge_sort_negative" {
  let arr = [5, -3, 0, -1, 4, -2, 3, -4, 1, -5, 2]
  block_merge_sort(arr)
  assert_eq(arr, [-5, -4, -3, -2, -1, 0, 1, 2, 3, 4, 5])
}

///|
test "block_merge_sort_stress" {
  let arr : Array[Int] = []
  for i = 0; i < 5000; i = i + 1 {
    arr.push((i * 7919 + 31) % 10000)
  }
  block_merge_sort(arr)
  assert_eq(arr.length(), 5000)
  for i = 0; i < 4999; i = i + 1 {
    assert_true(arr[i] <= arr[i + 1])
  }
}

///|
test "block_merge_sort_block_boundary" {
  // Test with arrays around block size boundaries
  for n in [31, 32, 33, 63, 64, 65, 127, 128, 129] {
    let arr : Array[Int] = []
    for i = 0; i < n; i = i + 1 {
      arr.push((n - i) * 7 % 100)
    }
    block_merge_sort(arr)
    for i = 0; i < n - 1; i = i + 1 {
      assert_true(arr[i] <= arr[i + 1])
    }
  }
}
