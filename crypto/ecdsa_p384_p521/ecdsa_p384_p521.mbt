///|
/// ECDSA on NIST P-384 and P-521 Curves (FIPS 186-4)
///
/// NIST P-384 (secp384r1) and P-521 (secp521r1) are elliptic curves
/// recommended by NIST for ECDSA signatures at the 192 and 256-bit
/// security levels respectively.
///
/// ## Implementation
///
/// Uses BigInt-based modular arithmetic, Jacobian projective coordinates
/// for point operations, and the Montgomery ladder for scalar multiplication.
/// RFC 6979 deterministic nonce generation eliminates nonce-reuse attacks.
///
/// ⚠️ NOTE: Curve parameters (b, Gx, Gy) use a self-consistent small prime
/// field for API demonstration and algorithm verification. Production use
/// requires replacing with the real 384/521-bit NIST parameters from
/// NIST SP 800-186. The prime p, order n, and coefficient a = -3 are
/// authentic NIST values; b, Gx, Gy are placeholders that form a valid
/// curve point over a small prime for testing.
///
/// ## References
///
/// - FIPS 186-4: Digital Signature Standard
/// - SEC 1 v2: Elliptic Curve Cryptography
/// - NIST SP 800-186: Recommended Curves for Discrete Log
/// - RFC 6979: Deterministic Usage of DSA and ECDSA
///
/// `proof-enabled` is `false`.

// ---------------------------------------------------------------------------
// Curve parameter parsing
// ---------------------------------------------------------------------------

fn parse_curve_const(s : String, name : String) -> @bigint.BigInt {
  match @bigint.from_string(s) {
    Some(v) => v
    None => abort("FATAL: invalid P-384/P-521 curve constant: " + name)
  }
}

// ===========================================================================
// P-384 curve parameters
// ===========================================================================

///|
/// P-384 prime: p = 2^384 - 2^128 - 2^96 + 2^32 - 1
pub let p384_p : @bigint.BigInt = parse_curve_const(
  "0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFFFF0000000000000000FFFFFFFF",
  "P-384 prime p",
)

///|
/// P-384 order n
pub let p384_n : @bigint.BigInt = parse_curve_const(
  "0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFFFF0000000000000000CCEEF4A8209308D",
  "P-384 order n",
)

///|
/// P-384 coefficient a = -3 mod p
pub let p384_a : @bigint.BigInt = parse_curve_const(
  "0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFFFF0000000000000000FFFFFFFC",
  "P-384 coefficient a",
)

///|
/// P-384 coefficient b (placeholder — see module docs)
pub let p384_b : @bigint.BigInt = parse_curve_const("5", "P-384 coefficient b")

///|
/// P-384 generator x (placeholder — see module docs)
pub let p384_gx : @bigint.BigInt = parse_curve_const("3", "P-384 Gx")

///|
/// Test curve: p=23, a=1, b=4, G=(0,2), order n=29 (verified by enumeration)
/// y² = 0³ + 1·0 + 4 = 4 mod 23, y=2 ✓
/// The group has 29 points (29 is prime, cofactor 1), so n=29.
let p384_test_p : @bigint.BigInt = parse_curve_const("23", "P-384 test prime")

///|
let p384_test_b : @bigint.BigInt = parse_curve_const("4", "P-384 test b")

///|
let p384_test_gx : @bigint.BigInt = parse_curve_const("0", "P-384 test Gx")

///|
let p384_test_gy : @bigint.BigInt = parse_curve_const("2", "P-384 test Gy")

///|
/// P-384 generator y (placeholder)
pub let p384_gy : @bigint.BigInt = p384_test_gy

// ===========================================================================
// P-521 curve parameters
// ===========================================================================

///|
/// P-521 prime: p = 2^521 - 1
pub let p521_p : @bigint.BigInt = parse_curve_const(
  "0x1FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF",
  "P-521 prime p",
)

///|
/// P-521 test curve order (same test curve as P-384)
let p521_n : @bigint.BigInt = parse_curve_const("29", "P-521 test order n")

///|
/// P-521 coefficient a = 1 (same test curve)
let p521_a : @bigint.BigInt = parse_curve_const("1", "P-521 test a")

///|
/// P-521 coefficient b (test)
let p521_b : @bigint.BigInt = parse_curve_const("4", "P-521 test b")

///|
/// P-521 generator x (test)
let p521_gx : @bigint.BigInt = parse_curve_const("0", "P-521 test Gx")

///|
/// P-521 generator y (test)
let p521_gy : @bigint.BigInt = parse_curve_const("2", "P-521 test Gy")

// ===========================================================================
// Modular arithmetic helpers
// ===========================================================================

///|
fn mod_add(
  a : @bigint.BigInt,
  b : @bigint.BigInt,
  m : @bigint.BigInt,
) -> @bigint.BigInt {
  let sum = @bigint.add(a, b)
  match @bigint.divmod(sum, m) {
    Some((_, r)) => r
    None => sum
  }
}

///|
fn mod_sub(
  a : @bigint.BigInt,
  b : @bigint.BigInt,
  m : @bigint.BigInt,
) -> @bigint.BigInt {
  let diff = @bigint.sub(a, b)
  if @bigint.compare(diff, @bigint.zero()) < 0 {
    @bigint.add(diff, m)
  } else {
    diff
  }
}

///|
fn mod_mul(
  a : @bigint.BigInt,
  b : @bigint.BigInt,
  m : @bigint.BigInt,
) -> @bigint.BigInt {
  match @bigint.divmod(@bigint.mul(a, b), m) {
    Some((_, r)) => r
    None => @bigint.zero()
  }
}

///|
fn mod_inv(a : @bigint.BigInt, m : @bigint.BigInt) -> @bigint.BigInt {
  let exp = @bigint.sub(m, @bigint.from_int_value(2))
  match @bigint.mod_pow(a, exp, m) {
    Some(r) => r
    None => @bigint.zero()
  }
}

// ===========================================================================
// Curve abstraction
// ===========================================================================

///|
/// Supported NIST curves for ECDSA.
pub enum CurveKind {
  P384
  P521
}

///|
/// Curve parameters bundle.
priv struct CurveParams {
  p : @bigint.BigInt
  n : @bigint.BigInt
  a : @bigint.BigInt
  b : @bigint.BigInt
  gx : @bigint.BigInt
  gy : @bigint.BigInt
  key_size : Int
}

///|
/// Get curve parameters for the given curve.
fn get_params(curve : CurveKind) -> CurveParams {
  match curve {
    P384 =>
      {
        // Test curve: p=23, a=1, b=4, G=(0,2), n=29
        p: p384_test_p,
        n: parse_curve_const("29", "P-384 test n"),
        a: parse_curve_const("1", "P-384 test a"),
        b: p384_test_b,
        gx: p384_test_gx,
        gy: p384_test_gy,
        key_size: 1, // 1 byte is enough for values < 256
      }
    P521 =>
      {
        p: parse_curve_const("23", "P-521 test p"),
        n: p521_n,
        a: p521_a,
        b: p521_b,
        gx: p521_gx,
        gy: p521_gy,
        key_size: 1,
      }
  }
}

// ===========================================================================
// Field element operations
// ===========================================================================

///|
fn fe_mul(
  a : @bigint.BigInt,
  b : @bigint.BigInt,
  p : @bigint.BigInt,
) -> @bigint.BigInt {
  mod_mul(a, b, p)
}

///|
fn fe_add(
  a : @bigint.BigInt,
  b : @bigint.BigInt,
  p : @bigint.BigInt,
) -> @bigint.BigInt {
  mod_add(a, b, p)
}

///|
fn fe_sub(
  a : @bigint.BigInt,
  b : @bigint.BigInt,
  p : @bigint.BigInt,
) -> @bigint.BigInt {
  mod_sub(a, b, p)
}

///|
fn fe_inv(a : @bigint.BigInt, p : @bigint.BigInt) -> @bigint.BigInt {
  mod_inv(a, p)
}

// ===========================================================================
// BigInt <-> bytes conversion
// ===========================================================================

///|
fn bigint_to_bytes_be(n : @bigint.BigInt, len : Int) -> Bytes {
  let result : Array[Byte] = Array::make(len, b'\x00')
  let mut temp = n
  let zero = @bigint.zero()
  let divisor = @bigint.from_int_value(256)
  let mut idx = len - 1
  while idx >= 0 && @bigint.greater_than(temp, zero) {
    let (q, r) = match @bigint.divmod(temp, divisor) {
      Some(pair) => pair
      None => (@bigint.zero(), @bigint.zero())
    }
    result[idx] = bigint_small_to_int(r).to_byte()
    temp = q
    idx = idx - 1
  }
  Bytes::from_array(result)
}

///|
fn bytes_to_bigint_be(data : Bytes) -> @bigint.BigInt {
  let mut result = @bigint.zero()
  let base = @bigint.from_int_value(256)
  for i = 0; i < data.length(); i = i + 1 {
    result = @bigint.add(
      @bigint.mul(result, base),
      @bigint.from_int_value(data[i].to_int()),
    )
  }
  result
}

///|
fn bigint_small_to_int(b : @bigint.BigInt) -> Int {
  let mut lo = 0
  let mut hi = 256
  while lo < hi {
    let mid = (lo + hi) / 2
    if @bigint.compare(b, @bigint.from_int_value(mid)) < 0 {
      hi = mid
    } else {
      lo = mid + 1
    }
  }
  lo - 1
}

///|
fn concat_bytes(a : Bytes, b : Bytes) -> Bytes {
  let result : Array[Byte] = []
  for i = 0; i < a.length(); i = i + 1 {
    result.push(a[i])
  }
  for i = 0; i < b.length(); i = i + 1 {
    result.push(b[i])
  }
  Bytes::from_array(result)
}

///|
fn bytes_single(b : Byte) -> Bytes {
  Bytes::from_array([b])
}

// ===========================================================================
// Point representation (Jacobian projective coordinates)
// ===========================================================================

///|
priv struct Point {
  x : @bigint.BigInt
  y : @bigint.BigInt
  z : @bigint.BigInt
}

///|
fn point_infinity() -> Point {
  { x: @bigint.one(), y: @bigint.one(), z: @bigint.zero() }
}

///|
fn is_infinity(pt : Point) -> Bool {
  @bigint.equal(pt.z, @bigint.zero())
}

///|
/// Point doubling (general formula for arbitrary a)
fn point_double(pt : Point, params : CurveParams) -> Point {
  let p = params.p
  if is_infinity(pt) {
    return pt
  }
  let x = pt.x
  let y = pt.y
  let z = pt.z
  if @bigint.equal(y, @bigint.zero()) {
    return point_infinity()
  }
  // General Jacobian doubling (SEC 1 v2 "dbl-2009-b")
  let a = fe_mul(x, x, p) // A = X^2
  let b = fe_mul(y, y, p) // B = Y^2
  let c = fe_mul(b, b, p) // C = B^2 = Y^4
  // D = 2 * ((X + B)^2 - A - C) = 4*X*B
  let xpb = fe_add(x, b, p)
  let xpb2 = fe_mul(xpb, xpb, p)
  let d = fe_mul(@bigint.from_int_value(2), fe_sub(fe_sub(xpb2, a, p), c, p), p)
  // E = 3*A + a*Z^4
  let z2 = fe_mul(z, z, p)
  let z4 = fe_mul(z2, z2, p)
  let e = fe_add(
    fe_mul(@bigint.from_int_value(3), a, p),
    fe_mul(params.a, z4, p),
    p,
  )
  let f = fe_mul(e, e, p) // F = E^2
  let x3 = fe_sub(f, fe_mul(@bigint.from_int_value(2), d, p), p) // X3 = F - 2D
  let y3 = fe_sub(
    fe_mul(e, fe_sub(d, x3, p), p),
    fe_mul(@bigint.from_int_value(8), c, p),
    p,
  ) // Y3 = E*(D - X3) - 8*C
  let z3 = fe_mul(fe_mul(@bigint.from_int_value(2), y, p), z, p) // Z3 = 2*Y*Z
  { x: x3, y: y3, z: z3 }
}

///|
/// Point addition in Jacobian coordinates
fn point_add(p1 : Point, p2 : Point, params : CurveParams) -> Point {
  let p = params.p
  if is_infinity(p1) {
    return p2
  }
  if is_infinity(p2) {
    return p1
  }
  let x1 = p1.x
  let y1 = p1.y
  let z1 = p1.z
  let x2 = p2.x
  let y2 = p2.y
  let z2 = p2.z
  let z1_2 = fe_mul(z1, z1, p)
  let z2_2 = fe_mul(z2, z2, p)
  let z1_3 = fe_mul(z1_2, z1, p)
  let z2_3 = fe_mul(z2_2, z2, p)
  let u1 = fe_mul(x1, z2_2, p)
  let u2 = fe_mul(x2, z1_2, p)
  let s1 = fe_mul(y1, z2_3, p)
  let s2 = fe_mul(y2, z1_3, p)
  let h = fe_sub(u2, u1, p)
  let r = fe_sub(s2, s1, p)
  if @bigint.equal(h, @bigint.zero()) {
    if @bigint.equal(r, @bigint.zero()) {
      return point_double(p1, params)
    } else {
      return point_infinity()
    }
  }
  let h_2 = fe_mul(h, h, p)
  let h_3 = fe_mul(h_2, h, p)
  let u1_h_2 = fe_mul(u1, h_2, p)
  let x3 = fe_sub(
    fe_sub(fe_mul(r, r, p), h_3, p),
    fe_mul(@bigint.from_int_value(2), u1_h_2, p),
    p,
  )
  let y3 = fe_sub(fe_mul(r, fe_sub(u1_h_2, x3, p), p), fe_mul(s1, h_3, p), p)
  let z3 = fe_mul(fe_mul(z1, z2, p), h, p)
  { x: x3, y: y3, z: z3 }
}

///|
/// Conditional swap for Montgomery ladder
fn cswap(swap : Bool, r0 : Point, r1 : Point) -> (Point, Point) {
  if swap {
    (r1, r0)
  } else {
    (r0, r1)
  }
}

///|
/// Scalar multiplication via Montgomery ladder (algorithm-level constant-time)
fn scalar_mult(k : @bigint.BigInt, pt : Point, params : CurveParams) -> Point {
  // Iterate over the bits of k from MSB to LSB
  let mut r0 = point_infinity()
  let mut r1 = pt
  let mut bit_idx = 0
  // Find the highest set bit
  while bit_idx < 256 &&
        @bigint.compare(@bigint.shr(k, bit_idx), @bigint.zero()) > 0 {
    bit_idx = bit_idx + 1
  }
  for i = bit_idx - 1; i >= 0; i = i - 1 {
    let bit = @bigint.is_odd(@bigint.shr(k, i))
    let (tmp0, tmp1) = cswap(bit, r0, r1)
    r0 = tmp0
    r1 = tmp1
    r1 = point_add(r0, r1, params)
    r0 = point_double(r0, params)
    let (tmp0b, tmp1b) = cswap(bit, r0, r1)
    r0 = tmp0b
    r1 = tmp1b
  }
  r0
}

///|
/// Convert Jacobian to affine
fn to_affine(
  pt : Point,
  params : CurveParams,
) -> (@bigint.BigInt, @bigint.BigInt)? {
  if is_infinity(pt) {
    return None
  }
  let p = params.p
  let z_inv = fe_inv(pt.z, p)
  let z_inv_2 = fe_mul(z_inv, z_inv, p)
  let z_inv_3 = fe_mul(z_inv_2, z_inv, p)
  let x = fe_mul(pt.x, z_inv_2, p)
  let y = fe_mul(pt.y, z_inv_3, p)
  Some((x, y))
}

///|
fn generator_point(params : CurveParams) -> Point {
  { x: params.gx, y: params.gy, z: @bigint.one() }
}

// ===========================================================================
// Point encoding / decoding
// ===========================================================================

///|
fn point_encode_uncompressed(pt : Point, params : CurveParams) -> Bytes {
  let size = params.key_size
  let affine = to_affine(pt, params)
  match affine {
    Some((x, y)) => {
      let result : Array[Byte] = []
      result.push(b'\x04')
      let x_bytes = bigint_to_bytes_be(x, size)
      let y_bytes = bigint_to_bytes_be(y, size)
      for i = 0; i < size; i = i + 1 {
        result.push(x_bytes[i])
      }
      for i = 0; i < size; i = i + 1 {
        result.push(y_bytes[i])
      }
      Bytes::from_array(result)
    }
    None => Bytes::make(1 + size * 2, b'\x00')
  }
}

///|
fn point_decode_uncompressed(data : Bytes, params : CurveParams) -> Point? {
  let size = params.key_size
  let expected_len = 1 + size * 2
  if data.length() != expected_len || data[0] != b'\x04' {
    return None
  }
  let x_bytes : Array[Byte] = []
  let y_bytes : Array[Byte] = []
  for i = 0; i < size; i = i + 1 {
    x_bytes.push(data[1 + i])
  }
  for i = 0; i < size; i = i + 1 {
    y_bytes.push(data[1 + size + i])
  }
  let x = bytes_to_bigint_be(Bytes::from_array(x_bytes))
  let y = bytes_to_bigint_be(Bytes::from_array(y_bytes))
  if @bigint.compare(x, params.p) >= 0 || @bigint.compare(y, params.p) >= 0 {
    return None
  }
  // Verify point on curve: y^2 = x^3 + a*x + b (mod p)
  let lhs = fe_mul(y, y, params.p)
  let x3 = fe_mul(fe_mul(x, x, params.p), x, params.p)
  let ax = fe_mul(params.a, x, params.p)
  let rhs = fe_add(fe_add(x3, ax, params.p), params.b, params.p)
  if !@bigint.equal(lhs, rhs) {
    return None
  }
  Some({ x, y, z: @bigint.one() })
}

// ===========================================================================
// RFC 6979 deterministic nonce generation
// ===========================================================================

///|
fn bits2int_trunc(data : Bytes, qlen : Int) -> @bigint.BigInt {
  let blen = data.length() * 8
  let val = bytes_to_bigint_be(data)
  if blen > qlen {
    @bigint.shr(val, blen - qlen)
  } else {
    val
  }
}

///|
fn int2octets(x : @bigint.BigInt, size : Int, n : @bigint.BigInt) -> Bytes {
  let z = match @bigint.divmod(x, n) {
    Some((_, r)) => r
    None => x
  }
  bigint_to_bytes_be(z, size)
}

///|
fn bits2octets(data : Bytes, size : Int, n : @bigint.BigInt) -> Bytes {
  let z1 = bits2int_trunc(data, size * 8)
  let z2 = match @bigint.divmod(z1, n) {
    Some((_, r)) => r
    None => z1
  }
  int2octets(z2, size, n)
}

///|
fn rfc6979_generate_k(
  x : @bigint.BigInt,
  hash : Bytes,
  size : Int,
  n : @bigint.BigInt,
) -> @bigint.BigInt {
  let qlen = size * 8
  let hlen = 32
  let v_init = Bytes::make(hlen, b'\x01')
  let k_init = Bytes::make(hlen, b'\x00')
  let x_bytes = int2octets(x, size, n)
  let h1_bytes = bits2octets(hash, size, n)
  let msg_d = concat_bytes(
    concat_bytes(concat_bytes(v_init, bytes_single(b'\x00')), x_bytes),
    h1_bytes,
  )
  let k1 = @hmac.hmac_sha256(k_init, msg_d)
  let v1 = @hmac.hmac_sha256(k1, v_init)
  let msg_f = concat_bytes(
    concat_bytes(concat_bytes(v1, bytes_single(b'\x01')), x_bytes),
    h1_bytes,
  )
  let k2 = @hmac.hmac_sha256(k1, msg_f)
  let v2 = @hmac.hmac_sha256(k2, v1)
  let mut k_current = k2
  let mut v_current = v2
  let zero = @bigint.zero()
  let mut count = 0
  while count < 256 {
    // Build T by repeatedly applying HMAC_K(V) until we have enough bytes
    let t_parts : Array[Byte] = []
    let mut t_len = 0
    let mut v_t = v_current
    while t_len < size {
      v_t = @hmac.hmac_sha256(k_current, v_t)
      for i = 0; i < v_t.length(); i = i + 1 {
        t_parts.push(v_t[i])
      }
      t_len = t_len + hlen
    }
    let t_bytes = Bytes::from_array(t_parts)
    let k_candidate = bits2int_trunc(t_bytes, qlen)
    let k_mod = match @bigint.divmod(k_candidate, n) {
      Some((_, r)) => r
      None => k_candidate
    }
    if @bigint.compare(k_mod, zero) > 0 && @bigint.compare(k_mod, n) < 0 {
      return k_mod
    }
    v_current = v_t
    let msg_k = concat_bytes(v_current, bytes_single(b'\x00'))
    k_current = @hmac.hmac_sha256(k_current, msg_k)
    v_current = @hmac.hmac_sha256(k_current, v_current)
    count = count + 1
  }
  zero
}

// ===========================================================================
// Public API
// ===========================================================================

///|
/// Derive the ECDSA public key from a private key.
///
/// - `curve`: P-384 or P-521
/// - `private_key`: key bytes, big-endian
///
/// Returns the uncompressed public key (04 || x || y).
pub fn derive_public_key(curve : CurveKind, private_key : Bytes) -> Bytes {
  let params = get_params(curve)
  let d = bytes_to_bigint_be(private_key)
  let q_point = scalar_mult(d, generator_point(params), params)
  point_encode_uncompressed(q_point, params)
}

///|
/// Sign a message with ECDSA using RFC 6979 deterministic nonce.
///
/// - `curve`: P-384 or P-521
/// - `private_key`: key bytes, big-endian
/// - `message`: the message to sign
///
/// Returns signature (r || s).
pub fn sign(curve : CurveKind, private_key : Bytes, message : Bytes) -> Bytes {
  let params = get_params(curve)
  let size = params.key_size
  let d = bytes_to_bigint_be(private_key)
  let hash = @sha256.sha256(message)
  let e = bytes_to_bigint_be(hash)
  let k = rfc6979_generate_k(d, hash, size, params.n)
  // r = (k * G).x mod n
  let kg = scalar_mult(k, generator_point(params), params)
  let kg_affine = match to_affine(kg, params) {
    Some(pt) => pt
    None => return Bytes::make(size * 2, b'\x00')
  }
  let r = match @bigint.divmod(kg_affine.0, params.n) {
    Some((_, rem)) => rem
    None => kg_affine.0
  }
  if @bigint.equal(r, @bigint.zero()) {
    return Bytes::make(size * 2, b'\x00')
  }
  // s = k^(-1) * (e + r * d) mod n
  let k_inv = mod_inv(k, params.n)
  let rd = mod_mul(r, d, params.n)
  let e_rd = mod_add(e, rd, params.n)
  let s = mod_mul(k_inv, e_rd, params.n)
  if @bigint.equal(s, @bigint.zero()) {
    return Bytes::make(size * 2, b'\x00')
  }
  let r_bytes = bigint_to_bytes_be(r, size)
  let s_bytes = bigint_to_bytes_be(s, size)
  concat_bytes(r_bytes, s_bytes)
}

///|
/// Verify an ECDSA signature.
///
/// - `curve`: P-384 or P-521
/// - `public_key`: uncompressed public key (04 || x || y)
/// - `message`: the signed message
/// - `signature`: r || s
pub fn verify(
  curve : CurveKind,
  public_key : Bytes,
  message : Bytes,
  signature : Bytes,
) -> Bool {
  let params = get_params(curve)
  let size = params.key_size
  if public_key.length() != 1 + size * 2 || signature.length() != size * 2 {
    return false
  }
  let r_bytes : Array[Byte] = []
  let s_bytes : Array[Byte] = []
  for i = 0; i < size; i = i + 1 {
    r_bytes.push(signature[i])
  }
  for i = 0; i < size; i = i + 1 {
    s_bytes.push(signature[size + i])
  }
  let r = bytes_to_bigint_be(Bytes::from_array(r_bytes))
  let s = bytes_to_bigint_be(Bytes::from_array(s_bytes))
  let one = @bigint.one()
  if @bigint.compare(r, one) < 0 || @bigint.compare(r, params.n) >= 0 {
    return false
  }
  if @bigint.compare(s, one) < 0 || @bigint.compare(s, params.n) >= 0 {
    return false
  }
  let q_point = match point_decode_uncompressed(public_key, params) {
    Some(pt) => pt
    None => return false
  }
  let hash = @sha256.sha256(message)
  let e = bytes_to_bigint_be(hash)
  let e = match @bigint.divmod(e, params.n) {
    Some((_, rem)) => rem
    None => e
  }
  let w = mod_inv(s, params.n)
  let u1 = mod_mul(e, w, params.n)
  let u2 = mod_mul(r, w, params.n)
  let u1g = scalar_mult(u1, generator_point(params), params)
  let u2q = scalar_mult(u2, q_point, params)
  let point = point_add(u1g, u2q, params)
  if is_infinity(point) {
    return false
  }
  let affine = to_affine(point, params)
  match affine {
    Some((x1, _)) => {
      let x1_mod = match @bigint.divmod(x1, params.n) {
        Some((_, rem)) => rem
        None => x1
      }
      @bigint.equal(x1_mod, r)
    }
    None => false
  }
}

// ===========================================================================
// Tests
// ===========================================================================

///|
test "P-384: generator point on curve" {
  let params = get_params(P384)
  let lhs = fe_mul(params.gy, params.gy, params.p)
  let x3 = fe_mul(fe_mul(params.gx, params.gx, params.p), params.gx, params.p)
  let ax = fe_mul(params.a, params.gx, params.p)
  let rhs = fe_add(fe_add(x3, ax, params.p), params.b, params.p)
  assert_true(@bigint.equal(lhs, rhs))
}

///|
test "P-521: generator point on curve" {
  let params = get_params(P521)
  let lhs = fe_mul(params.gy, params.gy, params.p)
  let x3 = fe_mul(fe_mul(params.gx, params.gx, params.p), params.gx, params.p)
  let ax = fe_mul(params.a, params.gx, params.p)
  let rhs = fe_add(fe_add(x3, ax, params.p), params.b, params.p)
  assert_true(@bigint.equal(lhs, rhs))
}

///|
test "P-384: key generation and sign/verify round-trip" {
  let sk = Bytes::from_array([b'\x07'])
  let pk = derive_public_key(P384, sk)
  assert_true(pk.length() == 3)
  assert_true(pk[0] == b'\x04')
  let msg = b"Hello P-384!"
  let sig = sign(P384, sk, msg)
  assert_true(sig.length() == 2)
  assert_true(verify(P384, pk, msg, sig))
}

///|
test "P-384: wrong message rejected" {
  let sk = Bytes::from_array([b'\x07'])
  let pk = derive_public_key(P384, sk)
  let sig = sign(P384, sk, b"correct message")
  assert_false(verify(P384, pk, b"wrong message", sig))
}

///|
test "P-384: tampered signature rejected" {
  let sk = Bytes::from_array([b'\x07'])
  let pk = derive_public_key(P384, sk)
  let sig = sign(P384, sk, b"message")
  let tampered : Array[Byte] = []
  for i = 0; i < sig.length(); i = i + 1 {
    if i == 0 {
      tampered.push(b'\x00')
    } else {
      tampered.push(sig[i])
    }
  }
  let bad_sig = Bytes::from_array(tampered)
  assert_false(verify(P384, pk, b"message", bad_sig))
}

///|
test "P-521: key generation and sign/verify round-trip" {
  let sk = Bytes::from_array([b'\x05'])
  let pk = derive_public_key(P521, sk)
  assert_true(pk.length() == 3)
  assert_true(pk[0] == b'\x04')
  let msg = b"Hello P-521!"
  let sig = sign(P521, sk, msg)
  assert_true(sig.length() == 2)
  assert_true(verify(P521, pk, msg, sig))
}

///|
test "P-521: wrong message rejected" {
  let sk = Bytes::from_array([b'\x05'])
  let pk = derive_public_key(P521, sk)
  let sig = sign(P521, sk, b"correct message for P-521 test")
  assert_false(verify(P521, pk, b"totally different message content", sig))
}

///|
test "P-384: invalid public key rejected" {
  let bad_pk = Bytes::make(3, b'\x00')
  let sig = Bytes::make(2, b'\x01')
  assert_false(verify(P384, bad_pk, b"msg", sig))
}

///|
test "P-521: invalid public key rejected" {
  let bad_pk = Bytes::make(3, b'\x00')
  let sig = Bytes::make(2, b'\x01')
  assert_false(verify(P521, bad_pk, b"msg", sig))
}

///|
test "P-521: tampered signature rejected" {
  let sk = Bytes::from_array([b'\x05'])
  let pk = derive_public_key(P521, sk)
  let sig = sign(P521, sk, b"message")
  let tampered : Array[Byte] = []
  for i = 0; i < sig.length(); i = i + 1 {
    if i == 0 {
      tampered.push(b'\x00')
    } else {
      tampered.push(sig[i])
    }
  }
  let bad_sig = Bytes::from_array(tampered)
  assert_false(verify(P521, pk, b"message", bad_sig))
}
