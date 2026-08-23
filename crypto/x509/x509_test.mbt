///|
/// Comprehensive tests for X.509 Certificate parsing (RFC 5280).

// ===========================================================================
// oid_to_string tests
// ===========================================================================

test "oid_to_string: simple OID" {
  assert_eq(oid_to_string([1, 2, 840, 113549]), "1.2.840.113549")
}

///|
test "oid_to_string: single component" {
  assert_eq(oid_to_string([1]), "1")
}

///|
test "oid_to_string: empty OID" {
  assert_eq(oid_to_string([]), "")
}

///|
test "oid_to_string: two components" {
  assert_eq(oid_to_string([1, 2]), "1.2")
}

///|
test "oid_to_string: long OID" {
  assert_eq(
    oid_to_string([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
    "1.2.3.4.5.6.7.8.9.10",
  )
}

// ===========================================================================
// dn_to_string tests
// ===========================================================================

///|
test "dn_to_string: single attribute" {
  let dn = DistinguishedName::new([RdnAttribute::new([2, 5, 4, 3], "Test")])
  assert_eq(dn_to_string(dn), "2.5.4.3=Test")
}

///|
test "dn_to_string: multiple attributes" {
  let dn = DistinguishedName::new([
    RdnAttribute::new([2, 5, 4, 3], "CN"),
    RdnAttribute::new([2, 5, 4, 10], "Org"),
  ])
  let s = dn_to_string(dn)
  assert_eq(s, "2.5.4.3=CN,2.5.4.10=Org")
}

///|
test "dn_to_string: empty DN" {
  let dn = DistinguishedName::new([])
  assert_eq(dn_to_string(dn), "")
}

// ===========================================================================
// get_common_name tests
// ===========================================================================

///|
test "get_common_name: with CN returns Some" {
  let dn = DistinguishedName::new([
    RdnAttribute::new([2, 5, 4, 10], "Org"),
    RdnAttribute::new([2, 5, 4, 3], "TestCN"),
  ])
  match get_common_name(dn) {
    Some(cn) => assert_eq(cn, "TestCN")
    None => abort("expected Some")
  }
}

///|
test "get_common_name: no CN returns None" {
  let dn = DistinguishedName::new([RdnAttribute::new([2, 5, 4, 10], "Org")])
  assert_true(get_common_name(dn) is None)
}

///|
test "get_common_name: empty DN returns None" {
  let dn = DistinguishedName::new([])
  assert_true(get_common_name(dn) is None)
}

///|
test "get_common_name: first attribute is CN" {
  let dn = DistinguishedName::new([RdnAttribute::new([2, 5, 4, 3], "First")])
  match get_common_name(dn) {
    Some(cn) => assert_eq(cn, "First")
    None => abort("expected Some")
  }
}

// ===========================================================================
// Helper: build a minimal cert
// ===========================================================================

///|
fn make_cert(
  serial : Int,
  not_before : String,
  not_after : String,
  issuer_attrs : Array[RdnAttribute],
  subject_attrs : Array[RdnAttribute],
  sig_oid : Array[Int],
  sig_value : Bytes,
  pk_bytes : Bytes,
) -> Certificate {
  let alg = AlgorithmIdentifier::new([1], None)
  let spki = SubjectPublicKeyInfo::new(alg, pk_bytes)
  let issuer = DistinguishedName::new(issuer_attrs)
  let subject = DistinguishedName::new(subject_attrs)
  let validity = Validity::new(not_before, not_after)
  let tbs = TbsCertificate::new(
    2,
    serial,
    alg,
    issuer,
    validity,
    subject,
    spki,
    [],
  )
  Certificate::new(tbs, AlgorithmIdentifier::new(sig_oid, None), sig_value)
}

// ===========================================================================
// is_ca tests
// ===========================================================================

///|
test "is_ca: non-CA cert returns false" {
  let cert = make_cert(
    1,
    "",
    "",
    [],
    [],
    [1],
    Bytes::from_array([]),
    Bytes::from_array([]),
  )
  assert_eq(is_ca(cert), false)
}

///|
test "is_ca: cert with no extensions returns false" {
  let cert = make_cert(
    42,
    "20230101",
    "20240101",
    [],
    [],
    [1, 2],
    Bytes::from_array([0x00]),
    Bytes::from_array([0x00]),
  )
  assert_eq(is_ca(cert), false)
}

// ===========================================================================
// Accessor function tests with constructed certificates
// ===========================================================================

///|
test "get_serial_number: returns correct serial" {
  let cert = make_cert(
    12345,
    "",
    "",
    [],
    [],
    [1],
    Bytes::from_array([]),
    Bytes::from_array([]),
  )
  assert_eq(get_serial_number(cert), 12345)
}

///|
test "get_validity: returns correct dates" {
  let cert = make_cert(
    1,
    "20230101Z",
    "20240101Z",
    [],
    [],
    [1],
    Bytes::from_array([]),
    Bytes::from_array([]),
  )
  let v = get_validity(cert)
  assert_eq(v.not_before, "20230101Z")
  assert_eq(v.not_after, "20240101Z")
}

///|
test "get_signature_algorithm_oid: returns correct OID" {
  let oid = [1, 2, 840, 113549, 1, 1, 11]
  let cert = make_cert(
    1,
    "",
    "",
    [],
    [],
    oid,
    Bytes::from_array([]),
    Bytes::from_array([]),
  )
  assert_eq(get_signature_algorithm_oid(cert), oid)
}

///|
test "get_public_key: returns correct bytes" {
  let pk_bytes = Bytes::from_array([0xAA, 0xBB, 0xCC])
  let cert = make_cert(1, "", "", [], [], [1], Bytes::from_array([]), pk_bytes)
  assert_eq(get_public_key(cert), pk_bytes)
}

///|
test "get_signature_value: returns correct bytes" {
  let sig = Bytes::from_array([0x01, 0x02, 0x03])
  let cert = make_cert(1, "", "", [], [], [1], sig, Bytes::from_array([]))
  assert_eq(get_signature_value(cert), sig)
}

///|
test "get_issuer_cn: with CN in issuer" {
  let cert = make_cert(
    1,
    "",
    "",
    [RdnAttribute::new([2, 5, 4, 3], "IssuerCN")],
    [],
    [1],
    Bytes::from_array([]),
    Bytes::from_array([]),
  )
  match get_issuer_cn(cert) {
    Some(cn) => assert_eq(cn, "IssuerCN")
    None => abort("expected Some")
  }
}

///|
test "get_subject_cn: with CN in subject" {
  let cert = make_cert(
    1,
    "",
    "",
    [],
    [RdnAttribute::new([2, 5, 4, 3], "SubjectCN")],
    [1],
    Bytes::from_array([]),
    Bytes::from_array([]),
  )
  match get_subject_cn(cert) {
    Some(cn) => assert_eq(cn, "SubjectCN")
    None => abort("expected Some")
  }
}

///|
test "get_issuer_cn: no CN returns None" {
  let cert = make_cert(
    1,
    "",
    "",
    [],
    [],
    [1],
    Bytes::from_array([]),
    Bytes::from_array([]),
  )
  assert_true(get_issuer_cn(cert) is None)
}
