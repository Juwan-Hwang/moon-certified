/// DCT/DST — Discrete Cosine and Sine Transforms.
///
/// This module implements the complete family of discrete trigonometric
/// transforms used in signal processing, image compression, and numerical
/// analysis:
///
/// - **DCT-I** through **DCT-IV**: The four standard DCT types.
/// - **DST-I** through **DST-IV**: The four standard DST types.
/// - **2D DCT-II**: The workhorse of image compression (JPEG, WebP, HEIF).
/// - **IDCT (Inverse DCT-II)**: DCT-III with proper normalisation.
///
/// ## DCT Types
///
/// ### DCT-II (most common, used in JPEG/MP3/AAC)
/// ```text
/// X_k = Σ_{n=0}^{N-1} x_n · cos(π/N · (n+½) · k)
/// ```
/// Orthonormal: `c_0 = √(1/N)`, `c_k = √(2/N)` for k > 0.
///
/// ### DCT-III (inverse of DCT-II)
/// ```text
/// X_k = ½·x_0 + Σ_{n=1}^{N-1} x_n · cos(π/N · n · (k+½))
/// ```
/// Orthonormal: same factors as DCT-II.
///
/// ### DCT-IV (used in MDCT for audio coding)
/// ```text
/// X_k = Σ_{n=0}^{N-1} x_n · cos(π/N · (n+½) · (k+½))
/// ```
/// Orthonormal: `c = √(2/N)` for all k.
///
/// ## Normalisation
///
/// Two normalisation modes are supported:
/// - `OrthoNormal`: Forward and inverse are exact transposes (unitary).
/// - `Unnormalised`: Raw sum (forward only; inverse requires manual scaling).
///
/// ## Complexity
///
/// - Time: O(N²) per 1-D transform (direct computation). For production use
///   with large N, an FFT-based O(N log N) algorithm is preferable, but the
///   direct method is numerically exact and sufficient for N ≤ ~1024.
/// - Space: O(N) for 1-D, O(N²) for 2-D.
///
/// ## References
///
/// - Rao, K. R. and Yip, P. *Discrete Cosine Transform: Algorithms,
///   Advantages, Applications.* Academic Press, 1990.
/// - Strang, G. "The Discrete Cosine Transform." SIAM Review, 41(1), 135–147, 1999.
/// - Britanak, V., Yip, P., and Rao, K. R. *Discrete Cosine and Sine Transforms:
///   General Properties, Fast Algorithms and Integer Approximations.* Elsevier, 2007.
/// - ISO/IEC 10918-1 (JPEG): Annex A uses DCT-II.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Normalisation mode
// ---------------------------------------------------------------------------

///|
/// Normalisation mode for DCT/DST transforms.
///
/// - `OrthoNormal`: The transform is unitary — forward and inverse are exact
///   transposes of each other. This is the default for most applications.
/// - `Unnormalised`: Raw cosine/sine sums without scaling factors. The inverse
///   transform requires manual scaling by 2/N (DCT-I), 2/N (DCT-II/III), or
///   2/N (DCT-IV).
pub(all) enum NormMode {
  OrthoNormal
  Unnormalised
}

// ---------------------------------------------------------------------------
// DCT-I
// ---------------------------------------------------------------------------

///|
/// DCT-I (Type-I Discrete Cosine Transform).
///
/// **Unnormalised:**
/// ```text
/// X_k = ½(x_0 + (-1)^k · x_{N-1}) + Σ_{n=1}^{N-2} x_n · cos(π·n·k/(N-1))
/// ```
///
/// **Orthonormal** (self-inverse):
/// ```text
/// X_k = √(2/(N-1)) · γ_k · [x_0/√2 + Σ_{n=1}^{N-2} x_n · cos(π·n·k/(N-1)) + (-1)^k · x_{N-1}/√2]
/// ```
/// where γ_0 = γ_{N-1} = 1/√2, γ_n = 1 for 0 < n < N-1.
///
/// Note: DCT-I requires N ≥ 2. DCT-I is self-inverse in both modes
/// (unnormalised C²=I, orthonormal C²=I).
pub fn dct1(x : Array[Double], norm : NormMode) -> Array[Double] {
  let n = x.length()
  if n <= 1 {
    return Array::make(n, 0.0)
  }
  let result = Array::make(n, 0.0)
  let nm1 = n - 1
  let nm1d = nm1.to_double()
  match norm {
    OrthoNormal => {
      // Orthonormal: boundary elements scaled by 1/√2 instead of ½,
      // then result scaled by √(2/(N-1)) * γ_k.
      let sqrt2_inv = 1.0 / 2.0.sqrt()
      let scale_inner = (2.0 / nm1d).sqrt() // √(2/(N-1))
      let scale_bound = scale_inner * sqrt2_inv // √(1/(N-1))
      for k = 0; k < n; k = k + 1 {
        let mut sum = sqrt2_inv * x[0] // x_0 / √2
        for j = 1; j < nm1; j = j + 1 {
          sum = sum +
            x[j] * @math.cos(@math.PI * j.to_double() * k.to_double() / nm1d)
        }
        let sgn = if k % 2 == 0 { 1.0 } else { -1.0 }
        sum = sum + sqrt2_inv * sgn * x[nm1] // (-1)^k * x_{N-1} / √2
        result[k] = sum
      }
      // Apply γ_k scaling: boundary rows get √(1/(N-1)), inner rows get √(2/(N-1))
      result[0] = result[0] * scale_bound
      result[nm1] = result[nm1] * scale_bound
      for k = 1; k < nm1; k = k + 1 {
        result[k] = result[k] * scale_inner
      }
    }
    Unnormalised =>
      for k = 0; k < n; k = k + 1 {
        let mut sum = 0.0
        for j = 1; j < nm1; j = j + 1 {
          sum = sum +
            x[j] * @math.cos(@math.PI * j.to_double() * k.to_double() / nm1d)
        }
        let sgn = if k % 2 == 0 { 1.0 } else { -1.0 }
        sum = sum + 0.5 * (x[0] + sgn * x[nm1])
        result[k] = sum
      }
  }
  result
}

// ---------------------------------------------------------------------------
// DCT-II (the workhorse — JPEG, MP3, AAC)
// ---------------------------------------------------------------------------

///|
/// DCT-II (Type-II Discrete Cosine Transform).
///
/// This is the most widely used DCT type, employed in JPEG image compression,
/// MP3/AAC audio coding, and many spectral analysis applications.
///
/// ```text
/// X_k = Σ_{n=0}^{N-1} x_n · cos(π/N · (n+½) · k)
/// ```
///
/// With orthonormal normalisation:
/// - `X_0 *= √(1/N)`
/// - `X_k *= √(2/N)` for k > 0
pub fn dct2(x : Array[Double], norm : NormMode) -> Array[Double] {
  let n = x.length()
  if n == 0 {
    return []
  }
  let result = Array::make(n, 0.0)
  let pi_over_n = @math.PI / n.to_double()
  for k = 0; k < n; k = k + 1 {
    let mut sum = 0.0
    for j = 0; j < n; j = j + 1 {
      sum = sum +
        x[j] * @math.cos(pi_over_n * (j.to_double() + 0.5) * k.to_double())
    }
    result[k] = sum
  }
  match norm {
    OrthoNormal => {
      let s0 = (1.0 / n.to_double()).sqrt()
      let sk = (2.0 / n.to_double()).sqrt()
      result[0] = result[0] * s0
      for k = 1; k < n; k = k + 1 {
        result[k] = result[k] * sk
      }
    }
    Unnormalised => ()
  }
  result
}

// ---------------------------------------------------------------------------
// DCT-III (inverse of DCT-II)
// ---------------------------------------------------------------------------

///|
/// DCT-III (Type-III Discrete Cosine Transform).
///
/// This is the inverse of DCT-II when both use orthonormal normalisation.
///
/// **Unnormalised:**
/// ```text
/// X_k = ½·x_0 + Σ_{n=1}^{N-1} x_n · cos(π/N · n · (k+½))
/// ```
///
/// **Orthonormal** (inverse of orthonormal DCT-II):
/// ```text
/// X_k = √(1/N)·x_0 + √(2/N) · Σ_{n=1}^{N-1} x_n · cos(π/N · n · (k+½))
/// ```
pub fn dct3(x : Array[Double], norm : NormMode) -> Array[Double] {
  let n = x.length()
  if n == 0 {
    return []
  }
  let result = Array::make(n, 0.0)
  let pi_over_n = @math.PI / n.to_double()
  let nd = n.to_double()
  match norm {
    OrthoNormal => {
      // Orthonormal: x_0 scaled by √(1/N), x_n (n>0) by √(2/N).
      // NO ½ factor — that's only in the unnormalised version.
      let s0 = (1.0 / nd).sqrt()
      let sk = (2.0 / nd).sqrt()
      for k = 0; k < n; k = k + 1 {
        let mut sum = s0 * x[0]
        for j = 1; j < n; j = j + 1 {
          sum = sum +
            sk *
            x[j] *
            @math.cos(pi_over_n * j.to_double() * (k.to_double() + 0.5))
        }
        result[k] = sum
      }
    }
    Unnormalised =>
      for k = 0; k < n; k = k + 1 {
        let mut sum = 0.5 * x[0]
        for j = 1; j < n; j = j + 1 {
          sum = sum +
            x[j] * @math.cos(pi_over_n * j.to_double() * (k.to_double() + 0.5))
        }
        result[k] = sum
      }
  }
  result
}

// ---------------------------------------------------------------------------
// DCT-IV (used in MDCT for audio coding)
// ---------------------------------------------------------------------------

///|
/// DCT-IV (Type-IV Discrete Cosine Transform).
///
/// Used in the MDCT (Modified Discrete Cosine Transform) for audio coding
/// (MP3, AAC, Vorbis, Opus).
///
/// ```text
/// X_k = Σ_{n=0}^{N-1} x_n · cos(π/N · (n+½) · (k+½))
/// ```
///
/// DCT-IV is its own inverse when orthonormalised.
pub fn dct4(x : Array[Double], norm : NormMode) -> Array[Double] {
  let n = x.length()
  if n == 0 {
    return []
  }
  let result = Array::make(n, 0.0)
  let pi_over_n = @math.PI / n.to_double()
  for k = 0; k < n; k = k + 1 {
    let mut sum = 0.0
    for j = 0; j < n; j = j + 1 {
      sum = sum +
        x[j] *
        @math.cos(pi_over_n * (j.to_double() + 0.5) * (k.to_double() + 0.5))
    }
    result[k] = sum
  }
  match norm {
    OrthoNormal => {
      let s = (2.0 / n.to_double()).sqrt()
      for k = 0; k < n; k = k + 1 {
        result[k] = result[k] * s
      }
    }
    Unnormalised => ()
  }
  result
}

// ---------------------------------------------------------------------------
// IDCT (Inverse DCT-II = DCT-III with orthonormal normalisation)
// ---------------------------------------------------------------------------

///|
/// Inverse DCT-II: reconstructs the original signal from DCT-II coefficients.
///
/// This is `dct3` with `OrthoNormal` normalisation. When the forward transform
/// `dct2` also uses `OrthoNormal`, `idct(dct2(x)) ≈ x`.
pub fn idct(x : Array[Double]) -> Array[Double] {
  dct3(x, OrthoNormal)
}

// ---------------------------------------------------------------------------
// DST-I
// ---------------------------------------------------------------------------

///|
/// DST-I (Type-I Discrete Sine Transform).
///
/// ```text
/// X_k = Σ_{n=0}^{N-2} x_n · sin(π·(n+1)·(k+1)/N)
/// ```
///
/// Note: DST-I has N-1 output points for N-1 input points. This implementation
/// uses N input/output points with the convention that x_0 and x_{N-1} are
/// zero (boundary conditions).
pub fn dst1(x : Array[Double], norm : NormMode) -> Array[Double] {
  let n = x.length()
  if n <= 1 {
    return Array::make(n, 0.0)
  }
  let result = Array::make(n, 0.0)
  // DST-I: X_k = sum_{j=1}^{N-2} x_j * sin(pi * j * k / (N-1))
  // k ranges from 1 to N-2 (X_0 = X_{N-1} = 0).
  let nm1 = n - 1
  for k = 1; k < nm1; k = k + 1 {
    let mut sum = 0.0
    for j = 1; j < nm1; j = j + 1 {
      sum = sum +
        x[j] *
        @math.sin(@math.PI * j.to_double() * k.to_double() / nm1.to_double())
    }
    result[k] = sum
  }
  match norm {
    OrthoNormal => {
      let scale = (2.0 / nm1.to_double()).sqrt()
      for k = 1; k < nm1; k = k + 1 {
        result[k] = result[k] * scale
      }
    }
    Unnormalised => ()
  }
  result
}

// ---------------------------------------------------------------------------
// DST-II
// ---------------------------------------------------------------------------

///|
/// DST-II (Type-II Discrete Sine Transform).
///
/// ```text
/// X_k = Σ_{n=0}^{N-1} x_n · sin(π/N · (n+½) · (k+1))
/// ```
pub fn dst2(x : Array[Double], norm : NormMode) -> Array[Double] {
  let n = x.length()
  if n == 0 {
    return []
  }
  let result = Array::make(n, 0.0)
  let pi_over_n = @math.PI / n.to_double()
  for k = 0; k < n; k = k + 1 {
    let mut sum = 0.0
    for j = 0; j < n; j = j + 1 {
      sum = sum +
        x[j] *
        @math.sin(pi_over_n * (j.to_double() + 0.5) * (k.to_double() + 1.0))
    }
    result[k] = sum
  }
  match norm {
    OrthoNormal => {
      let scale = (2.0 / n.to_double()).sqrt()
      for k = 0; k < n - 1; k = k + 1 {
        result[k] = result[k] * scale
      }
      result[n - 1] = result[n - 1] * scale / 2.0.sqrt()
    }
    Unnormalised => ()
  }
  result
}

// ---------------------------------------------------------------------------
// DST-III
// ---------------------------------------------------------------------------

///|
/// DST-III (Type-III Discrete Sine Transform, inverse of DST-II).
///
/// **Unnormalised:**
/// ```text
/// X_k = Σ_{n=0}^{N-2} x_n · sin(π/N · (n+1) · (k+½)) + ½·(-1)^k · x_{N-1}
/// ```
///
/// **Orthonormal** (inverse of orthonormal DST-II):
/// ```text
/// X_k = √(2/N) · Σ_{n=0}^{N-2} x_n · sin(π/N · (n+1) · (k+½)) + √(1/N) · (-1)^k · x_{N-1}
/// ```
pub fn dst3(x : Array[Double], norm : NormMode) -> Array[Double] {
  let n = x.length()
  if n == 0 {
    return []
  }
  let result = Array::make(n, 0.0)
  let pi_over_n = @math.PI / n.to_double()
  let nd = n.to_double()
  match norm {
    OrthoNormal => {
      // Orthonormal: x_n (n<N-1) scaled by √(2/N), x_{N-1} by √(1/N).
      // NO ½ factor — that's only in the unnormalised version.
      let sk = (2.0 / nd).sqrt()
      let s_last = (1.0 / nd).sqrt()
      for k = 0; k < n; k = k + 1 {
        let mut sum = 0.0
        for j = 0; j < n - 1; j = j + 1 {
          sum = sum +
            sk *
            x[j] *
            @math.sin(pi_over_n * (j.to_double() + 1.0) * (k.to_double() + 0.5))
        }
        let sgn = if k % 2 == 0 { 1.0 } else { -1.0 }
        sum = sum + s_last * sgn * x[n - 1]
        result[k] = sum
      }
    }
    Unnormalised =>
      for k = 0; k < n; k = k + 1 {
        let mut sum = 0.0
        for j = 0; j < n - 1; j = j + 1 {
          sum = sum +
            x[j] *
            @math.sin(pi_over_n * (j.to_double() + 1.0) * (k.to_double() + 0.5))
        }
        let sgn = if k % 2 == 0 { 1.0 } else { -1.0 }
        sum = sum + 0.5 * sgn * x[n - 1]
        result[k] = sum
      }
  }
  result
}

// ---------------------------------------------------------------------------
// DST-IV
// ---------------------------------------------------------------------------

///|
/// DST-IV (Type-IV Discrete Sine Transform).
///
/// ```text
/// X_k = Σ_{n=0}^{N-1} x_n · sin(π/N · (n+½) · (k+½))
/// ```
///
/// Like DCT-IV, DST-IV is its own inverse when orthonormalised.
pub fn dst4(x : Array[Double], norm : NormMode) -> Array[Double] {
  let n = x.length()
  if n == 0 {
    return []
  }
  let result = Array::make(n, 0.0)
  let pi_over_n = @math.PI / n.to_double()
  for k = 0; k < n; k = k + 1 {
    let mut sum = 0.0
    for j = 0; j < n; j = j + 1 {
      sum = sum +
        x[j] *
        @math.sin(pi_over_n * (j.to_double() + 0.5) * (k.to_double() + 0.5))
    }
    result[k] = sum
  }
  match norm {
    OrthoNormal => {
      let s = (2.0 / n.to_double()).sqrt()
      for k = 0; k < n; k = k + 1 {
        result[k] = result[k] * s
      }
    }
    Unnormalised => ()
  }
  result
}

// ---------------------------------------------------------------------------
// 2D DCT-II (for image processing)
// ---------------------------------------------------------------------------

///|
/// 2D DCT-II: applies DCT-II to rows then columns.
///
/// This is the transform used in JPEG image compression. The input is a
/// row-major N×N matrix, and the output is the 2D DCT-II coefficients.
///
/// With `OrthoNormal` normalisation, the 2D transform is separable:
/// `2D-DCT(x) = dct2(dct2(x, rows), cols)`.
pub fn dct2_2d(
  matrix : Array[Array[Double]],
  norm : NormMode,
) -> Array[Array[Double]] {
  let rows = matrix.length()
  if rows == 0 {
    return []
  }
  let cols = matrix[0].length()
  if cols == 0 {
    return []
  }
  // Step 1: Apply DCT-II to each row.
  let row_transformed : Array[Array[Double]] = []
  for i = 0; i < rows; i = i + 1 {
    row_transformed.push(dct2(matrix[i], norm))
  }
  // Step 2: Apply DCT-II to each column.
  let result : Array[Array[Double]] = []
  for i = 0; i < rows; i = i + 1 {
    result.push(Array::make(cols, 0.0))
  }
  for j = 0; j < cols; j = j + 1 {
    let col : Array[Double] = []
    for i = 0; i < rows; i = i + 1 {
      col.push(row_transformed[i][j])
    }
    let col_transformed = dct2(col, norm)
    for i = 0; i < rows; i = i + 1 {
      result[i][j] = col_transformed[i]
    }
  }
  result
}

///|
/// 2D IDCT: inverse 2D DCT-II (applies IDCT to columns then rows).
pub fn idct_2d(matrix : Array[Array[Double]]) -> Array[Array[Double]] {
  let rows = matrix.length()
  if rows == 0 {
    return []
  }
  let cols = matrix[0].length()
  if cols == 0 {
    return []
  }
  // Step 1: Apply IDCT to each column.
  let col_transformed : Array[Array[Double]] = []
  for i = 0; i < rows; i = i + 1 {
    col_transformed.push(Array::make(cols, 0.0))
  }
  for j = 0; j < cols; j = j + 1 {
    let col : Array[Double] = []
    for i = 0; i < rows; i = i + 1 {
      col.push(matrix[i][j])
    }
    let col_idct = idct(col)
    for i = 0; i < rows; i = i + 1 {
      col_transformed[i][j] = col_idct[i]
    }
  }
  // Step 2: Apply IDCT to each row.
  let result : Array[Array[Double]] = []
  for i = 0; i < rows; i = i + 1 {
    result.push(idct(col_transformed[i]))
  }
  result
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "dct2: DC component of constant signal" {
  // DCT-II of constant signal [c, c, c, c] should have X_0 = c*N (unnormalised).
  let x = [5.0, 5.0, 5.0, 5.0]
  let result = dct2(x, Unnormalised)
  // X_0 = sum of x_n * cos(0) = 4*5 = 20
  assert_true(result[0] > 19.9 && result[0] < 20.1)
  // AC components should be ~0.
  for k = 1; k < 4; k = k + 1 {
    assert_true(result[k].abs() < 1.0e-10)
  }
}

///|
test "dct2: orthonormal round-trip" {
  // idct(dct2(x)) ≈ x with orthonormal normalisation.
  let x = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]
  let coeffs = dct2(x, OrthoNormal)
  let reconstructed = idct(coeffs)
  for i = 0; i < x.length(); i = i + 1 {
    assert_true((x[i] - reconstructed[i]).abs() < 1.0e-10)
  }
}

///|
test "dct2: single frequency signal" {
  // x_n = cos(π·k·(n+½)/N) should concentrate energy in DCT bin k.
  let n = 8
  let k = 2
  let x : Array[Double] = []
  for i = 0; i < n; i = i + 1 {
    x.push(
      @math.cos(
        @math.PI * k.to_double() * (i.to_double() + 0.5) / n.to_double(),
      ),
    )
  }
  let result = dct2(x, OrthoNormal)
  // Most energy should be in bin k.
  let mut max_idx = 0
  let mut max_val = 0.0
  for i = 0; i < n; i = i + 1 {
    if result[i].abs() > max_val {
      max_val = result[i].abs()
      max_idx = i
    }
  }
  assert_true(max_idx == k)
}

///|
test "dct2: delta function" {
  // DCT-II of [1, 0, 0, 0] should give constant X_k = cos(π·(0+½)·k/N).
  let x = [1.0, 0.0, 0.0, 0.0]
  let result = dct2(x, Unnormalised)
  let n = 4
  for k = 0; k < n; k = k + 1 {
    let expected = @math.cos(@math.PI * 0.5 * k.to_double() / n.to_double())
    assert_true((result[k] - expected).abs() < 1.0e-10)
  }
}

///|
test "dct3: inverse of dct2 (orthonormal)" {
  let x = [3.0, 1.0, 4.0, 1.0, 5.0, 9.0, 2.0, 6.0]
  let coeffs = dct2(x, OrthoNormal)
  let recovered = dct3(coeffs, OrthoNormal)
  for i = 0; i < x.length(); i = i + 1 {
    assert_true((x[i] - recovered[i]).abs() < 1.0e-10)
  }
}

///|
test "dct4: self-inverse (orthonormal)" {
  // DCT-IV is its own inverse when orthonormalised.
  let x = [1.0, 2.0, 3.0, 4.0]
  let coeffs = dct4(x, OrthoNormal)
  let recovered = dct4(coeffs, OrthoNormal)
  for i = 0; i < x.length(); i = i + 1 {
    assert_true((x[i] - recovered[i]).abs() < 1.0e-10)
  }
}

///|
test "dct1: orthonormal round-trip" {
  // DCT-I is its own inverse when orthonormalised.
  let x = [1.0, 2.0, 3.0, 4.0, 5.0]
  let coeffs = dct1(x, OrthoNormal)
  let recovered = dct1(coeffs, OrthoNormal)
  for i = 0; i < x.length(); i = i + 1 {
    assert_true((x[i] - recovered[i]).abs() < 1.0e-10)
  }
}

///|
test "dst1: orthonormal round-trip" {
  // DST-I is its own inverse when orthonormalised.
  // Input: [0, 1, 2, 3, 0] (boundaries must be 0).
  let x = [0.0, 1.0, 2.0, 3.0, 0.0]
  let coeffs = dst1(x, OrthoNormal)
  let recovered = dst1(coeffs, OrthoNormal)
  for i = 0; i < x.length(); i = i + 1 {
    assert_true((x[i] - recovered[i]).abs() < 1.0e-10)
  }
}

///|
test "dst4: self-inverse (orthonormal)" {
  // DST-IV is its own inverse when orthonormalised.
  let x = [1.0, 2.0, 3.0, 4.0]
  let coeffs = dst4(x, OrthoNormal)
  let recovered = dst4(coeffs, OrthoNormal)
  for i = 0; i < x.length(); i = i + 1 {
    assert_true((x[i] - recovered[i]).abs() < 1.0e-10)
  }
}

///|
test "dct2_2d: constant image" {
  // 2D DCT of constant image should have DC = c*N*M (unnormalised).
  let img = [
    [5.0, 5.0, 5.0, 5.0],
    [5.0, 5.0, 5.0, 5.0],
    [5.0, 5.0, 5.0, 5.0],
    [5.0, 5.0, 5.0, 5.0],
  ]
  let result = dct2_2d(img, Unnormalised)
  // DC coefficient should be 4*4*5 = 80.
  assert_true(result[0][0] > 79.0 && result[0][0] < 81.0)
  // All AC coefficients should be ~0.
  for i = 0; i < 4; i = i + 1 {
    for j = 0; j < 4; j = j + 1 {
      if i != 0 || j != 0 {
        assert_true(result[i][j].abs() < 1.0e-10)
      }
    }
  }
}

///|
test "dct2_2d: orthonormal round-trip" {
  let img = [
    [1.0, 2.0, 3.0, 4.0],
    [5.0, 6.0, 7.0, 8.0],
    [9.0, 10.0, 11.0, 12.0],
    [13.0, 14.0, 15.0, 16.0],
  ]
  let coeffs = dct2_2d(img, OrthoNormal)
  let recovered = idct_2d(coeffs)
  for i = 0; i < 4; i = i + 1 {
    for j = 0; j < 4; j = j + 1 {
      assert_true((img[i][j] - recovered[i][j]).abs() < 1.0e-10)
    }
  }
}

///|
test "dct2: energy compaction" {
  // DCT-II should concentrate most energy in low-frequency coefficients.
  // Use a smooth signal (low-frequency).
  let n = 16
  let x : Array[Double] = []
  for i = 0; i < n; i = i + 1 {
    x.push(@math.cos(2.0 * @math.PI * i.to_double() / n.to_double()))
  }
  let coeffs = dct2(x, OrthoNormal)
  // Compute total energy.
  let mut total_energy = 0.0
  for i = 0; i < n; i = i + 1 {
    total_energy = total_energy + coeffs[i] * coeffs[i]
  }
  // Energy in first 4 coefficients should be > 90% of total.
  let mut low_freq_energy = 0.0
  for i = 0; i < 4; i = i + 1 {
    low_freq_energy = low_freq_energy + coeffs[i] * coeffs[i]
  }
  assert_true(low_freq_energy / total_energy > 0.9)
}

///|
test "dct2: empty input" {
  let result = dct2([], OrthoNormal)
  assert_true(result.length() == 0)
}

///|
test "dct2: single element" {
  let result = dct2([42.0], OrthoNormal)
  assert_true(result.length() == 1)
  assert_true(result[0] > 41.9 && result[0] < 42.1)
}

///|
test "dst2: orthonormal round-trip via dst3" {
  let x = [1.0, 2.0, 3.0, 4.0]
  let coeffs = dst2(x, OrthoNormal)
  let recovered = dst3(coeffs, OrthoNormal)
  for i = 0; i < x.length(); i = i + 1 {
    assert_true((x[i] - recovered[i]).abs() < 1.0e-10)
  }
}

///|
test "dct2: larger orthonormal round-trip" {
  let n = 32
  let x : Array[Double] = []
  for i = 0; i < n; i = i + 1 {
    x.push(i.to_double() * 0.1)
  }
  let coeffs = dct2(x, OrthoNormal)
  let recovered = idct(coeffs)
  for i = 0; i < n; i = i + 1 {
    assert_true((x[i] - recovered[i]).abs() < 1.0e-9)
  }
}
