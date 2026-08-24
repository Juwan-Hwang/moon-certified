/// Avro — Schema-Based Serialization
///
/// Apache Avro is a data serialization system that uses JSON schemas
/// to describe data structures and a compact binary encoding.
///
/// `proof-enabled` is `false`.

///|
/// Avro data types.
pub enum AvroType {
  Null
  Boolean
  Int
  Long
  Float
  Double
  Bytes
  String
  Record
  Enum
  Array
  Map
  Union
}

///|
/// Avro encoder.
pub struct AvroEncoder {
  buf : Array[Int]
  mut pos : Int
}

///|
/// Create a new Avro encoder.
pub fn AvroEncoder::new() -> AvroEncoder {
  { buf: Array::make(256, 0), pos: 0 }
}

///|
/// Encode a boolean.
pub fn AvroEncoder::encode_bool(self : AvroEncoder, val : Bool) -> Unit {
  self.buf[self.pos] = if val { 1 } else { 0 }
  self.pos = self.pos + 1
}

///|
/// Encode a 32-bit integer (zigzag encoding).
pub fn AvroEncoder::encode_int(self : AvroEncoder, val : Int) -> Unit {
  let zigzag = (val << 1) ^ (val >> 31)
  let mut n = zigzag
  while (n & 0xFFFFFF80) != 0 {
    self.buf[self.pos] = (n & 0x7F) | 0x80
    self.pos = self.pos + 1
    n = n >> 7
  }
  self.buf[self.pos] = n & 0x7F
  self.pos = self.pos + 1
}

///|
/// Encode a 64-bit long (zigzag + varint).
pub fn AvroEncoder::encode_long(self : AvroEncoder, val : Int) -> Unit {
  self.encode_int(val) // Simplified: use same as int
}

///|
/// Encode a string (length-prefixed).
pub fn AvroEncoder::encode_string(self : AvroEncoder, str : String) -> Unit {
  self.encode_int(str.length())
  for i = 0; i < str.length(); i = i + 1 {
    self.buf[self.pos] = str[i].to_int()
    self.pos = self.pos + 1
  }
}

///|
/// Get the serialized bytes.
pub fn AvroEncoder::to_bytes(self : AvroEncoder) -> Bytes {
  let result : Array[Byte] = []
  for i = 0; i < self.pos; i = i + 1 {
    result.push(self.buf[i].to_byte())
  }
  Bytes::from_array(result)
}

///|
/// Avro decoder.
pub struct AvroDecoder {
  data : Bytes
  mut pos : Int
}

///|
/// Create a decoder from bytes.
pub fn AvroDecoder::new(data : Bytes) -> AvroDecoder {
  { data, pos: 0 }
}

///|
/// Decode a boolean.
pub fn AvroDecoder::decode_bool(self : AvroDecoder) -> Bool {
  if self.pos >= self.data.length() {
    return false
  }
  let val = self.data[self.pos].to_int() & 0xFF
  self.pos = self.pos + 1
  val == 1
}

///|
/// Decode a 32-bit integer (zigzag + varint).
pub fn AvroDecoder::decode_int(self : AvroDecoder) -> Int {
  let mut result = 0
  let mut shift = 0
  let mut b = 0
  let mut continue_loop = true
  while continue_loop {
    if self.pos >= self.data.length() {
      break
    }
    b = self.data[self.pos].to_int() & 0xFF
    self.pos = self.pos + 1
    result = result | ((b & 0x7F) << shift)
    shift = shift + 7
    if (b & 0x80) == 0 {
      continue_loop = false
    }
  }
  // Zigzag decode
  (result >> 1) ^ -(result & 1)
}

///|
/// Decode a string.
pub fn AvroDecoder::decode_string(self : AvroDecoder) -> String {
  let len = self.decode_int()
  let sb = StringBuilder::new()
  for i = 0; i < len; i = i + 1 {
    sb.write_char((self.data[self.pos].to_int() & 0xFF).unsafe_to_char())
    self.pos = self.pos + 1
  }
  sb.to_string()
}

///|
/// All AvroType variants (internal type registry).
fn _all_avro_types() -> Array[AvroType] {
  [
    Null, Boolean, Int, Long, Float, Double, Bytes, String, Record, Enum, Array,
    Map, Union,
  ]
}
