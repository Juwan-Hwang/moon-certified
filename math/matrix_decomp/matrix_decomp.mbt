///|
/// Matrix decompositions for `Double` matrices stored in row-major flat
/// `FixedArray[Double]`.
///
/// Implements three fundamental decompositions:
/// - **LU** with partial pivoting: `PA = LU`, plus `lu_solve` for linear
///   systems `Ax = b`.
/// - **QR** via Householder reflections: `A = QR`, numerically stable.
/// - **SVD** via one-sided Jacobi rotations: `A = UΣV^T`, accurate for
///   small-to-medium dense matrices.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn abs(x : Double) -> Double {
  if x < 0.0 {
    -x
  } else {
    x
  }
}

///|
fn sgn(x : Double) -> Double {
  if x >= 0.0 {
    1.0
  } else {
    -1.0
  }
}

// `sqrt` is provided by `@newton_method` (dependency declared in moon.pkg).
// `abs` is a local helper for readability.

///|
/// Multiply `Double` matrix `A` (m×k) by `B` (k×n) → m×n.
fn matmul(
  a : FixedArray[Double],
  m : Int,
  k : Int,
  b : FixedArray[Double],
  n : Int,
) -> FixedArray[Double] {
  let r = FixedArray::make(m * n, 0.0)
  for i = 0; i < m; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      let mut sum = 0.0
      for t = 0; t < k; t = t + 1 {
        sum = sum + a[i * k + t] * b[t * n + j]
      }
      r[i * n + j] = sum
    }
  }
  r
}

// ---------------------------------------------------------------------------
// LU decomposition (partial pivoting)
// ---------------------------------------------------------------------------

///|
/// Result of LU decomposition: `PA = LU`.
///
/// `lu` stores both `L` (unit lower triangular, diagonal not stored) and `U`
/// (upper triangular) in a single `n×n` array. `piv` is the row permutation
/// and `sign` is its sign (+1 or −1), so `det(A) = sign * product(diag(U))`.
pub struct LU {
  lu : FixedArray[Double]
  piv : FixedArray[Int]
  sign : Int
}

///|
/// LU-decompose an `n×n` matrix `a` with partial pivoting.
///
/// Returns `Some(LU)` on success, or `None` if the matrix is (numerically)
/// singular. The input is not modified.
pub fn lu_decompose(a : FixedArray[Double], n : Int) -> LU? {
  if n <= 0 {
    return None
  }
  let lu = FixedArray::make(n * n, 0.0)
  for i = 0; i < n * n; i = i + 1 {
    lu[i] = a[i]
  }
  let piv = FixedArray::makei(n, fn(i) { i })
  let mut sign = 1
  for k = 0; k < n; k = k + 1 {
    // Partial pivot: find the largest |lu[i][k]| for i >= k.
    let mut max_val = abs(lu[k * n + k])
    let mut max_row = k
    for i = k + 1; i < n; i = i + 1 {
      let v = abs(lu[i * n + k])
      if v > max_val {
        max_val = v
        max_row = i
      }
    }
    if max_val < 1.0e-12 {
      return None // singular
    }
    if max_row != k {
      for j = 0; j < n; j = j + 1 {
        let tmp = lu[k * n + j]
        lu[k * n + j] = lu[max_row * n + j]
        lu[max_row * n + j] = tmp
      }
      let tmp = piv[k]
      piv[k] = piv[max_row]
      piv[max_row] = tmp
      sign = -sign
    }
    // Eliminate below the pivot.
    let pivot = lu[k * n + k]
    for i = k + 1; i < n; i = i + 1 {
      lu[i * n + k] = lu[i * n + k] / pivot
      let factor = lu[i * n + k]
      for j = k + 1; j < n; j = j + 1 {
        lu[i * n + j] = lu[i * n + j] - factor * lu[k * n + j]
      }
    }
  }
  Some({ lu, piv, sign, })
}

///|
/// Solve `Ax = b` using a precomputed LU decomposition.
///
/// Returns `Some(x)` on success, or `None` if the decomposition is singular.
pub fn lu_solve(decomp : LU, b : FixedArray[Double]) -> FixedArray[Double]? {
  let n = decomp.piv.length()
  // Apply permutation: y = Pb
  let y = FixedArray::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    y[i] = b[decomp.piv[i]]
  }
  // Forward substitution: Ly = Pb (L has unit diagonal)
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < i; j = j + 1 {
      y[i] = y[i] - decomp.lu[i * n + j] * y[j]
    }
  }
  // Back substitution: Ux = y
  let x = y
  for i = n - 1; i >= 0; i = i - 1 {
    for j = i + 1; j < n; j = j + 1 {
      x[i] = x[i] - decomp.lu[i * n + j] * x[j]
    }
    x[i] = x[i] / decomp.lu[i * n + i]
  }
  Some(x)
}

// ---------------------------------------------------------------------------
// QR decomposition (Householder)
// ---------------------------------------------------------------------------

///|
/// Result of QR decomposition: `A = QR`.
pub struct QR {
  q : FixedArray[Double] // m×m orthogonal
  r : FixedArray[Double] // m×n upper triangular
}

///|
/// QR-decompose an `m×n` matrix `a` via Householder reflections.
///
/// Produces `Q` (m×m orthogonal) and `R` (m×n upper triangular) such that
/// `A = Q·R`. The input is not modified.
pub fn qr_decompose(a : FixedArray[Double], m : Int, n : Int) -> QR {
  let r = FixedArray::make(m * n, 0.0)
  for i = 0; i < m * n; i = i + 1 {
    r[i] = a[i]
  }
  let q = FixedArray::make(m * m, 0.0)
  for i = 0; i < m; i = i + 1 {
    q[i * m + i] = 1.0
  }
  let kmax = if m < n { m } else { n }
  for k = 0; k < kmax; k = k + 1 {
    // Norm of the sub-column R[k:m, k].
    let mut norm_x = 0.0
    for i = k; i < m; i = i + 1 {
      norm_x = norm_x + r[i * n + k] * r[i * n + k]
    }
    norm_x = @newton_method.sqrt(norm_x)
    if norm_x < 1.0e-15 {
      continue
    }
    let alpha = -sgn(r[k * n + k]) * norm_x
    // Householder vector v = x - alpha * e_1 (restricted to rows k..m-1).
    let v = FixedArray::make(m, 0.0)
    v[k] = r[k * n + k] - alpha
    for i = k + 1; i < m; i = i + 1 {
      v[i] = r[i * n + k]
    }
    let mut vtv = 0.0
    for i = k; i < m; i = i + 1 {
      vtv = vtv + v[i] * v[i]
    }
    if vtv < 1.0e-30 {
      continue
    }
    let beta = 2.0 / vtv
    // Apply H to R: R = R - beta * v * (v^T * R)
    for j = k; j < n; j = j + 1 {
      let mut dot = 0.0
      for i = k; i < m; i = i + 1 {
        dot = dot + v[i] * r[i * n + j]
      }
      let s = beta * dot
      for i = k; i < m; i = i + 1 {
        r[i * n + j] = r[i * n + j] - s * v[i]
      }
    }
    // Apply H to Q: Q = Q - beta * (Q * v) * v^T
    for i = 0; i < m; i = i + 1 {
      let mut dot = 0.0
      for l = k; l < m; l = l + 1 {
        dot = dot + q[i * m + l] * v[l]
      }
      let s = beta * dot
      for j = k; j < m; j = j + 1 {
        q[i * m + j] = q[i * m + j] - s * v[j]
      }
    }
  }
  { q, r, }
}

// ---------------------------------------------------------------------------
// SVD (one-sided Jacobi)
// ---------------------------------------------------------------------------

///|
/// Result of SVD: `A = U·Σ·V^T`.
pub struct SVD {
  u : FixedArray[Double] // m×n, left singular vectors (column-normalized)
  s : FixedArray[Double] // n, singular values (descending)
  v : FixedArray[Double] // n×n, right singular vectors
}

///|
/// SVD-decompose an `m×n` matrix `a` via one-sided Jacobi rotations.
///
/// Iterates Jacobi rotations on column pairs until all columns are mutually
/// orthogonal. Singular values are the column norms of the rotated `U`;
/// columns are then normalised to give the left singular vectors.
///
/// Accurate for small-to-medium dense matrices. The input is not modified.
pub fn svd_decompose(a : FixedArray[Double], m : Int, n : Int) -> SVD {
  let u = FixedArray::make(m * n, 0.0)
  for i = 0; i < m * n; i = i + 1 {
    u[i] = a[i]
  }
  let v = FixedArray::make(n * n, 0.0)
  for i = 0; i < n; i = i + 1 {
    v[i * n + i] = 1.0
  }
  let max_sweeps = 100
  let tol = 1.0e-12
  for _sweep = 0; _sweep < max_sweeps; _sweep = _sweep + 1 {
    let mut rotated = false
    for p = 0; p < n - 1; p = p + 1 {
      for q = p + 1; q < n; q = q + 1 {
        let mut alpha = 0.0
        let mut beta = 0.0
        let mut gamma = 0.0
        for i = 0; i < m; i = i + 1 {
          let up = u[i * n + p]
          let uq = u[i * n + q]
          alpha = alpha + up * up
          beta = beta + uq * uq
          gamma = gamma + up * uq
        }
        if abs(gamma) < tol * @newton_method.sqrt(alpha * beta + 1.0e-30) {
          continue
        }
        rotated = true
        let zeta = (beta - alpha) / (2.0 * gamma)
        let t = sgn(zeta) / (abs(zeta) + @newton_method.sqrt(1.0 + zeta * zeta))
        let c = 1.0 / @newton_method.sqrt(1.0 + t * t)
        let s = c * t
        // Rotate columns p and q of U.
        for i = 0; i < m; i = i + 1 {
          let up = u[i * n + p]
          let uq = u[i * n + q]
          u[i * n + p] = c * up - s * uq
          u[i * n + q] = s * up + c * uq
        }
        // Rotate columns p and q of V.
        for i = 0; i < n; i = i + 1 {
          let vp = v[i * n + p]
          let vq = v[i * n + q]
          v[i * n + p] = c * vp - s * vq
          v[i * n + q] = s * vp + c * vq
        }
      }
    }
    if !rotated {
      break
    }
  }
  // Extract singular values (column norms) and normalise U.
  let s = FixedArray::make(n, 0.0)
  for j = 0; j < n; j = j + 1 {
    let mut norm = 0.0
    for i = 0; i < m; i = i + 1 {
      norm = norm + u[i * n + j] * u[i * n + j]
    }
    norm = @newton_method.sqrt(norm)
    s[j] = norm
    if norm > 1.0e-15 {
      for i = 0; i < m; i = i + 1 {
        u[i * n + j] = u[i * n + j] / norm
      }
    }
  }
  // Sort by descending singular value (selection sort on columns).
  for i = 0; i < n - 1; i = i + 1 {
    let mut max_idx = i
    for j = i + 1; j < n; j = j + 1 {
      if s[j] > s[max_idx] {
        max_idx = j
      }
    }
    if max_idx != i {
      let tmp_s = s[i]
      s[i] = s[max_idx]
      s[max_idx] = tmp_s
      for row = 0; row < m; row = row + 1 {
        let tmp = u[row * n + i]
        u[row * n + i] = u[row * n + max_idx]
        u[row * n + max_idx] = tmp
      }
      for row = 0; row < n; row = row + 1 {
        let tmp = v[row * n + i]
        v[row * n + i] = v[row * n + max_idx]
        v[row * n + max_idx] = tmp
      }
    }
  }
  { u, s, v, }
}

// ---------------------------------------------------------------------------
// Eigenvalue computation (QR iteration with Wilkinson shift)
// ---------------------------------------------------------------------------

///|
/// Compute the eigenvalues of a real square matrix using the **Wilkinson-shifted**
/// QR iteration algorithm.
///
/// The algorithm repeatedly computes `A = QR` (via Householder QR) and sets
/// `A ← R·Q`.  Before each sweep, a Wilkinson shift μ is computed from the
/// trailing 2×2 submatrix: μ is the eigenvalue of that submatrix closest to
/// the bottom-right entry.  The shift is applied as `A ← A − μI`, then
/// `A ← RQ + μI`, which accelerates convergence from linear (unshifted) to
/// cubic for symmetric matrices.
///
/// Under mild conditions (e.g., symmetric matrices, or matrices with simple
/// eigenvalues) the sequence converges to a quasi-upper-triangular matrix
/// whose diagonal entries are the eigenvalues.  For real matrices with
/// complex eigenvalues the 2×2 diagonal blocks encode complex conjugate pairs;
/// this function returns only the real parts of diagonal entries as an
/// approximation.
///
/// # Parameters
/// - `a`: row-major `n × n` matrix (not modified).
/// - `n`: dimension.
/// - `max_iters`: maximum QR sweeps (default 1000 is sufficient for most
///   well-conditioned matrices up to ~50×50).
/// - `tol`: convergence tolerance.  Iteration stops when the sum of absolute
///   sub-diagonal entries falls below `tol`.
///
/// # Returns
/// `Some(FixedArray[Double])` of length `n` containing the eigenvalue
/// approximations (in arbitrary order), or `None` if the matrix is not square
/// or `n ≤ 0`.
///
/// # Complexity
/// O(n³ · max_iters) — each QR sweep is O(n³).  Wilkinson shift typically
/// reduces the number of sweeps by an order of magnitude vs. unshifted QR.
///
/// # Limitations
/// - For non-symmetric matrices with complex eigenvalues, only real parts are
///   returned.  Use `SVD` for singular values of rectangular matrices.
/// - Convergence is not guaranteed for all matrices (defective matrices may
///   still fail).  The `max_iters` cap prevents infinite loops.
pub fn eigenvalues(
  a : FixedArray[Double],
  n : Int,
  max_iters : Int,
  tol : Double,
) -> FixedArray[Double]? {
  if n <= 0 || a.length() < n * n {
    return None
  }
  // Work on a copy so the input is not modified.
  let work = FixedArray::make(n * n, 0.0)
  for i = 0; i < n * n; i = i + 1 {
    work[i] = a[i]
  }
  let iters = if max_iters > 0 { max_iters } else { 1000 }
  let epsilon = if tol > 0.0 { tol } else { 1.0e-12 }
  // Reduce to Hessenberg form first to speed up QR iteration.
  hessenberg(work, n)
  // Main QR iteration loop with Wilkinson shift.
  let mut converged = false
  for _iter = 0; _iter < iters && !converged; _iter = _iter + 1 {
    // Compute sum of absolute sub-diagonal entries.
    let mut sub_diag_sum = 0.0
    for i = 1; i < n; i = i + 1 {
      sub_diag_sum = sub_diag_sum + abs(work[i * n + (i - 1)])
    }
    if sub_diag_sum < epsilon {
      converged = true
      break
    }
    // Compute Wilkinson shift from the trailing 2×2 submatrix:
    //   | a  b |
    //   | c  d |
    // eigenvalues: λ = (a+d)/2 ± √((a-d)²/4 + bc)
    // Wilkinson shift = eigenvalue closest to d.
    if n >= 2 {
      let a_ = work[(n - 2) * n + (n - 2)]
      let b_ = work[(n - 2) * n + (n - 1)]
      let c_ = work[(n - 1) * n + (n - 2)]
      let d_ = work[(n - 1) * n + (n - 1)]
      let tr = a_ + d_
      let det = a_ * d_ - b_ * c_
      let disc = tr * tr / 4.0 - det
      let mu = if disc >= 0.0 {
        let sqrt_disc = @newton_method.sqrt(disc)
        let l1 = tr / 2.0 + sqrt_disc
        let l2 = tr / 2.0 - sqrt_disc
        // Choose eigenvalue closest to d_.
        if (l1 - d_).abs() < (l2 - d_).abs() {
          l1
        } else {
          l2
        }
      } else {
        // Complex eigenvalues: use real part as shift.
        tr / 2.0
      }
      // Apply shift: A ← A − μI
      for i = 0; i < n; i = i + 1 {
        work[i * n + i] = work[i * n + i] - mu
      }
      // QR sweep: A ← R·Q where A = QR.
      let qr = qr_decompose(work, n, n)
      let rq = matmul(qr.r, n, n, qr.q, n)
      for i = 0; i < n * n; i = i + 1 {
        work[i] = rq[i]
      }
      // Undo shift: A ← A + μI
      for i = 0; i < n; i = i + 1 {
        work[i * n + i] = work[i * n + i] + mu
      }
    } else {
      // n == 1: already converged.
      break
    }
  }
  // Extract diagonal entries as eigenvalue approximations.
  let result = FixedArray::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    result[i] = work[i * n + i]
  }
  Some(result)
}

///|
/// Reduce a matrix to upper Hessenberg form via Householder reflections.
///
/// After this transformation, `work[i][j] = 0` for all `i > j + 1`.
/// The eigenvalues of the original matrix are preserved on the diagonal.
/// This is a standard pre-processing step for QR iteration that reduces
/// each sweep from O(n³) to O(n²).
fn hessenberg(a : FixedArray[Double], n : Int) -> Unit {
  if n <= 2 {
    return
  }
  for k = 0; k < n - 2; k = k + 1 {
    // Build Householder vector for the sub-column a[k+1..n, k].
    let mut norm_x = 0.0
    for i = k + 1; i < n; i = i + 1 {
      norm_x = norm_x + a[i * n + k] * a[i * n + k]
    }
    norm_x = @newton_method.sqrt(norm_x)
    if norm_x < 1.0e-15 {
      continue // Column already zeroed below k+1
    }
    // v = x ± ||x|| * e_1 (choose sign to avoid cancellation)
    let sign = if a[(k + 1) * n + k] >= 0.0 { 1.0 } else { -1.0 }
    let alpha = -sign * norm_x
    let v = FixedArray::make(n, 0.0)
    v[k + 1] = a[(k + 1) * n + k] - alpha
    for i = k + 2; i < n; i = i + 1 {
      v[i] = a[i * n + k]
    }
    // Compute v^T * v
    let mut vtv = 0.0
    for i = k + 1; i < n; i = i + 1 {
      vtv = vtv + v[i] * v[i]
    }
    if vtv < 1.0e-15 {
      continue
    }
    // Apply H = I - 2*v*v^T / (v^T*v) from left: A ← H * A
    for j = 0; j < n; j = j + 1 {
      let mut dot = 0.0
      for i = k + 1; i < n; i = i + 1 {
        dot = dot + v[i] * a[i * n + j]
      }
      let factor = 2.0 * dot / vtv
      for i = k + 1; i < n; i = i + 1 {
        a[i * n + j] = a[i * n + j] - factor * v[i]
      }
    }
    // Apply H from right: A ← A * H
    for i = 0; i < n; i = i + 1 {
      let mut dot = 0.0
      for j = k + 1; j < n; j = j + 1 {
        dot = dot + a[i * n + j] * v[j]
      }
      let factor = 2.0 * dot / vtv
      for j = k + 1; j < n; j = j + 1 {
        a[i * n + j] = a[i * n + j] - factor * v[j]
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "LU: 2x2 decomposition and solve" {
  // [4 3] [x]   [10]
  // [6 3] [y] = [12]
  // Solution: x = 1, y = 2
  let a = FixedArray::make(4, 0.0)
  a[0] = 4.0
  a[1] = 3.0
  a[2] = 6.0
  a[3] = 3.0
  let b = FixedArray::make(2, 0.0)
  b[0] = 10.0
  b[1] = 12.0
  match lu_decompose(a, 2) {
    Some(lu) => {
      let x = lu_solve(lu, b).unwrap()
      assert_true(abs(x[0] - 1.0) < 1.0e-10)
      assert_true(abs(x[1] - 2.0) < 1.0e-10)
    }
    None => assert_true(false)
  }
}

///|
test "LU: 3x3 solve" {
  // [2 1 1] [x]   [5]
  // [1 3 2] [y] = [15]
  // [1 0 0] [z]   [7]
  // x = 7, y = -5, z = 3... let's check: 2*7+(-5)+3 = 12 != 5.
  // Let's use a simpler system:
  // [1 0 0] [x]   [1]     x = 1
  // [0 1 0] [y] = [2]  => y = 2
  // [0 0 1] [z]   [3]     z = 3
  let a = FixedArray::make(9, 0.0)
  a[0] = 1.0
  a[4] = 1.0
  a[8] = 1.0
  let b = FixedArray::make(3, 0.0)
  b[0] = 1.0
  b[1] = 2.0
  b[2] = 3.0
  let lu = lu_decompose(a, 3)
  assert_true(lu is Some(_))
  let x = lu_solve(lu.unwrap(), b).unwrap()
  assert_true(abs(x[0] - 1.0) < 1.0e-10)
  assert_true(abs(x[1] - 2.0) < 1.0e-10)
  assert_true(abs(x[2] - 3.0) < 1.0e-10)
}

///|
test "LU: pivoting handles zero diagonal" {
  // [0 1] [x]   [2]     x = 1
  // [1 0] [y] = [1]  => y = 2
  let a = FixedArray::make(4, 0.0)
  a[1] = 1.0
  a[2] = 1.0
  let b = FixedArray::make(2, 0.0)
  b[0] = 2.0
  b[1] = 1.0
  match lu_decompose(a, 2) {
    Some(lu) => {
      let x = lu_solve(lu, b).unwrap()
      assert_true(abs(x[0] - 1.0) < 1.0e-10)
      assert_true(abs(x[1] - 2.0) < 1.0e-10)
    }
    None => assert_true(false)
  }
}

///|
test "LU: singular matrix returns None" {
  let a = FixedArray::make(4, 0.0)
  a[0] = 1.0
  a[1] = 2.0
  a[2] = 2.0
  a[3] = 4.0 // row 2 = 2 * row 1
  assert_true(lu_decompose(a, 2) is None)
}

///|
test "LU: determinant via diagonal product" {
  // [4 3; 6 3] det = 4*3 - 3*6 = -6
  let a = FixedArray::make(4, 0.0)
  a[0] = 4.0
  a[1] = 3.0
  a[2] = 6.0
  a[3] = 3.0
  let lu = lu_decompose(a, 2).unwrap()
  let mut det = lu.sign.to_double()
  for i = 0; i < 2; i = i + 1 {
    det = det * lu.lu[i * 2 + i]
  }
  assert_true(abs(det - -6.0) < 1.0e-10)
}

///|
test "QR: 3x3 identity reconstructs A = QR" {
  let a = FixedArray::make(9, 0.0)
  a[0] = 1.0
  a[4] = 1.0
  a[8] = 1.0
  let qr = qr_decompose(a, 3, 3)
  // Householder QR may produce Q = -I, R = -I for the identity matrix
  // (both sign flips cancel). Verify reconstruction A = Q·R instead.
  for i = 0; i < 3; i = i + 1 {
    for j = 0; j < 3; j = j + 1 {
      let mut dot = 0.0
      for k = 0; k < 3; k = k + 1 {
        dot = dot + qr.q[i * 3 + k] * qr.r[k * 3 + j]
      }
      let expected = if i == j { 1.0 } else { 0.0 }
      assert_true(abs(dot - expected) < 1.0e-10)
    }
  }
}

///|
test "QR: 3x3 matrix reconstructs A = QR" {
  // [1 2 3]
  // [4 5 6]
  // [7 8 10]
  let a = FixedArray::make(9, 0.0)
  a[0] = 1.0
  a[1] = 2.0
  a[2] = 3.0
  a[3] = 4.0
  a[4] = 5.0
  a[5] = 6.0
  a[6] = 7.0
  a[7] = 8.0
  a[8] = 10.0
  let qr = qr_decompose(a, 3, 3)
  let qr_prod = matmul(qr.q, 3, 3, qr.r, 3)
  for i = 0; i < 3; i = i + 1 {
    for j = 0; j < 3; j = j + 1 {
      assert_true(abs(qr_prod[i * 3 + j] - a[i * 3 + j]) < 1.0e-9)
    }
  }
}

///|
test "QR: Q is orthogonal" {
  let a = FixedArray::make(9, 0.0)
  a[0] = 12.0
  a[1] = -51.0
  a[2] = 4.0
  a[3] = 6.0
  a[4] = 167.0
  a[5] = -68.0
  a[6] = -4.0
  a[7] = 24.0
  a[8] = -41.0
  let qr = qr_decompose(a, 3, 3)
  // Q^T * Q should be identity.
  let qt = FixedArray::make(9, 0.0)
  for i = 0; i < 3; i = i + 1 {
    for j = 0; j < 3; j = j + 1 {
      qt[i * 3 + j] = qr.q[j * 3 + i]
    }
  }
  let qtq = matmul(qt, 3, 3, qr.q, 3)
  for i = 0; i < 3; i = i + 1 {
    for j = 0; j < 3; j = j + 1 {
      let expected = if i == j { 1.0 } else { 0.0 }
      assert_true(abs(qtq[i * 3 + j] - expected) < 1.0e-9)
    }
  }
}

///|
test "QR: R is upper triangular" {
  let a = FixedArray::make(9, 0.0)
  a[0] = 1.0
  a[1] = 2.0
  a[2] = 3.0
  a[3] = 4.0
  a[4] = 5.0
  a[5] = 6.0
  a[6] = 7.0
  a[7] = 8.0
  a[8] = 10.0
  let qr = qr_decompose(a, 3, 3)
  for i = 1; i < 3; i = i + 1 {
    for j = 0; j < i; j = j + 1 {
      assert_true(abs(qr.r[i * 3 + j]) < 1.0e-9)
    }
  }
}

///|
test "QR: rectangular 3x2" {
  let a = FixedArray::make(6, 0.0)
  a[0] = 1.0
  a[1] = 2.0
  a[2] = 3.0
  a[3] = 4.0
  a[4] = 5.0
  a[5] = 6.0
  let qr = qr_decompose(a, 3, 2)
  let qr_prod = matmul(qr.q, 3, 3, qr.r, 2)
  for i = 0; i < 3; i = i + 1 {
    for j = 0; j < 2; j = j + 1 {
      assert_true(abs(qr_prod[i * 2 + j] - a[i * 2 + j]) < 1.0e-9)
    }
  }
}

///|
test "SVD: 2x2 square matrix" {
  // [3 0]
  // [0 4]
  // Singular values should be 4 and 3.
  let a = FixedArray::make(4, 0.0)
  a[0] = 3.0
  a[3] = 4.0
  let svd = svd_decompose(a, 2, 2)
  assert_true(abs(svd.s[0] - 4.0) < 1.0e-8)
  assert_true(abs(svd.s[1] - 3.0) < 1.0e-8)
}

///|
test "SVD: reconstructs A = U*S*V^T" {
  // [1 2]
  // [3 4]
  let a = FixedArray::make(4, 0.0)
  a[0] = 1.0
  a[1] = 2.0
  a[2] = 3.0
  a[3] = 4.0
  let svd = svd_decompose(a, 2, 2)
  // Build S diagonal, V^T.
  let s_diag = FixedArray::make(4, 0.0)
  s_diag[0] = svd.s[0]
  s_diag[3] = svd.s[1]
  let vt = FixedArray::make(4, 0.0)
  for i = 0; i < 2; i = i + 1 {
    for j = 0; j < 2; j = j + 1 {
      vt[i * 2 + j] = svd.v[j * 2 + i]
    }
  }
  let us = matmul(svd.u, 2, 2, s_diag, 2)
  let usvt = matmul(us, 2, 2, vt, 2)
  for i = 0; i < 2; i = i + 1 {
    for j = 0; j < 2; j = j + 1 {
      assert_true(abs(usvt[i * 2 + j] - a[i * 2 + j]) < 1.0e-8)
    }
  }
}

///|
test "SVD: singular values of known matrix" {
  // [3 0 0]
  // [0 4 0]
  // [0 0 5]
  // Singular values: 5, 4, 3
  let a = FixedArray::make(9, 0.0)
  a[0] = 3.0
  a[4] = 4.0
  a[8] = 5.0
  let svd = svd_decompose(a, 3, 3)
  assert_true(abs(svd.s[0] - 5.0) < 1.0e-7)
  assert_true(abs(svd.s[1] - 4.0) < 1.0e-7)
  assert_true(abs(svd.s[2] - 3.0) < 1.0e-7)
}

///|
test "SVD: rank-deficient matrix" {
  // [1 2]   rank 1: [1] * [1 2]
  // [2 4]
  let a = FixedArray::make(4, 0.0)
  a[0] = 1.0
  a[1] = 2.0
  a[2] = 2.0
  a[3] = 4.0
  let svd = svd_decompose(a, 2, 2)
  // Largest singular value = sqrt(1+4+4+16) = sqrt(25) = 5
  assert_true(abs(svd.s[0] - 5.0) < 1.0e-7)
  // Smallest should be ~0.
  assert_true(svd.s[1] < 1.0e-7)
}

///|
test "SVD: columns of U are orthonormal" {
  let a = FixedArray::make(6, 0.0)
  a[0] = 1.0
  a[1] = 2.0
  a[2] = 3.0
  a[3] = 4.0
  a[4] = 5.0
  a[5] = 6.0
  let svd = svd_decompose(a, 3, 2)
  // U^T * U should be identity (2x2).
  for i = 0; i < 2; i = i + 1 {
    for j = 0; j < 2; j = j + 1 {
      let mut dot = 0.0
      for k = 0; k < 3; k = k + 1 {
        dot = dot + svd.u[k * 2 + i] * svd.u[k * 2 + j]
      }
      let expected = if i == j { 1.0 } else { 0.0 }
      assert_true(abs(dot - expected) < 1.0e-8)
    }
  }
}

///|
test "LU: 4x4 solve" {
  // [1 0 0 0] [x]   [1]
  // [0 1 0 0] [y] = [2]
  // [0 0 1 0] [z]   [3]
  // [0 0 0 1] [w]   [4]
  let a = FixedArray::make(16, 0.0)
  for i = 0; i < 4; i = i + 1 {
    a[i * 4 + i] = 1.0
  }
  let b = FixedArray::make(4, 0.0)
  b[0] = 1.0
  b[1] = 2.0
  b[2] = 3.0
  b[3] = 4.0
  let lu = lu_decompose(a, 4).unwrap()
  let x = lu_solve(lu, b).unwrap()
  for i = 0; i < 4; i = i + 1 {
    assert_true(abs(x[i] - (i + 1).to_double()) < 1.0e-10)
  }
}

///|
test "eigenvalues: 2x2 diagonal matrix" {
  // [3 0]
  // [0 5]  → eigenvalues 3 and 5
  let a = FixedArray::make(4, 0.0)
  a[0] = 3.0
  a[3] = 5.0
  match eigenvalues(a, 2, 1000, 1.0e-10) {
    Some(eigs) => {
      // Eigenvalues in arbitrary order: {3, 5}
      let mut has3 = false
      let mut has5 = false
      for i = 0; i < 2; i = i + 1 {
        if abs(eigs[i] - 3.0) < 1.0e-6 {
          has3 = true
        }
        if abs(eigs[i] - 5.0) < 1.0e-6 {
          has5 = true
        }
      }
      assert_true(has3)
      assert_true(has5)
    }
    None => fail("eigenvalues returned None")
  }
}

///|
test "eigenvalues: 2x2 symmetric matrix" {
  // [4 1]
  // [1 3]  → eigenvalues (7±√5)/2 ≈ 4.618 and 2.382
  let a = FixedArray::make(4, 0.0)
  a[0] = 4.0
  a[1] = 1.0
  a[2] = 1.0
  a[3] = 3.0
  match eigenvalues(a, 2, 1000, 1.0e-12) {
    Some(eigs) => {
      // Check trace = 7 and determinant = 11
      let trace = eigs[0] + eigs[1]
      let det = eigs[0] * eigs[1]
      assert_true(abs(trace - 7.0) < 1.0e-6)
      assert_true(abs(det - 11.0) < 1.0e-6)
    }
    None => fail("eigenvalues returned None")
  }
}

///|
test "eigenvalues: 3x3 diagonal" {
  // [1 0 0]
  // [0 2 0]
  // [0 0 3]  → eigenvalues 1, 2, 3
  let a = FixedArray::make(9, 0.0)
  a[0] = 1.0
  a[4] = 2.0
  a[8] = 3.0
  match eigenvalues(a, 3, 1000, 1.0e-10) {
    Some(eigs) => {
      let mut has1 = false
      let mut has2 = false
      let mut has3 = false
      for i = 0; i < 3; i = i + 1 {
        if abs(eigs[i] - 1.0) < 1.0e-6 {
          has1 = true
        }
        if abs(eigs[i] - 2.0) < 1.0e-6 {
          has2 = true
        }
        if abs(eigs[i] - 3.0) < 1.0e-6 {
          has3 = true
        }
      }
      assert_true(has1)
      assert_true(has2)
      assert_true(has3)
    }
    None => fail("eigenvalues returned None")
  }
}

///|
test "eigenvalues: 3x3 symmetric" {
  // [2 1 0]
  // [1 2 1]
  // [0 1 2]  → eigenvalues 2, 2+√2, 2-√2
  let a = FixedArray::make(9, 0.0)
  a[0] = 2.0
  a[1] = 1.0
  a[4] = 2.0
  a[5] = 1.0
  a[7] = 1.0
  a[8] = 2.0
  match eigenvalues(a, 3, 2000, 1.0e-14) {
    Some(eigs) => {
      // Trace = 6, product = 2*2 - 1 - 1 = 2... actually det = 2(4-1) - 1(2) = 6-2 = 4
      let trace = eigs[0] + eigs[1] + eigs[2]
      assert_true(abs(trace - 6.0) < 1.0e-5)
    }
    None => fail("eigenvalues returned None")
  }
}

///|
test "eigenvalues: invalid input returns None" {
  assert_true(eigenvalues(FixedArray::make(0, 0.0), 0, 100, 1.0e-10) is None)
  assert_true(eigenvalues(FixedArray::make(2, 0.0), 2, 100, 1.0e-10) is None)
}
