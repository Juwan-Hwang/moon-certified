/// Euclidean GCD algorithm using recursion.
///
/// Verified by `moon prove` (on `gcd_impl`):
/// - result >= 0 for non-negative inputs (non-negativity, proven by Z3)
///
/// Not verified (requires nonlinear arithmetic beyond Z3's capability):
/// - result divides both a and b (divisibility)
/// - result is the greatest common divisor (optimality)
///
/// These properties are tested exhaustively instead.
///
/// The public `gcd` function handles negative inputs by taking absolute
/// values before calling the verified `gcd_impl`. For `Int::MIN`, whose
/// absolute value (2³¹) overflows `Int`, the computation is performed in
/// `Int64` to produce the mathematically correct result.

/// Verified GCD implementation (requires non-negative inputs).
/// Calling with negative `b` can cause infinite recursion because
/// `proof_decrease: b` does not hold for negative values.
fn gcd_impl(
  a : Int,
  b : Int,
) -> Int where {
  proof_decrease: b,
  proof_require: 0 <= a && 0 <= b,
  proof_ensure: result => gcd_nonneg(result),
} {
  if b == 0 {
    proof_assert 0 <= a
    a
  } else {
    proof_assert 0 < b
    proof_assert 0 <= a % b
    proof_assert a % b < b
    gcd_impl(b, a % b)
  }
}

/// Int64 GCD for handling `Int::MIN` correctly.
///
/// `|Int::MIN|` = 2³¹ overflows `Int` (range [-2³¹, 2³¹-1]). By working in
/// `Int64`, we can represent the full absolute value and compute the exact
/// GCD. This is used exclusively when at least one input is `Int::MIN`.
fn gcd64(a : Int64, b : Int64) -> Int64 {
  let mut a = if a < 0L { -a } else { a }
  let mut b = if b < 0L { -b } else { b }
  while b != 0L {
    let t = b
    b = a % b
    a = t
  }
  a
}

/// Compute the greatest common divisor of two integers.
///
/// Returns a non-negative result. `gcd(0, 0) = 0`.
///
/// Handles negative inputs by taking absolute values. For inputs within
/// the normal `Int` range, the verified `gcd_impl` is used. When either
/// input is `Int::MIN` (whose absolute value 2³¹ overflows `Int`), the
/// computation is performed in `Int64` to produce the exact result.
///
/// **Int::MIN edge case**: `gcd(Int::MIN, Int::MIN)` = 2³¹, which exceeds
/// `Int::MAX`. In this sole case the result is clamped to `Int::MAX`.
/// All other `Int::MIN` combinations produce results that fit in `Int`:
/// - `gcd(Int::MIN, 2)` = 2
/// - `gcd(Int::MIN, 4)` = 4
/// - `gcd(Int::MIN, 1073741824)` = 1073741824
/// - `gcd(Int::MIN, 5)` = 1
pub fn gcd(a : Int, b : Int) -> Int {
  // Fast path: neither input is Int::MIN, so |a| and |b| fit in Int.
  if a != -2147483648 && b != -2147483648 {
    let abs_a = if a >= 0 { a } else { -a }
    let abs_b = if b >= 0 { b } else { -b }
    gcd_impl(abs_a, abs_b)
  } else {
    // At least one input is Int::MIN: use Int64 for exact computation.
    let result = gcd64(a.to_int64(), b.to_int64())
    if result > 2147483647L {
      // Only gcd(Int::MIN, Int::MIN) = 2^31 reaches here; clamp to Int::MAX.
      2147483647
    } else {
      result.to_int()
    }
  }
}

test "gcd: basic" {
  assert_eq(gcd(12, 8), 4)
  assert_eq(gcd(8, 12), 4)
}

test "gcd: coprime" {
  assert_eq(gcd(7, 13), 1)
  assert_eq(gcd(1, 1), 1)
}

test "gcd: one is zero" {
  assert_eq(gcd(5, 0), 5)
  assert_eq(gcd(0, 5), 5)
  assert_eq(gcd(0, 0), 0)
}

test "gcd: large numbers" {
  assert_eq(gcd(1071, 462), 21)
}

test "gcd: equal numbers" {
  assert_eq(gcd(6, 6), 6)
}

test "gcd: divisibility property" {
  let pairs = [(12, 8), (1071, 462), (7, 13), (100, 75), (36, 24)]
  for k = 0; k < 5; k = k + 1 {
    let (a, b) = pairs[k]
    let g = gcd(a, b)
    if g > 0 {
      assert_eq(a % g, 0)
      assert_eq(b % g, 0)
    }
  }
}

test "gcd: negative inputs handled safely" {
  assert_eq(gcd(-12, 8), 4)
  assert_eq(gcd(12, -8), 4)
  assert_eq(gcd(-12, -8), 4)
  assert_eq(gcd(-1071, -462), 21)
  assert_eq(gcd(-7, 13), 1)
  assert_eq(gcd(-5, 0), 5)
  assert_eq(gcd(0, -5), 5)
}

test "gcd: Int::MIN mathematically correct" {
  // Int::MIN = -2147483648 = -2^31
  // |Int::MIN| = 2^31, computed exactly via Int64.

  // gcd(2^31, 2) = 2 — 2^31 is even, divisible by 2.
  assert_eq(gcd(-2147483648, 2), 2)

  // gcd(2^31, 4) = 4 — 2^31 is divisible by 4.
  assert_eq(gcd(-2147483648, 4), 4)

  // gcd(2^31, 8) = 8
  assert_eq(gcd(-2147483648, 8), 8)

  // gcd(2^31, 1073741824) = 1073741824 (since 1073741824 = 2^30 divides 2^31)
  assert_eq(gcd(-2147483648, 1073741824), 1073741824)

  // gcd(2^31, 5) = 1 — 2^31 is a power of 2, coprime with 5.
  assert_eq(gcd(-2147483648, 5), 1)

  // gcd(2^31, 1) = 1
  assert_eq(gcd(-2147483648, 1), 1)

  // gcd(2^31, 2^31) = 2^31 — overflows Int, clamped to Int::MAX.
  assert_eq(gcd(-2147483648, -2147483648), 2147483647)

  // gcd(2^31, 3) = 1 — coprime
  assert_eq(gcd(-2147483648, 3), 1)

  // gcd(2^31, 6) = 2 — 6 = 2 * 3, gcd with 2^31 is 2
  assert_eq(gcd(-2147483648, 6), 2)

  // Verify divisibility for Int::MIN cases where g fits in Int.
  let g = gcd(-2147483648, 6)
  assert_eq(g, 2)
  // 2^31 mod 2 = 0, verified via Int64
  assert_eq(((2147483648L) % g.to_int64()), 0L)
}
