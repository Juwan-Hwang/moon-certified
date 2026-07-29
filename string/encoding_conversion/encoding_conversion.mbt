/// Character encoding conversion.
///
/// Provides conversion between UTF-8, UTF-16, ISO-8859-1 (Latin-1),
/// and ASCII encodings.
///
/// ## Supported conversions
///
/// - UTF-8 ↔ UTF-16 (big-endian and little-endian)
/// - UTF-8 ↔ ISO-8859-1 (Latin-1)
/// - UTF-8 ↔ ASCII (with replacement for non-ASCII)
///
/// ## References
///
/// - RFC 3629: UTF-8, a transformation format of ISO 10646
/// - ISO/IEC 8859-1: Latin-1
///
/// `proof-enabled` is `false`.

///|
/// Convert a Unicode codepoint array to UTF-8 bytes.
fn codepoints_to_utf8(cps : Array[Int]) -> Bytes {
  let buf : Array[Byte] = []
  for i = 0; i < cps.length(); i = i + 1 {
    let cp = cps[i]
    if cp <= 0x7F {
      buf.push(cp.to_byte())
    } else if cp <= 0x7FF {
      buf.push((0xC0 | (cp >> 6)).to_byte())
      buf.push((0x80 | (cp & 0x3F)).to_byte())
    } else if cp <= 0xFFFF {
      buf.push((0xE0 | (cp >> 12)).to_byte())
      buf.push((0x80 | ((cp >> 6) & 0x3F)).to_byte())
      buf.push((0x80 | (cp & 0x3F)).to_byte())
    } else {
      buf.push((0xF0 | (cp >> 18)).to_byte())
      buf.push((0x80 | ((cp >> 12) & 0x3F)).to_byte())
      buf.push((0x80 | ((cp >> 6) & 0x3F)).to_byte())
      buf.push((0x80 | (cp & 0x3F)).to_byte())
    }
  }
  Bytes::from_array(buf)
}

///|
/// Convert UTF-8 bytes to a Unicode codepoint array.
fn utf8_to_codepoints(data : Bytes) -> Array[Int]? {
  let cps : Array[Int] = []
  let mut i = 0
  while i < data.length() {
    let b = data[i].to_int()
    if b <= 0x7F {
      cps.push(b)
      i = i + 1
    } else if b >> 5 == 0x6 {
      if i + 1 >= data.length() {
        return None
      }
      let cp = ((b & 0x1F) << 6) | (data[i + 1].to_int() & 0x3F)
      cps.push(cp)
      i = i + 2
    } else if b >> 4 == 0xE {
      if i + 2 >= data.length() {
        return None
      }
      let cp = ((b & 0x0F) << 12) | ((data[i + 1].to_int() & 0x3F) << 6) | (data[i + 2].to_int() & 0x3F)
      cps.push(cp)
      i = i + 3
    } else if b >> 3 == 0x1E {
      if i + 3 >= data.length() {
        return None
      }
      let cp = ((b & 0x07) << 18) | ((data[i + 1].to_int() & 0x3F) << 12) | ((data[i + 2].to_int() & 0x3F) << 6) | (data[i + 3].to_int() & 0x3F)
      cps.push(cp)
      i = i + 4
    } else {
      return None
    }
  }
  Some(cps)
}

///|
/// Convert a String (UTF-8 internally) to UTF-16BE bytes.
pub fn utf8_to_utf16be(s : String) -> Bytes {
  let cps = match utf8_to_codepoints(@utils.string_to_bytes(s)) {
    None => return Bytes::make(0, b'\x00')
    Some(c) => c
  }
  let buf : Array[Byte] = []
  for i = 0; i < cps.length(); i = i + 1 {
    let cp = cps[i]
    if cp <= 0xFFFF {
      buf.push(((cp >> 8) & 0xFF).to_byte())
      buf.push((cp & 0xFF).to_byte())
    } else {
      // Surrogate pair
      let adjusted = cp - 0x10000
      let high = 0xD800 + (adjusted >> 10)
      let low = 0xDC00 + (adjusted & 0x3FF)
      buf.push(((high >> 8) & 0xFF).to_byte())
      buf.push((high & 0xFF).to_byte())
      buf.push(((low >> 8) & 0xFF).to_byte())
      buf.push((low & 0xFF).to_byte())
    }
  }
  Bytes::from_array(buf)
}

///|
/// Convert UTF-16BE bytes to a UTF-8 String.
pub fn utf16be_to_utf8(data : Bytes) -> String? {
  let cps : Array[Int] = []
  let mut i = 0
  while i + 1 < data.length() {
    let hi = (data[i].to_int() << 8) | data[i + 1].to_int()
    i = i + 2
    if hi >= 0xD800 && hi <= 0xDBFF {
      // High surrogate, need low surrogate
      if i + 1 >= data.length() {
        return None
      }
      let lo = (data[i].to_int() << 8) | data[i + 1].to_int()
      i = i + 2
      if lo < 0xDC00 || lo > 0xDFFF {
        return None
      }
      let cp = 0x10000 + ((hi - 0xD800) << 10) + (lo - 0xDC00)
      cps.push(cp)
    } else {
      cps.push(hi)
    }
  }
  Some(@utils.bytes_to_string(codepoints_to_utf8(cps)))
}

///|
/// Convert UTF-8 String to UTF-16LE bytes.
pub fn utf8_to_utf16le(s : String) -> Bytes {
  let be = utf8_to_utf16be(s)
  // Swap byte order
  let buf : Array[Byte] = []
  let mut i = 0
  while i + 1 < be.length() {
    buf.push(be[i + 1])
    buf.push(be[i])
    i = i + 2
  }
  Bytes::from_array(buf)
}

///|
/// Convert UTF-16LE bytes to a UTF-8 String.
pub fn utf16le_to_utf8(data : Bytes) -> String? {
  // Swap to BE then convert
  let buf : Array[Byte] = []
  let mut i = 0
  while i + 1 < data.length() {
    buf.push(data[i + 1])
    buf.push(data[i])
    i = i + 2
  }
  utf16be_to_utf8(Bytes::from_array(buf))
}

///|
/// Convert UTF-8 String to ISO-8859-1 (Latin-1) bytes.
/// Characters outside Latin-1 range (U+0100+) are replaced with '?'.
pub fn utf8_to_latin1(s : String) -> Bytes {
  let cps = match utf8_to_codepoints(@utils.string_to_bytes(s)) {
    None => return Bytes::make(0, b'\x00')
    Some(c) => c
  }
  let buf : Array[Byte] = []
  for i = 0; i < cps.length(); i = i + 1 {
    if cps[i] <= 0xFF {
      buf.push(cps[i].to_byte())
    } else {
      buf.push(b'?')
    }
  }
  Bytes::from_array(buf)
}

///|
/// Convert ISO-8859-1 (Latin-1) bytes to a UTF-8 String.
pub fn latin1_to_utf8(data : Bytes) -> String {
  let cps : Array[Int] = []
  for i = 0; i < data.length(); i = i + 1 {
    cps.push(data[i].to_int())
  }
  @utils.bytes_to_string(codepoints_to_utf8(cps))
}

///|
/// Convert UTF-8 String to ASCII bytes.
/// Non-ASCII characters are replaced with '?'.
pub fn utf8_to_ascii(s : String) -> Bytes {
  let cps = match utf8_to_codepoints(@utils.string_to_bytes(s)) {
    None => return Bytes::make(0, b'\x00')
    Some(c) => c
  }
  let buf : Array[Byte] = []
  for i = 0; i < cps.length(); i = i + 1 {
    if cps[i] <= 0x7F {
      buf.push(cps[i].to_byte())
    } else {
      buf.push(b'?')
    }
  }
  Bytes::from_array(buf)
}

///|
/// Convert ASCII bytes to a UTF-8 String.
/// Bytes with high bit set are replaced with '?'.
pub fn ascii_to_utf8(data : Bytes) -> String {
  let cps : Array[Int] = []
  for i = 0; i < data.length(); i = i + 1 {
    let b = data[i].to_int()
    if b <= 0x7F {
      cps.push(b)
    } else {
      cps.push(0x3F) // '?'
    }
  }
  @utils.bytes_to_string(codepoints_to_utf8(cps))
}

///|
test "encoding_conversion: UTF-8 to UTF-16BE roundtrip" {
  let s = "Hello, 世界"
  let utf16 = utf8_to_utf16be(s)
  let result = utf16be_to_utf8(utf16)
  match result {
    Some(r) => assert_eq(r, s)
    None => assert_true(false)
  }
}

///|
test "encoding_conversion: UTF-8 to Latin-1 roundtrip" {
  let s = "café"
  let latin1 = utf8_to_latin1(s)
  assert_eq(latin1.length(), 4)
  let result = latin1_to_utf8(latin1)
  assert_eq(result, s)
}

///|
test "encoding_conversion: Latin-1 out of range replacement" {
  // 世界 contains codepoints above U+00FF
  let s = "世界"
  let latin1 = utf8_to_latin1(s)
  // Both characters should be replaced with '?'
  assert_eq(latin1.length(), 2)
  assert_eq(latin1[0], b'?')
  assert_eq(latin1[1], b'?')
}

///|
test "encoding_conversion: ASCII conversion" {
  let s = "Hello"
  let ascii = utf8_to_ascii(s)
  assert_eq(ascii.length(), 5)
  let result = ascii_to_utf8(ascii)
  assert_eq(result, s)
}

///|
test "encoding_conversion: UTF-16LE roundtrip" {
  let s = "Test Ünïcödé"
  let utf16le = utf8_to_utf16le(s)
  let result = utf16le_to_utf8(utf16le)
  match result {
    Some(r) => assert_eq(r, s)
    None => assert_true(false)
  }
}
