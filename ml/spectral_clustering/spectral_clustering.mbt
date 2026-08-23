/// Spectral Clustering via normalized graph Laplacian.
///
/// Spectral clustering transforms the data into a low-dimensional embedding
/// using the eigenvectors of the graph Laplacian, then applies K-Means in
/// that embedding space. It excels at non-convex cluster shapes (concentric
/// circles, moons, etc.) that K-Means cannot handle.
///
/// ## Algorithm (Ng–Jordan–Weiss)
/// 1. **Affinity matrix** `W`: pairwise similarities via Gaussian RBF kernel
///    `W_ij = exp(−γ · ‖x_i − x_j‖²)` or k-nearest-neighbor graph.
/// 2. **Degree matrix** `D` (diagonal): `D_ii = Σ_j W_ij`.
/// 3. **Normalised affinity**: `L = D^{−1/2} W D^{−1/2}`.
/// 4. **Eigendecomposition**: find the `k` **largest** eigenvectors of `L`
///    (equivalently the `k` smallest eigenvectors of the Laplacian
///    `I − L`). Stack them as columns → matrix `U ∈ ℝ^{n×k}`.
/// 5. **Row-normalise** `U` so each row has unit L2 norm.
/// 6. **K-Means** on the rows of `U` to produce `k` clusters.
///
/// ## Complexity
/// - Time:  `O(n² · d)` for affinity + `O(n² · k · iter)` for power
///   iteration + `O(n · k · kmeans_iter)` for K-Means.
/// - Space: `O(n²)` for the affinity matrix.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

///|
/// Maximum power-iteration sweeps per eigenvector.
let sc_max_iter : Int = 500

///|
/// Relative convergence tolerance for power iteration.
let sc_tol : Double = 1.0e-10

///|
/// Default K-Means iterations for the embedding step.
let sc_kmeans_iter : Int = 300

///|
/// Default PRNG seed.
let sc_default_seed : Int = 0x1A2B3C4D

// ---------------------------------------------------------------------------
// Geometry helpers
// ---------------------------------------------------------------------------

///|
/// Squared Euclidean distance between two vectors.
fn sc_sq_dist(a : Array[Double], b : Array[Double]) -> Double {
  let n = a.length()
  let mut s = 0.0
  for i = 0; i < n; i = i + 1 {
    let diff = a[i] - b[i]
    s = s + diff * diff
  }
  s
}

///|
/// L2 norm of a vector.
fn sc_l2_norm(v : Array[Double]) -> Double {
  let mut s = 0.0
  for i = 0; i < v.length(); i = i + 1 {
    s = s + v[i] * v[i]
  }
  s.sqrt()
}

///|
/// Dot product of two equal-length vectors.
fn sc_dot(a : Array[Double], b : Array[Double]) -> Double {
  let n = a.length()
  let mut s = 0.0
  for i = 0; i < n; i = i + 1 {
    s = s + a[i] * b[i]
  }
  s
}

// ---------------------------------------------------------------------------
// Affinity matrix construction
// ---------------------------------------------------------------------------

///|
/// Affinity mode for spectral clustering.
pub enum AffinityMode {
  /// Gaussian RBF: W_ij = exp(−γ · ‖x_i − x_j‖²)
  RBF
  /// k-nearest-neighbors graph (symmetric: edge if either is in the
  /// other's k-NN). Gamma is used for edge weights (RBF within neighbors).
  KNN
} derive(Eq, Debug)

///|
/// Build the n×n affinity matrix.
///
/// - `RBF` mode: `W_ij = exp(−γ · ‖x_i − x_j‖²)`, diagonal = 0.
/// - `KNN` mode: For each point, find its `n_neighbors` nearest neighbors.
///   `W_ij = exp(−γ · ‖x_i − x_j‖²)` if `i ∈ kNN(j)` or `j ∈ kNN(i)`,
///   else 0. This makes the graph symmetric (undirected).
fn build_affinity(
  data : Array[Array[Double]],
  mode : AffinityMode,
  gamma : Double,
  n_neighbors : Int,
) -> Array[Array[Double]] {
  let n = data.length()
  let w : Array[Array[Double]] = []
  for i = 0; i < n; i = i + 1 {
    w.push(Array::make(n, 0.0))
  }
  match mode {
    RBF =>
      for i = 0; i < n; i = i + 1 {
        for j = i + 1; j < n; j = j + 1 {
          let sq_d = sc_sq_dist(data[i], data[j])
          let val = @math.exp(-gamma * sq_d)
          w[i][j] = val
          w[j][i] = val
        }
      }
    KNN => {
      // For each point, find n_neighbors nearest neighbors
      let k = if n_neighbors > 0 && n_neighbors < n {
        n_neighbors
      } else if n > 1 {
        n - 1
      } else {
        0
      }
      for i = 0; i < n; i = i + 1 {
        // Compute distances to all other points
        let dist_idx : Array[Int] = []
        let dist_val : Array[Double] = []
        for j = 0; j < n; j = j + 1 {
          if i != j {
            dist_idx.push(j)
            dist_val.push(sc_sq_dist(data[i], data[j]))
          }
        }
        // Sort by distance (selection sort; n is typically small)
        let m = dist_idx.length()
        for a = 0; a < m - 1; a = a + 1 {
          let mut min_idx = a
          for b = a + 1; b < m; b = b + 1 {
            if dist_val[b] < dist_val[min_idx] {
              min_idx = b
            }
          }
          if min_idx != a {
            let tmp_idx = dist_idx[a]
            dist_idx[a] = dist_idx[min_idx]
            dist_idx[min_idx] = tmp_idx
            let tmp_val = dist_val[a]
            dist_val[a] = dist_val[min_idx]
            dist_val[min_idx] = tmp_val
          }
        }
        // Take top-k nearest and set affinity
        let take = if k < m { k } else { m }
        for a = 0; a < take; a = a + 1 {
          let j = dist_idx[a]
          let val = @math.exp(-gamma * dist_val[a])
          // Use max for symmetry
          if val > w[i][j] {
            w[i][j] = val
          }
          if val > w[j][i] {
            w[j][i] = val
          }
        }
      }
    }
  }
  w
}

// ---------------------------------------------------------------------------
// Normalized Laplacian / affinity
// ---------------------------------------------------------------------------

///|
/// Compute the normalized affinity matrix `L = D^{−1/2} W D^{−1/2}`.
///
/// `D` is the degree matrix (diagonal, `D_ii = Σ_j W_ij`). The result is
/// symmetric and its largest eigenvectors correspond to the smallest
/// eigenvectors of the graph Laplacian `I − L`.
fn normalized_affinity(w : Array[Array[Double]]) -> Array[Array[Double]] {
  let n = w.length()
  // Compute D^{-1/2}
  let d_inv_sqrt = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    let mut deg = 0.0
    for j = 0; j < n; j = j + 1 {
      deg = deg + w[i][j]
    }
    if deg > 0.0 {
      d_inv_sqrt[i] = 1.0 / deg.sqrt()
    }
  }
  // L = D^{-1/2} W D^{-1/2}
  let l : Array[Array[Double]] = []
  for i = 0; i < n; i = i + 1 {
    let row = Array::make(n, 0.0)
    for j = 0; j < n; j = j + 1 {
      row[j] = d_inv_sqrt[i] * w[i][j] * d_inv_sqrt[j]
    }
    l.push(row)
  }
  l
}

// ---------------------------------------------------------------------------
// Power iteration with deflation (for largest eigenvalues)
// ---------------------------------------------------------------------------

///|
/// Matrix-vector product `out = M · v`.
fn sc_mat_vec(m : Array[Array[Double]], v : Array[Double]) -> Array[Double] {
  let n = m.length()
  let out = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    let row = m[i]
    let mut s = 0.0
    for j = 0; j < n; j = j + 1 {
      s = s + row[j] * v[j]
    }
    out[i] = s
  }
  out
}

///|
/// In-place Gram-Schmidt orthogonalization against previously found vectors.
fn sc_orthogonalize(v : Array[Double], prev : Array[Array[Double]]) -> Unit {
  for k = 0; k < prev.length(); k = k + 1 {
    let u = prev[k]
    let proj = sc_dot(v, u)
    for i = 0; i < v.length(); i = i + 1 {
      v[i] = v[i] - proj * u[i]
    }
  }
}

///|
/// Normalize v in place to unit L2 norm. Returns pre-normalization norm.
fn sc_normalize(v : Array[Double]) -> Double {
  let nrm = sc_l2_norm(v)
  if nrm > 0.0 {
    for i = 0; i < v.length(); i = i + 1 {
      v[i] = v[i] / nrm
    }
  }
  nrm
}

///|
/// Pin the sign of an eigenvector: largest-magnitude entry is positive.
fn sc_fix_sign(v : Array[Double]) -> Unit {
  let n = v.length()
  if n == 0 {
    return
  }
  let mut max_idx = 0
  let mut max_abs = v[0].abs()
  for i = 1; i < n; i = i + 1 {
    let a = v[i].abs()
    if a > max_abs {
      max_abs = a
      max_idx = i
    }
  }
  if v[max_idx] < 0.0 {
    for i = 0; i < n; i = i + 1 {
      v[i] = -v[i]
    }
  }
}

///|
/// Build an initial vector for power iteration. Uses a deterministic
/// pseudo-random draw, orthogonalized against `prev`. If the result
/// collapses to near-zero (lands in span(prev)), falls back to canonical
/// basis vectors. This ensures we always find a valid starting direction
/// even when the matrix has degenerate eigenvalues (e.g., disconnected
/// graph components where the all-ones vector is already captured).
fn sc_init_vector(
  n : Int,
  prev : Array[Array[Double]],
  seed : Int,
) -> Array[Double] {
  // Try pseudo-random initialization
  let v = Array::make(n, 0.0)
  let mut state = seed
  for i = 0; i < n; i = i + 1 {
    state = @utils.lcg_next(state)
    v[i] = state.to_double() / 2147483648.0 - 0.5
  }
  sc_orthogonalize(v, prev)
  let nrm = sc_l2_norm(v)
  if nrm > 1.0e-10 {
    for i = 0; i < n; i = i + 1 {
      v[i] = v[i] / nrm
    }
    return v
  }
  // Fallback: try canonical basis vectors
  for j = 0; j < n; j = j + 1 {
    let e = Array::make(n, 0.0)
    e[j] = 1.0
    sc_orthogonalize(e, prev)
    let en = sc_l2_norm(e)
    if en > 1.0e-10 {
      for i = 0; i < n; i = i + 1 {
        e[i] = e[i] / en
      }
      return e
    }
  }
  // Last resort: return zero vector (will be handled by caller)
  v
}

///|
/// Power iteration to find the dominant eigenvector of `m` restricted to
/// the orthogonal complement of `prev`. Returns (eigenvector, eigenvalue).
fn sc_power_iteration(
  m : Array[Array[Double]],
  n : Int,
  prev : Array[Array[Double]],
  seed : Int,
) -> (Array[Double], Double) {
  // Use varied seed per component for diverse initialization
  let init_seed = seed + prev.length() * 7919
  let v = sc_init_vector(n, prev, init_seed)
  let mut lambda = sc_dot(v, sc_mat_vec(m, v))
  for iter = 0; iter < sc_max_iter; iter = iter + 1 {
    let w = sc_mat_vec(m, v)
    sc_orthogonalize(w, prev)
    let nrm = sc_normalize(w)
    if nrm < sc_tol {
      // Null space direction
      lambda = 0.0
      break
    }
    // Copy w into v
    for i = 0; i < n; i = i + 1 {
      v[i] = w[i]
    }
    let new_lambda = sc_dot(v, sc_mat_vec(m, v))
    if (new_lambda - lambda).abs() <= sc_tol * (1.0 + lambda.abs()) {
      lambda = new_lambda
      break
    }
    lambda = new_lambda
  }
  sc_fix_sign(v)
  (v, lambda)
}

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

///|
/// Configuration for Spectral Clustering.
pub struct SpectralConfig {
  /// Number of clusters.
  n_clusters : Int
  /// Affinity mode (RBF or KNN).
  affinity : AffinityMode
  /// RBF gamma. If ≤ 0, set to `1 / n_features`.
  gamma : Double
  /// Number of neighbors for KNN affinity (ignored for RBF).
  n_neighbors : Int
  /// Maximum K-Means iterations on the embedding.
  kmeans_max_iter : Int
  /// PRNG seed.
  seed : Int
}

///|
/// Result of spectral clustering.
pub struct SpectralResult {
  /// Cluster label for each input point.
  labels : Array[Int]
  /// Cluster centres in the spectral embedding space.
  cluster_centers : Array[Array[Double]]
  /// The spectral embedding (n × n_clusters matrix, row-normalized).
  embedding : Array[Array[Double]]
  /// Affinity matrix used.
  affinity_matrix : Array[Array[Double]]
  /// Eigenvalues of the normalized affinity (top n_clusters).
  eigenvalues : Array[Double]
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

///|
/// Create a default Spectral Clustering configuration with RBF affinity.
pub fn SpectralConfig::default(
  n_clusters : Int,
  n_features : Int,
) -> SpectralConfig {
  let g = if n_features > 0 { 1.0 / n_features.to_double() } else { 1.0 }
  {
    n_clusters,
    affinity: RBF,
    gamma: g,
    n_neighbors: 10,
    kmeans_max_iter: sc_kmeans_iter,
    seed: sc_default_seed,
  }
}

///|
/// Create an RBF configuration with a specific gamma.
pub fn spectral_rbf_config(n_clusters : Int, gamma : Double) -> SpectralConfig {
  {
    n_clusters,
    affinity: RBF,
    gamma,
    n_neighbors: 10,
    kmeans_max_iter: sc_kmeans_iter,
    seed: sc_default_seed,
  }
}

///|
/// Create a KNN configuration.
pub fn spectral_knn_config(
  n_clusters : Int,
  n_neighbors : Int,
  gamma : Double,
) -> SpectralConfig {
  {
    n_clusters,
    affinity: KNN,
    gamma,
    n_neighbors,
    kmeans_max_iter: sc_kmeans_iter,
    seed: sc_default_seed,
  }
}

///|
/// Run Spectral Clustering on `data`.
///
/// **Parameters.**
/// - `data` — sample matrix, rows = samples, cols = features.
/// - `config` — configuration including number of clusters, affinity mode,
///   gamma, etc.
///
/// **Returns.** A `SpectralResult` with per-point labels, cluster centres
/// (in embedding space), the spectral embedding, the affinity matrix, and
/// the top eigenvalues.
///
/// **Edge cases.**
/// - Empty data → 0 labels, empty embedding.
/// - n_clusters ≤ 0 → treated as 1.
/// - n_clusters ≥ n → each point is its own cluster.
pub fn spectral_clustering(
  data : Array[Array[Double]],
  config : SpectralConfig,
) -> SpectralResult {
  let n = data.length()
  if n == 0 {
    return {
      labels: [],
      cluster_centers: [],
      embedding: [],
      affinity_matrix: [],
      eigenvalues: [],
    }
  }
  let d = if n > 0 { data[0].length() } else { 0 }
  let k = if config.n_clusters < 1 {
    1
  } else if config.n_clusters > n {
    n
  } else {
    config.n_clusters
  }
  // Determine gamma
  let gamma = if config.gamma > 0.0 {
    config.gamma
  } else if d > 0 {
    1.0 / d.to_double()
  } else {
    1.0
  }
  // 1. Build affinity matrix
  let w = build_affinity(data, config.affinity, gamma, config.n_neighbors)
  // 2. Normalized affinity L = D^{-1/2} W D^{-1/2}
  let l = normalized_affinity(w)
  // 3. Eigendecomposition: find k largest eigenvectors of L
  let eigenvectors : Array[Array[Double]] = []
  let eigenvalues : Array[Double] = []
  for c = 0; c < k; c = c + 1 {
    let (v, lambda) = sc_power_iteration(l, n, eigenvectors, config.seed)
    // Store a copy
    let v_copy = Array::make(n, 0.0)
    for i = 0; i < n; i = i + 1 {
      v_copy[i] = v[i]
    }
    eigenvectors.push(v_copy)
    eigenvalues.push(lambda)
  }
  // Sort eigenvectors by eigenvalue descending (selection sort; k is small)
  for a = 0; a < k - 1; a = a + 1 {
    let mut max_idx = a
    for b = a + 1; b < k; b = b + 1 {
      if eigenvalues[b] > eigenvalues[max_idx] {
        max_idx = b
      }
    }
    if max_idx != a {
      let tmp_val = eigenvalues[a]
      eigenvalues[a] = eigenvalues[max_idx]
      eigenvalues[max_idx] = tmp_val
      let tmp_vec = eigenvectors[a]
      eigenvectors[a] = eigenvectors[max_idx]
      eigenvectors[max_idx] = tmp_vec
    }
  }
  // 4. Build embedding matrix U (n × k): each row is [v_0[i], v_1[i], ..., v_{k-1}[i]]
  let embedding : Array[Array[Double]] = []
  for i = 0; i < n; i = i + 1 {
    let row = Array::make(k, 0.0)
    for c = 0; c < k; c = c + 1 {
      row[c] = eigenvectors[c][i]
    }
    embedding.push(row)
  }
  // 5. Row-normalize embedding to unit L2 norm (Ng-Jordan-Weiss)
  for i = 0; i < n; i = i + 1 {
    let nrm = sc_l2_norm(embedding[i])
    if nrm > 0.0 {
      for j = 0; j < k; j = j + 1 {
        embedding[i][j] = embedding[i][j] / nrm
      }
    }
  }
  // 6. K-Means on the embedding
  let km_result = @kmeans.kmeans_with_seed(
    embedding,
    k,
    config.kmeans_max_iter,
    config.seed,
  )
  {
    labels: km_result.assignments,
    cluster_centers: km_result.centroids,
    embedding,
    affinity_matrix: w,
    eigenvalues,
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "spectral: two concentric circles" {
  // Inner circle (radius 1) and outer circle (radius 3)
  // Using 15 points per circle for better graph connectivity
  let data : Array[Array[Double]] = []
  let n_per_circle = 15
  let step = 6.28318530718 / n_per_circle.to_double() // 2π/n
  // Inner circle
  for i = 0; i < n_per_circle; i = i + 1 {
    let angle = i.to_double() * step
    data.push([@math.cos(angle), @math.sin(angle)])
  }
  // Outer circle (offset for symmetry)
  for i = 0; i < n_per_circle; i = i + 1 {
    let angle = i.to_double() * step + step * 0.5
    data.push([3.0 * @math.cos(angle), 3.0 * @math.sin(angle)])
  }
  // RBF with gamma=1.0: inner-adjacent affinity ~0.84, outer-adjacent ~0.21,
  // inner-outer ~0.016. The large ratio ensures graph separation.
  let config = spectral_rbf_config(2, 1.0)
  let result = spectral_clustering(data, config)
  assert_eq(result.labels.length(), 30)
  // Inner and outer should be separated
  let inner_label = result.labels[0]
  let outer_label = result.labels[n_per_circle]
  assert_true(inner_label != outer_label)
  // At least 80% of inner points should share the same label
  let mut inner_count = 0
  for i = 0; i < n_per_circle; i = i + 1 {
    if result.labels[i] == inner_label {
      inner_count = inner_count + 1
    }
  }
  assert_true(inner_count * 5 >= n_per_circle * 4) // >= 80%
  // At least 80% of outer points should share the same label
  let mut outer_count = 0
  for i = n_per_circle; i < 2 * n_per_circle; i = i + 1 {
    if result.labels[i] == outer_label {
      outer_count = outer_count + 1
    }
  }
  assert_true(outer_count * 5 >= n_per_circle * 4) // >= 80%
}

///|
test "spectral: two well-separated blobs" {
  let data = [
    [0.0, 0.0],
    [0.1, 0.0],
    [0.0, 0.1],
    [5.0, 5.0],
    [5.1, 5.0],
    [5.0, 5.1],
  ]
  let config = spectral_rbf_config(2, 1.0)
  let result = spectral_clustering(data, config)
  assert_eq(result.labels.length(), 6)
  // First 3 should be same cluster, last 3 another
  let l0 = result.labels[0]
  let l3 = result.labels[3]
  assert_true(l0 != l3)
  for i = 0; i < 3; i = i + 1 {
    assert_eq(result.labels[i], l0)
  }
  for i = 3; i < 6; i = i + 1 {
    assert_eq(result.labels[i], l3)
  }
}

///|
test "spectral: single cluster" {
  let data = [[1.0, 2.0], [1.1, 2.0], [1.0, 2.1]]
  let config = spectral_rbf_config(1, 1.0)
  let result = spectral_clustering(data, config)
  assert_eq(result.labels.length(), 3)
  // All in one cluster
  for i = 0; i < 3; i = i + 1 {
    assert_eq(result.labels[i], 0)
  }
}

///|
test "spectral: empty data" {
  let data : Array[Array[Double]] = []
  let config = spectral_rbf_config(2, 1.0)
  let result = spectral_clustering(data, config)
  assert_eq(result.labels.length(), 0)
}

///|
test "spectral: three clusters" {
  let data = [
    [0.0, 0.0],
    [0.1, 0.0],
    [0.0, 0.1],
    [5.0, 0.0],
    [5.1, 0.0],
    [5.0, 0.1],
    [2.5, 5.0],
    [2.6, 5.0],
    [2.5, 5.1],
  ]
  let config = spectral_rbf_config(3, 1.0)
  let result = spectral_clustering(data, config)
  assert_eq(result.labels.length(), 9)
  // Each group of 3 should share a label
  assert_eq(result.labels[0], result.labels[1])
  assert_eq(result.labels[1], result.labels[2])
  assert_eq(result.labels[3], result.labels[4])
  assert_eq(result.labels[4], result.labels[5])
  assert_eq(result.labels[6], result.labels[7])
  assert_eq(result.labels[7], result.labels[8])
  // Three distinct labels
  assert_true(result.labels[0] != result.labels[3])
  assert_true(result.labels[0] != result.labels[6])
  assert_true(result.labels[3] != result.labels[6])
}

///|
test "spectral: KNN affinity" {
  let data = [
    [0.0, 0.0],
    [0.5, 0.0],
    [1.0, 0.0],
    [8.0, 0.0],
    [8.5, 0.0],
    [9.0, 0.0],
  ]
  let config = spectral_knn_config(2, 2, 1.0)
  let result = spectral_clustering(data, config)
  assert_eq(result.labels.length(), 6)
  // First 3 in one cluster, last 3 in another
  let l0 = result.labels[0]
  let l3 = result.labels[3]
  assert_true(l0 != l3)
  for i = 0; i < 3; i = i + 1 {
    assert_eq(result.labels[i], l0)
  }
  for i = 3; i < 6; i = i + 1 {
    assert_eq(result.labels[i], l3)
  }
}

///|
test "spectral: embedding has correct dimensions" {
  let data = [[0.0, 0.0], [1.0, 1.0], [5.0, 5.0], [6.0, 6.0]]
  let config = spectral_rbf_config(2, 0.5)
  let result = spectral_clustering(data, config)
  // Embedding should be n × k = 4 × 2
  assert_eq(result.embedding.length(), 4)
  for i = 0; i < 4; i = i + 1 {
    assert_eq(result.embedding[i].length(), 2)
  }
  // Each row should be unit norm (or zero)
  for i = 0; i < 4; i = i + 1 {
    let nrm = sc_l2_norm(result.embedding[i])
    assert_true(nrm < 1.0e-6 || (nrm - 1.0).abs() < 1.0e-6)
  }
}

///|
test "spectral: affinity matrix is symmetric" {
  let data = [[0.0, 0.0], [1.0, 0.0], [0.0, 1.0]]
  let config = spectral_rbf_config(2, 1.0)
  let result = spectral_clustering(data, config)
  let w = result.affinity_matrix
  let n = w.length()
  for i = 0; i < n; i = i + 1 {
    for j = i + 1; j < n; j = j + 1 {
      assert_true((w[i][j] - w[j][i]).abs() < 1.0e-10)
    }
    // Diagonal should be 0
    assert_true(w[i][i] < 1.0e-10)
  }
}

///|
test "spectral: eigenvalues sorted descending" {
  let data = [
    [0.0, 0.0],
    [0.1, 0.0],
    [0.0, 0.1],
    [5.0, 5.0],
    [5.1, 5.0],
    [5.0, 5.1],
  ]
  let config = spectral_rbf_config(2, 1.0)
  let result = spectral_clustering(data, config)
  // Largest eigenvalue should be >= second
  assert_true(result.eigenvalues[0] >= result.eigenvalues[1])
}

///|
test "spectral: deterministic (same seed)" {
  let data = [[0.0, 0.0], [0.1, 0.0], [5.0, 5.0], [5.1, 5.0]]
  let config = spectral_rbf_config(2, 1.0)
  let r1 = spectral_clustering(data, config)
  let r2 = spectral_clustering(data, config)
  for i = 0; i < r1.labels.length(); i = i + 1 {
    assert_eq(r1.labels[i], r2.labels[i])
  }
}

///|
test "spectral: 1D data" {
  let data = [[0.0], [0.5], [1.0], [8.0], [8.5], [9.0]]
  let config = spectral_rbf_config(2, 1.0)
  let result = spectral_clustering(data, config)
  assert_eq(result.labels.length(), 6)
  let l0 = result.labels[0]
  let l3 = result.labels[3]
  assert_true(l0 != l3)
  for i = 0; i < 3; i = i + 1 {
    assert_eq(result.labels[i], l0)
  }
  for i = 3; i < 6; i = i + 1 {
    assert_eq(result.labels[i], l3)
  }
}

///|
test "spectral: default config with auto gamma" {
  let data = [
    [0.0, 0.0],
    [0.5, 0.5],
    [1.0, 1.0],
    [10.0, 10.0],
    [10.5, 10.5],
    [11.0, 11.0],
  ]
  let config = SpectralConfig::default(2, 2)
  let result = spectral_clustering(data, config)
  assert_eq(result.labels.length(), 6)
  let l0 = result.labels[0]
  let l3 = result.labels[3]
  assert_true(l0 != l3)
}

///|
test "spectral: n_clusters >= n (each point own cluster)" {
  let data = [[0.0, 0.0], [5.0, 5.0]]
  let config = spectral_rbf_config(5, 1.0) // k > n
  let result = spectral_clustering(data, config)
  assert_eq(result.labels.length(), 2)
}
