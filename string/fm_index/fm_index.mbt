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
/// ## Complexity
///
/// - Build: O(n² log n) for suffix array + O(n) for BWT.
/// - Search: O(m) per pattern of length m.
/// - Space: O(n * |Σ|) for the Occ array.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

pub struct FMIndex {
  priv c_table : Map[Int, Int] // C[c] = count of chars < c
  priv occ : FixedArray[FixedArray[Int]] // Occ[c][i] = occurrences of c in BWT[0..i)
  priv char_index : Map[Int, Int] // char → index in alphabet
  priv n : Int // text length (including sentinel)
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
  // Build Occ array: occ[ci][i] = occurrences of alphabet[ci] in BWT[0..i).
  let sigma = alphabet.length()
  let occ = FixedArray::make(sigma, FixedArray::make(0, 0))
  for ci = 0; ci < sigma; ci = ci + 1 {
    occ[ci] = FixedArray::make(n + 2, 0)
  }
  for i = 0; i <= n; i = i + 1 {
    // Copy previous counts.
    for ci = 0; ci < sigma; ci = ci + 1 {
      occ[ci][i + 1] = occ[ci][i]
    }
    // Increment count for the character at position i.
    let ch = bwt_codes[i]
    match char_index.get(ch) {
      Some(idx) => occ[idx][i + 1] = occ[idx][i + 1] + 1
      None => ()
    }
  }
  { c_table, occ, char_index, n: n + 1 }
}

///|
/// Build suffix array with implicit sentinel at position n.
fn build_suffix_array_with_sentinel(text : String, n : Int) -> FixedArray[Int] {
  let sa = FixedArray::make(n + 1, 0)
  for i = 0; i <= n; i = i + 1 {
    sa[i] = i
  }
  // Sort suffixes. The sentinel (position n) is always the smallest.
  sa.sort_by(fn(a, b) {
    if a == b {
      return 0
    }
    let mut i = 0
    while true {
      let ca = if a + i < n {
        text[a + i].to_int()
      } else if a + i == n {
        -1
      } else {
        999999
      }
      let cb = if b + i < n {
        text[b + i].to_int()
      } else if b + i == n {
        -1
      } else {
        999999
      }
      if ca == cb {
        i = i + 1
      } else {
        return ca - cb
      }
    }
    0
  })
  sa
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
            lo = cv + index.occ[ci][lo]
            hi = cv + index.occ[ci][hi]
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
