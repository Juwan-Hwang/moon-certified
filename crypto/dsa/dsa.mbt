/// Digital Signature Algorithm (DSA) — FIPS 186-4
///
/// DSA is a federal standard for digital signatures based on the discrete
/// logarithm problem in Z_p*. This module implements DSA key generation,
/// signing, and verification using real FIPS 186-4 (L=2048, N=256)
/// domain parameters from RFC 6979 Appendix A.2.2 and RFC 6979
/// deterministic nonce generation.
///
/// ## Parameters
/// - p: 2048-bit prime modulus (FIPS 186-4 / RFC 6979)
/// - q: 256-bit prime divisor of p-1 (FIPS 186-4 / RFC 6979)
/// - g: generator of the subgroup of order q
///
/// ## References
/// - FIPS 186-4: Digital Signature Standard
/// - RFC 6979: Deterministic Usage of DSA and ECDSA (Appendix A.2.2)
///
/// `proof-enabled` is `false`.

// ---------------------------------------------------------------------------
// Parameter parsing
// ---------------------------------------------------------------------------

fn parse_const(s : String, name : String) -> @bigint.BigInt {
  match @bigint.from_string(s) {
    Some(v) => v
    None => abort("FATAL: invalid DSA constant: " + name)
  }
}

// ---------------------------------------------------------------------------
// FIPS 186-4 domain parameters (L=2048, N=256)
// From RFC 6979 Appendix A.2.2 — standard test parameters.
// ---------------------------------------------------------------------------

///|
/// DSA prime p (2048 bits, RFC 6979 A.2.2)
pub let dsa_p : @bigint.BigInt = parse_const(
  "0x9DB6FB5951B66BB6FE1E140F1D2CE5502374161FD6538DF1648218642F0B5C48C8F7A41AADFA187324B87674FA1822B00F1ECF8136943D7C55757264E5A1A44FFE012E9936E00C1D3E9310B01C7D179805D3058B2A9F4BB6F9716BFE6117C6B5B3CC4D9BE341104AD4A80AD6C94E005F4B993E14F091EB51743BF33050C38DE235567E1B34C3D6A5C0CEAA1A0F368213C3D19843D0B4B09DCB9FC72D39C8DE41F1BF14D4BB4563CA28371621CAD3324B6A2D392145BEBFAC748805236F5CA2FE92B871CD8F9C36D3292B5509CA8CAA77A2ADFC7BFD77DDA6F71125A7456FEA153E433256A2261C6A06ED3693797E7995FAD5AABBCFBE3EDA2741E375404AE25B",
  "DSA prime p",
)

///|
/// DSA subgroup order q (256 bits, RFC 6979 A.2.2)
pub let dsa_q : @bigint.BigInt = parse_const(
  "0xF2C3119374CE76C9356990B465374A17F23F9ED35089BD969F61C6DDE9998C1F",
  "DSA order q",
)

///|
/// DSA generator g (RFC 6979 A.2.2)
pub let dsa_g : @bigint.BigInt = parse_const(
  "0x5C7FF6B06F8F143FE8288433493E4769C4D988ACE5BE25A0E24809670716C613D7B0CEE6932F8FAA7C44D2CB24523DA53FBE4F6EC3595892D1AA58C4328A06C46A15662E7EAA703A1DECF8BBB2D05DBE2EB956C142A338661D10461C0D135472085057F3494309FFA73C611F78B32ADBB5740C361C9F35BE90997DB2014E2EF5AA61782F52ABEB8BD6432C4DD097BC5423B285DAFB60DC364E8161F4A2A35ACA3A10B1C4D203CC76A470A33AFDCBDD92959859ABD8B56E1725252D78EAC66E71BA9AE3F1DD2487199874393CD4D832186800654760E1E34C09E4D155179F9EC0DC4473F996BDCE6EED1CABED8B6F116F7AD9CF505DF0F998E34AB27514B0FFE7",
  "DSA generator g",
)

// ---------------------------------------------------------------------------
// Modular arithmetic helpers
// ---------------------------------------------------------------------------

///|
fn mod_p(a : @bigint.BigInt, b : @bigint.BigInt) -> @bigint.BigInt {
  match @bigint.divmod(@bigint.mul(a, b), dsa_p) {
    Some((_, r)) => r
    None => @bigint.zero()
  }
}

///|
fn mod_q(a : @bigint.BigInt, b : @bigint.BigInt) -> @bigint.BigInt {
  match @bigint.divmod(@bigint.mul(a, b), dsa_q) {
    Some((_, r)) => r
    None => @bigint.zero()
  }
}

///|
fn mod_pow_p(base : @bigint.BigInt, exp : @bigint.BigInt) -> @bigint.BigInt {
  match @bigint.mod_pow(base, exp, dsa_p) {
    Some(r) => r
    None => @bigint.zero()
  }
}

///|
fn mod_pow_q(base : @bigint.BigInt, exp : @bigint.BigInt) -> @bigint.BigInt {
  match @bigint.mod_pow(base, exp, dsa_q) {
    Some(r) => r
    None => @bigint.zero()
  }
}

///|
fn mod_inv_q(a : @bigint.BigInt) -> @bigint.BigInt {
  let exp = @bigint.sub(dsa_q, @bigint.from_int_value(2))
  mod_pow_q(a, exp)
}

///|
fn reduce_q(a : @bigint.BigInt) -> @bigint.BigInt {
  match @bigint.divmod(a, dsa_q) {
    Some((_, r)) => r
    None => a
  }
}

// ---------------------------------------------------------------------------
// BigInt <-> bytes conversion (big-endian)
// ---------------------------------------------------------------------------

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

fn bytes_single(b : Byte) -> Bytes {
  Bytes::from_array([b])
}

// ---------------------------------------------------------------------------
// RFC 6979 deterministic nonce generation (same as ECDSA)
// ---------------------------------------------------------------------------

fn bits2int_trunc(data : Bytes, qlen : Int) -> @bigint.BigInt {
  let blen = data.length() * 8
  let val = bytes_to_bigint_be(data)
  if blen > qlen {
    @bigint.shr(val, blen - qlen)
  } else {
    val
  }
}

fn int2octets(x : @bigint.BigInt, size : Int) -> Bytes {
  let z = match @bigint.divmod(x, dsa_q) {
    Some((_, r)) => r
    None => x
  }
  bigint_to_bytes_be(z, size)
}

fn bits2octets(data : Bytes, size : Int) -> Bytes {
  let z1 = bits2int_trunc(data, size * 8)
  let z2 = match @bigint.divmod(z1, dsa_q) {
    Some((_, r)) => r
    None => z1
  }
  int2octets(z2, size)
}

fn rfc6979_generate_k(
  x : @bigint.BigInt,
  hash : Bytes,
  size : Int,
) -> @bigint.BigInt {
  let qlen = size * 8
  let hlen = 32
  let v_init = Bytes::make(hlen, b'\x01')
  let k_init = Bytes::make(hlen, b'\x00')
  let x_bytes = int2octets(x, size)
  let h1_bytes = bits2octets(hash, size)
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
    let k_mod = match @bigint.divmod(k_candidate, dsa_q) {
      Some((_, r)) => r
      None => k_candidate
    }
    if @bigint.compare(k_mod, zero) > 0 && @bigint.compare(k_mod, dsa_q) < 0 {
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
// Key types
// ===========================================================================

///|
/// DSA secret key.
pub struct DsaSecretKey {
  /// Secret exponent x in [1, q-1]
  x : @bigint.BigInt
}

///|
/// Construct a `DsaSecretKey` from a BigInt.
pub fn DsaSecretKey::new(x : @bigint.BigInt) -> DsaSecretKey {
  let x_mod = reduce_q(x)
  if @bigint.equal(x_mod, @bigint.zero()) {
    abort("DSA: secret key must not be 0 mod q")
  }
  { x: x_mod }
}

///|
/// DSA public key.
pub struct DsaPublicKey {
  /// Public value y = g^x mod p
  y : @bigint.BigInt
}

///|
/// Construct a `DsaPublicKey` from a BigInt.
pub fn DsaPublicKey::new(y : @bigint.BigInt) -> DsaPublicKey {
  { y, }
}

///|
/// DSA signature (r, s).
pub struct DsaSignature {
  /// R component: (g^k mod p) mod q
  r : @bigint.BigInt
  /// S component: k^(-1) * (hash + x*r) mod q
  s : @bigint.BigInt
}

///|
/// Construct a `DsaSignature` from two BigInt values.
pub fn DsaSignature::new(
  r : @bigint.BigInt,
  s : @bigint.BigInt,
) -> DsaSignature {
  { r, s }
}

// ===========================================================================
// DSA operations
// ===========================================================================

///|
/// Generate a DSA key pair from a secret scalar.
pub fn dsa_keygen(secret : @bigint.BigInt) -> (DsaSecretKey, DsaPublicKey) {
  let x = reduce_q(secret)
  if @bigint.equal(x, @bigint.zero()) {
    abort("DSA: secret key must not be 0 mod q")
  }
  let y = mod_pow_p(dsa_g, x)
  (DsaSecretKey::{ x }, DsaPublicKey::{ y })
}

///|
/// Sign a message with DSA using RFC 6979 deterministic nonce.
///
/// - `sk`: secret key
/// - `message`: the message to sign (will be hashed with SHA-256)
pub fn dsa_sign(sk : DsaSecretKey, message : Bytes) -> DsaSignature {
  let hash = @sha256.sha256(message)
  let e = bytes_to_bigint_be(hash)
  // Truncate e to qlen bits
  let qlen = 256
  let elen = hash.length() * 8
  let e_trunc = if elen > qlen {
    @bigint.shr(e, elen - qlen)
  } else {
    e
  }
  // Generate deterministic k
  let k = rfc6979_generate_k(sk.x, hash, 32)
  // r = (g^k mod p) mod q
  let r = reduce_q(mod_pow_p(dsa_g, k))
  if @bigint.equal(r, @bigint.zero()) {
    abort("DSA: r must not be 0")
  }
  // s = k^(-1) * (e + x*r) mod q
  let k_inv = mod_inv_q(k)
  let xr = mod_q(sk.x, r)
  let e_xr = match @bigint.divmod(@bigint.add(e_trunc, xr), dsa_q) {
    Some((_, rem)) => rem
    None => @bigint.add(e_trunc, xr)
  }
  let s = mod_q(k_inv, e_xr)
  if @bigint.equal(s, @bigint.zero()) {
    abort("DSA: s must not be 0")
  }
  DsaSignature::{ r, s }
}

///|
/// Sign a message hash with DSA using a provided nonce k (for testing).
///
/// - `sk`: secret key
/// - `message_hash`: hash of the message (bytes, big-endian)
/// - `k`: nonce (will be reduced mod q)
pub fn dsa_sign_with_nonce(
  sk : DsaSecretKey,
  message_hash : Bytes,
  k : @bigint.BigInt,
) -> DsaSignature {
  let k_mod = reduce_q(k)
  if @bigint.equal(k_mod, @bigint.zero()) {
    abort("DSA: k must not be 0 mod q")
  }
  let e = bytes_to_bigint_be(message_hash)
  let qlen = 256
  let elen = message_hash.length() * 8
  let e_trunc = if elen > qlen {
    @bigint.shr(e, elen - qlen)
  } else {
    e
  }
  let r = reduce_q(mod_pow_p(dsa_g, k_mod))
  if @bigint.equal(r, @bigint.zero()) {
    abort("DSA: r must not be 0")
  }
  let k_inv = mod_inv_q(k_mod)
  let xr = mod_q(sk.x, r)
  let e_xr = match @bigint.divmod(@bigint.add(e_trunc, xr), dsa_q) {
    Some((_, rem)) => rem
    None => @bigint.add(e_trunc, xr)
  }
  let s = mod_q(k_inv, e_xr)
  if @bigint.equal(s, @bigint.zero()) {
    abort("DSA: s must not be 0")
  }
  DsaSignature::{ r, s }
}

///|
/// Verify a DSA signature.
///
/// - `pk`: public key
/// - `message`: the signed message (will be hashed with SHA-256)
/// - `sig`: signature (r, s)
pub fn dsa_verify(
  pk : DsaPublicKey,
  message : Bytes,
  sig : DsaSignature,
) -> Bool {
  let one = @bigint.one()
  if @bigint.compare(sig.r, one) < 0 || @bigint.compare(sig.r, dsa_q) >= 0 {
    return false
  }
  if @bigint.compare(sig.s, one) < 0 || @bigint.compare(sig.s, dsa_q) >= 0 {
    return false
  }
  let hash = @sha256.sha256(message)
  let e = bytes_to_bigint_be(hash)
  let qlen = 256
  let elen = hash.length() * 8
  let e_trunc = if elen > qlen {
    @bigint.shr(e, elen - qlen)
  } else {
    e
  }
  let w = mod_inv_q(sig.s)
  let u1 = mod_q(e_trunc, w)
  let u2 = mod_q(sig.r, w)
  let gu1 = mod_pow_p(dsa_g, u1)
  let yu2 = mod_pow_p(pk.y, u2)
  let prod = mod_p(gu1, yu2)
  let v = reduce_q(prod)
  @bigint.equal(v, sig.r)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "dsa: g^q mod p == 1" {
  // Verify that g is a generator of order q
  let result = mod_pow_p(dsa_g, dsa_q)
  assert_true(@bigint.equal(result, @bigint.one()))
}

///|
test "dsa_keygen: basic key generation" {
  let secret = parse_const("123456789", "test secret")
  let (sk, pk) = dsa_keygen(secret)
  // y = g^x mod p
  let expected_y = mod_pow_p(dsa_g, sk.x)
  assert_true(@bigint.equal(pk.y, expected_y))
}

///|
test "dsa_sign_verify: round-trip" {
  let secret = parse_const("42", "test secret")
  let (sk, pk) = dsa_keygen(secret)
  let msg = b"Hello, DSA!"
  let sig = dsa_sign(sk, msg)
  assert_true(dsa_verify(pk, msg, sig))
}

///|
test "dsa_sign_verify: wrong message rejected" {
  let secret = parse_const("42", "test secret")
  let (sk, pk) = dsa_keygen(secret)
  let sig = dsa_sign(sk, b"correct message")
  assert_false(dsa_verify(pk, b"wrong message", sig))
}

///|
test "dsa_sign_verify: wrong key rejected" {
  let secret1 = parse_const("42", "test secret 1")
  let secret2 = parse_const("99", "test secret 2")
  let (sk, _) = dsa_keygen(secret1)
  let (_, pk2) = dsa_keygen(secret2)
  let sig = dsa_sign(sk, b"message")
  assert_false(dsa_verify(pk2, b"message", sig))
}

///|
test "dsa_sign_verify: tampered signature rejected" {
  let secret = parse_const("42", "test secret")
  let (sk, pk) = dsa_keygen(secret)
  let sig = dsa_sign(sk, b"message")
  // Tamper with s
  let tampered_s = @bigint.add(sig.s, @bigint.one())
  let tampered = DsaSignature::new(sig.r, tampered_s)
  assert_false(dsa_verify(pk, b"message", tampered))
}

///|
test "dsa_sign_verify: deterministic signatures" {
  let secret = parse_const("42", "test secret")
  let (sk, _) = dsa_keygen(secret)
  let sig1 = dsa_sign(sk, b"message")
  let sig2 = dsa_sign(sk, b"message")
  // RFC 6979 deterministic nonce: same input -> same signature
  assert_true(@bigint.equal(sig1.r, sig2.r))
  assert_true(@bigint.equal(sig1.s, sig2.s))
}
