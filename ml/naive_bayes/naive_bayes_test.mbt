///|
test "GaussianNB: basic two-class separation" {
  // Class 0 centered around (0, 0), class 1 around (10, 10).
  let x = [
    [-1.0, -1.0],
    [-0.5, -0.5],
    [0.0, 0.0],
    [0.5, 0.5],
    [1.0, 1.0],
    [9.0, 9.0],
    [9.5, 9.5],
    [10.0, 10.0],
    [10.5, 10.5],
    [11.0, 11.0],
  ]
  let y = [0, 0, 0, 0, 0, 1, 1, 1, 1, 1]
  let model = gaussian_fit(x, y, 1.0e-9)
  assert_true(gaussian_predict(model, [0.1, 0.1]) == 0)
  assert_true(gaussian_predict(model, [9.9, 9.9]) == 1)
  assert_true(gaussian_predict(model, [-5.0, -5.0]) == 0)
  assert_true(gaussian_predict(model, [15.0, 15.0]) == 1)
}

///|
test "GaussianNB: batch prediction" {
  let x = [[0.0, 0.0], [10.0, 10.0]]
  let y = [0, 1]
  let model = gaussian_fit(x, y, 1.0e-9)
  let preds = gaussian_predict_batch(model, [[1.0, 1.0], [9.0, 9.0]])
  assert_eq(preds[0], 0)
  assert_eq(preds[1], 1)
}

///|
test "GaussianNB: log proba ordering" {
  let x = [[0.0], [10.0]]
  let y = [0, 1]
  let model = gaussian_fit(x, y, 1.0e-9)
  let (label, log_probs) = gaussian_predict_log_proba(model, [1.0])
  assert_eq(label, 0)
  // log P(class 0 | x=1) > log P(class 1 | x=1)
  assert_true(log_probs[0] > log_probs[1])
}

///|
test "GaussianNB: three classes" {
  let x = [[0.0], [5.0], [10.0]]
  let y = [0, 1, 2]
  let model = gaussian_fit(x, y, 1.0e-9)
  assert_eq(gaussian_predict(model, [0.5]), 0)
  assert_eq(gaussian_predict(model, [4.5]), 1)
  assert_eq(gaussian_predict(model, [9.5]), 2)
}

///|
test "MultinomialNB: text classification" {
  // 3 features (words), 2 classes (spam/ham)
  let x = [
    [3.0, 0.0, 1.0], // class 0: low word1, no word2, some word3
    [2.0, 1.0, 0.0],
    [4.0, 0.0, 1.0],
    [0.0, 5.0, 3.0], // class 1: no word1, high word2, some word3
    [1.0, 4.0, 2.0],
    [0.0, 6.0, 4.0],
  ]
  let y = [0, 0, 0, 1, 1, 1]
  let model = multinomial_fit(x, y, 1.0)
  assert_eq(multinomial_predict(model, [5.0, 0.0, 1.0]), 0)
  assert_eq(multinomial_predict(model, [0.0, 5.0, 3.0]), 1)
}

///|
test "MultinomialNB: smoothing prevents zero probability" {
  // With alpha=1, a feature unseen in training won't cause log(0).
  let x = [[1.0, 0.0], [0.0, 1.0]]
  let y = [0, 1]
  let model = multinomial_fit(x, y, 1.0)
  // Even with a feature never seen before, prediction should work.
  let label = multinomial_predict(model, [5.0, 5.0])
  assert_true(label == 0 || label == 1)
}

///|
test "BernoulliNB: binary classification" {
  let x = [
    [1.0, 0.0, 1.0],
    [1.0, 1.0, 0.0],
    [0.0, 1.0, 1.0],
    [1.0, 0.0, 0.0],
    [0.0, 0.0, 1.0],
    [0.0, 1.0, 0.0],
    [1.0, 1.0, 1.0],
    [0.0, 0.0, 0.0],
  ]
  let y = [1, 1, 0, 1, 0, 0, 1, 0]
  let model = bernoulli_fit(x, y, 1.0, 0.0)
  // Predict: a sample with pattern similar to class 1
  let label = bernoulli_predict(model, [1.0, 0.0, 1.0])
  assert_eq(label, 1)
}

///|
test "BernoulliNB: binarization" {
  let x = [[0.8, 0.1], [0.9, 0.2], [0.1, 0.8], [0.2, 0.9]]
  let y = [0, 0, 1, 1]
  let model = bernoulli_fit(x, y, 1.0, 0.5)
  assert_eq(bernoulli_predict(model, [0.7, 0.3]), 0)
  assert_eq(bernoulli_predict(model, [0.3, 0.7]), 1)
}

///|
test "accuracy: correct computation" {
  assert_eq(accuracy([0, 1, 2, 3], [0, 1, 2, 3]), 1.0)
  assert_eq(accuracy([0, 1, 2, 3], [0, 0, 2, 3]), 0.75)
  assert_eq(accuracy([1, 1, 1, 1], [0, 0, 0, 0]), 0.0)
  assert_eq(accuracy([], []), 0.0)
}

///|
test "GaussianNB: equal priors when balanced" {
  let x = [[0.0], [10.0]]
  let y = [0, 1]
  let model = gaussian_fit(x, y, 1.0e-9)
  let (_, log_probs) = gaussian_predict_log_proba(model, [5.0])
  // At midpoint, log probs should be approximately equal.
  let diff = log_probs[0] - log_probs[1]
  assert_true(diff > -0.001 && diff < 0.001)
}
