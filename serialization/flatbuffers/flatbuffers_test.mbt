/// White-box tests for the FlatBuffers serialization package.
///
/// NOTE: the `flatbuffer_read_*` helpers only decode the low 32 bits and do
/// not sign-extend, so only NON-NEGATIVE integers round-trip correctly.
/// `put_int32` returns Unit (no offset); the write offset is tracked via the
/// builder's `pos` (white-box) — a single write starts at offset 0.

///|
test "new_default_and_explicit_size_whitebox" {
  let b0 = FlatBufferBuilder::new(0)
  assert_eq(b0.buf.length(), 64)
  let b1 = FlatBufferBuilder::new(100)
  assert_eq(b1.buf.length(), 100)
  assert_eq(b1.pos, 0)
}

///|
test "put_byte_roundtrip" {
  let b = FlatBufferBuilder::new(64)
  b.put_byte(200) // writes at offset 0
  let data = b.finish()
  assert_eq(data.length(), 1)
  assert_eq(data[0], b'\xc8')
}

///|
test "put_int32_roundtrip" {
  let vals = [0, 1, 255, 256, 65535, 16777215, 123456789]
  for v in vals {
    let b = FlatBufferBuilder::new(64)
    b.put_int32(v) // writes at offset 0
    let data = b.finish()
    assert_eq(flatbuffer_read_int32(data, 0), v)
  }
}

///|
test "put_string_roundtrip" {
  let strs = ["", "hi", "flatbuffers!", "A", "The quick brown fox jumps"]
  for s in strs {
    let b = FlatBufferBuilder::new(64)
    let off = b.put_string(s)
    let data = b.finish()
    assert_eq(flatbuffer_read_string(data, off), s)
  }
}

///|
test "put_int_vector_roundtrip" {
  // empty vector
  let b0 = FlatBufferBuilder::new(64)
  let off0 = b0.put_int_vector([])
  let d0 = b0.finish()
  let g0 = flatbuffer_read_int_vector(d0, off0)
  assert_eq(g0.length(), 0)
  // non-empty vectors
  let cases : Array[Array[Int]] = [
    [1],
    [1, 2, 3, 4, 5],
    [10, 20, 30, 40, 50, 60, 70, 80, 90, 100],
  ]
  for v in cases {
    let b = FlatBufferBuilder::new(64)
    let off = b.put_int_vector(v)
    let data = b.finish()
    let got = flatbuffer_read_int_vector(data, off)
    assert_eq(got.length(), v.length())
    for i = 0; i < v.length(); i = i + 1 {
      assert_eq(got[i], v[i])
    }
  }
}

///|
test "multiple_puts_distinct_offsets" {
  let b = FlatBufferBuilder::new(64)
  b.put_int32(42) // offset 0
  let s_off = b.put_string("xyz") // offset 4
  let v_off = b.put_int_vector([7, 8, 9]) // offset 11
  let data = b.finish()
  assert_eq(flatbuffer_read_int32(data, 0), 42)
  assert_eq(flatbuffer_read_string(data, s_off), "xyz")
  let got = flatbuffer_read_int_vector(data, v_off)
  assert_eq(got.length(), 3)
  assert_eq(got[0], 7)
  assert_eq(got[1], 8)
  assert_eq(got[2], 9)
}

///|
test "put_string_offset_points_at_length_prefix" {
  let b = FlatBufferBuilder::new(64)
  b.put_int32(1) // 4 bytes, pos now 4
  let s_off = b.put_string("ab")
  let data = b.finish()
  assert_eq(s_off, 4)
  assert_eq(flatbuffer_read_int32(data, s_off), 2) // length prefix
}

///|
test "read_out_of_bounds_returns_default" {
  assert_eq(flatbuffer_read_int32(Bytes::from_array([]), 0), 0)
  assert_eq(flatbuffer_read_int32(Bytes::from_array([b'\x01', b'\x02']), 0), 0)
  assert_eq(flatbuffer_read_string(Bytes::from_array([]), 0), "")
  assert_eq(flatbuffer_read_int_vector(Bytes::from_array([]), 0).length(), 0)
}

///|
test "builder_grows_on_large_vector" {
  let big : Array[Int] = Array::make(1000, 0)
  for i = 0; i < 1000; i = i + 1 {
    big[i] = i % 1000
  }
  let b = FlatBufferBuilder::new(64)
  let off = b.put_int_vector(big)
  let data = b.finish()
  let got = flatbuffer_read_int_vector(data, off)
  assert_eq(got.length(), 1000)
  for i = 0; i < 1000; i = i + 1 {
    assert_eq(got[i], i % 1000)
  }
}

///|
test "finish_sets_finished_flag_whitebox" {
  let b = FlatBufferBuilder::new(64)
  b.put_byte(1)
  assert_eq(b.finished, false)
  let _ = b.finish()
  assert_eq(b.finished, true)
}
