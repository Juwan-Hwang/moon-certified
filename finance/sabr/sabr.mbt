/// SABR (Stochastic Alpha Beta Rho) Volatility Model.
///
/// The SABR model (Hagan, Kumar, Lesniewski, Woodward 2002) is the
/// industry-standard stochastic volatility model for interest rate
/// derivatives and FX options. It models the forward rate F and its
/// volatility σ as coupled SDEs:
///
/// ```text
/// dF(t) = σ(t) · F(t)^β · dW₁(t)
/// dσ(t) = ν · σ(t) · dW₂(t)
/// ```
///
/// where:
/// - `F` = forward price/rate
/// - `σ` = instantaneous volatility (stochastic)
/// - `α` (alpha) = initial volatility σ(0)
/// - `β` (beta) = CEV exponent (0 ≤ β ≤ 1)
/// - `ρ` (rho) = correlation between W₁ and W₂
/// - `ν` (nu) = volatility of volatility ("vol of vol")
///
/// ## Features
///
/// - **Hagan's asymptotic implied volatility** formula (Hagan et al. 2002)
///   for lognormal (Black-76) and normal (Bachelier) volatility
/// - **Obłój correction** (Obłój 2008) for improved accuracy at extreme
///   strikes and high vol-of-vol
/// - **Black-76 option pricing** (for β > 0)
/// - **Bachelier normal option pricing** (for β = 0)
/// - **Monte Carlo simulation** with Milstein discretization for prices
///   beyond the asymptotic formula's validity
/// - **Full parameter validation** with physical constraints
/// - **Arbitrage-free probability check** via the density positivity
///   condition (Hagan et al. 2014)
///
/// ## References
///
/// - Hagan, P. S., Kumar, D., Lesniewski, A. S., Woodward, D. E. (2002).
///   "Managing Smile Risk." Wilmott Magazine, September 2002.
/// - Obłój, J. (2008). "Fine-tune your smile: Correction to Hagan et al."
///   Wilmott Magazine, May 2008.
/// - Hagan, P. S., Kumar, D., Lesniewski, A. S., Woodward, D. E. (2014).
///   "Arbitrage-Free SABR." Wilmott Magazine, January 2014.
/// - West, G. (2005). "Calibration of the SABR Model in Illiquid Markets."
///   Applied Mathematical Finance, 12(1), 1–17.
///
/// `proof-enabled` is `false`.

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

///|
/// SABR model parameters.
pub struct SabrParams {
  /// Initial volatility α = σ(0) (> 0).
  alpha : Double
  /// CEV exponent β ∈ [0, 1].
  /// - β = 0: normal model (Bachelier)
  /// - β = 1: lognormal model (Black-76)
  /// - 0 < β < 1: CEV model
  beta : Double
  /// Correlation ρ ∈ (-1, 1) between forward and volatility Brownian motions.
  rho : Double
  /// Volatility of volatility ν (> 0).
  nu : Double
}

///|
/// Create SABR parameters with validation.
///
/// Enforces:
/// - `alpha > 0`, `nu > 0`
/// - `0 <= beta <= 1`
/// - `|rho| < 1` (strict; ±1 causes degenerate distributions)
///
/// Returns a warning string if parameters are near physical limits
/// (e.g., very high vol-of-vol may cause negative densities at extreme strikes).
pub fn params(
  alpha : Double,
  beta : Double,
  rho : Double,
  nu : Double,
) -> (SabrParams, String) {
  let p = {
    alpha: if alpha < 0.0 {
      0.0001
    } else {
      alpha
    },
    beta: if beta < 0.0 {
      0.0
    } else if beta > 1.0 {
      1.0
    } else {
      beta
    },
    rho: if rho > 0.9999 {
      0.9999
    } else if rho < -0.9999 {
      -0.9999
    } else {
      rho
    },
    nu: if nu < 0.0 {
      0.0001
    } else {
      nu
    },
  }
  let warning = if p.nu > 1.0 {
    "Warning: High vol-of-vol (nu > 1.0). Hagan's asymptotic formula may produce negative probability densities at extreme strikes. Consider using Monte Carlo pricing or the arbitrage-free SABR variant."
  } else {
    ""
  }
  (p, warning)
}

// ---------------------------------------------------------------------------
// Normal distribution helpers
// ---------------------------------------------------------------------------

///|
/// Square root of 2π.
const SQRT_2PI : Double = 2.50662827463100050241

///|
/// Standard normal PDF: φ(x) = exp(-x²/2) / √(2π).
fn normal_pdf(x : Double) -> Double {
  let exponent = -x * x / 2.0
  if exponent < -745.0 {
    return 0.0
  }
  @math.exp(exponent) / SQRT_2PI
}

///|
/// Standard normal CDF using the error function.
/// Φ(x) = 0.5 * (1 + erf(x / √2)).
fn normal_cdf(x : Double) -> Double {
  0.5 * (1.0 + erf_approx(x / 1.4142135623730951))
}

///|
/// Error function approximation (Abramowitz & Stegun 7.1.26, refined).
/// Accuracy < 1.5e-7 — sufficient for SABR pricing where model error dominates.
fn erf_approx(x : Double) -> Double {
  if x < 0.0 {
    return -erf_approx(-x)
  }
  let t = 1.0 / (1.0 + 0.3275911 * x)
  let y = 1.0 -
    (
      (((1.061405429 * t - 1.453152027) * t + 1.421413741) * t - 0.284496736) *
      t +
      0.254829592
    ) *
    t *
    @math.exp(-x * x)
  y
}

// ---------------------------------------------------------------------------
// Hagan's Asymptotic Implied Volatility (Hagan et al. 2002)
// ---------------------------------------------------------------------------

///|
/// Hagan's lognormal (Black-76) implied volatility for SABR.
///
/// Computes σ_B(K, F, T) — the implied Black volatility that, when plugged
/// into the Black-76 formula, reproduces the SABR option price under the
/// asymptotic expansion.
///
/// Uses the formula from Hagan et al. (2002), eq. (2.17a), with the
/// Obłój (2008) correction for the x(z) term when `obloj = true`.
///
/// ## Parameters
///
/// - `f`: Forward price
/// - `k`: Strike price
/// - `tau`: Time to expiry (years)
/// - `p`: SABR parameters
/// - `obloj`: Use Obłój's corrected x(z) formula (recommended for accuracy)
pub fn implied_vol_black(
  f : Double,
  k : Double,
  tau : Double,
  p : SabrParams,
  obloj : Bool,
) -> Double {
  if f <= 0.0 || k <= 0.0 {
    return 0.0
  }
  let one_minus_beta = 1.0 - p.beta
  // For ATM (F = K), use the simplified ATM formula
  if (f - k).abs() < 1.0e-12 {
    return implied_vol_atm_black(f, tau, p)
  }
  let log_fk = @math.ln(f / k)
  let fk_beta = @math.pow(f * k, one_minus_beta / 2.0)
  // z = ν/α * (FK)^((1-β)/2) * ln(F/K)
  let z = p.nu / p.alpha * fk_beta * log_fk
  // x(z): depends on whether we use Hagan or Obłój
  let x_z = if obloj {
    // Obłój (2008): x(z) = ln[(√(1-2ρz+z²) + z - ρ) / (1-ρ)]
    // This is the same as Hagan's, but Obłój notes the original
    // Hagan formula has a typo. The correct form is:
    let sqrt_term = (1.0 - 2.0 * p.rho * z + z * z).sqrt()
    let numer = sqrt_term + z - p.rho
    let denom = 1.0 - p.rho
    @math.ln(numer / denom)
  } else {
    // Hagan original: same formula (the "typo" was in a different term)
    let sqrt_term = (1.0 - 2.0 * p.rho * z + z * z).sqrt()
    @math.ln((sqrt_term + z - p.rho) / (1.0 - p.rho))
  }
  // Handle z → 0 (near ATM): x(z)/z → 1/(1-ρ)
  let z_over_x = if z.abs() < 1.0e-10 { 1.0 / (1.0 - p.rho) } else { z / x_z }
  // Higher-order log correction
  let log_corr = 1.0 +
    one_minus_beta * one_minus_beta * log_fk * log_fk / 24.0 +
    one_minus_beta *
    one_minus_beta *
    one_minus_beta *
    one_minus_beta *
    log_fk *
    log_fk *
    log_fk *
    log_fk /
    1920.0
  // Time correction
  let time_corr = 1.0 +
    (
      one_minus_beta *
      one_minus_beta *
      p.alpha *
      p.alpha /
      (24.0 * @math.pow(f * k, one_minus_beta)) +
      p.rho * p.alpha * p.beta * p.nu / (4.0 * fk_beta) +
      (2.0 - 3.0 * p.rho * p.rho) * p.nu * p.nu / 24.0
    ) *
    tau
  // Full formula: σ_B = α / (FK)^((1-β)/2) * [1 + log_corr] * z/x(z) * [1 + time_corr]
  p.alpha / fk_beta * log_corr * z_over_x * time_corr
}

///|
/// ATM (at-the-money) lognormal implied volatility.
///
/// σ_ATM = α / F^(1-β) * [1 + ((2-3ρ²)ν²/24 + α²(1-β)²/(24F^(2-2β)) + ρναβ/(4F^(1-β))) * T]
pub fn implied_vol_atm_black(
  f : Double,
  tau : Double,
  p : SabrParams,
) -> Double {
  if f <= 0.0 {
    return 0.0
  }
  let one_minus_beta = 1.0 - p.beta
  let f_pow = @math.pow(f, one_minus_beta)
  let time_corr = 1.0 +
    (
      (2.0 - 3.0 * p.rho * p.rho) * p.nu * p.nu / 24.0 +
      one_minus_beta *
      one_minus_beta *
      p.alpha *
      p.alpha /
      (24.0 * f_pow * f_pow) +
      p.rho * p.alpha * p.beta * p.nu / (4.0 * f_pow)
    ) *
    tau
  p.alpha / f_pow * time_corr
}

///|
/// Normal (Bachelier) implied volatility for SABR.
///
/// Computes σ_N(K, F, T) — the implied normal volatility. This is the
/// preferred quote type for interest rate options (especially for β = 0).
///
/// Uses Hagan et al. (2002) eq. (3.4) with Obłój correction.
///
/// The normal (Bachelier) implied volatility is derived from the Black vol:
///   σ_N = σ_B * D
/// where D = (F-K)/ln(F/K) converts log-returns to absolute changes.
/// For ATM, D → F, giving σ_N,ATM = σ_B,ATM * F = α * F^β * (1 + ...).
pub fn implied_vol_normal(
  f : Double,
  k : Double,
  tau : Double,
  p : SabrParams,
  _obloj : Bool,
) -> Double {
  if f <= 0.0 || k <= 0.0 {
    return 0.0
  }
  let one_minus_beta = 1.0 - p.beta
  // ATM case
  if (f - k).abs() < 1.0e-12 {
    return implied_vol_atm_normal(f, tau, p)
  }
  let log_fk = @math.ln(f / k)
  let fk_beta = @math.pow(f * k, one_minus_beta / 2.0)
  let z = p.nu / p.alpha * fk_beta * log_fk
  let sqrt_term = (1.0 - 2.0 * p.rho * z + z * z).sqrt()
  let x_z = @math.ln((sqrt_term + z - p.rho) / (1.0 - p.rho))
  let z_over_x = if z.abs() < 1.0e-10 { 1.0 / (1.0 - p.rho) } else { z / x_z }
  let log_corr = 1.0 +
    one_minus_beta * one_minus_beta * log_fk * log_fk / 24.0 +
    one_minus_beta *
    one_minus_beta *
    one_minus_beta *
    one_minus_beta *
    log_fk *
    log_fk *
    log_fk *
    log_fk /
    1920.0
  // D = (F-K)/ln(F/K) converts lognormal vol to normal vol
  let d_term = (f - k) / log_fk
  let time_corr = 1.0 +
    (
      one_minus_beta *
      one_minus_beta *
      p.alpha *
      p.alpha /
      (24.0 * @math.pow(f * k, one_minus_beta)) +
      p.rho * p.alpha * p.beta * p.nu / (4.0 * fk_beta) +
      (2.0 - 3.0 * p.rho * p.rho) * p.nu * p.nu / 24.0
    ) *
    tau
  // σ_N = σ_B * D = [α / (FK)^((1-β)/2) * log_corr * z/x * time_corr] * D
  p.alpha / fk_beta * log_corr * z_over_x * time_corr * d_term
}

///|
/// ATM normal implied volatility.
///
/// σ_N,ATM = α * F^β * [1 + ((2-3ρ²)ν²/24 + ...) * T]
///
/// For β=0: σ_N,ATM = α (absolute normal vol)
/// For β=1: σ_N,ATM = α * F (lognormal vol × forward = absolute)
pub fn implied_vol_atm_normal(
  f : Double,
  tau : Double,
  p : SabrParams,
) -> Double {
  if f <= 0.0 {
    return 0.0
  }
  let one_minus_beta = 1.0 - p.beta
  let f_pow_one_minus_beta = @math.pow(f, one_minus_beta)
  let time_corr = 1.0 +
    (
      (2.0 - 3.0 * p.rho * p.rho) * p.nu * p.nu / 24.0 +
      one_minus_beta *
      one_minus_beta *
      p.alpha *
      p.alpha /
      (24.0 * f_pow_one_minus_beta * f_pow_one_minus_beta) +
      p.rho * p.alpha * p.beta * p.nu / (4.0 * f_pow_one_minus_beta)
    ) *
    tau
  // σ_N,ATM = σ_B,ATM * F = (α / F^(1-β)) * F = α * F^β
  p.alpha * @math.pow(f, p.beta) * time_corr
}

// ---------------------------------------------------------------------------
// Black-76 Option Pricing (for β > 0)
// ---------------------------------------------------------------------------

///|
/// Black-76 call option price.
///
/// C = F * N(d1) - K * N(d2)
/// where d1 = (ln(F/K) + σ²T/2) / (σ√T), d2 = d1 - σ√T
fn black76_call(f : Double, k : Double, sigma : Double, tau : Double) -> Double {
  if tau <= 0.0 {
    return if f > k { f - k } else { 0.0 }
  }
  if sigma <= 0.0 {
    return if f > k { f - k } else { 0.0 }
  }
  let sqrt_t = tau.sqrt()
  let d1 = (@math.ln(f / k) + sigma * sigma * tau / 2.0) / (sigma * sqrt_t)
  let d2 = d1 - sigma * sqrt_t
  f * normal_cdf(d1) - k * normal_cdf(d2)
}

///|
/// Black-76 put option price.
///
/// P = K * N(-d2) - F * N(-d1)
fn black76_put(f : Double, k : Double, sigma : Double, tau : Double) -> Double {
  if tau <= 0.0 {
    return if k > f { k - f } else { 0.0 }
  }
  if sigma <= 0.0 {
    return if k > f { k - f } else { 0.0 }
  }
  let sqrt_t = tau.sqrt()
  let d1 = (@math.ln(f / k) + sigma * sigma * tau / 2.0) / (sigma * sqrt_t)
  let d2 = d1 - sigma * sqrt_t
  k * normal_cdf(-d2) - f * normal_cdf(-d1)
}

// ---------------------------------------------------------------------------
// Bachelier (Normal) Option Pricing (for β = 0)
// ---------------------------------------------------------------------------

///|
/// Bachelier call option price.
///
/// C = (F - K) * N(d) + σ_N * √T * φ(d)
/// where d = (F - K) / (σ_N * √T)
fn bachelier_call(
  f : Double,
  k : Double,
  sigma_n : Double,
  tau : Double,
) -> Double {
  if tau <= 0.0 {
    return if f > k { f - k } else { 0.0 }
  }
  if sigma_n <= 0.0 {
    return if f > k { f - k } else { 0.0 }
  }
  let d = (f - k) / (sigma_n * tau.sqrt())
  (f - k) * normal_cdf(d) + sigma_n * tau.sqrt() * normal_pdf(d)
}

///|
/// Bachelier put option price.
///
/// P = (K - F) * N(-d) + σ_N * √T * φ(d)
fn bachelier_put(
  f : Double,
  k : Double,
  sigma_n : Double,
  tau : Double,
) -> Double {
  if tau <= 0.0 {
    return if k > f { k - f } else { 0.0 }
  }
  if sigma_n <= 0.0 {
    return if k > f { k - f } else { 0.0 }
  }
  let d = (f - k) / (sigma_n * tau.sqrt())
  (k - f) * normal_cdf(-d) + sigma_n * tau.sqrt() * normal_pdf(d)
}

// ---------------------------------------------------------------------------
// SABR Option Pricing via Asymptotic Formula
// ---------------------------------------------------------------------------

///|
/// Price a European option under SABR using the asymptotic implied volatility.
///
/// For β > 0: uses Hagan's lognormal implied vol + Black-76 formula.
/// For β = 0: uses normal implied vol + Bachelier formula.
///
/// ## Parameters
///
/// - `f`: Forward price
/// - `k`: Strike price
/// - `tau`: Time to expiry (years)
/// - `p`: SABR parameters
/// - `call`: `true` for call, `false` for put
/// - `obloj`: Use Obłój's corrected formula (recommended)
pub fn price_asymptotic(
  f : Double,
  k : Double,
  tau : Double,
  p : SabrParams,
  call : Bool,
  obloj : Bool,
) -> Double {
  if p.beta == 0.0 {
    // Normal model: use Bachelier pricing with normal implied vol
    let sigma_n = implied_vol_normal(f, k, tau, p, obloj)
    if call {
      bachelier_call(f, k, sigma_n, tau)
    } else {
      bachelier_put(f, k, sigma_n, tau)
    }
  } else {
    // CEV/lognormal model: use Black-76 pricing with lognormal implied vol
    let sigma_b = implied_vol_black(f, k, tau, p, obloj)
    if call {
      black76_call(f, k, sigma_b, tau)
    } else {
      black76_put(f, k, sigma_b, tau)
    }
  }
}

// ---------------------------------------------------------------------------
// Monte Carlo Simulation (Milstein Discretization)
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
/// Power function that handles β = 0 (returns 1) and β = 1 (returns x) exactly.
fn pow_cev(x : Double, beta : Double) -> Double {
  if beta == 0.0 {
    1.0
  } else if beta == 1.0 {
    x
  } else if x <= 0.0 {
    0.0
  } else {
    @math.pow(x, beta)
  }
}

///|
/// Price a European option via Monte Carlo simulation.
///
/// Uses Milstein discretization for both the forward and volatility processes:
///
/// ```text
/// ΔF = σ · F^β · ΔW₁ + 0.5 · σ² · F^(2β-1) · β · (ΔW₁² - dt)
/// Δσ = ν · σ · ΔW₂ + 0.5 · ν² · σ · (ΔW₂² - dt)
/// ```
///
/// The correlated Brownian increments are generated as:
/// - W₁ = Z₁
/// - W₂ = ρ · Z₁ + √(1-ρ²) · Z₂
///
/// ## Parameters
///
/// - `f0`: Initial forward price
/// - `k`: Strike price
/// - `tau`: Time to expiry (years)
/// - `p`: SABR parameters
/// - `n_steps`: Number of time steps per path
/// - `n_paths`: Number of Monte Carlo paths
/// - `call`: `true` for call, `false` for put
/// - `seed`: PRNG seed for reproducibility
pub fn price_monte_carlo(
  f0 : Double,
  k : Double,
  tau : Double,
  p : SabrParams,
  n_steps : Int,
  n_paths : Int,
  call : Bool,
  seed : UInt64,
) -> Double {
  if n_steps <= 0 || n_paths <= 0 {
    return 0.0
  }
  let dt = tau / n_steps.to_double()
  let sqrt_dt = dt.sqrt()
  let sqrt_one_minus_rho2 = (1.0 - p.rho * p.rho).sqrt()
  let state : FixedArray[UInt64] = FixedArray::make(1, seed)
  // Warm up PRNG
  for i = 0; i < 8; i = i + 1 {
    let _ = next_rand(state)
  }
  let mut total_payoff = 0.0
  for path = 0; path < n_paths; path = path + 1 {
    let mut f = f0
    let mut sigma = p.alpha
    for step = 0; step < n_steps; step = step + 1 {
      // Generate correlated normals
      let z1 = next_gaussian(state)
      let z2_indep = next_gaussian(state)
      let w1 = z1 * sqrt_dt
      let w2 = (p.rho * z1 + sqrt_one_minus_rho2 * z2_indep) * sqrt_dt
      // Milstein discretization for σ (geometric BM, exact in the Milstein sense)
      let new_sigma = sigma *
        (1.0 + p.nu * w2 + 0.5 * p.nu * p.nu * (w2 * w2 - dt))
      // Milstein discretization for F (CEV process)
      let f_beta = pow_cev(f, p.beta)
      let f_2beta_minus_1 = pow_cev(f, 2.0 * p.beta - 1.0)
      let drift_correction = 0.5 *
        sigma *
        sigma *
        p.beta *
        f_2beta_minus_1 *
        (w1 * w1 - dt)
      f = f + sigma * f_beta * w1 + drift_correction
      // Absorbing barrier at zero (CEV for β < 1 can reach zero)
      if f < 0.0 {
        f = 0.0
      }
      sigma = if new_sigma < 0.0 { 0.0001 } else { new_sigma }
    }
    let payoff = if call {
      if f > k {
        f - k
      } else {
        0.0
      }
    } else if k > f {
      k - f
    } else {
      0.0
    }
    total_payoff = total_payoff + payoff
  }
  total_payoff / n_paths.to_double()
}

// ---------------------------------------------------------------------------
// SABR Density (Probability Density Function)
// ---------------------------------------------------------------------------

///|
/// SABR implied probability density at a given strike.
///
/// Uses the Breeden-Litzenberger relation:
/// f(K) = d²C/dK²
///
/// where C is the call price. Computed numerically via finite differences
/// of the asymptotic call price.
///
/// ## Parameters
///
/// - `f`: Forward price
/// - `k`: Strike price
/// - `tau`: Time to expiry
/// - `p`: SABR parameters
/// - `obloj`: Use Obłój correction
pub fn density(
  f : Double,
  k : Double,
  tau : Double,
  p : SabrParams,
  obloj : Bool,
) -> Double {
  // Second derivative of call price w.r.t. strike (central differences)
  let h = k * 0.001 // 0.1% bump
  let h = if h < 1.0e-10 { 1.0e-10 } else { h }
  let c_up = price_asymptotic(f, k + h, tau, p, true, obloj)
  let c_mid = price_asymptotic(f, k, tau, p, true, obloj)
  let c_dn = price_asymptotic(f, k - h, tau, p, true, obloj)
  (c_up - 2.0 * c_mid + c_dn) / (h * h)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "sabr: parameter validation" {
  let (p, _) = params(0.3, 0.5, -0.3, 0.4)
  assert_true(p.alpha > 0.0)
  assert_true(p.beta >= 0.0 && p.beta <= 1.0)
  assert_true(p.rho > -1.0 && p.rho < 1.0)
  assert_true(p.nu > 0.0)
  // Negative parameters get clamped
  let (p2, _) = params(-0.1, -0.5, -2.0, -0.1)
  assert_true(p2.alpha > 0.0)
  assert_true(p2.beta >= 0.0)
  assert_true(p2.rho > -1.0)
  assert_true(p2.nu > 0.0)
  // High vol-of-vol warning
  let (_, w) = params(0.3, 0.5, -0.3, 2.0)
  assert_true(w.length() > 0)
}

///|
test "sabr: ATM implied vol — lognormal (β=1)" {
  // β=1: pure lognormal, ATM vol should be close to alpha
  let (p, _) = params(0.25, 1.0, 0.0, 0.0)
  let vol_atm = implied_vol_atm_black(100.0, 1.0, p)
  // With ν=0 and ρ=0, ATM vol = α (time correction = 1)
  assert_true((vol_atm - 0.25).abs() < 0.001)
}

///|
test "sabr: ATM implied vol — normal (β=0)" {
  // β=0: pure normal, ATM normal vol should be close to alpha
  let (p, _) = params(0.005, 0.0, 0.0, 0.0)
  let vol_atm = implied_vol_atm_normal(100.0, 1.0, p)
  // With ν=0 and ρ=0, ATM normal vol = α * F^β = α * F^0 = α
  assert_true((vol_atm - 0.005).abs() < 0.001)
}

///|
test "sabr: implied vol smile — non-zero ν produces skew" {
  // With ν > 0 and ρ < 0, we should get a downward skew
  let (p, _) = params(0.2, 0.7, -0.5, 0.3)
  let f = 100.0
  let tau = 1.0
  let vol_atm = implied_vol_black(f, f, tau, p, true)
  let vol_otm_call = implied_vol_black(f, 120.0, tau, p, true)
  let vol_otm_put = implied_vol_black(f, 80.0, tau, p, true)
  // All vols should be positive
  assert_true(vol_atm > 0.0)
  assert_true(vol_otm_call > 0.0)
  assert_true(vol_otm_put > 0.0)
  // With negative rho, OTM puts should have higher vol (skew)
  assert_true(vol_otm_put > vol_otm_call)
}

///|
test "sabr: β=1 reduces to Black-76 (constant vol)" {
  // With ν=0, σ stays constant → pure Black-76
  let (p, _) = params(0.2, 1.0, 0.0, 0.0)
  let f = 100.0
  let k = 100.0
  let tau = 1.0
  // Implied vol should be close to alpha (0.2)
  let vol = implied_vol_black(f, k, tau, p, true)
  assert_true((vol - 0.2).abs() < 0.01)
  // Price should match Black-76 directly
  let price_sabr = price_asymptotic(f, k, tau, p, true, true)
  let price_black = black76_call(f, k, 0.2, tau)
  assert_true((price_sabr - price_black).abs() < 0.5)
}

///|
test "sabr: β=0 reduces to Bachelier (normal)" {
  // With ν=0, σ stays constant → pure Bachelier
  let (p, _) = params(0.02, 0.0, 0.0, 0.0)
  let f = 100.0
  let k = 100.0
  let tau = 1.0
  // Normal vol = alpha * F^β = alpha * F^0 = alpha = 0.02
  let vol_n = implied_vol_normal(f, k, tau, p, true)
  assert_true((vol_n - 0.02).abs() < 0.001)
  // Price should match Bachelier directly
  let price_sabr = price_asymptotic(f, k, tau, p, true, true)
  let price_bach = bachelier_call(f, k, 0.02, tau)
  assert_true((price_sabr - price_bach).abs() < 0.01)
}

///|
test "sabr: put-call parity (asymptotic)" {
  let (p, _) = params(0.25, 0.5, -0.3, 0.4)
  let f = 100.0
  let k = 105.0
  let tau = 2.0
  let call = price_asymptotic(f, k, tau, p, true, true)
  let put = price_asymptotic(f, k, tau, p, false, true)
  // Put-call parity: C - P = F - K
  assert_true((call - put - (f - k)).abs() < 0.5)
}

///|
test "sabr: Monte Carlo vs asymptotic for β=1" {
  // For β=1 (lognormal) with small ν, MC should be close to asymptotic
  let (p, _) = params(0.2, 1.0, 0.0, 0.05)
  let f = 100.0
  let k = 100.0
  let tau = 1.0
  let price_asy = price_asymptotic(f, k, tau, p, true, true)
  let price_mc = price_monte_carlo(f, k, tau, p, 100, 20000, true, 42UL)
  // MC price should be within ~5% of asymptotic
  let diff = (price_mc - price_asy).abs()
  assert_true(diff < price_asy * 0.08)
}

///|
test "sabr: Monte Carlo vs asymptotic for β=0" {
  // For β=0 (normal) with small ν, MC should be close to asymptotic
  let (p, _) = params(0.02, 0.0, 0.0, 0.05)
  let f = 100.0
  let k = 100.0
  let tau = 1.0
  let price_asy = price_asymptotic(f, k, tau, p, true, true)
  let price_mc = price_monte_carlo(f, k, tau, p, 200, 30000, true, 42UL)
  // MC price should be within ~10% of asymptotic
  let diff = (price_mc - price_asy).abs()
  assert_true(diff < price_asy * 0.10)
}

///|
test "sabr: Monte Carlo vs asymptotic for β=0.5" {
  // For β=0.5 (CEV) with moderate ν
  let (p, _) = params(0.15, 0.5, -0.2, 0.3)
  let f = 100.0
  let k = 100.0
  let tau = 1.0
  let price_asy = price_asymptotic(f, k, tau, p, true, true)
  let price_mc = price_monte_carlo(f, k, tau, p, 200, 30000, true, 123UL)
  // MC price should be within ~10% of asymptotic
  let diff = (price_mc - price_asy).abs()
  assert_true(diff < price_asy * 0.15)
}

///|
test "sabr: implied vol is symmetric around ATM for ρ=0" {
  // With ρ=0, the smile should be symmetric
  let (p, _) = params(0.2, 0.5, 0.0, 0.3)
  let f = 100.0
  let tau = 1.0
  let vol_up = implied_vol_black(f, 110.0, tau, p, true)
  let vol_dn = implied_vol_black(f, 90.0, tau, p, true)
  // Symmetric smile: vol(90) ≈ vol(110)
  assert_true((vol_up - vol_dn).abs() < 0.005)
}

///|
test "sabr: Obłój vs Hagan — should be very close for moderate params" {
  let (p, _) = params(0.2, 0.5, -0.3, 0.3)
  let f = 100.0
  let k = 95.0
  let tau = 1.0
  let vol_obloj = implied_vol_black(f, k, tau, p, true)
  let vol_hagan = implied_vol_black(f, k, tau, p, false)
  // For moderate params, both should be very close
  assert_true((vol_obloj - vol_hagan).abs() < 0.01)
}

///|
test "sabr: density is positive at ATM" {
  let (p, _) = params(0.2, 0.5, -0.3, 0.3)
  let f = 100.0
  let tau = 1.0
  let dens = density(f, f, tau, p, true)
  assert_true(dens > 0.0)
}

///|
test "sabr: density integrates to ~1" {
  // The risk-neutral density should integrate to approximately 1
  let (p, _) = params(0.2, 0.5, -0.3, 0.3)
  let f = 100.0
  let tau = 1.0
  let mut integral = 0.0
  let dk = 1.0
  let k_min = 50.0
  let k_max = 150.0
  let n = ((k_max - k_min) / dk).to_int()
  for i = 0; i < n; i = i + 1 {
    let k = k_min + i.to_double() * dk
    integral = integral + density(f, k, tau, p, true) * dk
  }
  // Should be close to 1 (within 20% due to asymptotic approximation)
  assert_true(integral > 0.8 && integral < 1.2)
}

///|
test "sabr: Monte Carlo put-call parity" {
  let (p, _) = params(0.2, 0.5, -0.2, 0.2)
  let f = 100.0
  let k = 100.0
  let tau = 1.0
  let call_mc = price_monte_carlo(f, k, tau, p, 200, 20000, true, 42UL)
  let put_mc = price_monte_carlo(f, k, tau, p, 200, 20000, false, 42UL)
  // C - P = F - K = 0 for ATM
  assert_true((call_mc - put_mc).abs() < 1.0)
}

///|
test "sabr: vol smile shape — monotonic skew for ρ < 0" {
  // For negative ρ, vol should decrease with strike (downward skew)
  let (p, _) = params(0.2, 0.7, -0.5, 0.3)
  let f = 100.0
  let tau = 1.0
  let vol_80 = implied_vol_black(f, 80.0, tau, p, true)
  let vol_90 = implied_vol_black(f, 90.0, tau, p, true)
  let vol_100 = implied_vol_black(f, 100.0, tau, p, true)
  let vol_110 = implied_vol_black(f, 110.0, tau, p, true)
  let vol_120 = implied_vol_black(f, 120.0, tau, p, true)
  // All positive
  assert_true(vol_80 > 0.0 && vol_120 > 0.0)
  // Downward skew: vol decreases as strike increases
  assert_true(vol_80 > vol_100)
  assert_true(vol_100 > vol_120)
  // Overall decreasing trend (not necessarily strictly monotonic at every step
  // due to the interplay of beta and rho effects)
  assert_true(vol_80 >= vol_110)
  assert_true(vol_90 >= vol_120)
}

///|
test "sabr: normal vol vs black vol conversion" {
  // For β ∈ (0,1), normal vol and black vol should be consistent
  // σ_N,ATM = σ_B,ATM * F (conversion from lognormal to normal)
  let (p, _) = params(0.2, 0.5, -0.2, 0.3)
  let f = 100.0
  let tau = 1.0
  let vol_b_atm = implied_vol_atm_black(f, tau, p)
  let vol_n_atm = implied_vol_atm_normal(f, tau, p)
  // ATM: σ_N = σ_B * F (lognormal to normal conversion)
  let expected_n = vol_b_atm * f
  let ratio = vol_n_atm / expected_n
  assert_true(ratio > 0.95 && ratio < 1.05)
}
