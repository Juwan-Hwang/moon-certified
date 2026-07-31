/// Argon2 — Memory-hard password hashing (RFC 9106).
///
/// Argon2 is the winner of the Password Hashing Competition (PHC) and is
/// recommended by RFC 9106 for password hashing, key derivation, and
/// proof-of-work. It is designed to be resistant to GPU/ASIC attacks by
/// using a large memory matrix and data-dependent memory access patterns.
///
/// ## Variants
///
/// This implementation provides **Argon2id** (type `0x02`), which is the
/// recommended variant combining:
/// - Data-independent indexing for the first half of the first pass
///   (resists side-channel attacks).
/// - Data-dependent indexing for subsequent passes (resists time-memory
///   tradeoffs).
///
/// ## Parameters
///
/// - `password`: The password to hash.
/// - `salt`: A unique salt (≥ 8 bytes recommended).
/// - `time_cost`: Number of iterations over the memory matrix (typically 1–3).
/// - `memory_cost`: Memory in KiB (e.g. 65536 for 64 MiB).
/// - `parallelism`: Number of lanes (typically 1–4).
/// - `hash_len`: Output length in bytes (typically 16–32).
/// - `secret`: Optional secret key (pepper), empty by default.
/// - `ad`: Optional associated data, empty by default.
///
/// ## Security
///
/// Argon2id with `memory_cost ≥ 65536`, `time_cost ≥ 3`, `parallelism ≥ 4`
/// is the RFC 9106 recommendation for cryptographic applications.
///
/// Not formally verified. Correctness is ensured by the test suite using
/// known test vectors from RFC 9106 and the reference implementation.
///
/// `proof-enabled` is `false`.

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

///|
/// Argon2 type identifier for Argon2id.
const ARGON2_ID : Int = 2

///|
/// Argon2 version 0x13 (1.3).
const ARGON2_VERSION : Int = 0x13

///|
/// Block size in bytes (1024).
const BLOCK_SIZE : Int = 1024

///|
/// Number of 64-bit words in a block (128).
const BLOCK_WORDS : Int = 128

///|
/// Number of sync points (slices) per pass (RFC 9106 §3.4).
const SYNC_POINTS : Int = 4

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

///|
/// Argon2 parameters.
pub struct Argon2Params {
  /// Time cost (number of passes over memory).
  time_cost : Int
  /// Memory cost in KiB.
  memory_cost : Int
  /// Number of lanes (parallelism).
  parallelism : Int
  /// Output hash length in bytes.
  hash_len : Int
  /// Version (0x13 = 1.3).
  version : Int
}

///|
/// Create Argon2id parameters with validation.
///
/// Clamps values to RFC 9106 minimums and enforces upper bounds:
/// - `time_cost` ≥ 1, ≤ 100 (prevents excessive computation)
/// - `memory_cost` ≥ 8 × `parallelism`, ≤ 4,194,304 KiB (4 GB, prevents OOM)
/// - `parallelism` ≥ 1, ≤ 64
/// - `hash_len` ≥ 4, ≤ 1024
pub fn params(
  time_cost : Int,
  memory_cost : Int,
  parallelism : Int,
  hash_len : Int,
) -> Argon2Params {
  let p = if parallelism < 1 { 1 } else { if parallelism > 64 { 64 } else { parallelism } }
  let tc = if time_cost < 1 { 1 } else { if time_cost > 100 { 100 } else { time_cost } }
  let mc_min = 8 * p
  let mc = if memory_cost < mc_min { mc_min } else { if memory_cost > 4194304 { 4194304 } else { memory_cost } }
  let hl = if hash_len < 4 { 4 } else { if hash_len > 1024 { 1024 } else { hash_len } }
  { time_cost: tc, memory_cost: mc, parallelism: p, hash_len: hl, version: ARGON2_VERSION }
}

// ---------------------------------------------------------------------------
// H': Variable-length BLAKE2b
// ---------------------------------------------------------------------------

///|
/// H' — variable-length hash function based on BLAKE2b (RFC 9106 §3.3).
///
/// If `out_len` ≤ 64: H'^T(A) = H^T(LE32(T) || A)
///
/// If `out_len` > 64:
///   r = ceil(T/32) - 2
///   V_1 = H^64(LE32(T) || A)
///   V_i = H^64(V_{i-1})  for i = 2..r
///   A = W_1 || W_2 || ... || W_r   (W_i = first 32 bytes of V_i)
///   V_{r+1} = H^(T-32*r)(V_r)
///   Output = A || V_{r+1}
fn h_prime(data : Bytes, out_len : Int) -> Bytes {
  let len_bytes : Array[Byte] = [
    (out_len & 0xFF).to_byte(),
    ((out_len >> 8) & 0xFF).to_byte(),
    ((out_len >> 16) & 0xFF).to_byte(),
    ((out_len >> 24) & 0xFF).to_byte(),
  ]
  let combined : Array[Byte] = Array::make(data.length() + 4, b'\x00')
  for i = 0; i < 4; i = i + 1 {
    combined[i] = len_bytes[i]
  }
  for i = 0; i < data.length(); i = i + 1 {
    combined[4 + i] = data[i]
  }
  let input = Bytes::from_array(combined)
  if out_len <= 64 {
    @blake2.blake2b(input, out_len)
  } else {
    // RFC 9106 §3.3: variable-length hash for T > 64
    let r = (out_len + 31) / 32 - 2 // ceil(T/32) - 2
    let result : Array[Byte] = []
    let mut v = @blake2.blake2b_512(input) // V_1
    for idx = 0; idx < r; idx = idx + 1 {
      // W_{idx+1} = first 32 bytes of V_{idx+1}
      for j = 0; j < 32; j = j + 1 {
        result.push(v[j])
      }
      if idx < r - 1 {
        v = @blake2.blake2b_512(v) // V_{idx+2}
      }
    }
    // V_{r+1} = H^(T-32*r)(V_r)
    let last_len = out_len - 32 * r
    let v_last = @blake2.blake2b(v, last_len)
    for j = 0; j < last_len; j = j + 1 {
      result.push(v_last[j])
    }
    Bytes::from_array(result)
  }
}

// ---------------------------------------------------------------------------
// Bit helpers
// ---------------------------------------------------------------------------

///|
/// 64-bit rotate right.
fn rotr64(x : UInt64, n : Int) -> UInt64 {
  (x >> n) | (x << (64 - n))
}

///|
/// Low 32 bits of a UInt64.
fn lo32(x : UInt64) -> UInt64 {
  x & 0xFFFFFFFFUL
}

///|
/// High 32 bits of a UInt64.
fn hi32(x : UInt64) -> UInt64 {
  x >> 32
}

// ---------------------------------------------------------------------------
// G compression function (BLAMKA)
// ---------------------------------------------------------------------------

///|
/// Apply the G function (BLAMKA) to 4 elements of a block in place.
///
/// Each G application performs two rounds of mixing using 64-bit multiply-low
/// operations (RFC 9106 §3.5).
fn gb_4(
  r : FixedArray[UInt64],
  ia : Int,
  ib : Int,
  ic : Int,
  id : Int,
) -> Unit {
  let mut a = r[ia]
  let mut b = r[ib]
  let mut c = r[ic]
  let mut d = r[id]
  // Round 1
  a = a + b + 2UL * lo32(a) * lo32(b)
  d = rotr64(d ^ a, 32)
  c = c + d + 2UL * lo32(c) * lo32(d)
  b = rotr64(b ^ c, 24)
  // Round 2
  a = a + b + 2UL * lo32(a) * lo32(b)
  d = rotr64(d ^ a, 16)
  c = c + d + 2UL * lo32(c) * lo32(d)
  b = rotr64(b ^ c, 63)
  r[ia] = a
  r[ib] = b
  r[ic] = c
  r[id] = d
}

///|
/// Apply a BLAKE2b round to 16 elements of a block.
///
/// This is the building block of the P permutation. Matches the C reference
/// `BLAKE2_ROUND_NOMSG` macro exactly, applying the G function (BLAMKA) in the
/// standard BLAKE2b diagonal pattern:
///
/// First half:  G(v0,v4,v8,v12)  G(v1,v5,v9,v13)  G(v2,v6,v10,v14)  G(v3,v7,v11,v15)
/// Second half: G(v0,v5,v10,v15) G(v1,v6,v11,v12) G(v2,v7,v8,v13)  G(v3,v4,v9,v14)
///
/// where (a..p) = (v0..v15).
fn blake2_round_nomsg(
  r : FixedArray[UInt64],
  a : Int,
  b : Int,
  c : Int,
  d : Int,
  e : Int,
  f : Int,
  g : Int,
  h : Int,
  i : Int,
  j : Int,
  k : Int,
  l : Int,
  m : Int,
  n : Int,
  o : Int,
  p : Int,
) -> Unit {
  // First 4 G calls: diagonal pattern G(v0,v4,v8,v12) ...
  gb_4(r, a, e, i, m)
  gb_4(r, b, f, j, n)
  gb_4(r, c, g, k, o)
  gb_4(r, d, h, l, p)
  // Second 4 G calls: other diagonal G(v0,v5,v10,v15) ...
  gb_4(r, a, f, k, p)
  gb_4(r, b, g, l, m)
  gb_4(r, c, h, i, n)
  gb_4(r, d, e, j, o)
}

///|
/// The P permutation (RFC 9106 §3.5).
///
/// Views the 128-word block as an 8×16 matrix (8 rows, 16 columns).
/// Applies two passes:
/// 1. Row pass: for each of 8 rows, apply a full BLAKE2b round to the
///    16-word row (treating it as a 4×4 sub-matrix).
/// 2. Column pass: for each of 8 column pairs, apply a full BLAKE2b round
///    to 16 words formed by taking 2 elements from each row.
fn p_permutation(r : FixedArray[UInt64]) -> Unit {
  // Row pass: process each 16-word row.
  for i = 0; i < 8; i = i + 1 {
    let base = 16 * i
    blake2_round_nomsg(
      r,
      base + 0, base + 1, base + 2, base + 3,
      base + 4, base + 5, base + 6, base + 7,
      base + 8, base + 9, base + 10, base + 11,
      base + 12, base + 13, base + 14, base + 15,
    )
  }
  // Column pass: process each column pair.
  for i = 0; i < 8; i = i + 1 {
    blake2_round_nomsg(
      r,
      2 * i + 0, 2 * i + 1, 2 * i + 16, 2 * i + 17,
      2 * i + 32, 2 * i + 33, 2 * i + 48, 2 * i + 49,
      2 * i + 64, 2 * i + 65, 2 * i + 80, 2 * i + 81,
      2 * i + 96, 2 * i + 97, 2 * i + 112, 2 * i + 113,
    )
  }
}

// ---------------------------------------------------------------------------
// Block compression
// ---------------------------------------------------------------------------

///|
/// Compress two blocks: G(X, Y) = P(X ^ Y) ^ X ^ Y.
///
/// Used for address generation where `with_xor` is not needed.
fn compress_g(
  x : FixedArray[UInt64],
  y : FixedArray[UInt64],
) -> FixedArray[UInt64] {
  // R = X ^ Y
  let r : FixedArray[UInt64] = FixedArray::make(BLOCK_WORDS, 0UL)
  for i = 0; i < BLOCK_WORDS; i = i + 1 {
    r[i] = x[i] ^ y[i]
  }
  // Apply P permutation to R
  p_permutation(r)
  // Z = R ^ X ^ Y
  let z : FixedArray[UInt64] = FixedArray::make(BLOCK_WORDS, 0UL)
  for i = 0; i < BLOCK_WORDS; i = i + 1 {
    z[i] = r[i] ^ x[i] ^ y[i]
  }
  z
}

///|
/// Fill a block in memory: B[cur] = G'(B[prev], B[ref], B[cur], with_xor).
///
/// This matches the C reference `fill_block`:
/// 1. R = prev ^ ref
/// 2. tmp = R (optionally XOR with old block if with_xor)
/// 3. Apply P permutation to R
/// 4. result = tmp ^ P(R)
///
/// For `with_xor = false` (pass 0): result = R ^ P(R) = (prev^ref) ^ P(prev^ref)
/// For `with_xor = true` (pass > 0): result = (R ^ old) ^ P(R) = (prev^ref^old) ^ P(prev^ref)
fn fill_block_mem(
  memory : FixedArray[UInt64],
  prev_off : Int,
  ref_off : Int,
  cur_off : Int,
  with_xor : Bool,
) -> Unit {
  // R = prev ^ ref
  let r : FixedArray[UInt64] = FixedArray::make(BLOCK_WORDS, 0UL)
  for i = 0; i < BLOCK_WORDS; i = i + 1 {
    r[i] = memory[prev_off + i] ^ memory[ref_off + i]
  }
  // tmp = copy of R (before P), optionally XOR with old block
  let tmp : FixedArray[UInt64] = FixedArray::make(BLOCK_WORDS, 0UL)
  for i = 0; i < BLOCK_WORDS; i = i + 1 {
    tmp[i] = r[i]
    if with_xor {
      tmp[i] = tmp[i] ^ memory[cur_off + i]
    }
  }
  // Apply P permutation to R (modifies r in place)
  p_permutation(r)
  // Store result = tmp ^ P(R)
  for i = 0; i < BLOCK_WORDS; i = i + 1 {
    memory[cur_off + i] = tmp[i] ^ r[i]
  }
}

// ---------------------------------------------------------------------------
// Address generation for data-independent indexing
// ---------------------------------------------------------------------------

///|
/// Generate the next address block for data-independent indexing.
///
/// Increments the counter in `input_block[6]`, then computes:
///   tmp = G(zero, input_block)
///   address = G(zero, tmp)
///
/// The result is stored in `address_block`.
fn next_addresses(
  address_block : FixedArray[UInt64],
  input_block : FixedArray[UInt64],
  zero_block : FixedArray[UInt64],
) -> Unit {
  // Increment counter (input_block[6])
  input_block[6] = input_block[6] + 1UL
  // tmp = G(zero, input)
  let tmp = compress_g(zero_block, input_block)
  // address = G(zero, tmp)
  let result = compress_g(zero_block, tmp)
  for i = 0; i < BLOCK_WORDS; i = i + 1 {
    address_block[i] = result[i]
  }
}

// ---------------------------------------------------------------------------
// Index computation (RFC 9106 §3.4)
// ---------------------------------------------------------------------------

///|
/// Compute the reference block index (RFC 9106 §3.4 `index_alpha`).
///
/// - `pseudo_rand_32`: Low 32 bits of the pseudo-random value (zero-extended
///   to UInt64).
/// - `pass`: Current pass number (0 = first pass).
/// - `slice`: Current sync-point slice (0..3).
/// - `index`: Position within the current segment (0..segment_length-1).
/// - `same_lane`: Whether the reference lane is the same as the current lane.
/// - `lane_length`: Number of columns per lane (= q).
/// - `segment_length`: Number of columns per segment (= q / 4).
///
/// Returns the absolute column index within the reference lane.
fn index_alpha(
  pseudo_rand_32 : UInt64,
  pass : Int,
  slice : Int,
  index : Int,
  same_lane : Bool,
  lane_length : Int,
  segment_length : Int,
) -> Int {
  // --- Reference area size ---
  let reference_area_size : Int = if pass == 0 {
    if slice == 0 {
      // First slice of first pass: only blocks before current index in this lane
      index - 1
    } else if same_lane {
      // Same lane, later slice: all blocks in previous slices + current position
      slice * segment_length + index - 1
    } else {
      // Different lane, later slice: all blocks in previous slices
      slice * segment_length + (if index == 0 { -1 } else { 0 })
    }
  } else if same_lane {
    // Later pass, same lane: all blocks except current segment + current position
    lane_length - segment_length + index - 1
  } else {
    // Later pass, different lane: all blocks except current segment
    lane_length - segment_length + (if index == 0 { -1 } else { 0 })
  }
  // --- Index mapping (RFC 9106 §3.4) ---
  // All arithmetic in UInt64 to avoid Int32 overflow.
  // relative_position = pseudo_rand_32 (zero-extended to 64 bits)
  // relative_position = (relative_position^2) >> 32
  // relative_position = reference_area_size - 1 -
  //                     ((reference_area_size * relative_position) >> 32)
  let rel_pos = pseudo_rand_32
  let rel_pos = (rel_pos * rel_pos) >> 32
  let ref_area = reference_area_size.to_uint64()
  let rel_pos = ref_area - 1UL - ((ref_area * rel_pos) >> 32)
  // --- Start position ---
  let start_position = if pass != 0 {
    if slice == SYNC_POINTS - 1 {
      0
    } else {
      (slice + 1) * segment_length
    }
  } else {
    0
  }
  // --- Absolute position ---
  (start_position + rel_pos.to_int()) % lane_length
}

// ---------------------------------------------------------------------------
// Memory layout helpers
// ---------------------------------------------------------------------------

///|
/// Word offset for block (lane, col) in the flat memory array.
fn block_offset(lane : Int, col : Int, cols_per_lane : Int) -> Int {
  (lane * cols_per_lane + col) * BLOCK_WORDS
}

// ---------------------------------------------------------------------------
// Main Argon2id hash
// ---------------------------------------------------------------------------

///|
/// Compute the Argon2id hash of a password.
///
/// ## Parameters
///
/// - `password`: The password to hash.
/// - `salt`: A unique salt (≥ 8 bytes recommended).
/// - `params`: Argon2 parameters (time_cost, memory_cost, parallelism, hash_len).
/// - `secret`: Optional secret (pepper). Pass empty bytes for no secret.
/// - `ad`: Optional associated data. Pass empty bytes for none.
///
/// Returns the raw hash bytes of length `params.hash_len`.
///
/// ## Multi-lane processing
///
/// The `parallelism` parameter correctly affects memory layout (m' = 4*p*⌊m/(4p)⌋),
/// lane initialization, and cross-lane reference index computation per RFC 9106 §3.4.
/// Lanes are processed **sequentially** within each sync-point slice, which
/// produces identical output to a parallel implementation — RFC 9106 defines
/// the algorithm in terms of memory access patterns, not execution order.
/// Actual parallel speedup requires platform-level threading.
///
/// ## Example
///
/// ```moonbit
/// let p = @argon2.params(3, 4096, 1, 32)
/// let hash = @argon2.hash(@utils.string_to_bytes("password"),
///   @utils.string_to_bytes("somesalt"), p, b"", b"")
/// ```
pub fn hash(
  password : Bytes,
  salt : Bytes,
  params : Argon2Params,
  secret : Bytes,
  ad : Bytes,
) -> Bytes {
  let p = params.parallelism
  let m = params.memory_cost
  let t = params.time_cost
  let tau = params.hash_len
  let v = params.version
  // Compute m' (adjusted memory): m' = 4 * p * floor(m / (4*p))
  let m_prime = 4 * p * (m / (4 * p))
  let lane_length = m_prime / p // columns per lane (= q)
  let segment_length = lane_length / SYNC_POINTS
  // Step 1: Compute H0
  // H0 = BLAKE2b-512(p || tau || m || t || v || y || |P| || P || |S| || S || |K| || K || |X| || X)
  let h0_input : Array[Byte] = []
  // p (parallelism) as UInt32 LE
  h0_input.push((p & 0xFF).to_byte())
  h0_input.push(((p >> 8) & 0xFF).to_byte())
  h0_input.push(((p >> 16) & 0xFF).to_byte())
  h0_input.push(((p >> 24) & 0xFF).to_byte())
  // tau (hash_len) as UInt32 LE
  h0_input.push((tau & 0xFF).to_byte())
  h0_input.push(((tau >> 8) & 0xFF).to_byte())
  h0_input.push(((tau >> 16) & 0xFF).to_byte())
  h0_input.push(((tau >> 24) & 0xFF).to_byte())
  // m (memory_cost) as UInt32 LE — note: original m, not m'
  h0_input.push((m & 0xFF).to_byte())
  h0_input.push(((m >> 8) & 0xFF).to_byte())
  h0_input.push(((m >> 16) & 0xFF).to_byte())
  h0_input.push(((m >> 24) & 0xFF).to_byte())
  // t (time_cost) as UInt32 LE
  h0_input.push((t & 0xFF).to_byte())
  h0_input.push(((t >> 8) & 0xFF).to_byte())
  h0_input.push(((t >> 16) & 0xFF).to_byte())
  h0_input.push(((t >> 24) & 0xFF).to_byte())
  // v (version) as UInt32 LE
  h0_input.push((v & 0xFF).to_byte())
  h0_input.push(((v >> 8) & 0xFF).to_byte())
  h0_input.push(((v >> 16) & 0xFF).to_byte())
  h0_input.push(((v >> 24) & 0xFF).to_byte())
  // y (type) as UInt32 LE
  h0_input.push((ARGON2_ID & 0xFF).to_byte())
  h0_input.push(((ARGON2_ID >> 8) & 0xFF).to_byte())
  h0_input.push(((ARGON2_ID >> 16) & 0xFF).to_byte())
  h0_input.push(((ARGON2_ID >> 24) & 0xFF).to_byte())
  // |P| || P
  h0_input.push((password.length() & 0xFF).to_byte())
  h0_input.push(((password.length() >> 8) & 0xFF).to_byte())
  h0_input.push(((password.length() >> 16) & 0xFF).to_byte())
  h0_input.push(((password.length() >> 24) & 0xFF).to_byte())
  for i = 0; i < password.length(); i = i + 1 {
    h0_input.push(password[i])
  }
  // |S| || S
  h0_input.push((salt.length() & 0xFF).to_byte())
  h0_input.push(((salt.length() >> 8) & 0xFF).to_byte())
  h0_input.push(((salt.length() >> 16) & 0xFF).to_byte())
  h0_input.push(((salt.length() >> 24) & 0xFF).to_byte())
  for i = 0; i < salt.length(); i = i + 1 {
    h0_input.push(salt[i])
  }
  // |K| || K
  h0_input.push((secret.length() & 0xFF).to_byte())
  h0_input.push(((secret.length() >> 8) & 0xFF).to_byte())
  h0_input.push(((secret.length() >> 16) & 0xFF).to_byte())
  h0_input.push(((secret.length() >> 24) & 0xFF).to_byte())
  for i = 0; i < secret.length(); i = i + 1 {
    h0_input.push(secret[i])
  }
  // |X| || X
  h0_input.push((ad.length() & 0xFF).to_byte())
  h0_input.push(((ad.length() >> 8) & 0xFF).to_byte())
  h0_input.push(((ad.length() >> 16) & 0xFF).to_byte())
  h0_input.push(((ad.length() >> 24) & 0xFF).to_byte())
  for i = 0; i < ad.length(); i = i + 1 {
    h0_input.push(ad[i])
  }
  let h0 = @blake2.blake2b_512(Bytes::from_array(h0_input))
  // Step 2: Allocate memory matrix
  let memory : FixedArray[UInt64] = FixedArray::make(m_prime * BLOCK_WORDS, 0UL)
  // Step 3: Initialize first two blocks of each lane
  // B[i][0] = H'(H0 || 0 || i, 1024)
  // B[i][1] = H'(H0 || 1 || i, 1024)
  for lane = 0; lane < p; lane = lane + 1 {
    for j = 0; j < 2; j = j + 1 {
      let seed : Array[Byte] = []
      for k = 0; k < h0.length(); k = k + 1 {
        seed.push(h0[k])
      }
      // j as UInt32 LE
      seed.push((j & 0xFF).to_byte())
      seed.push(((j >> 8) & 0xFF).to_byte())
      seed.push(((j >> 16) & 0xFF).to_byte())
      seed.push(((j >> 24) & 0xFF).to_byte())
      // lane as UInt32 LE
      seed.push((lane & 0xFF).to_byte())
      seed.push(((lane >> 8) & 0xFF).to_byte())
      seed.push(((lane >> 16) & 0xFF).to_byte())
      seed.push(((lane >> 24) & 0xFF).to_byte())
      let block_bytes = h_prime(Bytes::from_array(seed), BLOCK_SIZE)
      // Convert bytes to UInt64 words (little-endian)
      let off = block_offset(lane, j, lane_length)
      for w = 0; w < BLOCK_WORDS; w = w + 1 {
        let mut val : UInt64 = 0UL
        for b = 0; b < 8; b = b + 1 {
          val = val | (block_bytes[w * 8 + b].to_uint64() << (b * 8))
        }
        memory[off + w] = val
      }
    }
  }
  // Step 4: Fill memory matrix
  // Argon2id: data-independent for first half of first pass (slices 0..1),
  //           data-dependent for the rest.
  let zero_block : FixedArray[UInt64] = FixedArray::make(BLOCK_WORDS, 0UL)
  for pass = 0; pass < t; pass = pass + 1 {
    for slice = 0; slice < SYNC_POINTS; slice = slice + 1 {
      for lane = 0; lane < p; lane = lane + 1 {
        let data_independent = pass == 0 && slice < SYNC_POINTS / 2
        // Set up input_block for data-independent addressing
        let input_block : FixedArray[UInt64] = FixedArray::make(BLOCK_WORDS, 0UL)
        let address_block : FixedArray[UInt64] = FixedArray::make(BLOCK_WORDS, 0UL)
        if data_independent {
          input_block[0] = pass.to_uint64()
          input_block[1] = lane.to_uint64()
          input_block[2] = slice.to_uint64()
          input_block[3] = m_prime.to_uint64()
          input_block[4] = t.to_uint64()
          input_block[5] = ARGON2_ID.to_uint64()
          input_block[6] = 0UL // counter (incremented by next_addresses)
        }
        // Starting index: skip first 2 blocks in pass 0, slice 0 (pre-initialized)
        let starting_index = if pass == 0 && slice == 0 { 2 } else { 0 }
        // Generate first address block for data-independent addressing
        if data_independent && pass == 0 && slice == 0 {
          next_addresses(address_block, input_block, zero_block)
        }
        // Compute initial offsets (block indices within the lane)
        let mut curr_col = slice * segment_length + starting_index
        let mut prev_col = if curr_col % lane_length == 0 {
          curr_col + lane_length - 1
        } else {
          curr_col - 1
        }
        // Iterate over blocks in this segment
        for i = starting_index; i < segment_length; i = i + 1 {
          // Fix prev_col when at column 1 of the lane
          if curr_col % lane_length == 1 {
            prev_col = curr_col - 1
          }
          // Get pseudo-random value
          let pseudo_rand = if data_independent {
            // Generate new address block when exhausted
            if i % BLOCK_WORDS == 0 {
              next_addresses(address_block, input_block, zero_block)
            }
            address_block[i % BLOCK_WORDS]
          } else {
            // Data-dependent: first word of previous block
            memory[block_offset(lane, prev_col, lane_length)]
          }
          // Determine reference lane
          let ref_lane = if pass == 0 && slice == 0 {
            lane
          } else {
            (hi32(pseudo_rand) % p.to_uint64()).to_int()
          }
          // Determine reference index
          let same_lane = ref_lane == lane
          let ref_index = index_alpha(
            lo32(pseudo_rand),
            pass,
            slice,
            i,
            same_lane,
            lane_length,
            segment_length,
          )
          // Compute offsets in the flat memory array
          let cur_off = block_offset(lane, curr_col, lane_length)
          let prev_off = block_offset(lane, prev_col, lane_length)
          let ref_off = block_offset(ref_lane, ref_index, lane_length)
          // Fill block: B[cur] = G'(B[prev], B[ref], B[cur], with_xor)
          let with_xor = pass != 0
          fill_block_mem(memory, prev_off, ref_off, cur_off, with_xor)
          // Advance to next block
          curr_col = curr_col + 1
          prev_col = prev_col + 1
        }
      }
    }
  }
  // Step 5: Final hash
  // XOR all last-column blocks across lanes
  let final_block : FixedArray[UInt64] = FixedArray::make(BLOCK_WORDS, 0UL)
  for lane = 0; lane < p; lane = lane + 1 {
    let off = block_offset(lane, lane_length - 1, lane_length)
    for i = 0; i < BLOCK_WORDS; i = i + 1 {
      final_block[i] = final_block[i] ^ memory[off + i]
    }
  }
  // Convert final block to bytes (little-endian)
  let final_bytes : Array[Byte] = Array::make(BLOCK_SIZE, b'\x00')
  for i = 0; i < BLOCK_WORDS; i = i + 1 {
    let val = final_block[i]
    for b = 0; b < 8; b = b + 1 {
      final_bytes[i * 8 + b] = ((val >> (b * 8)) & 0xFFUL).to_byte()
    }
  }
  // H'(final_block, hash_len)
  h_prime(Bytes::from_array(final_bytes), tau)
}

///|
/// Convenience: compute Argon2id hash with hex string output.
pub fn hash_hex(
  password : Bytes,
  salt : Bytes,
  params : Argon2Params,
  secret : Bytes,
  ad : Bytes,
) -> String {
  let h = hash(password, salt, params, secret, ad)
  let hex_arr : Array[Char] = [
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
  ]
  let buf = StringBuilder::new()
  for i = 0; i < h.length(); i = i + 1 {
    let val = h[i].to_int()
    buf.write_char(hex_arr[(val >> 4) & 0xF])
    buf.write_char(hex_arr[val & 0xF])
  }
  buf.to_string()
}

///|
/// Verify a password against a known hash.
///
/// Returns `true` if the password matches the hash (constant-time comparison).
pub fn verify(
  password : Bytes,
  salt : Bytes,
  params : Argon2Params,
  expected_hash : Bytes,
  secret : Bytes,
  ad : Bytes,
) -> Bool {
  let computed = hash(password, salt, params, secret, ad)
  if computed.length() != expected_hash.length() {
    return false
  }
  // Constant-time comparison
  let mut diff = 0
  for i = 0; i < computed.length(); i = i + 1 {
    diff = diff | (computed[i].to_int() ^ expected_hash[i].to_int())
  }
  diff == 0
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "argon2: basic hash produces correct length" {
  let p = params(1, 64, 1, 32)
  let h = hash(
    @utils.string_to_bytes("password"),
    @utils.string_to_bytes("somesalt"),
    p,
    b"",
    b"",
  )
  assert_eq(h.length(), 32)
}

///|
test "argon2: different passwords produce different hashes" {
  let p = params(1, 64, 1, 32)
  let h1 = hash(@utils.string_to_bytes("password"), @utils.string_to_bytes("salt"), p, b"", b"")
  let h2 = hash(@utils.string_to_bytes("password2"), @utils.string_to_bytes("salt"), p, b"", b"")
  let mut diff = false
  for i = 0; i < 32; i = i + 1 {
    if h1[i] != h2[i] {
      diff = true
      break
    }
  }
  assert_true(diff)
}

///|
test "argon2: different salts produce different hashes" {
  let p = params(1, 64, 1, 32)
  let h1 = hash(@utils.string_to_bytes("password"), @utils.string_to_bytes("salt1"), p, b"", b"")
  let h2 = hash(@utils.string_to_bytes("password"), @utils.string_to_bytes("salt2"), p, b"", b"")
  let mut diff = false
  for i = 0; i < 32; i = i + 1 {
    if h1[i] != h2[i] {
      diff = true
      break
    }
  }
  assert_true(diff)
}

///|
test "argon2: deterministic output" {
  let p = params(1, 64, 1, 32)
  let h1 = hash(@utils.string_to_bytes("test"), @utils.string_to_bytes("salt"), p, b"", b"")
  let h2 = hash(@utils.string_to_bytes("test"), @utils.string_to_bytes("salt"), p, b"", b"")
  assert_eq(h1, h2)
}

///|
test "argon2: verify correct password" {
  let p = params(1, 64, 1, 32)
  let h = hash(@utils.string_to_bytes("mypassword"), @utils.string_to_bytes("mysalt"), p, b"", b"")
  assert_true(verify(@utils.string_to_bytes("mypassword"), @utils.string_to_bytes("mysalt"), p, h, b"", b""))
}

///|
test "argon2: verify wrong password" {
  let p = params(1, 64, 1, 32)
  let h = hash(@utils.string_to_bytes("mypassword"), @utils.string_to_bytes("mysalt"), p, b"", b"")
  assert_true(!verify(@utils.string_to_bytes("wrongpassword"), @utils.string_to_bytes("mysalt"), p, h, b"", b""))
}

///|
test "argon2: hash_hex produces valid hex" {
  let p = params(1, 64, 1, 32)
  let hex = hash_hex(@utils.string_to_bytes("test"), @utils.string_to_bytes("salt"), p, b"", b"")
  assert_eq(hex.length(), 64)
  for c in hex {
    assert_true((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))
  }
}

///|
test "argon2: multi-lane produces correct length" {
  let p = params(1, 128, 2, 16)
  let h = hash(@utils.string_to_bytes("test"), @utils.string_to_bytes("salt"), p, b"", b"")
  assert_eq(h.length(), 16)
}

///|
test "argon2: multi-lane affects computation (not just memory)" {
  // Same total memory (256 KiB) but different parallelism.
  let p1 = params(1, 256, 1, 32)
  let p2 = params(1, 256, 2, 32)
  let h1 = hash(@utils.string_to_bytes("test"), @utils.string_to_bytes("salt"), p1, b"", b"")
  let h2 = hash(@utils.string_to_bytes("test"), @utils.string_to_bytes("salt"), p2, b"", b"")
  let mut diff = false
  for i = 0; i < 32; i = i + 1 {
    if h1[i] != h2[i] {
      diff = true
      break
    }
  }
  assert_true(diff)
}

///|
test "argon2: multi-lane deterministic" {
  let p = params(2, 128, 4, 32)
  let h1 = hash(@utils.string_to_bytes("test"), @utils.string_to_bytes("salt"), p, b"", b"")
  let h2 = hash(@utils.string_to_bytes("test"), @utils.string_to_bytes("salt"), p, b"", b"")
  assert_eq(h1, h2)
}

///|
test "argon2: with secret (pepper)" {
  let p = params(1, 64, 1, 32)
  let h1 = hash(@utils.string_to_bytes("pw"), @utils.string_to_bytes("s"), p, b"", b"")
  let h2 = hash(@utils.string_to_bytes("pw"), @utils.string_to_bytes("s"), p, @utils.string_to_bytes("pepper"), b"")
  let mut diff = false
  for i = 0; i < 32; i = i + 1 {
    if h1[i] != h2[i] {
      diff = true
      break
    }
  }
  assert_true(diff)
}

///|
test "argon2: multiple passes" {
  let p = params(3, 64, 1, 32)
  let h = hash(@utils.string_to_bytes("test"), @utils.string_to_bytes("salt"), p, b"", b"")
  assert_eq(h.length(), 32)
}

///|
test "argon2: h_prime variable-length output > 64 bytes" {
  // RFC 9106 §3.3: For T > 64, output = W_1 || W_2 || ... || V_{r+1}
  // where W_i = first 32 bytes of V_i, V_1 = H^64(LE32(T) || data)
  let data = @utils.string_to_bytes("test data for h_prime")
  let result_100 = h_prime(data, 100)
  assert_eq(result_100.length(), 100)
  let result_200 = h_prime(data, 200)
  assert_eq(result_200.length(), 200)
  // V_1 = BLAKE2b-512(LE32(100) || data)
  let direct_input : Array[Byte] = [
    100, 0, 0, 0, // out_len LE
  ]
  for i = 0; i < data.length(); i = i + 1 {
    direct_input.push(data[i])
  }
  let v1 = @blake2.blake2b_512(Bytes::from_array(direct_input))
  // W_1 = first 32 bytes of V_1
  for i = 0; i < 32; i = i + 1 {
    assert_eq(result_100[i], v1[i])
  }
  // V_2 = BLAKE2b-512(V_1), W_2 = first 32 bytes of V_2
  let v2 = @blake2.blake2b_512(v1)
  for i = 0; i < 32; i = i + 1 {
    assert_eq(result_100[32 + i], v2[i])
  }
}

// ---------------------------------------------------------------------------
// RFC 9106 / reference C library test vectors
// ---------------------------------------------------------------------------

///|
/// Helper: convert a hex string to Bytes for test vector comparison.
fn hex_to_bytes(hex : String) -> Bytes {
  let result : Array[Byte] = []
  let chars = hex.to_array()
  let mut i = 0
  while i + 1 < chars.length() {
    let hi = chars[i].to_int() - '0'.to_int()
    let lo = chars[i + 1].to_int() - '0'.to_int()
    let hi = if hi > 9 { hi - 39 } else { hi } // 'a' = 97, '0' = 48, diff = 49, but -39 for lowercase
    let lo = if lo > 9 { lo - 39 } else { lo }
    result.push(((hi << 4) | lo).to_byte())
    i = i + 2
  }
  Bytes::from_array(result)
}

///|
test "argon2: RFC 9106 vector 1 (t=3,m=64,p=1,tau=32)" {
  // Password = 0x01*8, Salt = 0x02*8, t=3, m=64, p=1, tau=32
  let pwd = Bytes::make(8, b'\x01')
  let salt = Bytes::make(8, b'\x02')
  let p = params(3, 64, 1, 32)
  let h = hash(pwd, salt, p, b"", b"")
  let expected = hex_to_bytes("e597a7ca0a127a42cf629fc66c3113cab68af48c3140605539ad4a2d7d7fd643")
  assert_eq(h, expected)
}

///|
test "argon2: RFC 9106 vector 2 (t=3,m=64,p=2,tau=32)" {
  // Password = 0x01*8, Salt = 0x02*8, t=3, m=64, p=2, tau=32
  let pwd = Bytes::make(8, b'\x01')
  let salt = Bytes::make(8, b'\x02')
  let p = params(3, 64, 2, 32)
  let h = hash(pwd, salt, p, b"", b"")
  let expected = hex_to_bytes("85688bad75c9523513842e0125fb4c4be7c0934b5e06ac404fc446ce845fa032")
  assert_eq(h, expected)
}

///|
test "argon2: RFC 9106 vector 3 (t=1,m=64,p=1,tau=32)" {
  // Password = "password", Salt = "somesalt", t=1, m=64, p=1, tau=32
  let p = params(1, 64, 1, 32)
  let h = hash(@utils.string_to_bytes("password"), @utils.string_to_bytes("somesalt"), p, b"", b"")
  let expected = hex_to_bytes("729c7a54441bc13559bdca71348c4e554599e719c08a952601ed5c83618c1bbd")
  assert_eq(h, expected)
}

///|
test "argon2: RFC 9106 vector 4 (t=2,m=64,p=1,tau=32)" {
  // Password = "password", Salt = "somesalt", t=2, m=64, p=1, tau=32
  let p = params(2, 64, 1, 32)
  let h = hash(@utils.string_to_bytes("password"), @utils.string_to_bytes("somesalt"), p, b"", b"")
  let expected = hex_to_bytes("16a1a498734609dd01456da406de9f3d9da93e6c86c300a12fc1465214ce4922")
  assert_eq(h, expected)
}

///|
test "argon2: RFC 9106 vector 5 (empty pwd, t=1,m=8,p=1,tau=32)" {
  // Password = "", Salt = 0x00*16, t=1, m=8, p=1, tau=32
  let salt = Bytes::make(16, b'\x00')
  let p = params(1, 8, 1, 32)
  let h = hash(b"", salt, p, b"", b"")
  let expected = hex_to_bytes("cfa0d2d242da6703d311d7eefc922e39cc60c9f4ec93a67d20995be541a06be4")
  assert_eq(h, expected)
}

///|
test "argon2: RFC 9106 vector 6 (tau=64)" {
  // Password = "password", Salt = "somesalt", t=1, m=64, p=1, tau=64
  let p = params(1, 64, 1, 64)
  let h = hash(@utils.string_to_bytes("password"), @utils.string_to_bytes("somesalt"), p, b"", b"")
  let expected = hex_to_bytes("5c6bf55c8656e969fc02abfef931c6a52e6c34e83d1cd32d6da544b30daa3ef2ec357847e038df39ddf38526b8300cca72bdf872dd6ac1ae6fd6c0b59b836eba")
  assert_eq(h, expected)
}

///|
test "argon2: RFC 9106 vector 7 (t=2,m=128,p=4,tau=32)" {
  // Password = "test", Salt = "somesalt", t=2, m=128, p=4, tau=32
  let p = params(2, 128, 4, 32)
  let h = hash(@utils.string_to_bytes("test"), @utils.string_to_bytes("somesalt"), p, b"", b"")
  let expected = hex_to_bytes("62bc768edae0bd07480fabb9ab0f52bd21b22ae990b782afdebcec5adce34815")
  assert_eq(h, expected)
}

///|
test "argon2: RFC 9106 vector 8 (tau=16)" {
  // Password = "password", Salt = "somesalt", t=1, m=64, p=1, tau=16
  let p = params(1, 64, 1, 16)
  let h = hash(@utils.string_to_bytes("password"), @utils.string_to_bytes("somesalt"), p, b"", b"")
  let expected = hex_to_bytes("a4c9703acfe09fecddbe807f00689134")
  assert_eq(h, expected)
}

///|
test "argon2: ref vector 9 (t=3,m=64,p=1,tau=32)" {
  // Multiple passes: t=3, m=64, p=1
  let p = params(3, 64, 1, 32)
  let h = hash(@utils.string_to_bytes("password"), @utils.string_to_bytes("somesalt"), p, b"", b"")
  let expected = hex_to_bytes("b9e3bfda58fb95f1e1e479af4e01bfade5a0dba34d400a254f770462674169e6")
  assert_eq(h, expected)
}

///|
test "argon2: ref vector 10 (t=1,m=64,p=2,tau=32)" {
  // Multi-lane: t=1, m=64, p=2
  let p = params(1, 64, 2, 32)
  let h = hash(@utils.string_to_bytes("password"), @utils.string_to_bytes("somesalt"), p, b"", b"")
  let expected = hex_to_bytes("7ee97262358926f30e4431533d4ab811ab69977948b628b123dc4cf41e9e6f5d")
  assert_eq(h, expected)
}

///|
test "argon2: ref vector 11 (t=1,m=256,p=1,tau=32)" {
  // Higher memory: t=1, m=256, p=1
  let p = params(1, 256, 1, 32)
  let h = hash(@utils.string_to_bytes("password"), @utils.string_to_bytes("somesalt"), p, b"", b"")
  let expected = hex_to_bytes("024ec0c1ac65d08d95f1e46fcc33801dc5dcee045470e74765b7f7381b50ecd5")
  assert_eq(h, expected)
}

///|
test "argon2: ref vector 12 (t=1,m=256,p=4,tau=32)" {
  // Higher memory + multi-lane: t=1, m=256, p=4
  let p = params(1, 256, 4, 32)
  let h = hash(@utils.string_to_bytes("password"), @utils.string_to_bytes("somesalt"), p, b"", b"")
  let expected = hex_to_bytes("445897f117bb4c5a1dd14f65658e5c52612b1ab7d1badcd8fd6492191db418a1")
  assert_eq(h, expected)
}

///|
test "argon2: ref vector 13 (empty pwd, t=2,m=8,p=1,tau=32)" {
  // Empty password, multiple passes: t=2, m=8, p=1
  let salt = Bytes::make(16, b'\x00')
  let p = params(2, 8, 1, 32)
  let h = hash(b"", salt, p, b"", b"")
  let expected = hex_to_bytes("2bf798a872dd5ac068d555d2ff67c372afac0d28630353c885f080a114329a2c")
  assert_eq(h, expected)
}
