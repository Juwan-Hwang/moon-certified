// Tests for crypto/bulletproofs — Pedersen commitments and
// inner-product-argument range proofs over secp256k1.

///|
fn bp_seed(n : Int) -> Bytes {
  let arr : Array[Byte] = []
  for i = 0; i < 40; i = i + 1 {
    arr.push(((n * 61 + i * 31 + 5) & 0xFF).to_byte())
  }
  Bytes::from_array(arr)
}

///|
test "bp_pedersen_commit_deterministic" {
  let key = CommitmentKey::new()
  let blind = bp_random_blinding(bp_seed(1))
  let c1 = pedersen_commit(key, 42, blind)
  let c2 = pedersen_commit(key, 42, blind)
  assert_eq(c1.length(), 33)
  assert_eq(c1, c2)
  // Different value or blinding yields a different commitment
  // (hiding).
  let c3 = pedersen_commit(key, 43, blind)
  assert_true(c1 != c3)
  let c4 = pedersen_commit(key, 42, bp_random_blinding(bp_seed(2)))
  assert_true(c1 != c4)
}

///|
test "bp_range_proof_valid_values" {
  let key = CommitmentKey::new()
  let blind = bp_random_blinding(bp_seed(3))
  let value = 1234567
  let commitment = pedersen_commit(key, value, blind)
  let proof = prove_range(key, value, blind)
  assert_eq(proof.data.length(), 622)
  assert_eq(verify_range(key, commitment, proof), true)
}

///|
test "bp_range_proof_boundaries" {
  let key = CommitmentKey::new()
  // Zero.
  let b0 = bp_random_blinding(bp_seed(4))
  let c0 = pedersen_commit(key, 0, b0)
  let p0 = prove_range(key, 0, b0)
  assert_eq(verify_range(key, c0, p0), true)
  // Maximum representable value 2^32 - 1.
  let bmax = bp_random_blinding(bp_seed(5))
  let vmax = 2147483647 // largest positive Int here; full 32-bit max
  let cmax = pedersen_commit(key, vmax, bmax)
  let pmax = prove_range(key, vmax, bmax)
  assert_eq(verify_range(key, cmax, pmax), true)
}

///|
test "bp_range_proof_rejects_wrong_commitment" {
  let key = CommitmentKey::new()
  let blind = bp_random_blinding(bp_seed(6))
  let commitment = pedersen_commit(key, 999, blind)
  let proof = prove_range(key, 999, blind)
  assert_eq(verify_range(key, commitment, proof), true)
  // The same proof must not validate against a commitment to another
  // value (soundness against commitment switching).
  let other_blind = bp_random_blinding(bp_seed(7))
  let other_commitment = pedersen_commit(key, 1000, other_blind)
  assert_eq(verify_range(key, other_commitment, proof), false)
}

///|
test "bp_range_proof_rejects_tampering" {
  let key = CommitmentKey::new()
  let blind = bp_random_blinding(bp_seed(8))
  let commitment = pedersen_commit(key, 777, blind)
  let proof = prove_range(key, 777, blind)
  // Flip bits in the middle of the proof (t̂ region).
  let tampered = proof.data.to_array()
  tampered[200] = (tampered[200].to_int() ^ 0x01).to_byte()
  assert_eq(
    verify_range(key, commitment, RangeProof::new(Bytes::from_array(tampered))),
    false,
  )
  // Truncated proof is rejected.
  let short : Array[Byte] = []
  for i = 0; i < 100; i = i + 1 {
    short.push(proof.data[i])
  }
  assert_eq(
    verify_range(key, commitment, RangeProof::new(Bytes::from_array(short))),
    false,
  )
}

///|
test "bp_rejects_negative_value" {
  let key = CommitmentKey::new()
  let blind = bp_random_blinding(bp_seed(9))
  let r = Some(prove_range(key, -1, blind)) catch { _ => None }
  match r {
    Some(_) => fail("negative value accepted")
    None => ()
  }
}
