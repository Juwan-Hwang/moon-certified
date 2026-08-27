/// Shared utility functions used across multiple algorithm packages.
///
/// This module eliminates code duplication for common operations that are
/// needed by several packages (e.g. lexicographic string comparison, array
/// element swapping). Centralising these utilities ensures consistent
/// behaviour and simplifies maintenance.

///|
/// Global instance counter for per-instance seed derivation.
///
/// Each call to `fresh_seed()` increments this counter and combines it with
/// a base seed, ensuring that distinct instances of Treap, KMeans, etc.
/// receive different initial RNG states even when created with the same
/// default parameters. This prevents the "all instances share the same
/// priority sequence" pitfall while remaining fully deterministic within
/// a single process run.
let instance_counter : Ref[Int] = { val: 0, }

///|
/// Derive a fresh non-zero seed for a new algorithm instance.
///
/// Combines a base seed with a monotonically increasing instance counter
/// so that successive calls return different values:
///
/// ```moonbit nocheck
/// let s1 = fresh_seed(0x1A2B3C4D) // e.g. 0x1A2B3C4E
///
/// let s2 = fresh_seed(0x1A2B3C4D) // e.g. 0x1A2B3C4F
/// ```
///
/// The result is always a positive 31-bit integer (masked to `[1, 2^31)`),
/// suitable as an LCG seed.
pub fn fresh_seed(base : Int) -> Int {
  instance_counter.val = instance_counter.val + 1
  let s = (base ^ instance_counter.val) & 0x7FFFFFFF
  if s == 0 {
    1
  } else {
    s
  }
}

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

///|
/// Approximate equality for floating-point numbers.
///
/// Uses a hybrid absolute/relative tolerance: two values are considered
/// equal if their difference is less than `1e-6` in absolute terms, or
/// less than `1e-6` times the sum of their magnitudes (relative terms).
/// This handles both near-zero and large values gracefully.
///
/// This is the canonical implementation shared across all algorithm
/// packages to eliminate duplication.
pub fn approx_eq(a : Double, b : Double) -> Bool {
  let diff = (a - b).abs()
  diff < 1.0e-6 || diff < 1.0e-6 * (a.abs() + b.abs())
}
