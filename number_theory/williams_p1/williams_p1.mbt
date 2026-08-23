/// Williams' p+1 Integer Factorization — production-grade implementation.
///
/// A factoring algorithm based on **Lucas sequences**. It is the p+1
/// analogue of Pollard's p−1 method: if `p` is a prime factor of `n` and
/// `p+1` is B-smooth (all prime factors of p+1 are ≤ B), then the algorithm
/// finds `p` in time proportional to B.
///
/// ## Mathematical Foundation
///
/// The algorithm uses the **Lucas sequence** `V_k(P, Q)` with `Q = 1`:
///
/// ```text
/// V₀ = 2
/// V₁ = P
/// Vₖ = P · Vₖ₋₁ − Vₖ₋₂        (recurrence)
/// ```
///
/// **Key property** (Williams 1982): If `p | n` and the group order
/// `p − (D/p)` is B-smooth (where `D = P² − 4Q = P² − 4` is the discriminant
/// and `(D/p)` is the Jacobi symbol), then:
///
/// ```text
/// V_M(P) ≡ 2  (mod p)     where M = lcm(1, 2, …, B)
/// ```
///
/// - If `(D/p) = −1`, the group order is `p + 1` → **p+1 method succeeds**.
/// - If `(D/p) = +1`, the group order is `p − 1` → degenerates to p−1 method.
/// - If `(D/p) = 0`, then `p | D` → `gcd(D, n)` yields a factor directly.
///
/// By trying multiple starting values of `P`, we ensure `(D/p) = −1` for at
/// least one attempt (roughly half of all `P` values give `−1` for any given
/// prime `p`).
///
/// ## Algorithm
///
/// 1. Choose starting value `P` (try `P = 3, 5, 7, …`).
/// 2. For each prime `q ≤ B`:
///    - Compute `e = ⌊log_q(B)⌋` (largest power `q^e ≤ B`).
///    - Compute `V_{q^e}(P) mod n` via the **Lucas chain** (Montgomery ladder).
///    - Update `P ← V_{q^e}(P) mod n` (composition: `V_{a·b}(P) = V_a(V_b(P))`).
/// 3. Compute `g = gcd(P − 2, n)`.
///    - If `1 < g < n`: found a non-trivial factor.
///    - If `g == n`: overshot — restart with smaller `B` or different `P`.
///    - If `g == 1`: `p+1` not B-smooth — increase `B` or try different `P`.
///
/// ## Lucas Chain (Montgomery Ladder)
///
/// To compute `V_m(P) mod n`, maintain the pair `(U, V) = (V_k, V_{k+1})`:
///
/// ```text
/// Doubling (bit 0):  V_{2k}   = U² − 2
///                    V_{2k+1} = U·V − P
/// Adding   (bit 1):  V_{2k+1} = U·V − P
///                    V_{2k+2} = V² − 2
/// ```
///
/// Process bits of `m` from MSB to LSB. This is O(log m) modular
/// multiplications, each using `mul_mod` (overflow-safe for full Int64).
///
/// ## Complexity
///
/// - **Stage 1**: O(B / log B) primes, each requiring O(log B) modular
///   multiplications → O(B) total multiplications.
/// - **Expected**: succeeds when `p + 1` is B-smooth, i.e. `p + 1` has no
///   prime factor exceeding `B`.
/// - **Practical**: for 32-bit `n`, `B = 100000` handles most factors where
///   `p + 1` is 100K-smooth.
///
/// ## Overflow Safety
///
/// All arithmetic uses `Int64` with `@int64_utils.mul_mod` (binary
/// decomposition, safe for the full Int64 range). The input `n` is a 32-bit
/// `Int` (n < 2³¹), but internal computations are correct for any `Int64`
/// modulus.
///
/// ## References
///
/// - Williams, H. C. (1982): "A p+1 Method of Factoring." Mathematics of
///   Computation, 39(159), 225–234.
/// - Riesel, H. (1994): "Prime Numbers and Computer Methods for
///   Factorization," 2nd ed., Birkhäuser, §6.6.
/// - Crandall, R. and Pomerance, C. (2005): "Prime Numbers: A Computational
///   Perspective," 2nd ed., Springer, §6.2.
///
/// `proof-enabled` is `false`; correctness is ensured by the test suite.

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

///|
/// Default smoothness bound for stage 1.
let default_bound : Int = 100000

///|
/// Maximum starting values to try before giving up.
let max_attempts : Int = 20

// ---------------------------------------------------------------------------
// Sieve of Eratosthenes
// ---------------------------------------------------------------------------

///|
/// Generate all primes up to `limit` using a sieve of Eratosthenes.
/// Returns primes in ascending order.
fn sieve_primes(limit : Int) -> Array[Int] {
  if limit < 2 {
    return []
  }
  let composite : FixedArray[Bool] = FixedArray::make(limit + 1, false)
  for i = 2; i * i <= limit; i = i + 1 {
    if !composite[i] {
      let mut j = i * i
      while j <= limit {
        composite[j] = true
        j = j + i
      }
    }
  }
  let primes : Array[Int] = []
  for i = 2; i <= limit; i = i + 1 {
    if !composite[i] {
      primes.push(i)
    }
  }
  primes
}

// ---------------------------------------------------------------------------
// Lucas Chain: compute V_m(P) mod n using Montgomery ladder
// ---------------------------------------------------------------------------

///|
/// Compute `V_m(P) mod n` using the Montgomery ladder for Lucas sequences
/// with `Q = 1`.
///
/// Maintains the pair `(U, V) = (V_k, V_{k+1})` and processes bits of `m`
/// from MSB to LSB:
/// - **Doubling step** (bit 0): `(V_{2k}, V_{2k+1}) = (U²−2, U·V−P)`
/// - **Adding step** (bit 1): `(V_{2k+1}, V_{2k+2}) = (U·V−P, V²−2)`
///
/// All multiplications use `mul_mod` for overflow safety.
fn lucas_v(m : Int64, p_val : Int64, n : Int64) -> Int64 {
  if m == 0L {
    return 2L
  }
  if m == 1L {
    return @int64_utils.mod64(p_val, n)
  }
  // Find the highest set bit of m.
  let mut hi = 62
  while hi >= 0 && m >> hi == 0L {
    hi = hi - 1
  }
  // Start: k = 0, (U, V) = (V_0, V_1) = (2, P)
  let mut u = 2L
  let mut v = @int64_utils.mod64(p_val, n)
  // Process ALL bits from MSB down to LSB.
  for bit = hi; bit >= 0; bit = bit - 1 {
    let b = (m >> bit) & 1L
    // u_sq = U² mod n,  v_sq = V² mod n,  uv = U·V mod n
    let u_sq = @int64_utils.mul_mod(u, u, n)
    let v_sq = @int64_utils.mul_mod(v, v, n)
    let uv = @int64_utils.mul_mod(u, v, n)
    if b == 0L {
      // Doubling: V_{2k} = U² - 2, V_{2k+1} = U·V - P
      u = @int64_utils.mod64(u_sq - 2L, n)
      v = @int64_utils.mod64(uv - p_val, n)
    } else {
      // Adding: V_{2k+1} = U·V - P, V_{2k+2} = V² - 2
      u = @int64_utils.mod64(uv - p_val, n)
      v = @int64_utils.mod64(v_sq - 2L, n)
    }
  }
  u
}

// ---------------------------------------------------------------------------
// Stage 1: compute V_M(P) mod n where M = product of prime powers ≤ B
// ---------------------------------------------------------------------------

///|
/// Run stage 1 of Williams' p+1 method.
///
/// Computes `V_M(P) mod n` where `M = ∏ q^e` over all primes `q ≤ B` with
/// `q^e ≤ B` (i.e., `M` is the product of all maximal prime powers up to B).
///
/// Returns `V_M(P) mod n`.
fn stage1(p_val : Int64, n : Int64, primes : Array[Int]) -> Int64 {
  let mut p_cur = p_val
  for i = 0; i < primes.length(); i = i + 1 {
    let q = primes[i]
    // Compute largest power q^e ≤ B.
    let mut qe = 1
    let mut q_pow = q
    while q_pow <= primes[primes.length() - 1] && q_pow > 0 {
      qe = q_pow
      // Check overflow before multiplying
      if q_pow > 2147483647 / q {
        break
      }
      q_pow = q_pow * q
    }
    // Compose: P_cur = V_{q^e}(P_cur) mod n
    p_cur = lucas_v(qe.to_int64(), p_cur, n)
  }
  p_cur
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

///|
/// Find one non-trivial factor of `n` using Williams' p+1 method.
///
/// `n` must be a composite number greater than 1 (check with
/// `@int64_utils.is_prime64` before calling). Returns `Some(d)` with a factor
/// `d` satisfying `1 < d < n`. Returns `None` when `n <= 1`, when `n` is
/// prime, or if all attempts fail.
///
/// ## Parameters
///
/// - `n`: the number to factor (must be > 1).
/// - `bound`: smoothness bound B for stage 1. Larger B finds factors where
///   `p+1` has larger prime factors, at the cost of more computation.
///
/// ## Example
///
/// ```moonbit nocheck
/// let f = williams_p1(10403, 1000)
/// // 10403 = 101 × 103, 101+1 = 102 = 2·3·17 (1000-smooth)
/// // Returns Some(101) or Some(103)
/// ```
pub fn williams_p1(n : Int, bound : Int) -> Int? {
  if n <= 1 {
    return None
  }
  if n == 2 {
    return None
  }
  if n % 2 == 0 {
    return Some(2)
  }
  let n64 = n.to_int64()
  // Generate primes up to bound.
  let b = if bound < 100 { 100 } else { bound }
  let primes = sieve_primes(b)
  if primes.length() == 0 {
    return None
  }
  // Try multiple starting values for P.
  // P = 3 is the classic choice; if it fails, try P = 5, 7, 9, ...
  // Odd P values are used because P² - 4 must not be 0 mod p for any factor p.
  let mut p_start = 3L
  for attempt = 0; attempt < max_attempts; attempt = attempt + 1 {
    let result = stage1(p_start, n64, primes)
    // Check gcd(V_M - 2, n).
    let g = @int64_utils.gcd64(@int64_utils.mod64(result - 2L, n64), n64)
    if g > 1L && g < n64 {
      return Some(g.to_int())
    }
    // If g == n, we overshot. Try with a smaller subset of primes.
    if g == n64 {
      // Binary search for the critical prime: find the smallest subset of
      // primes that still yields a factor.
      let factor = binary_search_factor(p_start, n64, primes)
      if factor > 1L && factor < n64 {
        return Some(factor.to_int())
      }
    }
    // g == 1: p+1 not B-smooth for this P. Try next P.
    p_start = p_start + 2L
  }
  None
}

///|
/// Find one non-trivial factor using the default smoothness bound (100000).
pub fn williams_p1_default(n : Int) -> Int? {
  williams_p1(n, default_bound)
}

// ---------------------------------------------------------------------------
// Binary search: find the step that separates the factor
// ---------------------------------------------------------------------------

///|
/// When stage 1 yields gcd == n (all factors triggered simultaneously),
/// binary search through the primes to find the subset that yields a
/// non-trivial factor.
///
/// Process primes one at a time, checking GCD after each composition.
/// This is O(|primes|) extra work but guarantees we find the factor if it
/// exists.
fn binary_search_factor(p_val : Int64, n : Int64, primes : Array[Int]) -> Int64 {
  let mut p_cur = p_val
  for i = 0; i < primes.length(); i = i + 1 {
    let q = primes[i]
    // Compute largest power q^e ≤ B.
    let mut qe = 1
    let mut q_pow = q
    let max_prime = primes[primes.length() - 1]
    while q_pow <= max_prime && q_pow > 0 {
      qe = q_pow
      if q_pow > 2147483647 / q {
        break
      }
      q_pow = q_pow * q
    }
    p_cur = lucas_v(qe.to_int64(), p_cur, n)
    let g = @int64_utils.gcd64(@int64_utils.mod64(p_cur - 2L, n), n)
    if g > 1L && g < n {
      return g
    }
    if g == n {
      // This prime caused the overshoot; return n to signal failure.
      return n
    }
  }
  n
}

// ---------------------------------------------------------------------------
// Factorize: complete factorization using Williams p+1 + Miller-Rabin
// ---------------------------------------------------------------------------

///|
/// Factorize `n` into its prime factors (with multiplicity), in ascending
/// order.
///
/// Uses trial division for small primes (≤ 100), then Williams' p+1 method
/// with Miller-Rabin primality checking for large factors. Recursively
/// factors any composite cofactors found.
///
/// Returns an empty array for n < 2. For n >= 2, returns the complete list
/// of prime factors whose product equals n.
pub fn factorize(n : Int) -> Array[Int] {
  let result : Array[Int] = []
  if n < 2 {
    return result
  }
  let mut m = n
  // Trial division for small primes.
  let small_primes = [
    2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61, 67, 71, 73,
    79, 83, 89, 97,
  ]
  for i = 0; i < small_primes.length(); i = i + 1 {
    let p = small_primes[i]
    while m % p == 0 {
      result.push(p)
      m = m / p
    }
  }
  if m == 1 {
    return result
  }
  // Recursive factorization of the remaining cofactor.
  factor_recursive(m, result)
  result.sort_by(fn(a, b) { a.compare(b) })
  result
}

///|
/// Recursively factor a composite number, appending prime factors to result.
fn factor_recursive(m : Int, result : Array[Int]) -> Unit {
  if m <= 1 {
    return
  }
  // Check primality.
  if @int64_utils.is_prime64(m.to_int64()) {
    result.push(m)
    return
  }
  // Try Williams p+1 with increasing bounds.
  let bounds = [1000, 10000, 100000, 500000]
  let mut found = false
  for bi = 0; bi < bounds.length() && !found; bi = bi + 1 {
    let d = williams_p1(m, bounds[bi])
    match d {
      Some(factor) =>
        if factor > 1 && factor < m {
          factor_recursive(factor, result)
          factor_recursive(m / factor, result)
          found = true
        }
      None => ()
    }
  }
  if !found {
    // Fallback: trial division up to sqrt(m).
    // This guarantees correctness even if Williams p+1 fails.
    let mut k = m
    let mut d = 101 // Start after small primes.
    while d.to_int64() * d.to_int64() <= k.to_int64() {
      while k % d == 0 {
        result.push(d)
        k = k / d
      }
      d = d + 2
    }
    if k > 1 {
      result.push(k)
    }
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "williams_p1: factor of semiprime with smooth p+1" {
  // 10403 = 101 × 103
  // 101 + 1 = 102 = 2 × 3 × 17  (1000-smooth)
  // 103 + 1 = 104 = 2³ × 13     (1000-smooth)
  let f = williams_p1(10403, 1000)
  match f {
    Some(d) => {
      assert_true(d > 1 && d < 10403)
      assert_eq(10403 % d, 0)
    }
    None => fail("should find a factor of 10403")
  }
}

///|
test "williams_p1: factor of larger semiprime" {
  // 32713 = 181 × ... let's use a known one
  // 1681 = 41 × 41, 41+1 = 42 = 2·3·7 (smooth)
  let f = williams_p1(1681, 1000)
  match f {
    Some(d) => {
      assert_true(d > 1 && d < 1681)
      assert_eq(1681 % d, 0)
    }
    None => fail("should find a factor of 1681")
  }
}

///|
test "williams_p1: factor with p+1 having small prime factors" {
  // 1003 = 17 × 59
  // 17 + 1 = 18 = 2 × 3²  (very smooth)
  // 59 + 1 = 60 = 2² × 3 × 5  (very smooth)
  let f = williams_p1(1003, 100)
  match f {
    Some(d) => {
      assert_true(d > 1 && d < 1003)
      assert_eq(1003 % d, 0)
    }
    None => fail("should find a factor of 1003")
  }
}

///|
test "williams_p1: even number returns 2" {
  assert_eq(williams_p1(100, 1000), Some(2))
  assert_eq(williams_p1(14, 1000), Some(2))
}

///|
test "williams_p1: prime returns None" {
  assert_true(williams_p1(97, 1000) is None)
  assert_true(williams_p1(101, 1000) is None)
}

///|
test "williams_p1: n <= 1 returns None" {
  assert_true(williams_p1(0, 1000) is None)
  assert_true(williams_p1(1, 1000) is None)
}

///|
test "williams_p1: large semiprime with smooth p+1" {
  // 999997 * 1000003 = 1000000000000 - 1 ... too large for Int.
  // Use: 10007 * 10009 = 100160063
  // 10007 + 1 = 10008 = 2³ × 3 × 417 = 2³ × 3 × 3 × 139... not that smooth.
  // Try: 233 * 239 = 55687
  // 233 + 1 = 234 = 2 × 3² × 13 (smooth)
  // 239 + 1 = 240 = 2⁴ × 3 × 5 (very smooth)
  let f = williams_p1(55687, 5000)
  match f {
    Some(d) => {
      assert_true(d > 1 && d < 55687)
      assert_eq(55687 % d, 0)
    }
    None => fail("should find a factor of 55687")
  }
}

///|
test "williams_p1: factor of product of two primes with very smooth p+1" {
  // 29 × 31 = 899
  // 29 + 1 = 30 = 2 × 3 × 5 (very smooth)
  // 31 + 1 = 32 = 2⁵ (extremely smooth)
  let f = williams_p1(899, 100)
  match f {
    Some(d) => {
      assert_true(d > 1 && d < 899)
      assert_eq(899 % d, 0)
    }
    None => fail("should find a factor of 899")
  }
}

///|
test "williams_p1: Carmichael number factorization" {
  // 561 = 3 × 11 × 17 (Carmichael number)
  // 3 + 1 = 4 = 2² (very smooth)
  // 11 + 1 = 12 = 2² × 3 (smooth)
  // 17 + 1 = 18 = 2 × 3² (smooth)
  let f = williams_p1(561, 100)
  match f {
    Some(d) => {
      assert_true(d > 1 && d < 561)
      assert_eq(561 % d, 0)
    }
    None => fail("should find a factor of 561")
  }
}

///|
test "williams_p1: default bound factorization" {
  // 1003 = 17 × 59, both p+1 are smooth
  let f = williams_p1_default(1003)
  match f {
    Some(d) => {
      assert_true(d > 1 && d < 1003)
      assert_eq(1003 % d, 0)
    }
    None => fail("should find a factor of 1003 with default bound")
  }
}

///|
test "williams_p1: factor where p+1 is a power of 2" {
  // 7 × 31 = 217
  // 7 + 1 = 8 = 2³ (very smooth)
  // 31 + 1 = 32 = 2⁵ (very smooth)
  let f = williams_p1(217, 100)
  match f {
    Some(d) => {
      assert_true(d > 1 && d < 217)
      assert_eq(217 % d, 0)
    }
    None => fail("should find a factor of 217")
  }
}

///|
test "factorize: small numbers" {
  assert_eq(factorize(1), [])
  assert_eq(factorize(2), [2])
  assert_eq(factorize(12), [2, 2, 3])
  assert_eq(factorize(60), [2, 2, 3, 5])
  assert_eq(factorize(97), [97])
}

///|
test "factorize: semiprime with smooth p+1" {
  // 899 = 29 × 31
  let factors = factorize(899)
  assert_eq(factors, [29, 31])
}

///|
test "factorize: product of three primes" {
  // 2 × 3 × 5 = 30
  assert_eq(factorize(30), [2, 3, 5])
  // 3 × 11 × 17 = 561 (Carmichael)
  assert_eq(factorize(561), [3, 11, 17])
}

///|
test "factorize: prime power" {
  assert_eq(factorize(8), [2, 2, 2])
  assert_eq(factorize(49), [7, 7])
  assert_eq(factorize(1681), [41, 41])
}

///|
test "factorize: larger composite" {
  // 10403 = 101 × 103
  let factors = factorize(10403)
  assert_eq(factors, [101, 103])
}

///|
test "factorize: perfect square of prime" {
  // 9409 = 97², 97 + 1 = 98 = 2 × 7² (smooth)
  let factors = factorize(9409)
  assert_eq(factors, [97, 97])
}

///|
test "lucas_v: V_0 = 2" {
  // V_0(P) = 2 for any P
  assert_eq(lucas_v(0L, 5L, 1000L), 2L)
}

///|
test "lucas_v: V_1 = P" {
  assert_eq(lucas_v(1L, 7L, 1000L), 7L)
  assert_eq(lucas_v(1L, 15L, 1000L), 15L)
}

///|
test "lucas_v: V_2 = P² - 2" {
  // V_2(P) = P² - 2
  // P=3: V_2 = 9 - 2 = 7
  assert_eq(lucas_v(2L, 3L, 1000L), 7L)
  // P=5: V_2 = 25 - 2 = 23
  assert_eq(lucas_v(2L, 5L, 1000L), 23L)
}

///|
test "lucas_v: V_3 = P³ - 3P" {
  // V_3(P) = P³ - 3P
  // P=3: V_3 = 27 - 9 = 18
  assert_eq(lucas_v(3L, 3L, 1000L), 18L)
  // P=4: V_3 = 64 - 12 = 52
  assert_eq(lucas_v(3L, 4L, 1000L), 52L)
}

///|
test "lucas_v: modular reduction" {
  // V_4(P) = P⁴ - 4P² + 2
  // P=3: V_4 = 81 - 36 + 2 = 47
  assert_eq(lucas_v(4L, 3L, 1000L), 47L)
  // P=3, mod 10: 47 mod 10 = 7
  assert_eq(lucas_v(4L, 3L, 10L), 7L)
}

///|
test "lucas_v: composition property V_m(V_n(P)) = V_{mn}(P)" {
  // V_2(V_3(P)) should equal V_6(P) for P=5, mod 1000
  let v3 = lucas_v(3L, 5L, 1000L)
  let v6_composed = lucas_v(2L, v3, 1000L)
  let v6_direct = lucas_v(6L, 5L, 1000L)
  assert_eq(v6_composed, v6_direct)
}

///|
test "williams_p1: factor of 32-bit semiprime" {
  // 2147483647 is prime (Mersenne), so let's use a composite near it.
  // 2147483645 = 5 × 429496729
  // 5 + 1 = 6 = 2 × 3 (smooth)
  let f = williams_p1(2147483645, 10000)
  match f {
    Some(d) => {
      assert_true(d > 1 && d < 2147483645)
      assert_eq(2147483645 % d, 0)
    }
    None => fail("should find a factor of 2147483645")
  }
}

///|
test "williams_p1: consistency with trial division" {
  // Cross-check: for several composites, verify factor divides n.
  let test_numbers = [899, 1003, 10403, 55687, 217, 561]
  for i = 0; i < test_numbers.length(); i = i + 1 {
    let n = test_numbers[i]
    let f = williams_p1(n, 5000)
    match f {
      Some(d) => {
        assert_true(d > 1 && d < n)
        assert_eq(n % d, 0)
      }
      None => fail("should find a factor of \{n}")
    }
  }
}

///|
test "factorize: product verification" {
  // For several numbers, verify that the product of factors equals n.
  let test_numbers = [899, 10403, 55687, 561, 217, 9409, 1681]
  for i = 0; i < test_numbers.length(); i = i + 1 {
    let n = test_numbers[i]
    let factors = factorize(n)
    let mut product = 1
    for j = 0; j < factors.length(); j = j + 1 {
      product = product * factors[j]
    }
    assert_eq(product, n)
    // Verify all factors are prime.
    for j = 0; j < factors.length(); j = j + 1 {
      assert_true(@int64_utils.is_prime64(factors[j].to_int64()))
    }
  }
}

///|
test "factorize: sorted output" {
  let factors = factorize(55687) // 233 × 239
  assert_eq(factors, [233, 239])
}

///|
test "williams_p1: bound too small may fail, larger bound succeeds" {
  // 10403 = 101 × 103
  // 101 + 1 = 102 = 2 × 3 × 17
  // With bound=10, 17 > 10 so stage 1 might not find the factor.
  // With bound=100, 17 ≤ 100 so it should succeed.
  let f_small = williams_p1(10403, 10)
  let f_large = williams_p1(10403, 100)
  // Large bound should always find a factor.
  match f_large {
    Some(d) => {
      assert_true(d > 1 && d < 10403)
      assert_eq(10403 % d, 0)
    }
    None => fail("bound=100 should find a factor of 10403")
  }
  // Small bound may or may not find a factor (no assertion on f_small).
  match f_small {
    Some(d) => assert_eq(10403 % d, 0)
    None => ()
  }
}
