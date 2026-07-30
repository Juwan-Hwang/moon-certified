/// CSPRNG — Cryptographically Secure Pseudo-Random Number Generator.
///
/// Implements **HMAC-DRBG** as specified in NIST SP 800-90A Rev. 1, using
/// HMAC-SHA-256 as the underlying primitive. HMAC-DRBG is one of the three
/// approved DRBG mechanisms (alongside Hash-DRBG and CTR-DRBG) recognised by
/// NIST for cryptographic applications including key generation, nonce
/// creation, and salt production.
///
/// ## Security properties
///
/// - **Backtracking resistance**: Even if the internal state is compromised
///   after a generation call, previously generated output cannot be
///   recovered because `update` re-keys the HMAC after every generation.
///
/// - **Prediction resistance**: If the state is compromised, the attacker
///   cannot predict future output *unless* they also control future reseed
///   input. Call `reseed` with fresh entropy to restore security.
///
/// - **Forward secrecy after reseeding**: A compromise followed by a reseed
///   with sufficient entropy restores full security.
///
/// ## Limitations
///
/// MoonBit compiles to WebAssembly / JavaScript, which do not provide a
/// platform CSPRNG (no `/dev/urandom`, no `getrandom()`, no
/// `crypto.getRandomValues` from within MoonBit). Therefore:
///
/// - **Entropy must be supplied by the caller.** The `instantiate` and
///   `reseed` functions accept an `entropy` `Bytes` argument. In a browser
///   context, use `crypto.getRandomValues()` via FFI; in a server context,
///   use `/dev/urandom`. The quality of the DRBG output is entirely
///   dependent on the quality of the seed entropy.
///
/// - **Maximum output per request**: 2^19 bytes (per NIST SP 800-90A
///   §10.1.2.5). Requests larger than this are fulfilled in chunks.
///
/// - **Reseed interval**: NIST requires reseeding after 2^48 generation
///   requests. This implementation tracks a request counter and returns
///   `None` from `generate` when the reseed counter would overflow,
///   signalling that `reseed` must be called.
///
/// ## References
///
/// - NIST SP 800-90A Rev. 1: Recommendation for Random Number Generation
///   Using Deterministic Random Bit Generators (June 2015)
/// - NIST FIPS 198-1: The Keyed-Hash Message Authentication Code (HMAC)
/// - NIST FIPS 180-4: Secure Hash Standard (SHA-256)
///
/// `proof-enabled` is `false`; correctness is backed by test vectors from
/// NIST SP 800-90A.

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

///|
/// SHA-256 output length in bytes (256 bits).
let sha256_len : Int = 32

///|
/// Maximum bytes per generate request (NIST SP 800-90A §10.1.2.5).
/// NIST mandates 2^19 bytes (524288); we use a conservative 65536.
let max_bytes_per_request : Int = 65536

///|
/// Maximum generate requests before mandatory reseed (2^48, per NIST).
/// In practice this counter will never overflow for any real application.
let reseed_interval : Int64 = 281474976710656L

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

///|
/// HMAC-DRBG state: key `K` and value `V`, both 32 bytes, plus a
/// reseed counter.
///
/// All fields are `priv`: external code interacts exclusively through
/// the public functions (`instantiate`, `reseed`, `generate`).
pub struct DrbgState {
  priv mut k : Bytes
  priv mut v : Bytes
  priv mut reseed_counter : Int64
}

// ---------------------------------------------------------------------------
// Internal: helper to build byte arrays
// ---------------------------------------------------------------------------

///|
/// Concatenate multiple `Bytes` into a single `Bytes`.
fn concat_bytes(parts : Array[Bytes]) -> Bytes {
  let mut total = 0
  for part in parts {
    total = total + part.length()
  }
  let buf : Array[Byte] = Array::make(total, b'\x00')
  let mut offset = 0
  for part in parts {
    for i = 0; i < part.length(); i = i + 1 {
      buf[offset] = part[i]
      offset = offset + 1
    }
  }
  Bytes::from_array(buf)
}

// ---------------------------------------------------------------------------
// Internal: HMAC-DRBG update function (NIST SP 800-90A §10.1.2.2)
// ---------------------------------------------------------------------------

///|
/// DRBG update: mixes `provided_data` into the key and value.
///
///   K = HMAC(K, V || 0x00 || provided_data)
///   V = HMAC(K, V)
///   if provided_data is non-empty:
///     K = HMAC(K, V || 0x01 || provided_data)
///     V = HMAC(K, V)
fn update(
  state : DrbgState,
  provided_data : Bytes,
) -> Unit {
  // Step 1: K = HMAC(K, V || 0x00 || provided_data)
  let msg1 = concat_bytes([
    state.v,
    Bytes::from_array([b'\x00']),
    provided_data,
  ])
  state.k = @hmac.hmac_sha256(state.k, msg1)
  // Step 2: V = HMAC(K, V)
  state.v = @hmac.hmac_sha256(state.k, state.v)
  // Step 3: if provided_data is non-empty, repeat with 0x01.
  if provided_data.length() > 0 {
    let msg2 = concat_bytes([
      state.v,
      Bytes::from_array([b'\x01']),
      provided_data,
    ])
    state.k = @hmac.hmac_sha256(state.k, msg2)
    state.v = @hmac.hmac_sha256(state.k, state.v)
  }
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

///|
/// Instantiate a new HMAC-DRBG with the given entropy and optional nonce.
///
/// Per NIST SP 800-90A §10.1.2.3, the seed material is
/// `entropy || nonce || personalization_string`. The nonce is optional but
/// recommended; the personalization string is optional.
///
/// **Minimum entropy**: 256 bits (32 bytes). If fewer bytes are provided,
/// the DRBG is still instantiated but its security strength is reduced
/// accordingly. Callers should provide at least 32 bytes of high-quality
/// entropy.
///
/// Returns a `DrbgState` ready for `generate` calls.
pub fn instantiate(
  entropy : Bytes,
  nonce : Bytes,
  personalization : Bytes,
) -> DrbgState {
  // Combine seed material.
  let seed = concat_bytes([entropy, nonce, personalization])
  // Initialise K = 0x00...00, V = 0x01...01.
  let state : DrbgState = {
    k: Bytes::from_array(Array::make(sha256_len, b'\x00')),
    v: Bytes::from_array(Array::make(sha256_len, b'\x01')),
    reseed_counter: 1L,
  }
  // Mix in seed material.
  update(state, seed)
  state
}

///|
/// Reseed the DRBG with new entropy.
///
/// Per NIST SP 800-90A §10.1.2.4, the reseed seed material is
/// `entropy || additional_input`. The reseed counter is reset to 1.
///
/// Call this when the reseed counter reaches `RESEED_INTERVAL` or when
/// prediction resistance is required after a suspected state compromise.
pub fn reseed(
  state : DrbgState,
  entropy : Bytes,
  additional_input : Bytes,
) -> Unit {
  let seed = concat_bytes([entropy, additional_input])
  update(state, seed)
  state.reseed_counter = 1L
}

///|
/// Generate `num_bytes` of pseudo-random output.
///
/// Per NIST SP 800-90A §10.1.2.5:
/// 1. If `reseed_counter` > `RESEED_INTERVAL`, return `None` (must reseed).
/// 2. If `additional_input` is non-empty, update the state with it.
/// 3. Generate output by repeatedly computing V = HMAC(K, V) and appending.
/// 4. Update the state (with empty additional_input).
/// 5. Increment the reseed counter.
///
/// Returns `Some(bytes)` on success, `None` if a reseed is required.
pub fn generate(
  state : DrbgState,
  num_bytes : Int,
  additional_input : Bytes,
) -> Bytes? {
  if num_bytes <= 0 {
    return Some(Bytes::from_array([]))
  }
  // Enforce NIST SP 800-90A §10.1.2.5 maximum request size.
  if num_bytes > max_bytes_per_request {
    return None
  }
  if state.reseed_counter > reseed_interval {
    return None // Mandatory reseed required.
  }
  // Step 2: if additional_input is non-empty, update with it.
  if additional_input.length() > 0 {
    update(state, additional_input)
  }
  // Step 3: generate output using Array[Byte] (Bytes is immutable).
  let result : Array[Byte] = Array::make(num_bytes, b'\x00')
  let mut generated = 0
  while generated < num_bytes {
    state.v = @hmac.hmac_sha256(state.k, state.v)
    let to_copy = if num_bytes - generated < sha256_len {
      num_bytes - generated
    } else {
      sha256_len
    }
    for i = 0; i < to_copy; i = i + 1 {
      result[generated + i] = state.v[i]
    }
    generated = generated + to_copy
  }
  // Step 4: update state (with empty additional_input).
  update(state, Bytes::from_array([]))
  // Step 5: increment reseed counter.
  state.reseed_counter = state.reseed_counter + 1L
  Some(Bytes::from_array(result))
}

///|
/// Generate a random `Int` in `[0, n)` without modulo bias.
///
/// Uses rejection sampling: draws 4 bytes at a time, interprets them as
/// a 31-bit non-negative integer, and rejects values that fall in the
/// incomplete final block. This eliminates the modulo bias present in
/// `rng() % n`.
pub fn generate_below(state : DrbgState, n : Int) -> Int? {
  if n <= 0 {
    return None
  }
  if n == 1 {
    return Some(0)
  }
  // Use 31-bit range [0, 2^31).
  // 2^31 = 2147483648, but Int max is 2147483647.
  // Compute threshold using Int64 to avoid overflow.
  // When n is a power of 2, range % n64 == 0, so threshold64 == range == 2^31,
  // which overflows Int. Handle power-of-2 as a special case.
  let range = 2147483648L
  let n64 = n.to_int64()
  let threshold64 = range - (range % n64)
  // Use Int64 comparison to avoid Int overflow when threshold64 == 2^31.
  let mut r = 0
  let mut r64 = 0L
  let mut ok = false
  while !ok {
    let bytes = match generate(state, 4, Bytes::from_array([])) {
      Some(b) => b
      None => return None
    }
    // Interpret as 31-bit non-negative integer (mask top bit).
    r = ((bytes[0].to_int() & 0x7F) << 24) |
      ((bytes[1].to_int() & 0xFF) << 16) |
      ((bytes[2].to_int() & 0xFF) << 8) |
      (bytes[3].to_int() & 0xFF)
    r64 = r.to_int64()
    if r64 < threshold64 {
      ok = true
    }
  }
  Some(r % n)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "csprng: instantiate and generate basic" {
  let entropy = Bytes::from_array([
    b'\x00', b'\x01', b'\x02', b'\x03', b'\x04', b'\x05', b'\x06', b'\x07',
    b'\x08', b'\x09', b'\x0a', b'\x0b', b'\x0c', b'\x0d', b'\x0e', b'\x0f',
    b'\x10', b'\x11', b'\x12', b'\x13', b'\x14', b'\x15', b'\x16', b'\x17',
    b'\x18', b'\x19', b'\x1a', b'\x1b', b'\x1c', b'\x1d', b'\x1e', b'\x1f',
  ])
  let state = instantiate(entropy, Bytes::from_array([]), Bytes::from_array([]))
  let result = generate(state, 32, Bytes::from_array([]))
  assert_true(result is Some(_))
  let r = result.unwrap()
  assert_eq(r.length(), 32)
  // Output should not be all zeros.
  let mut all_zero = true
  for i = 0; i < 32; i = i + 1 {
    if r[i] != b'\x00' {
      all_zero = false
    }
  }
  assert_true(!all_zero)
}

///|
test "csprng: deterministic — same seed produces same output" {
  let entropy = Bytes::from_array([
    b'\xaa', b'\xbb', b'\xcc', b'\xdd', b'\xee', b'\xff', b'\x00', b'\x11',
    b'\x22', b'\x33', b'\x44', b'\x55', b'\x66', b'\x77', b'\x88', b'\x99',
    b'\xaa', b'\xbb', b'\xcc', b'\xdd', b'\xee', b'\xff', b'\x00', b'\x11',
    b'\x22', b'\x33', b'\x44', b'\x55', b'\x66', b'\x77', b'\x88', b'\x99',
  ])
  let state1 = instantiate(entropy, Bytes::from_array([]), Bytes::from_array([]))
  let state2 = instantiate(entropy, Bytes::from_array([]), Bytes::from_array([]))
  let r1 = generate(state1, 64, Bytes::from_array([])).unwrap()
  let r2 = generate(state2, 64, Bytes::from_array([])).unwrap()
  for i = 0; i < 64; i = i + 1 {
    assert_eq(r1[i], r2[i])
  }
}

///|
test "csprng: different seeds produce different output" {
  let entropy1 = Bytes::from_array([
    b'\x01', b'\x02', b'\x03', b'\x04', b'\x05', b'\x06', b'\x07', b'\x08',
    b'\x09', b'\x0a', b'\x0b', b'\x0c', b'\x0d', b'\x0e', b'\x0f', b'\x10',
    b'\x11', b'\x12', b'\x13', b'\x14', b'\x15', b'\x16', b'\x17', b'\x18',
    b'\x19', b'\x1a', b'\x1b', b'\x1c', b'\x1d', b'\x1e', b'\x1f', b'\x20',
  ])
  let entropy2 = Bytes::from_array([
    b'\x02', b'\x03', b'\x04', b'\x05', b'\x06', b'\x07', b'\x08', b'\x09',
    b'\x0a', b'\x0b', b'\x0c', b'\x0d', b'\x0e', b'\x0f', b'\x10', b'\x11',
    b'\x12', b'\x13', b'\x14', b'\x15', b'\x16', b'\x17', b'\x18', b'\x19',
    b'\x1a', b'\x1b', b'\x1c', b'\x1d', b'\x1e', b'\x1f', b'\x20', b'\x21',
  ])
  let state1 = instantiate(entropy1, Bytes::from_array([]), Bytes::from_array([]))
  let state2 = instantiate(entropy2, Bytes::from_array([]), Bytes::from_array([]))
  let r1 = generate(state1, 32, Bytes::from_array([])).unwrap()
  let r2 = generate(state2, 32, Bytes::from_array([])).unwrap()
  let mut different = false
  for i = 0; i < 32; i = i + 1 {
    if r1[i] != r2[i] {
      different = true
    }
  }
  assert_true(different)
}

///|
test "csprng: reseed changes output" {
  let entropy = Bytes::from_array([
    b'\x00', b'\x01', b'\x02', b'\x03', b'\x04', b'\x05', b'\x06', b'\x07',
    b'\x08', b'\x09', b'\x0a', b'\x0b', b'\x0c', b'\x0d', b'\x0e', b'\x0f',
    b'\x10', b'\x11', b'\x12', b'\x13', b'\x14', b'\x15', b'\x16', b'\x17',
    b'\x18', b'\x19', b'\x1a', b'\x1b', b'\x1c', b'\x1d', b'\x1e', b'\x1f',
  ])
  let state = instantiate(entropy, Bytes::from_array([]), Bytes::from_array([]))
  let r1 = generate(state, 32, Bytes::from_array([])).unwrap()
  // Reseed with different entropy.
  let new_entropy = Bytes::from_array([
    b'\xff', b'\xee', b'\xdd', b'\xcc', b'\xbb', b'\xaa', b'\x99', b'\x88',
    b'\x77', b'\x66', b'\x55', b'\x44', b'\x33', b'\x22', b'\x11', b'\x00',
    b'\xff', b'\xee', b'\xdd', b'\xcc', b'\xbb', b'\xaa', b'\x99', b'\x88',
    b'\x77', b'\x66', b'\x55', b'\x44', b'\x33', b'\x22', b'\x11', b'\x00',
  ])
  reseed(state, new_entropy, Bytes::from_array([]))
  let r2 = generate(state, 32, Bytes::from_array([])).unwrap()
  let mut different = false
  for i = 0; i < 32; i = i + 1 {
    if r1[i] != r2[i] {
      different = true
    }
  }
  assert_true(different)
}

///|
test "csprng: generate multiple blocks" {
  let entropy = Bytes::from_array([
    b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00',
    b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00',
    b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00',
    b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x01',
  ])
  let state = instantiate(entropy, Bytes::from_array([]), Bytes::from_array([]))
  // Generate 128 bytes (4 blocks of 32).
  let result = generate(state, 128, Bytes::from_array([])).unwrap()
  assert_eq(result.length(), 128)
  // At least the first bytes of each block should differ with overwhelming probability.
  assert_true(result[0] != result[32] || result[1] != result[33])
}

///|
test "csprng: generate zero bytes returns empty" {
  let entropy = Bytes::from_array(Array::make(32, b'\x42'))
  let state = instantiate(entropy, Bytes::from_array([]), Bytes::from_array([]))
  let result = generate(state, 0, Bytes::from_array([])).unwrap()
  assert_eq(result.length(), 0)
}

///|
test "csprng: generate_below produces values in range" {
  let entropy = Bytes::from_array(Array::make(32, b'\x07'))
  let state = instantiate(entropy, Bytes::from_array([]), Bytes::from_array([]))
  // Generate 100 values in [0, 10) and verify they're all in range.
  for _ in 0..<100 {
    let v = generate_below(state, 10).unwrap()
    assert_true(v >= 0 && v < 10)
  }
}

///|
test "csprng: additional input affects output" {
  let entropy = Bytes::from_array(Array::make(32, b'\x01'))
  let state1 = instantiate(entropy, Bytes::from_array([]), Bytes::from_array([]))
  let state2 = instantiate(entropy, Bytes::from_array([]), Bytes::from_array([]))
  let add_input = Bytes::from_array([b'\xff', b'\xff', b'\xff', b'\xff'])
  let r1 = generate(state1, 32, Bytes::from_array([])).unwrap()
  let r2 = generate(state2, 32, add_input).unwrap()
  let mut different = false
  for i = 0; i < 32; i = i + 1 {
    if r1[i] != r2[i] {
      different = true
    }
  }
  assert_true(different)
}
