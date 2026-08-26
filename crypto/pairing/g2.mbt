/// BLS12-381 G2 Group: Elliptic Curve y^2 = x^3 + 4(1+u) over Fp2
///
/// G2 is the subgroup of the twist of the BLS12-381 curve over Fp2.
/// The twist is D-type with the twisting isomorphism from E'(Fp2) to E(Fp6).
/// Using Jacobian projective coordinates over Fp2.

///|
/// G2 curve coefficient b' = 4(1+u) in Fp2
pub fn g2_b() -> Fp2 {
  let four = @bigint.from_int_value(4)
  { c0: four, c1: four } // 4 + 4u = 4(1+u)
}

///|
/// G2 generator x-coordinate (c0, c1) in Fp2 (BLS12-381 standard, EIP-2537).
pub fn g2_gx() -> Fp2 {
  {
    c0: match(@bigint.from_string(
      "0x024aa2b2f08f0a91260805272dc51051c6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8",
    )) {
      Some(v) => v
      None => abort("FATAL: invalid G2 generator x.c0")
    },
    c1: match(@bigint.from_string(
      "0x13e02b6052719f607dacd3a088274f65596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e",
    )) {
      Some(v) => v
      None => abort("FATAL: invalid G2 generator x.c1")
    },
  }
}

///|
/// G2 generator y-coordinate (c0, c1) in Fp2 (BLS12-381 standard, EIP-2537).
pub fn g2_gy() -> Fp2 {
  {
    c0: match(@bigint.from_string(
      "0x0ce5d527727d6e118cc9cdc6da2e351aadfd9baa8cbdd3a76d429a695160d12c923ac9cc3baca289e193548608b82801",
    )) {
      Some(v) => v
      None => abort("FATAL: invalid G2 generator y.c0")
    },
    c1: match(@bigint.from_string(
      "0x0606c4a02ea734cc32acd2b02bc28b99cb3e287e85a763af267492ab572e99ab3f370d275cec1da1aaa9075ff05f79be",
    )) {
      Some(v) => v
      None => abort("FATAL: invalid G2 generator y.c1")
    },
  }
}

///|
/// G2 point in Jacobian projective coordinates over Fp2
pub struct G2Point {
  x : Fp2
  y : Fp2
  z : Fp2
}

///|
/// G2 point at infinity (identity): (0, 1, 0) in Fp2
pub fn g2_identity() -> G2Point {
  { x: fp2_zero(), y: fp2_one(), z: fp2_zero() }
}

///|
pub fn g2_is_identity(p : G2Point) -> Bool {
  fp2_is_zero(p.z)
}

///|
/// G2 generator point
pub fn g2_generator() -> G2Point {
  { x: g2_gx(), y: g2_gy(), z: fp2_one() }
}

///|
/// G2 point doubling for a = 0 (y^2 = x^3 + b')
/// dbl-2001-b in Jacobian coordinates over Fp2
pub fn g2_double(p : G2Point) -> G2Point {
  if g2_is_identity(p) {
    return p
  }
  if fp2_is_zero(p.y) {
    return g2_identity()
  }
  let a = fp2_sqr(p.x) // A = X^2
  let b = fp2_sqr(p.y) // B = Y^2
  let c = fp2_sqr(b) // C = B^2 = Y^4
  let xpb = fp2_add(p.x, b)
  let d = fp2_sub(fp2_sub(fp2_sqr(xpb), a), c) // (X+B)^2 - A - C
  let d = fp2_add(d, d) // D = 2 * ((X+B)^2 - A - C)
  let three = @bigint.from_int_value(3)
  let e = fp2_mul_fp(a, three) // E = 3*A
  let f = fp2_sqr(e) // F = E^2
  let two_d = fp2_add(d, d)
  let x3 = fp2_sub(f, two_d) // X3 = F - 2*D
  let d_x3 = fp2_sub(d, x3)
  let eight_c = {
    let two_c = fp2_add(c, c)
    let four_c = fp2_add(two_c, two_c)
    fp2_add(four_c, four_c)
  }
  let y3 = fp2_sub(fp2_mul(e, d_x3), eight_c) // Y3 = E*(D - X3) - 8*C
  let z3 = fp2_mul(fp2_add(p.y, p.y), p.z) // Z3 = 2*Y*Z
  { x: x3, y: y3, z: z3 }
}

///|
/// G2 point addition (Jacobian + Jacobian)
/// add-2007-bl in Jacobian coordinates over Fp2
pub fn g2_add(p : G2Point, q : G2Point) -> G2Point {
  if g2_is_identity(p) {
    return q
  }
  if g2_is_identity(q) {
    return p
  }
  let z1z1 = fp2_sqr(p.z) // Z1Z1 = Z1^2
  let z2z2 = fp2_sqr(q.z) // Z2Z2 = Z2^2
  let u1 = fp2_mul(p.x, z2z2) // U1 = X1*Z2^2
  let u2 = fp2_mul(q.x, z1z1) // U2 = X2*Z1^2
  let s1 = fp2_mul(fp2_mul(p.y, q.z), z2z2) // S1 = Y1*Z2^3
  let s2 = fp2_mul(fp2_mul(q.y, p.z), z1z1) // S2 = Y2*Z1^3
  if fp2_eq(u1, u2) {
    if fp2_eq(s1, s2) {
      return g2_double(p)
    } else {
      return g2_identity()
    }
  }
  let h = fp2_sub(u2, u1) // H = U2 - U1
  let hh = fp2_sqr(h) // HH = H^2
  let two_hh = fp2_add(hh, hh)
  let i = fp2_add(two_hh, two_hh) // I = 4*HH
  let j = fp2_mul(h, i) // J = H*I
  let r = {
    let diff = fp2_sub(s2, s1)
    fp2_add(diff, diff) // r = 2*(S2-S1)
  }
  let v = fp2_mul(u1, i) // V = U1*I
  let x3 = {
    let r_sqr = fp2_sqr(r)
    let two_v = fp2_add(v, v)
    fp2_sub(fp2_sub(r_sqr, j), two_v) // X3 = r^2 - J - 2*V
  }
  let y3 = {
    let r_v_x3 = fp2_mul(r, fp2_sub(v, x3))
    let two_s1j = fp2_add(fp2_mul(s1, j), fp2_mul(s1, j))
    fp2_sub(r_v_x3, two_s1j) // Y3 = r*(V - X3) - 2*S1*J
  }
  let z3 = {
    let z1z2 = fp2_mul(p.z, q.z)
    let two = @bigint.from_int_value(2)
    fp2_mul(fp2_mul_fp(z1z2, two), h) // Z3 = 2*Z1*Z2*H
  }
  { x: x3, y: y3, z: z3 }
}

///|
/// G2 scalar multiplication (double-and-add)
pub fn g2_scalar_mul(k : @bigint.BigInt, p : G2Point) -> G2Point {
  let mut result = g2_identity()
  let mut base = p
  let mut e = k
  let zero = @bigint.zero()
  while @bigint.compare(e, zero) > 0 {
    if @bigint.is_odd(e) {
      result = g2_add(result, base)
    }
    base = g2_double(base)
    e = @bigint.shr(e, 1)
  }
  result
}

///|
/// Convert G2 Jacobian to affine (x, y) in Fp2
pub fn g2_to_affine(p : G2Point) -> (Fp2, Fp2) {
  if g2_is_identity(p) {
    return (fp2_zero(), fp2_zero())
  }
  let z_inv = fp2_inv(p.z)
  let z_inv2 = fp2_sqr(z_inv)
  let x = fp2_mul(p.x, z_inv2)
  let y = fp2_mul(p.y, fp2_mul(z_inv, z_inv2))
  (x, y)
}

///|
/// G2 negation: (X, Y, Z) -> (X, -Y, Z)
pub fn g2_neg(p : G2Point) -> G2Point {
  { x: p.x, y: fp2_neg(p.y), z: p.z }
}

///|
/// Check if a point (x, y) is on the curve y^2 = x^3 + 4(1+u)
pub fn g2_is_on_curve(x : Fp2, y : Fp2) -> Bool {
  let lhs = fp2_sqr(y)
  let rhs = fp2_add(fp2_mul(fp2_sqr(x), x), g2_b())
  fp2_eq(lhs, rhs)
}

///|
/// G2 point equality
pub fn g2_eq(p : G2Point, q : G2Point) -> Bool {
  if g2_is_identity(p) && g2_is_identity(q) {
    return true
  }
  if g2_is_identity(p) || g2_is_identity(q) {
    return false
  }
  let (px, py) = g2_to_affine(p)
  let (qx, qy) = g2_to_affine(q)
  fp2_eq(px, qx) && fp2_eq(py, qy)
}
