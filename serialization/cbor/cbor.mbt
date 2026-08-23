/// CBOR (Concise Binary Object Representation) — RFC 8949.
///
/// CBOR is a binary data format designed for small code size and small
/// message size. It is used in CoAP, WebAuthn, and many IoT protocols.
///
/// ## Supported types
///
/// - Unsigned integers (major type 0)
/// - Negative integers (major type 1)
/// - Byte strings (major type 2)
/// - Text strings (major type 3)
/// - Arrays (major type 4)
/// - Maps (major type 5)
/// - Tags (major type 6) — skipped during decode
/// - Simple values (major type 7): false, true, null, undefined, float64
///
/// ## References
///
/// - RFC 8949: Concise Binary Object Representation (CBOR)
///
/// `proof-enabled` is `false`.

///|
/// CBOR value type.
pub enum CborValue {
  CborUInt(UInt)
  CborNInt(Int) // negative integer (value = -1 - n)
  CborBytes(Bytes)
  CborStr(String)
  CborArray(Array[CborValue])
  CborMap(Array[(CborValue, CborValue)])
  CborBool(Bool)
  CborNull
  CborFloat(Double)
}

///|
/// Encode a CborValue to CBOR bytes.
pub fn encode(v : CborValue) -> Bytes {
  let buf : Array[Byte] = []
  encode_value(v, buf)
  Bytes::from_array(buf)
}

///|
fn encode_value(v : CborValue, buf : Array[Byte]) -> Unit {
  match v {
    CborUInt(n) => encode_head(0, n.to_uint64(), buf)
    CborNInt(n) => {
      // CBOR negative: argument = -(value) - 1
      // For n = -100, arg = 99
      let arg = (-n - 1).to_uint64()
      encode_head(1, arg, buf)
    }
    CborBytes(b) => {
      encode_head(2, b.length().to_uint64(), buf)
      for i = 0; i < b.length(); i = i + 1 {
        buf.push(b[i])
      }
    }
    CborStr(s) => {
      let utf8 = @utils.string_to_bytes(s)
      encode_head(3, utf8.length().to_uint64(), buf)
      for i = 0; i < utf8.length(); i = i + 1 {
        buf.push(utf8[i])
      }
    }
    CborArray(arr) => {
      encode_head(4, arr.length().to_uint64(), buf)
      for i = 0; i < arr.length(); i = i + 1 {
        encode_value(arr[i], buf)
      }
    }
    CborMap(pairs) => {
      encode_head(5, pairs.length().to_uint64(), buf)
      for i = 0; i < pairs.length(); i = i + 1 {
        encode_value(pairs[i].0, buf)
        encode_value(pairs[i].1, buf)
      }
    }
    CborBool(b) => buf.push(if b { 0xF5 } else { 0xF4 })
    CborNull => buf.push(0xF6)
    CborFloat(f) => {
      buf.push(0xFB)
      let bits = f.reinterpret_as_uint64()
      for i = 0; i < 8; i = i + 1 {
        buf.push(((bits >> (i * 8)) & 0xFFUL).to_byte())
      }
    }
  }
}

///|
/// Encode a CBOR head byte with major type and argument.
fn encode_head(major : Int, arg : UInt64, buf : Array[Byte]) -> Unit {
  let m = major.reinterpret_as_uint()
  if arg < 24UL {
    buf.push((m << 5).lor(arg.to_uint()).to_byte())
  } else if arg < 0x100UL {
    buf.push((m << 5).lor(24U).to_byte())
    buf.push(arg.to_byte())
  } else if arg < 0x10000UL {
    buf.push((m << 5).lor(25U).to_byte())
    buf.push(((arg >> 8) & 0xFFUL).to_byte())
    buf.push((arg & 0xFFUL).to_byte())
  } else if arg < 0x100000000UL {
    buf.push((m << 5).lor(26U).to_byte())
    for i = 0; i < 4; i = i + 1 {
      buf.push(((arg >> ((3 - i) * 8)) & 0xFFUL).to_byte())
    }
  } else {
    buf.push((m << 5).lor(27U).to_byte())
    for i = 0; i < 8; i = i + 1 {
      buf.push(((arg >> ((7 - i) * 8)) & 0xFFUL).to_byte())
    }
  }
}

///|
/// Decode CBOR bytes to a CborValue. Returns None on error.
pub fn decode(data : Bytes) -> CborValue? {
  let (v, pos) = match decode_value(data, 0) {
    None => return None
    Some(x) => x
  }
  ignore(pos)
  Some(v)
}

///|
fn decode_value(data : Bytes, pos : Int) -> (CborValue, Int)? {
  if pos >= data.length() {
    return None
  }
  let b = data[pos]
  let major = b.to_int() >> 5
  let info = (b & 0x1F).to_int()
  let p = pos + 1
  match major {
    0 => {
      let (arg, np) = match decode_arg(data, p, info) {
        None => return None
        Some(x) => x
      }
      Some((CborUInt(arg.to_uint()), np))
    }
    1 => {
      let (arg, np) = match decode_arg(data, p, info) {
        None => return None
        Some(x) => x
      }
      // value = -(arg) - 1
      let val = -arg.to_int() - 1
      Some((CborNInt(val), np))
    }
    2 => {
      let (arg, np) = match decode_arg(data, p, info) {
        None => return None
        Some(x) => x
      }
      let len = arg.to_int()
      if np + len > data.length() {
        return None
      }
      let bytes : Array[Byte] = []
      for i = 0; i < len; i = i + 1 {
        bytes.push(data[np + i])
      }
      Some((CborBytes(Bytes::from_array(bytes)), np + len))
    }
    3 => {
      let (arg, np) = match decode_arg(data, p, info) {
        None => return None
        Some(x) => x
      }
      let len = arg.to_int()
      if np + len > data.length() {
        return None
      }
      let s = bytes_to_string(data, np, len)
      Some((CborStr(s), np + len))
    }
    4 => {
      let (arg, np) = match decode_arg(data, p, info) {
        None => return None
        Some(x) => x
      }
      let len = arg.to_int()
      let arr : Array[CborValue] = []
      let mut cur = np
      for i = 0; i < len; i = i + 1 {
        match decode_value(data, cur) {
          None => return None
          Some((v, ni)) => {
            arr.push(v)
            cur = ni
          }
        }
      }
      Some((CborArray(arr), cur))
    }
    5 => {
      let (arg, np) = match decode_arg(data, p, info) {
        None => return None
        Some(x) => x
      }
      let len = arg.to_int()
      let pairs : Array[(CborValue, CborValue)] = []
      let mut cur = np
      for i = 0; i < len; i = i + 1 {
        let k = match decode_value(data, cur) {
          None => return None
          Some((v, ni)) => {
            cur = ni
            v
          }
        }
        let val = match decode_value(data, cur) {
          None => return None
          Some((v, ni)) => {
            cur = ni
            v
          }
        }
        pairs.push((k, val))
      }
      Some((CborMap(pairs), cur))
    }
    7 =>
      match info {
        20 => Some((CborBool(false), p))
        21 => Some((CborBool(true), p))
        22 => Some((CborNull, p))
        27 => {
          if p + 8 > data.length() {
            return None
          }
          let mut bits = 0UL
          for i = 0; i < 8; i = i + 1 {
            bits = bits.lor(data[p + i].to_uint64() << (i * 8))
          }
          Some((CborFloat(bits.reinterpret_as_double()), p + 8))
        }
        _ => None
      }
    _ => None
  }
}

///|
/// Decode the argument following a head byte.
fn decode_arg(data : Bytes, pos : Int, info : Int) -> (UInt64, Int)? {
  if info < 24 {
    return Some((info.to_uint64(), pos))
  }
  match info {
    24 => {
      if pos >= data.length() {
        return None
      }
      Some((data[pos].to_uint64(), pos + 1))
    }
    25 => {
      if pos + 1 >= data.length() {
        return None
      }
      let v = (data[pos].to_uint64() << 8) | data[pos + 1].to_uint64()
      Some((v, pos + 2))
    }
    26 => {
      if pos + 3 >= data.length() {
        return None
      }
      let mut v = 0UL
      for i = 0; i < 4; i = i + 1 {
        v = v.lor(data[pos + i].to_uint64() << ((3 - i) * 8))
      }
      Some((v, pos + 4))
    }
    27 => {
      if pos + 7 >= data.length() {
        return None
      }
      let mut v = 0UL
      for i = 0; i < 8; i = i + 1 {
        v = v.lor(data[pos + i].to_uint64() << ((7 - i) * 8))
      }
      Some((v, pos + 8))
    }
    _ => None
  }
}

///|
fn bytes_to_string(data : Bytes, offset : Int, len : Int) -> String {
  let arr : Array[Byte] = []
  for i = 0; i < len; i = i + 1 {
    arr.push(data[offset + i])
  }
  @utils.bytes_to_string(Bytes::from_array(arr))
}

///|
test "cbor: unsigned int roundtrip" {
  let v = CborUInt(42U)
  let encoded = encode(v)
  let decoded = decode(encoded)
  match decoded {
    Some(CborUInt(n)) => assert_eq(n, 42U)
    _ => assert_true(false)
  }
}

///|
test "cbor: negative int roundtrip" {
  let v = CborNInt(-100)
  let encoded = encode(v)
  let decoded = decode(encoded)
  match decoded {
    Some(CborNInt(n)) => assert_eq(n, -100)
    _ => assert_true(false)
  }
}

///|
test "cbor: string roundtrip" {
  let v = CborStr("Hello, CBOR!")
  let encoded = encode(v)
  let decoded = decode(encoded)
  match decoded {
    Some(CborStr(s)) => assert_eq(s, "Hello, CBOR!")
    _ => assert_true(false)
  }
}

///|
test "cbor: array roundtrip" {
  let v = CborArray([CborUInt(1U), CborUInt(2U), CborUInt(3U)])
  let encoded = encode(v)
  let decoded = decode(encoded)
  match decoded {
    Some(CborArray(arr)) => {
      assert_eq(arr.length(), 3)
      match arr[0] {
        CborUInt(n) => assert_eq(n, 1U)
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

///|
test "cbor: map roundtrip" {
  let v = CborMap([(CborStr("a"), CborUInt(1U)), (CborStr("b"), CborBool(true))])
  let encoded = encode(v)
  let decoded = decode(encoded)
  match decoded {
    Some(CborMap(pairs)) => {
      assert_eq(pairs.length(), 2)
      match pairs[0].1 {
        CborUInt(n) => assert_eq(n, 1U)
        _ => assert_true(false)
      }
      match pairs[1].1 {
        CborBool(b) => assert_true(b)
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

///|
test "cbor: null and bool roundtrip" {
  let encoded_null = encode(CborNull)
  match decode(encoded_null) {
    Some(CborNull) => assert_true(true)
    _ => assert_true(false)
  }
  let encoded_true = encode(CborBool(true))
  match decode(encoded_true) {
    Some(CborBool(b)) => assert_true(b)
    _ => assert_true(false)
  }
  let encoded_false = encode(CborBool(false))
  match decode(encoded_false) {
    Some(CborBool(b)) => assert_false(b)
    _ => assert_true(false)
  }
}
