/// Shared UTF-8 encoding and decoding utilities.
///
/// Provides RFC 3629 compliant UTF-8 encode/decode functions that are used
/// across multiple packages (compression, crypto, containers). Centralising
/// these eliminates duplicated implementations and ensures consistent
/// handling of multi-byte characters.
///
/// ## RFC 3629 Encoding Rules
///
/// | Code Point Range | Bytes | Byte 1   | Byte 2   | Byte 3   | Byte 4   |
/// |------------------|-------|----------|----------|----------|----------|
/// | U+0000–U+007F    | 1     | 0xxxxxxx |          |          |          |
/// | U+0080–U+07FF    | 2     | 110xxxxx | 10xxxxxx |          |          |
/// | U+0800–U+FFFF    | 3     | 1110xxxx | 10xxxxxx | 10xxxxxx |          |
/// | U+10000–U+10FFFF | 4     | 11110xxx | 10xxxxxx | 10xxxxxx | 10xxxxxx |

///|
/// Encode a single Unicode code point into a byte buffer using UTF-8.
///
/// Appends 1–4 bytes to `buf` per RFC 3629. Code points above U+10FFFF
/// are silently skipped (invalid input).
pub fn utf8_encode(cp : UInt, buf : Array[Byte]) -> Unit {
  if cp > 0x10FFFFU {
    return
  }
  if cp < 0x80U {
    buf.push(cp.to_byte())
  } else if cp < 0x800U {
    buf.push((0xC0U | (cp >> 6)).to_byte())
    buf.push((0x80U | (cp & 0x3FU)).to_byte())
  } else if cp < 0x10000U {
    buf.push((0xE0U | (cp >> 12)).to_byte())
    buf.push((0x80U | ((cp >> 6) & 0x3FU)).to_byte())
    buf.push((0x80U | (cp & 0x3FU)).to_byte())
  } else {
    buf.push((0xF0U | (cp >> 18)).to_byte())
    buf.push((0x80U | ((cp >> 12) & 0x3FU)).to_byte())
    buf.push((0x80U | ((cp >> 6) & 0x3FU)).to_byte())
    buf.push((0x80U | (cp & 0x3FU)).to_byte())
  }
}

///|
/// Encode a single Unicode code point, emitting each byte via `emit`.
///
/// This callback-based variant is useful for streaming encoders that write
/// directly to a hash or checksum accumulator without materialising an
/// intermediate buffer.
pub fn utf8_encode_emit(cp : UInt, emit : (Byte) -> Unit) -> Unit {
  if cp > 0x10FFFFU {
    return
  }
  if cp < 0x80U {
    emit(cp.to_byte())
  } else if cp < 0x800U {
    emit((0xC0U | (cp >> 6)).to_byte())
    emit((0x80U | (cp & 0x3FU)).to_byte())
  } else if cp < 0x10000U {
    emit((0xE0U | (cp >> 12)).to_byte())
    emit((0x80U | ((cp >> 6) & 0x3FU)).to_byte())
    emit((0x80U | (cp & 0x3FU)).to_byte())
  } else {
    emit((0xF0U | (cp >> 18)).to_byte())
    emit((0x80U | ((cp >> 12) & 0x3FU)).to_byte())
    emit((0x80U | ((cp >> 6) & 0x3FU)).to_byte())
    emit((0x80U | (cp & 0x3FU)).to_byte())
  }
}

///|
/// Convert a MoonBit `String` to UTF-8 `Bytes`.
///
/// Iterates over Unicode code points (not bytes), encoding each according
/// to RFC 3629. The result is a compact byte sequence with no BOM.
pub fn string_to_bytes(s : String) -> Bytes {
  let buf : Array[Byte] = []
  for c in s.iter() {
    utf8_encode(c.to_uint(), buf)
  }
  Bytes::from_array(buf)
}

///|
/// Convert UTF-8 `Bytes` to a MoonBit `String`.
///
/// Decodes multi-byte sequences per RFC 3629. Invalid bytes (continuation
/// bytes without a lead byte, overlong sequences, or truncated sequences)
/// are replaced with U+FFFD (replacement character).
pub fn bytes_to_string(bytes : Bytes) -> String {
  let buf = StringBuilder()
  let n = bytes.length()
  let mut i = 0
  while i < n {
    let b0 = bytes[i].to_uint()
    let mut cp = b0
    let mut extra = 0
    if b0 <= 0x7FU {
      cp = b0
      extra = 0
    } else if (b0 & 0xE0U) == 0xC0U {
      cp = b0 & 0x1FU
      extra = 1
    } else if (b0 & 0xF0U) == 0xE0U {
      cp = b0 & 0x0FU
      extra = 2
    } else if (b0 & 0xF8U) == 0xF0U {
      cp = b0 & 0x07U
      extra = 3
    } else {
      buf.write_char('\u{FFFD}')
      i = i + 1
      continue
    }
    let mut j = 1
    while j <= extra && i + j < n {
      let bj = bytes[i + j].to_uint()
      if (bj & 0xC0U) != 0x80U {
        break
      }
      cp = (cp << 6) | (bj & 0x3FU)
      j = j + 1
    }
    buf.write_char(cp.reinterpret_as_int().unsafe_to_char())
    i = i + extra + 1
  }
  buf.to_string()
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "encoding: round-trip ASCII" {
  let s = "Hello, World!"
  let b = string_to_bytes(s)
  assert_eq(bytes_to_string(b), s)
}

///|
test "encoding: round-trip multi-byte" {
  let s = "日本語テスト αβγδ 🚀🎉"
  let b = string_to_bytes(s)
  assert_eq(bytes_to_string(b), s)
}

///|
test "encoding: empty string" {
  let b = string_to_bytes("")
  assert_eq(b.length(), 0)
  assert_eq(bytes_to_string(b), "")
}

///|
test "encoding: invalid bytes replaced" {
  // 0xFF is not a valid UTF-8 lead byte.
  let b = Bytes::from_array([b'\x48', b'\xFF', b'\x49'])
  let s = bytes_to_string(b)
  assert_eq(s.length(), 3) // 'H', U+FFFD, 'I'
}
