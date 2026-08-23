///|
/// FM-Index (Full-text index in Minute space).
///
/// The FM-Index is a compressed full-text substring index that supports
/// pattern search in O(m) time with O(n) space. It is the core data
/// structure behind bowtie, BWA, and other bioinformatics aligners.
///
/// ## Algorithm
///
/// Built on the **Burrows-Wheeler Transform (BWT)** of the text. The BWT
/// is self-indexing: you can search for patterns using only the BWT and
/// a small auxiliary structure (C table and Occ array).
///
/// The suffix array is constructed in O(n) using **SA-IS** (Nong, Zhang,
/// Chan 2009), imported from the `@sa_is` package.
///
/// ## Space efficiency
///
/// Uses **sampled Occ arrays**: instead of storing Occ[c][i] for every
/// position i (O(n·|Σ|) space), we store samples every `SAMPLE_RATE`
/// positions and keep the BWT for interpolation. This reduces space to
/// O(n·|Σ|/k + n) while increasing query time to O(m·k) — still O(m)
/// for constant k.
///
/// For σ=256 (ASCII) and k=32: space drops from 256n to ~9n (28× savings).
/// For σ=4 (DNA) and k=32: space drops from 4n to ~1.1n (3.6× savings).
///
/// ## Complexity
///
/// - Build: O(n) via SA-IS suffix array + O(n) for BWT and sampled Occ.
/// - Search: O(m · k) per pattern of length m, where k = SAMPLE_RATE.
/// - Space: O(n · |Σ| / k + n) for sampled Occ + BWT.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

///|
/// Occ array sampling rate. Every k-th position stores a full Occ snapshot;
/// intermediate positions are reconstructed by scanning the BWT.
const SAMPLE_RATE : Int = 32

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

///|
pub struct FMIndex {
  priv c_table : Map[Int, Int] // C[c] = count of chars < c
  priv occ_samples : FixedArray[FixedArray[Int]] // Sampled Occ: occ[ci][sample_idx]
  priv bwt : FixedArray[Int] // BWT character codes (for interpolation)
  priv alphabet : FixedArray[Int] // alphabet[ci] = char code for index ci
  priv char_index : Map[Int, Int] // char → index in alphabet
  priv n : Int // text length (including sentinel)
}

///|
/// Compute Occ(ci, pos) = occurrences of alphabet[ci] in BWT[0..pos).
///
/// Uses the sampled Occ array: find the nearest sample at or before
/// position pos, then scan the BWT forward to adjust the count.
/// Time: O(SAMPLE_RATE) per call.
fn occ(index : FMIndex, ci : Int, pos : Int) -> Int {
  let sample_idx = pos / SAMPLE_RATE
  let mut count = index.occ_samples[ci][sample_idx]
  let start = sample_idx * SAMPLE_RATE
  let target = index.alphabet[ci]
  for j = start; j < pos; j = j + 1 {
    if index.bwt[j] == target {
      count = count + 1
    }
  }
  count
}

///|
/// Build an FM-Index from a text string.
pub fn build(text : String) -> FMIndex {
  let n = text.length()
  // Build suffix array of text + implicit sentinel at position n.
  let sa = build_suffix_array_with_sentinel(text, n)
  // Build BWT from suffix array: BWT[i] = text[SA[i] - 1], or sentinel.
  let bwt_codes = FixedArray::make(n + 1, 0)
  for i = 0; i <= n; i = i + 1 {
    let sa_val = sa[i]
    if sa_val == 0 {
      // Sentinel position: BWT char is the sentinel ($), represented as -1.
      // It is lexicographically smaller than all text characters and appears
      // exactly once in the BWT. Using -1 (not in char_index) ensures it is
      // skipped during Occ array construction, preserving correct counts.
      bwt_codes[i] = -1
    } else {
      bwt_codes[i] = text[sa_val - 1].to_int()
    }
  }
  // Build alphabet (sorted unique characters from the original text).
  let char_set : Map[Int, Unit] = Map([])
  for i = 0; i < n; i = i + 1 {
    char_set[text[i].to_int()] = ()
  }
  let alphabet : Array[Int] = []
  for c, _ in char_set {
    alphabet.push(c)
  }
  alphabet.sort_by(fn(a, b) { a - b })
  // Build character index.
  let char_index : Map[Int, Int] = Map([])
  for i = 0; i < alphabet.length(); i = i + 1 {
    char_index[alphabet[i]] = i
  }
  // Build C table: C[c] = number of characters in text that are < c.
  let counts = FixedArray::make(alphabet.length(), 0)
  for i = 0; i < n; i = i + 1 {
    match char_index.get(text[i].to_int()) {
      Some(ci) => counts[ci] = counts[ci] + 1
      None => ()
    }
  }
  let c_table : Map[Int, Int] = Map([])
  // Start at 1 to account for the sentinel ($), which is lexicographically
  // smallest and appears exactly once in the BWT. Every text character c
  // has C[c] = 1 + (count of chars < c in the text).
  let mut cum = 1
  for i = 0; i < alphabet.length(); i = i + 1 {
    c_table[alphabet[i]] = cum
    cum = cum + counts[i]
  }
  // Build sampled Occ array: occ_samples[ci][s] = Occ(ci, s * SAMPLE_RATE).
  // Instead of storing Occ for every position (O(n·σ) space), we store
  // snapshots every SAMPLE_RATE positions and scan the BWT for intermediate
  // values. This reduces space to O(n·σ/k + n) while keeping O(m·k) query.
  let sigma = alphabet.length()
  let bwt_len = n + 1 // BWT length including sentinel
  let num_samples = bwt_len / SAMPLE_RATE + 1
  let occ_samples = FixedArray::make(sigma, FixedArray::make(0, 0))
  for ci = 0; ci < sigma; ci = ci + 1 {
    occ_samples[ci] = FixedArray::make(num_samples, 0)
  }
  // occ_samples[ci][0] = 0 (zero-initialized, represents Occ(ci, 0)).
  // Scan BWT once, maintaining running counts. At each sample boundary
  // (every SAMPLE_RATE positions), snapshot the running counts.
  let running = FixedArray::make(sigma, 0)
  for i = 0; i < bwt_len; i = i + 1 {
    let ch = bwt_codes[i]
    match char_index.get(ch) {
      Some(idx) => running[idx] = running[idx] + 1
      None => ()
    }
    // After processing BWT[i], running[ci] = Occ(ci, i+1).
    // If (i+1) is a sample boundary, store the snapshot.
    let next = i + 1
    if next % SAMPLE_RATE == 0 {
      let s = next / SAMPLE_RATE
      for ci = 0; ci < sigma; ci = ci + 1 {
        occ_samples[ci][s] = running[ci]
      }
    }
  }
  // If bwt_len is not a multiple of SAMPLE_RATE, the last partial segment
  // relies on the nearest earlier sample + BWT scan in occ(). No extra
  // storage needed — occ() handles it transparently.
  // Convert alphabet Array to FixedArray for O(1) reverse lookup in occ().
  let alphabet_fa = FixedArray::make(sigma, 0)
  for i = 0; i < sigma; i = i + 1 {
    alphabet_fa[i] = alphabet[i]
  }
  {
    c_table,
    occ_samples,
    bwt: bwt_codes,
    alphabet: alphabet_fa,
    char_index,
    n: bwt_len,
  }
}

///|
/// Build suffix array with implicit sentinel at position n.
/// Uses SA-IS for O(n) construction.
fn build_suffix_array_with_sentinel(text : String, n : Int) -> FixedArray[Int] {
  // Build integer array: text chars + 1 (so sentinel 0 is smallest).
  let s : Array[Int] = []
  for i = 0; i < n; i = i + 1 {
    s.push(text[i].to_int() + 1)
  }
  s.push(0) // sentinel
  // SA-IS returns the full suffix array including the sentinel position.
  let full_sa = @sa_is.sa_is(s)
  // Convert to FixedArray.
  FixedArray::makei(full_sa.length(), fn(i) { full_sa[i] })
}

///|
/// Count the number of occurrences of a pattern in the text.
///
/// Uses the backward search algorithm: O(m) time where m = pattern length.
pub fn count(index : FMIndex, pattern : String) -> Int {
  let m = pattern.length()
  if m == 0 {
    return index.n - 1
  }
  let mut lo = 0
  let mut hi = index.n
  let mut i = m - 1
  while i >= 0 && lo < hi {
    let ch = pattern[i].to_int()
    match index.char_index.get(ch) {
      None => return 0
      Some(ci) =>
        match index.c_table.get(ch) {
          None => return 0
          Some(cv) => {
            lo = cv + occ(index, ci, lo)
            hi = cv + occ(index, ci, hi)
          }
        }
    }
    i = i - 1
  }
  if lo < hi {
    hi - lo
  } else {
    0
  }
}

///|
/// Check if a pattern exists in the text.
pub fn contains(index : FMIndex, pattern : String) -> Bool {
  count(index, pattern) > 0
}

///|
/// The length of the indexed text (excluding sentinel).
pub fn text_length(index : FMIndex) -> Int {
  index.n - 1
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "fm_index: count single occurrence" {
  let idx = build("banana")
  assert_eq(count(idx, "ana"), 2)
  assert_eq(count(idx, "ban"), 1)
  assert_eq(count(idx, "banana"), 1)
}

///|
test "fm_index: count no occurrence" {
  let idx = build("banana")
  assert_eq(count(idx, "xyz"), 0)
  assert_eq(count(idx, "bananaX"), 0)
}

///|
test "fm_index: contains" {
  let idx = build("mississippi")
  assert_true(contains(idx, "issi"))
  assert_true(contains(idx, "miss"))
  assert_true(contains(idx, "ppi"))
  assert_false(contains(idx, "abc"))
}

///|
test "fm_index: empty pattern" {
  let idx = build("hello")
  assert_eq(count(idx, ""), 5)
}

///|
test "fm_index: single character" {
  let idx = build("abracadabra")
  assert_eq(count(idx, "a"), 5)
  assert_eq(count(idx, "b"), 2)
  assert_eq(count(idx, "c"), 1)
  assert_eq(count(idx, "d"), 1)
  assert_eq(count(idx, "z"), 0)
}

///|
test "fm_index: repeated pattern" {
  let idx = build("aaaa")
  assert_eq(count(idx, "a"), 4)
  assert_eq(count(idx, "aa"), 3)
  assert_eq(count(idx, "aaa"), 2)
  assert_eq(count(idx, "aaaa"), 1)
  assert_eq(count(idx, "aaaaa"), 0)
}

///|
test "fm_index: text length" {
  let idx = build("banana")
  assert_eq(text_length(idx), 6)
}

///|
test "fm_index: long text crossing sample boundary" {
  // Text length 60 > SAMPLE_RATE (32), exercises one sample boundary.
  let mut text = ""
  for i = 0; i < 20; i = i + 1 {
    text = text + "abc"
  }
  let idx = build(text)
  assert_eq(count(idx, "abc"), 20)
  assert_eq(count(idx, "bca"), 19)
  assert_eq(count(idx, "cab"), 19)
  assert_eq(count(idx, "abcabc"), 19)
  assert_true(contains(idx, "abcabc"))
  assert_false(contains(idx, "xyz"))
}

///|
test "fm_index: long text crossing multiple sample boundaries" {
  // Text length 90 > 2 * SAMPLE_RATE (64), exercises multiple boundaries.
  let mut text = ""
  for i = 0; i < 30; i = i + 1 {
    text = text + "abc"
  }
  let idx = build(text)
  assert_eq(count(idx, "abc"), 30)
  assert_eq(count(idx, "bca"), 29)
  assert_eq(count(idx, "cab"), 29)
  assert_eq(text_length(idx), 90)
}

///|
test "fm_index: large alphabet long text" {
  // 26 distinct characters, text length 78 > 2 * SAMPLE_RATE.
  let mut text = ""
  for i = 0; i < 3; i = i + 1 {
    text = text + "abcdefghijklmnopqrstuvwxyz"
  }
  let idx = build(text)
  assert_eq(count(idx, "a"), 3)
  assert_eq(count(idx, "z"), 3)
  assert_eq(count(idx, "abc"), 3)
  assert_eq(count(idx, "xyz"), 3)
  assert_eq(count(idx, "abcdefghijklmnopqrstuvwxyz"), 3)
  assert_eq(count(idx, "zabc"), 2)
}
