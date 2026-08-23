///|
/// Fully Homomorphic Encryption (FHE) — BGV/BFV Scheme
///
/// Homomorphic encryption allows computation on encrypted data without
/// decryption. This module implements a simplified BGV/BFV-style FHE scheme
/// using the Learning with Errors (LWE) problem.
///
/// ## Design
///
/// - **KeyGen**: Secret key s ∈ Z_q^n, public key (A, b = A·s + e)
/// - **Encrypt**: c = (a, a·s + m + e) where a is random
/// - **Decrypt**: m = c_2 - s·c_1 (noise threshold)
/// - **Homomorphic Operations**:
///   - Addition: E(m1) + E(m2) = E(m1 + m2)
///   - Scalar multiplication: k * E(m) = E(k * m)
///   - Multiplication: limited by noise growth (bootstrapping needed)
///
/// ## References
///
/// - Gentry, "Fully Homomorphic Encryption Using Ideal Lattices." STOC 2009.
/// - Brakerski, Gentry, Vaikuntanathan. "BGV." CRYPTO 2012.
///
/// ⚠️ NOTE: Simplified LWE-based scheme for correctness demonstration.
///
/// `proof-enabled` is `false`.
const LWE_N : Int = 16 // Dimension

///|
const LWE_Q : Int = 65537 // Modulus (prime)

///|
const LWE_NOISE_BOUND : Int = 3

///|
fn mod_q(x : Int) -> Int {
  let r = x % LWE_Q
  if r < 0 {
    r + LWE_Q
  } else {
    r
  }
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
fn sample_small(rng : Xorshift64) -> Int {
  let v = rng.next() % (2 * LWE_NOISE_BOUND + 1)
  v - LWE_NOISE_BOUND
}

// ===========================================================================
// LWE types
// ===========================================================================

///|
/// LWE secret key.
pub struct LweSecretKey {
  /// Secret vector s ∈ Z_q^n
  s : Array[Int]
}

///|
/// LWE ciphertext (a, b) where b = a·s + m + e.
pub struct LweCiphertext {
  /// Vector a
  a : Array[Int]
  /// Value b = a·s + m + e
  b : Int
}

// ===========================================================================
// LWE operations
// ===========================================================================

///|
/// Generate an LWE secret key.
pub fn lwe_keygen(seed : Int) -> LweSecretKey {
  let rng = Xorshift64::new(seed)
  let s = Array::make(LWE_N, 0)
  for i = 0; i < LWE_N; i = i + 1 {
    s[i] = sample_small(rng)
  }
  { s, }
}

///|
/// Encrypt a message (integer) under an LWE key.
pub fn lwe_encrypt(
  sk : LweSecretKey,
  message : Int,
  seed : Int,
) -> LweCiphertext {
  let rng = Xorshift64::new(seed)
  let a = Array::make(LWE_N, 0)
  for i = 0; i < LWE_N; i = i + 1 {
    a[i] = rng.next() % LWE_Q
  }
  let e = sample_small(rng)
  // b = sum(a_i * s_i) + message * scale + e
  let mut dot = 0
  for i = 0; i < LWE_N; i = i + 1 {
    dot = dot + a[i] * sk.s[i]
  }
  let b = mod_q(dot + message * 1000 + e)
  { a, b }
}

///|
/// Decrypt an LWE ciphertext.
pub fn lwe_decrypt(sk : LweSecretKey, ct : LweCiphertext) -> Int {
  let mut dot = 0
  for i = 0; i < LWE_N; i = i + 1 {
    dot = dot + ct.a[i] * sk.s[i]
  }
  let m = mod_q(ct.b - dot)
  // Round to nearest message (undo scaling)
  let scaled = (m + 500) / 1000
  let _ = scaled
  // Center the result
  if m > LWE_Q / 2 {
    let centered = m - LWE_Q
    -((-centered + 500) / 1000)
  } else {
    (m + 500) / 1000
  }
}

///|
/// Homomorphic addition of two ciphertexts.
pub fn lwe_add(ct1 : LweCiphertext, ct2 : LweCiphertext) -> LweCiphertext {
  if ct1.a.length() != ct2.a.length() {
    abort("LWE: ciphertext dimension mismatch")
  }
  let a = Array::make(ct1.a.length(), 0)
  for i = 0; i < ct1.a.length(); i = i + 1 {
    a[i] = mod_q(ct1.a[i] + ct2.a[i])
  }
  let b = mod_q(ct1.b + ct2.b)
  { a, b }
}

///|
/// Homomorphic subtraction.
pub fn lwe_sub(ct1 : LweCiphertext, ct2 : LweCiphertext) -> LweCiphertext {
  if ct1.a.length() != ct2.a.length() {
    abort("LWE: ciphertext dimension mismatch")
  }
  let a = Array::make(ct1.a.length(), 0)
  for i = 0; i < ct1.a.length(); i = i + 1 {
    a[i] = mod_q(ct1.a[i] - ct2.a[i])
  }
  let b = mod_q(ct1.b - ct2.b)
  { a, b }
}

///|
/// Homomorphic scalar multiplication (multiply ciphertext by a plaintext constant).
pub fn lwe_mul_scalar(ct : LweCiphertext, k : Int) -> LweCiphertext {
  let a = Array::make(ct.a.length(), 0)
  for i = 0; i < ct.a.length(); i = i + 1 {
    a[i] = mod_q(ct.a[i] * k)
  }
  let b = mod_q(ct.b * k)
  { a, b }
}

///|
/// Homomorphic negation.
pub fn lwe_negate(ct : LweCiphertext) -> LweCiphertext {
  let a = Array::make(ct.a.length(), 0)
  for i = 0; i < ct.a.length(); i = i + 1 {
    a[i] = mod_q(-ct.a[i])
  }
  let b = mod_q(-ct.b)
  { a, b }
}
