// White-box tests for compression/paq.
// NOTE: this simplified PAQ stores raw symbols (no actual entropy coding),
// so compress->decompress is an exact identity round-trip. We verify that
// invariant on empty and small inputs, plus determinism and the ratio helper.

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
test "paq_roundtrip_empty" {
  let x = Bytes::from_array([])
  let c = paq_compress(x)
  let d = paq_decompress(c)
  assert_eq(d.length(), 0)
  assert_true(bytes_eq(c, x))
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
test "paq_roundtrip_longer" {
  let data : Array[Byte] = []
  for i = 0; i < 64; i = i + 1 {
    data.push((i % 256).to_byte())
  }
  let x = Bytes::from_array(data)
  let d = paq_decompress(paq_compress(x))
  assert_true(bytes_eq(d, x))
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
test "paq_compression_ratio_nonempty" {
  let x = Bytes::from_array([b'\x01', b'\x02', b'\x03', b'\x04'])
  let c = paq_compress(x)
  let r = paq_compression_ratio(x, c)
  // stores raw symbols -> length preserved -> ratio 1.0
  assert_true((r - 1.0).abs() < 1.0e-12)
}

///|
test "paq_compression_ratio_empty" {
  let x = Bytes::from_array([])
  let c = paq_compress(x)
  let r = paq_compression_ratio(x, c)
  assert_true((r - 1.0).abs() < 1.0e-12)
}
