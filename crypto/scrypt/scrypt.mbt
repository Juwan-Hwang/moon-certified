/// scrypt — Memory-Hard Password-Based Key Derivation Function (RFC 7914).
///
/// scrypt is a password-based key derivation function designed to be
/// computationally expensive in both time and memory, making brute-force
/// attacks using ASICs or GPUs prohibitively expensive. It was designed
/// by Colin Percival for the Tarsnap backup service and is specified in
/// RFC 7914.
///
/// ## Algorithm
///
/// ```text
/// 1. B = PBKDF2-HMAC-SHA-256(password, salt, 1, p * 128 * r)
/// 2. For i = 0..p-1: B'[i] = scryptROMix(r, B[i], N)
/// 3. DK = PBKDF2-HMAC-SHA-256(password, B', 1, dkLen)
/// ```
///
/// ### scryptROMix(r, B, N)
/// ```text
/// 1. X = B
/// 2. V[0] = X
/// 3. For i = 1..N-1: V[i] = BlockMix(r, V[i-1])
/// 4. X = BlockMix(r, V[N-1])
/// 5. For i = 0..N-1:
///      j = Integerify(X) mod N
///      X = BlockMix(r, X XOR V[j])
/// 6. Return X
/// ```
///
/// ### BlockMix(r, B)
/// ```text
/// 1. X = B[2r-1]
/// 2. For i = 0..2r-1:
///      X = X XOR B[i]
///      X = Salsa20/8(X)
///      Y[i] = X
/// 3. Return (Y[0], Y[2], ..., Y[2r-2], Y[1], Y[3], ..., Y[2r-1])
/// ```
///
/// ## Parameters
///
/// - **N**: CPU/memory cost parameter. Must be a power of 2 ≥ 2. Larger
///   values increase both time and memory linearly. Typical production
///   values: N=2^14 (16 MB) to N=2^20 (1 GB).
///
/// - **r**: Block size parameter. Each block is 128·r bytes. Typical: r=8.
///
/// - **p**: Parallelism parameter. Controls how many independent ROMix
///   chains run. Typical: p=1.
///
/// Memory usage ≈ 128 · r · N bytes.
///
/// ## Security
///
/// scrypt's memory-hardness makes it resistant to parallel brute-force
/// attacks on hardware with limited fast memory (GPUs, ASICs). The
/// parameters should be tuned so that a single derivation takes ~250ms
/// on production hardware.
///
/// ## References
///
/// - C. Percival, S. Josefsson. "The scrypt Password-Based Key
///   Derivation Function." RFC 7914, 2016.
/// - C. Percival. "Stronger Key Derivation via Sequential Memory-Hard
///   Functions." BSDCan 2009.
///
/// `proof-enabled` is `false`; correctness is backed by RFC 7914 test
/// vectors.

// ---------------------------------------------------------------------------
// Salsa20/8 Core
// ---------------------------------------------------------------------------

///|
/// Salsa20/8 core: 8 rounds of the Salsa20 word-permutation function.
///
/// Operates in-place on a 16-word (512-bit / 64-byte) block. This is the
/// core mixing function used by scrypt's BlockMix. It is **not** the full
/// Salsa20 stream cipher — scrypt only needs the core permutation, not
/// the cipher's key schedule or counter.
///
/// The function applies 8 rounds (4 double-rounds) of quarter-round
/// operations to the 16 words, following the Salsa20 specification
/// (Bernstein, 2005).
fn salsa20_8_core(x : FixedArray[Int]) -> Unit {
  // Save the original state — Salsa20/8 core adds the input back to the
  // permuted output (B[i] += permutation[i]), per the Salsa20 specification
  // and RFC 7914 §3. Without this final addition, the scrypt BlockMix
  // produces incorrect results.
  let orig : FixedArray[Int] = FixedArray::make(16, 0)
  for i = 0; i < 16; i = i + 1 {
    orig[i] = x[i]
  }
  // Helper: 32-bit left rotation using UInt to ensure logical (zero-fill)
  // right shift. Using signed Int would cause arithmetic (sign-extending)
  // right shift, producing incorrect rotation for values with bit 31 set.
  fn rotl(v : Int, n : Int) -> Int {
    let vu = v.reinterpret_as_uint()
    ((vu << n) | (vu >> (32 - n))).reinterpret_as_int()
  }
  // Helper: quarter round on (a, b, c, d).
  fn quarter_round(a : Int, b : Int, c : Int, d : Int) -> Unit {
    x[b] = (x[b] ^ rotl((x[a] + x[d]) & 0xFFFFFFFF, 7)) & 0xFFFFFFFF
    x[c] = (x[c] ^ rotl((x[b] + x[a]) & 0xFFFFFFFF, 9)) & 0xFFFFFFFF
    x[d] = (x[d] ^ rotl((x[c] + x[b]) & 0xFFFFFFFF, 13)) & 0xFFFFFFFF
    x[a] = (x[a] ^ rotl((x[d] + x[c]) & 0xFFFFFFFF, 18)) & 0xFFFFFFFF
  }
  // 4 double-rounds = 8 rounds total.
  for _ in 0..<4 {
    // Column rounds.
    quarter_round(0, 4, 8, 12)
    quarter_round(5, 9, 13, 1)
    quarter_round(10, 14, 2, 6)
    quarter_round(15, 3, 7, 11)
    // Row rounds.
    quarter_round(0, 1, 2, 3)
    quarter_round(5, 6, 7, 4)
    quarter_round(10, 11, 8, 9)
    quarter_round(15, 12, 13, 14)
  }
  // Final addition: x[i] = (permutation[i] + original[i]) mod 2^32.
  for i = 0; i < 16; i = i + 1 {
    x[i] = (x[i] + orig[i]) & 0xFFFFFFFF
  }
}

// ---------------------------------------------------------------------------
// BlockMix
// ---------------------------------------------------------------------------

///|
/// scrypt BlockMix: mixes 2r 64-byte blocks using Salsa20/8.
///
/// Given `B` containing `2r` blocks of 64 bytes each (total 128·r bytes),
/// produces a new array of the same size by:
/// 1. X = B[2r-1]
/// 2. For i = 0..2r-1: X = Salsa20/8(X XOR B[i]); Y[i] = X
/// 3. Return interleaved: (Y[0], Y[2], ..., Y[2r-2], Y[1], Y[3], ..., Y[2r-1])
///
/// All byte-to-word conversions are little-endian, per RFC 7914.
fn block_mix(
  r : Int,
  b : FixedArray[Int], // 32*r words (2r blocks of 16 words)
) -> FixedArray[Int] {
  let block_count = 2 * r
  let words_per_block = 16
  let total_words = block_count * words_per_block // 32*r
  // X starts as B[2r-1] (the last block).
  let x : FixedArray[Int] = FixedArray::make(16, 0)
  let last_block_start = (block_count - 1) * words_per_block
  for i = 0; i < 16; i = i + 1 {
    x[i] = b[last_block_start + i]
  }
  // Y: temporary storage for 2r blocks.
  let y : FixedArray[Int] = FixedArray::make(total_words, 0)
  for i = 0; i < block_count; i = i + 1 {
    let block_start = i * words_per_block
    // X = X XOR B[i]
    for j = 0; j < 16; j = j + 1 {
      x[j] = x[j] ^ b[block_start + j]
    }
    // X = Salsa20/8(X)
    salsa20_8_core(x)
    // Y[i] = X
    for j = 0; j < 16; j = j + 1 {
      y[i * words_per_block + j] = x[j]
    }
  }
  // Interleave: even blocks first, then odd blocks.
  let result : FixedArray[Int] = FixedArray::make(total_words, 0)
  for i = 0; i < r; i = i + 1 {
    let even_src = 2 * i * words_per_block
    let odd_src = (2 * i + 1) * words_per_block
    let even_dst = i * words_per_block
    let odd_dst = (r + i) * words_per_block
    for j = 0; j < words_per_block; j = j + 1 {
      result[even_dst + j] = y[even_src + j]
      result[odd_dst + j] = y[odd_src + j]
    }
  }
  result
}

// ---------------------------------------------------------------------------
// Integerify
// ---------------------------------------------------------------------------

///|
/// Integerify: extract a 64-bit integer from the first word of the last
/// 64-byte block of `B`.
///
/// Used by ROMix to index into the V array. Per RFC 7914, this reads the
/// first 64-bit little-endian integer from block `B[2r-1]`.
fn integerify(
  r : Int,
  b : FixedArray[Int], // 32*r words
) -> Int64 {
  // The last block starts at word offset (2r-1)*16 = 32r - 16.
  let offset = 32 * r - 16
  // Read first two words as a 64-bit little-endian integer.
  let lo = b[offset].to_int64() & 0xFFFFFFFFL
  let hi = b[offset + 1].to_int64() & 0xFFFFFFFFL
  lo | (hi << 32)
}

// ---------------------------------------------------------------------------
// ROMix
// ---------------------------------------------------------------------------

///|
/// scrypt ROMix: the memory-hard mixing function.
///
/// Performs N iterations of BlockMix, storing all intermediate results
/// in a V array of size N × 128·r bytes. Then performs another N
/// iterations, each time XORing the current block with a pseudo-randomly
/// selected V entry before mixing.
///
/// This is what makes scrypt memory-hard: an attacker cannot compute the
/// function without storing (or recomputing at high cost) the entire V
/// array of N × 128·r bytes.
fn ro_mix(
  r : Int,
  n : Int,
  b : FixedArray[Int], // 32*r words
) -> FixedArray[Int] {
  let words_per_block = 32 * r
  // V: array of N blocks, each 32*r words.
  let v : FixedArray[FixedArray[Int]] = FixedArray::make(
    n,
    FixedArray::make(0, 0),
  )
  let x = FixedArray::make(words_per_block, 0)
  for i = 0; i < words_per_block; i = i + 1 {
    x[i] = b[i]
  }
  // Phase 1 (RFC 7914 §4):
  //   for i = 0 to N-1 do
  //     V_i = X
  //     X = scryptBlockMix(r, X)
  //   end for
  // After this loop, X = BlockMix^N(B) and V_i = BlockMix^i(B).
  for i = 0; i < n; i = i + 1 {
    // V_i = X
    v[i] = FixedArray::make(words_per_block, 0)
    for j = 0; j < words_per_block; j = j + 1 {
      v[i][j] = x[j]
    }
    // X = BlockMix(X)
    let mixed = block_mix(r, x)
    for j = 0; j < words_per_block; j = j + 1 {
      x[j] = mixed[j]
    }
  }
  // Phase 2 (RFC 7914 §4):
  //   for i = 0 to N-1 do
  //     j = Integerify(X) mod N
  //     T = X XOR V_j
  //     X = scryptBlockMix(r, T)
  //   end for
  for _ in 0..<n {
    let j = (integerify(r, x) & (n.to_int64() - 1L)).to_int()
    // T = X XOR V[j]
    for i = 0; i < words_per_block; i = i + 1 {
      x[i] = x[i] ^ v[j][i]
    }
    // X = BlockMix(T)
    let mixed = block_mix(r, x)
    for i = 0; i < words_per_block; i = i + 1 {
      x[i] = mixed[i]
    }
  }
  x
}

// ---------------------------------------------------------------------------
// Byte ↔ Word conversion helpers
// ---------------------------------------------------------------------------

///|
/// Convert a byte array to a 32-bit little-endian word array.
fn bytes_to_words(data : Bytes) -> FixedArray[Int] {
  let n = data.length()
  let word_count = (n + 3) / 4
  let words = FixedArray::make(word_count, 0)
  for i = 0; i < word_count; i = i + 1 {
    let b0 = if i * 4 < n { data[i * 4].to_int() } else { 0 }
    let b1 = if i * 4 + 1 < n { data[i * 4 + 1].to_int() } else { 0 }
    let b2 = if i * 4 + 2 < n { data[i * 4 + 2].to_int() } else { 0 }
    let b3 = if i * 4 + 3 < n { data[i * 4 + 3].to_int() } else { 0 }
    words[i] = (b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)) & 0xFFFFFFFF
  }
  words
}

///|
/// Convert a 32-bit little-endian word array to bytes.
fn words_to_bytes(words : FixedArray[Int]) -> Bytes {
  let n = words.length()
  let result : FixedArray[Byte] = FixedArray::make(n * 4, b'\x00')
  for i = 0; i < n; i = i + 1 {
    let w = words[i]
    result[i * 4] = (w & 0xFF).to_byte()
    result[i * 4 + 1] = ((w >> 8) & 0xFF).to_byte()
    result[i * 4 + 2] = ((w >> 16) & 0xFF).to_byte()
    result[i * 4 + 3] = ((w >> 24) & 0xFF).to_byte()
  }
  Bytes::from_array(result)
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

///|
/// scrypt password-based key derivation function.
///
/// - `password`: the password bytes.
/// - `salt`: the salt bytes (should be at least 16 bytes / 128 bits).
/// - `n`: CPU/memory cost parameter (must be a power of 2, ≥ 2).
/// - `r`: block size parameter (must be ≥ 1).
/// - `p`: parallelism parameter (must be ≥ 1).
/// - `dklen`: desired output length in bytes (must be ≥ 1).
///
/// Returns `None` if any parameter is invalid.
///
/// ## Recommended production parameters
///
/// | Use case           | N     | r  | p  | Memory   |
/// |--------------------|-------|----|----|----------|
/// | Interactive login  | 16384 | 8  | 1  | 16 MB    |
/// | File encryption    | 65536 | 8  | 1  | 64 MB    |
/// | Sensitive data     | 131072| 8  | 2  | 256 MB   |
///
/// Memory usage ≈ 128 × r × N × p bytes.
pub fn scrypt(
  password : Bytes,
  salt : Bytes,
  n : Int,
  r : Int,
  p : Int,
  dklen : Int,
) -> Bytes? {
  // Parameter validation.
  if r < 1 || p < 1 || dklen < 1 {
    return None
  }
  if n < 2 || (n & (n - 1)) != 0 {
    return None // N must be a power of 2 ≥ 2.
  }
  // Check for integer overflow: 128 * r * p must not overflow Int32.
  let block_size = 128 * r
  let total_initial = block_size * p
  if total_initial < 0 || total_initial > 0x7FFFFFFF {
    return None
  }
  // Check memory: 128 * r * N must not overflow.
  let v_memory = block_size * n
  if v_memory < 0 || v_memory > 0x7FFFFFFF {
    return None
  }
  // Step 1: B = PBKDF2-HMAC-SHA-256(password, salt, 1, p * 128 * r)
  let b_bytes = match @pbkdf2.pbkdf2_sha256(password, salt, 1, total_initial) {
    None => return None
    Some(b) => b
  }
  // Step 2: For each parallel block, run ROMix.
  let words_per_block = 32 * r // 128*r bytes = 32*r 32-bit words
  let b_words = bytes_to_words(b_bytes)
  let b_result : FixedArray[Int] = FixedArray::make(p * words_per_block, 0)
  for i = 0; i < p; i = i + 1 {
    // Extract block i.
    let block : FixedArray[Int] = FixedArray::make(words_per_block, 0)
    for j = 0; j < words_per_block; j = j + 1 {
      block[j] = b_words[i * words_per_block + j]
    }
    // Run ROMix.
    let mixed = ro_mix(r, n, block)
    // Store result.
    for j = 0; j < words_per_block; j = j + 1 {
      b_result[i * words_per_block + j] = mixed[j]
    }
  }
  let b_mixed_bytes = words_to_bytes(b_result)
  // Step 3: DK = PBKDF2-HMAC-SHA-256(password, B_mixed, 1, dklen)
  @pbkdf2.pbkdf2_sha256(password, b_mixed_bytes, 1, dklen)
}

///|
/// scrypt with production-grade parameter validation.
///
/// Enforces:
/// - `n ≥ 2` and power of 2
/// - `r ≥ 1`
/// - `p ≥ 1`
/// - `dklen ≥ 16`
/// - `salt.length() ≥ 16` (128 bits per NIST SP 800-132)
/// - `password.length() ≥ 1`
/// - Total memory ≤ 1 GB (prevents accidental OOM)
///
/// Returns `None` if any parameter fails validation.
///
/// Upper bounds prevent accidental OOM/DoS:
/// - `n ≤ 2^22` (4M, ~4 GB max memory with r=8)
/// - `r ≤ 64`
/// - `p ≤ 64`
/// - `dklen ≤ 1024`
/// - Total memory ≤ 1 GB
pub fn scrypt_checked(
  password : Bytes,
  salt : Bytes,
  n : Int,
  r : Int,
  p : Int,
  dklen : Int,
) -> Bytes? {
  if password.length() < 1 {
    return None
  }
  if salt.length() < 16 {
    return None
  }
  if dklen < 16 || dklen > 1024 {
    return None
  }
  // Individual parameter upper bounds.
  if n > 4194304 || r > 64 || p > 64 {
    return None
  }
  // Memory limit: 128 * r * N ≤ 1 GB (1073741824 bytes)
  // Use Int64 to avoid overflow when r*n is large.
  let mem_estimate = 128L * r.to_int64() * n.to_int64()
  if mem_estimate > 1073741824L {
    return None
  }
  scrypt(password, salt, n, r, p, dklen)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
fn bytes_to_hex(data : Bytes) -> String {
  @hex.encode(data)
}

///|
test "scrypt: RFC 7914 test vector 1" {
  // scrypt(P="", S="", N=16, r=1, p=1, dklen=64)
  let password = Bytes::from_array([])
  let salt = Bytes::from_array([])
  let result = scrypt(password, salt, 16, 1, 1, 64)
  assert_true(result is Some(_))
  let dk = result.unwrap()
  assert_eq(dk.length(), 64)
  // Full 64-byte verification against RFC 7914 §12 test vector 1
  let expected = "77d6576238657b203b19ca42c18a0497f16b4844e3074ae8dfdffa3fede21442fcd0069ded0948f8326a753a0fc81f17e8d3e0fb2e0d3628cf35e20c38d18906"
  assert_eq(bytes_to_hex(dk), expected)
}

///|
test "scrypt: RFC 7914 test vector 2" {
  // scrypt(P="password", S="NaCl", N=1024, r=8, p=16, dklen=64)
  let password = Bytes::from_array([
    b'\x70', b'\x61', b'\x73', b'\x73', b'\x77', b'\x6f', b'\x72', b'\x64',
  ])
  let salt = Bytes::from_array([b'\x4e', b'\x61', b'\x43', b'\x6c'])
  let result = scrypt(password, salt, 1024, 8, 16, 64)
  assert_true(result is Some(_))
  let dk = result.unwrap()
  assert_eq(dk.length(), 64)
  // Full 64-byte verification against RFC 7914 §12 test vector 2
  let expected = "fdbabe1c9d3472007856e7190d01e9fe7c6ad7cbc8237830e77376634b3731622eaf30d92e22a3886ff109279d9830dac727afb94a83ee6d8360cbdfa2cc0640"
  assert_eq(bytes_to_hex(dk), expected)
}

///|
test "scrypt: determinism — same inputs produce same output" {
  let pw = Bytes::from_array([b'\x74', b'\x65', b'\x73', b'\x74'])
  let salt = Bytes::from_array(Array::make(16, b'\x42'))
  let r1 = scrypt(pw, salt, 16, 2, 1, 32)
  let r2 = scrypt(pw, salt, 16, 2, 1, 32)
  assert_true(r1 is Some(_))
  assert_true(r2 is Some(_))
  let d1 = r1.unwrap()
  let d2 = r2.unwrap()
  for i = 0; i < 32; i = i + 1 {
    assert_eq(d1[i], d2[i])
  }
}

///|
test "scrypt: different passwords produce different keys" {
  let salt = Bytes::from_array(Array::make(16, b'\x42'))
  let pw1 = Bytes::from_array([b'\x70', b'\x77', b'\x31'])
  let pw2 = Bytes::from_array([b'\x70', b'\x77', b'\x32'])
  let r1 = scrypt(pw1, salt, 16, 2, 1, 32).unwrap()
  let r2 = scrypt(pw2, salt, 16, 2, 1, 32).unwrap()
  let mut different = false
  for i = 0; i < 32; i = i + 1 {
    if r1[i] != r2[i] {
      different = true
    }
  }
  assert_true(different)
}

///|
test "scrypt: invalid parameters return None" {
  let pw = Bytes::from_array([b'\x70'])
  let salt = Bytes::from_array(Array::make(16, b'\x42'))
  // N < 2
  assert_true(scrypt(pw, salt, 1, 1, 1, 32) is None)
  // N not power of 2
  assert_true(scrypt(pw, salt, 3, 1, 1, 32) is None)
  // r < 1
  assert_true(scrypt(pw, salt, 16, 0, 1, 32) is None)
  // p < 1
  assert_true(scrypt(pw, salt, 16, 1, 0, 32) is None)
  // dklen < 1
  assert_true(scrypt(pw, salt, 16, 1, 1, 0) is None)
}

///|
test "scrypt: checked function rejects weak parameters" {
  let pw = Bytes::from_array([b'\x70'])
  // Short salt
  assert_true(
    scrypt_checked(pw, Bytes::from_array(Array::make(8, b'\x42')), 16, 1, 1, 32)
    is None,
  )
  // Short output
  assert_true(
    scrypt_checked(pw, Bytes::from_array(Array::make(16, b'\x42')), 16, 1, 1, 8)
    is None,
  )
  // Empty password
  assert_true(
    scrypt_checked(
      Bytes::from_array([]),
      Bytes::from_array(Array::make(16, b'\x42')),
      16,
      1,
      1,
      32,
    )
    is None,
  )
}

///|
test "scrypt: salsa20/8 core is deterministic" {
  // Verify Salsa20/8 core produces deterministic output.
  let x1 : FixedArray[Int] = FixedArray::from_array([
    0x76657469, 0x6d612e67, 0x6e696e65, 0x6c656172, 0x44206f66, 0x2070656f, 0x6c652073,
    0x6b696e67, 0x73206f74, 0x68656172, 0x20746865, 0x6d757369, 0x63206f66, 0x4a6f686e,
    0x20506172, 0x6b657220,
  ])
  let x2 : FixedArray[Int] = FixedArray::from_array([
    0x76657469, 0x6d612e67, 0x6e696e65, 0x6c656172, 0x44206f66, 0x2070656f, 0x6c652073,
    0x6b696e67, 0x73206f74, 0x68656172, 0x20746865, 0x6d757369, 0x63206f66, 0x4a6f686e,
    0x20506172, 0x6b657220,
  ])
  salsa20_8_core(x1)
  salsa20_8_core(x2)
  for i = 0; i < 16; i = i + 1 {
    assert_eq(x1[i], x2[i])
  }
}
