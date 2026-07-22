/// Euclidean GCD algorithm using recursion.
/// Verified: the result is non-negative for non-negative inputs.
pub fn gcd(
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
    gcd(b, a % b)
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
