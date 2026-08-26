/// BLS Signatures — Boneh-Lynn-Shacham Signature Scheme
///
/// Production implementation of the BLS signature scheme on the BLS12-381
/// elliptic curve, using the optimal Ate pairing from the `pairing` module.
///
/// ## Scheme Overview
///
/// - **Key generation**: Choose secret scalar s in [1, r-1].
///   Public key: P = s * G2 (in G2 for proof-of-possession)
/// - **Signing**: σ = s * H(m) where H maps to G1 (hash-to-curve)
/// - **Verification**: Check e(σ, G2) == e(H(m), P)
///
/// ## Aggregation
///
/// BLS signatures support:
/// - **Aggregation**: Given signatures σ_1, ..., σ_n on distinct messages
///   m_1, ..., m_n from public keys P_1, ..., P_n, the aggregate signature
///   is σ = σ_1 + ... + σ_n (point addition in G1).
/// - **Batch verification**: Check e(σ, G2) == ∏ e(H(m_i), P_i)
///
/// ## References
///
/// - Boneh, Lynn, Shacham: "Short Signatures from the Weil Pairing" (2001)
/// - RFC 9380: "Hashing to Elliptic Curves" (2023) — hash-to-curve
/// - BLS signature specification (https://www.ietf.org/id/draft-irtf-cfrg-bls-signature-05.html)

///|
/// BLS12-381 scalar field order r
/// r = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001
pub let bls_order : @bigint.BigInt = match(@bigint.from_string(
  "0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001",
)) {
  Some(v) => v
  None => abort("FATAL: invalid BLS12-381 order")
}

///|
/// BLS private key: a scalar in [1, r-1]
pub struct BlsPrivateKey {
  secret : @bigint.BigInt
}

///|
/// BLS public key: a point in G2
pub struct BlsPublicKey {
  point : @pairing.G2Point
}

///|
/// BLS signature: a point in G1
pub struct BlsSignature {
  point : @pairing.G1Point
}

///|
/// Generate a BLS key pair from a secret scalar.
/// The secret must be in [1, r-1].
pub fn keygen(secret : @bigint.BigInt) -> (BlsPrivateKey, BlsPublicKey) {
  let sk : BlsPrivateKey = { secret, }
  let g2 = @pairing.g2_generator()
  let pk_point = @pairing.g2_scalar_mul(secret, g2)
  let pk : BlsPublicKey = { point: pk_point }
  (sk, pk)
}

///|
/// Hash a message to a point in the prime-order subgroup G1.
///
/// Full RFC 9380 implementation of the suite
/// `BLS12381G1_XMD:SHA-256_SSWU_RO_`: expand_message_xmd with SHA-256,
/// hash_to_field, the simplified SWU map onto the isogenous curve E',
/// the 11-isogeny map back to E, and cofactor clearing with h_eff
/// (see `hash_to_curve.mbt`).
fn hash_to_g1(msg : String) -> @pairing.G1Point {
  hash_to_curve_g1(@utf8.encode(msg))
}

///|
/// Sign a message with a BLS private key.
/// σ = secret * H(m) in G1
pub fn sign(sk : BlsPrivateKey, msg : String) -> BlsSignature {
  let h = hash_to_g1(msg)
  let sig_point = @pairing.g1_scalar_mul(sk.secret, h)
  ({ point: sig_point } : BlsSignature)
}

///|
/// Verify a BLS signature.
/// Checks: e(σ, G2) == e(H(m), P)
pub fn verify(
  pk : BlsPublicKey,
  msg : String,
  sig : BlsSignature,
) -> Bool {
  // e(σ, G2)
  let g2 = @pairing.g2_generator()
  let lhs = @pairing.pairing(sig.point, g2)
  // e(H(m), P)
  let h = hash_to_g1(msg)
  let rhs = @pairing.pairing(h, pk.point)
  @pairing.fp12_eq(lhs, rhs)
}

///|
/// Aggregate multiple BLS signatures (point addition in G1).
pub fn aggregate_signatures(sigs : Array[BlsSignature]) -> BlsSignature {
  let mut result = @pairing.g1_identity()
  for sig in sigs {
    result = @pairing.g1_add(result, sig.point)
  }
  ({ point: result } : BlsSignature)
}

///|
/// Verify an aggregate BLS signature.
/// Checks: e(σ, G2) == ∏ e(H(m_i), P_i)
pub fn verify_aggregate(
  pks : Array[BlsPublicKey],
  msgs : Array[String],
  sig : BlsSignature,
) -> Bool {
  // e(σ, G2)
  let g2 = @pairing.g2_generator()
  let lhs = @pairing.pairing(sig.point, g2)
  // ∏ e(H(m_i), P_i)
  let mut rhs = @pairing.fp12_one()
  for i in 0..<pks.length() {
    let h = hash_to_g1(msgs[i])
    let pairing_val = @pairing.pairing(h, pks[i].point)
    rhs = @pairing.fp12_mul(rhs, pairing_val)
  }
  @pairing.fp12_eq(lhs, rhs)
}

///|
/// Batch verify multiple BLS signatures.
/// Each signature is verified independently.
pub fn batch_verify(
  pks : Array[BlsPublicKey],
  msgs : Array[String],
  sigs : Array[BlsSignature],
) -> Bool {
  for i in 0..<pks.length() {
    if !verify(pks[i], msgs[i], sigs[i]) {
      return false
    }
  }
  true
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "bls: key generation produces valid keys" {
  let secret = @bigint.from_int_value(42)
  let (_, pk) = keygen(secret)
  assert_false(@pairing.g2_is_identity(pk.point))
}

test "bls: sign and verify single message" {
  let secret = @bigint.from_int_value(12345)
  let (sk, pk) = keygen(secret)
  let msg = "Hello, BLS!"
  let sig = sign(sk, msg)
  assert_true(verify(pk, msg, sig))
}

test "bls: verify rejects wrong message" {
  let secret = @bigint.from_int_value(999)
  let (sk, pk) = keygen(secret)
  let sig = sign(sk, "original message")
  assert_false(verify(pk, "tampered message", sig))
}

test "bls: verify rejects wrong public key" {
  let secret1 = @bigint.from_int_value(111)
  let secret2 = @bigint.from_int_value(222)
  let (sk1, _) = keygen(secret1)
  let (_, pk2) = keygen(secret2)
  let sig = sign(sk1, "test message")
  assert_false(verify(pk2, "test message", sig))
}

test "bls: aggregate signature verification" {
  let secret1 = @bigint.from_int_value(100)
  let secret2 = @bigint.from_int_value(200)
  let (sk1, pk1) = keygen(secret1)
  let (sk2, pk2) = keygen(secret2)
  let msg1 = "message from signer 1"
  let msg2 = "message from signer 2"
  let sig1 = sign(sk1, msg1)
  let sig2 = sign(sk2, msg2)
  let agg_sig = aggregate_signatures([sig1, sig2])
  assert_true(verify_aggregate([pk1, pk2], [msg1, msg2], agg_sig))
}

test "bls: batch verify" {
  let secret1 = @bigint.from_int_value(10)
  let secret2 = @bigint.from_int_value(20)
  let (sk1, pk1) = keygen(secret1)
  let (sk2, pk2) = keygen(secret2)
  let sig1 = sign(sk1, "msg1")
  let sig2 = sign(sk2, "msg2")
  assert_true(batch_verify([pk1, pk2], ["msg1", "msg2"], [sig1, sig2]))
}

test "bls: batch verify detects tampered signature" {
  let secret1 = @bigint.from_int_value(10)
  let secret2 = @bigint.from_int_value(20)
  let (sk1, _) = keygen(secret1)
  let (sk2, pk2) = keygen(secret2)
  let _ = sign(sk1, "msg1")
  let sig2 = sign(sk2, "msg2")
  let (_, pk1) = keygen(secret1)
  assert_false(batch_verify([pk1, pk2], ["msg1", "msg2"], [sig2, sig2]))
}

test "bls: hash-to-curve output is on E and in the r-order subgroup" {
  // RFC 9380: the hashed point must lie on y² = x³ + 4 and satisfy [r]P = O.
  let p = hash_to_g1("hash-to-curve subgroup test")
  assert_false(@pairing.g1_is_identity(p))
  let (x, y) = @pairing.g1_to_affine(p)
  assert_true(@pairing.g1_is_on_curve(x, y))
  assert_true(@pairing.g1_is_identity(@pairing.g1_scalar_mul(bls_order, p)))
}

test "bls: hash-to-curve is deterministic and injective on distinct inputs" {
  let p1 = hash_to_g1("same message")
  let p2 = hash_to_g1("same message")
  let p3 = hash_to_g1("different message")
  assert_true(@pairing.g1_eq(p1, p2))
  assert_false(@pairing.g1_eq(p1, p3))
}
