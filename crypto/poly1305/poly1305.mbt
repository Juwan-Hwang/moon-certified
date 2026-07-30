/// Poly1305 — One-time authenticator (RFC 8439).
///
/// Poly1305 is a fast, one-time MAC designed by Daniel J. Bernstein. It is
/// used in TLS 1.3 and the ChaCha20-Poly1305 AEAD construction (RFC 8439).
///
/// Not formally verified. Correctness is ensured by RFC 8439 test vectors.

// ---------------------------------------------------------------------------
// 130-bit arithmetic (5 × 26-bit limbs, stored as UInt64)
// ---------------------------------------------------------------------------

///|
/// Mask for 26 bits.
const MASK26 : UInt64 = 0x03FFFFFFUL

///|
/// A 130-bit integer: 5 limbs of 26 bits each, stored as UInt64.
priv struct U130 {
  mut l0 : UInt64
  mut l1 : UInt64
  mut l2 : UInt64
  mut l3 : UInt64
  mut l4 : UInt64
}

///|
fn u130_zero() -> U130 {
  { l0: 0UL, l1: 0UL, l2: 0UL, l3: 0UL, l4: 0UL }
}

///|
/// Add `b` into `a` (a += b), with carry propagation.
fn u130_add(a : U130, b : U130) -> Unit {
  a.l0 = a.l0 + b.l0
  a.l1 = a.l1 + b.l1 + (a.l0 >> 26)
  a.l0 = a.l0 & MASK26
  a.l2 = a.l2 + b.l2 + (a.l1 >> 26)
  a.l1 = a.l1 & MASK26
  a.l3 = a.l3 + b.l3 + (a.l2 >> 26)
  a.l2 = a.l2 & MASK26
  a.l4 = a.l4 + b.l4 + (a.l3 >> 26)
  a.l3 = a.l3 & MASK26
}

///|
/// Multiply a by r (both 5×26-bit), reduce mod 2^130−5.
/// Result stored in a (a = a × r mod p).
fn u130_mulmod(a : U130, r : U130) -> Unit {
  let r0 = r.l0
  let r1 = r.l1
  let r2 = r.l2
  let r3 = r.l3
  let r4 = r.l4
  let a0 = a.l0
  let a1 = a.l1
  let a2 = a.l2
  let a3 = a.l3
  let a4 = a.l4

  // Schoolbook multiplication: 5×5 = 25 partial products.
  let p0 = a0 * r0
  let p1 = a0 * r1 + a1 * r0
  let p2 = a0 * r2 + a1 * r1 + a2 * r0
  let p3 = a0 * r3 + a1 * r2 + a2 * r1 + a3 * r0
  let p4 = a0 * r4 + a1 * r3 + a2 * r2 + a3 * r1 + a4 * r0
  let p5 = a1 * r4 + a2 * r3 + a3 * r2 + a4 * r1
  let p6 = a2 * r4 + a3 * r3 + a4 * r2
  let p7 = a3 * r4 + a4 * r3
  let p8 = a4 * r4

  // Reduce: 2^130 ≡ 5 (mod p), so high limbs × 5 are added to low.
  let h0 = p0 + p5 * 5UL
  let h1 = p1 + p6 * 5UL
  let h2 = p2 + p7 * 5UL
  let h3 = p3 + p8 * 5UL
  let h4 = p4

  // Carry propagation.
  let c0 = h0 >> 26
  let nl0 = h0 & MASK26
  let c1 = (h1 + c0) >> 26
  let nl1 = (h1 + c0) & MASK26
  let c2 = (h2 + c1) >> 26
  let nl2 = (h2 + c1) & MASK26
  let c3 = (h3 + c2) >> 26
  let nl3 = (h3 + c2) & MASK26
  let c4 = (h4 + c3) >> 26
  let nl4 = (h4 + c3) & MASK26

  // Final carry: c4 × 5 goes back to l0.
  let nl0b = nl0 + c4 * 5UL
  let carry = nl0b >> 26
  a.l0 = nl0b & MASK26
  a.l1 = nl1 + carry
  a.l2 = nl2
  a.l3 = nl3
  a.l4 = nl4
  // Propagate remaining carry.
  if a.l1 >= 1UL << 26 {
    let c = a.l1 >> 26
    a.l1 = a.l1 & MASK26
    a.l2 = a.l2 + c
    if a.l2 >= 1UL << 26 {
      let c2 = a.l2 >> 26
      a.l2 = a.l2 & MASK26
      a.l3 = a.l3 + c2
      if a.l3 >= 1UL << 26 {
        let c3 = a.l3 >> 26
        a.l3 = a.l3 & MASK26
        a.l4 = a.l4 + c3
      }
    }
  }
}

///|
/// Add the 128-bit `s` (16 bytes LE) to `a`, reduce mod 2^128.
fn u130_add_s(a : U130, s_bytes : Bytes) -> Unit {
  // Load s as two 64-bit halves, split into 5 × 26-bit limbs.
  let mut s_lo : UInt64 = 0UL
  for i = 0; i < 8; i = i + 1 {
    s_lo = s_lo.lor(s_bytes[i].to_uint64() << (i * 8))
  }
  let mut s_hi : UInt64 = 0UL
  for i = 0; i < 8; i = i + 1 {
    s_hi = s_hi.lor(s_bytes[8 + i].to_uint64() << (i * 8))
  }
  let s0 = s_lo & MASK26
  let s1 = (s_lo >> 26) & MASK26
  let s2 = (s_lo >> 52) & MASK26
  let s2b = (s_hi << 12) & MASK26
  let s2 = s2.lor(s2b)
  let s3 = (s_hi >> 14) & MASK26
  let s4 = (s_hi >> 40) & MASK26
  a.l0 = a.l0 + s0
  a.l1 = a.l1 + s1 + (a.l0 >> 26)
  a.l0 = a.l0 & MASK26
  a.l2 = a.l2 + s2 + (a.l1 >> 26)
  a.l1 = a.l1 & MASK26
  a.l3 = a.l3 + s3 + (a.l2 >> 26)
  a.l2 = a.l2 & MASK26
  a.l4 = a.l4 + s4 + (a.l3 >> 26)
  a.l3 = a.l3 & MASK26
  // Reduce mod 2^128: mask l4 to 24 bits (bits 104–127).
  a.l4 = a.l4 & 0x00FFFFFFUL
}

///|
/// Convert U130 to 16 bytes (little-endian, low 128 bits).
fn u130_to_bytes(a : U130) -> Bytes {
  let buf : Array[Byte] = Array::make(16, b'\x00')
  let v0 = a.l0
  let v1 = a.l1
  let v2 = a.l2
  let v3 = a.l3
  let v4 = a.l4
  // Byte 0-3: v0 | (v1 << 26)
  let b03 = v0.lor(v1 << 26)
  buf[0] = b03.to_byte()
  buf[1] = (b03 >> 8).to_byte()
  buf[2] = (b03 >> 16).to_byte()
  buf[3] = (b03 >> 24).to_byte()
  // Byte 4-7: (v1 >> 6) | (v2 << 20)
  let b47 = (v1 >> 6).lor(v2 << 20)
  buf[4] = b47.to_byte()
  buf[5] = (b47 >> 8).to_byte()
  buf[6] = (b47 >> 16).to_byte()
  buf[7] = (b47 >> 24).to_byte()
  // Byte 8-11: (v2 >> 12) | (v3 << 14)
  let b811 = (v2 >> 12).lor(v3 << 14)
  buf[8] = b811.to_byte()
  buf[9] = (b811 >> 8).to_byte()
  buf[10] = (b811 >> 16).to_byte()
  buf[11] = (b811 >> 24).to_byte()
  // Byte 12-15: (v3 >> 18) | (v4 << 8)
  let b1215 = (v3 >> 18).lor(v4 << 8)
  buf[12] = b1215.to_byte()
  buf[13] = (b1215 >> 8).to_byte()
  buf[14] = (b1215 >> 16).to_byte()
  buf[15] = (b1215 >> 24).to_byte()
  Bytes::from_array(buf)
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

///|
/// Load a 16-byte LE value into U130 (for r).
fn u130_from_le16(data : FixedArray[Byte]) -> U130 {
  let mut v : UInt64 = 0UL
  for i = 0; i < 8; i = i + 1 {
    v = v.lor(data[i].to_uint64() << (i * 8))
  }
  let mut v2 : UInt64 = 0UL
  for i = 0; i < 8; i = i + 1 {
    v2 = v2.lor(data[8 + i].to_uint64() << (i * 8))
  }
  let l0 = v & MASK26
  let l1 = (v >> 26) & MASK26
  let l2 = (v >> 52).lor(v2 << 12) & MASK26
  let l3 = (v2 >> 14) & MASK26
  let l4 = (v2 >> 40) & MASK26
  { l0, l1, l2, l3, l4 }
}

///|
/// Load a LE block (up to 16 bytes) + appended 0x01 into U130.
fn u130_from_le_block(data : Bytes, offset : Int, len : Int) -> U130 {
  let mut lo : UInt64 = 0UL
  let mut hi : UInt64 = 0UL
  let first = if len < 8 { len } else { 8 }
  for i = 0; i < first; i = i + 1 {
    lo = lo.lor(data[offset + i].to_uint64() << (i * 8))
  }
  if len > 8 {
    for i = 0; i < len - 8; i = i + 1 {
      hi = hi.lor(data[offset + 8 + i].to_uint64() << (i * 8))
    }
  }
  // Combine into 5 × 26-bit limbs.
  let l0 = lo & MASK26
  let l1 = (lo >> 26) & MASK26
  let l2 = (lo >> 52).lor(hi << 12) & MASK26
  let l3 = (hi >> 14) & MASK26
  let l4 = (hi >> 40) & MASK26
  let result = { l0, l1, l2, l3, l4 }
  // Add the 0x01 bit at position len*8 (the "high bit" of the block).
  let bit_pos = len * 8
  let limb_idx = bit_pos / 26
  let bit_in_limb = bit_pos % 26
  let one_bit = 1UL << bit_in_limb
  match limb_idx {
    0 => result.l0 = result.l0 + one_bit
    1 => result.l1 = result.l1 + one_bit
    2 => result.l2 = result.l2 + one_bit
    3 => result.l3 = result.l3 + one_bit
    4 => result.l4 = result.l4 + one_bit
    _ => () // Unreachable: len ∈ [1,16] → bit_pos ∈ [8,128] → limb_idx ∈ [0,4]
  }
  result
}

///|
/// Compute the Poly1305 tag for `data` using a 32-byte `key`.
///
/// Key = r(16 bytes) || s(16 bytes). r is clamped per RFC 8439.
/// Returns `None` if key is not exactly 32 bytes.
pub fn poly1305(key : Bytes, data : Bytes) -> Bytes? {
  if key.length() != 32 {
    return None
  }
  // Clamp r.
  let r_bytes : FixedArray[Byte] = FixedArray::make(16, b'\x00')
  for i = 0; i < 16; i = i + 1 {
    r_bytes[i] = key[i]
  }
  r_bytes[3] = r_bytes[3] & 0x0F
  r_bytes[7] = r_bytes[7] & 0x0F
  r_bytes[11] = r_bytes[11] & 0x0F
  r_bytes[15] = r_bytes[15] & 0x0F
  r_bytes[4] = r_bytes[4] & 0xFC
  r_bytes[8] = r_bytes[8] & 0xFC
  r_bytes[12] = r_bytes[12] & 0xFC
  let r = u130_from_le16(r_bytes)
  let s = Bytes::makei(16, i => key[16 + i])
  let acc = u130_zero()
  let data_len = data.length()
  let mut offset = 0
  while offset < data_len {
    let remaining = data_len - offset
    let block_len = if remaining < 16 { remaining } else { 16 }
    let block = u130_from_le_block(data, offset, block_len)
    u130_add(acc, block)
    u130_mulmod(acc, r)
    offset = offset + 16
  }
  u130_add_s(acc, s)
  Some(u130_to_bytes(acc))
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "poly1305: RFC 8439 test vector" {
  let key = Bytes::from_array([
    b'\x85', b'\xd6', b'\xbe', b'\x78', b'\x57', b'\x55', b'\x6d', b'\x33', b'\x7f',
    b'\x44', b'\x52', b'\xfe', b'\x42', b'\xd5', b'\x06', b'\xa8', b'\x01', b'\x03',
    b'\x80', b'\x8a', b'\xfb', b'\x0d', b'\xb2', b'\xfd', b'\x4a', b'\xbf', b'\xf6',
    b'\xaf', b'\x41', b'\x49', b'\xf5', b'\x1b',
  ])
  let msg = b"Cryptographic Forum Research Group"
  let tag = match poly1305(key, msg) {
    None => fail("poly1305 failed")
    Some(t) => t
  }
  assert_eq(tag.length(), 16)
  let expected = [
    b'\xa8', b'\x06', b'\x1d', b'\xc1', b'\x30', b'\x51', b'\x36', b'\xc6', b'\xc2',
    b'\x2b', b'\x8b', b'\xaf', b'\x0c', b'\x01', b'\x27', b'\xa9',
  ]
  for i = 0; i < 16; i = i + 1 {
    assert_eq(tag[i], expected[i])
  }
}

///|
test "poly1305: empty message" {
  let key = Bytes::make(32, b'\x00')
  let tag = match poly1305(key, b"") {
    None => fail("poly1305 failed")
    Some(t) => t
  }
  assert_eq(tag.length(), 16)
}

///|
test "poly1305: invalid key length" {
  assert_true(poly1305(Bytes::make(16, b'\x00'), b"test") is None)
}

///|
test "poly1305: determinism" {
  let key = Bytes::makei(32, i => (i * 7 + 3).to_byte())
  let msg = b"hello world"
  let tag1 = match poly1305(key, msg) {
    None => fail("poly1305 failed")
    Some(t) => t
  }
  let tag2 = match poly1305(key, msg) {
    None => fail("poly1305 failed")
    Some(t) => t
  }
  assert_true(tag1 == tag2)
}
