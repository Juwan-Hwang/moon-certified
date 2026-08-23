///|
/// HTTP/2 frame layer white-box tests (RFC 7540).
///
/// NOTE: in this build the test file is compiled as a black-box test, so
/// package struct literals (`H2Frame { ... }`) cannot be constructed
/// directly in the test. Frames are therefore obtained either from the
/// public constructor helpers or by parsing hand-built wire bytes (which
/// yields an `H2Frame` created inside the package). `h2_encode_frame` is
/// then exercised by re-encoding the parsed frame.
fn[T] unwrap_or_fail(o : T?) -> T {
  match o {
    Some(v) => v
    None => abort("unexpected None in test")
  }
}

///|
fn[T] expect_none(o : T?) -> Unit {
  match o {
    Some(_) => abort("expected None but got Some")
    None => ()
  }
}

///|
/// Build raw 9-byte-header + payload frame bytes (mirrors h2_encode_frame).
fn build_frame_raw(
  typ : Int,
  flags : Int,
  stream_id : Int,
  payload : Bytes,
) -> Bytes {
  let buf : Array[Byte] = []
  let len = payload.length()
  buf.push(((len >> 16) & 0xFF).to_byte())
  buf.push(((len >> 8) & 0xFF).to_byte())
  buf.push((len & 0xFF).to_byte())
  buf.push((typ & 0xFF).to_byte())
  buf.push((flags & 0xFF).to_byte())
  buf.push(((stream_id >> 24) & 0x7F).to_byte())
  buf.push(((stream_id >> 16) & 0xFF).to_byte())
  buf.push(((stream_id >> 8) & 0xFF).to_byte())
  buf.push((stream_id & 0xFF).to_byte())
  for i = 0; i < len; i = i + 1 {
    buf.push(payload[i])
  }
  Bytes::from_array(buf)
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

///|
test "h2_frame_type_constants" {
  assert_eq(H2_DATA, 0)
  assert_eq(H2_HEADERS, 1)
  assert_eq(H2_PRIORITY, 2)
  assert_eq(H2_RST_STREAM, 3)
  assert_eq(H2_SETTINGS, 4)
  assert_eq(H2_PUSH_PROMISE, 5)
  assert_eq(H2_PING, 6)
  assert_eq(H2_GOAWAY, 7)
  assert_eq(H2_WINDOW_UPDATE, 8)
  assert_eq(H2_CONTINUATION, 9)
}

// ---------------------------------------------------------------------------
// parse + encode roundtrip for every frame type
// ---------------------------------------------------------------------------

///|
test "h2_data_frame_roundtrip" {
  let payload = Bytes::from_array([b'h', b'e', b'l', b'l', b'o'])
  let raw = build_frame_raw(H2_DATA, 0x01, 3, payload)
  let (f, consumed) = unwrap_or_fail(h2_parse_frame(raw))
  assert_eq(consumed, 9 + payload.length())
  assert_eq(f.frame_type, H2_DATA)
  assert_eq(f.flags, 0x01)
  assert_eq(f.stream_id, 3)
  assert_eq(f.payload, payload)
  // re-encode must reproduce the wire bytes
  let re = h2_encode_frame(f)
  assert_eq(re, raw)
}

///|
test "h2_headers_frame_roundtrip" {
  let payload = Bytes::from_array(Array::make(20, b'\x00'))
  let raw = build_frame_raw(H2_HEADERS, 0x04, 1, payload)
  let (f, consumed) = unwrap_or_fail(h2_parse_frame(raw))
  assert_eq(consumed, 9 + 20)
  assert_eq(f.frame_type, H2_HEADERS)
  assert_eq(f.stream_id, 1)
  assert_eq(f.payload.length(), 20)
  assert_eq(h2_encode_frame(f), raw)
}

///|
test "h2_priority_frame_roundtrip" {
  let payload = Bytes::from_array(Array::make(5, b'\xff'))
  let raw = build_frame_raw(H2_PRIORITY, 0, 7, payload)
  let (f, _) = unwrap_or_fail(h2_parse_frame(raw))
  assert_eq(f.frame_type, H2_PRIORITY)
  assert_eq(f.stream_id, 7)
  assert_eq(h2_encode_frame(f), raw)
}

///|
test "h2_rst_stream_frame_roundtrip" {
  let payload = Bytes::from_array(Array::make(4, b'\x00'))
  let raw = build_frame_raw(H2_RST_STREAM, 0, 9, payload)
  let (f, _) = unwrap_or_fail(h2_parse_frame(raw))
  assert_eq(f.frame_type, H2_RST_STREAM)
  assert_eq(h2_encode_frame(f), raw)
}

///|
test "h2_settings_frame_roundtrip" {
  let payload = Bytes::from_array(Array::make(6, b'\x00'))
  let raw = build_frame_raw(H2_SETTINGS, 0, 0, payload)
  let (f, _) = unwrap_or_fail(h2_parse_frame(raw))
  assert_eq(f.frame_type, H2_SETTINGS)
  assert_eq(f.stream_id, 0)
  assert_eq(h2_encode_frame(f), raw)
}

///|
test "h2_push_promise_frame_roundtrip" {
  let payload = Bytes::from_array(Array::make(10, b'\xaa'))
  let raw = build_frame_raw(H2_PUSH_PROMISE, 0, 2, payload)
  let (f, _) = unwrap_or_fail(h2_parse_frame(raw))
  assert_eq(f.frame_type, H2_PUSH_PROMISE)
  assert_eq(h2_encode_frame(f), raw)
}

///|
test "h2_ping_frame_roundtrip" {
  let payload = Bytes::from_array(Array::make(8, b'\x55'))
  let raw = build_frame_raw(H2_PING, 0x01, 0, payload)
  let (f, _) = unwrap_or_fail(h2_parse_frame(raw))
  assert_eq(f.frame_type, H2_PING)
  assert_eq(f.flags, 0x01)
  assert_eq(h2_encode_frame(f), raw)
}

///|
test "h2_goaway_frame_roundtrip" {
  let payload = Bytes::from_array(Array::make(8, b'\x00'))
  let raw = build_frame_raw(H2_GOAWAY, 0, 0, payload)
  let (f, _) = unwrap_or_fail(h2_parse_frame(raw))
  assert_eq(f.frame_type, H2_GOAWAY)
  assert_eq(h2_encode_frame(f), raw)
}

///|
test "h2_window_update_frame_roundtrip" {
  let payload = Bytes::from_array(Array::make(4, b'\x00'))
  let raw = build_frame_raw(H2_WINDOW_UPDATE, 0, 5, payload)
  let (f, _) = unwrap_or_fail(h2_parse_frame(raw))
  assert_eq(f.frame_type, H2_WINDOW_UPDATE)
  assert_eq(f.stream_id, 5)
  assert_eq(h2_encode_frame(f), raw)
}

///|
test "h2_continuation_frame_roundtrip" {
  let payload = Bytes::from_array(Array::make(3, b'\x11'))
  let raw = build_frame_raw(H2_CONTINUATION, 0, 11, payload)
  let (f, _) = unwrap_or_fail(h2_parse_frame(raw))
  assert_eq(f.frame_type, H2_CONTINUATION)
  assert_eq(h2_encode_frame(f), raw)
}

///|
test "h2_empty_payload_frame" {
  let raw = build_frame_raw(H2_DATA, 0, 1, b"")
  let (f, consumed) = unwrap_or_fail(h2_parse_frame(raw))
  assert_eq(consumed, 9)
  assert_eq(f.payload.length(), 0)
  assert_eq(h2_encode_frame(f), raw)
}

// ---------------------------------------------------------------------------
// Public constructor helpers
// ---------------------------------------------------------------------------

///|
test "h2_settings_frame_helper" {
  let f = h2_settings_frame([(1, 4096), (3, 100)])
  assert_eq(f.frame_type, H2_SETTINGS)
  assert_eq(f.stream_id, 0)
  assert_eq(f.flags, 0)
  assert_eq(f.length, 12) // 2 settings * 6 bytes
  // payload: id(2) + value(4) per setting
  let p = f.payload
  assert_eq(p.length(), 12)
  assert_eq(p[0], b'\x00')
  assert_eq(p[1], b'\x01') // id 1
  assert_eq(p[2], b'\x00')
  assert_eq(p[3], b'\x00')
  assert_eq(p[4], b'\x10') // 4096 >> 8
  assert_eq(p[5], b'\x00') // 4096 & 0xFF
  assert_eq(p[6], b'\x00')
  assert_eq(p[7], b'\x03') // id 3
  assert_eq(p[10], b'\x00')
  assert_eq(p[11], b'\x64') // 100
  // full encode/parse roundtrip
  let (pf, _) = unwrap_or_fail(h2_parse_frame(h2_encode_frame(f)))
  assert_eq(pf.frame_type, H2_SETTINGS)
  assert_eq(pf.payload, p)
}

///|
test "h2_ping_frame_helper" {
  let opaque_data = Bytes::from_array([
    b'\x01', b'\x02', b'\x03', b'\x04', b'\x05', b'\x06', b'\x07', b'\x08',
  ])
  let f = h2_ping_frame(opaque_data)
  assert_eq(f.frame_type, H2_PING)
  assert_eq(f.length, 8)
  assert_eq(f.payload, opaque_data)
  let (pf, _) = unwrap_or_fail(h2_parse_frame(h2_encode_frame(f)))
  assert_eq(pf.payload, opaque_data)
}

///|
test "h2_goaway_frame_helper" {
  let debug = Bytes::from_array([b'x', b'y', b'z'])
  let f = h2_goaway_frame(0x0A, 0x01, debug)
  assert_eq(f.frame_type, H2_GOAWAY)
  // payload = 8 (last_stream_id+error_code) + 3 debug = 11
  assert_eq(f.length, 11)
  let p = f.payload
  assert_eq(p[0], b'\x00')
  assert_eq(p[1], b'\x00')
  assert_eq(p[2], b'\x00')
  assert_eq(p[3], b'\x0a') // last_stream_id
  assert_eq(p[4], b'\x00')
  assert_eq(p[5], b'\x00')
  assert_eq(p[6], b'\x00')
  assert_eq(p[7], b'\x01') // error_code
  assert_eq(p[8], b'x')
  assert_eq(p[9], b'y')
  assert_eq(p[10], b'z')
  let (pf, _) = unwrap_or_fail(h2_parse_frame(h2_encode_frame(f)))
  assert_eq(pf.frame_type, H2_GOAWAY)
  assert_eq(pf.payload, p)
}

///|
test "h2_window_update_frame_helper" {
  let f = h2_window_update_frame(3, 0x7FFFFFFF)
  assert_eq(f.frame_type, H2_WINDOW_UPDATE)
  assert_eq(f.stream_id, 3)
  assert_eq(f.length, 4)
  // high bit of increment must be masked (0x7F)
  let p = f.payload
  assert_eq(p[0], b'\x7f')
  assert_eq(p[1], b'\xff')
  assert_eq(p[2], b'\xff')
  assert_eq(p[3], b'\xff')
  let (pf, _) = unwrap_or_fail(h2_parse_frame(h2_encode_frame(f)))
  assert_eq(pf.payload, p)
}

///|
test "h2_rst_stream_frame_helper" {
  let f = h2_rst_stream_frame(9, 0x0000000B)
  assert_eq(f.frame_type, H2_RST_STREAM)
  assert_eq(f.stream_id, 9)
  assert_eq(f.length, 4)
  let p = f.payload
  assert_eq(p[0], b'\x00')
  assert_eq(p[1], b'\x00')
  assert_eq(p[2], b'\x00')
  assert_eq(p[3], b'\x0b') // error_code
  let (pf, _) = unwrap_or_fail(h2_parse_frame(h2_encode_frame(f)))
  assert_eq(pf.payload, p)
}

// ---------------------------------------------------------------------------
// Malformed / incomplete input
// ---------------------------------------------------------------------------

///|
test "h2_parse_too_short" {
  expect_none(h2_parse_frame(Bytes::from_array([])))
  expect_none(h2_parse_frame(Bytes::from_array(Array::make(8, b'\x00'))))
}

///|
test "h2_parse_incomplete_payload" {
  // header claims 5-byte payload but only 2 present
  let buf : Array[Byte] = []
  buf.push(b'\x00')
  buf.push(b'\x00')
  buf.push(b'\x05') // length 5
  buf.push(b'\x00')
  buf.push(b'\x00') // type, flags
  buf.push(b'\x00')
  buf.push(b'\x00')
  buf.push(b'\x00')
  buf.push(b'\x01') // stream
  buf.push(b'\xaa')
  buf.push(b'\xbb') // only 2 payload bytes
  expect_none(h2_parse_frame(Bytes::from_array(buf)))
}

// ---------------------------------------------------------------------------
// Streaming: parse consecutive frames using consumed offset
// ---------------------------------------------------------------------------

///|
test "h2_parse_multiple_frames" {
  let f1 = build_frame_raw(H2_DATA, 0, 1, Bytes::from_array([b'a']))
  let f2 = build_frame_raw(H2_HEADERS, 0, 3, Bytes::from_array([b'b', b'c']))
  let combined : Array[Byte] = []
  for i = 0; i < f1.length(); i = i + 1 {
    combined.push(f1[i])
  }
  for i = 0; i < f2.length(); i = i + 1 {
    combined.push(f2[i])
  }
  let data = Bytes::from_array(combined)
  let (p1, c1) = unwrap_or_fail(h2_parse_frame(data))
  assert_eq(p1.frame_type, H2_DATA)
  assert_eq(c1, 10)
  // remainder starts at c1
  let rest_arr : Array[Byte] = []
  for i = c1; i < combined.length(); i = i + 1 {
    rest_arr.push(combined[i])
  }
  let rest = Bytes::from_array(rest_arr)
  let (p2, c2) = unwrap_or_fail(h2_parse_frame(rest))
  assert_eq(p2.frame_type, H2_HEADERS)
  assert_eq(c2, 11)
}
