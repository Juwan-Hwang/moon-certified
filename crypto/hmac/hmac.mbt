/// HMAC (Hash-based Message Authentication Code) — HMAC-SHA-256.
///
/// HMAC is a mechanism for message authentication using cryptographic
/// hash functions. It is defined in RFC 2104 and widely used in protocols
/// like TLS, JWT, and AWS Signature v4.
///
/// ## Algorithm
///
/// Given a hash function H with block size B (64 bytes for SHA-256):
/// ```
/// HMAC(K, m) = H((K ⊕ opad) || H((K ⊕ ipad) || m))
/// ```
/// where ipad = 0x36 repeated B times, opad = 0x5c repeated B times.
///
/// If the key is longer than B, it is first hashed to produce a shorter key.
///
/// ## Complexity
/// - O(|key| + |message|) for computation.
///
/// ## Security
/// HMAC-SHA-256 is considered secure for message authentication.
/// The security depends on the underlying SHA-256 hash function and
/// the secrecy of the key.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

///|
/// SHA-256 block size in bytes.
const BLOCK_SIZE : Int = 64

///|
/// Hex lookup table.
let hex_chars : FixedArray[Char] = FixedArray::from_array([
  '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
])

///|
/// Compute HMAC-SHA-256 of a message with the given key.
///
/// Returns the 32-byte authentication tag.
pub fn hmac_sha256(key : Bytes, message : Bytes) -> Bytes {
  // Step 1: Normalize key to block size.
  // If key is longer than block size, hash it first.
  let normalized_key = if key.length() > BLOCK_SIZE {
    @sha256.sha256(key)
  } else {
    key
  }
  // Step 2: Pad key to block size with zeros and create ipad/opad.
  // Since Bytes is immutable, we build Arrays and convert.
  let k_buf : Array[Byte] = Array::make(BLOCK_SIZE, b'\x00')
  for i = 0; i < normalized_key.length(); i = i + 1 {
    k_buf[i] = normalized_key[i]
  }
  // Step 3: Create ipad and opad.
  let ipad : Array[Byte] = Array::make(BLOCK_SIZE, b'\x00')
  let opad : Array[Byte] = Array::make(BLOCK_SIZE, b'\x00')
  for i = 0; i < BLOCK_SIZE; i = i + 1 {
    let ki = k_buf[i].to_int()
    ipad[i] = (ki ^ 0x36).to_byte()
    opad[i] = (ki ^ 0x5c).to_byte()
  }
  // Step 4: inner = H(ipad || message)
  let inner_data : Array[Byte] = Array::make(
    BLOCK_SIZE + message.length(),
    b'\x00',
  )
  for i = 0; i < BLOCK_SIZE; i = i + 1 {
    inner_data[i] = ipad[i]
  }
  for i = 0; i < message.length(); i = i + 1 {
    inner_data[BLOCK_SIZE + i] = message[i]
  }
  let inner_hash = @sha256.sha256(Bytes::from_array(inner_data))
  // Step 5: outer = H(opad || inner)
  let outer_data : Array[Byte] = Array::make(
    BLOCK_SIZE + inner_hash.length(),
    b'\x00',
  )
  for i = 0; i < BLOCK_SIZE; i = i + 1 {
    outer_data[i] = opad[i]
  }
  for i = 0; i < inner_hash.length(); i = i + 1 {
    outer_data[BLOCK_SIZE + i] = inner_hash[i]
  }
  @sha256.sha256(Bytes::from_array(outer_data))
}

///|
/// Compute HMAC-SHA-256 and return as a lowercase hex string.
pub fn hmac_sha256_hex(key : Bytes, message : Bytes) -> String {
  let result = hmac_sha256(key, message)
  let buf = StringBuilder()
  for i = 0; i < result.length(); i = i + 1 {
    let b = result[i].to_int() & 0xFF
    buf.write_char(hex_chars[(b >> 4) & 0xF])
    buf.write_char(hex_chars[b & 0xF])
  }
  buf.to_string()
}

///|
/// Constant-time comparison of two byte arrays.
/// Returns true if they are equal. Does not short-circuit, preventing
/// timing attacks.
pub fn constant_time_eq(a : Bytes, b : Bytes) -> Bool {
  if a.length() != b.length() {
    return false
  }
  let mut diff = 0
  for i = 0; i < a.length(); i = i + 1 {
    diff = diff | (a[i].to_int() ^ b[i].to_int())
  }
  diff == 0
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "hmac: rfc 4231 test case 1" {
  // Test case from RFC 4231 Section 4.2
  let key = Bytes::from_array([
    b'\x0b', b'\x0b', b'\x0b', b'\x0b', b'\x0b', b'\x0b', b'\x0b', b'\x0b', b'\x0b',
    b'\x0b', b'\x0b', b'\x0b', b'\x0b', b'\x0b', b'\x0b', b'\x0b', b'\x0b', b'\x0b',
    b'\x0b', b'\x0b',
  ])
  let data = @utils.string_to_bytes("Hi There")
  let expected = "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7"
  assert_eq(hmac_sha256_hex(key, data), expected)
}

///|
test "hmac: rfc 4231 test case 2" {
  // Jefe key with message "what do ya want for nothing?"
  let key = @utils.string_to_bytes("Jefe")
  let data = @utils.string_to_bytes("what do ya want for nothing?")
  let expected = "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"
  assert_eq(hmac_sha256_hex(key, data), expected)
}

///|
test "hmac: empty message" {
  let key = Bytes::from_array([
    b'\x0b', b'\x0b', b'\x0b', b'\x0b', b'\x0b', b'\x0b', b'\x0b', b'\x0b', b'\x0b',
    b'\x0b', b'\x0b', b'\x0b', b'\x0b', b'\x0b', b'\x0b', b'\x0b', b'\x0b', b'\x0b',
    b'\x0b', b'\x0b',
  ])
  let data = b""
  let result = hmac_sha256(key, data)
  assert_eq(result.length(), 32)
}

///|
test "hmac: long key" {
  // Key longer than block size (64 bytes) — should be hashed first.
  let key = @utils.string_to_bytes(
    "This is a very long key that exceeds the SHA-256 block size of 64 bytes and must be hashed first before being used in HMAC computation",
  )
  let data = @utils.string_to_bytes("message")
  let result = hmac_sha256(key, data)
  assert_eq(result.length(), 32)
}

///|
test "hmac: determinism" {
  let key = @utils.string_to_bytes("secret")
  let msg = @utils.string_to_bytes("hello")
  assert_eq(hmac_sha256(key, msg), hmac_sha256(key, msg))
}

///|
test "hmac: different keys produce different macs" {
  let msg = @utils.string_to_bytes("hello")
  let mac1 = hmac_sha256(@utils.string_to_bytes("key1"), msg)
  let mac2 = hmac_sha256(@utils.string_to_bytes("key2"), msg)
  assert_true(mac1 != mac2)
}

///|
test "hmac: constant_time_eq" {
  let a = Bytes::from_array([b'\x01', b'\x02', b'\x03', b'\x04'])
  let b = Bytes::from_array([b'\x01', b'\x02', b'\x03', b'\x04'])
  let c = Bytes::from_array([b'\x01', b'\x02', b'\x03', b'\x05'])
  assert_true(constant_time_eq(a, b))
  assert_false(constant_time_eq(a, c))
  assert_false(
    constant_time_eq(a, Bytes::from_array([b'\x01', b'\x02', b'\x03'])),
  )
}
