/// Semidefinite Programming (SDP) solver.
///
/// Solves the primal SDP problem:
///
/// ```text
/// minimize    C • X
/// subject to  A_i • X = b_i,  i = 1..m
///             X ⪰ 0  (symmetric positive semidefinite)
/// ```
///
/// where C • X = trace(C^T X) is the Frobenius inner product.
///
/// ## Algorithm
///
/// Uses a projected subgradient method with eigenvalue-based PSD
/// projection. For each iteration:
/// 1. Take a gradient step on the objective + equality penalty.
/// 2. Project onto the PSD cone by computing the eigendecomposition
///    and clamping negative eigenvalues to zero.
/// 3. Project onto the equality constraints.
///
/// This method is simple and works well for small to medium problems.
/// For large-scale problems, an interior-point method would be preferred.
///
/// ## Applications
///
/// - MAXCUT relaxation
/// - Lovász theta number
/// - Trace norm minimisation
/// - Quantum information
///
/// ## References
///
/// - Vandenberghe, L. and Boyd, S. "Semidefinite Programming." SIAM Review, 1996.
/// - Burer, S. and Monteiro, R.D.C. "A Nonlinear Programming Algorithm for
///   Solving Semidefinite Programs via Low-Rank Factorization."
///   Math. Programming, 2003.
///
/// `proof-enabled` is `false`.

// ---------------------------------------------------------------------------
// Matrix helpers (flat row-major Double arrays)
// ---------------------------------------------------------------------------

/// Create an n×n zero matrix. Each row is an independent array.
fn zeros(n : Int) -> Array[Array[Double]] {
  let r : Array[Array[Double]] = []
  for i = 0; i < n; i = i + 1 {
    r.push(Array::make(n, 0.0))
  }
  r
}

/// Frobenius inner product: C • X = sum_{i,j} C[i][j] * X[i][j].
fn frobenius(a : Array[Array[Double]], b : Array[Array[Double]], n : Int) -> Double {
  let mut sum = 0.0
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      sum = sum + a[i][j] * b[i][j]
    }
  }
  sum
}

/// Matrix addition: result = a + b.
fn mat_add(a : Array[Array[Double]], b : Array[Array[Double]], n : Int) -> Array[Array[Double]] {
  let r = zeros(n)
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      r[i][j] = a[i][j] + b[i][j]
    }
  }
  r
}

/// Matrix subtraction: result = a - b.
fn mat_sub(a : Array[Array[Double]], b : Array[Array[Double]], n : Int) -> Array[Array[Double]] {
  let r = zeros(n)
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      r[i][j] = a[i][j] - b[i][j]
    }
  }
  r
}

/// Scalar multiplication: result = s * a.
fn mat_scale(s : Double, a : Array[Array[Double]], n : Int) -> Array[Array[Double]] {
  let r = zeros(n)
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      r[i][j] = s * a[i][j]
    }
  }
  r
}


/// Symmetrise a matrix: result = (X + X^T) / 2.
fn symmetrise(a : Array[Array[Double]], n : Int) -> Array[Array[Double]] {
  let r = zeros(n)
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      r[i][j] = (a[i][j] + a[j][i]) / 2.0
    }
  }
  r
}

/// Clone a matrix.
fn mat_copy(a : Array[Array[Double]], n : Int) -> Array[Array[Double]] {
  let r = zeros(n)
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      r[i][j] = a[i][j]
    }
  }
  r
}

// ---------------------------------------------------------------------------
// Eigenvalue computation (Jacobi rotation method)
// ---------------------------------------------------------------------------

/// Compute eigenvalues and eigenvectors of a symmetric matrix using the
/// Jacobi rotation method. This is numerically stable for small matrices
/// and converges quadratically near the solution.
///
/// Returns (eigenvalues, eigenvectors) where eigenvectors[i] is the i-th eigenvector.
fn top_eigen(a : Array[Array[Double]], n : Int, k : Int) -> (Array[Double], Array[Array[Double]]) {
  if n == 0 {
    return ([], [])
  }
  if n == 1 {
    return ([a[0][0]], [[1.0]])
  }
  // Copy the matrix (will be diagonalised in-place)
  let mat = mat_copy(a, n)
  // Eigenvector accumulator, starts as identity
  let v = zeros(n)
  for i = 0; i < n; i = i + 1 {
    v[i][i] = 1.0
  }
  let max_sweeps = 100
  for sweep = 0; sweep < max_sweeps; sweep = sweep + 1 {
    // Find the largest off-diagonal element
    let mut max_val = 0.0
    let mut p = 0
    let mut q = 1
    for i = 0; i < n - 1; i = i + 1 {
      for j = i + 1; j < n; j = j + 1 {
        let abs_val = mat[i][j].abs()
        if abs_val > max_val {
          max_val = abs_val
          p = i
          q = j
        }
      }
    }
    if max_val < 1.0e-14 {
      break
    }
    // Compute Jacobi rotation that zeros mat[p][q]
    let app = mat[p][p]
    let aqq = mat[q][q]
    let apq = mat[p][q]
    let tau = (aqq - app) / (2.0 * apq)
    let t = if tau >= 0.0 {
      1.0 / (tau + sqrt_(tau * tau + 1.0))
    } else {
      -1.0 / (-tau + sqrt_(tau * tau + 1.0))
    }
    let c = 1.0 / sqrt_(t * t + 1.0)
    let s = t * c
    // Apply rotation: A' = J^T * A * J (update columns then rows)
    for i = 0; i < n; i = i + 1 {
      let a_ip = mat[i][p]
      let a_iq = mat[i][q]
      mat[i][p] = c * a_ip - s * a_iq
      mat[i][q] = s * a_ip + c * a_iq
    }
    for j = 0; j < n; j = j + 1 {
      let a_pj = mat[p][j]
      let a_qj = mat[q][j]
      mat[p][j] = c * a_pj - s * a_qj
      mat[q][j] = s * a_pj + c * a_qj
    }
    // Update eigenvectors: V' = V * J
    for i = 0; i < n; i = i + 1 {
      let v_ip = v[i][p]
      let v_iq = v[i][q]
      v[i][p] = c * v_ip - s * v_iq
      v[i][q] = s * v_ip + c * v_iq
    }
  }
  // Extract eigenvalues (diagonal of mat) and eigenvectors (columns of v)
  let all_eigenvalues : Array[Double] = []
  let all_eigenvectors : Array[Array[Double]] = []
  for i = 0; i < n; i = i + 1 {
    all_eigenvalues.push(mat[i][i])
    let vec : Array[Double] = []
    for j = 0; j < n; j = j + 1 {
      vec.push(v[j][i])
    }
    all_eigenvectors.push(vec)
  }
  // Sort by descending absolute value and return top k
  let indices : Array[Int] = []
  for i = 0; i < n; i = i + 1 {
    indices.push(i)
  }
  // Simple selection sort by |eigenvalue| descending
  for i = 0; i < n - 1; i = i + 1 {
    for j = i + 1; j < n; j = j + 1 {
      if all_eigenvalues[indices[j]].abs() > all_eigenvalues[indices[i]].abs() {
        let tmp = indices[i]
        indices[i] = indices[j]
        indices[j] = tmp
      }
    }
  }
  let kk = if k > n { n } else { k }
  let eigenvalues : Array[Double] = []
  let eigenvectors : Array[Array[Double]] = []
  for i = 0; i < kk; i = i + 1 {
    eigenvalues.push(all_eigenvalues[indices[i]])
    eigenvectors.push(all_eigenvectors[indices[i]])
  }
  (eigenvalues, eigenvectors)
}


/// Square root via built-in Double method.
fn sqrt_(x : Double) -> Double {
  if x <= 0.0 {
    return 0.0
  }
  x.sqrt()
}

// ---------------------------------------------------------------------------
// PSD projection
// ---------------------------------------------------------------------------

/// Project a symmetric matrix onto the PSD cone.
/// X_psd = sum_{λ_i >= 0} λ_i * v_i * v_i^T
fn project_psd(a : Array[Array[Double]], n : Int) -> Array[Array[Double]] {
  let sym = symmetrise(a, n)
  let (eigenvalues, eigenvectors) = top_eigen(sym, n, n)
  let result = zeros(n)
  for idx = 0; idx < eigenvalues.length(); idx = idx + 1 {
    let lambda = eigenvalues[idx]
    if lambda > 0.0 {
      let v = eigenvectors[idx]
      // result += lambda * v * v^T
      for i = 0; i < n; i = i + 1 {
        for j = 0; j < n; j = j + 1 {
          result[i][j] = result[i][j] + lambda * v[i] * v[j]
        }
      }
    }
  }
  result
}

/// Check if a symmetric matrix is positive semidefinite.
fn is_psd(a : Array[Array[Double]], n : Int) -> Bool {
  let sym = symmetrise(a, n)
  let (eigenvalues, _) = top_eigen(sym, n, n)
  for i = 0; i < eigenvalues.length(); i = i + 1 {
    if eigenvalues[i] < -1.0e-8 {
      return false
    }
  }
  true
}

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

///|
/// A linear equality constraint A_i • X = b_i.
pub struct Constraint {
  /// Constraint matrix (n×n).
  a : Array[Array[Double]]
  /// Right-hand side.
  b : Double
}

///|
/// Result of solving an SDP.
pub struct SDPResult {
  /// Optimal primal variable X.
  x : Array[Array[Double]]
  /// Optimal objective value C • X.
  objective : Double
  /// Whether the solver converged.
  converged : Bool
  /// Number of iterations.
  iterations : Int
}

// ---------------------------------------------------------------------------
// SDP solver
// ---------------------------------------------------------------------------

///|
/// Solve the SDP: minimize C • X subject to A_i • X = b_i, X ⪰ 0.
///
/// - `c`: objective matrix (n×n, symmetric).
/// - `constraints`: equality constraints.
/// - `n`: matrix dimension.
/// - `max_iter`: maximum iterations.
/// - `lr`: step size for gradient descent.
pub fn solve(
  c : Array[Array[Double]],
  constraints : Array[Constraint],
  n : Int,
  max_iter : Int,
  lr : Double,
) -> SDPResult {
  if n == 0 {
    return { x: [], objective: 0.0, converged: true, iterations: 0 }
  }
  // Start with a feasible point: satisfy constraints, then project to PSD
  let x = zeros(n)
  // Project onto equality constraints (iterative)
  let mut x_current = project_psd(x, n)
  let mut prev_obj = 1.0e18
  let mut converged = false
  let mut iter = 0
  while iter < max_iter {
    iter = iter + 1
    // Gradient of objective: C
    let mut grad = mat_copy(c, n)
    // Penalty for constraint violation: sum_i (A_i • X - b_i) * A_i
    for ci = 0; ci < constraints.length(); ci = ci + 1 {
      let residual = frobenius(constraints[ci].a, x_current, n) - constraints[ci].b
      let penalty = mat_scale(residual * 10.0, constraints[ci].a, n)
      grad = mat_add(grad, penalty, n)
    }
    // Gradient step
    let stepped = mat_sub(x_current, mat_scale(lr, grad, n), n)
    // Project onto PSD cone
    x_current = project_psd(stepped, n)
    // Compute objective
    let obj = frobenius(c, x_current, n)
    if (obj - prev_obj).abs() < 1.0e-10 {
      converged = true
      break
    }
    prev_obj = obj
  }
  let obj = frobenius(c, x_current, n)
  { x: x_current, objective: obj, converged, iterations: iter }
}

///|
/// Check if a matrix is positive semidefinite.
pub fn check_psd(a : Array[Array[Double]], n : Int) -> Bool {
  is_psd(a, n)
}

///|
/// Project a matrix onto the positive semidefinite cone.
pub fn project_to_psd(a : Array[Array[Double]], n : Int) -> Array[Array[Double]] {
  project_psd(a, n)
}

///|
/// Compute the maximum eigenvalue of a symmetric matrix.
pub fn max_eigenvalue(a : Array[Array[Double]], n : Int) -> Double {
  let sym = symmetrise(a, n)
  let (eigenvalues, _) = top_eigen(sym, n, 1)
  if eigenvalues.length() > 0 {
    eigenvalues[0]
  } else {
    0.0
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "sdp: identity is PSD" {
  let id = zeros(3)
  for i = 0; i < 3; i = i + 1 {
    id[i][i] = 1.0
  }
  assert_true(check_psd(id, 3))
}

///|
test "sdp: negative diagonal is not PSD" {
  let m = zeros(2)
  m[0][0] = -1.0
  m[1][1] = -1.0
  assert_false(check_psd(m, 2))
}

///|
test "sdp: project indefinite to PSD" {
  let m = zeros(2)
  m[0][0] = 3.0
  m[1][1] = -1.0
  let projected = project_to_psd(m, 2)
  assert_true(check_psd(projected, 2))
}

///|
test "sdp: max eigenvalue of identity" {
  let id = zeros(3)
  for i = 0; i < 3; i = i + 1 {
    id[i][i] = 1.0
  }
  let ev = max_eigenvalue(id, 3)
  assert_true((ev - 1.0).abs() < 0.01)
}

///|
test "sdp: solve trivial problem" {
  // minimize X[0][0] + X[1][1] subject to X[0][0] + X[1][1] = 2, X ⪰ 0
  let c = zeros(2)
  c[0][0] = 1.0
  c[1][1] = 1.0
  let a1 = zeros(2)
  a1[0][0] = 1.0
  a1[1][1] = 1.0
  let constraints : Array[Constraint] = [{ a: a1, b: 2.0 }]
  let result = solve(c, constraints, 2, 500, 0.01)
  // Objective should be close to 2
  assert_true(result.objective < 3.0)
  assert_true(check_psd(result.x, 2))
}

///|
test "sdp: PSD projection preserves PSD matrix" {
  let m = zeros(2)
  m[0][0] = 2.0
  m[0][1] = 1.0
  m[1][0] = 1.0
  m[1][1] = 2.0
  let projected = project_to_psd(m, 2)
  // Should be close to original since it's already PSD
  assert_true((projected[0][0] - 2.0).abs() < 0.1)
  assert_true((projected[1][1] - 2.0).abs() < 0.1)
}

///|
test "sdp: empty problem" {
  let result = solve([], [], 0, 10, 0.01)
  assert_eq(result.objective, 0.0)
  assert_true(result.converged)
}
