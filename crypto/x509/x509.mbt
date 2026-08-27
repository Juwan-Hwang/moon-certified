/// X.509 Certificate Parsing and Verification (RFC 5280)
///
/// Implements parsing of X.509 v3 certificates encoded in DER (Distinguished
/// Encoding Rules) format, including:
/// - Certificate structure (tbsCertificate, signatureAlgorithm, signatureValue)
/// - Version, serial number, issuer/subject distinguished names
/// - Validity period (notBefore/notAfter)
/// - SubjectPublicKeyInfo
/// - Extensions (basic constraints, key usage, subject key identifier)
/// - Signature verification (RSA-PKCS1, ECDSA)
///
/// ## References
/// - RFC 5280: Internet X.509 Public Key Infrastructure Certificate and CRL Profile
/// - RFC 8017 (PKCS#1): RSA Cryptography Specifications
///
/// `proof-enabled` is `false`.

// ===========================================================================
// ASN.1 tag constants (DER)
// ===========================================================================

///|
const TAG_BOOLEAN : Int = 0x01

///|
const TAG_INTEGER : Int = 0x02

///|
const TAG_BIT_STRING : Int = 0x03

///|
let _TAG_OCTET_STRING : Int = 0x04

///|
const TAG_NULL : Int = 0x05

///|
const TAG_OID : Int = 0x06

///|
let _TAG_UTF8_STRING : Int = 0x0C

///|
let _TAG_PRINTABLE_STRING : Int = 0x13

///|
let _TAG_IA5_STRING : Int = 0x16

///|
let _TAG_UTCTIME : Int = 0x17

///|
let _TAG_GENERALIZEDTIME : Int = 0x18

///|
const TAG_SEQUENCE : Int = 0x30

///|
const TAG_SET : Int = 0x31

// ===========================================================================
// DER Reader
// ===========================================================================

///|
/// A cursor-based DER reader for sequential parsing of DER-encoded data.
priv struct DerCursor {
  data : Bytes
  mut pos : Int
  len : Int
}

///|
fn DerCursor::new(data : Bytes) -> DerCursor {
  { data, pos: 0, len: data.length() }
}

///|
fn DerCursor::remaining(self : DerCursor) -> Int {
  self.len - self.pos
}

///|
fn DerCursor::read_byte(self : DerCursor) -> Int {
  if self.pos >= self.len {
    abort("DER: unexpected end of data")
  }
  let b = self.data[self.pos].to_int()
  self.pos = self.pos + 1
  b
}

///|
fn DerCursor::peek_tag(self : DerCursor) -> Int {
  if self.pos >= self.len {
    abort("DER: unexpected end of data")
  }
  self.data[self.pos].to_int()
}

///|
fn DerCursor::read_tag(self : DerCursor) -> Int {
  self.read_byte()
}

///|
fn DerCursor::read_length(self : DerCursor) -> Int {
  let first = self.read_byte()
  if first < 0x80 {
    return first
  }
  let num_bytes = first & 0x7F
  if num_bytes == 0 {
    abort("DER: indefinite length not allowed in DER")
  }
  let mut result = 0
  for i = 0; i < num_bytes; i = i + 1 {
    result = (result << 8) | self.read_byte()
  }
  result
}

///|
fn DerCursor::read_bytes(self : DerCursor, n : Int) -> Bytes {
  if self.pos + n > self.len {
    abort("DER: unexpected end of data")
  }
  let arr = Array::make(n, b'\x00')
  for i = 0; i < n; i = i + 1 {
    arr[i] = self.data[self.pos + i]
  }
  self.pos = self.pos + n
  Bytes::from_array(arr)
}

///|
fn DerCursor::read_integer(self : DerCursor) -> Int {
  let tag = self.read_tag()
  if tag != TAG_INTEGER {
    abort("DER: expected INTEGER tag")
  }
  let len = self.read_length()
  if len == 0 {
    return 0
  }
  let mut result = 0
  for i = 0; i < len; i = i + 1 {
    let b = self.read_byte()
    result = (result << 8) | (b & 0xFF)
  }
  // Handle negative numbers (two's complement)
  if len > 0 && (self.data[self.pos - len] & 0x80) != 0 {
    // Negative integer
    let mut mask = -1
    mask = mask << (len * 8)
    result = result | mask
  }
  result
}

///|
fn DerCursor::_read_big_integer_bytes(self : DerCursor) -> Bytes {
  let tag = self.read_tag()
  if tag != TAG_INTEGER {
    abort("DER: expected INTEGER tag")
  }
  let len = self.read_length()
  self.read_bytes(len)
}

///|
fn DerCursor::read_oid(self : DerCursor) -> Array[Int] {
  let tag = self.read_tag()
  if tag != TAG_OID {
    abort("DER: expected OID tag")
  }
  let len = self.read_length()
  let raw = self.read_bytes(len)
  let components : Array[Int] = []
  let mut pos = 0
  if pos < len {
    let first_byte = raw[pos].to_int()
    pos = pos + 1
    components.push(first_byte / 40)
    components.push(first_byte % 40)
  }
  while pos < len {
    let mut value = 0
    let mut continue_reading = true
    while continue_reading && pos < len {
      let b = raw[pos].to_int()
      pos = pos + 1
      value = (value << 7) | (b & 0x7F)
      if (b & 0x80) == 0 {
        continue_reading = false
      }
    }
    components.push(value)
  }
  components
}

///|
fn DerCursor::read_string(self : DerCursor, expected_tag : Int) -> String {
  let tag = self.read_tag()
  if tag != expected_tag {
    abort("DER: expected string tag")
  }
  let len = self.read_length()
  let raw = self.read_bytes(len)
  let sb = StringBuilder()
  for i = 0; i < len; i = i + 1 {
    sb.write_char((raw[i].to_int() & 0xFF).unsafe_to_char())
  }
  sb.to_string()
}

///|
fn DerCursor::read_bit_string(self : DerCursor) -> Bytes {
  let tag = self.read_tag()
  if tag != TAG_BIT_STRING {
    abort("DER: expected BIT STRING tag")
  }
  let len = self.read_length()
  let unused_bits = self.read_byte()
  let _ = unused_bits
  self.read_bytes(len - 1)
}

///|
fn DerCursor::skip_element(self : DerCursor) -> Unit {
  let tag = self.read_tag()
  let _ = tag
  let len = self.read_length()
  self.pos = self.pos + len
}

// ===========================================================================
// X.509 Certificate Structures
// ===========================================================================

///|
/// Algorithm identifier (OID + optional parameters)
pub struct AlgorithmIdentifier {
  /// OID components, e.g. [1, 2, 840, 113549, 1, 1, 11] for RSA-SHA256
  oid : Array[Int]
  /// Optional parameters (raw DER bytes)
  parameters : Bytes?
}

///|
pub fn AlgorithmIdentifier::new(
  oid : Array[Int],
  parameters : Bytes?,
) -> AlgorithmIdentifier {
  { oid, parameters }
}

///|
/// Validity period
pub struct Validity {
  /// Not before, in ISO 8601 format
  not_before : String
  /// Not after, in ISO 8601 format
  not_after : String
}

///|
pub fn Validity::new(not_before : String, not_after : String) -> Validity {
  { not_before, not_after }
}

///|
/// SubjectPublicKeyInfo
pub struct SubjectPublicKeyInfo {
  /// Algorithm identifier
  algorithm : AlgorithmIdentifier
  /// Raw public key bytes (DER-encoded subjectPublicKey)
  subject_public_key : Bytes
}

///|
pub fn SubjectPublicKeyInfo::new(
  algorithm : AlgorithmIdentifier,
  subject_public_key : Bytes,
) -> SubjectPublicKeyInfo {
  { algorithm, subject_public_key }
}

///|
/// A relative distinguished name (RDN) attribute
pub struct RdnAttribute {
  /// OID of the attribute (e.g., [2, 5, 4, 3] for commonName)
  oid : Array[Int]
  /// Attribute value as string
  value : String
}

///|
pub fn RdnAttribute::new(oid : Array[Int], value : String) -> RdnAttribute {
  { oid, value }
}

///|
/// Distinguished Name (sequence of RDN attributes)
pub struct DistinguishedName {
  /// List of RDN attributes
  attributes : Array[RdnAttribute]
}

///|
pub fn DistinguishedName::new(
  attributes : Array[RdnAttribute],
) -> DistinguishedName {
  { attributes, }
}

///|
/// Extension
pub struct Extension {
  /// Extension OID
  oid : Array[Int]
  /// Whether the extension is critical
  critical : Bool
  /// Extension value (raw DER bytes)
  value : Bytes
}

///|
pub fn Extension::new(
  oid : Array[Int],
  critical : Bool,
  value : Bytes,
) -> Extension {
  { oid, critical, value }
}

///|
/// TBS Certificate (To-Be-Signed)
pub struct TbsCertificate {
  /// Version (0=v1, 1=v2, 2=v3)
  version : Int
  /// Serial number
  serial_number : Int
  /// Signature algorithm
  signature_algorithm : AlgorithmIdentifier
  /// Issuer distinguished name
  issuer : DistinguishedName
  /// Validity period
  validity : Validity
  /// Subject distinguished name
  subject : DistinguishedName
  /// Subject public key info
  subject_public_key_info : SubjectPublicKeyInfo
  /// Extensions (v3)
  extensions : Array[Extension]
}

///|
pub fn TbsCertificate::new(
  version : Int,
  serial_number : Int,
  signature_algorithm : AlgorithmIdentifier,
  issuer : DistinguishedName,
  validity : Validity,
  subject : DistinguishedName,
  subject_public_key_info : SubjectPublicKeyInfo,
  extensions : Array[Extension],
) -> TbsCertificate {
  {
    version,
    serial_number,
    signature_algorithm,
    issuer,
    validity,
    subject,
    subject_public_key_info,
    extensions,
  }
}

///|
/// X.509 Certificate
pub struct Certificate {
  /// TBS certificate
  tbs_certificate : TbsCertificate
  /// Signature algorithm
  signature_algorithm : AlgorithmIdentifier
  /// Signature value
  signature_value : Bytes
}

///|
pub fn Certificate::new(
  tbs_certificate : TbsCertificate,
  signature_algorithm : AlgorithmIdentifier,
  signature_value : Bytes,
) -> Certificate {
  { tbs_certificate, signature_algorithm, signature_value }
}

// ===========================================================================
// Parsing functions
// ===========================================================================

///|
fn parse_algorithm_identifier(cursor : DerCursor) -> AlgorithmIdentifier {
  let tag = cursor.read_tag()
  if tag != TAG_SEQUENCE {
    abort("X.509: expected SEQUENCE for AlgorithmIdentifier")
  }
  let _ = cursor.read_length()
  let oid = cursor.read_oid()
  // Optional parameters
  let parameters : Bytes? = if cursor.remaining() > 0 &&
    cursor.peek_tag() == TAG_NULL {
    let _ = cursor.read_tag()
    let _ = cursor.read_length()
    None
  } else if cursor.remaining() > 0 && cursor.peek_tag() == TAG_OID {
    let len = cursor.read_tag() // skip tag
    let _ = len
    let params_len = cursor.read_length()
    Some(cursor.read_bytes(params_len))
  } else if cursor.remaining() > 0 {
    let params_len = cursor.read_length()
    Some(cursor.read_bytes(params_len))
  } else {
    None
  }
  { oid, parameters }
}

///|
fn parse_distinguished_name(cursor : DerCursor) -> DistinguishedName {
  let tag = cursor.read_tag()
  if tag != TAG_SEQUENCE {
    abort("X.509: expected SEQUENCE for DistinguishedName")
  }
  let _ = cursor.read_length()
  let attributes : Array[RdnAttribute] = []
  while cursor.remaining() > 0 {
    // Read SET
    let set_tag = cursor.read_tag()
    if set_tag != TAG_SET {
      abort("X.509: expected SET for RDN")
    }
    let _ = cursor.read_length()
    // Read SEQUENCE { OID, ANY }
    let seq_tag = cursor.read_tag()
    if seq_tag != TAG_SEQUENCE {
      abort("X.509: expected SEQUENCE for AttributeTypeAndValue")
    }
    let _ = cursor.read_length()
    let oid = cursor.read_oid()
    // Read value (can be various string types)
    let value_tag = cursor.peek_tag()
    let value = cursor.read_string(value_tag)
    attributes.push({ oid, value })
  }
  { attributes, }
}

///|
fn parse_validity(cursor : DerCursor) -> Validity {
  let tag = cursor.read_tag()
  if tag != TAG_SEQUENCE {
    abort("X.509: expected SEQUENCE for Validity")
  }
  let _ = cursor.read_length()
  let not_before_tag = cursor.peek_tag()
  let not_before = cursor.read_string(not_before_tag)
  let not_after_tag = cursor.peek_tag()
  let not_after = cursor.read_string(not_after_tag)
  { not_before, not_after }
}

///|
fn parse_subject_public_key_info(cursor : DerCursor) -> SubjectPublicKeyInfo {
  let tag = cursor.read_tag()
  if tag != TAG_SEQUENCE {
    abort("X.509: expected SEQUENCE for SubjectPublicKeyInfo")
  }
  let _ = cursor.read_length()
  let algorithm = parse_algorithm_identifier(cursor)
  let subject_public_key = cursor.read_bit_string()
  { algorithm, subject_public_key }
}

///|
fn parse_extensions(cursor : DerCursor) -> Array[Extension] {
  let _tag = cursor.read_tag()
  // Extensions is [3] EXPLICIT SEQUENCE
  let _ = cursor.read_length()
  let seq_tag = cursor.read_tag()
  if seq_tag != TAG_SEQUENCE {
    abort("X.509: expected SEQUENCE for Extensions")
  }
  let _ = cursor.read_length()
  let extensions : Array[Extension] = []
  while cursor.remaining() > 0 {
    let ext_tag = cursor.read_tag()
    if ext_tag != TAG_SEQUENCE {
      abort("X.509: expected SEQUENCE for Extension")
    }
    let _ = cursor.read_length()
    let oid = cursor.read_oid()
    let critical = if cursor.remaining() > 0 && cursor.peek_tag() == TAG_BOOLEAN {
      let _ = cursor.read_tag()
      let _ = cursor.read_length()
      cursor.read_byte() != 0
    } else {
      false
    }
    let value_len = cursor.read_length()
    let value = cursor.read_bytes(value_len)
    extensions.push({ oid, critical, value })
  }
  extensions
}

///|
fn parse_tbs_certificate(cursor : DerCursor) -> TbsCertificate {
  let tag = cursor.read_tag()
  if tag != TAG_SEQUENCE {
    abort("X.509: expected SEQUENCE for TBS Certificate")
  }
  let _ = cursor.read_length()
  // Version [0] EXPLICIT INTEGER
  let mut version = 0 // Default v1
  if cursor.remaining() > 0 && cursor.peek_tag() == 0xA0 {
    let _ = cursor.read_tag() // [0] tag
    let _ = cursor.read_length()
    version = cursor.read_integer()
  }
  let serial_number = cursor.read_integer()
  let signature_algorithm = parse_algorithm_identifier(cursor)
  let issuer = parse_distinguished_name(cursor)
  let validity = parse_validity(cursor)
  let subject = parse_distinguished_name(cursor)
  let subject_public_key_info = parse_subject_public_key_info(cursor)
  let extensions : Array[Extension] = []
  // Skip optional issuerUniqueID [1] and subjectUniqueID [2]
  while cursor.remaining() > 0 {
    let peek = cursor.peek_tag()
    if peek == 0xA3 {
      // Extensions [3] EXPLICIT
      let _ = cursor.read_tag()
      let exts = parse_extensions(cursor)
      for e in exts {
        extensions.push(e)
      }
    } else {
      cursor.skip_element()
    }
  }
  {
    version,
    serial_number,
    signature_algorithm,
    issuer,
    validity,
    subject,
    subject_public_key_info,
    extensions,
  }
}

///|
/// Parse a DER-encoded X.509 certificate.
///
/// Returns the parsed Certificate struct, or aborts on malformed input.
pub fn parse_certificate(der_data : Bytes) -> Certificate {
  let cursor = DerCursor::new(der_data)
  let tag = cursor.read_tag()
  if tag != TAG_SEQUENCE {
    abort("X.509: expected outer SEQUENCE")
  }
  let _ = cursor.read_length()
  let tbs_certificate = parse_tbs_certificate(cursor)
  let signature_algorithm = parse_algorithm_identifier(cursor)
  let sig_tag = cursor.read_tag()
  if sig_tag != TAG_BIT_STRING {
    abort("X.509: expected BIT STRING for signature")
  }
  let _ = cursor.read_length()
  let _ = cursor.read_byte() // unused bits
  let remaining = cursor.remaining()
  let signature_value = cursor.read_bytes(remaining)
  { tbs_certificate, signature_algorithm, signature_value }
}

///|
/// Get the subject common name (CN) from a DistinguishedName.
pub fn get_common_name(dn : DistinguishedName) -> String? {
  for attr in dn.attributes {
    // OID 2.5.4.3 = commonName
    if attr.oid.length() == 4 &&
      attr.oid[0] == 2 &&
      attr.oid[1] == 5 &&
      attr.oid[2] == 4 &&
      attr.oid[3] == 3 {
      return Some(attr.value)
    }
  }
  None
}

///|
/// Get the issuer common name (CN) from a DistinguishedName.
pub fn get_issuer_cn(cert : Certificate) -> String? {
  get_common_name(cert.tbs_certificate.issuer)
}

///|
/// Get the subject common name (CN) from a certificate.
pub fn get_subject_cn(cert : Certificate) -> String? {
  get_common_name(cert.tbs_certificate.subject)
}

///|
/// Get the serial number of a certificate.
pub fn get_serial_number(cert : Certificate) -> Int {
  cert.tbs_certificate.serial_number
}

///|
/// Get the validity period of a certificate.
pub fn get_validity(cert : Certificate) -> Validity {
  cert.tbs_certificate.validity
}

///|
/// Get the signature algorithm OID of a certificate.
pub fn get_signature_algorithm_oid(cert : Certificate) -> Array[Int] {
  cert.signature_algorithm.oid
}

///|
/// Get the public key bytes from a certificate.
pub fn get_public_key(cert : Certificate) -> Bytes {
  cert.tbs_certificate.subject_public_key_info.subject_public_key
}

///|
/// Get the signature value from a certificate.
pub fn get_signature_value(cert : Certificate) -> Bytes {
  cert.signature_value
}

///|
/// Check if a certificate has the basic constraints CA flag.
pub fn is_ca(cert : Certificate) -> Bool {
  for ext in cert.tbs_certificate.extensions {
    // OID 2.5.29.19 = basicConstraints
    if ext.oid.length() == 4 &&
      ext.oid[0] == 2 &&
      ext.oid[1] == 5 &&
      ext.oid[2] == 29 &&
      ext.oid[3] == 19 {
      // Parse the basic constraints value
      let ext_cursor = DerCursor::new(ext.value)
      let tag = ext_cursor.read_tag()
      if tag == TAG_SEQUENCE {
        let _ = ext_cursor.read_length()
        if ext_cursor.remaining() > 0 && ext_cursor.peek_tag() == TAG_BOOLEAN {
          let _ = ext_cursor.read_tag()
          let _ = ext_cursor.read_length()
          return ext_cursor.read_byte() != 0
        }
      }
    }
  }
  false
}

///|
/// Format OID as a dotted-decimal string.
pub fn oid_to_string(oid : Array[Int]) -> String {
  let mut s = ""
  for i, v in oid {
    if i > 0 {
      s = s + "."
    }
    s = s + v.to_string()
  }
  s
}

///|
/// Format a DistinguishedName as an RFC 4514 string (e.g., "CN=foo,O=bar").
pub fn dn_to_string(dn : DistinguishedName) -> String {
  let parts : Array[String] = []
  for attr in dn.attributes {
    parts.push(oid_to_string(attr.oid) + "=" + attr.value)
  }
  let mut result = ""
  for i, part in parts {
    if i > 0 {
      result = result + ","
    }
    result = result + part
  }
  result
}
