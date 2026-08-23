/// CVA/DVA/FVA (xVA) — Valuation Adjustments
///
/// Implements credit valuation adjustments for OTC derivative pricing.
///
/// ## Components
/// - **CVA (Credit Valuation Adjustment)**: Expected loss from counterparty default
/// - **DVA (Debt Valuation Adjustment)**: Expected gain from own default
/// - **FVA (Funding Valuation Adjustment)**: Funding cost/benefit
/// - **BA (Bilateral Adjustment)**: CVA - DVA
///
/// ## Formulas
/// CVA = (1-R) * Σ EAD(t) * PD(t) * DF(t)
/// DVA = (1-R_self) * Σ EAD(t) * PD_self(t) * DF(t)
///
/// `proof-enabled` is `false`.

///|
/// xVA parameters.
pub struct XvaParams {
  recovery_rate : Double // Counterparty recovery rate R
  self_recovery : Double // Own recovery rate
  counterparty_hazard : Double // Counterparty hazard rate (PD per year)
  self_hazard : Double // Own hazard rate
  risk_free_rate : Double // Risk-free rate
  funding_spread : Double // Funding spread
}

///|
/// Default xVA parameters.
pub fn xva_default_params() -> XvaParams {
  XvaParams::{
    recovery_rate: 0.4,
    self_recovery: 0.4,
    counterparty_hazard: 0.02,
    self_hazard: 0.01,
    risk_free_rate: 0.03,
    funding_spread: 0.005,
  }
}

///|
/// Create XvaParams with custom values.
pub fn XvaParams::new(
  recovery_rate : Double,
  self_recovery : Double,
  counterparty_hazard : Double,
  self_hazard : Double,
  risk_free_rate : Double,
  funding_spread : Double,
) -> XvaParams {
  {
    recovery_rate,
    self_recovery,
    counterparty_hazard,
    self_hazard,
    risk_free_rate,
    funding_spread,
  }
}

///|
/// xVA result.
pub struct XvaResult {
  cva : Double
  dva : Double
  fva : Double
  total_xva : Double
}

///|
/// Survival probability under constant hazard rate.
/// S(t) = exp(-h * t)
fn survival_prob(hazard : Double, t : Double) -> Double {
  @math.exp(-hazard * t)
}

///|
/// Default probability in interval [t1, t2].
// PD(t1, t2) = S(t1) - S(t2)
fn default_prob(hazard : Double, t1 : Double, t2 : Double) -> Double {
  survival_prob(hazard, t1) - survival_prob(hazard, t2)
}

///|
/// Discount factor.
fn discount_factor(rate : Double, t : Double) -> Double {
  @math.exp(-rate * t)
}

///|
/// Compute CVA (Credit Valuation Adjustment).
///
/// CVA = (1-R) * Σ EAD(t_i) * PD(t_{i-1}, t_i) * DF(t_i)
///
/// ## Parameters
/// - `params`: xVA parameters
/// - `exposures`: expected positive exposure at each time point
/// - `times`: time points (years)
pub fn compute_cva(
  params : XvaParams,
  exposures : Array[Double],
  times : Array[Double],
) -> Double {
  let mut cva = 0.0
  for i = 1; i < exposures.length() && i < times.length(); i = i + 1 {
    let t_prev = times[i - 1]
    let t_curr = times[i]
    let pd = default_prob(params.counterparty_hazard, t_prev, t_curr)
    let df = discount_factor(params.risk_free_rate, t_curr)
    let lgd = 1.0 - params.recovery_rate
    cva = cva + lgd * exposures[i] * pd * df
  }
  cva
}

///|
/// Compute DVA (Debt Valuation Adjustment).
///
/// DVA = (1-R_self) * Σ ENE(t_i) * PD_self(t_{i-1}, t_i) * DF(t_i)
///
/// ## Parameters
/// - `params`: xVA parameters
/// - `exposures`: expected negative exposure (ENE) at each time point
/// - `times`: time points
pub fn compute_dva(
  params : XvaParams,
  exposures : Array[Double],
  times : Array[Double],
) -> Double {
  let mut dva = 0.0
  for i = 1; i < exposures.length() && i < times.length(); i = i + 1 {
    let t_prev = times[i - 1]
    let t_curr = times[i]
    let pd = default_prob(params.self_hazard, t_prev, t_curr)
    let df = discount_factor(params.risk_free_rate, t_curr)
    let lgd = 1.0 - params.self_recovery
    dva = dva + lgd * exposures[i] * pd * df
  }
  dva
}

///|
/// Compute FVA (Funding Valuation Adjustment).
///
/// FVA = Σ EAD(t_i) * funding_spread * Δt * DF(t_i)
pub fn compute_fva(
  params : XvaParams,
  exposures : Array[Double],
  times : Array[Double],
) -> Double {
  let mut fva = 0.0
  for i = 1; i < exposures.length() && i < times.length(); i = i + 1 {
    let dt = times[i] - times[i - 1]
    let df = discount_factor(params.risk_free_rate, times[i])
    fva = fva + exposures[i] * params.funding_spread * dt * df
  }
  fva
}

///|
/// Compute all valuation adjustments (CVA, DVA, FVA).
///
/// ## Parameters
/// - `params`: xVA parameters
/// - `positive_exposures`: EPE at each time point (for CVA)
/// - `negative_exposures`: ENE at each time point (for DVA)
/// - `funding_exposures`: exposure for FVA
/// - `times`: time points in years
pub fn compute_xva(
  params : XvaParams,
  positive_exposures : Array[Double],
  negative_exposures : Array[Double],
  funding_exposures : Array[Double],
  times : Array[Double],
) -> XvaResult {
  let cva = compute_cva(params, positive_exposures, times)
  let dva = compute_dva(params, negative_exposures, times)
  let fva = compute_fva(params, funding_exposures, times)
  { cva, dva, fva, total_xva: cva - dva + fva }
}

///|
/// Compute the bilateral CVA (CVA - DVA).
pub fn bilateral_cva(result : XvaResult) -> Double {
  result.cva - result.dva
}
