/// Heston Stochastic Volatility Model.
///
/// The Heston model (Heston 1993) extends Black-Scholes by modeling the
/// variance as a mean-reverting Cox-Ingersoll-Ross (CIR) process:
///
/// ```text
/// dS(t) = (r-q)·S·dt + √v(t)·S·dW₁(t)
/// dv(t) = κ(θ - v(t))·dt + σ·√v(t)·dW₂(t)
/// ```
///
/// where:
/// - `S` = asset price, `v` = instantaneous variance (σ²)
/// - `κ` = mean reversion speed of variance
/// - `θ` = long-run variance mean
/// - `σ` = volatility of variance ("vol of vol")
/// - `ρ` = correlation between Brownian motions W₁ and W₂
///
/// ## Features
///
/// - **Semi-analytical European option pricing** via Fourier inversion
///   (Heston's original characteristic function with "Little Trap" fix)
/// - **Full Monte Carlo simulation** with the Quadratic-Exponential (QE)
///   discretization scheme (Andersen 2008) — the industry-standard
///   variance discretization that preserves non-negativity and avoids
///   the "leaking" bias of log-Euler schemes
/// - **Exact log-asset integration** conditional on the variance path
///   (Andersen's eq. 24), eliminating discretization bias in the asset
///   price conditional on the variance
/// - **Risk-neutral drift** adjustment (q = dividend yield, r = risk-free rate)
/// - **Feller condition** check (2κθ > σ²) with warning documentation
///
/// ## References
///
/// - Heston, S. L. (1993). "A Closed-Form Solution for Options with
///   Stochastic Volatility with Applications to Bond and Currency Options."
///   The Review of Financial Studies, 6(2), 327–343.
/// - Andersen, L. (2008). "Simple and Efficient Simulation of the
///   Heston Stochastic Volatility Model." Journal of Computational Finance,
///   11(3), 1–42.
/// - Albrecher, H., Mayer, P., Schoutens, W., Tistaert, J. (2007).
///   "The Little Heston Trap." Wilmott Magazine.
///
/// `proof-enabled` is `false`.

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

///|
/// Heston model parameters.
pub struct HestonParams {
  /// Initial variance v₀ (= σ₀², NOT volatility).
  v0 : Double
  /// Mean reversion speed κ (> 0).
  kappa : Double
  /// Long-run variance mean θ (> 0).
  theta : Double
  /// Volatility of variance σ (> 0).
  sigma : Double
  /// Correlation ρ ∈ (-1, 1) between asset and variance Brownian motions.
  rho : Double
  /// Risk-free interest rate r (continuous, annualized).
  r : Double
  /// Dividend yield q (continuous, annualized).
  q : Double
}

///|
/// Create Heston parameters with validation.
///
/// Enforces:
/// - `v0 > 0`, `kappa > 0`, `theta > 0`, `sigma > 0`
/// - `|rho| < 1` (strict; ±1 causes degenerate CF)
/// - `r >= 0`, `q >= 0`
///
/// Returns a warning string if the Feller condition (2κθ > σ²) is violated,
/// which means the variance process can reach zero. This does not invalidate
/// pricing but may reduce Monte Carlo accuracy.
pub fn params(
  v0 : Double,
  kappa : Double,
  theta : Double,
  sigma : Double,
  rho : Double,
  r : Double,
  q : Double,
) -> (HestonParams, String) {
  let p = {
    v0: if v0 < 0.0 {
      0.0001
    } else {
      v0
    },
    kappa: if kappa < 0.0 {
      0.0001
    } else {
      kappa
    },
    theta: if theta < 0.0 {
      0.0001
    } else {
      theta
    },
    sigma: if sigma < 0.0 {
      0.0001
    } else {
      sigma
    },
    rho: if rho > 0.999 {
      0.999
    } else if rho < -0.999 {
      -0.999
    } else {
      rho
    },
    r: if r < 0.0 {
      0.0
    } else {
      r
    },
    q: if q < 0.0 {
      0.0
    } else {
      q
    },
  }
  let warning = if 2.0 * kappa * theta <= sigma * sigma {
    "Warning: Feller condition (2*kappa*theta > sigma^2) not satisfied. Variance process may reach zero. Monte Carlo accuracy may be reduced."
  } else {
    ""
  }
  (p, warning)
}

// ---------------------------------------------------------------------------
// Complex number helpers (for characteristic function)
// ---------------------------------------------------------------------------

///|
priv struct Complex {
  re : Double
  im : Double
}

///|
fn c_add(a : Complex, b : Complex) -> Complex {
  Complex::{ re: a.re + b.re, im: a.im + b.im, }
}

///|
fn c_sub(a : Complex, b : Complex) -> Complex {
  Complex::{ re: a.re - b.re, im: a.im - b.im, }
}

///|
fn c_mul(a : Complex, b : Complex) -> Complex {
  Complex::{ re: a.re * b.re - a.im * b.im, im: a.re * b.im + a.im * b.re, }
}

///|
fn c_div(a : Complex, b : Complex) -> Complex {
  let denom = b.re * b.re + b.im * b.im
  Complex::{
    re: (a.re * b.re + a.im * b.im) / denom,
    im: (a.im * b.re - a.re * b.im) / denom,
  }
}

///|
fn c_exp(a : Complex) -> Complex {
  let e = @math.exp(a.re)
  Complex::{ re: e * @math.cos(a.im), im: e * @math.sin(a.im), }
}

///|
fn c_log(a : Complex) -> Complex {
  let r = (a.re * a.re + a.im * a.im).sqrt()
  Complex::{ re: @math.ln(r), im: @math.atan2(a.im, a.re), }
}

///|
fn c_sqrt(a : Complex) -> Complex {
  let r = (a.re * a.re + a.im * a.im).sqrt()
  let theta = @math.atan2(a.im, a.re) / 2.0
  let s = r.sqrt()
  Complex::{ re: s * @math.cos(theta), im: s * @math.sin(theta), }
}

///|
fn c_scalar_mul(s : Double, a : Complex) -> Complex {
  Complex::{ re: s * a.re, im: s * a.im, }
}

///|
fn c_from_real(x : Double) -> Complex {
  Complex::{ re: x, im: 0.0, }
}

// ---------------------------------------------------------------------------
// Heston Characteristic Function (Heston 1993, "Little Trap" form)
// ---------------------------------------------------------------------------

///|
/// Heston characteristic function φ(u; τ) = E[exp(i·u·ln S(τ))].
///
/// Uses the "Little Trap" formulation (Albrecher et al. 2007) to avoid
/// numerical instabilities from the complex logarithm branch cut.
fn heston_cf(
  u : Double,
  s0 : Double,
  v0 : Double,
  tau : Double,
  p : HestonParams,
) -> Complex {
  let i_unit = Complex::{ re: 0.0, im: 1.0, }
  // d = sqrt((kappa - i*rho*sigma*u)^2 + (u^2 + i*u)*sigma^2)
  let term1 = Complex::{ re: p.kappa, im: -p.rho * p.sigma * u, }
  let term1_sq = c_mul(term1, term1)
  let term2 = c_scalar_mul(p.sigma * p.sigma, Complex::{ re: u * u, im: u, })
  let d = c_sqrt(c_add(term1_sq, term2))
  // numer = kappa - i*rho*sigma*u - d
  let numer = Complex::{ re: p.kappa - d.re, im: -p.rho * p.sigma * u - d.im, }
  // denom = kappa - i*rho*sigma*u + d
  let denom = Complex::{ re: p.kappa + d.re, im: -p.rho * p.sigma * u + d.im, }
  let g2 = c_div(numer, denom)
  let exp_term = c_exp(c_scalar_mul(tau, numer))
  let one = c_from_real(1.0)
  // D = numer / sigma^2 * (1 - exp(numer*tau)) / (1 - g2*exp(numer*tau))
  let d_num = c_scalar_mul(1.0 / (p.sigma * p.sigma), numer)
  let d_frac_num = c_sub(one, exp_term)
  let d_frac_den = c_sub(one, c_mul(g2, exp_term))
  let d_val = c_mul(d_num, c_div(d_frac_num, d_frac_den))
  // C = (r-q)*i*u*tau + kappa*theta/sigma^2 * (numer*tau - 2*ln((1-g2*exp)/(1-g2)))
  let c_drift = c_scalar_mul((p.r - p.q) * u * tau, i_unit)
  let c_coeff = p.kappa * p.theta / (p.sigma * p.sigma)
  let c_log_arg = c_div(c_sub(one, c_mul(g2, exp_term)), c_sub(one, g2))
  let c_log = c_log(c_log_arg)
  let c_val = c_add(
    c_drift,
    c_scalar_mul(
      c_coeff,
      c_sub(c_scalar_mul(tau, numer), c_scalar_mul(2.0, c_log)),
    ),
  )
  // phi = exp(C + D*v0 + i*u*ln(S0))
  let exponent = c_add(
    c_add(c_val, c_scalar_mul(v0, d_val)),
    c_scalar_mul(u * @math.ln(s0), i_unit),
  )
  c_exp(exponent)
}

///|
/// Characteristic function evaluated at complex argument (u - i) for P1.
fn heston_cf_complex_shift(
  u : Double,
  s0 : Double,
  v0 : Double,
  tau : Double,
  p : HestonParams,
) -> Complex {
  // Evaluate CF at z = u - i (real part = u, imag part = -1)
  // kappa - i*rho*sigma*z = kappa - i*rho*sigma*(u-i) = kappa - rho*sigma - i*rho*sigma*u
  let t1 = Complex::{ re: p.kappa - p.rho * p.sigma, im: -p.rho * p.sigma * u, }
  let t1_sq = c_mul(t1, t1)
  // (z^2 + i*z) * sigma^2 = (u^2 - iu) * sigma^2
  let t2 = c_scalar_mul(p.sigma * p.sigma, Complex::{ re: u * u, im: -u, })
  let d = c_sqrt(c_add(t1_sq, t2))
  // numer = kappa - rho*sigma - i*rho*sigma*u - d
  let numer = Complex::{
    re: p.kappa - p.rho * p.sigma - d.re,
    im: -p.rho * p.sigma * u - d.im,
  }
  let denom = Complex::{
    re: p.kappa - p.rho * p.sigma + d.re,
    im: -p.rho * p.sigma * u + d.im,
  }
  let g2 = c_div(numer, denom)
  let exp_term = c_exp(c_scalar_mul(tau, numer))
  let one = c_from_real(1.0)
  let d_num = c_scalar_mul(1.0 / (p.sigma * p.sigma), numer)
  let d_frac_num = c_sub(one, exp_term)
  let d_frac_den = c_sub(one, c_mul(g2, exp_term))
  let d_val = c_mul(d_num, c_div(d_frac_num, d_frac_den))
  // i*z = iu + 1
  let c_drift = c_scalar_mul((p.r - p.q) * tau, Complex::{ re: 1.0, im: u, })
  let c_coeff = p.kappa * p.theta / (p.sigma * p.sigma)
  let c_log_arg = c_div(c_sub(one, c_mul(g2, exp_term)), c_sub(one, g2))
  let c_log = c_log(c_log_arg)
  let c_val = c_add(
    c_drift,
    c_scalar_mul(
      c_coeff,
      c_sub(c_scalar_mul(tau, numer), c_scalar_mul(2.0, c_log)),
    ),
  )
  // phi = exp(C + D*v0 + (iu+1)*ln(S0))
  let ln_s0 = @math.ln(s0)
  let exponent = c_add(c_add(c_val, c_scalar_mul(v0, d_val)), Complex::{
    re: ln_s0,
    im: u * ln_s0,
  })
  c_exp(exponent)
}

// ---------------------------------------------------------------------------
// European Option Pricing via Fourier Inversion
// ---------------------------------------------------------------------------

///|
/// Price a European option under the Heston model using semi-analytical
/// Fourier inversion (Heston 1993, Carr-Madan 1999, Gil-Pelaez).
///
/// Uses 10,000 integration points over [0, 200] with the trapezoidal rule.
///
/// ## Parameters
///
/// - `s0`: Spot price
/// - `strike`: Strike price
/// - `tau`: Time to maturity (years)
/// - `p`: Heston parameters
/// - `call`: `true` for call, `false` for put
pub fn price_european(
  s0 : Double,
  strike : Double,
  tau : Double,
  p : HestonParams,
  call : Bool,
) -> Double {
  let upper = 200.0
  let n_points = 10000
  let du = upper / n_points.to_double()
  let ln_strike = @math.ln(strike)
  let mut sum_p2 = 0.0
  let mut sum_p1 = 0.0
  for j = 1; j < n_points; j = j + 1 {
    let u = j.to_double() * du
    let phi = heston_cf(u, s0, p.v0, tau, p)
    // e^{-iu*ln(K)} = cos(u*ln_K) - i*sin(u*ln_K)
    let e_term = Complex::{
      re: @math.cos(u * ln_strike),
      im: -@math.sin(u * ln_strike),
    }
    // phi * e_term / (iu) = (phi * e_term) * (-i/u)
    let integrand = c_mul(phi, e_term)
    let integrand = Complex::{ re: integrand.im / u, im: -integrand.re / u, }
    sum_p2 = sum_p2 + integrand.re
    // P1 uses φ(u-i)
    let phi_umi = heston_cf_complex_shift(u, s0, p.v0, tau, p)
    let integrand1 = c_mul(phi_umi, e_term)
    let scale = s0 * @math.exp((p.r - p.q) * tau) * u
    let integrand1 = Complex::{
      re: integrand1.im / scale,
      im: -integrand1.re / scale,
    }
    sum_p1 = sum_p1 + integrand1.re
  }
  let p2 = 0.5 + sum_p2 * du / @math.PI
  let p1 = 0.5 + sum_p1 * du / @math.PI
  let call_price = s0 * @math.exp(-p.q * tau) * p1 -
    strike * @math.exp(-p.r * tau) * p2
  if call {
    call_price
  } else {
    call_price - s0 * @math.exp(-p.q * tau) + strike * @math.exp(-p.r * tau)
  }
}

// ---------------------------------------------------------------------------
// Monte Carlo Simulation with QE Discretization (Andersen 2008)
// ---------------------------------------------------------------------------

///|
/// Deterministic PRNG (xorshift64) for reproducible Monte Carlo.
fn next_rand(state : FixedArray[UInt64]) -> Double {
  let mut x = state[0]
  x = x ^ (x << 13)
  x = x ^ (x >> 7)
  x = x ^ (x << 17)
  state[0] = x
  (x >> 11).to_double() / 9007199254740992.0
}

///|
/// Box-Muller transform: standard normal from two uniforms.
fn next_gaussian(state : FixedArray[UInt64]) -> Double {
  let u1 = next_rand(state)
  let u2 = next_rand(state)
  let u1 = if u1 < 1.0e-300 { 1.0e-300 } else { u1 }
  (-2.0 * @math.ln(u1)).sqrt() * @math.cos(2.0 * @math.PI * u2)
}

///|
/// Inverse CDF of the exponential distribution with mean `mean`.
///
/// F^{-1}(u) = -mean * ln(1 - u)
fn exponential_inv_cdf(u : Double, mean : Double) -> Double {
  let u = if u >= 1.0 { 0.9999999999999999 } else { u }
  let u = if u <= 0.0 { 1.0e-300 } else { u }
  -mean * @math.ln(1.0 - u)
}

///|
/// QE discretization for the variance process (Andersen 2008, §3.2).
///
/// Given v(t), produces v(t+dt) with the correct conditional distribution.
///
/// The scheme has two regimes:
/// - **ψ ≤ ψ_c** (quadratic): v(t+dt) = a·(b + Z)² where Z ~ N(0,1)
/// - **ψ > ψ_c** (exponential): v(t+dt) is drawn from a mixture of a
///   point mass at 0 (prob p) and an exponential distribution
///
/// where ψ = s²/m² is the ratio of variance to squared mean of v(t+dt).
fn qe_discretize(
  v : Double,
  dt : Double,
  p : HestonParams,
  z_v : Double,
  u : Double,
) -> Double {
  // Conditional mean and variance of v(t+dt) given v(t)
  // (exact moments of the CIR process, Andersen eq. 22-23)
  let exp_neg_kdt = @math.exp(-p.kappa * dt)
  let m = p.theta + (v - p.theta) * exp_neg_kdt
  let s2 = v * p.sigma * p.sigma * exp_neg_kdt * (1.0 - exp_neg_kdt) / p.kappa +
    p.theta *
    p.sigma *
    p.sigma *
    (1.0 - exp_neg_kdt) *
    (1.0 - exp_neg_kdt) /
    (2.0 * p.kappa)
  // ψ = s² / m²
  let psi = s2 / (m * m)
  // Critical threshold (Andersen recommends ψ_c ∈ [1, 2], default 1.5)
  let psi_c = 1.5
  if psi <= psi_c {
    // Quadratic transformation: v = a*(b + Z)^2
    let two_over_psi = 2.0 / psi
    let b2 = two_over_psi - 1.0 + (two_over_psi * (two_over_psi - 1.0)).sqrt()
    let b = b2.sqrt()
    let a = m / (1.0 + b2)
    a * (b + z_v) * (b + z_v)
  } else {
    // Exponential transformation: mixture of point mass at 0 and exponential
    let p_prob = (psi - 1.0) / (psi + 1.0)
    let beta = (1.0 - p_prob) / m
    if u > p_prob {
      // Draw from exponential with rate β
      exponential_inv_cdf((u - p_prob) / (1.0 - p_prob), 1.0 / beta)
    } else {
      0.0
    }
  }
}

///|
/// Price a European option via Monte Carlo simulation using the
/// Quadratic-Exponential (QE) scheme (Andersen 2008).
///
/// This is the industry-standard Heston Monte Carlo discretization:
/// - **Variance**: QE scheme with quadratic/exponential branching (§3.2)
/// - **Asset price**: Exact integration conditional on variance path (§3.2.4)
///
/// ## Parameters
///
/// - `s0`: Spot price
/// - `strike`: Strike price
/// - `tau`: Time to maturity (years)
/// - `p`: Heston parameters
/// - `n_steps`: Number of time steps per path
/// - `n_paths`: Number of Monte Carlo paths
/// - `call`: `true` for call, `false` for put
/// - `seed`: Random seed
pub fn price_monte_carlo(
  s0 : Double,
  strike : Double,
  tau : Double,
  p : HestonParams,
  n_steps : Int,
  n_paths : Int,
  call : Bool,
  seed : UInt64,
) -> Double {
  let dt = tau / n_steps.to_double()
  let state : FixedArray[UInt64] = FixedArray::make(1, seed)
  // Warm up PRNG
  for i = 0; i < 8; i = i + 1 {
    let _ = next_rand(state)
  }
  let mut total_payoff = 0.0
  let discount = @math.exp(-p.r * tau)
  let ln_s0 = @math.ln(s0)
  for path = 0; path < n_paths; path = path + 1 {
    let mut v = p.v0
    let mut ln_s = ln_s0
    for step = 0; step < n_steps; step = step + 1 {
      // Generate correlated randoms:
      // Z_v drives variance, Z' is independent, asset uses Z' directly
      let z_v = next_gaussian(state)
      let z_indep = next_gaussian(state)
      // Uniform for QE exponential branch
      let u_qe = next_rand(state)
      // QE discretization for variance
      let v_new = qe_discretize(v, dt, p, z_v, u_qe)
      // Exact log-asset integration (Andersen eq. 24):
      // ln(S_{t+dt}) = ln(S_t) + (r-q-0.5*v)*dt
      //   + rho/sigma * (v_new - v - kappa*(theta-v)*dt)
      //   + sqrt((1-rho^2)*v*dt) * Z'
      ln_s = ln_s +
        (p.r - p.q - 0.5 * v) * dt +
        p.rho / p.sigma * (v_new - v - p.kappa * (p.theta - v) * dt) +
        ((1.0 - p.rho * p.rho) * v * dt).sqrt() * z_indep
      v = v_new
    }
    let s_tau = @math.exp(ln_s)
    let payoff = if call {
      if s_tau > strike {
        s_tau - strike
      } else {
        0.0
      }
    } else if strike > s_tau {
      strike - s_tau
    } else {
      0.0
    }
    total_payoff = total_payoff + payoff
  }
  discount * total_payoff / n_paths.to_double()
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "heston: params validation clamps values" {
  let (p, warning) = params(0.04, 2.0, 0.04, 0.3, 0.5, 0.03, 0.0)
  assert_true(p.v0 > 0.0)
  assert_true(p.kappa > 0.0)
  assert_true(p.theta > 0.0)
  assert_true(p.sigma > 0.0)
  assert_true(p.rho > -1.0 && p.rho < 1.0)
  assert_true(warning == "")
}

///|
test "heston: Feller condition warning" {
  let (p, warning) = params(0.04, 0.5, 0.04, 0.5, 0.0, 0.03, 0.0)
  // 2*0.5*0.04 = 0.04 < 0.25 = 0.5^2, Feller condition violated
  assert_true(warning != "")
  assert_true(p.v0 > 0.0)
}

///|
test "heston: call price positive and reasonable" {
  let (p, _) = params(0.04, 2.0, 0.04, 0.3, -0.7, 0.03, 0.0)
  let price = price_european(100.0, 100.0, 1.0, p, true)
  assert_true(price > 0.0)
  assert_true(price > 3.0 && price < 20.0)
}

///|
test "heston: put price positive and reasonable" {
  let (p, _) = params(0.04, 2.0, 0.04, 0.3, -0.7, 0.03, 0.0)
  let price = price_european(100.0, 100.0, 1.0, p, false)
  assert_true(price > 0.0)
  assert_true(price > 3.0 && price < 20.0)
}

///|
test "heston: put-call parity holds" {
  let (p, _) = params(0.04, 2.0, 0.04, 0.3, -0.7, 0.03, 0.0)
  let call = price_european(100.0, 100.0, 1.0, p, true)
  let put = price_european(100.0, 100.0, 1.0, p, false)
  // Put-call parity: C - P = S*e^{-qT} - K*e^{-rT}
  let parity = call -
    put -
    100.0 * @math.exp(-0.0 * 1.0) +
    100.0 * @math.exp(-0.03 * 1.0)
  assert_true(parity.abs() < 0.5)
}

///|
test "heston: ITM call > OTM call" {
  let (p, _) = params(0.04, 2.0, 0.04, 0.3, -0.7, 0.03, 0.0)
  let itm = price_european(100.0, 80.0, 1.0, p, true)
  let otm = price_european(100.0, 120.0, 1.0, p, true)
  assert_true(itm > otm)
}

///|
test "heston: higher vol increases option price" {
  let (p_low, _) = params(0.01, 2.0, 0.01, 0.1, -0.5, 0.03, 0.0)
  let (p_high, _) = params(0.09, 2.0, 0.09, 0.3, -0.5, 0.03, 0.0)
  let price_low = price_european(100.0, 100.0, 1.0, p_low, true)
  let price_high = price_european(100.0, 100.0, 1.0, p_high, true)
  assert_true(price_high > price_low)
}

///|
test "heston: Monte Carlo approximates semi-analytical price" {
  let (p, _) = params(0.04, 2.0, 0.04, 0.3, -0.7, 0.03, 0.0)
  let mc_price = price_monte_carlo(100.0, 100.0, 1.0, p, 200, 50000, true, 42UL)
  let sa_price = price_european(100.0, 100.0, 1.0, p, true)
  // MC with QE scheme should be within 10% of semi-analytical price
  let diff = (mc_price - sa_price).abs() / sa_price
  assert_true(diff < 0.10)
}

///|
test "heston: deterministic output for same seed" {
  let (p, _) = params(0.04, 2.0, 0.04, 0.3, -0.7, 0.03, 0.0)
  let price1 = price_monte_carlo(100.0, 100.0, 1.0, p, 100, 10000, true, 42UL)
  let price2 = price_monte_carlo(100.0, 100.0, 1.0, p, 100, 10000, true, 42UL)
  assert_true((price1 - price2).abs() < 1.0e-10)
}

///|
test "heston: zero rate gives zero drift" {
  let (p, _) = params(0.04, 2.0, 0.04, 0.3, 0.0, 0.0, 0.0)
  let call = price_european(100.0, 100.0, 1.0, p, true)
  let put = price_european(100.0, 100.0, 1.0, p, false)
  // With r=q=0, put-call parity: C = P
  assert_true((call - put).abs() < 0.5)
}

///|
test "heston: complex number arithmetic" {
  let a = Complex::{ re: 3.0, im: 4.0, }
  let b = Complex::{ re: 1.0, im: 2.0, }
  let sum = c_add(a, b)
  assert_true((sum.re - 4.0).abs() < 1.0e-10)
  assert_true((sum.im - 6.0).abs() < 1.0e-10)
  let prod = c_mul(a, b)
  assert_true((prod.re - (3.0 * 1.0 - 4.0 * 2.0)).abs() < 1.0e-10)
  let div = c_div(a, b)
  // (3+4i)/(1+2i) = (11-2i)/5
  assert_true((div.re - 2.2).abs() < 1.0e-10)
  assert_true((div.im - -0.4).abs() < 1.0e-10)
  let e = c_exp(Complex::{ re: 0.0, im: @math.PI, })
  assert_true((e.re + 1.0).abs() < 1.0e-10)
  assert_true(e.im.abs() < 1.0e-10)
}

///|
test "heston: QE variance stays non-negative" {
  let (p, _) = params(0.04, 2.0, 0.04, 0.3, -0.7, 0.03, 0.0)
  // Run many paths and check variance never goes negative
  let dt = 1.0 / 100.0
  let state : FixedArray[UInt64] = FixedArray::make(1, 42UL)
  for i = 0; i < 8; i = i + 1 {
    let _ = next_rand(state)
  }
  let mut all_nonneg = true
  for path = 0; path < 1000; path = path + 1 {
    let mut v = p.v0
    for step = 0; step < 100; step = step + 1 {
      let z_v = next_gaussian(state)
      let _ = next_gaussian(state)
      let u_qe = next_rand(state)
      v = qe_discretize(v, dt, p, z_v, u_qe)
      if v < 0.0 {
        all_nonneg = false
      }
    }
  }
  assert_true(all_nonneg)
}

///|
test "heston: Monte Carlo put price reasonable" {
  let (p, _) = params(0.04, 2.0, 0.04, 0.3, -0.7, 0.03, 0.0)
  let mc_put = price_monte_carlo(100.0, 100.0, 1.0, p, 200, 50000, false, 42UL)
  assert_true(mc_put > 0.0)
  assert_true(mc_put < 20.0)
}
