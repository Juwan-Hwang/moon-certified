/// RIFF/WAVE (`.wav`) container codec — parse, decode, and encode PCM audio.
///
/// This package provides production-grade WAV handling:
///
/// - **Parsing**: strict RIFF/WAVE header validation, `fmt ` support for
///   PCM (`format = 1`), IEEE float (`format = 3`), and WAVE_FORMAT_EXTENSIBLE
///   (`format = 0xFFFE` with PCM/float subformat); unknown chunks (e.g.
///   `LIST`, `fact`) are skipped; trailing chunks after `data` are ignored.
/// - **Decoding**: normalized samples in `[-1, 1]` from 8-bit unsigned PCM,
///   16-bit PCM, 24-bit PCM, 32-bit PCM, and 32-bit IEEE float payloads
///   (interleaved channel layout preserved).
/// - **Encoding**: quantization of normalized doubles back into any of the
///   supported formats with proper clamping and rounding; the produced byte
///   stream is a valid canonical WAV file (44-byte header + payload).
///
/// ## Conventions
///
/// - Samples are interleaved: frame `i`, channel `c` lives at index
///   `i * channels + c`.
/// - Normalization divides signed integer formats by `2^(bits−1)` (so full
///   scale maps to `(−1, 1)`, excluding the most negative value) and 8-bit
///   unsigned PCM by 128 around a 128 offset — matching common practice.
/// - Parsing rejects: bad magic, truncated headers/chunks, unsupported
///   formats, zero channels/rate, and block-align inconsistencies. A corrupt
///   input yields `None`, never a panic.
///
/// ## References
///
/// - Microsoft & IBM (1991). "Multimedia Programming Interface and Data
///   Specifications 1.0" (RIFF WAVE format specification).
/// - IETF draft-ietf-avt-wav-format: "WAVE File Format" (extensible header).
///
/// `proof-enabled` is `false`; correctness is backed by the test suite
/// (round-trips across all formats at quantization tolerance, malformed-input
/// rejection, chunk skipping, and known-value checks).

///|
/// Sample encoding format declared by the `fmt ` chunk.
pub(all) enum SampleFormat {
  /// 8-bit unsigned PCM (offset binary, center at 128).
  PcmUint8
  /// 16-bit signed little-endian PCM.
  PcmInt16
  /// 24-bit signed little-endian PCM (3 bytes per sample).
  PcmInt24
  /// 32-bit signed little-endian PCM.
  PcmInt32
  /// 32-bit IEEE-754 float, nominally in `[-1, 1]`.
  IeeeFloat32
}

///|
/// Parsed metadata + raw payload of a WAVE file.
pub(all) struct WavFile {
  /// Sample rate in Hz (must be > 0).
  sample_rate : Int
  /// Number of interleaved channels (must be > 0).
  channels : Int
  /// Bits per sample as declared by `fmt `.
  bits_per_sample : Int
  /// Resolved sample format.
  format : SampleFormat
  /// Raw data-chunk payload (interleaved frames).
  payload : Bytes
}

///|
/// Internal fmt-chunk metadata gathered before the data chunk is found.
priv struct FmtMeta {
  sample_rate : Int
  channels : Int
  bits : Int
  format : SampleFormat
}

///|
fn read_u16_le(data : Bytes, pos : Int) -> UInt {
  data[pos].to_uint() | (data[pos + 1].to_uint() << 8)
}

///|
fn read_u32_le(data : Bytes, pos : Int) -> UInt {
  data[pos].to_uint() |
  (data[pos + 1].to_uint() << 8) |
  (data[pos + 2].to_uint() << 16) |
  (data[pos + 3].to_uint() << 24)
}

///|
fn write_u16_le(buf : Array[Byte], val : UInt) -> Unit {
  buf.push((val & 0xFFU).to_byte())
  buf.push(((val >> 8) & 0xFFU).to_byte())
}

///|
fn write_u32_le(buf : Array[Byte], val : UInt) -> Unit {
  buf.push((val & 0xFFU).to_byte())
  buf.push(((val >> 8) & 0xFFU).to_byte())
  buf.push(((val >> 16) & 0xFFU).to_byte())
  buf.push(((val >> 24) & 0xFFU).to_byte())
}

///|
fn tag(
  data : Bytes,
  pos : Int,
  t0 : Byte,
  t1 : Byte,
  t2 : Byte,
  t3 : Byte,
) -> Bool {
  data[pos] == t0 &&
  data[pos + 1] == t1 &&
  data[pos + 2] == t2 &&
  data[pos + 3] == t3
}

///|
/// Bytes per sample for each supported format.
pub fn bytes_per_sample(f : SampleFormat) -> Int {
  match f {
    PcmUint8 => 1
    PcmInt16 => 2
    PcmInt24 => 3
    PcmInt32 => 4
    IeeeFloat32 => 4
  }
}

///|
/// Parse and validate a RIFF/WAVE byte stream.
///
/// Walks top-level chunks, requires exactly one well-formed `fmt ` chunk,
/// accepts the first `data` chunk found after it, and skips everything else.
/// Returns `None` on any structural violation or unsupported encoding.
pub fn parse(data : Bytes) -> WavFile? {
  let n = data.length()
  // Minimum viable file: RIFF header (12) + fmt (8+16) + data (8)
  if n < 12 + 24 + 8 {
    return None
  }
  if !tag(data, 0, b'R', b'I', b'F', b'F') ||
    !tag(data, 8, b'W', b'A', b'V', b'E') {
    return None
  }
  let riff_size = read_u32_le(data, 4).reinterpret_as_int()
  if riff_size < 4 || riff_size + 8 > n {
    return None
  }
  let limit = riff_size + 8
  let mut pos = 12
  let mut fmt : FmtMeta? = None
  while pos + 8 <= limit {
    let chunk_len = read_u32_le(data, pos + 4).reinterpret_as_int()
    if chunk_len < 0 || pos + 8 + chunk_len > limit {
      return None
    }
    if tag(data, pos, b'f', b'm', b't', b' ') {
      match fmt {
        Some(_) => return None // Duplicate fmt chunk → malformed.
        None => ()
      }
      if chunk_len < 16 {
        return None
      }
      let audio_format = read_u16_le(data, pos + 8).reinterpret_as_int()
      let channels = read_u16_le(data, pos + 10).reinterpret_as_int()
      let sample_rate = read_u32_le(data, pos + 12).reinterpret_as_int()
      // byte_rate @ 16, block_align @ 20
      let block_align = read_u16_le(data, pos + 20).reinterpret_as_int()
      let bits = read_u16_le(data, pos + 22).reinterpret_as_int()
      // WAVE_FORMAT_EXTENSIBLE: resolve through the SubFormat GUID.
      let eff_format = if audio_format == 0xFFFE {
        if chunk_len < 40 {
          return None
        }
        // GUID = subformat id (first 2 bytes) + rest; PCM GUID starts
        // 01 00 …, float GUID starts 03 00 ….
        match (read_u16_le(data, pos + 8 + 24).reinterpret_as_int(), bits) {
          (1, 8) => 1
          (1, 16) => 1
          (1, 24) => 1
          (1, 32) => 1
          (3, 32) => 3
          _ => return None
        }
      } else {
        audio_format
      }
      let format : SampleFormat = match (eff_format, bits) {
        (1, 8) => PcmUint8
        (1, 16) => PcmInt16
        (1, 24) => PcmInt24
        (1, 32) => PcmInt32
        (3, 32) => IeeeFloat32
        _ => return None
      }
      if channels <= 0 || sample_rate <= 0 {
        return None
      }
      if block_align != channels * bytes_per_sample(format) {
        return None
      }
      fmt = Some({ sample_rate, channels, bits, format })
    } else if tag(data, pos, b'd', b'a', b't', b'a') {
      let meta = match fmt {
        Some(m) => m
        None => return None
      }
      let bps = bytes_per_sample(meta.format)
      // Payload must contain whole frames.
      if chunk_len % meta.channels != 0 || chunk_len % bps != 0 {
        return None
      }
      // Copy the payload slice into an owned Bytes value.
      let buf : Array[Byte] = []
      let mut k = pos + 8
      let end = pos + 8 + chunk_len
      while k < end {
        buf.push(data[k])
        k = k + 1
      }
      let payload = Bytes::from_array(buf)
      return Some({
        sample_rate: meta.sample_rate,
        channels: meta.channels,
        bits_per_sample: meta.bits,
        format: meta.format,
        payload,
      })
    }
    // Chunks are word-aligned: odd lengths carry one pad byte.
    pos = pos + 8 + chunk_len + (if chunk_len % 2 == 1 { 1 } else { 0 })
  }
  // No data chunk found.
  None
}

///|
/// Decode the payload to interleaved normalized samples in `[-1, 1]`.
///
/// Output length equals `payload.length() / bytes_per_sample`.
pub fn decode(w : WavFile) -> Array[Double] {
  let p = w.payload
  let n = p.length()
  let out : Array[Double] = []
  match w.format {
    PcmUint8 => {
      let mut i = 0
      while i < n {
        out.push((p[i].to_int() - 128).to_double() / 128.0)
        i = i + 1
      }
    }
    PcmInt16 => {
      let mut i = 0
      while i + 1 < n {
        let raw = read_u16_le(p, i).reinterpret_as_int()
        let v = if raw >= 32768 { raw - 65536 } else { raw }
        out.push(v.to_double() / 32768.0)
        i = i + 2
      }
    }
    PcmInt24 => {
      let mut i = 0
      while i + 2 < n {
        let mut v = p[i].to_int() |
          (p[i + 1].to_int() << 8) |
          (p[i + 2].to_int() << 16)
        if v >= 8388608 {
          v = v - 16777216
        }
        out.push(v.to_double() / 8388608.0)
        i = i + 3
      }
    }
    PcmInt32 => {
      let mut i = 0
      while i + 3 < n {
        // Read as UInt64 to avoid overflow of the negative extreme.
        let u = read_u32_le(p, i).to_uint64()
        let v = if u >= 2147483648UL {
          u.reinterpret_as_int64() - 4294967296L
        } else {
          u.reinterpret_as_int64()
        }
        out.push(v.to_double() / 2147483648.0)
        i = i + 4
      }
    }
    IeeeFloat32 => {
      let mut i = 0
      while i + 3 < n {
        out.push(Float::reinterpret_from_uint(read_u32_le(p, i)).to_double())
        i = i + 4
      }
    }
  }
  out
}

///|
/// Downmix interleaved multi-channel samples to mono by averaging each
/// frame's channels. Returns the input unchanged for mono input.
pub fn downmix_to_mono(
  samples : Array[Double],
  channels : Int,
) -> Array[Double]? {
  if channels <= 0 || samples.length() % channels != 0 {
    return None
  }
  if channels == 1 {
    return Some(Array::from_iter(samples.iter()))
  }
  let frames = samples.length() / channels
  let inv = 1.0 / channels.to_double()
  Some(
    Array::makei(frames, fn(i) {
      let mut s = 0.0
      let mut c = 0
      while c < channels {
        s = s + samples[i * channels + c]
        c = c + 1
      }
      s * inv
    }),
  )
}

///|
fn push_i16_le(buf : Array[Byte], v : Int) -> Unit {
  let u = (v & 0xFFFF).reinterpret_as_uint()
  write_u16_le(buf, u)
}

///|
fn push_i24_le(buf : Array[Byte], v : Int) -> Unit {
  buf.push((v & 0xFF).to_byte())
  buf.push(((v >> 8) & 0xFF).to_byte())
  buf.push(((v >> 16) & 0xFF).to_byte())
}

///|
/// Encode interleaved normalized samples into a canonical WAV byte stream.
///
/// Samples are clamped to `[-1, 1]`; integer formats use round-to-nearest
/// quantization. Returns `None` for invalid arguments (non-positive rate /
/// channels, length not divisible by `channels`, non-finite samples).
pub fn encode(
  sample_rate : Int,
  channels : Int,
  samples : Array[Double],
  format : SampleFormat,
) -> Bytes? {
  if sample_rate <= 0 || channels <= 0 {
    return None
  }
  if samples.length() % channels != 0 {
    return None
  }
  for s in samples {
    if s.is_nan() || s.is_inf() {
      return None
    }
  }
  let bps = bytes_per_sample(format)
  let payload : Array[Byte] = match format {
    PcmUint8 => {
      let arr : Array[Byte] = []
      for s in samples {
        let x = clamp_unit(s)
        // Round-half-away-from-zero keeps the mapping symmetric.
        let q = if x >= 0.0 { x * 128.0 + 0.5 } else { x * 128.0 - 0.5 }
        let v = 128 + q.to_int()
        arr.push(clamp_int(v, 0, 255).to_byte())
      }
      arr
    }
    PcmInt16 => {
      let arr : Array[Byte] = []
      for s in samples {
        let x = clamp_unit(s)
        let q = if x >= 0.0 { x * 32768.0 + 0.5 } else { x * 32768.0 - 0.5 }
        push_i16_le(arr, clamp_int(q.to_int(), -32768, 32767))
      }
      arr
    }
    PcmInt24 => {
      let arr : Array[Byte] = []
      for s in samples {
        let x = clamp_unit(s)
        let q = if x >= 0.0 { x * 8388608.0 + 0.5 } else { x * 8388608.0 - 0.5 }
        push_i24_le(arr, clamp_int(q.to_int(), -8388608, 8388607))
      }
      arr
    }
    PcmInt32 => {
      let arr : Array[Byte] = []
      for s in samples {
        let x = clamp_unit(s)
        let q = if x >= 0.0 {
          x * 2147483648.0 + 0.5
        } else {
          x * 2147483648.0 - 0.5
        }
        // Clamp into the closed Int32 range before bit-casting.
        let qi = if q <= -2147483648.0 {
          -2147483648
        } else if q >= 2147483647.0 {
          2147483647
        } else {
          q.to_int()
        }
        write_u32_le(arr, qi.reinterpret_as_uint())
      }
      arr
    }
    IeeeFloat32 => {
      let arr : Array[Byte] = []
      for s in samples {
        write_u32_le(arr, Float::from_double(s).reinterpret_as_uint())
      }
      arr
    }
  }
  let data_len = payload.length()
  let out : Array[Byte] = []
  // RIFF header
  out.push(b'R')
  out.push(b'I')
  out.push(b'F')
  out.push(b'F')
  write_u32_le(out, (36 + data_len).reinterpret_as_uint())
  out.push(b'W')
  out.push(b'A')
  out.push(b'V')
  out.push(b'E')
  // fmt chunk
  out.push(b'f')
  out.push(b'm')
  out.push(b't')
  out.push(b' ')
  write_u32_le(out, 16)
  let audio_format : UInt = match format {
    IeeeFloat32 => 3U
    _ => 1U
  }
  write_u16_le(out, audio_format)
  write_u16_le(out, channels.reinterpret_as_uint())
  write_u32_le(out, sample_rate.reinterpret_as_uint())
  write_u32_le(out, (sample_rate * channels * bps).reinterpret_as_uint())
  write_u16_le(out, (channels * bps).reinterpret_as_uint())
  write_u16_le(out, (bps * 8).reinterpret_as_uint())
  // data chunk
  out.push(b'd')
  out.push(b'a')
  out.push(b't')
  out.push(b'a')
  write_u32_le(out, data_len.reinterpret_as_uint())
  for b in payload {
    out.push(b)
  }
  Some(Bytes::from_array(out))
}

///|
fn clamp_unit(x : Double) -> Double {
  if x < -1.0 {
    -1.0
  } else if x > 1.0 {
    1.0
  } else {
    x
  }
}

///|
fn clamp_int(v : Int, lo : Int, hi : Int) -> Int {
  if v < lo {
    lo
  } else if v > hi {
    hi
  } else {
    v
  }
}
