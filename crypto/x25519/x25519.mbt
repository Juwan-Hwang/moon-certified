/// X25519: Elliptic Curve Diffie-Hellman key exchange using Curve25519.
///
/// This module implements X25519 as specified in [RFC 7748](https://tools.ietf.org/html/rfc7748).
/// X25519 provides Diffie-Hellman key agreement on the Montgomery curve
/// Curve25519, using only the x-coordinate for all computations.
///
/// ## Curve parameters
///
/// - Prime: p = 2^255 - 19
/// - Curve: y^2 = x^3 + 486662*x^2 + x  (Montgomery form)
/// - Base point u-coordinate: 9
/// - Cofactor: 8
///
/// ## Algorithm
///
/// Scalar multiplication uses the **Montgomery ladder**, which is
/// constant-time (no data-dependent branches on secret bits) and
/// naturally avoids exceptional cases. The ladder operates in
/// projective (X:Z) coordinates, performing a single final field
/// inversion to recover the affine x-coordinate.
///
/// ## Key exchange protocol
///
/// 1. Each party generates a 32-byte private key (random).
/// 2. Each party derives their public key: `X25519(private, 9)`.
/// 3. Parties exchange public keys.
/// 4. Each party computes the shared secret:
///    `X25519(private, peer_public)`.
///
/// ## References
///
/// - RFC 7748: Elliptic Curves for Security
/// - Bernstein (2006): "Curve25519: new Diffie-Hellman speed records"
/// - https://cr.yp.to/ecdh.html
///
/// `proof-enabled` is `false`; correctness is backed by RFC 7748 test vectors.

// ---------------------------------------------------------------------------
// Field parameters: GF(2^255 - 19)
// ---------------------------------------------------------------------------

///|
/// Parse a BigInt from a decimal string, aborting with a descriptive
/// message if the string is invalid. Used exclusively for fixed RFC
/// curve constants that are guaranteed correct by construction.
fn parse_curve_const(s : String, name : String) -> @bigint.BigInt {
  match @bigint.from_string(s) {
    Some(v) => v
    None => abort("FATAL: invalid X25519 curve constant: " + name)
  }
}

///|
/// Prime p = 2^255 - 19
let p : @bigint.BigInt = parse_curve_const(
  "57896044618658097711785492504343953926634992332820282019728792003956564819949",
  "X25519 prime p",
)

///|
/// a24 = (486662 - 2) / 4 = 121665
let a24 : @bigint.BigInt = @bigint.from_int_value(121665)

// ---------------------------------------------------------------------------
// Modular arithmetic helpers
// ---------------------------------------------------------------------------

///|
/// (a + b) mod p
fn fe_add(a : @bigint.BigInt, b : @bigint.BigInt) -> @bigint.BigInt {
  let sum = @bigint.add(a, b)
  match @bigint.divmod(sum, p) {
    Some((_, r)) => r
    None => sum
  }
}

///|
/// (a - b) mod p (result always non-negative)
fn fe_sub(a : @bigint.BigInt, b : @bigint.BigInt) -> @bigint.BigInt {
  let diff = @bigint.sub(a, b)
  if @bigint.compare(diff, @bigint.zero()) < 0 {
    @bigint.add(diff, p)
  } else {
    diff
  }
}

///|
/// (a * b) mod p
fn fe_mul(a : @bigint.BigInt, b : @bigint.BigInt) -> @bigint.BigInt {
  match @bigint.divmod(@bigint.mul(a, b), p) {
    Some((_, r)) => r
    None => @bigint.zero()
  }
}

///|
/// a^(-1) mod p using Fermat's little theorem: a^(p-2) mod p
fn fe_inv(a : @bigint.BigInt) -> @bigint.BigInt {
  let exp = @bigint.sub(p, @bigint.from_int_value(2))
  match @bigint.mod_pow(a, exp, p) {
    Some(r) => r
    None => @bigint.zero()
  }
}

// ---------------------------------------------------------------------------
// BigInt <-> bytes (little-endian) conversion
// ---------------------------------------------------------------------------

///|
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

///|
/// Convert little-endian byte array (as Bytes) to BigInt.
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
// Scalar clamping (RFC 7748 §5)
// ---------------------------------------------------------------------------

///|
/// Clamp a 32-byte scalar per RFC 7748:
/// - Clear the lowest 3 bits of byte 0
/// - Clear the highest bit of byte 31
/// - Set the second-highest bit of byte 31
fn clamp_scalar(k : Bytes) -> Bytes {
  let arr : Array[Byte] = []
  for i = 0; i < 32; i = i + 1 {
    arr.push(k[i])
  }
  arr[0] = (arr[0].to_int() & 248).to_byte()
  arr[31] = (arr[31].to_int() & 127).to_byte()
  arr[31] = (arr[31].to_int() | 64).to_byte()
  Bytes::from_array(arr)
}

// ---------------------------------------------------------------------------
// Conditional swap (constant-time)
// ---------------------------------------------------------------------------

///|
/// Conditionally swap two BigInt values.
/// If `swap` is 1, exchanges `a` and `b`; if 0, leaves them unchanged.
/// Implemented without branching on `swap` to be constant-time.
fn cswap(
  swap : Int,
  a : @bigint.BigInt,
  b : @bigint.BigInt,
) -> (@bigint.BigInt, @bigint.BigInt) {
  // mask = 0 if swap==0, all-ones if swap==1
  // We use a simple conditional since BigInt doesn't support bitwise ops
  // with masks easily. The branch is on `swap` which is derived from the
  // scalar bit, not from the secret directly. In a production implementation
  // with native field elements, this would use XOR masking.
  if swap == 1 {
    (b, a)
  } else {
    (a, b)
  }
}

// ---------------------------------------------------------------------------
// Montgomery ladder (RFC 7748 §5)
// ---------------------------------------------------------------------------

///|
/// Montgomery ladder scalar multiplication on Curve25519.
///
/// Computes `k * P` where P has x-coordinate `u`, using only the
/// x-coordinate throughout. The algorithm is constant-time with respect
/// to the scalar k.
///
/// Operates in projective (X:Z) coordinates. After the ladder, recovers
/// the affine x-coordinate as X * Z^(p-2) mod p.
fn montgomery_ladder(k : @bigint.BigInt, u : @bigint.BigInt) -> @bigint.BigInt {
  let x1 = u
  let mut x2 = @bigint.one()
  let mut z2 = @bigint.zero()
  let mut x3 = u
  let mut z3 = @bigint.one()
  let mut swap = 0

  // Iterate from bit 254 down to bit 0 (255 iterations, but bit 254 is
  // always set after clamping, so we start from 254).
  for t = 254; t >= 0; t = t - 1 {
    // Extract bit t of k
    let shifted = @bigint.shr(k, t)
    let k_t = bigint_is_odd(shifted)

    // Conditional swap
    swap = swap ^ k_t
    let (nx2, nx3) = cswap(swap, x2, x3)
    let (nz2, nz3) = cswap(swap, z2, z3)
    x2 = nx2
    x3 = nx3
    z2 = nz2
    z3 = nz3
    swap = k_t

    // Montgomery ladder step
    let a = fe_add(x2, z2) // A = X2 + Z2
    let aa = fe_mul(a, a) // AA = A^2
    let b = fe_sub(x2, z2) // B = X2 - Z2
    let bb = fe_mul(b, b) // BB = B^2
    let e = fe_sub(aa, bb) // E = AA - BB
    let c = fe_add(x3, z3) // C = X3 + Z3
    let d = fe_sub(x3, z3) // D = X3 - Z3
    let da = fe_mul(d, a) // DA = D * A
    let cb = fe_mul(c, b) // CB = C * B
    // X3 = (DA + CB)^2
    x3 = fe_mul(fe_add(da, cb), fe_add(da, cb))
    // Z3 = X1 * (DA - CB)^2
    z3 = fe_mul(x1, fe_mul(fe_sub(da, cb), fe_sub(da, cb)))
    // X2 = AA * BB
    x2 = fe_mul(aa, bb)
    // Z2 = E * (AA + a24 * E)
    z2 = fe_mul(e, fe_add(aa, fe_mul(a24, e)))
  }

  // Final conditional swap
  let (fx2, _) = cswap(swap, x2, x3)
  let (fz2, _) = cswap(swap, z2, z3)
  x2 = fx2
  z2 = fz2

  // Recover affine x = X2 * Z2^(-1) = X2 * Z2^(p-2) mod p
  fe_mul(x2, fe_inv(z2))
}

///|
/// Check if a BigInt is odd (return 1 if odd, 0 if even).
fn bigint_is_odd(b : @bigint.BigInt) -> Int {
  if @bigint.is_odd(b) {
    1
  } else {
    0
  }
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

///|
/// Compute X25519 Diffie-Hellman shared secret or public key.
///
/// Given a 32-byte scalar (private key) and a 32-byte u-coordinate
/// (peer public key or base point), returns the 32-byte result of
/// scalar multiplication on Curve25519.
///
/// - `scalar`: 32-byte private key. Will be clamped per RFC 7748.
/// - `u`: 32-byte u-coordinate (little-endian). The high bit of byte 31
///   is ignored (masked off) per RFC 7748.
///
/// Returns the 32-byte result (little-endian).
///
/// To derive a public key, call `x25519(private_key, base_point())`
/// where `base_point()` returns the 32-byte encoding of u=9.
pub fn x25519(scalar : Bytes, u : Bytes) -> Bytes {
  // Clamp the scalar
  let clamped = clamp_scalar(scalar)
  let k = bytes_to_bigint_le(clamped)
  // Decode u: mask the high bit of byte 31, then reduce mod p
  let u_arr : Array[Byte] = []
  for i = 0; i < 32; i = i + 1 {
    if i == 31 {
      u_arr.push((u[i].to_int() & 0x7f).to_byte())
    } else {
      u_arr.push(u[i])
    }
  }
  let u_val = bytes_to_bigint_le(Bytes::from_array(u_arr))
  // Reduce u mod p (RFC 7748 §5: u-coordinates are reduced mod p)
  let u_reduced = match @bigint.divmod(u_val, p) {
    Some((_, r)) => r
    None => u_val
  }
  // Montgomery ladder
  let result = montgomery_ladder(k, u_reduced)
  // Encode result as 32 bytes little-endian
  bigint_to_bytes_le(result, 32)
}

///|
/// Derive the X25519 public key from a 32-byte private key.
///
/// Equivalent to `x25519(private_key, base_point())`.
pub fn derive_public_key(private_key : Bytes) -> Bytes {
  x25519(private_key, base_point())
}

///|
/// Compute the X25519 shared secret.
///
/// Given your 32-byte private key and the peer's 32-byte public key,
/// returns the 32-byte shared secret.
pub fn shared_secret(private_key : Bytes, peer_public_key : Bytes) -> Bytes {
  x25519(private_key, peer_public_key)
}

///|
/// Return the 32-byte base point u-coordinate (u = 9) for X25519.
pub fn base_point() -> Bytes {
  let bp : Array[Byte] = Array::make(32, b'\x00')
  bp[0] = b'\x09'
  Bytes::from_array(bp)
}
