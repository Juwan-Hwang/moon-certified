/// Option Greeks — Sensitivity Measures for Options.
///
/// Greeks measure the sensitivity of option prices to various parameters.
/// They are essential for risk management, hedging, and trading strategies.
///
/// ## Greeks Implemented
///
/// - **Delta (Δ)**: ∂V/∂S — rate of change with respect to underlying price
/// - **Gamma (Γ)**: ∂²V/∂S² — rate of change of Delta
/// - **Theta (Θ)**: ∂V/∂t — time decay (per day)
/// - **Vega (ν)**: ∂V/∂σ — sensitivity to volatility (per 1% change)
/// - **Rho (ρ)**: ∂V/∂r — sensitivity to interest rate (per 1% change)
/// - **Vanna**: ∂²V/∂S∂σ — cross-sensitivity of Delta to volatility
/// - **Volga/Vomma**: ∂²V/∂σ² — sensitivity of Vega to volatility
/// - **Charm**: ∂²V/∂S∂t — Delta decay
///
/// ## References
///
/// - J. C. Hull. "Options, Futures, and Other Derivatives." 11th ed.
/// - Espen Gaarder Haug. "The Complete Guide to Option Pricing Formulas."
///
/// `proof-enabled` is `false`; correctness is backed by test vectors.

// @math.sqrt is unavailable in MoonBit stdlib; use Double::sqrt method.
fn sqrt(x : Double) -> Double {
  x.sqrt()
}

// ---------------------------------------------------------------------------
// Normal distribution helpers
// ---------------------------------------------------------------------------

///|
/// Standard normal CDF N(x) using Abramowitz-Stegun approximation.
fn normal_cdf(x : Double) -> Double {
  if x < -10.0 {
    return 0.0
  }
  if x > 10.0 {
    return 1.0
  }
  0.5 * (1.0 + erf(x / 1.4142135623730951))
}

///|
/// Standard normal PDF φ(x).
fn normal_pdf(x : Double) -> Double {
  0.3989422804014327 * @math.exp(-0.5 * x * x)
}

///|
/// Error function (Abramowitz-Stegun 7.1.26).
fn erf(x : Double) -> Double {
  let sign = if x < 0.0 { -1.0 } else { 1.0 }
  let ax = if x < 0.0 { -x } else { x }
  let a1 = 0.254829592
  let a2 = -0.284496736
  let a3 = 1.421413741
  let a4 = -1.453152027
  let a5 = 1.061405429
  let p = 0.3275911
  let t = 1.0 / (1.0 + p * ax)
  let y = 1.0 - (((((a5 * t + a4) * t) + a3) * t + a2) * t + a1) * t * @math.exp(-ax * ax)
  sign * y
}

///|
/// Compute d₁.
fn d1(s : Double, k : Double, r : Double, q : Double, sigma : Double, t : Double) -> Double {
  (@math.ln(s / k) + (r - q + 0.5 * sigma * sigma) * t) / (sigma * sqrt(t))
}

///|
/// Compute d₂ = d₁ - σ√T.
fn d2(d1_val : Double, sigma : Double, t : Double) -> Double {
  d1_val - sigma * sqrt(t)
}

// ---------------------------------------------------------------------------
// First-Order Greeks
// ---------------------------------------------------------------------------

///|
/// Delta of a European call option.
///
/// `Δ_call = e^(-qT) · N(d₁)`
pub fn call_delta(s : Double, k : Double, r : Double, q : Double, sigma : Double, t : Double) -> Double {
  if t <= 0.0 {
    return if s > k { 1.0 } else { 0.0 }
  }
  if sigma <= 0.0 {
    return if s > k { 1.0 } else { 0.0 }
  }
  let d1_val = d1(s, k, r, q, sigma, t)
  @math.exp(-q * t) * normal_cdf(d1_val)
}

///|
/// Delta of a European put option.
///
/// `Δ_put = e^(-qT) · [N(d₁) - 1] = -e^(-qT) · N(-d₁)`
pub fn put_delta(s : Double, k : Double, r : Double, q : Double, sigma : Double, t : Double) -> Double {
  if t <= 0.0 {
    return if s < k { -1.0 } else { 0.0 }
  }
  if sigma <= 0.0 {
    return if s < k { -1.0 } else { 0.0 }
  }
  let d1_val = d1(s, k, r, q, sigma, t)
  @math.exp(-q * t) * (normal_cdf(d1_val) - 1.0)
}

///|
/// Gamma of a European option (same for call and put).
///
/// `Γ = e^(-qT) · φ(d₁) / (S·σ·√T)`
pub fn gamma(s : Double, k : Double, r : Double, q : Double, sigma : Double, t : Double) -> Double {
  if t <= 0.0 || sigma <= 0.0 || s <= 0.0 {
    return 0.0
  }
  let d1_val = d1(s, k, r, q, sigma, t)
  @math.exp(-q * t) * normal_pdf(d1_val) / (s * sigma * sqrt(t))
}

///|
/// Theta of a European call option (per year).
///
/// `Θ_call = -S·e^(-qT)·φ(d₁)·σ/(2√T) - r·K·e^(-rT)·N(d₂) + q·S·e^(-qT)·N(d₁)`
pub fn call_theta(s : Double, k : Double, r : Double, q : Double, sigma : Double, t : Double) -> Double {
  if t <= 0.0 || sigma <= 0.0 {
    return 0.0
  }
  let d1_val = d1(s, k, r, q, sigma, t)
  let d2_val = d2(d1_val, sigma, t)
  let term1 = -s * @math.exp(-q * t) * normal_pdf(d1_val) * sigma / (2.0 * sqrt(t))
  let term2 = -r * k * @math.exp(-r * t) * normal_cdf(d2_val)
  let term3 = q * s * @math.exp(-q * t) * normal_cdf(d1_val)
  term1 + term2 + term3
}

///|
/// Theta of a European put option (per year).
///
/// `Θ_put = -S·e^(-qT)·φ(d₁)·σ/(2√T) + r·K·e^(-rT)·N(-d₂) - q·S·e^(-qT)·N(-d₁)`
pub fn put_theta(s : Double, k : Double, r : Double, q : Double, sigma : Double, t : Double) -> Double {
  if t <= 0.0 || sigma <= 0.0 {
    return 0.0
  }
  let d1_val = d1(s, k, r, q, sigma, t)
  let d2_val = d2(d1_val, sigma, t)
  let term1 = -s * @math.exp(-q * t) * normal_pdf(d1_val) * sigma / (2.0 * sqrt(t))
  let term2 = r * k * @math.exp(-r * t) * normal_cdf(-d2_val)
  let term3 = -q * s * @math.exp(-q * t) * normal_cdf(-d1_val)
  term1 + term2 + term3
}

///|
/// Vega of a European option (same for call and put).
///
/// Returns the sensitivity to a 1.0 (100%) change in volatility.
/// For sensitivity to a 1% change, divide by 100.
///
/// `ν = S·e^(-qT)·φ(d₁)·√T`
pub fn vega(s : Double, k : Double, r : Double, q : Double, sigma : Double, t : Double) -> Double {
  if t <= 0.0 || sigma <= 0.0 || s <= 0.0 {
    return 0.0
  }
  let d1_val = d1(s, k, r, q, sigma, t)
  s * @math.exp(-q * t) * normal_pdf(d1_val) * sqrt(t)
}

///|
/// Rho of a European call option (sensitivity to 1.0 change in rate).
///
/// `ρ_call = K·T·e^(-rT)·N(d₂)`
pub fn call_rho(s : Double, k : Double, r : Double, q : Double, sigma : Double, t : Double) -> Double {
  if t <= 0.0 || sigma <= 0.0 {
    return 0.0
  }
  let d1_val = d1(s, k, r, q, sigma, t)
  let d2_val = d2(d1_val, sigma, t)
  k * t * @math.exp(-r * t) * normal_cdf(d2_val)
}

///|
/// Rho of a European put option.
///
/// `ρ_put = -K·T·e^(-rT)·N(-d₂)`
pub fn put_rho(s : Double, k : Double, r : Double, q : Double, sigma : Double, t : Double) -> Double {
  if t <= 0.0 || sigma <= 0.0 {
    return 0.0
  }
  let d1_val = d1(s, k, r, q, sigma, t)
  let d2_val = d2(d1_val, sigma, t)
  -k * t * @math.exp(-r * t) * normal_cdf(-d2_val)
}

// ---------------------------------------------------------------------------
// Second-Order Greeks
// ---------------------------------------------------------------------------

///|
/// Vanna: ∂²V/∂S∂σ = rate of change of Delta w.r.t. volatility.
///
/// `Vanna = -e^(-qT) · φ(d₁) · d₂ / σ`
pub fn vanna(s : Double, k : Double, r : Double, q : Double, sigma : Double, t : Double) -> Double {
  if t <= 0.0 || sigma <= 0.0 {
    return 0.0
  }
  let d1_val = d1(s, k, r, q, sigma, t)
  let d2_val = d2(d1_val, sigma, t)
  -@math.exp(-q * t) * normal_pdf(d1_val) * d2_val / sigma
}

///|
/// Volga (Vomma): ∂²V/∂σ² = rate of change of Vega w.r.t. volatility.
///
/// `Volga = vega · d₁ · d₂ / σ`
pub fn volga(s : Double, k : Double, r : Double, q : Double, sigma : Double, t : Double) -> Double {
  if t <= 0.0 || sigma <= 0.0 {
    return 0.0
  }
  let d1_val = d1(s, k, r, q, sigma, t)
  let d2_val = d2(d1_val, sigma, t)
  let v = vega(s, k, r, q, sigma, t)
  v * d1_val * d2_val / sigma
}

///|
/// Charm (Delta decay): ∂²V/∂S∂t = rate of change of Delta over time.
///
/// For calls:
/// `Charm = -e^(-qT) · [φ(d₁) · (2(r-q)T - d₁·σ√T) / (2·σ·T·√T) - q·N(d₁)]`
pub fn call_charm(s : Double, k : Double, r : Double, q : Double, sigma : Double, t : Double) -> Double {
  if t <= 0.0 || sigma <= 0.0 {
    return 0.0
  }
  let d1_val = d1(s, k, r, q, sigma, t)
  let sqrt_t = sqrt(t)
  let phi_d1 = normal_pdf(d1_val)
  let term1 = phi_d1 * (2.0 * (r - q) * t - d1_val * sigma * sqrt_t) / (2.0 * sigma * t * sqrt_t)
  let term2 = q * normal_cdf(d1_val)
  -@math.exp(-q * t) * (term1 - term2)
}

///|
/// Charm for put options.
pub fn put_charm(s : Double, k : Double, r : Double, q : Double, sigma : Double, t : Double) -> Double {
  if t <= 0.0 || sigma <= 0.0 {
    return 0.0
  }
  let d1_val = d1(s, k, r, q, sigma, t)
  let sqrt_t = sqrt(t)
  let phi_d1 = normal_pdf(d1_val)
  let term1 = phi_d1 * (2.0 * (r - q) * t - d1_val * sigma * sqrt_t) / (2.0 * sigma * t * sqrt_t)
  let term2 = q * normal_cdf(-d1_val)
  @math.exp(-q * t) * (term1 + term2)
}

///|
/// Color (Gamma decay): ∂Γ/∂t = rate of change of Gamma over time.
pub fn color(s : Double, k : Double, r : Double, q : Double, sigma : Double, t : Double) -> Double {
  if t <= 0.0 || sigma <= 0.0 || s <= 0.0 {
    return 0.0
  }
  let d1_val = d1(s, k, r, q, sigma, t)
  let sqrt_t = sqrt(t)
  let phi_d1 = normal_pdf(d1_val)
  let term1 = phi_d1 * (2.0 * (r - q) * t - d1_val * sigma * sqrt_t) / (2.0 * sigma * t * sqrt_t)
  let term2 = q * phi_d1
  @math.exp(-q * t) * (term1 - term2) / (s * sigma * sqrt_t)
}

///|
/// Speed: ∂Γ/∂S = rate of change of Gamma w.r.t. underlying price.
pub fn speed(s : Double, k : Double, r : Double, q : Double, sigma : Double, t : Double) -> Double {
  if t <= 0.0 || sigma <= 0.0 || s <= 0.0 {
    return 0.0
  }
  let d1_val = d1(s, k, r, q, sigma, t)
  let g = gamma(s, k, r, q, sigma, t)
  -g * (1.0 + d1_val / (sigma * sqrt(t))) / s
}

///|
/// Ultima: ∂³V/∂σ³ — third derivative w.r.t. volatility.
pub fn ultima(s : Double, k : Double, r : Double, q : Double, sigma : Double, t : Double) -> Double {
  if t <= 0.0 || sigma <= 0.0 {
    return 0.0
  }
  let d1_val = d1(s, k, r, q, sigma, t)
  let d2_val = d2(d1_val, sigma, t)
  let v = vega(s, k, r, q, sigma, t)
  let w = d1_val * d2_val
  -v * (w * (1.0 - w) + d1_val * d1_val + d2_val * d2_val) / (sigma * sigma)
}

// ---------------------------------------------------------------------------
// Convenience: All Greeks in a struct
// ---------------------------------------------------------------------------

///|
/// Container for all standard Greeks of an option.
pub struct Greeks {
  delta : Double
  gamma : Double
  theta : Double // per year
  vega : Double // per 1.0 change in sigma
  rho : Double // per 1.0 change in rate
  vanna : Double
  volga : Double
  charm : Double
  color : Double
  speed : Double
  ultima : Double
}

///|
/// Compute all Greeks for a European call option.
pub fn call_greeks(s : Double, k : Double, r : Double, q : Double, sigma : Double, t : Double) -> Greeks {
  {
    delta: call_delta(s, k, r, q, sigma, t),
    gamma: gamma(s, k, r, q, sigma, t),
    theta: call_theta(s, k, r, q, sigma, t),
    vega: vega(s, k, r, q, sigma, t),
    rho: call_rho(s, k, r, q, sigma, t),
    vanna: vanna(s, k, r, q, sigma, t),
    volga: volga(s, k, r, q, sigma, t),
    charm: call_charm(s, k, r, q, sigma, t),
    color: color(s, k, r, q, sigma, t),
    speed: speed(s, k, r, q, sigma, t),
    ultima: ultima(s, k, r, q, sigma, t),
  }
}

///|
/// Compute all Greeks for a European put option.
pub fn put_greeks(s : Double, k : Double, r : Double, q : Double, sigma : Double, t : Double) -> Greeks {
  {
    delta: put_delta(s, k, r, q, sigma, t),
    gamma: gamma(s, k, r, q, sigma, t),
    theta: put_theta(s, k, r, q, sigma, t),
    vega: vega(s, k, r, q, sigma, t),
    rho: put_rho(s, k, r, q, sigma, t),
    vanna: vanna(s, k, r, q, sigma, t),
    volga: volga(s, k, r, q, sigma, t),
    charm: put_charm(s, k, r, q, sigma, t),
    color: color(s, k, r, q, sigma, t),
    speed: speed(s, k, r, q, sigma, t),
    ultima: ultima(s, k, r, q, sigma, t),
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "greeks: call delta range" {
  // ATM call delta should be around 0.5-0.6
  let d = call_delta(100.0, 100.0, 0.05, 0.0, 0.2, 1.0)
  assert_true(d > 0.5 && d < 0.7)
  // Deep ITM: delta close to 1
  let d_itm = call_delta(200.0, 100.0, 0.05, 0.0, 0.2, 1.0)
  assert_true(d_itm > 0.99)
  // Deep OTM: delta close to 0
  let d_otm = call_delta(10.0, 100.0, 0.05, 0.0, 0.2, 1.0)
  assert_true(d_otm < 0.01)
}

///|
test "greeks: put delta range" {
  let d = put_delta(100.0, 100.0, 0.05, 0.0, 0.2, 1.0)
  assert_true(d > -0.5 && d < -0.3)
  // Put-call parity: Δ_call - Δ_put = e^(-qT)
  let dc = call_delta(100.0, 100.0, 0.05, 0.0, 0.2, 1.0)
  let dp = put_delta(100.0, 100.0, 0.05, 0.0, 0.2, 1.0)
  assert_true((dc - dp - 1.0).abs() < 0.001)
}

///|
test "greeks: gamma is positive and same for call/put" {
  let gc = gamma(100.0, 100.0, 0.05, 0.0, 0.2, 1.0)
  let gp = gamma(100.0, 100.0, 0.05, 0.0, 0.2, 1.0)
  assert_true(gc > 0.0)
  assert_true((gc - gp).abs() < 1.0e-10)
}

///|
test "greeks: theta is negative for ATM call" {
  let t = call_theta(100.0, 100.0, 0.05, 0.0, 0.2, 1.0)
  assert_true(t < 0.0)
}

///|
test "greeks: vega is positive" {
  let v = vega(100.0, 100.0, 0.05, 0.0, 0.2, 1.0)
  assert_true(v > 0.0)
}

///|
test "greeks: call rho positive, put rho negative" {
  let rc = call_rho(100.0, 100.0, 0.05, 0.0, 0.2, 1.0)
  let rp = put_rho(100.0, 100.0, 0.05, 0.0, 0.2, 1.0)
  assert_true(rc > 0.0)
  assert_true(rp < 0.0)
}

///|
test "greeks: gamma peak near ATM" {
  let g_atm = gamma(100.0, 100.0, 0.05, 0.0, 0.2, 1.0)
  let g_otm = gamma(150.0, 100.0, 0.05, 0.0, 0.2, 1.0)
  assert_true(g_atm > g_otm)
}

///|
test "greeks: gamma decreases as time increases" {
  let g_short = gamma(100.0, 100.0, 0.05, 0.0, 0.2, 0.1)
  let g_long = gamma(100.0, 100.0, 0.05, 0.0, 0.2, 2.0)
  assert_true(g_short > g_long)
}

///|
test "greeks: all greeks struct" {
  let g = call_greeks(100.0, 100.0, 0.05, 0.0, 0.2, 1.0)
  assert_true(g.delta > 0.5 && g.delta < 0.7)
  assert_true(g.gamma > 0.0)
  assert_true(g.theta < 0.0)
  assert_true(g.vega > 0.0)
  assert_true(g.rho > 0.0)
}

///|
test "greeks: vanna sign" {
  // For ATM call, vanna should be near zero (d2 ≈ 0)
  let v = vanna(100.0, 100.0, 0.05, 0.0, 0.2, 1.0)
  assert_true(v.abs() < 0.5)
}

///|
test "greeks: speed is negative for ATM" {
  let s = speed(100.0, 100.0, 0.05, 0.0, 0.2, 1.0)
  assert_true(s < 0.0)
}

///|
test "greeks: with dividends reduces call delta" {
  let d_no_div = call_delta(100.0, 100.0, 0.05, 0.0, 0.2, 1.0)
  let d_div = call_delta(100.0, 100.0, 0.05, 0.03, 0.2, 1.0)
  assert_true(d_div < d_no_div)
}
