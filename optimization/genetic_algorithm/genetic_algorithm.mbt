/// Genetic Algorithm — a population-based metaheuristic inspired by natural
/// selection.
///
/// A **Genetic Algorithm** (GA) maintains a **population** of candidate
/// solutions and evolves them over successive **generations**. Each generation,
/// the algorithm selects parents (favoring fitter individuals), combines them
/// via **crossover** to produce offspring, and applies random **mutations**.
/// The fittest individuals survive into the next generation (**elitism**).
///
/// ## Algorithm
///
/// ```text
/// population = initial_population
/// evaluate(population)
/// for g = 1 to max_generations:
///   new_pop = elites(population)
///   while |new_pop| < population_size:
///     parent1 = select(population)
///     parent2 = select(population)
///     if random() < crossover_rate:
///       child = crossover(parent1, parent2)
///     else:
///       child = parent1
///     if random() < mutation_rate:
///       child = mutate(child)
///     new_pop.add(child)
///   population = new_pop
///   evaluate(population)
/// return best(population)
/// ```
///
/// ## Selection
///
/// **Tournament selection** with configurable tournament size `k`: pick `k`
/// random individuals and select the fittest. Larger `k` increases selection
/// pressure (faster convergence, less diversity); `k = 1` is random selection.
///
/// ## Crossover
///
/// The user provides a crossover function `(parent1, parent2, rng) -> child`.
/// Common operators for array-based solutions:
/// - **Single-point**: copy from parent1 up to a random point, then from parent2.
/// - **Two-point**: copy from parent1 between two random points, parent2 elsewhere.
/// - **Uniform**: for each gene, randomly choose from parent1 or parent2.
///
/// ## Mutation
///
/// The user provides a mutation function `(individual, rng) -> individual`.
/// Common operators:
/// - **Random reset**: replace a random gene with a new random value.
/// - **Swap**: swap two random genes.
/// - **Scramble**: randomly shuffle a subset of genes.
///
/// ## Complexity
///
/// O(max_generations · population_size · cost_per_eval), where cost_per_eval
/// includes one fitness evaluation per offspring.
///
/// ## References
///
/// - Holland, J. H. (1975). *Adaptation in Natural and Artificial Systems*.
///   University of Michigan Press.
/// - Goldberg, D. E. (1989). *Genetic Algorithms in Search, Optimization, and
///   Machine Learning*. Addison-Wesley.
/// - Mitchell, M. (1996). *An Introduction to Genetic Algorithms*. MIT Press.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Public RNG type
// ---------------------------------------------------------------------------

///|
/// A deterministic PRNG (xorshift64) for use in user-supplied crossover
/// and mutation functions.
///
/// Created internally by `optimize` and passed to user callbacks. This ensures
/// reproducibility: the same `config.seed` always produces the same result.
pub struct GARng {
  mut state : UInt64
}

///|
/// Create a new RNG with the given seed. Avoids the all-zero state.
pub fn GARng::new(seed : UInt64) -> GARng {
  let s = if seed == 0UL { 0xDEADBEEFCAFEBABEUL } else { seed }
  { state: s, }
}

///|
/// Generate the next Double in [0, 1).
pub fn GARng::next_double(self : GARng) -> Double {
  let mut x = self.state
  x = x ^ (x << 13)
  x = x ^ (x >> 7)
  x = x ^ (x << 17)
  self.state = x
  let mantissa = ((x >> 11) & 0x1FFFFFFFFFFFFFUL).reinterpret_as_int64()
  mantissa.to_double() / 9007199254740992.0
}

///|
/// Generate the next Int in [0, n).
pub fn GARng::next_int(self : GARng, n : Int) -> Int {
  if n <= 0 {
    return 0
  }
  let d = self.next_double()
  (d * n.to_double()).to_int()
}

///|
/// Generate a random Bool with probability `p` of being `true`.
pub fn GARng::next_bool(self : GARng, p : Double) -> Bool {
  self.next_double() < p
}

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

///|
/// Configuration parameters for the genetic algorithm.
pub struct GAConfig {
  /// Maximum number of generations to evolve.
  max_generations : Int
  /// Population size. If 0, uses the size of the initial population.
  population_size : Int
  /// Probability of mutation per offspring (0.0 to 1.0).
  mutation_rate : Double
  /// Probability of crossover (vs. copying a parent) (0.0 to 1.0).
  crossover_rate : Double
  /// Tournament size for selection. Must be ≥ 1. Larger values increase
  /// selection pressure.
  tournament_size : Int
  /// Number of elite individuals preserved each generation.
  /// These are the best `elite_count` individuals that survive unchanged.
  elite_count : Int
  /// Seed for the deterministic PRNG (xorshift64).
  seed : UInt64
}

///|
/// Result of a genetic algorithm optimization run.
pub struct GAResult[T] {
  /// The best solution found.
  best : T
  /// Cost (fitness) of the best solution. Lower is better.
  best_cost : Double
  /// Number of generations evolved.
  generations : Int
  /// Number of times the best solution was improved.
  improvements : Int
}

// ---------------------------------------------------------------------------
// Internal: scored individual
// ---------------------------------------------------------------------------

///|
/// An individual paired with its cost, for efficient sorting.
priv struct Scored[T] {
  individual : T
  cost : Double
}

// ---------------------------------------------------------------------------
// Main optimization function
// ---------------------------------------------------------------------------

///|
/// Run a genetic algorithm to minimize an objective function.
///
/// # Parameters
/// - `config`: GA configuration (generations, population size, rates, etc.)
/// - `initial_population`: The starting population. Must be non-empty.
/// - `cost`: Objective function to minimize. Returns a `Double` (lower is better).
/// - `crossover`: Combines two parent solutions to produce an offspring.
///   Receives a `GARng` for randomness.
/// - `mutate`: Mutates an individual. Receives a `GARng` for randomness.
///
/// # Returns
/// A `GAResult[T]` containing the best solution found, its cost, generation
/// count, and improvement count.
///
/// # Determinism
/// The algorithm uses a deterministic xorshift64 PRNG seeded by `config.seed`,
/// so the same config + initial population always produces the same result.
pub fn[T] optimize(
  config : GAConfig,
  initial_population : Array[T],
  cost : (T) -> Double,
  crossover : (T, T, GARng) -> T,
  mutate : (T, GARng) -> T,
) -> GAResult[T] {
  let rng = GARng::new(config.seed)
  let pop_size = if config.population_size > 0 {
    config.population_size
  } else {
    initial_population.length()
  }
  let tour_size = if config.tournament_size < 1 {
    1
  } else {
    config.tournament_size
  }
  let elite_count = if config.elite_count < 0 { 0 } else { config.elite_count }
  // Initialize population with scores
  let mut population : Array[Scored[T]] = []
  for i = 0; i < initial_population.length(); i = i + 1 {
    population.push({
      individual: initial_population[i],
      cost: cost(initial_population[i]),
    })
  }
  // Track best
  let mut best = population[0].individual
  let mut best_cost = population[0].cost
  for i = 1; i < population.length(); i = i + 1 {
    if population[i].cost < best_cost {
      best = population[i].individual
      best_cost = population[i].cost
    }
  }
  let mut improvements = 0
  // Evolve
  for gen = 0; gen < config.max_generations; gen = gen + 1 {
    // Sort population by cost (ascending = best first)
    sort_population(population)
    // Update best
    if population[0].cost < best_cost {
      best = population[0].individual
      best_cost = population[0].cost
      improvements = improvements + 1
    }
    // Build new population
    let new_pop : Array[Scored[T]] = []
    // Copy elites
    let n_elite = if elite_count < pop_size { elite_count } else { pop_size }
    for i = 0; i < n_elite; i = i + 1 {
      new_pop.push(population[i])
    }
    // Generate offspring
    while new_pop.length() < pop_size {
      let parent1 = tournament_select(population, tour_size, rng)
      let parent2 = tournament_select(population, tour_size, rng)
      let child = if rng.next_bool(config.crossover_rate) {
        crossover(parent1.individual, parent2.individual, rng)
      } else {
        parent1.individual
      }
      let mutated = if rng.next_bool(config.mutation_rate) {
        mutate(child, rng)
      } else {
        child
      }
      new_pop.push({ individual: mutated, cost: cost(mutated), })
    }
    population = new_pop
  }
  // Final check for best
  sort_population(population)
  if population[0].cost < best_cost {
    best = population[0].individual
    best_cost = population[0].cost
    improvements = improvements + 1
  }
  { best, best_cost, generations: config.max_generations, improvements, }
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

///|
/// Tournament selection: pick `k` random individuals, return the best.
fn[T] tournament_select(
  population : Array[Scored[T]],
  k : Int,
  rng : GARng,
) -> Scored[T] {
  let n = population.length()
  let mut best_idx = rng.next_int(n)
  let mut best_cost = population[best_idx].cost
  for i = 1; i < k; i = i + 1 {
    let idx = rng.next_int(n)
    if population[idx].cost < best_cost {
      best_idx = idx
      best_cost = population[idx].cost
    }
  }
  population[best_idx]
}

///|
/// Sort population by cost (ascending) using insertion sort.
/// Population sizes are typically small (hundreds), so O(n²) is fine.
fn[T] sort_population(population : Array[Scored[T]]) -> Unit {
  let n = population.length()
  for i = 1; i < n; i = i + 1 {
    let key = population[i]
    let mut j = i - 1
    while j >= 0 && population[j].cost > key.cost {
      population[j + 1] = population[j]
      j = j - 1
    }
    population[j + 1] = key
  }
}

// ---------------------------------------------------------------------------
// Utility crossover operators for Array-based solutions
// ---------------------------------------------------------------------------

///|
/// Single-point crossover: copy from `a` up to a random point, then from `b`.
///
/// Both arrays must have the same length.
pub fn[T] single_point_crossover(
  a : Array[T],
  b : Array[T],
  rng : GARng,
) -> Array[T] {
  let n = a.length()
  let result : Array[T] = []
  if n == 0 {
    return result
  }
  let point = rng.next_int(n + 1)
  for i = 0; i < n; i = i + 1 {
    if i < point {
      result.push(a[i])
    } else {
      result.push(b[i])
    }
  }
  result
}

///|
/// Two-point crossover: copy from `a` between two random points, from `b`
/// elsewhere.
///
/// Both arrays must have the same length.
pub fn[T] two_point_crossover(
  a : Array[T],
  b : Array[T],
  rng : GARng,
) -> Array[T] {
  let n = a.length()
  let result : Array[T] = []
  if n == 0 {
    return result
  }
  let p1 = rng.next_int(n)
  let p2 = rng.next_int(n)
  let (lo, hi) = if p1 <= p2 { (p1, p2) } else { (p2, p1) }
  for i = 0; i < n; i = i + 1 {
    if i >= lo && i < hi {
      result.push(a[i])
    } else {
      result.push(b[i])
    }
  }
  result
}

///|
/// Uniform crossover: for each gene, randomly choose from `a` or `b`.
///
/// Both arrays must have the same length.
pub fn[T] uniform_crossover(
  a : Array[T],
  b : Array[T],
  rng : GARng,
) -> Array[T] {
  let n = a.length()
  let result : Array[T] = []
  for i = 0; i < n; i = i + 1 {
    if rng.next_bool(0.5) {
      result.push(a[i])
    } else {
      result.push(b[i])
    }
  }
  result
}

// ---------------------------------------------------------------------------
// Utility mutation operators for Array[Int] solutions
// ---------------------------------------------------------------------------

///|
/// Random-reset mutation: replace one random gene with a value in
/// `[min_val, max_val]`.
pub fn random_reset_mutation(
  arr : Array[Int],
  min_val : Int,
  max_val : Int,
  rng : GARng,
) -> Array[Int] {
  let n = arr.length()
  if n == 0 || max_val < min_val {
    return arr
  }
  let result : Array[Int] = []
  for i = 0; i < n; i = i + 1 {
    result.push(arr[i])
  }
  let idx = rng.next_int(n)
  let range = max_val - min_val + 1
  result[idx] = min_val + rng.next_int(range)
  result
}

///|
/// Swap mutation: swap two random genes.
pub fn swap_mutation(arr : Array[Int], rng : GARng) -> Array[Int] {
  let n = arr.length()
  if n < 2 {
    return arr
  }
  let result : Array[Int] = []
  for i = 0; i < n; i = i + 1 {
    result.push(arr[i])
  }
  let i = rng.next_int(n)
  let j = rng.next_int(n)
  let tmp = result[i]
  result[i] = result[j]
  result[j] = tmp
  result
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "ga: finds global minimum of quadratic" {
  // Minimize (x - 7)^2 where x ∈ [0, 14]
  let config : GAConfig = {
    max_generations: 50,
    population_size: 30,
    mutation_rate: 0.3,
    crossover_rate: 0.8,
    tournament_size: 3,
    elite_count: 2,
    seed: 42UL,
  }
  let result = optimize(
    config,
    [0, 2, 4, 6, 8, 10, 12, 14],
    fn(x : Int) -> Double {
      let d = x - 7
      d.to_double() * d.to_double()
    },
    fn(a : Int, b : Int, _rng : GARng) -> Int {
      if a == b {
        a
      } else {
        (a + b) / 2
      }
    },
    fn(x : Int, rng : GARng) -> Int {
      let result = x + (rng.next_int(3) - 1)
      if result < 0 {
        0
      } else if result > 14 {
        14
      } else {
        result
      }
    },
  )
  assert_eq(result.best, 7)
  assert_eq(result.best_cost, 0.0)
}

///|
test "ga: onemax problem" {
  // Maximize number of 1s in a binary array (minimize number of 0s)
  let config : GAConfig = {
    max_generations: 100,
    population_size: 50,
    mutation_rate: 0.1,
    crossover_rate: 0.9,
    tournament_size: 3,
    elite_count: 2,
    seed: 42UL,
  }
  // Initial population: random binary arrays of length 10
  let init_pop : Array[Array[Int]] = []
  let rng0 = GARng::new(99UL)
  for i = 0; i < 50; i = i + 1 {
    let ind : Array[Int] = []
    for j = 0; j < 10; j = j + 1 {
      ind.push(rng0.next_int(2))
    }
    init_pop.push(ind)
  }
  let result = optimize(
    config,
    init_pop,
    fn(arr : Array[Int]) -> Double {
      let mut zeros = 0.0
      for i = 0; i < arr.length(); i = i + 1 {
        if arr[i] == 0 {
          zeros = zeros + 1.0
        }
      }
      zeros
    },
    fn(a : Array[Int], b : Array[Int], rng : GARng) -> Array[Int] {
      single_point_crossover(a, b, rng)
    },
    fn(arr : Array[Int], rng : GARng) -> Array[Int] {
      random_reset_mutation(arr, 0, 1, rng)
    },
  )
  // Should find all-1s array
  assert_eq(result.best_cost, 0.0)
  for i = 0; i < 10; i = i + 1 {
    assert_eq(result.best[i], 1)
  }
}

///|
test "ga: determinism" {
  let config : GAConfig = {
    max_generations: 30,
    population_size: 20,
    mutation_rate: 0.2,
    crossover_rate: 0.8,
    tournament_size: 3,
    elite_count: 1,
    seed: 123UL,
  }
  let cost_fn = fn(x : Int) -> Double {
    let d = x - 5
    d.to_double() * d.to_double()
  }
  let cross_fn = fn(a : Int, b : Int, _ : GARng) -> Int { (a + b) / 2 }
  let mut_fn = fn(x : Int, rng : GARng) -> Int { x + (rng.next_int(3) - 1) }
  let r1 = optimize(
    config,
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 10],
    cost_fn,
    cross_fn,
    mut_fn,
  )
  let r2 = optimize(
    config,
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 10],
    cost_fn,
    cross_fn,
    mut_fn,
  )
  assert_eq(r1.best, r2.best)
  assert_eq(r1.best_cost, r2.best_cost)
}

///|
test "ga: elitism preserves best" {
  // With high elite count, the best should never get worse
  let config : GAConfig = {
    max_generations: 50,
    population_size: 20,
    mutation_rate: 0.5,
    crossover_rate: 0.9,
    tournament_size: 2,
    elite_count: 5,
    seed: 42UL,
  }
  let result = optimize(
    config,
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
    fn(x : Int) -> Double {
      let d = x - 5
      d.to_double() * d.to_double()
    },
    fn(a : Int, b : Int, _ : GARng) -> Int { (a + b) / 2 },
    fn(x : Int, rng : GARng) -> Int { x + (rng.next_int(5) - 2) },
  )
  // Best cost should be at most 0 (starting population includes 5)
  assert_true(result.best_cost <= 0.0)
}

///|
test "ga: improvements counter" {
  let config : GAConfig = {
    max_generations: 50,
    population_size: 30,
    mutation_rate: 0.3,
    crossover_rate: 0.8,
    tournament_size: 3,
    elite_count: 2,
    seed: 42UL,
  }
  let result = optimize(
    config,
    [0, 1, 2, 3, 10, 11, 12, 13, 14],
    fn(x : Int) -> Double {
      let d = x - 7
      d.to_double() * d.to_double()
    },
    fn(a : Int, b : Int, _ : GARng) -> Int { (a + b) / 2 },
    fn(x : Int, rng : GARng) -> Int { x + (rng.next_int(3) - 1) },
  )
  assert_true(result.improvements > 0)
  assert_eq(result.best, 7)
  assert_eq(result.best_cost, 0.0)
}

///|
test "ga: TSP small instance" {
  // 5-city TSP using permutation representation
  let dist = [
    [0, 2, 9, 1, 7],
    [2, 0, 3, 8, 5],
    [9, 3, 0, 6, 4],
    [1, 8, 6, 0, 5],
    [7, 5, 4, 5, 0],
  ]
  let config : GAConfig = {
    max_generations: 100,
    population_size: 30,
    mutation_rate: 0.3,
    crossover_rate: 0.8,
    tournament_size: 3,
    elite_count: 3,
    seed: 42UL,
  }
  // Initial population: random permutations of [0,1,2,3,4]
  let rng0 = GARng::new(77UL)
  let init_pop : Array[Array[Int]] = []
  for p = 0; p < 30; p = p + 1 {
    let perm = [0, 1, 2, 3, 4]
    // Shuffle
    for i = 4; i > 0; i = i - 1 {
      let j = rng0.next_int(i + 1)
      let tmp = perm[i]
      perm[i] = perm[j]
      perm[j] = tmp
    }
    init_pop.push(perm)
  }
  let result = optimize(
    config,
    init_pop,
    fn(tour : Array[Int]) -> Double {
      let mut total = 0.0
      for i = 0; i < tour.length(); i = i + 1 {
        let from = tour[i]
        let to = tour[(i + 1) % tour.length()]
        total = total + dist[from][to].to_double()
      }
      total
    },
    fn(a : Array[Int], b : Array[Int], rng : GARng) -> Array[Int] {
      // Order crossover (OX) for permutations
      let n = a.length()
      let p1 = rng.next_int(n)
      let p2 = rng.next_int(n)
      let (lo, hi) = if p1 <= p2 { (p1, p2) } else { (p2, p1) }
      let child : Array[Int] = Array::make(n, -1)
      // Copy segment from parent a
      for i = lo; i <= hi; i = i + 1 {
        child[i] = a[i]
      }
      // Fill remaining from parent b in order
      let mut b_idx = (hi + 1) % n
      let mut c_idx = (hi + 1) % n
      while b_idx != (hi + 1) % n || child[c_idx] == -1 {
        let val = b[b_idx]
        // Check if val is already in child
        let mut found = false
        for k = 0; k < n; k = k + 1 {
          if child[k] == val {
            found = true
            break
          }
        }
        if !found {
          child[c_idx] = val
          c_idx = (c_idx + 1) % n
        }
        b_idx = (b_idx + 1) % n
        if b_idx == (hi + 1) % n && child[c_idx] != -1 {
          break
        }
      }
      child
    },
    fn(tour : Array[Int], rng : GARng) -> Array[Int] {
      swap_mutation(tour, rng)
    },
  )
  // Optimal: 0→3→4→2→1→0 = 1+5+4+3+2 = 15
  assert_true(result.best_cost <= 20.0)
  // Verify valid permutation
  let visited : Array[Bool] = Array::make(5, false)
  for i = 0; i < 5; i = i + 1 {
    visited[result.best[i]] = true
  }
  for i = 0; i < 5; i = i + 1 {
    assert_true(visited[i])
  }
}

///|
test "ga: GARng reproducibility" {
  let r1 = GARng::new(42UL)
  let r2 = GARng::new(42UL)
  for i = 0; i < 100; i = i + 1 {
    assert_eq(r1.next_int(1000), r2.next_int(1000))
  }
}

///|
test "ga: single_point_crossover produces valid child" {
  let rng = GARng::new(42UL)
  let a = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
  let b = [10, 9, 8, 7, 6, 5, 4, 3, 2, 1]
  let child = single_point_crossover(a, b, rng)
  assert_eq(child.length(), 10)
  // Each element should come from either a or b at the same position
  for i = 0; i < 10; i = i + 1 {
    assert_true(child[i] == a[i] || child[i] == b[i])
  }
}

///|
test "ga: uniform_crossover produces valid child" {
  let rng = GARng::new(42UL)
  let a = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
  let b = [10, 9, 8, 7, 6, 5, 4, 3, 2, 1]
  let child = uniform_crossover(a, b, rng)
  assert_eq(child.length(), 10)
  for i = 0; i < 10; i = i + 1 {
    assert_true(child[i] == a[i] || child[i] == b[i])
  }
}

///|
test "ga: swap_mutation preserves multiset" {
  let rng = GARng::new(42UL)
  let arr = [1, 2, 3, 4, 5]
  let mutated = swap_mutation(arr, rng)
  // Length should be the same
  assert_eq(mutated.length(), 5)
  // Should contain the same elements (just reordered)
  let sorted_orig = [1, 2, 3, 4, 5]
  let sorted_mut : Array[Int] = []
  for i = 0; i < 5; i = i + 1 {
    sorted_mut.push(mutated[i])
  }
  // Insertion sort
  for i = 1; i < 5; i = i + 1 {
    let key = sorted_mut[i]
    let mut j = i - 1
    while j >= 0 && sorted_mut[j] > key {
      sorted_mut[j + 1] = sorted_mut[j]
      j = j - 1
    }
    sorted_mut[j + 1] = key
  }
  for i = 0; i < 5; i = i + 1 {
    assert_eq(sorted_mut[i], sorted_orig[i])
  }
}

///|
test "ga: random_reset_mutation changes at most one element" {
  let rng = GARng::new(42UL)
  let arr = [5, 5, 5, 5, 5]
  let mutated = random_reset_mutation(arr, 0, 9, rng)
  let mut diff_count = 0
  for i = 0; i < 5; i = i + 1 {
    if mutated[i] != arr[i] {
      diff_count = diff_count + 1
    }
  }
  assert_true(diff_count <= 1)
}
