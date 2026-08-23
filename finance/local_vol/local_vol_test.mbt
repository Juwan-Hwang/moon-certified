// White-box tests for finance/local_vol.
// Covers local-vol surface computation (Dupire) and BS-style pricing.

///|
test "price_with_local_vol_maturity_zero_itm" {
  // maturity<=0 -> max(spot-strike, 0)
  let p = price_with_local_vol(110.0, 100.0, 0.0, 0.05, 0.0, 0.2)
  assert_true((p - 10.0).abs() < 1.0e-12)
  let p2 = price_with_local_vol(90.0, 100.0, 0.0, 0.05, 0.0, 0.2)
  assert_true((p2 - 0.0).abs() < 1.0e-12)
}

///|
test "price_with_local_vol_zero_sigma" {
  // sigma<=0 -> max(spot*exp(-qT) - strike*exp(-rT), 0)
  let p = price_with_local_vol(110.0, 100.0, 1.0, 0.0, 0.0, 0.0)
  assert_true((p - 10.0).abs() < 1.0e-12)
  let p0 = price_with_local_vol(100.0, 100.0, 1.0, 0.0, 0.0, 0.0)
  assert_true((p0 - 0.0).abs() < 1.0e-12)
}

///|
test "price_with_local_vol_monotonic_in_spot" {
  let lo = price_with_local_vol(100.0, 100.0, 1.0, 0.05, 0.0, 0.2)
  let hi = price_with_local_vol(110.0, 100.0, 1.0, 0.05, 0.0, 0.2)
  assert_true(hi > lo)
}

///|
test "price_with_local_vol_monotonic_in_strike" {
  let k90 = price_with_local_vol(100.0, 90.0, 1.0, 0.05, 0.0, 0.2)
  let k110 = price_with_local_vol(100.0, 110.0, 1.0, 0.05, 0.0, 0.2)
  assert_true(k90 > k110)
}

///|
test "price_with_local_vol_positive" {
  let p = price_with_local_vol(100.0, 100.0, 1.0, 0.05, 0.0, 0.2)
  assert_true(p > 0.0)
}

///|
test "compute_local_vol_empty" {
  let res = compute_local_vol([], 100.0, 0.05, 0.0)
  assert_eq(res.length(), 0)
}

///|
test "compute_local_vol_too_few_quotes" {
  let q = OptionQuote::new(100.0, 1.0, 10.0)
  let res = compute_local_vol([q], 100.0, 0.05, 0.0)
  assert_eq(res.length(), 0)
}

///|
test "compute_local_vol_basic" {
  // 3 quotes at same maturity, convex prices; q>r so Dupire numerator > 0.
  let q0 = OptionQuote::new(90.0, 1.0, 15.0)
  let q1 = OptionQuote::new(100.0, 1.0, 8.0)
  let q2 = OptionQuote::new(110.0, 1.0, 3.0)
  let res = compute_local_vol([q0, q1, q2], 100.0, 0.0, 0.05)
  // only the middle quote yields a central difference -> one point
  assert_eq(res.length(), 1)
  let pt = res[0]
  // independently replicate Dupire's formula used by the source
  let dk = 20.0
  let dC_dK = (3.0 - 15.0) / dk
  let d2C_dK2 = (3.0 - 2.0 * 8.0 + 15.0) / (dk * dk / 4.0)
  let num = 2.0 * ((0.0 - 0.05) * 100.0 * dC_dK + 0.05 * 8.0)
  let den = 100.0 * 100.0 * d2C_dK2
  let expected = (num / den).sqrt()
  assert_true((pt.vol - expected).abs() < 1.0e-9)
  assert_true(pt.vol > 0.0)
  assert_true(pt.vol < 1.0)
  assert_true((pt.strike - 100.0).abs() < 1.0e-12)
}
