/// LDA — Linear Discriminant Analysis.
///
/// Supervised dimensionality reduction: finds linear combinations of features
/// that best separate the classes, maximising the ratio of between-class
/// variance to within-class variance.
///
/// ## Algorithm
/// 1. Compute per-class means `μ_k` and overall mean `μ`.
/// 2. Within-class scatter: `SW = Σ_k Σ_{i∈C_k} (x_i − μ_k)(x_i − μ_k)ᵀ`
/// 3. Between-class scatter: `SB = Σ_k n_k (μ_k − μ)(μ_k − μ)ᵀ`
/// 4. Regularise: `SW_reg = SW + λ·I` (default `λ = 1e-4`) for stability.
/// 5. Solve `SW_reg⁻¹ · SB` and extract its top eigenvectors by power
///    iteration with deflation (same technique as PCA).
/// 6. Project samples onto the retained eigenvectors.
///
/// ## Complexity
/// - Time: `O(n·d² + d³ + n_comp·iter·d²)` — scatter build, matrix inverse,
///   and `n_comp` power sweeps.
/// - Space: `O(d²)` for scatter matrices and component store.
///
/// ## Limitations
/// - At most `min(n_classes−1, d)` meaningful discriminant axes.
/// - `n_components` is clamped to `min(n_classes−1, d)`.
/// - Small samples (`n < d`) benefit from the regularisation term.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

///|
/// Maximum power-iteration sweeps per component.
let lda_max_iter : Int = 1000

///|
/// Relative convergence tolerance on the Rayleigh quotient.
let lda_tol : Double = 1.0e-12

///|
/// Ridge regularisation added to the within-class scatter before inversion.
/// Prevents singularity when `n < d` or features are collinear.
let lda_default_reg : Double = 1.0e-4

// ---------------------------------------------------------------------------
// Local math helpers
// ---------------------------------------------------------------------------

///|
fn lda_sqrt(x : Double) -> Double {
  if x <= 0.0 {
    return 0.0
  }
  let mut guess = x
  if guess > 1.0 {
    guess = x / 2.0
  }
  for i = 0; i < 30; i = i + 1 {
    guess = (guess + x / guess) / 2.0
  }
  guess
}

///|
fn lda_dot(a : Array[Double], b : Array[Double]) -> Double {
  let n = a.length()
  if b.length() != n {
    return 0.0
  }
  let mut s = 0.0
  for i = 0; i < n; i = i + 1 {
    s = s + a[i] * b[i]
  }
  s
}

///|
fn lda_l2_norm(v : Array[Double]) -> Double {
  lda_dot(v, v).sqrt()
}

///|
fn lda_mat_vec(m : Array[Array[Double]], v : Array[Double]) -> Array[Double] {
  let d = m.length()
  let out = Array::make(d, 0.0)
  for i = 0; i < d; i = i + 1 {
    let row = m[i]
    let mut s = 0.0
    for j = 0; j < d; j = j + 1 {
      s = s + row[j] * v[j]
    }
    out[i] = s
  }
  out
}

///|
fn lda_rayleigh(m : Array[Array[Double]], v : Array[Double]) -> Double {
  lda_dot(v, lda_mat_vec(m, v))
}

///|
fn lda_orthogonalize_in_place(
  v : Array[Double],
  prev : Array[Array[Double]],
) -> Unit {
  for k = 0; k < prev.length(); k = k + 1 {
    let u = prev[k]
    let proj = lda_dot(v, u)
    for i = 0; i < v.length(); i = i + 1 {
      v[i] = v[i] - proj * u[i]
    }
  }
}

///|
fn lda_normalize_in_place(v : Array[Double]) -> Double {
  let nrm = lda_l2_norm(v)
  if nrm > 0.0 {
    for i = 0; i < v.length(); i = i + 1 {
      v[i] = v[i] / nrm
    }
  }
  nrm
}

///|
fn lda_fix_sign(v : Array[Double]) -> Unit {
  let n = v.length()
  if n == 0 {
    return
  }
  let mut max_idx = 0
  let mut max_abs = v[0].abs()
  for i = 1; i < n; i = i + 1 {
    let a = v[i].abs()
    if a > max_abs {
      max_abs = a
      max_idx = i
    }
  }
  if v[max_idx] < 0.0 {
    for i = 0; i < n; i = i + 1 {
      v[i] = -v[i]
    }
  }
}

// ---------------------------------------------------------------------------
// Matrix inversion via Gauss-Jordan with partial pivoting
// ---------------------------------------------------------------------------

///|
/// Invert a `d×d` matrix using Gauss-Jordan elimination with partial pivoting.
/// Returns `None` if the matrix is (numerically) singular.
fn lda_matrix_inverse(
  m : Array[Array[Double]],
  d : Int,
) -> Array[Array[Double]]? {
  // Build augmented [m | I]
  let aug : Array[Array[Double]] = []
  for i = 0; i < d; i = i + 1 {
    let row = Array::make(2 * d, 0.0)
    for j = 0; j < d; j = j + 1 {
      row[j] = m[i][j]
    }
    row[d + i] = 1.0
    aug.push(row)
  }
  // Forward elimination with partial pivoting
  for col = 0; col < d; col = col + 1 {
    // Find pivot
    let mut pivot_row = col
    let mut max_val = aug[col][col].abs()
    for r = col + 1; r < d; r = r + 1 {
      let v = aug[r][col].abs()
      if v > max_val {
        max_val = v
        pivot_row = r
      }
    }
    if max_val < 1.0e-15 {
      return None // Singular
    }
    // Swap rows
    if pivot_row != col {
      let tmp = aug[col]
      aug[col] = aug[pivot_row]
      aug[pivot_row] = tmp
    }
    // Scale pivot row
    let pivot = aug[col][col]
    for j = 0; j < 2 * d; j = j + 1 {
      aug[col][j] = aug[col][j] / pivot
    }
    // Eliminate column from all other rows
    for r = 0; r < d; r = r + 1 {
      if r != col {
        let factor = aug[r][col]
        if factor != 0.0 {
          for j = 0; j < 2 * d; j = j + 1 {
            aug[r][j] = aug[r][j] - factor * aug[col][j]
          }
        }
      }
    }
  }
  // Extract inverse from right half
  let inv : Array[Array[Double]] = []
  for i = 0; i < d; i = i + 1 {
    let row = Array::make(d, 0.0)
    for j = 0; j < d; j = j + 1 {
      row[j] = aug[i][d + j]
    }
    inv.push(row)
  }
  Some(inv)
}

///|
/// Multiply two `d×d` matrices: `C = A · B`.
fn lda_mat_mul(
  a : Array[Array[Double]],
  b : Array[Array[Double]],
  d : Int,
) -> Array[Array[Double]] {
  let c : Array[Array[Double]] = []
  for i = 0; i < d; i = i + 1 {
    let row = Array::make(d, 0.0)
    for j = 0; j < d; j = j + 1 {
      let mut s = 0.0
      for k = 0; k < d; k = k + 1 {
        s = s + a[i][k] * b[k][j]
      }
      row[j] = s
    }
    c.push(row)
  }
  c
}

// ---------------------------------------------------------------------------
// Power iteration with deflation (same as PCA)
// ---------------------------------------------------------------------------

///|
fn lda_power_iteration(
  m : Array[Array[Double]],
  prev : Array[Array[Double]],
  init_vec : Array[Double],
) -> (Array[Double], Double) {
  let mut v = init_vec
  ignore(lda_normalize_in_place(v))
  let mut lambda = lda_rayleigh(m, v)
  for it = 0; it < lda_max_iter; it = it + 1 {
    let w = lda_mat_vec(m, v)
    lda_orthogonalize_in_place(w, prev)
    let nrm = lda_normalize_in_place(w)
    if nrm < lda_tol {
      lambda = 0.0
      break
    }
    v = w
    let new_lambda = lda_rayleigh(m, v)
    if (new_lambda - lambda).abs() <= lda_tol * (1.0 + lambda.abs()) {
      lambda = new_lambda
      break
    }
    lambda = new_lambda
  }
  (v, lambda)
}

// ---------------------------------------------------------------------------
// Public types & entry points
// ---------------------------------------------------------------------------

///|
/// The fitted LDA model.
pub struct LDAResult {
  /// Discriminant axes as rows; `scalings[i]` is the `i`-th eigenvector
  /// of `SW⁻¹ · SB`, ordered by descending eigenvalue.
  scalings : Array[Array[Double]]
  /// Per-feature overall mean (used for centring before projection).
  mean : Array[Double]
  /// Explained variance ratio for each retained component.
  explained_variance : Array[Double]
}

///|
/// Fit LDA on labelled data and keep the top `n_components` discriminant axes.
///
/// **Parameters.**
/// - `data` — sample matrix (rows = samples, cols = features).
/// - `labels` — integer class label for each sample (same length as `data`).
/// - `n_components` — number of discriminant axes to keep; clamped to
///   `min(n_classes − 1, d)`. Values `< 1` are treated as `1`.
/// - `reg` — ridge regularisation added to the within-class scatter before
///   inversion (default `1e-4`). Increase for small or ill-conditioned data.
///
/// **Returns.** An `LDAResult` whose `scalings` has at most
/// `min(n_classes − 1, d)` orthonormal rows.
pub fn lda(
  data : Array[Array[Double]],
  labels : Array[Int],
  n_components : Int,
  reg : Double,
) -> LDAResult {
  let n = data.length()
  if n == 0 || labels.length() != n {
    return { scalings: [], mean: [], explained_variance: [] }
  }
  let d = data[0].length()
  if d == 0 {
    return { scalings: [], mean: [], explained_variance: [] }
  }
  // Collect unique classes and their indices
  let class_map : Map[Int, Array[Int]] = Map([])
  for i = 0; i < n; i = i + 1 {
    let lbl = labels[i]
    match class_map.get(lbl) {
      Some(arr) => arr.push(i)
      None => {
        let arr : Array[Int] = [i]
        class_map[lbl] = arr
      }
    }
  }
  let n_classes = class_map.length()
  if n_classes < 2 {
    return { scalings: [], mean: [], explained_variance: [] }
  }
  // Clamp n_components
  let max_comp = if n_classes - 1 < d { n_classes - 1 } else { d }
  let n_comp = if n_components < 1 {
    1
  } else if n_components > max_comp {
    max_comp
  } else {
    n_components
  }
  // Compute overall mean
  let mean = Array::make(d, 0.0)
  for i = 0; i < n; i = i + 1 {
    let row = data[i]
    for j = 0; j < d; j = j + 1 {
      if j < row.length() {
        mean[j] = mean[j] + row[j]
      }
    }
  }
  for j = 0; j < d; j = j + 1 {
    mean[j] = mean[j] / n.to_double()
  }
  // Compute class means
  let class_means : Map[Int, Array[Double]] = Map([])
  for kv in class_map {
    let lbl = kv.0
    let indices = kv.1
    let cnt = indices.length()
    let cm = Array::make(d, 0.0)
    for idx in indices {
      let row = data[idx]
      for j = 0; j < d; j = j + 1 {
        if j < row.length() {
          cm[j] = cm[j] + row[j]
        }
      }
    }
    for j = 0; j < d; j = j + 1 {
      cm[j] = cm[j] / cnt.to_double()
    }
    class_means[lbl] = cm
  }
  // Within-class scatter SW
  let sw : Array[Array[Double]] = []
  for i = 0; i < d; i = i + 1 {
    sw.push(Array::make(d, 0.0))
  }
  for i = 0; i < n; i = i + 1 {
    let row = data[i]
    let cm = class_means[labels[i]]
    for a = 0; a < d; a = a + 1 {
      let va = (if a < row.length() { row[a] } else { 0.0 }) - cm[a]
      for b = 0; b <= a; b = b + 1 {
        let vb = (if b < row.length() { row[b] } else { 0.0 }) - cm[b]
        sw[a][b] = sw[a][b] + va * vb
      }
    }
  }
  // Mirror lower triangle
  for a = 0; a < d; a = a + 1 {
    for b = 0; b < a; b = b + 1 {
      sw[b][a] = sw[a][b]
    }
  }
  // Between-class scatter SB
  let sb : Array[Array[Double]] = []
  for i = 0; i < d; i = i + 1 {
    sb.push(Array::make(d, 0.0))
  }
  for kv in class_map {
    let lbl = kv.0
    let indices = kv.1
    let cnt = indices.length().to_double()
    let cm = class_means[lbl]
    for a = 0; a < d; a = a + 1 {
      let va = cm[a] - mean[a]
      for b = 0; b <= a; b = b + 1 {
        let vb = cm[b] - mean[b]
        sb[a][b] = sb[a][b] + cnt * va * vb
      }
    }
  }
  // Mirror lower triangle
  for a = 0; a < d; a = a + 1 {
    for b = 0; b < a; b = b + 1 {
      sb[b][a] = sb[a][b]
    }
  }
  // Regularise SW: SW += reg * I
  let reg_val = if reg < 0.0 { lda_default_reg } else { reg }
  for i = 0; i < d; i = i + 1 {
    sw[i][i] = sw[i][i] + reg_val
  }
  // Compute SW^(-1)
  let sw_inv = match lda_matrix_inverse(sw, d) {
    Some(inv) => inv
    None => return { scalings: [], mean: [], explained_variance: [] }
  }
  // M = SW^(-1) * SB
  let m = lda_mat_mul(sw_inv, sb, d)
  // Power iteration with deflation to find top n_comp eigenvectors
  let components : Array[Array[Double]] = []
  let explained : Array[Double] = []
  let prev : Array[Array[Double]] = []
  let mut total_var = 0.0
  for c = 0; c < n_comp; c = c + 1 {
    // Init vector: all-ones (avoids landing in null space of M)
    let init = Array::make(d, 1.0 / lda_sqrt(d.to_double()))
    lda_orthogonalize_in_place(init, prev)
    let init_norm = lda_l2_norm(init)
    if init_norm < lda_tol {
      // Try canonical basis vectors
      let mut found = false
      for j = 0; j < d; j = j + 1 {
        if !found {
          let e = Array::make(d, 0.0)
          e[j] = 1.0
          lda_orthogonalize_in_place(e, prev)
          if lda_l2_norm(e) >= lda_tol {
            for k = 0; k < d; k = k + 1 {
              init[k] = e[k]
            }
            found = true
          }
        }
      }
    } else {
      // Renormalize after orthogonalization
      for k = 0; k < d; k = k + 1 {
        init[k] = init[k] / init_norm
      }
    }
    // If M*init is zero, try another direction
    let m_init = lda_mat_vec(m, init)
    if lda_l2_norm(m_init) < lda_tol {
      // Try each canonical basis vector
      let mut found = false
      for j = 0; j < d; j = j + 1 {
        if !found {
          let e = Array::make(d, 0.0)
          e[j] = 1.0
          lda_orthogonalize_in_place(e, prev)
          let m_e = lda_mat_vec(m, e)
          if lda_l2_norm(m_e) >= lda_tol {
            for k = 0; k < d; k = k + 1 {
              init[k] = e[k]
            }
            found = true
          }
        }
      }
    }
    let (v, lambda) = lda_power_iteration(m, prev, init)
    lda_fix_sign(v)
    components.push(v)
    explained.push(lambda)
    total_var = total_var + lambda
    prev.push(v)
  }
  // Convert explained_variance to ratios
  let ratios : Array[Double] = []
  for i = 0; i < explained.length(); i = i + 1 {
    if total_var > 0.0 {
      ratios.push(explained[i] / total_var)
    } else {
      ratios.push(0.0)
    }
  }
  { scalings: components, mean, explained_variance: ratios }
}

///|
/// Project a single sample onto the fitted discriminant axes.
///
/// Returns an empty array if the result has no components or the sample
/// dimension does not match the fitted feature count.
pub fn lda_transform(
  result : LDAResult,
  sample : Array[Double],
) -> Array[Double] {
  let comps = result.scalings
  let nc = comps.length()
  if nc == 0 {
    return []
  }
  let d = result.mean.length()
  if sample.length() != d {
    return []
  }
  let out : Array[Double] = []
  for c = 0; c < nc; c = c + 1 {
    let comp = comps[c]
    let mut s = 0.0
    for j = 0; j < d; j = j + 1 {
      s = s + (sample[j] - result.mean[j]) * comp[j]
    }
    out.push(s)
  }
  out
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "lda: empty data" {
  let r = lda([], [], 1, 1.0e-4)
  assert_eq(r.scalings.length(), 0)
  assert_eq(r.mean.length(), 0)
}

///|
test "lda: single class returns empty" {
  let data = [[1.0, 2.0], [3.0, 4.0], [5.0, 6.0]]
  let labels = [0, 0, 0]
  let r = lda(data, labels, 1, 1.0e-4)
  assert_eq(r.scalings.length(), 0)
}

///|
test "lda: two classes 1D, perfect separation" {
  // Class 0: points around x=0, Class 1: points around x=10
  let data = [[-1.0], [0.0], [1.0], [9.0], [10.0], [11.0]]
  let labels = [0, 0, 0, 1, 1, 1]
  let r = lda(data, labels, 1, 1.0e-4)
  assert_eq(r.scalings.length(), 1)
  // The discriminant axis should be [1.0] (only one feature)
  assert_true(
    (r.scalings[0][0] - 1.0).abs() < 0.01 ||
    (r.scalings[0][0] + 1.0).abs() < 0.01,
  )
  // Projection of class-0 mean should differ from class-1 mean
  let p0 = lda_transform(r, [0.0])
  let p1 = lda_transform(r, [10.0])
  assert_true((p0[0] - p1[0]).abs() > 5.0)
}

///|
test "lda: two classes 2D, axis-aligned separation" {
  // Class 0: x varies, y=0; Class 1: x varies, y=5
  let data = [
    [0.0, 0.0],
    [1.0, 0.0],
    [2.0, 0.0],
    [0.0, 5.0],
    [1.0, 5.0],
    [2.0, 5.0],
  ]
  let labels = [0, 0, 0, 1, 1, 1]
  let r = lda(data, labels, 1, 1.0e-4)
  assert_eq(r.scalings.length(), 1)
  // The discriminant should be along y-axis [0, 1]
  let comp = r.scalings[0]
  assert_true(comp[0].abs() < 0.1)
  assert_true((comp[1].abs() - 1.0).abs() < 0.1)
}

///|
test "lda: n_components clamped to n_classes-1" {
  // 3 classes, 2 features -> max 2 components (min(3-1, 2) = 2)
  let data = [
    [0.0, 0.0],
    [1.0, 0.0],
    [5.0, 5.0],
    [6.0, 5.0],
    [0.0, 10.0],
    [1.0, 10.0],
  ]
  let labels = [0, 0, 1, 1, 2, 2]
  // Ask for 5 components -> should get 2
  let r = lda(data, labels, 5, 1.0e-4)
  assert_eq(r.scalings.length(), 2)
}

///|
test "lda: three classes 2D" {
  let data = [
    [0.0, 0.0],
    [0.5, 0.0],
    [0.0, 0.5],
    [5.0, 5.0],
    [5.5, 5.0],
    [5.0, 5.5],
    [10.0, 0.0],
    [10.5, 0.0],
    [10.0, 0.5],
  ]
  let labels = [0, 0, 0, 1, 1, 1, 2, 2, 2]
  let r = lda(data, labels, 2, 1.0e-4)
  assert_eq(r.scalings.length(), 2)
  // Components should be unit length
  for c = 0; c < 2; c = c + 1 {
    let norm = lda_l2_norm(r.scalings[c])
    assert_true((norm - 1.0).abs() < 0.01)
  }
  // Components should be orthogonal
  let dot = lda_dot(r.scalings[0], r.scalings[1])
  assert_true(dot.abs() < 0.01)
  // Explained variance ratios should sum to 1
  let mut total = 0.0
  for i = 0; i < r.explained_variance.length(); i = i + 1 {
    total = total + r.explained_variance[i]
  }
  assert_true((total - 1.0).abs() < 0.01)
}

///|
test "lda: transform projects onto discriminant axes" {
  // Two well-separated classes along x-axis
  let data = [[0.0, 5.0], [1.0, 5.0], [10.0, 5.0], [11.0, 5.0]]
  let labels = [0, 0, 1, 1]
  let r = lda(data, labels, 1, 1.0e-4)
  // Mean is (5.5, 5.0), class-0 mean is (0.5, 5.0), class-1 mean is (10.5, 5.0)
  // The discriminant should be along x-axis
  let p0 = lda_transform(r, [0.5, 5.0])
  let p1 = lda_transform(r, [10.5, 5.0])
  // Projections should be different (class means separated)
  assert_true((p0[0] - p1[0]).abs() > 5.0)
}

///|
test "lda: dimension mismatch returns empty" {
  let data = [[1.0, 2.0], [3.0, 4.0], [5.0, 6.0], [7.0, 8.0]]
  let labels = [0, 0, 1, 1]
  let r = lda(data, labels, 1, 1.0e-4)
  // 3D sample with 2D model
  assert_eq(lda_transform(r, [1.0, 2.0, 3.0]).length(), 0)
}

///|
test "lda: label count mismatch returns empty" {
  let data = [[1.0, 2.0], [3.0, 4.0]]
  let labels = [0, 0, 1] // 3 labels for 2 samples
  let r = lda(data, labels, 1, 1.0e-4)
  assert_eq(r.scalings.length(), 0)
}

///|
test "lda: explained variance is non-increasing" {
  let data = [
    [0.0, 0.0],
    [0.5, 0.1],
    [1.0, 0.0],
    [5.0, 5.0],
    [5.5, 4.9],
    [6.0, 5.0],
    [0.0, 10.0],
    [0.5, 10.1],
    [1.0, 10.0],
  ]
  let labels = [0, 0, 0, 1, 1, 1, 2, 2, 2]
  let r = lda(data, labels, 2, 1.0e-4)
  if r.explained_variance.length() == 2 {
    assert_true(r.explained_variance[0] >= r.explained_variance[1])
  }
}

///|
test "lda: regularization prevents singularity" {
  // n < d case: 2 samples, 3 features, 2 classes
  let data = [[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]]
  let labels = [0, 1]
  // With regularization, should not fail
  let r = lda(data, labels, 1, 1.0e-2)
  assert_eq(r.scalings.length(), 1)
}
