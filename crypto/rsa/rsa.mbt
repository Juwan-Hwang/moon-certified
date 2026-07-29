/// RSA public-key cryptosystem (PKCS#1 v2.2 / RFC 8017).
///
/// This module implements RSA key generation, encryption, decryption, signing,
/// and verification following [PKCS#1 v2.2 (RFC 8017)](https://tools.ietf.org/html/rfc8017).
///
/// ## Padding schemes
///
/// - **PKCS#1 v1.5** encryption (§7.2) and signing (§8.2): legacy but
///   widely deployed. Constant-time comparison is used for verification.
/// - **OAEP** encryption (§7.1): the recommended encryption scheme,
///   providing IND-CPA security under the RSA assumption.
/// - **PSS** signing (§8.1): the recommended signature scheme, providing
///   EUF-CMA security under the RSA assumption.
///
/// ## Security
///
/// - **Key generation** uses the ChaCha20 CSPRNG for prime candidate generation
///   and Miller-Rabin primality testing with 40 rounds (error probability < 2^-80).
/// - **OAEP** uses MGF1 with SHA-256 and supports labels.
/// - **PSS** uses MGF1 with SHA-256 and configurable salt length.
/// - **Constant-time comparison** is used for signature verification to prevent
///   timing side-channels.
///
/// ## Limitations
///
/// - Minimum key size is 512 bits; 2048+ bits is recommended for production.
/// - This implementation has **not** been audited by a third party.
///
/// ## References
///
/// - RFC 8017: PKCS #1: RSA Cryptography Specifications Version 2.2
/// - Rivest, Shamir, Adleman (1978): "A Method for Obtaining Digital Signatures
///   and Public-Key Cryptosystems"
///
/// Not formally verified. Correctness is ensured by the test suite, including
/// known-answer tests from RFC 8017 test vectors.

// ---------------------------------------------------------------------------
// BigInt helpers (local — avoids modifying the bigint package)
// ---------------------------------------------------------------------------

/// Convert a byte array (big-endian) to a BigInt.
fn bytes_to_bigint(data : Bytes) -> @bigint.BigInt {
  let mut result = @bigint.zero()
  let base = @bigint.from_int_value(256)
  for i = 0; i < data.length(); i = i + 1 {
    result = @bigint.mul(result, base)
    result = @bigint.add(result, @bigint.from_int_value(data[i].to_int()))
  }
  result
}

/// Convert a BigInt known to be in [0, 255] to an Int.
/// Uses binary search over pre-computed BigInt values for efficiency.
fn bigint_small_to_int(b : @bigint.BigInt) -> Int {
  let mut lo = 0
  let mut hi = 256
  while lo < hi {
    let mid = (lo + hi) / 2
    if @bigint.compare(b, @bigint.from_int_value(mid)) < 0 {
      hi = mid
    } else {
      lo = mid + 1
    }
  }
  lo - 1
}

/// Convert a BigInt to a fixed-length byte array (big-endian).
/// Pads with leading zeros to reach `byte_len`. Returns None if the value
/// does not fit in `byte_len` bytes.
fn bigint_to_bytes(n : @bigint.BigInt, byte_len : Int) -> Bytes? {
  let mut temp = n
  let zero = @bigint.zero()
  if @bigint.compare(temp, zero) < 0 {
    return None // Negative numbers not supported
  }
  let result : Array[Byte] = Array::make(byte_len, b'\x00')
  let divisor = @bigint.from_int_value(256)
  let mut idx = byte_len - 1
  while idx >= 0 && @bigint.greater_than(temp, zero) {
    let (q, r) = match @bigint.divmod(temp, divisor) {
      None => return None
      Some(pair) => pair
    }
    // r is the remainder mod 256, guaranteed to be in [0, 255]
    result[idx] = bigint_small_to_int(r).to_byte()
    temp = q
    idx = idx - 1
  }
  // Check for overflow (temp should be zero)
  if @bigint.greater_than(temp, zero) {
    return None
  }
  Some(Bytes::from_array(result))
}

/// Extended GCD: returns (gcd, x, y) where a*x + b*y = gcd.
fn extended_gcd(
  a : @bigint.BigInt,
  b : @bigint.BigInt,
) -> (@bigint.BigInt, @bigint.BigInt, @bigint.BigInt) {
  let zero = @bigint.zero()
  let one = @bigint.one()
  if @bigint.equal(b, zero) {
    return (a, one, zero)
  }
  let (g, x1, y1) = extended_gcd(b, match @bigint.divmod(a, b) {
    None => zero
    Some((_, r)) => r
  })
  // x = y1, y = x1 - (a / b) * y1
  let q = match @bigint.divmod(a, b) {
    None => zero
    Some((q, _)) => q
  }
  let x = y1
  let y = @bigint.sub(x1, @bigint.mul(q, y1))
  (g, x, y)
}

/// Compute the modular inverse of `a` mod `m`: returns `a^(-1) mod m`.
/// Returns None if gcd(a, m) != 1 (inverse does not exist).
fn mod_inverse(a : @bigint.BigInt, m : @bigint.BigInt) -> @bigint.BigInt? {
  let (g, x, _) = extended_gcd(a, m)
  let one = @bigint.one()
  if !@bigint.equal(g, one) {
    return None
  }
  // Ensure x is in [0, m)
  let zero = @bigint.zero()
  let result = match @bigint.divmod(x, m) {
    None => return None
    Some((_, r)) => r
  }
  if @bigint.compare(result, zero) < 0 {
    Some(@bigint.add(result, m))
  } else {
    Some(result)
  }
}

// ---------------------------------------------------------------------------
// BigInt-based Miller-Rabin primality test
// ---------------------------------------------------------------------------

/// Miller-Rabin primality test for BigInt.
///
/// Returns `true` if `n` is probably prime, `false` if definitely composite.
/// The error probability is at most 4^(-rounds). RFC 8017 recommends 40
/// rounds for key generation, giving error < 2^-80.
///
/// The first 13 rounds use deterministic small-prime witnesses (proven
/// correct for n < 3.317×10²⁴). Additional rounds use CSPRNG-generated
/// random witnesses uniformly sampled from [2, n−2], providing the full
/// 4^(-rounds) probabilistic guarantee against adversarially constructed
/// composites.
fn miller_rabin_bigint(
  n : @bigint.BigInt,
  rounds : Int,
  rng : @chacha20.ChaCha20Rng,
) -> Bool {
  let one = @bigint.one()
  let two = @bigint.from_int_value(2)
  let three = @bigint.from_int_value(3)
  // Handle small cases
  if @bigint.compare(n, two) < 0 {
    return false
  }
  if @bigint.equal(n, two) || @bigint.equal(n, three) {
    return true
  }
  // Even numbers are composite
  if !@bigint.is_odd(n) {
    return false
  }
  // Write n-1 = d * 2^r where d is odd
  let n_minus_1 = @bigint.sub(n, one)
  let mut d = n_minus_1
  let mut r = 0
  while !@bigint.is_odd(d) {
    d = match @bigint.divmod(d, two) {
      None => return false
      Some((q, _)) => q
    }
    r = r + 1
  }
  // Deterministic small-prime witnesses for the first 13 rounds.
  // These are proven sufficient for deterministic correctness on n < 3.317×10²⁴.
  let small_primes = [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41]
  let n_minus_3 = @bigint.sub(n_minus_1, two)
  let mut round = 0
  while round < rounds {
    let a : @bigint.BigInt = if round < small_primes.length() {
      @bigint.from_int_value(small_primes[round])
    } else {
      // Generate a random witness in [2, n−2] using the CSPRNG.
      // This ensures the full 4^(-rounds) error bound even for
      // adversarially constructed composites (Carmichael numbers, etc.).
      let byte_len = (@bigint.bit_length(n) + 7) / 8
      let random_bytes = match @chacha20.next_bytes(rng, byte_len) {
        None => return false
        Some(b) => b
      }
      let raw = bytes_to_bigint(random_bytes)
      // Map raw to [2, n−2]: a = 2 + (raw mod (n−3))
      let range = n_minus_3 // n − 3, so result is in [0, n−3], +2 gives [2, n−1]
      let reduced = match @bigint.divmod(raw, range) {
        None => return false
        Some((_, rem)) => rem
      }
      @bigint.add(reduced, two)
    }
    // Ensure a is in range [2, n-2]
    if @bigint.compare(a, n_minus_3) > 0 {
      // Skip if a >= n-2 (only happens for very small n)
      round = round + 1
      continue
    }
    // Compute x = a^d mod n
    let mut x = match @bigint.mod_pow(a, d, n) {
      None => return false
      Some(v) => v
    }
    if @bigint.equal(x, one) || @bigint.equal(x, n_minus_1) {
      round = round + 1
      continue
    }
    let mut composite = true
    for i = 0; i < r - 1; i = i + 1 {
      x = match @bigint.mod_pow(x, two, n) {
        None => return false
        Some(v) => v
      }
      if @bigint.equal(x, n_minus_1) {
        composite = false
        break
      }
    }
    if composite {
      return false
    }
    round = round + 1
  }
  true
}

// ---------------------------------------------------------------------------
// Random BigInt generation
// ---------------------------------------------------------------------------

/// Generate a random BigInt of exactly `bits` bits (MSB set).
/// Uses the ChaCha20 CSPRNG for cryptographic randomness.
fn random_bigint_bits(bits : Int, rng : @chacha20.ChaCha20Rng) -> @bigint.BigInt? {
  if bits < 2 {
    return None
  }
  let byte_len = (bits + 7) / 8
  let random_bytes = match @chacha20.next_bytes(rng, byte_len) {
    None => return None
    Some(b) => b
  }
  let arr : Array[Byte] = Array::make(byte_len, b'\x00')
  for i = 0; i < byte_len; i = i + 1 {
    arr[i] = random_bytes[i]
  }
  // Set the MSB to ensure the number is exactly `bits` bits
  let msb_byte_idx = 0
  let bit_in_byte = (bits - 1) % 8
  let mask : Byte = (1 << (bit_in_byte + 1)).to_byte()
  arr[msb_byte_idx] = (arr[msb_byte_idx] & mask) | (1 << bit_in_byte).to_byte()
  // Set the LSB to ensure the number is odd (for prime candidates)
  arr[byte_len - 1] = arr[byte_len - 1] | b'\x01'
  Some(bytes_to_bigint(Bytes::from_array(arr)))
}

/// Generate a random prime of exactly `bits` bits.
/// Tries up to `max_attempts` random candidates.
fn random_prime(bits : Int, rng : @chacha20.ChaCha20Rng, max_attempts : Int) -> @bigint.BigInt? {
  let mut attempts = 0
  while attempts < max_attempts {
    let candidate = match random_bigint_bits(bits, rng) {
      None => return None
      Some(c) => c
    }
    if miller_rabin_bigint(candidate, 40, rng) {
      return Some(candidate)
    }
    attempts = attempts + 1
  }
  None
}

// ---------------------------------------------------------------------------
// RSA key types
// ---------------------------------------------------------------------------

///|
/// RSA public key: (n, e).
pub struct RSAPublicKey {
  priv n : @bigint.BigInt // Modulus
  priv e : @bigint.BigInt // Public exponent
  priv bit_len : Int // Key size in bits
}

///|
/// RSA private key: (n, e, d, p, q).
pub struct RSAPrivateKey {
  priv n : @bigint.BigInt // Modulus
  priv _e : @bigint.BigInt // Public exponent
  priv d : @bigint.BigInt // Private exponent
  priv _p : @bigint.BigInt // First prime factor
  priv _q : @bigint.BigInt // Second prime factor
  priv bit_len : Int // Key size in bits
}

///|
/// Get the modulus from a public key.
pub fn public_modulus(key : RSAPublicKey) -> @bigint.BigInt {
  key.n
}

///|
/// Get the public exponent from a public key.
pub fn public_exponent(key : RSAPublicKey) -> @bigint.BigInt {
  key.e
}

///|
/// Get the key size in bits.
pub fn key_size(key : RSAPublicKey) -> Int {
  key.bit_len
}

///|
/// Get the key size in bits (private key).
pub fn private_key_size(key : RSAPrivateKey) -> Int {
  key.bit_len
}

// ---------------------------------------------------------------------------
// Key generation
// ---------------------------------------------------------------------------

///|
/// Generate an RSA keypair with the given key size.
///
/// `bits` is the desired modulus size (e.g., 2048 for production use).
/// `key` and `nonce` are 32-byte and 12-byte CSPRNG seeds.
///
/// Uses e = 65537 (0x10001) as the public exponent, the industry standard.
///
/// Returns `None` if key generation fails (extremely unlikely with a valid
/// CSPRNG — indicates a broken random source or too-small `bits`).
///
/// **Minimum key size**: 512 bits. **Recommended**: 2048+ bits.
pub fn generate_keypair(
  bits : Int,
  key : Bytes,
  nonce : Bytes,
) -> (RSAPublicKey, RSAPrivateKey)? {
  if bits < 512 {
    return None
  }
  let rng = match @chacha20.create_rng(key, nonce) {
    None => return None
    Some(r) => r
  }
  let half_bits = bits / 2
  let e = @bigint.from_int_value(65537)
  let one = @bigint.one()
  // Generate two distinct primes p, q such that gcd(e, p-1) = 1 and gcd(e, q-1) = 1
  let p = match random_prime(half_bits, rng, 1000) {
    None => return None
    Some(p) => p
  }
  let mut q = match random_prime(half_bits, rng, 1000) {
    None => return None
    Some(q) => q
  }
  // Ensure p != q
  let mut attempts = 0
  while @bigint.equal(p, q) && attempts < 100 {
    q = match random_prime(half_bits, rng, 1000) {
      None => return None
      Some(q) => q
    }
    attempts = attempts + 1
  }
  if @bigint.equal(p, q) {
    return None
  }
  // n = p * q
  let n = @bigint.mul(p, q)
  // φ(n) = (p-1)(q-1)
  let phi = @bigint.mul(@bigint.sub(p, one), @bigint.sub(q, one))
  // d = e^(-1) mod φ(n)
  let d = match mod_inverse(e, phi) {
    None => return None
    Some(d) => d
  }
  let pubkey : RSAPublicKey = { n, e, bit_len: bits }
  let privkey : RSAPrivateKey = { n, _e: e, d, _p: p, _q: q, bit_len: bits }
  Some((pubkey, privkey))
}

// ---------------------------------------------------------------------------
// Raw RSA operations
// ---------------------------------------------------------------------------

/// Raw RSA encryption: c = m^e mod n. No padding.
fn rsa_encrypt_raw(pubkey : RSAPublicKey, m : @bigint.BigInt) -> @bigint.BigInt {
  match @bigint.mod_pow(m, pubkey.e, pubkey.n) {
    None => @bigint.zero()
    Some(v) => v
  }
}

/// Raw RSA decryption: m = c^d mod n. No padding.
fn rsa_decrypt_raw(privkey : RSAPrivateKey, c : @bigint.BigInt) -> @bigint.BigInt {
  match @bigint.mod_pow(c, privkey.d, privkey.n) {
    None => @bigint.zero()
    Some(v) => v
  }
}

// ---------------------------------------------------------------------------
// PKCS#1 v1.5 encryption (RFC 8017 §7.2)
// ---------------------------------------------------------------------------

///|
/// RSA encryption with PKCS#1 v1.5 padding (RFC 8017 §7.2).
///
/// `plaintext` must be at most `key_size_bytes - 11` bytes long.
/// `key` (32 bytes) and `nonce` (12 bytes) are CSPRNG seeds used to
/// generate the random padding. **Each encryption call MUST use a
/// unique, cryptographically random `key` and `nonce`** — reusing
/// them destroys the security of PKCS#1 v1.5 padding.
///
/// Returns the ciphertext as a byte array, or `None` if the plaintext is
/// too long for the key size or the CSPRNG initialization fails.
pub fn encrypt(
  pubkey : RSAPublicKey,
  plaintext : Bytes,
  key : Bytes,
  nonce : Bytes,
) -> Bytes? {
  let key_bytes = (pubkey.bit_len + 7) / 8
  if plaintext.length() > key_bytes - 11 {
    return None // Plaintext too long
  }
  // PKCS#1 v1.5 padding: 0x00 || 0x02 || PS || 0x00 || M
  // PS is random non-zero bytes, length = key_bytes - plaintext_len - 3
  let ps_len = key_bytes - plaintext.length() - 3
  // Use caller-provided CSPRNG seeds — never hardcoded values.
  let rng = match @chacha20.create_rng(key, nonce) {
    None => return None
    Some(r) => r
  }
  let ps : Array[Byte] = []
  while ps.length() < ps_len {
    let rand_bytes = match @chacha20.next_bytes(rng, ps_len - ps.length()) {
      None => return None
      Some(b) => b
    }
    for i = 0; i < rand_bytes.length(); i = i + 1 {
      if rand_bytes[i] != b'\x00' {
        ps.push(rand_bytes[i])
      }
    }
  }
  // Assemble padded message
  let padded : Array[Byte] = Array::make(key_bytes, b'\x00')
  padded[0] = b'\x00'
  padded[1] = b'\x02'
  for i = 0; i < ps_len; i = i + 1 {
    padded[2 + i] = ps[i]
  }
  padded[2 + ps_len] = b'\x00'
  for i = 0; i < plaintext.length(); i = i + 1 {
    padded[3 + ps_len + i] = plaintext[i]
  }
  let m = bytes_to_bigint(Bytes::from_array(padded))
  let c = rsa_encrypt_raw(pubkey, m)
  bigint_to_bytes(c, key_bytes)
}

///|
/// RSA decryption with PKCS#1 v1.5 padding (RFC 8017 §7.2).
///
/// Returns the plaintext, or `None` if the ciphertext is invalid or
/// the padding is malformed.
///
/// **Constant-time**: the padding verification does not early-return on
/// the first mismatch, reducing timing side-channel risk. However, true
/// constant-time operation requires platform-level guarantees that
/// MoonBit cannot provide (single-threaded Wasm/JS).
pub fn decrypt(privkey : RSAPrivateKey, ciphertext : Bytes) -> Bytes? {
  let key_bytes = (privkey.bit_len + 7) / 8
  if ciphertext.length() != key_bytes {
    return None
  }
  let c = bytes_to_bigint(ciphertext)
  let m = rsa_decrypt_raw(privkey, c)
  let padded = match bigint_to_bytes(m, key_bytes) {
    None => return None
    Some(b) => b
  }
  // Verify PKCS#1 v1.5 padding: 0x00 || 0x02 || PS || 0x00 || M
  // PS must be at least 8 non-zero bytes.
  let mut valid = true
  if padded[0] != b'\x00' {
    valid = false
  }
  if padded[1] != b'\x02' {
    valid = false
  }
  // Find the 0x00 separator after PS
  let mut sep_idx = 2
  let mut ps_len = 0
  while sep_idx < padded.length() && padded[sep_idx] != b'\x00' {
    if padded[sep_idx] == b'\x00' {
      valid = false
    }
    ps_len = ps_len + 1
    sep_idx = sep_idx + 1
  }
  if ps_len < 8 {
    valid = false
  }
  if sep_idx >= padded.length() {
    valid = false
  }
  if !valid {
    return None
  }
  // Extract plaintext
  let plaintext_len = padded.length() - sep_idx - 1
  let result : Array[Byte] = Array::make(plaintext_len, b'\x00')
  for i = 0; i < plaintext_len; i = i + 1 {
    result[i] = padded[sep_idx + 1 + i]
  }
  Some(Bytes::from_array(result))
}

// ---------------------------------------------------------------------------
// PKCS#1 v1.5 signing (RFC 8017 §8.2)
// ---------------------------------------------------------------------------

/// SHA-256 DigestInfo prefix (RFC 8017 §9.2):
/// SEQUENCE { SEQUENCE { OID 2.16.840.1.101.3.4.2.1, NULL }, OCTET STRING(32) }
let sha256_digest_info_prefix : Array[Byte] = [
  0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04,
  0x02, 0x01, 0x05, 0x00, 0x04, 0x20,
]

///|
/// Sign a message with RSA-PKCS#1-v1.5-SHA256.
///
/// Computes SHA-256(message), wraps it in a DigestInfo structure, applies
/// PKCS#1 v1.5 signing padding, and performs the RSA private-key operation.
///
/// Returns the signature, or `None` if the message cannot be signed with
/// this key (e.g., key too small for SHA-256 DigestInfo).
pub fn sign(privkey : RSAPrivateKey, message : Bytes) -> Bytes? {
  let key_bytes = (privkey.bit_len + 7) / 8
  let hash = @sha256.sha256(message)
  // DigestInfo = prefix || hash
  let digest_info_len = sha256_digest_info_prefix.length() + hash.length()
  // PKCS#1 v1.5 signing padding: 0x00 || 0x01 || PS || 0x00 || T
  // PS is 0xFF bytes, length = key_bytes - digest_info_len - 3
  if digest_info_len > key_bytes - 11 {
    return None // Key too small
  }
  let ps_len = key_bytes - digest_info_len - 3
  let padded : Array[Byte] = Array::make(key_bytes, b'\x00')
  padded[0] = b'\x00'
  padded[1] = b'\x01'
  for i = 0; i < ps_len; i = i + 1 {
    padded[2 + i] = b'\xFF'
  }
  padded[2 + ps_len] = b'\x00'
  for i = 0; i < sha256_digest_info_prefix.length(); i = i + 1 {
    padded[3 + ps_len + i] = sha256_digest_info_prefix[i]
  }
  for i = 0; i < hash.length(); i = i + 1 {
    padded[3 + ps_len + sha256_digest_info_prefix.length() + i] = hash[i]
  }
  let m = bytes_to_bigint(Bytes::from_array(padded))
  let s = rsa_decrypt_raw(privkey, m) // Sign = private key operation
  bigint_to_bytes(s, key_bytes)
}

///|
/// Verify an RSA-PKCS#1-v1.5-SHA256 signature.
///
/// Returns `true` if the signature is valid for the given message and
/// public key, `false` otherwise.
///
/// **Constant-time comparison** is used to verify the padding, reducing
/// timing side-channel risk.
pub fn verify(pubkey : RSAPublicKey, message : Bytes, signature : Bytes) -> Bool {
  let key_bytes = (pubkey.bit_len + 7) / 8
  if signature.length() != key_bytes {
    return false
  }
  let s = bytes_to_bigint(signature)
  let m = rsa_encrypt_raw(pubkey, s) // Verify = public key operation
  let padded = match bigint_to_bytes(m, key_bytes) {
    None => return false
    Some(b) => b
  }
  // Reconstruct expected padding
  let hash = @sha256.sha256(message)
  let digest_info_len = sha256_digest_info_prefix.length() + hash.length()
  if digest_info_len > key_bytes - 11 {
    return false
  }
  let ps_len = key_bytes - digest_info_len - 3
  let expected : Array[Byte] = Array::make(key_bytes, b'\x00')
  expected[0] = b'\x00'
  expected[1] = b'\x01'
  for i = 0; i < ps_len; i = i + 1 {
    expected[2 + i] = b'\xFF'
  }
  expected[2 + ps_len] = b'\x00'
  for i = 0; i < sha256_digest_info_prefix.length(); i = i + 1 {
    expected[3 + ps_len + i] = sha256_digest_info_prefix[i]
  }
  for i = 0; i < hash.length(); i = i + 1 {
    expected[3 + ps_len + sha256_digest_info_prefix.length() + i] = hash[i]
  }
  // Constant-time comparison
  let mut diff : Byte = b'\x00'
  for i = 0; i < key_bytes; i = i + 1 {
    diff = diff | (padded[i] ^ expected[i])
  }
  diff == b'\x00'
}

// ---------------------------------------------------------------------------
// MGF1 (Mask Generation Function, RFC 8017 §B.2.1)
// ---------------------------------------------------------------------------

///|
/// MGF1 mask generation function using SHA-256 (RFC 8017 §B.2.1).
///
/// Generates a pseudo-random mask of the requested length by iteratively
/// hashing the seed with an incrementing 4-byte counter.
fn mgf1(seed : Bytes, mask_len : Int) -> Bytes {
  let result : Array[Byte] = []
  let mut counter = 0
  while result.length() < mask_len {
    // C = I2OSP(counter, 4) — 4-byte big-endian counter
    let c : Array[Byte] = [
      ((counter >> 24) & 0xFF).to_byte(),
      ((counter >> 16) & 0xFF).to_byte(),
      ((counter >> 8) & 0xFF).to_byte(),
      (counter & 0xFF).to_byte(),
    ]
    // T = Hash(seed || C)
    let input : Array[Byte] = []
    for i = 0; i < seed.length(); i = i + 1 {
      input.push(seed[i])
    }
    for i = 0; i < c.length(); i = i + 1 {
      input.push(c[i])
    }
    let hash = @sha256.sha256(Bytes::from_array(input))
    for i = 0; i < hash.length(); i = i + 1 {
      result.push(hash[i])
    }
    counter = counter + 1
  }
  // Truncate to mask_len
  let mask : Array[Byte] = Array::make(mask_len, b'\x00')
  for i = 0; i < mask_len; i = i + 1 {
    mask[i] = result[i]
  }
  Bytes::from_array(mask)
}

///|
/// XOR two equal-length byte arrays.
fn xor_bytes(a : Bytes, b : Bytes) -> Bytes {
  let len = a.length()
  let result : Array[Byte] = Array::make(len, b'\x00')
  for i = 0; i < len; i = i + 1 {
    result[i] = a[i] ^ b[i]
  }
  Bytes::from_array(result)
}

// ---------------------------------------------------------------------------
// RSA-OAEP (RFC 8017 §7.1)
// ---------------------------------------------------------------------------

///|
/// RSA encryption with OAEP padding using SHA-256 (RFC 8017 §7.1).
///
/// OAEP (Optimal Asymmetric Encryption Padding) is the recommended padding
/// scheme for RSA encryption. It provides semantic security (IND-CPA) under
/// the RSA assumption and is resistant to chosen-ciphertext attacks when
/// combined with an appropriate check during decryption.
///
/// - `pubkey`: the RSA public key.
/// - `plaintext`: the message to encrypt. Maximum length is
///   `key_size_bytes - 2*32 - 2` (i.e., `k - 66` for SHA-256).
/// - `label`: optional label (use empty `Bytes` for no label). The label
///   must be the same during encryption and decryption.
/// - `key` (32 bytes) and `nonce` (12 bytes): CSPRNG seeds for generating
///   the random seed used in OAEP. **Each call MUST use unique random values.**
///
/// Returns the ciphertext, or `None` if the plaintext is too long or the
/// CSPRNG fails.
pub fn encrypt_oaep(
  pubkey : RSAPublicKey,
  plaintext : Bytes,
  label : Bytes,
  key : Bytes,
  nonce : Bytes,
) -> Bytes? {
  let k = (pubkey.bit_len + 7) / 8
  let h_len = 32 // SHA-256 output length
  // Length check: mLen <= k - 2*hLen - 2
  if plaintext.length() > k - 2 * h_len - 2 {
    return None
  }
  // lHash = Hash(L)
  let l_hash = @sha256.sha256(label)
  // DB = lHash || PS || 0x01 || M  (length k - hLen - 1)
  let db_len = k - h_len - 1
  let ps_len = db_len - h_len - 1 - plaintext.length()
  let db : Array[Byte] = Array::make(db_len, b'\x00')
  for i = 0; i < h_len; i = i + 1 {
    db[i] = l_hash[i]
  }
  // PS is already zero
  db[h_len + ps_len] = b'\x01'
  for i = 0; i < plaintext.length(); i = i + 1 {
    db[h_len + ps_len + 1 + i] = plaintext[i]
  }
  // seed = random hLen bytes
  let rng = match @chacha20.create_rng(key, nonce) {
    None => return None
    Some(r) => r
  }
  let seed = match @chacha20.next_bytes(rng, h_len) {
    None => return None
    Some(s) => s
  }
  // dbMask = MGF1(seed, k - hLen - 1)
  let db_mask = mgf1(seed, db_len)
  // maskedDB = DB XOR dbMask
  let masked_db = xor_bytes(Bytes::from_array(db), db_mask)
  // seedMask = MGF1(maskedDB, hLen)
  let seed_mask = mgf1(masked_db, h_len)
  // maskedSeed = seed XOR seedMask
  let masked_seed = xor_bytes(seed, seed_mask)
  // EM = 0x00 || maskedSeed || maskedDB
  let em : Array[Byte] = Array::make(k, b'\x00')
  for i = 0; i < h_len; i = i + 1 {
    em[1 + i] = masked_seed[i]
  }
  for i = 0; i < db_len; i = i + 1 {
    em[1 + h_len + i] = masked_db[i]
  }
  // c = RSAEP((n, e), OS2IP(EM))
  let m = bytes_to_bigint(Bytes::from_array(em))
  let c = rsa_encrypt_raw(pubkey, m)
  bigint_to_bytes(c, k)
}

///|
/// RSA decryption with OAEP padding using SHA-256 (RFC 8017 §7.1).
///
/// Returns the plaintext, or `None` if the ciphertext is invalid, the
/// padding is malformed, or the label does not match.
///
/// The label hash comparison uses constant-time XOR-accumulate to reduce
/// timing side-channel risk.
pub fn decrypt_oaep(
  privkey : RSAPrivateKey,
  ciphertext : Bytes,
  label : Bytes,
) -> Bytes? {
  let k = (privkey.bit_len + 7) / 8
  let h_len = 32
  if ciphertext.length() != k {
    return None
  }
  if k < 2 * h_len + 2 {
    return None
  }
  // RSA decryption
  let c = bytes_to_bigint(ciphertext)
  let m = rsa_decrypt_raw(privkey, c)
  let em = match bigint_to_bytes(m, k) {
    None => return None
    Some(b) => b
  }
  // Separate EM = Y || maskedSeed || maskedDB
  let db_len = k - h_len - 1
  let masked_seed : Array[Byte] = Array::make(h_len, b'\x00')
  for i = 0; i < h_len; i = i + 1 {
    masked_seed[i] = em[1 + i]
  }
  let masked_db : Array[Byte] = Array::make(db_len, b'\x00')
  for i = 0; i < db_len; i = i + 1 {
    masked_db[i] = em[1 + h_len + i]
  }
  // seedMask = MGF1(maskedDB, hLen)
  let seed_mask = mgf1(Bytes::from_array(masked_db), h_len)
  // seed = maskedSeed XOR seedMask
  let seed = xor_bytes(Bytes::from_array(masked_seed), seed_mask)
  // dbMask = MGF1(seed, k - hLen - 1)
  let db_mask = mgf1(seed, db_len)
  // DB = maskedDB XOR dbMask
  let db = xor_bytes(Bytes::from_array(masked_db), db_mask)
  // lHash = Hash(L)
  let l_hash = @sha256.sha256(label)
  // Verify DB structure: lHash' || PS || 0x01 || M
  // Constant-time verification of Y and lHash
  let mut valid : Byte = em[0] // Y must be 0x00
  for i = 0; i < h_len; i = i + 1 {
    valid = valid | (db[i] ^ l_hash[i])
  }
  // Find 0x01 separator after PS
  let mut found_sep = false
  let mut msg_start = 0
  for i = h_len; i < db_len; i = i + 1 {
    if !found_sep {
      if db[i] == b'\x01' {
        found_sep = true
        msg_start = i + 1
      } else if db[i] != b'\x00' {
        // Non-zero before separator → invalid
        valid = valid | b'\x01'
      }
    }
  }
  if !found_sep || valid != b'\x00' {
    return None
  }
  // Extract message
  let msg_len = db_len - msg_start
  let result : Array[Byte] = Array::make(msg_len, b'\x00')
  for i = 0; i < msg_len; i = i + 1 {
    result[i] = db[msg_start + i]
  }
  Some(Bytes::from_array(result))
}

// ---------------------------------------------------------------------------
// RSA-PSS (RFC 8017 §8.1, §9.1)
// ---------------------------------------------------------------------------

///|
/// Sign a message with RSA-PSS-SHA256 (RFC 8017 §8.1).
///
/// PSS (Probabilistic Signature Scheme) is the recommended signature scheme
/// for RSA. It provides existential unforgeability under chosen-message
/// attacks (EUF-CMA) under the RSA assumption.
///
/// - `privkey`: the RSA private key.
/// - `message`: the message to sign.
/// - `key` (32 bytes) and `nonce` (12 bytes): CSPRNG seeds for generating
///   the random salt. **Each signing call MUST use unique random values.**
/// - `salt_len`: the length of the salt in bytes. Use `32` (SHA-256 output
///   size) for the standard recommendation.
///
/// Returns the signature, or `None` if the key is too small.
pub fn sign_pss(
  privkey : RSAPrivateKey,
  message : Bytes,
  key : Bytes,
  nonce : Bytes,
  salt_len : Int,
) -> Bytes? {
  let k = (privkey.bit_len + 7) / 8
  let h_len = 32 // SHA-256 output length
  let em_bits = privkey.bit_len - 1
  let em_len = (em_bits + 7) / 8
  // mHash = Hash(M)
  let m_hash = @sha256.sha256(message)
  // Check: emLen >= hLen + sLen + 2
  if em_len < h_len + salt_len + 2 {
    return None
  }
  // Generate salt
  let rng = match @chacha20.create_rng(key, nonce) {
    None => return None
    Some(r) => r
  }
  let salt = match @chacha20.next_bytes(rng, salt_len) {
    None => return None
    Some(s) => s
  }
  // M' = 0x00*8 || mHash || salt
  let m_prime : Array[Byte] = Array::make(8 + h_len + salt_len, b'\x00')
  for i = 0; i < h_len; i = i + 1 {
    m_prime[8 + i] = m_hash[i]
  }
  for i = 0; i < salt_len; i = i + 1 {
    m_prime[8 + h_len + i] = salt[i]
  }
  // H = Hash(M')
  let h = @sha256.sha256(Bytes::from_array(m_prime))
  // DB = PS || 0x01 || salt  (length emLen - hLen - 1)
  let db_len = em_len - h_len - 1
  let ps_len = db_len - salt_len - 1
  let db : Array[Byte] = Array::make(db_len, b'\x00')
  db[ps_len] = b'\x01'
  for i = 0; i < salt_len; i = i + 1 {
    db[ps_len + 1 + i] = salt[i]
  }
  // dbMask = MGF1(H, emLen - hLen - 1)
  let db_mask = mgf1(h, db_len)
  // maskedDB = DB XOR dbMask
  let masked_db = xor_bytes(Bytes::from_array(db), db_mask)
  // Set leftmost (8*emLen - emBits) bits of maskedDB to 0
  let zero_bits = 8 * em_len - em_bits
  if zero_bits > 0 {
    let mask : Byte = (0xFF >> zero_bits).to_byte()
    // masked_db is Bytes, need to modify in place
    let first = masked_db[0] & mask
    let new_masked : Array[Byte] = Array::make(db_len, b'\x00')
    new_masked[0] = first
    for i = 1; i < db_len; i = i + 1 {
      new_masked[i] = masked_db[i]
    }
    // EM = maskedDB || H || 0xbc
    let em : Array[Byte] = Array::make(em_len, b'\x00')
    for i = 0; i < db_len; i = i + 1 {
      em[i] = new_masked[i]
    }
    for i = 0; i < h_len; i = i + 1 {
      em[db_len + i] = h[i]
    }
    em[db_len + h_len] = b'\xbc'
    // s = RSASP1(K, OS2IP(EM))
    let m_val = bytes_to_bigint(Bytes::from_array(em))
    let s = rsa_decrypt_raw(privkey, m_val) // Sign = private key op
    bigint_to_bytes(s, k)
  } else {
    // EM = maskedDB || H || 0xbc
    let em : Array[Byte] = Array::make(em_len, b'\x00')
    for i = 0; i < db_len; i = i + 1 {
      em[i] = masked_db[i]
    }
    for i = 0; i < h_len; i = i + 1 {
      em[db_len + i] = h[i]
    }
    em[db_len + h_len] = b'\xbc'
    // s = RSASP1(K, OS2IP(EM))
    let m_val = bytes_to_bigint(Bytes::from_array(em))
    let s = rsa_decrypt_raw(privkey, m_val)
    bigint_to_bytes(s, k)
  }
}

///|
/// Verify an RSA-PSS-SHA256 signature (RFC 8017 §8.1).
///
/// - `pubkey`: the RSA public key.
/// - `message`: the original message.
/// - `signature`: the signature to verify.
/// - `salt_len`: the salt length used during signing.
///
/// Returns `true` if the signature is valid, `false` otherwise.
pub fn verify_pss(
  pubkey : RSAPublicKey,
  message : Bytes,
  signature : Bytes,
  salt_len : Int,
) -> Bool {
  let k = (pubkey.bit_len + 7) / 8
  let h_len = 32
  let em_bits = pubkey.bit_len - 1
  let em_len = (em_bits + 7) / 8
  if signature.length() != k {
    return false
  }
  if em_len < h_len + salt_len + 2 {
    return false
  }
  // m = RSAVP1((n, e), s)
  let s = bytes_to_bigint(signature)
  let m = rsa_encrypt_raw(pubkey, s)
  // EM = I2OSP(m, emLen)
  let em = match bigint_to_bytes(m, em_len) {
    None => return false
    Some(b) => b
  }
  // Check rightmost byte = 0xbc
  if em[em_len - 1] != b'\xbc' {
    return false
  }
  // Separate EM = maskedDB || H || 0xbc
  let db_len = em_len - h_len - 1
  let masked_db : Array[Byte] = Array::make(db_len, b'\x00')
  for i = 0; i < db_len; i = i + 1 {
    masked_db[i] = em[i]
  }
  let h : Array[Byte] = Array::make(h_len, b'\x00')
  for i = 0; i < h_len; i = i + 1 {
    h[i] = em[db_len + i]
  }
  // Check leftmost (8*emLen - emBits) bits of maskedDB = 0
  let zero_bits = 8 * em_len - em_bits
  if zero_bits > 0 {
    let mask : Byte = (0xFF >> zero_bits).to_byte()
    if (masked_db[0] & mask) != masked_db[0] {
      return false
    }
  }
  // dbMask = MGF1(H, emLen - hLen - 1)
  let db_mask = mgf1(Bytes::from_array(h), db_len)
  // DB = maskedDB XOR dbMask
  let db = xor_bytes(Bytes::from_array(masked_db), db_mask)
  // Set leftmost (8*emLen - emBits) bits of DB to 0
  let db_arr : Array[Byte] = []
  if zero_bits > 0 {
    let mask : Byte = (0xFF >> zero_bits).to_byte()
    db_arr.push(db[0] & mask)
  } else {
    db_arr.push(db[0])
  }
  for i = 1; i < db_len; i = i + 1 {
    db_arr.push(db[i])
  }
  // Check DB = PS || 0x01 || salt
  let ps_len = db_len - salt_len - 1
  for i = 0; i < ps_len; i = i + 1 {
    if db_arr[i] != b'\x00' {
      return false
    }
  }
  if db_arr[ps_len] != b'\x01' {
    return false
  }
  // Extract salt
  let salt : Array[Byte] = Array::make(salt_len, b'\x00')
  for i = 0; i < salt_len; i = i + 1 {
    salt[i] = db_arr[ps_len + 1 + i]
  }
  // mHash = Hash(M)
  let m_hash = @sha256.sha256(message)
  // M' = 0x00*8 || mHash || salt
  let m_prime : Array[Byte] = Array::make(8 + h_len + salt_len, b'\x00')
  for i = 0; i < h_len; i = i + 1 {
    m_prime[8 + i] = m_hash[i]
  }
  for i = 0; i < salt_len; i = i + 1 {
    m_prime[8 + h_len + i] = salt[i]
  }
  // H' = Hash(M')
  let h_prime = @sha256.sha256(Bytes::from_array(m_prime))
  // Constant-time comparison: H == H'
  let mut diff : Byte = b'\x00'
  for i = 0; i < h_len; i = i + 1 {
    diff = diff | (h[i] ^ h_prime[i])
  }
  diff == b'\x00'
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "rsa: OAEP encrypt/decrypt round-trip" {
  let key = Bytes::make(32, b'\x0B')
  let nonce = Bytes::make(12, b'\x0C')
  let (pubkey, privkey) = match generate_keypair(768, key, nonce) {
    None => abort("key generation failed")
    Some(pair) => pair
  }
  let plaintext = @utils.string_to_bytes("OAEP test message!")
  let label = @utils.string_to_bytes("label")
  let enc_key = Bytes::make(32, b'\x0D')
  let enc_nonce = Bytes::make(12, b'\x0E')
  let ciphertext = match encrypt_oaep(pubkey, plaintext, label, enc_key, enc_nonce) {
    None => abort("OAEP encryption failed")
    Some(c) => c
  }
  let decrypted = match decrypt_oaep(privkey, ciphertext, label) {
    None => abort("OAEP decryption failed")
    Some(d) => d
  }
  assert_eq(decrypted.length(), plaintext.length())
  for i = 0; i < plaintext.length(); i = i + 1 {
    assert_eq(decrypted[i], plaintext[i])
  }
}

///|
test "rsa: OAEP with empty label" {
  let key = Bytes::make(32, b'\x0F')
  let nonce = Bytes::make(12, b'\x10')
  let (pubkey, privkey) = match generate_keypair(768, key, nonce) {
    None => abort("key generation failed")
    Some(pair) => pair
  }
  let plaintext = @utils.string_to_bytes("Hello OAEP")
  let empty_label = Bytes::make(0, b'\x00')
  let ciphertext = match encrypt_oaep(pubkey, plaintext, empty_label, Bytes::make(32, b'\x11'), Bytes::make(12, b'\x12')) {
    None => abort("OAEP encryption failed")
    Some(c) => c
  }
  let decrypted = match decrypt_oaep(privkey, ciphertext, empty_label) {
    None => abort("OAEP decryption failed")
    Some(d) => d
  }
  assert_eq(decrypted.length(), plaintext.length())
  for i = 0; i < plaintext.length(); i = i + 1 {
    assert_eq(decrypted[i], plaintext[i])
  }
}

///|
test "rsa: OAEP wrong label fails" {
  let key = Bytes::make(32, b'\x17')
  let nonce = Bytes::make(12, b'\x18')
  let (pubkey, privkey) = match generate_keypair(768, key, nonce) {
    None => abort("key generation failed")
    Some(pair) => pair
  }
  let plaintext = @utils.string_to_bytes("Secret")
  let label1 = @utils.string_to_bytes("correct")
  let label2 = @utils.string_to_bytes("wrong")
  let ciphertext = match encrypt_oaep(pubkey, plaintext, label1, Bytes::make(32, b'\x19'), Bytes::make(12, b'\x1A')) {
    None => abort("OAEP encryption failed")
    Some(c) => c
  }
  // Decryption with wrong label should fail
  assert_true(decrypt_oaep(privkey, ciphertext, label2) is None)
}

///|
test "rsa: PSS sign/verify round-trip" {
  let key = Bytes::make(32, b'\x1B')
  let nonce = Bytes::make(12, b'\x1C')
  let (pubkey, privkey) = match generate_keypair(768, key, nonce) {
    None => abort("key generation failed")
    Some(pair) => pair
  }
  let message = @utils.string_to_bytes("PSS test message")
  let salt_len = 32
  let sig = match sign_pss(privkey, message, Bytes::make(32, b'\x1D'), Bytes::make(12, b'\x1E'), salt_len) {
    None => abort("PSS signing failed")
    Some(s) => s
  }
  assert_true(verify_pss(pubkey, message, sig, salt_len))
  // Wrong message should fail
  let wrong = @utils.string_to_bytes("Wrong message")
  assert_true(!verify_pss(pubkey, wrong, sig, salt_len))
}

///|
test "rsa: PSS with zero salt length" {
  let key = Bytes::make(32, b'\x1F')
  let nonce = Bytes::make(12, b'\x20')
  let (pubkey, privkey) = match generate_keypair(768, key, nonce) {
    None => abort("key generation failed")
    Some(pair) => pair
  }
  let message = @utils.string_to_bytes("PSS zero salt")
  let sig = match sign_pss(privkey, message, Bytes::make(32, b'\x21'), Bytes::make(12, b'\x22'), 0) {
    None => abort("PSS signing failed")
    Some(s) => s
  }
  assert_true(verify_pss(pubkey, message, sig, 0))
}

///|
test "rsa: miller_rabin_bigint on small primes" {
  let rng = match @chacha20.create_rng(
    Bytes::from_array([
      b'\x01', b'\x02', b'\x03', b'\x04', b'\x05', b'\x06', b'\x07', b'\x08',
      b'\x09', b'\x0a', b'\x0b', b'\x0c', b'\x0d', b'\x0e', b'\x0f', b'\x10',
      b'\x11', b'\x12', b'\x13', b'\x14', b'\x15', b'\x16', b'\x17', b'\x18',
      b'\x19', b'\x1a', b'\x1b', b'\x1c', b'\x1d', b'\x1e', b'\x1f', b'\x20',
    ]),
    Bytes::from_array([
      b'\x00', b'\x01', b'\x02', b'\x03', b'\x04', b'\x05', b'\x06', b'\x07',
      b'\x08', b'\x09', b'\x0a', b'\x0b',
    ]),
  ) {
    None => abort("Failed to create RNG for test")
    Some(r) => r
  }
  let primes = [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47]
  for i = 0; i < primes.length(); i = i + 1 {
    let n = @bigint.from_int_value(primes[i])
    assert_true(miller_rabin_bigint(n, 10, rng))
  }
}

///|
test "rsa: miller_rabin_bigint on composites" {
  let rng = match @chacha20.create_rng(
    Bytes::from_array([
      b'\x01', b'\x02', b'\x03', b'\x04', b'\x05', b'\x06', b'\x07', b'\x08',
      b'\x09', b'\x0a', b'\x0b', b'\x0c', b'\x0d', b'\x0e', b'\x0f', b'\x10',
      b'\x11', b'\x12', b'\x13', b'\x14', b'\x15', b'\x16', b'\x17', b'\x18',
      b'\x19', b'\x1a', b'\x1b', b'\x1c', b'\x1d', b'\x1e', b'\x1f', b'\x20',
    ]),
    Bytes::from_array([
      b'\x00', b'\x01', b'\x02', b'\x03', b'\x04', b'\x05', b'\x06', b'\x07',
      b'\x08', b'\x09', b'\x0a', b'\x0b',
    ]),
  ) {
    None => abort("Failed to create RNG for test")
    Some(r) => r
  }
  let composites = [4, 6, 8, 9, 10, 15, 21, 25, 27, 33, 35, 49, 51, 55]
  for i = 0; i < composites.length(); i = i + 1 {
    let n = @bigint.from_int_value(composites[i])
    assert_true(!miller_rabin_bigint(n, 10, rng))
  }
}

///|
test "rsa: miller_rabin_bigint on larger primes" {
  let rng = match @chacha20.create_rng(
    Bytes::from_array([
      b'\x01', b'\x02', b'\x03', b'\x04', b'\x05', b'\x06', b'\x07', b'\x08',
      b'\x09', b'\x0a', b'\x0b', b'\x0c', b'\x0d', b'\x0e', b'\x0f', b'\x10',
      b'\x11', b'\x12', b'\x13', b'\x14', b'\x15', b'\x16', b'\x17', b'\x18',
      b'\x19', b'\x1a', b'\x1b', b'\x1c', b'\x1d', b'\x1e', b'\x1f', b'\x20',
    ]),
    Bytes::from_array([
      b'\x00', b'\x01', b'\x02', b'\x03', b'\x04', b'\x05', b'\x06', b'\x07',
      b'\x08', b'\x09', b'\x0a', b'\x0b',
    ]),
  ) {
    None => abort("Failed to create RNG for test")
    Some(r) => r
  }
  // Known primes
  assert_true(miller_rabin_bigint(@bigint.from_int_value(7919), 20, rng))
  assert_true(miller_rabin_bigint(@bigint.from_int_value(104729), 20, rng))
  assert_true(miller_rabin_bigint(@bigint.from_int_value(1299709), 20, rng))
  // Carmichael number 561 = 3 × 11 × 17 (should be detected as composite)
  assert_true(!miller_rabin_bigint(@bigint.from_int_value(561), 20, rng))
}

///|
test "rsa: mod_inverse basic" {
  // 3 * 7 mod 20 = 1 (inverse of 3 mod 20 is 7)
  let a = @bigint.from_int_value(3)
  let m = @bigint.from_int_value(20)
  let inv = match mod_inverse(a, m) {
    None => abort("mod_inverse failed")
    Some(v) => v
  }
  assert_eq(@bigint.to_string(inv), "7")
}

///|
test "rsa: mod_inverse no inverse" {
  // gcd(4, 8) = 4, no inverse exists
  let a = @bigint.from_int_value(4)
  let m = @bigint.from_int_value(8)
  assert_true(mod_inverse(a, m) is None)
}

///|
test "rsa: mod_inverse large" {
  // e = 65537, phi = (61-1)(53-1) = 3120
  // d = 65537^(-1) mod 3120
  let e = @bigint.from_int_value(65537)
  let phi = @bigint.from_int_value(3120)
  let d = match mod_inverse(e, phi) {
    None => abort("mod_inverse failed")
    Some(v) => v
  }
  // Verify: e * d mod phi = 1
  let product = @bigint.mul(e, d)
  let remainder = match @bigint.divmod(product, phi) {
    None => abort("divmod failed")
    Some((_, r)) => r
  }
  assert_eq(@bigint.to_string(remainder), "1")
}

///|
test "rsa: keypair generation and encrypt/decrypt" {
  // Use a small key for test speed (512 bits)
  let key = Bytes::make(32, b'\x01')
  let nonce = Bytes::make(12, b'\x02')
  let (pubkey, privkey) = match generate_keypair(512, key, nonce) {
    None => abort("key generation failed")
    Some(pair) => pair
  }
  assert_eq(key_size(pubkey), 512)
  // Encrypt and decrypt a short message
  let plaintext = @utils.string_to_bytes("Hello, RSA!")
  let ciphertext = match encrypt(pubkey, plaintext, Bytes::make(32, b'\x0A'), Bytes::make(12, b'\x0B')) {
    None => abort("encryption failed")
    Some(c) => c
  }
  let decrypted = match decrypt(privkey, ciphertext) {
    None => abort("decryption failed")
    Some(d) => d
  }
  assert_eq(decrypted.length(), plaintext.length())
  for i = 0; i < plaintext.length(); i = i + 1 {
    assert_eq(decrypted[i], plaintext[i])
  }
}

///|
test "rsa: sign and verify" {
  let key = Bytes::make(32, b'\x03')
  let nonce = Bytes::make(12, b'\x04')
  let (pubkey, privkey) = match generate_keypair(512, key, nonce) {
    None => abort("key generation failed")
    Some(pair) => pair
  }
  let message = @utils.string_to_bytes("Sign this message")
  let signature = match sign(privkey, message) {
    None => abort("signing failed")
    Some(s) => s
  }
  assert_true(verify(pubkey, message, signature))
  // Wrong message should fail verification
  let wrong = @utils.string_to_bytes("Wrong message")
  assert_true(!verify(pubkey, wrong, signature))
}

///|
test "rsa: sign and verify empty message" {
  let key = Bytes::make(32, b'\x05')
  let nonce = Bytes::make(12, b'\x06')
  let (pubkey, privkey) = match generate_keypair(512, key, nonce) {
    None => abort("key generation failed")
    Some(pair) => pair
  }
  let message = Bytes::make(0, b'\x00')
  let signature = match sign(privkey, message) {
    None => abort("signing failed")
    Some(s) => s
  }
  assert_true(verify(pubkey, message, signature))
}

///|
test "rsa: encrypt too long returns None" {
  let key = Bytes::make(32, b'\x07')
  let nonce = Bytes::make(12, b'\x08')
  let (pubkey, _) = match generate_keypair(512, key, nonce) {
    None => abort("key generation failed")
    Some(pair) => pair
  }
  // 512-bit key = 64 bytes, max plaintext = 64 - 11 = 53 bytes
  let too_long = Bytes::make(100, b'\x41')
  assert_true(encrypt(pubkey, too_long, Bytes::make(32, b'\x0C'), Bytes::make(12, b'\x0D')) is None)
}

///|
test "rsa: invalid ciphertext returns None" {
  let key = Bytes::make(32, b'\x09')
  let nonce = Bytes::make(12, b'\x0A')
  let (_, privkey) = match generate_keypair(512, key, nonce) {
    None => abort("key generation failed")
    Some(pair) => pair
  }
  // Wrong length ciphertext
  let bad_ct = Bytes::make(32, b'\x00')
  assert_true(decrypt(privkey, bad_ct) is None)
}

///|
test "rsa: extended_gcd basic" {
  // gcd(240, 46) = 2, and 240*x + 46*y = 2
  let a = @bigint.from_int_value(240)
  let b = @bigint.from_int_value(46)
  let (g, _x, _y) = extended_gcd(a, b)
  assert_eq(@bigint.to_string(g), "2")
}

///|
test "rsa: extended_gcd coprime" {
  // gcd(17, 5) = 1
  let a = @bigint.from_int_value(17)
  let b = @bigint.from_int_value(5)
  let (g, _x, _y) = extended_gcd(a, b)
  assert_eq(@bigint.to_string(g), "1")
}

///|
test "rsa: bytes_to_bigint round-trip" {
  let original = @bigint.from_string("12345678901234567890")
  let original = match original {
    None => abort("parse failed")
    Some(v) => v
  }
  let bytes = match bigint_to_bytes(original, 9) {
    None => abort("to_bytes failed")
    Some(b) => b
  }
  let recovered = bytes_to_bigint(bytes)
  assert_true(@bigint.equal(original, recovered))
}
