// ===========================================================================
// PQ Model Training Tests
// ===========================================================================

///|
test "pq_train_basic" {
  // 8 vectors of dimension 4, 2 sub-quantizers, 4 centroids each
  let data = [
    1.0, 0.0, 0.0, 0.0, 0.9, 0.1, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.9, 0.1, 0.0,
    0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.9, 0.1, 1.0, 0.0, 1.0, 0.0, 0.0, 1.0, 0.0, 1.0,
  ]
  let model = pq_train(data, 8, 4, 2, 4, 25, 42)
  assert_eq(model.sub_dim, 2)
  assert_eq(model.n_subquantizers, 2)
  assert_eq(model.n_centroids, 4)
  assert_eq(model.centroids.length(), 2 * 4 * 2)
}

///|
test "pq_train_invalid_dim" {
  // dim=5 not divisible by n_subquantizers=2
  let data = [1.0, 0.0, 0.0, 0.0, 0.0]
  let model = pq_train(data, 1, 5, 2, 4, 10, 42)
  assert_eq(model.sub_dim, 0)
  assert_eq(model.n_subquantizers, 0)
}

// ===========================================================================
// Encoding/Decoding Tests
// ===========================================================================

///|
test "pq_encode_decode" {
  let data = [
    1.0, 0.0, 0.0, 0.0, 0.9, 0.1, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.9, 0.1, 0.0,
    0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.9, 0.1, 1.0, 0.0, 1.0, 0.0, 0.0, 1.0, 0.0, 1.0,
  ]
  let model = pq_train(data, 8, 4, 2, 4, 25, 42)
  let vec = [0.95, 0.05, 0.0, 0.0]
  let code = pq_encode(model, vec)
  assert_eq(code.codes.length(), 2)
  let recon = pq_decode(model, code)
  assert_eq(recon.length(), 4)
}

///|
test "pq_encode_batch" {
  let data = [
    1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0,
  ]
  let model = pq_train(data, 4, 4, 2, 4, 25, 42)
  let codes = pq_encode_batch(model, data, 4)
  assert_eq(codes.length(), 4)
  for i = 0; i < 4; i = i + 1 {
    assert_eq(codes[i].codes.length(), 2)
  }
}

// ===========================================================================
// Distance Computation Tests
// ===========================================================================

///|
test "pq_adc_distance_self" {
  // ADC distance from a vector to its own PQ code should be non-negative
  // and bounded by the quantization error
  let data = [
    1.0, 0.0, 0.0, 0.0, 0.9, 0.1, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.9, 0.1, 0.0,
    0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.9, 0.1, 1.0, 0.0, 1.0, 0.0, 0.0, 1.0, 0.0, 1.0,
  ]
  let model = pq_train(data, 8, 4, 2, 4, 25, 42)
  let vec = [1.0, 0.0, 0.0, 0.0]
  let code = pq_encode(model, vec)
  let dist = pq_adc_distance(model, vec, code)
  assert_true(dist >= 0.0)
  // For well-clustered data with the vector being a training point,
  // the quantization error should be small
  assert_true(dist < 0.5)
}

///|
test "pq_adc_distance_nonneg" {
  let data = [
    1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0,
  ]
  let model = pq_train(data, 4, 4, 2, 4, 25, 42)
  let query = [0.5, 0.5, 0.5, 0.5]
  let code = pq_encode(model, data)
  let dist = pq_adc_distance(model, query, code)
  assert_true(dist >= 0.0)
}

///|
test "pq_sdc_distance_self_zero" {
  let data = [
    1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0,
  ]
  let model = pq_train(data, 4, 4, 2, 4, 25, 42)
  let code = pq_encode(model, [1.0, 0.0, 0.0, 0.0])
  let dist = pq_sdc_distance(model, code, code)
  assert_true(dist < 1.0e-10)
}

///|
test "pq_adc_table_consistency" {
  let data = [
    1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0,
  ]
  let model = pq_train(data, 4, 4, 2, 4, 25, 42)
  let query = [0.5, 0.5, 0.5, 0.5]
  let table = pq_adc_table(model, query)
  let code = pq_encode(model, data)
  let d1 = pq_adc_distance(model, query, code)
  let d2 = pq_adc_distance_table(model, table, code)
  assert_true((d1 - d2).abs() < 1.0e-10)
}

// ===========================================================================
// Search Tests
// ===========================================================================

///|
test "pq_search_returns_sorted" {
  let data = [
    1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0,
    2.0, 0.0, 0.0, 0.0, 3.0, 0.0, 0.0, 0.0,
  ]
  let model = pq_train(data, 6, 4, 2, 4, 25, 42)
  let codes = pq_encode_batch(model, data, 6)
  let query = [0.9, 0.0, 0.0, 0.0]
  let results = pq_search(model, query, codes, 3)
  assert_eq(results.length(), 3)
  // Results should be sorted by ascending distance
  assert_true(results[0].distance <= results[1].distance)
  assert_true(results[1].distance <= results[2].distance)
}

///|
test "pq_search_empty" {
  let data = [1.0, 0.0, 0.0, 0.0]
  let model = pq_train(data, 1, 4, 2, 4, 25, 42)
  let results = pq_search(model, [1.0, 0.0, 0.0, 0.0], [], 3)
  assert_eq(results.length(), 0)
}

///|
test "pq_search_k_larger_than_n" {
  let data = [1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0]
  let model = pq_train(data, 2, 4, 2, 4, 25, 42)
  let codes = pq_encode_batch(model, data, 2)
  let results = pq_search(model, [1.0, 0.0, 0.0, 0.0], codes, 10)
  assert_eq(results.length(), 2)
}

// ===========================================================================
// Reconstruction Error Tests
// ===========================================================================

///|
test "pq_reconstruction_error_nonneg" {
  let data = [
    1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0,
    1.0, 0.0, 1.0, 0.0, 0.0, 1.0, 0.0, 1.0, 0.5, 0.5, 0.5, 0.5, 0.3, 0.3, 0.3, 0.3,
  ]
  let model = pq_train(data, 8, 4, 2, 4, 25, 42)
  let err = pq_reconstruction_error(model, data, 8)
  assert_true(err >= 0.0)
}

///|
test "pq_reconstruction_error_zero_for_perfect" {
  // When n_centroids >= n, every point gets its own centroid
  let data = [
    1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0,
  ]
  // k=4 >= n=4, so each point is its own centroid -> zero error
  let model = pq_train(data, 4, 4, 2, 4, 25, 42)
  let err = pq_reconstruction_error(model, data, 4)
  assert_true(err < 1.0e-10)
}

// ===========================================================================
// Accessor Tests
// ===========================================================================

///|
test "pq_accessors" {
  let data = [
    1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0,
  ]
  let model = pq_train(data, 4, 4, 2, 4, 25, 42)
  assert_eq(pq_vector_dim(model), 4)
  assert_eq(pq_num_subquantizers(model), 2)
  assert_eq(pq_num_centroids(model), 4)
}

///|
test "pq_code_construct" {
  let c = pq_code([0, 1, 2, 3])
  assert_eq(c.codes.length(), 4)
  assert_eq(c.codes[0], 0)
  assert_eq(c.codes[3], 3)
}
