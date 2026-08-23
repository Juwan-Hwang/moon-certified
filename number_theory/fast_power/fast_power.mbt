///|
/// Fast exponentiation using binary decomposition.
/// Computes base^exp in O(log exp) multiplications.
///
/// **Deprecated**: This function does not detect overflow. If the result
/// exceeds 32-bit `Int` range, it silently wraps to a negative value,
/// invalidating the non-negativity guarantee at runtime.
///
/// Use `fast_power_checked` instead, which returns `None` on overflow.
///
/// This function is retained for formal verification (Z3 proof of
/// non-negativity under the mathematical integer model) and backward
/// compatibility with code that can guarantee no overflow.
///
/// Verified by `moon prove`:
/// - result >= 0 when base >= 0 and exp >= 0 (non-negativity, proven by Z3)
///
/// Not verified (requires nonlinear arithmetic beyond Z3's capability):
/// - result == base^exp (full correctness)
/// - result >= 1 when base >= 1 (monotonicity)
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

///|
/// Overflow-safe fast exponentiation.
///
/// Returns `Some(result)` when `base^exp` fits in 32-bit `Int`,
/// or `None` when the result would overflow.
///
/// Uses 64-bit arithmetic internally to detect overflow before it happens.
/// Rejects negative `base` or `exp` (returns `None`).
///
/// **Overflow safety**: The intermediate variable `b` is squared each
/// iteration. When `b` already exceeds `Int::max_value`, squaring it
/// would overflow `Int64`. Instead of squaring, we set `b` to a sentinel
/// value (`max_int + 1`) that will trigger the overflow check when
/// multiplied into `result`. This avoids `Int64` overflow entirely
/// while still correctly detecting `Int32` overflow.
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
    e = e / 2
    if e > 0 {
      // Only square b if it will be used again.
      // If b already exceeds Int32 range, squaring it would either
      // overflow Int64 or produce a value far beyond Int32 range.
      // Set a sentinel > max_int so any future result*b triggers None.
      if b > max_int {
        b = max_int + 1L
      } else {
        b = b * b
      }
    }
  }
  Some(result.to_int())
}

///|
test "fast_power: basic" {
  assert_eq(fast_power(2, 10), 1024)
  assert_eq(fast_power(3, 4), 81)
  assert_eq(fast_power(5, 3), 125)
}

///|
test "fast_power: zero exponent" {
  assert_eq(fast_power(7, 0), 1)
  assert_eq(fast_power(0, 0), 1)
}

///|
test "fast_power: one exponent" {
  assert_eq(fast_power(6, 1), 6)
}

///|
test "fast_power: zero base" {
  assert_eq(fast_power(0, 5), 0)
}

///|
test "fast_power: large exponent" {
  assert_eq(fast_power(2, 20), 1048576)
}

///|
test "fast_power: lower bound property" {
  let cases = [(1, 0), (1, 100), (2, 1), (2, 10), (3, 5), (10, 3)]
  for k = 0; k < 6; k = k + 1 {
    let (b, e) = cases[k]
    assert_true(fast_power(b, e) >= 1)
  }
}

///|
test "fast_power_checked: no overflow" {
  assert_eq(fast_power_checked(2, 10), Some(1024))
  assert_eq(fast_power_checked(2, 20), Some(1048576))
  assert_eq(fast_power_checked(3, 4), Some(81))
  assert_eq(fast_power_checked(1, 100), Some(1))
  assert_eq(fast_power_checked(0, 5), Some(0))
}

///|
test "fast_power_checked: overflow detected" {
  // 2^31 = 2147483648 > Int::MAX (2147483647)
  assert_true(fast_power_checked(2, 31) is None)
  // 3^20 = 3486784401 > Int::MAX
  assert_true(fast_power_checked(3, 20) is None)
  // 10^10 = 10000000000 > Int::MAX
  assert_true(fast_power_checked(10, 10) is None)
}

///|
test "fast_power_checked: boundary cases" {
  // 2^30 = 1073741824 < Int::MAX
  assert_eq(fast_power_checked(2, 30), Some(1073741824))
  // 2^31 overflows
  assert_true(fast_power_checked(2, 31) is None)
  // negative inputs rejected
  assert_true(fast_power_checked(-2, 3) is None)
  assert_true(fast_power_checked(2, -1) is None)
}

///|
test "fast_power_checked: 65536^4 overflow detected" {
  // This was the original bug: b*b overflowed Int64, producing garbage.
  // The fix detects that b exceeds Int32 range before squaring.
  assert_true(fast_power_checked(65536, 4) is None)
}

///|
test "fast_power_checked: large base with small exp" {
  // 2147483647^1 = 2147483647, fits exactly
  assert_eq(fast_power_checked(2147483647, 1), Some(2147483647))
  // 2147483647^2 overflows
  assert_true(fast_power_checked(2147483647, 2) is None)
}

///|
test "fast_power_checked: base just below sqrt(Int32::MAX)" {
  // 46340^2 = 2147395600 < Int::MAX (2147483647)
  assert_eq(fast_power_checked(46340, 2), Some(2147395600))
  // 46341^2 = 2147488281 > Int::MAX
  assert_true(fast_power_checked(46341, 2) is None)
}

///|
/// Verified fast power with lower bound: result >= 1 when base >= 1.
/// Proven by Z3: base >= 1 implies all intermediate results >= 1.
pub fn fast_power_ge1(
  base : Int,
  exp : Int,
) -> Int where {
  proof_decrease: exp,
  proof_require: 1 <= base && 0 <= exp,
  proof_ensure: result => power_ge1(result),
} {
  if exp == 0 {
    1
  } else if exp % 2 == 0 {
    proof_assert 0 < exp
    proof_assert 0 <= exp / 2
    proof_assert exp / 2 < exp
    let half = fast_power_ge1(base, exp / 2)
    proof_assert 1 <= half
    half * half
  } else {
    proof_assert 0 < exp
    proof_assert 0 <= exp - 1
    proof_assert exp - 1 < exp
    let rest = fast_power_ge1(base, exp - 1)
    proof_assert 1 <= rest
    base * rest
  }
}

///|
/// Verified fast power with base lower bound: result >= base when base >= 1, exp >= 1.
pub fn fast_power_ge_base(
  base : Int,
  exp : Int,
) -> Int where {
  proof_decrease: exp,
  proof_require: 1 <= base && 1 <= exp,
  proof_ensure: result => power_ge_base(base, result),
} {
  if exp == 1 {
    proof_assert base <= base
    base
  } else if exp % 2 == 0 {
    proof_assert 1 < exp
    proof_assert 0 <= exp / 2
    proof_assert exp / 2 < exp
    proof_assert 1 <= exp / 2
    let half = fast_power_ge_base(base, exp / 2)
    proof_assert base <= half
    half * half
  } else {
    proof_assert 1 < exp
    proof_assert 0 <= exp - 1
    proof_assert exp - 1 < exp
    proof_assert 1 <= exp - 1
    let rest = fast_power_ge_base(base, exp - 1)
    proof_assert base <= rest
    base * rest
  }
}

///|
test "fast_power_ge1: basic" {
  assert_eq(fast_power_ge1(2, 10), 1024)
  assert_eq(fast_power_ge1(3, 4), 81)
  assert_eq(fast_power_ge1(1, 0), 1)
  assert_true(fast_power_ge1(2, 10) >= 1)
  assert_true(fast_power_ge1(1, 100) >= 1)
}

///|
test "fast_power_ge1: zero exponent" {
  assert_eq(fast_power_ge1(5, 0), 1)
  assert_true(fast_power_ge1(5, 0) >= 1)
}

///|
test "fast_power_ge_base: basic" {
  assert_eq(fast_power_ge_base(2, 10), 1024)
  assert_eq(fast_power_ge_base(3, 4), 81)
  assert_true(fast_power_ge_base(2, 10) >= 2)
  assert_true(fast_power_ge_base(3, 4) >= 3)
}

///|
test "fast_power_ge_base: exp 1" {
  assert_eq(fast_power_ge_base(7, 1), 7)
  assert_true(fast_power_ge_base(7, 1) >= 7)
}
