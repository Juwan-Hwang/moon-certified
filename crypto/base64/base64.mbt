/// Base64 encoding and decoding (RFC 4648).
///
/// Provides standard and URL-safe Base64 encoding/decoding with proper
/// padding handling and strict input validation on decode.
///
/// ## API
///
/// - `encode(data)` — standard Base64 with `+` / `/` and `=` padding
/// - `encode_url_safe(data)` — URL-safe variant with `-` / `_`
/// - `decode(s)` — decode standard Base64, returns `None` on invalid input
/// - `decode_url_safe(s)` — decode URL-safe Base64
/// - `decode_any(s)` — accepts either alphabet
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Alphabet tables (built lazily via functions)
// ---------------------------------------------------------------------------

///|
/// Build the RFC 4648 standard alphabet: `A-Z a-z 0-9 + /`.
fn build_std_alphabet() -> FixedArray[Int] {
  let a = FixedArray::make(64, 0)
  for i = 0; i < 26; i = i + 1 {
    a[i] = 65 + i
  }
  for i = 0; i < 26; i = i + 1 {
    a[26 + i] = 97 + i
  }
  for i = 0; i < 10; i = i + 1 {
    a[52 + i] = 48 + i
  }
  a[62] = 43
  a[63] = 47
  a
}

///|
/// Build the RFC 4648 URL-safe alphabet: `A-Z a-z 0-9 - _`.
fn build_url_alphabet() -> FixedArray[Int] {
  let a = build_std_alphabet()
  a[62] = 45
  a[63] = 95
  a
}

///|
/// Build a reverse lookup table from an alphabet: maps char code → 6-bit value.
/// A value of -1 means "invalid character".
fn build_decode_table(alphabet : FixedArray[Int]) -> FixedArray[Int] {
  let t = FixedArray::make(256, -1)
  for i = 0; i < 64; i = i + 1 {
    t[alphabet[i]] = i
  }
  t
}

// ---------------------------------------------------------------------------
// Encoding
// ---------------------------------------------------------------------------

///|
/// Encode a byte array into a standard Base64 string with `=` padding.
///
/// Returns an empty string for empty input. The output length is always
/// a multiple of 4.
pub fn encode(data : FixedArray[Byte]) -> String {
  encode_with_alphabet(data, build_std_alphabet(), true)
}

///|
/// Encode a byte array into a URL-safe Base64 string with `=` padding.
///
/// Uses `-` and `_` instead of `+` and `/` so the output is safe to embed
/// in URLs and filenames without percent-encoding.
pub fn encode_url_safe(data : FixedArray[Byte]) -> String {
  encode_with_alphabet(data, build_url_alphabet(), true)
}

///|
/// Encode without `=` padding. Some protocols (JWS, certain JWTs) require
/// unpadded Base64.
pub fn encode_unpadded(data : FixedArray[Byte]) -> String {
  encode_with_alphabet(data, build_std_alphabet(), false)
}

///|
/// URL-safe variant without padding.
pub fn encode_url_safe_unpadded(data : FixedArray[Byte]) -> String {
  encode_with_alphabet(data, build_url_alphabet(), false)
}

///|
fn encode_with_alphabet(
  data : FixedArray[Byte],
  alphabet : FixedArray[Int],
  padded : Bool,
) -> String {
  let n = data.length()
  if n == 0 {
    return ""
  }
  let full_groups = n / 3
  let remainder = n % 3
  let out_len = if padded {
    (n + 2) / 3 * 4
  } else if remainder == 0 {
    full_groups * 4
  } else if remainder == 1 {
    full_groups * 4 + 2
  } else {
    full_groups * 4 + 3
  }
  let buf = FixedArray::make(out_len, 0)
  let mut idx = 0
  for g = 0; g < full_groups; g = g + 1 {
    let b0 = data[g * 3].to_int()
    let b1 = data[g * 3 + 1].to_int()
    let b2 = data[g * 3 + 2].to_int()
    buf[idx] = alphabet[(b0 >> 2) & 0x3F]
    idx = idx + 1
    buf[idx] = alphabet[((b0 << 4) | (b1 >> 4)) & 0x3F]
    idx = idx + 1
    buf[idx] = alphabet[((b1 << 2) | (b2 >> 6)) & 0x3F]
    idx = idx + 1
    buf[idx] = alphabet[b2 & 0x3F]
    idx = idx + 1
  }
  if remainder == 1 {
    let b0 = data[full_groups * 3].to_int()
    buf[idx] = alphabet[(b0 >> 2) & 0x3F]
    idx = idx + 1
    buf[idx] = alphabet[(b0 << 4) & 0x3F]
    idx = idx + 1
    if padded {
      buf[idx] = 61
      idx = idx + 1
      buf[idx] = 61
      idx = idx + 1
    }
  } else if remainder == 2 {
    let b0 = data[full_groups * 3].to_int()
    let b1 = data[full_groups * 3 + 1].to_int()
    buf[idx] = alphabet[(b0 >> 2) & 0x3F]
    idx = idx + 1
    buf[idx] = alphabet[((b0 << 4) | (b1 >> 4)) & 0x3F]
    idx = idx + 1
    buf[idx] = alphabet[(b1 << 2) & 0x3F]
    idx = idx + 1
    if padded {
      buf[idx] = 61
      idx = idx + 1
    }
  }
  let chars : Array[Char] = []
  for i = 0; i < idx; i = i + 1 {
    chars.push(buf[i].unsafe_to_char())
  }
  String::from_array(chars)
}

// ---------------------------------------------------------------------------
// Decoding
// ---------------------------------------------------------------------------

///|
/// Decode a standard Base64 string. Returns `None` if the input contains
/// invalid characters or has incorrect padding.
pub fn decode(s : String) -> FixedArray[Byte]? {
  decode_with_table(s, build_decode_table(build_std_alphabet()))
}

///|
/// Decode a URL-safe Base64 string. Returns `None` on invalid input.
pub fn decode_url_safe(s : String) -> FixedArray[Byte]? {
  decode_with_table(s, build_decode_table(build_url_alphabet()))
}

///|
/// Decode a Base64 string that may use either standard or URL-safe alphabet.
/// Returns `None` on invalid input.
pub fn decode_any(s : String) -> FixedArray[Byte]? {
  let result = decode(s)
  match result {
    Some(_) => result
    None => decode_url_safe(s)
  }
}

///|
fn decode_with_table(s : String, table : FixedArray[Int]) -> FixedArray[Byte]? {
  let n = s.length()
  if n == 0 {
    return Some(FixedArray::make(0, b'\x00'))
  }
  let mut pad = 0
  let mut actual_len = n
  for i = 0; i < n; i = i + 1 {
    let ch = s[i].to_int()
    if ch == 61 {
      pad = pad + 1
    } else if table[ch] == -1 {
      if ch != 10 && ch != 13 && ch != 32 {
        return None
      }
      actual_len = actual_len - 1
    } else {
      pad = 0
    }
  }
  if pad > 2 {
    return None
  }
  // Validate total length: when padded, total length (including '=') must
  // be a multiple of 4. When unpadded, the data length must be 0, 2, or 3
  // mod 4 (a remainder of 1 is invalid — it would represent a truncated
  // 6-bit group with no valid byte output).
  if pad > 0 {
    if n % 4 != 0 {
      return None
    }
  } else {
    let r = actual_len % 4
    if r == 1 {
      return None
    }
  }
  let values : Array[Int] = []
  for i = 0; i < n; i = i + 1 {
    let ch = s[i].to_int()
    if ch == 61 {
      break
    }
    let v = table[ch]
    if v == -1 {
      if ch == 10 || ch == 13 || ch == 32 {
        continue
      }
      return None
    }
    values.push(v)
  }
  let out_len = values.length() * 3 / 4
  let result = FixedArray::make(out_len, b'\x00')
  let mut ri = 0
  let full = values.length() / 4
  for g = 0; g < full; g = g + 1 {
    let v0 = values[g * 4]
    let v1 = values[g * 4 + 1]
    let v2 = values[g * 4 + 2]
    let v3 = values[g * 4 + 3]
    result[ri] = ((v0 << 2) | (v1 >> 4)).to_byte()
    ri = ri + 1
    result[ri] = (((v1 & 0xF) << 4) | (v2 >> 2)).to_byte()
    ri = ri + 1
    result[ri] = (((v2 & 0x3) << 6) | v3).to_byte()
    ri = ri + 1
  }
  let rem = values.length() % 4
  if rem == 2 {
    let v0 = values[full * 4]
    let v1 = values[full * 4 + 1]
    result[ri] = ((v0 << 2) | (v1 >> 4)).to_byte()
    ri = ri + 1
  } else if rem == 3 {
    let v0 = values[full * 4]
    let v1 = values[full * 4 + 1]
    let v2 = values[full * 4 + 2]
    result[ri] = ((v0 << 2) | (v1 >> 4)).to_byte()
    ri = ri + 1
    result[ri] = (((v1 & 0xF) << 4) | (v2 >> 2)).to_byte()
    ri = ri + 1
  }
  Some(result)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
fn str_to_bytes(s : String) -> FixedArray[Byte] {
  let arr = FixedArray::make(s.length(), b'\x00')
  for i = 0; i < s.length(); i = i + 1 {
    arr[i] = s[i].to_int().to_byte()
  }
  arr
}

///|
test "base64: RFC 4648 test vectors" {
  assert_eq(encode(FixedArray::make(0, b'\x00')), "")
  assert_eq(encode(str_to_bytes("f")), "Zg==")
  assert_eq(encode(str_to_bytes("fo")), "Zm8=")
  assert_eq(encode(str_to_bytes("foo")), "Zm9v")
  assert_eq(encode(str_to_bytes("foob")), "Zm9vYg==")
  assert_eq(encode(str_to_bytes("fooba")), "Zm9vYmE=")
  assert_eq(encode(str_to_bytes("foobar")), "Zm9vYmFy")
}

///|
test "base64: round-trip decode" {
  let inputs = ["", "f", "fo", "foo", "foob", "fooba", "foobar", "hello world"]
  for i = 0; i < inputs.length(); i = i + 1 {
    let encoded = encode(str_to_bytes(inputs[i]))
    match decode(encoded) {
      Some(decoded) => {
        assert_eq(decoded.length(), inputs[i].length())
        for j = 0; j < decoded.length(); j = j + 1 {
          assert_eq(decoded[j].to_int(), inputs[i][j].to_int())
        }
      }
      None => abort("decode failed for: " + inputs[i])
    }
  }
}

///|
test "base64: url-safe variant" {
  let data : FixedArray[Byte] = FixedArray::make(3, b'\x00')
  data[0] = b'\xfb'
  data[1] = b'\xff'
  data[2] = b'\xbf'
  let std_encoded = encode(data)
  let url_encoded = encode_url_safe(data)
  assert_true(std_encoded.contains("+") || std_encoded.contains("/"))
  assert_false(url_encoded.contains("+"))
  assert_false(url_encoded.contains("/"))
  match decode(std_encoded) {
    Some(d) => {
      assert_eq(d.length(), 3)
      assert_eq(d[0], b'\xfb')
      assert_eq(d[1], b'\xff')
      assert_eq(d[2], b'\xbf')
    }
    None => abort("decode failed")
  }
  match decode_url_safe(url_encoded) {
    Some(d) => {
      assert_eq(d.length(), 3)
      assert_eq(d[0], b'\xfb')
      assert_eq(d[1], b'\xff')
      assert_eq(d[2], b'\xbf')
    }
    None => abort("decode_url_safe failed")
  }
}

///|
test "base64: unpadded encoding" {
  assert_eq(encode_unpadded(str_to_bytes("f")), "Zg")
  assert_eq(encode_unpadded(str_to_bytes("fo")), "Zm8")
  assert_eq(encode_unpadded(str_to_bytes("foo")), "Zm9v")
  match decode("Zm9v") {
    Some(d) => assert_eq(d.length(), 3)
    None => abort("decode unpadded failed")
  }
}

///|
test "base64: invalid input rejected" {
  assert_true(decode("!!!") == None)
  assert_true(decode("Zg=") == None)
  assert_true(decode("====") == None)
}

///|
test "base64: binary data round-trip" {
  let data = FixedArray::make(256, b'\x00')
  for i = 0; i < 256; i = i + 1 {
    data[i] = i.to_byte()
  }
  let encoded = encode(data)
  match decode(encoded) {
    Some(decoded) => {
      assert_eq(decoded.length(), 256)
      for i = 0; i < 256; i = i + 1 {
        assert_eq(decoded[i], data[i])
      }
    }
    None => abort("binary round-trip failed")
  }
}

///|
test "base64: decode_any accepts both" {
  let data : FixedArray[Byte] = FixedArray::make(3, b'\x00')
  data[0] = b'\xfb'
  data[1] = b'\xff'
  data[2] = b'\xbf'
  let std_encoded = encode(data)
  let url_encoded = encode_url_safe(data)
  assert_true(decode_any(std_encoded) != None)
  assert_true(decode_any(url_encoded) != None)
}
