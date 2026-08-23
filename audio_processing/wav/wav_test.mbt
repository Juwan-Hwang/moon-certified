///|
/// Unwrap an Option or fail the test (never returns on None).
fn[T] unwrap_or_fail(o : T?) -> T {
  match o {
    Some(v) => v
    None => abort("unexpected None in test")
  }
}

///|
/// Assert that an Option.is_empty().
fn[T] expect_none(o : T?) -> Unit {
  match o {
    Some(_) => abort("expected None but got Some")
    None => ()
  }
}

///|
fn max_diff(a : Array[Double], b : Array[Double]) -> Double {
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  let mut m = 0.0
  for i = 0; i < n; i = i + 1 {
    let d = (a[i] - b[i]).abs()
    if d > m {
      m = d
    }
  }
  m
}

///|
test "roundtrip_pcm_uint8" {
  let x = [0.0, 0.5, -0.5, 1.0, -1.0, 0.25, -0.25]
  let bytes = unwrap_or_fail(encode(8000, 1, x, PcmUint8))
  let w = unwrap_or_fail(parse(bytes))
  assert_eq(w.sample_rate, 8000)
  assert_eq(w.channels, 1)
  assert_eq(w.bits_per_sample, 8)
  let y = decode(w)
  assert_eq(y.length(), x.length())
  // 8-bit quantization step is 1/128 → tolerance 1/128 + rounding.
  assert_true(max_diff(x, y) < 1.0 / 128.0 + 1.0e-9)
}

///|
test "roundtrip_pcm_int16" {
  let x = [0.0, 0.5, -0.5, 0.999, -1.0, 0.001, -0.001]
  let bytes = unwrap_or_fail(encode(44100, 1, x, PcmInt16))
  let w = unwrap_or_fail(parse(bytes))
  assert_eq(w.bits_per_sample, 16)
  let y = decode(w)
  // 16-bit step is 1/32768.
  assert_true(max_diff(x, y) < 1.0 / 32768.0 + 1.0e-9)
}

///|
test "roundtrip_pcm_int24" {
  let x = [0.0, 0.5, -0.5, 0.999999, -1.0]
  let bytes = unwrap_or_fail(encode(48000, 1, x, PcmInt24))
  let w = unwrap_or_fail(parse(bytes))
  assert_eq(w.bits_per_sample, 24)
  assert_true(max_diff(x, decode(w)) < 1.0 / 8388608.0 + 1.0e-9)
}

///|
test "roundtrip_pcm_int32" {
  let x = [0.0, 0.5, -0.5, 0.999999999, -1.0]
  let bytes = unwrap_or_fail(encode(96000, 1, x, PcmInt32))
  let w = unwrap_or_fail(parse(bytes))
  assert_eq(w.bits_per_sample, 32)
  assert_true(max_diff(x, decode(w)) < 4.0 / 2147483648.0)
}

///|
test "roundtrip_float32" {
  let x = [0.0, 0.5, -0.5, 1.0, -1.0, 0.123456789]
  let bytes = unwrap_or_fail(encode(44100, 1, x, IeeeFloat32))
  let w = unwrap_or_fail(parse(bytes))
  assert_eq(w.bits_per_sample, 32)
  // Float32 storage: tolerance ~1e-7 relative.
  assert_true(max_diff(x, decode(w)) < 1.0e-7)
}

///|
test "roundtrip_stereo_interleaved" {
  // Two channels with distinct content; interleaving must survive.
  let x = [1.0, -1.0, 0.5, -0.5, 0.25, -0.25]
  let bytes = unwrap_or_fail(encode(44100, 2, x, PcmInt16))
  let w = unwrap_or_fail(parse(bytes))
  assert_eq(w.channels, 2)
  let y = decode(w)
  assert_eq(y.length(), 6)
  assert_true(max_diff(x, y) < 1.0 / 32768.0 + 1.0e-9)
}

///|
test "encode_known_values_int16" {
  // 0.5 → round(0.5·32767 + 0.5) = 16384; −1 → −32768
  let bytes = unwrap_or_fail(encode(8000, 1, [0.5, -1.0], PcmInt16))
  let w = unwrap_or_fail(parse(bytes))
  let y = decode(w)
  assert_true((y[0] - 16384.0 / 32768.0).abs() < 1.0e-12)
  assert_true((y[1] + 1.0).abs() < 1.0e-12)
}

///|
test "encode_clamps_out_of_range" {
  let bytes = unwrap_or_fail(encode(8000, 1, [2.0, -3.0], PcmInt16))
  let w = unwrap_or_fail(parse(bytes))
  let y = decode(w)
  assert_true((y[0] - 1.0).abs() <= 1.0 / 32768.0 + 1.0e-12)
  assert_true((y[1] + 1.0).abs() <= 1.0 / 32768.0 + 1.0e-12)
}

///|
test "parse_rejects_malformed" {
  // Truncated header
  expect_none(parse(Bytes::from_array([b'R', b'I'])))
  // Bad magic
  let g = unwrap_or_fail(encode(8000, 1, [0.0], PcmUint8))
  let mut bad = Array::from_iter(g.iter())
  bad[0] = b'X'
  expect_none(parse(Bytes::from_array(bad)))
  // Bad WAVE tag
  bad = Array::from_iter(g.iter())
  bad[9] = b'X'
  expect_none(parse(Bytes::from_array(bad)))
  // Unsupported format: patch audio_format to 0x0007 (µ-law) in fmt chunk.
  bad = Array::from_iter(g.iter())
  bad[20] = b'\x07'
  expect_none(parse(Bytes::from_array(bad)))
  // Empty input
  expect_none(parse(Bytes::from_array([])))
  // Non-finite samples
  expect_none(encode(8000, 1, [0.0 / 0.0], PcmInt16))
  // Invalid arguments
  expect_none(encode(0, 1, [0.0], PcmInt16))
  expect_none(encode(8000, 2, [0.0], PcmInt16))
}

///|
test "parse_skips_unknown_chunks" {
  // Hand-build: RIFF + fmt + LIST (odd length, pad byte) + data.
  let buf : Array[Byte] = []
  buf.push(b'R')
  buf.push(b'I')
  buf.push(b'F')
  buf.push(b'F')
  // riff size patched later
  buf.push(b'\x00')
  buf.push(b'\x00')
  buf.push(b'\x00')
  buf.push(b'\x00')
  buf.push(b'W')
  buf.push(b'A')
  buf.push(b'V')
  buf.push(b'E')
  // fmt chunk (16 bytes)
  buf.push(b'f')
  buf.push(b'm')
  buf.push(b't')
  buf.push(b' ')
  buf.push(b'\x10')
  buf.push(b'\x00')
  buf.push(b'\x00')
  buf.push(b'\x00')
  buf.push(b'\x01')
  buf.push(b'\x00') // PCM
  buf.push(b'\x01')
  buf.push(b'\x00') // mono
  buf.push(b'\x40')
  buf.push(b'\x1f')
  buf.push(b'\x00')
  buf.push(b'\x00') // 8000 Hz
  buf.push(b'\x80')
  buf.push(b'\x3e')
  buf.push(b'\x00')
  buf.push(b'\x00') // byte_rate 16000
  buf.push(b'\x02')
  buf.push(b'\x00') // block_align 2
  buf.push(b'\x10')
  buf.push(b'\x00') // 16 bits
  // LIST chunk with odd payload "INFO" + 1 = 5 bytes
  buf.push(b'L')
  buf.push(b'I')
  buf.push(b'S')
  buf.push(b'T')
  buf.push(b'\x05')
  buf.push(b'\x00')
  buf.push(b'\x00')
  buf.push(b'\x00')
  buf.push(b'I')
  buf.push(b'N')
  buf.push(b'F')
  buf.push(b'O')
  buf.push(b'X')
  buf.push(b'\x00') // pad byte
  // data chunk: one int16 sample = 16384
  buf.push(b'd')
  buf.push(b'a')
  buf.push(b't')
  buf.push(b'a')
  buf.push(b'\x02')
  buf.push(b'\x00')
  buf.push(b'\x00')
  buf.push(b'\x00')
  buf.push(b'\x00')
  buf.push(b'\x40')
  // patch riff size = total − 8
  let total = buf.length()
  buf[4] = ((total - 8) & 0xFF).to_byte()
  buf[5] = (((total - 8) >> 8) & 0xFF).to_byte()
  buf[6] = (((total - 8) >> 16) & 0xFF).to_byte()
  buf[7] = (((total - 8) >> 24) & 0xFF).to_byte()
  let w = unwrap_or_fail(parse(Bytes::from_array(buf)))
  assert_eq(w.sample_rate, 8000)
  let y = decode(w)
  assert_eq(y.length(), 1)
  assert_true((y[0] - 0.5).abs() < 1.0e-12)
}

///|
test "parse_rejects_block_align_mismatch" {
  let good = unwrap_or_fail(encode(8000, 1, [0.0], PcmInt16))
  let bad = Array::from_iter(good.iter())
  // block_align field: RIFF(12) + chunk header(8) + [fmt@20, ch@22,
  // rate@24, byte_rate@28] → file offset 32.
  bad[32] = b'\x08' // claim block_align 8 instead of 2
  expect_none(parse(Bytes::from_array(bad)))
}

///|
test "parse_rejects_truncated_chunk" {
  let good = unwrap_or_fail(encode(8000, 1, [0.0, 0.5], PcmInt16))
  // Cut off half the data payload.
  let cut = Array::from_iter(good.iter().take(good.length() - 1))
  expect_none(parse(Bytes::from_array(cut)))
}

///|
test "downmix_to_mono" {
  let stereo = [1.0, 0.0, 0.5, -0.5, -1.0, 1.0]
  let mono = unwrap_or_fail(downmix_to_mono(stereo, 2))
  assert_eq(mono.length(), 3)
  assert_true((mono[0] - 0.5).abs() < 1.0e-15)
  assert_true(mono[1].abs() < 1.0e-15)
  assert_true(mono[2].abs() < 1.0e-15)
  // Mono passthrough
  let same = unwrap_or_fail(downmix_to_mono([0.25, -0.75], 1))
  assert_eq(same.length(), 2)
  // Invalid
  expect_none(downmix_to_mono([0.0, 0.0, 0.0], 2))
  expect_none(downmix_to_mono([], 0))
}
