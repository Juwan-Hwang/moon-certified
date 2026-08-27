/// Linear Regression — Least Squares Fitting.
///
/// Fits a linear model y = a*x + b to a set of (x, y) data points
/// using the ordinary least squares (OLS) method. Also supports
/// polynomial regression (quadratic, cubic, etc.) via least squares
/// on a Vandermonde-like design matrix.
///
/// ## Complexity
/// - Linear fit: O(n) time, O(1) space.
/// - Polynomial fit (degree d): O(n*d²) time via normal equations.
/// - R² computation: O(n) time.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

///|
/// Result of a linear regression fit.
pub struct LinearFit {
  /// Slope (coefficient of x).
  slope : Double
  /// Intercept (constant term).
  intercept : Double
  /// Coefficient of determination (R²), 0 ≤ R² ≤ 1.
  r_squared : Double
}

///|
/// Fit a line y = slope * x + intercept to the given data points.
///
/// Uses the ordinary least squares (OLS) formula:
/// - slope = (n*Σxy - Σx*Σy) / (n*Σx² - (Σx)²)
/// - intercept = (Σy - slope*Σx) / n
///
/// Returns None if there are fewer than 2 points or if all x values
/// are identical (division by zero).
pub fn fit_linear(xs : Array[Double], ys : Array[Double]) -> LinearFit? {
  let n = xs.length()
  if n < 2 || n != ys.length() {
    return None
  }
  let mut sum_x = 0.0
  let mut sum_y = 0.0
  let mut sum_xy = 0.0
  let mut sum_x2 = 0.0
  let mut sum_y2 = 0.0
  for i = 0; i < n; i = i + 1 {
    let x = xs[i]
    let y = ys[i]
    sum_x = sum_x + x
    sum_y = sum_y + y
    sum_xy = sum_xy + x * y
    sum_x2 = sum_x2 + x * x
    sum_y2 = sum_y2 + y * y
  }
  let nd = n.to_double()
  let denom = nd * sum_x2 - sum_x * sum_x
  if denom.abs() < 1.0e-15 {
    return None // All x values are identical
  }
  let slope = (nd * sum_xy - sum_x * sum_y) / denom
  let intercept = (sum_y - slope * sum_x) / nd
  // R² = 1 - SS_res / SS_tot
  let mean_y = sum_y / nd
  let mut ss_res = 0.0
  let mut ss_tot = 0.0
  for i = 0; i < n; i = i + 1 {
    let predicted = slope * xs[i] + intercept
    ss_res = ss_res + (ys[i] - predicted) * (ys[i] - predicted)
    ss_tot = ss_tot + (ys[i] - mean_y) * (ys[i] - mean_y)
  }
  let r_sq = if ss_tot.abs() < 1.0e-15 {
    1.0 // All y values identical → perfect fit
  } else {
    1.0 - ss_res / ss_tot
  }
  Some({ slope, intercept, r_squared: r_sq, })
}

///|
/// Predict y for a given x using a fitted linear model.
pub fn predict(fit : LinearFit, x : Double) -> Double {
  fit.slope * x + fit.intercept
}

///|
/// Fit a polynomial of degree `d` to the given data points.
///
/// Returns the coefficients [c_0, c_1, ..., c_d] such that
/// y ≈ c_0 + c_1*x + c_2*x² + ... + c_d*x^d.
///
/// Uses the normal equations: (X^T X) c = X^T y, solved via Gaussian
/// elimination. For numerical stability with high-degree polynomials,
/// consider scaling the input data.
///
/// Returns None if there are fewer than d+1 points or if the system
/// is singular.
pub fn fit_polynomial(
  xs : Array[Double],
  ys : Array[Double],
  degree : Int,
) -> Array[Double]? {
  let n = xs.length()
  if n < degree + 1 || n != ys.length() || degree < 0 {
    return None
  }
  let d = degree + 1 // number of coefficients
  // Build normal equations matrix A (d×d) and vector b (d).
  // A[i][j] = Σ x^(i+j), b[i] = Σ y * x^i
  // Use makei to avoid sharing the same inner array reference.
  let a : Array[Array[Double]] = Array::makei(d, fn(_) { Array::make(d, 0.0) })
  let b = Array::make(d, 0.0)
  for k = 0; k < n; k = k + 1 {
    let x = xs[k]
    let y = ys[k]
    // Precompute powers of x.
    let x_powers : Array[Double] = Array::make(2 * d - 1, 1.0)
    for i = 1; i < 2 * d - 1; i = i + 1 {
      x_powers[i] = x_powers[i - 1] * x
    }
    for i = 0; i < d; i = i + 1 {
      b[i] = b[i] + y * x_powers[i]
      for j = 0; j < d; j = j + 1 {
        a[i][j] = a[i][j] + x_powers[i + j]
      }
    }
  }
  // Solve A * c = b using Gaussian elimination with partial pivoting.
  gaussian_elimination(a, b, d)
}

///|
/// Solve a system of linear equations A*x = b using Gaussian elimination
/// with partial pivoting. Returns the solution vector, or None if A is singular.
fn gaussian_elimination(
  a : Array[Array[Double]],
  b : Array[Double],
  n : Int,
) -> Array[Double]? {
  // Forward elimination with partial pivoting.
  for col = 0; col < n; col = col + 1 {
    // Find pivot (max absolute value in column).
    let mut max_row = col
    let mut max_val = a[col][col].abs()
    for row = col + 1; row < n; row = row + 1 {
      if a[row][col].abs() > max_val {
        max_val = a[row][col].abs()
        max_row = row
      }
    }
    // Check for singularity.
    if max_val < 1.0e-15 {
      return None
    }
    // Swap rows.
    if max_row != col {
      let tmp_row = a[max_row]
      a[max_row] = a[col]
      a[col] = tmp_row
      let tmp_val = b[max_row]
      b[max_row] = b[col]
      b[col] = tmp_val
    }
    // Eliminate below.
    let pivot = a[col][col]
    for row = col + 1; row < n; row = row + 1 {
      let factor = a[row][col] / pivot
      a[row][col] = 0.0
      for j = col + 1; j < n; j = j + 1 {
        a[row][j] = a[row][j] - factor * a[col][j]
      }
      b[row] = b[row] - factor * b[col]
    }
  }
  // Back substitution.
  let x = Array::make(n, 0.0)
  for i = n - 1; i >= 0; i = i - 1 {
    let mut sum = b[i]
    for j = i + 1; j < n; j = j + 1 {
      sum = sum - a[i][j] * x[j]
    }
    x[i] = sum / a[i][i]
  }
  Some(x)
}

///|
/// Predict y for a given x using polynomial coefficients.
pub fn predict_polynomial(coeffs : Array[Double], x : Double) -> Double {
  let mut result = 0.0
  let mut x_pow = 1.0
  for i = 0; i < coeffs.length(); i = i + 1 {
    result = result + coeffs[i] * x_pow
    x_pow = x_pow * x
  }
  result
}

///|
// Note: mean, variance, and std_dev are not re-defined here.
// Use the @descriptive package for these basic descriptive statistics,
// avoiding code duplication between stats sub-packages.

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "linear_regression: perfect linear fit" {
  let xs = [1.0, 2.0, 3.0, 4.0, 5.0]
  let ys = [2.0, 4.0, 6.0, 8.0, 10.0] // y = 2x
  match fit_linear(xs, ys) {
    Some(fit) => {
      assert_true((fit.slope - 2.0).abs() < 1.0e-10)
      assert_true((fit.intercept - 0.0).abs() < 1.0e-10)
      assert_true((fit.r_squared - 1.0).abs() < 1.0e-10)
    }
    None => assert_true(false)
  }
}

///|
test "linear_regression: with intercept" {
  let xs = [0.0, 1.0, 2.0, 3.0, 4.0]
  let ys = [1.0, 3.0, 5.0, 7.0, 9.0] // y = 2x + 1
  match fit_linear(xs, ys) {
    Some(fit) => {
      assert_true((fit.slope - 2.0).abs() < 1.0e-10)
      assert_true((fit.intercept - 1.0).abs() < 1.0e-10)
      assert_true((fit.r_squared - 1.0).abs() < 1.0e-10)
    }
    None => assert_true(false)
  }
}

///|
test "linear_regression: noisy data" {
  let xs = [1.0, 2.0, 3.0, 4.0, 5.0]
  let ys = [2.1, 3.9, 6.2, 7.8, 10.1] // approximately y = 2x
  match fit_linear(xs, ys) {
    Some(fit) => {
      assert_true((fit.slope - 2.0).abs() < 0.1)
      assert_true(fit.r_squared > 0.99)
    }
    None => assert_true(false)
  }
}

///|
test "linear_regression: predict" {
  let xs = [0.0, 1.0, 2.0, 3.0]
  let ys = [1.0, 3.0, 5.0, 7.0] // y = 2x + 1
  match fit_linear(xs, ys) {
    Some(fit) => {
      let y = predict(fit, 10.0)
      assert_true((y - 21.0).abs() < 1.0e-10)
    }
    None => assert_true(false)
  }
}

///|
test "linear_regression: insufficient data" {
  let xs = [1.0]
  let ys = [2.0]
  assert_true(fit_linear(xs, ys) is None)
}

///|
test "linear_regression: constant x" {
  let xs = [5.0, 5.0, 5.0]
  let ys = [1.0, 2.0, 3.0]
  assert_true(fit_linear(xs, ys) is None)
}

///|
test "linear_regression: polynomial fit" {
  // y = x²  (coeffs: [0, 0, 1])
  let xs = [0.0, 1.0, 2.0, 3.0, 4.0]
  let ys = [0.0, 1.0, 4.0, 9.0, 16.0]
  match fit_polynomial(xs, ys, 2) {
    Some(coeffs) => {
      assert_true((coeffs[0] - 0.0).abs() < 1.0e-6)
      assert_true((coeffs[1] - 0.0).abs() < 1.0e-6)
      assert_true((coeffs[2] - 1.0).abs() < 1.0e-6)
    }
    None => assert_true(false)
  }
}

///|
test "linear_regression: polynomial predict" {
  let coeffs = [1.0, 2.0, 3.0] // y = 1 + 2x + 3x²
  let y = predict_polynomial(coeffs, 2.0)
  // 1 + 4 + 12 = 17
  assert_true((y - 17.0).abs() < 1.0e-10)
}

///|
test "linear_regression: mean (via @descriptive)" {
  assert_true(
    (@descriptive.mean([1.0, 2.0, 3.0, 4.0, 5.0]) - 3.0).abs() < 1.0e-10,
  )
  assert_true((@descriptive.mean([10.0, 20.0]) - 15.0).abs() < 1.0e-10)
}

///|
test "linear_regression: variance (via @descriptive)" {
  // Variance of [1, 2, 3, 4, 5] = 2.0
  assert_true(
    (@descriptive.variance([1.0, 2.0, 3.0, 4.0, 5.0]) - 2.0).abs() < 1.0e-10,
  )
}

///|
test "linear_regression: std_dev (via @descriptive)" {
  let data = [1.0, 2.0, 3.0, 4.0, 5.0]
  let sd = @descriptive.stddev(data)
  // sqrt(2.0) ≈ 1.41421
  assert_true((sd - 2.0.sqrt()).abs() < 1.0e-10)
}
