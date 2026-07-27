/// SHA-3 (Keccak) hash functions and SHAKE XOFs — FIPS 202.
///
/// This module implements the SHA-3 family of cryptographic hash functions
/// and extendable-output functions (XOFs) as specified in FIPS 202:
///
/// - **SHA3-224**: 224-bit hash, rate 144 bytes
/// - **SHA3-256**: 256-bit hash, rate 136 bytes
/// - **SHA3-384**: 384-bit hash, rate 104 bytes
/// - **SHA3-512**: 512-bit hash, rate 72 bytes
/// - **SHAKE128**: XOF, rate 168 bytes
/// - **SHAKE256**: XOF, rate 136 bytes
///
/// Not formally verified. Correctness is ensured by NIST test vectors.
///
/// `proof-enabled` is `false`.

// ---------------------------------------------------------------------------
// Keccak-f[1600] constants
// ---------------------------------------------------------------------------

///|
/// 24 round constants for Keccak-f[1600] (FIPS 202 §4.1.2).
let keccak_rc : FixedArray[UInt64] = FixedArray::from_array([
  0x0000000000000001UL, 0x0000000000008082UL, 0x800000000000808AUL, 0x8000000080008000UL,
  0x000000000000808BUL, 0x0000000080000001UL, 0x8000000080008081UL, 0x8000000000008009UL,
  0x000000000000008AUL, 0x0000000000000088UL, 0x0000000080008009UL, 0x000000008000000AUL,
  0x000000008000808BUL, 0x800000000000008BUL, 0x8000000000008089UL, 0x8000000000008003UL,
  0x8000000000008002UL, 0x8000000000000080UL, 0x000000000000800AUL, 0x800000008000000AUL,
  0x8000000080008081UL, 0x8000000000008080UL, 0x0000000080000001UL, 0x8000000080008008UL,
])

///|
/// Rotation offsets r[x][y], stored as a 5×5 table.
/// Indexed as rot[x][y] where x is the column and y is the row.
let rot_table : FixedArray[FixedArray[Int]] = FixedArray::from_array([
  FixedArray::from_array([0, 36, 3, 41, 18]),
  FixedArray::from_array([1, 44, 10, 45, 2]),
  FixedArray::from_array([62, 6, 43, 15, 61]),
  FixedArray::from_array([28, 55, 25, 21, 56]),
  FixedArray::from_array([27, 20, 39, 8, 14]),
])

// ---------------------------------------------------------------------------
// Keccak-f[1600] permutation
// ---------------------------------------------------------------------------

///|
/// Left-rotate a 64-bit value by `n` bits.
fn rotl64(x : UInt64, n : Int) -> UInt64 {
  if n == 0 {
    x
  } else {
    (x << n) | (x >> (64 - n))
  }
}

///|
/// Keccak-f[1600] permutation: 24 rounds of θ, ρ, π, χ, ι.
/// State is a 5×5 matrix of UInt64 lanes where A[x][y] = flat[x + 5*y].
/// Lane i (from byte buffer) maps to flat[i], i.e. x=i%5, y=i/5.
fn keccak_f(flat : FixedArray[UInt64]) -> Unit {
  let b : FixedArray[UInt64] = FixedArray::make(25, 0UL)
  let c : FixedArray[UInt64] = FixedArray::make(5, 0UL)
  let d : FixedArray[UInt64] = FixedArray::make(5, 0UL)
  for round = 0; round < 24; round = round + 1 {
    // θ step: C[x] = A[x,0]^A[x,1]^A[x,2]^A[x,3]^A[x,4]
    for x = 0; x < 5; x = x + 1 {
      c[x] = flat[x] ^ flat[x + 5] ^ flat[x + 10] ^ flat[x + 15] ^ flat[x + 20]
    }
    // D[x] = C[x-1] ^ rot(C[x+1], 1)
    for x = 0; x < 5; x = x + 1 {
      d[x] = c[(x + 4) % 5] ^ rotl64(c[(x + 1) % 5], 1)
    }
    // A[x,y] ^= D[x]
    for x = 0; x < 5; x = x + 1 {
      for y = 0; y < 5; y = y + 1 {
        flat[x + 5 * y] = flat[x + 5 * y] ^ d[x]
      }
    }
    // ρ and π steps: B[y, (2x+3y)%5] = rot(A[x,y], r[x,y])
    for x = 0; x < 5; x = x + 1 {
      for y = 0; y < 5; y = y + 1 {
        b[y + 5 * ((2 * x + 3 * y) % 5)] = rotl64(
          flat[x + 5 * y],
          rot_table[x][y],
        )
      }
    }
    // χ step: A[x,y] = B[x,y] ^ ((~B[x+1,y]) & B[x+2,y])
    // Use XOR with all-ones instead of lnot() for bitwise NOT.
    for x = 0; x < 5; x = x + 1 {
      for y = 0; y < 5; y = y + 1 {
        let not_next = b[(x + 1) % 5 + 5 * y] ^ 0xFFFFFFFFFFFFFFFFUL
        flat[x + 5 * y] = b[x + 5 * y] ^ (not_next & b[(x + 2) % 5 + 5 * y])
      }
    }
    // ι step: A[0,0] ^= RC[round]
    flat[0] = flat[0] ^ keccak_rc[round]
  }
}

// ---------------------------------------------------------------------------
// Sponge construction
// ---------------------------------------------------------------------------

///|
/// Keccak sponge state.
pub struct KeccakSponge {
  priv state : FixedArray[UInt64]
  priv rate : Int
  priv buf : Array[Byte]
  priv mut buf_len : Int
  priv domain : Byte
}

///|
/// Create a Keccak sponge with the given rate (in bytes) and domain byte.
fn new_sponge(rate : Int, domain : Byte) -> KeccakSponge {
  {
    state: FixedArray::make(25, 0UL),
    rate,
    buf: Array::make(rate, b'\x00'),
    buf_len: 0,
    domain,
  }
}

///|
/// Absorb data into the sponge.
fn absorb(sponge : KeccakSponge, data : Bytes) -> Unit {
  let mut offset = 0
  while offset < data.length() {
    let to_copy = if sponge.rate - sponge.buf_len < data.length() - offset {
      sponge.rate - sponge.buf_len
    } else {
      data.length() - offset
    }
    for i = 0; i < to_copy; i = i + 1 {
      sponge.buf[sponge.buf_len + i] = data[offset + i]
    }
    sponge.buf_len = sponge.buf_len + to_copy
    offset = offset + to_copy
    if sponge.buf_len == sponge.rate {
      absorb_block(sponge)
      sponge.buf_len = 0
    }
  }
}

///|
/// Load 8 bytes from buf at offset in little-endian order as a UInt64 lane.
fn load_lane_le(buf : Array[Byte], offset : Int) -> UInt64 {
  let b0 = buf[offset].to_uint64()
  let b1 = buf[offset + 1].to_uint64()
  let b2 = buf[offset + 2].to_uint64()
  let b3 = buf[offset + 3].to_uint64()
  let b4 = buf[offset + 4].to_uint64()
  let b5 = buf[offset + 5].to_uint64()
  let b6 = buf[offset + 6].to_uint64()
  let b7 = buf[offset + 7].to_uint64()
  b0 |
  (b1 << 8) |
  (b2 << 16) |
  (b3 << 24) |
  (b4 << 32) |
  (b5 << 40) |
  (b6 << 48) |
  (b7 << 56)
}

///|
/// Absorb a full block into the state and apply Keccak-f.
fn absorb_block(sponge : KeccakSponge) -> Unit {
  // XOR the block into the state (little-endian lane loading).
  // State uses A[x][y] = flat[x*5+y], but lanes are loaded sequentially
  // from the byte buffer. Lane i maps to flat[i] (i.e., x=i/5, y=i%5).
  for i = 0; i < sponge.rate / 8; i = i + 1 {
    let lane = load_lane_le(sponge.buf, i * 8)
    sponge.state[i] = sponge.state[i] ^ lane
  }
  keccak_f(sponge.state)
}

///|
/// Apply padding and finalize absorption.
fn pad_and_finalize(sponge : KeccakSponge) -> Unit {
  // Domain separation byte at position buf_len.
  sponge.buf[sponge.buf_len] = sponge.domain
  // Zero-fill between domain and last byte.
  for i = sponge.buf_len + 1; i < sponge.rate; i = i + 1 {
    sponge.buf[i] = b'\x00'
  }
  // Set the last byte's MSB (pad10*1 padding).
  sponge.buf[sponge.rate - 1] = sponge.buf[sponge.rate - 1] | b'\x80'
  absorb_block(sponge)
}

///|
/// Squeeze `n` bytes from the sponge.
fn squeeze(sponge : KeccakSponge, n : Int) -> Bytes {
  let output : Array[Byte] = Array::make(n, b'\x00')
  let mut offset = 0
  while offset < n {
    let block_len = if sponge.rate < n - offset {
      sponge.rate
    } else {
      n - offset
    }
    for i = 0; i < block_len; i = i + 1 {
      let lane = sponge.state[i / 8]
      let byte_val = (lane >> (i % 8 * 8)) & 0xFFUL
      output[offset + i] = byte_val.to_byte()
    }
    offset = offset + block_len
    if offset < n {
      keccak_f(sponge.state)
    }
  }
  Bytes::from_array(output)
}

// ---------------------------------------------------------------------------
// Public API: SHA-3 hash functions
// ---------------------------------------------------------------------------

///|
/// Compute SHA3-224 of the input data, returning a 28-byte hash.
pub fn sha3_224(data : Bytes) -> Bytes {
  let sponge = new_sponge(144, b'\x06')
  absorb(sponge, data)
  pad_and_finalize(sponge)
  squeeze(sponge, 28)
}

///|
/// Compute SHA3-256 of the input data, returning a 32-byte hash.
pub fn sha3_256(data : Bytes) -> Bytes {
  let sponge = new_sponge(136, b'\x06')
  absorb(sponge, data)
  pad_and_finalize(sponge)
  squeeze(sponge, 32)
}

///|
/// Compute SHA3-384 of the input data, returning a 48-byte hash.
pub fn sha3_384(data : Bytes) -> Bytes {
  let sponge = new_sponge(104, b'\x06')
  absorb(sponge, data)
  pad_and_finalize(sponge)
  squeeze(sponge, 48)
}

///|
/// Compute SHA3-512 of the input data, returning a 64-byte hash.
pub fn sha3_512(data : Bytes) -> Bytes {
  let sponge = new_sponge(72, b'\x06')
  absorb(sponge, data)
  pad_and_finalize(sponge)
  squeeze(sponge, 64)
}

// ---------------------------------------------------------------------------
// Public API: SHAKE XOFs
// ---------------------------------------------------------------------------

///|
/// Compute SHAKE128 of the input data with the given output length.
pub fn shake128(data : Bytes, output_len : Int) -> Bytes {
  if output_len <= 0 {
    return Bytes::from_array([])
  }
  let sponge = new_sponge(168, b'\x1f')
  absorb(sponge, data)
  pad_and_finalize(sponge)
  squeeze(sponge, output_len)
}

///|
/// Compute SHAKE256 of the input data with the given output length.
pub fn shake256(data : Bytes, output_len : Int) -> Bytes {
  if output_len <= 0 {
    return Bytes::from_array([])
  }
  let sponge = new_sponge(136, b'\x1f')
  absorb(sponge, data)
  pad_and_finalize(sponge)
  squeeze(sponge, output_len)
}

// ---------------------------------------------------------------------------
// Tests (NIST test vectors from FIPS 202)
// ---------------------------------------------------------------------------

///|
/// Convert a hex string to a byte array.
fn hex_to_bytes(hex : String) -> Bytes {
  let arr : Array[Byte] = []
  let mut i = 0
  while i < hex.length() {
    let h = hex[i].to_int()
    let l = hex[i + 1].to_int()
    arr.push((hex_val(h) * 16 + hex_val(l)).to_byte())
    i = i + 2
  }
  Bytes::from_array(arr)
}

///|
fn hex_val(c : Int) -> Int {
  if c >= 48 && c <= 57 {
    c - 48 // '0'..'9'
  } else if c >= 97 && c <= 102 {
    c - 87 // 'a'..'f'
  } else if c >= 65 && c <= 70 {
    c - 55 // 'A'..'F'
  } else {
    0
  }
}

///|
/// Convert an ASCII string to bytes (for test inputs).
fn ascii_to_bytes(s : String) -> Bytes {
  let arr : Array[Byte] = []
  for c in s {
    arr.push(c.to_int().to_byte())
  }
  Bytes::from_array(arr)
}

///|
fn bytes_eq(a : Bytes, b : Bytes) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i = 0; i < a.length(); i = i + 1 {
    if a[i] != b[i] {
      return false
    }
  }
  true
}

///|
test "sha3-256: empty string NIST vector" {
  let result = sha3_256(Bytes::from_array([]))
  let expected = hex_to_bytes(
    "a7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a",
  )
  assert_true(bytes_eq(result, expected))
}

///|
test "sha3-256: 'abc' NIST vector" {
  let result = sha3_256(ascii_to_bytes("abc"))
  let expected = hex_to_bytes(
    "3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
  )
  assert_true(bytes_eq(result, expected))
}

///|
test "sha3-512: empty string NIST vector" {
  let result = sha3_512(Bytes::from_array([]))
  let expected = hex_to_bytes(
    "a69f73cca23a9ac5c8b567dc185a756e97c982164fe25859e0d1dcc1475c80a615b2123af1f5f94c11e3e9402c3ac558f500199d95b6d3e301758586281dcd26",
  )
  assert_true(bytes_eq(result, expected))
}

///|
test "sha3-512: 'abc' NIST vector" {
  let result = sha3_512(ascii_to_bytes("abc"))
  let expected = hex_to_bytes(
    "b751850b1a57168a5693cd924b6b096e08f621827444f70d884f5d0240d2712e10e116e9192af3c91a7ec57647e3934057340b4cf408d5a56592f8274eec53f0",
  )
  assert_true(bytes_eq(result, expected))
}

///|
test "sha3-224: empty string NIST vector" {
  let result = sha3_224(Bytes::from_array([]))
  let expected = hex_to_bytes(
    "6b4e03423667dbb73b6e15454f0eb1abd4597f9a1b078e3f5b5a6bc7",
  )
  assert_true(bytes_eq(result, expected))
}

///|
test "sha3-224: 'abc' NIST vector" {
  let result = sha3_224(ascii_to_bytes("abc"))
  let expected = hex_to_bytes(
    "e642824c3f8cf24ad09234ee7d3c766fc9a3a5168d0c94ad73b46fdf",
  )
  assert_true(bytes_eq(result, expected))
}

///|
test "sha3-384: empty string NIST vector" {
  let result = sha3_384(Bytes::from_array([]))
  let expected = hex_to_bytes(
    "0c63a75b845e4f7d01107d852e4c2485c51a50aaaa94fc61995e71bbee983a2ac3713831264adb47fb6bd1e058d5f004",
  )
  assert_true(bytes_eq(result, expected))
}

///|
test "sha3-384: 'abc' NIST vector" {
  let result = sha3_384(ascii_to_bytes("abc"))
  let expected = hex_to_bytes(
    "ec01498288516fc926459f58e2c6ad8df9b473cb0fc08c2596da7cf0e49be4b298d88cea927ac7f539f1edf228376d25",
  )
  assert_true(bytes_eq(result, expected))
}

///|
test "shake128: empty string, 16 bytes NIST vector" {
  let result = shake128(Bytes::from_array([]), 16)
  let expected = hex_to_bytes("7f9c2ba4e88f827d616045507605853e")
  assert_true(bytes_eq(result, expected))
}

///|
test "shake256: empty string, 16 bytes NIST vector" {
  let result = shake256(Bytes::from_array([]), 16)
  let expected = hex_to_bytes("46b9dd2b0ba88d13233b3feb743eeb24")
  assert_true(bytes_eq(result, expected))
}

///|
test "sha3-256: long message (200 bytes)" {
  let msg = Bytes::makei(200, fn(i) { i.to_byte() })
  let result = sha3_256(msg)
  assert_true(result.length() == 32)
  let result2 = sha3_256(msg)
  assert_true(bytes_eq(result, result2))
}
