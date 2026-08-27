/// MessagePack Serialization (msgpack.org specification).
///
/// A production-grade MessagePack encoder and decoder implementing the
/// complete MessagePack type system:
///
/// - **Nil** (`nil`)
/// - **Boolean** (`true`, `false`)
/// - **Integers**: positive/negative fixint, uint8/16/32/64, int8/16/32/64
/// - **Floats**: float32, float64
/// - **Strings**: fixstr, str8, str16, str32
/// - **Binary**: bin8, bin16, bin32
/// - **Arrays**: fixarray, array16, array32
/// - **Maps**: fixmap, map16, map32
/// - **Extension types**: fixext1/2/4/8/16, ext8/16/32
///
/// ## Complexity
///
/// - Encoding: O(n) where n is the size of the value.
/// - Decoding: O(n) where n is the size of the packed data.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// MessagePack value type
// ---------------------------------------------------------------------------

///|
/// A MessagePack value — the universal representation for all msgpack data.
pub enum MsgPack {
  Nil
  Bool(Bool)
  Int(Int64)
  UInt(UInt64)
  Float64(Double)
  Str(String)
  Bin(Bytes)
  Array(Array[MsgPack])
  Map(Array[(MsgPack, MsgPack)])
  Ext(Int, Bytes) // (type_code, data)
}

///|
/// Pack a `MsgPack` value into a `Bytes` buffer.
///
/// Uses the smallest possible representation for each value (e.g. a
/// string of length 5 uses fixstr, not str8).
pub fn pack(value : MsgPack) -> Bytes {
  let buf : Array[Byte] = []
  pack_into(value, buf)
  Bytes::from_array(buf)
}

///|
/// Internal: pack a value into a byte array.
fn pack_into(value : MsgPack, buf : Array[Byte]) -> Unit {
  match value {
    Nil => buf.push(b'\xC0')
    Bool(b) => buf.push(if b { b'\xC3' } else { b'\xC2' })
    Int(n) => pack_int(n, buf)
    UInt(n) => pack_uint(n, buf)
    Float64(f) => pack_f64(f, buf)
    Str(s) => pack_str_impl(s, buf)
    Bin(b) => pack_bin_impl(b, buf)
    Array(arr) => pack_array_impl(arr, buf)
    Map(entries) => pack_map_impl(entries, buf)
    Ext(type_code, data) => pack_ext_impl(type_code, data, buf)
  }
}

// ---------------------------------------------------------------------------
// Integer encoding
// ---------------------------------------------------------------------------

///|
fn pack_int(n : Int64, buf : Array[Byte]) -> Unit {
  if n >= 0L {
    if n <= 127L {
      buf.push(n.to_byte())
    } else if n <= 0xFFL {
      buf.push(b'\xCC')
      buf.push(n.to_byte())
    } else if n <= 0xFFFFL {
      buf.push(b'\xCD')
      push_u16_be(buf, n.to_int())
    } else if n <= 0xFFFFFFFFL {
      buf.push(b'\xCE')
      push_u32_be(buf, n)
    } else {
      buf.push(b'\xCF')
      push_u64_be(buf, n.reinterpret_as_uint64())
    }
  } else if n >= -32L {
    buf.push(n.to_byte())
  } else if n >= -128L {
    buf.push(b'\xD0')
    buf.push(n.to_byte())
  } else if n >= -32768L {
    buf.push(b'\xD1')
    push_u16_be(buf, n.to_int())
  } else if n >= -2147483648L {
    buf.push(b'\xD2')
    push_u32_be(buf, n)
  } else {
    buf.push(b'\xD3')
    push_u64_be(buf, n.reinterpret_as_uint64())
  }
}

///|
fn pack_uint(n : UInt64, buf : Array[Byte]) -> Unit {
  let v = n.reinterpret_as_int64()
  if v >= 0L {
    pack_int(v, buf)
  } else {
    buf.push(b'\xCF')
    push_u64_be(buf, n)
  }
}

// ---------------------------------------------------------------------------
// Float encoding
// ---------------------------------------------------------------------------

///|
fn pack_f64(f : Double, buf : Array[Byte]) -> Unit {
  buf.push(b'\xCB')
  let bits = f.reinterpret_as_uint64()
  push_u64_be(buf, bits)
}

// ---------------------------------------------------------------------------
// String encoding
// ---------------------------------------------------------------------------

///|
fn pack_str_impl(s : String, buf : Array[Byte]) -> Unit {
  let bytes = @utils.string_to_bytes(s)
  let len = bytes.length()
  if len <= 31 {
    buf.push((0xA0 | len).to_byte())
  } else if len <= 0xFF {
    buf.push(b'\xD9')
    buf.push(len.to_byte())
  } else if len <= 0xFFFF {
    buf.push(b'\xDA')
    push_u16_be(buf, len)
  } else {
    buf.push(b'\xDB')
    push_u32_be(buf, len.to_int64())
  }
  for i = 0; i < len; i = i + 1 {
    buf.push(bytes[i])
  }
}

// ---------------------------------------------------------------------------
// Binary encoding
// ---------------------------------------------------------------------------

///|
fn pack_bin_impl(b : Bytes, buf : Array[Byte]) -> Unit {
  let len = b.length()
  if len <= 0xFF {
    buf.push(b'\xC4')
    buf.push(len.to_byte())
  } else if len <= 0xFFFF {
    buf.push(b'\xC5')
    push_u16_be(buf, len)
  } else {
    buf.push(b'\xC6')
    push_u32_be(buf, len.to_int64())
  }
  for i = 0; i < len; i = i + 1 {
    buf.push(b[i])
  }
}

// ---------------------------------------------------------------------------
// Array encoding
// ---------------------------------------------------------------------------

///|
fn pack_array_impl(arr : Array[MsgPack], buf : Array[Byte]) -> Unit {
  let len = arr.length()
  if len <= 15 {
    buf.push((0x90 | len).to_byte())
  } else if len <= 0xFFFF {
    buf.push(b'\xDC')
    push_u16_be(buf, len)
  } else {
    buf.push(b'\xDD')
    push_u32_be(buf, len.to_int64())
  }
  for i = 0; i < len; i = i + 1 {
    pack_into(arr[i], buf)
  }
}

// ---------------------------------------------------------------------------
// Map encoding
// ---------------------------------------------------------------------------

///|
fn pack_map_impl(
  entries : Array[(MsgPack, MsgPack)],
  buf : Array[Byte],
) -> Unit {
  let len = entries.length()
  if len <= 15 {
    buf.push((0x80 | len).to_byte())
  } else if len <= 0xFFFF {
    buf.push(b'\xDE')
    push_u16_be(buf, len)
  } else {
    buf.push(b'\xDF')
    push_u32_be(buf, len.to_int64())
  }
  for i = 0; i < len; i = i + 1 {
    let (k, v) = entries[i]
    pack_into(k, buf)
    pack_into(v, buf)
  }
}

// ---------------------------------------------------------------------------
// Extension type encoding
// ---------------------------------------------------------------------------

///|
fn pack_ext_impl(type_code : Int, data : Bytes, buf : Array[Byte]) -> Unit {
  let len = data.length()
  match len {
    1 => {
      buf.push(b'\xD4')
      buf.push(type_code.to_byte())
    }
    2 => {
      buf.push(b'\xD5')
      buf.push(type_code.to_byte())
    }
    4 => {
      buf.push(b'\xD6')
      buf.push(type_code.to_byte())
    }
    8 => {
      buf.push(b'\xD7')
      buf.push(type_code.to_byte())
    }
    16 => {
      buf.push(b'\xD8')
      buf.push(type_code.to_byte())
    }
    _ =>
      if len <= 0xFF {
        buf.push(b'\xC7')
        buf.push(len.to_byte())
        buf.push(type_code.to_byte())
      } else if len <= 0xFFFF {
        buf.push(b'\xC8')
        push_u16_be(buf, len)
        buf.push(type_code.to_byte())
      } else {
        buf.push(b'\xC9')
        push_u32_be(buf, len.to_int64())
        buf.push(type_code.to_byte())
      }
  }
  for i = 0; i < len; i = i + 1 {
    buf.push(data[i])
  }
}

// ---------------------------------------------------------------------------
// Byte helpers (big-endian)
// ---------------------------------------------------------------------------

///|
fn push_u16_be(buf : Array[Byte], val : Int) -> Unit {
  buf.push(((val >> 8) & 0xFF).to_byte())
  buf.push((val & 0xFF).to_byte())
}

///|
fn push_u32_be(buf : Array[Byte], val : Int64) -> Unit {
  buf.push(((val >> 24) & 0xFF).to_byte())
  buf.push(((val >> 16) & 0xFF).to_byte())
  buf.push(((val >> 8) & 0xFF).to_byte())
  buf.push((val & 0xFF).to_byte())
}

///|
fn push_u64_be(buf : Array[Byte], val : UInt64) -> Unit {
  buf.push(((val >> 56) & 0xFFUL).to_byte())
  buf.push(((val >> 48) & 0xFFUL).to_byte())
  buf.push(((val >> 40) & 0xFFUL).to_byte())
  buf.push(((val >> 32) & 0xFFUL).to_byte())
  buf.push(((val >> 24) & 0xFFUL).to_byte())
  buf.push(((val >> 16) & 0xFFUL).to_byte())
  buf.push(((val >> 8) & 0xFFUL).to_byte())
  buf.push((val & 0xFFUL).to_byte())
}

// ---------------------------------------------------------------------------
// Decoder
// ---------------------------------------------------------------------------

///|
/// Unpack a `Bytes` buffer into a `MsgPack` value.
///
/// Returns `Ok(value)` on success, or `Err(message)` if the data is
/// malformed, truncated, or uses an unknown format code.
pub fn unpack(data : Bytes) -> Result[MsgPack, String] {
  if data.length() == 0 {
    return Err("empty input")
  }
  let pos = { idx: 0, }
  unpack_one(data, pos)
}

///|
/// Mutable position tracker for decoding.
priv struct DecodePos {
  mut idx : Int
}

///|
/// Unpack a single value starting at `pos.idx`, advancing `pos.idx` past it.
fn unpack_one(data : Bytes, pos : DecodePos) -> Result[MsgPack, String] {
  if pos.idx >= data.length() {
    return Err("unexpected end of data")
  }
  let code = data[pos.idx].to_int()
  pos.idx = pos.idx + 1
  // Positive fixint: 0x00..0x7f
  if code <= 0x7F {
    return Ok(Int(code.to_int64()))
  }
  // fixmap: 0x80..0x8f
  if code >= 0x80 && code <= 0x8F {
    let len = code & 0x0F
    return unpack_map(data, pos, len)
  }
  // fixarray: 0x90..0x9f
  if code >= 0x90 && code <= 0x9F {
    let len = code & 0x0F
    return unpack_array(data, pos, len)
  }
  // fixstr: 0xa0..0xbf
  if code >= 0xA0 && code <= 0xBF {
    let len = code & 0x1F
    return unpack_str(data, pos, len)
  }
  // Negative fixint: 0xe0..0xff
  if code >= 0xE0 {
    let signed = code - 256
    return Ok(Int(signed.to_int64()))
  }
  match code {
    0xC0 => Ok(Nil)
    0xC2 => Ok(Bool(false))
    0xC3 => Ok(Bool(true))
    0xC4 => {
      let len = read_u8(data, pos)
      match len {
        None => Err("truncated bin8")
        Some(l) => unpack_bin(data, pos, l)
      }
    }
    0xC5 => {
      let len = read_u16_be(data, pos)
      match len {
        None => Err("truncated bin16")
        Some(l) => unpack_bin(data, pos, l)
      }
    }
    0xC6 => {
      let len = read_u32_be(data, pos)
      match len {
        None => Err("truncated bin32")
        Some(l) => unpack_bin(data, pos, l)
      }
    }
    0xC7 => {
      let len = read_u8(data, pos)
      match len {
        None => Err("truncated ext8")
        Some(l) => unpack_ext(data, pos, l)
      }
    }
    0xC8 => {
      let len = read_u16_be(data, pos)
      match len {
        None => Err("truncated ext16")
        Some(l) => unpack_ext(data, pos, l)
      }
    }
    0xC9 => {
      let len = read_u32_be(data, pos)
      match len {
        None => Err("truncated ext32")
        Some(l) => unpack_ext(data, pos, l)
      }
    }
    0xCA => {
      // float32
      let bits = read_u32_be(data, pos)
      match bits {
        None => Err("truncated float32")
        Some(b) => Ok(Float64(uint32_to_double(b)))
      }
    }
    0xCB => {
      // float64
      let bits = read_u64_be(data, pos)
      match bits {
        None => Err("truncated float64")
        Some(b) => Ok(Float64(b.reinterpret_as_double()))
      }
    }
    0xCC =>
      match read_u8(data, pos) {
        None => Err("truncated uint8")
        Some(v) => Ok(UInt(v.reinterpret_as_uint().to_uint64()))
      }
    0xCD =>
      match read_u16_be(data, pos) {
        None => Err("truncated uint16")
        Some(v) => Ok(UInt(v.reinterpret_as_uint().to_uint64()))
      }
    0xCE =>
      match read_u32_be(data, pos) {
        None => Err("truncated uint32")
        Some(v) => Ok(UInt(v.reinterpret_as_uint().to_uint64()))
      }
    0xCF =>
      match read_u64_be(data, pos) {
        None => Err("truncated uint64")
        Some(v) => Ok(UInt(v))
      }
    0xD0 =>
      match read_u8(data, pos) {
        None => Err("truncated int8")
        Some(v) => {
          let signed = if v >= 128 { v - 256 } else { v }
          Ok(Int(signed.to_int64()))
        }
      }
    0xD1 =>
      match read_u16_be(data, pos) {
        None => Err("truncated int16")
        Some(v) => {
          let signed = if v >= 32768 { v - 65536 } else { v }
          Ok(Int(signed.to_int64()))
        }
      }
    0xD2 =>
      match read_u32_be(data, pos) {
        None => Err("truncated int32")
        Some(v) => Ok(Int(v.to_int64()))
      }
    0xD3 =>
      match read_u64_be(data, pos) {
        None => Err("truncated int64")
        Some(v) => Ok(Int(v.reinterpret_as_int64()))
      }
    0xD4 => unpack_ext_fixed(data, pos, 1)
    0xD5 => unpack_ext_fixed(data, pos, 2)
    0xD6 => unpack_ext_fixed(data, pos, 4)
    0xD7 => unpack_ext_fixed(data, pos, 8)
    0xD8 => unpack_ext_fixed(data, pos, 16)
    0xD9 =>
      match read_u8(data, pos) {
        None => Err("truncated str8")
        Some(l) => unpack_str(data, pos, l)
      }
    0xDA =>
      match read_u16_be(data, pos) {
        None => Err("truncated str16")
        Some(l) => unpack_str(data, pos, l)
      }
    0xDB =>
      match read_u32_be(data, pos) {
        None => Err("truncated str32")
        Some(l) => unpack_str(data, pos, l)
      }
    0xDC =>
      match read_u16_be(data, pos) {
        None => Err("truncated array16")
        Some(l) => unpack_array(data, pos, l)
      }
    0xDD =>
      match read_u32_be(data, pos) {
        None => Err("truncated array32")
        Some(l) => unpack_array(data, pos, l)
      }
    0xDE =>
      match read_u16_be(data, pos) {
        None => Err("truncated map16")
        Some(l) => unpack_map(data, pos, l)
      }
    0xDF =>
      match read_u32_be(data, pos) {
        None => Err("truncated map32")
        Some(l) => unpack_map(data, pos, l)
      }
    _ => Err("unknown format code: 0x" + code.to_string())
  }
}

///|
/// Unpack a fixed-size extension type (fixext1/2/4/8/16).
fn unpack_ext_fixed(
  data : Bytes,
  pos : DecodePos,
  len : Int,
) -> Result[MsgPack, String] {
  match read_u8(data, pos) {
    None => Err("truncated ext type code")
    Some(tc) =>
      match read_bytes(data, pos, len) {
        None => Err("truncated ext data")
        Some(d) => Ok(Ext(tc, d))
      }
  }
}

// ---------------------------------------------------------------------------
// Reader helpers
// ---------------------------------------------------------------------------

///|
fn read_u8(data : Bytes, pos : DecodePos) -> Int? {
  if pos.idx >= data.length() {
    return None
  }
  let v = data[pos.idx].to_int()
  pos.idx = pos.idx + 1
  Some(v)
}

///|
fn read_u16_be(data : Bytes, pos : DecodePos) -> Int? {
  if pos.idx + 2 > data.length() {
    return None
  }
  let hi = data[pos.idx].to_int()
  let lo = data[pos.idx + 1].to_int()
  pos.idx = pos.idx + 2
  Some((hi << 8) | lo)
}

///|
fn read_u32_be(data : Bytes, pos : DecodePos) -> Int? {
  if pos.idx + 4 > data.length() {
    return None
  }
  let b0 = data[pos.idx].to_int()
  let b1 = data[pos.idx + 1].to_int()
  let b2 = data[pos.idx + 2].to_int()
  let b3 = data[pos.idx + 3].to_int()
  pos.idx = pos.idx + 4
  Some((b0 << 24) | (b1 << 16) | (b2 << 8) | b3)
}

///|
fn read_u64_be(data : Bytes, pos : DecodePos) -> UInt64? {
  if pos.idx + 8 > data.length() {
    return None
  }
  let mut result : UInt64 = 0UL
  for i = 0; i < 8; i = i + 1 {
    result = (result << 8) | data[pos.idx + i].to_uint64()
  }
  pos.idx = pos.idx + 8
  Some(result)
}

///|
fn read_bytes(data : Bytes, pos : DecodePos, n : Int) -> Bytes? {
  if pos.idx + n > data.length() {
    return None
  }
  let buf : Array[Byte] = []
  for i = 0; i < n; i = i + 1 {
    buf.push(data[pos.idx + i])
  }
  pos.idx = pos.idx + n
  Some(Bytes::from_array(buf))
}

// ---------------------------------------------------------------------------
// Compound type unpackers
// ---------------------------------------------------------------------------

///|
fn unpack_str(
  data : Bytes,
  pos : DecodePos,
  len : Int,
) -> Result[MsgPack, String] {
  if pos.idx + len > data.length() {
    return Err("truncated string")
  }
  let buf : Array[Byte] = []
  for i = 0; i < len; i = i + 1 {
    buf.push(data[pos.idx + i])
  }
  pos.idx = pos.idx + len
  Ok(Str(@utils.bytes_to_string(Bytes::from_array(buf))))
}

///|
fn unpack_bin(
  data : Bytes,
  pos : DecodePos,
  len : Int,
) -> Result[MsgPack, String] {
  if pos.idx + len > data.length() {
    return Err("truncated binary")
  }
  let buf : Array[Byte] = []
  for i = 0; i < len; i = i + 1 {
    buf.push(data[pos.idx + i])
  }
  pos.idx = pos.idx + len
  Ok(Bin(Bytes::from_array(buf)))
}

///|
fn unpack_array(
  data : Bytes,
  pos : DecodePos,
  len : Int,
) -> Result[MsgPack, String] {
  let arr : Array[MsgPack] = []
  for i = 0; i < len; i = i + 1 {
    match unpack_one(data, pos) {
      Err(e) => return Err(e)
      Ok(v) => arr.push(v)
    }
  }
  Ok(Array(arr))
}

///|
fn unpack_map(
  data : Bytes,
  pos : DecodePos,
  len : Int,
) -> Result[MsgPack, String] {
  let entries : Array[(MsgPack, MsgPack)] = []
  for i = 0; i < len; i = i + 1 {
    match unpack_one(data, pos) {
      Err(e) => return Err(e)
      Ok(k) =>
        match unpack_one(data, pos) {
          Err(e) => return Err(e)
          Ok(v) => entries.push((k, v))
        }
    }
  }
  Ok(Map(entries))
}

///|
fn unpack_ext(
  data : Bytes,
  pos : DecodePos,
  len : Int,
) -> Result[MsgPack, String] {
  match read_u8(data, pos) {
    None => Err("truncated extension type code")
    Some(type_code) =>
      match read_bytes(data, pos, len) {
        None => Err("truncated extension data")
        Some(d) => Ok(Ext(type_code, d))
      }
  }
}

// ---------------------------------------------------------------------------
// Float32 helper
// ---------------------------------------------------------------------------

///|
/// Reinterpret IEEE-754 single-precision bits (as Int) to Double.
fn uint32_to_double(bits : Int) -> Double {
  let sign = if bits >> 31 == 1 { -1.0 } else { 1.0 }
  let exp = (bits >> 23) & 0xFF
  let mantissa = bits & 0x7FFFFF
  if exp == 0 {
    if mantissa == 0 {
      return 0.0 * sign
    }
    // Denormalized: value = (-1)^s * 2^(-126) * (mantissa / 2^23)
    return sign * mantissa.to_double() * 1.401298464324817e-45
  }
  if exp == 0xFF {
    if mantissa == 0 {
      return sign * 1.0 / 0.0 // Infinity
    }
    return 0.0 / 0.0 // NaN
  }
  // Normalized: value = (-1)^s * 2^(exp-127) * (1 + mantissa/2^23)
  let m = mantissa.to_double() / 8388608.0
  let e = exp - 127
  // Compute 2^e manually for correctness.
  let mut pow_val = 1.0
  if e >= 0 {
    for i = 0; i < e; i = i + 1 {
      pow_val = pow_val * 2.0
    }
  } else {
    for i = 0; i > e; i = i - 1 {
      pow_val = pow_val / 2.0
    }
  }
  sign * (1.0 + m) * pow_val
}

// ---------------------------------------------------------------------------
// Convenience functions
// ---------------------------------------------------------------------------

///|
/// Pack a `Nil` value.
pub fn pack_nil() -> Bytes {
  Bytes::from_array([b'\xC0'])
}

///|
/// Pack a boolean.
pub fn pack_bool(b : Bool) -> Bytes {
  Bytes::from_array([if b { b'\xC3' } else { b'\xC2' }])
}

///|
/// Pack an Int64.
pub fn pack_int64(n : Int64) -> Bytes {
  pack(Int(n))
}

///|
/// Pack a Double.
pub fn pack_double(f : Double) -> Bytes {
  pack(Float64(f))
}

///|
/// Pack a string.
pub fn pack_str(s : String) -> Bytes {
  pack(Str(s))
}

///|
/// Pack binary data.
pub fn pack_bin(b : Bytes) -> Bytes {
  pack(Bin(b))
}

///|
/// Pack an array of MessagePack values.
pub fn pack_array(arr : Array[MsgPack]) -> Bytes {
  pack(Array(arr))
}

///|
/// Pack a map of key-value pairs.
pub fn pack_map(entries : Array[(MsgPack, MsgPack)]) -> Bytes {
  pack(Map(entries))
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "msgpack: nil round-trip" {
  let packed = pack_nil()
  assert_eq(packed.length(), 1)
  assert_eq(packed[0], b'\xC0')
  assert_true(unpack(packed) is Ok(Nil))
}

///|
test "msgpack: bool round-trip" {
  let t = pack_bool(true)
  let f = pack_bool(false)
  assert_eq(t[0], b'\xC3')
  assert_eq(f[0], b'\xC2')
  assert_true(unpack(t) is Ok(Bool(true)))
  assert_true(unpack(f) is Ok(Bool(false)))
}

///|
test "msgpack: positive fixint round-trip" {
  for i = 0; i <= 127; i = i + 17 {
    let packed = pack_int64(i.to_int64())
    assert_eq(packed.length(), 1)
    match unpack(packed) {
      Ok(Int(v)) => assert_eq(v, i.to_int64())
      _ => fail("expected Int")
    }
  }
}

///|
test "msgpack: negative fixint round-trip" {
  for i = -32; i <= -1; i = i + 7 {
    let packed = pack_int64(i.to_int64())
    assert_eq(packed.length(), 1)
    match unpack(packed) {
      Ok(Int(v)) => assert_eq(v, i.to_int64())
      _ => fail("expected Int")
    }
  }
}

///|
test "msgpack: uint8 round-trip" {
  let packed = pack_int64(200L)
  assert_eq(packed.length(), 2)
  assert_eq(packed[0], b'\xCC')
  match unpack(packed) {
    Ok(UInt(v)) => assert_eq(v, 200UL)
    _ => fail("expected UInt")
  }
}

///|
test "msgpack: uint16 round-trip" {
  let packed = pack_int64(300L)
  assert_eq(packed.length(), 3)
  assert_eq(packed[0], b'\xCD')
  match unpack(packed) {
    Ok(UInt(v)) => assert_eq(v, 300UL)
    _ => fail("expected UInt")
  }
}

///|
test "msgpack: int8 round-trip" {
  let packed = pack_int64(-100L)
  assert_eq(packed.length(), 2)
  assert_eq(packed[0], b'\xD0')
  match unpack(packed) {
    Ok(Int(v)) => assert_eq(v, -100L)
    _ => fail("expected Int")
  }
}

///|
test "msgpack: int16 round-trip" {
  let packed = pack_int64(-1000L)
  assert_eq(packed.length(), 3)
  assert_eq(packed[0], b'\xD1')
  match unpack(packed) {
    Ok(Int(v)) => assert_eq(v, -1000L)
    _ => fail("expected Int")
  }
}

///|
test "msgpack: int32 round-trip" {
  let packed = pack_int64(-100000L)
  assert_eq(packed.length(), 5)
  assert_eq(packed[0], b'\xD2')
  match unpack(packed) {
    Ok(Int(v)) => assert_eq(v, -100000L)
    _ => fail("expected Int")
  }
}

///|
test "msgpack: string round-trip" {
  let s = "Hello, MessagePack!"
  let packed = pack_str(s)
  assert_eq(packed[0].to_int(), 0xB3)
  match unpack(packed) {
    Ok(Str(v)) => assert_eq(v, s)
    _ => fail("expected Str")
  }
}

///|
test "msgpack: empty string round-trip" {
  let packed = pack_str("")
  assert_eq(packed.length(), 1)
  assert_eq(packed[0].to_int(), 0xA0)
  assert_true(unpack(packed) is Ok(Str("")))
}

///|
test "msgpack: long string uses str8" {
  let sb = StringBuilder()
  for i = 0; i < 50; i = i + 1 {
    sb.write_string("x")
  }
  let s = sb.to_string()
  let packed = pack_str(s)
  assert_eq(packed[0], b'\xD9')
  match unpack(packed) {
    Ok(Str(v)) => assert_eq(v, s)
    _ => fail("expected Str")
  }
}

///|
test "msgpack: binary round-trip" {
  let data = Bytes::from_array([b'\x01', b'\x02', b'\x03'])
  let packed = pack_bin(data)
  assert_eq(packed[0], b'\xC4')
  assert_eq(packed[1].to_int(), 3)
  match unpack(packed) {
    Ok(Bin(v)) => assert_eq(v, data)
    _ => fail("expected Bin")
  }
}

///|
test "msgpack: array round-trip" {
  let arr = [Int(1L), Int(2L), Int(3L)]
  let packed = pack_array(arr)
  assert_eq(packed[0].to_int(), 0x93)
  match unpack(packed) {
    Ok(Array(elements)) => {
      assert_eq(elements.length(), 3)
      match elements[0] {
        Int(v) => assert_eq(v, 1L)
        _ => fail("expected Int")
      }
    }
    _ => fail("expected Array")
  }
}

///|
test "msgpack: map round-trip" {
  let entries : Array[(MsgPack, MsgPack)] = [
    (Str("name"), Str("Alice")),
    (Str("age"), Int(30L)),
  ]
  let packed = pack_map(entries)
  assert_eq(packed[0].to_int(), 0x82)
  match unpack(packed) {
    Ok(Map(pairs)) => {
      assert_eq(pairs.length(), 2)
      match pairs[0] {
        (Str(k), Str(v)) => {
          assert_eq(k, "name")
          assert_eq(v, "Alice")
        }
        _ => fail("expected Str key-value")
      }
    }
    _ => fail("expected Map")
  }
}

///|
test "msgpack: float64 round-trip" {
  let packed = pack_double(3.14159265358979)
  assert_eq(packed[0], b'\xCB')
  match unpack(packed) {
    Ok(Float64(v)) =>
      assert_true((v - 3.14159265358979).abs() < 0.000000000000001)
    _ => fail("expected Float64")
  }
}

///|
test "msgpack: nested structure round-trip" {
  let nested : MsgPack = Map([
    (Str("name"), Str("test")),
    (Str("values"), Array([Int(1L), Int(2L), Int(3L)])),
    (Str("flag"), Bool(true)),
    (Str("null"), Nil),
  ])
  let packed = pack(nested)
  match unpack(packed) {
    Ok(Map(pairs)) => {
      assert_eq(pairs.length(), 4)
      match pairs[0] {
        (Str(k), Str(v)) => {
          assert_eq(k, "name")
          assert_eq(v, "test")
        }
        _ => fail("expected Str key-value")
      }
    }
    Ok(_) => fail("expected Map")
    Err(e) => fail("unpack failed: " + e)
  }
}

///|
test "msgpack: empty input returns error" {
  assert_true(unpack(b"") is Err(_))
}

///|
test "msgpack: truncated data returns error" {
  let result = unpack(Bytes::from_array([b'\xCD']))
  assert_true(result is Err(_))
}

///|
test "msgpack: extension type round-trip" {
  let data = Bytes::from_array([b'\x01', b'\x02', b'\x03', b'\x04'])
  let ext = Ext(5, data)
  let packed = pack(ext)
  assert_eq(packed[0], b'\xD6')
  assert_eq(packed[1].to_int(), 5)
  match unpack(packed) {
    Ok(Ext(tc, d)) => {
      assert_eq(tc, 5)
      assert_eq(d, data)
    }
    _ => fail("expected Ext")
  }
}

///|
test "msgpack: large array uses array16" {
  let arr : Array[MsgPack] = []
  for i = 0; i < 20; i = i + 1 {
    arr.push(Int(0L))
  }
  let packed = pack_array(arr)
  assert_eq(packed[0], b'\xDC')
  match unpack(packed) {
    Ok(Array(elements)) => assert_eq(elements.length(), 20)
    _ => fail("expected Array")
  }
}
