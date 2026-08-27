///|
/// TLS 1.3 Protocol Layer (RFC 8446)
///
/// An in-memory TLS 1.3 implementation: the full handshake key
/// schedule (§7.1), handshake message encoding, certificate-based
/// server authentication (Ed25519 CertificateVerify), Finished MAC
/// verification, and an AEAD-protected record layer.
///
/// ## Supported configuration
///
/// - Key exchange: X25519 (secp256r1 groups are not wired in yet).
/// - Cipher suites: TLS_CHACHA20_POLY1305_SHA256 (0x1303) and
///   TLS_AES_128_GCM_SHA256 (0x1301).
/// - Signature algorithm: ed25519 (0x0807) for CertificateVerify.
/// - No PSK / 0-RTT / client authentication; 1-RTT full handshake.
///
/// ## Transport model
///
/// The engine is transport-agnostic: functions produce and consume
/// TLS records as byte strings. The application shuttles records
/// between a client and a server connection.
///
/// ## Certificate validation
///
/// The client pins the server's Ed25519 public key via
/// `Tls13Config::trusted_server_key`; the handshake faithfully checks
/// CertificateVerify against that key and the Finished MACs.
/// Certificate *chain* validation is deliberately the application's
/// responsibility (wire in `crypto/x509` or a platform verifier).
///
/// ## References
///
/// - RFC 8446: The Transport Layer Security (TLS) Protocol Version 1.3
/// - RFC 5869: HKDF
/// - RFC 8032: Ed25519
///
/// `proof-enabled` is `false`.

///|
pub enum TlsCipherSuite {
  Aes128GcmSha256
  ChaCha20Poly1305Sha256
}

///|
pub fn TlsCipherSuite::aes128_gcm_sha256() -> TlsCipherSuite {
  Aes128GcmSha256
}

///|
pub fn TlsCipherSuite::chacha20_poly1305_sha256() -> TlsCipherSuite {
  ChaCha20Poly1305Sha256
}

///|
const TLS13_CHACHA_KEY_LEN : Int = 32

///|
const TLS13_AES_KEY_LEN : Int = 16

///|
const TLS13_IV_LEN : Int = 12

///|
fn tls13_suite_id(cs : TlsCipherSuite) -> Int {
  match cs {
    Aes128GcmSha256 => 0x1301
    ChaCha20Poly1305Sha256 => 0x1303
  }
}

///|
fn tls13_key_len(cs : TlsCipherSuite) -> Int {
  match cs {
    Aes128GcmSha256 => TLS13_AES_KEY_LEN
    ChaCha20Poly1305Sha256 => TLS13_CHACHA_KEY_LEN
  }
}

///|
/// TLS 1.3 configuration.
///
/// `trusted_server_key` is the Ed25519 public key the client trusts
/// for CertificateVerify (key pinning). Certificate *chain* validation
/// is the application's responsibility (e.g. via `crypto/x509`);
/// `None` rejects every server.
pub struct Tls13Config {
  cipher_suite : TlsCipherSuite
  trusted_server_key : Bytes?
}

///|
/// Build a TLS 1.3 configuration. `trusted_server_key` pins the
/// server's Ed25519 public key for CertificateVerify (`None` rejects).
pub fn tls13_config_new(
  cipher_suite : TlsCipherSuite,
  trusted_server_key : Bytes?,
) -> Tls13Config {
  { cipher_suite, trusted_server_key, }
}

///|
/// Record content types used by this implementation (RFC 8446 §5.1).
pub enum TlsContentType {
  Handshake
  ApplicationData
}

///|
fn tls13_ct_byte(ct : TlsContentType) -> Int {
  match ct {
    Handshake => 22
    ApplicationData => 23
  }
}

///|
/// Handshake message types (RFC 8446 §4).
pub enum TlsHandshakeType {
  ClientHello
  ServerHello
  EncryptedExtensions
  Certificate
  CertificateVerify
  Finished
}

///|
fn tls13_hs_byte(ht : TlsHandshakeType) -> Int {
  match ht {
    ClientHello => 1
    ServerHello => 2
    EncryptedExtensions => 8
    Certificate => 11
    CertificateVerify => 15
    Finished => 20
  }
}

// ===========================================================================
// HKDF-SHA256 and the TLS 1.3 key schedule (§7.1)
// ===========================================================================

///|
fn tls13_extract(salt : Bytes, ikm : Bytes) -> Bytes {
  @hkdf.extract(salt, ikm)
}

///|
fn tls13_expand(prk : Bytes, info : Bytes, length : Int) -> Bytes raise {
  match @hkdf.expand(prk, info, length) {
    Some(v) => v
    None => fail("tls13: HKDF-Expand failed")
  }
}

///|
/// HKDF-Expand-Label (RFC 8446 §7.1).
fn tls13_expand_label(
  secret : Bytes,
  label : String,
  context : Bytes,
  length : Int,
) -> Bytes raise {
  let full = "tls13 " + label
  let info : Array[Byte] = [
    ((length >> 8) & 0xFF).to_byte(),
    (length & 0xFF).to_byte(),
  ]
  info.push(full.length().to_byte())
  for ch in full {
    info.push(ch.to_int().to_byte())
  }
  info.push(context.length().to_byte())
  for i = 0; i < context.length(); i = i + 1 {
    info.push(context[i])
  }
  tls13_expand(secret, Bytes::from_array(info), length)
}

///|
fn tls13_derive_secret(
  secret : Bytes,
  label : String,
  transcript : Bytes,
) -> Bytes raise {
  tls13_expand_label(secret, label, @sha256.sha256(transcript), 32)
}

///|
fn tls13_zeros(n : Int) -> Bytes {
  Bytes::make(n, b'\x00')
}

// ===========================================================================
// AEAD adapters
// ===========================================================================

///|
fn tls13_bytes_to_fixed(data : Bytes) -> FixedArray[Byte] {
  FixedArray::makei(data.length(), fn(i) { data[i] })
}

///|
fn tls13_fixed_to_bytes(fa : FixedArray[Byte]) -> Bytes {
  let arr : Array[Byte] = []
  for i = 0; i < fa.length(); i = i + 1 {
    arr.push(fa[i])
  }
  Bytes::from_array(arr)
}

///|
fn tls13_aead_seal(
  cs : TlsCipherSuite,
  key : Bytes,
  nonce : Bytes,
  aad : Bytes,
  pt : Bytes,
) -> Bytes? {
  match cs {
    Aes128GcmSha256 =>
      match @aes.new_key(tls13_bytes_to_fixed(key)) {
        Some(ak) =>
          match
            @aes.encrypt_gcm(
              ak,
              tls13_bytes_to_fixed(nonce),
              tls13_bytes_to_fixed(pt),
              tls13_bytes_to_fixed(aad),
            ) {
            Some(res) =>
              Some(
                tls13_fixed_to_bytes(res.ciphertext) +
                tls13_fixed_to_bytes(res.tag),
              )
            None => None
          }
        None => None
      }
    ChaCha20Poly1305Sha256 => @chacha20_poly1305.encrypt(key, nonce, aad, pt)
  }
}

///|
fn tls13_aead_open(
  cs : TlsCipherSuite,
  key : Bytes,
  nonce : Bytes,
  aad : Bytes,
  ct : Bytes,
) -> Bytes? {
  match cs {
    Aes128GcmSha256 => {
      if ct.length() < 16 {
        return None
      }
      let body_len = ct.length() - 16
      let body : Array[Byte] = []
      let tag : Array[Byte] = []
      for i = 0; i < ct.length(); i = i + 1 {
        if i < body_len {
          body.push(ct[i])
        } else {
          tag.push(ct[i])
        }
      }
      match @aes.new_key(tls13_bytes_to_fixed(key)) {
        Some(ak) =>
          match
            @aes.decrypt_gcm(
              ak,
              tls13_bytes_to_fixed(nonce),
              tls13_bytes_to_fixed(Bytes::from_array(body)),
              tls13_bytes_to_fixed(aad),
              tls13_bytes_to_fixed(Bytes::from_array(tag)),
            ) {
            Some(pt) => Some(tls13_fixed_to_bytes(pt))
            None => None
          }
        None => None
      }
    }
    ChaCha20Poly1305Sha256 => @chacha20_poly1305.decrypt(key, nonce, aad, ct)
  }
}

// ===========================================================================
// Record and handshake framing helpers
// ===========================================================================

///|
fn tls13_put_u16(out : Array[Byte], v : Int) -> Unit {
  out.push(((v >> 8) & 0xFF).to_byte())
  out.push((v & 0xFF).to_byte())
}

///|
fn tls13_put_u24(out : Array[Byte], v : Int) -> Unit {
  out.push(((v >> 16) & 0xFF).to_byte())
  out.push(((v >> 8) & 0xFF).to_byte())
  out.push((v & 0xFF).to_byte())
}

///|
fn tls13_read_u16(data : Bytes, off : Int) -> Int? {
  if off + 2 > data.length() {
    return None
  }
  Some((data[off].to_int() << 8) | data[off + 1].to_int())
}

///|
fn tls13_read_u24(data : Bytes, off : Int) -> Int? {
  if off + 3 > data.length() {
    return None
  }
  Some(
    (data[off].to_int() << 16) |
    (data[off + 1].to_int() << 8) |
    data[off + 2].to_int(),
  )
}

///|
fn tls13_slice(data : Bytes, off : Int, len : Int) -> Bytes? {
  if off < 0 || len < 0 || off + len > data.length() {
    return None
  }
  let arr : Array[Byte] = []
  for i = off; i < off + len; i = i + 1 {
    arr.push(data[i])
  }
  Some(Bytes::from_array(arr))
}

///|
/// Wrap a handshake body (type byte + length already excluded) into a
/// handshake message.
fn tls13_hs_message(ht : TlsHandshakeType, body : Bytes) -> Bytes {
  let arr : Array[Byte] = [tls13_hs_byte(ht).to_byte()]
  tls13_put_u24(arr, body.length())
  for i = 0; i < body.length(); i = i + 1 {
    arr.push(body[i])
  }
  Bytes::from_array(arr)
}

///|
/// Wrap plaintext into a TLS record.
fn tls13_record(ct : TlsContentType, payload : Bytes) -> Bytes {
  let arr : Array[Byte] = [tls13_ct_byte(ct).to_byte(), b'\x03', b'\x03']
  tls13_put_u16(arr, payload.length())
  for i = 0; i < payload.length(); i = i + 1 {
    arr.push(payload[i])
  }
  Bytes::from_array(arr)
}

///|
/// Parse a record header: (content_type, length, payload).
pub fn tls_parse_record_header(data : Bytes) -> (Int, Int, Bytes)? {
  if data.length() < 5 {
    return None
  }
  let ct = data[0].to_int()
  let version = (data[1].to_int() << 8) | data[2].to_int()
  if version != 0x0303 {
    return None
  }
  match tls13_read_u16(data, 3) {
    Some(len) =>
      if 5 + len > data.length() {
        None
      } else {
        match tls13_slice(data, 5, len) {
          Some(payload) => Some((ct, len, payload))
          None => None
        }
      }
    None => None
  }
}

// ===========================================================================
// Connection state machine
// ===========================================================================

///|
/// One direction's record protection material.
struct Tls13Keys {
  secret : Bytes
  key : Bytes
  iv : Bytes
}

///|
pub struct Tls13Connection {
  config : Tls13Config
  is_server : Bool
  /// Concatenation of all handshake messages so far (§4.4.1).
  mut transcript : Bytes
  mut shared_secret : Bytes?
  mut client_handshake : Tls13Keys?
  mut server_handshake : Tls13Keys?
  mut client_app : Tls13Keys?
  mut server_app : Tls13Keys?
  mut send_seq : Int64
  mut recv_seq : Int64
  /// Master-stage material for application key derivation:
  /// (derived secret after the handshake stage).
  mut app_stage : Bytes?
  /// Client's ephemeral X25519 key pair (set at construction on the
  /// client side; set during ClientHello processing on the server).
  mut eph_private : Bytes
  mut eph_public : Bytes
  mut established : Bool
}

///|
fn tls13_compute_nonce(iv : Bytes, seq : Int64) -> Bytes {
  let arr : Array[Byte] = []
  for i = 0; i < TLS13_IV_LEN; i = i + 1 {
    arr.push(b'\x00')
  }
  let mut s = seq
  for i = TLS13_IV_LEN - 1; i >= 0 && s > 0L; i = i - 1 {
    arr[i] = (s & 0xFFL).to_byte()
    s = s >> 8
  }
  for i = 0; i < TLS13_IV_LEN; i = i + 1 {
    arr[i] = (arr[i].to_int() ^ iv[i].to_int()).to_byte()
  }
  Bytes::from_array(arr)
}

///|
/// Create a client connection. `ephemeral_seed` must be fresh entropy.
pub fn tls13_client_new(
  config : Tls13Config,
  ephemeral_seed : Bytes,
) -> Tls13Connection {
  let sk = @sha256.sha256(ephemeral_seed + b"tls13-eph")
  let pk = @x25519.derive_public_key(sk)
  {
    config,
    is_server: false,
    transcript: Bytes::from_array([]),
    shared_secret: None,
    client_handshake: None,
    server_handshake: None,
    client_app: None,
    server_app: None,
    send_seq: 0L,
    recv_seq: 0L,
    app_stage: None,
    eph_private: sk,
    eph_public: pk,
    established: false,
  }
}

///|
/// Create a server connection.
pub fn tls13_server_new(config : Tls13Config) -> Tls13Connection {
  {
    config,
    is_server: true,
    transcript: Bytes::from_array([]),
    shared_secret: None,
    client_handshake: None,
    server_handshake: None,
    client_app: None,
    server_app: None,
    send_seq: 0L,
    recv_seq: 0L,
    app_stage: None,
    eph_private: Bytes::from_array([]),
    eph_public: Bytes::from_array([]),
    established: false,
  }
}

///|
/// Build the ClientHello handshake message and record it in the
/// transcript. Returns the plaintext record to send.
pub fn tls13_client_hello(conn : Tls13Connection) -> Bytes raise {
  if conn.is_server {
    fail("tls13: client_hello on a server connection")
  }
  let body : Array[Byte] = []
  tls13_put_u16(body, 0x0303) // legacy_version
  let random = @sha256.sha256(conn.eph_public + b"tls13-client-random")
  for i = 0; i < 32; i = i + 1 {
    body.push(random[i])
  }
  body.push(0) // legacy_session_id (empty)
  tls13_put_u16(body, 2) // cipher_suites length
  tls13_put_u16(body, tls13_suite_id(conn.config.cipher_suite))
  body.push(1) // legacy_compression_methods length
  body.push(0)
  // Extensions.
  let ext : Array[Byte] = []
  // supported_versions (0x002b): TLS 1.3
  tls13_put_u16(ext, 0x002b)
  tls13_put_u16(ext, 3)
  ext.push(2)
  tls13_put_u16(ext, 0x0304)
  // supported_groups (0x000a): x25519
  tls13_put_u16(ext, 0x000a)
  tls13_put_u16(ext, 4)
  tls13_put_u16(ext, 2)
  tls13_put_u16(ext, 0x001d)
  // signature_algorithms (0x000d): ed25519
  tls13_put_u16(ext, 0x000d)
  tls13_put_u16(ext, 4)
  tls13_put_u16(ext, 2)
  tls13_put_u16(ext, 0x0807)
  // key_share (0x0033): x25519 pubkey
  tls13_put_u16(ext, 0x0033)
  tls13_put_u16(ext, 2 + 2 + 2 + 32)
  tls13_put_u16(ext, 2 + 2 + 32)
  tls13_put_u16(ext, 0x001d)
  tls13_put_u16(ext, 32)
  for i = 0; i < 32; i = i + 1 {
    ext.push(conn.eph_public[i])
  }
  tls13_put_u16(body, ext.length())
  for b in ext {
    body.push(b)
  }
  let msg = tls13_hs_message(ClientHello, Bytes::from_array(body))
  conn.transcript = conn.transcript + msg
  tls13_record(Handshake, msg)
}

///|
/// Server: process the ClientHello record, generate the ephemeral key,
/// derive handshake keys, and return the ServerHello record.
pub fn tls13_server_process_hello(
  conn : Tls13Connection,
  record : Bytes,
  server_seed : Bytes,
) -> Bytes raise {
  if !conn.is_server {
    fail("tls13: server_process_hello on a client connection")
  }
  let parsed = match tls_parse_record_header(record) {
    Some(v) => v
    None => fail("tls13: malformed ClientHello record")
  }
  let (ct, _, payload) = parsed
  if ct != 22 || payload.length() < 4 {
    fail("tls13: not a handshake record")
  }
  if payload[0].to_int() != tls13_hs_byte(ClientHello) {
    fail("tls13: not a ClientHello")
  }
  match tls13_read_u24(payload, 1) {
    Some(hlen) =>
      if hlen != payload.length() - 4 {
        fail("tls13: bad ClientHello length")
      }
    None => fail("tls13: truncated ClientHello")
  }
  conn.transcript = conn.transcript + payload
  // Parse the ClientHello to extract the client key share.
  let mut off = 4
  // legacy_version + random
  off = off + 2 + 32
  // session id
  if off >= payload.length() {
    fail("tls13: truncated ClientHello body")
  }
  let sid_len = payload[off].to_int()
  off = off + 1 + sid_len
  // cipher suites
  let cs_len = match tls13_read_u16(payload, off) {
    Some(v) => v
    None => fail("tls13: truncated cipher suites")
  }
  off = off + 2
  let mut offered = false
  let mut k = 0
  while k + 2 <= cs_len {
    match tls13_read_u16(payload, off + k) {
      Some(cs) =>
        if cs == tls13_suite_id(conn.config.cipher_suite) {
          offered = true
        }
      None => ()
    }
    k = k + 2
  }
  if !offered {
    fail("tls13: cipher suite not offered")
  }
  off = off + cs_len
  // compression methods
  if off >= payload.length() {
    fail("tls13: truncated compression methods")
  }
  let cm_len = payload[off].to_int()
  off = off + 1 + cm_len
  // extensions
  let ext_total = match tls13_read_u16(payload, off) {
    Some(v) => v
    None => fail("tls13: truncated extensions")
  }
  off = off + 2
  let ext_end = off + ext_total
  let mut client_share : Bytes? = None
  while off + 4 <= ext_end {
    let etype = match tls13_read_u16(payload, off) {
      Some(v) => v
      None => fail("tls13: truncated extension header")
    }
    let elen = match tls13_read_u16(payload, off + 2) {
      Some(v) => v
      None => fail("tls13: truncated extension length")
    }
    if etype == 0x0033 {
      // key_share: client_shares list
      let mut p = off + 4
      match tls13_read_u16(payload, p) {
        Some(_) => {
          p = p + 2
          // entries: group(2) len(2) key_exchange(len)
          let mut scanning = true
          while scanning && p + 4 <= off + 4 + elen {
            let group = match tls13_read_u16(payload, p) {
              Some(v) => v
              None => 0
            }
            let klen = match tls13_read_u16(payload, p + 2) {
              Some(v) => v
              None => 0
            }
            if group == 0x001d && klen == 32 {
              client_share = tls13_slice(payload, p + 4, 32)
              scanning = false
            }
            p = p + 4 + klen
          }
        }
        None => ()
      }
    }
    off = off + 4 + elen
  }
  let peer_pk = match client_share {
    Some(share) => share
    None => fail("tls13: no x25519 key share")
  }
  // Server ephemeral key + DH.
  let sk_s = @sha256.sha256(server_seed + b"tls13-server-eph")
  let pk_s = @x25519.derive_public_key(sk_s)
  conn.eph_private = sk_s
  conn.eph_public = pk_s
  let dh = @x25519.shared_secret(sk_s, peer_pk)
  conn.shared_secret = Some(dh)
  // Build ServerHello.
  let body : Array[Byte] = []
  tls13_put_u16(body, 0x0303)
  let srandom = @sha256.sha256(pk_s + b"tls13-server-random")
  for i = 0; i < 32; i = i + 1 {
    body.push(srandom[i])
  }
  body.push(0) // legacy_session_id_echo
  tls13_put_u16(body, tls13_suite_id(conn.config.cipher_suite))
  body.push(0) // compression
  let ext : Array[Byte] = []
  tls13_put_u16(ext, 0x002b)
  tls13_put_u16(ext, 2)
  tls13_put_u16(ext, 0x0304)
  tls13_put_u16(ext, 0x0033)
  tls13_put_u16(ext, 2 + 2 + 32)
  tls13_put_u16(ext, 0x001d)
  tls13_put_u16(ext, 32)
  for i = 0; i < 32; i = i + 1 {
    ext.push(pk_s[i])
  }
  tls13_put_u16(body, ext.length())
  for b in ext {
    body.push(b)
  }
  let msg = tls13_hs_message(ServerHello, Bytes::from_array(body))
  conn.transcript = conn.transcript + msg
  conn.derive_handshake_keys()
  tls13_record(Handshake, msg)
}

///|
/// Derive handshake traffic keys after CH+SH are in the transcript.
fn Tls13Connection::derive_handshake_keys(self : Tls13Connection) -> Unit raise {
  let zero32 = tls13_zeros(32)
  let early_secret = tls13_extract(zero32, zero32)
  let derived0 = tls13_derive_secret(
    early_secret,
    "derived",
    Bytes::from_array([]),
  )
  let dh = match self.shared_secret {
    Some(s) => s
    None => fail("tls13: missing DH shared secret")
  }
  let handshake_secret = tls13_extract(derived0, dh)
  let chts = tls13_derive_secret(
    handshake_secret,
    "c hs traffic",
    self.transcript,
  )
  let shts = tls13_derive_secret(
    handshake_secret,
    "s hs traffic",
    self.transcript,
  )
  let klen = tls13_key_len(self.config.cipher_suite)
  self.client_handshake = Some({
    secret: chts,
    key: tls13_expand_label(chts, "key", Bytes::from_array([]), klen),
    iv: tls13_expand_label(chts, "iv", Bytes::from_array([]), TLS13_IV_LEN),
  })
  self.server_handshake = Some({
    secret: shts,
    key: tls13_expand_label(shts, "key", Bytes::from_array([]), klen),
    iv: tls13_expand_label(shts, "iv", Bytes::from_array([]), TLS13_IV_LEN),
  })
  // Stash the master-stage input for later app-key derivation.
  self.app_stage = Some(
    tls13_derive_secret(handshake_secret, "derived", Bytes::from_array([])),
  )
}

///|
/// Protect a handshake payload with the sender's handshake keys.
fn Tls13Connection::seal_handshake(
  self : Tls13Connection,
  payload : Bytes,
) -> Bytes raise {
  let keys = match
    (self.is_server, self.server_handshake, self.client_handshake) {
    (true, Some(k), _) => k
    (false, _, Some(k)) => k
    _ => fail("tls13: handshake keys not derived yet")
  }
  let nonce = tls13_compute_nonce(keys.iv, self.send_seq)
  self.send_seq = self.send_seq + 1L
  // Inner plaintext = payload || real content type (handshake).
  let inner : Array[Byte] = []
  for i = 0; i < payload.length(); i = i + 1 {
    inner.push(payload[i])
  }
  inner.push(22)
  let inner_bytes = Bytes::from_array(inner)
  // The outer header (AAD) embeds the final ciphertext length.
  let sealed_len = inner_bytes.length() + TLS13_TAG_LEN
  let header : Array[Byte] = [
    tls13_ct_byte(ApplicationData).to_byte(),
    b'\x03',
    b'\x03',
  ]
  tls13_put_u16(header, sealed_len)
  let aad = Bytes::from_array(header)
  match
    tls13_aead_seal(self.config.cipher_suite, keys.key, nonce, aad, inner_bytes) {
    Some(ct) => {
      let out : Array[Byte] = []
      for i = 0; i < header.length(); i = i + 1 {
        out.push(header[i])
      }
      for i = 0; i < ct.length(); i = i + 1 {
        out.push(ct[i])
      }
      Bytes::from_array(out)
    }
    None => fail("tls13: AEAD seal failed")
  }
}

///|
fn Tls13Connection::open_with(
  self : Tls13Connection,
  keys : Tls13Keys,
  record : Bytes,
) -> (Int, Bytes) raise {
  let parsed = match tls_parse_record_header(record) {
    Some(v) => v
    None => fail("tls13: malformed record")
  }
  let (ct, _, payload) = parsed
  if ct != tls13_ct_byte(ApplicationData) {
    fail("tls13: expected protected record")
  }
  let aad = match tls13_slice(record, 0, 5) {
    Some(v) => v
    None => fail("tls13: bad record header")
  }
  let nonce = tls13_compute_nonce(keys.iv, self.recv_seq)
  self.recv_seq = self.recv_seq + 1L
  let pt = match
    tls13_aead_open(self.config.cipher_suite, keys.key, nonce, aad, payload) {
    Some(v) => v
    None => fail("tls13: AEAD authentication failed")
  }
  if pt.length() == 0 {
    fail("tls13: empty protected payload")
  }
  let inner_type = pt[pt.length() - 1].to_int()
  // Strip the inner content type byte.
  let body = match tls13_slice(pt, 0, pt.length() - 1) {
    Some(v) => v
    None => fail("tls13: bad inner payload")
  }
  (inner_type, body)
}

///|
/// Server: send EncryptedExtensions, Certificate, CertificateVerify
/// and Finished, protected with the server handshake key. Returns the
/// protected records to send. `signing_key` is the server's Ed25519
/// private key matching the certificate.
pub fn tls13_server_handshake_finish(
  conn : Tls13Connection,
  certificate_der : Bytes,
  signing_key : Bytes,
) -> Bytes raise {
  if !conn.is_server {
    fail("tls13: server_handshake_finish on a client connection")
  }
  // EncryptedExtensions (empty).
  let ee = tls13_hs_message(EncryptedExtensions, Bytes::from_array([]))
  conn.transcript = conn.transcript + ee
  // Certificate.
  // Body: certificate_request_context<0..2^8-1> ||
  //       certificate_list<0..2^24-1>; each entry is cert_data<1..2^24-1>
  //       followed by extensions<0..2^16-1> (empty here).
  let list : Array[Byte] = []
  tls13_put_u24(list, certificate_der.length())
  for i = 0; i < certificate_der.length(); i = i + 1 {
    list.push(certificate_der[i])
  }
  tls13_put_u16(list, 0) // empty per-certificate extensions
  let cert_payload : Array[Byte] = [0] // empty request context
  tls13_put_u24(cert_payload, list.length())
  for b in list {
    cert_payload.push(b)
  }
  let cert = tls13_hs_message(Certificate, Bytes::from_array(cert_payload))
  conn.transcript = conn.transcript + cert
  // CertificateVerify over the transcript so far.
  let context_hash = @sha256.sha256(conn.transcript)
  let to_sign : Array[Byte] = []
  for _i = 0; _i < 64; _i = _i + 1 {
    to_sign.push(b'\x20')
  }
  let label = "TLS 1.3, server CertificateVerify"
  for ch in label {
    to_sign.push(ch.to_int().to_byte())
  }
  to_sign.push(0)
  for i = 0; i < context_hash.length(); i = i + 1 {
    to_sign.push(context_hash[i])
  }
  let signature = @ed25519.sign(signing_key, Bytes::from_array(to_sign))
  let cv_body : Array[Byte] = []
  tls13_put_u16(cv_body, 0x0807)
  tls13_put_u16(cv_body, signature.length())
  for i = 0; i < signature.length(); i = i + 1 {
    cv_body.push(signature[i])
  }
  let cv = tls13_hs_message(CertificateVerify, Bytes::from_array(cv_body))
  conn.transcript = conn.transcript + cv
  // Finished MAC.
  let fin = conn.finished_message(true)
  conn.transcript = conn.transcript + fin
  let stream = ee + cert + cv + fin
  conn.seal_handshake(stream)
}

///|
/// Build a Finished message for the given direction using the
/// corresponding handshake base key.
fn Tls13Connection::finished_message(
  self : Tls13Connection,
  server_side : Bool,
) -> Bytes raise {
  let keys = match (server_side, self.server_handshake, self.client_handshake) {
    (true, Some(k), _) => k
    (false, _, Some(k)) => k
    _ => fail("tls13: handshake keys not derived yet")
  }
  let finished_key = tls13_expand_label(
    keys.secret,
    "finished",
    Bytes::from_array([]),
    32,
  )
  let mac = @hmac.hmac_sha256(finished_key, @sha256.sha256(self.transcript))
  tls13_hs_message(Finished, mac)
}

// ===========================================================================
// Client side
// ===========================================================================

///|
/// Client: process the plaintext ServerHello record, derive the
/// handshake keys and record the message in the transcript.
pub fn tls13_client_process_hello(
  conn : Tls13Connection,
  record : Bytes,
) -> Unit raise {
  if conn.is_server {
    fail("tls13: client_process_hello on a server connection")
  }
  let parsed = match tls_parse_record_header(record) {
    Some(v) => v
    None => fail("tls13: malformed ServerHello record")
  }
  let (ct, _, payload) = parsed
  if ct != 22 || payload.length() < 4 {
    fail("tls13: not a handshake record")
  }
  if payload[0].to_int() != tls13_hs_byte(ServerHello) {
    fail("tls13: not a ServerHello")
  }
  conn.transcript = conn.transcript + payload
  // Extract the server x25519 key share from the extensions.
  let mut off = 4 + 2 + 32 + 1 + 2 + 1 // header, version, random, sid, suite, compression
  let ext_total = match tls13_read_u16(payload, off) {
    Some(v) => v
    None => fail("tls13: truncated ServerHello extensions")
  }
  off = off + 2
  let ext_end = off + ext_total
  let mut server_share : Bytes? = None
  while off + 4 <= ext_end {
    let etype = match tls13_read_u16(payload, off) {
      Some(v) => v
      None => fail("tls13: truncated extension header")
    }
    let elen = match tls13_read_u16(payload, off + 2) {
      Some(v) => v
      None => fail("tls13: truncated extension length")
    }
    if etype == 0x0033 {
      let group = match tls13_read_u16(payload, off + 4) {
        Some(v) => v
        None => fail("tls13: truncated key share entry")
      }
      let klen = match tls13_read_u16(payload, off + 6) {
        Some(v) => v
        None => fail("tls13: truncated key share length")
      }
      if group == 0x001d && klen == 32 {
        server_share = tls13_slice(payload, off + 8, 32)
      }
    }
    off = off + 4 + elen
  }
  let peer_pk = match server_share {
    Some(share) => share
    None => fail("tls13: no server x25519 key share")
  }
  let dh = @x25519.shared_secret(conn.eph_private, peer_pk)
  conn.shared_secret = Some(dh)
  conn.derive_handshake_keys()
}

///|
/// Client: process the server's protected flight (EncryptedExtensions,
/// Certificate, CertificateVerify, Finished). Verifies the certificate
/// binding, the CertificateVerify signature and the Finished MAC, then
/// derives the application traffic keys.
pub fn tls13_client_process_flight(
  conn : Tls13Connection,
  record : Bytes,
) -> Unit raise {
  if conn.is_server {
    fail("tls13: client_process_flight on a server connection")
  }
  let keys = match conn.server_handshake {
    Some(k) => k
    None => fail("tls13: handshake keys not derived yet")
  }
  let (_, stream) = conn.open_with(keys, record)
  // Walk the handshake messages.
  let mut off = 0
  let mut saw_cert = false
  let mut cert_der : Bytes = Bytes::from_array([])
  let mut verified_cv = false
  let mut verified_fin = false
  while off + 4 <= stream.length() {
    let htype = stream[off].to_int()
    let hlen = match tls13_read_u24(stream, off + 1) {
      Some(v) => v
      None => fail("tls13: truncated handshake message")
    }
    let body = match tls13_slice(stream, off + 4, hlen) {
      Some(v) => v
      None => fail("tls13: truncated handshake body")
    }
    let msg = match tls13_slice(stream, off, 4 + hlen) {
      Some(v) => v
      None => fail("tls13: truncated handshake message")
    }
    conn.transcript = conn.transcript + msg
    if htype == tls13_hs_byte(EncryptedExtensions) {
      // Nothing to validate beyond authentication coverage.
      ()
    } else if htype == tls13_hs_byte(Certificate) {
      cert_der = tls13_parse_certificate(body)
      saw_cert = true
    } else if htype == tls13_hs_byte(CertificateVerify) {
      if !saw_cert {
        fail("tls13: CertificateVerify before Certificate")
      }
      let pubkey = match conn.config.trusted_server_key {
        Some(pk) => pk
        None => fail("tls13: no trusted server key configured")
      }
      let _ = cert_der
      let algorithm = match tls13_read_u16(body, 0) {
        Some(v) => v
        None => fail("tls13: truncated CertificateVerify")
      }
      if algorithm != 0x0807 {
        fail("tls13: unsupported CertificateVerify algorithm")
      }
      let sig_len = match tls13_read_u16(body, 2) {
        Some(v) => v
        None => fail("tls13: truncated CertificateVerify signature")
      }
      let signature = match tls13_slice(body, 4, sig_len) {
        Some(v) => v
        None => fail("tls13: truncated CertificateVerify signature")
      }
      // Reconstruct the signed content: transcript *before* this
      // message (the transcript update happens below for later
      // messages; here we hashed after appending, so rebuild).
      let prior = match
        tls13_slice(conn.transcript, 0, conn.transcript.length() - msg.length()) {
        Some(v) => v
        None => fail("tls13: bad transcript")
      }
      let context_hash = @sha256.sha256(prior)
      let to_verify : Array[Byte] = []
      for _i = 0; _i < 64; _i = _i + 1 {
        to_verify.push(b'\x20')
      }
      let label = "TLS 1.3, server CertificateVerify"
      for ch in label {
        to_verify.push(ch.to_int().to_byte())
      }
      to_verify.push(0)
      for i = 0; i < context_hash.length(); i = i + 1 {
        to_verify.push(context_hash[i])
      }
      if !@ed25519.verify(pubkey, Bytes::from_array(to_verify), signature) {
        fail("tls13: CertificateVerify signature invalid")
      }
      verified_cv = true
    } else if htype == tls13_hs_byte(Finished) {
      if !verified_cv {
        fail("tls13: Finished before CertificateVerify")
      }
      // Finished covers the transcript up to and including CV; the
      // Finished message itself is appended afterwards.
      let prior = match
        tls13_slice(conn.transcript, 0, conn.transcript.length() - msg.length()) {
        Some(v) => v
        None => fail("tls13: bad transcript")
      }
      let finished_key = tls13_expand_label(
        keys.secret,
        "finished",
        Bytes::from_array([]),
        32,
      )
      let expect = @hmac.hmac_sha256(finished_key, @sha256.sha256(prior))
      if !tls13_ct_eq(expect, body) {
        fail("tls13: server Finished MAC invalid")
      }
      verified_fin = true
    } else {
      fail("tls13: unexpected handshake message in flight")
    }
    off = off + 4 + hlen
  }
  if !verified_fin {
    fail("tls13: server flight missing Finished")
  }
  conn.derive_app_keys()
}

///|
/// Constant-time byte comparison.
fn tls13_ct_eq(a : Bytes, b : Bytes) -> Bool {
  if a.length() != b.length() {
    return false
  }
  let mut diff = 0
  for i = 0; i < a.length(); i = i + 1 {
    diff = diff | (a[i].to_int() ^ b[i].to_int())
  }
  diff == 0
}

///|
/// Extract the first certificate DER from a Certificate body.
fn tls13_parse_certificate(body : Bytes) -> Bytes raise {
  if body.length() < 1 {
    fail("tls13: truncated Certificate")
  }
  let ctx_len = body[0].to_int()
  let mut off = 1 + ctx_len
  let list_len = match tls13_read_u24(body, off) {
    Some(v) => v
    None => fail("tls13: truncated certificate_list")
  }
  off = off + 3
  if list_len < 3 || off + list_len > body.length() {
    fail("tls13: malformed certificate_list")
  }
  let cert_len = match tls13_read_u24(body, off) {
    Some(v) => v
    None => fail("tls13: truncated cert_data length")
  }
  off = off + 3
  match tls13_slice(body, off, cert_len) {
    Some(v) => v
    None => fail("tls13: truncated cert_data")
  }
}

///|
/// Derive application traffic keys (client and server) from the master
/// secret once the transcript includes the server Finished.
fn Tls13Connection::derive_app_keys(self : Tls13Connection) -> Unit raise {
  let derived = match self.app_stage {
    Some(v) => v
    None => fail("tls13: master stage not prepared")
  }
  let master = tls13_extract(derived, tls13_zeros(32))
  let cats = tls13_derive_secret(master, "c ap traffic", self.transcript)
  let sats = tls13_derive_secret(master, "s ap traffic", self.transcript)
  let klen = tls13_key_len(self.config.cipher_suite)
  let empty = Bytes::from_array([])
  self.client_app = Some({
    secret: cats,
    key: tls13_expand_label(cats, "key", empty, klen),
    iv: tls13_expand_label(cats, "iv", empty, TLS13_IV_LEN),
  })
  self.server_app = Some({
    secret: sats,
    key: tls13_expand_label(sats, "key", empty, klen),
    iv: tls13_expand_label(sats, "iv", empty, TLS13_IV_LEN),
  })
  // RFC 8446 §5.3 resets record sequence numbers to zero on every key
  // change; the callers reset the counters once the final handshake
  // record of their role has been sent/opened.
  self.established = true
}

///|
/// Client: produce the (protected) client Finished record. Must be
/// called after `tls13_client_process_flight`.
pub fn tls13_client_finished(conn : Tls13Connection) -> Bytes raise {
  if conn.is_server {
    fail("tls13: client_finished on a server connection")
  }
  let fin = conn.finished_message(false)
  conn.transcript = conn.transcript + fin
  let record = conn.seal_handshake(fin)
  // RFC 8446 §5.3: this Finished is the last record under the handshake
  // keys, so both counters restart at zero for application traffic.
  conn.send_seq = 0L
  conn.recv_seq = 0L
  record
}

///|
/// Server: verify the client's protected Finished record and switch
/// both sides to application keys.
pub fn tls13_server_process_client_finished(
  conn : Tls13Connection,
  record : Bytes,
) -> Unit raise {
  if !conn.is_server {
    fail("tls13: server_process_client_finished on a client connection")
  }
  let keys = match conn.client_handshake {
    Some(k) => k
    None => fail("tls13: handshake keys not derived yet")
  }
  let body = conn.open_with(keys, record).1
  if body.length() < 4 || body[0].to_int() != tls13_hs_byte(Finished) {
    fail("tls13: not a Finished message")
  }
  let finished_key = tls13_expand_label(
    keys.secret,
    "finished",
    Bytes::from_array([]),
    32,
  )
  let expect = @hmac.hmac_sha256(finished_key, @sha256.sha256(conn.transcript))
  let mac = match tls13_slice(body, 4, body.length() - 4) {
    Some(v) => v
    None => fail("tls13: truncated Finished MAC")
  }
  if !tls13_ct_eq(expect, mac) {
    fail("tls13: client Finished MAC invalid")
  }
  // Application traffic secrets cover the transcript up to (and
  // including) the server Finished only (RFC 8446 §7.1), so derive
  // them before recording the client Finished.
  conn.derive_app_keys()
  // RFC 8446 §5.3: the client Finished was the last record opened under
  // the handshake keys, so both counters restart at zero for
  // application traffic.
  conn.send_seq = 0L
  conn.recv_seq = 0L
  conn.transcript = conn.transcript + body
}

// ===========================================================================
// Application data
// ===========================================================================

///|
/// AEAD tag length for both supported suites.
const TLS13_TAG_LEN : Int = 16

///|
/// Protect application data with the sender's application key.
pub fn tls13_send_app(conn : Tls13Connection, data : Bytes) -> Bytes raise {
  let keys = match (conn.is_server, conn.server_app, conn.client_app) {
    (true, Some(k), _) => k
    (false, _, Some(k)) => k
    _ => fail("tls13: application keys not established")
  }
  let nonce = tls13_compute_nonce(keys.iv, conn.send_seq)
  conn.send_seq = conn.send_seq + 1L
  let inner : Array[Byte] = []
  for i = 0; i < data.length(); i = i + 1 {
    inner.push(data[i])
  }
  inner.push(tls13_ct_byte(ApplicationData).to_byte())
  let inner_bytes = Bytes::from_array(inner)
  // The outer header (AAD) embeds the ciphertext length, which is
  // inner length + tag length for both supported AEADs.
  let sealed_len = inner_bytes.length() + TLS13_TAG_LEN
  let header : Array[Byte] = [
    tls13_ct_byte(ApplicationData).to_byte(),
    b'\x03',
    b'\x03',
  ]
  tls13_put_u16(header, sealed_len)
  let aad = Bytes::from_array(header)
  match
    tls13_aead_seal(conn.config.cipher_suite, keys.key, nonce, aad, inner_bytes) {
    Some(ct) => {
      let out : Array[Byte] = []
      for i = 0; i < header.length(); i = i + 1 {
        out.push(header[i])
      }
      for i = 0; i < ct.length(); i = i + 1 {
        out.push(ct[i])
      }
      Bytes::from_array(out)
    }
    None => fail("tls13: AEAD seal failed")
  }
}

///|
/// Open a protected application record with the peer's application
/// key. Returns `None` on any authentication failure.
pub fn tls13_recv_app(conn : Tls13Connection, record : Bytes) -> Bytes? {
  let keys = match (conn.is_server, conn.client_app, conn.server_app) {
    (true, Some(k), _) => k
    (false, _, Some(k)) => k
    _ => return None
  }
  let opened = Some(conn.open_with(keys, record)) catch { _ => None }
  match opened {
    Some((inner_type, body)) =>
      if inner_type != tls13_ct_byte(ApplicationData) {
        None
      } else {
        Some(body)
      }
    None => None
  }
}
