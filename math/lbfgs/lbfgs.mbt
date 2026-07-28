/// L-BFGS — Limited-memory BFGS quasi-Newton optimizer for unconstrained
/// smooth minimization.
///
/// L-BFGS approximates the inverse Hessian `H_k` of the objective function
/// using only the last `m` pairs of `(s, y)` vectors (position and gradient
/// differences), achieving `O(nm)` per-iteration cost instead of the `O(n²)`
/// storage and computation of full BFGS. It is the workhorse optimizer for
/// large-scale machine learning, scientific computing, and engineering
/// optimization.
///
/// ## Algorithm
///
/// ```text
/// x₀ = initial point
/// for k = 0, 1, 2, …:
///   d_k = -H_k ∇f(x_k)        // via two-loop recursion
///   α_k = line_search(f, ∇f, x_k, d_k)  // Armijo backtracking
///   x_{k+1} = x_k + α_k d_k
///   s_k = x_{k+1} − x_k
///   y_k = ∇f(x_{k+1}) − ∇f(x_k)
///   if y_kᵀ s_k > 0: store (s_k, y_k), discard oldest if > m pairs
///   if ‖∇f(x_{k+1})‖ < tol: stop
/// ```
///
/// The two-loop recursion computes `H_k · g` in `O(nm)` without ever forming
/// the `n×n` matrix:
///
/// ```text
/// q = g
/// for i = k−1 … k−m:  αᵢ = ρᵢ sᵢᵀq;  q ← q − αᵢ yᵢ
/// r = H⁰ q            // H⁰ = (sᵀy)/(yᵀy) scaling
/// for i = k−m … k−1:  β = ρᵢ yᵢᵀr;  r ← r + sᵢ(αᵢ − β)
/// return r
/// ```
///
/// ## Complexity
///
/// - Per iteration: `O(nm)` for the two-loop recursion plus `O(n)` for
///   gradient evaluation and line search.
/// - Total: `O(nm · k)` where `k` is the number of iterations.
/// - Memory: `O(nm)` for storing `m` pairs of `n`-vectors.
///
/// ## References
///
/// - Nocedal, J. (1980): "Updating quasi-Newton matrices with limited
///   storage." *Mathematics of Computation*, 35(151), 773–782.
/// - Liu, D. C. and Nocedal, J. (1989): "On the limited memory BFGS method
///   for large scale optimization." *Mathematical Programming*, 45, 503–528.
/// - Nocedal, J. and Wright, S. J. (2006): *Numerical Optimization*, 2nd ed.,
///   Springer, Chapter 7.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

///|
/// Default convergence tolerance on the gradient norm: `‖∇f‖ < tol`.
let lbfgs_default_tol : Double = 1.0e-8

///|
/// Default maximum number of outer iterations.
let lbfgs_default_max_iter : Int = 1000

///|
/// Default history size (number of `(s, y)` pairs retained). `m = 10` is the
/// widely used default recommended by Nocedal & Wright.
let lbfgs_default_m : Int = 10

///|
/// Armijo condition constant `c₁` (sufficient decrease). Must satisfy
/// `0 < c₁ < 1`. Standard value `1e-4` from Nocedal & Wright (2006, Eq. 3.4).
let lbfgs_c1 : Double = 1.0e-4

///|
/// Backtracking line-search shrinkage factor `β`. Each failed Armijo trial
/// multiplies the step by `β`. `0.5` gives bisection-style shrinkage.
let lbfgs_beta : Double = 0.5

///|
/// Initial line-search step size. L-BFGS typically starts with `α = 1.0`
/// (the natural quasi-Newton step) on every iteration after the first.
let lbfgs_alpha_init : Double = 1.0

///|
/// Minimum line-search step to avoid infinite shrinking.
let lbfgs_alpha_min : Double = 1.0e-20

///|
/// Maximum number of backtracking trials per iteration.
let lbfgs_max_ls : Int = 50

// ---------------------------------------------------------------------------
// Result type
// ---------------------------------------------------------------------------

///|
/// Result of an L-BFGS optimization run.
pub enum LbfgsResult {
  /// Converged: gradient norm fell below `tol`.
  ///
  /// Fields: `(x, fval, iterations, grad_norm)`.
  Converged(
    Array[Double],
    Double,
    Int,
    Double,
  )
  /// Reached the iteration limit without converging. The returned point is
  /// the best found so far.
  ///
  /// Fields: `(x, fval, iterations, grad_norm)`.
  MaxIterations(
    Array[Double],
    Double,
    Int,
    Double,
  )
  /// Dimension mismatch or invalid input.
  InvalidInput
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

///|
/// Minimize a smooth function `f` with gradient `grad` starting from `x0`.
///
/// Uses default parameters: `tol = 1e-8`, `max_iter = 1000`, `m = 10`.
///
/// - `f`: objective function `f(x) → Double`.
/// - `grad`: gradient function `∇f(x) → Array[Double]`.
/// - `x0`: initial point (not modified; a copy is used internally).
///
/// Returns a [`LbfgsResult`] indicating convergence status.
pub fn minimize(
  f : (Array[Double]) -> Double,
  grad : (Array[Double]) -> Array[Double],
  x0 : Array[Double],
) -> LbfgsResult {
  minimize_with(f, grad, x0, lbfgs_default_tol, lbfgs_default_max_iter, lbfgs_default_m)
}

///|
/// Minimize with custom parameters.
///
/// - `tol`: gradient-norm convergence threshold.
/// - `max_iter`: maximum outer iterations.
/// - `m`: L-BFGS history size (number of `(s, y)` pairs retained, `1 ≤ m`).
pub fn minimize_with(
  f : (Array[Double]) -> Double,
  grad : (Array[Double]) -> Array[Double],
  x0 : Array[Double],
  tol : Double,
  max_iter : Int,
  m : Int,
) -> LbfgsResult {
  let n = x0.length()
  if n == 0 || tol <= 0.0 || max_iter <= 0 || m <= 0 {
    return InvalidInput
  }
  // Validate gradient dimension on first call.
  let g0 = grad(x0)
  if g0.length() != n {
    return InvalidInput
  }
  _minimize_impl(f, grad, x0, n, tol, max_iter, m, g0)
}

// ---------------------------------------------------------------------------
// Core implementation
// ---------------------------------------------------------------------------

///|
/// Ring-buffer entry for one `(s, y, ρ)` triplet.
priv struct HistoryEntry {
  s : Array[Double]
  y : Array[Double]
  rho : Double // 1 / (yᵀs)
}

///|
fn _minimize_impl(
  f : (Array[Double]) -> Double,
  grad : (Array[Double]) -> Array[Double],
  x0 : Array[Double],
  n : Int,
  tol : Double,
  max_iter : Int,
  m : Int,
  g0 : Array[Double],
) -> LbfgsResult {
  // Working copies (do not mutate caller's x0).
  let x : Array[Double] = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    x[i] = x0[i]
  }
  let g : Array[Double] = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    g[i] = g0[i]
  }
  // History ring buffer.
  let history : Array[HistoryEntry] = []
  let mut fval = f(x)
  let mut grad_norm = _vec_norm(g, n)
  // Convergence on initial point.
  if grad_norm < tol {
    return Converged(x, fval, 0, grad_norm)
  }
  // Search direction d = -H·g  (initially H = I, so d = -g).
  let d : Array[Double] = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    d[i] = -g[i]
  }
  for iter = 0; iter < max_iter; iter = iter + 1 {
    // --- Line search (Armijo backtracking) ---
    let mut alpha = if iter == 0 { 1.0 / _vec_norm(d, n) } else { lbfgs_alpha_init }
    let dg = _dot(g, d, n) // directional derivative (should be < 0)
    if dg >= 0.0 {
      // Not a descent direction — reset to steepest descent.
      for i = 0; i < n; i = i + 1 {
        d[i] = -g[i]
      }
      alpha = 1.0 / _vec_norm(g, n)
    }
    let f_old = fval
    // Armijo: f(x + αd) ≤ f(x) + c₁ α ∇fᵀd
    let ls = _armijo_line_search(f, x, d, f_old, dg, alpha, n)
    if !ls.success {
      // Line search failed entirely — return current best.
      return MaxIterations(x, fval, iter, grad_norm)
    }
    alpha = ls.alpha
    // x_new = x + α·d
    let x_new : Array[Double] = Array::make(n, 0.0)
    for i = 0; i < n; i = i + 1 {
      x_new[i] = x[i] + alpha * d[i]
    }
    let g_new = grad(x_new)
    if g_new.length() != n {
      return MaxIterations(x, fval, iter, grad_norm)
    }
    let f_new = f(x_new)
    // s = x_new - x, y = g_new - g
    let s : Array[Double] = Array::make(n, 0.0)
    let y : Array[Double] = Array::make(n, 0.0)
    for i = 0; i < n; i = i + 1 {
      s[i] = x_new[i] - x[i]
      y[i] = g_new[i] - g[i]
    }
    let ys = _dot(y, s, n)
    // Curvature condition: yᵀs > 0 (required for positive-definiteness of H).
    if ys > 1.0e-16 {
      let entry : HistoryEntry = { s, y, rho: 1.0 / ys }
      history.push(entry)
      if history.length() > m {
        // Discard oldest by shifting left and popping the tail.
        for i = 0; i < m; i = i + 1 {
          history[i] = history[i + 1]
        }
        ignore(history.pop())
      }
    }
    // Accept the step.
    for i = 0; i < n; i = i + 1 {
      x[i] = x_new[i]
      g[i] = g_new[i]
    }
    fval = f_new
    grad_norm = _vec_norm(g, n)
    if grad_norm < tol {
      return Converged(x, fval, iter + 1, grad_norm)
    }
    // --- Compute next search direction via two-loop recursion ---
    _two_loop_recursion(history, g, d, n, ys)
  }
  MaxIterations(x, fval, max_iter, grad_norm)
}

// ---------------------------------------------------------------------------
// Two-loop recursion
// ---------------------------------------------------------------------------

///|
/// Compute `d = -H_k · g` using the L-BFGS two-loop recursion.
///
/// Modifies `d` in place. Uses `H⁰ = γI` where `γ = sᵀy / yᵀy` from the most
/// recent pair (or `γ = 1` if history is empty).
fn _two_loop_recursion(
  history : Array[HistoryEntry],
  g : Array[Double],
  d : Array[Double],
  n : Int,
  last_ys : Double,
) -> Unit {
  let h = history.length()
  if h == 0 {
    // No history: steepest descent.
    for i = 0; i < n; i = i + 1 {
      d[i] = -g[i]
    }
    return
  }
  // q = g (copy into d which will become the output).
  let q : Array[Double] = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    q[i] = g[i]
  }
  // αᵢ storage.
  let alphas : Array[Double] = Array::make(h, 0.0)
  // First loop: i = h-1 … 0 (newest to oldest).
  for k = h - 1; k >= 0; k = k - 1 {
    let entry = history[k]
    let a = entry.rho * _dot(entry.s, q, n)
    alphas[k] = a
    for i = 0; i < n; i = i + 1 {
      q[i] = q[i] - a * entry.y[i]
    }
  }
  // Apply initial Hessian H⁰ = γI.
  let last_entry = history[h - 1]
  let yy = _dot(last_entry.y, last_entry.y, n)
  let gamma = if yy > 1.0e-30 {
    last_ys / yy
  } else {
    1.0
  }
  for i = 0; i < n; i = i + 1 {
    d[i] = gamma * q[i]
  }
  // Second loop: i = 0 … h-1 (oldest to newest).
  for k = 0; k < h; k = k + 1 {
    let entry = history[k]
    let beta = entry.rho * _dot(entry.y, d, n)
    let a = alphas[k] - beta
    for i = 0; i < n; i = i + 1 {
      d[i] = d[i] + a * entry.s[i]
    }
  }
  // Negate to get descent direction.
  for i = 0; i < n; i = i + 1 {
    d[i] = -d[i]
  }
}

// ---------------------------------------------------------------------------
// Line search
// ---------------------------------------------------------------------------

priv struct LineSearchResult {
  success : Bool
  alpha : Double
}

///|
/// Armijo backtracking line search.
///
/// Finds `α` satisfying the sufficient-decrease (Armijo) condition:
///   f(x + αd) ≤ f(x) + c₁·α·∇f(x)ᵀd
///
/// Starting from `alpha`, shrinks by `β` until the condition holds or `α`
/// drops below `alpha_min`.
fn _armijo_line_search(
  f : (Array[Double]) -> Double,
  x : Array[Double],
  d : Array[Double],
  f_old : Double,
  dg : Double,
  alpha_init : Double,
  n : Int,
) -> LineSearchResult {
  let mut alpha = alpha_init
  let x_trial : Array[Double] = Array::make(n, 0.0)
  for trial = 0; trial < lbfgs_max_ls; trial = trial + 1 {
    for i = 0; i < n; i = i + 1 {
      x_trial[i] = x[i] + alpha * d[i]
    }
    let f_trial = f(x_trial)
    // Armijo condition: f(x + αd) ≤ f(x) + c₁ α ∇fᵀd
    if f_trial <= f_old + lbfgs_c1 * alpha * dg {
      return { success: true, alpha }
    }
    alpha = alpha * lbfgs_beta
    if alpha < lbfgs_alpha_min {
      return { success: false, alpha }
    }
  }
  { success: false, alpha }
}

// ---------------------------------------------------------------------------
// Vector helpers
// ---------------------------------------------------------------------------

///|
fn _dot(a : Array[Double], b : Array[Double], n : Int) -> Double {
  let mut s = 0.0
  for i = 0; i < n; i = i + 1 {
    s = s + a[i] * b[i]
  }
  s
}

///|
fn _vec_norm(a : Array[Double], n : Int) -> Double {
  _dot(a, a, n).sqrt()
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "lbfgs: minimize quadratic (2D)" {
  // f(x) = (x₀−3)² + (x₁+1)²,  gradient = [2(x₀−3), 2(x₁+1)]
  // Minimum at (3, −1), f = 0.
  let f = fn(x : Array[Double]) -> Double {
    (x[0] - 3.0) * (x[0] - 3.0) + (x[1] + 1.0) * (x[1] + 1.0)
  }
  let grad = fn(x : Array[Double]) -> Array[Double] {
    [2.0 * (x[0] - 3.0), 2.0 * (x[1] + 1.0)]
  }
  match minimize(f, grad, [0.0, 0.0]) {
    Converged(x, fval, _iter, _gn) => {
      assert_true((x[0] - 3.0).abs() < 1.0e-6)
      assert_true((x[1] + 1.0).abs() < 1.0e-6)
      assert_true(fval.abs() < 1.0e-12)
    }
    _ => abort("lbfgs should converge on simple quadratic")
  }
}

///|
test "lbfgs: minimize Rosenbrock function" {
  // f(x,y) = (1−x)² + 100(y−x²)²
  // Minimum at (1, 1), f = 0.
  let f = fn(x : Array[Double]) -> Double {
    let dx = 1.0 - x[0]
    let dy = x[1] - x[0] * x[0]
    dx * dx + 100.0 * dy * dy
  }
  let grad = fn(x : Array[Double]) -> Array[Double] {
    let dx = 1.0 - x[0]
    let dy = x[1] - x[0] * x[0]
    [-2.0 * dx - 400.0 * x[0] * dy, 200.0 * dy]
  }
  match minimize_with(f, grad, [-1.2, 1.0], 1.0e-8, 1000, 10) {
    Converged(x, fval, _iter, _gn) => {
      assert_true((x[0] - 1.0).abs() < 1.0e-4)
      assert_true((x[1] - 1.0).abs() < 1.0e-4)
      assert_true(fval < 1.0e-10)
    }
    _ => abort("lbfgs should converge on Rosenbrock")
  }
}

///|
test "lbfgs: minimize Booth function" {
  // f(x,y) = (x+2y−7)² + (2x+y−5)²
  // Minimum at (1, 3), f = 0.
  let f = fn(x : Array[Double]) -> Double {
    let a = x[0] + 2.0 * x[1] - 7.0
    let b = 2.0 * x[0] + x[1] - 5.0
    a * a + b * b
  }
  let grad = fn(x : Array[Double]) -> Array[Double] {
    let a = x[0] + 2.0 * x[1] - 7.0
    let b = 2.0 * x[0] + x[1] - 5.0
    [2.0 * a + 4.0 * b, 4.0 * a + 2.0 * b]
  }
  match minimize(f, grad, [0.0, 0.0]) {
    Converged(x, fval, _iter, _gn) => {
      assert_true((x[0] - 1.0).abs() < 1.0e-6)
      assert_true((x[1] - 3.0).abs() < 1.0e-6)
      assert_true(fval < 1.0e-12)
    }
    _ => abort("lbfgs should converge on Booth function")
  }
}

///|
test "lbfgs: already at minimum" {
  let f = fn(x : Array[Double]) -> Double {
    x[0] * x[0] + x[1] * x[1]
  }
  let grad = fn(_x : Array[Double]) -> Array[Double] {
    [0.0, 0.0]
  }
  match minimize(f, grad, [0.0, 0.0]) {
    Converged(x, _fval, iter, _gn) => {
      assert_true(iter == 0)
      assert_true(x[0].abs() < 1.0e-15)
      assert_true(x[1].abs() < 1.0e-15)
    }
    _ => abort("should converge immediately at minimum")
  }
}

///|
test "lbfgs: 5D diagonal quadratic" {
  // f(x) = Σ i·xᵢ², minimum at origin.
  let f = fn(x : Array[Double]) -> Double {
    let mut s = 0.0
    for i = 0; i < 5; i = i + 1 {
      s = s + (i + 1).to_double() * x[i] * x[i]
    }
    s
  }
  let grad = fn(x : Array[Double]) -> Array[Double] {
    let g = Array::make(5, 0.0)
    for i = 0; i < 5; i = i + 1 {
      g[i] = 2.0 * (i + 1).to_double() * x[i]
    }
    g
  }
  let x0 = [1.0, 2.0, 3.0, 4.0, 5.0]
  match minimize(f, grad, x0) {
    Converged(x, fval, _iter, _gn) => {
      for i = 0; i < 5; i = i + 1 {
        assert_true(x[i].abs() < 1.0e-6)
      }
      assert_true(fval < 1.0e-12)
    }
    _ => abort("lbfgs should converge on 5D quadratic")
  }
}

///|
test "lbfgs: invalid input returns InvalidInput" {
  let f = fn(_x : Array[Double]) -> Double { 0.0 }
  let grad = fn(_x : Array[Double]) -> Array[Double] { [] }
  match minimize(f, grad, []) {
    InvalidInput => ()
    _ => abort("empty x0 should return InvalidInput")
  }
}

///|
test "lbfgs: gradient dimension mismatch" {
  let f = fn(x : Array[Double]) -> Double { x[0] * x[0] }
  let grad = fn(_x : Array[Double]) -> Array[Double] { [0.0, 0.0] } // wrong size
  match minimize(f, grad, [1.0]) {
    InvalidInput => ()
    _ => abort("dimension mismatch should return InvalidInput")
  }
}

///|
test "lbfgs: small history size m=1" {
  let f = fn(x : Array[Double]) -> Double {
    (x[0] - 5.0) * (x[0] - 5.0) + (x[1] - 3.0) * (x[1] - 3.0)
  }
  let grad = fn(x : Array[Double]) -> Array[Double] {
    [2.0 * (x[0] - 5.0), 2.0 * (x[1] - 3.0)]
  }
  match minimize_with(f, grad, [0.0, 0.0], 1.0e-8, 1000, 1) {
    Converged(x, fval, _iter, _gn) => {
      assert_true((x[0] - 5.0).abs() < 1.0e-5)
      assert_true((x[1] - 3.0).abs() < 1.0e-5)
      assert_true(fval < 1.0e-10)
    }
    _ => abort("lbfgs should converge with m=1")
  }
}

///|
test "lbfgs: Matyas function" {
  // f(x,y) = 0.26(x²+y²) − 0.48xy
  // Minimum at (0, 0), f = 0.
  let f = fn(x : Array[Double]) -> Double {
    0.26 * (x[0] * x[0] + x[1] * x[1]) - 0.48 * x[0] * x[1]
  }
  let grad = fn(x : Array[Double]) -> Array[Double] {
    [0.52 * x[0] - 0.48 * x[1], 0.52 * x[1] - 0.48 * x[0]]
  }
  match minimize(f, grad, [3.0, -2.0]) {
    Converged(x, fval, _iter, _gn) => {
      assert_true(x[0].abs() < 1.0e-6)
      assert_true(x[1].abs() < 1.0e-6)
      assert_true(fval.abs() < 1.0e-12)
    }
    _ => abort("lbfgs should converge on Matyas function")
  }
}
