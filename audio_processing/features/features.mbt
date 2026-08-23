/// Audio feature extraction — resampling, framing, mel spectrograms, and
/// MFCC features.
///
/// This package provides production-grade audio front-end primitives:
///
/// - **Resampling**: high-quality linear-interpolation resampler with exact
///   output-length arithmetic (`ceil(n·target/orig)`).
/// - **Framing**: sliding-window segmentation with configurable frame length
///   and hop; incomplete trailing frames are dropped (librosa convention).
/// - **Mel filterbank**: HTK-style triangular filters on the FFT bin grid.
/// - **MFCC pipeline**: pre-emphasis → framing → Hamming window → power
///   spectrum (FFT) → mel filterbank energies → log → DCT-II → cepstral
///   coefficients, plus first-order delta regression.
///
/// ## Conventions
///
/// - Mel scale uses the **HTK formula**:
///   `mel = 2595 · log10(1 + f/700)` and its inverse. This differs from the
///   Slaney (auditory-toolbox) scale used by librosa's default `mel` filter.
/// - Spectra keep `n_fft/2 + 1` bins (DC through Nyquist); power bins are
///   normalized by `n_fft` so Parseval energy identity holds approximately.
/// - Log-mel energies are floored at `1e−10` to avoid `-inf`.
/// - DCT-II uses orthonormal normalization; coefficients are ordered with
///   `c0` first (the log-energy term).
///
/// ## Complexity
///
/// | Operation            | Time                    |
/// |----------------------|-------------------------|
/// | `resample_linear`    | O(M)                    |
/// | `frame_signal`       | O(N)                    |
/// | `power_spectrum`     | O(n_fft log n_fft)      |
/// | `mfcc`               | O(T · F log F + T·M·K)  |
/// | `delta`              | O(F · T · W)            |
///
/// where T = frames, F = frame length, M = mel bands, K = cepstral order,
/// N = signal length, M_out = resampled length.
///
/// ## References
///
/// - Rabiner, L. R. & Schafer, R. W. (1978). *Digital Processing of Speech
///   Signals*. Prentice Hall.
/// - Young, S. et al. (2006). *The HTK Book*, §5.5 (MFCC pipeline, mel scale).
/// - Davis, S. & Mermelstein, P. (1980). "Comparison of parametric
///   representations for monosyllabic word recognition." *IEEE Trans. ASSP*,
///   28(4), 357–366.
/// - Soong, F. K. & Rosenberg, A. E. (1988). "On the use of instantaneous
///   and transitional spectral information in speaker recognition." *IEEE
///   Trans. ASSP*, 36(6), 871–879 (delta regression).
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

///|
/// Convert a frequency in Hz to the HTK mel scale.
pub fn hz_to_mel(hz : Double) -> Double {
  2595.0 * @math.log10(1.0 + hz / 700.0)
}

///|
/// Convert an HTK mel value back to Hz.
pub fn mel_to_hz(mel : Double) -> Double {
  700.0 * (@math.pow(10.0, mel / 2595.0) - 1.0)
}

///|
/// Build a mel filterbank of `n_mels` triangular filters over
/// `[fmin, fmax]` Hz mapped onto `n_fft/2 + 1` FFT bins.
///
/// Filter edges are placed at equally spaced mel points (HTK convention);
/// filter `m` ramps up to its center bin and down again. Returns `None`
/// for invalid parameters (`n_mels < 2`, `n_fft < 16`, `fmin >= fmax`,
/// `fmax > sample_rate/2`, non-positive rate).
pub fn mel_filterbank(
  n_mels : Int,
  n_fft : Int,
  sample_rate : Int,
  fmin : Double,
  fmax : Double,
) -> Array[Array[Double]]? {
  if n_mels < 2 || n_fft < 16 || sample_rate <= 0 || !(fmin < fmax) {
    return None
  }
  if fmax > sample_rate.to_double() / 2.0 {
    return None
  }
  let n_bins = n_fft / 2 + 1
  let nyquist_hz = sample_rate.to_double() / 2.0
  let bin_hz = nyquist_hz / (n_bins - 1).to_double()
  // n_mels + 2 mel-spaced edge frequencies.
  let mel_min = hz_to_mel(fmin)
  let mel_max = hz_to_mel(fmax)
  let points : Array[Double] = Array::make(n_mels + 2, 0.0)
  for i = 0; i < n_mels + 2; i = i + 1 {
    let t = i.to_double() / (n_mels + 1).to_double()
    let hz = mel_to_hz(mel_min + t * (mel_max - mel_min))
    // Edge positions on the bin grid (fractional).
    points[i] = hz / bin_hz
  }
  let bank : Array[Array[Double]] = []
  for m = 0; m < n_mels; m = m + 1 {
    let left = points[m]
    let center = points[m + 1]
    let right = points[m + 2]
    let row = Array::make(n_bins, 0.0)
    for b = 0; b < n_bins; b = b + 1 {
      let x = b.to_double()
      let v = if x >= left && x <= center && center > left {
        (x - left) / (center - left)
      } else if x > center && x <= right && right > center {
        (right - x) / (right - center)
      } else {
        0.0
      }
      row[b] = v
    }
    bank.push(row)
  }
  Some(bank)
}

///|
/// Segment `signal` into overlapping frames.
///
/// Frame `t` starts at sample `t · hop` and spans `frame_len` samples.
/// The number of frames is `max(0, 1 + (n − frame_len) / hop)` (integer
/// division); incomplete trailing frames are dropped. Returns `None` when
/// `frame_len <= 0` or `hop <= 0`.
pub fn frame_signal(
  signal : Array[Double],
  frame_len : Int,
  hop : Int,
) -> Array[Array[Double]]? {
  if frame_len <= 0 || hop <= 0 {
    return None
  }
  let n = signal.length()
  if n < frame_len {
    return Some([])
  }
  let n_frames = 1 + (n - frame_len) / hop
  let frames : Array[Array[Double]] = []
  for t = 0; t < n_frames; t = t + 1 {
    let base = t * hop
    let frame = Array::make(frame_len, 0.0)
    for i = 0; i < frame_len; i = i + 1 {
      frame[i] = signal[base + i]
    }
    frames.push(frame)
  }
  Some(frames)
}

///|
/// Next power of two ≥ `n` (for zero-padded FFT sizes).
fn next_pow2(n : Int) -> Int {
  let mut p = 1
  while p < n {
    p = p * 2
  }
  p
}

///|
/// Windowed power spectrum of one frame: zero-pad to `n_fft` (next power of
/// two ≥ frame length), apply `window_fn`, take the FFT, and return the
/// first `n_fft/2 + 1` power bins normalized by `n_fft`.
pub fn power_spectrum(
  frame : Array[Double],
  n_fft : Int,
  window_type : @filter_design.WindowType,
) -> Array[Double]? {
  if n_fft < frame.length() || n_fft % 2 != 0 {
    return None
  }
  let win = @filter_design.window(window_type, frame.length())
  let buf : Array[@fft.Complex] = Array::make(n_fft, @fft.complex(0.0, 0.0))
  for i = 0; i < frame.length(); i = i + 1 {
    buf[i] = @fft.complex(frame[i] * win[i], 0.0)
  }
  @fft.fft(buf, false)
  let half = n_fft / 2
  let out = Array::make(half + 1, 0.0)
  let norm = n_fft.to_double()
  for k = 0; k <= half; k = k + 1 {
    let re = @fft.re(buf[k])
    let im = @fft.im(buf[k])
    out[k] = (re * re + im * im) / norm
  }
  Some(out)
}

///|
/// MFCC extraction options.
///
/// Defaults mirror common practice (HTK/librosa): 25 ms frames, 10 ms hop,
/// 512-point FFT, 40 mel bands, 13 coefficients, no pre-emphasis unless
/// enabled, Hamming windowing, DC-inclusive band `[0, Nyquist]`.
pub(all) struct MfccConfig {
  /// Samples per second (> 0).
  sample_rate : Int
  /// Frame length in samples (> 0).
  frame_len : Int
  /// Hop length in samples (> 0).
  hop_len : Int
  /// FFT size (power of two ≥ frame_len is enforced internally).
  n_fft : Int
  /// Number of mel filterbank bands (≥ 2).
  n_mels : Int
  /// Number of cepstral coefficients returned per frame (≤ n_mels).
  n_cepstral : Int
  /// Pre-emphasis coefficient in `[0, 1)`; 0 disables.
  pre_emphasis : Double
  /// Lower mel-band edge in Hz (≥ 0).
  fmin : Double
  /// Upper mel-band edge in Hz (≤ Nyquist).
  fmax : Double
}

///|
/// Default configuration: 16 kHz, 400-sample frames, 160 hop, 512-point FFT,
/// 40 mel bands, 13 MFCCs, no pre-emphasis, full band.
pub fn mfcc_default_config() -> MfccConfig {
  {
    sample_rate: 16000,
    frame_len: 400,
    hop_len: 160,
    n_fft: 512,
    n_mels: 40,
    n_cepstral: 13,
    pre_emphasis: 0.0,
    fmin: 0.0,
    fmax: 8000.0,
  }
}

///|
/// Extract MFCC features: one row of `n_cepstral` coefficients per frame.
///
/// Pipeline: optional pre-emphasis (`y[i] = x[i] − α·x[i−1]`) → framing →
/// Hamming window → power spectrum → mel energies → `log(max(e, 1e−10))` →
/// orthonormal DCT-II truncated to `n_cepstral`. Returns `None` for invalid
/// configurations or signals too short to hold one frame.
pub fn mfcc(
  signal : Array[Double],
  config : MfccConfig,
) -> Array[Array[Double]]? {
  if config.sample_rate <= 0 || config.frame_len <= 0 || config.hop_len <= 0 {
    return None
  }
  if config.n_mels < 2 ||
    config.n_cepstral < 1 ||
    config.n_cepstral > config.n_mels {
    return None
  }
  if config.pre_emphasis < 0.0 || config.pre_emphasis >= 1.0 {
    return None
  }
  let nyquist = config.sample_rate.to_double() / 2.0
  if !(config.fmin >= 0.0 && config.fmin < config.fmax && config.fmax <= nyquist) {
    return None
  }
  let n_fft = next_pow2(config.frame_len)
  if n_fft < 16 {
    return None
  }
  // Pre-emphasis
  let prepared = if config.pre_emphasis > 0.0 {
    let y = Array::make(signal.length(), 0.0)
    y[0] = signal[0]
    for i = 1; i < signal.length(); i = i + 1 {
      y[i] = signal[i] - config.pre_emphasis * signal[i - 1]
    }
    y
  } else {
    signal
  }
  let frames = match frame_signal(prepared, config.frame_len, config.hop_len) {
    Some(f) => f
    None => return None
  }
  if frames.length() == 0 {
    return None
  }
  let bank = match
    mel_filterbank(
      config.n_mels,
      n_fft,
      config.sample_rate,
      config.fmin,
      config.fmax,
    ) {
    Some(b) => b
    None => return None
  }
  let out : Array[Array[Double]] = []
  for frame in frames {
    let spec = match power_spectrum(frame, n_fft, @filter_design.Hamming) {
      Some(s) => s
      None => return None
    }
    let mel_energies = Array::make(config.n_mels, 0.0)
    for m = 0; m < config.n_mels; m = m + 1 {
      let row = bank[m]
      let mut e = 0.0
      for b = 0; b < spec.length(); b = b + 1 {
        e = e + row[b] * spec[b]
      }
      mel_energies[m] = @math.ln(if e > 1.0e-10 { e } else { 1.0e-10 })
    }
    // Orthonormal DCT-II over the log-mel vector; keep first n_cepstral.
    let full = @dct.dct2(mel_energies, @dct.OrthoNormal)
    let row_out = Array::make(config.n_cepstral, 0.0)
    for k = 0; k < config.n_cepstral; k = k + 1 {
      row_out[k] = full[k]
    }
    out.push(row_out)
  }
  Some(out)
}

///|
/// First-order delta regression (Soong & Rosenberg 1988):
/// `Δf[t] = Σ_{w=1..W} w·(f[t+w] − f[t−w]) / (2·Σ_{w=1..W} w²)`
/// with frame replication at the boundaries. `window = 2` is standard.
/// Returns `None` for empty input or `window < 1`.
pub fn delta(
  features : Array[Array[Double]],
  window : Int,
) -> Array[Array[Double]]? {
  if window < 1 || features.length() == 0 {
    return None
  }
  let t_n = features.length()
  let dim = features[0].length()
  let mut wsum = 0
  for w = 1; w <= window; w = w + 1 {
    wsum = wsum + w * w
  }
  let denom = (2 * wsum).to_double()
  let out : Array[Array[Double]] = []
  for t = 0; t < t_n; t = t + 1 {
    let row = Array::make(dim, 0.0)
    for d = 0; d < dim; d = d + 1 {
      let mut num = 0.0
      for w = 1; w <= window; w = w + 1 {
        let tp = if t + w >= t_n { t_n - 1 } else { t + w }
        let tm = if t - w < 0 { 0 } else { t - w }
        num = num + w.to_double() * (features[tp][d] - features[tm][d])
      }
      row[d] = num / denom
    }
    out.push(row)
  }
  Some(out)
}

///|
/// Linear-interpolation resampler from `orig_rate` to `target_rate`.
///
/// Output length is `ceil(n · target/orig)`; output position `i` maps back
/// to input position `pos = i · orig/target` and interpolates between the
/// two neighboring input samples (clamped at the right edge). Returns
/// `None` for non-positive rates.
pub fn resample_linear(
  signal : Array[Double],
  orig_rate : Int,
  target_rate : Int,
) -> Array[Double]? {
  if orig_rate <= 0 || target_rate <= 0 {
    return None
  }
  let n = signal.length()
  if n == 0 || orig_rate == target_rate {
    return Some(Array::from_iter(signal.iter()))
  }
  let step = orig_rate.to_double() / target_rate.to_double()
  let out_len = @math.ceil(
    n.to_double() * target_rate.to_double() / orig_rate.to_double(),
  ).to_int()
  let out = Array::make(out_len, 0.0)
  for i = 0; i < out_len; i = i + 1 {
    let pos = i.to_double() * step
    let i0 = pos.to_int()
    let frac = pos - i0.to_double()
    let a = signal[i0]
    let b = if i0 + 1 < n { signal[i0 + 1] } else { signal[n - 1] }
    out[i] = a + (b - a) * frac
  }
  Some(out)
}
