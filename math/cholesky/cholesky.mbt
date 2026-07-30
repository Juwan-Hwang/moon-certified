/// Cholesky Decomposition — Symmetric Positive Definite Matrix Factorisation.
///
/// The Cholesky decomposition factors a symmetric positive definite (SPD)
/// matrix **A** into the product **A = L · Lᵀ**, where **L** is a lower
/// triangular matrix with positive diagonal entries. This is the matrix
/// analogue of taking a square root, and it is roughly **twice as fast** as
/// LU decomposition for SPD matrices because it exploits symmetry.
///
/// ## Algorithm
///
/// The decomposition is computed column by column using the standard
/// Cholesky-Banachiewicz algorithm:
///
/// For each column `j = 0, 1, …, n-1`:
///
/// 1. **Diagonal element:**
///    `L[j][j] = √(A[j][j] − Σ_{k<j} L[j][k]²)`
///
/// 2. **Off-diagonal elements** (rows `i > j`):
///    `L[i][j] = (A[i][j] − Σ_{k<j} L[i][k]·L[j][k]) / L[j][j]`
///
/// If the radicand in step 1 is non-positive, the matrix is not positive
/// definite and the decomposition fails (returns `None`).
///
/// ## Solving Linear Systems
///
/// Once **A = L · Lᵀ** is available, solving **A·x = b** reduces to two
/// triangular solves:
///
/// 1. Forward substitution: **L·y = b**
/// 2. Backward substitution: **Lᵀ·x = y**
///
/// Each triangular solve is **O(n²)**, so the total solve cost (after
/// factorisation) is **O(n²)**, compared to **O(n³)** for general systems.
///
/// ## Matrix Inverse
///
/// The inverse of an SPD matrix can be computed via the Cholesky factor:
///
/// `A⁻¹ = (Lᵀ)⁻¹ · L⁻¹`
///
/// This is done by solving `L · X = I` (forward substitution for each column
/// of `I`), then `Lᵀ · Y = X` (backward substitution).
///
/// ## Determinant
///
/// `det(A) = det(L)² = (Π L[i][i])²`
///
/// ## Applications
///
/// - **Monte Carlo simulation**: generating correlated random variables
///   (if `z ~ N(0, I)`, then `L·z ~ N(0, A)`).
/// - **Kalman filters**: measurement update and state prediction.
/// - **Optimisation**: interior-point methods, trust-region subproblems.
/// - **Gaussian processes**: kernel matrix factorisation.
/// - **Least squares**: normal equations `AᵀA·x = Aᵀb` where `AᵀA` is SPD.
///
/// ## Complexity
///
/// - Factorisation: **O(n³)** (with a constant factor ~½ compared to LU's ~⅔).
/// - Solve: **O(n²)**.
/// - Inverse: **O(n³)** (two triangular solves per column of I).
///
/// ## Numerical Stability
///
/// Cholesky decomposition is unconditionally backward stable for SPD
/// matrices — no pivoting is required. The relative error is bounded by
/// `O(n · ε_machine · κ(A))`, where `κ(A)` is the condition number.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

///|
/// Result of a Cholesky decomposition.
///
/// Stores the lower triangular factor **L** in a flat `FixedArray[Double]`
/// (row-major). The upper triangle is implicitly zero.
pub struct Cholesky {
  l : FixedArray[Double] // Lower triangular factor L (row-major, n×n)
  n : Int
}

// ---------------------------------------------------------------------------
// Factorisation
// ---------------------------------------------------------------------------

///|
/// Compute the Cholesky decomposition of a symmetric positive definite matrix.
///
/// - `a`: The input matrix in row-major order (`a[i * n + j]` = element at
///   row `i`, column `j`). Only the lower triangle is read (the matrix is
///   assumed symmetric).
/// - `n`: Matrix dimension.
///
/// Returns `None` if the matrix is not positive definite (a diagonal element
/// has a non-positive radicand).
///
/// ## Complexity
///
/// O(n³) with a constant factor of ~½ (exploiting symmetry).
pub fn decompose(a : FixedArray[Double], n : Int) -> Cholesky? {
  if n <= 0 {
    return None
  }
  let l : FixedArray[Double] = FixedArray::make(n * n, 0.0)
  for j = 0; j < n; j = j + 1 {
    // Diagonal element: L[j][j] = sqrt(A[j][j] - sum_{k<j} L[j][k]^2)
    let mut sum = a[j * n + j]
    for k = 0; k < j; k = k + 1 {
      sum = sum - l[j * n + k] * l[j * n + k]
    }
    if sum <= 0.0 {
      return None // Not positive definite
    }
    let diag = sum.sqrt()
    l[j * n + j] = diag
    // Off-diagonal: L[i][j] = (A[i][j] - sum_{k<j} L[i][k]*L[j][k]) / L[j][j]
    for i = j + 1; i < n; i = i + 1 {
      let mut s = a[i * n + j]
      for k = 0; k < j; k = k + 1 {
        s = s - l[i * n + k] * l[j * n + k]
      }
      l[i * n + j] = s / diag
    }
  }
  Some({ l: l, n: n })
}

// ---------------------------------------------------------------------------
// Accessors
// ---------------------------------------------------------------------------

///|
/// Return the lower triangular factor L as a flat row-major array.
pub fn factor(chol : Cholesky) -> FixedArray[Double] {
  chol.l
}

///|
/// Return the matrix dimension.
pub fn dimension(chol : Cholesky) -> Int {
  chol.n
}

///|
/// Return the diagonal entry L[i][i].
pub fn diagonal(chol : Cholesky, i : Int) -> Double {
  chol.l[i * chol.n + i]
}

// ---------------------------------------------------------------------------
// Solving linear systems
// ---------------------------------------------------------------------------

///|
/// Solve the system **A·x = b** using the precomputed Cholesky factor.
///
/// Performs two triangular solves: **L·y = b** (forward), then **Lᵀ·x = y**
/// (backward).
///
/// - `b`: Right-hand side vector (length `n`).
///
/// Returns the solution vector `x` (length `n`).
///
/// ## Complexity
///
/// O(n²).
pub fn solve(chol : Cholesky, b : FixedArray[Double]) -> FixedArray[Double] {
  let n = chol.n
  let y : FixedArray[Double] = FixedArray::make(n, 0.0)
  // Forward substitution: L·y = b
  for i = 0; i < n; i = i + 1 {
    let mut sum = b[i]
    for k = 0; k < i; k = k + 1 {
      sum = sum - chol.l[i * n + k] * y[k]
    }
    y[i] = sum / chol.l[i * n + i]
  }
  // Backward substitution: Lᵀ·x = y
  let x : FixedArray[Double] = FixedArray::make(n, 0.0)
  for i = n - 1; i >= 0; i = i - 1 {
    let mut sum = y[i]
    for k = i + 1; k < n; k = k + 1 {
      sum = sum - chol.l[k * n + i] * x[k] // Lᵀ[i][k] = L[k][i]
    }
    x[i] = sum / chol.l[i * n + i]
  }
  x
}

// ---------------------------------------------------------------------------
// Determinant
// ---------------------------------------------------------------------------

///|
/// Compute det(A) = (Π L[i][i])² using the Cholesky factor.
///
/// For numerical stability, the product of diagonal entries is accumulated
/// in log space when possible.
pub fn determinant(chol : Cholesky) -> Double {
  let n = chol.n
  let mut log_det = 0.0
  for i = 0; i < n; i = i + 1 {
    let d = chol.l[i * n + i]
    if d <= 0.0 {
      return 0.0
    }
    log_det = log_det + 2.0 * @math.ln(d)
  }
  if log_det > 700.0 {
    return 1.0e308
  }
  if log_det < -700.0 {
    return 0.0
  }
  @math.exp(log_det)
}

// ---------------------------------------------------------------------------
// Matrix inverse
// ---------------------------------------------------------------------------

///|
/// Compute A⁻¹ using the Cholesky factor.
///
/// Solves `L · X = I` (forward) then `Lᵀ · Y = X` (backward) for each column
/// of the identity matrix. The result is `A⁻¹ = Y`.
///
/// ## Complexity
///
/// O(n³) — n triangular solves, each O(n²).
pub fn inverse(chol : Cholesky) -> FixedArray[Double] {
  let n = chol.n
  let inv : FixedArray[Double] = FixedArray::make(n * n, 0.0)
  for col = 0; col < n; col = col + 1 {
    // Construct the col-th column of identity.
    let e : FixedArray[Double] = FixedArray::make(n, 0.0)
    e[col] = 1.0
    // Solve A·x = e_col
    let x = solve(chol, e)
    // Fill column col of inverse.
    for i = 0; i < n; i = i + 1 {
      inv[i * n + col] = x[i]
    }
  }
  inv
}

// ---------------------------------------------------------------------------
// Reconstruction (for verification)
// ---------------------------------------------------------------------------

///|
/// Reconstruct A = L · Lᵀ from the Cholesky factor.
///
/// Useful for verifying decomposition correctness.
pub fn reconstruct(chol : Cholesky) -> FixedArray[Double] {
  let n = chol.n
  let a : FixedArray[Double] = FixedArray::make(n * n, 0.0)
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      let mut sum = 0.0
      for k = 0; k < n; k = k + 1 {
        let lik = chol.l[i * n + k]
        let ljk = chol.l[j * n + k]
        // L[i][k] * L[j][k] = L[i][k] * Lᵀ[k][j]
        // But L is lower-triangular, so only k <= min(i,j) contributes.
        sum = sum + lik * ljk
      }
      a[i * n + j] = sum
    }
  }
  a
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn approx_eq(a : Double, b : Double, tol : Double) -> Bool {
  (a - b).abs() < tol
}

test "decompose: 2x2 SPD matrix" {
  // A = [[4, 2], [2, 3]] — SPD (eigenvalues 5±√5 > 0)
  let a : FixedArray[Double] = FixedArray::from_array([4.0, 2.0, 2.0, 3.0])
  let chol = decompose(a, 2).unwrap()
  let l = factor(chol)
  // L = [[2, 0], [1, sqrt(2)]]
  assert_true(approx_eq(l[0], 2.0, 1.0e-10)) // L[0][0] = 2
  assert_true(approx_eq(l[1], 0.0, 1.0e-10)) // L[0][1] = 0
  assert_true(approx_eq(l[2], 1.0, 1.0e-10)) // L[1][0] = 1
  assert_true(approx_eq(l[3], 1.4142135623730951, 1.0e-10)) // L[1][1] = sqrt(2)
}

test "decompose: identity matrix" {
  let n = 3
  let a : FixedArray[Double] = FixedArray::make(n * n, 0.0)
  for i = 0; i < n; i = i + 1 {
    a[i * n + i] = 1.0
  }
  let chol = decompose(a, n).unwrap()
  let l = factor(chol)
  // L should be identity
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      let expected = if i == j { 1.0 } else { 0.0 }
      assert_true(approx_eq(l[i * n + j], expected, 1.0e-10))
    }
  }
}

test "decompose: non-positive-definite returns None" {
  // A = [[1, 2], [2, 1]] — indefinite (eigenvalues 3, -1)
  let a : FixedArray[Double] = FixedArray::from_array([1.0, 2.0, 2.0, 1.0])
  let result = decompose(a, 2)
  assert_true(result is None)
}

test "decompose: zero diagonal returns None" {
  let a : FixedArray[Double] = FixedArray::from_array([0.0, 0.0, 0.0, 0.0])
  let result = decompose(a, 2)
  assert_true(result is None)
}

test "solve: 3x3 system" {
  // A = [[4, 12, -16], [12, 37, -43], [-16, -43, 98]] — SPD
  // A·x = b where b = [1, 2, 3]
  let a : FixedArray[Double] = FixedArray::from_array([
    4.0, 12.0, -16.0, 12.0, 37.0, -43.0, -16.0, -43.0, 98.0,
  ])
  let b : FixedArray[Double] = FixedArray::from_array([1.0, 2.0, 3.0])
  let chol = decompose(a, 3).unwrap()
  let x = solve(chol, b)
  // Verify A·x = b
  for i = 0; i < 3; i = i + 1 {
    let mut sum = 0.0
    for j = 0; j < 3; j = j + 1 {
      sum = sum + a[i * 3 + j] * x[j]
    }
    assert_true(approx_eq(sum, b[i], 1.0e-8))
  }
}

test "solve: diagonal system" {
  let a : FixedArray[Double] = FixedArray::from_array([9.0, 0.0, 0.0, 4.0])
  let b : FixedArray[Double] = FixedArray::from_array([18.0, 8.0])
  let chol = decompose(a, 2).unwrap()
  let x = solve(chol, b)
  assert_true(approx_eq(x[0], 2.0, 1.0e-10))
  assert_true(approx_eq(x[1], 2.0, 1.0e-10))
}

test "determinant: 2x2 SPD" {
  // A = [[4, 2], [2, 3]], det = 4*3 - 2*2 = 8
  let a : FixedArray[Double] = FixedArray::from_array([4.0, 2.0, 2.0, 3.0])
  let chol = decompose(a, 2).unwrap()
  let det = determinant(chol)
  assert_true(approx_eq(det, 8.0, 1.0e-8))
}

test "determinant: identity" {
  let n = 3
  let a : FixedArray[Double] = FixedArray::make(n * n, 0.0)
  for i = 0; i < n; i = i + 1 {
    a[i * n + i] = 1.0
  }
  let chol = decompose(a, n).unwrap()
  let det = determinant(chol)
  assert_true(approx_eq(det, 1.0, 1.0e-10))
}

test "inverse: 2x2 SPD" {
  // A = [[4, 2], [2, 3]], A⁻¹ = [[3/8, -1/4], [-1/4, 1/2]]
  let a : FixedArray[Double] = FixedArray::from_array([4.0, 2.0, 2.0, 3.0])
  let chol = decompose(a, 2).unwrap()
  let inv = inverse(chol)
  assert_true(approx_eq(inv[0], 0.375, 1.0e-10)) // 3/8
  assert_true(approx_eq(inv[1], -0.25, 1.0e-10)) // -1/4
  assert_true(approx_eq(inv[2], -0.25, 1.0e-10)) // -1/4
  assert_true(approx_eq(inv[3], 0.5, 1.0e-10)) // 1/2
}

test "inverse: verify A·A⁻¹ = I" {
  // 3x3 SPD matrix
  let a : FixedArray[Double] = FixedArray::from_array([
    4.0, 12.0, -16.0, 12.0, 37.0, -43.0, -16.0, -43.0, 98.0,
  ])
  let chol = decompose(a, 3).unwrap()
  let inv = inverse(chol)
  // Verify A · inv = I
  for i = 0; i < 3; i = i + 1 {
    for j = 0; j < 3; j = j + 1 {
      let mut sum = 0.0
      for k = 0; k < 3; k = k + 1 {
        sum = sum + a[i * 3 + k] * inv[k * 3 + j]
      }
      let expected = if i == j { 1.0 } else { 0.0 }
      assert_true(approx_eq(sum, expected, 1.0e-8))
    }
  }
}

test "reconstruct: L·Lᵀ = A" {
  let a : FixedArray[Double] = FixedArray::from_array([
    4.0, 12.0, -16.0, 12.0, 37.0, -43.0, -16.0, -43.0, 98.0,
  ])
  let chol = decompose(a, 3).unwrap()
  let recon = reconstruct(chol)
  for i = 0; i < 9; i = i + 1 {
    assert_true(approx_eq(recon[i], a[i], 1.0e-10))
  }
}

test "large matrix: 10x10 SPD" {
  // Construct a diagonally dominant SPD matrix: A = D + v·vᵀ
  // where D = 10*I and v = [1,2,...,10]
  let n = 10
  let a : FixedArray[Double] = FixedArray::make(n * n, 0.0)
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      let vi = (i + 1).to_double()
      let vj = (j + 1).to_double()
      a[i * n + j] = if i == j { 10.0 + vi * vi } else { vi * vj }
    }
  }
  let chol = decompose(a, n).unwrap()
  // Verify reconstruction
  let recon = reconstruct(chol)
  for i = 0; i < n * n; i = i + 1 {
    assert_true(approx_eq(recon[i], a[i], 1.0e-8))
  }
  // Solve A·x = b
  let b : FixedArray[Double] = FixedArray::make(n, 1.0)
  let x = solve(chol, b)
  // Verify A·x = b
  for i = 0; i < n; i = i + 1 {
    let mut sum = 0.0
    for j = 0; j < n; j = j + 1 {
      sum = sum + a[i * n + j] * x[j]
    }
    assert_true(approx_eq(sum, 1.0, 1.0e-6))
  }
}
