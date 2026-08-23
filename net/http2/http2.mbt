/// HTTP/2 Frame Layer — RFC 7540
///
/// Implements HTTP/2 frame parsing and construction including:
/// - DATA frames (stream payload)
/// - HEADERS frames (HPACK headers)
/// - SETTINGS frames
/// - RST_STREAM, PING, GOAWAY frames
/// - WINDOW_UPDATE for flow control
/// - PRIORITY frames
///
/// `proof-enabled` is `false`.

///|
/// HTTP/2 frame types.
pub const H2_DATA : Int = 0x0

///|
pub const H2_HEADERS : Int = 0x1

///|
pub const H2_PRIORITY : Int = 0x2

///|
pub const H2_RST_STREAM : Int = 0x3

///|
pub const H2_SETTINGS : Int = 0x4

///|
pub const H2_PUSH_PROMISE : Int = 0x5

///|
pub const H2_PING : Int = 0x6

///|
pub const H2_GOAWAY : Int = 0x7

///|
pub const H2_WINDOW_UPDATE : Int = 0x8

///|
pub const H2_CONTINUATION : Int = 0x9

///|
/// HTTP/2 frame.
pub struct H2Frame {
  length : Int // 3 bytes (max 2^24-1)
  frame_type : Int // 1 byte
  flags : Int // 1 byte
  stream_id : Int // 4 bytes (low 31 bits)
  payload : Bytes
}

///|
/// Encode an HTTP/2 frame to bytes.
pub fn h2_encode_frame(frame : H2Frame) -> Bytes {
  let buf : Array[Byte] = []
  // Length (3 bytes, big-endian)
  buf.push(((frame.length >> 16) & 0xFF).to_byte())
  buf.push(((frame.length >> 8) & 0xFF).to_byte())
  buf.push((frame.length & 0xFF).to_byte())
  // Type
  buf.push((frame.frame_type & 0xFF).to_byte())
  // Flags
  buf.push((frame.flags & 0xFF).to_byte())
  // Stream ID (4 bytes, R bit must be 0)
  buf.push(((frame.stream_id >> 24) & 0x7F).to_byte())
  buf.push(((frame.stream_id >> 16) & 0xFF).to_byte())
  buf.push(((frame.stream_id >> 8) & 0xFF).to_byte())
  buf.push((frame.stream_id & 0xFF).to_byte())
  // Payload
  for i = 0; i < frame.payload.length(); i = i + 1 {
    buf.push(frame.payload[i])
  }
  Bytes::from_array(buf)
}

///|
/// Parse an HTTP/2 frame from raw bytes.
pub fn h2_parse_frame(data : Bytes) -> (H2Frame, Int)? {
  if data.length() < 9 {
    return None
  }
  let length = ((data[0].to_int() & 0xFF) << 16) |
    ((data[1].to_int() & 0xFF) << 8) |
    (data[2].to_int() & 0xFF)
  let frame_type = data[3].to_int() & 0xFF
  let flags = data[4].to_int() & 0xFF
  let stream_id = ((data[5].to_int() & 0x7F) << 24) |
    ((data[6].to_int() & 0xFF) << 16) |
    ((data[7].to_int() & 0xFF) << 8) |
    (data[8].to_int() & 0xFF)
  if data.length() < 9 + length {
    return None // Incomplete frame
  }
  let payload_buf : Array[Byte] = []
  for i = 0; i < length; i = i + 1 {
    payload_buf.push(data[9 + i])
  }
  let payload = Bytes::from_array(payload_buf)
  let consumed = 9 + length
  Some(({ length, frame_type, flags, stream_id, payload }, consumed))
}

///|
/// Create a SETTINGS frame.
pub fn h2_settings_frame(settings : Array[(Int, Int)]) -> H2Frame {
  let payload_buf : Array[Byte] = []
  for setting in settings {
    payload_buf.push(((setting.0 >> 8) & 0xFF).to_byte())
    payload_buf.push((setting.0 & 0xFF).to_byte())
    payload_buf.push(((setting.1 >> 24) & 0xFF).to_byte())
    payload_buf.push(((setting.1 >> 16) & 0xFF).to_byte())
    payload_buf.push(((setting.1 >> 8) & 0xFF).to_byte())
    payload_buf.push((setting.1 & 0xFF).to_byte())
  }
  let payload_len = settings.length() * 6
  let payload = Bytes::from_array(payload_buf)
  {
    length: payload_len,
    frame_type: H2_SETTINGS,
    flags: 0,
    stream_id: 0,
    payload,
  }
}

///|
/// Create a PING frame.
pub fn h2_ping_frame(opaque_data : Bytes) -> H2Frame {
  {
    length: 8,
    frame_type: H2_PING,
    flags: 0,
    stream_id: 0,
    payload: opaque_data,
  }
}

///|
/// Create a GOAWAY frame.
pub fn h2_goaway_frame(
  last_stream_id : Int,
  error_code : Int,
  debug_data : Bytes,
) -> H2Frame {
  let payload_buf : Array[Byte] = []
  payload_buf.push(((last_stream_id >> 24) & 0x7F).to_byte())
  payload_buf.push(((last_stream_id >> 16) & 0xFF).to_byte())
  payload_buf.push(((last_stream_id >> 8) & 0xFF).to_byte())
  payload_buf.push((last_stream_id & 0xFF).to_byte())
  payload_buf.push(((error_code >> 24) & 0xFF).to_byte())
  payload_buf.push(((error_code >> 16) & 0xFF).to_byte())
  payload_buf.push(((error_code >> 8) & 0xFF).to_byte())
  payload_buf.push((error_code & 0xFF).to_byte())
  for i = 0; i < debug_data.length(); i = i + 1 {
    payload_buf.push(debug_data[i])
  }
  let payload = Bytes::from_array(payload_buf)
  {
    length: payload.length(),
    frame_type: H2_GOAWAY,
    flags: 0,
    stream_id: 0,
    payload,
  }
}

///|
/// Create a WINDOW_UPDATE frame.
pub fn h2_window_update_frame(stream_id : Int, increment : Int) -> H2Frame {
  let payload : Bytes = Bytes::from_array([
    ((increment >> 24) & 0x7F).to_byte(),
    ((increment >> 16) & 0xFF).to_byte(),
    ((increment >> 8) & 0xFF).to_byte(),
    (increment & 0xFF).to_byte(),
  ])
  { length: 4, frame_type: H2_WINDOW_UPDATE, flags: 0, stream_id, payload }
}

///|
/// Create an RST_STREAM frame.
pub fn h2_rst_stream_frame(stream_id : Int, error_code : Int) -> H2Frame {
  let payload : Bytes = Bytes::from_array([
    ((error_code >> 24) & 0xFF).to_byte(),
    ((error_code >> 16) & 0xFF).to_byte(),
    ((error_code >> 8) & 0xFF).to_byte(),
    (error_code & 0xFF).to_byte(),
  ])
  { length: 4, frame_type: H2_RST_STREAM, flags: 0, stream_id, payload }
}
