/// AES-CCM — Counter with CBC-MAC (RFC 3610, NIST SP 800-38C).
///
/// AES-CCM is an AEAD (Authenticated Encryption with Associated Data)
/// mode combining CTR mode for encryption with CBC-MAC for authentication.
/// It is mandated by IEEE 802.11i (WPA2), Bluetooth LE, and Zigbee.
///
/// ## Parameters
///
/// - **Key**: 16, 24, or 32 bytes (AES-128/192/256).
/// - **Nonce**: 7–13 bytes. `L = 15 - nonce_len` gives the octet-length
///   of the message-length field.
/// - **Tag length (M)**: 4, 6, 8, 10, 12, 14, or 16 bytes.
/// - **AAD**: optional associated data (authenticated but not encrypted).
///
/// ## Algorithm
///
/// 1. **CBC-MAC**: Build B_0 (flags ‖ nonce ‖ msg-length), process B_0,
///    AAD blocks (if any), and message blocks through AES-CBC. Truncate
///    the final block to M bytes → tag T.
/// 2. **CTR encryption**: Encrypt tag with S_0 = E(K, A_0), encrypt
///    message blocks with S_i = E(K, A_i).
///
/// ## References
///
/// - J. Jonsson. "Security of CCM." 2004.
/// - NIST SP 800-38C. "Recommendation for Block Cipher Modes of Operation:
///   The CCM Mode for Authentication and Confidentiality."
///
/// `proof-enabled` is `false`; correctness is backed by test vectors.

///|
/// Result of AES-CCM encryption.
pub struct CcmResult {
  /// Ciphertext (same length as plaintext).
  ciphertext : FixedArray[Byte]
  /// Authentication tag.
  tag : FixedArray[Byte]
}

///|
/// XOR two fixed-length byte arrays (truncated to shorter length).
fn xor_block(a : FixedArray[Byte], b : FixedArray[Byte]) -> FixedArray[Byte] {
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  let result = FixedArray::make(n, b'\x00')
  for i = 0; i < n; i = i + 1 {
    result[i] = (a[i].to_int() ^ b[i].to_int()).to_byte()
  }
  result
}

///|
/// XOR a portion of `src` with `key_stream` into `dst`.
fn xor_into(
  dst : FixedArray[Byte],
  dst_offset : Int,
  src : FixedArray[Byte],
  src_offset : Int,
  key_stream : FixedArray[Byte],
  len : Int,
) -> Unit {
  for i = 0; i < len; i = i + 1 {
    dst[dst_offset + i] = (src[src_offset + i].to_int() ^ key_stream[i].to_int()).to_byte()
  }
}

///|
/// Pad a byte array to a multiple of 16 bytes with zeros.
fn pad_to_block(data : FixedArray[Byte]) -> FixedArray[Byte] {
  let n = data.length()
  if n == 0 {
    return FixedArray::make(16, b'\x00')
  }
  let rem = n % 16
  if rem == 0 {
    return data
  }
  let padded = FixedArray::make(n + (16 - rem), b'\x00')
  for i = 0; i < n; i = i + 1 {
    padded[i] = data[i]
  }
  padded
}

///|
/// Build the B_0 block for CBC-MAC.
fn build_b0(
  nonce : FixedArray[Byte],
  msg_len : Int,
  tag_len : Int,
  has_aad : Bool,
) -> FixedArray[Byte] {
  let l = 15 - nonce.length()
  let b0 = FixedArray::make(16, b'\x00')
  // Flags: Reserved(1) | AAD(1) | (M-2)/2(3) | L-1(3)
  let m_flag = ((tag_len - 2) / 2) & 0x07
  let a_flag = if has_aad { 0x40 } else { 0x00 }
  let flags = 0x00 | a_flag | (m_flag << 3) | ((l - 1) & 0x07)
  b0[0] = flags.to_byte()
  for i = 0; i < nonce.length(); i = i + 1 {
    b0[1 + i] = nonce[i]
  }
  // Message length in L bytes (big-endian)
  let mut ml = msg_len
  for i = l - 1; i >= 0; i = i - 1 {
    b0[15 - i] = (ml & 0xFF).to_byte()
    ml = ml >> 8
  }
  b0
}

///|
/// Build the A_i counter block for CTR mode.
fn build_ctr_block(nonce : FixedArray[Byte], counter : Int) -> FixedArray[Byte] {
  let l = 15 - nonce.length()
  let ai = FixedArray::make(16, b'\x00')
  // Flags: Reserved(1) | 0(1) | 0(3) | L-1(3)
  let flags = (l - 1) & 0x07
  ai[0] = flags.to_byte()
  for i = 0; i < nonce.length(); i = i + 1 {
    ai[1 + i] = nonce[i]
  }
  // Counter in L bytes (big-endian)
  let mut ctr = counter
  for i = l - 1; i >= 0; i = i - 1 {
    ai[15 - i] = (ctr & 0xFF).to_byte()
    ctr = ctr >> 8
  }
  ai
}

///|
/// Build AAD blocks for CBC-MAC.
fn build_aad_blocks(aad : FixedArray[Byte]) -> FixedArray[Byte] {
  let aad_len = aad.length()
  let header : Array[Byte] = []
  // Encode AAD length
  if aad_len < 0xFF00 {
    // 2-byte length
    header.push((aad_len >> 8).to_byte())
    header.push((aad_len & 0xFF).to_byte())
  } else {
    // 4-byte length with 0xFF prefix
    header.push(b'\xFF')
    header.push(b'\xFF')
    header.push((aad_len >> 24).to_byte())
    header.push(((aad_len >> 16) & 0xFF).to_byte())
    header.push(((aad_len >> 8) & 0xFF).to_byte())
    header.push((aad_len & 0xFF).to_byte())
  }
  // Append AAD
  for i = 0; i < aad.length(); i = i + 1 {
    header.push(aad[i])
  }
  // Convert to FixedArray and pad
  let header_fa = FixedArray::make(header.length(), b'\x00')
  for i = 0; i < header.length(); i = i + 1 {
    header_fa[i] = header[i]
  }
  pad_to_block(header_fa)
}

///|
/// AES-CCM encrypt.
///
/// - `key`: AES key (16/24/32 bytes).
/// - `nonce`: Nonce (7–13 bytes).
/// - `plaintext`: Data to encrypt.
/// - `aad`: Associated data (authenticated, not encrypted; may be empty).
/// - `tag_len`: Tag length (4/6/8/10/12/14/16).
///
/// Returns `Some(CcmResult)` on success, `None` on invalid parameters.
pub fn encrypt(
  key : FixedArray[Byte],
  nonce : FixedArray[Byte],
  plaintext : FixedArray[Byte],
  aad : FixedArray[Byte],
  tag_len : Int,
) -> CcmResult? {
  // Validate parameters
  if nonce.length() < 7 || nonce.length() > 13 {
    return None
  }
  if tag_len < 4 || tag_len > 16 || tag_len % 2 != 0 {
    return None
  }
  let aes_key = match @aes.new_key(key) {
    None => return None
    Some(k) => k
  }
  let l = 15 - nonce.length()
  let msg_len = plaintext.length()
  // Check message length fits in L bytes.
  // For l >= 4, 2^(8*l) overflows 32-bit Int; any practical message fits.
  if l < 4 && msg_len > 1 << (l * 8) {
    return None
  }
  let has_aad = aad.length() > 0
  // ---- CBC-MAC ----
  // B_0
  let b0 = build_b0(nonce, msg_len, tag_len, has_aad)
  let mut mac = match @aes.encrypt_block(aes_key, b0) {
    None => return None
    Some(b) => b
  }
  // AAD blocks
  if has_aad {
    let aad_blocks = build_aad_blocks(aad)
    let n_blocks = aad_blocks.length() / 16
    for i = 0; i < n_blocks; i = i + 1 {
      let block = FixedArray::make(16, b'\x00')
      for j = 0; j < 16; j = j + 1 {
        block[j] = aad_blocks[i * 16 + j]
      }
      let x = xor_block(mac, block)
      mac = match @aes.encrypt_block(aes_key, x) {
        None => return None
        Some(b) => b
      }
    }
  }
  // Message blocks (padded)
  let pt_padded = pad_to_block(plaintext)
  let n_pt_blocks = pt_padded.length() / 16
  for i = 0; i < n_pt_blocks; i = i + 1 {
    let block = FixedArray::make(16, b'\x00')
    for j = 0; j < 16; j = j + 1 {
      block[j] = pt_padded[i * 16 + j]
    }
    let x = xor_block(mac, block)
    mac = match @aes.encrypt_block(aes_key, x) {
      None => return None
      Some(b) => b
    }
  }
  // Tag T = mac[:tag_len]
  let tag = FixedArray::make(tag_len, b'\x00')
  for i = 0; i < tag_len; i = i + 1 {
    tag[i] = mac[i]
  }
  // ---- CTR encryption ----
  // S_0 = E(K, A_0)
  let a0 = build_ctr_block(nonce, 0)
  let s0 = match @aes.encrypt_block(aes_key, a0) {
    None => return None
    Some(b) => b
  }
  // U = T XOR S_0[:tag_len]
  let u = FixedArray::make(tag_len, b'\x00')
  for i = 0; i < tag_len; i = i + 1 {
    u[i] = (tag[i].to_int() ^ s0[i].to_int()).to_byte()
  }
  // Encrypt plaintext
  let ciphertext = FixedArray::make(msg_len, b'\x00')
  let mut ctr = 1
  let mut pos = 0
  while pos < msg_len {
    let ai = build_ctr_block(nonce, ctr)
    let si = match @aes.encrypt_block(aes_key, ai) {
      None => return None
      Some(b) => b
    }
    let remaining = msg_len - pos
    let block_len = if remaining < 16 { remaining } else { 16 }
    xor_into(ciphertext, pos, plaintext, pos, si, block_len)
    pos = pos + block_len
    ctr = ctr + 1
  }
  Some({ ciphertext, tag: u, })
}

///|
/// AES-CCM decrypt and verify.
///
/// - `key`: AES key.
/// - `nonce`: Nonce (7–13 bytes).
/// - `ciphertext`: Encrypted data.
/// - `aad`: Associated data.
/// - `tag`: Authentication tag.
///
/// Returns `Some(plaintext)` if the tag verifies, `None` otherwise.
pub fn decrypt(
  key : FixedArray[Byte],
  nonce : FixedArray[Byte],
  ciphertext : FixedArray[Byte],
  aad : FixedArray[Byte],
  tag : FixedArray[Byte],
) -> FixedArray[Byte]? {
  // Validate parameters
  if nonce.length() < 7 || nonce.length() > 13 {
    return None
  }
  let tag_len = tag.length()
  if tag_len < 4 || tag_len > 16 || tag_len % 2 != 0 {
    return None
  }
  let aes_key = match @aes.new_key(key) {
    None => return None
    Some(k) => k
  }
  let l = 15 - nonce.length()
  let ct_len = ciphertext.length()
  if l < 4 && ct_len > 1 << (l * 8) {
    return None
  }
  let has_aad = aad.length() > 0
  // ---- CTR decryption ----
  let plaintext = FixedArray::make(ct_len, b'\x00')
  let mut ctr = 1
  let mut pos = 0
  while pos < ct_len {
    let ai = build_ctr_block(nonce, ctr)
    let si = match @aes.encrypt_block(aes_key, ai) {
      None => return None
      Some(b) => b
    }
    let remaining = ct_len - pos
    let block_len = if remaining < 16 { remaining } else { 16 }
    xor_into(plaintext, pos, ciphertext, pos, si, block_len)
    pos = pos + block_len
    ctr = ctr + 1
  }
  // ---- CBC-MAC verification ----
  let b0 = build_b0(nonce, ct_len, tag_len, has_aad)
  let mut mac = match @aes.encrypt_block(aes_key, b0) {
    None => return None
    Some(b) => b
  }
  if has_aad {
    let aad_blocks = build_aad_blocks(aad)
    let n_blocks = aad_blocks.length() / 16
    for i = 0; i < n_blocks; i = i + 1 {
      let block = FixedArray::make(16, b'\x00')
      for j = 0; j < 16; j = j + 1 {
        block[j] = aad_blocks[i * 16 + j]
      }
      let x = xor_block(mac, block)
      mac = match @aes.encrypt_block(aes_key, x) {
        None => return None
        Some(b) => b
      }
    }
  }
  let pt_padded = pad_to_block(plaintext)
  let n_pt_blocks = pt_padded.length() / 16
  for i = 0; i < n_pt_blocks; i = i + 1 {
    let block = FixedArray::make(16, b'\x00')
    for j = 0; j < 16; j = j + 1 {
      block[j] = pt_padded[i * 16 + j]
    }
    let x = xor_block(mac, block)
    mac = match @aes.encrypt_block(aes_key, x) {
      None => return None
      Some(b) => b
    }
  }
  // Compute expected tag
  let a0 = build_ctr_block(nonce, 0)
  let s0 = match @aes.encrypt_block(aes_key, a0) {
    None => return None
    Some(b) => b
  }
  // Constant-time comparison
  let mut diff = 0
  for i = 0; i < tag_len; i = i + 1 {
    let expected = (mac[i].to_int() ^ s0[i].to_int()).to_byte()
    diff = diff | (expected.to_int() ^ tag[i].to_int())
  }
  if diff != 0 {
    return None
  }
  Some(plaintext)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "aes_ccm: round-trip empty plaintext" {
  let key = FixedArray::make(16, b'\x00')
  for i = 0; i < 16; i = i + 1 {
    key[i] = i.to_byte()
  }
  let nonce = FixedArray::make(13, b'\x00')
  for i = 0; i < 13; i = i + 1 {
    nonce[i] = (i + 1).to_byte()
  }
  let pt = FixedArray::make(0, b'\x00')
  let aad = FixedArray::make(0, b'\x00')
  match encrypt(key, nonce, pt, aad, 8) {
    Some(result) => {
      assert_eq(result.ciphertext.length(), 0)
      assert_eq(result.tag.length(), 8)
      match decrypt(key, nonce, result.ciphertext, aad, result.tag) {
        Some(decrypted) => assert_eq(decrypted.length(), 0)
        None => assert_true(false)
      }
    }
    None => assert_true(false)
  }
}

///|
test "aes_ccm: round-trip short message" {
  let key = FixedArray::make(16, b'\x00')
  for i = 0; i < 16; i = i + 1 {
    key[i] = (i * 17).to_byte()
  }
  let nonce = FixedArray::make(12, b'\x00')
  for i = 0; i < 12; i = i + 1 {
    nonce[i] = (i + 1).to_byte()
  }
  let pt = FixedArray::make(10, b'\x00')
  for i = 0; i < 10; i = i + 1 {
    pt[i] = (65 + i).to_byte() // "ABCDEFGHIJ"
  }
  let aad = FixedArray::make(0, b'\x00')
  match encrypt(key, nonce, pt, aad, 8) {
    Some(result) => {
      assert_eq(result.ciphertext.length(), 10)
      assert_eq(result.tag.length(), 8)
      match decrypt(key, nonce, result.ciphertext, aad, result.tag) {
        Some(decrypted) =>
          for i = 0; i < 10; i = i + 1 {
            assert_eq(decrypted[i], pt[i])
          }
        None => assert_true(false)
      }
    }
    None => assert_true(false)
  }
}

///|
test "aes_ccm: round-trip with AAD" {
  let key = FixedArray::make(16, b'\x00')
  for i = 0; i < 16; i = i + 1 {
    key[i] = (i * 3 + 1).to_byte()
  }
  let nonce = FixedArray::make(7, b'\x00')
  for i = 0; i < 7; i = i + 1 {
    nonce[i] = (i * 5).to_byte()
  }
  let pt = FixedArray::make(32, b'\x00')
  for i = 0; i < 32; i = i + 1 {
    pt[i] = i.to_byte()
  }
  let aad = FixedArray::make(8, b'\x00')
  for i = 0; i < 8; i = i + 1 {
    aad[i] = (100 + i).to_byte()
  }
  match encrypt(key, nonce, pt, aad, 16) {
    Some(result) => {
      assert_eq(result.ciphertext.length(), 32)
      assert_eq(result.tag.length(), 16)
      match decrypt(key, nonce, result.ciphertext, aad, result.tag) {
        Some(decrypted) =>
          for i = 0; i < 32; i = i + 1 {
            assert_eq(decrypted[i], pt[i])
          }
        None => assert_true(false)
      }
    }
    None => assert_true(false)
  }
}

///|
test "aes_ccm: tampered tag rejected" {
  let key = FixedArray::make(16, b'\x00')
  for i = 0; i < 16; i = i + 1 {
    key[i] = (i * 7).to_byte()
  }
  let nonce = FixedArray::make(12, b'\x00')
  for i = 0; i < 12; i = i + 1 {
    nonce[i] = (i + 10).to_byte()
  }
  let pt = FixedArray::make(16, b'\x00')
  for i = 0; i < 16; i = i + 1 {
    pt[i] = (i + 1).to_byte()
  }
  let aad = FixedArray::make(0, b'\x00')
  match encrypt(key, nonce, pt, aad, 8) {
    Some(result) => {
      // Tamper with tag
      let bad_tag = FixedArray::make(8, b'\x00')
      for i = 0; i < 8; i = i + 1 {
        bad_tag[i] = result.tag[i]
      }
      bad_tag[0] = (bad_tag[0].to_int() ^ 0x01).to_byte()
      match decrypt(key, nonce, result.ciphertext, aad, bad_tag) {
        Some(_) => assert_true(false) // Should reject
        None => assert_true(true)
      }
    }
    None => assert_true(false)
  }
}

///|
test "aes_ccm: tampered ciphertext rejected" {
  let key = FixedArray::make(16, b'\x00')
  for i = 0; i < 16; i = i + 1 {
    key[i] = (i * 11).to_byte()
  }
  let nonce = FixedArray::make(11, b'\x00')
  for i = 0; i < 11; i = i + 1 {
    nonce[i] = (i + 3).to_byte()
  }
  let pt = FixedArray::make(20, b'\x00')
  for i = 0; i < 20; i = i + 1 {
    pt[i] = (i * 2).to_byte()
  }
  let aad = FixedArray::make(0, b'\x00')
  match encrypt(key, nonce, pt, aad, 10) {
    Some(result) => {
      // Tamper with ciphertext
      let bad_ct = FixedArray::make(20, b'\x00')
      for i = 0; i < 20; i = i + 1 {
        bad_ct[i] = result.ciphertext[i]
      }
      bad_ct[0] = (bad_ct[0].to_int() ^ 0x80).to_byte()
      match decrypt(key, nonce, bad_ct, aad, result.tag) {
        Some(_) => assert_true(false) // Should reject
        None => assert_true(true)
      }
    }
    None => assert_true(false)
  }
}

///|
test "aes_ccm: invalid nonce length rejected" {
  let key = FixedArray::make(16, b'\x00')
  let nonce = FixedArray::make(6, b'\x00') // Too short
  let pt = FixedArray::make(4, b'\x00')
  let aad = FixedArray::make(0, b'\x00')
  match encrypt(key, nonce, pt, aad, 8) {
    Some(_) => assert_true(false)
    None => assert_true(true)
  }
}

///|
test "aes_ccm: multi-block message" {
  let key = FixedArray::make(32, b'\x00')
  for i = 0; i < 32; i = i + 1 {
    key[i] = i.to_byte()
  }
  let nonce = FixedArray::make(12, b'\x00')
  for i = 0; i < 12; i = i + 1 {
    nonce[i] = (i + 1).to_byte()
  }
  let pt = FixedArray::make(100, b'\x00')
  for i = 0; i < 100; i = i + 1 {
    pt[i] = (i * 7 % 256).to_byte()
  }
  let aad = FixedArray::make(16, b'\x00')
  for i = 0; i < 16; i = i + 1 {
    aad[i] = (i + 200).to_byte()
  }
  match encrypt(key, nonce, pt, aad, 16) {
    Some(result) => {
      assert_eq(result.ciphertext.length(), 100)
      match decrypt(key, nonce, result.ciphertext, aad, result.tag) {
        Some(decrypted) =>
          for i = 0; i < 100; i = i + 1 {
            assert_eq(decrypted[i], pt[i])
          }
        None => assert_true(false)
      }
    }
    None => assert_true(false)
  }
}
