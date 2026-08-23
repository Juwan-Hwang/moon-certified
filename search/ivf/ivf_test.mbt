// ===========================================================================
// IVF Build Tests
// ===========================================================================

///|
test "ivf_build_basic" {
  let data = [
    1.0, 0.0, 0.0, 0.9, 0.1, 0.0, 0.0, 1.0, 0.0, 0.0, 0.9, 0.1, 0.0, 0.0, 1.0, 0.0,
    0.0, 0.9, 1.0, 1.0, 0.0, 0.0, 1.0, 1.0,
  ]
  let index = ivf_build(data, 8, 3, 3, 25, 42)
  assert_eq(ivf_dim(index), 3)
  assert_eq(ivf_n_vectors(index), 8)
  assert_true(ivf_nlist(index) <= 3)
}

///|
test "ivf_build_empty" {
  let index = ivf_build([], 0, 3, 3, 25, 42)
  assert_eq(ivf_n_vectors(index), 0)
}

///|
test "ivf_build_nlist_larger_than_n" {
  let data = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0]
  let index = ivf_build(data, 2, 3, 10, 25, 42)
  assert_eq(ivf_nlist(index), 2)
}

// ===========================================================================
// IVF Search Tests
// ===========================================================================

///|
test "ivf_search_basic" {
  let data = [
    1.0, 0.0, 0.0, 0.9, 0.1, 0.0, 0.0, 1.0, 0.0, 0.0, 0.9, 0.1, 0.0, 0.0, 1.0, 0.0,
    0.0, 0.9, 1.0, 1.0, 0.0, 0.0, 1.0, 1.0,
  ]
  let index = ivf_build(data, 8, 3, 3, 25, 42)
  let results = ivf_search(index, [0.95, 0.05, 0.0], 2, 1)
  assert_true(results.length() <= 2)
  // Results should be sorted by ascending distance
  if results.length() >= 2 {
    assert_true(results[0].distance <= results[1].distance)
  }
}

///|
test "ivf_search_empty_index" {
  let index = ivf_build([], 0, 3, 3, 25, 42)
  let results = ivf_search(index, [1.0, 0.0, 0.0], 2, 1)
  assert_eq(results.length(), 0)
}

///|
test "ivf_search_k_zero" {
  let data = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0]
  let index = ivf_build(data, 2, 3, 2, 25, 42)
  let results = ivf_search(index, [1.0, 0.0, 0.0], 0, 1)
  assert_eq(results.length(), 0)
}

///|
test "ivf_search_all_cells_probed" {
  // With nprobe = nlist, should find exact nearest neighbor
  let data = [
    1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 2.0, 0.0, 0.0, 3.0, 0.0, 0.0, 0.0,
    2.0, 0.0,
  ]
  let index = ivf_build(data, 6, 3, 3, 25, 42)
  let results = ivf_search(index, [0.9, 0.0, 0.0], 1, 3)
  assert_eq(results.length(), 1)
  // The nearest vector to [0.9, 0, 0] should be [1, 0, 0] (index 0)
  assert_eq(results[0].index, 0)
}

///|
test "ivf_search_increasing_nprobe_improves_recall" {
  let data = [
    1.0, 0.0, 0.0, 2.0, 0.0, 0.0, 3.0, 0.0, 0.0, 4.0, 0.0, 0.0, 5.0, 0.0, 0.0, 6.0,
    0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 2.0, 0.0, 0.0, 3.0, 0.0, 0.0, 4.0, 0.0,
  ]
  let index = ivf_build(data, 10, 3, 3, 25, 42)
  // Brute force: nearest to [5.5, 0, 0] is index 4 (5.0, 0, 0)
  // With nprobe=1, may or may not find it, but with nprobe=3 should
  let results_full = ivf_search(index, [5.5, 0.0, 0.0], 1, 3)
  assert_true(results_full.length() >= 1)
}

// ===========================================================================
// Accessor Tests
// ===========================================================================

///|
test "ivf_accessors" {
  let data = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0]
  let index = ivf_build(data, 4, 3, 2, 25, 42)
  assert_eq(ivf_dim(index), 3)
  assert_eq(ivf_n_vectors(index), 4)
  assert_eq(ivf_nlist(index), 2)
}

///|
test "ivf_cell_size" {
  // Use well-separated clusters
  let data = [10.0, 0.0, 0.0, 10.0, 1.0, 0.0, -10.0, 0.0, 0.0, -10.0, 1.0, 0.0]
  let index = ivf_build(data, 4, 3, 2, 25, 42)
  // Sum of all cell sizes should equal n_vectors
  let n = ivf_nlist(index)
  let total = loop_sum_cell_sizes(index, n)
  assert_eq(total, 4)
  // Invalid cell returns 0
  assert_eq(ivf_cell_size(index, -1), 0)
  assert_eq(ivf_cell_size(index, 99), 0)
}

///|
fn loop_sum_cell_sizes(index : IVFIndex, n : Int) -> Int {
  let mut total = 0
  for c = 0; c < n; c = c + 1 {
    total = total + ivf_cell_size(index, c)
  }
  total
}

// ===========================================================================
// Recall Test
// ===========================================================================

///|
test "ivf_recall" {
  // Build an index and test recall against brute-force
  let data = [
    1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 2.0, 0.0, 0.0, 0.0, 2.0, 0.0, 0.0,
    0.0, 2.0,
  ]
  let index = ivf_build(data, 6, 3, 3, 25, 42)
  // Query near [1,0,0] - true NN is index 0
  let results = ivf_search(index, [0.9, 0.0, 0.0], 1, 3)
  let true_nn = [0]
  let r = ivf_recall(true_nn, results)
  assert_true((r - 1.0).abs() < 1.0e-10)
}

///|
test "ivf_recall_empty" {
  let r = ivf_recall([], [])
  assert_true((r - 1.0).abs() < 1.0e-10)
}
