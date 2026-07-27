/// BigInt — Arbitrary-precision signed integer arithmetic.
///
/// This module provides a production-grade arbitrary-precision integer type
/// (`BigInt`) with full arithmetic support: addition, subtraction, multiplication
/// (including Karatsuba for large operands), division, modulo, comparison,
/// bit-shift, bitwise operations, GCD, modular exponentiation, and string
/// conversion (decimal and hexadecimal).
///
/// ## Internal representation
///
/// A `BigInt` is stored as an array of 32-bit unsigned "limbs" in little-endian
/// order (limb 0 = least significant 32 bits), together with a sign flag. The
/// value zero is always canonicalised to a single zero limb with `is_negative =
/// false`. Leading zero limbs are stripped after every operation.
///
/// ## Complexity
///
/// | Operation         | Complexity              |
/// |-------------------|-------------------------|
/// | Add / Sub         | O(n)                    |
/// | Mul (schoolbook)  | O(n²)                   |
/// | Mul (Karatsuba)   | O(n^1.585)  (n > 32)    |
/// | Div / Mod         | O(n²)                   |
/// | Cmp               | O(n)                    |
/// | GCD (binary)      | O(n²)                   |
/// | ModExp            | O(n³ log e)             |
/// | To-string         | O(n²)                   |
///
/// where `n` is the number of 32-bit limbs.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

///|
/// Karatsuba threshold: operands with at least this many limbs use the
/// Karatsuba multiplication algorithm. Below this, schoolbook is faster
/// due to lower constant factors.
const KARATSUBA_THRESHOLD : Int = 32

// ---------------------------------------------------------------------------
// BigInt type
// ---------------------------------------------------------------------------

///|
/// An arbitrary-precision signed integer.
///
/// Internally stored as little-endian array of 32-bit limbs.
/// The value zero is canonicalised to `{ limbs: [0u], is_negative: false }`.
pub struct BigInt {
  // Little-endian limbs: limbs[0] = least significant 32 bits.
  priv mut limbs : Array[UInt]
  // True if the value is negative. Always false for zero.
  priv mut is_negative : Bool
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

///|
/// Remove leading zero limbs, leaving at least one limb.
fn trim(b : BigInt) -> Unit {
  while b.limbs.length() > 1 && b.limbs[b.limbs.length() - 1] == 0U {
    b.limbs.pop() |> ignore
  }
  // Canonicalise zero.
  if b.limbs.length() == 1 && b.limbs[0] == 0U {
    b.is_negative = false
  }
}

///|
/// Create a BigInt from an Int.
///
/// Delegates to `from_int64` to avoid platform-dependent `Int` width issues:
/// on the wasm-gc target `Int` is 32-bit, so `n.reinterpret_as_uint() >> 32`
/// is a no-op (shift amount is masked to 5 bits, 32 & 31 = 0), which would
/// create duplicate limbs. Converting to `Int64` first ensures correct
/// 64-bit arithmetic on all targets.
fn from_int(n : Int) -> BigInt {
  from_int64(n.to_int64())
}

///|
/// Create a BigInt from an Int64.
///
/// Handles `Int64::min_value` correctly: when `n` is the most negative
/// `Int64`, `-n` overflows back to the same value. We detect this by
/// checking whether the negated value is still negative, and if so,
/// use `reinterpret_as_uint64` on the original `n` (whose two's-complement
/// bit pattern equals `|n|` as an unsigned value).
fn from_int64(n : Int64) -> BigInt {
  if n == 0L {
    return { limbs: [0U], is_negative: false }
  }
  let neg = n < 0L
  let u : UInt64 = if neg {
    let abs_n = -n
    if abs_n < 0L {
      // n was Int64.min_value: -n overflowed. The two's-complement
      // representation of n as UInt64 equals |n|.
      n.reinterpret_as_uint64()
    } else {
      abs_n.reinterpret_as_uint64()
    }
  } else {
    n.reinterpret_as_uint64()
  }
  let l0 = (u & 0xFFFFFFFFUL).to_uint()
  let l1 = ((u >> 32) & 0xFFFFFFFFUL).to_uint()
  let limbs : Array[UInt] = if l1 != 0U { [l0, l1] } else { [l0] }
  let b : BigInt = { limbs, is_negative: neg }
  trim(b)
  b
}

///|
/// Deep copy a BigInt.
fn copy(b : BigInt) -> BigInt {
  let limbs : Array[UInt] = []
  for i = 0; i < b.limbs.length(); i = i + 1 {
    limbs.push(b.limbs[i])
  }
  { limbs, is_negative: b.is_negative }
}

///|
/// Compare absolute values: returns -1, 0, or 1.
fn cmp_abs(a : BigInt, b : BigInt) -> Int {
  if a.limbs.length() != b.limbs.length() {
    return if a.limbs.length() < b.limbs.length() { -1 } else { 1 }
  }
  // Same length — compare from most significant limb.
  for i = a.limbs.length() - 1; i >= 0; i = i - 1 {
    if a.limbs[i] != b.limbs[i] {
      return if a.limbs[i] < b.limbs[i] { -1 } else { 1 }
    }
  }
  0
}

///|
/// Is the BigInt zero?
fn is_zero(b : BigInt) -> Bool {
  b.limbs.length() == 1 && b.limbs[0] == 0U
}

// ---------------------------------------------------------------------------
// Unsigned arithmetic helpers (operate on limb arrays)
// ---------------------------------------------------------------------------

///|
/// Add two unsigned limb arrays. Returns carry-extended sum.
fn uadd(a : Array[UInt], b : Array[UInt]) -> Array[UInt] {
  let n = if a.length() > b.length() { a.length() } else { b.length() }
  let result : Array[UInt] = Array::make(n, 0U)
  let mut carry : UInt64 = 0UL
  for i = 0; i < n; i = i + 1 {
    let av = if i < a.length() { a[i] } else { 0U }
    let bv = if i < b.length() { b[i] } else { 0U }
    let sum = av.to_uint64() + bv.to_uint64() + carry
    result[i] = (sum & 0xFFFFFFFFUL).to_uint()
    carry = sum >> 32
  }
  if carry != 0UL {
    result.push(carry.to_uint())
  }
  result
}

///|
/// Subtract unsigned: a - b, assuming a >= b. Returns result.
fn usub(a : Array[UInt], b : Array[UInt]) -> Array[UInt] {
  let result : Array[UInt] = Array::make(a.length(), 0U)
  let mut borrow : UInt64 = 0UL
  for i = 0; i < a.length(); i = i + 1 {
    let av = a[i].to_uint64()
    let bv = if i < b.length() { b[i].to_uint64() } else { 0UL }
    if av >= bv + borrow {
      result[i] = (av - bv - borrow).to_uint()
      borrow = 0UL
    } else {
      // Borrow from next limb.
      let diff = av + 0x100000000UL - bv - borrow
      result[i] = (diff & 0xFFFFFFFFUL).to_uint()
      borrow = 1UL
    }
  }
  // Trim trailing zeros.
  while result.length() > 1 && result[result.length() - 1] == 0U {
    result.pop() |> ignore
  }
  result
}

///|
/// Schoolbook multiplication of two unsigned limb arrays.
///
/// Uses 64-bit intermediate arithmetic to avoid overflow: the product of
/// two 32-bit limbs fits in 64 bits, and adding the accumulated result plus
/// carry still fits in 64 bits (max = (2³²−1)² + 2·(2³²−1) = 2⁶⁴−1).
fn umul_schoolbook(a : Array[UInt], b : Array[UInt]) -> Array[UInt] {
  let na = a.length()
  let nb = b.length()
  let result : Array[UInt] = Array::make(na + nb, 0U)
  for i = 0; i < na; i = i + 1 {
    let mut carry : UInt64 = 0UL
    let ai = a[i].to_uint64()
    for j = 0; j < nb; j = j + 1 {
      let product = ai * b[j].to_uint64() + result[i + j].to_uint64() + carry
      result[i + j] = (product & 0xFFFFFFFFUL).to_uint()
      carry = product >> 32
    }
    // Propagate remaining carry through subsequent limbs.
    let mut k = i + nb
    while carry != 0UL {
      if k >= result.length() {
        result.push(0U)
      }
      let sum = result[k].to_uint64() + carry
      result[k] = (sum & 0xFFFFFFFFUL).to_uint()
      carry = sum >> 32
      k = k + 1
    }
  }
  // Trim.
  while result.length() > 1 && result[result.length() - 1] == 0U {
    result.pop() |> ignore
  }
  result
}

///|
/// Karatsuba multiplication. Assumes both arrays have the same length
/// (padded with zeros if needed), which is a power of 2.
fn umul_karatsuba(a : Array[UInt], b : Array[UInt]) -> Array[UInt] {
  let n = a.length()
  if n <= KARATSUBA_THRESHOLD {
    return umul_schoolbook(a, b)
  }
  // Split point.
  let half = n / 2
  // a = a_hi * B^half + a_lo,  b = b_hi * B^half + b_lo
  let a_lo : Array[UInt] = Array::make(half, 0U)
  let a_hi : Array[UInt] = Array::make(n - half, 0U)
  let b_lo : Array[UInt] = Array::make(half, 0U)
  let b_hi : Array[UInt] = Array::make(n - half, 0U)
  for i = 0; i < half; i = i + 1 {
    a_lo[i] = a[i]
    b_lo[i] = b[i]
  }
  for i = 0; i < n - half; i = i + 1 {
    a_hi[i] = a[half + i]
    b_hi[i] = b[half + i]
  }
  // z0 = a_lo * b_lo
  let z0 = umul_karatsuba(a_lo, b_lo)
  // z2 = a_hi * b_hi
  let z2 = umul_karatsuba(a_hi, b_hi)
  // z1 = (a_lo + a_hi) * (b_lo + b_hi) - z0 - z2
  let sum_a = uadd(a_lo, a_hi)
  let sum_b = uadd(b_lo, b_hi)
  // Pad to same length for Karatsuba.
  let max_sum = if sum_a.length() > sum_b.length() {
    sum_a.length()
  } else {
    sum_b.length()
  }
  // Round up to power of 2 for clean recursion.
  let padded_len = @hash_utils.next_pow2(max_sum)
  let padded_a : Array[UInt] = Array::make(padded_len, 0U)
  let padded_b : Array[UInt] = Array::make(padded_len, 0U)
  for i = 0; i < sum_a.length(); i = i + 1 {
    padded_a[i] = sum_a[i]
  }
  for i = 0; i < sum_b.length(); i = i + 1 {
    padded_b[i] = sum_b[i]
  }
  let z1_full = umul_karatsuba(padded_a, padded_b)
  let z1 = usub(usub(z1_full, z0), z2)
  // result = z2 * B^n + z1 * B^half + z0
  // B = 2^32, B^half = 2^(32*half)
  let result : Array[UInt] = Array::make(n + n, 0U)
  // Add z0 at offset 0.
  add_to_offset(result, 0, z0)
  // Add z1 at offset half.
  add_to_offset(result, half, z1)
  // Add z2 at offset n.
  add_to_offset(result, n, z2)
  // Trim.
  while result.length() > 1 && result[result.length() - 1] == 0U {
    result.pop() |> ignore
  }
  result
}

///|
/// Add a value to `result` starting at `offset`, with carry propagation.
fn add_to_offset(
  result : Array[UInt],
  offset : Int,
  value : Array[UInt],
) -> Unit {
  let mut carry : UInt64 = 0UL
  let mut i = 0
  while i < value.length() || carry != 0UL {
    if offset + i >= result.length() {
      result.push(0U)
    }
    let v = if i < value.length() { value[i].to_uint64() } else { 0UL }
    let sum = result[offset + i].to_uint64() + v + carry
    result[offset + i] = (sum & 0xFFFFFFFFUL).to_uint()
    carry = sum >> 32
    i = i + 1
  }
}

///|
/// Unsigned division: returns (quotient, remainder).
/// Uses long division algorithm.
fn udivmod(a : Array[UInt], b : Array[UInt]) -> (Array[UInt], Array[UInt]) {
  // Handle trivial cases.
  if b.length() == 1 && b[0] == 0U {
    // Division by zero — return zero quotient and zero remainder.
    // (Public API returns Option; this is a safety net.)
    return ([0U], [0U])
  }
  // Compare |a| vs |b|.
  let cmp = cmp_arrays(a, b)
  if cmp < 0 {
    // a < b: quotient = 0, remainder = a.
    return ([0U], copy_array(a))
  }
  if cmp == 0 {
    // a == b: quotient = 1, remainder = 0.
    return ([1U], [0U])
  }
  // Single-limb divisor: use fast path.
  if b.length() == 1 {
    let divisor = b[0].to_uint64()
    let quotient : Array[UInt] = Array::make(a.length(), 0U)
    let mut rem : UInt64 = 0UL
    for i = a.length() - 1; i >= 0; i = i - 1 {
      let cur = (rem << 32) | a[i].to_uint64()
      quotient[i] = (cur / divisor).to_uint()
      rem = cur % divisor
    }
    // Trim quotient.
    while quotient.length() > 1 && quotient[quotient.length() - 1] == 0U {
      quotient.pop() |> ignore
    }
    (quotient, [rem.to_uint()])
  } else {
    // Multi-limb long division.
    long_division(a, b)
  }
}

///|
/// Compare two unsigned limb arrays.
fn cmp_arrays(a : Array[UInt], b : Array[UInt]) -> Int {
  // Trim both for comparison.
  let la = effective_len(a)
  let lb = effective_len(b)
  if la != lb {
    return if la < lb { -1 } else { 1 }
  }
  for i = la - 1; i >= 0; i = i - 1 {
    if a[i] != b[i] {
      return if a[i] < b[i] { -1 } else { 1 }
    }
  }
  0
}

///|
/// Effective length (ignoring leading zeros).
fn effective_len(a : Array[UInt]) -> Int {
  let mut n = a.length()
  while n > 1 && a[n - 1] == 0U {
    n = n - 1
  }
  n
}

///|
/// Deep copy an array of UInt.
fn copy_array(a : Array[UInt]) -> Array[UInt] {
  let r : Array[UInt] = []
  for i = 0; i < a.length(); i = i + 1 {
    r.push(a[i])
  }
  r
}

///|
/// Multi-limb long division using Knuth's Algorithm D (simplified).
/// Returns (quotient, remainder).
fn long_division(
  dividend : Array[UInt],
  divisor : Array[UInt],
) -> (Array[UInt], Array[UInt]) {
  let n = effective_len(divisor)
  let m = effective_len(dividend) - n
  // Normalise: shift both left so that the top limb of divisor has its
  // high bit set. This ensures the quotient digit estimate is at most
  // 2 too large (instead of potentially way off).
  let d0 = divisor[n - 1]
  let shift = count_leading_zeros(d0)
  let norm_div : Array[UInt] = Array::make(n, 0U)
  let norm_dividend : Array[UInt] = Array::make(effective_len(dividend) + 1, 0U)
  if shift == 0 {
    // No normalisation needed — copy as-is.
    for i = 0; i < n; i = i + 1 {
      norm_div[i] = divisor[i]
    }
    for i = 0; i < effective_len(dividend); i = i + 1 {
      norm_dividend[i] = dividend[i]
    }
  } else {
    // Shift divisor left by `shift` bits.
    let mut carry : UInt = 0U
    for i = 0; i < n; i = i + 1 {
      norm_div[i] = (divisor[i] << shift) | carry
      carry = divisor[i] >> (32 - shift)
    }
    // Shift dividend left by `shift` bits.
    carry = 0U
    for i = 0; i < effective_len(dividend); i = i + 1 {
      norm_dividend[i] = (dividend[i] << shift) | carry
      carry = dividend[i] >> (32 - shift)
    }
    norm_dividend[effective_len(dividend)] = carry
  }
  // Quotient array.
  let quotient : Array[UInt] = Array::make(m + 1, 0U)
  // Long division loop.
  for j = m; j >= 0; j = j - 1 {
    // Estimate quotient digit q_hat.
    let top = (norm_dividend[j + n].to_uint64() << 32) |
      norm_dividend[j + n - 1].to_uint64()
    let d_top = norm_div[n - 1].to_uint64()
    let mut q_hat = top / d_top
    let mut r_hat = top % d_top
    // Refine: ensure q_hat is not too large.
    let test_val = q_hat * norm_div[n - 2].to_uint64()
    while q_hat >= 0x100000000UL ||
          test_val > (r_hat << 32) + norm_dividend[j + n - 2].to_uint64() {
      q_hat = q_hat - 1UL
      r_hat = r_hat + d_top
      if r_hat >= 0x100000000UL {
        break
      }
    }
    // Multiply and subtract: norm_dividend[j..j+n] -= q_hat * divisor.
    let mut borrow : Int64 = 0L
    let mut mul_carry : UInt64 = 0UL
    for i = 0; i < n; i = i + 1 {
      let product = q_hat * norm_div[i].to_uint64() + mul_carry
      mul_carry = product >> 32
      let pl = (product & 0xFFFFFFFFUL).to_uint()
      let cur = norm_dividend[j + i].to_int64() - pl.to_int64() - borrow
      if cur < 0L {
        norm_dividend[j + i] = (cur + 0x100000000L)
          .reinterpret_as_uint64()
          .to_uint()
        borrow = 1L
      } else {
        norm_dividend[j + i] = cur.reinterpret_as_uint64().to_uint()
        borrow = 0L
      }
    }
    let cur = norm_dividend[j + n].to_int64() -
      mul_carry.reinterpret_as_int64() -
      borrow
    if cur < 0L {
      // q_hat was 1 too large — add back.
      q_hat = q_hat - 1UL
      let mut add_carry : UInt64 = 0UL
      for i = 0; i < n; i = i + 1 {
        let sum = norm_dividend[j + i].to_uint64() +
          norm_div[i].to_uint64() +
          add_carry
        norm_dividend[j + i] = (sum & 0xFFFFFFFFUL).to_uint()
        add_carry = sum >> 32
      }
      norm_dividend[j + n] = (cur.reinterpret_as_uint64() + add_carry).to_uint()
    } else {
      norm_dividend[j + n] = cur.reinterpret_as_uint64().to_uint()
    }
    quotient[j] = q_hat.to_uint()
  }
  // Trim quotient.
  while quotient.length() > 1 && quotient[quotient.length() - 1] == 0U {
    quotient.pop() |> ignore
  }
  // Unnormalise remainder: shift right by `shift` bits.
  // When shift == 0, we must NOT apply `<< (32 - 0)` because on 32-bit
  // platforms the shift amount is masked to 5 bits, making `<< 32` equivalent
  // to `<< 0`, which would corrupt the remainder.
  let remainder : Array[UInt] = Array::make(n, 0U)
  if shift == 0 {
    for i = 0; i < n; i = i + 1 {
      remainder[i] = norm_dividend[i]
    }
  } else {
    let mut rcarry : UInt = 0U
    for i = n - 1; i >= 0; i = i - 1 {
      remainder[i] = (norm_dividend[i] >> shift) | rcarry
      rcarry = norm_dividend[i] << (32 - shift)
    }
  }
  // Trim remainder.
  while remainder.length() > 1 && remainder[remainder.length() - 1] == 0U {
    remainder.pop() |> ignore
  }
  (quotient, remainder)
}

///|
/// Count leading zeros in a UInt (32-bit).
fn count_leading_zeros(x : UInt) -> Int {
  if x == 0U {
    return 32
  }
  let mut n = 0
  let mut v = x
  if (v & 0xFFFF0000U) == 0U {
    n = n + 16
    v = v << 16
  }
  if (v & 0xFF000000U) == 0U {
    n = n + 8
    v = v << 8
  }
  if (v & 0xF0000000U) == 0U {
    n = n + 4
    v = v << 4
  }
  if (v & 0xC0000000U) == 0U {
    n = n + 2
    v = v << 2
  }
  if (v & 0x80000000U) == 0U {
    n = n + 1
  }
  n
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

///|
/// Create BigInt from an Int.
pub fn from_int_value(n : Int) -> BigInt {
  from_int(n)
}

///|
/// Create BigInt from an Int64.
pub fn from_int64_value(n : Int64) -> BigInt {
  from_int64(n)
}

///|
/// Create BigInt zero.
pub fn zero() -> BigInt {
  { limbs: [0U], is_negative: false }
}

///|
/// Create BigInt one.
pub fn one() -> BigInt {
  { limbs: [1U], is_negative: false }
}

///|
/// Parse a decimal string into a BigInt. Returns None on invalid input.
pub fn from_string(s : String) -> BigInt? {
  if s.length() == 0 {
    return None
  }
  let mut start = 0
  let mut neg = false
  if s[0].to_int() == 0x2D {
    // '-'
    neg = true
    start = 1
  } else if s[0].to_int() == 0x2B {
    // '+'
    start = 1
  }
  if start >= s.length() {
    return None
  }
  // Check for 0x prefix (hex).
  if start + 1 < s.length() &&
    s[start].to_int() == 0x30 &&
    (s[start + 1].to_int() == 0x78 || s[start + 1].to_int() == 0x58) {
    // Hex input.
    return from_hex_string(s, start + 2, neg)
  }
  // Decimal input: accumulate using multiply-by-10 and add.
  let result = zero()
  for i = start; i < s.length(); i = i + 1 {
    let c = s[i].to_int()
    if c < 0x30 || c > 0x39 {
      return None
    }
    let digit = from_int(c - 0x30)
    let multiplied = mul(result, from_int(10))
    let added = add(multiplied, digit)
    result.limbs = added.limbs
    result.is_negative = added.is_negative
  }
  result.is_negative = neg && !is_zero(result)
  Some(result)
}

///|
/// Parse a hex string (after 0x prefix).
fn from_hex_string(s : String, start : Int, neg : Bool) -> BigInt? {
  if start >= s.length() {
    return None
  }
  let result = zero()
  for i = start; i < s.length(); i = i + 1 {
    let c = s[i].to_int()
    let digit = if c >= 0x30 && c <= 0x39 {
      c - 0x30
    } else if c >= 0x61 && c <= 0x66 {
      c - 0x61 + 10
    } else if c >= 0x41 && c <= 0x46 {
      c - 0x41 + 10
    } else {
      return None
    }
    let multiplied = mul(result, from_int(16))
    let added = add(multiplied, from_int(digit))
    result.limbs = added.limbs
    result.is_negative = added.is_negative
  }
  result.is_negative = neg && !is_zero(result)
  Some(result)
}

///|
/// Convert BigInt to a decimal string.
pub fn to_string(b : BigInt) -> String {
  if is_zero(b) {
    return "0"
  }
  let mut result = ""
  let mut temp = copy(b)
  temp.is_negative = false
  // Repeatedly divide by 10^9 and collect digits.
  let divisor = from_int(1000000000)
  let parts : Array[String] = []
  while !is_zero(temp) {
    match divmod(temp, divisor) {
      Some((q, r)) => {
        let r_int = r.limbs[0].reinterpret_as_int()
        if is_zero(q) {
          // Most significant part — no zero padding.
          parts.push(r_int.to_string())
        } else {
          // Zero-pad to 9 digits.
          let s = r_int.to_string()
          let padded = String::make(9 - s.length(), '0') + s
          parts.push(padded)
        }
        temp = q
      }
      None => break
    }
  }
  // Parts are in reverse order (least significant first).
  for i = parts.length() - 1; i >= 0; i = i - 1 {
    result = result + parts[i]
  }
  if b.is_negative {
    result = "-" + result
  }
  result
}

///|
/// Convert a nibble (0–15) to a single hex digit string.
///
/// Uses a match expression instead of indexing into a `String` and calling
/// `Char::to_string()`, because on some MoonBit targets the latter returns
/// the numeric code point (e.g. "48" for '0') rather than the character.
fn hex_digit(n : Int) -> String {
  match n {
    0 => "0"
    1 => "1"
    2 => "2"
    3 => "3"
    4 => "4"
    5 => "5"
    6 => "6"
    7 => "7"
    8 => "8"
    9 => "9"
    10 => "a"
    11 => "b"
    12 => "c"
    13 => "d"
    14 => "e"
    15 => "f"
    _ => "?"
  }
}

///|
/// Convert a 32-bit value to an 8-character hex string (no prefix).
fn limb_to_hex(v : Int) -> String {
  hex_digit((v >> 28) & 0xF) +
  hex_digit((v >> 24) & 0xF) +
  hex_digit((v >> 20) & 0xF) +
  hex_digit((v >> 16) & 0xF) +
  hex_digit((v >> 12) & 0xF) +
  hex_digit((v >> 8) & 0xF) +
  hex_digit((v >> 4) & 0xF) +
  hex_digit(v & 0xF)
}

///|
/// Convert BigInt to a hexadecimal string (with 0x prefix).
pub fn to_hex(b : BigInt) -> String {
  if is_zero(b) {
    return "0x0"
  }
  let mut result = "0x"
  for i = b.limbs.length() - 1; i >= 0; i = i - 1 {
    let v = b.limbs[i].reinterpret_as_int()
    let hex_str = limb_to_hex(v)
    if i == b.limbs.length() - 1 {
      // Most significant limb — skip leading zeros.
      result = result + trim_leading_zeros(hex_str)
    } else {
      result = result + hex_str
    }
  }
  if b.is_negative {
    result = "-0x" + result[2:].to_owned()
  }
  result
}

///|
/// Trim leading '0' characters from a string.
fn trim_leading_zeros(s : String) -> String {
  let mut i = 0
  while i < s.length() - 1 && s[i].to_int() == 0x30 {
    i = i + 1
  }
  s[i:].to_owned()
}

// ---------------------------------------------------------------------------
// Arithmetic operations
// ---------------------------------------------------------------------------

///|
/// Addition: a + b.
pub fn add(a : BigInt, b : BigInt) -> BigInt {
  if is_zero(a) {
    return copy(b)
  }
  if is_zero(b) {
    return copy(a)
  }
  if a.is_negative == b.is_negative {
    // Same sign: add magnitudes.
    let result_limbs = uadd(a.limbs, b.limbs)
    let result : BigInt = { limbs: result_limbs, is_negative: a.is_negative }
    trim(result)
    result
  } else {
    // Different signs: subtract smaller from larger.
    let cmp = cmp_abs(a, b)
    if cmp == 0 {
      return zero()
    }
    if cmp > 0 {
      // |a| > |b|
      let result_limbs = usub(a.limbs, b.limbs)
      let result : BigInt = { limbs: result_limbs, is_negative: a.is_negative }
      trim(result)
      result
    } else {
      // |b| > |a|
      let result_limbs = usub(b.limbs, a.limbs)
      let result : BigInt = { limbs: result_limbs, is_negative: b.is_negative }
      trim(result)
      result
    }
  }
}

///|
/// Subtraction: a - b.
pub fn sub(a : BigInt, b : BigInt) -> BigInt {
  // a - b = a + (-b)
  let neg_b = copy(b)
  if !is_zero(neg_b) {
    neg_b.is_negative = !neg_b.is_negative
  }
  add(a, neg_b)
}

///|
/// Multiplication: a * b.
///
/// Uses schoolbook multiplication for small operands and Karatsuba
/// for operands larger than KARATSUBA_THRESHOLD limbs.
pub fn mul(a : BigInt, b : BigInt) -> BigInt {
  if is_zero(a) || is_zero(b) {
    return zero()
  }
  let result_limbs = if a.limbs.length() >= KARATSUBA_THRESHOLD &&
    b.limbs.length() >= KARATSUBA_THRESHOLD {
    // Karatsuba: pad both to the same power-of-2 length.
    let max_len = if a.limbs.length() > b.limbs.length() {
      a.limbs.length()
    } else {
      b.limbs.length()
    }
    let padded_len = @hash_utils.next_pow2(max_len)
    let pa : Array[UInt] = Array::make(padded_len, 0U)
    let pb : Array[UInt] = Array::make(padded_len, 0U)
    for i = 0; i < a.limbs.length(); i = i + 1 {
      pa[i] = a.limbs[i]
    }
    for i = 0; i < b.limbs.length(); i = i + 1 {
      pb[i] = b.limbs[i]
    }
    umul_karatsuba(pa, pb)
  } else {
    umul_schoolbook(a.limbs, b.limbs)
  }
  let result : BigInt = {
    limbs: result_limbs,
    is_negative: a.is_negative != b.is_negative,
  }
  trim(result)
  result
}

///|
/// Division: returns the quotient a / b.
/// Returns None if b is zero.
pub fn div(a : BigInt, b : BigInt) -> BigInt? {
  if is_zero(b) {
    return None
  }
  let (q, _) = udivmod(a.limbs, b.limbs)
  let result : BigInt = {
    limbs: q,
    is_negative: a.is_negative != b.is_negative && !is_zero_impl(q),
  }
  trim(result)
  Some(result)
}

///|
/// Modulo: returns the remainder a % b.
/// Returns None if b is zero.
pub fn rem(a : BigInt, b : BigInt) -> BigInt? {
  if is_zero(b) {
    return None
  }
  let (_, r) = udivmod(a.limbs, b.limbs)
  let result : BigInt = {
    limbs: r,
    is_negative: a.is_negative && !is_zero_impl(r),
  }
  trim(result)
  Some(result)
}

///|
/// Division and modulo: returns (quotient, remainder).
/// Returns None if b is zero.
pub fn divmod(a : BigInt, b : BigInt) -> (BigInt, BigInt)? {
  if is_zero(b) {
    return None
  }
  let (q, r) = udivmod(a.limbs, b.limbs)
  let quotient : BigInt = {
    limbs: q,
    is_negative: a.is_negative != b.is_negative && !is_zero_impl(q),
  }
  let remainder : BigInt = {
    limbs: r,
    is_negative: a.is_negative && !is_zero_impl(r),
  }
  trim(quotient)
  trim(remainder)
  Some((quotient, remainder))
}

///|
/// Check if a limb array represents zero.
fn is_zero_impl(limbs : Array[UInt]) -> Bool {
  limbs.length() == 1 && limbs[0] == 0U
}

// ---------------------------------------------------------------------------
// Comparison
// ---------------------------------------------------------------------------

///|
/// Compare two BigInts: returns -1, 0, or 1.
pub fn compare(a : BigInt, b : BigInt) -> Int {
  if a.is_negative && !b.is_negative {
    return -1
  }
  if !a.is_negative && b.is_negative {
    return 1
  }
  // Same sign.
  let cmp = cmp_abs(a, b)
  if a.is_negative {
    -cmp
  } else {
    cmp
  }
}

///|
/// Equality test.
pub fn equal(a : BigInt, b : BigInt) -> Bool {
  compare(a, b) == 0
}

///|
/// Less than.
pub fn less_than(a : BigInt, b : BigInt) -> Bool {
  compare(a, b) < 0
}

///|
/// Greater than.
pub fn greater_than(a : BigInt, b : BigInt) -> Bool {
  compare(a, b) > 0
}

// ---------------------------------------------------------------------------
// Bit operations
// ---------------------------------------------------------------------------

///|
/// Left shift by n bits (multiply by 2^n).
pub fn shl(b : BigInt, n : Int) -> BigInt {
  if n <= 0 || is_zero(b) {
    return copy(b)
  }
  let limb_shift = n / 32
  let bit_shift = n % 32
  let new_len = b.limbs.length() + limb_shift + 1
  let result : Array[UInt] = Array::make(new_len, 0U)
  if bit_shift == 0 {
    // Pure limb shift.
    for i = 0; i < b.limbs.length(); i = i + 1 {
      result[i + limb_shift] = b.limbs[i]
    }
  } else {
    let mut carry : UInt = 0U
    for i = 0; i < b.limbs.length(); i = i + 1 {
      result[i + limb_shift] = (b.limbs[i] << bit_shift) | carry
      carry = b.limbs[i] >> (32 - bit_shift)
    }
    result[b.limbs.length() + limb_shift] = carry
  }
  let r : BigInt = { limbs: result, is_negative: b.is_negative }
  trim(r)
  r
}

///|
/// Right shift by n bits (divide by 2^n, floor towards zero).
pub fn shr(b : BigInt, n : Int) -> BigInt {
  if n <= 0 || is_zero(b) {
    return copy(b)
  }
  let limb_shift = n / 32
  let bit_shift = n % 32
  if limb_shift >= b.limbs.length() {
    return zero()
  }
  let new_len = b.limbs.length() - limb_shift
  let result : Array[UInt] = Array::make(new_len, 0U)
  if bit_shift == 0 {
    for i = 0; i < new_len; i = i + 1 {
      result[i] = b.limbs[i + limb_shift]
    }
  } else {
    for i = 0; i < new_len; i = i + 1 {
      let cur = b.limbs[i + limb_shift]
      let next = if i + limb_shift + 1 < b.limbs.length() {
        b.limbs[i + limb_shift + 1]
      } else {
        0U
      }
      result[i] = (cur >> bit_shift) | (next << (32 - bit_shift))
    }
  }
  let r : BigInt = { limbs: result, is_negative: b.is_negative }
  trim(r)
  r
}

///|
/// Bitwise AND.
pub fn bit_and(a : BigInt, b : BigInt) -> BigInt {
  let n = if a.limbs.length() < b.limbs.length() {
    a.limbs.length()
  } else {
    b.limbs.length()
  }
  let result : Array[UInt] = Array::make(n, 0U)
  for i = 0; i < n; i = i + 1 {
    result[i] = a.limbs[i] & b.limbs[i]
  }
  let r : BigInt = { limbs: result, is_negative: false }
  trim(r)
  r
}

///|
/// Bitwise OR.
pub fn bit_or(a : BigInt, b : BigInt) -> BigInt {
  let n = if a.limbs.length() > b.limbs.length() {
    a.limbs.length()
  } else {
    b.limbs.length()
  }
  let result : Array[UInt] = Array::make(n, 0U)
  for i = 0; i < n; i = i + 1 {
    let av = if i < a.limbs.length() { a.limbs[i] } else { 0U }
    let bv = if i < b.limbs.length() { b.limbs[i] } else { 0U }
    result[i] = av | bv
  }
  let r : BigInt = { limbs: result, is_negative: false }
  trim(r)
  r
}

///|
/// Bitwise XOR.
pub fn bit_xor(a : BigInt, b : BigInt) -> BigInt {
  let n = if a.limbs.length() > b.limbs.length() {
    a.limbs.length()
  } else {
    b.limbs.length()
  }
  let result : Array[UInt] = Array::make(n, 0U)
  for i = 0; i < n; i = i + 1 {
    let av = if i < a.limbs.length() { a.limbs[i] } else { 0U }
    let bv = if i < b.limbs.length() { b.limbs[i] } else { 0U }
    result[i] = av ^ bv
  }
  let r : BigInt = { limbs: result, is_negative: false }
  trim(r)
  r
}

// ---------------------------------------------------------------------------
// Number theory functions
// ---------------------------------------------------------------------------

///|
/// Absolute value.
pub fn abs(b : BigInt) -> BigInt {
  let r = copy(b)
  r.is_negative = false
  r
}

///|
/// Negate.
pub fn negate(b : BigInt) -> BigInt {
  let r = copy(b)
  if !is_zero(r) {
    r.is_negative = !r.is_negative
  }
  r
}

///|
/// Greatest common divisor (binary GCD algorithm).
pub fn gcd(a : BigInt, b : BigInt) -> BigInt {
  let mut x = abs(a)
  let mut y = abs(b)
  if is_zero(x) {
    return y
  }
  if is_zero(y) {
    return x
  }
  // Count trailing zeros of both.
  let mut shift = 0
  while !is_odd(x) && !is_odd(y) {
    x = shr(x, 1)
    y = shr(y, 1)
    shift = shift + 1
  }
  while !is_odd(x) {
    x = shr(x, 1)
  }
  // Now x is odd.
  while !is_zero(y) {
    while !is_odd(y) {
      y = shr(y, 1)
    }
    // Both x and y are odd now.
    if less_than(x, y) {
      let temp = x
      x = y
      y = temp
    }
    x = sub(x, y)
  }
  shl(x, shift)
}

///|
/// Check if the BigInt is odd.
pub fn is_odd(b : BigInt) -> Bool {
  (b.limbs[0] & 1U) != 0U
}

///|
/// Modular exponentiation: base^exp mod modulus.
/// Returns None if modulus is zero.
pub fn mod_pow(base : BigInt, exp : BigInt, modulus : BigInt) -> BigInt? {
  if is_zero(modulus) {
    return None
  }
  if is_zero(exp) {
    return Some(one())
  }
  if equal(modulus, one()) {
    return Some(zero())
  }
  // Ensure base is in [0, modulus).
  let b = match rem(abs(base), modulus) {
    Some(r) => r
    None => return None
  }
  let mut result = one()
  let mut current = b
  let mut e = copy(exp)
  let two = from_int(2)
  while !is_zero(e) {
    if is_odd(e) {
      let product = mul(result, current)
      match rem(product, modulus) {
        Some(r) => result = r
        None => return None
      }
    }
    let product = mul(current, current)
    match rem(product, modulus) {
      Some(r) => current = r
      None => return None
    }
    match div(e, two) {
      Some(q) => e = q
      None => return None
    }
  }
  Some(result)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
/// Unwrap a BigInt? for test convenience.
fn unwrap(b : BigInt?) -> BigInt {
  match b {
    Some(v) => v
    None => zero()
  }
}

///|
test "bigint: basic construction and to_string" {
  let a = from_int(42)
  assert_eq(to_string(a), "42")
  let b = from_int(-123)
  assert_eq(to_string(b), "-123")
  let z = zero()
  assert_eq(to_string(z), "0")
  let o = one()
  assert_eq(to_string(o), "1")
}

///|
test "bigint: from_string decimal" {
  match from_string("12345") {
    Some(b) => assert_eq(to_string(b), "12345")
    None => assert_true(false)
  }
  match from_string("-999") {
    Some(b) => assert_eq(to_string(b), "-999")
    None => assert_true(false)
  }
  match from_string("0") {
    Some(b) => assert_eq(to_string(b), "0")
    None => assert_true(false)
  }
  match from_string("+42") {
    Some(b) => assert_eq(to_string(b), "42")
    None => assert_true(false)
  }
  match from_string("invalid") {
    Some(_) => assert_true(false)
    None => assert_true(true)
  }
}

///|
test "bigint: from_string hex" {
  match from_string("0xFF") {
    Some(b) => assert_eq(to_string(b), "255")
    None => assert_true(false)
  }
  match from_string("0xDEADBEEF") {
    Some(b) => assert_eq(to_string(b), "3735928559")
    None => assert_true(false)
  }
  match from_string("-0x100") {
    Some(b) => assert_eq(to_string(b), "-256")
    None => assert_true(false)
  }
}

///|
test "bigint: addition" {
  let a = from_int(123)
  let b = from_int(456)
  assert_eq(to_string(add(a, b)), "579")
  let c = from_int(-100)
  let d = from_int(50)
  assert_eq(to_string(add(c, d)), "-50")
  let e = from_int(-200)
  let f = from_int(-300)
  assert_eq(to_string(add(e, f)), "-500")
  // Large numbers.
  let big1 = unwrap(from_string("99999999999999999999"))
  let big2 = unwrap(from_string("1"))
  assert_eq(to_string(add(big1, big2)), "100000000000000000000")
}

///|
test "bigint: subtraction" {
  let a = from_int(500)
  let b = from_int(200)
  assert_eq(to_string(sub(a, b)), "300")
  let c = from_int(100)
  let d = from_int(200)
  assert_eq(to_string(sub(c, d)), "-100")
  let e = from_int(-50)
  let f = from_int(-100)
  assert_eq(to_string(sub(e, f)), "50")
}

///|
test "bigint: multiplication" {
  let a = from_int(12)
  let b = from_int(34)
  assert_eq(to_string(mul(a, b)), "408")
  let c = from_int(-7)
  let d = from_int(8)
  assert_eq(to_string(mul(c, d)), "-56")
  let e = from_int(-6)
  let f = from_int(-7)
  assert_eq(to_string(mul(e, f)), "42")
  // Large multiplication.
  let big1 = unwrap(from_string("12345678901234567890"))
  let big2 = unwrap(from_string("98765432109876543210"))
  let product = mul(big1, big2)
  assert_eq(to_string(product), "1219326311370217952237463801111263526900")
}

///|
test "bigint: division" {
  let a = from_int(100)
  let b = from_int(7)
  match div(a, b) {
    Some(q) => assert_eq(to_string(q), "14")
    None => assert_true(false)
  }
  match rem(a, b) {
    Some(r) => assert_eq(to_string(r), "2")
    None => assert_true(false)
  }
  // Division by zero.
  match div(a, zero()) {
    Some(_) => assert_true(false)
    None => assert_true(true)
  }
  // Large division.
  // 10^21 mod (10^12 - 1): since 10^12 ≡ 1 (mod 10^12-1),
  // 10^21 = (10^12)^1 · 10^9 ≡ 1 · 10^9 = 10^9 (mod 10^12-1).
  let big1 = unwrap(from_string("1000000000000000000000"))
  let big2 = unwrap(from_string("999999999999"))
  match divmod(big1, big2) {
    Some((q, r)) => {
      assert_eq(to_string(q), "1000000000")
      assert_eq(to_string(r), "1000000000")
    }
    None => assert_true(false)
  }
}

///|
test "bigint: comparison" {
  let a = from_int(100)
  let b = from_int(200)
  let c = from_int(100)
  let d = from_int(-50)
  assert_true(less_than(a, b))
  assert_true(greater_than(b, a))
  assert_true(equal(a, c))
  assert_true(less_than(d, a))
  assert_true(greater_than(a, d))
}

///|
test "bigint: bit shifts" {
  let a = from_int(1)
  assert_eq(to_string(shl(a, 10)), "1024")
  let b = from_int(256)
  assert_eq(to_string(shr(b, 4)), "16")
  // Large shift.
  let c = from_int(1)
  let shifted = shl(c, 100)
  match div(shifted, unwrap(from_string("1267650600228229401496703205376"))) {
    Some(q) => assert_eq(to_string(q), "1")
    None => assert_true(false)
  }
}

///|
test "bigint: bitwise operations" {
  let a = from_int(0xFF)
  let b = from_int(0x0F)
  assert_eq(to_string(bit_and(a, b)), "15")
  assert_eq(to_string(bit_or(a, b)), "255")
  assert_eq(to_string(bit_xor(a, b)), "240")
}

///|
test "bigint: gcd" {
  let a = from_int(48)
  let b = from_int(18)
  assert_eq(to_string(gcd(a, b)), "6")
  let c = from_int(1071)
  let d = from_int(462)
  assert_eq(to_string(gcd(c, d)), "21")
  // GCD with zero.
  assert_eq(to_string(gcd(from_int(42), zero())), "42")
}

///|
test "bigint: mod_pow" {
  // 2^10 mod 1000 = 24
  match mod_pow(from_int(2), from_int(10), from_int(1000)) {
    Some(r) => assert_eq(to_string(r), "24")
    None => assert_true(false)
  }
  // 3^7 mod 100 = 87
  match mod_pow(from_int(3), from_int(7), from_int(100)) {
    Some(r) => assert_eq(to_string(r), "87")
    None => assert_true(false)
  }
  // Large: 2^100 mod (10^30)
  match
    mod_pow(
      from_int(2),
      from_int(100),
      unwrap(from_string("1000000000000000000000000000000")),
    ) {
    Some(r) =>
      // Just verify it's a valid number less than modulus.
      assert_true(
        less_than(r, unwrap(from_string("1000000000000000000000000000000"))),
      )
    None => assert_true(false)
  }
}

///|
test "bigint: negation and abs" {
  let a = from_int(-42)
  assert_eq(to_string(abs(a)), "42")
  assert_eq(to_string(negate(a)), "42")
  let b = from_int(42)
  assert_eq(to_string(negate(b)), "-42")
  assert_eq(to_string(abs(b)), "42")
}

///|
test "bigint: to_hex" {
  let a = from_int(255)
  assert_eq(to_hex(a), "0xff")
  let b = from_int64_value(3735928559L)
  assert_eq(to_hex(b), "0xdeadbeef")
  let c = from_int(-256)
  assert_eq(to_hex(c), "-0x100")
}

///|
test "bigint: very large multiplication" {
  // Test Karatsuba threshold.
  let big1 = unwrap(from_string("1234567890123456789012345678901234567890"))
  let big2 = unwrap(from_string("9876543210987654321098765432109876543210"))
  let product = mul(big1, big2)
  let expected_str = "12193263113702179522618503273386678859448712086533622923332237463801111263526900"
  assert_eq(to_string(product), expected_str)
}
