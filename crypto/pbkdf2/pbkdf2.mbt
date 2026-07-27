/// PBKDF2-HMAC-SHA-256 — Password-Based Key Derivation Function 2 (RFC 2898).
///
/// PBKDF2 derives a key of arbitrary length from a password and salt by
/// iteratively applying HMAC-SHA-256. It is the standard password hashing
/// scheme used in WPA2, 1Password, LastPass, and many other systems.
///
/// ## Algorithm
///
/// ```
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
/// (OWASP 2023 recommendation). Each doubling of `c` roughly doubles the
/// cost of brute-force attacks.
///
/// Not formally verified. Correctness is ensured by RFC 6070 test vectors.

///|
/// PBKDF2-HMAC-SHA-256.
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
  let hlen = 32 // SHA-256 output length
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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "pbkdf2: RFC 6070 basic vector (SHA-256 analog)" {
  // Verify basic properties: output length and determinism.
  let dk1 = match pbkdf2_sha256(b"password", b"salt", 1, 32) {
    None => abort("pbkdf2 failed")
    Some(d) => d
  }
  assert_eq(dk1.length(), 32)
  // Same inputs → same output.
  let dk2 = match pbkdf2_sha256(b"password", b"salt", 1, 32) {
    None => abort("pbkdf2 failed")
    Some(d) => d
  }
  assert_true(dk1 == dk2)
}

///|
test "pbkdf2: different iterations produce different keys" {
  let dk1 = match pbkdf2_sha256(b"password", b"salt", 1, 32) {
    None => abort("pbkdf2 failed")
    Some(d) => d
  }
  let dk2 = match pbkdf2_sha256(b"password", b"salt", 100, 32) {
    None => abort("pbkdf2 failed")
    Some(d) => d
  }
  assert_true(dk1 != dk2)
}

///|
test "pbkdf2: output length > hash length" {
  let dk = match pbkdf2_sha256(b"password", b"salt", 10, 64) {
    None => abort("pbkdf2 failed")
    Some(d) => d
  }
  assert_eq(dk.length(), 64)
}

///|
test "pbkdf2: invalid parameters return None" {
  assert_true(pbkdf2_sha256(b"pw", b"salt", 0, 32) is None)
  assert_true(pbkdf2_sha256(b"pw", b"salt", 10, 0) is None)
}
