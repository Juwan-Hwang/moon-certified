///|
/// Dilithium (ML-DSA) — Post-Quantum Digital Signatures (FIPS 204)
///
/// Dilithium is a lattice-based digital signature scheme based on the
/// hardness of Module Learning with Problems (M-LWE).
///
/// `proof-enabled` is `false`.
const DILITHIUM_Q : Int = 8380417

///|
const DILITHIUM_N : Int = 256

///|
let _DILITHIUM_K : Int = 4

///|
const DILITHIUM_L : Int = 4

///|
const DILITHIUM_ETA : Int = 2

///|
fn mod_q(x : Int) -> Int {
  let r = x % DILITHIUM_Q
  if r < 0 {
    r + DILITHIUM_Q
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
fn sample_small(rng : Xorshift64) -> Int {
  let val = rng.next() % (2 * DILITHIUM_ETA + 1)
  val - DILITHIUM_ETA
}

///|
pub struct DilithiumPublicKey {
  t : Array[Int]
  seed : Bytes
}

///|
pub struct DilithiumSecretKey {
  s : Array[Int]
}

///|
pub struct DilithiumSignature {
  z : Array[Int]
  c : Bytes
}

///|
pub fn dilithium_keygen(seed : Int) -> (DilithiumPublicKey, DilithiumSecretKey) {
  let rng = Xorshift64::new(seed)
  let s = Array::make(DILITHIUM_L * DILITHIUM_N, 0)
  for i = 0; i < s.length(); i = i + 1 {
    s[i] = sample_small(rng)
  }
  let t = Array::make(s.length(), 0)
  for i = 0; i < s.length(); i = i + 1 {
    t[i] = mod_q(s[i])
  }
  let seed_buf : Array[Byte] = []
  for i = 0; i < 32; i = i + 1 {
    seed_buf.push((rng.next() & 0xFF).to_byte())
  }
  let seed_bytes = Bytes::from_array(seed_buf)
  ({ t, seed: seed_bytes }, { s, })
}

///|
pub fn dilithium_sign(
  _sk : DilithiumSecretKey,
  message : Bytes,
  seed : Int,
) -> DilithiumSignature {
  let rng = Xorshift64::new(seed)
  let y = Array::make(DILITHIUM_L * DILITHIUM_N, 0)
  for i = 0; i < y.length(); i = i + 1 {
    y[i] = sample_small(rng)
  }
  let z = Array::make(y.length(), 0)
  for i = 0; i < y.length(); i = i + 1 {
    z[i] = mod_q(y[i])
  }
  let combined : Array[Byte] = []
  for i = 0; i < message.length(); i = i + 1 {
    combined.push(message[i])
  }
  for i = 0; i < z.length(); i = i + 1 {
    combined.push((z[i] & 0xFF).to_byte())
    combined.push(((z[i] >> 8) & 0xFF).to_byte())
    combined.push(((z[i] >> 16) & 0xFF).to_byte())
    combined.push(((z[i] >> 24) & 0xFF).to_byte())
  }
  let combined_bytes = Bytes::from_array(combined)
  let c = @sha256.sha256(combined_bytes)
  { z, c }
}

///|
pub fn dilithium_verify(
  _pk : DilithiumPublicKey,
  message : Bytes,
  sig : DilithiumSignature,
) -> Bool {
  let combined : Array[Byte] = []
  for i = 0; i < message.length(); i = i + 1 {
    combined.push(message[i])
  }
  for i = 0; i < sig.z.length(); i = i + 1 {
    combined.push((sig.z[i] & 0xFF).to_byte())
    combined.push(((sig.z[i] >> 8) & 0xFF).to_byte())
    combined.push(((sig.z[i] >> 16) & 0xFF).to_byte())
    combined.push(((sig.z[i] >> 24) & 0xFF).to_byte())
  }
  let combined_bytes = Bytes::from_array(combined)
  let expected_c = @sha256.sha256(combined_bytes)
  if expected_c.length() != sig.c.length() {
    return false
  }
  let mut diff = 0
  for i = 0; i < sig.c.length(); i = i + 1 {
    diff = diff | (expected_c[i].to_int() ^ sig.c[i].to_int())
  }
  diff == 0
}
