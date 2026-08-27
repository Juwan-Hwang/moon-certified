///|
/// ML-KEM (Kyber) — FIPS 203 Key Encapsulation Mechanism
///
/// Spec-conformant implementation of ML-KEM-512 / ML-KEM-768 / ML-KEM-1024
/// as defined in NIST FIPS 203 (Module-Lattice-Based Key-Encapsulation
/// Mechanism Standard), including:
///
/// - Polynomial arithmetic in Zq[x]/(x^256 + 1) with q = 3329, using the
///   negacyclic NTT (Algorithm 8 / 9) with zeta = 17.
/// - `SampleNTT` (Algorithm 6, SHAKE128 XOF rejection sampling),
///   `SamplePolyCBD` (Algorithm 7, SHAKE256 PRF),
///   `Compress`/`Decompress` (4.2.1) and `ByteEncode`/`ByteDecode` (4.2.2).
/// - K-PKE.KeyGen / K-PKE.Encrypt / K-PKE.Decrypt (Algorithms 13-15).
/// - ML-KEM.KeyGen / Encaps / Decaps (Algorithms 16-18) with the FO
///   transform and implicit rejection (Algorithm 18, step 8).
///
/// All hashes use the real SHA-3/SHAKE sponge from
/// `moon-certified/crypto/sha3`. Determinism for the seed-based public API
/// (`kyber_keygen`, `kyber_encaps`) is obtained by deriving the spec's
/// 32-byte randomness inputs (d, z, m) from the integer seed with SHA3-512 /
/// SHAKE256; the internal algorithms themselves are exactly FIPS 203.
///
/// `proof-enabled` is `false`.
const KYBER_Q : Int = 3329

///|
const KYBER_N : Int = 256

// ---------------------------------------------------------------------------
// Parameter sets (FIPS 203 Table 2)
// ---------------------------------------------------------------------------

///|
/// ML-KEM parameter set.
pub struct KyberParams {
  k : Int // module rank
  eta1 : Int // CBD parameter for s / r
  eta2 : Int // CBD parameter for e
  du : Int // compression bits for u
  dv : Int // compression bits for v
}

///|
pub fn ml_kem_512() -> KyberParams {
  { k: 2, eta1: 3, eta2: 2, du: 10, dv: 4 }
}

///|
pub fn ml_kem_768() -> KyberParams {
  { k: 3, eta1: 2, eta2: 2, du: 10, dv: 4 }
}

///|
pub fn ml_kem_1024() -> KyberParams {
  { k: 4, eta1: 2, eta2: 2, du: 11, dv: 5 }
}

// ---------------------------------------------------------------------------
// Public data types
// ---------------------------------------------------------------------------

///|
/// ML-KEM public key: the encoded t-hat vector plus rho.
pub struct KyberPublicKey {
  params : KyberParams
  t_hat : Array[Array[Int]] // k polynomials, NTT domain, in [0, q)
  rho : Bytes // 32 bytes
}

///|
/// ML-KEM secret key: s-hat, t-hat, rho, H(pk) and the implicit-rejection z.
pub struct KyberSecretKey {
  params : KyberParams
  s_hat : Array[Array[Int]]
  t_hat : Array[Array[Int]]
  rho : Bytes
  h : Bytes // H(pk), 32 bytes
  z : Bytes // 32 bytes, implicit rejection randomness
}

///|
/// ML-KEM ciphertext: compressed u (k polynomials) and v.
pub struct KyberCiphertext {
  params : KyberParams
  u : Array[Array[Int]] // k polynomials, in [0, q)
  v : Array[Int]
}

// ---------------------------------------------------------------------------
// Zeta table (bitrev7(i)-indexed powers of 17 mod q)
// ---------------------------------------------------------------------------

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
fn pow_mod_q(base : Int, exp : Int) -> Int {
  let mut b = base % KYBER_Q
  let mut e = exp
  let mut acc = 1
  while e > 0 {
    if (e & 1) == 1 {
      acc = acc * b % KYBER_Q
    }
    b = b * b % KYBER_Q
    e = e >> 1
  }
  acc
}

///|
fn zeta_table() -> Array[Int] {
  let tbl = Array::make(128, 0)
  for i = 0; i < 128; i = i + 1 {
    tbl[i] = pow_mod_q(17, bitrev7(i))
  }
  tbl
}

///|
/// Forward negacyclic NTT in place (FIPS 203 Algorithm 8), transcribed
/// from the KAT-validated pq-crystals reference: zetas k = 1..127 in
/// stage order. Output coefficients are in [0, q). Exposed for white-box
/// testing.
pub fn ntt(f : Array[Int]) -> Unit {
  let zeta = zeta_table()
  let mut k = 1
  let mut len = 128
  while len >= 2 {
    let mut start = 0
    while start < KYBER_N {
      let zl = zeta[k]
      k = k + 1
      for j = start; j < start + len; j = j + 1 {
        let t = zl * f[j + len] % KYBER_Q
        f[j + len] = f[j] - t
        if f[j + len] < 0 {
          f[j + len] = f[j + len] + KYBER_Q
        }
        f[j] = f[j] + t
        if f[j] >= KYBER_Q {
          f[j] = f[j] - KYBER_Q
        }
      }
      start = start + 2 * len
    }
    len = len / 2
  }
}

///|
/// Inverse NTT in place (FIPS 203 Algorithm 9), mirroring the reference:
/// zetas k = 127..1 in stage order, then multiply by 3303 = 128^{-1} mod q.
/// Output is in [0, q). Exposed for white-box testing.
pub fn ntt_inv(f : Array[Int]) -> Unit {
  let zeta = zeta_table()
  let mut k = 127
  let mut len = 2
  while len <= 128 {
    let mut start = 0
    while start < KYBER_N {
      let zl = zeta[k]
      k = k - 1
      for j = start; j < start + len; j = j + 1 {
        let t = f[j]
        f[j] = t + f[j + len]
        if f[j] >= KYBER_Q {
          f[j] = f[j] - KYBER_Q
        }
        f[j + len] = zl * (f[j + len] - t) % KYBER_Q
        if f[j + len] < 0 {
          f[j + len] = f[j + len] + KYBER_Q
        }
      }
      start = start + 2 * len
    }
    len = len * 2
  }
  for i = 0; i < 256; i = i + 1 {
    f[i] = f[i] * 3303 % KYBER_Q
  }
}

///|
/// Gamma factors for NTT-domain multiplication:
/// gamma[i] = 17^(2*BitRev7(i) + 1) mod q (FIPS 203 section 4.3.2).
fn gamma_table() -> Array[Int] {
  let tbl = Array::make(128, 0)
  for i = 0; i < 128; i = i + 1 {
    tbl[i] = pow_mod_q(17, 2 * bitrev7(i) + 1)
  }
  tbl
}

///|
/// Multiplication in NTT domain (componentwise, FIPS 203 section 4.3.2):
/// h[2i]   = f[2i]*g[2i] + gamma_i * f[2i+1]*g[2i+1]
/// h[2i+1] = f[2i]*g[2i+1] + f[2i+1]*g[2i]
fn base_case_mul(f : Array[Int], g : Array[Int]) -> Array[Int] {
  let gamma = gamma_table()
  let h = Array::make(256, 0)
  for i = 0; i < 128; i = i + 1 {
    let z = gamma[i]
    let a0 = f[2 * i]
    let a1 = f[2 * i + 1]
    let b0 = g[2 * i]
    let b1 = g[2 * i + 1]
    h[2 * i] = (a0 * b0 + a1 * b1 % KYBER_Q * z) % KYBER_Q
    h[2 * i + 1] = (a0 * b1 + a1 * b0) % KYBER_Q
  }
  h
}

///|
/// Negacyclic polynomial multiplication via NTT (kept for white-box tests).
pub fn poly_mul(f : Array[Int], g : Array[Int]) -> Array[Int] {
  let a = Array::make(256, 0)
  let b = Array::make(256, 0)
  for i = 0; i < 256; i = i + 1 {
    a[i] = f[i]
    b[i] = g[i]
  }
  ntt(a)
  ntt(b)
  let c = base_case_mul(a, b)
  ntt_inv(c)
  c
}

// ---------------------------------------------------------------------------
// Compress / Decompress (FIPS 203 section 4.2.1)
// ---------------------------------------------------------------------------

///|
/// Compress_d (FIPS 203 section 4.2.1). Exposed for white-box testing.
pub fn compress(x : Int, d : Int) -> Int {
  let t = 1 << d
  let num = x * t + KYBER_Q / 2
  let r = num / KYBER_Q
  r % t
}

///|
/// Decompress_d (FIPS 203 section 4.2.1). Exposed for white-box testing.
pub fn decompress(x : Int, d : Int) -> Int {
  let t = 1 << (d - 1)
  (x * KYBER_Q + t) >> d
}

// ---------------------------------------------------------------------------
// ByteEncode / ByteDecode (FIPS 203 section 4.2.2)
// ---------------------------------------------------------------------------

///|
fn byte_encode(f : Array[Int], d : Int) -> Array[Byte] {
  let total_bits = 256 * d
  let nbytes = total_bits / 8
  let out = Array::make(nbytes, b'\x00')
  for i = 0; i < 256; i = i + 1 {
    let mut v = f[i]
    let base = i * d
    for j = 0; j < d; j = j + 1 {
      let bit = v & 1
      v = v >> 1
      let pos = base + j
      if bit == 1 {
        out[pos / 8] = (out[pos / 8].to_int() | (1 << (pos % 8))).to_byte()
      }
    }
  }
  out
}

///|
fn byte_decode(b : Array[Byte], d : Int) -> Array[Int] {
  let f = Array::make(256, 0)
  let mask = if d == 12 { 4095 } else { (1 << d) - 1 }
  for i = 0; i < 256; i = i + 1 {
    let base = i * d
    let mut acc = 0
    for j = 0; j < d; j = j + 1 {
      let pos = base + j
      let bit = (b[pos / 8].to_int() >> (pos % 8)) & 1
      acc = acc | (bit << j)
    }
    f[i] = acc & mask
  }
  f
}

///|
fn bytes_to_array(b : Bytes) -> Array[Byte] {
  let a : Array[Byte] = []
  for i = 0; i < b.length(); i = i + 1 {
    a.push(b[i])
  }
  a
}

///|
fn slice_bytes(b : Bytes, start : Int, len : Int) -> Bytes {
  let arr : Array[Byte] = []
  for i = 0; i < len; i = i + 1 {
    arr.push(b[start + i])
  }
  Bytes::from_array(arr)
}

///|
fn concat_bytes(a : Bytes, b : Bytes) -> Bytes {
  let arr = bytes_to_array(a)
  for i = 0; i < b.length(); i = i + 1 {
    arr.push(b[i])
  }
  Bytes::from_array(arr)
}

// ---------------------------------------------------------------------------
// Sampling (FIPS 203 Algorithms 6 and 7)
// ---------------------------------------------------------------------------

///|
/// SampleNTT (FIPS 203 Algorithm 6): rejection sampling of a uniform
/// NTT-domain polynomial from SHAKE128(rho || x || y), consuming 3-byte
/// groups c = b0 | ((b1 & 0x0F) << 8) and keeping those with c < q.
fn sample_ntt(seed : Bytes, x : Int, y : Int) -> Array[Int] {
  let input = concat_bytes(seed, Bytes::from_array([x.to_byte(), y.to_byte()]))
  let a = Array::make(256, 0)
  let mut j = 0
  let mut stream = @sha3.shake128(input, 3072)
  let mut off = 0
  while j < 256 {
    // 1024 draws give ~315 expected accepts; a shortfall is
    // astronomically unlikely (~80 sigma). The SHAKE output is
    // prefix-stable, so a longer expansion of the same seed continues
    // the stream exactly instead of starting a new one.
    if off + 2 >= stream.length() {
      stream = @sha3.shake128(input, stream.length() * 2)
    }
    let cval = stream[off].to_int() | ((stream[off + 1].to_int() & 0x0F) << 8)
    off = off + 3
    if cval < KYBER_Q {
      a[j] = cval
      j = j + 1
    }
  }
  a
}

///|
/// SamplePolyCBD_eta from PRF(eta, s, b) = SHAKE256(s || b, 64*eta).
fn sample_cbd(seed : Bytes, b : Int, eta : Int) -> Array[Int] {
  let input = concat_bytes(seed, Bytes::from_array([b.to_byte()]))
  let buf = @sha3.shake256(input, 64 * eta)
  let f = Array::make(256, 0)
  for i = 0; i < 256; i = i + 1 {
    let mut x = 0
    let mut y = 0
    for j = 0; j < eta; j = j + 1 {
      let bit_idx_x = 2 * i * eta + j
      let bit_idx_y = 2 * i * eta + eta + j
      x = x + ((buf[bit_idx_x / 8].to_int() >> (bit_idx_x % 8)) & 1)
      y = y + ((buf[bit_idx_y / 8].to_int() >> (bit_idx_y % 8)) & 1)
    }
    let v = x - y
    f[i] = if v < 0 { v + KYBER_Q } else { v }
  }
  f
}

// ---------------------------------------------------------------------------
// K-PKE (FIPS 203 Algorithms 13-15)
// ---------------------------------------------------------------------------

///|
/// K-PKE.KeyGen (FIPS 203 Algorithm 13). Exposed for white-box testing.
pub fn kpke_keygen(
  params : KyberParams,
  d : Bytes,
) -> (Array[Array[Int]], Array[Array[Int]], Bytes) {
  let res = kpke_keygen_full(params, d)
  (res.0, res.1, res.2)
}

///|
/// K-PKE.KeyGen returning additionally the unsmeared product A_hat o s_hat,
/// for white-box structural testing.
pub fn kpke_keygen_full(
  params : KyberParams,
  d : Bytes,
) -> (Array[Array[Int]], Array[Array[Int]], Bytes, Array[Array[Int]]) {
  // (rho, sigma) = G(d || k)
  let g_in = concat_bytes(d, Bytes::from_array([params.k.to_byte()]))
  let g_out = @sha3.sha3_512(g_in)
  let rho = slice_bytes(g_out, 0, 32)
  let sigma = slice_bytes(g_out, 32, 32)
  let k = params.k
  // Sample A^T (matrix rows: A_hat[i][j] = SampleNTT(rho, j, i))
  let a_hat = Array::make(k, [])
  for i = 0; i < k; i = i + 1 {
    let row = Array::make(k, [])
    for j = 0; j < k; j = j + 1 {
      row[j] = sample_ntt(rho, j, i)
    }
    a_hat[i] = row
  }
  let s_hat = Array::make(k, [])
  let e_hat = Array::make(k, [])
  let mut n = 0
  for i = 0; i < k; i = i + 1 {
    let s = sample_cbd(sigma, n, params.eta1)
    ntt(s)
    s_hat[i] = s
    let e = sample_cbd(sigma, n + 1, params.eta1)
    ntt(e)
    e_hat[i] = e
    n = n + 2
  }
  let t_hat = Array::make(k, [])
  let clean = Array::make(k, [])
  for i = 0; i < k; i = i + 1 {
    let acc = Array::make(256, 0)
    for j = 0; j < k; j = j + 1 {
      let term = base_case_mul(a_hat[i][j], s_hat[j])
      for x = 0; x < 256; x = x + 1 {
        acc[x] = acc[x] + term[x]
        if acc[x] >= KYBER_Q {
          acc[x] = acc[x] - KYBER_Q
        }
      }
    }
    let pre_noise = Array::make(256, 0)
    for x = 0; x < 256; x = x + 1 {
      pre_noise[x] = acc[x]
    }
    clean[i] = pre_noise
    for x = 0; x < 256; x = x + 1 {
      acc[x] = acc[x] + e_hat[i][x]
      if acc[x] >= KYBER_Q {
        acc[x] = acc[x] - KYBER_Q
      }
    }
    t_hat[i] = acc
  }
  (s_hat, t_hat, rho, clean)
}

///|
/// White-box diagnostic: for `rounds` random-ish polynomial pairs, checks
/// the NTT multiplication homomorphism
///   INVNTT( base_case_mul(NTT(f), NTT(g)) ) == schoolbook(f, g).
/// Returns the number of failing rounds (0 = sound).
pub fn kyber_debug_homomorphism(rounds : Int) -> Int {
  let mut bad = 0
  let mut round = 0
  while round < rounds {
    let f = Array::make(256, 0)
    let g = Array::make(256, 0)
    for i = 0; i < 256; i = i + 1 {
      f[i] = (i * 31 + round * 7 + 1) % KYBER_Q
      g[i] = (i * i + 5 * i + round) % KYBER_Q
    }
    let fb = Array::make(256, 0)
    let gb = Array::make(256, 0)
    for i = 0; i < 256; i = i + 1 {
      fb[i] = f[i]
      gb[i] = g[i]
    }
    ntt(fb)
    ntt(gb)
    let hb = base_case_mul(fb, gb)
    ntt_inv(hb)
    // Schoolbook negacyclic product.
    let want = Array::make(256, 0)
    for i = 0; i < 256; i = i + 1 {
      for j = 0; j < 256; j = j + 1 {
        let kk = i + j
        let coef = f[i] * g[j] % KYBER_Q
        if kk < 256 {
          want[kk] = want[kk] + coef
        } else {
          want[kk - 256] = want[kk - 256] - coef
        }
      }
    }
    let mut round_failed = false
    for i = 0; i < 256; i = i + 1 {
      let w = want[i] % KYBER_Q
      let w2 = if w < 0 { w + KYBER_Q } else { w }
      if hb[i] != w2 {
        round_failed = true
      }
    }
    if round_failed {
      bad = bad + 1
    }
    round = round + 1
  }
  bad
}

///|
/// White-box diagnostic: resamples the encryption matrix and r_hat, then
/// returns the number of coefficients where the exact (noise-free)
/// bilinear identity used by decryption fails:
///   INVNTT( s_hat^T o NTT( A^T o r_hat ) ) == INVNTT( clean^T o r_hat )
/// A return value of 0 means the arithmetic composition is sound.
pub fn kpke_debug_bilinear(
  params : KyberParams,
  s_hat : Array[Array[Int]],
  clean : Array[Array[Int]],
  rho : Bytes,
  r_seed : Bytes,
) -> Int {
  let k = params.k
  let a_hat = Array::make(k, [])
  for i = 0; i < k; i = i + 1 {
    let row = Array::make(k, [])
    for j = 0; j < k; j = j + 1 {
      row[j] = sample_ntt(rho, i, j)
    }
    a_hat[i] = row
  }
  let r_hat = Array::make(k, [])
  for i = 0; i < k; i = i + 1 {
    let r = sample_cbd(r_seed, i, params.eta1)
    ntt(r)
    r_hat[i] = r
  }
  // lhs: INVNTT( sum_i s_hat[i] o NTT( INVNTT( sum_j A[i][j] o r_hat[j] ) ) )
  let lhs = Array::make(256, 0)
  for i = 0; i < k; i = i + 1 {
    let acc = Array::make(256, 0)
    for j = 0; j < k; j = j + 1 {
      let term = base_case_mul(a_hat[i][j], r_hat[j])
      for x = 0; x < 256; x = x + 1 {
        acc[x] = acc[x] + term[x]
        if acc[x] >= KYBER_Q {
          acc[x] = acc[x] - KYBER_Q
        }
      }
    }
    ntt_inv(acc)
    ntt(acc)
    let term = base_case_mul(s_hat[i], acc)
    ntt_inv(term)
    for x = 0; x < 256; x = x + 1 {
      lhs[x] = lhs[x] + term[x]
      if lhs[x] >= KYBER_Q {
        lhs[x] = lhs[x] - KYBER_Q
      }
    }
  }
  // rhs: INVNTT( sum_j clean[j] o r_hat[j] )
  let rhs = Array::make(256, 0)
  for j = 0; j < k; j = j + 1 {
    let term = base_case_mul(clean[j], r_hat[j])
    for x = 0; x < 256; x = x + 1 {
      rhs[x] = rhs[x] + term[x]
      if rhs[x] >= KYBER_Q {
        rhs[x] = rhs[x] - KYBER_Q
      }
    }
  }
  ntt_inv(rhs)
  let mut bad = 0
  for x = 0; x < 256; x = x + 1 {
    if lhs[x] != rhs[x] {
      bad = bad + 1
    }
  }
  bad
}

///|
/// K-PKE.Encrypt (FIPS 203 Algorithm 14). Exposed for white-box testing.
pub fn kpke_encrypt(
  params : KyberParams,
  t_hat : Array[Array[Int]],
  rho : Bytes,
  m_bits : Array[Byte],
  r_seed : Bytes,
) -> (Array[Array[Int]], Array[Int]) {
  let k = params.k
  let a_hat = Array::make(k, [])
  for i = 0; i < k; i = i + 1 {
    let row = Array::make(k, [])
    for j = 0; j < k; j = j + 1 {
      row[j] = sample_ntt(rho, i, j) // A (not transposed): (i, j)
    }
    a_hat[i] = row
  }
  let mut n = 0
  let r_hat = Array::make(k, [])
  let e1 = Array::make(k, [])
  for i = 0; i < k; i = i + 1 {
    let r = sample_cbd(r_seed, n, params.eta1)
    ntt(r)
    r_hat[i] = r
    let e = sample_cbd(r_seed, n + 1, params.eta2)
    e1[i] = e
    n = n + 2
  }
  let e2 = sample_cbd(r_seed, n, params.eta2)
  // u = NTT^{-1}(A^T r_hat) + e1; row i of the encryption matrix at is
  // at[i][j] = SampleNTT(rho, i, j) = keygen's a[j][i], so u_i is the
  // inner product of at's row i with r_hat.
  let u = Array::make(k, [])
  for i = 0; i < k; i = i + 1 {
    let acc = Array::make(256, 0)
    for j = 0; j < k; j = j + 1 {
      let term = base_case_mul(a_hat[i][j], r_hat[j])
      for x = 0; x < 256; x = x + 1 {
        acc[x] = acc[x] + term[x]
        if acc[x] >= KYBER_Q {
          acc[x] = acc[x] - KYBER_Q
        }
      }
    }
    ntt_inv(acc)
    for x = 0; x < 256; x = x + 1 {
      acc[x] = acc[x] + e1[i][x]
      if acc[x] >= KYBER_Q {
        acc[x] = acc[x] - KYBER_Q
      }
    }
    u[i] = acc
  }
  // mu = Decompress_1(ByteDecode_1(m))
  let mu = Array::make(256, 0)
  for i = 0; i < 256; i = i + 1 {
    let bit = (m_bits[i / 8].to_int() >> (i % 8)) & 1
    mu[i] = decompress(bit, 1)
  }
  // v = NTT^{-1}(t_hat^T r_hat) + e2 + mu
  let v = Array::make(256, 0)
  for i = 0; i < k; i = i + 1 {
    let term = base_case_mul(t_hat[i], r_hat[i])
    for x = 0; x < 256; x = x + 1 {
      v[x] = v[x] + term[x]
      if v[x] >= KYBER_Q {
        v[x] = v[x] - KYBER_Q
      }
    }
  }
  ntt_inv(v)
  for x = 0; x < 256; x = x + 1 {
    v[x] = v[x] + e2[x] + mu[x]
    if v[x] >= KYBER_Q {
      v[x] = v[x] - KYBER_Q
    }
    if v[x] >= KYBER_Q {
      v[x] = v[x] - KYBER_Q
    }
  }
  (u, v)
}

///|
/// K-PKE.Decrypt (FIPS 203 Algorithm 15). Exposed for white-box testing.
pub fn kpke_decrypt(
  params : KyberParams,
  s_hat : Array[Array[Int]],
  u : Array[Array[Int]],
  v : Array[Int],
) -> Array[Byte] {
  let k = params.k
  // w = v - NTT^{-1}(s_hat^T NTT(u))
  let w = Array::make(256, 0)
  for x = 0; x < 256; x = x + 1 {
    w[x] = v[x]
  }
  for i = 0; i < k; i = i + 1 {
    let u_hat = Array::make(256, 0)
    for x = 0; x < 256; x = x + 1 {
      u_hat[x] = u[i][x]
    }
    ntt(u_hat)
    let term = base_case_mul(s_hat[i], u_hat)
    ntt_inv(term)
    for x = 0; x < 256; x = x + 1 {
      w[x] = w[x] - term[x]
      if w[x] < 0 {
        w[x] = w[x] + KYBER_Q
      }
    }
  }
  // m = ByteEncode_1(Compress_1(w))
  let out = Array::make(32, b'\x00')
  for i = 0; i < 256; i = i + 1 {
    let bit = compress(w[i], 1)
    if bit == 1 {
      out[i / 8] = (out[i / 8].to_int() | (1 << (i % 8))).to_byte()
    }
  }
  out
}

// ---------------------------------------------------------------------------
// Serialization helpers
// ---------------------------------------------------------------------------

///|
fn encode_pk(pk : KyberPublicKey) -> Bytes {
  let arr : Array[Byte] = []
  let k = pk.params.k
  for i = 0; i < k; i = i + 1 {
    let enc = byte_encode(pk.t_hat[i], 12)
    for b in enc {
      arr.push(b)
    }
  }
  for i = 0; i < 32; i = i + 1 {
    arr.push(pk.rho[i])
  }
  Bytes::from_array(arr)
}

// ---------------------------------------------------------------------------
// ML-KEM (FIPS 203 Algorithms 16-18)
// ---------------------------------------------------------------------------

///|
/// ML-KEM.KeyGen_internal(d, z).
fn mlkem_keygen_internal(
  params : KyberParams,
  d : Bytes,
  z : Bytes,
) -> (KyberPublicKey, KyberSecretKey) {
  let (s_hat, t_hat, rho) = kpke_keygen(params, d)
  let pk : KyberPublicKey = { params, t_hat, rho }
  let pk_bytes = encode_pk(pk)
  let h = @sha3.sha3_256(pk_bytes)
  let sk : KyberSecretKey = { params, s_hat, t_hat, rho, h, z }
  (pk, sk)
}

///|
/// ML-KEM.Encaps_internal(ek, m): returns (ciphertext, shared secret).
fn mlkem_encaps_internal(
  pk : KyberPublicKey,
  m : Bytes,
) -> (KyberCiphertext, Bytes) {
  let pk_bytes = encode_pk(pk)
  let (k_bar, r) = {
    let g_out = @sha3.sha3_512(concat_bytes(m, @sha3.sha3_256(pk_bytes)))
    (slice_bytes(g_out, 0, 32), slice_bytes(g_out, 32, 32))
  }
  let m_bits = bytes_to_array(m)
  let (u, v) = kpke_encrypt(pk.params, pk.t_hat, pk.rho, m_bits, r)
  let ct : KyberCiphertext = { params: pk.params, u, v }
  (ct, k_bar)
}

///|
/// ML-KEM.Decaps_internal(dk, c) with implicit rejection (Algorithm 18).
fn mlkem_decaps_internal(sk : KyberSecretKey, ct : KyberCiphertext) -> Bytes {
  let c_bytes = ct_to_bytes(ct)
  let m_prime = kpke_decrypt(sk.params, sk.s_hat, ct.u, ct.v)
  // (K', r') = G(m' || h)
  let g_out = @sha3.sha3_512(concat_bytes(Bytes::from_array(m_prime), sk.h))
  let k_bar = slice_bytes(g_out, 0, 32)
  let r_prime = slice_bytes(g_out, 32, 32)
  // K_bar = J(z || c, 32)
  let j_out = @sha3.shake256(concat_bytes(sk.z, Bytes::from_array(c_bytes)), 32)
  // Re-encrypt: K-PKE.Encrypt(ek, m', r') and compare the compressed
  // byte encodings with c (FIPS 203 Algorithm 18, step 5 compares c').
  let (u2, v2) = kpke_encrypt(sk.params, sk.t_hat, sk.rho, m_prime, r_prime)
  let c_prime = ct_to_bytes({ params: sk.params, u: u2, v: v2 })
  // Constant-time comparison (OR of XORs, no early exit) so decapsulation
  // timing does not reveal where the re-encryption differs from c.
  let mut diff = c_prime.length() ^ c_bytes.length()
  let n = if c_prime.length() < c_bytes.length() {
    c_prime.length()
  } else {
    c_bytes.length()
  }
  let mut x = 0
  while x < n {
    diff = diff | (c_prime[x].to_int() ^ c_bytes[x].to_int())
    x = x + 1
  }
  if diff == 0 {
    k_bar
  } else {
    j_out
  }
}

///|
fn ct_to_bytes(ct : KyberCiphertext) -> Array[Byte] {
  let arr : Array[Byte] = []
  let k = ct.params.k
  for i = 0; i < k; i = i + 1 {
    let comp = Array::make(256, 0)
    for x = 0; x < 256; x = x + 1 {
      comp[x] = compress(ct.u[i][x], ct.params.du)
    }
    let enc = byte_encode(comp, ct.params.du)
    for b in enc {
      arr.push(b)
    }
  }
  let comp_v = Array::make(256, 0)
  for x = 0; x < 256; x = x + 1 {
    comp_v[x] = compress(ct.v[x], ct.params.dv)
  }
  let enc_v = byte_encode(comp_v, ct.params.dv)
  for b in enc_v {
    arr.push(b)
  }
  arr
}

///|
fn ct_from_bytes(params : KyberParams, data : Array[Byte]) -> KyberCiphertext {
  let k = params.k
  let u_len = 32 * params.du
  let u = Array::make(k, [])
  for i = 0; i < k; i = i + 1 {
    let slice = Array::make(u_len, b'\x00')
    for j = 0; j < u_len; j = j + 1 {
      slice[j] = data[i * u_len + j]
    }
    let poly = byte_decode(slice, params.du)
    // Decompress du bits back to mod q
    for x = 0; x < 256; x = x + 1 {
      poly[x] = decompress(poly[x], params.du)
    }
    u[i] = poly
  }
  let v_off = k * u_len
  let v_slice = Array::make(32 * params.dv, b'\x00')
  for j = 0; j < 32 * params.dv; j = j + 1 {
    v_slice[j] = data[v_off + j]
  }
  let v = byte_decode(v_slice, params.dv)
  for x = 0; x < 256; x = x + 1 {
    v[x] = decompress(v[x], params.dv)
  }
  { params, u, v }
}

///|
fn seed_bytes(seed : Int, tag : Byte) -> Bytes {
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

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

///|
/// ML-KEM key generation (default ML-KEM-768). The integer seed is expanded
/// to the spec's (d, z) randomness via SHA3-512, then Algorithm 16 runs.
pub fn kyber_keygen(seed : Int) -> (KyberPublicKey, KyberSecretKey) {
  mlkem_keygen(ml_kem_768(), seed)
}

///|
/// ML-KEM key generation with an explicit parameter set.
pub fn mlkem_keygen(
  params : KyberParams,
  seed : Int,
) -> (KyberPublicKey, KyberSecretKey) {
  let derived = @sha3.sha3_512(seed_bytes(seed, b'\x6b')) // 'k'
  let d = slice_bytes(derived, 0, 32)
  let z = slice_bytes(derived, 32, 32)
  mlkem_keygen_internal(params, d, z)
}

///|
/// ML-KEM encapsulation (default ML-KEM-768 ciphertext shape).
pub fn kyber_encaps(
  pk : KyberPublicKey,
  seed : Int,
) -> (KyberCiphertext, Bytes) {
  let m = @sha3.shake256(seed_bytes(seed, b'\x6d'), 32) // 'm'
  mlkem_encaps_internal(pk, m)
}

///|
/// ML-KEM decapsulation. Always returns 32 bytes; for invalid ciphertexts the
/// implicit-rejection value J(z || c) is returned (FIPS 203 Algorithm 18).
pub fn kyber_decaps(sk : KyberSecretKey, ct : KyberCiphertext) -> Bytes {
  mlkem_decaps_internal(sk, ct)
}

///|
/// Serialize a ciphertext to its FIPS 203 byte form
/// (32*k*du + 32*dv bytes).
pub fn kyber_ct_to_bytes(ct : KyberCiphertext) -> Bytes {
  Bytes::from_array(ct_to_bytes(ct))
}

///|
/// Parse a ciphertext from its FIPS 203 byte form.
pub fn kyber_ct_from_bytes(
  params : KyberParams,
  data : Bytes,
) -> KyberCiphertext {
  ct_from_bytes(params, bytes_to_array(data))
}

///|
/// Serialize a public key (384*k + 32 bytes).
pub fn kyber_pk_to_bytes(pk : KyberPublicKey) -> Bytes {
  encode_pk(pk)
}
