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

/// Search for pattern in text using KMP algorithm.
///
/// Returns `Some(index)` for the first match, or `None` if not found.
/// Empty pattern returns `None` (no meaningful search), consistent with
/// `kmp_search_all` returning an empty array for empty pattern.
pub fn kmp_search(
  text : String,
  pattern : String,
) -> Int? {
  let n = text.length()
  let m = pattern.length()
  if m == 0 {
    return None
  }
  if n < m {
    return None
  }
  let lps = build_lps(pattern)
  let mut i = 0
  let mut j = 0
  while i < n {
    if text[i] == pattern[j] {
      i = i + 1
      j = j + 1
      if j == m {
        return Some(i - m)
      }
    } else if j != 0 {
      j = lps[j - 1]
    } else {
      i = i + 1
    }
  }
  None
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
    if text[i] == pattern[j] {
      i = i + 1
      j = j + 1
      if j == m {
        count = count + 1
        j = lps[j - 1]
      }
    } else if j != 0 {
      j = lps[j - 1]
    } else {
      i = i + 1
    }
  }
  // Second pass: collect match positions
  let result = FixedArray::make(count, 0)
  let mut idx = 0
  i = 0
  j = 0
  while i < n {
    if text[i] == pattern[j] {
      i = i + 1
      j = j + 1
      if j == m {
        result[idx] = i - m
        idx = idx + 1
        j = lps[j - 1]
      }
    } else if j != 0 {
      j = lps[j - 1]
    } else {
      i = i + 1
    }
  }
  result
}

test "kmp_search: basic match" {
  assert_eq(kmp_search("hello world", "world"), Some(6))
  assert_eq(kmp_search("hello world", "hello"), Some(0))
}

test "kmp_search: no match" {
  assert_true(kmp_search("hello world", "xyz") is None)
}

test "kmp_search: empty pattern returns None" {
  assert_true(kmp_search("hello", "") is None)
}

test "kmp_search: empty text" {
  assert_true(kmp_search("", "abc") is None)
}

test "kmp_search: pattern longer than text" {
  assert_true(kmp_search("hi", "hello") is None)
}

test "kmp_search: overlapping matches" {
  assert_eq(kmp_search("AAAAAA", "AAAA"), Some(0))
}

test "kmp_search: single char" {
  assert_eq(kmp_search("abcdef", "d"), Some(3))
  assert_true(kmp_search("abcdef", "z") is None)
}

test "kmp_search: repeated pattern" {
  assert_eq(kmp_search("abababab", "abab"), Some(0))
}

test "kmp_search: at end" {
  assert_eq(kmp_search("abcdefghij", "hij"), Some(7))
}

test "kmp_search: full match" {
  assert_eq(kmp_search("hello", "hello"), Some(0))
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
