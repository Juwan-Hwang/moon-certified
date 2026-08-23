///|
test "window_rectangular" {
  let w = window(Rectangular, 8)
  assert_eq(w.length(), 8)
  for i = 0; i < 8; i = i + 1 {
    assert_true(w[i] == 1.0)
  }
}

///|
test "window_hamming" {
  let w = window(Hamming, 11)
  assert_eq(w.length(), 11)
  // Symmetric
  for i = 0; i < 5; i = i + 1 {
    assert_true((w[i] - w[10 - i]).abs() < 1.0e-12)
  }
  // Center should be near 1.0
  assert_true(w[5] > 0.99)
  // Ends should be near 0.08
  assert_true(w[0] < 0.1)
}

///|
test "window_hann" {
  let w = window(Hann, 9)
  assert_eq(w.length(), 9)
  // Ends should be 0
  assert_true(w[0].abs() < 1.0e-12)
  assert_true(w[8].abs() < 1.0e-12)
  // Center should be 1.0
  assert_true((w[4] - 1.0).abs() < 1.0e-12)
}

///|
test "window_blackman" {
  let w = window(Blackman, 7)
  assert_eq(w.length(), 7)
  // Ends should be near 0
  assert_true(w[0].abs() < 0.01)
  assert_true(w[6].abs() < 0.01)
  // Center should be near 1.0
  assert_true(w[3] > 0.99)
}

///|
test "window_kaiser" {
  let w = window(Kaiser(5.0), 16)
  assert_eq(w.length(), 16)
  // Symmetric
  for i = 0; i < 8; i = i + 1 {
    assert_true((w[i] - w[15 - i]).abs() < 1.0e-10)
  }
  // Center should be close to 1.0 (Kaiser is normalized, but center of even-length is between indices)
  assert_true(w[7] > 0.97)
}

///|
test "window_bartlett" {
  let w = window(Bartlett, 9)
  assert_eq(w.length(), 9)
  // Triangular shape
  assert_true(w[0].abs() < 1.0e-12)
  assert_true((w[4] - 1.0).abs() < 1.0e-12)
  assert_true(w[8].abs() < 1.0e-12)
}

///|
test "window_lanczos" {
  let w = window(Lanczos, 11)
  assert_eq(w.length(), 11)
  // Center should be 1.0
  assert_true((w[5] - 1.0).abs() < 1.0e-10)
  // Ends should be near 0
  assert_true(w[0].abs() < 0.1)
  assert_true(w[10].abs() < 0.1)
}

///|
test "window_flattop" {
  let w = window(Flattop, 9)
  assert_eq(w.length(), 9)
  // Symmetric
  for i = 0; i < 4; i = i + 1 {
    assert_true((w[i] - w[8 - i]).abs() < 1.0e-12)
  }
}

///|
test "window_edge_cases" {
  assert_eq(window(Hamming, 0).length(), 0)
  let w1 = window(Hamming, 1)
  assert_eq(w1.length(), 1)
  assert_true(w1[0] == 1.0)
}

///|
test "fir_lowpass_design" {
  let f = fir_design_lowpass(0.25, 21, Hamming)
  assert_eq(f.length, 21)
  assert_eq(f.coeffs.length(), 21)
  // Should be symmetric (linear phase)
  for i = 0; i < 10; i = i + 1 {
    assert_true((f.coeffs[i] - f.coeffs[20 - i]).abs() < 1.0e-10)
  }
  // Sum of coefficients ≈ 1 (DC gain)
  let mut sum = 0.0
  for i = 0; i < 21; i = i + 1 {
    sum = sum + f.coeffs[i]
  }
  assert_true((sum - 1.0).abs() < 0.01)
}

///|
test "fir_highpass_design" {
  let f = fir_design_highpass(0.25, 21, Hamming)
  assert_eq(f.length, 21)
  // Symmetric
  for i = 0; i < 10; i = i + 1 {
    assert_true((f.coeffs[i] - f.coeffs[20 - i]).abs() < 1.0e-10)
  }
  // Sum of coefficients ≈ 0 (zero DC gain for highpass)
  let mut sum = 0.0
  for i = 0; i < 21; i = i + 1 {
    sum = sum + f.coeffs[i]
  }
  assert_true(sum.abs() < 0.01)
}

///|
test "fir_bandpass_design" {
  let f = fir_design_bandpass(0.2, 0.4, 31, Hamming)
  assert_eq(f.length, 31)
  // Symmetric
  for i = 0; i < 15; i = i + 1 {
    assert_true((f.coeffs[i] - f.coeffs[30 - i]).abs() < 1.0e-10)
  }
  // DC gain should be near 0
  let mut sum = 0.0
  for i = 0; i < 31; i = i + 1 {
    sum = sum + f.coeffs[i]
  }
  assert_true(sum.abs() < 0.01)
}

///|
test "fir_bandstop_design" {
  let f = fir_design_bandstop(0.2, 0.4, 31, Hamming)
  assert_eq(f.length, 31)
  // Symmetric
  for i = 0; i < 15; i = i + 1 {
    assert_true((f.coeffs[i] - f.coeffs[30 - i]).abs() < 1.0e-10)
  }
  // DC gain should be near 1
  let mut sum = 0.0
  for i = 0; i < 31; i = i + 1 {
    sum = sum + f.coeffs[i]
  }
  assert_true((sum - 1.0).abs() < 0.01)
}

///|
test "fir_filter_passes_dc" {
  let f = fir_design_lowpass(0.3, 15, Hamming)
  // DC signal should pass through with unity gain
  let dc : Array[Double] = [
    1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0,
    1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0,
  ]
  let out = fir_filter(f, dc)
  // After transient, output should be ~1.0
  assert_true((out[29] - 1.0).abs() < 0.01)
}

///|
test "fir_filter_rejects_high_freq" {
  let f = fir_design_lowpass(0.2, 31, Blackman)
  // High frequency signal (alternating ±1) should be attenuated
  let hf : Array[Double] = []
  for i = 0; i < 64; i = i + 1 {
    hf.push(if i % 2 == 0 { 1.0 } else { -1.0 })
  }
  let out = fir_filter(f, hf)
  // Last sample should be near 0 (high freq rejected)
  assert_true(out[63].abs() < 0.1)
}

///|
test "fir_filter_fft_matches_direct" {
  let f = fir_design_lowpass(0.3, 15, Hamming)
  let signal : Array[Double] = []
  for i = 0; i < 128; i = i + 1 {
    signal.push(@math.sin(3.14159 * 0.1 * i.to_double()))
  }
  let direct = fir_filter(f, signal)
  let fft_out = fir_filter_fft(f, signal)
  // Results should match within numerical precision
  for i = 0; i < 128; i = i + 1 {
    assert_true((direct[i] - fft_out[i]).abs() < 1.0e-3)
  }
}

///|
test "fir_magnitude_response" {
  let f = fir_design_lowpass(0.3, 31, Hamming)
  // DC gain should be ~1
  let dc_resp = fir_magnitude_response(f, 0.0)
  assert_true((dc_resp - 1.0).abs() < 0.01)
  // At cutoff, response should be around 0.5 (−6 dB), but windowing shifts it
  let cutoff_resp = fir_magnitude_response(f, 0.3)
  assert_true(cutoff_resp < 0.85)
  assert_true(cutoff_resp > 0.1)
  // Well above cutoff, response should be low
  let high_resp = fir_magnitude_response(f, 0.8)
  assert_true(high_resp < 0.1)
}

///|
test "butterworth_lowpass" {
  let f = butterworth_lowpass(0.3, 4)
  assert_eq(f.order, 4)
  // Should have 2 biquad sections for order 4
  assert_eq(f.sections.length(), 2)
  // DC gain should be 1
  let dc_gain = iir_magnitude_response(f, 0.0)
  assert_true((dc_gain - 1.0).abs() < 0.1)
  // At cutoff (normalized 0.3), gain should be ~1/sqrt(2) ≈ 0.707
  let cutoff_gain = iir_magnitude_response(f, 0.3)
  assert_true(cutoff_gain > 0.4)
  assert_true(cutoff_gain < 0.95)
  // Well above cutoff, gain should be low
  let high_gain = iir_magnitude_response(f, 0.8)
  assert_true(high_gain < 0.15)
}

///|
test "butterworth_lowpass_odd_order" {
  let f = butterworth_lowpass(0.25, 3)
  assert_eq(f.order, 3)
  // 1 first-order + 1 second-order = 2 sections
  assert_eq(f.sections.length(), 2)
  // DC gain should be 1
  let dc_gain = iir_magnitude_response(f, 0.0)
  assert_true((dc_gain - 1.0).abs() < 0.01)
}

///|
test "butterworth_highpass" {
  let f = butterworth_highpass(0.3, 4)
  assert_eq(f.order, 4)
  // DC gain should be near 0
  let dc_gain = iir_magnitude_response(f, 0.0)
  assert_true(dc_gain < 0.1)
  // Nyquist gain should be ~1
  let nyq_gain = iir_magnitude_response(f, 0.999)
  assert_true((nyq_gain - 1.0).abs() < 0.2)
  // At cutoff, gain should be ~0.707
  let cutoff_gain = iir_magnitude_response(f, 0.3)
  assert_true(cutoff_gain > 0.4)
  assert_true(cutoff_gain < 0.95)
}

///|
test "butterworth_bandpass" {
  let f = butterworth_bandpass(0.2, 0.4, 2)
  assert_eq(f.order, 4)
  // DC gain should be near 0
  let dc_gain = iir_magnitude_response(f, 0.0)
  assert_true(dc_gain < 0.1)
  // Center frequency gain should be near 1
  let center_gain = iir_magnitude_response(f, 0.3)
  assert_true(center_gain > 0.2)
  // High frequency gain should be near 0
  let high_gain = iir_magnitude_response(f, 0.9)
  assert_true(high_gain < 0.2)
}

///|
test "iir_filter_constant_signal" {
  let f = butterworth_lowpass(0.3, 2)
  // Constant signal should pass through (DC gain = 1)
  let sig : Array[Double] = [
    1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0,
    1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0,
  ]
  let out = iir_filter(f, sig)
  // After transient, output should be ~1.0
  assert_true((out[31] - 1.0).abs() < 0.01)
}

///|
test "iir_reset" {
  let f = butterworth_lowpass(0.3, 2)
  let sig : Array[Double] = [1.0, 1.0, 1.0, 1.0]
  let _ = iir_filter(f, sig)
  // State should be non-zero
  assert_true(f.sections[0].s1 != 0.0 || f.sections[0].s2 != 0.0)
  // Reset
  iir_reset(f)
  assert_true(f.sections[0].s1 == 0.0)
  assert_true(f.sections[0].s2 == 0.0)
}

///|
test "periodogram_pure_tone" {
  // A pure sinusoid should show a peak at its frequency
  let n = 256
  let signal : Array[Double] = []
  for i = 0; i < n; i = i + 1 {
    signal.push(@math.sin(2.0 * 3.14159265358979 * 0.125 * i.to_double()))
  }
  let psd = periodogram(signal, 256)
  assert_eq(psd.length(), 129)
  // Peak should be at bin 32 (0.125 * 256 = 32)
  let mut max_bin = 0
  let mut max_val = 0.0
  for i = 0; i < 129; i = i + 1 {
    if psd[i] > max_val {
      max_val = psd[i]
      max_bin = i
    }
  }
  assert_true(max_bin == 32 || max_bin == 31 || max_bin == 33)
}

///|
test "periodogram_dc_signal" {
  let signal : Array[Double] = [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
  let psd = periodogram(signal, 8)
  // All power should be at DC
  assert_true(psd[0] > 0.0)
  for i = 1; i < psd.length(); i = i + 1 {
    assert_true(psd[i] < 1.0e-6)
  }
}

///|
test "welch_psd" {
  let n = 256
  let signal : Array[Double] = []
  for i = 0; i < n; i = i + 1 {
    signal.push(@math.sin(2.0 * 3.14159265358979 * 0.25 * i.to_double()))
  }
  let psd = welch_psd(signal, 64, 32, Hann)
  assert_eq(psd.length(), 33)
  // Should have a peak somewhere around bin 16 (0.25 * 64 = 16)
  let mut max_bin = 0
  let mut max_val = 0.0
  for i = 0; i < 33; i = i + 1 {
    if psd[i] > max_val {
      max_val = psd[i]
      max_bin = i
    }
  }
  assert_true(max_bin >= 14 && max_bin <= 18)
}

///|
test "pre_emphasis" {
  let signal : Array[Double] = [1.0, 2.0, 3.0, 4.0]
  let out = pre_emphasis(signal, 0.97)
  assert_true((out[0] - 1.0).abs() < 1.0e-12)
  assert_true((out[1] - (2.0 - 0.97 * 1.0)).abs() < 1.0e-12)
  assert_true((out[2] - (3.0 - 0.97 * 2.0)).abs() < 1.0e-12)
  assert_true((out[3] - (4.0 - 0.97 * 3.0)).abs() < 1.0e-12)
}

///|
test "moving_average" {
  let signal : Array[Double] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]
  let out = moving_average(signal, 3)
  // After warm-up, moving average of 3 should be correct
  assert_true((out[0] - 1.0).abs() < 1.0e-12) // avg(1) = 1
  assert_true((out[1] - 1.5).abs() < 1.0e-12) // avg(1,2) = 1.5
  assert_true((out[2] - 2.0).abs() < 1.0e-12) // avg(1,2,3) = 2
  assert_true((out[3] - 3.0).abs() < 1.0e-12) // avg(2,3,4) = 3
  assert_true((out[7] - 7.0).abs() < 1.0e-12) // avg(6,7,8) = 7
}

///|
test "median_filter" {
  // Test with an impulse
  let signal : Array[Double] = [1.0, 1.0, 1.0, 10.0, 1.0, 1.0, 1.0]
  let out = median_filter(signal, 3)
  // The impulse at index 3 should be removed
  assert_true((out[0] - 1.0).abs() < 1.0e-12)
  assert_true((out[3] - 1.0).abs() < 1.0e-12)
  assert_true((out[6] - 1.0).abs() < 1.0e-12)
}

///|
test "diff" {
  let signal : Array[Double] = [1.0, 3.0, 6.0, 10.0]
  let out = diff(signal)
  assert_eq(out.length(), 3)
  assert_true((out[0] - 2.0).abs() < 1.0e-12)
  assert_true((out[1] - 3.0).abs() < 1.0e-12)
  assert_true((out[2] - 4.0).abs() < 1.0e-12)
}

///|
test "detrend" {
  // Linear signal: y = 2x + 1
  let signal : Array[Double] = [1.0, 3.0, 5.0, 7.0, 9.0]
  let out = detrend(signal)
  // After detrending, all values should be ~0
  for i = 0; i < 5; i = i + 1 {
    assert_true(out[i].abs() < 1.0e-10)
  }
}

///|
test "fir_freq_response_dc" {
  let f = fir_design_lowpass(0.3, 15, Hamming)
  let (re, im) = fir_freq_response(f, 0.0)
  // At DC, response should be real and near 1
  assert_true(im.abs() < 1.0e-10)
  assert_true((re - 1.0).abs() < 0.01)
}

///|
test "butterworth_lowpass_order1" {
  let f = butterworth_lowpass(0.3, 1)
  assert_eq(f.order, 1)
  assert_eq(f.sections.length(), 1)
  let dc = iir_magnitude_response(f, 0.0)
  assert_true((dc - 1.0).abs() < 0.01)
}

///|
test "butterworth_highpass_order1" {
  let f = butterworth_highpass(0.3, 1)
  assert_eq(f.order, 1)
  let dc = iir_magnitude_response(f, 0.0)
  assert_true(dc < 0.01)
  let nyq = iir_magnitude_response(f, 0.999)
  assert_true((nyq - 1.0).abs() < 0.05)
}

///|
test "window_consistency_all_types" {
  // All windows of length 1 should return [1.0]
  assert_true(window(Rectangular, 1)[0] == 1.0)
  assert_true(window(Hamming, 1)[0] == 1.0)
  assert_true(window(Hann, 1)[0] == 1.0)
  assert_true(window(Blackman, 1)[0] == 1.0)
  assert_true(window(Kaiser(6.0), 1)[0] == 1.0)
  assert_true(window(Bartlett, 1)[0] == 1.0)
  assert_true(window(Lanczos, 1)[0] == 1.0)
  assert_true(window(Flattop, 1)[0] == 1.0)
}
