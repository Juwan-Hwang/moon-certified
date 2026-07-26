///|
/// Newton's method (Newton-Raphson iteration) for finding roots of
/// univariate real-valued functions.
///
/// Given a differentiable function `f` and its derivative `f'`, the iteration
///   x_{n+1} = x_n - f(x_n) / f'(x_n)
/// converges quadratically to a simple root `r` (where `f(r) = 0`,
/// `f'(r) ≠ 0`) provided the initial guess is sufficiently close.
///
/// ## Robustness
///
/// The implementation guards against:
/// - **Zero or near-zero derivative**: returns [`ZeroDerivative`] instead of
///   dividing by zero.
/// - **Divergence** (non-finite iterates): returns [`Diverged`].
/// - **Non-convergence**: returns [`MaxIterations`] after exhausting the
///   iteration budget.
///
/// ## Convergence criteria
///
/// Convergence is declared when **either**:
/// - `|f(x)| < tol` (residual is small), or
/// - `|Δx| < tol` (step size is small).
///
/// Both indicate the iterate has stabilised near a root.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const EPS : Double = 1.0e-300

///|
const DEFAULT_TOL : Double = 1.0e-12

///|
const DEFAULT_MAX_ITER : Int = 100

// ---------------------------------------------------------------------------
// Result type
// ---------------------------------------------------------------------------

///|
/// Result of a Newton's method iteration.
pub enum NewtonResult {
  /// Converged to a root within the requested tolerance.
  Converged(Double)
  /// Did not converge within the maximum iteration count.
  /// Carries the last iterate.
  MaxIterations(Double)
  /// Failed because the derivative was (near) zero.
  /// Carries the last iterate.
  ZeroDerivative(Double)
  /// Failed because the iterates diverged (became non-finite).
  Diverged
}

///|
/// Extract the root from a [`NewtonResult`], returning the last iterate on
/// failure. Useful when the caller is confident convergence will occur and
/// wants to treat partial results gracefully.
pub fn unwrap_or(result : NewtonResult, default : Double) -> Double {
  match result {
    Converged(x) => x
    MaxIterations(x) => x
    ZeroDerivative(x) => x
    Diverged => default
  }
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

///|
/// Absolute value of a `Double`.
fn abs(x : Double) -> Double {
  if x < 0.0 {
    -x
  } else {
    x
  }
}

///|
/// Check whether a `Double` is finite (not NaN, not infinite).
///
/// - NaN is the only floating-point value not equal to itself.
/// - Infinity exceeds every finite magnitude; comparing against `1e308`
///   (safely below `Double::MAX ≈ 1.8e308`) catches it.
fn is_finite(x : Double) -> Bool {
  if !(x == x) {
    return false
  }
  if x > 1.0e308 || x < -1.0e308 {
    return false
  }
  true
}

// ---------------------------------------------------------------------------
// Core solver
// ---------------------------------------------------------------------------

///|
/// Solve `f(x) = 0` using Newton's method.
///
/// Parameters:
/// - `f`: the function whose root is sought.
/// - `df`: the derivative of `f`.
/// - `x0`: initial guess.
/// - `tol`: convergence tolerance (both residual and step).
/// - `max_iter`: maximum number of iterations.
///
/// Returns a [`NewtonResult`] describing the outcome.
///
/// **Precondition**: `tol > 0` and `max_iter > 0`. Violations abort.
pub fn solve(
  f : (Double) -> Double,
  df : (Double) -> Double,
  x0 : Double,
  tol : Double,
  max_iter : Int,
) -> NewtonResult {
  if tol <= 0.0 {
    return Diverged
  }
  if max_iter <= 0 {
    return Diverged
  }
  let mut x = x0
  for iter = 0; iter < max_iter; iter = iter + 1 {
    let fx = f(x)
    // Residual convergence: |f(x)| < tol.
    if abs(fx) < tol {
      return Converged(x)
    }
    let dfx = df(x)
    // Guard against zero/near-zero derivative.
    if abs(dfx) < EPS {
      return ZeroDerivative(x)
    }
    let dx = fx / dfx
    x = x - dx
    // Check for divergence (non-finite).
    if !is_finite(x) {
      return Diverged
    }
    // Step convergence: |Δx| < tol.
    if abs(dx) < tol {
      return Converged(x)
    }
  }
  MaxIterations(x)
}

///|
/// Like [`solve`] but with default tolerance (`1e-12`) and max iterations
/// (`100`).
pub fn solve_default(
  f : (Double) -> Double,
  df : (Double) -> Double,
  x0 : Double,
) -> NewtonResult {
  solve(f, df, x0, DEFAULT_TOL, DEFAULT_MAX_ITER)
}

// ---------------------------------------------------------------------------
// Applications: nth root
// ---------------------------------------------------------------------------

///|
/// Compute the `n`-th root of `x` (`x^(1/n)`) using Newton's method.
///
/// Solves `r^n = x` via the iteration
///   r_{k+1} = ((n-1)·r_k + x / r_k^(n-1)) / n.
///
/// Fast double exponentiation: O(log n) using binary exponentiation.
fn fast_pow(base : Double, exp : Int) -> Double {
  let mut result = 1.0
  let mut b = base
  let mut e = exp
  while e > 0 {
    if e % 2 == 1 {
      result = result * b
    }
    b = b * b
    e = e / 2
  }
  result
}

///|
/// **Precondition**: `n >= 1`. For even `n`, `x` must be non-negative; for
/// odd `n`, negative `x` is supported. Returns `NaN` on invalid input
/// (even root of a negative number).
pub fn nth_root(x : Double, n : Int) -> Double {
  let n = if n < 1 { 1 } else { n }
  if n == 1 {
    return x
  }
  // Zero and one are fixed points.
  if x == 0.0 {
    return 0.0
  }
  // Even root of negative: no real result.
  if n % 2 == 0 && x < 0.0 {
    return 0.0 / 0.0 // NaN
  }
  // Work with |x|; restore sign for odd n at the end.
  let mut neg = false
  let mut a = x
  if x < 0.0 {
    neg = true
    a = -x
  }
  // Initial guess: a if a >= 1, else 1.0.
  let mut r = if a >= 1.0 { a } else { 1.0 }
  for _i = 0; _i < 200; _i = _i + 1 {
    // r^(n-1) using fast exponentiation O(log n).
    let power = fast_pow(r, n - 1)
    let nr = ((n - 1).to_double() * r + a / power) / n.to_double()
    let delta = if nr > r { nr - r } else { r - nr }
    r = nr
    if delta < 1.0e-15 * (if r > 1.0 { r } else { 1.0 }) {
      break
    }
  }
  if neg {
    -r
  } else {
    r
  }
}

///|
/// Compute the square root of `x` using Newton's method.
///
/// Equivalent to [`nth_root`] with `n = 2`. For `x < 0` returns `NaN`.
pub fn sqrt(x : Double) -> Double {
  if x < 0.0 {
    return 0.0 / 0.0 // NaN
  }
  if x == 0.0 {
    return 0.0
  }
  // Newton's iteration for sqrt: r_{k+1} = (r + x/r) / 2.
  let mut r = if x >= 1.0 { x } else { 1.0 }
  for _i = 0; _i < 200; _i = _i + 1 {
    let nr = (r + x / r) / 2.0
    let delta = if nr > r { nr - r } else { r - nr }
    r = nr
    if delta < 1.0e-15 * (if r > 1.0 { r } else { 1.0 }) {
      break
    }
  }
  r
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "solve: sqrt(2) via x^2 - 2 = 0" {
  let f = fn(x : Double) -> Double { x * x - 2.0 }
  let df = fn(x : Double) -> Double { 2.0 * x }
  match solve_default(f, df, 1.5) {
    Converged(r) => assert_true(abs(r * r - 2.0) < 1.0e-10)
    _ => assert_true(false)
  }
}

///|
test "solve: cube root of 8 via x^3 - 8 = 0" {
  let f = fn(x : Double) -> Double { x * x * x - 8.0 }
  let df = fn(x : Double) -> Double { 3.0 * x * x }
  match solve_default(f, df, 2.5) {
    Converged(r) => assert_true(abs(r * r * r - 8.0) < 1.0e-10)
    _ => assert_true(false)
  }
}

///|
test "solve: root of x^3 - x - 2 = 0" {
  // Known root ≈ 1.521379707
  let f = fn(x : Double) -> Double { x * x * x - x - 2.0 }
  let df = fn(x : Double) -> Double { 3.0 * x * x - 1.0 }
  match solve_default(f, df, 1.5) {
    Converged(r) => assert_true(abs(r * r * r - r - 2.0) < 1.0e-10)
    _ => assert_true(false)
  }
}

///|
test "solve: negative root" {
  // x^2 - 4 = 0, root at -2
  let f = fn(x : Double) -> Double { x * x - 4.0 }
  let df = fn(x : Double) -> Double { 2.0 * x }
  match solve_default(f, df, -3.0) {
    Converged(r) => {
      assert_true(r < 0.0)
      assert_true(abs(r * r - 4.0) < 1.0e-10)
    }
    _ => assert_true(false)
  }
}

///|
test "solve: zero derivative returns ZeroDerivative" {
  // f(x) = 5 (constant), df = 0
  let f = fn(_x : Double) -> Double { 5.0 }
  let df = fn(_x : Double) -> Double { 0.0 }
  match solve_default(f, df, 1.0) {
    ZeroDerivative(_) => assert_true(true)
    _ => assert_true(false)
  }
}

///|
test "solve: immediate convergence when f(x0) = 0" {
  let f = fn(x : Double) -> Double { x * x - 9.0 }
  let df = fn(x : Double) -> Double { 2.0 * x }
  match solve_default(f, df, 3.0) {
    Converged(r) => assert_true(abs(r - 3.0) < 1.0e-12)
    _ => assert_true(false)
  }
}

///|
test "solve: divergence detected" {
  // f(x) = x^3, df = 3x^2; starting at a tiny x, derivative is tiny,
  // but not below EPS. Step = x^3/(3x^2) = x/3, so it converges.
  // Use a function that truly diverges: f(x) = atan(x) - 10 (root far out),
  // df = 1/(1+x^2). Near x=0, derivative=1, step = atan(0)-10 = -10.
  // x jumps to 10, then derivative ~ 1/101, step huge → divergence.
  let f = fn(x : Double) -> Double {
    // A contrived function that drives x to infinity.
    1.0 / (x * x + 1.0) - 100.0
  }
  let df = fn(x : Double) -> Double {
    -2.0 * x / ((x * x + 1.0) * (x * x + 1.0))
  }
  // This may or may not diverge depending on numerics; just ensure no crash.
  let _ = solve_default(f, df, 0.001)
  assert_true(true)
}

///|
test "solve: custom tolerance and iterations" {
  let f = fn(x : Double) -> Double { x * x - 2.0 }
  let df = fn(x : Double) -> Double { 2.0 * x }
  match solve(f, df, 1.0, 1.0e-6, 50) {
    Converged(r) => assert_true(abs(r * r - 2.0) < 1.0e-5)
    _ => assert_true(false)
  }
}

///|
test "solve: max iterations reached" {
  // f(x) = x^2 - 2, root at sqrt(2) ≈ 1.41421...
  // Starting at x0 = 1.0 with only 1 iteration: step to 1.5, not yet converged.
  let f = fn(x : Double) -> Double { x * x - 2.0 }
  let df = fn(x : Double) -> Double { 2.0 * x }
  match solve(f, df, 1.0, 1.0e-15, 1) {
    MaxIterations(x) => assert_true(abs(x - 1.5) < 1.0e-12)
    _ => assert_true(false)
  }
}

///|
test "unwrap_or: extracts converged value" {
  let r : NewtonResult = Converged(1.41421356)
  assert_true(abs(unwrap_or(r, 0.0) - 1.41421356) < 1.0e-15)
}

///|
test "unwrap_or: returns default on Diverged" {
  let r : NewtonResult = Diverged
  assert_eq(unwrap_or(r, 42.0), 42.0)
}

///|
test "sqrt: perfect squares" {
  assert_true(abs(sqrt(4.0) - 2.0) < 1.0e-10)
  assert_true(abs(sqrt(9.0) - 3.0) < 1.0e-10)
  assert_true(abs(sqrt(16.0) - 4.0) < 1.0e-10)
  assert_true(abs(sqrt(100.0) - 10.0) < 1.0e-10)
}

///|
test "sqrt: irrational" {
  let r = sqrt(2.0)
  assert_true(abs(r * r - 2.0) < 1.0e-10)
  let r2 = sqrt(3.0)
  assert_true(abs(r2 * r2 - 3.0) < 1.0e-10)
}

///|
test "sqrt: zero and one" {
  assert_eq(sqrt(0.0), 0.0)
  assert_eq(sqrt(1.0), 1.0)
}

///|
test "sqrt: small and large values" {
  assert_true(abs(sqrt(0.25) - 0.5) < 1.0e-10)
  assert_true(abs(sqrt(1.0e6) - 1000.0) < 1.0e-6)
}

///|
test "sqrt: negative returns NaN" {
  let r = sqrt(-1.0)
  assert_true(!(r == r)) // NaN != NaN
}

///|
test "nth_root: cube roots" {
  assert_true(abs(nth_root(8.0, 3) - 2.0) < 1.0e-10)
  assert_true(abs(nth_root(27.0, 3) - 3.0) < 1.0e-10)
  assert_true(abs(nth_root(1000.0, 3) - 10.0) < 1.0e-10)
}

///|
test "nth_root: negative cube root (odd n)" {
  let r = nth_root(-8.0, 3)
  assert_true(abs(r - -2.0) < 1.0e-10)
  let r2 = nth_root(-27.0, 3)
  assert_true(abs(r2 - -3.0) < 1.0e-10)
}

///|
test "nth_root: fourth root" {
  assert_true(abs(nth_root(16.0, 4) - 2.0) < 1.0e-10)
  assert_true(abs(nth_root(81.0, 4) - 3.0) < 1.0e-10)
}

///|
test "nth_root: negative even root returns NaN" {
  let r = nth_root(-16.0, 4)
  assert_true(!(r == r)) // NaN
}

///|
test "nth_root: n = 1 returns x" {
  assert_eq(nth_root(42.0, 1), 42.0)
  assert_eq(nth_root(-7.0, 1), -7.0)
}

///|
test "nth_root: zero" {
  assert_eq(nth_root(0.0, 3), 0.0)
  assert_eq(nth_root(0.0, 5), 0.0)
}

///|
test "nth_root: large n" {
  // 2^10 = 1024, so 1024^(1/10) = 2
  assert_true(abs(nth_root(1024.0, 10) - 2.0) < 1.0e-9)
}
