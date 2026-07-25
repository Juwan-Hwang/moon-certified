/// Suffix Balanced Tree (后缀平衡树)
///
/// An **offline** data structure that maintains all suffixes of a fixed string
/// in lexicographic order. Supports queries for suffix rank, k-th suffix,
/// pattern occurrence, and distinct substring count.
///
/// ## Important: Offline vs Online
///
/// This is an **offline** data structure — the entire string must be provided
/// upfront via `from_array`. This is because appending a character to a string
/// can **change the relative order of existing suffixes**. For example, in
/// "aba", suffix(2)="a" < suffix(0)="aba". But after appending 'c' to get
/// "abac", suffix(2)="ac" > suffix(0)="abac". Therefore, incremental insertion
/// into a sorted array is incorrect for a growing string.
///
/// For **online** (growing string) suffix queries, use the `suffix_automaton`
/// package instead, which supports O(n) online construction.
///
/// ## Algorithm
///
/// The string is provided as an array of code points. All suffix positions
/// are sorted using MoonBit's built-in `Array::sort` with a comparator function
/// that compares suffixes character by character. This gives O(n² log n)
/// construction (n log n comparisons, each O(n) worst case).
///
/// ## Complexity
/// - `from_array(text)`: O(n² log n) — one-time sort
/// - `kth_suffix(k)`: O(1)
/// - `rank_of(pos)`: O(n log n) — binary search with O(n) comparison
/// - `suffix_count()`: O(1)
/// - `pattern_count(pattern)`: O(|pattern| × log n + n log n)
/// - `count_distinct_substrings()`: O(n²) — traverse sorted suffixes + LCP
///
/// ## Stack safety
/// All operations are fully iterative — no recursion, no stack overflow risk.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

/// A suffix balanced tree maintaining all suffixes of a fixed string.
///
/// Characters are stored as `Int` code points. The string is provided upfront
/// via `from_array`.
pub struct SuffixBalancedTree {
  priv text : Array[Int] // the string (code points)
  priv sorted : Array[Int] // suffix positions in lexicographic order
}

/// Build a suffix balanced tree from an array of code points.
///
/// This is an O(n² log n) operation that sorts all suffixes once.
/// After construction, all queries are efficient.
pub fn SuffixBalancedTree::from_array(text : Array[Int]) -> SuffixBalancedTree {
  let n = text.length()
  let sorted = Array::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    sorted[i] = i
  }
  // Sort suffix positions lexicographically.
  // We use a simple insertion sort to avoid issues with closure-based comparators.
  // For production use on large strings, prefer the `suffix_array` package
  // which uses O(n log n) construction.
  for i = 1; i < n; i = i + 1 {
    let key = sorted[i]
    let mut j = i - 1
    // Shift elements that are > suffix(key) to the right.
    while j >= 0 {
      if compare_suffixes_array(text, sorted[j], key) > 0 {
        sorted[j + 1] = sorted[j]
        j = j - 1
      } else {
        break
      }
    }
    sorted[j + 1] = key
  }
  { text, sorted }
}

/// Compare two suffixes of `text` lexicographically.
///
/// Returns negative if suffix at `i` < suffix at `j`, positive if >, 0 if equal.
fn compare_suffixes_array(text : Array[Int], i : Int, j : Int) -> Int {
  let n = text.length()
  let mut k = 0
  while i + k < n && j + k < n {
    let ci = text[i + k]
    let cj = text[j + k]
    if ci != cj {
      return ci - cj
    }
    k = k + 1
  }
  if i + k >= n && j + k >= n {
    return 0
  }
  if i + k >= n {
    return -1 // suffix i is shorter -> smaller
  }
  return 1 // suffix j is shorter -> smaller
}

/// Number of characters (and suffixes) in the tree.
pub fn SuffixBalancedTree::length(self : SuffixBalancedTree) -> Int {
  self.text.length()
}

/// Compare two suffixes lexicographically by direct character-by-character
/// comparison.
fn SuffixBalancedTree::compare_suffixes(
  self : SuffixBalancedTree,
  i : Int,
  j : Int,
) -> Int {
  compare_suffixes_array(self.text, i, j)
}

/// Compute LCP (longest common prefix) between suffixes at positions i and j.
fn SuffixBalancedTree::lcp(
  self : SuffixBalancedTree,
  i : Int,
  j : Int,
) -> Int {
  let n = self.text.length()
  let mut k = 0
  while i + k < n && j + k < n && self.text[i + k] == self.text[j + k] {
    k = k + 1
  }
  k
}

/// Return the starting position of the k-th lexicographically smallest suffix.
///
/// k is 0-based. Returns -1 if k is out of range.
pub fn SuffixBalancedTree::kth_suffix(
  self : SuffixBalancedTree,
  k : Int,
) -> Int {
  if k < 0 || k >= self.sorted.length() {
    return -1
  }
  self.sorted[k]
}

/// Return the rank (0-based) of the suffix at position `pos`.
///
/// Returns -1 if `pos` is out of range.
pub fn SuffixBalancedTree::rank_of(
  self : SuffixBalancedTree,
  pos : Int,
) -> Int {
  let n = self.text.length()
  if pos < 0 || pos >= n {
    return -1
  }
  // Binary search for pos in the sorted array.
  let mut left = 0
  let mut right = self.sorted.length()
  while left < right {
    let mid = (left + right) / 2
    let cmp = self.compare_suffixes(self.sorted[mid], pos)
    if cmp < 0 {
      left = mid + 1
    } else if cmp > 0 {
      right = mid
    } else {
      // Found the suffix.
      return mid
    }
  }
  -1 // not found (shouldn't happen for valid pos)
}

/// Count the number of distinct substrings.
///
/// Computed on demand using the formula:
///   D = n*(n+1)/2 - sum of LCPs between adjacent suffixes in sorted order.
pub fn SuffixBalancedTree::count_distinct_substrings(
  self : SuffixBalancedTree,
) -> Int64 {
  let n = self.text.length()
  if n == 0 {
    return 0L
  }
  if n == 1 {
    return 1L
  }
  let total_substrings = n.to_int64() * (n.to_int64() + 1L) / 2L
  let mut sum_lcp = 0L
  for k = 1; k < n; k = k + 1 {
    let l = self.lcp(self.sorted[k - 1], self.sorted[k])
    sum_lcp = sum_lcp + l.to_int64()
  }
  total_substrings - sum_lcp
}

/// Compare a pattern (as an array of code points) with the suffix at `pos`.
///
/// Returns negative if pattern < suffix, 0 if pattern is a prefix of suffix,
/// positive if pattern > suffix.
fn SuffixBalancedTree::compare_pattern_with_suffix(
  self : SuffixBalancedTree,
  pattern : Array[Int],
  pos : Int,
) -> Int {
  let n = self.text.length()
  for k = 0; k < pattern.length(); k = k + 1 {
    if pos + k >= n {
      return 1 // suffix is shorter -> pattern > suffix
    }
    let diff = pattern[k] - self.text[pos + k]
    if diff != 0 {
      return diff
    }
  }
  0 // pattern is a prefix of suffix
}

/// Count the number of suffixes that start with the given pattern.
///
/// `pattern` is an array of code points. Returns 0 if pattern is empty or
/// no suffix starts with it.
pub fn SuffixBalancedTree::pattern_count(
  self : SuffixBalancedTree,
  pattern : Array[Int],
) -> Int {
  if pattern.length() == 0 || self.sorted.length() == 0 {
    return 0
  }
  let hi = self.sorted.length()
  // Find lower bound: first suffix >= pattern (as a prefix).
  let mut left = 0
  let mut right = hi
  while left < right {
    let mid = (left + right) / 2
    let pos = self.sorted[mid]
    let cmp = self.compare_pattern_with_suffix(pattern, pos)
    if cmp <= 0 {
      right = mid
    } else {
      left = mid + 1
    }
  }
  let lower = left
  // Find upper bound: first suffix > pattern (prefix comparison).
  left = lower
  right = hi
  while left < right {
    let mid = (left + right) / 2
    let pos = self.sorted[mid]
    let cmp = self.compare_pattern_with_suffix(pattern, pos)
    if cmp < 0 {
      right = mid
    } else {
      left = mid + 1
    }
  }
  let upper = left
  upper - lower
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "suffix_balanced_tree: empty tree" {
  let tree = SuffixBalancedTree::from_array([])
  assert_eq(tree.length(), 0)
  assert_eq(tree.kth_suffix(0), -1)
  assert_eq(tree.rank_of(0), -1)
  assert_eq(tree.count_distinct_substrings(), 0L)
}

test "suffix_balanced_tree: single character" {
  let tree = SuffixBalancedTree::from_array([97]) // 'a'
  assert_eq(tree.length(), 1)
  assert_eq(tree.kth_suffix(0), 0)
  assert_eq(tree.rank_of(0), 0)
  assert_eq(tree.count_distinct_substrings(), 1L)
}

test "suffix_balanced_tree: sorted suffixes" {
  // String "abc": suffixes "abc"(0), "bc"(1), "c"(2)
  // Sorted: "abc" < "bc" < "c"
  let tree = SuffixBalancedTree::from_array([97, 98, 99])
  assert_eq(tree.length(), 3)
  assert_eq(tree.kth_suffix(0), 0) // "abc"
  assert_eq(tree.kth_suffix(1), 1) // "bc"
  assert_eq(tree.kth_suffix(2), 2) // "c"
  assert_eq(tree.rank_of(0), 0)
  assert_eq(tree.rank_of(1), 1)
  assert_eq(tree.rank_of(2), 2)
}

test "suffix_balanced_tree: reverse sorted" {
  // String "cba": suffixes "cba"(0), "ba"(1), "a"(2)
  // Sorted: "a"(2) < "ba"(1) < "cba"(0)
  let tree = SuffixBalancedTree::from_array([99, 98, 97])
  assert_eq(tree.length(), 3)
  assert_eq(tree.kth_suffix(0), 2) // "a"
  assert_eq(tree.kth_suffix(1), 1) // "ba"
  assert_eq(tree.kth_suffix(2), 0) // "cba"
}

test "suffix_balanced_tree: repeated characters" {
  // String "aaa": suffixes "aaa"(0), "aa"(1), "a"(2)
  // Sorted: "a"(2) < "aa"(1) < "aaa"(0)
  let tree = SuffixBalancedTree::from_array([97, 97, 97])
  assert_eq(tree.length(), 3)
  assert_eq(tree.kth_suffix(0), 2) // "a"
  assert_eq(tree.kth_suffix(1), 1) // "aa"
  assert_eq(tree.kth_suffix(2), 0) // "aaa"
  assert_eq(tree.count_distinct_substrings(), 3L)
}

test "suffix_balanced_tree: banana" {
  // String "banana": suffixes
  // 0: banana, 1: anana, 2: nana, 3: ana, 4: na, 5: a
  // Sorted: a(5) < ana(3) < anana(1) < banana(0) < na(4) < nana(2)
  let tree = SuffixBalancedTree::from_array([98, 97, 110, 97, 110, 97])
  assert_eq(tree.length(), 6)
  assert_eq(tree.kth_suffix(0), 5) // "a"
  assert_eq(tree.kth_suffix(1), 3) // "ana"
  assert_eq(tree.kth_suffix(2), 1) // "anana"
  assert_eq(tree.kth_suffix(3), 0) // "banana"
  assert_eq(tree.kth_suffix(4), 4) // "na"
  assert_eq(tree.kth_suffix(5), 2) // "nana"
  // Distinct substrings of "banana": 15
  assert_eq(tree.count_distinct_substrings(), 15L)
}

test "suffix_balanced_tree: distinct substrings" {
  // String "abab": suffixes
  // 0: abab, 1: bab, 2: ab, 3: b
  // Sorted: ab(2) < abab(0) < b(3) < bab(1)
  let tree = SuffixBalancedTree::from_array([97, 98, 97, 98])
  assert_eq(tree.length(), 4)
  assert_eq(tree.kth_suffix(0), 2) // "ab"
  assert_eq(tree.kth_suffix(1), 0) // "abab"
  assert_eq(tree.kth_suffix(2), 3) // "b"
  assert_eq(tree.kth_suffix(3), 1) // "bab"
  // Distinct substrings: a, ab, aba, abab, b, ba, bab = 7
  assert_eq(tree.count_distinct_substrings(), 7L)
}

test "suffix_balanced_tree: pattern count" {
  // String "ababab": suffixes
  // 0: ababab, 1: babab, 2: abab, 3: bab, 4: ab, 5: b
  // Sorted: ab(4) < abab(2) < ababab(0) < b(5) < bab(3) < babab(1)
  let tree = SuffixBalancedTree::from_array([97, 98, 97, 98, 97, 98])
  // Pattern "ab": suffixes starting with "ab" are at positions 0, 2, 4 → 3
  assert_eq(tree.pattern_count([97, 98]), 3)
  // Pattern "bab": positions 1, 3 → 2
  assert_eq(tree.pattern_count([98, 97, 98]), 2)
  // Pattern "abc": 0
  assert_eq(tree.pattern_count([97, 98, 99]), 0)
  // Pattern "ababab": position 0 → 1
  assert_eq(tree.pattern_count([97, 98, 97, 98, 97, 98]), 1)
}

test "suffix_balanced_tree: abcabcab" {
  // String "abcabcab"
  let tree = SuffixBalancedTree::from_array([
    97, 98, 99, 97, 98, 99, 97, 98,
  ])
  let n = tree.length()
  assert_eq(n, 8)
  // Sorted suffixes:
  // 6: ab, 3: abcab, 0: abcabcab, 7: b, 4: bcab, 1: bcabcab,
  // 5: cab, 2: cabcab
  assert_eq(tree.kth_suffix(0), 6) // "ab"
  assert_eq(tree.kth_suffix(1), 3) // "abcab"
  assert_eq(tree.kth_suffix(2), 0) // "abcabcab"
  assert_eq(tree.kth_suffix(3), 7) // "b"
  assert_eq(tree.kth_suffix(4), 4) // "bcab"
  assert_eq(tree.kth_suffix(5), 1) // "bcabcab"
  assert_eq(tree.kth_suffix(6), 5) // "cab"
  assert_eq(tree.kth_suffix(7), 2) // "cabcab"
}

test "suffix_balanced_tree: random stress test 50" {
  // Build a 50-character random string and verify suffix order
  let chars : Array[Int] = []
  let mut seed = 42
  for i = 0; i < 50; i = i + 1 {
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
    let c = seed % 26 + 97
    chars.push(c)
  }
  let tree = SuffixBalancedTree::from_array(chars)
  let n = tree.length()
  // Verify all suffixes are present (permutation check).
  let seen = FixedArray::make(n, false)
  for k = 0; k < n; k = k + 1 {
    let pos = tree.kth_suffix(k)
    assert_true(pos >= 0 && pos < n)
    assert_false(seen[pos])
    seen[pos] = true
  }
  // Verify the suffix order is correct (each suffix < next).
  for k = 0; k < n - 1; k = k + 1 {
    let p1 = tree.kth_suffix(k)
    let p2 = tree.kth_suffix(k + 1)
    let mut ok = false
    let mut i = 0
    while p1 + i < n && p2 + i < n {
      let c1 = chars[p1 + i]
      let c2 = chars[p2 + i]
      if c1 < c2 {
        ok = true
        break
      }
      if c1 > c2 {
        abort("order violation k=\{k}: p1=\{p1} p2=\{p2} offset=\{i}")
      }
      i = i + 1
    }
    if !ok {
      // p1 must be a prefix of p2 (p1 shorter, so p1 < p2)
      assert_true(p1 + i >= n)
    }
  }
}

test "suffix_balanced_tree: stress 100 chars" {
  let chars : Array[Int] = []
  let mut seed = 12345
  for i = 0; i < 100; i = i + 1 {
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
    let c = seed % 26 + 97
    chars.push(c)
  }
  let tree = SuffixBalancedTree::from_array(chars)
  let n = tree.length()
  assert_eq(n, 100)
  // Verify permutation.
  let seen = FixedArray::make(n, false)
  for k = 0; k < n; k = k + 1 {
    let pos = tree.kth_suffix(k)
    assert_true(pos >= 0 && pos < n)
    assert_false(seen[pos])
    seen[pos] = true
  }
  // Verify sorted order.
  for k = 0; k < n - 1; k = k + 1 {
    let p1 = tree.kth_suffix(k)
    let p2 = tree.kth_suffix(k + 1)
    let mut i = 0
    let mut verified = false
    while p1 + i < n && p2 + i < n {
      let c1 = chars[p1 + i]
      let c2 = chars[p2 + i]
      if c1 < c2 {
        verified = true
        break
      }
      if c1 > c2 {
        abort("100-char order violation at k=\{k}: p1=\{p1} p2=\{p2} offset=\{i}")
      }
      i = i + 1
    }
    if !verified {
      assert_true(p1 + i >= n)
    }
  }
}

test "suffix_balanced_tree: stress 200 chars" {
  let chars : Array[Int] = []
  let mut seed = 999
  for i = 0; i < 200; i = i + 1 {
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
    let c = seed % 26 + 97
    chars.push(c)
  }
  let tree = SuffixBalancedTree::from_array(chars)
  let n = tree.length()
  assert_eq(n, 200)
  let seen = FixedArray::make(n, false)
  for k = 0; k < n; k = k + 1 {
    let pos = tree.kth_suffix(k)
    assert_true(pos >= 0 && pos < n)
    assert_false(seen[pos])
    seen[pos] = true
  }
  for k = 0; k < n - 1; k = k + 1 {
    let p1 = tree.kth_suffix(k)
    let p2 = tree.kth_suffix(k + 1)
    let mut i = 0
    let mut verified = false
    while p1 + i < n && p2 + i < n {
      let c1 = chars[p1 + i]
      let c2 = chars[p2 + i]
      if c1 < c2 {
        verified = true
        break
      }
      if c1 > c2 {
        abort("200-char order violation at k=\{k}: p1=\{p1} p2=\{p2} offset=\{i}")
      }
      i = i + 1
    }
    if !verified {
      assert_true(p1 + i >= n)
    }
  }
}

test "suffix_balanced_tree: rank_of consistency" {
  // rank_of(kth_suffix(k)) == k for all k
  let chars : Array[Int] = []
  let mut seed = 7777
  for i = 0; i < 30; i = i + 1 {
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
    let c = seed % 26 + 97
    chars.push(c)
  }
  let tree = SuffixBalancedTree::from_array(chars)
  let n = tree.length()
  for k = 0; k < n; k = k + 1 {
    let pos = tree.kth_suffix(k)
    let rank = tree.rank_of(pos)
    assert_eq(rank, k)
  }
}

test "suffix_balanced_tree: distinct substrings ababa" {
  // String "ababa": suffixes
  // 0: ababa, 1: baba, 2: aba, 3: ba, 4: a
  // Sorted: a(4) < aba(2) < ababa(0) < ba(3) < baba(1)
  let tree = SuffixBalancedTree::from_array([97, 98, 97, 98, 97])
  assert_eq(tree.kth_suffix(0), 4) // "a"
  assert_eq(tree.kth_suffix(1), 2) // "aba"
  assert_eq(tree.kth_suffix(2), 0) // "ababa"
  assert_eq(tree.kth_suffix(3), 3) // "ba"
  assert_eq(tree.kth_suffix(4), 1) // "baba"
  // Distinct substrings of "ababa":
  // a, ab, aba, abab, ababa, b, ba, bab, baba = 9
  assert_eq(tree.count_distinct_substrings(), 9L)
}

test "suffix_balanced_tree: distinct substrings abac" {
  // String "abac": suffixes
  // 0: abac, 1: bac, 2: ac, 3: c
  // Sorted: abac(0) < ac(2) < bac(1) < c(3)
  let tree = SuffixBalancedTree::from_array([97, 98, 97, 99])
  assert_eq(tree.kth_suffix(0), 0) // "abac"
  assert_eq(tree.kth_suffix(1), 2) // "ac"
  assert_eq(tree.kth_suffix(2), 1) // "bac"
  assert_eq(tree.kth_suffix(3), 3) // "c"
  // Distinct substrings of "abac":
  // a, ab, aba, abac, ac, b, ba, bac, c = 9
  assert_eq(tree.count_distinct_substrings(), 9L)
}
