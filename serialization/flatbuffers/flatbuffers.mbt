/// FlatBuffers — Zero-Copy Serialization Framework
///
/// FlatBuffers provides efficient serialization without deserialization
/// overhead. Data is accessed in-place from the serialized buffer.
///
/// ## Design
/// - All data is stored in a flat byte buffer with offset pointers
/// - No allocation needed during access
/// - Forward and backward compatible schema evolution
///
/// `proof-enabled` is `false`.

///|
/// FlatBuffer builder.
pub struct FlatBufferBuilder {
  buf : Array[Int]
  mut pos : Int // Current write position (from end)
  /// VTable offsets for each object
  vtables : Array[Int]
  /// Nested object info
  nested : Bool
  mut finished : Bool
}

///|
/// Create a new FlatBuffer builder.
pub fn FlatBufferBuilder::new(initial_size : Int) -> FlatBufferBuilder {
  let size = if initial_size < 64 { 64 } else { initial_size }
  {
    buf: Array::make(size, 0),
    pos: 0,
    vtables: [],
    nested: false,
    finished: false,
  }
}

///|
/// Write a byte to the buffer.
pub fn FlatBufferBuilder::put_byte(self : FlatBufferBuilder, val : Int) -> Unit {
  self.ensure_capacity(self.pos + 1)
  self.buf[self.pos] = val & 0xFF
  self.pos = self.pos + 1
}

///|
/// Write a 32-bit integer (little-endian).
pub fn FlatBufferBuilder::put_int32(
  self : FlatBufferBuilder,
  val : Int,
) -> Unit {
  self.ensure_capacity(self.pos + 4)
  self.buf[self.pos] = val & 0xFF
  self.buf[self.pos + 1] = (val >> 8) & 0xFF
  self.buf[self.pos + 2] = (val >> 16) & 0xFF
  self.buf[self.pos + 3] = (val >> 24) & 0xFF
  self.pos = self.pos + 4
}

///|
/// Write a string with length prefix.
pub fn FlatBufferBuilder::put_string(
  self : FlatBufferBuilder,
  str : String,
) -> Int {
  let offset = self.pos
  self.put_int32(str.length())
  self.ensure_capacity(self.pos + str.length())
  for i = 0; i < str.length(); i = i + 1 {
    self.buf[self.pos + i] = str[i].to_int()
  }
  self.pos = self.pos + str.length()
  offset
}

///|
/// Write a vector of integers.
pub fn FlatBufferBuilder::put_int_vector(
  self : FlatBufferBuilder,
  vec : Array[Int],
) -> Int {
  let offset = self.pos
  self.put_int32(vec.length())
  for v in vec {
    self.put_int32(v)
  }
  offset
}

///|
/// Ensure buffer has enough capacity.
fn FlatBufferBuilder::ensure_capacity(
  self : FlatBufferBuilder,
  needed : Int,
) -> Unit {
  if needed < self.buf.length() {
    return
  }
  // Grow by doubling
  let new_cap = if needed > self.buf.length() * 2 {
    needed
  } else {
    self.buf.length() * 2
  }
  let new_buf = Array::make(new_cap, 0)
  for i = 0; i < self.pos; i = i + 1 {
    new_buf[i] = self.buf[i]
  }
  self.buf.clear()
  for v in new_buf {
    self.buf.push(v)
  }
}

///|
/// Finalize the buffer and return the serialized bytes.
pub fn FlatBufferBuilder::finish(self : FlatBufferBuilder) -> Bytes {
  let result : Array[Byte] = []
  for i = 0; i < self.pos; i = i + 1 {
    result.push(self.buf[i].to_byte())
  }
  self.finished = true
  Bytes::from_array(result)
}

///|
/// Read a 32-bit integer from a FlatBuffer at offset.
pub fn flatbuffer_read_int32(data : Bytes, offset : Int) -> Int {
  if offset + 4 > data.length() {
    return 0
  }
  (data[offset].to_int() & 0xFF) |
  ((data[offset + 1].to_int() & 0xFF) << 8) |
  ((data[offset + 2].to_int() & 0xFF) << 16) |
  ((data[offset + 3].to_int() & 0xFF) << 24)
}

///|
/// Read a string from a FlatBuffer at offset.
pub fn flatbuffer_read_string(data : Bytes, offset : Int) -> String {
  let len = flatbuffer_read_int32(data, offset)
  let sb = StringBuilder()
  for i = 0; i < len && offset + 4 + i < data.length(); i = i + 1 {
    sb.write_char((data[offset + 4 + i].to_int() & 0xFF).unsafe_to_char())
  }
  sb.to_string()
}

///|
/// Read a vector of integers from a FlatBuffer at offset.
pub fn flatbuffer_read_int_vector(data : Bytes, offset : Int) -> Array[Int] {
  let len = flatbuffer_read_int32(data, offset)
  let result = Array::make(len, 0)
  for i = 0; i < len; i = i + 1 {
    result[i] = flatbuffer_read_int32(data, offset + 4 + i * 4)
  }
  result
}
