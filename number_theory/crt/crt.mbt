/// Chinese Remainder Theorem (CRT) solver.
///
/// Solves systems of simultaneous congruences
///   x ≡ r1 (mod m1),  x ≡ r2 (mod m2),  ...
/// including the case where the moduli are not pairwise coprime.
///
/// **Algorithm.** For two congruences, let g = gcd(m1, m2). A solution exists
/// iff g | (r2 - r1). When it exists, the extended Euclidean algorithm yields
/// Bézout coefficients (p, q) with m1*p + m2*q = g, and the unique solution
/// modulo lcm(m1, m2) is
///   x ≡ r1 + m1 * ((r2 - r1)/g) * p   (mod lcm(m1, m2)).
/// Larger systems are reduced by repeatedly merging pairs.
///
/// **Complexity.** O(log(min(m1, m2))) per merge, dominated by the extended
/// Euclidean algorithm. A system of k congruences costs O(k * log M) where M
/// is the largest modulus seen.
///
/// **Overflow safety.** All arithmetic is performed in `Int64`. Because each
/// modulus is a 32-bit `Int`, intermediate products stay below 2^62 < 2^63 and
/// never overflow `Int64`. The canonical solution lies in [0, lcm); the caller
/// must keep the combined modulus within `Int`'s positive range (as the test
/// inputs do) for the returned `Int` to be the exact representative.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below,
/// which includes congruence-consistency, no-solution and multi-congruence
/// checks.

/// `Int64` modulo that always returns a result in [0, m) for m > 0.
fn mod64(a : Int64, m : Int64) -> Int64 {
  let r = a % m
  if r < 0L {
    r + m
  } else {
    r
  }
}

/// Extended Euclidean algorithm on `Int64`.
///
/// Returns (g, x, y) with a*x + b*y == g == gcd(a, b). Implemented
/// iteratively so the Bézout coefficients stay naturally bounded; for 32-bit
/// inputs every value remains well within `Int64` range.
fn ext_gcd64(a : Int64, b : Int64) -> (Int64, Int64, Int64) {
  let mut old_r = a
  let mut r = b
  let mut old_s = 1L
  let mut s = 0L
  let mut old_t = 0L
  let mut t = 1L
  while r != 0L {
    let q = old_r / r
    let new_r = old_r - q * r
    old_r = r
    r = new_r
    let new_s = old_s - q * s
    old_s = s
    s = new_s
    let new_t = old_t - q * t
    old_t = t
    t = new_t
  }
  (old_r, old_s, old_t)
}

/// Merge two congruences x ≡ r1 (mod m1) and x ≡ r2 (mod m2).
///
/// Requires m1 > 0 and m2 > 0. Returns `Some((x, lcm))` with
/// `0 <= x < lcm(m1, m2)`, or `None` when no solution exists
/// (g does not divide r2 - r1).
fn crt_combine64(
  r1 : Int64,
  m1 : Int64,
  r2 : Int64,
  m2 : Int64
) -> (Int64, Int64)? {
  let r1n = mod64(r1, m1)
  let r2n = mod64(r2, m2)
  let (g, p, _) = ext_gcd64(m1, m2)
  let diff = r2n - r1n
  if diff % g != 0L {
    return None
  }
  let lcm = m1 / g * m2
  let mod_k = m2 / g
  // k ≡ (diff / g) * p (mod mod_k); reduce each factor first to bound the product.
  let k = mod64(mod64(diff / g, mod_k) * mod64(p, mod_k), mod_k)
  let x = mod64(m1 * k + r1n, lcm)
  Some((x, lcm))
}

/// Solve the two-congruence system
///   x ≡ r1 (mod m1),  x ≡ r2 (mod m2).
///
/// Returns `Some(x)` with `0 <= x < lcm(m1, m2)`, or `None` if no solution
/// exists (when `gcd(m1, m2)` does not divide `r2 - r1`) or when a modulus is
/// not positive. Remainders are normalised into `[0, m)` first, so negative
/// remainders are accepted.
pub fn crt(r1 : Int, m1 : Int, r2 : Int, m2 : Int) -> Int? {
  if m1 <= 0 || m2 <= 0 {
    return None
  }
  match crt_combine64(r1.to_int64(), m1.to_int64(), r2.to_int64(), m2.to_int64()) {
    None => None
    Some((x, _)) => Some(x.to_int())
  }
}

/// Solve a system of congruences
///   x ≡ remainders[i] (mod moduli[i])   for i = 0 .. k-1
/// by repeatedly merging pairs.
///
/// Returns `Some(x)` with `0 <= x < lcm(moduli[0], ..., moduli[k-1])`, or
/// `None` if any modulus is non-positive, the two arrays differ in length, the
/// system is empty, or the system is inconsistent (some pair has no solution).
pub fn crt_system(
  remainders : FixedArray[Int],
  moduli : FixedArray[Int]
) -> Int? {
  let n = remainders.length()
  if n == 0 || n != moduli.length() {
    return None
  }
  if moduli[0] <= 0 {
    return None
  }
  let mut cur_r = mod64(remainders[0].to_int64(), moduli[0].to_int64())
  let mut cur_m = moduli[0].to_int64()
  for i = 1; i < n; i = i + 1 {
    if moduli[i] <= 0 {
      return None
    }
    match crt_combine64(
      cur_r,
      cur_m,
      remainders[i].to_int64(),
      moduli[i].to_int64()
    ) {
      None => return None
      Some((x, m)) => {
        cur_r = x
        cur_m = m
      }
    }
  }
  Some(cur_r.to_int())
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "crt: basic two congruences" {
  // x ≡ 2 (mod 3), x ≡ 3 (mod 5) -> x = 8 (mod 15).
  assert_eq(crt(2, 3, 3, 5), Some(8))
}

test "crt: symmetric in argument order" {
  // Swapping the two congruences yields the same solution.
  assert_eq(crt(3, 5, 2, 3), Some(8))
}

test "crt: no solution when gcd does not divide the difference" {
  // gcd(4, 6) = 2 does not divide 2 - 1 = 1.
  assert_true(crt(1, 4, 2, 6) is None)
  // gcd(6, 4) = 2 does not divide 2 - 3 = -1.
  assert_true(crt(3, 6, 2, 4) is None)
}

test "crt: non-coprime moduli, solvable" {
  // gcd(4, 6) = 2 divides 3 - 1 = 2; lcm = 12.
  assert_eq(crt(1, 4, 3, 6), Some(9))
  assert_eq(crt(2, 4, 4, 6), Some(10))
}

test "crt: modulus of one is absorbed" {
  // x ≡ 0 (mod 1) is trivially satisfied, leaving x ≡ 7 (mod 9).
  assert_eq(crt(0, 1, 7, 9), Some(7))
  // Both moduli are 1, so every x is a solution; the canonical rep is 0.
  assert_eq(crt(5, 1, 9, 1), Some(0))
}

test "crt: negative remainders are normalised" {
  // -1 ≡ 2 (mod 3), so this equals the basic case (solution 8).
  assert_eq(crt(-1, 3, 3, 5), Some(8))
  // -2 ≡ 3 (mod 5), again the basic case.
  assert_eq(crt(2, 3, -2, 5), Some(8))
}

test "crt: large coprime moduli" {
  // 10007 and 10009 are coprime; lcm = 100160063 (< 2^31).
  let x = crt(5, 10007, 7, 10009)
  assert_eq(x, Some(100150061))
  let v = x.unwrap()
  assert_eq(v % 10007, 5)
  assert_eq(v % 10009, 7)
  assert_true(v >= 0)
  assert_true(v < 100160063)
}

test "crt: moduli near the Int32 sqrt limit" {
  // 46337 and 46327 are coprime; lcm = 2146654199 (< 2^31), so the
  // intermediate products approach 2^31 and exercise the Int64 path.
  let x = crt(11, 46337, 13, 46327)
  assert_eq(x, Some(858670958))
  let v = x.unwrap()
  assert_eq(v % 46337, 11)
  assert_eq(v % 46327, 13)
  assert_true(v >= 0)
  assert_true(v < 2146654199)
}

test "crt: non-positive modulus returns None" {
  assert_true(crt(2, 0, 3, 5) is None)
  assert_true(crt(2, 3, 3, 0) is None)
  assert_true(crt(2, -3, 3, 5) is None)
}

test "crt: solution satisfies both congruences" {
  let cases = [
    (2, 3, 3, 5),
    (1, 4, 3, 6),
    (2, 4, 4, 6),
    (5, 10007, 7, 10009),
    (11, 46337, 13, 46327),
  ]
  for i = 0; i < cases.length(); i = i + 1 {
    let (r1, m1, r2, m2) = cases[i]
    let res = crt(r1, m1, r2, m2)
    assert_true(res is Some(_))
    let v = res.unwrap()
    let r1n = if r1 % m1 < 0 { r1 % m1 + m1 } else { r1 % m1 }
    let r2n = if r2 % m2 < 0 { r2 % m2 + m2 } else { r2 % m2 }
    assert_eq(v % m1, r1n)
    assert_eq(v % m2, r2n)
    assert_true(v >= 0)
    let (g, _, _) = ext_gcd64(m1.to_int64(), m2.to_int64())
    let lcm = m1.to_int64() / g * m2.to_int64()
    assert_true(v.to_int64() < lcm)
  }
}

test "crt_system: Sun Tzu's problem" {
  // x ≡ 2 (mod 3), x ≡ 3 (mod 5), x ≡ 2 (mod 7) -> x = 23 (mod 105).
  let rs = FixedArray::from_array([2, 3, 2])
  let ms = FixedArray::from_array([3, 5, 7])
  assert_eq(crt_system(rs, ms), Some(23))
}

test "crt_system: non-coprime moduli" {
  // moduli 4, 6, 15 share factors; the system is still consistent -> 34.
  let rs = FixedArray::from_array([2, 4, 4])
  let ms = FixedArray::from_array([4, 6, 15])
  assert_eq(crt_system(rs, ms), Some(34))
}

test "crt_system: single congruence" {
  let rs = FixedArray::from_array([5])
  let ms = FixedArray::from_array([7])
  assert_eq(crt_system(rs, ms), Some(5))
  // Negative remainder normalised into [0, m): -3 ≡ 4 (mod 7).
  let rs2 = FixedArray::from_array([-3])
  let ms2 = FixedArray::from_array([7])
  assert_eq(crt_system(rs2, ms2), Some(4))
}

test "crt_system: three coprime moduli round-trip" {
  // 500000 mod {97, 101, 103} = {62, 50, 38}; lcm = 1009091.
  let rs = FixedArray::from_array([62, 50, 38])
  let ms = FixedArray::from_array([97, 101, 103])
  assert_eq(crt_system(rs, ms), Some(500000))
}

test "crt_system: larger coprime moduli" {
  // lcm = 1041537223 (< 2^31).
  let rs = FixedArray::from_array([545, 591, 690])
  let ms = FixedArray::from_array([1009, 1013, 1019])
  assert_eq(crt_system(rs, ms), Some(500000))
}

test "crt_system: inconsistent system returns None" {
  // x ≡ 2 (mod 4), x ≡ 4 (mod 6) -> x = 10 (mod 12), i.e. x ≡ 1 (mod 3),
  // but x ≡ 0 (mod 9) forces x ≡ 0 (mod 3): contradiction.
  let rs = FixedArray::from_array([2, 4, 0])
  let ms = FixedArray::from_array([4, 6, 9])
  assert_true(crt_system(rs, ms) is None)
}

test "crt_system: empty system returns None" {
  let rs = FixedArray::make(0, 0)
  let ms = FixedArray::make(0, 0)
  assert_true(crt_system(rs, ms) is None)
}

test "crt_system: mismatched lengths return None" {
  let rs = FixedArray::from_array([1, 2])
  let ms = FixedArray::from_array([3])
  assert_true(crt_system(rs, ms) is None)
}

test "crt_system: non-positive modulus returns None" {
  let rs = FixedArray::from_array([2, 3])
  let ms = FixedArray::from_array([3, 0])
  assert_true(crt_system(rs, ms) is None)
  let ms2 = FixedArray::from_array([3, -5])
  assert_true(crt_system(rs, ms2) is None)
}

test "crt_system: solution satisfies every congruence" {
  let rs = FixedArray::from_array([2, 3, 2])
  let ms = FixedArray::from_array([3, 5, 7])
  let res = crt_system(rs, ms)
  assert_true(res is Some(_))
  let v = res.unwrap()
  for i = 0; i < rs.length(); i = i + 1 {
    assert_eq(v % ms[i], rs[i])
  }
}
