///|
/// Threshold Signatures — Shamir-Keyed Threshold Schnorr over
/// secp256k1
///
/// A (t, n) threshold signature scheme: the Schnorr signing key x is
/// shared with Shamir secret sharing; any t parties can jointly produce
/// a standard Schnorr signature verifiable against the single group
/// public key P = x·G, while fewer than t parties learn nothing about x
/// and cannot sign.
///
/// ## Protocol (two rounds, honest signer set known in advance)
///
/// 1. **Nonce round** — each signer generates a nonce pair and shares
///    the commitment R_i = k_i·G (`threshold_nonce_generate`).
/// 2. **Sign round** — each signer computes the challenge
///    e = H(R ‖ P ‖ m) where R = Σ λ_i·R_i (λ_i the Lagrange
///    coefficient at 0 over the signer set) and emits the partial
///    signature s_i = λ_i·(k_i + e·x_i) mod n
///    (`threshold_sign_partial`).
/// 3. **Combine** — s = Σ s_i yields a valid Schnorr signature because
///    s = Σ λ_i·k_i + e·Σ λ_i·x_i = k + e·x with R = k·G
///    (`threshold_combine_signatures`, which rejects any partial that
///    fails its per-signer verification equation).
///
/// Verification is standard Schnorr: s·G == R + e·P.
///
/// ## Security notes
///
/// - Nonces are drawn from a ChaCha20 CSPRNG; reusing a nonce secret
///   for two messages leaks the share. Generate a fresh nonce pair per
///   signing session.
/// - Deterministic challenge e = SHA-256(R ‖ P ‖ m) (random-oracle
///   model). Signature encoding: 33-byte compressed R followed by
///   32-byte big-endian s (65 bytes total).
/// - Scalar multiplication is plain double-and-add, not constant time.
///
/// ## References
///
/// - Shamir, "How to Share a Secret." CACM 1979.
/// - Desmedt, Frankel. "Shared Generation of Authenticators and
///   Signatures." CRYPTO 1991.
/// - Boneh, Lynn, Shacham. "Short Signatures from the Weil Pairing"
///   (Schnorr baseline). secp256k1: SEC 2 v2.
///
/// `proof-enabled` is `false`.

// ===========================================================================
// secp256k1 group parameters (SEC 2 v2)
// ===========================================================================

///|
fn ts_parse_const(s : String, name : String) -> @bigint.BigInt {
  match @bigint.from_string(s) {
    Some(v) => v
    None => abort("FATAL: invalid threshold_sig curve constant: " + name)
  }
}

///|
/// Field prime p = 2^256 - 2^32 - 977.
pub let ts_p : @bigint.BigInt = ts_parse_const(
  "0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F", "p",
)

///|
/// Group order n.
pub let ts_n : @bigint.BigInt = ts_parse_const(
  "0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141", "n",
)

///|
/// Generator x coordinate.
pub let ts_gx : @bigint.BigInt = ts_parse_const(
  "0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798", "Gx",
)

///|
/// Generator y coordinate.
pub let ts_gy : @bigint.BigInt = ts_parse_const(
  "0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8", "Gy",
)

// ===========================================================================
// Field helpers
// ===========================================================================

///|
fn ts_mod(a : @bigint.BigInt, m : @bigint.BigInt) -> @bigint.BigInt {
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
fn ts_mod_add(
  a : @bigint.BigInt,
  b : @bigint.BigInt,
  m : @bigint.BigInt,
) -> @bigint.BigInt {
  ts_mod(@bigint.add(a, b), m)
}

///|
fn ts_mod_sub(
  a : @bigint.BigInt,
  b : @bigint.BigInt,
  m : @bigint.BigInt,
) -> @bigint.BigInt {
  ts_mod(@bigint.sub(a, b), m)
}

///|
fn ts_mod_mul(
  a : @bigint.BigInt,
  b : @bigint.BigInt,
  m : @bigint.BigInt,
) -> @bigint.BigInt {
  @bigint.mod_mul(a, b, m)
}

///|
fn ts_mod_inv(a : @bigint.BigInt, m : @bigint.BigInt) -> @bigint.BigInt {
  match @bigint.mod_pow(a, @bigint.sub(m, @bigint.from_int_value(2)), m) {
    Some(r) => r
    None => @bigint.zero()
  }
}

// ===========================================================================
// Byte <-> scalar encoding
// ===========================================================================

///|
fn ts_bigint_to_32(b : @bigint.BigInt) -> Bytes {
  let arr = Array::make(32, b'\x00')
  let mut v = b
  let base = @bigint.from_int_value(256)
  for i = 31; i >= 0; i = i - 1 {
    match @bigint.divmod(v, base) {
      Some((q, r)) => {
        match @bigint.to_int(r) {
          Some(rv) => arr[i] = rv.to_byte()
          None => ()
        }
        v = q
      }
      None => ()
    }
  }
  Bytes::from_array(arr)
}

///|
fn ts_bytes_to_bigint(b : Bytes) -> @bigint.BigInt {
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

// ===========================================================================
// Group arithmetic (Jacobian coordinates)
// ===========================================================================

///|
priv struct TsPoint {
  x : @bigint.BigInt
  y : @bigint.BigInt
  z : @bigint.BigInt
}

///|
fn ts_point_infinity() -> TsPoint {
  { x: @bigint.one(), y: @bigint.one(), z: @bigint.zero(), }
}

///|
fn ts_is_infinity(pt : TsPoint) -> Bool {
  @bigint.is_zero(pt.z)
}

///|
fn ts_point_double(pt : TsPoint) -> TsPoint {
  if ts_is_infinity(pt) || @bigint.is_zero(pt.y) {
    return ts_point_infinity()
  }
  let p = ts_p
  let one = @bigint.one()
  let two = @bigint.from_int_value(2)
  let three = @bigint.from_int_value(3)
  let four = @bigint.from_int_value(4)
  let eight = @bigint.from_int_value(8)
  let ysq = ts_mod_mul(pt.y, pt.y, p)
  let s = ts_mod_mul(four, ts_mod_mul(pt.x, ysq, p), p)
  let xsq = ts_mod_mul(pt.x, pt.x, p)
  let m = ts_mod_mul(three, xsq, p) // a = 0 for secp256k1
  let xsq8 = ts_mod_mul(eight, ts_mod_mul(ysq, ysq, p), p)
  let xr = ts_mod_sub(ts_mod_mul(m, m, p), ts_mod_mul(two, s, p), p)
  let yr = ts_mod_sub(ts_mod_mul(m, ts_mod_sub(s, xr, p), p), xsq8, p)
  let zr = ts_mod_mul(two, ts_mod_mul(pt.y, pt.z, p), p)
  let _ = one
  { x: xr, y: yr, z: zr, }
}

///|
fn ts_point_add(a : TsPoint, b : TsPoint) -> TsPoint {
  if ts_is_infinity(a) {
    return b
  }
  if ts_is_infinity(b) {
    return a
  }
  let p = ts_p
  let two = @bigint.from_int_value(2)
  let u1 = ts_mod_mul(a.x, ts_mod_mul(b.z, b.z, p), p)
  let u2 = ts_mod_mul(b.x, ts_mod_mul(a.z, a.z, p), p)
  let s1 = ts_mod_mul(a.y, ts_mod_mul(b.z, ts_mod_mul(b.z, b.z, p), p), p)
  let s2 = ts_mod_mul(b.y, ts_mod_mul(a.z, ts_mod_mul(a.z, a.z, p), p), p)
  if @bigint.compare(u1, u2) == 0 {
    if @bigint.compare(s1, s2) == 0 {
      return ts_point_double(a)
    }
    return ts_point_infinity()
  }
  let h = ts_mod_sub(u2, u1, p)
  let r = ts_mod_sub(s2, s1, p)
  let h2 = ts_mod_mul(h, h, p)
  let h3 = ts_mod_mul(h, h2, p)
  let u1h2 = ts_mod_mul(u1, h2, p)
  let xr = ts_mod_sub(
    ts_mod_sub(ts_mod_mul(r, r, p), h3, p),
    ts_mod_mul(two, u1h2, p),
    p,
  )
  let yr = ts_mod_sub(
    ts_mod_mul(r, ts_mod_sub(u1h2, xr, p), p),
    ts_mod_mul(s1, h3, p),
    p,
  )
  let zr = ts_mod_mul(h, ts_mod_mul(a.z, b.z, p), p)
  { x: xr, y: yr, z: zr, }
}

///|
fn ts_to_affine(pt : TsPoint) -> (@bigint.BigInt, @bigint.BigInt)? {
  if ts_is_infinity(pt) {
    return None
  }
  let p = ts_p
  let zinv = ts_mod_inv(pt.z, p)
  let zinv2 = ts_mod_mul(zinv, zinv, p)
  let zinv3 = ts_mod_mul(zinv2, zinv, p)
  Some((ts_mod_mul(pt.x, zinv2, p), ts_mod_mul(pt.y, zinv3, p)))
}

///|
fn ts_div2(v : @bigint.BigInt) -> (@bigint.BigInt, Bool) {
  match @bigint.divmod(v, @bigint.from_int_value(2)) {
    Some((q, r)) => (q, @bigint.compare(r, @bigint.zero()) != 0)
    None => (@bigint.zero(), false)
  }
}

///|
/// Scalar multiplication (double-and-add, not constant time).
fn ts_scalar_mul(k : @bigint.BigInt, pt : TsPoint) -> TsPoint {
  if @bigint.is_zero(k) || ts_is_infinity(pt) {
    return ts_point_infinity()
  }
  let mut result = ts_point_infinity()
  let mut addend = pt
  let mut v = k
  while @bigint.compare(v, @bigint.zero()) > 0 {
    let (q, odd) = ts_div2(v)
    if odd {
      result = ts_point_add(result, addend)
    }
    addend = ts_point_double(addend)
    v = q
  }
  result
}

///|
fn ts_generator() -> TsPoint {
  { x: ts_gx, y: ts_gy, z: @bigint.one(), }
}

// ===========================================================================
// Point encoding (SEC1 compressed, 33 bytes)
// ===========================================================================

///|
fn ts_point_compress(pt : TsPoint) -> Bytes? {
  match ts_to_affine(pt) {
    Some((x, y)) => {
      let prefix = match @bigint.divmod(y, @bigint.from_int_value(2)) {
        Some((_, r)) =>
          if @bigint.compare(r, @bigint.zero()) == 0 {
            b'\x02'
          } else {
            b'\x03'
          }
        None => b'\x02'
      }
      let xb = ts_bigint_to_32(x)
      let arr : Array[Byte] = [prefix]
      for i = 0; i < 32; i = i + 1 {
        arr.push(xb[i])
      }
      Some(Bytes::from_array(arr))
    }
    None => None
  }
}

///|
fn ts_point_decompress(data : Bytes) -> TsPoint? {
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
  let x = ts_bytes_to_bigint(Bytes::from_array(xarr))
  if @bigint.compare(x, ts_p) >= 0 {
    return None
  }
  let p = ts_p
  let seven = @bigint.from_int_value(7)
  let three = @bigint.from_int_value(3)
  let four = @bigint.from_int_value(4)
  // y^2 = x^3 + 7
  let y2 = ts_mod_add(ts_mod_mul(ts_mod_mul(x, x, p), x, p), seven, p)
  // p = 3 (mod 4): sqrt = y2^((p+1)/4)
  let exp = match @bigint.divmod(@bigint.add(p, @bigint.one()), four) {
    Some((q, _)) => q
    None => return None
  }
  let y = match @bigint.mod_pow(y2, exp, p) {
    Some(v) => v
    None => return None
  }
  // Verify the square root is genuine.
  if @bigint.compare(ts_mod_mul(y, y, p), y2) != 0 {
    return None
  }
  let y_is_odd = match @bigint.divmod(y, @bigint.from_int_value(2)) {
    Some((_, r)) => @bigint.compare(r, @bigint.zero()) != 0
    None => false
  }
  let want_odd = prefix == 3
  let y_final = if y_is_odd == want_odd { y } else { ts_mod_sub(p, y, p) }
  let _ = three
  Some({ x, y: y_final, z: @bigint.one(), })
}

// ===========================================================================
// Challenge and randomness
// ===========================================================================

///|
fn ts_challenge(
  r_enc : Bytes,
  p_enc : Bytes,
  message : Bytes,
) -> @bigint.BigInt {
  let h = @sha256.sha256(r_enc + p_enc + message)
  ts_mod(ts_bytes_to_bigint(h), ts_n)
}

///|
fn ts_rng(seed : Bytes) -> @chacha20.ChaCha20Rng raise {
  let key = @sha256.sha256(seed)
  let nsrc = @sha256.sha256(seed + b"threshold-nonce")
  let narr : Array[Byte] = []
  for i = 0; i < 12; i = i + 1 {
    narr.push(nsrc[i])
  }
  match @chacha20.create_rng(key, Bytes::from_array(narr)) {
    Some(r) => r
    None => fail("threshold_sig: CSPRNG init failed")
  }
}

///|
/// Uniform random scalar in [1, n-1] via rejection sampling.
fn ts_rand_scalar(rng : @chacha20.ChaCha20Rng) -> @bigint.BigInt raise {
  let mut result : @bigint.BigInt? = None
  while result is None {
    match @chacha20.next_bytes(rng, 32) {
      Some(bs) => {
        let v = ts_mod(ts_bytes_to_bigint(bs), ts_n)
        if !@bigint.is_zero(v) {
          result = Some(v)
        }
      }
      None => fail("threshold_sig: CSPRNG exhausted")
    }
  }
  match result {
    Some(v) => v
    None => fail("threshold_sig: scalar sampling failed")
  }
}

// ===========================================================================
// Shamir sharing over the scalar field
// ===========================================================================

///|
/// A threshold key share: the party's index and its Shamir share of
/// the group secret key.
pub struct KeyShare {
  /// Party index (1..n), also the Shamir x-coordinate.
  index : Int
  /// Shamir share value in [1, n-1].
  value : Bytes
}

///|
fn ts_poly_eval(
  coeffs : Array[@bigint.BigInt],
  x : @bigint.BigInt,
) -> @bigint.BigInt {
  let mut acc = @bigint.zero()
  for i = coeffs.length() - 1; i >= 0; i = i - 1 {
    acc = ts_mod_add(ts_mod_mul(acc, x, ts_n), coeffs[i], ts_n)
  }
  acc
}

///|
/// Lagrange coefficient at 0 for party `i` within the signer set.
fn ts_lagrange_at_zero(signer_indices : Array[Int], i : Int) -> @bigint.BigInt {
  let xi = @bigint.from_int_value(signer_indices[i])
  let mut num = @bigint.one()
  let mut den = @bigint.one()
  for j = 0; j < signer_indices.length(); j = j + 1 {
    if i != j {
      let xj = @bigint.from_int_value(signer_indices[j])
      num = ts_mod_mul(num, ts_mod_sub(@bigint.zero(), xj, ts_n), ts_n)
      den = ts_mod_mul(den, ts_mod_sub(xi, xj, ts_n), ts_n)
    }
  }
  ts_mod_mul(num, ts_mod_inv(den, ts_n), ts_n)
}

///|
/// Generate a (t, n) threshold key. Returns the group public key
/// (33-byte compressed encoding) and n key shares.
pub fn threshold_keygen(
  n : Int,
  t : Int,
  seed : Bytes,
) -> (Bytes, Array[KeyShare]) raise {
  if t < 1 || n < t {
    fail("threshold_sig: requires 1 <= t <= n")
  }
  let rng = ts_rng(seed)
  let coeffs : Array[@bigint.BigInt] = []
  for _i = 0; _i < t; _i = _i + 1 {
    coeffs.push(ts_rand_scalar(rng))
  }
  let secret = coeffs[0]
  let pubkey = match ts_point_compress(ts_scalar_mul(secret, ts_generator())) {
    Some(enc) => enc
    None => fail("threshold_sig: invalid public key")
  }
  let shares : Array[KeyShare] = []
  for idx = 1; idx <= n; idx = idx + 1 {
    let x = @bigint.from_int_value(idx)
    let v = ts_poly_eval(coeffs, x)
    shares.push({ index: idx, value: ts_bigint_to_32(v), })
  }
  (pubkey, shares)
}

///|
/// Reconstruct the group secret key from t or more shares.
///
/// WARNING: this defeats the threshold property; provided for key
/// recovery/backup and testing only.
pub fn threshold_reconstruct(shares : Array[KeyShare]) -> Bytes raise {
  if shares.length() == 0 {
    fail("threshold_sig: no shares")
  }
  let indices : Array[Int] = []
  for s in shares {
    indices.push(s.index)
  }
  let mut acc = @bigint.zero()
  for i = 0; i < shares.length(); i = i + 1 {
    let li = ts_lagrange_at_zero(indices, i)
    let v = ts_bytes_to_bigint(shares[i].value)
    acc = ts_mod_add(acc, ts_mod_mul(li, v, ts_n), ts_n)
  }
  ts_bigint_to_32(acc)
}

// ===========================================================================
// Signing protocol
// ===========================================================================

///|
/// A nonce pair for one signing session: the secret scalar (keep
/// private until the sign round) and its commitment R_i = k_i·G
/// (33-byte compressed encoding, share with the other signers).
pub struct NoncePair {
  secret : Bytes
  commitment : Bytes
}

///|
/// Generate a fresh nonce pair for a signing session. Never reuse a
/// nonce secret across messages.
pub fn threshold_nonce_generate(seed : Bytes) -> NoncePair raise {
  let rng = ts_rng(seed)
  let k = ts_rand_scalar(rng)
  let comm = match ts_point_compress(ts_scalar_mul(k, ts_generator())) {
    Some(c) => c
    None => fail("threshold_sig: invalid nonce commitment")
  }
  { secret: ts_bigint_to_32(k), commitment: comm, }
}

///|
/// Produce one partial signature.
///
/// - `share`: this party's key share.
/// - `signer_indices`: indices of all participating parties (>= t),
///   including this party's.
/// - `commitments`: nonce commitments aligned with `signer_indices`.
/// - `nonce`: this party's nonce pair for the session.
/// - `pubkey`: the group public key (from `threshold_keygen`).
/// - `message`: the message to sign.
///
/// Returns the 32-byte partial scalar s_i = λ_i·(k_i + e·x_i) mod n.
pub fn threshold_sign_partial(
  share : KeyShare,
  signer_indices : Array[Int],
  commitments : Array[Bytes],
  nonce : NoncePair,
  pubkey : Bytes,
  message : Bytes,
) -> Bytes raise {
  if signer_indices.length() != commitments.length() {
    fail("threshold_sig: indices/commitments length mismatch")
  }
  let mut my_pos = -1
  for i = 0; i < signer_indices.length(); i = i + 1 {
    if signer_indices[i] == share.index {
      my_pos = i
    }
  }
  if my_pos < 0 {
    fail("threshold_sig: share index not in signer set")
  }
  // Combined nonce R = Σ λ_i·R_i and challenge e = H(R ‖ P ‖ m).
  let r_enc = match
    ts_point_compress(ts_combine_nonce_point(signer_indices, commitments)) {
    Some(enc) => enc
    None => fail("threshold_sig: combined nonce is the identity")
  }
  let e = ts_challenge(r_enc, pubkey, message)
  let li = ts_lagrange_at_zero(signer_indices, my_pos)
  let ki = ts_bytes_to_bigint(nonce.secret)
  let xi = ts_bytes_to_bigint(share.value)
  let si = ts_mod_mul(li, ts_mod_add(ki, ts_mod_mul(e, xi, ts_n), ts_n), ts_n)
  ts_bigint_to_32(si)
}

///|
fn ts_combine_nonce_point(
  signer_indices : Array[Int],
  commitments : Array[Bytes],
) -> TsPoint {
  let mut acc = ts_point_infinity()
  for i = 0; i < commitments.length(); i = i + 1 {
    let li = ts_lagrange_at_zero(signer_indices, i)
    match ts_point_decompress(commitments[i]) {
      Some(pt) => acc = ts_point_add(acc, ts_scalar_mul(li, pt))
      None => ()
    }
  }
  acc
}

///|
/// Combine partial signatures into a standard Schnorr signature.
///
/// Every partial is first checked against its verification equation
/// s_i·G == λ_i·R_i + e·λ_i·P_i (with P_i = x_i·G recomputed from the
/// corresponding share), so a faulty or malicious partial is rejected
/// instead of corrupting the signature.
///
/// Returns the 65-byte signature: 33-byte compressed R followed by
/// 32-byte big-endian s.
pub fn threshold_combine_signatures(
  partials : Array[Bytes],
  shares : Array[KeyShare],
  signer_indices : Array[Int],
  commitments : Array[Bytes],
  pubkey : Bytes,
  message : Bytes,
) -> Bytes raise {
  let m = partials.length()
  if m != signer_indices.length() ||
    m != commitments.length() ||
    m != shares.length() {
    fail("threshold_sig: argument length mismatch")
  }
  let r_enc = match
    ts_point_compress(ts_combine_nonce_point(signer_indices, commitments)) {
    Some(enc) => enc
    None => fail("threshold_sig: combined nonce is the identity")
  }
  let e = ts_challenge(r_enc, pubkey, message)
  let g = ts_generator()
  let mut s = @bigint.zero()
  for i = 0; i < m; i = i + 1 {
    let si = ts_bytes_to_bigint(partials[i])
    let li = ts_lagrange_at_zero(signer_indices, i)
    // Per-partial verification: s_i·G == λ_i·R_i + e·λ_i·P_i.
    let lhs = ts_scalar_mul(si, g)
    let ri = match ts_point_decompress(commitments[i]) {
      Some(pt) => pt
      None => fail("threshold_sig: malformed commitment")
    }
    let xi = ts_bytes_to_bigint(shares[i].value)
    let pi = ts_scalar_mul(xi, g)
    let li_e = ts_mod_mul(li, e, ts_n)
    let rhs = ts_point_add(ts_scalar_mul(li, ri), ts_scalar_mul(li_e, pi))
    match (ts_to_affine(lhs), ts_to_affine(rhs)) {
      (Some((lx, ly)), Some((rx, ry))) =>
        if @bigint.compare(lx, rx) != 0 || @bigint.compare(ly, ry) != 0 {
          fail("threshold_sig: partial signature failed verification")
        }
      _ => fail("threshold_sig: degenerate partial")
    }
    s = ts_mod_add(s, si, ts_n)
  }
  let sarr = ts_bigint_to_32(s)
  let out : Array[Byte] = []
  for i = 0; i < r_enc.length(); i = i + 1 {
    out.push(r_enc[i])
  }
  for i = 0; i < 32; i = i + 1 {
    out.push(sarr[i])
  }
  Bytes::from_array(out)
}

///|
/// Verify a combined threshold Schnorr signature against the group
/// public key — identical to verifying an ordinary Schnorr signature.
pub fn threshold_verify(
  pubkey : Bytes,
  message : Bytes,
  signature : Bytes,
) -> Bool {
  if signature.length() != 65 {
    return false
  }
  let renc_arr : Array[Byte] = []
  for i = 0; i < 33; i = i + 1 {
    renc_arr.push(signature[i])
  }
  let r_enc = Bytes::from_array(renc_arr)
  let sarr : Array[Byte] = []
  for i = 33; i < 65; i = i + 1 {
    sarr.push(signature[i])
  }
  let s = ts_bytes_to_bigint(Bytes::from_array(sarr))
  if @bigint.compare(s, ts_n) >= 0 || @bigint.is_zero(s) {
    return false
  }
  let r_pt = match ts_point_decompress(r_enc) {
    Some(pt) => pt
    None => return false
  }
  let p_pt = match ts_point_decompress(pubkey) {
    Some(pt) => pt
    None => return false
  }
  let e = ts_challenge(r_enc, pubkey, message)
  // s·G == R + e·P
  let lhs = ts_scalar_mul(s, ts_generator())
  let rhs = ts_point_add(r_pt, ts_scalar_mul(e, p_pt))
  match (ts_to_affine(lhs), ts_to_affine(rhs)) {
    (Some((lx, ly)), Some((rx, ry))) =>
      @bigint.compare(lx, rx) == 0 && @bigint.compare(ly, ry) == 0
    _ => false
  }
}
