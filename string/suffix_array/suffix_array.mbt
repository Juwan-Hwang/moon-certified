/// Suffix array construction using prefix doubling (Manber-Myers).
///
/// Builds the suffix array of a string in O(n log^2 n) time using a
/// comparison-based merge sort. The suffix array `sa` is a permutation of
/// [0, n) such that `s[sa[0]..] < s[sa[1]..] < ... < s[sa[n-1]..]`
/// lexicographically (byte-level comparison).
///
/// Algorithm:
/// 1. Initialise ranks to individual byte values.
/// 2. For k = 1, 2, 4, ...: sort suffixes by the rank pair
///    (rank[i], rank[i+k]), then recompute ranks from the sorted order.
/// 3. Stop when all suffixes have distinct ranks (max rank == n - 1).
///
/// IMPORTANT: MoonBit's String indexing is byte-level, not Unicode codepoint.
/// For multi-byte UTF-8 strings, suffixes are compared at the byte level.
///
/// Not formally verified (String operations not supported by moon prove).
/// Correctness ensured by comprehensive tests.

/// Stable merge sort of `arr[lo, hi)` (an array of integers) by comparator.
/// Uses `tmp` as scratch space. Sorts in place.
fn msort_int(
  arr : FixedArray[Int],
  tmp : FixedArray[Int],
  lo : Int,
  hi : Int,
  cmp : (Int, Int) -> Int,
) -> Unit {
  let len = hi - lo
  if len <= 1 {
    return
  }
  let mid = lo + len / 2
  msort_int(arr, tmp, lo, mid, cmp)
  msort_int(arr, tmp, mid, hi, cmp)
  let mut i = lo
  let mut j = mid
  for k = lo; k < hi; k = k + 1 {
    if j >= hi || (i < mid && cmp(arr[i], arr[j]) <= 0) {
      tmp[k] = arr[i]
      i = i + 1
    } else {
      tmp[k] = arr[j]
      j = j + 1
    }
  }
  for k = lo; k < hi; k = k + 1 {
    arr[k] = tmp[k]
  }
}

/// Build the suffix array of `s`.
/// Returns a `FixedArray[Int]` of sorted suffix start indices.
pub fn build(s : String) -> FixedArray[Int] {
  let n = s.length()
  if n == 0 {
    return FixedArray::make(0, 0)
  }
  if n == 1 {
    return FixedArray::make(1, 0)
  }
  // sa[i] = i-th smallest suffix start index.
  let sa = FixedArray::makei(n, fn(i) { i })
  // rank[i] = current rank of the suffix starting at position i.
  let rank = FixedArray::makei(n, fn(i) { s[i].to_int() })
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

/// Compare `pattern` with the suffix of `s` starting at `pos`.
/// Returns < 0 if the suffix is lexicographically smaller than `pattern`,
/// 0 if the suffix starts with `pattern`, > 0 if the suffix is greater.
fn compare_suffix_pattern(s : String, pos : Int, pattern : String) -> Int {
  let n = s.length()
  let m = pattern.length()
  for i = 0; i < m; i = i + 1 {
    if pos + i >= n {
      // Suffix exhausted before pattern: suffix < pattern.
      return -1
    }
    let sc = s[pos + i].to_int()
    let pc = pattern[i].to_int()
    if sc != pc {
      return sc - pc
    }
  }
  // All of pattern matched: suffix starts with pattern.
  0
}

/// Binary search for `pattern` in the suffix array of `s`.
///
/// Returns `Some(pos)` where `pos` is the starting index in `s` of the
/// lexicographically smallest suffix that begins with `pattern`, or `None`
/// if no suffix starts with `pattern`.
pub fn search(
  sa : FixedArray[Int],
  s : String,
  pattern : String,
) -> Int? {
  let n = s.length()
  let m = pattern.length()
  if m == 0 {
    return None
  }
  // Binary search for the leftmost suffix >= pattern.
  let mut lo = 0
  let mut hi = n
  while lo < hi {
    let mid = (lo + hi) / 2
    let cmp = compare_suffix_pattern(s, sa[mid], pattern)
    if cmp < 0 {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  // Check whether the found suffix actually starts with pattern.
  if lo < n {
    if compare_suffix_pattern(s, sa[lo], pattern) == 0 {
      return Some(sa[lo])
    }
  }
  None
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

/// Compare two suffixes of `s` starting at `a` and `b` lexicographically.
/// Returns < 0, 0, or > 0.
fn compare_suffixes(s : String, a : Int, b : Int) -> Int {
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
    -1  // a is shorter, so a < b
  } else {
    1   // b is shorter, so a > b
  }
}

/// Check that the suffix array produces lexicographically sorted suffixes.
fn is_sorted_suffixes(sa : FixedArray[Int], s : String) -> Bool {
  let n = sa.length()
  if n <= 1 {
    return true
  }
  for i = 0; i < n - 1; i = i + 1 {
    if compare_suffixes(s, sa[i], sa[i + 1]) >= 0 {
      return false
    }
  }
  true
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

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

test "build: empty string" {
  let sa = build("")
  assert_eq(sa.length(), 0)
}

test "build: single char" {
  let sa = build("a")
  assert_eq(sa.length(), 1)
  assert_eq(sa[0], 0)
  assert_true(is_sorted_suffixes(sa, "a"))
}

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

test "search: pattern found" {
  let sa = build("banana")
  // "ana" occurs at positions 1 and 3 in "banana".
  let result = search(sa, "banana", "ana")
  assert_true(result is Some(_))
  let pos = result.unwrap()
  // The lexicographically smallest matching suffix is "ana" at position 3.
  assert_eq(pos, 3)
}

test "search: pattern not found" {
  let sa = build("banana")
  assert_true(search(sa, "banana", "xyz") is None)
  assert_true(search(sa, "banana", "bananas") is None)
}

test "build: large string 100 chars" {
  // Build a 100-character string with a repeating pattern.
  let mut s = ""
  for i = 0; i < 50; i = i + 1 {
    s = s + "ab"
  }
  // s = "ababab...ab" (100 chars)
  assert_eq(s.length(), 100)
  let sa = build(s)
  assert_eq(sa.length(), 100)
  assert_true(is_sorted_suffixes(sa, s))
  // Verify: suffixes starting with 'a' (even indices) come before those
  // starting with 'b' (odd indices).
  for i = 0; i < 50; i = i + 1 {
    assert_eq(sa[i] % 2, 0)  // even index starts with 'a'
  }
  for i = 50; i < 100; i = i + 1 {
    assert_eq(sa[i] % 2, 1)  // odd index starts with 'b'
  }
}

test "build: verify sorted suffixes for various strings" {
  let strings = ["mississippi", "abracadabra", "abababab", "abcdefgh", "hgfedcba"]
  for i = 0; i < strings.length(); i = i + 1 {
    let s = strings[i]
    let sa = build(s)
    assert_true(is_sorted_suffixes(sa, s))
  }
}

test "search: full string match" {
  let sa = build("banana")
  assert_eq(search(sa, "banana", "banana"), Some(0))
}

test "search: single char pattern" {
  let sa = build("banana")
  // "a" occurs at positions 1, 3, 5. Lex smallest suffix starting with "a"
  // is "a" at position 5.
  assert_eq(search(sa, "banana", "a"), Some(5))
  // "b" occurs at position 0.
  assert_eq(search(sa, "banana", "b"), Some(0))
}

test "search: empty pattern returns None" {
  let sa = build("banana")
  assert_true(search(sa, "banana", "") is None)
}

test "search: multiple matches returns valid position" {
  let s = "abababab"
  let sa = build(s)
  let result = search(sa, s, "ab")
  assert_true(result is Some(_))
  let pos = result.unwrap()
  // Verify the pattern actually occurs at the returned position.
  assert_eq(s[pos].to_int(), 97)  // 'a'
  assert_eq(s[pos + 1].to_int(), 98)  // 'b'
}

test "search: pattern at end of string" {
  let sa = build("abcdef")
  assert_eq(search(sa, "abcdef", "ef"), Some(4))
  assert_eq(search(sa, "abcdef", "f"), Some(5))
}

test "search: pattern longer than string" {
  let sa = build("abc")
  assert_true(search(sa, "abc", "abcd") is None)
}
