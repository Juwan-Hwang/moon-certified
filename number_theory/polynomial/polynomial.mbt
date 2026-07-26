/// Polynomial operations modulo NTT_MOD (998244353).
///
/// Supports polynomial inverse, square root, logarithm, and exponential
/// using Newton's method, all via NTT-based multiplication.
///
/// ## Algorithms
///
/// All operations use **Newton's iteration**: given a polynomial `f(x)`,
/// to compute `g(x)` satisfying `F(g) = 0`, iterate
/// `g ← g - F(g) / F'(g)` (where `/` uses polynomial division). Each
/// iteration doubles the precision, so the total cost is O(n log n).
///
/// - **Inverse** `h = f^{-1}`: `f·h ≡ 1`. Newton: `h ← 2h - f·h²`.
/// - **Square root** `h = sqrt(f)`: `h² ≡ f`. Newton: `h ← (h + f/h) / 2`.
/// - **Logarithm** `ln(f)`: `ln(f) = f'/f`. Requires `f(0) = 1`.
/// - **Exponential** `exp(f)`: `g = exp(f)`. Newton: `g ← g·(1 - ln(g) + f)`.
///   Requires `f(0) = 0`.
///
/// ## Complexity
///
/// Each operation: O(n log n) via NTT.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const MOD : Int64 = 998244353L

/// Pad a polynomial to exactly `n` elements with zeros.
fn pad(a : Array[Int64], n : Int) -> Array[Int64] {
  let result : Array[Int64] = []
  for i = 0; i < n; i = i + 1 {
    if i < a.length() {
      result.push(a[i])
    } else {
      result.push(0L)
    }
  }
  result
}

/// Modular inverse of a single element `a` mod MOD.
fn mod_inv(a : Int64) -> Int64 {
  @int64_utils.pow_mod64(a, MOD - 2L, MOD)
}

/// Polynomial multiplication mod MOD via NTT.
fn poly_mul(a : Array[Int64], b : Array[Int64]) -> Array[Int64] {
  @ntt.multiply(a, b)
}

// ---------------------------------------------------------------------------
// Polynomial inverse
// ---------------------------------------------------------------------------

/// Compute `h = f^{-1} mod x^n`, i.e., `f · h ≡ 1 (mod x^n)`.
///
/// Requires `f[0] ≠ 0` (otherwise the inverse doesn't exist).
///
/// # Algorithm
/// Newton's method: start with `h₀ = f[0]^{-1}`, then
/// `h ← 2h - f·h² (mod x^(2k))`, doubling precision each step.
///
/// # Complexity
/// O(n log n).
pub fn poly_inv(f : Array[Int64], n : Int) -> Array[Int64] {
  if n == 0 {
    return []
  }
  if f.length() == 0 || f[0] == 0L {
    return []
  }
  // Start with h = f[0]^{-1} mod x.
  let mut h : Array[Int64] = [mod_inv(f[0])]
  let mut k = 1
  while k < n {
    let next_k = k * 2
    if next_k > n {
      // Final step: pad to n.
    }
    // h = 2h - f * h^2 mod x^next_k
    // First, compute f_trunc * h^2.
    let f_pad = pad(f, next_k)
    // Compute h^2.
    let h_pad = pad(h, next_k)
    let h_sq = poly_mul(h_pad, h_pad)
    // Truncate h_sq to next_k.
    let h_sq_trunc = pad(h_sq, next_k)
    // f * h^2
    let fh2 = poly_mul(f_pad, h_sq_trunc)
    let fh2_trunc = pad(fh2, next_k)
    // h = 2h - f*h^2
    let new_h : Array[Int64] = []
    for i = 0; i < next_k; i = i + 1 {
      let val = @int64_utils.mod64(
        2L * h_pad[i] - (if i < fh2_trunc.length() { fh2_trunc[i] } else { 0L }),
        MOD,
      )
      new_h.push(val)
    }
    h = new_h
    k = next_k
  }
  // Truncate to n.
  pad(h, n)
}

// ---------------------------------------------------------------------------
// Polynomial square root
// ---------------------------------------------------------------------------

/// Compute `h = sqrt(f) mod x^n`, i.e., `h² ≡ f (mod x^n)`.
///
/// Requires `f[0]` to be a quadratic residue mod MOD. Uses Tonelli-Shanks
/// for the initial square root of `f[0]`.
///
/// # Algorithm
/// Newton's method: `h ← (h + f/h) / 2 mod x^(2k)`.
///
/// # Complexity
/// O(n log n).
pub fn poly_sqrt(f : Array[Int64], n : Int) -> Array[Int64] {
  if n == 0 {
    return []
  }
  if f.length() == 0 {
    return pad([], n)
  }
  // Compute sqrt(f[0]) mod MOD using the quadratic residue module.
  let c0 = @int64_utils.mod64(f[0], MOD)
  let sqrt_c0 = sqrt_mod_simple(c0)
  match sqrt_c0 {
    None => return []
    Some(s) => {
      let inv2 = mod_inv(2L)
      let mut h : Array[Int64] = [s]
      let mut k = 1
      while k < n {
        let next_k = k * 2
        let f_pad = pad(f, next_k)
        let h_pad = pad(h, next_k)
        // h_inv = poly_inv(h, next_k)
        let h_inv = poly_inv(h_pad, next_k)
        // f / h = f * h_inv
        let fh = poly_mul(f_pad, h_inv)
        let fh_trunc = pad(fh, next_k)
        // h = (h + f/h) / 2
        let new_h : Array[Int64] = []
        for i = 0; i < next_k; i = i + 1 {
          let val = @int64_utils.mod64(
            @int64_utils.mod64(h_pad[i] + fh_trunc[i], MOD) * inv2,
            MOD,
          )
          new_h.push(val)
        }
        h = new_h
        k = next_k
      }
      pad(h, n)
    }
  }
}

/// Simple modular square root using Tonelli-Shanks.
/// Returns None if a is not a QR.
fn sqrt_mod_simple(a : Int64) -> Int64? {
  // Delegate to the quadratic_residue package logic inline.
  // For MOD = 998244353 ≡ 1 (mod 4), we need full Tonelli-Shanks.
  // Since this package depends on int64_utils, we implement it inline.
  let a_mod = @int64_utils.mod64(a, MOD)
  if a_mod == 0L {
    return Some(0L)
  }
  // Euler's criterion
  let r = @int64_utils.pow_mod64(a_mod, (MOD - 1L) / 2L, MOD)
  if r != 1L {
    return None
  }
  // MOD = 998244353 = 119 * 2^23 + 1, so MOD ≡ 1 (mod 4).
  // Write MOD-1 = Q * 2^S.
  let mut q = MOD - 1L
  let mut s = 0
  while q % 2L == 0L {
    q = q / 2L
    s = s + 1
  }
  // Find non-residue.
  let mut z = 2L
  while @int64_utils.pow_mod64(z, (MOD - 1L) / 2L, MOD) != MOD - 1L {
    z = z + 1L
  }
  let mut m = s
  let mut c = @int64_utils.pow_mod64(z, q, MOD)
  let mut t = @int64_utils.pow_mod64(a_mod, q, MOD)
  let mut r_val = @int64_utils.pow_mod64(a_mod, (q + 1L) / 2L, MOD)
  while t != 1L {
    // Find the least i >= 1 such that t^(2^i) = 1.
    let mut i = 0
    let mut tmp = t
    while tmp != 1L {
      tmp = @int64_utils.mul_mod(tmp, tmp, MOD)
      i = i + 1
    }
    // b = c^(2^(m - i - 1)): square c exactly (m - i - 1) times.
    let mut b = c
    for j = 0; j < m - i - 1; j = j + 1 {
      b = @int64_utils.mul_mod(b, b, MOD)
    }
    r_val = @int64_utils.mul_mod(r_val, b, MOD)
    t = @int64_utils.mul_mod(t, @int64_utils.mul_mod(b, b, MOD), MOD)
    c = @int64_utils.mul_mod(b, b, MOD)
    m = i
  }
  Some(r_val)
}

// ---------------------------------------------------------------------------
// Polynomial logarithm
// ---------------------------------------------------------------------------

/// Compute `h = ln(f) mod x^n`.
///
/// Requires `f[0] = 1` (otherwise the logarithm doesn't exist as a
/// power series).
///
/// # Algorithm
/// `ln(f) = ∫ (f' / f) dx`, where `f'` is the formal derivative.
///
/// # Complexity
/// O(n log n).
pub fn poly_log(f : Array[Int64], n : Int) -> Array[Int64] {
  if n == 0 {
    return []
  }
  let f_pad = pad(f, n)
  if f_pad[0] != 1L {
    return []
  }
  // Compute f' (derivative).
  let f_prime : Array[Int64] = [0L]
  for i = 1; i < n; i = i + 1 {
    f_prime.push(@int64_utils.mul_mod(f_pad[i], i.to_int64(), MOD))
  }
  // Compute f^{-1}.
  let f_inv = poly_inv(f_pad, n)
  // Compute f' * f^{-1}.
  let product = poly_mul(f_prime, f_inv)
  // Truncate and integrate.
  let result : Array[Int64] = [0L]
  for i = 1; i < n; i = i + 1 {
    // ∫ product[i] / i = product[i] * inv(i)
    let val = if i < product.length() {
      @int64_utils.mul_mod(product[i], mod_inv(i.to_int64()), MOD)
    } else {
      0L
    }
    result.push(val)
  }
  result
}

// ---------------------------------------------------------------------------
// Polynomial exponential
// ---------------------------------------------------------------------------

/// Compute `h = exp(f) mod x^n`.
///
/// Requires `f[0] = 0` (otherwise the exponential doesn't exist as a
/// power series with integer coefficients).
///
/// # Algorithm
/// Newton's method: `h ← h · (1 - ln(h) + f) mod x^(2k)`.
///
/// # Complexity
/// O(n log n).
pub fn poly_exp(f : Array[Int64], n : Int) -> Array[Int64] {
  if n == 0 {
    return []
  }
  let f_pad = pad(f, n)
  if f_pad[0] != 0L {
    return [1L]
  }
  let mut h : Array[Int64] = [1L] // exp(0) = 1
  let mut k = 1
  while k < n {
    let next_k = k * 2
    let f_trunc = pad(f_pad, next_k)
    let h_pad = pad(h, next_k)
    // Compute ln(h) mod x^next_k.
    let ln_h = poly_log(h_pad, next_k)
    // Compute 1 - ln(h) + f.
    let g : Array[Int64] = []
    for i = 0; i < next_k; i = i + 1 {
      let ln_val = if i < ln_h.length() { ln_h[i] } else { 0L }
      let f_val = if i < f_trunc.length() { f_trunc[i] } else { 0L }
      // 1 - ln_h + f. The "1" only affects the constant term.
      let one = if i == 0 { 1L } else { 0L }
      g.push(@int64_utils.mod64(one - ln_val + f_val, MOD))
    }
    // h = h * g.
    let new_h = poly_mul(h_pad, g)
    h = pad(new_h, next_k)
    k = next_k
  }
  pad(h, n)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "poly_inv: basic" {
  // f = 1 + x → inv = 1 - x + x^2 - x^3 + ...
  let f : Array[Int64] = [1L, 1L]
  let h = poly_inv(f, 4)
  // h should be [1, -1, 1, -1] = [1, MOD-1, 1, MOD-1]
  assert_eq(h[0], 1L)
  assert_eq(h[1], MOD - 1L)
  assert_eq(h[2], 1L)
  assert_eq(h[3], MOD - 1L)
}

test "poly_inv: verify f * h = 1" {
  let f : Array[Int64] = [1L, 2L, 3L]
  let h = poly_inv(f, 8)
  let product = poly_mul(f, h)
  // product should be [1, 0, 0, 0, 0, 0, 0, 0, ...]
  assert_eq(product[0], 1L)
  for i = 1; i < 8; i = i + 1 {
    assert_eq(product[i], 0L)
  }
}

test "poly_sqrt: basic" {
  // f = 1 → sqrt = 1
  let f : Array[Int64] = [1L]
  let h = poly_sqrt(f, 4)
  assert_eq(h[0], 1L)
}

test "poly_sqrt: (1+x)^2 = 1+2x+x^2" {
  // f = 1 + 2x + x^2 → sqrt = 1 + x
  let f : Array[Int64] = [1L, 2L, 1L]
  let h = poly_sqrt(f, 4)
  assert_eq(h[0], 1L)
  assert_eq(h[1], 1L)
  assert_eq(h[2], 0L)
}

test "poly_sqrt: verify h^2 = f" {
  let f : Array[Int64] = [1L, 4L, 6L, 4L, 1L] // (1+x)^4
  let h = poly_sqrt(f, 8)
  let h_sq = poly_mul(h, h)
  // Truncate to 5 terms and check.
  for i = 0; i < 5; i = i + 1 {
    assert_eq(h_sq[i], f[i])
  }
}

test "poly_log: basic" {
  // f = 1 + x → ln(1+x) = x - x^2/2 + x^3/3 - ...
  let f : Array[Int64] = [1L, 1L]
  let h = poly_log(f, 5)
  // h = [0, 1, -1/2, 1/3, -1/4]
  assert_eq(h[0], 0L)
  assert_eq(h[1], 1L)
  assert_eq(h[2], @int64_utils.mul_mod(MOD - 1L, mod_inv(2L), MOD))
  assert_eq(h[3], mod_inv(3L))
  assert_eq(h[4], @int64_utils.mul_mod(MOD - 1L, mod_inv(4L), MOD))
}

test "poly_log: verify exp(log(f)) = f" {
  // f = 1 + x + x^2
  let f : Array[Int64] = [1L, 1L, 1L]
  let lf = poly_log(f, 8)
  let ef = poly_exp(lf, 8)
  for i = 0; i < 3; i = i + 1 {
    assert_eq(ef[i], f[i])
  }
}

test "poly_exp: basic" {
  // f = x → exp(x) = 1 + x + x^2/2 + x^3/6 + ...
  let f : Array[Int64] = [0L, 1L]
  let h = poly_exp(f, 5)
  // h = [1, 1, 1/2, 1/6, 1/24]
  assert_eq(h[0], 1L)
  assert_eq(h[1], 1L)
  assert_eq(h[2], mod_inv(2L))
  assert_eq(h[3], mod_inv(6L))
  assert_eq(h[4], mod_inv(24L))
}

test "poly_exp: verify log(exp(f)) = f" {
  let f : Array[Int64] = [0L, 1L, 2L, 3L]
  let ef = poly_exp(f, 8)
  let lf = poly_log(ef, 8)
  for i = 0; i < 4; i = i + 1 {
    assert_eq(lf[i], f[i])
  }
}

test "poly_inv: with larger polynomial" {
  // f = 1 + 2x + 3x^2
  let f : Array[Int64] = [1L, 2L, 3L]
  let h = poly_inv(f, 16)
  // Verify f * h ≡ 1 (mod x^16).
  let product = poly_mul(f, h)
  assert_eq(product[0], 1L)
  for i = 1; i < 16; i = i + 1 {
    assert_eq(product[i], 0L)
  }
}

test "poly_log: f = 1/(1-x) = 1 + x + x^2 + ..., ln = -ln(1-x) = x + x^2/2 + x^3/3 + ..." {
  // Actually ln(1/(1-x)) = -ln(1-x) = Σ x^n/n.
  let f : Array[Int64] = [1L, 1L, 1L, 1L, 1L]
  let h = poly_log(f, 5)
  assert_eq(h[0], 0L)
  assert_eq(h[1], 1L)
  assert_eq(h[2], mod_inv(2L))
  assert_eq(h[3], mod_inv(3L))
  assert_eq(h[4], mod_inv(4L))
}
