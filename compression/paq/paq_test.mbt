// Tests for compression/paq — real context-mixing arithmetic coder.
// Covers round-trips on several data classes, genuine compression on
// redundant data, determinism, and rejection of corrupted containers.

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
fn paq_try_decompress(data : Bytes) -> Bytes? {
  Some(paq_decompress(data)) catch {
    _ => None
  }
}

///|
test "paq_roundtrip_empty" {
  let x = Bytes::from_array([])
  let c = paq_compress(x)
  let d = paq_decompress(c)
  assert_eq(d.length(), 0)
  // Header (magic + length) plus 4 flushed range-coder bytes minimum.
  assert_true(c.length() >= 12)
}

///|
test "paq_roundtrip_small" {
  let x = Bytes::from_array([
    b'\x00', b'\x01', b'\x41', b'\xff', b'\x7f', b'\x80',
  ])
  let c = paq_compress(x)
  let d = paq_decompress(c)
  assert_eq(d.length(), x.length())
  assert_true(bytes_eq(d, x))
}

///|
test "paq_roundtrip_all_byte_values" {
  let data : Array[Byte] = []
  for i = 0; i < 256; i = i + 1 {
    data.push(i.to_byte())
  }
  let x = Bytes::from_array(data)
  let d = paq_decompress(paq_compress(x))
  assert_true(bytes_eq(d, x))
}

///|
test "paq_roundtrip_repetitive_text" {
  // Highly redundant English-like text: must compress well.
  let words = [
    "the", "quick", "brown", "fox", "jumps", "over", "lazy", "dog", "and", "the",
    "dog", "barks", "at", "the", "fox", "again",
  ]
  let data : Array[Byte] = []
  for rep = 0; rep < 200; rep = rep + 1 {
    for w in words {
      for ch in w {
        data.push(ch.to_int().to_byte())
      }
      data.push(b' ')
    }
  }
  let x = Bytes::from_array(data)
  let c = paq_compress(x)
  let d = paq_decompress(c)
  assert_true(bytes_eq(d, x))
  // Redundant text must genuinely shrink (ratio well below 1.0).
  assert_true(paq_compression_ratio(x, c) < 0.5)
}

///|
test "paq_roundtrip_pseudorandom" {
  // Incompressible data still round-trips exactly.
  let data : Array[Byte] = []
  let mut state = 123456789L
  for _i = 0; _i < 4096; _i = _i + 1 {
    state = (state * 1103515245L + 12345L) & 0x7FFFFFFFL
    // Take high bits: low bits of an LCG have short periods.
    data.push(((state >> 23) & 0xFFL).to_byte())
  }
  let x = Bytes::from_array(data)
  let c = paq_compress(x)
  let d = paq_decompress(c)
  assert_true(bytes_eq(d, x))
  // Random data cannot shrink meaningfully; allow header overhead.
  assert_true(paq_compression_ratio(x, c) > 0.9)
}

///|
test "paq_compress_is_deterministic" {
  let x = Bytes::from_array([b'\x10', b'\x20', b'\x30', b'\xaa'])
  let c1 = paq_compress(x)
  let c2 = paq_compress(x)
  assert_eq(c1.length(), c2.length())
  assert_true(bytes_eq(c1, c2))
}

///|
test "paq_rejects_corrupted_containers" {
  let x = Bytes::from_array([
    b'a', b'b', b'r', b'a', b'c', b'a', b'd', b'a', b'b', b'r', b'a',
  ])
  let c = paq_compress(x)
  // Bad magic.
  let bad_magic = Bytes::from_array(c.to_array())
  let arr0 = bad_magic.to_array()
  arr0[0] = b'X'
  assert_eq(paq_try_decompress(Bytes::from_array(arr0)), None)
  // Truncated header.
  assert_eq(paq_try_decompress(Bytes::from_array([b'M', b'B', b'P'])), None)
  // Garbage stream with valid header.
  let garbage : Array[Byte] = [
    b'M', b'B', b'P', b'Q', b'\x05', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00',
    b'\x00', b'\x00', b'\x99', b'\x99', b'\x99', b'\x99',
  ]
  // Decoding garbage either fails or yields non-matching bytes; it
  // must never silently return the original payload.
  match paq_try_decompress(Bytes::from_array(garbage)) {
    Some(out) => assert_true(!bytes_eq(out, x))
    None => ()
  }
}

///|
test "paq_compression_ratio_empty" {
  let x = Bytes::from_array([])
  let c = paq_compress(x)
  let r = paq_compression_ratio(x, c)
  assert_true((r - 1.0).abs() < 1.0e-12)
}
