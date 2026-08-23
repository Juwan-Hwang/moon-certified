///|
test "bls: sign and verify" {
  let (sk, pk) = bls_keygen(42)
  let msg = b"Hello BLS!"
  let sig = bls_sign(sk, msg)
  assert_true(bls_verify(pk, msg, sig))
}

///|
test "bls: wrong message fails" {
  let (sk, pk) = bls_keygen(42)
  let sig = bls_sign(sk, b"message A")
  assert_false(bls_verify(pk, b"message B", sig))
}

///|
test "bls: wrong key fails" {
  let (sk1, _) = bls_keygen(42)
  let (_, pk2) = bls_keygen(99)
  let sig = bls_sign(sk1, b"test")
  assert_false(bls_verify(pk2, b"test", sig))
}

///|
test "bls: aggregate signatures" {
  let (sk1, pk1) = bls_keygen(10)
  let (sk2, pk2) = bls_keygen(20)
  let (sk3, pk3) = bls_keygen(30)
  let msg = b"aggregate test"
  let sig1 = bls_sign(sk1, msg)
  let sig2 = bls_sign(sk2, msg)
  let sig3 = bls_sign(sk3, msg)
  let agg_sig = bls_aggregate_signatures([sig1, sig2, sig3])
  let agg_pk = bls_aggregate_public_keys([pk1, pk2, pk3])
  assert_true(bls_verify_aggregate(agg_pk, msg, agg_sig))
}

///|
test "bls: batch verify" {
  let (sk1, pk1) = bls_keygen(10)
  let (sk2, pk2) = bls_keygen(20)
  let msg1 = b"message one"
  let msg2 = b"message two"
  let sig1 = bls_sign(sk1, msg1)
  let sig2 = bls_sign(sk2, msg2)
  assert_true(bls_batch_verify([(pk1, msg1, sig1), (pk2, msg2, sig2)], 12345))
}

///|
test "bls: batch verify rejects forgery" {
  let (sk1, pk1) = bls_keygen(10)
  let (_, pk2) = bls_keygen(20)
  let msg1 = b"message one"
  let msg2 = b"message two"
  let sig1 = bls_sign(sk1, msg1)
  let sig2 = bls_sign(sk1, msg2) // Wrong key
  assert_false(bls_batch_verify([(pk1, msg1, sig1), (pk2, msg2, sig2)], 99999))
}
