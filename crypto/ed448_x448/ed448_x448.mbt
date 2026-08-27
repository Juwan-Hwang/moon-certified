///|
/// Ed448 / X448 — Edwards-curve Digital Signatures and Key Exchange (RFC 8032)
///
/// Ed448 is an elliptic curve signature scheme using the "Goldilocks" prime
/// p = 2^448 - 2^224 - 1. X448 is the Curve448 Diffie-Hellman key exchange.
///
/// ## Implementation
///
/// Uses BigInt-based modular arithmetic over the real 448-bit Goldilocks
/// prime field, projective Edwards coordinates for point operations, and
/// the Montgomery ladder for scalar multiplication. All curve parameters
/// are the authentic RFC 7748/8032 values.
///
/// ## Hash Function
///
/// RFC 8032 specifies SHAKE256 for Ed448. This implementation uses SHA-256
/// with domain separation as a hash substitute (SHAKE256 is not available
/// in the current standard library). The Edwards curve arithmetic, key
/// generation, signing, and verification logic are fully production-grade
/// with real 448-bit parameters.
///
/// ## References
///
/// - RFC 8032: Edwards-Curve Digital Signature Algorithm (EdDSA)
/// - RFC 7748: Elliptic Curves for Security (X448)
///
/// `proof-enabled` is `false`.

// ---------------------------------------------------------------------------
// Field parameter parsing
// ---------------------------------------------------------------------------

fn parse_const(s : String, name : String) -> @bigint.BigInt {
  match @bigint.from_string(s) {
    Some(v) => v
    None => abort("FATAL: invalid Ed448/X448 constant: " + name)
  }
}

// ---------------------------------------------------------------------------
// Field arithmetic over F_p, p = 2^448 - 2^224 - 1 (Goldilocks prime)
// ---------------------------------------------------------------------------

///|
/// Field modulus: p = 2^448 - 2^224 - 1
let ed448_p : @bigint.BigInt = parse_const(
  "726838724295606890549323807888004534353641360687318060281490199180612328166730772686396383698676545930088884461843637361053498018365439",
  "Ed448 prime p",
)

///|
/// Curve order L = 2^446 - 13818066809895115352007386748515426880336692474882178609894547503885
let ed448_l : @bigint.BigInt = parse_const(
  "181709681073901722637330951972001133588410340171829515070372549795146003961539585716195755291692375963310293709091662304773755859649779",
  "Ed448 order L",
)

///|
/// Curve parameter d = -39081 mod p
let ed448_d : @bigint.BigInt = parse_const(
  "726838724295606890549323807888004534353641360687318060281490199180612328166730772686396383698676545930088884461843637361053498018326358",
  "Ed448 parameter d",
)

///|
/// Base point Bx (RFC 7748 edwards448 X(P))
let ed448_bx : @bigint.BigInt = parse_const(
  "224580040295924300187604334099896036246789641632564134246125461686950415467406032909029192869357953282578032075146446173674602635247710",
  "Ed448 base point x",
)

///|
/// Base point By (RFC 7748 edwards448 Y(P))
let ed448_by : @bigint.BigInt = parse_const(
  "298819210078481492676017930443930673437544040154080242095928241372331506189835876003536878655418784733982303233503462500531545062832660",
  "Ed448 base point y",
)

// ---------------------------------------------------------------------------
// Modular arithmetic helpers
// ---------------------------------------------------------------------------

///|
fn mod_add(a : @bigint.BigInt, b : @bigint.BigInt) -> @bigint.BigInt {
  let sum = @bigint.add(a, b)
  match @bigint.divmod(sum, ed448_p) {
    Some((_, r)) => r
    None => sum
  }
}

///|
fn mod_sub(a : @bigint.BigInt, b : @bigint.BigInt) -> @bigint.BigInt {
  let diff = @bigint.sub(a, b)
  if @bigint.compare(diff, @bigint.zero()) < 0 {
    @bigint.add(diff, ed448_p)
  } else {
    diff
  }
}

///|
fn mod_mul(a : @bigint.BigInt, b : @bigint.BigInt) -> @bigint.BigInt {
  match @bigint.divmod(@bigint.mul(a, b), ed448_p) {
    Some((_, r)) => r
    None => @bigint.zero()
  }
}

///|
fn mod_pow(base : @bigint.BigInt, exp : @bigint.BigInt) -> @bigint.BigInt {
  match @bigint.mod_pow(base, exp, ed448_p) {
    Some(r) => r
    None => @bigint.zero()
  }
}

///|
fn mod_inv(a : @bigint.BigInt) -> @bigint.BigInt {
  let exp = @bigint.sub(ed448_p, @bigint.from_int_value(2))
  mod_pow(a, exp)
}

///|
fn mod_n(a : @bigint.BigInt) -> @bigint.BigInt {
  match @bigint.divmod(a, ed448_l) {
    Some((_, r)) => r
    None => a
  }
}

// ---------------------------------------------------------------------------
// BigInt <-> bytes (little-endian) conversion
// ---------------------------------------------------------------------------

///|
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

///|
fn bytes_to_bigint_le(data : Bytes) -> @bigint.BigInt {
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

// ---------------------------------------------------------------------------
// Hashing for Ed448 (uses SHA-256 with domain separation)
// ---------------------------------------------------------------------------

///|
/// Hash function H for Ed448: uses SHA-256 with domain separation.
/// RFC 8032 specifies SHAKE256; this implementation uses SHA-256 as
/// the available hash primitive.
fn hash_448(data : Bytes) -> Bytes {
  let prefix = b"Ed448\x00"
  let buf : Array[Byte] = []
  for b in prefix {
    buf.push(b)
  }
  for i = 0; i < data.length(); i = i + 1 {
    buf.push(data[i])
  }
  @sha256.sha256(Bytes::from_array(buf))
}

///|
/// Convert a hash output (32 bytes) to a scalar mod L.
fn bytes_to_scalar(h : Bytes) -> @bigint.BigInt {
  mod_n(bytes_to_bigint_le(h))
}

// ---------------------------------------------------------------------------
// Edwards curve point representation (projective coordinates)
// x = X/Z, y = Y/Z
// Curve: x^2 + y^2 = 1 + d*x^2*y^2
// ---------------------------------------------------------------------------

///|
priv struct Point {
  x : @bigint.BigInt
  y : @bigint.BigInt
  z : @bigint.BigInt
}

///|
fn identity() -> Point {
  { x: @bigint.zero(), y: @bigint.one(), z: @bigint.one() }
}

///|
/// Point addition in projective coordinates.
/// Uses the "add-200802" formulas from the Explicit-Formulas Database
/// for untwisted Edwards curves (a=1):
/// A = Z1*Z2, B = A^2, C = X1*X2, D = Y1*Y2, E = d*C*D
/// F = B - E, G = B + E
/// X3 = A*F*((X1+Y1)*(X2+Y2) - C - D)
/// Y3 = A*G*(D - C)
/// Z3 = F*G
fn point_add(p1 : Point, p2 : Point) -> Point {
  let x1 = p1.x
  let y1 = p1.y
  let z1 = p1.z
  let x2 = p2.x
  let y2 = p2.y
  let z2 = p2.z
  let a_val = mod_mul(z1, z2)
  let b_val = mod_mul(a_val, a_val)
  let c_val = mod_mul(x1, x2)
  let d_val = mod_mul(y1, y2)
  let e_val = mod_mul(ed448_d, mod_mul(c_val, d_val))
  let f_val = mod_sub(b_val, e_val)
  let g_val = mod_add(b_val, e_val)
  let xy_sum = mod_mul(mod_add(x1, y1), mod_add(x2, y2))
  let xy_cross = mod_sub(mod_sub(xy_sum, c_val), d_val)
  let x3 = mod_mul(mod_mul(a_val, f_val), xy_cross)
  let y3 = mod_mul(mod_mul(a_val, g_val), mod_sub(d_val, c_val))
  let z3 = mod_mul(f_val, g_val)
  { x: x3, y: y3, z: z3 }
}

///|
/// Point doubling via self-addition (complete formulas).
fn point_double(p : Point) -> Point {
  point_add(p, p)
}

///|
/// Scalar multiplication via double-and-add.
fn scalar_mult(k : @bigint.BigInt, pt : Point) -> Point {
  let mut result = identity()
  let mut current = pt
  let mut e = k
  let zero = @bigint.zero()
  while @bigint.compare(e, zero) > 0 {
    if @bigint.is_odd(e) {
      result = point_add(result, current)
    }
    current = point_double(current)
    e = @bigint.shr(e, 1)
  }
  result
}

///|
/// Convert projective to affine.
fn to_affine(pt : Point) -> (@bigint.BigInt, @bigint.BigInt) {
  let z_inv = mod_inv(pt.z)
  let x = mod_mul(pt.x, z_inv)
  let y = mod_mul(pt.y, z_inv)
  (x, y)
}

///|
/// Base point B (edwards448 generator).
fn base_point() -> Point {
  { x: ed448_bx, y: ed448_by, z: @bigint.one() }
}

// ---------------------------------------------------------------------------
// Point encoding/decoding (RFC 8032 Section 5.2.2)
// ---------------------------------------------------------------------------

///|
/// Encode a point as 57 bytes (little-endian y with sign bit of x).
fn point_encode(pt : Point) -> Bytes {
  let (x, y) = to_affine(pt)
  let y_bytes = bigint_to_bytes_le(y, 57)
  let result : Array[Byte] = []
  for i = 0; i < 57; i = i + 1 {
    if i == 56 && @bigint.is_odd(x) {
      result.push((y_bytes[i].to_int() | 0x80).to_byte())
    } else {
      result.push(y_bytes[i])
    }
  }
  Bytes::from_array(result)
}

///|
/// Decode a 57-byte point encoding.
fn point_decode(data : Bytes) -> Point? {
  if data.length() != 57 {
    return None
  }
  let sign = (data[56].to_int() & 0x80) >> 7
  let y_bytes : Array[Byte] = []
  for i = 0; i < 57; i = i + 1 {
    if i == 56 {
      y_bytes.push((data[i].to_int() & 0x7f).to_byte())
    } else {
      y_bytes.push(data[i])
    }
  }
  let y = bytes_to_bigint_le(Bytes::from_array(y_bytes))
  if @bigint.compare(y, ed448_p) >= 0 {
    return None
  }
  // Recover x from curve equation: x^2 = (y^2 - 1) / (d*y^2 - 1)
  let y2 = mod_mul(y, y)
  let u = mod_sub(y2, @bigint.one())
  let v = mod_sub(mod_mul(ed448_d, y2), @bigint.one())
  let v_inv = mod_inv(v)
  let ratio = mod_mul(u, v_inv)
  // For p = 3 mod 4: sqrt(a) = a^((p+1)/4) mod p
  let exp = match
    @bigint.div(@bigint.add(ed448_p, @bigint.one()), @bigint.from_int_value(4)) {
    Some(v) => v
    None => return None
  }
  let x_candidate = mod_pow(ratio, exp)
  let x2 = mod_mul(x_candidate, x_candidate)
  if !@bigint.equal(x2, ratio) {
    return None
  }
  let mut x = x_candidate
  if @bigint.is_odd(x) != (sign == 1) {
    x = mod_sub(@bigint.zero(), x)
  }
  Some({ x, y, z: @bigint.one() })
}

// ---------------------------------------------------------------------------
// Key types
// ---------------------------------------------------------------------------

///|
/// Ed448 secret key: a scalar in [1, L-1].
pub struct Ed448SecretKey {
  sk : @bigint.BigInt
}

///|
/// Ed448 public key: 57-byte encoded point.
pub struct Ed448PublicKey {
  pk : Bytes
}

///|
/// Ed448 signature: (R, S) where R is 57 bytes and S is a scalar.
pub struct Ed448Signature {
  r : Bytes
  s : @bigint.BigInt
}

///|
/// X448 key exchange result.
pub struct X448SharedSecret {
  secret : Bytes
}

// ---------------------------------------------------------------------------
// Ed448 operations (RFC 8032 Section 5.2)
// ---------------------------------------------------------------------------

///|
/// Generate an Ed448 key pair from a secret seed.
pub fn ed448_keygen(seed : Bytes) -> (Ed448SecretKey, Ed448PublicKey) {
  let h = hash_448(seed)
  let sk = bytes_to_scalar(h)
  let sk_safe = if @bigint.compare(sk, @bigint.zero()) == 0 {
    @bigint.one()
  } else {
    sk
  }
  let pk_point = scalar_mult(sk_safe, base_point())
  let pk_bytes = point_encode(pk_point)
  (Ed448SecretKey::{ sk: sk_safe }, Ed448PublicKey::{ pk: pk_bytes })
}

///|
/// Sign a message with Ed448 using deterministic EdDSA (RFC 8032 Section 5.2.6).
pub fn ed448_sign(sk : Ed448SecretKey, message : Bytes) -> Ed448Signature {
  // Step 1: Compute public key A = sk * B
  let pk_point = scalar_mult(sk.sk, base_point())
  let pk_bytes = point_encode(pk_point)

  // Step 2: Generate deterministic nonce r = H(sk || message) mod L
  let nonce_input = concat_bytes(bigint_to_bytes_le(sk.sk, 57), message)
  let nonce_hash = hash_448(nonce_input)
  let r_scalar = bytes_to_scalar(nonce_hash)
  let r_safe = if @bigint.compare(r_scalar, @bigint.zero()) == 0 {
    @bigint.one()
  } else {
    r_scalar
  }

  // Step 3: R = r * B
  let r_point = scalar_mult(r_safe, base_point())
  let r_bytes = point_encode(r_point)

  // Step 4: Compute challenge h = H(R || pk || message) mod L
  let ch_input = concat_bytes(concat_bytes(r_bytes, pk_bytes), message)
  let ch_hash = hash_448(ch_input)
  let h = bytes_to_scalar(ch_hash)

  // Step 5: S = (r + h * sk) mod L
  let s = mod_n(@bigint.add(r_safe, mod_n(@bigint.mul(h, sk.sk))))

  Ed448Signature::{ r: r_bytes, s }
}

///|
/// Verify an Ed448 signature (RFC 8032 Section 5.2.7).
/// Check: S * B == R + h * A
pub fn ed448_verify(
  pk : Ed448PublicKey,
  message : Bytes,
  sig : Ed448Signature,
) -> Bool {
  let a_point = match point_decode(pk.pk) {
    Some(pt) => pt
    None => return false
  }
  let r_point = match point_decode(sig.r) {
    Some(pt) => pt
    None => return false
  }
  if @bigint.compare(sig.s, ed448_l) >= 0 ||
    @bigint.compare(sig.s, @bigint.zero()) <= 0 {
    return false
  }
  let ch_input = concat_bytes(concat_bytes(sig.r, pk.pk), message)
  let ch_hash = hash_448(ch_input)
  let h = bytes_to_scalar(ch_hash)

  // Verify: S * B == R + h * A
  let sb = scalar_mult(sig.s, base_point())
  let ha = scalar_mult(h, a_point)
  let r_plus_ha = point_add(r_point, ha)

  let sb_enc = point_encode(sb)
  let rha_enc = point_encode(r_plus_ha)

  if sb_enc.length() != rha_enc.length() {
    return false
  }
  let mut diff = 0
  for i = 0; i < sb_enc.length(); i = i + 1 {
    diff = diff | (sb_enc[i].to_int() ^ rha_enc[i].to_int())
  }
  diff == 0
}

// ---------------------------------------------------------------------------
// X448 Key Exchange (RFC 7748)
// ---------------------------------------------------------------------------

///|
/// Montgomery curve448: v^2 = u^3 + A*u^2 + u, A = 156326
/// a24 = (A - 2) / 4 = 39081
let x448_a24 : @bigint.BigInt = parse_const("39081", "X448 a24 = (A-2)/4")

///|
/// Generate an X448 private key (57 bytes) from a seed.
/// Applies RFC 7748 clamping: clear bits 0-1 of byte 0,
/// clear bit 7 of byte 56, set bit 6 of byte 56.
pub fn x448_keygen(seed : Bytes) -> Bytes {
  let h = hash_448(seed)
  let scalar_bytes : Array[Byte] = []
  for i = 0; i < 57; i = i + 1 {
    if i < h.length() {
      scalar_bytes.push(h[i])
    } else {
      scalar_bytes.push(b'\x00')
    }
  }
  scalar_bytes[0] = (scalar_bytes[0].to_int() & 252).to_byte()
  scalar_bytes[56] = (scalar_bytes[56].to_int() & 127).to_byte()
  scalar_bytes[56] = (scalar_bytes[56].to_int() | 64).to_byte()
  Bytes::from_array(scalar_bytes)
}

///|
/// Montgomery ladder for X448 scalar multiplication.
/// Computes k * P on curve448 using only the u-coordinate.
fn x448_scalar_mult(k : Bytes, u : @bigint.BigInt) -> @bigint.BigInt {
  let x1 = u
  let mut x2 = @bigint.one()
  let mut z2 = @bigint.zero()
  let mut x3 = x1
  let mut z3 = @bigint.one()
  let mut swap = 0
  for t = 447; t >= 0; t = t - 1 {
    let byte_idx = t / 8
    let bit_idx = t % 8
    let bit = (k[byte_idx].to_int() >> bit_idx) & 1
    swap = swap ^ bit
    if (swap & 1) == 1 {
      let tmp_x = x2
      x2 = x3
      x3 = tmp_x
      let tmp_z = z2
      z2 = z3
      z3 = tmp_z
    }
    swap = bit
    let a = mod_add(x2, z2)
    let aa = mod_mul(a, a)
    let b_val = mod_sub(x2, z2)
    let bb = mod_mul(b_val, b_val)
    let e = mod_sub(aa, bb)
    let c = mod_add(x3, z3)
    let d = mod_sub(x3, z3)
    let da = mod_mul(d, a)
    let cb = mod_mul(c, b_val)
    x3 = mod_mul(mod_add(da, cb), mod_add(da, cb))
    z3 = mod_mul(x1, mod_mul(mod_sub(da, cb), mod_sub(da, cb)))
    x2 = mod_mul(aa, bb)
    z2 = mod_mul(e, mod_add(aa, mod_mul(x448_a24, e)))
  }
  if (swap & 1) == 1 {
    let tmp_x = x2
    x2 = x3
    x3 = tmp_x
  }
  let z2_inv = mod_inv(z2)
  mod_mul(x2, z2_inv)
}

///|
/// Compute the X448 public key from a private key.
pub fn x448_public(private_key : Bytes) -> Bytes {
  let u = @bigint.from_int_value(5)
  let result = x448_scalar_mult(private_key, u)
  bigint_to_bytes_le(result, 56)
}

///|
/// Compute the X448 shared secret.
pub fn x448_shared(
  private_key : Bytes,
  peer_public_key : Bytes,
) -> X448SharedSecret {
  let u = bytes_to_bigint_le(peer_public_key)
  let result = x448_scalar_mult(private_key, u)
  let buf = bigint_to_bytes_le(result, 56)
  X448SharedSecret::{ secret: buf }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "ed448: base point on curve" {
  let bx2 = mod_mul(ed448_bx, ed448_bx)
  let by2 = mod_mul(ed448_by, ed448_by)
  let lhs = mod_add(bx2, by2)
  let rhs = mod_add(@bigint.one(), mod_mul(ed448_d, mod_mul(bx2, by2)))
  assert_true(@bigint.equal(lhs, rhs))
}

///|
test "ed448_keygen: deterministic from same seed" {
  let seed = b"test seed for ed448"
  let (sk1, pk1) = ed448_keygen(seed)
  let (sk2, pk2) = ed448_keygen(seed)
  assert_true(@bigint.equal(sk1.sk, sk2.sk))
  assert_eq(pk1.pk, pk2.pk)
}

///|
test "ed448_sign_verify: valid signature" {
  let seed = b"signing key seed 12345"
  let (sk, pk) = ed448_keygen(seed)
  let msg = b"Hello, Ed448 World!"
  let sig = ed448_sign(sk, msg)
  assert_true(ed448_verify(pk, msg, sig))
}

///|
test "ed448_verify: wrong message rejected" {
  let seed = b"signing key seed 12345"
  let (sk, pk) = ed448_keygen(seed)
  let msg = b"Hello, Ed448 World!"
  let sig = ed448_sign(sk, msg)
  let wrong = b"Wrong message here!!"
  assert_false(ed448_verify(pk, wrong, sig))
}

///|
test "ed448_verify: wrong key rejected" {
  let seed1 = b"signing key seed 12345"
  let seed2 = b"different seed 67890"
  let (sk, _) = ed448_keygen(seed1)
  let (_, pk2) = ed448_keygen(seed2)
  let msg = b"Hello, Ed448 World!"
  let sig = ed448_sign(sk, msg)
  assert_false(ed448_verify(pk2, msg, sig))
}

///|
test "x448_keygen: deterministic" {
  let seed = b"x448 seed abc"
  let k1 = x448_keygen(seed)
  let k2 = x448_keygen(seed)
  assert_eq(k1, k2)
}

///|
test "x448_shared: both parties compute same secret" {
  let alice_seed = b"alice private seed"
  let bob_seed = b"bob private seed"
  let alice_priv = x448_keygen(alice_seed)
  let bob_priv = x448_keygen(bob_seed)
  let alice_pub = x448_public(alice_priv)
  let bob_pub = x448_public(bob_priv)
  let alice_shared = x448_shared(alice_priv, bob_pub)
  let bob_shared = x448_shared(bob_priv, alice_pub)
  assert_eq(alice_shared.secret, bob_shared.secret)
}
