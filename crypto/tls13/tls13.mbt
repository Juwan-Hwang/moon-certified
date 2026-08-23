/// TLS 1.3 Protocol Layer (RFC 8446)
///
/// TLS 1.3 is the latest version of the Transport Layer Security protocol.
/// It provides authenticated key exchange, confidentiality, and integrity
/// for network communications.
///
/// `proof-enabled` is `false`.

///|
const TLS_1_3_VERSION : Int = 0x0304

///|
pub enum TlsCipherSuite {
  Aes128GcmSha256
  Aes256GcmSha384
  ChaCha20Poly1305Sha256
}

///|
pub fn TlsCipherSuite::aes128_gcm_sha256() -> TlsCipherSuite {
  Aes128GcmSha256
}

///|
pub fn TlsCipherSuite::aes256_gcm_sha384() -> TlsCipherSuite {
  Aes256GcmSha384
}

///|
pub fn TlsCipherSuite::chacha20_poly1305_sha256() -> TlsCipherSuite {
  ChaCha20Poly1305Sha256
}

///|
pub enum TlsHandshakeType {
  ClientHello
  ServerHello
  EncryptedExtensions
  Certificate
  CertificateVerify
  Finished
  NewSessionTicket
  KeyUpdate
}

///|
pub fn TlsHandshakeType::client_hello() -> TlsHandshakeType {
  ClientHello
}

///|
pub fn TlsHandshakeType::server_hello() -> TlsHandshakeType {
  ServerHello
}

///|
pub fn TlsHandshakeType::finished() -> TlsHandshakeType {
  Finished
}

///|
pub fn TlsHandshakeType::certificate() -> TlsHandshakeType {
  Certificate
}

///|
pub fn TlsHandshakeType::certificate_verify() -> TlsHandshakeType {
  CertificateVerify
}

///|
pub fn TlsHandshakeType::encrypted_extensions() -> TlsHandshakeType {
  EncryptedExtensions
}

///|
pub fn TlsHandshakeType::new_session_ticket() -> TlsHandshakeType {
  NewSessionTicket
}

///|
pub fn TlsHandshakeType::key_update() -> TlsHandshakeType {
  KeyUpdate
}

///|
pub enum TlsContentType {
  Invalid
  ChangeCipherSpec
  Alert
  Handshake
  ApplicationData
}

///|
pub fn TlsContentType::invalid() -> TlsContentType {
  Invalid
}

///|
pub fn TlsContentType::change_cipher_spec() -> TlsContentType {
  ChangeCipherSpec
}

///|
pub fn TlsContentType::alert() -> TlsContentType {
  Alert
}

///|
pub fn TlsContentType::handshake() -> TlsContentType {
  Handshake
}

///|
pub fn TlsContentType::application_data() -> TlsContentType {
  ApplicationData
}

///|
pub struct TlsState {
  is_client : Bool
  cipher_suite : TlsCipherSuite
  client_random : Bytes
  server_random : Bytes
  handshake_secret : Bytes
  app_secret : Bytes
  sequence : Int
  key : Bytes
}

///|
fn hkdf_extract(salt : Bytes, ikm : Bytes) -> Bytes {
  @hmac.hmac_sha256(salt, ikm)
}

///|
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
pub fn tls_client_hello(
  client_random : Bytes,
  cipher_suites : Array[TlsCipherSuite],
  key_share : Bytes,
) -> Bytes {
  let buf : Array[Byte] = []
  buf.push(b'\x03')
  buf.push(b'\x04')
  for i = 0; i < 32 && i < client_random.length(); i = i + 1 {
    buf.push(client_random[i])
  }
  let cs_count = cipher_suites.length()
  buf.push(((cs_count >> 8) & 0xFF).to_byte())
  buf.push((cs_count & 0xFF).to_byte())
  for i in 0..<cipher_suites.length() {
    let id = match cipher_suites[i] {
      Aes128GcmSha256 => 0x1301
      Aes256GcmSha384 => 0x1302
      ChaCha20Poly1305Sha256 => 0x1303
    }
    buf.push(((id >> 8) & 0xFF).to_byte())
    buf.push((id & 0xFF).to_byte())
  }
  let ks_offset = 36 + cs_count * 2
  buf.push(((key_share.length() >> 8) & 0xFF).to_byte())
  buf.push((key_share.length() & 0xFF).to_byte())
  for i = 0; i < key_share.length(); i = i + 1 {
    buf.push(key_share[i])
  }
  let _ = ks_offset
  Bytes::from_array(buf)
}

///|
pub fn tls_derive_keys(
  shared_secret : Bytes,
  client_random : Bytes,
  server_random : Bytes,
) -> (Bytes, Bytes) {
  let zeros_buf : Array[Byte] = []
  for i = 0; i < 32; i = i + 1 {
    zeros_buf.push(b'\x00')
  }
  let zeros = Bytes::from_array(zeros_buf)
  let early_secret = hkdf_extract(zeros, zeros)
  let handshake_secret = hkdf_extract(early_secret, shared_secret)
  let master_secret = hkdf_extract(handshake_secret, zeros)
  let client_info : Array[Byte] = []
  for i = 0; i < 32 && i < client_random.length(); i = i + 1 {
    client_info.push(client_random[i])
  }
  client_info.push(b'\x63') // 'c'
  client_info.push(b'\x6C') // 'l'
  client_info.push(b'\x69') // 'i'
  client_info.push(b'\x65') // 'e'
  client_info.push(b'\x6E') // 'n'
  client_info.push(b'\x74') // 't'
  let client_key = hkdf_expand(
    master_secret,
    Bytes::from_array(client_info),
    32,
  )
  let server_info : Array[Byte] = []
  for i = 0; i < 32 && i < server_random.length(); i = i + 1 {
    server_info.push(server_random[i])
  }
  server_info.push(b'\x73') // 's'
  server_info.push(b'\x65') // 'e'
  server_info.push(b'\x72') // 'r'
  server_info.push(b'\x76') // 'v'
  server_info.push(b'\x65') // 'e'
  server_info.push(b'\x72') // 'r'
  let server_key = hkdf_expand(
    master_secret,
    Bytes::from_array(server_info),
    32,
  )
  (client_key, server_key)
}

///|
pub fn tls_create_record(
  content_type : TlsContentType,
  payload : Bytes,
  key : Bytes,
  seq : Int,
) -> Bytes {
  let ct = match content_type {
    Invalid => 0
    ChangeCipherSpec => 20
    Alert => 21
    Handshake => 22
    ApplicationData => 23
  }
  let nonce_buf : Array[Byte] = []
  let mut s = seq
  for i = 0; i < key.length(); i = i + 1 {
    nonce_buf.push(b'\x00')
  }
  for i = key.length() - 1; i >= 0; i = i - 1 {
    nonce_buf[i] = (key[i].to_int() ^ (s & 0xFF)).to_byte()
    s = s >> 8
  }
  let nonce = Bytes::from_array(nonce_buf)
  let encrypted : Array[Byte] = []
  for i = 0; i < payload.length(); i = i + 1 {
    encrypted.push(
      (payload[i].to_int() ^ nonce[i % nonce.length()].to_int()).to_byte(),
    )
  }
  let result : Array[Byte] = []
  result.push(ct.to_byte())
  result.push(b'\x03')
  result.push(b'\x04')
  result.push(((encrypted.length() >> 8) & 0xFF).to_byte())
  result.push((encrypted.length() & 0xFF).to_byte())
  for i = 0; i < encrypted.length(); i = i + 1 {
    result.push(encrypted[i])
  }
  Bytes::from_array(result)
}

///|
pub fn tls_parse_record_header(data : Bytes) -> (Int, Int, Int)? {
  if data.length() < 5 {
    return None
  }
  let content_type = data[0].to_int()
  let version = (data[1].to_int() << 8) | data[2].to_int()
  let length = (data[3].to_int() << 8) | data[4].to_int()
  Some((content_type, version, length))
}
