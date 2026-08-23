/// t-SNE (t-Distributed Stochastic Neighbor Embedding)
///
/// t-SNE is a non-linear dimensionality reduction technique that maps
/// high-dimensional data to 2D or 3D for visualization. It preserves local
/// structure by modeling pairwise similarities in both spaces.
///
/// ## Algorithm
/// 1. Compute pairwise affinities in high-D space (Gaussian kernel)
/// 2. Compute pairwise affinities in low-D space (Student-t kernel)
/// 3. Minimize KL divergence via gradient descent
///
/// ## References
/// - van der Maaten, Hinton. "Visualizing Data using t-SNE." JMLR 2008.
///
/// `proof-enabled` is `false`.

///|
/// t-SNE hyperparameters.
pub struct TSneParams {
  n_components : Int
  perplexity : Double
  n_iter : Int
  learning_rate : Double
  momentum : Double
  final_momentum : Double
  early_exaggeration : Double
}

///|
/// Default t-SNE parameters for 2D visualization.
pub fn tsne_default_params() -> TSneParams {
  {
    n_components: 2,
    perplexity: 30.0,
    n_iter: 1000,
    learning_rate: 200.0,
    momentum: 0.5,
    final_momentum: 0.8,
    early_exaggeration: 4.0,
  }
}

///|
/// Compute squared Euclidean distance between two vectors.
fn sq_dist(a : Array[Double], b : Array[Double]) -> Double {
  let mut sum = 0.0
  for i = 0; i < a.length() && i < b.length(); i = i + 1 {
    let d = a[i] - b[i]
    sum = sum + d * d
  }
  sum
}

///|
/// Compute pairwise squared distances matrix.
fn pairwise_sq_dist(x : Array[Array[Double]]) -> Array[Array[Double]] {
  let n = x.length()
  let d : Array[Array[Double]] = []
  for i = 0; i < n; i = i + 1 {
    d.push(Array::make(n, 0.0))
  }
  for i = 0; i < n; i = i + 1 {
    for j = i + 1; j < n; j = j + 1 {
      let dist = sq_dist(x[i], x[j])
      d[i][j] = dist
      d[j][i] = dist
    }
  }
  d
}

///|
/// Binary search for the sigma that achieves target perplexity.
fn find_sigma(
  distances : Array[Double],
  target_perplexity : Double,
  max_iter : Int,
) -> Double {
  let mut lo = 0.01
  let mut hi = 100.0
  let log_target = @math.ln(target_perplexity)
  for iter = 0; iter < max_iter; iter = iter + 1 {
    let sigma = (lo + hi) / 2.0
    // Compute P_j with current sigma
    let mut sum_exp = 0.0
    for d in distances {
      sum_exp = sum_exp + @math.exp(-d / (2.0 * sigma * sigma))
    }
    if sum_exp == 0.0 {
      lo = sigma
    } else {
      let mut entropy = 0.0
      for d in distances {
        let p = @math.exp(-d / (2.0 * sigma * sigma)) / sum_exp
        if p > 0.0 {
          entropy = entropy - p * @math.ln(p)
        }
      }
      // Perplexity = exp(entropy)
      if entropy > log_target {
        hi = sigma
      } else {
        lo = sigma
      }
    }
  }
  (lo + hi) / 2.0
}

///|
/// Compute the joint probability matrix P in high-D space.
fn compute_p(
  distances : Array[Array[Double]],
  perplexity : Double,
) -> Array[Array[Double]] {
  let n = distances.length()
  let p : Array[Array[Double]] = []
  for i = 0; i < n; i = i + 1 {
    p.push(Array::make(n, 0.0))
  }
  for i = 0; i < n; i = i + 1 {
    // Exclude self, find sigma
    let dists = Array::make(n - 1, 0.0)
    let mut idx = 0
    for j = 0; j < n; j = j + 1 {
      if j != i {
        dists[idx] = distances[i][j]
        idx = idx + 1
      }
    }
    let sigma = find_sigma(dists, perplexity, 50)
    let mut sum_exp = 0.0
    for j = 0; j < n; j = j + 1 {
      if j != i {
        let val = @math.exp(-distances[i][j] / (2.0 * sigma * sigma))
        p[i][j] = val
        sum_exp = sum_exp + val
      }
    }
    if sum_exp > 0.0 {
      for j = 0; j < n; j = j + 1 {
        p[i][j] = p[i][j] / sum_exp
      }
    }
  }
  // Symmetrize: P_ij = (P_j|i + P_i|j) / (2n)
  for i = 0; i < n; i = i + 1 {
    for j = i + 1; j < n; j = j + 1 {
      let avg = (p[i][j] + p[j][i]) / (2.0 * n.to_double())
      p[i][j] = avg
      p[j][i] = avg
    }
  }
  p
}

///|
/// Simple LCG random number generator.
fn lcg_next(seed : Int) -> Int {
  (seed * 1103515245 + 12345) & 0x7FFFFFFF
}

///|
/// Run t-SNE dimensionality reduction.
///
/// ## Parameters
/// - `x`: input data (n_samples × n_features)
/// - `params`: t-SNE hyperparameters
/// - `seed`: random seed for initialization
///
/// ## Returns
/// 2D embedding (n_samples × n_components)
pub fn tsne_fit(
  x : Array[Array[Double]],
  params : TSneParams,
  seed : Int,
) -> Array[Array[Double]] {
  let n = x.length()
  if n == 0 {
    return []
  }
  // Compute pairwise distances
  let distances = pairwise_sq_dist(x)
  // Compute P matrix
  let p = compute_p(distances, params.perplexity)
  // Initialize Y randomly (small Gaussian-like)
  let y : Array[Array[Double]] = []
  let gains : Array[Array[Double]] = []
  let iY : Array[Array[Double]] = []
  let mut rng = seed
  for i = 0; i < n; i = i + 1 {
    let row = Array::make(params.n_components, 0.0)
    for j = 0; j < params.n_components; j = j + 1 {
      rng = lcg_next(rng)
      row[j] = ((rng % 1000).to_double() - 500.0) / 1000.0 * 0.0001
    }
    y.push(row)
    gains.push(Array::make(params.n_components, 1.0))
    iY.push(Array::make(params.n_components, 0.0))
  }
  // Gradient descent
  for iter = 0; iter < params.n_iter; iter = iter + 1 {
    // Compute Q matrix (Student-t distribution)
    let q : Array[Array[Double]] = []
    for i = 0; i < n; i = i + 1 {
      q.push(Array::make(n, 0.0))
    }
    let mut sum_q = 0.0
    for i = 0; i < n; i = i + 1 {
      for j = i + 1; j < n; j = j + 1 {
        let dist = sq_dist(y[i], y[j])
        let q_val = 1.0 / (1.0 + dist)
        q[i][j] = q_val
        q[j][i] = q_val
        sum_q = sum_q + 2.0 * q_val
      }
    }
    if sum_q == 0.0 {
      sum_q = 1.0
    }
    // Compute gradients
    let grads : Array[Array[Double]] = []
    for i = 0; i < n; i = i + 1 {
      grads.push(Array::make(params.n_components, 0.0))
    }
    for i = 0; i < n; i = i + 1 {
      for j = 0; j < n; j = j + 1 {
        if i != j {
          let pq = (p[i][j] - q[i][j] / sum_q) * 4.0
          for k = 0; k < params.n_components; k = k + 1 {
            grads[i][k] = grads[i][k] + pq * (y[i][k] - y[j][k])
          }
        }
      }
    }
    // Update with momentum
    let mom = if iter < 250 { params.momentum } else { params.final_momentum }
    let exag = if iter < 100 { params.early_exaggeration } else { 1.0 }
    for i = 0; i < n; i = i + 1 {
      for k = 0; k < params.n_components; k = k + 1 {
        let grad = exag * grads[i][k]
        // Adaptive gain (Jacobs' delta-bar-delta)
        if (grad > 0.0) != (iY[i][k] > 0.0) {
          gains[i][k] = gains[i][k] + 0.2
        } else {
          gains[i][k] = gains[i][k] * 0.8
        }
        if gains[i][k] < 0.01 {
          gains[i][k] = 0.01
        }
        iY[i][k] = mom * iY[i][k] - params.learning_rate * gains[i][k] * grad
        y[i][k] = y[i][k] + iY[i][k]
      }
    }
  }
  y
}

///|
/// Compute the KL divergence between high-D and low-D representations.
pub fn tsne_kl_divergence(
  p : Array[Array[Double]],
  y : Array[Array[Double]],
) -> Double {
  let n = p.length()
  let mut kl = 0.0
  let mut sum_q = 0.0
  let q : Array[Array[Double]] = []
  for i = 0; i < n; i = i + 1 {
    q.push(Array::make(n, 0.0))
  }
  for i = 0; i < n; i = i + 1 {
    for j = i + 1; j < n; j = j + 1 {
      let dist = sq_dist(y[i], y[j])
      let q_val = 1.0 / (1.0 + dist)
      q[i][j] = q_val
      q[j][i] = q_val
      sum_q = sum_q + 2.0 * q_val
    }
  }
  if sum_q == 0.0 {
    sum_q = 1.0
  }
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      if i != j && p[i][j] > 0.0 {
        let q_val = q[i][j] / sum_q
        if q_val > 0.0 {
          kl = kl + p[i][j] * @math.ln(p[i][j] / q_val)
        }
      }
    }
  }
  kl
}

// ===========================================================================
// Tests
// ===========================================================================

///|
test "t-SNE: default params" {
  let p = tsne_default_params()
  assert_true(p.n_components == 2)
  assert_true(p.perplexity == 30.0)
  assert_true(p.n_iter == 1000)
}

///|
test "t-SNE: fit on small dataset" {
  let x = [
    [0.0, 0.0],
    [0.1, 0.1],
    [0.0, 0.1],
    [10.0, 10.0],
    [10.1, 10.1],
    [10.0, 10.1],
  ]
  let params : TSneParams = {
    n_components: 2,
    perplexity: 3.0,
    n_iter: 200,
    learning_rate: 100.0,
    momentum: 0.5,
    final_momentum: 0.8,
    early_exaggeration: 4.0,
  }
  let y = tsne_fit(x, params, 42)
  assert_true(y.length() == 6)
  assert_true(y[0].length() == 2)
  // Check output is finite
  for i = 0; i < 6; i = i + 1 {
    for j = 0; j < 2; j = j + 1 {
      assert_true(!y[i][j].is_nan())
    }
  }
}

///|
test "t-SNE: empty input" {
  let params = tsne_default_params()
  let y = tsne_fit([], params, 42)
  assert_true(y.length() == 0)
}

///|
test "t-SNE: KL divergence is finite" {
  let x = [[0.0, 0.0], [1.0, 1.0], [2.0, 2.0], [3.0, 3.0]]
  let params : TSneParams = {
    n_components: 2,
    perplexity: 2.0,
    n_iter: 100,
    learning_rate: 100.0,
    momentum: 0.5,
    final_momentum: 0.8,
    early_exaggeration: 4.0,
  }
  let y = tsne_fit(x, params, 42)
  let distances = pairwise_sq_dist(x)
  let p = compute_p(distances, params.perplexity)
  let kl = tsne_kl_divergence(p, y)
  assert_true(!kl.is_nan())
}
