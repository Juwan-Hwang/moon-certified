/// Support Vector Machine (SVM) — SMO algorithm with kernel methods.
///
/// Implements a SVM classifier using the Sequential Minimal Optimisation
/// (SMO) algorithm (Platt, 1998) with support for multiple kernel functions
/// and multi-class classification.
///
/// ## Algorithm
///
/// SMO decomposes the constrained QP optimisation problem into a sequence
/// of smallest possible sub-problems (two Lagrange multipliers at a time),
/// each solvable analytically. This avoids the need for a general QP solver.
///
/// ## Kernels
///
/// - **Linear**: `K(x, y) = x · y`
/// - **RBF (Gaussian)**: `K(x, y) = exp(-γ · ||x - y||²)`
/// - **Polynomial**: `K(x, y) = (γ · x · y + r)^d`
/// - **Sigmoid**: `K(x, y) = tanh(γ · x · y + r)`
///
/// ## Multi-class
///
/// One-vs-Rest (OvR) strategy: trains K binary classifiers for K classes,
/// each separating one class from the rest. Prediction picks the class
/// with the highest decision score.
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
/// - Hsu, C.-W. and Lin, C.-J. (2002): "A Comparison of Methods for
///   Multi-class Support Vector Machines"
///
/// Not formally verified. Correctness is ensured by the test suite.

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

///|
/// Kernel function type.
pub enum KernelType {
  Linear       // K(x, y) = x · y
  RBF          // K(x, y) = exp(-γ · ||x - y||²)
  Polynomial   // K(x, y) = (γ · x · y + r)^d
  Sigmoid      // K(x, y) = tanh(γ · x · y + r)
} derive(Eq, Debug)

///|
/// SVM model: stores support vectors, their labels, Lagrange multipliers,
/// the bias term, and kernel configuration.
pub struct SVMModel {
  priv support_vectors : Array[Array[Double]]
  priv support_labels : Array[Double]
  priv alphas : Array[Double]
  priv bias : Double
  priv n_features : Int
  priv kernel : KernelType
  priv gamma : Double
  priv degree : Int
  priv coef0 : Double
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
  /// Kernel function type.
  priv kernel : KernelType
  /// γ (gamma) parameter for RBF/poly/sigmoid kernels.
  /// If ≤ 0, auto-computed as 1/n_features.
  priv gamma : Double
  /// Polynomial degree for Polynomial kernel.
  priv degree : Int
  /// r (coef0) parameter for poly/sigmoid kernels.
  priv coef0 : Double
}

///|
/// Default configuration: C=1.0, max_iter=1000, tol=0.001, eps=0.001,
/// Linear kernel.
pub fn default_config() -> SVMConfig {
  {
    c: 1.0,
    max_iter: 1000,
    tol: 0.001,
    eps: 0.001,
    kernel: Linear,
    gamma: 0.0,
    degree: 3,
    coef0: 0.0,
  }
}

///|
/// Create a custom configuration with Linear kernel (backward compatible).
pub fn make_config(c : Double, max_iter : Int, tol : Double, eps : Double) -> SVMConfig {
  {
    c,
    max_iter,
    tol,
    eps,
    kernel: Linear,
    gamma: 0.0,
    degree: 3,
    coef0: 0.0,
  }
}

///|
/// Create a configuration with a specific kernel.
///
/// - `c`: Regularisation parameter
/// - `max_iter`: Maximum SMO iterations
/// - `tol`: KKT tolerance
/// - `eps`: Convergence threshold
/// - `kernel`: Kernel type
/// - `gamma`: γ parameter (≤ 0 means auto = 1/n_features)
/// - `degree`: Polynomial degree
/// - `coef0`: r parameter for poly/sigmoid
pub fn make_kernel_config(
  c : Double,
  max_iter : Int,
  tol : Double,
  eps : Double,
  kernel : KernelType,
  gamma : Double,
  degree : Int,
  coef0 : Double,
) -> SVMConfig {
  { c, max_iter, tol, eps, kernel, gamma, degree, coef0 }
}

///|
/// Convenience: create an RBF kernel config.
pub fn rbf_config(c : Double, gamma : Double) -> SVMConfig {
  {
    c,
    max_iter: 1000,
    tol: 0.001,
    eps: 0.001,
    kernel: RBF,
    gamma,
    degree: 3,
    coef0: 0.0,
  }
}

///|
/// Convenience: create a Polynomial kernel config.
pub fn poly_config(c : Double, gamma : Double, degree : Int, coef0 : Double) -> SVMConfig {
  {
    c,
    max_iter: 1000,
    tol: 0.001,
    eps: 0.001,
    kernel: Polynomial,
    gamma,
    degree,
    coef0,
  }
}

// ---------------------------------------------------------------------------
// Kernel computation
// ---------------------------------------------------------------------------

///|
/// Compute the kernel value K(a, b) based on the kernel type and parameters.
fn kernel_fn(
  a : Array[Double],
  b : Array[Double],
  config : SVMConfig,
  n_features : Int,
) -> Double {
  let gamma = if config.gamma > 0.0 {
    config.gamma
  } else {
    1.0 / n_features.to_double()
  }
  let result = match config.kernel {
    Linear => dot(a, b)
    RBF => {
      let mut dist_sq = 0.0
      for i = 0; i < a.length(); i = i + 1 {
        let diff = a[i] - b[i]
        dist_sq = dist_sq + diff * diff
      }
      exp_approx(-gamma * dist_sq)
    }
    Polynomial => {
      let val = gamma * dot(a, b) + config.coef0
      let mut pwr = 1.0
      for k = 0; k < config.degree; k = k + 1 {
        pwr = pwr * val
      }
      pwr
    }
    Sigmoid => tanh_approx(gamma * dot(a, b) + config.coef0)
  }
  result
}

///|
/// Compute the kernel value using model parameters (for prediction).
fn kernel_fn_model(a : Array[Double], b : Array[Double], model : SVMModel) -> Double {
  let result = match model.kernel {
    Linear => dot(a, b)
    RBF => {
      let mut dist_sq = 0.0
      for i = 0; i < a.length(); i = i + 1 {
        let diff = a[i] - b[i]
        dist_sq = dist_sq + diff * diff
      }
      exp_approx(-model.gamma * dist_sq)
    }
    Polynomial => {
      let val = model.gamma * dot(a, b) + model.coef0
      let mut pwr = 1.0
      for k = 0; k < model.degree; k = k + 1 {
        pwr = pwr * val
      }
      pwr
    }
    Sigmoid => tanh_approx(model.gamma * dot(a, b) + model.coef0)
  }
  result
}

// ---------------------------------------------------------------------------
// Training (SMO algorithm)
// ---------------------------------------------------------------------------

///|
/// Train an SVM on the given data with the configured kernel.
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
  // Resolve gamma (auto = 1/n_features if ≤ 0)
  let resolved_gamma = if config.gamma > 0.0 {
    config.gamma
  } else {
    1.0 / n_features.to_double()
  }
  // Precompute the kernel matrix K[i][j]
  let k : Array[Array[Double]] = Array::makei(n, fn(_) { Array::make(n, 0.0) })
  for i = 0; i < n; i = i + 1 {
    for j = i; j < n; j = j + 1 {
      let val = kernel_fn(x[i], x[j], config, n_features)
      k[i][j] = val
      k[j][i] = val
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
        if examine_example(i, y, k, alphas, bias, config, n) {
          num_changed = num_changed + 1
        }
      }
    } else {
      for i = 0; i < n; i = i + 1 {
        if alphas[i] > 0.0 && alphas[i] < config.c {
          if examine_example(i, y, k, alphas, bias, config, n) {
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
    if alphas[i] > 1.0e-10 {
      // Deep copy the support vector
      let sv_copy = Array::make(n_features, 0.0)
      for j = 0; j < n_features; j = j + 1 {
        sv_copy[j] = x[i][j]
      }
      sv.push(sv_copy)
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
    kernel: config.kernel,
    gamma: resolved_gamma,
    degree: config.degree,
    coef0: config.coef0,
  })
}

///|
/// Examine a training example and try to optimise its Lagrange multiplier.
/// Returns true if the alpha was changed.
fn examine_example(
  i2 : Int,
  y : Array[Double],
  k : Array[Array[Double]],
  alphas : Array[Double],
  bias : Array[Double],
  config : SVMConfig,
  n : Int,
) -> Bool {
  let alpha2 = alphas[i2]
  let y2 = y[i2]
  let e2 = compute_error(i2, y, k, alphas, bias[0], n) - y2
  let r2 = e2 * y2
  if (r2 < -config.tol && alpha2 < config.c) ||
    (r2 > config.tol && alpha2 > 0.0) {
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
    if i1 >= 0 && take_step(i1, i2, y, k, alphas, bias, config, n) {
      return true
    }
    // If heuristic failed, try non-bound examples
    let mut j = 0
    while j < n {
      if alphas[j] > 0.0 && alphas[j] < config.c {
        if take_step(j, i2, y, k, alphas, bias, config, n) {
          return true
        }
      }
      j = j + 1
    }
    // If that failed, try all examples
    j = 0
    while j < n {
      if take_step(j, i2, y, k, alphas, bias, config, n) {
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
  let (l, h) = if s < 0.0 {
    let lo = (0.0).max(alpha2 - alpha1)
    let hi = config.c.min(config.c + alpha2 - alpha1)
    (lo, hi)
  } else {
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
  if (a2 - alpha2).abs() < config.eps * (a2 + alpha2 + config.eps) {
    return false
  }
  let a1 = alpha1 + s * (alpha2 - a2)
  let b1 = bias[0] - e1 - y1 * (a1 - alpha1) * k11 - y2 * (a2 - alpha2) * k12
  let b2 = bias[0] - e2 - y1 * (a1 - alpha1) * k12 - y2 * (a2 - alpha2) * k22
  bias[0] = if a1 > 0.0 && a1 < config.c {
    b1
  } else if a2 > 0.0 && a2 < config.c {
    b2
  } else {
    (b1 + b2) / 2.0
  }
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

// ---------------------------------------------------------------------------
// Multi-class (One-vs-Rest)
// ---------------------------------------------------------------------------

///|
/// Multi-class SVM model using One-vs-Rest strategy.
pub struct MultiClassModel {
  priv models : Array[SVMModel]
  priv classes : Array[Double]
}

///|
/// Train a multi-class SVM using One-vs-Rest.
///
/// Labels in `y` can be arbitrary values (0.0, 1.0, 2.0, etc.).
/// For each class c, a binary SVM is trained with y=+1 for class c and
/// y=-1 for all other classes.
///
/// Returns `None` if input is empty or has fewer than 2 classes.
pub fn train_multiclass(
  x : Array[Array[Double]],
  y : Array[Double],
  config : SVMConfig,
) -> MultiClassModel? {
  let n = x.length()
  if n == 0 || y.length() != n {
    return None
  }
  // Extract unique classes
  let classes : Array[Double] = []
  for i = 0; i < n; i = i + 1 {
    let mut found = false
    for j = 0; j < classes.length(); j = j + 1 {
      if y[i] == classes[j] {
        found = true
        break
      }
    }
    if !found {
      classes.push(y[i])
    }
  }
  if classes.length() < 2 {
    return None
  }
  // Train one binary SVM per class (one-vs-rest)
  let models : Array[SVMModel] = []
  for c = 0; c < classes.length(); c = c + 1 {
    let cls = classes[c]
    // Build binary labels: +1 for class cls, -1 for others
    let bin_y : Array[Double] = Array::make(n, 0.0)
    for i = 0; i < n; i = i + 1 {
      bin_y[i] = if y[i] == cls { 1.0 } else { -1.0 }
    }
    match train(x, bin_y, config) {
      Some(model) => models.push(model)
      None => return None
    }
  }
  Some({ models, classes })
}

///|
/// Predict the class label for a feature vector using a multi-class model.
///
/// Returns the class label with the highest decision score.
pub fn predict_multiclass(model : MultiClassModel, x : Array[Double]) -> Double {
  let mut best_score = -1.0e18
  let mut best_class = model.classes[0]
  for i = 0; i < model.models.length(); i = i + 1 {
    let score = decision_function(model.models[i], x)
    if score > best_score {
      best_score = score
      best_class = model.classes[i]
    }
  }
  best_class
}

///|
/// Get the number of classes in a multi-class model.
pub fn num_classes(model : MultiClassModel) -> Int {
  model.classes.length()
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
    sum = sum + model.alphas[i] * model.support_labels[i] * kernel_fn_model(
      x, model.support_vectors[i], model,
    )
  }
  if sum >= 0.0 { 1.0 } else { -1.0 }
}

///|
/// Get the raw decision score (distance from the margin).
pub fn decision_function(model : SVMModel, x : Array[Double]) -> Double {
  let mut sum = model.bias
  for i = 0; i < model.support_vectors.length(); i = i + 1 {
    sum = sum + model.alphas[i] * model.support_labels[i] * kernel_fn_model(
      x, model.support_vectors[i], model,
    )
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

///|
/// Get the kernel type used by the model.
pub fn kernel_type(model : SVMModel) -> KernelType {
  model.kernel
}

// ---------------------------------------------------------------------------
// Math helpers
// ---------------------------------------------------------------------------

///|
/// Dot product of two vectors.
fn dot(a : Array[Double], b : Array[Double]) -> Double {
  let mut sum = 0.0
  for i = 0; i < a.length(); i = i + 1 {
    sum = sum + a[i] * b[i]
  }
  sum
}

///|
/// Exponential approximation via Taylor series with range reduction.
/// Accurate to ~1e-15 for |x| < 700.
fn exp_approx(x : Double) -> Double {
  if x < -700.0 {
    return 0.0
  }
  if x > 700.0 {
    return 1.0e300
  }
  // Split x = k*ln2 + r, where |r| <= ln2/2
  let ln2 = 0.6931471805599453
  let k = (x / ln2).round().to_int()
  let r = x - k.to_double() * ln2
  // exp(r) via Taylor series
  let mut term = 1.0
  let mut sum = 1.0
  for i = 1; i <= 20; i = i + 1 {
    term = term * r / i.to_double()
    sum = sum + term
    if term.abs() < 1.0e-16 {
      break
    }
  }
  // exp(x) = 2^k * exp(r)
  // For k > 0: multiply by 2 k times. For k < 0: divide by 2 |k| times.
  let mut result = sum
  if k >= 0 {
    for m = 0; m < k; m = m + 1 {
      result = result * 2.0
    }
  } else {
    for m = 0; m < 0 - k; m = m + 1 {
      result = result / 2.0
    }
  }
  result
}

///|
/// Hyperbolic tangent approximation.
/// tanh(x) = (e^x - e^(-x)) / (e^x + e^(-x))
/// For large |x|, clamps to ±1 to avoid overflow.
fn tanh_approx(x : Double) -> Double {
  if x > 20.0 {
    return 1.0
  }
  if x < -20.0 {
    return -1.0
  }
  let ex = exp_approx(x)
  let enx = exp_approx(-x)
  (ex - enx) / (ex + enx)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "svm: linearly separable data" {
  let x : Array[Array[Double]] = [
    [1.0, 1.0], [1.5, 0.5], [0.5, 1.5], [1.0, 2.0], [2.0, 1.0],
    [5.0, 5.0], [5.5, 4.5], [4.5, 5.5], [5.0, 6.0], [6.0, 5.0],
  ]
  let y : Array[Double] = [-1.0, -1.0, -1.0, -1.0, -1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
  let config = default_config()
  let model = match train(x, y, config) {
    None => fail("training failed")
    Some(m) => m
  }
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
  assert_true(decision_function(model, [0.0, 0.0]) < 0.0)
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

///|
test "svm: RBF kernel solves XOR problem" {
  // XOR: (0,0)→-1, (1,1)→-1, (0,1)→+1, (1,0)→+1
  // Linear kernel cannot solve this, but RBF can.
  let x : Array[Array[Double]] = [
    [0.0, 0.0], [1.0, 1.0], [0.0, 1.0], [1.0, 0.0],
  ]
  let y : Array[Double] = [-1.0, -1.0, 1.0, 1.0]
  let config = rbf_config(10.0, 1.0)
  let model = match train(x, y, config) {
    None => fail("RBF training failed")
    Some(m) => m
  }
  assert_eq(kernel_type(model), RBF)
  assert_eq(predict(model, [0.0, 0.0]), -1.0)
  assert_eq(predict(model, [1.0, 1.0]), -1.0)
  assert_eq(predict(model, [0.0, 1.0]), 1.0)
  assert_eq(predict(model, [1.0, 0.0]), 1.0)
}

///|
test "svm: RBF kernel with concentric circles" {
  // Inner circle (class -1) and outer ring (class +1)
  let x : Array[Array[Double]] = [
    [0.0, 0.0], [0.5, 0.0], [0.0, 0.5], [-0.5, 0.0], [0.0, -0.5],
    [3.0, 0.0], [3.5, 0.0], [0.0, 3.0], [-3.0, 0.0], [0.0, -3.0],
  ]
  let y : Array[Double] = [-1.0, -1.0, -1.0, -1.0, -1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
  let config = rbf_config(1.0, 0.5)
  let model = match train(x, y, config) {
    None => fail("RBF training failed")
    Some(m) => m
  }
  assert_eq(predict(model, [0.1, 0.1]), -1.0)
  assert_eq(predict(model, [3.0, 0.1]), 1.0)
}

///|
test "svm: polynomial kernel" {
  // Data separable by a polynomial decision boundary
  let x : Array[Array[Double]] = [
    [1.0, 0.0], [0.0, 1.0], [-1.0, 0.0], [0.0, -1.0],
    [2.0, 2.0], [2.0, 3.0], [3.0, 2.0], [3.0, 3.0],
  ]
  let y : Array[Double] = [-1.0, -1.0, -1.0, -1.0, 1.0, 1.0, 1.0, 1.0]
  let config = poly_config(1.0, 1.0, 2, 0.0) // degree-2 poly
  let model = match train(x, y, config) {
    None => fail("poly training failed")
    Some(m) => m
  }
  assert_eq(kernel_type(model), Polynomial)
  assert_eq(predict(model, [0.5, 0.5]), -1.0)
  assert_eq(predict(model, [2.5, 2.5]), 1.0)
}

///|
test "svm: sigmoid kernel" {
  let x : Array[Array[Double]] = [
    [0.1, 0.1], [0.2, 0.1], [0.1, 0.2], [0.2, 0.2],
    [0.8, 0.8], [0.9, 0.8], [0.8, 0.9], [0.9, 0.9],
  ]
  let y : Array[Double] = [-1.0, -1.0, -1.0, -1.0, 1.0, 1.0, 1.0, 1.0]
  let config = make_kernel_config(1.0, 1000, 0.001, 0.001, Sigmoid, 1.0, 3, 0.0)
  let model = match train(x, y, config) {
    None => fail("sigmoid training failed")
    Some(m) => m
  }
  assert_eq(kernel_type(model), Sigmoid)
  assert_eq(predict(model, [0.15, 0.15]), -1.0)
  assert_eq(predict(model, [0.85, 0.85]), 1.0)
}

///|
test "svm: linear kernel still works with new config" {
  let x : Array[Array[Double]] = [
    [1.0, 1.0], [2.0, 2.0], [8.0, 8.0], [9.0, 9.0],
  ]
  let y : Array[Double] = [-1.0, -1.0, 1.0, 1.0]
  let config = make_kernel_config(1.0, 1000, 0.001, 0.001, Linear, 0.0, 3, 0.0)
  let model = match train(x, y, config) {
    None => fail("linear training failed")
    Some(m) => m
  }
  assert_eq(kernel_type(model), Linear)
  assert_eq(predict(model, [1.5, 1.5]), -1.0)
  assert_eq(predict(model, [8.5, 8.5]), 1.0)
}

///|
test "svm: multi-class one-vs-rest (3 classes)" {
  // 3 clusters: class 0 near (1,1), class 1 near (5,5), class 2 near (1,5)
  let x : Array[Array[Double]] = [
    [1.0, 1.0], [1.5, 0.5], [0.5, 1.5], [1.0, 2.0],
    [5.0, 5.0], [5.5, 4.5], [4.5, 5.5], [5.0, 6.0],
    [1.0, 5.0], [1.5, 4.5], [0.5, 5.5], [1.0, 6.0],
  ]
  let y : Array[Double] = [
    0.0, 0.0, 0.0, 0.0,
    1.0, 1.0, 1.0, 1.0,
    2.0, 2.0, 2.0, 2.0,
  ]
  let config = default_config()
  let model = match train_multiclass(x, y, config) {
    None => fail("multiclass training failed")
    Some(m) => m
  }
  assert_eq(num_classes(model), 3)
  assert_eq(predict_multiclass(model, [1.0, 1.0]), 0.0)
  assert_eq(predict_multiclass(model, [5.0, 5.0]), 1.0)
  assert_eq(predict_multiclass(model, [1.0, 5.0]), 2.0)
}

///|
test "svm: multi-class with RBF kernel" {
  // Non-linearly separable 3-class problem
  let x : Array[Array[Double]] = [
    [0.0, 0.0], [0.5, 0.0], [0.0, 0.5],
    [4.0, 0.0], [4.5, 0.0], [4.0, 0.5],
    [2.0, 4.0], [2.5, 4.0], [2.0, 4.5],
  ]
  let y : Array[Double] = [0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 2.0, 2.0, 2.0]
  let config = rbf_config(10.0, 0.5)
  let model = match train_multiclass(x, y, config) {
    None => fail("multiclass RBF training failed")
    Some(m) => m
  }
  assert_eq(num_classes(model), 3)
  assert_eq(predict_multiclass(model, [0.1, 0.1]), 0.0)
  assert_eq(predict_multiclass(model, [4.1, 0.1]), 1.0)
  assert_eq(predict_multiclass(model, [2.1, 4.1]), 2.0)
}

///|
test "svm: multi-class returns None for single class" {
  let x : Array[Array[Double]] = [[1.0, 2.0], [3.0, 4.0]]
  let y : Array[Double] = [0.0, 0.0]
  assert_true(train_multiclass(x, y, default_config()) is None)
}

///|
test "svm: multi-class returns None for empty input" {
  let x : Array[Array[Double]] = []
  let y : Array[Double] = []
  assert_true(train_multiclass(x, y, default_config()) is None)
}

///|
test "svm: exp and tanh helpers" {
  // Verify exp_approx is close to a known value
  let e1 = exp_approx(1.0)
  assert_true(e1 > 2.71 && e1 < 2.72)
  let e0 = exp_approx(0.0)
  assert_true(e0 > 0.999 && e0 < 1.001)
  let t0 = tanh_approx(0.0)
  assert_true(t0 > -0.001 && t0 < 0.001)
  let t1 = tanh_approx(1.0)
  assert_true(t1 > 0.76 && t1 < 0.77)
}

///|
test "svm: auto gamma computation" {
  // When gamma=0.0, it should be auto-computed as 1/n_features
  let x : Array[Array[Double]] = [
    [0.0, 0.0], [1.0, 1.0], [0.0, 1.0], [1.0, 0.0],
  ]
  let y : Array[Double] = [-1.0, -1.0, 1.0, 1.0]
  // gamma=0 means auto=1/2=0.5
  let config = make_kernel_config(10.0, 1000, 0.001, 0.001, RBF, 0.0, 3, 0.0)
  let model = match train(x, y, config) {
    None => fail("auto gamma RBF training failed")
    Some(m) => m
  }
  assert_eq(kernel_type(model), RBF)
  // With auto gamma, XOR should still be solvable
  assert_eq(predict(model, [0.0, 0.0]), -1.0)
  assert_eq(predict(model, [0.0, 1.0]), 1.0)
}
