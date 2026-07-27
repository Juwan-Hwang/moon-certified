/// Logistic Regression — Binary classification via gradient descent.
///
/// Logistic regression models the probability P(y=1|x) = σ(w·x + b)
/// where σ is the sigmoid function. Parameters are learned via mini-batch
/// gradient descent on the log-loss (cross-entropy).
///
/// ## Complexity
/// - Training: O(epochs × n × d) where n = samples, d = features.
/// - Prediction: O(d) per sample.
///
/// Not formally verified. Correctness is ensured by the test suite.

///|
/// Sigmoid function: σ(z) = 1 / (1 + e^{-z}).
/// Clamped to avoid overflow.
fn sigmoid(z : Double) -> Double {
  if z >= 35.0 {
    1.0
  } else if z <= -35.0 {
    0.0
  } else {
    1.0 / (1.0 + @math.exp(-z))
  }
}

///|
/// Logistic regression model.
pub struct LogisticRegression {
  priv mut weights : Array[Double]
  priv mut bias : Double
  priv learning_rate : Double
  priv n_iterations : Int
  priv mut fitted : Bool
}

///|
/// Create a new logistic regression model.
///
/// - `learning_rate`: step size for gradient descent (typical: 0.01).
/// - `n_iterations`: number of training epochs (typical: 1000).
pub fn new(learning_rate : Double, n_iterations : Int) -> LogisticRegression {
  {
    weights: [],
    bias: 0.0,
    learning_rate: if learning_rate > 0.0 {
      learning_rate
    } else {
      0.01
    },
    n_iterations: if n_iterations > 0 {
      n_iterations
    } else {
      1000
    },
    fitted: false,
  }
}

///|
/// Fit the model to training data using gradient descent.
///
/// - `x_data`: feature matrix (n_samples × n_features).
/// - `y_labels`: labels (0 or 1), length must equal x_data.length().
pub fn fit(
  model : LogisticRegression,
  x_data : Array[Array[Double]],
  y_labels : Array[Int],
) -> Unit {
  let n = x_data.length()
  if n == 0 || y_labels.length() != n {
    return
  }
  let d = x_data[0].length()
  model.weights = Array::make(d, 0.0)
  model.bias = 0.0
  for _epoch = 0; _epoch < model.n_iterations; _epoch = _epoch + 1 {
    let grad_w : Array[Double] = Array::make(d, 0.0)
    let mut grad_b = 0.0
    for i = 0; i < n; i = i + 1 {
      let mut z = model.bias
      for j = 0; j < d; j = j + 1 {
        z = z + model.weights[j] * x_data[i][j]
      }
      let pred = sigmoid(z)
      let err = pred - y_labels[i].to_double()
      for j = 0; j < d; j = j + 1 {
        grad_w[j] = grad_w[j] + err * x_data[i][j]
      }
      grad_b = grad_b + err
    }
    let lr = model.learning_rate / n.to_double()
    for j = 0; j < d; j = j + 1 {
      model.weights[j] = model.weights[j] - lr * grad_w[j]
    }
    model.bias = model.bias - lr * grad_b
  }
  model.fitted = true
}

///|
/// Predict probability P(y=1|x).
pub fn predict_proba(model : LogisticRegression, x : Array[Double]) -> Double {
  if !model.fitted {
    return 0.0
  }
  let mut z = model.bias
  for j = 0; j < model.weights.length(); j = j + 1 {
    z = z + model.weights[j] * x[j]
  }
  sigmoid(z)
}

///|
/// Predict class label (0 or 1) with threshold 0.5.
pub fn predict(model : LogisticRegression, x : Array[Double]) -> Int {
  if predict_proba(model, x) >= 0.5 {
    1
  } else {
    0
  }
}

///|
/// Get model weights.
pub fn get_weights(model : LogisticRegression) -> Array[Double] {
  Array::copy(model.weights)
}

///|
/// Get model bias.
pub fn get_bias(model : LogisticRegression) -> Double {
  model.bias
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "logistic_regression: linearly separable" {
  let model = new(0.1, 500)
  // AND gate: y = 1 only when both features are 1.
  let x_data : Array[Array[Double]] = []
  x_data.push([0.0, 0.0])
  x_data.push([0.0, 1.0])
  x_data.push([1.0, 0.0])
  x_data.push([1.0, 1.0])
  let y_labels = [0, 0, 0, 1]
  fit(model, x_data, y_labels)
  assert_eq(predict(model, [0.0, 0.0]), 0)
  assert_eq(predict(model, [1.0, 1.0]), 1)
}

///|
test "logistic_regression: probability in [0,1]" {
  let model = new(0.01, 100)
  let x_data : Array[Array[Double]] = []
  x_data.push([1.0])
  x_data.push([2.0])
  x_data.push([3.0])
  x_data.push([4.0])
  x_data.push([5.0])
  let y_labels = [0, 0, 1, 1, 1]
  fit(model, x_data, y_labels)
  let p = predict_proba(model, [3.5])
  assert_true(p >= 0.0 && p <= 1.0)
}

///|
test "logistic_regression: unfitted returns 0" {
  let model = new(0.01, 100)
  assert_eq(predict(model, [1.0, 2.0]), 0)
}
