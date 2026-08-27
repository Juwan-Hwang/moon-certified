// Tests for crypto/tls13 — RFC 8446 handshake, authentication and
// protected application data over an in-memory transport.

///|
fn tls13_seed(n : Int) -> Bytes {
  let arr : Array[Byte] = []
  for i = 0; i < 40; i = i + 1 {
    arr.push(((n * 97 + i * 13 + 7) & 0xFF).to_byte())
  }
  Bytes::from_array(arr)
}

///|
/// Run a full handshake; returns (client_conn, server_conn).
fn tls13_do_handshake(
  suite : TlsCipherSuite,
  server_sk : Bytes,
  cert : Bytes,
) -> (Tls13Connection, Tls13Connection) raise {
  let server_pk = @ed25519.derive_public_key(server_sk)
  let client_config = tls13_config_new(suite, Some(server_pk))
  let server_config = tls13_config_new(suite, None)
  let client = tls13_client_new(client_config, tls13_seed(1))
  let server = tls13_server_new(server_config)
  let ch = tls13_client_hello(client)
  let sh = tls13_server_process_hello(server, ch, tls13_seed(2))
  tls13_client_process_hello(client, sh)
  let flight = tls13_server_handshake_finish(server, cert, server_sk)
  tls13_client_process_flight(client, flight)
  let fin = tls13_client_finished(client)
  tls13_server_process_client_finished(server, fin)
  (client, server)
}

///|
test "tls13_full_handshake_chacha20" {
  let server_sk = @sha256.sha256(tls13_seed(10) + b"server-signing-key")
  let cert = b"opaque test certificate DER"
  let (client, server) = tls13_do_handshake(
    TlsCipherSuite::chacha20_poly1305_sha256(),
    server_sk,
    cert,
  )
  // Application data client -> server.
  let r1 = tls13_send_app(client, b"GET / HTTP/1.1")
  match tls13_recv_app(server, r1) {
    Some(v) => assert_eq(v, b"GET / HTTP/1.1")
    None => fail("server failed to open client record")
  }
  // Server -> client.
  let r2 = tls13_send_app(server, b"200 OK")
  match tls13_recv_app(client, r2) {
    Some(v) => assert_eq(v, b"200 OK")
    None => fail("client failed to open server record")
  }
  // Multiple messages advance the sequence numbers correctly.
  let r3 = tls13_send_app(client, b"second")
  let r4 = tls13_send_app(client, b"third")
  match tls13_recv_app(server, r3) {
    Some(v) => assert_eq(v, b"second")
    None => fail("server failed to open r3")
  }
  match tls13_recv_app(server, r4) {
    Some(v) => assert_eq(v, b"third")
    None => fail("server failed to open r4")
  }
}

///|
test "tls13_full_handshake_aes128gcm" {
  let server_sk = @sha256.sha256(tls13_seed(11) + b"server-signing-key")
  let cert = b"opaque test certificate DER 2"
  let (client, server) = tls13_do_handshake(TlsCipherSuite::aes128_gcm_sha256(), server_sk, cert)
  let r = tls13_send_app(client, b"payload-over-gcm")
  match tls13_recv_app(server, r) {
    Some(v) => assert_eq(v, b"payload-over-gcm")
    None => fail("AES-GCM record failed to open")
  }
}

///|
test "tls13_tampered_flight_rejected" {
  let server_sk = @sha256.sha256(tls13_seed(12) + b"server-signing-key")
  let server_pk = @ed25519.derive_public_key(server_sk)
  let cert = b"opaque cert"
  let client_config = tls13_config_new(TlsCipherSuite::chacha20_poly1305_sha256(), Some(server_pk))
  let server_config = tls13_config_new(TlsCipherSuite::chacha20_poly1305_sha256(), None)
  let client = tls13_client_new(client_config, tls13_seed(3))
  let server = tls13_server_new(server_config)
  let ch = tls13_client_hello(client)
  let sh = tls13_server_process_hello(server, ch, tls13_seed(4))
  tls13_client_process_hello(client, sh)
  let flight = tls13_server_handshake_finish(server, cert, server_sk)
  // Flip one ciphertext byte: AEAD authentication must reject it.
  let tampered = flight.to_array()
  tampered[tampered.length() / 2] = (
    tampered[tampered.length() / 2].to_int() ^ 0x01
  ).to_byte()
  let r = Some(
    tls13_client_process_flight(client, Bytes::from_array(tampered)),
  ) catch { _ => None }
  match r {
    Some(_) => fail("client accepted a tampered server flight")
    None => ()
  }
}

///|
test "tls13_wrong_certificate_key_rejected" {
  let server_sk = @sha256.sha256(tls13_seed(13) + b"server-signing-key")
  let attacker_pk = @ed25519.derive_public_key(
    @sha256.sha256(tls13_seed(14) + b"attacker-key"),
  )
  let cert = b"opaque cert"
  // Client trusts a *different* key than the one that signs
  // CertificateVerify: the handshake must fail.
  let client_config = tls13_config_new(TlsCipherSuite::chacha20_poly1305_sha256(), Some(attacker_pk))
  let server_config = tls13_config_new(TlsCipherSuite::chacha20_poly1305_sha256(), None)
  let client = tls13_client_new(client_config, tls13_seed(5))
  let server = tls13_server_new(server_config)
  let ch = tls13_client_hello(client)
  let sh = tls13_server_process_hello(server, ch, tls13_seed(6))
  tls13_client_process_hello(client, sh)
  let flight = tls13_server_handshake_finish(server, cert, server_sk)
  let r = Some(tls13_client_process_flight(client, flight)) catch { _ => None }
  match r {
    Some(_) => fail("client accepted a CertificateVerify under the wrong key")
    None => ()
  }
}

///|
test "tls13_tampered_app_record_rejected" {
  let server_sk = @sha256.sha256(tls13_seed(15) + b"server-signing-key")
  let (client, server) = tls13_do_handshake(
    TlsCipherSuite::chacha20_poly1305_sha256(),
    server_sk,
    b"cert",
  )
  let r = tls13_send_app(client, b"sensitive data")
  let tampered = r.to_array()
  tampered[tampered.length() - 3] = (
    tampered[tampered.length() - 3].to_int() ^ 0x80
  ).to_byte()
  assert_eq(tls13_recv_app(server, Bytes::from_array(tampered)), None)
  // Out-of-order delivery fails authentication: the receiver's nonce
  // counter advances strictly, so neither a skipped nor a replayed
  // record can be opened.
  let a = tls13_send_app(client, b"msg-a") // sender seq 1
  let b_ = tls13_send_app(client, b"msg-b") // sender seq 2
  assert_eq(tls13_recv_app(server, b_), None) // receiver expects seq 1
  assert_eq(tls13_recv_app(server, a), None) // receiver now expects seq 2+
}

///|
test "tls13_record_header_parsing" {
  match tls_parse_record_header(Bytes::from_array([23, 3, 3, 0, 3, 1, 2, 3])) {
    Some((ct, len, payload)) => {
      assert_eq(ct, 23)
      assert_eq(len, 3)
      assert_eq(payload.length(), 3)
    }
    None => fail("valid record header rejected")
  }
  assert_eq(tls_parse_record_header(Bytes::from_array([23, 3, 3])), None)
  // Wrong legacy version is rejected.
  assert_eq(
    tls_parse_record_header(Bytes::from_array([23, 3, 1, 0, 0])),
    None,
  )
}
