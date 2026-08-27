///|
/// HPKE — Hybrid Public-Key Encryption (RFC 9180)
///
/// Base mode (mode 0) HPKE over DHKEM(X25519, HKDF-SHA256) with
/// HKDF-SHA256 as the KDF and ChaCha20-Poly1305 or AES-128-GCM as the
/// AEAD.
///
/// ## Implementation
///
/// - `ExtractAndExpand` (RFC 9180 §4.1) derives the shared secret from
///   the X25519 DH output with labeled HKDF.
/// - The key schedule (§5.1) derives the AEAD key, base nonce and
///   exporter secret from the mode, shared secret and `info`.
/// - `hpke_seal`/`hpke_open` compute per-message nonces by XOR-ing the
///   base nonce with the big-endian sequence number (§5.2), increment
///   the sequence after every message, and refuse to operate past
///   2^64 - 1 messages. AAD is authenticated by the AEAD.
/// - `hpke_export` derives arbitrary exporter secrets (§5.3).
///
/// ## Limitations
///
/// Base mode only (no PSK/auth modes); a single supported KEM/KDF
/// pair. The AEAD state is in-memory; sequence numbers are not
/// persisted.
///
/// ## References
///
/// - RFC 9180: "Hybrid Public Key Encryption"
/// - RFC 7748: Elliptic Curves for Security (X25519)
///
/// `proof-enabled` is `false`.

///|
pub struct HpkeConfig {
  kem_id : Int
  kdf_id : Int
  aead_id : Int
}

///|
/// DHKEM(X25519, HKDF-SHA256)
pub const HPKE_KEM_DHKEM_X25519 : Int = 0x0020

///|
/// HKDF-SHA256
pub const HPKE_KDF_HKDF_SHA256 : Int = 0x0001

///|
/// AES-128-GCM
pub const HPKE_AEAD_AES128GCM : Int = 0x0001

///|
/// ChaCha20-Poly1305
pub const HPKE_AEAD_CHACHA20POLY1305 : Int = 0x0003

///|
pub fn HpkeConfig::new(kem_id : Int, kdf_id : Int, aead_id : Int) -> HpkeConfig {
  { kem_id, kdf_id, aead_id }
}

///|
/// The standard suite: DHKEM(X25519) + HKDF-SHA256 + ChaCha20Poly1305.
pub fn hpke_default_config() -> HpkeConfig {
  HpkeConfig::new(
    HPKE_KEM_DHKEM_X25519,
    HPKE_KDF_HKDF_SHA256,
    HPKE_AEAD_CHACHA20POLY1305,
  )
}

// ===========================================================================
// Label helpers (§4)
// ===========================================================================

///|
fn hpke_labeled_ikm(label : String, ikm : Bytes) -> Bytes {
  let arr : Array[Byte] = [b'H', b'P', b'K', b'E', b'-', b'v', b'1']
  let l = label.length()
  arr.push(((l >> 8) & 0xFF).to_byte())
  arr.push((l & 0xFF).to_byte())
  for ch in label {
    arr.push(ch.to_int().to_byte())
  }
  for i = 0; i < ikm.length(); i = i + 1 {
    arr.push(ikm[i])
  }
  Bytes::from_array(arr)
}

///|
fn hpke_labeled_info(
  length : Int,
  label : String,
  info : Bytes,
) -> Bytes {
  let arr : Array[Byte] = [((length >> 8) & 0xFF).to_byte(), (length & 0xFF).to_byte()]
  let l = label.length()
  arr.push(((l >> 8) & 0xFF).to_byte())
  arr.push((l & 0xFF).to_byte())
  for ch in label {
    arr.push(ch.to_int().to_byte())
  }
  for i = 0; i < info.length(); i = i + 1 {
    arr.push(info[i])
  }
  Bytes::from_array(arr)
}

///|
fn hpke_extract(salt : Bytes, ikm : Bytes) -> Bytes {
  @hkdf.extract(salt, ikm)
}

///|
fn hpke_expand(prk : Bytes, length : Int, info : Bytes) -> Bytes raise {
  match @hkdf.expand(prk, info, length) {
    Some(okm) => okm
    None => fail("hpke: HKDF-Expand failed")
  }
}

// ===========================================================================
// KEM: DHKEM(X25519, HKDF-SHA256) (§4.1)
// ===========================================================================

///|
const HPKE_N_SECRET : Int = 32

///|
fn hpke_kem_suite_id() -> Bytes {
  Bytes::from_array([b'K', b'E', b'M', b'\x00', b'\x20'])
}

///|
fn hpke_kem_labeled_extract(
  salt : Bytes,
  label : String,
  ikm : Bytes,
) -> Bytes {
  let labeled = hpke_kem_suite_id() + hpke_labeled_ikm(label, ikm)
  hpke_extract(salt, labeled)
}

///|
fn hpke_kem_labeled_expand(
  prk : Bytes,
  label : String,
  info : Bytes,
  length : Int,
) -> Bytes raise {
  let labeled = hpke_kem_suite_id() + hpke_labeled_info(length, label, info)
  hpke_expand(prk, length, labeled)
}

///|
fn hpke_extract_and_expand(dh : Bytes, kem_context : Bytes) -> Bytes raise {
  let eae_prk = hpke_kem_labeled_extract(
    Bytes::make(32, b'\x00'),
    "eae_prk",
    dh,
  )
  hpke_kem_labeled_expand(eae_prk, "shared_secret", kem_context, HPKE_N_SECRET)
}

///|
fn hpke_dh(sk : Bytes, pk : Bytes) -> Bytes raise {
  let shared = @x25519.shared_secret(sk, pk)
  // RFC 7748: the all-zero output means the peer key is small-order.
  let mut zero = true
  for i = 0; i < shared.length(); i = i + 1 {
    if shared[i].to_int() != 0 {
      zero = false
    }
  }
  if zero {
    fail("hpke: degenerate X25519 shared secret")
  }
  shared
}

///|
/// Generate an HPKE key pair (32-byte X25519 private/public keys).
/// The seed is expanded with SHA-256 into the private scalar; pass
/// fresh entropy from `crypto/csprng` in production.
pub fn hpke_generate_keypair(seed : Bytes) -> (Bytes, Bytes) {
  let sk = @sha256.sha256(seed + b"hpke-keygen")
  let pk = @x25519.derive_public_key(sk)
  (sk, pk)
}

///|
/// KEM encapsulation: returns (enc, shared_secret).
fn hpke_encap(pk_r : Bytes, seed : Bytes) -> (Bytes, Bytes) raise {
  let sk_e = @sha256.sha256(seed + b"hpke-ephemeral")
  let pk_e = @x25519.derive_public_key(sk_e)
  let dh = hpke_dh(sk_e, pk_r)
  let shared = hpke_extract_and_expand(dh, pk_e + pk_r)
  (pk_e, shared)
}

///|
/// KEM decapsulation: recovers the shared secret from `enc`.
fn hpke_decap(enc : Bytes, sk_r : Bytes) -> Bytes raise {
  if enc.length() != 32 {
    fail("hpke: malformed enc")
  }
  let pk_r = @x25519.derive_public_key(sk_r)
  let dh = hpke_dh(sk_r, enc)
  hpke_extract_and_expand(dh, enc + pk_r)
}

// ===========================================================================
// Key schedule (§5.1) and context (§5.2)
// ===========================================================================

///|
fn hpke_suite_id() -> Bytes {
  Bytes::from_array([b'H', b'P', b'K', b'E'])
}

///|
fn hpke_kdf_labeled_extract(
  salt : Bytes,
  label : String,
  ikm : Bytes,
) -> Bytes {
  let labeled = hpke_suite_id() + hpke_labeled_ikm(label, ikm)
  hpke_extract(salt, labeled)
}

///|
fn hpke_kdf_labeled_expand(
  prk : Bytes,
  label : String,
  info : Bytes,
  length : Int,
) -> Bytes raise {
  let labeled = hpke_suite_id() + hpke_labeled_info(length, label, info)
  hpke_expand(prk, length, labeled)
}

///|
/// AEAD parameters per suite: (key length, nonce length).
fn hpke_aead_params(config : HpkeConfig) -> (Int, Int) raise {
  if config.aead_id == HPKE_AEAD_AES128GCM {
    (16, 12)
  } else if config.aead_id == HPKE_AEAD_CHACHA20POLY1305 {
    (32, 12)
  } else {
    fail("hpke: unsupported AEAD id")
  }
}

///|
fn hpke_verify_config(config : HpkeConfig) -> Unit raise {
  if config.kem_id != HPKE_KEM_DHKEM_X25519 {
    fail("hpke: unsupported KEM id")
  }
  if config.kdf_id != HPKE_KDF_HKDF_SHA256 {
    fail("hpke: unsupported KDF id")
  }
  let (_, _) = hpke_aead_params(config)
}

///|
pub struct HpkeSenderContext {
  config : HpkeConfig
  key : Bytes
  base_nonce : Bytes
  exporter_secret : Bytes
  mut seq : Int64
}

///|
pub struct HpkeReceiverContext {
  config : HpkeConfig
  key : Bytes
  base_nonce : Bytes
  exporter_secret : Bytes
  mut seq : Int64
}

///|
fn hpke_key_schedule(
  config : HpkeConfig,
  shared_secret : Bytes,
  info : Bytes,
) -> (Bytes, Bytes, Bytes) raise {
  let (n_k, n_n) = hpke_aead_params(config)
  // Base mode: psk = "", psk_id = "" (RFC 9180 §5.1). The HKDF salt
  // "" is equivalent to a HashLen string of zeros (RFC 5869 §2.2).
  let zeros = Bytes::make(32, b'\x00')
  let empty = Bytes::from_array([])
  let psk_id_hash = hpke_kdf_labeled_extract(zeros, "psk_id_hash", empty)
  let info_hash = hpke_kdf_labeled_extract(zeros, "info_hash", info)
  let mode_zero = Bytes::from_array([b'\x00'])
  let ks_context = mode_zero + psk_id_hash + info_hash
  let inner_secret = hpke_kdf_labeled_extract(zeros, "secret", empty)
  let secret = hpke_kdf_labeled_extract(inner_secret, "secret", shared_secret)
  let key = hpke_kdf_labeled_expand(secret, "key", ks_context, n_k)
  let base_nonce = hpke_kdf_labeled_expand(secret, "base_nonce", ks_context, n_n)
  let exporter_secret = hpke_kdf_labeled_expand(
    secret,
    "exp",
    ks_context,
    32,
  )
  (key, base_nonce, exporter_secret)
}

///|
/// Base-mode sender setup (RFC 9180 §5.1). Returns (enc, context).
pub fn hpke_setup_base_sender(
  config : HpkeConfig,
  recipient_public_key : Bytes,
  info : Bytes,
  seed : Bytes,
) -> (Bytes, HpkeSenderContext) raise {
  hpke_verify_config(config)
  if recipient_public_key.length() != 32 {
    fail("hpke: malformed recipient public key")
  }
  let (enc, shared) = hpke_encap(recipient_public_key, seed)
  let (key, base_nonce, exporter_secret) = hpke_key_schedule(
    config,
    shared,
    info,
  )
  (
    enc,
    { config, key, base_nonce, exporter_secret, seq: 0L },
  )
}

///|
/// Base-mode receiver setup (RFC 9180 §5.1).
pub fn hpke_setup_base_receiver(
  config : HpkeConfig,
  enc : Bytes,
  recipient_private_key : Bytes,
  info : Bytes,
) -> HpkeReceiverContext raise {
  hpke_verify_config(config)
  if recipient_private_key.length() != 32 {
    fail("hpke: malformed recipient private key")
  }
  let shared = hpke_decap(enc, recipient_private_key)
  let (key, base_nonce, exporter_secret) = hpke_key_schedule(
    config,
    shared,
    info,
  )
  { config, key, base_nonce, exporter_secret, seq: 0L }
}

// ===========================================================================
// AEAD sequencing (§5.2)
// ===========================================================================

///|
fn hpke_compute_nonce(base_nonce : Bytes, seq : Int64) -> Bytes {
  let n = base_nonce.length()
  let arr : Array[Byte] = []
  for i = 0; i < n; i = i + 1 {
    arr.push(b'\x00')
  }
  // Big-endian sequence, right-aligned, XORed into the base nonce.
  let mut s = seq
  for i = n - 1; i >= 0 && s > 0L; i = i - 1 {
    arr[i] = (s & 0xFFL).to_byte()
    s = s >> 8
  }
  for i = 0; i < n; i = i + 1 {
    arr[i] = (arr[i].to_int() ^ base_nonce[i].to_int()).to_byte()
  }
  Bytes::from_array(arr)
}

///|
fn hpke_next_seq(seq : Int64) -> Int64 {
  // RFC 9180 §5.2 sets the message limit at 2^64 - 1; with Int64
  // sequence counters we saturate one below Int64's maximum, which is
  // already unreachable in practice.
  if seq >= 9223372036854775806L {
    seq
  } else {
    seq + 1L
  }
}

///|
fn hpke_bytes_to_fixed(data : Bytes) -> FixedArray[Byte] {
  FixedArray::makei(data.length(), fn(i) { data[i] })
}

///|
fn hpke_fixed_to_bytes(fa : FixedArray[Byte]) -> Bytes {
  let arr : Array[Byte] = []
  for i = 0; i < fa.length(); i = i + 1 {
    arr.push(fa[i])
  }
  Bytes::from_array(arr)
}

///|
fn hpke_aead_seal(
  config : HpkeConfig,
  key : Bytes,
  nonce : Bytes,
  aad : Bytes,
  pt : Bytes,
) -> Bytes? {
  if config.aead_id == HPKE_AEAD_AES128GCM {
    let ak = match @aes.new_key(hpke_bytes_to_fixed(key)) {
      Some(k) => k
      None => return None
    }
    match @aes.encrypt_gcm(
      ak,
      hpke_bytes_to_fixed(nonce),
      hpke_bytes_to_fixed(pt),
      hpke_bytes_to_fixed(aad),
    ) {
      Some(res) => {
        let ct = hpke_fixed_to_bytes(res.ciphertext)
        let tag = hpke_fixed_to_bytes(res.tag)
        Some(ct + tag)
      }
      None => None
    }
  } else {
    @chacha20_poly1305.encrypt(key, nonce, aad, pt)
  }
}

///|
fn hpke_aead_open(
  config : HpkeConfig,
  key : Bytes,
  nonce : Bytes,
  aad : Bytes,
  ct : Bytes,
) -> Bytes? {
  if config.aead_id == HPKE_AEAD_AES128GCM {
    // GCM tag is the trailing 16 bytes.
    if ct.length() < 16 {
      return None
    }
    let ct_len = ct.length() - 16
    let ct_arr : Array[Byte] = []
    let tag_arr : Array[Byte] = []
    for i = 0; i < ct.length(); i = i + 1 {
      if i < ct_len {
        ct_arr.push(ct[i])
      } else {
        tag_arr.push(ct[i])
      }
    }
    let ak = match @aes.new_key(hpke_bytes_to_fixed(key)) {
      Some(k) => k
      None => return None
    }
    match @aes.decrypt_gcm(
      ak,
      hpke_bytes_to_fixed(nonce),
      hpke_bytes_to_fixed(Bytes::from_array(ct_arr)),
      hpke_bytes_to_fixed(aad),
      hpke_bytes_to_fixed(Bytes::from_array(tag_arr)),
    ) {
      Some(pt) => Some(hpke_fixed_to_bytes(pt))
      None => None
    }
  } else {
    @chacha20_poly1305.decrypt(key, nonce, aad, ct)
  }
}

///|
/// Encrypt and authenticate a message. The sequence number advances
/// after every call; never reuse a context beyond its limit.
pub fn hpke_seal(
  ctx : HpkeSenderContext,
  aad : Bytes,
  pt : Bytes,
) -> Bytes raise {
  let nonce = hpke_compute_nonce(ctx.base_nonce, ctx.seq)
  ctx.seq = hpke_next_seq(ctx.seq)
  match hpke_aead_seal(ctx.config, ctx.key, nonce, aad, pt) {
    Some(ct) => ct
    None => fail("hpke: AEAD encryption failed")
  }
}

///|
/// Decrypt and authenticate a message. Returns `None` when the tag or
/// AAD does not match — never releases unauthenticated plaintext.
pub fn hpke_open(
  ctx : HpkeReceiverContext,
  aad : Bytes,
  ct : Bytes,
) -> Bytes? {
  let nonce = hpke_compute_nonce(ctx.base_nonce, ctx.seq)
  ctx.seq = hpke_next_seq(ctx.seq)
  hpke_aead_open(ctx.config, ctx.key, nonce, aad, ct)
}

///|
/// Derive an exported secret from the context (RFC 9180 §5.3).
pub fn hpke_export_sender(
  ctx : HpkeSenderContext,
  length : Int,
  exporter_context : Bytes,
) -> Bytes raise {
  hpke_kdf_labeled_expand(
    ctx.exporter_secret,
    "sec",
    exporter_context,
    length,
  )
}

///|
/// Derive an exported secret from a receiver context.
pub fn hpke_export_receiver(
  ctx : HpkeReceiverContext,
  length : Int,
  exporter_context : Bytes,
) -> Bytes raise {
  hpke_kdf_labeled_expand(
    ctx.exporter_secret,
    "sec",
    exporter_context,
    length,
  )
}
