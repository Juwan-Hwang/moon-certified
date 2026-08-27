///|
/// FHE — BFV Brakerski/Fan-Vercauteren Somewhat-Homomorphic Encryption
///
/// A real BFV implementation over the polynomial ring
/// Z_q[x]/(x^n + 1): Δ-scaled encoding, RLWE-based encryption,
/// coefficient-wise plaintext arithmetic, ciphertext × ciphertext
/// multiplication via tensor product with Fan-Vercauteren t/q
/// rescaling, and relinearization with an evaluation key.
///
/// ## Operations
///
/// - Addition / subtraction / negation / plaintext-scalar
///   multiplication: unlimited (noise grows additively).
/// - Ciphertext × ciphertext multiplication: supported at depth 1
///   with the demonstration parameters below (tensor + relinearize).
///
/// ## Parameters (demonstration profile)
///
/// - n = 64 (ring degree), q = 998244353 (2^29.9, prime), t = 257
///   (plaintext modulus). Δ = floor(q / t).
/// - Secret/error distributions: ternary {-1, 0, 1}.
/// - These parameters give NO meaningful cryptographic security; they
///   are chosen so the scheme mathematics runs exactly on this
///   platform. Production FHE requires n >= 4096 and multi-prime q of
///   109+ bits (Homomorphic Encryption Security Standard); the
///   algorithm here is the same, only the parameterization differs.
///
/// ## Correctness condition
///
/// Decryption succeeds while the total noise stays below Δ/2. Fresh
/// ciphertexts carry ternary noise; one multiplication followed by
/// relinearization stays inside the budget for these parameters.
///
/// ## References
///
/// - Brakerski, "Fully Homomorphic Encryption without Modulus
///   Switching from Classical GapSVP." CRYPTO 2012.
/// - Fan, Vercauteren, "Somewhat Practical Fully Homomorphic
///   Encryption." IACR ePrint 2012/144.
///
/// `proof-enabled` is `false`.

///|
/// Ring degree (power of two).
pub const BFV_N : Int = 64

///|
/// Ciphertext modulus (prime).
pub const BFV_Q : Int = 998244353

///|
/// Plaintext modulus (prime, < BFV_Q).
pub const BFV_T : Int = 257

///|
/// Relinearization decomposition base (bits per digit).
const BFV_RELIN_BASE_BITS : Int = 8

///|
/// Number of base digits covering residues mod BFV_Q
/// (ceil(30 / 8) = 4).
const BFV_RELIN_DIGITS : Int = 4

// ===========================================================================
// Field helpers
// ===========================================================================

///|
fn bfv_mod(a : Int, m : Int) -> Int {
  let r = a % m
  if r < 0 {
    r + m
  } else {
    r
  }
}

///|
fn bfv_add_mod(a : Int, b : Int, m : Int) -> Int {
  let s = a.to_int64() + b.to_int64()
  (s % m.to_int64()).to_int()
}

///|
fn bfv_sub_mod(a : Int, b : Int, m : Int) -> Int {
  bfv_mod(a - b, m)
}

///|
fn bfv_mul_mod(a : Int, b : Int, m : Int) -> Int {
  (a.to_int64() * b.to_int64() % m.to_int64()).to_int()
}

// ===========================================================================
// CSPRNG plumbing
// ===========================================================================

///|
fn bfv_rng(seed : Bytes) -> @chacha20.ChaCha20Rng raise {
  let key = @sha256.sha256(seed)
  let nsrc = @sha256.sha256(seed + b"bfv-nonce")
  let narr : Array[Byte] = []
  for i = 0; i < 12; i = i + 1 {
    narr.push(nsrc[i])
  }
  match @chacha20.create_rng(key, Bytes::from_array(narr)) {
    Some(r) => r
    None => fail("bfv: CSPRNG init failed")
  }
}

///|
/// Uniform field element in [0, BFV_Q) via rejection sampling.
fn bfv_rand_uniform(rng : @chacha20.ChaCha20Rng) -> Int raise {
  // Sample 31 bits and reject values >= q.
  let mut result = -1
  while result < 0 {
    match @chacha20.next_uint32(rng) {
      Some(v) => {
        let x = v & 0x7FFFFFFFU
        if x < BFV_Q.reinterpret_as_uint() {
          result = x.reinterpret_as_int()
        }
      }
      None => fail("bfv: CSPRNG exhausted")
    }
  }
  result
}

///|
/// Ternary sample: value in {-1, 0, 1} represented mod BFV_Q.
fn bfv_rand_ternary(rng : @chacha20.ChaCha20Rng) -> Int raise {
  match @chacha20.next_int_in_range(rng, 3) {
    Some(0) => BFV_Q - 1 // -1
    Some(1) => 0
    Some(_) => 1
    None => fail("bfv: CSPRNG exhausted")
  }
}

///|
fn bfv_rand_poly_uniform(rng : @chacha20.ChaCha20Rng) -> Array[Int] raise {
  let p = Array::make(BFV_N, 0)
  for i = 0; i < BFV_N; i = i + 1 {
    p[i] = bfv_rand_uniform(rng)
  }
  p
}

///|
fn bfv_rand_poly_ternary(rng : @chacha20.ChaCha20Rng) -> Array[Int] raise {
  let p = Array::make(BFV_N, 0)
  for i = 0; i < BFV_N; i = i + 1 {
    p[i] = bfv_rand_ternary(rng)
  }
  p
}

// ===========================================================================
// Ring arithmetic in Z_q[x] / (x^n + 1)
// ===========================================================================

///|
fn bfv_poly_add(a : Array[Int], b : Array[Int]) -> Array[Int] {
  let r = Array::make(BFV_N, 0)
  for i = 0; i < BFV_N; i = i + 1 {
    r[i] = bfv_add_mod(a[i], b[i], BFV_Q)
  }
  r
}

///|
fn bfv_poly_sub(a : Array[Int], b : Array[Int]) -> Array[Int] {
  let r = Array::make(BFV_N, 0)
  for i = 0; i < BFV_N; i = i + 1 {
    r[i] = bfv_sub_mod(a[i], b[i], BFV_Q)
  }
  r
}

///|
fn bfv_poly_neg(a : Array[Int]) -> Array[Int] {
  let r = Array::make(BFV_N, 0)
  for i = 0; i < BFV_N; i = i + 1 {
    r[i] = if a[i] == 0 { 0 } else { BFV_Q - a[i] }
  }
  r
}

///|
fn bfv_poly_mul(a : Array[Int], b : Array[Int]) -> Array[Int] {
  // Schoolbook negacyclic convolution modulo q; the accumulator is
  // reduced every step (a[i] < q, b[j] < q, so each partial sum stays
  // below 2^60 in Int64).
  let q64 = BFV_Q.to_int64()
  let acc = Array::make(BFV_N, 0L)
  for i = 0; i < BFV_N; i = i + 1 {
    if a[i] == 0 {
      continue
    }
    let ai = a[i].to_int64()
    for j = 0; j < BFV_N; j = j + 1 {
      let k = i + j
      let idx = if k < BFV_N { k } else { k - BFV_N }
      let prod = ai * b[j].to_int64()
      if k < BFV_N {
        acc[idx] = (acc[idx] + prod) % q64
      } else {
        acc[idx] = (acc[idx] - prod) % q64
      }
    }
  }
  let r = Array::make(BFV_N, 0)
  for i = 0; i < BFV_N; i = i + 1 {
    let v = acc[i] % q64
    r[i] = (if v < 0L { v + q64 } else { v }).to_int()
  }
  r
}

// ===========================================================================
// Exact (big-integer) ring arithmetic for BFV rescaling
// ===========================================================================

///|
fn bfv_big(v : Int) -> @bigint.BigInt {
  @bigint.from_int_value(v)
}

///|
/// Exact negacyclic product over the integers (coefficients are exact
/// sums of at most n products of residues < q).
fn bfv_poly_mul_exact(a : Array[Int], b : Array[Int]) -> Array[@bigint.BigInt] {
  let acc : Array[@bigint.BigInt] = []
  for _i = 0; _i < BFV_N; _i = _i + 1 {
    acc.push(@bigint.zero())
  }
  for i = 0; i < BFV_N; i = i + 1 {
    if a[i] == 0 {
      continue
    }
    let ai = bfv_big(a[i])
    for j = 0; j < BFV_N; j = j + 1 {
      if b[j] == 0 {
        continue
      }
      let prod = @bigint.mul(ai, bfv_big(b[j]))
      let k = i + j
      if k < BFV_N {
        acc[k] = @bigint.add(acc[k], prod)
      } else {
        acc[k - BFV_N] = @bigint.sub(acc[k - BFV_N], prod)
      }
    }
  }
  acc
}

///|
/// Coefficient-wise rescale: round(t · c / q) mod q, over exact
/// integer coefficients c (BFV Fan-Vercauteren scaling).
fn bfv_scale_round(coeffs : Array[@bigint.BigInt]) -> Array[Int] {
  let q = bfv_big(BFV_Q)
  let t = bfv_big(BFV_T)
  let two = bfv_big(2)
  let r = Array::make(BFV_N, 0)
  for i = 0; i < BFV_N; i = i + 1 {
    let c = coeffs[i]
    // Handle negative exact coefficients by centering.
    let neg = @bigint.compare(c, @bigint.zero()) < 0
    let abs_c = if neg { @bigint.negate(c) } else { c }
    let v = @bigint.mul(t, abs_c)
    match @bigint.divmod(v, q) {
      Some((qq, rem)) => {
        // Round half up: add one when 2*rem >= q.
        let mut out = qq
        match @bigint.divmod(@bigint.mul(two, rem), q) {
          Some((cmp, _)) =>
            if @bigint.compare(cmp, @bigint.zero()) >= 0 {
              out = @bigint.add(out, @bigint.one())
            }
          None => ()
        }
        match @bigint.divmod(out, q) {
          Some((_, mr)) =>
            match @bigint.to_int(mr) {
              Some(iv) => r[i] = if neg { bfv_mod(-iv, BFV_Q) } else { iv }
              None => r[i] = 0
            }
          None => r[i] = 0
        }
      }
      None => r[i] = 0
    }
  }
  r
}

// ===========================================================================
// Key generation, encryption, decryption
// ===========================================================================

///|
pub struct BfvSecretKey {
  poly : Array[Int]
}

///|
pub struct BfvPublicKey {
  p0 : Array[Int]
  p1 : Array[Int]
}

///|
/// Evaluation (relinearization) key: BFV_RELIN_DIGITS pairs, one per
/// base-2^8 digit of the quadratic component.
pub struct BfvEvalKey {
  e0 : Array[Array[Int]]
  e1 : Array[Array[Int]]
}

///|
pub struct BfvCiphertext {
  c0 : Array[Int]
  c1 : Array[Int]
}

///|
/// Generate a BFV key pair. `seed` must be fresh entropy.
pub fn bfv_keygen(seed : Bytes) -> (BfvPublicKey, BfvSecretKey) raise {
  let rng = bfv_rng(seed)
  let s = bfv_rand_poly_ternary(rng)
  let a = bfv_rand_poly_uniform(rng)
  let e = bfv_rand_poly_ternary(rng)
  // pk = (-(a·s) + e, a)
  let p0 = bfv_poly_add(bfv_poly_neg(bfv_poly_mul(a, s)), e)
  ({ p0, p1: a }, { poly: s })
}

///|
/// Derive the evaluation key for ciphertext multiplication, one
/// component per base-2^8 digit: evk_j = (-(a_j·s) + e_j + T^j·s^2, a_j).
pub fn bfv_eval_key(sk : BfvSecretKey, seed : Bytes) -> BfvEvalKey raise {
  let rng = bfv_rng(seed)
  let s2 = bfv_poly_mul(sk.poly, sk.poly)
  let e0s : Array[Array[Int]] = []
  let e1s : Array[Array[Int]] = []
  let mut base_pow = 1 // T^j mod q
  for _j = 0; _j < BFV_RELIN_DIGITS; _j = _j + 1 {
    let a = bfv_rand_poly_uniform(rng)
    let e = bfv_rand_poly_ternary(rng)
    // T^j · s^2
    let scaled_s2 = Array::make(BFV_N, 0)
    for i = 0; i < BFV_N; i = i + 1 {
      scaled_s2[i] = bfv_mul_mod(s2[i], base_pow, BFV_Q)
    }
    let e0 = bfv_poly_add(
      bfv_poly_add(bfv_poly_neg(bfv_poly_mul(a, sk.poly)), e),
      scaled_s2,
    )
    e0s.push(e0)
    e1s.push(a)
    base_pow = bfv_mul_mod(base_pow, 1 << BFV_RELIN_BASE_BITS, BFV_Q)
  }
  { e0: e0s, e1: e1s }
}

///|
/// Encrypt a plaintext message (coefficients mod BFV_T).
pub fn bfv_encrypt(
  pk : BfvPublicKey,
  message : Array[Int],
  seed : Bytes,
) -> BfvCiphertext raise {
  if message.length() != BFV_N {
    fail("bfv: message must have BFV_N coefficients")
  }
  let rng = bfv_rng(seed)
  let u = bfv_rand_poly_ternary(rng)
  let e1 = bfv_rand_poly_ternary(rng)
  let e2 = bfv_rand_poly_ternary(rng)
  let delta = BFV_Q / BFV_T
  let scaled = Array::make(BFV_N, 0)
  for i = 0; i < BFV_N; i = i + 1 {
    scaled[i] = bfv_mul_mod(bfv_mod(message[i], BFV_T), delta, BFV_Q)
  }
  // ct = (pk0·u + e1 + Δ·m, pk1·u + e2)
  let c0 = bfv_poly_add(bfv_poly_add(bfv_poly_mul(pk.p0, u), e1), scaled)
  let c1 = bfv_poly_add(bfv_poly_mul(pk.p1, u), e2)
  { c0, c1 }
}

///|
/// Decrypt a ciphertext back to plaintext coefficients mod BFV_T.
pub fn bfv_decrypt(sk : BfvSecretKey, ct : BfvCiphertext) -> Array[Int] {
  let v = bfv_poly_add(ct.c0, bfv_poly_mul(ct.c1, sk.poly))
  let r = Array::make(BFV_N, 0)
  for i = 0; i < BFV_N; i = i + 1 {
    // Centered representative in (-q/2, q/2].
    let mut x = v[i].to_int64()
    if x > BFV_Q.to_int64() / 2L {
      x = x - BFV_Q.to_int64()
    }
    // m = round(v · t / q) mod t
    let num = x * BFV_T.to_int64()
    let half = BFV_Q.to_int64() / 2L
    let rounded = if num >= 0L {
      (num + half) / BFV_Q.to_int64()
    } else {
      (num - half) / BFV_Q.to_int64()
    }
    let m = rounded % BFV_T.to_int64()
    r[i] = (if m < 0L { m + BFV_T.to_int64() } else { m }).to_int()
  }
  r
}

// ===========================================================================
// Homomorphic operations
// ===========================================================================

///|
/// Homomorphic addition.
pub fn bfv_add(ct1 : BfvCiphertext, ct2 : BfvCiphertext) -> BfvCiphertext {
  { c0: bfv_poly_add(ct1.c0, ct2.c0), c1: bfv_poly_add(ct1.c1, ct2.c1) }
}

///|
/// Homomorphic subtraction.
pub fn bfv_sub(ct1 : BfvCiphertext, ct2 : BfvCiphertext) -> BfvCiphertext {
  { c0: bfv_poly_sub(ct1.c0, ct2.c0), c1: bfv_poly_sub(ct1.c1, ct2.c1) }
}

///|
/// Homomorphic negation.
pub fn bfv_negate(ct : BfvCiphertext) -> BfvCiphertext {
  { c0: bfv_poly_neg(ct.c0), c1: bfv_poly_neg(ct.c1) }
}

///|
/// Homomorphic multiplication by a plaintext scalar (mod BFV_T).
/// Scaling by k (not k·Δ): decrypt(c·k) = round(t/q·k·(Δ·m + e)) = k·m.
pub fn bfv_mul_scalar(ct : BfvCiphertext, k : Int) -> BfvCiphertext {
  let kk = bfv_mod(k, BFV_Q)
  let c0 = Array::make(BFV_N, 0)
  let c1 = Array::make(BFV_N, 0)
  for i = 0; i < BFV_N; i = i + 1 {
    c0[i] = bfv_mul_mod(ct.c0[i], kk, BFV_Q)
    c1[i] = bfv_mul_mod(ct.c1[i], kk, BFV_Q)
  }
  { c0, c1 }
}

///|
/// Homomorphic ciphertext × ciphertext multiplication with
/// relinearization: tensor product, Fan-Vercauteren t/q rescaling, and
/// base-decomposed evaluation-key relinearization (key switching)
/// back to two components.
pub fn bfv_mul(
  ct1 : BfvCiphertext,
  ct2 : BfvCiphertext,
  evk : BfvEvalKey,
) -> BfvCiphertext {
  // Tensor product (exact integer coefficients).
  let h0 = bfv_scale_round(bfv_poly_mul_exact(ct1.c0, ct2.c0))
  let h1 = bfv_scale_round(
    bfv_poly_add_exact(
      bfv_poly_mul_exact(ct1.c0, ct2.c1),
      bfv_poly_mul_exact(ct1.c1, ct2.c0),
    ),
  )
  let h2 = bfv_scale_round(bfv_poly_mul_exact(ct1.c1, ct2.c1))
  // Decompose h2 into base-2^8 digits and relinearize:
  // (h0 + Σ_j h2_j·evk0_j, h1 + Σ_j h2_j·evk1_j)
  let mut c0 = h0
  let mut c1 = h1
  let mask = (1 << BFV_RELIN_BASE_BITS) - 1
  for j = 0; j < BFV_RELIN_DIGITS; j = j + 1 {
    let shift = j * BFV_RELIN_BASE_BITS
    let digit = Array::make(BFV_N, 0)
    for i = 0; i < BFV_N; i = i + 1 {
      digit[i] = (h2[i] >> shift) & mask
    }
    c0 = bfv_poly_add(c0, bfv_poly_mul(digit, evk.e0[j]))
    c1 = bfv_poly_add(c1, bfv_poly_mul(digit, evk.e1[j]))
  }
  { c0, c1 }
}

///|
/// Exact (big-integer) addition of two exact products.
fn bfv_poly_add_exact(
  a : Array[@bigint.BigInt],
  b : Array[@bigint.BigInt],
) -> Array[@bigint.BigInt] {
  let r : Array[@bigint.BigInt] = []
  for i = 0; i < BFV_N; i = i + 1 {
    r.push(@bigint.add(a[i], b[i]))
  }
  r
}
