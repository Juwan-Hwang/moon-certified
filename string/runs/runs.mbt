/// Runs — Lempel-Ziv Factorization.
///
/// Implements the Lempel-Ziv (LZ77) factorization of a string, also known as
/// the Lempel-Ziv parsing or decomposition. This is a fundamental string
/// decomposition used in data compression (LZ77/LZ78/LZW), string indexing,
/// and repetition detection.
///
/// ## Lempel-Ziv Factorization
///
/// Given a string S of length n, the LZ factorization decomposes S into
/// factors (phrases):
///
/// S = f₁ f₂ ... fₖ
///
/// where each factor fᵢ is either:
/// - A **literal**: a single character that does not occur in S[0..pos-1]
///   (where pos is the start of fᵢ), or
/// - A **match**: the longest substring S[pos..pos+L-1] such that this
///   substring occurs starting at some position j < pos in S.
///   Self-referencing matches (where the match source overlaps with the
///   current position) are supported.
///
/// ## Algorithm
///
/// Uses the **Longest Previous Factor (LPF)** approach with suffix array
/// and LCP array, following the framework of Crochemore & Ilie (2008):
///
/// 1. Build the suffix array (SA) and LCP array of S.
/// 2. Build a sparse table for O(1) range minimum queries (RMQ) on LCP.
/// 3. Process positions in **decreasing order** of original index, maintaining
///    a doubly-linked list of unprocessed SA ranks. For each position i,
///    the linked-list neighbours in SA give the closest suffixes (sharing the
///    longest prefix), and since all remaining positions are < i, every
///    neighbour is a valid previous occurrence.
/// 4. Derive the LZ factorization from the LPF array.
///
/// ## Complexity
///
/// - Time: O(n log n) — SA construction O(n), LCP construction O(n),
///   sparse table O(n log n), LPF computation O(n).
/// - Space: O(n log n) for the sparse table; O(n) for everything else.
///
/// ## References
///
/// - Ziv & Lempel (1977): "A Universal Algorithm for Sequential Data Compression"
/// - Crochemore & Ilie (2008): "Computing the Lempel-Ziv Factorization in O(n log n) Time"
/// - Crochemore, Hancart & Lecroq (2007): "Algorithms on Strings"
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Sparse table for Range Minimum Query (RMQ) on the LCP array
// ---------------------------------------------------------------------------

///|
/// Sparse table for range minimum queries on an integer array.
///
/// `query(l, r)` returns `min(arr[l], arr[l+1], ..., arr[r])` in O(1).
/// Construction is O(n log n) time and space.
priv struct SparseTable {
  table : Array[Array[Int]] // table[j][i] = min(arr[i..i+2^j-1])
  log_table : Array[Int] // precomputed floor(log2(k)) for k = 0..n
}

///|
/// Build a sparse table for range minimum queries.
fn build_sparse_table(arr : FixedArray[Int]) -> SparseTable {
  let n = arr.length()
  if n == 0 {
    return { table: [], log_table: [] }
  }
  // Precompute floor(log2(k)) for k = 0..n.
  let log_table = Array::make(n + 1, 0)
  let mut k = 1
  while 1 << k <= n {
    let mut j = 1 << k
    while j < 1 << (k + 1) && j <= n {
      log_table[j] = k
      j = j + 1
    }
    k = k + 1
  }
  // Build the sparse table.
  let max_k = if n > 0 { log_table[n] + 1 } else { 1 }
  let table : Array[Array[Int]] = []
  for _j = 0; _j < max_k; _j = _j + 1 {
    table.push(Array::make(n, 0))
  }
  // Level 0: table[0][i] = arr[i].
  for i = 0; i < n; i = i + 1 {
    table[0][i] = arr[i]
  }
  // Level j: table[j][i] = min(table[j-1][i], table[j-1][i + 2^(j-1)]).
  for j = 1; j < max_k; j = j + 1 {
    let step = 1 << (j - 1)
    let mut i = 0
    while i + (1 << j) - 1 < n {
      let a = table[j - 1][i]
      let b = table[j - 1][i + step]
      table[j][i] = if a < b { a } else { b }
      i = i + 1
    }
  }
  { table, log_table }
}

///|
/// Query the minimum value in arr[l..r] (inclusive) in O(1).
fn sparse_query(st : SparseTable, l : Int, r : Int) -> Int {
  if l > r {
    return 0x7FFFFFFF // Should not happen; return sentinel
  }
  let len = r - l + 1
  let k = st.log_table[len]
  let a = st.table[k][l]
  let b = st.table[k][r - (1 << k) + 1]
  if a < b {
    a
  } else {
    b
  }
}

// ---------------------------------------------------------------------------
// Longest Previous Factor (LPF) computation
// ---------------------------------------------------------------------------

///|
/// Result of LPF computation: for each position i, the length of the longest
/// prefix of S[i..] that occurs starting at some position j < i, and the
/// starting position j of that occurrence (-1 if no match).
priv struct LpfResult {
  lpf : Array[Int] // lpf[i] = longest previous factor length at position i
  prev_occ : Array[Int] // prev_occ[i] = starting position of the match, or -1
}

///|
/// Compute the Longest Previous Factor (LPF) array using SA + LCP + RMQ.
///
/// For each position i in the string, computes:
/// - `lpf[i]`: length of the longest prefix of S[i..] that occurs at some
///   position j < i in S.
/// - `prev_occ[i]`: the starting position j of that occurrence, or -1 if
///   no match exists (lpf[i] == 0).
///
/// ## Algorithm
///
/// Processes positions in **decreasing order** of original index. A
/// doubly-linked list tracks unprocessed SA ranks. When processing position i,
/// all remaining ranks correspond to positions < i, so every neighbour is a
/// valid previous occurrence. The closest neighbours in SA give the longest
/// common prefix, found via RMQ on the LCP array.
fn compute_lpf(
  sa : Array[Int],
  lcp : FixedArray[Int],
  isa : Array[Int],
  n : Int,
) -> LpfResult {
  let lpf = Array::make(n, 0)
  let prev_occ = Array::make(n, -1)
  if n == 0 {
    return { lpf, prev_occ }
  }
  if n == 1 {
    return { lpf, prev_occ }
  }
  // Build sparse table for RMQ on LCP.
  let st = build_sparse_table(lcp)
  // Initialize doubly-linked list of all ranks.
  let next_rank = Array::make(n, 0) // next_rank[r] = next rank in list, or -1
  let prev_rank = Array::make(n, 0) // prev_rank[r] = prev rank in list, or -1
  for r = 0; r < n; r = r + 1 {
    prev_rank[r] = r - 1
    next_rank[r] = r + 1
  }
  next_rank[n - 1] = -1
  // Process positions in decreasing order of original index.
  // When processing position i, positions i+1..n-1 have been removed.
  // Remaining ranks correspond to positions 0..i, all < i (except i itself).
  for i = n - 1; i >= 0; i = i - 1 {
    let r = isa[i]
    let p = prev_rank[r] // nearest remaining rank to the left
    let s = next_rank[r] // nearest remaining rank to the right
    let mut best = 0
    let mut best_pos = -1
    // Check left neighbour.
    if p >= 0 {
      // LCP(r, p) = min(lcp[p+1], ..., lcp[r])
      let lcp_val = sparse_query(st, p + 1, r)
      if lcp_val > best {
        best = lcp_val
        best_pos = sa[p]
      }
    }
    // Check right neighbour.
    if s >= 0 && s < n {
      // LCP(r, s) = min(lcp[r+1], ..., lcp[s])
      let lcp_val = sparse_query(st, r + 1, s)
      if lcp_val > best {
        best = lcp_val
        best_pos = sa[s]
      }
    }
    // Cap match length to avoid reading past end of string.
    // The match S[best_pos..best_pos+best-1] must not exceed position i-1+best,
    // but self-referencing matches are allowed (LZ77 style), so the only
    // constraint is best_pos + best <= n and i + best <= n.
    // Since both suffixes are within the string, LCP already respects this.
    lpf[i] = best
    prev_occ[i] = best_pos
    // Remove rank r from the linked list.
    if p >= 0 {
      next_rank[p] = s
    }
    if s >= 0 {
      prev_rank[s] = p
    }
  }
  { lpf, prev_occ }
}

// ---------------------------------------------------------------------------
// Lempel-Ziv factorization
// ---------------------------------------------------------------------------

///|
/// A single factor in the Lempel-Ziv factorization.
///
/// - `pos`: start position in the original string.
/// - `len`: length of this factor.
/// - `ref_pos`: for matches, the starting position of the referenced occurrence.
///   For literals, this is -1.
/// - `is_literal`: `true` if this factor is a literal (single new character),
///   `false` if it is a match (reference to a previous occurrence).
pub struct LzFactor {
  pos : Int
  len : Int
  ref_pos : Int
  is_literal : Bool
}

///|
/// Compute the Lempel-Ziv (LZ77) factorization of a string.
///
/// Returns an array of factors. Each factor is either a literal (a single
/// character not seen before at its position) or a match (the longest
/// substring starting at the current position that occurs earlier in the
/// string).
///
/// # Example
///
/// For `"banana"`:
/// - Factor 0: literal 'b' (pos=0, len=1)
/// - Factor 1: literal 'a' (pos=1, len=1)
/// - Factor 2: literal 'n' (pos=2, len=1)
/// - Factor 3: match "ana" (pos=3, len=3, ref_pos=1) — matches S[1..3]
///
/// # Complexity
/// - Time: O(n log n)
/// - Space: O(n log n)
pub fn lz_factorize(text : String) -> Array[LzFactor] {
  let n = text.length()
  if n == 0 {
    return []
  }
  // Build suffix array.
  let sa = @sa_is.build_suffix_array(text)
  // Build inverse suffix array (ISA).
  let isa = Array::make(n, 0)
  for r = 0; r < n; r = r + 1 {
    isa[sa[r]] = r
  }
  // Build LCP array (requires FixedArray[Int] for SA).
  let sa_fa = FixedArray::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    sa_fa[i] = sa[i]
  }
  let lcp = @lcp_array.build(sa_fa, text)
  // Compute LPF (Longest Previous Factor).
  let { lpf, prev_occ } = compute_lpf(sa, lcp, isa, n)
  // Derive LZ factorization from LPF.
  let factors : Array[LzFactor] = []
  let mut i = 0
  while i < n {
    if lpf[i] == 0 {
      // Literal: single character not seen before.
      factors.push({ pos: i, len: 1, ref_pos: -1, is_literal: true })
      i = i + 1
    } else {
      // Match: longest previous factor.
      let len = lpf[i]
      factors.push({ pos: i, len, ref_pos: prev_occ[i], is_literal: false })
      i = i + len
    }
  }
  factors
}

///|
/// Compute the Lempel-Ziv factorization and return it as (position, length)
/// pairs. Literal factors have length 1 and ref_pos = -1.
pub fn lz_factorize_pairs(text : String) -> Array[(Int, Int)] {
  let factors = lz_factorize(text)
  let result : Array[(Int, Int)] = []
  for f in factors {
    result.push((f.pos, f.len))
  }
  result
}

///|
/// Count the number of factors in the Lempel-Ziv factorization.
///
/// This is useful as a measure of string compressibility: fewer factors
/// indicate more repetition.
pub fn count_factors(text : String) -> Int {
  lz_factorize(text).length()
}

///|
/// Compute the compression ratio: (number of factors * 2) / string length.
///
/// Each factor can be represented as a (offset, length) pair, so the ratio
/// approximates how much space the LZ-encoded representation would take
/// relative to the raw string. Lower values indicate better compressibility.
pub fn compression_ratio(text : String) -> Double {
  let n = text.length()
  if n == 0 {
    return 0.0
  }
  let k = count_factors(text)
  (k * 2).to_double() / n.to_double()
}

///|
/// Compute the Longest Previous Factor (LPF) array for a string.
///
/// Returns (lpf, prev_occ) where:
/// - `lpf[i]` = length of longest prefix of S[i..] occurring at some j < i.
/// - `prev_occ[i]` = starting position j of that occurrence, or -1.
pub fn lpf_array(text : String) -> (Array[Int], Array[Int]) {
  let n = text.length()
  if n == 0 {
    return ([], [])
  }
  let sa = @sa_is.build_suffix_array(text)
  let isa = Array::make(n, 0)
  for r = 0; r < n; r = r + 1 {
    isa[sa[r]] = r
  }
  let sa_fa = FixedArray::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    sa_fa[i] = sa[i]
  }
  let lcp = @lcp_array.build(sa_fa, text)
  let { lpf, prev_occ } = compute_lpf(sa, lcp, isa, n)
  (lpf, prev_occ)
}

///|
/// Reconstruct the original string from its Lempel-Ziv factorization.
///
/// This is the inverse of `lz_factorize`: given the factors and the original
/// text, verifies that the factorization is correct by reconstructing the
/// text. For literals, the character at `pos` is used. For matches, the
/// substring starting at `ref_pos` with the given `len` is copied (with
/// self-referencing support).
pub fn lz_reconstruct(factors : Array[LzFactor], text : String) -> String {
  let n = text.length()
  let buf = StringBuilder::new()
  for f in factors {
    if f.is_literal {
      // Literal: copy single character.
      if f.pos < n {
        buf.write_char(text[f.pos].unsafe_to_char())
      }
    } else {
      // Match: copy from reference position (with self-referencing).
      for k = 0; k < f.len; k = k + 1 {
        let src = f.ref_pos + k
        if src < n {
          buf.write_char(text[src].unsafe_to_char())
        }
      }
    }
  }
  buf.to_string()
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "lz_factorize: empty string" {
  let factors = lz_factorize("")
  assert_eq(factors.length(), 0)
}

///|
test "lz_factorize: single character" {
  let factors = lz_factorize("a")
  assert_eq(factors.length(), 1)
  assert_true(factors[0].is_literal)
  assert_eq(factors[0].pos, 0)
  assert_eq(factors[0].len, 1)
}

///|
test "lz_factorize: all same characters (self-referencing)" {
  // "aaaa": literal 'a', then match "aaa" (self-referencing: ref_pos=0, len=3)
  let factors = lz_factorize("aaaa")
  assert_eq(factors.length(), 2)
  assert_true(factors[0].is_literal)
  assert_eq(factors[0].len, 1)
  assert_false(factors[1].is_literal)
  assert_eq(factors[1].len, 3)
  assert_eq(factors[1].ref_pos, 0)
  // Verify reconstruction.
  assert_eq(lz_reconstruct(factors, "aaaa"), "aaaa")
}

///|
test "lz_factorize: banana" {
  // S = "banana"
  // pos 0: 'b' -> literal (first occurrence)
  // pos 1: 'a' -> literal (first occurrence)
  // pos 2: 'n' -> literal (first occurrence)
  // pos 3: "ana" -> match at ref_pos=1, len=3
  let factors = lz_factorize("banana")
  assert_eq(factors.length(), 4)
  assert_true(factors[0].is_literal)
  assert_eq(factors[0].pos, 0)
  assert_true(factors[1].is_literal)
  assert_eq(factors[1].pos, 1)
  assert_true(factors[2].is_literal)
  assert_eq(factors[2].pos, 2)
  assert_false(factors[3].is_literal)
  assert_eq(factors[3].pos, 3)
  assert_eq(factors[3].len, 3)
  assert_eq(factors[3].ref_pos, 1)
  // Verify reconstruction.
  assert_eq(lz_reconstruct(factors, "banana"), "banana")
}

///|
test "lz_factorize: abababab" {
  // S = "abababab"
  // pos 0: 'a' -> literal
  // pos 1: 'b' -> literal
  // pos 2: "ababab" -> match at ref_pos=0, len=6
  let factors = lz_factorize("abababab")
  assert_eq(factors.length(), 3)
  assert_true(factors[0].is_literal)
  assert_true(factors[1].is_literal)
  assert_false(factors[2].is_literal)
  assert_eq(factors[2].len, 6)
  assert_eq(factors[2].ref_pos, 0)
  assert_eq(lz_reconstruct(factors, "abababab"), "abababab")
}

///|
test "lz_factorize: abcabcabc" {
  // S = "abcabcabc"
  // pos 0: 'a' -> literal
  // pos 1: 'b' -> literal
  // pos 2: 'c' -> literal
  // pos 3: "abcabc" -> match at ref_pos=0, len=6
  let factors = lz_factorize("abcabcabc")
  assert_eq(factors.length(), 4)
  assert_true(factors[0].is_literal)
  assert_true(factors[1].is_literal)
  assert_true(factors[2].is_literal)
  assert_false(factors[3].is_literal)
  assert_eq(factors[3].len, 6)
  assert_eq(factors[3].ref_pos, 0)
  assert_eq(lz_reconstruct(factors, "abcabcabc"), "abcabcabc")
}

///|
test "lz_factorize: no repeats" {
  // "abcdef" — all characters distinct, no repeats.
  let factors = lz_factorize("abcdef")
  assert_eq(factors.length(), 6)
  for f in factors {
    assert_true(f.is_literal)
    assert_eq(f.len, 1)
  }
  assert_eq(lz_reconstruct(factors, "abcdef"), "abcdef")
}

///|
test "lz_factorize: abracadabra" {
  let text = "abracadabra"
  let factors = lz_factorize(text)
  // Verify reconstruction.
  assert_eq(lz_reconstruct(factors, text), text)
  // First character is always a literal.
  assert_true(factors[0].is_literal)
  // Total length should equal text length.
  let mut total = 0
  for f in factors {
    total = total + f.len
  }
  assert_eq(total, text.length())
}

///|
test "lz_factorize: mississippi" {
  let text = "mississippi"
  let factors = lz_factorize(text)
  assert_eq(lz_reconstruct(factors, text), text)
  // Total length should equal text length.
  let mut total = 0
  for f in factors {
    total = total + f.len
  }
  assert_eq(total, text.length())
  // First factor is literal.
  assert_true(factors[0].is_literal)
}

///|
test "lz_factorize: repeated pattern" {
  // "abcabcabcabc" = "abc" * 4
  let text = "abcabcabcabc"
  let factors = lz_factorize(text)
  assert_eq(lz_reconstruct(factors, text), text)
  // Should have 4 factors: 3 literals + 1 match of length 9.
  assert_eq(factors.length(), 4)
  assert_false(factors[3].is_literal)
  assert_eq(factors[3].len, 9)
  assert_eq(factors[3].ref_pos, 0)
}

///|
test "lz_factorize: self-referencing match" {
  // "aab" — 'a' literal, then "ab" matches at ref_pos=0? No.
  // S[0] = 'a', S[1] = 'a', S[2] = 'b'
  // pos 0: 'a' -> literal
  // pos 1: "ab" — longest prefix of "ab" occurring before pos 1 is "a" (ref_pos=0, len=1)
  let factors = lz_factorize("aab")
  assert_eq(factors.length(), 3)
  assert_true(factors[0].is_literal)
  assert_eq(factors[1].len, 1)
  assert_eq(factors[1].ref_pos, 0)
  assert_eq(lz_reconstruct(factors, "aab"), "aab")
}

///|
test "lz_factorize: long self-referencing" {
  // "aaaaaaaaaa" (10 a's)
  let text = "aaaaaaaaaa"
  let factors = lz_factorize(text)
  assert_eq(factors.length(), 2)
  assert_true(factors[0].is_literal)
  assert_eq(factors[0].len, 1)
  assert_false(factors[1].is_literal)
  assert_eq(factors[1].len, 9)
  assert_eq(factors[1].ref_pos, 0)
  assert_eq(lz_reconstruct(factors, text), text)
}

///|
test "count_factors: basic" {
  assert_eq(count_factors(""), 0)
  assert_eq(count_factors("a"), 1)
  assert_eq(count_factors("abcdef"), 6)
  assert_eq(count_factors("aaaa"), 2)
  assert_eq(count_factors("banana"), 4)
}

///|
test "compression_ratio: basic" {
  let r1 = compression_ratio("abcdef")
  let r2 = compression_ratio("aaaaaaaaaa")
  // "abcdef": 6 factors * 2 / 6 = 2.0
  assert_eq(r1, 2.0)
  // "aaaaaaaaaa": 2 factors * 2 / 10 = 0.4
  assert_eq(r2, 0.4)
}

///|
test "lpf_array: basic" {
  let (lpf, prev) = lpf_array("banana")
  // lpf[0] = 0 (first character, no previous occurrence)
  assert_eq(lpf[0], 0)
  assert_eq(prev[0], -1)
  // lpf[1] = 0 (first 'a', no previous occurrence)
  assert_eq(lpf[1], 0)
  assert_eq(prev[1], -1)
  // lpf[2] = 0 (first 'n', no previous occurrence)
  assert_eq(lpf[2], 0)
  assert_eq(prev[2], -1)
  // lpf[3] = 3 ("ana" matches S[1..3])
  assert_eq(lpf[3], 3)
  assert_eq(prev[3], 1)
}

///|
test "lpf_array: all same" {
  let (lpf, _prev) = lpf_array("aaaa")
  assert_eq(lpf[0], 0)
  assert_eq(lpf[1], 3)
  assert_eq(lpf[2], 2)
  assert_eq(lpf[3], 1)
}

///|
test "lpf_array: no repeats" {
  let (lpf, prev) = lpf_array("abcdef")
  for i = 0; i < 6; i = i + 1 {
    assert_eq(lpf[i], 0)
    assert_eq(prev[i], -1)
  }
}

///|
test "lz_factorize: stress test - fibonacci word" {
  // Fibonacci word: S(0)="a", S(1)="ab", S(n) = S(n-1) + S(n-2)
  // This has many repetitions and is a good test for LZ factorization.
  // S(2) = "aba", S(3) = "abaab", S(4) = "abaababa", S(5) = "abaababaabaab"
  let text = "abaababaabaab"
  let factors = lz_factorize(text)
  // Verify reconstruction.
  assert_eq(lz_reconstruct(factors, text), text)
  // Total length matches.
  let mut total = 0
  for f in factors {
    total = total + f.len
  }
  assert_eq(total, text.length())
}

///|
test "lz_factorize: stress test - long repetitive string" {
  // 1000 'a' characters.
  let buf = StringBuilder::new()
  for i = 0; i < 1000; i = i + 1 {
    buf.write_char('a')
  }
  let text = buf.to_string()
  let factors = lz_factorize(text)
  // Should be 2 factors: literal 'a' + match of length 999.
  assert_eq(factors.length(), 2)
  assert_eq(factors[1].len, 999)
  assert_eq(factors[1].ref_pos, 0)
  assert_eq(lz_reconstruct(factors, text), text)
}

///|
test "lz_factorize: stress test - alternating pattern" {
  // "ab" repeated 500 times (1000 chars).
  let buf = StringBuilder::new()
  for i = 0; i < 500; i = i + 1 {
    buf.write_char('a')
    buf.write_char('b')
  }
  let text = buf.to_string()
  let factors = lz_factorize(text)
  assert_eq(lz_reconstruct(factors, text), text)
  // Should be 3 factors: 'a', 'b', match of length 998.
  assert_eq(factors.length(), 3)
  assert_eq(factors[2].len, 998)
}

///|
test "lz_factorize: stress test - Thue-Morse" {
  // Thue-Morse sequence (first 32 terms): cube-free, overlap-free.
  // t(0)=0, t(n) = parity of 1-bits in n.
  // 01101001100101101001011001101001
  let chars = "01101001100101101001011001101001"
  let factors = lz_factorize(chars)
  assert_eq(lz_reconstruct(factors, chars), chars)
  let mut total = 0
  for f in factors {
    total = total + f.len
  }
  assert_eq(total, chars.length())
}

///|
test "lz_factorize: unicode string" {
  // Unicode characters (MoonBit uses UTF-16 code units).
  let text = "αβγαβγ"
  let factors = lz_factorize(text)
  assert_eq(lz_reconstruct(factors, text), text)
  // "αβγ" repeated: 3 literals + 1 match.
  assert_eq(factors.length(), 4)
  assert_false(factors[3].is_literal)
}

///|
test "lz_factorize: two characters" {
  let factors = lz_factorize("ab")
  assert_eq(factors.length(), 2)
  assert_true(factors[0].is_literal)
  assert_true(factors[1].is_literal)
  assert_eq(lz_reconstruct(factors, "ab"), "ab")
}

///|
test "lz_factorize: overlapping match" {
  // "aabaab" — pos 0: 'a' literal, pos 1: 'a' match(ref_pos=0,len=1),
  // pos 2: "baab" — wait, let's check:
  // S = "aabaab"
  // S[0]='a', S[1]='a', S[2]='b', S[3]='a', S[4]='a', S[5]='b'
  // pos 0: 'a' -> literal
  // pos 1: longest prefix of "abaab" occurring before pos 1: "a" (ref_pos=0, len=1)
  // pos 2: longest prefix of "baab" occurring before pos 2: "b" — wait, 'b' first occurs at pos 2, so no match? Actually 'b' hasn't occurred before pos 2, so literal.
  // pos 3: longest prefix of "aab" occurring before pos 3: "aab" (ref_pos=0, len=3)
  let factors = lz_factorize("aabaab")
  assert_eq(lz_reconstruct(factors, "aabaab"), "aabaab")
  assert_true(factors[0].is_literal) // 'a'
  assert_eq(factors[1].len, 1) // 'a' match
  assert_eq(factors[1].ref_pos, 0)
  assert_true(factors[2].is_literal) // 'b' (first occurrence)
  assert_eq(factors[3].len, 3) // "aab" match
  assert_eq(factors[3].ref_pos, 0)
}
