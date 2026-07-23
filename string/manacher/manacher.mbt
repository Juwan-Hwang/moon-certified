/// Manacher's algorithm for palindromic substrings.
///
/// Finds all palindromic substrings of a string in linear time.  The key
/// idea is to interleave the input with sentinel separators so that every
/// palindrome — odd- or even-length — has a single well-defined center,
/// then reuse the symmetry of an already-known rightmost palindrome to
/// avoid re-comparing characters.
///
/// Transformation.  For an input `s` of length `n`, build a working array
///   t = [#, s[0], #, s[1], #, ..., #, s[n-1], #]
/// of length `2n + 1`, where `#` is a sentinel.  Here the sentinel is the
/// integer `-1`, which lies outside the byte range [0, 255] and therefore
/// can never collide with an actual input byte.  This is exactly the
/// standard `#`-separator formulation but rendered collision-free, so the
/// algorithm is correct for arbitrary byte content (including inputs that
/// themselves contain a `#`).
///
/// Radius array.  `p[i]` is the radius of the longest palindrome centered
/// at `t[i]`, i.e. the palindrome spans `t[i - p[i] .. i + p[i]]`.  Two
/// clean identities follow from the alternating layout:
///   - the length (in bytes) of the corresponding palindromic substring of
///     `s` equals `p[i]`;
///   - the start index of that substring in `s` is `(i - p[i]) / 2`.
/// Even indices `i` of `p` are separator centers (even-length palindromes
/// in `s`); odd indices are character centers (odd-length palindromes).
///
/// Algorithm.  Maintain the rightmost palindrome found so far, with center
/// `c` and exclusive right bound `r = c + p[c]`.  For a new center `i < r`,
/// its mirror `2*c - i` gives a lower bound `min(p[mirror], r - i)` on
/// `p[i]`, after which we expand naively.  As with the Z-algorithm, `r`
/// only moves right and each successful comparison advances it, giving
/// O(n) total time.
///
/// Counting.  The number of palindromic substrings centered at `i` is
/// `(p[i] + 1) / 2` (the palindrome of radius `p[i]` and every nested
/// shorter one), so the total count is `sum_i (p[i] + 1) / 2`.
///
/// IMPORTANT: MoonBit's `String` indexing is byte-level, not Unicode
/// codepoint.  For multi-byte UTF-8 strings, palindromes are detected at
/// the byte level and may begin/end inside a multi-byte character.  This
/// is correct for ASCII-only inputs.  For Unicode-aware detection, convert
/// to a `FixedArray[Int]` of codepoints first.
///
/// Not formally verified (`String` operations are not supported by
/// `moon prove`).  Correctness is ensured by comprehensive tests.
///
/// Time complexity: O(n).
/// Space complexity: O(n).

/// Sentinel value used in the transformed array.  It is outside the byte
/// range [0, 255], so it can never collide with an actual input byte,
/// making the algorithm correct for arbitrary byte content.  Conceptually
/// it plays the role of the `#` separator in the standard formulation.
const MANACHER_SENTINEL : Int = -1

/// Build the transformed array `t` of length `2n + 1`:
///   t = [#, s[0], #, s[1], #, ..., #, s[n-1], #]
/// Even positions hold the sentinel; odd positions hold the byte values
/// of `s`.
fn manacher_transform(s : String) -> FixedArray[Int] {
  let n = s.length()
  let m = 2 * n + 1
  let t = FixedArray::make(m, MANACHER_SENTINEL)
  for i = 0; i < n; i = i + 1 {
    t[2 * i + 1] = s[i].to_int()
  }
  t
}

/// Run Manacher's algorithm on the transformed array `t`.
///
/// Returns the radius array `p` where `p[i]` is the radius of the longest
/// palindrome centered at `t[i]` (the palindrome spans
/// `t[i - p[i] .. i + p[i]]`).
fn manacher_core(t : FixedArray[Int]) -> FixedArray[Int] {
  let m = t.length()
  let p = FixedArray::make(m, 0)
  let mut c = 0 // center of the rightmost palindrome
  let mut r = 0 // exclusive right bound: r = c + p[c]
  for i = 0; i < m; i = i + 1 {
    if i < r {
      // `i` lies inside the rightmost palindrome; mirror it around `c`.
      let mirror = 2 * c - i
      let bound = r - i
      p[i] = if p[mirror] < bound { p[mirror] } else { bound }
    }
    // Expand the palindrome around `i` as far as possible.
    while i - p[i] - 1 >= 0 &&
      i + p[i] + 1 < m &&
      t[i - p[i] - 1] == t[i + p[i] + 1] {
      p[i] = p[i] + 1
    }
    // Update the rightmost palindrome if we expanded past `r`.
    if i + p[i] > r {
      c = i
      r = i + p[i]
    }
  }
  p
}

/// Return the palindrome radius array of `s`.
///
/// The returned array has length `2 * s.length() + 1` and corresponds to
/// the transformed string with sentinel separators: index `2*i` is a
/// separator center (even-length palindromes in `s`) and index `2*i + 1`
/// is the center at `s[i]` (odd-length palindromes).  `p[i]` equals the
/// length in bytes of the longest palindromic substring centered there.
pub fn palindrome_radii(s : String) -> FixedArray[Int] {
  let t = manacher_transform(s)
  manacher_core(t)
}

/// Return the longest palindromic substring of `s`, or `None` if `s` is
/// empty.  When several substrings share the maximum length, the one with
/// the smallest center (and hence the smallest start index) is returned.
pub fn longest_palindrome(s : String) -> String? {
  let n = s.length()
  if n == 0 {
    return None
  }
  let p = palindrome_radii(s)
  let mut best_center = 0
  let mut best_len = 0
  for i = 0; i < p.length(); i = i + 1 {
    if p[i] > best_len {
      best_len = p[i]
      best_center = i
    }
  }
  let start = (best_center - best_len) / 2
  let end = start + best_len
  Some(s[start:end].to_owned())
}

/// Count all palindromic substrings of `s`.
///
/// Each center `i` contributes `(p[i] + 1) / 2` palindromes (the longest
/// one centered there plus every nested shorter palindrome), so the total
/// is `sum_i (p[i] + 1) / 2`.  Returns 0 for the empty string.
pub fn count_palindromes(s : String) -> Int {
  let p = palindrome_radii(s)
  let mut count = 0
  for i = 0; i < p.length(); i = i + 1 {
    count = count + (p[i] + 1) / 2
  }
  count
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "palindrome_radii: basic aba" {
  // t = # a # b # a #  ->  p = [0,1,0,3,0,1,0]
  let p = palindrome_radii("aba")
  assert_eq(p.length(), 7)
  assert_eq(p[0], 0)
  assert_eq(p[1], 1)
  assert_eq(p[2], 0)
  assert_eq(p[3], 3)
  assert_eq(p[4], 0)
  assert_eq(p[5], 1)
  assert_eq(p[6], 0)
}

test "palindrome_radii: single char" {
  // t = # a #  ->  p = [0,1,0]
  let p = palindrome_radii("a")
  assert_eq(p.length(), 3)
  assert_eq(p[0], 0)
  assert_eq(p[1], 1)
  assert_eq(p[2], 0)
}

test "palindrome_radii: empty string" {
  // t = #  ->  p = [0]
  let p = palindrome_radii("")
  assert_eq(p.length(), 1)
  assert_eq(p[0], 0)
}

test "palindrome_radii: aa (even palindrome)" {
  // t = # a # a #  ->  p = [0,1,2,1,0]
  let p = palindrome_radii("aa")
  assert_eq(p.length(), 5)
  assert_eq(p[0], 0)
  assert_eq(p[1], 1)
  assert_eq(p[2], 2)
  assert_eq(p[3], 1)
  assert_eq(p[4], 0)
}

test "palindrome_radii: aaaa" {
  // t = # a # a # a # a #  ->  p = [0,1,2,3,4,3,2,1,0]
  let p = palindrome_radii("aaaa")
  assert_eq(p.length(), 9)
  assert_eq(p[0], 0)
  assert_eq(p[1], 1)
  assert_eq(p[2], 2)
  assert_eq(p[3], 3)
  assert_eq(p[4], 4)
  assert_eq(p[5], 3)
  assert_eq(p[6], 2)
  assert_eq(p[7], 1)
  assert_eq(p[8], 0)
}

test "longest_palindrome: basic aba" {
  assert_eq(longest_palindrome("aba"), Some("aba"))
}

test "longest_palindrome: babad accepts bab or aba" {
  // Both "bab" (start 0) and "aba" (start 1) are valid length-3 answers.
  let r = longest_palindrome("babad")
  assert_true(r is Some(_))
  let v = r.unwrap()
  assert_eq(v.length(), 3)
  assert_true(v == "bab" || v == "aba")
}

test "longest_palindrome: cbbd -> bb" {
  assert_eq(longest_palindrome("cbbd"), Some("bb"))
}

test "longest_palindrome: single char" {
  assert_eq(longest_palindrome("a"), Some("a"))
}

test "longest_palindrome: empty string returns None" {
  assert_true(longest_palindrome("") is None)
}

test "longest_palindrome: all same chars aaaa" {
  assert_eq(longest_palindrome("aaaa"), Some("aaaa"))
}

test "longest_palindrome: even length abba" {
  assert_eq(longest_palindrome("abba"), Some("abba"))
}

test "longest_palindrome: no palindrome longer than 1" {
  // "abcd" has no palindrome longer than a single character.
  let r = longest_palindrome("abcd")
  assert_true(r is Some(_))
  let v = r.unwrap()
  assert_eq(v.length(), 1)
  // The result must actually be a (single-char) palindrome.
  assert_true(v == "a" || v == "b" || v == "c" || v == "d")
}

test "longest_palindrome: longer string racecar" {
  assert_eq(longest_palindrome("racecar"), Some("racecar"))
}

test "longest_palindrome: palindrome in the middle" {
  assert_eq(longest_palindrome("xyzracecarabc"), Some("racecar"))
}

test "count_palindromes: aba" {
  // "a", "b", "a", "aba" -> 4
  assert_eq(count_palindromes("aba"), 4)
}

test "count_palindromes: aaa" {
  // "a","a","a","aa","aa","aaa" -> 6
  assert_eq(count_palindromes("aaa"), 6)
}

test "count_palindromes: abc (no palindrome longer than 1)" {
  // "a", "b", "c" -> 3
  assert_eq(count_palindromes("abc"), 3)
}

test "count_palindromes: empty string" {
  assert_eq(count_palindromes(""), 0)
}

test "count_palindromes: aa" {
  // "a", "a", "aa" -> 3
  assert_eq(count_palindromes("aa"), 3)
}

test "count_palindromes: aaaa" {
  // a(4) + aa(3) + aaa(2) + aaaa(1) = 10
  assert_eq(count_palindromes("aaaa"), 10)
}

test "count_palindromes: abba" {
  // "a","b","b","a","bb","abba" -> 6
  assert_eq(count_palindromes("abba"), 6)
}

test "manacher: cross-check against brute force" {
  // Verify longest_palindrome and count_palindromes against naive O(n^2)
  // implementations over several inputs.
  let inputs = [
    "aba", "babad", "cbbd", "aaaa", "abba", "abcd", "racecar",
    "bananas", "abacdfgdcaba", "a", "", "aaabaaa", "xabay",
  ]
  for k = 0; k < inputs.length(); k = k + 1 {
    let s = inputs[k]
    // Brute-force longest palindrome length.
    let n = s.length()
    let mut best_len = 0
    for i = 0; i < n; i = i + 1 {
      for j = i; j < n; j = j + 1 {
        // check s[i..j] is a palindrome
        let mut lo = i
        let mut hi = j
        let mut is_palin = true
        while lo < hi {
          if s[lo] != s[hi] {
            is_palin = false
          }
          lo = lo + 1
          hi = hi - 1
        }
        if is_palin {
          let len = j - i + 1
          if len > best_len {
            best_len = len
          }
        }
      }
    }
    // Brute-force count.
    let mut brute_count = 0
    for i = 0; i < n; i = i + 1 {
      for j = i; j < n; j = j + 1 {
        let mut lo = i
        let mut hi = j
        let mut is_palin = true
        while lo < hi {
          if s[lo] != s[hi] {
            is_palin = false
          }
          lo = lo + 1
          hi = hi - 1
        }
        if is_palin {
          brute_count = brute_count + 1
        }
      }
    }
    // Compare counts directly.
    assert_eq(count_palindromes(s), brute_count)
    // Compare longest: same length, and the returned value must be a
    // palindrome of that length.
    let res = longest_palindrome(s)
    if best_len == 0 {
      assert_true(res is None)
    } else {
      assert_true(res is Some(_))
      let v = res.unwrap()
      assert_eq(v.length(), best_len)
      // verify v is a palindrome
      let mut lo = 0
      let mut hi = v.length() - 1
      let mut ok = true
      while lo < hi {
        if v[lo] != v[hi] {
          ok = false
        }
        lo = lo + 1
        hi = hi - 1
      }
      assert_true(ok)
    }
  }
}
