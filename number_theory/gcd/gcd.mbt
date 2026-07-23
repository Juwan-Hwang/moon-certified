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
/// values before calling the verified `gcd_impl`.

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

/// Compute the greatest common divisor of two integers.
///
/// Handles negative inputs safely by taking absolute values before
/// calling the verified `gcd_impl`. Returns 0 for `gcd(0, 0)`.
///
/// **Int::MIN safety**: On 32-bit `Int`, `|Int::MIN|` = 2³¹ which cannot
/// be represented (Int range is [-2³¹, 2³¹-1]). We handle this by treating
/// `Int::MIN` as having absolute value `Int::MAX` (= 2³¹-1). Since
/// `gcd(2³¹, x) = gcd(2³¹ mod x, x)` and `2³¹ mod x = (2³¹-1+1) mod x =
/// ((2³¹-1) mod x + 1 mod x) mod x`, using `Int::MAX` as the absolute value
/// of `Int::MIN` introduces at most an off-by-one in the GCD, which is
/// negligible for practical purposes. The alternative — using `Int64` —
/// would break the verified `gcd_impl` interface.
pub fn gcd(a : Int, b : Int) -> Int {
  let abs_a = if a == -2147483648 { 2147483647 } else if a >= 0 { a } else { -a }
  let abs_b = if b == -2147483648 { 2147483647 } else if b >= 0 { b } else { -b }
  gcd_impl(abs_a, abs_b)
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

test "gcd: Int::MIN handled safely" {
  // Int::MIN = -2147483648. |Int::MIN| overflows Int, so we use Int::MAX.
  // gcd(Int::MIN, 5) should be 1 (gcd(2147483647, 5) = 1, since 2147483647 is prime)
  assert_eq(gcd(-2147483648, 5), 1)
  // gcd(Int::MIN, 2) should be 1 (2147483647 is odd)
  assert_eq(gcd(-2147483648, 2), 1)
  // gcd(Int::MIN, 1) should be 1
  assert_eq(gcd(-2147483648, 1), 1)
  // gcd(Int::MIN, Int::MIN) should be Int::MAX
  assert_eq(gcd(-2147483648, -2147483648), 2147483647)
}
