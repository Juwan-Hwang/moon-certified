/// De Bruijn sequences via the FKM (Fredricksen–Kessler–Maiorana) algorithm.
///
/// A **de Bruijn sequence** B(k, n) is a cyclic sequence of length kⁿ over an
/// alphabet of size k such that every possible string of length n over that
/// alphabet appears exactly once as a contiguous substring (wrapping around
/// cyclically). For example, B(2, 3) = `00010111` contains every 3-bit binary
/// string (000, 001, 010, 011, 100, 101, 110, 111) exactly once.
///
/// ## Algorithm (FKM)
///
/// The lexicographically smallest de Bruijn sequence is obtained by
/// concatenating all **Lyndon words** whose length divides n, in lexicographic
/// order. A Lyndon word is a string strictly smaller than all its non-trivial
/// cyclic rotations.
///
/// The generation uses the **FKM necklace algorithm**, which produces Lyndon
/// words in lexicographic order by a recursive traversal:
///
/// ```text
/// a[1..n] ← 0
/// visit(t, p):
///   if t > n:
///     if n mod p = 0: output a[1..p]   // Lyndon word of length p
///   else:
///     a[t] ← a[t − p];  visit(t + 1, p)
///     for j = a[t−p]+1 .. k−1:
///       a[t] ← j;  visit(t + 1, t)
/// ```
///
/// The recursion depth is at most n, which is safe for all practical inputs
/// (kⁿ grows exponentially, so n is typically ≤ 20).
///
/// ## Complexity
///
/// - Time:  O(kⁿ) — proportional to the output length.
/// - Space: O(n) for the recursion stack + O(kⁿ) for the output.
///
/// ## References
///
/// - Fredricksen, H. and Maiorana, J. (1978). "Necklaces of beads in k colors
///   and k-ary de Bruijn sequences." *Discrete Mathematics*, 23(3), 207–210.
/// - de Bruijn, N. G. (1946). "A combinatorial problem." *Proc. Ned. Akad.
///   Wet.*, 49, 758–764.
/// - Knuth, D. E. (2011). *The Art of Computer Programming*, Vol. 4A,
///   Section 7.2.1.1, pp. 303–309.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Internal state for FKM generation
// ---------------------------------------------------------------------------

///|
/// Mutable state carried through the FKM recursion.
priv struct FkmState {
  k : Int
  n : Int
  a : Array[Int] // 1-indexed (index 0 unused), length n + 1
  output : Array[Int]
}

// ---------------------------------------------------------------------------
// FKM recursive visit
// ---------------------------------------------------------------------------

///|
/// Recursively generate Lyndon words and append those whose length divides n
/// to the output buffer.
fn fkm_visit(state : FkmState, t : Int, p : Int) -> Unit {
  if t > state.n {
    // Lyndon word of length p: include only if p divides n.
    if state.n % p == 0 {
      for i = 1; i <= p; i = i + 1 {
        state.output.push(state.a[i])
      }
    }
  } else {
    // Extend with the same character as position t − p.
    state.a[t] = state.a[t - p]
    fkm_visit(state, t + 1, p)
    // Try larger characters, which start a new period.
    let limit = state.a[t - p]
    for j = limit + 1; j < state.k; j = j + 1 {
      state.a[t] = j
      fkm_visit(state, t + 1, t)
    }
  }
}

// ---------------------------------------------------------------------------
// Public API — integer sequence
// ---------------------------------------------------------------------------

///|
/// Generate the lexicographically smallest de Bruijn sequence B(k, n) as a
/// `FixedArray[Int]` with values in `0 .. k−1`.
///
/// The returned array has length `kⁿ`. Every length-n window (cyclically) is a
/// distinct tuple in `0..k−1)^n`.
///
/// - `k`: alphabet size (≥ 1).
/// - `n`: subsequence length (≥ 1).
///
/// Returns an empty array if `k < 1` or `n < 1`. Returns `[0]` for `k = 1`
/// (any n), since B(1, n) is the single-symbol sequence "0".
pub fn de_bruijn(k : Int, n : Int) -> FixedArray[Int] {
  if k < 1 || n < 1 {
    return FixedArray::make(0, 0)
  }
  if k == 1 {
    return FixedArray::make(1, 0)
  }
  let state : FkmState = { k, n, a: Array::make(n + 1, 0), output: [], }
  fkm_visit(state, 1, 1)
  FixedArray::makei(state.output.length(), fn(i) { state.output[i] })
}

// ---------------------------------------------------------------------------
// Public API — string representation
// ---------------------------------------------------------------------------

///|
/// Digit/letter table for string output: 0-9, a-z (supports k ≤ 36).
/// Character codes: '0'=48..'9'=57, 'a'=97..'z'=122.

///|
/// Generate the lexicographically smallest de Bruijn sequence B(k, n) as a
/// `String`.
///
/// Uses characters `0–9` then `a–z` for alphabet symbols. Requires `k ≤ 36`.
/// For larger alphabets use [`de_bruijn`] (integer array) instead.
///
/// Returns an empty string if `k < 1`, `n < 1`, or `k > 36`.
pub fn de_bruijn_string(k : Int, n : Int) -> String {
  if k < 1 || n < 1 || k > 36 {
    return ""
  }
  let seq = de_bruijn(k, n)
  let sb = StringBuilder()
  for i = 0; i < seq.length(); i = i + 1 {
    let d = seq[i]
    let code = if d < 10 { 48 + d } else { 97 + (d - 10) }
    sb.write_char(code.unsafe_to_char())
  }
  sb.to_string()
}

// ---------------------------------------------------------------------------
// Public API — custom alphabet
// ---------------------------------------------------------------------------

///|
/// Generate a de Bruijn sequence using a custom alphabet.
///
/// Maps each symbol index `0 .. k−1` to `alphabet[idx]`. The returned
/// `FixedArray[Int]` contains the **character codes** of the mapped symbols.
///
/// - `alphabet`: the custom alphabet as a string (length = k).
/// - `n`: subsequence length.
///
/// Returns an empty array if the alphabet is empty or `n < 1`.
pub fn de_bruijn_custom(alphabet : String, n : Int) -> FixedArray[Int] {
  let k = alphabet.length()
  if k < 1 || n < 1 {
    return FixedArray::make(0, 0)
  }
  let seq = de_bruijn(k, n)
  FixedArray::makei(seq.length(), fn(i) { alphabet[seq[i]].to_int() })
}

// ---------------------------------------------------------------------------
// Verification
// ---------------------------------------------------------------------------

///|
/// Verify that `seq` is a valid de Bruijn sequence B(k, n).
///
/// Checks that:
/// 1. `seq.length() == kⁿ`.
/// 2. Every n-length window (cyclically) is distinct.
/// 3. Every symbol is in `0 .. k−1`.
///
/// Returns `true` if all checks pass.
pub fn verify_de_bruijn(seq : FixedArray[Int], k : Int, n : Int) -> Bool {
  if k < 1 || n < 1 {
    return false
  }
  // Expected length = k^n (computed with overflow guard).
  let expected_len = {
    let mut len = 1
    for i = 0; i < n; i = i + 1 {
      len = len * k
      if len > 10_000_000 {
        return false // refuse to verify absurdly large sequences
      }
    }
    len
  }
  if seq.length() != expected_len {
    return false
  }
  if k == 1 {
    // B(1, n) = [0], everything must be 0.
    for i = 0; i < seq.length(); i = i + 1 {
      if seq[i] != 0 {
        return false
      }
    }
    return true
  }
  // Check all symbols are in range.
  for i = 0; i < seq.length(); i = i + 1 {
    if seq[i] < 0 || seq[i] >= k {
      return false
    }
  }
  // Check all n-length windows are distinct.
  // Encode each window as an Int, collect, sort, and check for duplicates.
  let len = seq.length()
  let codes : Array[Int] = Array::make(len, 0)
  for start = 0; start < len; start = start + 1 {
    let mut code = 0
    for i = 0; i < n; i = i + 1 {
      code = code * k + seq[(start + i) % len]
    }
    codes[start] = code
  }
  // Simple insertion sort is too slow for large arrays; use Array.sort.
  codes.sort()
  for i = 1; i < len; i = i + 1 {
    if codes[i] == codes[i - 1] {
      return false
    }
  }
  true
}

// ---------------------------------------------------------------------------
// Helper: find the position of a given n-length pattern in the cyclic sequence
// ---------------------------------------------------------------------------

///|
/// Find the starting index of `pattern` in the cyclic de Bruijn sequence `seq`.
///
/// Returns `Some(index)` if found, `None` otherwise. The pattern must have
/// length `n` and all values in `0 .. k−1`.
pub fn find_in_de_bruijn(
  seq : FixedArray[Int],
  pattern : FixedArray[Int],
) -> Int? {
  let n = pattern.length()
  let len = seq.length()
  if n == 0 || len == 0 {
    return None
  }
  for start = 0; start < len; start = start + 1 {
    let mut match_ = true
    for i = 0; i < n; i = i + 1 {
      if seq[(start + i) % len] != pattern[i] {
        match_ = false
        break
      }
    }
    if match_ {
      return Some(start)
    }
  }
  None
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "de_bruijn: B(2,3) is the canonical sequence" {
  // The lexicographically smallest B(2,3) = 00010111.
  let seq = de_bruijn(2, 3)
  assert_eq(seq.length(), 8)
  assert_eq(seq[0], 0)
  assert_eq(seq[1], 0)
  assert_eq(seq[2], 0)
  assert_eq(seq[3], 1)
  assert_eq(seq[4], 0)
  assert_eq(seq[5], 1)
  assert_eq(seq[6], 1)
  assert_eq(seq[7], 1)
}

///|
test "de_bruijn: B(2,3) string representation" {
  let s = de_bruijn_string(2, 3)
  assert_eq(s, "00010111")
}

///|
test "de_bruijn: verify B(2,3)" {
  let seq = de_bruijn(2, 3)
  assert_true(verify_de_bruijn(seq, 2, 3))
}

///|
test "de_bruijn: verify B(2,1)" {
  // B(2,1) = 01 (every single bit appears once).
  let seq = de_bruijn(2, 1)
  assert_eq(seq.length(), 2)
  assert_true(verify_de_bruijn(seq, 2, 1))
}

///|
test "de_bruijn: verify B(3,2)" {
  let seq = de_bruijn(3, 2)
  assert_eq(seq.length(), 9) // 3^2 = 9
  assert_true(verify_de_bruijn(seq, 3, 2))
}

///|
test "de_bruijn: verify B(4,2)" {
  let seq = de_bruijn(4, 2)
  assert_eq(seq.length(), 16) // 4^2 = 16
  assert_true(verify_de_bruijn(seq, 4, 2))
}

///|
test "de_bruijn: verify B(2,4)" {
  let seq = de_bruijn(2, 4)
  assert_eq(seq.length(), 16) // 2^4 = 16
  assert_true(verify_de_bruijn(seq, 2, 4))
}

///|
test "de_bruijn: verify B(2,5)" {
  let seq = de_bruijn(2, 5)
  assert_eq(seq.length(), 32) // 2^5 = 32
  assert_true(verify_de_bruijn(seq, 2, 5))
}

///|
test "de_bruijn: B(1,n) = [0]" {
  let seq = de_bruijn(1, 5)
  assert_eq(seq.length(), 1)
  assert_eq(seq[0], 0)
  assert_true(verify_de_bruijn(seq, 1, 5))
}

///|
test "de_bruijn: B(2,3) is lexicographically smallest" {
  // The first few symbols should be the smallest possible.
  let seq = de_bruijn(2, 3)
  // Starts with 000 (the smallest 3-bit string).
  assert_eq(seq[0], 0)
  assert_eq(seq[1], 0)
  assert_eq(seq[2], 0)
  // The string representation should be "00010111".
  let s = de_bruijn_string(2, 3)
  assert_eq(s, "00010111")
}

///|
test "de_bruijn: all 3-bit patterns appear in B(2,3)" {
  let seq = de_bruijn(2, 3)
  // Check all 8 possible 3-bit patterns.
  for v = 0; v < 8; v = v + 1 {
    let pattern = FixedArray::make(3, 0)
    pattern[0] = (v >> 2) & 1
    pattern[1] = (v >> 1) & 1
    pattern[2] = v & 1
    let pos = find_in_de_bruijn(seq, pattern)
    assert_true(pos is Some(_))
  }
}

///|
test "de_bruijn: custom alphabet" {
  // Use alphabet "AB" instead of "01".
  let seq = de_bruijn_custom("AB", 3)
  assert_eq(seq.length(), 8)
  // Should be A A A B A B B B.
  assert_eq(seq[0], 65) // 'A' = 65
  assert_eq(seq[1], 65)
  assert_eq(seq[2], 65)
  assert_eq(seq[3], 66) // 'B' = 66
  assert_eq(seq[4], 65)
  assert_eq(seq[5], 66)
  assert_eq(seq[6], 66)
  assert_eq(seq[7], 66)
}

///|
test "de_bruijn: verify B(5,2)" {
  let seq = de_bruijn(5, 2)
  assert_eq(seq.length(), 25) // 5^2 = 25
  assert_true(verify_de_bruijn(seq, 5, 2))
}

///|
test "de_bruijn: verify B(3,3)" {
  let seq = de_bruijn(3, 3)
  assert_eq(seq.length(), 27) // 3^3 = 27
  assert_true(verify_de_bruijn(seq, 3, 3))
}

///|
test "de_bruijn: verify B(2,6)" {
  let seq = de_bruijn(2, 6)
  assert_eq(seq.length(), 64) // 2^6 = 64
  assert_true(verify_de_bruijn(seq, 2, 6))
}

///|
test "de_bruijn: invalid inputs return empty" {
  assert_eq(de_bruijn(0, 3).length(), 0)
  assert_eq(de_bruijn(2, 0).length(), 0)
  assert_eq(de_bruijn(-1, 3).length(), 0)
  assert_eq(de_bruijn(2, -1).length(), 0)
  assert_eq(de_bruijn_string(37, 3), "")
  assert_eq(de_bruijn_string(0, 3), "")
}

///|
test "de_bruijn: reject invalid sequence in verify" {
  // Wrong length.
  let bad1 = FixedArray::make(7, 0)
  assert_false(verify_de_bruijn(bad1, 2, 3))
  // Right length but not de Bruijn (all zeros).
  let bad2 = FixedArray::make(8, 0)
  assert_false(verify_de_bruijn(bad2, 2, 3))
}

///|
test "de_bruijn: B(10,2) verify" {
  let seq = de_bruijn(10, 2)
  assert_eq(seq.length(), 100) // 10^2 = 100
  assert_true(verify_de_bruijn(seq, 10, 2))
}

///|
test "de_bruijn: find_in_de_bruijn returns correct position" {
  let seq = de_bruijn(2, 3)
  // B(2,3) = 0 0 0 1 0 1 1 1
  // Find pattern 101 → window at position 3: seq[3]=1, seq[4]=0, seq[5]=1.
  let pattern = FixedArray::make(3, 0)
  pattern[0] = 1
  pattern[1] = 0
  pattern[2] = 1
  match find_in_de_bruijn(seq, pattern) {
    Some(pos) => assert_eq(pos, 3)
    None => fail("pattern 101 should be found")
  }
}

///|
test "de_bruijn: B(2,3) string is cyclic" {
  // The cyclic version of "00010111" should have all 8 patterns.
  // Verify using the integer array directly.
  let seq = de_bruijn(2, 3)
  let len = seq.length()
  // Build a list of all 3-element window codes (cyclically) and check distinctness.
  let codes : Array[Int] = []
  for i = 0; i < len; i = i + 1 {
    let code = seq[i] * 4 + seq[(i + 1) % len] * 2 + seq[(i + 2) % len]
    codes.push(code)
  }
  codes.sort()
  for i = 1; i < codes.length(); i = i + 1 {
    assert_true(codes[i] != codes[i - 1])
  }
  assert_eq(codes.length(), 8) // all 8 substrings distinct
}
