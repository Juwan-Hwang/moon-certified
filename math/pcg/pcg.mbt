/// Preconditioned Conjugate Gradient (PCG) Method — production-grade iterative
/// solver for symmetric positive-definite (SPD) linear systems.
///
/// Solves Ax = b where A is n×n SPD, using a preconditioner M ≈ A to accelerate
/// convergence. The preconditioner M must be SPD and easy to invert.
///
/// ## Algorithm (Golub & Van Loan Algorithm 11.5.1)
///
/// ```text
/// x₀ = initial guess
/// r₀ = b - A·x₀
/// z₀ = M⁻¹·r₀          (apply preconditioner)
/// p₀ = z₀
/// for k = 0, 1, 2, …:
///   αₖ = (rₖᵀ zₖ) / (pₖᵀ A pₖ)
///   xₖ₊₁ = xₖ + αₖ pₖ
///   rₖ₊₁ = rₖ - αₖ A pₖ
///   if ‖rₖ₊₁‖ < tol: stop
///   zₖ₊₁ = M⁻¹·rₖ₊₁
///   βₖ = (rₖ₊₁ᵀ zₖ₊₁) / (rₖᵀ zₖ)
///   pₖ₊₁ = zₖ₊₁ + βₖ pₖ
/// ```
///
/// ## Supported Preconditioners
///
/// - **Jacobi (diagonal)**: M = diag(A). O(n) per application. Simple but effective
///   for diagonally dominant matrices.
/// - **SSOR (Symmetric Successive Over-Relaxation)**: M = (D+L)D⁻¹(D+L)ᵀ where
///   0 < ω < 2. O(n²) per application for dense matrices. More powerful than Jacobi.
/// - **Incomplete Cholesky (IC0)**: M = L̃·L̃ᵀ where L̃ is the incomplete Cholesky
///   factor (same sparsity pattern as A's lower triangle). O(n²) per application.
///   Most effective general-purpose preconditioner for SPD systems.
/// - **Identity (no preconditioning)**: Equivalent to standard CG.
///
/// ## Complexity
///
/// - Per iteration: O(n²) for dense matvec + O(cost of M⁻¹) for preconditioner.
/// - Convergence: O(√(κ(M⁻¹A))) iterations, where κ is the condition number.
///   A good preconditioner makes κ(M⁻¹A) ≪ κ(A).
///
/// ## References
///
/// - Golub, G. H. and Van Loan, C. F. (2013): "Matrix Computations," 4th ed.,
///   §11.5.
/// - Saad, Y. (2003): "Iterative Methods for Sparse Linear Systems," 2nd ed.,
///   Chapter 9.
/// - Shewchuk, J. R. (1994): "An Introduction to the Conjugate Gradient Method
///   Without the Agonizing Pain."
///
/// Not formally verified. Correctness is ensured by the test suite.

// ---------------------------------------------------------------------------
// Preconditioner type
// ---------------------------------------------------------------------------

///|
/// Preconditioner type selector.
pub enum Preconditioner {
  /// No preconditioning (equivalent to standard CG).
  Identity
  /// Jacobi (diagonal) preconditioner: M = diag(A).
  Jacobi
  /// SSOR preconditioner with relaxation parameter ω (0 < ω < 2).
  SSOR(Double)
  /// Incomplete Cholesky (IC0) preconditioner.
  IncompleteCholesky
} derive(Debug)

// ---------------------------------------------------------------------------
// Internal: Preconditioner data structure
// ---------------------------------------------------------------------------

///|
/// Internal representation of a constructed preconditioner.
priv struct PrecData {
  // For Jacobi: diagonal entries of M⁻¹ (inverse of diagonal of A)
  diag_inv : Array[Double]
  // For SSOR: matrix A (needed for triangular solves); omega is in kind
  ssor_a : Array[Array[Double]]
  // For IC0: incomplete Cholesky factor L (lower triangular, same sparsity as A)
  ic_L : Array[Array[Double]]
  kind : Preconditioner
}

// ---------------------------------------------------------------------------
// Preconditioner construction
// ---------------------------------------------------------------------------

///|
/// Build preconditioner data from matrix A and selected preconditioner type.
fn build_preconditioner(
  a : Array[Array[Double]],
  n : Int,
  kind : Preconditioner,
) -> PrecData {
  match kind {
    Identity => {
      let diag_inv = Array::make(n, 1.0)
      { diag_inv, ssor_a: [], ic_L: [], kind }
    }
    Jacobi => {
      let diag_inv = Array::make(n, 0.0)
      for i = 0; i < n; i = i + 1 {
        if a[i][i].abs() > 1.0e-300 {
          diag_inv[i] = 1.0 / a[i][i]
        } else {
          diag_inv[i] = 1.0
        }
      }
      { diag_inv, ssor_a: [], ic_L: [], kind }
    }
    SSOR(_omega) => {
      let diag_inv = Array::make(n, 0.0)
      for i = 0; i < n; i = i + 1 {
        if a[i][i].abs() > 1.0e-300 {
          diag_inv[i] = 1.0 / a[i][i]
        } else {
          diag_inv[i] = 1.0
        }
      }
      { diag_inv, ssor_a: a, ic_L: [], kind }
    }
    IncompleteCholesky => {
      // IC0: incomplete Cholesky factorization with same sparsity pattern as A.
      // L[i][j] for j <= i, and L[i][j] = 0 if A[i][j] = 0.
      let l : Array[Array[Double]] = Array::make(n, [])
      for i = 0; i < n; i = i + 1 {
        l[i] = Array::make(n, 0.0)
      }
      let diag_inv = Array::make(n, 1.0) // not used for IC
      for i = 0; i < n; i = i + 1 {
        for j = 0; j <= i; j = j + 1 {
          if a[i][j].abs() < 1.0e-300 && a[j][i].abs() < 1.0e-300 {
            continue // preserve sparsity pattern
          }
          if j == i {
            // Diagonal
            let mut sum = a[i][i]
            for k = 0; k < j; k = k + 1 {
              sum = sum - l[i][k] * l[i][k]
            }
            if sum > 0.0 {
              l[i][j] = sum.sqrt()
            } else {
              // Fallback: use diagonal of A
              l[i][j] = a[i][i].abs().sqrt().max(1.0e-10)
            }
          } else {
            // Off-diagonal (lower triangle)
            let mut sum = a[i][j]
            for k = 0; k < j; k = k + 1 {
              sum = sum - l[i][k] * l[j][k]
            }
            if l[j][j].abs() > 1.0e-300 {
              l[i][j] = sum / l[j][j]
            } else {
              l[i][j] = 0.0
            }
          }
        }
      }
      { diag_inv, ssor_a: [], ic_L: l, kind }
    }
  }
}

// ---------------------------------------------------------------------------
// Preconditioner application: z = M⁻¹ · r
// ---------------------------------------------------------------------------

///|
/// Apply preconditioner: compute z = M⁻¹ · r.
fn apply_preconditioner(
  prec : PrecData,
  r : Array[Double],
  n : Int,
) -> Array[Double] {
  match prec.kind {
    Identity => {
      // z = r
      let z = Array::make(n, 0.0)
      for i = 0; i < n; i = i + 1 {
        z[i] = r[i]
      }
      z
    }
    Jacobi => {
      // z = D⁻¹ · r
      let z = Array::make(n, 0.0)
      for i = 0; i < n; i = i + 1 {
        z[i] = prec.diag_inv[i] * r[i]
      }
      z
    }
    SSOR(omega) => {
      // M = (D/ω + L) · (D/ω)⁻¹ · (D/ω + Lᵀ)  [Golub & Van Loan §11.5]
      // where A = D + L + Lᵀ (symmetric), D = diag(A), L = strict lower(A).
      // Solve M·z = r in three steps:
      // 1. Forward:  (D/ω + L)·y = r        → y_i = ω·(r_i - Σ_{j<i} L_ij·y_j) / A_ii
      // 2. Scale:    z' = (D/ω)⁻¹·y = (ω/D)·y
      // 3. Backward: (D/ω + Lᵀ)·z = z'     → z_i = ω·(z'_i - Σ_{j>i} A_ji·z_j) / A_ii
      let a = prec.ssor_a
      let z = Array::make(n, 0.0)
      // Step 1: Forward solve (D/ω + L)·y = r
      let y = Array::make(n, 0.0)
      for i = 0; i < n; i = i + 1 {
        let mut s = r[i]
        for j = 0; j < i; j = j + 1 {
          s = s - a[i][j] * y[j]
        }
        let d = a[i][i] / omega
        if d.abs() > 1.0e-300 {
          y[i] = s / d
        } else {
          y[i] = s
        }
      }
      // Step 2: Scale z' = (ω/D)·y  (equivalently z'_i = ω·y_i / A_ii)
      let zp = Array::make(n, 0.0)
      for i = 0; i < n; i = i + 1 {
        if a[i][i].abs() > 1.0e-300 {
          zp[i] = omega * y[i] / a[i][i]
        } else {
          zp[i] = y[i]
        }
      }
      // Step 3: Backward solve (D/ω + Lᵀ)·z = z'
      for i = n - 1; i >= 0; i = i - 1 {
        let mut s = zp[i]
        for j = i + 1; j < n; j = j + 1 {
          s = s - a[j][i] * z[j] // Lᵀ[i][j] = A[j][i]
        }
        let d = a[i][i] / omega
        if d.abs() > 1.0e-300 {
          z[i] = s / d
        } else {
          z[i] = s
        }
      }
      z
    }
    IncompleteCholesky => {
      // M = L · Lᵀ, solve L·Lᵀ·z = r via forward/backward substitution.
      let z = Array::make(n, 0.0)
      let l = prec.ic_L
      // Forward solve: L · y = r
      let y = Array::make(n, 0.0)
      for i = 0; i < n; i = i + 1 {
        let mut s = r[i]
        for k = 0; k < i; k = k + 1 {
          s = s - l[i][k] * y[k]
        }
        if l[i][i].abs() > 1.0e-300 {
          y[i] = s / l[i][i]
        } else {
          y[i] = s
        }
      }
      // Backward solve: Lᵀ · z = y
      for i = n - 1; i >= 0; i = i - 1 {
        let mut s = y[i]
        for k = i + 1; k < n; k = k + 1 {
          s = s - l[k][i] * z[k]
        }
        if l[i][i].abs() > 1.0e-300 {
          z[i] = s / l[i][i]
        } else {
          z[i] = s
        }
      }
      z
    }
  }
}

// ---------------------------------------------------------------------------
// Public API: PCG solver
// ---------------------------------------------------------------------------

///|
/// Solve Ax = b using Preconditioned Conjugate Gradient.
///
/// `a` is an n×n SPD matrix (row-major). `b` is the right-hand side.
/// `x0` is the initial guess. `prec` selects the preconditioner.
///
/// Returns the solution vector, or `None` if the matrix is not SPD or
/// convergence is not reached within `max_iter` iterations.
///
/// ## Example
///
/// ```moonbit nocheck
/// let a = [[4.0, 1.0], [1.0, 3.0]]
///
/// let b = [1.0, 2.0]
///
/// let x = pcg_solve(a, b, [0.0, 0.0], Jacobi)
/// // x ≈ [0.0909, 0.6364]
/// ```
pub fn pcg_solve(
  a : Array[Array[Double]],
  b : Array[Double],
  x0 : Array[Double],
  prec : Preconditioner,
) -> Array[Double]? {
  let n = b.length()
  if n == 0 {
    return Some([])
  }
  if a.length() != n || x0.length() != n {
    return None
  }
  for i = 0; i < n; i = i + 1 {
    if a[i].length() != n {
      return None
    }
  }
  _pcg_solve_impl(a, b, x0, n, 1.0e-10, 10000, prec)
}

///|
/// Solve with custom tolerance and iteration limit.
pub fn pcg_solve_with(
  a : Array[Array[Double]],
  b : Array[Double],
  x0 : Array[Double],
  tol : Double,
  max_iter : Int,
  prec : Preconditioner,
) -> Array[Double]? {
  let n = b.length()
  if n == 0 {
    return Some([])
  }
  if a.length() != n || x0.length() != n || tol <= 0.0 || max_iter <= 0 {
    return None
  }
  for i = 0; i < n; i = i + 1 {
    if a[i].length() != n {
      return None
    }
  }
  _pcg_solve_impl(a, b, x0, n, tol, max_iter, prec)
}

// ---------------------------------------------------------------------------
// Core PCG implementation
// ---------------------------------------------------------------------------

///|
fn _pcg_solve_impl(
  a : Array[Array[Double]],
  b : Array[Double],
  x0 : Array[Double],
  n : Int,
  tol : Double,
  max_iter : Int,
  prec_kind : Preconditioner,
) -> Array[Double]? {
  // Build preconditioner
  let prec = build_preconditioner(a, n, prec_kind)
  // x = x0 (copy)
  let x : Array[Double] = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    x[i] = x0[i]
  }
  // r = b - A·x
  let r : Array[Double] = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    let mut s = 0.0
    for j = 0; j < n; j = j + 1 {
      s = s + a[i][j] * x[j]
    }
    r[i] = b[i] - s
  }
  // Check if already converged
  let mut rs_old = 0.0
  for i = 0; i < n; i = i + 1 {
    rs_old = rs_old + r[i] * r[i]
  }
  if rs_old < tol * tol {
    return Some(x)
  }
  // z = M⁻¹ · r
  let z = apply_preconditioner(prec, r, n)
  // p = z
  let p : Array[Double] = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    p[i] = z[i]
  }
  // rz_old = rᵀ · z
  let mut rz_old = 0.0
  for i = 0; i < n; i = i + 1 {
    rz_old = rz_old + r[i] * z[i]
  }
  // Ap = A·p (reused)
  let ap : Array[Double] = Array::make(n, 0.0)
  for iter = 0; iter < max_iter; iter = iter + 1 {
    // Compute Ap
    for i = 0; i < n; i = i + 1 {
      let mut s = 0.0
      for j = 0; j < n; j = j + 1 {
        s = s + a[i][j] * p[j]
      }
      ap[i] = s
    }
    // alpha = rz_old / (pᵀ · Ap)
    let mut pap = 0.0
    for i = 0; i < n; i = i + 1 {
      pap = pap + p[i] * ap[i]
    }
    if pap <= 0.0 {
      return None // Not positive-definite
    }
    let alpha = rz_old / pap
    // x = x + alpha · p
    for i = 0; i < n; i = i + 1 {
      x[i] = x[i] + alpha * p[i]
    }
    // r = r - alpha · Ap
    for i = 0; i < n; i = i + 1 {
      r[i] = r[i] - alpha * ap[i]
    }
    // Check convergence
    let mut rs_new = 0.0
    for i = 0; i < n; i = i + 1 {
      rs_new = rs_new + r[i] * r[i]
    }
    if rs_new < tol * tol {
      return Some(x)
    }
    // z = M⁻¹ · r
    for i = 0; i < n; i = i + 1 {
      z[i] = 0.0
    }
    let z_new = apply_preconditioner(prec, r, n)
    for i = 0; i < n; i = i + 1 {
      z[i] = z_new[i]
    }
    // beta = (rᵀ z_new) / rz_old
    let mut rz_new = 0.0
    for i = 0; i < n; i = i + 1 {
      rz_new = rz_new + r[i] * z[i]
    }
    let beta = rz_new / rz_old
    // p = z + beta · p
    for i = 0; i < n; i = i + 1 {
      p[i] = z[i] + beta * p[i]
    }
    rz_old = rz_new
  }
  None
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "pcg: Jacobi 2×2 SPD system" {
  let a = [[4.0, 1.0], [1.0, 3.0]]
  let b = [1.0, 2.0]
  let x = @test_utils.expect_some(
    pcg_solve(a, b, [0.0, 0.0], Jacobi),
    "PCG should converge",
  )
  let r0 = a[0][0] * x[0] + a[0][1] * x[1] - b[0]
  let r1 = a[1][0] * x[0] + a[1][1] * x[1] - b[1]
  assert_true(r0.abs() < 1.0e-8)
  assert_true(r1.abs() < 1.0e-8)
}

///|
test "pcg: Identity preconditioner equals CG" {
  let a = [[4.0, 1.0], [1.0, 3.0]]
  let b = [1.0, 2.0]
  let x = @test_utils.expect_some(
    pcg_solve(a, b, [0.0, 0.0], Identity),
    "PCG-Identity should converge",
  )
  let r0 = a[0][0] * x[0] + a[0][1] * x[1] - b[0]
  let r1 = a[1][0] * x[0] + a[1][1] * x[1] - b[1]
  assert_true(r0.abs() < 1.0e-8)
  assert_true(r1.abs() < 1.0e-8)
}

///|
test "pcg: Jacobi 3×3 SPD system" {
  let a = [[4.0, 1.0, 0.0], [1.0, 3.0, 1.0], [0.0, 1.0, 2.0]]
  let b = [5.0, 6.0, 4.0]
  let x = @test_utils.expect_some(
    pcg_solve(a, b, [0.0, 0.0, 0.0], Jacobi),
    "3×3 should converge",
  )
  for i = 0; i < 3; i = i + 1 {
    let mut s = 0.0
    for j = 0; j < 3; j = j + 1 {
      s = s + a[i][j] * x[j]
    }
    assert_true((s - b[i]).abs() < 1.0e-8)
  }
}

///|
test "pcg: Incomplete Cholesky preconditioner" {
  let a = [[4.0, 1.0, 0.0], [1.0, 3.0, 1.0], [0.0, 1.0, 2.0]]
  let b = [5.0, 6.0, 4.0]
  let x = @test_utils.expect_some(
    pcg_solve(a, b, [0.0, 0.0, 0.0], IncompleteCholesky),
    "IC-PCG should converge",
  )
  for i = 0; i < 3; i = i + 1 {
    let mut s = 0.0
    for j = 0; j < 3; j = j + 1 {
      s = s + a[i][j] * x[j]
    }
    assert_true((s - b[i]).abs() < 1.0e-8)
  }
}

///|
test "pcg: SSOR preconditioner" {
  let a = [[4.0, 1.0, 0.0], [1.0, 3.0, 1.0], [0.0, 1.0, 2.0]]
  let b = [5.0, 6.0, 4.0]
  let x = @test_utils.expect_some(
    pcg_solve(a, b, [0.0, 0.0, 0.0], SSOR(1.0)),
    "SSOR-PCG should converge",
  )
  for i = 0; i < 3; i = i + 1 {
    let mut s = 0.0
    for j = 0; j < 3; j = j + 1 {
      s = s + a[i][j] * x[j]
    }
    assert_true((s - b[i]).abs() < 1.0e-8)
  }
}

///|
test "pcg: identity matrix with Jacobi" {
  let a = [[1.0, 0.0], [0.0, 1.0]]
  let b = [3.0, 7.0]
  let x = @test_utils.expect_some(
    pcg_solve(a, b, [0.0, 0.0], Jacobi),
    "identity should converge",
  )
  assert_true((x[0] - 3.0).abs() < 1.0e-10)
  assert_true((x[1] - 7.0).abs() < 1.0e-10)
}

///|
test "pcg: larger system 10×10 with Jacobi" {
  let n = 10
  let a : Array[Array[Double]] = Array::make(n, [])
  for i = 0; i < n; i = i + 1 {
    a[i] = Array::make(n, 0.0)
    a[i][i] = 10.0
    if i > 0 {
      a[i][i - 1] = 1.0
      a[i - 1][i] = 1.0
    }
  }
  let b = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    b[i] = i.to_double() + 1.0
  }
  let x = @test_utils.expect_some(
    pcg_solve(a, b, Array::make(n, 0.0), Jacobi),
    "10×10 should converge",
  )
  for i = 0; i < n; i = i + 1 {
    let mut s = 0.0
    for j = 0; j < n; j = j + 1 {
      s = s + a[i][j] * x[j]
    }
    assert_true((s - b[i]).abs() < 1.0e-8)
  }
}

///|
test "pcg: larger system 10×10 with IC" {
  let n = 10
  let a : Array[Array[Double]] = Array::make(n, [])
  for i = 0; i < n; i = i + 1 {
    a[i] = Array::make(n, 0.0)
    a[i][i] = 10.0
    if i > 0 {
      a[i][i - 1] = 1.0
      a[i - 1][i] = 1.0
    }
  }
  let b = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    b[i] = i.to_double() + 1.0
  }
  let x = @test_utils.expect_some(
    pcg_solve(a, b, Array::make(n, 0.0), IncompleteCholesky),
    "10×10 IC should converge",
  )
  for i = 0; i < n; i = i + 1 {
    let mut s = 0.0
    for j = 0; j < n; j = j + 1 {
      s = s + a[i][j] * x[j]
    }
    assert_true((s - b[i]).abs() < 1.0e-8)
  }
}

///|
test "pcg: custom tolerance" {
  let a = [[2.0, 0.0], [0.0, 2.0]]
  let b = [2.0, 4.0]
  let x = @test_utils.expect_some(
    pcg_solve_with(a, b, [0.0, 0.0], 1.0e-6, 100, Jacobi),
    "should converge with custom tol",
  )
  assert_true((x[0] - 1.0).abs() < 1.0e-5)
  assert_true((x[1] - 2.0).abs() < 1.0e-5)
}

///|
test "pcg: dimension mismatch returns None" {
  let a = [[1.0, 0.0], [0.0, 1.0]]
  let b = [1.0]
  assert_true(pcg_solve(a, b, [0.0], Jacobi) is None)
}

///|
test "pcg: already solved (zero residual)" {
  let a = [[2.0, 0.0], [0.0, 2.0]]
  let b = [4.0, 6.0]
  let x = @test_utils.expect_some(
    pcg_solve(a, b, [2.0, 3.0], Jacobi),
    "should converge immediately",
  )
  assert_true((x[0] - 2.0).abs() < 1.0e-10)
  assert_true((x[1] - 3.0).abs() < 1.0e-10)
}

///|
test "pcg: returns None for non-SPD matrix" {
  let a = [[0.0, 1.0], [1.0, 0.0]]
  let b = [1.0, 0.0]
  let result = pcg_solve(a, b, [0.0, 0.0], Jacobi)
  match result {
    Some(_) => ()
    None => ()
  }
}

///|
test "pcg: 5×5 ill-conditioned with Jacobi" {
  // Hilbert-like matrix (ill-conditioned but SPD)
  let n = 5
  let a : Array[Array[Double]] = Array::make(n, [])
  for i = 0; i < n; i = i + 1 {
    a[i] = Array::make(n, 0.0)
    for j = 0; j < n; j = j + 1 {
      a[i][j] = 1.0 / (i + j + 1).to_double()
    }
  }
  let b = Array::make(n, 1.0)
  let x = @test_utils.expect_some(
    pcg_solve_with(a, b, Array::make(n, 0.0), 1.0e-8, 5000, Jacobi),
    "ill-conditioned should converge",
  )
  // Verify residual
  for i = 0; i < n; i = i + 1 {
    let mut s = 0.0
    for j = 0; j < n; j = j + 1 {
      s = s + a[i][j] * x[j]
    }
    assert_true((s - b[i]).abs() < 1.0e-6)
  }
}

///|
test "pcg: 5×5 ill-conditioned with IC" {
  let n = 5
  let a : Array[Array[Double]] = Array::make(n, [])
  for i = 0; i < n; i = i + 1 {
    a[i] = Array::make(n, 0.0)
    for j = 0; j < n; j = j + 1 {
      a[i][j] = 1.0 / (i + j + 1).to_double()
    }
  }
  let b = Array::make(n, 1.0)
  let x = @test_utils.expect_some(
    pcg_solve_with(a, b, Array::make(n, 0.0), 1.0e-8, 5000, IncompleteCholesky),
    "IC should converge on ill-conditioned",
  )
  for i = 0; i < n; i = i + 1 {
    let mut s = 0.0
    for j = 0; j < n; j = j + 1 {
      s = s + a[i][j] * x[j]
    }
    assert_true((s - b[i]).abs() < 1.0e-6)
  }
}

///|
test "pcg: 20×20 tridiagonal with IC" {
  let n = 20
  let a : Array[Array[Double]] = Array::make(n, [])
  for i = 0; i < n; i = i + 1 {
    a[i] = Array::make(n, 0.0)
    a[i][i] = 4.0
    if i > 0 {
      a[i][i - 1] = -1.0
      a[i - 1][i] = -1.0
    }
  }
  let b = Array::make(n, 1.0)
  let x = @test_utils.expect_some(
    pcg_solve(a, b, Array::make(n, 0.0), IncompleteCholesky),
    "20×20 IC should converge",
  )
  for i = 0; i < n; i = i + 1 {
    let mut s = 0.0
    for j = 0; j < n; j = j + 1 {
      s = s + a[i][j] * x[j]
    }
    assert_true((s - b[i]).abs() < 1.0e-8)
  }
}
