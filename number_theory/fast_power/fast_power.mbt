/// Fast exponentiation using binary decomposition.
/// Computes base^exp in O(log exp) multiplications.
///
/// Verified by `moon prove`:
/// - result >= 0 when base >= 0 and exp >= 0 (non-negativity, proven by Z3)
///
/// Not verified (requires nonlinear arithmetic beyond Z3's capability):
/// - result == base^exp (full correctness)
/// - result >= 1 when base >= 1 (monotonicity)
///
/// **Overflow**: `base^exp` is computed using 32-bit `Int` arithmetic.
/// Results exceeding 2³¹−1 silently wrap to negative values, which
/// invalidates the non-negativity guarantee at runtime (the proof
/// models `Int` as mathematical integers).
/// Use `fast_power_checked` for an overflow-safe variant that returns
/// `None` when the result would exceed `Int`'s range.

pub fn fast_power(
  base : Int,
  exp : Int,
) -> Int where {
  proof_decrease: exp,
  proof_require: 0 <= base && 0 <= exp,
  proof_ensure: result => power_nonneg(result),
} {
  if exp == 0 {
    1
  } else if exp % 2 == 0 {
    proof_assert 0 < exp
    proof_assert 0 <= exp / 2
    proof_assert exp / 2 < exp
    let half = fast_power(base, exp / 2)
    proof_assert 0 <= half
    half * half
  } else {
    proof_assert 0 < exp
    proof_assert 0 <= exp - 1
    proof_assert exp - 1 < exp
    let rest = fast_power(base, exp - 1)
    proof_assert 0 <= rest
    base * rest
  }
}

/// Overflow-safe fast exponentiation.
///
/// Returns `Some(result)` when `base^exp` fits in 32-bit `Int`,
/// or `None` when the result would overflow.
///
/// Uses 64-bit arithmetic internally to detect overflow before it happens.
/// Rejects negative `base` or `exp` (returns `None`).
pub fn fast_power_checked(base : Int, exp : Int) -> Int? {
  if base < 0 || exp < 0 {
    return None
  }
  let base64 = base.to_int64()
  let mut result = 1L
  let mut b = base64
  let mut e = exp
  let max_int = 2147483647L
  while e > 0 {
    if e % 2 == 1 {
      result = result * b
      if result > max_int {
        return None
      }
    }
    b = b * b
    if b > max_int && e > 1 {
      // b will be used in future iterations; if it already overflows,
      // and we have more bits to process, the result will overflow.
      // But we can only be sure if the remaining exponent is > 0.
      // Actually, b might not be used if all remaining bits are 0.
      // So we continue the loop and only fail if result overflows.
    }
    e = e / 2
  }
  Some(result.to_int())
}

test "fast_power: basic" {
  assert_eq(fast_power(2, 10), 1024)
  assert_eq(fast_power(3, 4), 81)
  assert_eq(fast_power(5, 3), 125)
}

test "fast_power: zero exponent" {
  assert_eq(fast_power(7, 0), 1)
  assert_eq(fast_power(0, 0), 1)
}

test "fast_power: one exponent" {
  assert_eq(fast_power(6, 1), 6)
}

test "fast_power: zero base" {
  assert_eq(fast_power(0, 5), 0)
}

test "fast_power: large exponent" {
  assert_eq(fast_power(2, 20), 1048576)
}

test "fast_power: lower bound property" {
  let cases = [(1, 0), (1, 100), (2, 1), (2, 10), (3, 5), (10, 3)]
  for k = 0; k < 6; k = k + 1 {
    let (b, e) = cases[k]
    assert_true(fast_power(b, e) >= 1)
  }
}

test "fast_power_checked: no overflow" {
  assert_eq(fast_power_checked(2, 10), Some(1024))
  assert_eq(fast_power_checked(2, 20), Some(1048576))
  assert_eq(fast_power_checked(3, 4), Some(81))
  assert_eq(fast_power_checked(1, 100), Some(1))
  assert_eq(fast_power_checked(0, 5), Some(0))
}

test "fast_power_checked: overflow detected" {
  // 2^31 = 2147483648 > Int::MAX (2147483647)
  assert_true(fast_power_checked(2, 31) is None)
  // 3^20 = 3486784401 > Int::MAX
  assert_true(fast_power_checked(3, 20) is None)
  // 10^10 = 10000000000 > Int::MAX
  assert_true(fast_power_checked(10, 10) is None)
}

test "fast_power_checked: boundary cases" {
  // 2^30 = 1073741824 < Int::MAX
  assert_eq(fast_power_checked(2, 30), Some(1073741824))
  // 2^31 overflows
  assert_true(fast_power_checked(2, 31) is None)
  // negative inputs rejected
  assert_true(fast_power_checked(-2, 3) is None)
  assert_true(fast_power_checked(2, -1) is None)
}
