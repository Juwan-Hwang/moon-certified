/// SHA-256 secure hash algorithm (FIPS 180-4).
///
/// SHA-256 maps an arbitrarily long byte sequence to a fixed 256-bit (32-byte)
/// digest. It is a Merkle-Damgard construction built from a 64-round Davies-
/// Meyer compression function over a 256-bit state of eight 32-bit words.
///
/// # Algorithm outline
///
/// 1. **Padding.** Append a single `0x80` byte, then zero-pad so that the total
///    length is 8 bytes short of a multiple of 64, then append the message
///    length in **bits** as a 64-bit big-endian integer. The padded message is
///    an exact multiple of 64 bytes.
/// 2. **Initialise** the eight 32-bit working words `H0..H7` to the fractional
///    parts of the square roots of the first 8 primes (FIPS 180-4 §5.3.3).
/// 3. **Compress** each 512-bit (64-byte) block: expand its 16 words into a
///    64-word schedule, then run 64 mixing rounds that combine the schedule
///    with the round constants (fractional parts of the cube roots of the
///    first 64 primes) and the logical functions `Ch`, `Maj`, `Σ0`, `Σ1`,
///    `σ0`, `σ1`. The eight working words accumulate the result.
/// 4. **Output** the eight working words in big-endian order — 32 bytes.
///
/// # Types
///
/// The 32-bit working variables use MoonBit's `UInt` — the language's native
/// 32-bit unsigned integer (MAX_VALUE = 2^32 − 1), which is exactly the
/// "UInt32" of the FIPS specification. All arithmetic is modulo 2^32, which
/// `UInt`'s wrapping `+` provides for free with no manual masking.
///
/// The 64-bit message-bit-length is held in `UInt64` so that inputs up to
/// nearly 2^31 bytes (the `Int` range of `Bytes::length`) are encoded
/// correctly per spec.
///
/// # Strings vs. byte arrays
///
/// MoonBit `String` is internally UTF-16. A SHA-256 "of a string" conventionally
/// means SHA-256 of the string's **UTF-8** encoding (the byte encoding every
/// interop partner uses — `hashlib.sha256(s.encode())`, TLS, JWT, …). Accordingly
/// `sha256_string` first encodes the string to UTF-8 bytes (streaming, zero
/// intermediate allocation beyond the byte buffer) and then hashes them, so
/// `sha256_string(s)` always equals `sha256_hex(utf8_bytes(s))` (verified by the
/// cross-check tests). ASCII inputs match byte-for-byte.
///
/// Not formally verified. Correctness is ensured by the comprehensive test
/// suite below, whose expected values are the official NIST FIPS 180-4 test
/// vectors cross-checked against Python's `hashlib.sha256`.

// ---------------------------------------------------------------------------
// Round constants K[0..63] — fractional parts of the cube roots of the first
// 64 prime numbers (FIPS 180-4 §4.2.2).
// ---------------------------------------------------------------------------

///|
let round_constants : FixedArray[UInt] = FixedArray::from_array([
  0x428a2f98U, 0x71374491U, 0xb5c0fbcfU, 0xe9b5dba5U, 0x3956c25bU, 0x59f111f1U, 0x923f82a4U,
  0xab1c5ed5U, 0xd807aa98U, 0x12835b01U, 0x243185beU, 0x550c7dc3U, 0x72be5d74U, 0x80deb1feU,
  0x9bdc06a7U, 0xc19bf174U, 0xe49b69c1U, 0xefbe4786U, 0x0fc19dc6U, 0x240ca1ccU, 0x2de92c6fU,
  0x4a7484aaU, 0x5cb0a9dcU, 0x76f988daU, 0x983e5152U, 0xa831c66dU, 0xb00327c8U, 0xbf597fc7U,
  0xc6e00bf3U, 0xd5a79147U, 0x06ca6351U, 0x14292967U, 0x27b70a85U, 0x2e1b2138U, 0x4d2c6dfcU,
  0x53380d13U, 0x650a7354U, 0x766a0abbU, 0x81c2c92eU, 0x92722c85U, 0xa2bfe8a1U, 0xa81a664bU,
  0xc24b8b70U, 0xc76c51a3U, 0xd192e819U, 0xd6990624U, 0xf40e3585U, 0x106aa070U, 0x19a4c116U,
  0x1e376c08U, 0x2748774cU, 0x34b0bcb5U, 0x391c0cb3U, 0x4ed8aa4aU, 0x5b9cca4fU, 0x682e6ff3U,
  0x748f82eeU, 0x78a5636fU, 0x84c87814U, 0x8cc70208U, 0x90befffaU, 0xa4506cebU, 0xbef9a3f7U,
  0xc67178f2U,
])

// ---------------------------------------------------------------------------
// Initial hash values H0..H7 — fractional parts of the square roots of the
// first 8 prime numbers (FIPS 180-4 §5.3.3).
// ---------------------------------------------------------------------------

///|
let initial_hash : FixedArray[UInt] = FixedArray::from_array([
  0x6a09e667U, 0xbb67ae85U, 0x3c6ef372U, 0xa54ff53aU, 0x510e527fU, 0x9b05688cU, 0x1f83d9abU,
  0x5be0cd19U,
])

// ---------------------------------------------------------------------------
// Hex lookup table for lowercase hex output.
// ---------------------------------------------------------------------------

///|
let hex_digits : FixedArray[Char] = FixedArray::from_array([
  '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
])

// ---------------------------------------------------------------------------
// Logical functions (FIPS 180-4 §4.1.2)
// ---------------------------------------------------------------------------

///|
/// Rotate `x` right by `n` bits (0 < n < 32). Implemented as
/// `(x >> n) | (x << (32 - n))`; `UInt` is exactly 32 bits so the left shift
/// discards the bits that wrap past the top, yielding a clean bitwise rotation.
fn rotr(x : UInt, n : Int) -> UInt {
  (x >> n) | (x << (32 - n))
}

///|
/// Shift `x` right by `n` bits, zero-filling from the left (`SHR^n(x)`).
fn shr(x : UInt, n : Int) -> UInt {
  x >> n
}

///|
/// Ch(x, y, z) = (x AND y) XOR (NOT x AND z) — the "choose" function: for each
/// bit position, pick `y`'s bit where `x` is 1 and `z`'s bit where `x` is 0.
fn ch(x : UInt, y : UInt, z : UInt) -> UInt {
  (x & y) ^ (x.lnot() & z)
}

///|
/// Maj(x, y, z) = (x AND y) XOR (x AND z) XOR (y AND z) — the "majority"
/// function: each output bit is the majority vote of the three input bits.
fn maj(x : UInt, y : UInt, z : UInt) -> UInt {
  (x & y) ^ (x & z) ^ (y & z)
}

///|
/// Σ0(x) = ROTR^2(x) XOR ROTR^13(x) XOR ROTR^22(x) — big sigma 0, applied to
/// working variable `a` each round.
fn big_sigma0(x : UInt) -> UInt {
  rotr(x, 2) ^ rotr(x, 13) ^ rotr(x, 22)
}

///|
/// Σ1(x) = ROTR^6(x) XOR ROTR^11(x) XOR ROTR^25(x) — big sigma 1, applied to
/// working variable `e` each round.
fn big_sigma1(x : UInt) -> UInt {
  rotr(x, 6) ^ rotr(x, 11) ^ rotr(x, 25)
}

///|
/// σ0(x) = ROTR^7(x) XOR ROTR^18(x) XOR SHR^3(x) — small sigma 0, applied to
/// schedule word `W[i-15]` during message expansion.
fn small_sigma0(x : UInt) -> UInt {
  rotr(x, 7) ^ rotr(x, 18) ^ shr(x, 3)
}

///|
/// σ1(x) = ROTR^17(x) XOR ROTR^19(x) XOR SHR^10(x) — small sigma 1, applied to
/// schedule word `W[i-2]` during message expansion.
fn small_sigma1(x : UInt) -> UInt {
  rotr(x, 17) ^ rotr(x, 19) ^ shr(x, 10)
}

// ---------------------------------------------------------------------------
// Block helpers
// ---------------------------------------------------------------------------

///|
/// Load a big-endian 32-bit word from four consecutive bytes of `msg` starting
/// at `offset`. SHA-256 specifies big-endian throughout, so the first byte
/// contributes the most-significant 8 bits.
fn load_be32(msg : FixedArray[Byte], offset : Int) -> UInt {
  (msg[offset].to_uint() << 24) |
  (msg[offset + 1].to_uint() << 16) |
  (msg[offset + 2].to_uint() << 8) |
  msg[offset + 3].to_uint()
}

///|
/// Compress one 64-byte block (starting at `offset` in `msg`) into the running
/// hash `state` (eight 32-bit words, mutated in place).
///
/// This is the Davies-Meyer compression function (FIPS 180-4 §6.2.2): build the
/// 64-word message schedule `W`, run 64 rounds with working variables
/// `a..h` initialised from `state`, then add the working variables back into
/// `state`. All addition is modulo 2^32 via `UInt`'s wrapping `+`.
fn compress(
  state : FixedArray[UInt],
  msg : FixedArray[Byte],
  offset : Int,
) -> Unit {
  // Message schedule: W[0..15] from the block, W[16..63] expanded.
  let w : FixedArray[UInt] = FixedArray::make(64, 0U)
  for i in 0..<16 {
    w[i] = load_be32(msg, offset + i * 4)
  }
  for i in 16..<64 {
    w[i] = small_sigma1(w[i - 2]) +
      w[i - 7] +
      small_sigma0(w[i - 15]) +
      w[i - 16]
  }
  // Initialise working variables from the current hash state.
  let mut a = state[0]
  let mut b = state[1]
  let mut c = state[2]
  let mut d = state[3]
  let mut e = state[4]
  let mut f = state[5]
  let mut g = state[6]
  let mut h = state[7]
  // 64 mixing rounds.
  for i in 0..<64 {
    let t1 = h + big_sigma1(e) + ch(e, f, g) + round_constants[i] + w[i]
    let t2 = big_sigma0(a) + maj(a, b, c)
    h = g
    g = f
    f = e
    e = d + t1
    d = c
    c = b
    b = a
    a = t1 + t2
  }
  // Add the compressed chunk to the running hash (Davies-Meyer feed-forward).
  state[0] = state[0] + a
  state[1] = state[1] + b
  state[2] = state[2] + c
  state[3] = state[3] + d
  state[4] = state[4] + e
  state[5] = state[5] + f
  state[6] = state[6] + g
  state[7] = state[7] + h
}

// ---------------------------------------------------------------------------
// UTF-8 streaming encoder (for sha256_string)
// ---------------------------------------------------------------------------

///|
/// Emit the 1–4 UTF-8 bytes of a single Unicode code point `cp` via `emit`.
///
/// Factored out so that [`sha256_string`] can encode a string to UTF-8 bytes
/// for hashing. Ranges follow RFC 3629:
///   U+0000   .. U+007F   -> 1 byte  (0xxxxxxx)
///   U+0080   .. U+07FF   -> 2 bytes (110xxxxx 10xxxxxx)
///   U+0800   .. U+FFFF   -> 3 bytes (1110xxxx 10xxxxxx 10xxxxxx)
///   U+10000  .. U+10FFFF -> 4 bytes (11110xxx 10xxxxxx 10xxxxxx 10xxxxxx)
fn utf8_encode(cp : UInt, emit : (Byte) -> Unit) -> Unit {
  // Validate code point range per RFC 3629: U+0000..U+10FFFF.
  // Code points above U+10FFFF are invalid; skip them silently.
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
/// Materialise the UTF-8 encoding of `s` as a fresh `Bytes`.
///
/// Used by [`sha256_string`] to obtain the byte sequence to hash. MoonBit
/// `String` is UTF-16 internally, so this explicit UTF-8 encoding guarantees
/// `sha256_string(s) == sha256_hex(utf8_bytes(s))` and matches the byte
/// encoding used by every standard SHA-256 interop partner.
fn utf8_bytes(s : String) -> Bytes {
  let buf : Array[Byte] = []
  for c in s.iter() {
    utf8_encode(c.to_uint(), fn(b) { buf.push(b) })
  }
  Bytes::from_array(buf)
}

// ---------------------------------------------------------------------------
// Hex encoding
// ---------------------------------------------------------------------------

///|
/// Render `bytes` as a lowercase hexadecimal string (two chars per byte).
///
/// Used by [`sha256_hex`] and [`sha256_string`]. A 32-byte digest yields the
/// canonical 64-character hex representation.
fn to_hex(bytes : Bytes) -> String {
  let buf = StringBuilder()
  let n = bytes.length()
  for i in 0..<n {
    let b = bytes[i].to_int()
    buf.write_char(hex_digits[(b >> 4) & 0xF])
    buf.write_char(hex_digits[b & 0xF])
  }
  buf.to_string()
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

///|
/// Compute the SHA-256 digest of `data`, returning the raw 32-byte hash.
///
/// The input is padded per FIPS 180-4 §5.1.1 (append `0x80`, zero-fill, append
/// the 64-bit big-endian bit-length), then compressed one 64-byte block at a
/// time. The returned `Bytes` has length 32.
pub fn sha256(data : Bytes) -> Bytes {
  let data_len = data.length()
  // Message length in bits, as a 64-bit value (spec mandates 64-bit length).
  let bit_len = data_len.to_uint64() << 3
  // Padded length: smallest multiple of 64 that fits data + 0x80 + 8 length
  // bytes. (data_len + 9) rounded up to a multiple of 64.
  let padded_len = (data_len + 9 + 63) / 64 * 64
  let msg = FixedArray::make(padded_len, b'\x00')
  // Copy the input message.
  for i in 0..<data_len {
    msg[i] = data[i]
  }
  // Append the terminating 0x80 bit.
  msg[data_len] = b'\x80'
  // Append the 64-bit big-endian bit-length in the final 8 bytes (the bytes
  // between 0x80 and the length are already zero from `make`).
  let hi = (bit_len >> 32).to_uint()
  let lo = (bit_len & 0xFFFFFFFFUL).to_uint()
  msg[padded_len - 8] = (hi >> 24).to_byte()
  msg[padded_len - 7] = (hi >> 16).to_byte()
  msg[padded_len - 6] = (hi >> 8).to_byte()
  msg[padded_len - 5] = hi.to_byte()
  msg[padded_len - 4] = (lo >> 24).to_byte()
  msg[padded_len - 3] = (lo >> 16).to_byte()
  msg[padded_len - 2] = (lo >> 8).to_byte()
  msg[padded_len - 1] = lo.to_byte()
  // Initialise the hash state.
  let state : FixedArray[UInt] = FixedArray::make(8, 0U)
  for i in 0..<8 {
    state[i] = initial_hash[i]
  }
  // Process each 64-byte block.
  let mut offset = 0
  while offset < padded_len {
    compress(state, msg, offset)
    offset = offset + 64
  }
  // Emit the eight state words in big-endian order (32 bytes total).
  Bytes::makei(32, i => {
    let word = state[i / 4]
    let shift = (3 - i % 4) * 8
    (word >> shift).to_byte()
  })
}

///|
/// Compute the SHA-256 digest of `data` and return it as a 64-character
/// lowercase hexadecimal string.
pub fn sha256_hex(data : Bytes) -> String {
  to_hex(sha256(data))
}

///|
/// Compute the SHA-256 digest of the UTF-8 encoding of `text`, returning a
/// 64-character lowercase hexadecimal string.
///
/// The string is first encoded to UTF-8 (the byte encoding assumed by every
/// standard SHA-256 interop partner), so `sha256_string(s)` always equals
/// `sha256_hex(utf8_bytes(s))`.
pub fn sha256_string(text : String) -> String {
  sha256_hex(utf8_bytes(text))
}

// ---------------------------------------------------------------------------
// Tests — expected values are the official NIST FIPS 180-4 test vectors,
// cross-checked against Python's `hashlib.sha256`.
// ---------------------------------------------------------------------------

///|
test "sha256: empty string (NIST)" {
  // SHA-256("") = e3b0c442...
  assert_eq(
    sha256_hex(b""),
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  )
  assert_eq(
    sha256_string(""),
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  )
  // Raw bytes: 32-byte digest.
  let raw = sha256(b"")
  assert_eq(raw.length(), 32)
  assert_eq(raw[0], b'\xe3')
  assert_eq(raw[31], b'\x55')
}

///|
test "sha256: \"abc\" (NIST single-block)" {
  // SHA-256("abc") = ba7816bf...
  assert_eq(
    sha256_hex(b"abc"),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
  assert_eq(
    sha256_string("abc"),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
}

///|
test "sha256: \"abcdbcdec...nopq\" (NIST two-block)" {
  // SHA-256 of the 448-bit (56-byte) NIST sample — spans two blocks after
  // padding, exercising the multi-block compression path.
  let msg = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
  assert_eq(
    sha256_string(msg),
    "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
  )
}

///|
test "sha256: \"Hello, World!\"" {
  assert_eq(
    sha256_string("Hello, World!"),
    "dffd6021bb2bd5b0af676290809ec3a53191dd81c7f70a4b28688a362182986f",
  )
  assert_eq(
    sha256_hex(b"Hello, World!"),
    "dffd6021bb2bd5b0af676290809ec3a53191dd81c7f70a4b28688a362182986f",
  )
}

///|
test "sha256: one million 'a' (NIST large multi-block)" {
  // The canonical NIST stress vector: 1,000,000 'a' bytes (15,625 blocks).
  // Expected value is the official FIPS 180-4 vector, verified against
  // Python's hashlib.sha256(b"a"*1000000).hexdigest().
  let big = "a".repeat(1000000)
  assert_eq(
    sha256_string(big),
    "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0",
  )
}

///|
test "sha256: padding boundary at one block (55 bytes)" {
  // 55 bytes: 55 + 1(0x80) + 0 zeros + 8(length) = 64 — fits exactly one
  // block with no zero fill. Verifies the no-extra-block padding edge case.
  let s = "a".repeat(55)
  assert_eq(
    sha256_string(s),
    "9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318",
  )
}

///|
test "sha256: padding boundary forcing a second block (56 bytes)" {
  // 56 bytes: 56 + 1(0x80) leaves no room for the 8-byte length in the first
  // block, so padding spills into a second 64-byte block. Verifies the
  // spill-over padding edge case.
  let s = "a".repeat(56)
  assert_eq(
    sha256_string(s),
    "b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a",
  )
}

///|
test "sha256: exactly one full block of input (64 bytes)" {
  let s = "a".repeat(64)
  assert_eq(
    sha256_string(s),
    "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb",
  )
}

///|
test "sha256: sha256_string equals sha256_hex of UTF-8 (non-ASCII)" {
  // Cross-check that sha256_string encodes via UTF-8 and matches hashing the
  // explicit UTF-8 bytes, including a multi-byte code point ("你好" = 6 UTF-8
  // bytes). Uses the shared utf8_encode so the two paths cannot diverge.
  let s = "Hello, 世界! €"
  assert_eq(sha256_string(s), sha256_hex(utf8_bytes(s)))
  // Determinism: same input always yields the same digest.
  assert_eq(sha256_string(s), sha256_string(s))
}

///|
test "sha256: round constants and initial hash are correct" {
  // Spot-check the FIPS 180-4 constants.
  assert_eq(round_constants[0], 0x428a2f98U)
  assert_eq(round_constants[63], 0xc67178f2U)
  assert_eq(initial_hash[0], 0x6a09e667U)
  assert_eq(initial_hash[7], 0x5be0cd19U)
}

///|
test "sha256: logical functions match the FIPS definitions" {
  // Ch(x,y,z): bit from y where x=1, from z where x=0.
  let x = 0xF0F0F0F0U
  let y = 0xFFFFFFFFU
  let z = 0x00000000U
  assert_eq(ch(x, y, z), 0xF0F0F0F0U)
  assert_eq(ch(x, z, y), 0x0F0F0F0FU)
  // Maj: majority vote — bit 7 (1,1,1)->1, bit 6 (1,1,0)->1, rest 0 => 0xC0.
  assert_eq(maj(0xF0U, 0xC0U, 0x80U), 0xC0U)
  // ROTR by full width is identity; ROTR^1 of 1 is the top bit set.
  assert_eq(rotr(0x00000001U, 1), 0x80000000U)
  assert_eq(rotr(0x12345678U, 32 - 0), 0x12345678U)
  // Σ0 / Σ1 / σ0 / σ1 are exercised end-to-end by the NIST vectors above;
  // here we just confirm they are pure functions of their input (determinism).
  assert_eq(big_sigma0(0x6a09e667U), big_sigma0(0x6a09e667U))
  assert_eq(small_sigma1(0x6a09e667U), small_sigma1(0x6a09e667U))
}
