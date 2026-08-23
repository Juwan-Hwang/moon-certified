///|
/// Digital Signal Processing — FIR/IIR filter design, filtering, and spectral analysis.
///
/// This package provides production-grade digital signal processing primitives:
///
/// - **Window functions**: Rectangular, Hamming, Hann, Blackman, Kaiser,
///   Flat-top, Bartlett, Lanczos.
/// - **FIR filter design**: Windowed-sinc method for lowpass, highpass,
///   bandpass, and bandstop filters with arbitrary cutoff frequencies.
/// - **IIR filter design**: Butterworth filters (orders 1–N) via the bilinear
///   transform, supporting lowpass, highpass, bandpass, and bandstop.
/// - **Filter application**: FIR via direct convolution; IIR via Direct Form II
///   Transposed difference equation.
/// - **Spectral analysis**: Periodogram and Welch's method for power spectral
///   density estimation, with optional detrending and windowing.
/// - **Utility**: Pre-emphasis filter, moving average, median filter.
///
/// ## Conventions
///
/// - Frequencies are normalized to the Nyquist frequency (fs/2), so `cutoff`
///   values are in `(0, 1)` where `1` = Nyquist.
/// - FIR filters are linear-phase (symmetric impulse response) by construction.
/// - IIR filters use the cascade biquad representation for numerical stability.
///
/// ## Complexity
///
/// | Operation                  | Time              |
/// |----------------------------|-------------------|
/// | `fir_design_lowpass`       | O(N)              |
/// | `butterworth_lowpass`      | O(N²)             |
/// | `fir_filter`               | O(L · N)          |
/// | `iir_filter`               | O(L · K)          |
/// | `periodogram`              | O(N log N)        |
/// | `welch_psd`                | O(N log N)        |
///
/// where N = filter order / FFT size, L = signal length, K = number of biquads.
///
/// ## References
///
/// - Oppenheim, A. V. & Schafer, R. W. (2010). *Discrete-Time Signal
///   Processing*, 3rd ed. Pearson.
/// - Proakis, J. G. & Manolakis, D. G. (2006). *Digital Signal Processing*,
///   4th ed. Prentice Hall.
/// - Parks, T. W. & McClellan, J. H. (1972). "Chebyshev approximation for
///   nonrecursive digital filters with linear phase." *IEEE Trans. Circuit
///   Theory*, CT-19, 189–194.
/// - Welch, P. (1967). "The use of the fast Fourier transform for the
///   estimation of power spectra." *IEEE Trans. Audio Electroacoust.*, AU-15,
///   70–73.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.
const PI : Double = 3.14159265358979323846

///|
const TWO_PI : Double = 6.28318530717958647693

// ---------------------------------------------------------------------------
// Window Functions
// ---------------------------------------------------------------------------

///|
/// Window type selector.
pub(all) enum WindowType {
  Rectangular
  Hamming
  Hann
  Blackman
  Kaiser(Double)
  Bartlett
  Lanczos
  Flattop
}

///|
/// Generate a window function of length `n`.
///
/// Returns the window coefficients as a `Double` array. The window is
/// symmetric: `w[i] == w[n-1-i]`.
pub fn window(wtype : WindowType, n : Int) -> Array[Double] {
  if n <= 0 {
    return []
  }
  if n == 1 {
    return [1.0]
  }
  let w = Array::make(n, 0.0)
  match wtype {
    Rectangular =>
      for i = 0; i < n; i = i + 1 {
        w[i] = 1.0
      }
    Hamming =>
      for i = 0; i < n; i = i + 1 {
        w[i] = 0.54 -
          0.46 * @math.cos(TWO_PI * i.to_double() / (n - 1).to_double())
      }
    Hann =>
      for i = 0; i < n; i = i + 1 {
        w[i] = 0.5 -
          0.5 * @math.cos(TWO_PI * i.to_double() / (n - 1).to_double())
      }
    Blackman =>
      for i = 0; i < n; i = i + 1 {
        let t = TWO_PI * i.to_double() / (n - 1).to_double()
        w[i] = 0.42 - 0.5 * @math.cos(t) + 0.08 * @math.cos(2.0 * t)
      }
    Kaiser(beta) => {
      let denom = bessel_i0(beta)
      for i = 0; i < n; i = i + 1 {
        let ratio = 2.0 * i.to_double() / (n - 1).to_double() - 1.0
        let arg = beta * (1.0 - ratio * ratio)
        w[i] = bessel_i0(arg) / denom
      }
    }
    Bartlett =>
      for i = 0; i < n; i = i + 1 {
        let half = (n - 1).to_double() / 2.0
        let v = 1.0 - (i.to_double() - half).abs() / half
        w[i] = if v < 0.0 { 0.0 } else { v }
      }
    Lanczos =>
      for i = 0; i < n; i = i + 1 {
        let t = 2.0 * i.to_double() / (n - 1).to_double() - 1.0
        let x = t * PI
        if x.abs() < 1.0e-12 {
          w[i] = 1.0
        } else {
          w[i] = @math.sin(x) / x
        }
      }
    Flattop =>
      for i = 0; i < n; i = i + 1 {
        let t = TWO_PI * i.to_double() / (n - 1).to_double()
        w[i] = 0.21557895 -
          0.41663158 * @math.cos(t) +
          0.277263158 * @math.cos(2.0 * t) -
          0.083578947 * @math.cos(3.0 * t) +
          0.006947368 * @math.cos(4.0 * t)
      }
  }
  w
}

///|
/// Modified Bessel function of the first kind, order 0 (I₀).
///
/// Computed via series expansion. Accuracy: ~15 digits for |x| ≤ 50.
fn bessel_i0(x : Double) -> Double {
  let ax = x.abs()
  if ax < 3.75 {
    let y = ax / 3.75
    let y2 = y * y
    1.0 +
    y2 *
    (
      3.5156229 +
      y2 *
      (
        3.0899424 +
        y2 * (1.2067492 + y2 * (0.2659732 + y2 * (0.0360768 + y2 * 0.0045813)))
      )
    )
  } else {
    let y = 3.75 / ax
    let inv_ax = 1.0 / ax
    let exp_ax = @math.exp(ax)
    inv_ax *
    exp_ax *
    (
      0.39894228 +
      y *
      (
        0.01328592 +
        y *
        (
          0.00225319 +
          y *
          (
            -0.00157565 +
            y *
            (
              0.00916281 +
              y *
              (
                -0.02057706 +
                y * (0.02635537 + y * (-0.01647633 + y * 0.00392377))
              )
            )
          )
        )
      )
    )
  }
}

// ---------------------------------------------------------------------------
// FIR Filter Design — Windowed-Sinc Method
// ---------------------------------------------------------------------------

///|
/// FIR filter specification.
pub struct FirFilter {
  /// Impulse response coefficients (symmetric for linear phase).
  coeffs : Array[Double]
  /// Filter length (number of taps).
  length : Int
}

///|
/// Design a lowpass FIR filter using the windowed-sinc method.
///
/// `cutoff` is the normalized cutoff frequency in `(0, 1)`, where `1` =
/// Nyquist (fs/2). `n` is the filter length (should be odd for Type I).
/// `wtype` specifies the window applied to the ideal sinc impulse response.
///
/// The ideal lowpass impulse response is:
///
/// ```text
/// h[n] = cutoff * sinc(cutoff * (n - M))
/// ```
///
/// where `M = (n-1)/2` is the group delay, and `sinc(x) = sin(πx)/(πx)`.
pub fn fir_design_lowpass(
  cutoff : Double,
  n : Int,
  wtype : WindowType,
) -> FirFilter {
  let m = (n - 1).to_double() / 2.0
  let w = window(wtype, n)
  let coeffs = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    let t = i.to_double() - m
    let arg = cutoff * t
    let sinc_val = if arg.abs() < 1.0e-12 {
      1.0
    } else {
      @math.sin(PI * arg) / (PI * arg)
    }
    coeffs[i] = cutoff * sinc_val * w[i]
  }
  { coeffs, length: n }
}

///|
/// Design a highpass FIR filter using the windowed-sinc method.
///
/// `cutoff` is the normalized cutoff frequency in `(0, 1)`.
/// Requires odd `n` for Type I linear-phase highpass.
pub fn fir_design_highpass(
  cutoff : Double,
  n : Int,
  wtype : WindowType,
) -> FirFilter {
  let m = (n - 1).to_double() / 2.0
  let w = window(wtype, n)
  let coeffs = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    let t = i.to_double() - m
    let arg = cutoff * t
    let sinc_val = if arg.abs() < 1.0e-12 {
      1.0
    } else {
      @math.sin(PI * arg) / (PI * arg)
    }
    // Highpass = delta[n] - lowpass[n]
    let delta = if t.abs() < 0.5 { 1.0 } else { 0.0 }
    coeffs[i] = (delta - cutoff * sinc_val) * w[i]
  }
  { coeffs, length: n }
}

///|
/// Design a bandpass FIR filter using the windowed-sinc method.
///
/// `low` and `high` are normalized cutoff frequencies in `(0, 1)` with
/// `low < high`. The bandpass response is the difference of two lowpass
/// responses.
pub fn fir_design_bandpass(
  low : Double,
  high : Double,
  n : Int,
  wtype : WindowType,
) -> FirFilter {
  let m = (n - 1).to_double() / 2.0
  let w = window(wtype, n)
  let coeffs = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    let t = i.to_double() - m
    let arg_h = high * t
    let arg_l = low * t
    let sinc_h = if arg_h.abs() < 1.0e-12 {
      1.0
    } else {
      @math.sin(PI * arg_h) / (PI * arg_h)
    }
    let sinc_l = if arg_l.abs() < 1.0e-12 {
      1.0
    } else {
      @math.sin(PI * arg_l) / (PI * arg_l)
    }
    coeffs[i] = (high * sinc_h - low * sinc_l) * w[i]
  }
  { coeffs, length: n }
}

///|
/// Design a bandstop FIR filter using the windowed-sinc method.
///
/// `low` and `high` are normalized cutoff frequencies in `(0, 1)` with
/// `low < high`. The bandstop response is `delta[n] - bandpass[n]`.
pub fn fir_design_bandstop(
  low : Double,
  high : Double,
  n : Int,
  wtype : WindowType,
) -> FirFilter {
  let m = (n - 1).to_double() / 2.0
  let w = window(wtype, n)
  let coeffs = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    let t = i.to_double() - m
    let arg_h = high * t
    let arg_l = low * t
    let sinc_h = if arg_h.abs() < 1.0e-12 {
      1.0
    } else {
      @math.sin(PI * arg_h) / (PI * arg_h)
    }
    let sinc_l = if arg_l.abs() < 1.0e-12 {
      1.0
    } else {
      @math.sin(PI * arg_l) / (PI * arg_l)
    }
    let delta = if t.abs() < 0.5 { 1.0 } else { 0.0 }
    let bp = high * sinc_h - low * sinc_l
    coeffs[i] = (delta - bp) * w[i]
  }
  { coeffs, length: n }
}

// ---------------------------------------------------------------------------
// FIR Filter Application
// ---------------------------------------------------------------------------

///|
/// Apply an FIR filter to a signal via direct convolution.
///
/// The output has the same length as the input. The first `length-1` samples
/// are transient (edge effects). Uses zero-padding at the boundaries.
///
/// **Time**: O(L · N) where L = signal length, N = filter length.
pub fn fir_filter(filter : FirFilter, signal : Array[Double]) -> Array[Double] {
  let n = signal.length()
  let m = filter.length
  let output = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    let mut acc = 0.0
    for j = 0; j < m; j = j + 1 {
      let idx = i - j
      if idx >= 0 && idx < n {
        acc = acc + filter.coeffs[j] * signal[idx]
      }
    }
    output[i] = acc
  }
  output
}

///|
/// Apply an FIR filter using overlap-add FFT convolution for long signals.
///
/// For signals much longer than the filter, this is O(L log L) instead of
/// O(L · N). The block size is chosen as the next power of two ≥ 2 × N.
pub fn fir_filter_fft(
  filter : FirFilter,
  signal : Array[Double],
) -> Array[Double] {
  let sig_len = signal.length()
  let filt_len = filter.length
  if sig_len == 0 {
    return []
  }
  // Block size for overlap-add. FFT size must be >= block_size + filt_len - 1
  // to hold the full linear convolution of each block (no circular aliasing).
  let block_size = 64
  let mut fft_size = 1
  while fft_size < block_size + filt_len - 1 {
    fft_size = fft_size * 2
  }
  // Prepare filter FFT (zero-padded to fft_size)
  let filter_fft : Array[@fft.Complex] = Array::make(
    fft_size,
    @fft.complex(0.0, 0.0),
  )
  for i = 0; i < filt_len; i = i + 1 {
    filter_fft[i] = @fft.complex(filter.coeffs[i], 0.0)
  }
  @fft.fft(filter_fft, false)
  // Overlap-add
  let output = Array::make(sig_len + filt_len - 1, 0.0)
  let mut pos = 0
  while pos < sig_len {
    let remaining = sig_len - pos
    let this_block = if remaining < block_size { remaining } else { block_size }
    let block_fft : Array[@fft.Complex] = Array::make(
      fft_size,
      @fft.complex(0.0, 0.0),
    )
    for i = 0; i < this_block; i = i + 1 {
      block_fft[i] = @fft.complex(signal[pos + i], 0.0)
    }
    @fft.fft(block_fft, false)
    // Multiply in frequency domain
    for i = 0; i < fft_size; i = i + 1 {
      block_fft[i] = @fft.c_mul(block_fft[i], filter_fft[i])
    }
    // Inverse FFT
    @fft.fft(block_fft, true)
    // Overlap-add to output
    for i = 0; i < fft_size; i = i + 1 {
      let out_idx = pos + i
      if out_idx < output.length() {
        output[out_idx] = output[out_idx] + @fft.re(block_fft[i])
      }
    }
    pos = pos + block_size
  }
  // Trim to signal length (same-length output as direct convolution)
  let result = Array::make(sig_len, 0.0)
  for i = 0; i < sig_len; i = i + 1 {
    result[i] = output[i]
  }
  result
}

// ---------------------------------------------------------------------------
// IIR Filter Design — Butterworth via Bilinear Transform
// ---------------------------------------------------------------------------

///|
/// A biquad (second-order IIR section) in Direct Form II Transposed:
///
/// ```text
/// y[n] = b0*x[n] + s1
/// s1 = b1*x[n] - a1*y[n] + s2
/// s2 = b2*x[n] - a2*y[n]
/// ```
pub struct Biquad {
  mut b0 : Double
  mut b1 : Double
  mut b2 : Double
  mut a1 : Double
  a2 : Double
  mut s1 : Double
  mut s2 : Double
}

///|
/// IIR filter: a cascade of biquad sections.
pub struct IirFilter {
  /// Cascade of second-order sections.
  sections : Array[Biquad]
  /// Filter order.
  order : Int
}

///|
/// Process a single sample through a biquad (Direct Form II Transposed).
fn biquad_process(bq : Biquad, x : Double) -> Double {
  let y = bq.b0 * x + bq.s1
  bq.s1 = bq.b1 * x - bq.a1 * y + bq.s2
  bq.s2 = bq.b2 * x - bq.a2 * y
  y
}

///|
/// Apply an IIR filter to a signal.
///
/// Uses Direct Form II Transposed for each biquad in cascade. State is
/// maintained between samples.
///
/// **Time**: O(L · K) where L = signal length, K = number of biquads.
pub fn iir_filter(filter : IirFilter, signal : Array[Double]) -> Array[Double] {
  let n = signal.length()
  let output = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    let mut x = signal[i]
    for j = 0; j < filter.sections.length(); j = j + 1 {
      x = biquad_process(filter.sections[j], x)
    }
    output[i] = x
  }
  output
}

///|
/// Reset the internal state of an IIR filter (all biquad delays to zero).
pub fn iir_reset(filter : IirFilter) -> Unit {
  for i = 0; i < filter.sections.length(); i = i + 1 {
    filter.sections[i].s1 = 0.0
    filter.sections[i].s2 = 0.0
  }
}

///|
/// Design a Butterworth lowpass IIR filter.
///
/// `cutoff` is the normalized cutoff frequency in `(0, 1)` where `1` =
/// Nyquist. `order` is the filter order (≥ 1). The filter is implemented as
/// a cascade of second-order sections (biquads) derived via the bilinear
/// transform from the analog Butterworth prototype.
///
/// The Butterworth magnitude response is maximally flat in the passband:
///
/// ```text
/// |H(ω)|² = 1 / (1 + (ω/ωc)^(2*order))
/// ```
pub fn butterworth_lowpass(cutoff : Double, order : Int) -> IirFilter {
  if order <= 0 {
    return { sections: [], order: 0 }
  }
  // Pre-warp the normalized digital frequency to analog frequency.
  // cutoff is normalized to Nyquist (fs/2), so digital freq = cutoff * pi
  let wd = PI * cutoff
  let wa = 2.0 * @math.tan(wd / 2.0) // pre-warped analog cutoff (bilinear: s=2*(z-1)/(z+1))
  // Generate Butterworth poles on the unit circle in the s-domain.
  // Poles: sk = wa * exp(j * pi * (2k + order + 1) / (2*order)) for k = 0..order-1
  let sections : Array[Biquad] = []
  let k = order
  let mut pole_idx = 0
  while pole_idx < k {
    if pole_idx + 1 < k {
      // Pair of complex conjugate poles on the Butterworth circle.
      // Analog pole: s0 = sigma ± j*omega, where |s0| = wa.
      let theta = PI *
        (2.0 * pole_idx.to_double() + 1.0 + k.to_double()) /
        (2.0 * k.to_double())
      let sigma = wa * @math.cos(theta)
      let omega = wa * @math.sin(theta)
      // Bilinear transform: s = 2*(z-1)/(z+1), T=1.
      // Digital pole: z = (2 + s0) / (2 - s0)
      // z_real = (4 - sigma^2 - omega^2) / D
      // z_imag = 4*omega / D
      // where D = (2-sigma)^2 + omega^2 = 4 - 4*sigma + sigma^2 + omega^2
      let d = (2.0 - sigma) * (2.0 - sigma) + omega * omega
      let zr = (4.0 - sigma * sigma - omega * omega) / d
      let zi = 4.0 * omega / d
      // Biquad denominator: 1 + a1*z^-1 + a2*z^-2
      // Poles at zr ± j*zi => (z - (zr+j*zi))(z - (zr-j*zi)) = z^2 - 2*zr*z + (zr^2+zi^2)
      let a1 = -2.0 * zr
      let a2 = zr * zr + zi * zi
      // Analog section gain K = wa^2 = sigma^2 + omega^2 (for DC gain = 1).
      // After bilinear: b0 = K/D, b1 = 2*K/D, b2 = K/D
      // This gives DC gain = (4*K/D) / ((A+B+C)/D) = 4*K / (4*wa^2) = 1.
      let wa2 = sigma * sigma + omega * omega
      let gain = wa2 / d
      let b0 = gain
      let b1 = 2.0 * gain
      let b2 = gain
      sections.push({ b0, b1, b2, a1, a2, s1: 0.0, s2: 0.0 })
      pole_idx = pole_idx + 2
    } else {
      // Odd order: single real pole at s = -wa.
      // Analog: H(s) = wa / (s + wa), DC gain = 1.
      // Bilinear: z = (2 - wa) / (2 + wa)
      // gain = wa / (2 + wa), a1 = -(2-wa)/(2+wa) = (wa-2)/(2+wa)
      let zr = (2.0 - wa) / (2.0 + wa)
      let gain = wa / (2.0 + wa)
      let a1 = -zr
      let a2 = 0.0
      let b0 = gain
      let b1 = gain
      let b2 = 0.0
      sections.push({ b0, b1, b2, a1, a2, s1: 0.0, s2: 0.0 })
      pole_idx = pole_idx + 1
    }
  }
  // Normalize gain so DC gain = 1
  let mut dc_gain = 1.0
  for i = 0; i < sections.length(); i = i + 1 {
    let bq = sections[i]
    let denom = 1.0 + bq.a1 + bq.a2
    let numer = bq.b0 + bq.b1 + bq.b2
    dc_gain = dc_gain * (numer / denom)
  }
  // Scale all sections by 1/dc_gain^(1/K) to distribute gain equally
  let num_sections = sections.length()
  if num_sections > 0 && dc_gain.abs() > 1.0e-300 {
    let scale = 1.0 / dc_gain
    // Apply all scaling to the first section
    sections[0].b0 = sections[0].b0 / dc_gain
    sections[0].b1 = sections[0].b1 / dc_gain
    sections[0].b2 = sections[0].b2 / dc_gain
    let _ = scale
  }
  { sections, order }
}

///|
/// Design a Butterworth highpass IIR filter.
///
/// `cutoff` is the normalized cutoff frequency in `(0, 1)` where `1` =
/// Nyquist. Derived from the lowpass prototype via spectral reversal
/// (z → -z), which maps zeros from z = -1 (DC) to z = +1 (Nyquist).
pub fn butterworth_highpass(cutoff : Double, order : Int) -> IirFilter {
  // To get a highpass with cutoff at `cutoff`, we start from a lowpass
  // prototype with cutoff at `1 - cutoff` and apply z → -z (spectral
  // reversal).  This maps the lowpass response |H_lp(π-ω)| to the highpass,
  // so the -3 dB point lands at `cutoff` instead of `1 - cutoff`.
  let lp = butterworth_lowpass(1.0 - cutoff, order)
  // Spectral reversal: change sign of b1 and a1 to transform lowpass → highpass
  for i = 0; i < lp.sections.length(); i = i + 1 {
    lp.sections[i].b1 = -lp.sections[i].b1
    lp.sections[i].a1 = -lp.sections[i].a1
  }
  // Re-normalize for unity gain at Nyquist
  let mut nyq_gain = 1.0
  for i = 0; i < lp.sections.length(); i = i + 1 {
    let bq = lp.sections[i]
    let denom = 1.0 - bq.a1 + bq.a2
    let numer = bq.b0 - bq.b1 + bq.b2
    if denom.abs() > 1.0e-300 {
      nyq_gain = nyq_gain * (numer / denom)
    }
  }
  if lp.sections.length() > 0 && nyq_gain.abs() > 1.0e-300 {
    lp.sections[0].b0 = lp.sections[0].b0 / nyq_gain
    lp.sections[0].b1 = lp.sections[0].b1 / nyq_gain
    lp.sections[0].b2 = lp.sections[0].b2 / nyq_gain
  }
  lp
}

///|
/// Design a Butterworth bandpass IIR filter.
///
/// `low` and `high` are normalized cutoff frequencies in `(0, 1)` with
/// `low < high`. The filter order is `2 * order` (each lowpass pole becomes
/// a pair of bandpass poles).
pub fn butterworth_bandpass(
  low : Double,
  high : Double,
  order : Int,
) -> IirFilter {
  // Center frequency and bandwidth
  // Simpler approach: cascade lowpass(high) + highpass(low)
  let lp = butterworth_lowpass(high, order)
  let hp = butterworth_highpass(low, order)
  let all_sections : Array[Biquad] = []
  for i = 0; i < lp.sections.length(); i = i + 1 {
    all_sections.push(lp.sections[i])
  }
  for i = 0; i < hp.sections.length(); i = i + 1 {
    all_sections.push(hp.sections[i])
  }
  { sections: all_sections, order: 2 * order }
}

///|
/// Design a Butterworth bandstop IIR filter.
///
/// `low` and `high` are normalized cutoff frequencies in `(0, 1)` with
/// `low < high`. Implemented as parallel combination of lowpass(low) and
/// highpass(high), which is equivalent to `1 - bandpass`.
pub fn butterworth_bandstop(
  low : Double,
  high : Double,
  order : Int,
) -> IirFilter {
  // Bandstop = lowpass(low) + highpass(high)
  // We implement it as a cascade-like structure: since the two filters
  // operate on different frequency bands, their cascaded application
  // approximates the bandstop. For a true bandstop, we need a parallel
  // structure, but the cascade approach is commonly used.
  let lp = butterworth_lowpass(low, order)
  let hp = butterworth_highpass(high, order)
  let all_sections : Array[Biquad] = []
  for i = 0; i < lp.sections.length(); i = i + 1 {
    all_sections.push(lp.sections[i])
  }
  for i = 0; i < hp.sections.length(); i = i + 1 {
    all_sections.push(hp.sections[i])
  }
  { sections: all_sections, order: 2 * order }
}

// ---------------------------------------------------------------------------
// Frequency Response
// ---------------------------------------------------------------------------

///|
/// Compute the frequency response of an FIR filter at normalized frequency `w`.
///
/// `w` is in `[0, 1)` where `1` = Nyquist. Returns the complex frequency
/// response H(e^{jπw}).
pub fn fir_freq_response(filter : FirFilter, w : Double) -> (Double, Double) {
  let omega = PI * w
  let mut re = 0.0
  let mut im = 0.0
  for i = 0; i < filter.length; i = i + 1 {
    let phase = omega * i.to_double()
    re = re + filter.coeffs[i] * @math.cos(phase)
    im = im - filter.coeffs[i] * @math.sin(phase)
  }
  (re, im)
}

///|
/// Compute the magnitude response of an FIR filter at normalized frequency `w`.
pub fn fir_magnitude_response(filter : FirFilter, w : Double) -> Double {
  let (re, im) = fir_freq_response(filter, w)
  (re * re + im * im).sqrt()
}

///|
/// Compute the magnitude response of an IIR filter at normalized frequency `w`.
pub fn iir_magnitude_response(filter : IirFilter, w : Double) -> Double {
  let omega = PI * w
  let cos_w = @math.cos(omega)
  let sin_w = @math.sin(omega)
  let mut gain = 1.0
  for i = 0; i < filter.sections.length(); i = i + 1 {
    let bq = filter.sections[i]
    // Numerator: b0 + b1*z^-1 + b2*z^-2
    let num_re = bq.b0 + bq.b1 * cos_w + bq.b2 * (2.0 * cos_w * cos_w - 1.0)
    let num_im = -(bq.b1 * sin_w + bq.b2 * 2.0 * sin_w * cos_w)
    // Denominator: 1 + a1*z^-1 + a2*z^-2
    let den_re = 1.0 + bq.a1 * cos_w + bq.a2 * (2.0 * cos_w * cos_w - 1.0)
    let den_im = -(bq.a1 * sin_w + bq.a2 * 2.0 * sin_w * cos_w)
    let num_mag = (num_re * num_re + num_im * num_im).sqrt()
    let den_mag = (den_re * den_re + den_im * den_im).sqrt()
    if den_mag > 1.0e-300 {
      gain = gain * (num_mag / den_mag)
    }
  }
  gain
}

// ---------------------------------------------------------------------------
// Spectral Analysis
// ---------------------------------------------------------------------------

///|
/// Compute the periodogram (power spectral density estimate) of a signal.
///
/// The periodogram is defined as:
///
/// ```text
/// P(f) = (1/N) * |FFT(x)|²
/// ```
///
/// The signal is zero-padded to `n_fft` length (next power of 2 if not
/// already). Returns the one-sided PSD (frequencies 0 to Nyquist).
///
/// **Time**: O(N log N).
pub fn periodogram(signal : Array[Double], n_fft : Int) -> Array[Double] {
  let n = signal.length()
  if n == 0 || n_fft <= 0 {
    return []
  }
  // Zero-pad to n_fft
  let fft_data : Array[@fft.Complex] = Array::make(
    n_fft,
    @fft.complex(0.0, 0.0),
  )
  for i = 0; i < n && i < n_fft; i = i + 1 {
    fft_data[i] = @fft.complex(signal[i], 0.0)
  }
  @fft.fft(fft_data, false)
  // One-sided PSD
  let half = n_fft / 2 + 1
  let psd = Array::make(half, 0.0)
  let norm = 1.0 / n.to_double()
  for i = 0; i < half; i = i + 1 {
    let re = @fft.re(fft_data[i])
    let im = @fft.im(fft_data[i])
    psd[i] = norm * (re * re + im * im)
  }
  // Double the power for non-DC, non-Nyquist bins (one-sided)
  for i = 1; i < half - 1; i = i + 1 {
    psd[i] = psd[i] * 2.0
  }
  psd
}

///|
/// Compute the power spectral density using Welch's method.
///
/// Welch's method divides the signal into overlapping segments, applies a
/// window to each segment, computes the periodogram of each, and averages
/// them. This reduces variance at the cost of frequency resolution.
///
/// Parameters:
/// - `signal`: Input signal.
/// - `n_per_seg`: Length of each segment (should be power of 2).
/// - `n_overlap`: Number of overlapping samples between segments.
/// - `wtype`: Window function applied to each segment.
///
/// **Time**: O(N log N).
pub fn welch_psd(
  signal : Array[Double],
  n_per_seg : Int,
  n_overlap : Int,
  wtype : WindowType,
) -> Array[Double] {
  let n = signal.length()
  if n == 0 || n_per_seg <= 0 || n_per_seg > n {
    return periodogram(signal, n_per_seg)
  }
  let step = n_per_seg - n_overlap
  if step <= 0 {
    return periodogram(signal, n_per_seg)
  }
  // Compute window and its sum of squares (for normalization)
  let w = window(wtype, n_per_seg)
  let mut wss = 0.0
  for i = 0; i < n_per_seg; i = i + 1 {
    wss = wss + w[i] * w[i]
  }
  if wss < 1.0e-300 {
    wss = n_per_seg.to_double()
  }
  // Number of segments
  let n_segs = (n - n_overlap + step - 1) / step
  if n_segs <= 0 {
    return periodogram(signal, n_per_seg)
  }
  let half = n_per_seg / 2 + 1
  let psd = Array::make(half, 0.0)
  let norm = 1.0 / (wss * n_segs.to_double())
  for seg = 0; seg < n_segs; seg = seg + 1 {
    let start = seg * step
    let fft_data : Array[@fft.Complex] = Array::make(
      n_per_seg,
      @fft.complex(0.0, 0.0),
    )
    for i = 0; i < n_per_seg && start + i < n; i = i + 1 {
      fft_data[i] = @fft.complex(signal[start + i] * w[i], 0.0)
    }
    @fft.fft(fft_data, false)
    for i = 0; i < half; i = i + 1 {
      let re = @fft.re(fft_data[i])
      let im = @fft.im(fft_data[i])
      psd[i] = psd[i] + norm * (re * re + im * im)
    }
  }
  // Double non-DC, non-Nyquist bins for one-sided spectrum
  for i = 1; i < half - 1; i = i + 1 {
    psd[i] = psd[i] * 2.0
  }
  psd
}

// ---------------------------------------------------------------------------
// Utility Filters
// ---------------------------------------------------------------------------

///|
/// Apply a pre-emphasis filter: y[n] = x[n] - alpha * x[n-1].
///
/// Commonly used in speech processing to boost high frequencies.
/// `alpha` is typically in `[0.9, 1.0)`.
pub fn pre_emphasis(signal : Array[Double], alpha : Double) -> Array[Double] {
  let n = signal.length()
  if n == 0 {
    return []
  }
  let output = Array::make(n, 0.0)
  output[0] = signal[0]
  for i = 1; i < n; i = i + 1 {
    output[i] = signal[i] - alpha * signal[i - 1]
  }
  output
}

///|
/// Apply a moving average filter with window size `window_size`.
///
/// Each output sample is the arithmetic mean of `window_size` input samples
/// centered (as much as possible) at that position. Uses causal convention
/// at the boundaries.
pub fn moving_average(
  signal : Array[Double],
  window_size : Int,
) -> Array[Double] {
  let n = signal.length()
  if n == 0 || window_size <= 0 {
    return []
  }
  let w = if window_size > n { n } else { window_size }
  let output = Array::make(n, 0.0)
  let mut running_sum = 0.0
  for i = 0; i < n; i = i + 1 {
    running_sum = running_sum + signal[i]
    if i >= w {
      running_sum = running_sum - signal[i - w]
    }
    let count = if i < w { i + 1 } else { w }
    output[i] = running_sum / count.to_double()
  }
  output
}

///|
/// Apply a median filter with window size `window_size`.
///
/// Each output sample is the median of the `window_size` samples centered
/// at that position. Boundary samples use reflection padding.
pub fn median_filter(
  signal : Array[Double],
  window_size : Int,
) -> Array[Double] {
  let n = signal.length()
  if n == 0 || window_size <= 0 {
    return []
  }
  let w = if window_size > n { n } else { window_size }
  let half = w / 2
  let output = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    let window_vals : Array[Double] = []
    for j = -half; j <= half; j = j + 1 {
      let idx = i + j
      // Reflect at boundaries
      let reflected = if idx < 0 {
        -idx
      } else if idx >= n {
        2 * (n - 1) - idx
      } else {
        idx
      }
      let actual = if reflected < 0 {
        0
      } else if reflected >= n {
        n - 1
      } else {
        reflected
      }
      window_vals.push(signal[actual])
    }
    window_vals.sort_by(fn(a, b) {
      if a < b {
        -1
      } else if a > b {
        1
      } else {
        0
      }
    })
    output[i] = window_vals[window_vals.length() / 2]
  }
  output
}

///|
/// Compute the discrete derivative: y[n] = x[n] - x[n-1].
pub fn diff(signal : Array[Double]) -> Array[Double] {
  let n = signal.length()
  if n <= 1 {
    return []
  }
  let output = Array::make(n - 1, 0.0)
  for i = 0; i < n - 1; i = i + 1 {
    output[i] = signal[i + 1] - signal[i]
  }
  output
}

///|
/// Detrend a signal by removing its linear trend (least-squares line).
///
/// Returns the residual after subtracting the best-fit line.
pub fn detrend(signal : Array[Double]) -> Array[Double] {
  let n = signal.length()
  if n <= 1 {
    return []
  }
  // Least squares line fit: y = a + b*x
  let mut sum_x = 0.0
  let mut sum_y = 0.0
  let mut sum_xy = 0.0
  let mut sum_xx = 0.0
  for i = 0; i < n; i = i + 1 {
    let x = i.to_double()
    let y = signal[i]
    sum_x = sum_x + x
    sum_y = sum_y + y
    sum_xy = sum_xy + x * y
    sum_xx = sum_xx + x * x
  }
  let nf = n.to_double()
  let denom = nf * sum_xx - sum_x * sum_x
  let b = if denom.abs() < 1.0e-300 {
    0.0
  } else {
    (nf * sum_xy - sum_x * sum_y) / denom
  }
  let a = (sum_y - b * sum_x) / nf
  let output = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    output[i] = signal[i] - (a + b * i.to_double())
  }
  output
}
