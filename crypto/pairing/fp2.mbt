/// BLS12-381 Quadratic Extension Field (Fp2)
///
/// Fp2 = Fp[u]/(u^2 + 1), so u^2 = -1.
/// Elements are (c0, c1) representing c0 + c1*u.

///|
/// Fp2 element: c0 + c1*u where u^2 = -1
pub struct Fp2 {
  c0 : @bigint.BigInt
  c1 : @bigint.BigInt
}

///|
pub fn fp2_zero() -> Fp2 {
  { c0: @bigint.zero(), c1: @bigint.zero() }
}

///|
pub fn fp2_one() -> Fp2 {
  { c0: @bigint.one(), c1: @bigint.zero() }
}

///|
pub fn fp2_from_fp(s : @bigint.BigInt) -> Fp2 {
  { c0: s, c1: @bigint.zero() }
}

///|
pub fn fp2_add(a : Fp2, b : Fp2) -> Fp2 {
  { c0: fp_add(a.c0, b.c0), c1: fp_add(a.c1, b.c1) }
}

///|
pub fn fp2_sub(a : Fp2, b : Fp2) -> Fp2 {
  { c0: fp_sub(a.c0, b.c0), c1: fp_sub(a.c1, b.c1) }
}

///|
/// Fp2 multiplication: (a0+a1*u)(b0+b1*u) = (a0*b0 - a1*b1) + (a0*b1 + a1*b0)*u
pub fn fp2_mul(a : Fp2, b : Fp2) -> Fp2 {
  let c0 = fp_sub(fp_mul(a.c0, b.c0), fp_mul(a.c1, b.c1))
  let c1 = fp_add(fp_mul(a.c0, b.c1), fp_mul(a.c1, b.c0))
  { c0, c1 }
}

///|
/// Fp2 squaring: (a0+a1*u)^2 = (a0^2 - a1^2) + 2*a0*a1*u
pub fn fp2_sqr(a : Fp2) -> Fp2 {
  let a0_sqr = fp_sqr(a.c0)
  let a1_sqr = fp_sqr(a.c1)
  let two_a0 = fp_add(a.c0, a.c0)
  { c0: fp_sub(a0_sqr, a1_sqr), c1: fp_mul(two_a0, a.c1) }
}

///|
pub fn fp2_neg(a : Fp2) -> Fp2 {
  { c0: fp_sub(@bigint.zero(), a.c0), c1: fp_sub(@bigint.zero(), a.c1) }
}

///|
/// Fp2 inverse: (a0+a1*u)^(-1) = (a0 - a1*u) / (a0^2 + a1^2)
pub fn fp2_inv(a : Fp2) -> Fp2 {
  let t0 = fp_sqr(a.c0)
  let t1 = fp_sqr(a.c1)
  let denom = fp_add(t0, t1)
  let denom_inv = fp_inv(denom)
  { c0: fp_mul(a.c0, denom_inv), c1: fp_mul(fp_sub(@bigint.zero(), a.c1), denom_inv) }
}

///|
pub fn fp2_eq(a : Fp2, b : Fp2) -> Bool {
  @bigint.equal(a.c0, b.c0) && @bigint.equal(a.c1, b.c1)
}

///|
/// Fp2 Frobenius (conjugation): (a0+a1*u) -> (a0-a1*u)
pub fn fp2_conjugate(a : Fp2) -> Fp2 {
  { c0: a.c0, c1: fp_sub(@bigint.zero(), a.c1) }
}

///|
/// Fp2 scalar multiplication by an Fp element
pub fn fp2_mul_fp(a : Fp2, s : @bigint.BigInt) -> Fp2 {
  { c0: fp_mul(a.c0, s), c1: fp_mul(a.c1, s) }
}

///|
/// Multiply Fp2 by u (the nonresidue): a*u = -a.c1 + a.c0*u
pub fn fp2_mul_u(a : Fp2) -> Fp2 {
  { c0: fp_sub(@bigint.zero(), a.c1), c1: a.c0 }
}

///|
/// Fp2 is zero
pub fn fp2_is_zero(a : Fp2) -> Bool {
  @bigint.equal(a.c0, @bigint.zero()) && @bigint.equal(a.c1, @bigint.zero())
}

///|
/// Fp2 equality to one
pub fn fp2_is_one(a : Fp2) -> Bool {
  @bigint.equal(a.c0, @bigint.one()) && @bigint.equal(a.c1, @bigint.zero())
}
