/// WebSocket Protocol (RFC 6455) — Frame Parsing and Construction
///
/// Implements the WebSocket framing protocol for client-server messaging
/// over TCP. Handles text and binary frames, masking, fragmentation,
/// and close/handshake frames.
///
/// `proof-enabled` is `false`.

///|
/// WebSocket opcode values.
pub enum WsOpcode {
  Continuation // 0x0
  Text // 0x1
  Binary // 0x2
  Close // 0x8
  Ping // 0x9
  Pong // 0xA
}

///|
/// WebSocket frame.
pub struct WsFrame {
  fin : Bool // Final fragment?
  opcode : Int // Frame opcode
  masked : Bool // Is payload masked?
  payload : Bytes // Frame payload data
}

///|
/// Encode a WebSocket frame to bytes.
///
/// ## Parameters
/// - `fin`: true for final fragment
/// - `opcode`: frame opcode (0x1=text, 0x2=binary, 0x8=close)
/// - `payload`: frame data
/// - `mask`: whether to mask the payload (client must mask)
/// - `mask_key`: 4-byte masking key (required if mask=true)
pub fn ws_encode_frame(
  fin : Bool,
  opcode : Int,
  payload : Bytes,
  mask : Bool,
  mask_key : Bytes,
) -> Bytes {
  let payload_len = payload.length()
  let buf : Array[Byte] = []
  // Byte 0: FIN + RSV + opcode
  let b0 = (if fin { 0x80 } else { 0 }) | (opcode & 0x0F)
  buf.push(b0.to_byte())
  // Byte 1: MASK + payload length
  let mut b1 = if mask { 0x80 } else { 0 }
  if payload_len < 126 {
    b1 = b1 | payload_len
    buf.push(b1.to_byte())
  } else if payload_len < 65536 {
    b1 = b1 | 126
    buf.push(b1.to_byte())
    buf.push(((payload_len >> 8) & 0xFF).to_byte())
    buf.push((payload_len & 0xFF).to_byte())
  } else {
    b1 = b1 | 127
    buf.push(b1.to_byte())
    // 8-byte length (high 4 bytes are 0)
    buf.push(b'\x00')
    buf.push(b'\x00')
    buf.push(b'\x00')
    buf.push(b'\x00')
    buf.push(((payload_len >> 24) & 0xFF).to_byte())
    buf.push(((payload_len >> 16) & 0xFF).to_byte())
    buf.push(((payload_len >> 8) & 0xFF).to_byte())
    buf.push((payload_len & 0xFF).to_byte())
  }
  // Masking key
  if mask {
    for i = 0; i < 4; i = i + 1 {
      buf.push(mask_key[i])
    }
  }
  // Payload (masked if needed)
  for i = 0; i < payload_len; i = i + 1 {
    if mask {
      buf.push((payload[i].to_int() ^ mask_key[i % 4].to_int()).to_byte())
    } else {
      buf.push(payload[i])
    }
  }
  Bytes::from_array(buf)
}

///|
/// Parse a WebSocket frame from raw bytes.
///
/// Returns (frame, bytes_consumed) or None if the data is incomplete.
pub fn ws_parse_frame(data : Bytes) -> (WsFrame, Int)? {
  if data.length() < 2 {
    return None
  }
  let b0 = data[0].to_int() & 0xFF
  let b1 = data[1].to_int() & 0xFF
  let fin = (b0 & 0x80) != 0
  let opcode = b0 & 0x0F
  let masked = (b1 & 0x80) != 0
  let mut payload_len = b1 & 0x7F
  let mut pos = 2
  if payload_len == 126 {
    if data.length() < 4 {
      return None
    }
    payload_len = ((data[2].to_int() & 0xFF) << 8) | (data[3].to_int() & 0xFF)
    pos = 4
  } else if payload_len == 127 {
    if data.length() < 10 {
      return None
    }
    // Only use lower 32 bits
    payload_len = ((data[6].to_int() & 0xFF) << 24) |
      ((data[7].to_int() & 0xFF) << 16) |
      ((data[8].to_int() & 0xFF) << 8) |
      (data[9].to_int() & 0xFF)
    pos = 10
  }
  let mask_arr : Array[Int] = [0, 0, 0, 0]
  if masked {
    if data.length() < pos + 4 {
      return None
    }
    for i = 0; i < 4; i = i + 1 {
      mask_arr[i] = data[pos + i].to_int() & 0xFF
    }
    pos = pos + 4
  }
  if data.length() < pos + payload_len {
    return None
  }
  // Extract and unmask payload
  let payload_buf : Array[Byte] = []
  for i = 0; i < payload_len; i = i + 1 {
    if masked {
      payload_buf.push((data[pos + i].to_int() ^ mask_arr[i % 4]).to_byte())
    } else {
      payload_buf.push(data[pos + i])
    }
  }
  let payload = Bytes::from_array(payload_buf)
  pos = pos + payload_len
  Some(({ fin, opcode, masked, payload }, pos))
}

///|
/// Create a text frame.
pub fn ws_text_frame(message : String) -> Bytes {
  let payload = @utf8.encode(message)
  ws_encode_frame(true, 1, payload, false, b"\x00\x00\x00\x00")
}

///|
/// Create a binary frame.
pub fn ws_binary_frame(data : Bytes) -> Bytes {
  ws_encode_frame(true, 2, data, false, b"\x00\x00\x00\x00")
}

///|
/// Create a close frame with optional status code.
pub fn ws_close_frame(status_code : Int?) -> Bytes {
  match status_code {
    Some(code) => {
      let payload_arr : Array[Byte] = [
        ((code >> 8) & 0xFF).to_byte(),
        (code & 0xFF).to_byte(),
      ]
      let payload = Bytes::from_array(payload_arr)
      ws_encode_frame(true, 8, payload, false, b"\x00\x00\x00\x00")
    }
    None => ws_encode_frame(true, 8, b"", false, b"\x00\x00\x00\x00")
  }
}

///|
/// Create a ping frame.
pub fn ws_ping_frame(payload : Bytes) -> Bytes {
  ws_encode_frame(true, 9, payload, false, b"\x00\x00\x00\x00")
}

///|
/// Create a pong frame (response to ping).
pub fn ws_pong_frame(payload : Bytes) -> Bytes {
  ws_encode_frame(true, 10, payload, false, b"\x00\x00\x00\x00")
}

///|
/// All WsOpcode variants (internal type registry).
fn _all_ws_opcodes() -> Array[WsOpcode] {
  [Continuation, Text, Binary, Close, Ping, Pong]
}
