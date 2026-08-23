/// Discrete Wavelet Transform (DWT) — orthogonal wavelets, multi-level
/// decomposition, and wavelet denoising.
///
/// This package provides production-grade wavelet analysis primitives:
///
/// - **Orthogonal wavelet families**: Haar (db1) and Daubechies db2/db4/db6/db8
///   compactly-supported orthonormal wavelets.
/// - **Single-level DWT/IDWT**: periodic (circular) boundary extension,
///   exact perfect reconstruction for all supported wavelets.
/// - **Multi-level decomposition** (`wavedec` / `waverec`): PyWavelets-style
///   coefficient packing `[cA_J, cD_J, …, cD_2, cD_1]` with per-band lengths.
/// - **Denoising**: universal (VisuShrink) threshold
///   `λ = σ·√(2·ln N)` with a robust MAD noise estimate
///   `σ̂ = median(|cD_1|)/0.6745`, plus soft/hard thresholding.
///
/// ## Conventions
///
/// - **Periodic boundary extension**: all index arithmetic is modulo the
///   current signal length `N`; `N` must be divisible by 2 at every level.
/// - **Analysis** (one level, filter `f`, length `L`):
///   `c[k] = Σ_n f[n] · x[(n + 2k) mod N]` for `k ∈ [0, N/2)`.
/// - **Synthesis**: `x[(n + 2k) mod N] += a[k]·h[n] + d[k]·g[n]`, which is the
///   exact inverse for orthonormal filter pairs (see derivation in the test
///   suite: perfect reconstruction and Parseval energy identity are verified
///   numerically for every wavelet).
/// - **QMF convention**: `g[i] = (−1)^i · h[L−1−i]`.
///
/// ## Complexity
///
/// | Operation          | Time         |
/// |--------------------|--------------|
/// | `dwt` / `idwt`     | O(N · L)     |
/// | `wavedec` / `waverec` | O(N · L · (1 + 1/2 + …)) = O(N · L) |
/// | `denoise`          | O(N · L + N log N) (median via sort) |
///
/// where `N` = signal length, `L` = filter length.
///
/// ## References
///
/// - Daubechies, I. (1992). *Ten Lectures on Wavelets*. SIAM.
/// - Mallat, S. G. (1989). "A theory for multiresolution signal
///   decomposition: the wavelet representation." *IEEE Trans. PAMI*, 11(7),
///   674–693.
/// - Donoho, D. L. & Johnstone, I. M. (1994). "Ideal spatial adaptation by
///   wavelet shrinkage." *Biometrika*, 81(3), 425–455.
/// - Percival, D. B. & Walden, A. T. (2000). *Wavelet Methods for Time Series
///   Analysis*. Cambridge University Press.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite
/// (perfect reconstruction, Parseval energy conservation, vanishing moments,
/// and known-value checks).

///|
/// Supported orthogonal wavelet families.
pub(all) enum Wavelet {
  /// Haar wavelet (db1), filter length 2.
  Haar
  /// Daubechies 4-tap wavelet (db2), filter length 4.
  Db2
  /// Daubechies 8-tap wavelet (db4), filter length 8.
  Db4
  /// Daubechies 12-tap wavelet (db6), filter length 12.
  Db6
  /// Daubechies 16-tap wavelet (db8), filter length 16.
  Db8
}

///|
/// Thresholding mode for wavelet denoising.
pub(all) enum ThresholdMode {
  /// Soft thresholding (shrinkage): `sign(c)·max(|c|−λ, 0)`.
  /// Yields smoother estimates; optimal in minimax sense (Donoho 1995).
  Soft
  /// Hard thresholding (keep-or-kill): `c` if `|c| > λ`, else `0`.
  /// Preserves edge amplitudes but can introduce artifacts.
  Hard
}

///|
/// Multi-level wavelet decomposition result.
///
/// `coeffs` packs the bands contiguously in coarse-to-fine order:
/// `[cA_J, cD_J, cD_{J−1}, …, cD_1]`, and `lengths[i]` is the length of the
/// i-th band in that order. `original_len` is the length of the signal that
/// produced this decomposition (`waverec` restores exactly that length).
pub(all) struct Wavedec {
  /// Packed coefficients, coarse-to-fine.
  coeffs : Array[Double]
  /// Length of each band, in the same order as they appear in `coeffs`.
  lengths : Array[Int]
  /// Length of the original signal.
  original_len : Int
}

///|
/// Construct a `Wavedec` value (exposed for tests and interop).
pub fn Wavedec::make(
  coeffs : Array[Double],
  lengths : Array[Int],
  original_len : Int,
) -> Wavedec {
  { coeffs, lengths, original_len }
}

///|
/// Analysis lowpass (scaling) filter `h` for the given wavelet.
///
/// Coefficients are the standard orthonormal Daubechies filters
/// (Daubechies 1992, Tables 6.1 & 6.3), normalized so that `Σ h = √2`.
pub fn analysis_lowpass(w : Wavelet) -> Array[Double] {
  match w {
    Haar => [0.7071067811865476, 0.7071067811865476]
    Db2 =>
      [
        0.4829629131445341, 0.8365163037378079, 0.2241438680420134, -0.1294095225512604,
      ]
    Db4 =>
      [
        0.2303778133088965, 0.7148465705529154, 0.6308807679295904, -0.02798376941698385,
        -0.1870348117190931, 0.03084138183556076, 0.03288301166698945, -0.010597401785069028,
      ]
    Db6 =>
      [
        0.1115407433501095, 0.4946238903983854, 0.7511339080210959, 0.3152503517091972,
        -0.2262646939653914, -0.1297668675672615, 0.09750160558732304, 0.02752286553030573,
        -0.03158203931803115, 0.0005538422011614863, 0.004777257511010451, -0.001077301085308478,
      ]
    Db8 =>
      [
        0.05441584224308161, 0.3128715909144659, 0.6756307362980128, 0.5853546836542159,
        -0.01582910525602389, -0.2840155429624281, 0.0004724845739979725, 0.128747426620186,
        -0.01736930100202211, -0.04408825393106472, 0.01398102791740074, 0.008746094047015981,
        -0.00487035299301066, -0.0003917403733769547, 0.0006754494064505695, -0.000117476784002282,
      ]
  }
}

///|
/// Analysis highpass (wavelet) filter `g`, the quadrature mirror filter of
/// the lowpass: `g[i] = (−1)^i · h[L−1−i]`.
pub fn analysis_highpass(w : Wavelet) -> Array[Double] {
  let h = analysis_lowpass(w)
  let n = h.length()
  Array::makei(n, fn(i) {
    if i % 2 == 0 {
      h[n - 1 - i]
    } else {
      -h[n - 1 - i]
    }
  })
}

///|
/// Maximum decomposition depth for a signal of length `n` with the given
/// wavelet: the largest `J` such that `n` is divisible by `2^J` and every
/// intermediate band retains at least one full filter length. This keeps
/// perfect reconstruction exact — with periodic extension the biorthogonality
/// identities degrade once a band is shorter than the filter.
pub fn max_level(n : Int, w : Wavelet) -> Int {
  if n <= 0 {
    return 0
  }
  let filter_len = analysis_lowpass(w).length()
  let mut level = 0
  let mut len = n
  while len % 2 == 0 && len / 2 >= filter_len {
    len = len / 2
    level = level + 1
  }
  level
}

///|
/// Single-level forward DWT with periodic extension.
///
/// Returns `(approximation, detail)` each of length `N/2`.
/// Requires `N` even and `N ≥ 2` (an odd or too-short input returns `None`).
pub fn dwt(x : Array[Double], w : Wavelet) -> (Array[Double], Array[Double])? {
  let n = x.length()
  if n < 2 || n % 2 != 0 {
    return None
  }
  let h = analysis_lowpass(w)
  let g = analysis_highpass(w)
  let half = n / 2
  let ca = Array::make(half, 0.0)
  let cd = Array::make(half, 0.0)
  for k = 0; k < half; k = k + 1 {
    let base = 2 * k
    let mut sa = 0.0
    let mut sd = 0.0
    for j = 0; j < h.length(); j = j + 1 {
      let idx = (base + j) % n
      sa = sa + h[j] * x[idx]
      sd = sd + g[j] * x[idx]
    }
    ca[k] = sa
    cd[k] = sd
  }
  Some((ca, cd))
}

///|
/// Single-level inverse DWT (exact inverse of `dwt` for orthonormal
/// wavelets, verified numerically to ~1e−12 relative error).
///
/// Requires `ca.length() == cd.length() == N/2` with `N` even.
pub fn idwt(
  ca : Array[Double],
  cd : Array[Double],
  w : Wavelet,
) -> Array[Double]? {
  let half = ca.length()
  if half != cd.length() || half == 0 {
    return None
  }
  let n = half * 2
  let h = analysis_lowpass(w)
  let g = analysis_highpass(w)
  let y = Array::make(n, 0.0)
  for k = 0; k < half; k = k + 1 {
    let base = 2 * k
    let ak = ca[k]
    let dk = cd[k]
    for j = 0; j < h.length(); j = j + 1 {
      let idx = (base + j) % n
      y[idx] = y[idx] + ak * h[j] + dk * g[j]
    }
  }
  Some(y)
}

///|
/// Multi-level wavelet decomposition (Mallat algorithm).
///
/// Decomposes `x` into `level` stages; `level` is clamped to
/// `min(requested, max_level(x.length(), w))`. Returns `None` when `x` is
/// empty or too short for even a single level.
pub fn wavedec(x : Array[Double], w : Wavelet, level : Int) -> Wavedec? {
  let n = x.length()
  if n == 0 || max_level(n, w) == 0 {
    return None
  }
  let depth = if level < 0 {
    0
  } else if level < max_level(n, w) {
    level
  } else {
    max_level(n, w)
  }
  let bands : Array[Array[Double]] = []
  let mut current = x
  for _i = 0; _i < depth; _i = _i + 1 {
    let next = match dwt(current, w) {
      Some(pair) => pair
      None => return None
    }
    bands.push(next.1)
    current = next.0
  }
  let lengths = Array::make(depth + 1, 0)
  lengths[0] = current.length()
  let coeffs = Array::from_iter(current.iter())
  for i = 0; i < depth; i = i + 1 {
    let band = bands[depth - 1 - i]
    lengths[i + 1] = band.length()
    for v in band {
      coeffs.push(v)
    }
  }
  Some({ coeffs, lengths, original_len: n })
}

///|
/// Multi-level inverse wavelet transform; the exact inverse of `wavedec`.
pub fn waverec(d : Wavedec, w : Wavelet) -> Array[Double]? {
  let nbands = d.lengths.length()
  if nbands == 0 || d.original_len != d.coeffs.length() {
    return None
  }
  let approx_len = d.lengths[0]
  let mut current = Array::make(approx_len, 0.0)
  for i = 0; i < approx_len; i = i + 1 {
    current[i] = d.coeffs[i]
  }
  let mut offset = approx_len
  for i = 1; i < nbands; i = i + 1 {
    let dlen = d.lengths[i]
    if dlen == 0 || dlen != current.length() {
      return None
    }
    let detail = Array::make(dlen, 0.0)
    for j = 0; j < dlen; j = j + 1 {
      detail[j] = d.coeffs[offset + j]
    }
    let merged = match idwt(current, detail, w) {
      Some(y) => y
      None => return None
    }
    current = merged
    offset = offset + dlen
  }
  if current.length() != d.original_len {
    return None
  }
  Some(current)
}

///|
/// Soft thresholding: `sign(c)·max(|c|−λ, 0)`.
pub fn soft_threshold(c : Double, lambda : Double) -> Double {
  if lambda <= 0.0 {
    return c
  }
  let mag = c.abs() - lambda
  if mag <= 0.0 {
    0.0
  } else if c > 0.0 {
    mag
  } else {
    -mag
  }
}

///|
/// Hard thresholding: `c` if `|c| > λ`, else `0`.
pub fn hard_threshold(c : Double, lambda : Double) -> Double {
  if c.abs() > lambda {
    c
  } else {
    0.0
  }
}

///|
/// Apply a threshold to every detail band of a decomposition in place
/// (the approximation band `cA_J` is left untouched).
pub fn threshold_details(
  d : Wavedec,
  lambda : Double,
  mode : ThresholdMode,
) -> Unit {
  let offset = d.lengths[0]
  for i = offset; i < d.coeffs.length(); i = i + 1 {
    d.coeffs[i] = match mode {
      Soft => soft_threshold(d.coeffs[i], lambda)
      Hard => hard_threshold(d.coeffs[i], lambda)
    }
  }
}

///|
/// Universal (VisuShrink) threshold for `n` samples with noise scale `sigma`:
/// `λ = σ·√(2·ln n)`.
pub fn universal_threshold(n : Int, sigma : Double) -> Double {
  if n <= 1 || sigma <= 0.0 {
    return 0.0
  }
  sigma * (2.0 * @math.ln(n.to_double())).sqrt()
}

///|
/// Robust noise standard deviation estimate from the finest detail band:
/// `σ̂ = median(|cD_1|) / 0.6745` (Donoho & Johnstone 1994).
///
/// Returns `None` for an empty or structurally invalid decomposition.
pub fn estimate_noise(d : Wavedec) -> Double? {
  let nbands = d.lengths.length()
  if nbands < 2 {
    return None
  }
  let dlen = d.lengths[nbands - 1]
  if dlen == 0 {
    return None
  }
  let start = d.coeffs.length() - dlen
  let abs = Array::make(dlen, 0.0)
  for i = 0; i < dlen; i = i + 1 {
    abs[i] = d.coeffs[start + i].abs()
  }
  abs.sort()
  let med = if dlen % 2 == 1 {
    abs[dlen / 2]
  } else {
    0.5 * (abs[dlen / 2 - 1] + abs[dlen / 2])
  }
  Some(med / 0.6745)
}

///|
/// Wavelet denoising (VisuShrink): decompose, estimate the noise scale from
/// the finest detail band, apply the universal threshold to all detail
/// bands, and reconstruct.
///
/// Returns the denoised signal of the same length as `x`, or `None` when
/// `x` cannot be decomposed (empty / too short / odd length).
///
/// `level` is clamped exactly as in `wavedec`; pass a large value (e.g. 10)
/// to decompose as deeply as the signal allows.
pub fn denoise(
  x : Array[Double],
  w : Wavelet,
  level : Int,
  mode : ThresholdMode,
) -> Array[Double]? {
  let d = match wavedec(x, w, level) {
    Some(dec) => dec
    None => return None
  }
  let sigma = match estimate_noise(d) {
    Some(s) => s
    None => return None
  }
  let lambda = universal_threshold(x.length(), sigma)
  if lambda > 0.0 {
    threshold_details(d, lambda, mode)
  }
  waverec(d, w)
}
