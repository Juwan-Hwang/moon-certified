/// White-box tests for the Thrift binary protocol package.
///
/// NOTE: `read_i32` only decodes the low 32 bits and does not sign-extend,
/// so only NON-NEGATIVE integers round-trip correctly. `write_i64` delegates
/// to `write_i32`, so it too is limited to 32 bits.

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
test "thrift_constants" {
  assert_eq(T_CALL, 1)
  assert_eq(T_REPLY, 2)
  assert_eq(T_EXCEPTION, 3)
  assert_eq(T_ONEWAY, 4)
  assert_eq(T_STOP, 0)
  assert_eq(T_BOOL, 2)
  assert_eq(T_BYTE, 3)
  assert_eq(T_I32, 8)
  assert_eq(T_I64, 10)
  assert_eq(T_STRING, 11)
  assert_eq(T_STRUCT, 12)
  assert_eq(T_LIST, 15)
}

///|
test "field_begin_roundtrip" {
  for fid in [0, 1, 255, 256, 65535] {
    let enc = ThriftEncoder::new()
    enc.write_field_begin(T_STRING, fid)
    enc.write_stop()
    let dec = ThriftDecoder::new(enc.to_bytes())
    let (t, id) = dec.read_field_begin()
    assert_eq(t, T_STRING)
    assert_eq(id, fid)
  }
}

///|
test "bool_roundtrip" {
  for val in [true, false] {
    let enc = ThriftEncoder::new()
    enc.write_bool(val)
    let dec = ThriftDecoder::new(enc.to_bytes())
    assert_eq(dec.read_bool(), val)
  }
}

///|
test "i32_roundtrip" {
  let vals = [0, 1, 255, 256, 65535, 16777215, 123456789]
  for v in vals {
    let enc = ThriftEncoder::new()
    enc.write_i32(v)
    let dec = ThriftDecoder::new(enc.to_bytes())
    assert_eq(dec.read_i32(), v)
  }
}

///|
test "i64_uses_low_32_bits" {
  // write_i64 delegates to write_i32; read back via read_i32.
  let enc = ThriftEncoder::new()
  enc.write_i64(777)
  let dec = ThriftDecoder::new(enc.to_bytes())
  assert_eq(dec.read_i32(), 777)
}

///|
test "string_roundtrip" {
  let strs = ["", "hello thrift", "a", "1234567890"]
  for s in strs {
    let enc = ThriftEncoder::new()
    enc.write_string(s)
    let dec = ThriftDecoder::new(enc.to_bytes())
    assert_eq(dec.read_string(), s)
  }
}

///|
test "struct_begin_is_noop" {
  let enc = ThriftEncoder::new()
  enc.write_struct_begin("MyStruct")
  assert_eq(enc.to_bytes().length(), 0)
}

///|
test "stop_marks_end_of_struct" {
  let enc = ThriftEncoder::new()
  enc.write_field_begin(T_BOOL, 1)
  enc.write_bool(true)
  enc.write_stop()
  let dec = ThriftDecoder::new(enc.to_bytes())
  let (t, id) = dec.read_field_begin()
  assert_eq(t, T_BOOL)
  assert_eq(id, 1)
  assert_eq(dec.read_bool(), true)
  let (t2, id2) = dec.read_field_begin()
  assert_eq(t2, T_STOP)
  assert_eq(id2, 0)
}

///|
test "decode_empty_input_is_safe" {
  let dec = ThriftDecoder::new(Bytes::from_array([]))
  let (t, id) = dec.read_field_begin()
  assert_eq(t, 0)
  assert_eq(id, 0)
  assert_eq(dec.read_bool(), false)
  assert_eq(dec.read_i32(), 0)
  assert_eq(dec.read_string(), "")
}

///|
test "known_i32_encoding" {
  let e1 = ThriftEncoder::new()
  e1.write_i32(1)
  assert_true(
    bytes_eq(
      e1.to_bytes(),
      Bytes::from_array([b'\x00', b'\x00', b'\x00', b'\x01']),
    ),
  )
  let e2 = ThriftEncoder::new()
  e2.write_i32(256)
  assert_true(
    bytes_eq(
      e2.to_bytes(),
      Bytes::from_array([b'\x00', b'\x00', b'\x01', b'\x00']),
    ),
  )
}

///|
test "known_field_begin_encoding" {
  let e = ThriftEncoder::new()
  e.write_field_begin(T_I32, 1) // type 8, id 1 big-endian
  assert_true(
    bytes_eq(e.to_bytes(), Bytes::from_array([b'\x08', b'\x00', b'\x01'])),
  )
}

///|
test "skip_advances_pos_whitebox" {
  // T_BOOL advances by 1.
  let d_bool = ThriftDecoder::new(Bytes::from_array([b'\x00']))
  d_bool.skip(T_BOOL)
  assert_eq(d_bool.pos, 1)

  // T_I32 advances by 4.
  let d_i32 = ThriftDecoder::new(
    Bytes::from_array([b'\x00', b'\x00', b'\x00', b'\x00']),
  )
  d_i32.skip(T_I32)
  assert_eq(d_i32.pos, 4)

  // T_STRING reads a 4-byte length prefix then advances by that many bytes.
  let d_str = ThriftDecoder::new(
    Bytes::from_array([
      b'\x00', b'\x00', b'\x00', b'\x03', b'\x41', b'\x42', b'\x43',
    ]),
  )
  d_str.skip(T_STRING)
  assert_eq(d_str.pos, 4 + 3)
}
