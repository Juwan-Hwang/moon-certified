/// ECDSA: Elliptic Curve Digital Signature Algorithm (FIPS 186-4).
///
/// This module implements ECDSA over the NIST P-256 curve (secp256r1 /
/// prime256v1) with **RFC 6979 deterministic nonce generation**.
/// Deterministic signing eliminates the catastrophic security failure
/// of nonce reuse or weak RNG, making this implementation safe for
/// production use without a cryptographic random number generator.
///
/// ## Curve parameters (P-256)
///
/// - Prime: p = 2^256 - 2^224 + 2^192 + 2^96 - 1
/// - a = -3 mod p
/// - b = 0x5AC635D8AA3A93E7B3EBBD55769886BC651D06B0CC53B0F63BCE3C3E27D2604B
/// - Generator G: standard P-256 base point
/// - Order n = 0xFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551
///
/// ## Algorithm
///
/// ### Key generation
/// 1. Private key d: random integer in [1, n-1] (32 bytes big-endian).
/// 2. Public key Q = d * G (65 bytes uncompressed: 04 || Qx || Qy).
///
/// ### Signing (RFC 6979 deterministic)
/// 1. e = SHA-256(message), interpreted as big-endian integer.
/// 2. k = RFC 6979 deterministic nonce from HMAC-SHA256(d, e).
/// 3. (x1, y1) = k * G; r = x1 mod n.
/// 4. s = k^(-1) * (e + r * d) mod n.
/// 5. Signature = r || s (64 bytes, big-endian).
///
/// ### Verification
/// 1. Check r, s ∈ [1, n-1].
/// 2. e = SHA-256(message).
/// 3. w = s^(-1) mod n.
/// 4. u1 = e * w mod n; u2 = r * w mod n.
/// 5. (x1, y1) = u1 * G + u2 * Q.
/// 6. Valid iff x1 mod n == r.
///
/// ## References
///
/// - FIPS 186-4: Digital Signature Standard
/// - RFC 6979: Deterministic Usage of DSA and ECDSA
/// - SEC 1: Elliptic Curve Cryptography (SEC 1 v2)
///
/// `proof-enabled` is `false`; correctness is backed by RFC 6979 test vectors.

// ---------------------------------------------------------------------------
// Curve parameters: NIST P-256 (secp256r1)
// ---------------------------------------------------------------------------

/// Prime p = 2^256 - 2^224 + 2^192 + 2^96 - 1
let p : @bigint.BigInt = @bigint.from_string(
  "115792089210356248762697446949407573530086143415290314195533631308867097853951",
).unwrap()

/// Curve order n
let n_order : @bigint.BigInt = @bigint.from_string(
  "115792089210356248762697446949407573529996955224135760342422259061068512044369",
).unwrap()

/// Curve coefficient a = -3 mod p
let a_coeff : @bigint.BigInt = @bigint.from_string(
  "115792089210356248762697446949407573530086143415290314195533631308867097853948",
).unwrap()

/// Curve coefficient b
let b_coeff : @bigint.BigInt = @bigint.from_string(
  "41058363725152142129326129780047268409114441015993725554835256314039467401291",
).unwrap()

/// Generator x-coordinate
let gx : @bigint.BigInt = @bigint.from_string(
  "48439561293906451759052585252797914202762949526041747995844080717082404635286",
).unwrap()

/// Generator y-coordinate
let gy : @bigint.BigInt = @bigint.from_string(
  "36134250956749795798585127919587881956611106672985015071877198253568414405109",
).unwrap()

// ---------------------------------------------------------------------------
// Modular arithmetic helpers
// ---------------------------------------------------------------------------

/// (a + b) mod m
fn mod_add(a : @bigint.BigInt, b : @bigint.BigInt, m : @bigint.BigInt) -> @bigint.BigInt {
  let sum = @bigint.add(a, b)
  match @bigint.divmod(sum, m) {
    Some((_, r)) => r
    None => sum
  }
}

/// (a - b) mod m (result always non-negative)
fn mod_sub(a : @bigint.BigInt, b : @bigint.BigInt, m : @bigint.BigInt) -> @bigint.BigInt {
  let diff = @bigint.sub(a, b)
  if @bigint.compare(diff, @bigint.zero()) < 0 {
    @bigint.add(diff, m)
  } else {
    diff
  }
}

/// (a * b) mod m
fn mod_mul(a : @bigint.BigInt, b : @bigint.BigInt, m : @bigint.BigInt) -> @bigint.BigInt {
  match @bigint.divmod(@bigint.mul(a, b), m) {
    Some((_, r)) => r
    None => @bigint.zero()
  }
}

/// a^(-1) mod m using Fermat's little theorem (for prime m)
fn mod_inv(a : @bigint.BigInt, m : @bigint.BigInt) -> @bigint.BigInt {
  let exp = @bigint.sub(m, @bigint.from_int_value(2))
  match @bigint.mod_pow(a, exp, m) {
    Some(r) => r
    None => @bigint.zero()
  }
}

/// (a * b) mod p (field multiplication)
fn fe_mul(a : @bigint.BigInt, b : @bigint.BigInt) -> @bigint.BigInt {
  mod_mul(a, b, p)
}

/// (a + b) mod p (field addition)
fn fe_add(a : @bigint.BigInt, b : @bigint.BigInt) -> @bigint.BigInt {
  mod_add(a, b, p)
}

/// (a - b) mod p (field subtraction)
fn fe_sub(a : @bigint.BigInt, b : @bigint.BigInt) -> @bigint.BigInt {
  mod_sub(a, b, p)
}

/// a^(-1) mod p (field inversion)
fn fe_inv(a : @bigint.BigInt) -> @bigint.BigInt {
  mod_inv(a, p)
}

// ---------------------------------------------------------------------------
// BigInt <-> bytes (big-endian) conversion
// ---------------------------------------------------------------------------

/// Convert BigInt to big-endian byte array of fixed length.
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

/// Convert big-endian byte array (as Bytes) to BigInt.
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

/// Convert a BigInt known to be in [0, 255] to an Int.
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

/// Jacobian projective coordinates (X, Y, Z) with x = X/Z^2, y = Y/Z^3.
/// The point at infinity is represented as Z = 0.
priv struct Point {
  x : @bigint.BigInt
  y : @bigint.BigInt
  z : @bigint.BigInt
}

/// Point at infinity (Z = 0).
fn point_infinity() -> Point {
  { x: @bigint.one(), y: @bigint.one(), z: @bigint.zero() }
}

/// Check if a point is the point at infinity.
fn is_infinity(pt : Point) -> Bool {
  @bigint.equal(pt.z, @bigint.zero())
}

/// Point doubling in Jacobian coordinates (optimized for a = -3).
/// Uses the formula:
///   if Y == 0: return infinity
///   S = 4 * X * Y^2
///   M = 3 * (X - Z^2) * (X + Z^2)    (since a = -3)
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
  // Check Y == 0
  if @bigint.equal(y, @bigint.zero()) {
    return point_infinity()
  }
  let z2 = fe_mul(z, z)
  let y2 = fe_mul(y, y)
  let s = fe_mul(fe_mul(@bigint.from_int_value(4), x), y2)
  // M = 3 * (X - Z^2) * (X + Z^2)  for a = -3
  let m = fe_mul(
    fe_mul(@bigint.from_int_value(3), fe_sub(x, z2)),
    fe_add(x, z2),
  )
  let x3 = fe_sub(fe_mul(m, m), fe_mul(@bigint.from_int_value(2), s))
  let y4 = fe_mul(y2, y2)
  let y3 = fe_sub(fe_mul(m, fe_sub(s, x3)), fe_mul(@bigint.from_int_value(8), y4))
  let z3 = fe_mul(fe_mul(@bigint.from_int_value(2), y), z)
  { x: x3, y: y3, z: z3 }
}

/// Point addition in Jacobian coordinates.
/// Handles all cases including doubling and infinity.
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
  // If H == 0
  if @bigint.equal(h, @bigint.zero()) {
    if @bigint.equal(r, @bigint.zero()) {
      // P1 == P2: double
      return point_double(p1)
    } else {
      // P1 == -P2: infinity
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
  let y3 = fe_sub(
    fe_mul(r, fe_sub(u1_h_2, x3)),
    fe_mul(s1, h_3),
  )
  let z3 = fe_mul(fe_mul(z1, z2), h)
  { x: x3, y: y3, z: z3 }
}

/// Scalar multiplication: k * P using double-and-add.
fn scalar_mult(k : @bigint.BigInt, pt : Point) -> Point {
  let mut result = point_infinity()
  let mut current = pt
  let mut scalar = k
  let zero = @bigint.zero()
  while @bigint.greater_than(scalar, zero) {
    if @bigint.is_odd(scalar) {
      result = point_add(result, current)
    }
    current = point_double(current)
    scalar = @bigint.shr(scalar, 1)
  }
  result
}

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

/// Generator point G in Jacobian coordinates (Z = 1).
let generator : Point = { x: gx, y: gy, z: @bigint.one() }

// ---------------------------------------------------------------------------
// Point encoding / decoding (uncompressed SEC1 format)
// ---------------------------------------------------------------------------

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

/// Decode a 65-byte uncompressed public key.
/// Returns the point, or None if invalid.
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
  // Check x, y < p
  if @bigint.compare(x, p) >= 0 || @bigint.compare(y, p) >= 0 {
    return None
  }
  // Check point is on curve: y^2 = x^3 + a*x + b (mod p)
  let lhs = fe_mul(y, y)
  let x3 = fe_mul(fe_mul(x, x), x)
  let ax = fe_mul(a_coeff, x)
  let rhs = fe_add(fe_add(x3, ax), b_coeff)
  if !@bigint.equal(lhs, rhs) {
    return None
  }
  Some({ x, y, z: @bigint.one() })
}

// ---------------------------------------------------------------------------
// RFC 6979 deterministic nonce generation
// ---------------------------------------------------------------------------

/// bits2int: convert a byte string to an integer.
/// For P-256 with SHA-256, the bit length of q is 256, and the hash
/// output is also 256 bits, so this is just big-endian interpretation.
fn bits2int(data : Bytes) -> @bigint.BigInt {
  bytes_to_bigint_be(data)
}

/// int2octets: convert an integer to a 32-byte big-endian octet string.
/// Per RFC 6979, x is first reduced mod q.
fn int2octets(x : @bigint.BigInt) -> Bytes {
  let z = match @bigint.divmod(x, n_order) {
    Some((_, r)) => r
    None => x
  }
  bigint_to_bytes_be(z, 32)
}

/// bits2octets: convert a byte string to a 32-byte octet string.
/// z1 = bits2int(data); z2 = z1 mod q; return int2octets(z2)
fn bits2octets(data : Bytes) -> Bytes {
  let z1 = bits2int(data)
  let z2 = match @bigint.divmod(z1, n_order) {
    Some((_, r)) => r
    None => z1
  }
  int2octets(z2)
}

/// Generate a deterministic nonce k per RFC 6979 using HMAC-SHA256.
///
/// Inputs:
/// - x: private key as BigInt
/// - hash: message hash (32 bytes from SHA-256)
///
/// Returns k in [1, n-1].
fn rfc6979_generate_k(x : @bigint.BigInt, hash : Bytes) -> @bigint.BigInt {
  // Step a: h1 = hash (already done by caller)
  // Step b: V = 0x01 0x01 ... 0x01 (32 bytes)
  let v_init = Bytes::make(32, b'\x01')
  // Step c: K = 0x00 0x00 ... 0x00 (32 bytes)
  let k_init = Bytes::make(32, b'\x00')
  // Process private key and hash as octet strings
  let x_bytes = int2octets(x)
  let h1_bytes = bits2octets(hash)

  // Step d: K = HMAC_K(V || 0x00 || x_bytes || h1_bytes)
  let msg_d = concat_bytes(concat_bytes(concat_bytes(v_init, bytes_single(b'\x00')), x_bytes), h1_bytes)
  let k1 = @hmac.hmac_sha256(k_init, msg_d)
  // Step e: V = HMAC_K(V)
  let v1 = @hmac.hmac_sha256(k1, v_init)
  // Step f: K = HMAC_K(V || 0x01 || x_bytes || h1_bytes)
  let msg_f = concat_bytes(concat_bytes(concat_bytes(v1, bytes_single(b'\x01')), x_bytes), h1_bytes)
  let k2 = @hmac.hmac_sha256(k1, msg_f)
  // Step g: V = HMAC_K(V)
  let v2 = @hmac.hmac_sha256(k2, v1)

  // Step h: loop to generate k
  let mut k_current = k2
  let mut v_current = v2
  let zero = @bigint.zero()
  while true {
    // T = empty; while tlen < qlen: V = HMAC_K(V); T = T || V
    // For P-256 (qlen = 256 bits = 32 bytes), one HMAC output suffices.
    v_current = @hmac.hmac_sha256(k_current, v_current)
    let t = v_current
    let k_candidate = bits2int(t)
    // Check 1 <= k < n
    if @bigint.compare(k_candidate, zero) > 0 && @bigint.compare(
      k_candidate,
      n_order,
    ) < 0 {
      return k_candidate
    }
    // K = HMAC_K(V || 0x00)
    let msg_k = concat_bytes(v_current, bytes_single(b'\x00'))
    k_current = @hmac.hmac_sha256(k_current, msg_k)
    // V = HMAC_K(V)
    v_current = @hmac.hmac_sha256(k_current, v_current)
  }
  // Unreachable, but needed for type checker
  zero
}

/// Concatenate two Bytes.
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

/// Create a single-byte Bytes.
fn bytes_single(b : Byte) -> Bytes {
  Bytes::from_array([b])
}

// ---------------------------------------------------------------------------
// Public API: key generation, signing, verification
// ---------------------------------------------------------------------------

///|
/// Derive the ECDSA public key from a 32-byte private key.
///
/// The private key must be a big-endian integer in [1, n-1].
/// Returns the 65-byte uncompressed public key (04 || x || y).
pub fn derive_public_key(private_key : Bytes) -> Bytes {
  let d = bytes_to_bigint_be(private_key)
  let q_point = scalar_mult(d, generator)
  point_encode_uncompressed(q_point)
}

///|
/// Sign a message with an ECDSA private key using RFC 6979 deterministic nonce.
///
/// - `private_key`: 32-byte private key (big-endian).
/// - `message`: the message to sign.
///
/// Returns the 64-byte signature (32-byte r || 32-byte s, both big-endian).
pub fn sign(private_key : Bytes, message : Bytes) -> Bytes {
  let d = bytes_to_bigint_be(private_key)
  // Compute e = SHA-256(message)
  let hash = @sha256.sha256(message)
  let e = bytes_to_bigint_be(hash)
  // Generate deterministic nonce k
  let k = rfc6979_generate_k(d, hash)
  // Compute r = (k * G).x mod n
  let kg = scalar_mult(k, generator)
  let kg_affine = to_affine(kg).unwrap()
  let r = match @bigint.divmod(kg_affine.0, n_order) {
    Some((_, rem)) => rem
    None => kg_affine.0
  }
  // Compute s = k^(-1) * (e + r * d) mod n
  let k_inv = mod_inv(k, n_order)
  let rd = mod_mul(r, d, n_order)
  let e_rd = mod_add(e, rd, n_order)
  let s = mod_mul(k_inv, e_rd, n_order)
  // Encode signature as r || s (64 bytes, big-endian)
  let r_bytes = bigint_to_bytes_be(r, 32)
  let s_bytes = bigint_to_bytes_be(s, 32)
  concat_bytes(r_bytes, s_bytes)
}

///|
/// Verify an ECDSA signature.
///
/// - `public_key`: 65-byte uncompressed public key.
/// - `message`: the signed message.
/// - `signature`: 64-byte signature (r || s, big-endian).
///
/// Returns `true` if the signature is valid, `false` otherwise.
pub fn verify(public_key : Bytes, message : Bytes, signature : Bytes) -> Bool {
  // Check sizes
  if public_key.length() != 65 || signature.length() != 64 {
    return false
  }
  // Parse r, s
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
  // Check r, s in [1, n-1]
  let one = @bigint.one()
  if @bigint.compare(r, one) < 0 || @bigint.compare(r, n_order) >= 0 {
    return false
  }
  if @bigint.compare(s, one) < 0 || @bigint.compare(s, n_order) >= 0 {
    return false
  }
  // Parse public key Q
  let q_point = match point_decode_uncompressed(public_key) {
    Some(pt) => pt
    None => return false
  }
  // Compute e = SHA-256(message)
  let hash = @sha256.sha256(message)
  let e = bytes_to_bigint_be(hash)
  // Reduce e mod n if needed
  let e = match @bigint.divmod(e, n_order) {
    Some((_, rem)) => rem
    None => e
  }
  // w = s^(-1) mod n
  let w = mod_inv(s, n_order)
  // u1 = e * w mod n; u2 = r * w mod n
  let u1 = mod_mul(e, w, n_order)
  let u2 = mod_mul(r, w, n_order)
  // (x1, y1) = u1 * G + u2 * Q
  let u1g = scalar_mult(u1, generator)
  let u2q = scalar_mult(u2, q_point)
  let point = point_add(u1g, u2q)
  // Check point is not infinity
  if is_infinity(point) {
    return false
  }
  // Check x1 mod n == r
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
