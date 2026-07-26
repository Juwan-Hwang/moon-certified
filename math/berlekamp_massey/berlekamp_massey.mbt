/// Berlekamp-Massey algorithm for finding the shortest linear recurrence.
///
/// Given a sequence `a[0], a[1], ..., a[n-1]` over GF(p) (integers mod a prime
/// `p`), the Berlekamp-Massey algorithm finds the shortest linear recurrence
/// relation of the form:
///
/// `a[i] = c[0]*a[i-1] + c[1]*a[i-2] + ... + c[L-1]*a[i-L]`
///
/// for all `i >= L`, where `L` is the **recurrence length**. The algorithm
/// runs in O(n^2) time.
///
/// ## Applications
///
/// - Finding recurrence relations in sequences
/// - Solving linear recurrence problems (e.g. computing the n-th term of a
///   linear recurrence in O(L^2 log n) after finding the recurrence)
/// - Error-correcting codes (BCH codes, Reed-Solomon decoding)
/// - Cryptanalysis of LFSR-based stream ciphers
///
/// ## Modular arithmetic
///
/// All arithmetic is performed modulo a prime `p` (typically 998244353 or
/// 1e9+7). Multiplication uses Int64 to avoid overflow, consistent with the
/// rolling hash implementation.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

///|
/// Default prime modulus: 998244353 (commonly used in competitive programming).
const DEFAULT_MOD : Int = 998_244_353

///|
/// Modular multiplication using Int64 to avoid overflow.
fn mod_mul(a : Int, b : Int, p : Int) -> Int {
  let r = a.to_int64() * b.to_int64() % p.to_int64()
  r.to_int()
}

///|
/// Modular exponentiation: a^b mod p. O(log b).
fn mod_pow(a : Int, b : Int, p : Int) -> Int {
  let mut result = 1
  let mut base = a % p
  if base < 0 {
    base = base + p
  }
  let mut exp = b
  while exp > 0 {
    if (exp & 1) == 1 {
      result = mod_mul(result, base, p)
    }
    base = mod_mul(base, base, p)
    exp = exp >> 1
  }
  result
}

///|
/// Modular inverse: a^(-1) mod p, using Fermat's little theorem.
/// Requires p to be prime. O(log p).
fn mod_inv(a : Int, p : Int) -> Int {
  mod_pow(a, p - 2, p)
}

///|
/// Find the shortest linear recurrence of a sequence modulo a prime.
///
/// Given `a = [a[0], a[1], ..., a[n-1]]` and prime modulus `p`, returns the
/// recurrence coefficients `[c[0], c[1], ..., c[L-1]]` such that:
///
/// `a[i] = c[0]*a[i-1] + c[1]*a[i-2] + ... + c[L-1]*a[i-L] (mod p)`
///
/// for all `i >= L`. If no recurrence is found (e.g., the sequence is all
/// zeros), returns an empty array.
///
/// O(n^2) time, O(n) space.
pub fn berlekamp_massey(a : Array[Int], p : Int) -> Array[Int] {
  let n = a.length()
  // `cur` is the current connection polynomial coefficients (cur[0] = 1).
  // The recurrence is: a[i] = -(cur[1]*a[i-1] + ... + cur[L]*a[i-L]) mod p
  let cur : Array[Int] = [1]
  let mut prev : Array[Int] = [1] // Previous polynomial before last change
  let mut rec_len = 0 // Current recurrence length
  let mut m = 1 // Steps since last length change
  let mut b = 1 // Previous discrepancy
  for i = 0; i < n; i = i + 1 {
    // Compute discrepancy: delta = a[i] + sum(cur[j] * a[i-j] for j=1..rec_len)
    let mut delta = a[i] % p
    if delta < 0 {
      delta = delta + p
    }
    for j = 1; j <= rec_len; j = j + 1 {
      if j < cur.length() {
        delta = (delta + mod_mul(cur[j], a[i - j], p)) % p
      }
    }
    delta = delta % p
    if delta == 0 {
      m = m + 1
    } else if 2 * rec_len <= i {
      // Length increase: save current cur, then update.
      let temp : Array[Int] = []
      for j = 0; j < cur.length(); j = j + 1 {
        temp.push(cur[j])
      }
      // Extend cur to have enough elements for the update.
      // cur = cur - (delta * b_inv) * x^m * prev
      let coef = mod_mul(delta, mod_inv(b, p), p)
      let needed = m + prev.length()
      while cur.length() < needed {
        cur.push(0)
      }
      for j = 0; j < prev.length(); j = j + 1 {
        cur[m + j] = (cur[m + j] - mod_mul(coef, prev[j], p) + p) % p
      }
      rec_len = i + 1 - rec_len
      prev = temp
      b = delta
      m = 1
    } else {
      // No length increase, just update cur.
      let coef = mod_mul(delta, mod_inv(b, p), p)
      let needed = m + prev.length()
      while cur.length() < needed {
        cur.push(0)
      }
      for j = 0; j < prev.length(); j = j + 1 {
        cur[m + j] = (cur[m + j] - mod_mul(coef, prev[j], p) + p) % p
      }
      m = m + 1
    }
  }
  // Extract the recurrence: a[i] = -cur[1]*a[i-1] - ... - cur[rec_len]*a[i-rec_len]
  // So the coefficients are: [-cur[1], -cur[2], ..., -cur[rec_len]]
  let result : Array[Int] = []
  for j = 1; j <= rec_len; j = j + 1 {
    let val = if j < cur.length() { (p - cur[j]) % p } else { 0 }
    result.push(val)
  }
  result
}

///|
/// Find the shortest linear recurrence of a sequence modulo 998244353.
///
/// Convenience wrapper around `berlekamp_massey` with the default modulus.
pub fn berlekamp_massey_default(a : Array[Int]) -> Array[Int] {
  berlekamp_massey(a, DEFAULT_MOD)
}

///|
/// Compute the n-th term of a linear recurrence given the first `L` terms
/// and the recurrence coefficients, using polynomial exponentiation (Kitamasa).
///
/// Given `init = [a[0], ..., a[L-1]]` and `coef = [c[0], ..., c[L-1]]` where
/// `a[i] = c[0]*a[i-1] + ... + c[L-1]*a[i-L]`, computes `a[n]` mod p.
///
/// O(L^2 log n) time, O(L) space.
pub fn linear_recurrence_nth(
  init : Array[Int],
  coef : Array[Int],
  n : Int,
  p : Int,
) -> Int {
  let l = coef.length()
  if n < l {
    return init[n] % p
  }
  if l == 0 {
    return 0
  }
  // Use polynomial exponentiation (Kitamasa method).
  // Compute x^n mod (x^l - c[0]*x^(l-1) - ... - c[l-1])
  // Then a[n] = sum(result[i] * init[i])
  let mut result = poly_zero()
  result = poly_set(result, 0, 1) // Start with x^0 = 1
  let mut base = poly_zero()
  base = poly_set(base, 1, 1) // x^1
  let mut exp = n
  while exp > 0 {
    if (exp & 1) == 1 {
      result = poly_mul_mod(result, base, coef, p)
    }
    base = poly_mul_mod(base, base, coef, p)
    exp = exp >> 1
  }
  // a[n] = sum(result[i] * init[i])
  let mut ans = 0
  for i = 0; i < l; i = i + 1 {
    if i < result.length() {
      ans = (ans + mod_mul(result[i], init[i], p)) % p
    }
  }
  ans
}

// Polynomial helpers for Kitamasa method.

///|
fn poly_zero() -> Array[Int] {
  [0]
}

///|
fn poly_set(poly : Array[Int], idx : Int, val : Int) -> Array[Int] {
  let result : Array[Int] = []
  for i = 0; i < poly.length(); i = i + 1 {
    result.push(poly[i])
  }
  while result.length() <= idx {
    result.push(0)
  }
  result[idx] = val
  result
}

///|
/// Multiply two polynomials and reduce modulo the characteristic polynomial.
/// The characteristic polynomial is: x^l - c[0]*x^(l-1) - ... - c[l-1]
/// i.e., x^l = c[0]*x^(l-1) + ... + c[l-1]
fn poly_mul_mod(
  a : Array[Int],
  b : Array[Int],
  coef : Array[Int],
  p : Int,
) -> Array[Int] {
  let la = a.length()
  let lb = b.length()
  let rec_len = coef.length()
  if la == 0 || lb == 0 {
    return [0]
  }
  if la == 1 && a[0] == 0 {
    return [0]
  }
  if lb == 1 && b[0] == 0 {
    return [0]
  }
  // Result before reduction: degree la + lb - 2
  let result = Array::make(la + lb - 1, 0)
  for i = 0; i < la; i = i + 1 {
    for j = 0; j < lb; j = j + 1 {
      result[i + j] = (result[i + j] + mod_mul(a[i], b[j], p)) % p
    }
  }
  // Reduce: replace x^k for k >= rec_len
  // using x^rec_len = sum(coef[i] * x^(rec_len-1-i))
  for k = result.length() - 1; k >= rec_len; k = k - 1 {
    if result[k] != 0 {
      let val = result[k]
      result[k] = 0
      for j = 0; j < rec_len; j = j + 1 {
        let idx = k - rec_len + (rec_len - 1 - j)
        result[idx] = (result[idx] + mod_mul(val, coef[j], p)) % p
      }
    }
  }
  // Trim to length rec_len
  let trimmed : Array[Int] = []
  for i = 0; i < rec_len && i < result.length(); i = i + 1 {
    trimmed.push(result[i])
  }
  while trimmed.length() < rec_len {
    trimmed.push(0)
  }
  trimmed
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "berlekamp_massey: fibonacci sequence" {
  // Fibonacci: 1, 1, 2, 3, 5, 8, 13, 21, ...
  // Recurrence: a[i] = a[i-1] + a[i-2]
  let fib = [1, 1, 2, 3, 5, 8, 13, 21, 34, 55]
  let rec = berlekamp_massey_default(fib)
  assert_eq(rec.length(), 2)
  assert_eq(rec[0], 1) // c[0] = 1
  assert_eq(rec[1], 1) // c[1] = 1
}

///|
test "berlekamp_massey: arithmetic progression" {
  // 2, 5, 8, 11, 14, ...
  // a[i] = 2*a[i-1] - a[i-2]
  let seq = [2, 5, 8, 11, 14, 17, 20]
  let rec = berlekamp_massey_default(seq)
  assert_eq(rec.length(), 2)
  assert_eq(rec[0], 2)
  assert_eq(rec[1], 998_244_353 - 1) // -1 mod p
}

///|
test "berlekamp_massey: geometric sequence" {
  // 3, 6, 12, 24, 48, ...
  // a[i] = 2*a[i-1]
  let seq = [3, 6, 12, 24, 48, 96]
  let rec = berlekamp_massey_default(seq)
  assert_eq(rec.length(), 1)
  assert_eq(rec[0], 2)
}

///|
test "berlekamp_massey: constant sequence" {
  // 7, 7, 7, 7, ...
  // a[i] = a[i-1]
  let seq = [7, 7, 7, 7, 7]
  let rec = berlekamp_massey_default(seq)
  assert_eq(rec.length(), 1)
  assert_eq(rec[0], 1)
}

///|
test "berlekamp_massey: zero sequence" {
  let seq = [0, 0, 0, 0, 0]
  let rec = berlekamp_massey_default(seq)
  assert_eq(rec.length(), 0)
}

///|
test "berlekamp_massey: verify recurrence" {
  // Generate a sequence with known recurrence, then verify
  let p = 998_244_353
  // a[i] = 3*a[i-1] + 2*a[i-2], a[0]=1, a[1]=2
  let seq : Array[Int] = [1, 2]
  for i = 2; i < 20; i = i + 1 {
    let val = (mod_mul(3, seq[i - 1], p) + mod_mul(2, seq[i - 2], p)) % p
    seq.push(val)
  }
  let rec = berlekamp_massey(seq, p)
  assert_eq(rec.length(), 2)
  assert_eq(rec[0], 3)
  assert_eq(rec[1], 2)
}

///|
test "linear_recurrence_nth: fibonacci" {
  let p = 998_244_353
  let init = [1, 1]
  let coef = [1, 1]
  // Fib(10) = 89, Fib(20) = 10946
  assert_eq(linear_recurrence_nth(init, coef, 10, p), 89)
  assert_eq(linear_recurrence_nth(init, coef, 20, p), 10946)
}

///|
test "linear_recurrence_nth: within init" {
  let p = 998_244_353
  let init = [5, 10, 15]
  let coef = [2, 0, p - 1] // a[i] = 2*a[i-1] - a[i-3]... just testing
  // For n < l, should return init[n]
  assert_eq(linear_recurrence_nth(init, coef, 0, p), 5)
  assert_eq(linear_recurrence_nth(init, coef, 1, p), 10)
  assert_eq(linear_recurrence_nth(init, coef, 2, p), 15)
}

///|
test "linear_recurrence_nth: large exponent" {
  let p = 998_244_353
  // Fib(100) mod p — compute expected by iterating
  let mut a = 1
  let mut b = 1
  for _ in 0..<99 {
    let c = (a + b) % p
    a = b
    b = c
  }
  let expected = b
  let init = [1, 1]
  let coef = [1, 1]
  assert_eq(linear_recurrence_nth(init, coef, 100, p), expected)
}

///|
test "berlekamp_massey: tribonacci" {
  // Tribonacci: 1, 1, 2, 4, 7, 13, 24, 44, ...
  // a[i] = a[i-1] + a[i-2] + a[i-3]
  let seq = [1, 1, 2, 4, 7, 13, 24, 44, 81, 149, 274]
  let rec = berlekamp_massey_default(seq)
  assert_eq(rec.length(), 3)
  assert_eq(rec[0], 1)
  assert_eq(rec[1], 1)
  assert_eq(rec[2], 1)
}
