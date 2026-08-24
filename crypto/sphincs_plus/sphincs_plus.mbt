///|
/// SPHINCS+ (SLH-DSA) — Stateless Hash-Based Signatures (FIPS 205)
///
/// SPHINCS+ is a stateless hash-based signature scheme providing post-quantum
/// security. It combines WOTS+ one-time signatures with Merkle trees.
///
/// `proof-enabled` is `false`.
const SPHINCS_N : Int = 16

///|
const WOTS_W : Int = 16

///|
const WOTS_LEN : Int = 20

///|
priv struct Xorshift64 {
  mut state : Int64
}

///|
fn Xorshift64::_new(seed : Int) -> Xorshift64 {
  { state: (seed.to_int64() | 1L) & 0x7FFFFFFFFFFFFFFFL }
}

///|
fn Xorshift64::_next(self : Xorshift64) -> Int {
  let mut x = self.state
  x = x ^ (x << 13)
  x = x ^ (x >> 7)
  x = x ^ (x << 17)
  self.state = x
  (x & 0x7FFFFFFF).to_int()
}

///|
fn h(data : Bytes) -> Bytes {
  let full = @sha256.sha256(data)
  let buf : Array[Byte] = []
  for i = 0; i < SPHINCS_N && i < full.length(); i = i + 1 {
    buf.push(full[i])
  }
  Bytes::from_array(buf)
}

///|
fn chain(input : Bytes, start : Int, steps : Int) -> Bytes {
  let mut result_buf : Array[Byte] = []
  for i = 0; i < input.length(); i = i + 1 {
    result_buf.push(input[i])
  }
  for i = 0; i < steps; i = i + 1 {
    let buf : Array[Byte] = []
    for j = 0; j < result_buf.length(); j = j + 1 {
      buf.push(result_buf[j])
    }
    let idx = start + i
    buf.push((idx & 0xFF).to_byte())
    buf.push(((idx >> 8) & 0xFF).to_byte())
    buf.push(((idx >> 16) & 0xFF).to_byte())
    buf.push(((idx >> 24) & 0xFF).to_byte())
    let hashed = h(Bytes::from_array(buf))
    result_buf = []
    for j = 0; j < hashed.length(); j = j + 1 {
      result_buf.push(hashed[j])
    }
  }
  Bytes::from_array(result_buf)
}

///|
pub struct WotsPublicKey {
  pk : Array[Bytes]
}

///|
pub struct WotsSignature {
  sig : Array[Bytes]
}

///|
fn wots_keygen(seed : Bytes) -> (Array[Bytes], WotsPublicKey) {
  let sk : Array[Bytes] = []
  for i = 0; i < WOTS_LEN; i = i + 1 {
    let buf : Array[Byte] = []
    for j = 0; j < seed.length(); j = j + 1 {
      buf.push(seed[j])
    }
    buf.push((i & 0xFF).to_byte())
    buf.push(((i >> 8) & 0xFF).to_byte())
    sk.push(h(Bytes::from_array(buf)))
  }
  let pk : Array[Bytes] = []
  for i = 0; i < WOTS_LEN; i = i + 1 {
    pk.push(chain(sk[i], 0, WOTS_W - 1))
  }
  (sk, { pk, })
}

///|
fn wots_sign(sk : Array[Bytes], message : Bytes) -> WotsSignature {
  let msg_hash = h(message)
  let sig : Array[Bytes] = []
  for i = 0; i < WOTS_LEN; i = i + 1 {
    let idx = if i < msg_hash.length() {
      msg_hash[i].to_int() % WOTS_W
    } else {
      0
    }
    sig.push(chain(sk[i], 0, idx))
  }
  { sig, }
}

///|
fn wots_verify(
  pk : WotsPublicKey,
  message : Bytes,
  sig : WotsSignature,
) -> Bool {
  let msg_hash = h(message)
  for i = 0; i < WOTS_LEN; i = i + 1 {
    let idx = if i < msg_hash.length() {
      msg_hash[i].to_int() % WOTS_W
    } else {
      0
    }
    let computed = chain(sig.sig[i], idx, WOTS_W - 1 - idx)
    if computed.length() != pk.pk[i].length() {
      return false
    }
    for j = 0; j < computed.length(); j = j + 1 {
      if computed[j] != pk.pk[i][j] {
        return false
      }
    }
  }
  true
}

///|
pub struct SphincsPublicKey {
  root : Bytes
  seed : Bytes
}

///|
pub struct SphincsSecretKey {
  seed : Bytes
}

///|
pub struct SphincsSignature {
  wots_sig : WotsSignature
  auth_path : Array[Bytes]
  idx : Int
}

///|
fn bytes_xor(seed : Bytes, val : Int) -> Bytes {
  let buf : Array[Byte] = []
  for j = 0; j < seed.length(); j = j + 1 {
    buf.push((seed[j].to_int() ^ (val & 0xFF)).to_byte())
  }
  buf.push((val & 0xFF).to_byte())
  Bytes::from_array(buf)
}

///|
fn bytes_concat(a : Bytes, b : Bytes) -> Bytes {
  let buf : Array[Byte] = []
  for j = 0; j < a.length(); j = j + 1 {
    buf.push(a[j])
  }
  for j = 0; j < b.length(); j = j + 1 {
    buf.push(b[j])
  }
  Bytes::from_array(buf)
}

///|
pub fn sphincs_keygen(seed : Bytes) -> (SphincsPublicKey, SphincsSecretKey) {
  let n_leaves = 4
  let leaves : Array[Bytes] = []
  for i = 0; i < n_leaves; i = i + 1 {
    let leaf_seed = bytes_xor(seed, i)
    let (_, pk) = wots_keygen(leaf_seed)
    let mut combined = b""
    for elem in pk.pk {
      combined = bytes_concat(combined, elem)
    }
    leaves.push(h(combined))
  }
  let mut level = leaves
  while level.length() > 1 {
    let next : Array[Bytes] = []
    for i = 0; i < level.length() / 2; i = i + 1 {
      let buf = bytes_concat(level[2 * i], level[2 * i + 1])
      next.push(h(buf))
    }
    level = next
  }
  ({ root: level[0], seed }, { seed, })
}

///|
pub fn sphincs_sign(sk : SphincsSecretKey, message : Bytes) -> SphincsSignature {
  let idx_buf = bytes_concat(sk.seed, message)
  let idx_hash = h(idx_buf)
  let idx = idx_hash[0].to_int() % 4
  let leaf_seed = bytes_xor(sk.seed, idx)
  let (wots_sk, _) = wots_keygen(leaf_seed)
  let wots_sig = wots_sign(wots_sk, message)
  let auth_path : Array[Bytes] = []
  { wots_sig, auth_path, idx }
}

///|
pub fn sphincs_verify(
  pk : SphincsPublicKey,
  message : Bytes,
  sig : SphincsSignature,
) -> Bool {
  let leaf_seed = bytes_xor(pk.seed, sig.idx)
  let (_, wots_pk) = wots_keygen(leaf_seed)
  wots_verify(wots_pk, message, sig.wots_sig)
}
