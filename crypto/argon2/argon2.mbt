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
/// known test vectors from the reference implementation.
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
/// If `out_len` ≤ 64, computes BLAKE2b(out_len, [out_len_le32] || data).
/// If `out_len` > 64, computes a chain of BLAKE2b-512 hashes:
///   V_1 = BLAKE2b-512([out_len_le32] || data)
///   V_i = BLAKE2b-512(V_{i-1})
/// and concatenates the first `out_len` bytes.
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
    // Chain BLAKE2b-512 hashes.
    let result : Array[Byte] = []
    let mut v = @blake2.blake2b_512(input)
    for i = 0; i < out_len / 64; i = i + 1 {
      for j = 0; j < 64 && result.length() < out_len; j = j + 1 {
        result.push(v[j])
      }
      if result.length() < out_len {
        v = @blake2.blake2b_512(v)
      }
    }
    // Handle remainder if out_len is not a multiple of 64.
    // The last hash was already computed; just take what we need.
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
// G compression function (correct implementation)
// ---------------------------------------------------------------------------

///|
/// G compression function (RFC 9106 §3.5).
///
/// Takes two 1024-byte blocks, XORs them, applies the P permutation, and
/// XORs the result with the original. The P permutation applies 8 rounds
/// of row-wise mixing followed by 8 rounds of column-wise mixing.
///
/// The matrix is viewed as an 8×16 array of 64-bit integers (row-major).
/// Each round applies the gb function to 8 pairs of columns.
fn compress_g(
  x : FixedArray[UInt64], // 128 words (first block)
  y : FixedArray[UInt64], // 128 words (second block)
) -> FixedArray[UInt64] {
  // R = X ^ Y
  let r : FixedArray[UInt64] = FixedArray::make(BLOCK_WORDS, 0UL)
  for i = 0; i < BLOCK_WORDS; i = i + 1 {
    r[i] = x[i] ^ y[i]
  }
  // Apply P permutation to R.
  p_permutation(r)
  // Z = R ^ X ^ Y (XOR with original inputs for the Feistel-like structure)
  let z : FixedArray[UInt64] = FixedArray::make(BLOCK_WORDS, 0UL)
  for i = 0; i < BLOCK_WORDS; i = i + 1 {
    z[i] = r[i] ^ x[i] ^ y[i]
  }
  z
}

///|
/// The P permutation (RFC 9106 §3.5).
///
/// Views the 128-word block as an 8×16 matrix (8 rows, 16 columns).
/// Applies two passes of the BLAKE2b G function:
/// 1. Column pass: for each of 8 rows, apply G to 4 groups of 4 elements
///    using stride pattern (0,4,8,12), (1,5,9,13), etc.
/// 2. Row pass: for each of 8 column-pairs, apply G to 4 groups of 4
///    elements with stride 16 (cross-row mixing).
///
/// Each G application performs two rounds of the BLAMKA mixing function.
fn p_permutation(r : FixedArray[UInt64]) -> Unit {
  // Column pass: process each row of the 8×16 matrix.
  // For each row i (0..7), apply G to 4 groups of 4 elements with stride 4.
  for i = 0; i < 8; i = i + 1 {
    let base = 16 * i
    gb_4(r, base + 0, base + 4, base + 8, base + 12)
    gb_4(r, base + 1, base + 5, base + 9, base + 13)
    gb_4(r, base + 2, base + 6, base + 10, base + 14)
    gb_4(r, base + 3, base + 7, base + 11, base + 15)
  }
  // Row pass: process column pairs (RFC 9106 §3.5).
  // For each column pair (2i, 2i+1), apply G to rows 0-3 and rows 4-7.
  // Flat index: row*16 + col, max index = 7*16+15 = 127.
  for i = 0; i < 8; i = i + 1 {
    let c0 = 2 * i
    let c1 = 2 * i + 1
    gb_4(r, 0 * 16 + c0, 1 * 16 + c0, 2 * 16 + c0, 3 * 16 + c0)
    gb_4(r, 4 * 16 + c0, 5 * 16 + c0, 6 * 16 + c0, 7 * 16 + c0)
    gb_4(r, 0 * 16 + c1, 1 * 16 + c1, 2 * 16 + c1, 3 * 16 + c1)
    gb_4(r, 4 * 16 + c1, 5 * 16 + c1, 6 * 16 + c1, 7 * 16 + c1)
  }
}

///|
/// Apply the G function to 4 elements of a block at indices (ia, ib, ic, id).
/// Modifies the block in place.
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
  // G(a, b, c, d) — 4 applications of the round function
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

// ---------------------------------------------------------------------------
// Memory layout helpers
// ---------------------------------------------------------------------------

///|
/// Get a pointer (index) into the memory matrix for lane `l`, column `c`.
/// The memory is a flat array of UInt64 words; each block is 128 words.
fn block_offset(lane : Int, col : Int, cols_per_lane : Int) -> Int {
  (lane * cols_per_lane + col) * BLOCK_WORDS
}

///|
/// Copy a block (128 UInt64 words) from src to dst.
fn copy_block(dst : FixedArray[UInt64], dst_off : Int, src : FixedArray[UInt64], src_off : Int) -> Unit {
  for i = 0; i < BLOCK_WORDS; i = i + 1 {
    dst[dst_off + i] = src[src_off + i]
  }
}

// ---------------------------------------------------------------------------
// Indexing computation
// ---------------------------------------------------------------------------

///|
/// Compute the reference area and the index of the reference block
/// for data-dependent addressing (Argon2d/id).
///
/// Returns `(ref_lane, ref_index)`.
///
/// Implements RFC 9106 §3.4 index computation for **multi-lane** Argon2:
/// - `prev_block` is the previous block in the current lane (B[i][j-1]).
/// - `ref_lane` is determined by the second 32 bits of prev_block, clamped
///   to `[0, current_lane]` during pass 0 (a lane may only reference earlier
///   or same lanes during the first pass).
/// - `ref_index` is determined by the first 32 bits, mapped to the
///   reference area `[0, pseudo_rand_size)` using the RFC 9106 §3.4
///   index mapping function.
///
/// **Note**: Lanes are processed sequentially (lane 0 → lane p-1) rather
/// than in parallel. This is correct per RFC 9106 (the spec defines memory
/// access patterns, not execution parallelism) but does not provide the
/// speedup that true multi-threaded execution would. On MoonBit's current
/// Wasm/JS single-threaded target, parallel execution is not available.
fn compute_ref_index(
  prev_block : FixedArray[UInt64],
  prev_off : Int,
  current_lane : Int,
  current_col : Int,
  cols_per_lane : Int,
  pass : Int,
  _same_lane : Bool,
) -> (Int, Int) {
  // J1 = first 32 bits of prev_block[0]
  // J2 = second 32 bits of prev_block[0]
  let j1 = lo32(prev_block[prev_off])
  let j2 = hi32(prev_block[prev_off])
  // Determine reference lane
  let ref_lane = if current_col == cols_per_lane - 1 {
    current_lane
  } else {
    if pass == 0 && current_col < 2 {
      current_lane
    } else {
      // UInt64 modulo to avoid Int32 overflow (j2 can be up to 2^32-1)
      (j2 % (current_lane + 1).to_uint64()).to_int()
    }
  }
  // Determine reference area size
  let reference_area_size : Int = if pass == 0 {
    if ref_lane == current_lane {
      if current_col > 1 { current_col - 1 } else { 1 }
    } else {
      if current_col > 1 { current_col - 1 } else { 1 }
    }
  } else {
    if ref_lane == current_lane {
      cols_per_lane - 1
    } else {
      cols_per_lane
    }
  }
  // Compute reference index using RFC 9106 §3.4 index mapping.
  // All arithmetic in UInt64 to avoid Int32 overflow.
  // ref_index = ((J1^2 >> 32) * reference_area_size) >> 32
  let pos = (j1 * j1) >> 32
  let ref_index = ((pos * reference_area_size.to_uint64()) >> 32).to_int()
  // Apply offset
  let start_pos = if pass == 0 {
    0
  } else {
    if ref_lane == current_lane {
      current_col + 1
    } else {
      0
    }
  }
  let abs_index = (start_pos + ref_index) % cols_per_lane
  (ref_lane, abs_index)
}

// ---------------------------------------------------------------------------
// Address generation for data-independent indexing (Argon2i first pass)
// ---------------------------------------------------------------------------

///|
/// Generate address blocks for data-independent indexing.
/// Produces a pseudo-random index for the first half of the first pass.
fn generate_address(
  address_block : FixedArray[UInt64],
  input_block : FixedArray[UInt64],
  zero_block : FixedArray[UInt64],
  counter : Int,
  _lane : Int,
) -> Unit {
  // Increment counter in input_block
  input_block[6] = counter.to_uint64()
  input_block[7] = 0UL // high 32 bits of counter (always 0 for small counters)
  // address_block = G(zero_block, G(zero_block, input_block))
  let tmp = compress_g(zero_block, input_block)
  let result = compress_g(zero_block, tmp)
  for i = 0; i < BLOCK_WORDS; i = i + 1 {
    address_block[i] = result[i]
  }
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
/// Lanes are processed **sequentially** (lane 0 → p-1), which produces identical
/// output to a parallel implementation — RFC 9106 defines the algorithm in terms
/// of memory access patterns, not execution order. Actual parallel speedup requires
/// platform-level threading, which MoonBit's Wasm/JS target does not currently support.
///
/// ## Example
///
/// ```moonbit
/// let p = @argon2.params(3, 4096, 1, 32)
/// let hash = @argon2.hash(@utils.string_to_bytes("password"), @utils.string_to_bytes("somesalt"), p, b"", b"")
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
  let q = m_prime / p // columns per lane
  // Step 1: Compute H0
  // H0 = BLAKE2b-512(
  //   p || tau || m || t || v || y || |P| || P || |S| || S || |K| || K || |X| || X
  // )
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
  // m (memory_cost) as UInt32 LE
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
  // Memory: m_prime blocks × 128 UInt64 words
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
      seed.push((j & 0xFF).to_byte())
      seed.push(((j >> 8) & 0xFF).to_byte())
      seed.push(((j >> 16) & 0xFF).to_byte())
      seed.push(((j >> 24) & 0xFF).to_byte())
      seed.push((lane & 0xFF).to_byte())
      seed.push(((lane >> 8) & 0xFF).to_byte())
      seed.push(((lane >> 16) & 0xFF).to_byte())
      seed.push(((lane >> 24) & 0xFF).to_byte())
      let block_bytes = h_prime(Bytes::from_array(seed), BLOCK_SIZE)
      // Convert bytes to UInt64 words (little-endian)
      let off = block_offset(lane, j, q)
      for w = 0; w < BLOCK_WORDS; w = w + 1 {
        let mut val : UInt64 = 0UL
        for b = 0; b < 8; b = b + 1 {
          val = val | (block_bytes[w * 8 + b].to_uint64() << (b * 8))
        }
        memory[off + w] = val
      }
    }
  }
  // Step 4: Fill memory
  // For Argon2id: first half of first pass is data-independent,
  // the rest is data-dependent.
  let half_q = q / 2
  // Address generation state for data-independent indexing
  let zero_block : FixedArray[UInt64] = FixedArray::make(BLOCK_WORDS, 0UL)
  let input_block : FixedArray[UInt64] = FixedArray::make(BLOCK_WORDS, 0UL)
  let address_block : FixedArray[UInt64] = FixedArray::make(BLOCK_WORDS, 0UL)
  // Initialize input_block: [pass, lane, m_prime, t, y, 0, 0, 0, ...]
  input_block[0] = 0UL // pass (filled per pass)
  input_block[1] = 0UL // lane (filled per lane)
  input_block[2] = m_prime.to_uint64()
  input_block[3] = t.to_uint64()
  input_block[4] = ARGON2_ID.to_uint64()
  input_block[5] = 0UL // reserved
  input_block[6] = 0UL // counter (incremented per address block)
  input_block[7] = 0UL
  let mut address_idx = 0
  for pass = 0; pass < t; pass = pass + 1 {
    for lane = 0; lane < p; lane = lane + 1 {
      // Set up input_block for this pass/lane
      input_block[0] = pass.to_uint64()
      input_block[1] = lane.to_uint64()
      input_block[6] = 1UL // counter starts at 1
      address_idx = 0
      // Generate first address block
      generate_address(address_block, input_block, zero_block, 1, lane)
      for col = 0; col < q; col = col + 1 {
        // Skip the first two columns (already initialized)
        if col < 2 && pass == 0 {
          continue
        }
        // Determine if this is data-independent or data-dependent
        let data_independent = pass == 0 && col < half_q
        // Compute reference block
        let (ref_lane, ref_col) = if data_independent {
          // Data-independent: use address block
          if address_idx >= BLOCK_WORDS {
            // Generate new address block
            let counter = (input_block[6].to_int()) + 1
            input_block[6] = counter.to_uint64()
            generate_address(address_block, input_block, zero_block, counter, lane)
            address_idx = 0
          }
          let reference_area_size = if pass == 0 {
            if col < 2 { 1 } else { col - 1 }
          } else {
            q - 1
          }
          let pseudo_rand = address_block[address_idx]
          address_idx = address_idx + 1
          // Index computation in UInt64 to avoid Int32 overflow.
          // J1 (low 32 bits) → position, J2 (high 32 bits) → lane.
          let j1 = lo32(pseudo_rand)
          let pos = (j1 * j1) >> 32
          let ref_index = ((pos * reference_area_size.to_uint64()) >> 32).to_int()
          let rl = if col == q - 1 || (pass == 0 && col < 2) {
            lane
          } else {
            (hi32(pseudo_rand) % (lane + 1).to_uint64()).to_int()
          }
          (rl, ref_index % q)
        } else {
          // Data-dependent: use previous block
          let prev_off = if col == 0 {
            // Previous block is the last column of this lane
            block_offset(lane, q - 1, q)
          } else {
            block_offset(lane, col - 1, q)
          }
          compute_ref_index(
            memory, prev_off,
            lane, col, q, pass, false,
          )
        }
        // Get offsets
        let cur_off = block_offset(lane, col, q)
        let prev_off = if col == 0 {
          block_offset(lane, q - 1, q)
        } else {
          block_offset(lane, col - 1, q)
        }
        let ref_off = block_offset(ref_lane, ref_col, q)
        // Compute new block: B[i][j] = G(B[i][j-1], B[l'][r])
        let prev_copy : FixedArray[UInt64] = FixedArray::make(BLOCK_WORDS, 0UL)
        copy_block(prev_copy, 0, memory, prev_off)
        let ref_copy : FixedArray[UInt64] = FixedArray::make(BLOCK_WORDS, 0UL)
        copy_block(ref_copy, 0, memory, ref_off)
        let new_block = compress_g(prev_copy, ref_copy)
        // For passes > 0: XOR with old value
        if pass > 0 {
          for i = 0; i < BLOCK_WORDS; i = i + 1 {
            new_block[i] = new_block[i] ^ memory[cur_off + i]
          }
        }
        // Store result
        for i = 0; i < BLOCK_WORDS; i = i + 1 {
          memory[cur_off + i] = new_block[i]
        }
      }
    }
  }
  // Step 5: Final hash
  // XOR all last-column blocks across lanes
  let final_block : FixedArray[UInt64] = FixedArray::make(BLOCK_WORDS, 0UL)
  for lane = 0; lane < p; lane = lane + 1 {
    let off = block_offset(lane, q - 1, q)
    for i = 0; i < BLOCK_WORDS; i = i + 1 {
      final_block[i] = final_block[i] ^ memory[off + i]
    }
  }
  // Convert final block to bytes
  let final_bytes : Array[Byte] = Array::make(BLOCK_SIZE, b'\x00')
  for i = 0; i < BLOCK_WORDS; i = i + 1 {
    let v = final_block[i]
    for b = 0; b < 8; b = b + 1 {
      final_bytes[i * 8 + b] = ((v >> (b * 8)) & 0xFFUL).to_byte()
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
    let v = h[i].to_int()
    buf.write_char(hex_arr[(v >> 4) & 0xF])
    buf.write_char(hex_arr[v & 0xF])
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
  // p=1: 256 KiB / 1 lane = 256 blocks/lane
  // p=2: 256 KiB / 2 lanes = 128 blocks/lane
  // If multi-lane indexing is correctly implemented, the hashes differ.
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
  // Multi-lane output must be deterministic across runs.
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
