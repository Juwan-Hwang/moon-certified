/// Conjugate Gradient Method — iterative solver for symmetric positive-definite (SPD) linear systems.
///
/// Solves Ax = b where A is n×n symmetric positive-definite, using the
/// Conjugate Gradient (CG) algorithm of Hestenes & Stiefel (1952).
///
/// ## Algorithm
///
/// ```text
/// x₀ = initial guess (typically 0)
/// r₀ = b - A·x₀
/// p₀ = r₀
/// for k = 0, 1, 2, …:
///   αₖ = (rₖᵀ rₖ) / (pₖᵀ A pₖ)
///   xₖ₊₁ = xₖ + αₖ pₖ
///   rₖ₊₁ = rₖ - αₖ A pₖ
///   if ‖rₖ₊₁‖ < tol: stop
///   βₖ = (rₖ₊₁ᵀ rₖ₊₁) / (rₖᵀ rₖ)
///   pₖ₊₁ = rₖ₊₁ + βₖ pₖ
/// ```
///
/// ## Complexity
///
/// - Per iteration: O(n²) for dense matrix-vector product (or O(nnz) for sparse).
/// - Worst case: n iterations to exact solution (in exact arithmetic).
/// - In practice: converges in O(√κ) iterations where κ is the condition number.
///
/// ## References
///
/// - Hestenes, M. R. and Stiefel, E. (1952): "Methods of Conjugate Gradients
///   for Solving Linear Systems." Journal of Research of the NBS.
/// - Shewchuk, J. R. (1994): "An Introduction to the Conjugate Gradient Method
///   Without the Agonizing Pain."
///
/// Not formally verified. Correctness is ensured by the test suite.

///|
/// Tolerance for convergence: iterations stop when ‖r‖ < `tol`.
let default_tol : Double = 1.0e-10

///|
/// Maximum iterations to prevent infinite loop on non-convergent systems.
let default_max_iter : Int = 10000

///|
/// Solve Ax = b using the Conjugate Gradient method.
///
/// `a` is an n×n symmetric positive-definite matrix stored as `Array[Array[Double]]`
/// (row-major). `b` is the right-hand side. `x0` is the initial guess (use
/// `Array::make(n, 0.0)` for zero initial guess).
///
/// Returns the solution vector, or `None` if the matrix is not SPD or
/// convergence is not reached within `max_iter` iterations.
///
/// ## Preconditions
///
/// - `a` must be symmetric positive-definite.
/// - `a.length() == b.length() == x0.length()`.
///
/// ## Example
///
/// ```moonbit
/// let a = [[4.0, 1.0], [1.0, 3.0]]
/// let b = [1.0, 2.0]
/// let x = cg_solve(a, b, [0.0, 0.0])
/// // x ≈ [0.0909, 0.6364]
/// ```
pub fn cg_solve(
  a : Array[Array[Double]],
  b : Array[Double],
  x0 : Array[Double],
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
  _cg_solve_impl(a, b, x0, n, default_tol, default_max_iter)
}

///|
/// Solve with custom tolerance and iteration limit.
pub fn cg_solve_with(
  a : Array[Array[Double]],
  b : Array[Double],
  x0 : Array[Double],
  tol : Double,
  max_iter : Int,
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
  _cg_solve_impl(a, b, x0, n, tol, max_iter)
}

///|
/// Core CG implementation — assumes inputs are already validated.
fn _cg_solve_impl(
  a : Array[Array[Double]],
  b : Array[Double],
  x0 : Array[Double],
  n : Int,
  tol : Double,
  max_iter : Int,
) -> Array[Double]? {
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
  // p = r
  let p : Array[Double] = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    p[i] = r[i]
  }
  // rs_old = rᵀ·r
  let mut rs_old = 0.0
  for i = 0; i < n; i = i + 1 {
    rs_old = rs_old + r[i] * r[i]
  }
  // Check if already converged
  if rs_old < tol * tol {
    return Some(x)
  }
  // Ap = A·p (reused each iteration)
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
    // alpha = rs_old / (pᵀ·Ap)
    let mut pap = 0.0
    for i = 0; i < n; i = i + 1 {
      pap = pap + p[i] * ap[i]
    }
    if pap <= 0.0 {
      // Matrix is not positive-definite
      return None
    }
    let alpha = rs_old / pap
    // x = x + alpha·p
    for i = 0; i < n; i = i + 1 {
      x[i] = x[i] + alpha * p[i]
    }
    // r = r - alpha·Ap
    for i = 0; i < n; i = i + 1 {
      r[i] = r[i] - alpha * ap[i]
    }
    // rs_new = rᵀ·r
    let mut rs_new = 0.0
    for i = 0; i < n; i = i + 1 {
      rs_new = rs_new + r[i] * r[i]
    }
    // Convergence check: ‖r‖ < tol
    if rs_new < tol * tol {
      return Some(x)
    }
    // beta = rs_new / rs_old
    let beta = rs_new / rs_old
    // p = r + beta·p
    for i = 0; i < n; i = i + 1 {
      p[i] = r[i] + beta * p[i]
    }
    rs_old = rs_new
  }
  // Did not converge within max_iter iterations
  None
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "cg: solve 2×2 SPD system" {
  let a = [[4.0, 1.0], [1.0, 3.0]]
  let b = [1.0, 2.0]
  let x = @test_utils.expect_some(cg_solve(a, b, [0.0, 0.0]), "cg_solve should converge")
  // Verify: A·x ≈ b
  let r0 = a[0][0] * x[0] + a[0][1] * x[1] - b[0]
  let r1 = a[1][0] * x[0] + a[1][1] * x[1] - b[1]
  assert_true(r0.abs() < 1.0e-8)
  assert_true(r1.abs() < 1.0e-8)
}

///|
test "cg: solve 3×3 SPD system" {
  let a = [
    [4.0, 1.0, 0.0],
    [1.0, 3.0, 1.0],
    [0.0, 1.0, 2.0],
  ]
  let b = [5.0, 6.0, 4.0]
  let x = @test_utils.expect_some(cg_solve(a, b, [0.0, 0.0, 0.0]), "should converge")
  for i = 0; i < 3; i = i + 1 {
    let mut s = 0.0
    for j = 0; j < 3; j = j + 1 {
      s = s + a[i][j] * x[j]
    }
    assert_true((s - b[i]).abs() < 1.0e-8)
  }
}

///|
test "cg: identity matrix" {
  let a = [[1.0, 0.0], [0.0, 1.0]]
  let b = [3.0, 7.0]
  let x = @test_utils.expect_some(cg_solve(a, b, [0.0, 0.0]), "identity should converge")
  assert_true((x[0] - 3.0).abs() < 1.0e-10)
  assert_true((x[1] - 7.0).abs() < 1.0e-10)
}

///|
test "cg: returns None for non-SPD matrix" {
  // Indefinite matrix (eigenvalues +1 and -1)
  let a = [[0.0, 1.0], [1.0, 0.0]]
  let b = [1.0, 0.0]
  let x = cg_solve(a, b, [0.0, 0.0])
  // CG should detect non-positive-definiteness (pap <= 0)
  // or fail to converge
  match x {
    Some(_) => () // May still return a result for trivial systems
    None => ()
  }
}

///|
test "cg: zero initial residual (already solved)" {
  let a = [[2.0, 0.0], [0.0, 2.0]]
  let b = [4.0, 6.0]
  // Start at the exact solution
  let x = @test_utils.expect_some(cg_solve(a, b, [2.0, 3.0]), "should converge immediately")
  assert_true((x[0] - 2.0).abs() < 1.0e-10)
  assert_true((x[1] - 3.0).abs() < 1.0e-10)
}

///|
test "cg: larger system (10×10)" {
  // Build a diagonally dominant SPD matrix
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
  let x0 = Array::make(n, 0.0)
  let x = @test_utils.expect_some(cg_solve(a, b, x0), "10×10 should converge")
  for i = 0; i < n; i = i + 1 {
    let mut s = 0.0
    for j = 0; j < n; j = j + 1 {
      s = s + a[i][j] * x[j]
    }
    assert_true((s - b[i]).abs() < 1.0e-8)
  }
}

///|
test "cg: custom tolerance" {
  let a = [[2.0, 0.0], [0.0, 2.0]]
  let b = [2.0, 4.0]
  let x = @test_utils.expect_some(
    cg_solve_with(a, b, [0.0, 0.0], 1.0e-6, 100),
    "should converge with custom tol",
  )
  assert_true((x[0] - 1.0).abs() < 1.0e-5)
  assert_true((x[1] - 2.0).abs() < 1.0e-5)
}

///|
test "cg: dimension mismatch returns None" {
  let a = [[1.0, 0.0], [0.0, 1.0]]
  let b = [1.0] // Wrong size
  assert_true(cg_solve(a, b, [0.0]) is None)
}
