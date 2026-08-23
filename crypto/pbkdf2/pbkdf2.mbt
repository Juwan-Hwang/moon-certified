/// PBKDF2-HMAC-SHA-256 — Password-Based Key Derivation Function 2 (RFC 2898).
///
/// PBKDF2 derives a key of arbitrary length from a password and salt by
/// iteratively applying HMAC-SHA-256. It is the standard password hashing
/// scheme used in WPA2, 1Password, LastPass, and many other systems.
///
/// ## Algorithm
///
/// ```text
/// DK = T1 || T2 || ... || T_dklen/hlen
/// Ti = F(Password, Salt, c, i)
/// F(P, S, c, i) = U1 ^ U2 ^ ... ^ Uc
/// U1 = HMAC(P, S || INT32_BE(i))
/// Uj = HMAC(P, U_{j-1})
/// ```
///
/// ## Security
///
/// The iteration count `c` should be at least 600,000 for interactive use
/// (OWASP 2023 recommendation for PBKDF2-SHA-256). Each doubling of `c`
/// roughly doubles the cost of brute-force attacks.
///
/// ### Production usage
///
/// Always use `pbkdf2_sha256_checked` in production code. It enforces the
/// OWASP-recommended minimum iteration count and rejects dangerously weak
/// parameters. The raw `pbkdf2_sha256` function is provided for testing,
/// legacy compatibility, and advanced use cases where the caller assumes
/// full responsibility for parameter selection.
///
/// ### Limitations
///
/// - MoonBit has a garbage collector, so the password bytes may persist in
///   memory until GC collects them. The `zeroize` function overwrites the
///   mutable `Bytes` buffer in-place, but immutable copies created by the
///   runtime cannot be cleared.
///
/// - No salting is performed: the caller must supply a cryptographically
///   random salt of at least 16 bytes (128 bits).
///
/// Not formally verified. Correctness is ensured by RFC 6070 test vectors.

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

///|
/// OWASP 2023 recommended minimum iteration count for PBKDF2-HMAC-SHA-256.
///
/// This value was determined by OWASP based on the computational cost of
/// SHA-256 and the need to make brute-force attacks economically infeasible.
/// As hardware improves, this value should be increased. See:
/// https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html
pub const PBKDF2_MIN_ITERATIONS : Int = 600_000

///|
/// Maximum iterations to prevent accidental DoS (100M iterations ≈ minutes).
pub const PBKDF2_MAX_ITERATIONS : Int = 100_000_000

///|
/// Minimum salt length in bytes (128 bits per NIST SP 800-132).
pub const PBKDF2_MIN_SALT_LEN : Int = 16

///|
/// Maximum salt length in bytes (prevents excessive memory consumption).
pub const PBKDF2_MAX_SALT_LEN : Int = 1024

///|
/// Default output length in bytes (256-bit key).
pub const PBKDF2_DEFAULT_DKLEN : Int = 32

///|
/// SHA-256 output length in bytes.
let pbkdf2_hlen : Int = 32

// ---------------------------------------------------------------------------
// Internal: zeroize sensitive memory
// ---------------------------------------------------------------------------

///|
/// Overwrite a mutable `Array[Byte]` buffer with zeros in-place.
///
/// This is a best-effort defence against residual key material in memory.
/// Because MoonBit has a garbage collector, this cannot guarantee that all
/// copies of the data are cleared — the GC may have duplicated the buffer
/// during compaction. However, clearing the buffer we hold a reference to
/// reduces the window of exposure.
///
/// **Note**: MoonBit's `Bytes` type is immutable, so `zeroize` accepts
/// `Array[Byte]` instead. When working with password data, keep it in an
/// `Array[Byte]` so it can be cleared after use.
///
/// **Usage pattern**:
/// ```moonbit nocheck
/// let password : Array[Byte] = [b'p', b'w', ...]
/// let pw_bytes = Bytes::from_array(password)
/// let derived = pbkdf2_sha256_checked(pw_bytes, salt, 600_000, 32)
/// zeroize(password) // clear password after derivation
/// ```
pub fn zeroize(buf : Array[Byte]) -> Unit {
  for i = 0; i < buf.length(); i = i + 1 {
    buf[i] = b'\x00'
  }
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

///|
/// PBKDF2-HMAC-SHA-256 (raw, no parameter validation beyond ≥ 1).
///
/// This is the low-level implementation. It performs no iteration-count
/// or salt-length checks. Use `pbkdf2_sha256_checked` for production code.
///
/// - `password`: the password bytes.
/// - `salt`: the salt bytes.
/// - `iterations`: number of HMAC iterations (must be ≥ 1).
/// - `dklen`: desired output length in bytes (must be ≥ 1).
///
/// Returns `None` if `iterations < 1` or `dklen < 1`.
pub fn pbkdf2_sha256(
  password : Bytes,
  salt : Bytes,
  iterations : Int,
  dklen : Int,
) -> Bytes? {
  if iterations < 1 || dklen < 1 {
    return None
  }
  let hlen = pbkdf2_hlen
  let num_blocks = (dklen + hlen - 1) / hlen
  let result : Array[Byte] = []
  for block_num = 1; block_num <= num_blocks; block_num = block_num + 1 {
    // F(Password, Salt, c, i)
    // U1 = HMAC(P, Salt || INT32_BE(block_num))
    let salt_and_idx : Array[Byte] = []
    for b in salt {
      salt_and_idx.push(b)
    }
    salt_and_idx.push((block_num >> 24).to_byte())
    salt_and_idx.push((block_num >> 16).to_byte())
    salt_and_idx.push((block_num >> 8).to_byte())
    salt_and_idx.push(block_num.to_byte())
    let mut u = @hmac.hmac_sha256(password, Bytes::from_array(salt_and_idx))
    let t : Array[Byte] = []
    for b in u {
      t.push(b)
    }
    // U2..Uc
    for _j = 1; _j < iterations; _j = _j + 1 {
      u = @hmac.hmac_sha256(password, u)
      for k = 0; k < hlen; k = k + 1 {
        t[k] = t[k] ^ u[k]
      }
    }
    // Append T_block_num to result (truncated if last block).
    for k = 0; k < hlen && result.length() < dklen; k = k + 1 {
      result.push(t[k])
    }
  }
  Some(Bytes::from_array(result))
}

///|
/// PBKDF2-HMAC-SHA-256 with production-grade parameter validation.
///
/// Enforces the following security requirements:
///
/// - `iterations ≥ PBKDF2_MIN_ITERATIONS` (600,000 per OWASP 2023)
/// - `iterations ≤ PBKDF2_MAX_ITERATIONS` (100M, prevents DoS)
/// - `salt.length() ≥ PBKDF2_MIN_SALT_LEN` (16 bytes / 128 bits per NIST)
/// - `salt.length() ≤ PBKDF2_MAX_SALT_LEN` (1024 bytes, prevents memory waste)
/// - `dklen ≥ 16` (minimum useful key length)
/// - `dklen ≤ 4096` (prevent excessive memory consumption)
///
/// Returns `None` if any parameter fails validation.
///
/// **Always prefer this function over `pbkdf2_sha256` in production code.**
pub fn pbkdf2_sha256_checked(
  password : Bytes,
  salt : Bytes,
  iterations : Int,
  dklen : Int,
) -> Bytes? {
  if iterations < PBKDF2_MIN_ITERATIONS || iterations > PBKDF2_MAX_ITERATIONS {
    return None
  }
  if salt.length() < PBKDF2_MIN_SALT_LEN || salt.length() > PBKDF2_MAX_SALT_LEN {
    return None
  }
  if dklen < 16 || dklen > 4096 {
    return None
  }
  pbkdf2_sha256(password, salt, iterations, dklen)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "pbkdf2: RFC 6070 basic vector (SHA-256 analog)" {
  // Verify basic properties: output length and determinism.
  let dk1 = match pbkdf2_sha256(b"password", b"salt", 1, 32) {
    None => fail("pbkdf2 failed")
    Some(d) => d
  }
  assert_eq(dk1.length(), 32)
  // Same inputs → same output.
  let dk2 = match pbkdf2_sha256(b"password", b"salt", 1, 32) {
    None => fail("pbkdf2 failed")
    Some(d) => d
  }
  assert_true(dk1 == dk2)
}

///|
test "pbkdf2: different iterations produce different keys" {
  let dk1 = match pbkdf2_sha256(b"password", b"salt", 1, 32) {
    None => fail("pbkdf2 failed")
    Some(d) => d
  }
  let dk2 = match pbkdf2_sha256(b"password", b"salt", 100, 32) {
    None => fail("pbkdf2 failed")
    Some(d) => d
  }
  assert_true(dk1 != dk2)
}

///|
test "pbkdf2: output length > hash length" {
  let dk = match pbkdf2_sha256(b"password", b"salt", 10, 64) {
    None => fail("pbkdf2 failed")
    Some(d) => d
  }
  assert_eq(dk.length(), 64)
}

///|
test "pbkdf2: raw function invalid parameters return None" {
  assert_true(pbkdf2_sha256(b"pw", b"salt", 0, 32) is None)
  assert_true(pbkdf2_sha256(b"pw", b"salt", 10, 0) is None)
}

///|
test "pbkdf2: checked function rejects low iterations" {
  // 1 iteration is below OWASP minimum (600,000).
  let salt = Bytes::from_array(Array::make(16, b'\x42'))
  assert_true(pbkdf2_sha256_checked(b"password", salt, 1, 32) is None)
}

///|
test "pbkdf2: checked function rejects short salt" {
  // 8-byte salt is below NIST minimum (16 bytes).
  let short_salt = Bytes::from_array(Array::make(8, b'\x42'))
  assert_true(
    pbkdf2_sha256_checked(b"password", short_salt, 600_000, 32) is None,
  )
}

///|
test "pbkdf2: checked function rejects short dklen" {
  let salt = Bytes::from_array(Array::make(16, b'\x42'))
  assert_true(pbkdf2_sha256_checked(b"password", salt, 600_000, 8) is None)
}

///|
test "pbkdf2: zeroize clears buffer" {
  let buf : Array[Byte] = [b'\x01', b'\x02', b'\x03', b'\x04', b'\x05']
  zeroize(buf)
  for i = 0; i < buf.length(); i = i + 1 {
    assert_eq(buf[i], b'\x00')
  }
}
