///|
/// Comprehensive tests for WebSocket Protocol (RFC 6455).

// ===========================================================================
// Frame encoding tests (unmasked)
// ===========================================================================

test "ws_encode_frame: small unmasked text frame" {
  let payload = Bytes::from_array([0x48, 0x69]) // "Hi"
  let frame = ws_encode_frame(true, 1, payload, false, b"\x00\x00\x00\x00")
  // FIN=1, opcode=1 => byte0 = 0x81
  assert_eq(frame[0].to_int(), 0x81)
  // No mask, payload_len = 2 => byte1 = 0x02
  assert_eq(frame[1].to_int(), 0x02)
  // Payload
  assert_eq(frame[2].to_int(), 0x48)
  assert_eq(frame[3].to_int(), 0x69)
}

///|
test "ws_encode_frame: FIN=false" {
  let payload = Bytes::from_array([0x41])
  let frame = ws_encode_frame(false, 0, payload, false, b"\x00\x00\x00\x00")
  // FIN=0, opcode=0 => byte0 = 0x00
  assert_eq(frame[0].to_int(), 0x00)
}

///|
test "ws_encode_frame: binary opcode" {
  let payload = Bytes::from_array([0x01])
  let frame = ws_encode_frame(true, 2, payload, false, b"\x00\x00\x00\x00")
  assert_eq(frame[0].to_int(), 0x82)
}

///|
test "ws_encode_frame: close opcode" {
  let payload = Bytes::from_array([])
  let frame = ws_encode_frame(true, 8, payload, false, b"\x00\x00\x00\x00")
  assert_eq(frame[0].to_int(), 0x88)
}

///|
test "ws_encode_frame: ping opcode" {
  let payload = Bytes::from_array([0x01])
  let frame = ws_encode_frame(true, 9, payload, false, b"\x00\x00\x00\x00")
  assert_eq(frame[0].to_int(), 0x89)
}

///|
test "ws_encode_frame: pong opcode" {
  let payload = Bytes::from_array([0x01])
  let frame = ws_encode_frame(true, 10, payload, false, b"\x00\x00\x00\x00")
  assert_eq(frame[0].to_int(), 0x8A)
}

///|
test "ws_encode_frame: empty payload" {
  let payload = Bytes::from_array([])
  let frame = ws_encode_frame(true, 1, payload, false, b"\x00\x00\x00\x00")
  assert_eq(frame[0].to_int(), 0x81)
  assert_eq(frame[1].to_int(), 0x00)
  assert_eq(frame.length(), 2)
}

// ===========================================================================
// Extended payload length tests
// ===========================================================================

///|
test "ws_encode_frame: 126-byte payload uses 16-bit length" {
  let arr : Array[Byte] = Array::make(126, 0x41)
  let payload = Bytes::from_array(arr)
  let frame = ws_encode_frame(true, 2, payload, false, b"\x00\x00\x00\x00")
  // byte1 should have payload_len = 126
  assert_eq(frame[1].to_int() & 0x7F, 126)
  // Extended length: 126 = 0x007E
  assert_eq(frame[2].to_int(), 0x00)
  assert_eq(frame[3].to_int(), 0x7E)
}

///|
test "ws_encode_frame: 125-byte payload uses short length" {
  let arr : Array[Byte] = Array::make(125, 0x41)
  let payload = Bytes::from_array(arr)
  let frame = ws_encode_frame(true, 2, payload, false, b"\x00\x00\x00\x00")
  assert_eq(frame[1].to_int() & 0x7F, 125)
}

///|
test "ws_encode_frame: 65536-byte payload uses 64-bit length" {
  let arr : Array[Byte] = Array::make(65536, 0x42)
  let payload = Bytes::from_array(arr)
  let frame = ws_encode_frame(true, 2, payload, false, b"\x00\x00\x00\x00")
  assert_eq(frame[1].to_int() & 0x7F, 127)
  // 8-byte length field (only lower 32 bits used)
  // Skip the first 4 zero bytes, check the lower 4
  assert_eq(frame[2].to_int(), 0x00)
  assert_eq(frame[3].to_int(), 0x00)
  assert_eq(frame[4].to_int(), 0x00)
  assert_eq(frame[5].to_int(), 0x00)
  assert_eq(frame[6].to_int(), 0x00) // 65536 >> 24 = 0
  assert_eq(frame[7].to_int(), 0x01) // 65536 >> 16 = 1
  assert_eq(frame[8].to_int(), 0x00) // 65536 >> 8 = 0
  assert_eq(frame[9].to_int(), 0x00) // 65536 & 0xFF = 0
}

// ===========================================================================
// Masked frame tests
// ===========================================================================

///|
test "ws_encode_frame: masked frame" {
  let payload = Bytes::from_array([0x48, 0x69])
  let mask = Bytes::from_array([0x37, 0xFA, 0x21, 0x3D])
  let frame = ws_encode_frame(true, 1, payload, true, mask)
  // byte1 has mask bit set
  assert_eq((frame[1].to_int() & 0x80) != 0, true)
  // Mask key at bytes 2-5
  assert_eq(frame[2].to_int(), 0x37)
  assert_eq(frame[3].to_int(), 0xFA)
  assert_eq(frame[4].to_int(), 0x21)
  assert_eq(frame[5].to_int(), 0x3D)
  // Masked payload: payload[i] XOR mask[i%4]
  assert_eq(frame[6].to_int(), 0x48 ^ 0x37)
  assert_eq(frame[7].to_int(), 0x69 ^ 0xFA)
}

// ===========================================================================
// Frame parsing round-trip tests
// ===========================================================================

///|
test "ws_parse_frame: parse unmasked text frame" {
  let payload = Bytes::from_array([0x48, 0x69])
  let encoded = ws_encode_frame(true, 1, payload, false, b"\x00\x00\x00\x00")
  match ws_parse_frame(encoded) {
    Some((frame, consumed)) => {
      assert_eq(frame.fin, true)
      assert_eq(frame.opcode, 1)
      assert_eq(frame.masked, false)
      assert_eq(frame.payload.length(), 2)
      assert_eq(frame.payload[0].to_int(), 0x48)
      assert_eq(frame.payload[1].to_int(), 0x69)
      assert_eq(consumed, encoded.length())
    }
    None => abort("expected Some")
  }
}

///|
test "ws_parse_frame: parse masked frame round-trip" {
  let payload = Bytes::from_array([0xDE, 0xAD, 0xBE, 0xEF, 0x01])
  let mask = Bytes::from_array([0x37, 0xFA, 0x21, 0x3D])
  let encoded = ws_encode_frame(true, 2, payload, true, mask)
  match ws_parse_frame(encoded) {
    Some((frame, consumed)) => {
      assert_eq(frame.fin, true)
      assert_eq(frame.opcode, 2)
      assert_eq(frame.masked, true)
      assert_eq(frame.payload.length(), 5)
      // Payload should be unmasked back to original
      assert_eq(frame.payload[0].to_int(), 0xDE)
      assert_eq(frame.payload[1].to_int(), 0xAD)
      assert_eq(frame.payload[2].to_int(), 0xBE)
      assert_eq(frame.payload[3].to_int(), 0xEF)
      assert_eq(frame.payload[4].to_int(), 0x01)
      assert_eq(consumed, encoded.length())
    }
    None => abort("expected Some")
  }
}

///|
test "ws_parse_frame: empty payload" {
  let payload = Bytes::from_array([])
  let encoded = ws_encode_frame(true, 1, payload, false, b"\x00\x00\x00\x00")
  match ws_parse_frame(encoded) {
    Some((frame, _)) => assert_eq(frame.payload.length(), 0)
    None => abort("expected Some")
  }
}

///|
test "ws_parse_frame: 126-byte payload round-trip" {
  let arr : Array[Byte] = Array::make(126, 0x42)
  let payload = Bytes::from_array(arr)
  let encoded = ws_encode_frame(true, 2, payload, false, b"\x00\x00\x00\x00")
  match ws_parse_frame(encoded) {
    Some((frame, _)) => {
      assert_eq(frame.payload.length(), 126)
      for i = 0; i < 126; i = i + 1 {
        assert_eq(frame.payload[i].to_int(), 0x42)
      }
    }
    None => abort("expected Some")
  }
}

///|
test "ws_parse_frame: incomplete data returns None" {
  let data = Bytes::from_array([0x81]) // Only 1 byte
  assert_true(ws_parse_frame(data) is None)
}

///|
test "ws_parse_frame: incomplete extended length returns None" {
  // Frame claiming 126-byte payload but only 3 bytes total
  let data = Bytes::from_array([0x82, 0x7E, 0x00])
  assert_true(ws_parse_frame(data) is None)
}

///|
test "ws_parse_frame: incomplete masked frame returns None" {
  // Masked frame but no mask key
  let data = Bytes::from_array([0x81, 0x81])
  assert_true(ws_parse_frame(data) is None)
}

///|
test "ws_parse_frame: FIN=false fragment" {
  let payload = Bytes::from_array([0x01])
  let encoded = ws_encode_frame(false, 0, payload, false, b"\x00\x00\x00\x00")
  match ws_parse_frame(encoded) {
    Some((frame, _)) => assert_eq(frame.fin, false)
    None => abort("expected Some")
  }
}

// ===========================================================================
// Convenience frame builders tests
// ===========================================================================

///|
test "ws_text_frame: creates valid text frame" {
  let frame = ws_text_frame("Hi")
  match ws_parse_frame(frame) {
    Some((parsed, _)) => {
      assert_eq(parsed.opcode, 1)
      assert_eq(parsed.fin, true)
      assert_eq(parsed.masked, false)
    }
    None => abort("expected Some")
  }
}

///|
test "ws_text_frame: empty string" {
  let frame = ws_text_frame("")
  match ws_parse_frame(frame) {
    Some((parsed, _)) => {
      assert_eq(parsed.opcode, 1)
      assert_eq(parsed.payload.length(), 0)
    }
    None => abort("expected Some")
  }
}

///|
test "ws_binary_frame: creates valid binary frame" {
  let data = Bytes::from_array([0x01, 0x02, 0x03])
  let frame = ws_binary_frame(data)
  match ws_parse_frame(frame) {
    Some((parsed, _)) => {
      assert_eq(parsed.opcode, 2)
      assert_eq(parsed.fin, true)
      assert_eq(parsed.payload.length(), 3)
    }
    None => abort("expected Some")
  }
}

///|
test "ws_close_frame: with status code" {
  let frame = ws_close_frame(Some(1000))
  match ws_parse_frame(frame) {
    Some((parsed, _)) => {
      assert_eq(parsed.opcode, 8)
      assert_eq(parsed.fin, true)
      assert_eq(parsed.payload.length(), 2)
      // Status code 1000 = 0x03E8
      assert_eq(parsed.payload[0].to_int(), 0x03)
      assert_eq(parsed.payload[1].to_int(), 0xE8)
    }
    None => abort("expected Some")
  }
}

///|
test "ws_close_frame: without status code" {
  let frame = ws_close_frame(None)
  match ws_parse_frame(frame) {
    Some((parsed, _)) => {
      assert_eq(parsed.opcode, 8)
      assert_eq(parsed.payload.length(), 0)
    }
    None => abort("expected Some")
  }
}

///|
test "ws_ping_frame: with payload" {
  let payload = Bytes::from_array([0x01, 0x02])
  let frame = ws_ping_frame(payload)
  match ws_parse_frame(frame) {
    Some((parsed, _)) => {
      assert_eq(parsed.opcode, 9)
      assert_eq(parsed.payload.length(), 2)
    }
    None => abort("expected Some")
  }
}

///|
test "ws_pong_frame: with payload" {
  let payload = Bytes::from_array([0x03, 0x04])
  let frame = ws_pong_frame(payload)
  match ws_parse_frame(frame) {
    Some((parsed, _)) => {
      assert_eq(parsed.opcode, 10)
      assert_eq(parsed.payload.length(), 2)
    }
    None => abort("expected Some")
  }
}

///|
test "ws_pong_frame: empty payload" {
  let frame = ws_pong_frame(Bytes::from_array([]))
  match ws_parse_frame(frame) {
    Some((parsed, _)) => {
      assert_eq(parsed.opcode, 10)
      assert_eq(parsed.payload.length(), 0)
    }
    None => abort("expected Some")
  }
}
