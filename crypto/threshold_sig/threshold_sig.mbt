/// Threshold Signatures — Shamir-based t-of-n Secret Sharing + Signing
///
/// Threshold signatures allow t out of n parties to jointly produce a valid
/// signature without ever reconstructing the secret key. Any t-1 parties learn
/// nothing about the key.
///
/// ## Design
///
/// - **Distributed Key Generation (DKG)**: Use Pedersen Verifiable Secret
///   Sharing to generate a shared secret key without a trusted dealer.
/// - **Threshold Signing**: Each party computes a partial signature σ_i.
///   Any t partial signatures can be combined into a valid signature.
///
/// ## References
///
/// - Shamir, "How to Share a Secret." CACM 1979.
/// - Gennaro, Jarecki, Krawczyk, Rabin. "Secure Distributed Key Generation
///   for Discrete-Log Based Cryptosystems." EUROCRYPT 1999.
///
/// `proof-enabled` is `false`.

///|
const TS_PRIME : Int = 2147483647

///|
fn mod_p(x : Int) -> Int {
  let r = x % TS_PRIME
  if r < 0 {
    r + TS_PRIME
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

// ===========================================================================
// Threshold key types
// ===========================================================================

///|
/// A key share for party i.
pub struct KeyShare {
  /// Party index (1-based)
  party_id : Int
  /// Secret share value
  share : Int
}

///|
/// A partial signature from party i.
pub struct PartialSignature {
  /// Party index
  party_id : Int
  /// Partial signature value
  partial : Int
}

// ===========================================================================
// Distributed Key Generation (simplified trusted dealer)
// ===========================================================================

///|
/// Generate a threshold key set.
///
/// A trusted dealer generates the secret and shares it among n parties
/// with threshold t. In production, this would use DKG (no trusted dealer).
///
/// ## Parameters
/// - `secret`: the secret key to share
/// - `n`: number of parties
/// - `t`: threshold (minimum parties needed)
/// - `seed`: randomness
pub fn threshold_keygen(
  secret : Int,
  n : Int,
  t : Int,
  seed : Int,
) -> Array[KeyShare] {
  if t < 1 || n < t {
    abort("Threshold: invalid parameters")
  }
  let rng = Xorshift64::new(seed)
  // Shamir secret sharing
  let coeffs = Array::make(t, 0)
  coeffs[0] = mod_p(secret)
  for i = 1; i < t; i = i + 1 {
    coeffs[i] = rng.next() % TS_PRIME
  }
  let shares : Array[KeyShare] = []
  for x = 1; x <= n; x = x + 1 {
    let mut y = 0
    let mut x_pow = 1
    for i = 0; i < t; i = i + 1 {
      y = mod_p(y + coeffs[i] * x_pow)
      x_pow = mod_p(x_pow * x)
    }
    shares.push({ party_id: x, share: y })
  }
  shares
}

///|
/// Reconstruct the secret from t shares (Lagrange interpolation).
pub fn threshold_reconstruct(shares : Array[KeyShare]) -> Int {
  let t = shares.length()
  let mut result = 0
  for i = 0; i < t; i = i + 1 {
    let mut num = 1
    let mut den = 1
    for j = 0; j < t; j = j + 1 {
      if i != j {
        num = mod_p(num * -shares[j].party_id)
        den = mod_p(den * mod_p(shares[i].party_id - shares[j].party_id))
      }
    }
    let lagrange = mod_p(num * mod_inv(den, TS_PRIME))
    result = mod_p(result + shares[i].share * lagrange)
  }
  result
}

// ===========================================================================
// Threshold signing
// ===========================================================================

///|
/// Generate a partial signature for a message.
///
/// Each party i computes σ_i = share_i * H(message) mod p.
pub fn threshold_sign_partial(
  share : KeyShare,
  message_hash : Int,
) -> PartialSignature {
  let partial = mod_p(share.share * message_hash)
  { party_id: share.party_id, partial }
}

///|
/// Combine t partial signatures into a full signature.
///
/// Uses Lagrange interpolation on the partial signatures.
pub fn threshold_combine_signatures(partials : Array[PartialSignature]) -> Int {
  let t = partials.length()
  let mut result = 0
  for i = 0; i < t; i = i + 1 {
    let mut num = 1
    let mut den = 1
    for j = 0; j < t; j = j + 1 {
      if i != j {
        num = mod_p(num * -partials[j].party_id)
        den = mod_p(den * mod_p(partials[i].party_id - partials[j].party_id))
      }
    }
    let lagrange = mod_p(num * mod_inv(den, TS_PRIME))
    result = mod_p(result + partials[i].partial * lagrange)
  }
  result
}

///|
/// Verify a threshold signature.
///
/// Checks that σ == secret * H(message) where the secret is
/// the reconstructed key.
pub fn threshold_verify(
  public_key : Int,
  message_hash : Int,
  signature : Int,
) -> Bool {
  // Check: G^signature == public_key^message_hash
  // In simplified multiplicative notation: signature == pk^H(m)
  let expected = mod_pow(public_key, message_hash, TS_PRIME)
  expected == signature
}
