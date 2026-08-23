/// Multivariate Normal Distribution — PDF, Sampling, and Inference.
///
/// This module provides production-grade computation for the multivariate
/// normal (Gaussian) distribution N(mu, Sigma), including:
///
/// - **Probability density function (PDF)** and **log-PDF**.
/// - **Mahalanobis distance** computation.
/// - **Random sampling** via Cholesky decomposition.
/// - **Marginal and conditional distributions**.
/// - **Maximum likelihood estimation (MLE)** of mean and covariance.
///
/// ## Mathematical Background
///
/// The PDF of the d-dimensional multivariate normal N(mu, Sigma) is:
///
/// ```text
/// f(x) = (2 pi)^{-d/2} |Sigma|^{-1/2} exp(-0.5 * (x-mu)^T Sigma^{-1} (x-mu))
/// ```
///
/// where |Sigma| is the determinant of the covariance matrix and
/// (x-mu)^T Sigma^{-1} (x-mu) is the squared Mahalanobis distance.
///
/// The log-PDF is:
/// ```text
/// ln f(x) = -0.5 * (d * ln(2*pi) + ln|Sigma| + d^2(x, mu))
/// ```
///
/// Sampling: if Sigma = L * L^T (Cholesky), then x = mu + L * z where
/// z ~ N(0, I_d) gives x ~ N(mu, Sigma).
///
/// ## Matrix Storage
///
/// Matrices are stored as `FixedArray[Double]` in **row-major** order,
/// consistent with the `math/cholesky` module. Vector inputs use
/// `FixedArray[Double]`.
///
/// ## References
///
/// - Tong, Y. L. "The Multivariate Normal Distribution," Springer, 1990.
/// - Eaton, M. L. "Multivariate Statistics: A Vector Space Approach,"
///   IMS Lecture Notes, 1983.
/// - Gentle, J. E. "Computational Statistics," Springer, 2009, Ch. 4.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

///|
/// Natural logarithm of 2*pi.
let ln_2pi : Double = 1.83787706640934548356

// ---------------------------------------------------------------------------
// Struct
// ---------------------------------------------------------------------------

///|
/// A multivariate normal distribution N(mu, Sigma).
///
/// Construct with `MVN::new(mean, cov, dim)`. The covariance matrix must be
/// symmetric positive definite (SPD); construction returns `None` if Cholesky
/// decomposition fails (indicating non-PD covariance).
pub struct MVN {
  /// Dimensionality d.
  dim : Int
  /// Mean vector (length d).
  mean : FixedArray[Double]
  /// Covariance matrix (d*d, row-major).
  cov : FixedArray[Double]
  /// Cholesky factor L (lower triangular, d*d, row-major).
  chol : @cholesky.Cholesky
  /// Log-determinant of covariance: ln|Sigma|.
  log_det : Double
}

///|
/// Create a multivariate normal distribution.
///
/// Returns `None` if the covariance matrix is not symmetric positive definite
/// (Cholesky decomposition fails).
pub fn MVN::new(
  mean : FixedArray[Double],
  cov : FixedArray[Double],
  dim : Int,
) -> MVN? {
  if mean.length() != dim || cov.length() != dim * dim {
    return None
  }
  match @cholesky.decompose(cov, dim) {
    Some(chol) => {
      let log_det = @cholesky.log_det(chol)
      Some({ dim, mean, cov, chol, log_det })
    }
    None => None
  }
}

// ---------------------------------------------------------------------------
// PDF and Log-PDF
// ---------------------------------------------------------------------------

///|
/// Compute the squared Mahalanobis distance: d^2 = (x-mu)^T Sigma^{-1} (x-mu).
///
/// Uses the Cholesky factor: solve L*y = (x-mu) by forward substitution,
/// then d^2 = y^T * y.
///
/// **Complexity**: O(d^2) for the solve, O(d) for the dot product.
pub fn mahalanobis_squared(mvn : MVN, x : FixedArray[Double]) -> Double {
  let d = mvn.dim
  // Compute diff = x - mu.
  let diff = FixedArray::make(d, 0.0)
  for i = 0; i < d; i = i + 1 {
    diff[i] = x[i] - mvn.mean[i]
  }
  // Solve L * y = diff (forward substitution using Cholesky).
  let y = @cholesky.solve_lower(mvn.chol, diff)
  // d^2 = y^T * y.
  let mut sq = 0.0
  for i = 0; i < d; i = i + 1 {
    sq = sq + y[i] * y[i]
  }
  sq
}

///|
/// Compute the natural logarithm of the PDF: ln f(x).
///
/// ln f(x) = -0.5 * (d * ln(2*pi) + ln|Sigma| + d^2(x, mu))
///
/// **Complexity**: O(d^2).
pub fn log_pdf(mvn : MVN, x : FixedArray[Double]) -> Double {
  let d2 = mahalanobis_squared(mvn, x)
  -0.5 * (mvn.dim.to_double() * ln_2pi + mvn.log_det + d2)
}

///|
/// Compute the probability density function: f(x).
///
/// Returns exp(log_pdf(x)). For very small densities, this may underflow to 0.0.
///
/// **Complexity**: O(d^2).
pub fn pdf(mvn : MVN, x : FixedArray[Double]) -> Double {
  @math.exp(log_pdf(mvn, x))
}

// ---------------------------------------------------------------------------
// Sampling
// ---------------------------------------------------------------------------

///|
/// Sample a single point from N(mu, Sigma).
///
/// Uses the Cholesky factor: x = mu + L * z, where z ~ N(0, I_d).
/// The caller provides a function `z_gen` that returns standard normal samples.
///
/// **Complexity**: O(d^2) for the matrix-vector multiply.
pub fn sample(mvn : MVN, z_gen : () -> Double) -> FixedArray[Double] {
  let d = mvn.dim
  // Generate d standard normal samples.
  let z = FixedArray::make(d, 0.0)
  for i = 0; i < d; i = i + 1 {
    z[i] = z_gen()
  }
  // x = mu + L * z, where L is the lower-triangular Cholesky factor.
  let l = @cholesky.factor(mvn.chol)
  let x = FixedArray::make(d, 0.0)
  for i = 0; i < d; i = i + 1 {
    let mut s = mvn.mean[i]
    for j = 0; j <= i; j = j + 1 {
      s = s + l[i * d + j] * z[j]
    }
    x[i] = s
  }
  x
}

// ---------------------------------------------------------------------------
// Marginal and Conditional Distributions
// ---------------------------------------------------------------------------

///|
/// Extract the marginal distribution for a subset of dimensions.
///
/// Given indices `idx` (0-based), returns N(mu[idx], Sigma[idx, idx]).
///
/// **Complexity**: O(k^3) for the Cholesky decomposition of the sub-matrix,
/// where k = |idx|.
pub fn marginal(mvn : MVN, idx : Array[Int]) -> MVN? {
  let k = idx.length()
  if k == 0 || k > mvn.dim {
    return None
  }
  let sub_mean = FixedArray::make(k, 0.0)
  let sub_cov = FixedArray::make(k * k, 0.0)
  for i = 0; i < k; i = i + 1 {
    sub_mean[i] = mvn.mean[idx[i]]
    for j = 0; j < k; j = j + 1 {
      sub_cov[i * k + j] = mvn.cov[idx[i] * mvn.dim + idx[j]]
    }
  }
  MVN::new(sub_mean, sub_cov, k)
}

///|
/// Compute the conditional distribution X_1 | X_2 = x_2.
///
/// Given a partition of dimensions into `idx1` (conditioned) and `idx2`
/// (conditioning), and the observed values `x2` for idx2, returns:
///
/// X_1 | X_2 = x_2 ~ N(mu_cond, Sigma_cond), where:
/// - mu_cond = mu_1 + Sigma_12 * Sigma_22^{-1} * (x_2 - mu_2)
/// - Sigma_cond = Sigma_11 - Sigma_12 * Sigma_22^{-1} * Sigma_21
///
/// **Complexity**: O(k2^3 + k1*k2 + k1^2*k2 + k1^3), where k1=|idx1|, k2=|idx2|.
pub fn conditional(
  mvn : MVN,
  idx1 : Array[Int],
  idx2 : Array[Int],
  x2 : FixedArray[Double],
) -> MVN? {
  let k1 = idx1.length()
  let k2 = idx2.length()
  if k1 == 0 || k2 == 0 || k1 + k2 > mvn.dim || x2.length() != k2 {
    return None
  }
  let d = mvn.dim
  // Extract sub-matrices.
  let mu1 = FixedArray::make(k1, 0.0)
  let mu2 = FixedArray::make(k2, 0.0)
  let s11 = FixedArray::make(k1 * k1, 0.0)
  let s12 = FixedArray::make(k1 * k2, 0.0)
  let s22 = FixedArray::make(k2 * k2, 0.0)
  for i = 0; i < k1; i = i + 1 {
    mu1[i] = mvn.mean[idx1[i]]
    for j = 0; j < k1; j = j + 1 {
      s11[i * k1 + j] = mvn.cov[idx1[i] * d + idx1[j]]
    }
    for j = 0; j < k2; j = j + 1 {
      s12[i * k2 + j] = mvn.cov[idx1[i] * d + idx2[j]]
    }
  }
  for i = 0; i < k2; i = i + 1 {
    mu2[i] = mvn.mean[idx2[i]]
    for j = 0; j < k2; j = j + 1 {
      s22[i * k2 + j] = mvn.cov[idx2[i] * d + idx2[j]]
    }
  }
  // Cholesky of S22.
  match @cholesky.decompose(s22, k2) {
    Some(chol22) => {
      // Compute diff = x2 - mu2.
      let diff = FixedArray::make(k2, 0.0)
      for i = 0; i < k2; i = i + 1 {
        diff[i] = x2[i] - mu2[i]
      }
      // Solve S22 * y = diff  =>  y = S22^{-1} * diff.
      let y = @cholesky.solve(chol22, diff)
      // mu_cond = mu1 + S12 * y.
      let mu_cond = FixedArray::make(k1, 0.0)
      for i = 0; i < k1; i = i + 1 {
        let mut s = mu1[i]
        for j = 0; j < k2; j = j + 1 {
          s = s + s12[i * k2 + j] * y[j]
        }
        mu_cond[i] = s
      }
      // S22_inv = inverse of S22.
      let s22_inv = @cholesky.inverse(chol22)
      // Sigma_cond = S11 - S12 * S22_inv * S21.
      // S21 = S12^T, so S12 * S22_inv * S21 = S12 * (S22_inv * S12^T).
      // Compute temp = S22_inv * S21 (k2 x k1), then Sigma_cond = S11 - S12 * temp.
      let sigma_cond = FixedArray::make(k1 * k1, 0.0)
      for i = 0; i < k1; i = i + 1 {
        for j = 0; j < k1; j = j + 1 {
          let mut s = s11[i * k1 + j]
          for k = 0; k < k2; k = k + 1 {
            // S12[i, k] * S22_inv[k, :] * S21[:, j] = S12[i,k] * sum_l(S22_inv[k,l] * S12[j,l])
            let mut inner = 0.0
            for l = 0; l < k2; l = l + 1 {
              inner = inner + s22_inv[k * k2 + l] * s12[j * k2 + l]
            }
            s = s - s12[i * k2 + k] * inner
          }
          sigma_cond[i * k1 + j] = s
        }
      }
      MVN::new(mu_cond, sigma_cond, k1)
    }
    None => None
  }
}

// ---------------------------------------------------------------------------
// Maximum Likelihood Estimation
// ---------------------------------------------------------------------------

///|
/// Estimate the mean vector from a set of observations (MLE).
///
/// mu_hat = (1/n) * sum_i x_i
///
/// **Input**: `data` is an n*d array (n observations, each of dimension d),
/// stored row-major.
///
/// **Complexity**: O(n * d).
pub fn estimate_mean(
  data : FixedArray[Double],
  n : Int,
  d : Int,
) -> FixedArray[Double] {
  let mean = FixedArray::make(d, 0.0)
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < d; j = j + 1 {
      mean[j] = mean[j] + data[i * d + j]
    }
  }
  let inv_n = 1.0 / n.to_double()
  for j = 0; j < d; j = j + 1 {
    mean[j] = mean[j] * inv_n
  }
  mean
}

///|
/// Estimate the covariance matrix from a set of observations (MLE).
///
/// Sigma_hat = (1/n) * sum_i (x_i - mu_hat)(x_i - mu_hat)^T
///
/// Uses the unbiased estimator (dividing by n-1) by default.
///
/// **Input**: `data` is an n*d array, `mean` is the estimated mean (length d).
///
/// **Complexity**: O(n * d^2).
pub fn estimate_covariance(
  data : FixedArray[Double],
  mean : FixedArray[Double],
  n : Int,
  d : Int,
) -> FixedArray[Double] {
  let cov = FixedArray::make(d * d, 0.0)
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < d; j = j + 1 {
      for k = 0; k < d; k = k + 1 {
        cov[j * d + k] = cov[j * d + k] +
          (data[i * d + j] - mean[j]) * (data[i * d + k] - mean[k])
      }
    }
  }
  let denom = if n > 1 { (n - 1).to_double() } else { 1.0 }
  for j = 0; j < d * d; j = j + 1 {
    cov[j] = cov[j] / denom
  }
  cov
}

///|
/// Fit a multivariate normal distribution to data using MLE.
///
/// Estimates both mean and covariance from the data, then constructs
/// the MVN distribution.
///
/// **Input**: `data` is an n*d array.
///
/// **Complexity**: O(n * d^2 + d^3).
pub fn fit(data : FixedArray[Double], n : Int, d : Int) -> MVN? {
  if n < 2 || d < 1 || data.length() != n * d {
    return None
  }
  let mean = estimate_mean(data, n, d)
  let cov = estimate_covariance(data, mean, n, d)
  MVN::new(mean, cov, d)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "mvn: univariate normal" {
  // 1D normal with mean=2, var=9 (std=3).
  let mean = FixedArray::make(1, 2.0)
  let cov = FixedArray::make(1, 9.0)
  match MVN::new(mean, cov, 1) {
    Some(mvn) => {
      let x = FixedArray::make(1, 2.0)
      let lp = log_pdf(mvn, x)
      // ln f(2) = -0.5 * (ln(2pi) + ln(9) + 0) = -0.5 * (1.8379 + 2.1972)
      let expected = -0.5 * (1.8378770664093453 + 2.1972245773362196)
      assert_true((lp - expected).abs() < 1.0e-10)
      let p = pdf(mvn, x)
      // f(2) = 1/(3*sqrt(2pi)) ~ 0.13298
      let expected_p = 1.0 / (3.0 * (2.0 * 3.14159265358979323846).sqrt())
      assert_true((p - expected_p).abs() < 1.0e-10)
    }
    None => assert_true(false)
  }
}

///|
test "mvn: identity covariance" {
  // 2D standard normal: mean=[0,0], cov=I.
  let mean = FixedArray::make(2, 0.0)
  let cov = FixedArray::make(4, 0.0)
  cov[0] = 1.0
  cov[3] = 1.0
  match MVN::new(mean, cov, 2) {
    Some(mvn) => {
      let x = FixedArray::make(2, 0.0)
      let lp = log_pdf(mvn, x)
      // ln f(0,0) = -0.5 * (2*ln(2pi) + 0 + 0) = -ln(2pi)
      let expected = -1.8378770664093453
      assert_true((lp - expected).abs() < 1.0e-10)
    }
    None => assert_true(false)
  }
}

///|
test "mvn: mahalanobis distance identity" {
  let mean = FixedArray::make(2, 0.0)
  let cov = FixedArray::make(4, 0.0)
  cov[0] = 1.0
  cov[3] = 1.0
  match MVN::new(mean, cov, 2) {
    Some(mvn) => {
      let x = FixedArray::make(2, 0.0)
      x[0] = 3.0
      x[1] = 4.0
      let d2 = mahalanobis_squared(mvn, x)
      // With identity cov, d^2 = 3^2 + 4^2 = 25.
      assert_true((d2 - 25.0).abs() < 1.0e-10)
    }
    None => assert_true(false)
  }
}

///|
test "mvn: mahalanobis distance correlated" {
  // cov = [[4, 2], [2, 3]]
  let mean = FixedArray::make(2, 0.0)
  let cov = FixedArray::make(4, 0.0)
  cov[0] = 4.0
  cov[1] = 2.0
  cov[2] = 2.0
  cov[3] = 3.0
  match MVN::new(mean, cov, 2) {
    Some(mvn) => {
      let x = FixedArray::make(2, 0.0)
      x[0] = 1.0
      x[1] = 1.0
      let d2 = mahalanobis_squared(mvn, x)
      // Sigma^{-1} = 1/(4*3-2*2) * [[3, -2], [-2, 4]] = 1/8 * [[3,-2],[-2,4]]
      // d^2 = [1,1] * Sigma^{-1} * [1,1]^T = 1/8 * (3 - 2 - 2 + 4) = 3/8
      assert_true((d2 - 0.375).abs() < 1.0e-10)
    }
    None => assert_true(false)
  }
}

///|
test "mvn: pdf symmetry" {
  // For a symmetric distribution, f(mu + d) = f(mu - d).
  let mean = FixedArray::make(2, 0.0)
  let cov = FixedArray::make(4, 0.0)
  cov[0] = 2.0
  cov[1] = 1.0
  cov[2] = 1.0
  cov[3] = 2.0
  match MVN::new(mean, cov, 2) {
    Some(mvn) => {
      let x1 = FixedArray::make(2, 0.0)
      x1[0] = 1.0
      x1[1] = 0.5
      let x2 = FixedArray::make(2, 0.0)
      x2[0] = -1.0
      x2[1] = -0.5
      let p1 = pdf(mvn, x1)
      let p2 = pdf(mvn, x2)
      assert_true((p1 - p2).abs() < 1.0e-10)
    }
    None => assert_true(false)
  }
}

///|
test "mvn: pdf maximized at mean" {
  let mean = FixedArray::make(2, 0.0)
  mean[0] = 1.0
  mean[1] = -1.0
  let cov = FixedArray::make(4, 0.0)
  cov[0] = 2.0
  cov[1] = 0.5
  cov[2] = 0.5
  cov[3] = 1.5
  match MVN::new(mean, cov, 2) {
    Some(mvn) => {
      let p_mean = pdf(mvn, mean)
      let x = FixedArray::make(2, 0.0)
      x[0] = 2.0
      x[1] = 0.0
      let p_other = pdf(mvn, x)
      assert_true(p_mean > p_other)
    }
    None => assert_true(false)
  }
}

///|
test "mvn: sampling produces correct distribution" {
  // Sample from N(0, I_2) and check statistics.
  let mean = FixedArray::make(2, 0.0)
  let cov = FixedArray::make(4, 0.0)
  cov[0] = 1.0
  cov[3] = 1.0
  match MVN::new(mean, cov, 2) {
    Some(mvn) => {
      // Simple PRNG for reproducibility.
      let mut state = 42L
      let z_gen = fn() {
        state = state ^ (state << 13)
        state = state ^ (state >> 7)
        state = state ^ (state << 17)
        let u1 = ((state >> 11) & 0x1FFFFFFFFFFFFFL).to_double() /
          9007199254740992.0
        state = state ^ (state << 13)
        state = state ^ (state >> 7)
        state = state ^ (state << 17)
        let u2 = ((state >> 11) & 0x1FFFFFFFFFFFFFL).to_double() /
          9007199254740992.0
        let u1_safe = if u1 < 1.0e-300 { 1.0e-300 } else { u1 }
        (-2.0 * @math.ln(u1_safe)).sqrt() *
        @math.cos(2.0 * 3.14159265358979323846 * u2)
      }
      let n = 5000
      let mut sum_x = 0.0
      let mut sum_y = 0.0
      let mut sum_xx = 0.0
      let mut sum_yy = 0.0
      for i = 0; i < n; i = i + 1 {
        let x = sample(mvn, z_gen)
        sum_x = sum_x + x[0]
        sum_y = sum_y + x[1]
        sum_xx = sum_xx + x[0] * x[0]
        sum_yy = sum_yy + x[1] * x[1]
      }
      let mean_x = sum_x / n.to_double()
      let mean_y = sum_y / n.to_double()
      let var_x = sum_xx / n.to_double() - mean_x * mean_x
      let var_y = sum_yy / n.to_double() - mean_y * mean_y
      // E[X] = 0, Var[X] = 1.
      assert_true(mean_x.abs() < 0.1)
      assert_true(mean_y.abs() < 0.1)
      assert_true((var_x - 1.0).abs() < 0.15)
      assert_true((var_y - 1.0).abs() < 0.15)
    }
    None => assert_true(false)
  }
}

///|
test "mvn: marginal distribution" {
  // 3D normal, marginal over dims [0, 2].
  let mean = FixedArray::make(3, 0.0)
  mean[0] = 1.0
  mean[1] = 2.0
  mean[2] = 3.0
  let cov = FixedArray::make(9, 0.0)
  cov[0] = 2.0
  cov[1] = 0.5
  cov[2] = 0.3
  cov[3] = 0.5
  cov[4] = 1.0
  cov[5] = 0.2
  cov[6] = 0.3
  cov[7] = 0.2
  cov[8] = 3.0
  match MVN::new(mean, cov, 3) {
    Some(mvn) =>
      match marginal(mvn, [0, 2]) {
        Some(marg) => {
          assert_eq(marg.dim, 2)
          assert_true((marg.mean[0] - 1.0).abs() < 1.0e-10)
          assert_true((marg.mean[1] - 3.0).abs() < 1.0e-10)
          assert_true((marg.cov[0] - 2.0).abs() < 1.0e-10)
          assert_true((marg.cov[1] - 0.3).abs() < 1.0e-10)
          assert_true((marg.cov[2] - 0.3).abs() < 1.0e-10)
          assert_true((marg.cov[3] - 3.0).abs() < 1.0e-10)
        }
        None => assert_true(false)
      }
    None => assert_true(false)
  }
}

///|
test "mvn: conditional distribution" {
  // Bivariate normal: X1 | X2 = x2.
  // cov = [[1, 0.5], [0.5, 1]], mu = [0, 0].
  // X1 | X2 = 1 ~ N(0.5, 0.75).
  let mean = FixedArray::make(2, 0.0)
  let cov = FixedArray::make(4, 0.0)
  cov[0] = 1.0
  cov[1] = 0.5
  cov[2] = 0.5
  cov[3] = 1.0
  match MVN::new(mean, cov, 2) {
    Some(mvn) => {
      let x2 = FixedArray::make(1, 0.0)
      x2[0] = 1.0
      match conditional(mvn, [0], [1], x2) {
        Some(cond) => {
          assert_eq(cond.dim, 1)
          // mu_cond = 0 + 0.5 * 1^{-1} * (1 - 0) = 0.5.
          assert_true((cond.mean[0] - 0.5).abs() < 1.0e-10)
          // var_cond = 1 - 0.5 * 1 * 0.5 = 0.75.
          assert_true((cond.cov[0] - 0.75).abs() < 1.0e-10)
        }
        None => assert_true(false)
      }
    }
    None => assert_true(false)
  }
}

///|
test "mvn: estimate_mean and covariance" {
  // Data: 3 observations of dim 2.
  // [1, 2], [3, 4], [5, 6]
  let data = FixedArray::make(6, 0.0)
  data[0] = 1.0
  data[1] = 2.0
  data[2] = 3.0
  data[3] = 4.0
  data[4] = 5.0
  data[5] = 6.0
  let n = 3
  let d = 2
  let mean = estimate_mean(data, n, d)
  // mean = [3, 4]
  assert_true((mean[0] - 3.0).abs() < 1.0e-10)
  assert_true((mean[1] - 4.0).abs() < 1.0e-10)
  let cov = estimate_covariance(data, mean, n, d)
  // cov = [[4, 4], [4, 4]] (unbiased: divide by n-1=2)
  // sum of (x_i - mean)(x_i - mean)^T:
  // [-2,-2]^T * [-2,-2] = [[4,4],[4,4]]
  // [0,0]^T * [0,0] = [[0,0],[0,0]]
  // [2,2]^T * [2,2] = [[4,4],[4,4]]
  // sum = [[8,8],[8,8]], /2 = [[4,4],[4,4]]
  assert_true((cov[0] - 4.0).abs() < 1.0e-10)
  assert_true((cov[1] - 4.0).abs() < 1.0e-10)
  assert_true((cov[2] - 4.0).abs() < 1.0e-10)
  assert_true((cov[3] - 4.0).abs() < 1.0e-10)
}

///|
test "mvn: fit to data" {
  // Fit a 2D normal to 4 non-collinear points.
  let data = FixedArray::make(8, 0.0)
  data[0] = 0.0
  data[1] = 0.0
  data[2] = 2.0
  data[3] = 0.0
  data[4] = 0.0
  data[5] = 2.0
  data[6] = 2.0
  data[7] = 2.0
  match fit(data, 4, 2) {
    Some(mvn) => {
      assert_eq(mvn.dim, 2)
      // mean = [1, 1]
      assert_true((mvn.mean[0] - 1.0).abs() < 1.0e-10)
      assert_true((mvn.mean[1] - 1.0).abs() < 1.0e-10)
    }
    None => assert_true(false)
  }
}

///|
test "mvn: non-PD covariance returns None" {
  let mean = FixedArray::make(2, 0.0)
  let cov = FixedArray::make(4, 0.0)
  // [[1, 2], [2, 1]] has eigenvalues 3 and -1, not PD.
  cov[0] = 1.0
  cov[1] = 2.0
  cov[2] = 2.0
  cov[3] = 1.0
  match MVN::new(mean, cov, 2) {
    Some(_) => assert_true(false)
    None => assert_true(true)
  }
}

///|
test "mvn: log_pdf sum for independent components" {
  // If X = (X1, X2) with independent components, ln f(x) = ln f1(x1) + ln f2(x2).
  let mean = FixedArray::make(2, 0.0)
  let cov = FixedArray::make(4, 0.0)
  cov[0] = 4.0 // var1 = 4
  cov[3] = 9.0 // var2 = 9
  // cov[1] = cov[2] = 0 (independent)
  match MVN::new(mean, cov, 2) {
    Some(mvn) => {
      let x = FixedArray::make(2, 0.0)
      x[0] = 1.0
      x[1] = 1.0
      let lp = log_pdf(mvn, x)
      // ln f1(1) = -0.5 * (ln(2pi) + ln(4) + 1/4)
      let lp1 = -0.5 * (1.8378770664093453 + 1.3862943611198906 + 0.25)
      let lp2 = -0.5 * (1.8378770664093453 + 2.1972245773362196 + 1.0 / 9.0)
      assert_true((lp - (lp1 + lp2)).abs() < 1.0e-8)
    }
    None => assert_true(false)
  }
}

///|
test "mvn: higher dim mahalanobis" {
  // 3D diagonal covariance.
  let mean = FixedArray::make(3, 0.0)
  let cov = FixedArray::make(9, 0.0)
  cov[0] = 1.0
  cov[4] = 4.0
  cov[8] = 9.0
  match MVN::new(mean, cov, 3) {
    Some(mvn) => {
      let x = FixedArray::make(3, 0.0)
      x[0] = 1.0
      x[1] = 2.0
      x[2] = 3.0
      let d2 = mahalanobis_squared(mvn, x)
      // d^2 = 1/1 + 4/4 + 9/9 = 3
      assert_true((d2 - 3.0).abs() < 1.0e-10)
    }
    None => assert_true(false)
  }
}

///|
test "mvn: conditional independence" {
  // If Sigma_12 = 0, then X1 | X2 = x2 = X1 (no update).
  let mean = FixedArray::make(2, 0.0)
  mean[0] = 1.0
  mean[1] = 2.0
  let cov = FixedArray::make(4, 0.0)
  cov[0] = 3.0
  cov[3] = 5.0
  // cov[1] = cov[2] = 0 (independent)
  match MVN::new(mean, cov, 2) {
    Some(mvn) => {
      let x2 = FixedArray::make(1, 0.0)
      x2[0] = 100.0
      match conditional(mvn, [0], [1], x2) {
        Some(cond) => {
          // mu_cond = 1 + 0 = 1, var_cond = 3 - 0 = 3.
          assert_true((cond.mean[0] - 1.0).abs() < 1.0e-10)
          assert_true((cond.cov[0] - 3.0).abs() < 1.0e-10)
        }
        None => assert_true(false)
      }
    }
    None => assert_true(false)
  }
}
