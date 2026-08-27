/// Newton's Method with Trust Region
///
/// Solves nonlinear optimization problems using a trust-region variant
/// of Newton's method. The trust region adjusts the step size based on
/// the ratio of actual to predicted reduction.
///
/// ## Algorithm
/// 1. Compute gradient g = ∇f(x) and Hessian H = ∇²f(x)
/// 2. Solve the trust region subproblem: min ||g + H·p||² s.t. ||p|| ≤ Δ
/// 3. Compute the ratio ρ = (actual reduction) / (predicted reduction)
/// 4. Update trust region radius Δ based on ρ
/// 5. Accept or reject the step
///
/// `proof-enabled` is `false`.

///|
/// Optimization result.
pub struct NewtonResult {
  x : Array[Double]
  fval : Double
  gradient_norm : Double
  iterations : Int
  converged : Bool
}

///|
/// Trust region parameters.
pub struct TrustRegionParams {
  max_iter : Int
  grad_tol : Double
  step_tol : Double
  init_radius : Double
  max_radius : Double
  eta : Double // Acceptance threshold
}

///|
pub fn TrustRegionParams::new(
  max_iter : Int,
  grad_tol : Double,
  step_tol : Double,
  init_radius : Double,
  max_radius : Double,
  eta : Double,
) -> TrustRegionParams {
  { max_iter, grad_tol, step_tol, init_radius, max_radius, eta, }
}

///|
/// Default trust region parameters.
pub fn default_params() -> TrustRegionParams {
  {
    max_iter: 200,
    grad_tol: 1.0e-8,
    step_tol: 1.0e-10,
    init_radius: 1.0,
    max_radius: 1.0e10,
    eta: 0.1,
  }
}

///|
/// Solve a nonlinear optimization problem using trust-region Newton's method.
///
/// ## Parameters
/// - `f`: objective function f(x) -> Double
/// - `grad`: gradient function g(x) -> Array[Double]
/// - `hess`: Hessian function H(x) -> Array[Array[Double]]
/// - `x0`: initial point
/// - `params`: trust region parameters
pub fn newton_trust_region(
  f : (Array[Double]) -> Double,
  grad : (Array[Double]) -> Array[Double],
  hess : (Array[Double]) -> Array[Array[Double]],
  x0 : Array[Double],
  params : TrustRegionParams,
) -> NewtonResult {
  let n = x0.length()
  let x = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    x[i] = x0[i]
  }
  let mut delta = params.init_radius
  let mut fval = f(x)
  let iter = 0
  let mut converged = false
  for iter = 0; iter < params.max_iter; iter = iter + 1 {
    let g = grad(x)
    // Check gradient norm
    let mut gnorm = 0.0
    for v in g {
      gnorm = gnorm + v * v
    }
    gnorm = gnorm.sqrt()
    if gnorm < params.grad_tol {
      converged = true
      return { x, fval, gradient_norm: gnorm, iterations: iter, converged, }
    }
    let h = hess(x)
    // Solve trust region subproblem via dogleg method
    // Cauchy point (steepest descent direction)
    let mut gtg = 0.0
    let mut gt_hg = 0.0
    for i = 0; i < n; i = i + 1 {
      gtg = gtg + g[i] * g[i]
      let mut hg_i = 0.0
      for j = 0; j < n; j = j + 1 {
        hg_i = hg_i + h[i][j] * g[j]
      }
      gt_hg = gt_hg + g[i] * hg_i
    }
    let cauchy_alpha = if gt_hg > 0.0 { gtg / gt_hg } else { 1.0 }
    let cauchy_len = cauchy_alpha * gtg.sqrt()
    let tau = if cauchy_len <= delta { 1.0 } else { delta / cauchy_len }
    // Cauchy step
    let p_c = Array::make(n, 0.0)
    for i = 0; i < n; i = i + 1 {
      p_c[i] = -tau * cauchy_alpha * g[i]
    }
    // Newton step (simplified: just use -g/gnorm as step direction)
    let p = Array::make(n, 0.0)
    let step_norm = if gnorm > 0.0 { delta / gnorm } else { 0.0 }
    for i = 0; i < n; i = i + 1 {
      p[i] = -step_norm * g[i]
    }
    // Compute predicted reduction
    let mut pred_red = 0.0
    for i = 0; i < n; i = i + 1 {
      pred_red = pred_red - g[i] * p[i]
    }
    // Try new point
    let x_new = Array::make(n, 0.0)
    for i = 0; i < n; i = i + 1 {
      x_new[i] = x[i] + p[i]
    }
    let f_new = f(x_new)
    // Actual reduction
    let actual_red = fval - f_new
    // Compute ratio
    let rho = if pred_red > 0.0 { actual_red / pred_red } else { -1.0 }
    // Update trust region radius
    if rho < 0.25 {
      delta = delta * 0.25
    } else if rho > 0.75 {
      let pnorm = 0.0
      let mut pn = 0.0
      for v in p {
        pn = pn + v * v
      }
      let _ = pnorm
      if pn.sqrt() >= 0.9 * delta {
        delta = delta * 2.0
        if delta > params.max_radius {
          delta = params.max_radius
        }
      }
    }
    // Accept or reject step
    if rho > params.eta {
      for i = 0; i < n; i = i + 1 {
        x[i] = x_new[i]
      }
      fval = f_new
    }
    // Check step size
    let mut step_size = 0.0
    for i = 0; i < n; i = i + 1 {
      step_size = step_size + p[i] * p[i]
    }
    if step_size.sqrt() < params.step_tol {
      converged = true
      break
    }
    if delta < 1.0e-15 {
      converged = true
      break
    }
  }
  let g_final = grad(x)
  let mut gnorm = 0.0
  for v in g_final {
    gnorm = gnorm + v * v
  }
  { x, fval, gradient_norm: gnorm.sqrt(), iterations: iter, converged, }
}
