/// BLS12-381 Sextic Extension Field (Fp6)
///
/// Fp6 = Fp2[v]/(v^3 - (u+1)), so v^3 = u+1.
/// The nonresidue for Fp6/Fp2 is (u+1), which as an Fp2 element is {c0: 1, c1: 1}.
/// Elements are (c0, c1, c2) representing c0 + c1*v + c2*v^2.

///|
/// Fp6 element: c0 + c1*v + c2*v^2 where v^3 = u+1
pub struct Fp6 {
  c0 : Fp2
  c1 : Fp2
  c2 : Fp2
}

///|
pub fn fp6_zero() -> Fp6 {
  { c0: fp2_zero(), c1: fp2_zero(), c2: fp2_zero(), }
}

///|
pub fn fp6_one() -> Fp6 {
  { c0: fp2_one(), c1: fp2_zero(), c2: fp2_zero(), }
}

///|
pub fn fp6_add(a : Fp6, b : Fp6) -> Fp6 {
  { c0: fp2_add(a.c0, b.c0), c1: fp2_add(a.c1, b.c1), c2: fp2_add(a.c2, b.c2), }
}

///|
pub fn fp6_sub(a : Fp6, b : Fp6) -> Fp6 {
  { c0: fp2_sub(a.c0, b.c0), c1: fp2_sub(a.c1, b.c1), c2: fp2_sub(a.c2, b.c2), }
}

///|
/// The nonresidue for Fp6/Fp2 is (u+1), which in Fp2 is {c0: 1, c1: 1}
pub fn fp6_nonresidue() -> Fp2 {
  { c0: @bigint.one(), c1: @bigint.one(), }
}

///|
/// Fp6 multiplication: schoolbook with reduction by v^3 = (u+1)
pub fn fp6_mul(a : Fp6, b : Fp6) -> Fp6 {
  let nr = fp6_nonresidue()
  let a0b0 = fp2_mul(a.c0, b.c0)
  let a1b1 = fp2_mul(a.c1, b.c1)
  let a2b2 = fp2_mul(a.c2, b.c2)
  // c0 = a0*b0 + (a1*b2 + a2*b1)*nr
  let a1b2 = fp2_mul(a.c1, b.c2)
  let a2b1 = fp2_mul(a.c2, b.c1)
  let c0 = fp2_add(a0b0, fp2_mul(fp2_add(a1b2, a2b1), nr))
  // c1 = a0*b1 + a1*b0 + a2*b2*nr
  let a0b1 = fp2_mul(a.c0, b.c1)
  let a1b0 = fp2_mul(a.c1, b.c0)
  let c1 = fp2_add(fp2_add(a0b1, a1b0), fp2_mul(a2b2, nr))
  // c2 = a0*b2 + a1*b1 + a2*b0
  let a0b2 = fp2_mul(a.c0, b.c2)
  let a2b0 = fp2_mul(a.c2, b.c0)
  let c2 = fp2_add(fp2_add(a0b2, a1b1), a2b0)
  { c0, c1, c2, }
}

///|
pub fn fp6_sqr(a : Fp6) -> Fp6 {
  fp6_mul(a, a)
}

///|
pub fn fp6_neg(a : Fp6) -> Fp6 {
  { c0: fp2_neg(a.c0), c1: fp2_neg(a.c1), c2: fp2_neg(a.c2), }
}

///|
pub fn fp6_eq(a : Fp6, b : Fp6) -> Bool {
  fp2_eq(a.c0, b.c0) && fp2_eq(a.c1, b.c1) && fp2_eq(a.c2, b.c2)
}

///|
/// Fp6 inverse via the norm in Fp6/Fp2
/// For a = c0 + c1*v + c2*v^2 with v^3 = nr:
/// det = c0^3 + nr*c1^3 + nr^2*c2^3 - 3*nr*c0*c1*c2
/// a^{-1} = ((c0^2 - nr*c1*c2) + (nr*c2^2 - c0*c1)*v + (c1^2 - c0*c2)*v^2) / det
pub fn fp6_inv(a : Fp6) -> Fp6 {
  let nr = fp6_nonresidue()
  let c0 = a.c0
  let c1 = a.c1
  let c2 = a.c2
  let c0_sqr = fp2_sqr(c0)
  let c1_sqr = fp2_sqr(c1)
  let c2_sqr = fp2_sqr(c2)
  let c0_c1 = fp2_mul(c0, c1)
  let c0_c2 = fp2_mul(c0, c2)
  let c1_c2 = fp2_mul(c1, c2)
  let c0_cube = fp2_mul(c0_sqr, c0)
  let c1_cube = fp2_mul(c1_sqr, c1)
  let c2_cube = fp2_mul(c2_sqr, c2)
  let nr_c1_cube = fp2_mul(nr, c1_cube)
  let nr_sqr = fp2_sqr(nr)
  let nr_sqr_c2_cube = fp2_mul(nr_sqr, c2_cube)
  let three = @bigint.from_int_value(3)
  let nr_3_c0c1c2 = fp2_mul(fp2_mul(nr, c0_c1), c2)
  let nr_3_c0c1c2_scaled = fp2_mul_fp(nr_3_c0c1c2, three)
  let det = fp2_sub(
    fp2_add(fp2_add(c0_cube, nr_c1_cube), nr_sqr_c2_cube),
    nr_3_c0c1c2_scaled,
  )
  let det_inv = fp2_inv(det)
  let b0 = fp2_mul(fp2_sub(c0_sqr, fp2_mul(nr, c1_c2)), det_inv)
  let b1 = fp2_mul(fp2_sub(fp2_mul(nr, c2_sqr), c0_c1), det_inv)
  let b2 = fp2_mul(fp2_sub(c1_sqr, c0_c2), det_inv)
  { c0: b0, c1: b1, c2: b2, }
}

///|
/// Fp6 scalar multiplication (multiply by an Fp2 element)
pub fn fp6_mul_fp2(a : Fp6, s : Fp2) -> Fp6 {
  { c0: fp2_mul(a.c0, s), c1: fp2_mul(a.c1, s), c2: fp2_mul(a.c2, s), }
}
