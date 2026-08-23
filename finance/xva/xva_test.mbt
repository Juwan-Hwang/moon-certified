// White-box tests for finance/xva.
// Covers CVA/DVA/FVA computation, aggregated XVA result, and bilateral CVA.

///|
test "xva_default_params" {
  let p = xva_default_params()
  assert_true((p.recovery_rate - 0.4).abs() < 1.0e-12)
  assert_true((p.self_recovery - 0.4).abs() < 1.0e-12)
  assert_true((p.counterparty_hazard - 0.02).abs() < 1.0e-12)
  assert_true((p.self_hazard - 0.01).abs() < 1.0e-12)
  assert_true((p.risk_free_rate - 0.03).abs() < 1.0e-12)
  assert_true((p.funding_spread - 0.005).abs() < 1.0e-12)
}

///|
test "compute_cva_zero_exposure" {
  let p = xva_default_params()
  let cva = compute_cva(p, [0.0, 0.0], [0.0, 1.0])
  assert_true((cva - 0.0).abs() < 1.0e-12)
}

///|
test "compute_cva_single_point" {
  // one exposure point -> loop body never executes -> 0
  let p = xva_default_params()
  let cva = compute_cva(p, [100.0], [1.0])
  assert_true((cva - 0.0).abs() < 1.0e-12)
}

///|
test "compute_cva_basic" {
  let p = xva_default_params()
  let cva = compute_cva(p, [0.0, 100.0], [0.0, 1.0])
  // 0.6 * 100 * (1 - exp(-0.02)) * exp(-0.03)
  let expected = 0.6 * 100.0 * (1.0 - @math.exp(-0.02)) * @math.exp(-0.03)
  assert_true((cva - expected).abs() < 1.0e-9)
  assert_true(cva > 0.0)
}

///|
test "compute_cva_increases_with_hazard" {
  let p_low = xva_default_params()
  let p_high = XvaParams::new(0.4, 0.4, 0.1, 0.01, 0.03, 0.005)
  let cva_low = compute_cva(p_low, [0.0, 100.0], [0.0, 1.0])
  let cva_high = compute_cva(p_high, [0.0, 100.0], [0.0, 1.0])
  assert_true(cva_high > cva_low)
}

///|
test "compute_dva_basic" {
  let p = xva_default_params()
  let dva = compute_dva(p, [0.0, 50.0], [0.0, 1.0])
  let expected = (1.0 - p.self_recovery) *
    50.0 *
    (1.0 - @math.exp(-p.self_hazard)) *
    @math.exp(-p.risk_free_rate)
  assert_true((dva - expected).abs() < 1.0e-9)
  assert_true(dva > 0.0)
}

///|
test "compute_fva_basic" {
  let p = xva_default_params()
  let fva = compute_fva(p, [0.0, 100.0], [0.0, 1.0])
  // 100 * 0.005 * 1 * exp(-0.03)
  let expected = 100.0 * 0.005 * 1.0 * @math.exp(-0.03)
  assert_true((fva - expected).abs() < 1.0e-9)
  assert_true(fva > 0.0)
}

///|
test "compute_fva_zero_spread" {
  let p = XvaParams::new(0.4, 0.4, 0.02, 0.01, 0.03, 0.0)
  let fva = compute_fva(p, [0.0, 100.0], [0.0, 1.0])
  assert_true((fva - 0.0).abs() < 1.0e-12)
}

///|
test "compute_xva_consistency" {
  let p = xva_default_params()
  let pos = [0.0, 100.0, 80.0]
  let neg = [0.0, 10.0, 20.0]
  let fund = [0.0, 100.0, 90.0]
  let times = [0.0, 1.0, 2.0]
  let r = compute_xva(p, pos, neg, fund, times)
  assert_true((r.total_xva - (r.cva - r.dva + r.fva)).abs() < 1.0e-12)
  assert_true(r.cva > 0.0)
  assert_true(r.dva > 0.0)
  assert_true(r.fva > 0.0)
}

///|
test "bilateral_cva" {
  let p = xva_default_params()
  let r = compute_xva(p, [0.0, 100.0], [0.0, 10.0], [0.0, 100.0], [0.0, 1.0])
  assert_true((bilateral_cva(r) - (r.cva - r.dva)).abs() < 1.0e-12)
}
