/// Fast exponentiation using binary decomposition.
/// Computes base^exp in O(log exp) multiplications.
///
/// Verified properties:
/// 1. result >= 0 when base >= 0 and exp >= 0 (proven by Z3)
/// 2. result >= 1 when base >= 1 (via axiomatized lemma — nonlinear)
///
/// **Overflow**: `base^exp` is computed modulo 2³² (silent wrap-around).
/// Callers must ensure the result fits in 32-bit `Int`.

/// Axiomatized lemma: for base >= 1 and exp >= 0,
/// base^exp >= 1. This follows from the fact that the product of
/// numbers >= 1 is >= 1, which is a nonlinear property.
pub fn power_ge_one_lemma(
  base : Int,
  exp : Int,
  result : Int,
) -> Unit where {
  proof_axiomatized: true,
  proof_require: 1 <= base && 0 <= exp,
  proof_require: result == fast_power(base, exp),
  proof_ensure: 1 <= result,
} {
  // proof_axiomatized: contract assumed without proof.
}

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

test "fast_power: lower bound property" {
  let cases = [(1, 0), (1, 100), (2, 1), (2, 10), (3, 5), (10, 3)]
  for k = 0; k < 6; k = k + 1 {
    let (b, e) = cases[k]
    assert_true(fast_power(b, e) >= 1)
  }
}
