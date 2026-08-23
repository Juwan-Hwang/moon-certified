/// Reed-Solomon Error Correction Coding.
///
/// Reed-Solomon codes are block-based error-correcting codes widely used
/// in CDs, DVDs, QR codes, and data transmission. They can correct up to
/// `t = (n - k) / 2` symbol errors in a codeword of `n` symbols containing
/// `k` data symbols.
///
/// ## Algorithm
///
/// Works over GF(2^m), the Galois field with 2^m elements. This
/// implementation uses GF(2^8) (m=8), the most common choice supporting
/// 256-element alphabets.
///
/// ### Encoding
/// The encoder treats the message as a polynomial and divides it by the
/// generator polynomial to produce parity symbols.
///
/// ### Decoding
/// The decoder uses the Berlekamp-Massey algorithm to find the error
/// locator polynomial, then Chien search to find error positions, and
/// Forney algorithm to compute error values.
///
/// ## Complexity
/// - Encode: O(n * t) where t = n - k.
/// - Decode: O(n * t) with Berlekamp-Massey.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// GF(2^8) field arithmetic
// ---------------------------------------------------------------------------

///|
/// Primitive polynomial for GF(2^8): x^8 + x^4 + x^3 + x^2 + 1 = 0x11D.
const GF_PRIMITIVE : Int = 0x11D

///|
/// GF(2^8) field: 256-element Galois field.
/// Uses log/antilog tables for fast multiplication.
pub struct GF256 {
  priv exp_table : FixedArray[Int] // exp[i] = α^i
  priv log_table : FixedArray[Int] // log[i] = log_α(i)
}

///|
/// Create a GF(2^8) field.
pub fn gf256_new() -> GF256 {
  let exp = FixedArray::make(512, 0) // doubled for easy modular arithmetic
  let log = FixedArray::make(256, 0)
  let mut x = 1
  for i = 0; i < 255; i = i + 1 {
    exp[i] = x
    log[x] = i
    x = x << 1
    if x >= 256 {
      x = x ^ GF_PRIMITIVE
    }
  }
  // Extend exp table for convenience.
  for i = 255; i < 512; i = i + 1 {
    exp[i] = exp[i - 255]
  }
  GF256::{ exp_table: exp, log_table: log }
}

///|
/// Add two field elements (XOR in GF(2^m)).
pub fn gf_add(_gf : GF256, a : Int, b : Int) -> Int {
  a ^ b
}

///|
/// Subtract two field elements (same as add in GF(2^m)).
pub fn gf_sub(gf : GF256, a : Int, b : Int) -> Int {
  gf_add(gf, a, b)
}

///|
/// Multiply two field elements.
pub fn gf_mul(gf : GF256, a : Int, b : Int) -> Int {
  if a == 0 || b == 0 {
    0
  } else {
    gf.exp_table[(gf.log_table[a] + gf.log_table[b]) % 255]
  }
}

///|
/// Divide two field elements.
/// Returns `None` if `b` is zero (division by zero is undefined in GF(256)).
pub fn gf_div(gf : GF256, a : Int, b : Int) -> Int? {
  if b == 0 {
    return None
  }
  if a == 0 {
    return Some(0)
  }
  Some(gf.exp_table[(gf.log_table[a] + 255 - gf.log_table[b]) % 255])
}

///|
/// Power: a^exp in the field.
pub fn gf_pow(gf : GF256, a : Int, exp : Int) -> Int {
  if a == 0 {
    if exp == 0 {
      1 // 0^0 = 1 by convention
    } else {
      0
    }
  } else {
    gf.exp_table[gf.log_table[a] * exp % 255]
  }
}

///|
/// Inverse of a field element.
/// Returns `None` if `a` is zero (zero has no multiplicative inverse in GF(256)).
pub fn gf_inv(gf : GF256, a : Int) -> Int? {
  if a == 0 {
    return None
  }
  Some(gf.exp_table[255 - gf.log_table[a]])
}

// ---------------------------------------------------------------------------
// Polynomial operations over GF(256)
// ---------------------------------------------------------------------------

///|
/// Polynomial multiplication (convolution).
fn poly_mul(
  gf : GF256,
  a : FixedArray[Int],
  b : FixedArray[Int],
) -> FixedArray[Int] {
  let la = a.length()
  let lb = b.length()
  let result = FixedArray::make(la + lb - 1, 0)
  for i = 0; i < la; i = i + 1 {
    for j = 0; j < lb; j = j + 1 {
      result[i + j] = result[i + j] ^ gf_mul(gf, a[i], b[j])
    }
  }
  result
}

///|
/// Polynomial division: returns (quotient, remainder).
fn poly_div(
  gf : GF256,
  dividend : FixedArray[Int],
  divisor : FixedArray[Int],
) -> (FixedArray[Int], FixedArray[Int]) {
  let la = dividend.length()
  let lb = divisor.length()
  if lb > la {
    return (FixedArray::make(0, 0), dividend)
  }
  let quot = FixedArray::make(la - lb + 1, 0)
  let rem = FixedArray::makei(la, fn(i) { dividend[i] })
  let inv_lead = match gf_inv(gf, divisor[lb - 1]) {
    Some(v) => v
    None => return (FixedArray::make(0, 0), dividend) // divisor lead is zero
  }
  for i = la - lb; i >= 0; i = i - 1 {
    let coeff = gf_mul(gf, rem[i + lb - 1], inv_lead)
    quot[i] = coeff
    // Subtract coeff * divisor(x) * x^i from rem.
    // divisor[j] is the coefficient of x^j, so coeff * divisor[j]
    // affects rem[i + j] (degree i + j).
    for j = 0; j < lb; j = j + 1 {
      rem[i + j] = gf_sub(gf, rem[i + j], gf_mul(gf, coeff, divisor[j]))
    }
  }
  // Trim remainder.
  let rem_len = if lb - 1 > 0 { lb - 1 } else { 0 }
  let rem_trimmed = FixedArray::make(rem_len, 0)
  for i = 0; i < rem_len && i < la; i = i + 1 {
    rem_trimmed[i] = rem[i]
  }
  (quot, rem_trimmed)
}

///|
/// Evaluate polynomial at point x using Horner's method.
fn poly_eval(gf : GF256, coeffs : FixedArray[Int], x : Int) -> Int {
  let mut result = 0
  for i = coeffs.length() - 1; i >= 0; i = i - 1 {
    result = gf_add(gf, gf_mul(gf, result, x), coeffs[i])
  }
  result
}

// ---------------------------------------------------------------------------
// Reed-Solomon encoder
// ---------------------------------------------------------------------------

///|
/// Build the generator polynomial for t error-correction symbols.
/// g(x) = (x - α^0)(x - α^1)...(x - α^(t-1))
/// In GF(2^m), subtraction = addition, so each factor is (x + α^i).
/// Polynomial convention: index 0 = constant term.
/// Factor (x + α^i) = [α^i, 1] (constant = α^i, x-coeff = 1).
fn build_generator(gf : GF256, t : Int) -> FixedArray[Int] {
  let mut g = FixedArray::make(1, 1) // g(x) = 1
  for i = 0; i < t; i = i + 1 {
    let factor = FixedArray::make(2, 0)
    factor[0] = gf.exp_table[i] // constant term: α^i
    factor[1] = 1 // x coefficient: 1
    g = poly_mul(gf, g, factor)
  }
  g
}

///|
/// Reed-Solomon encoder for GF(256).
///
/// Encodes `k` data symbols into `n = k + 2*t` symbols (data + parity).
///
/// # Parameters
/// - `data`: the k data symbols (each 0-255).
/// - `t`: error correction capability (number of correctable symbol errors).
///
/// # Returns
/// The full codeword (data followed by parity symbols).
pub fn rs_encode(
  gf : GF256,
  data : FixedArray[Int],
  t : Int,
) -> FixedArray[Int] {
  let k = data.length()
  let n = k + 2 * t
  // Generator polynomial.
  let gen = build_generator(gf, 2 * t)
  // Systematic encoding: C(x) = D(x)·x^(2t) + R(x)
  // where R(x) = (D(x)·x^(2t)) mod g(x).
  // In constant-first convention (index 0 = x^0), D(x)·x^(2t) places
  // data coefficients at indices 2t .. n-1, leaving indices 0 .. 2t-1
  // as zeros for the remainder.
  let msg = FixedArray::make(n, 0)
  for i = 0; i < k; i = i + 1 {
    msg[2 * t + i] = data[i]
  }
  // Divide msg by gen; remainder is the parity (degree < 2t).
  let (_, rem) = poly_div(gf, msg, gen)
  // Codeword = msg XOR rem (in GF(2^m), subtraction = XOR).
  // Result: parity at indices 0..2t-1, data at indices 2t..n-1.
  let codeword = FixedArray::make(n, 0)
  for i = 0; i < rem.length() && i < n; i = i + 1 {
    codeword[i] = rem[i]
  }
  for i = 0; i < k; i = i + 1 {
    codeword[2 * t + i] = data[i]
  }
  codeword
}

// ---------------------------------------------------------------------------
// Reed-Solomon decoder (Berlekamp-Massey + Chien + Forney)
// ---------------------------------------------------------------------------

///|
/// Reed-Solomon decoder for GF(256).
///
/// Attempts to decode the received codeword, correcting up to `t` symbol
/// errors.
///
/// # Parameters
/// - `received`: the received codeword (n symbols).
/// - `k`: number of original data symbols.
/// - `t`: error correction capability.
///
/// # Returns
/// `Some(decoded_data)` if decoding succeeds, `None` if too many errors.
pub fn rs_decode(
  gf : GF256,
  received : FixedArray[Int],
  k : Int,
  t : Int,
) -> FixedArray[Int]? {
  let n = received.length()
  let nsym = 2 * t // number of parity symbols
  // Step 1: Compute syndromes.
  // S_i = R(α^i) for i = 0, 1, ..., nsym-1
  let syndromes = FixedArray::make(nsym, 0)
  let mut has_errors = false
  for i = 0; i < nsym; i = i + 1 {
    let x = gf.exp_table[i]
    let s = poly_eval(gf, received, x)
    syndromes[i] = s
    if s != 0 {
      has_errors = true
    }
  }
  if !has_errors {
    // No errors. Data is at indices 2t..n-1 (high-degree positions).
    return Some(FixedArray::makei(k, fn(i) { received[2 * t + i] }))
  }
  // Step 2: Berlekamp-Massey to find error locator polynomial.
  let err_loc = berlekamp_massey(gf, syndromes)
  // Step 3: Chien search to find error positions.
  // Position i has an error iff Λ(α^(-i)) = 0.
  let error_positions : Array[Int] = []
  for i = 0; i < n; i = i + 1 {
    // α^(-i) = α^(255-i) mod 255
    let x = gf.exp_table[(255 - i) % 255]
    if poly_eval(gf, err_loc, x) == 0 {
      error_positions.push(i)
    }
  }
  let num_errors = error_positions.length()
  if num_errors > t {
    return None // Too many errors to correct
  }
  if num_errors == 0 {
    // Found no error positions but syndromes are non-zero.
    // This shouldn't happen if the locator polynomial is correct.
    return None
  }
  // Step 4: Forney algorithm to find error values.
  // Compute error evaluator polynomial: ω(x) = S(x) * Λ(x) mod x^nsym
  // First, build syndrome polynomial S(x) = S_0 + S_1*x + ... + S_(nsym-1)*x^(nsym-1)
  let s_poly = FixedArray::makei(nsym, fn(i) { syndromes[i] })
  // ω(x) = S(x) * Λ(x) mod x^nsym
  let omega_full = poly_mul(gf, s_poly, err_loc)
  let omega_len = if nsym < omega_full.length() {
    nsym
  } else {
    omega_full.length()
  }
  let omega = FixedArray::make(omega_len, 0)
  for i = 0; i < omega_len; i = i + 1 {
    omega[i] = omega_full[i]
  }
  // Compute error magnitudes using Forney.
  let corrected = FixedArray::makei(n, fn(i) { received[i] })
  let err_len = err_loc.length()
  for idx = 0; idx < num_errors; idx = idx + 1 {
    let pos = error_positions[idx]
    let xi_inv = gf.exp_table[(255 - pos) % 255] // α^(-pos) = X_j⁻¹
    // ω(X_j⁻¹) and Λ'(X_j⁻¹)
    let omega_val = poly_eval(gf, omega, xi_inv)
    // Derivative of Λ(x): in GF(2^m), formal derivative keeps only odd-degree
    // terms (even-degree terms vanish since 2 = 0). Shift them down by one.
    let err_derive = FixedArray::make(err_len - 1, 0)
    for j = 1; j < err_len; j = j + 1 {
      if j % 2 == 1 {
        err_derive[j - 1] = err_loc[j]
      }
    }
    let lambda_prime_val = poly_eval(gf, err_derive, xi_inv)
    if lambda_prime_val == 0 {
      return None
    }
    // Forney: e_j = X_j · ω(X_j⁻¹) / Λ'(X_j⁻¹), where X_j = α^(pos).
    // The X_j factor is required because ω(x) = S(x)·Λ(x) mod x^(2t)
    // evaluates to e_j · ∏_{l≠j}(1 - X_l·x) at x = X_j⁻¹, while Λ'(X_j⁻¹)
    // = X_j · ∏_{l≠j}(1 - X_l/X_j). The X_j cancels in the denominator.
    let x_j = gf.exp_table[pos % 255]
    let magnitude = match
      gf_div(gf, gf_mul(gf, x_j, omega_val), lambda_prime_val) {
      Some(m) => m
      None => return None // Should not happen if lambda_prime_val != 0
    }
    corrected[pos] = corrected[pos] ^ magnitude
  }
  // Verify correction by checking syndromes.
  for i = 0; i < nsym; i = i + 1 {
    let x = gf.exp_table[i]
    let s = poly_eval(gf, corrected, x)
    if s != 0 {
      return None // Correction failed
    }
  }
  Some(FixedArray::makei(k, fn(i) { corrected[2 * t + i] }))
}

///|
/// Berlekamp-Massey algorithm to find the error locator polynomial.
///
/// Standard implementation with explicit degree L tracking.
/// Polynomial convention: index 0 = constant term.
/// Λ(x) = Λ_0 + Λ_1·x + ... + Λ_L·x^L, where Λ_0 = 1.
fn berlekamp_massey(gf : GF256, syndromes : FixedArray[Int]) -> FixedArray[Int] {
  let nsym = syndromes.length()
  // Error locator polynomial Λ(x), index 0 = constant.
  let err_loc = FixedArray::make(nsym + 1, 0)
  err_loc[0] = 1
  // Previous Λ (B(x)), used for updates.
  let old_loc = FixedArray::make(nsym + 1, 0)
  old_loc[0] = 1
  let mut l = 0 // current degree of Λ
  let mut m = 1 // steps since last L update
  let mut b = 1 // last nonzero discrepancy
  for n_step = 0; n_step < nsym; n_step = n_step + 1 {
    // Compute discrepancy: Δ = S_n + Σ_{i=1}^{L} Λ_i · S_{n-i}
    let mut delta = syndromes[n_step]
    for i = 1; i <= l; i = i + 1 {
      if err_loc[i] != 0 {
        delta = delta ^ gf_mul(gf, err_loc[i], syndromes[n_step - i])
      }
    }
    if delta == 0 {
      m = m + 1
    } else if 2 * l <= n_step {
      // Copy current Λ to old_loc before updating.
      let temp = FixedArray::makei(nsym + 1, fn(i) { err_loc[i] })
      let coeff = match gf_div(gf, delta, b) {
        Some(c) => c
        None => 0 // b != 0 is guaranteed (set from non-zero delta)
      }
      // Λ(x) = Λ(x) - (Δ/b) · x^m · B(x)
      for i = 0; i <= nsym - m; i = i + 1 {
        err_loc[i + m] = err_loc[i + m] ^ gf_mul(gf, coeff, old_loc[i])
      }
      l = n_step + 1 - l
      for i = 0; i <= nsym; i = i + 1 {
        old_loc[i] = temp[i]
      }
      b = delta
      m = 1
    } else {
      let coeff = match gf_div(gf, delta, b) {
        Some(c) => c
        None => 0 // b != 0 is guaranteed (set from non-zero delta)
      }
      for i = 0; i <= nsym - m; i = i + 1 {
        err_loc[i + m] = err_loc[i + m] ^ gf_mul(gf, coeff, old_loc[i])
      }
      m = m + 1
    }
  }
  // Trim to actual degree L (or less if trailing zeros).
  let mut degree = l
  while degree > 0 && err_loc[degree] == 0 {
    degree = degree - 1
  }
  FixedArray::makei(degree + 1, fn(i) { err_loc[i] })
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "gf256: basic operations" {
  let gf = gf256_new()
  assert_eq(gf_add(gf, 5, 3), 6) // 5 XOR 3 = 6
  assert_eq(gf_mul(gf, 0, 100), 0)
  assert_eq(gf_mul(gf, 1, 100), 100)
  // 2 * 3 in GF(256) with primitive 0x11D:
  // log(2) = 1, log(3) = 25, so 2*3 = exp(26) = ?
  let p = gf_mul(gf, 2, 3)
  assert_true(p > 0 && p < 256)
  // Verify: 2 * inverse(2) = 1
  match gf_inv(gf, 2) {
    Some(inv) => assert_eq(gf_mul(gf, 2, inv), 1)
    None => assert_true(false) // Should not happen for non-zero input
  }
}

///|
test "rs: encode and decode no errors" {
  let gf = gf256_new()
  let data = FixedArray::make(4, 0)
  data[0] = 32
  data[1] = 64
  data[2] = 96
  data[3] = 128
  let t = 2 // correct up to 2 errors
  let codeword = rs_encode(gf, data, t)
  assert_eq(codeword.length(), 4 + 2 * t)
  // Decode with no errors.
  match rs_decode(gf, codeword, 4, t) {
    Some(decoded) =>
      for i = 0; i < 4; i = i + 1 {
        assert_eq(decoded[i], data[i])
      }
    None => assert_true(false)
  }
}

///|
test "rs: correct single error" {
  let gf = gf256_new()
  let data = FixedArray::make(4, 0)
  data[0] = 32
  data[1] = 64
  data[2] = 96
  data[3] = 128
  let t = 2
  let codeword = rs_encode(gf, data, t)
  // Introduce one error.
  codeword[2] = codeword[2] ^ 0x55
  let decoded = @test_utils.expect_some(
    rs_decode(gf, codeword, 4, t),
    "rs: expected successful decode of single-error codeword",
  )
  for i = 0; i < 4; i = i + 1 {
    assert_eq(decoded[i], data[i])
  }
}

///|
test "rs: correct two errors" {
  let gf = gf256_new()
  let data = FixedArray::make(4, 0)
  data[0] = 10
  data[1] = 20
  data[2] = 30
  data[3] = 40
  let t = 2
  let codeword = rs_encode(gf, data, t)
  // Introduce two errors.
  codeword[1] = codeword[1] ^ 0x33
  codeword[5] = codeword[5] ^ 0x77
  let decoded = @test_utils.expect_some(
    rs_decode(gf, codeword, 4, t),
    "rs: expected successful decode of two-error codeword",
  )
  for i = 0; i < 4; i = i + 1 {
    assert_eq(decoded[i], data[i])
  }
}

///|
test "rs: detect too many errors" {
  let gf = gf256_new()
  let data = FixedArray::make(4, 0)
  data[0] = 10
  data[1] = 20
  data[2] = 30
  data[3] = 40
  let t = 1 // only 1 error correctable
  let codeword = rs_encode(gf, data, t)
  // Introduce 2 errors (beyond correction capability).
  codeword[0] = codeword[0] ^ 0x11
  codeword[1] = codeword[1] ^ 0x22
  // Should return None (cannot correct).
  let result = rs_decode(gf, codeword, 4, t)
  assert_true(result is None)
}

///|
test "gf256: division and inverse" {
  let gf = gf256_new()
  // a / b * b = a for non-zero a, b
  for v = 1; v < 10; v = v + 1 {
    match gf_div(gf, v, 3) {
      Some(q) => assert_eq(gf_mul(gf, q, 3), v)
      None => assert_true(false)
    }
  }
  // Division by zero returns None
  assert_true(gf_div(gf, 5, 0) is None)
  // Inverse of zero returns None
  assert_true(gf_inv(gf, 0) is None)
}

///|
test "gf256: power and repeated multiplication" {
  let gf = gf256_new()
  // a^3 = a * a * a
  for a = 1; a < 8; a = a + 1 {
    let powed = gf_pow(gf, a, 3)
    let manual = gf_mul(gf, gf_mul(gf, a, a), a)
    assert_eq(powed, manual)
  }
  // a^0 = 1 for non-zero a
  assert_eq(gf_pow(gf, 7, 0), 1)
}

///|
test "rs: single data symbol" {
  let gf = gf256_new()
  let data = FixedArray::make(1, 0)
  data[0] = 99
  let t = 1
  let codeword = rs_encode(gf, data, t)
  assert_eq(codeword.length(), 1 + 2 * t)
  match rs_decode(gf, codeword, 1, t) {
    Some(decoded) => assert_eq(decoded[0], 99)
    None => assert_true(false)
  }
}

///|
test "rs: correct error in data region" {
  let gf = gf256_new()
  let data = FixedArray::make(5, 0)
  data[0] = 0x12
  data[1] = 0x34
  data[2] = 0x56
  data[3] = 0x78
  data[4] = 0x9A
  let t = 3
  let codeword = rs_encode(gf, data, t)
  // Introduce one error in the data region (high index)
  let data_pos = 2 * t + 2
  codeword[data_pos] = codeword[data_pos] ^ 0xAB
  match rs_decode(gf, codeword, 5, t) {
    Some(decoded) =>
      for i = 0; i < 5; i = i + 1 {
        assert_eq(decoded[i], data[i])
      }
    None => assert_true(false)
  }
}

///|
test "rs: correct maximum errors" {
  let gf = gf256_new()
  let data = FixedArray::make(4, 0)
  data[0] = 0x01
  data[1] = 0x02
  data[2] = 0x03
  data[3] = 0x04
  let t = 2 // can correct up to 2 errors
  let codeword = rs_encode(gf, data, t)
  // Introduce exactly t=2 errors
  codeword[0] = codeword[0] ^ 0x10
  codeword[3] = codeword[3] ^ 0x20
  match rs_decode(gf, codeword, 4, t) {
    Some(decoded) =>
      for i = 0; i < 4; i = i + 1 {
        assert_eq(decoded[i], data[i])
      }
    None => assert_true(false)
  }
}
