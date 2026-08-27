/// Agglomerative Hierarchical Clustering.
///
/// Builds a hierarchy of clusters by iteratively merging the closest pair.
/// Supports single, complete, average, and Ward linkage methods.
/// The result is a dendrogram (merge sequence) that can be cut at any
/// distance threshold to obtain a flat clustering.
///
/// ## Algorithm
///
/// 1. Start with N singleton clusters (one per data point).
/// 2. Compute the initial pairwise distance matrix.
/// 3. Repeatedly merge the two closest clusters.
/// 4. Update inter-cluster distances using the selected linkage method.
/// 5. Stop when a single cluster remains (or `num_clusters` is reached).
///
/// ## Linkage methods
///
/// - **Single**: min distance between points in the two clusters.
/// - **Complete**: max distance between points in the two clusters.
/// - **Average**: mean distance between all cross-cluster point pairs.
/// - **Ward**: minimises the increase in total within-cluster variance.
///
/// ## Complexity
///
/// O(n³) time, O(n²) space (naive implementation with Lance-Williams update).
///
/// ## References
///
/// - Lance, G.N. and Williams, W.T. "A General Theory of Classificatory
///   Sorting Strategies." Computer Journal, 1967.
/// - Müllner, D. "Modern Hierarchical, Agglomerative Clustering Algorithms."
///   arXiv:1109.2378, 2011.
///
/// `proof-enabled` is `false`.

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

///|
/// Linkage method for computing inter-cluster distances.
pub enum Linkage {
  Single // min d(a, b) across a ∈ A, b ∈ B
  Complete // max d(a, b) across a ∈ A, b ∈ B
  Average // mean d(a, b) across a ∈ A, b ∈ B
  Ward // minimise increase in within-cluster variance
}

///|
/// A single merge step in the dendrogram.
pub struct MergeStep {
  /// Index of the first cluster merged (0-based, into the merged cluster).
  cluster_a : Int
  /// Index of the second cluster merged.
  cluster_b : Int
  /// Distance between the two clusters at merge time.
  distance : Double
  /// Size of the resulting merged cluster.
  size : Int
}

///|
/// Result of hierarchical clustering.
pub struct HierarchicalResult {
  /// Ordered list of merges (first merge is index 0).
  merges : Array[MergeStep]
  /// Cluster label for each input point (based on the cut).
  labels : Array[Int]
}

// ---------------------------------------------------------------------------
// Distance helpers
// ---------------------------------------------------------------------------

///|
/// Squared Euclidean distance between two points.
fn sq_euclidean(a : Array[Double], b : Array[Double]) -> Double {
  let n = a.length()
  let mut sum = 0.0
  for i = 0; i < n; i = i + 1 {
    let d = a[i] - b[i]
    sum = sum + d * d
  }
  sum
}

///|
/// Euclidean distance between two points.
fn euclidean(a : Array[Double], b : Array[Double]) -> Double {
  let s = sq_euclidean(a, b)
  // Manual sqrt via Newton's method (avoid stdlib sqrt issues)
  if s <= 0.0 {
    return 0.0
  }
  let mut x = s
  let mut y = (x + 1.0) / 2.0
  while y < x {
    x = y
    y = (x + s / x) / 2.0
  }
  x
}

// ---------------------------------------------------------------------------
// Clustering
// ---------------------------------------------------------------------------

///|
/// Perform agglomerative hierarchical clustering.
///
/// - `data`: array of points, each an `Array[Double]` of the same dimension.
/// - `linkage`: linkage method to use.
/// - `num_clusters`: stop when this many clusters remain (1 = full dendrogram).
///
/// Returns the merge history and cluster labels.
pub fn cluster(
  data : Array[Array[Double]],
  linkage : Linkage,
  num_clusters : Int,
) -> HierarchicalResult {
  let n = data.length()
  let k = if num_clusters < 1 {
    1
  } else if num_clusters > n {
    n
  } else {
    num_clusters
  }
  // Special case: empty or single point
  if n <= 1 {
    let labels : Array[Int] = []
    for i = 0; i < n; i = i + 1 {
      labels.push(0)
    }
    return { merges: [], labels, }
  }
  // Compute initial pairwise distances
  let dist : Array[Array[Double]] = Array::make(n, [])
  for i = 0; i < n; i = i + 1 {
    dist[i] = Array::make(n, 0.0)
  }
  for i = 0; i < n; i = i + 1 {
    for j = i + 1; j < n; j = j + 1 {
      let d = match linkage {
        Ward => sq_euclidean(data[i], data[j])
        _ => euclidean(data[i], data[j])
      }
      dist[i][j] = d
      dist[j][i] = d
    }
  }
  // Active cluster list: each entry is (representative_index, size)
  let active : Array[Int] = []
  let sizes : Array[Int] = []
  for i = 0; i < n; i = i + 1 {
    active.push(i)
    sizes.push(1)
  }
  // Merge history
  let merges : Array[MergeStep] = []
  // Merge map: original point index -> current cluster representative
  let cluster_of : Array[Int] = Array::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    cluster_of[i] = i
  }
  // Iteratively merge closest clusters
  let mut num_active = n
  while num_active > k {
    // Find the closest pair
    let mut best_i = 0
    let mut best_j = 1
    let mut best_dist = 1.0e18
    for ai = 0; ai < active.length(); ai = ai + 1 {
      let ci = active[ai]
      if ci < 0 {
        continue
      }
      for aj = ai + 1; aj < active.length(); aj = aj + 1 {
        let cj = active[aj]
        if cj < 0 {
          continue
        }
        let d = dist[ci][cj]
        if d < best_dist {
          best_dist = d
          best_i = ai
          best_j = aj
        }
      }
    }
    let ci = active[best_i]
    let cj = active[best_j]
    let merged_size = sizes[ci] + sizes[cj]
    // Record the merge
    merges.push({
      cluster_a: ci,
      cluster_b: cj,
      distance: best_dist,
      size: merged_size,
    })
    // Update distances using Lance-Williams formula
    let si = sizes[ci].to_double()
    let sj = sizes[cj].to_double()
    for ak = 0; ak < active.length(); ak = ak + 1 {
      let ck = active[ak]
      if ck < 0 || ck == ci || ck == cj {
        continue
      }
      let dik = dist[ci][ck]
      let djk = dist[cj][ck]
      let new_d = match linkage {
        Single => if dik < djk { dik } else { djk }
        Complete => if dik > djk { dik } else { djk }
        Average => (dik * si + djk * sj) / (si + sj)
        Ward =>
          // Lance-Williams Ward: ((si+sk)*dik + (sj+sk)*djk - sk*dij) / (si+sj+sk)
          (
            dik * (si + sizes[ck].to_double()) +
            djk * (sj + sizes[ck].to_double()) -
            sizes[ck].to_double() * best_dist
          ) /
          (si + sj + sizes[ck].to_double())
      }
      dist[ci][ck] = new_d
      dist[ck][ci] = new_d
    }
    // Merge: cj is absorbed into ci
    sizes[ci] = merged_size
    active[best_j] = -1
    // Update cluster_of for all points in cluster cj
    for p = 0; p < n; p = p + 1 {
      if cluster_of[p] == cj {
        cluster_of[p] = ci
      }
    }
    num_active = num_active - 1
  }
  // Relabel clusters to 0..k-1
  let label_map : Map[Int, Int] = Map([])
  let mut next_label = 0
  for i = 0; i < n; i = i + 1 {
    let c = cluster_of[i]
    if !label_map.contains(c) {
      label_map.set(c, next_label)
      next_label = next_label + 1
    }
  }
  let labels : Array[Int] = Array::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    labels[i] = label_map.get(cluster_of[i]).unwrap_or(0)
  }
  { merges, labels, }
}

///|
/// Cut the dendrogram at a given distance threshold.
///
/// Returns cluster labels for each input point. Points merged at a distance
/// greater than the threshold are in separate clusters.
pub fn cut_at_distance(
  data : Array[Array[Double]],
  linkage : Linkage,
  threshold : Double,
) -> Array[Int] {
  let result = cluster(data, linkage, 1)
  // Start with each point in its own cluster
  let n = data.length()
  let parent : Array[Int] = Array::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    parent[i] = i
  }
  // Union-find helper
  fn find(x : Int) -> Int {
    let mut root = x
    while parent[root] != root {
      root = parent[root]
    }
    // Path compression
    let mut curr = x
    while parent[curr] != root {
      let next = parent[curr]
      parent[curr] = root
      curr = next
    }
    root
  }
  // Apply merges below threshold
  let merge_parent : Array[Int] = Array::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    merge_parent[i] = i
  }
  // Build cluster tree from merge steps
  // Each merge creates a new node; points merged at distance <= threshold are joined
  for idx = 0; idx < result.merges.length(); idx = idx + 1 {
    let m = result.merges[idx]
    if m.distance <= threshold {
      let ra = find(m.cluster_a)
      let rb = find(m.cluster_b)
      if ra != rb {
        parent[ra] = rb
      }
    }
  }
  // Extract labels
  let label_map : Map[Int, Int] = Map([])
  let mut next_label = 0
  let labels : Array[Int] = Array::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    let root = find(i)
    if !label_map.contains(root) {
      label_map.set(root, next_label)
      next_label = next_label + 1
    }
    labels[i] = label_map.get(root).unwrap_or(0)
  }
  labels
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "hierarchical_clustering: two well-separated clusters" {
  let data : Array[Array[Double]] = []
  data.push([0.0, 0.0])
  data.push([0.1, 0.1])
  data.push([0.0, 0.1])
  data.push([5.0, 5.0])
  data.push([5.1, 5.0])
  data.push([5.0, 5.1])
  let result = cluster(data, Average, 2)
  // First three points should be in one cluster, last three in another
  assert_eq(result.labels.length(), 6)
  assert_eq(result.labels[0], result.labels[1])
  assert_eq(result.labels[1], result.labels[2])
  assert_eq(result.labels[3], result.labels[4])
  assert_eq(result.labels[4], result.labels[5])
  assert_not_eq(result.labels[0], result.labels[3])
}

///|
test "hierarchical_clustering: single linkage" {
  let data : Array[Array[Double]] = []
  data.push([0.0])
  data.push([1.0])
  data.push([2.0])
  data.push([10.0])
  data.push([11.0])
  let result = cluster(data, Single, 2)
  // Points 0,1,2 are close; 3,4 are close
  assert_eq(result.labels[0], result.labels[1])
  assert_eq(result.labels[1], result.labels[2])
  assert_eq(result.labels[3], result.labels[4])
  assert_not_eq(result.labels[0], result.labels[3])
}

///|
test "hierarchical_clustering: complete linkage" {
  let data : Array[Array[Double]] = []
  data.push([0.0])
  data.push([1.0])
  data.push([2.0])
  data.push([3.0])
  let result = cluster(data, Complete, 2)
  // With complete linkage, {0,1} and {2,3} should merge
  assert_eq(result.labels[0], result.labels[1])
  assert_eq(result.labels[2], result.labels[3])
  assert_not_eq(result.labels[0], result.labels[2])
}

///|
test "hierarchical_clustering: ward linkage" {
  let data : Array[Array[Double]] = []
  data.push([0.0, 0.0])
  data.push([1.0, 0.0])
  data.push([10.0, 10.0])
  data.push([11.0, 10.0])
  let result = cluster(data, Ward, 2)
  assert_eq(result.labels[0], result.labels[1])
  assert_eq(result.labels[2], result.labels[3])
  assert_not_eq(result.labels[0], result.labels[2])
}

///|
test "hierarchical_clustering: full dendrogram" {
  let data : Array[Array[Double]] = []
  data.push([0.0])
  data.push([1.0])
  data.push([5.0])
  let result = cluster(data, Average, 1)
  // Should produce 2 merges for 3 points
  assert_eq(result.merges.length(), 2)
  // Final merge has larger distance
  assert_true(result.merges[1].distance > result.merges[0].distance)
}

///|
test "hierarchical_clustering: cut at distance" {
  let data : Array[Array[Double]] = []
  data.push([0.0])
  data.push([1.0])
  data.push([10.0])
  data.push([11.0])
  let labels = cut_at_distance(data, Average, 2.0)
  // Points 0,1 should be together; 2,3 should be together
  assert_eq(labels[0], labels[1])
  assert_eq(labels[2], labels[3])
  assert_not_eq(labels[0], labels[2])
}

///|
test "hierarchical_clustering: single point" {
  let data : Array[Array[Double]] = []
  data.push([1.0, 2.0])
  let result = cluster(data, Average, 1)
  assert_eq(result.labels.length(), 1)
  assert_eq(result.labels[0], 0)
  assert_eq(result.merges.length(), 0)
}

///|
test "hierarchical_clustering: all same point" {
  let data : Array[Array[Double]] = []
  data.push([1.0, 1.0])
  data.push([1.0, 1.0])
  data.push([1.0, 1.0])
  let result = cluster(data, Average, 1)
  assert_eq(result.labels[0], result.labels[1])
  assert_eq(result.labels[1], result.labels[2])
  // All merges should have distance 0
  for i = 0; i < result.merges.length(); i = i + 1 {
    assert_true(result.merges[i].distance < 1.0e-10)
  }
}
