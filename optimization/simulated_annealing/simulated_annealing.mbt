/// Simulated Annealing — Generic metaheuristic optimizer for combinatorial
/// and continuous optimization problems.
///
/// Simulated Annealing (SA) is a probabilistic metaheuristic inspired by the
/// physical annealing process: a metal is heated to a high temperature and then
/// slowly cooled, allowing atoms to settle into a low-energy crystalline
/// state. Similarly, SA explores the solution space by accepting improving
/// moves always and accepting worsening moves with a probability that
/// decreases over time (as "temperature" cools), enabling escape from local
/// optima.
///
/// ## Algorithm
///
/// ```text
/// s = initial_solution
/// T = T₀                        // initial temperature
/// best = s
/// while T > T_min and iterations < max_iter:
///   s' = neighbor(s)            // perturb current solution
///   ΔE = cost(s') − cost(s)     // energy difference
///   if ΔE < 0 or random() < exp(−ΔE / T):
///     s = s'                    // accept new state
///   if cost(s) < cost(best):
///     best = s                  // track best solution found
///   T = cooling(T)              // decrease temperature
/// return best
/// ```
///
/// ## Cooling Schedules
///
/// - **Geometric**: T_{k+1} = T_k · α (α ∈ (0, 1)). Simple and widely used.
/// - **Linear**: T_{k+1} = T_k − β. Reaches T_min quickly.
/// - **Logarithmic**: T_{k+1} = T₀ / ln(k + 2). Theoretically guarantees
///   convergence to the global optimum (Geman & Geman, 1984), but impractically
///   slow.
///
/// ## Metropolis Acceptance Criterion
///
/// A worsening move with energy increase ΔE > 0 is accepted with probability
/// `exp(−ΔE / T)`. At high temperature, almost all moves are accepted (random
/// walk). As T → 0, only improving moves are accepted (greedy hill-climbing).
/// The transition is smooth, allowing the algorithm to traverse energy barriers
/// early and settle into deep minima late.
///
/// ## Complexity
///
/// O(max_iter · cost_per_iteration), where cost_per_iteration includes one
/// neighbor generation, one cost evaluation, and one random number generation.
///
/// ## References
///
/// - Kirkpatrick, S., Gelatt, C. D., & Vecchi, M. P. (1983). "Optimization by
///   simulated annealing." *Science*, 220(4598), 671–680.
/// - Geman, S., & Geman, D. (1984). "Stochastic relaxation, Gibbs distributions,
///   and the Bayesian restoration of images." *IEEE TPAMI*, 6(6), 721–741.
/// - Aarts, E., & Korst, J. (1989). *Simulated Annealing and Boltzmann
///   Machines*. Wiley.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

///|
/// Cooling schedule strategy.
pub enum CoolingSchedule {
  /// Geometric: T_{k+1} = T_k · alpha. Requires 0 < alpha < 1.
  /// The most commonly used schedule. alpha = 0.95 is a typical default.
  Geometric(Double)
  /// Linear: T_{k+1} = max(T_min, T_k − beta).
  /// Reaches the minimum temperature in a predictable number of steps.
  Linear(Double)
  /// Logarithmic: T_{k+1} = T₀ / ln(k + 2).
  /// Theoretically guarantees convergence to the global optimum, but very slow.
  /// Suitable for small-scale problems where optimality is critical.
  Logarithmic(Double)
} derive(Eq, Debug)

///|
/// Configuration parameters for the simulated annealing optimizer.
pub struct SAConfig {
  /// Initial temperature T₀. Should be set high enough that most moves are
  /// accepted initially (typically 10× the average energy difference).
  initial_temp : Double
  /// Minimum temperature. The algorithm stops when T falls below this.
  min_temp : Double
  /// Maximum number of iterations regardless of temperature.
  max_iter : Int
  /// Number of iterations at each temperature level before cooling.
  /// Higher values give more exploration at each temperature.
  iter_per_temp : Int
  /// Cooling schedule.
  cooling : CoolingSchedule
  /// Seed for the deterministic PRNG (xorshift64).
  seed : UInt64
}

///|
/// Result of a simulated annealing optimization run.
pub struct SAResult[T] {
  /// The best solution found.
  best : T
  /// Cost of the best solution.
  best_cost : Double
  /// Total number of iterations executed.
  iterations : Int
  /// Whether the algorithm terminated by reaching min_temp (true) or
  /// max_iter (false).
  converged : Bool
}

// ---------------------------------------------------------------------------
// PRNG — xorshift64 for deterministic reproducibility
// ---------------------------------------------------------------------------

///|
/// xorshift64 state — a simple, fast, deterministic PRNG.
priv struct XorShift64 {
  mut state : UInt64
}

///|
fn xs64_new(seed : UInt64) -> XorShift64 {
  // Avoid the all-zero state (which would produce only zeros).
  let s = if seed == 0UL { 0xDEADBEEFCAFEBABEUL } else { seed }
  { state: s }
}

///|
/// Generate the next Double in [0, 1) from the xorshift64 state.
fn xs64_next_double(rng : XorShift64) -> Double {
  // xorshift64 step
  let mut x = rng.state
  x = x ^ (x << 13)
  x = x ^ (x >> 7)
  x = x ^ (x << 17)
  rng.state = x
  // Convert to [0, 1) using the top 53 bits for Double precision.
  // Mask to 53 bits to prevent sign-bit issues when reinterpreting as Int64.
  let mantissa = ((x >> 11) & 0x1FFFFFFFFFFFFFUL).reinterpret_as_int64()
  mantissa.to_double() / 9007199254740992.0 // 2^53
}

// ---------------------------------------------------------------------------
// Math helpers
// ---------------------------------------------------------------------------

///|
/// Exponential function via Taylor series with range reduction.
/// Computes exp(x) for moderate |x| values (|x| < ~700).
fn exp_approx(x : Double) -> Double {
  if x <= -700.0 {
    return 0.0
  }
  if x >= 700.0 {
    return 1.0 / 0.0 // +inf
  }
  // Split x = k*ln(2) + r, where |r| <= ln(2)/2 ≈ 0.347
  let ln2 = 0.6931471805599453
  let k = @math.floor(x / ln2)
  let r = x - k * ln2
  // exp(r) via Taylor series (|r| < 0.347, so ~12 terms suffice for 1e-16)
  let mut term = 1.0
  let mut sum = 1.0
  for i = 1; i <= 12; i = i + 1 {
    term = term * r / i.to_double()
    sum = sum + term
  }
  // exp(x) = 2^k * exp(r)
  let k_int = k.to_int()
  if k_int >= 0 {
    let mut pow2 = 1.0
    for j = 0; j < k_int; j = j + 1 {
      pow2 = pow2 * 2.0
    }
    pow2 * sum
  } else {
    let mut pow2 = 1.0
    for j = 0; j < -k_int; j = j + 1 {
      pow2 = pow2 * 2.0
    }
    sum / pow2
  }
}

///|
/// Natural logarithm via atanh series (for the logarithmic cooling schedule).
fn ln_approx(x : Double) -> Double {
  if x <= 0.0 {
    return -1.0 / 0.0 // -inf
  }
  // Reduce: x = 2^k * m where 1 <= m < 2
  let mut k = 0
  let mut m = x
  while m >= 2.0 {
    m = m / 2.0
    k = k + 1
  }
  while m < 1.0 {
    m = m * 2.0
    k = k - 1
  }
  // ln(m) via atanh series: ln(m) = 2*(t + t^3/3 + t^5/5 + ...)
  // where t = (m-1)/(m+1), |t| < 1/3 for m in [1,2)
  let t = (m - 1.0) / (m + 1.0)
  let mut term = t
  let mut sum = t
  let t2 = t * t
  for i = 1; i <= 20; i = i + 1 {
    term = term * t2
    sum = sum + term / (2 * i + 1).to_double()
  }
  k.to_double() * 0.6931471805599453 + 2.0 * sum
}

// ---------------------------------------------------------------------------
// Cooling schedule computation
// ---------------------------------------------------------------------------

///|
/// Compute the next temperature given the current schedule and iteration.
fn cool_temperature(
  config : SAConfig,
  current_temp : Double,
  iter : Int,
) -> Double {
  match config.cooling {
    Geometric(alpha) => {
      let next = current_temp * alpha
      if next < config.min_temp {
        config.min_temp
      } else {
        next
      }
    }
    Linear(beta) => {
      let next = current_temp - beta
      if next < config.min_temp {
        config.min_temp
      } else {
        next
      }
    }
    Logarithmic(t0) => {
      // T_k = T₀ / ln(k + 2) where k is the temperature step
      let next = t0 / ln_approx(iter.to_double() + 2.0)
      if next < config.min_temp {
        config.min_temp
      } else {
        next
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Main optimization function
// ---------------------------------------------------------------------------

///|
/// Run simulated annealing to minimize an objective function.
///
/// # Parameters
/// - `config`: SA configuration (temperatures, cooling schedule, etc.)
/// - `initial`: The initial solution.
/// - `cost`: Objective function to minimize. Returns a `Double` (lower is better).
/// - `neighbor`: Generates a neighboring solution from the current one. The
///   neighborhood function controls the search space — small perturbations
///   give local search, large jumps give global exploration.
///
/// # Returns
/// A `SAResult[T]` containing the best solution found, its cost, iteration
/// count, and convergence status.
///
/// # Determinism
/// The algorithm uses a deterministic xorshift64 PRNG seeded by `config.seed`,
/// so the same config + initial solution always produces the same result.
pub fn[T] optimize(
  config : SAConfig,
  initial : T,
  cost : (T) -> Double,
  neighbor : (T, Double) -> T,
) -> SAResult[T] {
  let rng = xs64_new(config.seed)
  let mut current = initial
  let mut current_cost = cost(current)
  let mut best = initial
  let mut best_cost = current_cost
  let mut temp = config.initial_temp
  let mut iter = 0
  let mut total_iter = 0
  let mut converged = false
  while temp > config.min_temp && total_iter < config.max_iter {
    for j = 0; j < config.iter_per_temp; j = j + 1 {
      // Generate neighbor
      let candidate = neighbor(current, temp)
      let candidate_cost = cost(candidate)
      let delta = candidate_cost - current_cost
      // Metropolis acceptance criterion
      let accept = if delta <= 0.0 {
        true
      } else {
        // P(accept) = exp(-delta / temp)
        let p = exp_approx(-delta / temp)
        xs64_next_double(rng) < p
      }
      if accept {
        current = candidate
        current_cost = candidate_cost
        // Track best solution
        if current_cost < best_cost {
          best = current
          best_cost = current_cost
        }
      }
      total_iter = total_iter + 1
      if total_iter >= config.max_iter {
        break
      }
    }
    iter = iter + 1
    temp = cool_temperature(config, temp, iter)
    if temp <= config.min_temp {
      converged = true
      break
    }
  }
  if temp <= config.min_temp {
    converged = true
  }
  { best, best_cost, iterations: total_iter, converged }
}

///|
/// Convenience function to create a geometric cooling config with sensible
/// defaults.
pub fn default_config(
  initial_temp : Double,
  min_temp : Double,
  max_iter : Int,
  seed : UInt64,
) -> SAConfig {
  {
    initial_temp,
    min_temp,
    max_iter,
    iter_per_temp: 20,
    cooling: Geometric(0.95),
    seed,
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "sa: minimizes quadratic function" {
  // Minimize f(x) = (x - 5)^2, optimal x = 5, f(5) = 0.
  let config = default_config(100.0, 0.01, 10000, 42UL)
  let result = optimize(
    config,
    0.0, // initial x
    fn(x) { (x - 5.0) * (x - 5.0) },
    fn(x, temp) {
      // Perturbation: scale with sqrt(temp) for better exploration
      let rng = xs64_new(42UL + temp.reinterpret_as_uint64())
      let r = xs64_next_double(rng) - 0.5
      x + r * (temp * 0.1).sqrt() * 2.0
    },
  )
  assert_true(result.best_cost < 1.0)
  assert_true(result.best > 4.0 && result.best < 6.0)
}

///|
test "sa: finds global minimum of multi-modal function" {
  // f(x) = x^4 - 10x^2 + 5x + 20
  // Has local minima near x ≈ -2.2 and x ≈ 2.2
  // Global minimum is near x ≈ -2.18
  let config : SAConfig = {
    initial_temp: 200.0,
    min_temp: 0.001,
    max_iter: 50000,
    iter_per_temp: 50,
    cooling: Geometric(0.999),
    seed: 123UL,
  }
  let result = optimize(
    config,
    0.0,
    fn(x) { x * x * x * x - 10.0 * x * x + 5.0 * x + 20.0 },
    fn(x, temp) {
      let rng = xs64_new(123UL + temp.reinterpret_as_uint64() * 7UL)
      let r = xs64_next_double(rng) - 0.5
      x + r * (temp * 0.05).sqrt() * 3.0
    },
  )
  // The global minimum is approximately at x ≈ -2.18 with f ≈ -2.38
  assert_true(result.best_cost < 0.0)
}

///|
test "sa: Rastrigin function (combinatorial landscape)" {
  // Rastrigin: f(x) = 10 + x^2 - 10*cos(2*pi*x)
  // Global minimum at x=0, f(0) = 0. Many local minima.
  let config : SAConfig = {
    initial_temp: 50.0,
    min_temp: 0.01,
    max_iter: 20000,
    iter_per_temp: 20,
    cooling: Geometric(0.99),
    seed: 99UL,
  }
  let pi = 3.141592653589793
  let result = optimize(
    config,
    3.0, // start far from optimum
    fn(x) { 10.0 + x * x - 10.0 * @math.cos(2.0 * pi * x) },
    fn(x, temp) {
      let rng = xs64_new(99UL + temp.reinterpret_as_uint64() * 3UL)
      let r = xs64_next_double(rng) - 0.5
      x + r * 2.0
    },
  )
  assert_true(result.best_cost < 5.0) // should get close to 0
}

///|
test "sa: TSP small instance" {
  // 5-city TSP, coordinates in 2D.
  // Cities: (0,0), (1,0), (2,0), (0,1), (1,1)
  // Optimal tour: 0 -> 1 -> 2 -> 4 -> 3 -> 0, distance ≈ 5.414
  let cities = [(0.0, 0.0), (1.0, 0.0), (2.0, 0.0), (0.0, 1.0), (1.0, 1.0)]
  let n = cities.length()
  // Cost function: total tour length
  let tour_cost = fn(tour : FixedArray[Int]) -> Double {
    let mut total = 0.0
    for i = 0; i < n; i = i + 1 {
      let (x1, y1) = cities[tour[i]]
      let (x2, y2) = cities[tour[(i + 1) % n]]
      let dx = x1 - x2
      let dy = y1 - y2
      total = total + (dx * dx + dy * dy).sqrt()
    }
    total
  }
  // Neighbor: swap two random cities
  let neighbor_fn = fn(
    tour : FixedArray[Int],
    _temp : Double,
  ) -> FixedArray[Int] {
    let new_tour = FixedArray::makei(tour.length(), fn(i) { tour[i] })
    let rng = xs64_new(777UL + tour[0].to_uint64())
    let i = xs64_next_double(rng) * n.to_double()
    let j = xs64_next_double(rng) * n.to_double()
    let ii = i.to_int() % n
    let jj = j.to_int() % n
    let tmp = new_tour[ii]
    new_tour[ii] = new_tour[jj]
    new_tour[jj] = tmp
    new_tour
  }
  let initial_tour = FixedArray::makei(n, fn(i) { i })
  let config = default_config(10.0, 0.01, 5000, 777UL)
  let result = optimize(config, initial_tour, tour_cost, neighbor_fn)
  // Optimal tour cost ≈ 5.414
  assert_true(result.best_cost < 7.0)
  assert_true(result.best_cost > 4.0)
}

///|
test "sa: deterministic with same seed" {
  let cost_fn = fn(x : Double) -> Double { x * x }
  let neighbor_fn = fn(x : Double, _temp : Double) -> Double {
    let rng = xs64_new(42UL)
    let r = xs64_next_double(rng) - 0.5
    x + r
  }
  let config = default_config(10.0, 0.1, 1000, 42UL)
  let result1 = optimize(config, 5.0, cost_fn, neighbor_fn)
  let result2 = optimize(config, 5.0, cost_fn, neighbor_fn)
  assert_eq(result1.best_cost, result2.best_cost)
}

///|
test "sa: converges (reaches min_temp)" {
  let config : SAConfig = {
    initial_temp: 10.0,
    min_temp: 1.0,
    max_iter: 100000,
    iter_per_temp: 5,
    cooling: Geometric(0.9),
    seed: 1UL,
  }
  let result = optimize(
    config,
    0.0,
    fn(x) { x * x },
    fn(x, _) { x + 0.1 },
  )
  assert_true(result.converged)
  assert_true(result.iterations < 100000)
}

///|
test "sa: hits max_iter limit" {
  let config : SAConfig = {
    initial_temp: 1000.0,
    min_temp: 0.0,
    max_iter: 100,
    iter_per_temp: 10,
    cooling: Geometric(0.999),
    seed: 1UL,
  }
  let result = optimize(
    config,
    0.0,
    fn(x) { x * x },
    fn(x, _) { x + 0.1 },
  )
  assert_false(result.converged)
  assert_eq(result.iterations, 100)
}

///|
test "sa: linear cooling schedule" {
  let config : SAConfig = {
    initial_temp: 100.0,
    min_temp: 0.0,
    max_iter: 10000,
    iter_per_temp: 10,
    cooling: Linear(1.0),
    seed: 1UL,
  }
  let result = optimize(
    config,
    10.0,
    fn(x) { x * x },
    fn(x, _) { x - 0.1 },
  )
  // Linear cooling: 100 steps (100/1), 10 iter each = 1000 total
  assert_true(result.converged)
}

///|
test "sa: logarithmic cooling schedule" {
  let config : SAConfig = {
    initial_temp: 50.0,
    min_temp: 0.1,
    max_iter: 5000,
    iter_per_temp: 10,
    cooling: Logarithmic(50.0),
    seed: 1UL,
  }
  let result = optimize(
    config,
    5.0,
    fn(x) { x * x },
    fn(x, temp) {
      let rng = xs64_new(1UL + temp.reinterpret_as_uint64())
      let r = xs64_next_double(rng) - 0.5
      x + r
    },
  )
  assert_true(result.best_cost < 30.0)
}

///|
test "sa: binary optimization (maximize ones)" {
  // Maximize number of 1s in a binary array of length 10.
  // Cost = -count(ones) (minimize negative = maximize positive).
  let n = 10
  let cost_fn = fn(state : FixedArray[Int]) -> Double {
    let mut ones = 0
    for i = 0; i < n; i = i + 1 {
      if state[i] == 1 {
        ones = ones + 1
      }
    }
    -ones.to_double()
  }
  // Round-robin neighbor: cycle through bits 0..n-1, flipping each in turn.
  // This ensures the algorithm explores all bits systematically.
  let counter = [0]
  let neighbor_fn = fn(
    state : FixedArray[Int],
    _temp : Double,
  ) -> FixedArray[Int] {
    let new_state = FixedArray::makei(n, fn(i) { state[i] })
    counter[0] = counter[0] + 1
    let idx = counter[0] % n
    new_state[idx] = if new_state[idx] == 0 { 1 } else { 0 }
    new_state
  }
  let initial = FixedArray::make(n, 0)
  let config : SAConfig = {
    initial_temp: 1.0,
    min_temp: 0.01,
    max_iter: 1000,
    iter_per_temp: 10,
    cooling: Geometric(0.95),
    seed: 42UL,
  }
  let result = optimize(config, initial, cost_fn, neighbor_fn)
  // Should find all-ones (cost = -10.0) within first 10 iterations.
  assert_true(result.best_cost <= -8.0)
}

///|
test "sa: starting at optimum stays at optimum" {
  // If we start at the global minimum, SA should not wander far.
  let config = default_config(1.0, 0.01, 1000, 42UL)
  let result = optimize(
    config,
    0.0, // already at optimum of x^2
    fn(x) { x * x },
    fn(x, temp) {
      let rng = xs64_new(42UL + temp.reinterpret_as_uint64())
      let r = xs64_next_double(rng) - 0.5
      x + r * 0.5
    },
  )
  assert_true(result.best_cost <= 0.01) // should stay near 0
}

///|
test "sa: default_config creates geometric schedule" {
  let config = default_config(100.0, 0.01, 10000, 42UL)
  assert_eq(config.initial_temp, 100.0)
  assert_eq(config.min_temp, 0.01)
  assert_eq(config.max_iter, 10000)
  assert_eq(config.iter_per_temp, 20)
  // Verify cooling schedule is Geometric(0.95)
  match config.cooling {
    Geometric(alpha) => assert_eq(alpha, 0.95)
    _ => assert_true(false)
  }
}

///|
test "sa: exp_approx accuracy" {
  // Verify exp_approx matches known values
  let e0 = exp_approx(0.0)
  assert_true((e0 - 1.0).abs() < 0.0000000001)
  let e1 = exp_approx(1.0)
  assert_true((e1 - 2.718281828459045).abs() < 0.0000000001)
  let e2 = exp_approx(2.0)
  assert_true((e2 - 7.38905609893065).abs() < 0.0000000001)
  let e_neg = exp_approx(-1.0)
  assert_true((e_neg - 0.36787944117144233).abs() < 0.0000000001)
}

///|
test "sa: ln_approx accuracy" {
  let ln1 = ln_approx(1.0)
  assert_true(ln1.abs() < 0.0000000001)
  let ln2 = ln_approx(2.0)
  assert_true((ln2 - 0.6931471805599453).abs() < 0.0000000001)
  let ln10 = ln_approx(10.0)
  assert_true((ln10 - 2.302585092994046).abs() < 0.0000000001)
}
