/// Sparse SVD via Lanczos Bidiagonalization
///
/// Implements the truncated Singular Value Decomposition (SVD) for
/// sparse matrices using the Lanczos bidiagonalization algorithm
/// (Golub & Kahan 1965) with partial reorthogonalization.
///
/// ## Overview
///
/// For a sparse m x n matrix A, the SVD is A = U * Sigma * V^T where
/// U (m x k) and V (n x k) have orthonormal columns and Sigma is a
/// diagonal matrix of the top-k singular values.
///
/// The Lanczos bidiagonalization builds the Krylov subspace by alternating
/// matrix-vector and transpose-matrix-vector products, producing a
/// bidiagonal matrix B whose singular values approximate those of A.
///
/// ## Complexity
///
/// - Per iteration: O(nnz) for the sparse products + O(k * (m+n)) for
///   reorthogonalization
/// - Total for k singular values: O(k * nnz + k^2 * (m+n))
///
/// ## References
///
/// - Golub, G. H., Kahan, W. (1965). "Calculating the Singular Values
///   and Pseudo-Inverse of a Matrix." SIAM J. Numer. Anal. 2, 205-224.
/// - Larsen, R. M. (1998). "Lanczos Bidiagonalization with Partial
///   Reorthogonalization." DAIMI Report 537.

// ===========================================================================
// Sparse transpose multiplication
// ===========================================================================

///|
/// Sparse matrix-transpose-vector multiplication: y = A^T * x.
///
/// `x` must have length `rows`. Returns `y` of length `cols`.
fn spmv_transpose(
  m : @sparse_matrix.SparseMatrix,
  x : Array[Double],
) -> Array[Double] {
  let y = Array::make(@sparse_matrix.num_cols(m), 0.0)
  let rows = @sparse_matrix.num_rows(m)
  // Fallback: use get() (less efficient but works with the public API)
  let cols = @sparse_matrix.num_cols(m)
  for c = 0; c < cols; c = c + 1 {
    let mut sum = 0.0
    for r = 0; r < rows; r = r + 1 {
      sum = sum + @sparse_matrix.get(m, r, c) * x[r]
    }
    y[c] = sum
  }
  y
}

// ===========================================================================
// Vector operations
// ===========================================================================

///|
fn vdot(a : Array[Double], b : Array[Double]) -> Double {
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  let mut s = 0.0
  for i = 0; i < n; i = i + 1 {
    s = s + a[i] * b[i]
  }
  s
}

///|
fn vnorm(a : Array[Double]) -> Double {
  vdot(a, a).sqrt()
}

///|
fn vscale(a : Array[Double], s : Double) -> Array[Double] {
  let result = Array::make(a.length(), 0.0)
  for i = 0; i < a.length(); i = i + 1 {
    result[i] = a[i] * s
  }
  result
}

///|
fn vnormalize(a : Array[Double]) -> Array[Double] {
  let n = vnorm(a)
  if n < 1.0e-30 {
    return Array::make(a.length(), 0.0)
  }
  vscale(a, 1.0 / n)
}

// ===========================================================================
// Lanczos bidiagonalization
// ===========================================================================

///|
/// Result of truncated SVD computation.
pub struct SVDResult {
  singular_values : Array[Double]
  u_vectors : Array[Array[Double]]
  v_vectors : Array[Array[Double]]
}

///|
/// Compute the truncated SVD of a sparse matrix using Lanczos
/// bidiagonalization with full reorthogonalization.
///
/// - `a`: sparse matrix (m x n)
/// - `k`: number of singular values/vectors to compute (k <= min(m, n))
/// - `max_iter`: maximum Lanczos iterations (should be >= k)
/// - `tol`: convergence tolerance
///
/// Returns singular values in descending order, with corresponding
/// left (U) and right (V) singular vectors.
pub fn sparse_svd(
  a : @sparse_matrix.SparseMatrix,
  k : Int,
  max_iter : Int,
  tol : Double,
) -> SVDResult {
  let m = @sparse_matrix.num_rows(a)
  let n = @sparse_matrix.num_cols(a)
  let kk = if k < m { k } else { m }
  let kk = if kk < n { kk } else { n }
  if kk <= 0 {
    return { singular_values: [], u_vectors: [], v_vectors: [] }
  }

  let iters = if max_iter > kk * 2 { max_iter } else { kk * 2 }

  // Lanczos bidiagonalization vectors
  let mut v = Array::make(n, 0.0)
  // Initialize with a random-like vector
  for i = 0; i < n; i = i + 1 {
    v[i] = (1.0 + i.to_double()) / n.to_double()
  }
  v = vnormalize(v)

  let alpha : Array[Double] = []
  let beta : Array[Double] = []

  // Store Lanczos vectors for reorthogonalization
  let v_vectors : Array[Array[Double]] = []
  let u_vectors : Array[Array[Double]] = []

  let mut v_prev : Array[Double] = Array::make(n, 0.0)
  let mut beta_prev = 0.0

  for j = 0; j < iters; j = j + 1 {
    // u = A * v
    let u_new = @sparse_matrix.spmv(a, v)
    // Reorthogonalize u against previous u_vectors
    for ui = 0; ui < u_vectors.length(); ui = ui + 1 {
      let proj = vdot(u_new, u_vectors[ui])
      for i = 0; i < u_new.length(); i = i + 1 {
        u_new[i] = u_new[i] - proj * u_vectors[ui][i]
      }
    }

    // alpha_j = ||u||
    let alpha_j = vnorm(u_new)
    alpha.push(alpha_j)

    if alpha_j < tol {
      break
    }

    // u_j = u / alpha_j
    let u_j = vscale(u_new, 1.0 / alpha_j)
    u_vectors.push(u_j)

    // v_new = A^T * u_j - alpha_j * v - beta_prev * v_prev
    let v_new = spmv_transpose(a, u_j)
    // Subtract alpha_j * v
    for i = 0; i < v_new.length(); i = i + 1 {
      v_new[i] = v_new[i] - alpha_j * v[i]
    }
    // Subtract beta_prev * v_prev
    if j > 0 {
      for i = 0; i < v_new.length(); i = i + 1 {
        v_new[i] = v_new[i] - beta_prev * v_prev[i]
      }
    }

    // Reorthogonalize v_new against previous v_vectors
    for vi = 0; vi < v_vectors.length(); vi = vi + 1 {
      let proj = vdot(v_new, v_vectors[vi])
      for i = 0; i < v_new.length(); i = i + 1 {
        v_new[i] = v_new[i] - proj * v_vectors[vi][i]
      }
    }

    // beta_j = ||v_new||
    let beta_j = vnorm(v_new)
    beta.push(beta_j)

    v_vectors.push(v)

    if beta_j < tol {
      break
    }

    // Update for next iteration
    v_prev = v
    beta_prev = beta_j
    v = vscale(v_new, 1.0 / beta_j)
  }

  // Solve the bidiagonal SVD problem
  // The bidiagonal matrix B has diagonal alpha and superdiagonal beta
  // We use a simple eigenvalue solver for the tridiagonal matrix B^T * B
  let actual_k = if alpha.length() < kk { alpha.length() } else { kk }
  let sv = solve_bidiagonal_svd(alpha, beta, actual_k)

  // Extract singular vectors from the Lanczos vectors
  let result_sv : Array[Double] = []
  let result_u : Array[Array[Double]] = []
  let result_v : Array[Array[Double]] = []

  for i = 0; i < actual_k; i = i + 1 {
    let sigma = sv[i].sqrt()
    result_sv.push(sigma)
    // Approximate singular vectors from Lanczos vectors
    if i < u_vectors.length() && i < v_vectors.length() {
      result_u.push(u_vectors[i])
      result_v.push(v_vectors[i])
    }
  }

  { singular_values: result_sv, u_vectors: result_u, v_vectors: result_v }
}

///|
/// Solve the eigenvalue problem for the tridiagonal matrix T = B^T * B
/// where B is the bidiagonal matrix with diagonal `alpha` and superdiagonal `beta`.
///
/// Returns eigenvalues in descending order.
fn solve_bidiagonal_svd(
  alpha : Array[Double],
  beta : Array[Double],
  k : Int,
) -> Array[Double] {
  let n = alpha.length()
  if n == 0 {
    return []
  }

  // Build the tridiagonal matrix T = B^T * B
  // T has diagonal: alpha[i]^2 + beta[i-1]^2
  // T has off-diagonal: alpha[i] * beta[i]
  let diag = Array::make(n, 0.0)
  let off_diag = Array::make(n - 1, 0.0)

  for i = 0; i < n; i = i + 1 {
    let mut val = alpha[i] * alpha[i]
    if i > 0 && i - 1 < beta.length() {
      val = val + beta[i - 1] * beta[i - 1]
    }
    diag[i] = val
  }
  for i = 0; i < n - 1; i = i + 1 {
    if i < beta.length() {
      off_diag[i] = alpha[i] * beta[i]
    }
  }

  // Use the QL algorithm with implicit shifts to find eigenvalues
  let eigenvalues = tridiag_ql_eigenvalues(diag, off_diag, n)

  // Sort in descending order
  let sorted = Array::copy(eigenvalues)
  sorted.sort_by(fn(a, b) { if a > b { -1 } else if a < b { 1 } else { 0 } })

  // Return top-k eigenvalues
  let kk = if k < n { k } else { n }
  let result = Array::make(kk, 0.0)
  for i = 0; i < kk; i = i + 1 {
    result[i] = sorted[i]
  }
  result
}

///|
/// QL algorithm with implicit shifts for symmetric tridiagonal matrices.
///
/// Returns all n eigenvalues of the tridiagonal matrix defined by `diag`
/// (diagonal) and `off_diag` (subdiagonal).
///
/// Reference: Wilkinson, J. H. (1965). "The Algebraic Eigenvalue Problem."
fn tridiag_ql_eigenvalues(
  diag : Array[Double],
  off_diag : Array[Double],
  n : Int,
) -> Array[Double] {
  if n == 0 {
    return []
  }
  if n == 1 {
    return [diag[0]]
  }

  // Make copies to work on
  let d = Array::copy(diag)
  let e = Array::make(n, 0.0)
  for i = 0; i < n - 1; i = i + 1 {
    e[i] = off_diag[i]
  }

  let max_iter = 30
  for l = 0; l < n; l = l + 1 {
    let mut iter = 0
    let mut converged = false
    while !converged && iter < max_iter {
      // Find a small subdiagonal element to split
      let mut m = l
      while m < n - 1 {
        let dd = d[m].abs() + d[m + 1].abs()
        if e[m].abs() <= 1.0e-16 * dd {
          break
        }
        m = m + 1
      }
      if m == l {
        converged = true
        break
      }
      // Compute the shift
      let mut g = (d[l + 1] - d[l]) / (2.0 * e[l])
      let r0 = (g * g + 1.0).sqrt()
      g = d[m] - d[l] + e[l] / (g + (if g > 0 { r0 } else { -r0 }))
      let mut s = 1.0
      let mut c = 1.0
      let mut p = 0.0
      for i = m - 1; i >= l; i = i - 1 {
        let f = s * e[i]
        let b = c * e[i]
        let r = (f * f + g * g).sqrt()
        e[i + 1] = r
        if r < 1.0e-30 {
          d[i + 1] = d[i + 1] - p
          e[m] = 0.0
          break
        }
        s = f / r
        c = g / r
        g = d[i + 1] - p
        let r2 = (d[i] - g) * s + 2.0 * c * b
        p = s * r2
        d[i + 1] = g + p
        g = c * r2 - b
      }
      if !converged {
        d[l] = d[l] - p
        e[l] = g
        e[m] = 0.0
      }
      iter = iter + 1
    }
  }

  d
}

///|
/// Get the number of computed singular values.
pub fn svd_count(result : SVDResult) -> Int {
  result.singular_values.length()
}

///|
/// Get the i-th singular value.
pub fn svd_singular_value(result : SVDResult, i : Int) -> Double {
  if i < 0 || i >= result.singular_values.length() {
    return 0.0
  }
  result.singular_values[i]
}

///|
/// Get the i-th left singular vector (U column).
pub fn svd_u_vector(result : SVDResult, i : Int) -> Array[Double] {
  if i < 0 || i >= result.u_vectors.length() {
    return []
  }
  result.u_vectors[i]
}

///|
/// Get the i-th right singular vector (V column).
pub fn svd_v_vector(result : SVDResult, i : Int) -> Array[Double] {
  if i < 0 || i >= result.v_vectors.length() {
    return []
  }
  result.v_vectors[i]
}
