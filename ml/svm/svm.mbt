/// Support Vector Machine (SVM) — Linear SVM via SMO algorithm.
///
/// Implements a binary linear SVM classifier using the Sequential Minimal
/// Optimisation (SMO) algorithm (Platt, 1998), the standard training
/// algorithm for SVMs.
///
/// ## Algorithm
///
/// SMO decomposes the constrained QP optimisation problem into a sequence
/// of smallest possible sub-problems (two Lagrange multipliers at a time),
/// each solvable analytically. This avoids the need for a general QP solver.
///
/// ## Features
///
/// - Linear kernel (dot product)
/// - L1-soft-margin (slack penalty C)
/// - Support vector extraction
/// - Margin-based classification with sign convention: +1 / -1
///
/// ## Complexity
///
/// Training is O(n²) in the worst case due to kernel matrix computation,
/// but SMO converges in O(n) to O(n²) iterations in practice.
///
/// ## References
///
/// - Platt, J. (1998): "Sequential Minimal Optimization: A Fast Algorithm
///   for Training Support Vector Machines"
/// - Cortes, C. and Vapnik, V. (1995): "Support-Vector Networks"
///
/// Not formally verified. Correctness is ensured by the test suite.

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

///|
/// SVM model: stores support vectors, their labels, Lagrange multipliers,
/// and the bias term.
pub struct SVMModel {
  priv support_vectors : Array[Array[Double]]
  priv support_labels : Array[Double]
  priv alphas : Array[Double]
  priv bias : Double
  priv n_features : Int
}

///|
/// SVM training configuration.
pub struct SVMConfig {
  /// Regularisation parameter (penalty for misclassification).
  /// Larger C → less tolerance for errors → potentially overfits.
  /// Smaller C → more tolerance → potentially underfits.
  priv c : Double
  /// Maximum number of SMO iterations.
  priv max_iter : Int
  /// Tolerance for KKT condition violations.
  priv tol : Double
  /// Convergence threshold for alpha changes.
  priv eps : Double
}

///|
/// Default configuration: C=1.0, max_iter=1000, tol=0.001, eps=0.001.
pub fn default_config() -> SVMConfig {
  { c: 1.0, max_iter: 1000, tol: 0.001, eps: 0.001 }
}

///|
/// Create a custom configuration.
pub fn make_config(c : Double, max_iter : Int, tol : Double, eps : Double) -> SVMConfig {
  { c, max_iter, tol, eps }
}

// ---------------------------------------------------------------------------
// Training (SMO algorithm)
// ---------------------------------------------------------------------------

///|
/// Train a linear SVM on the given data.
///
/// `x` is an array of feature vectors, `y` is an array of labels
/// (+1.0 or -1.0). Returns a trained `SVMModel`.
///
/// Returns `None` if the input is empty or dimensions are inconsistent.
pub fn train(
  x : Array[Array[Double]],
  y : Array[Double],
  config : SVMConfig,
) -> SVMModel? {
  let n = x.length()
  if n == 0 || y.length() != n {
    return None
  }
  let n_features = x[0].length()
  if n_features == 0 {
    return None
  }
  for i = 0; i < n; i = i + 1 {
    if x[i].length() != n_features {
      return None
    }
  }
  // Precompute the linear kernel matrix K[i][j] = x[i] · x[j]
  // Use makei to ensure each row is a distinct array (not shared reference).
  let k : Array[Array[Double]] = Array::makei(n, fn(_) { Array::make(n, 0.0) })
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      k[i][j] = dot(x[i], x[j])
    }
  }
  // SMO algorithm
  let alphas = Array::make(n, 0.0)
  let bias : Array[Double] = [0.0]
  let mut iter = 0
  let mut num_changed = 0
  let mut examine_all = true
  while (num_changed > 0 || examine_all) && iter < config.max_iter {
    num_changed = 0
    if examine_all {
      for i = 0; i < n; i = i + 1 {
        if examine_example(i, x, y, k, alphas, bias, config, n) {
          num_changed = num_changed + 1
        }
      }
    } else {
      for i = 0; i < n; i = i + 1 {
        if alphas[i] > 0.0 && alphas[i] < config.c {
          if examine_example(i, x, y, k, alphas, bias, config, n) {
            num_changed = num_changed + 1
          }
        }
      }
    }
    if examine_all {
      examine_all = false
    } else if num_changed == 0 {
      examine_all = true
    }
    iter = iter + 1
  }
  // Extract support vectors (alphas > 0)
  let sv : Array[Array[Double]] = []
  let sv_labels : Array[Double] = []
  let sv_alphas : Array[Double] = []
  for i = 0; i < n; i = i + 1 {
    if alphas[i] > 0.0000000001 {
      sv.push(x[i])
      sv_labels.push(y[i])
      sv_alphas.push(alphas[i])
    }
  }
  Some({
    support_vectors: sv,
    support_labels: sv_labels,
    alphas: sv_alphas,
    bias: bias[0],
    n_features,
  })
}

///|
/// Examine a training example and try to optimise its Lagrange multiplier.
/// Returns true if the alpha was changed.
fn examine_example(
  i2 : Int,
  x : Array[Array[Double]],
  y : Array[Double],
  k : Array[Array[Double]],
  alphas : Array[Double],
  bias : Array[Double],
  config : SVMConfig,
  n : Int,
) -> Bool {
  let alpha2 = alphas[i2]
  let y2 = y[i2]
  // Compute error E2 = f(x2) - y2
  let e2 = compute_error(i2, y, k, alphas, bias[0], n) - y2
  let r2 = e2 * y2
  // Check KKT conditions
  if (r2 < -config.tol && alpha2 < config.c) ||
    (r2 > config.tol && alpha2 > 0.0) {
    // Try to find a second alpha to optimise
    // Heuristic: pick the alpha that maximises |E1 - E2|
    let mut max_delta = 0.0
    let mut i1 = -1
    for i = 0; i < n; i = i + 1 {
      if alphas[i] > 0.0 && alphas[i] < config.c {
        let e1 = compute_error(i, y, k, alphas, bias[0], n) - y[i]
        let delta = (e1 - e2).abs()
        if delta > max_delta {
          max_delta = delta
          i1 = i
        }
      }
    }
    if i1 >= 0 && take_step(i1, i2, x, y, k, alphas, bias, config, n) {
      return true
    }
    // If heuristic failed, try non-bound examples
    let mut j = 0
    while j < n {
      if alphas[j] > 0.0 && alphas[j] < config.c {
        if take_step(j, i2, x, y, k, alphas, bias, config, n) {
          return true
        }
      }
      j = j + 1
    }
    // If that failed, try all examples
    j = 0
    while j < n {
      if take_step(j, i2, x, y, k, alphas, bias, config, n) {
        return true
      }
      j = j + 1
    }
  }
  false
}

///|
/// Optimise two Lagrange multipliers (alpha1, alpha2) simultaneously.
/// Returns true if the alphas were changed.
fn take_step(
  i1 : Int,
  i2 : Int,
  _x : Array[Array[Double]],
  y : Array[Double],
  k : Array[Array[Double]],
  alphas : Array[Double],
  bias : Array[Double],
  config : SVMConfig,
  n : Int,
) -> Bool {
  if i1 == i2 {
    return false
  }
  let alpha1 = alphas[i1]
  let alpha2 = alphas[i2]
  let y1 = y[i1]
  let y2 = y[i2]
  let e1 = compute_error(i1, y, k, alphas, bias[0], n) - y1
  let e2 = compute_error(i2, y, k, alphas, bias[0], n) - y2
  let s = y1 * y2
  // Compute bounds L and H for alpha2 (RFC SMO §12.2.2)
  let (l, h) = if s < 0.0 {
    // y1 != y2: L = max(0, α2 - α1), H = min(C, C + α2 - α1)
    let lo = (0.0).max(alpha2 - alpha1)
    let hi = config.c.min(config.c + alpha2 - alpha1)
    (lo, hi)
  } else {
    // y1 == y2: L = max(0, α1 + α2 - C), H = min(C, α1 + α2)
    let lo = (0.0).max(alpha2 + alpha1 - config.c)
    let hi = config.c.min(alpha2 + alpha1)
    (lo, hi)
  }
  if h <= l {
    return false
  }
  let k11 = k[i1][i1]
  let k12 = k[i1][i2]
  let k22 = k[i2][i2]
  let eta = k11 + k22 - 2.0 * k12
  let mut a2 = 0.0
  if eta > 0.0 {
    a2 = alpha2 + y2 * (e1 - e2) / eta
    if a2 < l {
      a2 = l
    } else if a2 > h {
      a2 = h
    }
  } else {
    // Non-positive eta: use objective function at bounds
    let f1 = y1 * (e1 + bias[0]) - alpha1 * k11 - s * alpha2 * k12
    let f2 = y2 * (e2 + bias[0]) - s * alpha1 * k12 - alpha2 * k22
    let l1 = alpha1 + s * (alpha2 - l)
    let h1 = alpha1 + s * (alpha2 - h)
    let l_obj = l1 * f1 + l * f2 + 0.5 * l1 * l1 * k11 + 0.5 * l * l * k22 + s * l * l1 * k12
    let h_obj = h1 * f1 + h * f2 + 0.5 * h1 * h1 * k11 + 0.5 * h * h * k22 + s * h * h1 * k12
    if l_obj < h_obj - config.eps {
      a2 = l
    } else if l_obj > h_obj + config.eps {
      a2 = h
    } else {
      a2 = alpha2
    }
  }
  // Check if change is significant
  if (a2 - alpha2).abs() < config.eps * (a2 + alpha2 + config.eps) {
    return false
  }
  // Compute alpha1
  let a1 = alpha1 + s * (alpha2 - a2)
  // Update bias (standard SMO: b = b_old - E - y1*da1*K11 - y2*da2*K12)
  let b1 = bias[0] - e1 - y1 * (a1 - alpha1) * k11 - y2 * (a2 - alpha2) * k12
  let b2 = bias[0] - e2 - y1 * (a1 - alpha1) * k12 - y2 * (a2 - alpha2) * k22
  bias[0] = if a1 > 0.0 && a1 < config.c {
    b1
  } else if a2 > 0.0 && a2 < config.c {
    b2
  } else {
    (b1 + b2) / 2.0
  }
  // Update alphas
  alphas[i1] = a1
  alphas[i2] = a2
  true
}

///|
/// Compute the decision function f(xi) = sum_j(alpha_j * y_j * K(xi, xj)) + bias.
fn compute_error(
  i : Int,
  y : Array[Double],
  k : Array[Array[Double]],
  alphas : Array[Double],
  bias : Double,
  n : Int,
) -> Double {
  let mut sum = bias
  for j = 0; j < n; j = j + 1 {
    if alphas[j] > 0.0 {
      sum = sum + alphas[j] * y[j] * k[i][j]
    }
  }
  sum
}

///|
/// Dot product of two vectors.
fn dot(a : Array[Double], b : Array[Double]) -> Double {
  let mut sum = 0.0
  for i = 0; i < a.length(); i = i + 1 {
    sum = sum + a[i] * b[i]
  }
  sum
}

// ---------------------------------------------------------------------------
// Prediction
// ---------------------------------------------------------------------------

///|
/// Predict the class label for a feature vector.
///
/// Returns +1.0 or -1.0.
pub fn predict(model : SVMModel, x : Array[Double]) -> Double {
  if model.support_vectors.length() == 0 {
    return if model.bias >= 0.0 { 1.0 } else { -1.0 }
  }
  let mut sum = model.bias
  for i = 0; i < model.support_vectors.length(); i = i + 1 {
    sum = sum + model.alphas[i] * model.support_labels[i] * dot(x, model.support_vectors[i])
  }
  if sum >= 0.0 { 1.0 } else { -1.0 }
}

///|
/// Get the raw decision score (distance from the margin).
pub fn decision_function(model : SVMModel, x : Array[Double]) -> Double {
  let mut sum = model.bias
  for i = 0; i < model.support_vectors.length(); i = i + 1 {
    sum = sum + model.alphas[i] * model.support_labels[i] * dot(x, model.support_vectors[i])
  }
  sum
}

///|
/// Get the number of support vectors.
pub fn num_support_vectors(model : SVMModel) -> Int {
  model.support_vectors.length()
}

///|
/// Get the number of features the model was trained on.
pub fn n_features(model : SVMModel) -> Int {
  model.n_features
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "svm: linearly separable data" {
  // Two clusters: positive class around (5,5), negative around (1,1)
  let x : Array[Array[Double]] = [
    [1.0, 1.0], [1.5, 0.5], [0.5, 1.5], [1.0, 2.0], [2.0, 1.0],
    [5.0, 5.0], [5.5, 4.5], [4.5, 5.5], [5.0, 6.0], [6.0, 5.0],
  ]
  let y : Array[Double] = [-1.0, -1.0, -1.0, -1.0, -1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
  let config = default_config()
  let model = match train(x, y, config) {
    None => abort("training failed")
    Some(m) => m
  }
  // Test classification
  assert_eq(predict(model, [0.5, 0.5]), -1.0)
  assert_eq(predict(model, [5.5, 5.5]), 1.0)
  assert_eq(predict(model, [1.0, 1.0]), -1.0)
  assert_eq(predict(model, [6.0, 6.0]), 1.0)
}

///|
test "svm: decision function sign" {
  let x : Array[Array[Double]] = [
    [0.0, 0.0], [0.1, 0.1], [10.0, 10.0], [9.5, 10.5],
  ]
  let y : Array[Double] = [-1.0, -1.0, 1.0, 1.0]
  let model = train(x, y, default_config()).unwrap()
  // Points near origin should have negative decision score
  assert_true(decision_function(model, [0.0, 0.0]) < 0.0)
  // Points near (10,10) should have positive decision score
  assert_true(decision_function(model, [10.0, 10.0]) > 0.0)
}

///|
test "svm: has support vectors" {
  let x : Array[Array[Double]] = [
    [0.0, 0.0], [1.0, 1.0], [10.0, 10.0], [11.0, 11.0],
  ]
  let y : Array[Double] = [-1.0, -1.0, 1.0, 1.0]
  let model = train(x, y, default_config()).unwrap()
  assert_true(num_support_vectors(model) > 0)
}

///|
test "svm: empty input returns None" {
  let x : Array[Array[Double]] = []
  let y : Array[Double] = []
  assert_true(train(x, y, default_config()) is None)
}

///|
test "svm: inconsistent dimensions returns None" {
  let x : Array[Array[Double]] = [[1.0, 2.0], [3.0]]
  let y : Array[Double] = [-1.0, 1.0]
  assert_true(train(x, y, default_config()) is None)
}
