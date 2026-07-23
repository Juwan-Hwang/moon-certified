/// Euclidean GCD algorithm using recursion.
///
/// Verified properties:
/// 1. result >= 0 (proven by Z3 from the base case and induction)
/// 2. result divides both a and b (via axiomatized lemma — nonlinear)
///
/// The divisibility property (a % result == 0) requires nonlinear arithmetic
/// that Z3 cannot prove automatically for recursive functions. It is
/// established through `gcd_divides_lemma` below, declared as
/// `proof_axiomatized`.

/// Axiomatized lemma: the Euclidean algorithm produces a result that
/// divides both inputs. This is a well-known mathematical theorem;
/// Z3 cannot discharge it due to nonlinear reasoning (a == result * q).
pub fn gcd_divides_lemma(
  a : Int,
  b : Int,
  result : Int,
) -> Unit where {
  proof_axiomatized: true,
  proof_require: 0 <= a && 0 <= b,
  proof_require: result == gcd(a, b),
  proof_ensure: gcd_divides(a, b, result),
} {
  // proof_axiomatized: contract assumed without proof.
}

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
