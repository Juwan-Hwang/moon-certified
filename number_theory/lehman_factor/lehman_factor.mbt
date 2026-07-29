/// Lehman integer factorization.
///
/// An O(n^{1/3}) deterministic factoring algorithm due to R. Sherman Lehman.
/// It bridges the gap between trial division (O(√n)) and modern sub-exponential
/// methods (quadratic sieve, number-field sieve), making it practical for
/// numbers up to ~10^{15}.
///
/// **Key idea.** If n = pq with n^{1/3} < p ≤ q, then there exists an integer
/// k ∈ [1, ⌈n^{1/3}⌉] and an integer a near √(kn) such that
///
///   a² − k·n = b²      (a perfect square)
///
/// Writing n = (a² − b²)/k = (a−b)(a+b)/k, a non-trivial factor can be
/// extracted as gcd(a ± b, n). The range of a to check for each k is narrow —
/// roughly n^{1/6} / (4√k) values — so the total work across all k sums to
/// O(n^{1/3}).
///
/// **Algorithm.**
/// 1. Remove small factors by trial division up to n^{1/3}.
/// 2. For k = 1 … ⌈n^{1/3}⌉:
///      a₀ = ⌈√(k·n)⌉
///      for a = a₀ … a₀ + ⌈n^{1/6} / (4√k)⌉ + 1:
///        b² = a² − k·n
///        if b² is a perfect square:
///          d = gcd(a − b, n);  if 1 < d < n → return d
///          d = gcd(a + b, n);  if 1 < d < n → return d
///
/// **Overflow safety.** All arithmetic is in Int64. For 32-bit Int inputs
/// (n < 2³¹), k·n < 2^{41} and a² < 2^{42}, both well within Int64 range.
/// Cube-root and square-root helpers use Newton's method, which converges
/// monotonically and never overflows for this input range.
///
/// **Reference.**
/// - R. S. Lehman, "Factoring Large Integers", Mathematics of Computation
///   28(126), 637–646 (1974).
/// - H. Riesel, "Prime Numbers and Computer Methods for Factorization",
///   2nd ed., Birkhäuser 1994, §6.5.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below,
/// which verifies factors against known factorisations and primality.

// ---------------------------------------------------------------------------
// Integer root helpers (Int64)
// ---------------------------------------------------------------------------

///|
/// Bit length of a non-negative Int64 (position of the highest set bit + 1).
fn bit_length64(n : Int64) -> Int {
  let mut bits = 0
  let mut v = n
  while v > 0L {
    bits = bits + 1
    v = v >> 1
  }
  bits
}

///|
/// Integer cube root: floor(n^{1/3}) for n ≥ 0.
///
/// Newton's method x ← (2x + n/x²)/3 with a bit-length-based initial guess,
/// followed by a ±1 correction. For 32-bit inputs x < 2^{11}, so x³ < 2^{33}
/// — no Int64 overflow.
fn icbrt64(n : Int64) -> Int64 {
  if n <= 0L {
    return 0L
  }
  if n < 8L {
    return 1L
  }
  let bl = bit_length64(n)
  let mut x = 1L << ((bl + 2) / 3)
  let mut y = (2L * x + n / (x * x)) / 3L
  while y < x {
    x = y
    y = (2L * x + n / (x * x)) / 3L
  }
  // Newton converges from above; correct the ±1 error from truncation.
  while x * x * x > n {
    x = x - 1L
  }
  while (x + 1L) * (x + 1L) * (x + 1L) <= n {
    x = x + 1L
  }
  x
}

///|
/// Integer square root: floor(√n) for n ≥ 0.
///
/// Newton's method x ← (x + n/x)/2, which converges monotonically from above.
fn isqrt64(n : Int64) -> Int64 {
  if n <= 0L {
    return 0L
  }
  let mut x = n
  let mut y = (x + 1L) / 2L
  while y < x {
    x = y
    y = (x + n / x) / 2L
  }
  x
}

///|
/// Ceiling square root: ceil(√n) for n > 0.
fn isqrt_ceil64(n : Int64) -> Int64 {
  let s = isqrt64(n)
  if s * s == n {
    s
  } else {
    s + 1L
  }
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

///|
/// Find a non-trivial factor of `n` using Lehman's algorithm.
///
/// Returns `Some(d)` with `1 < d < n` and `n % d == 0`, or `None` when:
/// - `n ≤ 1` (no factor to find),
/// - `n` is prime (determined by deterministic Miller–Rabin via
///   `@int64_utils.is_prime64`),
/// - the algorithm exhausts its search without finding a factor
///   (theoretically impossible for composite odd `n`, but retained as a
///   safety net).
///
/// **Complexity.** O(n^{1/3}) arithmetic operations.
pub fn lehman_factor(n : Int) -> Int? {
  if n <= 1 {
    return None
  }
  if n == 2 {
    return None // 2 is prime
  }
  // Even numbers > 2: 2 is always a non-trivial factor.
  if n % 2 == 0 {
    return Some(2)
  }
  let n64 = n.to_int64()
  // Prime check: a prime has no non-trivial factor.
  if @int64_utils.is_prime64(n64) {
    return None
  }
  let n3 = icbrt64(n64).to_int()
  // --- Step 1: trial division up to n^{1/3} -------------------------------
  // Any factor ≤ n^{1/3} is found here; only factors > n^{1/3} reach step 2.
  let mut d = 3
  while d <= n3 {
    if n % d == 0 {
      return Some(d)
    }
    d = d + 2
  }
  // --- Step 2: Lehman search ---------------------------------------------
  // For each k in [1, n^{1/3}], look for a near √(kn) such that
  // a² − kn is a perfect square.  The inner range width is ~n^{1/6}/(4√k).
  let n6 = isqrt64(n3.to_int64()) // ≈ n^{1/6}
  let mut k = 1
  while k <= n3 {
    let kn = k.to_int64() * n64
    let a_start = isqrt_ceil64(kn)
    let k_sqrt = isqrt64(k.to_int64())
    // Theoretical range: n^{1/6} / (4√k); add 2 as a safety margin.
    let bound = n6 / (4L * k_sqrt) + 2L
    let mut j = 0L
    while j <= bound {
      let a = a_start + j
      let b2 = a * a - kn
      // b2 ≥ 0 is guaranteed because a ≥ ⌈√(kn)⌉, hence a² ≥ kn.
      if b2 >= 0L {
        let b = isqrt64(b2)
        if b * b == b2 {
          // a² − kn = b²  ⟹  kn = (a−b)(a+b)  ⟹  factor via gcd.
          let g1 = @int64_utils.gcd64(a - b, n64)
          if g1 > 1L && g1 < n64 {
            return Some(g1.to_int())
          }
          if b > 0L {
            let g2 = @int64_utils.gcd64(a + b, n64)
            if g2 > 1L && g2 < n64 {
              return Some(g2.to_int())
            }
          }
        }
      }
      j = j + 1L
    }
    k = k + 1
  }
  // No factor found: n is prime (already checked) or an edge case.
  None
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "lehman_factor: small composites" {
  // 15 = 3 × 5
  let d = lehman_factor(15).unwrap()
  assert_eq(15 % d, 0)
  assert_true(d > 1 && d < 15)
  // 21 = 3 × 7
  let d2 = lehman_factor(21).unwrap()
  assert_eq(21 % d2, 0)
  // 35 = 5 × 7
  let d3 = lehman_factor(35).unwrap()
  assert_eq(35 % d3, 0)
}

///|
test "lehman_factor: prime powers" {
  // Perfect squares of primes (k=1, a=√n, b=0 path)
  assert_eq(lehman_factor(9).unwrap(), 3) // 3²
  assert_eq(lehman_factor(25).unwrap(), 5) // 5²
  assert_eq(lehman_factor(49).unwrap(), 7) // 7²
  assert_eq(lehman_factor(121).unwrap(), 11) // 11²
  assert_eq(lehman_factor(169).unwrap(), 13) // 13²
  // Cube of prime
  assert_eq(lehman_factor(27).unwrap(), 3) // 3³
  assert_eq(lehman_factor(125).unwrap(), 5) // 5³
}

///|
test "lehman_factor: semiprimes with larger factors" {
  // Factors > n^{1/3}, exercising the Lehman search.
  // 77 = 7 × 11
  let d = lehman_factor(77).unwrap()
  assert_eq(77 % d, 0)
  assert_true(d == 7 || d == 11)
  // 91 = 7 × 13
  let d2 = lehman_factor(91).unwrap()
  assert_eq(91 % d2, 0)
  assert_true(d2 == 7 || d2 == 13)
  // 143 = 11 × 13
  let d3 = lehman_factor(143).unwrap()
  assert_eq(143 % d3, 0)
  assert_true(d3 == 11 || d3 == 13)
  // 221 = 13 × 17
  let d4 = lehman_factor(221).unwrap()
  assert_eq(221 % d4, 0)
  assert_true(d4 == 13 || d4 == 17)
}

///|
test "lehman_factor: primes return None" {
  assert_true(lehman_factor(2) is None)
  assert_true(lehman_factor(3) is None)
  assert_true(lehman_factor(7) is None)
  assert_true(lehman_factor(13) is None)
  assert_true(lehman_factor(97) is None)
  assert_true(lehman_factor(997) is None)
  assert_true(lehman_factor(7919) is None)
}

///|
test "lehman_factor: edge cases" {
  assert_true(lehman_factor(0) is None)
  assert_true(lehman_factor(1) is None)
  assert_true(lehman_factor(-5) is None)
  // Even numbers always yield 2.
  assert_eq(lehman_factor(4), Some(2))
  assert_eq(lehman_factor(6), Some(2))
  assert_eq(lehman_factor(100), Some(2))
}

///|
test "lehman_factor: Carmichael number 561 = 3 × 11 × 17" {
  let d = lehman_factor(561).unwrap()
  assert_eq(561 % d, 0)
  assert_true(d == 3 || d == 11 || d == 17)
}

///|
test "lehman_factor: large semiprime" {
  // 10007 × 10009 = 100160063
  let n = 100160063
  let d = lehman_factor(n).unwrap()
  assert_eq(n % d, 0)
  assert_true(d == 10007 || d == 10009)
}

///|
test "lehman_factor: product of two primes near Int32 sqrt" {
  // 46337 × 46327 = 2146654199 (< 2^31)
  let n = 2146654199
  let d = lehman_factor(n).unwrap()
  assert_eq(n % d, 0)
  assert_true(d == 46327 || d == 46337)
}

///|
test "lehman_factor: factor divides n for various composites" {
  let cases = [
    15, 21, 35, 49, 77, 91, 143, 187, 221, 247, 299, 323, 361, 391, 437, 529,
    667, 899, 1147, 1517, 561, 1105, 1729, 2465,
  ]
  for i = 0; i < cases.length(); i = i + 1 {
    let n = cases[i]
    let d = lehman_factor(n).unwrap()
    assert_eq(n % d, 0)
    assert_true(d > 1 && d < n)
  }
}
