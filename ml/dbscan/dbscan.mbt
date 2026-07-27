/// DBSCAN — Density-Based Spatial Clustering of Applications with Noise.
///
/// Discovers clusters of arbitrary shape by connectivity in dense regions of
/// the point set. Unlike k-means, DBSCAN needs no cluster count: it grows
/// clusters from dense "core" points and marks sparse outliers as noise.
///
/// ## Algorithm
/// For each unvisited point `p`, count its ε-neighbours (points whose squared
/// Euclidean distance to `p` is ≤ ε², including `p` itself, whose distance is
/// `0`). If `p` has at least `min_pts` neighbours it is a *core* point: a new
/// cluster is opened and every density-reachable point is absorbed via a
/// work-list (BFS) expansion. A neighbour that is itself a core point extends
/// the frontier; a neighbour that is merely a *border* point joins the cluster
/// without expanding it. Points that never become density-reachable from any
/// core point remain *noise* and are excluded from the result.
///
/// ## Complexity
/// - Time:  `O(n²)` — each point is compared with every other point exactly
///   once per neighbourhood query, and each point is queried at most once
///   (core points query once when they seed/extend the frontier; border and
///   noise points are never queried).
/// - Space: `O(n)` for labels and the work-list.
///
/// ## Distance
/// Squared Euclidean distance is used throughout; comparing against `ε²` is
/// equivalent to comparing Euclidean distance against `ε` (sqrt is monotonic
/// and non-negative), so no square root is ever needed.
///
/// ## Dimension safety
/// `dbscan_sq_dist` returns `+∞` for vectors of differing length, so
/// dimension-mismatched points are simply never ε-neighbours — they fall back
/// to noise unless joined by same-dimension core points. No `abort` is ever
/// raised by the public API.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Constants & helpers
// ---------------------------------------------------------------------------

///|
/// Positive-infinity sentinel used to make dimension-mismatched vectors
/// "infinitely far apart". Obtained via IEEE-754 division by zero, which
/// yields `+∞` without trapping; it compares greater than every finite
/// `Double`, so it is naturally excluded from any finite `ε`-neighbourhood.
let dbscan_inf : Double = 1.0 / 0.0

///|
/// Squared Euclidean distance between two equal-length vectors. Returns
/// `+∞` when the vectors differ in length so that dimension-mismatched
/// points can never be ε-neighbours.
fn dbscan_sq_dist(a : Array[Double], b : Array[Double]) -> Double {
  let n = a.length()
  if b.length() != n {
    return dbscan_inf
  }
  let mut s = 0.0
  for i = 0; i < n; i = i + 1 {
    let d = a[i] - b[i]
    s = s + d * d
  }
  s
}

///|
/// Indices of every point within `eps_sq` (squared ε) of `points[p_idx]`,
/// inclusive of `p_idx` itself (distance `0`). `O(n)` per call.
fn dbscan_region_query(
  points : Array[DBSCANPoint],
  p_idx : Int,
  eps_sq : Double,
) -> Array[Int] {
  let n = points.length()
  let nbrs : Array[Int] = []
  let pc = points[p_idx].coords
  for q = 0; q < n; q = q + 1 {
    if dbscan_sq_dist(pc, points[q].coords) <= eps_sq {
      nbrs.push(q)
    }
  }
  nbrs
}

// ---------------------------------------------------------------------------
// Public types & entry point
// ---------------------------------------------------------------------------

///|
/// A labelled input point. `id` is the caller-supplied identifier that is
/// returned (untouched) inside the cluster lists; `coords` is the feature
/// vector, whose dimension is arbitrary but should be consistent across the
/// point set for meaningful clustering.
pub struct DBSCANPoint {
  id : Int
  coords : Array[Double]
}

///|
/// Cluster `points` with the DBSCAN density-based algorithm.
///
/// **Parameters.**
/// - `points`  — the input points, in any order. Each point carries its own
///   `id`; clustering never inspects `id`, it only uses `coords`.
/// - `eps`     — neighbourhood radius. Two points are neighbours when their
///   squared Euclidean distance is ≤ `eps * eps`.
/// - `min_pts` — minimum neighbourhood size (counting the point itself) for a
///   point to qualify as a *core* point. Values `< 1` are clamped to `1`.
///
/// **Return value.** An array of clusters; each cluster is the array of point
/// `id`s that belong to it, in density-reachable (BFS) order. Noise points —
/// those reachable from no core point — are excluded entirely, so the union
/// of all returned ids is exactly the non-noise subset of the input.
///
/// **Edge cases.**
/// - Empty input → empty result.
/// - `eps <= 0` → only coincident points (distance exactly `0`) cluster
///   together; everything else is noise.
/// - `min_pts <= 1` → every point is a core point, so the result is one
///   connected component per ε-connected set (singletons included).
///
/// **Determinism.** The cluster contents depend only on `(points, eps,
/// min_pts)`: the scan order follows the input order, and the BFS work-list is
/// FIFO, so the same input always yields identical clusters in identical
/// order. Cluster *indices* in the outer array follow the order in which the
/// first core point of each cluster is encountered.
pub fn dbscan(
  points : Array[DBSCANPoint],
  eps : Double,
  min_pts : Int,
) -> Array[Array[Int]] {
  let n = points.length()
  if n == 0 {
    return []
  }
  // Effective parameters: squared radius and a positive core threshold.
  let eps_sq = eps * eps
  let mp = if min_pts < 1 { 1 } else { min_pts }
  // label[i]: -1 = unvisited, 0 = noise, c >= 1 = cluster id `c`.
  let label = Array::make(n, -1)
  let clusters : Array[Array[Int]] = []
  let mut cid = 0
  for p = 0; p < n; p = p + 1 {
    if label[p] != -1 {
      continue // already noise or assigned to a cluster
    }
    let nbrs = dbscan_region_query(points, p, eps_sq)
    if nbrs.length() < mp {
      // Not dense enough to seed a cluster: provisional noise. It may still be
      // reclaimed as a border point when a later core point reaches it.
      label[p] = 0
      continue
    }
    // Open a new cluster and grow it by density-reachability.
    cid = cid + 1
    label[p] = cid
    let cluster : Array[Int] = [points[p].id]
    // Seed the frontier with the neighbours minus p (already absorbed).
    let queue : Array[Int] = []
    for k = 0; k < nbrs.length(); k = k + 1 {
      if nbrs[k] != p {
        queue.push(nbrs[k])
      }
    }
    let mut head = 0
    while head < queue.length() {
      let q = queue[head]
      head = head + 1
      if label[q] == cid {
        continue // already absorbed by this cluster
      }
      if label[q] == 0 {
        // Previously-noise point becomes a border point: join but never expand.
        label[q] = cid
        cluster.push(points[q].id)
        continue
      }
      // label[q] == -1: unvisited. Absorb, then expand if it is itself a core
      // point. (A point labelled noise above had |N| < mp; since the dataset
      // is fixed its neighbourhood is invariant, so it can never become core.)
      label[q] = cid
      cluster.push(points[q].id)
      let qn = dbscan_region_query(points, q, eps_sq)
      if qn.length() >= mp {
        for k = 0; k < qn.length(); k = k + 1 {
          let r = qn[k]
          if label[r] != cid {
            queue.push(r)
          }
        }
      }
    }
    clusters.push(cluster)
  }
  clusters
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

///|
/// `true` when `id` appears in `cluster`. Used to check membership without
/// depending on cluster-internal ordering.
fn cluster_contains(cluster : Array[Int], id : Int) -> Bool {
  for i = 0; i < cluster.length(); i = i + 1 {
    if cluster[i] == id {
      return true
    }
  }
  false
}

///|
/// Total number of point ids across all clusters.
fn total_clustered(clusters : Array[Array[Int]]) -> Int {
  let mut total = 0
  for c = 0; c < clusters.length(); c = c + 1 {
    total = total + clusters[c].length()
  }
  total
}

///|
/// Index of the cluster that contains `id`, or `-1` (noise / not found).
fn cluster_of(clusters : Array[Array[Int]], id : Int) -> Int {
  for c = 0; c < clusters.length(); c = c + 1 {
    if cluster_contains(clusters[c], id) {
      return c
    }
  }
  -1
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "dbscan: empty input returns no clusters" {
  let r = dbscan([], 1.0, 2)
  assert_eq(r.length(), 0)
}

///|
test "dbscan: single point with min_pts=1 forms a singleton cluster" {
  let pts = [{ id: 0, coords: [5.0, 5.0] }]
  let r = dbscan(pts, 1.0, 1)
  assert_eq(r.length(), 1)
  assert_eq(r[0].length(), 1)
  assert_eq(r[0][0], 0)
}

///|
test "dbscan: isolated point is noise when min_pts=2" {
  let pts = [{ id: 0, coords: [5.0, 5.0] }]
  let r = dbscan(pts, 1.0, 2)
  assert_eq(r.length(), 0) // the lone point is noise, excluded
}

///|
test "dbscan: two well-separated 2-D clusters, one noise point" {
  // Cluster A: four points packed inside a unit square near the origin.
  // Cluster B: four points packed near (10, 10).
  // Noise:    a lone point at (100, 100).
  let pts = [
    { id: 0, coords: [0.0, 0.0] }, // A
    { id: 1, coords: [0.0, 1.0] }, // A
    { id: 2, coords: [1.0, 0.0] }, // A
    { id: 3, coords: [1.0, 1.0] }, // A
    { id: 4, coords: [10.0, 10.0] }, // B
    { id: 5, coords: [10.0, 11.0] }, // B
    { id: 6, coords: [11.0, 10.0] }, // B
    { id: 7, coords: [11.0, 11.0] }, // B
    { id: 8, coords: [100.0, 100.0] }, // noise
  ]
  // eps=1.5 (eps_sq=2.25): within-cluster pairs are at most sqrt(2) apart,
  // between-cluster pairs are far apart; the noise point is far from all.
  let r = dbscan(pts, 1.5, 2)
  assert_eq(r.length(), 2)
  assert_eq(total_clustered(r), 8) // 8 clustered, 1 noise excluded
  // Cluster membership: ids 0-3 together, ids 4-7 together, id 8 absent.
  let ca = cluster_of(r, 0)
  let cb = cluster_of(r, 4)
  assert_true(ca >= 0)
  assert_true(cb >= 0)
  assert_true(ca != cb) // the two clusters are distinct
  for i = 0; i < 4; i = i + 1 {
    assert_eq(cluster_of(r, i), ca)
  }
  for i = 4; i < 8; i = i + 1 {
    assert_eq(cluster_of(r, i), cb)
  }
  assert_eq(cluster_of(r, 8), -1) // noise
  // Each cluster has exactly four members.
  assert_eq(r[ca].length(), 4)
  assert_eq(r[cb].length(), 4)
}

///|
test "dbscan: arbitrary-shape cluster via a connected chain" {
  // Points along a line spaced 0.5 apart: adjacent points are within eps=1.0
  // but the endpoints are far apart. A centroid method would split this; a
  // density method keeps it as one connected cluster.
  let pts : Array[DBSCANPoint] = []
  for i = 0; i < 10; i = i + 1 {
    pts.push({ id: i, coords: [i.to_double() * 0.5, 0.0] })
  }
  let r = dbscan(pts, 1.0, 2)
  assert_eq(r.length(), 1)
  assert_eq(r[0].length(), 10) // the whole chain is one cluster
}

///|
test "dbscan: 3-D clusters separate correctly" {
  // Two tight 3-D blobs far apart.
  let pts : Array[DBSCANPoint] = []
  for i = 0; i < 4; i = i + 1 {
    pts.push({ id: i, coords: [0.0, 0.0, i.to_double()] }) // blob at origin
  }
  for i = 0; i < 4; i = i + 1 {
    pts.push({ id: 100 + i, coords: [50.0, 50.0, i.to_double()] }) // far blob
  }
  let r = dbscan(pts, 2.0, 2)
  assert_eq(r.length(), 2)
  assert_eq(total_clustered(r), 8)
  let c0 = cluster_of(r, 0)
  let c100 = cluster_of(r, 100)
  assert_true(c0 != c100)
  for i = 0; i < 4; i = i + 1 {
    assert_eq(cluster_of(r, i), c0)
    assert_eq(cluster_of(r, 100 + i), c100)
  }
}

///|
test "dbscan: min_pts=1 makes every point a core point" {
  let pts = [
    { id: 0, coords: [0.0] },
    { id: 1, coords: [5.0] }, // distance 5 > eps
    { id: 2, coords: [100.0] }, // distance 95 > eps
  ]
  let r = dbscan(pts, 1.0, 1)
  // With min_pts=1 every point is core, so each isolated point is its own
  // singleton cluster (none is noise).
  assert_eq(r.length(), 3)
  assert_eq(total_clustered(r), 3)
}

///|
test "dbscan: coincident points collapse into one cluster (eps=0)" {
  // eps=0 keeps only distance-exactly-0 neighbours, i.e. coincident points.
  let pts = [
    { id: 0, coords: [2.0, 2.0] },
    { id: 1, coords: [2.0, 2.0] },
    { id: 2, coords: [2.0, 2.0] },
    { id: 3, coords: [9.0, 9.0] }, // not coincident -> noise (min_pts=2)
  ]
  let r = dbscan(pts, 0.0, 2)
  assert_eq(r.length(), 1)
  assert_eq(r[0].length(), 3)
  assert_eq(cluster_of(r, 3), -1) // the isolated point is noise
}

///|
test "dbscan: border point attaches to first cluster that reaches it" {
  // A bridge point exactly eps from two cores lands in whichever cluster
  // reaches it first (here, the lower-id cluster scanned first).
  let pts = [
    { id: 0, coords: [0.0] }, // core of cluster A
    { id: 1, coords: [1.0] }, // within eps=1.5 of both 0 and 2 (border)
    { id: 2, coords: [2.0] }, // core of cluster B
  ]
  let r = dbscan(pts, 1.5, 2)
  // 0 and 2 are each core (neighbourhoods {0,1} and {1,2}); 1 is a border
  // point. All three are density-connected, hence a single cluster.
  assert_eq(r.length(), 1)
  assert_eq(r[0].length(), 3)
}

///|
test "dbscan: dimension-mismatched points are treated as noise" {
  // A 2-D point can never be a neighbour of a 3-D point (infinite distance),
  // so the 3-D outlier is noise even though it sits at a "small" coordinate.
  let pts = [
    { id: 0, coords: [0.0, 0.0] },
    { id: 1, coords: [0.0, 1.0] },
    { id: 2, coords: [0.0, 0.0, 0.0] }, // different dimension
  ]
  let r = dbscan(pts, 2.0, 2)
  // ids 0 and 1 form a cluster; id 2 is unreachable (infinite distance) and
  // thus noise.
  assert_eq(r.length(), 1)
  assert_eq(r[0].length(), 2)
  assert_eq(cluster_of(r, 2), -1)
}
