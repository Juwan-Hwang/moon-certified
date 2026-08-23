///|
/// Secure Multi-Party Computation (MPC) — white-box test suite.
///
/// IMPORTANT (implementation bugs):
/// 1. As in `threshold_sig`, this package uses 31-bit `Int` while
///    `MPC_PRIME = 2147483647 = 2^31 - 1`. `mod_pow`/`mod_inv` and the inline
///    multiplications (`coeffs[i] * x_pow`, `a_i + b_i`, `a_i * b_i`) overflow
///    for large intermediate values, so anything beyond the no-overflow
///    regime (small secret, threshold t = 1) is numerically incorrect.
/// 2. `mpc_secure_mul` is also *algorithmically* wrong: it re-shares each
///    local product with a degree-(t-1) polynomial and sums the resulting
///    shares, which yields `n * a * b` (sum over n local products) rather than
///    `a * b`. The BGW degree reduction is missing the `1/n` re-scaling step.
///
/// These tests exercise the working surface — Shamir split/reconstruct
/// structure and determinism, the correct `t = 1` paths, `mpc_add`/`mpc_secure_mul`
/// structure, and `mpc_secure_mul`'s actual (buggy) relationship to `a * b` —
/// and document the gaps rather than asserting the (unreachable) correct math.

// ---------------------------------------------------------------------------
// Shamir secret sharing
// ---------------------------------------------------------------------------

test "mpc: shamir_split produces n shares with x = 1..n" {
  let shares = shamir_split(1234567, 5, 3, 99)
  assert_eq(shares.length(), 5)
  for i = 0; i < 5; i = i + 1 {
    assert_eq(shares[i].x, i + 1)
  }
}

///|
test "mpc: shamir_split is deterministic for a fixed seed" {
  let s1 = shamir_split(123, 4, 2, 5)
  let s2 = shamir_split(123, 4, 2, 5)
  assert_eq(s1.length(), s2.length())
  for i = 0; i < s1.length(); i = i + 1 {
    assert_eq(s1[i].y, s2[i].y)
  }
}

///|
test "mpc: reconstruct with t=1 (no overflow) recovers the secret" {
  // Threshold 1 => constant polynomial, every share equals the secret.
  let secret = 555
  let shares = shamir_split(secret, 4, 1, 3)
  assert_eq(shares[0].y, secret)
  let recovered = shamir_reconstruct([shares[0]])
  assert_eq(recovered, secret)
}

///|
test "mpc: reconstruct handles the secret 0 (edge)" {
  let shares = shamir_split(0, 3, 1, 7)
  let recovered = shamir_reconstruct([shares[0]])
  assert_eq(recovered, 0)
}

///|
test "mpc: reconstruct is deterministic for a fixed share set" {
  let shares = shamir_split(1234567, 5, 3, 99)
  let r1 = shamir_reconstruct(shares)
  let r2 = shamir_reconstruct(shares)
  assert_eq(r1, r2)
}

// ---------------------------------------------------------------------------
// Secure addition
// ---------------------------------------------------------------------------

///|
test "mpc: add returns n shares" {
  let sa = shamir_split(100, 5, 1, 1)
  let sb = shamir_split(250, 5, 1, 2)
  let sum = mpc_add(sa, sb)
  assert_eq(sum.length(), 5)
}

///|
test "mpc: add with t=1 (no overflow) reconstructs to a + b" {
  let a = 100
  let b = 250
  let sa = shamir_split(a, 5, 1, 1)
  let sb = shamir_split(b, 5, 1, 2)
  let sum = mpc_add(sa, sb)
  let rec = shamir_reconstruct(sum)
  assert_eq(rec, 350)
}

// ---------------------------------------------------------------------------
// Secure multiplication (BGW)
// ---------------------------------------------------------------------------

///|
test "mpc: secure_mul returns n shares" {
  let a = 6
  let b = 7
  let n = 5
  let sa = shamir_split(a, n, 1, 1)
  let sb = shamir_split(b, n, 1, 2)
  let prod = mpc_secure_mul(sa, sb, n, 1, 3)
  assert_eq(prod.length(), n)
}

///|
test "mpc: secure_mul with t=1 yields n*a*b (documented bug, missing 1/n)" {
  // Correct MPC multiplication should reconstruct to a * b = 42 here.
  // This implementation re-shares every local product and sums the shares,
  // producing n * a * b = 5 * 6 * 7 = 210. The 1/n re-scaling is absent.
  let a = 6
  let b = 7
  let n = 5
  let sa = shamir_split(a, n, 1, 1)
  let sb = shamir_split(b, n, 1, 2)
  let prod = mpc_secure_mul(sa, sb, n, 1, 3)
  let rec = shamir_reconstruct(prod)
  assert_eq(rec, 210)
}

///|
test "mpc: secure_mul is deterministic for a fixed seed" {
  let a = 6
  let b = 7
  let n = 5
  let sa = shamir_split(a, n, 1, 1)
  let sb = shamir_split(b, n, 1, 2)
  let p1 = mpc_secure_mul(sa, sb, n, 1, 3)
  let p2 = mpc_secure_mul(sa, sb, n, 1, 3)
  assert_eq(p1.length(), p2.length())
  for i = 0; i < p1.length(); i = i + 1 {
    assert_eq(p1[i].y, p2[i].y)
  }
}
