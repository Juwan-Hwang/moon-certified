/// Secure Multi-Party Computation (MPC) — Shamir Secret Sharing + BGW Protocol
///
/// MPC allows multiple parties to jointly compute a function on their private
/// inputs without revealing those inputs.
///
/// ## Design
///
/// - **Shamir Secret Sharing**: Split a secret s into n shares where any t
///   shares can reconstruct s, but t-1 shares reveal nothing.
/// - **BGW Protocol**: For arithmetic circuits over a field, parties compute
///   addition (local) and multiplication (degree reduction via share exchange).
///
/// ## References
///
/// - Shamir, "How to Share a Secret." CACM 1979.
/// - Ben-Or, Goldwasser, Wigderson. "BGW Protocol." STOC 1988.
///
/// `proof-enabled` is `false`.

///|
const MPC_PRIME : Int = 2147483647 // Mersenne prime 2^31-1

///|
fn mod_p(x : Int) -> Int {
  let r = x % MPC_PRIME
  if r < 0 {
    r + MPC_PRIME
  } else {
    r
  }
}

///|
fn mod_pow(base : Int, exp : Int, m : Int) -> Int {
  if m == 1 {
    return 0
  }
  let mut result = 1
  let mut b = mod_p(base)
  let mut e = exp
  while e > 0 {
    if (e & 1) == 1 {
      result = result * b % m
    }
    e = e >> 1
    b = b * b % m
  }
  result
}

///|
fn mod_inv(a : Int, m : Int) -> Int {
  mod_pow(a, m - 2, m)
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
}

///|
priv struct Xorshift64 {
  mut state : Int64
}

///|
fn Xorshift64::new(seed : Int) -> Xorshift64 {
  { state: (seed.to_int64() | 1L) & 0x7FFFFFFFFFFFFFFFL }
}

///|
fn Xorshift64::next(self : Xorshift64) -> Int {
  let mut x = self.state
  x = x ^ (x << 13)
  x = x ^ (x >> 7)
  x = x ^ (x << 17)
  self.state = x
  (x & 0x7FFFFFFF).to_int()
}

///|
/// Split a secret into n shares using threshold t.
///
/// Any t shares can reconstruct the secret.
/// Requires: n >= t >= 1.
pub fn shamir_split(
  secret : Int,
  n : Int,
  t : Int,
  seed : Int,
) -> Array[ShamirShare] {
  if t < 1 || n < t {
    abort("Shamir: invalid parameters")
  }
  let rng = Xorshift64::new(seed)
  // Generate random polynomial coefficients: f(x) = secret + a_1*x + ... + a_{t-1}*x^{t-1}
  let coeffs = Array::make(t, 0)
  coeffs[0] = mod_p(secret)
  for i = 1; i < t; i = i + 1 {
    coeffs[i] = rng.next() % MPC_PRIME
  }
  // Evaluate f(x) for x = 1, 2, ..., n
  let shares : Array[ShamirShare] = []
  for x = 1; x <= n; x = x + 1 {
    let mut y = 0
    let mut x_pow = 1
    for i = 0; i < t; i = i + 1 {
      y = mod_p(y + coeffs[i] * x_pow)
      x_pow = mod_p(x_pow * x)
    }
    shares.push({ x, y })
  }
  shares
}

///|
/// Reconstruct a secret from t shares using Lagrange interpolation.
pub fn shamir_reconstruct(shares : Array[ShamirShare]) -> Int {
  let t = shares.length()
  let mut result = 0
  for i = 0; i < t; i = i + 1 {
    // Lagrange coefficient: L_i(0) = prod_{j≠i} (-x_j) / (x_i - x_j)
    let mut num = 1
    let mut den = 1
    for j = 0; j < t; j = j + 1 {
      if i != j {
        num = mod_p(num * -shares[j].x)
        den = mod_p(den * mod_p(shares[i].x - shares[j].x))
      }
    }
    let lagrange = mod_p(num * mod_inv(den, MPC_PRIME))
    result = mod_p(result + shares[i].y * lagrange)
  }
  result
}

// ===========================================================================
// Secure Multiplication (BGW protocol, single multiplication)
// ===========================================================================

///|
/// Secure multiplication of two shared secrets.
///
/// Each party locally computes the product of their shares, then shares
/// the result using degree-reduced sharing.
///
/// ## Parameters
/// - `shares_a`: shares of secret a
/// - `shares_b`: shares of secret b
/// - `n`: number of parties
/// - `t`: threshold
/// - `seed`: randomness
///
/// ## Returns
/// Shares of a * b.
pub fn mpc_secure_mul(
  shares_a : Array[ShamirShare],
  shares_b : Array[ShamirShare],
  n : Int,
  t : Int,
  seed : Int,
) -> Array[ShamirShare] {
  // Each party computes c_i = a_i * b_i (local)
  let local_products : Array[Int] = []
  for i = 0; i < shares_a.length(); i = i + 1 {
    local_products.push(mod_p(shares_a[i].y * shares_b[i].y))
  }
  // Each party shares their local product using degree t-1 polynomial
  // (degree reduction from 2(t-1) to t-1)
  let rng = Xorshift64::new(seed)
  let shares_of_products : Array[Array[ShamirShare]] = []
  for i = 0; i < local_products.length(); i = i + 1 {
    // Share local_products[i] using a degree t-1 polynomial
    let coeffs = Array::make(t, 0)
    coeffs[0] = local_products[i]
    for j = 1; j < t; j = j + 1 {
      coeffs[j] = rng.next() % MPC_PRIME
    }
    let party_shares : Array[ShamirShare] = []
    for x = 1; x <= n; x = x + 1 {
      let mut y = 0
      let mut x_pow = 1
      for k = 0; k < t; k = k + 1 {
        y = mod_p(y + coeffs[k] * x_pow)
        x_pow = mod_p(x_pow * x)
      }
      party_shares.push({ x, y })
    }
    shares_of_products.push(party_shares)
  }
  // Each party j collects the j-th share from all parties and sums them
  let result : Array[ShamirShare] = []
  for j = 0; j < n; j = j + 1 {
    let mut sum = 0
    let mut x = 0
    for i = 0; i < shares_of_products.length(); i = i + 1 {
      if j < shares_of_products[i].length() {
        sum = mod_p(sum + shares_of_products[i][j].y)
        x = shares_of_products[i][j].x
      }
    }
    result.push({ x, y: sum })
  }
  result
}

///|
/// Secure addition of two shared secrets (local operation).
pub fn mpc_add(
  shares_a : Array[ShamirShare],
  shares_b : Array[ShamirShare],
) -> Array[ShamirShare] {
  let result : Array[ShamirShare] = []
  for i = 0; i < shares_a.length(); i = i + 1 {
    result.push({ x: shares_a[i].x, y: mod_p(shares_a[i].y + shares_b[i].y) })
  }
  result
}
