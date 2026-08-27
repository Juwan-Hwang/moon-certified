/// Kalman Filter — Linear and Extended Kalman Filter for state estimation.
///
/// The Kalman filter is an optimal recursive estimator for linear dynamic
/// systems perturbed by Gaussian noise. It maintains a state estimate and its
/// error covariance, updating both with each new measurement using a
/// predict–update cycle.
///
/// ## Linear Kalman Filter
///
/// State model:
/// ```text
/// x_{k} = F · x_{k-1} + B · u_{k} + w_{k},   w ~ N(0, Q)
/// z_{k} = H · x_{k} + v_{k},                  v ~ N(0, R)
/// ```
///
/// **Predict:**
/// - x̂⁻ = F · x̂ + B · u
/// - P⁻ = F · P · Fᵀ + Q
///
/// **Update:**
/// - y = z − H · x̂⁻                    (innovation / measurement residual)
/// - S = H · P⁻ · Hᵀ + R               (innovation covariance)
/// - K = P⁻ · Hᵀ · S⁻¹                 (Kalman gain)
/// - x̂ = x̂⁻ + K · y                   (updated state estimate)
/// - P = (I − K · H) · P⁻              (updated covariance, Joseph form)
///
/// The **Joseph form** `P = (I − KH)P(I − KH)ᵀ + KRKᵀ` is used for the
/// covariance update because it guarantees that P remains symmetric positive
/// semidefinite even in the presence of round-off, unlike the simpler
/// `P = (I − KH)P` form which can lose PSD-ness.
///
/// ## Extended Kalman Filter (EKF)
///
/// For nonlinear systems:
/// ```text
/// x_{k} = f(x_{k-1}, u_{k}) + w_{k}
/// z_{k} = h(x_{k}) + v_{k}
/// ```
///
/// The EKF linearises f and h around the current estimate using Jacobians:
/// - F = ∂f/∂x, H = ∂h/∂x
/// Then applies the standard KF equations with these linearised matrices.
///
/// ## Numerical Stability
///
/// - **Joseph-form covariance update**: guarantees PSD output.
/// - **Symmetric enforcement**: P is symmetrised after each update.
/// - **Matrix inversion via Gaussian elimination** with partial pivoting.
///
/// ## Complexity
///
/// - Time: O(n³) per step (dominated by matrix inversion for S⁻¹).
/// - Space: O(n²) for covariance and Jacobian storage.
///
/// ## References
///
/// - Kalman, R. E. (1960). "A New Approach to Linear Filtering and Prediction
///   Problems." *Journal of Basic Engineering*, 82(1), 35–45.
/// - Welch, G. and Bishop, G. "An Introduction to the Kalman Filter."
///   TR 95-041, UNC Chapel Hill.
/// - Bar-Shalom, Y., Li, X. R., and Kirubarajan, T. *Estimation with
///   Applications to Tracking and Navigation*. Wiley, 2001.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Matrix helpers (row-major Array[Array[Double]])
// ---------------------------------------------------------------------------

///|
/// Create an n×m zero matrix.
fn mat_zeros(rows : Int, cols : Int) -> Array[Array[Double]] {
  let r : Array[Array[Double]] = []
  for i = 0; i < rows; i = i + 1 {
    r.push(Array::make(cols, 0.0))
  }
  r
}

///|
/// Create an n×n identity matrix.
fn mat_identity(n : Int) -> Array[Array[Double]] {
  let r = mat_zeros(n, n)
  for i = 0; i < n; i = i + 1 {
    r[i][i] = 1.0
  }
  r
}

///|
/// Matrix multiplication: C = A (m×k) × B (k×n) → m×n.
fn mat_mul(
  a : Array[Array[Double]],
  b : Array[Array[Double]],
  m : Int,
  k : Int,
  n : Int,
) -> Array[Array[Double]] {
  let r = mat_zeros(m, n)
  for i = 0; i < m; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      let mut s = 0.0
      for l = 0; l < k; l = l + 1 {
        s = s + a[i][l] * b[l][j]
      }
      r[i][j] = s
    }
  }
  r
}

///|
/// Matrix transpose: A (m×n) → Aᵀ (n×m).
fn mat_transpose(
  a : Array[Array[Double]],
  m : Int,
  n : Int,
) -> Array[Array[Double]] {
  let r = mat_zeros(n, m)
  for i = 0; i < m; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      r[j][i] = a[i][j]
    }
  }
  r
}

///|
/// Matrix addition: C = A + B (both m×n).
fn mat_add(
  a : Array[Array[Double]],
  b : Array[Array[Double]],
  m : Int,
  n : Int,
) -> Array[Array[Double]] {
  let r = mat_zeros(m, n)
  for i = 0; i < m; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      r[i][j] = a[i][j] + b[i][j]
    }
  }
  r
}

///|
/// Matrix subtraction: C = A − B (both m×n).
fn mat_sub(
  a : Array[Array[Double]],
  b : Array[Array[Double]],
  m : Int,
  n : Int,
) -> Array[Array[Double]] {
  let r = mat_zeros(m, n)
  for i = 0; i < m; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      r[i][j] = a[i][j] - b[i][j]
    }
  }
  r
}

///|
/// Symmetrise a square matrix: R = (A + Aᵀ) / 2.
fn mat_symmetrise(a : Array[Array[Double]], n : Int) -> Array[Array[Double]] {
  let r = mat_zeros(n, n)
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      r[i][j] = (a[i][j] + a[j][i]) / 2.0
    }
  }
  r
}

///|
/// Invert an n×n matrix via Gaussian elimination with partial pivoting.
/// Returns None if the matrix is singular.
fn mat_invert(a : Array[Array[Double]], n : Int) -> Array[Array[Double]]? {
  // Build augmented matrix [A | I].
  let aug : Array[Array[Double]] = []
  for i = 0; i < n; i = i + 1 {
    let row = Array::make(2 * n, 0.0)
    for j = 0; j < n; j = j + 1 {
      row[j] = a[i][j]
    }
    row[n + i] = 1.0
    aug.push(row)
  }
  // Forward elimination with partial pivoting.
  for col = 0; col < n; col = col + 1 {
    // Find pivot.
    let mut max_row = col
    let mut max_val = aug[col][col].abs()
    for r = col + 1; r < n; r = r + 1 {
      if aug[r][col].abs() > max_val {
        max_val = aug[r][col].abs()
        max_row = r
      }
    }
    if max_val < 1.0e-15 {
      return None // Singular.
    }
    // Swap rows.
    if max_row != col {
      let tmp = aug[max_row]
      aug[max_row] = aug[col]
      aug[col] = tmp
    }
    // Eliminate below.
    let pivot = aug[col][col]
    for r = col + 1; r < n; r = r + 1 {
      let factor = aug[r][col] / pivot
      for c = col; c < 2 * n; c = c + 1 {
        aug[r][c] = aug[r][c] - factor * aug[col][c]
      }
    }
  }
  // Back substitution.
  for col = n - 1; col >= 0; col = col - 1 {
    let pivot = aug[col][col]
    // Normalise pivot row.
    for c = col; c < 2 * n; c = c + 1 {
      aug[col][c] = aug[col][c] / pivot
    }
    // Eliminate above.
    for r = col - 1; r >= 0; r = r - 1 {
      let factor = aug[r][col]
      for c = col; c < 2 * n; c = c + 1 {
        aug[r][c] = aug[r][c] - factor * aug[col][c]
      }
    }
  }
  // Extract inverse.
  let inv = mat_zeros(n, n)
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      inv[i][j] = aug[i][n + j]
    }
  }
  Some(inv)
}

///|
/// Matrix-vector multiply: y = A (m×n) × x (n) → m.
fn mat_vec_mul(
  a : Array[Array[Double]],
  x : Array[Double],
  m : Int,
  n : Int,
) -> Array[Double] {
  let r = Array::make(m, 0.0)
  for i = 0; i < m; i = i + 1 {
    let mut s = 0.0
    for j = 0; j < n; j = j + 1 {
      s = s + a[i][j] * x[j]
    }
    r[i] = s
  }
  r
}

///|
/// Vector addition.
fn vec_add(a : Array[Double], b : Array[Double], n : Int) -> Array[Double] {
  let r = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    r[i] = a[i] + b[i]
  }
  r
}

///|
/// Vector subtraction.
fn vec_sub(a : Array[Double], b : Array[Double], n : Int) -> Array[Double] {
  let r = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    r[i] = a[i] - b[i]
  }
  r
}

// ---------------------------------------------------------------------------
// Linear Kalman Filter
// ---------------------------------------------------------------------------

///|
/// Configuration for the linear Kalman filter.
///
/// - `state_dim`: Dimension of the state vector x.
/// - `meas_dim`: Dimension of the measurement vector z.
/// - `control_dim`: Dimension of the control input u (0 if no control).
/// - `f_mat`: State transition matrix (state_dim × state_dim).
/// - `h_mat`: Measurement matrix (meas_dim × state_dim).
/// - `q_mat`: Process noise covariance (state_dim × state_dim).
/// - `r_mat`: Measurement noise covariance (meas_dim × meas_dim).
/// - `b_mat`: Control input matrix (state_dim × control_dim), or empty if none.
pub struct KFConfig {
  state_dim : Int
  meas_dim : Int
  control_dim : Int
  f_mat : Array[Array[Double]]
  h_mat : Array[Array[Double]]
  q_mat : Array[Array[Double]]
  r_mat : Array[Array[Double]]
  b_mat : Array[Array[Double]]
}

///|
/// State of the Kalman filter.
///
/// - `x`: State estimate (state_dim).
/// - `p_mat`: Error covariance (state_dim × state_dim).
pub struct KFState {
  x : Array[Double]
  p_mat : Array[Array[Double]]
}

///|
/// Create a new Kalman filter state with initial estimate and covariance.
pub fn kf_init(
  _config : KFConfig,
  x0 : Array[Double],
  p0 : Array[Array[Double]],
) -> KFState {
  { x: x0, p_mat: p0, }
}

///|
/// Prediction step: project the state estimate ahead in time.
///
/// x̂⁻ = F · x̂ + B · u
/// P⁻ = F · P · Fᵀ + Q
pub fn kf_predict(
  config : KFConfig,
  state : KFState,
  u : Array[Double],
) -> KFState {
  let n = config.state_dim
  // x̂⁻ = F · x̂
  let x_pred = mat_vec_mul(config.f_mat, state.x, n, n)
  // Add control input: B · u (if applicable).
  let x_final = if config.control_dim > 0 && config.b_mat.length() > 0 {
    let bu = mat_vec_mul(config.b_mat, u, n, config.control_dim)
    vec_add(x_pred, bu, n)
  } else {
    x_pred
  }
  // P⁻ = F · P · Fᵀ + Q
  let fp = mat_mul(config.f_mat, state.p_mat, n, n, n)
  let ft = mat_transpose(config.f_mat, n, n)
  let fpft = mat_mul(fp, ft, n, n, n)
  let p_pred = mat_add(fpft, config.q_mat, n, n)
  // Symmetrise for numerical stability.
  let p_final = mat_symmetrise(p_pred, n)
  { x: x_final, p_mat: p_final, }
}

///|
/// Update step: correct the predicted estimate with a measurement.
///
/// Uses the **Joseph form** for the covariance update:
/// `P = (I − KH)P(I − KH)ᵀ + KRKᵀ`
/// which guarantees that P remains symmetric positive semidefinite.
///
/// Returns `None` if the innovation covariance S is singular (numerical
/// failure), in which case the caller should skip this measurement.
pub fn kf_update(
  config : KFConfig,
  state : KFState,
  z : Array[Double],
) -> KFState? {
  let n = config.state_dim
  let m = config.meas_dim
  // Innovation: y = z − H · x̂⁻
  let hx = mat_vec_mul(config.h_mat, state.x, m, n)
  let y = vec_sub(z, hx, m)
  // Innovation covariance: S = H · P · Hᵀ + R
  let hp = mat_mul(config.h_mat, state.p_mat, m, n, n)
  let ht = mat_transpose(config.h_mat, m, n)
  let hpht = mat_mul(hp, ht, m, n, m)
  let s_mat = mat_add(hpht, config.r_mat, m, m)
  // S⁻¹
  let s_inv = match mat_invert(s_mat, m) {
    Some(inv) => inv
    None => return None
  }
  // Kalman gain: K = P · Hᵀ · S⁻¹
  let pht = mat_mul(state.p_mat, ht, n, n, m)
  let k_mat = mat_mul(pht, s_inv, n, m, m)
  // Updated state: x̂ = x̂⁻ + K · y
  let ky = mat_vec_mul(k_mat, y, n, m)
  let x_new = vec_add(state.x, ky, n)
  // Joseph-form covariance update:
  // P = (I − KH) · P · (I − KH)ᵀ + K · R · Kᵀ
  let i_mat = mat_identity(n)
  let kh = mat_mul(k_mat, config.h_mat, n, m, n)
  let imkh = mat_sub(i_mat, kh, n, n)
  let imkht = mat_transpose(imkh, n, n)
  let term1 = mat_mul(imkh, state.p_mat, n, n, n)
  let term1_full = mat_mul(term1, imkht, n, n, n)
  let kr = mat_mul(k_mat, config.r_mat, n, m, m)
  let krt = mat_transpose(k_mat, n, m)
  let term2 = mat_mul(kr, krt, n, m, n)
  let p_new = mat_add(term1_full, term2, n, n)
  // Symmetrise for numerical stability.
  let p_final = mat_symmetrise(p_new, n)
  Some({ x: x_new, p_mat: p_final, })
}

///|
/// Full predict + update cycle for the linear Kalman filter.
///
/// Convenience function that chains `kf_predict` and `kf_update`.
/// If the update fails (singular S), returns the predicted state only.
pub fn kf_step(
  config : KFConfig,
  state : KFState,
  u : Array[Double],
  z : Array[Double],
) -> KFState {
  let predicted = kf_predict(config, state, u)
  match kf_update(config, predicted, z) {
    Some(updated) => updated
    None => predicted
  }
}

// ---------------------------------------------------------------------------
// Extended Kalman Filter (EKF)
// ---------------------------------------------------------------------------

///|
/// Configuration for the Extended Kalman Filter.
///
/// - `state_dim`: Dimension of the state vector.
/// - `meas_dim`: Dimension of the measurement vector.
/// - `control_dim`: Dimension of the control input (0 if none).
/// - `q_mat`: Process noise covariance (state_dim × state_dim).
/// - `r_mat`: Measurement noise covariance (meas_dim × meas_dim).
pub struct EKFConfig {
  state_dim : Int
  meas_dim : Int
  control_dim : Int
  q_mat : Array[Array[Double]]
  r_mat : Array[Array[Double]]
}

///|
/// State of the Extended Kalman Filter.
pub struct EKFState {
  x : Array[Double]
  p_mat : Array[Array[Double]]
}

///|
/// Create a new EKF state with initial estimate and covariance.
pub fn ekf_init(x0 : Array[Double], p0 : Array[Array[Double]]) -> EKFState {
  { x: x0, p_mat: p0, }
}

///|
/// EKF prediction step.
///
/// - `f`: State transition function f(x, u) → x'.
/// - `f_jac`: Jacobian of f w.r.t. x, evaluated at (x, u). (state_dim × state_dim)
///
/// x̂⁻ = f(x̂, u)
/// P⁻ = F · P · Fᵀ + Q
pub fn ekf_predict(
  config : EKFConfig,
  state : EKFState,
  f : (Array[Double], Array[Double]) -> Array[Double],
  f_jac : Array[Array[Double]],
  u : Array[Double],
) -> EKFState {
  let n = config.state_dim
  let x_pred = f(state.x, u)
  // P⁻ = F · P · Fᵀ + Q
  let fp = mat_mul(f_jac, state.p_mat, n, n, n)
  let ft = mat_transpose(f_jac, n, n)
  let fpft = mat_mul(fp, ft, n, n, n)
  let p_pred = mat_add(fpft, config.q_mat, n, n)
  let p_final = mat_symmetrise(p_pred, n)
  { x: x_pred, p_mat: p_final, }
}

///|
/// EKF update step.
///
/// - `h`: Measurement function h(x) → z'.
/// - `h_jac`: Jacobian of h w.r.t. x, evaluated at x̂⁻. (meas_dim × state_dim)
///
/// Uses Joseph-form covariance update for numerical stability.
pub fn ekf_update(
  config : EKFConfig,
  state : EKFState,
  h : (Array[Double]) -> Array[Double],
  h_jac : Array[Array[Double]],
  z : Array[Double],
) -> EKFState? {
  let n = config.state_dim
  let m = config.meas_dim
  // Innovation: y = z − h(x̂⁻)
  let hx = h(state.x)
  let y = vec_sub(z, hx, m)
  // Innovation covariance: S = H · P · Hᵀ + R
  let hp = mat_mul(h_jac, state.p_mat, m, n, n)
  let ht = mat_transpose(h_jac, m, n)
  let hpht = mat_mul(hp, ht, m, n, m)
  let s_mat = mat_add(hpht, config.r_mat, m, m)
  let s_inv = match mat_invert(s_mat, m) {
    Some(inv) => inv
    None => return None
  }
  // Kalman gain: K = P · Hᵀ · S⁻¹
  let pht = mat_mul(state.p_mat, ht, n, n, m)
  let k_mat = mat_mul(pht, s_inv, n, m, m)
  // Updated state: x̂ = x̂⁻ + K · y
  let ky = mat_vec_mul(k_mat, y, n, m)
  let x_new = vec_add(state.x, ky, n)
  // Joseph-form covariance update.
  let i_mat = mat_identity(n)
  let kh = mat_mul(k_mat, h_jac, n, m, n)
  let imkh = mat_sub(i_mat, kh, n, n)
  let imkht = mat_transpose(imkh, n, n)
  let term1 = mat_mul(imkh, state.p_mat, n, n, n)
  let term1_full = mat_mul(term1, imkht, n, n, n)
  let kr = mat_mul(k_mat, config.r_mat, n, m, m)
  let krt = mat_transpose(k_mat, n, m)
  let term2 = mat_mul(kr, krt, n, m, n)
  let p_new = mat_add(term1_full, term2, n, n)
  let p_final = mat_symmetrise(p_new, n)
  Some({ x: x_new, p_mat: p_final, })
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "kf: constant velocity model — track a moving object" {
  // State: [position, velocity], Measurement: [position]
  let config : KFConfig = {
    state_dim: 2,
    meas_dim: 1,
    control_dim: 0,
    f_mat: [[1.0, 1.0], [0.0, 1.0]],
    h_mat: [[1.0, 0.0]],
    q_mat: [[0.01, 0.0], [0.0, 0.01]],
    r_mat: [[1.0]],
    b_mat: [],
  }
  let mut state = kf_init(config, [0.0, 0.0], [[100.0, 0.0], [0.0, 100.0]])
  let measurements = [1.1, 1.9, 3.2, 3.8, 5.1]
  for i = 0; i < measurements.length(); i = i + 1 {
    state = kf_step(config, state, [], [measurements[i]])
  }
  assert_true(state.x[0] > 4.0 && state.x[0] < 6.0)
  assert_true(state.x[1] > 0.5 && state.x[1] < 1.5)
  assert_true(state.p_mat[0][0] < 100.0)
  assert_true(state.p_mat[1][1] < 100.0)
}

///|
test "kf: predict only — state propagates with F" {
  let config : KFConfig = {
    state_dim: 2,
    meas_dim: 1,
    control_dim: 0,
    f_mat: [[1.0, 1.0], [0.0, 1.0]],
    h_mat: [[1.0, 0.0]],
    q_mat: [[0.0, 0.0], [0.0, 0.0]],
    r_mat: [[1.0]],
    b_mat: [],
  }
  let state = kf_init(config, [0.0, 2.0], [[1.0, 0.0], [0.0, 1.0]])
  let predicted = kf_predict(config, state, [])
  assert_true(predicted.x[0] > 1.99 && predicted.x[0] < 2.01)
  assert_true(predicted.x[1] > 1.99 && predicted.x[1] < 2.01)
}

///|
test "kf: control input — B·u applied" {
  let config : KFConfig = {
    state_dim: 1,
    meas_dim: 1,
    control_dim: 1,
    f_mat: [[1.0]],
    h_mat: [[1.0]],
    q_mat: [[0.0]],
    r_mat: [[1.0]],
    b_mat: [[2.0]],
  }
  let state = kf_init(config, [0.0], [[1.0]])
  let predicted = kf_predict(config, state, [5.0])
  assert_true(predicted.x[0] > 9.99 && predicted.x[0] < 10.01)
}

///|
test "kf: measurement update reduces uncertainty" {
  let config : KFConfig = {
    state_dim: 1,
    meas_dim: 1,
    control_dim: 0,
    f_mat: [[1.0]],
    h_mat: [[1.0]],
    q_mat: [[0.0]],
    r_mat: [[1.0]],
    b_mat: [],
  }
  let state = kf_init(config, [0.0], [[100.0]])
  let predicted = kf_predict(config, state, [])
  let updated = kf_update(config, predicted, [5.0])
  assert_true(updated is Some(_))
  let u = updated.unwrap()
  assert_true(u.x[0] > 4.0 && u.x[0] < 6.0)
  assert_true(u.p_mat[0][0] < 1.0)
}

///|
test "kf: multiple measurements converge to true value" {
  let config : KFConfig = {
    state_dim: 1,
    meas_dim: 1,
    control_dim: 0,
    f_mat: [[1.0]],
    h_mat: [[1.0]],
    q_mat: [[0.001]],
    r_mat: [[4.0]],
    b_mat: [],
  }
  let mut state = kf_init(config, [0.0], [[100.0]])
  let measurements = [
    40.0, 43.0, 41.0, 44.0, 42.0, 41.0, 43.0, 42.0, 42.0, 43.0,
  ]
  for i = 0; i < measurements.length(); i = i + 1 {
    state = kf_step(config, state, [], [measurements[i]])
  }
  assert_true(state.x[0] > 41.0 && state.x[0] < 43.0)
}

///|
test "kf: 2D position tracking" {
  let dt = 1.0
  let config : KFConfig = {
    state_dim: 4,
    meas_dim: 2,
    control_dim: 0,
    f_mat: [
      [1.0, 0.0, dt, 0.0],
      [0.0, 1.0, 0.0, dt],
      [0.0, 0.0, 1.0, 0.0],
      [0.0, 0.0, 0.0, 1.0],
    ],
    h_mat: [[1.0, 0.0, 0.0, 0.0], [0.0, 1.0, 0.0, 0.0]],
    q_mat: [
      [0.01, 0.0, 0.0, 0.0],
      [0.0, 0.01, 0.0, 0.0],
      [0.0, 0.0, 0.01, 0.0],
      [0.0, 0.0, 0.0, 0.01],
    ],
    r_mat: [[1.0, 0.0], [0.0, 1.0]],
    b_mat: [],
  }
  let mut state = kf_init(config, [0.0, 0.0, 1.0, 1.0], [
    [10.0, 0.0, 0.0, 0.0],
    [0.0, 10.0, 0.0, 0.0],
    [0.0, 0.0, 10.0, 0.0],
    [0.0, 0.0, 0.0, 10.0],
  ])
  let meas = [[1.1, 0.9], [2.2, 1.8], [2.9, 3.1], [4.1, 3.9], [5.0, 5.2]]
  for i = 0; i < meas.length(); i = i + 1 {
    state = kf_step(config, state, [], meas[i])
  }
  assert_true(state.x[0] > 4.0 && state.x[0] < 6.0)
  assert_true(state.x[1] > 4.0 && state.x[1] < 6.0)
  assert_true(state.x[2] > 0.5 && state.x[2] < 1.5)
  assert_true(state.x[3] > 0.5 && state.x[3] < 1.5)
}

///|
test "kf: covariance stays symmetric and PSD" {
  let config : KFConfig = {
    state_dim: 2,
    meas_dim: 1,
    control_dim: 0,
    f_mat: [[1.0, 1.0], [0.0, 1.0]],
    h_mat: [[1.0, 0.0]],
    q_mat: [[0.1, 0.0], [0.0, 0.1]],
    r_mat: [[1.0]],
    b_mat: [],
  }
  let mut state = kf_init(config, [0.0, 0.0], [[10.0, 0.0], [0.0, 10.0]])
  for i = 0; i < 20; i = i + 1 {
    state = kf_step(config, state, [], [i.to_double() + 0.5])
  }
  let p01 = state.p_mat[0][1]
  let p10 = state.p_mat[1][0]
  assert_true((p01 - p10).abs() < 1.0e-10)
  assert_true(state.p_mat[0][0] > 0.0)
  assert_true(state.p_mat[1][1] > 0.0)
  let det = state.p_mat[0][0] * state.p_mat[1][1] -
    state.p_mat[0][1] * state.p_mat[1][0]
  assert_true(det >= -1.0e-10)
}

///|
test "kf: singular R returns None" {
  let config : KFConfig = {
    state_dim: 1,
    meas_dim: 1,
    control_dim: 0,
    f_mat: [[1.0]],
    h_mat: [[0.0]],
    q_mat: [[0.0]],
    r_mat: [[0.0]],
    b_mat: [],
  }
  let state = kf_init(config, [0.0], [[0.0]])
  let result = kf_update(config, state, [1.0])
  assert_true(result is None)
}

///|
test "ekf: tracking a nonlinear system (range-bearing)" {
  let dt = 1.0
  let config : EKFConfig = {
    state_dim: 4,
    meas_dim: 1,
    control_dim: 0,
    q_mat: [
      [0.01, 0.0, 0.0, 0.0],
      [0.0, 0.01, 0.0, 0.0],
      [0.0, 0.0, 0.01, 0.0],
      [0.0, 0.0, 0.0, 0.01],
    ],
    r_mat: [[1.0]],
  }
  let f = fn(x : Array[Double], _u : Array[Double]) -> Array[Double] {
    [x[0] + dt * x[2], x[1] + dt * x[3], x[2], x[3]]
  }
  let f_jac : Array[Array[Double]] = [
    [1.0, 0.0, dt, 0.0],
    [0.0, 1.0, 0.0, dt],
    [0.0, 0.0, 1.0, 0.0],
    [0.0, 0.0, 0.0, 1.0],
  ]
  let h = fn(x : Array[Double]) -> Array[Double] {
    let r = (x[0] * x[0] + x[1] * x[1]).sqrt()
    [r]
  }
  let make_h_jac = fn(x : Array[Double]) -> Array[Array[Double]] {
    let r = (x[0] * x[0] + x[1] * x[1]).sqrt()
    let r_safe = if r < 1.0e-10 { 1.0e-10 } else { r }
    [[x[0] / r_safe, x[1] / r_safe, 0.0, 0.0]]
  }
  let mut state = ekf_init([10.0, 0.0, -1.0, 0.0], [
    [1.0, 0.0, 0.0, 0.0],
    [0.0, 1.0, 0.0, 0.0],
    [0.0, 0.0, 1.0, 0.0],
    [0.0, 0.0, 0.0, 1.0],
  ])
  let true_ranges = [10.0, 9.0, 8.0, 7.0, 6.0]
  for i = 0; i < true_ranges.length(); i = i + 1 {
    state = ekf_predict(config, state, f, f_jac, [])
    let h_jac = make_h_jac(state.x)
    let z = [true_ranges[i] + 0.1]
    let updated = ekf_update(config, state, h, h_jac, z)
    assert_true(updated is Some(_))
    state = updated.unwrap()
  }
  assert_true(state.x[0] > 4.0 && state.x[0] < 7.0)
  assert_true(state.x[1] > -1.0 && state.x[1] < 1.0)
  assert_true(state.x[2] > -1.5 && state.x[2] < -0.5)
}

///|
test "ekf: pendulum tracking" {
  let g_grav = 9.81
  let l_len = 1.0
  let dt = 0.1
  let config : EKFConfig = {
    state_dim: 2,
    meas_dim: 1,
    control_dim: 0,
    q_mat: [[0.001, 0.0], [0.0, 0.001]],
    r_mat: [[0.01]],
  }
  let f = fn(x : Array[Double], _u : Array[Double]) -> Array[Double] {
    [x[0] + x[1] * dt, x[1] - g_grav / l_len * @math.sin(x[0]) * dt]
  }
  let make_f_jac = fn(x : Array[Double]) -> Array[Array[Double]] {
    [[1.0, dt], [-(g_grav / l_len) * @math.cos(x[0]) * dt, 1.0]]
  }
  let h = fn(x : Array[Double]) -> Array[Double] { [x[0]] }
  let h_jac : Array[Array[Double]] = [[1.0, 0.0]]
  let mut state = ekf_init([0.1, 0.0], [[0.01, 0.0], [0.0, 0.01]])
  for i = 0; i < 10; i = i + 1 {
    let f_jac = make_f_jac(state.x)
    state = ekf_predict(config, state, f, f_jac, [])
    let z = [0.1 * @math.cos(dt * i.to_double()) + 0.005]
    let updated = ekf_update(config, state, h, h_jac, z)
    assert_true(updated is Some(_))
    state = updated.unwrap()
  }
  assert_true(state.x[0].abs() < 0.5)
  assert_true(state.x[1].abs() < 1.0)
}

///|
test "ekf: covariance stays PSD after many steps" {
  let config : EKFConfig = {
    state_dim: 2,
    meas_dim: 1,
    control_dim: 0,
    q_mat: [[0.01, 0.0], [0.0, 0.01]],
    r_mat: [[0.1]],
  }
  let f = fn(x : Array[Double], _u : Array[Double]) -> Array[Double] {
    [x[0] + 0.1 * x[1], 0.99 * x[1]]
  }
  let f_jac : Array[Array[Double]] = [[1.0, 0.1], [0.0, 0.99]]
  let h = fn(x : Array[Double]) -> Array[Double] { [x[0]] }
  let h_jac : Array[Array[Double]] = [[1.0, 0.0]]
  let mut state = ekf_init([1.0, 0.5], [[1.0, 0.0], [0.0, 1.0]])
  for i = 0; i < 50; i = i + 1 {
    state = ekf_predict(config, state, f, f_jac, [])
    let updated = ekf_update(config, state, h, h_jac, [
      1.0 + 0.1 * i.to_double(),
    ])
    assert_true(updated is Some(_))
    state = updated.unwrap()
  }
  let p01 = state.p_mat[0][1]
  let p10 = state.p_mat[1][0]
  assert_true((p01 - p10).abs() < 1.0e-10)
  assert_true(state.p_mat[0][0] > 0.0)
  assert_true(state.p_mat[1][1] > 0.0)
  let det = state.p_mat[0][0] * state.p_mat[1][1] -
    state.p_mat[0][1] * state.p_mat[1][0]
  assert_true(det >= -1.0e-10)
}

///|
test "kf: zero process noise — pure smoothing" {
  let config : KFConfig = {
    state_dim: 1,
    meas_dim: 1,
    control_dim: 0,
    f_mat: [[1.0]],
    h_mat: [[1.0]],
    q_mat: [[0.0]],
    r_mat: [[1.0]],
    b_mat: [],
  }
  let mut state = kf_init(config, [5.0], [[0.0]])
  state = kf_step(config, state, [], [100.0])
  assert_true(state.x[0] > 4.99 && state.x[0] < 5.01)
}

///|
test "kf: high R — filter ignores noisy measurements" {
  let config : KFConfig = {
    state_dim: 1,
    meas_dim: 1,
    control_dim: 0,
    f_mat: [[1.0]],
    h_mat: [[1.0]],
    q_mat: [[0.01]],
    r_mat: [[1000000.0]],
    b_mat: [],
  }
  let mut state = kf_init(config, [10.0], [[1.0]])
  for i = 0; i < 10; i = i + 1 {
    state = kf_step(config, state, [], [(i - 5).to_double() * 100.0])
  }
  assert_true(state.x[0] > 5.0 && state.x[0] < 15.0)
}
