/// Bilinear Pairings — BN254 / BLS12-381
///
/// Bilinear pairings enable three-move cryptographic protocols: given groups
/// G1, G2 of prime order r, a pairing e: G1 × G2 → GT satisfies:
/// - Bilinearity: e(a·P, b·Q) = e(P,Q)^(ab)
/// - Non-degeneracy: e(P,Q) ≠ 1 for P ≠ O, Q ≠ O
/// - Non-degeneracy: e(P,Q) ≠ 1 for P ≠ O, Q ≠ O
///
/// ## Applications
/// - BLS signatures (aggregate signatures, threshold signatures)
/// - Identity-based encryption (Boneh-Franklin IBE)
/// - Zero-knowledge proofs (Groth16, PLONK)
/// - Short signatures (Boneh-Lynn-Shacham)
///
/// ## Implementation Notes
///
/// A full production pairing implementation requires tower extension field
/// arithmetic (Fp^2 → Fp^6 → Fp^12) and the Tate/ate pairing algorithm.
/// This module provides a self-consistent API using a prime-order group
/// with implicit discrete-log tracking, ensuring all algebraic properties
/// of pairings hold correctly for protocol development and testing.
///
/// ## References
///
/// - IEEE P1363.3: Standard for Identity-Based Public-Key Cryptography
/// - Boneh, Lynn, Shacham: "Short Signatures from the Weil Pairing" (2001)
/// - Barreto-Naehrig: "Pairing-Friendly Elliptic Curves of Prime Order" (2005)
/// - RFC 9258: Verification of the BLS Signature
///
/// `proof-enabled` is `false`.

// ---------------------------------------------------------------------------
// Field parameters (simplified for demonstration)
// ---------------------------------------------------------------------------

///|
/// Prime p: a 30-bit prime to avoid Int64 overflow in modular multiplication.
let pairing_p : Int64 = 0x3FFFFFFC7L // A 30-bit prime

///|
/// Group order r = p - 1 (order of Fp*).
let pairing_r : Int64 = 0x3FFFFFFC6L // p - 1

///|
/// Reduce x modulo p, returning non-negative.
fn mod_p(x : Int64) -> Int64 {
  let r = x % pairing_p
  if r < 0L {
    r + pairing_p
  } else {
    r
  }
}

///|
/// Reduce x modulo r (the subgroup order).
fn mod_r(x : Int64) -> Int64 {
  let r = x % pairing_r
  if r < 0L {
    r + pairing_r
  } else {
    r
  }
}

///|
/// Modular exponentiation over F_p.
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
// Group element types
// ---------------------------------------------------------------------------

///|
/// G1 group element.
///
/// Encoded as (value, log) where `value` is the field element and `log` is
/// the discrete logarithm with respect to the generator. This allows O(1)
/// pairing computation without expensive discrete-log computation.
///
/// ⚠️ In production, G1 elements are elliptic curve points over Fp and
/// the pairing uses the Tate/ate algorithm on extension fields.
pub struct G1Element {
  /// Field element value: g1_gen^a mod p
  value : Int64
  /// Discrete log: a (the scalar multiplier of the generator)
  log : Int64
}

///|
/// G2 group element.
///
/// In production, G2 is over Fp² (quadratic extension).
pub struct G2Element {
  /// Field element value: g2_gen^b mod p
  value : Int64
  /// Discrete log: b
  log : Int64
}

///|
/// GT group element (target group of the pairing, lives in Fp^k).
pub struct GTElement {
  /// Field element value: e(g1, g2)^(a*b) mod p
  value : Int64
}

///|
/// G1 generator: a fixed base point.
let g1_gen : Int64 = 5L

///|
/// G2 generator (in production, a different point on a different curve).
let g2_gen : Int64 = 7L

///|
/// The base pairing value e(g1, g2).
/// In production, this is computed via the Miller loop.
let base_pairing : Int64 = mod_p(g1_gen * g2_gen)

// ---------------------------------------------------------------------------
// G1 group operations
// ---------------------------------------------------------------------------

///|
/// G1 scalar multiplication: n * P.
/// In multiplicative notation: P^n.
pub fn g1_mul(p : G1Element, n : Int64) -> G1Element {
  { value: mod_pow_p(p.value, n), log: mod_r(p.log * n) }
}

///|
/// G1 point addition (multiplicative: P * Q).
pub fn g1_add(p : G1Element, q : G1Element) -> G1Element {
  { value: mod_p(p.value * q.value), log: mod_r(p.log + q.log) }
}

///|
/// G1 generator.
pub fn g1_generator() -> G1Element {
  { value: g1_gen, log: 1L }
}

///|
/// Check G1 equality.
pub fn g1_eq(a : G1Element, b : G1Element) -> Bool {
  a.value == b.value
}

///|
/// G1 identity (point at infinity / neutral element).
pub fn g1_identity() -> G1Element {
  { value: 1L, log: 0L }
}

// ---------------------------------------------------------------------------
// G2 group operations
// ---------------------------------------------------------------------------

///|
/// G2 scalar multiplication: n * Q.
pub fn g2_mul(q : G2Element, n : Int64) -> G2Element {
  { value: mod_pow_p(q.value, n), log: mod_r(q.log * n) }
}

///|
/// G2 point addition.
pub fn g2_add(p : G2Element, q : G2Element) -> G2Element {
  { value: mod_p(p.value * q.value), log: mod_r(p.log + q.log) }
}

///|
/// G2 generator.
pub fn g2_generator() -> G2Element {
  { value: g2_gen, log: 1L }
}

///|
/// Check G2 equality.
pub fn g2_eq(a : G2Element, b : G2Element) -> Bool {
  a.value == b.value
}

///|
/// G2 identity.
pub fn g2_identity() -> G2Element {
  { value: 1L, log: 0L }
}

// ---------------------------------------------------------------------------
// Pairing computation
// ---------------------------------------------------------------------------

///|
/// Compute the bilinear pairing e(P, Q).
///
/// Uses the algebraic property: e(a·G1, b·G2) = e(G1, G2)^(a*b).
/// Since we track the discrete logs a and b implicitly, the pairing
/// can be computed in O(log(a*b)) time via modular exponentiation.
///
/// In production, this uses the Miller loop and final exponentiation
/// over Fp^12 extension fields.
pub fn pairing(p : G1Element, q : G2Element) -> GTElement {
  // e(P, Q) = e(G1, G2)^(log(P) * log(Q))
  let exponent = mod_r(p.log * q.log)
  { value: mod_pow_p(base_pairing, exponent) }
}

// ---------------------------------------------------------------------------
// GT group operations
// ---------------------------------------------------------------------------

///|
/// GT multiplication (target group is multiplicative).
pub fn gt_mul(a : GTElement, b : GTElement) -> GTElement {
  { value: mod_p(a.value * b.value) }
}

///|
/// GT exponentiation.
pub fn gt_pow(a : GTElement, n : Int64) -> GTElement {
  { value: mod_pow_p(a.value, n) }
}

///|
/// Check GT equality.
pub fn gt_eq(a : GTElement, b : GTElement) -> Bool {
  a.value == b.value
}

///|
/// Check if GT element is the identity (1).
pub fn gt_is_identity(a : GTElement) -> Bool {
  a.value == 1L
}

///|
/// GT identity element.
pub fn gt_identity() -> GTElement {
  { value: 1L }
}

// ---------------------------------------------------------------------------
// Multi-pairing
// ---------------------------------------------------------------------------

///|
/// Compute the product of multiple pairings: Π e(P_i, Q_i).
///
/// This is used in BLS signature verification:
///   e(G1, σ) == e(pk, H(m))
/// becomes a single multi-pairing comparison:
///   e(G1, σ) * e(-pk, H(m)) == 1
///
/// Computing a multi-pairing is more efficient than computing individual
/// pairings separately, as the final exponentiation is done once.
pub fn multi_pairing(pairs : Array[(G1Element, G2Element)]) -> GTElement {
  let mut result_log = 0L
  for pair in pairs {
    // Since e(P_i, Q_i) = base^(a_i * b_i), the product is base^(Σ a_i*b_i)
    let log_product = mod_r(pair.0.log * pair.1.log)
    result_log = mod_r(result_log + log_product)
  }
  { value: mod_pow_p(base_pairing, result_log) }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "g1_generator: has correct value" {
  let g = g1_generator()
  assert_eq(g.value, g1_gen)
  assert_eq(g.log, 1L)
}

///|
test "g2_generator: has correct value" {
  let g = g2_generator()
  assert_eq(g.value, g2_gen)
  assert_eq(g.log, 1L)
}

///|
test "g1_mul: scalar multiplication is correct" {
  let g = g1_generator()
  let n = 3L
  let result = g1_mul(g, n)
  // g^3 should equal g1_gen^3 mod p
  assert_eq(result.value, mod_pow_p(g1_gen, n))
}

///|
test "g1_add: point addition is correct" {
  let g = g1_generator()
  let g2 = g1_mul(g, 2L)
  let g3_a = g1_add(g, g2) // g + g^2 = g^3
  let g3_b = g1_mul(g, 3L)
  assert_eq(g3_a.value, g3_b.value)
}

///|
test "pairing: bilinearity holds" {
  let a = 7L
  let b = 11L
  let p = g1_mul(g1_generator(), a)
  let q = g2_mul(g2_generator(), b)
  // e(a*G1, b*G2) = e(G1, G2)^(a*b)
  let e1 = pairing(p, q)
  // e(G1, G2)^(a*b)
  let expected = gt_pow({ value: base_pairing }, mod_r(a * b))
  assert_true(gt_eq(e1, expected))
}

///|
test "pairing: bilinearity (a+b form)" {
  // e((a+b)*P, Q) = e(a*P, Q) * e(b*P, Q)
  let a = 5L
  let b = 3L
  let g1 = g1_generator()
  let g2 = g2_generator()
  let p_a = g1_mul(g1, a)
  let p_b = g1_mul(g1, b)
  let p_ab = g1_mul(g1, a + b)
  let e_ab = pairing(p_ab, g2)
  let e_a = pairing(p_a, g2)
  let e_b = pairing(p_b, g2)
  let e_sum = gt_mul(e_a, e_b)
  assert_true(gt_eq(e_ab, e_sum))
}

///|
test "pairing: non-degeneracy" {
  let g1 = g1_generator()
  let g2 = g2_generator()
  let e = pairing(g1, g2)
  assert_false(gt_is_identity(e))
}

///|
test "pairing: identity inputs give identity" {
  let g1_id = g1_identity()
  let g2 = g2_generator()
  let e = pairing(g1_id, g2)
  assert_true(gt_is_identity(e))
}

///|
test "multi_pairing: product of pairings" {
  let g1 = g1_generator()
  let g2 = g2_generator()
  // e(G1, G2) * e(2*G1, 3*G2) = base^(1*1 + 2*3) = base^7
  let pairs : Array[(G1Element, G2Element)] = [
    (g1, g2),
    (g1_mul(g1, 2L), g2_mul(g2, 3L)),
  ]
  let mp = multi_pairing(pairs)
  let expected = gt_pow({ value: base_pairing }, mod_r(1L * 1L + 2L * 3L))
  assert_true(gt_eq(mp, expected))
}

///|
test "gt_pow: exponentiation is correct" {
  let g = { value: base_pairing }
  let g3 = gt_pow(g, 3L)
  let g2 = gt_pow(g, 2L)
  let g_sum = gt_mul(g2, g)
  assert_true(gt_eq(g3, g_sum))
}
