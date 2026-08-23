/// Digital Signature Algorithm (DSA) — FIPS 186-4
///
/// DSA is a federal standard for digital signatures based on the discrete
/// logarithm problem in Z_p*. This module implements DSA key generation,
/// signing, and verification.
///
/// ## Parameters
/// - p: prime modulus (1024-3072 bits per FIPS 186-4)
/// - q: prime divisor of p-1 (160-256 bits)
/// - g: generator of the subgroup of order q
///
/// ⚠️ NOTE: Simplified over small primes for API demonstration.
///
/// `proof-enabled` is `false`.

///|
const DSA_P : Int = 10007

///|
const DSA_Q : Int = 5003

///|
/// Generator of the subgroup of order q.
/// Computed as h^((p-1)/q) mod p = 2^2 mod 10007 = 4,
/// ensuring g^q ≡ 1 (mod p) so DSA verification math is correct.
const DSA_G : Int = 4

///|
fn mod_p(x : Int) -> Int {
  let r = x % DSA_P
  if r < 0 {
    r + DSA_P
  } else {
    r
  }
}

///|
fn mod_q(x : Int) -> Int {
  let r = x % DSA_Q
  if r < 0 {
    r + DSA_Q
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
  let mut b = base % m
  if b < 0 {
    b = b + m
  }
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
// Key types
// ===========================================================================

///|
/// DSA secret key.
pub struct DsaSecretKey {
  /// Secret exponent x ∈ [1, q-1]
  x : Int
}

///|
/// Construct a `DsaSecretKey`.
pub fn DsaSecretKey::new(x : Int) -> DsaSecretKey {
  { x, }
}

///|
/// DSA public key.
pub struct DsaPublicKey {
  /// Public value y = g^x mod p
  y : Int
}

///|
/// Construct a `DsaPublicKey`.
pub fn DsaPublicKey::new(y : Int) -> DsaPublicKey {
  { y, }
}

///|
/// DSA signature (r, s).
pub struct DsaSignature {
  /// R component: (g^k mod p) mod q
  r : Int
  /// S component: k^(-1) * (hash + x*r) mod q
  s : Int
}

///|
/// Construct a `DsaSignature`.
pub fn DsaSignature::new(r : Int, s : Int) -> DsaSignature {
  { r, s }
}

// ===========================================================================
// DSA operations
// ===========================================================================

///|
/// Generate a DSA key pair from a secret scalar.
pub fn dsa_keygen(secret : Int) -> (DsaSecretKey, DsaPublicKey) {
  let x = mod_q(secret)
  if x == 0 {
    abort("DSA: secret key must not be 0")
  }
  let y = mod_pow(DSA_G, x, DSA_P)
  ({ x, }, { y, })
}

///|
/// Sign a message hash with DSA.
///
/// ## Parameters
/// - `sk`: secret key
/// - `message_hash`: hash of the message (bytes)
/// - `k`: random nonce (must be in [1, q-1])
pub fn dsa_sign(
  sk : DsaSecretKey,
  message_hash : Bytes,
  k : Int,
) -> DsaSignature {
  let k_mod = mod_q(k)
  if k_mod == 0 {
    abort("DSA: k must not be 0")
  }
  // r = (g^k mod p) mod q
  let r = mod_q(mod_pow(DSA_G, k_mod, DSA_P))
  if r == 0 {
    abort("DSA: r must not be 0")
  }
  // Convert message hash to integer
  let mut z = 0
  for i = 0; i < message_hash.length() && i < 4; i = i + 1 {
    z = (z << 8) | (message_hash[i].to_int() & 0xFF)
  }
  z = mod_q(z)
  // s = k^(-1) * (z + x*r) mod q
  let k_inv = mod_inv(k_mod, DSA_Q)
  let s = mod_q(k_inv * mod_q(z + sk.x * r))
  if s == 0 {
    abort("DSA: s must not be 0")
  }
  { r, s }
}

///|
/// Verify a DSA signature.
pub fn dsa_verify(
  pk : DsaPublicKey,
  message_hash : Bytes,
  sig : DsaSignature,
) -> Bool {
  if sig.r < 1 || sig.r >= DSA_Q {
    return false
  }
  if sig.s < 1 || sig.s >= DSA_Q {
    return false
  }
  let mut z = 0
  for i = 0; i < message_hash.length() && i < 4; i = i + 1 {
    z = (z << 8) | (message_hash[i].to_int() & 0xFF)
  }
  z = mod_q(z)
  let w = mod_inv(sig.s, DSA_Q)
  let u1 = mod_q(z * w)
  let u2 = mod_q(sig.r * w)
  // v = (g^u1 * y^u2 mod p) mod q
  let v = mod_q(mod_p(mod_pow(DSA_G, u1, DSA_P) * mod_pow(pk.y, u2, DSA_P)))
  v == sig.r
}

// ===========================================================================
// ECDSA variant (simplified, for comparison)
// ===========================================================================

///|
/// ECDSA variant prime modulus.
const ECDSA_VARIANT_P : Int = 10007

///|
/// ECDSA variant subgroup order (must divide p-1 = 10006 = 2 * 5003).
const ECDSA_VARIANT_ORDER : Int = 5003

///|
/// ECDSA variant generator (order q = 5003).
/// Uses g = 2^((p-1)/q) mod p = 2^2 mod 10007 = 4.
const ECDSA_VARIANT_GEN : Int = 4

///|
/// ECDSA variant: sign with a simplified elliptic curve.
pub fn ecdsa_variant_sign(
  private_key : Int,
  message_hash : Bytes,
  k : Int,
) -> (Int, Int) {
  let sk = private_key % ECDSA_VARIANT_ORDER
  if sk == 0 {
    abort("ECDSA: private key must not be 0")
  }
  let k_mod = k % ECDSA_VARIANT_ORDER
  if k_mod == 0 {
    abort("ECDSA: k must not be 0")
  }
  // r = (k * G) mod n (x-coordinate simplified)
  let r = mod_pow(ECDSA_VARIANT_GEN, k_mod, ECDSA_VARIANT_P) %
    ECDSA_VARIANT_ORDER
  if r == 0 {
    abort("ECDSA: r must not be 0")
  }
  let mut z = 0
  for i = 0; i < message_hash.length() && i < 4; i = i + 1 {
    z = (z << 8) | (message_hash[i].to_int() & 0xFF)
  }
  z = z % ECDSA_VARIANT_ORDER
  let k_inv = mod_inv(k_mod, ECDSA_VARIANT_ORDER)
  let s = k_inv * (z + r * sk) % ECDSA_VARIANT_ORDER
  if s == 0 {
    abort("ECDSA: s must not be 0")
  }
  (r, s)
}

///|
/// ECDSA variant: verify.
pub fn ecdsa_variant_verify(
  public_key : Int,
  message_hash : Bytes,
  r : Int,
  s : Int,
) -> Bool {
  if r < 1 || r >= ECDSA_VARIANT_ORDER {
    return false
  }
  if s < 1 || s >= ECDSA_VARIANT_ORDER {
    return false
  }
  let mut z = 0
  for i = 0; i < message_hash.length() && i < 4; i = i + 1 {
    z = (z << 8) | (message_hash[i].to_int() & 0xFF)
  }
  z = z % ECDSA_VARIANT_ORDER
  let w = mod_inv(s, ECDSA_VARIANT_ORDER)
  let u1 = z * w % ECDSA_VARIANT_ORDER
  let u2 = r * w % ECDSA_VARIANT_ORDER
  let v = mod_pow(ECDSA_VARIANT_GEN, u1, ECDSA_VARIANT_P) *
    mod_pow(public_key, u2, ECDSA_VARIANT_P) %
    ECDSA_VARIANT_P %
    ECDSA_VARIANT_ORDER
  v == r
}
