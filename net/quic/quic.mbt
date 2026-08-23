/// QUIC Packet Format (RFC 9000)
///
/// Implements QUIC long and short header packet format.
///
/// `proof-enabled` is `false`.

///|
/// QUIC long header packet.
pub struct QuicLongHeader {
  header_form : Int
  fixed_bit : Int
  long_packet_type : Int
  version : Int
  dcid : Bytes
  scid : Bytes
  payload : Bytes
}

///|
/// Encode a QUIC long header packet.
pub fn quic_encode_long_header(
  packet_type : Int,
  version : Int,
  dcid : Bytes,
  scid : Bytes,
  payload : Bytes,
) -> Bytes {
  let buf : Array[Byte] = []
  let b0 = 0xC0 | ((packet_type & 0x03) << 4) | 0x03
  buf.push(b0.to_byte())
  buf.push(((version >> 24) & 0xFF).to_byte())
  buf.push(((version >> 16) & 0xFF).to_byte())
  buf.push(((version >> 8) & 0xFF).to_byte())
  buf.push((version & 0xFF).to_byte())
  buf.push((dcid.length() & 0xFF).to_byte())
  for i = 0; i < dcid.length(); i = i + 1 {
    buf.push(dcid[i])
  }
  buf.push((scid.length() & 0xFF).to_byte())
  for i = 0; i < scid.length(); i = i + 1 {
    buf.push(scid[i])
  }
  for i = 0; i < payload.length(); i = i + 1 {
    buf.push(payload[i])
  }
  Bytes::from_array(buf)
}

///|
/// Parse a QUIC long header from raw bytes.
pub fn quic_parse_long_header(data : Bytes) -> QuicLongHeader? {
  if data.length() < 7 {
    return None
  }
  let b0 = data[0].to_int() & 0xFF
  if (b0 & 0x80) == 0 {
    return None
  }
  let packet_type = (b0 >> 4) & 0x03
  let version = ((data[1].to_int() & 0xFF) << 24) |
    ((data[2].to_int() & 0xFF) << 16) |
    ((data[3].to_int() & 0xFF) << 8) |
    (data[4].to_int() & 0xFF)
  let dcid_len = data[5].to_int() & 0xFF
  if data.length() < 6 + dcid_len {
    return None
  }
  let dcid_buf : Array[Byte] = []
  for i = 0; i < dcid_len; i = i + 1 {
    dcid_buf.push(data[6 + i])
  }
  let dcid = Bytes::from_array(dcid_buf)
  let scid_offset = 6 + dcid_len
  if data.length() < scid_offset + 1 {
    return None
  }
  let scid_len = data[scid_offset].to_int() & 0xFF
  if data.length() < scid_offset + 1 + scid_len {
    return None
  }
  let scid_buf : Array[Byte] = []
  for i = 0; i < scid_len; i = i + 1 {
    scid_buf.push(data[scid_offset + 1 + i])
  }
  let scid = Bytes::from_array(scid_buf)
  let payload_offset = scid_offset + 1 + scid_len
  let payload_len = data.length() - payload_offset
  let payload_buf : Array[Byte] = []
  for i = 0; i < payload_len; i = i + 1 {
    payload_buf.push(data[payload_offset + i])
  }
  let payload = Bytes::from_array(payload_buf)
  Some({
    header_form: 1,
    fixed_bit: 1,
    long_packet_type: packet_type,
    version,
    dcid,
    scid,
    payload,
  })
}
