/// K-Means clustering for arbitrary-dimensional points.
///
/// Uses k-means++ seeding and Lloyd refinement. Points are represented as
/// `Array[Double]` vectors of arbitrary dimension. All points must share the
/// same dimensionality; mixed dimensions cause a runtime error.
///
/// Not formally verified. Correctness ensured by comprehensive tests.

// ---------------------------------------------------------------------------
// Internal LCG (delegates to @utils.lcg_next)
// ---------------------------------------------------------------------------

let km_default_seed : Int = 0x1A2B3C4D

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
// Geometry helpers
// ---------------------------------------------------------------------------

/// Squared Euclidean distance between two d-dimensional points.
fn sq_dist(a : Array[Double], b : Array[Double]) -> Double {
  let d = a.length()
  let mut sum = 0.0
  for i = 0; i < d; i = i + 1 {
    let diff = a[i] - b[i]
    sum = sum + diff * diff
  }
  sum
}

// ---------------------------------------------------------------------------
// Result type
// ---------------------------------------------------------------------------

pub struct KMeansResult {
  centroids : Array[Array[Double]]
  assignments : Array[Int]
}

// ---------------------------------------------------------------------------
// k-means++ initialisation
// ---------------------------------------------------------------------------

fn kmeans_pp_init(
  points : Array[Array[Double]],
  k : Int,
  rng : Rng,
) -> Array[Array[Double]] {
  let n = points.length()
  let centroids : Array[Array[Double]] = []
  let min_sq = FixedArray::make(n, 0.0)
  let first = rng.next() % n
  centroids.push(points[first])
  for i = 0; i < n; i = i + 1 {
    min_sq[i] = sq_dist(points[i], points[first])
  }
  for c = 1; c < k; c = c + 1 {
    let mut total = 0.0
    for i = 0; i < n; i = i + 1 {
      total = total + min_sq[i]
    }
    if total <= 0.0 {
      centroids.push(points[c])
      continue
    }
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

fn assign_all(
  points : Array[Array[Double]],
  centroids : Array[Array[Double]],
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

fn recompute(
  points : Array[Array[Double]],
  assignments : Array[Int],
  prev_centroids : Array[Array[Double]],
) -> Array[Array[Double]] {
  let n = points.length()
  let k = prev_centroids.length()
  let d = if n > 0 { points[0].length() } else { 0 }
  let sums : Array[Array[Double]] = Array::makei(k, fn(_i) { Array::make(d, 0.0) })
  let counts = Array::make(k, 0)
  for i = 0; i < n; i = i + 1 {
    let c = assignments[i]
    counts[c] = counts[c] + 1
    for j = 0; j < d; j = j + 1 {
      sums[c][j] = sums[c][j] + points[i][j]
    }
  }
  let centroids : Array[Array[Double]] = Array::makei(k, fn(_i) { Array::make(d, 0.0) })
  for c = 0; c < k; c = c + 1 {
    if counts[c] > 0 {
      let cnt = counts[c].to_double()
      for j = 0; j < d; j = j + 1 {
        centroids[c][j] = sums[c][j] / cnt
      }
    } else {
      centroids[c] = Array::make(d, 0.0)
      for j = 0; j < d; j = j + 1 {
        centroids[c][j] = prev_centroids[c][j]
      }
    }
  }
  reseed_empty(points, centroids, counts, assignments)
  centroids
}

fn reseed_empty(
  points : Array[Array[Double]],
  centroids : Array[Array[Double]],
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
        let d = sq_dist(points[i], centroids[assignments[i]])
        if d > best_d {
          best_d = d
          best_idx = i
        }
      }
    }
    if best_idx >= 0 {
      centroids[c] = Array::make(points[best_idx].length(), 0.0)
      for j = 0; j < points[best_idx].length(); j = j + 1 {
        centroids[c][j] = points[best_idx][j]
      }
      used[best_idx] = true
    }
  }
}

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
// Public API
// ---------------------------------------------------------------------------

/// Cluster `points` into `k` groups using k-means++ and Lloyd iteration.
///
/// Points are arbitrary-dimensional vectors (`Array[Double]`). All points must
/// have the same dimensionality.
pub fn kmeans(
  points : Array[Array[Double]],
  k : Int,
  max_iters : Int,
) -> KMeansResult {
  kmeans_with_seed(points, k, max_iters, km_default_seed)
}

/// K-means with a user-specified PRNG seed for reproducible independent runs.
pub fn kmeans_with_seed(
  points : Array[Array[Double]],
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
// Helpers for 2-D convenience
// ---------------------------------------------------------------------------

/// Helper to create a 2-D point from a tuple.
pub fn point2d(x : Double, y : Double) -> Array[Double] {
  [x, y]
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

fn approx_eq(a : Double, b : Double) -> Bool {
  let diff = (a - b).abs()
  diff < 1.0e-6 || diff < 1.0e-6 * (a.abs() + b.abs())
}

fn centroid_index_near(
  centroids : Array[Array[Double]],
  coords : Array[Double],
) -> Int {
  for i = 0; i < centroids.length(); i = i + 1 {
    let mut ok = true
    for j = 0; j < coords.length(); j = j + 1 {
      if !approx_eq(centroids[i][j], coords[j]) {
        ok = false
        break
      }
    }
    if ok {
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
  let r = kmeans([[5.0, 5.0]], 1, 10)
  assert_eq(r.centroids.length(), 1)
  assert_eq(r.assignments.length(), 1)
  assert_eq(r.assignments[0], 0)
  assert_true(approx_eq(r.centroids[0][0], 5.0))
  assert_true(approx_eq(r.centroids[0][1], 5.0))
}

///|
test "kmeans: k greater than n is clamped to n" {
  let pts = [[0.0, 0.0], [10.0, 10.0], [20.0, 20.0]]
  let r = kmeans(pts, 10, 10)
  assert_eq(r.centroids.length(), 3)
  assert_eq(r.assignments.length(), 3)
  let seen = [false, false, false]
  for i = 0; i < 3; i = i + 1 {
    let c = r.assignments[i]
    assert_true(c >= 0 && c < 3)
    assert_false(seen[c])
    seen[c] = true
  }
  assert_true(centroid_index_near(r.centroids, [0.0, 0.0]) >= 0)
  assert_true(centroid_index_near(r.centroids, [10.0, 10.0]) >= 0)
  assert_true(centroid_index_near(r.centroids, [20.0, 20.0]) >= 0)
}

///|
test "kmeans: two well-separated clusters 2D" {
  let pts = [
    [0.0, 0.0], [0.0, 1.0], [1.0, 0.0], [1.0, 1.0],
    [10.0, 10.0], [10.0, 11.0], [11.0, 10.0], [11.0, 11.0],
  ]
  let r = kmeans(pts, 2, 100)
  assert_eq(r.centroids.length(), 2)
  let g0 = r.assignments[0]
  for i = 0; i < 4; i = i + 1 {
    assert_eq(r.assignments[i], g0)
  }
  let g1 = r.assignments[4]
  for i = 4; i < 8; i = i + 1 {
    assert_eq(r.assignments[i], g1)
  }
  assert_true(g0 != g1)
  assert_true(centroid_index_near(r.centroids, [0.5, 0.5]) >= 0)
  assert_true(centroid_index_near(r.centroids, [10.5, 10.5]) >= 0)
}

///|
test "kmeans: three clusters 3D" {
  let pts : Array[Array[Double]] = []
  let centres = [[0.0, 0.0, 0.0], [20.0, 0.0, 0.0], [10.0, 20.0, 10.0]]
  for ci = 0; ci < 3; ci = ci + 1 {
    for di = 0; di < 4; di = di + 1 {
      let p = Array::make(3, 0.0)
      p[0] = centres[ci][0] + (di % 2).to_double()
      p[1] = centres[ci][1] + (di / 2).to_double()
      p[2] = centres[ci][2]
      pts.push(p)
    }
  }
  let r = kmeans(pts, 3, 100)
  assert_eq(r.centroids.length(), 3)
  let groups = [r.assignments[0], r.assignments[4], r.assignments[8]]
  assert_true(groups[0] != groups[1])
  assert_true(groups[1] != groups[2])
  assert_true(groups[0] != groups[2])
}

///|
test "kmeans: identical points collapse to one centroid" {
  let pts = [[7.0, 7.0], [7.0, 7.0], [7.0, 7.0]]
  let r = kmeans(pts, 1, 10)
  assert_eq(r.centroids.length(), 1)
  assert_true(approx_eq(r.centroids[0][0], 7.0))
  assert_true(approx_eq(r.centroids[0][1], 7.0))
  for i = 0; i < 3; i = i + 1 {
    assert_eq(r.assignments[i], 0)
  }
}

///|
test "kmeans: k <= 0 treated as one cluster" {
  let pts = [[0.0, 0.0], [10.0, 0.0], [20.0, 0.0]]
  let r = kmeans(pts, 0, 10)
  assert_eq(r.centroids.length(), 1)
  assert_eq(r.assignments.length(), 3)
  for i = 0; i < 3; i = i + 1 {
    assert_eq(r.assignments[i], 0)
  }
  assert_true(approx_eq(r.centroids[0][0], 10.0))
  assert_true(approx_eq(r.centroids[0][1], 0.0))
}

///|
test "kmeans: max_iters = 0 returns a consistent assignment" {
  let pts = [[0.0, 0.0], [1.0, 1.0], [10.0, 10.0], [11.0, 11.0]]
  let r = kmeans(pts, 2, 0)
  assert_eq(r.centroids.length(), 2)
  assert_eq(r.assignments.length(), 4)
  for i = 0; i < 4; i = i + 1 {
    assert_true(r.assignments[i] >= 0 && r.assignments[i] < 2)
  }
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
  let pts : Array[Array[Double]] = []
  for i = 0; i < 8; i = i + 1 {
    pts.push([i.to_double(), 0.0])
  }
  for i = 0; i < 8; i = i + 1 {
    pts.push([100.0 + i.to_double(), 0.0])
  }
  let r = kmeans(pts, 2, 100)
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
  let pts : Array[Array[Double]] = []
  let mut st = 12345
  for i = 0; i < 30; i = i + 1 {
    st = (st * 1103515245 + 12345) & 0x7FFFFFFF
    pts.push([(st % 5).to_double(), 0.0])
  }
  for i = 0; i < 30; i = i + 1 {
    st = (st * 1103515245 + 12345) & 0x7FFFFFFF
    pts.push([100.0 + (st % 5).to_double(), 0.0])
  }
  let r = kmeans(pts, 2, 100)
  assert_eq(r.centroids.length(), 2)
  assert_eq(r.assignments.length(), 60)
  let g0 = r.assignments[0]
  let g1 = r.assignments[30]
  assert_true(g0 != g1)
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

///|
test "kmeans: 1-D points" {
  let pts = [[0.0], [1.0], [2.0], [10.0], [11.0], [12.0]]
  let r = kmeans(pts, 2, 100)
  assert_eq(r.centroids.length(), 2)
  let g0 = r.assignments[0]
  let g1 = r.assignments[3]
  assert_true(g0 != g1)
  for i = 0; i < 3; i = i + 1 {
    assert_eq(r.assignments[i], g0)
  }
  for i = 3; i < 6; i = i + 1 {
    assert_eq(r.assignments[i], g1)
  }
}
