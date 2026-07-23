/// KMP string matching algorithm.
/// Implements the Knuth-Morris-Pratt algorithm for efficient
/// pattern matching with O(n+m) time complexity.
///
/// IMPORTANT: MoonBit's String indexing is byte-level, not Unicode codepoint.
/// For multi-byte UTF-8 strings (e.g., Chinese, emoji), matching operates on
/// raw bytes and may match in the middle of a multi-byte character. This is
/// correct for ASCII-only inputs. For Unicode-aware matching, convert to
/// FixedArray[Int] of codepoints first.
///
/// Not formally verified (String operations not supported by moon prove).
/// Correctness ensured by comprehensive tests.

/// Build the Longest Proper Prefix which is also Suffix (LPS) array.
/// lps[i] = length of the longest proper prefix of pattern[0..i]
/// which is also a suffix of pattern[0..i].
pub fn build_lps(pattern : String) -> FixedArray[Int] {
  let m = pattern.length()
  let lps = FixedArray::make(m, 0)
  if m == 0 {
    return lps
  }
  lps[0] = 0
  let mut len = 0
  let mut i = 1
  while i < m {
    if pattern[i] == pattern[len] {
      len = len + 1
      lps[i] = len
      i = i + 1
    } else if len != 0 {
      len = lps[len - 1]
    } else {
      lps[i] = 0
      i = i + 1
    }
  }
  lps
}

/// Advance KMP state by one step.
/// Returns (new_i, new_j, match_position) where match_position is
/// Some(pos) if a match was found at position pos, None otherwise.
fn kmp_step(
  text : String,
  pattern : String,
  lps : FixedArray[Int],
  i : Int,
  j : Int,
  m : Int,
  n : Int,
) -> (Int, Int, Int?) {
  let mut ci = i
  let mut cj = j
  let mut match_pos : Int? = None
  if ci < n && text[ci] == pattern[cj] {
    ci = ci + 1
    cj = cj + 1
  }
  if cj == m {
    match_pos = Some(ci - m)
    cj = lps[cj - 1]
  } else if ci < n && text[ci] != pattern[cj] {
    if cj != 0 {
      cj = lps[cj - 1]
    } else {
      ci = ci + 1
    }
  }
  (ci, cj, match_pos)
}

/// Search for pattern in text using KMP algorithm.
/// Returns the starting index of the first occurrence, or -1 if not found.
pub fn kmp_search(
  text : String,
  pattern : String,
) -> Int {
  let n = text.length()
  let m = pattern.length()
  if m == 0 {
    return 0
  }
  if n < m {
    return -1
  }
  let lps = build_lps(pattern)
  let mut i = 0
  let mut j = 0
  while i < n {
    let (ni, nj, match_pos) = kmp_step(text, pattern, lps, i, j, m, n)
    i = ni
    j = nj
    if match_pos is Some(_) {
      return match_pos.unwrap()
    }
  }
  -1
}

/// Search for all occurrences of pattern in text.
/// Returns a FixedArray of starting indices (may be empty).
pub fn kmp_search_all(
  text : String,
  pattern : String,
) -> FixedArray[Int] {
  let n = text.length()
  let m = pattern.length()
  if m == 0 || n < m {
    return FixedArray::make(0, 0)
  }
  let lps = build_lps(pattern)
  // First pass: count matches
  let mut count = 0
  let mut i = 0
  let mut j = 0
  while i < n {
    let (ni, nj, match_pos) = kmp_step(text, pattern, lps, i, j, m, n)
    i = ni
    j = nj
    if match_pos is Some(_) {
      count = count + 1
    }
  }
  // Second pass: collect match positions
  let result = FixedArray::make(count, 0)
  let mut idx = 0
  i = 0
  j = 0
  while i < n {
    let (ni, nj, match_pos) = kmp_step(text, pattern, lps, i, j, m, n)
    i = ni
    j = nj
    if match_pos is Some(_) {
      result[idx] = match_pos.unwrap()
      idx = idx + 1
    }
  }
  result
}

test "kmp_search: basic match" {
  assert_eq(kmp_search("hello world", "world"), 6)
  assert_eq(kmp_search("hello world", "hello"), 0)
}

test "kmp_search: no match" {
  assert_eq(kmp_search("hello world", "xyz"), -1)
}

test "kmp_search: empty pattern" {
  assert_eq(kmp_search("hello", ""), 0)
}

test "kmp_search: empty text" {
  assert_eq(kmp_search("", "abc"), -1)
}

test "kmp_search: pattern longer than text" {
  assert_eq(kmp_search("hi", "hello"), -1)
}

test "kmp_search: overlapping matches" {
  assert_eq(kmp_search("AAAAAA", "AAAA"), 0)
}

test "kmp_search: single char" {
  assert_eq(kmp_search("abcdef", "d"), 3)
  assert_eq(kmp_search("abcdef", "z"), -1)
}

test "kmp_search: repeated pattern" {
  assert_eq(kmp_search("abababab", "abab"), 0)
}

test "kmp_search: at end" {
  assert_eq(kmp_search("abcdefghij", "hij"), 7)
}

test "kmp_search: full match" {
  assert_eq(kmp_search("hello", "hello"), 0)
}

test "kmp_search_all: basic" {
  let result = kmp_search_all("abababab", "ab")
  assert_eq(result.length(), 4)
  assert_eq(result[0], 0)
  assert_eq(result[1], 2)
  assert_eq(result[2], 4)
  assert_eq(result[3], 6)
}

test "kmp_search_all: no match" {
  let result = kmp_search_all("hello world", "xyz")
  assert_eq(result.length(), 0)
}

test "kmp_search_all: overlapping" {
  let result = kmp_search_all("aaaa", "aa")
  assert_eq(result.length(), 3)
  assert_eq(result[0], 0)
  assert_eq(result[1], 1)
  assert_eq(result[2], 2)
}

test "kmp_search_all: single occurrence" {
  let result = kmp_search_all("hello world", "world")
  assert_eq(result.length(), 1)
  assert_eq(result[0], 6)
}

test "build_lps: basic" {
  let lps = build_lps("AABAACAABAA")
  assert_eq(lps[0], 0)
  assert_eq(lps[1], 1)
  assert_eq(lps[2], 0)
  assert_eq(lps[3], 1)
  assert_eq(lps[4], 2)
  assert_eq(lps[5], 0)
  assert_eq(lps[9], 4)
}

test "build_lps: all same" {
  let lps = build_lps("AAAA")
  assert_eq(lps[0], 0)
  assert_eq(lps[1], 1)
  assert_eq(lps[2], 2)
  assert_eq(lps[3], 3)
}

test "build_lps: empty" {
  let lps = build_lps("")
  assert_eq(lps.length(), 0)
}
