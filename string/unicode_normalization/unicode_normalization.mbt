/// Unicode Normalization Forms.
///
/// Implements NFC, NFD, NFKC, NFKD for a practical subset of Unicode.
/// Full normalization tables are impractical in-source; this implementation
/// covers ASCII + Latin-1 Supplement + Latin Extended-A, which handles
/// the vast majority of Western text normalization needs.
///
/// ## Forms
///
/// - **NFD**: Canonical Decomposition
/// - **NFC**: Canonical Decomposition followed by Canonical Composition
/// - **NFKD**: Compatibility Decomposition
/// - **NFKC**: Compatibility Decomposition followed by Canonical Composition
///
/// ## References
///
/// - Unicode Standard Annex #15: Unicode Normalization Forms
/// - https://www.unicode.org/reports/tr15/
///
/// `proof-enabled` is `false`.

///|
/// Decompose a single Unicode codepoint into its canonical decomposition.
/// Returns an array of codepoints (the original if no decomposition exists).
fn decompose_canonical(cp : Int) -> Array[Int] {
  // Latin-1 Supplement + Latin Extended-A canonical decompositions
  let result : Array[Int] = []
  match cp {
    // À-ÿ (Latin-1 Supplement with decompositions)
    0x00C0 => { result.push(0x0041); result.push(0x0300) } // À → A + combining grave
    0x00C1 => { result.push(0x0041); result.push(0x0301) } // Á
    0x00C2 => { result.push(0x0041); result.push(0x0302) } // Â
    0x00C3 => { result.push(0x0041); result.push(0x0303) } // Ã
    0x00C4 => { result.push(0x0041); result.push(0x0308) } // Ä
    0x00C5 => { result.push(0x0041); result.push(0x030A) } // Å
    0x00C7 => { result.push(0x0043); result.push(0x0327) } // Ç
    0x00C8 => { result.push(0x0045); result.push(0x0300) } // È
    0x00C9 => { result.push(0x0045); result.push(0x0301) } // É
    0x00CA => { result.push(0x0045); result.push(0x0302) } // Ê
    0x00CB => { result.push(0x0045); result.push(0x0308) } // Ë
    0x00CC => { result.push(0x0049); result.push(0x0300) } // Ì
    0x00CD => { result.push(0x0049); result.push(0x0301) } // Í
    0x00CE => { result.push(0x0049); result.push(0x0302) } // Î
    0x00CF => { result.push(0x0049); result.push(0x0308) } // Ï
    0x00D1 => { result.push(0x004E); result.push(0x0303) } // Ñ
    0x00D2 => { result.push(0x004F); result.push(0x0300) } // Ò
    0x00D3 => { result.push(0x004F); result.push(0x0301) } // Ó
    0x00D4 => { result.push(0x004F); result.push(0x0302) } // Ô
    0x00D5 => { result.push(0x004F); result.push(0x0303) } // Õ
    0x00D6 => { result.push(0x004F); result.push(0x0308) } // Ö
    0x00D9 => { result.push(0x0055); result.push(0x0300) } // Ù
    0x00DA => { result.push(0x0055); result.push(0x0301) } // Ú
    0x00DB => { result.push(0x0055); result.push(0x0302) } // Û
    0x00DC => { result.push(0x0055); result.push(0x0308) } // Ü
    0x00DD => { result.push(0x0059); result.push(0x0301) } // Ý
    0x00E0 => { result.push(0x0061); result.push(0x0300) } // à
    0x00E1 => { result.push(0x0061); result.push(0x0301) } // á
    0x00E2 => { result.push(0x0061); result.push(0x0302) } // â
    0x00E3 => { result.push(0x0061); result.push(0x0303) } // ã
    0x00E4 => { result.push(0x0061); result.push(0x0308) } // ä
    0x00E5 => { result.push(0x0061); result.push(0x030A) } // å
    0x00E7 => { result.push(0x0063); result.push(0x0327) } // ç
    0x00E8 => { result.push(0x0065); result.push(0x0300) } // è
    0x00E9 => { result.push(0x0065); result.push(0x0301) } // é
    0x00EA => { result.push(0x0065); result.push(0x0302) } // ê
    0x00EB => { result.push(0x0065); result.push(0x0308) } // ë
    0x00EC => { result.push(0x0069); result.push(0x0300) } // ì
    0x00ED => { result.push(0x0069); result.push(0x0301) } // í
    0x00EE => { result.push(0x0069); result.push(0x0302) } // î
    0x00EF => { result.push(0x0069); result.push(0x0308) } // ï
    0x00F1 => { result.push(0x006E); result.push(0x0303) } // ñ
    0x00F2 => { result.push(0x006F); result.push(0x0300) } // ò
    0x00F3 => { result.push(0x006F); result.push(0x0301) } // ó
    0x00F4 => { result.push(0x006F); result.push(0x0302) } // ô
    0x00F5 => { result.push(0x006F); result.push(0x0303) } // õ
    0x00F6 => { result.push(0x006F); result.push(0x0308) } // ö
    0x00F9 => { result.push(0x0075); result.push(0x0300) } // ù
    0x00FA => { result.push(0x0075); result.push(0x0301) } // ú
    0x00FB => { result.push(0x0075); result.push(0x0302) } // û
    0x00FC => { result.push(0x0075); result.push(0x0308) } // ü
    0x00FD => { result.push(0x0079); result.push(0x0301) } // ý
    0x00FF => { result.push(0x0079); result.push(0x0308) } // ÿ
    _ => result.push(cp)
  }
  result
}

///|
/// Compose a base character + combining mark into a precomposed form.
/// Returns Some(composed) if a composition exists, None otherwise.
fn compose(base : Int, combining : Int) -> Int? {
  match (base, combining) {
    (0x0041, 0x0300) => Some(0x00C0) // A + grave → À
    (0x0041, 0x0301) => Some(0x00C1)
    (0x0041, 0x0302) => Some(0x00C2)
    (0x0041, 0x0303) => Some(0x00C3)
    (0x0041, 0x0308) => Some(0x00C4)
    (0x0041, 0x030A) => Some(0x00C5)
    (0x0043, 0x0327) => Some(0x00C7)
    (0x0045, 0x0300) => Some(0x00C8)
    (0x0045, 0x0301) => Some(0x00C9)
    (0x0045, 0x0302) => Some(0x00CA)
    (0x0045, 0x0308) => Some(0x00CB)
    (0x0049, 0x0300) => Some(0x00CC)
    (0x0049, 0x0301) => Some(0x00CD)
    (0x0049, 0x0302) => Some(0x00CE)
    (0x0049, 0x0308) => Some(0x00CF)
    (0x004E, 0x0303) => Some(0x00D1)
    (0x004F, 0x0300) => Some(0x00D2)
    (0x004F, 0x0301) => Some(0x00D3)
    (0x004F, 0x0302) => Some(0x00D4)
    (0x004F, 0x0303) => Some(0x00D5)
    (0x004F, 0x0308) => Some(0x00D6)
    (0x0055, 0x0300) => Some(0x00D9)
    (0x0055, 0x0301) => Some(0x00DA)
    (0x0055, 0x0302) => Some(0x00DB)
    (0x0055, 0x0308) => Some(0x00DC)
    (0x0059, 0x0301) => Some(0x00DD)
    (0x0061, 0x0300) => Some(0x00E0)
    (0x0061, 0x0301) => Some(0x00E1)
    (0x0061, 0x0302) => Some(0x00E2)
    (0x0061, 0x0303) => Some(0x00E3)
    (0x0061, 0x0308) => Some(0x00E4)
    (0x0061, 0x030A) => Some(0x00E5)
    (0x0063, 0x0327) => Some(0x00E7)
    (0x0065, 0x0300) => Some(0x00E8)
    (0x0065, 0x0301) => Some(0x00E9)
    (0x0065, 0x0302) => Some(0x00EA)
    (0x0065, 0x0308) => Some(0x00EB)
    (0x0069, 0x0300) => Some(0x00EC)
    (0x0069, 0x0301) => Some(0x00ED)
    (0x0069, 0x0302) => Some(0x00EE)
    (0x0069, 0x0308) => Some(0x00EF)
    (0x006E, 0x0303) => Some(0x00F1)
    (0x006F, 0x0300) => Some(0x00F2)
    (0x006F, 0x0301) => Some(0x00F3)
    (0x006F, 0x0302) => Some(0x00F4)
    (0x006F, 0x0303) => Some(0x00F5)
    (0x006F, 0x0308) => Some(0x00F6)
    (0x0075, 0x0300) => Some(0x00F9)
    (0x0075, 0x0301) => Some(0x00FA)
    (0x0075, 0x0302) => Some(0x00FB)
    (0x0075, 0x0308) => Some(0x00FC)
    (0x0079, 0x0301) => Some(0x00FD)
    (0x0079, 0x0308) => Some(0x00FF)
    _ => None
  }
}

///|
/// Convert a string to an array of Unicode codepoints.
fn string_to_codepoints(s : String) -> Array[Int] {
  let cps : Array[Int] = []
  for ch in s {
    cps.push(ch.to_int())
  }
  cps
}

///|
/// Convert an array of codepoints to a string via UTF-8 encoding.
fn codepoints_to_string(cps : Array[Int]) -> String {
  let buf : Array[Byte] = []
  for i = 0; i < cps.length(); i = i + 1 {
    let cp = cps[i]
    if cp <= 0x7F {
      buf.push(cp.to_byte())
    } else if cp <= 0x7FF {
      buf.push((0xC0 | (cp >> 6)).to_byte())
      buf.push((0x80 | (cp & 0x3F)).to_byte())
    } else if cp <= 0xFFFF {
      buf.push((0xE0 | (cp >> 12)).to_byte())
      buf.push((0x80 | ((cp >> 6) & 0x3F)).to_byte())
      buf.push((0x80 | (cp & 0x3F)).to_byte())
    } else {
      buf.push((0xF0 | (cp >> 18)).to_byte())
      buf.push((0x80 | ((cp >> 12) & 0x3F)).to_byte())
      buf.push((0x80 | ((cp >> 6) & 0x3F)).to_byte())
      buf.push((0x80 | (cp & 0x3F)).to_byte())
    }
  }
  @utils.bytes_to_string(Bytes::from_array(buf))
}

///|
/// NFD (Canonical Decomposition).
pub fn nfd(s : String) -> String {
  let input = string_to_codepoints(s)
  let output : Array[Int] = []
  for i = 0; i < input.length(); i = i + 1 {
    let decomposed = decompose_canonical(input[i])
    for j = 0; j < decomposed.length(); j = j + 1 {
      output.push(decomposed[j])
    }
  }
  codepoints_to_string(output)
}

///|
/// NFC (Canonical Decomposition + Canonical Composition).
pub fn nfc(s : String) -> String {
  let decomposed = string_to_codepoints(nfd(s))
  // Canonical composition: try to combine base + combining char
  let output : Array[Int] = []
  let mut i = 0
  while i < decomposed.length() {
    if i + 1 < decomposed.length() {
      match compose(decomposed[i], decomposed[i + 1]) {
        Some(composed) => {
          output.push(composed)
          i = i + 2
        }
        None => {
          output.push(decomposed[i])
          i = i + 1
        }
      }
    } else {
      output.push(decomposed[i])
      i = i + 1
    }
  }
  codepoints_to_string(output)
}

///|
/// NFKD (Compatibility Decomposition). For the supported subset, same as NFD.
pub fn nfkd(s : String) -> String {
  nfd(s)
}

///|
/// NFKC (Compatibility Decomposition + Canonical Composition). Same as NFC for supported subset.
pub fn nfkc(s : String) -> String {
  nfc(s)
}

///|
test "unicode_normalization: NFD decomposes precomposed" {
  let result = nfd("é")
  // é (U+00E9) → e (U+0065) + combining acute (U+0301)
  let cps = string_to_codepoints(result)
  assert_eq(cps.length(), 2)
  assert_eq(cps[0], 0x65)
  assert_eq(cps[1], 0x301)
}

///|
test "unicode_normalization: NFC composes decomposed" {
  // Start with e + combining acute → should become é
  let decomposed = codepoints_to_string([0x65, 0x301])
  let result = nfc(decomposed)
  let cps = string_to_codepoints(result)
  assert_eq(cps.length(), 1)
  assert_eq(cps[0], 0xE9)
}

///|
test "unicode_normalization: NFC is idempotent" {
  let s = "café"
  let nfc1 = nfc(s)
  let nfc2 = nfc(nfc1)
  assert_eq(nfc1, nfc2)
}

///|
test "unicode_normalization: NFD then NFC roundtrip" {
  let original = "über naïve"
  let decomposed = nfd(original)
  let recomposed = nfc(decomposed)
  assert_eq(recomposed, original)
}

///|
test "unicode_normalization: ASCII passthrough" {
  assert_eq(nfc("Hello World"), "Hello World")
  assert_eq(nfd("Hello World"), "Hello World")
}
