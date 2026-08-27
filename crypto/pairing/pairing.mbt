/// Bilinear Pairings — BLS12-381 Optimal Ate Pairing
///
/// Production implementation of the optimal ate pairing on the BLS12-381
/// elliptic curve. This module provides:
///
/// - **Fp**: Base field arithmetic modulo the 381-bit BLS12-381 prime
/// - **Fp2**: Quadratic extension field (used by G2 and the twist)
/// - **Fp6**: Sextic extension field (building block for Fp12)
/// - **Fp12**: Degree-12 extension field (target group GT)
/// - **G1**: Elliptic curve group y² = x³ + 4 over Fp
/// - **G2**: Elliptic curve group y² = x³ + 4(1+u) over Fp² (twist)
/// - **Optimal Ate Pairing**: Miller loop + final exponentiation
///
/// ## BLS12-381 Parameters
///
/// - Base field prime p = 0x1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab
/// - Scalar field order r = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001
/// - BLS parameter x = -0xd201000000010000 (used in Miller loop)
/// - Embedding degree k = 12
/// - G1 curve: y² = x³ + 4 (b = 4)
/// - G2 twist: y² = x³ + 4(1+u) (b' = 4(1+u), D-type twist with β = -1)
/// - Fp² nonresidue: u² = -1 (i.e., β = -1)
///
/// ## References
///
/// - Boneh, Lynn, Shacham: "Short Signatures from the Weil Pairing" (2001)
/// - Barreto-Naehrig: "Pairing-Friendly Elliptic Curves of Prime Order" (2005)
/// - Aranha et al.: "A Note on the Implementation of the Ate Pairing" (2010)
/// - https://github.com/zkcrypto/bls12_381 (reference Rust implementation)

// All implementation details are in the split files:
// - fp.mbt: Base field Fp arithmetic
// - fp2.mbt: Quadratic extension Fp2
// - fp6.mbt: Sextic extension Fp6
// - fp12.mbt: Degree-12 extension Fp12
// - g1.mbt: G1 elliptic curve group
// - g2.mbt: G2 elliptic curve group (twist)
// - miller.mbt: Miller loop and final exponentiation

///|
/// Compute the pairing of a G1 point and a G2 point.
/// This is the main entry point for the optimal ate pairing.
///
/// e: G1 × G2 → GT ⊂ Fp12*
///
/// Properties:
/// - Bilinearity: e(aP, Q) = e(P, Q)^a = e(P, aQ)
/// - Non-degeneracy: e(P, Q) ≠ 1 for P, Q ≠ O
/// - Identity: e(O, Q) = e(P, O) = 1
pub fn optimal_ate(p : G1Point, q : G2Point) -> Fp12 {
  pairing(p, q)
}

///|
test "bls12_381 — G1 generator is on curve" {
  let g = g1_generator()
  let (x, y) = g1_to_affine(g)
  assert_true(g1_is_on_curve(x, y))
}

///|
test "bls12_381 — G2 generator is on curve" {
  let g = g2_generator()
  let (x, y) = g2_to_affine(g)
  assert_true(g2_is_on_curve(x, y))
}

///|
test "bls12_381 — G1 generator has order r" {
  // [r] * G1 = O (point at infinity)
  let g = g1_generator()
  let result = g1_scalar_mul(bls_r, g)
  assert_true(g1_is_identity(result))
}

///|
test "bls12_381 — G2 generator has order r" {
  // [r] * G2 = O (point at infinity)
  let g = g2_generator()
  let result = g2_scalar_mul(bls_r, g)
  assert_true(g2_is_identity(result))
}

///|
test "bls12_381 — G1 doubling: 2G = G + G" {
  let g = g1_generator()
  let g2 = g1_double(g)
  let g_add = g1_add(g, g)
  assert_true(g1_eq(g2, g_add))
}

///|
test "bls12_381 — G2 doubling: 2G = G + G" {
  let g = g2_generator()
  let g2_dbl = g2_double(g)
  let g2_add = g2_add(g, g)
  assert_true(g2_eq(g2_dbl, g2_add))
}

///|
test "bls12_381 — G1 negation: G + (-G) = O" {
  let g = g1_generator()
  let neg_g = g1_neg(g)
  let result = g1_add(g, neg_g)
  assert_true(g1_is_identity(result))
}

///|
test "bls12_381 — G2 negation: G + (-G) = O" {
  let g = g2_generator()
  let neg_g = g2_neg(g)
  let result = g2_add(g, neg_g)
  assert_true(g2_is_identity(result))
}

///|
test "bls12_381 — Fp2 arithmetic: u^2 = -1" {
  // u = (0, 1), u^2 should be (-1, 0)
  let u : Fp2 = { c0: @bigint.zero(), c1: @bigint.one() }
  let u2 = fp2_sqr(u)
  let neg_one : Fp2 = {
    c0: fp_sub(@bigint.zero(), @bigint.one()),
    c1: @bigint.zero(),
  }
  assert_true(fp2_eq(u2, neg_one))
}

///|
test "bls12_381 — Fp2 inverse: a * a^(-1) = 1" {
  let a = g2_gx() // Use G2 generator x as a test value
  let a_inv = fp2_inv(a)
  let product = fp2_mul(a, a_inv)
  assert_true(fp2_is_one(product))
}

///|
test "bls12_381 — Fp12 multiplication: 1 * a = a" {
  let one = fp12_one()
  let a = fp12_add(fp12_one(), fp12_one()) // 2 in Fp12
  let result = fp12_mul(one, a)
  assert_true(fp12_eq(result, a))
}

///|
test "bls12_381 — Fp12 inverse: a * a^(-1) = 1" {
  // Create a non-trivial Fp12 element
  let a : Fp12 = {
    c0: {
      c0: { c0: @bigint.from_int_value(3), c1: @bigint.from_int_value(5) },
      c1: { c0: @bigint.from_int_value(7), c1: @bigint.from_int_value(11) },
      c2: { c0: @bigint.from_int_value(13), c1: @bigint.from_int_value(17) },
    },
    c1: {
      c0: { c0: @bigint.from_int_value(19), c1: @bigint.from_int_value(23) },
      c1: { c0: @bigint.from_int_value(29), c1: @bigint.from_int_value(31) },
      c2: { c0: @bigint.from_int_value(37), c1: @bigint.from_int_value(41) },
    },
  }
  let a_inv = fp12_inv(a)
  let product = fp12_mul(a, a_inv)
  assert_true(fp12_eq(product, fp12_one()))
}

///|
test "bls12_381 — Pairing non-degeneracy: e(G1, G2) ≠ 1" {
  let p = g1_generator()
  let q = g2_generator()
  let result = optimal_ate(p, q)
  // e(G1, G2) should NOT be the identity in GT
  assert_false(fp12_eq(result, fp12_one()))
}

///|
test "bls12_381 — Pairing bilinearity: e(aP, Q) = e(P, Q)^a" {
  let a = @bigint.from_int_value(7)
  let p = g1_generator()
  let q = g2_generator()
  // e(aP, Q)
  let ap = g1_scalar_mul(a, p)
  let lhs = optimal_ate(ap, q)
  // e(P, Q)^a
  let pq = optimal_ate(p, q)
  let rhs = fp12_pow(pq, a)
  assert_true(fp12_eq(lhs, rhs))
}

///|
test "bls12_381 — Pairing bilinearity: e(P, aQ) = e(P, Q)^a" {
  let a = @bigint.from_int_value(7)
  let p = g1_generator()
  let q = g2_generator()
  // e(P, aQ)
  let aq = g2_scalar_mul(a, q)
  let lhs = optimal_ate(p, aq)
  // e(P, Q)^a
  let pq = optimal_ate(p, q)
  let rhs = fp12_pow(pq, a)
  assert_true(fp12_eq(lhs, rhs))
}

///|
test "bls12_381 — Pairing identity: e(O, Q) = 1" {
  let o = g1_identity()
  let q = g2_generator()
  let result = optimal_ate(o, q)
  assert_true(fp12_eq(result, fp12_one()))
}

///|
test "bls12_381 — Pairing identity: e(P, O) = 1" {
  let p = g1_generator()
  let o = g2_identity()
  let result = optimal_ate(p, o)
  assert_true(fp12_eq(result, fp12_one()))
}
