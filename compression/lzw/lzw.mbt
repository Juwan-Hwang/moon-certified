/// LZW (Lempel-Ziv-Welch) — Lossless dictionary compression.
///
/// LZW builds a dictionary of seen byte sequences on the fly. It outputs
/// dictionary codes instead of raw bytes, achieving compression for inputs
/// with repeated patterns. Used in GIF and TIFF.
///
/// ## Dictionary size
///
/// The maximum dictionary size is configurable via `compress_with_max_dict_size`
/// and `decompress_with_max_dict_size`. The default (`compress` / `decompress`)
/// uses 4096 entries (12-bit codes), which is GIF-compatible. Larger dictionary
/// sizes (e.g. 32768 for 15-bit codes, as in UNIX `compress`) yield better
/// compression ratios at the cost of more memory.
///
/// ## Complexity
/// - Compression: O(n) where n = input length.
/// - Decompression: O(n) output length.
///
/// Not formally verified. Correctness is ensured by the test suite.

///|
/// Initial dictionary size: 256 entries (all single bytes).
const INITIAL_DICT_SIZE : Int = 256

///|
/// Default maximum dictionary size (12-bit codes = 4096 entries, GIF-compatible).
const DEFAULT_MAX_DICT_SIZE : Int = 4096

///|
/// Compress `data` into a list of LZW codes using the default max dictionary
/// size (4096 entries, 12-bit codes, GIF-compatible).
pub fn compress(data : Bytes) -> Array[Int] {
  compress_with_max_dict_size(data, DEFAULT_MAX_DICT_SIZE)
}

///|
/// Compress `data` with a configurable maximum dictionary size.
///
/// `max_dict_size` controls when the dictionary stops growing. A value of
/// 4096 produces 12-bit codes (GIF-compatible); 32768 produces 15-bit codes
/// (UNIX compress-compatible). Values below 256 are clamped to 256.
pub fn compress_with_max_dict_size(
  data : Bytes,
  max_dict_size : Int,
) -> Array[Int] {
  if data.length() == 0 {
    return []
  }
  let max_size = if max_dict_size < INITIAL_DICT_SIZE {
    INITIAL_DICT_SIZE
  } else {
    max_dict_size
  }
  // Dictionary: maps string → code. We use a simple approach with
  // prefix+byte pairs. For performance, we represent strings as (code, byte).
  let dict : Map[(Int, Int), Int] = Map([])
  let mut next_code = INITIAL_DICT_SIZE
  let codes : Array[Int] = []
  let mut prefix = data[0].to_int()
  for i = 1; i < data.length(); i = i + 1 {
    let byte = data[i].to_int()
    let key = (prefix, byte)
    match dict.get(key) {
      Some(code) => prefix = code
      None => {
        codes.push(prefix)
        if next_code < max_size {
          dict[key] = next_code
          next_code = next_code + 1
        }
        prefix = byte
      }
    }
  }
  codes.push(prefix)
  codes
}

///|
/// Decompress LZW `codes` back into the original bytes using the default max
/// dictionary size (4096 entries).
pub fn decompress(codes : Array[Int]) -> Bytes? {
  decompress_with_max_dict_size(codes, DEFAULT_MAX_DICT_SIZE)
}

///|
/// Decompress LZW `codes` with a configurable maximum dictionary size.
///
/// `max_dict_size` must match the value used during compression. Values below
/// 256 are clamped to 256.
pub fn decompress_with_max_dict_size(
  codes : Array[Int],
  max_dict_size : Int,
) -> Bytes? {
  if codes.length() == 0 {
    return Some(b"")
  }
  let max_size = if max_dict_size < INITIAL_DICT_SIZE {
    INITIAL_DICT_SIZE
  } else {
    max_dict_size
  }
  // Dictionary: code → byte sequence (stored as Array[Byte]).
  // Initialize with single-byte entries 0..255.
  let dict : Map[Int, Array[Byte]] = Map([])
  for i = 0; i < INITIAL_DICT_SIZE; i = i + 1 {
    dict[i] = [i.to_byte()]
  }
  let mut next_code = INITIAL_DICT_SIZE
  let output : Array[Byte] = []
  let mut prev = match dict.get(codes[0]) {
    None => return None
    Some(seq) => {
      for b in seq {
        output.push(b)
      }
      seq
    }
  }
  for i = 1; i < codes.length(); i = i + 1 {
    let code = codes[i]
    let entry : Array[Byte] = match dict.get(code) {
      Some(seq) => Array::copy(seq)
      None =>
        if code == next_code {
          let e = Array::copy(prev)
          e.push(prev[0])
          e
        } else {
          return None // Invalid code
        }
    }
    for b in entry {
      output.push(b)
    }
    if next_code < max_size {
      let new_entry = Array::copy(prev)
      new_entry.push(entry[0])
      dict[next_code] = new_entry
      next_code = next_code + 1
    }
    prev = entry
  }
  Some(Bytes::from_array(output))
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "lzw: round-trip basic" {
  let data = b"ABABABABABABABAB"
  let codes = compress(data)
  let result = decompress(codes)
  assert_true(result is Some(_))
  assert_true(data == result.unwrap())
}

///|
test "lzw: empty input" {
  let codes = compress(b"")
  assert_eq(codes.length(), 0)
  let result = decompress(codes)
  assert_true(result is Some(_))
  assert_eq(result.unwrap().length(), 0)
}

///|
test "lzw: single byte" {
  let data = b"A"
  let codes = compress(data)
  let result = decompress(codes)
  assert_true(result is Some(_))
  assert_true(data == result.unwrap())
}

///|
test "lzw: repetitive data compresses well" {
  let data = b"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
  let codes = compress(data)
  // Highly repetitive data should produce few codes.
  assert_true(codes.length() < data.length())
}

///|
test "lzw: mixed content round-trip" {
  let data = b"TOBEORNOTTOBEORTOBEORNOT"
  let codes = compress(data)
  let result = decompress(codes)
  assert_true(result is Some(_))
  assert_true(data == result.unwrap())
}

///|
test "lzw: configurable dictionary size" {
  let data = b"TOBEORNOTTOBEORTOBEORNOT"
  // Test with larger dictionary.
  let codes = compress_with_max_dict_size(data, 32768)
  let result = decompress_with_max_dict_size(codes, 32768)
  assert_true(result is Some(_))
  assert_true(data == result.unwrap())
  // Test with minimum dictionary (no new entries).
  let codes2 = compress_with_max_dict_size(data, 256)
  let result2 = decompress_with_max_dict_size(codes2, 256)
  assert_true(result2 is Some(_))
  assert_true(data == result2.unwrap())
}
