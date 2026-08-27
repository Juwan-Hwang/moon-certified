// Tests for crypto/fhe — BFV somewhat-homomorphic encryption.

///|
fn fhe_seed(n : Int) -> Bytes {
  let arr : Array[Byte] = []
  for i = 0; i < 40; i = i + 1 {
    arr.push(((n * 53 + i * 29 + 11) & 0xFF).to_byte())
  }
  Bytes::from_array(arr)
}

///|
fn fhe_msg(vals : Array[Int]) -> Array[Int] {
  let m = Array::make(BFV_N, 0)
  for i = 0; i < vals.length() && i < BFV_N; i = i + 1 {
    m[i] = vals[i]
  }
  m
}

///|
fn fhe_msg_eq(a : Array[Int], b : Array[Int]) -> Bool {
  for i = 0; i < BFV_N; i = i + 1 {
    if a[i] != b[i] {
      return false
    }
  }
  true
}

///|
test "bfv_encrypt_decrypt_roundtrip" {
  let (pk, sk) = bfv_keygen(fhe_seed(1))
  let m = fhe_msg([3, 7, 0, 256, 1, 128, 42])
  let ct = bfv_encrypt(pk, m, fhe_seed(2))
  let dec = bfv_decrypt(sk, ct)
  assert_eq(fhe_msg_eq(dec, m), true)
  // A different message round-trips too.
  let m2 = fhe_msg([100, 200, 250, 17])
  let ct2 = bfv_encrypt(pk, m2, fhe_seed(3))
  assert_eq(fhe_msg_eq(bfv_decrypt(sk, ct2), m2), true)
}

///|
test "bfv_homomorphic_add_sub_negate" {
  let (pk, sk) = bfv_keygen(fhe_seed(4))
  let ma = fhe_msg([10, 20, 30])
  let mb = fhe_msg([3, 4, 5])
  let ca = bfv_encrypt(pk, ma, fhe_seed(5))
  let cb = bfv_encrypt(pk, mb, fhe_seed(6))
  // Addition: coefficient-wise, including wraparound mod t.
  let sum = bfv_decrypt(sk, bfv_add(ca, cb))
  assert_eq(sum[0], 13)
  assert_eq(sum[1], 24)
  assert_eq(sum[2], 35)
  // Subtraction with underflow mod t.
  let diff = bfv_decrypt(sk, bfv_sub(cb, ca))
  assert_eq(diff[0], BFV_T - 7)
  assert_eq(diff[1], BFV_T - 16)
  assert_eq(diff[2], BFV_T - 25)
  // Negation.
  let neg = bfv_decrypt(sk, bfv_negate(ca))
  assert_eq(neg[0], BFV_T - 10)
  assert_eq(neg[1], BFV_T - 20)
  assert_eq(neg[2], BFV_T - 30)
  // Adding several ciphertexts accumulates correctly.
  let acc = bfv_add(bfv_add(ca, ca), ca)
  let thrice = bfv_decrypt(sk, acc)
  assert_eq(thrice[0], 30)
  assert_eq(thrice[1], 60)
  assert_eq(thrice[2], 90)
}

///|
test "bfv_homomorphic_scalar_mul" {
  let (pk, sk) = bfv_keygen(fhe_seed(7))
  let m = fhe_msg([5, 11, 19])
  let ct = bfv_encrypt(pk, m, fhe_seed(8))
  let scaled = bfv_decrypt(sk, bfv_mul_scalar(ct, 7))
  assert_eq(scaled[0], 35)
  assert_eq(scaled[1], 77)
  assert_eq(scaled[2], 133)
  // Scalar multiplication modulo t.
  let wrapped = bfv_decrypt(sk, bfv_mul_scalar(ct, BFV_T + 2))
  assert_eq(wrapped[0], 10)
  assert_eq(wrapped[1], 22)
  assert_eq(wrapped[2], 38)
}

///|
// The core claim: ciphertext × ciphertext multiplication through the
// tensor product + relinearization decrypts to the product polynomial
// mod t (negacyclic convolution).
test "bfv_homomorphic_ciphertext_mul" {
  let (pk, sk) = bfv_keygen(fhe_seed(9))
  let evk = bfv_eval_key(sk, fhe_seed(10))
  // Constant polynomials: product is a plain integer product.
  let ma = fhe_msg([6])
  let mb = fhe_msg([7])
  let ca = bfv_encrypt(pk, ma, fhe_seed(11))
  let cb = bfv_encrypt(pk, mb, fhe_seed(12))
  let prod = bfv_decrypt(sk, bfv_mul(ca, cb, evk))
  assert_eq(prod[0], 42)
  // Non-constant polynomials: negacyclic convolution mod t.
  // a = 1 + 2x, b = 3 + x  =>  a·b = 3 + 7x + 2x^2
  let pa = fhe_msg([1, 2])
  let pb = fhe_msg([3, 1])
  let cpa = bfv_encrypt(pk, pa, fhe_seed(13))
  let cpb = bfv_encrypt(pk, pb, fhe_seed(14))
  let pprod = bfv_decrypt(sk, bfv_mul(cpa, cpb, evk))
  assert_eq(pprod[0], 3)
  assert_eq(pprod[1], 7)
  assert_eq(pprod[2], 2)
  assert_eq(pprod[3], 0)
  // Multiplication distributes over addition:
  // (a + a) * b == a*b + a*b
  let lhs = bfv_mul(bfv_add(cpa, cpa), cpb, evk)
  let rhs = bfv_add(bfv_mul(cpa, cpb, evk), bfv_mul(cpa, cpb, evk))
  let dl = bfv_decrypt(sk, lhs)
  let dr = bfv_decrypt(sk, rhs)
  assert_eq(fhe_msg_eq(dl, dr), true)
}

///|
test "bfv_wrong_key_gives_wrong_plaintext" {
  let (pk, _sk) = bfv_keygen(fhe_seed(15))
  let (_pk2, sk2) = bfv_keygen(fhe_seed(16))
  let m = fhe_msg([9, 9, 9])
  let ct = bfv_encrypt(pk, m, fhe_seed(17))
  // Decryption under an unrelated secret key must not recover the
  // message (noise overwhelms the scaled plaintext).
  let dec = bfv_decrypt(sk2, ct)
  assert_eq(fhe_msg_eq(dec, m), false)
}

///|
test "bfv_rejects_bad_message_length" {
  let (pk, _sk) = bfv_keygen(fhe_seed(18))
  let r = Some(bfv_encrypt(pk, [1, 2, 3], fhe_seed(19))) catch { _ => None }
  match r {
    Some(_) => fail("short message accepted")
    None => ()
  }
}
