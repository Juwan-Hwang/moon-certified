/// Mean Shift clustering via kernel density estimation.
///
/// Mean Shift is a non-parametric, iterative clustering algorithm that
/// locates the maxima of a density function given by a kernel estimate.
/// Unlike K-Means it does not require the number of clusters as input;
/// instead it discovers clusters by finding modes (local maxima) of the
/// density.
///
/// ## Algorithm
/// 1. **Initialise** every data point as a candidate mode.
/// 2. **Mean shift iteration**: for each candidate mode `x`, compute the
///    weighted mean of all points within the kernel bandwidth:
///    ```text
///    m(x) = ( Σ_i K(x_i − x) · x_i ) / ( Σ_i K(x_i − x) ) − x
///    ```
///    and shift `x ← x + m(x)`. For the Gaussian kernel
///    `K(d) = exp(−‖d‖² / (2 h²))`, this is gradient ascent on the KDE.
/// 3. **Converge** when `‖m(x)‖ < tol · h`.
/// 4. **Cluster** points whose converged modes are within `cluster_tol · h`
///    of each other.
///
/// ## Complexity
/// - Time:  `O(n² · d · max_iter)` — each iteration scans all n points for
///   each of the n candidate modes. This is the standard Mean Shift cost;
///   speed-ups via KD-tree or ball-tree neighbourhood queries are future
///   work.
/// - Space: `O(n · d)` for the mode array.
///
/// ## Bandwidth selection
/// When the bandwidth is not supplied, Silverman's rule of thumb is used:
/// `h = (4 / (d + 2))^(1 / (d + 4)) · n^(−1 / (d + 4)) · σ̄`, where `σ̄`
/// is the average per-feature standard deviation.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

///|
/// Maximum mean-shift iterations per point.
let ms_max_iter : Int = 300

///|
/// Convergence tolerance relative to bandwidth: stop when the shift
/// magnitude falls below `tol · h`.
let ms_tol : Double = 1.0e-3

///|
/// Cluster-merge tolerance relative to bandwidth: two converged modes
/// within `cluster_tol · h` are merged into one cluster.
let ms_cluster_tol : Double = 0.25

// ---------------------------------------------------------------------------
// Deterministic PRNG
// ---------------------------------------------------------------------------

///|
/// Reproducible default seed (matches `kmeans` / `pca`).
let ms_default_seed : Int = 0x1A2B3C4D

///|
/// Private LCG state.
priv struct Rng {
  mut state : Int
}

///|
fn Rng::new(seed : Int) -> Rng {
  let s = seed & 0x7FFFFFFF
  { state: if s == 0 { 1 } else { s } }
}

///|
fn Rng::next(self : Rng) -> Int {
  self.state = @utils.lcg_next(self.state)
  self.state
}

///|
fn Rng::next_double(self : Rng) -> Double {
  self.next().to_double() / 2147483648.0
}

// ---------------------------------------------------------------------------
// Geometry helpers
// ---------------------------------------------------------------------------

///|
/// Squared Euclidean distance between two equal-length vectors.
fn ms_sq_dist(a : Array[Double], b : Array[Double]) -> Double {
  let n = a.length()
  let mut sum = 0.0
  for i = 0; i < n; i = i + 1 {
    let diff = a[i] - b[i]
    sum = sum + diff * diff
  }
  sum
}

// ---------------------------------------------------------------------------
// Bandwidth estimation (Silverman's rule of thumb)
// ---------------------------------------------------------------------------

///|
/// Per-feature mean of `data` (rows = samples, cols = features).
fn ms_mean(data : Array[Array[Double]], d : Int) -> Array[Double] {
  let n = data.length()
  let m = Array::make(d, 0.0)
  for i = 0; i < n; i = i + 1 {
    let row = data[i]
    let len = row.length()
    for j = 0; j < d; j = j + 1 {
      if j < len {
        m[j] = m[j] + row[j]
      }
    }
  }
  if n > 0 {
    let nd = n.to_double()
    for j = 0; j < d; j = j + 1 {
      m[j] = m[j] / nd
    }
  }
  m
}

///|
/// Per-feature sample standard deviation (ddof = 1).
fn ms_std(
  data : Array[Array[Double]],
  mean : Array[Double],
  d : Int,
) -> Array[Double] {
  let n = data.length()
  let stds = Array::make(d, 0.0)
  if n <= 1 {
    return stds
  }
  for i = 0; i < n; i = i + 1 {
    let row = data[i]
    let len = row.length()
    for j = 0; j < d; j = j + 1 {
      let v = if j < len { row[j] } else { 0.0 }
      let diff = v - mean[j]
      stds[j] = stds[j] + diff * diff
    }
  }
  let denom = (n - 1).to_double()
  for j = 0; j < d; j = j + 1 {
    stds[j] = (stds[j] / denom).sqrt()
  }
  stds
}

///|
/// Estimate bandwidth using Silverman's rule of thumb:
/// `h = (4 / (d + 2))^(1 / (d + 4)) · n^(−1 / (d + 4)) · σ̄`
/// where `σ̄` is the mean per-feature standard deviation.
/// Falls back to `1.0` if data is degenerate (zero variance or n ≤ 1).
pub fn estimate_bandwidth(data : Array[Array[Double]]) -> Double {
  let n = data.length()
  if n <= 1 {
    return 1.0
  }
  let d = data[0].length()
  if d == 0 {
    return 1.0
  }
  let mean = ms_mean(data, d)
  let stds = ms_std(data, mean, d)
  let mut sigma_avg = 0.0
  for j = 0; j < d; j = j + 1 {
    sigma_avg = sigma_avg + stds[j]
  }
  sigma_avg = sigma_avg / d.to_double()
  if sigma_avg < 1.0e-10 {
    return 1.0
  }
  // Silverman's factor: (4/(d+2))^(1/(d+4))
  let factor = @math.pow(
    4.0 / (d.to_double() + 2.0),
    1.0 / (d.to_double() + 4.0),
  )
  let n_factor = @math.pow(n.to_double(), -1.0 / (d.to_double() + 4.0))
  factor * n_factor * sigma_avg
}

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

///|
/// Kernel type for Mean Shift.
pub enum KernelType {
  Gaussian // K(d) = exp(−d² / (2 h²))
  Flat // K(d) = 1 if d < h, else 0
} derive(Eq, Debug)

///|
/// Configuration for Mean Shift clustering.
pub struct MeanShiftConfig {
  /// Kernel bandwidth. If ≤ 0, estimated from data via Silverman's rule.
  bandwidth : Double
  /// Kernel function type (default: Gaussian).
  kernel : KernelType
  /// Maximum iterations per point (default: 300).
  max_iter : Int
  /// Convergence tolerance relative to bandwidth (default: 1e-3).
  tol : Double
  /// Cluster merge tolerance relative to bandwidth (default: 0.25).
  cluster_tol : Double
  /// PRNG seed (for tie-breaking in cluster assignment).
  seed : Int
}

///|
/// The fitted Mean Shift model.
pub struct MeanShiftResult {
  /// Cluster centre coordinates (one per discovered cluster).
  cluster_centers : Array[Array[Double]]
  /// Cluster label for each input point, or −1 for noise.
  labels : Array[Int]
  /// Number of clusters discovered.
  n_clusters : Int
  /// Bandwidth used (estimated or user-supplied).
  bandwidth : Double
}

// ---------------------------------------------------------------------------
// Kernel evaluation
// ---------------------------------------------------------------------------

///|
/// Evaluate the kernel weight for a squared distance `sq_d` given bandwidth
/// `h`. Returns 0.0 if the point is outside the kernel support.
fn kernel_weight(sq_d : Double, h : Double, kernel : KernelType) -> Double {
  match kernel {
    Gaussian => {
      // K(d) = exp(−d² / (2 h²))
      // For d >> h the weight is negligibly small; we cut at 4σ to
      // avoid underflow noise (exp(−8) ≈ 3.4e-4).
      let ratio = sq_d / (h * h)
      if ratio > 8.0 {
        0.0
      } else {
        @math.exp(-ratio * 0.5)
      }
    }
    Flat =>
      // K(d) = 1 if d < h, else 0
      if sq_d < h * h {
        1.0
      } else {
        0.0
      }
  }
}

// ---------------------------------------------------------------------------
// Mean shift iteration (single point)
// ---------------------------------------------------------------------------

///|
/// Perform one mean-shift step for point `x`: compute the weighted mean
/// of all data points and return the shift vector `m(x)` plus the total
/// weight (for convergence check). If total weight is zero, returns a
/// zero vector (point is isolated).
fn mean_shift_step(
  x : Array[Double],
  data : Array[Array[Double]],
  h : Double,
  kernel : KernelType,
  d : Int,
) -> (Array[Double], Double) {
  let n = data.length()
  let shift = Array::make(d, 0.0)
  let mut total_weight = 0.0
  for i = 0; i < n; i = i + 1 {
    let p = data[i]
    let sq_d = ms_sq_dist(x, p)
    let w = kernel_weight(sq_d, h, kernel)
    if w > 0.0 {
      for j = 0; j < d; j = j + 1 {
        shift[j] = shift[j] + w * p[j]
      }
      total_weight = total_weight + w
    }
  }
  if total_weight > 0.0 {
    for j = 0; j < d; j = j + 1 {
      shift[j] = shift[j] / total_weight - x[j]
    }
  }
  (shift, total_weight)
}

///|
/// Shift a single point until convergence. Returns the converged mode.
fn shift_point(
  x0 : Array[Double],
  data : Array[Array[Double]],
  h : Double,
  kernel : KernelType,
  d : Int,
  max_iter : Int,
  tol : Double,
) -> Array[Double] {
  let x = Array::make(d, 0.0)
  for j = 0; j < d; j = j + 1 {
    x[j] = x0[j]
  }
  let conv_thresh = tol * h
  let conv_thresh_sq = conv_thresh * conv_thresh
  for iter = 0; iter < max_iter; iter = iter + 1 {
    let (shift, total_w) = mean_shift_step(x, data, h, kernel, d)
    if total_w == 0.0 {
      // Isolated point — no neighbours; keep current position.
      break
    }
    // Apply shift
    for j = 0; j < d; j = j + 1 {
      x[j] = x[j] + shift[j]
    }
    // Convergence: shift magnitude < tol * h
    let shift_sq = ms_sq_dist(shift, Array::make(d, 0.0))
    if shift_sq < conv_thresh_sq {
      break
    }
  }
  x
}

// ---------------------------------------------------------------------------
// Cluster merging
// ---------------------------------------------------------------------------

///|
/// Merge converged modes that are within `merge_tol` of each other.
/// Returns the unique cluster centres and a mapping from mode index to
/// cluster label.
fn merge_modes(
  modes : Array[Array[Double]],
  merge_tol : Double,
) -> (Array[Array[Double]], Array[Int]) {
  let n = modes.length()
  let labels = Array::make(n, -1)
  let centers : Array[Array[Double]] = []
  let merge_tol_sq = merge_tol * merge_tol
  for i = 0; i < n; i = i + 1 {
    let mut assigned = false
    for c = 0; c < centers.length(); c = c + 1 {
      let sq_d = ms_sq_dist(modes[i], centers[c])
      if sq_d < merge_tol_sq {
        labels[i] = c
        assigned = true
        break
      }
    }
    if !assigned {
      labels[i] = centers.length()
      // Copy the mode as a new cluster centre
      let center = Array::make(modes[i].length(), 0.0)
      for j = 0; j < modes[i].length(); j = j + 1 {
        center[j] = modes[i][j]
      }
      centers.push(center)
    }
  }
  (centers, labels)
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

///|
/// Create a default Mean Shift configuration with Gaussian kernel and
/// auto-estimated bandwidth.
pub fn MeanShiftConfig::default() -> MeanShiftConfig {
  {
    bandwidth: 0.0,
    kernel: Gaussian,
    max_iter: ms_max_iter,
    tol: ms_tol,
    cluster_tol: ms_cluster_tol,
    seed: ms_default_seed,
  }
}

///|
/// Create a configuration with a specific bandwidth.
pub fn mean_shift_config(bandwidth : Double) -> MeanShiftConfig {
  {
    bandwidth,
    kernel: Gaussian,
    max_iter: ms_max_iter,
    tol: ms_tol,
    cluster_tol: ms_cluster_tol,
    seed: ms_default_seed,
  }
}

///|
/// Run Mean Shift clustering on `data`.
///
/// **Parameters.**
/// - `data` — sample matrix, rows = samples, cols = features.
/// - `config` — configuration; if `config.bandwidth ≤ 0` the bandwidth is
///   estimated from data via Silverman's rule.
///
/// **Returns.** A `MeanShiftResult` with cluster centres, per-point labels,
/// cluster count, and the effective bandwidth.
///
/// **Edge cases.**
/// - Empty data → 0 clusters, empty labels.
/// - Single point → 1 cluster.
/// - All points identical → 1 cluster.
pub fn mean_shift(
  data : Array[Array[Double]],
  config : MeanShiftConfig,
) -> MeanShiftResult {
  let n = data.length()
  if n == 0 {
    return { cluster_centers: [], labels: [], n_clusters: 0, bandwidth: 0.0 }
  }
  if n == 1 {
    let center = Array::make(data[0].length(), 0.0)
    for j = 0; j < data[0].length(); j = j + 1 {
      center[j] = data[0][j]
    }
    return {
      cluster_centers: [center],
      labels: [0],
      n_clusters: 1,
      bandwidth: if config.bandwidth > 0.0 {
        config.bandwidth
      } else {
        1.0
      },
    }
  }
  let d = data[0].length()
  if d == 0 {
    return { cluster_centers: [], labels: [], n_clusters: 0, bandwidth: 0.0 }
  }
  // Determine bandwidth
  let h = if config.bandwidth > 0.0 {
    config.bandwidth
  } else {
    estimate_bandwidth(data)
  }
  // Shift every point to its converged mode
  let modes : Array[Array[Double]] = []
  for i = 0; i < n; i = i + 1 {
    let mode = shift_point(
      data[i],
      data,
      h,
      config.kernel,
      d,
      config.max_iter,
      config.tol,
    )
    modes.push(mode)
  }
  // Merge nearby modes into clusters
  let merge_dist = config.cluster_tol * h
  let (centers, mode_labels) = merge_modes(modes, merge_dist)
  // Compute cluster centres as the mean of all points assigned to each cluster
  let n_clusters = centers.length()
  let final_centers : Array[Array[Double]] = []
  if n_clusters > 0 {
    // Accumulate per-cluster sums and counts
    let sums : Array[Array[Double]] = []
    let counts : Array[Int] = Array::make(n_clusters, 0)
    for c = 0; c < n_clusters; c = c + 1 {
      sums.push(Array::make(d, 0.0))
    }
    for i = 0; i < n; i = i + 1 {
      let c = mode_labels[i]
      let row = data[i]
      let len = row.length()
      for j = 0; j < d; j = j + 1 {
        sums[c][j] = sums[c][j] + (if j < len { row[j] } else { 0.0 })
      }
      counts[c] = counts[c] + 1
    }
    for c = 0; c < n_clusters; c = c + 1 {
      let center = Array::make(d, 0.0)
      if counts[c] > 0 {
        let cnt = counts[c].to_double()
        for j = 0; j < d; j = j + 1 {
          center[j] = sums[c][j] / cnt
        }
      }
      final_centers.push(center)
    }
  }
  {
    cluster_centers: final_centers,
    labels: mode_labels,
    n_clusters,
    bandwidth: h,
  }
}

///|
/// Convenience: run Mean Shift with default Gaussian kernel and
/// auto-estimated bandwidth.
pub fn mean_shift_default(data : Array[Array[Double]]) -> MeanShiftResult {
  mean_shift(data, MeanShiftConfig::default())
}

///|
/// Predict the cluster label for a new point `x` by shifting it to its
/// mode and finding the nearest cluster centre.
///
/// Returns −1 if the model has no clusters.
pub fn mean_shift_predict(
  result : MeanShiftResult,
  x : Array[Double],
  data : Array[Array[Double]],
  config : MeanShiftConfig,
) -> Int {
  if result.n_clusters == 0 {
    return -1
  }
  let d = x.length()
  let h = result.bandwidth
  // Shift the new point to its mode
  let mode = shift_point(
    x,
    data,
    h,
    config.kernel,
    d,
    config.max_iter,
    config.tol,
  )
  // Find nearest cluster centre
  let mut best_c = 0
  let mut best_d = ms_sq_dist(mode, result.cluster_centers[0])
  for c = 1; c < result.n_clusters; c = c + 1 {
    let dd = ms_sq_dist(mode, result.cluster_centers[c])
    if dd < best_d {
      best_d = dd
      best_c = c
    }
  }
  best_c
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "mean_shift: single cluster (all identical points)" {
  let data = [[1.0, 2.0], [1.0, 2.0], [1.0, 2.0]]
  let result = mean_shift_default(data)
  assert_eq(result.n_clusters, 1)
  assert_eq(result.labels[0], 0)
  assert_eq(result.labels[1], 0)
  assert_eq(result.labels[2], 0)
  // Centre should be at (1, 2)
  let c = result.cluster_centers[0]
  assert_true((c[0] - 1.0).abs() < 1.0e-6)
  assert_true((c[1] - 2.0).abs() < 1.0e-6)
}

///|
test "mean_shift: two well-separated clusters" {
  let data = [
    [0.0, 0.0],
    [0.5, 0.0],
    [0.0, 0.5],
    [10.0, 10.0],
    [10.5, 10.0],
    [10.0, 10.5],
  ]
  let config = mean_shift_config(3.0)
  let result = mean_shift(data, config)
  assert_eq(result.n_clusters, 2)
  // Points 0-2 should share a label, 3-5 another
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
test "mean_shift: three clusters" {
  let data = [
    [0.0, 0.0],
    [0.3, 0.0],
    [0.0, 0.3],
    [5.0, 0.0],
    [5.3, 0.0],
    [5.0, 0.3],
    [2.5, 5.0],
    [2.8, 5.0],
    [2.5, 5.3],
  ]
  let config = mean_shift_config(2.0)
  let result = mean_shift(data, config)
  assert_eq(result.n_clusters, 3)
  // Each group of 3 should share a label
  assert_eq(result.labels[0], result.labels[1])
  assert_eq(result.labels[1], result.labels[2])
  assert_eq(result.labels[3], result.labels[4])
  assert_eq(result.labels[4], result.labels[5])
  assert_eq(result.labels[6], result.labels[7])
  assert_eq(result.labels[7], result.labels[8])
  // All three groups should have different labels
  assert_true(result.labels[0] != result.labels[3])
  assert_true(result.labels[0] != result.labels[6])
  assert_true(result.labels[3] != result.labels[6])
}

///|
test "mean_shift: bandwidth estimation (Silverman)" {
  let data = [
    [0.0],
    [1.0],
    [2.0],
    [3.0],
    [4.0],
    [5.0],
    [6.0],
    [7.0],
    [8.0],
    [9.0],
    [10.0],
  ]
  let h = estimate_bandwidth(data)
  // Silverman for uniform [0,10], n=11, d=1:
  // sigma ≈ 3.316, factor = (4/3)^(1/5) ≈ 1.059, n^(-1/5) ≈ 0.617
  // h ≈ 1.059 * 0.617 * 3.316 ≈ 2.17
  assert_true(h > 1.0)
  assert_true(h < 4.0)
}

///|
test "mean_shift: single point" {
  let data = [[5.0, 5.0]]
  let result = mean_shift_default(data)
  assert_eq(result.n_clusters, 1)
  assert_eq(result.labels[0], 0)
  assert_true((result.cluster_centers[0][0] - 5.0).abs() < 1.0e-6)
}

///|
test "mean_shift: empty data" {
  let data : Array[Array[Double]] = []
  let result = mean_shift_default(data)
  assert_eq(result.n_clusters, 0)
  assert_eq(result.labels.length(), 0)
}

///|
test "mean_shift: flat kernel" {
  let data = [
    [0.0, 0.0],
    [0.5, 0.0],
    [0.0, 0.5],
    [8.0, 8.0],
    [8.5, 8.0],
    [8.0, 8.5],
  ]
  let config = {
    bandwidth: 2.0,
    kernel: Flat,
    max_iter: ms_max_iter,
    tol: ms_tol,
    cluster_tol: ms_cluster_tol,
    seed: ms_default_seed,
  }
  let result = mean_shift(data, config)
  assert_eq(result.n_clusters, 2)
}

///|
test "mean_shift: convergence on Gaussian blob" {
  // Two Gaussian blobs centered at (0,0) and (8,8)
  let data : Array[Array[Double]] = []
  let rng = Rng::new(42)
  for k = 0; k < 20; k = k + 1 {
    data.push([rng.next_double() * 2.0 - 1.0, rng.next_double() * 2.0 - 1.0])
  }
  for k = 0; k < 20; k = k + 1 {
    data.push([
      8.0 + rng.next_double() * 2.0 - 1.0,
      8.0 + rng.next_double() * 2.0 - 1.0,
    ])
  }
  let config = mean_shift_config(3.0)
  let result = mean_shift(data, config)
  assert_eq(result.n_clusters, 2)
  // First 20 points in one cluster, last 20 in another
  let l0 = result.labels[0]
  let l20 = result.labels[20]
  assert_true(l0 != l20)
  for i = 0; i < 20; i = i + 1 {
    assert_eq(result.labels[i], l0)
  }
  for i = 20; i < 40; i = i + 1 {
    assert_eq(result.labels[i], l20)
  }
}

///|
test "mean_shift: cluster centers are means of members" {
  let data = [[0.0, 0.0], [2.0, 0.0], [10.0, 0.0], [12.0, 0.0]]
  let config = mean_shift_config(4.0)
  let result = mean_shift(data, config)
  assert_eq(result.n_clusters, 2)
  // Find which cluster contains points 0,1
  let c01 = result.labels[0]
  // Centre of cluster with points (0,0) and (2,0) should be near (1,0)
  let center = result.cluster_centers[c01]
  assert_true((center[0] - 1.0).abs() < 0.5)
  assert_true((center[1] - 0.0).abs() < 0.5)
}

///|
test "mean_shift: predict new point" {
  let data = [
    [0.0, 0.0],
    [0.5, 0.0],
    [0.0, 0.5],
    [10.0, 10.0],
    [10.5, 10.0],
    [10.0, 10.5],
  ]
  let config = mean_shift_config(3.0)
  let result = mean_shift(data, config)
  // A new point near (0,0) should be assigned to the first cluster
  let label = mean_shift_predict(result, [0.2, 0.2], data, config)
  assert_true(label >= 0)
  // A new point near (10,10) should be assigned to the other cluster
  let label2 = mean_shift_predict(result, [10.2, 10.2], data, config)
  assert_true(label2 >= 0)
  assert_true(label != label2)
}

///|
test "mean_shift: 1D data" {
  let data = [[0.0], [0.5], [1.0], [8.0], [8.5], [9.0]]
  let config = mean_shift_config(3.0)
  let result = mean_shift(data, config)
  assert_eq(result.n_clusters, 2)
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
test "mean_shift: deterministic (same seed)" {
  let data = [[0.0, 0.0], [0.3, 0.0], [5.0, 5.0], [5.3, 5.0]]
  let config = mean_shift_config(2.0)
  let r1 = mean_shift(data, config)
  let r2 = mean_shift(data, config)
  assert_eq(r1.n_clusters, r2.n_clusters)
  for i = 0; i < r1.labels.length(); i = i + 1 {
    assert_eq(r1.labels[i], r2.labels[i])
  }
}

///|
test "mean_shift: bandwidth affects cluster count" {
  let data = [[0.0], [2.0], [4.0], [6.0], [8.0]]
  // Large bandwidth → fewer clusters (all merge into 1)
  let wide = mean_shift_config(10.0)
  let r_wide = mean_shift(data, wide)
  assert_true(r_wide.n_clusters <= 2)
  // Small bandwidth → more clusters
  let narrow = mean_shift_config(0.5)
  let r_narrow = mean_shift(data, narrow)
  assert_true(r_narrow.n_clusters >= 2)
}
