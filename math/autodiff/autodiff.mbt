/// Automatic Differentiation — forward-mode (dual-number) AD.
///
/// Provides exact derivatives and gradients of smooth functions without the
/// numerical error of finite differences and without the overhead of symbolic
/// differentiation. Forward mode is ideal for functions `f: ℝⁿ → ℝᵐ` with
/// `n ≪ m` (few inputs, many outputs) or for computing individual partial
/// derivatives.
///
/// ## Dual Numbers
///
/// A dual number `a + a′ε` carries a primal value `a` and a derivative `a′`,
/// where `ε² = 0`. Arithmetic on duals propagates derivatives via the chain
/// rule automatically:
///
/// ```text
/// (a + a′ε) + (b + b′ε) = (a+b) + (a′+b′)ε
/// (a + a′ε) × (b + b′ε) = ab  + (a′b + ab′)ε
/// f(a + a′ε)             = f(a) + f′(a)·a′ε
/// ```
///
/// ## Gradient Computation
///
/// For a multivariate function `f: ℝⁿ → ℝ`, the gradient `∇f` is computed in
/// `n` forward passes, each seeding one variable's derivative to `1` and the
/// rest to `0`. This costs `O(n · C(f))` where `C(f)` is the cost of one
/// function evaluation — optimal for forward mode.
///
/// ## References
///
/// - Griewank, A. and Walther, A. (2008): *Evaluating Derivatives: Principles
///   and Techniques of Algorithmic Differentiation*, 2nd ed., SIAM.
/// - Baydin, A. G. et al. (2018): "Automatic Differentiation in Machine
///   Learning: a Survey." *Journal of Machine Learning Research*, 18(153).
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Dual number type
// ---------------------------------------------------------------------------

///|
/// A dual number: primal `val` + tangent `deriv`, representing
/// `val + deriv·ε` where `ε² = 0`.
pub struct Dual {
  /// Primal (function value).
  val : Double
  /// Derivative (tangent).
  deriv : Double
}

// ---------------------------------------------------------------------------
// Constructors
// ---------------------------------------------------------------------------

///|
/// Create a constant (derivative = 0).
pub fn constant(v : Double) -> Dual {
  { val: v, deriv: 0.0, }
}

///|
/// Create an independent variable with derivative `1` (i.e., `d/dx = 1`).
pub fn variable(v : Double) -> Dual {
  { val: v, deriv: 1.0, }
}

///|
/// Create an independent variable with a custom seed derivative.
pub fn variable_with_seed(v : Double, seed : Double) -> Dual {
  { val: v, deriv: seed, }
}

// ---------------------------------------------------------------------------
// Accessors
// ---------------------------------------------------------------------------

///|
/// Extract the primal value.
pub fn primal(d : Dual) -> Double {
  d.val
}

///|
/// Extract the derivative.
pub fn tangent(d : Dual) -> Double {
  d.deriv
}

// ---------------------------------------------------------------------------
// Arithmetic operations
// ---------------------------------------------------------------------------

///|
/// Addition: `(a+a′ε) + (b+b′ε) = (a+b) + (a′+b′)ε`.
pub fn add(a : Dual, b : Dual) -> Dual {
  { val: a.val + b.val, deriv: a.deriv + b.deriv, }
}

///|
/// Subtraction: `(a+a′ε) − (b+b′ε) = (a−b) + (a′−b′)ε`.
pub fn sub(a : Dual, b : Dual) -> Dual {
  { val: a.val - b.val, deriv: a.deriv - b.deriv, }
}

///|
/// Multiplication: `(a+a′ε)(b+b′ε) = ab + (a′b + ab′)ε`.
pub fn mul(a : Dual, b : Dual) -> Dual {
  { val: a.val * b.val, deriv: a.deriv * b.val + a.val * b.deriv, }
}

///|
/// Division: `(a+a′ε)/(b+b′ε) = a/b + (a′b − ab′)/(b²) ε`.
pub fn div(a : Dual, b : Dual) -> Dual {
  let bv2 = b.val * b.val
  { val: a.val / b.val, deriv: (a.deriv * b.val - a.val * b.deriv) / bv2, }
}

///|
/// Negation: `−(a+a′ε) = −a + (−a′)ε`.
pub fn neg(a : Dual) -> Dual {
  { val: -a.val, deriv: -a.deriv, }
}

///|
/// Scalar addition: `a + c` (c is a constant).
pub fn add_scalar(a : Dual, c : Double) -> Dual {
  { val: a.val + c, deriv: a.deriv, }
}

///|
/// Scalar multiplication: `a × c` (c is a constant).
pub fn mul_scalar(a : Dual, c : Double) -> Dual {
  { val: a.val * c, deriv: a.deriv * c, }
}

///|
/// Power: `(a+a′ε)^n = a^n + n·a^(n−1)·a′·ε` for integer `n`.
pub fn pow_int(a : Dual, n : Int) -> Dual {
  if n == 0 {
    return { val: 1.0, deriv: 0.0, }
  }
  let nd = n.to_double()
  let an = @math.pow(a.val, nd)
  { val: an, deriv: nd * @math.pow(a.val, nd - 1.0) * a.deriv, }
}

///|
/// Power with real exponent: `a^p` where `d/da a^p = p·a^(p−1)`.
pub fn pow(a : Dual, p : Double) -> Dual {
  { val: @math.pow(a.val, p), deriv: p * @math.pow(a.val, p - 1.0) * a.deriv, }
}

// ---------------------------------------------------------------------------
// Elementary functions
// ---------------------------------------------------------------------------

///|
/// `sin(a+a′ε) = sin(a) + cos(a)·a′·ε`.
pub fn sin(a : Dual) -> Dual {
  { val: @math.sin(a.val), deriv: @math.cos(a.val) * a.deriv, }
}

///|
/// `cos(a+a′ε) = cos(a) − sin(a)·a′·ε`.
pub fn cos(a : Dual) -> Dual {
  { val: @math.cos(a.val), deriv: -@math.sin(a.val) * a.deriv, }
}

///|
/// `tan(a+a′ε) = tan(a) + (1 + tan²(a))·a′·ε`.
pub fn tan(a : Dual) -> Dual {
  let t = @math.sin(a.val) / @math.cos(a.val)
  { val: t, deriv: (1.0 + t * t) * a.deriv, }
}

///|
/// `exp(a+a′ε) = exp(a) + exp(a)·a′·ε`.
pub fn exp(a : Dual) -> Dual {
  let e = @math.exp(a.val)
  { val: e, deriv: e * a.deriv, }
}

///|
/// `log(a+a′ε) = log(a) + a′/a · ε` (natural logarithm).
pub fn log(a : Dual) -> Dual {
  { val: @math.ln(a.val), deriv: a.deriv / a.val, }
}

///|
/// `sqrt(a+a′ε) = √a + a′/(2√a) · ε`.
pub fn sqrt(a : Dual) -> Dual {
  let s = a.val.sqrt()
  { val: s, deriv: a.deriv / (2.0 * s), }
}

///|
/// `sinh(a+a′ε) = sinh(a) + cosh(a)·a′·ε`.
pub fn sinh(a : Dual) -> Dual {
  let ea = @math.exp(a.val)
  let ema = @math.exp(-a.val)
  let sh = (ea - ema) / 2.0
  let ch = (ea + ema) / 2.0
  { val: sh, deriv: ch * a.deriv, }
}

///|
/// `cosh(a+a′ε) = cosh(a) + sinh(a)·a′·ε`.
pub fn cosh(a : Dual) -> Dual {
  let ea = @math.exp(a.val)
  let ema = @math.exp(-a.val)
  let sh = (ea - ema) / 2.0
  let ch = (ea + ema) / 2.0
  { val: ch, deriv: sh * a.deriv, }
}

///|
/// `tanh(a+a′ε) = tanh(a) + (1−tanh²(a))·a′·ε`.
pub fn tanh(a : Dual) -> Dual {
  let ea = @math.exp(a.val)
  let ema = @math.exp(-a.val)
  let t = (ea - ema) / (ea + ema)
  { val: t, deriv: (1.0 - t * t) * a.deriv, }
}

///|
/// `abs(a+a′ε) = |a| + sign(a)·a′·ε`.
///
/// The derivative of `|x|` is `sign(x)` for `x ≠ 0`; at `x = 0` the
/// derivative is set to `0` (subgradient convention).
pub fn abs(a : Dual) -> Dual {
  let s = if a.val > 0.0 { 1.0 } else if a.val < 0.0 { -1.0 } else { 0.0 }
  { val: a.val.abs(), deriv: s * a.deriv, }
}

// ---------------------------------------------------------------------------
// Multivariate gradient
// ---------------------------------------------------------------------------

///|
/// Compute the gradient `∇f` of a scalar function `f: ℝⁿ → ℝ` at point `x`.
///
/// Performs `n` forward passes, each seeding one variable's derivative to `1`.
/// Returns an array of `n` partial derivatives.
pub fn gradient(f : (Array[Dual]) -> Dual, x : Array[Double]) -> Array[Double] {
  let n = x.length()
  let result = Array::make(n, 0.0)
  let duals : Array[Dual] = Array::make(n, { val: 0.0, deriv: 0.0, })
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      if j == i {
        duals[j] = { val: x[j], deriv: 1.0, }
      } else {
        duals[j] = { val: x[j], deriv: 0.0, }
      }
    }
    let result_dual = f(duals)
    result[i] = result_dual.deriv
  }
  result
}

///|
/// Compute the directional derivative of `f` at `x` in direction `d`.
///
/// This is a single forward pass: seed each variable with `dᵢ` as the
/// derivative. The result's `val` is `f(x)` and `deriv` is `∇f(x)·d`.
pub fn directional_derivative(
  f : (Array[Dual]) -> Dual,
  x : Array[Double],
  d : Array[Double],
) -> Dual {
  let n = x.length()
  let duals : Array[Dual] = Array::make(n, { val: 0.0, deriv: 0.0, })
  for i = 0; i < n; i = i + 1 {
    duals[i] = { val: x[i], deriv: d[i], }
  }
  f(duals)
}

///|
/// Compute the Jacobian of a vector function `F: ℝⁿ → ℝᵐ`.
///
/// `F` takes an array of `n` duals and returns an array of `m` duals.
/// The Jacobian is an `m × n` matrix stored as `Array[Array[Double]]`
/// (row-major: `jacobian[i][j] = ∂Fᵢ/∂xⱼ`).
pub fn jacobian(
  f : (Array[Dual]) -> Array[Dual],
  x : Array[Double],
) -> Array[Array[Double]] {
  let n = x.length()
  let duals0 : Array[Dual] = Array::make(n, { val: 0.0, deriv: 0.0, })
  for j = 0; j < n; j = j + 1 {
    duals0[j] = { val: x[j], deriv: 0.0, }
  }
  duals0[0] = { val: x[0], deriv: 1.0, }
  let out0 = f(duals0)
  let m = out0.length()
  let jac : Array[Array[Double]] = Array::makei(m, fn(_i) {
    Array::make(n, 0.0)
  })
  for i = 0; i < m; i = i + 1 {
    jac[i][0] = out0[i].deriv
  }
  for j = 1; j < n; j = j + 1 {
    for k = 0; k < n; k = k + 1 {
      duals0[k] = { val: x[k], deriv: if k == j { 1.0 } else { 0.0 }, }
    }
    let out = f(duals0)
    for i = 0; i < m; i = i + 1 {
      jac[i][j] = out[i].deriv
    }
  }
  jac
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "autodiff: basic derivative of x²" {
  let f = fn(x : Dual) -> Dual { mul(x, x) }
  let d = f(variable(3.0))
  assert_true((d.val - 9.0).abs() < 1.0e-15)
  assert_true((d.deriv - 6.0).abs() < 1.0e-15)
}

///|
test "autodiff: derivative of x³" {
  let f = fn(x : Dual) -> Dual { pow_int(x, 3) }
  let d = f(variable(2.0))
  assert_true((d.val - 8.0).abs() < 1.0e-15)
  assert_true((d.deriv - 12.0).abs() < 1.0e-15)
}

///|
test "autodiff: derivative of sin(x)" {
  let d = sin(variable(0.5))
  assert_true((d.val - @math.sin(0.5)).abs() < 1.0e-15)
  assert_true((d.deriv - @math.cos(0.5)).abs() < 1.0e-15)
}

///|
test "autodiff: derivative of exp(x)" {
  let d = exp(variable(1.0))
  assert_true((d.val - @math.exp(1.0)).abs() < 1.0e-15)
  assert_true((d.deriv - @math.exp(1.0)).abs() < 1.0e-15)
}

///|
test "autodiff: derivative of log(x)" {
  let d = log(variable(2.0))
  assert_true((d.val - @math.ln(2.0)).abs() < 1.0e-15)
  assert_true((d.deriv - 0.5).abs() < 1.0e-15)
}

///|
test "autodiff: derivative of sqrt(x)" {
  let d = sqrt(variable(4.0))
  assert_true((d.val - 2.0).abs() < 1.0e-15)
  assert_true((d.deriv - 0.25).abs() < 1.0e-15)
}

///|
test "autodiff: chain rule — sin(x²)" {
  let f = fn(x : Dual) -> Dual { sin(mul(x, x)) }
  let d = f(variable(1.5))
  let expected_val = @math.sin(1.5 * 1.5)
  let expected_deriv = @math.cos(1.5 * 1.5) * 2.0 * 1.5
  assert_true((d.val - expected_val).abs() < 1.0e-15)
  assert_true((d.deriv - expected_deriv).abs() < 1.0e-15)
}

///|
test "autodiff: division derivative" {
  let f = fn(x : Dual) -> Dual { div(add_scalar(x, 1.0), add_scalar(x, -1.0)) }
  let d = f(variable(3.0))
  assert_true((d.val - 2.0).abs() < 1.0e-15)
  assert_true((d.deriv + 0.5).abs() < 1.0e-15)
}

///|
test "autodiff: multivariate gradient" {
  let f = fn(xs : Array[Dual]) -> Dual {
    add(
      add(mul(xs[0], xs[0]), mul_scalar(mul(xs[0], xs[1]), 3.0)),
      mul(xs[1], xs[1]),
    )
  }
  let g = gradient(f, [2.0, 5.0])
  assert_true((g[0] - 19.0).abs() < 1.0e-15)
  assert_true((g[1] - 16.0).abs() < 1.0e-15)
}

///|
test "autodiff: gradient of Rosenbrock-like function" {
  let f = fn(xs : Array[Dual]) -> Dual {
    let dx = add_scalar(neg(xs[0]), 1.0)
    let x2 = mul(xs[0], xs[0])
    let dy = sub(xs[1], x2)
    add(mul(dx, dx), mul_scalar(mul(dy, dy), 100.0))
  }
  let g = gradient(f, [1.0, 1.0])
  assert_true(g[0].abs() < 1.0e-12)
  assert_true(g[1].abs() < 1.0e-12)
}

///|
test "autodiff: gradient of exp(x₁+x₂)" {
  let f = fn(xs : Array[Dual]) -> Dual { exp(add(xs[0], xs[1])) }
  let g = gradient(f, [0.0, 0.0])
  assert_true((g[0] - 1.0).abs() < 1.0e-15)
  assert_true((g[1] - 1.0).abs() < 1.0e-15)
}

///|
test "autodiff: directional derivative" {
  let f = fn(xs : Array[Dual]) -> Dual {
    add(mul(xs[0], xs[0]), mul(xs[1], xs[1]))
  }
  let d = directional_derivative(f, [3.0, 4.0], [1.0, 1.0])
  assert_true((d.val - 25.0).abs() < 1.0e-15)
  assert_true((d.deriv - 14.0).abs() < 1.0e-15)
}

///|
test "autodiff: Jacobian of [x₀², x₀·x₁]" {
  let f = fn(xs : Array[Dual]) -> Array[Dual] {
    [mul(xs[0], xs[0]), mul(xs[0], xs[1])]
  }
  let jac = jacobian(f, [3.0, 5.0])
  assert_true((jac[0][0] - 6.0).abs() < 1.0e-15)
  assert_true((jac[0][1] - 0.0).abs() < 1.0e-15)
  assert_true((jac[1][0] - 5.0).abs() < 1.0e-15)
  assert_true((jac[1][1] - 3.0).abs() < 1.0e-15)
}

///|
test "autodiff: tanh derivative" {
  let d = tanh(variable(0.5))
  let ea = @math.exp(0.5)
  let ema = @math.exp(-0.5)
  let t = (ea - ema) / (ea + ema)
  assert_true((d.val - t).abs() < 1.0e-15)
  assert_true((d.deriv - (1.0 - t * t)).abs() < 1.0e-15)
}

///|
test "autodiff: power with real exponent" {
  let d = pow(variable(4.0), 2.5)
  let expected_val = @math.pow(4.0, 2.5)
  let expected_deriv = 2.5 * @math.pow(4.0, 1.5)
  assert_true((d.val - expected_val).abs() < 1.0e-12)
  assert_true((d.deriv - expected_deriv).abs() < 1.0e-12)
}

///|
test "autodiff: constant has zero derivative" {
  let c = constant(42.0)
  assert_true((c.val - 42.0).abs() < 1.0e-15)
  assert_true(c.deriv.abs() < 1.0e-15)
}

///|
test "autodiff: 3D gradient" {
  let f = fn(xs : Array[Dual]) -> Dual { mul(mul(xs[0], xs[1]), xs[2]) }
  let g = gradient(f, [2.0, 3.0, 4.0])
  assert_true((g[0] - 12.0).abs() < 1.0e-15)
  assert_true((g[1] - 8.0).abs() < 1.0e-15)
  assert_true((g[2] - 6.0).abs() < 1.0e-15)
}

///|
test "autodiff: sinh derivative" {
  let d = sinh(variable(1.0))
  let ea = @math.exp(1.0)
  let ema = @math.exp(-1.0)
  let sh = (ea - ema) / 2.0
  let ch = (ea + ema) / 2.0
  assert_true((d.val - sh).abs() < 1.0e-15)
  assert_true((d.deriv - ch).abs() < 1.0e-15)
}

///|
test "autodiff: cosh derivative" {
  let d = cosh(variable(1.0))
  let ea = @math.exp(1.0)
  let ema = @math.exp(-1.0)
  let sh = (ea - ema) / 2.0
  let ch = (ea + ema) / 2.0
  assert_true((d.val - ch).abs() < 1.0e-15)
  assert_true((d.deriv - sh).abs() < 1.0e-15)
}
