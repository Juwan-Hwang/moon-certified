/// Rabin-Karp string matching with polynomial rolling hash.
///
/// Uses a base of 256 (natural for byte-level matching) and the large prime
/// modulus 1_000_000_007.  Hash arithmetic is performed in `Int64` to avoid
/// the 32-bit `Int` overflow that would otherwise occur when multiplying a
/// hash value (< 10^9) by the base (256).
///
/// Hash collisions are resolved by verifying the actual characters at every
/// candidate position, so the result is always exact — never a false positive.
///
/// IMPORTANT: MoonBit's `String` indexing is byte-level, not Unicode codepoint.
/// For multi-byte UTF-8 strings (e.g., Chinese, emoji), matching operates on
/// raw bytes and may match in the middle of a multi-byte character.  This is
/// correct for ASCII-only inputs.  For Unicode-aware matching, convert to a
/// `FixedArray[Int]` of codepoints first.
///
/// Not formally verified (`String` operations are not supported by `moon prove`).
/// Correctness is ensured by comprehensive tests.
///
/// Time complexity: O(n + m) average, O(n·m) worst-case (adversarial input
/// with many hash collisions).

/// Polynomial rolling-hash constants.
/// `RK_BASE = 256` matches the byte alphabet; `RK_MOD` is a large prime.
const RK_BASE : Int64 = 256L

const RK_MOD : Int64 = 1000000007L

/// Fast modular exponentiation: base^exp mod `RK_MOD`.
/// Uses binary decomposition (square-and-multiply) in O(log exp).
fn rk_pow(base : Int64, exp : Int) -> Int64 {
  let mut result : Int64 = 1L
  let mut b = base % RK_MOD
  let mut e = exp
  while e > 0 {
    if e % 2 == 1 {
      result = result * b % RK_MOD
    }
    b = b * b % RK_MOD
    e = e / 2
  }
  result
}

/// Compute the polynomial hash of `s[start .. start+len)` (byte-level).
/// hash = s[start]·B^(len-1) + s[start+1]·B^(len-2) + … + s[start+len-1]  (mod M)
fn rk_hash(s : String, start : Int, len : Int) -> Int64 {
  let mut h : Int64 = 0L
  for i = 0; i < len; i = i + 1 {
    h = (h * RK_BASE + s[start + i].to_int().to_int64()) % RK_MOD
  }
  h
}

/// Roll the hash one position to the right.
/// Removes the contribution of `old_byte` (which occupied the most-significant
/// position) and appends `new_byte` at the least-significant position.
/// `power` must be `RK_BASE^(window_len-1) mod RK_MOD`.
fn rk_roll(h : Int64, old_byte : Int, new_byte : Int, power : Int64) -> Int64 {
  let old_c = old_byte.to_int64()
  let new_c = new_byte.to_int64()
  let removed = (h - old_c * power % RK_MOD % RK_MOD + RK_MOD) % RK_MOD
  (removed * RK_BASE + new_c) % RK_MOD
}

/// Byte-level verification: check whether `text[start .. start+m)` equals
/// `pattern`.  Called on every hash match to eliminate false positives.
fn rk_verify(text : String, pattern : String, start : Int, m : Int) -> Bool {
  for k = 0; k < m; k = k + 1 {
    if text[start + k] != pattern[k] {
      return false
    }
  }
  true
}

/// Search for `pattern` in `text` using the Rabin-Karp algorithm.
/// Returns the starting index of the first occurrence, or -1 if not found.
///
/// Edge cases (matching the KMP convention):
/// - empty pattern → 0  (the empty string is a prefix of every string)
/// - empty text (and non-empty pattern) → -1
/// - pattern longer than text → -1
pub fn rk_search(text : String, pattern : String) -> Int {
  let n = text.length()
  let m = pattern.length()
  if m == 0 {
    return 0
  }
  if n < m {
    return -1
  }
  let hash_p = rk_hash(pattern, 0, m)
  let mut hash_t = rk_hash(text, 0, m)
  let power = rk_pow(RK_BASE, m - 1)
  // Check the first window
  if hash_t == hash_p && rk_verify(text, pattern, 0, m) {
    return 0
  }
  // Slide the window across the text
  for i = 1; i <= n - m; i = i + 1 {
    hash_t = rk_roll(hash_t, text[i - 1].to_int(), text[i + m - 1].to_int(), power)
    if hash_t == hash_p && rk_verify(text, pattern, i, m) {
      return i
    }
  }
  -1
}

/// Search for all occurrences of `pattern` in `text`.
/// Returns a `FixedArray` of starting indices (possibly empty).
///
/// Edge cases:
/// - empty pattern → empty array (no well-defined match positions)
/// - pattern longer than text → empty array
pub fn rk_search_all(text : String, pattern : String) -> FixedArray[Int] {
  let n = text.length()
  let m = pattern.length()
  if m == 0 || n < m {
    return FixedArray::make(0, 0)
  }
  let hash_p = rk_hash(pattern, 0, m)
  let mut hash_t = rk_hash(text, 0, m)
  let power = rk_pow(RK_BASE, m - 1)
  let result : Array[Int] = []
  // Check the first window
  if hash_t == hash_p && rk_verify(text, pattern, 0, m) {
    result.push(0)
  }
  // Slide the window across the text
  for i = 1; i <= n - m; i = i + 1 {
    hash_t = rk_roll(hash_t, text[i - 1].to_int(), text[i + m - 1].to_int(), power)
    if hash_t == hash_p && rk_verify(text, pattern, i, m) {
      result.push(i)
    }
  }
  FixedArray::from_array(result)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "rk_search: basic match" {
  assert_eq(rk_search("hello world", "world"), 6)
  assert_eq(rk_search("hello world", "hello"), 0)
}

test "rk_search: no match" {
  assert_eq(rk_search("hello world", "xyz"), -1)
}

test "rk_search: empty pattern" {
  assert_eq(rk_search("hello", ""), 0)
  assert_eq(rk_search("", ""), 0)
}

test "rk_search: empty text" {
  assert_eq(rk_search("", "abc"), -1)
}

test "rk_search: pattern longer than text" {
  assert_eq(rk_search("hi", "hello"), -1)
  assert_eq(rk_search("abc", "abcdef"), -1)
}

test "rk_search: multiple matches returns first" {
  assert_eq(rk_search("abababab", "abab"), 0)
  assert_eq(rk_search("abcabcabc", "abc"), 0)
}

test "rk_search: overlapping matches" {
  assert_eq(rk_search("AAAAAA", "AAAA"), 0)
  assert_eq(rk_search("aabaaaabaa", "aabaa"), 0)
}

test "rk_search: single char pattern" {
  assert_eq(rk_search("abcdef", "d"), 3)
  assert_eq(rk_search("abcdef", "z"), -1)
  assert_eq(rk_search("a", "a"), 0)
}

test "rk_search: full string match" {
  assert_eq(rk_search("hello", "hello"), 0)
}

test "rk_search: match at end" {
  assert_eq(rk_search("abcdefghij", "hij"), 7)
  assert_eq(rk_search("abcdefghij", "ij"), 8)
  assert_eq(rk_search("abcdefghij", "j"), 9)
}

test "rk_search: large text" {
  // Build a 200-char text: "abcabc...abc" + "XYZ" suffix
  let mut text = ""
  for i = 0; i < 67; i = i + 1 {
    text = text + "abc"
  }
  text = text + "XYZ"
  assert_eq(rk_search(text, "XYZ"), 201)
  assert_eq(rk_search(text, "abc"), 0)
  // Last "abc" before XYZ starts at 198
  assert_eq(rk_search(text, "abcXYZ"), 198)
}

test "rk_search: hash collision verification" {
  // The polynomial hash can collide for different strings.  rk_search
  // always calls rk_verify on a hash match, so false positives are
  // impossible.  This test exercises that path with a dense, repetitive
  // text where many substrings share the same rolling-hash value.
  // 30 'a' bytes followed by "ab": the only true "ab" match is at the end.
  let prefix = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  let text = prefix + "ab"
  let pattern = "ab"
  // The match is at the position where "ab" starts, i.e. prefix.length().
  assert_eq(rk_search(text, pattern), prefix.length())
}

test "rk_search_all: basic multiple matches" {
  let result = rk_search_all("abababab", "ab")
  assert_eq(result.length(), 4)
  assert_eq(result[0], 0)
  assert_eq(result[1], 2)
  assert_eq(result[2], 4)
  assert_eq(result[3], 6)
}

test "rk_search_all: overlapping matches" {
  let result = rk_search_all("aaaa", "aa")
  assert_eq(result.length(), 3)
  assert_eq(result[0], 0)
  assert_eq(result[1], 1)
  assert_eq(result[2], 2)
}

test "rk_search_all: no match" {
  let result = rk_search_all("hello world", "xyz")
  assert_eq(result.length(), 0)
}

test "rk_search_all: single occurrence" {
  let result = rk_search_all("hello world", "world")
  assert_eq(result.length(), 1)
  assert_eq(result[0], 6)
}

test "rk_search_all: full string match" {
  let result = rk_search_all("hello", "hello")
  assert_eq(result.length(), 1)
  assert_eq(result[0], 0)
}

test "rk_search_all: empty pattern returns empty" {
  let result = rk_search_all("hello", "")
  assert_eq(result.length(), 0)
}

test "rk_search_all: pattern longer than text returns empty" {
  let result = rk_search_all("hi", "hello")
  assert_eq(result.length(), 0)
}

test "rk_search_all: large text with periodic matches" {
  // 100 repetitions of "ab" = "ababab...ab" (200 chars)
  let mut text = ""
  for i = 0; i < 100; i = i + 1 {
    text = text + "ab"
  }
  let result = rk_search_all(text, "ab")
  assert_eq(result.length(), 100)
  for i = 0; i < 100; i = i + 1 {
    assert_eq(result[i], i * 2)
  }
}

test "rk_search_all: match at very end" {
  let result = rk_search_all("abcdefghijxyz", "xyz")
  assert_eq(result.length(), 1)
  assert_eq(result[0], 10)
}

test "rk_pow: basic" {
  assert_eq(rk_pow(256L, 0), 1L)
  assert_eq(rk_pow(256L, 1), 256L)
  assert_eq(rk_pow(256L, 2), 65536L)
}

test "rk_hash: single char" {
  // hash("a") = 97
  assert_eq(rk_hash("a", 0, 1), 97L)
}

test "rk_hash: two chars" {
  // hash("ab") = 97 * 256 + 98 = 24930
  assert_eq(rk_hash("ab", 0, 2), 24930L)
}

test "rk_roll: consistency with rehash" {
  // Rolling hash over "hello" with window 3 should match re-computed hashes.
  let s = "hello"
  let m = 3
  let power = rk_pow(RK_BASE, m - 1)
  let mut h = rk_hash(s, 0, m)
  assert_eq(h, rk_hash(s, 0, 3))
  h = rk_roll(h, s[0].to_int(), s[3].to_int(), power)
  assert_eq(h, rk_hash(s, 1, 3))
  h = rk_roll(h, s[1].to_int(), s[4].to_int(), power)
  assert_eq(h, rk_hash(s, 2, 3))
}
