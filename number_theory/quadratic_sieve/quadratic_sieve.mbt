/// Quadratic Sieve integer factorization with multiple polynomials.
///
/// Implements the self-initializing quadratic sieve (SIQS) — the most
/// practical variant of the quadratic sieve for factoring integers up to
/// ~100 bits. Key features:
///
/// 1. **Factor base**: Primes `p` where `n` is a quadratic residue mod `p`,
///    computed via the Jacobi symbol. Includes `-1` to handle sign.
/// 2. **Self-initializing multiple polynomials**: Uses `g_a,b(x) = (a·x + b)² − n`
///    where `a = q²` for factor-base primes `q`, and `b` satisfies `b² ≡ n (mod a)`.
///    Each `a` yields two roots `b` and `a−b`, doubling polynomial coverage.
/// 3. **Sieve interval**: For each polynomial, sieve `x ∈ [−M, M)` using
///    log-approximated sieve values for speed.
/// 4. **Smooth detection**: After sieving, candidates above a threshold are
///    trial-divided against the factor base to confirm B-smoothness.
/// 5. **Gaussian elimination over GF(2)**: Find a subset of smooth relations
///    whose exponent parity vector is zero — i.e., the product is a perfect square.
/// 6. **Factor extraction**: Compute `gcd(√(∏Q(xᵢ)) − ∏(aᵢxᵢ+bᵢ), n)`.
///
/// ## Complexity
///
/// `L(n) = exp(√(ln n · ln ln n))` — sub-exponential, the fastest known
/// algorithm for `n < ~100` digits (beyond that, NFS takes over).
///
/// ## References
///
/// - Pomerance, C. "The Quadratic Sieve Factoring Algorithm." Advances in
///   Cryptology — CRYPTO '84, 1985.
/// - Contini, S. "Factoring Integers with the Self-Initializing Quadratic
///   Sieve." Master's thesis, University of Georgia, 1997.
/// - Crandall & Pomerance. "Prime Numbers: A Computational Perspective."
///   Springer, 2005. Chapter 6.
///
/// `proof-enabled` is `false`.

// ---------------------------------------------------------------------------
// Utility functions
// ---------------------------------------------------------------------------

///|
/// Integer square root (Newton's method).
fn isqrt(n : Int) -> Int {
  if n <= 0 {
    return 0
  }
  let mut x = n
  let mut y = (n + 1) / 2
  while y < x {
    x = y
    y = (x + n / x) / 2
  }
  x
}

///|
/// Compute gcd of two integers.
pub fn gcd(a : Int, b : Int) -> Int {
  let mut x = if a < 0 { -a } else { a }
  let mut y = if b < 0 { -b } else { b }
  while y > 0 {
    let t = x % y
    x = y
    y = t
  }
  x
}

///|
/// GCD for Int64.
fn gcd64(a : Int64, b : Int64) -> Int64 {
  let mut x = if a < 0L { -a } else { a }
  let mut y = if b < 0L { -b } else { b }
  while y > 0L {
    let t = x % y
    x = y
    y = t
  }
  x
}

///|
/// Modular exponentiation: base^exp mod m.
/// Uses Int64 internally to avoid overflow when base*m is large.
fn powmod(base : Int, exp : Int, m : Int) -> Int {
  if m == 1 {
    return 0
  }
  let m64 = m.to_int64()
  let mut result = 1L
  let mut b = (base % m).to_int64()
  if b < 0L {
    b = b + m64
  }
  let mut e = exp
  while e > 0 {
    if (e & 1) == 1 {
      result = result * b % m64
    }
    e = e >> 1
    b = b * b % m64
  }
  result.to_int()
}

///|
/// Extended GCD: returns (g, x, y) where a*x + b*y = g = gcd(a, b).
fn ext_gcd(a : Int, b : Int) -> (Int, Int, Int) {
  if b == 0 {
    return (a, 1, 0)
  }
  let (g, x1, y1) = ext_gcd(b, a % b)
  (g, y1, x1 - a / b * y1)
}

///|
/// Modular inverse: a^(-1) mod m.
fn mod_inverse(a : Int, m : Int) -> Int {
  let (g, x, _) = ext_gcd(a % m, m)
  if g != 1 {
    return 0
  }
  let r = x % m
  if r < 0 {
    r + m
  } else {
    r
  }
}

///|
/// Natural logarithm approximation (Newton's method).
/// Used for sieve thresholds — precision is not critical.
fn ln_approx(x : Double) -> Double {
  if x <= 0.0 {
    return 0.0
  }
  // Change of variable: ln(x) = 2 * atanh((x-1)/(x+1))
  // atanh(z) = z + z^3/3 + z^5/5 + ... (converges for |z| < 1)
  // For x > ~3, divide repeatedly by e to bring into [1, e) range.
  let mut val = x
  let mut scale = 0.0
  let e_half = 1.6487212707 // e^(1/2)
  let ln_e_half = 0.5
  while val > 3.0 {
    val = val / e_half
    scale = scale + ln_e_half
  }
  while val < 0.5 {
    val = val * e_half
    scale = scale - ln_e_half
  }
  // Now use atanh series
  let z = (val - 1.0) / (val + 1.0)
  let mut sum = 0.0
  let z2 = z * z
  let mut term = z
  let mut k = 1
  while k < 100 {
    sum = sum + term / k.to_double()
    term = term * z2
    k = k + 2
    if term.abs() < 1.0e-15 {
      break
    }
  }
  2.0 * sum + scale
}

///|
/// Jacobi symbol (a/n) for odd n > 0.
/// Returns 0 if gcd(a,n) > 1, 1 if a is a QR mod n, -1 otherwise.
fn jacobi(a : Int, n : Int) -> Int {
  let mut a_val = a % n
  if a_val < 0 {
    a_val = a_val + n
  }
  let mut n_val = n
  let mut result = 1
  while a_val != 0 {
    while a_val % 2 == 0 {
      a_val = a_val / 2
      let r = n_val % 8
      if r == 3 || r == 5 {
        result = -result
      }
    }
    // Swap
    let t = a_val
    a_val = n_val
    n_val = t
    if a_val % 4 == 3 && n_val % 4 == 3 {
      result = -result
    }
    a_val = a_val % n_val
  }
  if n_val == 1 {
    result
  } else {
    0
  }
}

///|
/// Tonelli-Shanks algorithm: find x such that x² ≡ n (mod p).
/// Returns 0 if no solution exists (n is not a QR mod p).
fn tonelli_shanks(n : Int, p : Int) -> Int {
  if p == 2 {
    return n % 2
  }
  // Check if n is a QR mod p
  let j = jacobi(n % p, p)
  if j == 0 {
    return 0 // p divides n
  }
  if j == -1 {
    return 0 // No solution
  }
  // Factor p-1 = q * 2^s
  let mut q = p - 1
  let mut s = 0
  while q % 2 == 0 {
    q = q / 2
    s = s + 1
  }
  if s == 1 {
    // p ≡ 3 (mod 4): direct formula
    let r = powmod(n % p, (p + 1) / 4, p)
    let r64 = r.to_int64()
    let p64 = p.to_int64()
    if r64 * r64 % p64 == (n % p).to_int64() {
      return r
    }
    return 0
  }
  // Find a quadratic non-residue z
  let mut z = 2
  while jacobi(z, p) != -1 {
    z = z + 1
  }
  let mut c = powmod(z, q, p)
  let mut t = powmod(n % p, q, p)
  let mut r = powmod(n % p, (q + 1) / 2, p)
  let mut m = s
  while t != 1 {
    // Find least i such that t^(2^i) ≡ 1
    let mut i = 0
    let mut temp = t
    while temp != 1 {
      temp = temp * temp % p
      i = i + 1
      if i == m {
        return 0 // Shouldn't happen if n is a QR
      }
    }
    // Update
    let b = powmod(c, 1 << (m - i - 1), p)
    r = r * b % p
    t = t * b * b % p
    c = b * b % p
    m = i
  }
  let r_final = r
  let r64 = r_final.to_int64()
  let p64 = p.to_int64()
  if r64 * r64 % p64 == (n % p).to_int64() {
    r_final
  } else {
    0
  }
}

///|
/// Simple sieve of Eratosthenes: generate primes up to limit.
pub fn small_primes(limit : Int) -> Array[Int] {
  if limit < 2 {
    return []
  }
  let sieve : Array[Bool] = Array::make(limit + 1, true)
  sieve[0] = false
  sieve[1] = false
  let mut i = 2
  while i * i <= limit {
    if sieve[i] {
      let mut j = i * i
      while j <= limit {
        sieve[j] = false
        j = j + i
      }
    }
    i = i + 1
  }
  let primes : Array[Int] = []
  for k = 2; k <= limit; k = k + 1 {
    if sieve[k] {
      primes.push(k)
    }
  }
  primes
}

///|
/// Miller-Rabin primality test with deterministic witnesses for n < 3.3×10²⁴.
fn is_probable_prime(n : Int) -> Bool {
  if n < 2 {
    return false
  }
  if n == 2 || n == 3 {
    return true
  }
  if n % 2 == 0 {
    return false
  }
  let mut d = n - 1
  let mut r = 0
  while d % 2 == 0 {
    d = d / 2
    r = r + 1
  }
  let witnesses = [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37]
  for i = 0; i < witnesses.length(); i = i + 1 {
    let a = witnesses[i]
    if a >= n {
      continue
    }
    let x = powmod(a, d, n)
    if x == 1 || x == n - 1 {
      continue
    }
    let mut composite = true
    let n64 = n.to_int64()
    let mut x64 = x.to_int64()
    for j = 0; j < r - 1; j = j + 1 {
      x64 = x64 * x64 % n64
      if x64 == n64 - 1L {
        composite = false
        break
      }
    }
    if composite {
      return false
    }
  }
  true
}

// ---------------------------------------------------------------------------
// Factor base
// ---------------------------------------------------------------------------

///|
/// A prime in the factor base with its sieve roots.
/// `root1` and `root2` are the solutions to Q(x) ≡ 0 (mod p).
/// `log_p` is ln(p) used for sieve approximation.
priv struct FBPrime {
  p : Int
  log_p : Double
  root1 : Int // First root of Q(x) ≡ 0 (mod p)
  root2 : Int // Second root (same as root1 if p==2)
}

///|
/// Build the factor base for n: primes p ≤ B where n is a QR mod p,
/// plus the special entry for -1 (sign bit).
///
/// Uses the Jacobi symbol to test quadratic residuosity.
fn build_factor_base(n : Int, bound : Int) -> Array[FBPrime] {
  let primes = small_primes(bound)
  let fb : Array[FBPrime] = []
  for i = 0; i < primes.length(); i = i + 1 {
    let p = primes[i]
    if p == 2 {
      // 2 is in the factor base if n is odd (always, since we handle 2 separately)
      let n_mod_8 = n % 8
      if n_mod_8 == 1 || n_mod_8 == 7 {
        // n ≡ 1 or 7 (mod 8): Q(x) ≡ 0 (mod 2) has solutions
        fb.push({ p, log_p: ln_approx(2.0), root1: 0, root2: 0, })
      } else if n_mod_8 == 3 || n_mod_8 == 5 {
        // n ≡ 3 or 5 (mod 8): roots are odd
        fb.push({ p, log_p: ln_approx(2.0), root1: 1, root2: 1, })
      }
      continue
    }
    let j = jacobi(n % p, p)
    if j == 1 {
      // n is a QR mod p: find the square root
      let root = tonelli_shanks(n % p, p)
      if root > 0 {
        fb.push({
          p,
          log_p: ln_approx(p.to_double()),
          root1: root,
          root2: p - root,
        })
      }
    } else if j == 0 {
      // p divides n — we should have caught this earlier, but skip
      continue
    }
    // j == -1: n is not a QR mod p, skip this prime
  }
  fb
}

///|
/// Compute optimal factor base bound B for n.
/// Based on the heuristic B ≈ exp(√(ln n · ln ln n) / 2).
fn factor_base_bound(n : Int) -> Int {
  if n < 1000 {
    return 50
  }
  if n < 100000 {
    return 200
  }
  if n < 10000000 {
    return 500
  }
  if n < 100000000 {
    return 1000
  }
  2000
}

// ---------------------------------------------------------------------------
// Sieving
// ---------------------------------------------------------------------------

///|
/// A smooth relation: Q(x) = (a*x + b)² - n is B-smooth.
/// Stores the "square root" part (a*x+b) and the exponent parity vector.
priv struct Relation {
  ax_b : Int64 // a*x + b (the "square root" part)
  parity : Array[Bool] // exponent mod 2 for each factor base prime
}

///|
/// Check if a value is B-smooth over the factor base.
/// Returns the exponent parity vector if smooth, None otherwise.
fn check_smooth(val_in : Int64, fb : Array[FBPrime]) -> Array[Bool]? {
  let mut val = if val_in < 0L { -val_in } else { val_in }
  let parity : Array[Bool] = Array::make(fb.length(), false)
  for i = 0; i < fb.length(); i = i + 1 {
    let p = fb[i].p
    let p64 = p.to_int64()
    while val % p64 == 0L {
      val = val / p64
      parity[i] = !parity[i]
    }
  }
  if val == 1L {
    Some(parity)
  } else {
    None
  }
}

///|
/// Sieve with a single polynomial g(x) = (a*x + b)² - n.
///
/// For each factor base prime p, the roots of g(x) ≡ 0 (mod p) are
/// computed from the roots of Q(x) = x² - n adjusted for the polynomial.
/// Sieve values are accumulated as log approximations.
///
/// Returns a list of smooth relations found.
fn sieve_polynomial(
  n : Int,
  fb : Array[FBPrime],
  a : Int,
  b : Int,
  m : Int,
  threshold : Double,
) -> Array[Relation] {
  let sieve_size = 2 * m
  // Sieve array: log-approximated values
  let sieve_arr : Array[Double] = Array::make(sieve_size, 0.0)
  // For each factor base prime, add log(p) at sieve positions where Q(x) ≡ 0 (mod p)
  for i = 0; i < fb.length(); i = i + 1 {
    let p = fb[i].p
    let log_p = fb[i].log_p
    if p == 2 {
      // Special handling for p=2
      // Q(x) = (a*x+b)^2 - n. For p=2, we need (a*x+b)^2 ≡ n (mod 2)
      // Since a*x+b is an integer, (a*x+b)^2 ≡ (a*x+b) (mod 2)
      // So we need a*x+b ≡ n (mod 2)
      if a % 2 == 0 {
        if b % 2 == n % 2 {
          for x = 0; x < sieve_size; x = x + 1 {
            sieve_arr[x] = sieve_arr[x] + log_p
          }
        }
      } else {
        let target = ((n - b) % 2 + 2) % 2
        let start = if m % 2 == target { 0 } else { 1 }
        let mut x = start
        while x < sieve_size {
          sieve_arr[x] = sieve_arr[x] + log_p
          x = x + 2
        }
      }
      continue
    }
    // For p > 2: roots of (a*x + b)² ≡ n (mod p)
    // → a*x + b ≡ ±√n (mod p)
    // → x ≡ (±root - b) * a^(-1) (mod p)
    let a_inv = mod_inverse(a % p, p)
    if a_inv == 0 {
      continue // p divides a, skip
    }
    let r1 = (fb[i].root1 - b % p + p) % p * a_inv % p
    let r2 = (fb[i].root2 - b % p + p) % p * a_inv % p
    // Sieve: add log_p at x ≡ r1 (mod p) and x ≡ r2 (mod p)
    // x ranges from -m to m-1, stored at index x + m
    // Find first x >= -m with x ≡ r1 (mod p)
    let mut x1 = r1
    while x1 < -m {
      x1 = x1 + p
    }
    while x1 >= -m {
      x1 = x1 - p
    }
    x1 = x1 + p
    let mut x = x1
    while x < m {
      sieve_arr[x + m] = sieve_arr[x + m] + log_p
      x = x + p
    }
    if r2 != r1 {
      let mut x2 = r2
      while x2 < -m {
        x2 = x2 + p
      }
      while x2 >= -m {
        x2 = x2 - p
      }
      x2 = x2 + p
      let mut x = x2
      while x < m {
        sieve_arr[x + m] = sieve_arr[x + m] + log_p
        x = x + p
      }
    }
  }
  // Collect candidates above threshold
  let relations : Array[Relation] = []
  for x_idx = 0; x_idx < sieve_size; x_idx = x_idx + 1 {
    if sieve_arr[x_idx] < threshold {
      continue
    }
    let x = x_idx - m
    let ax_b = a.to_int64() * x.to_int64() + b.to_int64()
    let q_val = ax_b * ax_b - n.to_int64()
    match check_smooth(q_val, fb) {
      Some(parity) => relations.push({ ax_b, parity, })
      None => continue
    }
  }
  relations
}

// ---------------------------------------------------------------------------
// Gaussian elimination over GF(2)
// ---------------------------------------------------------------------------

///|
/// Solve the homogeneous system M·v = 0 over GF(2) using Gaussian elimination.
///
/// `matrix` is an array of rows, each row is a bit vector (Array[Bool]).
/// Returns a null-space vector v such that M·v = 0, or None if only the
/// trivial solution exists.
///
/// Uses bitwise operations on packed Int64 arrays for efficiency.
fn gaussian_elimination_gf2(
  matrix : Array[Array[Bool]],
  n_cols : Int,
) -> Array[Bool]? {
  let n_rows = matrix.length()
  if n_rows == 0 {
    return None
  }
  // Convert to packed representation: each row is an array of Int64
  let words_per_row = (n_cols + 63) / 64
  let packed : Array[Array[Int64]] = []
  for i = 0; i < n_rows; i = i + 1 {
    let row : Array[Int64] = Array::make(words_per_row, 0L)
    for j = 0; j < n_cols; j = j + 1 {
      if matrix[i][j] {
        let word = j / 64
        let bit = j % 64
        row[word] = row[word] | (1L << bit)
      }
    }
    packed.push(row)
  }
  // Track which column each pivot row eliminates
  let pivot_col : Array[Int] = Array::make(n_rows, -1)
  let mut pivot_row = 0
  for col = 0; col < n_cols && pivot_row < n_rows; col = col + 1 {
    // Find a row with a 1 in this column
    let mut found = -1
    for row = pivot_row; row < n_rows; row = row + 1 {
      let word = col / 64
      let bit = col % 64
      if (packed[row][word] & (1L << bit)) != 0L {
        found = row
        break
      }
    }
    if found < 0 {
      continue // Free variable
    }
    // Swap rows
    if found != pivot_row {
      let tmp = packed[pivot_row]
      packed[pivot_row] = packed[found]
      packed[found] = tmp
    }
    // Eliminate this column from all other rows
    let word = col / 64
    let bit = col % 64
    let mask = 1L << bit
    for row = 0; row < n_rows; row = row + 1 {
      if row != pivot_row && (packed[row][word] & mask) != 0L {
        for w = 0; w < words_per_row; w = w + 1 {
          packed[row][w] = packed[row][w] ^ packed[pivot_row][w]
        }
      }
    }
    pivot_col[pivot_row] = col
    pivot_row = pivot_row + 1
  }
  // Find a free variable and construct a null-space vector
  let is_pivot : Array[Bool] = Array::make(n_cols, false)
  for i = 0; i < pivot_row; i = i + 1 {
    if pivot_col[i] >= 0 {
      is_pivot[pivot_col[i]] = true
    }
  }
  // Find the first free variable
  let mut free_var = -1
  for j = 0; j < n_cols; j = j + 1 {
    if !is_pivot[j] {
      free_var = j
      break
    }
  }
  if free_var < 0 {
    return None // No free variables → only trivial solution
  }
  // Construct the null-space vector:
  // Set free_var = 1, then back-substitute to find other components
  let solution : Array[Bool] = Array::make(n_cols, false)
  solution[free_var] = true
  // For each pivot row, if the free_var column is set, set the pivot column
  for i = 0; i < pivot_row; i = i + 1 {
    let pc = pivot_col[i]
    if pc < 0 {
      continue
    }
    let word = free_var / 64
    let bit = free_var % 64
    if (packed[i][word] & (1L << bit)) != 0L {
      solution[pc] = true
    }
  }
  Some(solution)
}

// ---------------------------------------------------------------------------
// Self-initializing quadratic sieve
// ---------------------------------------------------------------------------

///|
/// Factor n using the self-initializing quadratic sieve (SIQS).
///
/// Returns `Some(factor)` if a non-trivial factor is found, `None` if n is
/// prime or a factor cannot be found within the iteration limit.
pub fn factor(n : Int) -> Int? {
  if n < 2 {
    return None
  }
  if n == 2 || n == 3 {
    return None
  }
  if n % 2 == 0 {
    return Some(2)
  }
  // Trial division for small factors
  let trial_limit = isqrt(isqrt(n)) + 1
  match trial_division(n, trial_limit * 100) {
    Some(d) => if d < n { return Some(d) }
    None => ()
  }
  // Check if n is prime
  if is_probable_prime(n) {
    return None
  }
  // Check if n is a perfect square
  let sq = isqrt(n)
  if sq * sq == n {
    return Some(sq)
  }
  // Determine factor base parameters
  let bound = factor_base_bound(n)
  let fb = build_factor_base(n, bound)
  if fb.length() < 3 {
    // Factor base too small, fall back to Fermat
    return fermat_factor(n)
  }
  // Sieve parameters
  let m = if n < 100000 { 500 } else if n < 10000000 { 2000 } else { 5000 }
  let log_n = ln_approx(n.to_double())
  let threshold = log_n * 0.5
  // Collect relations
  let all_relations : Array[Relation] = []
  let needed = fb.length() + 10
  // Self-initializing: use multiple polynomials
  // g_a,b(x) = (a*x + b)² - n, where a = q² for some factor base prime q
  let mut found = false
  let mut result = 0
  // Use q values from the factor base (skip very small primes)
  let start_q_idx = if fb.length() > 10 { fb.length() / 3 } else { 1 }
  let max_polynomials = 200
  let mut poly_count = 0
  for qi = start_q_idx
      qi < fb.length() && poly_count < max_polynomials
      qi = qi + 1 {
    if found {
      break
    }
    let q = fb[qi].p
    let a = q * q
    if a == 0 {
      continue
    }
    // Find b such that b² ≡ n (mod a)
    // Since a = q² and n is QR mod q, we need b² ≡ n (mod q²)
    // Use Hensel's lemma: lift the root from mod q to mod q²
    let root_mod_q = fb[qi].root1
    if root_mod_q == 0 {
      continue
    }
    // Hensel lift: b = root_mod_q + k*q where k chosen so b² ≡ n (mod q²)
    // b² ≡ n (mod q²) → (root + kq)² ≡ n (mod q²)
    // → root² + 2*root*k*q ≡ n (mod q²)
    // → k ≡ (n - root²) / (2*root*q) (mod q)
    let n_mod_q2 = n % a
    let root_sq = root_mod_q * root_mod_q % a
    let diff = (n_mod_q2 - root_sq + a) % a
    let denom = 2 * root_mod_q * q % a
    let denom_q = denom / q
    if denom_q == 0 {
      continue
    }
    let k_inv = mod_inverse(denom_q % q, q)
    if k_inv == 0 {
      continue
    }
    let k = diff / q * k_inv % q
    let b = root_mod_q + k * q
    // Two polynomials: (a, b) and (a, a-b)
    let bs = [b, a - b]
    for bi = 0; bi < 2 && poly_count < max_polynomials; bi = bi + 1 {
      if found {
        break
      }
      let b_val = bs[bi]
      poly_count = poly_count + 1
      let rels = sieve_polynomial(n, fb, a, b_val, m, threshold)
      for r = 0; r < rels.length(); r = r + 1 {
        all_relations.push(rels[r])
      }
      // Try to find a factor once we have enough relations
      if all_relations.length() >= needed {
        match try_find_factor(n, fb, all_relations) {
          Some(f) =>
            if f > 1 && f < n {
              found = true
              result = f
            }
          None => continue
        }
      }
    }
  }
  if found {
    return Some(result)
  }
  // Last attempt with all collected relations
  match try_find_factor(n, fb, all_relations) {
    Some(f) => if f > 1 && f < n { return Some(f) }
    None => ()
  }
  // Fall back to Fermat factorization
  fermat_factor(n)
}

///|
/// Trial division: try all divisors up to limit.
fn trial_division(n : Int, limit : Int) -> Int? {
  if n % 2 == 0 {
    return Some(2)
  }
  let mut d = 3
  while d <= limit && d * d <= n {
    if n % d == 0 {
      return Some(d)
    }
    d = d + 2
  }
  None
}

///|
/// Attempt to find a factor from collected smooth relations.
///
/// Builds the parity matrix, solves for a null-space vector, then
/// computes gcd(∏(aᵢxᵢ+bᵢ) - √(∏Q(xᵢ)), n).
fn try_find_factor(
  n : Int,
  fb : Array[FBPrime],
  relations : Array[Relation],
) -> Int? {
  let n_rels = relations.length()
  let n_cols = fb.length()
  if n_rels < n_cols + 1 {
    return None
  }
  // Build the transposed parity matrix for M^T · v = 0:
  // Rows = factor base primes (n_cols), Cols = relations (n_rels).
  // The null-space vector v has n_rels entries (one per relation).
  let matrix : Array[Array[Bool]] = []
  for j = 0; j < n_cols; j = j + 1 {
    let row : Array[Bool] = Array::make(n_rels, false)
    for i = 0; i < n_rels; i = i + 1 {
      row[i] = relations[i].parity[j]
    }
    matrix.push(row)
  }
  // Find a null-space vector of size n_rels
  match gaussian_elimination_gf2(matrix, n_rels) {
    Some(dependent) => {
      // Compute x = ∏(aᵢxᵢ+bᵢ) mod n and y = ∏√Q(xᵢ) mod n
      let mut x_prod = 1L
      // For y, accumulate prime exponents from selected relations
      let total_exp : Array[Int] = Array::make(n_cols, 0)
      for i = 0; i < n_rels; i = i + 1 {
        if dependent[i] {
          x_prod = x_prod * relations[i].ax_b % n.to_int64()
          // Re-derive full exponents by trial division of |Q(x)|
          let q_val = relations[i].ax_b * relations[i].ax_b - n.to_int64()
          let mut val = if q_val < 0L { -q_val } else { q_val }
          for j = 0; j < n_cols; j = j + 1 {
            let p64 = fb[j].p.to_int64()
            while val % p64 == 0L {
              val = val / p64
              total_exp[j] = total_exp[j] + 1
            }
          }
        }
      }
      // y = ∏ p^(total_exp[j] / 2) mod n
      let mut y_prod = 1L
      let n64 = n.to_int64()
      for j = 0; j < n_cols; j = j + 1 {
        let half = total_exp[j] / 2
        let p64 = fb[j].p.to_int64()
        for k = 0; k < half; k = k + 1 {
          y_prod = y_prod * p64 % n64
        }
      }
      // Compute gcd(|x - y|, n) and gcd(|x + y|, n)
      let diff = if x_prod > y_prod { x_prod - y_prod } else { y_prod - x_prod }
      let g1 = gcd64(diff % n64, n64)
      let sum = (x_prod + y_prod) % n64
      let g2 = gcd64(sum, n64)
      let g = if g1 > g2 { g1 } else { g2 }
      let g_int = g.to_int()
      if g_int > 1 && g_int < n {
        return Some(g_int)
      }
      // Try with negative y
      let neg_diff = (x_prod + n64 - y_prod) % n64
      let g3 = gcd64(neg_diff, n64)
      let g_int3 = g3.to_int()
      if g_int3 > 1 && g_int3 < n {
        return Some(g_int3)
      }
      None
    }
    None => None
  }
}

///|
/// Fermat factorization: find a, b such that n = a² - b² = (a+b)(a-b).
/// Used as a fallback for small numbers or when the sieve fails.
fn fermat_factor(n : Int) -> Int? {
  if n % 2 == 0 {
    return Some(2)
  }
  let mut a = isqrt(n)
  if a * a == n {
    return Some(a)
  }
  a = a + 1
  let mut iter = 0
  let max_iter = 1000000
  while iter < max_iter {
    let b2 = a * a - n
    if b2 > 0 {
      let b = isqrt(b2)
      if b * b == b2 {
        let factor = a - b
        if factor > 1 && factor < n {
          return Some(factor)
        }
        let factor2 = a + b
        if factor2 > 1 && factor2 < n {
          return Some(factor2)
        }
      }
    }
    a = a + 1
    iter = iter + 1
  }
  None
}

///|
/// Check if n is B-smooth (all prime factors ≤ B).
/// Returns the list of prime factor exponents mod 2 if smooth, None otherwise.
pub fn try_smooth(n : Int, primes : Array[Int]) -> Array[Int]? {
  let mut val = n
  let exponents : Array[Int] = Array::make(primes.length(), 0)
  for i = 0; i < primes.length(); i = i + 1 {
    while val % primes[i] == 0 {
      val = val / primes[i]
      exponents[i] = exponents[i] + 1
    }
    exponents[i] = exponents[i] % 2
  }
  if val == 1 {
    Some(exponents)
  } else {
    None
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "quadratic_sieve: factor 15" {
  match factor(15) {
    Some(d) => {
      assert_true(d == 3 || d == 5)
      assert_eq(15 / d * d, 15)
    }
    None => assert_true(false)
  }
}

///|
test "quadratic_sieve: factor 21" {
  match factor(21) {
    Some(d) => {
      assert_true(d == 3 || d == 7)
      assert_eq(21 % d, 0)
    }
    None => assert_true(false)
  }
}

///|
test "quadratic_sieve: factor 35" {
  match factor(35) {
    Some(d) => {
      assert_true(d == 5 || d == 7)
      assert_eq(35 % d, 0)
    }
    None => assert_true(false)
  }
}

///|
test "quadratic_sieve: factor 77" {
  match factor(77) {
    Some(d) => {
      assert_true(d == 7 || d == 11)
      assert_eq(77 % d, 0)
    }
    None => assert_true(false)
  }
}

///|
test "quadratic_sieve: prime returns None" {
  match factor(97) {
    Some(_) => assert_true(false)
    None => assert_true(true)
  }
}

///|
test "quadratic_sieve: factor 91" {
  match factor(91) {
    Some(d) => {
      assert_true(d == 7 || d == 13)
      assert_eq(91 % d, 0)
    }
    None => assert_true(false)
  }
}

///|
test "quadratic_sieve: factor 153" {
  match factor(153) {
    Some(d) => {
      assert_true(d == 3 || d == 9 || d == 17 || d == 51)
      assert_eq(153 % d, 0)
    }
    None => assert_true(false)
  }
}

///|
test "quadratic_sieve: factor 1003" {
  // 1003 = 17 × 59
  match factor(1003) {
    Some(d) => {
      assert_true(d == 17 || d == 59)
      assert_eq(1003 % d, 0)
    }
    None => assert_true(false)
  }
}

///|
test "quadratic_sieve: factor semiprime 10403" {
  // 10403 = 101 × 103 (two primes close together, ideal for QS)
  match factor(10403) {
    Some(d) => {
      assert_true(d == 101 || d == 103)
      assert_eq(10403 % d, 0)
    }
    None => assert_true(false)
  }
}

///|
test "quadratic_sieve: factor 5759" {
  // 5759 = 53 × 109 (semiprime)
  match factor(5759) {
    Some(d) => {
      assert_eq(5759 % d, 0)
      assert_true(d > 1 && d < 5759)
    }
    None => assert_true(false)
  }
}

///|
test "quadratic_sieve: perfect square" {
  // 1681 = 41²
  match factor(1681) {
    Some(d) => assert_eq(d, 41)
    None => assert_true(false)
  }
}

///|
test "quadratic_sieve: factor 65537 (prime)" {
  match factor(65537) {
    Some(_) => assert_true(false)
    None => assert_true(true)
  }
}

///|
test "quadratic_sieve: jacobi symbol" {
  assert_eq(jacobi(1, 3), 1)
  assert_eq(jacobi(2, 3), -1)
  assert_eq(jacobi(2, 7), 1)
  assert_eq(jacobi(3, 7), -1)
  assert_eq(jacobi(5, 7), -1)
}

///|
test "quadratic_sieve: tonelli_shanks" {
  // 2 is a QR mod 7: 3² = 9 ≡ 2 (mod 7)
  let r = tonelli_shanks(2, 7)
  assert_true(r == 3 || r == 4)
  // 5 is a QR mod 11: 4² = 16 ≡ 5 (mod 11)
  let r2 = tonelli_shanks(5, 11)
  assert_true(r2 == 4 || r2 == 7)
  // 3 is not a QR mod 7
  assert_eq(tonelli_shanks(3, 7), 0)
}
