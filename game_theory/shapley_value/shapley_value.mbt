///|
/// Shapley Value — cooperative game theory solution concept.
///
/// The Shapley value distributes the total worth of a coalition among its
/// members according to their average marginal contribution across all
/// possible orderings of the grand coalition.
///
/// ## Formula
///
/// For player `i` in a game with characteristic function `v`:
///
/// ```text
/// φ_i = Σ_{S ⊆ N\{i}} [|S|! × (n - |S| - 1)! / n!] × [v(S ∪ {i}) - v(S)]
/// ```
///
/// where `N = {0, ..., n-1}` is the set of all players.
///
/// ## Complexity
/// - Exact (bitmask): O(2^n × n) — feasible for n ≤ ~20.
/// - Approximate (Monte Carlo): O(samples × n) — for large n.
///
/// ## Axioms satisfied
/// - **Efficiency**: Σ φ_i = v(N)
/// - **Symmetry**: symmetric players get equal shares
/// - **Dummy**: dummy players get zero
/// - **Additivity**: φ(v + w) = φ(v) + φ(w)
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// SplitMix64 PRNG (for Monte Carlo approximation) — delegates to @utils
// ---------------------------------------------------------------------------

priv struct SMRng {
  mut state : Int64
}

///|
fn sm_next(rng : SMRng) -> Int64 {
  let (new_state, z) = @utils.splitmix64_next(rng.state)
  rng.state = new_state
  z
}

///|
fn sm_next_int(rng : SMRng, max_exclusive : Int) -> Int {
  if max_exclusive <= 0 {
    return 0
  }
  let v = sm_next(rng)
  // Round up to next power of 2 for rejection-free sampling.
  let mut pow2 = 1
  while pow2 < max_exclusive {
    pow2 = pow2 * 2
  }
  let masked = (v & (pow2 - 1).to_int64()).to_int()
  if masked < max_exclusive {
    masked
  } else {
    // Very unlikely rejection; just wrap.
    masked % max_exclusive
  }
}

// ---------------------------------------------------------------------------
// Exact Shapley value via bitmask DP
// ---------------------------------------------------------------------------

///|
/// Compute the exact Shapley value for `n` players.
///
/// # Parameters
/// - `v`: characteristic function mapping a coalition (bitmask) to its worth.
///   Coalition `0` (empty set) should have value `0`.
/// - `n`: number of players. Must be ≤ 20 for practical runtime.
///
/// # Returns
/// Array of `n` doubles — the Shapley value of each player.
///
/// # Complexity
/// O(2^n × n) time, O(2^n) space.
pub fn shapley_exact(v : (Int) -> Double, n : Int) -> FixedArray[Double] {
  if n <= 0 {
    return FixedArray::make(0, 0.0)
  }
  if n > 20 {
    // Fall back to Monte Carlo for large n.
    return shapley_approximate(v, n, 100000, 12345L)
  }
  let total = 1 << n
  // Precompute factorials.
  let fact = FixedArray::make(n + 1, 1.0)
  for i = 2; i <= n; i = i + 1 {
    fact[i] = fact[i - 1] * i.to_double()
  }
  let n_fact = fact[n]
  // shapley[i] = Σ_{S not containing i} [|S|! * (n-|S|-1)! / n!] * [v(S|i) - v(S)]
  let result = FixedArray::make(n, 0.0)
  // Precompute v for all coalitions.
  let v_table = FixedArray::make(total, 0.0)
  for mask = 0; mask < total; mask = mask + 1 {
    v_table[mask] = v(mask)
  }
  for i = 0; i < n; i = i + 1 {
    let bit_i = 1 << i
    let mut sum = 0.0
    for mask = 0; mask < total; mask = mask + 1 {
      if (mask & bit_i) != 0 {
        // Coalition includes i. S = mask without i.
        let s = mask ^ bit_i
        let s_size = popcount(s)
        let weight = fact[s_size] * fact[n - s_size - 1] / n_fact
        let marginal = v_table[mask] - v_table[s]
        sum = sum + weight * marginal
      }
    }
    result[i] = sum
  }
  result
}

///|
/// Count the number of set bits in an integer (population count).
fn popcount(x : Int) -> Int {
  let mut v = x
  let mut count = 0
  while v != 0 {
    count = count + 1
    v = v & (v - 1)
  }
  count
}

// ---------------------------------------------------------------------------
// Approximate Shapley value via Monte Carlo sampling
// ---------------------------------------------------------------------------

///|
/// Compute an approximate Shapley value using Monte Carlo sampling.
///
/// Generates `samples` random permutations of players and averages the
/// marginal contributions. Uses SplitMix64 for high-quality randomness.
///
/// # Parameters
/// - `v`: characteristic function.
/// - `n`: number of players.
/// - `samples`: number of random permutations to sample.
/// - `seed`: PRNG seed.
///
/// # Returns
/// Array of `n` doubles approximating the Shapley value.
pub fn shapley_approximate(
  v : (Int) -> Double,
  n : Int,
  samples : Int,
  seed : Int64,
) -> FixedArray[Double] {
  if n <= 0 {
    return FixedArray::make(0, 0.0)
  }
  if n == 1 {
    let result = FixedArray::make(1, 0.0)
    result[0] = v(1) // v({0}) - v(∅) = v(1) - v(0)
    return result
  }
  let rng = SMRng::{ state: seed }
  let result = FixedArray::make(n, 0.0)
  // Players array for shuffling.
  let players = FixedArray::makei(n, fn(i) { i })
  for s = 0; s < samples; s = s + 1 {
    // Fisher-Yates shuffle.
    for i = n - 1; i > 0; i = i - 1 {
      let j = sm_next_int(rng, i + 1)
      let tmp = players[i]
      players[i] = players[j]
      players[j] = tmp
    }
    // Compute marginal contributions in this permutation.
    let mut coalition = 0 // bitmask of players seen so far
    let mut v_prev = 0.0 // v(coalition) before adding current player
    for k = 0; k < n; k = k + 1 {
      let p = players[k]
      coalition = coalition | (1 << p)
      let v_new = v(coalition)
      let marginal = v_new - v_prev
      result[p] = result[p] + marginal
      v_prev = v_new
    }
  }
  // Average.
  let inv = 1.0 / samples.to_double()
  for i = 0; i < n; i = i + 1 {
    result[i] = result[i] * inv
  }
  result
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "shapley: two-player equal split" {
  // v(∅) = 0, v({0}) = 0, v({1}) = 0, v({0,1}) = 100
  // Both players contribute equally → Shapley = 50 each.
  let v = fn(mask : Int) -> Double {
    match mask {
      0 => 0.0
      1 => 0.0 // {0}
      2 => 0.0 // {1}
      3 => 100.0 // {0,1}
      _ => 0.0
    }
  }
  let result = shapley_exact(v, 2)
  assert_true(abs(result[0] - 50.0) < 0.001)
  assert_true(abs(result[1] - 50.0) < 0.001)
}

///|
test "shapley: efficiency (sum = v(N))" {
  // Random 3-player game.
  let v_table = [0.0, 10.0, 20.0, 40.0, 30.0, 50.0, 60.0, 100.0]
  let v = fn(mask : Int) -> Double { v_table[mask] }
  let result = shapley_exact(v, 3)
  let mut sum = 0.0
  for i = 0; i < 3; i = i + 1 {
    sum = sum + result[i]
  }
  assert_true(abs(sum - 100.0) < 0.001)
}

///|
test "shapley: dummy player gets zero" {
  // Player 2 is a dummy: adding them never changes the value.
  // v(S) = v(S ∪ {2}) for all S.
  let v = fn(mask : Int) -> Double {
    // Only players 0 and 1 matter.
    let m = mask & 3 // mask out player 2
    match m {
      0 => 0.0
      1 => 10.0
      2 => 20.0
      3 => 50.0
      _ => 0.0
    }
  }
  let result = shapley_exact(v, 3)
  assert_true(abs(result[2]) < 0.001)
}

///|
test "shapley: symmetry" {
  // Players 0 and 1 are symmetric (swapping them doesn't change v).
  let v = fn(mask : Int) -> Double {
    // v depends only on |S ∩ {0,1}|, not on which specific players.
    let count01 = (if (mask & 1) != 0 { 1 } else { 0 }) +
      (if (mask & 2) != 0 { 1 } else { 0 })
    let has2 = if (mask & 4) != 0 { 1 } else { 0 }
    (count01 * 10 + has2 * 5).to_double()
  }
  let result = shapley_exact(v, 3)
  assert_true(abs(result[0] - result[1]) < 0.001)
}

///|
test "shapley: approximate vs exact" {
  // Simple 4-player game: v(S) = |S|^2.
  let v = fn(mask : Int) -> Double {
    let sz = popcount(mask)
    (sz * sz).to_double()
  }
  let exact = shapley_exact(v, 4)
  let approx = shapley_approximate(v, 4, 50000, 42L)
  for i = 0; i < 4; i = i + 1 {
    assert_true(abs(exact[i] - approx[i]) < 1.0)
  }
}

///|
test "shapley: single player" {
  let v = fn(mask : Int) -> Double { if mask == 1 { 42.0 } else { 0.0 } }
  let result = shapley_exact(v, 1)
  assert_true(abs(result[0] - 42.0) < 0.001)
}

///|
test "shapley: zero game" {
  // All coalitions have value 0.
  let v = fn(_mask : Int) -> Double { 0.0 }
  let result = shapley_exact(v, 3)
  for i = 0; i < 3; i = i + 1 {
    assert_true(abs(result[i]) < 0.001)
  }
}

///|
test "shapley: unanimity game" {
  // Only the grand coalition has value 1; all others 0.
  let n = 3
  let grand = (1 << n) - 1
  let v = fn(mask : Int) -> Double { if mask == grand { 1.0 } else { 0.0 } }
  let result = shapley_exact(v, n)
  // Each player gets 1/n.
  for i = 0; i < n; i = i + 1 {
    assert_true(abs(result[i] - 1.0 / n.to_double()) < 0.001)
  }
}

// Helper for tests.

///|
fn abs(x : Double) -> Double {
  if x < 0.0 {
    -x
  } else {
    x
  }
}
