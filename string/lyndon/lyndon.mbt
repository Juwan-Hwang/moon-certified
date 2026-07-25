/// Lyndon factorization and minimum rotation.
///
/// A **Lyndon word** is a non-empty string that is strictly smaller than all
/// its non-trivial cyclic rotations. Equivalently, it is strictly smaller than
/// any of its proper suffixes.
///
/// Every string can be uniquely decomposed into a sequence of Lyndon words
/// `w1, w2, ..., wk` such that `w1 >= w2 >= ... >= wk` (non-increasing
/// lexicographic order). This is the **Lyndon factorization** (also known as
/// the Chen-Fox-Lyndon decomposition).
///
/// ## Algorithms
///
/// - **Duval's algorithm** computes the factorization in O(n) time and O(1)
///   extra space, streaming through the string with two pointers.
/// - **Minimum representation** finds the lexicographically smallest rotation
///   in O(n) time using a two-pointer comparison with cyclic indexing.
///
/// ## Complexity
///
/// - `lyndon_factorization`: O(n) time, O(k) space (k = number of factors)
/// - `min_rotation_index`: O(n) time, O(1) extra space
/// - `is_lyndon`: O(n^2) worst case, O(n) typical for Lyndon words
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Lyndon factorization (Duval's algorithm)
// ---------------------------------------------------------------------------

/// Decompose `s` into its Lyndon factors using Duval's algorithm.
///
/// Returns an array of `(start, length)` pairs. Each factor is a Lyndon word,
/// and the factors are in non-increasing lexicographic order. The factors cover
/// the entire string without gaps.
///
/// O(n) time, O(k) space where k is the number of factors.
pub fn lyndon_factorization(s : String) -> Array[(Int, Int)] {
  let n = s.length()
  let factors : Array[(Int, Int)] = []
  let mut i = 0
  while i < n {
    let mut j = i + 1
    let mut k = i
    // Duval inner loop: extend while s[j] >= s[k].
    while j < n && s[j] >= s[k] {
      if s[j] > s[k] {
        k = i
      } else {
        k = k + 1
      }
      j = j + 1
    }
    // Emit factors of length (j - k) while i <= k.
    // Each emitted factor s[i..i+(j-k)) is a Lyndon word.
    while i <= k {
      factors.push((i, j - k))
      i = i + (j - k)
    }
  }
  factors
}

// ---------------------------------------------------------------------------
// Minimum rotation (minimum representation algorithm)
// ---------------------------------------------------------------------------

/// Find the starting index of the lexicographically smallest rotation of `s`.
///
/// Uses the minimum representation algorithm: two candidate pointers `i` and
/// `j` are maintained, and at each step the string starting at each candidate
/// is compared cyclically. The loser advances past the matched region.
///
/// Returns 0 for empty or single-character strings. O(n) time, O(1) space.
pub fn min_rotation_index(s : String) -> Int {
  let n = s.length()
  if n <= 1 {
    return 0
  }
  let mut i = 0
  let mut j = 1
  let mut k = 0
  while i < n && j < n && k < n {
    let a = s[(i + k) % n]
    let b = s[(j + k) % n]
    if a == b {
      k = k + 1
    } else if a < b {
      // s[i..] is smaller. Advance j past the matched region.
      j = j + k + 1
      if j <= i {
        j = i + 1
      }
      k = 0
    } else {
      // s[j..] is smaller. Advance i past the matched region.
      i = i + k + 1
      if i <= j {
        i = j + 1
      }
      k = 0
    }
  }
  if i < j {
    i
  } else {
    j
  }
}

// ---------------------------------------------------------------------------
// Lyndon word check
// ---------------------------------------------------------------------------

/// Check if `s` is a Lyndon word.
///
/// A string is a Lyndon word iff it is strictly smaller than all its proper
/// suffixes. This implementation checks the condition directly: for each
/// suffix s[i..n), verify s < s[i..n) character by character.
///
/// O(n^2) worst case, but typically O(n) for Lyndon words (breaks early).
pub fn is_lyndon(s : String) -> Bool {
  let n = s.length()
  if n == 0 {
    return false
  }
  if n == 1 {
    return true
  }
  for i = 1; i < n; i = i + 1 {
    // Compare s[0..] with s[i..n) character by character.
    // If all overlapping characters are equal, s is longer and thus s > suffix.
    let mut suffix_is_smaller = false
    for j = 0; j < n - i; j = j + 1 {
      let a = s[j]
      let b = s[i + j]
      if a < b {
        suffix_is_smaller = true
        break
      } else if a > b {
        return false
      }
      // Equal: continue comparing
    }
    // If we never found s < suffix in the overlap, and s is longer than
    // the suffix, then s >= suffix (s is NOT strictly smaller). Not Lyndon.
    if !suffix_is_smaller {
      return false
    }
  }
  true
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "lyndon: factorization of simple string" {
  // "abc" is already a Lyndon word (a < b < c)
  let factors = lyndon_factorization("abc")
  assert_eq(factors.length(), 1)
  assert_eq(factors[0], (0, 3))
}

test "lyndon: factorization of repeated chars" {
  // "aaa" → "a", "a", "a" (single chars are Lyndon words)
  let factors = lyndon_factorization("aaa")
  assert_eq(factors.length(), 3)
  assert_eq(factors[0], (0, 1))
  assert_eq(factors[1], (1, 1))
  assert_eq(factors[2], (2, 1))
}

test "lyndon: factorization of abab" {
  // "ab" is a Lyndon word. "abab" → "ab", "ab"
  let factors = lyndon_factorization("abab")
  assert_eq(factors.length(), 2)
  assert_eq(factors[0], (0, 2))
  assert_eq(factors[1], (2, 2))
}

test "lyndon: factorization covers entire string" {
  let test_strings = ["hello", "cba", "aaaa", "abracadabra", "z", ""]
  for s in test_strings {
    let factors = lyndon_factorization(s)
    let mut total = 0
    for f in factors {
      total = total + f.1
    }
    assert_eq(total, s.length())
  }
}

test "lyndon: factors are non-increasing" {
  let s = "dcbaab"
  let factors = lyndon_factorization(s)
  for i = 0; i < factors.length() - 1; i = i + 1 {
    let (s1, l1) = factors[i]
    let (s2, l2) = factors[i + 1]
    let w1 = s[s1 : s1 + l1].to_owned()
    let w2 = s[s2 : s2 + l2].to_owned()
    // w1 >= w2 lexicographically: compare char by char
    let mut cmp = 0
    for j = 0; j < w1.length() && j < w2.length(); j = j + 1 {
      if w1[j] > w2[j] {
        cmp = 1
        break
      } else if w1[j] < w2[j] {
        cmp = -1
        break
      }
    }
    if cmp == 0 {
      cmp = w1.length() - w2.length()
    }
    assert_true(cmp >= 0)
  }
}

test "lyndon: factorization of cba" {
  // "c", "b", "a" — each is a single-char Lyndon word, non-increasing
  let factors = lyndon_factorization("cba")
  assert_eq(factors.length(), 3)
  assert_eq(factors[0], (0, 1))
  assert_eq(factors[1], (1, 1))
  assert_eq(factors[2], (2, 1))
}

test "lyndon: factorization of aabaa" {
  // Duval: "aabaa"
  //   i=0, j=1, k=0
  //   s[1]='a' == s[0]='a' → k=1, j=2
  //   s[2]='b' > s[1]='a'  → k=0, j=3
  //   s[3]='a' == s[0]='a' → k=1, j=4
  //   s[4]='a' == s[1]='a' → k=2, j=5 (end)
  //   Emit while i<=k: factor_len = j-k = 5-2 = 3
  //     i=0 <= k=2: emit (0,3), i=3
  //     i=3 <= k=2? No.
  //   i=3, j=4, k=3
  //   s[4]='a' == s[3]='a' → k=4, j=5 (end)
  //   Emit while i<=k: factor_len = j-k = 5-4 = 1
  //     i=3 <= k=4: emit (3,1), i=4
  //     i=4 <= k=4: emit (4,1), i=5
  //     i=5 <= k=4? No.
  //   Result: [(0,3),(3,1),(4,1)] → "aab", "a", "a"
  let factors = lyndon_factorization("aabaa")
  assert_eq(factors.length(), 3)
  assert_eq(factors[0], (0, 3))
  assert_eq(factors[1], (3, 1))
  assert_eq(factors[2], (4, 1))
}

test "lyndon: factorization each factor is Lyndon" {
  let test_strings = [
    "hello", "cba", "aaaa", "abracadabra", "aabaa", "abab", "abcabc",
  ]
  for s in test_strings {
    let factors = lyndon_factorization(s)
    for f in factors {
      let word = s[f.0 : f.0 + f.1].to_owned()
      assert_true(is_lyndon(word))
    }
  }
}

test "lyndon: is_lyndon basic" {
  assert_true(is_lyndon("a"))
  assert_true(is_lyndon("ab"))
  assert_true(is_lyndon("abc"))
  assert_true(is_lyndon("aab"))
  assert_false(is_lyndon("aa"))
  assert_false(is_lyndon("ba"))
  assert_false(is_lyndon(""))
  assert_false(is_lyndon("abab"))
  assert_false(is_lyndon("aba"))
  assert_true(is_lyndon("aab"))
  assert_true(is_lyndon("aaab"))
}

test "lyndon: min_rotation basic" {
  assert_eq(min_rotation_index("abc"), 0)
  // "bca" → rotations: bca, cab, abc → min "abc" at index 2
  assert_eq(min_rotation_index("bca"), 2)
  // "cab" → rotations: cab, abc, bca → min "abc" at index 1
  assert_eq(min_rotation_index("cab"), 1)
  assert_eq(min_rotation_index("aaa"), 0)
  assert_eq(min_rotation_index(""), 0)
  assert_eq(min_rotation_index("a"), 0)
}

test "lyndon: min_rotation of repeated pattern" {
  // "abab" rotations: "abab", "baba", "abab", "baba"
  // minimum is "abab" at index 0
  assert_eq(min_rotation_index("abab"), 0)
  // "baba" rotations: "baba", "abab", "baba", "abab"
  // minimum is "abab" at index 1
  assert_eq(min_rotation_index("baba"), 1)
}

test "lyndon: min_rotation complex" {
  // rotations of "dcba": dcba, cbad, badc, adcb
  // sorted: adcb, badc, cbad, dcba → min at index 3
  assert_eq(min_rotation_index("dcba"), 3)
  // rotations of "cdab": cdab, dabc, abcd, bcda
  // sorted: abcd, bcda, cdab, dabc → min at index 2
  assert_eq(min_rotation_index("cdab"), 2)
}

test "lyndon: min_rotation brute force check" {
  // Verify against brute force for various strings
  let test_strings = [
    "hello", "world", "abracadabra", "mississippi", "aabaa",
    "xyzabc", "zzz", "cbcba",
  ]
  for s in test_strings {
    let n = s.length()
    let mut best_idx = 0
    for i = 1; i < n; i = i + 1 {
      // Compare rotation starting at i with rotation starting at best_idx.
      // rotation(i) < rotation(best_idx) iff i is a better candidate.
      let mut j = 0
      let mut better = false
      while j < n {
        let a = s[(best_idx + j) % n]
        let b = s[(i + j) % n]
        if b < a {
          better = true
          break
        } else if b > a {
          break
        }
        j = j + 1
      }
      if better {
        best_idx = i
      }
    }
    assert_eq(min_rotation_index(s), best_idx)
  }
}
