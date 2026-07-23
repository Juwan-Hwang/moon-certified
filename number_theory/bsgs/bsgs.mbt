/// Baby-Step Giant-Step (BSGS) discrete logarithm.
///
/// Solves a^x ≡ b (mod p) for the smallest non-negative x, where p is a
/// positive modulus and gcd(a, p) = 1 (automatically satisfied when p is
/// prime and a is not a multiple of p).
///
/// **Algorithm.** Let m = ⌈√p⌉. We seek x = i·m + j with 0 ≤ j < m.
/// Then a^j ≡ b · (a^{-m})^i (mod p).
///   Baby step: precompute a^j mod p for j = 0..m-1, store in a sorted table.
///   Giant step: compute g = a^{-m} mod p, then for i = 0..m-1,
///     check if b · g^i mod p appears in the baby-step table.
///   If found, return i·m + j.
///
/// **Complexity.** O(√p · log p) time (√p for the table, log p for each
/// binary search), O(√p) space.
///
/// **Overflow safety.** All arithmetic is performed in `Int64`. Since
/// p < 2^31, every intermediate product is below p^2 < 2^62 < 2^63, so
/// no `Int64` overflow can occur.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

// ---------------------------------------------------------------------------
// Int64 helpers (self-contained, no cross-package dependency)
// ---------------------------------------------------------------------------

/// Int64 modulo that always returns a result in [0, m) for m > 0.
fn mod64(a : Int64, m : Int64) -> Int64 {
  let r = a % m
  if r < 0L {
    r + m
  } else {
    r
  }
}

/// Modular exponentiation in `Int64`: returns (base^exp) mod m.
/// Requires m > 0, exp >= 0. Uses binary exponentiation; for 32-bit moduli
/// every intermediate product stays below m^2 < 2^62.
fn pow_mod64(base : Int64, exp : Int64, m : Int64) -> Int64 {
  let mut result = 1L
  let mut b = mod64(base, m)
  let mut e = exp
  while e > 0L {
    if e % 2L == 1L {
      result = result * b % m
    }
    e = e / 2L
    b = b * b % m
  }
  result
}

/// Int64 GCD (Euclidean algorithm).
fn gcd64(a : Int64, b : Int64) -> Int64 {
  let mut x = a
  let mut y = b
  while y != 0L {
    let t = x % y
    x = y
    y = t
  }
  x
}

/// Int64 modular inverse via the extended Euclidean algorithm.
///
/// Returns `Some(inv)` with a · inv ≡ 1 (mod m), or `None` when
/// gcd(a, m) ≠ 1. The result lies in [0, m).
fn mod_inv64(a : Int64, m : Int64) -> Int64? {
  let a_n = mod64(a, m)
  let mut old_r = a_n
  let mut r = m
  let mut old_s = 1L
  let mut s = 0L
  while r != 0L {
    let q = old_r / r
    let new_r = old_r - q * r
    old_r = r
    r = new_r
    let new_s = old_s - q * s
    old_s = s
    s = new_s
  }
  if old_r != 1L {
    None
  } else {
    Some(mod64(old_s, m))
  }
}

/// Integer square root ceiling: smallest r with r · r >= n, for n > 0.
/// Uses binary search with Int64 to avoid overflow.
fn isqrt_ceil(n : Int) -> Int {
  if n <= 0 {
    return 0
  }
  let n64 = n.to_int64()
  let mut lo = 1
  let mut hi = n
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    let mid64 = mid.to_int64()
    if mid64 * mid64 >= n64 {
      hi = mid
    } else {
      lo = mid + 1
    }
  }
  lo
}

// ---------------------------------------------------------------------------
// Sorted-table infrastructure for the baby-step phase
// ---------------------------------------------------------------------------

/// Stable merge sort of `(Int64, Int)` pairs by the first element.
/// Sorts `arr[lo, hi)` in place using `tmp` as scratch.
fn msort_pairs(
  arr : Array[(Int64, Int)],
  lo : Int,
  hi : Int,
  tmp : Array[(Int64, Int)],
) -> Unit {
  let len = hi - lo
  if len <= 1 {
    return
  }
  let mid = lo + len / 2
  msort_pairs(arr, lo, mid, tmp)
  msort_pairs(arr, mid, hi, tmp)
  let mut i = lo
  let mut j = mid
  for k = lo; k < hi; k = k + 1 {
    if j >= hi || (i < mid && arr[i].0 <= arr[j].0) {
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

/// Binary search for `val` in a sorted array of `(Int64, Int)` pairs.
///
/// Assumes `arr` is sorted ascending by the first element with duplicates
/// removed (or at least the first occurrence kept). Returns `Some(j)` if
/// found, `None` otherwise.
fn bsearch_pairs(arr : Array[(Int64, Int)], val : Int64) -> Int? {
  let mut lo = 0
  let mut hi = arr.length()
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    if arr[mid].0 < val {
      lo = mid + 1
    } else if arr[mid].0 > val {
      hi = mid
    } else {
      return Some(arr[mid].1)
    }
  }
  None
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Solve the discrete logarithm a^x ≡ b (mod p).
///
/// Returns `Some(x)` with the smallest non-negative x satisfying the
/// congruence, or `None` if no solution exists or the input is invalid.
///
/// **Preconditions.** `p > 0` and `gcd(a, p) = 1` (the latter is automatic
/// when p is prime and a is not a multiple of p). When `gcd(a, p) > 1` and
/// `a` is not zero, `None` is returned even if a solution might exist.
///
/// **Edge cases handled.**
/// - `p == 1`: every integer is 0 mod 1; returns `Some(0)`.
/// - `b ≡ 1 (mod p)`: a^0 = 1; returns `Some(0)`.
/// - `a ≡ 0 (mod p)`: a^x = 0 for x ≥ 1; returns `Some(1)` if b ≡ 0,
///   `None` otherwise.
pub fn discrete_log(a : Int, b : Int, p : Int) -> Int? {
  if p <= 0 {
    return None
  }
  if p == 1 {
    return Some(0)
  }
  let p64 = p.to_int64()
  let a64 = mod64(a.to_int64(), p64)
  let b64 = mod64(b.to_int64(), p64)

  // a^0 = 1 ≡ b (mod p)
  if b64 == 1L {
    return Some(0)
  }

  // a ≡ 0 (mod p): a^x = 1 for x=0, 0 for x ≥ 1
  if a64 == 0L {
    if b64 == 0L {
      return Some(1)
    }
    return None
  }

  // BSGS requires gcd(a, p) = 1 to compute the modular inverse.
  if gcd64(a64, p64) != 1L {
    return None
  }

  let m = isqrt_ceil(p)
  let m64 = m.to_int64()

  // --- Baby step: build sorted table of (a^j mod p, j) for j = 0..m-1 ---
  let baby : Array[(Int64, Int)] = []
  let mut cur = 1L // a^0 = 1
  for j = 0; j < m; j = j + 1 {
    baby.push((cur, j))
    cur = cur * a64 % p64
  }
  // Stable sort by value; ties keep the smaller j (which comes first since
  // we iterate j in increasing order).
  let tmp : Array[(Int64, Int)] = []
  for j = 0; j < m; j = j + 1 {
    tmp.push((0L, 0))
  }
  msort_pairs(baby, 0, m, tmp)
  // Deduplicate: keep only the first (smallest j) occurrence of each value.
  let unique : Array[(Int64, Int)] = []
  if m > 0 {
    unique.push(baby[0])
    for k = 1; k < m; k = k + 1 {
      if baby[k].0 != baby[k - 1].0 {
        unique.push(baby[k])
      }
    }
  }

  // --- Giant step: search for b · (a^{-m})^i in the baby-step table ---
  // a^m mod p
  let am = pow_mod64(a64, m64, p64)
  // a^{-m} mod p (safe: gcd(a, p) = 1 implies gcd(a^m, p) = 1)
  let inv_am = match mod_inv64(am, p64) {
    None => return None // unreachable given gcd(a, p) = 1
    Some(inv) => inv
  }

  let mut g = b64 // b · (a^{-m})^0 = b
  for i = 0; i < m; i = i + 1 {
    match bsearch_pairs(unique, g) {
      Some(j) => return Some(i * m + j)
      None => ()
    }
    g = g * inv_am % p64
  }
  None
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "discrete_log: basic" {
  // 2^x ≡ 3 (mod 5). 2^0=1, 2^1=2, 2^2=4, 2^3=3. Answer: x=3.
  assert_eq(discrete_log(2, 3, 5), Some(3))
}

test "discrete_log: b is one" {
  // a^0 = 1, so any a with b=1 gives x=0.
  assert_eq(discrete_log(3, 1, 7), Some(0))
  assert_eq(discrete_log(123, 1, 997), Some(0))
}

test "discrete_log: no solution" {
  // 2^x mod 7 cycles through 1,2,4,1,...; 3 never appears.
  assert_true(discrete_log(2, 3, 7) is None)
}

test "discrete_log: generator of Z_7*" {
  // 3 is a primitive root mod 7: 3^0=1, 3^1=3, 3^2=2, 3^3=6, 3^4=4, 3^5=5.
  assert_eq(discrete_log(3, 1, 7), Some(0))
  assert_eq(discrete_log(3, 3, 7), Some(1))
  assert_eq(discrete_log(3, 2, 7), Some(2))
  assert_eq(discrete_log(3, 6, 7), Some(3))
  assert_eq(discrete_log(3, 4, 7), Some(4))
  assert_eq(discrete_log(3, 5, 7), Some(5))
}

test "discrete_log: primitive root mod large prime" {
  // 5 is a primitive root mod 1000003 (a prime).
  // 5^1000002 ≡ 1 (mod 1000003) by Fermat's little theorem.
  // Verify round-trip: for each x, 5^x mod p should give b, and
  // discrete_log(5, b, p) should give back x.
  let p = 1000003
  let mut a_pow = 1 // 5^0 = 1
  for x = 0; x < 100; x = x + 1 {
    let result = discrete_log(5, a_pow, p)
    assert_eq(result, Some(x))
    a_pow = a_pow * 5 % p
  }
}

test "discrete_log: a is zero" {
  // 0^x = 0 for x >= 1, 0^0 = 1.
  assert_eq(discrete_log(0, 0, 7), Some(1))
  assert_eq(discrete_log(0, 1, 7), Some(0)) // 0^0 = 1 ≡ b
  assert_true(discrete_log(0, 3, 7) is None)
}

test "discrete_log: b is zero with coprime a" {
  // If gcd(a, p) = 1, a^x is never 0 mod p, so no solution.
  assert_true(discrete_log(2, 0, 7) is None)
}

test "discrete_log: negative a and b" {
  // -2 mod 5 = 3; 3^x ≡ -3 mod 5 → 3^x ≡ 2 mod 5.
  // 3^0=1, 3^1=3, 3^2=4, 3^3=2. Answer: x=3.
  assert_eq(discrete_log(-2, -3, 5), Some(3))
}

test "discrete_log: p equals one" {
  assert_eq(discrete_log(5, 3, 1), Some(0))
}

test "discrete_log: p non-positive" {
  assert_true(discrete_log(2, 3, 0) is None)
  assert_true(discrete_log(2, 3, -1) is None)
}

test "discrete_log: large prime near Int max" {
  // 2147483647 = 2^31 - 1 is a Mersenne prime (M31).
  // 7 is a primitive root mod M31.
  // Verify: 7^1 mod p = 7, so discrete_log(7, 7, p) = 1.
  let p = 2147483647
  assert_eq(discrete_log(7, 7, p), Some(1))
  // 7^2 = 49
  assert_eq(discrete_log(7, 49, p), Some(2))
  // 7^0 = 1
  assert_eq(discrete_log(7, 1, p), Some(0))
}

test "discrete_log: b equals one returns zero before coprimality" {
  // b=1 should return Some(0) regardless of gcd(a, p), since a^0 = 1.
  assert_eq(discrete_log(6, 1, 9), Some(0))
}

test "discrete_log: non-coprime a with non-trivial b returns None" {
  // gcd(6, 9) = 3 ≠ 1; BSGS cannot compute the inverse for non-trivial b.
  assert_true(discrete_log(6, 3, 9) is None)
}

test "discrete_log: exhaustive check mod 11" {
  // 2 is a primitive root mod 11. Check all residues.
  let p = 11
  let powers = FixedArray::make(p, 0)
  let mut cur = 1
  for x = 0; x < p - 1; x = x + 1 {
    powers[x] = cur
    cur = cur * 2 % p
  }
  // powers = [1, 2, 4, 8, 5, 10, 9, 7, 3, 6]
  for x = 0; x < p - 1; x = x + 1 {
    assert_eq(discrete_log(2, powers[x], p), Some(x))
  }
  // 0 is not in the subgroup generated by 2.
  assert_true(discrete_log(2, 0, p) is None)
}
