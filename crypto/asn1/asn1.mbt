/// ASN.1/DER — Distinguished Encoding Rules for ASN.1.
///
/// ASN.1 (Abstract Syntax Notation One) is a standard interface description
/// language for defining data structures that can be serialized and
/// deserialized in a cross-platform way. DER (Distinguished Encoding Rules)
/// is a binary encoding specified in ITU-T X.690 that produces a unique
/// representation for each ASN.1 value — essential for cryptographic
/// applications where signatures must be deterministic.
///
/// ## Common Use Cases
///
/// - X.509 certificate encoding/decoding
/// - RSA/ECDSA key encoding (PKCS#1, PKCS#8, SEC1)
/// - PKCS#7/CMS signed and enveloped data
/// - LDAP attribute values
///
/// ## DER Encoding Rules
///
/// Every value is encoded as Tag-Length-Value (TLV):
/// - **Tag**: 1+ bytes identifying the type (class + constructed flag + number)
/// - **Length**: 1+ bytes giving the content length (definite form only in DER)
/// - **Value**: the content bytes
///
/// DER mandates the shortest possible encoding (e.g., INTEGER must use
/// minimal bytes, length must use short form if < 128, SET elements must
/// be sorted by encoding).
///
/// ## References
///
/// - ITU-T X.680: ASN.1 syntax
/// - ITU-T X.690: BER/DER encoding rules
/// - RFC 8017 (PKCS#1): RSA key encoding
/// - RFC 5280: X.509 certificate profile
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Tag definitions
// ---------------------------------------------------------------------------

///|
/// ASN.1 tag class.
pub enum Asn1Class {
  Universal // 0x00
  Application // 0x40
  ContextSpecific // 0x80
  Private // 0xC0
}

///|
/// Universal tag numbers (X.680).
pub let tag_boolean : Int = 0x01

///|
pub let tag_integer : Int = 0x02

///|
pub let tag_bit_string : Int = 0x03

///|
pub let tag_octet_string : Int = 0x04

///|
pub let tag_null : Int = 0x05

///|
pub let tag_oid : Int = 0x06

///|
pub let tag_enumerated : Int = 0x0A

///|
pub let tag_utf8_string : Int = 0x0C

///|
pub let tag_printable_string : Int = 0x13

///|
pub let tag_ia5_string : Int = 0x16

///|
pub let tag_utc_time : Int = 0x17

///|
pub let tag_generalized_time : Int = 0x18

///|
pub let tag_sequence : Int = 0x30 // constructed

///|
pub let tag_set : Int = 0x31 // constructed

// ---------------------------------------------------------------------------
// DER Writer
// ---------------------------------------------------------------------------

///|
/// DER encoder: accumulates bytes into a buffer.
///
/// Provides a fluent API for building DER structures:
/// ```
/// let der = DerWriter::new()
/// der.begin_sequence()
/// der.write_integer(42)
/// der.write_oid("1.2.840.113549.1.1.1")
/// der.end_sequence()
/// let bytes = der.finish()
/// ```
pub struct DerWriter {
  buf : Array[Byte]
  // Stack of saved positions for constructed types (SEQUENCE, SET).
  // Each entry records the position where the length placeholder starts.
  stack : Array[Int]
}

///|
/// Create a new DER writer.
pub fn DerWriter::new() -> DerWriter {
  { buf: [], stack: [] }
}

///|
/// Get the encoded bytes.
pub fn DerWriter::finish(self : DerWriter) -> Array[Byte] {
  self.buf
}

///|
/// Get current buffer length.
pub fn DerWriter::len(self : DerWriter) -> Int {
  self.buf.length()
}

// ---------------------------------------------------------------------------
// Tag and Length encoding
// ---------------------------------------------------------------------------

///|
/// Encode a tag byte. For low tag numbers (0-30), uses single-byte form.
/// For high tag numbers (>= 31), uses multi-byte form (bas1.0e-128).
fn DerWriter::write_tag(
  self : DerWriter,
  class : Asn1Class,
  constructed : Bool,
  tag_num : Int,
) -> Unit {
  let class_bits = match class {
    Universal => 0x00
    Application => 0x40
    ContextSpecific => 0x80
    Private => 0xC0
  }
  let constructed_bit = if constructed { 0x20 } else { 0x00 }
  if tag_num < 31 {
    self.buf.push((class_bits | constructed_bit | tag_num).to_byte())
  } else {
    // Multi-byte tag: first byte has low 5 bits = 11111
    self.buf.push((class_bits | constructed_bit | 0x1F).to_byte())
    // Encode tag number in bas1.0e-128 with continuation bit
    let tmp : Array[Int] = []
    let mut n = tag_num
    tmp.push(n & 0x7F)
    n = n >> 7
    while n > 0 {
      tmp.push((n & 0x7F) | 0x80)
      n = n >> 7
    }
    // Write in reverse order (MSB first)
    for i = tmp.length() - 1; i >= 0; i = i - 1 {
      self.buf.push(tmp[i].to_byte())
    }
  }
}

///|
/// Encode a length in DER definite form.
/// If length < 128: single byte.
/// If length >= 128: first byte = 0x80 | num_length_bytes, then big-endian length.
fn DerWriter::write_length(self : DerWriter, length : Int) -> Unit {
  if length < 0 {
    abort("DER length cannot be negative")
  }
  if length < 128 {
    self.buf.push(length.to_byte())
  } else {
    // Count bytes needed
    let mut n = length
    let mut num_bytes = 0
    while n > 0 {
      n = n >> 8
      num_bytes = num_bytes + 1
    }
    self.buf.push((0x80 | num_bytes).to_byte())
    // Write big-endian
    for i = num_bytes - 1; i >= 0; i = i - 1 {
      self.buf.push(((length >> (i * 8)) & 0xFF).to_byte())
    }
  }
}

// ---------------------------------------------------------------------------
// Primitive type encoders
// ---------------------------------------------------------------------------

///|
/// Write a BOOLEAN value (DER: 0xFF for true, 0x00 for false).
pub fn DerWriter::write_boolean(self : DerWriter, val : Bool) -> Unit {
  self.write_tag(Universal, false, tag_boolean)
  self.write_length(1)
  self.buf.push(if val { b'\xFF' } else { b'\x00' })
}

///|
/// Write an INTEGER from a signed Int value.
/// DER requires minimal two's-complement encoding.
pub fn DerWriter::write_integer(self : DerWriter, val : Int) -> Unit {
  self.write_tag(Universal, false, tag_integer)
  let content = encode_integer_content(val)
  self.write_length(content.length())
  for i = 0; i < content.length(); i = i + 1 {
    self.buf.push(content[i])
  }
}

///|
/// Write an INTEGER from a BigInt value (for large numbers like RSA keys).
pub fn DerWriter::write_big_integer(
  self : DerWriter,
  val : @bigint.BigInt,
) -> Unit {
  self.write_tag(Universal, false, tag_integer)
  let content = encode_bigint_content(val)
  self.write_length(content.length())
  for i = 0; i < content.length(); i = i + 1 {
    self.buf.push(content[i])
  }
}

///|
/// Encode a signed Int as DER INTEGER content (minimal two's complement).
fn encode_integer_content(val : Int) -> Array[Byte] {
  if val == 0 {
    return [b'\x00']
  }
  // Determine the number of bytes needed for minimal two's complement.
  let is_negative = val < 0
  let bytes : Array[Byte] = []
  if is_negative {
    // For negative values: find minimal representation.
    // Two's complement of a negative number n: encode as unsigned (2^32 + n),
    // then find the shortest byte sequence whose sign bit is 1.
    let v : UInt = val.reinterpret_as_uint()
    // Extract all 4 bytes (big-endian)
    let all_bytes : Array[Byte] = []
    let mut tmp = v
    for i = 0; i < 4; i = i + 1 {
      all_bytes.push((tmp & 0xFFU).to_byte())
      tmp = tmp >> 8
    }
    // all_bytes is little-endian; reverse to big-endian
    let be : Array[Byte] = []
    for i = 3; i >= 0; i = i - 1 {
      be.push(all_bytes[i])
    }
    // Find the minimal number of bytes: scan from MSB, skip leading 0xFF
    // only if the next byte has its MSB set (preserving the sign).
    let mut start = 0
    while start < 3 &&
          be[start].to_int() == 0xFF &&
          (be[start + 1].to_int() & 0x80) != 0 {
      start = start + 1
    }
    for i = start; i < 4; i = i + 1 {
      bytes.push(be[i])
    }
  } else {
    let mut v = val
    let temp : Array[Byte] = []
    while v > 0 {
      temp.push((v & 0xFF).to_byte())
      v = v >> 8
    }
    // Reverse to get big-endian
    for i = temp.length() - 1; i >= 0; i = i - 1 {
      bytes.push(temp[i])
    }
    // Check if we need a leading 0x00 byte
    // If the MSB of the first byte is 1, we need 0x00 prefix (positive sign)
    if (bytes[0].to_int() & 0x80) != 0 {
      bytes.insert(0, b'\x00')
    }
  }
  bytes
}

///|
/// Encode a BigInt as DER INTEGER content (minimal two's complement).
fn encode_bigint_content(val : @bigint.BigInt) -> Array[Byte] {
  let zero = @bigint.zero()
  if @bigint.equal(val, zero) {
    return [b'\x00']
  }
  let is_negative = @bigint.compare(val, zero) < 0
  // Get absolute value
  let abs_val = if is_negative { @bigint.negate(val) } else { val }
  // Convert to big-endian byte array via hex
  let hex = @bigint.to_hex(abs_val)
  let bytes = hex_to_bytes(hex)
  // Ensure at least 1 byte
  if bytes.is_empty() {
    return [b'\x00']
  }
  if is_negative {
    // Two's complement: invert bits and add 1
    let tc : Array[Byte] = []
    for i = 0; i < bytes.length(); i = i + 1 {
      tc.push((0xFF ^ bytes[i].to_int()).to_byte())
    }
    // Add 1
    let mut carry = 1
    for i = tc.length() - 1; i >= 0 && carry > 0; i = i - 1 {
      let v = tc[i].to_int() + carry
      tc[i] = (v & 0xFF).to_byte()
      carry = v >> 8
    }
    if carry > 0 {
      tc.insert(0, carry.to_byte())
    }
    // Check if MSB is 0 (need 0xFF prefix for negative)
    if (tc[0].to_int() & 0x80) == 0 {
      tc.insert(0, b'\xFF')
    }
    tc
  } else {
    // Positive: add 0x00 prefix if MSB is set
    if (bytes[0].to_int() & 0x80) != 0 {
      bytes.insert(0, b'\x00')
    }
    bytes
  }
}

///|
/// Convert hex string to byte array.
fn hex_to_bytes(hex : String) -> Array[Byte] {
  let bytes : Array[Byte] = []
  let chars = hex.to_array()
  let mut i = 0
  while i + 1 < chars.length() {
    let hi = hex_digit(chars[i])
    let lo = hex_digit(chars[i + 1])
    bytes.push((hi * 16 + lo).to_byte())
    i = i + 2
  }
  bytes
}

///|
fn hex_digit(c : Char) -> Int {
  if c >= '0' && c <= '9' {
    c.to_int() - '0'.to_int()
  } else if c >= 'a' && c <= 'f' {
    c.to_int() - 'a'.to_int() + 10
  } else if c >= 'A' && c <= 'F' {
    c.to_int() - 'A'.to_int() + 10
  } else {
    0
  }
}

///|
/// Write a BIT STRING.
/// `unused_bits` is the number of unused bits in the last byte (0-7).
pub fn DerWriter::write_bit_string(
  self : DerWriter,
  data : Array[Byte],
  unused_bits : Int,
) -> Unit {
  self.write_tag(Universal, false, tag_bit_string)
  self.write_length(data.length() + 1)
  self.buf.push(unused_bits.to_byte())
  for i = 0; i < data.length(); i = i + 1 {
    self.buf.push(data[i])
  }
}

///|
/// Write an OCTET STRING.
pub fn DerWriter::write_octet_string(
  self : DerWriter,
  data : Array[Byte],
) -> Unit {
  self.write_tag(Universal, false, tag_octet_string)
  self.write_length(data.length())
  for i = 0; i < data.length(); i = i + 1 {
    self.buf.push(data[i])
  }
}

///|
/// Write NULL.
pub fn DerWriter::write_null(self : DerWriter) -> Unit {
  self.write_tag(Universal, false, tag_null)
  self.write_length(0)
}

///|
/// Write an OBJECT IDENTIFIER (OID).
/// The OID is given as a dotted-decimal string (e.g., "1.2.840.113549.1.1.1").
pub fn DerWriter::write_oid(self : DerWriter, oid_str : String) -> Unit {
  let content = encode_oid_content(oid_str)
  self.write_tag(Universal, false, tag_oid)
  self.write_length(content.length())
  for i = 0; i < content.length(); i = i + 1 {
    self.buf.push(content[i])
  }
}

///|
/// Encode OID dotted-decimal string to DER content bytes.
/// First two components are packed as 40*first + second.
/// Remaining components use bas1.0e-128 with continuation bit.
fn encode_oid_content(oid_str : String) -> Array[Byte] {
  let parts : Array[Int] = []
  let mut current = 0
  let mut has_digit = false
  for c in oid_str {
    if c >= '0' && c <= '9' {
      current = current * 10 + (c.to_int() - '0'.to_int())
      has_digit = true
    } else if c == '.' {
      if has_digit {
        parts.push(current)
      }
      current = 0
      has_digit = false
    }
  }
  if has_digit {
    parts.push(current)
  }
  let content : Array[Byte] = []
  if parts.length() >= 2 {
    // First two components: 40 * first + second
    let first_val = parts[0] * 40 + parts[1]
    // This value can exceed 127, so use bas1.0e-128 encoding
    encode_base128(content, first_val)
    // Remaining components: bas1.0e-128
    for i = 2; i < parts.length(); i = i + 1 {
      encode_base128(content, parts[i])
    }
  } else if parts.length() == 1 {
    content.push((parts[0] * 40).to_byte())
  }
  content
}

///|
/// Encode a value in bas1.0e-128 with continuation bits.
fn encode_base128(buf : Array[Byte], val : Int) -> Unit {
  if val == 0 {
    buf.push(b'\x00')
    return
  }
  let temp : Array[Int] = []
  let mut n = val
  while n > 0 {
    temp.push(n & 0x7F)
    n = n >> 7
  }
  // temp is built LSB-first; when written MSB-first the first output byte
  // is temp[last] and the last output byte is temp[0].  Continuation bit
  // must be set on all output bytes EXCEPT the last, i.e. on temp[1..].
  for i = 1; i < temp.length(); i = i + 1 {
    temp[i] = temp[i] | 0x80
  }
  // Write MSB first
  for i = temp.length() - 1; i >= 0; i = i - 1 {
    buf.push(temp[i].to_byte())
  }
}

///|
/// Write a PrintableString.
pub fn DerWriter::write_printable_string(self : DerWriter, s : String) -> Unit {
  self.write_tag(Universal, false, tag_printable_string)
  let bytes = string_to_bytes(s)
  self.write_length(bytes.length())
  for i = 0; i < bytes.length(); i = i + 1 {
    self.buf.push(bytes[i])
  }
}

///|
/// Write a UTF8String.
pub fn DerWriter::write_utf8_string(self : DerWriter, s : String) -> Unit {
  self.write_tag(Universal, false, tag_utf8_string)
  let bytes = string_to_bytes(s)
  self.write_length(bytes.length())
  for i = 0; i < bytes.length(); i = i + 1 {
    self.buf.push(bytes[i])
  }
}

///|
/// Write an IA5String (ASCII).
pub fn DerWriter::write_ia5_string(self : DerWriter, s : String) -> Unit {
  self.write_tag(Universal, false, tag_ia5_string)
  let bytes = string_to_bytes(s)
  self.write_length(bytes.length())
  for i = 0; i < bytes.length(); i = i + 1 {
    self.buf.push(bytes[i])
  }
}

///|
/// Write a UTCTime (YYMMDDHHmmssZ format).
pub fn DerWriter::write_utc_time(
  self : DerWriter,
  year : Int,
  month : Int,
  day : Int,
  hour : Int,
  minute : Int,
  second : Int,
) -> Unit {
  self.write_tag(Universal, false, tag_utc_time)
  let yy = year % 100
  let s = format2(yy) +
    format2(month) +
    format2(day) +
    format2(hour) +
    format2(minute) +
    format2(second) +
    "Z"
  let bytes = string_to_bytes(s)
  self.write_length(bytes.length())
  for i = 0; i < bytes.length(); i = i + 1 {
    self.buf.push(bytes[i])
  }
}

///|
/// Write a GeneralizedTime (YYYYMMDDHHmmssZ format).
pub fn DerWriter::write_generalized_time(
  self : DerWriter,
  year : Int,
  month : Int,
  day : Int,
  hour : Int,
  minute : Int,
  second : Int,
) -> Unit {
  self.write_tag(Universal, false, tag_generalized_time)
  let s = format4(year) +
    format2(month) +
    format2(day) +
    format2(hour) +
    format2(minute) +
    format2(second) +
    "Z"
  let bytes = string_to_bytes(s)
  self.write_length(bytes.length())
  for i = 0; i < bytes.length(); i = i + 1 {
    self.buf.push(bytes[i])
  }
}

// ---------------------------------------------------------------------------
// Constructed type encoders
// ---------------------------------------------------------------------------

///|
/// Begin a SEQUENCE. Must be matched by `end_sequence()`.
/// The length is backpatched when `end_sequence()` is called.
pub fn DerWriter::begin_sequence(self : DerWriter) -> Unit {
  self.write_tag(Universal, true, 0x10) // SEQUENCE = 0x30
  self.stack.push(self.buf.length()) // Save position for length backpatch
  // Write a placeholder length (will be overwritten)
  self.buf.push(b'\x00')
}

///|
/// End a SEQUENCE. Backpatches the length.
pub fn DerWriter::end_sequence(self : DerWriter) -> Unit {
  let pos = self.stack[self.stack.length() - 1]
  ignore(self.stack.pop())
  let content_len = self.buf.length() - pos - 1 // Subtract placeholder byte
  // Calculate the length encoding size
  let len_bytes = if content_len < 128 {
    1
  } else {
    let mut n = content_len
    let mut count = 0
    while n > 0 {
      n = n >> 8
      count = count + 1
    }
    1 + count
  }
  if len_bytes == 1 {
    // Overwrite the placeholder
    self.buf[pos] = content_len.to_byte()
  } else {
    // Need to insert extra bytes for long-form length
    // Remove placeholder, insert proper length encoding
    self.buf[pos] = (0x80 | (len_bytes - 1)).to_byte()
    // Insert length bytes after position
    for i = len_bytes - 2; i >= 0; i = i - 1 {
      self.buf.insert(
        pos + 1 + (len_bytes - 2 - i),
        ((content_len >> (i * 8)) & 0xFF).to_byte(),
      )
    }
  }
}

///|
/// Begin a SET. Must be matched by `end_set()`.
/// DER requires SET elements to be sorted by their encoding.
pub fn DerWriter::begin_set(self : DerWriter) -> Unit {
  self.write_tag(Universal, true, 0x11) // SET = 0x31
  self.stack.push(self.buf.length())
  self.buf.push(b'\x00')
}

///|
/// End a SET. Backpatches the length.
/// Note: caller is responsible for writing elements in sorted order.
pub fn DerWriter::end_set(self : DerWriter) -> Unit {
  // Same as end_sequence
  let pos = self.stack[self.stack.length() - 1]
  ignore(self.stack.pop())
  let content_len = self.buf.length() - pos - 1
  let len_bytes = if content_len < 128 {
    1
  } else {
    let mut n = content_len
    let mut count = 0
    while n > 0 {
      n = n >> 8
      count = count + 1
    }
    1 + count
  }
  if len_bytes == 1 {
    self.buf[pos] = content_len.to_byte()
  } else {
    self.buf[pos] = (0x80 | (len_bytes - 1)).to_byte()
    for i = len_bytes - 2; i >= 0; i = i - 1 {
      self.buf.insert(
        pos + 1 + (len_bytes - 2 - i),
        ((content_len >> (i * 8)) & 0xFF).to_byte(),
      )
    }
  }
}

///|
/// Begin a context-specific constructed type [tag].
pub fn DerWriter::begin_context(self : DerWriter, tag_num : Int) -> Unit {
  self.write_tag(ContextSpecific, true, tag_num)
  self.stack.push(self.buf.length())
  self.buf.push(b'\x00')
}

///|
/// End a context-specific constructed type.
pub fn DerWriter::end_context(self : DerWriter) -> Unit {
  let pos = self.stack[self.stack.length() - 1]
  ignore(self.stack.pop())
  let content_len = self.buf.length() - pos - 1
  let len_bytes = if content_len < 128 {
    1
  } else {
    let mut n = content_len
    let mut count = 0
    while n > 0 {
      n = n >> 8
      count = count + 1
    }
    1 + count
  }
  if len_bytes == 1 {
    self.buf[pos] = content_len.to_byte()
  } else {
    self.buf[pos] = (0x80 | (len_bytes - 1)).to_byte()
    for i = len_bytes - 2; i >= 0; i = i - 1 {
      self.buf.insert(
        pos + 1 + (len_bytes - 2 - i),
        ((content_len >> (i * 8)) & 0xFF).to_byte(),
      )
    }
  }
}

///|
/// Write raw TLV bytes (pre-encoded).
pub fn DerWriter::write_raw(
  self : DerWriter,
  tag : Int,
  content : Array[Byte],
) -> Unit {
  self.buf.push(tag.to_byte())
  self.write_length(content.length())
  for i = 0; i < content.length(); i = i + 1 {
    self.buf.push(content[i])
  }
}

// ---------------------------------------------------------------------------
// DER Reader
// ---------------------------------------------------------------------------

///|
/// DER parser: reads TLV structures from a byte buffer.
pub struct DerReader {
  buf : Array[Byte]
  mut pos : Int
}

///|
/// Create a DER reader from a byte buffer.
pub fn DerReader::new(buf : Array[Byte]) -> DerReader {
  { buf, pos: 0 }
}

///|
/// Parsed TLV element.
pub struct DerElement {
  tag : Int // Full tag byte (e.g., 0x30 for SEQUENCE)
  tag_class : Int
  constructed : Bool
  tag_num : Int
  content : Array[Byte] // Content bytes (between length and next element)
  // For constructed types, content can be parsed recursively
}

///|
/// Read the next TLV element.
/// Returns None if at end of buffer.
pub fn DerReader::read_element(self : DerReader) -> DerElement? {
  if self.pos >= self.buf.length() {
    return None
  }
  // Read tag
  let tag_byte = self.buf[self.pos].to_int()
  self.pos = self.pos + 1
  let tag_class = tag_byte & 0xC0
  let constructed = (tag_byte & 0x20) != 0
  let mut tag_num = tag_byte & 0x1F
  if tag_num == 0x1F {
    // Multi-byte tag
    tag_num = 0
    let mut more = true
    while more {
      if self.pos >= self.buf.length() {
        return None
      }
      let b = self.buf[self.pos].to_int()
      self.pos = self.pos + 1
      tag_num = (tag_num << 7) | (b & 0x7F)
      more = (b & 0x80) != 0
    }
  }
  // Read length
  if self.pos >= self.buf.length() {
    return None
  }
  let len_byte = self.buf[self.pos].to_int()
  self.pos = self.pos + 1
  let mut length = 0
  if (len_byte & 0x80) == 0 {
    // Short form
    length = len_byte
  } else {
    // Long form
    let num_bytes = len_byte & 0x7F
    if num_bytes == 0 {
      // Indefinite length — not valid in DER
      return None
    }
    for i = 0; i < num_bytes; i = i + 1 {
      if self.pos >= self.buf.length() {
        return None
      }
      length = (length << 8) | self.buf[self.pos].to_int()
      self.pos = self.pos + 1
    }
  }
  // Read content
  if self.pos + length > self.buf.length() {
    return None
  }
  let content : Array[Byte] = []
  for i = 0; i < length; i = i + 1 {
    content.push(self.buf[self.pos])
    self.pos = self.pos + 1
  }
  Some({ tag: tag_byte, tag_class, constructed, tag_num, content })
}

///|
/// Peek at the next element's tag without consuming it.
pub fn DerReader::peek_tag(self : DerReader) -> Int? {
  if self.pos >= self.buf.length() {
    return None
  }
  Some(self.buf[self.pos].to_int())
}

///|
/// Get current position.
pub fn DerReader::position(self : DerReader) -> Int {
  self.pos
}

///|
/// Check if at end of buffer.
pub fn DerReader::at_end(self : DerReader) -> Bool {
  self.pos >= self.buf.length()
}

// ---------------------------------------------------------------------------
// Content decoders for DerElement
// ---------------------------------------------------------------------------

///|
/// Decode an INTEGER element to a signed Int.
pub fn decode_integer(elem : DerElement) -> Int? {
  if elem.tag_num != tag_integer || elem.tag_class != 0 {
    return None
  }
  if elem.content.length() == 0 {
    return Some(0)
  }
  let first = elem.content[0].to_int()
  let is_negative = (first & 0x80) != 0
  if is_negative {
    // Two's complement: sign-extend to 32 bits
    let mut result : UInt = 0
    for i = 0; i < elem.content.length(); i = i + 1 {
      result = (result << 8) | elem.content[i].to_uint()
    }
    // Sign-extend: fill remaining high bits with 1
    let bits = elem.content.length() * 8
    if bits < 32 {
      let mask = 0xFFFFFFFFU << bits
      result = result | mask
    }
    Some(result.reinterpret_as_int())
  } else {
    let mut result = 0
    for i = 0; i < elem.content.length(); i = i + 1 {
      result = (result << 8) | elem.content[i].to_int()
    }
    Some(result)
  }
}

///|
/// Decode an INTEGER element to a BigInt.
pub fn decode_big_integer(elem : DerElement) -> @bigint.BigInt? {
  if elem.tag_num != tag_integer || elem.tag_class != 0 {
    return None
  }
  if elem.content.length() == 0 {
    return Some(@bigint.from_int_value(0))
  }
  let first = elem.content[0].to_int()
  let is_negative = (first & 0x80) != 0
  if is_negative {
    // Two's complement: invert, add 1, negate
    let inverted : Array[Byte] = []
    for i = 0; i < elem.content.length(); i = i + 1 {
      inverted.push((0xFF ^ elem.content[i].to_int()).to_byte())
    }
    // Add 1
    let mut carry = 1
    for i = inverted.length() - 1; i >= 0 && carry > 0; i = i - 1 {
      let v = inverted[i].to_int() + carry
      inverted[i] = (v & 0xFF).to_byte()
      carry = v >> 8
    }
    // Convert to hex
    let hex = bytes_to_hex(inverted)
    match @bigint.from_string(hex) {
      Some(abs_val) => Some(@bigint.negate(abs_val))
      None => None
    }
  } else {
    // Positive: convert bytes to hex then to BigInt
    let hex = bytes_to_hex(elem.content)
    @bigint.from_string(hex)
  }
}

///|
/// Convert byte array to hex string.
fn bytes_to_hex(bytes : Array[Byte]) -> String {
  let hex = "0123456789ABCDEF".to_array()
  let result : Array[Char] = []
  for i = 0; i < bytes.length(); i = i + 1 {
    let v = bytes[i].to_int()
    result.push(hex[v >> 4])
    result.push(hex[v & 0x0F])
  }
  String::from_array(result)
}

///|
/// Decode a BOOLEAN element.
pub fn decode_boolean(elem : DerElement) -> Bool? {
  if elem.tag_num != tag_boolean || elem.tag_class != 0 {
    return None
  }
  if elem.content.length() != 1 {
    return None
  }
  Some(elem.content[0].to_int() != 0)
}

///|
/// Decode an OCTET STRING element.
pub fn decode_octet_string(elem : DerElement) -> Array[Byte]? {
  if elem.tag_num != tag_octet_string || elem.tag_class != 0 {
    return None
  }
  Some(elem.content)
}

///|
/// Decode a BIT STRING element. Returns (data, unused_bits).
pub fn decode_bit_string(elem : DerElement) -> (Array[Byte], Int)? {
  if elem.tag_num != tag_bit_string || elem.tag_class != 0 {
    return None
  }
  if elem.content.length() < 1 {
    return None
  }
  let unused = elem.content[0].to_int()
  let data : Array[Byte] = []
  for i = 1; i < elem.content.length(); i = i + 1 {
    data.push(elem.content[i])
  }
  Some((data, unused))
}

///|
/// Decode an OID element to a dotted-decimal string.
pub fn decode_oid(elem : DerElement) -> String? {
  if elem.tag_num != tag_oid || elem.tag_class != 0 {
    return None
  }
  if elem.content.length() == 0 {
    return None
  }
  // First two components are packed as 40*first + second, using bas1.0e-128.
  let mut i = 0
  let mut first_val = 0
  let mut more = true
  while more && i < elem.content.length() {
    let b = elem.content[i].to_int()
    first_val = (first_val << 7) | (b & 0x7F)
    more = (b & 0x80) != 0
    i = i + 1
  }
  let first = if first_val >= 80 { 2 } else { first_val / 40 }
  let second = first_val - first * 40
  let mut result = first.to_string() + "." + second.to_string()
  // Remaining components: bas1.0e-128
  while i < elem.content.length() {
    let mut val = 0
    let mut more = true
    while more && i < elem.content.length() {
      let b = elem.content[i].to_int()
      val = (val << 7) | (b & 0x7F)
      more = (b & 0x80) != 0
      i = i + 1
    }
    result = result + "." + val.to_string()
  }
  Some(result)
}

///|
/// Decode a NULL element (returns true if valid NULL).
pub fn decode_null(elem : DerElement) -> Bool {
  elem.tag_num == tag_null && elem.tag_class == 0 && elem.content.length() == 0
}

///|
/// Decode a PrintableString/UTF8String/IA5String element.
pub fn decode_string(elem : DerElement) -> String? {
  if elem.tag_class != 0 {
    return None
  }
  match elem.tag_num {
    0x0C | 0x13 | 0x16 | 0x14 | 0x1E => {
      let chars : Array[Char] = []
      for i = 0; i < elem.content.length(); i = i + 1 {
        match elem.content[i].to_int().to_char() {
          Some(c) => chars.push(c)
          None => chars.push('?')
        }
      }
      Some(String::from_array(chars))
    }
    _ => None
  }
}

///|
/// Decode a SEQUENCE element's content into a list of sub-elements.
pub fn decode_sequence(elem : DerElement) -> Array[DerElement]? {
  if elem.tag != tag_sequence {
    return None
  }
  let reader = DerReader::new(elem.content)
  let elements : Array[DerElement] = []
  while !reader.at_end() {
    match reader.read_element() {
      Some(e) => elements.push(e)
      None => break
    }
  }
  Some(elements)
}

///|
/// Decode a SET element's content into a list of sub-elements.
pub fn decode_set(elem : DerElement) -> Array[DerElement]? {
  if elem.tag != tag_set {
    return None
  }
  let reader = DerReader::new(elem.content)
  let elements : Array[DerElement] = []
  while !reader.at_end() {
    match reader.read_element() {
      Some(e) => elements.push(e)
      None => break
    }
  }
  Some(elements)
}

// ---------------------------------------------------------------------------
// Utility functions
// ---------------------------------------------------------------------------

///|
fn string_to_bytes(s : String) -> Array[Byte] {
  let bytes : Array[Byte] = []
  for c in s {
    let v = c.to_int()
    if v < 128 {
      bytes.push(v.to_byte())
    } else if v < 2048 {
      bytes.push((0xC0 | (v >> 6)).to_byte())
      bytes.push((0x80 | (v & 0x3F)).to_byte())
    } else if v < 65536 {
      bytes.push((0xE0 | (v >> 12)).to_byte())
      bytes.push((0x80 | ((v >> 6) & 0x3F)).to_byte())
      bytes.push((0x80 | (v & 0x3F)).to_byte())
    } else {
      bytes.push((0xF0 | (v >> 18)).to_byte())
      bytes.push((0x80 | ((v >> 12) & 0x3F)).to_byte())
      bytes.push((0x80 | ((v >> 6) & 0x3F)).to_byte())
      bytes.push((0x80 | (v & 0x3F)).to_byte())
    }
  }
  bytes
}

///|
fn format2(n : Int) -> String {
  if n < 10 {
    "0" + n.to_string()
  } else {
    n.to_string()
  }
}

///|
fn format4(n : Int) -> String {
  let s = n.to_string()
  let mut result = ""
  for i = 0; i < 4 - s.length(); i = i + 1 {
    result = result + "0"
  }
  result + s
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "asn1: integer encode/decode small positive" {
  let w = DerWriter::new()
  w.write_integer(42)
  let bytes = w.finish()
  assert_eq(bytes.length(), 3)
  assert_eq(bytes[0], b'\x02') // INTEGER tag
  assert_eq(bytes[1], b'\x01') // length 1
  assert_eq(bytes[2], b'\x2A') // 42
  let r = DerReader::new(bytes)
  let elem = r.read_element()
  assert_true(elem is Some(_))
  match elem {
    Some(e) => assert_eq(decode_integer(e), Some(42))
    None => assert_true(false)
  }
}

///|
test "asn1: integer encode/decode zero" {
  let w = DerWriter::new()
  w.write_integer(0)
  let bytes = w.finish()
  assert_eq(bytes[0], b'\x02')
  assert_eq(bytes[1], b'\x01')
  assert_eq(bytes[2], b'\x00')
}

///|
test "asn1: integer encode/decode negative" {
  let w = DerWriter::new()
  w.write_integer(-1)
  let bytes = w.finish()
  assert_eq(bytes[0], b'\x02')
  assert_eq(bytes[1], b'\x01')
  assert_eq(bytes[2], b'\xFF') // -1 in two's complement
  let r = DerReader::new(bytes)
  match r.read_element() {
    Some(e) => assert_eq(decode_integer(e), Some(-1))
    None => assert_true(false)
  }
}

///|
test "asn1: integer encode/decode 256" {
  let w = DerWriter::new()
  w.write_integer(256)
  let bytes = w.finish()
  // 256 = 0x0100, MSB of 0x01 is 0, so no leading zero needed
  assert_eq(bytes[0], b'\x02')
  assert_eq(bytes[1], b'\x02') // length 2
  assert_eq(bytes[2], b'\x01')
  assert_eq(bytes[3], b'\x00')
  let r = DerReader::new(bytes)
  match r.read_element() {
    Some(e) => assert_eq(decode_integer(e), Some(256))
    None => assert_true(false)
  }
}

///|
test "asn1: boolean encode/decode" {
  let w = DerWriter::new()
  w.write_boolean(true)
  let bytes = w.finish()
  assert_eq(bytes[0], b'\x01')
  assert_eq(bytes[1], b'\x01')
  assert_eq(bytes[2], b'\xFF')
  let r = DerReader::new(bytes)
  match r.read_element() {
    Some(e) => assert_eq(decode_boolean(e), Some(true))
    None => assert_true(false)
  }
  let w2 = DerWriter::new()
  w2.write_boolean(false)
  let bytes2 = w2.finish()
  assert_eq(bytes2[2], b'\x00')
}

///|
test "asn1: null encode/decode" {
  let w = DerWriter::new()
  w.write_null()
  let bytes = w.finish()
  assert_eq(bytes[0], b'\x05')
  assert_eq(bytes[1], b'\x00')
  let r = DerReader::new(bytes)
  match r.read_element() {
    Some(e) => assert_true(decode_null(e))
    None => assert_true(false)
  }
}

///|
test "asn1: oid encode/decode rsa" {
  let w = DerWriter::new()
  w.write_oid("1.2.840.113549.1.1.1")
  let bytes = w.finish()
  assert_eq(bytes[0], b'\x06') // OID tag
  let r = DerReader::new(bytes)
  match r.read_element() {
    Some(e) => assert_eq(decode_oid(e), Some("1.2.840.113549.1.1.1"))
    None => assert_true(false)
  }
}

///|
test "asn1: oid encode/decode ecdsa p256" {
  let w = DerWriter::new()
  w.write_oid("1.2.840.10045.2.1")
  let bytes = w.finish()
  let r = DerReader::new(bytes)
  match r.read_element() {
    Some(e) => assert_eq(decode_oid(e), Some("1.2.840.10045.2.1"))
    None => assert_true(false)
  }
}

///|
test "asn1: octet string encode/decode" {
  let data = [b'\x01', b'\x02', b'\x03', b'\x04']
  let w = DerWriter::new()
  w.write_octet_string(data)
  let bytes = w.finish()
  assert_eq(bytes[0], b'\x04')
  assert_eq(bytes[1], b'\x04')
  let r = DerReader::new(bytes)
  match r.read_element() {
    Some(e) =>
      match decode_octet_string(e) {
        Some(d) => assert_eq(d, data)
        None => assert_true(false)
      }
    None => assert_true(false)
  }
}

///|
test "asn1: bit string encode/decode" {
  let data = [b'\xC0']
  let w = DerWriter::new()
  w.write_bit_string(data, 0)
  let bytes = w.finish()
  assert_eq(bytes[0], b'\x03')
  assert_eq(bytes[1], b'\x02') // length 2
  assert_eq(bytes[2], b'\x00') // unused bits
  assert_eq(bytes[3], b'\xC0')
  let r = DerReader::new(bytes)
  match r.read_element() {
    Some(e) =>
      match decode_bit_string(e) {
        Some((d, u)) => {
          assert_eq(d, data)
          assert_eq(u, 0)
        }
        None => assert_true(false)
      }
    None => assert_true(false)
  }
}

///|
test "asn1: sequence encode/decode" {
  let w = DerWriter::new()
  w.begin_sequence()
  w.write_integer(1)
  w.write_integer(2)
  w.end_sequence()
  let bytes = w.finish()
  assert_eq(bytes[0], b'\x30') // SEQUENCE tag
  let r = DerReader::new(bytes)
  match r.read_element() {
    Some(e) => {
      assert_eq(e.tag, tag_sequence)
      match decode_sequence(e) {
        Some(elems) => {
          assert_eq(elems.length(), 2)
          assert_eq(decode_integer(elems[0]), Some(1))
          assert_eq(decode_integer(elems[1]), Some(2))
        }
        None => assert_true(false)
      }
    }
    None => assert_true(false)
  }
}

///|
test "asn1: nested sequence" {
  let w = DerWriter::new()
  w.begin_sequence()
  w.write_integer(42)
  w.begin_sequence()
  w.write_integer(1)
  w.write_integer(2)
  w.end_sequence()
  w.end_sequence()
  let bytes = w.finish()
  let r = DerReader::new(bytes)
  match r.read_element() {
    Some(e) =>
      match decode_sequence(e) {
        Some(elems) => {
          assert_eq(elems.length(), 2)
          assert_eq(decode_integer(elems[0]), Some(42))
          match decode_sequence(elems[1]) {
            Some(inner) => {
              assert_eq(inner.length(), 2)
              assert_eq(decode_integer(inner[0]), Some(1))
              assert_eq(decode_integer(inner[1]), Some(2))
            }
            None => assert_true(false)
          }
        }
        None => assert_true(false)
      }
    None => assert_true(false)
  }
}

///|
test "asn1: printable string encode/decode" {
  let w = DerWriter::new()
  w.write_printable_string("Hello")
  let bytes = w.finish()
  assert_eq(bytes[0], b'\x13') // PrintableString tag
  let r = DerReader::new(bytes)
  match r.read_element() {
    Some(e) => assert_eq(decode_string(e), Some("Hello"))
    None => assert_true(false)
  }
}

///|
test "asn1: utc time encode" {
  let w = DerWriter::new()
  w.write_utc_time(2023, 6, 15, 10, 30, 0)
  let bytes = w.finish()
  assert_eq(bytes[0], b'\x17') // UTCTime tag
  let r = DerReader::new(bytes)
  match r.read_element() {
    Some(e) => {
      // Content should be "230615103000Z"
      let s = bytes_to_string(e.content)
      assert_eq(s, "230615103000Z")
    }
    None => assert_true(false)
  }
}

///|
test "asn1: long length encoding" {
  let w = DerWriter::new()
  w.write_octet_string(Array::make(200, b'\xAA'))
  let bytes = w.finish()
  // Length 200 should use long form: 0x81 0xC8
  assert_eq(bytes[0], b'\x04') // OCTET STRING
  assert_eq(bytes[1], b'\x81') // long form, 1 length byte
  assert_eq(bytes[2].to_int(), 200) // content length is 200
}

///|
test "asn1: context-specific tag" {
  let w = DerWriter::new()
  w.begin_context(0)
  w.write_integer(42)
  w.end_context()
  let bytes = w.finish()
  assert_eq(bytes[0].to_int(), 0xA0) // context [0] constructed
  let r = DerReader::new(bytes)
  match r.read_element() {
    Some(e) => {
      assert_eq(e.tag_class, 0x80) // ContextSpecific
      assert_true(e.constructed)
      assert_eq(e.tag_num, 0)
    }
    None => assert_true(false)
  }
}

///|
test "asn1: rsa public key structure" {
  // Encode an RSA public key in PKCS#1 format:
  // RSAPublicKey ::= SEQUENCE { modulus INTEGER, publicExponent INTEGER }
  let w = DerWriter::new()
  w.begin_sequence()
  w.write_integer(65537)
  w.begin_sequence()
  w.write_oid("1.2.840.113549.1.1.1")
  w.write_null()
  w.end_sequence()
  w.end_sequence()
  let bytes = w.finish()
  // Round-trip
  let r = DerReader::new(bytes)
  match r.read_element() {
    Some(e) => {
      assert_eq(e.tag, tag_sequence)
      match decode_sequence(e) {
        Some(elems) => {
          assert_eq(elems.length(), 2)
          assert_eq(decode_integer(elems[0]), Some(65537))
          match decode_sequence(elems[1]) {
            Some(inner) => {
              assert_eq(inner.length(), 2)
              assert_eq(decode_oid(inner[0]), Some("1.2.840.113549.1.1.1"))
              assert_true(decode_null(inner[1]))
            }
            None => assert_true(false)
          }
        }
        None => assert_true(false)
      }
    }
    None => assert_true(false)
  }
}

///|
test "asn1: oid large component" {
  // OID with a large component (113549 = 0x1BB8D)
  let w = DerWriter::new()
  w.write_oid("1.2.840.113549")
  let bytes = w.finish()
  let r = DerReader::new(bytes)
  match r.read_element() {
    Some(e) => assert_eq(decode_oid(e), Some("1.2.840.113549"))
    None => assert_true(false)
  }
}

///|
test "asn1: set encode/decode" {
  let w = DerWriter::new()
  w.begin_set()
  w.write_integer(1)
  w.write_integer(2)
  w.end_set()
  let bytes = w.finish()
  assert_eq(bytes[0], b'\x31') // SET tag
  let r = DerReader::new(bytes)
  match r.read_element() {
    Some(e) => {
      assert_eq(e.tag, tag_set)
      match decode_set(e) {
        Some(elems) => assert_eq(elems.length(), 2)
        None => assert_true(false)
      }
    }
    None => assert_true(false)
  }
}

///|
test "asn1: reader at_end" {
  let w = DerWriter::new()
  w.write_integer(1)
  let bytes = w.finish()
  let r = DerReader::new(bytes)
  assert_true(!r.at_end())
  let _ = r.read_element()
  assert_true(r.at_end())
}

///|
test "asn1: peek tag" {
  let w = DerWriter::new()
  w.write_integer(42)
  let bytes = w.finish()
  let r = DerReader::new(bytes)
  match r.peek_tag() {
    Some(t) => assert_eq(t, tag_integer)
    None => assert_true(false)
  }
  // Position should not advance
  assert_eq(r.position(), 0)
}

///|
fn bytes_to_string(bytes : Array[Byte]) -> String {
  let chars : Array[Char] = []
  for i = 0; i < bytes.length(); i = i + 1 {
    match bytes[i].to_int().to_char() {
      Some(c) => chars.push(c)
      None => chars.push('?')
    }
  }
  String::from_array(chars)
}

///|
/// Map Asn1Class to its tag byte prefix (internal validation).
fn _asn1_class_to_prefix(cls : Asn1Class) -> Int {
  match cls {
    Universal => 0x00
    Application => 0x40
    ContextSpecific => 0x80
    Private => 0xC0
  }
}

///|
/// All Asn1Class variants (internal validation).
fn _all_asn1_classes() -> Array[Asn1Class] {
  [Universal, Application, ContextSpecific, Private]
}
