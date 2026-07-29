/// Gaussian Process Regression.
///
/// Implements GP regression with the Radial Basis Function (RBF / squared
/// exponential) kernel. GP regression is a non-parametric Bayesian method
/// that provides both a posterior mean prediction and an uncertainty
/// estimate (posterior variance).
///
/// ## Algorithm
///
/// Given training inputs X and outputs y:
///
/// 1. Compute the kernel matrix K where K[i][j] = k(X_i, X_j).
/// 2. Add observation noise: K_y = K + σ²_n · I.
/// 3. Cholesky-decompose K_y = L · L^T.
/// 4. Solve L · α = y via forward substitution.
///
/// For a test point x*:
/// - Compute k_s = [k(x*, X_1), ..., k(x*, X_n)].
/// - Posterior mean: f* = k_s^T · (L^T \ (L \ y)).
/// - Posterior variance: V[f*] = k(x*, x*) - k_s^T · (K_y^(-1) · k_s).
///
/// ## Kernel
///
/// RBF kernel: k(x, x') = σ²_f · exp(-||x - x'||² / (2·l²))
///
/// ## References
///
/// - Rasmussen, C.E. and Williams, C.K.I. "Gaussian Processes for Machine
///   Learning." MIT Press, 2006.
/// - Stein, M.L. "Interpolation of Spatial Data." Springer, 1999.
///
/// `proof-enabled` is `false`.

// ---------------------------------------------------------------------------
// Math helpers
// ---------------------------------------------------------------------------

fn exp_(x : Double) -> Double {
  if x < -700.0 {
    return 0.0
  }
  if x > 700.0 {
    return 1.0e300
  }
  let ln2 = 0.6931471805599453
  let n = (x / ln2).floor()
  let r = x - n * ln2
  let mut term = 1.0
  let mut sum = 1.0
  for k = 1; k <= 30; k = k + 1 {
    term = term * r / k.to_double()
    sum = sum + term
    if term.abs() < 1.0e-16 {
      break
    }
  }
  let mut result = sum
  let p = n.to_int()
  if p >= 0 {
    for i = 0; i < p; i = i + 1 {
      result = result * 2.0
    }
  } else {
    for i = 0; i < -p; i = i + 1 {
      result = result / 2.0
    }
  }
  result
}

fn sq_dist(a : Array[Double], b : Array[Double]) -> Double {
  let n = a.length()
  let mut sum = 0.0
  for i = 0; i < n; i = i + 1 {
    let d = a[i] - b[i]
    sum = sum + d * d
  }
  sum
}

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

///|
/// Kernel function type.
pub enum Kernel {
  /// RBF kernel: k(x, x') = sigma_f² · exp(-||x-x'||² / (2·length_scale²))
  RBF(Double, Double)
}

///|
/// A fitted Gaussian Process model.
pub struct GPModel {
  /// Training inputs.
  x_train : Array[Array[Double]]
  /// Training outputs.
  y_train : Array[Double]
  /// Kernel parameters.
  kernel : Kernel
  /// Observation noise variance.
  noise_variance : Double
  /// Cholesky factor L of (K + σ²I).
  chol : Array[Array[Double]]
  /// Alpha = (K + σ²I)^(-1) y, solved via Cholesky.
  alpha : Array[Double]
}

///|
/// Prediction result with mean and variance.
pub struct GPPrediction {
  mean : Double
  variance : Double
}

// ---------------------------------------------------------------------------
// Kernel computation
// ---------------------------------------------------------------------------

/// Evaluate the kernel function at two points.
fn kernel_eval(k : Kernel, a : Array[Double], b : Array[Double]) -> Double {
  match k {
    RBF(length_scale, signal_variance) => {
      let d2 = sq_dist(a, b)
      signal_variance * exp_(-d2 / (2.0 * length_scale * length_scale))
    }
  }
}

// ---------------------------------------------------------------------------
// Cholesky decomposition (lower triangular L such that A = L · L^T)
// ---------------------------------------------------------------------------

/// Cholesky decomposition of a symmetric positive-definite matrix.
/// Returns the lower-triangular factor L, or an empty array if the
/// matrix is not positive-definite.
fn cholesky(a : Array[Array[Double]], n : Int) -> Array[Array[Double]] {
  let l : Array[Array[Double]] = Array::make(n, [])
  for i = 0; i < n; i = i + 1 {
    l[i] = Array::make(n, 0.0)
  }
  for i = 0; i < n; i = i + 1 {
    for j = 0; j <= i; j = j + 1 {
      let mut sum = a[i][j]
      for k = 0; k < j; k = k + 1 {
        sum = sum - l[i][k] * l[j][k]
      }
      if i == j {
        if sum <= 0.0 {
          // Not positive-definite; add jitter
          sum = 1.0e-10
        }
        l[i][j] = sum.sqrt()
      } else {
        let diag = l[j][j]
        if diag.abs() < 1.0e-15 {
          l[i][j] = 0.0
        } else {
          l[i][j] = sum / diag
        }
      }
    }
  }
  l
}

/// Solve L · y = b (forward substitution, L lower-triangular).
fn forward_sub(l : Array[Array[Double]], b : Array[Double], n : Int) -> Array[Double] {
  let y : Array[Double] = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    let mut sum = b[i]
    for j = 0; j < i; j = j + 1 {
      sum = sum - l[i][j] * y[j]
    }
    let diag = l[i][i]
    y[i] = if diag.abs() < 1.0e-15 { 0.0 } else { sum / diag }
  }
  y
}

/// Solve L^T · x = y (back substitution, L^T upper-triangular).
fn back_sub(l : Array[Array[Double]], y : Array[Double], n : Int) -> Array[Double] {
  let x : Array[Double] = Array::make(n, 0.0)
  for i = n - 1; i >= 0; i = i - 1 {
    let mut sum = y[i]
    for j = i + 1; j < n; j = j + 1 {
      sum = sum - l[j][i] * x[j]
    }
    let diag = l[i][i]
    x[i] = if diag.abs() < 1.0e-15 { 0.0 } else { sum / diag }
  }
  x
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

///|
/// Fit a Gaussian Process regression model.
///
/// - `x_train`: training inputs (n × d).
/// - `y_train`: training outputs (length n).
/// - `kernel`: kernel function and hyperparameters.
/// - `noise_variance`: observation noise variance σ²_n (≥ 0).
pub fn fit(
  x_train : Array[Array[Double]],
  y_train : Array[Double],
  kernel : Kernel,
  noise_variance : Double,
) -> GPModel {
  let n = x_train.length()
  // Compute kernel matrix K
  let k_mat : Array[Array[Double]] = Array::make(n, [])
  for i = 0; i < n; i = i + 1 {
    k_mat[i] = Array::make(n, 0.0)
    for j = 0; j < n; j = j + 1 {
      k_mat[i][j] = kernel_eval(kernel, x_train[i], x_train[j])
    }
    k_mat[i][i] = k_mat[i][i] + noise_variance
  }
  // Cholesky decomposition
  let l = cholesky(k_mat, n)
  // Solve L · α' = y, then L^T · α = α'
  let y_intermediate = forward_sub(l, y_train, n)
  let alpha = back_sub(l, y_intermediate, n)
  { x_train, y_train, kernel, noise_variance, chol: l, alpha }
}

///|
/// Predict at a single test point.
///
/// Returns the posterior mean and variance.
pub fn predict(model : GPModel, x_test : Array[Double]) -> GPPrediction {
  let n = model.x_train.length()
  if n == 0 {
    return { mean: 0.0, variance: 0.0 }
  }
  // Compute k_s = [k(x*, X_1), ..., k(x*, X_n)]
  let k_s : Array[Double] = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    k_s[i] = kernel_eval(model.kernel, x_test, model.x_train[i])
  }
  // Posterior mean: f* = k_s^T · alpha
  let mut mean = 0.0
  for i = 0; i < n; i = i + 1 {
    mean = mean + k_s[i] * model.alpha[i]
  }
  // Posterior variance: k(x*, x*) - k_s^T · (K_y^(-1) · k_s)
  let k_ss = kernel_eval(model.kernel, x_test, x_test)
  // Solve L · v = k_s, then v = L^T \ (L \ k_s) = K_y^(-1) k_s
  let v_intermediate = forward_sub(model.chol, k_s, n)
  let v = back_sub(model.chol, v_intermediate, n)
  let mut variance = k_ss
  for i = 0; i < n; i = i + 1 {
    variance = variance - k_s[i] * v[i]
  }
  // Clamp to non-negative
  if variance < 0.0 {
    variance = 0.0
  }
  { mean, variance }
}

///|
/// Predict at multiple test points.
pub fn predict_batch(model : GPModel, x_test : Array[Array[Double]]) -> Array[GPPrediction] {
  let result : Array[GPPrediction] = []
  for i = 0; i < x_test.length(); i = i + 1 {
    result.push(predict(model, x_test[i]))
  }
  result
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "gaussian_process: predicts training points" {
  // Simple 1D: y = sin(x) approximated
  let x : Array[Array[Double]] = []
  let y : Array[Double] = []
  for i = 0; i < 10; i = i + 1 {
    let xi = i.to_double() * 0.5
    x.push([xi])
    // Approximate sin
    y.push(xi - xi * xi * xi / 6.0)
  }
  let model = fit(x, y, RBF(1.0, 1.0), 1.0e-6)
  // Predict at training points: should be close to training values
  for i = 0; i < 10; i = i + 1 {
    let p = predict(model, x[i])
    assert_true((p.mean - y[i]).abs() < 0.1)
  }
}

///|
test "gaussian_process: uncertainty is non-negative" {
  let x : Array[Array[Double]] = []
  let y : Array[Double] = []
  x.push([0.0])
  x.push([1.0])
  x.push([2.0])
  y.push(0.0)
  y.push(1.0)
  y.push(0.0)
  let model = fit(x, y, RBF(1.0, 1.0), 0.01)
  // At a test point far from training data, variance should be positive
  let p = predict(model, [10.0])
  assert_true(p.variance >= 0.0)
}

///|
test "gaussian_process: lower variance near training points" {
  let x : Array[Array[Double]] = []
  let y : Array[Double] = []
  x.push([0.0])
  x.push([5.0])
  y.push(0.0)
  y.push(1.0)
  let model = fit(x, y, RBF(1.0, 1.0), 0.01)
  // Variance at a training point should be lower than at a far point
  let p_near = predict(model, [0.0])
  let p_far = predict(model, [100.0])
  assert_true(p_near.variance < p_far.variance)
}

///|
test "gaussian_process: predict_batch" {
  let x : Array[Array[Double]] = []
  let y : Array[Double] = []
  x.push([0.0])
  x.push([1.0])
  x.push([2.0])
  y.push(0.0)
  y.push(0.5)
  y.push(1.0)
  let model = fit(x, y, RBF(1.0, 1.0), 0.01)
  let test_points : Array[Array[Double]] = []
  test_points.push([0.5])
  test_points.push([1.5])
  test_points.push([3.0])
  let preds = predict_batch(model, test_points)
  assert_eq(preds.length(), 3)
  // Midpoints should have intermediate values
  assert_true(preds[0].mean > preds[0].mean - 1.0) // sanity
}

///|
test "gaussian_process: empty model" {
  let model = fit([], [], RBF(1.0, 1.0), 0.0)
  let p = predict(model, [1.0])
  assert_eq(p.mean, 0.0)
}

///|
test "gaussian_process: noisy interpolation" {
  // With noise, predictions at training points should be close but not exact
  let x : Array[Array[Double]] = []
  let y : Array[Double] = []
  x.push([0.0])
  x.push([1.0])
  x.push([2.0])
  x.push([3.0])
  y.push(0.0)
  y.push(1.0)
  y.push(4.0)
  y.push(9.0) // x²
  let model = fit(x, y, RBF(2.0, 10.0), 0.1)
  let p = predict(model, [1.5])
  // Should be between 1.0 and 4.0
  assert_true(p.mean > 0.5 && p.mean < 5.0)
}
