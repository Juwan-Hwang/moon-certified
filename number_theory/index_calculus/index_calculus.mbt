/// Index Calculus — sub-exponential discrete logarithm in Z/pZ.
///
/// Computes `x = log_g(h)` (i.e., `g^x ≡ h (mod p)`) for a prime `p`,
/// generator `g`, and target `h`, using the **index calculus** method.
///
/// ## Algorithm
///
/// 1. **Factor base**: primes {p₁, ..., pₖ} up to smoothness bound B.
/// 2. **Relation collection**: find random exponents `e` such that
///    `g^e mod p` is B-smooth. Each such relation gives a row:
///    `e ≡ Σ aᵢ · log_g(pᵢ) (mod p-1)`.
/// 3. **Linear algebra**: solve the system over Z/(p-1)Z via Gaussian
///    elimination (with CRT for composite moduli).
/// 4. **Target resolution**: find random `t` such that `h · g^t mod p` is
///    B-smooth, then `log_g(h) = Σ aᵢ · log_g(pᵢ) - t (mod p-1)`.
///
/// ## Complexity
///
/// Sub-exponential: L_p[1/2, √2] where L_p[α, c] = exp(c · (ln p)^α · (ln ln p)^(1-α)).
/// For 32-bit primes, this is effectively polynomial.
///
/// ## Overflow Safety
///
/// All arithmetic uses `Int64`. For primes `p < 2^31`, intermediate
/// products are below `p^2 < 2^62 < 2^63`, preventing overflow.
///
/// ## References
///
/// - Adleman, L. (1979): "A Subexponential Algorithm for the Discrete
///   Logarithm Problem with Applications to Cryptography." FOCS 1979.
/// - Gordon, D. M. (1993): "Discrete Logarithms in GF(p) Using the Number
///   Field Sieve." SIAM J. Discrete Math., 6(1), 124–138.
/// - Pomerance, C. (1987): "Fast, Rigorous Factorization and Discrete
///   Logarithm Algorithms." In: Discrete Algorithms and Complexity.
///
/// `proof-enabled` is `false`; correctness is ensured by the test suite.

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

///|
/// Int64 modular inverse via extended Euclidean algorithm.
/// Returns `Some(inv)` with `a * inv ≡ 1 (mod m)`, or `None` when gcd ≠ 1.
fn mod_inv64(a : Int64, m : Int64) -> Int64? {
  let a_n = @int64_utils.mod64(a, m)
  let mut old_r = a_n
  let mut r = m
  let mut old_s = 1L
  let mut s = 0L
  while r != 0L {
    let q = old_r / r
    let new_r = old_r - q * r
    old_r = r
    r = new_r
    let new_s = old_s - q * s
    old_s = s
    s = new_s
  }
  if old_r != 1L {
    None
  } else {
    Some(@int64_utils.mod64(old_s, m))
  }
}

///|
/// Trial-factor `n` over the factor base. Returns an array of exponents
/// (one per prime in the factor base), or `None` if `n` is not B-smooth.
fn try_factor(n : Int64, factor_base : Array[Int]) -> Array[Int]? {
  let mut val = n
  let exps = Array::make(factor_base.length(), 0)
  for i = 0; i < factor_base.length(); i = i + 1 {
    let p = factor_base[i].to_int64()
    if val % p == 0L {
      let mut cnt = 0
      while val % p == 0L {
        val = val / p
        cnt = cnt + 1
      }
      exps[i] = cnt
    }
    if val == 1L {
      return Some(exps)
    }
  }
  if val == 1L {
    Some(exps)
  } else {
    None
  }
}

///|
/// Simple xorshift64 PRNG for deterministic relation collection.
/// Uses UInt64 internally for correct logical (zero-filling) right shifts.
priv struct XorShift64 {
  mut state : UInt64
}

///|
fn XorShift64::new(seed : Int64) -> XorShift64 {
  let s = if seed == 0L { 0x9E3779B97F4A7C15L } else { seed }
  { state: s.reinterpret_as_uint64() }
}

///|
fn XorShift64::next(self : XorShift64) -> Int64 {
  let mut x = self.state
  x = x ^ (x << 13)
  x = x ^ (x >> 7)
  x = x ^ (x << 17)
  self.state = x
  x.reinterpret_as_int64()
}

///|
fn XorShift64::next_mod(self : XorShift64, m : Int64) -> Int64 {
  @int64_utils.mod64(self.next(), m)
}

// ---------------------------------------------------------------------------
// Gaussian elimination over Z/nZ (n may be composite)
// ---------------------------------------------------------------------------

///|
/// Solve a system of linear equations over Z/nZ.
///
/// Given augmented matrix [A|b] where each row represents:
///   Σ aᵢⱼ · xⱼ ≡ bᵢ (mod n)
///
/// Returns `Some(solution)` if the system has a unique solution, `None` otherwise.
///
/// For composite n, we use the approach of solving modulo each prime power
/// factor of n and combining via CRT.
fn solve_mod(matrix : Array[Array[Int64]], n : Int64) -> Array[Int64]? {
  let num_rows = matrix.length()
  if num_rows == 0 {
    return None
  }
  let num_cols = matrix[0].length() - 1
  if num_rows < num_cols {
    return None
  }
  // Factor n into prime powers.
  let factors = factor_prime_powers(n)
  if factors.is_empty() {
    // n = 1, trivial
    return Some(Array::make(num_cols, 0L))
  }
  // Solve modulo each prime power, then CRT.
  let solutions : Array[Array[Int64]] = []
  let moduli : Array[Int64] = []
  for f in factors {
    let pe = f[0]
    let prime = f[1]
    match solve_mod_prime_power(matrix, pe, prime) {
      Some(sol) => {
        solutions.push(sol)
        moduli.push(pe)
      }
      None => return None
    }
  }
  // CRT combination.
  let result = Array::make(num_cols, 0L)
  for j = 0; j < num_cols; j = j + 1 {
    let residues : Array[Int64] = []
    for i = 0; i < solutions.length(); i = i + 1 {
      residues.push(solutions[i][j])
    }
    match crt_combine(residues, moduli) {
      Some(v) => result[j] = v
      None => return None
    }
  }
  Some(result)
}

///|
/// Factor n into list of [prime_power, prime] pairs.
fn factor_prime_powers(n : Int64) -> Array[Array[Int64]] {
  let result : Array[Array[Int64]] = []
  let mut m = n
  let mut d = 2L
  while d * d <= m {
    if m % d == 0L {
      let mut pe = 1L
      while m % d == 0L {
        pe = pe * d
        m = m / d
      }
      result.push([pe, d])
    }
    d = d + 1L
  }
  if m > 1L {
    result.push([m, m])
  }
  result
}

///|
/// Solve A*x ≡ b (mod p) where p is prime.
///
/// Standard Gaussian elimination — every non-zero element is invertible mod p.
/// Columns without pivots are free variables (set to 0).
fn solve_mod_prime(matrix : Array[Array[Int64]], p : Int64) -> Array[Int64]? {
  let num_rows = matrix.length()
  if num_rows == 0 {
    return None
  }
  let num_cols = matrix[0].length() - 1
  if num_cols <= 0 {
    return None
  }
  // Copy and reduce mod p.
  let aug : Array[Array[Int64]] = []
  for i = 0; i < num_rows; i = i + 1 {
    let row : Array[Int64] = []
    for j = 0; j <= num_cols; j = j + 1 {
      row.push(@int64_utils.mod64(matrix[i][j], p))
    }
    aug.push(row)
  }
  // Gaussian elimination.
  let mut pivot_row = 0
  let pivot_cols : Array[Int] = []
  for col = 0; col < num_cols; col = col + 1 {
    // Find non-zero pivot.
    let mut found = -1
    for row = pivot_row; row < num_rows; row = row + 1 {
      if aug[row][col] != 0L {
        found = row
        break
      }
    }
    if found < 0 {
      continue // Free variable — skip this column.
    }
    // Swap rows.
    if found != pivot_row {
      let tmp = aug[pivot_row]
      aug[pivot_row] = aug[found]
      aug[found] = tmp
    }
    // Scale pivot row so pivot becomes 1.
    let inv = match mod_inv64(aug[pivot_row][col], p) {
      Some(v) => v
      None => continue
    }
    for j = 0; j <= num_cols; j = j + 1 {
      aug[pivot_row][j] = @int64_utils.mod64(aug[pivot_row][j] * inv, p)
    }
    // Eliminate this column from all other rows.
    for row = 0; row < num_rows; row = row + 1 {
      if row != pivot_row {
        let factor = aug[row][col]
        if factor != 0L {
          for j = 0; j <= num_cols; j = j + 1 {
            aug[row][j] = @int64_utils.mod64(
              aug[row][j] - factor * aug[pivot_row][j],
              p,
            )
          }
        }
      }
    }
    pivot_cols.push(col)
    pivot_row = pivot_row + 1
  }
  // Extract solution. Free variables default to 0.
  let solution = Array::make(num_cols, 0L)
  for i = 0; i < pivot_row; i = i + 1 {
    let col = pivot_cols[i]
    solution[col] = aug[i][num_cols]
  }
  Some(solution)
}

///|
/// Solve A*x ≡ b (mod p^e) using Hensel lifting.
///
/// 1. Solve mod p (standard Gaussian elimination).
/// 2. Iteratively lift: given x_k mod p^k, find x_{k+1} = x_k + t·p^k
///    such that A·x_{k+1} ≡ b (mod p^{k+1}).
///    This reduces to solving A·t ≡ (b − A·x_k)/p^k (mod p).
fn solve_mod_prime_power(
  matrix : Array[Array[Int64]],
  pe : Int64,
  prime : Int64,
) -> Array[Int64]? {
  // Step 1: Solve mod prime.
  let solution = match solve_mod_prime(matrix, prime) {
    Some(s) => s
    None => return None
  }
  // Step 2: Iteratively lift from mod p^k to mod p^{k+1}.
  let num_cols = matrix[0].length() - 1
  let mut current_mod = prime
  while current_mod < pe {
    let next_mod = current_mod * prime
    // Build the residual system: A*t ≡ r (mod prime)
    // where r_i = (b_i − Σ a_{ij}·x_j) / current_mod  (mod prime)
    let residual : Array[Array[Int64]] = []
    for i = 0; i < matrix.length(); i = i + 1 {
      let row : Array[Int64] = []
      for j = 0; j < num_cols; j = j + 1 {
        row.push(@int64_utils.mod64(matrix[i][j], prime))
      }
      // Compute b − A·x (mod next_mod) using overflow-safe mul_mod.
      let mut ax = 0L
      for j = 0; j < num_cols; j = j + 1 {
        ax = @int64_utils.mod64(
          ax + @int64_utils.mul_mod(matrix[i][j], solution[j], next_mod),
          next_mod,
        )
      }
      let b_minus_ax = @int64_utils.mod64(matrix[i][num_cols] - ax, next_mod)
      // Divide by current_mod — this should be exact.
      let r = @int64_utils.mod64(b_minus_ax / current_mod, prime)
      row.push(r)
      residual.push(row)
    }
    // Solve A*t ≡ r (mod prime).
    let t = match solve_mod_prime(residual, prime) {
      Some(s) => s
      None => return None
    }
    // Update: x = x + t·current_mod (mod next_mod).
    for j = 0; j < num_cols; j = j + 1 {
      solution[j] = @int64_utils.mod64(
        solution[j] + @int64_utils.mul_mod(t[j], current_mod, next_mod),
        next_mod,
      )
    }
    current_mod = next_mod
  }
  Some(solution)
}

///|
/// CRT combination of residues.
fn crt_combine(residues : Array[Int64], moduli : Array[Int64]) -> Int64? {
  let k = residues.length()
  if k == 0 {
    return Some(0L)
  }
  let mut result = residues[0]
  let mut mod_so_far = moduli[0]
  for i = 1; i < k; i = i + 1 {
    let r2 = residues[i]
    let m2 = moduli[i]
    // Solve: x ≡ result (mod mod_so_far), x ≡ r2 (mod m2)
    // x = result + t * mod_so_far, where t ≡ (r2 - result) * inv(mod_so_far) (mod m2)
    let g = @int64_utils.gcd64(mod_so_far, m2)
    let diff = @int64_utils.mod64(r2 - result, m2)
    if diff % g != 0L {
      return None
    }
    let m1_reduced = mod_so_far / g
    let m2_reduced = m2 / g
    let diff_reduced = diff / g
    match mod_inv64(m1_reduced, m2_reduced) {
      Some(inv) => {
        let t = @int64_utils.mod64(diff_reduced * inv, m2_reduced)
        result = @int64_utils.mod64(
          result + t * mod_so_far,
          mod_so_far * m2_reduced,
        )
        mod_so_far = mod_so_far * m2_reduced
      }
      None => return None
    }
  }
  Some(result)
}

// ---------------------------------------------------------------------------
// Main index calculus algorithm
// ---------------------------------------------------------------------------

///|
/// Compute the discrete logarithm `x = log_g(h)` (i.e., `g^x ≡ h (mod p)`)
/// using the index calculus method.
///
/// **Parameters**:
/// - `g`: base (must be a generator of Z/pZ*)
/// - `h`: target value
/// - `p`: prime modulus
///
/// **Returns**: `Some(x)` with `0 ≤ x < p-1` and `g^x ≡ h (mod p)`, or `None`
/// if no solution exists or the algorithm fails to find one.
///
/// **Preconditions**: `p` must be prime, `1 ≤ g, h < p`, `gcd(g, p) = 1`.
pub fn index_calculus(g : Int64, h : Int64, p : Int64) -> Int64? {
  if p <= 1L {
    return None
  }
  let g = @int64_utils.mod64(g, p)
  let h = @int64_utils.mod64(h, p)
  if g == 0L || h == 0L {
    return None
  }
  if h == 1L {
    return Some(0L)
  }
  if g == h {
    return Some(1L)
  }
  let order = p - 1L
  // Choose smoothness bound B.
  // L_p[1/2, √2] heuristic: B ≈ exp(√(ln p · ln ln p))
  // For practical 32-bit primes, use a smaller bound.
  let ln_p = ln_int64(p)
  let ln_ln_p = ln_int64(ln_p.to_int64())
  let b_exp = sqrt_approx(ln_p * ln_ln_p)
  // Cap B at p-1: no value mod p can have a prime factor ≥ p.
  let b = min_int(
    max_int(100, min_int(b_exp.to_int(), 100000)),
    (p - 1L).to_int(),
  )
  // Generate factor base: primes up to B.
  let sieve = match @euler_sieve.sieve(b) {
    Some(s) => s
    None => return None
  }
  let primes_fa = @euler_sieve.primes(sieve)
  let factor_base : Array[Int] = []
  for i = 0; i < primes_fa.length(); i = i + 1 {
    factor_base.push(primes_fa[i])
  }
  let fb_size = factor_base.length()
  if fb_size == 0 {
    return None
  }
  // Collect relations.
  let rng = XorShift64::new(0x12345678ABCDEF01L)
  let relations : Array[Array[Int64]] = []
  let max_relations = fb_size + 10
  let mut attempts = 0
  let max_attempts = max_relations * 200
  while relations.length() < max_relations && attempts < max_attempts {
    attempts = attempts + 1
    let e = rng.next_mod(order)
    if e == 0L {
      continue
    }
    let val = @int64_utils.pow_mod64(g, e, p)
    match try_factor(val, factor_base) {
      Some(exps) => {
        // Row: [exp_0, exp_1, ..., exp_{k-1}, e]
        let row : Array[Int64] = []
        for i = 0; i < fb_size; i = i + 1 {
          row.push(exps[i].to_int64())
        }
        row.push(e)
        relations.push(row)
      }
      None => continue
    }
  }
  if relations.length() < fb_size {
    return None
  }
  // Solve the system to get logs of factor base primes.
  let logs = match solve_mod(relations, order) {
    Some(sol) => sol
    None => return None
  }
  // Verify logs and mark determined ones.
  // Free variables (set to 0 by Gaussian elimination) may not match the true
  // discrete log. Only use primes whose logs are verified.
  let determined : Array[Bool] = Array::make(fb_size, false)
  let mut num_determined = 0
  for i = 0; i < fb_size; i = i + 1 {
    let check = @int64_utils.pow_mod64(g, logs[i], p)
    if check == factor_base[i].to_int64() {
      determined[i] = true
      num_determined = num_determined + 1
    }
  }
  if num_determined == 0 {
    return None
  }
  // Find target: search for t such that h·g^t is B-smooth AND all primes
  // in its factorization have determined logs.
  let rng2 = XorShift64::new(0xFEDCBA9876543210L)
  let mut t_attempts = 0
  let max_t_attempts = 50000
  while t_attempts < max_t_attempts {
    t_attempts = t_attempts + 1
    let t = rng2.next_mod(order)
    let val = @int64_utils.mod64(
      @int64_utils.mul_mod(h, @int64_utils.pow_mod64(g, t, p), p),
      p,
    )
    match try_factor(val, factor_base) {
      Some(exps) => {
        // Reject if any prime with non-zero exponent is undetermined.
        let mut ok = true
        for i = 0; i < fb_size; i = i + 1 {
          if exps[i] > 0 && !determined[i] {
            ok = false
            break
          }
        }
        if !ok {
          continue
        }
        // log_g(h) = Σ exps[i] * logs[i] - t (mod order)
        let mut result = 0L
        for i = 0; i < fb_size; i = i + 1 {
          if exps[i] > 0 {
            result = @int64_utils.mod64(
              result + @int64_utils.mul_mod(exps[i].to_int64(), logs[i], order),
              order,
            )
          }
        }
        result = @int64_utils.mod64(result - t, order)
        // Final verification.
        let check = @int64_utils.pow_mod64(g, result, p)
        if check == h {
          return Some(result)
        }
      }
      None => continue
    }
  }
  None
}

// ---------------------------------------------------------------------------
// Math helpers
// ---------------------------------------------------------------------------

///|
/// Natural log of an Int64, returning as Double.
fn ln_int64(n : Int64) -> Double {
  if n <= 0L {
    return 0.0
  }
  // Use float conversion (safe for n < 2^52).
  let d = n.to_double()
  // Initial estimate: log2(x) ≈ bit position
  let mut log2 = 0.0
  let mut val = d
  while val >= 2.0 {
    val = val / 2.0
    log2 = log2 + 1.0
  }
  while val < 1.0 {
    val = val * 2.0
    log2 = log2 - 1.0
  }
  // log(x) = log2 * ln(2) + ln(val) where val in [1, 2)
  // ln(val) ≈ (val-1) - (val-1)^2/2 + (val-1)^3/3 - ... (Taylor series)
  let t = val - 1.0
  let ln_val = t -
    t * t / 2.0 +
    t * t * t / 3.0 -
    t * t * t * t / 4.0 +
    t * t * t * t * t / 5.0
  log2 * 0.6931471805599453 + ln_val
}

///|
/// Square root approximation for Double.
fn sqrt_approx(x : Double) -> Double {
  if x <= 0.0 {
    return 0.0
  }
  let mut guess = x / 2.0
  if guess < 1.0 {
    guess = 1.0
  }
  for i = 0; i < 20; i = i + 1 {
    guess = (guess + x / guess) / 2.0
  }
  guess
}

///|
fn max_int(a : Int, b : Int) -> Int {
  if a > b {
    a
  } else {
    b
  }
}

///|
fn min_int(a : Int, b : Int) -> Int {
  if a < b {
    a
  } else {
    b
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "index_calculus: small prime" {
  // p = 101, g = 2 (primitive root mod 101)
  // 2^1 = 2, 2^2 = 4, ..., find log_2(50) mod 101
  let result = index_calculus(2L, 50L, 101L)
  assert_true(result is Some(_))
  match result {
    Some(x) => {
      let check = @int64_utils.pow_mod64(2L, x, 101L)
      assert_eq(check, 50L)
    }
    None => assert_true(false)
  }
}

///|
test "index_calculus: log of 1" {
  // log_g(1) = 0 for any g
  let result = index_calculus(5L, 1L, 23L)
  assert_eq(result, Some(0L))
}

///|
test "index_calculus: log of generator" {
  // log_g(g) = 1
  let result = index_calculus(5L, 5L, 23L)
  assert_eq(result, Some(1L))
}

///|
test "index_calculus: medium prime" {
  // p = 1009 (prime), g = 11 (primitive root)
  // Verify: 11^x ≡ 500 (mod 1009)
  let result = index_calculus(11L, 500L, 1009L)
  assert_true(result is Some(_))
  match result {
    Some(x) => {
      let check = @int64_utils.pow_mod64(11L, x, 1009L)
      assert_eq(check, 500L)
    }
    None => assert_true(false)
  }
}

///|
test "index_calculus: verify with known value" {
  // p = 23, g = 5 (primitive root mod 23)
  // 5^3 = 125 = 5*23 + 10, so 5^3 ≡ 10 (mod 23)
  // Thus log_5(10) = 3
  let result = index_calculus(5L, 10L, 23L)
  match result {
    Some(x) => {
      assert_eq(x, 3L)
      let check = @int64_utils.pow_mod64(5L, x, 23L)
      assert_eq(check, 10L)
    }
    None => assert_true(false)
  }
}

///|
test "index_calculus: larger prime" {
  // p = 10007 (prime), g = 5 (primitive root mod 10007)
  let result = index_calculus(5L, 8192L, 10007L)
  match result {
    Some(x) => {
      let check = @int64_utils.pow_mod64(5L, x, 10007L)
      assert_eq(check, 8192L)
    }
    None => assert_true(false)
  }
}

///|
test "index_calculus: returns None for zero" {
  let result = index_calculus(0L, 5L, 23L)
  assert_eq(result, None)
}

///|
test "index_calculus: consistency check" {
  // For p = 101, g = 2:
  // Check that log_2(4) = 2 and log_2(8) = 3
  let r1 = index_calculus(2L, 4L, 101L)
  let r2 = index_calculus(2L, 8L, 101L)
  match (r1, r2) {
    (Some(x1), Some(x2)) => {
      assert_eq(x1, 2L)
      assert_eq(x2, 3L)
    }
    _ => assert_true(false)
  }
}
