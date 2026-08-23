///|
/// Comprehensive tests for Bulletproofs range proofs.

// ===========================================================================
// Pedersen commitment tests
// ===========================================================================

test "pedersen_commit: basic commitment" {
  let key = CommitmentKey::new(3, 5)
  let c = pedersen_commit(key, 7, 11)
  // C = G^value * H^blinding mod p = 3^7 * 5^11 mod 2147483647
  let expected = mod_pow_for_test(3, 7, 2147483647) *
    mod_pow_for_test(5, 11, 2147483647) %
    2147483647
  assert_eq(c, expected)
}

///|
test "pedersen_commit: zero value" {
  let key = CommitmentKey::new(3, 5)
  let c = pedersen_commit(key, 0, 11)
  // G^0 = 1, so C = 1 * H^blinding = H^blinding
  let expected = mod_pow_for_test(5, 11, 2147483647)
  assert_eq(c, expected)
}

///|
test "pedersen_commit: zero blinding" {
  let key = CommitmentKey::new(3, 5)
  let c = pedersen_commit(key, 7, 0)
  // H^0 = 1, so C = G^value
  let expected = mod_pow_for_test(3, 7, 2147483647)
  assert_eq(c, expected)
}

///|
test "pedersen_commit: both zero" {
  let key = CommitmentKey::new(3, 5)
  let c = pedersen_commit(key, 0, 0)
  // G^0 * H^0 = 1 * 1 = 1
  assert_eq(c, 1)
}

///|
test "pedersen_commit: same value different blinding produces different commitments" {
  let key = CommitmentKey::new(3, 5)
  let c1 = pedersen_commit(key, 42, 10)
  let c2 = pedersen_commit(key, 42, 20)
  assert_true(c1 != c2)
}

///|
test "pedersen_commit: different value same blinding produces different commitments" {
  let key = CommitmentKey::new(3, 5)
  let c1 = pedersen_commit(key, 10, 42)
  let c2 = pedersen_commit(key, 20, 42)
  assert_true(c1 != c2)
}

///|
test "pedersen_commit: homomorphic property (additive)" {
  // Pedersen commitment is homomorphic: C(v1,r1) * C(v2,r2) = C(v1+v2, r1+r2)
  let key = CommitmentKey::new(3, 5)
  let c1 = pedersen_commit(key, 10, 5)
  let c2 = pedersen_commit(key, 20, 7)
  let combined = c1 * c2 % 2147483647
  let direct = pedersen_commit(key, 30, 12)
  assert_eq(combined, direct)
}

// ===========================================================================
// Range proof generation tests
// ===========================================================================

///|
test "prove_range: valid value in range" {
  let key = CommitmentKey::new(3, 5)
  let proof = prove_range(key, 42, 123, 8)
  assert_true(proof is Some(_))
}

///|
test "prove_range: zero value" {
  let key = CommitmentKey::new(3, 5)
  let proof = prove_range(key, 0, 99, 8)
  assert_true(proof is Some(_))
}

///|
test "prove_range: max value in range" {
  let key = CommitmentKey::new(3, 5)
  let proof = prove_range(key, 255, 7, 8)
  assert_true(proof is Some(_))
}

///|
test "prove_range: value exceeds range returns None" {
  let key = CommitmentKey::new(3, 5)
  // 2^8 = 256, so 256 is out of range
  let proof = prove_range(key, 256, 0, 8)
  assert_true(proof is None)
}

///|
test "prove_range: negative value returns None" {
  let key = CommitmentKey::new(3, 5)
  let proof = prove_range(key, -1, 0, 8)
  assert_true(proof is None)
}

///|
test "prove_range: proof_data contains correct number of entries" {
  let key = CommitmentKey::new(3, 5)
  let proof_opt = prove_range(key, 5, 10, 4)
  match proof_opt {
    Some(p) => assert_eq(p.proof_data.length(), 4 + 2) // n_bits commitments + value + blinding
    None => abort("expected Some")
  }
}

// ===========================================================================
// Range proof verification tests
// ===========================================================================

///|
test "verify_range: valid proof verifies" {
  let key = CommitmentKey::new(3, 5)
  let value = 42
  let blinding = 123
  let n_bits = 8
  let commitment = pedersen_commit(key, value, blinding)
  let proof_opt = prove_range(key, value, blinding, n_bits)
  match proof_opt {
    Some(p) => assert_eq(verify_range(key, commitment, p, n_bits), true)
    None => abort("expected Some")
  }
}

///|
test "verify_range: zero value proof" {
  let key = CommitmentKey::new(3, 5)
  let commitment = pedersen_commit(key, 0, 5)
  let proof_opt = prove_range(key, 0, 5, 8)
  match proof_opt {
    Some(p) => assert_eq(verify_range(key, commitment, p, 8), true)
    None => abort("expected Some")
  }
}

///|
test "verify_range: max value proof" {
  let key = CommitmentKey::new(3, 5)
  let value = 255
  let blinding = 1
  let commitment = pedersen_commit(key, value, blinding)
  let proof_opt = prove_range(key, value, blinding, 8)
  match proof_opt {
    Some(p) => assert_eq(verify_range(key, commitment, p, 8), true)
    None => abort("expected Some")
  }
}

///|
test "verify_range: wrong commitment fails" {
  let key = CommitmentKey::new(3, 5)
  let value = 42
  let blinding = 123
  let proof_opt = prove_range(key, value, blinding, 8)
  // Use a different commitment (for value 99)
  let wrong_commitment = pedersen_commit(key, 99, 1)
  match proof_opt {
    Some(p) => assert_eq(verify_range(key, wrong_commitment, p, 8), false)
    None => abort("expected Some")
  }
}

///|
test "verify_range: tampered proof fails" {
  let key = CommitmentKey::new(3, 5)
  let value = 42
  let blinding = 123
  let commitment = pedersen_commit(key, value, blinding)
  let proof_opt = prove_range(key, value, blinding, 8)
  match proof_opt {
    Some(p) => {
      // Tamper: change the stored value
      let tampered = RangeProof::new(p.proof_data.copy())
      let last_idx = tampered.proof_data.length() - 2
      tampered.proof_data[last_idx] = 99
      assert_eq(verify_range(key, commitment, tampered, 8), false)
    }
    None => abort("expected Some")
  }
}

///|
test "verify_range: proof with too few entries fails" {
  let key = CommitmentKey::new(3, 5)
  let short_proof = RangeProof::new([1, 2])
  assert_eq(verify_range(key, 100, short_proof, 8), false)
}

///|
test "verify_range: round-trip for multiple values" {
  let key = CommitmentKey::new(3, 5)
  for v in [0, 1, 10, 50, 100, 200, 255] {
    let blinding = v * 3 + 1
    let commitment = pedersen_commit(key, v, blinding)
    let proof_opt = prove_range(key, v, blinding, 8)
    match proof_opt {
      Some(p) => assert_eq(verify_range(key, commitment, p, 8), true)
      None => abort("expected Some for value \{v}")
    }
  }
}

///|
test "verify_range: different bit widths" {
  let key = CommitmentKey::new(3, 5)
  for n_bits in [1, 2, 4, 8, 16] {
    let max_val = (1 << n_bits) - 1
    let value = max_val / 2
    let blinding = 5
    let commitment = pedersen_commit(key, value, blinding)
    let proof_opt = prove_range(key, value, blinding, n_bits)
    match proof_opt {
      Some(p) => assert_eq(verify_range(key, commitment, p, n_bits), true)
      None => abort("expected Some for n_bits=\{n_bits}")
    }
  }
}

// Helper: local mod_pow to avoid dependency on private function

///|
fn mod_pow_for_test(base : Int, exp : Int, m : Int) -> Int {
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
