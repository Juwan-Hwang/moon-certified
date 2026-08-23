/// Pollard-Rho integer factorization.
///
/// Finds a non-trivial factor of a composite number `n > 1`. Combined with
/// a primality test (Miller-Rabin via `@int64_utils.is_prime64`), it provides
/// a complete integer factorization routine.
///
/// **Algorithm.** Uses Brent's cycle detection with **batched GCD** on the
/// polynomial sequence x₀ = 2, x_{i+1} = (xᵢ² + c) mod n.
///
/// Brent's improvement over Floyd's classic tortoise-and-hare: only the hare
/// (fast pointer) advances each step; the tortoise is teleported to the hare's
/// position at power-of-2 boundaries. This reduces the number of function
/// evaluations by ~25% compared to Floyd's, where both pointers advance every
/// step.
///
/// **Batched GCD optimization.** Instead of computing gcd(|x−y|, n) at every
/// step (each GCD is O(log n)), the product of differences is accumulated over
/// a batch of `BATCH_SIZE` (128) steps and a single GCD is computed per batch.
/// This reduces the number of GCD calls by a factor of ~128, with the trade-off
/// that if the batch GCD yields `n`, a short backtracking scan of the last
/// batch is needed to pinpoint the exact factor.
///
/// If the batch GCD `g` satisfies `1 < g < n`, `g` is a factor. If `g == n`,
/// backtrack step-by-step through the last batch. If `diff == 0` (the sequence
/// entered a cycle without finding a factor), the attempt fails and a new
/// constant `c` is tried.
///
/// **Complexity.** Expected O(√p) function evaluations where p is the smallest
/// prime factor of n, i.e. O(n^{1/4}) in the worst case. GCD calls are reduced
/// to O(√p / BATCH_SIZE).
///
/// **Overflow safety.** All arithmetic is in `Int64`. Since n < 2^31,
/// x² < 2^62 < 2^63, so no `Int64` overflow can occur. The accumulated product
/// `q` is reduced mod n after each multiplication, so q < n < 2^31 and
/// q × diff < 2^62, well within Int64 range.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

// ---------------------------------------------------------------------------
// Pollard-Rho core
// ---------------------------------------------------------------------------

///|
/// Batch size for GCD accumulation. 128 is the standard choice balancing GCD
/// call reduction against backtracking cost.
let prho_batch_size : Int = 128

///|
/// One iteration of the Pollard-Rho sequence: f(x) = (x² + c) mod n.
fn prho_f(x : Int64, c : Int64, n : Int64) -> Int64 {
  (x * x + c) % n
}

///|
/// Attempt to find a non-trivial factor of n using Pollard-Rho with Brent's
/// cycle detection and batched GCD.
///
/// Parameters:
/// - `n`: the number to factor (must be composite, > 1).
/// - `c`: polynomial offset (must not be 0 or n-2 to avoid trivial cycles).
/// - `x0`: starting value for the sequence.
///
/// Returns a factor `d` with `1 < d < n`, or `n` if the attempt failed
/// (cycle found without a factor, or gcd yielded n).
fn prho_find(n : Int64, c : Int64, x0 : Int64) -> Int64 {
  let mut y = x0
  let mut r = 1 // Power-of-2 window size.
  while true {
    // Save tortoise position; advance hare by r steps.
    let x = y
    for i = 0; i < r; i = i + 1 {
      y = prho_f(y, c, n)
    }
    let mut k = 0
    let mut g = 1L
    let mut ys = y // Save hare position at batch start for backtracking.
    // Process the window in batches of prho_batch_size.
    while k < r && g == 1L {
      ys = y
      let limit = if r - k < prho_batch_size { r - k } else { prho_batch_size }
      let mut q = 1L
      for i = 0; i < limit; i = i + 1 {
        y = prho_f(y, c, n)
        let diff = if x > y { x - y } else { y - x }
        if diff == 0L {
          // Cycle found without a factor; this attempt failed.
          return n
        }
        q = q * diff % n
      }
      g = @int64_utils.gcd64(q, n)
      k = k + limit
    }
    if g == n {
      // Batch GCD yielded n: backtrack through the last batch to find
      // the exact step that produces a non-trivial factor.
      y = ys
      g = 1L
      while g == 1L {
        y = prho_f(y, c, n)
        let diff = if x > y { x - y } else { y - x }
        if diff == 0L {
          return n
        }
        g = @int64_utils.gcd64(diff, n)
      }
    }
    if g > 1L && g < n {
      return g
    }
    // g == 1: no factor in this window; double the window and continue.
    r = r * 2
  }
  n
}

///|
/// Find one non-trivial factor of `n`.
///
/// `n` must be a composite number greater than 1 (check with
/// `@int64_utils.is_prime64` before calling). Returns `Some(d)` with a factor
/// `d` satisfying `1 < d < n`. Returns `None` when `n <= 1`, when `n` is prime
/// (it has no non-trivial factor), or if all attempts fail (extremely unlikely
/// for composite `n`).
pub fn pollard_rho(n : Int) -> Int? {
  if n <= 1 {
    return None
  }
  // 2 is prime: no non-trivial factor exists.
  if n == 2 {
    return None
  }
  // Any even n > 2 has 2 as a non-trivial factor.
  if n % 2 == 0 {
    return Some(2)
  }
  let n64 = n.to_int64()
  // Try several values of c and x0. Using a fixed list avoids dependence on
  // a random number generator while still covering diverse failure modes.
  let constants = [1L, 2L, 3L, 5L, 7L, 11L, 13L, 17L, 19L, 23L, 29L, 31L]
  for i = 0; i < constants.length(); i = i + 1 {
    let d = prho_find(n64, constants[i], 2L)
    if d != 1L && d != n64 {
      return Some(d.to_int())
    }
    // Retry with a different starting value for this c.
    let d2 = prho_find(n64, constants[i], 3L)
    if d2 != 1L && d2 != n64 {
      return Some(d2.to_int())
    }
  }
  None // Should not happen for genuine composites
}

///|
/// Factorize `n` into its prime factors (with multiplicity), in ascending order.
///
/// Returns an empty array for n < 2. For n >= 2, returns the complete list
/// of prime factors whose product equals n.
///
/// **Algorithm.** Trial division for small primes (≤ 100), then Pollard-Rho
/// with Miller-Rabin primality checking for large factors. Recursively
/// factors any composite cofactors found by Pollard-Rho.
///
/// **Fallback.** If Pollard-Rho fails to find a factor for a composite
/// cofactor (extremely unlikely), the function falls back to trial division
/// up to √m. This guarantees correctness: no composite number is ever pushed
/// as a prime factor.
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
  // m is now free of factors ≤ 97. Factor the remaining cofactor.
  factor_rec(m, result)
  // Sort the result (trial-division factors are already ascending, but
  // Pollard-Rho may find larger factors first).
  // Simple insertion sort (result is typically short).
  let len = result.length()
  for i = 1; i < len; i = i + 1 {
    let key = result[i]
    let mut j = i - 1
    while j >= 0 && result[j] > key {
      result[j + 1] = result[j]
      j = j - 1
    }
    result[j + 1] = key
  }
  result
}

///|
/// Recursively factor a cofactor `m` (all factors > 97) into `result`.
///
/// If `m` is prime, it is pushed directly. Otherwise, Pollard-Rho is used
/// to find a non-trivial factor `d`, and both `d` and `m/d` are recursively
/// factored.
///
/// **Fallback.** If Pollard-Rho returns `None` (failure), the function falls
/// back to trial division starting from 101 up to √m. This guarantees that
/// no composite number is ever pushed as a prime factor, even in the
/// pathological case where Pollard-Rho fails.
fn factor_rec(m : Int, result : Array[Int]) -> Unit {
  if m == 1 {
    return
  }
  if @int64_utils.is_prime64(m.to_int64()) {
    result.push(m)
    return
  }
  // m is composite; find a factor with Pollard-Rho.
  match pollard_rho(m) {
    Some(d) => {
      factor_rec(d, result)
      factor_rec(m / d, result)
    }
    None => {
      // Pollard-Rho failed (extremely unlikely). Fall back to trial division
      // from 101 upward to guarantee correct factorization. This ensures no
      // composite number is ever silently pushed as a prime factor.
      let mut remaining = m
      let mut p = 101
      let limit = isqrt(m)
      while p <= limit && remaining > 1 {
        while remaining % p == 0 {
          result.push(p)
          remaining = remaining / p
        }
        p = p + 2 // Skip even numbers (m is odd at this point)
      }
      // If remaining > 1 after trial division, it must be prime.
      if remaining > 1 {
        result.push(remaining)
      }
    }
  }
}

///|
/// Integer square root: floor(sqrt(n)) for n >= 0.
fn isqrt(n : Int) -> Int {
  if n <= 0 {
    return 0
  }
  if n < 4 {
    return 1
  }
  // Newton's method with Int64 to prevent overflow.
  let mut x = n.to_int64()
  let mut y = (x + 1L) / 2L
  while y < x {
    x = y
    y = (x + n.to_int64() / x) / 2L
  }
  x.to_int()
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "pollard_rho: even number returns 2" {
  assert_eq(pollard_rho(100), Some(2))
  assert_eq(pollard_rho(6), Some(2))
  assert_eq(pollard_rho(2147483646), Some(2))
}

///|
test "pollard_rho: semiprime 15 = 3 * 5" {
  let d = pollard_rho(15).unwrap()
  assert_true(d == 3 || d == 5)
  assert_eq(15 / d * d, 15) // d divides 15
}

///|
test "pollard_rho: semiprime 49 = 7 * 7" {
  let d = pollard_rho(49).unwrap()
  assert_eq(d, 7)
}

///|
test "pollard_rho: large semiprime" {
  // 10007 * 10009 = 100160063
  let n = 100160063
  let d = pollard_rho(n).unwrap()
  assert_true(d != 1 && d != n)
  assert_eq(n % d, 0)
  assert_true(d == 10007 || d == 10009)
}

///|
test "pollard_rho: product of two large primes" {
  // 46337 * 46327 = 2146654199 (< 2^31)
  let n = 2146654199
  let d = pollard_rho(n).unwrap()
  assert_true(d != 1 && d != n)
  assert_eq(n % d, 0)
}

///|
test "pollard_rho: Carmichael number 561 = 3 * 11 * 17" {
  let d = pollard_rho(561).unwrap()
  assert_true(d != 1 && d != 561)
  assert_eq(561 % d, 0)
}

///|
test "pollard_rho: n <= 1 returns None" {
  assert_true(pollard_rho(0) is None)
  assert_true(pollard_rho(1) is None)
  assert_true(pollard_rho(-5) is None)
}

///|
test "pollard_rho: prime returns None (no non-trivial factor)" {
  // A prime has no non-trivial factor; the result must be None rather than
  // a value indistinguishable from a real factor.
  assert_true(pollard_rho(2) is None)
  assert_true(pollard_rho(3) is None)
  assert_true(pollard_rho(7) is None)
  assert_true(pollard_rho(13) is None)
  assert_true(pollard_rho(97) is None)
}

///|
test "is_prime64: small primes" {
  assert_eq(@int64_utils.is_prime64(2L), true)
  assert_eq(@int64_utils.is_prime64(3L), true)
  assert_eq(@int64_utils.is_prime64(5L), true)
  assert_eq(@int64_utils.is_prime64(7L), true)
  assert_eq(@int64_utils.is_prime64(11L), true)
}

///|
test "is_prime64: small composites" {
  assert_eq(@int64_utils.is_prime64(4L), false)
  assert_eq(@int64_utils.is_prime64(6L), false)
  assert_eq(@int64_utils.is_prime64(9L), false)
  assert_eq(@int64_utils.is_prime64(15L), false)
}

///|
test "is_prime64: Mersenne prime" {
  assert_eq(@int64_utils.is_prime64(2147483647L), true)
}

///|
test "is_prime64: Carmichael numbers" {
  assert_eq(@int64_utils.is_prime64(561L), false)
  assert_eq(@int64_utils.is_prime64(1105L), false)
  assert_eq(@int64_utils.is_prime64(1729L), false)
}

///|
test "factorize: prime number" {
  let f = factorize(17)
  assert_eq(f.length(), 1)
  assert_eq(f[0], 17)
}

///|
test "factorize: power of 2" {
  let f = factorize(1024)
  assert_eq(f.length(), 10)
  for i = 0; i < 10; i = i + 1 {
    assert_eq(f[i], 2)
  }
}

///|
test "factorize: semiprime" {
  let f = factorize(15)
  assert_eq(f.length(), 2)
  assert_eq(f[0], 3)
  assert_eq(f[1], 5)
}

///|
test "factorize: perfect square of prime" {
  let f = factorize(49)
  assert_eq(f.length(), 2)
  assert_eq(f[0], 7)
  assert_eq(f[1], 7)
}

///|
test "factorize: 561 = 3 * 11 * 17" {
  let f = factorize(561)
  assert_eq(f.length(), 3)
  assert_eq(f[0], 3)
  assert_eq(f[1], 11)
  assert_eq(f[2], 17)
}

///|
test "factorize: large semiprime 100160063" {
  let f = factorize(100160063)
  assert_eq(f.length(), 2)
  assert_eq(f[0], 10007)
  assert_eq(f[1], 10009)
}

///|
test "factorize: product of two large primes" {
  let n = 2146654199 // 46337 * 46327
  let f = factorize(n)
  assert_eq(f.length(), 2)
  assert_eq(f[0], 46327)
  assert_eq(f[1], 46337)
}

///|
test "factorize: one" {
  let f = factorize(1)
  assert_eq(f.length(), 0)
}

///|
test "factorize: zero and negative" {
  assert_eq(factorize(0).length(), 0)
  assert_eq(factorize(-5).length(), 0)
}

///|
test "factorize: factorial" {
  // 10! = 3628800 = 2^8 * 3^4 * 5^2 * 7
  let f = factorize(3628800)
  let mut product = 1
  for i = 0; i < f.length(); i = i + 1 {
    product = product * f[i]
  }
  assert_eq(product, 3628800)
  // Verify ascending order.
  for i = 1; i < f.length(); i = i + 1 {
    assert_true(f[i] >= f[i - 1])
  }
}

///|
test "factorize: large prime stays as single factor" {
  let f = factorize(2147483647) // Mersenne prime M31
  assert_eq(f.length(), 1)
  assert_eq(f[0], 2147483647)
}

///|
test "factorize: product verified for various n" {
  let cases = [12, 100, 999, 123456, 999983, 1048576]
  for i = 0; i < cases.length(); i = i + 1 {
    let n = cases[i]
    let f = factorize(n)
    let mut product = 1
    for j = 0; j < f.length(); j = j + 1 {
      product = product * f[j]
    }
    assert_eq(product, n)
    // Every factor should be prime.
    for j = 0; j < f.length(); j = j + 1 {
      assert_eq(@int64_utils.is_prime64(f[j].to_int64()), true)
    }
  }
}

///|
test "factorize: all factors verified as prime (regression for composite push)" {
  // This test verifies the fix for factor_rec pushing composite numbers
  // when pollard_rho returns None. We factorize many numbers and verify
  // that every factor in the result is genuinely prime.
  let cases = [
    121, 169, 289, 361, 529, 841, 961, 1369, 1681, 1849, 2209, 2809, 3481, 3721,
    4489, 5041, 5329, 6241, 6889, 7921, 9409, 10201, 10609, 11449, 11881, 12769,
    16129, 17161, 18769, 22201,
  ]
  for i = 0; i < cases.length(); i = i + 1 {
    let n = cases[i]
    let f = factorize(n)
    let mut product = 1
    for j = 0; j < f.length(); j = j + 1 {
      product = product * f[j]
      // Every factor must be prime (not composite).
      assert_eq(@int64_utils.is_prime64(f[j].to_int64()), true)
    }
    assert_eq(product, n)
  }
}

///|
test "factorize: product of three large primes" {
  // 101 * 103 * 107 = 1113121
  let n = 1113121
  let f = factorize(n)
  assert_eq(f.length(), 3)
  assert_eq(f[0], 101)
  assert_eq(f[1], 103)
  assert_eq(f[2], 107)
}

///|
test "factorize: perfect cube of prime" {
  // 101^3 = 1030301
  let f = factorize(1030301)
  assert_eq(f.length(), 3)
  for i = 0; i < 3; i = i + 1 {
    assert_eq(f[i], 101)
  }
}
