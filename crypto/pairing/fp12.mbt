/// BLS12-381 Degree-12 Extension Field (Fp12)
///
/// Fp12 = Fp6[w]/(w^2 - v), so w^2 = v.
/// The nonresidue for Fp12/Fp6 is v, which is the Fp6 element {0, 1, 0}.
/// Elements are (c0, c1) representing c0 + c1*w.

///|
/// Fp12 element: c0 + c1*w where w^2 = v (the Fp6 nonresidue)
pub struct Fp12 {
  c0 : Fp6
  c1 : Fp6
}

///|
pub fn fp12_zero() -> Fp12 {
  { c0: fp6_zero(), c1: fp6_zero() }
}

///|
pub fn fp12_one() -> Fp12 {
  { c0: fp6_one(), c1: fp6_zero() }
}

///|
pub fn fp12_add(a : Fp12, b : Fp12) -> Fp12 {
  { c0: fp6_add(a.c0, b.c0), c1: fp6_add(a.c1, b.c1) }
}

///|
pub fn fp12_sub(a : Fp12, b : Fp12) -> Fp12 {
  { c0: fp6_sub(a.c0, b.c0), c1: fp6_sub(a.c1, b.c1) }
}

///|
/// The nonresidue v for Fp12/Fp6, as an Fp6 element: {0, 1, 0}
fn fp12_nonresidue_v() -> Fp6 {
  { c0: fp2_zero(), c1: fp2_one(), c2: fp2_zero() }
}

///|
/// Fp12 multiplication: (a0+a1*w)(b0+b1*w) = a0*b0 + a1*b1*v + (a0*b1+a1*b0)*w
pub fn fp12_mul(a : Fp12, b : Fp12) -> Fp12 {
  let v_elem = fp12_nonresidue_v()
  let a0b0 = fp6_mul(a.c0, b.c0)
  let a1b1 = fp6_mul(a.c1, b.c1)
  let c0 = fp6_add(a0b0, fp6_mul(a1b1, v_elem))
  let c1 = fp6_add(fp6_mul(a.c0, b.c1), fp6_mul(a.c1, b.c0))
  { c0, c1 }
}

///|
pub fn fp12_sqr(a : Fp12) -> Fp12 {
  fp12_mul(a, a)
}

///|
pub fn fp12_eq(a : Fp12, b : Fp12) -> Bool {
  fp6_eq(a.c0, b.c0) && fp6_eq(a.c1, b.c1)
}

///|
/// Fp12 inverse: (a0+a1*w)^(-1) = (a0-a1*w) / (a0^2 - a1^2*v)
pub fn fp12_inv(a : Fp12) -> Fp12 {
  let v_elem = fp12_nonresidue_v()
  let a0_sqr = fp6_sqr(a.c0)
  let a1_sqr = fp6_sqr(a.c1)
  let denom = fp6_sub(a0_sqr, fp6_mul(a1_sqr, v_elem))
  let denom_inv = fp6_inv(denom)
  { c0: fp6_mul(a.c0, denom_inv), c1: fp6_mul(fp6_neg(a.c1), denom_inv) }
}

///|
/// Fp12 conjugate (in Fp12/Fp6): (a0+a1*w) -> (a0-a1*w)
pub fn fp12_conjugate(a : Fp12) -> Fp12 {
  { c0: a.c0, c1: fp6_neg(a.c1) }
}

///|
/// Fp12 exponentiation (square-and-multiply)
pub fn fp12_pow(a : Fp12, exp : @bigint.BigInt) -> Fp12 {
  let mut result = fp12_one()
  let mut base = a
  let mut e = exp
  let zero = @bigint.zero()
  while @bigint.compare(e, zero) > 0 {
    if @bigint.is_odd(e) {
      result = fp12_mul(result, base)
    }
    base = fp12_sqr(base)
    e = @bigint.shr(e, 1)
  }
  result
}

///|
/// Fp12 Frobenius map (p-power): x -> x^p
pub fn fp12_frobenius(a : Fp12) -> Fp12 {
  fp12_pow(a, bls_p)
}

///|
/// Multiply Fp12 by the sparse element c0 + c1·v + c2·v·w, which in the
/// Fp2-slot layout (c0.c0, c0.c1, c0.c2, c1.c0, c1.c1, c1.c2) occupies
/// slots 0, 1, 4 — hence "mul_by_014" (zkcrypto convention).
pub fn fp12_mul_by_014(f : Fp12, c0 : Fp2, c1 : Fp2, c2 : Fp2) -> Fp12 {
  // sparse = (c0 + c1·v) + (c2·v)·w
  let sparse_c0 : Fp6 = { c0, c1, c2: fp2_zero() }
  let sparse_c1 : Fp6 = { c0: fp2_zero(), c1: c2, c2: fp2_zero() }
  let sparse : Fp12 = { c0: sparse_c0, c1: sparse_c1 }
  fp12_mul(f, sparse)
}
