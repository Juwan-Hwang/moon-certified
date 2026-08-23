///|
test "yc_linear_interpolation" {
  let curve = yield_curve_linear([1.0, 2.0, 5.0], [0.03, 0.04, 0.05])
  assert_eq(yield_curve_size(curve), 3)
  // At tenor points, rate should match exactly
  assert_true((yield_curve_zero_rate(curve, 1.0) - 0.03).abs() < 1.0e-10)
  assert_true((yield_curve_zero_rate(curve, 2.0) - 0.04).abs() < 1.0e-10)
  assert_true((yield_curve_zero_rate(curve, 5.0) - 0.05).abs() < 1.0e-10)
  // Linear interpolation at t=1.5: 0.03 + (0.04-0.03)*(0.5/1.0) = 0.035
  assert_true((yield_curve_zero_rate(curve, 1.5) - 0.035).abs() < 1.0e-10)
  // Linear interpolation at t=3.5: 0.04 + (0.05-0.04)*(1.5/3.0) = 0.045
  assert_true((yield_curve_zero_rate(curve, 3.5) - 0.045).abs() < 1.0e-10)
}

///|
test "yc_extrapolation" {
  let curve = yield_curve_linear([1.0, 5.0], [0.03, 0.05])
  // Before first tenor: flat at first rate
  assert_true((yield_curve_zero_rate(curve, 0.5) - 0.03).abs() < 1.0e-10)
  // After last tenor: flat at last rate
  assert_true((yield_curve_zero_rate(curve, 10.0) - 0.05).abs() < 1.0e-10)
}

///|
test "yc_discount_factor" {
  let curve = yield_curve_linear([1.0, 2.0], [0.05, 0.05])
  // df(0) = 1.0
  assert_true((yield_curve_discount_factor(curve, 0.0) - 1.0).abs() < 1.0e-10)
  // df(1) = exp(-0.05) ≈ 0.9512
  let df1 = yield_curve_discount_factor(curve, 1.0)
  assert_true((df1 - 0.951229).abs() < 1.0e-4)
  // df(2) = exp(-0.10) ≈ 0.9048
  let df2 = yield_curve_discount_factor(curve, 2.0)
  assert_true((df2 - 0.904837).abs() < 1.0e-4)
}

///|
test "yc_forward_rate_linear" {
  // Flat curve: forward rate = zero rate
  let flat = yield_curve_linear([1.0, 5.0], [0.04, 0.04])
  let fr = yield_curve_forward_rate(flat, 3.0)
  assert_true((fr - 0.04).abs() < 1.0e-10)
  // Upward sloping: forward > zero rate
  let slope = yield_curve_linear([1.0, 5.0], [0.03, 0.07])
  let fr2 = yield_curve_forward_rate(slope, 3.0)
  let zr = yield_curve_zero_rate(slope, 3.0)
  assert_true(fr2 > zr) // Forward should exceed spot for upward curve
}

///|
test "yc_forward_rate_simple" {
  let curve = yield_curve_linear([1.0, 2.0], [0.03, 0.05])
  // f(1, 2) = (0.05*2 - 0.03*1) / (2-1) = 0.07
  let fr = yield_curve_forward_rate_simple(curve, 1.0, 2.0)
  assert_true((fr - 0.07).abs() < 1.0e-10)
}

///|
test "yc_log_linear_interpolation" {
  let curve = yield_curve_log_linear([1.0, 2.0], [0.03, 0.05])
  // At tenor points, should match
  assert_true((yield_curve_zero_rate(curve, 1.0) - 0.03).abs() < 1.0e-10)
  assert_true((yield_curve_zero_rate(curve, 2.0) - 0.05).abs() < 1.0e-10)
  // At t=1.5, the log-linear rate should be between 0.03 and 0.05
  let r = yield_curve_zero_rate(curve, 1.5)
  assert_true(r > 0.03 && r < 0.05)
}

///|
test "yc_cubic_spline_interpolation" {
  let curve = yield_curve_cubic_spline([1.0, 2.0, 3.0, 5.0], [
    0.03, 0.035, 0.04, 0.05,
  ])
  // At tenor points, should match exactly
  assert_true((yield_curve_zero_rate(curve, 1.0) - 0.03).abs() < 1.0e-10)
  assert_true((yield_curve_zero_rate(curve, 2.0) - 0.035).abs() < 1.0e-10)
  assert_true((yield_curve_zero_rate(curve, 3.0) - 0.04).abs() < 1.0e-10)
  assert_true((yield_curve_zero_rate(curve, 5.0) - 0.05).abs() < 1.0e-10)
  // Interpolated values should be reasonable
  let r = yield_curve_zero_rate(curve, 4.0)
  assert_true(r > 0.04 && r < 0.05)
}

///|
test "yc_bootstrap_zero_coupon" {
  // Zero-coupon bond prices
  // Price(1yr) = 0.95 → r = -ln(0.95)/1 ≈ 0.0513
  // Price(2yr) = 0.90 → r = -ln(0.90)/2 ≈ 0.0527
  let curve = bootstrap_from_zero_coupon_bonds([1.0, 2.0], [0.95, 0.90])
  let r1 = yield_curve_zero_rate(curve, 1.0)
  let r2 = yield_curve_zero_rate(curve, 2.0)
  assert_true((r1 - 0.051293).abs() < 1.0e-4)
  assert_true((r2 - 0.052680).abs() < 1.0e-4)
}

///|
test "yc_bootstrap_coupon_bonds" {
  // 1-year bond: 5% coupon, price 0.995 → r1 = -ln(1.05/0.995)/1
  // 2-year bond: 5% coupon, price 0.985 → need to discount year 1 coupon at r1
  let curve = bootstrap_from_coupon_bonds([1.0, 2.0], [0.05, 0.05], [
    0.995, 0.985,
  ])
  let r1 = yield_curve_zero_rate(curve, 1.0)
  // r1 = -ln((0.995 - 0) / 1.05) / 1 = -ln(0.9476) ≈ 0.0538
  assert_true(r1 > 0.04 && r1 < 0.07)
  let r2 = yield_curve_zero_rate(curve, 2.0)
  assert_true(r2 > 0.04 && r2 < 0.08)
}

///|
test "yc_nelson_siegel_eval" {
  let params = ns_params(0.05, -0.02, 0.01, 2.0)
  // At tau → 0: y → beta1 + beta2 = 0.03
  let y0 = nelson_siegel_eval(params, 0.001)
  assert_true((y0 - 0.03).abs() < 1.0e-3)
  // At tau → ∞: y → beta1 = 0.05
  let y_inf = nelson_siegel_eval(params, 100.0)
  assert_true((y_inf - 0.05).abs() < 1.0e-3)
  // At tau = lambda: y is between beta1 and beta1+beta2
  let y_mid = nelson_siegel_eval(params, 2.0)
  assert_true(y_mid > 0.03 && y_mid < 0.05)
}

///|
test "yc_nelson_siegel_curve" {
  let params = ns_params(0.04, -0.01, 0.005, 3.0)
  let curve = nelson_siegel_curve(params)
  assert_true(yield_curve_size(curve) == 11)
  // All rates should be positive
  for i = 0; i < 11; i = i + 1 {
    assert_true(yield_curve_zero_rate_at(curve, i) > 0.0)
  }
}

///|
test "yc_nelson_siegel_fit" {
  // Generate data from known NS parameters, then fit and check recovery
  let true_params = ns_params(0.05, -0.02, 0.01, 2.0)
  let tenors = [0.5, 1.0, 2.0, 3.0, 5.0, 7.0, 10.0]
  let rates : Array[Double] = []
  for i = 0; i < tenors.length(); i = i + 1 {
    rates.push(nelson_siegel_eval(true_params, tenors[i]))
  }
  let fitted = nelson_siegel_fit(tenors, rates)
  // Check that fitted rates are close to true rates
  for i = 0; i < tenors.length(); i = i + 1 {
    let fitted_rate = nelson_siegel_eval(fitted, tenors[i])
    let true_rate = rates[i]
    assert_true((fitted_rate - true_rate).abs() < 1.0e-3)
  }
}

///|
test "yc_nss_eval" {
  let params = nss_params(0.05, -0.02, 0.01, 0.005, 2.0, 5.0)
  // At tau → 0: y → beta1 + beta2 = 0.03
  let y0 = nss_eval(params, 0.001)
  assert_true((y0 - 0.03).abs() < 1.0e-3)
  // At tau → ∞: y → beta1 = 0.05
  let y_inf = nss_eval(params, 100.0)
  assert_true((y_inf - 0.05).abs() < 1.0e-3)
}

///|
test "yc_nss_curve" {
  let params = nss_params(0.04, -0.01, 0.005, 0.002, 2.0, 7.0)
  let curve = nss_curve(params)
  assert_true(yield_curve_size(curve) == 11)
  // All rates should be reasonable
  for i = 0; i < 11; i = i + 1 {
    let r = yield_curve_zero_rate_at(curve, i)
    assert_true(r > 0.0 && r < 0.1)
  }
}

///|
test "yc_accessors" {
  let curve = yield_curve_linear([1.0, 3.0, 5.0], [0.03, 0.04, 0.05])
  assert_eq(yield_curve_size(curve), 3)
  assert_true((yield_curve_tenor(curve, 0) - 1.0).abs() < 1.0e-10)
  assert_true((yield_curve_tenor(curve, 2) - 5.0).abs() < 1.0e-10)
  assert_true((yield_curve_zero_rate_at(curve, 1) - 0.04).abs() < 1.0e-10)
  let m = yield_curve_method(curve)
  assert_true(m is Linear)
}

///|
test "yc_single_point" {
  let curve = yield_curve_linear([2.0], [0.05])
  // With a single point, all rates are flat at 0.05
  assert_true((yield_curve_zero_rate(curve, 1.0) - 0.05).abs() < 1.0e-10)
  assert_true((yield_curve_zero_rate(curve, 5.0) - 0.05).abs() < 1.0e-10)
}
