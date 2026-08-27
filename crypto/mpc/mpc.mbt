///|
/// Secure Multi-Party Computation (MPC) — Shamir Secret Sharing +
/// BGW88 Secure Multiplication
///
/// MPC allows multiple parties to jointly compute a function on their
/// private inputs without revealing those inputs.
///
/// ## Design
///
/// - **Field**: integers modulo the Mersenne prime `2^31 - 1`. All
///   products are computed in `Int64` to avoid 32-bit overflow.
/// - **Shamir Secret Sharing**: split a secret s into n shares where
///   any t shares reconstruct s, but t-1 shares reveal nothing
///   (information-theoretically, over a field larger than the secret).
/// - **BGW multiplication** (Ben-Or, Goldwasser, Wigderson 1988):
///   parties locally multiply their shares (points of a degree-2(t-1)
///   polynomial h with h(0) = a·b), then degree-reduce: each party
///   re-shares its local product with a fresh degree-(t-1) polynomial,
///   and every party's new share is the Lagrange-weighted (at 0) sum
///   of the received sub-shares. The result is a degree-(t-1) sharing
///   of a·b. Requires `n >= 2t - 1`.
/// - **Randomness**: all protocol randomness is drawn from a
///   ChaCha20-based CSPRNG keyed by SHA-256 of the caller-provided
///   seed. Passing a predictable seed yields a predictable sharing —
///   production deployments must seed from `crypto/csprng`.
///
/// ## Security model
///
/// Semi-honest (honest-but-curious) adversaries corrupting fewer than
/// t parties; the multiplication gate additionally requires an honest
/// majority (`n >= 2t - 1`). Shares of different secrets must never
/// reuse a seed.
///
/// ## References
///
/// - Shamir, "How to Share a Secret." CACM 1979.
/// - Ben-Or, Goldwasser, Wigderson. "Completeness Theorems for
///   Non-Cryptographic Fault-Tolerant Distributed Computation." STOC
///   1988.
///
/// `proof-enabled` is `false`.

///|
/// Field prime: 2^31 - 1 (Mersenne prime M31).
pub const MPC_PRIME : Int = 2147483647

///|
fn mpc_add_mod(a : Int, b : Int) -> Int {
  let s = a.to_int64() + b.to_int64()
  let r = s % MPC_PRIME.to_int64()
  r.to_int()
}

///|
fn mpc_mul_mod(a : Int, b : Int) -> Int {
  let p = a.to_int64() * b.to_int64() % MPC_PRIME.to_int64()
  let r = if p < 0L { p + MPC_PRIME.to_int64() } else { p }
  r.to_int()
}

///|
/// Field addition modulo `MPC_PRIME`.
pub fn mpc_field_add(a : Int, b : Int) -> Int {
  mpc_add_mod(a, b)
}

///|
/// Field multiplication modulo `MPC_PRIME`.
pub fn mpc_field_mul(a : Int, b : Int) -> Int {
  mpc_mul_mod(a, b)
}

///|
fn mpc_neg(a : Int) -> Int {
  if a == 0 {
    0
  } else {
    MPC_PRIME - a
  }
}

///|
/// Modular inverse via the extended Euclidean algorithm.
fn mpc_inv_mod(a : Int) -> Int {
  let mut old_r = a.to_int64()
  let mut r = MPC_PRIME.to_int64()
  let mut old_s = 1L
  let mut s = 0L
  while r != 0L {
    let q = old_r / r
    let nr = old_r - q * r
    old_r = r
    r = nr
    let ns = old_s - q * s
    old_s = s
    s = ns
  }
  let v = old_s % MPC_PRIME.to_int64()
  let w = if v < 0L { v + MPC_PRIME.to_int64() } else { v }
  w.to_int()
}

///|
/// Lagrange coefficient `L_i(0)` for the share set (x-coordinates).
fn mpc_lagrange_at_zero(shares : Array[ShamirShare], i : Int) -> Int {
  let mut num = 1
  let mut den = 1
  for j = 0; j < shares.length(); j = j + 1 {
    if i != j {
      num = mpc_mul_mod(num, mpc_neg(shares[j].x))
      let mut diff = shares[i].x - shares[j].x
      if diff < 0 {
        diff = diff + MPC_PRIME
      }
      den = mpc_mul_mod(den, diff)
    }
  }
  mpc_mul_mod(num, mpc_inv_mod(den))
}

// ===========================================================================
// CSPRNG plumbing (ChaCha20 keyed by SHA-256 of the seed)
// ===========================================================================

///|
fn mpc_rng(seed : Bytes) -> @chacha20.ChaCha20Rng raise {
  let key = @sha256.sha256(seed)
  let nonce_src = @sha256.sha256(seed + b"mpc-nonce")
  let nonce_arr : Array[Byte] = []
  for i = 0; i < 12; i = i + 1 {
    nonce_arr.push(nonce_src[i])
  }
  match @chacha20.create_rng(key, Bytes::from_array(nonce_arr)) {
    Some(rng) => rng
    None => fail("mpc: failed to initialise CSPRNG")
  }
}

///|
fn mpc_rand_field(rng : @chacha20.ChaCha20Rng) -> Int raise {
  match @chacha20.next_int_in_range(rng, MPC_PRIME) {
    Some(v) => v
    None => fail("mpc: CSPRNG exhausted")
  }
}

// ===========================================================================
// Shamir Secret Sharing
// ===========================================================================

///|
/// A share in Shamir's secret sharing: (x, y) where y = f(x).
pub struct ShamirShare {
  /// X-coordinate (party ID)
  x : Int
  /// Y-coordinate (share value)
  y : Int
} derive(Eq, Debug)

///|
/// Evaluate a polynomial (coefficients low-to-high) at x modulo p.
fn mpc_poly_eval(coeffs : Array[Int], x : Int) -> Int {
  let mut acc = 0
  for i = coeffs.length() - 1; i >= 0; i = i - 1 {
    acc = mpc_add_mod(mpc_mul_mod(acc, x), coeffs[i])
  }
  acc
}

///|
/// Split a secret into n shares using threshold t.
///
/// Any t shares can reconstruct the secret; fewer reveal nothing.
/// Requires `1 <= t <= n` and values in `[0, MPC_PRIME)`.
pub fn shamir_split(
  secret : Int,
  n : Int,
  t : Int,
  seed : Bytes,
) -> Array[ShamirShare] raise {
  if t < 1 || n < t {
    fail("shamir: requires 1 <= t <= n")
  }
  if secret < 0 || secret >= MPC_PRIME {
    fail("shamir: secret out of field range")
  }
  let rng = mpc_rng(seed)
  // Random polynomial f with f(0) = secret.
  let coeffs = Array::make(t, 0)
  coeffs[0] = secret
  for i = 1; i < t; i = i + 1 {
    coeffs[i] = mpc_rand_field(rng)
  }
  let shares : Array[ShamirShare] = []
  for x = 1; x <= n; x = x + 1 {
    shares.push({ x, y: mpc_poly_eval(coeffs, x), })
  }
  shares
}

///|
/// Reconstruct a secret from shares using Lagrange interpolation at 0.
/// Passing fewer than the threshold shares yields an arbitrary field
/// element, not the secret.
pub fn shamir_reconstruct(shares : Array[ShamirShare]) -> Int {
  let mut result = 0
  for i = 0; i < shares.length(); i = i + 1 {
    let li = mpc_lagrange_at_zero(shares, i)
    result = mpc_add_mod(result, mpc_mul_mod(shares[i].y, li))
  }
  result
}

// ===========================================================================
// BGW secure arithmetic
// ===========================================================================

///|
/// Secure addition of two shared secrets (purely local).
pub fn mpc_add(
  shares_a : Array[ShamirShare],
  shares_b : Array[ShamirShare],
) -> Array[ShamirShare] {
  let result : Array[ShamirShare] = []
  for i = 0; i < shares_a.length(); i = i + 1 {
    result.push({
      x: shares_a[i].x,
      y: mpc_add_mod(shares_a[i].y, shares_b[i].y),
    })
  }
  result
}

///|
/// Secure multiplication of two shared secrets (BGW88).
///
/// Each party locally multiplies its shares of a and b, obtaining
/// points of a degree-2(t-1) polynomial h with h(0) = a·b. Degree
/// reduction then re-shares every local product with a fresh
/// degree-(t-1) polynomial and combines the sub-shares with Lagrange
/// weights at 0, yielding a degree-(t-1) sharing of a·b.
///
/// Requires `n >= 2t - 1` (honest majority). Returns shares with the
/// same x-coordinates as the inputs.
pub fn mpc_secure_mul(
  shares_a : Array[ShamirShare],
  shares_b : Array[ShamirShare],
  n : Int,
  t : Int,
  seed : Bytes,
) -> Array[ShamirShare] raise {
  if t < 1 || n < t {
    fail("bgw: requires 1 <= t <= n")
  }
  if n < 2 * t - 1 {
    fail("bgw: multiplication requires n >= 2t - 1 (honest majority)")
  }
  if shares_a.length() != n || shares_b.length() != n {
    fail("bgw: share arrays must have length n")
  }
  // Local products: points of h(x) = a(x)·b(x), degree 2(t-1).
  let local_products : Array[Int] = []
  for i = 0; i < n; i = i + 1 {
    local_products.push(mpc_mul_mod(shares_a[i].y, shares_b[i].y))
  }
  // Lagrange weights at 0 over the input x-coordinates.
  let weights : Array[Int] = []
  for i = 0; i < n; i = i + 1 {
    weights.push(mpc_lagrange_at_zero(shares_a, i))
  }
  // Each party re-shares its local product with a fresh degree-(t-1)
  // polynomial; party j accumulates the Lagrange-weighted sub-shares.
  let rng = mpc_rng(seed)
  let accum : Array[Int] = Array::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    let coeffs = Array::make(t, 0)
    coeffs[0] = local_products[i]
    for j = 1; j < t; j = j + 1 {
      coeffs[j] = mpc_rand_field(rng)
    }
    let wi = weights[i]
    for j = 0; j < n; j = j + 1 {
      let sub = mpc_poly_eval(coeffs, shares_a[j].x)
      accum[j] = mpc_add_mod(accum[j], mpc_mul_mod(wi, sub))
    }
  }
  let result : Array[ShamirShare] = []
  for j = 0; j < n; j = j + 1 {
    result.push({ x: shares_a[j].x, y: accum[j], })
  }
  result
}
