/// Ed25519: Edwards-curve Digital Signature Algorithm (RFC 8032).
///
/// This module implements Ed25519 signing and verification as specified in
/// [RFC 8032](https://tools.ietf.org/html/rfc8032). Ed25519 is an EdDSA
/// signature scheme using SHA-512 and Curve25519's twisted Edwards form.
///
/// ## Features
///
/// - **Deterministic signing**: signatures are deterministic (no random nonce),
///   eliminating side-channel vulnerabilities from weak RNGs.
/// - **Fast verification**: single scalar multiplication + double-scalar
///   verification equation.
/// - **Small signatures**: 64 bytes (32-byte R || 32-byte S).
/// - **Small keys**: 32-byte private key, 32-byte public key.
///
/// ## Algorithm
///
/// ### Key generation
/// 1. Private key: 32 random bytes.
/// 2. Hash with SHA-512 -> 64-byte `h`.
/// 3. Clamp `h[0:32]`: clear bits 0-2 of h[0], clear bit 255 of h[31],
///    set bit 254 of h[31]. This gives scalar `s`.
/// 4. Public key `A = s * B` where B is the base point.
///
/// ### Signing (RFC 8032 §5.1.6)
/// 1. Hash private key -> `h`.
/// 2. `r = SHA-512(h[32:64] || message) mod L`
/// 3. `R = r * B`
/// 4. `k = SHA-512(R || A || message) mod L`
/// 5. `S = (r + k * s) mod L`
/// 6. Signature = `encode(R) || encode(S)`
///
/// ### Verification (RFC 8032 §5.1.7)
/// 1. Parse `R` and `S` from signature, `A` from public key.
/// 2. Check `S < L`.
/// 3. `k = SHA-512(R || A || message) mod L`
/// 4. Check `S * B == R + k * A`
///
/// ## Curve parameters
///
/// - Prime: p = 2^255 - 19
/// - Curve: -x^2 + y^2 = 1 + d*x^2*y^2 (twisted Edwards form)
/// - d = -121665/121666 mod p
/// - Base point B: y = 4/5, x recovered from curve equation
/// - Order L = 2^252 + 27742317777372353535851937790883648493
///
/// ## References
///
/// - RFC 8032: Edwards-Curve Digital Signature Algorithm (EdDSA)
/// - Bernstein, Duif, Lange, Schwabe, Yang (2012): "High-speed high-security
///   signatures"
/// - https://ed25519.cr.yp.to/
///
/// `proof-enabled` is `false`; correctness is backed by RFC 8032 test vectors.

// ---------------------------------------------------------------------------
// Field parameters: GF(2^255 - 19)
// ---------------------------------------------------------------------------

/// Prime p = 2^255 - 19
let p : @bigint.BigInt = @bigint.from_string(
  "57896044618658097711785492504343953926634992332820282019728792003956564819949",
).unwrap()

/// Curve order L = 2^252 + 27742317777372353535851937790883648493
let l_order : @bigint.BigInt = @bigint.from_string(
  "7237005577332262213973186563042994240857116359379907606001950938285454250989",
).unwrap()

/// d = -121665 * inv(121666) mod p
let d_param : @bigint.BigInt = @bigint.from_string(
  "37095705934669439343138083508754565189542113879843219016388785533085940283555",
).unwrap()

/// I = sqrt(-1) mod p = 2^((p-1)/4) mod p
let i_sqrt : @bigint.BigInt = @bigint.from_string(
  "19681161376707505956807079304988542015446066515923890162744021073123829784752",
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

/// a^(-1) mod p using Fermat's little theorem: a^(p-2) mod p
fn fe_inv(a : @bigint.BigInt) -> @bigint.BigInt {
  let exp = @bigint.sub(p, @bigint.from_int_value(2))
  match @bigint.mod_pow(a, exp, p) {
    Some(r) => r
    None => @bigint.zero()
  }
}

// ---------------------------------------------------------------------------
// Point representation (extended twisted Edwards coordinates)
// ---------------------------------------------------------------------------

/// Extended twisted Edwards coordinates (X, Y, Z, T) with x = X/Z, y = Y/Z, T = X*Y/Z.
priv struct Point {
  x : @bigint.BigInt
  y : @bigint.BigInt
  z : @bigint.BigInt
  t : @bigint.BigInt // T = X*Y/Z
}

/// Identity point (0, 1, 1, 0)
fn identity() -> Point {
  { x: @bigint.zero(), y: @bigint.one(), z: @bigint.one(), t: @bigint.zero() }
}

/// Point addition in extended coordinates (RFC 8032 §5.1.4 variant).
/// Uses the formula from the ed25519 reference implementation:
/// A = (Y1-X1)*(Y2-X2)
/// B = (Y1+X1)*(Y2+X2)
/// C = T1*2*d*T2
/// D = Z1*2*Z2
/// E = B-A
/// F = D-C
/// G = D+C
/// H = B+A
/// X3 = E*F, Y3 = G*H, T3 = E*H, Z3 = F*G
fn point_add(p1 : Point, p2 : Point) -> Point {
  let x1 = p1.x
  let y1 = p1.y
  let z1 = p1.z
  let t1 = p1.t
  let x2 = p2.x
  let y2 = p2.y
  let z2 = p2.z
  let t2 = p2.t

  let a = fe_mul(fe_sub(y1, x1), fe_sub(y2, x2))
  let b = fe_mul(fe_add(y1, x1), fe_add(y2, x2))
  let c = fe_mul(fe_mul(t1, t2), fe_mul(@bigint.from_int_value(2), d_param))
  let dd = fe_mul(fe_mul(z1, z2), @bigint.from_int_value(2))
  let e = fe_sub(b, a)
  let f = fe_sub(dd, c)
  let g = fe_add(dd, c)
  let h = fe_add(b, a)

  { x: fe_mul(e, f), y: fe_mul(g, h), z: fe_mul(f, g), t: fe_mul(e, h) }
}

/// Scalar multiplication: k * P using double-and-add.
fn scalar_mult(k : @bigint.BigInt, pt : Point) -> Point {
  let mut result = identity()
  let mut current = pt
  let mut scalar = k
  let zero = @bigint.zero()
  while @bigint.greater_than(scalar, zero) {
    if @bigint.is_odd(scalar) {
      result = point_add(result, current)
    }
    current = point_add(current, current)
    scalar = @bigint.shr(scalar, 1)
  }
  result
}

// ---------------------------------------------------------------------------
// Encoding / decoding
// ---------------------------------------------------------------------------

/// Encode a point as 32 bytes (little-endian y-coordinate with sign bit of x).
fn point_encode(pt : Point) -> Bytes {
  // Recover affine x = X/Z, y = Y/Z
  let z_inv = fe_inv(pt.z)
  let x = fe_mul(pt.x, z_inv)
  let y = fe_mul(pt.y, z_inv)
  // Encode y as 32 bytes little-endian
  let y_bytes = bigint_to_bytes_le(y, 32)
  // Set the high bit of the last byte to the sign of x (bit 0 of x)
  let result : Array[Byte] = []
  for i = 0; i < 32; i = i + 1 {
    if i == 31 && @bigint.is_odd(x) {
      result.push((y_bytes[i].to_int() | 0x80).to_byte())
    } else {
      result.push(y_bytes[i])
    }
  }
  Bytes::from_array(result)
}

/// Decode a 32-byte point encoding.
/// Returns the point, or None if the encoding is invalid.
fn point_decode(data : Bytes) -> Point? {
  if data.length() != 32 {
    return None
  }
  // The sign bit is the high bit of the last byte
  let sign = (data[31].to_int() & 0x80) >> 7
  // Clear the sign bit to get y
  let y_bytes : Array[Byte] = []
  for i = 0; i < 32; i = i + 1 {
    if i == 31 {
      y_bytes.push((data[i].to_int() & 0x7f).to_byte())
    } else {
      y_bytes.push(data[i])
    }
  }
  let y = bytes_to_bigint_le(y_bytes)
  // Check y < p
  if @bigint.compare(y, p) >= 0 {
    return None
  }
  // Recover x from curve equation: -x^2 + y^2 = 1 + d*x^2*y^2
  // => x^2 * (-1 - d*y^2) = 1 - y^2
  // => x^2 = (y^2 - 1) / (d*y^2 + 1)  ... wait, for a = -1:
  // -x^2 + y^2 = 1 + d*x^2*y^2
  // => y^2 - 1 = x^2 + d*x^2*y^2 = x^2 * (1 + d*y^2)
  // => x^2 = (y^2 - 1) / (1 + d*y^2)
  let y2 = fe_mul(y, y)
  let u = fe_sub(y2, @bigint.one()) // y^2 - 1
  let v = fe_add(@bigint.one(), fe_mul(d_param, y2)) // 1 + d*y^2
  // x = sqrt(u / v) = sqrt(u * v^(-1))
  // For p = 5 (mod 8), sqrt(u/v) = u * v^3 * (u * v^7)^((p-5)/8)
  let v2 = fe_mul(v, v)
  let v3 = fe_mul(v2, v)
  let v7 = fe_mul(fe_mul(v3, v3), v) // v^3 * v^3 * v = v^7
  let uv7 = fe_mul(u, v7)
  let exp = @bigint.div(
    @bigint.sub(p, @bigint.from_int_value(5)),
    @bigint.from_int_value(8),
  ).unwrap()
  let pow_result = match @bigint.mod_pow(uv7, exp, p) {
    Some(r) => r
    None => return None
  }
  let x_candidate = fe_mul(fe_mul(u, v3), pow_result)
  // Check: x^2 == u/v ?
  let x2 = fe_mul(x_candidate, x_candidate)
  let v_inv = fe_inv(v)
  let check = fe_mul(u, v_inv)
  let mut x = x_candidate
  if !@bigint.equal(x2, check) {
    if @bigint.equal(x2, fe_sub(@bigint.zero(), check)) {
      // x^2 == -(u/v), so x = x * sqrt(-1) gives the correct root
      x = fe_mul(x_candidate, i_sqrt)
    } else {
      return None // No square root exists
    }
  }
  // Adjust sign
  if @bigint.is_odd(x) != (sign == 1) {
    x = fe_sub(@bigint.zero(), x)
    x = match @bigint.divmod(x, p) {
      Some((_, r)) => r
      None => x
    }
    if @bigint.compare(x, @bigint.zero()) < 0 {
      x = @bigint.add(x, p)
    }
  }
  // Build point in extended coordinates (x, y, 1, x*y)
  Some({ x, y, z: @bigint.one(), t: fe_mul(x, y) })
}

// ---------------------------------------------------------------------------
// BigInt <-> bytes (little-endian) conversion
// ---------------------------------------------------------------------------

/// Convert BigInt to little-endian byte array of fixed length.
fn bigint_to_bytes_le(n : @bigint.BigInt, len : Int) -> Bytes {
  let result : Array[Byte] = Array::make(len, b'\x00')
  let mut temp = n
  let zero = @bigint.zero()
  let divisor = @bigint.from_int_value(256)
  let mut idx = 0
  while idx < len && @bigint.greater_than(temp, zero) {
    let (q, r) = match @bigint.divmod(temp, divisor) {
      Some(pair) => pair
      None => (@bigint.zero(), @bigint.zero())
    }
    result[idx] = bigint_small_to_int(r).to_byte()
    temp = q
    idx = idx + 1
  }
  Bytes::from_array(result)
}

/// Convert little-endian byte array to BigInt.
fn bytes_to_bigint_le(data : Array[Byte]) -> @bigint.BigInt {
  let mut result = @bigint.zero()
  let base = @bigint.from_int_value(256)
  for i = data.length() - 1; i >= 0; i = i - 1 {
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
// Base point
// ---------------------------------------------------------------------------

/// Compute the base point B for Ed25519.
/// By = 4/5 mod p, Bx recovered from curve equation.
fn compute_base_point() -> Point {
  // By = 4 * inv(5) mod p
  let by = fe_mul(@bigint.from_int_value(4), fe_inv(@bigint.from_int_value(5)))
  // Recover Bx from curve equation
  let by2 = fe_mul(by, by)
  let u = fe_sub(by2, @bigint.one())
  let v = fe_add(@bigint.one(), fe_mul(d_param, by2))
  let v2 = fe_mul(v, v)
  let v3 = fe_mul(v2, v)
  let v7 = fe_mul(fe_mul(v3, v3), v) // v^3 * v^3 * v = v^7
  let uv7 = fe_mul(u, v7)
  let exp = @bigint.div(
    @bigint.sub(p, @bigint.from_int_value(5)),
    @bigint.from_int_value(8),
  ).unwrap()
  let pow_result = match @bigint.mod_pow(uv7, exp, p) {
    Some(r) => r
    None => @bigint.zero()
  }
  let mut bx = fe_mul(fe_mul(u, v3), pow_result)
  let x2 = fe_mul(bx, bx)
  let v_inv = fe_inv(v)
  let check = fe_mul(u, v_inv)
  if !@bigint.equal(x2, check) {
    if @bigint.equal(x2, fe_sub(@bigint.zero(), check)) {
      bx = fe_mul(bx, i_sqrt)
    }
  }
  // Ensure positive (even) x
  if @bigint.is_odd(bx) {
    bx = fe_sub(p, bx)
  }
  { x: bx, y: by, z: @bigint.one(), t: fe_mul(bx, by) }
}

/// Cached base point B (computed once at module init).
let base_point : Point = compute_base_point()

// ---------------------------------------------------------------------------
// Public API: key generation, signing, verification
// ---------------------------------------------------------------------------

///|
/// Derive the Ed25519 public key from a 32-byte private key.
///
/// Returns the 32-byte public key.
pub fn derive_public_key(private_key : Bytes) -> Bytes {
  // Hash the private key with SHA-512
  let h = @sha512.sha512(private_key)
  // Clamp the lower 32 bytes to get scalar s
  let s = decode_scalar(h, 0)
  // Compute A = s * B
  let a_point = scalar_mult(s, base_point)
  // Encode A
  point_encode(a_point)
}

///|
/// Sign a message with an Ed25519 private key.
///
/// - `private_key`: 32-byte private key.
/// - `message`: the message to sign.
///
/// Returns the 64-byte signature (R || S).
pub fn sign(private_key : Bytes, message : Bytes) -> Bytes {
  // Step 1: Hash the private key
  let h = @sha512.sha512(private_key)
  // Step 2: Extract scalar s from h[0:32] (clamped)
  let s = decode_scalar(h, 0)
  // Step 3: Compute prefix = h[32:64]
  let prefix : Array[Byte] = []
  for i = 32; i < 64; i = i + 1 {
    prefix.push(h[i])
  }
  // Step 4: Compute public key A = s * B
  let a_point = scalar_mult(s, base_point)
  let a_bytes = point_encode(a_point)
  // Step 5: r = SHA-512(prefix || message) mod L
  let r_input : Array[Byte] = []
  for b in prefix {
    r_input.push(b)
  }
  for i = 0; i < message.length(); i = i + 1 {
    r_input.push(message[i])
  }
  let r_hash = @sha512.sha512(Bytes::from_array(r_input))
  let r = bytes_to_bigint_le(bytes_to_array(r_hash))
  // Reduce r mod L
  let r = match @bigint.divmod(r, l_order) {
    Some((_, rem)) => rem
    None => r
  }
  // Step 6: R = r * B
  let r_point = scalar_mult(r, base_point)
  let r_bytes = point_encode(r_point)
  // Step 7: k = SHA-512(R || A || message) mod L
  let k_input : Array[Byte] = []
  for i = 0; i < 32; i = i + 1 {
    k_input.push(r_bytes[i])
  }
  for i = 0; i < 32; i = i + 1 {
    k_input.push(a_bytes[i])
  }
  for i = 0; i < message.length(); i = i + 1 {
    k_input.push(message[i])
  }
  let k_hash = @sha512.sha512(Bytes::from_array(k_input))
  let k = bytes_to_bigint_le(bytes_to_array(k_hash))
  // Reduce k mod L
  let k = match @bigint.divmod(k, l_order) {
    Some((_, rem)) => rem
    None => k
  }
  // Step 8: S = (r + k * s) mod L
  let s_val = mod_mul(k, s, l_order)
  let s_final = mod_add(r, s_val, l_order)
  // Step 9: Signature = R || S
  let sig : Array[Byte] = []
  for i = 0; i < 32; i = i + 1 {
    sig.push(r_bytes[i])
  }
  let s_bytes = bigint_to_bytes_le(s_final, 32)
  for i = 0; i < 32; i = i + 1 {
    sig.push(s_bytes[i])
  }
  Bytes::from_array(sig)
}

///|
/// Verify an Ed25519 signature.
///
/// - `public_key`: 32-byte public key.
/// - `message`: the signed message.
/// - `signature`: 64-byte signature.
///
/// Returns `true` if the signature is valid, `false` otherwise.
pub fn verify(public_key : Bytes, message : Bytes, signature : Bytes) -> Bool {
  // Check sizes
  if public_key.length() != 32 || signature.length() != 64 {
    return false
  }
  // Parse R from signature[0:32]
  let r_point = match point_decode(Bytes::from_array(slice(signature, 0, 32))) {
    Some(pt) => pt
    None => return false
  }
  // Parse S from signature[32:64]
  let s = bytes_to_bigint_le(slice(signature, 32, 32))
  // Check S < L
  if @bigint.compare(s, l_order) >= 0 {
    return false
  }
  // Parse A from public key
  let a_point = match point_decode(public_key) {
    Some(pt) => pt
    None => return false
  }
  // Compute k = SHA-512(R || A || message) mod L
  let k_input : Array[Byte] = []
  for i = 0; i < 32; i = i + 1 {
    k_input.push(signature[i])
  }
  for i = 0; i < 32; i = i + 1 {
    k_input.push(public_key[i])
  }
  for i = 0; i < message.length(); i = i + 1 {
    k_input.push(message[i])
  }
  let k_hash = @sha512.sha512(Bytes::from_array(k_input))
  let k = bytes_to_bigint_le(bytes_to_array(k_hash))
  let k = match @bigint.divmod(k, l_order) {
    Some((_, rem)) => rem
    None => k
  }
  // Verification: S * B == R + k * A
  let sb = scalar_mult(s, base_point)
  let ka = scalar_mult(k, a_point)
  let rka = point_add(r_point, ka)
  // Compare by encoding both points
  let sb_enc = point_encode(sb)
  let rka_enc = point_encode(rka)
  constant_time_eq(sb_enc, rka_enc)
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Decode a clamped scalar from 32 bytes of a hash (little-endian).
fn decode_scalar(h : Bytes, offset : Int) -> @bigint.BigInt {
  let bytes : Array[Byte] = []
  for i = 0; i < 32; i = i + 1 {
    bytes.push(h[offset + i])
  }
  // Clamp: clear bits 0-2 of byte 0, clear bit 7 of byte 31, set bit 6 of byte 31
  bytes[0] = (bytes[0].to_int() & 248).to_byte()
  bytes[31] = (bytes[31].to_int() & 127).to_byte()
  bytes[31] = (bytes[31].to_int() | 64).to_byte()
  bytes_to_bigint_le(bytes)
}

/// Slice a Bytes into an Array[Byte].
fn slice(data : Bytes, offset : Int, len : Int) -> Array[Byte] {
  let result : Array[Byte] = []
  for i = 0; i < len; i = i + 1 {
    result.push(data[offset + i])
  }
  result
}

/// Convert Bytes to Array[Byte].
fn bytes_to_array(data : Bytes) -> Array[Byte] {
  let result : Array[Byte] = []
  for i = 0; i < data.length(); i = i + 1 {
    result.push(data[i])
  }
  result
}

/// Constant-time byte array comparison.
fn constant_time_eq(a : Bytes, b : Bytes) -> Bool {
  if a.length() != b.length() {
    return false
  }
  let mut diff = 0
  for i = 0; i < a.length(); i = i + 1 {
    diff = diff | (a[i].to_int() ^ b[i].to_int())
  }
  diff == 0
}
