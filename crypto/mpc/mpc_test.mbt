// Tests for crypto/mpc — Shamir secret sharing and BGW88 secure
// multiplication over the Mersenne prime field 2^31 - 1.

///|
fn mpc_seed(n : Int) -> Bytes {
  let arr : Array[Byte] = []
  for i = 0; i < 32; i = i + 1 {
    arr.push(((n + i * 7919) & 0xFF).to_byte())
  }
  Bytes::from_array(arr)
}

///|
test "shamir_split_reconstruct_thresholds" {
  // Several (n, t) configurations must all reconstruct exactly.
  let configs = [(3, 2), (5, 3), (7, 4), (5, 5), (4, 1)]
  for cfg in configs {
    let n = cfg.0
    let t = cfg.1
    let secret = 1234567
    let shares = shamir_split(secret, n, t, mpc_seed(n * 100 + t))
    assert_eq(shares.length(), n)
    assert_eq(shamir_reconstruct(shares), secret)
    // Any t-share subset must also reconstruct.
    let subset : Array[ShamirShare] = []
    for i = 0; i < t; i = i + 1 {
      subset.push(shares[n - 1 - i])
    }
    assert_eq(shamir_reconstruct(subset), secret)
    // A disjoint t-share subset too.
    let subset2 : Array[ShamirShare] = []
    for i = 0; i < t; i = i + 1 {
      subset2.push(shares[i * 2 % n])
    }
    assert_eq(shamir_reconstruct(subset2), secret)
  }
}

///|
test "shamir_below_threshold_does_not_reconstruct" {
  let secret = 987654321
  let shares = shamir_split(secret, 5, 3, mpc_seed(1))
  // With t-1 shares the interpolation is unconstrained at 0: over a
  // 2^31-sized field the chance of guessing the secret is negligible.
  let few : Array[ShamirShare] = [shares[0], shares[1]]
  assert_true(shamir_reconstruct(few) != secret)
  let one : Array[ShamirShare] = [shares[3]]
  assert_true(shamir_reconstruct(one) != secret)
}

///|
test "shamir_field_boundaries" {
  // Secrets at field edges round-trip.
  let edge0 = shamir_split(0, 3, 2, mpc_seed(2))
  assert_eq(shamir_reconstruct(edge0), 0)
  let edge_max = shamir_split(MPC_PRIME - 1, 3, 2, mpc_seed(3))
  assert_eq(shamir_reconstruct(edge_max), MPC_PRIME - 1)
}

///|
test "shamir_invalid_params_rejected" {
  let r1 = Some(shamir_split(5, 2, 3, mpc_seed(4))) catch { _ => None }
  assert_eq(r1, None)
  let r2 = Some(shamir_split(5, 3, 0, mpc_seed(5))) catch { _ => None }
  assert_eq(r2, None)
  let r3 = Some(shamir_split(MPC_PRIME, 3, 2, mpc_seed(6))) catch { _ => None }
  assert_eq(r3, None)
}

///|
test "mpc_add_is_linear" {
  let a = 111111111
  let b = 222222222
  let sa = shamir_split(a, 5, 3, mpc_seed(10))
  let sb = shamir_split(b, 5, 3, mpc_seed(11))
  let ssum = mpc_add(sa, sb)
  assert_eq(shamir_reconstruct(ssum), mpc_field_add(a, b))
}

///|
// The old implementation returned shares of an arbitrary linear
// combination of local products, not a·b. The BGW degree-reduction
// must now produce a correct degree-(t-1) sharing of the product.
test "mpc_secure_mul_correctness" {
  let cases = [
    (6, 9, 3, 2),
    (42, 7, 5, 3),
    (2147483646, 2, 3, 2),
    (0, 12345, 5, 3),
  ]
  for c in cases {
    let a = c.0
    let b = c.1
    let n = c.2
    let t = c.3
    let sa = shamir_split(a, n, t, mpc_seed(n * 1000 + t))
    let sb = shamir_split(b, n, t, mpc_seed(n * 2000 + t))
    let prod = mpc_secure_mul(sa, sb, n, t, mpc_seed(n * 3000 + t))
    assert_eq(prod.length(), n)
    // Full reconstruction gives a·b mod p.
    assert_eq(shamir_reconstruct(prod), mpc_field_mul(a, b))
    // The result is a proper degree-(t-1) sharing: any t shares
    // reconstruct, and the x-coordinates are preserved.
    let subset : Array[ShamirShare] = []
    for i = 0; i < t; i = i + 1 {
      subset.push(prod[n - 1 - i])
      assert_eq(prod[i].x, i + 1)
    }
    assert_eq(shamir_reconstruct(subset), mpc_field_mul(a, b))
  }
}

///|
test "mpc_secure_mul_requires_honest_majority" {
  // n = 2, t = 2 violates n >= 2t - 1 and must be rejected.
  let sa = shamir_split(3, 2, 2, mpc_seed(20))
  let sb = shamir_split(4, 2, 2, mpc_seed(21))
  let r = Some(mpc_secure_mul(sa, sb, 2, 2, mpc_seed(22))) catch { _ => None }
  assert_eq(r, None)
}

///|
test "mpc_circuit_add_then_mul" {
  // Evaluate (a + b) * c through the sharing layer end-to-end.
  let a = 135791
  let b = 246810
  let c = 112233
  let n = 5
  let t = 3
  let sa = shamir_split(a, n, t, mpc_seed(30))
  let sb = shamir_split(b, n, t, mpc_seed(31))
  let sc = shamir_split(c, n, t, mpc_seed(32))
  let sum = mpc_add(sa, sb)
  let out = mpc_secure_mul(sum, sc, n, t, mpc_seed(33))
  assert_eq(shamir_reconstruct(out), mpc_field_mul(mpc_field_add(a, b), c))
}
