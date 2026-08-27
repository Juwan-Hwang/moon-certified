/// OPTICS — Ordering Points To Identify the Clustering Structure.
///
/// OPTICS is a density-based clustering algorithm that generalises DBSCAN.
/// Instead of producing a single flat clustering, OPTICS generates an
/// **ordering** of the point set together with a **reachability plot** that
/// encodes the hierarchical density structure. Clusters of any desired density
/// threshold can then be extracted in a single pass from this ordering.
///
/// ## Key Concepts
///
/// - **ε-neighbourhood**: All points within distance `ε` of a point `p`
///   (including `p` itself).
/// - **Core distance** `core_dist(p)`: The distance from `p` to its
///   `min_pts`-th nearest neighbour within the ε-neighbourhood. If `p` has
///   fewer than `min_pts` neighbours, `core_dist(p)` is undefined (`+∞`).
/// - **Reachability distance** `reach_dist(o, p)`:
///   `max(core_dist(o), dist(o, p))`. This is the minimum density threshold
///   at which `p` becomes directly density-reachable from `o`.
///
/// ## Algorithm
///
/// 1. Start with an arbitrary unprocessed point `p`.
/// 2. Compute its ε-neighbourhood and core distance.
/// 3. Append `p` to the ordering. If `p` is a core point, update the
///    reachability distances of its unprocessed neighbours using a priority
///    queue (the **seed set**).
/// 4. If the seed set is non-empty, extract the point with the smallest
///    reachability distance and repeat from step 2. Otherwise, pick a new
///    arbitrary unprocessed point.
/// 5. The ordering and reachability distances form the **reachability plot**.
///
/// ## Cluster Extraction
///
/// Two extraction methods are provided:
///
/// - **DBSCAN-style** (`extract_dbscan_clusters`): Extract flat clusters at a
///   fixed density threshold `eps_clamped < eps`. Points with reachability
///   distance > `eps_clamped` start new clusters; points with core distance
///   > `eps_clamped` are noise.
///
/// - **ξ-cluster** (`extract_xi_clusters`): Automatically identify
///   hierarchical clusters by detecting "valleys" in the reachability plot.
///   A cluster starts at a steep down-area (reachability drops by more than
///   factor `1−ξ`) and ends at a steep up-area. This is the method described
///   in the original OPTICS paper (Ankerst et al., 1999).
///
/// ## Complexity
///
/// - Time: `O(n²)` — each point's ε-neighbourhood requires scanning all points.
///   The priority queue operations add `O(n log n)` overhead.
/// - Space: `O(n)` for ordering, reachability distances, core distances, and
///   the seed set.
///
/// ## References
///
/// - Ankerst, M., Breunig, M. M., Kriegel, H.-P., and Sander, J. "OPTICS:
///   Ordering Points To Identify the Clustering Structure." SIGMOD 1999.
/// - Sklearn cluster._optics module documentation.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Constants & helpers
// ---------------------------------------------------------------------------

///|
/// Positive-infinity sentinel. Used for undefined core distances and
/// initial reachability distances.
let optics_inf : Double = 1.0 / 0.0

///|
/// Squared Euclidean distance between two equal-length vectors. Returns
/// `+∞` when the vectors differ in length so that dimension-mismatched
/// points can never be ε-neighbours.
fn optics_sq_dist(a : Array[Double], b : Array[Double]) -> Double {
  let n = a.length()
  if b.length() != n {
    return optics_inf
  }
  let mut s = 0.0
  for i = 0; i < n; i = i + 1 {
    let d = a[i] - b[i]
    s = s + d * d
  }
  s
}

///|
/// Euclidean distance between two points (takes sqrt).
fn optics_dist(a : Array[Double], b : Array[Double]) -> Double {
  let sq = optics_sq_dist(a, b)
  if sq == optics_inf {
    return optics_inf
  }
  sq.sqrt()
}

// ---------------------------------------------------------------------------
// Result types
// ---------------------------------------------------------------------------

///|
/// Result of running OPTICS on a point set.
///
/// - `ordering`: The order in which points were processed (indices into the
///   original array).
/// - `reachability`: `reachability[i]` is the reachability distance at which
///   point `i` was added to the ordering. `reachability[ordering[0]]` is
///   `+∞` (the first point has no predecessor).
/// - `core_distances`: `core_distances[i]` is the core distance of point `i`,
///   or `+∞` if point `i` has fewer than `min_pts` neighbours.
/// - `labels`: Cluster labels from DBSCAN-style extraction at `eps_extract`.
///   `-1` means noise. Only populated if `extract_dbscan_clusters` was called.
pub struct OpticsResult {
  ordering : Array[Int]
  reachability : Array[Double]
  core_distances : Array[Double]
  labels : Array[Int]
}

// ---------------------------------------------------------------------------
// Min-heap for the seed set
// ---------------------------------------------------------------------------

///|
/// A binary min-heap of `(reachability_distance, point_index)` pairs.
/// Used as the priority queue (seed set) in the OPTICS algorithm.
priv struct SeedHeap {
  // Parallel arrays: heap_key[i] is the reachability distance,
  // heap_val[i] is the point index.
  heap_key : Array[Double]
  heap_val : Array[Int]
}

///|
fn heap_new() -> SeedHeap {
  { heap_key: [], heap_val: [], }
}

///|
fn heap_size(h : SeedHeap) -> Int {
  h.heap_key.length()
}

///|
fn heap_push(h : SeedHeap, key : Double, val : Int) -> Unit {
  h.heap_key.push(key)
  h.heap_val.push(val)
  let mut i = h.heap_key.length() - 1
  while i > 0 {
    let parent = (i - 1) / 2
    if h.heap_key[parent] <= h.heap_key[i] {
      break
    }
    let tk = h.heap_key[parent]
    h.heap_key[parent] = h.heap_key[i]
    h.heap_key[i] = tk
    let tv = h.heap_val[parent]
    h.heap_val[parent] = h.heap_val[i]
    h.heap_val[i] = tv
    i = parent
  }
}

///|
/// Pop the minimum element. Returns `(key, val)`. Caller must ensure non-empty.
fn heap_pop(h : SeedHeap) -> (Double, Int) {
  let n = h.heap_key.length()
  let top_key = h.heap_key[0]
  let top_val = h.heap_val[0]
  let last_key = h.heap_key[n - 1]
  let last_val = h.heap_val[n - 1]
  h.heap_key[n - 1] = h.heap_key[0]
  h.heap_val[n - 1] = h.heap_val[0]
  h.heap_key[0] = last_key
  h.heap_val[0] = last_val
  ignore(h.heap_key.pop())
  ignore(h.heap_val.pop())
  let nn = h.heap_key.length()
  let mut i = 0
  while true {
    let left = 2 * i + 1
    let right = 2 * i + 2
    let mut smallest = i
    if left < nn && h.heap_key[left] < h.heap_key[smallest] {
      smallest = left
    }
    if right < nn && h.heap_key[right] < h.heap_key[smallest] {
      smallest = right
    }
    if smallest == i {
      break
    }
    let tk = h.heap_key[smallest]
    h.heap_key[smallest] = h.heap_key[i]
    h.heap_key[i] = tk
    let tv = h.heap_val[smallest]
    h.heap_val[smallest] = h.heap_val[i]
    h.heap_val[i] = tv
    i = smallest
  }
  (top_key, top_val)
}

// ---------------------------------------------------------------------------
// Core OPTICS algorithm
// ---------------------------------------------------------------------------

///|
/// Run the OPTICS algorithm on a set of points.
///
/// # Parameters
/// - `points`: The input data, one array per point. All points should have
///   the same dimension; mismatched points are treated as infinitely far.
/// - `eps`: The maximum neighbourhood radius. Must be > 0.
/// - `min_pts`: Minimum number of points to form a dense region (core point).
///   Must be ≥ 1. A value of 1 makes every point a core point.
///
/// # Returns
/// An `OpticsResult` containing the point ordering, reachability distances,
/// and core distances. The `labels` field is empty; call
/// `extract_dbscan_clusters` or `extract_xi_clusters` to populate it.
///
/// # Panics
/// Never aborts. Invalid parameters produce an empty result.
pub fn optics(
  points : Array[Array[Double]],
  eps : Double,
  min_pts : Int,
) -> OpticsResult {
  let n = points.length()
  if n == 0 || eps <= 0.0 || min_pts < 1 {
    return { ordering: [], reachability: [], core_distances: [], labels: [], }
  }
  // For min_pts == 1, every point is its own neighbour and core_dist = 0.
  // This degenerates to single-linkage; still valid.
  let eps_sq = eps * eps
  let reachability = Array::make(n, optics_inf)
  let core_distances = Array::make(n, optics_inf)
  let processed = Array::make(n, false)
  let ordering : Array[Int] = []
  // Pre-compute all pairwise distances? For n > 5000 this is O(n²) memory.
  // We compute neighbourhoods on-the-fly instead.
  for start = 0; start < n; start = start + 1 {
    if processed[start] {
      continue
    }
    // Process this point.
    process_point(
      points, start, eps, eps_sq, min_pts, reachability, core_distances, processed,
      ordering,
    )
  }
  { ordering, reachability, core_distances, labels: [], }
}

///|
/// Process a single point and expand its neighbourhood using a seed heap.
fn process_point(
  points : Array[Array[Double]],
  p_idx : Int,
  eps : Double,
  eps_sq : Double,
  min_pts : Int,
  reachability : Array[Double],
  core_distances : Array[Double],
  processed : Array[Bool],
  ordering : Array[Int],
) -> Unit {
  // Use a seed heap (priority queue) for the frontier.
  let heap = heap_new()
  // Process the starting point.
  process_single(
    points, p_idx, eps, eps_sq, min_pts, reachability, core_distances, processed,
    ordering, heap,
  )
  // Expand from the seed heap.
  while heap_size(heap) > 0 {
    let (_, q) = heap_pop(heap)
    if processed[q] {
      continue
    }
    process_single(
      points, q, eps, eps_sq, min_pts, reachability, core_distances, processed, ordering,
      heap,
    )
  }
}

///|
/// Process a single point: compute its neighbourhood, core distance, update
/// the ordering, and update the seed heap with unprocessed neighbours.
fn process_single(
  points : Array[Array[Double]],
  p_idx : Int,
  eps : Double,
  eps_sq : Double,
  min_pts : Int,
  reachability : Array[Double],
  core_distances : Array[Double],
  processed : Array[Bool],
  ordering : Array[Int],
  heap : SeedHeap,
) -> Unit {
  let n = points.length()
  processed[p_idx] = true
  ordering.push(p_idx)
  // Find all ε-neighbours and compute core distance.
  // We need the distances sorted to find the min_pts-th nearest.
  let neigh_dists : Array[Double] = []
  for j = 0; j < n; j = j + 1 {
    let d_sq = optics_sq_dist(points[p_idx], points[j])
    if d_sq <= eps_sq {
      neigh_dists.push(d_sq.sqrt())
    }
  }
  // Compute core distance: the min_pts-th smallest distance (1-indexed).
  // If min_pts > neighbourhood size, core_dist is undefined.
  let cd = if neigh_dists.length() >= min_pts {
    // Find the min_pts-th smallest (partial sort via simple selection).
    // Copy and sort.
    let sorted = Array::make(neigh_dists.length(), 0.0)
    for i = 0; i < neigh_dists.length(); i = i + 1 {
      sorted[i] = neigh_dists[i]
    }
    // Selection sort the first min_pts elements (we only need the min_pts-th).
    for i = 0; i < min_pts && i < sorted.length(); i = i + 1 {
      let mut min_idx = i
      for j = i + 1; j < sorted.length(); j = j + 1 {
        if sorted[j] < sorted[min_idx] {
          min_idx = j
        }
      }
      if min_idx != i {
        let tmp = sorted[i]
        sorted[i] = sorted[min_idx]
        sorted[min_idx] = tmp
      }
    }
    sorted[min_pts - 1]
  } else {
    optics_inf
  }
  core_distances[p_idx] = cd
  // If p is a core point, update reachability of unprocessed neighbours.
  if cd != optics_inf {
    for j = 0; j < n; j = j + 1 {
      if processed[j] {
        continue
      }
      let d = optics_dist(points[p_idx], points[j])
      if d <= eps {
        let new_reach = if cd > d { cd } else { d }
        // Update reachability if this is better.
        if new_reach < reachability[j] {
          reachability[j] = new_reach
          heap_push(heap, new_reach, j)
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Cluster extraction: DBSCAN-style
// ---------------------------------------------------------------------------

///|
/// Extract flat clusters from the OPTICS ordering at a specific ε threshold.
///
/// This produces the same result as running DBSCAN with `eps_extract` and
/// `min_pts`, but reuses the pre-computed OPTICS ordering — no recomputation
/// needed.
///
/// # Parameters
/// - `result`: The OPTICS result from `optics()`.
/// - `eps_extract`: The extraction threshold. Must be ≤ the `eps` used in
///   `optics()`. Points with reachability distance > `eps_extract` start new
///   clusters; points with core distance > `eps_extract` are noise.
///
/// # Returns
/// A new `OpticsResult` with the `labels` field populated. Label `-1` means
/// noise; labels `0, 1, 2, ...` are cluster IDs.
pub fn extract_dbscan_clusters(
  result : OpticsResult,
  eps_extract : Double,
) -> OpticsResult {
  let n = result.reachability.length()
  let labels = Array::make(n, -1)
  if n == 0 || eps_extract <= 0.0 {
    return {
      ordering: result.ordering,
      reachability: result.reachability,
      core_distances: result.core_distances,
      labels,
    }
  }
  let mut cluster_id = -1
  for idx = 0; idx < result.ordering.length(); idx = idx + 1 {
    let p = result.ordering[idx]
    let reach = result.reachability[p]
    let cd = result.core_distances[p]
    if reach > eps_extract {
      // This point starts a new potential cluster.
      if cd <= eps_extract && cd != optics_inf {
        cluster_id = cluster_id + 1
        labels[p] = cluster_id
      } else {
        // Noise.
        labels[p] = -1
      }
      // Same cluster as predecessor.
    } else if cd <= eps_extract && cd != optics_inf {
      labels[p] = cluster_id
      // Border point: assign to current cluster if one exists.
    } else if cluster_id >= 0 {
      labels[p] = cluster_id
    } else {
      labels[p] = -1
    }
  }
  {
    ordering: result.ordering,
    reachability: result.reachability,
    core_distances: result.core_distances,
    labels,
  }
}

// ---------------------------------------------------------------------------
// Cluster extraction: ξ-clusters (automatic hierarchical extraction)
// ---------------------------------------------------------------------------

///|
/// Extract hierarchical clusters from the reachability plot using the
/// ξ-steep-area method described in the original OPTICS paper.
///
/// A **steep down-area** begins at index `i` when
/// `reachability[i] ≤ reachability[i+1] * (1 − ξ)` (the reachability drops
/// sharply). A **steep up-area** begins when
/// `reachability[i] ≥ reachability[i+1] / (1 − ξ)` (the reachability rises
/// sharply). A cluster is a valley between a steep down-area and a steep
/// up-area where the maximum reachability in the up-area does not exceed
/// the maximum at the start of the down-area, and the minimum does not drop
/// below the minimum at the end of the up-area.
///
/// # Parameters
/// - `result`: The OPTICS result from `optics()`.
/// - `xi`: The steepness parameter in `(0, 1)`. Smaller values produce more
///   clusters; larger values produce fewer. Typical: 0.05.
///
/// # Returns
/// A new `OpticsResult` with the `labels` field populated.
pub fn extract_xi_clusters(result : OpticsResult, xi : Double) -> OpticsResult {
  let n = result.reachability.length()
  let labels = Array::make(n, -1)
  if n == 0 || xi <= 0.0 || xi >= 1.0 || result.ordering.length() == 0 {
    return {
      ordering: result.ordering,
      reachability: result.reachability,
      core_distances: result.core_distances,
      labels,
    }
  }
  // Build the reachability plot in ordering order.
  let m = result.ordering.length()
  let rplot = Array::make(m, optics_inf)
  for i = 0; i < m; i = i + 1 {
    rplot[i] = result.reachability[result.ordering[i]]
  }
  // ξ-cluster extraction: detect valleys in the reachability plot.
  //
  // Strategy: split the plot at infinity points (connected component
  // boundaries) into segments. Within each segment, detect ξ-clusters
  // by finding steep down → valley → steep up patterns. A steep down at
  // index i means reachability[i] >> reachability[i+1] (ratio >= 1/(1-ξ)).
  // A steep up means reachability[i] << reachability[i+1] (ratio <= 1-ξ).
  let steep_down_threshold = 1.0 / (1.0 - xi)
  let steep_up_threshold = 1.0 - xi
  let mut cluster_id = 0
  // Process each connected component separately.
  let mut seg_start = 0
  while seg_start < m {
    // Find the end of the current segment (next infinity or end of plot).
    let mut seg_end = seg_start
    while seg_end < m && rplot[seg_end] != optics_inf {
      seg_end = seg_end + 1
    }
    // Segment is [seg_start, seg_end). The point at seg_start-1 (if exists)
    // has reachability = inf (component boundary).
    // If segment has at least 2 points, try to detect ξ-clusters within it.
    let seg_len = seg_end - seg_start
    if seg_len >= 2 {
      // Check if there's a steep down at the start of the segment
      // (i.e., the first point has higher reachability than the rest).
      // This happens when the component boundary (inf) is just before seg_start.
      let has_boundary = seg_start > 0 && rplot[seg_start - 1] == optics_inf
      if has_boundary {
        // The segment starts after an inf boundary — the entire segment
        // is a potential cluster (valley from the inf drop to the end).
        // Check if there's a steep up at the end (next inf boundary).
        let has_end_boundary = seg_end < m && rplot[seg_end] == optics_inf
        if has_end_boundary {
          // Complete valley: inf → low → inf. Assign as cluster.
          for kk = seg_start; kk < seg_end; kk = kk + 1 {
            if labels[result.ordering[kk]] == -1 {
              labels[result.ordering[kk]] = cluster_id
            }
          }
          cluster_id = cluster_id + 1
        } else {
          // Valley from inf to end of plot. Check for internal steep up.
          let mut found_up = false
          for kk = seg_start; kk < seg_end - 1; kk = kk + 1 {
            let r = rplot[kk] / rplot[kk + 1]
            if r <= steep_up_threshold {
              // Steep up found — cluster ends here.
              for jj = seg_start; jj <= kk + 1; jj = jj + 1 {
                if labels[result.ordering[jj]] == -1 {
                  labels[result.ordering[jj]] = cluster_id
                }
              }
              cluster_id = cluster_id + 1
              found_up = true
              break
            }
          }
          if !found_up {
            // No steep up — entire segment is one cluster.
            for kk = seg_start; kk < seg_end; kk = kk + 1 {
              if labels[result.ordering[kk]] == -1 {
                labels[result.ordering[kk]] = cluster_id
              }
            }
            cluster_id = cluster_id + 1
          }
        }
      } else {
        // No boundary before segment — look for internal steep down/up.
        let mut i = seg_start
        while i < seg_end - 1 {
          let ratio = rplot[i] / rplot[i + 1]
          if ratio >= steep_down_threshold {
            // Steep down — start of cluster.
            let c_start = i
            let mut c_end = seg_end - 1
            let mut found_up = false
            for j = i + 1; j < seg_end - 1; j = j + 1 {
              let r = rplot[j] / rplot[j + 1]
              if r <= steep_up_threshold {
                c_end = j + 1
                found_up = true
                break
              }
            }
            for kk = c_start; kk <= c_end; kk = kk + 1 {
              if labels[result.ordering[kk]] == -1 {
                labels[result.ordering[kk]] = cluster_id
              }
            }
            cluster_id = cluster_id + 1
            i = c_end + 1
            let _ = found_up
          } else {
            i = i + 1
          }
        }
      }
    }
    // Move to the next segment (skip the infinity point).
    seg_start = seg_end + 1
  }
  {
    ordering: result.ordering,
    reachability: result.reachability,
    core_distances: result.core_distances,
    labels,
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "optics: empty input" {
  let result = optics([], 1.0, 2)
  assert_true(result.ordering.length() == 0)
  assert_true(result.reachability.length() == 0)
  assert_true(result.core_distances.length() == 0)
}

///|
test "optics: invalid params" {
  let pts = [[0.0], [1.0]]
  let r1 = optics(pts, 0.0, 2)
  assert_true(r1.ordering.length() == 0)
  let r2 = optics(pts, 1.0, 0)
  assert_true(r2.ordering.length() == 0)
}

///|
test "optics: single point" {
  let pts = [[0.0, 0.0]]
  let result = optics(pts, 1.0, 1)
  assert_true(result.ordering.length() == 1)
  assert_true(result.ordering[0] == 0)
  assert_true(result.reachability[0] == optics_inf)
  assert_true(result.core_distances[0] == 0.0)
}

///|
test "optics: two points close" {
  let pts = [[0.0], [0.5]]
  let result = optics(pts, 2.0, 2)
  assert_true(result.ordering.length() == 2)
  // Both points are within eps of each other.
  // Core distance of point 0 is 0.5 (distance to its 2nd nearest neighbor = point 1).
  assert_true(result.core_distances[0] <= 0.5 + 1.0e-10)
  assert_true(result.core_distances[1] <= 0.5 + 1.0e-10)
  // The second point processed has reachability = max(core_dist(first), dist).
  let second = result.ordering[1]
  assert_true(result.reachability[second] <= 0.5 + 1.0e-10)
}

///|
test "optics: ordering covers all points" {
  let pts = [
    [0.0, 0.0],
    [1.0, 0.0],
    [0.0, 1.0],
    [10.0, 10.0],
    [10.5, 10.0],
    [10.0, 10.5],
  ]
  let result = optics(pts, 2.0, 2)
  assert_true(result.ordering.length() == 6)
  // Every point appears exactly once.
  let seen = Array::make(6, false)
  for i = 0; i < 6; i = i + 1 {
    let idx = result.ordering[i]
    assert_true(idx >= 0 && idx < 6)
    assert_true(!seen[idx])
    seen[idx] = true
  }
}

///|
test "optics: two well-separated clusters" {
  // Cluster 1: points near origin
  // Cluster 2: points near (10, 10)
  let pts = [
    [0.0, 0.0],
    [0.5, 0.0],
    [0.0, 0.5],
    [0.5, 0.5],
    [10.0, 10.0],
    [10.5, 10.0],
    [10.0, 10.5],
    [10.5, 10.5],
  ]
  let result = optics(pts, 1.5, 2)
  assert_true(result.ordering.length() == 8)
  // The ordering should keep cluster members together.
  // Check that points 0-3 are contiguous and 4-7 are contiguous.
  let mut first_cluster_end = -1
  for i = 0; i < 8; i = i + 1 {
    if result.ordering[i] < 4 {
      first_cluster_end = i
    }
  }
  // After the first cluster ends, all remaining should be the second cluster.
  for i = first_cluster_end + 1; i < 8; i = i + 1 {
    assert_true(result.ordering[i] >= 4)
  }
}

///|
test "optics: reachability distance correctness" {
  // Three points in a line: 0 -- 1 -- 2
  let pts = [[0.0], [1.0], [2.0]]
  let result = optics(pts, 3.0, 2)
  // All three should be processed.
  assert_true(result.ordering.length() == 3)
  // The first point has reachability = infinity.
  assert_true(result.reachability[result.ordering[0]] == optics_inf)
  // The second point's reachability should be ≤ 1.0 (dist = 1.0).
  let second = result.ordering[1]
  assert_true(result.reachability[second] <= 1.0 + 1.0e-10)
}

///|
test "optics: core distance undefined for sparse point" {
  // A point far away from others with min_pts > 1 should have infinite core dist.
  let pts = [[0.0], [0.1], [5.0]]
  let result = optics(pts, 1.0, 2)
  // Point at 5.0 has no neighbors within eps=1.0 except itself.
  // min_pts=2 means it needs at least 2 neighbors.
  assert_true(result.core_distances[2] == optics_inf)
}

///|
test "optics: DBSCAN extraction - two clusters" {
  let pts = [
    [0.0, 0.0],
    [0.5, 0.0],
    [0.0, 0.5],
    [0.5, 0.5],
    [10.0, 10.0],
    [10.5, 10.0],
    [10.0, 10.5],
    [10.5, 10.5],
  ]
  let result = optics(pts, 2.0, 2)
  let extracted = extract_dbscan_clusters(result, 1.0)
  // Points 0-3 should be in one cluster, 4-7 in another.
  let l0 = extracted.labels[0]
  let l1 = extracted.labels[1]
  let l2 = extracted.labels[2]
  let l3 = extracted.labels[3]
  let l4 = extracted.labels[4]
  let l5 = extracted.labels[5]
  let l6 = extracted.labels[6]
  let l7 = extracted.labels[7]
  // All cluster members should have the same label.
  assert_true(l0 == l1)
  assert_true(l1 == l2)
  assert_true(l2 == l3)
  assert_true(l4 == l5)
  assert_true(l5 == l6)
  assert_true(l6 == l7)
  // Different clusters should have different labels.
  assert_true(l0 != l4)
  // Labels should be non-negative (not noise).
  assert_true(l0 >= 0)
  assert_true(l4 >= 0)
}

///|
test "optics: DBSCAN extraction - noise point" {
  let pts = [
    [0.0, 0.0],
    [0.5, 0.0],
    [20.0, 20.0], // Far away — noise
  ]
  let result = optics(pts, 2.0, 2)
  let extracted = extract_dbscan_clusters(result, 1.5)
  // Point 2 should be noise (-1).
  assert_true(extracted.labels[2] == -1)
  // Points 0 and 1 should be in the same cluster.
  assert_true(extracted.labels[0] >= 0)
  assert_true(extracted.labels[0] == extracted.labels[1])
}

///|
test "optics: xi extraction - two clusters" {
  let pts = [
    [0.0, 0.0],
    [0.5, 0.0],
    [0.0, 0.5],
    [0.5, 0.5],
    [10.0, 10.0],
    [10.5, 10.0],
    [10.0, 10.5],
    [10.5, 10.5],
  ]
  let result = optics(pts, 5.0, 2)
  let extracted = extract_xi_clusters(result, 0.05)
  // At least two distinct non-noise labels should exist.
  let label_set : Array[Int] = []
  for i = 0; i < 8; i = i + 1 {
    if extracted.labels[i] >= 0 {
      let mut found = false
      for j = 0; j < label_set.length(); j = j + 1 {
        if label_set[j] == extracted.labels[i] {
          found = true
          break
        }
      }
      if !found {
        label_set.push(extracted.labels[i])
      }
    }
  }
  assert_true(label_set.length() >= 2)
}

///|
test "optics: min_pts=1 degenerates to single linkage" {
  let pts = [[0.0], [1.0], [2.0], [3.0]]
  let result = optics(pts, 10.0, 1)
  // With min_pts=1, core distance is always 0.
  for i = 0; i < 4; i = i + 1 {
    assert_true(result.core_distances[i] == 0.0)
  }
  // All points should be processed.
  assert_true(result.ordering.length() == 4)
}

///|
test "optics: dimension mismatch handled" {
  let pts = [[0.0, 0.0], [1.0], [0.0, 1.0]]
  let result = optics(pts, 2.0, 2)
  // Should not abort; mismatched point treated as infinitely far.
  assert_true(result.ordering.length() == 3)
}

///|
test "optics: deterministic ordering" {
  let pts = [[0.0, 0.0], [1.0, 0.0], [0.0, 1.0], [1.0, 1.0]]
  let r1 = optics(pts, 2.0, 2)
  let r2 = optics(pts, 2.0, 2)
  // Same input should produce same ordering.
  assert_true(r1.ordering.length() == r2.ordering.length())
  for i = 0; i < r1.ordering.length(); i = i + 1 {
    assert_true(r1.ordering[i] == r2.ordering[i])
  }
  // Same reachability.
  for i = 0; i < r1.reachability.length(); i = i + 1 {
    assert_true(r1.reachability[i] == r2.reachability[i])
  }
}

///|
test "optics: stress test 100 points" {
  // 10 clusters of 10 points each.
  let pts : Array[Array[Double]] = []
  let mut seed : UInt64 = 42
  for c = 0; c < 10; c = c + 1 {
    let cx = (c * 10).to_double()
    let cy = (c * 10 + 5).to_double()
    for _k = 0; _k < 10; _k = _k + 1 {
      // Simple LCG for pseudo-random jitter.
      seed = seed * 6364136223846793005UL + 1442695040888963407UL
      let jx = ((seed >> 33).to_double() / 2147483648.0 - 0.5) * 0.5
      seed = seed * 6364136223846793005UL + 1442695040888963407UL
      let jy = ((seed >> 33).to_double() / 2147483648.0 - 0.5) * 0.5
      pts.push([cx + jx, cy + jy])
    }
  }
  let result = optics(pts, 3.0, 3)
  assert_true(result.ordering.length() == 100)
  // All points should be processed.
  let seen = Array::make(100, false)
  for i = 0; i < 100; i = i + 1 {
    seen[result.ordering[i]] = true
  }
  for i = 0; i < 100; i = i + 1 {
    assert_true(seen[i])
  }
  // DBSCAN extraction should find ~10 clusters.
  let extracted = extract_dbscan_clusters(result, 2.0)
  let mut max_label = -1
  for i = 0; i < 100; i = i + 1 {
    if extracted.labels[i] > max_label {
      max_label = extracted.labels[i]
    }
  }
  assert_true(max_label >= 9)
  assert_true(max_label <= 10)
}

///|
test "optics: reachability plot valley detection" {
  // Points forming a clear valley in the reachability plot:
  // Dense cluster in the middle, sparse on the sides.
  let pts : Array[Array[Double]] = []
  // Left sparse point.
  pts.push([-10.0])
  // Dense cluster.
  for i = 0; i < 10; i = i + 1 {
    pts.push([i.to_double() * 0.1])
  }
  // Right sparse point.
  pts.push([10.0])
  let result = optics(pts, 20.0, 3)
  assert_true(result.ordering.length() == 12)
  // The reachability of the dense cluster points should be small.
  let mut has_small_reach = false
  for i = 0; i < 12; i = i + 1 {
    if result.reachability[i] != optics_inf && result.reachability[i] < 0.5 {
      has_small_reach = true
    }
  }
  assert_true(has_small_reach)
}
