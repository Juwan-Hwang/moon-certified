///|
/// SA-IS: Suffix Array - Induced Sorting (Nong, Zhang, Chan 2009).
/// O(n) suffix array construction via S/L-type classification, LMS
/// substring sorting, naming, recursion, and final induced sort.
/// Input `s` must end with sentinel 0 (strictly smallest value).
fn is_lms(t : Array[Bool], i : Int) -> Bool {
  i > 0 && t[i] && !t[i - 1]
}

///|
/// Compare two LMS substrings: equal iff identical chars, types, and
/// both reach an LMS boundary at the same position.
fn lms_equal(
  s : Array[Int],
  t : Array[Bool],
  n : Int,
  i : Int,
  j : Int,
) -> Bool {
  if i == j {
    return true
  }
  for d = 0; d < n; d = d + 1 {
    if i + d >= n || j + d >= n {
      return false
    }
    if s[i + d] != s[j + d] {
      return false
    }
    if t[i + d] != t[j + d] {
      return false
    }
    if d > 0 {
      let ie = is_lms(t, i + d)
      let je = is_lms(t, j + d)
      if ie && je {
        return true
      }
      if ie || je {
        return false
      }
    }
  }
  false
}

///|
fn bucket_size(s : Array[Int], n : Int, maxc : Int) -> Array[Int] {
  let b = Array::make(maxc + 1, 0)
  for i = 0; i < n; i = i + 1 {
    b[s[i]] = b[s[i]] + 1
  }
  b
}

///|
/// Induced sort: place LMS at bucket ends, induce L-type (left-to-right),
/// then S-type (right-to-left). Modifies `sa` in place.
fn induced_sort(
  s : Array[Int],
  t : Array[Bool],
  n : Int,
  maxc : Int,
  sa : Array[Int],
  lms_arr : Array[Int],
) -> Unit {
  for i = 0; i < n; i = i + 1 {
    sa[i] = -1
  }
  // Place LMS suffixes at end of their buckets.
  let bkt = bucket_size(s, n, maxc)
  let mut sum = 0
  for i = 0; i <= maxc; i = i + 1 {
    sum = sum + bkt[i]
    bkt[i] = sum
  }
  for i = lms_arr.length() - 1; i >= 0; i = i - 1 {
    let c = s[lms_arr[i]]
    bkt[c] = bkt[c] - 1
    sa[bkt[c]] = lms_arr[i]
  }
  // Induce L-type suffixes (scan left to right, place at front).
  let bkt2 = bucket_size(s, n, maxc)
  sum = 0
  for i = 0; i <= maxc; i = i + 1 {
    let cnt = bkt2[i]
    bkt2[i] = sum
    sum = sum + cnt
  }
  for i = 0; i < n; i = i + 1 {
    let j = sa[i] - 1
    if j >= 0 && !t[j] {
      let c = s[j]
      sa[bkt2[c]] = j
      bkt2[c] = bkt2[c] + 1
    }
  }
  // Induce S-type suffixes (scan right to left, place at end).
  let bkt3 = bucket_size(s, n, maxc)
  sum = 0
  for i = 0; i <= maxc; i = i + 1 {
    sum = sum + bkt3[i]
    bkt3[i] = sum
  }
  for i = n - 1; i >= 0; i = i - 1 {
    let j = sa[i] - 1
    if j >= 0 && t[j] {
      let c = s[j]
      bkt3[c] = bkt3[c] - 1
      sa[bkt3[c]] = j
    }
  }
}

///|
/// SA-IS recursive core. Builds suffix array of s[0..n) where all
/// values are in [0, maxc] and s[n-1] = 0 (sentinel).
fn sa_is_rec(s : Array[Int], n : Int, maxc : Int) -> Array[Int] {
  if n == 1 {
    return [0]
  }
  // Step 1: Classify each position as S-type (true) or L-type (false).
  let t = Array::make(n, false)
  t[n - 1] = true
  for i = n - 2; i >= 0; i = i - 1 {
    t[i] = if s[i] < s[i + 1] {
      true
    } else if s[i] > s[i + 1] {
      false
    } else {
      t[i + 1]
    }
  }
  // Collect LMS positions in string order.
  let lms_positions : Array[Int] = []
  for i = 1; i < n; i = i + 1 {
    if is_lms(t, i) {
      lms_positions.push(i)
    }
  }
  let n1 = lms_positions.length()
  // Step 2: First induced sort to sort LMS substrings.
  let sa = Array::make(n, -1)
  induced_sort(s, t, n, maxc, sa, lms_positions)
  // Step 3: Name LMS substrings in sorted order.
  let name = Array::make(n, -1)
  let mut name_count = 0
  let mut prev = -1
  for i = 0; i < n; i = i + 1 {
    if is_lms(t, sa[i]) {
      if prev == -1 || !lms_equal(s, t, n, prev, sa[i]) {
        name[sa[i]] = name_count
        name_count = name_count + 1
        prev = sa[i]
      } else {
        name[sa[i]] = name_count - 1
      }
    }
  }
  // Build reduced string s1 from names.
  let s1 = Array::make(n1, 0)
  let mut idx = 0
  for i = 0; i < n; i = i + 1 {
    if is_lms(t, i) {
      s1[idx] = name[i]
      idx = idx + 1
    }
  }
  // Step 4: Recurse if duplicate names exist, otherwise compute directly.
  let sa1 : Array[Int] = if name_count == n1 {
    let sa1 = Array::make(n1, 0)
    for i = 0; i < n1; i = i + 1 {
      sa1[s1[i]] = i
    }
    sa1
  } else {
    sa_is_rec(s1, n1, name_count - 1)
  }
  // Step 5: Final induced sort with LMS in sorted order.
  let sorted_lms = Array::make(n1, 0)
  for i = 0; i < n1; i = i + 1 {
    sorted_lms[i] = lms_positions[sa1[i]]
  }
  induced_sort(s, t, n, maxc, sa, sorted_lms)
  sa
}

///|
/// Build suffix array using SA-IS.
/// Input `s` must end with sentinel 0 (strictly smallest value).
pub fn sa_is(s : Array[Int]) -> Array[Int] {
  let n = s.length()
  let mut maxc = 0
  for i = 0; i < n; i = i + 1 {
    if s[i] > maxc {
      maxc = s[i]
    }
  }
  sa_is_rec(s, n, maxc)
}

///|
/// Build suffix array of a string.
/// Converts string to int array (code units + 1 so sentinel is 0),
/// calls sa_is, then strips the sentinel entry from the result.
pub fn build_suffix_array(text : String) -> Array[Int] {
  let n = text.length()
  let s : Array[Int] = []
  for i = 0; i < n; i = i + 1 {
    s.push(text[i].to_int() + 1)
  }
  s.push(0)
  let full_sa = sa_is(s)
  let result : Array[Int] = []
  for i = 1; i <= n; i = i + 1 {
    result.push(full_sa[i])
  }
  result
}

///|
/// Brute-force suffix array for testing: sort suffix indices by comparison.
fn brute_force_sa(text : String) -> Array[Int] {
  let n = text.length()
  let sa : Array[Int] = []
  for i = 0; i < n; i = i + 1 {
    sa.push(i)
  }
  sa.sort_by(fn(i, j) {
    let mut k = 0
    while i + k < n && j + k < n {
      let a = text[i + k].to_int()
      let b = text[j + k].to_int()
      if a != b {
        return a.compare(b)
      }
      k = k + 1
    }
    if i + k == n {
      if j + k == n {
        0
      } else {
        -1
      }
    } else {
      1
    }
  })
  sa
}

///|
test "sa_is: banana" {
  assert_eq(build_suffix_array("banana"), brute_force_sa("banana"))
}

///|
test "sa_is: mississippi" {
  assert_eq(build_suffix_array("mississippi"), brute_force_sa("mississippi"))
}

///|
test "sa_is: edge cases" {
  let texts = ["aaaa", "abababab", "abracadabra", "a", ""]
  for i = 0; i < texts.length(); i = i + 1 {
    assert_eq(build_suffix_array(texts[i]), brute_force_sa(texts[i]))
  }
}

///|
test "sa_is: all same character" {
  assert_eq(build_suffix_array("zzzzzz"), brute_force_sa("zzzzzz"))
}

///|
test "sa_is: sorted string" {
  assert_eq(build_suffix_array("abcdefg"), brute_force_sa("abcdefg"))
}

///|
test "sa_is: reverse sorted string" {
  assert_eq(build_suffix_array("zyxwvut"), brute_force_sa("zyxwvut"))
}

///|
test "sa_is: long random-like string" {
  let s = "abracadabradefghijklmnopqrstuvwxyz"
  assert_eq(build_suffix_array(s), brute_force_sa(s))
}

///|
test "sa_is: string with repeated pattern" {
  let s = "abcabcabcabcabc"
  assert_eq(build_suffix_array(s), brute_force_sa(s))
}

///|
test "sa_is: binary alphabet" {
  // Binary alphabet exercises the induced-sorting classification well.
  let s = "01001010100101001010"
  assert_eq(build_suffix_array(s), brute_force_sa(s))
}

///|
test "sa_is: verify suffix array correctness" {
  // For "banana", the suffix array should be [6, 5, 3, 1, 0, 4, 2]
  // (indices of suffixes sorted lexicographically, with sentinel at end).
  let sa = build_suffix_array("banana")
  // The SA should contain all indices exactly once.
  let n = "banana".length()
  assert_eq(sa.length(), n)
  let seen = FixedArray::make(n, false)
  for i = 0; i < n; i = i + 1 {
    assert_true(sa[i] >= 0 && sa[i] < n)
    assert_false(seen[sa[i]])
    seen[sa[i]] = true
  }
}

///|
test "sa_is: raw int array [1,2,1,0]" {
  // Suffixes: [1,2,1,0] < [2,1,0] ... sorted: [0], [1,0], [1,2,1,0], [2,1,0]
  assert_eq(sa_is([1, 2, 1, 0]), [3, 2, 0, 1])
}

///|
test "sa_is: single sentinel element" {
  assert_eq(sa_is([0]), [0])
}

///|
test "sa_is: two elements [1,0]" {
  // Suffixes: [1,0] (idx 0), [0] (idx 1). Sorted: [0] < [1,0].
  assert_eq(sa_is([1, 0]), [1, 0])
}

///|
test "sa_is: large alphabet values" {
  // Values 0, 500, 1000 — tests that SA-IS handles non-ASCII ranges.
  assert_eq(sa_is([1000, 500, 0]), [2, 1, 0])
}

///|
test "sa_is: non-contiguous alphabet values" {
  // Values 0, 1, 5 — tests handling of gaps in alphabet.
  // Suffixes: [5,1,5,0](0), [1,5,0](1), [5,0](2), [0](3).
  // Sorted: [0], [1,5,0], [5,0], [5,1,5,0].
  assert_eq(sa_is([5, 1, 5, 0]), [3, 1, 2, 0])
}

///|
test "sa_is: exact suffix array for banana" {
  // Suffixes of "banana" sorted: a(5), ana(3), anana(1), banana(0), na(4), nana(2).
  // SA = [5, 3, 1, 0, 4, 2] (sentinel entry stripped by build_suffix_array).
  assert_eq(build_suffix_array("banana"), [5, 3, 1, 0, 4, 2])
}

///|
test "sa_is: string with punctuation" {
  let s = "a!b@c#"
  assert_eq(build_suffix_array(s), brute_force_sa(s))
}
