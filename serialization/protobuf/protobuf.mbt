/// Protocol Buffers encoding/decoding.
///
/// Implements the binary wire format for Protocol Buffers (protobuf).
/// Supports varint, fixed32, fixed64, length-delimited, and zigzag encoding.
///
/// ## Wire types
///
/// - 0: Varint (int32, int64, uint32, uint64, sint32, sint64, bool, enum)
/// - 1: 64-bit (fixed64, sfixed64, double)
/// - 2: Length-delimited (string, bytes, embedded messages, packed repeated)
/// - 5: 32-bit (fixed32, sfixed32, float)
///
/// ## References
///
/// - Protocol Buffers Encoding: https://protobuf.dev/programming-guides/encoding/
///
/// `proof-enabled` is `false`.

///|
/// Encode a varint (unsigned integer) to bytes.
pub fn encode_varint(value : UInt64) -> Bytes {
  let buf : Array[Byte] = []
  let mut v = value
  while v >= 0x80UL {
    buf.push((v & 0x7FUL).to_byte() | 0x80)
    v = v >> 7
  }
  buf.push(v.to_byte())
  Bytes::from_array(buf)
}

///|
/// Decode a varint from bytes at given offset.
/// Returns (value, new_offset) or None on error.
pub fn decode_varint(data : Bytes, offset : Int) -> (UInt64, Int)? {
  let mut result = 0UL
  let mut shift = 0
  let mut pos = offset
  while pos < data.length() {
    let b = data[pos]
    result = result.lor((b & 0x7F).to_uint64() << shift)
    pos = pos + 1
    if (b & 0x80) == 0 {
      return Some((result, pos))
    }
    shift = shift + 7
    if shift >= 64 {
      return None
    }
  }
  None
}

///|
/// Zigzag encode a 32-bit signed integer.
pub fn zigzag_encode32(n : Int) -> UInt {
  (n << 1).reinterpret_as_uint().lxor((n >> 31).reinterpret_as_uint())
}

///|
/// Zigzag decode a 32-bit unsigned integer.
pub fn zigzag_decode32(n : UInt) -> Int {
  (n.reinterpret_as_int() >> 1) ^ -(n.reinterpret_as_int() & 1)
}

///|
/// Zigzag encode a 64-bit signed integer.
pub fn zigzag_encode64(n : Int64) -> UInt64 {
  (n << 1).reinterpret_as_uint64().lxor((n >> 63).reinterpret_as_uint64())
}

///|
/// Zigzag decode a 64-bit unsigned integer.
pub fn zigzag_decode64(n : UInt64) -> Int64 {
  (n.reinterpret_as_int64() >> 1) ^ -(n.reinterpret_as_int64() & 1L)
}

///|
/// Encode a field tag (field_number, wire_type).
pub fn encode_tag(field_number : Int, wire_type : Int) -> Bytes {
  let tag = (field_number.to_uint64() << 3).lor(wire_type.to_uint64())
  encode_varint(tag)
}

///|
/// Decode a field tag. Returns (field_number, wire_type, new_offset).
pub fn decode_tag(data : Bytes, offset : Int) -> (Int, Int, Int)? {
  match decode_varint(data, offset) {
    None => None
    Some((tag, np)) => {
      let wire_type = (tag & 7UL).to_int()
      let field_number = (tag >> 3).to_int()
      Some((field_number, wire_type, np))
    }
  }
}

///|
/// Encode a length-delimited field (string, bytes, embedded message).
pub fn encode_length_delimited(field_number : Int, data : Bytes) -> Bytes {
  let tag = encode_tag(field_number, 2)
  let len = encode_varint(data.length().to_uint64())
  let result : Array[Byte] = []
  for i = 0; i < tag.length(); i = i + 1 {
    result.push(tag[i])
  }
  for i = 0; i < len.length(); i = i + 1 {
    result.push(len[i])
  }
  for i = 0; i < data.length(); i = i + 1 {
    result.push(data[i])
  }
  Bytes::from_array(result)
}

///|
/// Encode a varint field (int32, uint32, int64, uint64, bool, enum).
pub fn encode_varint_field(field_number : Int, value : UInt64) -> Bytes {
  let tag = encode_tag(field_number, 0)
  let val = encode_varint(value)
  let result : Array[Byte] = []
  for i = 0; i < tag.length(); i = i + 1 {
    result.push(tag[i])
  }
  for i = 0; i < val.length(); i = i + 1 {
    result.push(val[i])
  }
  Bytes::from_array(result)
}

///|
/// Encode a 32-bit fixed field.
pub fn encode_fixed32_field(field_number : Int, value : UInt) -> Bytes {
  let tag = encode_tag(field_number, 5)
  let result : Array[Byte] = []
  for i = 0; i < tag.length(); i = i + 1 {
    result.push(tag[i])
  }
  result.push((value & 0xFFU).to_byte())
  result.push(((value >> 8) & 0xFFU).to_byte())
  result.push(((value >> 16) & 0xFFU).to_byte())
  result.push(((value >> 24) & 0xFFU).to_byte())
  Bytes::from_array(result)
}

///|
/// Encode a 64-bit fixed field.
pub fn encode_fixed64_field(field_number : Int, value : UInt64) -> Bytes {
  let tag = encode_tag(field_number, 1)
  let result : Array[Byte] = []
  for i = 0; i < tag.length(); i = i + 1 {
    result.push(tag[i])
  }
  for i = 0; i < 8; i = i + 1 {
    result.push(((value >> (i * 8)) & 0xFFUL).to_int().to_byte())
  }
  Bytes::from_array(result)
}

///|
/// Encode a string field.
pub fn encode_string_field(field_number : Int, s : String) -> Bytes {
  encode_length_delimited(field_number, @utils.string_to_bytes(s))
}

///|
/// A decoded protobuf field.
pub struct ProtoField {
  field_number : Int
  wire_type : Int
  data : Bytes // raw field data (varint value or length-delimited content)
}

///|
/// Decode all fields from a protobuf message.
pub fn decode_message(data : Bytes) -> Array[ProtoField]? {
  let fields : Array[ProtoField] = []
  let mut pos = 0
  while pos < data.length() {
    match decode_tag(data, pos) {
      None => return None
      Some((fn_, wt, np)) => {
        pos = np
        match wt {
          0 =>
            // Varint
            match decode_varint(data, pos) {
              None => return None
              Some((v, vp)) => {
                let buf : Array[Byte] = []
                let mut val = v
                while val >= 0x80UL {
                  buf.push((val & 0x7FUL).to_byte() | 0x80)
                  val = val >> 7
                }
                buf.push(val.to_byte())
                fields.push({
                  field_number: fn_,
                  wire_type: wt,
                  data: Bytes::from_array(buf),
                })
                pos = vp
              }
            }
          1 => {
            // 64-bit
            if pos + 8 > data.length() {
              return None
            }
            let buf : Array[Byte] = []
            for i = 0; i < 8; i = i + 1 {
              buf.push(data[pos + i])
            }
            fields.push({
              field_number: fn_,
              wire_type: wt,
              data: Bytes::from_array(buf),
            })
            pos = pos + 8
          }
          2 =>
            // Length-delimited
            match decode_varint(data, pos) {
              None => return None
              Some((len, lp)) => {
                pos = lp
                let ilen = len.to_int()
                if pos + ilen > data.length() {
                  return None
                }
                let buf : Array[Byte] = []
                for i = 0; i < ilen; i = i + 1 {
                  buf.push(data[pos + i])
                }
                fields.push({
                  field_number: fn_,
                  wire_type: wt,
                  data: Bytes::from_array(buf),
                })
                pos = pos + ilen
              }
            }
          5 => {
            // 32-bit
            if pos + 4 > data.length() {
              return None
            }
            let buf : Array[Byte] = []
            for i = 0; i < 4; i = i + 1 {
              buf.push(data[pos + i])
            }
            fields.push({
              field_number: fn_,
              wire_type: wt,
              data: Bytes::from_array(buf),
            })
            pos = pos + 4
          }
          _ => return None
        }
      }
    }
  }
  Some(fields)
}

///|
test "protobuf: varint encode/decode" {
  let encoded = encode_varint(300UL)
  assert_eq(encoded.length(), 2)
  let decoded = decode_varint(encoded, 0)
  match decoded {
    Some((v, _)) => assert_eq(v, 300UL)
    None => assert_true(false)
  }
}

///|
test "protobuf: varint single byte" {
  let encoded = encode_varint(1UL)
  assert_eq(encoded.length(), 1)
  let decoded = decode_varint(encoded, 0)
  match decoded {
    Some((v, _)) => assert_eq(v, 1UL)
    None => assert_true(false)
  }
}

///|
test "protobuf: zigzag encode/decode 32" {
  assert_eq(zigzag_encode32(0), 0U)
  assert_eq(zigzag_encode32(-1), 1U)
  assert_eq(zigzag_encode32(1), 2U)
  assert_eq(zigzag_encode32(-2), 3U)
  assert_eq(zigzag_decode32(0U), 0)
  assert_eq(zigzag_decode32(1U), -1)
  assert_eq(zigzag_decode32(2U), 1)
  assert_eq(zigzag_decode32(3U), -2)
}

///|
test "protobuf: string field roundtrip" {
  let encoded = encode_string_field(1, "hello")
  match decode_message(encoded) {
    Some(fields) => {
      assert_eq(fields.length(), 1)
      assert_eq(fields[0].field_number, 1)
      assert_eq(fields[0].wire_type, 2)
      let s = @utils.bytes_to_string(fields[0].data)
      assert_eq(s, "hello")
    }
    None => assert_true(false)
  }
}

///|
test "protobuf: varint field roundtrip" {
  let encoded = encode_varint_field(5, 123456UL)
  match decode_message(encoded) {
    Some(fields) => {
      assert_eq(fields.length(), 1)
      assert_eq(fields[0].field_number, 5)
      assert_eq(fields[0].wire_type, 0)
      match decode_varint(fields[0].data, 0) {
        Some((v, _)) => assert_eq(v, 123456UL)
        None => assert_true(false)
      }
    }
    None => assert_true(false)
  }
}

///|
test "protobuf: multiple fields" {
  let msg : Array[Byte] = []
  let f1 = encode_varint_field(1, 42UL)
  let f2 = encode_string_field(2, "test")
  for i = 0; i < f1.length(); i = i + 1 {
    msg.push(f1[i])
  }
  for i = 0; i < f2.length(); i = i + 1 {
    msg.push(f2[i])
  }
  match decode_message(Bytes::from_array(msg)) {
    Some(fields) => {
      assert_eq(fields.length(), 2)
      assert_eq(fields[0].field_number, 1)
      assert_eq(fields[1].field_number, 2)
    }
    None => assert_true(false)
  }
}
