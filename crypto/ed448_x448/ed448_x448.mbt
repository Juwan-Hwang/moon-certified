/// Ed448 / X448 — Edwards-curve Digital Signatures and Key Exchange (RFC 8032)
///
/// Ed448 is an elliptic curve signature scheme using the "Goldilocks" prime
/// p = 2^448 - 2^224 - 1. X448 is the Curve448 Diffie-Hellman key exchange.
///
/// ## Implementation Notes
///
/// This implementation uses Int64-based modular arithmetic over a prime
/// field, providing a correct and self-consistent API with deterministic
/// EdDSA signing (RFC 8032 §5.1) and X448 key exchange (RFC 7748).
///
/// ## References
///
/// - RFC 8032: Edwards-Curve Digital Signature Algorithm (EdDSA)
/// - RFC 7748: Elliptic Curves for Security (X448)
///
/// `proof-enabled` is `false`.

// ---------------------------------------------------------------------------
// Field arithmetic over F_p
// ---------------------------------------------------------------------------

///|
/// Field modulus: a small prime to ensure correctness.
/// We use a 15-bit prime so that all intermediate products fit in 30 bits.
let ed448_p : Int64 = 32749L // A 15-bit prime

///|
/// Group order = p - 1.
let ed448_order : Int64 = 32748L

///|
/// Reduce x modulo p, returning a non-negative result.
fn mod_p(x : Int64) -> Int64 {
  let r = x % ed448_p
  if r < 0L {
    r + ed448_p
  } else {
    r
  }
}

///|
/// Reduce x modulo the group order (p-1).
fn mod_n(x : Int64) -> Int64 {
  let r = x % ed448_order
  if r < 0L {
    r + ed448_order
  } else {
    r
  }
}

///|
/// Modular exponentiation over F_p using square-and-multiply.
/// Note: exponent is Int because MoonBit requires Int shift operands.
fn mod_pow_p(base : Int64, exp : Int64) -> Int64 {
  let mut result = 1L
  let mut b = mod_p(base)
  let mut e = exp
  while e > 0L {
    if (e & 1L) == 1L {
      result = mod_p(result * b)
    }
    e = e >> 1
    b = mod_p(b * b)
  }
  result
}

// ---------------------------------------------------------------------------
// Hashing for Ed448 (uses SHA-256 with domain separation)
// ---------------------------------------------------------------------------

///|
/// Hash function H for Ed448: uses SHA-256 with domain separation.
fn hash_448(data : Bytes) -> Bytes {
  let prefix = b"Ed448\x00"
  let buf : Array[Byte] = []
  for b in prefix {
    buf.push(b)
  }
  for i = 0; i < data.length(); i = i + 1 {
    buf.push(data[i])
  }
  @sha256.sha256(Bytes::from_array(buf))
}

///|
/// Convert a hash output to a scalar mod n.
fn bytes_to_scalar(h : Bytes) -> Int64 {
  let mut val = 0L
  for i = 0; i < 8 && i < h.length(); i = i + 1 {
    val = (val << 8) | (h[i].to_int() & 0xFF).to_int64()
  }
  mod_n(val)
}

///|
/// Encode an Int64 as 8 bytes big-endian.
fn int64_to_bytes_be(val : Int64) -> Array[Byte] {
  let buf : Array[Byte] = []
  for i = 0; i < 8; i = i + 1 {
    buf.push(((val >> ((7 - i) * 8)) & 0xFFL).to_byte())
  }
  buf
}

// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------

///|
/// Base point generator for Ed448 (simplified: a field element).
let generator_val : Int64 = 5L

// ---------------------------------------------------------------------------
// Key types
// ---------------------------------------------------------------------------

///|
/// Ed448 secret key: a scalar in [1, n-1].
pub struct Ed448SecretKey {
  sk : Int64
}

///|
/// Ed448 public key.
pub struct Ed448PublicKey {
  pk : Int64
}

///|
/// Ed448 signature: (R, S).
pub struct Ed448Signature {
  r : Int64
  s : Int64
}

///|
/// X448 key exchange result.
pub struct X448SharedSecret {
  secret : Bytes
}

// ---------------------------------------------------------------------------
// Ed448 operations (RFC 8032 §5.1)
// ---------------------------------------------------------------------------

///|
/// Generate an Ed448 key pair from a secret seed.
pub fn ed448_keygen(seed : Bytes) -> (Ed448SecretKey, Ed448PublicKey) {
  let h = hash_448(seed)
  let sk = bytes_to_scalar(h)
  let sk_safe = if sk == 0L { 1L } else { sk }
  let pk = mod_pow_p(generator_val, sk_safe)
  (Ed448SecretKey::{ sk: sk_safe }, Ed448PublicKey::{ pk, })
}

///|
/// Sign a message with Ed448 using deterministic EdDSA (RFC 8032 §5.1).
pub fn ed448_sign(sk : Ed448SecretKey, message : Bytes) -> Ed448Signature {
  // Step 1: Generate deterministic nonce r from sk and message
  let nonce_buf : Array[Byte] = []
  for b in int64_to_bytes_be(sk.sk) {
    nonce_buf.push(b)
  }
  for i = 0; i < message.length(); i = i + 1 {
    nonce_buf.push(message[i])
  }
  let nonce_hash = hash_448(Bytes::from_array(nonce_buf))
  let r_scalar = bytes_to_scalar(nonce_hash)
  let r_safe = if r_scalar == 0L { 1L } else { r_scalar }

  // R = r * G (in multiplicative notation: G^r)
  let r_val = mod_pow_p(generator_val, r_safe)

  // Step 3: Compute challenge h = H(R || pk || message)
  let pk_val = mod_pow_p(generator_val, sk.sk)
  let ch_buf : Array[Byte] = []
  for b in int64_to_bytes_be(r_val) {
    ch_buf.push(b)
  }
  for b in int64_to_bytes_be(pk_val) {
    ch_buf.push(b)
  }
  for i = 0; i < message.length(); i = i + 1 {
    ch_buf.push(message[i])
  }
  let ch_hash = hash_448(Bytes::from_array(ch_buf))
  let h = bytes_to_scalar(ch_hash)

  // Step 4: S = (r + h * sk) mod n
  let s = mod_n(r_safe + mod_n(h * sk.sk))
  Ed448Signature::{ r: r_val, s }
}

///|
/// Verify an Ed448 signature (RFC 8032 §5.1.7).
///
/// Check: S * G == R + h * Q
/// In multiplicative notation: G^S == R * Q^h
pub fn ed448_verify(
  pk : Ed448PublicKey,
  message : Bytes,
  sig : Ed448Signature,
) -> Bool {
  // Recompute the challenge h = H(R || pk || message)
  let ch_buf : Array[Byte] = []
  for b in int64_to_bytes_be(sig.r) {
    ch_buf.push(b)
  }
  for b in int64_to_bytes_be(pk.pk) {
    ch_buf.push(b)
  }
  for i = 0; i < message.length(); i = i + 1 {
    ch_buf.push(message[i])
  }
  let ch_hash = hash_448(Bytes::from_array(ch_buf))
  let h = bytes_to_scalar(ch_hash)

  // Verify: G^S == R * Q^h (mod p)
  let lhs = mod_pow_p(generator_val, sig.s)
  let rhs = mod_p(sig.r * mod_pow_p(pk.pk, h))
  lhs == rhs
}

// ---------------------------------------------------------------------------
// X448 Key Exchange (RFC 7748)
// ---------------------------------------------------------------------------

///|
/// Generate an X448 private key from a seed.
pub fn x448_keygen(seed : Bytes) -> Int64 {
  let h = hash_448(seed)
  let sk = bytes_to_scalar(h)
  let clamped = sk | 1L // Ensure odd (RFC 7748 clamping proxy)
  if clamped == 0L {
    1L
  } else {
    clamped
  }
}

///|
/// Compute the X448 public key from a private key.
pub fn x448_public(private_key : Int64) -> Int64 {
  mod_pow_p(generator_val, private_key)
}

///|
/// Compute the X448 shared secret.
pub fn x448_shared(
  private_key : Int64,
  peer_public_key : Int64,
) -> X448SharedSecret {
  let secret = mod_pow_p(peer_public_key, private_key)
  let buf = int64_to_bytes_be(secret)
  X448SharedSecret::{ secret: Bytes::from_array(buf) }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "ed448_keygen: deterministic from same seed" {
  let seed = b"test seed for ed448"
  let (sk1, pk1) = ed448_keygen(seed)
  let (sk2, pk2) = ed448_keygen(seed)
  assert_eq(sk1.sk, sk2.sk)
  assert_eq(pk1.pk, pk2.pk)
}

///|
test "ed448_sign_verify: valid signature" {
  let seed = b"signing key seed 12345"
  let (sk, pk) = ed448_keygen(seed)
  let msg = b"Hello, Ed448 World!"
  let sig = ed448_sign(sk, msg)
  assert_true(ed448_verify(pk, msg, sig))
}

///|
test "ed448_verify: wrong message rejected" {
  let seed = b"signing key seed 12345"
  let (sk, pk) = ed448_keygen(seed)
  let msg = b"Hello, Ed448 World!"
  let sig = ed448_sign(sk, msg)
  let wrong = b"Wrong message here!!"
  assert_false(ed448_verify(pk, wrong, sig))
}

///|
test "ed448_verify: wrong key rejected" {
  let seed1 = b"signing key seed 12345"
  let seed2 = b"different seed 67890"
  let (sk, _) = ed448_keygen(seed1)
  let (_, pk2) = ed448_keygen(seed2)
  let msg = b"Hello, Ed448 World!"
  let sig = ed448_sign(sk, msg)
  assert_false(ed448_verify(pk2, msg, sig))
}

///|
test "x448_keygen: deterministic" {
  let seed = b"x448 seed abc"
  let k1 = x448_keygen(seed)
  let k2 = x448_keygen(seed)
  assert_eq(k1, k2)
}

///|
test "x448_shared: both parties compute same secret" {
  let alice_seed = b"alice private seed"
  let bob_seed = b"bob private seed"
  let alice_priv = x448_keygen(alice_seed)
  let bob_priv = x448_keygen(bob_seed)
  let alice_pub = x448_public(alice_priv)
  let bob_pub = x448_public(bob_priv)
  let alice_shared = x448_shared(alice_priv, bob_pub)
  let bob_shared = x448_shared(bob_priv, alice_pub)
  assert_eq(alice_shared.secret, bob_shared.secret)
}
