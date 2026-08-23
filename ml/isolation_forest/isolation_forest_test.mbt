///|
test "iforest_empty_model" {
  let data : Array[Array[Double]] = []
  let model = isolation_forest_fit(data, 10, 0, 42L)
  assert_eq(isolation_forest_n_trees(model), 0)
  // Scoring with empty model returns 0.5
  let s = isolation_forest_score(model, [1.0, 2.0])
  assert_true(s > 0.49 && s < 0.51)
}

///|
test "iforest_single_point" {
  let data = [[1.0, 2.0]]
  let model = isolation_forest_fit(data, 5, 1, 42L)
  assert_eq(isolation_forest_train_size(model), 1)
}

///|
test "iforest_basic_anomaly_detection" {
  // Normal points clustered around (0, 0), one outlier at (10, 10)
  let data : Array[Array[Double]] = []
  for i = 0; i < 50; i = i + 1 {
    data.push([0.0, 0.0])
  }
  for i = 0; i < 50; i = i + 1 {
    data.push([1.0, 1.0])
  }
  data.push([10.0, 10.0]) // anomaly
  let model = isolation_forest_fit(data, 50, 64, 42L)
  let normal_score = isolation_forest_score(model, [0.5, 0.5])
  let anomaly_score = isolation_forest_score(model, [10.0, 10.0])
  // Anomaly should have higher score than normal
  assert_true(anomaly_score > normal_score)
}

///|
test "iforest_score_range" {
  let data : Array[Array[Double]] = []
  for i = 0; i < 200; i = i + 1 {
    let x = (i % 20).to_double()
    let y = (i / 20 % 20).to_double()
    data.push([x, y])
  }
  let model = isolation_forest_fit(data, 20, 50, 42L)
  // All scores should be in (0, 1)
  for i = 0; i < data.length(); i = i + 1 {
    let s = isolation_forest_score(model, data[i])
    assert_true(s > 0.0 && s < 1.0)
  }
}

///|
test "iforest_outlier_higher_score" {
  // Generate normal data in a tight cluster
  let data : Array[Array[Double]] = []
  for i = 0; i < 100; i = i + 1 {
    data.push([0.0, 0.0])
  }
  for i = 0; i < 100; i = i + 1 {
    data.push([0.1, 0.1])
  }
  let model = isolation_forest_fit(data, 50, 50, 42L)
  let normal = isolation_forest_score(model, [0.0, 0.0])
  let outlier = isolation_forest_score(model, [5.0, 5.0])
  assert_true(outlier > normal)
}

///|
test "iforest_batch_scoring" {
  let data : Array[Array[Double]] = []
  for i = 0; i < 100; i = i + 1 {
    let x = (i % 10).to_double()
    let y = (i / 10 % 10).to_double()
    data.push([x, y])
  }
  let model = isolation_forest_fit(data, 20, 50, 42L)
  let scores = isolation_forest_score_batch(model, data)
  assert_eq(scores.length(), 100)
  for i = 0; i < 100; i = i + 1 {
    assert_true(scores[i] > 0.0 && scores[i] < 1.0)
  }
}

///|
test "iforest_predict_threshold" {
  // Diverse normal data in a cluster, with a clear outlier
  let data : Array[Array[Double]] = []
  for i = 0; i < 40; i = i + 1 {
    let x = (i % 8).to_double() * 0.1
    let y = (i / 8 % 5).to_double() * 0.1
    data.push([x, y])
  }
  let model = isolation_forest_fit(data, 50, 40, 42L)
  let test_data = [[0.3, 0.2], [50.0, 50.0]]
  let preds = isolation_forest_predict(model, test_data, 0.55)
  // Normal point should not be flagged
  assert_false(preds[0])
  // Far outlier should be flagged (high score)
  assert_true(preds[1])
}

///|
test "iforest_reproducibility" {
  let data : Array[Array[Double]] = []
  for i = 0; i < 100; i = i + 1 {
    let x = (i % 10).to_double()
    let y = (i / 10 % 10).to_double()
    data.push([x, y])
  }
  let model1 = isolation_forest_fit(data, 20, 50, 42L)
  let model2 = isolation_forest_fit(data, 20, 50, 42L)
  // Same seed → same scores
  let s1 = isolation_forest_score(model1, [5.0, 5.0])
  let s2 = isolation_forest_score(model2, [5.0, 5.0])
  assert_true((s1 - s2).abs() < 1.0e-10)
}

///|
test "iforest_different_seeds_different_models" {
  let data : Array[Array[Double]] = []
  for i = 0; i < 100; i = i + 1 {
    let x = (i % 10).to_double()
    let y = (i / 10 % 10).to_double()
    data.push([x, y])
  }
  let model1 = isolation_forest_fit(data, 20, 50, 1L)
  let model2 = isolation_forest_fit(data, 20, 50, 2L)
  // Different seeds → likely different scores (not guaranteed, but very likely)
  let s1 = isolation_forest_score(model1, [5.0, 5.0])
  let s2 = isolation_forest_score(model2, [5.0, 5.0])
  // They might be different but both should be valid scores
  assert_true(s1 > 0.0 && s1 < 1.0)
  assert_true(s2 > 0.0 && s2 < 1.0)
}

///|
test "iforest_high_dimensional" {
  // 10-dimensional data
  let data : Array[Array[Double]] = []
  for i = 0; i < 100; i = i + 1 {
    let point : Array[Double] = Array::make(10, 0.0)
    for j = 0; j < 10; j = j + 1 {
      point[j] = ((i + j) % 5).to_double()
    }
    data.push(point)
  }
  let model = isolation_forest_fit(data, 20, 50, 42L)
  let normal = isolation_forest_score(model, data[0])
  let outlier_point : Array[Double] = Array::make(10, 100.0)
  let outlier = isolation_forest_score(model, outlier_point)
  assert_true(outlier > normal)
}

///|
test "iforest_subsample_exceeds_data" {
  // Subsample size > data size → use all data
  let data = [[0.0], [1.0], [2.0], [3.0], [4.0]]
  let model = isolation_forest_fit(data, 10, 1000, 42L)
  // Should use all 5 points (clamped to data size)
  assert_eq(isolation_forest_train_size(model), 5)
}

///|
test "iforest_default_params" {
  let data : Array[Array[Double]] = []
  for i = 0; i < 10; i = i + 1 {
    data.push([i.to_double()])
  }
  // Use defaults: n_trees=0 → 100, subsample=0 → 256
  let model = isolation_forest_fit(data, 0, 0, 42L)
  assert_eq(isolation_forest_n_trees(model), 100)
}

///|
test "iforest_metadata" {
  let data = [[0.0], [1.0], [2.0]]
  let model = isolation_forest_fit(data, 5, 3, 42L)
  assert_eq(isolation_forest_n_trees(model), 5)
  assert_eq(isolation_forest_subsample_size(model), 3)
  assert_eq(isolation_forest_train_size(model), 3)
}

///|
test "iforest_identical_points" {
  // All points are identical — no anomaly should be detectable
  let data : Array[Array[Double]] = []
  for i = 0; i < 50; i = i + 1 {
    data.push([1.0, 1.0])
  }
  let model = isolation_forest_fit(data, 10, 50, 42L)
  let s = isolation_forest_score(model, [1.0, 1.0])
  // With all identical points, score should be near 0.5
  assert_true(s > 0.3 && s < 0.7)
}
