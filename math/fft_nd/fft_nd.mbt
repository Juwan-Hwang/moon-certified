/// Multi-dimensional Fast Fourier Transform.
///
/// The N-dimensional DFT is defined as:
///
/// ```text
/// X[k0, k1, ..., k_{N-1}] = Σ_{n0=0}^{d0-1} ... Σ_{n_{N-1}=0}^{d_{N-1}-1}
///   x[n0, ..., n_{N-1}] * exp(+2πi * Σ_j (kj * nj / dj))
/// ```
///
/// This is computed by the **separability** property: the N-D DFT decomposes
/// into N successive 1-D DFTs applied along each axis. For each axis k, we
/// extract every 1-D slice along that axis and apply a standard 1-D FFT.
///
/// ## Algorithm
///
/// For each axis `k = 0, 1, ..., N-1`:
///   1. Compute the stride along axis k (product of dimensions after k).
///   2. For each hyper-plane perpendicular to axis k, extract all 1-D slices
///      (contiguous elements spaced `stride` apart) and apply the 1-D FFT.
///
/// All dimensions must be powers of two. The transform operates in place.
///
/// ## Complexity
///
/// O(N_total * Σ log(d_k)) where N_total = d0 * d1 * ... * d_{N-1}.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// 2-D FFT (the most common case, used in image and signal processing)
// ---------------------------------------------------------------------------

///|
/// Perform an in-place 2-D FFT on a flat row-major array of shape `(rows, cols)`.
///
/// `data` must have exactly `rows * cols` elements. Both `rows` and `cols`
/// must be powers of two. When `invert` is `false` the forward transform is
/// computed; when `true` the inverse transform is computed (with the `1/N`
/// normalisation).
///
/// Returns `true` on success, `false` if the dimensions are invalid (size
/// mismatch or non-power-of-two). On failure `data` may be partially modified.
///
/// **Complexity**: O(rows * cols * (log rows + log cols)).
pub fn fft_2d(
  data : Array[@fft.Complex],
  rows : Int,
  cols : Int,
  invert : Bool,
) -> Bool {
  if data.length() != rows * cols {
    return false
  }
  if rows < 1 || cols < 1 {
    return false
  }
  if (rows & (rows - 1)) != 0 || (cols & (cols - 1)) != 0 {
    return false
  }
  // Step 1: Transform each row (axis 1 — contiguous elements).
  for r = 0; r < rows; r = r + 1 {
    let offset = r * cols
    let row : Array[@fft.Complex] = Array::make(cols, @fft.complex(0.0, 0.0))
    for c = 0; c < cols; c = c + 1 {
      row[c] = data[offset + c]
    }
    @fft.fft(row, invert)
    for c = 0; c < cols; c = c + 1 {
      data[offset + c] = row[c]
    }
  }
  // Step 2: Transform each column (axis 0 — strided elements).
  for c = 0; c < cols; c = c + 1 {
    let col : Array[@fft.Complex] = Array::make(rows, @fft.complex(0.0, 0.0))
    for r = 0; r < rows; r = r + 1 {
      col[r] = data[r * cols + c]
    }
    @fft.fft(col, invert)
    for r = 0; r < rows; r = r + 1 {
      data[r * cols + c] = col[r]
    }
  }
  true
}

///|
/// Convenience wrapper: forward 2-D FFT. Returns a **new** array; the input
/// is not modified.
pub fn fft_2d_forward(
  data : Array[@fft.Complex],
  rows : Int,
  cols : Int,
) -> Array[@fft.Complex]? {
  let copy = copy_complex_array(data)
  if fft_2d(copy, rows, cols, false) {
    Some(copy)
  } else {
    None
  }
}

///|
/// Convenience wrapper: inverse 2-D FFT. Returns a **new** array; the input
/// is not modified.
pub fn fft_2d_inverse(
  data : Array[@fft.Complex],
  rows : Int,
  cols : Int,
) -> Array[@fft.Complex]? {
  let copy = copy_complex_array(data)
  if fft_2d(copy, rows, cols, true) {
    Some(copy)
  } else {
    None
  }
}

// ---------------------------------------------------------------------------
// N-D FFT (general case)
// ---------------------------------------------------------------------------

///|
/// Perform an in-place N-dimensional FFT on a flat row-major array.
///
/// `shape` is the array of dimension sizes `[d0, d1, ..., d_{N-1}]`. `data`
/// must have exactly `d0 * d1 * ... * d_{N-1}` elements. Every dimension must
/// be a power of two. When `invert` is `false` the forward transform is
/// computed; when `true` the inverse (with `1/N_total` normalisation).
///
/// Returns `true` on success, `false` if the shape is invalid.
///
/// **Complexity**: O(N_total * Σ log(d_k)).
pub fn fft_nd(
  data : Array[@fft.Complex],
  shape : Array[Int],
  invert : Bool,
) -> Bool {
  let ndim = shape.length()
  if ndim == 0 {
    return data.length() == 0
  }
  // Validate dimensions and compute total size.
  let mut total = 1
  for k = 0; k < ndim; k = k + 1 {
    let d = shape[k]
    if d < 1 || (d & (d - 1)) != 0 {
      return false
    }
    total = total * d
  }
  if data.length() != total {
    return false
  }
  // Transform each axis.
  for axis = 0; axis < ndim; axis = axis + 1 {
    fft_nd_axis(data, shape, axis, invert)
  }
  true
}

///|
/// Transform along a single axis of an N-dimensional array.
///
/// The data is stored in row-major (C) order. For axis `k`:
/// - `stride` = product of shape[k+1 .. ndim-1] (distance between consecutive
///   elements along axis k)
/// - `axis_size` = shape[k] (number of elements in each 1-D slice)
/// - `outer` = total / axis_size (number of independent 1-D slices)
///
/// For each of the `outer` slices, and for each offset within the stride,
/// we extract `axis_size` elements spaced `stride` apart, apply the 1-D FFT,
/// and scatter them back.
fn fft_nd_axis(
  data : Array[@fft.Complex],
  shape : Array[Int],
  axis : Int,
  invert : Bool,
) -> Unit {
  let ndim = shape.length()
  // stride = product of dimensions after `axis`
  let mut stride = 1
  for k = axis + 1; k < ndim; k = k + 1 {
    stride = stride * shape[k]
  }
  let axis_size = shape[axis]
  // outer = product of dimensions before `axis`
  let mut outer = 1
  for k = 0; k < axis; k = k + 1 {
    outer = outer * shape[k]
  }
  // Total number of 1-D slices = outer * stride.
  let num_slices = outer * stride
  let slice : Array[@fft.Complex] = Array::make(
    axis_size,
    @fft.complex(0.0, 0.0),
  )
  for s = 0; s < num_slices; s = s + 1 {
    // The s-th slice starts at: (s / stride) * axis_size * stride + (s % stride)
    let base = s / stride * axis_size * stride + s % stride
    // Gather elements along this axis.
    for i = 0; i < axis_size; i = i + 1 {
      slice[i] = data[base + i * stride]
    }
    @fft.fft(slice, invert)
    // Scatter back.
    for i = 0; i < axis_size; i = i + 1 {
      data[base + i * stride] = slice[i]
    }
  }
}

///|
/// Convenience wrapper: forward N-D FFT. Returns a **new** array.
pub fn fft_nd_forward(
  data : Array[@fft.Complex],
  shape : Array[Int],
) -> Array[@fft.Complex]? {
  let copy = copy_complex_array(data)
  if fft_nd(copy, shape, false) {
    Some(copy)
  } else {
    None
  }
}

///|
/// Convenience wrapper: inverse N-D FFT. Returns a **new** array.
pub fn fft_nd_inverse(
  data : Array[@fft.Complex],
  shape : Array[Int],
) -> Array[@fft.Complex]? {
  let copy = copy_complex_array(data)
  if fft_nd(copy, shape, true) {
    Some(copy)
  } else {
    None
  }
}

// ---------------------------------------------------------------------------
// 2-D convolution via FFT
// ---------------------------------------------------------------------------

///|
/// 2-D convolution of two real-valued matrices via FFT.
///
/// `a` is a flat row-major array of shape `(ra, ca)`, `b` has shape
/// `(rb, cb)`. The result has shape `(ra + rb - 1, ca + cb - 1)`.
///
/// Both dimensions are padded to the next power of two ≥ the output size,
/// the 2-D FFT is applied to both padded inputs, they are multiplied
/// pointwise, and the inverse 2-D FFT recovers the convolution. The result
/// is trimmed to the exact output shape.
///
/// Returns `None` if either input is empty.
pub fn convolve_2d(
  a : Array[Double],
  ra : Int,
  ca : Int,
  b : Array[Double],
  rb : Int,
  cb : Int,
) -> Array[Double]? {
  if a.length() != ra * ca || b.length() != rb * cb {
    return None
  }
  if ra == 0 || ca == 0 || rb == 0 || cb == 0 {
    return None
  }
  let out_rows = ra + rb - 1
  let out_cols = ca + cb - 1
  // Pad to next power of two.
  let mut pr = 1
  while pr < out_rows {
    pr = pr * 2
  }
  let mut pc = 1
  while pc < out_cols {
    pc = pc * 2
  }
  // Create padded complex arrays.
  let fa : Array[@fft.Complex] = Array::make(pr * pc, @fft.complex(0.0, 0.0))
  let fb : Array[@fft.Complex] = Array::make(pr * pc, @fft.complex(0.0, 0.0))
  for r = 0; r < ra; r = r + 1 {
    for c = 0; c < ca; c = c + 1 {
      fa[r * pc + c] = @fft.complex(a[r * ca + c], 0.0)
    }
  }
  for r = 0; r < rb; r = r + 1 {
    for c = 0; c < cb; c = c + 1 {
      fb[r * pc + c] = @fft.complex(b[r * cb + c], 0.0)
    }
  }
  // Forward 2-D FFT on both.
  let _ = fft_2d(fa, pr, pc, false)
  let _ = fft_2d(fb, pr, pc, false)
  // Pointwise multiply.
  for i = 0; i < pr * pc; i = i + 1 {
    fa[i] = @fft.c_mul(fa[i], fb[i])
  }
  // Inverse 2-D FFT.
  let _ = fft_2d(fa, pr, pc, true)
  // Extract real part, trimmed to output size.
  let result : Array[Double] = Array::make(out_rows * out_cols, 0.0)
  for r = 0; r < out_rows; r = r + 1 {
    for c = 0; c < out_cols; c = c + 1 {
      result[r * out_cols + c] = @fft.re(fa[r * pc + c])
    }
  }
  Some(result)
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

///|
fn copy_complex_array(data : Array[@fft.Complex]) -> Array[@fft.Complex] {
  let n = data.length()
  let out : Array[@fft.Complex] = Array::make(n, @fft.complex(0.0, 0.0))
  for i = 0; i < n; i = i + 1 {
    out[i] = data[i]
  }
  out
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "fft_2d: identity (forward then inverse)" {
  // 4x4 identity test: ifft(fft(x)) ≈ x
  let rows = 4
  let cols = 4
  let data : Array[@fft.Complex] = Array::make(
    rows * cols,
    @fft.complex(0.0, 0.0),
  )
  // Fill with known values.
  for r = 0; r < rows; r = r + 1 {
    for c = 0; c < cols; c = c + 1 {
      data[r * cols + c] = @fft.complex(
        r.to_double() + c.to_double() * 0.5,
        0.0,
      )
    }
  }
  let original = copy_complex_array(data)
  // Forward then inverse should recover the original (within float tolerance).
  assert_true(fft_2d(data, rows, cols, false))
  assert_true(fft_2d(data, rows, cols, true))
  for i = 0; i < rows * cols; i = i + 1 {
    assert_true((@fft.re(data[i]) - @fft.re(original[i])).abs() < 1.0e-9)
    assert_true((@fft.im(data[i]) - @fft.im(original[i])).abs() < 1.0e-9)
  }
}

///|
test "fft_2d: DC component of constant signal" {
  // A 2x2 constant signal: all ones. The DC bin (0,0) should be 4.
  let data : Array[@fft.Complex] = Array::make(4, @fft.complex(1.0, 0.0))
  assert_true(fft_2d(data, 2, 2, false))
  // DC = sum of all elements = 4.
  assert_true((@fft.re(data[0]) - 4.0).abs() < 1.0e-9)
  assert_true(@fft.im(data[0]).abs() < 1.0e-9)
  // All other bins should be ~0.
  for i = 1; i < 4; i = i + 1 {
    assert_true(@fft.re(data[i]).abs() < 1.0e-9)
    assert_true(@fft.im(data[i]).abs() < 1.0e-9)
  }
}

///|
test "fft_2d: single impulse (delta) gives all-ones spectrum" {
  // A 4x4 delta at (0,0): spectrum should be all 1+0j.
  let rows = 4
  let cols = 4
  let data : Array[@fft.Complex] = Array::make(
    rows * cols,
    @fft.complex(0.0, 0.0),
  )
  data[0] = @fft.complex(1.0, 0.0)
  assert_true(fft_2d(data, rows, cols, false))
  for i = 0; i < rows * cols; i = i + 1 {
    assert_true((@fft.re(data[i]) - 1.0).abs() < 1.0e-9)
    assert_true(@fft.im(data[i]).abs() < 1.0e-9)
  }
}

///|
test "fft_2d: known 2x2 transform" {
  // data = [[1, 2], [3, 4]]
  // 1-D FFT of row [1,2] = [3, -1]
  // 1-D FFT of row [3,4] = [7, -1]
  // After row transform: [[3,-1],[7,-1]]
  // 1-D FFT of col [3,7] = [10, -4]
  // 1-D FFT of col [-1,-1] = [-2, 0]
  // Result: [[10,-2],[-4,0]]
  let data : Array[@fft.Complex] = [
    @fft.complex(1.0, 0.0),
    @fft.complex(2.0, 0.0),
    @fft.complex(3.0, 0.0),
    @fft.complex(4.0, 0.0),
  ]
  assert_true(fft_2d(data, 2, 2, false))
  assert_true((@fft.re(data[0]) - 10.0).abs() < 1.0e-9)
  assert_true((@fft.re(data[1]) - -2.0).abs() < 1.0e-9)
  assert_true((@fft.re(data[2]) - -4.0).abs() < 1.0e-9)
  assert_true((@fft.re(data[3]) - 0.0).abs() < 1.0e-9)
}

///|
test "fft_2d: invalid dimensions return false" {
  let data : Array[@fft.Complex] = Array::make(6, @fft.complex(0.0, 0.0))
  // 2x3 — 3 is not a power of two.
  assert_false(fft_2d(data, 2, 3, false))
  // Size mismatch.
  assert_false(fft_2d(data, 2, 2, false))
}

///|
test "fft_2d: 8x8 round-trip with random-ish data" {
  let rows = 8
  let cols = 8
  let data : Array[@fft.Complex] = Array::make(
    rows * cols,
    @fft.complex(0.0, 0.0),
  )
  let mut seed = 12345
  for i = 0; i < rows * cols; i = i + 1 {
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
    let r = (seed % 100).to_double() / 10.0
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
    let im = (seed % 100).to_double() / 10.0
    data[i] = @fft.complex(r, im)
  }
  let original = copy_complex_array(data)
  assert_true(fft_2d(data, rows, cols, false))
  assert_true(fft_2d(data, rows, cols, true))
  for i = 0; i < rows * cols; i = i + 1 {
    assert_true((@fft.re(data[i]) - @fft.re(original[i])).abs() < 1.0e-9)
    assert_true((@fft.im(data[i]) - @fft.im(original[i])).abs() < 1.0e-9)
  }
}

///|
test "fft_nd: 3-D round-trip" {
  // Shape [2, 4, 2] = 16 elements.
  let shape = [2, 4, 2]
  let total = 16
  let data : Array[@fft.Complex] = Array::make(total, @fft.complex(0.0, 0.0))
  let mut seed = 999
  for i = 0; i < total; i = i + 1 {
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
    data[i] = @fft.complex((seed % 50).to_double(), 0.0)
  }
  let original = copy_complex_array(data)
  assert_true(fft_nd(data, shape, false))
  assert_true(fft_nd(data, shape, true))
  for i = 0; i < total; i = i + 1 {
    assert_true((@fft.re(data[i]) - @fft.re(original[i])).abs() < 1.0e-9)
    assert_true(@fft.im(data[i]).abs() < 1.0e-9)
  }
}

///|
test "fft_nd: 1-D equivalence" {
  // N-D FFT with a single dimension should match 1-D FFT.
  let n = 8
  let data1 : Array[@fft.Complex] = Array::make(n, @fft.complex(0.0, 0.0))
  let data2 : Array[@fft.Complex] = Array::make(n, @fft.complex(0.0, 0.0))
  for i = 0; i < n; i = i + 1 {
    let v = @fft.complex(i.to_double(), (i * 2).to_double())
    data1[i] = v
    data2[i] = v
  }
  @fft.fft(data1, false)
  assert_true(fft_nd(data2, [n], false))
  for i = 0; i < n; i = i + 1 {
    assert_true((@fft.re(data1[i]) - @fft.re(data2[i])).abs() < 1.0e-9)
    assert_true((@fft.im(data1[i]) - @fft.im(data2[i])).abs() < 1.0e-9)
  }
}

///|
test "fft_nd: invalid shape returns false" {
  let data : Array[@fft.Complex] = Array::make(4, @fft.complex(0.0, 0.0))
  // 3 is not a power of two.
  assert_false(fft_nd(data, [3], false))
  // Size mismatch.
  assert_false(fft_nd(data, [2, 2, 2], false))
}

///|
test "fft_nd: DC of constant 3-D array" {
  // All-ones [2,2,2] array. DC = 8.
  let data : Array[@fft.Complex] = Array::make(8, @fft.complex(1.0, 0.0))
  assert_true(fft_nd(data, [2, 2, 2], false))
  assert_true((@fft.re(data[0]) - 8.0).abs() < 1.0e-9)
  for i = 1; i < 8; i = i + 1 {
    assert_true(@fft.re(data[i]).abs() < 1.0e-9)
  }
}

///|
test "convolve_2d: simple 2x2 * 2x2" {
  // a = [[1, 0], [0, 1]]  (identity-like)
  // b = [[1, 2], [3, 4]]
  // Full convolution should be 3x3.
  let a = [1.0, 0.0, 0.0, 1.0]
  let b = [1.0, 2.0, 3.0, 4.0]
  let result = convolve_2d(a, 2, 2, b, 2, 2)
  assert_true(result is Some(_))
  let r = result.unwrap()
  // Output is 3x3 = 9 elements.
  assert_eq(r.length(), 9)
  // Convolution of identity-like with b should give b padded.
  // (0,0): a[0,0]*b[0,0] = 1*1 = 1
  assert_true((r[0] - 1.0).abs() < 1.0e-9)
  // (0,1): a[0,0]*b[0,1] + a[0,1]*b[0,0] = 1*2 + 0*1 = 2
  assert_true((r[1] - 2.0).abs() < 1.0e-9)
  // (1,1): a[0,0]*b[1,1] + a[0,1]*b[1,0] + a[1,0]*b[0,1] + a[1,1]*b[0,0]
  //       = 1*4 + 0*3 + 0*2 + 1*1 = 5
  assert_true((r[4] - 5.0).abs() < 1.0e-9)
}

///|
test "convolve_2d: empty input returns None" {
  let a : Array[Double] = []
  let b = [1.0]
  assert_true(convolve_2d(a, 0, 0, b, 1, 1) is None)
}

///|
test "convolve_2d: 1x1 * 1x1" {
  let result = convolve_2d([3.0], 1, 1, [7.0], 1, 1)
  assert_true(result is Some(_))
  let r = result.unwrap()
  assert_eq(r.length(), 1)
  assert_true((r[0] - 21.0).abs() < 1.0e-9)
}

///|
test "fft_2d_forward/inverse: non-mutating wrappers" {
  let rows = 4
  let cols = 4
  let data : Array[@fft.Complex] = Array::make(
    rows * cols,
    @fft.complex(0.0, 0.0),
  )
  for r = 0; r < rows; r = r + 1 {
    for c = 0; c < cols; c = c + 1 {
      data[r * cols + c] = @fft.complex(r.to_double(), c.to_double())
    }
  }
  let original = copy_complex_array(data)
  let fwd = fft_2d_forward(data, rows, cols)
  assert_true(fwd is Some(_))
  // Original should be unmodified.
  for i = 0; i < rows * cols; i = i + 1 {
    assert_true((@fft.re(data[i]) - @fft.re(original[i])).abs() < 1.0e-9)
  }
  let fwd_data = fwd.unwrap()
  let inv = fft_2d_inverse(fwd_data, rows, cols)
  assert_true(inv is Some(_))
  let inv_data = inv.unwrap()
  for i = 0; i < rows * cols; i = i + 1 {
    assert_true((@fft.re(inv_data[i]) - @fft.re(original[i])).abs() < 1.0e-9)
    assert_true((@fft.im(inv_data[i]) - @fft.im(original[i])).abs() < 1.0e-9)
  }
}
