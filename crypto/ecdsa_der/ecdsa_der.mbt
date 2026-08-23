/// ECDSA DER Signature Encoding — IEEE P1363 ↔ ASN.1 DER Conversion
///
/// ECDSA signatures exist in two wire formats:
///
/// 1. **Fixed-length (P1363 / IEEE 1363)**: r and s are zero-padded to the
///    field size and concatenated: `r || s` (64 bytes for P-256, 48 for
///    P-384, 66 for P-521). Used by JWT/JWS (RFC 7518), TLS 1.3, and many
///    modern protocols.
///
/// 2. **DER (ASN.1)**: An ASN.1 SEQUENCE of two INTEGERs:
///    ```
///    SEQUENCE {
///      r INTEGER,
///      s INTEGER
///    }
///    ```
///    Used by X.509 certificates, PKCS#11, OpenSSL's `ECDSA_sign`, and
///    legacy systems.
///
/// This module converts between the two formats. It is **not** a
/// general-purpose DER encoder — it implements only the minimal ASN.1
/// structures needed for ECDSA signatures, making it self-contained with
/// zero external dependencies.
///
/// ## DER Encoding Rules for ECDSA
///
/// - Tag: `0x30` (SEQUENCE, constructed, universal class)
/// - Each INTEGER: tag `0x02`, then DER length, then big-endian two's
///   complement value with minimal encoding (no leading zero bytes unless
///   the high bit of the value is set, in which case a single `0x00` prefix
///   byte makes it positive).
/// - Length: short form (`0x00`–`0x7F`) or long form (`0x81`/`0x82`...).
///
/// ## References
///
/// - RFC 3279: Algorithms and Identifiers for PKI
/// - RFC 5480: Elliptic Curve Cryptography Subject Public Key Information
/// - SEC 1 v2: Elliptic Curve Cryptography (§4.1.6)
/// - ANSI X9.62: Public Key Cryptography for the Financial Services Industry
///
/// `proof-enabled` is `false`.

// ---------------------------------------------------------------------------
// DER tag constants
// ---------------------------------------------------------------------------

///|
/// ASN.1 SEQUENCE tag (constructed, universal).
let tag_sequence : Byte = b'\x30'

///|
/// ASN.1 INTEGER tag (primitive, universal).
let tag_integer : Byte = b'\x02'

// ---------------------------------------------------------------------------
// Internal helpers: minimal DER encoding
// ---------------------------------------------------------------------------

///|
/// Encode a DER length value.
///
/// - If `len < 128`: single byte (short form).
/// - If `len >= 128`: `0x80 | num_len_bytes` followed by big-endian length.
fn encode_length(len : Int) -> Array[Byte] {
  if len < 128 {
    [len.to_byte()]
  } else {
    let mut n = len
    let tmp : Array[Byte] = []
    while n > 0 {
      tmp.insert(0, (n & 0xFF).to_byte())
      n = n >> 8
    }
    let result : Array[Byte] = []
    result.push((0x80 | tmp.length()).to_byte())
    for b in tmp {
      result.push(b)
    }
    result
  }
}

///|
/// Encode a non-negative integer as DER INTEGER content (minimal big-endian
/// with a leading zero byte if the high bit is set).
///
/// This handles the common case of ECDSA r/s values which are always
/// non-negative. If the value's most significant byte has the high bit set,
/// a `0x00` prefix byte is added to keep the INTEGER positive in DER's
/// two's-complement representation.
fn encode_integer_content(bytes : Array[Byte]) -> Array[Byte] {
  // Strip leading zeros (DER requires minimal encoding)
  let mut start = 0
  while start < bytes.length() - 1 && bytes[start] == b'\x00' {
    start = start + 1
  }
  let content : Array[Byte] = []
  for i = start; i < bytes.length(); i = i + 1 {
    content.push(bytes[i])
  }
  // If the MSB is set, prepend 0x00 to keep it positive
  if content.length() > 0 && (content[0].to_int() & 0x80) != 0 {
    content.insert(0, b'\x00')
  }
  // Edge case: all zeros → single 0x00 byte
  if content.length() == 0 {
    content.push(b'\x00')
  }
  content
}

// ---------------------------------------------------------------------------
// Public API: P1363 → DER
// ---------------------------------------------------------------------------

///|
/// Convert a fixed-length (P1363 / IEEE 1363) ECDSA signature to DER format.
///
/// - `p1363_sig`: The signature as `r || s`, each component padded to
///   `field_size` bytes (e.g., 32 for P-256, 48 for P-384).
/// - `field_size`: Byte length of each component (e.g., 32, 48, 66).
///
/// Returns the DER-encoded SEQUENCE { INTEGER r, INTEGER s }.
///
/// Returns `None` if the input length is not `2 * field_size`.
pub fn p1363_to_der(p1363_sig : Bytes, field_size : Int) -> Bytes? {
  if p1363_sig.length() != field_size * 2 || field_size <= 0 {
    return None
  }
  // Extract r and s as arrays
  let r_bytes : Array[Byte] = []
  for i = 0; i < field_size; i = i + 1 {
    r_bytes.push(p1363_sig[i])
  }
  let s_bytes : Array[Byte] = []
  for i = 0; i < field_size; i = i + 1 {
    s_bytes.push(p1363_sig[field_size + i])
  }
  // Encode each as DER INTEGER content
  let r_content = encode_integer_content(r_bytes)
  let s_content = encode_integer_content(s_bytes)
  // Build each INTEGER: tag || length || content
  let r_der : Array[Byte] = []
  r_der.push(tag_integer)
  for b in encode_length(r_content.length()) {
    r_der.push(b)
  }
  for b in r_content {
    r_der.push(b)
  }
  let s_der : Array[Byte] = []
  s_der.push(tag_integer)
  for b in encode_length(s_content.length()) {
    s_der.push(b)
  }
  for b in s_content {
    s_der.push(b)
  }
  // Build SEQUENCE: tag || length || r_der || s_der
  let seq_content_len = r_der.length() + s_der.length()
  let result : Array[Byte] = []
  result.push(tag_sequence)
  for b in encode_length(seq_content_len) {
    result.push(b)
  }
  for b in r_der {
    result.push(b)
  }
  for b in s_der {
    result.push(b)
  }
  Some(Bytes::from_array(result))
}

// ---------------------------------------------------------------------------
// Internal helpers: DER parsing
// ---------------------------------------------------------------------------

///|
/// Read a DER tag at position `pos` in `buf`.
/// Returns `(tag_value, next_pos)` or `None` on error.
fn read_tag(buf : Array[Byte], pos : Int) -> (Int, Int)? {
  if pos >= buf.length() {
    return None
  }
  Some((buf[pos].to_int(), pos + 1))
}

///|
/// Read a DER length at position `pos` in `buf`.
/// Returns `(length, next_pos)` or `None` on error.
fn read_length(buf : Array[Byte], pos : Int) -> (Int, Int)? {
  if pos >= buf.length() {
    return None
  }
  let first = buf[pos].to_int()
  if (first & 0x80) == 0 {
    // Short form
    Some((first, pos + 1))
  } else {
    // Long form
    let num_bytes = first & 0x7F
    if num_bytes == 0 || pos + num_bytes >= buf.length() {
      return None
    }
    let mut length = 0
    for i = 0; i < num_bytes; i = i + 1 {
      length = (length << 8) | buf[pos + 1 + i].to_int()
    }
    Some((length, pos + 1 + num_bytes))
  }
}

///|
/// Read a DER INTEGER at position `pos` in `buf`.
/// Returns `(content_bytes, next_pos)` where `content_bytes` is the raw
/// big-endian integer content (may have a leading 0x00 for positive sign).
/// Returns `None` on error.
fn read_integer(buf : Array[Byte], pos : Int) -> (Array[Byte], Int)? {
  let (tag, p1) = match read_tag(buf, pos) {
    Some(t) => t
    None => return None
  }
  if tag != tag_integer.to_int() {
    return None
  }
  let (len, p2) = match read_length(buf, p1) {
    Some(l) => l
    None => return None
  }
  if len <= 0 || p2 + len > buf.length() {
    return None
  }
  let content : Array[Byte] = []
  for i = 0; i < len; i = i + 1 {
    content.push(buf[p2 + i])
  }
  Some((content, p2 + len))
}

// ---------------------------------------------------------------------------
// Public API: DER → P1363
// ---------------------------------------------------------------------------

///|
/// Convert a DER-encoded ECDSA signature to fixed-length (P1363) format.
///
/// - `der_sig`: The DER-encoded `SEQUENCE { INTEGER r, INTEGER s }`.
/// - `field_size`: The desired byte length of each component (e.g., 32 for
///   P-256). The r and s values are zero-padded (on the left) to this size.
///
/// Returns the P1363 signature `r || s` (2 * field_size bytes), or `None`
/// if the DER encoding is malformed or if r/s are too large for the
/// specified field size.
pub fn der_to_p1363(der_sig : Bytes, field_size : Int) -> Bytes? {
  if field_size <= 0 {
    return None
  }
  let buf : Array[Byte] = []
  for i = 0; i < der_sig.length(); i = i + 1 {
    buf.push(der_sig[i])
  }
  // Read SEQUENCE tag
  let (tag, p1) = match read_tag(buf, 0) {
    Some(t) => t
    None => return None
  }
  if tag != tag_sequence.to_int() {
    return None
  }
  // Read SEQUENCE length
  let (seq_len, p2) = match read_length(buf, p1) {
    Some(l) => l
    None => return None
  }
  if p2 + seq_len > buf.length() {
    return None
  }
  // Read INTEGER r
  let (r_content, p3) = match read_integer(buf, p2) {
    Some(i) => i
    None => return None
  }
  // Read INTEGER s
  let (s_content, p4) = match read_integer(buf, p3) {
    Some(i) => i
    None => return None
  }
  // Verify we consumed exactly the SEQUENCE content
  if p4 != p2 + seq_len {
    return None
  }
  // Strip leading 0x00 from r and s (the DER positive-sign prefix)
  let r_stripped = strip_leading_zero(r_content)
  let s_stripped = strip_leading_zero(s_content)
  // Check that values fit in field_size bytes
  if r_stripped.length() > field_size || s_stripped.length() > field_size {
    return None
  }
  // Left-pad to field_size
  let result : Array[Byte] = []
  pad_to_size(r_stripped, field_size, result)
  pad_to_size(s_stripped, field_size, result)
  Some(Bytes::from_array(result))
}

///|
/// Strip a single leading 0x00 byte that was added for DER positive sign.
/// If the first byte is 0x00 and there are more bytes, remove it.
fn strip_leading_zero(bytes : Array[Byte]) -> Array[Byte] {
  if bytes.length() > 1 && bytes[0] == b'\x00' {
    let result : Array[Byte] = []
    for i = 1; i < bytes.length(); i = i + 1 {
      result.push(bytes[i])
    }
    result
  } else {
    bytes
  }
}

///|
/// Left-pad `bytes` with zeros to reach `target_size`, appending to `result`.
fn pad_to_size(
  bytes : Array[Byte],
  target_size : Int,
  result : Array[Byte],
) -> Unit {
  let padding = target_size - bytes.length()
  for _ in 0..<padding {
    result.push(b'\x00')
  }
  for b in bytes {
    result.push(b)
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "p1363_to_der: basic P-256 signature" {
  // r = 1, s = 1 (32 bytes each, big-endian)
  let r = Bytes::make(31, b'\x00') + Bytes::make(1, b'\x01')
  let s = Bytes::make(31, b'\x00') + Bytes::make(1, b'\x01')
  let p1363 = r + s
  match p1363_to_der(p1363, 32) {
    Some(der) => {
      // Expected: 30 06 02 01 01 02 01 01
      assert_eq(der.length(), 8)
      assert_eq(der[0], b'\x30') // SEQUENCE
      assert_eq(der[1], b'\x06') // length 6
      assert_eq(der[2], b'\x02') // INTEGER
      assert_eq(der[3], b'\x01') // length 1
      assert_eq(der[4], b'\x01') // value 1
      assert_eq(der[5], b'\x02') // INTEGER
      assert_eq(der[6], b'\x01') // length 1
      assert_eq(der[7], b'\x01') // value 1
    }
    None => assert_true(false) // Should not happen
  }
}

///|
test "p1363_to_der: high-bit value gets 0x00 prefix" {
  // r = 0xFF (high bit set), s = 0x01
  let r = Bytes::make(31, b'\x00') + Bytes::make(1, b'\xFF')
  let s = Bytes::make(31, b'\x00') + Bytes::make(1, b'\x01')
  let p1363 = r + s
  match p1363_to_der(p1363, 32) {
    Some(der) => {
      // r should be encoded as 02 02 00 FF (with leading zero)
      assert_eq(der[2], b'\x02') // INTEGER tag
      assert_eq(der[3], b'\x02') // length 2
      assert_eq(der[4], b'\x00') // leading zero for positive sign
      assert_eq(der[5], b'\xFF') // value
    }
    None => assert_true(false)
  }
}

///|
test "der_to_p1363: round-trip P-256" {
  // Create a signature with non-trivial r, s
  let r_bytes = [
    b'\x00', b'\x00', b'\x01', b'\x02', b'\x03', b'\x04', b'\x05', b'\x06', b'\x07',
    b'\x08', b'\x09', b'\x0A', b'\x0B', b'\x0C', b'\x0D', b'\x0E', b'\x0F', b'\x10',
    b'\x11', b'\x12', b'\x13', b'\x14', b'\x15', b'\x16', b'\x17', b'\x18', b'\x19',
    b'\x1A', b'\x1B', b'\x1C', b'\x1D', b'\x1E',
  ]
  let s_bytes = [
    b'\x00', b'\x00', b'\x1F', b'\x20', b'\x21', b'\x22', b'\x23', b'\x24', b'\x25',
    b'\x26', b'\x27', b'\x28', b'\x29', b'\x2A', b'\x2B', b'\x2C', b'\x2D', b'\x2E',
    b'\x2F', b'\x30', b'\x31', b'\x32', b'\x33', b'\x34', b'\x35', b'\x36', b'\x37',
    b'\x38', b'\x39', b'\x3A', b'\x3B', b'\x3C',
  ]
  let p1363 = Bytes::from_array(r_bytes) + Bytes::from_array(s_bytes)
  match p1363_to_der(p1363, 32) {
    Some(der) =>
      match der_to_p1363(der, 32) {
        Some(roundtrip) => {
          assert_eq(roundtrip.length(), 64)
          // Verify r matches
          for i = 0; i < 32; i = i + 1 {
            assert_eq(roundtrip[i], p1363[i])
          }
          // Verify s matches
          for i = 0; i < 32; i = i + 1 {
            assert_eq(roundtrip[32 + i], p1363[32 + i])
          }
        }
        None => assert_true(false)
      }
    None => assert_true(false)
  }
}

///|
test "der_to_p1363: rejects malformed DER" {
  // Not a SEQUENCE
  let bad = Bytes::from_array([b'\x02', b'\x01', b'\x01'])
  assert_true(der_to_p1363(bad, 32) is None)
  // Truncated
  let trunc = Bytes::from_array([b'\x30', b'\x06', b'\x02', b'\x01', b'\x01'])
  assert_true(der_to_p1363(trunc, 32) is None)
}

///|
test "p1363_to_der: rejects wrong-size input" {
  // Too short
  let short = Bytes::make(32, b'\x00')
  assert_true(p1363_to_der(short, 32) is None)
  // Too long
  let long = Bytes::make(70, b'\x00')
  assert_true(p1363_to_der(long, 32) is None)
}

///|
test "p1363_to_der: P-384 round-trip" {
  // 48-byte r and s
  let r = Bytes::make(47, b'\x00') + Bytes::make(1, b'\x42')
  let s = Bytes::make(47, b'\x00') + Bytes::make(1, b'\x84')
  let p1363 = r + s
  match p1363_to_der(p1363, 48) {
    Some(der) =>
      match der_to_p1363(der, 48) {
        Some(rt) => {
          assert_eq(rt.length(), 96)
          assert_eq(rt[47], b'\x42')
          assert_eq(rt[95], b'\x84')
        }
        None => assert_true(false)
      }
    None => assert_true(false)
  }
}

///|
test "der_to_p1363: handles all-zero values" {
  // r = 0, s = 0 → DER encodes each as a single 0x00 byte
  let der = Bytes::from_array([
    b'\x30', b'\x06', b'\x02', b'\x01', b'\x00', b'\x02', b'\x01', b'\x00',
  ])
  match der_to_p1363(der, 32) {
    Some(p1363) => {
      assert_eq(p1363.length(), 64)
      for i = 0; i < 64; i = i + 1 {
        assert_eq(p1363[i], b'\x00')
      }
    }
    None => assert_true(false)
  }
}
