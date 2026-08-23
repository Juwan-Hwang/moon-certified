///|
/// QUIC long header packet tests (RFC 9000).
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
/// Encode then parse and verify every field round-trips.
fn roundtrip(
  pt : Int,
  ver : Int,
  dcid : Bytes,
  scid : Bytes,
  payload : Bytes,
) -> Unit {
  let enc = quic_encode_long_header(pt, ver, dcid, scid, payload)
  let h = unwrap_or_fail(quic_parse_long_header(enc))
  if h.header_form != 1 {
    abort("roundtrip: header_form != 1")
  }
  if h.fixed_bit != 1 {
    abort("roundtrip: fixed_bit != 1")
  }
  if h.long_packet_type != pt {
    abort("roundtrip: long_packet_type mismatch")
  }
  if h.version != ver {
    abort("roundtrip: version mismatch")
  }
  if h.dcid != dcid {
    abort("roundtrip: dcid mismatch")
  }
  if h.scid != scid {
    abort("roundtrip: scid mismatch")
  }
  if h.payload != payload {
    abort("roundtrip: payload mismatch")
  }
}

// ---------------------------------------------------------------------------
// Wire format / encode correctness
// ---------------------------------------------------------------------------

///|
test "quic_encode_wire_format" {
  let dcid = Bytes::from_array([b'\xaa'])
  let scid = Bytes::from_array([b'\xbb', b'\xcc'])
  let payload = Bytes::from_array([b'\x01', b'\x02'])
  let enc = quic_encode_long_header(1, 0x00000001, dcid, scid, payload)
  // b0 = 0xC0 | (1<<4) | 0x03 = 0xD3
  let expected = Bytes::from_array([
    b'\xd3', // b0
     b'\x00', b'\x00', b'\x00', b'\x01', // version
     b'\x01', b'\xaa', // dcid_len + dcid
     b'\x02', b'\xbb', b'\xcc', // scid_len + scid
     b'\x01', b'\x02', // payload
  ])
  assert_eq(enc, expected)
}

///|
test "quic_roundtrip_all_packet_types" {
  let dcid = Bytes::from_array([b'\xde', b'\xad'])
  let scid = Bytes::from_array([b'\xbe', b'\xef', b'\x00'])
  let payload = Bytes::from_array([b'\x10', b'\x20', b'\x30'])
  for pt in 0..<4 {
    roundtrip(pt, 0x01020304, dcid, scid, payload)
  }
}

///|
test "quic_roundtrip_empty_ids" {
  // empty dcid and scid, empty payload
  roundtrip(0, 0xffffffff, b"", b"", b"")
}

///|
test "quic_roundtrip_various_lengths" {
  let dcid = Bytes::from_array(Array::make(8, b'\x11'))
  let scid = Bytes::from_array(Array::make(4, b'\x22'))
  let payload = Bytes::from_array(Array::make(50, b'\x33'))
  roundtrip(2, 1, dcid, scid, payload)
}

// ---------------------------------------------------------------------------
// Malformed / incomplete input
// ---------------------------------------------------------------------------

///|
test "quic_parse_too_short" {
  expect_none(quic_parse_long_header(Bytes::from_array([])))
  expect_none(
    quic_parse_long_header(Bytes::from_array(Array::make(6, b'\x00'))),
  )
}

///|
test "quic_parse_rejects_short_header" {
  // Long header requires the high bit (0x80) set; a short header is rejected.
  let data = Bytes::from_array([
    b'\x00', // b0: high bit clear
     b'\x00', b'\x00', b'\x00', b'\x01', // version
     b'\x00', b'\x00', // dcid_len + scid_len
  ])
  expect_none(quic_parse_long_header(data))
}

///|
test "quic_parse_truncated_dcid" {
  // claims dcid_len = 10 but only 3 bytes follow
  let data = Bytes::from_array([
    b'\xc0', b'\x00', b'\x00', b'\x00', b'\x01', b'\x0a', b'\xaa', b'\xbb', b'\xcc',
  ])
  expect_none(quic_parse_long_header(data))
}

///|
test "quic_parse_truncated_scid" {
  // dcid_len = 1, then scid_len = 10 but buffer ends
  let data = Bytes::from_array([
    b'\xc0', b'\x00', b'\x00', b'\x00', b'\x01', b'\x01', b'\xaa', b'\x0a', b'\xbb',
  ])
  expect_none(quic_parse_long_header(data))
}

// ---------------------------------------------------------------------------
// Field decoding details
// ---------------------------------------------------------------------------

///|
test "quic_parse_version_and_ids" {
  let dcid = Bytes::from_array([b'\x01', b'\x02', b'\x03', b'\x04'])
  let scid = Bytes::from_array([b'\x05', b'\x06'])
  let payload = Bytes::from_array([b'\x99'])
  let enc = quic_encode_long_header(3, 0x11223344, dcid, scid, payload)
  let h = unwrap_or_fail(quic_parse_long_header(enc))
  assert_eq(h.long_packet_type, 3)
  assert_eq(h.version, 0x11223344)
  assert_eq(h.dcid, dcid)
  assert_eq(h.scid, scid)
  assert_eq(h.payload, payload)
}
