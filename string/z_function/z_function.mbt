/// Z-algorithm for string matching and prefix analysis.
///
/// The Z-array of a string `s` of length `n` is defined by
///   Z[i] = length of the longest common prefix of `s` and `s[i..]`.
/// Equivalently, Z[i] is the largest `k` such that `s[0..k] == s[i..i+k]`.
///
/// Convention: Z[0] is set to 0.  The value at index 0 is trivially `n`
/// (a string is its own longest prefix), so it carries no useful
/// information; setting it to 0 is the common competitive-programming
/// convention and keeps the Z-box invariant simple.  Some texts instead
/// set Z[0] = n — both are valid as long as the choice is documented.
///
/// Algorithm: the Z-box technique.  We maintain the interval `[l, r)`
/// of the rightmost position `r` for which `s[l..r] == s[0..r-l]`.
/// For each `i` inside the box, the mirrored position `i - l` (in the
/// prefix) gives a lower bound `min(Z[i-l], r - i)` on Z[i], after
/// which we expand character by character.  This yields O(n) total time
/// because `r` only ever moves right and each successful comparison
/// advances it.
///
/// Pattern search (`z_search`): concatenate `pattern + sep + text`
/// (with a single-byte separator) and compute the Z-array.  Every text
/// position whose Z-value reaches `pattern.length()` is an occurrence.
/// We test `Z[i] >= m` rather than `Z[i] == m`: with a separator that is
/// guaranteed absent from the input the two are equivalent, but the `>=`
/// test is correct unconditionally (it does not rely on the separator
/// being absent, e.g. when the input itself contains the null byte).
///
/// IMPORTANT: MoonBit's `String` indexing is byte-level, not Unicode
/// codepoint.  For multi-byte UTF-8 strings (e.g. Chinese, emoji),
/// matching operates on raw bytes and may match in the middle of a
/// multi-byte character.  This is correct for ASCII-only inputs.  For
/// Unicode-aware matching, convert to a `FixedArray[Int]` of codepoints
/// first.
///
/// Not formally verified (`String` operations are not supported by
/// `moon prove`).  Correctness is ensured by comprehensive tests.
///
/// Time complexity: O(n) for `z_array`, O(n + m) for `z_search`.
/// Space complexity: O(n) / O(n + m).

/// Compute the Z-array of `s`.
///
/// `z[i]` is the length of the longest common prefix of `s` and `s[i..]`.
/// `z[0]` is 0 by convention (see the file header).
pub fn z_array(s : String) -> FixedArray[Int] {
  let n = s.length()
  let z = FixedArray::make(n, 0)
  if n == 0 {
    return z
  }
  // z[0] = 0 by convention.
  let mut l = 0 // inclusive left end of the rightmost Z-box [l, r)
  let mut r = 0 // exclusive right end of the rightmost Z-box
  for i = 1; i < n; i = i + 1 {
    if i < r {
      // `i` lies inside the box s[l..r) == s[0..r-l).  Position `i` mirrors
      // position (i - l) in the prefix, so Z[i] is lower-bounded by the
      // smaller of Z[i - l] and the remaining box width (r - i).
      let mirror = i - l
      let bound = r - i
      z[i] = if z[mirror] < bound { z[mirror] } else { bound }
    }
    // Extend the match past the initial lower bound.
    while i + z[i] < n && s[z[i]] == s[i + z[i]] {
      z[i] = z[i] + 1
    }
    // Move the Z-box rightwards if we expanded past `r`.
    if i + z[i] > r {
      l = i
      r = i + z[i]
    }
  }
  z
}

/// Find all occurrences of `pattern` in `text` using the Z-algorithm.
///
/// Returns a `FixedArray[Int]` of starting indices in ascending order
/// (possibly empty).  The concatenated string `pattern + sep + text` is
/// built with a single-byte separator; a text index `i` is reported when
/// `Z[i] >= pattern.length()` (see the file header for why `>=` is used).
///
/// Edge cases (consistent with the sibling `kmp` / `rabin_karp` packages):
/// - empty pattern -> empty array (no well-defined match positions)
/// - pattern longer than text -> empty array
pub fn z_search(pattern : String, text : String) -> FixedArray[Int] {
  let m = pattern.length()
  let n = text.length()
  if m == 0 || n < m {
    return FixedArray::make(0, 0)
  }
  // Concatenate pattern + separator + text.  '\u{0}' is a single byte that
  // prevents matches from spanning the boundary into the pattern region.
  let combined = pattern + "\u{0}" + text
  let z = z_array(combined)
  let result : Array[Int] = []
  // The text occupies indices [m + 1, m + 1 + n) of `combined`; each such
  // index maps back to text position (i - m - 1).
  for i = m + 1; i < m + 1 + n; i = i + 1 {
    if z[i] >= m {
      result.push(i - m - 1)
    }
  }
  FixedArray::from_array(result)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "z_array: classic example aabcaab" {
  // s = a a b c a a b
  // Z[4] = 3 because s[4..] = "aab" is a prefix of s.
  let z = z_array("aabcaab")
  assert_eq(z.length(), 7)
  assert_eq(z[0], 0) // by convention
  assert_eq(z[1], 1)
  assert_eq(z[2], 0)
  assert_eq(z[3], 0)
  assert_eq(z[4], 3)
  assert_eq(z[5], 1)
  assert_eq(z[6], 0)
}

test "z_array: all same characters aaaa" {
  let z = z_array("aaaa")
  assert_eq(z.length(), 4)
  assert_eq(z[0], 0)
  assert_eq(z[1], 3)
  assert_eq(z[2], 2)
  assert_eq(z[3], 1)
}

test "z_array: no repeated prefix abcde" {
  let z = z_array("abcde")
  assert_eq(z.length(), 5)
  for i = 0; i < 5; i = i + 1 {
    assert_eq(z[i], 0)
  }
}

test "z_array: single char" {
  let z = z_array("a")
  assert_eq(z.length(), 1)
  assert_eq(z[0], 0)
}

test "z_array: empty string" {
  let z = z_array("")
  assert_eq(z.length(), 0)
}

test "z_array: abababab" {
  // s = a b a b a b a b
  // Z[1]=0, Z[2]=6, Z[3]=0, Z[4]=4, Z[5]=0, Z[6]=2, Z[7]=0
  let z = z_array("abababab")
  assert_eq(z[0], 0)
  assert_eq(z[1], 0)
  assert_eq(z[2], 6)
  assert_eq(z[3], 0)
  assert_eq(z[4], 4)
  assert_eq(z[5], 0)
  assert_eq(z[6], 2)
  assert_eq(z[7], 0)
}

test "z_search: basic match" {
  // "ab" occurs at positions 0, 2, 5 in "ababcab"
  let result = z_search("ab", "ababcab")
  assert_eq(result.length(), 3)
  assert_eq(result[0], 0)
  assert_eq(result[1], 2)
  assert_eq(result[2], 5)
}

test "z_search: no matches" {
  let result = z_search("xyz", "hello world")
  assert_eq(result.length(), 0)
}

test "z_search: single char pattern" {
  let result = z_search("a", "banana")
  assert_eq(result.length(), 3)
  assert_eq(result[0], 1)
  assert_eq(result[1], 3)
  assert_eq(result[2], 5)
  // single char not present
  let none = z_search("z", "banana")
  assert_eq(none.length(), 0)
}

test "z_search: empty pattern returns empty" {
  let result = z_search("", "hello")
  assert_eq(result.length(), 0)
  // empty pattern and empty text
  assert_eq(z_search("", "").length(), 0)
}

test "z_search: pattern equals text" {
  let result = z_search("hello", "hello")
  assert_eq(result.length(), 1)
  assert_eq(result[0], 0)
}

test "z_search: overlapping matches" {
  // "aa" in "aaaa" matches at 0, 1, 2
  let result = z_search("aa", "aaaa")
  assert_eq(result.length(), 3)
  assert_eq(result[0], 0)
  assert_eq(result[1], 1)
  assert_eq(result[2], 2)
}

test "z_search: repeated pattern" {
  // "ab" in "abababab" matches at 0, 2, 4, 6
  let result = z_search("ab", "abababab")
  assert_eq(result.length(), 4)
  assert_eq(result[0], 0)
  assert_eq(result[1], 2)
  assert_eq(result[2], 4)
  assert_eq(result[3], 6)
}

test "z_search: all same characters" {
  // "aaa" in "aaaaaa" matches at 0, 1, 2, 3 (overlapping)
  let result = z_search("aaa", "aaaaaa")
  assert_eq(result.length(), 4)
  assert_eq(result[0], 0)
  assert_eq(result[1], 1)
  assert_eq(result[2], 2)
  assert_eq(result[3], 3)
}

test "z_search: pattern longer than text" {
  assert_eq(z_search("hello", "hi").length(), 0)
  assert_eq(z_search("abcdef", "abc").length(), 0)
}

test "z_search: match at end" {
  let result = z_search("xyz", "abcdefghijxyz")
  assert_eq(result.length(), 1)
  assert_eq(result[0], 10)
}

test "z_search: cross-check against z_array definition" {
  // Verify z_search agrees with a brute-force scan over many small inputs.
  let haystack = "ababcababababcab"
  let needle = "ab"
  let brute : Array[Int] = []
  for i = 0; i + needle.length() <= haystack.length(); i = i + 1 {
    let mut ok = true
    for k = 0; k < needle.length(); k = k + 1 {
      if haystack[i + k] != needle[k] {
        ok = false
      }
    }
    if ok {
      brute.push(i)
    }
  }
  let fast = z_search(needle, haystack)
  assert_eq(fast.length(), brute.length())
  for i = 0; i < fast.length(); i = i + 1 {
    assert_eq(fast[i], brute[i])
  }
}

test "z_search: large periodic text" {
  // 100 repetitions of "ab" -> "ab" occurs at every even index 0..198
  let mut text = ""
  for i = 0; i < 100; i = i + 1 {
    text = text + "ab"
  }
  let result = z_search("ab", text)
  assert_eq(result.length(), 100)
  for i = 0; i < 100; i = i + 1 {
    assert_eq(result[i], i * 2)
  }
}
