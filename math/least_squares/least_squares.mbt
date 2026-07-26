/// Least Squares — linear and polynomial regression.
///
/// Finds the best-fit line (or polynomial) through a set of data
/// points by minimizing the sum of squared residuals. Uses the
/// normal equations method (X^T X) β = X^T y solved via Gaussian
/// elimination with partial pivoting.
///
/// ## Complexity
/// - Time:  O(n × m²) for n points and m parameters.
/// - Space: O(m²) for the normal equations matrix.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

///|
/// Helper: absolute value of double.
fn absd(x : Double) -> Double {
  if x < 0.0 {
    -x
  } else {
    x
  }
}

///|
/// Linear least-squares fit: y = a + b*x.
/// Returns (a, b, r²) where r² is the coefficient of determination.
pub fn linear_fit(points : Array[(Double, Double)]) -> (Double, Double, Double) {
  let n = points.length()
  if n < 2 {
    return (0.0, 0.0, 0.0)
  }
  let mut sum_x = 0.0
  let mut sum_y = 0.0
  let mut sum_xx = 0.0
  let mut sum_xy = 0.0
  let mut sum_yy = 0.0
  for i = 0; i < n; i = i + 1 {
    let (x, y) = points[i]
    sum_x = sum_x + x
    sum_y = sum_y + y
    sum_xx = sum_xx + x * x
    sum_xy = sum_xy + x * y
    sum_yy = sum_yy + y * y
  }
  let nd = n.to_double()
  let denom = nd * sum_xx - sum_x * sum_x
  if denom == 0.0 {
    return (sum_y / nd, 0.0, 0.0)
  }
  let b = (nd * sum_xy - sum_x * sum_y) / denom
  let a = (sum_y - b * sum_x) / nd
  // Compute r².
  let mean_y = sum_y / nd
  let mut ss_res = 0.0
  let mut ss_tot = 0.0
  for i = 0; i < n; i = i + 1 {
    let (x, y) = points[i]
    let predicted = a + b * x
    ss_res = ss_res + (y - predicted) * (y - predicted)
    ss_tot = ss_tot + (y - mean_y) * (y - mean_y)
  }
  let r2 = if ss_tot == 0.0 { 1.0 } else { 1.0 - ss_res / ss_tot }
  (a, b, r2)
}

///|
/// Polynomial least-squares fit of degree `d`: y = c₀ + c₁x + ... + cₐxᵈ.
/// Returns the coefficient array [c₀, c₁, ..., cₐ].
pub fn polynomial_fit(
  points : Array[(Double, Double)],
  degree : Int,
) -> Array[Double] {
  let n = points.length()
  let d = if degree < 0 { 0 } else { degree }
  if n < d + 1 {
    let a : Array[Double] = []
    for i = 0; i <= d; i = i + 1 {
      a.push(0.0)
    }
    return a
  }
  let m = d + 1 // Number of coefficients.
  // Build normal equations: A^T A * c = A^T y.
  let ata = FixedArray::make(m * m, 0.0)
  let aty = FixedArray::make(m, 0.0)
  for i = 0; i < n; i = i + 1 {
    let (x, y) = points[i]
    let x_powers = FixedArray::make(2 * d + 1, 1.0)
    for p = 1; p <= 2 * d; p = p + 1 {
      x_powers[p] = x_powers[p - 1] * x
    }
    for j = 0; j < m; j = j + 1 {
      aty[j] = aty[j] + y * x_powers[j]
      for k = 0; k < m; k = k + 1 {
        ata[j * m + k] = ata[j * m + k] + x_powers[j + k]
      }
    }
  }
  // Solve ATA * c = ATy via Gaussian elimination with partial pivoting.
  gaussian_solve(ata, aty, m)
}

///|
fn gaussian_solve(
  a : FixedArray[Double],
  b : FixedArray[Double],
  n : Int,
) -> Array[Double] {
  // Augmented matrix in a copy.
  let aug = FixedArray::make(n * (n + 1), 0.0)
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      aug[i * (n + 1) + j] = a[i * n + j]
    }
    aug[i * (n + 1) + n] = b[i]
  }
  // Forward elimination with partial pivoting.
  for col = 0; col < n; col = col + 1 {
    let mut max_row = col
    let mut max_val = absd(aug[col * (n + 1) + col])
    for row = col + 1; row < n; row = row + 1 {
      let val = absd(aug[row * (n + 1) + col])
      if val > max_val {
        max_val = val
        max_row = row
      }
    }
    // Swap rows.
    if max_row != col {
      for j = 0; j <= n; j = j + 1 {
        let tmp = aug[col * (n + 1) + j]
        aug[col * (n + 1) + j] = aug[max_row * (n + 1) + j]
        aug[max_row * (n + 1) + j] = tmp
      }
    }
    let pivot = aug[col * (n + 1) + col]
    if absd(pivot) < 0.000000000000001 {
      continue // Singular — skip.
    }
    for row = col + 1; row < n; row = row + 1 {
      let factor = aug[row * (n + 1) + col] / pivot
      for j = col; j <= n; j = j + 1 {
        aug[row * (n + 1) + j] = aug[row * (n + 1) + j] -
          factor * aug[col * (n + 1) + j]
      }
    }
  }
  // Back substitution.
  let x = FixedArray::make(n, 0.0)
  let mut i = n - 1
  while i >= 0 {
    let mut sum = aug[i * (n + 1) + n]
    for j = i + 1; j < n; j = j + 1 {
      sum = sum - aug[i * (n + 1) + j] * x[j]
    }
    let diag = aug[i * (n + 1) + i]
    x[i] = if absd(diag) < 0.000000000000001 { 0.0 } else { sum / diag }
    i = i - 1
  }
  let result : Array[Double] = []
  for i = 0; i < n; i = i + 1 {
    result.push(x[i])
  }
  result
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "linear_fit: perfect line" {
  // y = 2 + 3x
  let points = [(0.0, 2.0), (1.0, 5.0), (2.0, 8.0), (3.0, 11.0)]
  let (a, b, r2) = linear_fit(points)
  assert_true(absd(a - 2.0) < 0.0000000001)
  assert_true(absd(b - 3.0) < 0.0000000001)
  assert_true(absd(r2 - 1.0) < 0.0000000001)
}

///|
test "linear_fit: noisy data" {
  let points = [(0.0, 1.1), (1.0, 2.9), (2.0, 3.2), (3.0, 4.8)]
  let (_, _, r2) = linear_fit(points)
  assert_true(r2 > 0.9)
}

///|
test "linear_fit: horizontal line" {
  let points = [(0.0, 5.0), (1.0, 5.0), (2.0, 5.0)]
  let (a, b, _) = linear_fit(points)
  assert_true(absd(a - 5.0) < 0.0000000001)
  assert_true(absd(b) < 0.0000000001)
}

///|
test "polynomial_fit: quadratic" {
  // y = 1 + 2x + 3x²
  let points = [(-2.0, 9.0), (-1.0, 2.0), (0.0, 1.0), (1.0, 6.0), (2.0, 17.0)]
  let coeffs = polynomial_fit(points, 2)
  assert_true(absd(coeffs[0] - 1.0) < 0.000001)
  assert_true(absd(coeffs[1] - 2.0) < 0.000001)
  assert_true(absd(coeffs[2] - 3.0) < 0.000001)
}

///|
test "polynomial_fit: linear" {
  let points = [(0.0, 1.0), (1.0, 3.0), (2.0, 5.0), (3.0, 7.0)]
  let coeffs = polynomial_fit(points, 1)
  assert_true(absd(coeffs[0] - 1.0) < 0.000001)
  assert_true(absd(coeffs[1] - 2.0) < 0.000001)
}
