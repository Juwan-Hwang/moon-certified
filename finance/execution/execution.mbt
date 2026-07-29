/// Algorithmic Execution — TWAP, VWAP, and Almgren-Chriss.
///
/// Algorithmic execution strategies determine how to split a large parent
/// order into smaller child orders to minimise market impact and timing
/// risk. This module implements three industry-standard approaches:
///
/// - **TWAP** (Time-Weighted Average Price): splits the order evenly
///   across time slots, producing a flat execution profile.
/// - **VWAP** (Volume-Weighted Average Price): allocates more shares to
///   high-volume periods, matching the intraday volume curve.
/// - **Almgren-Chriss**: the seminal optimal-execution model that
///   minimises the weighted sum of expected cost and cost variance
///   (risk). The solution traces a deterministic hyperbolic trajectory
///   that smoothly interpolates between TWAP (risk-neutral) and
///   immediate execution (infinitely risk-averse).
///
/// ## Almgren-Chriss Model
///
/// A trader must liquidate `X` shares over horizon `T` divided into `N`
/// periods of length `τ = T / N`. Let `x_k` be the shares remaining at
/// time `t_k = kτ` (so `x_0 = X`, `x_N = 0`) and `v_k = x_{k-1} - x_k`
/// the shares traded in period `k`.
///
/// - **Temporary impact** (per-period, proportional to execution rate):
///   `h(v) = η · v / τ`
/// - **Permanent impact** (shifts the mid-price for all future periods):
///   `g(v) = γ · v`
/// - **Volatility**: `σ` (per-period standard deviation of returns)
/// - **Risk aversion**: `λ`
///
/// The objective minimises:
///
/// `E[cost] + λ · Var[cost]`
///
/// where:
/// - `E[cost] = (η/τ) · Σ v_k² + (γ/2) · X²`  (permanent impact is
///   strategy-independent for linear impact)
/// - `Var[cost] = σ² · τ · Σ x_k²`
///
/// ## Optimal trajectory
///
/// `x_k = X · sinh(κ · (T − t_k)) / sinh(κ · T)`
///
/// where `κ = √(λ σ² / η)` is the characteristic liquidation rate.
///
/// - When `λ → 0` (risk-neutral), `κ → 0` and the trajectory becomes
///   linear — equivalent to TWAP.
/// - When `λ → ∞` (infinitely risk-averse), the trajectory front-loads
///   execution to eliminate price exposure.
///
/// ## References
///
/// - R. Almgren, N. Chriss. "Optimal Execution of Portfolio
///   Transactions." Journal of Risk, 2001.
/// - R. Kissell. "The Science of Algorithmic Trading and Portfolio
///   Management." Academic Press, 2013.
/// - B. Leinweber. "Algo Trading: What's Next?" Journal of Portfolio
///   Management, 2009.
///
/// `proof-enabled` is `false`; correctness is backed by test vectors.

// ---------------------------------------------------------------------------
// TWAP
// ---------------------------------------------------------------------------

///|
/// Generate a TWAP (Time-Weighted Average Price) execution schedule.
///
/// Splits `total_qty` into `num_slices` equal child orders. Each slice
/// is `total_qty / num_slices`, optionally rounded down to the nearest
/// multiple of `lot_size` (with the remainder added to the last slice).
///
/// - `total_qty`: Total quantity to execute (positive for buy, negative
///   for sell).
/// - `num_slices`: Number of time slots.
/// - `lot_size`: Minimum lot size. Use 0.0 to disable rounding.
///
/// Returns an array of length `num_slices` whose elements sum to
/// `total_qty`.
pub fn twap_schedule(
  total_qty : Double,
  num_slices : Int,
  lot_size : Double,
) -> Array[Double] {
  if num_slices <= 0 {
    return []
  }
  let result : Array[Double] = Array::make(num_slices, 0.0)
  if lot_size <= 0.0 {
    let per_slice = total_qty / num_slices.to_double()
    for i = 0; i < num_slices; i = i + 1 {
      result[i] = per_slice
    }
    return result
  }
  let per_slice_raw = total_qty / num_slices.to_double()
  let per_slice = (per_slice_raw / lot_size).floor() * lot_size
  let mut allocated = 0.0
  for i = 0; i < num_slices - 1; i = i + 1 {
    result[i] = per_slice
    allocated = allocated + per_slice
  }
  // Remainder goes to the last slice to ensure the sum equals total_qty.
  result[num_slices - 1] = total_qty - allocated
  result
}

// ---------------------------------------------------------------------------
// VWAP
// ---------------------------------------------------------------------------

///|
/// Generate a VWAP (Volume-Weighted Average Price) execution schedule.
///
/// Allocates `total_qty` across time slots proportionally to the
/// expected volume in each slot. High-volume periods receive a larger
/// share of the parent order, matching the intraday volume curve.
///
/// - `total_qty`: Total quantity to execute.
/// - `volume_profile`: Expected volume for each time slot (must be
///   non-negative; at least one element must be positive).
/// - `lot_size`: Minimum lot size. Use 0.0 to disable rounding.
///
/// Returns an array of the same length as `volume_profile` whose
/// elements sum to `total_qty`.
pub fn vwap_schedule(
  total_qty : Double,
  volume_profile : Array[Double],
  lot_size : Double,
) -> Array[Double] {
  let n = volume_profile.length()
  if n == 0 {
    return []
  }
  let result : Array[Double] = Array::make(n, 0.0)
  let mut total_vol = 0.0
  for i = 0; i < n; i = i + 1 {
    let v = volume_profile[i]
    total_vol = total_vol + (if v > 0.0 { v } else { 0.0 })
  }
  if total_vol <= 0.0 {
    // Fall back to equal split if no volume information.
    return twap_schedule(total_qty, n, lot_size)
  }
  if lot_size <= 0.0 {
    for i = 0; i < n; i = i + 1 {
      let v = if volume_profile[i] > 0.0 { volume_profile[i] } else { 0.0 }
      result[i] = total_qty * v / total_vol
    }
    return result
  }
  let mut allocated = 0.0
  for i = 0; i < n - 1; i = i + 1 {
    let v = if volume_profile[i] > 0.0 { volume_profile[i] } else { 0.0 }
    let raw = total_qty * v / total_vol
    let rounded = (raw / lot_size).floor() * lot_size
    result[i] = rounded
    allocated = allocated + rounded
  }
  result[n - 1] = total_qty - allocated
  result
}

// ---------------------------------------------------------------------------
// Almgren-Chriss
// ---------------------------------------------------------------------------

///|
/// Compute the Almgren-Chriss optimal execution trajectory.
///
/// Returns the shares remaining at each time point `t_k = k·τ` for
/// `k = 0, 1, …, N`, where `N = num_periods`. The first element is
/// `total_shares` and the last is `0.0`.
///
/// - `total_shares`: Total quantity to liquidate (X > 0).
/// - `num_periods`: Number of execution periods (N).
/// - `horizon`: Total time horizon T.
/// - `volatility`: Per-period price volatility σ (same time unit as τ).
/// - `temp_impact`: Temporary impact coefficient η (> 0).
/// - `risk_aversion`: Risk aversion parameter λ (≥ 0).
///
/// When `risk_aversion = 0` the trajectory is linear (TWAP). As
/// `risk_aversion → ∞` the trajectory front-loads execution.
pub fn almgren_chriss_trajectory(
  total_shares : Double,
  num_periods : Int,
  horizon : Double,
  volatility : Double,
  temp_impact : Double,
  risk_aversion : Double,
) -> Array[Double] {
  let n = num_periods
  if n <= 0 || total_shares <= 0.0 || horizon <= 0.0 {
    return []
  }
  let trajectory : Array[Double] = Array::make(n + 1, 0.0)
  trajectory[0] = total_shares
  trajectory[n] = 0.0
  let tau = horizon / n.to_double()
  // Characteristic rate κ = sqrt(λ σ² / η).
  // When κ is zero (risk-neutral), use linear (TWAP) trajectory.
  let kappa_sq = risk_aversion * volatility * volatility / temp_impact
  if kappa_sq <= 0.0 || temp_impact <= 0.0 {
    // Linear trajectory: x_k = X * (1 - k/N).
    for k = 1; k < n; k = k + 1 {
      trajectory[k] = total_shares * (1.0 - k.to_double() / n.to_double())
    }
    return trajectory
  }
  let kappa = kappa_sq.sqrt()
  let kappa_t = kappa * horizon
  let sinh_kt = @math.sinh(kappa_t)
  if sinh_kt.abs() < 1.0e-15 {
    // Near-zero κT → linear.
    for k = 1; k < n; k = k + 1 {
      trajectory[k] = total_shares * (1.0 - k.to_double() / n.to_double())
    }
    return trajectory
  }
  for k = 1; k < n; k = k + 1 {
    let t_k = k.to_double() * tau
    trajectory[k] = total_shares * @math.sinh(kappa * (horizon - t_k)) / sinh_kt
  }
  trajectory
}

///|
/// Derive the per-period trade list from an Almgren-Chriss trajectory.
///
/// Returns an array of length `num_periods` where element `k` is the
/// number of shares to execute in period `k` (always non-negative for a
/// sell programme).
pub fn almgren_chriss_trade_list(
  total_shares : Double,
  num_periods : Int,
  horizon : Double,
  volatility : Double,
  temp_impact : Double,
  risk_aversion : Double,
) -> Array[Double] {
  let n = num_periods
  if n <= 0 {
    return []
  }
  let trajectory = almgren_chriss_trajectory(
    total_shares, n, horizon, volatility, temp_impact, risk_aversion,
  )
  let trades : Array[Double] = Array::make(n, 0.0)
  for k = 0; k < n; k = k + 1 {
    let diff = trajectory[k] - trajectory[k + 1]
    trades[k] = if diff > 0.0 { diff } else { 0.0 }
  }
  trades
}

///|
/// Expected execution cost under the Almgren-Chriss model.
///
/// Computes the expected total implementation shortfall:
///
/// `E[cost] = (η/τ) · Σ v_k² + (γ/2) · X²`
///
/// The first term is the temporary impact cost (strategy-dependent);
/// the second is the permanent impact cost (strategy-independent for
/// linear impact).
///
/// - `total_shares`: Total quantity X.
/// - `num_periods`: Number of periods N.
/// - `horizon`: Time horizon T.
/// - `volatility`: Per-period volatility σ.
/// - `temp_impact`: Temporary impact coefficient η.
/// - `perm_impact`: Permanent impact coefficient γ.
/// - `risk_aversion`: Risk aversion λ.
pub fn almgren_chriss_expected_cost(
  total_shares : Double,
  num_periods : Int,
  horizon : Double,
  volatility : Double,
  temp_impact : Double,
  perm_impact : Double,
  risk_aversion : Double,
) -> Double {
  let n = num_periods
  if n <= 0 || horizon <= 0.0 || total_shares <= 0.0 {
    return 0.0
  }
  let tau = horizon / n.to_double()
  let trades = almgren_chriss_trade_list(
    total_shares, n, horizon, volatility, temp_impact, risk_aversion,
  )
  let mut temp_cost = 0.0
  for k = 0; k < n; k = k + 1 {
    temp_cost = temp_cost + trades[k] * trades[k]
  }
  temp_cost = temp_impact * temp_cost / tau
  let perm_cost = 0.5 * perm_impact * total_shares * total_shares
  temp_cost + perm_cost
}

///|
/// Variance of execution cost under the Almgren-Chriss model.
///
/// `Var[cost] = σ² · τ · Σ x_k²`
///
/// where `x_k` is the remaining position at the start of each period.
pub fn almgren_chriss_cost_variance(
  total_shares : Double,
  num_periods : Int,
  horizon : Double,
  volatility : Double,
  temp_impact : Double,
  risk_aversion : Double,
) -> Double {
  let n = num_periods
  if n <= 0 || horizon <= 0.0 || total_shares <= 0.0 {
    return 0.0
  }
  let tau = horizon / n.to_double()
  let trajectory = almgren_chriss_trajectory(
    total_shares, n, horizon, volatility, temp_impact, risk_aversion,
  )
  let mut sum_sq = 0.0
  for k = 0; k < n; k = k + 1 {
    sum_sq = sum_sq + trajectory[k] * trajectory[k]
  }
  volatility * volatility * tau * sum_sq
}

// ---------------------------------------------------------------------------
// Market Impact Models
// ---------------------------------------------------------------------------

///|
/// Linear (temporary) market impact in basis points.
///
/// Models the price impact of a child order as a linear function of
/// its participation rate:
///
/// `impact (bps) = coefficient · (shares / period_volume) · 1e4`
///
/// - `shares`: Order size in shares.
/// - `period_volume`: Expected volume in the execution period.
/// - `coefficient`: Linear impact coefficient (e.g. 0.1).
///
/// Returns the impact in basis points. Returns 0 if `period_volume`
/// is non-positive.
pub fn linear_market_impact_bps(
  shares : Double,
  period_volume : Double,
  coefficient : Double,
) -> Double {
  if period_volume <= 0.0 {
    return 0.0
  }
  coefficient * (shares / period_volume) * 1.0e4
}

///|
/// Square-root market impact in basis points.
///
/// Empirical studies show that impact often scales with the square
/// root of participation rate rather than linearly:
///
/// `impact (bps) = coefficient · √(shares / ADV) · 1e4`
///
/// This is the model used by many buy-side desks (e.g. the Kissell
/// model). Returns the impact in basis points.
///
/// - `shares`: Order size.
/// - `adv`: Average daily volume.
/// - `coefficient`: Impact coefficient (e.g. 0.5).
pub fn square_root_impact_bps(
  shares : Double,
  adv : Double,
  coefficient : Double,
) -> Double {
  if adv <= 0.0 || shares <= 0.0 {
    return 0.0
  }
  coefficient * (shares / adv).sqrt() * 1.0e4
}

///|
/// Estimated execution cost from temporary market impact.
///
/// Converts a basis-point impact into a monetary cost:
///
/// `cost = shares · price · impact_bps / 1e4`
///
/// - `shares`: Number of shares executed.
/// - `price`: Execution price.
/// - `impact_bps`: Market impact in basis points.
pub fn impact_cost(
  shares : Double,
  price : Double,
  impact_bps : Double,
) -> Double {
  shares * price * impact_bps / 1.0e4
}

///|
/// Participation-rate constraint check.
///
/// Ensures that no child order exceeds a maximum participation rate
/// (fraction of period volume). Returns `true` if all slices satisfy
/// the constraint.
///
/// - `slices`: Child order sizes.
/// - `period_volumes`: Expected volume per period.
/// - `max_participation`: Maximum allowed participation (e.g. 0.1 for
///   10%).
pub fn check_participation(
  slices : Array[Double],
  period_volumes : Array[Double],
  max_participation : Double,
) -> Bool {
  let n = slices.length()
  if n == 0 || n != period_volumes.length() {
    return true
  }
  for i = 0; i < n; i = i + 1 {
    if period_volumes[i] > 0.0 {
      let rate = slices[i].abs() / period_volumes[i]
      if rate > max_participation + 1.0e-12 {
        return false
      }
    }
  }
  true
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "twap: equal slices without lot size" {
  let sched = twap_schedule(10000.0, 10, 0.0)
  assert_eq(sched.length(), 10)
  for i = 0; i < 10; i = i + 1 {
    assert_true((sched[i] - 1000.0).abs() < 1.0e-10)
  }
}

///|
test "twap: sum equals total" {
  let sched = twap_schedule(10000.0, 7, 0.0)
  let mut sum = 0.0
  for i = 0; i < 7; i = i + 1 {
    sum = sum + sched[i]
  }
  assert_true((sum - 10000.0).abs() < 1.0e-10)
}

///|
test "twap: lot size rounding" {
  // 10000 / 3 = 3333.33..., lot_size=100 → 3300 per slice, remainder in last.
  let sched = twap_schedule(10000.0, 3, 100.0)
  assert_true((sched[0] - 3300.0).abs() < 1.0e-10)
  assert_true((sched[1] - 3300.0).abs() < 1.0e-10)
  // Last slice gets the remainder: 10000 - 6600 = 3400
  assert_true((sched[2] - 3400.0).abs() < 1.0e-10)
}

///|
test "vwap: proportional to volume" {
  let volumes = [100.0, 200.0, 300.0, 400.0]
  let sched = vwap_schedule(10000.0, volumes, 0.0)
  // Total volume = 1000, so fractions are 0.1, 0.2, 0.3, 0.4
  assert_true((sched[0] - 1000.0).abs() < 1.0e-10)
  assert_true((sched[1] - 2000.0).abs() < 1.0e-10)
  assert_true((sched[2] - 3000.0).abs() < 1.0e-10)
  assert_true((sched[3] - 4000.0).abs() < 1.0e-10)
}

///|
test "vwap: sum equals total" {
  let volumes = [50.0, 150.0, 80.0, 120.0, 200.0]
  let sched = vwap_schedule(50000.0, volumes, 0.0)
  let mut sum = 0.0
  for i = 0; i < 5; i = i + 1 {
    sum = sum + sched[i]
  }
  assert_true((sum - 50000.0).abs() < 1.0e-10)
}

///|
test "vwap: zero volume falls back to twap" {
  let volumes = [0.0, 0.0, 0.0]
  let sched = vwap_schedule(9000.0, volumes, 0.0)
  assert_eq(sched.length(), 3)
  for i = 0; i < 3; i = i + 1 {
    assert_true((sched[i] - 3000.0).abs() < 1.0e-10)
  }
}

///|
test "almgren_chriss: trajectory endpoints" {
  let traj = almgren_chriss_trajectory(10000.0, 10, 1.0, 0.3, 0.001, 1.0e-6)
  assert_eq(traj.length(), 11)
  assert_true((traj[0] - 10000.0).abs() < 1.0e-6)
  assert_true(traj[10].abs() < 1.0e-6)
}

///|
test "almgren_chriss: monotonically decreasing" {
  let traj = almgren_chriss_trajectory(10000.0, 20, 1.0, 0.3, 0.001, 1.0e-6)
  for k = 0; k < 20; k = k + 1 {
    assert_true(traj[k] >= traj[k + 1] - 1.0e-6)
  }
}

///|
test "almgren_chriss: risk-neutral equals twap" {
  // With λ=0, trajectory should be linear (TWAP).
  let traj = almgren_chriss_trajectory(10000.0, 10, 1.0, 0.3, 0.001, 0.0)
  for k = 0; k <= 10; k = k + 1 {
    let expected = 10000.0 * (1.0 - k.to_double() / 10.0)
    assert_true((traj[k] - expected).abs() < 1.0)
  }
}

///|
test "almgren_chriss: higher risk front-loads" {
  let traj_low = almgren_chriss_trajectory(10000.0, 10, 1.0, 0.3, 0.001, 1.0e-7)
  let traj_high = almgren_chriss_trajectory(
    10000.0, 10, 1.0, 0.3, 0.001, 1.0e-4,
  )
  // Higher risk aversion → trade more early → lower remaining at t=τ.
  assert_true(traj_high[1] < traj_low[1])
}

///|
test "almgren_chriss: trade list sums to total" {
  let trades = almgren_chriss_trade_list(10000.0, 10, 1.0, 0.3, 0.001, 1.0e-6)
  let mut sum = 0.0
  for k = 0; k < 10; k = k + 1 {
    sum = sum + trades[k]
  }
  assert_true((sum - 10000.0).abs() < 1.0e-3)
}

///|
test "almgren_chriss: expected cost positive" {
  let cost = almgren_chriss_expected_cost(
    10000.0, 10, 1.0, 0.3, 0.001, 0.0001, 1.0e-6,
  )
  assert_true(cost > 0.0)
}

///|
test "almgren_chriss: variance decreases with risk aversion" {
  let var_low = almgren_chriss_cost_variance(
    10000.0, 10, 1.0, 0.3, 0.001, 1.0e-8,
  )
  let var_high = almgren_chriss_cost_variance(
    10000.0, 10, 1.0, 0.3, 0.001, 1.0e-3,
  )
  // Higher risk aversion → front-load → lower position over time →
  // lower variance.
  assert_true(var_high < var_low)
}

///|
test "market_impact: linear scales with size" {
  let impact_small = linear_market_impact_bps(100.0, 10000.0, 0.1)
  let impact_large = linear_market_impact_bps(500.0, 10000.0, 0.1)
  assert_true((impact_large - 5.0 * impact_small).abs() < 1.0e-10)
}

///|
test "market_impact: square root model" {
  // 100 shares / 10000 ADV = 0.01, sqrt = 0.1, coefficient 0.5 → 500 bps
  let impact = square_root_impact_bps(100.0, 10000.0, 0.5)
  let expected = 0.5 * 0.01.sqrt() * 1.0e4
  assert_true((impact - expected).abs() < 1.0e-8)
}

///|
test "market_impact: cost conversion" {
  // 1000 shares * $50 * 10 bps / 1e4 = $50 (10 bps = 0.1%)
  let cost = impact_cost(1000.0, 50.0, 10.0)
  assert_true((cost - 50.0).abs() < 1.0e-10)
}

///|
test "participation: constraint check" {
  let slices = [100.0, 200.0, 50.0]
  let volumes = [1000.0, 1000.0, 1000.0]
  assert_true(check_participation(slices, volumes, 0.25))
  // 200/1000 = 20% < 25% → OK
  assert_false(check_participation(slices, volumes, 0.15))
  // 200/1000 = 20% > 15% → violation
}
