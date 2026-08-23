/// Cap'n Proto — Zero-Copy Serialization
///
/// Cap'n Proto encodes data in a packed binary format that can be
/// accessed directly without deserialization. This simplified version
/// implements basic struct and list encoding.
///
/// `proof-enabled` is `false`.

///|
/// Cap'n Proto message builder.
pub struct CapnpBuilder {
  segments : Array[Array[Int]]
  current_segment : Int
}

///|
/// Create a new Cap'n Proto builder.
pub fn CapnpBuilder::new() -> CapnpBuilder {
  { segments: [Array::make(64, 0)], current_segment: 0 }
}

///|
/// Write a 64-bit integer (little-endian) at position.
pub fn CapnpBuilder::write_int64(self : CapnpBuilder, value : Int) -> Unit {
  let seg = self.segments[self.current_segment]
  let pos = seg[0] // Use first 8 bytes as position counter
  // Ensure capacity (simplified)
  if pos + 8 < seg.length() {
    seg[pos + 0] = value & 0xFF
    seg[pos + 1] = (value >> 8) & 0xFF
    seg[pos + 2] = (value >> 16) & 0xFF
    seg[pos + 3] = (value >> 24) & 0xFF
    seg[0] = pos + 8
  }
}

///|
/// Serialize the message to bytes.
pub fn CapnpBuilder::to_bytes(self : CapnpBuilder) -> Bytes {
  let seg = self.segments[self.current_segment]
  let len = seg[0]
  let arr = Array::make(len, b'\x00')
  for i = 0; i < len; i = i + 1 {
    arr[i] = seg[i].to_byte()
  }
  Bytes::from_array(arr)
}

///|
/// Read a 64-bit integer from Cap'n Proto data.
pub fn capnp_read_int64(data : Bytes, offset : Int) -> Int {
  if offset + 8 > data.length() {
    return 0
  }
  (data[offset].to_int() & 0xFF) |
  ((data[offset + 1].to_int() & 0xFF) << 8) |
  ((data[offset + 2].to_int() & 0xFF) << 16) |
  ((data[offset + 3].to_int() & 0xFF) << 24)
}
