///|
/// DNS protocol white-box tests (RFC 1035 message encode/decode).
///
/// NOTE: `build_dns_query` / `encode_name` panic at runtime (index
/// assignment `buf[pos] = x` on a fresh array does not auto-extend in
/// MoonBit). Those are documented as genuine source bugs; this suite
/// exercises the working surface: `parse_dns_header`, `parse_name`, and
/// the public type constructors.
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

// ---------------------------------------------------------------------------
// parse_dns_header
// ---------------------------------------------------------------------------

///|
test "parse_dns_header_valid" {
  let data = Bytes::from_array([
    b'\x12', b'\x34', // id
     b'\x01', b'\x00', // flags (RD set)
     b'\x00', b'\x01', // qdcount
     b'\x00', b'\x02', // ancount
     b'\x00', b'\x03', // nscount
     b'\x00', b'\x04', // arcount
  ])
  let h = unwrap_or_fail(parse_dns_header(data))
  assert_eq(h.id, 0x1234)
  assert_eq(h.flags, 0x0100)
  assert_eq(h.qdcount, 1)
  assert_eq(h.ancount, 2)
  assert_eq(h.nscount, 3)
  assert_eq(h.arcount, 4)
}

///|
test "parse_dns_header_flags_bits" {
  // RD=1, RA=1, QR=1 -> 0x8180
  let data = Bytes::from_array([
    b'\x00', b'\x00', b'\x81', b'\x80', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00',
    b'\x00', b'\x00', b'\x00',
  ])
  let h = unwrap_or_fail(parse_dns_header(data))
  assert_eq(h.flags, 0x8180)
}

///|
test "parse_dns_header_too_short" {
  expect_none(parse_dns_header(Bytes::from_array([])))
  expect_none(parse_dns_header(Bytes::from_array(Array::make(1, b'\x00'))))
  expect_none(parse_dns_header(Bytes::from_array(Array::make(11, b'\x00'))))
}

///|
test "parse_dns_header_reads_only_first_12" {
  // A trailing question section must not affect header parsing.
  let data = Bytes::from_array([
    b'\xab', b'\xcd', b'\x01', b'\x00', b'\x00', b'\x01', b'\x00', b'\x00', b'\x00',
    b'\x00', b'\x00', b'\x00', b'\x07', b'e', b'x', b'a', b'm', b'p', b'l', b'e',
  ])
  let h = unwrap_or_fail(parse_dns_header(data))
  assert_eq(h.id, 0xabcd)
  assert_eq(h.qdcount, 1)
}

// ---------------------------------------------------------------------------
// parse_name (manual wire-format buffers)
// ---------------------------------------------------------------------------

///|
test "parse_name_single_label" {
  let data = Bytes::from_array([
    b'\t', b'l', b'o', b'c', b'a', b'l', b'h', b'o', b's', b't', b'\x00',
  ])
  let (name, off) = parse_name(data, 0)
  assert_eq(name, "localhost")
  assert_eq(off, 11)
}

///|
test "parse_name_multi_label" {
  let data = Bytes::from_array([
    b'\x07', b'e', b'x', b'a', b'm', b'p', b'l', b'e', b'\x03', b'c', b'o', b'm',
    b'\x00',
  ])
  let (name, off) = parse_name(data, 0)
  assert_eq(name, "example.com")
  assert_eq(off, 13)
}

///|
test "parse_name_empty" {
  let data = Bytes::from_array([b'\x00'])
  let (name, off) = parse_name(data, 0)
  assert_eq(name, "")
  assert_eq(off, 1)
}

///|
test "parse_name_at_offset" {
  // Two junk bytes, then "www.example.com" at offset 2.
  let data = Bytes::from_array([
    b'\xff', b'\xff', b'\x03', b'w', b'w', b'w', b'\x07', b'e', b'x', b'a', b'm',
    b'p', b'l', b'e', b'\x03', b'c', b'o', b'm', b'\x00',
  ])
  let (name, off) = parse_name(data, 2)
  assert_eq(name, "www.example.com")
  assert_eq(off, 2 + 17)
}

///|
test "parse_name_three_labels" {
  let data = Bytes::from_array([
    b'\x01', b'a', b'\x01', b'b', b'\x01', b'c', b'\x01', b'd', b'\x00',
  ])
  let (name, off) = parse_name(data, 0)
  assert_eq(name, "a.b.c.d")
  assert_eq(off, 9)
}

///|
test "parse_name_label_63_boundary" {
  let buf : Array[Byte] = []
  buf.push(b'\x3f')
  for _i in 0..<63 {
    buf.push(b'a')
  }
  buf.push(b'\x00')
  let (name, _) = parse_name(Bytes::from_array(buf), 0)
  assert_eq(name, String::make(63, 'a'))
}

///|
test "parse_name_compression_pointer" {
  // "example.com" at offset 0, then a pointer (0xC0 0x00) at offset 12
  // pointing back to offset 0.
  let data : Array[Byte] = []
  data.push(b'\x07')
  data.push(b'e')
  data.push(b'x')
  data.push(b'a')
  data.push(b'm')
  data.push(b'p')
  data.push(b'l')
  data.push(b'e')
  data.push(b'\x03')
  data.push(b'c')
  data.push(b'o')
  data.push(b'm')
  data.push(b'\x00')
  data.push(b'\xc0')
  data.push(b'\x00')
  let (name, off) = parse_name(Bytes::from_array(data), 13)
  assert_eq(name, "example.com")
  // pointer consumes exactly 2 bytes: 13 + 2
  assert_eq(off, 15)
}

///|
test "parse_name_compression_with_suffix" {
  // Offset 0: "example.com". Offset 14: a label "www" then pointer to 0,
  // reconstructing "www.example.com".
  let data : Array[Byte] = []
  data.push(b'\x07')
  data.push(b'e')
  data.push(b'x')
  data.push(b'a')
  data.push(b'm')
  data.push(b'p')
  data.push(b'l')
  data.push(b'e')
  data.push(b'\x03')
  data.push(b'c')
  data.push(b'o')
  data.push(b'm')
  data.push(b'\x00')
  // continuation at 14
  data.push(b'\x03')
  data.push(b'w')
  data.push(b'w')
  data.push(b'w')
  data.push(b'\xc0')
  data.push(b'\x00')
  let (name, off) = parse_name(Bytes::from_array(data), 13)
  assert_eq(name, "www.example.com")
  assert_eq(off, 19)
}

///|
test "parse_name_cyclic_pointer_does_not_hang" {
  // Pointer to itself: 0xC0 0x00 (points to offset 0, which is also a
  // pointer to 0). The internal safety counter must bound the loop.
  let data = Bytes::from_array([b'\xc0', b'\x00'])
  let (name, off) = parse_name(data, 0)
  assert_eq(name, "")
  assert_eq(off, 2)
}
