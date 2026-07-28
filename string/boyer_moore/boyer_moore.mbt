/// Boyer-Moore string search algorithm.
///
/// The Boyer-Moore algorithm searches for a pattern in a text using two
/// heuristics to skip sections of the text that cannot match:
///
/// 1. **Bad character rule**: When a mismatch occurs at position `j` in the
///    pattern, shift the pattern so that the mismatched text character aligns
///    with the rightmost occurrence of that character in the pattern (or shift
///    past it if the character is absent).
///
/// 2. **Good suffix rule**: When a suffix of the pattern has been matched
///    before a mismatch, shift the pattern so that another occurrence of that
///    suffix aligns with the text (or shift past if no such occurrence exists).
///
/// The shift is the maximum of the two heuristics, which is always at least 1.
/// For typical text, Boyer-Moore is sublinear (examines fewer than `n`
/// characters) because large shifts skip over unexamined portions.
///
/// ## Complexity
///
/// - **Preprocessing**: O(m + |Σ|) for the bad-character table,
///   O(m) for the good-suffix table.
/// - **Search**: O(n/m) best case (sublinear), O(n*m) worst case
///   (but O(n) with the good-suffix rule; O(n/m) average for typical text).
///
/// ## API
///
/// - `search(text, pattern)` — returns the index of the first occurrence of
///   `pattern` in `text`, or `None` if not found.
/// - `search_all(text, pattern)` — returns all occurrence indices.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Bad character table
// ---------------------------------------------------------------------------

///|
/// Build the bad-character shift table.
///
/// Returns a `Map[Int, Int]` mapping each character code point to its
/// rightmost index in the pattern. Characters absent from the pattern
/// are simply missing from the map (treated as -1 during lookup).
///
/// Uses a hash map instead of a fixed-size array to support **all Unicode
/// code points**, including CJK characters (e.g. '中' = U+4E2D = 20013)
/// and emoji, which would overflow a 256-element ASCII table.
fn build_bad_char(pattern : String) -> Map[Int, Int] {
  let table : Map[Int, Int] = Map([])
  for i = 0; i < pattern.length(); i = i + 1 {
    table[pattern[i].to_int()] = i
  }
  table
}

// ---------------------------------------------------------------------------
// Good suffix table
// ---------------------------------------------------------------------------

///|
/// Build the good-suffix shift table.
///
/// `good_suffix[j]` = the minimum shift such that the matched suffix
/// (pattern[j+1..m-1]) aligns with another occurrence in the pattern,
/// or the longest prefix of the pattern that matches a suffix of the pattern.
fn build_good_suffix(pattern : String) -> FixedArray[Int] {
  let m = pattern.length()
  let table = FixedArray::make(m + 1, m)
  if m == 0 {
    return table
  }
  // `suffix[i]` = length of the longest suffix of pattern that matches
  // a suffix of pattern ending at position i.
  let suffix = FixedArray::make(m, 0)
  suffix[m - 1] = m
  // Compute suffix array using a modified Z-like approach.
  let mut g = m - 1
  let mut f = 0
  let mut i = m - 2
  while i >= 0 {
    if i > g && suffix[i + m - 1 - f] < i - g {
      suffix[i] = suffix[i + m - 1 - f]
    } else {
      if i < g {
        g = i
      }
      f = i
      while g >= 0 && pattern[g] == pattern[g + m - 1 - f] {
        g = g - 1
      }
      suffix[i] = f - g
    }
    i = i - 1
  }
  // Case 1: another occurrence of the suffix exists in the pattern.
  let mut j = 0
  for i = m - 1; i >= 0; i = i - 1 {
    if suffix[i] == i + 1 {
      while j < m - 1 - i {
        if table[j] == m {
          table[j] = m - 1 - i
        }
        j = j + 1
      }
    }
  }
  // Case 2: only a prefix matches a suffix.
  for i = 0; i < m - 1; i = i + 1 {
    table[m - 1 - suffix[i]] = m - 1 - i
  }
  table
}

// ---------------------------------------------------------------------------
// Search
// ---------------------------------------------------------------------------

///|
/// Search for the first occurrence of `pattern` in `text`.
///
/// Returns `Some(index)` if found, `None` if not found or if `pattern` is
/// empty. The search uses both the bad-character and good-suffix heuristics.
pub fn search(text : String, pattern : String) -> Int? {
  if pattern.length() == 0 || pattern.length() > text.length() {
    return None
  }
  let bad_char = build_bad_char(pattern)
  let good_suffix = build_good_suffix(pattern)
  let m = pattern.length()
  let n = text.length()
  let mut s = 0 // shift of the pattern relative to text
  while s <= n - m {
    let mut j = m - 1
    // Compare from right to left.
    while j >= 0 && pattern[j] == text[s + j] {
      j = j - 1
    }
    if j < 0 {
      // Full match found.
      return Some(s)
    }
    // Compute shift from both heuristics and take the maximum.
    let bc_shift = j - bad_char.get(text[s + j].to_int()).unwrap_or(-1)
    let gs_shift = good_suffix[j]
    let shift = if bc_shift > gs_shift { bc_shift } else { gs_shift }
    s = s + (if shift < 1 { 1 } else { shift })
  }
  None
}

///|
/// Find all occurrences of `pattern` in `text`.
///
/// Returns an `Array[Int]` of starting indices, in ascending order, including
/// overlapping occurrences. Uses the same bad-character and good-suffix
/// tables as [`search`]; on a full match the pattern advances by
/// `good_suffix[0]` (the minimum shift consistent with the good-suffix rule),
/// which finds every overlapping occurrence while still skipping sections
/// that cannot match.
pub fn search_all(text : String, pattern : String) -> Array[Int] {
  let result : Array[Int] = []
  if pattern.length() == 0 || pattern.length() > text.length() {
    return result
  }
  let bad_char = build_bad_char(pattern)
  let good_suffix = build_good_suffix(pattern)
  let m = pattern.length()
  let n = text.length()
  let mut s = 0
  while s <= n - m {
    let mut j = m - 1
    while j >= 0 && pattern[j] == text[s + j] {
      j = j - 1
    }
    if j < 0 {
      result.push(s)
      // Shift by good_suffix[0] to reach the next position where the
      // pattern can match, catching overlapping occurrences.
      s = s + good_suffix[0]
    } else {
      let bc_shift = j - bad_char.get(text[s + j].to_int()).unwrap_or(-1)
      let gs_shift = good_suffix[j]
      let shift = if bc_shift > gs_shift { bc_shift } else { gs_shift }
      s = s + (if shift < 1 { 1 } else { shift })
    }
  }
  result
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "boyer_moore: basic match" {
  assert_eq(search("hello world", "world"), Some(6))
  assert_eq(search("hello world", "hello"), Some(0))
  assert_eq(search("ababcababc", "abc"), Some(2))
}

///|
test "boyer_moore: no match" {
  assert_true(search("hello world", "xyz") is None)
  assert_true(search("abc", "abcd") is None)
}

///|
test "boyer_moore: empty pattern" {
  assert_true(search("hello", "") is None)
}

///|
test "boyer_moore: full match" {
  assert_eq(search("abc", "abc"), Some(0))
}

///|
test "boyer_moore: repeated pattern" {
  assert_eq(search("aaaaaa", "aa"), Some(0))
  assert_eq(search("ababab", "ab"), Some(0))
}

///|
test "boyer_moore: single char" {
  assert_eq(search("hello", "e"), Some(1))
  assert_eq(search("hello", "o"), Some(4))
  assert_true(search("hello", "z") is None)
}

///|
test "boyer_moore: pattern at end" {
  assert_eq(search("abcdefghij", "hij"), Some(7))
  assert_eq(search("abcdefghij", "ij"), Some(8))
}

///|
test "boyer_moore: search_all" {
  let positions = search_all("ababcababc", "ab")
  assert_eq(positions.length(), 4)
  assert_eq(positions[0], 0)
  assert_eq(positions[1], 2)
  assert_eq(positions[2], 5)
  assert_eq(positions[3], 7)
}

///|
test "boyer_moore: search_all overlapping" {
  let positions = search_all("aaaaaa", "aa")
  assert_eq(positions.length(), 5)
  for i = 0; i < 5; i = i + 1 {
    assert_eq(positions[i], i)
  }
}

///|
test "boyer_moore: search_all no match" {
  let positions = search_all("hello world", "xyz")
  assert_eq(positions.length(), 0)
}

///|
test "boyer_moore: search_all single occurrence" {
  let positions = search_all("abcdef", "def")
  assert_eq(positions.length(), 1)
  assert_eq(positions[0], 3)
}

///|
test "boyer_moore: large text" {
  // Build a large text with known pattern.
  let text_buf : Array[Char] = []
  for i = 0; i < 1000; i = i + 1 {
    text_buf.push((i % 26 + 97).to_char().unwrap())
  }
  // The base text is periodic with period 26, so a slice taken at position 500
  // (500 mod 26 == 6) would also match at position 6. Overwrite positions
  // 500..509 with uppercase 'A'..'J' (absent from the lowercase base text) so
  // the pattern occurs only at position 500.
  for k = 0; k < 10; k = k + 1 {
    text_buf[500 + k] = (65 + k).to_char().unwrap()
  }
  let text = String::from_array(text_buf.view())
  // Search for a substring at position 500.
  let pat = text[500:510].to_owned()
  assert_eq(search(text, pat), Some(500))
}

///|
test "boyer_moore: pattern longer than text" {
  assert_true(search("ab", "abc") is None)
}

///|
test "boyer_moore: matches KMP semantics" {
  // Cross-check with brute force on various inputs.
  let texts = ["ababcababc", "mississippi", "aaaaaaaab", "xyzxyzxyz"]
  let patterns = ["ab", "ss", "aaa", "xyz", "z", "abc", "aaaa"]
  for t_idx = 0; t_idx < texts.length(); t_idx = t_idx + 1 {
    let text = texts[t_idx]
    for p_idx = 0; p_idx < patterns.length(); p_idx = p_idx + 1 {
      let pat = patterns[p_idx]
      // Brute force.
      let bf = brute_search(text, pat)
      assert_eq(search(text, pat), bf)
    }
  }
}

///|
fn brute_search(text : String, pattern : String) -> Int? {
  if pattern.length() == 0 || pattern.length() > text.length() {
    return None
  }
  let n = text.length()
  let m = pattern.length()
  for i = 0; i + m <= n; i = i + 1 {
    let mut match_ok = true
    for j = 0; j < m; j = j + 1 {
      if text[i + j] != pattern[j] {
        match_ok = false
        break
      }
    }
    if match_ok {
      return Some(i)
    }
  }
  None
}

///|
/// Brute-force `search_all` oracle: scans every start position and collects
/// all (overlapping) matches. Used to cross-check the Boyer-Moore
/// `search_all` shift logic, which must not skip overlapping occurrences.
fn brute_search_all(text : String, pattern : String) -> Array[Int] {
  let result : Array[Int] = []
  if pattern.length() == 0 || pattern.length() > text.length() {
    return result
  }
  let n = text.length()
  let m = pattern.length()
  for i = 0; i + m <= n; i = i + 1 {
    let mut match_ok = true
    for j = 0; j < m; j = j + 1 {
      if text[i + j] != pattern[j] {
        match_ok = false
        break
      }
    }
    if match_ok {
      result.push(i)
    }
  }
  result
}

///|
test "boyer_moore: search_all matches brute force" {
  // Cross-check the overlapping-match shift logic against brute force.
  let texts = ["ababcababc", "mississippi", "aaaaaaaab", "xyzxyzxyz", "ababa", "aabaaabaa"]
  let patterns = ["ab", "ss", "aaa", "xyz", "z", "abc", "aaaa", "aba", "aa"]
  for t_idx = 0; t_idx < texts.length(); t_idx = t_idx + 1 {
    let text = texts[t_idx]
    for p_idx = 0; p_idx < patterns.length(); p_idx = p_idx + 1 {
      let pat = patterns[p_idx]
      let bf = brute_search_all(text, pat)
      let bm = search_all(text, pat)
      assert_eq(bm.length(), bf.length())
      for i = 0; i < bf.length(); i = i + 1 {
        assert_eq(bm[i], bf[i])
      }
    }
  }
}
