/// Shared utility functions used across multiple algorithm packages.
///
/// This module eliminates code duplication for common operations that are
/// needed by several packages (e.g. lexicographic string comparison, array
/// element swapping). Centralising these utilities ensures consistent
/// behaviour and simplifies maintenance.

///|
/// Lexicographic string comparator: compares character-by-character, then
/// by length. Returns a negative value when `a` precedes `b`, zero when
/// equal, and a positive value when `a` follows `b`.
///
/// MoonBit's default `Compare` for `String` uses shortlex (length-first)
/// ordering, which differs from the standard lexicographic order that most
/// algorithms expect. This function provides the conventional
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

///|
/// Swap two elements in an `Array[T]` at indices `i` and `j`.
pub fn[T] swap_array(arr : Array[T], i : Int, j : Int) -> Unit {
  let tmp = arr[i]
  arr[i] = arr[j]
  arr[j] = tmp
}

///|
/// Swap two elements in a `FixedArray[T]` at indices `i` and `j`.
pub fn[T] swap_fixed(arr : FixedArray[T], i : Int, j : Int) -> Unit {
  let tmp = arr[i]
  arr[i] = arr[j]
  arr[j] = tmp
}

///|
/// Round up to the next power of two. Returns `n` if it is already a power
/// of two. For `n <= 0`, returns `1`.
pub fn next_pow2(n : Int) -> Int {
  if n <= 1 {
    return 1
  }
  let mut m = n - 1
  m = m | (m >> 1)
  m = m | (m >> 2)
  m = m | (m >> 4)
  m = m | (m >> 8)
  m = m | (m >> 16)
  m + 1
}
