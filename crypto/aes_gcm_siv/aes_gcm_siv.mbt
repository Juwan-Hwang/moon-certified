///|
/// AES-GCM-SIV (RFC 8452) — Nonce-Misuse-Resistant AEAD
///
/// AES-GCM-SIV is a nonce-misuse-resistant variant of AES-GCM.
///
/// `proof-enabled` is `false`.
fn to_bytes(arr : Array[Int]) -> Bytes {
  let buf : Array[Byte] = []
  for v in arr {
    buf.push((v & 0xFF).to_byte())
  }
  Bytes::from_array(buf)
}

///|
fn to_fixed(arr : Array[Int]) -> FixedArray[Byte] {
  let fa = FixedArray::make(arr.length(), b'\x00')
  for i in 0..<arr.length() {
    fa[i] = (arr[i] & 0xFF).to_byte()
  }
  fa
}

///|
fn fixed_to_bytes(fa : FixedArray[Byte]) -> Bytes {
  let buf : Array[Byte] = []
  for i = 0; i < fa.length(); i = i + 1 {
    buf.push(fa[i])
  }
  Bytes::from_array(buf)
}

///|
fn bytes_to_fixed(b : Bytes) -> FixedArray[Byte] {
  let fa = FixedArray::make(b.length(), b'\x00')
  for i = 0; i < b.length(); i = i + 1 {
    fa[i] = b[i]
  }
  fa
}

///|
fn bytes_to_array(b : Bytes) -> Array[Int] {
  let a = Array::make(b.length(), 0)
  for i = 0; i < b.length(); i = i + 1 {
    a[i] = b[i].to_int()
  }
  a
}

///|
fn array_to_bytes(a : Array[Int]) -> Bytes {
  to_bytes(a)
}

///|
fn gf128_mul_le(a : Array[Int], b : Array[Int]) -> Array[Int] {
  let z = Array::make(16, 0)
  let v = Array::make(16, 0)
  for i = 0; i < 16; i = i + 1 {
    v[i] = b[i]
  }
  for i = 0; i < 128; i = i + 1 {
    let byte_idx = i / 8
    let bit_idx = i % 8
    if ((a[byte_idx] >> bit_idx) & 1) == 1 {
      for j = 0; j < 16; j = j + 1 {
        z[j] = z[j] ^ v[j]
      }
    }
    let carry = v[0] & 1
    for j = 0; j < 15; j = j + 1 {
      v[j] = (v[j] >> 1) | ((v[j + 1] & 1) << 7)
    }
    v[15] = v[15] >> 1
    if carry == 1 {
      v[15] = v[15] ^ 0xe1
    }
  }
  z
}

///|
fn polyval(key : Array[Int], blocks : Array[Int]) -> Array[Int] {
  let s = Array::make(16, 0)
  let n_blocks = blocks.length() / 16
  for i = 0; i < n_blocks; i = i + 1 {
    for j = 0; j < 16; j = j + 1 {
      s[j] = s[j] ^ blocks[i * 16 + j]
    }
    let result = gf128_mul_le(s, key)
    for j = 0; j < 16; j = j + 1 {
      s[j] = result[j]
    }
  }
  s
}

///|
fn aes_encrypt_block_bytes(key : @aes.AesKey, block : Bytes) -> Bytes {
  let fa = bytes_to_fixed(block)
  match @aes.encrypt_block(key, fa) {
    Some(result) => fixed_to_bytes(result)
    None => abort("AES-GCM-SIV: block encryption failed")
  }
}

///|
fn aes_new_key(key : Bytes) -> @aes.AesKey {
  match @aes.new_key(bytes_to_fixed(key)) {
    Some(k) => k
    None => abort("AES-GCM-SIV: invalid key length")
  }
}

///|
pub fn aes_gcm_siv_encrypt(
  key : Bytes,
  nonce : Bytes,
  aad : Bytes,
  plaintext : Bytes,
) -> Bytes {
  if nonce.length() != 12 {
    abort("AES-GCM-SIV: nonce must be 12 bytes")
  }
  let aes_key = aes_new_key(key)
  let ctr1 = Array::make(16, 0)
  for i = 0; i < 12; i = i + 1 {
    ctr1[i + 4] = nonce[i].to_int()
  }
  ctr1[15] = 1
  let ctr2 = Array::make(16, 0)
  for i = 0; i < 12; i = i + 1 {
    ctr2[i + 4] = nonce[i].to_int()
  }
  ctr2[15] = 2
  let auth_key = bytes_to_array(
    aes_encrypt_block_bytes(aes_key, array_to_bytes(ctr1)),
  )
  let enc_key = bytes_to_array(
    aes_encrypt_block_bytes(aes_key, array_to_bytes(ctr2)),
  )
  let aad_padded_len = (aad.length() + 15) / 16 * 16
  let pt_padded_len = (plaintext.length() + 15) / 16 * 16
  let tag_input = Array::make(aad_padded_len + pt_padded_len + 16, 0)
  for i = 0; i < aad.length(); i = i + 1 {
    tag_input[i] = aad[i].to_int()
  }
  let pt_offset = aad_padded_len
  for i = 0; i < plaintext.length(); i = i + 1 {
    tag_input[pt_offset + i] = plaintext[i].to_int()
  }
  let aad_bits = aad.length() * 8
  let pt_bits = plaintext.length() * 8
  let len_offset = aad_padded_len + pt_padded_len
  tag_input[len_offset + 0] = aad_bits & 0xFF
  tag_input[len_offset + 1] = (aad_bits >> 8) & 0xFF
  tag_input[len_offset + 2] = (aad_bits >> 16) & 0xFF
  tag_input[len_offset + 3] = (aad_bits >> 24) & 0xFF
  tag_input[len_offset + 8] = pt_bits & 0xFF
  tag_input[len_offset + 9] = (pt_bits >> 8) & 0xFF
  tag_input[len_offset + 10] = (pt_bits >> 16) & 0xFF
  tag_input[len_offset + 11] = (pt_bits >> 24) & 0xFF
  let polyval_result = polyval(auth_key, tag_input)
  let tag_input2 = Array::make(16, 0)
  for i = 0; i < 12; i = i + 1 {
    tag_input2[i] = polyval_result[i] ^ nonce[i].to_int()
  }
  tag_input2[15] = polyval_result[15] ^ 0x80
  let tag = bytes_to_array(
    aes_encrypt_block_bytes(aes_key, array_to_bytes(tag_input2)),
  )
  let result = Array::make(plaintext.length() + 16, 0)
  for i = 0; i < 16; i = i + 1 {
    result[plaintext.length() + i] = tag[i]
  }
  let enc_aes_key = aes_new_key(array_to_bytes(enc_key))
  let counter = Array::make(16, 0)
  for i = 0; i < 12; i = i + 1 {
    counter[i] = tag[i]
  }
  counter[15] = 2
  let n_blocks = (plaintext.length() + 15) / 16
  for block_idx = 0; block_idx < n_blocks; block_idx = block_idx + 1 {
    let keystream = bytes_to_array(
      aes_encrypt_block_bytes(enc_aes_key, array_to_bytes(counter)),
    )
    let start = block_idx * 16
    let block_end = start + 16
    let end = if block_end <= plaintext.length() {
      block_end
    } else {
      plaintext.length()
    }
    for i = start; i < end; i = i + 1 {
      result[i] = plaintext[i].to_int() ^ keystream[i - start]
    }
    counter[15] = counter[15] + 1
    if counter[15] == 0 {
      counter[14] = counter[14] + 1
      if counter[14] == 0 {
        counter[13] = counter[13] + 1
      }
    }
  }
  array_to_bytes(result)
}

///|
pub fn aes_gcm_siv_decrypt(
  key : Bytes,
  nonce : Bytes,
  aad : Bytes,
  ciphertext_with_tag : Bytes,
) -> Bytes? {
  if nonce.length() != 12 {
    abort("AES-GCM-SIV: nonce must be 12 bytes")
  }
  let total_len = ciphertext_with_tag.length()
  if total_len < 16 {
    return None
  }
  let ct_len = total_len - 16
  let aes_key = aes_new_key(key)
  let tag = Array::make(16, 0)
  for i = 0; i < 16; i = i + 1 {
    tag[i] = ciphertext_with_tag[ct_len + i].to_int()
  }
  let ctr1 = Array::make(16, 0)
  for i = 0; i < 12; i = i + 1 {
    ctr1[i + 4] = nonce[i].to_int()
  }
  ctr1[15] = 1
  let ctr2 = Array::make(16, 0)
  for i = 0; i < 12; i = i + 1 {
    ctr2[i + 4] = nonce[i].to_int()
  }
  ctr2[15] = 2
  let auth_key = bytes_to_array(
    aes_encrypt_block_bytes(aes_key, array_to_bytes(ctr1)),
  )
  let enc_key = bytes_to_array(
    aes_encrypt_block_bytes(aes_key, array_to_bytes(ctr2)),
  )
  let enc_aes_key = aes_new_key(array_to_bytes(enc_key))
  let plaintext = Array::make(ct_len, 0)
  let counter = Array::make(16, 0)
  for i = 0; i < 12; i = i + 1 {
    counter[i] = tag[i]
  }
  counter[15] = 2
  let n_blocks = (ct_len + 15) / 16
  for block_idx = 0; block_idx < n_blocks; block_idx = block_idx + 1 {
    let keystream = bytes_to_array(
      aes_encrypt_block_bytes(enc_aes_key, array_to_bytes(counter)),
    )
    let start = block_idx * 16
    let block_end = start + 16
    let end = if block_end <= ct_len { block_end } else { ct_len }
    for i = start; i < end; i = i + 1 {
      plaintext[i] = ciphertext_with_tag[i].to_int() ^ keystream[i - start]
    }
    counter[15] = counter[15] + 1
    if counter[15] == 0 {
      counter[14] = counter[14] + 1
    }
  }
  let aad_padded_len = (aad.length() + 15) / 16 * 16
  let pt_padded_len = (ct_len + 15) / 16 * 16
  let tag_input = Array::make(aad_padded_len + pt_padded_len + 16, 0)
  for i = 0; i < aad.length(); i = i + 1 {
    tag_input[i] = aad[i].to_int()
  }
  let pt_offset = aad_padded_len
  for i = 0; i < ct_len; i = i + 1 {
    tag_input[pt_offset + i] = plaintext[i]
  }
  let aad_bits = aad.length() * 8
  let pt_bits = ct_len * 8
  let len_offset = aad_padded_len + pt_padded_len
  tag_input[len_offset + 0] = aad_bits & 0xFF
  tag_input[len_offset + 1] = (aad_bits >> 8) & 0xFF
  tag_input[len_offset + 2] = (aad_bits >> 16) & 0xFF
  tag_input[len_offset + 3] = (aad_bits >> 24) & 0xFF
  tag_input[len_offset + 8] = pt_bits & 0xFF
  tag_input[len_offset + 9] = (pt_bits >> 8) & 0xFF
  tag_input[len_offset + 10] = (pt_bits >> 16) & 0xFF
  tag_input[len_offset + 11] = (pt_bits >> 24) & 0xFF
  let polyval_result = polyval(auth_key, tag_input)
  let expected_tag_input = Array::make(16, 0)
  for i = 0; i < 12; i = i + 1 {
    expected_tag_input[i] = polyval_result[i] ^ nonce[i].to_int()
  }
  expected_tag_input[15] = polyval_result[15] ^ 0x80
  let expected_tag = bytes_to_array(
    aes_encrypt_block_bytes(aes_key, array_to_bytes(expected_tag_input)),
  )
  let mut diff = 0
  for i = 0; i < 16; i = i + 1 {
    diff = diff | (tag[i] ^ expected_tag[i])
  }
  if diff != 0 {
    return None
  }
  Some(array_to_bytes(plaintext))
}
