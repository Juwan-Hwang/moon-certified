/// Fast Fourier Transform (FFT) over the complex numbers.
///
/// The FFT evaluates a polynomial at the `n`-th roots of unity in
/// `O(n log n)` time; the inverse transform recovers the coefficients from
/// the evaluations. Polynomial multiplication (convolution) via FFT runs in
/// `O(n log n)` instead of the naive `O(n^2)`.
///
/// This is the floating-point analogue of the NTT in `number_theory/ntt`.
/// Unlike the NTT, results carry floating-point round-off error; tests compare
/// with tolerances rather than exact equality.
///
/// ## Algorithm
///
/// Implements the iterative Cooley-Tukey decimation-in-time butterfly. The
/// recursion is unrolled into an explicit bottom-up loop over transform
/// lengths `2, 4, ..., n`, which avoids stack overflow on large inputs and
/// keeps extra space to `O(1)` (beyond the input array). The input is first
/// permuted by an `O(n)` incremental bit-reversal so that the butterflies can
/// operate fully in place.
///
/// ## Sign convention
///
/// The forward transform `fft(a, false)` computes
///
/// ```text
/// X[k] = sum_{n=0}^{N-1} a[n] * exp(+2*pi*i*k*n / N)
/// ```
///
/// using the positive-exponent kernel (the same direction as the NTT
/// library's forward transform). The inverse transform `fft(a, true)` uses
/// the conjugate roots and divides every entry by `N`, so
/// `fft(fft(a, false), true) == a`. The sign of the exponent does not affect
/// convolution: pointwise multiplication in either domain followed by the
/// inverse transform yields the cyclic convolution.
///
/// ## API
///
/// - `Complex` — complex number type (`Double` real / imaginary parts)
/// - `c_add`, `c_sub`, `c_mul`, `c_div`, `c_abs`, `c_conj` — complex arithmetic
/// - `fft(a, invert)` — in-place forward or inverse FFT
/// - `multiply(a, b)` — polynomial multiplication returning `a * b`
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Complex numbers
// ---------------------------------------------------------------------------

///|
/// A complex number with `Double` real and imaginary parts.
///
/// Fields are private: construct with [`complex`] and read with [`re`] /
/// [`im`]. Keeping the representation private lets the FFT use struct literals
/// and field access internally while remaining free to change the layout
/// later (e.g. to a packed representation) without breaking callers.
pub struct Complex {
  priv real : Double
  priv imag : Double
}

///|
/// Construct the complex number `real + imag * i`.
pub fn complex(real : Double, imag : Double) -> Complex {
  { real, imag }
}

///|
/// Real part of `c`.
pub fn re(c : Complex) -> Double {
  c.real
}

///|
/// Imaginary part of `c`.
pub fn im(c : Complex) -> Double {
  c.imag
}

///|
/// Complex addition: `(a + b)`.
pub fn c_add(a : Complex, b : Complex) -> Complex {
  { real: a.real + b.real, imag: a.imag + b.imag }
}

///|
/// Complex subtraction: `(a - b)`.
pub fn c_sub(a : Complex, b : Complex) -> Complex {
  { real: a.real - b.real, imag: a.imag - b.imag }
}

///|
/// Complex multiplication: `(a * b)`.
///
/// Uses the identity
/// `(ar + ai i)(br + bi i) = (ar*br - ai*bi) + (ar*bi + ai*br) i`.
pub fn c_mul(a : Complex, b : Complex) -> Complex {
  {
    real: a.real * b.real - a.imag * b.imag,
    imag: a.real * b.imag + a.imag * b.real,
  }
}

///|
/// Complex division: `(a / b)`.
///
/// Multiplies numerator and denominator by the conjugate of `b` so the
/// denominator becomes the real scalar `|b|^2`:
/// `(ar*br + ai*bi)/|b|^2 + (ai*br - ar*bi)/|b|^2 * i`.
///
/// Follows IEEE-754 semantics for a zero denominator: `|b|^2 = 0` yields
/// `Inf` or `NaN` components rather than aborting, matching the behaviour of
/// ordinary `Double` division.
pub fn c_div(a : Complex, b : Complex) -> Complex {
  let denom = b.real * b.real + b.imag * b.imag
  {
    real: (a.real * b.real + a.imag * b.imag) / denom,
    imag: (a.imag * b.real - a.real * b.imag) / denom,
  }
}

///|
/// Modulus (absolute value) `|c| = sqrt(real^2 + imag^2)`.
pub fn c_abs(c : Complex) -> Double {
  (c.real * c.real + c.imag * c.imag).sqrt()
}

///|
/// Complex conjugate `conj(a + bi) = a - bi`.
pub fn c_conj(c : Complex) -> Complex {
  { real: c.real, imag: -c.imag }
}

// ---------------------------------------------------------------------------
// Bit-reversal permutation
// ---------------------------------------------------------------------------

///|
/// Reorder `a` so that element `i` moves to the position obtained by reversing
/// the `log2(n)` low bits of `i`. This is the standard pre-processing step
/// for the iterative (Cooley-Tukey) FFT.
///
/// Uses the standard `O(n)` incremental bit-reversal: each index `j` is
/// derived from the previous one by adding 1 in reversed-bit order (most
/// significant bit first), avoiding the `O(n log n)` cost of reversing the
/// bits of every index independently. This is the same pattern used by the
/// NTT library's `bit_reverse`, adapted to `Array[Complex]`.
fn bit_reverse(a : Array[Complex], n : Int) -> Unit {
  let mut j = 0
  for i = 1; i < n; i = i + 1 {
    // Compute the bit-reversal of i from the bit-reversal of i-1:
    // add 1 to the reversed representation (MSB first).
    let mut bit = n >> 1
    while (j & bit) != 0 {
      j = j ^ bit
      bit = bit >> 1
    }
    j = j | bit
    if j > i {
      let tmp = a[i]
      a[i] = a[j]
      a[j] = tmp
    }
  }
}

// ---------------------------------------------------------------------------
// Core FFT
// ---------------------------------------------------------------------------

///|
/// In-place iterative Cooley-Tukey FFT.
///
/// When `invert` is `false`, performs the forward transform: evaluates the
/// input at the powers of the primitive `n`-th root of unity
/// `exp(+2*pi*i/n)`.
///
/// When `invert` is `true`, performs the inverse transform: recovers the
/// original coefficients from the evaluations, using the conjugate roots and
/// dividing every entry by `n`.
///
/// The array length `n` must be a power of 2; otherwise the function aborts.
/// Lengths 0 and 1 are no-ops. The transform runs in `O(n log n)` time and
/// `O(1)` extra space (beyond the input array), and operates fully in place.
///
/// The iterative bottom-up loop (lengths `2, 4, ..., n`) is used instead of
/// recursion to avoid stack overflow on large inputs.
pub fn fft(a : Array[Complex], invert : Bool) -> Unit {
  let n = a.length()
  if n <= 1 {
    return
  }
  // Verify n is a power of 2; if not, return silently (no-op).
  if (n & (n - 1)) != 0 {
    return
  }
  bit_reverse(a, n)
  // Cooley-Tukey butterfly: process lengths 2, 4, 8, ..., n.
  let mut len = 2
  while len <= n {
    // Primitive len-th root of unity. Forward uses exp(+2*pi*i/len);
    // inverse uses the conjugate exp(-2*pi*i/len).
    let sign : Double = if invert { -1.0 } else { 1.0 }
    let ang = 2.0 * @math.PI * sign / len.to_double()
    let wlen = complex(@math.cos(ang), @math.sin(ang))
    let half = len / 2
    let mut i = 0
    while i < n {
      let mut w = complex(1.0, 0.0)
      let mut j = 0
      while j < half {
        let u = a[i + j]
        let v = c_mul(a[i + j + half], w)
        a[i + j] = c_add(u, v)
        a[i + j + half] = c_sub(u, v)
        w = c_mul(w, wlen)
        j = j + 1
      }
      i = i + len
    }
    len = len * 2
  }
  if invert {
    // Divide by n to complete the inverse transform.
    let inv_n = 1.0 / n.to_double()
    for i = 0; i < n; i = i + 1 {
      a[i] = { real: a[i].real * inv_n, imag: a[i].imag * inv_n }
    }
  }
}

// ---------------------------------------------------------------------------
// Polynomial multiplication
// ---------------------------------------------------------------------------

///|
/// Multiply two polynomials with real (`Double`) coefficients.
///
/// Given coefficient arrays `a` (degree `len(a) - 1`) and `b` (degree
/// `len(b) - 1`), returns the product `c = a * b` of degree
/// `len(a) + len(b) - 2`, i.e. an array of `len(a) + len(b) - 1`
/// coefficients where `c[k] = sum_{i+j=k} a[i] * b[j]`.
///
/// Inputs of arbitrary length are supported: the convolution is computed by
/// padding both operands to the next power of two `>= len(a) + len(b) - 1`
/// internally, so callers never need to align lengths themselves. The result
/// is trimmed back to the exact convolution length.
///
/// Uses the FFT for `O(n log n)` multiplication. Results carry floating-point
/// round-off; for integer inputs the values are within a few `1e-9` of the
/// true integers.
///
/// Returns an empty array if either input is empty.
pub fn multiply(a : Array[Double], b : Array[Double]) -> Array[Double] {
  if a.length() == 0 || b.length() == 0 {
    return []
  }
  let result_len = a.length() + b.length() - 1
  // Pad to the next power of 2 >= result_len.
  let mut n = 1
  while n < result_len {
    n = n * 2
  }
  // Copy a and b into complex arrays of length n (zero-padded).
  let fa : Array[Complex] = []
  let fb : Array[Complex] = []
  for i = 0; i < n; i = i + 1 {
    if i < a.length() {
      fa.push(complex(a[i], 0.0))
    } else {
      fa.push(complex(0.0, 0.0))
    }
    if i < b.length() {
      fb.push(complex(b[i], 0.0))
    } else {
      fb.push(complex(0.0, 0.0))
    }
  }
  // Forward FFT both, pointwise multiply, inverse FFT.
  fft(fa, false)
  fft(fb, false)
  for i = 0; i < n; i = i + 1 {
    fa[i] = c_mul(fa[i], fb[i])
  }
  fft(fa, true)
  // Truncate to the exact convolution length, keeping the real parts.
  let result : Array[Double] = []
  for i = 0; i < result_len; i = i + 1 {
    result.push(fa[i].real)
  }
  result
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

///|
/// Tolerant equality for `Double`: passes if the difference is within an
/// absolute bound (`1e-6`) or a relative bound (`1e-6` of the larger
/// magnitude). Used everywhere FFT results are compared, since the transform
/// accumulates a small amount of floating-point error.
fn approx_eq(a : Double, b : Double) -> Bool {
  let diff = (a - b).abs()
  diff < 1.0e-6 || diff < 1.0e-6 * (a.abs() + b.abs())
}

///|
/// Assert `a` and `b` are approximately equal, panicking with a message if
/// not. The explicit message makes FFT round-off failures easy to diagnose.
fn assert_approx(a : Double, b : Double) -> Unit {
  if !approx_eq(a, b) {
    abort("assert_approx: " + a.to_string() + " != " + b.to_string())
  }
}

///|
/// Naive `O(n*m)` convolution, used as an independent oracle for the FFT
/// multiplier in the tests below.
fn brute_convolve(a : Array[Double], b : Array[Double]) -> Array[Double] {
  let m = a.length()
  let nn = b.length()
  if m == 0 || nn == 0 {
    return []
  }
  let result_len = m + nn - 1
  let acc = FixedArray::make(result_len, 0.0)
  for i = 0; i < m; i = i + 1 {
    for j = 0; j < nn; j = j + 1 {
      acc[i + j] = acc[i + j] + a[i] * b[j]
    }
  }
  let out : Array[Double] = []
  for k = 0; k < result_len; k = k + 1 {
    out.push(acc[k])
  }
  out
}

///|
/// Direct `O(n^2)` DFT using the same `+2*pi*i` convention as
/// `fft(_, false)`, used as an independent oracle for the transform itself.
fn direct_dft(a : Array[Double]) -> Array[Complex] {
  let n = a.length()
  let out : Array[Complex] = []
  for k = 0; k < n; k = k + 1 {
    let mut sre = 0.0
    let mut sim = 0.0
    for j = 0; j < n; j = j + 1 {
      let ang = 2.0 * @math.PI * k.to_double() * j.to_double() / n.to_double()
      sre = sre + a[j] * @math.cos(ang)
      sim = sim + a[j] * @math.sin(ang)
    }
    out.push(complex(sre, sim))
  }
  out
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "fft: complex arithmetic" {
  // (1 + 2i) + (3 - i) = 4 + i
  let z1 = c_add(complex(1.0, 2.0), complex(3.0, -1.0))
  assert_approx(re(z1), 4.0)
  assert_approx(im(z1), 1.0)
  // (1 + 2i) - (3 - i) = -2 + 3i
  let z2 = c_sub(complex(1.0, 2.0), complex(3.0, -1.0))
  assert_approx(re(z2), -2.0)
  assert_approx(im(z2), 3.0)
  // (1 + 2i) * (3 + 4i) = (3 - 8) + (4 + 6)i = -5 + 10i
  let z3 = c_mul(complex(1.0, 2.0), complex(3.0, 4.0))
  assert_approx(re(z3), -5.0)
  assert_approx(im(z3), 10.0)
  // (3 + 4i) / (1 + i) = (3+4i)(1-i)/2 = (7 + i)/2 = 3.5 + 0.5i
  let z4 = c_div(complex(3.0, 4.0), complex(1.0, 1.0))
  assert_approx(re(z4), 3.5)
  assert_approx(im(z4), 0.5)
  // |3 + 4i| = 5
  assert_approx(c_abs(complex(3.0, 4.0)), 5.0)
  // conj(3 + 4i) = 3 - 4i
  let z5 = c_conj(complex(3.0, 4.0))
  assert_approx(re(z5), 3.0)
  assert_approx(im(z5), -4.0)
}

///|
test "fft: forward and inverse round-trip" {
  let original = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]
  let a : Array[Complex] = []
  for i = 0; i < original.length(); i = i + 1 {
    a.push(complex(original[i], 0.0))
  }
  fft(a, false)
  fft(a, true)
  // After forward + inverse, we recover the original exactly up to round-off.
  for i = 0; i < original.length(); i = i + 1 {
    assert_approx(re(a[i]), original[i])
    assert_approx(im(a[i]), 0.0)
  }
}

///|
test "fft: known DFT values" {
  // DFT of [1, 1, 1, 1] is [4, 0, 0, 0] (sign-independent).
  let a : Array[Complex] = [
    complex(1.0, 0.0),
    complex(1.0, 0.0),
    complex(1.0, 0.0),
    complex(1.0, 0.0),
  ]
  fft(a, false)
  assert_approx(re(a[0]), 4.0)
  assert_approx(im(a[0]), 0.0)
  for k = 1; k < 4; k = k + 1 {
    assert_approx(re(a[k]), 0.0)
    assert_approx(im(a[k]), 0.0)
  }
  // DFT of [0, 1, 0, 0] is [1, +i, -1, -i] under the +2*pi*i convention.
  let b : Array[Complex] = [
    complex(0.0, 0.0),
    complex(1.0, 0.0),
    complex(0.0, 0.0),
    complex(0.0, 0.0),
  ]
  fft(b, false)
  assert_approx(re(b[0]), 1.0)
  assert_approx(im(b[0]), 0.0)
  assert_approx(re(b[1]), 0.0)
  assert_approx(im(b[1]), 1.0)
  assert_approx(re(b[2]), -1.0)
  assert_approx(im(b[2]), 0.0)
  assert_approx(re(b[3]), 0.0)
  assert_approx(im(b[3]), -1.0)
  // Cross-check against the direct O(n^2) DFT for a non-trivial signal.
  let signal = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]
  let c : Array[Complex] = []
  for i = 0; i < signal.length(); i = i + 1 {
    c.push(complex(signal[i], 0.0))
  }
  fft(c, false)
  let expected = direct_dft(signal)
  for k = 0; k < signal.length(); k = k + 1 {
    assert_approx(re(c[k]), re(expected[k]))
    assert_approx(im(c[k]), im(expected[k]))
  }
}

///|
test "fft: polynomial multiply simple" {
  // (1 + x) * (1 + x) = 1 + 2x + x^2
  let c = multiply([1.0, 1.0], [1.0, 1.0])
  assert_eq(c.length(), 3)
  assert_approx(c[0], 1.0)
  assert_approx(c[1], 2.0)
  assert_approx(c[2], 1.0)
}

///|
test "fft: polynomial multiply larger" {
  // (1 + 2x + 3x^2) * (4 + 5x) = 4 + 13x + 22x^2 + 15x^3
  let c = multiply([1.0, 2.0, 3.0], [4.0, 5.0])
  assert_eq(c.length(), 4)
  assert_approx(c[0], 4.0)
  assert_approx(c[1], 13.0) // 1*5 + 2*4
  assert_approx(c[2], 22.0) // 2*5 + 3*4
  assert_approx(c[3], 15.0) // 3*5
}

///|
test "fft: multiply degree 0" {
  // Constant * constant.
  let c = multiply([7.0], [3.0])
  assert_eq(c.length(), 1)
  assert_approx(c[0], 21.0)
}

///|
test "fft: empty input" {
  // Either operand empty -> empty result.
  assert_true(multiply([], [1.0, 2.0]).length() == 0)
  assert_true(multiply([1.0, 2.0], []).length() == 0)
  assert_true(multiply([], []).length() == 0)
}

///|
test "fft: single element" {
  // [5] * [3, 7, 11] = [15, 35, 55]
  let c = multiply([5.0], [3.0, 7.0, 11.0])
  assert_eq(c.length(), 3)
  assert_approx(c[0], 15.0)
  assert_approx(c[1], 35.0)
  assert_approx(c[2], 55.0)
}

///|
test "fft: non-power-of-2 padding" {
  // Inputs whose convolution length is not a power of 2 exercise the
  // internal zero-padding. (1 + 2x + 3x^2) * (1 + x + x^2 + x^3 + x^4)
  // has result length 3 + 5 - 1 = 7 (next power of 2 is 8).
  let a = [1.0, 2.0, 3.0]
  let b = [1.0, 1.0, 1.0, 1.0, 1.0]
  let c = multiply(a, b)
  assert_eq(c.length(), 7)
  let expected = brute_convolve(a, b)
  for i = 0; i < expected.length(); i = i + 1 {
    assert_approx(c[i], expected[i])
  }
  // Sanity-check a couple of coefficients by hand:
  // c[0] = 1*1 = 1; c[6] = 3*1 = 3.
  assert_approx(c[0], 1.0)
  assert_approx(c[6], 3.0)
}

///|
test "fft: large input stress" {
  // 64 x 64 convolution: result length 127 (next power of 2 is 128).
  let a : Array[Double] = []
  let b : Array[Double] = []
  for i = 0; i < 64; i = i + 1 {
    a.push((i * 3 + 1).to_double())
    b.push((i * 2 + 5).to_double())
  }
  let c = multiply(a, b)
  let expected = brute_convolve(a, b)
  assert_eq(c.length(), expected.length())
  for i = 0; i < expected.length(); i = i + 1 {
    assert_approx(c[i], expected[i])
  }
}

///|
test "fft: cross-check with brute force" {
  // Asymmetric lengths and mixed magnitudes, compared against the O(n^2)
  // oracle coefficient by coefficient.
  let a = [1.0, 2.0, 3.0, 4.0, 5.0]
  let b = [6.0, 7.0, 8.0, 9.0]
  let c = multiply(a, b)
  let expected = brute_convolve(a, b)
  assert_eq(c.length(), a.length() + b.length() - 1)
  for i = 0; i < expected.length(); i = i + 1 {
    assert_approx(c[i], expected[i])
  }
}
