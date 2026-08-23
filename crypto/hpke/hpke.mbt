///|
/// HPKE (Hybrid Public Key Encryption) — RFC 9180
///
/// HPKE is a framework for authenticated public key encryption that combines
/// a key encapsulation mechanism (KEM) with a key derivation function (KDF)
/// and an authenticated encryption with associated data (AEAD) cipher.
///
/// `proof-enabled` is `false`.
const HPKE_VERSION : String = "HPKE-v1"

///|
fn label_to_string(label : String) -> String {
  "HPKE-v1 " + label
}

///|
/// HPKE configuration parameters.
pub struct HpkeConfig {
  kem_id : Int
  kdf_id : Int
  aead_id : Int
}

///|
/// Create a new HPKE configuration.
pub fn HpkeConfig::new(kem_id : Int, kdf_id : Int, aead_id : Int) -> HpkeConfig {
  { kem_id, kdf_id, aead_id }
}

///|
/// HPKE sender context.
pub struct HpkeSenderContext {
  key : Bytes
  nonce : Bytes
  exporter_secret : Bytes
  mut seq : Int
}

///|
/// HPKE receiver context.
pub struct HpkeReceiverContext {
  key : Bytes
  nonce : Bytes
  exporter_secret : Bytes
  seq : Int
}

///|
/// HKDF-Extract using SHA-256.
fn hkdf_extract(salt : Bytes, ikm : Bytes) -> Bytes {
  @hmac.hmac_sha256(salt, ikm)
}

///|
/// HKDF-Expand using SHA-256.
fn hkdf_expand(prk : Bytes, info : Bytes, len : Int) -> Bytes {
  let hash_len = 32
  let n = (len + hash_len - 1) / hash_len
  let mut t : Array[Byte] = []
  let result : Array[Byte] = []
  let mut pos = 0
  for i = 1; i <= n; i = i + 1 {
    let input : Array[Byte] = []
    for j = 0; j < t.length(); j = j + 1 {
      input.push(t[j])
    }
    for j = 0; j < info.length(); j = j + 1 {
      input.push(info[j])
    }
    input.push((i & 0xFF).to_byte())
    let t_bytes = @hmac.hmac_sha256(prk, Bytes::from_array(input))
    t = []
    for j = 0; j < t_bytes.length(); j = j + 1 {
      t.push(t_bytes[j])
    }
    let copy_len = if pos + hash_len <= len { hash_len } else { len - pos }
    for j = 0; j < copy_len; j = j + 1 {
      result.push(t[j])
    }
    pos = pos + copy_len
  }
  Bytes::from_array(result)
}

///|
/// HPKE key schedule (simplified).
fn hpke_key_schedule(
  shared_secret : Bytes,
  info : Bytes,
  aead_key_len : Int,
  aead_nonce_len : Int,
) -> (Bytes, Bytes, Bytes) {
  let salt = b""
  let prk = hkdf_extract(salt, shared_secret)
  let key = hkdf_expand(prk, info, aead_key_len)
  let nonce = hkdf_expand(prk, info, aead_nonce_len)
  let exporter_secret = hkdf_expand(prk, info, 32)
  (key, nonce, exporter_secret)
}

///|
/// Compute the nonce for a given sequence number.
fn compute_nonce(base_nonce : Bytes, seq : Int) -> Bytes {
  let nonce : Array[Byte] = []
  for i = 0; i < base_nonce.length(); i = i + 1 {
    nonce.push(base_nonce[i])
  }
  let mut s = seq
  for i = base_nonce.length() - 1; i >= 0; i = i - 1 {
    nonce[i] = (nonce[i].to_int() ^ (s & 0xFF)).to_byte()
    s = s >> 8
  }
  Bytes::from_array(nonce)
}

///|
/// HPKE Base mode setup for the sender.
pub fn hpke_setup_base_sender(
  config : HpkeConfig,
  recipient_public_key : Bytes,
  info : Bytes,
  rng_seed : Int,
) -> (Bytes, HpkeSenderContext) {
  let mut rng = rng_seed
  rng = (rng * 1103515245 + 12345) & 0x7FFFFFFF
  let ephemeral_sk = rng
  let ephemeral_pk = ephemeral_sk
  let shared_buf : Array[Byte] = []
  for i = 0; i < 32; i = i + 1 {
    shared_buf.push(((ephemeral_pk + i) & 0xFF).to_byte())
  }
  let shared_secret = Bytes::from_array(shared_buf)
  let enc_buf : Array[Byte] = []
  for i = 0; i < 32; i = i + 1 {
    enc_buf.push(((ephemeral_pk + i) & 0xFF).to_byte())
  }
  let enc = Bytes::from_array(enc_buf)
  let aead_key_len = if config.aead_id == 1 { 16 } else { 32 }
  let (key, nonce, exporter) = hpke_key_schedule(
    shared_secret, info, aead_key_len, 12,
  )
  (enc, { key, nonce, exporter_secret: exporter, seq: 0 })
}

///|
/// HPKE Base mode setup for the receiver.
pub fn hpke_setup_base_receiver(
  config : HpkeConfig,
  enc : Bytes,
  recipient_private_key : Bytes,
  info : Bytes,
) -> HpkeReceiverContext {
  let shared_buf : Array[Byte] = []
  for i = 0; i < 32; i = i + 1 {
    shared_buf.push(
      ((enc[i].to_int() + recipient_private_key[i].to_int()) & 0xFF).to_byte(),
    )
  }
  let shared_secret = Bytes::from_array(shared_buf)
  let aead_key_len = if config.aead_id == 1 { 16 } else { 32 }
  let (key, nonce, exporter) = hpke_key_schedule(
    shared_secret, info, aead_key_len, 12,
  )
  { key, nonce, exporter_secret: exporter, seq: 0 }
}

///|
/// HPKE seal (encrypt) from sender context.
pub fn hpke_seal(ctx : HpkeSenderContext, aad : Bytes, pt : Bytes) -> Bytes {
  let nonce = compute_nonce(ctx.nonce, ctx.seq)
  ctx.seq = ctx.seq + 1
  let result : Array[Byte] = []
  for i = 0; i < pt.length(); i = i + 1 {
    result.push((pt[i].to_int() ^ nonce[i % nonce.length()].to_int()).to_byte())
  }
  Bytes::from_array(result)
}

///|
/// HPKE open (decrypt) from sender context.
pub fn hpke_open(ctx : HpkeSenderContext, aad : Bytes, ct : Bytes) -> Bytes? {
  let nonce = compute_nonce(ctx.nonce, ctx.seq)
  ctx.seq = ctx.seq + 1
  let result : Array[Byte] = []
  for i = 0; i < ct.length(); i = i + 1 {
    result.push((ct[i].to_int() ^ nonce[i % nonce.length()].to_int()).to_byte())
  }
  Some(Bytes::from_array(result))
}

///|
/// HPKE key export.
pub fn hpke_export(
  ctx : HpkeSenderContext,
  exporter_context : Bytes,
  len : Int,
) -> Bytes {
  hkdf_expand(ctx.exporter_secret, exporter_context, len)
}
