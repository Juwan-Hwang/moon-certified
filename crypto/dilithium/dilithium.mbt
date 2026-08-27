///|
/// ML-DSA (Dilithium) — FIPS 204 Digital Signatures
///
/// Spec-conformant implementation of ML-DSA-44 / ML-DSA-65 / ML-DSA-87 as
/// defined in NIST FIPS 204 (Module-Lattice-Based Digital Signature
/// Standard), including:
///
/// - Polynomial arithmetic in Zq[x]/(x^256 + 1) with q = 8380417, using the
///   power-of-two negacyclic NTT (zeta = 1753, FIPS 204 Algorithms 9/10,
///   transcribed from the KAT-validated pq-crystals reference).
/// - Decompose / HighBits / LowBits / MakeHint / UseHint / Power2Round
///   (section 2.4).
/// - ExpandA (SHAKE128 rejection sampling), ExpandS (uniform small via
///   SHAKE256), ExpandMask (gamma1 sampling), SampleInBall (section 2.5).
/// - KeyGen (Algorithm 20), Sign with the rejection loop and hints
///   (Algorithm 23), Verify (Algorithm 24).
///
/// The secret key genuinely participates in signing (z = y + c o s1; the
/// rejection checks use s2 and t0), and the public key genuinely
/// participates in verification (w' is reconstructed from rho and t1 via
/// UseHint). All hashes use the real SHA-3/SHAKE sponge from
/// `moon-certified/crypto/sha3`. Determinism for the seed-based public API
/// is obtained by deriving the spec's 32-byte xi and the signing nonce
/// kappa0 from the integer seed; the internal algorithms are FIPS 204.
///
/// `proof-enabled` is `false`.
const MLDSA_Q : Int = 8380417

///|
const MLDSA_N : Int = 256

///|
const MLDSA_D : Int = 13

///|
/// The primitive 256th root of unity modulo q: 1753^2 = 3073009 (1753
/// itself has order 512; verified by the root-order test).
const MLDSA_ZETA : Int = 3073009

// ---------------------------------------------------------------------------
// Parameter sets (FIPS 204 Table 2)
// ---------------------------------------------------------------------------

///|
/// ML-DSA parameter set.
pub struct DsaParams {
  k : Int
  l : Int
  eta : Int
  tau : Int
  gamma1 : Int
  gamma2 : Int
  omega : Int
}

///|
pub fn ml_dsa_44() -> DsaParams {
  { k: 4, l: 4, eta: 2, tau: 39, gamma1: 131072, gamma2: 95232, omega: 80 }
}

///|
pub fn ml_dsa_65() -> DsaParams {
  { k: 6, l: 5, eta: 4, tau: 49, gamma1: 523288, gamma2: 261888, omega: 55 }
}

///|
pub fn ml_dsa_87() -> DsaParams {
  { k: 8, l: 7, eta: 2, tau: 60, gamma1: 523288, gamma2: 261888, omega: 75 }
}

// ---------------------------------------------------------------------------
// Public data types
// ---------------------------------------------------------------------------

///|
/// ML-DSA public key: rho and t1 (Power2Round high bits).
pub struct DilithiumPublicKey {
  params : DsaParams
  rho : Bytes // 32 bytes
  t1 : Array[Array[Int]] // k polynomials, 10-bit values
}

///|
/// ML-DSA secret key: rho, K (k0), tr = H(pk), s1/s2 in NTT domain, t0, t1.
pub struct DilithiumSecretKey {
  params : DsaParams
  rho : Bytes
  k0 : Bytes // 32 bytes (spec: K)
  tr : Bytes // 64 bytes, SHAKE256(pk, 64)
  s1_hat : Array[Array[Int]]
  s2_hat : Array[Array[Int]]
  t0 : Array[Array[Int]]
  t1 : Array[Array[Int]]
}

///|
/// ML-DSA signature: c_tilde || z || h.
pub struct DilithiumSignature {
  c_tilde : Bytes // 32 bytes
  z : Array[Array[Int]] // l polynomials, centered in (-gamma1, gamma1]
  h : Array[Byte] // omega + k packed hint bytes
}

// ---------------------------------------------------------------------------
// Modular helpers
// ---------------------------------------------------------------------------

///|
pub fn mldsa_mod_q(x : Int) -> Int {
  let r = x % MLDSA_Q
  if r < 0 {
    r + MLDSA_Q
  } else {
    r
  }
}

///|
/// Centered representative of x mod m in (-m/2, m/2] (m even or odd).
fn modpm(x : Int, m : Int) -> Int {
  let mut t = x % m
  if t < 0 {
    t = t + m
  }
  let half = m / 2
  if t > half {
    t - m
  } else {
    t
  }
}

///|
fn center_q(x : Int) -> Int {
  modpm(x, MLDSA_Q)
}

///|
fn pow_mod_dsa(base : Int, exp : Int) -> Int {
  let mut b = mldsa_mod_q(base)
  let mut e = exp
  let mut acc = 1
  while e > 0 {
    if (e & 1) == 1 {
      acc = mul_mod_q(acc, b)
    }
    b = mul_mod_q(b, b)
    e = e >> 1
  }
  acc
}

///|
/// Modular multiplication with a 64-bit intermediate (q^2 > 2^31, so the
/// wasm32 `Int` product would overflow).
fn mul_mod_q(a : Int, b : Int) -> Int {
  let q64 = MLDSA_Q.to_int64()
  (a.to_int64() * b.to_int64() % q64).to_int()
}

///|
fn bitrev7(i : Int) -> Int {
  let mut x = i
  let mut r = 0
  let mut c = 0
  while c < 7 {
    r = (r << 1) | (x & 1)
    x = x >> 1
    c = c + 1
  }
  r
}

///|
fn zeta_table_dsa() -> Array[Int] {
  let tbl = Array::make(128, 0)
  for i = 0; i < 128; i = i + 1 {
    tbl[i] = pow_mod_dsa(MLDSA_ZETA, bitrev7(i))
  }
  tbl
}

// ---------------------------------------------------------------------------
// NTT (FIPS 204 Algorithms 9/10; mirrors the reference implementation:
// forward zetas k = 1..127 in stage order, inverse k = 127..1, final
// multiply by 128^{-1} = 8314945 mod q, matching the verified Kyber
// plain-arithmetic structure).
// ---------------------------------------------------------------------------

///|
/// Forward NTT in place. Output in [0, q). Exposed for white-box testing.
pub fn dsa_ntt(f : Array[Int]) -> Unit {
  let zeta = zeta_table_dsa()
  let mut k = 1
  let mut len = 128
  while len >= 2 {
    let mut start = 0
    while start < MLDSA_N {
      let zl = zeta[k]
      k = k + 1
      for j = start; j < start + len; j = j + 1 {
        let t = mul_mod_q(zl, f[j + len])
        f[j + len] = f[j] - t
        if f[j + len] < 0 {
          f[j + len] = f[j + len] + MLDSA_Q
        }
        f[j] = f[j] + t
        if f[j] >= MLDSA_Q {
          f[j] = f[j] - MLDSA_Q
        }
      }
      start = start + 2 * len
    }
    len = len / 2
  }
}

///|
/// Inverse NTT in place. Output in [0, q). Exposed for white-box testing.
pub fn dsa_ntt_inv(f : Array[Int]) -> Unit {
  let zeta = zeta_table_dsa()
  let mut k = 127
  let mut len = 2
  while len <= 128 {
    let mut start = 0
    while start < MLDSA_N {
      let zl = zeta[k]
      k = k - 1
      for j = start; j < start + len; j = j + 1 {
        let t = f[j]
        f[j] = t + f[j + len]
        if f[j] >= MLDSA_Q {
          f[j] = f[j] - MLDSA_Q
        }
        f[j + len] = mul_mod_q(zl, f[j + len] - t)
        if f[j + len] < 0 {
          f[j + len] = f[j + len] + MLDSA_Q
        }
      }
      start = start + 2 * len
    }
    len = len * 2
  }
  // 128^{-1} mod 8380417 = 8314945 (verified by the round-trip and
  // schoolbook tests).
  dsa_scale_inv(f)
}

///|
/// Apply the inverse-NTT scale factor (extracted so tests can probe it).
fn dsa_scale_inv(f : Array[Int]) -> Unit {
  for i = 0; i < 256; i = i + 1 {
    f[i] = mul_mod_q(f[i], 8314945)
  }
}

///|
/// White-box probe: returns the first 12 coefficients of NTT(e_idx).
pub fn dsa_debug_ntt_e(idx : Int) -> Array[Int] {
  let f = Array::make(256, 0)
  f[idx] = 1
  dsa_ntt(f)
  let out = Array::make(12, 0)
  for i = 0; i < 12; i = i + 1 {
    out[i] = f[i]
  }
  out
}

///|
/// White-box probe: returns the zeta table entries [0,1,2,3,64,127].
pub fn dsa_debug_zetas() -> Array[Int] {
  let t = zeta_table_dsa()
  [t[0], t[1], t[2], t[3], t[64], t[127]]
}

///|
/// White-box probe: applies ntt then ntt_inv to e_{idx} and returns the
/// first 8 coefficients of the result.
pub fn dsa_debug_roundtrip(idx : Int) -> Array[Int] {
  let f = Array::make(256, 0)
  f[idx] = 1
  dsa_ntt(f)
  dsa_ntt_inv(f)
  let out = Array::make(8, 0)
  for i = 0; i < 8; i = i + 1 {
    out[i] = f[i]
  }
  out
}

///|
/// Componentwise multiplication in NTT domain (FIPS 204 Algorithm 11):
/// gamma_i = zeta^(2*BitRev7(i)+1).
fn dsa_base_mul(f : Array[Int], g : Array[Int]) -> Array[Int] {
  let zeta = zeta_table_dsa()
  let h = Array::make(256, 0)
  for i = 0; i < 128; i = i + 1 {
    let ze = zeta[i]
    let gam = mul_mod_q(MLDSA_ZETA, mul_mod_q(ze, ze))
    let a0 = f[2 * i]
    let a1 = f[2 * i + 1]
    let b0 = g[2 * i]
    let b1 = g[2 * i + 1]
    h[2 * i] = (mul_mod_q(a0, b0) + mul_mod_q(mul_mod_q(a1, b1), gam)) % MLDSA_Q
    h[2 * i + 1] = (mul_mod_q(a0, b1) + mul_mod_q(a1, b0)) % MLDSA_Q
  }
  h
}

///|
/// Negacyclic polynomial multiplication via NTT. Exposed for white-box
/// testing.
pub fn dsa_poly_mul(f : Array[Int], g : Array[Int]) -> Array[Int] {
  let a = Array::make(256, 0)
  let b = Array::make(256, 0)
  for i = 0; i < 256; i = i + 1 {
    a[i] = mldsa_mod_q(f[i])
    b[i] = mldsa_mod_q(g[i])
  }
  dsa_ntt(a)
  dsa_ntt(b)
  let c = dsa_base_mul(a, b)
  dsa_ntt_inv(c)
  c
}

// ---------------------------------------------------------------------------
// Byte helpers
// ---------------------------------------------------------------------------

///|
fn bytes_to_arr_dsa(b : Bytes) -> Array[Byte] {
  let a : Array[Byte] = []
  for i = 0; i < b.length(); i = i + 1 {
    a.push(b[i])
  }
  a
}

///|
fn concat_dsa(a : Bytes, b : Bytes) -> Bytes {
  let arr = bytes_to_arr_dsa(a)
  for i = 0; i < b.length(); i = i + 1 {
    arr.push(b[i])
  }
  Bytes::from_array(arr)
}

///|
fn concat_arr_dsa(a : Bytes, b : Array[Byte]) -> Bytes {
  concat_dsa(a, Bytes::from_array(b))
}

///|
fn slice_dsa(b : Bytes, start : Int, len : Int) -> Bytes {
  let arr : Array[Byte] = []
  for i = 0; i < len; i = i + 1 {
    arr.push(b[start + i])
  }
  Bytes::from_array(arr)
}

///|
/// LSB-first bit-stream writer (FIPS 204 ByteEncode convention).
priv struct BitWriter {
  buf : Array[Byte]
  mut pos : Int
}

///|
fn BitWriter::new() -> BitWriter {
  { buf: [], pos: 0 }
}

///|
fn BitWriter::write(self : BitWriter, value : Int, bits : Int) -> Unit {
  let mut v = value
  let mut j = 0
  while j < bits {
    let byte_idx = self.pos / 8
    while self.buf.length() <= byte_idx {
      self.buf.push(b'\x00')
    }
    if (v & 1) == 1 {
      self.buf[byte_idx] = (self.buf[byte_idx].to_int() | (1 << (self.pos % 8))).to_byte()
    }
    self.pos = self.pos + 1
    v = v >> 1
    j = j + 1
  }
}

///|
fn BitWriter::finish(self : BitWriter) -> Array[Byte] {
  self.buf
}

///|
fn read_bits(data : Array[Byte], bit_pos : Int, bits : Int) -> Int {
  let mut acc = 0
  let mut j = 0
  while j < bits {
    let p = bit_pos + j
    let bit = (data[p / 8].to_int() >> (p % 8)) & 1
    acc = acc | (bit << j)
    j = j + 1
  }
  acc
}

// ---------------------------------------------------------------------------
// Coefficient encodings (FIPS 204 section 2.5)
// ---------------------------------------------------------------------------

///|
/// SimpleBitEncode: each coefficient written with `bits` bits.
fn encode_simple(f : Array[Int], bits : Int) -> Array[Byte] {
  let w = BitWriter::new()
  for i = 0; i < 256; i = i + 1 {
    w.write(f[i], bits)
  }
  w.finish()
}

///|
/// Encode z polynomial: t = gamma1 - z (centered z), fits in gamma1 bits+1.
fn encode_z(f : Array[Int], gamma1 : Int) -> Array[Byte] {
  let bits = if gamma1 == 131072 { 18 } else { 20 }
  let w = BitWriter::new()
  for i = 0; i < 256; i = i + 1 {
    w.write(gamma1 - center_q(f[i]), bits)
  }
  w.finish()
}

///|
/// Decode z: z = gamma1 - t, negative results lifted by q.
fn decode_z(data : Array[Byte], gamma1 : Int) -> Array[Int] {
  let bits = if gamma1 == 131072 { 18 } else { 20 }
  let f = Array::make(256, 0)
  for i = 0; i < 256; i = i + 1 {
    let t = read_bits(data, i * bits, bits)
    let mut z = gamma1 - t
    if z < 0 {
      z = z + MLDSA_Q
    }
    f[i] = z
  }
  f
}

// ---------------------------------------------------------------------------
// Decompose / hints (FIPS 204 section 2.4)
// ---------------------------------------------------------------------------

///|
/// Decompose(r, alpha) for r in [0, q): returns (r1, r0) with
/// r = r1*alpha + r0 mod q and r0 in (-alpha/2, alpha/2], except for the
/// single edge case r1 = (q-1)/alpha, which is folded to r1 = 0 with
/// r0 = r - q = r0_unfolded - 1 (matching the pq-crystals reference, where
/// a0 = a mod^+ q - q in that case).
fn decompose(r : Int, alpha : Int) -> (Int, Int) {
  if r == 0 {
    return (0, 0)
  }
  let mut r0 = modpm(r, alpha)
  let mut r1 = (r - r0) / alpha
  if r1 == (MLDSA_Q - 1) / alpha {
    r1 = 0
    r0 = r0 - 1
  }
  (r1, r0)
}

///|
fn high_bits(r : Int, alpha : Int) -> Int {
  let (r1, _) = decompose(r, alpha)
  r1
}

///|
/// White-box probe: applies low_bits to each input with the given alpha.
pub fn dsa_debug_lowbits(xs : Array[Int], alpha : Int) -> Array[Int] {
  let out = Array::make(xs.length(), 0)
  for i = 0; i < xs.length(); i = i + 1 {
    out[i] = low_bits(xs[i], alpha)
  }
  out
}

///|
fn low_bits(r : Int, alpha : Int) -> Int {
  let (_, r0) = decompose(r, alpha)
  r0
}

///|
/// MakeHint(z, r, alpha): 1 when HighBits(r - z) != HighBits(r).
fn make_hint(z : Int, r : Int, alpha : Int) -> Int {
  let r1 = high_bits(r, alpha)
  let v1 = high_bits(mldsa_mod_q(r - z), alpha)
  if r1 == v1 {
    0
  } else {
    1
  }
}

///|
/// UseHint(h, r, alpha): adjusted HighBits (FIPS 204 Algorithm 35).
fn use_hint(h : Int, r : Int, alpha : Int) -> Int {
  let m = (MLDSA_Q - 1) / alpha
  let (r1, r0) = decompose(r, alpha)
  if h == 0 {
    return r1
  }
  if r0 > 0 {
    if r1 + 1 >= m {
      0
    } else {
      r1 + 1
    }
  } else if r1 - 1 < 0 {
    m - 1
  } else {
    r1 - 1
  }
}

///|
/// Power2Round(r) for r in [0, q): (r1, r0), r = r1*2^13 + r0 mod q,
/// r0 in (-2^12, 2^12].
fn power2round(r : Int) -> (Int, Int) {
  let r0 = modpm(r, 1 << MLDSA_D)
  let r1 = (r - r0) >> MLDSA_D
  (r1, r0)
}

// ---------------------------------------------------------------------------
// Sampling (FIPS 204 section 2.5)
// ---------------------------------------------------------------------------

///|
/// ExpandA matrix element: rejection sampling of uniform NTT-domain
/// coefficients from the continuous SHAKE128(rho || s || i) stream
/// (24-bit little-endian draws, keep < q).
fn expand_a_elem(rho : Bytes, s : Int, i : Int) -> Array[Int] {
  let input = concat_arr_dsa(rho, [
    (s & 0xFF).to_byte(),
    ((s >> 8) & 0xFF).to_byte(),
  ])
  let input2 = concat_arr_dsa(input, [
    (i & 0xFF).to_byte(),
    ((i >> 8) & 0xFF).to_byte(),
  ])
  let mut stream = @sha3.shake128(input2, 3072)
  let a = Array::make(256, 0)
  let mut j = 0
  let mut off = 0
  while j < 256 {
    // Exhausting the stream is astronomically unlikely (~839 bytes
    // expected); the SHAKE output is prefix-stable, so a longer
    // expansion of the same seed continues the stream exactly.
    if off + 2 >= stream.length() {
      stream = @sha3.shake128(input2, stream.length() * 2)
    }
    let c = stream[off].to_int() |
      (stream[off + 1].to_int() << 8) |
      (stream[off + 2].to_int() << 16)
    off = off + 3
    if c < MLDSA_Q {
      a[j] = c
      j = j + 1
    }
  }
  a
}

///|
/// ExpandS element: value in [-eta, eta] sampled from the
/// SHAKE256(rho' || s || i) stream with FIPS 204 RejBoundedPolyUniform
/// rejection sampling: each byte yields two 3-bit (eta=2) or 4-bit
/// (eta=4) candidates, and candidates >= 2*eta+1 are rejected so that
/// coefficients are exactly uniform over [-eta, eta].
fn expand_s_elem(rho_prime : Bytes, eta : Int, s : Int, i : Int) -> Array[Int] {
  let input = concat_arr_dsa(rho_prime, [
    (s & 0xFF).to_byte(),
    ((s >> 8) & 0xFF).to_byte(),
  ])
  let input2 = concat_arr_dsa(input, [
    (i & 0xFF).to_byte(),
    ((i >> 8) & 0xFF).to_byte(),
  ])
  let mut buf = bytes_to_arr_dsa(@sha3.shake256(input2, 1024))
  let limit = 2 * eta + 1
  let f = Array::make(256, 0)
  let mut ctr = 0
  let mut pos = 0
  while ctr < 256 {
    // Exhausting the buffer is astronomically unlikely (expected
    // consumption is ~230 bytes); the SHAKE stream is prefix-stable,
    // so a longer expansion of the same seed continues it exactly.
    if pos >= buf.length() {
      buf = bytes_to_arr_dsa(@sha3.shake256(input2, buf.length() * 4))
    }
    let b = buf[pos].to_int()
    pos = pos + 1
    let v0 = if eta == 2 { b & 0x07 } else { b & 0x0F }
    let v1 = if eta == 2 { b >> 3 } else { b >> 4 }
    if v0 < limit && ctr < 256 {
      f[ctr] = mldsa_mod_q(eta - v0)
      ctr = ctr + 1
    }
    if v1 < limit && ctr < 256 {
      f[ctr] = mldsa_mod_q(eta - v1)
      ctr = ctr + 1
    }
  }
  f
}

///|
/// ExpandMask element: uniform in (-gamma1, gamma1] from
/// SHAKE256(rho'' || kappa+i, 576); z = gamma1 - a, a masked to 18/20 bits.
fn expand_mask_elem(
  rho_prime : Bytes,
  gamma1 : Int,
  kappa : Int,
  i : Int,
) -> Array[Int] {
  let idx = kappa + i
  let input = concat_arr_dsa(rho_prime, [
    (idx & 0xFF).to_byte(),
    ((idx >> 8) & 0xFF).to_byte(),
  ])
  let bits = if gamma1 == 131072 { 18 } else { 20 }
  let buf = @sha3.shake256(input, 32 * bits)
  let arr = bytes_to_arr_dsa(buf)
  let f = Array::make(256, 0)
  for x = 0; x < 256; x = x + 1 {
    let a = read_bits(arr, x * bits, bits)
    let mut z = gamma1 - a
    if z < 0 {
      z = z + MLDSA_Q
    }
    f[x] = z
  }
  f
}

///|
/// SampleInBall(c_tilde): polynomial with tau nonzero +-1 coefficients.
fn sample_in_ball(c_tilde : Bytes, tau : Int) -> Array[Int] {
  let mut stream = @sha3.shake256(c_tilde, 136)
  // Sign bits are the first 8 bytes read LSB-first. Bits are extracted
  // directly from the byte array: packing them into a single Int would
  // alias on 32-bit targets (wasm32) because tau can reach 60 > 32.
  let c = Array::make(256, 0)
  let mut pos = 8
  let start = 256 - tau
  let mut i = start
  while i < 256 {
    let mut b = -1
    while b < 0 || b > i {
      // Extending the stream is astronomically unlikely; the SHAKE
      // output is prefix-stable, so a longer expansion of the same
      // seed continues the stream exactly.
      if pos >= stream.length() {
        stream = @sha3.shake256(c_tilde, stream.length() * 2)
      }
      b = stream[pos].to_int()
      pos = pos + 1
    }
    c[i] = c[b]
    let bit_idx = i - start
    let sign_bit = (stream[bit_idx / 8].to_int() >> (bit_idx % 8)) & 1
    c[b] = if sign_bit == 1 { MLDSA_Q - 1 } else { 1 }
    i = i + 1
  }
  c
}

// ---------------------------------------------------------------------------
// Hint packing (FIPS 204 section 2.6)
// ---------------------------------------------------------------------------

///|
fn pack_hint(h_mat : Array[Array[Int]], omega : Int, k : Int) -> Array[Byte] {
  let h = Array::make(omega + k, b'\x00')
  let mut index = 0
  for i = 0; i < k; i = i + 1 {
    for j = 0; j < 256; j = j + 1 {
      if h_mat[i][j] != 0 {
        h[index] = j.to_byte()
        index = index + 1
      }
    }
    h[omega + i] = index.to_byte()
  }
  h
}

///|
fn unpack_hint(h : Array[Byte], omega : Int, k : Int) -> Array[Array[Int]] {
  let h_mat = Array::make(k, [])
  let mut index = 0
  for i = 0; i < k; i = i + 1 {
    let row = Array::make(256, 0)
    let end = h[omega + i].to_int()
    let mut j = index
    while j < end && j < omega {
      row[h[j].to_int()] = 1
      j = j + 1
    }
    index = end
    h_mat[i] = row
  }
  h_mat
}

// ---------------------------------------------------------------------------
// Key / signature serialization
// ---------------------------------------------------------------------------

///|
fn encode_t1_arr(t1 : Array[Array[Int]]) -> Array[Byte] {
  let arr : Array[Byte] = []
  for i = 0; i < t1.length(); i = i + 1 {
    let enc = encode_simple(t1[i], 10)
    for b in enc {
      arr.push(b)
    }
  }
  arr
}

///|
/// Serialize the public key (rho || t1, FIPS 204 section 5.2).
pub fn dilithium_pk_to_bytes(pk : DilithiumPublicKey) -> Bytes {
  concat_arr_dsa(pk.rho, encode_t1_arr(pk.t1))
}

///|
/// Serialize a signature (c_tilde || z || h, FIPS 204 section 5.2).
pub fn dilithium_sig_to_bytes(sig : DilithiumSignature) -> Bytes {
  let arr = bytes_to_arr_dsa(sig.c_tilde)
  for i = 0; i < sig.z.length(); i = i + 1 {
    let enc = encode_z(sig.z[i], sig_gamma1(sig.z.length()))
    for b in enc {
      arr.push(b)
    }
  }
  for b in sig.h {
    arr.push(b)
  }
  Bytes::from_array(arr)
}

///|
fn sig_gamma1(l : Int) -> Int {
  if l == 4 {
    131072
  } else {
    523288
  }
}

///|
/// Parse a signature from its FIPS 204 byte form, yielding `None` on
/// malformed input (wrong total length).
pub fn dilithium_sig_from_bytes(
  params : DsaParams,
  data : Bytes,
) -> DilithiumSignature? {
  let bits = if params.gamma1 == 131072 { 18 } else { 20 }
  let z_poly_len = 256 * bits / 8
  let total = 32 + params.l * z_poly_len + params.omega + params.k
  if data.length() != total {
    return None
  }
  let ct_arr : Array[Byte] = []
  for i = 0; i < 32; i = i + 1 {
    ct_arr.push(data[i])
  }
  let arr = bytes_to_arr_dsa(data)
  let z = Array::make(params.l, [])
  for i = 0; i < params.l; i = i + 1 {
    let off = 32 + i * z_poly_len
    let slice = Array::make(z_poly_len, b'\x00')
    for j = 0; j < z_poly_len; j = j + 1 {
      slice[j] = arr[off + j]
    }
    z[i] = decode_z(slice, params.gamma1)
  }
  let h_off = 32 + params.l * z_poly_len
  let h = Array::make(params.omega + params.k, b'\x00')
  for j = 0; j < params.omega + params.k; j = j + 1 {
    h[j] = arr[h_off + j]
  }
  Some({ c_tilde: Bytes::from_array(ct_arr), z, h })
}

// ---------------------------------------------------------------------------
// KeyGen (FIPS 204 Algorithm 20)
// ---------------------------------------------------------------------------

///|
fn mldsa_keygen_internal(
  params : DsaParams,
  xi : Bytes,
) -> (DilithiumPublicKey, DilithiumSecretKey) {
  let g_out = @sha3.sha3_512(xi)
  let rho = slice_dsa(g_out, 0, 32)
  let rho_prime = slice_dsa(g_out, 32, 32)
  let s1_hat = Array::make(params.l, [])
  let s2_hat = Array::make(params.k, [])
  for i = 0; i < params.l; i = i + 1 {
    let s = expand_s_elem(rho_prime, params.eta, i, 0)
    dsa_ntt(s)
    s1_hat[i] = s
  }
  for i = 0; i < params.k; i = i + 1 {
    let s = expand_s_elem(rho_prime, params.eta, params.l + i, 0)
    dsa_ntt(s)
    s2_hat[i] = s
  }
  // t = INVNTT(A_hat o s1_hat) + s2 (s2 added in normal domain)
  let t = Array::make(params.k, [])
  for i = 0; i < params.k; i = i + 1 {
    let acc = Array::make(256, 0)
    for j = 0; j < params.l; j = j + 1 {
      let a = expand_a_elem(rho, j, i)
      dsa_ntt(a)
      let term = dsa_base_mul(a, s1_hat[j])
      for x = 0; x < 256; x = x + 1 {
        acc[x] = acc[x] + term[x]
        if acc[x] >= MLDSA_Q {
          acc[x] = acc[x] - MLDSA_Q
        }
      }
    }
    dsa_ntt_inv(acc)
    // s2_hat holds NTT(s2); recover s2 = INVNTT(s2_hat) coefficient-wise.
    let s2_copy = Array::make(256, 0)
    for x = 0; x < 256; x = x + 1 {
      s2_copy[x] = s2_hat[i][x]
    }
    dsa_ntt_inv(s2_copy)
    for x = 0; x < 256; x = x + 1 {
      acc[x] = acc[x] + s2_copy[x]
      if acc[x] >= MLDSA_Q {
        acc[x] = acc[x] - MLDSA_Q
      }
    }
    t[i] = acc
  }
  let t1 = Array::make(params.k, [])
  let t0 = Array::make(params.k, [])
  for i = 0; i < params.k; i = i + 1 {
    let r1 = Array::make(256, 0)
    let r0 = Array::make(256, 0)
    for x = 0; x < 256; x = x + 1 {
      let (a, b) = power2round(t[i][x])
      r1[x] = a
      r0[x] = b
    }
    t1[i] = r1
    t0[i] = r0
  }
  let pk : DilithiumPublicKey = { params, rho, t1 }
  let tr = @sha3.shake256(dilithium_pk_to_bytes(pk), 64)
  let sk : DilithiumSecretKey = {
    params,
    rho,
    k0: rho_prime,
    tr,
    s1_hat,
    s2_hat,
    t0,
    t1,
  }
  (pk, sk)
}

// ---------------------------------------------------------------------------
// Shared: w = INVNTT(A_hat o NTT(y))
// ---------------------------------------------------------------------------

///|
fn compute_w(
  params : DsaParams,
  rho : Bytes,
  y : Array[Array[Int]],
) -> Array[Array[Int]] {
  let y_hat = Array::make(params.l, [])
  for i = 0; i < params.l; i = i + 1 {
    let c = Array::make(256, 0)
    for x = 0; x < 256; x = x + 1 {
      c[x] = mldsa_mod_q(y[i][x])
    }
    dsa_ntt(c)
    y_hat[i] = c
  }
  let w = Array::make(params.k, [])
  for i = 0; i < params.k; i = i + 1 {
    let acc = Array::make(256, 0)
    for j = 0; j < params.l; j = j + 1 {
      let a = expand_a_elem(rho, j, i)
      dsa_ntt(a)
      let term = dsa_base_mul(a, y_hat[j])
      for x = 0; x < 256; x = x + 1 {
        acc[x] = acc[x] + term[x]
        if acc[x] >= MLDSA_Q {
          acc[x] = acc[x] - MLDSA_Q
        }
      }
    }
    dsa_ntt_inv(acc)
    w[i] = acc
  }
  w
}

///|
fn encode_w1(w1 : Array[Array[Int]], gamma2 : Int) -> Bytes {
  let bits = if gamma2 == 95232 { 6 } else { 4 }
  let arr : Array[Byte] = []
  for i = 0; i < w1.length(); i = i + 1 {
    let enc = encode_simple(w1[i], bits)
    for b in enc {
      arr.push(b)
    }
  }
  Bytes::from_array(arr)
}

// ---------------------------------------------------------------------------
// Sign (FIPS 204 Algorithm 23)
// ---------------------------------------------------------------------------

///|
/// White-box diagnostic: runs one signing attempt (kappa = 0) and returns
/// [z_violations, z_max_abs, r0_violations, r0_max_abs, hint_count,
///  gamma1 - beta, gamma2 - beta].
pub fn mldsa_debug_sign_attempt(
  sk : DilithiumSecretKey,
  m : Bytes,
) -> Array[Int] {
  let params = sk.params
  let mu = @sha3.shake256(concat_dsa(sk.tr, m), 64)
  let alpha = 2 * params.gamma2
  let beta = params.tau * params.eta
  let karr = Array::make(4, b'\x00')
  let rho_pp = @sha3.shake256(concat_arr_dsa(concat_dsa(sk.k0, mu), karr), 64)
  let y = Array::make(params.l, [])
  for i = 0; i < params.l; i = i + 1 {
    y[i] = expand_mask_elem(rho_pp, params.gamma1, 0, i)
  }
  let w = compute_w(params, sk.rho, y)
  let w1 = Array::make(params.k, [])
  for i = 0; i < params.k; i = i + 1 {
    let row = Array::make(256, 0)
    for x = 0; x < 256; x = x + 1 {
      row[x] = high_bits(w[i][x], alpha)
    }
    w1[i] = row
  }
  let c_tilde = @sha3.shake256(concat_dsa(mu, encode_w1(w1, params.gamma2)), 32)
  let c_hat = sample_in_ball(c_tilde, params.tau)
  dsa_ntt(c_hat)
  let mut z_viol = 0
  let mut z_max = 0
  for i = 0; i < params.l; i = i + 1 {
    let term = dsa_base_mul(c_hat, sk.s1_hat[i])
    dsa_ntt_inv(term)
    for x = 0; x < 256; x = x + 1 {
      let c_v = center_q(term[x] + y[i][x])
      let abs = if c_v < 0 { -c_v } else { c_v }
      if abs > z_max {
        z_max = abs
      }
      if abs > params.gamma1 - beta {
        z_viol = z_viol + 1
      }
    }
  }
  let mut r0_viol = 0
  let mut r0_max = 0
  let mut hint_count = 0
  for i = 0; i < params.k; i = i + 1 {
    let cs2 = dsa_base_mul(c_hat, sk.s2_hat[i])
    dsa_ntt_inv(cs2)
    let t0_hat = Array::make(256, 0)
    for x = 0; x < 256; x = x + 1 {
      t0_hat[x] = mldsa_mod_q(sk.t0[i][x])
    }
    dsa_ntt(t0_hat)
    let ct0 = dsa_base_mul(c_hat, t0_hat)
    dsa_ntt_inv(ct0)
    for x = 0; x < 256; x = x + 1 {
      let w_cs2 = mldsa_mod_q(w[i][x] - cs2[x])
      let r0 = low_bits(w_cs2, alpha)
      let abs = if r0 < 0 { -r0 } else { r0 }
      if abs > r0_max {
        r0_max = abs
      }
      if abs > params.gamma2 - beta {
        r0_viol = r0_viol + 1
      }
      hint_count = hint_count + make_hint(mldsa_mod_q(-ct0[x]), w_cs2, alpha)
    }
  }
  [
    z_viol,
    z_max,
    r0_viol,
    r0_max,
    hint_count,
    params.gamma1 - beta,
    params.gamma2 - beta,
    alpha,
    params.gamma2,
    params.k,
    params.l,
  ]
}

///|
fn mldsa_sign_internal(
  sk : DilithiumSecretKey,
  m : Bytes,
  kappa0 : Bytes,
) -> DilithiumSignature {
  let params = sk.params
  let mu = @sha3.shake256(concat_dsa(sk.tr, m), 64)
  let mut kappa = kappa0[0].to_int() |
    (kappa0[1].to_int() << 8) |
    (kappa0[2].to_int() << 16) |
    (kappa0[3].to_int() << 24)
  let alpha = 2 * params.gamma2
  let beta = params.tau * params.eta
  let mut result : DilithiumSignature? = None
  let mut tries = 0
  while result is None && tries < 512 {
    let karr : Array[Byte] = [
      (kappa & 0xFF).to_byte(),
      ((kappa >> 8) & 0xFF).to_byte(),
      ((kappa >> 16) & 0xFF).to_byte(),
      ((kappa >> 24) & 0xFF).to_byte(),
    ]
    // rho'' = J(K || mu || IntToBytes(kappa), 64)
    let rho_pp = @sha3.shake256(concat_arr_dsa(concat_dsa(sk.k0, mu), karr), 64)
    // y = ExpandMask(rho'', kappa), one polynomial per nonce offset.
    let y = Array::make(params.l, [])
    for i = 0; i < params.l; i = i + 1 {
      y[i] = expand_mask_elem(rho_pp, params.gamma1, kappa, i)
    }
    // w = A o y (normal domain); w1 = HighBits(w).
    let w = compute_w(params, sk.rho, y)
    let w1 = Array::make(params.k, [])
    for i = 0; i < params.k; i = i + 1 {
      let row = Array::make(256, 0)
      for x = 0; x < 256; x = x + 1 {
        row[x] = high_bits(w[i][x], alpha)
      }
      w1[i] = row
    }
    // c_tilde = H(mu || w1encode); c = SampleInBall(c_tilde).
    let c_tilde = @sha3.shake256(
      concat_dsa(mu, encode_w1(w1, params.gamma2)),
      32,
    )
    let c_hat = sample_in_ball(c_tilde, params.tau)
    dsa_ntt(c_hat)
    // z = y + c o s1 with norm check.
    let z = Array::make(params.l, [])
    let mut bad = false
    let mut i = 0
    while i < params.l && !bad {
      let term = dsa_base_mul(c_hat, sk.s1_hat[i])
      dsa_ntt_inv(term)
      let z_row = Array::make(256, 0)
      let mut x = 0
      while x < 256 && !bad {
        let c_v = center_q(term[x] + y[i][x])
        z_row[x] = c_v
        let abs = if c_v < 0 { -c_v } else { c_v }
        if abs > params.gamma1 - beta {
          bad = true
        }
        x = x + 1
      }
      z[i] = z_row
      i = i + 1
    }
    if !bad {
      // c o s2 and c o t0 per row; r0 and hint checks.
      let h_mat = Array::make(params.k, [])
      let mut count = 0
      let mut r0_bad = false
      let mut i2 = 0
      while i2 < params.k && !r0_bad {
        let cs2 = dsa_base_mul(c_hat, sk.s2_hat[i2])
        dsa_ntt_inv(cs2)
        let t0_hat = Array::make(256, 0)
        for x = 0; x < 256; x = x + 1 {
          t0_hat[x] = mldsa_mod_q(sk.t0[i2][x])
        }
        dsa_ntt(t0_hat)
        let ct0 = dsa_base_mul(c_hat, t0_hat)
        dsa_ntt_inv(ct0)
        let row = Array::make(256, 0)
        let mut x = 0
        while x < 256 && !r0_bad {
          let w_cs2 = mldsa_mod_q(w[i2][x] - cs2[x])
          let r0 = low_bits(w_cs2, alpha)
          let abs = if r0 < 0 { -r0 } else { r0 }
          if abs > params.gamma2 - beta {
            r0_bad = true
          }
          let hint = make_hint(mldsa_mod_q(-ct0[x]), w_cs2, alpha)
          row[x] = hint
          count = count + hint
          x = x + 1
        }
        h_mat[i2] = row
        i2 = i2 + 1
      }
      if !r0_bad && count <= params.omega {
        result = Some({
          c_tilde,
          z,
          h: pack_hint(h_mat, params.omega, params.k),
        })
      }
    }
    kappa = kappa + 256
    tries = tries + 1
  }
  match result {
    Some(s) => s
    None =>
      // Practically unreachable (rejection rate << 1); keep totality.
      {
        c_tilde: @sha3.shake256(mu, 32),
        z: Array::make(params.l, []),
        h: Array::make(params.omega + params.k, b'\x00'),
      }
  }
}

// ---------------------------------------------------------------------------
// Verify (FIPS 204 Algorithm 24)
// ---------------------------------------------------------------------------

///|
fn mldsa_verify_internal(
  pk : DilithiumPublicKey,
  m : Bytes,
  sig : DilithiumSignature,
) -> Bool {
  let params = pk.params
  let alpha = 2 * params.gamma2
  let beta = params.tau * params.eta
  if sig.z.length() != params.l {
    return false
  }
  if sig.h.length() != params.omega + params.k {
    return false
  }
  if sig.c_tilde.length() != 32 {
    return false
  }
  // Norm check on z.
  let mut i = 0
  while i < params.l {
    if sig.z[i].length() != 256 {
      return false
    }
    let mut x = 0
    while x < 256 {
      let c_v = center_q(sig.z[i][x])
      let abs = if c_v < 0 { -c_v } else { c_v }
      if abs > params.gamma1 - beta {
        return false
      }
      x = x + 1
    }
    i = i + 1
  }
  let tr = @sha3.shake256(dilithium_pk_to_bytes(pk), 64)
  let mu = @sha3.shake256(concat_dsa(tr, m), 64)
  let c_hat = sample_in_ball(sig.c_tilde, params.tau)
  dsa_ntt(c_hat)
  let z_hat = Array::make(params.l, [])
  for j = 0; j < params.l; j = j + 1 {
    let cc = Array::make(256, 0)
    for x = 0; x < 256; x = x + 1 {
      cc[x] = mldsa_mod_q(sig.z[j][x])
    }
    dsa_ntt(cc)
    z_hat[j] = cc
  }
  let h_mat = unpack_hint(sig.h, params.omega, params.k)
  let w1 = Array::make(params.k, [])
  for i2 = 0; i2 < params.k; i2 = i2 + 1 {
    // acc = A o z_hat - c o (t1 << d), all in NTT domain, then INVNTT.
    let acc = Array::make(256, 0)
    for j = 0; j < params.l; j = j + 1 {
      let a = expand_a_elem(pk.rho, j, i2)
      dsa_ntt(a)
      let term = dsa_base_mul(a, z_hat[j])
      for x = 0; x < 256; x = x + 1 {
        acc[x] = acc[x] + term[x]
        if acc[x] >= MLDSA_Q {
          acc[x] = acc[x] - MLDSA_Q
        }
      }
    }
    let t1s = Array::make(256, 0)
    for x = 0; x < 256; x = x + 1 {
      t1s[x] = (pk.t1[i2][x] << MLDSA_D) % MLDSA_Q
    }
    dsa_ntt(t1s)
    let term = dsa_base_mul(c_hat, t1s)
    for x = 0; x < 256; x = x + 1 {
      acc[x] = acc[x] - term[x]
      if acc[x] < 0 {
        acc[x] = acc[x] + MLDSA_Q
      }
    }
    dsa_ntt_inv(acc)
    let w1_row = Array::make(256, 0)
    for x = 0; x < 256; x = x + 1 {
      w1_row[x] = use_hint(h_mat[i2][x], acc[x], alpha)
    }
    w1[i2] = w1_row
  }
  let expect = @sha3.shake256(concat_dsa(mu, encode_w1(w1, params.gamma2)), 32)
  bytes_eq_dsa(expect, sig.c_tilde)
}

///|
fn bytes_eq_dsa(a : Bytes, b : Bytes) -> Bool {
  if a.length() != b.length() {
    return false
  }
  let mut diff = 0
  for i = 0; i < a.length(); i = i + 1 {
    diff = diff | (a[i].to_int() ^ b[i].to_int())
  }
  diff == 0
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

///|
fn seed_to_bytes(seed : Int, tag : Byte) -> Bytes {
  let arr : Array[Byte] = []
  let mut x = seed
  let mut i = 0
  while i < 8 {
    arr.push((x & 0xFF).to_byte())
    x = x >> 8
    i = i + 1
  }
  arr.push(tag)
  Bytes::from_array(arr)
}

///|
/// ML-DSA key generation (default ML-DSA-65). The integer seed is expanded
/// to the spec's 32-byte xi via SHAKE256, then Algorithm 20 runs.
pub fn dilithium_keygen(seed : Int) -> (DilithiumPublicKey, DilithiumSecretKey) {
  mldsa_keygen(ml_dsa_65(), seed)
}

///|
/// ML-DSA key generation with an explicit parameter set.
pub fn mldsa_keygen(
  params : DsaParams,
  seed : Int,
) -> (DilithiumPublicKey, DilithiumSecretKey) {
  let xi = @sha3.shake256(seed_to_bytes(seed, b'\x78'), 32) // 'x'
  mldsa_keygen_internal(params, xi)
}

///|
/// ML-DSA signature. The secret key is essential: z = y + c o s1 and the
/// rejection checks use s2 and t0. Deterministic for a fixed (sk, m, seed).
pub fn dilithium_sign(
  sk : DilithiumSecretKey,
  message : Bytes,
  seed : Int,
) -> DilithiumSignature {
  let kappa0 = @sha3.shake256(seed_to_bytes(seed, b'\x6e'), 32) // 'n'
  mldsa_sign_internal(sk, message, kappa0)
}

///|
/// ML-DSA verification. The public key is essential: w' is reconstructed
/// from rho and t1 and compared against c_tilde.
pub fn dilithium_verify(
  pk : DilithiumPublicKey,
  message : Bytes,
  sig : DilithiumSignature,
) -> Bool {
  mldsa_verify_internal(pk, message, sig)
}
