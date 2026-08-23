/// Hex (Base16) encoding and decoding.
///
/// Provides RFC 4648 compliant hexadecimal encoding with:
///
/// - **Lowercase** output (`encode`) — the canonical form for cryptographic hashes,
///   keys, and protocol identifiers.
/// - **Uppercase** output (`encode_upper`) — for display contexts where
///   readability matters.
/// - Case-insensitive decoding (`decode`) — accepts both upper and lower case.
/// - **Constant-time** comparison helper (`ct_compare`) for hex-encoded secrets.
///
/// ## Complexity
///
/// - `encode` / `encode_upper` — O(n)
/// - `decode` — O(n)
///
/// ## References
///
/// - RFC 4648: The Base16, Base32, and Base64 Data Encodings
///
/// Not formally verified. Correctness is ensured by the test suite.

// ---------------------------------------------------------------------------
// Lookup tables
// ---------------------------------------------------------------------------

///|
/// Lowercase hex digits: '0'..'9', 'a'..'f'.
let hex_lower : FixedArray[Byte] = FixedArray::make(16, b'\x00')

///|
/// Uppercase hex digits: '0'..'9', 'A'..'F'.
let hex_upper : FixedArray[Byte] = FixedArray::make(16, b'\x00')

///|
/// Pre-filled decode table: maps ASCII byte → value 0–15, or -1 if invalid.
/// Indexed by byte value (0–255).
let hex_decode : FixedArray[Int] = FixedArray::make(256, -1)

///|
test "hex: init tables" {
  // Tables are initialised lazily on first use via init_tables().
  // This test verifies the initialisation is correct.
  init_tables()
  assert_eq(hex_lower[0], b'\x30') // '0'
  assert_eq(hex_lower[10], b'\x61') // 'a'
  assert_eq(hex_lower[15], b'\x66') // 'f'
  assert_eq(hex_upper[10], b'\x41') // 'A'
  assert_eq(hex_upper[15], b'\x46') // 'F'
  assert_eq(hex_decode[b'\x30'.to_int()], 0)
  assert_eq(hex_decode[b'\x39'.to_int()], 9)
  assert_eq(hex_decode[b'\x61'.to_int()], 10)
  assert_eq(hex_decode[b'\x66'.to_int()], 15)
  assert_eq(hex_decode[b'\x41'.to_int()], 10)
  assert_eq(hex_decode[b'\x46'.to_int()], 15)
  assert_eq(hex_decode[b'\x67'.to_int()], -1) // 'g' is invalid
  assert_eq(hex_decode[b'\x2f'.to_int()], -1) // '/' is invalid
}

///|
/// One-time initialisation of lookup tables.
/// Idempotent: calling multiple times is safe (values are just overwritten).
fn init_tables() -> Unit {
  // Fill lowercase: '0'-'9' (0x30-0x39), 'a'-'f' (0x61-0x66)
  for i = 0; i < 10; i = i + 1 {
    hex_lower[i] = (0x30 + i).to_byte()
    hex_upper[i] = (0x30 + i).to_byte()
  }
  for i = 0; i < 6; i = i + 1 {
    hex_lower[10 + i] = (0x61 + i).to_byte()
    hex_upper[10 + i] = (0x41 + i).to_byte()
  }
  // Fill decode table.
  for i = 0; i < 256; i = i + 1 {
    hex_decode[i] = -1
  }
  for i = 0; i < 10; i = i + 1 {
    hex_decode[0x30 + i] = i // '0'-'9'
  }
  for i = 0; i < 6; i = i + 1 {
    hex_decode[0x41 + i] = 10 + i // 'A'-'F'
    hex_decode[0x61 + i] = 10 + i // 'a'-'f'
  }
}

// ---------------------------------------------------------------------------
// Encoding
// ---------------------------------------------------------------------------

///|
/// Encode a byte array to a lowercase hexadecimal string.
///
/// Each byte produces two hex characters. The output string length is
/// exactly `2 * data.length()`.
///
/// Example: `[0xDE, 0xAD, 0xBE, 0xEF]` → `"deadbeef"`
pub fn encode(data : Bytes) -> String {
  init_tables()
  let n = data.length()
  let buf : Array[Byte] = Array::make(n * 2, b'\x00')
  for i = 0; i < n; i = i + 1 {
    let b = data[i].to_int()
    buf[i * 2] = hex_lower[(b >> 4) & 0x0F]
    buf[i * 2 + 1] = hex_lower[b & 0x0F]
  }
  bytes_to_string(Bytes::from_array(buf))
}

///|
/// Encode a byte array to an uppercase hexadecimal string.
///
/// Example: `[0xDE, 0xAD, 0xBE, 0xEF]` → `"DEADBEEF"`
pub fn encode_upper(data : Bytes) -> String {
  init_tables()
  let n = data.length()
  let buf : Array[Byte] = Array::make(n * 2, b'\x00')
  for i = 0; i < n; i = i + 1 {
    let b = data[i].to_int()
    buf[i * 2] = hex_upper[(b >> 4) & 0x0F]
    buf[i * 2 + 1] = hex_upper[b & 0x0F]
  }
  bytes_to_string(Bytes::from_array(buf))
}

// ---------------------------------------------------------------------------
// Decoding
// ---------------------------------------------------------------------------

///|
/// Decode a hexadecimal string to a byte array.
///
/// Accepts both uppercase and lowercase hex digits. The input string length
/// must be even. Returns `None` if the input contains invalid characters
/// or has an odd length.
///
/// Example: `"deadbeef"` → `Some([0xDE, 0xAD, 0xBE, 0xEF])`
pub fn decode(s : String) -> Bytes? {
  init_tables()
  let bytes = string_to_bytes(s)
  let n = bytes.length()
  if n % 2 != 0 {
    return None
  }
  let result : Array[Byte] = Array::make(n / 2, b'\x00')
  for i = 0; i < n; i = i + 2 {
    let hi = hex_decode[bytes[i].to_int()]
    let lo = hex_decode[bytes[i + 1].to_int()]
    if hi < 0 || lo < 0 {
      return None
    }
    result[i / 2] = ((hi << 4) | lo).to_byte()
  }
  Some(Bytes::from_array(result))
}

// ---------------------------------------------------------------------------
// Utility
// ---------------------------------------------------------------------------

///|
/// Constant-time comparison of two hex strings.
///
/// Compares the underlying byte values without short-circuiting on the first
/// difference. Useful for comparing hex-encoded MACs or tokens where timing
/// information could leak partial results.
///
/// Returns `true` if the strings represent identical byte sequences
/// (case-insensitive), `false` otherwise. Length mismatch does NOT cause
/// an early return.
pub fn ct_compare(a : String, b : String) -> Bool {
  let ba = string_to_bytes(a)
  let bb = string_to_bytes(b)
  let la = ba.length()
  let lb = bb.length()
  let max_len = if la > lb { la } else { lb }
  let mut diff = la ^ lb
  for i = 0; i < max_len; i = i + 1 {
    let va = if i < la { normalize_hex(ba[i]) } else { 0 }
    let vb = if i < lb { normalize_hex(bb[i]) } else { 0 }
    diff = diff | (va ^ vb)
  }
  diff == 0
}

///|
/// Normalize a hex character to its numeric value (0–15), or 0 if invalid.
/// Uppercase letters are converted to lowercase equivalent for comparison.
fn normalize_hex(b : Byte) -> Int {
  let v = b.to_int()
  if v >= 0x41 && v <= 0x46 {
    v - 0x41 + 10 // 'A'-'F'
  } else if v >= 0x61 && v <= 0x66 {
    v - 0x61 + 10 // 'a'-'f'
  } else if v >= 0x30 && v <= 0x39 {
    v - 0x30 // '0'-'9'
  } else {
    0
  }
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

///|
fn string_to_bytes(s : String) -> Bytes {
  let arr : Array[Byte] = []
  for c in s.iter() {
    arr.push(c.to_int().to_byte())
  }
  Bytes::from_array(arr)
}

///|
fn bytes_to_string(b : Bytes) -> String {
  let sb = StringBuilder::new()
  for i = 0; i < b.length(); i = i + 1 {
    sb.write_char(b[i].to_int().unsafe_to_char())
  }
  sb.to_string()
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "hex: encode empty" {
  assert_eq(encode(Bytes::make(0, b'\x00')), "")
}

///|
test "hex: encode known vectors" {
  // RFC 4648 Section 10 test vectors.
  assert_eq(encode(Bytes::from_array([])), "")
  assert_eq(encode(Bytes::from_array([b'\x66'])), "66")
  assert_eq(encode(Bytes::from_array([b'\x66', b'\x6f'])), "666f")
  assert_eq(encode(Bytes::from_array([b'\x66', b'\x6f', b'\x6f'])), "666f6f")
  assert_eq(
    encode(Bytes::from_array([b'\x66', b'\x6f', b'\x6f', b'\x62'])),
    "666f6f62",
  )
  assert_eq(
    encode(Bytes::from_array([b'\x66', b'\x6f', b'\x6f', b'\x62', b'\x61'])),
    "666f6f6261",
  )
  assert_eq(
    encode(
      Bytes::from_array([b'\x66', b'\x6f', b'\x6f', b'\x62', b'\x61', b'\x72']),
    ),
    "666f6f626172",
  )
}

///|
test "hex: encode_upper" {
  assert_eq(
    encode_upper(Bytes::from_array([b'\xDE', b'\xAD', b'\xBE', b'\xEF'])),
    "DEADBEEF",
  )
  assert_eq(encode_upper(Bytes::from_array([b'\x00', b'\xff'])), "00FF")
}

///|
test "hex: decode known vectors" {
  assert_true(decode("") is Some(_))
  assert_eq(decode("").unwrap().length(), 0)
  assert_eq(decode("66").unwrap(), Bytes::from_array([b'\x66']))
  assert_eq(decode("666f").unwrap(), Bytes::from_array([b'\x66', b'\x6f']))
  assert_eq(
    decode("666f6f").unwrap(),
    Bytes::from_array([b'\x66', b'\x6f', b'\x6f']),
  )
  assert_eq(
    decode("666f6f62").unwrap(),
    Bytes::from_array([b'\x66', b'\x6f', b'\x6f', b'\x62']),
  )
  assert_eq(
    decode("666f6f6261").unwrap(),
    Bytes::from_array([b'\x66', b'\x6f', b'\x6f', b'\x62', b'\x61']),
  )
  assert_eq(
    decode("666f6f626172").unwrap(),
    Bytes::from_array([b'\x66', b'\x6f', b'\x6f', b'\x62', b'\x61', b'\x72']),
  )
}

///|
test "hex: decode uppercase" {
  assert_eq(
    decode("DEADBEEF").unwrap(),
    Bytes::from_array([b'\xDE', b'\xAD', b'\xBE', b'\xEF']),
  )
  assert_eq(decode("00FF").unwrap(), Bytes::from_array([b'\x00', b'\xFF']))
}

///|
test "hex: decode mixed case" {
  assert_eq(
    decode("DeAdBeEf").unwrap(),
    Bytes::from_array([b'\xDE', b'\xAD', b'\xBE', b'\xEF']),
  )
  assert_eq(
    decode("aAbBcC").unwrap(),
    Bytes::from_array([b'\xAA', b'\xBB', b'\xCC']),
  )
}

///|
test "hex: decode invalid inputs" {
  // Odd length.
  assert_true(decode("abc") is None)
  // Invalid characters.
  assert_true(decode("xy") is None)
  assert_true(decode("gh") is None)
  assert_true(decode("0/") is None)
  assert_true(decode("@!") is None)
}

///|
test "hex: round-trip all byte values" {
  let arr : Array[Byte] = Array::make(256, b'\x00')
  for i = 0; i < 256; i = i + 1 {
    arr[i] = i.to_byte()
  }
  let data = Bytes::from_array(arr)
  let encoded = encode(data)
  let decoded = decode(encoded).unwrap()
  assert_eq(decoded.length(), 256)
  for i = 0; i < 256; i = i + 1 {
    assert_eq(decoded[i], data[i])
  }
}

///|
test "hex: round-trip with encode_upper" {
  let data = Bytes::from_array([
    b'\x00', b'\x01', b'\x7f', b'\x80', b'\xfe', b'\xff',
  ])
  let encoded = encode_upper(data)
  let decoded = decode(encoded).unwrap()
  assert_eq(decoded, data)
}

///|
test "hex: ct_compare equal" {
  assert_true(ct_compare("deadbeef", "deadbeef"))
  assert_true(ct_compare("DEADBEEF", "deadbeef"))
  assert_true(ct_compare("DeAdBeEf", "dEaDbEeF"))
}

///|
test "hex: ct_compare not equal" {
  assert_false(ct_compare("deadbeef", "deadbeeg"))
  assert_false(ct_compare("deadbeef", "deadbee0"))
  assert_false(ct_compare("deadbeef", "deadbee"))
  assert_false(ct_compare("deadbeef", "deadbeef00"))
}

///|
test "hex: encode all zeros" {
  let data = Bytes::make(8, b'\x00')
  assert_eq(encode(data), "0000000000000000")
}

///|
test "hex: encode all ones" {
  let data = Bytes::make(4, b'\xff')
  assert_eq(encode(data), "ffffffff")
}
