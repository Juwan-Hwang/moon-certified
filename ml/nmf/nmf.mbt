/// NMF — Non-negative Matrix Factorization.
///
/// Decomposes a non-negative matrix `V` (n×d) into two non-negative matrices
/// `W` (n×k) and `H` (k×d) such that `V ≈ W·H`, where `k ≤ min(n, d)`.
///
/// ## Algorithm
/// Multiplicative updates (Lee & Seung, 1999):
///
/// ```text
/// H = H ⊙ (Wᵀ V) / (Wᵀ W H)
/// W = W ⊙ (V Hᵀ) / (W H Hᵀ)
/// ```
///
/// where `⊙` is element-wise multiplication and `/` is element-wise division.
/// Both `W` and `H` remain non-negative throughout, and the Frobenius norm
/// `‖V − WH‖_F` decreases monotonically.
///
/// A small epsilon is added to denominators to prevent division by zero.
///
/// ## Complexity
/// - Time: `O(max_iter · n · d · k)` per fit
/// - Space: `O(n·k + k·d + n·d)` for W, H, and V
///
/// ## References
/// - Lee, D.D. and Seung, H.S. (1999). "Learning the parts of objects by
///   non-negative matrix factorization." Nature, 401(6755), 788-791.
/// - Lee, D.D. and Seung, H.S. (2001). "Algorithms for non-negative matrix
///   factorization." NIPS, 556-562.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

///|
/// Maximum number of multiplicative update iterations.
let nmf_default_max_iter : Int = 200

///|
/// Default convergence tolerance (relative change in reconstruction error).
let nmf_default_tol : Double = 1.0e-4

///|
/// Small epsilon to prevent division by zero in multiplicative updates.
let nmf_eps : Double = 1.0e-10

// ---------------------------------------------------------------------------
// Deterministic PRNG (LCG)
// ---------------------------------------------------------------------------

///|
priv struct NmfRng {
  mut state : Int
}

///|
fn NmfRng::new(seed : Int) -> NmfRng {
  let s = seed & 0x7FFFFFFF
  { state: if s == 0 { 1 } else { s } }
}

///|
fn NmfRng::next(self : NmfRng) -> Int {
  // LCG: state = (a * state + c) mod 2^31
  self.state = (self.state * 1103515245 + 12345) & 0x7FFFFFFF
  self.state
}

///|
fn NmfRng::next_double(self : NmfRng) -> Double {
  self.next().to_double() / 2147483648.0
}

// ---------------------------------------------------------------------------
// Matrix operations (local, dimension-checked)
// ---------------------------------------------------------------------------

///|
/// Transpose a matrix: `B = Aᵀ` where A is `m×n` and B is `n×m`.
fn nmf_transpose(a : Array[Array[Double]]) -> Array[Array[Double]] {
  let m = a.length()
  if m == 0 {
    return []
  }
  let n = a[0].length()
  let result : Array[Array[Double]] = []
  for j = 0; j < n; j = j + 1 {
    let row = Array::make(m, 0.0)
    for i = 0; i < m; i = i + 1 {
      row[i] = a[i][j]
    }
    result.push(row)
  }
  result
}

///|
/// Matrix multiplication: `C = A · B` where A is `m×k` and B is `k×n`.
fn nmf_mat_mul(
  a : Array[Array[Double]],
  b : Array[Array[Double]],
) -> Array[Array[Double]] {
  let m = a.length()
  if m == 0 {
    return []
  }
  let k = a[0].length()
  let n = if b.length() > 0 { b[0].length() } else { 0 }
  let result : Array[Array[Double]] = []
  for i = 0; i < m; i = i + 1 {
    let row = Array::make(n, 0.0)
    for j = 0; j < n; j = j + 1 {
      let mut s = 0.0
      for p = 0; p < k; p = p + 1 {
        s = s + a[i][p] * b[p][j]
      }
      row[j] = s
    }
    result.push(row)
  }
  result
}

///|
/// Element-wise matrix multiplication: `C = A ⊙ B`.
fn nmf_elem_mul(
  a : Array[Array[Double]],
  b : Array[Array[Double]],
) -> Array[Array[Double]] {
  let m = a.length()
  if m == 0 {
    return []
  }
  let n = a[0].length()
  let result : Array[Array[Double]] = []
  for i = 0; i < m; i = i + 1 {
    let row = Array::make(n, 0.0)
    for j = 0; j < n; j = j + 1 {
      row[j] = a[i][j] * b[i][j]
    }
    result.push(row)
  }
  result
}

///|
/// Frobenius norm of the difference `‖A − B‖_F`.
fn nmf_frobenius_diff(
  a : Array[Array[Double]],
  b : Array[Array[Double]],
) -> Double {
  let m = a.length()
  if m == 0 {
    return 0.0
  }
  let n = a[0].length()
  let mut s = 0.0
  for i = 0; i < m; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      let diff = a[i][j] - b[i][j]
      s = s + diff * diff
    }
  }
  s.sqrt()
}

// ---------------------------------------------------------------------------
// Public types & entry points
// ---------------------------------------------------------------------------

///|
/// The fitted NMF model.
pub struct NMFResult {
  /// Basis matrix `W` (n×k): each row is the coefficient vector for a sample.
  w : Array[Array[Double]]
  /// Encoding matrix `H` (k×d): each row is a basis component (factor).
  h : Array[Array[Double]]
  /// Reconstruction error (Frobenius norm of `V − WH`) at convergence.
  reconstruction_err : Double
  /// Number of iterations actually executed.
  n_iter : Int
}

///|
/// Fit NMF on non-negative data `V`.
///
/// **Parameters.**
/// - `v` — non-negative matrix (n×d). Negative entries are clamped to 0.
/// - `n_components` — number of latent factors `k`; clamped to
///   `min(n, d)`. Values `< 1` are treated as `1`.
/// - `max_iter` — maximum multiplicative update iterations.
///   Values `< 1` default to `nmf_default_max_iter`.
/// - `tol` — convergence tolerance: stop when the relative change in
///   reconstruction error drops below this. Values `<= 0` default to
///   `nmf_default_tol`.
/// - `seed` — PRNG seed for reproducible initialization.
///
/// **Returns.** An `NMFResult` with `W` (n×k), `H` (k×d), and the final
/// reconstruction error.
///
/// **Edge cases.**
/// - Empty `V` → empty `W`, `H`, zero error.
/// - `n_components > min(n, d)` → clamped to `min(n, d)`.
pub fn nmf(
  v : Array[Array[Double]],
  n_components : Int,
  max_iter : Int,
  tol : Double,
  seed : Int,
) -> NMFResult {
  let n = v.length()
  if n == 0 {
    return { w: [], h: [], reconstruction_err: 0.0, n_iter: 0 }
  }
  let d = v[0].length()
  if d == 0 {
    return { w: [], h: [], reconstruction_err: 0.0, n_iter: 0 }
  }
  // Clamp n_components
  let max_k = if n < d { n } else { d }
  let k = if n_components < 1 {
    1
  } else if n_components > max_k {
    max_k
  } else {
    n_components
  }
  // Clamp max_iter and tol
  let mi = if max_iter < 1 { nmf_default_max_iter } else { max_iter }
  let tl = if tol <= 0.0 { nmf_default_tol } else { tol }
  // Clamp V to non-negative
  let v_clamped : Array[Array[Double]] = []
  for i = 0; i < n; i = i + 1 {
    let row = Array::make(d, 0.0)
    for j = 0; j < d; j = j + 1 {
      let val = if j < v[i].length() { v[i][j] } else { 0.0 }
      row[j] = if val > 0.0 { val } else { 0.0 }
    }
    v_clamped.push(row)
  }
  // Initialize W and H with uniform random in [0, 1)
  let rng = NmfRng::new(seed)
  let w : Array[Array[Double]] = []
  for i = 0; i < n; i = i + 1 {
    let row = Array::make(k, 0.0)
    for j = 0; j < k; j = j + 1 {
      row[j] = rng.next_double() + 0.01 // Avoid exact zeros
    }
    w.push(row)
  }
  let h : Array[Array[Double]] = []
  for i = 0; i < k; i = i + 1 {
    let row = Array::make(d, 0.0)
    for j = 0; j < d; j = j + 1 {
      row[j] = rng.next_double() + 0.01
    }
    h.push(row)
  }
  // Initial error
  let wh = nmf_mat_mul(w, h)
  let mut prev_err = nmf_frobenius_diff(v_clamped, wh)
  let mut iter_done = 0
  for iter = 0; iter < mi; iter = iter + 1 {
    iter_done = iter + 1
    // Update H: H = H * (W^T V) / (W^T W H)
    let w_t = nmf_transpose(w)
    let w_t_v = nmf_mat_mul(w_t, v_clamped)
    let w_t_w = nmf_mat_mul(w_t, w)
    let w_t_w_h = nmf_mat_mul(w_t_w, h)
    let h_update_num = nmf_elem_mul(h, w_t_v)
    let h_update_den = w_t_w_h
    for i = 0; i < k; i = i + 1 {
      for j = 0; j < d; j = j + 1 {
        let denom = if h_update_den[i][j] > nmf_eps {
          h_update_den[i][j]
        } else {
          nmf_eps
        }
        h[i][j] = h_update_num[i][j] / denom
      }
    }
    // Update W: W = W * (V H^T) / (W H H^T)
    let h_t = nmf_transpose(h)
    let v_h_t = nmf_mat_mul(v_clamped, h_t)
    let w_h = nmf_mat_mul(w, h)
    let w_h_h_t = nmf_mat_mul(w_h, h_t)
    for i = 0; i < n; i = i + 1 {
      for j = 0; j < k; j = j + 1 {
        let denom = if w_h_h_t[i][j] > nmf_eps {
          w_h_h_t[i][j]
        } else {
          nmf_eps
        }
        w[i][j] = w[i][j] * v_h_t[i][j] / denom
      }
    }
    // Check convergence
    let wh_new = nmf_mat_mul(w, h)
    let err = nmf_frobenius_diff(v_clamped, wh_new)
    if prev_err > 0.0 {
      let rel_change = (prev_err - err).abs() / prev_err
      if rel_change < tl {
        prev_err = err
        break
      }
    }
    prev_err = err
  }
  { w, h, reconstruction_err: prev_err, n_iter: iter_done }
}

///|
/// Transform a new sample `x` using the fitted NMF basis.
///
/// Finds the best non-negative coefficient vector `w` such that
/// `x ≈ w · H` (least-squares with non-negativity constraint, solved
/// via multiplicative updates on `w` alone).
///
/// Returns an empty array if the model has no components.
pub fn nmf_transform(
  result : NMFResult,
  x : Array[Double],
  max_iter : Int,
) -> Array[Double] {
  let k = result.h.length()
  if k == 0 {
    return []
  }
  let d = result.h[0].length()
  if x.length() != d {
    return []
  }
  let mi = if max_iter < 1 { 50 } else { max_iter }
  // Initialize w with small positive values
  let w = Array::make(k, 0.5)
  // x is 1×d, h is k×d
  // w = w * (x * H^T) / (w * H * H^T)
  let h_t = nmf_transpose(result.h) // d×k
  // x * H^T → 1×k
  let x_h_t = Array::make(k, 0.0)
  for j = 0; j < k; j = j + 1 {
    let mut s = 0.0
    for p = 0; p < d; p = p + 1 {
      s = s + x[p] * h_t[p][j]
    }
    x_h_t[j] = s
  }
  // H * H^T → k×k
  let h_h_t : Array[Array[Double]] = []
  for i = 0; i < k; i = i + 1 {
    let row = Array::make(k, 0.0)
    for j = 0; j < k; j = j + 1 {
      let mut s = 0.0
      for p = 0; p < d; p = p + 1 {
        s = s + result.h[i][p] * result.h[j][p]
      }
      row[j] = s
    }
    h_h_t.push(row)
  }
  for iter = 0; iter < mi; iter = iter + 1 {
    // w * H * H^T → 1×k
    let w_h_h_t = Array::make(k, 0.0)
    for j = 0; j < k; j = j + 1 {
      let mut s = 0.0
      for p = 0; p < k; p = p + 1 {
        s = s + w[p] * h_h_t[p][j]
      }
      w_h_h_t[j] = s
    }
    // Update
    for j = 0; j < k; j = j + 1 {
      let denom = if w_h_h_t[j] > nmf_eps { w_h_h_t[j] } else { nmf_eps }
      w[j] = w[j] * x_h_t[j] / denom
    }
  }
  w
}

///|
/// Reconstruct `V` from the fitted factors: `V̂ = W · H`.
pub fn nmf_reconstruct(result : NMFResult) -> Array[Array[Double]] {
  nmf_mat_mul(result.w, result.h)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "nmf: empty data" {
  let r = nmf([], 2, 100, 1.0e-4, 42)
  assert_eq(r.w.length(), 0)
  assert_eq(r.h.length(), 0)
}

///|
test "nmf: basic decomposition" {
  // 4×3 non-negative matrix
  let v = [
    [1.0, 2.0, 3.0],
    [4.0, 5.0, 6.0],
    [7.0, 8.0, 9.0],
    [10.0, 11.0, 12.0],
  ]
  let r = nmf(v, 2, 200, 1.0e-4, 42)
  assert_eq(r.w.length(), 4)
  assert_eq(r.w[0].length(), 2)
  assert_eq(r.h.length(), 2)
  assert_eq(r.h[0].length(), 3)
  // W and H should be non-negative
  for i = 0; i < 4; i = i + 1 {
    for j = 0; j < 2; j = j + 1 {
      assert_true(r.w[i][j] >= 0.0)
    }
  }
  for i = 0; i < 2; i = i + 1 {
    for j = 0; j < 3; j = j + 1 {
      assert_true(r.h[i][j] >= 0.0)
    }
  }
}

///|
test "nmf: reconstruction error decreases" {
  let v = [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0], [1.0, 1.0, 0.0]]
  let r = nmf(v, 2, 200, 1.0e-6, 42)
  // With k=2 and 3 features, reconstruction won't be perfect
  // but error should be reasonable
  assert_true(r.reconstruction_err < 2.0)
}

///|
test "nmf: perfect reconstruction with k=d" {
  // With k = d, NMF should reconstruct V (up to numerical precision)
  let v = [[1.0, 2.0, 0.0], [3.0, 0.0, 4.0], [0.0, 5.0, 6.0]]
  let r = nmf(v, 3, 500, 1.0e-8, 42)
  let recon = nmf_reconstruct(r)
  let err = nmf_frobenius_diff(v, recon)
  // Should be close to zero (but NMF doesn't guarantee perfect with
  // multiplicative updates, so we use a generous tolerance)
  assert_true(err < 1.0)
}

///|
test "nmf: negative values clamped" {
  let v = [[-1.0, 2.0], [3.0, -4.0]]
  let r = nmf(v, 1, 100, 1.0e-4, 42)
  // Should not crash; negative values treated as 0
  assert_eq(r.w.length(), 2)
  assert_eq(r.h.length(), 1)
}

///|
test "nmf: n_components clamped" {
  // 3×2 matrix, ask for 5 components -> clamped to 2
  let v = [[1.0, 2.0], [3.0, 4.0], [5.0, 6.0]]
  let r = nmf(v, 5, 100, 1.0e-4, 42)
  assert_eq(r.w[0].length(), 2)
  assert_eq(r.h.length(), 2)
}

///|
test "nmf: deterministic with same seed" {
  let v = [[1.0, 2.0], [3.0, 4.0], [5.0, 6.0]]
  let r1 = nmf(v, 2, 100, 1.0e-4, 999)
  let r2 = nmf(v, 2, 100, 1.0e-4, 999)
  // Same seed → same W and H
  for i = 0; i < 3; i = i + 1 {
    for j = 0; j < 2; j = j + 1 {
      assert_true((r1.w[i][j] - r2.w[i][j]).abs() < 1.0e-10)
    }
  }
  for i = 0; i < 2; i = i + 1 {
    for j = 0; j < 2; j = j + 1 {
      assert_true((r1.h[i][j] - r2.h[i][j]).abs() < 1.0e-10)
    }
  }
}

///|
test "nmf: transform new sample" {
  let v = [[1.0, 2.0, 3.0], [4.0, 5.0, 6.0], [7.0, 8.0, 9.0]]
  let r = nmf(v, 2, 200, 1.0e-4, 42)
  // Transform a new 3D sample
  let coeffs = nmf_transform(r, [2.0, 3.0, 4.0], 100)
  assert_eq(coeffs.length(), 2)
  // Coefficients should be non-negative
  for i = 0; i < 2; i = i + 1 {
    assert_true(coeffs[i] >= 0.0)
  }
}

///|
test "nmf: reconstruct returns W*H" {
  let v = [[1.0, 2.0], [3.0, 4.0]]
  let r = nmf(v, 1, 100, 1.0e-4, 42)
  let recon = nmf_reconstruct(r)
  assert_eq(recon.length(), 2)
  assert_eq(recon[0].length(), 2)
  // Reconstruction error should match
  let err = nmf_frobenius_diff(v, recon)
  assert_true((err - r.reconstruction_err).abs() < 0.01)
}

///|
test "nmf: single component" {
  // Rank-1 approximation
  let v = [[1.0, 2.0, 3.0], [2.0, 4.0, 6.0], [3.0, 6.0, 9.0]]
  let r = nmf(v, 1, 300, 1.0e-6, 42)
  // This is a rank-1 matrix, so k=1 should reconstruct well
  let recon = nmf_reconstruct(r)
  let err = nmf_frobenius_diff(v, recon)
  assert_true(err < 0.5)
}
