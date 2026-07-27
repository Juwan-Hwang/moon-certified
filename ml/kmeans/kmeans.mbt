// K-Means clustering for 2-D points, with k-means++ seeding and Lloyd
// refinement. The full contract is documented on `kmeans` below.

// ---------------------------------------------------------------------------
// Internal LCG (Linear Congruential Generator)
// ---------------------------------------------------------------------------

///|
/// LCG multiplier (≡ 1 mod 4) and increment (odd); with the `& 0x7FFFFFFF`
/// mask they give a full-period generator mod 2^31 (Hull-Dobell). The mask
/// keeps only the low 31 bits, so the recurrence is correct mod 2^31
/// regardless of any wraparound in the wider `Int` product. This is the same
/// generator used by `fisher_yates`, `reservoir_sampling`, `skip_list` and
/// `treap` elsewhere in this collection, which makes every run reproducible.
let km_lcg_a : Int = 1103515245

///|
let km_lcg_c : Int = 12345

///|
/// Reproducible default seed (same value used by `fisher_yates`).
let km_default_seed : Int = 0x1A2B3C4D

///|
/// Private mutable LCG state, advanced by `Rng::next` to yield non-negative
/// `Int`s in `[0, 2^31)`.
priv struct Rng {
  mut state : Int
}

///|
/// Create an LCG whose state is `seed` masked to 31 bits; a zero seed is
/// replaced by 1 so the stream never sits at the trivial fixed point.
fn Rng::new(seed : Int) -> Rng {
  let s = seed & 0x7FFFFFFF
  { state: if s == 0 { 1 } else { s } }
}

///|
/// Advance the LCG one step and return the new state in `[0, 2^31)`.
fn Rng::next(self : Rng) -> Int {
  self.state = (self.state * km_lcg_a + km_lcg_c) & 0x7FFFFFFF
  self.state
}

///|
/// Draw a `Double` in `[0, 1)` from the next LCG state.
fn Rng::next_double(self : Rng) -> Double {
  // state ∈ [0, 2^31); dividing by 2^31 maps it to [0, 1).
  self.next().to_double() / 2147483648.0
}

// ---------------------------------------------------------------------------
// Geometry helper
// ---------------------------------------------------------------------------

///|
/// Squared Euclidean distance between two 2-D points. Used for both
/// nearest-centroid assignment and k-means++ weighting; because `sqrt` is
/// monotonic the argmin is unchanged, so no square root is ever needed (and
/// `@math.sqrt` is not part of the MoonBit core).
fn sq_dist(a : (Double, Double), b : (Double, Double)) -> Double {
  let dx = a.0 - b.0
  let dy = a.1 - b.1
  dx * dx + dy * dy
}

// ---------------------------------------------------------------------------
// Result type
// ---------------------------------------------------------------------------

///|
/// Outcome of `kmeans`: the final cluster centres and, for each input point
/// (in input order), the index of its assigned centre in `[0, k_eff)`.
pub struct KMeansResult {
  centroids : Array[(Double, Double)]
  assignments : Array[Int]
}

// ---------------------------------------------------------------------------
// k-means++ initialisation
// ---------------------------------------------------------------------------

///|
/// Choose `k` initial centres via k-means++. The first centre is a pseudo-
/// random point; each later centre is drawn with probability proportional to
/// its squared distance to the nearest centre chosen so far. An incremental
/// `min_sq` table keeps the total cost O(n·k) rather than O(n·k²).
fn kmeans_pp_init(
  points : Array[(Double, Double)],
  k : Int,
  rng : Rng,
) -> Array[(Double, Double)] {
  let n = points.length()
  let centroids : Array[(Double, Double)] = []
  // `min_sq[i]` = squared distance from point i to the nearest chosen centre.
  let min_sq = FixedArray::make(n, 0.0)
  let first = rng.next() % n
  centroids.push(points[first])
  for i = 0; i < n; i = i + 1 {
    min_sq[i] = sq_dist(points[i], points[first])
  }
  for c = 1; c < k; c = c + 1 {
    // Total weighted mass; if it is zero, every point already coincides with a
    // chosen centre, so cycle through point indices (k <= n is guaranteed by
    // the caller, so `c < n` here).
    let mut total = 0.0
    for i = 0; i < n; i = i + 1 {
      total = total + min_sq[i]
    }
    if total <= 0.0 {
      centroids.push(points[c])
      continue
    }
    // Draw r ∈ [0, total) and walk the cumulative sum to pick a centre. The
    // scan is a `while` loop so we can `break` as soon as the threshold is
    // crossed; `chosen` defaults to the last point for the (impossible) case
    // where rounding never exceeds `r`.
    let r = rng.next_double() * total
    let mut cumul = 0.0
    let mut chosen = n - 1
    let mut i = 0
    while i < n {
      cumul = cumul + min_sq[i]
      if cumul > r {
        chosen = i
        break
      }
      i = i + 1
    }
    centroids.push(points[chosen])
    // Refresh `min_sq` with the newly added centre.
    for j = 0; j < n; j = j + 1 {
      let d = sq_dist(points[j], points[chosen])
      if d < min_sq[j] {
        min_sq[j] = d
      }
    }
  }
  centroids
}

// ---------------------------------------------------------------------------
// Lloyd iteration
// ---------------------------------------------------------------------------

///|
/// Assign every point to the index of its nearest centroid (ties go to the
/// lower index, since `<` is strict and the scan starts at 0).
fn assign_all(
  points : Array[(Double, Double)],
  centroids : Array[(Double, Double)],
) -> Array[Int] {
  let n = points.length()
  let k = centroids.length()
  let assignments = Array::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    let mut best_c = 0
    let mut best_d = sq_dist(points[i], centroids[0])
    for c = 1; c < k; c = c + 1 {
      let d = sq_dist(points[i], centroids[c])
      if d < best_d {
        best_d = d
        best_c = c
      }
    }
    assignments[i] = best_c
  }
  assignments
}

///|
/// Recompute each centroid as the mean of its assigned points. A cluster with
/// no points is left at its previous centre as a placeholder and then reseeded
/// by `reseed_empty` to the worst-served point.
fn recompute(
  points : Array[(Double, Double)],
  assignments : Array[Int],
  prev_centroids : Array[(Double, Double)],
) -> Array[(Double, Double)] {
  let n = points.length()
  let k = prev_centroids.length()
  let sum_x = Array::make(k, 0.0)
  let sum_y = Array::make(k, 0.0)
  let counts = Array::make(k, 0)
  for i = 0; i < n; i = i + 1 {
    let c = assignments[i]
    let (px, py) = points[i]
    sum_x[c] = sum_x[c] + px
    sum_y[c] = sum_y[c] + py
    counts[c] = counts[c] + 1
  }
  let centroids : Array[(Double, Double)] = Array::make(k, (0.0, 0.0))
  for c = 0; c < k; c = c + 1 {
    if counts[c] > 0 {
      let cnt = counts[c].to_double()
      centroids[c] = (sum_x[c] / cnt, sum_y[c] / cnt)
    } else {
      centroids[c] = prev_centroids[c]
    }
  }
  reseed_empty(points, centroids, counts, assignments)
  centroids
}

///|
/// Reseed each empty cluster to a distinct, currently worst-served point — the
/// point whose squared distance to its own (non-empty) centroid is largest.
/// This replaces a useless stale centre with the single point that most reduces
/// total distortion, and is deterministic given the input order. Points already
/// taken by a previous reseed are skipped so each empty cluster gets a distinct
/// seed point.
fn reseed_empty(
  points : Array[(Double, Double)],
  centroids : Array[(Double, Double)],
  counts : Array[Int],
  assignments : Array[Int],
) -> Unit {
  let n = points.length()
  let k = centroids.length()
  let empties : Array[Int] = []
  for c = 0; c < k; c = c + 1 {
    if counts[c] == 0 {
      empties.push(c)
    }
  }
  if empties.length() == 0 {
    return
  }
  let used = FixedArray::make(n, false)
  for ei = 0; ei < empties.length(); ei = ei + 1 {
    let c = empties[ei]
    let mut best_idx = -1
    let mut best_d = -1.0
    for i = 0; i < n; i = i + 1 {
      if !used[i] {
        let (px, py) = points[i]
        // `assignments[i]` is always a non-empty cluster, so this reads a
        // freshly recomputed mean, never a stale placeholder.
        let (cx, cy) = centroids[assignments[i]]
        let d = (px - cx) * (px - cx) + (py - cy) * (py - cy)
        if d > best_d {
          best_d = d
          best_idx = i
        }
      }
    }
    if best_idx >= 0 {
      centroids[c] = points[best_idx]
      used[best_idx] = true
    }
  }
}

///|
/// Element-wise equality of two int arrays of the same length.
fn assignments_equal(a : Array[Int], b : Array[Int]) -> Bool {
  let n = a.length()
  if b.length() != n {
    return false
  }
  for i = 0; i < n; i = i + 1 {
    if a[i] != b[i] {
      return false
    }
  }
  true
}

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

///|
/// Cluster `points` into `k` groups using k-means++ initialisation followed by
/// up to `max_iters` Lloyd iterations.
///
/// **Distance.** All comparisons use *squared* Euclidean distance. The argmin
/// is identical to the unsquared distance (sqrt is monotonic), and k-means++
/// weights are proportional to D(x)^2 — so no square root is ever needed.
///
/// **Initialisation (k-means++).** The first centre is a deterministic
/// pseudo-random point; each subsequent centre is drawn with probability
/// proportional to its squared distance to the nearest already-chosen centre.
/// This spreads the initial centres far apart, which both speeds up Lloyd's
/// iteration and yields provably O(log k)-competitive expected cost versus the
/// optimal clustering (Arthur & Vassilvitskii, 2007). A private LCG supplies
/// the pseudo-random draws, so every run is fully reproducible.
///
/// **Refinement (Lloyd).** Repeat up to `max_iters` times: recompute each
/// centroid as the mean of its assigned points, then reassign every point to
/// its nearest centroid. Stop early when an iteration leaves the assignment
/// unchanged (a fixed point). Empty clusters — rare under k-means++ — are
/// reseeded to the point currently *worst-served* by its own centroid, which
/// reduces total distortion instead of leaving a stale centre.
///
/// **Edge cases.**
///   - Empty input → empty `centroids` and `assignments`.
///   - `k <= 0` → treated as `k = 1`.
///   - `k > n_points` → clamped to `n_points` (each point its own cluster).
///   - `max_iters <= 0` → the k-means++ centres are returned with their direct
///     assignment, unrefined.
///
/// **Consistency.** The returned `assignments` are always exactly the nearest
/// centroid of each point under the returned `centroids`, i.e. the result is a
/// fixed point of one more assignment step.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.
///
/// **Note**: All calls use the same default PRNG seed, so the same input
/// always produces the same result. For independent runs with different
/// initializations, use [`kmeans_with_seed`].
pub fn kmeans(
  points : Array[(Double, Double)],
  k : Int,
  max_iters : Int,
) -> KMeansResult {
  kmeans_with_seed(points, k, max_iters, km_default_seed)
}

///|
/// K-means clustering with a user-specified PRNG seed. Different seeds
/// produce different k-means++ initializations, which may yield different
/// local optima. This is the recommended API for production code where
/// multiple independent runs are needed to find the best clustering.
pub fn kmeans_with_seed(
  points : Array[(Double, Double)],
  k : Int,
  max_iters : Int,
  seed : Int,
) -> KMeansResult {
  let n = points.length()
  if n == 0 {
    return { centroids: [], assignments: [] }
  }
  let k_eff = if k < 1 { 1 } else if k > n { n } else { k }
  let rng = Rng::new(seed)
  let centroids = kmeans_pp_init(points, k_eff, rng)
  let mut cur_centroids = centroids
  let mut cur_assignments = assign_all(points, cur_centroids)
  let mut changed = true
  let mut iters = 0
  while changed && iters < max_iters {
    iters = iters + 1
    cur_centroids = recompute(points, cur_assignments, cur_centroids)
    let new_assignments = assign_all(points, cur_centroids)
    if assignments_equal(new_assignments, cur_assignments) {
      changed = false
    } else {
      cur_assignments = new_assignments
    }
  }
  { centroids: cur_centroids, assignments: cur_assignments }
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

///|
/// Tolerant equality for `Double`: passes if the difference is within an
/// absolute bound (`1e-6`) or a relative bound (`1e-6` of the combined
/// magnitude). Used to compare centroid coordinates that accumulate a small
/// amount of floating-point error.
fn approx_eq(a : Double, b : Double) -> Bool {
  let diff = (a - b).abs()
  diff < 1.0e-6 || diff < 1.0e-6 * (a.abs() + b.abs())
}

///|
/// Index of the centroid whose coordinates approximately equal `(x, y)`, or
/// `-1` if none matches.
fn centroid_index_near(
  centroids : Array[(Double, Double)],
  x : Double,
  y : Double,
) -> Int {
  for i = 0; i < centroids.length(); i = i + 1 {
    let (cx, cy) = centroids[i]
    if approx_eq(cx, x) && approx_eq(cy, y) {
      return i
    }
  }
  -1
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "kmeans: empty points" {
  let r = kmeans([], 3, 10)
  assert_eq(r.centroids.length(), 0)
  assert_eq(r.assignments.length(), 0)
}

///|
test "kmeans: single point" {
  let r = kmeans([(5.0, 5.0)], 1, 10)
  assert_eq(r.centroids.length(), 1)
  assert_eq(r.assignments.length(), 1)
  assert_eq(r.assignments[0], 0)
  let (cx, cy) = r.centroids[0]
  assert_true(approx_eq(cx, 5.0))
  assert_true(approx_eq(cy, 5.0))
}

///|
test "kmeans: k greater than n is clamped to n" {
  let pts = [(0.0, 0.0), (10.0, 10.0), (20.0, 20.0)]
  let r = kmeans(pts, 10, 10) // k=10 > n=3 -> k_eff=3
  assert_eq(r.centroids.length(), 3)
  assert_eq(r.assignments.length(), 3)
  // Each point is its own cluster, so assignments are a permutation of [0,1,2].
  let seen = [false, false, false]
  for i = 0; i < 3; i = i + 1 {
    let c = r.assignments[i]
    assert_true(c >= 0 && c < 3)
    assert_false(seen[c])
    seen[c] = true
  }
  // The centroid set equals the point set (in some order).
  assert_true(centroid_index_near(r.centroids, 0.0, 0.0) >= 0)
  assert_true(centroid_index_near(r.centroids, 10.0, 10.0) >= 0)
  assert_true(centroid_index_near(r.centroids, 20.0, 20.0) >= 0)
}

///|
test "kmeans: two well-separated clusters" {
  let pts = [
    (0.0, 0.0),
    (0.0, 1.0),
    (1.0, 0.0),
    (1.0, 1.0),
    (10.0, 10.0),
    (10.0, 11.0),
    (11.0, 10.0),
    (11.0, 11.0),
  ]
  let r = kmeans(pts, 2, 100)
  assert_eq(r.centroids.length(), 2)
  // First four points share one cluster, last four another, and they differ.
  let g0 = r.assignments[0]
  for i = 0; i < 4; i = i + 1 {
    assert_eq(r.assignments[i], g0)
  }
  let g1 = r.assignments[4]
  for i = 4; i < 8; i = i + 1 {
    assert_eq(r.assignments[i], g1)
  }
  assert_true(g0 != g1)
  // Centroids land near the two group means (in some order).
  assert_true(centroid_index_near(r.centroids, 0.5, 0.5) >= 0)
  assert_true(centroid_index_near(r.centroids, 10.5, 10.5) >= 0)
}

///|
test "kmeans: three well-separated clusters" {
  let pts : Array[(Double, Double)] = []
  // Cluster A around (0,0), B around (20,0), C around (10,20); 4 points each.
  let centres = [(0.0, 0.0), (20.0, 0.0), (10.0, 20.0)]
  for ci = 0; ci < 3; ci = ci + 1 {
    let (cx, cy) = centres[ci]
    pts.push((cx, cy))
    pts.push((cx + 1.0, cy))
    pts.push((cx, cy + 1.0))
    pts.push((cx + 1.0, cy + 1.0))
  }
  let r = kmeans(pts, 3, 100)
  assert_eq(r.centroids.length(), 3)
  // Three distinct clusters; each group of 4 points shares its assignment.
  let groups = [r.assignments[0], r.assignments[4], r.assignments[8]]
  assert_true(groups[0] != groups[1])
  assert_true(groups[1] != groups[2])
  assert_true(groups[0] != groups[2])
  for gi = 0; gi < 3; gi = gi + 1 {
    for pi = 0; pi < 4; pi = pi + 1 {
      assert_eq(r.assignments[gi * 4 + pi], groups[gi])
    }
  }
  // Centroids land near the three group means (in some order).
  assert_true(centroid_index_near(r.centroids, 0.5, 0.5) >= 0)
  assert_true(centroid_index_near(r.centroids, 20.5, 0.5) >= 0)
  assert_true(centroid_index_near(r.centroids, 10.5, 20.5) >= 0)
}

///|
test "kmeans: identical points collapse to one centroid" {
  let pts = [(7.0, 7.0), (7.0, 7.0), (7.0, 7.0)]
  let r = kmeans(pts, 1, 10)
  assert_eq(r.centroids.length(), 1)
  let (cx, cy) = r.centroids[0]
  assert_true(approx_eq(cx, 7.0))
  assert_true(approx_eq(cy, 7.0))
  for i = 0; i < 3; i = i + 1 {
    assert_eq(r.assignments[i], 0)
  }
}

///|
test "kmeans: k <= 0 treated as one cluster" {
  let pts = [(0.0, 0.0), (10.0, 0.0), (20.0, 0.0)]
  let r = kmeans(pts, 0, 10)
  assert_eq(r.centroids.length(), 1)
  assert_eq(r.assignments.length(), 3)
  for i = 0; i < 3; i = i + 1 {
    assert_eq(r.assignments[i], 0)
  }
  // Centroid is the mean: (10.0, 0.0).
  let (cx, cy) = r.centroids[0]
  assert_true(approx_eq(cx, 10.0))
  assert_true(approx_eq(cy, 0.0))
}

///|
test "kmeans: max_iters = 0 returns a consistent assignment" {
  let pts = [(0.0, 0.0), (1.0, 1.0), (10.0, 10.0), (11.0, 11.0)]
  let r = kmeans(pts, 2, 0)
  assert_eq(r.centroids.length(), 2)
  assert_eq(r.assignments.length(), 4)
  for i = 0; i < 4; i = i + 1 {
    assert_true(r.assignments[i] >= 0 && r.assignments[i] < 2)
  }
  // Even unrefined, the result is a fixed point of the assignment step.
  for i = 0; i < pts.length(); i = i + 1 {
    let mut best = 0
    let mut best_d = sq_dist(pts[i], r.centroids[0])
    for c = 1; c < r.centroids.length(); c = c + 1 {
      let d = sq_dist(pts[i], r.centroids[c])
      if d < best_d {
        best_d = d
        best = c
      }
    }
    assert_eq(best, r.assignments[i])
  }
}

///|
test "kmeans: result is a fixed point after convergence" {
  let pts : Array[(Double, Double)] = []
  // Two separated chains of 8 points each.
  for i = 0; i < 8; i = i + 1 {
    pts.push((i.to_double(), 0.0))
  }
  for i = 0; i < 8; i = i + 1 {
    pts.push((100.0 + i.to_double(), 0.0))
  }
  let r = kmeans(pts, 2, 100)
  // Reassigning each point to its nearest returned centroid reproduces the
  // returned assignment (the consistency guarantee).
  for i = 0; i < pts.length(); i = i + 1 {
    let mut best = 0
    let mut best_d = sq_dist(pts[i], r.centroids[0])
    for c = 1; c < r.centroids.length(); c = c + 1 {
      let d = sq_dist(pts[i], r.centroids[c])
      if d < best_d {
        best_d = d
        best = c
      }
    }
    assert_eq(best, r.assignments[i])
  }
}

///|
test "kmeans: two separated clouds split cleanly" {
  // Deterministic pseudo-random points forming two well-separated clouds:
  // cloud 0 at x in [0, 4], cloud 1 at x in [100, 104].
  let pts : Array[(Double, Double)] = []
  let mut st = 12345
  for i = 0; i < 30; i = i + 1 {
    st = (st * 1103515245 + 12345) & 0x7FFFFFFF
    pts.push(((st % 5).to_double(), 0.0))
  }
  for i = 0; i < 30; i = i + 1 {
    st = (st * 1103515245 + 12345) & 0x7FFFFFFF
    pts.push((100.0 + (st % 5).to_double(), 0.0))
  }
  let r = kmeans(pts, 2, 100)
  assert_eq(r.centroids.length(), 2)
  assert_eq(r.assignments.length(), 60)
  let g0 = r.assignments[0]
  let g1 = r.assignments[30]
  assert_true(g0 != g1) // the two clouds land in different clusters
  let mut same0 = 0
  let mut same1 = 0
  for i = 0; i < 30; i = i + 1 {
    if r.assignments[i] == g0 {
      same0 = same0 + 1
    }
  }
  for i = 30; i < 60; i = i + 1 {
    if r.assignments[i] == g1 {
      same1 = same1 + 1
    }
  }
  assert_eq(same0, 30)
  assert_eq(same1, 30)
}
