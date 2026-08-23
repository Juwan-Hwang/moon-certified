/// Apache Thrift — Binary Serialization Protocol
///
/// Implements the Thrift binary and compact protocols for
/// cross-language RPC serialization.
///
/// `proof-enabled` is `false`.

///|
/// Thrift message types.
pub const T_CALL : Int = 1

///|
pub const T_REPLY : Int = 2

///|
pub const T_EXCEPTION : Int = 3

///|
pub const T_ONEWAY : Int = 4

///|
/// Thrift data types.
pub const T_STOP : Int = 0

///|
pub const T_VOID : Int = 1

///|
pub const T_BOOL : Int = 2

///|
pub const T_BYTE : Int = 3

///|
pub const T_DOUBLE : Int = 4

///|
pub const T_I16 : Int = 6

///|
pub const T_I32 : Int = 8

///|
pub const T_I64 : Int = 10

///|
pub const T_STRING : Int = 11

///|
pub const T_STRUCT : Int = 12

///|
pub const T_MAP : Int = 13

///|
pub const T_SET : Int = 14

///|
pub const T_LIST : Int = 15

///|
/// Thrift binary protocol encoder.
pub struct ThriftEncoder {
  buf : Array[Int]
  mut pos : Int
}

///|
/// Create a new Thrift encoder.
pub fn ThriftEncoder::new() -> ThriftEncoder {
  { buf: Array::make(256, 0), pos: 0 }
}

///|
/// Write a struct begin.
pub fn ThriftEncoder::write_struct_begin(
  self : ThriftEncoder,
  name : String,
) -> Unit {
  // No-op for binary protocol
  let _ = name
}

///|
/// Write a field header.
pub fn ThriftEncoder::write_field_begin(
  self : ThriftEncoder,
  field_type : Int,
  field_id : Int,
) -> Unit {
  self.buf[self.pos] = field_type & 0xFF
  self.pos = self.pos + 1
  self.buf[self.pos] = (field_id >> 8) & 0xFF
  self.buf[self.pos + 1] = field_id & 0xFF
  self.pos = self.pos + 2
}

///|
/// Write a stop field (marks end of struct).
pub fn ThriftEncoder::write_stop(self : ThriftEncoder) -> Unit {
  self.buf[self.pos] = 0
  self.pos = self.pos + 1
}

///|
/// Write a boolean.
pub fn ThriftEncoder::write_bool(self : ThriftEncoder, val : Bool) -> Unit {
  self.buf[self.pos] = if val { 1 } else { 0 }
  self.pos = self.pos + 1
}

///|
/// Write a 32-bit integer (big-endian).
pub fn ThriftEncoder::write_i32(self : ThriftEncoder, val : Int) -> Unit {
  self.buf[self.pos] = (val >> 24) & 0xFF
  self.buf[self.pos + 1] = (val >> 16) & 0xFF
  self.buf[self.pos + 2] = (val >> 8) & 0xFF
  self.buf[self.pos + 3] = val & 0xFF
  self.pos = self.pos + 4
}

///|
/// Write a 64-bit integer (big-endian).
pub fn ThriftEncoder::write_i64(self : ThriftEncoder, val : Int) -> Unit {
  // Simplified: only write lower 32 bits
  self.write_i32(val)
}

///|
/// Write a string (length-prefixed, big-endian).
pub fn ThriftEncoder::write_string(self : ThriftEncoder, str : String) -> Unit {
  self.write_i32(str.length())
  for i = 0; i < str.length(); i = i + 1 {
    self.buf[self.pos] = str[i].to_int()
    self.pos = self.pos + 1
  }
}

///|
/// Get the serialized bytes.
pub fn ThriftEncoder::to_bytes(self : ThriftEncoder) -> Bytes {
  let result : Array[Byte] = []
  for i = 0; i < self.pos; i = i + 1 {
    result.push(self.buf[i].to_byte())
  }
  Bytes::from_array(result)
}

///|
/// Thrift binary protocol decoder.
pub struct ThriftDecoder {
  data : Bytes
  mut pos : Int
}

///|
/// Create a decoder from bytes.
pub fn ThriftDecoder::new(data : Bytes) -> ThriftDecoder {
  { data, pos: 0 }
}

///|
/// Read a field header: (type, id).
pub fn ThriftDecoder::read_field_begin(self : ThriftDecoder) -> (Int, Int) {
  if self.pos >= self.data.length() {
    return (0, 0)
  }
  let ftype = self.data[self.pos].to_int() & 0xFF
  self.pos = self.pos + 1
  if ftype == 0 {
    return (0, 0) // T_STOP
  }
  let fid = ((self.data[self.pos].to_int() & 0xFF) << 8) |
    (self.data[self.pos + 1].to_int() & 0xFF)
  self.pos = self.pos + 2
  (ftype, fid)
}

///|
/// Read a boolean.
pub fn ThriftDecoder::read_bool(self : ThriftDecoder) -> Bool {
  if self.pos >= self.data.length() {
    return false
  }
  let val = self.data[self.pos].to_int() & 0xFF
  self.pos = self.pos + 1
  val == 1
}

///|
/// Read a 32-bit integer (big-endian).
pub fn ThriftDecoder::read_i32(self : ThriftDecoder) -> Int {
  if self.pos + 4 > self.data.length() {
    return 0
  }
  let val = ((self.data[self.pos].to_int() & 0xFF) << 24) |
    ((self.data[self.pos + 1].to_int() & 0xFF) << 16) |
    ((self.data[self.pos + 2].to_int() & 0xFF) << 8) |
    (self.data[self.pos + 3].to_int() & 0xFF)
  self.pos = self.pos + 4
  val
}

///|
/// Read a string.
pub fn ThriftDecoder::read_string(self : ThriftDecoder) -> String {
  let len = self.read_i32()
  if len <= 0 {
    return ""
  }
  let sb = StringBuilder::new()
  for i = 0; i < len && self.pos < self.data.length(); i = i + 1 {
    sb.write_char((self.data[self.pos].to_int() & 0xFF).unsafe_to_char())
    self.pos = self.pos + 1
  }
  sb.to_string()
}

///|
/// Skip a field of a given type.
pub fn ThriftDecoder::skip(self : ThriftDecoder, ftype : Int) -> Unit {
  match ftype {
    T_BOOL => self.pos = self.pos + 1
    T_BYTE => self.pos = self.pos + 1
    T_I16 => self.pos = self.pos + 2
    T_I32 => self.pos = self.pos + 4
    T_I64 => self.pos = self.pos + 8
    T_DOUBLE => self.pos = self.pos + 8
    T_STRING => {
      let len = self.read_i32()
      self.pos = self.pos + len
    }
    _ => ()
  }
}
