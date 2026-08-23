/// PKCS#7 / CMS (Cryptographic Message Syntax) — RFC 5652
///
/// PKCS#7 defines the Cryptographic Message Syntax (CMS) for digitally signed,
/// enveloped, authenticated, or encrypted data.
///
/// ## Content Types
/// - **data**: arbitrary octet string
/// - **signedData**: data + digital signatures
/// - **envelopedData**: data + encrypted content encryption keys
/// - **digestedData**: data + digest
/// - **encryptedData**: data + encrypted with a symmetric key
///
/// ## References
///
/// - RFC 5652: "Cryptographic Message Syntax (CMS)"
/// - RFC 8017: "PKCS #1: RSA Cryptography Specifications"
///
/// `proof-enabled` is `false`.

// ===========================================================================
// Content type OIDs (as dotted-decimal strings)
// ===========================================================================

///|
/// OID for id-data: 1.2.840.113549.1.7.1
pub const OID_DATA : String = "1.2.840.113549.1.7.1"

///|
/// OID for id-signedData: 1.2.840.113549.1.7.2
pub const OID_SIGNED_DATA : String = "1.2.840.113549.1.7.2"

///|
/// OID for id-envelopedData: 1.2.840.113549.1.7.3
pub const OID_ENVELOPED_DATA : String = "1.2.840.113549.1.7.3"

///|
/// OID for id-digestedData: 1.2.840.113549.1.7.5
pub const OID_DIGESTED_DATA : String = "1.2.840.113549.1.7.5"

///|
/// OID for id-encryptedData: 1.2.840.113549.1.7.6
pub const OID_ENCRYPTED_DATA : String = "1.2.840.113549.1.7.6"

// ===========================================================================
// PKCS#7 Content Types
// ===========================================================================

///|
/// PKCS#7 content type enumeration.
pub enum Pkcs7ContentType {
  Data
  SignedData
  EnvelopedData
  DigestedData
  EncryptedData
}

///|
/// Construct a `Data` content type.
pub fn Pkcs7ContentType::data() -> Pkcs7ContentType {
  Data
}

///|
/// Construct a `SignedData` content type.
pub fn Pkcs7ContentType::signed_data() -> Pkcs7ContentType {
  SignedData
}

///|
/// Construct an `EnvelopedData` content type.
pub fn Pkcs7ContentType::enveloped_data() -> Pkcs7ContentType {
  EnvelopedData
}

///|
/// Construct a `DigestedData` content type.
pub fn Pkcs7ContentType::digested_data() -> Pkcs7ContentType {
  DigestedData
}

///|
/// Construct an `EncryptedData` content type.
pub fn Pkcs7ContentType::encrypted_data() -> Pkcs7ContentType {
  EncryptedData
}

///|
/// Signer information for SignedData.
pub struct SignerInfo {
  /// Issuer distinguished name (simplified as string)
  issuer : String
  /// Serial number of the signer's certificate
  serial_number : Int
  /// Digest algorithm OID
  digest_algorithm : String
  /// Signature algorithm OID
  signature_algorithm : String
  /// The actual signature value
  signature : Bytes
}

///|
/// Construct a `SignerInfo`.
pub fn SignerInfo::new(
  issuer : String,
  serial_number : Int,
  digest_algorithm : String,
  signature_algorithm : String,
  signature : Bytes,
) -> SignerInfo {
  { issuer, serial_number, digest_algorithm, signature_algorithm, signature }
}

///|
/// SignedData content type.
pub struct SignedData {
  /// Content type OID
  content_type : String
  /// Version
  version : Int
  /// Digest algorithms used
  digest_algorithms : Array[String]
  /// Encapsulated content (the data being signed)
  content : Bytes
  /// Signer information
  signer_infos : Array[SignerInfo]
  /// Certificates (optional, simplified as raw bytes)
  certificates : Array[Bytes]
}

///|
/// Recipient information for EnvelopedData.
pub struct RecipientInfo {
  /// Issuer name
  issuer : String
  /// Serial number
  serial_number : Int
  /// Key encryption algorithm OID
  key_encryption_algorithm : String
  /// Encrypted content encryption key
  encrypted_key : Bytes
}

///|
/// Construct a `RecipientInfo`.
pub fn RecipientInfo::new(
  issuer : String,
  serial_number : Int,
  key_encryption_algorithm : String,
  encrypted_key : Bytes,
) -> RecipientInfo {
  { issuer, serial_number, key_encryption_algorithm, encrypted_key }
}

///|
/// EnvelopedData content type.
pub struct EnvelopedData {
  /// Content type OID
  content_type : String
  /// Version
  version : Int
  /// Content encryption algorithm OID
  content_encryption_algorithm : String
  /// Recipient information
  recipient_infos : Array[RecipientInfo]
  /// Encrypted content
  encrypted_content : Bytes
}

///|
/// DigestedData content type.
pub struct DigestedData {
  /// Content type OID
  content_type : String
  /// Version
  version : Int
  /// Digest algorithm OID
  digest_algorithm : String
  /// Content
  content : Bytes
  /// Digest value
  digest : Bytes
}

// ===========================================================================
// PKCS#7 builders
// ===========================================================================

///|
/// Create a simple Data content (just the raw bytes).
pub fn pkcs7_create_data(data : Bytes) -> Bytes {
  data
}

///|
/// Create a SignedData structure.
///
/// ## Parameters
/// - `content`: the data to sign
/// - `digest_algorithm`: OID of the digest algorithm (e.g., "2.16.840.1.101.3.4.2.1" for SHA-256)
/// - `signature_algorithm`: OID of the signature algorithm
/// - `signature`: the computed signature
/// - `issuer`: issuer name for signer info
/// - `serial_number`: signer certificate serial number
pub fn pkcs7_create_signed_data(
  content : Bytes,
  digest_algorithm : String,
  signature_algorithm : String,
  signature : Bytes,
  issuer : String,
  serial_number : Int,
) -> SignedData {
  let signer = {
    issuer,
    serial_number,
    digest_algorithm,
    signature_algorithm,
    signature,
  }
  {
    content_type: OID_SIGNED_DATA,
    version: 1,
    digest_algorithms: [digest_algorithm],
    content,
    signer_infos: [signer],
    certificates: [],
  }
}

///|
/// Create an EnvelopedData structure.
pub fn pkcs7_create_enveloped_data(
  encrypted_content : Bytes,
  content_encryption_algorithm : String,
  recipient_infos : Array[RecipientInfo],
) -> EnvelopedData {
  {
    content_type: OID_ENVELOPED_DATA,
    version: 0,
    content_encryption_algorithm,
    recipient_infos,
    encrypted_content,
  }
}

///|
/// Create a DigestedData structure.
pub fn pkcs7_create_digested_data(
  content : Bytes,
  digest_algorithm : String,
  digest : Bytes,
) -> DigestedData {
  {
    content_type: OID_DIGESTED_DATA,
    version: 0,
    digest_algorithm,
    content,
    digest,
  }
}

// ===========================================================================
// Verification helpers
// ===========================================================================

///|
/// Verify a SignedData structure's digest.
///
/// Recomputes the digest of the content and compares it with the
/// expected digest derived from the signature.
pub fn pkcs7_verify_digest(
  signed_data : SignedData,
  expected_digest : Bytes,
) -> Bool {
  // Hash the content with SHA-256 (simplified)
  let computed = @sha256.sha256(signed_data.content)
  if computed.length() != expected_digest.length() {
    return false
  }
  let mut diff = 0
  for i = 0; i < computed.length(); i = i + 1 {
    diff = diff | (computed[i].to_int() ^ expected_digest[i].to_int())
  }
  diff == 0
}

///|
/// Get the content type OID for a PKCS#7 content type.
pub fn pkcs7_content_type_oid(ct : Pkcs7ContentType) -> String {
  match ct {
    Data => OID_DATA
    SignedData => OID_SIGNED_DATA
    EnvelopedData => OID_ENVELOPED_DATA
    DigestedData => OID_DIGESTED_DATA
    EncryptedData => OID_ENCRYPTED_DATA
  }
}
