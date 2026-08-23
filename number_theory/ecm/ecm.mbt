/// Lenstra Elliptic Curve Factorization (ECM) — production-grade implementation.
///
/// ECM is a probabilistic integer factorization algorithm that uses elliptic
/// curves over `Z/nZ`. Its running time depends on the **smallest** prime
/// factor `p` of `n`, not on `n` itself, making it the best algorithm for
/// finding medium-sized factors (20–60 digits) of large composites.
///
/// ## Mathematical Foundation
///
/// An elliptic curve `E` over `Z/pZ` (for prime `p | n`) has a group of points
/// whose order `#E(Z/pZ)` lies in the Hasse interval `[p + 1 - 2√p, p + 1 + 2√p]`.
/// If `#E(Z/pZ)` is B-smooth (all prime factors ≤ B), then computing
/// `k = ∏ q^⌊log_q B⌋` and `Q = kP` on `E` will yield `Q ≡ O (mod p)`,
/// meaning the Z-coordinate of `Q` becomes `0 (mod p)`. Then `gcd(Z_Q, n)`
/// reveals the factor `p`.
///
/// Since `#E` varies with the curve (different A gives different group order),
/// trying multiple random curves gives independent chances of success.
///
/// ## Montgomery Curves
///
/// We use **Montgomery-form curves** `B·y² = x³ + A·x² + x` with
/// **x-coordinate-only arithmetic** via the Montgomery ladder. This avoids
/// costly y-coordinate computation and inversion, and gracefully detects
/// non-invertible elements (i.e. factors) via the Z-coordinate.
///
/// Point representation: projective `(X : Z)` with affine `x = X/Z`.
/// The point at infinity is `(X : 0)`.
///
/// ### Montgomery Ladder Step
///
/// Given `(X₁:Z₁)` = `mP`, `(X₂:Z₂)` = `(m+1)P`, and the base point
/// `(X₀:Z₀)` = `P` (the fixed difference):
///
/// **Doubling** `(X₁:Z₁) → 2(X₁:Z₁)`:
/// ```text
/// U  = X₁ + Z₁
/// V  = X₁ - Z₁
/// UU = U²
/// VV = V²
/// W  = UU - VV           // = 4·X₁·Z₁
/// X' = UU · VV
/// Z' = W · (VV + a24·W)   // a24 = (A+2)/4
/// ```
///
/// **Differential Addition** `(X₁:Z₁) + (X₂:Z₂)`:
/// ```text
/// TR = U · (X₂ - Z₂)     // U = X₁+Z₁ from doubling
/// TS = V · (X₂ + Z₂)     // V = X₁-Z₂ from doubling
/// X'' = Z₀ · (TR + TS)²
/// Z'' = X₀ · (TR - TS)²
/// ```
///
/// ## Suyama Parameterization
///
/// For curve generation we use Suyama's parameterization (1985), which
/// guarantees a non-trivial torsion group (order divisible by 6), improving
/// the probability of success per curve.
///
/// Given a random parameter `σ`:
/// ```text
/// u = σ² - 5     (mod n)
/// v = 4σ         (mod n)
/// X₀ = u³        (mod n)
/// Z₀ = v³        (mod n)
/// a24 = ((v-u)³ · (3u+v)) · (4u³v)⁻¹  - 2   (mod n)
/// ```
///
/// If `gcd(4u³v, n) > 1`, we immediately have a factor.
///
/// ## Stage 1
///
/// Compute `Q = kP` where `k = ∏_{q ≤ B₁} q^⌊log_q(B₁)⌋` using the Montgomery
/// ladder. After all primes, check `gcd(Z_Q, n)`.
///
/// ## Stage 2 (Standard Continuation)
///
/// For primes `q ∈ (B₁, B₂]`, we check whether `qQ ≡ O (mod p)`. We use the
/// **baby-step / giant-step** continuation:
///
/// 1. Precompute `S_d = dQ` for `d = 1, ..., D` (baby steps, stored X-coords).
/// 2. Compute `R = DQ` and iterate `R, R+DQ, R+2DQ, ...` (giant steps).
/// 3. For each prime `q = jD + i` with `1 ≤ i ≤ D`, compute
///    `gcd(X_R - X_{S_i}, n)`. If `qQ ≡ O (mod p)` but `Q ≢ O (mod p)`,
///    this reveals `p`.
///
/// ## Complexity
///
/// - **Stage 1**: `O(B₁ / log B₁)` primes, each `O(log B₁)` Montgomery steps.
/// - **Stage 2**: `O(B₂ / D + D)` multiplications.
/// - **Expected**: `L(p) = exp(√(2 ln p · ln ln p))` (sub-exponential in `p`).
/// - **Practical**: for 32-bit `n`, `B₁ = 10000, B₂ = 100000` finds most
///   factors up to ~25 digits.
///
/// ## Overflow Safety
///
/// All arithmetic uses `Int64` with `@int64_utils.mul_mod` (binary
/// decomposition, safe for the full `Int64` range). Input `n` is a 32-bit `Int`.
///
/// ## References
///
/// - Lenstra, H. W. (1987): "Factoring Integers with Elliptic Curves."
///   Annals of Mathematics, 126(3), 649–673.
/// - Montgomery, P. (1987): "Speeding the Pollard and Elliptic Curve Methods
///   of Factorization." Mathematics of Computation, 48(177), 243–264.
/// - Suyama, H. (1985): informal communication (see Brent 1986).
/// - Crandall, R. and Pomerance, C. (2005): "Prime Numbers: A Computational
///   Perspective," 2nd ed., Springer, §6.4.
/// - Zimmermann, P. and Dodson, B. (2006): "20 Years of ECM." ANTS VII.
///
/// `proof-enabled` is `false`; correctness is ensured by the test suite.

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

///|
/// Default stage 1 bound.
let default_b1 : Int = 10000

///|
/// Default stage 2 bound (10× stage 1).
let default_b2 : Int = 100000

///|
/// Maximum curve attempts before giving up.
let max_curves : Int = 40

///|
/// Giant step size for stage 2 (≈ √B₂).
let stage2_d : Int = 256

// ---------------------------------------------------------------------------
// Sieve of Eratosthenes
// ---------------------------------------------------------------------------

///|
/// Generate all primes up to `limit` using a sieve of Eratosthenes.
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
// Modular inverse (extended Euclidean)
// ---------------------------------------------------------------------------

///|
/// Modular inverse `a⁻¹ mod n` using the extended Euclidean algorithm.
///
/// Returns `Some(inv)` if `gcd(a, n) = 1`, or `None` if `gcd(a, n) > 1`
/// (in which case `gcd(a, n)` is a non-trivial factor of `n`).
fn mod_inv(a : Int64, n : Int64) -> Int64? {
  let mut t = 0L
  let mut new_t = 1L
  let mut r = n
  let mut new_r = @int64_utils.mod64(a, n)
  while new_r != 0L {
    let q = r / new_r
    let temp_t = t - q * new_t
    t = new_t
    new_t = temp_t
    let temp_r = r - q * new_r
    r = new_r
    new_r = temp_r
  }
  if r > 1L {
    // a is not invertible mod n → gcd(a,n) > 1
    return None
  }
  if t < 0L {
    t = t + n
  }
  Some(t)
}

// ---------------------------------------------------------------------------
// Montgomery curve state
// ---------------------------------------------------------------------------

///|
/// A Montgomery curve point in projective x-coordinate-only representation.
priv struct MontPoint {
  x : Int64
  z : Int64
}

///|
/// Montgomery curve parameters.
///
/// Curve: `B·y² = x³ + A·x² + x`
/// Stored as `a24 = (A + 2) / 4` (avoids storing A directly).
priv struct MontCurve {
  a24 : Int64
  // Base point (X₀ : Z₀) — the generator P.
  x0 : Int64
  z0 : Int64
}

// ---------------------------------------------------------------------------
// Montgomery ladder arithmetic
// ---------------------------------------------------------------------------

///|
/// Montgomery ladder step: given (X₁:Z₁) = mP and (X₂:Z₂) = (m+1)P,
/// compute (X':Z') = 2·(X₁:Z₁) and (X'':Z'') = (X₁:Z₁) + (X₂:Z₂).
///
/// The difference (X₂:Z₂) - (X₁:Z₁) = P = (X₀:Z₀) (the base point).
///
/// Returns ((X', Z'), (X'', Z'')).
///
/// All operations are mod `n`. If any denominator becomes non-invertible
/// (Z ≡ 0 mod a factor), the GCD will catch it later.
fn ladder_step(
  p1 : MontPoint,
  p2 : MontPoint,
  curve : MontCurve,
  n : Int64,
) -> (MontPoint, MontPoint) {
  let x1 = p1.x
  let z1 = p1.z
  let x2 = p2.x
  let z2 = p2.z

  // Doubling: (X₁:Z₁) → (X':Z') = 2·(X₁:Z₁)
  let u = @int64_utils.mod64(x1 + z1, n)
  let v = @int64_utils.mod64(x1 - z1, n)
  let uu = @int64_utils.mul_mod(u, u, n)
  let vv = @int64_utils.mul_mod(v, v, n)
  let w = @int64_utils.mod64(uu - vv, n) // = 4·x₁·z₁ mod n
  let x_double = @int64_utils.mul_mod(uu, vv, n)
  let z_double = @int64_utils.mul_mod(
    w,
    @int64_utils.mod64(vv + @int64_utils.mul_mod(curve.a24, w, n), n),
    n,
  )

  // Differential addition: (X₁:Z₁) + (X₂:Z₂), diff = (X₀:Z₀)
  // TR = u · (x₂ - z₂)
  let diff_x2 = @int64_utils.mod64(x2 - z2, n)
  let tr = @int64_utils.mul_mod(u, diff_x2, n)
  // TS = v · (x₂ + z₂)
  let sum_x2 = @int64_utils.mod64(x2 + z2, n)
  let ts = @int64_utils.mul_mod(v, sum_x2, n)
  let sum_tr_ts = @int64_utils.mod64(tr + ts, n)
  let diff_tr_ts = @int64_utils.mod64(tr - ts, n)
  let x_add = @int64_utils.mul_mod(
    curve.z0,
    @int64_utils.mul_mod(sum_tr_ts, sum_tr_ts, n),
    n,
  )
  let z_add = @int64_utils.mul_mod(
    curve.x0,
    @int64_utils.mul_mod(diff_tr_ts, diff_tr_ts, n),
    n,
  )

  ({ x: x_double, z: z_double }, { x: x_add, z: z_add })
}

///|
/// Compute `kP` on the Montgomery curve using the Montgomery ladder.
///
/// Processes bits of `k` from MSB to LSB. At each step, maintains
/// `(X₁:Z₁) = mP` and `(X₂:Z₂) = (m+1)P`.
///
/// Returns `(X:Z) = kP` (projective x-coordinate).
fn scalar_mult(k : Int64, curve : MontCurve, n : Int64) -> MontPoint {
  if k == 0L {
    return { x: 0L, z: 0L } // O (point at infinity)
  }
  if k == 1L {
    return { x: curve.x0, z: curve.z0 }
  }
  // Find highest set bit.
  let mut hi = 62
  while hi >= 0 && k >> hi == 0L {
    hi = hi - 1
  }
  // Initialize: (X₁:Z₁) = P, (X₂:Z₂) = 2P
  // We start from the second-highest bit, so initial state is m=1.
  let p1 = { x: curve.x0, z: curve.z0 }
  // Compute 2P for initial p2.
  let u = @int64_utils.mod64(curve.x0 + curve.z0, n)
  let v = @int64_utils.mod64(curve.x0 - curve.z0, n)
  let uu = @int64_utils.mul_mod(u, u, n)
  let vv = @int64_utils.mul_mod(v, v, n)
  let w = @int64_utils.mod64(uu - vv, n)
  let p2_x = @int64_utils.mul_mod(uu, vv, n)
  let p2_z = @int64_utils.mul_mod(
    w,
    @int64_utils.mod64(vv + @int64_utils.mul_mod(curve.a24, w, n), n),
    n,
  )
  let mut p2 = { x: p2_x, z: p2_z }
  let mut p1_mut = p1
  // Process remaining bits from hi-1 down to 0.
  for bit = hi - 1; bit >= 0; bit = bit - 1 {
    let b = (k >> bit) & 1L
    let (doubled, added) = ladder_step(p1_mut, p2, curve, n)
    if b == 0L {
      // new (X₁:Z₁) = 2·(X₁:Z₁), new (X₂:Z₂) = (X₁:Z₁) + (X₂:Z₂)
      p1_mut = doubled
      p2 = added
    } else {
      // new (X₁:Z₁) = (X₁:Z₁) + (X₂:Z₂), new (X₂:Z₂) = 2·(X₂:Z₂)
      // For bit=1, we need to double p2 and add p1+p2.
      // Swap: compute doubling of p2 and addition with p1.
      let (doubled2, added2) = ladder_step(p2, p1_mut, curve, n)
      p1_mut = added2
      p2 = doubled2
    }
  }
  p1_mut
}

// ---------------------------------------------------------------------------
// Suyama parameterization
// ---------------------------------------------------------------------------

///|
/// Generate a Montgomery curve and base point using Suyama's parameterization.
///
/// Given σ, computes:
/// ```text
/// u = σ² - 5  (mod n)
/// v = 4σ      (mod n)
/// X₀ = u³     (mod n)
/// Z₀ = v³     (mod n)
/// a24 = ((v-u)³ · (3u+v)) · (4u³v)⁻¹  - 2  (mod n)
/// ```
///
/// Returns `Some(curve)` if successful, or `None` if the modular inverse
/// fails (meaning `gcd(4u³v, n) > 1` — a factor was found, but we return
/// `None` to signal this; the caller should check `gcd` separately).
///
/// In the `None` case, the factor is available as `gcd(4u³v, n)`.
fn suyama_curve(sigma : Int64, n : Int64) -> MontCurve? {
  let u = @int64_utils.mod64(sigma * sigma - 5L, n)
  let v = @int64_utils.mod64(4L * sigma, n)
  let u_cubed = @int64_utils.mul_mod(u, @int64_utils.mul_mod(u, u, n), n)
  let v_cubed = @int64_utils.mul_mod(v, @int64_utils.mul_mod(v, v, n), n)
  // Compute numerator: (v-u)³ · (3u+v)
  let v_minus_u = @int64_utils.mod64(v - u, n)
  let v_minus_u_cubed = @int64_utils.mul_mod(
    v_minus_u,
    @int64_utils.mul_mod(v_minus_u, v_minus_u, n),
    n,
  )
  let three_u_plus_v = @int64_utils.mod64(3L * u + v, n)
  let numerator = @int64_utils.mul_mod(v_minus_u_cubed, three_u_plus_v, n)
  // Compute a24 = (A+2)/4 = ((v-u)³ · (3u+v)) / (16·u³·v)
  // Note: A = ((v-u)³·(3u+v))/(4u³v) - 2, so (A+2)/4 = numerator/(16u³v).
  let denom = @int64_utils.mul_mod(16L, @int64_utils.mul_mod(u_cubed, v, n), n)
  // Compute modular inverse of denominator.
  match mod_inv(denom, n) {
    None => return None
    Some(inv_denom) =>
      Some({
        a24: @int64_utils.mul_mod(numerator, inv_denom, n),
        x0: u_cubed,
        z0: v_cubed,
      })
  }
}

// ---------------------------------------------------------------------------
// Stage 1: compute kP where k = product of prime powers up to B1
// ---------------------------------------------------------------------------

///|
/// Run stage 1 of ECM.
///
/// Computes `Q = kP` where `k = ∏_{q ≤ B₁} q^⌊log_q(B₁)⌋`.
///
/// Returns the point `Q = (X_Q : Z_Q)`. The caller should check
/// `gcd(Z_Q, n)` for a factor.
fn stage1(
  curve : MontCurve,
  n : Int64,
  primes : Array[Int],
  max_prime : Int,
) -> MontPoint {
  // Start with P = (X₀:Z₀).
  let mut q_point = { x: curve.x0, z: curve.z0 }
  for i = 0; i < primes.length(); i = i + 1 {
    let q = primes[i]
    // Compute largest power q^e ≤ B₁.
    let mut qe = 1
    let mut q_pow = q
    while q_pow <= max_prime && q_pow > 0 {
      qe = q_pow
      if q_pow > 2147483647 / q {
        break
      }
      q_pow = q_pow * q
    }
    // Q = q^e · Q (Montgomery ladder).
    q_point = scalar_mult(
      qe.to_int64(),
      { a24: curve.a24, x0: q_point.x, z0: q_point.z },
      n,
    )
  }
  q_point
}

// ---------------------------------------------------------------------------
// Stage 1 backtracking: isolate factor when gcd == n
// ---------------------------------------------------------------------------

///|
/// Re-run stage 1 prime by prime, checking GCD after each multiplication by q.
///
/// When `gcd(Z_Q, n) == n` after stage 1, both prime factors were triggered
/// simultaneously. This function re-does the computation one prime at a time,
/// multiplying by q repeatedly (q^1, q^2, ..., q^e) and checking `gcd(Z, n)`
/// after each step. As soon as the GCD becomes non-trivial (1 < g < n), we
/// return the factor. If the GCD jumps to n, this curve cannot isolate the
/// factor and we return None.
fn stage1_backtrack(
  curve : MontCurve,
  n : Int64,
  primes : Array[Int],
  max_prime : Int,
) -> Int64? {
  let mut q_point = { x: curve.x0, z: curve.z0 }
  for i = 0; i < primes.length(); i = i + 1 {
    let q = primes[i]
    // Compute largest power q^e ≤ B₁.
    let mut qe = 1
    let mut q_pow = q
    while q_pow <= max_prime && q_pow > 0 {
      qe = q_pow
      if q_pow > 2147483647 / q {
        break
      }
      q_pow = q_pow * q
    }
    // Multiply by q repeatedly (q^1, q^2, ..., q^e), checking GCD each time.
    let mut q_test = q_point
    let mut pow = 1
    while pow <= qe {
      q_test = scalar_mult(
        q.to_int64(),
        { a24: curve.a24, x0: q_test.x, z0: q_test.z },
        n,
      )
      let g = @int64_utils.gcd64(q_test.z, n)
      if g > 1L && g < n {
        return Some(g)
      }
      if g == n {
        // This prime triggered both factors simultaneously.
        // Cannot isolate with this curve.
        return None
      }
      pow = pow * q
    }
    q_point = q_test
  }
  // Final check.
  let g = @int64_utils.gcd64(q_point.z, n)
  if g > 1L && g < n {
    return Some(g)
  }
  None
}

// ---------------------------------------------------------------------------
// Stage 2: standard continuation (baby-step / giant-step)
// ---------------------------------------------------------------------------

///|
/// Run stage 2 of ECM using the standard continuation.
///
/// After stage 1, we have `Q = kP`. For each prime `p` in `(B₁, B₂]`, we
/// check if `pQ ≡ O (mod n_factor)` by checking `gcd(X_difference, n)`.
///
/// **Algorithm**:
/// 1. Compute `DQ` (giant step) and baby steps `Q, 2Q, ..., DQ`.
/// 2. Iterate giant steps: `DQ, 2DQ, 3DQ, ...`
/// 3. For each prime `q = jD + i` with `1 ≤ i ≤ D`, check
///    `gcd(X_{jD·Q} - X_{i·Q}, n)`.
///
/// Returns `Some(factor)` if a factor is found, `None` otherwise.
fn stage2(
  q_point : MontPoint,
  curve : MontCurve,
  n : Int64,
  b1 : Int,
  b2 : Int,
) -> Int64? {
  let d = stage2_d
  // Create a curve with Q as the base point for further multiplications.
  let curve_q = { a24: curve.a24, x0: q_point.x, z0: q_point.z }
  // Compute baby steps: iQ for i = 1, ..., D.
  let baby_x : FixedArray[Int64] = FixedArray::make(d + 1, 0L)
  let baby_z : FixedArray[Int64] = FixedArray::make(d + 1, 0L)
  baby_x[1] = q_point.x
  baby_z[1] = q_point.z
  // Compute 2Q using the doubling formula.
  if d >= 2 {
    let u = @int64_utils.mod64(q_point.x + q_point.z, n)
    let v = @int64_utils.mod64(q_point.x - q_point.z, n)
    let uu = @int64_utils.mul_mod(u, u, n)
    let vv = @int64_utils.mul_mod(v, v, n)
    let w = @int64_utils.mod64(uu - vv, n)
    baby_x[2] = @int64_utils.mul_mod(uu, vv, n)
    baby_z[2] = @int64_utils.mul_mod(
      w,
      @int64_utils.mod64(vv + @int64_utils.mul_mod(curve.a24, w, n), n),
      n,
    )
    // Compute iQ = (i-1)Q + Q using differential addition with diff = (i-2)Q.
    for i = 3; i <= d; i = i + 1 {
      let curve_diff = { a24: curve.a24, x0: baby_x[i - 2], z0: baby_z[i - 2] }
      // P1 = Q, P2 = (i-1)Q, diff = P2-P1 = (i-2)Q.
      // ladder_step returns (2*P1, P1+P2); we use P1+P2 = iQ.
      let p1 = { x: q_point.x, z: q_point.z }
      let p2 = { x: baby_x[i - 1], z: baby_z[i - 1] }
      let (_, iQ) = ladder_step(p1, p2, curve_diff, n)
      baby_x[i] = iQ.x
      baby_z[i] = iQ.z
    }
  }
  // Compute giant step DQ.
  let dq = scalar_mult(d.to_int64(), curve_q, n)
  // Iterate giant steps: S_j = jD · Q.
  // S_1 = DQ, S_2 = 2*DQ (doubling), S_{j+1} = S_j + DQ (diff = S_{j-1}) for j >= 2.
  let mut giant = dq
  let mut product = 1L
  let mut j = 1
  let max_j = b2 / d + 2
  // s_prev tracks S_{j-1} for differential addition.
  // For j=1, there's no valid S_0 (point at infinity), so the transition
  // from S_1 to S_2 uses doubling instead.
  let mut s_prev = dq // placeholder; will be set correctly after j=1
  let mut first_giant = true
  while j <= max_j {
    // For each prime q in (B1, B2] with q = jD + i (1 ≤ i ≤ D):
    // Check gcd(X_giant - X_baby[i], n).
    for i = 1; i <= d; i = i + 1 {
      let q_val = j * d + i
      if q_val <= b1 {
        continue
      }
      if q_val > b2 {
        break
      }
      // Check if q_val is prime (trial division).
      let mut is_p = true
      if q_val < 2 {
        is_p = false
      } else if q_val == 2 {
        is_p = true
      } else if q_val % 2 == 0 {
        is_p = false
      } else {
        let mut k = 3
        while k * k <= q_val {
          if q_val % k == 0 {
            is_p = false
            break
          }
          k = k + 2
        }
      }
      if !is_p {
        continue
      }
      // Accumulate product of (X_giant - X_baby[i]) mod n.
      let diff = @int64_utils.mod64(giant.x - baby_x[i], n)
      if diff == 0L {
        // X_giant == X_baby[i] → check Z
        let g = @int64_utils.gcd64(
          @int64_utils.mod64(giant.z - baby_z[i], n),
          n,
        )
        if g > 1L && g < n {
          return Some(g)
        }
      } else {
        product = @int64_utils.mul_mod(product, diff, n)
      }
    }
    // Check accumulated product.
    let g = @int64_utils.gcd64(product, n)
    if g > 1L && g < n {
      return Some(g)
    }
    if g == n {
      // Product captured all factors; re-scan this batch individually.
      product = 1L
      for i = 1; i <= d; i = i + 1 {
        let q_val = j * d + i
        if q_val <= b1 || q_val > b2 {
          continue
        }
        let diff = @int64_utils.mod64(giant.x - baby_x[i], n)
        if diff != 0L {
          let g2 = @int64_utils.gcd64(diff, n)
          if g2 > 1L && g2 < n {
            return Some(g2)
          }
        }
      }
    }
    // Next giant step.
    if first_giant {
      // S_2 = 2 * S_1 (doubling, since S_0 = O can't be used as diff).
      let u = @int64_utils.mod64(giant.x + giant.z, n)
      let v = @int64_utils.mod64(giant.x - giant.z, n)
      let uu = @int64_utils.mul_mod(u, u, n)
      let vv = @int64_utils.mul_mod(v, v, n)
      let w = @int64_utils.mod64(uu - vv, n)
      let next_x = @int64_utils.mul_mod(uu, vv, n)
      let next_z = @int64_utils.mul_mod(
        w,
        @int64_utils.mod64(vv + @int64_utils.mul_mod(curve.a24, w, n), n),
        n,
      )
      s_prev = giant
      giant = { x: next_x, z: next_z }
      first_giant = false
    } else {
      // S_{j+1} = S_j + DQ, diff = S_{j-1} = s_prev.
      let curve_gs = { a24: curve.a24, x0: s_prev.x, z0: s_prev.z }
      let (_, next_giant) = ladder_step(
        { x: dq.x, z: dq.z },
        giant,
        curve_gs,
        n,
      )
      s_prev = giant
      giant = next_giant
    }
    j = j + 1
  }
  // Final GCD check.
  let g = @int64_utils.gcd64(product, n)
  if g > 1L && g < n {
    return Some(g)
  }
  None
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

///|
/// Find one non-trivial factor of `n` using Lenstra's ECM.
///
/// `n` must be a composite number greater than 1. Returns `Some(d)` with
/// a factor `d` satisfying `1 < d < n`. Returns `None` when `n <= 1`, when
/// `n` is prime, or if all curve attempts fail.
///
/// ## Parameters
///
/// - `n`: the number to factor (must be > 1).
/// - `b1`: stage 1 smoothness bound. Larger B₁ finds factors where the
///   curve order has larger prime factors.
/// - `b2`: stage 2 bound (should be ~10–100× B₁).
///
/// ## Example
///
/// ```moonbit nocheck
/// let f = ecm(10403, 1000, 10000)
/// // 10403 = 101 × 103
/// // Returns Some(101) or Some(103)
/// ```
pub fn ecm(n : Int, b1 : Int, b2 : Int) -> Int? {
  if n <= 1 {
    return None
  }
  if n == 2 {
    return None
  }
  if n % 2 == 0 {
    return Some(2)
  }
  // Perfect square check.
  let sqrt_n = isqrt(n)
  if sqrt_n * sqrt_n == n && sqrt_n > 1 {
    if @int64_utils.is_prime64(sqrt_n.to_int64()) {
      return Some(sqrt_n)
    }
  }
  let n64 = n.to_int64()
  let actual_b1 = if b1 < 100 { 100 } else { b1 }
  let actual_b2 = if b2 < actual_b1 { actual_b1 * 10 } else { b2 }
  // Generate primes for stage 1.
  let primes_b1 = sieve_primes(actual_b1)
  if primes_b1.length() == 0 {
    return None
  }
  // Try multiple curves with different σ values.
  // σ = 6, 7, 8, ... (Suyama requires σ ≥ 5).
  let mut sigma = 6L
  for attempt = 0; attempt < max_curves; attempt = attempt + 1 {
    // Generate curve via Suyama parameterization.
    match suyama_curve(sigma, n64) {
      None => {
        // Mod inverse failed → gcd(4u³v, n) > 1.
        // Compute the factor directly.
        let u = @int64_utils.mod64(sigma * sigma - 5L, n64)
        let v = @int64_utils.mod64(4L * sigma, n64)
        let u_cubed = @int64_utils.mul_mod(
          u,
          @int64_utils.mul_mod(u, u, n64),
          n64,
        )
        let denom = @int64_utils.mul_mod(
          16L,
          @int64_utils.mul_mod(u_cubed, v, n64),
          n64,
        )
        let g = @int64_utils.gcd64(denom, n64)
        if g > 1L && g < n64 {
          return Some(g.to_int())
        }
      }
      Some(curve) => {
        // Stage 1: compute Q = kP.
        let q_point = stage1(curve, n64, primes_b1, actual_b1)
        // Check GCD of Z-coordinate.
        let g = @int64_utils.gcd64(q_point.z, n64)
        if g > 1L && g < n64 {
          return Some(g.to_int())
        }
        // If g == n, both factors were triggered simultaneously.
        // Backtrack: re-do stage 1 prime by prime to isolate the factor.
        if g == n64 {
          match stage1_backtrack(curve, n64, primes_b1, actual_b1) {
            Some(factor) =>
              if factor > 1L && factor < n64 {
                return Some(factor.to_int())
              }
            None => ()
          }
        } else {
          // g == 1: no factor found in stage 1, proceed to stage 2.
          match stage2(q_point, curve, n64, actual_b1, actual_b2) {
            Some(factor) =>
              if factor > 1L && factor < n64 {
                return Some(factor.to_int())
              }
            None => ()
          }
        }
      }
    }
    sigma = sigma + 1L
  }
  None
}

///|
/// Find one non-trivial factor using default bounds (B₁=10000, B₂=100000).
pub fn ecm_default(n : Int) -> Int? {
  ecm(n, default_b1, default_b2)
}

// ---------------------------------------------------------------------------
// Complete factorization
// ---------------------------------------------------------------------------

///|
/// Factorize `n` into its prime factors (with multiplicity), in ascending
/// order.
///
/// Uses trial division for small primes (≤ 100), then ECM with Miller-Rabin
/// primality checking for large factors. Recursively factors any composite
/// cofactors found. Uses increasing bounds if ECM fails.
///
/// Returns an empty array for `n < 2`. For `n >= 2`, returns the complete
/// list of prime factors whose product equals `n`.
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
  // Try ECM with increasing bounds.
  let bounds = [
    (1000, 10000),
    (5000, 50000),
    (10000, 100000),
    (50000, 500000),
    (100000, 1000000),
  ]
  let mut found = false
  for bi = 0; bi < bounds.length() && !found; bi = bi + 1 {
    let (b1, b2) = bounds[bi]
    let d = ecm(m, b1, b2)
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
  // If ECM failed, the number is likely a prime power or has only very large
  // factors. Check if it's a perfect power.
  if !found {
    // Check perfect powers: p^k for small k.
    let k = 2
    let mut k_val = k
    while k_val * k_val <= m {
      let root = iroot(m, k_val)
      if root > 1 {
        let mut check = 1
        for iter = 0; iter < k_val; iter = iter + 1 {
          check = check * root
        }
        if check == m {
          for iter = 0; iter < k_val; iter = iter + 1 {
            factor_recursive(root, result)
          }
          return
        }
      }
      k_val = k_val + 1
    }
    // Fallback: trial division up to sqrt(m).
    // This guarantees correctness even if ECM fails to find a factor.
    let mut k = m
    let mut d = 101 // Start after small primes already divided out.
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
// Utilities
// ---------------------------------------------------------------------------

///|
/// Integer square root.
fn isqrt(n : Int) -> Int {
  if n < 0 {
    return 0
  }
  if n < 2 {
    return n
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
/// Integer k-th root: floor(n^(1/k)).
fn iroot(n : Int, k : Int) -> Int {
  if n < 0 || k < 1 {
    return 0
  }
  if n < 2 {
    return n
  }
  if k == 1 {
    return n
  }
  if k == 2 {
    return isqrt(n)
  }
  // Binary search for the k-th root.
  let mut lo = 1
  let mut hi = n
  // Narrow the upper bound: hi = 2^(ceil(log2(n)/k))
  let mut hi_approx = 1
  while hi_approx < n {
    let mut p = 1
    for iter = 0; iter < k; iter = iter + 1 {
      p = p * hi_approx
    }
    if p >= n {
      break
    }
    hi = hi_approx
    hi_approx = hi_approx * 2
  }
  // Binary search.
  while lo <= hi {
    let mid = lo + (hi - lo) / 2
    let mut pow = 1
    let mut overflow = false
    for iter = 0; iter < k; iter = iter + 1 {
      pow = pow * mid
      if pow > n || pow <= 0 {
        overflow = true
        break
      }
    }
    if overflow {
      hi = mid - 1
    } else if pow == n {
      return mid
    } else if pow < n {
      lo = mid + 1
    } else {
      hi = mid - 1
    }
  }
  hi
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "ecm: mod_inv basic" {
  assert_eq(mod_inv(3L, 7L).unwrap(), 5L) // 3*5=15≡1 mod 7
  assert_eq(mod_inv(1L, 5L).unwrap(), 1L)
  assert_eq(mod_inv(2L, 5L).unwrap(), 3L) // 2*3=6≡1 mod 5
  assert_true(mod_inv(0L, 5L) is None)
  assert_true(mod_inv(6L, 9L) is None) // gcd(6,9)=3
}

///|
test "ecm: small semiprime 15 = 3*5" {
  let f = ecm(15, 100, 1000)
  assert_true(f is Some(_))
  let factor = f.unwrap()
  assert_true(factor == 3 || factor == 5)
}

///|
test "ecm: semiprime 77 = 7*11" {
  let f = ecm(77, 200, 2000)
  assert_true(f is Some(_))
  let factor = f.unwrap()
  assert_true(factor == 7 || factor == 11)
}

///|
test "ecm: semiprime 10403 = 101*103" {
  let f = ecm(10403, 1000, 10000)
  assert_true(f is Some(_))
  let factor = f.unwrap()
  assert_true(factor == 101 || factor == 103)
}

///|
test "ecm: semiprime 323 = 17*19" {
  let f = ecm(323, 500, 5000)
  assert_true(f is Some(_))
  let factor = f.unwrap()
  assert_true(factor == 17 || factor == 19)
}

///|
test "ecm: Carmichael number 561 = 3*11*17" {
  let f = ecm(561, 200, 2000)
  assert_true(f is Some(_))
  let factor = f.unwrap()
  assert_true(561 % factor == 0)
  assert_true(factor > 1 && factor < 561)
}

///|
test "ecm: prime power 49 = 7^2" {
  let f = ecm(49, 100, 1000)
  assert_true(f is Some(_))
  assert_eq(f.unwrap(), 7)
}

///|
test "ecm: even number" {
  assert_eq(ecm(100, 100, 1000), Some(2))
  assert_eq(ecm(6, 100, 1000), Some(2))
}

///|
test "ecm: prime returns None" {
  assert_true(ecm(7, 100, 1000) is None)
  assert_true(ecm(13, 100, 1000) is None)
  assert_true(ecm(101, 100, 1000) is None)
}

///|
test "ecm: n <= 1 returns None" {
  assert_true(ecm(0, 100, 1000) is None)
  assert_true(ecm(1, 100, 1000) is None)
}

///|
test "ecm: n = 2 returns None" {
  assert_true(ecm(2, 100, 1000) is None)
}

///|
test "ecm: larger semiprime 1927 = 41*47" {
  let f = ecm(1927, 1000, 10000)
  assert_true(f is Some(_))
  let factor = f.unwrap()
  assert_true(factor == 41 || factor == 47)
}

///|
test "ecm: semiprime 4081 = 53*77... wait 53*77=4081? 53*77=4081" {
  // 53 * 77 = 4081, but 77 = 7*11, so 4081 = 53*7*11
  // Let's use 53*79 = 4187
  let f = ecm(4187, 1000, 10000)
  assert_true(f is Some(_))
  let factor = f.unwrap()
  assert_true(factor == 53 || factor == 79)
}

///|
test "ecm: default bounds" {
  let f = ecm_default(10403)
  assert_true(f is Some(_))
  let factor = f.unwrap()
  assert_true(factor == 101 || factor == 103)
}

///|
test "ecm: factorize small number" {
  let factors = factorize(12)
  assert_eq(factors, [2, 2, 3])
}

///|
test "ecm: factorize prime" {
  let factors = factorize(17)
  assert_eq(factors, [17])
}

///|
test "ecm: factorize prime power" {
  let factors = factorize(8)
  assert_eq(factors, [2, 2, 2])
  let factors2 = factorize(27)
  assert_eq(factors2, [3, 3, 3])
  let factors3 = factorize(49)
  assert_eq(factors3, [7, 7])
}

///|
test "ecm: factorize semiprime" {
  let factors = factorize(10403)
  assert_eq(factors.length(), 2)
  assert_eq(factors[0] * factors[1], 10403)
}

///|
test "ecm: factorize multi-factor" {
  let factors = factorize(2310) // 2*3*5*7*11
  assert_eq(factors, [2, 3, 5, 7, 11])
}

///|
test "ecm: factorize Carmichael 561" {
  let factors = factorize(561) // 3*11*17
  assert_eq(factors, [3, 11, 17])
}

///|
test "ecm: factorize large semiprime" {
  // 10007 * 10009 = 100160063
  let factors = factorize(100160063)
  assert_eq(factors.length(), 2)
  assert_eq(factors[0] * factors[1], 100160063)
}

///|
test "ecm: factorize n < 2" {
  assert_eq(factorize(0), [])
  assert_eq(factorize(1), [])
}

///|
test "ecm: factorize perfect power" {
  // 64 = 2^6
  let factors = factorize(64)
  assert_eq(factors, [2, 2, 2, 2, 2, 2])
  // 81 = 3^4
  let factors2 = factorize(81)
  assert_eq(factors2, [3, 3, 3, 3])
}

///|
test "ecm: factorize with repeated factors" {
  // 180 = 2^2 * 3^2 * 5
  let factors = factorize(180)
  assert_eq(factors, [2, 2, 3, 3, 5])
}

///|
test "ecm: factorize large product" {
  // 997 * 1009 = 1006073
  let factors = factorize(1006073)
  assert_eq(factors.length(), 2)
  assert_eq(factors[0] * factors[1], 1006073)
}

///|
test "ecm: Suyama curve generation" {
  let n = 10403L
  let curve = suyama_curve(6L, n)
  assert_true(curve is Some(_))
  let c = curve.unwrap()
  // a24 should be in [0, n)
  assert_true(c.a24 >= 0L && c.a24 < n)
  assert_true(c.x0 >= 0L && c.x0 < n)
  assert_true(c.z0 >= 0L && c.z0 < n)
}

///|
test "ecm: scalar_mult identity" {
  let n = 10403L
  let curve = suyama_curve(6L, n).unwrap()
  // 1*P should return P
  let result = scalar_mult(1L, curve, n)
  assert_eq(result.x, curve.x0)
  assert_eq(result.z, curve.z0)
}

///|
test "ecm: stage1 produces valid point" {
  let n = 10403L
  let curve = suyama_curve(6L, n).unwrap()
  let primes = sieve_primes(100)
  let q = stage1(curve, n, primes, 100)
  // Q should be a valid point (Z != 0 or Z = 0 if factor found)
  assert_true(q.x >= 0L && q.x < n)
  assert_true(q.z >= 0L && q.z < n)
}

///|
test "ecm: isqrt" {
  assert_eq(isqrt(0), 0)
  assert_eq(isqrt(1), 1)
  assert_eq(isqrt(4), 2)
  assert_eq(isqrt(9), 3)
  assert_eq(isqrt(15), 3)
  assert_eq(isqrt(16), 4)
  assert_eq(isqrt(100), 10)
  assert_eq(isqrt(99), 9)
}

///|
test "ecm: factorize consistency" {
  // Verify that product of factors equals original.
  for i = 2; i <= 200; i = i + 1 {
    let factors = factorize(i)
    let mut product = 1
    for j = 0; j < factors.length(); j = j + 1 {
      product = product * factors[j]
    }
    assert_eq(product, i)
    // Verify ascending order.
    for j = 1; j < factors.length(); j = j + 1 {
      assert_true(factors[j] >= factors[j - 1])
    }
  }
}

///|
test "ecm: factorize 32-bit semiprime" {
  // 4099 * 4111 = 16850989
  let factors = factorize(16850989)
  assert_eq(factors.length(), 2)
  assert_eq(factors[0] * factors[1], 16850989)
}

///|
test "ecm: multiple curve attempts" {
  // This number has factors that require trying multiple curves.
  // 809 * 811 = 656099
  let f = ecm(656099, 500, 5000)
  assert_true(f is Some(_))
  let factor = f.unwrap()
  assert_true(factor == 809 || factor == 811)
}

///|
test "ecm: factorize with large prime factor" {
  // 101 * 10007 = 1010707
  let factors = factorize(1010707)
  assert_eq(factors.length(), 2)
  assert_eq(factors[0] * factors[1], 1010707)
}
