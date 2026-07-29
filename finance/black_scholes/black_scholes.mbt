/// Black-Scholes Option Pricing Model.
///
/// The Black-Scholes-Merton model is the industry standard for pricing
/// European-style options. It provides closed-form analytical solutions
/// for call and put options on non-dividend-paying stocks, and the
/// generalized Merton extension handles continuous dividend yields.
///
/// ## Model Assumptions
///
/// - European exercise (exercise only at expiry)
/// - Log-normal stock price distribution
/// - Constant volatility and risk-free rate
/// - No transaction costs or taxes
/// - Continuous trading
///
/// ## Formulas
///
/// ### Call (no dividend):
/// `C = S·N(d₁) - K·e^(-rT)·N(d₂)`
///
/// ### Put (no dividend):
/// `P = K·e^(-rT)·N(-d₂) - S·N(-d₁)`
///
/// ### With continuous dividend yield q:
/// `d₁ = [@math.ln(S/K) + (r - q + σ²/2)T] / (σ√T)`
/// `d₂ = d₁ - σ√T`
///
/// ## References
///
/// - F. Black, M. Scholes. "The Pricing of Options and Corporate
///   Liabilities." Journal of Political Economy, 1973.
/// - R. C. Merton. "Theory of Rational Option Pricing." Bell Journal
///   of Economics, 1973.
/// - J. C. Hull. "Options, Futures, and Other Derivatives." 11th ed.
///
/// `proof-enabled` is `false`; correctness is backed by test vectors.

// @math.sqrt is unavailable in MoonBit stdlib; use Double::sqrt method.
fn sqrt(x : Double) -> Double {
  x.sqrt()
}

// ---------------------------------------------------------------------------
// Normal distribution CDF (using error function approximation)
// ---------------------------------------------------------------------------

///|
/// Standard normal CDF N(x) using the Abramowitz-Stegun approximation.
///
/// N(x) = 0.5 · (1 + erf(x / √2))
///
/// The erf approximation has maximum absolute error < 7.5×10⁻⁸,
/// sufficient for option pricing to sub-cent precision.
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
/// Error function using Abramowitz-Stegun formula 7.1.26.
///
/// Maximum absolute error: 1.5×10⁻⁷.
fn erf(x : Double) -> Double {
  let sign = if x < 0.0 { -1.0 } else { 1.0 }
  let ax = if x < 0.0 { -x } else { x }
  // Constants
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
/// Standard normal PDF φ(x).
fn normal_pdf(x : Double) -> Double {
  0.3989422804014327 * @math.exp(-0.5 * x * x)
}

// ---------------------------------------------------------------------------
// d₁ and d₂
// ---------------------------------------------------------------------------

///|
/// Compute d₁ for the Black-Scholes formula.
///
/// `d₁ = [@math.ln(S/K) + (r - q + σ²/2)T] / (σ√T)`
fn d1(
  s : Double,
  k : Double,
  r : Double,
  q : Double,
  sigma : Double,
  t : Double,
) -> Double {
  let numerator = @math.ln(s / k) + (r - q + 0.5 * sigma * sigma) * t
  let denominator = sigma * sqrt(t)
  numerator / denominator
}

///|
/// Compute d₂ = d₁ - σ√T.
fn d2(d1_val : Double, sigma : Double, t : Double) -> Double {
  d1_val - sigma * sqrt(t)
}

// ---------------------------------------------------------------------------
// Public API: European Option Pricing
// ---------------------------------------------------------------------------

///|
/// Price a European call option using Black-Scholes-Merton.
///
/// - `s`: Spot price of the underlying asset.
/// - `k`: Strike price.
/// - `r`: Risk-free interest rate (annualized, continuously compounded).
/// - `q`: Continuous dividend yield (annualized). Use 0.0 for no dividends.
/// - `sigma`: Volatility of the underlying (annualized, e.g. 0.2 for 20%).
/// - `t`: Time to maturity in years.
///
/// Returns the call option price.
pub fn call_price(
  s : Double,
  k : Double,
  r : Double,
  q : Double,
  sigma : Double,
  t : Double,
) -> Double {
  if t <= 0.0 {
    // At expiry: max(S - K, 0)
    return (s - k).max(0.0)
  }
  if sigma <= 0.0 {
    // No volatility: option value is discounted intrinsic value
    let intrinsic = s * @math.exp(-q * t) - k * @math.exp(-r * t)
    return intrinsic.max(0.0)
  }
  let d1_val = d1(s, k, r, q, sigma, t)
  let d2_val = d2(d1_val, sigma, t)
  s * @math.exp(-q * t) * normal_cdf(d1_val) - k * @math.exp(-r * t) * normal_cdf(d2_val)
}

///|
/// Price a European put option using Black-Scholes-Merton.
///
/// - `s`: Spot price of the underlying asset.
/// - `k`: Strike price.
/// - `r`: Risk-free interest rate (annualized, continuously compounded).
/// - `q`: Continuous dividend yield (annualized). Use 0.0 for no dividends.
/// - `sigma`: Volatility of the underlying (annualized).
/// - `t`: Time to maturity in years.
///
/// Returns the put option price.
pub fn put_price(
  s : Double,
  k : Double,
  r : Double,
  q : Double,
  sigma : Double,
  t : Double,
) -> Double {
  if t <= 0.0 {
    return (k - s).max(0.0)
  }
  if sigma <= 0.0 {
    let intrinsic = k * @math.exp(-r * t) - s * @math.exp(-q * t)
    return intrinsic.max(0.0)
  }
  let d1_val = d1(s, k, r, q, sigma, t)
  let d2_val = d2(d1_val, sigma, t)
  k * @math.exp(-r * t) * normal_cdf(-d2_val) - s * @math.exp(-q * t) * normal_cdf(-d1_val)
}

// ---------------------------------------------------------------------------
// Put-Call Parity
// ---------------------------------------------------------------------------

///|
/// Verify put-call parity: C - P = S·e^(-qT) - K·e^(-rT).
///
/// Returns the parity violation (should be ≈ 0 for European options).
pub fn put_call_parity_check(
  call : Double,
  put : Double,
  s : Double,
  k : Double,
  r : Double,
  q : Double,
  t : Double,
) -> Double {
  call - put - (s * @math.exp(-q * t) - k * @math.exp(-r * t))
}

// ---------------------------------------------------------------------------
// Implied Volatility (Newton-Raphson)
// ---------------------------------------------------------------------------

///|
/// Compute implied volatility from a market call price using Newton-Raphson.
///
/// - `market_price`: Observed market call price.
/// - `s`, `k`, `r`, `q`, `t`: As in `call_price`.
/// - `initial_guess`: Initial volatility guess (e.g. 0.2).
/// - `max_iter`: Maximum Newton-Raphson iterations.
/// - `tolerance`: Convergence tolerance.
///
/// Returns the implied volatility, or `None` if convergence fails.
pub fn implied_volatility_call(
  market_price : Double,
  s : Double,
  k : Double,
  r : Double,
  q : Double,
  t : Double,
  initial_guess : Double,
  max_iter : Int,
  tolerance : Double,
) -> Double? {
  if t <= 0.0 || s <= 0.0 || k <= 0.0 {
    return None
  }
  let mut sigma = if initial_guess > 0.0 { initial_guess } else { 0.2 }
  for iter = 0; iter < max_iter; iter = iter + 1 {
    let price = call_price(s, k, r, q, sigma, t)
    let diff = price - market_price
    if diff.abs() < tolerance {
      return Some(sigma)
    }
    // Vega = S·e^(-qT)·φ(d₁)·√T
    let d1_val = d1(s, k, r, q, sigma, t)
    let vega = s * @math.exp(-q * t) * normal_pdf(d1_val) * sqrt(t)
    if vega < 1.0e-15 {
      return None
    }
    sigma = sigma - diff / vega
    if sigma <= 0.0 {
      sigma = 0.001
    }
    if sigma > 10.0 {
      return None
    }
  }
  None
}

///|
/// Compute implied volatility from a market put price using Newton-Raphson.
pub fn implied_volatility_put(
  market_price : Double,
  s : Double,
  k : Double,
  r : Double,
  q : Double,
  t : Double,
  initial_guess : Double,
  max_iter : Int,
  tolerance : Double,
) -> Double? {
  if t <= 0.0 || s <= 0.0 || k <= 0.0 {
    return None
  }
  let mut sigma = if initial_guess > 0.0 { initial_guess } else { 0.2 }
  for iter = 0; iter < max_iter; iter = iter + 1 {
    let price = put_price(s, k, r, q, sigma, t)
    let diff = price - market_price
    if diff.abs() < tolerance {
      return Some(sigma)
    }
    let d1_val = d1(s, k, r, q, sigma, t)
    let vega = s * @math.exp(-q * t) * normal_pdf(d1_val) * sqrt(t)
    if vega < 1.0e-15 {
      return None
    }
    sigma = sigma - diff / vega
    if sigma <= 0.0 {
      sigma = 0.001
    }
    if sigma > 10.0 {
      return None
    }
  }
  None
}

// ---------------------------------------------------------------------------
// Binomial Tree (CRR) for American Options
// ---------------------------------------------------------------------------

///|
/// Price an American call option using the Cox-Ross-Rubinstein (CRR)
/// binomial tree model.
///
/// American calls on non-dividend-paying stocks are never exercised early,
/// so this gives the same result as European. For dividend-paying stocks,
/// early exercise may be optimal, and the binomial tree handles this.
///
/// - `steps`: Number of binomial tree steps (more steps = higher accuracy).
pub fn american_call(
  s : Double,
  k : Double,
  r : Double,
  q : Double,
  sigma : Double,
  t : Double,
  steps : Int,
) -> Double {
  if steps < 1 {
    return call_price(s, k, r, q, sigma, t)
  }
  let dt = t / steps.to_double()
  let u = @math.exp(sigma * sqrt(dt))
  let d = 1.0 / u
  let p = (@math.exp((r - q) * dt) - d) / (u - d)
  let disc = @math.exp(-r * dt)
  // Initialize option values at expiry
  let n = steps + 1
  let values : Array[Double] = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    let st = s * @math.pow(u, i.to_double()) * @math.pow(d, (steps - i).to_double())
    values[i] = (st - k).max(0.0)
  }
  // Backward induction
  for step = steps - 1; step >= 0; step = step - 1 {
    for i = 0; i <= step; i = i + 1 {
      let cont = disc * (p * values[i + 1] + (1.0 - p) * values[i])
      let st = s * @math.pow(u, i.to_double()) * @math.pow(d, (step - i).to_double())
      values[i] = (cont).max((st - k).max(0.0))
    }
  }
  values[0]
}

///|
/// Price an American put option using the CRR binomial tree model.
pub fn american_put(
  s : Double,
  k : Double,
  r : Double,
  q : Double,
  sigma : Double,
  t : Double,
  steps : Int,
) -> Double {
  if steps < 1 {
    return put_price(s, k, r, q, sigma, t)
  }
  let dt = t / steps.to_double()
  let u = @math.exp(sigma * sqrt(dt))
  let d = 1.0 / u
  let p = (@math.exp((r - q) * dt) - d) / (u - d)
  let disc = @math.exp(-r * dt)
  let n = steps + 1
  let values : Array[Double] = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    let st = s * @math.pow(u, i.to_double()) * @math.pow(d, (steps - i).to_double())
    values[i] = (k - st).max(0.0)
  }
  for step = steps - 1; step >= 0; step = step - 1 {
    for i = 0; i <= step; i = i + 1 {
      let cont = disc * (p * values[i + 1] + (1.0 - p) * values[i])
      let st = s * @math.pow(u, i.to_double()) * @math.pow(d, (step - i).to_double())
      values[i] = (cont).max((k - st).max(0.0))
    }
  }
  values[0]
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "black_scholes: call price zero volatility" {
  // With σ=0, call = S·e^(-qT) - K·e^(-rT)
  let c = call_price(100.0, 100.0, 0.05, 0.0, 0.0, 1.0)
  let expected = 100.0 - 100.0 * @math.exp(-0.05)
  assert_true((c - expected).abs() < 1.0e-8)
}

///|
test "black_scholes: put price zero volatility" {
  let p = put_price(100.0, 100.0, 0.05, 0.0, 0.0, 1.0)
  // With σ=0, put = max(K·e^(-rT) - S·e^(-qT), 0)
  let expected = (100.0 * @math.exp(-0.05) - 100.0).max(0.0)
  assert_true((p - expected).abs() < 1.0e-8)
}

///|
test "black_scholes: put-call parity" {
  let s = 100.0
  let k = 105.0
  let r = 0.05
  let q = 0.02
  let sigma = 0.3
  let t = 0.5
  let c = call_price(s, k, r, q, sigma, t)
  let p = put_price(s, k, r, q, sigma, t)
  let violation = put_call_parity_check(c, p, s, k, r, q, t)
  assert_true(violation.abs() < 1.0e-8)
}

///|
test "black_scholes: call at expiry" {
  let c = call_price(105.0, 100.0, 0.05, 0.0, 0.2, 0.0)
  assert_true((c - 5.0).abs() < 1.0e-10)
  let c2 = call_price(95.0, 100.0, 0.05, 0.0, 0.2, 0.0)
  assert_true(c2.abs() < 1.0e-10)
}

///|
test "black_scholes: put at expiry" {
  let p = put_price(95.0, 100.0, 0.05, 0.0, 0.2, 0.0)
  assert_true((p - 5.0).abs() < 1.0e-10)
}

///|
test "black_scholes: known values" {
  // S=100, K=100, r=5%, q=0, σ=20%, T=1
  // C ≈ 10.4506, P ≈ 5.5735
  let c = call_price(100.0, 100.0, 0.05, 0.0, 0.2, 1.0)
  assert_true((c - 10.4506).abs() < 0.01)
  let p = put_price(100.0, 100.0, 0.05, 0.0, 0.2, 1.0)
  assert_true((p - 5.5735).abs() < 0.01)
}

///|
test "black_scholes: with dividends" {
  // S=100, K=100, r=5%, q=3%, σ=20%, T=1
  let c = call_price(100.0, 100.0, 0.05, 0.03, 0.2, 1.0)
  // With dividends, call is cheaper
  let c_no_div = call_price(100.0, 100.0, 0.05, 0.0, 0.2, 1.0)
  assert_true(c < c_no_div)
}

///|
test "black_scholes: implied volatility recovery" {
  let sigma = 0.3
  let price = call_price(100.0, 100.0, 0.05, 0.0, sigma, 1.0)
  let iv = match implied_volatility_call(price, 100.0, 100.0, 0.05, 0.0, 1.0, 0.2, 100, 1.0e-10) {
    None => -1.0
    Some(v) => v
  }
  assert_true((iv - sigma).abs() < 1.0e-6)
}

///|
test "black_scholes: american vs european put" {
  // American put should be >= European put (early exercise premium)
  let euro = put_price(100.0, 100.0, 0.05, 0.0, 0.2, 1.0)
  let amer = american_put(100.0, 100.0, 0.05, 0.0, 0.2, 1.0, 500)
  assert_true(amer >= euro - 0.01)
}

///|
test "black_scholes: american call no dividend equals european" {
  // American call on non-div stock = European call
  let euro = call_price(100.0, 100.0, 0.05, 0.0, 0.2, 1.0)
  let amer = american_call(100.0, 100.0, 0.05, 0.0, 0.2, 1.0, 500)
  assert_true((amer - euro).abs() < 0.05)
}

///|
test "black_scholes: deep ITM/OTM" {
  // Deep ITM call (S >> K)
  let c_itm = call_price(200.0, 100.0, 0.05, 0.0, 0.2, 1.0)
  let intrinsic_itm = 200.0 - 100.0 * @math.exp(-0.05)
  assert_true((c_itm - intrinsic_itm).abs() < 1.0)
  // Deep OTM call (S << K)
  let c_otm = call_price(10.0, 100.0, 0.05, 0.0, 0.2, 1.0)
  assert_true(c_otm < 0.01)
}
