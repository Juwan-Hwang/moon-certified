/// Shared test utilities used across multiple algorithm test suites.
///
/// These functions are **test-only**: they exist to eliminate boilerplate
/// (e.g. the `str_cmp` comparator that was previously copy-pasted into 11+
/// test files) and are not part of the public algorithm library API.

/// Lexicographic string comparator: compares character-by-character, then
/// by length. Returns a negative value when `a` precedes `b`, zero when
/// equal, and a positive value when `a` follows `b`.
///
/// MoonBit's default `Compare` for `String` uses shortlex (length-first)
/// ordering, which differs from the standard lexicographic order that most
/// algorithm tests expect. This function provides the conventional
/// character-by-character comparison.
pub fn str_cmp(a : String, b : String) -> Int {
  let la = a.length()
  let lb = b.length()
  let min = if la < lb { la } else { lb }
  for k = 0; k < min; k = k + 1 {
    let ca = a[k].to_int()
    let cb = b[k].to_int()
    if ca < cb {
      return -1
    }
    if ca > cb {
      return 1
    }
  }
  la - lb
}
