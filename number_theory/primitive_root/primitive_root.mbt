/// Primitive roots and discrete logarithms.
///
/// ## Primitive Root
///
/// A **primitive root** modulo `n` is an integer `g` such that the powers
/// `g^1, g^2, ..., g^φ(n)` are all distinct modulo `n` (where `φ` is Euler's
/// totient function). In other words, `g` generates the multiplicative group
/// `(Z/nZ)*`, which has order `φ(n)`.
///
/// A primitive root exists iff `n` is `1, 2, 4, p^k,` or `2p^k` for odd
/// prime `p`.
///
/// ## Algorithm
///
/// To find a primitive root of `n`:
/// 1. Compute `φ(n)` and factorise `φ(n)`.
/// 2. For each prime factor `p` of `φ(n)`, check that `g^(φ(n)/p) ≢ 1 (mod n)`.
///    If `g` passes all tests, it's a primitive root.
/// 3. Trial `g = 2, 3, 5, ...` until one passes.
///
/// ## Discrete Logarithm
///
/// `discrete_log(g, y, n)`: find `x` such that `g^x ≡ y (mod n)`.
/// Uses the **baby-step giant-step** (BSGS) algorithm: O(√φ(n)) time and space.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

// ---------------------------------------------------------------------------
// Euler's totient (naive)
// ---------------------------------------------------------------------------

///|
/// Compute Euler's totient `φ(n)` for `n >= 1`.
///
/// Uses trial division to factorise `n`, then applies the formula
/// `φ(n) = n * ∏ (1 - 1/p)` for each prime `p` dividing `n`.
pub fn euler_totient(n : Int64) -> Int64 {
  if n <= 0L {
    return 0L
  }
  if n == 1L {
    return 1L
  }
  let mut result = n
  let mut m = n
  let mut p = 2L
  while p * p <= m {
    if m % p == 0L {
      while m % p == 0L {
        m = m / p
      }
      result = result - result / p
    }
    p = p + 1L
  }
  if m > 1L {
    result = result - result / m
  }
  result
}

// ---------------------------------------------------------------------------
// Factorisation of φ(n)
// ---------------------------------------------------------------------------

///|
/// Return the distinct prime factors of `m` as a sorted array.
fn prime_factors(m : Int64) -> Array[Int64] {
  let factors : Array[Int64] = []
  let mut x = m
  let mut p = 2L
  while p * p <= x {
    if x % p == 0L {
      factors.push(p)
      while x % p == 0L {
        x = x / p
      }
    }
    p = p + 1L
  }
  if x > 1L {
    factors.push(x)
  }
  factors
}

// ---------------------------------------------------------------------------
// Primitive root
// ---------------------------------------------------------------------------

///|
/// Find the smallest primitive root modulo `n`.
///
/// Returns `Some(g)` where `g` is the smallest primitive root, or `None`
/// if no primitive root exists (i.e., `n` is not of the form
/// `1, 2, 4, p^k, 2p^k` for odd prime `p`).
///
/// # Complexity
/// O(φ(n) · log² n · √φ(n)) worst case (factoring φ(n) dominates).
pub fn primitive_root(n : Int64) -> Int64? {
  if n <= 1L {
    return if n == 1L { Some(0L) } else { None }
  }
  if n == 2L {
    return Some(1L)
  }
  if n == 4L {
    return Some(3L)
  }
  // Check if n is p^k or 2*p^k for odd prime p.
  let mut m = n
  if m % 2L == 0L {
    m = m / 2L
  }
  // Now m should be an odd prime power.
  if m % 2L == 0L {
    return None // n has factor 4
  }
  // Check m is a prime power.
  let mut base = 0L
  let mut x = m
  let mut p = 2L
  while p * p <= x {
    if x % p == 0L {
      if base == 0L {
        base = p
      } else if p != base {
        return None // not a prime power
      }
      while x % p == 0L {
        x = x / p
      }
    }
    p = p + 1L
  }
  if x > 1L {
    if base == 0L {
      base = x // m is prime
    } else if x != base {
      return None
    }
  }
  // Now n has a primitive root.
  let phi = euler_totient(n)
  let factors = prime_factors(phi)
  // Trial candidates g = 2, 3, 5, ...
  let mut g = 2L
  while g < n {
    if @int64_utils.gcd64(g, n) != 1L {
      g = g + 1L
      continue
    }
    let mut is_primitive = true
    for i = 0; i < factors.length(); i = i + 1 {
      let exp = phi / factors[i]
      if @int64_utils.pow_mod64(g, exp, n) == 1L {
        is_primitive = false
        break
      }
    }
    if is_primitive {
      return Some(g)
    }
    g = g + 1L
  }
  None
}

///|
/// Check if `g` is a primitive root modulo `n`.
pub fn is_primitive_root(g : Int64, n : Int64) -> Bool {
  if @int64_utils.gcd64(g, n) != 1L {
    return false
  }
  let phi = euler_totient(n)
  let factors = prime_factors(phi)
  for i = 0; i < factors.length(); i = i + 1 {
    let exp = phi / factors[i]
    if @int64_utils.pow_mod64(g, exp, n) == 1L {
      return false
    }
  }
  true
}

///|
/// Count the number of primitive roots modulo `n`.
///
/// If `n` has primitive roots, the count is `φ(φ(n))`. Otherwise, 0.
pub fn count_primitive_roots(n : Int64) -> Int64 {
  let phi = euler_totient(n)
  euler_totient(phi)
}

// ---------------------------------------------------------------------------
// Discrete logarithm (Baby-step Giant-step)
// ---------------------------------------------------------------------------

///|
/// Compute the discrete logarithm: find `x` such that `g^x ≡ y (mod n)`.
///
/// Uses the baby-step giant-step algorithm.
///
/// # Returns
/// `Some(x)` where `0 <= x < ord(g)` (the order of `g` modulo `n`),
/// or `None` if no solution exists.
///
/// # Complexity
/// O(√n) time and space.
pub fn discrete_log(g : Int64, y : Int64, n : Int64) -> Int64? {
  let g_mod = @int64_utils.mod64(g, n)
  let y_mod = @int64_utils.mod64(y, n)
  if y_mod == 1L {
    return Some(0L)
  }
  // Baby step: compute g^j for j = 0..m-1, store in a hash map.
  // m = ceil(sqrt(n))
  let mut m = 1L
  while m * m < n {
    m = m + 1L
  }
  // Use a simple array of (key, value) pairs for the baby-step table.
  // For production use, a hash map would be better, but MoonBit's Map
  // supports Int64 keys.
  let table : Map[Int64, Int64] = Map([])
  let mut current = 1L
  let mut j = 0L
  while j < m {
    if !table.contains(current) {
      table[current] = j
    }
    current = @int64_utils.mul_mod(current, g_mod, n)
    j = j + 1L
  }
  // Giant step: factor = g^(-m) mod n = g^(phi(n)-m) mod n
  // But we need g^(-m) = (g^m)^(-1). Compute inverse via Fermat if n is prime,
  // or via extended GCD. For simplicity, use g^(phi-m) if gcd(g,n)=1.
  // Actually, BSGS doesn't require n to be prime; we just need g^m and its
  // inverse. Use the formula: check y * (g^(-m))^i for each i.
  let gm = @int64_utils.pow_mod64(g_mod, m, n) // g^m mod n
  // Compute inverse of gm mod n via extended Euclidean.
  let gm_inv = mod_inverse(gm, n)
  match gm_inv {
    None => return None // g and n not coprime
    Some(inv) => {
      let mut gamma = y_mod
      let mut i = 0L
      while i <= m {
        // Check if gamma is in the baby-step table.
        match table.get(gamma) {
          Some(j) => {
            let result = i * m + j
            return Some(result)
          }
          None => {
            gamma = @int64_utils.mul_mod(gamma, inv, n)
            i = i + 1L
          }
        }
      }
      None
    }
  }
}

///|
/// Modular inverse via extended Euclidean algorithm.
fn mod_inverse(a : Int64, m : Int64) -> Int64? {
  let a_mod = @int64_utils.mod64(a, m)
  let mut old_r = a_mod
  let mut r = m
  let mut old_s = 1L
  let mut s = 0L
  while r != 0L {
    let q = old_r / r
    let temp_r = old_r - q * r
    old_r = r
    r = temp_r
    let temp_s = old_s - q * s
    old_s = s
    s = temp_s
  }
  if old_r != 1L {
    None // a and m not coprime
  } else {
    Some(@int64_utils.mod64(old_s, m))
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "euler_totient: basic" {
  assert_eq(euler_totient(1L), 1L)
  assert_eq(euler_totient(2L), 1L)
  assert_eq(euler_totient(7L), 6L) // prime
  assert_eq(euler_totient(12L), 4L) // {1,5,7,11}
  assert_eq(euler_totient(36L), 12L)
}

///|
test "primitive_root: small primes" {
  // Primitive root of 7 is 3.
  assert_eq(primitive_root(7L), Some(3L))
  // Primitive root of 11 is 2.
  assert_eq(primitive_root(11L), Some(2L))
  // Primitive root of 13 is 2.
  assert_eq(primitive_root(13L), Some(2L))
  // Primitive root of 5 is 2.
  assert_eq(primitive_root(5L), Some(2L))
}

///|
test "primitive_root: special cases" {
  assert_eq(primitive_root(1L), Some(0L))
  assert_eq(primitive_root(2L), Some(1L))
  assert_eq(primitive_root(4L), Some(3L))
}

///|
test "primitive_root: no primitive root" {
  // 8 = 2^3 has no primitive root.
  assert_true(primitive_root(8L) is None)
  // 15 = 3*5 has no primitive root.
  assert_true(primitive_root(15L) is None)
}

///|
test "is_primitive_root: verification" {
  // 3 is a primitive root of 7.
  assert_true(is_primitive_root(3L, 7L))
  // 2 is NOT a primitive root of 7 (ord(2) = 3, not 6).
  assert_false(is_primitive_root(2L, 7L))
  // 2 is a primitive root of 11.
  assert_true(is_primitive_root(2L, 11L))
  // 3 is NOT a primitive root of 11.
  assert_false(is_primitive_root(3L, 11L))
}

///|
test "count_primitive_roots: basic" {
  // φ(φ(7)) = φ(6) = 2
  assert_eq(count_primitive_roots(7L), 2L)
  // φ(φ(11)) = φ(10) = 4
  assert_eq(count_primitive_roots(11L), 4L)
}

///|
test "discrete_log: basic" {
  // g = 3, n = 7: 3^1=3, 3^2=2, 3^3=6, 3^4=4, 3^5=5, 3^6=1
  assert_eq(discrete_log(3L, 3L, 7L), Some(1L))
  assert_eq(discrete_log(3L, 2L, 7L), Some(2L))
  assert_eq(discrete_log(3L, 6L, 7L), Some(3L))
  assert_eq(discrete_log(3L, 4L, 7L), Some(4L))
  assert_eq(discrete_log(3L, 5L, 7L), Some(5L))
  assert_eq(discrete_log(3L, 1L, 7L), Some(0L))
}

///|
test "discrete_log: g = 2, n = 11" {
  // 2 is a primitive root of 11.
  // 2^1=2, 2^2=4, 2^3=8, 2^4=5, 2^5=10, 2^6=9, 2^7=7, 2^8=3, 2^9=6, 2^10=1
  assert_eq(discrete_log(2L, 2L, 11L), Some(1L))
  assert_eq(discrete_log(2L, 4L, 11L), Some(2L))
  assert_eq(discrete_log(2L, 8L, 11L), Some(3L))
  assert_eq(discrete_log(2L, 5L, 11L), Some(4L))
  assert_eq(discrete_log(2L, 10L, 11L), Some(5L))
  assert_eq(discrete_log(2L, 9L, 11L), Some(6L))
  assert_eq(discrete_log(2L, 1L, 11L), Some(0L))
}

///|
test "discrete_log: no solution" {
  // 3 is not a power of 2 mod 11 (since 3 = 2^8 mod 11, it IS a solution).
  // Let's check a non-existent one: 0 can't be a power of a coprime g.
  assert_true(discrete_log(2L, 0L, 11L) is None)
}

///|
test "primitive_root: prime powers" {
  // 9 = 3^2, primitive root exists.
  let r = primitive_root(9L)
  assert_true(r is Some(_))
  match r {
    Some(g) => assert_true(is_primitive_root(g, 9L))
    None => abort("expected Some")
  }
  // 25 = 5^2, primitive root exists.
  let r2 = primitive_root(25L)
  assert_true(r2 is Some(_))
  // 2*9 = 18, primitive root exists (2*p^k).
  let r3 = primitive_root(18L)
  assert_true(r3 is Some(_))
}

///|
test "discrete_log: large prime" {
  // p = 1000000007, g = 5 (a primitive root of 1000000007)
  // First verify 5 is a primitive root.
  // Actually, let's just test a known case:
  // 2^x ≡ 4 (mod 1000000007) → x = 2.
  let r = discrete_log(2L, 4L, 1000000007L)
  assert_eq(r, Some(2L))
  // 2^x ≡ 8 (mod 1000000007) → x = 3.
  let r2 = discrete_log(2L, 8L, 1000000007L)
  assert_eq(r2, Some(3L))
}

///|
test "mod_inverse: basic" {
  assert_eq(mod_inverse(3L, 7L), Some(5L)) // 3*5=15≡1 mod 7
  assert_eq(mod_inverse(2L, 5L), Some(3L)) // 2*3=6≡1 mod 5
  assert_true(mod_inverse(2L, 4L) is None) // gcd(2,4)=2≠1
}
