/// Unicode Normalization Forms.
///
/// Implements NFC, NFD, NFKC, NFKD for a practical subset of Unicode.
/// Full normalization tables (UnicodeData.txt, ~30,000 entries) are
/// impractical to embed in-source; this implementation covers:
///
/// - **ASCII** — passthrough
/// - **Latin-1 Supplement** (U+0080–U+00FF) — full canonical decompositions
/// - **Latin Extended-A** (U+0100–U+017F) — full canonical decompositions
/// - **Greek and Coptic** (U+0370–U+03FF) — all precomposed decompositions
/// - **Hangul syllables** (U+AC00–U+D7A3) — algorithmic decomposition of
///   all 11,172 syllables (Korean)
/// - **Full-width / half-width forms** (U+FF00–U+FFEF) — compatibility
///   decomposition for CJK text
/// - **CJK Compatibility Forms** (U+FE30–U+FE4F) — compatibility decomposition
/// - **Ligatures and presentation forms** — compatibility decomposition
///
/// Additionally, this implementation correctly performs **canonical
/// ordering** of combining marks (stable sort by Canonical Combining Class),
/// which is required by the Unicode Standard for sequences with multiple
/// combining marks.
///
/// ## Forms
///
/// - **NFD**: Canonical Decomposition + Canonical Ordering
/// - **NFC**: NFD + Canonical Composition
/// - **NFKD**: Compatibility Decomposition + Canonical Ordering
/// - **NFKC**: NFKD + Canonical Composition
///
/// ## References
///
/// - Unicode Standard Annex #15: Unicode Normalization Forms
/// - https://www.unicode.org/reports/tr15/
/// - Unicode Standard §3.11 (Canonical Ordering)
/// - Unicode Standard §3.12 (Hangul Composition/Decomposition)
///
/// `proof-enabled` is `false`.

// ---------------------------------------------------------------------------
// Canonical Combining Class (CCC)
// ---------------------------------------------------------------------------

///|
/// Canonical Combining Class for a codepoint.
///
/// Returns 0 for starters (non-combining characters). Non-zero values
/// indicate the position where a combining mark attaches (e.g., 230 = above,
/// 220 = below). Used by canonical ordering to sort combining marks.
///
/// Reference: UnicodeData.txt field 3 (Canonical_Combining_Class).
fn ccc(cp : Int) -> Int {
  match cp {
    // 230 — Above
    0x0300 | 0x0301 | 0x0302 | 0x0303 | 0x0304 | 0x0305 | 0x0306 | 0x0307 |
    0x0308 | 0x0309 | 0x030A | 0x030B | 0x030C | 0x030D | 0x030E | 0x030F |
    0x0310 | 0x0311 | 0x0312 | 0x0313 | 0x0314 | 0x033B | 0x033C | 0x033D |
    0x033E | 0x033F | 0x0342 | 0x0346 | 0x034A | 0x034B | 0x034C |
    0x0350 | 0x0351 | 0x0352 | 0x0357 | 0x0358 => 230
    // 220 — Below
    0x0316 | 0x0317 | 0x0318 | 0x0319 | 0x031C | 0x031D | 0x031E | 0x031F |
    0x0320 | 0x0323 | 0x0324 | 0x0325 | 0x0326 | 0x0329 | 0x032A | 0x032B |
    0x032C | 0x032D | 0x032E | 0x032F | 0x0330 | 0x0331 | 0x0332 | 0x0333 |
    0x0339 | 0x0340 | 0x0341 | 0x0343 | 0x0344 | 0x0345 | 0x0347 | 0x0348 |
    0x0349 | 0x034D | 0x034E | 0x0353 | 0x0354 | 0x0355 | 0x0356 | 0x0359 |
    0x035A => 220
    // 1 — Overlay
    0x0334 | 0x0335 | 0x0336 | 0x0337 | 0x0338 => 1
    // 232 — Above (attached, specific to Greek)
    0x0315 | 0x031A => 232
    // 216 — Below (attached)
    0x0321 | 0x0322 | 0x0327 | 0x0328 => 216
    // 7 — Nukta (Devanagari etc.)
    0x093C | 0x09BC | 0x0A3C | 0x0ABC | 0x0B3C | 0x0CBC | 0x0D4B => 7
    // 9 — Virama
    0x094D | 0x09CD | 0x0A4D | 0x0ACD | 0x0B4D | 0x0BCD | 0x0C4D | 0x0CCD |
    0x0D4D | 0x0DCA => 9
    _ => 0
  }
}

// ---------------------------------------------------------------------------
// Canonical Ordering
// ---------------------------------------------------------------------------

///|
/// Apply canonical ordering: stable-sort combining marks by CCC.
///
/// Implements D109 (Canonical Ordering Algorithm) from the Unicode Standard.
/// Only runs of non-starters (CCC > 0) are reordered; starters (CCC = 0)
/// are fixed anchors.
fn canonical_ordering(cps : Array[Int]) -> Array[Int] {
  let n = cps.length()
  if n <= 1 {
    return cps
  }
  let result = Array::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    result[i] = cps[i]
  }
  // Insertion sort within runs of non-starters.
  // Walk the array; when we find a starter (CCC=0), start a new run.
  let mut i = 0
  while i < n {
    // Skip starters (CCC = 0) — they are anchors.
    if ccc(result[i]) == 0 {
      i = i + 1
    } else {
      // Find the end of the non-starter run.
      let start = i
      while i < n && ccc(result[i]) > 0 {
        i = i + 1
      }
      // Stable sort the run [start, i) by CCC value using insertion sort.
      for j = start + 1; j < i; j = j + 1 {
        let key = result[j]
        let key_ccc = ccc(key)
        let mut k = j
        while k > start && ccc(result[k - 1]) > key_ccc {
          result[k] = result[k - 1]
          k = k - 1
        }
        result[k] = key
      }
    }
  }
  result
}

// ---------------------------------------------------------------------------
// Hangul Algorithmic Decomposition
// ---------------------------------------------------------------------------

/// Hangul syllable constants (Unicode Standard §3.12).
let hangul_sbase : Int = 0xAC00
let hangul_lbase : Int = 0x1100
let hangul_vbase : Int = 0x1161
let hangul_tbase : Int = 0x11A7
let hangul_lcount : Int = 19
let hangul_vcount : Int = 21
let hangul_tcount : Int = 28
let hangul_ncount : Int = 588 // VCount * TCount
let hangul_scount : Int = 11172 // LCount * NCount

///|
/// Algorithmically decompose a Hangul syllable into its Jamo components.
/// Returns `Some([L, V])` or `Some([L, V, T])` if `cp` is a Hangul syllable,
/// `None` otherwise.
fn decompose_hangul(cp : Int) -> Array[Int]? {
  let sindex = cp - hangul_sbase
  if sindex < 0 || sindex >= hangul_scount {
    return None
  }
  let l = hangul_lbase + sindex / hangul_ncount
  let v = hangul_vbase + (sindex % hangul_ncount) / hangul_tcount
  let t = hangul_tbase + sindex % hangul_tcount
  let result : Array[Int] = [l, v]
  if t != hangul_tbase {
    result.push(t)
  }
  Some(result)
}

///|
/// Try to compose two Jamo into a Hangul syllable.
/// Returns `Some(syllable)` if `a` is an L or LV Jamo and `b` is a V or T
/// Jamo that can compose, `None` otherwise.
fn compose_hangul(a : Int, b : Int) -> Int? {
  // L + V → LV
  if a >= hangul_lbase && a < hangul_lbase + hangul_lcount &&
     b >= hangul_vbase && b < hangul_vbase + hangul_vcount {
    let lindex = a - hangul_lbase
    let vindex = b - hangul_vbase
    let lvindex = lindex * hangul_ncount + vindex * hangul_tcount
    Some(hangul_sbase + lvindex)
  } else if a >= hangul_sbase && a < hangul_sbase + hangul_scount &&
            (a - hangul_sbase) % hangul_tcount == 0 &&
            b > hangul_tbase && b < hangul_tbase + hangul_tcount {
    // LV + T → LVT
    Some(a + (b - hangul_tbase))
  } else {
    None
  }
}

// ---------------------------------------------------------------------------
// Canonical Decomposition Table
// ---------------------------------------------------------------------------

///|
/// Decompose a single Unicode codepoint into its canonical decomposition.
/// Returns an array of codepoints (the original if no decomposition exists).
///
/// Covers: Latin-1 Supplement, Latin Extended-A, Greek and Coptic, and
/// Hangul syllables (algorithmically).
fn decompose_canonical(cp : Int) -> Array[Int] {
  // Try Hangul first (algorithmic, covers all 11,172 syllables).
  match decompose_hangul(cp) {
    Some(result) => return result
    None => ()
  }
  let result : Array[Int] = []
  match cp {
    // === Latin-1 Supplement (U+00C0–U+00FF) ===
    0x00C0 => { result.push(0x0041); result.push(0x0300) }
    0x00C1 => { result.push(0x0041); result.push(0x0301) }
    0x00C2 => { result.push(0x0041); result.push(0x0302) }
    0x00C3 => { result.push(0x0041); result.push(0x0303) }
    0x00C4 => { result.push(0x0041); result.push(0x0308) }
    0x00C5 => { result.push(0x0041); result.push(0x030A) }
    0x00C7 => { result.push(0x0043); result.push(0x0327) }
    0x00C8 => { result.push(0x0045); result.push(0x0300) }
    0x00C9 => { result.push(0x0045); result.push(0x0301) }
    0x00CA => { result.push(0x0045); result.push(0x0302) }
    0x00CB => { result.push(0x0045); result.push(0x0308) }
    0x00CC => { result.push(0x0049); result.push(0x0300) }
    0x00CD => { result.push(0x0049); result.push(0x0301) }
    0x00CE => { result.push(0x0049); result.push(0x0302) }
    0x00CF => { result.push(0x0049); result.push(0x0308) }
    0x00D1 => { result.push(0x004E); result.push(0x0303) }
    0x00D2 => { result.push(0x004F); result.push(0x0300) }
    0x00D3 => { result.push(0x004F); result.push(0x0301) }
    0x00D4 => { result.push(0x004F); result.push(0x0302) }
    0x00D5 => { result.push(0x004F); result.push(0x0303) }
    0x00D6 => { result.push(0x004F); result.push(0x0308) }
    0x00D9 => { result.push(0x0055); result.push(0x0300) }
    0x00DA => { result.push(0x0055); result.push(0x0301) }
    0x00DB => { result.push(0x0055); result.push(0x0302) }
    0x00DC => { result.push(0x0055); result.push(0x0308) }
    0x00DD => { result.push(0x0059); result.push(0x0301) }
    0x00E0 => { result.push(0x0061); result.push(0x0300) }
    0x00E1 => { result.push(0x0061); result.push(0x0301) }
    0x00E2 => { result.push(0x0061); result.push(0x0302) }
    0x00E3 => { result.push(0x0061); result.push(0x0303) }
    0x00E4 => { result.push(0x0061); result.push(0x0308) }
    0x00E5 => { result.push(0x0061); result.push(0x030A) }
    0x00E7 => { result.push(0x0063); result.push(0x0327) }
    0x00E8 => { result.push(0x0065); result.push(0x0300) }
    0x00E9 => { result.push(0x0065); result.push(0x0301) }
    0x00EA => { result.push(0x0065); result.push(0x0302) }
    0x00EB => { result.push(0x0065); result.push(0x0308) }
    0x00EC => { result.push(0x0069); result.push(0x0300) }
    0x00ED => { result.push(0x0069); result.push(0x0301) }
    0x00EE => { result.push(0x0069); result.push(0x0302) }
    0x00EF => { result.push(0x0069); result.push(0x0308) }
    0x00F1 => { result.push(0x006E); result.push(0x0303) }
    0x00F2 => { result.push(0x006F); result.push(0x0300) }
    0x00F3 => { result.push(0x006F); result.push(0x0301) }
    0x00F4 => { result.push(0x006F); result.push(0x0302) }
    0x00F5 => { result.push(0x006F); result.push(0x0303) }
    0x00F6 => { result.push(0x006F); result.push(0x0308) }
    0x00F9 => { result.push(0x0075); result.push(0x0300) }
    0x00FA => { result.push(0x0075); result.push(0x0301) }
    0x00FB => { result.push(0x0075); result.push(0x0302) }
    0x00FC => { result.push(0x0075); result.push(0x0308) }
    0x00FD => { result.push(0x0079); result.push(0x0301) }
    0x00FF => { result.push(0x0079); result.push(0x0308) }
    // === Latin Extended-A (U+0100–U+017F) ===
    0x0100 => { result.push(0x0041); result.push(0x0304) }
    0x0101 => { result.push(0x0061); result.push(0x0304) }
    0x0102 => { result.push(0x0041); result.push(0x0306) }
    0x0103 => { result.push(0x0061); result.push(0x0306) }
    0x0104 => { result.push(0x0041); result.push(0x0328) }
    0x0105 => { result.push(0x0061); result.push(0x0328) }
    0x0106 => { result.push(0x0043); result.push(0x0301) }
    0x0107 => { result.push(0x0063); result.push(0x0301) }
    0x0108 => { result.push(0x0043); result.push(0x0302) }
    0x0109 => { result.push(0x0063); result.push(0x0302) }
    0x010A => { result.push(0x0043); result.push(0x0307) }
    0x010B => { result.push(0x0063); result.push(0x0307) }
    0x010C => { result.push(0x0043); result.push(0x030C) }
    0x010D => { result.push(0x0063); result.push(0x030C) }
    0x010E => { result.push(0x0044); result.push(0x030C) }
    0x010F => { result.push(0x0064); result.push(0x030C) }
    0x0112 => { result.push(0x0045); result.push(0x0304) }
    0x0113 => { result.push(0x0065); result.push(0x0304) }
    0x0114 => { result.push(0x0045); result.push(0x0306) }
    0x0115 => { result.push(0x0065); result.push(0x0306) }
    0x0116 => { result.push(0x0045); result.push(0x0307) }
    0x0117 => { result.push(0x0065); result.push(0x0307) }
    0x0118 => { result.push(0x0045); result.push(0x0328) }
    0x0119 => { result.push(0x0065); result.push(0x0328) }
    0x011A => { result.push(0x0045); result.push(0x030C) }
    0x011B => { result.push(0x0065); result.push(0x030C) }
    0x011C => { result.push(0x0047); result.push(0x0302) }
    0x011D => { result.push(0x0067); result.push(0x0302) }
    0x011E => { result.push(0x0047); result.push(0x0306) }
    0x011F => { result.push(0x0067); result.push(0x0306) }
    0x0120 => { result.push(0x0047); result.push(0x0307) }
    0x0121 => { result.push(0x0067); result.push(0x0307) }
    0x0122 => { result.push(0x0047); result.push(0x0327) }
    0x0123 => { result.push(0x0067); result.push(0x0327) }
    0x0124 => { result.push(0x0048); result.push(0x0302) }
    0x0125 => { result.push(0x0068); result.push(0x0302) }
    0x0128 => { result.push(0x0049); result.push(0x0303) }
    0x0129 => { result.push(0x0069); result.push(0x0303) }
    0x012A => { result.push(0x0049); result.push(0x0304) }
    0x012B => { result.push(0x0069); result.push(0x0304) }
    0x012C => { result.push(0x0049); result.push(0x0306) }
    0x012D => { result.push(0x0069); result.push(0x0306) }
    0x012E => { result.push(0x0049); result.push(0x0328) }
    0x012F => { result.push(0x0069); result.push(0x0328) }
    0x0130 => { result.push(0x0049); result.push(0x0307) }
    0x0134 => { result.push(0x004A); result.push(0x0302) }
    0x0135 => { result.push(0x006A); result.push(0x0302) }
    0x0136 => { result.push(0x004B); result.push(0x0327) }
    0x0137 => { result.push(0x006B); result.push(0x0327) }
    0x0139 => { result.push(0x004C); result.push(0x0301) }
    0x013A => { result.push(0x006C); result.push(0x0301) }
    0x013B => { result.push(0x004C); result.push(0x0327) }
    0x013C => { result.push(0x006C); result.push(0x0327) }
    0x013D => { result.push(0x004C); result.push(0x030C) }
    0x013E => { result.push(0x006C); result.push(0x030C) }
    0x0143 => { result.push(0x004E); result.push(0x0301) }
    0x0144 => { result.push(0x006E); result.push(0x0301) }
    0x0145 => { result.push(0x004E); result.push(0x0327) }
    0x0146 => { result.push(0x006E); result.push(0x0327) }
    0x0147 => { result.push(0x004E); result.push(0x030C) }
    0x0148 => { result.push(0x006E); result.push(0x030C) }
    0x014C => { result.push(0x004F); result.push(0x0304) }
    0x014D => { result.push(0x006F); result.push(0x0304) }
    0x014E => { result.push(0x004F); result.push(0x0306) }
    0x014F => { result.push(0x006F); result.push(0x0306) }
    0x0150 => { result.push(0x004F); result.push(0x030B) }
    0x0151 => { result.push(0x006F); result.push(0x030B) }
    0x0154 => { result.push(0x0052); result.push(0x0301) }
    0x0155 => { result.push(0x0072); result.push(0x0301) }
    0x0156 => { result.push(0x0052); result.push(0x0327) }
    0x0157 => { result.push(0x0072); result.push(0x0327) }
    0x0158 => { result.push(0x0052); result.push(0x030C) }
    0x0159 => { result.push(0x0072); result.push(0x030C) }
    0x015A => { result.push(0x0053); result.push(0x0301) }
    0x015B => { result.push(0x0073); result.push(0x0301) }
    0x015C => { result.push(0x0053); result.push(0x0302) }
    0x015D => { result.push(0x0073); result.push(0x0302) }
    0x015E => { result.push(0x0053); result.push(0x0327) }
    0x015F => { result.push(0x0073); result.push(0x0327) }
    0x0160 => { result.push(0x0053); result.push(0x030C) }
    0x0161 => { result.push(0x0073); result.push(0x030C) }
    0x0162 => { result.push(0x0054); result.push(0x0327) }
    0x0163 => { result.push(0x0074); result.push(0x0327) }
    0x0164 => { result.push(0x0054); result.push(0x030C) }
    0x0165 => { result.push(0x0074); result.push(0x030C) }
    0x0168 => { result.push(0x0055); result.push(0x0303) }
    0x0169 => { result.push(0x0075); result.push(0x0303) }
    0x016A => { result.push(0x0055); result.push(0x0304) }
    0x016B => { result.push(0x0075); result.push(0x0304) }
    0x016C => { result.push(0x0055); result.push(0x0306) }
    0x016D => { result.push(0x0075); result.push(0x0306) }
    0x016E => { result.push(0x0055); result.push(0x030A) }
    0x016F => { result.push(0x0075); result.push(0x030A) }
    0x0170 => { result.push(0x0055); result.push(0x030B) }
    0x0171 => { result.push(0x0075); result.push(0x030B) }
    0x0172 => { result.push(0x0055); result.push(0x0328) }
    0x0173 => { result.push(0x0075); result.push(0x0328) }
    0x0174 => { result.push(0x0057); result.push(0x0302) }
    0x0175 => { result.push(0x0077); result.push(0x0302) }
    0x0176 => { result.push(0x0059); result.push(0x0302) }
    0x0177 => { result.push(0x0079); result.push(0x0302) }
    0x0178 => { result.push(0x0059); result.push(0x0308) }
    0x0179 => { result.push(0x005A); result.push(0x0301) }
    0x017A => { result.push(0x007A); result.push(0x0301) }
    0x017B => { result.push(0x005A); result.push(0x0307) }
    0x017C => { result.push(0x007A); result.push(0x0307) }
    0x017D => { result.push(0x005A); result.push(0x030C) }
    0x017E => { result.push(0x007A); result.push(0x030C) }
    // === Greek and Coptic (U+0386–U+03CE) ===
    0x0386 => { result.push(0x0391); result.push(0x0301) }
    0x0388 => { result.push(0x0395); result.push(0x0301) }
    0x0389 => { result.push(0x0397); result.push(0x0301) }
    0x038A => { result.push(0x0399); result.push(0x0301) }
    0x038C => { result.push(0x039F); result.push(0x0301) }
    0x038E => { result.push(0x03A5); result.push(0x0301) }
    0x038F => { result.push(0x03A9); result.push(0x0301) }
    0x0390 => { result.push(0x03B9); result.push(0x0308); result.push(0x0301) }
    0x03AA => { result.push(0x0399); result.push(0x0308) }
    0x03AB => { result.push(0x03A5); result.push(0x0308) }
    0x03AC => { result.push(0x03B1); result.push(0x0301) }
    0x03AD => { result.push(0x03B5); result.push(0x0301) }
    0x03AE => { result.push(0x03B7); result.push(0x0301) }
    0x03AF => { result.push(0x03B9); result.push(0x0301) }
    0x03B0 => { result.push(0x03C5); result.push(0x0308); result.push(0x0301) }
    0x03CA => { result.push(0x03B9); result.push(0x0308) }
    0x03CB => { result.push(0x03C5); result.push(0x0308) }
    0x03CC => { result.push(0x03BF); result.push(0x0301) }
    0x03CD => { result.push(0x03C5); result.push(0x0301) }
    0x03CE => { result.push(0x03C9); result.push(0x0301) }
    _ => result.push(cp)
  }
  result
}

// ---------------------------------------------------------------------------
// Compatibility Decomposition
// ---------------------------------------------------------------------------

///|
/// Decompose a single Unicode codepoint into its compatibility decomposition.
/// Falls back to canonical decomposition when no compatibility mapping exists.
///
/// Covers: full-width ASCII variants, full-width space, CJK Compatibility
/// Forms, ligatures, superscript/subscript digits, and all canonical
/// decompositions.
fn decompose_compatibility(cp : Int) -> Array[Int] {
  // Full-width ASCII variants (U+FF01–U+FF5E → U+0021–U+007E): algorithmic.
  if cp >= 0xFF01 && cp <= 0xFF5E {
    return [cp - 0xFEE0]
  }
  // Full-width space.
  if cp == 0x3000 {
    return [0x0020]
  }
  let result : Array[Int] = []
  match cp {
    // Superscript/subscript digits
    0x00B2 => result.push(0x0032) // ² → 2
    0x00B3 => result.push(0x0033) // ³ → 3
    0x00B9 => result.push(0x0031) // ¹ → 1
    0x2070 => result.push(0x0030) // ⁰ → 0
    0x2074 => result.push(0x0034) // ⁴ → 4
    0x2075 => result.push(0x0035)
    0x2076 => result.push(0x0036)
    0x2077 => result.push(0x0037)
    0x2078 => result.push(0x0038)
    0x2079 => result.push(0x0039)
    0x2080 => result.push(0x0030) // ₀ → 0
    0x2081 => result.push(0x0031)
    0x2082 => result.push(0x0032)
    0x2083 => result.push(0x0033)
    0x2084 => result.push(0x0034)
    0x2085 => result.push(0x0035)
    0x2086 => result.push(0x0036)
    0x2087 => result.push(0x0037)
    0x2088 => result.push(0x0038)
    0x2089 => result.push(0x0039)
    // Latin ligatures
    0xFB00 => { result.push(0x0066); result.push(0x0066) } // ﬀ → ff
    0xFB01 => { result.push(0x0066); result.push(0x0069) } // ﬁ → fi
    0xFB02 => { result.push(0x0066); result.push(0x006C) } // ﬂ → fl
    0xFB03 => { result.push(0x0066); result.push(0x0066); result.push(0x0069) } // ﬃ → ffi
    0xFB04 => { result.push(0x0066); result.push(0x0066); result.push(0x006C) } // ﬄ → ffl
    // CJK Compatibility Forms (U+FE30–U+FE4F)
    0xFE49 | 0xFE4A | 0xFE4B | 0xFE4C => result.push(0x203E) // ﹉﹊﹋﹌ → ‾
    0xFE4D | 0xFE4E | 0xFE4F => result.push(0x005F) // ﹍﹎﹏ → _
    0xFE33 | 0xFE34 => result.push(0x005F) // ﹳﹴ → _
    // Half-width Katakana (U+FF66–U+FF9C → full-width Katakana)
    0xFF66 => result.push(0x30F2) // ｦ → ヲ
    0xFF67 => result.push(0x30A1) // ｧ → ァ
    0xFF68 => result.push(0x30A3) // ｨ → ィ
    0xFF69 => result.push(0x30A5) // ｩ → ゥ
    0xFF6A => result.push(0x30A7) // ｪ → ェ
    0xFF6B => result.push(0x30A9) // ｫ → ォ
    0xFF6C => result.push(0x30E3) // ｬ → ャ
    0xFF6D => result.push(0x30E5) // ｭ → ュ
    0xFF6E => result.push(0x30E7) // ｮ → ョ
    0xFF6F => result.push(0x30C3) // ｯ → ッ
    0xFF70 => result.push(0x30FC) // ｰ → ー
    0xFF71 => result.push(0x30A2) // ｱ → ア
    0xFF72 => result.push(0x30A4) // ｲ → イ
    0xFF73 => result.push(0x30A6) // ｳ → ウ
    0xFF74 => result.push(0x30A8) // ｴ → エ
    0xFF75 => result.push(0x30AA) // ｵ → オ
    0xFF76 => result.push(0x30AB) // ｶ → カ
    0xFF77 => result.push(0x30AD) // ｷ → キ
    0xFF78 => result.push(0x30AF) // ｸ → ク
    0xFF79 => result.push(0x30B1) // ｹ → ケ
    0xFF7A => result.push(0x30B3) // ｺ → コ
    0xFF7B => result.push(0x30B5) // ｻ → サ
    0xFF7C => result.push(0x30B7) // ｼ → シ
    0xFF7D => result.push(0x30B9) // ｽ → ス
    0xFF7E => result.push(0x30BB) // ｾ → セ
    0xFF7F => result.push(0x30BD) // ｿ → ソ
    0xFF80 => result.push(0x30BF) // ﾀ → タ
    0xFF81 => result.push(0x30C1) // ﾁ → チ
    0xFF82 => result.push(0x30C4) // ﾂ → ツ
    0xFF83 => result.push(0x30C6) // ﾃ → テ
    0xFF84 => result.push(0x30C8) // ﾄ → ト
    0xFF85 => result.push(0x30CA) // ﾅ → ナ
    0xFF86 => result.push(0x30CB) // ﾆ → ニ
    0xFF87 => result.push(0x30CC) // ﾇ → ヌ
    0xFF88 => result.push(0x30CD) // ﾈ → ネ
    0xFF89 => result.push(0x30CE) // ﾉ → ノ
    0xFF8A => result.push(0x30CF) // ﾊ → ハ
    0xFF8B => result.push(0x30D2) // ﾋ → ヒ
    0xFF8C => result.push(0x30D5) // ﾌ → フ
    0xFF8D => result.push(0x30D8) // ﾍ → ヘ
    0xFF8E => result.push(0x30DB) // ﾎ → ホ
    0xFF8F => result.push(0x30DE) // ﾏ → マ
    0xFF90 => result.push(0x30DF) // ﾐ → ミ
    0xFF91 => result.push(0x30E0) // ﾑ → ム
    0xFF92 => result.push(0x30E1) // ﾒ → メ
    0xFF93 => result.push(0x30E2) // ﾓ → モ
    0xFF94 => result.push(0x30E4) // ﾔ → ヤ
    0xFF95 => result.push(0x30E6) // ﾕ → ユ
    0xFF96 => result.push(0x30E8) // ﾖ → ヨ
    0xFF97 => result.push(0x30E9) // ﾗ → ラ
    0xFF98 => result.push(0x30EA) // ﾘ → リ
    0xFF99 => result.push(0x30EB) // ﾙ → ル
    0xFF9A => result.push(0x30EC) // ﾚ → レ
    0xFF9B => result.push(0x30ED) // ﾛ → ロ
    0xFF9C => result.push(0x30EF) // ﾜ → ワ
    0xFF9D => result.push(0x30F3) // ﾝ → ン
    // Letterlike symbols
    0x2103 => { result.push(0x00B0); result.push(0x0043) } // ℃ → °C
    0x2122 => { result.push(0x0054); result.push(0x004D) } // ™ → TM
    0x2109 => { result.push(0x00B0); result.push(0x0046) } // ℉ → °F
    // No compatibility decomposition — fall back to canonical.
    _ => {
      let canon = decompose_canonical(cp)
      for i = 0; i < canon.length(); i = i + 1 {
        result.push(canon[i])
      }
    }
  }
  result
}

// ---------------------------------------------------------------------------
// Canonical Composition Table
// ---------------------------------------------------------------------------

///|
/// Compose a base character + combining mark into a precomposed form.
/// Returns `Some(composed)` if a composition exists, `None` otherwise.
///
/// Covers: Latin-1 Supplement, Latin Extended-A, Greek, and Hangul (L+V, LV+T).
fn compose(base : Int, combining : Int) -> Int? {
  // Try Hangul composition first (algorithmic).
  match compose_hangul(base, combining) {
    Some(result) => return Some(result)
    None => ()
  }
  match (base, combining) {
    // === Latin-1 Supplement ===
    (0x0041, 0x0300) => Some(0x00C0)
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
    // === Latin Extended-A ===
    (0x0041, 0x0304) => Some(0x0100)
    (0x0061, 0x0304) => Some(0x0101)
    (0x0041, 0x0306) => Some(0x0102)
    (0x0061, 0x0306) => Some(0x0103)
    (0x0041, 0x0328) => Some(0x0104)
    (0x0061, 0x0328) => Some(0x0105)
    (0x0043, 0x0301) => Some(0x0106)
    (0x0063, 0x0301) => Some(0x0107)
    (0x0043, 0x0302) => Some(0x0108)
    (0x0063, 0x0302) => Some(0x0109)
    (0x0043, 0x0307) => Some(0x010A)
    (0x0063, 0x0307) => Some(0x010B)
    (0x0043, 0x030C) => Some(0x010C)
    (0x0063, 0x030C) => Some(0x010D)
    (0x0044, 0x030C) => Some(0x010E)
    (0x0064, 0x030C) => Some(0x010F)
    (0x0045, 0x0304) => Some(0x0112)
    (0x0065, 0x0304) => Some(0x0113)
    (0x0045, 0x0306) => Some(0x0114)
    (0x0065, 0x0306) => Some(0x0115)
    (0x0045, 0x0307) => Some(0x0116)
    (0x0065, 0x0307) => Some(0x0117)
    (0x0045, 0x0328) => Some(0x0118)
    (0x0065, 0x0328) => Some(0x0119)
    (0x0045, 0x030C) => Some(0x011A)
    (0x0065, 0x030C) => Some(0x011B)
    (0x0047, 0x0302) => Some(0x011C)
    (0x0067, 0x0302) => Some(0x011D)
    (0x0047, 0x0306) => Some(0x011E)
    (0x0067, 0x0306) => Some(0x011F)
    (0x0047, 0x0307) => Some(0x0120)
    (0x0067, 0x0307) => Some(0x0121)
    (0x0047, 0x0327) => Some(0x0122)
    (0x0067, 0x0327) => Some(0x0123)
    (0x0048, 0x0302) => Some(0x0124)
    (0x0068, 0x0302) => Some(0x0125)
    (0x0049, 0x0303) => Some(0x0128)
    (0x0069, 0x0303) => Some(0x0129)
    (0x0049, 0x0304) => Some(0x012A)
    (0x0069, 0x0304) => Some(0x012B)
    (0x0049, 0x0306) => Some(0x012C)
    (0x0069, 0x0306) => Some(0x012D)
    (0x0049, 0x0328) => Some(0x012E)
    (0x0069, 0x0328) => Some(0x012F)
    (0x0049, 0x0307) => Some(0x0130)
    (0x004A, 0x0302) => Some(0x0134)
    (0x006A, 0x0302) => Some(0x0135)
    (0x004B, 0x0327) => Some(0x0136)
    (0x006B, 0x0327) => Some(0x0137)
    (0x004C, 0x0301) => Some(0x0139)
    (0x006C, 0x0301) => Some(0x013A)
    (0x004C, 0x0327) => Some(0x013B)
    (0x006C, 0x0327) => Some(0x013C)
    (0x004C, 0x030C) => Some(0x013D)
    (0x006C, 0x030C) => Some(0x013E)
    (0x004E, 0x0301) => Some(0x0143)
    (0x006E, 0x0301) => Some(0x0144)
    (0x004E, 0x0327) => Some(0x0145)
    (0x006E, 0x0327) => Some(0x0146)
    (0x004E, 0x030C) => Some(0x0147)
    (0x006E, 0x030C) => Some(0x0148)
    (0x004F, 0x0304) => Some(0x014C)
    (0x006F, 0x0304) => Some(0x014D)
    (0x004F, 0x0306) => Some(0x014E)
    (0x006F, 0x0306) => Some(0x014F)
    (0x004F, 0x030B) => Some(0x0150)
    (0x006F, 0x030B) => Some(0x0151)
    (0x0052, 0x0301) => Some(0x0154)
    (0x0072, 0x0301) => Some(0x0155)
    (0x0052, 0x0327) => Some(0x0156)
    (0x0072, 0x0327) => Some(0x0157)
    (0x0052, 0x030C) => Some(0x0158)
    (0x0072, 0x030C) => Some(0x0159)
    (0x0053, 0x0301) => Some(0x015A)
    (0x0073, 0x0301) => Some(0x015B)
    (0x0053, 0x0302) => Some(0x015C)
    (0x0073, 0x0302) => Some(0x015D)
    (0x0053, 0x0327) => Some(0x015E)
    (0x0073, 0x0327) => Some(0x015F)
    (0x0053, 0x030C) => Some(0x0160)
    (0x0073, 0x030C) => Some(0x0161)
    (0x0054, 0x0327) => Some(0x0162)
    (0x0074, 0x0327) => Some(0x0163)
    (0x0054, 0x030C) => Some(0x0164)
    (0x0074, 0x030C) => Some(0x0165)
    (0x0055, 0x0303) => Some(0x0168)
    (0x0075, 0x0303) => Some(0x0169)
    (0x0055, 0x0304) => Some(0x016A)
    (0x0075, 0x0304) => Some(0x016B)
    (0x0055, 0x0306) => Some(0x016C)
    (0x0075, 0x0306) => Some(0x016D)
    (0x0055, 0x030A) => Some(0x016E)
    (0x0075, 0x030A) => Some(0x016F)
    (0x0055, 0x030B) => Some(0x0170)
    (0x0075, 0x030B) => Some(0x0171)
    (0x0055, 0x0328) => Some(0x0172)
    (0x0075, 0x0328) => Some(0x0173)
    (0x0057, 0x0302) => Some(0x0174)
    (0x0077, 0x0302) => Some(0x0175)
    (0x0059, 0x0302) => Some(0x0176)
    (0x0079, 0x0302) => Some(0x0177)
    (0x0059, 0x0308) => Some(0x0178)
    (0x005A, 0x0301) => Some(0x0179)
    (0x007A, 0x0301) => Some(0x017A)
    (0x005A, 0x0307) => Some(0x017B)
    (0x007A, 0x0307) => Some(0x017C)
    (0x005A, 0x030C) => Some(0x017D)
    (0x007A, 0x030C) => Some(0x017E)
    // === Greek and Coptic ===
    (0x0391, 0x0301) => Some(0x0386)
    (0x0395, 0x0301) => Some(0x0388)
    (0x0397, 0x0301) => Some(0x0389)
    (0x0399, 0x0301) => Some(0x038A)
    (0x039F, 0x0301) => Some(0x038C)
    (0x03A5, 0x0301) => Some(0x038E)
    (0x03A9, 0x0301) => Some(0x038F)
    (0x0399, 0x0308) => Some(0x03AA)
    (0x03A5, 0x0308) => Some(0x03AB)
    (0x03B1, 0x0301) => Some(0x03AC)
    (0x03B5, 0x0301) => Some(0x03AD)
    (0x03B7, 0x0301) => Some(0x03AE)
    (0x03B9, 0x0301) => Some(0x03AF)
    (0x03B9, 0x0308) => Some(0x03CA)
    (0x03C5, 0x0308) => Some(0x03CB)
    (0x03BF, 0x0301) => Some(0x03CC)
    (0x03C5, 0x0301) => Some(0x03CD)
    (0x03C9, 0x0301) => Some(0x03CE)
    _ => None
  }
}

// ---------------------------------------------------------------------------
// String / Codepoint Conversion
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Normalization: Internal Helpers
// ---------------------------------------------------------------------------

///|
/// Recursively decompose all codepoints in the input, then apply canonical
/// ordering. Used by both NFD and NFKD (the latter passes
/// `decompose_compatibility` instead of `decompose_canonical`).
fn decompose_all(
  input : Array[Int],
  decompose_fn : (Int) -> Array[Int],
) -> Array[Int] {
  // Recursively decompose until no further decomposition is possible.
  // Iterative fixed-point: keep decomposing until the sequence stabilises.
  let mut current = input
  let mut changed = true
  while changed {
    changed = false
    let next : Array[Int] = []
    for i = 0; i < current.length(); i = i + 1 {
      let decomposed = decompose_fn(current[i])
      // Check if decomposition actually changed anything.
      if decomposed.length() > 1 {
        changed = true
      }
      for j = 0; j < decomposed.length(); j = j + 1 {
        next.push(decomposed[j])
      }
    }
    current = next
  }
  // Apply canonical ordering to sort combining marks by CCC.
  canonical_ordering(current)
}

// ---------------------------------------------------------------------------
// Normalization: Public API
// ---------------------------------------------------------------------------

///|
/// NFD (Canonical Decomposition + Canonical Ordering).
pub fn nfd(s : String) -> String {
  let input = string_to_codepoints(s)
  let decomposed = decompose_all(input, decompose_canonical)
  codepoints_to_string(decomposed)
}

///|
/// NFC (Canonical Decomposition + Canonical Ordering + Canonical Composition).
pub fn nfc(s : String) -> String {
  let input = string_to_codepoints(s)
  let decomposed = decompose_all(input, decompose_canonical)
  // Canonical composition per Unicode Standard §3.11 D117.
  let output : Array[Int] = []
  if decomposed.length() == 0 {
    return ""
  }
  let mut last = decomposed[0] // Always a starter after NFD.
  output.push(last)
  let mut last_ccc = 0 // CCC of the last non-starter appended (0 if starter).
  for i = 1; i < decomposed.length(); i = i + 1 {
    let cp = decomposed[i]
    let cp_ccc = ccc(cp)
    if cp_ccc > 0 {
      // Non-starter: try composition if not blocked.
      // Blocked = there was a non-starter between last and cp with a
      // different (higher) CCC.
      if last_ccc == 0 || last_ccc < cp_ccc {
        match compose(last, cp) {
          Some(composed) => {
            // Replace last in output with composed value.
            output[output.length() - 1] = composed
            last = composed
            // last_ccc stays 0 — composed result is a starter.
            continue
          }
          None => ()
        }
      }
      output.push(cp)
      last_ccc = cp_ccc
    } else {
      // Starter: try composition with the previous starter.
      match compose(last, cp) {
        Some(composed) => {
          output[output.length() - 1] = composed
          last = composed
        }
        None => {
          output.push(cp)
          last = cp
        }
      }
      last_ccc = 0
    }
  }
  codepoints_to_string(output)
}

///|
/// NFKD (Compatibility Decomposition + Canonical Ordering).
pub fn nfkd(s : String) -> String {
  let input = string_to_codepoints(s)
  let decomposed = decompose_all(input, decompose_compatibility)
  codepoints_to_string(decomposed)
}

///|
/// NFKC (Compatibility Decomposition + Canonical Ordering + Canonical Composition).
pub fn nfkc(s : String) -> String {
  let input = string_to_codepoints(s)
  let decomposed = decompose_all(input, decompose_compatibility)
  // Canonical composition (same logic as NFC).
  let output : Array[Int] = []
  if decomposed.length() == 0 {
    return ""
  }
  let mut last = decomposed[0]
  output.push(last)
  let mut last_ccc = 0
  for i = 1; i < decomposed.length(); i = i + 1 {
    let cp = decomposed[i]
    let cp_ccc = ccc(cp)
    if cp_ccc > 0 {
      if last_ccc == 0 || last_ccc < cp_ccc {
        match compose(last, cp) {
          Some(composed) => {
            output[output.length() - 1] = composed
            last = composed
            continue
          }
          None => ()
        }
      }
      output.push(cp)
      last_ccc = cp_ccc
    } else {
      match compose(last, cp) {
        Some(composed) => {
          output[output.length() - 1] = composed
          last = composed
        }
        None => {
          output.push(cp)
          last = cp
        }
      }
      last_ccc = 0
    }
  }
  codepoints_to_string(output)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "unicode_normalization: NFD decomposes precomposed" {
  let result = nfd("é")
  let cps = string_to_codepoints(result)
  assert_eq(cps.length(), 2)
  assert_eq(cps[0], 0x65)
  assert_eq(cps[1], 0x301)
}

///|
test "unicode_normalization: NFC composes decomposed" {
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

///|
test "unicode_normalization: Latin Extended-A NFD" {
  // š (U+0161) → s (U+0073) + caron (U+030C)
  let result = nfd("š")
  let cps = string_to_codepoints(result)
  assert_eq(cps.length(), 2)
  assert_eq(cps[0], 0x73)
  assert_eq(cps[1], 0x30C)
}

///|
test "unicode_normalization: Latin Extended-A NFC roundtrip" {
  let original = "čokoláda"
  let decomposed = nfd(original)
  let recomposed = nfc(decomposed)
  assert_eq(recomposed, original)
}

///|
test "unicode_normalization: Greek NFD" {
  // ά (U+03AC) → α (U+03B1) + acute (U+0301)
  let result = nfd("ά")
  let cps = string_to_codepoints(result)
  assert_eq(cps.length(), 2)
  assert_eq(cps[0], 0x3B1)
  assert_eq(cps[1], 0x301)
}

///|
test "unicode_normalization: Greek NFC roundtrip" {
  let original = "Ελληνικά"
  let decomposed = nfd(original)
  let recomposed = nfc(decomposed)
  assert_eq(recomposed, original)
}

///|
test "unicode_normalization: Greek multi-mark NFD" {
  // ΐ (U+0390) → ι (U+03B9) + diaeresis (U+0308) + acute (U+0301)
  let result = nfd("ΐ")
  let cps = string_to_codepoints(result)
  assert_eq(cps.length(), 3)
  assert_eq(cps[0], 0x3B9)
  assert_eq(cps[1], 0x308)
  assert_eq(cps[2], 0x301)
}

///|
test "unicode_normalization: Hangul decomposition" {
  // 한 (U+D55C) → ᄒ (U+1112) + ᅡ (U+1161) + ᆫ (U+11AB)
  let result = nfd("한")
  let cps = string_to_codepoints(result)
  assert_eq(cps.length(), 3)
  assert_eq(cps[0], 0x1112)
  assert_eq(cps[1], 0x1161)
  assert_eq(cps[2], 0x11AB)
}

///|
test "unicode_normalization: Hangul composition" {
  // ᄒ + ᅡ + ᆫ → 한
  let decomposed = codepoints_to_string([0x1112, 0x1161, 0x11AB])
  let result = nfc(decomposed)
  let cps = string_to_codepoints(result)
  assert_eq(cps.length(), 1)
  assert_eq(cps[0], 0xD55C)
}

///|
test "unicode_normalization: Hangul NFC roundtrip" {
  let original = "안녕하세요"
  let decomposed = nfd(original)
  let recomposed = nfc(decomposed)
  assert_eq(recomposed, original)
}

///|
test "unicode_normalization: Hangul LV-only" {
  // 가 (U+AC00) = ᄀ (U+1100) + ᅡ (U+1161), no trailing consonant
  let result = nfd("가")
  let cps = string_to_codepoints(result)
  assert_eq(cps.length(), 2)
  assert_eq(cps[0], 0x1100)
  assert_eq(cps[1], 0x1161)
  // Roundtrip
  let recomposed = nfc(result)
  let rcps = string_to_codepoints(recomposed)
  assert_eq(rcps.length(), 1)
  assert_eq(rcps[0], 0xAC00)
}

///|
test "unicode_normalization: full-width ASCII NFKD" {
  // Ａ (U+FF21) → A (U+0041)
  let result = nfkd("Ａ")
  assert_eq(result, "A")
  // ０ (U+FF10) → 0 (U+0030)
  assert_eq(nfkd("０"), "0")
  // ！ (U+FF01) → ! (U+0021)
  assert_eq(nfkd("！"), "!")
}

///|
test "unicode_normalization: full-width space NFKD" {
  // U+3000 → U+0020
  let result = nfkd(codepoints_to_string([0x3000]))
  let cps = string_to_codepoints(result)
  assert_eq(cps.length(), 1)
  assert_eq(cps[0], 0x20)
}

///|
test "unicode_normalization: ligature NFKD" {
  // ﬁ (U+FB01) → fi
  let result = nfkd("ﬁ")
  assert_eq(result, "fi")
  // ﬂ (U+FB02) → fl
  assert_eq(nfkd("ﬂ"), "fl")
}

///|
test "unicode_normalization: superscript NFKD" {
  // ² (U+00B2) → 2
  assert_eq(nfkd("²"), "2")
  // ³ (U+00B3) → 3
  assert_eq(nfkd("³"), "3")
  // ¹ (U+00B9) → 1
  assert_eq(nfkd("¹"), "1")
}

///|
test "unicode_normalization: half-width Katakana NFKD" {
  // ｱ (U+FF71) → ア (U+30A2)
  let result = nfkd("ｱ")
  let cps = string_to_codepoints(result)
  assert_eq(cps.length(), 1)
  assert_eq(cps[0], 0x30A2)
}

///|
test "unicode_normalization: NFKC composes after compatibility decomposition" {
  // full-width é (U+FF25 is E, not é — use full-width Ｅ + combining)
  // Instead test: ﬁ → fi (no composition needed, just decomposition)
  assert_eq(nfkc("ﬁ"), "fi")
  // full-width Ａ → A
  assert_eq(nfkc("Ａ"), "A")
}

///|
test "unicode_normalization: canonical ordering sorts combining marks" {
  // e + acute (CCC=230) + cedilla (CCC=216)
  // After ordering: e + cedilla (CCC=216) + acute (CCC=230)
  // Then compose: e + cedilla → ȩ, then ȩ + acute → no composition
  let input = codepoints_to_string([0x65, 0x301, 0x327])
  let result = nfd(input)
  let cps = string_to_codepoints(result)
  // After canonical ordering: e (0x65) + cedilla (0x327, CCC=216) + acute (0x301, CCC=230)
  assert_eq(cps.length(), 3)
  assert_eq(cps[0], 0x65)
  assert_eq(cps[1], 0x327)
  assert_eq(cps[2], 0x301)
}

///|
test "unicode_normalization: NFD is idempotent" {
  let s = "café"
  let nfd1 = nfd(s)
  let nfd2 = nfd(nfd1)
  assert_eq(nfd1, nfd2)
}

///|
test "unicode_normalization: NFKD is idempotent" {
  let s = "Ａﬁ"
  let nfkd1 = nfkd(s)
  let nfkd2 = nfkd(nfkd1)
  assert_eq(nfkd1, nfkd2)
}

///|
test "unicode_normalization: empty string" {
  assert_eq(nfd(""), "")
  assert_eq(nfc(""), "")
  assert_eq(nfkd(""), "")
  assert_eq(nfkc(""), "")
}

///|
test "unicode_normalization: TM symbol NFKD" {
  // ™ (U+2122) → TM
  assert_eq(nfkd("™"), "TM")
}

///|
test "unicode_normalization: degree Celsius NFKD" {
  // ℃ (U+2103) → °C
  let result = nfkd("℃")
  let cps = string_to_codepoints(result)
  assert_eq(cps.length(), 2)
  assert_eq(cps[0], 0xB0)
  assert_eq(cps[1], 0x43)
}

///|
test "unicode_normalization: CJK compatibility forms NFKD" {
  // ﹉ (U+FE49) → ‾ (U+203E)
  let result = nfkd(codepoints_to_string([0xFE49]))
  let cps = string_to_codepoints(result)
  assert_eq(cps.length(), 1)
  assert_eq(cps[0], 0x203E)
  // ﹍ (U+FE4D) → _ (U+005F)
  let result2 = nfkd(codepoints_to_string([0xFE4D]))
  let cps2 = string_to_codepoints(result2)
  assert_eq(cps2.length(), 1)
  assert_eq(cps2[0], 0x5F)
}

///|
test "unicode_normalization: mixed scripts NFC" {
  // Mix Latin, Greek, and Hangul in one string
  let original = "café Έλληνικά 안녕"
  let decomposed = nfd(original)
  let recomposed = nfc(decomposed)
  assert_eq(recomposed, original)
}
