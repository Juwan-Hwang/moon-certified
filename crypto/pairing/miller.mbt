/// BLS12-381 Optimal Ate Pairing: Miller Loop + Final Exponentiation
///
/// The pairing is a bilinear map e: G1 x G2 -> GT where GT is a subgroup
/// of Fp12*. It is computed in two steps:
/// 1. Miller loop: iterates over the bits of the BLS parameter x
/// 2. Final exponentiation: raises the Miller loop result to (p^12 - 1) / r

///|
/// BLS parameter x = 0xd201000000010000 (absolute value)
pub let bls_x : @bigint.BigInt = match(@bigint.from_string("0xd201000000010000")) {
  Some(v) => v
  None => abort("FATAL: invalid BLS parameter x")
}

///|
/// BLS parameter x is negative for BLS12-381
pub let bls_x_is_negative : Bool = true

///|
/// Evaluate the tangent or chord line through affine points on the twist
/// E': y² = x³ + 4(1+u) at the G1 point P, returning the exact line value
/// as an element of Fp12.
///
/// With the D-type untwist ψ(x', y') = (x'/v, y'/(vw)) where v³ = ξ = 1+u
/// and w² = v, a line of slope λ through R on E' evaluates at P to
///
///   ℓ(P) = y_P + (λ·x_R - y_R)·ξ⁻¹·(vw) + (-λ·x_P)·ξ⁻¹·(v²w).
///
/// No non-trivial scalar factor is dropped, so the Miller function
/// computed from these values is exact.
fn line_eval(
  lam : Fp2,
  rx : Fp2,
  ry : Fp2,
  px : Fp2,
  py : Fp2,
  xi_inv : Fp2,
) -> Fp12 {
  // coefficient of vw: (λ·x_R - y_R) / ξ
  let vw_coeff = fp2_mul(fp2_sub(fp2_mul(lam, rx), ry), xi_inv)
  // coefficient of v²w: (-λ·x_P) / ξ
  let v2w_coeff = fp2_neg(fp2_mul(fp2_mul(lam, px), xi_inv))
  let c0 : Fp6 = { c0: py, c1: fp2_zero(), c2: fp2_zero() }
  let c1 : Fp6 = { c0: fp2_zero(), c1: vw_coeff, c2: v2w_coeff }
  { c0, c1 }
}

///|
/// Evaluate the vertical line X - x_R at P exactly:
/// (x_P - x_R/v) = x_P - (x_R/ξ)·v².
fn vertical_line_eval(
  rx : Fp2,
  px : Fp2,
  xi_inv : Fp2,
) -> Fp12 {
  let c0 : Fp6 = { c0: px, c1: fp2_zero(), c2: fp2_neg(fp2_mul(rx, xi_inv)) }
  let c1 : Fp6 = fp6_zero()
  { c0, c1 }
}

///|
/// Miller loop for the optimal ate pairing e(P, Q).
///
/// Standard double-and-add accumulation over the bits of |x| (the BLS
/// parameter): for every bit after the leading one,
/// f ← f² · ℓ_{R,R}(P) with R ← 2R, and for set bits additionally
/// f ← f · ℓ_{R,Q}(P) with R ← R + Q. Line values are evaluated exactly
/// per `line_eval`. Because x < 0 for BLS12-381, the Miller function for
/// x is the inverse of the one for |x|; on cyclotomic-subgroup inputs
/// this is realized by conjugation.
pub fn miller_loop(p : G1Point, q : G2Point) -> Fp12 {
  if g1_is_identity(p) || g2_is_identity(q) {
    return fp12_one()
  }
  let (px_raw, py_raw) = g1_to_affine(p)
  let (qx, qy) = g2_to_affine(q)
  let px = fp2_from_fp(px_raw)
  let py = fp2_from_fp(py_raw)
  let xi_inv = fp2_inv(fp6_nonresidue())
  let three = @bigint.from_int_value(3)
  let mut f = fp12_one()
  let mut rx = qx
  let mut ry = qy
  let bits = bls_x_bits()
  for i in 0..<bits.length() {
    if bits[i] == 2 { // leading-bit marker: initial value, nothing to do
      continue
    }
    f = fp12_sqr(f)
    // Tangent at R: λ = 3·x_R² / (2·y_R)  (the curve has a = 0).
    let lam = fp2_mul(
      fp2_mul_fp(fp2_sqr(rx), three),
      fp2_inv(fp2_add(ry, ry)),
    )
    f = fp12_mul(f, line_eval(lam, rx, ry, px, py, xi_inv))
    // R ← 2R (affine).
    let lam2 = fp2_sqr(lam)
    let x2 = fp2_sub(lam2, fp2_add(rx, rx))
    let y2 = fp2_sub(fp2_mul(lam, fp2_sub(rx, x2)), ry)
    rx = x2
    ry = y2
    if bits[i] == 1 {
      // Chord through R and Q.
      if fp2_eq(rx, qx) {
        if fp2_eq(ry, qy) {
          // Same point: use the tangent instead.
          let lam_a = fp2_mul(
            fp2_mul_fp(fp2_sqr(rx), three),
            fp2_inv(fp2_add(ry, ry)),
          )
          f = fp12_mul(f, line_eval(lam_a, rx, ry, px, py, xi_inv))
          let lam2_a = fp2_sqr(lam_a)
          let xa = fp2_sub(lam2_a, fp2_add(rx, rx))
          let ya = fp2_sub(fp2_mul(lam_a, fp2_sub(rx, xa)), ry)
          rx = xa
          ry = ya
        } else {
          // R = -Q: vertical line, R + Q = O. Cannot occur for points of
          // odd prime order with |x| ≪ r; handled for totality.
          f = fp12_mul(f, vertical_line_eval(rx, px, xi_inv))
          return if bls_x_is_negative { fp12_conjugate(f) } else { f }
        }
      } else {
        let lam_c = fp2_mul(fp2_sub(qy, ry), fp2_inv(fp2_sub(qx, rx)))
        f = fp12_mul(f, line_eval(lam_c, rx, ry, px, py, xi_inv))
        // R ← R + Q (affine).
        let lam2_c = fp2_sqr(lam_c)
        let xc = fp2_sub(fp2_sub(lam2_c, rx), qx)
        let yc = fp2_sub(fp2_mul(lam_c, fp2_sub(rx, xc)), ry)
        rx = xc
        ry = yc
      }
    }
  }
  if bls_x_is_negative {
    f = fp12_conjugate(f)
  }
  f
}

///|
/// Bits of the BLS parameter x to iterate, MSB first. Entry values:
/// 2 marks the leading bit (starting point), then each remaining bit of
/// |x| follows. This iterates the full 64-bit |x| = 0xd201000000010000.
fn bls_x_bits() -> Array[Int] {
  let bits : Array[Int] = []
  let one = @bigint.one()
  let mut leading_marked = false
  for i in [63, 62, 61, 60, 59, 58, 57, 56, 55, 54, 53, 52, 51, 50, 49, 48, 47, 46, 45, 44, 43, 42, 41, 40, 39, 38, 37, 36, 35, 34, 33, 32, 31, 30, 29, 28, 27, 26, 25, 24, 23, 22, 21, 20, 19, 18, 17, 16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0] {
    let bit_val = @bigint.shr(bls_x, i)
    let bit = @bigint.equal(@bigint.bit_and(bit_val, one), one)
    if !leading_marked {
      if bit {
        bits.push(2)
        leading_marked = true
      }
      continue
    }
    bits.push(if bit { 1 } else { 0 })
  }
  bits
}

///|
/// Final exponentiation: raises f to the power (p^12 - 1) / r
///
/// This is the direct computation. While not as optimized as the
/// Frobenius-based decomposition, it is straightforward and correct.
/// The exponent (p^12 - 1) / r is approximately 4572 bits.
pub fn final_exponentiation(f : Fp12) -> Fp12 {
  let p2 = @bigint.mul(bls_p, bls_p)
  let p4 = @bigint.mul(p2, p2)
  let p6 = @bigint.mul(p4, p2)
  let p12 = @bigint.mul(p6, p6)
  let p12_minus_1 = @bigint.sub(p12, @bigint.one())
  let final_exp = match(@bigint.divmod(p12_minus_1, bls_r)) {
    Some((q, _)) => q
    None => abort("FATAL: failed to compute final exponent")
  }
  fp12_pow(f, final_exp)
}

///|
/// Optimal Ate pairing: e(p, q) where p in G1, q in G2
/// Returns an element of GT (a subgroup of Fp12*)
pub fn pairing(p : G1Point, q : G2Point) -> Fp12 {
  let f = miller_loop(p, q)
  final_exponentiation(f)
}
