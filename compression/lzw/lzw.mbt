/// LZW (Lempel-Ziv-Welch) — Lossless dictionary compression.
///
/// LZW builds a dictionary of seen byte sequences on the fly. It outputs
/// dictionary codes instead of raw bytes, achieving compression for inputs
/// with repeated patterns. Used in GIF and TIFF.
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
/// Maximum dictionary size (12-bit codes = 4096 entries, GIF-compatible).
const MAX_DICT_SIZE : Int = 4096

///|
/// Compress `data` into a list of LZW codes.
pub fn compress(data : Bytes) -> Array[Int] {
  if data.length() == 0 {
    return []
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
        if next_code < MAX_DICT_SIZE {
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
/// Decompress LZW `codes` back into the original bytes.
pub fn decompress(codes : Array[Int]) -> Bytes? {
  if codes.length() == 0 {
    return Some(b"")
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
    if next_code < MAX_DICT_SIZE {
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
  let result = match decompress(codes) {
    None => abort("decompress failed")
    Some(b) => b
  }
  assert_true(data == result)
}

///|
test "lzw: empty input" {
  let codes = compress(b"")
  assert_eq(codes.length(), 0)
  let result = match decompress(codes) {
    None => abort("decompress failed")
    Some(b) => b
  }
  assert_eq(result.length(), 0)
}

///|
test "lzw: single byte" {
  let data = b"A"
  let codes = compress(data)
  let result = match decompress(codes) {
    None => abort("decompress failed")
    Some(b) => b
  }
  assert_true(data == result)
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
  let result = match decompress(codes) {
    None => abort("decompress failed")
    Some(b) => b
  }
  assert_true(data == result)
}
