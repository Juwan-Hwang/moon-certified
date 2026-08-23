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
const TWO_PI : Double = 6.28318530717958647693

///|
test "mel_scale_roundtrip" {
  // HTK: mel(0) = 0; roundtrip identity within tolerance.
  assert_true(hz_to_mel(0.0).abs() < 1.0e-15)
  for f in [100.0, 440.0, 1000.0, 4000.0, 7999.0] {
    let m = hz_to_mel(f)
    assert_true((mel_to_hz(m) - f).abs() < 1.0e-9 * f)
  }
  // Known HTK value: mel(1000 Hz) ≈ 1000.05
  assert_true((hz_to_mel(1000.0) - 1000.0).abs() < 0.1)
  // Monotonicity
  let mut prev = -1.0
  for f in [0.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0] {
    let m = hz_to_mel(f)
    assert_true(m > prev)
    prev = m
  }
}

///|
test "mel_filterbank_structure" {
  let bank = unwrap_or_fail(mel_filterbank(26, 512, 16000, 0.0, 8000.0))
  assert_eq(bank.length(), 26)
  for row in bank {
    assert_eq(row.length(), 257) // n_fft/2 + 1
    let mut sum = 0.0
    for v in row {
      assert_true(v >= 0.0)
      sum += v
    }
    assert_true(sum > 0.0) // every filter covers some bins
  }
  // Triangles peak at 1.0 at their center.
  for row in bank {
    let mut peak = 0.0
    for v in row {
      if v > peak {
        peak = v
      }
    }
    assert_true(peak > 0.5 && peak <= 1.0 + 1.0e-12)
  }
  // Invalid parameters
  expect_none(mel_filterbank(1, 512, 16000, 0.0, 8000.0))
  expect_none(mel_filterbank(26, 8, 16000, 0.0, 8000.0))
  expect_none(mel_filterbank(26, 512, 16000, 900.0, 800.0))
  expect_none(mel_filterbank(26, 512, 16000, 0.0, 9000.0))
  expect_none(mel_filterbank(26, 512, 0, 0.0, 8000.0))
}

///|
test "frame_signal_counts" {
  let n = 1000
  let x = Array::makei(n, fn(i) { i.to_double() })
  let frames = unwrap_or_fail(frame_signal(x, 400, 160))
  // 1 + (1000−400)/160 = 4 frames
  assert_eq(frames.length(), 4)
  assert_eq(frames[0][0], 0.0)
  assert_eq(frames[1][0], 160.0)
  assert_eq(frames[3][399], 3.0 * 160.0 + 399.0)
  // Signal shorter than one frame → zero frames
  let empty_frames = unwrap_or_fail(
    frame_signal(Array::make(10, 0.0), 400, 160),
  )
  assert_eq(empty_frames.length(), 0)
  // Invalid
  expect_none(frame_signal(x, 0, 160))
  expect_none(frame_signal(x, 400, 0))
  expect_none(frame_signal(x, 400, -5))
}

///|
test "power_spectrum_sine_peak" {
  // Sine at exactly bin k (16 kHz rate, 512 FFT): k = f / (rate/n_fft).
  let rate = 16000
  let n_fft = 512
  let freq = 2000.0 // bin 64
  let frame_len = 512
  let x = Array::make(frame_len, 0.0)
  for i = 0; i < frame_len; i = i + 1 {
    x[i] = @math.sin(TWO_PI * freq * i.to_double() / rate.to_double())
  }
  let spec = unwrap_or_fail(
    power_spectrum(x, n_fft, @filter_design.Rectangular),
  )
  assert_eq(spec.length(), 257)
  let mut best_bin = 0
  let mut best_val = -1.0
  for k = 0; k < spec.length(); k = k + 1 {
    if spec[k] > best_val {
      best_val = spec[k]
      best_bin = k
    }
  }
  // Spectral leakage with rectangular window on an exact bin: sharp peak.
  assert_eq(best_bin, 64)
  // Parseval check: Σ power bins ≈ mean-square energy of the windowed frame.
  // Rectangular window, full-length sine: energy = n/2 per side.
  let mut total = 0.0
  for k = 0; k < spec.length(); k = k + 1 {
    total += spec[k]
  }
  // Only half the spectrum is returned; the other half mirrors it.
  assert_true(
    (2.0 * total - frame_len.to_double() * 0.5).abs() /
    (frame_len.to_double() * 0.5) <
    1.0e-9,
  )
  // Invalid: n_fft smaller than frame or odd.
  expect_none(power_spectrum(x, 256, @filter_design.Hamming))
  expect_none(power_spectrum(x, 513, @filter_design.Hamming))
}

///|
test "mfcc_shapes_and_finiteness" {
  let config = mfcc_default_config()
  let n = config.frame_len + 10 * config.hop_len
  let x = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    x[i] = @math.sin(
      TWO_PI * 440.0 * i.to_double() / config.sample_rate.to_double(),
    )
  }
  let feats = unwrap_or_fail(mfcc(x, config))
  // 1 + floor((n − 400)/160) = 11 frames
  assert_eq(feats.length(), 11)
  for row in feats {
    assert_eq(row.length(), 13)
    for v in row {
      assert_true(!v.is_nan())
      assert_true(!v.is_inf())
    }
  }
  // c0 (log-energy term) should dominate in magnitude for a loud signal.
  for row in feats {
    let mut max_rest = 0.0
    for k = 1; k < 13; k = k + 1 {
      if row[k].abs() > max_rest {
        max_rest = row[k].abs()
      }
    }
    assert_true(row[0].abs() > max_rest)
  }
}

///|
test "mfcc_rejects_invalid_config" {
  fn bad_config(mutate : (MfccConfig) -> MfccConfig) -> Bool {
    match mfcc([0.1, 0.2, 0.3], mutate(mfcc_default_config())) {
      Some(_) => false
      None => true
    }
  }

  assert_true(bad_config(fn(c) { { ..c, sample_rate: 0 } }))
  assert_true(bad_config(fn(c) { { ..c, n_cepstral: 0 } }))
  assert_true(bad_config(fn(c) { { ..c, n_cepstral: 41 } })) // > n_mels
  assert_true(bad_config(fn(c) { { ..c, pre_emphasis: 1.0 } })) // must be < 1
  assert_true(bad_config(fn(c) { { ..c, fmax: 9000.0 } })) // above Nyquist
  // Too short to hold a single frame (valid config, short signal)
  expect_none(mfcc(Array::make(100, 0.0), mfcc_default_config()))
}

///|
test "delta_regression" {
  // Linear ramp rows: delta of a linear sequence is its slope (=1).
  let feats : Array[Array[Double]] = []
  for t = 0; t < 10; t = t + 1 {
    feats.push([t.to_double(), 2.0 * t.to_double()])
  }
  let d = unwrap_or_fail(delta(feats, 2))
  assert_eq(d.length(), 10)
  // Interior frames: exact slope; boundary frames use replication → smaller.
  for t = 2; t < 8; t = t + 1 {
    assert_true((d[t][0] - 1.0).abs() < 1.0e-12)
    assert_true((d[t][1] - 2.0).abs() < 1.0e-12)
  }
  assert_true(d[0][0] >= 0.0 && d[0][0] <= 1.0)
  // Constant features → zero delta everywhere.
  let flat : Array[Array[Double]] = []
  for _t = 0; _t < 6; _t = _t + 1 {
    flat.push([3.14, -1.0])
  }
  let df = unwrap_or_fail(delta(flat, 2))
  for row in df {
    for v in row {
      assert_true(v.abs() < 1.0e-15)
    }
  }
  expect_none(delta([], 2))
  expect_none(delta(flat, 0))
}

///|
test "resample_linear_basics" {
  // Identity when rates match.
  let x = [0.0, 1.0, 2.0, 3.0]
  let same = unwrap_or_fail(resample_linear(x, 8000, 8000))
  assert_eq(same.length(), 4)
  // Upsample 2×: length ceil(4·2/1)=8, values interpolate.
  let up = unwrap_or_fail(resample_linear(x, 8000, 16000))
  assert_eq(up.length(), 8)
  assert_true(up[0].abs() < 1.0e-12)
  assert_true((up[2] - 1.0).abs() < 1.0e-12)
  assert_true((up[1] - 0.5).abs() < 1.0e-12)
  // Downsample 2×: length ceil(4/2)=2.
  let down = unwrap_or_fail(resample_linear(x, 8000, 4000))
  assert_eq(down.length(), 2)
  assert_true(down[0].abs() < 1.0e-12)
  assert_true((down[1] - 2.0).abs() < 1.0e-12)
  // Empty input
  let empty = unwrap_or_fail(resample_linear([], 8000, 16000))
  assert_eq(empty.length(), 0)
  // Invalid rates
  expect_none(resample_linear(x, 0, 16000))
  expect_none(resample_linear(x, 8000, -1))
}

///|
test "resample_preserves_tone_frequency" {
  // 220 Hz tone sampled at 44100 → resampled to 16000 must still be ~220 Hz,
  // measured by rising zero crossings over a 1-second window.
  fn make_tone(rate : Int, samples : Int, freq : Double) -> Array[Double] {
    let x = Array::make(samples, 0.0)
    for i = 0; i < samples; i = i + 1 {
      x[i] = @math.sin(TWO_PI * freq * i.to_double() / rate.to_double())
    }
    x
  }

  fn count_zero_crossings(x : Array[Double]) -> Int {
    let mut c = 0
    for i = 1; i < x.length(); i = i + 1 {
      if x[i - 1] <= 0.0 && x[i] > 0.0 {
        c = c + 1
      }
    }
    c
  }

  let duration = 1.0
  let orig = make_tone(44100, (44100.0 * duration).to_int(), 220.0)
  let rs = unwrap_or_fail(resample_linear(orig, 44100, 16000))
  assert_eq(rs.length(), (16000.0 * duration).to_int())
  let f_orig = count_zero_crossings(orig).to_double() / duration
  let f_rs = count_zero_crossings(rs).to_double() / duration
  // Rising crossings per second ≈ frequency; allow small interpolation error.
  assert_true((f_orig - 220.0).abs() < 1.0)
  assert_true((f_rs - 220.0).abs() < 1.0)
}
