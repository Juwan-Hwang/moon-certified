///|
test "sparse_svd: diagonal matrix" {
  // Diagonal matrix with singular values [3, 1, 2]
  let m = @sparse_matrix.from_triplets(3, 3, [
    (0, 0, 3.0),
    (1, 1, 1.0),
    (2, 2, 2.0),
  ])
  let result = sparse_svd(m, 3, 30, 1.0e-10)
  assert_eq(svd_count(result), 3)
  // Singular values should be [3, 2, 1] in descending order
  assert_true((svd_singular_value(result, 0) - 3.0).abs() < 0.5)
  assert_true((svd_singular_value(result, 1) - 2.0).abs() < 0.5)
  assert_true((svd_singular_value(result, 2) - 1.0).abs() < 0.5)
}

///|
test "sparse_svd: single element" {
  let m = @sparse_matrix.from_triplets(1, 1, [(0, 0, 5.0)])
  let result = sparse_svd(m, 1, 30, 1.0e-10)
  assert_true(svd_count(result) >= 1)
  assert_true((svd_singular_value(result, 0) - 5.0).abs() < 1.0)
}

///|
test "sparse_svd: identity matrix" {
  let m = @sparse_matrix.from_triplets(3, 3, [
    (0, 0, 1.0),
    (1, 1, 1.0),
    (2, 2, 1.0),
  ])
  let result = sparse_svd(m, 3, 30, 1.0e-10)
  assert_true(svd_count(result) >= 1)
  // All singular values should be 1
  assert_true((svd_singular_value(result, 0) - 1.0).abs() < 0.3)
}

///|
test "sparse_svd: rectangular matrix" {
  // 2x3 matrix
  let m = @sparse_matrix.from_triplets(2, 3, [
    (0, 0, 1.0),
    (0, 2, 2.0),
    (1, 1, 3.0),
  ])
  let result = sparse_svd(m, 2, 30, 1.0e-10)
  // Should have at most min(2,3) = 2 singular values
  assert_true(svd_count(result) <= 2)
  // Largest singular value should be >= 3 (due to the [3] entry)
  assert_true(svd_singular_value(result, 0) >= 2.5)
}

///|
test "sparse_svd: singular_values_descending" {
  let m = @sparse_matrix.from_triplets(4, 4, [
    (0, 0, 4.0),
    (1, 1, 3.0),
    (2, 2, 2.0),
    (3, 3, 1.0),
  ])
  let result = sparse_svd(m, 4, 30, 1.0e-10)
  let n = svd_count(result)
  // Check descending order
  for i = 1; i < n; i = i + 1 {
    assert_true(
      svd_singular_value(result, i - 1) >= svd_singular_value(result, i) - 0.5,
    )
  }
}

///|
test "sparse_svd: k_zero" {
  let m = @sparse_matrix.from_triplets(2, 2, [(0, 0, 1.0), (1, 1, 2.0)])
  let result = sparse_svd(m, 0, 30, 1.0e-10)
  assert_eq(svd_count(result), 0)
}

///|
test "sparse_svd: zero_matrix" {
  let m = @sparse_matrix.from_triplets(2, 2, [])
  let result = sparse_svd(m, 2, 30, 1.0e-10)
  // All singular values should be zero or near-zero
  for i = 0; i < svd_count(result); i = i + 1 {
    assert_true(svd_singular_value(result, i) < 1.0)
  }
}

///|
test "sparse_svd: accessors_bounds" {
  let m = @sparse_matrix.from_triplets(2, 2, [(0, 0, 3.0), (1, 1, 4.0)])
  let result = sparse_svd(m, 2, 30, 1.0e-10)
  // Out of bounds access
  assert_eq(svd_singular_value(result, -1), 0.0)
  assert_eq(svd_singular_value(result, 99), 0.0)
  assert_eq(svd_u_vector(result, -1).length(), 0)
  assert_eq(svd_v_vector(result, 99).length(), 0)
}
