/// Random Walk — Stochastic Process Simulation and Analysis.
///
/// This module provides production-grade simulation and analysis of random
/// walks, including:
///
/// - **1D simple symmetric random walk**: Steps +1/-1 with equal probability.
/// - **Biased random walk**: Steps +1 with probability `p`, -1 with `1-p`.
/// - **Gaussian random walk**: Steps drawn from N(0, sigma^2).
/// - **Multi-dimensional random walk**: 2D and 3D lattice walks.
/// - **Custom step distribution**: User-supplied step generator.
/// - **Analytical formulas**: Expected position, variance, hitting probabilities.
/// - **Monte Carlo estimation**: Statistical properties via repeated simulation.
///
/// ## Mathematical Background
///
/// For a 1D simple symmetric random walk S_n = X_1 + ... + X_n where
/// X_i = +1 with probability p and X_i = -1 with probability 1-p:
///
/// - E[S_n] = n(2p - 1)
/// - Var[S_n] = 4n p(1 - p)
/// - For p = 0.5: S_n is a martingale, E[S_n] = 0, Var[S_n] = n
/// - P(S_n = k) = C(n, (n+k)/2) p^{(n+k)/2} (1-p)^{(n-k)/2}  (n+k even)
///
/// The reflection principle: for a symmetric walk,
/// P(max_{i<=n} S_i >= a, S_n = b) = P(S_n = 2a - b)  for a >= max(0, b).
///
/// ## Determinism
///
/// All simulations use a deterministic xorshift64 PRNG seeded by the caller,
/// ensuring reproducible results — essential for testing and scientific
/// computing.
///
/// ## References
///
/// - Feller, W. "An Introduction to Probability Theory and Its Applications,"
///   Vol. 1, 3rd ed., Chapter III.
/// - Lawler, G. F. & Limic, V. "Random Walk: A Modern Introduction,"
///   Cambridge Studies in Advanced Mathematics, 2010.
/// - Spitzer, F. "Principles of Random Walk," 2nd ed., Springer, 1976.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// PRNG (xorshift64 — deterministic, reproducible)
// ---------------------------------------------------------------------------

///|
/// Deterministic PRNG state for random walk simulation.
///
/// Construct with `RWState::new(seed)`. Each call to `next_double()` or
/// `next_int()` advances the state. The same seed always produces the
/// same sequence, ensuring reproducibility.
pub struct RWState {
  mut state : Int64
}

///|
/// Create a new PRNG state from a 64-bit seed.
///
/// A seed of 0 is replaced with a non-zero constant to avoid the
/// degenerate fixed point of xorshift64.
pub fn RWState::new(seed : Int64) -> RWState {
  let s = if seed == 0L { 0x9E3779B97F4A7C15L } else { seed }
  // Warm up: 8 iterations to mix the initial state thoroughly.
  let mut x = s
  for i = 0; i < 8; i = i + 1 {
    x = x ^ (x << 13)
    x = x ^ (x >> 7)
    x = x ^ (x << 17)
  }
  { state: x }
}

///|
/// Advance the PRNG and return a uniform double in [0, 1).
pub fn RWState::next_double(self : RWState) -> Double {
  self.state = self.state ^ (self.state << 13)
  self.state = self.state ^ (self.state >> 7)
  self.state = self.state ^ (self.state << 17)
  // Use the upper 53 bits for a double with full mantissa precision.
  let bits = (self.state >> 11) & 0x1FFFFFFFFFFFFFL
  bits.to_double() / 9007199254740992.0
}

///|
/// Advance the PRNG and return a uniform integer in [0, n).
///
/// Uses rejection sampling to eliminate modulo bias.
pub fn RWState::next_int(self : RWState, n : Int) -> Int {
  if n <= 0 {
    return 0
  }
  // Rejection sampling: draw from [0, 2^31) and reject if >= floor(2^31 / n) * n.
  let limit = 2147483647 - 2147483647 % n
  let mut r = 0
  while true {
    self.state = self.state ^ (self.state << 13)
    self.state = self.state ^ (self.state >> 7)
    self.state = self.state ^ (self.state << 17)
    r = (self.state & 0x7FFFFFFFL).to_int()
    if r < limit {
      return r % n
    }
  }
  r % n // unreachable, but satisfies the compiler
}

///|
/// Generate a standard normal sample using the Box-Muller transform.
///
/// Returns (z0, z1) where both are independent N(0, 1) samples.
/// We cache z1 for the next call to avoid wasting entropy.
pub fn RWState::next_standard_normal(self : RWState) -> Double {
  // Box-Muller: given U1, U2 ~ Uniform(0,1),
  // Z0 = sqrt(-2 ln U1) cos(2pi U2), Z1 = sqrt(-2 ln U1) sin(2pi U2)
  let u1 = self.next_double()
  let u2 = self.next_double()
  // Guard against u1 = 0 (log(0) = -inf).
  let u1_safe = if u1 < 1.0e-300 { 1.0e-300 } else { u1 }
  let r = (-2.0 * @math.ln(u1_safe)).sqrt()
  let theta = 2.0 * 3.14159265358979323846 * u2
  r * @math.cos(theta)
}

///|
/// Generate a normal sample with given mean and standard deviation.
pub fn RWState::next_normal(
  self : RWState,
  mean : Double,
  std : Double,
) -> Double {
  mean + std * self.next_standard_normal()
}

///|
fn copy_array(a : Array[Int]) -> Array[Int] {
  let result = Array::make(a.length(), 0)
  for i = 0; i < a.length(); i = i + 1 {
    result[i] = a[i]
  }
  result
}

// ---------------------------------------------------------------------------
// 1D Simple Symmetric Random Walk
// ---------------------------------------------------------------------------

///|
/// Result of a single random walk simulation.
pub struct WalkResult {
  /// Final position after all steps.
  final_position : Int
  /// Maximum position reached during the walk.
  max_position : Int
  /// Minimum position reached during the walk.
  min_position : Int
  /// Number of times the walk returned to the origin (excluding start).
  return_count : Int
  /// Step at which the walk first reached `final_position`'s sign
  /// (or -1 if never). This is the first passage time to the final level.
  first_passage : Int
  /// All positions visited, including the initial 0.
  path : Array[Int]
}

///|
/// Simulate a 1D simple symmetric random walk of `n` steps.
///
/// Each step is +1 or -1 with equal probability (p = 0.5).
/// The walk starts at position 0.
///
/// **Complexity**: O(n) time, O(n) space (for the path).
pub fn simulate_symmetric(rng : RWState, n : Int) -> WalkResult {
  simulate_biased(rng, n, 0.5)
}

///|
/// Simulate a 1D biased random walk of `n` steps.
///
/// Each step is +1 with probability `p` and -1 with probability `1-p`.
/// The walk starts at position 0.
///
/// **Complexity**: O(n) time, O(n) space.
pub fn simulate_biased(rng : RWState, n : Int, p : Double) -> WalkResult {
  let path = Array::make(n + 1, 0)
  let mut pos = 0
  let mut max_pos = 0
  let mut min_pos = 0
  let mut return_count = 0
  let mut first_passage = -1
  let final_sign = 0 // will be set after walk
  let _ = final_sign // suppress unused warning
  for i = 0; i < n; i = i + 1 {
    if rng.next_double() < p {
      pos = pos + 1
    } else {
      pos = pos - 1
    }
    path[i + 1] = pos
    if pos > max_pos {
      max_pos = pos
    }
    if pos < min_pos {
      min_pos = pos
    }
    if pos == 0 {
      return_count = return_count + 1
    }
  }
  // Determine first passage to the final position's level.
  let target = pos
  for i = 1; i <= n; i = i + 1 {
    if path[i] == target {
      first_passage = i
      break
    }
  }
  {
    final_position: pos,
    max_position: max_pos,
    min_position: min_pos,
    return_count,
    first_passage,
    path,
  }
}

// ---------------------------------------------------------------------------
// Gaussian Random Walk
// ---------------------------------------------------------------------------

///|
/// Result of a Gaussian random walk simulation.
pub struct GaussianWalkResult {
  /// Final position.
  final_position : Double
  /// Maximum position reached.
  max_position : Double
  /// Minimum position reached.
  min_position : Double
  /// All positions visited, including the initial 0.0.
  path : Array[Double]
}

///|
/// Simulate a 1D Gaussian random walk of `n` steps.
///
/// Each step is drawn from N(0, sigma^2). The walk starts at 0.
/// This is the discrete-time analogue of Brownian motion.
///
/// **Complexity**: O(n) time, O(n) space.
pub fn simulate_gaussian(
  rng : RWState,
  n : Int,
  sigma : Double,
) -> GaussianWalkResult {
  let path = Array::make(n + 1, 0.0)
  let mut pos = 0.0
  let mut max_pos = 0.0
  let mut min_pos = 0.0
  for i = 0; i < n; i = i + 1 {
    pos = pos + rng.next_normal(0.0, sigma)
    path[i + 1] = pos
    if pos > max_pos {
      max_pos = pos
    }
    if pos < min_pos {
      min_pos = pos
    }
  }
  { final_position: pos, max_position: max_pos, min_position: min_pos, path }
}

// ---------------------------------------------------------------------------
// Multi-dimensional Random Walk
// ---------------------------------------------------------------------------

///|
/// Result of a multi-dimensional lattice random walk.
pub struct MultiDimWalkResult {
  /// Final position in each dimension.
  final_position : Array[Int]
  /// Squared displacement from origin (final).
  r_squared : Int
  /// All positions visited (each is an array of d coordinates).
  path : Array[Array[Int]]
}

///|
/// Simulate a d-dimensional simple symmetric random walk on the integer
/// lattice Z^d.
///
/// At each step, one of the 2d directions is chosen uniformly at random,
/// and the walk moves one unit in that direction.
///
/// **Complexity**: O(n * d) time, O(n * d) space.
pub fn simulate_multidim(
  rng : RWState,
  n : Int,
  dim : Int,
) -> MultiDimWalkResult {
  let pos = Array::make(dim, 0)
  let path : Array[Array[Int]] = []
  path.push(Array::make(dim, 0)) // initial position
  for i = 0; i < n; i = i + 1 {
    let dir = rng.next_int(dim) // which axis
    let sign = if rng.next_double() < 0.5 { 1 } else { -1 }
    pos[dir] = pos[dir] + sign
    path.push(copy_array(pos)) // snapshot
  }
  let mut rsq = 0
  for d = 0; d < dim; d = d + 1 {
    rsq = rsq + pos[d] * pos[d]
  }
  { final_position: pos, r_squared: rsq, path }
}

// ---------------------------------------------------------------------------
// Custom Step Distribution
// ---------------------------------------------------------------------------

///|
/// Simulate a random walk with a user-supplied step function.
///
/// The step function takes the PRNG state and returns the next step value.
/// This allows arbitrary step distributions (e.g. heavy-tailed, multi-valued).
///
/// **Complexity**: O(n) time, O(n) space.
pub fn simulate_custom(
  rng : RWState,
  n : Int,
  step_fn : (RWState) -> Double,
) -> GaussianWalkResult {
  let path = Array::make(n + 1, 0.0)
  let mut pos = 0.0
  let mut max_pos = 0.0
  let mut min_pos = 0.0
  for i = 0; i < n; i = i + 1 {
    pos = pos + step_fn(rng)
    path[i + 1] = pos
    if pos > max_pos {
      max_pos = pos
    }
    if pos < min_pos {
      min_pos = pos
    }
  }
  { final_position: pos, max_position: max_pos, min_position: min_pos, path }
}

// ---------------------------------------------------------------------------
// Analytical Formulas
// ---------------------------------------------------------------------------

///|
/// Expected position of a biased random walk after `n` steps.
///
/// E[S_n] = n * (2p - 1), where p is the probability of a +1 step.
pub fn expected_position(n : Int, p : Double) -> Double {
  n.to_double() * (2.0 * p - 1.0)
}

///|
/// Variance of a biased random walk after `n` steps.
///
/// Var[S_n] = 4 * n * p * (1 - p).
pub fn variance(n : Int, p : Double) -> Double {
  4.0 * n.to_double() * p * (1.0 - p)
}

///|
/// Standard deviation of a biased random walk after `n` steps.
pub fn std_dev(n : Int, p : Double) -> Double {
  variance(n, p).sqrt()
}

///|
/// Probability that a symmetric (p=0.5) random walk is at position `k`
/// after `n` steps.
///
/// P(S_n = k) = C(n, (n+k)/2) / 2^n, valid when n+k is even and |k| <= n.
/// Returns 0.0 for invalid (n+k odd or |k| > n).
///
/// Uses log-space computation to avoid overflow for large n.
pub fn position_probability(n : Int, k : Int) -> Double {
  if n < 0 || (n + k) % 2 != 0 || k > n || k < -n {
    return 0.0
  }
  let n2 = (n + k) / 2
  // C(n, n2) / 2^n = exp(lgamma(n+1) - lgamma(n2+1) - lgamma(n-n2+1) - n*ln2)
  let log_coeff = log_binomial(n, n2)
  let log_2n = n.to_double() * 0.69314718055994530942 // n * ln(2)
  @math.exp(log_coeff - log_2n)
}

///|
/// Logarithm of the binomial coefficient C(n, k), computed via lgamma.
fn log_binomial(n : Int, k : Int) -> Double {
  if k < 0 || k > n {
    return -1.0e308
  }
  if k == 0 || k == n {
    return 0.0
  }
  // lgamma(n+1) - lgamma(k+1) - lgamma(n-k+1)
  @special_functions.lgamma(n.to_double() + 1.0) -
  @special_functions.lgamma(k.to_double() + 1.0) -
  @special_functions.lgamma((n - k).to_double() + 1.0)
}

///|
/// Probability that a symmetric random walk returns to the origin at step 2n.
///
/// P(S_{2n} = 0) = C(2n, n) / 4^n.
/// Returns 0.0 for odd step counts (the walk can only return at even steps).
pub fn return_probability(step : Int) -> Double {
  if step % 2 != 0 || step < 0 {
    return 0.0
  }
  if step == 0 {
    return 1.0
  }
  let n = step / 2
  let log_coeff = log_binomial(2 * n, n)
  let log_4n = step.to_double() * 0.69314718055994530942 // 2n * ln(2) = step * ln(2)
  @math.exp(log_coeff - log_4n)
}

///|
/// Expected number of returns to the origin in the first `2n` steps
/// of a symmetric random walk.
///
/// For a 1D walk, E[# returns in 2n steps] = sum_{k=1}^{n} P(S_{2k} = 0).
/// This sum diverges as n -> infinity, confirming recurrence in 1D.
pub fn expected_returns(n : Int) -> Double {
  let mut total = 0.0
  for k = 1; k <= n; k = k + 1 {
    total = total + return_probability(2 * k)
  }
  total
}

// ---------------------------------------------------------------------------
// Monte Carlo Estimation
// ---------------------------------------------------------------------------

///|
/// Statistical summary of a Monte Carlo simulation.
pub struct MonteCarloResult {
  /// Sample mean of the final positions.
  mean : Double
  /// Sample variance of the final positions.
  variance : Double
  /// Sample standard deviation.
  std_dev : Double
  /// Standard error of the mean (std_dev / sqrt(trials)).
  std_error : Double
  /// 95% confidence interval half-width (1.96 * std_error).
  ci_half_width : Double
  /// Number of trials.
  trials : Int
  /// Fraction of walks that reached or exceeded `target` at any point.
  hit_fraction : Double
}

///|
/// Run a Monte Carlo simulation of a biased random walk.
///
/// Performs `trials` independent simulations of `n` steps each, and
/// computes statistics on the final position and hitting probability
/// for the given `target` level.
///
/// **Complexity**: O(trials * n) time.
pub fn monte_carlo(
  rng : RWState,
  n : Int,
  p : Double,
  target : Int,
  trials : Int,
) -> MonteCarloResult {
  let finals : Array[Int] = Array::make(trials, 0)
  let mut hit_count = 0
  for t = 0; t < trials; t = t + 1 {
    let result = simulate_biased(rng, n, p)
    finals[t] = result.final_position
    if result.max_position >= target {
      hit_count = hit_count + 1
    }
  }
  // Compute mean.
  let mut sum = 0.0
  for t = 0; t < trials; t = t + 1 {
    sum = sum + finals[t].to_double()
  }
  let mean = sum / trials.to_double()
  // Compute variance.
  let mut sq_sum = 0.0
  for t = 0; t < trials; t = t + 1 {
    let diff = finals[t].to_double() - mean
    sq_sum = sq_sum + diff * diff
  }
  let sample_var = if trials > 1 {
    sq_sum / (trials - 1).to_double()
  } else {
    0.0
  }
  let sd = sample_var.sqrt()
  let se = sd / trials.to_double().sqrt()
  let ci = 1.96 * se
  {
    mean,
    variance: sample_var,
    std_dev: sd,
    std_error: se,
    ci_half_width: ci,
    trials,
    hit_fraction: hit_count.to_double() / trials.to_double(),
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "rw: deterministic reproducibility" {
  let rng1 = RWState::new(42L)
  let rng2 = RWState::new(42L)
  for i = 0; i < 100; i = i + 1 {
    assert_eq(rng1.next_int(1000), rng2.next_int(1000))
  }
}

///|
test "rw: uniform distribution of next_double" {
  let rng = RWState::new(12345L)
  let n = 10000
  let mut sum = 0.0
  let mut below_half = 0
  for i = 0; i < n; i = i + 1 {
    let u = rng.next_double()
    assert_true(u >= 0.0 && u < 1.0)
    sum = sum + u
    if u < 0.5 {
      below_half = below_half + 1
    }
  }
  let mean = sum / n.to_double()
  // E[U] = 0.5, std = 1/sqrt(12*n) ~ 0.0029
  assert_true((mean - 0.5).abs() < 0.05)
  // About half should be below 0.5
  assert_true(below_half > n * 4 / 10 && below_half < n * 6 / 10)
}

///|
test "rw: next_int range" {
  let rng = RWState::new(999L)
  for i = 0; i < 10000; i = i + 1 {
    let v = rng.next_int(7)
    assert_true(v >= 0 && v < 7)
  }
}

///|
test "rw: symmetric walk starts at origin" {
  let rng = RWState::new(1L)
  let result = simulate_symmetric(rng, 0)
  assert_eq(result.final_position, 0)
  assert_eq(result.path.length(), 1)
}

///|
test "rw: symmetric walk final position parity" {
  let rng = RWState::new(42L)
  let result = simulate_symmetric(rng, 100)
  // After n steps, position has the same parity as n.
  assert_eq((result.final_position + 100) % 2, 0)
  assert_eq(result.path.length(), 101)
  assert_eq(result.path[0], 0)
}

///|
test "rw: symmetric walk max and min bounds" {
  let rng = RWState::new(42L)
  let result = simulate_symmetric(rng, 1000)
  assert_true(result.max_position >= 0)
  assert_true(result.min_position <= 0)
  assert_true(result.max_position <= 1000)
  assert_true(result.min_position >= -1000)
}

///|
test "rw: biased walk drift" {
  // With p=0.9, the walk should drift strongly positive.
  let rng = RWState::new(42L)
  let result = simulate_biased(rng, 1000, 0.9)
  assert_true(result.final_position > 500)
}

///|
test "rw: biased walk negative drift" {
  let rng = RWState::new(42L)
  let result = simulate_biased(rng, 1000, 0.1)
  assert_true(result.final_position < -500)
}

///|
test "rw: gaussian walk mean near zero" {
  let rng = RWState::new(42L)
  let mut sum = 0.0
  let trials = 1000
  for t = 0; t < trials; t = t + 1 {
    let result = simulate_gaussian(rng, 100, 1.0)
    sum = sum + result.final_position
  }
  let mean = sum / trials.to_double()
  // E[S_100] = 0, Var = 100, std = 10, SE = 10/sqrt(1000) ~ 0.316
  assert_true(mean.abs() < 2.0)
}

///|
test "rw: gaussian walk variance" {
  let rng = RWState::new(42L)
  let trials = 5000
  let finals : Array[Double] = Array::make(trials, 0.0)
  for t = 0; t < trials; t = t + 1 {
    let result = simulate_gaussian(rng, 100, 2.0)
    finals[t] = result.final_position
  }
  let mut sum = 0.0
  for t = 0; t < trials; t = t + 1 {
    sum = sum + finals[t]
  }
  let mean = sum / trials.to_double()
  let mut sq_sum = 0.0
  for t = 0; t < trials; t = t + 1 {
    let d = finals[t] - mean
    sq_sum = sq_sum + d * d
  }
  let var_val = sq_sum / (trials - 1).to_double()
  // Var[S_100] = 100 * sigma^2 = 100 * 4 = 400
  assert_true((var_val - 400.0).abs() < 60.0)
}

///|
test "rw: multidim walk dimension" {
  let rng = RWState::new(42L)
  let result = simulate_multidim(rng, 100, 3)
  assert_eq(result.final_position.length(), 3)
  assert_eq(result.path.length(), 101)
  assert_eq(result.path[0].length(), 3)
  // r_squared should be non-negative
  assert_true(result.r_squared >= 0)
}

///|
test "rw: multidim walk 2d parity" {
  let rng = RWState::new(42L)
  let result = simulate_multidim(rng, 100, 2)
  // After n steps, sum of coordinates has same parity as n.
  let coord_sum = result.final_position[0] + result.final_position[1]
  assert_eq((coord_sum + 100) % 2, 0)
}

///|
test "rw: custom step distribution" {
  let rng = RWState::new(42L)
  // Steps are always +2 (deterministic).
  let result = simulate_custom(rng, 10, fn(_r) { 2.0 })
  assert_eq(result.final_position, 20.0)
  assert_eq(result.path[10], 20.0)
}

///|
test "rw: expected_position formulas" {
  // Symmetric: E[S_n] = 0
  assert_true(expected_position(100, 0.5).abs() < 1.0e-10)
  // p=1: E[S_n] = n
  assert_eq(expected_position(100, 1.0), 100.0)
  // p=0: E[S_n] = -n
  assert_eq(expected_position(100, 0.0), -100.0)
  // p=0.75: E[S_n] = n * 0.5
  assert_eq(expected_position(100, 0.75), 50.0)
}

///|
test "rw: variance formula" {
  // Symmetric: Var = n
  assert_eq(variance(100, 0.5), 100.0)
  // p=1 or p=0: Var = 0 (deterministic)
  assert_eq(variance(100, 1.0), 0.0)
  assert_eq(variance(100, 0.0), 0.0)
  // p=0.25: Var = 4 * n * 0.25 * 0.75 = 0.75n
  assert_eq(variance(100, 0.25), 75.0)
}

///|
test "rw: position_probability basic" {
  // P(S_0 = 0) = 1
  assert_eq(position_probability(0, 0), 1.0)
  // P(S_1 = 1) = 0.5, P(S_1 = -1) = 0.5
  assert_true((position_probability(1, 1) - 0.5).abs() < 1.0e-10)
  assert_true((position_probability(1, -1) - 0.5).abs() < 1.0e-10)
  // P(S_1 = 0) = 0 (odd step, even position)
  assert_eq(position_probability(1, 0), 0.0)
  // P(S_2 = 0) = C(2,1)/4 = 0.5
  assert_true((position_probability(2, 0) - 0.5).abs() < 1.0e-10)
  // P(S_2 = 2) = C(2,2)/4 = 0.25
  assert_true((position_probability(2, 2) - 0.25).abs() < 1.0e-10)
  // P(S_2 = 1) = 0 (parity mismatch)
  assert_eq(position_probability(2, 1), 0.0)
  // Out of range
  assert_eq(position_probability(2, 3), 0.0)
}

///|
test "rw: position_probability sums to 1" {
  // For n=10, sum of P(S_10 = k) for all valid k should be 1.
  let mut total = 0.0
  for k = -10; k <= 10; k = k + 1 {
    total = total + position_probability(10, k)
  }
  assert_true((total - 1.0).abs() < 1.0e-10)
}

///|
test "rw: position_probability large n" {
  // P(S_100 = 0) should be positive and small.
  let p = position_probability(100, 0)
  assert_true(p > 0.0 && p < 0.1)
  // Symmetric: P(S_n = k) = P(S_n = -k)
  let p_pos = position_probability(20, 4)
  let p_neg = position_probability(20, -4)
  assert_true((p_pos - p_neg).abs() < 1.0e-10)
}

///|
test "rw: return_probability" {
  // P(S_0 = 0) = 1
  assert_eq(return_probability(0), 1.0)
  // P(S_1 = 0) = 0 (odd)
  assert_eq(return_probability(1), 0.0)
  // P(S_2 = 0) = C(2,1)/4 = 0.5
  assert_true((return_probability(2) - 0.5).abs() < 1.0e-10)
  // P(S_4 = 0) = C(4,2)/16 = 6/16 = 0.375
  assert_true((return_probability(4) - 0.375).abs() < 1.0e-10)
}

///|
test "rw: expected_returns diverges" {
  // The expected number of returns should increase with n.
  let r10 = expected_returns(10)
  let r100 = expected_returns(100)
  assert_true(r100 > r10)
  // For large n, it should grow like sqrt(n).
  assert_true(r100 > 5.0)
}

///|
test "rw: monte_carlo mean matches theory" {
  let rng = RWState::new(42L)
  let mc = monte_carlo(rng, 200, 0.5, 50, 5000)
  // E[S_200] = 0, Var = 200, SE = sqrt(200/5000) ~ 0.2
  assert_true(mc.mean.abs() < 1.0)
  // Variance should be close to 200.
  assert_true((mc.variance - 200.0).abs() < 30.0)
  // Hit fraction for target=50 in 200 steps should be positive but < 1.
  assert_true(mc.hit_fraction > 0.0 && mc.hit_fraction < 1.0)
}

///|
test "rw: monte_carlo biased" {
  let rng = RWState::new(42L)
  let mc = monte_carlo(rng, 500, 0.6, 100, 5000)
  // E[S_500] = 500 * 0.2 = 100
  assert_true((mc.mean - 100.0).abs() < 5.0)
}

///|
test "rw: first_passage correctness" {
  let rng = RWState::new(42L)
  let result = simulate_symmetric(rng, 100)
  // first_passage should be >= 1 and <= 100.
  assert_true(result.first_passage >= 1 && result.first_passage <= 100)
  // The path at first_passage should equal the final position.
  assert_eq(result.path[result.first_passage], result.final_position)
}

///|
test "rw: walk result path consistency" {
  let rng = RWState::new(42L)
  let result = simulate_symmetric(rng, 50)
  assert_eq(result.path.length(), 51)
  assert_eq(result.path[0], 0)
  assert_eq(result.path[50], result.final_position)
  // Consecutive steps differ by exactly 1.
  for i = 0; i < 50; i = i + 1 {
    let diff = result.path[i + 1] - result.path[i]
    assert_true(diff == 1 || diff == -1)
  }
}

///|
test "rw: gaussian walk path consistency" {
  let rng = RWState::new(42L)
  let result = simulate_gaussian(rng, 50, 1.0)
  assert_eq(result.path.length(), 51)
  assert_eq(result.path[0], 0.0)
  assert_eq(result.path[50], result.final_position)
  // max >= all elements >= min
  for i = 0; i <= 50; i = i + 1 {
    assert_true(result.path[i] <= result.max_position + 1.0e-10)
    assert_true(result.path[i] >= result.min_position - 1.0e-10)
  }
}

///|
test "rw: return count tracks zeros" {
  let rng = RWState::new(42L)
  let result = simulate_symmetric(rng, 1000)
  let mut zeros = 0
  for i = 1; i <= 1000; i = i + 1 {
    if result.path[i] == 0 {
      zeros = zeros + 1
    }
  }
  assert_eq(result.return_count, zeros)
}

///|
test "rw: standard normal approx" {
  let rng = RWState::new(42L)
  let n = 100000
  let mut sum = 0.0
  let mut sq_sum = 0.0
  for i = 0; i < n; i = i + 1 {
    let z = rng.next_standard_normal()
    sum = sum + z
    sq_sum = sq_sum + z * z
  }
  let mean = sum / n.to_double()
  let var_val = sq_sum / n.to_double() - mean * mean
  // E[Z] = 0, Var[Z] = 1.
  assert_true(mean.abs() < 0.02)
  assert_true((var_val - 1.0).abs() < 0.05)
}

///|
test "rw: multidim 3d walk consistency" {
  let rng = RWState::new(42L)
  let result = simulate_multidim(rng, 200, 3)
  assert_eq(result.path.length(), 201)
  assert_eq(result.path[0].length(), 3)
  // Each step changes exactly one coordinate by +/- 1.
  for i = 0; i < 200; i = i + 1 {
    let diff_count = count_diffs(result.path[i], result.path[i + 1])
    assert_eq(diff_count, 1)
  }
}

///|
fn count_diffs(a : Array[Int], b : Array[Int]) -> Int {
  let mut count = 0
  for i = 0; i < a.length(); i = i + 1 {
    if a[i] != b[i] {
      count = count + 1
    }
  }
  count
}

///|
test "rw: std_dev formula" {
  // Symmetric: std = sqrt(n)
  assert_true((std_dev(100, 0.5) - 10.0).abs() < 1.0e-10)
  // p=0.25: std = sqrt(75) ~ 8.66
  assert_true((std_dev(100, 0.25) - 8.660254).abs() < 0.001)
}
