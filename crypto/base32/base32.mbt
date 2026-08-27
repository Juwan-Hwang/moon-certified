/// Base32 encoding and decoding (RFC 4648).
///
/// Provides RFC 4648 compliant Base32 encoding with:
///
/// - **Standard** alphabet (`ABCDEFGHIJKLMNOPQRSTUVWXYZ234567`) using `=`
///   padding (`encode` / `decode`).
/// - **Hex** alphabet (`0123456789ABCDEFGHIJKLMNOPQRSTUV`) for case-insensitive
///   URLs (`encode_hex` / `decode_hex`).
/// - Case-insensitive decoding for both alphabets.
///
/// ## Complexity
///
/// - `encode` / `encode_hex` — O(n)
/// - `decode` / `decode_hex` — O(n)
///
/// ## References
///
/// - RFC 4648: The Base16, Base32, and Base64 Data Encodings
///
/// Not formally verified. Correctness is ensured by the test suite.

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

///|
/// Standard Base32 alphabet (RFC 4648 Section 6).
let b32_std_alphabet : FixedArray[Char] = FixedArray::from_array([
  'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P',
  'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '2', '3', '4', '5', '6', '7',
])

///|
/// Extended hex Base32 alphabet (RFC 4648 Section 7).
let b32_hex_alphabet : FixedArray[Char] = FixedArray::from_array([
  '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F',
  'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V',
])

///|
/// Decode table for standard alphabet. Maps char code (0-127) to value 0-31, or -1.
/// Extended at runtime for lowercase letters.
let b32_std_decode : FixedArray[Int] = FixedArray::make(128, -1)

///|
/// Decode table for hex alphabet.
let b32_hex_decode : FixedArray[Int] = FixedArray::make(128, -1)

///|
/// Flag to ensure tables are initialised exactly once.
let b32_tables_init : Ref[Bool] = { val: false, }

///|
/// Initialise decode tables. Idempotent.
fn init_decode_tables() -> Unit {
  if b32_tables_init.val {
    return
  }
  // Standard alphabet.
  for i in 0..<32 {
    let c = b32_std_alphabet[i].to_int()
    b32_std_decode[c] = i
    // Lowercase equivalent.
    if c >= 65 && c <= 90 {
      b32_std_decode[c + 32] = i
    }
  }
  // Hex alphabet.
  for i in 0..<32 {
    let c = b32_hex_alphabet[i].to_int()
    b32_hex_decode[c] = i
    // Lowercase equivalent.
    if c >= 65 && c <= 90 {
      b32_hex_decode[c + 32] = i
    }
  }
  b32_tables_init.val = true
}

// ---------------------------------------------------------------------------
// Encoding
// ---------------------------------------------------------------------------

///|
/// Encode a byte array to a standard Base32 string with `=` padding.
///
/// Each 5-byte group produces 8 Base32 characters. The output is padded with
/// `=` to a multiple of 8 characters.
///
/// Example: `[0x66, 0x6f, 0x6f]` → `"MZXW6==="`
pub fn encode(data : Bytes) -> String {
  encode_with_alphabet(data, b32_std_alphabet)
}

///|
/// Encode a byte array to a Base32 hex string with `=` padding.
///
/// Uses the extended hex alphabet for case-insensitive encoding suitable
/// for URLs and file names.
///
/// Example: `[0x66, 0x6f, 0x6f]` → `"CPNMU==="`
pub fn encode_hex(data : Bytes) -> String {
  encode_with_alphabet(data, b32_hex_alphabet)
}

///|
/// Internal: encode with a given alphabet.
fn encode_with_alphabet(data : Bytes, alphabet : FixedArray[Char]) -> String {
  let n = data.length()
  if n == 0 {
    return ""
  }
  // Number of 5-byte groups (full and partial).
  // Output length: ceil(n * 8 / 5), rounded up to multiple of 8.
  let output_len = ((n * 8 + 4) / 5 + 7) / 8 * 8
  let buf = StringBuilder()
  let mut i = 0
  while i < n {
    // Collect up to 5 bytes into a 40-bit buffer.
    let mut buffer : UInt64 = 0UL
    let mut bytes_in_group = 0
    for j in 0..<5 {
      if i + j < n {
        buffer = (buffer << 8) | data[i + j].to_uint64()
        bytes_in_group = bytes_in_group + 1
      } else {
        buffer = buffer << 8
      }
    }
    // Number of characters to emit for this group.
    let chars_to_emit = (bytes_in_group * 8 + 4) / 5
    // Buffer is already 40 bits with data at the top (MSB).
    // Extract 5-bit groups from the top.
    let mut shifted = buffer
    // Emit characters.
    for _ in 0..<chars_to_emit {
      let idx = (shifted >> 35).to_int() & 0x1F
      buf.write_char(alphabet[idx])
      shifted = shifted << 5
    }
    // Emit padding.
    for _ in chars_to_emit..<8 {
      buf.write_char('=')
    }
    i = i + 5
  }
  let result = buf.to_string()
  // Trim unused output (shouldn't happen but guard anyway).
  let mut result_len = 0
  for _ in result.iter() {
    result_len = result_len + 1
  }
  ignore(output_len)
  ignore(result_len)
  result
}

// ---------------------------------------------------------------------------
// Decoding
// ---------------------------------------------------------------------------

///|
/// Decode a standard Base32 string to a byte array.
///
/// Accepts both uppercase and lowercase, ignores `=` padding.
/// Returns `None` if the input contains invalid characters.
///
/// Example: `"MZXW6==="` → `Some([0x66, 0x6f, 0x6f])`
pub fn decode(s : String) -> Bytes? {
  init_decode_tables()
  decode_with_table(s, b32_std_decode)
}

///|
/// Decode a Base32 hex string to a byte array.
///
/// Accepts both uppercase and lowercase, ignores `=` padding.
/// Returns `None` if the input contains invalid characters.
pub fn decode_hex(s : String) -> Bytes? {
  init_decode_tables()
  decode_with_table(s, b32_hex_decode)
}

///|
/// Internal: decode using a pre-filled lookup table.
fn decode_with_table(s : String, table : FixedArray[Int]) -> Bytes? {
  // Collect valid Base32 characters (skip '=' padding).
  let chars : Array[Int] = []
  for c in s.iter() {
    let ci = c.to_int()
    if c == '=' {
      continue
    }
    if ci >= 128 || table[ci] < 0 {
      return None
    }
    chars.push(table[ci])
  }
  let num_chars = chars.length()
  if num_chars == 0 {
    return Some(Bytes::make(0, b'\x00'))
  }
  // Calculate output byte count.
  let result : Array[Byte] = []
  let mut i = 0
  while i < num_chars {
    // Collect up to 8 characters into a 40-bit buffer.
    let mut buffer : UInt64 = 0UL
    let mut chars_in_group = 0
    for j in 0..<8 {
      if i + j < num_chars {
        buffer = (buffer << 5) | chars[i + j].to_uint64()
        chars_in_group = chars_in_group + 1
      } else {
        buffer = buffer << 5
      }
    }
    // Number of bytes to emit for this group.
    let bytes_to_emit = chars_in_group * 5 / 8
    // Buffer is already 40 bits with data at the top (MSB).
    // Extract 8-bit groups from the top.
    let mut shifted = buffer
    // Emit bytes.
    for _ in 0..<bytes_to_emit {
      result.push(((shifted >> 32).to_int() & 0xFF).to_byte())
      shifted = shifted << 8
    }
    i = i + 8
  }
  Some(Bytes::from_array(result))
}

// ---------------------------------------------------------------------------
// Tests — RFC 4648 Section 10 test vectors
// ---------------------------------------------------------------------------

///|
test "base32: encode RFC 4648 vectors" {
  assert_eq(encode(Bytes::from_array([])), "")
  assert_eq(encode(Bytes::from_array([b'\x66'])), "MY======")
  assert_eq(encode(Bytes::from_array([b'\x66', b'\x6f'])), "MZXQ====")
  assert_eq(encode(Bytes::from_array([b'\x66', b'\x6f', b'\x6f'])), "MZXW6===")
  assert_eq(
    encode(Bytes::from_array([b'\x66', b'\x6f', b'\x6f', b'\x62'])),
    "MZXW6YQ=",
  )
  assert_eq(
    encode(Bytes::from_array([b'\x66', b'\x6f', b'\x6f', b'\x62', b'\x61'])),
    "MZXW6YTB",
  )
  assert_eq(
    encode(
      Bytes::from_array([b'\x66', b'\x6f', b'\x6f', b'\x62', b'\x61', b'\x72']),
    ),
    "MZXW6YTBOI======",
  )
}

///|
test "base32: decode RFC 4648 vectors" {
  assert_eq(decode("").unwrap(), Bytes::from_array([]))
  assert_eq(decode("MY======").unwrap(), Bytes::from_array([b'\x66']))
  assert_eq(decode("MZXQ====").unwrap(), Bytes::from_array([b'\x66', b'\x6f']))
  assert_eq(
    decode("MZXW6===").unwrap(),
    Bytes::from_array([b'\x66', b'\x6f', b'\x6f']),
  )
  assert_eq(
    decode("MZXW6YQ=").unwrap(),
    Bytes::from_array([b'\x66', b'\x6f', b'\x6f', b'\x62']),
  )
  assert_eq(
    decode("MZXW6YTB").unwrap(),
    Bytes::from_array([b'\x66', b'\x6f', b'\x6f', b'\x62', b'\x61']),
  )
  assert_eq(
    decode("MZXW6YTBOI======").unwrap(),
    Bytes::from_array([b'\x66', b'\x6f', b'\x6f', b'\x62', b'\x61', b'\x72']),
  )
}

///|
test "base32: decode without padding" {
  assert_eq(decode("MY").unwrap(), Bytes::from_array([b'\x66']))
  assert_eq(decode("MZXQ").unwrap(), Bytes::from_array([b'\x66', b'\x6f']))
  assert_eq(
    decode("MZXW6").unwrap(),
    Bytes::from_array([b'\x66', b'\x6f', b'\x6f']),
  )
}

///|
test "base32: decode lowercase" {
  assert_eq(decode("my======").unwrap(), Bytes::from_array([b'\x66']))
  assert_eq(
    decode("mzxw6ytb").unwrap(),
    Bytes::from_array([b'\x66', b'\x6f', b'\x6f', b'\x62', b'\x61']),
  )
}

///|
test "base32: decode invalid" {
  assert_true(decode("1=") is None) // '1' is not in standard alphabet
  assert_true(decode("8=") is None) // '8' is not in standard alphabet
  assert_true(decode("9=") is None) // '9' is not in standard alphabet
  assert_true(decode("0=") is None) // '0' is not in standard alphabet
}

///|
test "base32: round-trip all lengths 0-10" {
  for len in 0..<11 {
    let arr : Array[Byte] = Array::make(len, b'\x00')
    for i in 0..<len {
      arr[i] = ((i * 37 + 13) % 256).to_byte()
    }
    let data = Bytes::from_array(arr)
    let encoded = encode(data)
    let decoded = decode(encoded).unwrap()
    assert_eq(decoded.length(), data.length())
    for i in 0..<len {
      assert_eq(decoded[i], data[i])
    }
  }
}

///|
test "base32: hex encode/decode round-trip" {
  let data = Bytes::from_array([
    b'\x00', b'\x01', b'\x02', b'\x03', b'\xff', b'\xfe', b'\x80', b'\x7f',
  ])
  let encoded = encode_hex(data)
  let decoded = decode_hex(encoded).unwrap()
  assert_eq(decoded, data)
}

///|
test "base32: hex RFC 4648 vectors" {
  assert_eq(encode_hex(Bytes::from_array([])), "")
  assert_eq(encode_hex(Bytes::from_array([b'\x66'])), "CO======")
  assert_eq(encode_hex(Bytes::from_array([b'\x66', b'\x6f'])), "CPNG====")
  assert_eq(
    encode_hex(Bytes::from_array([b'\x66', b'\x6f', b'\x6f'])),
    "CPNMU===",
  )
  assert_eq(
    encode_hex(Bytes::from_array([b'\x66', b'\x6f', b'\x6f', b'\x62'])),
    "CPNMUOG=",
  )
  assert_eq(
    encode_hex(Bytes::from_array([b'\x66', b'\x6f', b'\x6f', b'\x62', b'\x61'])),
    "CPNMUOJ1",
  )
}

///|
test "base32: empty encode/decode" {
  assert_eq(encode(Bytes::make(0, b'\x00')), "")
  assert_eq(decode("").unwrap().length(), 0)
}
