/// MSD (Most-Significant-Digit) radix sort for integers and strings.
///
/// MSD radix sort processes keys from the most significant digit to the least,
/// recursively partitioning the array into buckets. Unlike LSD radix sort
/// (which always performs `d` full passes), MSD radix sort only recurses into
/// buckets that contain more than one element, making it significantly faster
/// when the keys differ in their most significant digits.
///
/// ## Algorithms
///
/// 1. **Integer MSD radix sort** (base-256): Partitions by each byte from the
///    most significant to least significant. Handles negative integers by
///    flipping the sign bit (so negative values sort before positives).
///
/// 2. **String MSD radix sort**: Sorts strings character-by-character from the
///    first character. End-of-string is treated as -1 (sorts before all
///    characters), ensuring shorter strings sort before longer prefixes.
///    Uses insertion sort for small subarrays (≤ 15 elements).
///
/// ## Complexity
///
/// - **Integer**: O(d · n) worst case, O(n + R) per level where d = number of
///   byte digits (≤ 4 for 32-bit Int) and R = 256.
/// - **String**: O(n · L) average where L = average string length. Worst case
///   O(n · W) where W = length of the longest string.
/// - **Space**: O(n + R) auxiliary per recursion level.
///
/// ## References
///
/// - Sedgewick, R. & Wayne, K. "Algorithms," 4th ed., §5.1 (MSD String Sort).
/// - Cormen, Leiserson, Rivest, Stein. "Introduction to Algorithms,"
///   3rd ed., §8.3 (Radix Sort).
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

///|
/// Radix (number of buckets per digit): 256 for base-256 (one byte).
const R : Int = 256

///|
/// Cutoff to insertion sort for small subarrays.
const CUTOFF : Int = 15

///|
/// Sentinel value for "end of string" — sorts before all character codes.
const EOF_CHAR : Int = -1

// ---------------------------------------------------------------------------
// Integer MSD radix sort
// ---------------------------------------------------------------------------

///|
/// Extract byte `pos` (0 = most significant) of a non-negative integer.
fn uint_digit(v : Int, pos : Int) -> Int {
  (v >> (24 - 8 * pos)) & 0xFF
}

///|
/// MSD radix sort for integers (including negatives).
///
/// Returns a new ascendingly-sorted `Array[Int]`. The input is not modified.
///
/// Handles negative values by separating them from non-negatives: negatives
/// are sorted by their bitwise complement (which reverses the unsigned
/// ordering so that more-negative values come first), and non-negatives are
/// sorted directly. The two sorted groups are then concatenated.
///
/// **Complexity**: O(d · n) where d ≤ 4, O(n) space.
pub fn msd_sort_int(xs : Array[Int]) -> Array[Int] {
  let n = xs.length()
  if n <= 1 {
    return xs.copy()
  }
  // Split into negatives and non-negatives.
  let negs : Array[Int] = []
  let nonnegs : Array[Int] = []
  for i = 0; i < n; i = i + 1 {
    if xs[i] < 0 {
      // Bitwise NOT: ~v = -v - 1. For negatives, this gives a non-negative
      // value whose unsigned ordering matches the reverse of the original
      // signed ordering (more negative → larger complement → sorts later).
      negs.push(xs[i] ^ -1)
    } else {
      nonnegs.push(xs[i])
    }
  }
  // Sort non-negatives with MSD radix sort.
  if nonnegs.length() > 1 {
    let aux_n : Array[Int] = Array::make(nonnegs.length(), 0)
    msd_uint_sort(nonnegs, aux_n, 0, nonnegs.length() - 1, 0)
  }
  // Sort negatives (as complements) with MSD radix sort.
  if negs.length() > 1 {
    let aux_g : Array[Int] = Array::make(negs.length(), 0)
    msd_uint_sort(negs, aux_g, 0, negs.length() - 1, 0)
  }
  // Restore negatives from complement form. The complement sort produces
  // ascending order of complements, which is descending order of the
  // original negative values (most negative first). We reverse to get
  // ascending original order.
  let result : Array[Int] = []
  // Negatives in reverse (ascending original order).
  for i = negs.length() - 1; i >= 0; i = i - 1 {
    result.push(negs[i] ^ -1)
  }
  // Non-negatives in ascending order.
  for i = 0; i < nonnegs.length(); i = i + 1 {
    result.push(nonnegs[i])
  }
  result
}

///|
/// Recursive MSD unsigned-integer sort on byte position `pos` for the
/// subarray `arr[lo..=hi]`. All elements must be non-negative.
fn msd_uint_sort(
  arr : Array[Int],
  aux : Array[Int],
  lo : Int,
  hi : Int,
  pos : Int,
) -> Unit {
  if lo >= hi {
    return
  }
  if hi - lo + 1 <= CUTOFF {
    insertion_sort_range(arr, lo, hi)
    return
  }
  if pos >= 4 {
    return
  }
  let count = Array::make(R + 1, 0)
  for i = lo; i <= hi; i = i + 1 {
    let d = uint_digit(arr[i], pos)
    count[d + 1] = count[d + 1] + 1
  }
  for r = 0; r < R; r = r + 1 {
    count[r + 1] = count[r + 1] + count[r]
  }
  for i = lo; i <= hi; i = i + 1 {
    let d = uint_digit(arr[i], pos)
    aux[count[d]] = arr[i]
    count[d] = count[d] + 1
  }
  for i = lo; i <= hi; i = i + 1 {
    arr[i] = aux[i - lo]
  }
  let mut start = lo
  for r = 0; r < R; r = r + 1 {
    let bucket_size = count[r] - (if r > 0 { count[r - 1] } else { 0 })
    if bucket_size > 1 {
      msd_uint_sort(arr, aux, start, start + bucket_size - 1, pos + 1)
    }
    start = start + bucket_size
  }
}

// ---------------------------------------------------------------------------
// String MSD radix sort
// ---------------------------------------------------------------------------

///|
/// Get the character at position `d` of string `s`, or `EOF_CHAR` (-1) if
/// `d` is past the end of the string.
fn char_at(s : String, d : Int) -> Int {
  if d < s.length() {
    s[d].to_int()
  } else {
    EOF_CHAR
  }
}

///|
/// MSD radix sort for strings.
///
/// Returns a new ascendingly-sorted `Array[String]`. The input is not modified.
/// Sorting is case-sensitive and uses Unicode codepoint order (via MoonBit's
/// `Char` comparison).
///
/// End-of-string sorts before all characters, so `"ab"` < `"abc"`.
///
/// **Complexity**: O(n · L) average where L = average string length.
/// O(n · W) worst case where W = longest string length.
pub fn msd_sort_string(xs : Array[String]) -> Array[String] {
  let n = xs.length()
  if n <= 1 {
    return xs.copy()
  }
  // Copy into a working array.
  let arr : Array[String] = Array::make(n, "")
  for i = 0; i < n; i = i + 1 {
    arr[i] = xs[i]
  }
  let aux : Array[String] = Array::make(n, "")
  msd_string_sort(arr, aux, 0, n - 1, 0)
  arr
}

///|
/// Recursive MSD string sort on character position `d` for the subarray
/// `arr[lo..=hi]`.
fn msd_string_sort(
  arr : Array[String],
  aux : Array[String],
  lo : Int,
  hi : Int,
  d : Int,
) -> Unit {
  if lo >= hi {
    return
  }
  if hi - lo + 1 <= CUTOFF {
    insertion_sort_strings(arr, lo, hi, d)
    return
  }
  // Count frequencies: R+2 buckets (EOF_CHAR=-1 maps to index 0, chars 0..255
  // map to indices 1..256).
  let count = Array::make(R + 2, 0)
  for i = lo; i <= hi; i = i + 1 {
    let c = char_at(arr[i], d)
    let idx = c + 1 // EOF_CHAR (-1) → 0, char 0 → 1, ..., char 255 → 256
    count[idx + 1] = count[idx + 1] + 1
  }
  // Prefix sums.
  for r = 0; r < R + 1; r = r + 1 {
    count[r + 1] = count[r + 1] + count[r]
  }
  // Distribute into aux.
  for i = lo; i <= hi; i = i + 1 {
    let c = char_at(arr[i], d)
    let idx = c + 1
    aux[count[idx]] = arr[i]
    count[idx] = count[idx] + 1
  }
  // Copy back.
  for i = lo; i <= hi; i = i + 1 {
    arr[i] = aux[i - lo]
  }
  // Recurse into each bucket (skip the EOF bucket — those strings are done).
  // Bucket 0 = EOF (strings with length ≤ d), no need to recurse.
  for r = 0; r < R; r = r + 1 {
    let bucket_lo = lo + count[r]
    let bucket_hi = lo + count[r + 1] - 1
    if bucket_lo < bucket_hi {
      msd_string_sort(arr, aux, bucket_lo, bucket_hi, d + 1)
    }
  }
}

// ---------------------------------------------------------------------------
// Insertion sort for small subarrays
// ---------------------------------------------------------------------------

///|
/// Insertion sort for a range of sign-flipped integers.
fn insertion_sort_range(arr : Array[Int], lo : Int, hi : Int) -> Unit {
  for i = lo + 1; i <= hi; i = i + 1 {
    let key = arr[i]
    let mut j = i - 1
    while j >= lo && arr[j] > key {
      arr[j + 1] = arr[j]
      j = j - 1
    }
    arr[j + 1] = key
  }
}

///|
/// Insertion sort for strings, comparing from character position `d` onward.
///
/// This is the standard optimization for MSD string sort: when the subarray
/// is small, the overhead of bucket counting exceeds the cost of a simple
/// insertion sort.
fn insertion_sort_strings(
  arr : Array[String],
  lo : Int,
  hi : Int,
  d : Int,
) -> Unit {
  for i = lo + 1; i <= hi; i = i + 1 {
    let key = arr[i]
    let mut j = i - 1
    while j >= lo && compare_strings_at(arr[j], key, d) > 0 {
      arr[j + 1] = arr[j]
      j = j - 1
    }
    arr[j + 1] = key
  }
}

///|
/// Compare two strings starting from character position `d`.
///
/// Returns negative if `a < b`, zero if `a == b`, positive if `a > b`.
fn compare_strings_at(a : String, b : String, d : Int) -> Int {
  let la = a.length()
  let lb = b.length()
  let mut k = d
  while k < la && k < lb {
    let ca = a[k].to_int()
    let cb = b[k].to_int()
    if ca != cb {
      return ca - cb
    }
    k = k + 1
  }
  // One is a prefix of the other: shorter string sorts first.
  la - k - (lb - k)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "msd_int: basic ascending" {
  let xs = [5, 4, 3, 2, 1]
  let sorted = msd_sort_int(xs)
  assert_eq(sorted, [1, 2, 3, 4, 5])
}

///|
test "msd_int: with negatives" {
  let xs = [3, -1, 0, -5, 2, -3, 5]
  let sorted = msd_sort_int(xs)
  assert_eq(sorted, [-5, -3, -1, 0, 2, 3, 5])
}

///|
test "msd_int: empty and single" {
  assert_eq(msd_sort_int([]), [])
  assert_eq(msd_sort_int([42]), [42])
}

///|
test "msd_int: already sorted" {
  let xs = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
  assert_eq(msd_sort_int(xs), xs)
}

///|
test "msd_int: reverse sorted" {
  let xs = [10, 9, 8, 7, 6, 5, 4, 3, 2, 1]
  let sorted = msd_sort_int(xs)
  assert_eq(sorted, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
}

///|
test "msd_int: duplicates" {
  let xs = [3, 1, 4, 1, 5, 9, 2, 6, 5, 3, 5]
  let sorted = msd_sort_int(xs)
  assert_eq(sorted, [1, 1, 2, 3, 3, 4, 5, 5, 5, 6, 9])
}

///|
test "msd_int: all same" {
  let xs = [7, 7, 7, 7, 7]
  assert_eq(msd_sort_int(xs), [7, 7, 7, 7, 7])
}

///|
test "msd_int: large values with negatives" {
  let xs = [
    2147483647, -2147483648, 0, -1, 1, 16777216, -16777216, 65535, -65535,
  ]
  let sorted = msd_sort_int(xs)
  // Correct ascending order: most negative to most positive
  assert_eq(sorted, [
    -2147483648, -16777216, -65535, -1, 0, 1, 65535, 16777216, 2147483647,
  ])
}

///|
test "msd_int: input not modified" {
  let xs = [5, 3, 1, 4, 2]
  let _ = msd_sort_int(xs)
  assert_eq(xs, [5, 3, 1, 4, 2])
}

///|
test "msd_int: stress test 1000 elements" {
  // Deterministic pseudo-random via LCG
  let xs : Array[Int] = Array::make(1000, 0)
  let mut seed = 42
  for i = 0; i < 1000; i = i + 1 {
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
    xs[i] = seed - 0x3FFFFFFF // Range roughly -1B to +1B
  }
  let sorted = msd_sort_int(xs)
  // Verify sorted order
  for i = 0; i < 999; i = i + 1 {
    assert_true(sorted[i] <= sorted[i + 1])
  }
  // Verify it's a permutation: check sum
  let mut sum_orig = 0
  let mut sum_sorted = 0
  for i = 0; i < 1000; i = i + 1 {
    sum_orig = sum_orig + xs[i]
    sum_sorted = sum_sorted + sorted[i]
  }
  assert_eq(sum_orig, sum_sorted)
}

///|
test "msd_string: basic" {
  let xs = ["banana", "apple", "cherry", "date"]
  let sorted = msd_sort_string(xs)
  assert_eq(sorted, ["apple", "banana", "cherry", "date"])
}

///|
test "msd_string: empty and single" {
  assert_eq(msd_sort_string([]), [])
  assert_eq(msd_sort_string(["hello"]), ["hello"])
}

///|
test "msd_string: prefix sorting" {
  // Shorter strings sort before longer strings with the same prefix
  let xs = ["abc", "ab", "abcd", "a"]
  let sorted = msd_sort_string(xs)
  assert_eq(sorted, ["a", "ab", "abc", "abcd"])
}

///|
test "msd_string: with empty strings" {
  let xs = ["b", "", "a", "", "c"]
  let sorted = msd_sort_string(xs)
  assert_eq(sorted, ["", "", "a", "b", "c"])
}

///|
test "msd_string: case sensitive" {
  let xs = ["Banana", "apple", "Cherry", "banana"]
  let sorted = msd_sort_string(xs)
  // Uppercase letters (65-90) sort before lowercase (97-122)
  assert_eq(sorted, ["Banana", "Cherry", "apple", "banana"])
}

///|
test "msd_string: duplicates" {
  let xs = ["abc", "abc", "abc", "abc"]
  let sorted = msd_sort_string(xs)
  assert_eq(sorted, ["abc", "abc", "abc", "abc"])
}

///|
test "msd_string: input not modified" {
  let xs = ["zebra", "apple", "mango"]
  let _ = msd_sort_string(xs)
  assert_eq(xs, ["zebra", "apple", "mango"])
}

///|
test "msd_string: common prefixes" {
  let xs = [
    "prefix_aaa", "prefix_bbb", "prefix_aab", "other", "prefix_aaa", "prefix_",
  ]
  let sorted = msd_sort_string(xs)
  assert_eq(sorted, [
    "other", "prefix_", "prefix_aaa", "prefix_aaa", "prefix_aab", "prefix_bbb",
  ])
}

///|
test "msd_string: single chars" {
  let xs = ["c", "a", "b", "a", "c", "b"]
  let sorted = msd_sort_string(xs)
  assert_eq(sorted, ["a", "a", "b", "b", "c", "c"])
}

///|
test "msd_string: stress test 500 strings" {
  // Generate 500 strings of varying lengths
  let xs : Array[String] = Array::make(500, "")
  let mut seed = 12345
  for i = 0; i < 500; i = i + 1 {
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
    let len = 1 + seed % 10
    let buf = StringBuilder()
    for j = 0; j < len; j = j + 1 {
      seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
      buf.write_char((97 + seed % 26).unsafe_to_char())
    }
    xs[i] = buf.to_string()
  }
  let sorted = msd_sort_string(xs)
  // Verify sorted order using same comparison as the sort
  for i = 0; i < 499; i = i + 1 {
    assert_true(compare_strings_at(sorted[i], sorted[i + 1], 0) <= 0)
  }
}

///|
test "msd_string: compare_strings_at" {
  assert_true(compare_strings_at("abc", "abd", 0) < 0)
  assert_true(compare_strings_at("abc", "abc", 0) == 0)
  assert_true(compare_strings_at("abd", "abc", 0) > 0)
  assert_true(compare_strings_at("abc", "abcd", 0) < 0)
  assert_true(compare_strings_at("abcd", "abc", 0) > 0)
  // Compare from position 2
  assert_true(compare_strings_at("xyzabc", "xyzabd", 2) < 0)
  assert_true(compare_strings_at("xyzabc", "xyzab", 2) > 0)
}
