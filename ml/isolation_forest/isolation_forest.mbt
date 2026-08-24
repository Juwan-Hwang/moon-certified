/// Isolation Forest — anomaly detection via random isolation trees.
///
/// Isolation Forest (Liu, Ting & Zhou 2008, 2012) detects anomalies by
/// **isolating** observations: because anomalies are "few and different",
/// they are easier to separate from the rest of the data. The algorithm
/// builds an ensemble of random isolation trees (iTrees), each of which
/// recursively partitions the data by randomly selecting a feature and a
/// split value. Anomalous points require fewer partitions to isolate
/// (shorter path lengths), so the **average path length** across trees
/// serves as an inverse anomaly score.
///
/// ## Anomaly Score
///
/// `s(x, n) = 2^(-E[h(x)] / c(n))`
///
/// where:
/// - `E[h(x)]` = average path length of `x` across all iTrees
/// - `c(n)` = normalisation factor ≈ `2·(H(n-1)) - 2(n-1)/n`
/// - `H(i)` ≈ `ln(i) + γ` (γ = Euler–Mascheroni constant ≈ 0.5772)
///
/// Interpretation:
/// - `s → 1` → strong anomaly
/// - `s → 0.5` → normal (indistinguishable from the bulk)
/// - `s → 0` → very normal
///
/// ## Complexity
///
/// | Phase  | Time           | Space   |
/// |--------|----------------|---------|
/// | Build  | O(t · ψ · log ψ) | O(t · ψ) |
/// | Score  | O(t · log ψ)   | O(1)    |
///
/// where `t` = number of trees, `ψ` = subsample size.
///
/// ## References
///
/// - Liu, F. T., Ting, K. M., & Zhou, Z. H. (2008). "Isolation Forest."
///   *ICDM 2008*, 413–422.
/// - Liu, F. T., Ting, K. M., & Zhou, Z. H. (2012). "Isolation-Based
///   Anomaly Detection." *ACM TKDD* 6(1), Article 3.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

///|
/// Euler–Mascheroni constant γ ≈ 0.5772156649.
const GAMMA : Double = 0.5772156649015329

///|
/// Default number of trees (as recommended by Liu et al. 2008).
const DEFAULT_N_TREES : Int = 100

///|
/// Default subsample size ψ (as recommended: 256 is sufficient for most data).
const DEFAULT_SUBSAMPLE_SIZE : Int = 256

// ---------------------------------------------------------------------------
// PRNG — xorshift32 for reproducible randomness
// ---------------------------------------------------------------------------

///|
/// A simple xorshift32 pseudo-random number generator for reproducible
/// tree construction. Using a PRNG rather than system randomness ensures
/// that results are deterministic given the same seed.
priv struct Rng {
  mut state : Int
}

///|
/// Create a new PRNG with the given seed.
fn rng_new(seed : Int64) -> Rng {
  // Fold the 64-bit seed into a 32-bit state
  let lo = (seed & 0xFFFFFFFFL).to_int()
  let hi = (seed.reinterpret_as_uint64() >> 32).to_int()
  let s = lo ^ hi
  { state: if s == 0 { 1 } else { s } }
}

///|
/// Generate the next 32-bit pseudo-random value.
fn rng_next_u32(r : Rng) -> Int {
  let mut x = r.state
  x = x ^ (x << 13)
  x = x ^ (x.reinterpret_as_uint() >> 17).reinterpret_as_int()
  x = x ^ (x << 5)
  r.state = x
  x
}

///|
/// Generate a random integer in [0, n).
fn rng_next_int(r : Rng, n : Int) -> Int {
  if n <= 0 {
    return 0
  }
  if n == 1 {
    return 0
  }
  let v = rng_next_u32(r)
  // Ensure non-negative, then modulo
  let non_neg = (v.reinterpret_as_uint() >> 1).reinterpret_as_int()
  non_neg % n
}

///|
/// Generate a random double in [0, 1).
fn rng_next_double(r : Rng) -> Double {
  let v = rng_next_u32(r)
  // Use the high 31 bits (after making non-negative)
  let non_neg = (v.reinterpret_as_uint() >> 1).reinterpret_as_int()
  non_neg.to_double() / 2147483648.0
}

///|
/// Generate a random double in [lo, hi).
fn rng_range_double(r : Rng, lo : Double, hi : Double) -> Double {
  lo + rng_next_double(r) * (hi - lo)
}

// ---------------------------------------------------------------------------
// Isolation Tree
// ---------------------------------------------------------------------------

///|
/// An iTree node. Internal nodes store the split feature and threshold;
/// leaf nodes store the number of points that reached them (used for the
/// `c(size)` correction in the path length formula).
struct ITreeNode {
  /// -1 = leaf, ≥0 = internal node with this feature index
  feature : Int
  /// Split threshold for internal nodes
  threshold : Double
  /// Left child (feature value < threshold)
  left : ITreeNode?
  /// Right child (feature value ≥ threshold)
  right : ITreeNode?
  /// Number of data points in this leaf (only meaningful for leaves)
  size : Int
}

///|
/// Create a leaf node with the given number of points.
fn make_leaf(size : Int) -> ITreeNode {
  { feature: -1, threshold: 0.0, left: None, right: None, size }
}

///|
/// Build an isolation tree from a subsample of the data.
///
/// Recursively partitions the data by randomly selecting a feature and a
/// split point between the min and max of that feature in the current
/// subset. Stops when: (1) only one point remains, (2) all points are
/// identical, or (3) the maximum depth is reached.
fn build_itree(
  data : Array[Array[Double]],
  indices : Array[Int],
  depth : Int,
  max_depth : Int,
  rng : Rng,
) -> ITreeNode {
  let n = indices.length()
  // Stop conditions: single point or max depth reached
  if n <= 1 || depth >= max_depth {
    return make_leaf(n)
  }
  let num_features = data[indices[0]].length()
  if num_features == 0 {
    return make_leaf(n)
  }
  // Try to find a feature with non-zero range
  let mut chosen_feature = -1
  let mut min_val = 0.0
  let mut max_val = 0.0
  // Try each feature in random order
  let tried : Array[Int] = []
  for i = 0; i < num_features; i = i + 1 {
    tried.push(i)
  }
  // Shuffle feature order
  for i = num_features - 1; i > 0; i = i - 1 {
    let j = rng_next_int(rng, i + 1)
    let tmp = tried[i]
    tried[i] = tried[j]
    tried[j] = tmp
  }
  for fi = 0; fi < num_features; fi = fi + 1 {
    let f = tried[fi]
    // Find min and max for this feature
    let mut lo = data[indices[0]][f]
    let mut hi = lo
    for i = 1; i < n; i = i + 1 {
      let v = data[indices[i]][f]
      if v < lo {
        lo = v
      }
      if v > hi {
        hi = v
      }
    }
    if lo < hi {
      chosen_feature = f
      min_val = lo
      max_val = hi
      break
    }
  }
  // If all features have zero range, all points are identical → leaf
  if chosen_feature < 0 {
    return make_leaf(n)
  }
  // Random split point in [min_val, max_val)
  let threshold = rng_range_double(rng, min_val, max_val)
  // Partition indices
  let left_indices : Array[Int] = []
  let right_indices : Array[Int] = []
  for i = 0; i < n; i = i + 1 {
    let idx = indices[i]
    if data[idx][chosen_feature] < threshold {
      left_indices.push(idx)
    } else {
      right_indices.push(idx)
    }
  }
  // If one side is empty (shouldn't happen with proper random split, but guard)
  if left_indices.length() == 0 || right_indices.length() == 0 {
    return make_leaf(n)
  }
  // Recursively build children
  let left = build_itree(data, left_indices, depth + 1, max_depth, rng)
  let right = build_itree(data, right_indices, depth + 1, max_depth, rng)
  {
    feature: chosen_feature,
    threshold,
    left: Some(left),
    right: Some(right),
    size: n,
  }
}

///|
/// Compute the path length of a single point through an iTree.
///
/// For internal nodes, adds 1 and recurses into the appropriate child.
/// For leaf nodes, returns `depth + c(size)` where `c(size)` is the
/// average path length of an unsuccessful BST search.
fn path_length(node : ITreeNode, point : Array[Double], depth : Int) -> Double {
  if node.feature < 0 {
    // Leaf node
    return depth.to_double() + c_factor(node.size)
  }
  if point[node.feature] < node.threshold {
    match node.left {
      Some(child) => path_length(child, point, depth + 1)
      None => depth.to_double()
    }
  } else {
    match node.right {
      Some(child) => path_length(child, point, depth + 1)
      None => depth.to_double()
    }
  }
}

///|
/// Average path length of an unsuccessful BST search with `n` elements.
///
/// `c(n) = 2·H(n-1) - 2(n-1)/n`  for `n > 1`, `0` for `n ≤ 1`.
/// `H(i) ≈ ln(i) + γ` where γ is the Euler–Mascheroni constant.
fn c_factor(n : Int) -> Double {
  if n <= 1 {
    return 0.0
  }
  if n == 2 {
    return 1.0
  }
  let h_n_minus_1 = @math.ln((n - 1).to_double()) + GAMMA
  2.0 * h_n_minus_1 - 2.0 * (n - 1).to_double() / n.to_double()
}

// ---------------------------------------------------------------------------
// Isolation Forest
// ---------------------------------------------------------------------------

///|
/// An Isolation Forest model.
pub struct IsolationForest {
  /// Trained iTrees
  priv trees : Array[ITreeNode]
  /// Subsample size used during training
  priv subsample_size : Int
  /// Number of training samples (for c(n) normalisation)
  priv train_size : Int
}

///|
/// Build an Isolation Forest from training data.
///
/// Parameters:
/// - `data`: Training data, each element is a feature vector
/// - `n_trees`: Number of isolation trees (default 100)
/// - `subsample_size`: Points sampled per tree (default 256)
/// - `seed`: PRNG seed for reproducibility
///
/// Returns a trained `IsolationForest` model.
pub fn isolation_forest_fit(
  data : Array[Array[Double]],
  n_trees : Int,
  subsample_size : Int,
  seed : Int64,
) -> IsolationForest {
  let n = data.length()
  if n == 0 {
    return { trees: [], subsample_size: 0, train_size: 0 }
  }
  let nt = if n_trees <= 0 { DEFAULT_N_TREES } else { n_trees }
  let raw_psi = if subsample_size <= 0 {
    DEFAULT_SUBSAMPLE_SIZE
  } else {
    subsample_size
  }
  let psi = if raw_psi > n { n } else { raw_psi }
  let rng = rng_new(seed)
  // Max tree depth = ceil(log2(psi))
  let max_depth = @math.ln(psi.to_double()) / @math.ln(2.0)
  let max_depth_int = if max_depth > max_depth.to_int().to_double() {
    max_depth.to_int() + 1
  } else {
    max_depth.to_int()
  }
  let trees : Array[ITreeNode] = []
  for _ in 0..<nt {
    // Subsample: select psi indices without replacement
    let indices : Array[Int] = []
    for i = 0; i < n; i = i + 1 {
      indices.push(i)
    }
    // Fisher-Yates shuffle to get first psi as subsample
    for i = n - 1; i > 0; i = i - 1 {
      let j = rng_next_int(rng, i + 1)
      let tmp = indices[i]
      indices[i] = indices[j]
      indices[j] = tmp
    }
    let subsample : Array[Int] = []
    for i = 0; i < psi; i = i + 1 {
      subsample.push(indices[i])
    }
    let tree = build_itree(data, subsample, 0, max_depth_int, rng)
    trees.push(tree)
  }
  { trees, subsample_size: psi, train_size: n }
}

///|
/// Compute the anomaly score of a single point.
///
/// Returns a value in (0, 1):
/// - Close to 1 → strong anomaly
/// - Close to 0.5 → normal
/// - Close to 0 → very normal
pub fn isolation_forest_score(
  model : IsolationForest,
  point : Array[Double],
) -> Double {
  let t = model.trees.length()
  if t == 0 {
    return 0.5
  }
  let mut total_path = 0.0
  for i = 0; i < t; i = i + 1 {
    total_path = total_path + path_length(model.trees[i], point, 0)
  }
  let avg_path = total_path / t.to_double()
  let cn = c_factor(model.train_size)
  if cn == 0.0 {
    return 0.5
  }
  // s = 2^(-E[h(x)] / c(n))
  let exponent = -1.0 * avg_path / cn
  @math.pow(2.0, exponent)
}

///|
/// Compute anomaly scores for an array of points. Returns a new array
/// of scores aligned with the input.
pub fn isolation_forest_score_batch(
  model : IsolationForest,
  data : Array[Array[Double]],
) -> Array[Double] {
  let n = data.length()
  let scores : Array[Double] = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    scores[i] = isolation_forest_score(model, data[i])
  }
  scores
}

///|
/// Predict whether each point is an anomaly based on a threshold.
///
/// A point is an anomaly if its score exceeds the threshold. Common
/// thresholds: 0.6 (conservative), 0.7 (moderate), 0.8 (aggressive).
pub fn isolation_forest_predict(
  model : IsolationForest,
  data : Array[Array[Double]],
  threshold : Double,
) -> Array[Bool] {
  let n = data.length()
  let result : Array[Bool] = Array::make(n, false)
  for i = 0; i < n; i = i + 1 {
    let s = isolation_forest_score(model, data[i])
    result[i] = s > threshold
  }
  result
}

///|
/// Return the number of trees in the forest.
pub fn isolation_forest_n_trees(model : IsolationForest) -> Int {
  model.trees.length()
}

///|
/// Return the subsample size used during training.
pub fn isolation_forest_subsample_size(model : IsolationForest) -> Int {
  model.subsample_size
}

///|
/// Return the training set size.
pub fn isolation_forest_train_size(model : IsolationForest) -> Int {
  model.train_size
}
