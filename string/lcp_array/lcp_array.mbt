/// LCP Array construction using Kasai's algorithm.
///
/// Given a string `s` and its suffix array `sa`, computes the Longest Common
/// Prefix (LCP) array: `lcp[i]` is the length of the longest common prefix
/// between the `i`-th and `(i-1)`-th suffixes in the sorted order.
///
/// Concretely, if `sa = [sa[0], sa[1], ..., sa[n-1]]` is the suffix array,
/// then `lcp[i]` (for `i >= 1`) is the LCP of `s[sa[i-1]..]` and `s[sa[i]..]`.
/// `lcp[0]` is conventionally set to 0 (no preceding suffix).
///
/// ## Algorithm (Kasai)
///
/// Kasai's algorithm processes suffixes in the **original order** (not the
/// sorted order), maintaining the key insight that if the LCP of the suffix
/// starting at position `i` with its predecessor in the sorted order is `h`,
/// then the LCP of the suffix starting at `i+1` is at least `h-1` (if `h > 0`).
///
/// This amortises to O(n) total character comparisons:
/// 1. Compute `rank[i]` = position of suffix `s[i..]` in the sorted order.
/// 2. For `i = 0, 1, ..., n-1`:
///    - If `rank[i] == 0`, skip (first in sorted order, no predecessor).
///    - Let `j = sa[rank[i] - 1]` (the predecessor of `s[i..]` in sorted order).
///    - Compare `s[i+h..]` with `s[j+h..]` to find the actual LCP, starting
///      from `h = max(0, h - 1)` where `h` is the previous LCP.
///    - Set `lcp[rank[i]] = h`.
///
/// ## Complexity
///
/// - Time: O(n) — Kasai's algorithm performs at most `2n` character
///   comparisons in total.
/// - Space: O(n) for the `rank` and `lcp` arrays.
///
/// ## Usage with suffix_array
///
/// This module is designed to be used with the `suffix_array` package:
///
/// ```moonbit
/// let sa = @suffix_array.build("banana")
/// let lcp = @lcp_array.build(sa, "banana")
/// ```
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

// ---------------------------------------------------------------------------
// LCP array construction
// ---------------------------------------------------------------------------

/// Build the LCP array from a suffix array and the original string.
///
/// # Parameters
/// - `sa`: the suffix array of `s`, as returned by `@suffix_array.build`.
///   `sa[i]` is the starting index of the `i`-th lexicographically smallest
///   suffix. Must be a permutation of `0..n-1` where `n = s.length()`.
/// - `s`: the original string.
///
/// # Returns
/// A `FixedArray[Int]` of length `n` where:
/// - `lcp[0] = 0` (convention: the first suffix has no predecessor).
/// - `lcp[i]` (for `i >= 1`) = length of the longest common prefix between
///   `s[sa[i-1]..]` and `s[sa[i]..]`.
///
/// Returns an empty array if `s` is empty or `sa` has the wrong length.
///
/// # Complexity
/// - Time: O(n) via Kasai's algorithm.
/// - Space: O(n) for the rank array.
pub fn build(sa : FixedArray[Int], s : String) -> FixedArray[Int] {
  let n = s.length()
  if n == 0 || sa.length() != n {
    return FixedArray::make(0, 0)
  }
  let lcp = FixedArray::make(n, 0)
  // rank[i] = position of suffix s[i..] in the sorted order.
  let rank = FixedArray::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    rank[sa[i]] = i
  }
  let mut h = 0
  // Process suffixes in original order (i = 0, 1, ..., n-1).
  for i = 0; i < n; i = i + 1 {
    if rank[i] == 0 {
      // First in sorted order: no predecessor, LCP is 0.
      h = 0
      continue
    }
    // j = starting index of the predecessor of s[i..] in sorted order.
    let j = sa[rank[i] - 1]
    // If we had a non-zero LCP from the previous iteration, reduce by 1
    // (Kasai's key insight: lcp[i+1] >= lcp[i] - 1).
    if h > 0 {
      h = h - 1
    }
    // Compare s[i+h..] with s[j+h..].
    while i + h < n && j + h < n {
      if s[i + h].to_int() == s[j + h].to_int() {
        h = h + 1
      } else {
        break
      }
    }
    lcp[rank[i]] = h
  }
  lcp
}

/// Compute the LCP of two suffixes of `s` starting at positions `a` and `b`.
///
/// This is a direct (non-amortised) comparison, used for verification and
/// testing. Runs in O(min(n-a, n-b)) time.
fn lcp_direct(s : String, a : Int, b : Int) -> Int {
  let n = s.length()
  let mut h = 0
  while a + h < n && b + h < n {
    if s[a + h].to_int() == s[b + h].to_int() {
      h = h + 1
    } else {
      break
    }
  }
  h
}

// ---------------------------------------------------------------------------
// Derived queries
// ---------------------------------------------------------------------------

/// Find the longest repeated substring in `s` using the LCP array.
///
/// Returns `Some((start, length))` where `s[start..start+length]` is the
/// longest substring that appears at least twice. Returns `None` if all
/// characters are unique (no repeated substring).
///
/// Uses the fact that the maximum `lcp[i]` gives the longest repeated
/// substring: the suffix `sa[i]` shares a prefix of length `lcp[i]` with
/// `sa[i-1]`, which is the longest repeated substring ending at that position.
///
/// # Complexity
/// - Time: O(n) — single pass over the LCP array.
/// - Space: O(1) — only tracks the maximum.
pub fn longest_repeated_substring(
  sa : FixedArray[Int],
  lcp : FixedArray[Int],
) -> (Int, Int)? {
  let n = sa.length()
  if n <= 1 {
    return None
  }
  let mut max_len = 0
  let mut best_start = -1
  for i = 1; i < n; i = i + 1 {
    if lcp[i] > max_len {
      max_len = lcp[i]
      best_start = sa[i]
    }
  }
  if max_len > 0 {
    Some((best_start, max_len))
  } else {
    None
  }
}

/// Count the number of distinct substrings of `s`.
///
/// The total number of substrings of a string of length `n` is `n*(n+1)/2`.
/// The number of **distinct** substrings is:
///
///     sum_{i=0}^{n-1} (n - sa[i]) - sum_{i=1}^{n-1} lcp[i]
///
/// because each suffix `sa[i]` contributes `n - sa[i]` new substrings,
/// but `lcp[i]` of them were already counted by `sa[i-1]`.
///
/// Returns `n*(n+1)/2` if `s` has all unique characters (no repeats).
///
/// # Complexity
/// - Time: O(n) — single pass.
/// - Space: O(1) — just accumulates.
///
/// Uses `Int64` for the accumulation to prevent overflow for large `n`.
pub fn count_distinct_substrings(
  sa : FixedArray[Int],
  lcp : FixedArray[Int],
  n : Int,
) -> Int64 {
  if n <= 0 {
    return 0L
  }
  let mut total = 0L
  for i = 0; i < n; i = i + 1 {
    total = total + (n - sa[i]).to_int64()
  }
  for i = 1; i < n; i = i + 1 {
    total = total - lcp[i].to_int64()
  }
  total
}

/// Compare two suffixes of `s` lexicographically.
/// Returns < 0 if suffix at `a` is smaller, 0 if equal, > 0 if greater.
fn compare_suffix(s : String, a : Int, b : Int) -> Int {
  let n = s.length()
  let mut i = 0
  while a + i < n && b + i < n {
    let ca = s[a + i].to_int()
    let cb = s[b + i].to_int()
    if ca != cb {
      return ca - cb
    }
    i = i + 1
  }
  if a + i >= n && b + i >= n {
    0
  } else if a + i >= n {
    -1 // a is shorter
  } else {
    1 // b is shorter
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "lcp: banana" {
  // s = "banana", sa = [5, 3, 1, 0, 4, 2]
  // Suffixes sorted:
  //   5: "a"
  //   3: "ana"
  //   1: "anana"
  //   0: "banana"
  //   4: "na"
  //   2: "nana"
  // LCP: [0, 1, 3, 0, 0, 2]
  //   lcp[1] = LCP("a", "ana") = 1
  //   lcp[2] = LCP("ana", "anana") = 3
  //   lcp[3] = LCP("anana", "banana") = 0
  //   lcp[4] = LCP("banana", "na") = 0
  //   lcp[5] = LCP("na", "nana") = 2
  let sa = FixedArray::make(6, 0)
  sa[0] = 5
  sa[1] = 3
  sa[2] = 1
  sa[3] = 0
  sa[4] = 4
  sa[5] = 2
  let lcp = build(sa, "banana")
  assert_eq(lcp[0], 0)
  assert_eq(lcp[1], 1)
  assert_eq(lcp[2], 3)
  assert_eq(lcp[3], 0)
  assert_eq(lcp[4], 0)
  assert_eq(lcp[5], 2)
}

test "lcp: empty string" {
  let sa : FixedArray[Int] = FixedArray::make(0, 0)
  let lcp = build(sa, "")
  assert_eq(lcp.length(), 0)
}

test "lcp: single character" {
  let sa = FixedArray::make(1, 0)
  let lcp = build(sa, "a")
  assert_eq(lcp.length(), 1)
  assert_eq(lcp[0], 0)
}

test "lcp: all same characters" {
  // s = "aaaa", sa = [3, 2, 1, 0]
  // Suffixes sorted:
  //   3: "a"
  //   2: "aa"
  //   1: "aaa"
  //   0: "aaaa"
  // LCP: [0, 1, 2, 3]
  let sa = FixedArray::make(4, 0)
  sa[0] = 3
  sa[1] = 2
  sa[2] = 1
  sa[3] = 0
  let lcp = build(sa, "aaaa")
  assert_eq(lcp[0], 0)
  assert_eq(lcp[1], 1)
  assert_eq(lcp[2], 2)
  assert_eq(lcp[3], 3)
}

test "lcp: all unique characters" {
  // s = "abcde", sa = [0, 1, 2, 3, 4]
  // Every suffix starts with a different character, so all LCPs are 0.
  let sa = FixedArray::make(5, 0)
  sa[0] = 0
  sa[1] = 1
  sa[2] = 2
  sa[3] = 3
  sa[4] = 4
  let lcp = build(sa, "abcde")
  for i = 0; i < 5; i = i + 1 {
    assert_eq(lcp[i], 0)
  }
}

test "lcp: mismatched sa length returns empty" {
  let sa = FixedArray::make(3, 0) // wrong length
  let lcp = build(sa, "banana") // length 6
  assert_eq(lcp.length(), 0)
}

test "lcp: verify against brute force" {
  // Verify the LCP array matches a direct comparison for "mississippi".
  let s = "mississippi"
  let n = s.length()
  // Build a simple suffix array by sorting suffix indices.
  let indices : Array[Int] = []
  for i = 0; i < n; i = i + 1 {
    indices.push(i)
  }
  // Simple sort by suffix comparison.
  for i = 1; i < n; i = i + 1 {
    let key = indices[i]
    let mut j = i - 1
    while j >= 0 && compare_suffix(s, indices[j], key) > 0 {
      indices[j + 1] = indices[j]
      j = j - 1
    }
    indices[j + 1] = key
  }
  let sa = FixedArray::makei(n, fn(i) { indices[i] })
  let lcp = build(sa, s)
  // Verify each LCP against the brute-force computation.
  for i = 1; i < n; i = i + 1 {
    let expected = lcp_direct(s, sa[i - 1], sa[i])
    assert_eq(lcp[i], expected)
  }
}

test "lcp: longest repeated substring" {
  // s = "banana"
  // Longest repeated substring: "ana" (at positions 1 and 3)
  let sa = FixedArray::make(6, 0)
  sa[0] = 5
  sa[1] = 3
  sa[2] = 1
  sa[3] = 0
  sa[4] = 4
  sa[5] = 2
  let lcp = build(sa, "banana")
  let result = longest_repeated_substring(sa, lcp)
  match result {
    Some((start, length)) => {
      assert_eq(length, 3) // "ana" has length 3
      // The start should be 1 or 3 (both have "ana")
      let s = "banana"
      assert_eq(s[start].to_int(), 97) // 'a'
      assert_eq(s[start + 1].to_int(), 110) // 'n'
      assert_eq(s[start + 2].to_int(), 97) // 'a'
    }
    None => abort("should find a repeated substring")
  }
}

test "lcp: no repeated substring" {
  // s = "abcde" — all characters unique.
  let sa = FixedArray::make(5, 0)
  sa[0] = 0
  sa[1] = 1
  sa[2] = 2
  sa[3] = 3
  sa[4] = 4
  let lcp = build(sa, "abcde")
  let result = longest_repeated_substring(sa, lcp)
  assert_true(result is None)
}

test "lcp: count distinct substrings" {
  // s = "banana"
  // Total substrings: 6*7/2 = 21
  // Distinct substrings: "a", "an", "ana", "anan", "anana", "b", "ba",
  //   "ban", "bana", "banan", "banana", "n", "na", "nan", "nana"
  // That's 15 distinct substrings.
  let sa = FixedArray::make(6, 0)
  sa[0] = 5
  sa[1] = 3
  sa[2] = 1
  sa[3] = 0
  sa[4] = 4
  sa[5] = 2
  let lcp = build(sa, "banana")
  let count = count_distinct_substrings(sa, lcp, 6)
  assert_eq(count, 15L)
}

test "lcp: count distinct substrings — all unique" {
  // s = "abc" — all unique, so 3*4/2 = 6 distinct substrings.
  let sa = FixedArray::make(3, 0)
  sa[0] = 0
  sa[1] = 1
  sa[2] = 2
  let lcp = build(sa, "abc")
  let count = count_distinct_substrings(sa, lcp, 3)
  assert_eq(count, 6L) // 3*4/2 = 6
}

test "lcp: count distinct substrings — all same" {
  // s = "aaa" — distinct substrings are "a", "aa", "aaa" = 3.
  let sa = FixedArray::make(3, 0)
  sa[0] = 2
  sa[1] = 1
  sa[2] = 0
  let lcp = build(sa, "aaa")
  let count = count_distinct_substrings(sa, lcp, 3)
  assert_eq(count, 3L) // 6 - 3 = 3 (lcp = [0, 1, 2], sum = 3)
}

test "lcp: large string consistency" {
  // Verify LCP array on a 100-character string against brute force.
  let mut s = ""
  for i = 0; i < 50; i = i + 1 {
    s = s + "ab"
  }
  let n = s.length()
  // Build suffix array.
  let indices : Array[Int] = []
  for i = 0; i < n; i = i + 1 {
    indices.push(i)
  }
  for i = 1; i < n; i = i + 1 {
    let key = indices[i]
    let mut j = i - 1
    while j >= 0 && compare_suffix(s, indices[j], key) > 0 {
      indices[j + 1] = indices[j]
      j = j - 1
    }
    indices[j + 1] = key
  }
  let sa = FixedArray::makei(n, fn(i) { indices[i] })
  let lcp = build(sa, s)
  // Verify against brute force for all i.
  for i = 1; i < n; i = i + 1 {
    let expected = lcp_direct(s, sa[i - 1], sa[i])
    assert_eq(lcp[i], expected)
  }
}
