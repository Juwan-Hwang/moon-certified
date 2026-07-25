/// Cyclic Redundancy Check (CRC) checksums for error-detection.
///
/// A CRC treats a message as a polynomial over GF(2) and computes the remainder
/// of its division by a fixed generator polynomial. The remainder is the
/// checksum appended to (or exchanged alongside) the message; a receiver
/// re-runs the same division and compares, detecting any burst of bit errors
/// shorter than the polynomial degree plus many longer error patterns.
///
/// This module implements three widely-deployed 16- and 32-bit CRCs, each via a
/// **256-entry lookup table** precomputed once at module-initialisation time so
/// that checksumming is a single table lookup per input byte — **O(n)** with a
/// tiny constant, and zero per-call allocation.
///
/// # Variants
///
/// | Function        | Standard alias        | poly      | init      | refl | xorout    | check ("123456789") |
/// |-----------------|-----------------------|-----------|-----------|------|-----------|---------------------|
/// | `crc32`         | CRC-32 / ISO-HDLC     | 0xEDB88320| 0xFFFFFFFF| yes  | 0xFFFFFFFF| 0xCBF43926          |
/// | `crc16_ccitt`   | CRC-16/CCITT-FALSE    | 0x1021    | 0xFFFF    | no   | 0x0000    | 0x29B1              |
/// | `crc16_modbus`  | CRC-16/MODBUS         | 0xA001    | 0xFFFF    | yes  | 0x0000    | 0x4B37              |
///
/// `poly` is shown in the *processing* orientation: reflected polynomials
/// (CRC-32, CRC-16/Modbus) are stored already bit-reversed so the engine can
/// shift right; the non-reflected CRC-16/CCITT shifts left with the normal
/// polynomial.
///
/// # Reflection
///
/// "Reflected" CRCs process the least-significant bit first (both input and
/// output are bit-reversed). This matches little-endian hardware (Ethernet,
/// PCI) and is the convention for CRC-32 and CRC-16/Modbus. CRC-16/CCITT-FALSE
/// is **non-reflected** (most-significant-bit first), the classical
/// CCITT orientation.
///
/// # On the CRC-16/CCITT variant
///
/// The "CCITT" family with polynomial `0x1021` has several members that differ
/// only in init / reflection / xorout. The genuine X.25 / Bluetooth variant is
/// **CRC-16/X-25** (`init=0xFFFF`, reflected, `xorout=0xFFFF`, check
/// `0x906E`), which is reflected and therefore conflicts with this module's
/// specification that reflection applies only to CRC-32 and CRC-16/Modbus.
/// This module therefore implements the canonical **non-reflected** member —
/// CRC-16/CCITT-FALSE (`init=0xFFFF`, `xorout=0x0000`, check `0x29B1`) — which
/// is the variant most commonly labelled plain "CRC-16-CCITT" and is consistent
/// with the non-reflection constraint. Switching to X.25 would only require
/// reflecting the table engine and XOR-ing the final value with `0xFFFF`.
///
/// # Strings vs. byte arrays
///
/// MoonBit `String` is internally UTF-16; its deprecated `to_bytes` yields
/// UTF-16LE code units, which is *not* what a CRC-over-a-string conventionally
/// means. `crc32_str` therefore encodes the string's Unicode code-point
/// sequence to **UTF-8** (the byte encoding used by every interop partner —
/// ZIP, PNG, HTTP, Python's `zlib.crc32(s.encode())`, …) and checksums those
/// bytes, streaming them so no intermediate array is allocated. Consequently
/// `crc32_str(s)` always equals `crc32(utf8_bytes(s))` (verified by the
/// cross-check tests), and ASCII inputs match byte-by-byte.
///
/// # Return types
///
/// CRC-32 returns `UInt` (a full 32-bit checksum needs the unsigned 32-bit
/// type — e.g. the all-`0xFF` vector is `0xFFFFFFFF`). The CRC-16 variants
/// return `Int`; their values always lie in `[0, 0xFFFF]` and are non-negative,
/// so a signed 32-bit `Int` carries them without sign tricks.
///
/// # Why `Byte` and not `UInt8`
///
/// MoonBit's core has no `UInt8` type; the native 8-bit unsigned integer is
/// `Byte` (`moonbitlang/core/byte`). The public API therefore takes
/// `FixedArray[Byte]`. This is the idiomatic and only correct choice in
/// MoonBit.
///
/// Not formally verified. Correctness is ensured by the comprehensive test
/// suite below, whose expected values are cross-checked against independent
/// reference implementations (Python's `zlib.crc32` and a from-scratch
/// bit-by-bit model).

// ---------------------------------------------------------------------------
// Polynomials and parameters
// ---------------------------------------------------------------------------

/// CRC-32 generator polynomial in *reflected* (LSB-first) form.
/// `0xEDB88320` is the bit-reversal of `0x04C11DB7` (the IEEE 802.3 /
/// ISO-HDLC polynomial). Used by Ethernet, ZIP, PNG, gzip.
const CRC32_POLY : UInt = 0xEDB88320U

/// CRC-16/CCITT generator polynomial `0x1021` (normal, MSB-first form).
/// `0x1021` = x^16 + x^12 + x^5 + 1, the CCITT-recommended polynomial.
const CRC16_CCITT_POLY : Int = 0x1021

/// CRC-16/Modbus generator polynomial in *reflected* form.
/// `0xA001` is the bit-reversal of `0x8005` (the ARC / Modbus polynomial).
const CRC16_MODBUS_POLY : Int = 0xA001

/// Initial register value shared by all three variants.
/// CRC-32, CRC-16/CCITT-FALSE and CRC-16/Modbus all initialise to all-ones.
const CRC32_INIT : UInt = 0xFFFFFFFFU

const CRC16_INIT : Int = 0xFFFF

/// Final XOR applied to CRC-32 (the all-ones complement that turns the
/// running remainder into the conventional check value).
const CRC32_XOROUT : UInt = 0xFFFFFFFFU

// ---------------------------------------------------------------------------
// Lookup tables — precomputed once at module initialisation
// ---------------------------------------------------------------------------
//
// A top-level `let` initialised with a builder call is evaluated exactly once
// when the module loads — MoonBit's equivalent of a static initialiser. Each
// table has 256 entries, one per possible byte value, so the per-byte update is
// a single index + XOR regardless of the byte's value (true O(n) checksumming
// with no bit loop on the hot path).

/// Build the 256-entry reflected CRC table for `poly` (LSB-first engine).
///
/// For each index `i` in `[0,256)`, simulate processing the *low* byte `i`
/// through 8 right-shift rounds:
///   crc = i; repeat 8 times: crc = (crc >> 1) ^ (crc & 1 ? poly : 0)
/// The stored entry is the residual after those 8 rounds, so the hot-path
/// update need only `(crc >> 8) ^ table[(crc ^ byte) & 0xFF]`.
fn build_reflected_table(poly : UInt) -> FixedArray[UInt] {
  let table = FixedArray::make(256, 0U)
  for i = 0; i < 256; i = i + 1 {
    let mut crc = i.reinterpret_as_uint()
    for _ in 0..<8 {
      if (crc & 1U) != 0U {
        crc = (crc >> 1) ^ poly
      } else {
        crc = crc >> 1
      }
    }
    table[i] = crc
  }
  table
}

/// Build the 256-entry reflected CRC-16 table for `poly` (LSB-first engine,
/// 16-bit residuals).
///
/// Identical in spirit to [`build_reflected_table`] but for 16-bit registers:
/// each entry is the residual of processing the byte `i` through 8 right-shift
/// rounds, masked to 16 bits. `poly` must already be in reflected form
/// (e.g. `0xA001` for Modbus). The hot-path update is then
/// `crc = (crc >> 8) ^ table[(crc ^ byte) & 0xFF]`.
fn build_reflected_table16(poly : Int) -> FixedArray[Int] {
  let table = FixedArray::make(256, 0)
  for i = 0; i < 256; i = i + 1 {
    let mut crc = i
    for _ in 0..<8 {
      if (crc & 1) != 0 {
        crc = (crc >> 1) ^ poly
      } else {
        crc = crc >> 1
      }
    }
    table[i] = crc & 0xFFFF
  }
  table
}

/// Build the 256-entry **non-reflected** CRC-16 table for `poly` (MSB-first
/// engine).
///
/// For each index `i`, place `i` in the *high* byte (`i << 8`) and run 8
/// left-shift rounds, masking to 16 bits each step so the residual stays in
/// `[0, 0xFFFF]`:
///   crc = i << 8; repeat 8 times:
///     crc = (crc & 0x8000) ? ((crc << 1) ^ poly) : (crc << 1);  crc &= 0xFFFF
/// The hot-path update is then `crc = ((crc << 8) ^ table[((crc >> 8) ^ byte) & 0xFF]) & 0xFFFF`.
fn build_nonreflected_table(poly : Int) -> FixedArray[Int] {
  let table = FixedArray::make(256, 0)
  for i = 0; i < 256; i = i + 1 {
    let mut crc = i << 8
    for _ in 0..<8 {
      if (crc & 0x8000) != 0 {
        crc = ((crc << 1) ^ poly) & 0xFFFF
      } else {
        crc = (crc << 1) & 0xFFFF
      }
    }
    table[i] = crc
  }
  table
}

/// Precomputed CRC-32 (reflected) lookup table. `table[1] == 0x77073096` is the
/// canonical first entry of the IEEE 802.3 table.
let crc32_table : FixedArray[UInt] = build_reflected_table(CRC32_POLY)

/// Precomputed CRC-16/CCITT-FALSE (non-reflected) lookup table.
let crc16_ccitt_table : FixedArray[Int] = build_nonreflected_table(CRC16_CCITT_POLY)

/// Precomputed CRC-16/Modbus (reflected) lookup table.
let crc16_modbus_table : FixedArray[Int] = build_reflected_table16(CRC16_MODBUS_POLY)

// ---------------------------------------------------------------------------
// UTF-8 streaming encoder (shared by crc32_str and the test cross-check)
// ---------------------------------------------------------------------------

/// Emit the 1–4 UTF-8 bytes of a single Unicode code point `cp` via `emit`.
///
/// Factored out so that [`crc32_str`] can stream bytes straight into the CRC
/// fold (zero allocation) while the test harness can collect the same bytes
/// into an array for the `crc32_str`-vs-`crc32` cross-check — guaranteeing the
/// two paths can never diverge because they share this single encoder.
///
/// Ranges follow RFC 3629:
///   U+0000   .. U+007F   -> 1 byte  (0xxxxxxx)
///   U+0080   .. U+07FF   -> 2 bytes (110xxxxx 10xxxxxx)
///   U+0800   .. U+FFFF   -> 3 bytes (1110xxxx 10xxxxxx 10xxxxxx)
///   U+10000  .. U+10FFFF -> 4 bytes (11110xxx 10xxxxxx 10xxxxxx 10xxxxxx)
fn utf8_encode(cp : UInt, emit : (Byte) -> Unit) -> Unit {
  if cp < 0x80U {
    emit(cp.to_byte())
  } else if cp < 0x800U {
    emit((0xC0U | (cp >> 6)).to_byte())
    emit((0x80U | (cp & 0x3FU)).to_byte())
  } else if cp < 0x10000U {
    emit((0xE0U | (cp >> 12)).to_byte())
    emit((0x80U | ((cp >> 6) & 0x3FU)).to_byte())
    emit((0x80U | (cp & 0x3FU)).to_byte())
  } else {
    emit((0xF0U | (cp >> 18)).to_byte())
    emit((0x80U | ((cp >> 12) & 0x3FU)).to_byte())
    emit((0x80U | ((cp >> 6) & 0x3FU)).to_byte())
    emit((0x80U | (cp & 0x3FU)).to_byte())
  }
}

/// Materialise the UTF-8 encoding of `s` as a fresh `FixedArray[Byte]`.
///
/// Used only by tests to build the byte array fed to [`crc32`] for the
/// cross-check against [`crc32_str`]. The shared [`utf8_encode`] guarantees the
/// bytes here are byte-for-byte identical to those [`crc32_str`] consumes.
fn utf8_bytes(s : String) -> FixedArray[Byte] {
  let buf : Array[Byte] = []
  for c in s.iter() {
    utf8_encode(c.to_uint(), fn(b) { buf.push(b) })
  }
  FixedArray::from_array(buf)
}

// ---------------------------------------------------------------------------
// CRC-32 (IEEE 802.3 / ISO-HDLC) — reflected, table-driven
// ---------------------------------------------------------------------------

/// Advance the CRC-32 register by one byte (reflected engine).
///
///   idx  = (crc XOR byte) & 0xFF
///   crc' = (crc >> 8) XOR crc32_table[idx]
///
/// The XOR with the byte before masking exploits reflection: the low 8 bits of
/// the register meet the incoming byte, and the table entry — precomputed for
/// exactly that low-byte residual — replaces them.
fn crc32_step(crc : UInt, byte : Byte) -> UInt {
  let idx = ((crc ^ byte.to_uint()) & 0xFFU).reinterpret_as_int()
  (crc >> 8) ^ crc32_table[idx]
}

/// Compute CRC-32 (IEEE 802.3, reflected, init/xorout `0xFFFFFFFF`) of `data`.
///
/// Returns `0` for empty input (init XOR xorout = `0xFFFFFFFF ^ 0xFFFFFFFF`).
/// Complexity: O(n) time, O(1) extra space.
pub fn crc32(data : FixedArray[Byte]) -> UInt {
  let mut crc = CRC32_INIT
  for i = 0; i < data.length(); i = i + 1 {
    crc = crc32_step(crc, data[i])
  }
  crc ^ CRC32_XOROUT
}

/// Compute CRC-32 of the **UTF-8 encoding** of `data`.
///
/// The string's Unicode code points (MoonBit `String::iter` correctly combines
/// UTF-16 surrogate pairs into scalar values) are streamed through [`utf8_encode`]
/// directly into the CRC fold, so no intermediate byte buffer is allocated.
/// Equivalent to `crc32(utf8_bytes(data))` but allocation-free.
///
/// For ASCII input this matches a byte-for-byte checksum of the ASCII bytes;
/// for any string it matches what interop partners compute over the UTF-8 bytes.
pub fn crc32_str(data : String) -> UInt {
  let mut crc = CRC32_INIT
  for c in data.iter() {
    utf8_encode(c.to_uint(), fn(b) { crc = crc32_step(crc, b) })
  }
  crc ^ CRC32_XOROUT
}

// ---------------------------------------------------------------------------
// CRC-16/CCITT-FALSE — non-reflected, table-driven
// ---------------------------------------------------------------------------

/// Advance the CRC-16/CCITT-FALSE register by one byte (non-reflected engine).
///
///   idx  = ((crc >> 8) XOR byte) & 0xFF
///   crc' = ((crc << 8) XOR table[idx]) & 0xFFFF
///
/// The high byte of the register meets the incoming byte to select the table
/// entry; the low 16 bits are kept by masking. `crc` is always in
/// `[0, 0xFFFF]`, so `>> 8` is a clean logical shift.
fn crc16_ccitt_step(crc : Int, byte : Byte) -> Int {
  let idx = ((crc >> 8) ^ byte.to_int()) & 0xFF
  ((crc << 8) ^ crc16_ccitt_table[idx]) & 0xFFFF
}

/// Compute CRC-16/CCITT-FALSE (poly `0x1021`, init `0xFFFF`, non-reflected,
/// xorout `0x0000`) of `data`.
///
/// Returns `0xFFFF` for empty input (the init register, no xorout). The check
/// value for `"123456789"` is `0x29B1`. Complexity: O(n) time, O(1) extra space.
pub fn crc16_ccitt(data : FixedArray[Byte]) -> Int {
  let mut crc = CRC16_INIT
  for i = 0; i < data.length(); i = i + 1 {
    crc = crc16_ccitt_step(crc, data[i])
  }
  crc
}

// ---------------------------------------------------------------------------
// CRC-16/Modbus — reflected, table-driven
// ---------------------------------------------------------------------------

/// Advance the CRC-16/Modbus register by one byte (reflected engine).
///
///   idx  = (crc XOR byte) & 0xFF
///   crc' = (crc >> 8) XOR table[idx]
///
/// No final mask is needed: `crc >> 8` is at most `0x00FF` and every table
/// entry lies in `[0, 0xFFFF]`, so the XOR stays within 16 bits.
fn crc16_modbus_step(crc : Int, byte : Byte) -> Int {
  let idx = (crc ^ byte.to_int()) & 0xFF
  (crc >> 8) ^ crc16_modbus_table[idx]
}

/// Compute CRC-16/Modbus (poly `0xA001` reflected, init `0xFFFF`, reflected,
/// xorout `0x0000`) of `data`.
///
/// Returns `0xFFFF` for empty input. The check value for `"123456789"` is
/// `0x4B37`. Complexity: O(n) time, O(1) extra space.
pub fn crc16_modbus(data : FixedArray[Byte]) -> Int {
  let mut crc = CRC16_INIT
  for i = 0; i < data.length(); i = i + 1 {
    crc = crc16_modbus_step(crc, data[i])
  }
  crc
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
//
// Expected values are produced by independent reference implementations
// (Python's `zlib.crc32` for CRC-32 and a from-scratch bit-by-bit model for the
// CRC-16 variants), then pinned here as literals so the tests stay self-contained.

/// Test helper: build a `FixedArray[Byte]` from a list of integer byte values.
fn bytes_of(list : Array[Int]) -> FixedArray[Byte] {
  let n = list.length()
  let arr = FixedArray::make(n, b'\x00')
  for i = 0; i < n; i = i + 1 {
    arr[i] = list[i].to_byte()
  }
  arr
}

/// ASCII bytes of a (ASCII-only) string — for building CRC-16 test inputs.
fn ascii_bytes(s : String) -> FixedArray[Byte] {
  let n = s.length()
  let arr = FixedArray::make(n, b'\x00')
  for i = 0; i < n; i = i + 1 {
    arr[i] = s[i].to_int().to_byte()
  }
  arr
}

// --- precomputed-table sanity ------------------------------------------------

test "crc: lookup tables are precomputed at init" {
  // Canonical first entries of each standard table — proves the top-level
  // `let` builders ran at module load.
  assert_eq(crc32_table[0], 0U) // reflected table[0] is always 0
  assert_eq(crc32_table[1], 0x77073096U) // IEEE 802.3 table[1]
  assert_eq(crc32_table[0xFF], 0x2D02EF8DU) // IEEE 802.3 table[255]
  // Non-reflected CCITT table[0] is always 0; table[1] = 0x1021.
  assert_eq(crc16_ccitt_table[0], 0)
  assert_eq(crc16_ccitt_table[1], 0x1021)
  // Reflected Modbus table[0] is 0. Note table[1] is NOT the polynomial: a
  // reflected table entry is the residual after 8 right-shift rounds, so
  // table[1] = 0xC0C1 (the CRC-16/MODBUS table[1]), just as CRC-32's
  // table[1] = 0x77073096 != poly 0xEDB88320. table[1] == poly only holds for
  // the non-reflected (left-shift) table, as with CCITT above.
  assert_eq(crc16_modbus_table[0], 0)
  assert_eq(crc16_modbus_table[1], 0xC0C1)
}

// --- CRC-32: known test vectors ---------------------------------------------

test "crc32: check value 123456789 = 0xCBF43926" {
  // The canonical CRC-32 check value (catalogue: CRC-32/ISO-HDLC).
  assert_eq(crc32_str("123456789"), 0xCBF43926U)
  assert_eq(crc32(ascii_bytes("123456789")), 0xCBF43926U)
}

test "crc32: empty input is zero" {
  // init 0xFFFFFFFF XOR xorout 0xFFFFFFFF == 0.
  assert_eq(crc32_str(""), 0U)
  let empty : FixedArray[Byte] = FixedArray::make(0, b'\x00')
  assert_eq(crc32(empty), 0U)
}

test "crc32: single byte" {
  // CRC-32 of 0x61 ('a') and 0x41 ('A').
  assert_eq(crc32_str("a"), 0xE8B7BE43U)
  assert_eq(crc32_str("A"), 0xD3D99E8BU)
  assert_eq(crc32(bytes_of([97])), 0xE8B7BE43U) // 'a'
  assert_eq(crc32(bytes_of([0])), 0xD202EF8DU) // single zero byte
}

test "crc32: known patterns all-zeros and all-0xFF" {
  // 4 zero bytes.
  assert_eq(crc32(FixedArray::make(4, b'\x00')), 0x2144DF1CU)
  // 4 0xFF bytes — saturates to 0xFFFFFFFF.
  assert_eq(crc32(FixedArray::make(4, b'\xFF')), 0xFFFFFFFFU)
  // 16 zero bytes / 16 0xFF bytes.
  assert_eq(crc32(FixedArray::make(16, b'\x00')), 0xECBB4B55U)
  assert_eq(crc32(FixedArray::make(16, b'\xFF')), 0x3FB3C61AU)
  // 8 zero bytes / 8 0xFF bytes.
  assert_eq(crc32(FixedArray::make(8, b'\x00')), 0x6522DF69U)
  assert_eq(crc32(FixedArray::make(8, b'\xFF')), 0x2144DF1CU)
}

test "crc32: common ASCII strings" {
  assert_eq(crc32_str("hello"), 0x3610A686U)
  assert_eq(crc32(ascii_bytes("hello")), 0x3610A686U)
  assert_eq(
    crc32_str("The quick brown fox jumps over the lazy dog"),
    0x414FA339U,
  )
}

test "crc32: UTF-8 multibyte strings" {
  // 'é' is U+00E9 -> UTF-8 0xC3 0xA9, so "héllo" is 6 bytes.
  assert_eq(crc32_str("héllo"), 0x9E3B8236U)
  // U+03C0 'π' -> 0xCF 0x80.
  assert_eq(crc32_str("π"), 0xE0035A5EU)
  // U+20AC '€' -> 0xE2 0x82 0xAC.
  assert_eq(crc32_str("€"), 0x83F2C8D6U)
  // U+4F60 '你' -> 0xE4 0xBD 0xA0 (3-byte).
  assert_eq(crc32_str("你"), 0xD617D273U)
  // Mixed ASCII + CJK.
  assert_eq(crc32_str("abc你好123"), 0xF197002DU)
}

test "crc32: cross-check crc32_str vs crc32 on identical bytes" {
  // For every string, the streaming UTF-8 path must agree with materialising
  // the UTF-8 bytes and calling crc32 — including multibyte code points.
  for s in [
    "", "a", "123456789", "hello", "The quick brown fox jumps over the lazy dog",
    "héllo", "π", "€", "你", "abc你好123", "🌟✨", // 4-byte emoji
  ] {
    assert_eq(crc32_str(s), crc32(utf8_bytes(s)))
  }
}

test "crc32: incremental composition matches whole" {
  // CRC of A++B equals folding B's bytes onto the running register of A
  // (without the final xorout). This verifies the per-byte step is the true
  // polynomial remainder update.
  let ab = ascii_bytes("Hello, world!")
  let a = ascii_bytes("Hello, ")
  let b = ascii_bytes("world!")
  // Run A through init, then continue with B, then xorout.
  let mut crc = CRC32_INIT
  for i = 0; i < a.length(); i = i + 1 {
    crc = crc32_step(crc, a[i])
  }
  for i = 0; i < b.length(); i = i + 1 {
    crc = crc32_step(crc, b[i])
  }
  assert_eq(crc ^ CRC32_XOROUT, crc32(ab))
}

test "crc32: large input is O(n) and stable" {
  // 4096 bytes of a repeating pattern; just assert it matches the reference
  // computed over the same materialised bytes (no hard-coded literal needed —
  // the cross-check here is determinism + the table engine on a long input).
  let n = 4096
  let big = FixedArray::makei(n, fn(i) { ((i * 31 + 7) % 251).to_byte() })
  let once = crc32(big)
  // Re-running is deterministic.
  assert_eq(crc32(big), once)
  // And equals the byte-wise fold done by hand via crc32_str on the same bytes
  // packed as a string only works for ASCII; instead fold manually to be sure.
  let mut manual = CRC32_INIT
  for i = 0; i < n; i = i + 1 {
    manual = crc32_step(manual, big[i])
  }
  assert_eq(manual ^ CRC32_XOROUT, once)
}

// --- CRC-16/CCITT-FALSE: known test vectors ---------------------------------

test "crc16_ccitt: check value 123456789 = 0x29B1" {
  assert_eq(crc16_ccitt(ascii_bytes("123456789")), 0x29B1)
  assert_eq(crc16_ccitt(bytes_of([49, 50, 51, 52, 53, 54, 55, 56, 57])), 0x29B1)
}

test "crc16_ccitt: empty input is init 0xFFFF" {
  let empty : FixedArray[Byte] = FixedArray::make(0, b'\x00')
  assert_eq(crc16_ccitt(empty), 0xFFFF)
}

test "crc16_ccitt: single byte" {
  assert_eq(crc16_ccitt(bytes_of([97])), 0x9D77) // 'a' = 0x61
  assert_eq(crc16_ccitt(bytes_of([0])), 0xE1F0) // single zero byte
}

test "crc16_ccitt: known patterns all-zeros and all-0xFF" {
  assert_eq(crc16_ccitt(FixedArray::make(4, b'\x00')), 0x84C0)
  assert_eq(crc16_ccitt(FixedArray::make(4, b'\xFF')), 0x1D0F)
  assert_eq(crc16_ccitt(FixedArray::make(16, b'\x00')), 0x6A0A)
  assert_eq(crc16_ccitt(FixedArray::make(16, b'\xFF')), 0x6A4B)
  assert_eq(crc16_ccitt(FixedArray::make(8, b'\x00')), 0x313E)
  assert_eq(crc16_ccitt(FixedArray::make(8, b'\xFF')), 0x97DF)
}

// --- CRC-16/Modbus: known test vectors --------------------------------------

test "crc16_modbus: check value 123456789 = 0x4B37" {
  assert_eq(crc16_modbus(ascii_bytes("123456789")), 0x4B37)
  assert_eq(crc16_modbus(bytes_of([49, 50, 51, 52, 53, 54, 55, 56, 57])), 0x4B37)
}

test "crc16_modbus: empty input is init 0xFFFF" {
  let empty : FixedArray[Byte] = FixedArray::make(0, b'\x00')
  assert_eq(crc16_modbus(empty), 0xFFFF)
}

test "crc16_modbus: single byte" {
  assert_eq(crc16_modbus(bytes_of([97])), 0xA87E) // 'a' = 0x61
  // A zero byte is *not* a no-op: it XORs into the low byte of the register and
  // drives 8 reflected shift rounds, so init 0xFFFF -> 0x40BF (verified against
  // an independent bit-by-bit model). Only an *empty* input returns init.
  assert_eq(crc16_modbus(bytes_of([0])), 0x40BF)
}

test "crc16_modbus: known patterns all-zeros and all-0xFF" {
  assert_eq(crc16_modbus(FixedArray::make(4, b'\x00')), 0x2400)
  assert_eq(crc16_modbus(FixedArray::make(4, b'\xFF')), 0xB001)
  assert_eq(crc16_modbus(FixedArray::make(16, b'\x00')), 0xF0BE)
  assert_eq(crc16_modbus(FixedArray::make(16, b'\xFF')), 0x80FE)
  assert_eq(crc16_modbus(FixedArray::make(8, b'\x00')), 0x0B40)
  assert_eq(crc16_modbus(FixedArray::make(8, b'\xFF')), 0x8F01)
}

// --- cross-variant sanity ----------------------------------------------------

test "crc: distinct variants give distinct checksums for same input" {
  // The three CRCs are different functions; for a non-trivial input they must
  // not collide with each other (sanity, not a proof of collision-resistance).
  let data = ascii_bytes("123456789")
  let c32 = crc32(data)
  let c16c = crc16_ccitt(data)
  let c16m = crc16_modbus(data)
  assert_true(c32 != 0U)
  assert_true(c16c != c16m)
  // CRC-16 values stay within 16 bits.
  assert_true(c16c >= 0 && c16c <= 0xFFFF)
  assert_true(c16m >= 0 && c16m <= 0xFFFF)
}

test "crc: byte order sensitivity" {
  // Reversing bytes changes the CRC (the polynomial division is order-sensitive).
  let fwd = ascii_bytes("abc")
  let rev = bytes_of([99, 98, 97]) // "cba"
  assert_true(crc32(fwd) != crc32(rev))
  assert_true(crc16_ccitt(fwd) != crc16_ccitt(rev))
  assert_true(crc16_modbus(fwd) != crc16_modbus(rev))
}
