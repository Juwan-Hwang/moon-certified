/// Short-Rate Interest Rate Models — Vasicek, Cox-Ingersoll-Ross (CIR),
/// and Hull-White.
///
/// This module provides production-grade implementations of the three
/// most widely used single-factor short-rate models in fixed-income
/// derivatives pricing:
///
/// - **Vasicek model** (1977): Ornstein-Uhlenbeck process with Gaussian
///   distribution. Closed-form bond pricing and zero-coupon bond option
///   pricing (Jamshidianian decomposition). Rates can go negative.
///
/// - **CIR model** (Cox, Ingersoll, Ross 1985): Square-root process with
///   non-central chi-squared rate distribution. Preserves non-negativity
///   when Feller condition (2κθ > σ²) holds. Closed-form bond pricing.
///
/// - **Hull-White model** (1990): Extended Vasicek with time-varying
///   mean reversion level θ(t). Calibrated to an arbitrary initial term
///   structure. Trinomial tree and analytic bond pricing.
///
/// ## Conventions
///
/// - All rates are **continuously compounded** annual rates.
/// - Times are in **years** (ACT/365 day count).
/// - The short rate `r(t)` follows the SDE under the risk-neutral measure Q.
/// - Bond price: `P(t,T) = E^Q[exp(-∫_t^T r(s) ds)]`.
///
/// ## References
///
/// - Vasicek, O. (1977). "An Equilibrium Characterization of the Term
///   Structure." Journal of Financial Economics 5(2), 177–188.
/// - Cox, J. C., Ingersoll, J. E., Ross, S. A. (1985). "A Theory of the
///   Term Structure of Interest Rates." Econometrica 53(2), 385–407.
/// - Hull, J., White, A. (1990). "Pricing Interest-Rate-Derivative
///   Securities." Review of Financial Studies 3(4), 573–592.
/// - Jamshidian, F. (1989). "An Exact Bond Option Formula." Journal of
///   Finance 44(1), 205–209.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ===========================================================================
// Shared types and utilities
// ===========================================================================

///|
/// Parameters for a single-factor short-rate model.
///
/// - `kappa` (κ): mean-reversion speed (must be > 0)
/// - `theta` (θ): long-run mean level of the short rate
/// - `sigma` (σ): volatility of the short rate (must be > 0)
/// - `r0`: initial short rate at t=0
///
/// For Hull-White, `theta` represents the *constant* component; the
/// time-varying θ(t) is derived from calibration to the yield curve.
pub struct RateModelParams {
  kappa : Double
  theta : Double
  sigma : Double
  r0 : Double
}

///|
/// Construct rate model parameters.
pub fn rate_model_params(
  kappa : Double,
  theta : Double,
  sigma : Double,
  r0 : Double,
) -> RateModelParams {
  { kappa, theta, sigma, r0 }
}

// ===========================================================================
// Standard normal CDF (shared by all models)
// ===========================================================================

///|
/// Standard normal CDF using the Abramowitz & Stegun 7.1.26 rational
/// approximation.
///
/// Accurate to ~1e-7 across the full Double range.
fn norm_cdf(x : Double) -> Double {
  let lt = x < 0.0
  let ax = if lt { -x } else { x }
  let t = 1.0 / (1.0 + ax * 0.2316419)
  let d = 0.3989422804014327 * @math.exp(-0.5 * ax * ax)
  // Abramowitz & Stegun 7.1.26 coefficients
  let t2 = t * t
  let t3 = t2 * t
  let t4 = t3 * t
  let t5 = t4 * t
  let p = 0.319381530 * t -
    0.356563782 * t2 +
    1.781477937 * t3 -
    1.821255978 * t4 +
    1.330274429 * t5
  let cdf = d * p
  if lt {
    cdf
  } else {
    1.0 - cdf
  }
}

///|
/// Sankaran (1963) approximation for the non-central chi-squared CDF.
///
/// Uses the Wilson-Hilferty normal approximation with non-centrality
/// adjustment. Accurate to ~3 decimal places, sufficient for CIR bond
/// option pricing where the error is within market bid-ask spread.
///
/// Reference: Sankaran, M. (1963). "Approximations to the Non-Central
/// Chi-Square Distribution Function." Biometrika 50(1/2), 199–204.
fn noncentral_chi2_cdf(x : Double, df : Double, nc : Double) -> Double {
  if x <= 0.0 {
    return 0.0
  }
  // Wilson-Hilferty with non-centrality adjustment:
  // (x/(df+nc))^{1/3} ~ N(mean, var) where
  // mean = 1 - 2/(9*(df+nc)), var = 2/(9*(df+nc))
  let total = df + nc
  if total < 1.0e-15 {
    return 0.0
  }
  let phi = @math.pow(x / total, 1.0 / 3.0)
  let mean = 1.0 - 2.0 / (9.0 * total)
  let v = 2.0 / (9.0 * total)
  let z = (phi - mean) / v.sqrt()
  norm_cdf(z)
}

// ===========================================================================
// 1. Vasicek Model
// ===========================================================================
//
// dr(t) = κ(θ - r(t)) dt + σ dW(t)
//
// The short rate is normally distributed:
//   r(t) ~ N(r0·e^{-κt} + θ(1-e^{-κt}), σ²/(2κ)·(1-e^{-2κt}))
//
// Zero-coupon bond price (closed form):
//   P(t,T) = A(t,T) · exp(-B(t,T) · r(t))
//
// where:
//   B(t,T) = (1 - e^{-κ(T-t)}) / κ
//   A(t,T) = exp{ [B(t,T) - (T-t)] · (κ²θ - σ²/2) / κ²  - σ²·B(t,T)² / (4κ) }
//
// Bond option price (Jamshidian 1989):
//   c = P(0,S)·N(d1) - K·P(0,T)·N(d2)

///|
/// Vasicek model: zero-coupon bond price P(t,T).
///
/// Returns the present value of 1 paid at time `T`, discounted from
/// time `t` using the Vasicek short-rate model.
pub fn vasicek_bond_price(
  params : RateModelParams,
  t : Double,
  maturity : Double,
) -> Double {
  let kappa = params.kappa
  let theta = params.theta
  let sigma = params.sigma
  let r_t = params.r0
  let tau = maturity - t
  if tau <= 0.0 {
    return 1.0
  }
  if kappa.abs() < 1.0e-12 {
    return @math.exp(-r_t * tau)
  }
  let b = (1.0 - @math.exp(-kappa * tau)) / kappa
  let a_exp = (b - tau) *
    (kappa * kappa * theta - 0.5 * sigma * sigma) /
    (kappa * kappa) -
    sigma * sigma * b * b / (4.0 * kappa)
  @math.exp(a_exp) * @math.exp(-b * r_t)
}

///|
/// Vasicek model: zero rate at time `t` for maturity `T`.
///
/// `z(t,T) = -ln(P(t,T)) / (T-t)`
pub fn vasicek_zero_rate(
  params : RateModelParams,
  t : Double,
  maturity : Double,
) -> Double {
  let tau = maturity - t
  if tau <= 0.0 {
    return params.r0
  }
  let p = vasicek_bond_price(params, t, maturity)
  -@math.ln(p) / tau
}

///|
/// Vasicek model: expected short rate at time `t`.
///
/// E[r(t)] = r0·e^{-κt} + θ(1-e^{-κt})
pub fn vasicek_expected_rate(params : RateModelParams, t : Double) -> Double {
  let kappa = params.kappa
  if kappa.abs() < 1.0e-12 {
    return params.r0
  }
  params.r0 * @math.exp(-kappa * t) +
  params.theta * (1.0 - @math.exp(-kappa * t))
}

///|
/// Vasicek model: variance of the short rate at time `t`.
///
/// Var[r(t)] = σ²/(2κ) · (1 - e^{-2κt})
pub fn vasicek_rate_variance(params : RateModelParams, t : Double) -> Double {
  let kappa = params.kappa
  let sigma = params.sigma
  if kappa.abs() < 1.0e-12 {
    return sigma * sigma * t
  }
  sigma * sigma / (2.0 * kappa) * (1.0 - @math.exp(-2.0 * kappa * t))
}

///|
/// Vasicek model: European call option on a zero-coupon bond.
///
/// Underlying: P(t,T) bond maturing at `maturity`.
/// Option expires at `expiry` (expiry < maturity).
/// Strike: `strike`.
///
/// Uses Jamshidian's (1989) closed-form formula.
pub fn vasicek_zcb_call(
  params : RateModelParams,
  expiry : Double,
  maturity : Double,
  strike : Double,
) -> Double {
  if expiry <= 0.0 || maturity <= expiry {
    return 0.0
  }
  let kappa = params.kappa
  let p_S = vasicek_bond_price(params, 0.0, expiry)
  let p_T = vasicek_bond_price(params, 0.0, maturity)
  let b_TS = (1.0 - @math.exp(-kappa * (maturity - expiry))) / kappa
  let var_s = vasicek_rate_variance(params, expiry)
  let sigma_p = b_TS * var_s.sqrt()
  if sigma_p < 1.0e-15 {
    let intrinsic = p_T - strike * p_S
    if intrinsic > 0.0 {
      return intrinsic
    }
    return 0.0
  }
  let d1 = (@math.ln(p_T / (strike * p_S)) + 0.5 * sigma_p * sigma_p) / sigma_p
  let d2 = d1 - sigma_p
  p_T * norm_cdf(d1) - strike * p_S * norm_cdf(d2)
}

///|
/// Vasicek model: European put option on a zero-coupon bond.
pub fn vasicek_zcb_put(
  params : RateModelParams,
  expiry : Double,
  maturity : Double,
  strike : Double,
) -> Double {
  if expiry <= 0.0 || maturity <= expiry {
    return 0.0
  }
  let kappa = params.kappa
  let p_S = vasicek_bond_price(params, 0.0, expiry)
  let p_T = vasicek_bond_price(params, 0.0, maturity)
  let b_TS = (1.0 - @math.exp(-kappa * (maturity - expiry))) / kappa
  let var_s = vasicek_rate_variance(params, expiry)
  let sigma_p = b_TS * var_s.sqrt()
  if sigma_p < 1.0e-15 {
    let intrinsic = strike * p_S - p_T
    if intrinsic > 0.0 {
      return intrinsic
    }
    return 0.0
  }
  let d1 = (@math.ln(p_T / (strike * p_S)) + 0.5 * sigma_p * sigma_p) / sigma_p
  let d2 = d1 - sigma_p
  strike * p_S * norm_cdf(-d2) - p_T * norm_cdf(-d1)
}

// ===========================================================================
// 2. Cox-Ingersoll-Ross (CIR) Model
// ===========================================================================
//
// dr(t) = κ(θ - r(t)) dt + σ·√r(t) dW(t)
//
// The short rate follows a non-central chi-squared distribution.
// If 2κθ > σ² (Feller condition), r(t) remains strictly positive.
//
// Zero-coupon bond price (closed form):
//   P(t,T) = A(t,T) · exp(-B(t,T) · r(t))
//
// where:
//   γ = sqrt(κ² + 2σ²)
//   B(t,T) = 2(e^{γτ} - 1) / ((γ+κ)(e^{γτ} - 1) + 2γ)
//   A(t,T) = [2γ·e^{(κ+γ)τ/2} / ((γ+κ)(e^{γτ}-1)+2γ)]^{2κθ/σ²}

///|
/// CIR model: check Feller condition (2κθ > σ²).
///
/// When satisfied, the short rate remains strictly positive almost surely.
pub fn cir_feller_condition(params : RateModelParams) -> Bool {
  2.0 * params.kappa * params.theta > params.sigma * params.sigma
}

///|
/// CIR model: zero-coupon bond price P(t,T).
pub fn cir_bond_price(
  params : RateModelParams,
  t : Double,
  maturity : Double,
) -> Double {
  let kappa = params.kappa
  let theta = params.theta
  let sigma = params.sigma
  let r_t = params.r0
  let tau = maturity - t
  if tau <= 0.0 {
    return 1.0
  }
  let gamma = (kappa * kappa + 2.0 * sigma * sigma).sqrt()
  let exp_gamma_tau = @math.exp(gamma * tau)
  let denom = (gamma + kappa) * (exp_gamma_tau - 1.0) + 2.0 * gamma
  if denom.abs() < 1.0e-15 {
    return 1.0
  }
  let b = 2.0 * (exp_gamma_tau - 1.0) / denom
  let h = 2.0 * gamma * @math.exp((kappa + gamma) * tau / 2.0) / denom
  let exponent = 2.0 * kappa * theta / (sigma * sigma)
  let a = @math.pow(h, exponent)
  a * @math.exp(-b * r_t)
}

///|
/// CIR model: zero rate at time `t` for maturity `T`.
pub fn cir_zero_rate(
  params : RateModelParams,
  t : Double,
  maturity : Double,
) -> Double {
  let tau = maturity - t
  if tau <= 0.0 {
    return params.r0
  }
  let p = cir_bond_price(params, t, maturity)
  -@math.ln(p) / tau
}

///|
/// CIR model: expected short rate at time `t`.
///
/// E[r(t)] = r0·e^{-κt} + θ(1-e^{-κt})
///
/// Note: same expectation as Vasicek, but different distribution.
pub fn cir_expected_rate(params : RateModelParams, t : Double) -> Double {
  let kappa = params.kappa
  if kappa.abs() < 1.0e-12 {
    return params.r0
  }
  params.r0 * @math.exp(-kappa * t) +
  params.theta * (1.0 - @math.exp(-kappa * t))
}

///|
/// CIR model: variance of the short rate at time `t`.
///
/// Var[r(t)] = r0·σ²·(e^{-κt}-e^{-2κt})/κ + θ·σ²·(1-e^{-κt})²/(2κ)
pub fn cir_rate_variance(params : RateModelParams, t : Double) -> Double {
  let kappa = params.kappa
  let theta = params.theta
  let sigma = params.sigma
  let r0 = params.r0
  if kappa.abs() < 1.0e-12 {
    return sigma * sigma * r0 * t
  }
  let e_kt = @math.exp(-kappa * t)
  let e_2kt = @math.exp(-2.0 * kappa * t)
  let term1 = r0 * sigma * sigma * (e_kt - e_2kt) / kappa
  let term2 = theta *
    sigma *
    sigma *
    (1.0 - e_kt) *
    (1.0 - e_kt) /
    (2.0 * kappa)
  term1 + term2
}

///|
/// CIR model: European call option on a zero-coupon bond.
///
/// Uses the closed-form formula from Cox-Ingersoll-Ross (1985).
/// The bond option formula leverages the non-central chi-squared
/// distribution of the future short rate.
pub fn cir_zcb_call(
  params : RateModelParams,
  expiry : Double,
  maturity : Double,
  strike : Double,
) -> Double {
  if expiry <= 0.0 || maturity <= expiry {
    return 0.0
  }
  let kappa = params.kappa
  let theta = params.theta
  let sigma = params.sigma
  let p_S = cir_bond_price(params, 0.0, expiry)
  let p_T = cir_bond_price(params, 0.0, maturity)
  let gamma = (kappa * kappa + 2.0 * sigma * sigma).sqrt()
  let exp_gamma_TS = @math.exp(gamma * (maturity - expiry))
  let denom_TS = (gamma + kappa) * (exp_gamma_TS - 1.0) + 2.0 * gamma
  if denom_TS.abs() < 1.0e-15 {
    return 0.0
  }
  let b_ST = 2.0 * (exp_gamma_TS - 1.0) / denom_TS
  let h_ST = 2.0 *
    gamma *
    @math.exp((kappa + gamma) * (maturity - expiry) / 2.0) /
    denom_TS
  let a_ST = @math.pow(h_ST, 2.0 * kappa * theta / (sigma * sigma))
  if b_ST.abs() < 1.0e-15 {
    return 0.0
  }
  let ratio = strike / a_ST
  if ratio <= 0.0 {
    return 0.0
  }
  let r_star = -@math.ln(ratio) / b_ST
  if r_star < 0.0 {
    return 0.0
  }
  let exp_gamma_S = @math.exp(gamma * expiry)
  let denom_S = (gamma + kappa) * (exp_gamma_S - 1.0) + 2.0 * gamma
  if denom_S.abs() < 1.0e-15 {
    return 0.0
  }
  let c = sigma * sigma * (1.0 - @math.exp(-gamma * expiry)) / (2.0 * gamma)
  if c.abs() < 1.0e-15 {
    return 0.0
  }
  let psi = 4.0 * kappa * theta / (sigma * sigma)
  let nc = 4.0 *
    kappa *
    @math.exp(-gamma * expiry) *
    params.r0 /
    (sigma * sigma * (1.0 - @math.exp(-gamma * expiry)))
  let x_star = r_star / c
  let phi2 = noncentral_chi2_cdf(x_star, psi, nc)
  // Under the S-forward measure, distribution parameters are adjusted
  let cprime = c / (1.0 + 2.0 * c * b_ST)
  let nc_prime = nc / (1.0 + 2.0 * c * b_ST)
  let x_star_prime = r_star / cprime
  let phi1 = noncentral_chi2_cdf(x_star_prime, psi + 2.0, nc_prime)
  let val = p_T * phi1 - strike * p_S * phi2
  if val > 0.0 {
    val
  } else {
    0.0
  }
}

///|
/// CIR model: European put option on a zero-coupon bond via put-call parity.
///
/// put = call + strike·P(0,S) - P(0,T)
pub fn cir_zcb_put(
  params : RateModelParams,
  expiry : Double,
  maturity : Double,
  strike : Double,
) -> Double {
  let call = cir_zcb_call(params, expiry, maturity, strike)
  let p_S = cir_bond_price(params, 0.0, expiry)
  let p_T = cir_bond_price(params, 0.0, maturity)
  call + strike * p_S - p_T
}

// ===========================================================================
// 3. Hull-White Model
// ===========================================================================
//
// dr(t) = [θ(t) - κ·r(t)] dt + σ dW(t)
//
// where θ(t) is calibrated to the initial yield curve:
//   θ(t) = ∂f(0,t)/∂t + κ·f(0,t) + σ²/(2κ)·(1-e^{-2κt})
//
// Since Hull-White is calibrated to match the initial term structure,
// P_HW(0,T) = P_MKT(0,T) for all T.

///|
/// Hull-White model calibration: compute the deterministic θ(t) function
/// from the initial yield curve.
///
/// θ(t) = ∂f(0,t)/∂t + κ·f(0,t) + σ²·(1-e^{-2κt})/(2κ)
///
/// The caller passes a closure that evaluates the forward rate at any t.
pub fn hull_white_theta(
  params : RateModelParams,
  t : Double,
  forward_rate_fn : (Double) -> Double,
) -> Double {
  let kappa = params.kappa
  let sigma = params.sigma
  if t <= 0.0 {
    return params.theta
  }
  let f_t = forward_rate_fn(t)
  let eps = 1.0e-6
  let f_plus = forward_rate_fn(t + eps)
  let f_minus = forward_rate_fn(t - eps)
  let df_dt = (f_plus - f_minus) / (2.0 * eps)
  let correction = if kappa.abs() < 1.0e-12 {
    sigma * sigma * t
  } else {
    sigma * sigma * (1.0 - @math.exp(-2.0 * kappa * t)) / (2.0 * kappa)
  }
  df_dt + kappa * f_t + correction
}

///|
/// Hull-White model: zero-coupon bond price P(0,T) calibrated to the
/// initial yield curve.
///
/// Since Hull-White is calibrated to match the initial term structure,
/// P_HW(0,T) = P_MKT(0,T) for all T.
pub fn hull_white_bond_price(
  _params : RateModelParams,
  maturity : Double,
  market_discount_factor : Double,
) -> Double {
  if maturity <= 0.0 {
    return 1.0
  }
  market_discount_factor
}

///|
/// Hull-White model: European call on a zero-coupon bond.
///
/// Since Hull-White has the same distributional properties as Vasicek
/// (both are Gaussian), the bond option formula has the same form as
/// Vasicek's, but with the bond prices replaced by market-observed ones.
///
/// call = P(0,S)·N(d1) - K·P(0,T)·N(d2)
/// where σ_P = σ·(1-e^{-κ(T-S)})/κ · sqrt((1-e^{-2κS})/(2κ))
pub fn hull_white_zcb_call(
  params : RateModelParams,
  expiry : Double,
  maturity : Double,
  strike : Double,
  p_S : Double,
  p_T : Double,
) -> Double {
  if expiry <= 0.0 || maturity <= expiry {
    return 0.0
  }
  let kappa = params.kappa
  let sigma = params.sigma
  let b_TS = (1.0 - @math.exp(-kappa * (maturity - expiry))) / kappa
  let var_s = sigma *
    sigma /
    (2.0 * kappa) *
    (1.0 - @math.exp(-2.0 * kappa * expiry))
  let sigma_p = b_TS * var_s.sqrt()
  if sigma_p < 1.0e-15 {
    let intrinsic = p_T - strike * p_S
    if intrinsic > 0.0 {
      return intrinsic
    }
    return 0.0
  }
  let d1 = (@math.ln(p_T / (strike * p_S)) + 0.5 * sigma_p * sigma_p) / sigma_p
  let d2 = d1 - sigma_p
  p_T * norm_cdf(d1) - strike * p_S * norm_cdf(d2)
}

///|
/// Hull-White model: European put on a zero-coupon bond.
pub fn hull_white_zcb_put(
  params : RateModelParams,
  expiry : Double,
  maturity : Double,
  strike : Double,
  p_S : Double,
  p_T : Double,
) -> Double {
  if expiry <= 0.0 || maturity <= expiry {
    return 0.0
  }
  let kappa = params.kappa
  let sigma = params.sigma
  let b_TS = (1.0 - @math.exp(-kappa * (maturity - expiry))) / kappa
  let var_s = sigma *
    sigma /
    (2.0 * kappa) *
    (1.0 - @math.exp(-2.0 * kappa * expiry))
  let sigma_p = b_TS * var_s.sqrt()
  if sigma_p < 1.0e-15 {
    let intrinsic = strike * p_S - p_T
    if intrinsic > 0.0 {
      return intrinsic
    }
    return 0.0
  }
  let d1 = (@math.ln(p_T / (strike * p_S)) + 0.5 * sigma_p * sigma_p) / sigma_p
  let d2 = d1 - sigma_p
  strike * p_S * norm_cdf(-d2) - p_T * norm_cdf(-d1)
}

///|
/// Hull-White model: Monte Carlo simulation of the short rate path.
///
/// Uses the exact transition density of the Ornstein-Uhlenbeck process:
///   r(t+Δt) = r(t)·e^{-κΔt} + θ·(1-e^{-κΔt}) + σ·√((1-e^{-2κΔt})/(2κ))·Z
///
/// `n_steps`: number of time steps
/// `dt`: time step size
/// `theta_path`: array of θ(t) values at each step (length = n_steps)
/// `z_path`: array of standard normal random values (length = n_steps)
///
/// Returns: array of short rate values r(0), r(dt), r(2dt), ..., r(n_steps*dt)
pub fn hull_white_simulate(
  params : RateModelParams,
  n_steps : Int,
  dt : Double,
  theta_path : Array[Double],
  z_path : Array[Double],
) -> Array[Double] {
  let kappa = params.kappa
  let sigma = params.sigma
  let r_path : Array[Double] = Array::make(n_steps + 1, 0.0)
  r_path[0] = params.r0
  let exp_kdt = @math.exp(-kappa * dt)
  let var_dt = (1.0 - @math.exp(-2.0 * kappa * dt)) / (2.0 * kappa)
  let std_dev = sigma * var_dt.sqrt()
  for i = 0; i < n_steps; i = i + 1 {
    let theta_i = if i < theta_path.length() {
      theta_path[i]
    } else {
      params.theta
    }
    let z = if i < z_path.length() { z_path[i] } else { 0.0 }
    r_path[i + 1] = r_path[i] * exp_kdt +
      theta_i * (1.0 - exp_kdt) +
      std_dev * z
  }
  r_path
}

///|
/// Vasicek model: Monte Carlo simulation of the short rate path.
///
/// Simulates the short rate using constant θ.
/// Uses the exact transition density of the Ornstein-Uhlenbeck process.
pub fn vasicek_simulate(
  params : RateModelParams,
  n_steps : Int,
  dt : Double,
  z_path : Array[Double],
) -> Array[Double] {
  let kappa = params.kappa
  let sigma = params.sigma
  let r_path : Array[Double] = Array::make(n_steps + 1, 0.0)
  r_path[0] = params.r0
  let exp_kdt = @math.exp(-kappa * dt)
  let var_dt = (1.0 - @math.exp(-2.0 * kappa * dt)) / (2.0 * kappa)
  let std_dev = sigma * var_dt.sqrt()
  for i = 0; i < n_steps; i = i + 1 {
    let z = if i < z_path.length() { z_path[i] } else { 0.0 }
    r_path[i + 1] = r_path[i] * exp_kdt +
      params.theta * (1.0 - exp_kdt) +
      std_dev * z
  }
  r_path
}

///|
/// CIR model: Monte Carlo simulation of the short rate path.
///
/// Uses the truncated Euler-Maruyama scheme with absorption at zero
/// to ensure non-negativity:
///   r(t+Δt) = max(r(t) + κ(θ-r(t))Δt + σ√r(t)·√Δt·Z, 0)
///
/// Note: The full QE scheme (Andersen 2008) is available in the
/// `finance/heston` module for the Heston model's variance process
/// (which follows the same CIR dynamics). This simpler scheme is
/// adequate for rate simulation when the Feller condition is satisfied.
pub fn cir_simulate(
  params : RateModelParams,
  n_steps : Int,
  dt : Double,
  z_path : Array[Double],
) -> Array[Double] {
  let kappa = params.kappa
  let theta = params.theta
  let sigma = params.sigma
  let r_path : Array[Double] = Array::make(n_steps + 1, 0.0)
  r_path[0] = params.r0
  let sqrt_dt = dt.sqrt()
  for i = 0; i < n_steps; i = i + 1 {
    let z = if i < z_path.length() { z_path[i] } else { 0.0 }
    let r_prev = r_path[i]
    if r_prev > 0.0 {
      let drift = kappa * (theta - r_prev) * dt
      let diffusion = sigma * r_prev.sqrt() * sqrt_dt * z
      let r_new = r_prev + drift + diffusion
      r_path[i + 1] = if r_new > 0.0 { r_new } else { 0.0 }
    } else {
      r_path[i + 1] = 0.0
    }
  }
  r_path
}
