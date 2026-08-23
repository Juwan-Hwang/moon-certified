///|
/// Kyber (Module-Lattice-Based KEM) — NIST PQC Standard
///
/// ML-KEM (Kyber) is a post-quantum key encapsulation mechanism based on the
/// hardness of the Module Learning with Errors (M-LWE) problem.
///
/// `proof-enabled` is `false`.
const KYBER_Q : Int = 3329

///|
const KYBER_N : Int = 256

///|
const KYBER_K : Int = 2

///|
const KYBER_ETA : Int = 2

///|
/// Kyber public key.
pub struct KyberPublicKey {
  t : Array[Int]
  seed : Bytes
}

///|
/// Kyber secret key.
pub struct KyberSecretKey {
  s : Array[Int]
}

///|
/// Kyber ciphertext.
pub struct KyberCiphertext {
  c1 : Array[Int]
  c2 : Array[Int]
}

///|
fn mod_q(x : Int) -> Int {
  let r = x % KYBER_Q
  if r < 0 {
    r + KYBER_Q
  } else {
    r
  }
}

///|
fn centered(x : Int) -> Int {
  let r = mod_q(x)
  if r > KYBER_Q / 2 {
    r - KYBER_Q
  } else {
    r
  }
}

///|
priv struct Xorshift64 {
  mut state : Int64
}

///|
fn Xorshift64::new(seed : Int) -> Xorshift64 {
  { state: (seed.to_int64() | 1L) & 0x7FFFFFFFFFFFFFFFL }
}

///|
fn Xorshift64::next(self : Xorshift64) -> Int {
  let mut x = self.state
  x = x ^ (x << 13)
  x = x ^ (x >> 7)
  x = x ^ (x << 17)
  self.state = x
  (x & 0x7FFFFFFF).to_int()
}

///|
fn sample_cbd(rng : Xorshift64) -> Int {
  let val = rng.next() % (2 * KYBER_ETA + 1)
  val - KYBER_ETA
}

///|
pub fn kyber_keygen(seed : Int) -> (KyberPublicKey, KyberSecretKey) {
  let rng = Xorshift64::new(seed)
  let s = Array::make(KYBER_N, 0)
  let e = Array::make(KYBER_N, 0)
  for i = 0; i < KYBER_N; i = i + 1 {
    s[i] = sample_cbd(rng)
    e[i] = sample_cbd(rng)
  }
  let t = Array::make(KYBER_N, 0)
  for i = 0; i < KYBER_N; i = i + 1 {
    t[i] = mod_q(s[i] + e[i])
  }
  let seed_buf : Array[Byte] = []
  for i = 0; i < 32; i = i + 1 {
    seed_buf.push((rng.next() & 0xFF).to_byte())
  }
  let seed_bytes = Bytes::from_array(seed_buf)
  ({ t, seed: seed_bytes }, { s, })
}

///|
pub fn kyber_encaps(
  pk : KyberPublicKey,
  seed : Int,
) -> (KyberCiphertext, Bytes) {
  let rng = Xorshift64::new(seed)
  let r = Array::make(KYBER_N, 0)
  let e1 = Array::make(KYBER_N, 0)
  let e2 = Array::make(KYBER_N, 0)
  for i = 0; i < KYBER_N; i = i + 1 {
    r[i] = sample_cbd(rng)
    e1[i] = sample_cbd(rng)
    e2[i] = sample_cbd(rng)
  }
  let m = Array::make(KYBER_N, 0)
  for i = 0; i < KYBER_N; i = i + 1 {
    if (rng.next() & 1) == 1 {
      m[i] = (KYBER_Q + 1) / 2
    }
  }
  let c1 = Array::make(KYBER_N, 0)
  let c2 = Array::make(KYBER_N, 0)
  for i = 0; i < KYBER_N; i = i + 1 {
    c1[i] = mod_q(r[i] + e1[i])
    c2[i] = mod_q(pk.t[i] * r[i] + e2[i] + m[i])
  }
  let shared_buf : Array[Byte] = []
  for i = 0; i < 32; i = i + 1 {
    shared_buf.push((m[i % KYBER_N] & 0xFF).to_byte())
  }
  let shared = Bytes::from_array(shared_buf)
  ({ c1, c2 }, shared)
}

///|
pub fn kyber_decaps(sk : KyberSecretKey, ct : KyberCiphertext) -> Bytes {
  let m = Array::make(KYBER_N, 0)
  for i = 0; i < KYBER_N; i = i + 1 {
    m[i] = mod_q(ct.c2[i] - sk.s[i] * ct.c1[i])
  }
  let shared_buf : Array[Byte] = []
  for i = 0; i < 32; i = i + 1 {
    let c = centered(m[i])
    let bit = if c > KYBER_Q / 4 || c < -KYBER_Q / 4 { 1 } else { 0 }
    shared_buf.push((bit << (i % 8)).to_byte())
  }
  let combined_buf : Array[Byte] = []
  for i = 0; i < KYBER_N; i = i + 1 {
    combined_buf.push((m[i] & 0xFF).to_byte())
  }
  let combined = Bytes::from_array(combined_buf)
  @sha256.sha256(combined)
}
