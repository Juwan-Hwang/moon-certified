/// Gaussian Mixture Model (GMM) with Expectation-Maximization.
///
/// Fits a mixture of multivariate Gaussian distributions to data using
/// the EM algorithm. Supports diagonal covariance (for efficiency and
/// numerical stability) and provides soft cluster assignments.
///
/// ## Algorithm
///
/// 1. **Initialisation**: k-means++ style seeding for component means;
///    uniform mixing weights; data-variance-based covariance.
/// 2. **E-step**: compute posterior responsibilities γ(z_nk) for each
///    data point n and component k.
/// 3. **M-step**: update means, covariances, and mixing weights using
///    the responsibilities.
/// 4. **Convergence**: stop when the log-likelihood change falls below
///    a tolerance or the maximum iteration count is reached.
///
/// ## Complexity
///
/// O(n * k * d * iterations) where n = samples, k = components, d = dimensions.
///
/// ## References
///
/// - Dempster, A.P., Laird, N.M., and Rubin, D.B. "Maximum Likelihood from
///   Incomplete Data via the EM Algorithm." J. Royal Stat. Soc. B, 1977.
/// - Bishop, C. "Pattern Recognition and Machine Learning." Springer, 2006.
///
/// `proof-enabled` is `false`.

// ---------------------------------------------------------------------------
// Internal RNG (delegates to @utils)
// ---------------------------------------------------------------------------


priv struct Rng {
  mut state : Int
}

fn Rng::new(seed : Int) -> Rng {
  let s = seed & 0x7FFFFFFF
  { state: if s == 0 { 1 } else { s } }
}

fn Rng::next(self : Rng) -> Int {
  self.state = @utils.lcg_next(self.state)
  self.state
}

fn Rng::next_double(self : Rng) -> Double {
  self.next().to_double() / 2147483648.0
}

// ---------------------------------------------------------------------------
// Math helpers
// ---------------------------------------------------------------------------

/// Natural log approximation (Borchardt's algorithm via AGM).
fn ln(x : Double) -> Double {
  if x <= 0.0 {
    return -1.0e18
  }
  if x == 1.0 {
    return 0.0
  }
  // Argument reduction: find m such that x = m * 2^e, m in [1, 2)
  let mut m = x
  let mut e = 0
  while m >= 2.0 {
    m = m / 2.0
    e = e + 1
  }
  while m < 1.0 {
    m = m * 2.0
    e = e - 1
  }
  // ln(x) = e * ln(2) + ln(m), m in [1, 2)
  // Use series: ln(m) = 2 * sum_{k=0}^{inf} ((m-1)/(m+1))^(2k+1) / (2k+1)
  let t = (m - 1.0) / (m + 1.0)
  let mut sum = 0.0
  let mut t_pow = t
  let mut k = 0
  while k < 50 {
    let term = t_pow / (2 * k + 1).to_double()
    sum = sum + term
    t_pow = t_pow * t * t
    if term.abs() < 1.0e-16 {
      break
    }
    k = k + 1
  }
  e.to_double() * 0.6931471805599453 + 2.0 * sum
}

/// Exponential via Taylor series with range reduction.
fn exp(x : Double) -> Double {
  if x < -700.0 {
    return 0.0
  }
  if x > 700.0 {
    return 1.0e300
  }
  // exp(x) = exp(n) * exp(r) where x = n * ln(2) + r, |r| <= ln(2)/2
  let ln2 = 0.6931471805599453
  let n = (x / ln2).floor()
  let r = x - n * ln2
  // exp(r) via Taylor series
  let mut term = 1.0
  let mut sum = 1.0
  for k = 1; k <= 30; k = k + 1 {
    term = term * r / k.to_double()
    sum = sum + term
    if term.abs() < 1.0e-16 {
      break
    }
  }
  // 2^n
  let mut result = sum
  let p = n.to_int()
  if p >= 0 {
    for i = 0; i < p; i = i + 1 {
      result = result * 2.0
    }
  } else {
    for i = 0; i < -p; i = i + 1 {
      result = result / 2.0
    }
  }
  result
}

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

///|
/// A fitted Gaussian Mixture Model component (diagonal covariance).
pub struct GMMComponent {
  /// Mean vector (length d).
  mean : Array[Double]
  /// Diagonal covariance entries (variance per dimension).
  variance : Array[Double]
  /// Mixing weight (prior probability).
  mut weight : Double
}

///|
/// Result of fitting a GMM.
pub struct GMMResult {
  /// Mixture components.
  components : Array[GMMComponent]
  /// Log-likelihood of the data at convergence.
  log_likelihood : Double
  /// Number of EM iterations run.
  iterations : Int
}

// ---------------------------------------------------------------------------
// GMM fitting
// ---------------------------------------------------------------------------

///|
/// Fit a Gaussian Mixture Model with diagonal covariance.
///
/// - `data`: n points, each of dimension d.
/// - `k`: number of mixture components.
/// - `max_iter`: maximum EM iterations.
/// - `tol`: convergence tolerance on log-likelihood change.
/// - `seed`: RNG seed for initialisation.
pub fn fit(
  data : Array[Array[Double]],
  k : Int,
  max_iter : Int,
  tol : Double,
  seed : Int,
) -> GMMResult {
  let n = data.length()
  let d = if n > 0 { data[0].length() } else { 0 }
  if n == 0 || k <= 0 || d == 0 {
    return { components: [], log_likelihood: 0.0, iterations: 0 }
  }
  let kk = if k > n { n } else { k }
  let rng = Rng::new(seed)
  // --- Initialise means via k-means++ ---
  let means : Array[Array[Double]] = []
  let first = rng.next() % n
  means.push(copy_vec(data[first]))
  let min_sq : Array[Double] = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    min_sq[i] = sq_dist(data[i], means[0])
  }
  for c = 1; c < kk; c = c + 1 {
    let mut total = 0.0
    for i = 0; i < n; i = i + 1 {
      total = total + min_sq[i]
    }
    let target = rng.next_double() * total
    let mut cum = 0.0
    let mut chosen = n - 1
    for i = 0; i < n; i = i + 1 {
      cum = cum + min_sq[i]
      if cum >= target {
        chosen = i
        break
      }
    }
    means.push(copy_vec(data[chosen]))
    for i = 0; i < n; i = i + 1 {
      let dd = sq_dist(data[i], means[c])
      if dd < min_sq[i] {
        min_sq[i] = dd
      }
    }
  }
  // --- Initialise variances and weights ---
  // Use global data variance as initial covariance
  let global_var : Array[Double] = Array::make(d, 0.0)
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < d; j = j + 1 {
      global_var[j] = global_var[j] + data[i][j] * data[i][j]
    }
  }
  for j = 0; j < d; j = j + 1 {
    global_var[j] = global_var[j] / n.to_double()
    if global_var[j] < 1.0e-10 {
      global_var[j] = 1.0e-10
    }
  }
  let components : Array[GMMComponent] = []
  for c = 0; c < kk; c = c + 1 {
    components.push({
      mean: copy_vec(means[c]),
      variance: copy_vec(global_var),
      weight: 1.0 / kk.to_double(),
    })
  }
  // --- EM iterations ---
  let mut prev_ll = -1.0e18
  let mut iter = 0
  let log_2pi = 1.8378770664093453
  while iter < max_iter {
    iter = iter + 1
    // E-step: compute responsibilities
    let resp : Array[Array[Double]] = Array::make(n, [])
    for i = 0; i < n; i = i + 1 {
      resp[i] = Array::make(kk, 0.0)
    }
    let mut ll = 0.0
    for i = 0; i < n; i = i + 1 {
      let mut max_log = -1.0e18
      let log_probs : Array[Double] = Array::make(kk, 0.0)
      for c = 0; c < kk; c = c + 1 {
        // log N(x | mu, sigma) = -d/2 * log(2pi) - 0.5 * sum(log(var_j)) - 0.5 * sum((x-mu)^2 / var_j)
        let mut log_det = 0.0
        let mut mahal = 0.0
        for j = 0; j < d; j = j + 1 {
          let v = components[c].variance[j]
          if v < 1.0e-12 {
            log_det = log_det + ln(1.0e-12)
          } else {
            log_det = log_det + ln(v)
          }
          let diff = data[i][j] - components[c].mean[j]
          mahal = mahal + diff * diff / (if v < 1.0e-12 { 1.0e-12 } else { v })
        }
        let lp = ln(components[c].weight) - 0.5 * d.to_double() * log_2pi - 0.5 * log_det - 0.5 * mahal
        log_probs[c] = lp
        if lp > max_log {
          max_log = lp
        }
      }
      // Log-sum-exp for numerical stability
      let mut sum_exp = 0.0
      for c = 0; c < kk; c = c + 1 {
        sum_exp = sum_exp + exp(log_probs[c] - max_log)
      }
      let log_sum = max_log + ln(sum_exp)
      ll = ll + log_sum
      for c = 0; c < kk; c = c + 1 {
        resp[i][c] = exp(log_probs[c] - log_sum)
      }
    }
    // M-step: update parameters
    for c = 0; c < kk; c = c + 1 {
      let mut nk = 0.0
      let new_mean : Array[Double] = Array::make(d, 0.0)
      for i = 0; i < n; i = i + 1 {
        nk = nk + resp[i][c]
        for j = 0; j < d; j = j + 1 {
          new_mean[j] = new_mean[j] + resp[i][c] * data[i][j]
        }
      }
      if nk < 1.0e-10 {
        continue
      }
      for j = 0; j < d; j = j + 1 {
        new_mean[j] = new_mean[j] / nk
        components[c].mean[j] = new_mean[j]
      }
      // Update variance (diagonal)
      for j = 0; j < d; j = j + 1 {
        let mut var_val = 0.0
        for i = 0; i < n; i = i + 1 {
          let diff = data[i][j] - components[c].mean[j]
          var_val = var_val + resp[i][c] * diff * diff
        }
        var_val = var_val / nk
        // Regularise to avoid singular covariance
        if var_val < 1.0e-6 {
          var_val = 1.0e-6
        }
        components[c].variance[j] = var_val
      }
      components[c].weight = nk / n.to_double()
    }
    // Check convergence
    let ll_change = (ll - prev_ll).abs()
    prev_ll = ll
    if ll_change < tol && iter > 1 {
      break
    }
  }
  { components, log_likelihood: prev_ll, iterations: iter }
}

///|
/// Predict soft cluster assignments (responsibilities) for data points.
///
/// Returns an n×k matrix where entry (i, c) is the posterior probability
/// that point i belongs to component c.
pub fn predict_proba(result : GMMResult, data : Array[Array[Double]]) -> Array[Array[Double]] {
  let n = data.length()
  let kk = result.components.length()
  let d = if n > 0 { data[0].length() } else { 0 }
  let log_2pi = 1.8378770664093453
  let resp : Array[Array[Double]] = Array::make(n, [])
  for i = 0; i < n; i = i + 1 {
    resp[i] = Array::make(kk, 0.0)
    if kk == 0 || d == 0 {
      continue
    }
    let mut max_log = -1.0e18
    let log_probs : Array[Double] = Array::make(kk, 0.0)
    for c = 0; c < kk; c = c + 1 {
      let mut log_det = 0.0
      let mut mahal = 0.0
      for j = 0; j < d; j = j + 1 {
        let v = result.components[c].variance[j]
        let safe_v = if v < 1.0e-12 { 1.0e-12 } else { v }
        log_det = log_det + ln(safe_v)
        let diff = data[i][j] - result.components[c].mean[j]
        mahal = mahal + diff * diff / safe_v
      }
      let lp = ln(result.components[c].weight) - 0.5 * d.to_double() * log_2pi - 0.5 * log_det - 0.5 * mahal
      log_probs[c] = lp
      if lp > max_log {
        max_log = lp
      }
    }
    let mut sum_exp = 0.0
    for c = 0; c < kk; c = c + 1 {
      sum_exp = sum_exp + exp(log_probs[c] - max_log)
    }
    let log_sum = max_log + ln(sum_exp)
    for c = 0; c < kk; c = c + 1 {
      resp[i][c] = exp(log_probs[c] - log_sum)
    }
  }
  resp
}

///|
/// Predict hard cluster labels (argmax of responsibilities).
pub fn predict(result : GMMResult, data : Array[Array[Double]]) -> Array[Int] {
  let probs = predict_proba(result, data)
  let n = probs.length()
  let labels : Array[Int] = Array::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    let mut best_c = 0
    let mut best_p = -1.0
    for c = 0; c < probs[i].length(); c = c + 1 {
      if probs[i][c] > best_p {
        best_p = probs[i][c]
        best_c = c
      }
    }
    labels[i] = best_c
  }
  labels
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

fn sq_dist(a : Array[Double], b : Array[Double]) -> Double {
  let n = a.length()
  let mut sum = 0.0
  for i = 0; i < n; i = i + 1 {
    let d = a[i] - b[i]
    sum = sum + d * d
  }
  sum
}

fn copy_vec(v : Array[Double]) -> Array[Double] {
  let r : Array[Double] = []
  for i = 0; i < v.length(); i = i + 1 {
    r.push(v[i])
  }
  r
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "gmm: two well-separated 1D clusters" {
  let data : Array[Array[Double]] = []
  for i = 0; i < 20; i = i + 1 {
    data.push([0.0 + (i % 3).to_double() * 0.1])
  }
  for i = 0; i < 20; i = i + 1 {
    data.push([10.0 + (i % 3).to_double() * 0.1])
  }
  let result = fit(data, 2, 100, 1.0e-6, 42)
  assert_eq(result.components.length(), 2)
  let labels = predict(result, data)
  // First 20 should be one cluster, last 20 another
  assert_eq(labels[0], labels[5])
  assert_eq(labels[20], labels[25])
  assert_not_eq(labels[0], labels[20])
}

///|
test "gmm: single component" {
  let data : Array[Array[Double]] = []
  for i = 0; i < 10; i = i + 1 {
    data.push([i.to_double()])
  }
  let result = fit(data, 1, 50, 1.0e-6, 1)
  assert_eq(result.components.length(), 1)
  // Mean should be close to 4.5
  let mean = result.components[0].mean[0]
  assert_true((mean - 4.5).abs() < 1.0)
}

///|
test "gmm: 2D clusters" {
  let data : Array[Array[Double]] = []
  for i = 0; i < 15; i = i + 1 {
    data.push([0.0 + (i % 4).to_double() * 0.2, 0.0 + (i % 3).to_double() * 0.2])
  }
  for i = 0; i < 15; i = i + 1 {
    data.push([8.0 + (i % 4).to_double() * 0.2, 8.0 + (i % 3).to_double() * 0.2])
  }
  let result = fit(data, 2, 100, 1.0e-6, 7)
  assert_eq(result.components.length(), 2)
  let labels = predict(result, data)
  assert_not_eq(labels[0], labels[15])
}

///|
test "gmm: predict_proba sums to 1" {
  let data : Array[Array[Double]] = []
  for i = 0; i < 10; i = i + 1 {
    data.push([i.to_double()])
  }
  let result = fit(data, 3, 50, 1.0e-6, 99)
  let probs = predict_proba(result, data)
  for i = 0; i < data.length(); i = i + 1 {
    let mut sum = 0.0
    for c = 0; c < probs[i].length(); c = c + 1 {
      sum = sum + probs[i][c]
    }
    assert_true((sum - 1.0).abs() < 1.0e-6)
  }
}

///|
test "gmm: weights sum to 1" {
  let data : Array[Array[Double]] = []
  for i = 0; i < 20; i = i + 1 {
    data.push([i.to_double() * 0.5])
  }
  let result = fit(data, 3, 50, 1.0e-6, 123)
  let mut w_sum = 0.0
  for c = 0; c < result.components.length(); c = c + 1 {
    w_sum = w_sum + result.components[c].weight
  }
  assert_true((w_sum - 1.0).abs() < 1.0e-6)
}

///|
test "gmm: empty data" {
  let data : Array[Array[Double]] = []
  let result = fit(data, 2, 10, 1.0e-6, 1)
  assert_eq(result.components.length(), 0)
}

///|
test "gmm: log-likelihood increases" {
  let data : Array[Array[Double]] = []
  for i = 0; i < 30; i = i + 1 {
    if i < 15 {
      data.push([0.0 + (i % 5).to_double() * 0.1])
    } else {
      data.push([5.0 + (i % 5).to_double() * 0.1])
    }
  }
  // Run with few iterations
  let r1 = fit(data, 2, 1, 1.0e-6, 55)
  let r2 = fit(data, 2, 50, 1.0e-6, 55)
  // More iterations should give higher (or equal) log-likelihood
  assert_true(r2.log_likelihood >= r1.log_likelihood - 0.1)
}
