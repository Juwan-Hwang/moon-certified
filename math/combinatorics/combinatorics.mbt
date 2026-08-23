/// Combinatorial mathematics: binomial coefficients, Catalan numbers,
/// Stirling numbers of the second kind, and factorial.
///
/// All functions use Int64 internally to prevent overflow, and return
/// `Int?` — `None` when the result would overflow Int64 or inputs are
/// invalid.
///
/// **Complexity**:
/// - `binomial(n, k)` — O(k) time, O(1) space
/// - `catalan(n)` — O(n) time, O(1) space
/// - `stirling2(n, k)` — O(n*k) time, O(k) space (rolling array)
/// - `factorial(n)` — O(n) time, O(1) space
/// - `permutation(n, k)` — O(k) time, O(1) space
///
/// `proof-enabled` is `false`; correctness is ensured by the test suite.

///|
/// Maximum Int64 value, used for overflow detection.
let int64_max : Int64 = 9223372036854775807L

///|
/// Compute n! (factorial). Returns `None` if n < 0 or n! overflows Int64.
/// n! is defined for n >= 0; 0! = 1.
pub fn factorial(n : Int) -> Int? {
  if n < 0 {
    return None
  }
  let mut result = 1L
  for i = 2; i <= n; i = i + 1 {
    let prev = result
    result = result * i.to_int64()
    // Overflow check: if result / i != prev, we overflowed.
    if i > 1 && result / i.to_int64() != prev {
      return None
    }
  }
  if result > 2147483647L {
    None
  } else {
    Some(result.to_int())
  }
}

///|
/// Compute the falling factorial P(n, k) = n! / (n-k)! = n * (n-1) * ... * (n-k+1).
/// Returns `None` if inputs are invalid or the result overflows.
pub fn permutation(n : Int, k : Int) -> Int? {
  if n < 0 || k < 0 || k > n {
    return None
  }
  let mut result = 1L
  for i = 0; i < k; i = i + 1 {
    let factor = (n - i).to_int64()
    let prev = result
    result = result * factor
    if factor != 0L && result / factor != prev {
      return None
    }
  }
  if result > 2147483647L {
    None
  } else {
    Some(result.to_int())
  }
}

///|
/// Compute the binomial coefficient C(n, k) = n! / (k! * (n-k)!).
///
/// Uses the multiplicative formula: C(n,k) = product_{i=1}^{k} (n-k+i)/i.
/// This avoids computing large factorials directly.
///
/// **Overflow-safe computation**: The intermediate product
/// `result * (n-k+i)` is computed in `Int64` before dividing by `i`.
/// Since `C(n-k+i, i)` is always an integer, the division is exact — no
/// "divide first" shortcut is needed.  Each partial result is checked
/// against `Int32` max after every step, so the next intermediate is
/// bounded by `Int32_max * Int32_max < Int64_max` and can never overflow
/// `Int64`.
///
/// Returns `None` if inputs are invalid or the result overflows Int32.
pub fn binomial(n : Int, k : Int) -> Int? {
  if n < 0 || k < 0 {
    return None
  }
  if k > n {
    return Some(0)
  }
  // Use symmetry: C(n,k) = C(n,n-k)
  let k = if k > n - k { n - k } else { k }
  if k == 0 {
    return Some(1)
  }
  let mut result = 1L
  for i = 1; i <= k; i = i + 1 {
    // result = result * (n - k + i) / i
    // C(n-k+i, i) is always an integer, so the division is exact.
    // The intermediate result * (n-k+i) cannot overflow Int64 because
    // result < 2^31 (checked below) and (n-k+i) < 2^31.
    result = result * (n - k + i).to_int64() / i.to_int64()
    if result > 2147483647L {
      return None // Overflow: partial result exceeds Int32
    }
  }
  Some(result.to_int())
}

///|
/// Compute the n-th Catalan number: C(n) = C(2n, n) / (n+1).
///
/// Catalan numbers: 1, 1, 2, 5, 14, 42, 132, 429, 1430, 4862, ...
/// Returns `None` if n < 0 or the result overflows.
pub fn catalan(n : Int) -> Int? {
  if n < 0 {
    return None
  }
  if n == 0 {
    return Some(1)
  }
  // C(n) = C(2n, n) / (n+1)
  // Compute as: product_{i=0}^{n-1} (2n - i) / (n + 1 - i)
  // But simpler: C(n) = C(2n,n) / (n+1)
  // Use the recurrence: C(n) = C(n-1) * 2*(2n-1) / (n+1)
  let mut result = 1L
  for i = 0; i < n; i = i + 1 {
    // result = result * 2 * (2*i + 1) / (i + 2)
    let numerator = 2L * (2 * i + 1).to_int64()
    let denominator = (i + 2).to_int64()
    // Multiply first, then divide (result is always divisible)
    if result > int64_max / numerator {
      return None
    }
    result = result * numerator
    result = result / denominator
  }
  if result > 2147483647L {
    None
  } else {
    Some(result.to_int())
  }
}

///|
/// Compute Stirling numbers of the second kind S(n, k).
///
/// S(n, k) counts the number of ways to partition a set of n elements
/// into exactly k non-empty subsets.
///
/// Uses the recurrence: S(n, k) = k * S(n-1, k) + S(n-1, k-1)
/// with S(0, 0) = 1, S(n, 0) = 0 for n > 0, S(0, k) = 0 for k > 0.
///
/// Returns `None` if inputs are invalid or the result overflows.
/// Uses a rolling array for O(k) space.
pub fn stirling2(n : Int, k : Int) -> Int? {
  if n < 0 || k < 0 {
    return None
  }
  if k > n {
    return Some(0)
  }
  if n == 0 && k == 0 {
    return Some(1)
  }
  if k == 0 {
    return Some(0)
  }
  // Rolling array: dp[j] = S(i, j) for current i
  let dp = FixedArray::make(k + 1, 0L)
  dp[0] = 1L // S(0, 0) = 1
  for i = 1; i <= n; i = i + 1 {
    // Iterate backwards to use the rolling array in-place
    let mut j = if i < k { i } else { k }
    while j >= 1 {
      // S(i, j) = j * S(i-1, j) + S(i-1, j-1)
      // dp[j] currently holds S(i-1, j)
      // dp[j-1] currently holds S(i-1, j-1) (not yet updated)
      let s_prev_j = dp[j] // S(i-1, j)
      let s_prev_jm1 = dp[j - 1] // S(i-1, j-1)
      // Overflow-safe computation: check BEFORE each operation rather
      // than detecting wraparound after the fact.  j is a small Int
      // (<= k <= n), but s_prev_j can be large.
      let j_i64 = j.to_int64()
      // Multiplication: would j_i64 * s_prev_j exceed Int64?
      if s_prev_j > 0L && j_i64 > int64_max / s_prev_j {
        return None
      }
      let product = j_i64 * s_prev_j
      // Addition: would product + s_prev_jm1 exceed Int64?
      if s_prev_jm1 > 0L && product > int64_max - s_prev_jm1 {
        return None
      }
      let val = product + s_prev_jm1
      dp[j] = val
      j = j - 1
    }
    dp[0] = 0L // S(i, 0) = 0 for i > 0
  }
  let result = dp[k]
  if result > 2147483647L {
    None
  } else {
    Some(result.to_int())
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "factorial: basic" {
  assert_eq(factorial(0), Some(1))
  assert_eq(factorial(1), Some(1))
  assert_eq(factorial(5), Some(120))
  assert_eq(factorial(10), Some(3628800))
  assert_eq(factorial(12), Some(479001600))
}

///|
test "factorial: negative returns None" {
  assert_true(factorial(-1) is None)
}

///|
test "factorial: overflow returns None" {
  assert_true(factorial(13) is None) // 13! = 6227020800 > Int32 max
}

///|
test "permutation: basic" {
  assert_eq(permutation(5, 3), Some(60)) // 5*4*3
  assert_eq(permutation(5, 0), Some(1))
  assert_eq(permutation(5, 5), Some(120))
  assert_eq(permutation(10, 3), Some(720))
}

///|
test "permutation: invalid" {
  assert_true(permutation(-1, 0) is None)
  assert_true(permutation(5, 6) is None)
  assert_true(permutation(5, -1) is None)
}

///|
test "binomial: basic" {
  assert_eq(binomial(5, 2), Some(10))
  assert_eq(binomial(5, 3), Some(10)) // symmetry
  assert_eq(binomial(5, 0), Some(1))
  assert_eq(binomial(5, 5), Some(1))
  assert_eq(binomial(10, 4), Some(210))
  assert_eq(binomial(0, 0), Some(1))
}

///|
test "binomial: symmetry" {
  for n = 1; n <= 20; n = n + 1 {
    for k = 0; k <= n; k = k + 1 {
      let a = binomial(n, k)
      let b = binomial(n, n - k)
      assert_eq(a, b)
    }
  }
}

///|
test "binomial: Pascal's triangle identity" {
  // C(n,k) = C(n-1,k-1) + C(n-1,k)
  for n = 1; n <= 25; n = n + 1 {
    for k = 1; k < n; k = k + 1 {
      let lhs = binomial(n, k)
      let rhs = match (binomial(n - 1, k - 1), binomial(n - 1, k)) {
        (Some(a), Some(b)) => Some(a + b)
        _ => None
      }
      // If both sides are Some, they must match; if overflow, both None
      match (lhs, rhs) {
        (Some(a), Some(b)) => assert_eq(a, b)
        (None, None) => ()
        (_, _) => fail("binomial mismatch")
      }
    }
  }
}

///|
test "binomial: invalid" {
  assert_true(binomial(-1, 0) is None)
  assert_true(binomial(5, -1) is None)
  assert_eq(binomial(5, 6), Some(0))
}

///|
test "catalan: basic" {
  assert_eq(catalan(0), Some(1))
  assert_eq(catalan(1), Some(1))
  assert_eq(catalan(2), Some(2))
  assert_eq(catalan(3), Some(5))
  assert_eq(catalan(4), Some(14))
  assert_eq(catalan(5), Some(42))
  assert_eq(catalan(6), Some(132))
  assert_eq(catalan(7), Some(429))
  assert_eq(catalan(8), Some(1430))
  assert_eq(catalan(9), Some(4862))
}

///|
test "catalan: recurrence C(n) = C(2n,n)/(n+1)" {
  for n = 0; n <= 15; n = n + 1 {
    let cat = catalan(n)
    match (binomial(2 * n, n), cat) {
      (Some(b), Some(c)) => assert_eq(b / (n + 1), c)
      (None, None) => ()
      (_, _) => fail("catalan mismatch")
    }
  }
}

///|
test "catalan: negative returns None" {
  assert_true(catalan(-1) is None)
}

///|
test "stirling2: basic" {
  assert_eq(stirling2(0, 0), Some(1))
  assert_eq(stirling2(1, 1), Some(1))
  assert_eq(stirling2(2, 1), Some(1))
  assert_eq(stirling2(2, 2), Some(1))
  assert_eq(stirling2(3, 1), Some(1))
  assert_eq(stirling2(3, 2), Some(3))
  assert_eq(stirling2(3, 3), Some(1))
  assert_eq(stirling2(4, 2), Some(7))
  assert_eq(stirling2(5, 3), Some(25))
  assert_eq(stirling2(7, 4), Some(350))
}

///|
test "stirling2: recurrence S(n,k) = k*S(n-1,k) + S(n-1,k-1)" {
  for n = 1; n <= 15; n = n + 1 {
    for k = 1; k <= n; k = k + 1 {
      let lhs = stirling2(n, k)
      let rhs = match (stirling2(n - 1, k), stirling2(n - 1, k - 1)) {
        (Some(a), Some(b)) => Some(k * a + b)
        _ => None
      }
      match (lhs, rhs) {
        (Some(a), Some(b)) => assert_eq(a, b)
        (None, None) => ()
        (_, _) => fail("stirling2 mismatch")
      }
    }
  }
}

///|
test "stirling2: k > n returns 0" {
  assert_eq(stirling2(3, 5), Some(0))
  assert_eq(stirling2(0, 1), Some(0))
}

///|
test "stirling2: invalid" {
  assert_true(stirling2(-1, 0) is None)
  assert_true(stirling2(0, -1) is None)
}

///|
test "binomial: large values" {
  // C(30, 15) = 155117520
  assert_eq(binomial(30, 15), Some(155117520))
  // C(31, 15) = 300540195
  assert_eq(binomial(31, 15), Some(300540195))
  // C(33, 16) = 1166803110 (fits Int32: < 2147483647)
  assert_eq(binomial(33, 16), Some(1166803110))
  // C(34, 17) = 2333606220 (overflows Int32: > 2147483647)
  assert_true(binomial(34, 17) is None)
}

///|
/// Verified factorial: result >= 1 for n >= 0.
/// Uses for...nobreak loop with Z3-verifiable invariant.
pub fn factorial_int(n : Int) -> Int where {
  proof_require: 0 <= n,
  proof_ensure: result => factorial_ok(result),
} {
  let mut result = 1
  for i = 0; i < n; {
    result = result * (i + 1)
    continue i + 1
  } nobreak {
    result
  } where {
    proof_invariant: 0 <= i,
    proof_invariant: i <= n,
    proof_invariant: 1 <= result,
    proof_reasoning: (
      #| result starts at 1, each step multiplies by (i+1) >= 1,
      #| so result >= 1 is maintained. At exit i == n.
    ),
  }
}

///|
test "factorial_int: basic" {
  assert_eq(factorial_int(0), 1)
  assert_eq(factorial_int(1), 1)
  assert_eq(factorial_int(5), 120)
  assert_eq(factorial_int(10), 3628800)
  assert_true(factorial_int(0) >= 1)
  assert_true(factorial_int(10) >= 1)
}
