/// Fast exponentiation using binary decomposition.
/// Computes base^exp in O(log exp) multiplications.
/// Verified: the result is non-negative when base >= 0 and exp >= 0.
///
/// **Overflow**: `base^exp` is computed modulo 2³² (silent wrap-around).
/// Callers must ensure the result fits in 32-bit `Int`; e.g. `fast_power(2, 31)`
/// overflows. The proof guarantees non-negativity of the *intended* result
/// but does not account for integer overflow.
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
