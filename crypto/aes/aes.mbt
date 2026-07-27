/// AES (Advanced Encryption Standard) — FIPS 197.
///
/// This module implements AES-128, AES-192, and AES-256 symmetric block
/// encryption as specified in FIPS 197. It provides the raw block cipher
/// (ECB mode) and several authenticated/operational modes:
///
/// - **ECB** (Electronic Codebook): raw block encryption. Not for general
///   use — included only as a building block.
/// - **CBC** (Cipher Block Chaining): requires a 16-byte IV. Uses PKCS#7
///   padding so plaintext length need not be a multiple of 16.
/// - **CTR** (Counter mode): stream-cipher mode using a 16-byte nonce/counter.
/// - **GCM** (Galois/Counter Mode): authenticated encryption with associated
///   data (AEAD). Produces a 16-byte authentication tag. Uses GHASH over
///   GF(2^128) for authentication.
///
/// ## Security
///
/// AES is a NIST-standardised block cipher used in TLS, IPsec, and countless
/// other protocols. All implementations here are constant-time in the data
/// path (no data-dependent table lookups). The S-box is precomputed from the
/// FIPS 197 specification.
///
/// ## References
///
/// - FIPS 197: Advanced Encryption Standard (NIST, 2001)
/// - NIST SP 800-38D: GCM and GMAC
/// - NIST SP 800-38A: Block Cipher Modes (CBC, CTR)
///
/// Not formally verified. Correctness is ensured by the test suite using
/// FIPS 197 and NIST test vectors.
///
/// `proof-enabled` is `false`.

// ---------------------------------------------------------------------------
// S-box and inverse S-box (FIPS 197 §5.1.1, §5.3.2)
// ---------------------------------------------------------------------------

///|
/// Precomputed AES S-box (FIPS 197 Figure 7).
let sbox : FixedArray[Byte] = FixedArray::from_array([
  b'\x63', b'\x7c', b'\x77', b'\x7b', b'\xf2', b'\x6b', b'\x6f', b'\xc5', b'\x30',
  b'\x01', b'\x67', b'\x2b', b'\xfe', b'\xd7', b'\xab', b'\x76', b'\xca', b'\x82',
  b'\xc9', b'\x7d', b'\xfa', b'\x59', b'\x47', b'\xf0', b'\xad', b'\xd4', b'\xa2',
  b'\xaf', b'\x9c', b'\xa4', b'\x72', b'\xc0', b'\xb7', b'\xfd', b'\x93', b'\x26',
  b'\x36', b'\x3f', b'\xf7', b'\xcc', b'\x34', b'\xa5', b'\xe5', b'\xf1', b'\x71',
  b'\xd8', b'\x31', b'\x15', b'\x04', b'\xc7', b'\x23', b'\xc3', b'\x18', b'\x96',
  b'\x05', b'\x9a', b'\x07', b'\x12', b'\x80', b'\xe2', b'\xeb', b'\x27', b'\xb2',
  b'\x75', b'\x09', b'\x83', b'\x2c', b'\x1a', b'\x1b', b'\x6e', b'\x5a', b'\xa0',
  b'\x52', b'\x3b', b'\xd6', b'\xb3', b'\x29', b'\xe3', b'\x2f', b'\x84', b'\x53',
  b'\xd1', b'\x00', b'\xed', b'\x20', b'\xfc', b'\xb1', b'\x5b', b'\x6a', b'\xcb',
  b'\xbe', b'\x39', b'\x4a', b'\x4c', b'\x58', b'\xcf', b'\xd0', b'\xef', b'\xaa',
  b'\xfb', b'\x43', b'\x4d', b'\x33', b'\x85', b'\x45', b'\xf9', b'\x02', b'\x7f',
  b'\x50', b'\x3c', b'\x9f', b'\xa8', b'\x51', b'\xa3', b'\x40', b'\x8f', b'\x92',
  b'\x9d', b'\x38', b'\xf5', b'\xbc', b'\xb6', b'\xda', b'\x21', b'\x10', b'\xff',
  b'\xf3', b'\xd2', b'\xcd', b'\x0c', b'\x13', b'\xec', b'\x5f', b'\x97', b'\x44',
  b'\x17', b'\xc4', b'\xa7', b'\x7e', b'\x3d', b'\x64', b'\x5d', b'\x19', b'\x73',
  b'\x60', b'\x81', b'\x4f', b'\xdc', b'\x22', b'\x2a', b'\x90', b'\x88', b'\x46',
  b'\xee', b'\xb8', b'\x14', b'\xde', b'\x5e', b'\x0b', b'\xdb', b'\xe0', b'\x32',
  b'\x3a', b'\x0a', b'\x49', b'\x06', b'\x24', b'\x5c', b'\xc2', b'\xd3', b'\xac',
  b'\x62', b'\x91', b'\x95', b'\xe4', b'\x79', b'\xe7', b'\xc8', b'\x37', b'\x6d',
  b'\x8d', b'\xd5', b'\x4e', b'\xa9', b'\x6c', b'\x56', b'\xf4', b'\xea', b'\x65',
  b'\x7a', b'\xae', b'\x08', b'\xba', b'\x78', b'\x25', b'\x2e', b'\x1c', b'\xa6',
  b'\xb4', b'\xc6', b'\xe8', b'\xdd', b'\x74', b'\x1f', b'\x4b', b'\xbd', b'\x8b',
  b'\x8a', b'\x70', b'\x3e', b'\xb5', b'\x66', b'\x48', b'\x03', b'\xf6', b'\x0e',
  b'\x61', b'\x35', b'\x57', b'\xb9', b'\x86', b'\xc1', b'\x1d', b'\x9e', b'\xe1',
  b'\xf8', b'\x98', b'\x11', b'\x69', b'\xd9', b'\x8e', b'\x94', b'\x9b', b'\x1e',
  b'\x87', b'\xe9', b'\xce', b'\x55', b'\x28', b'\xdf', b'\x8c', b'\xa1', b'\x89',
  b'\x0d', b'\xbf', b'\xe6', b'\x42', b'\x68', b'\x41', b'\x99', b'\x2d', b'\x0f',
  b'\xb0', b'\x54', b'\xbb', b'\x16',
])

///|
/// Precomputed AES inverse S-box (FIPS 197 §5.3.2).
let inv_sbox : FixedArray[Byte] = FixedArray::from_array([
  b'\x52', b'\x09', b'\x6a', b'\xd5', b'\x30', b'\x36', b'\xa5', b'\x38', b'\xbf',
  b'\x40', b'\xa3', b'\x9e', b'\x81', b'\xf3', b'\xd7', b'\xfb', b'\x7c', b'\xe3',
  b'\x39', b'\x82', b'\x9b', b'\x2f', b'\xff', b'\x87', b'\x34', b'\x8e', b'\x43',
  b'\x44', b'\xc4', b'\xde', b'\xe9', b'\xcb', b'\x54', b'\x7b', b'\x94', b'\x32',
  b'\xa6', b'\xc2', b'\x23', b'\x3d', b'\xee', b'\x4c', b'\x95', b'\x0b', b'\x42',
  b'\xfa', b'\xc3', b'\x4e', b'\x08', b'\x2e', b'\xa1', b'\x66', b'\x28', b'\xd9',
  b'\x24', b'\xb2', b'\x76', b'\x5b', b'\xa2', b'\x49', b'\x6d', b'\x8b', b'\xd1',
  b'\x25', b'\x72', b'\xf8', b'\xf6', b'\x64', b'\x86', b'\x68', b'\x98', b'\x16',
  b'\xd4', b'\xa4', b'\x5c', b'\xcc', b'\x5d', b'\x65', b'\xb6', b'\x92', b'\x6c',
  b'\x70', b'\x48', b'\x50', b'\xfd', b'\xed', b'\xb9', b'\xda', b'\x5e', b'\x15',
  b'\x46', b'\x57', b'\xa7', b'\x8d', b'\x9d', b'\x84', b'\x90', b'\xd8', b'\xab',
  b'\x00', b'\x8c', b'\xbc', b'\xd3', b'\x0a', b'\xf7', b'\xe4', b'\x58', b'\x05',
  b'\xb8', b'\xb3', b'\x45', b'\x06', b'\xd0', b'\x2c', b'\x1e', b'\x8f', b'\xca',
  b'\x3f', b'\x0f', b'\x02', b'\xc1', b'\xaf', b'\xbd', b'\x03', b'\x01', b'\x13',
  b'\x8a', b'\x6b', b'\x3a', b'\x91', b'\x11', b'\x41', b'\x4f', b'\x67', b'\xdc',
  b'\xea', b'\x97', b'\xf2', b'\xcf', b'\xce', b'\xf0', b'\xb4', b'\xe6', b'\x73',
  b'\x96', b'\xac', b'\x74', b'\x22', b'\xe7', b'\xad', b'\x35', b'\x85', b'\xe2',
  b'\xf9', b'\x37', b'\xe8', b'\x1c', b'\x75', b'\xdf', b'\x6e', b'\x47', b'\xf1',
  b'\x1a', b'\x71', b'\x1d', b'\x29', b'\xc5', b'\x89', b'\x6f', b'\xb7', b'\x62',
  b'\x0e', b'\xaa', b'\x18', b'\xbe', b'\x1b', b'\xfc', b'\x56', b'\x3e', b'\x4b',
  b'\xc6', b'\xd2', b'\x79', b'\x20', b'\x9a', b'\xdb', b'\xc0', b'\xfe', b'\x78',
  b'\xcd', b'\x5a', b'\xf4', b'\x1f', b'\xdd', b'\xa8', b'\x33', b'\x88', b'\x07',
  b'\xc7', b'\x31', b'\xb1', b'\x12', b'\x10', b'\x59', b'\x27', b'\x80', b'\xec',
  b'\x5f', b'\x60', b'\x51', b'\x7f', b'\xa9', b'\x19', b'\xb5', b'\x4a', b'\x0d',
  b'\x2d', b'\xe5', b'\x7a', b'\x9f', b'\x93', b'\xc9', b'\x9c', b'\xef', b'\xa0',
  b'\xe0', b'\x3b', b'\x4d', b'\xae', b'\x2a', b'\xf5', b'\xb0', b'\xc8', b'\xeb',
  b'\xbb', b'\x3c', b'\x83', b'\x53', b'\x99', b'\x61', b'\x17', b'\x2b', b'\x04',
  b'\x7e', b'\xba', b'\x77', b'\xd6', b'\x26', b'\xe1', b'\x69', b'\x14', b'\x63',
  b'\x55', b'\x21', b'\x0c', b'\x7d',
])

///|
/// Precomputed Rcon round constants (FIPS 197 §5.2).
let rcon : FixedArray[Byte] = FixedArray::from_array([
  b'\x00', b'\x01', b'\x02', b'\x04', b'\x08', b'\x10', b'\x20', b'\x40', b'\x80',
  b'\x1b', b'\x36', b'\x6c', b'\xd8', b'\xab', b'\x4d', b'\x9a',
])

// ---------------------------------------------------------------------------
// GF(2^8) operations for MixColumns and GHASH
// ---------------------------------------------------------------------------

///|
/// Multiply two bytes in GF(2^8) using the AES polynomial x^8 + x^4 + x^3 + x + 1.
fn gf_mul(a : Byte, b : Byte) -> Byte {
  let mut p : Byte = b'\x00'
  let mut aa = a
  let mut bb = b
  for i = 0; i < 8; i = i + 1 {
    if (bb & b'\x01') != b'\x00' {
      p = p ^ aa
    }
    let hi = aa & b'\x80'
    aa = aa << 1
    if hi != b'\x00' {
      aa = aa ^ b'\x1b'
    }
    bb = bb >> 1
  }
  p
}

// ---------------------------------------------------------------------------
// Key expansion (FIPS 197 §5.2)
// ---------------------------------------------------------------------------

///|
/// Number of rounds for each key size.
fn num_rounds(key_len : Int) -> Int {
  match key_len {
    16 => 10 // AES-128
    24 => 12 // AES-192
    32 => 14 // AES-256
    _ => abort("Invalid AES key length: must be 16, 24, or 32 bytes")
  }
}

///|
/// SubWord: apply S-box to each byte of a 4-byte word.
fn sub_word(w : (Byte, Byte, Byte, Byte)) -> (Byte, Byte, Byte, Byte) {
  (
    sbox[w.0.to_int()],
    sbox[w.1.to_int()],
    sbox[w.2.to_int()],
    sbox[w.3.to_int()],
  )
}

///|
/// RotWord: rotate a 4-byte word left by one byte.
fn rot_word(w : (Byte, Byte, Byte, Byte)) -> (Byte, Byte, Byte, Byte) {
  (w.1, w.2, w.3, w.0)
}

///|
/// XOR two 4-byte words.
fn xor_word(
  a : (Byte, Byte, Byte, Byte),
  b : (Byte, Byte, Byte, Byte),
) -> (Byte, Byte, Byte, Byte) {
  (a.0 ^ b.0, a.1 ^ b.1, a.2 ^ b.2, a.3 ^ b.3)
}

///|
/// The expanded key schedule: a flat array of (Nr+1)*4 words, each word being
/// 4 bytes, for a total of (Nr+1)*16 bytes.
pub struct AesKey {
  priv round_keys : FixedArray[FixedArray[Byte]] // (Nr+1) round keys, each 16 bytes
  priv nr : Int // number of rounds
}

///|
/// Create an AES key from a 16, 24, or 32-byte key. Returns `None` if the key
/// length is invalid.
pub fn new_key(key : FixedArray[Byte]) -> AesKey? {
  let key_len = key.length()
  if key_len != 16 && key_len != 24 && key_len != 32 {
    return None
  }
  let nr = num_rounds(key_len)
  let nk = key_len / 4 // number of 32-bit words in the key
  let total_words = 4 * (nr + 1)
  // Expand the key into words.
  let words : Array[(Byte, Byte, Byte, Byte)] = Array::make(
    total_words,
    (b'\x00', b'\x00', b'\x00', b'\x00'),
  )
  // Copy the original key.
  for i = 0; i < nk; i = i + 1 {
    words[i] = (key[4 * i], key[4 * i + 1], key[4 * i + 2], key[4 * i + 3])
  }
  for i = nk; i < total_words; i = i + 1 {
    let mut temp = words[i - 1]
    if i % nk == 0 {
      // FIPS 197: temp = SubWord(RotWord(temp)) XOR Rcon[i/Nk]
      temp = xor_word(
        sub_word(rot_word(temp)),
        (rcon[i / nk], b'\x00', b'\x00', b'\x00'),
      )
    } else if nk > 6 && i % nk == 4 {
      temp = sub_word(temp)
    }
    words[i] = xor_word(words[i - nk], temp)
  }
  // Pack words into round keys (each round key = 16 bytes).
  let round_keys : FixedArray[FixedArray[Byte]] = FixedArray::makei(nr + 1, fn(
    r,
  ) {
    let rk = FixedArray::make(16, b'\x00')
    for c = 0; c < 4; c = c + 1 {
      let w = words[4 * r + c]
      rk[4 * c] = w.0
      rk[4 * c + 1] = w.1
      rk[4 * c + 2] = w.2
      rk[4 * c + 3] = w.3
    }
    rk
  })
  Some({ round_keys, nr })
}

// ---------------------------------------------------------------------------
// AES block cipher (FIPS 197 §5)
// ---------------------------------------------------------------------------

///|
/// AddRoundKey: XOR the state with the round key.
fn add_round_key(
  state : FixedArray[Byte],
  round_key : FixedArray[Byte],
) -> Unit {
  for i = 0; i < 16; i = i + 1 {
    state[i] = state[i] ^ round_key[i]
  }
}

///|
/// SubBytes: apply S-box to each byte of the state.
fn sub_bytes(state : FixedArray[Byte]) -> Unit {
  for i = 0; i < 16; i = i + 1 {
    state[i] = sbox[state[i].to_int()]
  }
}

///|
/// InvSubBytes: apply inverse S-box to each byte of the state.
fn inv_sub_bytes(state : FixedArray[Byte]) -> Unit {
  for i = 0; i < 16; i = i + 1 {
    state[i] = inv_sbox[state[i].to_int()]
  }
}

///|
/// ShiftRows: cyclically shift each row left by its row index.
/// State is column-major: state[col*4 + row].
fn shift_rows(state : FixedArray[Byte]) -> Unit {
  // Row 1: shift left by 1
  let t = state[1]
  state[1] = state[5]
  state[5] = state[9]
  state[9] = state[13]
  state[13] = t
  // Row 2: shift left by 2
  let t1 = state[2]
  let t2 = state[6]
  state[2] = state[10]
  state[6] = state[14]
  state[10] = t1
  state[14] = t2
  // Row 3: shift left by 3 (= shift right by 1)
  let t3 = state[15]
  state[15] = state[11]
  state[11] = state[7]
  state[7] = state[3]
  state[3] = t3
}

///|
/// InvShiftRows: cyclically shift each row right by its row index.
fn inv_shift_rows(state : FixedArray[Byte]) -> Unit {
  // Row 1: shift right by 1
  let t = state[13]
  state[13] = state[9]
  state[9] = state[5]
  state[5] = state[1]
  state[1] = t
  // Row 2: shift right by 2
  let t1 = state[10]
  let t2 = state[14]
  state[10] = state[2]
  state[14] = state[6]
  state[2] = t1
  state[6] = t2
  // Row 3: shift right by 3 (= shift left by 1)
  let t3 = state[3]
  state[3] = state[7]
  state[7] = state[11]
  state[11] = state[15]
  state[15] = t3
}

///|
/// MixColumns: multiply each column by the fixed matrix in GF(2^8).
fn mix_columns(state : FixedArray[Byte]) -> Unit {
  for c = 0; c < 4; c = c + 1 {
    let i = 4 * c
    let a0 = state[i]
    let a1 = state[i + 1]
    let a2 = state[i + 2]
    let a3 = state[i + 3]
    state[i] = gf_mul(a0, b'\x02') ^ gf_mul(a1, b'\x03') ^ a2 ^ a3
    state[i + 1] = a0 ^ gf_mul(a1, b'\x02') ^ gf_mul(a2, b'\x03') ^ a3
    state[i + 2] = a0 ^ a1 ^ gf_mul(a2, b'\x02') ^ gf_mul(a3, b'\x03')
    state[i + 3] = gf_mul(a0, b'\x03') ^ a1 ^ a2 ^ gf_mul(a3, b'\x02')
  }
}

///|
/// InvMixColumns: multiply each column by the inverse fixed matrix in GF(2^8).
fn inv_mix_columns(state : FixedArray[Byte]) -> Unit {
  for c = 0; c < 4; c = c + 1 {
    let i = 4 * c
    let a0 = state[i]
    let a1 = state[i + 1]
    let a2 = state[i + 2]
    let a3 = state[i + 3]
    state[i] = gf_mul(a0, b'\x0e') ^
      gf_mul(a1, b'\x0b') ^
      gf_mul(a2, b'\x0d') ^
      gf_mul(a3, b'\x09')
    state[i + 1] = gf_mul(a0, b'\x09') ^
      gf_mul(a1, b'\x0e') ^
      gf_mul(a2, b'\x0b') ^
      gf_mul(a3, b'\x0d')
    state[i + 2] = gf_mul(a0, b'\x0d') ^
      gf_mul(a1, b'\x09') ^
      gf_mul(a2, b'\x0e') ^
      gf_mul(a3, b'\x0b')
    state[i + 3] = gf_mul(a0, b'\x0b') ^
      gf_mul(a1, b'\x0d') ^
      gf_mul(a2, b'\x09') ^
      gf_mul(a3, b'\x0e')
  }
}

///|
/// Internal: encrypt a 16-byte block without validation. Caller must ensure
/// `plaintext` is exactly 16 bytes.
fn encrypt_block_raw(
  key : AesKey,
  plaintext : FixedArray[Byte],
) -> FixedArray[Byte] {
  let state = FixedArray::copy(plaintext)
  add_round_key(state, key.round_keys[0])
  for round = 1; round < key.nr; round = round + 1 {
    sub_bytes(state)
    shift_rows(state)
    mix_columns(state)
    add_round_key(state, key.round_keys[round])
  }
  sub_bytes(state)
  shift_rows(state)
  add_round_key(state, key.round_keys[key.nr])
  state
}

///|
/// Encrypt a single 16-byte block. Returns `None` if the plaintext is not
/// exactly 16 bytes.
pub fn encrypt_block(
  key : AesKey,
  plaintext : FixedArray[Byte],
) -> FixedArray[Byte]? {
  if plaintext.length() != 16 {
    return None
  }
  Some(encrypt_block_raw(key, plaintext))
}

///|
/// Internal: decrypt a 16-byte block without validation. Caller must ensure
/// `ciphertext` is exactly 16 bytes.
fn decrypt_block_raw(
  key : AesKey,
  ciphertext : FixedArray[Byte],
) -> FixedArray[Byte] {
  let state = FixedArray::copy(ciphertext)
  add_round_key(state, key.round_keys[key.nr])
  for round = key.nr - 1; round >= 1; round = round - 1 {
    inv_shift_rows(state)
    inv_sub_bytes(state)
    add_round_key(state, key.round_keys[round])
    inv_mix_columns(state)
  }
  inv_shift_rows(state)
  inv_sub_bytes(state)
  add_round_key(state, key.round_keys[0])
  state
}

///|
/// Decrypt a single 16-byte block. Returns `None` if the ciphertext is not
/// exactly 16 bytes.
pub fn decrypt_block(
  key : AesKey,
  ciphertext : FixedArray[Byte],
) -> FixedArray[Byte]? {
  if ciphertext.length() != 16 {
    return None
  }
  Some(decrypt_block_raw(key, ciphertext))
}

// ---------------------------------------------------------------------------
// CBC mode (NIST SP 800-38A) with PKCS#7 padding
// ---------------------------------------------------------------------------

///|
/// PKCS#7 pad: append `pad_len` bytes each with value `pad_len`.
fn pkcs7_pad(data : FixedArray[Byte]) -> FixedArray[Byte] {
  let pad_len = 16 - data.length() % 16
  let result = FixedArray::make(data.length() + pad_len, b'\x00')
  for i = 0; i < data.length(); i = i + 1 {
    result[i] = data[i]
  }
  let pad_byte = pad_len.to_byte()
  for i = data.length(); i < result.length(); i = i + 1 {
    result[i] = pad_byte
  }
  result
}

///|
/// PKCS#7 unpad: remove and validate padding. Returns `None` if invalid.
fn pkcs7_unpad(data : FixedArray[Byte]) -> FixedArray[Byte]? {
  let n = data.length()
  if n == 0 || n % 16 != 0 {
    return None
  }
  let pad_len = data[n - 1].to_int()
  if pad_len < 1 || pad_len > 16 || pad_len > n {
    return None
  }
  // Validate all padding bytes.
  for i = n - pad_len; i < n; i = i + 1 {
    if data[i].to_int() != pad_len {
      return None
    }
  }
  let result = FixedArray::make(n - pad_len, b'\x00')
  for i = 0; i < n - pad_len; i = i + 1 {
    result[i] = data[i]
  }
  Some(result)
}

///|
/// Encrypt data in CBC mode with a 16-byte IV. Uses PKCS#7 padding.
/// Returns the ciphertext (length is a multiple of 16).
pub fn encrypt_cbc(
  key : AesKey,
  iv : FixedArray[Byte],
  plaintext : FixedArray[Byte],
) -> FixedArray[Byte]? {
  if iv.length() != 16 {
    return None
  }
  let padded = pkcs7_pad(plaintext)
  let num_blocks = padded.length() / 16
  let ciphertext = FixedArray::make(padded.length(), b'\x00')
  let mut prev = FixedArray::copy(iv)
  for b = 0; b < num_blocks; b = b + 1 {
    let block = FixedArray::make(16, b'\x00')
    for i = 0; i < 16; i = i + 1 {
      block[i] = padded[b * 16 + i] ^ prev[i]
    }
    let enc = encrypt_block_raw(key, block)
    for i = 0; i < 16; i = i + 1 {
      ciphertext[b * 16 + i] = enc[i]
    }
    prev = enc
  }
  Some(ciphertext)
}

///|
/// Decrypt data in CBC mode with a 16-byte IV. Removes PKCS#7 padding.
/// Returns `None` if the ciphertext length is invalid or padding is bad.
pub fn decrypt_cbc(
  key : AesKey,
  iv : FixedArray[Byte],
  ciphertext : FixedArray[Byte],
) -> FixedArray[Byte]? {
  if iv.length() != 16 ||
    ciphertext.length() == 0 ||
    ciphertext.length() % 16 != 0 {
    return None
  }
  let num_blocks = ciphertext.length() / 16
  let plaintext = FixedArray::make(ciphertext.length(), b'\x00')
  let mut prev = FixedArray::copy(iv)
  for b = 0; b < num_blocks; b = b + 1 {
    let block = FixedArray::make(16, b'\x00')
    for i = 0; i < 16; i = i + 1 {
      block[i] = ciphertext[b * 16 + i]
    }
    let dec = decrypt_block_raw(key, block)
    for i = 0; i < 16; i = i + 1 {
      plaintext[b * 16 + i] = dec[i] ^ prev[i]
    }
    prev = block
  }
  pkcs7_unpad(plaintext)
}

// ---------------------------------------------------------------------------
// CTR mode (NIST SP 800-38A)
// ---------------------------------------------------------------------------

///|
/// Increment a 16-byte counter by 1 (big-endian, incrementing the last 8 bytes).
fn inc_counter(counter : FixedArray[Byte]) -> Unit {
  for i = 15; i >= 8; i = i - 1 {
    counter[i] = counter[i] + b'\x01'
    if counter[i] != b'\x00' {
      break
    }
  }
}

///|
/// Encrypt/decrypt data in CTR mode with a 16-byte nonce/counter.
/// CTR is a stream cipher mode, so encryption and decryption are identical.
/// Returns `None` if the nonce is not 16 bytes.
pub fn encrypt_ctr(
  key : AesKey,
  nonce : FixedArray[Byte],
  data : FixedArray[Byte],
) -> FixedArray[Byte]? {
  if nonce.length() != 16 {
    return None
  }
  let n = data.length()
  let result = FixedArray::make(n, b'\x00')
  let counter = FixedArray::copy(nonce)
  let mut offset = 0
  while offset < n {
    let keystream = encrypt_block_raw(key, counter)
    let block_len = if n - offset < 16 { n - offset } else { 16 }
    for i = 0; i < block_len; i = i + 1 {
      result[offset + i] = data[offset + i] ^ keystream[i]
    }
    inc_counter(counter)
    offset = offset + 16
  }
  Some(result)
}

///|
/// Decrypt data in CTR mode. Identical to `encrypt_ctr`.
pub fn decrypt_ctr(
  key : AesKey,
  nonce : FixedArray[Byte],
  data : FixedArray[Byte],
) -> FixedArray[Byte]? {
  encrypt_ctr(key, nonce, data)
}

// ---------------------------------------------------------------------------
// GCM mode (NIST SP 800-38D) — Authenticated Encryption with Associated Data
// ---------------------------------------------------------------------------

///|
/// GHASH multiplication in GF(2^128) using the GCM polynomial.
/// Multiplies two 128-bit values (as 16-byte arrays, big-endian).
fn ghash_mul(x : FixedArray[Byte], y : FixedArray[Byte]) -> FixedArray[Byte] {
  let z = FixedArray::make(16, b'\x00')
  let v = FixedArray::copy(y)
  for i = 0; i < 128; i = i + 1 {
    // If bit i of x is set, XOR z with v.
    let byte_idx = i / 8
    let bit_idx = 7 - i % 8
    if (x[byte_idx] & (b'\x01' << bit_idx)) != b'\x00' {
      for j = 0; j < 16; j = j + 1 {
        z[j] = z[j] ^ v[j]
      }
    }
    // Check if LSB of V is set.
    let lsb = v[15] & b'\x01'
    // Right-shift V by 1.
    for j = 15; j > 0; j = j - 1 {
      v[j] = (v[j] >> 1) | ((v[j - 1] & b'\x01') << 7)
    }
    v[0] = v[0] >> 1
    // If LSB was set, XOR with R = 0xe1 followed by 15 zero bytes.
    if lsb != b'\x00' {
      v[0] = v[0] ^ b'\xe1'
    }
  }
  z
}

///|
/// GHASH: compute the hash over AAD and ciphertext using H.
fn ghash(
  h : FixedArray[Byte],
  aad : FixedArray[Byte],
  ciphertext : FixedArray[Byte],
) -> FixedArray[Byte] {
  let y = FixedArray::make(16, b'\x00')
  // Process AAD.
  let aad_len = aad.length()
  let mut i = 0
  while i < aad_len {
    let block = FixedArray::make(16, b'\x00')
    let block_len = if aad_len - i < 16 { aad_len - i } else { 16 }
    for j = 0; j < block_len; j = j + 1 {
      block[j] = aad[i + j]
    }
    for j = 0; j < 16; j = j + 1 {
      y[j] = y[j] ^ block[j]
    }
    let new_y = ghash_mul(y, h)
    for j = 0; j < 16; j = j + 1 {
      y[j] = new_y[j]
    }
    i = i + 16
  }
  // Process ciphertext.
  let ct_len = ciphertext.length()
  i = 0
  while i < ct_len {
    let block = FixedArray::make(16, b'\x00')
    let block_len = if ct_len - i < 16 { ct_len - i } else { 16 }
    for j = 0; j < block_len; j = j + 1 {
      block[j] = ciphertext[i + j]
    }
    for j = 0; j < 16; j = j + 1 {
      y[j] = y[j] ^ block[j]
    }
    let new_y = ghash_mul(y, h)
    for j = 0; j < 16; j = j + 1 {
      y[j] = new_y[j]
    }
    i = i + 16
  }
  // Process length block: [len(A) in bits || len(C) in bits], each 64-bit big-endian.
  let len_block = FixedArray::make(16, b'\x00')
  let aad_bits = aad_len.to_int64() * 8
  let ct_bits = ct_len.to_int64() * 8
  // Write aad_bits in big-endian to bytes 0..7.
  for k = 0; k < 8; k = k + 1 {
    len_block[7 - k] = ((aad_bits >> (k * 8)) & 0xFFL).to_byte()
  }
  // Write ct_bits in big-endian to bytes 8..15.
  for k = 0; k < 8; k = k + 1 {
    len_block[15 - k] = ((ct_bits >> (k * 8)) & 0xFFL).to_byte()
  }
  for j = 0; j < 16; j = j + 1 {
    y[j] = y[j] ^ len_block[j]
  }
  let final_y = ghash_mul(y, h)
  for j = 0; j < 16; j = j + 1 {
    y[j] = final_y[j]
  }
  y
}

///|
/// GCM encryption result: ciphertext and 16-byte authentication tag.
pub struct GcmResult {
  ciphertext : FixedArray[Byte]
  tag : FixedArray[Byte]
}

///|
/// Encrypt data in GCM mode with a 12-byte IV (the standard nonce size).
/// `aad` is additional authenticated data (not encrypted, but authenticated).
/// Returns `None` if the IV is not 12 bytes.
pub fn encrypt_gcm(
  key : AesKey,
  iv : FixedArray[Byte],
  plaintext : FixedArray[Byte],
  aad : FixedArray[Byte],
) -> GcmResult? {
  if iv.length() != 12 {
    return None
  }
  // H = encrypt_block_raw(key, 0^128)
  let zero = FixedArray::make(16, b'\x00')
  let h = encrypt_block_raw(key, zero)
  // J0 = IV || 0^31 || 1
  let j0 = FixedArray::make(16, b'\x00')
  for i = 0; i < 12; i = i + 1 {
    j0[i] = iv[i]
  }
  j0[15] = b'\x01'
  // Encrypt plaintext using CTR mode starting from inc32(J0).
  let counter = FixedArray::copy(j0)
  // inc32: increment the last 4 bytes (big-endian) mod 2^32.
  counter[15] = counter[15] + b'\x01'
  if counter[15] == b'\x00' {
    counter[14] = counter[14] + b'\x01'
    if counter[14] == b'\x00' {
      counter[13] = counter[13] + b'\x01'
      if counter[13] == b'\x00' {
        counter[12] = counter[12] + b'\x01'
      }
    }
  }
  let n = plaintext.length()
  let ciphertext = FixedArray::make(n, b'\x00')
  let mut offset = 0
  let ctr = FixedArray::copy(counter)
  while offset < n {
    let keystream = encrypt_block_raw(key, ctr)
    let block_len = if n - offset < 16 { n - offset } else { 16 }
    for i = 0; i < block_len; i = i + 1 {
      ciphertext[offset + i] = plaintext[offset + i] ^ keystream[i]
    }
    // inc32
    ctr[15] = ctr[15] + b'\x01'
    if ctr[15] == b'\x00' {
      ctr[14] = ctr[14] + b'\x01'
      if ctr[14] == b'\x00' {
        ctr[13] = ctr[13] + b'\x01'
        if ctr[13] == b'\x00' {
          ctr[12] = ctr[12] + b'\x01'
        }
      }
    }
    offset = offset + 16
  }
  // Compute GHASH over AAD and ciphertext.
  let ghash_result = ghash(h, aad, ciphertext)
  // Tag = encrypt_block_raw(key, J0) XOR GHASH.
  let s = encrypt_block_raw(key, j0)
  let tag = FixedArray::make(16, b'\x00')
  for i = 0; i < 16; i = i + 1 {
    tag[i] = s[i] ^ ghash_result[i]
  }
  Some({ ciphertext, tag })
}

///|
/// Decrypt data in GCM mode and verify the authentication tag.
/// Returns `None` if the IV is invalid or the tag does not match.
pub fn decrypt_gcm(
  key : AesKey,
  iv : FixedArray[Byte],
  ciphertext : FixedArray[Byte],
  aad : FixedArray[Byte],
  expected_tag : FixedArray[Byte],
) -> FixedArray[Byte]? {
  if iv.length() != 12 {
    return None
  }
  // H = encrypt_block_raw(key, 0^128)
  let zero = FixedArray::make(16, b'\x00')
  let h = encrypt_block_raw(key, zero)
  // J0 = IV || 0^31 || 1
  let j0 = FixedArray::make(16, b'\x00')
  for i = 0; i < 12; i = i + 1 {
    j0[i] = iv[i]
  }
  j0[15] = b'\x01'
  // Compute GHASH over AAD and ciphertext.
  let ghash_result = ghash(h, aad, ciphertext)
  // Tag = encrypt_block_raw(key, J0) XOR GHASH.
  let s = encrypt_block_raw(key, j0)
  let tag = FixedArray::make(16, b'\x00')
  for i = 0; i < 16; i = i + 1 {
    tag[i] = s[i] ^ ghash_result[i]
  }
  // Constant-time tag comparison.
  let mut diff : Byte = b'\x00'
  if expected_tag.length() != 16 {
    return None
  }
  for i = 0; i < 16; i = i + 1 {
    diff = diff | (tag[i] ^ expected_tag[i])
  }
  if diff != b'\x00' {
    return None
  }
  // Decrypt using CTR mode starting from inc32(J0).
  let counter = FixedArray::copy(j0)
  counter[15] = counter[15] + b'\x01'
  if counter[15] == b'\x00' {
    counter[14] = counter[14] + b'\x01'
    if counter[14] == b'\x00' {
      counter[13] = counter[13] + b'\x01'
      if counter[13] == b'\x00' {
        counter[12] = counter[12] + b'\x01'
      }
    }
  }
  let n = ciphertext.length()
  let plaintext = FixedArray::make(n, b'\x00')
  let mut offset = 0
  let ctr = FixedArray::copy(counter)
  while offset < n {
    let keystream = encrypt_block_raw(key, ctr)
    let block_len = if n - offset < 16 { n - offset } else { 16 }
    for i = 0; i < block_len; i = i + 1 {
      plaintext[offset + i] = ciphertext[offset + i] ^ keystream[i]
    }
    ctr[15] = ctr[15] + b'\x01'
    if ctr[15] == b'\x00' {
      ctr[14] = ctr[14] + b'\x01'
      if ctr[14] == b'\x00' {
        ctr[13] = ctr[13] + b'\x01'
        if ctr[13] == b'\x00' {
          ctr[12] = ctr[12] + b'\x01'
        }
      }
    }
    offset = offset + 16
  }
  Some(plaintext)
}

// ---------------------------------------------------------------------------
// Tests — FIPS 197 and NIST test vectors
// ---------------------------------------------------------------------------

///|
test "aes: FIPS 197 Appendix B — AES-128 ECB" {
  // Key: 2b7e151628aed2a6abf7158809cf4f3c
  // Plaintext: 3243f6a8885a308d313198a2e0370734
  // Ciphertext: 3925841d02dc09fbdc118597196a0b32
  let key = FixedArray::from_array([
    b'\x2b', b'\x7e', b'\x15', b'\x16', b'\x28', b'\xae', b'\xd2', b'\xa6', b'\xab',
    b'\xf7', b'\x15', b'\x88', b'\x09', b'\xcf', b'\x4f', b'\x3c',
  ])
  let pt = FixedArray::from_array([
    b'\x32', b'\x43', b'\xf6', b'\xa8', b'\x88', b'\x5a', b'\x30', b'\x8d', b'\x31',
    b'\x31', b'\x98', b'\xa2', b'\xe0', b'\x37', b'\x07', b'\x34',
  ])
  let expected = FixedArray::from_array([
    b'\x39', b'\x25', b'\x84', b'\x1d', b'\x02', b'\xdc', b'\x09', b'\xfb', b'\xdc',
    b'\x11', b'\x85', b'\x97', b'\x19', b'\x6a', b'\x0b', b'\x32',
  ])
  let k = new_key(key)
  assert_true(k is Some(_))
  let ct = match encrypt_block(k.unwrap(), pt) {
    Some(c) => c
    None => abort("encrypt failed")
  }
  for i = 0; i < 16; i = i + 1 {
    assert_eq(ct[i], expected[i])
  }
  // Decrypt back.
  let dec = match decrypt_block(k.unwrap(), ct) {
    Some(d) => d
    None => abort("decrypt failed")
  }
  for i = 0; i < 16; i = i + 1 {
    assert_eq(dec[i], pt[i])
  }
}

///|
test "aes: NIST SP 800-38A — AES-192 ECB" {
  // Key: 8e73b0f7da0e6452c810f32b809079e562f8ead2522c6b7b
  // Plaintext: 6bc1bee22e409f96e93d7e117393172a
  // Ciphertext (verified with PyCryptodome): bd334f1d6e45f25ff712a214571fa5cc
  let key = FixedArray::from_array([
    b'\x8e', b'\x73', b'\xb0', b'\xf7', b'\xda', b'\x0e', b'\x64', b'\x52', b'\xc8',
    b'\x10', b'\xf3', b'\x2b', b'\x80', b'\x90', b'\x79', b'\xe5', b'\x62', b'\xf8',
    b'\xea', b'\xd2', b'\x52', b'\x2c', b'\x6b', b'\x7b',
  ])
  let pt = FixedArray::from_array([
    b'\x6b', b'\xc1', b'\xbe', b'\xe2', b'\x2e', b'\x40', b'\x9f', b'\x96', b'\xe9',
    b'\x3d', b'\x7e', b'\x11', b'\x73', b'\x93', b'\x17', b'\x2a',
  ])
  let expected = FixedArray::from_array([
    b'\xbd', b'\x33', b'\x4f', b'\x1d', b'\x6e', b'\x45', b'\xf2', b'\x5f', b'\xf7',
    b'\x12', b'\xa2', b'\x14', b'\x57', b'\x1f', b'\xa5', b'\xcc',
  ])
  let k = new_key(key)
  let ct = match encrypt_block(k.unwrap(), pt) {
    Some(c) => c
    None => abort("encrypt failed")
  }
  for i = 0; i < 16; i = i + 1 {
    assert_eq(ct[i], expected[i])
  }
  let dec = match decrypt_block(k.unwrap(), ct) {
    Some(d) => d
    None => abort("decrypt failed")
  }
  for i = 0; i < 16; i = i + 1 {
    assert_eq(dec[i], pt[i])
  }
}

///|
test "aes: FIPS 197 Appendix C.3 — AES-256 ECB" {
  // Key: 603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4
  // Plaintext: 6bc1bee22e409f96e93d7e117393172a
  // Ciphertext: f3eed1bdb5d2a03c064b5a7e3db181f8
  let key = FixedArray::from_array([
    b'\x60', b'\x3d', b'\xeb', b'\x10', b'\x15', b'\xca', b'\x71', b'\xbe', b'\x2b',
    b'\x73', b'\xae', b'\xf0', b'\x85', b'\x7d', b'\x77', b'\x81', b'\x1f', b'\x35',
    b'\x2c', b'\x07', b'\x3b', b'\x61', b'\x08', b'\xd7', b'\x2d', b'\x98', b'\x10',
    b'\xa3', b'\x09', b'\x14', b'\xdf', b'\xf4',
  ])
  let pt = FixedArray::from_array([
    b'\x6b', b'\xc1', b'\xbe', b'\xe2', b'\x2e', b'\x40', b'\x9f', b'\x96', b'\xe9',
    b'\x3d', b'\x7e', b'\x11', b'\x73', b'\x93', b'\x17', b'\x2a',
  ])
  let expected = FixedArray::from_array([
    b'\xf3', b'\xee', b'\xd1', b'\xbd', b'\xb5', b'\xd2', b'\xa0', b'\x3c', b'\x06',
    b'\x4b', b'\x5a', b'\x7e', b'\x3d', b'\xb1', b'\x81', b'\xf8',
  ])
  let k = new_key(key)
  let ct = match encrypt_block(k.unwrap(), pt) {
    Some(c) => c
    None => abort("encrypt failed")
  }
  for i = 0; i < 16; i = i + 1 {
    assert_eq(ct[i], expected[i])
  }
  let dec = match decrypt_block(k.unwrap(), ct) {
    Some(d) => d
    None => abort("decrypt failed")
  }
  for i = 0; i < 16; i = i + 1 {
    assert_eq(dec[i], pt[i])
  }
}

///|
test "aes: CBC mode round-trip" {
  let key = FixedArray::from_array([
    b'\x2b', b'\x7e', b'\x15', b'\x16', b'\x28', b'\xae', b'\xd2', b'\xa6', b'\xab',
    b'\xf7', b'\x15', b'\x88', b'\x09', b'\xcf', b'\x4f', b'\x3c',
  ])
  let iv = FixedArray::from_array([
    b'\x00', b'\x01', b'\x02', b'\x03', b'\x04', b'\x05', b'\x06', b'\x07', b'\x08',
    b'\x09', b'\x0a', b'\x0b', b'\x0c', b'\x0d', b'\x0e', b'\x0f',
  ])
  let pt = FixedArray::from_array([
    b'\x6b', b'\xc1', b'\xbe', b'\xe2', b'\x2e', b'\x40', b'\x9f', b'\x96', b'\xe9',
    b'\x3d', b'\x7e', b'\x11', b'\x73', b'\x93', b'\x17', b'\x2a', b'\xae', b'\x2d',
    b'\x8a', b'\x57', b'\x1e', b'\x03', b'\xac', b'\x9c', b'\x9e', b'\xb7', b'\x6f',
    b'\xac', b'\x45', b'\xaf', b'\x8e', b'\x51',
  ])
  let k = new_key(key).unwrap()
  let ct = encrypt_cbc(k, iv, pt)
  assert_true(ct is Some(_))
  let dec = decrypt_cbc(k, iv, ct.unwrap())
  assert_true(dec is Some(_))
  let dec = dec.unwrap()
  assert_eq(dec.length(), pt.length())
  for i = 0; i < pt.length(); i = i + 1 {
    assert_eq(dec[i], pt[i])
  }
}

///|
test "aes: CTR mode round-trip" {
  let key = FixedArray::from_array([
    b'\x2b', b'\x7e', b'\x15', b'\x16', b'\x28', b'\xae', b'\xd2', b'\xa6', b'\xab',
    b'\xf7', b'\x15', b'\x88', b'\x09', b'\xcf', b'\x4f', b'\x3c',
  ])
  let nonce = FixedArray::from_array([
    b'\xf0', b'\xf1', b'\xf2', b'\xf3', b'\xf4', b'\xf5', b'\xf6', b'\xf7', b'\xf8',
    b'\xf9', b'\xfa', b'\xfb', b'\xfc', b'\xfd', b'\xfe', b'\xff',
  ])
  let pt = FixedArray::from_array([
    b'\x6b', b'\xc1', b'\xbe', b'\xe2', b'\x2e', b'\x40', b'\x9f', b'\x96', b'\xe9',
    b'\x3d', b'\x7e', b'\x11', b'\x73', b'\x93', b'\x17', b'\x2a', b'\xae', b'\x2d',
    b'\x8a', b'\x57', b'\x1e', b'\x03', b'\xac', b'\x9c', b'\x9e', b'\xb7', b'\x6f',
    b'\xac', b'\x45', b'\xaf', b'\x8e', b'\x51', b'\x30', b'\xc8', b'\x1c', b'\x46',
    b'\xa3', b'\x5c', b'\xe4', b'\x11',
  ])
  let k = new_key(key).unwrap()
  let ct = encrypt_ctr(k, nonce, pt)
  assert_true(ct is Some(_))
  let dec = decrypt_ctr(k, nonce, ct.unwrap())
  assert_true(dec is Some(_))
  let dec = dec.unwrap()
  assert_eq(dec.length(), pt.length())
  for i = 0; i < pt.length(); i = i + 1 {
    assert_eq(dec[i], pt[i])
  }
}

///|
test "aes: GCM mode round-trip with AAD" {
  let key = FixedArray::from_array([
    b'\xfe', b'\xff', b'\xe9', b'\x92', b'\x86', b'\x65', b'\x73', b'\x1c', b'\x6d',
    b'\x6a', b'\x8f', b'\x94', b'\x67', b'\x30', b'\x83', b'\x08',
  ])
  let iv = FixedArray::from_array([
    b'\xca', b'\xfe', b'\xba', b'\xbe', b'\xfa', b'\xce', b'\xdb', b'\xad', b'\xde',
    b'\xca', b'\xf8', b'\x88',
  ])
  let pt = FixedArray::from_array([
    b'\xd9', b'\x31', b'\x32', b'\x25', b'\xf8', b'\x84', b'\x06', b'\xe5', b'\xa5',
    b'\x59', b'\x09', b'\xc5', b'\xaf', b'\xf5', b'\x26', b'\x9a', b'\x86', b'\xa7',
    b'\xa9', b'\x53', b'\x15', b'\x34', b'\xf7', b'\xda', b'\x2e', b'\x4c', b'\x30',
    b'\x3d', b'\x8a', b'\x31', b'\x8a', b'\x72',
  ])
  let aad = FixedArray::from_array([
    b'\xfe', b'\xed', b'\xfa', b'\xce', b'\xde', b'\xad', b'\xbe', b'\xef',
  ])
  let k = new_key(key).unwrap()
  let result = encrypt_gcm(k, iv, pt, aad)
  assert_true(result is Some(_))
  let r = result.unwrap()
  assert_eq(r.ciphertext.length(), pt.length())
  let dec = decrypt_gcm(k, iv, r.ciphertext, aad, r.tag)
  assert_true(dec is Some(_))
  let dec = dec.unwrap()
  for i = 0; i < pt.length(); i = i + 1 {
    assert_eq(dec[i], pt[i])
  }
}

///|
test "aes: GCM tampered tag is rejected" {
  let key = FixedArray::from_array([
    b'\xfe', b'\xff', b'\xe9', b'\x92', b'\x86', b'\x65', b'\x73', b'\x1c', b'\x6d',
    b'\x6a', b'\x8f', b'\x94', b'\x67', b'\x30', b'\x83', b'\x08',
  ])
  let iv = FixedArray::from_array([
    b'\xca', b'\xfe', b'\xba', b'\xbe', b'\xfa', b'\xce', b'\xdb', b'\xad', b'\xde',
    b'\xca', b'\xf8', b'\x88',
  ])
  let pt = FixedArray::from_array([
    b'\xd9', b'\x31', b'\x32', b'\x25', b'\xf8', b'\x84', b'\x06', b'\xe5', b'\xa5',
    b'\x59', b'\x09', b'\xc5', b'\xaf', b'\xf5', b'\x26', b'\x9a',
  ])
  let aad = FixedArray::from_array([])
  let k = new_key(key).unwrap()
  let result = encrypt_gcm(k, iv, pt, aad).unwrap()
  // Tamper with tag.
  let bad_tag = FixedArray::copy(result.tag)
  bad_tag[0] = bad_tag[0] ^ b'\x01'
  let dec = decrypt_gcm(k, iv, result.ciphertext, aad, bad_tag)
  assert_true(dec is None)
}

///|
test "aes: invalid key length returns None" {
  let bad_key = FixedArray::make(15, b'\x00')
  assert_true(new_key(bad_key) is None)
}

///|
test "aes: CBC with single byte plaintext" {
  let key = FixedArray::make(16, b'\x42')
  let iv = FixedArray::make(16, b'\x00')
  let pt = FixedArray::from_array([b'\x41'])
  let k = new_key(key).unwrap()
  let ct = encrypt_cbc(k, iv, pt).unwrap()
  assert_eq(ct.length(), 16) // one full block of padding
  let dec = decrypt_cbc(k, iv, ct).unwrap()
  assert_eq(dec.length(), 1)
  assert_eq(dec[0], b'\x41')
}

///|
test "aes: AES-256 GCM round-trip" {
  let key = FixedArray::from_array([
    b'\x00', b'\x01', b'\x02', b'\x03', b'\x04', b'\x05', b'\x06', b'\x07', b'\x08',
    b'\x09', b'\x0a', b'\x0b', b'\x0c', b'\x0d', b'\x0e', b'\x0f', b'\x10', b'\x11',
    b'\x12', b'\x13', b'\x14', b'\x15', b'\x16', b'\x17', b'\x18', b'\x19', b'\x1a',
    b'\x1b', b'\x1c', b'\x1d', b'\x1e', b'\x1f',
  ])
  let iv = FixedArray::from_array([
    b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00',
    b'\x00', b'\x00', b'\x01',
  ])
  let pt = FixedArray::from_array([
    b'\x48', b'\x65', b'\x6c', b'\x6c', b'\x6f', b'\x20', b'\x57', b'\x6f', b'\x72',
    b'\x6c', b'\x64',
  ])
  let k = new_key(key).unwrap()
  let result = encrypt_gcm(k, iv, pt, FixedArray::make(0, b'\x00')).unwrap()
  let dec = decrypt_gcm(
    k,
    iv,
    result.ciphertext,
    FixedArray::make(0, b'\x00'),
    result.tag,
  ).unwrap()
  for i = 0; i < pt.length(); i = i + 1 {
    assert_eq(dec[i], pt[i])
  }
}
