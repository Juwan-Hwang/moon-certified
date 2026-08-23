///|
/// Comprehensive tests for PKCS#7 / CMS (RFC 5652).

// ===========================================================================
// Content type OID tests
// ===========================================================================

test "pkcs7_content_type_oid: Data" {
  assert_eq(pkcs7_content_type_oid(Pkcs7ContentType::data()), OID_DATA)
}

///|
test "pkcs7_content_type_oid: SignedData" {
  assert_eq(
    pkcs7_content_type_oid(Pkcs7ContentType::signed_data()),
    OID_SIGNED_DATA,
  )
}

///|
test "pkcs7_content_type_oid: EnvelopedData" {
  assert_eq(
    pkcs7_content_type_oid(Pkcs7ContentType::enveloped_data()),
    OID_ENVELOPED_DATA,
  )
}

///|
test "pkcs7_content_type_oid: DigestedData" {
  assert_eq(
    pkcs7_content_type_oid(Pkcs7ContentType::digested_data()),
    OID_DIGESTED_DATA,
  )
}

///|
test "pkcs7_content_type_oid: EncryptedData" {
  assert_eq(
    pkcs7_content_type_oid(Pkcs7ContentType::encrypted_data()),
    OID_ENCRYPTED_DATA,
  )
}

///|
test "pkcs7_content_type_oid: all OIDs match expected values" {
  assert_eq(OID_DATA, "1.2.840.113549.1.7.1")
  assert_eq(OID_SIGNED_DATA, "1.2.840.113549.1.7.2")
  assert_eq(OID_ENVELOPED_DATA, "1.2.840.113549.1.7.3")
  assert_eq(OID_DIGESTED_DATA, "1.2.840.113549.1.7.5")
  assert_eq(OID_ENCRYPTED_DATA, "1.2.840.113549.1.7.6")
}

// ===========================================================================
// Create Data tests
// ===========================================================================

///|
test "pkcs7_create_data: returns raw bytes" {
  let data = Bytes::from_array([0x48, 0x65, 0x6C, 0x6C, 0x6F])
  let result = pkcs7_create_data(data)
  assert_eq(result.length(), 5)
  for i = 0; i < 5; i = i + 1 {
    assert_eq(result[i], data[i])
  }
}

///|
test "pkcs7_create_data: empty data" {
  let data = Bytes::from_array([])
  let result = pkcs7_create_data(data)
  assert_eq(result.length(), 0)
}

// ===========================================================================
// SignedData tests
// ===========================================================================

///|
test "pkcs7_create_signed_data: basic structure" {
  let content = Bytes::from_array([0x01, 0x02, 0x03])
  let sig = Bytes::from_array([0xAA, 0xBB, 0xCC])
  let sd = pkcs7_create_signed_data(
    content, "2.16.840.1.101.3.4.2.1", "1.2.840.113549.1.1.11", sig, "CN=TestSigner",
    42,
  )
  assert_eq(sd.content_type, OID_SIGNED_DATA)
  assert_eq(sd.version, 1)
  assert_eq(sd.digest_algorithms.length(), 1)
  assert_eq(sd.digest_algorithms[0], "2.16.840.1.101.3.4.2.1")
  assert_eq(sd.content, content)
  assert_eq(sd.signer_infos.length(), 1)
  assert_eq(sd.signer_infos[0].issuer, "CN=TestSigner")
  assert_eq(sd.signer_infos[0].serial_number, 42)
  assert_eq(sd.signer_infos[0].signature, sig)
  assert_eq(sd.certificates.length(), 0)
}

///|
test "pkcs7_create_signed_data: empty content" {
  let content = Bytes::from_array([])
  let sig = Bytes::from_array([0xFF])
  let sd = pkcs7_create_signed_data(content, "sha256", "rsa", sig, "issuer", 0)
  assert_eq(sd.content.length(), 0)
  assert_eq(sd.signer_infos[0].signature, sig)
}

///|
test "pkcs7_create_signed_data: large serial number" {
  let content = Bytes::from_array([0x00])
  let sig = Bytes::from_array([])
  let sd = pkcs7_create_signed_data(
    content, "sha256", "rsa", sig, "issuer", 999999,
  )
  assert_eq(sd.signer_infos[0].serial_number, 999999)
}

// ===========================================================================
// EnvelopedData tests
// ===========================================================================

///|
test "pkcs7_create_enveloped_data: basic structure" {
  let encrypted = Bytes::from_array([0xDE, 0xAD, 0xBE, 0xEF])
  let recipient = RecipientInfo::new(
    "CN=Recipient1",
    1,
    "1.2.840.113549.1.1.1",
    Bytes::from_array([0x11, 0x22]),
  )
  let ed = pkcs7_create_enveloped_data(encrypted, "aes256-gcm", [recipient])
  assert_eq(ed.content_type, OID_ENVELOPED_DATA)
  assert_eq(ed.version, 0)
  assert_eq(ed.content_encryption_algorithm, "aes256-gcm")
  assert_eq(ed.recipient_infos.length(), 1)
  assert_eq(ed.recipient_infos[0].issuer, "CN=Recipient1")
  assert_eq(ed.encrypted_content, encrypted)
}

///|
test "pkcs7_create_enveloped_data: multiple recipients" {
  let encrypted = Bytes::from_array([0x01])
  let r1 = RecipientInfo::new("CN=R1", 1, "rsa", Bytes::from_array([0x01]))
  let r2 = RecipientInfo::new("CN=R2", 2, "rsa", Bytes::from_array([0x02]))
  let ed = pkcs7_create_enveloped_data(encrypted, "aes128", [r1, r2])
  assert_eq(ed.recipient_infos.length(), 2)
  assert_eq(ed.recipient_infos[0].issuer, "CN=R1")
  assert_eq(ed.recipient_infos[1].issuer, "CN=R2")
}

///|
test "pkcs7_create_enveloped_data: no recipients" {
  let encrypted = Bytes::from_array([0x01])
  let ed = pkcs7_create_enveloped_data(encrypted, "aes256", [])
  assert_eq(ed.recipient_infos.length(), 0)
}

// ===========================================================================
// DigestedData tests
// ===========================================================================

///|
fn make_bytes(val : Int, n : Int) -> Bytes {
  let arr : Array[Byte] = Array::make(n, val.to_byte())
  Bytes::from_array(arr)
}

///|
test "pkcs7_create_digested_data: basic structure" {
  let content = Bytes::from_array([0x48, 0x69])
  let digest = make_bytes(0xFF, 32)
  let dd = pkcs7_create_digested_data(content, "2.16.840.1.101.3.4.2.1", digest)
  assert_eq(dd.content_type, OID_DIGESTED_DATA)
  assert_eq(dd.version, 0)
  assert_eq(dd.digest_algorithm, "2.16.840.1.101.3.4.2.1")
  assert_eq(dd.content, content)
  assert_eq(dd.digest, digest)
}

///|
test "pkcs7_create_digested_data: empty content" {
  let content = Bytes::from_array([])
  let digest = make_bytes(0x00, 32)
  let dd = pkcs7_create_digested_data(content, "sha256", digest)
  assert_eq(dd.content.length(), 0)
  assert_eq(dd.digest, digest)
}

// ===========================================================================
// Digest verification tests
// ===========================================================================

///|
test "pkcs7_verify_digest: matching digest" {
  let content = Bytes::from_array([0x48, 0x65, 0x6C, 0x6C, 0x6F])
  let computed = @sha256.sha256(content)
  let sd = pkcs7_create_signed_data(
    content,
    "sha256",
    "rsa",
    Bytes::from_array([]),
    "issuer",
    1,
  )
  assert_eq(pkcs7_verify_digest(sd, computed), true)
}

///|
test "pkcs7_verify_digest: non-matching digest" {
  let content = Bytes::from_array([0x48, 0x65, 0x6C, 0x6C, 0x6F])
  let wrong_digest = make_bytes(0x00, 32)
  let sd = pkcs7_create_signed_data(
    content,
    "sha256",
    "rsa",
    Bytes::from_array([]),
    "issuer",
    1,
  )
  assert_eq(pkcs7_verify_digest(sd, wrong_digest), false)
}

///|
test "pkcs7_verify_digest: different content produces different digest" {
  let content1 = Bytes::from_array([0x41])
  let content2 = Bytes::from_array([0x42])
  let digest1 = @sha256.sha256(content1)
  let sd2 = pkcs7_create_signed_data(
    content2,
    "sha256",
    "rsa",
    Bytes::from_array([]),
    "issuer",
    1,
  )
  assert_eq(pkcs7_verify_digest(sd2, digest1), false)
}

///|
test "pkcs7_verify_digest: empty content" {
  let content = Bytes::from_array([])
  let digest = @sha256.sha256(content)
  let sd = pkcs7_create_signed_data(
    content,
    "sha256",
    "rsa",
    Bytes::from_array([]),
    "issuer",
    1,
  )
  assert_eq(pkcs7_verify_digest(sd, digest), true)
}

///|
test "pkcs7_verify_digest: length mismatch fails" {
  let content = Bytes::from_array([0x01])
  let short_digest = make_bytes(0x00, 16)
  let sd = pkcs7_create_signed_data(
    content,
    "sha256",
    "rsa",
    Bytes::from_array([]),
    "issuer",
    1,
  )
  assert_eq(pkcs7_verify_digest(sd, short_digest), false)
}
