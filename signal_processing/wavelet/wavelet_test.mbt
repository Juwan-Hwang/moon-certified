///|
/// Unwrap an Option or fail the test (never returns on None).
fn[T] unwrap_or_fail(o : T?) -> T {
  match o {
    Some(v) => v
    None => abort("unexpected None in test")
  }
}

///|
/// Assert that an Option.is_empty().
fn[T] expect_none(o : T?) -> Unit {
  match o {
    Some(_) => abort("expected None but got Some")
    None => ()
  }
}

///|
/// Deterministic xorshift64 PRNG for reproducible tests (Marsaglia 2003).
fn test_rng_new(seed : UInt64) -> () -> UInt64 {
  let mut state = if seed == 0UL { 0x9E3779B97F4A7C15UL } else { seed }
  fn() -> UInt64 {
    let x = state
    let y = x ^ (x << 13)
    let z = y ^ (y >> 7)
    let w = z ^ (z << 17)
    state = w
    w
  }
}

///|
/// Uniform Double in (−1, 1) from a UInt64 state.
fn rng_uniform(next : () -> UInt64) -> Double {
  (next() >> 11).to_double() / 9007199254740992.0 * 2.0 - 1.0
}

///|
fn max_abs_diff(a : Array[Double], b : Array[Double]) -> Double {
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  let mut m = 0.0
  for i = 0; i < n; i = i + 1 {
    let d = (a[i] - b[i]).abs()
    if d > m {
      m = d
    }
  }
  m
}

///|
fn energy(x : Array[Double]) -> Double {
  let mut s = 0.0
  for v in x {
    s = s + v * v
  }
  s
}

///|
const SQRT2 : Double = 1.4142135623730951

///|
const TWO_PI : Double = 6.28318530717958647693

///|
test "filter_properties_all_wavelets" {
  let wavelets : Array[Wavelet] = [Haar, Db2, Db4, Db6, Db8]
  for w in wavelets {
    let h = analysis_lowpass(w)
    let g = analysis_highpass(w)
    let n = h.length()
    assert_eq(g.length(), n)
    // Normalization: Σh = √2, Σh² = 1
    let mut sum_h = 0.0
    let mut sum_h2 = 0.0
    let mut sum_g = 0.0
    let mut sum_g2 = 0.0
    for i = 0; i < n; i = i + 1 {
      sum_h = sum_h + h[i]
      sum_h2 = sum_h2 + h[i] * h[i]
      sum_g = sum_g + g[i]
      sum_g2 = sum_g2 + g[i] * g[i]
    }
    assert_true((sum_h - SQRT2).abs() < 1.0e-12)
    // Coefficients carry 16 significant digits; allow a few ulps of slack
    // for the 16-term accumulation on db8.
    assert_true((sum_h2 - 1.0).abs() < 5.0e-12)
    assert_true(sum_g.abs() < 5.0e-12)
    assert_true((sum_g2 - 1.0).abs() < 5.0e-12)
    // Orthonormality across even shifts (zero-padded, no wraparound):
    // Σ h[i]·h[i+2k] = δ(k), and cross-orthogonality Σ h[i]·g[i+2k] = 0.
    for shift = 2; shift < n; shift = shift + 2 {
      let mut sh = 0.0
      let mut sg = 0.0
      for i = 0; i + shift < n; i = i + 1 {
        sh = sh + h[i] * h[i + shift]
        sg = sg + h[i] * g[i + shift]
      }
      assert_true(sh.abs() < 1.0e-12)
      assert_true(sg.abs() < 1.0e-12)
    }
  }
}

///|
test "qmf_definition" {
  // g[i] = (−1)^i · h[L−1−i]
  let h = analysis_lowpass(Db4)
  let g = analysis_highpass(Db4)
  for i = 0; i < h.length(); i = i + 1 {
    let expected = if i % 2 == 0 {
      h[h.length() - 1 - i]
    } else {
      -h[h.length() - 1 - i]
    }
    assert_true((g[i] - expected).abs() < 1.0e-15)
  }
}

///|
test "dwt_haar_known_values" {
  let x = [1.0, 2.0, 3.0, 4.0]
  let (ca, cd) = unwrap_or_fail(dwt(x, Haar))
  assert_eq(ca.length(), 2)
  assert_true((ca[0] - 3.0 / SQRT2).abs() < 1.0e-12)
  assert_true((ca[1] - 7.0 / SQRT2).abs() < 1.0e-12)
  assert_true((cd[0] + 1.0 / SQRT2).abs() < 1.0e-12)
  assert_true((cd[1] + 1.0 / SQRT2).abs() < 1.0e-12)
}

///|
test "idwt_haar_known_values" {
  let ca = [3.0 / SQRT2, 7.0 / SQRT2]
  let cd = [-1.0 / SQRT2, -1.0 / SQRT2]
  let y = unwrap_or_fail(idwt(ca, cd, Haar))
  assert_eq(y.length(), 4)
  assert_true(max_abs_diff(y, [1.0, 2.0, 3.0, 4.0]) < 1.0e-12)
}

///|
test "perfect_reconstruction_single_level" {
  let wavelets : Array[Wavelet] = [Haar, Db2, Db4, Db6, Db8]
  let next = test_rng_new(42)
  for w in wavelets {
    for n in [2, 4, 16, 64] {
      let x = Array::make(n, 0.0)
      for i = 0; i < n; i = i + 1 {
        x[i] = rng_uniform(next)
      }
      let (ca, cd) = unwrap_or_fail(dwt(x, w))
      let y = unwrap_or_fail(idwt(ca, cd, w))
      assert_true(max_abs_diff(y, x) < 1.0e-9)
    }
  }
}

///|
test "perfect_reconstruction_multilevel" {
  let wavelets : Array[Wavelet] = [Haar, Db2, Db4, Db6, Db8]
  let next = test_rng_new(1234)
  for w in wavelets {
    let n = 256
    let x = Array::make(n, 0.0)
    for i = 0; i < n; i = i + 1 {
      x[i] = rng_uniform(next)
    }
    let maxlv = max_level(n, w)
    assert_true(maxlv >= 4)
    for level = 1; level <= maxlv; level = level + 1 {
      let d = unwrap_or_fail(wavedec(x, w, level))
      let y = unwrap_or_fail(waverec(d, w))
      assert_true(max_abs_diff(y, x) < 1.0e-9)
    }
  }
}

///|
test "parseval_energy_conservation" {
  let wavelets : Array[Wavelet] = [Haar, Db2, Db4, Db6, Db8]
  let next = test_rng_new(777)
  for w in wavelets {
    let n = 128
    let x = Array::make(n, 0.0)
    for i = 0; i < n; i = i + 1 {
      x[i] = rng_uniform(next)
    }
    // Single level
    let (ca, cd) = unwrap_or_fail(dwt(x, w))
    let e1 = energy(ca) + energy(cd)
    assert_true((e1 - energy(x)).abs() / energy(x) < 1.0e-10)
    // Multi level
    let d = unwrap_or_fail(wavedec(x, w, 4))
    assert_eq(d.coeffs.length(), n)
    assert_eq(d.original_len, n)
    let mut total = 0
    for l in d.lengths {
      total = total + l
    }
    assert_eq(total, n)
    assert_true((energy(d.coeffs) - energy(x)).abs() / energy(x) < 1.0e-10)
  }
}

///|
test "constant_signal_zero_details" {
  let wavelets : Array[Wavelet] = [Haar, Db2, Db4, Db6, Db8]
  for w in wavelets {
    let x = Array::make(64, 2.5)
    let d = unwrap_or_fail(wavedec(x, w, 3))
    let offset = d.lengths[0]
    let mut max_detail = 0.0
    for i = offset; i < d.coeffs.length(); i = i + 1 {
      let m = d.coeffs[i].abs()
      if m > max_detail {
        max_detail = m
      }
    }
    // Detail coefficients vanish for constant input (vanishing moments).
    assert_true(max_detail < 1.0e-10)
  }
}

///|
test "wavedec_level_clamping" {
  let x = Array::make(64, 1.0)
  // Requesting more levels than max_level clamps silently (64/Haar →
  // 5 levels, coarsest band of length 2).
  let d = unwrap_or_fail(wavedec(x, Haar, 100))
  assert_eq(d.lengths[0], 2)
  assert_eq(d.lengths.length(), 6)
  // Too short for even one level → None
  expect_none(wavedec([], Haar, 1))
  expect_none(wavedec([1.0], Haar, 1))
  // Odd length → None
  expect_none(wavedec([1.0, 2.0, 3.0], Haar, 1))
  // Filter longer than any possible coarsest band → max_level 0 → None
  expect_none(wavedec(Array::make(4, 1.0), Db8, 1))
}

///|
test "max_level_values" {
  // Constraint: every band keeps at least one full filter length.
  assert_eq(max_level(1024, Haar), 9)
  assert_eq(max_level(1024, Db8), 6)
  assert_eq(max_level(100, Haar), 2)
  assert_eq(max_level(8, Db8), 0)
  assert_eq(max_level(0, Haar), 0)
  assert_eq(max_level(-4, Haar), 0)
}

///|
test "threshold_functions" {
  // Soft: sign(c)·max(|c|−λ, 0)
  assert_true((soft_threshold(3.0, 1.0) - 2.0).abs() < 1.0e-15)
  assert_true((soft_threshold(-3.0, 1.0) + 2.0).abs() < 1.0e-15)
  assert_true(soft_threshold(0.5, 1.0) == 0.0)
  assert_true((soft_threshold(3.0, 0.0) - 3.0).abs() < 1.0e-15)
  // Hard: keep or kill
  assert_true(hard_threshold(3.0, 1.0) == 3.0)
  assert_true(hard_threshold(-3.0, 1.0) == -3.0)
  assert_true(hard_threshold(0.5, 1.0) == 0.0)
}

///|
test "threshold_details_preserves_approximation" {
  let x = Array::make(16, 0.0)
  let next = test_rng_new(9)
  for i = 0; i < 16; i = i + 1 {
    x[i] = rng_uniform(next)
  }
  let d = unwrap_or_fail(wavedec(x, Db2, 2))
  let approx = Array::make(d.lengths[0], 0.0)
  for i = 0; i < d.lengths[0]; i = i + 1 {
    approx[i] = d.coeffs[i]
  }
  threshold_details(d, 1.0e6, Soft)
  for i = 0; i < approx.length(); i = i + 1 {
    assert_true((d.coeffs[i] - approx[i]).abs() < 1.0e-15)
  }
  for i = approx.length(); i < d.coeffs.length(); i = i + 1 {
    assert_true(d.coeffs[i] == 0.0)
  }
}

///|
test "universal_threshold_value" {
  // λ = σ·√(2 ln n). Verify via the exact ratio for powers of two:
  // λ(4096)/λ(1024) = √(ln 4096 / ln 1024) = √1.2
  let l1 = universal_threshold(1024, 1.0)
  let l2 = universal_threshold(4096, 1.0)
  assert_true((l2 / l1 - 1.0954451150103323).abs() < 1.0e-12)
  // Absolute sanity bound: √(2 ln 1024) ∈ (3.72, 3.73)
  assert_true(l1 > 3.72 && l1 < 3.73)
  assert_true(universal_threshold(0, 1.0) == 0.0)
  assert_true(universal_threshold(10, 0.0) == 0.0)
}

///|
test "estimate_noise_mad" {
  // Finest band (last stored) = [1, −1] → |·| = [1,1], median 1
  // σ̂ = 1 / 0.6745; approximation [8,8], coarser detail [2, −2].
  let d : Wavedec = Wavedec::make(
    [8.0, 8.0, 2.0, -2.0, 1.0, -1.0],
    [2, 2, 2],
    6,
  )
  let sigma = unwrap_or_fail(estimate_noise(d))
  assert_true((sigma - 1.0 / 0.6745).abs() < 1.0e-12)
  expect_none(estimate_noise(Wavedec::make([1.0, 2.0], [2], 2)))
}

///|
test "denoise_improves_snr" {
  // Clean signal: sparse spikes — the canonical VisuShrink-friendly case.
  // Hard thresholding removes most noise without shrinkage bias.
  let n = 256
  let clean = Array::make(n, 0.0)
  for i in [32, 96, 160, 224] {
    clean[i] = 3.0
  }
  let next = test_rng_new(20260822)
  let noisy = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    // Box–Muller from two uniforms, scaled to σ = 0.05
    let u1 = (rng_uniform(next) + 1.0) * 0.5
    let u2 = (rng_uniform(next) + 1.0) * 0.5
    let g = (-2.0 * @math.ln(u1)).sqrt() * @math.cos(TWO_PI * u2)
    noisy[i] = clean[i] + 0.05 * g
  }
  let signal_power = energy(clean) / n.to_double()
  // Noise power measured against the clean reference.
  let mut nm = 0.0
  for i = 0; i < n; i = i + 1 {
    let d = noisy[i] - clean[i]
    nm += d * d
  }
  let noise_mse = nm / n.to_double()
  let snr_before = 10.0 * @math.log10(signal_power / noise_mse)
  let denoised = unwrap_or_fail(denoise(noisy, Db4, 6, Hard))
  assert_eq(denoised.length(), n)
  // Error of the denoised signal against the clean reference.
  let mut se = 0.0
  for i = 0; i < n; i = i + 1 {
    let d = denoised[i] - clean[i]
    se += d * d
  }
  let err_mse = se / n.to_double()
  // Denoising must reduce the error power by a clear margin (≥ 30% here).
  assert_true(err_mse < 0.7 * noise_mse)
  let snr_after = 10.0 * @math.log10(signal_power / err_mse)
  assert_true(snr_after > snr_before)
}

///|
test "denoise_invalid_input" {
  expect_none(denoise([], Haar, 3, Soft))
  expect_none(denoise([1.0], Db2, 3, Soft))
  expect_none(denoise([1.0, 2.0, 3.0], Haar, 3, Soft))
}

///|
test "waverec_rejects_corrupt_decomposition" {
  let x = Array::make(16, 1.0)
  let d = unwrap_or_fail(wavedec(x, Haar, 2))
  // Length mismatch between coeffs and original_len
  expect_none(waverec(Wavedec::make([], d.lengths, 16), Haar))
  // Zero-length detail band
  let truncated = Array::make(14, 0.0)
  for i = 0; i < 14; i = i + 1 {
    truncated[i] = d.coeffs[i]
  }
  expect_none(waverec(Wavedec::make(truncated, [4, 4, 4, 0], 12), Haar))
  // idwt mismatched band lengths
  expect_none(idwt([1.0], [], Haar))
  expect_none(idwt([], [], Haar))
}
