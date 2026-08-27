/// BLS12-381 G1 Group: Elliptic Curve y^2 = x^3 + 4 over Fp
///
/// Using Jacobian projective coordinates (X, Y, Z) where x = X/Z, y = Y/Z.
/// This provides efficient addition and doubling without field inversions.

///|
/// G1 curve coefficient b = 4
pub let g1_b : @bigint.BigInt = @bigint.from_int_value(4)

///|
/// G1 generator x-coordinate (BLS12-381 standard, EIP-2537).
/// x limbs (little-endian u64): [0xfb3af00adb22c6bb, 0x6c55e83ff97a1aef,
/// 0xa14e3a3f171bac58, 0xc3688c4f9774b905, 0x2695638c4fa9ac0f, 0x17f1d3a73197d794]
pub let g1_gx : @bigint.BigInt = match
  @bigint.from_string(
    "0x17f1d3a73197d7942695638c4fa9ac0fc3688c4f9774b905a14e3a3f171bac586c55e83ff97a1aeffb3af00adb22c6bb",
  ) {
  Some(v) => v
  None => abort("FATAL: invalid G1 generator x")
}

///|
/// G1 generator y-coordinate (BLS12-381 standard, EIP-2537).
/// y limbs (little-endian u64): [0x0caa232946c5e7e1, 0xd03cc744a2888ae4,
/// 0x00db18cb2c04b3ed, 0xfcf5e095d5d00af6, 0xa09e30ed741d8ae4, 0x08b3f481e3aaa0f1]
pub let g1_gy : @bigint.BigInt = match
  @bigint.from_string(
    "0x08b3f481e3aaa0f1a09e30ed741d8ae4fcf5e095d5d00af600db18cb2c04b3edd03cc744a2888ae40caa232946c5e7e1",
  ) {
  Some(v) => v
  None => abort("FATAL: invalid G1 generator y")
}

///|
/// G1 point in Jacobian projective coordinates (X, Y, Z)
pub struct G1Point {
  x : @bigint.BigInt
  y : @bigint.BigInt
  z : @bigint.BigInt
}

///|
/// G1 point at infinity (identity element): (0, 1, 0)
pub fn g1_identity() -> G1Point {
  { x: @bigint.zero(), y: @bigint.one(), z: @bigint.zero() }
}

///|
pub fn g1_is_identity(p : G1Point) -> Bool {
  @bigint.equal(p.z, @bigint.zero())
}

///|
/// G1 generator point
pub fn g1_generator() -> G1Point {
  { x: g1_gx, y: g1_gy, z: @bigint.one() }
}

///|
/// Construct a G1 point from affine coordinates (x, y).
/// The caller is responsible for ensuring the point is on the curve.
pub fn g1_from_affine(x : @bigint.BigInt, y : @bigint.BigInt) -> G1Point {
  { x, y, z: @bigint.one() }
}

///|
/// G1 point doubling for a = 0 (y^2 = x^3 + b)
/// dbl-2001-b (Jacobian, a = 0):
/// A = X^2; B = Y^2; C = B^2; D = 2((X+B)^2 - A - C)
/// E = 3*A; F = E^2
/// X3 = F - 2D; Y3 = E(D - X3) - 8C; Z3 = 2*Y*Z
pub fn g1_double(p : G1Point) -> G1Point {
  if g1_is_identity(p) {
    return p
  }
  if @bigint.equal(p.y, @bigint.zero()) {
    return g1_identity()
  }
  let a = fp_sqr(p.x) // A = X^2
  let b = fp_sqr(p.y) // B = Y^2
  let c = fp_sqr(b) // C = B^2 = Y^4
  let xpb = fp_add(p.x, b)
  let d = fp_sub(fp_sub(fp_sqr(xpb), a), c) // (X+B)^2 - A - C
  let d = fp_add(d, d) // D = 2 * ((X+B)^2 - A - C)
  let three = @bigint.from_int_value(3)
  let e = fp_mul(three, a) // E = 3*A
  let f = fp_sqr(e) // F = E^2
  let two_d = fp_add(d, d)
  let x3 = fp_sub(f, two_d) // X3 = F - 2*D
  let d_x3 = fp_sub(d, x3)
  let eight_c = {
    let two_c = fp_add(c, c)
    let four_c = fp_add(two_c, two_c)
    fp_add(four_c, four_c)
  }
  let y3 = fp_sub(fp_mul(e, d_x3), eight_c) // Y3 = E*(D - X3) - 8*C
  let z3 = fp_mul(fp_add(p.y, p.y), p.z) // Z3 = 2*Y*Z
  { x: x3, y: y3, z: z3 }
}

///|
/// G1 point addition (Jacobian + Jacobian)
/// add-2007-bl
pub fn g1_add(p : G1Point, q : G1Point) -> G1Point {
  if g1_is_identity(p) {
    return q
  }
  if g1_is_identity(q) {
    return p
  }
  let z1z1 = fp_sqr(p.z) // Z1Z1 = Z1^2
  let z2z2 = fp_sqr(q.z) // Z2Z2 = Z2^2
  let u1 = fp_mul(p.x, z2z2) // U1 = X1*Z2^2
  let u2 = fp_mul(q.x, z1z1) // U2 = X2*Z1^2
  let s1 = fp_mul(fp_mul(p.y, q.z), z2z2) // S1 = Y1*Z2^3
  let s2 = fp_mul(fp_mul(q.y, p.z), z1z1) // S2 = Y2*Z1^3
  if @bigint.equal(u1, u2) {
    if @bigint.equal(s1, s2) {
      return g1_double(p)
    } else {
      return g1_identity()
    }
  }
  let h = fp_sub(u2, u1) // H = U2 - U1
  let i = {
    let hh = fp_sqr(h) // HH = H^2
    let two_hh = fp_add(hh, hh)
    fp_add(two_hh, two_hh) // I = 4*HH
  }
  let j = fp_mul(h, i) // J = H*I
  let r = {
    let diff = fp_sub(s2, s1) // S2 - S1
    fp_add(diff, diff) // r = 2*(S2-S1)
  }
  let v = fp_mul(u1, i) // V = U1*I
  let x3 = {
    let r_sqr = fp_sqr(r)
    let two_v = fp_add(v, v)
    fp_sub(fp_sub(r_sqr, j), two_v) // X3 = r^2 - J - 2*V
  }
  let y3 = {
    let r_v_x3 = fp_mul(r, fp_sub(v, x3))
    let two_s1j = fp_add(fp_mul(s1, j), fp_mul(s1, j))
    fp_sub(r_v_x3, two_s1j) // Y3 = r*(V - X3) - 2*S1*J
  }
  let two = @bigint.from_int_value(2)
  let z1z2 = fp_mul(p.z, q.z)
  let z3 = fp_mul(fp_mul(two, z1z2), h) // Z3 = 2*Z1*Z2*H
  { x: x3, y: y3, z: z3 }
}

///|
/// G1 scalar multiplication (double-and-add)
pub fn g1_scalar_mul(k : @bigint.BigInt, p : G1Point) -> G1Point {
  let mut result = g1_identity()
  let mut base = p
  let mut e = k
  let zero = @bigint.zero()
  while @bigint.compare(e, zero) > 0 {
    if @bigint.is_odd(e) {
      result = g1_add(result, base)
    }
    base = g1_double(base)
    e = @bigint.shr(e, 1)
  }
  result
}

///|
/// Convert G1 Jacobian to affine (x, y)
pub fn g1_to_affine(p : G1Point) -> (@bigint.BigInt, @bigint.BigInt) {
  if g1_is_identity(p) {
    return (@bigint.zero(), @bigint.zero())
  }
  let z_inv = fp_inv(p.z)
  let z_inv2 = fp_sqr(z_inv)
  let x = fp_mul(p.x, z_inv2)
  let y = fp_mul(p.y, fp_mul(z_inv, z_inv2))
  (x, y)
}

///|
/// Check if a point (x, y) is on the curve y^2 = x^3 + 4
pub fn g1_is_on_curve(x : @bigint.BigInt, y : @bigint.BigInt) -> Bool {
  let lhs = fp_sqr(y)
  let rhs = fp_add(fp_mul(fp_sqr(x), x), g1_b)
  @bigint.equal(lhs, rhs)
}

///|
/// G1 point equality (after converting to affine)
pub fn g1_eq(p : G1Point, q : G1Point) -> Bool {
  if g1_is_identity(p) && g1_is_identity(q) {
    return true
  }
  if g1_is_identity(p) || g1_is_identity(q) {
    return false
  }
  let (px, py) = g1_to_affine(p)
  let (qx, qy) = g1_to_affine(q)
  @bigint.equal(px, qx) && @bigint.equal(py, qy)
}

///|
/// G1 negation: (X, Y, Z) -> (X, -Y, Z)
pub fn g1_neg(p : G1Point) -> G1Point {
  { x: p.x, y: fp_sub(@bigint.zero(), p.y), z: p.z }
}
