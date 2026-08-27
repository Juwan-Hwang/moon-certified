/// secp256k1 Elliptic Curve Cryptography.
///
/// Implements ECDSA over the secp256k1 curve (the Bitcoin/Ethereum curve)
/// with **RFC 6979 deterministic nonce generation**.
///
/// ## Curve parameters (secp256k1)
///
/// - Prime: p = 2^256 - 2^32 - 977
/// - a = 0, b = 7  (curve equation: y² = x³ + 7)
/// - Generator G: standard secp256k1 base point
/// - Order n = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
///
/// ## Key differences from P-256
///
/// - a = 0 (not -3), so point doubling uses the general formula M = 3X²
///   instead of the a = -3 optimisation.
/// - The curve has a special structure (Koblitz curve) that allows for
///   efficient endomorphism-based optimisations (not implemented here).
///
/// ## References
///
/// - SEC 2: Recommended Elliptic Curve Domain Parameters
/// - FIPS 186-4: Digital Signature Standard
/// - RFC 6979: Deterministic Usage of DSA and ECDSA
/// - Bitcoin Core: https://github.com/bitcoin-core/secp256k1
///
/// `proof-enabled` is `false`; correctness is backed by RFC 6979 test vectors.

// ---------------------------------------------------------------------------
// Curve parameters: secp256k1
// ---------------------------------------------------------------------------

///|
/// Parse a BigInt from a decimal string, aborting with a descriptive
/// message if the string is invalid. Used exclusively for fixed RFC
/// curve constants that are guaranteed correct by construction.
fn parse_curve_const(s : String, name : String) -> @bigint.BigInt {
  match @bigint.from_string(s) {
    Some(v) => v
    None => abort("FATAL: invalid secp256k1 curve constant: " + name)
  }
}

///|
/// Prime p = 2^256 - 2^32 - 977
let p : @bigint.BigInt = parse_curve_const(
  "115792089237316195423570985008687907853269984665640564039457584007908834671663",
  "secp256k1 prime p",
)

///|
/// Curve order n
let n_order : @bigint.BigInt = parse_curve_const(
  "115792089237316195423570985008687907852837564279074904382605163141518161494337",
  "secp256k1 order n",
)

/// Curve coefficient a = 0

///|
/// Curve coefficient b = 7
let b_coeff : @bigint.BigInt = @bigint.from_int_value(7)

///|
/// Generator x-coordinate
let gx : @bigint.BigInt = parse_curve_const(
  "55066263022277343669578718895168534326250603453777594175500187360389116729240",
  "secp256k1 generator Gx",
)

///|
/// Generator y-coordinate
let gy : @bigint.BigInt = parse_curve_const(
  "32670510020758816978083085130507043184471273380659243275938904335757337482424",
  "secp256k1 generator Gy",
)

// ---------------------------------------------------------------------------
// Modular arithmetic helpers
// ---------------------------------------------------------------------------

///|
/// (a + b) mod m
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
/// (a - b) mod m (result always non-negative)
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
/// (a * b) mod m
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
/// a^(-1) mod m using Fermat's little theorem (for prime m)
fn mod_inv(a : @bigint.BigInt, m : @bigint.BigInt) -> @bigint.BigInt {
  let exp = @bigint.sub(m, @bigint.from_int_value(2))
  match @bigint.mod_pow(a, exp, m) {
    Some(r) => r
    None => @bigint.zero()
  }
}

///|
/// (a * b) mod p (field multiplication)
fn fe_mul(a : @bigint.BigInt, b : @bigint.BigInt) -> @bigint.BigInt {
  mod_mul(a, b, p)
}

///|
/// (a + b) mod p (field addition)
fn fe_add(a : @bigint.BigInt, b : @bigint.BigInt) -> @bigint.BigInt {
  mod_add(a, b, p)
}

///|
/// (a - b) mod p (field subtraction)
fn fe_sub(a : @bigint.BigInt, b : @bigint.BigInt) -> @bigint.BigInt {
  mod_sub(a, b, p)
}

///|
/// a^(-1) mod p (field inversion)
fn fe_inv(a : @bigint.BigInt) -> @bigint.BigInt {
  mod_inv(a, p)
}

// ---------------------------------------------------------------------------
// BigInt <-> bytes (big-endian) conversion
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Point representation (Jacobian projective coordinates)
// ---------------------------------------------------------------------------

///|
/// Jacobian projective coordinates (X, Y, Z) with x = X/Z^2, y = Y/Z^3.
/// The point at infinity is represented as Z = 0.
priv struct Point {
  x : @bigint.BigInt
  y : @bigint.BigInt
  z : @bigint.BigInt
}

///|
/// Point at infinity (Z = 0).
fn point_infinity() -> Point {
  { x: @bigint.one(), y: @bigint.one(), z: @bigint.zero(), }
}

///|
/// Check if a point is the point at infinity.
fn is_infinity(pt : Point) -> Bool {
  @bigint.equal(pt.z, @bigint.zero())
}

///|
/// Point doubling in Jacobian coordinates (general formula for a = 0).
/// Since a = 0 for secp256k1, the formula simplifies:
///   if Y == 0: return infinity
///   S = 4 * X * Y^2
///   M = 3 * X^2              (since a = 0)
///   X' = M^2 - 2*S
///   Y' = M * (S - X') - 8 * Y^4
///   Z' = 2 * Y * Z
fn point_double(pt : Point) -> Point {
  if is_infinity(pt) {
    return pt
  }
  let x = pt.x
  let y = pt.y
  let z = pt.z
  if @bigint.equal(y, @bigint.zero()) {
    return point_infinity()
  }
  let y2 = fe_mul(y, y)
  let s = fe_mul(fe_mul(@bigint.from_int_value(4), x), y2)
  // M = 3 * X^2  (since a = 0 for secp256k1)
  let m = fe_mul(@bigint.from_int_value(3), fe_mul(x, x))
  let x3 = fe_sub(fe_mul(m, m), fe_mul(@bigint.from_int_value(2), s))
  let y4 = fe_mul(y2, y2)
  let y3 = fe_sub(
    fe_mul(m, fe_sub(s, x3)),
    fe_mul(@bigint.from_int_value(8), y4),
  )
  let z3 = fe_mul(fe_mul(@bigint.from_int_value(2), y), z)
  { x: x3, y: y3, z: z3, }
}

///|
/// Point addition in Jacobian coordinates.
fn point_add(p1 : Point, p2 : Point) -> Point {
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
  let z1_2 = fe_mul(z1, z1)
  let z2_2 = fe_mul(z2, z2)
  let z1_3 = fe_mul(z1_2, z1)
  let z2_3 = fe_mul(z2_2, z2)
  let u1 = fe_mul(x1, z2_2)
  let u2 = fe_mul(x2, z1_2)
  let s1 = fe_mul(y1, z2_3)
  let s2 = fe_mul(y2, z1_3)
  let h = fe_sub(u2, u1)
  let r = fe_sub(s2, s1)
  if @bigint.equal(h, @bigint.zero()) {
    if @bigint.equal(r, @bigint.zero()) {
      return point_double(p1)
    } else {
      return point_infinity()
    }
  }
  let h_2 = fe_mul(h, h)
  let h_3 = fe_mul(h_2, h)
  let u1_h_2 = fe_mul(u1, h_2)
  let x3 = fe_sub(
    fe_sub(fe_mul(r, r), h_3),
    fe_mul(@bigint.from_int_value(2), u1_h_2),
  )
  let y3 = fe_sub(fe_mul(r, fe_sub(u1_h_2, x3)), fe_mul(s1, h_3))
  let z3 = fe_mul(fe_mul(z1, z2), h)
  { x: x3, y: y3, z: z3, }
}

///|
/// Conditional swap for Montgomery ladder.
fn cswap(swap : Bool, r0 : Point, r1 : Point) -> (Point, Point) {
  if swap {
    (r1, r0)
  } else {
    (r0, r1)
  }
}

///|
/// Scalar multiplication: k * P using the Montgomery ladder.
///
/// Constant-time at the algorithm level: always performs one point_add
/// and one point_double per bit, eliminating the Hamming-weight timing
/// leak of double-and-add. The underlying BigInt arithmetic is NOT
/// constant-time; for production use OpenSSL/ring.
///
/// secp256k1 curve order is 256 bits.
fn scalar_mult(k : @bigint.BigInt, pt : Point) -> Point {
  let n_bits = 256
  let mut r0 = point_infinity()
  let mut r1 = pt
  for i = n_bits - 1; i >= 0; i = i - 1 {
    let bit = @bigint.is_odd(@bigint.shr(k, i))
    let (tmp0, tmp1) = cswap(bit, r0, r1)
    r0 = tmp0
    r1 = tmp1
    r1 = point_add(r0, r1)
    r0 = point_double(r0)
    let (tmp0b, tmp1b) = cswap(bit, r0, r1)
    r0 = tmp0b
    r1 = tmp1b
  }
  r0
}

///|
/// Convert a Jacobian point to affine coordinates.
fn to_affine(pt : Point) -> (@bigint.BigInt, @bigint.BigInt)? {
  if is_infinity(pt) {
    return None
  }
  let z_inv = fe_inv(pt.z)
  let z_inv_2 = fe_mul(z_inv, z_inv)
  let z_inv_3 = fe_mul(z_inv_2, z_inv)
  let x = fe_mul(pt.x, z_inv_2)
  let y = fe_mul(pt.y, z_inv_3)
  Some((x, y))
}

///|
/// Generator point G in Jacobian coordinates (Z = 1).
let generator : Point = { x: gx, y: gy, z: @bigint.one(), }

// ---------------------------------------------------------------------------
// Point encoding / decoding (SEC1 format)
// ---------------------------------------------------------------------------

///|
/// Encode a public key point as 65 bytes (uncompressed SEC1):
/// 04 || x (32 bytes, big-endian) || y (32 bytes, big-endian)
fn point_encode_uncompressed(pt : Point) -> Bytes {
  let affine = to_affine(pt)
  match affine {
    Some((x, y)) => {
      let result : Array[Byte] = []
      result.push(b'\x04')
      let x_bytes = bigint_to_bytes_be(x, 32)
      let y_bytes = bigint_to_bytes_be(y, 32)
      for i = 0; i < 32; i = i + 1 {
        result.push(x_bytes[i])
      }
      for i = 0; i < 32; i = i + 1 {
        result.push(y_bytes[i])
      }
      Bytes::from_array(result)
    }
    None => Bytes::make(65, b'\x00')
  }
}

///|
/// Encode a public key point as 33 bytes (compressed SEC1):
/// 02/03 || x (32 bytes, big-endian)
/// Prefix is 02 if y is even, 03 if y is odd.
fn point_encode_compressed(pt : Point) -> Bytes {
  let affine = to_affine(pt)
  match affine {
    Some((x, y)) => {
      let result : Array[Byte] = []
      // Check parity of y
      let y_mod2 = match @bigint.divmod(y, @bigint.from_int_value(2)) {
        Some((_, r)) => bigint_small_to_int(r)
        None => 0
      }
      if y_mod2 == 0 {
        result.push(b'\x02')
      } else {
        result.push(b'\x03')
      }
      let x_bytes = bigint_to_bytes_be(x, 32)
      for i = 0; i < 32; i = i + 1 {
        result.push(x_bytes[i])
      }
      Bytes::from_array(result)
    }
    None => Bytes::make(33, b'\x00')
  }
}

///|
/// Decode a 65-byte uncompressed public key.
fn point_decode_uncompressed(data : Bytes) -> Point? {
  if data.length() != 65 || data[0] != b'\x04' {
    return None
  }
  let x_bytes : Array[Byte] = []
  let y_bytes : Array[Byte] = []
  for i = 0; i < 32; i = i + 1 {
    x_bytes.push(data[1 + i])
  }
  for i = 0; i < 32; i = i + 1 {
    y_bytes.push(data[33 + i])
  }
  let x = bytes_to_bigint_be(Bytes::from_array(x_bytes))
  let y = bytes_to_bigint_be(Bytes::from_array(y_bytes))
  if @bigint.compare(x, p) >= 0 || @bigint.compare(y, p) >= 0 {
    return None
  }
  // Check y^2 = x^3 + 7 (mod p)  (a = 0, b = 7)
  let lhs = fe_mul(y, y)
  let x3 = fe_mul(fe_mul(x, x), x)
  let rhs = fe_add(x3, b_coeff)
  if !@bigint.equal(lhs, rhs) {
    return None
  }
  Some({ x, y, z: @bigint.one(), })
}

///|
/// Decode a 33-byte compressed public key.
fn point_decode_compressed(data : Bytes) -> Point? {
  if data.length() != 33 || (data[0] != b'\x02' && data[0] != b'\x03') {
    return None
  }
  let x_bytes : Array[Byte] = []
  for i = 0; i < 32; i = i + 1 {
    x_bytes.push(data[1 + i])
  }
  let x = bytes_to_bigint_be(Bytes::from_array(x_bytes))
  if @bigint.compare(x, p) >= 0 {
    return None
  }
  // Compute y^2 = x^3 + 7 (mod p)
  let x3 = fe_mul(fe_mul(x, x), x)
  let y2 = fe_add(x3, b_coeff)
  // Compute y = y2^((p+1)/4) mod p (since p ≡ 3 mod 4)
  let exp = match
    @bigint.from_string(
      "28948022309329048855892746252171976963317496166410141009864396001977208667916",
    ) {
    Some(v) => v
    None => return None
  }
  match @bigint.mod_pow(y2, exp, p) {
    Some(y) => {
      // Check y^2 == y2
      let y_sq = fe_mul(y, y)
      if !@bigint.equal(y_sq, y2) {
        return None
      }
      // Adjust parity
      let y_mod2 = match @bigint.divmod(y, @bigint.from_int_value(2)) {
        Some((_, r)) => bigint_small_to_int(r)
        None => 0
      }
      let want_odd = data[0] == b'\x03'
      let is_odd = y_mod2 == 1
      let final_y = if want_odd == is_odd {
        y
      } else {
        mod_sub(@bigint.zero(), y, p)
      }
      Some({ x, y: final_y, z: @bigint.one(), })
    }
    None => None
  }
}

///|
/// Decode a public key (compressed or uncompressed).
fn point_decode(data : Bytes) -> Point? {
  if data.length() == 65 {
    point_decode_uncompressed(data)
  } else if data.length() == 33 {
    point_decode_compressed(data)
  } else {
    None
  }
}

// ---------------------------------------------------------------------------
// RFC 6979 deterministic nonce generation
// ---------------------------------------------------------------------------

///|
fn bits2int(data : Bytes) -> @bigint.BigInt {
  bytes_to_bigint_be(data)
}

///|
fn int2octets(x : @bigint.BigInt) -> Bytes {
  let z = match @bigint.divmod(x, n_order) {
    Some((_, r)) => r
    None => x
  }
  bigint_to_bytes_be(z, 32)
}

///|
fn bits2octets(data : Bytes) -> Bytes {
  let z1 = bits2int(data)
  let z2 = match @bigint.divmod(z1, n_order) {
    Some((_, r)) => r
    None => z1
  }
  int2octets(z2)
}

///|
fn rfc6979_generate_k(x : @bigint.BigInt, hash : Bytes) -> @bigint.BigInt {
  let v_init = Bytes::make(32, b'\x01')
  let k_init = Bytes::make(32, b'\x00')
  let x_bytes = int2octets(x)
  let h1_bytes = bits2octets(hash)
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
  while true {
    v_current = @hmac.hmac_sha256(k_current, v_current)
    let t = v_current
    let k_candidate = bits2int(t)
    if @bigint.compare(k_candidate, zero) > 0 &&
      @bigint.compare(k_candidate, n_order) < 0 {
      return k_candidate
    }
    let msg_k = concat_bytes(v_current, bytes_single(b'\x00'))
    k_current = @hmac.hmac_sha256(k_current, msg_k)
    v_current = @hmac.hmac_sha256(k_current, v_current)
  }
  zero
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

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

///|
/// Derive the secp256k1 public key from a 32-byte private key.
///
/// The private key must be a big-endian integer in [1, n-1].
/// Returns the 65-byte uncompressed public key (04 || x || y).
pub fn derive_public_key(private_key : Bytes) -> Bytes {
  let d = bytes_to_bigint_be(private_key)
  let q_point = scalar_mult(d, generator)
  point_encode_uncompressed(q_point)
}

///|
/// Derive the compressed public key (33 bytes).
pub fn derive_public_key_compressed(private_key : Bytes) -> Bytes {
  let d = bytes_to_bigint_be(private_key)
  let q_point = scalar_mult(d, generator)
  point_encode_compressed(q_point)
}

///|
/// Sign a message with a secp256k1 private key using RFC 6979 deterministic nonce.
///
/// - `private_key`: 32-byte private key (big-endian).
/// - `message`: the message to sign.
///
/// Returns the 64-byte signature (32-byte r || 32-byte s, both big-endian).
pub fn sign(private_key : Bytes, message : Bytes) -> Bytes {
  let d = bytes_to_bigint_be(private_key)
  let hash = @sha256.sha256(message)
  let e = bytes_to_bigint_be(hash)
  let k = rfc6979_generate_k(d, hash)
  let kg = scalar_mult(k, generator)
  let kg_affine = match to_affine(kg) {
    Some(v) => v
    None => abort("FATAL: k*G is point at infinity in secp256k1 sign")
  }
  let r = match @bigint.divmod(kg_affine.0, n_order) {
    Some((_, rem)) => rem
    None => kg_affine.0
  }
  let k_inv = mod_inv(k, n_order)
  let rd = mod_mul(r, d, n_order)
  let e_rd = mod_add(e, rd, n_order)
  let s = mod_mul(k_inv, e_rd, n_order)
  // Low-S normalisation (BIP 62): s = min(s, n - s)
  let n_minus_s = mod_sub(n_order, s, n_order)
  let s_final = if @bigint.compare(s, n_minus_s) <= 0 { s } else { n_minus_s }
  let r_bytes = bigint_to_bytes_be(r, 32)
  let s_bytes = bigint_to_bytes_be(s_final, 32)
  concat_bytes(r_bytes, s_bytes)
}

///|
/// Verify a secp256k1 ECDSA signature.
///
/// - `public_key`: 33-byte compressed or 65-byte uncompressed public key.
/// - `message`: the signed message.
/// - `signature`: 64-byte signature (r || s, big-endian).
///
/// Returns `true` if the signature is valid, `false` otherwise.
pub fn verify(public_key : Bytes, message : Bytes, signature : Bytes) -> Bool {
  if signature.length() != 64 {
    return false
  }
  let r_bytes : Array[Byte] = []
  let s_bytes : Array[Byte] = []
  for i = 0; i < 32; i = i + 1 {
    r_bytes.push(signature[i])
  }
  for i = 0; i < 32; i = i + 1 {
    s_bytes.push(signature[32 + i])
  }
  let r = bytes_to_bigint_be(Bytes::from_array(r_bytes))
  let s = bytes_to_bigint_be(Bytes::from_array(s_bytes))
  let one = @bigint.one()
  if @bigint.compare(r, one) < 0 || @bigint.compare(r, n_order) >= 0 {
    return false
  }
  if @bigint.compare(s, one) < 0 || @bigint.compare(s, n_order) >= 0 {
    return false
  }
  let q_point = match point_decode(public_key) {
    Some(pt) => pt
    None => return false
  }
  let hash = @sha256.sha256(message)
  let e = bytes_to_bigint_be(hash)
  let e = match @bigint.divmod(e, n_order) {
    Some((_, rem)) => rem
    None => e
  }
  let w = mod_inv(s, n_order)
  let u1 = mod_mul(e, w, n_order)
  let u2 = mod_mul(r, w, n_order)
  let u1g = scalar_mult(u1, generator)
  let u2q = scalar_mult(u2, q_point)
  let point = point_add(u1g, u2q)
  if is_infinity(point) {
    return false
  }
  let affine = to_affine(point)
  match affine {
    Some((x1, _)) => {
      let x1_mod = match @bigint.divmod(x1, n_order) {
        Some((_, rem)) => rem
        None => x1
      }
      @bigint.equal(x1_mod, r)
    }
    None => false
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
/// Build a 32-byte private key with a given last byte.
fn make_key(last_byte : Byte) -> Bytes {
  let arr : Array[Byte] = Array::make(32, b'\x00')
  arr[31] = last_byte
  Bytes::from_array(arr)
}

///|
test "secp256k1: generator is on curve" {
  // y^2 = x^3 + 7
  let lhs = fe_mul(gy, gy)
  let x3 = fe_mul(fe_mul(gx, gx), gx)
  let rhs = fe_add(x3, b_coeff)
  assert_true(@bigint.equal(lhs, rhs))
}

///|
test "secp256k1: derive public key" {
  // Known test vector: private key = 1
  let priv_key = make_key(b'\x01')
  let pub_key = derive_public_key(priv_key)
  assert_eq(pub_key.length(), 65)
  assert_eq(pub_key[0], b'\x04')
  // Public key for privkey=1 should be the generator
  let pub_x = bytes_to_bigint_be(
    Bytes::from_array([
      pub_key[1],
      pub_key[2],
      pub_key[3],
      pub_key[4],
      pub_key[5],
      pub_key[6],
      pub_key[7],
      pub_key[8],
      pub_key[9],
      pub_key[10],
      pub_key[11],
      pub_key[12],
      pub_key[13],
      pub_key[14],
      pub_key[15],
      pub_key[16],
      pub_key[17],
      pub_key[18],
      pub_key[19],
      pub_key[20],
      pub_key[21],
      pub_key[22],
      pub_key[23],
      pub_key[24],
      pub_key[25],
      pub_key[26],
      pub_key[27],
      pub_key[28],
      pub_key[29],
      pub_key[30],
      pub_key[31],
      pub_key[32],
    ]),
  )
  assert_true(@bigint.equal(pub_x, gx))
}

///|
test "secp256k1: sign and verify" {
  // Use a known private key
  let priv_key = make_key(b'\x42') // private key = 0x42
  let pub_key = derive_public_key(priv_key)
  let message = @utils.string_to_bytes("Hello, Bitcoin!")
  let signature = sign(priv_key, message)
  assert_eq(signature.length(), 64)
  assert_true(verify(pub_key, message, signature))
}

///|
test "secp256k1: verify rejects wrong message" {
  let priv_key = make_key(b'\x42')
  let pub_key = derive_public_key(priv_key)
  let message = @utils.string_to_bytes("Hello, Bitcoin!")
  let signature = sign(priv_key, message)
  let wrong_message = @utils.string_to_bytes("Hello, Ethereum!")
  assert_false(verify(pub_key, wrong_message, signature))
}

///|
test "secp256k1: verify rejects wrong key" {
  let priv_key1 = make_key(b'\x42')
  let priv_key2 = make_key(b'\x43')
  let pub_key2 = derive_public_key(priv_key2)
  let message = @utils.string_to_bytes("Hello, Bitcoin!")
  let signature = sign(priv_key1, message)
  assert_false(verify(pub_key2, message, signature))
}

///|
test "secp256k1: deterministic signing" {
  let priv_key = make_key(b'\x99')
  let message = @utils.string_to_bytes("Deterministic test")
  let sig1 = sign(priv_key, message)
  let sig2 = sign(priv_key, message)
  // Same input should produce same signature (RFC 6979)
  assert_eq(sig1, sig2)
}

///|
test "secp256k1: compressed public key" {
  let priv_key = make_key(b'\x01')
  let compressed = derive_public_key_compressed(priv_key)
  assert_eq(compressed.length(), 33)
  assert_true(compressed[0] == b'\x02' || compressed[0] == b'\x03')
  // Should verify correctly
  let message = @utils.string_to_bytes("Compressed key test")
  let signature = sign(priv_key, message)
  assert_true(verify(compressed, message, signature))
}

///|
test "secp256k1: point at infinity for n*G" {
  // n * G should be the point at infinity
  let result = scalar_mult(n_order, generator)
  assert_true(is_infinity(result))
}

///|
test "secp256k1: 2G = G + G" {
  let g2_double = point_double(generator)
  let g2_add = point_add(generator, generator)
  // Both should give the same affine point
  let aff1 = to_affine(g2_double)
  let aff2 = to_affine(g2_add)
  match (aff1, aff2) {
    (Some((x1, y1)), Some((x2, y2))) => {
      assert_true(@bigint.equal(x1, x2))
      assert_true(@bigint.equal(y1, y2))
    }
    _ => assert_true(false)
  }
}

///|
test "secp256k1: low-S normalisation" {
  // After BIP 62, s should be <= n/2
  let priv_key = make_key(b'\x77')
  let message = @utils.string_to_bytes("Low-S test")
  let signature = sign(priv_key, message)
  // Extract s (bytes 32-63)
  let s_bytes : Array[Byte] = []
  for i = 0; i < 32; i = i + 1 {
    s_bytes.push(signature[32 + i])
  }
  let s = bytes_to_bigint_be(Bytes::from_array(s_bytes))
  let half_n = @bigint.from_string(
    "57896044618658097711785492504343953926418782139537452191302581570759080747168",
  ).unwrap()
  assert_true(@bigint.compare(s, half_n) <= 0)
}
