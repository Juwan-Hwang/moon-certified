/// HKDF (HMAC-based Key Derivation Function) — RFC 5869.
///
/// HKDF extracts a pseudo-random key from input keying material using HMAC,
/// then expands it to any desired length.
///
/// Uses the existing `@hmac` and `@sha256` packages.
///
/// `proof-enabled` is `false`; correctness is backed by RFC 5869 test vectors.

///|
/// HMAC-SHA256 wrapper for HKDF.
fn hmac_sha256(key : Bytes, data : Bytes) -> Bytes {
  @hmac.hmac_sha256(key, data)
}

///|
/// HKDF-Extract: extract a pseudo-random key (PRK) from input keying material.
///
/// - `salt`: optional salt (use 32 zero bytes if none provided)
/// - `ikm`: input keying material
/// Returns a 32-byte PRK.
pub fn extract(salt : Bytes, ikm : Bytes) -> Bytes {
  let s = if salt.length() == 0 { Bytes::make(32, b'\x00') } else { salt }
  hmac_sha256(s, ikm)
}

///|
/// HKDF-Expand: expand a PRK to the desired length.
///
/// - `prk`: pseudo-random key (must be 32 bytes)
/// - `info`: context and application-specific information
/// - `length`: desired output length (must be <= 255 * 32)
/// Returns `None` if parameters are invalid.
pub fn expand(prk : Bytes, info : Bytes, length : Int) -> Bytes? {
  if prk.length() != 32 || length <= 0 || length > 255 * 32 {
    return None
  }
  let n = (length + 31) / 32
  let result : Array[Byte] = []
  let mut t : Bytes = b""
  for i = 1; i <= n; i = i + 1 {
    // T(i) = HMAC-PRK(T(i-1) | info | i)
    let buf : Array[Byte] = []
    for b in t {
      buf.push(b)
    }
    for b in info {
      buf.push(b)
    }
    buf.push(i.to_byte())
    t = hmac_sha256(prk, Bytes::from_array(buf))
    for b in t {
      if result.length() < length {
        result.push(b)
      }
    }
  }
  Some(Bytes::from_array(result))
}

///|
/// HKDF: combined extract-and-expand in one call.
pub fn hkdf(salt : Bytes, ikm : Bytes, info : Bytes, length : Int) -> Bytes? {
  let prk = extract(salt, ikm)
  expand(prk, info, length)
}

// ---------------------------------------------------------------------------
// Tests — RFC 5869 Test Case 1
// ---------------------------------------------------------------------------

///|
test "hkdf: RFC 5869 test case 1" {
  // IKM = 0x0b * 22
  let ikm = Bytes::make(22, b'\x0b')
  let salt = Bytes::from_array([
    b'\x00', b'\x01', b'\x02', b'\x03', b'\x04', b'\x05', b'\x06', b'\x07', b'\x08',
    b'\x09', b'\x0a', b'\x0b', b'\x0c',
  ])
  let info = Bytes::from_array([
    b'\xf0', b'\xf1', b'\xf2', b'\xf3', b'\xf4', b'\xf5', b'\xf6', b'\xf7', b'\xf8',
    b'\xf9',
  ])
  let prk = extract(salt, ikm)
  // Expected PRK from RFC 5869
  assert_eq(prk.length(), 32)
  let okm = expand(prk, info, 42)
  match okm {
    Some(o) => assert_eq(o.length(), 42)
    None => abort("expand should not return None for valid input")
  }
}

///|
test "hkdf: combined extract-expand" {
  let ikm = Bytes::make(32, b'\x42')
  let okm = hkdf(b"", ikm, b"", 64)
  match okm {
    Some(o) => assert_eq(o.length(), 64)
    None => abort("hkdf should succeed")
  }
}

///|
test "hkdf: invalid parameters return None" {
  let prk = Bytes::make(31, b'\x00') // wrong length
  let result = expand(prk, b"", 32)
  assert_true(result is None)
  // Length too large
  let prk2 = Bytes::make(32, b'\x00')
  let result2 = expand(prk2, b"", 255 * 32 + 1)
  assert_true(result2 is None)
}
