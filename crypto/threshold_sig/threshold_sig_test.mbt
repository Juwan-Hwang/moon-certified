// Tests for crypto/threshold_sig — (t, n) threshold Schnorr over
// secp256k1. Adversarial cases included: forgery without enough
// shares, tampered partials, wrong-message rejection.

///|
fn ts_seed(n : Int) -> Bytes {
  let arr : Array[Byte] = []
  for i = 0; i < 32; i = i + 1 {
    arr.push(((n * 31 + i * 7 + 5) & 0xFF).to_byte())
  }
  Bytes::from_array(arr)
}

///|
/// Run one full signing session with the given signer indices.
fn ts_sign_session(
  all_shares : Array[KeyShare],
  signer_indices : Array[Int],
  pubkey : Bytes,
  message : Bytes,
  session_seed : Int,
) -> Bytes raise {
  let nonces : Array[NoncePair] = []
  let commitments : Array[Bytes] = []
  let picked : Array[KeyShare] = []
  for i = 0; i < signer_indices.length(); i = i + 1 {
    let idx = signer_indices[i]
    let nonce = threshold_nonce_generate(ts_seed(session_seed + idx * 977))
    nonces.push(nonce)
    commitments.push(nonce.commitment)
    picked.push(all_shares[idx - 1])
  }
  let partials : Array[Bytes] = []
  for i = 0; i < signer_indices.length(); i = i + 1 {
    partials.push(
      threshold_sign_partial(
        picked[i],
        signer_indices,
        commitments,
        nonces[i],
        pubkey,
        message,
      ),
    )
  }
  threshold_combine_signatures(
    partials,
    picked,
    signer_indices,
    commitments,
    pubkey,
    message,
  )
}

///|
test "threshold_keygen_and_reconstruct" {
  let (pubkey, shares) = threshold_keygen(5, 3, ts_seed(1))
  assert_eq(pubkey.length(), 33)
  assert_eq(shares.length(), 5)
  // Any 3 shares reconstruct the same secret; the reconstructed key
  // must correspond to the group public key.
  let subset : Array[KeyShare] = [shares[0], shares[2], shares[4]]
  let secret = threshold_reconstruct(subset)
  let subset2 : Array[KeyShare] = [shares[1], shares[3], shares[4]]
  assert_eq(threshold_reconstruct(subset2), secret)
}

///|
test "threshold_sign_verify_3_of_5" {
  let (pubkey, shares) = threshold_keygen(5, 3, ts_seed(2))
  let msg = b"moon-certified threshold signing"
  let sig = ts_sign_session(shares, [1, 3, 5], pubkey, msg, 100)
  assert_eq(sig.length(), 65)
  assert_eq(threshold_verify(pubkey, msg, sig), true)
  // Different signer subsets produce valid (different) signatures.
  let sig2 = ts_sign_session(shares, [2, 3, 4], pubkey, msg, 200)
  assert_eq(threshold_verify(pubkey, msg, sig2), true)
}

///|
test "threshold_rejects_wrong_message_and_key" {
  let (pubkey, shares) = threshold_keygen(4, 2, ts_seed(3))
  let msg = b"original message"
  let sig = ts_sign_session(shares, [1, 2], pubkey, msg, 300)
  assert_eq(threshold_verify(pubkey, b"tampered message", sig), false)
  // A different group key must not validate the signature.
  let (other_pk, _) = threshold_keygen(4, 2, ts_seed(4))
  assert_eq(threshold_verify(other_pk, msg, sig), false)
  // Truncated / garbage signatures are rejected, not crashed on.
  assert_eq(threshold_verify(pubkey, msg, Bytes::make(64, b'\x00')), false)
  assert_eq(threshold_verify(pubkey, msg, Bytes::make(65, b'\xff')), false)
}

///|
test "threshold_tampered_partial_rejected" {
  let (pubkey, shares) = threshold_keygen(3, 2, ts_seed(5))
  let msg = b"adversarial partial check"
  let signer_indices = [1, 2]
  let nonces : Array[NoncePair] = []
  let commitments : Array[Bytes] = []
  let picked : Array[KeyShare] = []
  for i = 0; i < signer_indices.length(); i = i + 1 {
    let idx = signer_indices[i]
    let nonce = threshold_nonce_generate(ts_seed(400 + idx * 977))
    nonces.push(nonce)
    commitments.push(nonce.commitment)
    picked.push(shares[idx - 1])
  }
  let partials : Array[Bytes] = []
  for i = 0; i < signer_indices.length(); i = i + 1 {
    partials.push(
      threshold_sign_partial(
        picked[i],
        signer_indices,
        commitments,
        nonces[i],
        pubkey,
        msg,
      ),
    )
  }
  // Corrupt the second partial's scalar.
  let bad = partials[1].to_array()
  bad[31] = (bad[31].to_int() ^ 1).to_byte()
  let bad_partials = [partials[0], Bytes::from_array(bad)]
  let r = Some(
    threshold_combine_signatures(
      bad_partials,
      picked,
      signer_indices,
      commitments,
      pubkey,
      msg,
    ),
  ) catch { _ => None }
  assert_eq(r, None)
}

///|
// The old fake implementation let anyone "sign" without any key
// material. Verify this is no longer possible: without t shares the
// signing API cannot even be invoked meaningfully, and a signature
// under the group key cannot be produced from fewer shares.
test "threshold_no_forgery_without_shares" {
  let (pubkey, shares) = threshold_keygen(3, 2, ts_seed(6))
  let msg = b"forgery attempt"
  // A single share (< t) cannot form a valid signer set; attempting a
  // 1-of-3 session produces a signature only over the attacker's own
  // share, which fails group verification.
  let one = [shares[0]]
  let idx1 = [1]
  let nonce = threshold_nonce_generate(ts_seed(500))
  let partial = threshold_sign_partial(
    one[0],
    idx1,
    [nonce.commitment],
    nonce,
    pubkey,
    msg,
  )
  let attempt = Some(
    threshold_combine_signatures(
      [partial],
      one,
      idx1,
      [nonce.commitment],
      pubkey,
      msg,
    ),
  ) catch { _ => None }
  match attempt {
    Some(sig) => assert_eq(threshold_verify(pubkey, msg, sig), false)
    None => ()
  }
}

///|
test "threshold_signature_is_deterministic_per_session" {
  let (pubkey, shares) = threshold_keygen(3, 2, ts_seed(7))
  let msg = b"determinism"
  let s1 = ts_sign_session(shares, [1, 3], pubkey, msg, 600)
  let s2 = ts_sign_session(shares, [1, 3], pubkey, msg, 600)
  assert_eq(s1.length(), s2.length())
  let mut same = true
  for i = 0; i < s1.length(); i = i + 1 {
    if s1[i] != s2[i] {
      same = false
    }
  }
  assert_eq(same, true)
}
