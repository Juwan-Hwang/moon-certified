///|
/// Bulletproofs — Zero-Knowledge Range Proofs (secp256k1)
///
/// A real Bulletproofs implementation: Pedersen commitments plus the
/// logarithmic-size inner-product argument range proof of Bünz et al.
/// The proof convinces a verifier that a committed value v lies in
/// [0, 2^32) without revealing v or the blinding factor.
///
/// ## Protocol outline (Fiat-Shamir heuristic)
///
/// 1. Commit V = v·G + γ·H.
/// 2. Bit-decompose v = a_L, set a_R = a_L − 1^n, commit
///    A = α·H + ⟨a_L, g⟩ + ⟨a_R, h⟩ and
///    S = ρ·H + ⟨s_L, g⟩ + ⟨s_R, h⟩ for random blinds/vectors.
/// 3. Challenges y, z; form l(X) = (a_L − z·1) + s_L·X and
///    r(X) = y^n ∘ (a_R + z·1 + s_R·X) + z²·2^n; commit the linear and
///    quadratic coefficients of t(X) = ⟨l(X), r(X)⟩ as T1, T2.
/// 4. Challenge x; open t̂ = t(x) with blinding τ_x, send μ = α + ρx.
/// 5. Inner-product argument proves ⟨l(x), r(x)⟩ = t̂ against the
///    folded generators in O(log n) rounds.
///
/// Verification checks (1) the t-polynomial opening against V, and
/// (2) the inner-product argument — nothing about v or γ leaks.
///
/// ## Notes
///
/// - n = 32 bits; generators are derived deterministically by
///   hash-to-curve so prover and verifier share them without trust.
/// - Scalar operations run modulo the secp256k1 group order; points
///   use Jacobian coordinates.
///
/// ## References
///
/// - Bünz, Bootle, Boneh, Poelstra, Wuille, Maxwell. "Bulletproofs:
///   Short Proofs for Confidential Transactions and More." IEEE S&P
///   2018.
///
/// `proof-enabled` is `false`.

// ===========================================================================
// secp256k1 group arithmetic
// ===========================================================================

///|
fn bp_parse_const(s : String, name : String) -> @bigint.BigInt {
  match @bigint.from_string(s) {
    Some(v) => v
    None => abort("FATAL: invalid bulletproofs curve constant: " + name)
  }
}

///|
/// Field prime of secp256k1.
pub let bp_q : @bigint.BigInt = bp_parse_const(
  "0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F", "q",
)

///|
/// Group order of secp256k1.
pub let bp_p : @bigint.BigInt = bp_parse_const(
  "0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141", "p",
)

///|
fn bp_field_q() -> @bigint.BigInt {
  bp_q
}

///|
fn bp_order() -> @bigint.BigInt {
  bp_p
}

///|
fn bp_mod(a : @bigint.BigInt, m : @bigint.BigInt) -> @bigint.BigInt {
  match @bigint.divmod(a, m) {
    Some((_, r)) =>
      if @bigint.compare(r, @bigint.zero()) < 0 {
        @bigint.add(r, m)
      } else {
        r
      }
    None => @bigint.zero()
  }
}

///|
fn bp_add_mod(a : @bigint.BigInt, b : @bigint.BigInt) -> @bigint.BigInt {
  bp_mod(@bigint.add(a, b), bp_order())
}

///|
fn bp_sub_mod(a : @bigint.BigInt, b : @bigint.BigInt) -> @bigint.BigInt {
  bp_mod(@bigint.sub(a, b), bp_order())
}

///|
fn bp_mul_mod(a : @bigint.BigInt, b : @bigint.BigInt) -> @bigint.BigInt {
  bp_mod(@bigint.mul(a, b), bp_order())
}

///|
fn bp_inv(a : @bigint.BigInt) -> @bigint.BigInt {
  match
    @bigint.mod_pow(
      a,
      @bigint.sub(bp_order(), @bigint.from_int_value(2)),
      bp_order(),
    ) {
    Some(v) => v
    None => @bigint.zero()
  }
}

///|
fn bp_field_mod(a : @bigint.BigInt) -> @bigint.BigInt {
  bp_mod(a, bp_field_q())
}

///|
fn bp_field_mul(a : @bigint.BigInt, b : @bigint.BigInt) -> @bigint.BigInt {
  bp_field_mod(@bigint.mul(a, b))
}

///|
fn bp_field_add(a : @bigint.BigInt, b : @bigint.BigInt) -> @bigint.BigInt {
  bp_field_mod(@bigint.add(a, b))
}

///|
fn bp_field_sub(a : @bigint.BigInt, b : @bigint.BigInt) -> @bigint.BigInt {
  bp_field_mod(@bigint.sub(a, b))
}

///|
fn bp_field_inv(a : @bigint.BigInt) -> @bigint.BigInt {
  match
    @bigint.mod_pow(
      a,
      @bigint.sub(bp_field_q(), @bigint.from_int_value(2)),
      bp_field_q(),
    ) {
    Some(v) => v
    None => @bigint.zero()
  }
}

///|
pub struct BpPoint {
  priv x : @bigint.BigInt
  priv y : @bigint.BigInt
  priv z : @bigint.BigInt
}

///|
fn bp_infinity() -> BpPoint {
  { x: @bigint.one(), y: @bigint.one(), z: @bigint.zero() }
}

///|
fn bp_is_infinity(pt : BpPoint) -> Bool {
  @bigint.is_zero(pt.z)
}

///|
fn bp_double(pt : BpPoint) -> BpPoint {
  if bp_is_infinity(pt) || @bigint.is_zero(pt.y) {
    return bp_infinity()
  }
  let q = bp_field_q()
  let two = @bigint.from_int_value(2)
  let three = @bigint.from_int_value(3)
  let four = @bigint.from_int_value(4)
  let eight = @bigint.from_int_value(8)
  let ysq = bp_field_mul(pt.y, pt.y)
  let s = bp_field_mul(four, bp_field_mul(pt.x, ysq))
  let xsq = bp_field_mul(pt.x, pt.x)
  let m = bp_field_mul(three, xsq)
  let xsq8 = bp_field_mul(eight, bp_field_mul(ysq, ysq))
  let xr = bp_field_sub(bp_field_mul(m, m), bp_field_mul(two, s))
  let yr = bp_field_sub(bp_field_mul(m, bp_field_sub(s, xr)), xsq8)
  let zr = bp_field_mul(two, bp_field_mul(pt.y, pt.z))
  let _ = q
  { x: xr, y: yr, z: zr }
}

///|
fn bp_add(a : BpPoint, b : BpPoint) -> BpPoint {
  if bp_is_infinity(a) {
    return b
  }
  if bp_is_infinity(b) {
    return a
  }
  let two = @bigint.from_int_value(2)
  let u1 = bp_field_mul(a.x, bp_field_mul(b.z, b.z))
  let u2 = bp_field_mul(b.x, bp_field_mul(a.z, a.z))
  let s1 = bp_field_mul(a.y, bp_field_mul(b.z, bp_field_mul(b.z, b.z)))
  let s2 = bp_field_mul(b.y, bp_field_mul(a.z, bp_field_mul(a.z, a.z)))
  if @bigint.compare(u1, u2) == 0 {
    if @bigint.compare(s1, s2) == 0 {
      return bp_double(a)
    }
    return bp_infinity()
  }
  let h = bp_field_sub(u2, u1)
  let r = bp_field_sub(s2, s1)
  let h2 = bp_field_mul(h, h)
  let h3 = bp_field_mul(h, h2)
  let u1h2 = bp_field_mul(u1, h2)
  let xr = bp_field_sub(
    bp_field_sub(bp_field_mul(r, r), h3),
    bp_field_mul(two, u1h2),
  )
  let yr = bp_field_sub(
    bp_field_mul(r, bp_field_sub(u1h2, xr)),
    bp_field_mul(s1, h3),
  )
  let zr = bp_field_mul(h, bp_field_mul(a.z, b.z))
  { x: xr, y: yr, z: zr }
}

///|
fn bp_neg(pt : BpPoint) -> BpPoint {
  if bp_is_infinity(pt) {
    pt
  } else {
    { x: pt.x, y: bp_field_sub(bp_field_q(), pt.y), z: pt.z }
  }
}

///|
fn bp_scalar_mul(k : @bigint.BigInt, pt : BpPoint) -> BpPoint {
  if @bigint.is_zero(k) || bp_is_infinity(pt) {
    return bp_infinity()
  }
  let kk = bp_mod(k, bp_order())
  let mut result = bp_infinity()
  let mut addend = pt
  let mut v = kk
  while @bigint.compare(v, @bigint.zero()) > 0 {
    match @bigint.divmod(v, @bigint.from_int_value(2)) {
      Some((qq, rr)) => {
        if @bigint.compare(rr, @bigint.zero()) != 0 {
          result = bp_add(result, addend)
        }
        addend = bp_double(addend)
        v = qq
      }
      None => v = @bigint.zero()
    }
  }
  result
}

///|
fn bp_to_affine(pt : BpPoint) -> (@bigint.BigInt, @bigint.BigInt)? {
  if bp_is_infinity(pt) {
    return None
  }
  let zinv = bp_field_inv(pt.z)
  let zinv2 = bp_field_mul(zinv, zinv)
  let zinv3 = bp_field_mul(zinv2, zinv)
  Some((bp_field_mul(pt.x, zinv2), bp_field_mul(pt.y, zinv3)))
}

///|
fn bp_bytes_to_bigint(b : Bytes) -> @bigint.BigInt {
  let base = @bigint.from_int_value(256)
  let mut acc = @bigint.zero()
  for i = 0; i < b.length(); i = i + 1 {
    acc = @bigint.add(
      @bigint.mul(acc, base),
      @bigint.from_int_value(b[i].to_int() & 0xFF),
    )
  }
  acc
}

///|
fn bp_bigint_to_32(b : @bigint.BigInt) -> Bytes {
  let arr = Array::make(32, b'\x00')
  let mut v = b
  let base = @bigint.from_int_value(256)
  for i = 31; i >= 0; i = i - 1 {
    match @bigint.divmod(v, base) {
      Some((qq, rr)) => {
        match @bigint.to_int(rr) {
          Some(iv) => arr[i] = iv.to_byte()
          None => ()
        }
        v = qq
      }
      None => ()
    }
  }
  Bytes::from_array(arr)
}

///|
fn bp_point_compress(pt : BpPoint) -> Bytes? {
  match bp_to_affine(pt) {
    Some((x, y)) => {
      let odd = match @bigint.divmod(y, @bigint.from_int_value(2)) {
        Some((_, rr)) => @bigint.compare(rr, @bigint.zero()) != 0
        None => false
      }
      let arr : Array[Byte] = [if odd { b'\x03' } else { b'\x02' }]
      let xb = bp_bigint_to_32(x)
      for i = 0; i < 32; i = i + 1 {
        arr.push(xb[i])
      }
      Some(Bytes::from_array(arr))
    }
    None => None
  }
}

///|
fn bp_point_decompress(data : Bytes) -> BpPoint? {
  if data.length() != 33 {
    return None
  }
  let prefix = data[0].to_int()
  if prefix != 2 && prefix != 3 {
    return None
  }
  let xarr : Array[Byte] = []
  for i = 1; i < 33; i = i + 1 {
    xarr.push(data[i])
  }
  let x = bp_field_mod(bp_bytes_to_bigint(Bytes::from_array(xarr)))
  let seven = @bigint.from_int_value(7)
  let four = @bigint.from_int_value(4)
  let y2 = bp_field_add(bp_field_mul(bp_field_mul(x, x), x), seven)
  let exp = match
    @bigint.divmod(@bigint.add(bp_field_q(), @bigint.one()), four) {
    Some((qq, _)) => qq
    None => return None
  }
  let y = match @bigint.mod_pow(y2, exp, bp_field_q()) {
    Some(v) => v
    None => return None
  }
  if @bigint.compare(bp_field_mul(y, y), y2) != 0 {
    return None
  }
  let y_is_odd = match @bigint.divmod(y, @bigint.from_int_value(2)) {
    Some((_, rr)) => @bigint.compare(rr, @bigint.zero()) != 0
    None => false
  }
  let want_odd = prefix == 3
  let y_final = if y_is_odd == want_odd {
    y
  } else {
    bp_field_sub(bp_field_q(), y)
  }
  Some({ x, y: y_final, z: @bigint.one() })
}

///|
fn bp_base_g() -> BpPoint {
  {
    x: bp_parse_const(
      "0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798", "Gx",
    ),
    y: bp_parse_const(
      "0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8", "Gy",
    ),
    z: @bigint.one(),
  }
}

///|
/// Hash-to-curve generator derivation: try counter values until the
/// candidate x yields a valid curve point.
fn bp_hash_to_point(label : Bytes, index : Int) -> BpPoint {
  let mut result : BpPoint? = None
  let mut counter = 0
  while result is None {
    let buf : Array[Byte] = []
    for i = 0; i < label.length(); i = i + 1 {
      buf.push(label[i])
    }
    buf.push(((index >> 8) & 0xFF).to_byte())
    buf.push((index & 0xFF).to_byte())
    buf.push(((counter >> 8) & 0xFF).to_byte())
    buf.push((counter & 0xFF).to_byte())
    let cand = bp_field_mod(
      bp_bytes_to_bigint(@sha256.sha256(Bytes::from_array(buf))),
    )
    let seven = @bigint.from_int_value(7)
    let four = @bigint.from_int_value(4)
    let y2 = bp_field_add(bp_field_mul(bp_field_mul(cand, cand), cand), seven)
    match @bigint.divmod(@bigint.add(bp_field_q(), @bigint.one()), four) {
      Some((exp, _)) =>
        match @bigint.mod_pow(y2, exp, bp_field_q()) {
          Some(y) =>
            if @bigint.compare(bp_field_mul(y, y), y2) == 0 {
              result = Some({ x: cand, y, z: @bigint.one() })
            }
          None => ()
        }
      None => ()
    }
    counter = counter + 1
  }
  match result {
    Some(pt) => pt
    None => bp_infinity()
  }
}

// ===========================================================================
// Generators and parameters
// ===========================================================================

///|
/// Number of bits proven (range [0, 2^BP_N)).
pub const BP_N : Int = 32

///|
/// Number of inner-product argument rounds (log2 of BP_N).
const BP_ROUNDS : Int = 5

///|
/// Common reference parameters: independent generators derived by
/// hash-to-curve.
pub struct CommitmentKey {
  g : BpPoint
  h : BpPoint
  u : BpPoint
  g_vec : Array[BpPoint]
  h_vec : Array[BpPoint]
}

///|
fn bp_gen_vector(label : Bytes) -> Array[BpPoint] {
  let v : Array[BpPoint] = []
  for i = 0; i < BP_N; i = i + 1 {
    v.push(bp_hash_to_point(label, i))
  }
  v
}

///|
/// Build the commitment key (deterministic; safe to rebuild anywhere).
pub fn CommitmentKey::new() -> CommitmentKey {
  {
    g: bp_base_g(),
    h: bp_hash_to_point(b"bulletproofs-h", 0),
    u: bp_hash_to_point(b"bulletproofs-u", 0),
    g_vec: bp_gen_vector(b"bulletproofs-gvec"),
    h_vec: bp_gen_vector(b"bulletproofs-hvec"),
  }
}

// ===========================================================================
// Transcript (Fiat-Shamir)
// ===========================================================================

///|
priv struct BpTranscript {
  mut state : Bytes
}

///|
fn BpTranscript::new(label : String) -> BpTranscript {
  let arr : Array[Byte] = []
  for ch in label {
    arr.push(ch.to_int().to_byte())
  }
  { state: @sha256.sha256(Bytes::from_array(arr)) }
}

///|
fn BpTranscript::append(self : BpTranscript, data : Bytes) -> Unit {
  self.state = @sha256.sha256(self.state + data)
}

///|
fn BpTranscript::append_point(self : BpTranscript, pt : BpPoint) -> Unit raise {
  match bp_point_compress(pt) {
    Some(enc) => self.append(enc)
    None => fail("bulletproofs: cannot serialize point")
  }
}

///|
fn BpTranscript::challenge(self : BpTranscript) -> @bigint.BigInt {
  let c = @sha256.sha256(b"bp-challenge" + self.state)
  self.state = @sha256.sha256(b"bp-next" + self.state)
  bp_mod(bp_bytes_to_bigint(c), bp_order())
}

// ===========================================================================
// Vector helpers (scalars mod the group order)
// ===========================================================================

///|
fn bp_scalar_of_int(v : Int) -> @bigint.BigInt {
  bp_mod(@bigint.from_int_value(v), bp_order())
}

///|
fn bp_vec_inner(
  a : Array[@bigint.BigInt],
  b : Array[@bigint.BigInt],
) -> @bigint.BigInt {
  let mut acc = @bigint.zero()
  for i = 0; i < a.length(); i = i + 1 {
    acc = bp_add_mod(acc, bp_mul_mod(a[i], b[i]))
  }
  acc
}

///|
fn bp_msm(scalars : Array[@bigint.BigInt], points : Array[BpPoint]) -> BpPoint {
  let mut acc = bp_infinity()
  for i = 0; i < scalars.length(); i = i + 1 {
    if !@bigint.is_zero(scalars[i]) {
      acc = bp_add(acc, bp_scalar_mul(scalars[i], points[i]))
    }
  }
  acc
}

// ===========================================================================
// Pedersen commitments
// ===========================================================================

///|
/// Pedersen commitment to `value` with 32-byte blinding scalar:
/// C = value·G + blinding·H.
pub fn pedersen_commit(
  key : CommitmentKey,
  value : Int,
  blinding : Bytes,
) -> Bytes raise {
  let gamma = bp_mod(bp_bytes_to_bigint(blinding), bp_order())
  let pt = bp_add(
    bp_scalar_mul(bp_scalar_of_int(value), key.g),
    bp_scalar_mul(gamma, key.h),
  )
  match bp_point_compress(pt) {
    Some(enc) => enc
    None => fail("bulletproofs: degenerate commitment")
  }
}

///|
/// A Bulletproofs range proof (opaque byte encoding).
pub struct RangeProof {
  data : Bytes
}

///|
pub fn RangeProof::new(proof_data : Bytes) -> RangeProof {
  { data: proof_data }
}

// ===========================================================================
// Prover randomness
// ===========================================================================

///|
fn bp_rng(seed : Bytes) -> @chacha20.ChaCha20Rng raise {
  let key = @sha256.sha256(seed)
  let nsrc = @sha256.sha256(seed + b"bp-nonce")
  let narr : Array[Byte] = []
  for i = 0; i < 12; i = i + 1 {
    narr.push(nsrc[i])
  }
  match @chacha20.create_rng(key, Bytes::from_array(narr)) {
    Some(r) => r
    None => fail("bulletproofs: CSPRNG init failed")
  }
}

///|
/// Uniform scalar in [1, p-1] via rejection sampling.
fn bp_rand_scalar(rng : @chacha20.ChaCha20Rng) -> @bigint.BigInt raise {
  let mut result : @bigint.BigInt? = None
  while result is None {
    match @chacha20.next_bytes(rng, 32) {
      Some(bs) => {
        let v = bp_bytes_to_bigint(bs)
        if @bigint.compare(v, bp_order()) < 0 && !@bigint.is_zero(v) {
          result = Some(v)
        }
      }
      None => fail("bulletproofs: CSPRNG exhausted")
    }
  }
  match result {
    Some(v) => v
    None => fail("bulletproofs: scalar sampling failed")
  }
}

///|
/// Derive a 32-byte blinding factor from entropy.
pub fn bp_random_blinding(seed : Bytes) -> Bytes {
  @sha256.sha256(seed + b"bp-blinding")
}

// ===========================================================================
// Prove
// ===========================================================================

///|
/// Produce a range proof that the committed `value` lies in
/// [0, 2^32). The blinding factor must match the one used for the
/// public Pedersen commitment.
pub fn prove_range(
  key : CommitmentKey,
  value : Int,
  blinding : Bytes,
) -> RangeProof raise {
  if value < 0 {
    fail("bulletproofs: negative value")
  }
  let n = BP_N
  let gamma = bp_mod(bp_bytes_to_bigint(blinding), bp_order())
  // Deterministic prover nonce from the blinding factor and value.
  let nonce_seed = @sha256.sha256(
    blinding + bp_bigint_to_32(bp_scalar_of_int(value)),
  )
  let rng = bp_rng(nonce_seed)
  // Bit decomposition.
  let a_l : Array[@bigint.BigInt] = []
  let a_r : Array[@bigint.BigInt] = []
  for i = 0; i < n; i = i + 1 {
    let bit = (value >> i) & 1
    a_l.push(bp_scalar_of_int(bit))
    a_r.push(bp_scalar_of_int(bit - 1))
  }
  let alpha = bp_rand_scalar(rng)
  let rho = bp_rand_scalar(rng)
  let s_l : Array[@bigint.BigInt] = []
  let s_r : Array[@bigint.BigInt] = []
  for _i = 0; _i < n; _i = _i + 1 {
    s_l.push(bp_rand_scalar(rng))
    s_r.push(bp_rand_scalar(rng))
  }
  let v_pt = bp_add(
    bp_scalar_mul(bp_scalar_of_int(value), key.g),
    bp_scalar_mul(gamma, key.h),
  )
  let a_pt = bp_add(
    bp_scalar_mul(alpha, key.h),
    bp_add(bp_msm(a_l, key.g_vec), bp_msm(a_r, key.h_vec)),
  )
  let s_pt = bp_add(
    bp_scalar_mul(rho, key.h),
    bp_add(bp_msm(s_l, key.g_vec), bp_msm(s_r, key.h_vec)),
  )
  let ts = BpTranscript::new("moon-certified-bulletproofs-v1")
  ts.append_point(v_pt)
  ts.append_point(a_pt)
  ts.append_point(s_pt)
  let y = ts.challenge()
  let z = ts.challenge()
  // y^n, 2^n vectors.
  let y_vec : Array[@bigint.BigInt] = []
  let two_vec : Array[@bigint.BigInt] = []
  let mut ypow = @bigint.one()
  let mut twopow = @bigint.one()
  for _i = 0; _i < n; _i = _i + 1 {
    y_vec.push(ypow)
    two_vec.push(twopow)
    ypow = bp_mul_mod(ypow, y)
    twopow = bp_mul_mod(twopow, bp_scalar_of_int(2))
  }
  let z2 = bp_mul_mod(z, z)
  // l(X) = l0 + l1·X, r(X) = r0 + r1·X
  let l0 : Array[@bigint.BigInt] = []
  let l1 = s_l
  let r0 : Array[@bigint.BigInt] = []
  let r1 : Array[@bigint.BigInt] = []
  for i = 0; i < n; i = i + 1 {
    l0.push(bp_sub_mod(a_l[i], z))
    let ar_z = bp_add_mod(a_r[i], z)
    r0.push(bp_add_mod(bp_mul_mod(y_vec[i], ar_z), bp_mul_mod(z2, two_vec[i])))
    r1.push(bp_mul_mod(y_vec[i], s_r[i]))
  }
  let t0 = bp_vec_inner(l0, r0)
  let t1 = bp_add_mod(bp_vec_inner(l0, r1), bp_vec_inner(l1, r0))
  let t2 = bp_vec_inner(l1, r1)
  let tau1 = bp_rand_scalar(rng)
  let tau2 = bp_rand_scalar(rng)
  let t1_pt = bp_add(bp_scalar_mul(t1, key.g), bp_scalar_mul(tau1, key.h))
  let t2_pt = bp_add(bp_scalar_mul(t2, key.g), bp_scalar_mul(tau2, key.h))
  ts.append_point(t1_pt)
  ts.append_point(t2_pt)
  let x = ts.challenge()
  let x2 = bp_mul_mod(x, x)
  let taux = bp_add_mod(
    bp_add_mod(bp_mul_mod(tau2, x2), bp_mul_mod(tau1, x)),
    bp_mul_mod(z2, gamma),
  )
  let mu = bp_add_mod(alpha, bp_mul_mod(rho, x))
  let t_hat = bp_add_mod(t0, bp_add_mod(bp_mul_mod(t1, x), bp_mul_mod(t2, x2)))
  let lx : Array[@bigint.BigInt] = []
  let rx : Array[@bigint.BigInt] = []
  for i = 0; i < n; i = i + 1 {
    lx.push(bp_add_mod(l0[i], bp_mul_mod(l1[i], x)))
    rx.push(bp_add_mod(r0[i], bp_mul_mod(r1[i], x)))
  }
  ts.append(bp_bigint_to_32(taux))
  ts.append(bp_bigint_to_32(mu))
  ts.append(bp_bigint_to_32(t_hat))
  // Folded h'_i = y^{-i}·h_i for the inner-product argument.
  let h_prime : Array[BpPoint] = []
  let mut yinv_pow = @bigint.one()
  let y_inv = bp_inv(y)
  for i = 0; i < n; i = i + 1 {
    h_prime.push(bp_scalar_mul(yinv_pow, key.h_vec[i]))
    yinv_pow = bp_mul_mod(yinv_pow, y_inv)
  }
  // Inner-product argument on (lx, rx) with generators (g_vec, h').
  let rounds_l : Array[BpPoint] = []
  let rounds_r : Array[BpPoint] = []
  let mut avec = lx
  let mut bvec = rx
  let mut gvec = key.g_vec
  let mut hvec = h_prime
  let mut len = n
  while len > 1 {
    let half = len / 2
    let a_lo = bp_slice_vec(avec, 0, half)
    let a_hi = bp_slice_vec(avec, half, len)
    let b_lo = bp_slice_vec(bvec, 0, half)
    let b_hi = bp_slice_vec(bvec, half, len)
    let g_lo = bp_slice_pts(gvec, 0, half)
    let g_hi = bp_slice_pts(gvec, half, len)
    let h_lo = bp_slice_pts(hvec, 0, half)
    let h_hi = bp_slice_pts(hvec, half, len)
    let c_l = bp_vec_inner(a_lo, b_hi)
    let c_r = bp_vec_inner(a_hi, b_lo)
    let l_pt = bp_add(
      bp_add(bp_msm(a_lo, g_hi), bp_msm(b_hi, h_lo)),
      bp_scalar_mul(c_l, key.u),
    )
    let r_pt = bp_add(
      bp_add(bp_msm(a_hi, g_lo), bp_msm(b_lo, h_hi)),
      bp_scalar_mul(c_r, key.u),
    )
    rounds_l.push(l_pt)
    rounds_r.push(r_pt)
    ts.append_point(l_pt)
    ts.append_point(r_pt)
    let u_ch = ts.challenge()
    let u_inv = bp_inv(u_ch)
    // Fold generators and vectors.
    let new_g : Array[BpPoint] = []
    let new_h : Array[BpPoint] = []
    let new_a : Array[@bigint.BigInt] = []
    let new_b : Array[@bigint.BigInt] = []
    for i = 0; i < half; i = i + 1 {
      new_g.push(
        bp_add(bp_scalar_mul(u_inv, g_lo[i]), bp_scalar_mul(u_ch, g_hi[i])),
      )
      new_h.push(
        bp_add(bp_scalar_mul(u_ch, h_lo[i]), bp_scalar_mul(u_inv, h_hi[i])),
      )
      new_a.push(
        bp_add_mod(bp_mul_mod(u_ch, a_lo[i]), bp_mul_mod(u_inv, a_hi[i])),
      )
      new_b.push(
        bp_add_mod(bp_mul_mod(u_inv, b_lo[i]), bp_mul_mod(u_ch, b_hi[i])),
      )
    }
    gvec = new_g
    hvec = new_h
    avec = new_a
    bvec = new_b
    len = half
  }
  // Serialize the proof.
  let out : Array[Byte] = []
  bp_emit_point(out, a_pt)
  bp_emit_point(out, s_pt)
  bp_emit_point(out, t1_pt)
  bp_emit_point(out, t2_pt)
  bp_emit_scalar(out, taux)
  bp_emit_scalar(out, mu)
  bp_emit_scalar(out, t_hat)
  for i = 0; i < BP_ROUNDS; i = i + 1 {
    bp_emit_point(out, rounds_l[i])
    bp_emit_point(out, rounds_r[i])
  }
  bp_emit_scalar(out, avec[0])
  bp_emit_scalar(out, bvec[0])
  { data: Bytes::from_array(out) }
}

///|
fn bp_slice_vec(
  v : Array[@bigint.BigInt],
  lo : Int,
  hi : Int,
) -> Array[@bigint.BigInt] {
  let r : Array[@bigint.BigInt] = []
  for i = lo; i < hi; i = i + 1 {
    r.push(v[i])
  }
  r
}

///|
fn bp_slice_pts(v : Array[BpPoint], lo : Int, hi : Int) -> Array[BpPoint] {
  let r : Array[BpPoint] = []
  for i = lo; i < hi; i = i + 1 {
    r.push(v[i])
  }
  r
}

///|
fn bp_emit_point(out : Array[Byte], pt : BpPoint) -> Unit {
  match bp_point_compress(pt) {
    Some(enc) =>
      for i = 0; i < enc.length(); i = i + 1 {
        out.push(enc[i])
      }
    None => ()
  }
}

///|
fn bp_emit_scalar(out : Array[Byte], s : @bigint.BigInt) -> Unit {
  let b = bp_bigint_to_32(s)
  for i = 0; i < 32; i = i + 1 {
    out.push(b[i])
  }
}

// ===========================================================================
// Verify
// ===========================================================================

///|
fn bp_take(data : Bytes, off : Int) -> Bytes? {
  if off + 33 > data.length() {
    return None
  }
  let arr : Array[Byte] = []
  for i = off; i < off + 33; i = i + 1 {
    arr.push(data[i])
  }
  Some(Bytes::from_array(arr))
}

///|
fn bp_take_point(data : Bytes, off : Int) -> BpPoint? {
  match bp_take(data, off) {
    Some(b) => bp_point_decompress(b)
    None => None
  }
}

///|
fn bp_take_bytes(data : Bytes, off : Int, len : Int) -> Bytes {
  let arr : Array[Byte] = []
  for i = off; i < off + len && i < data.length(); i = i + 1 {
    arr.push(data[i])
  }
  Bytes::from_array(arr)
}

///|
fn bp_take_scalar(data : Bytes, off : Int) -> @bigint.BigInt {
  bp_mod(bp_bytes_to_bigint(bp_take_bytes(data, off, 32)), bp_order())
}

///|
/// Verify a range proof against a Pedersen commitment. Returns `true`
/// iff the committed value lies in [0, 2^32) and the proof is
/// well-formed; false on any parse or verification failure.
pub fn verify_range(
  key : CommitmentKey,
  commitment : Bytes,
  proof : RangeProof,
) -> Bool {
  let data = proof.data
  // Layout: 4 points (132) + 3 scalars (96) + 5 rounds × 2 points
  // (330) + 2 scalars (64) = 622 bytes.
  if data.length() != 622 {
    return false
  }
  let v_pt = match bp_point_decompress(commitment) {
    Some(pt) => pt
    None => return false
  }
  let a_pt = match bp_take_point(data, 0) {
    Some(pt) => pt
    None => return false
  }
  let s_pt = match bp_take_point(data, 33) {
    Some(pt) => pt
    None => return false
  }
  let t1_pt = match bp_take_point(data, 66) {
    Some(pt) => pt
    None => return false
  }
  let t2_pt = match bp_take_point(data, 99) {
    Some(pt) => pt
    None => return false
  }
  let taux = bp_take_scalar(data, 132)
  let mu = bp_take_scalar(data, 164)
  let t_hat = bp_take_scalar(data, 196)
  // Rebuild the transcript and challenges.
  let ts = BpTranscript::new("moon-certified-bulletproofs-v1")
  ts.append_point(v_pt) catch {
    _ => return false
  }
  ts.append_point(a_pt) catch {
    _ => return false
  }
  ts.append_point(s_pt) catch {
    _ => return false
  }
  let y = ts.challenge()
  let z = ts.challenge()
  let n = BP_N
  let y_vec : Array[@bigint.BigInt] = []
  let two_vec : Array[@bigint.BigInt] = []
  let mut ypow = @bigint.one()
  let mut twopow = @bigint.one()
  let mut sum_y = @bigint.zero()
  let mut sum_two = @bigint.zero()
  for _i = 0; _i < n; _i = _i + 1 {
    y_vec.push(ypow)
    two_vec.push(twopow)
    sum_y = bp_add_mod(sum_y, ypow)
    sum_two = bp_add_mod(sum_two, twopow)
    ypow = bp_mul_mod(ypow, y)
    twopow = bp_mul_mod(twopow, bp_scalar_of_int(2))
  }
  ts.append_point(t1_pt) catch {
    _ => return false
  }
  ts.append_point(t2_pt) catch {
    _ => return false
  }
  let x = ts.challenge()
  let z2 = bp_mul_mod(z, z)
  let z3 = bp_mul_mod(z2, z)
  ts.append(bp_take_bytes(data, 132, 32))
  ts.append(bp_take_bytes(data, 164, 32))
  ts.append(bp_take_bytes(data, 196, 32))
  // Check 1: t̂·G + τ_x·H == z²·V + δ(y,z)·G
  let delta = bp_sub_mod(
    bp_mul_mod(bp_sub_mod(z, z2), sum_y),
    bp_mul_mod(z3, sum_two),
  )
  let x2 = bp_mul_mod(x, x)
  let lhs = bp_add(bp_scalar_mul(t_hat, key.g), bp_scalar_mul(taux, key.h))
  let rhs = bp_add(
    bp_add(bp_scalar_mul(z2, v_pt), bp_scalar_mul(delta, key.g)),
    bp_add(bp_scalar_mul(x, t1_pt), bp_scalar_mul(x2, t2_pt)),
  )
  if !bp_point_eq(lhs, rhs) {
    return false
  }
  // Reconstruct P = A + x·S − μ·H − z·ΣG_i + z·ΣH'_i + z²·⟨2^n, h'⟩.
  let y_inv = bp_inv(y)
  let h_prime : Array[BpPoint] = []
  let mut yinv_pow = @bigint.one()
  for i = 0; i < n; i = i + 1 {
    h_prime.push(bp_scalar_mul(yinv_pow, key.h_vec[i]))
    yinv_pow = bp_mul_mod(yinv_pow, y_inv)
  }
  let mut p_pt = bp_add(a_pt, bp_scalar_mul(x, s_pt))
  p_pt = bp_add(p_pt, bp_neg(bp_scalar_mul(mu, key.h)))
  // − z · Σ G_i + <z*y^n + z^2*2^n, h'>
  let mut g_sum = bp_infinity()
  for i = 0; i < n; i = i + 1 {
    g_sum = bp_add(g_sum, key.g_vec[i])
  }
  p_pt = bp_add(p_pt, bp_neg(bp_scalar_mul(z, g_sum)))
  for i = 0; i < n; i = i + 1 {
    let coef = bp_add_mod(bp_mul_mod(z, y_vec[i]), bp_mul_mod(z2, two_vec[i]))
    p_pt = bp_add(p_pt, bp_scalar_mul(coef, h_prime[i]))
  }
  // The inner-product argument proves against P + t̂·U.
  p_pt = bp_add(p_pt, bp_scalar_mul(t_hat, key.u))
  // IPA verification: fold with round challenges, then check the
  // final scalar relation.
  let mut gvec = key.g_vec
  let mut hvec = h_prime
  let mut p_acc = p_pt
  let mut off = 228
  for _i = 0; _i < BP_ROUNDS; _i = _i + 1 {
    let l_pt = match bp_take_point(data, off) {
      Some(pt) => pt
      None => return false
    }
    let r_pt = match bp_take_point(data, off + 33) {
      Some(pt) => pt
      None => return false
    }
    ts.append_point(l_pt) catch {
      _ => return false
    }
    ts.append_point(r_pt) catch {
      _ => return false
    }
    let u_ch = ts.challenge()
    let u_inv = bp_inv(u_ch)
    let u_sq = bp_mul_mod(u_ch, u_ch)
    let u_inv_sq = bp_mul_mod(u_inv, u_inv)
    p_acc = bp_add(
      bp_add(p_acc, bp_scalar_mul(u_sq, l_pt)),
      bp_scalar_mul(u_inv_sq, r_pt),
    )
    // Fold generators.
    let len = gvec.length()
    let half = len / 2
    let new_g : Array[BpPoint] = []
    let new_h : Array[BpPoint] = []
    for j = 0; j < half; j = j + 1 {
      new_g.push(
        bp_add(
          bp_scalar_mul(u_inv, gvec[j]),
          bp_scalar_mul(u_ch, gvec[half + j]),
        ),
      )
      new_h.push(
        bp_add(
          bp_scalar_mul(u_ch, hvec[j]),
          bp_scalar_mul(u_inv, hvec[half + j]),
        ),
      )
    }
    gvec = new_g
    hvec = new_h
    off = off + 66
  }
  let a_final = bp_take_scalar(data, off)
  let b_final = bp_take_scalar(data, off + 32)
  // Final relation: P_acc == a·G_f + b·H_f + a·b·U
  let expected = bp_add(
    bp_add(bp_scalar_mul(a_final, gvec[0]), bp_scalar_mul(b_final, hvec[0])),
    bp_scalar_mul(bp_mul_mod(a_final, b_final), key.u),
  )
  bp_point_eq(p_acc, expected)
}

///|
fn bp_point_eq(a : BpPoint, b : BpPoint) -> Bool {
  match (bp_to_affine(a), bp_to_affine(b)) {
    (Some((ax, ay)), Some((bx, by))) =>
      @bigint.compare(ax, bx) == 0 && @bigint.compare(ay, by) == 0
    (None, None) => true
    _ => false
  }
}
