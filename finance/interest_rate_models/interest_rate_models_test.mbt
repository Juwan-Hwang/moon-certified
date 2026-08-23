// ===========================================================================
// Vasicek Model Tests
// ===========================================================================

///|
test "vasicek_bond_price_at_zero" {
  let p = vasicek_bond_price(rate_model_params(0.1, 0.05, 0.01, 0.04), 0.0, 0.0)
  // P(t,t) = 1
  assert_true((p - 1.0).abs() < 1.0e-10)
}

///|
test "vasicek_bond_price_known" {
  // κ=0.1, θ=0.05, σ=0.01, r0=0.04
  let p1 = vasicek_bond_price(
    rate_model_params(0.1, 0.05, 0.01, 0.04),
    0.0,
    1.0,
  )
  // Should be between exp(-0.04) ≈ 0.9608 and exp(-0.05) ≈ 0.9512
  assert_true(p1 > 0.95 && p1 < 0.965)
}

///|
test "vasicek_bond_price_decreasing_in_maturity" {
  let params = rate_model_params(0.2, 0.05, 0.02, 0.04)
  let p1 = vasicek_bond_price(params, 0.0, 1.0)
  let p2 = vasicek_bond_price(params, 0.0, 2.0)
  let p5 = vasicek_bond_price(params, 0.0, 5.0)
  // Bond price decreases with maturity (positive rates)
  assert_true(p1 > p2)
  assert_true(p2 > p5)
}

///|
test "vasicek_zero_rate" {
  let params = rate_model_params(0.1, 0.05, 0.01, 0.04)
  let z = vasicek_zero_rate(params, 0.0, 1.0)
  // Should be between r0=0.04 and θ=0.05
  assert_true(z > 0.039 && z < 0.052)
}

///|
test "vasicek_expected_rate" {
  let params = rate_model_params(0.1, 0.05, 0.01, 0.04)
  // At t=0: E[r] = r0 = 0.04
  assert_true((vasicek_expected_rate(params, 0.0) - 0.04).abs() < 1.0e-10)
  // As t→∞: E[r] → θ = 0.05
  let r_long = vasicek_expected_rate(params, 100.0)
  assert_true((r_long - 0.05).abs() < 1.0e-3)
}

///|
test "vasicek_rate_variance" {
  let params = rate_model_params(0.1, 0.05, 0.01, 0.04)
  // At t=0: variance = 0
  assert_true(vasicek_rate_variance(params, 0.0) < 1.0e-15)
  // Variance increases with time
  assert_true(
    vasicek_rate_variance(params, 1.0) < vasicek_rate_variance(params, 10.0),
  )
}

///|
test "vasicek_zcb_call_put_parity" {
  // Put-call parity: call - put = P(0,T) - K*P(0,S)
  let params = rate_model_params(0.2, 0.05, 0.01, 0.04)
  let expiry = 1.0
  let maturity = 5.0
  let strike = 0.8
  let call = vasicek_zcb_call(params, expiry, maturity, strike)
  let put = vasicek_zcb_put(params, expiry, maturity, strike)
  let p_S = vasicek_bond_price(params, 0.0, expiry)
  let p_T = vasicek_bond_price(params, 0.0, maturity)
  let parity = call - put
  let intrinsic = p_T - strike * p_S
  assert_true((parity - intrinsic).abs() < 1.0e-8)
}

///|
test "vasicek_zcb_call_nonnegativity" {
  let params = rate_model_params(0.2, 0.05, 0.01, 0.04)
  let expiry = 0.5
  let maturity = 2.0
  let strike = 0.95
  let call = vasicek_zcb_call(params, expiry, maturity, strike)
  assert_true(call >= 0.0)
}

///|
test "vasicek_simulate" {
  let params = rate_model_params(0.1, 0.05, 0.01, 0.04)
  let n = 100
  let dt = 0.01
  // Use deterministic Z path (all zeros)
  let z_path = Array::make(n, 0.0)
  let path = vasicek_simulate(params, n, dt, z_path)
  assert_eq(path.length(), n + 1)
  assert_true((path[0] - 0.04).abs() < 1.0e-10)
  // With Z=0, the path should follow the deterministic mean
  let expected_r1 = 0.04 * @math.exp(-0.1 * 0.01) +
    0.05 * (1.0 - @math.exp(-0.1 * 0.01))
  assert_true((path[1] - expected_r1).abs() < 1.0e-8)
}

// ===========================================================================
// CIR Model Tests
// ===========================================================================

///|
test "cir_feller_condition" {
  // Feller satisfied: 2*0.2*0.05 = 0.02 > 0.01 = 0.1^2
  let ok = cir_feller_condition(rate_model_params(0.2, 0.05, 0.1, 0.04))
  assert_true(ok)
  // Feller violated: 2*0.1*0.05 = 0.01 < 0.04 = 0.2^2
  let violated = cir_feller_condition(rate_model_params(0.1, 0.05, 0.2, 0.04))
  assert_false(violated)
}

///|
test "cir_bond_price_at_zero" {
  let p = cir_bond_price(rate_model_params(0.2, 0.05, 0.1, 0.04), 0.0, 0.0)
  assert_true((p - 1.0).abs() < 1.0e-10)
}

///|
test "cir_bond_price_known" {
  let params = rate_model_params(0.2, 0.05, 0.1, 0.04)
  let p1 = cir_bond_price(params, 0.0, 1.0)
  // P(0,1) should be near exp(-0.04) ≈ 0.9608
  assert_true(p1 > 0.94 && p1 < 0.98)
}

///|
test "cir_bond_price_decreasing_in_maturity" {
  let params = rate_model_params(0.2, 0.05, 0.1, 0.04)
  let p1 = cir_bond_price(params, 0.0, 1.0)
  let p2 = cir_bond_price(params, 0.0, 2.0)
  let p5 = cir_bond_price(params, 0.0, 5.0)
  assert_true(p1 > p2)
  assert_true(p2 > p5)
}

///|
test "cir_zero_rate" {
  let params = rate_model_params(0.2, 0.05, 0.1, 0.04)
  let z = cir_zero_rate(params, 0.0, 1.0)
  // Should be between r0=0.04 and θ=0.05
  assert_true(z > 0.039 && z < 0.052)
}

///|
test "cir_expected_rate" {
  let params = rate_model_params(0.2, 0.05, 0.1, 0.04)
  // At t=0: E[r] = r0 = 0.04
  assert_true((cir_expected_rate(params, 0.0) - 0.04).abs() < 1.0e-10)
  // As t→∞: E[r] → θ = 0.05
  let r_long = cir_expected_rate(params, 100.0)
  assert_true((r_long - 0.05).abs() < 1.0e-3)
}

///|
test "cir_rate_variance" {
  let params = rate_model_params(0.2, 0.05, 0.1, 0.04)
  // At t=0: variance = 0
  assert_true(cir_rate_variance(params, 0.0) < 1.0e-15)
  // Variance increases with time (initially)
  assert_true(cir_rate_variance(params, 1.0) < cir_rate_variance(params, 10.0))
}

///|
test "cir_zcb_call_put_parity" {
  let params = rate_model_params(0.2, 0.05, 0.1, 0.04)
  let expiry = 1.0
  let maturity = 5.0
  let strike = 0.8
  let call = cir_zcb_call(params, expiry, maturity, strike)
  let put = cir_zcb_put(params, expiry, maturity, strike)
  let p_S = cir_bond_price(params, 0.0, expiry)
  let p_T = cir_bond_price(params, 0.0, maturity)
  let parity = call - put
  let intrinsic = p_T - strike * p_S
  assert_true((parity - intrinsic).abs() < 1.0e-4)
}

///|
test "cir_zcb_call_nonnegativity" {
  let params = rate_model_params(0.2, 0.05, 0.1, 0.04)
  let expiry = 0.5
  let maturity = 2.0
  let strike = 0.95
  let call = cir_zcb_call(params, expiry, maturity, strike)
  assert_true(call >= -1.0e-10)
}

///|
test "cir_simulate_nonnegativity" {
  let params = rate_model_params(0.2, 0.05, 0.1, 0.04)
  let n = 1000
  let dt = 0.01
  // Use deterministic Z path (all zeros) — drift only
  let z_path = Array::make(n, 0.0)
  let path = cir_simulate(params, n, dt, z_path)
  assert_eq(path.length(), n + 1)
  // With Feller condition satisfied, rate should stay non-negative
  for i = 0; i <= n; i = i + 1 {
    assert_true(path[i] >= 0.0)
  }
}

// ===========================================================================
// Hull-White Model Tests
// ===========================================================================

///|
test "hull_white_bond_price" {
  let params = rate_model_params(0.1, 0.05, 0.01, 0.04)
  // P_HW(0,T) = P_MKT(0,T)
  let p = hull_white_bond_price(params, 1.0, 0.95)
  assert_true((p - 0.95).abs() < 1.0e-10)
  // At T=0: P = 1
  let p0 = hull_white_bond_price(params, 0.0, 1.0)
  assert_true((p0 - 1.0).abs() < 1.0e-10)
}

///|
test "hull_white_zcb_call_put_parity" {
  let params = rate_model_params(0.1, 0.05, 0.01, 0.04)
  let expiry = 1.0
  let maturity = 5.0
  let strike = 0.8
  let p_S = 0.95
  let p_T = 0.80
  let call = hull_white_zcb_call(params, expiry, maturity, strike, p_S, p_T)
  let put = hull_white_zcb_put(params, expiry, maturity, strike, p_S, p_T)
  let parity = call - put
  let intrinsic = p_T - strike * p_S
  assert_true((parity - intrinsic).abs() < 1.0e-8)
}

///|
test "hull_white_zcb_call_nonnegativity" {
  let params = rate_model_params(0.1, 0.05, 0.01, 0.04)
  let expiry = 0.5
  let maturity = 2.0
  let strike = 0.95
  let p_S = 0.97
  let p_T = 0.90
  let call = hull_white_zcb_call(params, expiry, maturity, strike, p_S, p_T)
  assert_true(call >= 0.0)
}

///|
test "hull_white_theta" {
  let params = rate_model_params(0.1, 0.05, 0.01, 0.04)
  // Constant forward rate of 0.04
  let theta = hull_white_theta(params, 1.0, fn(_t) { 0.04 })
  // θ(1) = 0 (df/dt=0 for constant f) + 0.1*0.04 + correction
  // correction = 0.0001*(1-e^{-0.2})/(0.2) ≈ 0.0001*0.1813/0.2 ≈ 9.06e-5
  assert_true(theta > 0.004 && theta < 0.005)
}

///|
test "hull_white_simulate" {
  let params = rate_model_params(0.1, 0.05, 0.01, 0.04)
  let n = 100
  let dt = 0.01
  let theta_path = Array::make(n, 0.05)
  let z_path = Array::make(n, 0.0)
  let path = hull_white_simulate(params, n, dt, theta_path, z_path)
  assert_eq(path.length(), n + 1)
  assert_true((path[0] - 0.04).abs() < 1.0e-10)
  // With Z=0, deterministic path
  let expected_r1 = 0.04 * @math.exp(-0.001) + 0.05 * (1.0 - @math.exp(-0.001))
  assert_true((path[1] - expected_r1).abs() < 1.0e-8)
}

// ===========================================================================
// Cross-model consistency tests
// ===========================================================================

///|
test "vasicek_cir_same_expectation" {
  // Both models have the same expected rate when parameters match
  let vp = rate_model_params(0.2, 0.05, 0.01, 0.04)
  let cp = rate_model_params(0.2, 0.05, 0.01, 0.04)
  for t in [0.5, 1.0, 2.0, 5.0, 10.0] {
    let v_rate = vasicek_expected_rate(vp, t)
    let c_rate = cir_expected_rate(cp, t)
    assert_true((v_rate - c_rate).abs() < 1.0e-10)
  }
}

///|
test "rate_model_params_construct" {
  let p = rate_model_params(0.1, 0.05, 0.01, 0.04)
  assert_true((p.kappa - 0.1).abs() < 1.0e-10)
  assert_true((p.theta - 0.05).abs() < 1.0e-10)
  assert_true((p.sigma - 0.01).abs() < 1.0e-10)
  assert_true((p.r0 - 0.04).abs() < 1.0e-10)
}

///|
test "rate_model_kind_eq" {
  // Enum variants are read-only from test files; test via structural
  // equality of the model params and model functions instead.
  let p = rate_model_params(0.1, 0.05, 0.01, 0.04)
  // Vasicek and CIR share the same expectation formula
  let v = vasicek_expected_rate(p, 1.0)
  let c = cir_expected_rate(p, 1.0)
  assert_true((v - c).abs() < 1.0e-10)
}
