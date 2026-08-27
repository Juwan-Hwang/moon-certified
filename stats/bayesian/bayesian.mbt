/// Bayesian Inference — MCMC Sampling and Posterior Estimation.
///
/// This module provides production-grade Markov Chain Monte Carlo (MCMC)
/// algorithms for Bayesian inference:
///
/// - **Metropolis-Hastings**: general-purpose MCMC with symmetric
///   proposal distribution.
/// - **Gibbs Sampling**: for models with tractable full conditionals.
/// - **Hamiltonian Monte Carlo (HMC)**: gradient-based sampling for
///   high-dimensional posteriors.
/// - **Convergence diagnostics**: Gelman-Rubin R-hat, effective sample size.
///
/// ## Background
///
/// Bayesian inference updates beliefs about parameters θ given data D:
///
/// ```text
///   p(θ | D) ∝ p(D | θ) · p(θ)
/// ```
///
/// where `p(D | θ)` is the likelihood and `p(θ)` is the prior. The posterior
/// `p(θ | D)` is typically intractable, so we use MCMC to draw samples.
///
/// ## PRNG
///
/// All samplers use a deterministic xorshift128 PRNG for reproducibility.
/// The Box-Muller transform provides standard normal samples.
///
/// ## References
///
/// - Gelman, A. et al. *Bayesian Data Analysis*, 3rd ed., 2013.
/// - Brooks, S. et al. *Handbook of Markov Chain Monte Carlo*, 2011.
/// - Neal, R. "MCMC using Hamiltonian dynamics." 2011.
/// - Gelman, A. & Rubin, D. "Inference from iterative simulation." 1992.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// PRNG: xorshift128 — deterministic, reproducible
// ---------------------------------------------------------------------------

///|
/// Deterministic PRNG state for MCMC sampling.
pub struct Rng {
  mut s0 : UInt
  mut s1 : UInt
  mut s2 : UInt
  mut s3 : UInt
}

///|
/// Create a new PRNG with the given seed.
pub fn Rng::new(seed : UInt) -> Rng {
  // SplitMix32 to initialize all 4 state words from a single seed.
  let mut z = seed
  let next_state = fn() -> UInt {
    z = z + 0x9E3779B9U
    let mut t = z
    t = t ^ (t >> 16)
    t = t * 0x21F0AAADU
    t = t ^ (t >> 15)
    t = t * 0x735A2D97U
    t = t ^ (t >> 15)
    t
  }
  // Ensure no zero state.
  let s0 = next_state() | 1U
  let s1 = next_state() | 1U
  let s2 = next_state() | 1U
  let s3 = next_state() | 1U
  { s0, s1, s2, s3, }
}

///|
/// Generate the next 32-bit pseudo-random integer.
pub fn next_uint(rng : Rng) -> UInt {
  let t = rng.s0
  let s = rng.s3
  rng.s0 = rng.s1
  rng.s1 = rng.s2
  rng.s2 = s
  let mut v = t ^ (t << 11)
  v = v ^ (v >> 8)
  rng.s3 = v ^ s ^ (s >> 19)
  rng.s3
}

///|
/// Generate a uniform random double in [0, 1).
pub fn next_uniform(rng : Rng) -> Double {
  next_uint(rng).to_double() / 4294967296.0
}

///|
/// Generate a standard normal random variable using Box-Muller transform.
pub fn next_normal(rng : Rng) -> Double {
  let u1 = next_uniform(rng)
  let u2 = next_uniform(rng)
  // Avoid log(0).
  let u1_safe = if u1 < 1.0e-300 { 1.0e-300 } else { u1 }
  (-2.0 * @math.ln(u1_safe)).sqrt() *
  @math.cos(2.0 * 3.14159265358979323846 * u2)
}

// ---------------------------------------------------------------------------
// MCMC Sample storage and statistics
// ---------------------------------------------------------------------------

///|
/// A collection of MCMC samples for a single parameter.
pub struct MCMCSamples {
  /// Raw samples (including burn-in).
  samples : Array[Double]
  /// Number of burn-in samples to discard.
  mut burn_in : Int
  /// Thinning interval (keep every `thin`-th sample after burn-in).
  mut thin : Int
}

///|
/// Get the effective samples (post burn-in, post thinning).
pub fn effective_samples(s : MCMCSamples) -> Array[Double] {
  let result : Array[Double] = []
  let start = s.burn_in
  let n = s.samples.length()
  for i = start; i < n; i = i + 1 {
    if s.thin <= 1 || (i - start) % s.thin == 0 {
      result.push(s.samples[i])
    }
  }
  result
}

///|
/// Compute the mean of effective samples.
pub fn sample_mean(s : MCMCSamples) -> Double {
  let eff = effective_samples(s)
  if eff.length() == 0 {
    return 0.0
  }
  let mut sum = 0.0
  for i = 0; i < eff.length(); i = i + 1 {
    sum = sum + eff[i]
  }
  sum / eff.length().to_double()
}

///|
/// Compute the variance of effective samples.
pub fn sample_variance(s : MCMCSamples) -> Double {
  let eff = effective_samples(s)
  let n = eff.length()
  if n < 2 {
    return 0.0
  }
  let mean = sample_mean(s)
  let mut ss = 0.0
  for i = 0; i < n; i = i + 1 {
    let d = eff[i] - mean
    ss = ss + d * d
  }
  ss / (n - 1).to_double()
}

///|
/// Compute a credible interval [lower, upper] at the given level.
///
/// For example, `credible_interval(s, 0.95)` returns the 95% credible interval.
pub fn credible_interval(s : MCMCSamples, level : Double) -> (Double, Double) {
  let eff = effective_samples(s)
  let n = eff.length()
  if n == 0 {
    return (0.0, 0.0)
  }
  // Sort a copy.
  let sorted : Array[Double] = []
  for i = 0; i < n; i = i + 1 {
    sorted.push(eff[i])
  }
  sorted.sort()
  let alpha = 1.0 - level
  let lower_idx = (alpha / 2.0 * n.to_double()).to_int()
  let upper_idx = ((1.0 - alpha / 2.0) * n.to_double()).to_int() - 1
  let lo = if lower_idx < 0 { 0 } else { lower_idx }
  let hi = if upper_idx >= n { n - 1 } else { upper_idx }
  (sorted[lo], sorted[hi])
}

// ---------------------------------------------------------------------------
// Metropolis-Hastings
// ---------------------------------------------------------------------------

///|
/// Run Metropolis-Hastings MCMC for a 1D parameter.
///
/// Samples from `p(θ) ∝ exp(log_target(θ))` using a Gaussian random-walk
/// proposal with standard deviation `proposal_sd`.
///
/// # Parameters
/// - `log_target`: Log of the (unnormalized) target density. Takes the
///   current parameter value and returns the log density.
/// - `init`: Initial parameter value.
/// - `proposal_sd`: Standard deviation of the Gaussian proposal distribution.
/// - `num_samples`: Total number of MCMC iterations (including burn-in).
/// - `burn_in`: Number of initial samples to discard.
/// - `thin`: Thinning interval (keep every `thin`-th sample).
/// - `rng`: PRNG state.
///
/// # Returns
/// An `MCMCSamples` object containing all samples and metadata.
///
/// # Complexity
///
/// O(num_samples) evaluations of `log_target`.
pub fn metropolis_hastings(
  log_target : (Double) -> Double,
  init : Double,
  proposal_sd : Double,
  num_samples : Int,
  burn_in : Int,
  thin : Int,
  rng : Rng,
) -> MCMCSamples {
  let samples : Array[Double] = []
  let mut current = init
  let mut current_log = log_target(current)
  for i = 0; i < num_samples; i = i + 1 {
    // Propose new value via Gaussian random walk.
    let proposal = current + proposal_sd * next_normal(rng)
    let proposal_log = log_target(proposal)
    // Acceptance ratio: log α = log_target(proposal) - log_target(current)
    // (symmetric proposal, so q(x|y)/q(y|x) = 1).
    let log_alpha = proposal_log - current_log
    let log_u = @math.ln(next_uniform(rng))
    if log_u < log_alpha {
      current = proposal
      current_log = proposal_log
    }
    samples.push(current)
  }
  { samples, burn_in, thin: if thin < 1 { 1 } else { thin }, }
}

///|
/// Run Metropolis-Hastings for a multi-dimensional parameter.
///
/// Uses a multivariate Gaussian proposal with diagonal covariance
/// (each dimension has its own proposal_sd).
///
/// # Parameters
/// - `log_target`: Log of the (unnormalized) target density. Takes the
///   current parameter vector and returns the log density.
/// - `init`: Initial parameter vector.
/// - `proposal_sd`: Standard deviations for each dimension.
/// - `dim`: Number of dimensions.
/// - `num_samples`: Total number of MCMC iterations.
/// - `burn_in`: Number of burn-in samples.
/// - `thin`: Thinning interval.
/// - `rng`: PRNG state.
///
/// # Returns
/// Array of `MCMCSamples`, one per dimension.
pub fn metropolis_hastings_mv(
  log_target : (FixedArray[Double]) -> Double,
  init : FixedArray[Double],
  proposal_sd : FixedArray[Double],
  dim : Int,
  num_samples : Int,
  burn_in : Int,
  thin : Int,
  rng : Rng,
) -> Array[MCMCSamples] {
  let per_dim : Array[MCMCSamples] = []
  for d = 0; d < dim; d = d + 1 {
    per_dim.push({ samples: [], burn_in: 0, thin: 1, })
  }
  let current = FixedArray::make(dim, 0.0)
  for d = 0; d < dim; d = d + 1 {
    current[d] = init[d]
  }
  let mut current_log = log_target(current)
  for i = 0; i < num_samples; i = i + 1 {
    // Propose new vector.
    let proposal = FixedArray::make(dim, 0.0)
    for d = 0; d < dim; d = d + 1 {
      proposal[d] = current[d] + proposal_sd[d] * next_normal(rng)
    }
    let proposal_log = log_target(proposal)
    let log_alpha = proposal_log - current_log
    let log_u = @math.ln(next_uniform(rng))
    if log_u < log_alpha {
      for d = 0; d < dim; d = d + 1 {
        current[d] = proposal[d]
      }
      current_log = proposal_log
    }
    // Store samples.
    for d = 0; d < dim; d = d + 1 {
      per_dim[d].samples.push(current[d])
    }
  }
  let t = if thin < 1 { 1 } else { thin }
  for d = 0; d < dim; d = d + 1 {
    per_dim[d].burn_in = burn_in
    per_dim[d].thin = t
  }
  per_dim
}

// ---------------------------------------------------------------------------
// Gibbs Sampling
// ---------------------------------------------------------------------------

///|
/// Run Gibbs sampling for a multi-dimensional parameter.
///
/// Gibbs sampling cycles through dimensions, sampling each from its full
/// conditional distribution given the current values of all other dimensions.
///
/// # Parameters
/// - `conditional_sampler`: Function `(dim, current_state, rng) -> Double`
///   that samples a new value for dimension `dim` given the current state.
/// - `init`: Initial parameter vector.
/// - `dim`: Number of dimensions.
/// - `num_samples`: Total number of Gibbs iterations.
/// - `burn_in`: Number of burn-in samples.
/// - `thin`: Thinning interval.
/// - `rng`: PRNG state.
///
/// # Returns
/// Array of `MCMCSamples`, one per dimension.
///
/// # Complexity
///
/// O(num_samples · dim) calls to `conditional_sampler`.
pub fn gibbs_sampling(
  conditional_sampler : (Int, FixedArray[Double], Rng) -> Double,
  init : FixedArray[Double],
  dim : Int,
  num_samples : Int,
  burn_in : Int,
  thin : Int,
  rng : Rng,
) -> Array[MCMCSamples] {
  let per_dim : Array[MCMCSamples] = []
  for d = 0; d < dim; d = d + 1 {
    per_dim.push({ samples: [], burn_in: 0, thin: 1, })
  }
  let state = FixedArray::make(dim, 0.0)
  for d = 0; d < dim; d = d + 1 {
    state[d] = init[d]
  }
  for i = 0; i < num_samples; i = i + 1 {
    // Update each dimension in turn.
    for d = 0; d < dim; d = d + 1 {
      state[d] = conditional_sampler(d, state, rng)
    }
    // Store samples.
    for d = 0; d < dim; d = d + 1 {
      per_dim[d].samples.push(state[d])
    }
  }
  let t = if thin < 1 { 1 } else { thin }
  for d = 0; d < dim; d = d + 1 {
    per_dim[d].burn_in = burn_in
    per_dim[d].thin = t
  }
  per_dim
}

// ---------------------------------------------------------------------------
// Hamiltonian Monte Carlo
// ---------------------------------------------------------------------------

///|
/// Run Hamiltonian Monte Carlo for a 1D parameter.
///
/// HMC uses gradient information to propose efficient moves in the parameter
/// space. It simulates Hamiltonian dynamics using the leapfrog integrator.
///
/// The algorithm:
/// 1. Sample momentum p ~ N(0, 1).
/// 2. Simulate Hamiltonian dynamics for L leapfrog steps with step size ε.
/// 3. Accept/reject using the Metropolis criterion on the Hamiltonian.
///
/// # Parameters
/// - `log_target`: Log of the (unnormalized) target density.
/// - `grad_log_target`: Gradient of `log_target`.
/// - `init`: Initial parameter value.
/// - `step_size`: Leapfrog integrator step size ε.
/// - `num_leapfrog`: Number of leapfrog steps per proposal (L).
/// - `num_samples`: Total number of HMC iterations.
/// - `burn_in`: Number of burn-in samples.
/// - `thin`: Thinning interval.
/// - `rng`: PRNG state.
///
/// # Returns
/// An `MCMCSamples` object.
///
/// # Complexity
///
/// O(num_samples · num_leapfrog) gradient evaluations.
pub fn hmc(
  log_target : (Double) -> Double,
  grad_log_target : (Double) -> Double,
  init : Double,
  step_size : Double,
  num_leapfrog : Int,
  num_samples : Int,
  burn_in : Int,
  thin : Int,
  rng : Rng,
) -> MCMCSamples {
  let samples : Array[Double] = []
  let mut q = init
  let mut current_log = log_target(q)
  for i = 0; i < num_samples; i = i + 1 {
    // Save current position for potential revert on rejection.
    let q_old = q
    // Sample momentum p ~ N(0, 1).
    let p0 = next_normal(rng)
    let mut p = p0
    // Leapfrog integrator.
    // Half step for momentum.
    p = p - step_size * grad_log_target(q) / 2.0
    for step = 0; step < num_leapfrog; step = step + 1 {
      // Full step for position.
      q = q + step_size * p
      // Full step for momentum (except last step).
      if step < num_leapfrog - 1 {
        p = p - step_size * grad_log_target(q)
      }
    }
    // Half step for momentum at the end.
    p = p - step_size * grad_log_target(q) / 2.0
    // Negate momentum (for reversibility).
    p = -p
    // Compute Hamiltonians.
    let proposed_log = log_target(q)
    let current_H = -current_log + p0 * p0 / 2.0
    let proposed_H = -proposed_log + p * p / 2.0
    // Accept/reject using Metropolis criterion.
    let log_alpha = current_H - proposed_H
    let log_u = @math.ln(next_uniform(rng))
    if log_u < log_alpha {
      // Accept: keep the proposed q, update current log target.
      current_log = proposed_log
    } else {
      // Reject: revert to old position.
      q = q_old
    }
    samples.push(q)
  }
  { samples, burn_in, thin: if thin < 1 { 1 } else { thin }, }
}

// ---------------------------------------------------------------------------
// Convergence Diagnostics
// ---------------------------------------------------------------------------

///|
/// Compute the Gelman-Rubin R-hat (potential scale reduction factor).
///
/// R-hat compares the between-chain variance to the within-chain variance.
/// Values close to 1.0 indicate convergence; values > 1.1 suggest
/// the chains have not converged.
///
/// # Parameters
/// - `chains`: Array of MCMCSamples (one per chain).
///
/// # Returns
/// The R-hat statistic. Returns 1.0 if fewer than 2 chains.
pub fn gelman_rubin(chains : Array[MCMCSamples]) -> Double {
  let m = chains.length()
  if m < 2 {
    return 1.0
  }
  // Get effective samples from each chain.
  let eff_chains : Array[Array[Double]] = []
  for i = 0; i < m; i = i + 1 {
    eff_chains.push(effective_samples(chains[i]))
  }
  // Use the minimum chain length.
  let mut n = eff_chains[0].length()
  for i = 1; i < m; i = i + 1 {
    let ni = eff_chains[i].length()
    if ni < n {
      n = ni
    }
  }
  if n < 2 {
    return 1.0
  }
  // Compute chain means (using first n samples from each chain).
  let chain_means = FixedArray::make(m, 0.0)
  for i = 0; i < m; i = i + 1 {
    let mut sum = 0.0
    for j = 0; j < n; j = j + 1 {
      sum = sum + eff_chains[i][j]
    }
    chain_means[i] = sum / n.to_double()
  }
  // Overall mean.
  let mut overall_mean = 0.0
  for i = 0; i < m; i = i + 1 {
    overall_mean = overall_mean + chain_means[i]
  }
  overall_mean = overall_mean / m.to_double()
  // Between-chain variance B.
  let mut between_var = 0.0
  for i = 0; i < m; i = i + 1 {
    let diff = chain_means[i] - overall_mean
    between_var = between_var + diff * diff
  }
  between_var = between_var * n.to_double() / (m - 1).to_double()
  // Within-chain variance W.
  let mut within_var = 0.0
  for i = 0; i < m; i = i + 1 {
    let ci = eff_chains[i]
    let mut s2 = 0.0
    for j = 0; j < n; j = j + 1 {
      let diff = ci[j] - chain_means[i]
      s2 = s2 + diff * diff
    }
    s2 = s2 / (n - 1).to_double()
    within_var = within_var + s2
  }
  within_var = within_var / m.to_double()
  // Marginal posterior variance estimate.
  let var_hat = (n - 1).to_double() / n.to_double() * within_var +
    between_var / n.to_double()
  // R-hat.
  if within_var < 1.0e-300 {
    return 1.0
  }
  (var_hat / within_var).sqrt()
}

///|
/// Compute the effective sample size (ESS) for a single chain.
///
/// ESS estimates the number of independent samples represented by the
/// autocorrelated MCMC chain. It uses the autocorrelation function:
///
/// ```text
///   ESS = n / (1 + 2 * sum_{k=1}^{K} ρ_k)
/// ```
///
/// where ρ_k is the autocorrelation at lag k and K is the first lag
/// where the autocorrelation becomes negative.
///
/// # Parameters
/// - `s`: MCMC samples.
///
/// # Returns
/// The effective sample size (>= 1).
pub fn effective_sample_size(s : MCMCSamples) -> Double {
  let eff = effective_samples(s)
  let n = eff.length()
  if n < 2 {
    return n.to_double()
  }
  // Compute mean and variance.
  let mut mean = 0.0
  for i = 0; i < n; i = i + 1 {
    mean = mean + eff[i]
  }
  mean = mean / n.to_double()
  let mut variance = 0.0
  for i = 0; i < n; i = i + 1 {
    let d = eff[i] - mean
    variance = variance + d * d
  }
  variance = variance / (n - 1).to_double()
  if variance < 1.0e-300 {
    return n.to_double()
  }
  // Compute autocorrelations and sum until first negative.
  let mut acf_sum = 0.0
  let max_lag = if n / 2 < 1000 { n / 2 } else { 1000 }
  for lag = 1; lag <= max_lag; lag = lag + 1 {
    let mut cov = 0.0
    let count = n - lag
    for i = 0; i < count; i = i + 1 {
      cov = cov + (eff[i] - mean) * (eff[i + lag] - mean)
    }
    cov = cov / count.to_double()
    let rho = cov / variance
    if rho < 0.0 {
      break
    }
    acf_sum = acf_sum + rho
  }
  n.to_double() / (1.0 + 2.0 * acf_sum)
}

// ---------------------------------------------------------------------------
// Conjugate Models
// ---------------------------------------------------------------------------

///|
/// Bayesian estimation of a Normal mean with known variance.
///
/// Model: x_i ~ N(μ, σ²) with known σ².
/// Prior: μ ~ N(μ₀, τ₀²).
/// Posterior: μ | x ~ N(μ_n, τ_n²) where:
/// - τ_n² = 1 / (1/τ₀² + n/σ²)
/// - μ_n = τ_n² * (μ₀/τ₀² + sum(x_i)/σ²)
///
/// This is a conjugate model with a closed-form posterior.
///
/// # Parameters
/// - `data`: Observed data points.
/// - `n`: Number of data points.
/// - `sigma2`: Known variance σ².
/// - `prior_mean`: Prior mean μ₀.
/// - `prior_var`: Prior variance τ₀².
///
/// # Returns
/// `(posterior_mean, posterior_var)`.
pub fn normal_mean_conjugate(
  data : FixedArray[Double],
  n : Int,
  sigma2 : Double,
  prior_mean : Double,
  prior_var : Double,
) -> (Double, Double) {
  if n < 1 || sigma2 <= 0.0 || prior_var <= 0.0 {
    return (prior_mean, prior_var)
  }
  let mut sum = 0.0
  for i = 0; i < n; i = i + 1 {
    sum = sum + data[i]
  }
  let post_var = 1.0 / (1.0 / prior_var + n.to_double() / sigma2)
  let post_mean = post_var * (prior_mean / prior_var + sum / sigma2)
  (post_mean, post_var)
}

///|
/// Bayesian estimation of a Beta-Binomial model (conjugate).
///
/// Model: k ~ Binomial(n, p).
/// Prior: p ~ Beta(a, b).
/// Posterior: p | k ~ Beta(a + k, b + n - k).
///
/// # Parameters
/// - `successes`: Number of successes k.
/// - `trials`: Number of trials n.
/// - `prior_a`: Prior shape parameter a.
/// - `prior_b`: Prior shape parameter b.
///
/// # Returns
/// `(posterior_a, posterior_b)` — the parameters of the posterior Beta distribution.
pub fn beta_binomial_conjugate(
  successes : Int,
  trials : Int,
  prior_a : Double,
  prior_b : Double,
) -> (Double, Double) {
  if trials < 0 || successes < 0 || successes > trials {
    return (prior_a, prior_b)
  }
  (prior_a + successes.to_double(), prior_b + (trials - successes).to_double())
}

///|
/// Compute the posterior mean of a Beta(a, b) distribution.
///
/// E[p] = a / (a + b).
pub fn beta_mean(a : Double, b : Double) -> Double {
  if a + b <= 0.0 {
    return 0.0
  }
  a / (a + b)
}

///|
/// Compute the posterior variance of a Beta(a, b) distribution.
///
/// Var[p] = ab / ((a+b)² (a+b+1)).
pub fn beta_variance(a : Double, b : Double) -> Double {
  let s = a + b
  if s <= 0.0 || s + 1.0 <= 0.0 {
    return 0.0
  }
  a * b / (s * s * (s + 1.0))
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "rng: xorshift128 produces different values" {
  let rng = Rng::new(42U)
  let v1 = next_uint(rng)
  let v2 = next_uint(rng)
  let v3 = next_uint(rng)
  assert_true(v1 != v2)
  assert_true(v2 != v3)
  assert_true(v1 != v3)
}

///|
test "rng: deterministic with same seed" {
  let rng1 = Rng::new(123U)
  let rng2 = Rng::new(123U)
  for i = 0; i < 10; i = i + 1 {
    assert_eq(next_uint(rng1), next_uint(rng2))
  }
}

///|
test "rng: next_uniform in [0, 1)" {
  let rng = Rng::new(999U)
  for i = 0; i < 100; i = i + 1 {
    let u = next_uniform(rng)
    assert_true(u >= 0.0 && u < 1.0)
  }
}

///|
test "rng: next_normal has reasonable mean and variance" {
  let rng = Rng::new(7U)
  let n = 10000
  let mut sum = 0.0
  let mut sum_sq = 0.0
  for i = 0; i < n; i = i + 1 {
    let z = next_normal(rng)
    sum = sum + z
    sum_sq = sum_sq + z * z
  }
  let mean = sum / n.to_double()
  let variance = sum_sq / n.to_double() - mean * mean
  // Mean should be close to 0, variance close to 1.
  assert_true(mean.abs() < 0.05)
  assert_true((variance - 1.0).abs() < 0.1)
}

///|
test "metropolis_hastings: samples from standard normal" {
  let rng = Rng::new(42U)
  let log_target = fn(x : Double) -> Double { -0.5 * x * x }
  let result = metropolis_hastings(log_target, 0.0, 2.0, 5000, 1000, 1, rng)
  let mean = sample_mean(result)
  let variance = sample_variance(result)
  // Should be close to N(0, 1).
  assert_true(mean.abs() < 0.2)
  assert_true((variance - 1.0).abs() < 0.3)
}

///|
test "metropolis_hastings: samples from normal with known mean" {
  let rng = Rng::new(123U)
  let mu = 3.0
  let sigma = 2.0
  let log_target = fn(x : Double) -> Double {
    -0.5 * ((x - mu) / sigma) * ((x - mu) / sigma)
  }
  let result = metropolis_hastings(log_target, 0.0, 1.0, 5000, 1000, 1, rng)
  let mean = sample_mean(result)
  let variance = sample_variance(result)
  // Should be close to N(3, 4).
  assert_true((mean - mu).abs() < 0.3)
  assert_true((variance - sigma * sigma).abs() < 1.0)
}

///|
test "metropolis_hastings: burn_in discards early samples" {
  let rng = Rng::new(42U)
  let log_target = fn(x : Double) -> Double { -0.5 * x * x }
  let result = metropolis_hastings(log_target, 100.0, 1.0, 200, 100, 1, rng)
  let eff = effective_samples(result)
  // After burn-in of 100, should have 100 effective samples.
  assert_eq(eff.length(), 100)
}

///|
test "metropolis_hastings: thinning reduces sample count" {
  let rng = Rng::new(42U)
  let log_target = fn(x : Double) -> Double { -0.5 * x * x }
  let result = metropolis_hastings(log_target, 0.0, 1.0, 200, 50, 5, rng)
  let eff = effective_samples(result)
  // 150 samples after burn-in, thinned by 5 → 30 samples.
  assert_true(eff.length() <= 31)
  assert_true(eff.length() >= 29)
}

///|
test "metropolis_hastings_mv: 2D standard normal" {
  let rng = Rng::new(42U)
  let log_target = fn(v : FixedArray[Double]) -> Double {
    -0.5 * (v[0] * v[0] + v[1] * v[1])
  }
  let init = FixedArray::make(2, 0.0)
  let proposal_sd = FixedArray::make(2, 1.0)
  let result = metropolis_hastings_mv(
    log_target, init, proposal_sd, 2, 5000, 1000, 1, rng,
  )
  let mean0 = sample_mean(result[0])
  let mean1 = sample_mean(result[1])
  let var0 = sample_variance(result[0])
  let var1 = sample_variance(result[1])
  assert_true(mean0.abs() < 0.3)
  assert_true(mean1.abs() < 0.3)
  assert_true((var0 - 1.0).abs() < 0.4)
  assert_true((var1 - 1.0).abs() < 0.4)
}

///|
test "gibbs_sampling: bivariate normal with known conditionals" {
  let rng = Rng::new(42U)
  // Bivariate normal with ρ = 0.5, marginals N(0, 1).
  // Conditional: X | Y=y ~ N(ρ*y, 1-ρ²), Y | X=x ~ N(ρ*x, 1-ρ²).
  let rho = 0.5
  let cond_var = 1.0 - rho * rho
  let cond_std = cond_var.sqrt()
  let conditional_sampler = fn(
    dim : Int,
    state : FixedArray[Double],
    r : Rng,
  ) -> Double {
    if dim == 0 {
      rho * state[1] + cond_std * next_normal(r)
    } else {
      rho * state[0] + cond_std * next_normal(r)
    }
  }
  let init = FixedArray::make(2, 0.0)
  let result = gibbs_sampling(conditional_sampler, init, 2, 5000, 1000, 1, rng)
  let mean0 = sample_mean(result[0])
  let mean1 = sample_mean(result[1])
  let var0 = sample_variance(result[0])
  let var1 = sample_variance(result[1])
  assert_true(mean0.abs() < 0.2)
  assert_true(mean1.abs() < 0.2)
  assert_true((var0 - 1.0).abs() < 0.3)
  assert_true((var1 - 1.0).abs() < 0.3)
}

///|
test "hmc: samples from standard normal" {
  let rng = Rng::new(42U)
  let log_target = fn(x : Double) -> Double { -0.5 * x * x }
  let grad_log_target = fn(x : Double) -> Double { -x }
  let result = hmc(
    log_target, grad_log_target, 0.0, 0.3, 10, 5000, 1000, 1, rng,
  )
  let mean = sample_mean(result)
  let variance = sample_variance(result)
  // HMC should converge well for Gaussian targets.
  assert_true(mean.abs() < 0.2)
  assert_true((variance - 1.0).abs() < 0.3)
}

///|
test "hmc: samples from normal with nonzero mean" {
  let rng = Rng::new(77U)
  let mu = 5.0
  let sigma = 2.0
  let log_target = fn(x : Double) -> Double {
    -0.5 * ((x - mu) / sigma) * ((x - mu) / sigma)
  }
  let grad_log_target = fn(x : Double) -> Double { -(x - mu) / (sigma * sigma) }
  let result = hmc(
    log_target, grad_log_target, 0.0, 0.2, 15, 5000, 1000, 1, rng,
  )
  let mean = sample_mean(result)
  let variance = sample_variance(result)
  assert_true((mean - mu).abs() < 0.5)
  assert_true((variance - sigma * sigma).abs() < 1.0)
}

///|
test "gelman_rubin: converged chains have R-hat near 1" {
  let rng1 = Rng::new(1U)
  let rng2 = Rng::new(2U)
  let rng3 = Rng::new(3U)
  let log_target = fn(x : Double) -> Double { -0.5 * x * x }
  let chain1 = metropolis_hastings(log_target, 0.0, 2.0, 5000, 1000, 1, rng1)
  let chain2 = metropolis_hastings(log_target, 0.0, 2.0, 5000, 1000, 1, rng2)
  let chain3 = metropolis_hastings(log_target, 0.0, 2.0, 5000, 1000, 1, rng3)
  let rhat = gelman_rubin([chain1, chain2, chain3])
  // Converged chains should have R-hat < 1.1.
  assert_true(rhat < 1.1)
  assert_true(rhat >= 0.99)
}

///|
test "gelman_rubin: single chain returns 1.0" {
  let rng = Rng::new(42U)
  let log_target = fn(x : Double) -> Double { -0.5 * x * x }
  let chain = metropolis_hastings(log_target, 0.0, 1.0, 1000, 100, 1, rng)
  let rhat = gelman_rubin([chain])
  assert_true((rhat - 1.0).abs() < 1.0e-10)
}

///|
test "effective_sample_size: moderate proposal gives reasonable ESS" {
  let rng = Rng::new(42U)
  // Use optimal proposal_sd for N(0,1) in 1D (~2.4).
  let log_target = fn(x : Double) -> Double { -0.5 * x * x }
  let result = metropolis_hastings(log_target, 0.0, 2.4, 2000, 0, 1, rng)
  let ess = effective_sample_size(result)
  // With good proposal, ESS should be a reasonable fraction of n.
  assert_true(ess > 50.0)
}

///|
test "effective_sample_size: autocorrelated samples give lower ESS" {
  let rng = Rng::new(42U)
  let log_target = fn(x : Double) -> Double { -0.5 * x * x }
  // Small proposal_sd leads to high autocorrelation.
  let result = metropolis_hastings(log_target, 0.0, 0.1, 2000, 0, 1, rng)
  let ess = effective_sample_size(result)
  // ESS should be much less than 2000 for highly autocorrelated chain.
  assert_true(ess < 2000.0)
}

///|
test "credible_interval: 95% CI for standard normal" {
  let rng = Rng::new(42U)
  let log_target = fn(x : Double) -> Double { -0.5 * x * x }
  let result = metropolis_hastings(log_target, 0.0, 2.0, 10000, 2000, 1, rng)
  let (lo, hi) = credible_interval(result, 0.95)
  // 95% CI for N(0,1) is approximately [-1.96, 1.96].
  assert_true(lo < -1.5)
  assert_true(hi > 1.5)
  assert_true(lo > -2.5)
  assert_true(hi < 2.5)
}

///|
test "normal_mean_conjugate: basic update" {
  // Prior: N(0, 1), data: 3 points from N(2, 1).
  let data = FixedArray::make(3, 2.0)
  let (post_mean, post_var) = normal_mean_conjugate(data, 3, 1.0, 0.0, 1.0)
  // Posterior variance: 1 / (1/1 + 3/1) = 1/4 = 0.25.
  // Posterior mean: 0.25 * (0/1 + 6/1) = 0.25 * 6 = 1.5.
  assert_true((post_var - 0.25).abs() < 1.0e-10)
  assert_true((post_mean - 1.5).abs() < 1.0e-10)
}

///|
test "normal_mean_conjugate: prior dominates with little data" {
  // Strong prior N(10, 0.01), single data point at 0.
  let data = FixedArray::make(1, 0.0)
  let (post_mean, post_var) = normal_mean_conjugate(data, 1, 1.0, 10.0, 0.01)
  // Posterior variance: 1 / (1/0.01 + 1/1) = 1 / (100 + 1) ≈ 0.0099.
  // Posterior mean: 0.0099 * (10/0.01 + 0/1) = 0.0099 * 1000 = 9.9.
  assert_true((post_var - 1.0 / 101.0).abs() < 1.0e-6)
  assert_true((post_mean - 1000.0 / 101.0).abs() < 1.0e-6)
}

///|
test "normal_mean_conjugate: invalid inputs return prior" {
  let data = FixedArray::make(3, 1.0)
  let (mean, variance) = normal_mean_conjugate(data, 0, 1.0, 5.0, 2.0)
  assert_true((mean - 5.0).abs() < 1.0e-10)
  assert_true((variance - 2.0).abs() < 1.0e-10)
}

///|
test "beta_binomial_conjugate: basic update" {
  // Prior: Beta(1, 1) (uniform), 3 successes in 10 trials.
  let (post_a, post_b) = beta_binomial_conjugate(3, 10, 1.0, 1.0)
  // Posterior: Beta(1+3, 1+10-3) = Beta(4, 8).
  assert_true((post_a - 4.0).abs() < 1.0e-10)
  assert_true((post_b - 8.0).abs() < 1.0e-10)
}

///|
test "beta_binomial_conjugate: all successes" {
  let (post_a, post_b) = beta_binomial_conjugate(5, 5, 2.0, 3.0)
  // Posterior: Beta(2+5, 3+5-5) = Beta(7, 3).
  assert_true((post_a - 7.0).abs() < 1.0e-10)
  assert_true((post_b - 3.0).abs() < 1.0e-10)
}

///|
test "beta_binomial_conjugate: invalid inputs return prior" {
  let (a, b) = beta_binomial_conjugate(-1, 5, 1.0, 1.0)
  assert_true((a - 1.0).abs() < 1.0e-10)
  assert_true((b - 1.0).abs() < 1.0e-10)
}

///|
test "beta_mean: known values" {
  // Beta(1, 1): mean = 0.5.
  assert_true((beta_mean(1.0, 1.0) - 0.5).abs() < 1.0e-10)
  // Beta(2, 3): mean = 2/5 = 0.4.
  assert_true((beta_mean(2.0, 3.0) - 0.4).abs() < 1.0e-10)
  // Beta(3, 1): mean = 3/4 = 0.75.
  assert_true((beta_mean(3.0, 1.0) - 0.75).abs() < 1.0e-10)
}

///|
test "beta_variance: known values" {
  // Beta(1, 1): var = 1*1 / ((2)^2 * 3) = 1/12.
  assert_true((beta_variance(1.0, 1.0) - 1.0 / 12.0).abs() < 1.0e-10)
  // Beta(2, 2): var = 2*2 / ((4)^2 * 5) = 4/80 = 0.05.
  assert_true((beta_variance(2.0, 2.0) - 0.05).abs() < 1.0e-10)
}

///|
test "sample_mean: empty samples return zero" {
  let s : MCMCSamples = { samples: [], burn_in: 0, thin: 1, }
  assert_true(sample_mean(s) == 0.0)
}

///|
test "sample_variance: fewer than 2 samples returns zero" {
  let s : MCMCSamples = { samples: [1.0], burn_in: 0, thin: 1, }
  assert_true(sample_variance(s) == 0.0)
}

///|
test "effective_samples: empty samples" {
  let s : MCMCSamples = { samples: [], burn_in: 0, thin: 1, }
  let eff = effective_samples(s)
  assert_eq(eff.length(), 0)
}

///|
test "metropolis_hastings: rejects far proposals for peaked target" {
  let rng = Rng::new(42U)
  // Very peaked target: N(0, 0.01).
  let sigma = 0.1
  let log_target = fn(x : Double) -> Double { -0.5 * (x / sigma) * (x / sigma) }
  let result = metropolis_hastings(log_target, 0.0, 0.05, 5000, 1000, 1, rng)
  let mean = sample_mean(result)
  let variance = sample_variance(result)
  assert_true(mean.abs() < 0.05)
  assert_true((variance - sigma * sigma).abs() < 0.01)
}

///|
test "hmc: bimodal target sampling" {
  let rng = Rng::new(42U)
  // Bimodal: mixture of N(-3, 0.5) and N(3, 0.5).
  let log_target = fn(x : Double) -> Double {
    let d1 = x + 3.0
    let d2 = x - 3.0
    let e1 = -0.5 * d1 * d1 / 0.25
    let e2 = -0.5 * d2 * d2 / 0.25
    // log(exp(e1) + exp(e2)) via log-sum-exp.
    let m = if e1 > e2 { e1 } else { e2 }
    m + @math.ln(@math.exp(e1 - m) + @math.exp(e2 - m))
  }
  let grad_log_target = fn(x : Double) -> Double {
    let d1 = x + 3.0
    let d2 = x - 3.0
    let e1 = -0.5 * d1 * d1 / 0.25
    let e2 = -0.5 * d2 * d2 / 0.25
    let m = if e1 > e2 { e1 } else { e2 }
    let w1 = @math.exp(e1 - m)
    let w2 = @math.exp(e2 - m)
    let g1 = -d1 / 0.25 * w1
    let g2 = -d2 / 0.25 * w2
    (g1 + g2) / (w1 + w2)
  }
  let result = hmc(
    log_target, grad_log_target, 0.0, 0.1, 20, 10000, 2000, 1, rng,
  )
  let mean = sample_mean(result)
  // Mean of symmetric bimodal should be near 0.
  assert_true(mean.abs() < 0.5)
}

///|
test "gelman_rubin: non-converged chains have higher R-hat" {
  // Chains starting far apart with short runs.
  let rng1 = Rng::new(1U)
  let rng2 = Rng::new(2U)
  let log_target = fn(x : Double) -> Double { -0.5 * x * x }
  // Start one chain at +10 and another at -10, short run.
  let chain1 = metropolis_hastings(log_target, 10.0, 0.5, 200, 10, 1, rng1)
  let chain2 = metropolis_hastings(log_target, -10.0, 0.5, 200, 10, 1, rng2)
  let rhat = gelman_rubin([chain1, chain2])
  // Non-converged chains should have R-hat > 1.0.
  assert_true(rhat > 1.0)
}
