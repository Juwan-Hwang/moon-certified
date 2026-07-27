///|
/// Metropolis-Hastings MCMC sampler.
///
/// Draws samples from any unnormalised target density `p(x)` via a symmetric
/// random-walk Gaussian proposal. Each iteration proposes
/// x' ~ N(current, proposal_std^2) and accepts with probability
/// min(1, p(x') / p(current)). The chain converges to the target distribution
/// as iterations approach infinity. Because the Gaussian proposal is
/// symmetric, the Hastings ratio reduces to the target ratio.

// xorshift64 PRNG for tests.
priv struct Rng {
  mut state : Int64
}

///|
fn make_rng(seed : Int64) -> () -> Double {
  let r = { state: if seed == 0L { 0x9E3779B97F4A7C15L } else { seed } }
  fn() {
    let mut x = r.state
    x = x ^ (x << 13)
    x = x ^ (x >> 7)
    x = x ^ (x << 17)
    r.state = x
    let abs_x = if x < 0L { -x } else { x }
    (abs_x & 0x001FFFFFFFFFFFFFL).to_double() / 9007199254740992.0
  }
}

///|
/// Draw one N(0, std^2) sample via Box-Muller.
fn normal_sample(std : Double, rng : () -> Double) -> Double {
  let u1 = 1.0 - rng()
  let u2 = rng()
  let r = (-2.0 * @math.ln(u1)).sqrt()
  let theta = 2.0 * @math.PI * u2
  r * @math.cos(theta) * std
}

///|
/// Run MH-MCMC, returning all `iterations` samples (including burn-in).
pub fn metropolis_hastings(
  target : (Double) -> Double,
  initial : Double,
  iterations : Int,
  proposal_std : Double,
  rng : () -> Double,
) -> Array[Double] {
  let samples = Array::make(iterations, 0.0)
  let mut current = initial
  for i = 0; i < iterations; i = i + 1 {
    let proposal = current + normal_sample(proposal_std, rng)
    let t_cur = target(current)
    let t_prop = target(proposal)
    // Acceptance: min(1, t_prop / t_cur). When t_cur <= 0, accept iff
    // t_prop > 0; otherwise reject (handles 0/0 gracefully).
    let accept = if t_cur <= 0.0 {
      t_prop > 0.0
    } else {
      t_prop / t_cur > rng()
    }
    if accept {
      current = proposal
    }
    samples[i] = current
  }
  samples
}

///|
/// Sample mean of an array of doubles.
pub fn mcmc_mean(samples : Array[Double]) -> Double {
  let mut sum = 0.0
  for i = 0; i < samples.length(); i = i + 1 {
    sum = sum + samples[i]
  }
  sum / samples.length().to_double()
}

///|
/// Sample standard deviation (population, dividing by n).
pub fn mcmc_std(samples : Array[Double]) -> Double {
  let n = samples.length().to_double()
  let mean = mcmc_mean(samples)
  let mut sum_sq = 0.0
  for i = 0; i < samples.length(); i = i + 1 {
    let d = samples[i] - mean
    sum_sq = sum_sq + d * d
  }
  let variance = sum_sq / n
  if variance <= 0.0 {
    0.0
  } else {
    variance.sqrt()
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "mcmc: standard normal — mean near 0" {
  let rng = make_rng(42L)
  let target = fn(x) { @math.exp(-x * x / 2.0) }
  let samples = metropolis_hastings(target, 0.0, 50000, 2.0, rng)
  let burn_in = 5000
  let post = Array::make(samples.length() - burn_in, 0.0)
  for i = 0; i < post.length(); i = i + 1 {
    post[i] = samples[burn_in + i]
  }
  assert_true(mcmc_mean(post).abs() < 0.1)
}

///|
test "mcmc: standard normal — std near 1" {
  let rng = make_rng(137L)
  let target = fn(x) { @math.exp(-x * x / 2.0) }
  let samples = metropolis_hastings(target, 0.0, 50000, 2.0, rng)
  let burn_in = 5000
  let post = Array::make(samples.length() - burn_in, 0.0)
  for i = 0; i < post.length(); i = i + 1 {
    post[i] = samples[burn_in + i]
  }
  assert_true((mcmc_std(post) - 1.0).abs() < 0.15)
}

///|
test "mcmc: exponential target — mean near 1" {
  // Target: exp(-x) for x >= 0, which is Exponential(1) with mean 1.
  let rng = make_rng(999L)
  let target = fn(x : Double) { if x < 0.0 { 0.0 } else { @math.exp(-x) } }
  let samples = metropolis_hastings(target, 0.5, 50000, 1.5, rng)
  let burn_in = 5000
  let post = Array::make(samples.length() - burn_in, 0.0)
  for i = 0; i < post.length(); i = i + 1 {
    post[i] = samples[burn_in + i]
  }
  // Mean of Exp(1) is 1.0; allow generous tolerance for MCMC noise.
  assert_true((mcmc_mean(post) - 1.0).abs() < 0.2)
}

///|
test "mcmc: bimodal target — samples explore both modes" {
  // Target: 0.5 * N(-3, 1) + 0.5 * N(3, 1), unnormalised.
  let rng = make_rng(2024L)
  let target = fn(x : Double) {
    @math.exp(-(x + 3.0) * (x + 3.0) / 2.0) +
    @math.exp(-(x - 3.0) * (x - 3.0) / 2.0)
  }
  let samples = metropolis_hastings(target, 0.0, 50000, 5.0, rng)
  let burn_in = 5000
  // Count samples near each mode (within 2 of -3 or +3).
  let mut left = 0
  let mut right = 0
  for i = burn_in; i < samples.length(); i = i + 1 {
    if samples[i] < 0.0 {
      left = left + 1
    } else {
      right = right + 1
    }
  }
  // Both modes should have substantial representation.
  assert_true(left > 5000)
  assert_true(right > 5000)
}

///|
test "mcmc: deterministic seed reproducibility" {
  let rng1 = make_rng(42L)
  let rng2 = make_rng(42L)
  let target = fn(x : Double) { @math.exp(-x * x) }
  let s1 = metropolis_hastings(target, 0.0, 1000, 1.0, rng1)
  let s2 = metropolis_hastings(target, 0.0, 1000, 1.0, rng2)
  for i = 0; i < s1.length(); i = i + 1 {
    assert_eq(s1[i], s2[i])
  }
}

///|
test "mcmc: single sample edge case" {
  let rng = make_rng(7L)
  let target = fn(_x : Double) { 1.0 }
  let samples = metropolis_hastings(target, 0.0, 1, 1.0, rng)
  assert_eq(samples.length(), 1)
}
