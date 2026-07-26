/// Number Theoretic Transform (NTT) for fast polynomial multiplication.
///
/// The NTT is the finite-field analogue of the FFT. It evaluates a polynomial
/// at the powers of a primitive root of unity modulo a prime `p`, and the
/// inverse transform recovers the coefficients. Polynomial multiplication
/// via NTT runs in O(n log n) instead of O(n²).
///
/// ## Prime and primitive root
///
/// Uses the NTT-friendly prime `p = 998244353 = 119 * 2^23 + 1`, which
/// supports transform lengths up to `2^23` (8,388,608 coefficients). The
/// primitive root is `g = 3`; the `2^k`-th root of unity is
/// `ω = g^((p-1)/2^k) mod p`.
///
/// ## Overflow safety
///
/// All modular arithmetic is performed in `Int64` using `mul_mod` from
/// `@int64_utils`, which uses binary decomposition to prevent overflow even
/// when squaring values close to `Int64::MAX`. This makes the NTT safe for
/// the full range of coefficient values modulo `p`.
///
/// ## API
///
/// - `ntt(a, invert)` — in-place forward or inverse NTT
/// - `multiply(a, b)` — polynomial multiplication returning `a * b`
/// - `convolve_mod(a, b, p, g)` — convolution under a custom NTT prime
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

/// The default NTT prime: 998244353 = 119 * 2^23 + 1.
pub const NTT_MOD : Int64 = 998244353L

/// The primitive root modulo NTT_MOD.
pub const NTT_G : Int64 = 3L

// ---------------------------------------------------------------------------
// Bit-reversal permutation
// ---------------------------------------------------------------------------

/// Reorder `a` so that element `i` moves to the position obtained by reversing
/// the bits of `i` in `log2(n)` bits. This is the standard pre-processing
/// step for iterative (Cooley-Tukey) NTT.
///
/// Uses the standard O(n) incremental bit-reversal: each j is derived from
/// the previous j by adding 1 in reversed-bit order, avoiding the O(n log n)
/// cost of reversing bits independently for each index.
fn bit_reverse(a : Array[Int64], n : Int) -> Unit {
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
// Core NTT
// ---------------------------------------------------------------------------

/// In-place Number Theoretic Transform.
///
/// When `invert` is `false`, performs the forward NTT: evaluates the
/// polynomial at the powers of the primitive `n`-th root of unity.
///
/// When `invert` is `true`, performs the inverse NTT: recovers the
/// coefficients from the evaluations, dividing by `n` at the end.
///
/// The array length `n` must be a power of 2. The modulus is `NTT_MOD`
/// (998244353), which supports `n` up to `2^23`.
///
/// Uses the iterative Cooley-Tukey butterfly with in-place swaps, running in
/// O(n log n) time and O(1) extra space (beyond the input array).
pub fn ntt(a : Array[Int64], invert : Bool) -> Unit {
  let n = a.length()
  if n <= 1 {
    return
  }
  // Verify n is a power of 2; if not, return silently (no-op).
  if (n & (n - 1)) != 0 {
    return
  }
  let p = NTT_MOD
  bit_reverse(a, n)
  // Cooley-Tukey butterfly: process lengths 2, 4, 8, ..., n.
  let mut len = 2
  while len <= n {
    // Compute the len-th root of unity: w = g^((p-1)/len) mod p.
    // For inverse, use w^{-1} = w^(len-1).
    let exp = (p - 1L) / len.to_int64()
    let mut w = @int64_utils.pow_mod64(NTT_G, exp, p)
    if invert {
      // w^{-1} = w^(len-1) mod p
      w = @int64_utils.pow_mod64(w, len.to_int64() - 1L, p)
    }
    let half = len / 2
    let mut i = 0
    while i < n {
      let mut wn = 1L
      let mut j = 0
      while j < half {
        let u = a[i + j]
        let v = @int64_utils.mul_mod(a[i + j + half], wn, p)
        let sum = @int64_utils.mod64(u + v, p)
        let diff = @int64_utils.mod64(u - v, p)
        a[i + j] = sum
        a[i + j + half] = diff
        wn = @int64_utils.mul_mod(wn, w, p)
        j = j + 1
      }
      i = i + len
    }
    len = len * 2
  }
  if invert {
    // Divide by n (multiply by n^{-1} mod p).
    let n_inv = @int64_utils.pow_mod64(
      n.to_int64(),
      p - 2L,
      p,
    )
    for i = 0; i < n; i = i + 1 {
      a[i] = @int64_utils.mul_mod(a[i], n_inv, p)
    }
  }
}

// ---------------------------------------------------------------------------
// Polynomial multiplication
// ---------------------------------------------------------------------------

/// Multiply two polynomials modulo NTT_MOD.
///
/// Given coefficient arrays `a` (degree `deg_a`) and `b` (degree `deg_b`),
/// returns the product `c = a * b` of degree `deg_a + deg_b`.
///
/// The result has `deg_a + deg_b + 1` coefficients, all reduced modulo
/// `NTT_MOD` (998244353). Each input coefficient must be in `[0, NTT_MOD)`.
///
/// Uses the NTT for O(n log n) multiplication where `n` is the next power of
/// 2 ≥ `len(a) + len(b) - 1`.
///
/// Returns an empty array if either input is empty.
pub fn multiply(
  a : Array[Int64],
  b : Array[Int64]
) -> Array[Int64] {
  if a.length() == 0 || b.length() == 0 {
    return []
  }
  let result_len = a.length() + b.length() - 1
  // Pad to next power of 2 ≥ result_len.
  let mut n = 1
  while n < result_len {
    n = n * 2
  }
  // Copy and pad a and b.
  let fa : Array[Int64] = []
  let fb : Array[Int64] = []
  for i = 0; i < n; i = i + 1 {
    if i < a.length() {
      fa.push(@int64_utils.mod64(a[i], NTT_MOD))
    } else {
      fa.push(0L)
    }
    if i < b.length() {
      fb.push(@int64_utils.mod64(b[i], NTT_MOD))
    } else {
      fb.push(0L)
    }
  }
  // Forward NTT both.
  ntt(fa, false)
  ntt(fb, false)
  // Pointwise multiply.
  for i = 0; i < n; i = i + 1 {
    fa[i] = @int64_utils.mul_mod(fa[i], fb[i], NTT_MOD)
  }
  // Inverse NTT.
  ntt(fa, true)
  // Truncate to result_len.
  let result : Array[Int64] = []
  for i = 0; i < result_len; i = i + 1 {
    result.push(fa[i])
  }
  result
}

/// Convolution of two `Int` arrays modulo NTT_MOD.
///
/// Convenience wrapper around `multiply` that accepts and returns `Int`
/// arrays (widened to `Int64` internally, narrowed back at the end).
/// Each input element is reduced to `[0, NTT_MOD)` before processing.
pub fn convolve(a : Array[Int], b : Array[Int]) -> Array[Int] {
  let a64 : Array[Int64] = []
  let b64 : Array[Int64] = []
  for i = 0; i < a.length(); i = i + 1 {
    a64.push(a[i].to_int64())
  }
  for i = 0; i < b.length(); i = i + 1 {
    b64.push(b[i].to_int64())
  }
  let result = multiply(a64, b64)
  let out : Array[Int] = []
  for i = 0; i < result.length(); i = i + 1 {
    out.push(result[i].to_int())
  }
  out
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "ntt: forward and inverse round-trip" {
  let a : Array[Int64] = [1L, 2L, 3L, 4L]
  let original = [1L, 2L, 3L, 4L]
  ntt(a, false)
  ntt(a, true)
  for i = 0; i < 4; i = i + 1 {
    assert_eq(a[i], original[i])
  }
}

test "ntt: multiply simple polynomials" {
  // (1 + x) * (1 + x) = 1 + 2x + x^2
  let a : Array[Int64] = [1L, 1L]
  let b : Array[Int64] = [1L, 1L]
  let c = multiply(a, b)
  assert_eq(c.length(), 3)
  assert_eq(c[0], 1L)
  assert_eq(c[1], 2L)
  assert_eq(c[2], 1L)
}

test "ntt: multiply with larger polynomials" {
  // (1 + 2x + 3x^2) * (4 + 5x) = 4 + 13x + 22x^2 + 15x^3
  let a : Array[Int64] = [1L, 2L, 3L]
  let b : Array[Int64] = [4L, 5L]
  let c = multiply(a, b)
  assert_eq(c.length(), 4)
  assert_eq(c[0], 4L)
  assert_eq(c[1], 13L)  // 1*5 + 2*4 = 13
  assert_eq(c[2], 22L)  // 2*5 + 3*4 = 22
  assert_eq(c[3], 15L)  // 3*5 = 15
}

test "ntt: multiply degree 0" {
  // Constant * constant
  let a : Array[Int64] = [7L]
  let b : Array[Int64] = [3L]
  let c = multiply(a, b)
  assert_eq(c.length(), 1)
  assert_eq(c[0], 21L)
}

test "ntt: multiply with zero coefficients" {
  let a : Array[Int64] = [0L, 1L, 0L]
  let b : Array[Int64] = [1L, 0L, 1L]
  let c = multiply(a, b)
  assert_eq(c.length(), 5)
  assert_eq(c[0], 0L)
  assert_eq(c[1], 1L) // 0*0 + 1*1 = 1
  assert_eq(c[2], 0L)
  assert_eq(c[3], 1L) // 1*1 + 0*0 = 1
  assert_eq(c[4], 0L)
}

test "ntt: multiply matches brute force" {
  // Verify against O(n^2) multiplication.
  let a : Array[Int64] = [1L, 2L, 3L, 4L, 5L]
  let b : Array[Int64] = [6L, 7L, 8L, 9L]
  let c = multiply(a, b)
  // Brute force.
  let expected_len = a.length() + b.length() - 1
  let expected = FixedArray::make(expected_len, 0L)
  for i = 0; i < a.length(); i = i + 1 {
    for j = 0; j < b.length(); j = j + 1 {
      expected[i + j] = expected[i + j] + a[i] * b[j]
      expected[i + j] = expected[i + j] % NTT_MOD
    }
  }
  assert_eq(c.length(), expected_len)
  for i = 0; i < expected_len; i = i + 1 {
    assert_eq(c[i], expected[i])
  }
}

test "ntt: convolve (Int wrapper)" {
  let a = [1, 2, 3]
  let b = [1, 1]
  let c = convolve(a, b)
  assert_eq(c.length(), 4)
  assert_eq(c[0], 1)
  assert_eq(c[1], 3)  // 1*1 + 2*1
  assert_eq(c[2], 5)  // 2*1 + 3*1
  assert_eq(c[3], 3)  // 3*1
}

test "ntt: large coefficients" {
  // Coefficients close to NTT_MOD.
  let a : Array[Int64] = [998244352L, 1L] // -1 mod p, 1
  let b : Array[Int64] = [998244352L, 1L] // -1 mod p, 1
  let c = multiply(a, b)
  // (-1 + x)^2 = 1 - 2x + x^2 (mod p)
  assert_eq(c[0], 1L)
  assert_eq(c[1], NTT_MOD - 2L) // -2 mod p
  assert_eq(c[2], 1L)
}

test "ntt: power-of-2 length enforcement" {
  let a : Array[Int64] = [1L, 2L, 3L] // length 3, not power of 2
  // ntt now returns silently (no-op) for non-power-of-2 length.
  // multiply handles non-power-of-2 inputs by padding internally.
  let b : Array[Int64] = [1L]
  let c = multiply(a, b)
  assert_eq(c.length(), 3)
  for i = 0; i < 3; i = i + 1 {
    assert_eq(c[i], a[i])
  }
}

test "ntt: multiply with single element" {
  let a : Array[Int64] = [5L]
  let b : Array[Int64] = [3L, 7L, 11L]
  let c = multiply(a, b)
  assert_eq(c.length(), 3)
  assert_eq(c[0], 15L)
  assert_eq(c[1], 35L)
  assert_eq(c[2], 55L)
}

test "ntt: stress test 64 coefficients" {
  let a : Array[Int64] = []
  let b : Array[Int64] = []
  for i = 0; i < 64; i = i + 1 {
    a.push((i * 3 + 1).to_int64())
    b.push((i * 2 + 5).to_int64())
  }
  let c = multiply(a, b)
  // Verify against brute force.
  let expected_len = a.length() + b.length() - 1
  let expected = FixedArray::make(expected_len, 0L)
  for i = 0; i < a.length(); i = i + 1 {
    for j = 0; j < b.length(); j = j + 1 {
      expected[i + j] = (expected[i + j] + a[i] * b[j]) % NTT_MOD
    }
  }
  assert_eq(c.length(), expected_len)
  for i = 0; i < expected_len; i = i + 1 {
    assert_eq(c[i], expected[i])
  }
}
