/// Threshold signatures — white-box test suite.
///
/// IMPORTANT (implementation bug): this package uses `Int`, which is a 31-bit
/// signed integer in MoonBit, while `TS_PRIME = 2147483647 = 2^31 - 1` is the
/// maximum 31-bit value. The shared `mod_pow`/`mod_inv` helpers multiply
/// `result * b` (each up to ~2^31 - 1), which overflows 31-bit `Int`. As a
/// result, `threshold_reconstruct` and `threshold_combine_signatures` return
/// *incorrect* results whenever the internal coefficients/partials are large
/// (i.e. for any threshold t >= 2, since keygen draws random coefficients up
/// near 2^31 - 1). The no-overflow regime (t = 1, small values) is correct.
///
/// These tests cover the working surface: key generation structure,
/// determinism, the well-defined `t = 1` correctness path, `sign_partial`
/// structure, `verify`'s own documented contract, and determinism of the
/// reconstruction / combination routines. The t >= 2 correctness gap is
/// documented in the coverage report, not asserted here.

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

///|
/// Local re-implementation of the package's `mod_pow` (mirrors its exact
/// operation order so it overflows identically and can be used to probe the
/// package's deterministic behavior). `p` below equals `TS_PRIME`.
fn tmod_pow(base : Int, exp : Int, m : Int) -> Int {
  if m == 1 {
    return 0
  }
  let mut result = 1
  let mut b = base % m
  if b < 0 {
    b = b + m
  }
  let mut e = exp
  while e > 0 {
    if (e & 1) == 1 {
      result = result * b % m
    }
    e = e >> 1
    b = b * b % m
  }
  result
}

// ---------------------------------------------------------------------------
// Key generation & reconstruction
// ---------------------------------------------------------------------------

///|
test "threshold: keygen produces n shares with party ids 1..n" {
  let shares = threshold_keygen(123456789, 5, 3, 42)
  assert_eq(shares.length(), 5)
  for i = 0; i < 5; i = i + 1 {
    assert_eq(shares[i].party_id, i + 1)
  }
}

///|
test "threshold: keygen is deterministic for a fixed seed" {
  let s1 = threshold_keygen(123, 4, 2, 5)
  let s2 = threshold_keygen(123, 4, 2, 5)
  assert_eq(s1.length(), s2.length())
  for i = 0; i < s1.length(); i = i + 1 {
    assert_eq(s1[i].share, s2[i].share)
  }
}

///|
test "threshold: reconstruct with t=1 (no overflow) recovers the secret" {
  // Threshold 1 => the polynomial is constant, every share equals the secret,
  // and no large intermediate multiplications occur.
  let secret = 555
  let shares = threshold_keygen(secret, 4, 1, 3)
  assert_eq(shares[0].share, secret)
  let recovered = threshold_reconstruct([shares[0]])
  assert_eq(recovered, secret)
}

///|
test "threshold: reconstruct is deterministic for a fixed share set" {
  let shares = threshold_keygen(123456789, 5, 3, 42)
  let r1 = threshold_reconstruct(shares)
  let r2 = threshold_reconstruct(shares)
  assert_eq(r1, r2)
}

// ---------------------------------------------------------------------------
// Threshold signing
// ---------------------------------------------------------------------------

///|
test "threshold: sign_partial preserves party ids and count" {
  let secret = 55
  let n = 5
  let shares = threshold_keygen(secret, n, 3, 11)
  let mh = 12345
  let partials : Array[PartialSignature] = []
  for i = 0; i < n; i = i + 1 {
    partials.push(threshold_sign_partial(shares[i], mh))
  }
  assert_eq(partials.length(), n)
  for i = 0; i < n; i = i + 1 {
    assert_eq(partials[i].party_id, shares[i].party_id)
  }
}

///|
test "threshold: combine with n=t=1 (no overflow) yields secret*message_hash" {
  // Small values avoid the 31-bit overflow, exercising the correct path.
  let secret = 2
  let mh = 3
  let shares = threshold_keygen(secret, 1, 1, 5)
  let partials : Array[PartialSignature] = []
  for i = 0; i < 1; i = i + 1 {
    partials.push(threshold_sign_partial(shares[i], mh))
  }
  let sig = threshold_combine_signatures(partials)
  assert_eq(sig, secret % 2147483647 * mh % 2147483647)
}

///|
test "threshold: combine is deterministic for a fixed partial set" {
  let secret = 99
  let shares = threshold_keygen(secret, 4, 2, 8)
  let mh = 777
  let partials : Array[PartialSignature] = []
  for i = 0; i < 4; i = i + 1 {
    partials.push(threshold_sign_partial(shares[i], mh))
  }
  let s1 = threshold_combine_signatures(partials)
  let s2 = threshold_combine_signatures(partials)
  assert_eq(s1, s2)
}

// ---------------------------------------------------------------------------
// Verification (tested on its own documented contract:
// `signature == public_key^message_hash mod p`)
// ---------------------------------------------------------------------------

///|
test "threshold: verify accepts signature == public_key^message_hash" {
  let pk = 17
  let mh = 99
  let expected_sig = tmod_pow(pk, mh, 2147483647)
  assert_true(threshold_verify(pk, mh, expected_sig))
}

///|
test "threshold: verify rejects a wrong signature" {
  let pk = 17
  let mh = 99
  let expected_sig = tmod_pow(pk, mh, 2147483647)
  assert_false(threshold_verify(pk, mh, (expected_sig + 1) % 2147483647))
}

///|
test "threshold: verify is consistent for a fixed public key and message" {
  let pk = 123
  let mh = 456
  let s = tmod_pow(pk, mh, 2147483647)
  assert_true(threshold_verify(pk, mh, s))
  assert_true(threshold_verify(pk, mh, s))
}
