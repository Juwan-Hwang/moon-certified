/// Suffix array construction using prefix doubling (Manber-Myers).
///
/// Builds the suffix array of a string in O(n log^2 n) time using a
/// comparison-based merge sort. The suffix array `sa` is a permutation of
/// [0, n) such that `s[sa[0]..] < s[sa[1]..] < ... < s[sa[n-1]..]`
/// lexicographically (byte-level comparison on the UTF-8 encoding).
///
/// The string is first converted to its UTF-8 byte representation. This
/// ensures correct handling of all Unicode characters, including those
/// outside the BMP (e.g. emoji, CJK Extension B). UTF-8 was designed so
/// that byte-level lexicographic comparison yields the same ordering as
/// codepoint-level comparison, so the resulting suffix array is correct
/// at both the byte and codepoint levels.
///
/// Algorithm:
/// 1. Convert the input string to UTF-8 bytes.
/// 2. Initialise ranks to individual byte values (0–255).
/// 3. For k = 1, 2, 4, ...: sort suffixes by the rank pair
///    (rank[i], rank[i+k]), then recompute ranks from the sorted order.
/// 4. Stop when all suffixes have distinct ranks (max rank == n - 1).
///
/// All indices in the returned suffix array are **byte offsets** into the
/// UTF-8 encoding of the string. For ASCII inputs, byte offsets coincide
/// with character positions.
///
/// Not formally verified (String operations not supported by moon prove).
/// Correctness ensured by comprehensive tests.

///|
/// Convert a MoonBit `String` to a `FixedArray[Int]` of UTF-8 byte values
/// (each in the range 0–255).
///
/// MoonBit's `String` is internally UTF-16; `String[i]` returns a UTF-16
/// code unit, not a raw byte. For non-BMP characters (e.g. emoji), a single
/// codepoint spans two UTF-16 code units (a surrogate pair), making
/// code-unit-level indexing incorrect for suffix comparison. By converting
/// to UTF-8 bytes we obtain a representation where:
/// - Each element is a single byte (0–255).
/// - Byte-level lexicographic order equals codepoint-level order (a design
///   property of UTF-8 per RFC 3629).
fn str_to_utf8_bytes(s : String) -> FixedArray[Int] {
  let buf : Array[Int] = []
  for c in s.iter() {
    let cp = c.to_uint()
    if cp <= 0x7FU {
      buf.push(cp.reinterpret_as_int())
    } else if cp <= 0x7FFU {
      buf.push((0xC0U | (cp >> 6)).reinterpret_as_int())
      buf.push((0x80U | (cp & 0x3FU)).reinterpret_as_int())
    } else if cp <= 0xFFFFU {
      buf.push((0xE0U | (cp >> 12)).reinterpret_as_int())
      buf.push((0x80U | ((cp >> 6) & 0x3FU)).reinterpret_as_int())
      buf.push((0x80U | (cp & 0x3FU)).reinterpret_as_int())
    } else {
      buf.push((0xF0U | (cp >> 18)).reinterpret_as_int())
      buf.push((0x80U | ((cp >> 12) & 0x3FU)).reinterpret_as_int())
      buf.push((0x80U | ((cp >> 6) & 0x3FU)).reinterpret_as_int())
      buf.push((0x80U | (cp & 0x3FU)).reinterpret_as_int())
    }
  }
  FixedArray::from_array(buf)
}

///|
/// Stable bottom-up (iterative) merge sort of `arr[lo, hi)` by comparator.
///
/// Uses an explicit bottom-up approach: merge sub-arrays of width 1, 2, 4,
/// 8, ... until the entire range is sorted. This avoids recursion entirely,
/// preventing stack overflow on large strings (the recursive variant could
/// crash at depth ~10⁴ on MoonBit's default stack).
fn msort_int(
  arr : FixedArray[Int],
  tmp : FixedArray[Int],
  lo : Int,
  hi : Int,
  cmp : (Int, Int) -> Int,
) -> Unit {
  let n = hi - lo
  if n <= 1 {
    return
  }
  let mut width = 1
  while width < n {
    let mut i = lo
    while i < hi {
      let mid = if i + width < hi { i + width } else { hi }
      let end = if i + 2 * width < hi { i + 2 * width } else { hi }
      if mid < end {
        // Merge [i, mid) and [mid, end) into tmp[i..end).
        let mut p = i
        let mut q = mid
        for k = i; k < end; k = k + 1 {
          if q >= end || (p < mid && cmp(arr[p], arr[q]) <= 0) {
            tmp[k] = arr[p]
            p = p + 1
          } else {
            tmp[k] = arr[q]
            q = q + 1
          }
        }
        // Copy back.
        for k = i; k < end; k = k + 1 {
          arr[k] = tmp[k]
        }
      }
      i = i + 2 * width
    }
    width = width * 2
  }
}

///|
/// Build the suffix array of `s`.
///
/// Returns a `FixedArray[Int]` of sorted suffix start indices (byte offsets
/// into the UTF-8 encoding of `s`).
pub fn build(s : String) -> FixedArray[Int] {
  let bytes = str_to_utf8_bytes(s)
  let n = bytes.length()
  if n == 0 {
    return FixedArray::make(0, 0)
  }
  if n == 1 {
    return FixedArray::make(1, 0)
  }
  // sa[i] = i-th smallest suffix start index.
  let sa = FixedArray::makei(n, fn(i) { i })
  // rank[i] = current rank of the suffix starting at byte position i.
  let rank = FixedArray::makei(n, fn(i) { bytes[i] })
  // tmp holds new ranks during recomputation.
  let tmp = FixedArray::make(n, 0)
  // Scratch array for merge sort.
  let sort_tmp = FixedArray::make(n, 0)
  let mut k = 1
  let mut need_more = true
  while need_more {
    // Comparator: compare suffixes starting at a and b by their
    // (rank[a], rank[a+k]) and (rank[b], rank[b+k]) pairs.
    let cmp = fn(a : Int, b : Int) -> Int {
      let ra = rank[a]
      let rb = rank[b]
      if ra != rb {
        ra - rb
      } else {
        let rak = if a + k < n { rank[a + k] } else { -1 }
        let rbk = if b + k < n { rank[b + k] } else { -1 }
        rak - rbk
      }
    }
    msort_int(sa, sort_tmp, 0, n, cmp)
    // Recompute ranks based on sorted order.
    tmp[sa[0]] = 0
    for i = 1; i < n; i = i + 1 {
      let prev = sa[i - 1]
      let curr = sa[i]
      let prev_r1 = rank[prev]
      let curr_r1 = rank[curr]
      let prev_r2 = if prev + k < n { rank[prev + k] } else { -1 }
      let curr_r2 = if curr + k < n { rank[curr + k] } else { -1 }
      if prev_r1 == curr_r1 && prev_r2 == curr_r2 {
        tmp[curr] = tmp[prev]
      } else {
        tmp[curr] = tmp[prev] + 1
      }
    }
    // Copy new ranks back to rank.
    for i = 0; i < n; i = i + 1 {
      rank[i] = tmp[i]
    }
    // Check termination: all ranks distinct or k large enough.
    if rank[sa[n - 1]] == n - 1 {
      need_more = false
    } else {
      k = k * 2
      if k >= n {
        need_more = false
      }
    }
  }
  sa
}

///|
/// Compare `pattern_bytes` with the suffix of `text_bytes` starting at `pos`.
/// Returns < 0 if the suffix is lexicographically smaller than `pattern`,
/// 0 if the suffix starts with `pattern`, > 0 if the suffix is greater.
fn compare_suffix_pattern_bytes(
  text_bytes : FixedArray[Int],
  pos : Int,
  pattern_bytes : FixedArray[Int],
) -> Int {
  let n = text_bytes.length()
  let m = pattern_bytes.length()
  for i = 0; i < m; i = i + 1 {
    if pos + i >= n {
      // Suffix exhausted before pattern: suffix < pattern.
      return -1
    }
    let sc = text_bytes[pos + i]
    let pc = pattern_bytes[i]
    if sc != pc {
      return sc - pc
    }
  }
  // All of pattern matched: suffix starts with pattern.
  0
}

///|
/// Binary search for `pattern` in the suffix array of `s`.
///
/// Returns `Some(pos)` where `pos` is the starting byte offset in the UTF-8
/// encoding of `s` of the lexicographically smallest suffix that begins with
/// `pattern`, or `None` if no suffix starts with `pattern`.
pub fn search(sa : FixedArray[Int], s : String, pattern : String) -> Int? {
  let text_bytes = str_to_utf8_bytes(s)
  let pattern_bytes = str_to_utf8_bytes(pattern)
  let n = text_bytes.length()
  let m = pattern_bytes.length()
  if m == 0 {
    return None
  }
  // Binary search for the leftmost suffix >= pattern.
  let mut lo = 0
  let mut hi = n
  while lo < hi {
    let mid = (lo + hi) / 2
    let cmp = compare_suffix_pattern_bytes(text_bytes, sa[mid], pattern_bytes)
    if cmp < 0 {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  // Check whether the found suffix actually starts with pattern.
  if lo < n {
    if compare_suffix_pattern_bytes(text_bytes, sa[lo], pattern_bytes) == 0 {
      return Some(sa[lo])
    }
  }
  None
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

///|
/// Compare two suffixes of `text_bytes` starting at `a` and `b` lexicographically.
/// Returns < 0, 0, or > 0.
fn compare_suffixes_bytes(
  text_bytes : FixedArray[Int],
  a : Int,
  b : Int,
) -> Int {
  let n = text_bytes.length()
  let mut i = 0
  while a + i < n && b + i < n {
    let ca = text_bytes[a + i]
    let cb = text_bytes[b + i]
    if ca != cb {
      return ca - cb
    }
    i = i + 1
  }
  if a + i >= n && b + i >= n {
    0
  } else if a + i >= n {
    -1 // a is shorter, so a < b
  } else {
    1 // b is shorter, so a > b
  }
}

///|
/// Check that the suffix array produces lexicographically sorted suffixes.
fn is_sorted_suffixes(sa : FixedArray[Int], s : String) -> Bool {
  let text_bytes = str_to_utf8_bytes(s)
  let n = sa.length()
  if n <= 1 {
    return true
  }
  for i = 0; i < n - 1; i = i + 1 {
    if compare_suffixes_bytes(text_bytes, sa[i], sa[i + 1]) >= 0 {
      return false
    }
  }
  true
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "build: basic string" {
  let sa = build("banana")
  // Suffixes sorted: a(5) < ana(3) < anana(1) < banana(0) < na(4) < nana(2)
  assert_eq(sa.length(), 6)
  assert_eq(sa[0], 5)
  assert_eq(sa[1], 3)
  assert_eq(sa[2], 1)
  assert_eq(sa[3], 0)
  assert_eq(sa[4], 4)
  assert_eq(sa[5], 2)
  assert_true(is_sorted_suffixes(sa, "banana"))
}

///|
test "build: empty string" {
  let sa = build("")
  assert_eq(sa.length(), 0)
}

///|
test "build: single char" {
  let sa = build("a")
  assert_eq(sa.length(), 1)
  assert_eq(sa[0], 0)
  assert_true(is_sorted_suffixes(sa, "a"))
}

///|
test "build: repeated chars aaaa" {
  let sa = build("aaaa")
  // Suffixes: a(3) < aa(2) < aaa(1) < aaaa(0)
  assert_eq(sa.length(), 4)
  assert_eq(sa[0], 3)
  assert_eq(sa[1], 2)
  assert_eq(sa[2], 1)
  assert_eq(sa[3], 0)
  assert_true(is_sorted_suffixes(sa, "aaaa"))
}

///|
test "build: banana" {
  let sa = build("banana")
  assert_eq(sa.length(), 6)
  assert_true(is_sorted_suffixes(sa, "banana"))
  // Verify the known SA for "banana".
  assert_eq(sa[0], 5)
  assert_eq(sa[1], 3)
  assert_eq(sa[2], 1)
  assert_eq(sa[3], 0)
  assert_eq(sa[4], 4)
  assert_eq(sa[5], 2)
}

///|
test "search: pattern found" {
  let sa = build("banana")
  // "ana" occurs at positions 1 and 3 in "banana".
  let result = search(sa, "banana", "ana")
  assert_true(result is Some(_))
  let pos = result.unwrap()
  // The lexicographically smallest matching suffix is "ana" at position 3.
  assert_eq(pos, 3)
}

///|
test "search: pattern not found" {
  let sa = build("banana")
  assert_true(search(sa, "banana", "xyz") is None)
  assert_true(search(sa, "banana", "bananas") is None)
}

///|
test "build: large string 100 chars" {
  // Build a 100-character string with a repeating pattern.
  let mut s = ""
  for i = 0; i < 50; i = i + 1 {
    s = s + "ab"
  }
  // s = "ababab...ab" (100 chars, 100 UTF-8 bytes since all ASCII)
  assert_eq(s.length(), 100)
  let sa = build(s)
  assert_eq(sa.length(), 100)
  assert_true(is_sorted_suffixes(sa, s))
  // Verify: suffixes starting with 'a' (even indices) come before those
  // starting with 'b' (odd indices).
  for i = 0; i < 50; i = i + 1 {
    assert_eq(sa[i] % 2, 0) // even index starts with 'a'
  }
  for i = 50; i < 100; i = i + 1 {
    assert_eq(sa[i] % 2, 1) // odd index starts with 'b'
  }
}

///|
test "build: verify sorted suffixes for various strings" {
  let strings = [
    "mississippi", "abracadabra", "abababab", "abcdefgh", "hgfedcba",
  ]
  for i = 0; i < strings.length(); i = i + 1 {
    let s = strings[i]
    let sa = build(s)
    assert_true(is_sorted_suffixes(sa, s))
  }
}

///|
test "search: full string match" {
  let sa = build("banana")
  assert_eq(search(sa, "banana", "banana"), Some(0))
}

///|
test "search: single char pattern" {
  let sa = build("banana")
  // "a" occurs at positions 1, 3, 5. Lex smallest suffix starting with "a"
  // is "a" at position 5.
  assert_eq(search(sa, "banana", "a"), Some(5))
  // "b" occurs at position 0.
  assert_eq(search(sa, "banana", "b"), Some(0))
}

///|
test "search: empty pattern returns None" {
  let sa = build("banana")
  assert_true(search(sa, "banana", "") is None)
}

///|
test "search: multiple matches returns valid position" {
  let s = "abababab"
  let sa = build(s)
  let result = search(sa, s, "ab")
  assert_true(result is Some(_))
  let pos = result.unwrap()
  // Verify the pattern actually occurs at the returned position.
  let bytes = str_to_utf8_bytes(s)
  assert_eq(bytes[pos], 97) // 'a'
  assert_eq(bytes[pos + 1], 98) // 'b'
}

///|
test "search: pattern at end of string" {
  let sa = build("abcdef")
  assert_eq(search(sa, "abcdef", "ef"), Some(4))
  assert_eq(search(sa, "abcdef", "f"), Some(5))
}

///|
test "search: pattern longer than string" {
  let sa = build("abc")
  assert_true(search(sa, "abc", "abcd") is None)
}

///|
test "build: non-ASCII (UTF-8 multi-byte)" {
  // "café" = c(1) a(1) f(1) é(2 bytes in UTF-8) = 5 bytes total
  let sa = build("café")
  // UTF-8 bytes: 99 97 102 195 169
  assert_eq(sa.length(), 5)
  assert_true(is_sorted_suffixes(sa, "café"))
  // Suffixes (byte-level), sorted by first byte value:
  // 1: 97  102 195 169  ("afé")
  // 0: 99  97  102 195 169  ("café")
  // 2: 102 195 169  ("fé")
  // 4: 169 (continuation byte of é, sorts before lead byte)
  // 3: 195 169  ("é" lead byte)
  assert_eq(sa[0], 1) // "afé" — 'a' = 97
  assert_eq(sa[1], 0) // "café" — 'c' = 99
  assert_eq(sa[2], 2) // "fé" — 'f' = 102
  assert_eq(sa[3], 4) // continuation byte 0xA9 = 169
  assert_eq(sa[4], 3) // "é" lead byte 0xC3 = 195
}

///|
test "build: emoji (non-BMP codepoint)" {
  // "a😀b" — 😀 is U+1F600, 4 UTF-8 bytes: F0 9F 98 80
  // Total: 1 + 4 + 1 = 6 bytes
  let sa = build("a😀b")
  assert_eq(sa.length(), 6)
  assert_true(is_sorted_suffixes(sa, "a😀b"))
  // Byte values: 97 240 159 152 128 98
  // Suffixes sorted by first byte:
  // 0: 97  240 159 152 128 98  ("a😀b")
  // 5: 98                        ("b")
  // 4: 128 98                    (continuation byte + "b")
  // 3: 152 128 98                (continuation byte + ...)
  // 2: 159 152 128 98            (continuation byte + ...)
  // 1: 240 159 152 128 98        ("😀b")
  assert_eq(sa[0], 0) // 'a' = 97
  assert_eq(sa[1], 5) // 'b' = 98
  assert_eq(sa[2], 4) // continuation byte 0x80 = 128
  assert_eq(sa[3], 3) // continuation byte 0x98 = 152
  assert_eq(sa[4], 2) // continuation byte 0x9F = 159
  assert_eq(sa[5], 1) // lead byte 0xF0 = 240
}

///|
test "search: non-ASCII pattern" {
  let sa = build("café")
  // Search for "é" — its UTF-8 bytes are C3 A9, at byte offset 3
  assert_eq(search(sa, "café", "é"), Some(3))
  // Search for "af" — at byte offset 1
  assert_eq(search(sa, "café", "af"), Some(1))
}
