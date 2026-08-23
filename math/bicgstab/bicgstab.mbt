/// BiCGSTAB — Biconjugate Gradient Stabilized Method.
///
/// Solves Ax = b for general (non-symmetric, non-Hermitian) n×n matrices.
/// Unlike CG which requires SPD matrices, BiCGSTAB works for arbitrary
/// nonsingular matrices with suitable spectral properties.
///
/// ## Algorithm (van der Vorst 1992)
///
/// ```text
/// x₀ = initial guess
/// r₀ = b - A·x₀
/// r̂₀ = r₀  (arbitrary, typically r₀)
/// ρ₀ = α = ω₀ = 1
/// v₀ = p₀ = 0
/// for k = 1, 2, …:
///   ρₖ = r̂₀ᵀ · rₖ
///   β = (ρₖ / ρₖ₋₁) · (α / ωₖ₋₁)
///   pₖ = rₖ + β · (pₖ₋₁ - ωₖ₋₁ · vₖ₋₁)
///   vₖ = A · pₖ
///   α = ρₖ / (r̂₀ᵀ · vₖ)
///   s = rₖ - α · vₖ
///   if ‖s‖ < tol: x = xₖ₋₁ + α · pₖ; stop
///   t = A · s
///   ωₖ = (tᵀ · s) / (tᵀ · t)
///   xₖ = xₖ₋₁ + α · pₖ + ωₖ · s
///   rₖ₊₁ = s - ωₖ · t
///   if ‖rₖ₊₁‖ < tol: stop
/// ```
///
/// ## Properties
///
/// - **General matrices**: Works for non-symmetric, non-Hermitian systems.
/// - **Smooth convergence**: More stable than BiCG (which can have erratic
///   convergence due to the squared residual polynomial).
/// - **Two matvecs per iteration**: One for A·p, one for A·s.
/// - **Breakdown conditions**: Fails when ρₖ ≈ 0 (r̂₀ ⊥ rₖ) or ωₖ ≈ 0
///   (t ⊥ s). These indicate the algorithm cannot make further progress.
/// - **Superlinear convergence**: Common for matrices with clustered eigenvalues.
///
/// ## Complexity
///
/// - Per iteration: O(n²) for dense, O(nnz) for sparse (2 matvecs).
/// - Storage: 7 vectors of length n (r, r̂, p, v, s, t, x) = O(n).
/// - Convergence: Generally O(√κ) for well-conditioned systems, but no
///   tight theoretical bound for non-symmetric matrices.
///
/// ## References
///
/// - van der Vorst, H. A. (1992): "Bi-CGSTAB: A Fast and Smoothly Converging
///   Variant of Bi-CG for the Solution of Nonsymmetric Linear Systems."
///   SIAM J. Sci. Stat. Comput., 13(2), 631–644.
/// - Saad, Y. (2003): "Iterative Methods for Sparse Linear Systems," 2nd ed.,
///   §7.4.2.
///
/// Not formally verified. Correctness is ensured by the test suite.

// ---------------------------------------------------------------------------
// Default parameters
// ---------------------------------------------------------------------------

///|
/// Default tolerance for convergence.
let default_tol : Double = 1.0e-10

///|
/// Default maximum iterations.
let default_max_iter : Int = 10000

// ---------------------------------------------------------------------------
// Vector operations (inline for clarity)
// ---------------------------------------------------------------------------

///|
/// Dot product of two vectors.
fn dot(a : Array[Double], b : Array[Double], n : Int) -> Double {
  let mut s = 0.0
  for i = 0; i < n; i = i + 1 {
    s = s + a[i] * b[i]
  }
  s
}

///|
/// Matrix-vector product: result = A · x.
fn matvec(
  a : Array[Array[Double]],
  x : Array[Double],
  result : Array[Double],
  n : Int,
) -> Unit {
  for i = 0; i < n; i = i + 1 {
    let mut s = 0.0
    for j = 0; j < n; j = j + 1 {
      s = s + a[i][j] * x[j]
    }
    result[i] = s
  }
}

///|
/// 2-norm squared of a vector.
fn norm_sq(v : Array[Double], n : Int) -> Double {
  dot(v, v, n)
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

///|
/// Solve Ax = b using the BiCGSTAB method.
///
/// `a` is an n×n matrix (row-major). `b` is the right-hand side.
/// `x0` is the initial guess (use `Array::make(n, 0.0)` for zero initial guess).
///
/// Returns the solution vector, or `None` if convergence is not reached
/// within `max_iter` iterations or a breakdown occurs.
///
/// ## Example
///
/// ```moonbit nocheck
/// let a = [[4.0, 1.0], [1.0, 3.0]]
///
/// let b = [1.0, 2.0]
///
/// let x = bicgstab_solve(a, b, [0.0, 0.0])
/// // x ≈ [0.0909, 0.6364]
/// ```
pub fn bicgstab_solve(
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
  _bicgstab_impl(a, b, x0, n, default_tol, default_max_iter)
}

///|
/// Solve with custom tolerance and iteration limit.
pub fn bicgstab_solve_with(
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
  _bicgstab_impl(a, b, x0, n, tol, max_iter)
}

// ---------------------------------------------------------------------------
// Core BiCGSTAB implementation
// ---------------------------------------------------------------------------

///|
fn _bicgstab_impl(
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
  let tmp : Array[Double] = Array::make(n, 0.0)
  matvec(a, x, tmp, n)
  for i = 0; i < n; i = i + 1 {
    r[i] = b[i] - tmp[i]
  }
  // Check if already converged
  let r_norm_sq = norm_sq(r, n)
  if r_norm_sq < tol * tol {
    return Some(x)
  }
  // r̂ = r (shadow residual)
  let r_hat : Array[Double] = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    r_hat[i] = r[i]
  }
  // Initial values
  let mut rho = 1.0
  let mut alpha = 1.0
  let mut omega = 1.0
  // p = 0, v = 0
  let p : Array[Double] = Array::make(n, 0.0)
  let v : Array[Double] = Array::make(n, 0.0)
  // Working vectors
  let s : Array[Double] = Array::make(n, 0.0)
  let t : Array[Double] = Array::make(n, 0.0)
  let tol_sq = tol * tol
  for iter = 0; iter < max_iter; iter = iter + 1 {
    // rho_new = r̂ᵀ · r
    let rho_new = dot(r_hat, r, n)
    // Check for breakdown: rho ≈ 0
    if rho_new.abs() < 1.0e-300 {
      return None
    }
    // beta = (rho_new / rho) * (alpha / omega)
    let beta = rho_new / rho * (alpha / omega)
    // p = r + beta * (p - omega * v)
    for i = 0; i < n; i = i + 1 {
      p[i] = r[i] + beta * (p[i] - omega * v[i])
    }
    // v = A · p
    matvec(a, p, v, n)
    // alpha = rho_new / (r̂ᵀ · v)
    let r_hat_dot_v = dot(r_hat, v, n)
    if r_hat_dot_v.abs() < 1.0e-300 {
      return None // Breakdown
    }
    alpha = rho_new / r_hat_dot_v
    // s = r - alpha * v
    for i = 0; i < n; i = i + 1 {
      s[i] = r[i] - alpha * v[i]
    }
    // Check early convergence: ‖s‖ < tol
    let s_norm_sq = norm_sq(s, n)
    if s_norm_sq < tol_sq {
      // x = x + alpha * p
      for i = 0; i < n; i = i + 1 {
        x[i] = x[i] + alpha * p[i]
      }
      return Some(x)
    }
    // t = A · s
    matvec(a, s, t, n)
    // omega = (tᵀ · s) / (tᵀ · t)
    let t_dot_s = dot(t, s, n)
    let t_dot_t = dot(t, t, n)
    if t_dot_t.abs() < 1.0e-300 {
      return None // Breakdown
    }
    omega = t_dot_s / t_dot_t
    // x = x + alpha * p + omega * s
    for i = 0; i < n; i = i + 1 {
      x[i] = x[i] + alpha * p[i] + omega * s[i]
    }
    // r = s - omega * t
    for i = 0; i < n; i = i + 1 {
      r[i] = s[i] - omega * t[i]
    }
    // Check convergence
    let r_new_norm_sq = norm_sq(r, n)
    if r_new_norm_sq < tol_sq {
      return Some(x)
    }
    // Check for omega breakdown
    if omega.abs() < 1.0e-300 {
      return None
    }
    rho = rho_new
  }
  // Did not converge
  None
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "bicgstab: solve 2×2 SPD system" {
  let a = [[4.0, 1.0], [1.0, 3.0]]
  let b = [1.0, 2.0]
  let x = @test_utils.expect_some(
    bicgstab_solve(a, b, [0.0, 0.0]),
    "should converge",
  )
  let r0 = a[0][0] * x[0] + a[0][1] * x[1] - b[0]
  let r1 = a[1][0] * x[0] + a[1][1] * x[1] - b[1]
  assert_true(r0.abs() < 1.0e-8)
  assert_true(r1.abs() < 1.0e-8)
}

///|
test "bicgstab: solve 3×3 SPD system" {
  let a = [[4.0, 1.0, 0.0], [1.0, 3.0, 1.0], [0.0, 1.0, 2.0]]
  let b = [5.0, 6.0, 4.0]
  let x = @test_utils.expect_some(
    bicgstab_solve(a, b, [0.0, 0.0, 0.0]),
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
test "bicgstab: solve non-symmetric system" {
  // Non-symmetric matrix
  let a = [[1.0, 2.0, 0.0], [0.0, 1.0, 2.0], [2.0, 0.0, 1.0]]
  let b = [5.0, 5.0, 5.0]
  let x = @test_utils.expect_some(
    bicgstab_solve(a, b, [0.0, 0.0, 0.0]),
    "non-symmetric should converge",
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
test "bicgstab: identity matrix" {
  let a = [[1.0, 0.0], [0.0, 1.0]]
  let b = [3.0, 7.0]
  let x = @test_utils.expect_some(
    bicgstab_solve(a, b, [0.0, 0.0]),
    "identity should converge",
  )
  assert_true((x[0] - 3.0).abs() < 1.0e-10)
  assert_true((x[1] - 7.0).abs() < 1.0e-10)
}

///|
test "bicgstab: diagonal matrix" {
  let a = [[5.0, 0.0], [0.0, 3.0]]
  let b = [10.0, 9.0]
  let x = @test_utils.expect_some(
    bicgstab_solve(a, b, [0.0, 0.0]),
    "diagonal should converge",
  )
  assert_true((x[0] - 2.0).abs() < 1.0e-10)
  assert_true((x[1] - 3.0).abs() < 1.0e-10)
}

///|
test "bicgstab: 10×10 tridiagonal" {
  let n = 10
  let a : Array[Array[Double]] = Array::make(n, [])
  for i = 0; i < n; i = i + 1 {
    a[i] = Array::make(n, 0.0)
    a[i][i] = 4.0
    if i > 0 {
      a[i][i - 1] = -1.0
      a[i - 1][i] = -1.0
    }
  }
  let b = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    b[i] = i.to_double() + 1.0
  }
  let x = @test_utils.expect_some(
    bicgstab_solve(a, b, Array::make(n, 0.0)),
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
test "bicgstab: 10×10 non-symmetric" {
  let n = 10
  let a : Array[Array[Double]] = Array::make(n, [])
  for i = 0; i < n; i = i + 1 {
    a[i] = Array::make(n, 0.0)
    a[i][i] = 3.0
    if i > 0 {
      a[i][i - 1] = 0.5 // Lower: non-symmetric (upper would be -0.5)
    }
    if i < n - 1 {
      a[i][i + 1] = -1.0 // Upper: different magnitude
    }
  }
  let b = Array::make(n, 1.0)
  let x = @test_utils.expect_some(
    bicgstab_solve(a, b, Array::make(n, 0.0)),
    "non-symmetric 10×10 should converge",
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
test "bicgstab: custom tolerance" {
  let a = [[2.0, 0.0], [0.0, 2.0]]
  let b = [2.0, 4.0]
  let x = @test_utils.expect_some(
    bicgstab_solve_with(a, b, [0.0, 0.0], 1.0e-6, 100),
    "should converge with custom tol",
  )
  assert_true((x[0] - 1.0).abs() < 1.0e-5)
  assert_true((x[1] - 2.0).abs() < 1.0e-5)
}

///|
test "bicgstab: dimension mismatch returns None" {
  let a = [[1.0, 0.0], [0.0, 1.0]]
  let b = [1.0]
  assert_true(bicgstab_solve(a, b, [0.0]) is None)
}

///|
test "bicgstab: already solved (zero residual)" {
  let a = [[2.0, 0.0], [0.0, 2.0]]
  let b = [4.0, 6.0]
  let x = @test_utils.expect_some(
    bicgstab_solve(a, b, [2.0, 3.0]),
    "should converge immediately",
  )
  assert_true((x[0] - 2.0).abs() < 1.0e-10)
  assert_true((x[1] - 3.0).abs() < 1.0e-10)
}

///|
test "bicgstab: non-symmetric 4×4 with complex spectrum" {
  // Matrix from Saad's book (non-symmetric, complex eigenvalues)
  let a = [
    [4.0, -1.0, 0.0, 0.0],
    [-1.0, 4.0, -1.0, 0.0],
    [0.0, -1.0, 4.0, -1.0],
    [0.0, 0.0, -1.0, 4.0],
  ]
  let b = [3.0, 2.0, 2.0, 3.0]
  let x = @test_utils.expect_some(
    bicgstab_solve(a, b, [0.0, 0.0, 0.0, 0.0]),
    "4×4 should converge",
  )
  for i = 0; i < 4; i = i + 1 {
    let mut s = 0.0
    for j = 0; j < 4; j = j + 1 {
      s = s + a[i][j] * x[j]
    }
    assert_true((s - b[i]).abs() < 1.0e-8)
  }
}

///|
test "bicgstab: 20×20 non-symmetric system" {
  let n = 20
  let a : Array[Array[Double]] = Array::make(n, [])
  for i = 0; i < n; i = i + 1 {
    a[i] = Array::make(n, 0.0)
    a[i][i] = 4.0
    if i > 0 {
      a[i][i - 1] = -0.5
    }
    if i < n - 1 {
      a[i][i + 1] = -1.0
    }
  }
  let b = Array::make(n, 1.0)
  let x = @test_utils.expect_some(
    bicgstab_solve(a, b, Array::make(n, 0.0)),
    "20×20 non-symmetric should converge",
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
test "bicgstab: 5×5 Hilbert matrix" {
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
    bicgstab_solve_with(a, b, Array::make(n, 0.0), 1.0e-8, 5000),
    "Hilbert should converge",
  )
  for i = 0; i < n; i = i + 1 {
    let mut s = 0.0
    for j = 0; j < n; j = j + 1 {
      s = s + a[i][j] * x[j]
    }
    assert_true((s - b[i]).abs() < 1.0e-6)
  }
}
