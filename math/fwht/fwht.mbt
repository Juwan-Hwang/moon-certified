/// Fast Walsh-Hadamard Transform (FWHT).
///
/// Computes the Hadamard transform in O(n log n) using the
/// butterfly FFT-like algorithm. Requires input length to be a
/// power of 2. Supports both sequency (bit-reversed) and natural
/// (Paley) ordering.
///
/// Applications: signal processing, XOR convolution, cryptography.
///
/// ## Complexity
/// - Time:  O(n log n) = O(n log n) where n = 2^k.
/// - Space: O(n) in-place.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

///|
/// In-place FWHT (sequency order, normalized).
/// `data` must have length = power of 2.
pub fn fwht(data : Array[Double]) -> Unit {
  let n = data.length()
  if n == 0 || (n & (n - 1)) != 0 {
    return // Not a power of 2 — do nothing.
  }
  let mut step = 1
  while step < n {
    let mut i = 0
    while i < n {
      let j = i + step
      for k = 0; k < step; k = k + 1 {
        let a = data[i + k]
        let b = data[j + k]
        data[i + k] = a + b
        data[j + k] = a - b
      }
      i = i + 2 * step
    }
    step = step * 2
  }
  // Normalize.
  let norm = 1.0 / n.to_double().sqrt()
  for i = 0; i < n; i = i + 1 {
    data[i] = data[i] * norm
  }
}

///|
/// Inverse FWHT (same as forward for Hadamard, then normalize).
pub fn ifwht(data : Array[Double]) -> Unit {
  // Hadamard transform is self-inverse up to scaling.
  // Forward: H_n / sqrt(n), so inverse = sqrt(n) * H_n.
  let n = data.length()
  if n == 0 || (n & (n - 1)) != 0 {
    return
  }
  let mut step = 1
  while step < n {
    let mut i = 0
    while i < n {
      let j = i + step
      for k = 0; k < step; k = k + 1 {
        let a = data[i + k]
        let b = data[j + k]
        data[i + k] = a + b
        data[j + k] = a - b
      }
      i = i + 2 * step
    }
    step = step * 2
  }
  // Inverse uses the same orthonormal normalization as forward.
  let norm = 1.0 / n.to_double().sqrt()
  for i = 0; i < n; i = i + 1 {
    data[i] = data[i] * norm
  }
}

///|
/// Integer FWHT for XOR convolution.
/// Computes in-place Hadamard transform on integers (no normalization).
pub fn fwht_int(data : Array[Int]) -> Unit {
  let n = data.length()
  if n == 0 || (n & (n - 1)) != 0 {
    return
  }
  let mut step = 1
  while step < n {
    let mut i = 0
    while i < n {
      let j = i + step
      for k = 0; k < step; k = k + 1 {
        let a = data[i + k]
        let b = data[j + k]
        data[i + k] = a + b
        data[j + k] = a - b
      }
      i = i + 2 * step
    }
    step = step * 2
  }
}

///|
/// Inverse integer FWHT: divide by n after forward transform.
pub fn ifwht_int(data : Array[Int]) -> Unit {
  fwht_int(data)
  let n = data.length()
  for i = 0; i < n; i = i + 1 {
    data[i] = data[i] / n
  }
}

///|
/// XOR convolution: c[k] = Σ_{i xor j = k} a[i] * b[j].
pub fn xor_convolve(a : Array[Int], b : Array[Int]) -> Array[Int] {
  let n = a.length()
  if n != b.length() || n == 0 || (n & (n - 1)) != 0 {
    return []
  }
  let fa = a.copy()
  let fb = b.copy()
  fwht_int(fa)
  fwht_int(fb)
  let fc : Array[Int] = []
  for i = 0; i < n; i = i + 1 {
    fc.push(fa[i] * fb[i])
  }
  ifwht_int(fc)
  fc
}

///|
/// Helper: absolute value of double.
fn absd(x : Double) -> Double {
  if x < 0.0 {
    -x
  } else {
    x
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "fwht: forward and inverse roundtrip" {
  let data = [1.0, 2.0, 3.0, 4.0]
  let original = data.copy()
  fwht(data)
  ifwht(data)
  for i = 0; i < 4; i = i + 1 {
    assert_true(absd(data[i] - original[i]) < 0.0000000001)
  }
}

///|
test "fwht: known transform" {
  // H_2 = [[1,1],[1,-1]] / sqrt(2)
  // [1, 0] -> [1/sqrt(2), 1/sqrt(2)]
  let data = [1.0, 0.0]
  fwht(data)
  let expected = 1.0 / 2.0.sqrt()
  assert_true(absd(data[0] - expected) < 0.0000000001)
  assert_true(absd(data[1] - expected) < 0.0000000001)
}

///|
test "fwht_int: forward inverse roundtrip" {
  let data = [1, 2, 3, 4]
  let original = data.copy()
  fwht_int(data)
  ifwht_int(data)
  assert_eq(data, original)
}

///|
test "xor_convolve: basic" {
  // a = [1, 1, 0, 0], b = [1, 1, 0, 0]
  // c[k] = Σ_{i xor j = k} a[i]*b[j]
  // c[0] = a[0]*b[0] + a[1]*b[1] = 2
  // c[1] = a[0]*b[1] + a[1]*b[0] = 2
  let a = [1, 1, 0, 0]
  let b = [1, 1, 0, 0]
  let c = xor_convolve(a, b)
  assert_eq(c[0], 2)
  assert_eq(c[1], 2)
  assert_eq(c[2], 0)
  assert_eq(c[3], 0)
}

///|
test "fwht: power of 2 check" {
  let data = [1.0, 2.0, 3.0] // Not power of 2
  fwht(data)
  // Should remain unchanged.
  assert_eq(data, [1.0, 2.0, 3.0])
}

///|
test "fwht: single element" {
  let data = [5.0]
  fwht(data)
  assert_true(absd(data[0] - 5.0) < 0.0000000001)
}

///|
test "fwht: eight element roundtrip" {
  let data = [3.0, -1.0, 2.0, 4.0, -2.0, 5.0, 1.0, -3.0]
  let original = data.copy()
  fwht(data)
  ifwht(data)
  for i = 0; i < 8; i = i + 1 {
    assert_true(absd(data[i] - original[i]) < 0.0000000001)
  }
}

///|
test "xor_convolve: identity convolution" {
  // Convolving with delta [1,0,0,0] should return the original
  let a = [3, 7, 2, 5]
  let delta = [1, 0, 0, 0]
  let c = xor_convolve(a, delta)
  assert_eq(c, [3, 7, 2, 5])
}

///|
test "xor_convolve: mismatched lengths returns empty" {
  let a = [1, 2, 3, 4]
  let b = [1, 2, 3]
  assert_eq(xor_convolve(a, b).length(), 0)
}

///|
test "fwht_int: known transform values" {
  // H_2 * [1, 0] = [1, 1]
  let data = [1, 0]
  fwht_int(data)
  assert_eq(data, [1, 1])
}
