/// White-box tests for the Avro serialization package.
///
/// These tests exercise every public encoder/decoder method and verify
/// encode -> decode round-trips reproduce the original value. Note that
/// Avro uses zigzag + varint encoding, so negative integers DO round-trip.

///|
/// Local byte-equality helper (package does not import test_utils).
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
test "encode_decode_bool_roundtrip" {
  for val in [true, false] {
    let enc = AvroEncoder::new()
    enc.encode_bool(val)
    let dec = AvroDecoder::new(enc.to_bytes())
    assert_eq(dec.decode_bool(), val)
  }
}

///|
test "encode_decode_int_roundtrip" {
  let vals = [
    0, 1, -1, 63, -64, 100, -100, 1000, -1000, 100000, -100000, 1234567, -1234567,
  ]
  for v in vals {
    let enc = AvroEncoder::new()
    enc.encode_int(v)
    let dec = AvroDecoder::new(enc.to_bytes())
    assert_eq(dec.decode_int(), v)
  }
}

///|
test "encode_decode_long_roundtrip" {
  // encode_long is identical to encode_int; decode via decode_int.
  let vals = [0, 1, -1, 100000, -100000, 1000000]
  for v in vals {
    let enc = AvroEncoder::new()
    enc.encode_long(v)
    let dec = AvroDecoder::new(enc.to_bytes())
    assert_eq(dec.decode_int(), v)
  }
}

///|
test "encode_decode_string_roundtrip" {
  let strs = ["", "a", "hello", "avro test 123", "The quick brown fox"]
  for s in strs {
    let enc = AvroEncoder::new()
    enc.encode_string(s)
    let dec = AvroDecoder::new(enc.to_bytes())
    assert_eq(dec.decode_string(), s)
  }
}

///|
test "encode_sequence_roundtrip" {
  // Simulate a small record: int, string, bool.
  let enc = AvroEncoder::new()
  enc.encode_int(42)
  enc.encode_string("answer")
  enc.encode_bool(true)
  let dec = AvroDecoder::new(enc.to_bytes())
  assert_eq(dec.decode_int(), 42)
  assert_eq(dec.decode_string(), "answer")
  assert_eq(dec.decode_bool(), true)
}

///|
test "known_varint_encodings" {
  // zigzag(1) = 2 -> single byte 0x02
  let e1 = AvroEncoder::new()
  e1.encode_int(1)
  assert_true(bytes_eq(e1.to_bytes(), Bytes::from_array([b'\x02'])))
  // zigzag(-1) = 1 -> single byte 0x01
  let e2 = AvroEncoder::new()
  e2.encode_int(-1)
  assert_true(bytes_eq(e2.to_bytes(), Bytes::from_array([b'\x01'])))
  // zigzag(0) = 0 -> 0x00
  let e3 = AvroEncoder::new()
  e3.encode_int(0)
  assert_true(bytes_eq(e3.to_bytes(), Bytes::from_array([b'\x00'])))
}

///|
test "known_string_encoding" {
  // "AB": length zigzag(2)=4 -> 0x04, then 'A'(65) 'B'(66)
  let e = AvroEncoder::new()
  e.encode_string("AB")
  assert_true(bytes_eq(e.to_bytes(), Bytes::from_array([b'\x04', b'A', b'B'])))
}

///|
test "decode_empty_input_is_safe" {
  let dec = AvroDecoder::new(Bytes::from_array([]))
  assert_eq(dec.decode_bool(), false)
  assert_eq(dec.decode_int(), 0)
  assert_eq(dec.decode_string(), "")
}

///|
test "encoder_pos_advances_whitebox" {
  let enc = AvroEncoder::new()
  assert_eq(enc.pos, 0)
  enc.encode_bool(true)
  assert_eq(enc.pos, 1)
  enc.encode_int(300) // multi-byte varint: 2 bytes
  assert_eq(enc.pos, 3)
  enc.encode_string("XY") // 1 (len prefix) + 2 chars = 3 bytes
  assert_eq(enc.pos, 6)
}
