/// GMRES — Generalized Minimal RESidual method for non-symmetric linear systems.
///
/// Solves Ax = b for general (non-symmetric, non-SPD) square matrices using
/// the Arnoldi iteration to build an orthonormal Krylov subspace and minimize
/// the residual over that subspace.
///
/// ## Algorithm
///
/// ```text
/// r₀ = b - A·x₀
/// β = ‖r₀‖
/// v₁ = r₀ / β
/// for j = 0, 1, …, m-1:
///   w = A·vⱼ₊₁
///   for i = 0, …, j:           (Modified Gram-Schmidt)
///     hᵢⱼ = wᵀ·vᵢ₊₁
///     w = w - hᵢⱼ·vᵢ₊₁
///   hⱼ₊₁ⱼ = ‖w‖
///   vⱼ₊₂ = w / hⱼ₊₁ⱼ
///   Solve least-squares: min ‖β·e₁ - H̄ⱼ·yⱼ‖  (via Givens rotations)
///   if residual < tol: x = x₀ + Vⱼ·yⱼ; stop
/// ```
///
/// ## Complexity
///
/// - Per restart cycle: O(m²·n + m·n²) where m = restart parameter, n = dimension.
/// - Memory: O(m·n) for the Krylov basis.
///
/// ## References
///
/// - Saad, Y. and Schultz, M. H. (1986): "GMRES: A Generalized Minimal
///   Residual Algorithm for Solving Nonsymmetric Linear Systems."
///   SIAM J. Sci. Stat. Comput.
/// - Saad, Y. (2003): "Iterative Methods for Sparse Linear Systems," 2nd ed.
///
/// Not formally verified. Correctness is ensured by the test suite.

///|
/// Default convergence tolerance.
let default_tol : Double = 1.0e-10

///|
/// Default maximum outer iterations (restart cycles).
let default_max_iter : Int = 100

///|
/// Default restart parameter (Krylov subspace size per cycle).
let default_restart : Int = 30

///|
/// Euclidean norm of a vector.
fn vec_norm(v : Array[Double]) -> Double {
  let mut s = 0.0
  for i = 0; i < v.length(); i = i + 1 {
    s = s + v[i] * v[i]
  }
  s.sqrt()
}

///|
/// Dot product of two vectors.
fn dot(a : Array[Double], b : Array[Double]) -> Double {
  let n = a.length()
  let mut s = 0.0
  for i = 0; i < n; i = i + 1 {
    s = s + a[i] * b[i]
  }
  s
}

///|
/// Matrix-vector product: result = A·v.
fn mat_vec(
  a : Array[Array[Double]],
  v : Array[Double],
  result : Array[Double],
) -> Unit {
  let n = v.length()
  for i = 0; i < n; i = i + 1 {
    let mut s = 0.0
    for j = 0; j < n; j = j + 1 {
      s = s + a[i][j] * v[j]
    }
    result[i] = s
  }
}

///|
/// Solve Ax = b using GMRES with restart (GMRES(m)).
///
/// `a` is an n×n matrix (row-major). `b` is the RHS. `x0` is the initial guess.
/// Returns the solution, or `None` if convergence fails or dimensions mismatch.
pub fn gmres_solve(
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
  _gmres_impl(a, b, x0, n, default_tol, default_max_iter, default_restart)
}

///|
/// GMRES with custom parameters.
pub fn gmres_solve_with(
  a : Array[Array[Double]],
  b : Array[Double],
  x0 : Array[Double],
  tol : Double,
  max_iter : Int,
  restart : Int,
) -> Array[Double]? {
  let n = b.length()
  if n == 0 {
    return Some([])
  }
  if a.length() != n ||
    x0.length() != n ||
    tol <= 0.0 ||
    max_iter <= 0 ||
    restart < 1 {
    return None
  }
  for i = 0; i < n; i = i + 1 {
    if a[i].length() != n {
      return None
    }
  }
  _gmres_impl(a, b, x0, n, tol, max_iter, restart)
}

///|
/// Core GMRES implementation.
fn _gmres_impl(
  a : Array[Array[Double]],
  b : Array[Double],
  x0 : Array[Double],
  n : Int,
  tol : Double,
  max_iter : Int,
  m : Int,
) -> Array[Double]? {
  // x = x0 (copy, will be updated)
  let x : Array[Double] = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    x[i] = x0[i]
  }
  let b_norm = vec_norm(b)
  if b_norm == 0.0 {
    return Some(x)
  }
  let tol_sq = tol * tol * b_norm * b_norm // Relative tolerance
  // Work arrays
  let r : Array[Double] = Array::make(n, 0.0)
  let w : Array[Double] = Array::make(n, 0.0)
  let av : Array[Double] = Array::make(n, 0.0)
  // V = Krylov basis vectors (m+1 vectors of length n)
  let v_basis : Array[Array[Double]] = Array::make(m + 1, [])
  for j = 0; j <= m; j = j + 1 {
    v_basis[j] = Array::make(n, 0.0)
  }
  // H = upper Hessenberg matrix (m+1 × m), stored as 2D array
  let h : Array[Array[Double]] = Array::make(m + 1, [])
  for j = 0; j <= m; j = j + 1 {
    h[j] = Array::make(m, 0.0)
  }
  // Givens rotation cosines and sines
  let cs : Array[Double] = Array::make(m, 0.0)
  let sn : Array[Double] = Array::make(m, 0.0)
  // g = RHS of least-squares problem (length m+1)
  let g : Array[Double] = Array::make(m + 1, 0.0)
  // y = solution of least-squares (length m)
  let y : Array[Double] = Array::make(m, 0.0)
  for iter = 0; iter < max_iter; iter = iter + 1 {
    // r = b - A·x
    mat_vec(a, x, r)
    for i = 0; i < n; i = i + 1 {
      r[i] = b[i] - r[i]
    }
    let beta = vec_norm(r)
    if beta * beta < tol_sq {
      return Some(x)
    }
    // v₁ = r / β
    for i = 0; i < n; i = i + 1 {
      v_basis[0][i] = r[i] / beta
    }
    // g = β·e₁
    g[0] = beta
    for j = 1; j <= m; j = j + 1 {
      g[j] = 0.0
    }
    // Reset H
    for j = 0; j <= m; j = j + 1 {
      for k = 0; k < m; k = k + 1 {
        h[j][k] = 0.0
      }
    }
    let mut converged = false
    for j = 0; j < m; j = j + 1 {
      // w = A·vⱼ
      mat_vec(a, v_basis[j], av)
      for i = 0; i < n; i = i + 1 {
        w[i] = av[i]
      }
      // Modified Gram-Schmidt
      for i = 0; i <= j; i = i + 1 {
        h[i][j] = dot(w, v_basis[i])
        for k = 0; k < n; k = k + 1 {
          w[k] = w[k] - h[i][j] * v_basis[i][k]
        }
      }
      let h_next = vec_norm(w)
      h[j + 1][j] = h_next
      // Check for breakdown
      if h_next < 1.0e-14 {
        // Lucky breakdown: w ≈ 0, solution is in current subspace
        // Apply Givens rotations to column j of H, then solve
        _apply_givens_to_col(h, cs, sn, j)
        _back_substitute(h, g, y, j + 1)
        // x = x + V·y
        for k = 0; k <= j; k = k + 1 {
          for i = 0; i < n; i = i + 1 {
            x[i] = x[i] + v_basis[k][i] * y[k]
          }
        }
        converged = true
        break
      }
      // vⱼ₊₁ = w / hⱼ₊₁ⱼ
      for i = 0; i < n; i = i + 1 {
        v_basis[j + 1][i] = w[i] / h_next
      }
      // Apply previous Givens rotations to new column of H
      _apply_givens_to_col(h, cs, sn, j)
      // Compute new Givens rotation to eliminate h[j+1][j]
      let h_jj = h[j][j]
      let h_j1j = h[j + 1][j]
      if h_j1j == 0.0 {
        cs[j] = 1.0
        sn[j] = 0.0
      } else {
        let denom = (h_jj * h_jj + h_j1j * h_j1j).sqrt()
        cs[j] = h_jj / denom
        sn[j] = h_j1j / denom
      }
      // Apply new rotation to H and g
      h[j][j] = cs[j] * h_jj + sn[j] * h_j1j
      h[j + 1][j] = 0.0
      let g_j = g[j]
      g[j] = cs[j] * g_j + sn[j] * g[j + 1]
      g[j + 1] = -sn[j] * g_j + cs[j] * g[j + 1]
      // Check convergence: |g[j+1]| / ‖b‖ < tol
      if g[j + 1] * g[j + 1] < tol_sq {
        _back_substitute(h, g, y, j + 1)
        for k = 0; k <= j; k = k + 1 {
          for i = 0; i < n; i = i + 1 {
            x[i] = x[i] + v_basis[k][i] * y[k]
          }
        }
        converged = true
        break
      }
    }
    if converged {
      return Some(x)
    }
    // Restart: solve least-squares with full m, update x, loop
    _back_substitute(h, g, y, m)
    for k = 0; k < m; k = k + 1 {
      for i = 0; i < n; i = i + 1 {
        x[i] = x[i] + v_basis[k][i] * y[k]
      }
    }
  }
  // Final residual check
  mat_vec(a, x, r)
  for i = 0; i < n; i = i + 1 {
    r[i] = b[i] - r[i]
  }
  if vec_norm(r) * vec_norm(r) < tol_sq * 10.0 {
    return Some(x)
  }
  None
}

///|
/// Apply all previous Givens rotations to column `j` of H.
fn _apply_givens_to_col(
  h : Array[Array[Double]],
  cs : Array[Double],
  sn : Array[Double],
  j : Int,
) -> Unit {
  for i = 0; i < j; i = i + 1 {
    let h_ij = h[i][j]
    let h_i1j = h[i + 1][j]
    h[i][j] = cs[i] * h_ij + sn[i] * h_i1j
    h[i + 1][j] = -sn[i] * h_ij + cs[i] * h_i1j
  }
}

///|
/// Back-substitution to solve the upper-triangular system R·y = g.
/// `size` is the number of variables (0 to size-1).
fn _back_substitute(
  h : Array[Array[Double]],
  g : Array[Double],
  y : Array[Double],
  size : Int,
) -> Unit {
  for i = size - 1; i >= 0; i = i - 1 {
    let mut s = g[i]
    for j = i + 1; j < size; j = j + 1 {
      s = s - h[i][j] * y[j]
    }
    if h[i][i].abs() < 1.0e-300 {
      y[i] = 0.0
    } else {
      y[i] = s / h[i][i]
    }
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "gmres: solve 2×2 system" {
  let a = [[4.0, 1.0], [1.0, 3.0]]
  let b = [1.0, 2.0]
  let x = @test_utils.expect_some(
    gmres_solve(a, b, [0.0, 0.0]),
    "gmres should converge",
  )
  let r0 = a[0][0] * x[0] + a[0][1] * x[1] - b[0]
  let r1 = a[1][0] * x[0] + a[1][1] * x[1] - b[1]
  assert_true(r0.abs() < 1.0e-8)
  assert_true(r1.abs() < 1.0e-8)
}

///|
test "gmres: solve non-symmetric 3×3" {
  let a = [[2.0, 1.0, 0.0], [0.0, 3.0, 1.0], [1.0, 0.0, 4.0]]
  let b = [5.0, 10.0, 9.0]
  let x = @test_utils.expect_some(
    gmres_solve(a, b, [0.0, 0.0, 0.0]),
    "should converge",
  )
  for i = 0; i < 3; i = i + 1 {
    let mut s = 0.0
    for j = 0; j < 3; j = j + 1 {
      s = s + a[i][j] * x[j]
    }
    assert_true((s - b[i]).abs() < 1.0e-6)
  }
}

///|
test "gmres: identity matrix" {
  let a = [[1.0, 0.0], [0.0, 1.0]]
  let b = [5.0, 3.0]
  let x = @test_utils.expect_some(gmres_solve(a, b, [0.0, 0.0]), "identity")
  assert_true((x[0] - 5.0).abs() < 1.0e-10)
  assert_true((x[1] - 3.0).abs() < 1.0e-10)
}

///|
test "gmres: diagonal system" {
  let a = [[3.0, 0.0, 0.0], [0.0, 5.0, 0.0], [0.0, 0.0, 7.0]]
  let b = [6.0, 10.0, 14.0]
  let x = @test_utils.expect_some(
    gmres_solve(a, b, [0.0, 0.0, 0.0]),
    "diagonal",
  )
  assert_true((x[0] - 2.0).abs() < 1.0e-8)
  assert_true((x[1] - 2.0).abs() < 1.0e-8)
  assert_true((x[2] - 2.0).abs() < 1.0e-8)
}

///|
test "gmres: dimension mismatch" {
  let a = [[1.0, 0.0], [0.0, 1.0]]
  assert_true(gmres_solve(a, [1.0], [0.0]) is None)
}

///|
test "gmres: 5×5 system" {
  let n = 5
  let a : Array[Array[Double]] = Array::make(n, [])
  for i = 0; i < n; i = i + 1 {
    a[i] = Array::make(n, 0.0)
    a[i][i] = 4.0
    if i > 0 {
      a[i][i - 1] = -1.0
    }
    if i < n - 1 {
      a[i][i + 1] = -1.0
    }
  }
  let b = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    b[i] = (i + 1).to_double()
  }
  let x = @test_utils.expect_some(
    gmres_solve(a, b, Array::make(n, 0.0)),
    "5×5 should converge",
  )
  for i = 0; i < n; i = i + 1 {
    let mut s = 0.0
    for j = 0; j < n; j = j + 1 {
      s = s + a[i][j] * x[j]
    }
    assert_true((s - b[i]).abs() < 1.0e-6)
  }
}
