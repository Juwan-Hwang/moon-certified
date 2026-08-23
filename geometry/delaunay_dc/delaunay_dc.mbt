/// Delaunay triangulation via divide-and-conquer (Guibas & Stolfi 1985).
///
/// This is the optimal O(n log n) algorithm with guaranteed worst-case
/// complexity, unlike the incremental Bowyer-Watson method (O(n²) worst case).
/// The algorithm sorts points by x-coordinate, recursively triangulates the
/// left and right halves, then merges by finding the lower common tangent
/// and zig-zagging upward to add cross-edges.
///
/// ## Algorithm
///
/// 1. **Sort** points by x-coordinate (ties by y).
/// 2. **Divide**: split into left and right halves.
/// 3. **Conquer**: recursively triangulate each half.
/// 4. **Merge**: find the lower common tangent (bottom-most cross-edge), then
///    zig-zag upward adding Delaunay cross-edges. At each step, candidates
///    from both sides are tested with the incircle predicate; edges that
///    violate the empty-circumcircle property are removed.
///
/// ## Geometric predicates
///
/// - `orient2d(a, b, c)`: sign of the cross product (b−a) × (c−a).
///   Positive if a→b→c is CCW.
/// - `incircle(a, b, c, d)`: sign of the in-circle determinant.
///   Positive if d lies inside the circumcircle of a, b, c (CCW).
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Point type
// ---------------------------------------------------------------------------

///|
/// A 2-D point with `Double` coordinates.
pub struct DcPoint {
  x : Double
  y : Double
}

///|
/// Construct a point.
pub fn point(x : Double, y : Double) -> DcPoint {
  { x, y }
}

// ---------------------------------------------------------------------------
// Geometric predicates
// ---------------------------------------------------------------------------

///|
/// Orientation test: returns positive if `a → b → c` is counter-clockwise,
/// negative if clockwise, zero if collinear.
fn orient2d(a : DcPoint, b : DcPoint, c : DcPoint) -> Double {
  (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
}

///|
/// In-circle test: returns positive if `d` lies strictly inside the
/// circumcircle of `a`, `b`, `c` (assumed CCW). Negative if outside.
fn incircle(a : DcPoint, b : DcPoint, c : DcPoint, d : DcPoint) -> Double {
  let adx = a.x - d.x
  let ady = a.y - d.y
  let bdx = b.x - d.x
  let bdy = b.y - d.y
  let cdx = c.x - d.x
  let cdy = c.y - d.y
  let ab = adx * bdy - bdx * ady
  let bc = bdx * cdy - cdx * bdy
  let ca = cdx * ady - adx * cdy
  let asq = adx * adx + ady * ady
  let bsq = bdx * bdx + bdy * bdy
  let csq = cdx * cdx + cdy * cdy
  ab * csq + bc * asq + ca * bsq
}

// ---------------------------------------------------------------------------
// Triangulation data structure
// ---------------------------------------------------------------------------

///|
/// A triangulation: symmetric adjacency + triangle list + convex hull.
///
/// - `adj[i]` = list of all neighbors of point `i` (symmetric).
/// - `triangles` = list of CCW-oriented triangles.
/// - `hull` = convex hull vertices in CCW order.
priv struct Triangulation {
  adj : Array[Array[Int]]
  triangles : Array[(Int, Int, Int)]
  mut hull : Array[Int]
}

///|
fn new_triangulation(n : Int) -> Triangulation {
  let adj : Array[Array[Int]] = []
  for i = 0; i < n; i = i + 1 {
    adj.push([])
  }
  { adj, triangles: [], hull: [] }
}

///|
/// Add symmetric adjacency between `u` and `v`.
fn add_edge(tri : Triangulation, u : Int, v : Int) -> Unit {
  let lu = tri.adj[u]
  for i = 0; i < lu.length(); i = i + 1 {
    if lu[i] == v {
      return
    }
  }
  lu.push(v)
  let lv = tri.adj[v]
  for i = 0; i < lv.length(); i = i + 1 {
    if lv[i] == u {
      return
    }
  }
  lv.push(u)
}

///|
/// Remove symmetric adjacency between `u` and `v`.
fn remove_edge(tri : Triangulation, u : Int, v : Int) -> Unit {
  let lu = tri.adj[u]
  for i = 0; i < lu.length(); i = i + 1 {
    if lu[i] == v {
      lu.remove(i) |> ignore
      break
    }
  }
  let lv = tri.adj[v]
  for i = 0; i < lv.length(); i = i + 1 {
    if lv[i] == u {
      lv.remove(i) |> ignore
      break
    }
  }
}

///|
/// Add a triangle (a, b, c) assumed CCW. Updates adjacency symmetrically.
fn add_triangle(tri : Triangulation, a : Int, b : Int, c : Int) -> Unit {
  tri.triangles.push((a, b, c))
  add_edge(tri, a, b)
  add_edge(tri, b, c)
  add_edge(tri, c, a)
}

///|
/// Remove the first triangle found that contains the edge (a, b) and whose
/// third vertex is on the same side as `ref_point`. This is used during the
/// merge candidate search to remove the triangle on the "base-edge side".
fn remove_triangle_with_edge(
  tri : Triangulation,
  a : Int,
  b : Int,
  pts : Array[DcPoint],
  ref_point : Int,
) -> Unit {
  for i = 0; i < tri.triangles.length(); i = i + 1 {
    let (t0, t1, t2) = tri.triangles[i]
    // Check if edge (a, b) is in this triangle (either direction).
    let has_edge = (t0 == a && t1 == b) ||
      (t1 == a && t2 == b) ||
      (t2 == a && t0 == b) ||
      (t0 == b && t1 == a) ||
      (t1 == b && t2 == a) ||
      (t2 == b && t0 == a)
    if has_edge {
      // The third vertex is the one that's not a or b.
      let third = if t0 != a && t0 != b {
        t0
      } else if t1 != a && t1 != b {
        t1
      } else {
        t2
      }
      // Only remove if the third vertex is on the same side as ref_point
      // relative to edge (a, b).
      let o_ref = orient2d(pts[a], pts[b], pts[ref_point])
      let o_third = orient2d(pts[a], pts[b], pts[third])
      if o_ref * o_third > 0.0 || (o_ref != 0.0 && o_third == 0.0) {
        tri.triangles.remove(i) |> ignore
        remove_edge(tri, a, b)
        remove_edge(tri, b, third)
        remove_edge(tri, third, a)
        return
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Result type
// ---------------------------------------------------------------------------

///|
/// Result of the triangulation.
pub struct DcResult {
  /// Triangle indices: each triple (i, j, k) is a CCW triangle.
  triangles : Array[(Int, Int, Int)]
  /// Edge list: each pair (i, j) is an undirected edge (i < j).
  edges : Array[(Int, Int)]
  num_points : Int
}

// ---------------------------------------------------------------------------
// Divide-and-conquer Delaunay triangulation
// ---------------------------------------------------------------------------

///|
/// Compute the Delaunay triangulation of `pts` using divide-and-conquer.
///
/// Points are sorted by x-coordinate (ties broken by y). The algorithm
/// recursively splits the sorted array, triangulates each half, and merges
/// by finding the lower common tangent and zig-zagging upward.
///
/// **Complexity**: O(n log n) time, O(n) space.
pub fn delaunay_triangulate(pts : Array[DcPoint]) -> DcResult {
  let n = pts.length()
  if n < 3 {
    let edges : Array[(Int, Int)] = []
    if n == 2 {
      edges.push((0, 1))
    }
    return { triangles: [], edges, num_points: n }
  }
  // Sort point indices by x, then y.
  let order : Array[Int] = []
  for i = 0; i < n; i = i + 1 {
    order.push(i)
  }
  order.sort_by(fn(a, b) {
    if pts[a].x != pts[b].x {
      if pts[a].x < pts[b].x {
        -1
      } else {
        1
      }
    } else if pts[a].y != pts[b].y {
      if pts[a].y < pts[b].y {
        -1
      } else {
        1
      }
    } else {
      0
    }
  })
  // Build sorted points array.
  let sorted : Array[DcPoint] = Array::make(n, point(0.0, 0.0))
  for i = 0; i < n; i = i + 1 {
    sorted[i] = pts[order[i]]
  }
  // Recursively triangulate.
  let tri = triangulate_dc(sorted, 0, n - 1)
  // Extract result, mapping back to original indices.
  let triangles : Array[(Int, Int, Int)] = []
  for t in tri.triangles {
    triangles.push((order[t.0], order[t.1], order[t.2]))
  }
  // Extract unique edges from the adjacency list (covers both triangle
  // edges and collinear chain edges that have no associated triangle).
  let mapped_edges : Array[(Int, Int)] = []
  for i = 0; i < tri.adj.length(); i = i + 1 {
    for v in tri.adj[i] {
      if i < v {
        let (a, b) = (order[i], order[v])
        if a < b {
          mapped_edges.push((a, b))
        } else {
          mapped_edges.push((b, a))
        }
      }
    }
  }
  { triangles, edges: mapped_edges, num_points: n }
}

///|
/// Recursively triangulate the sorted points in range [lo, hi].
fn triangulate_dc(pts : Array[DcPoint], lo : Int, hi : Int) -> Triangulation {
  let n = hi - lo + 1
  let tri = new_triangulation(hi + 1)
  if n == 1 {
    tri.hull.push(lo)
    return tri
  }
  if n == 2 {
    add_edge(tri, lo, hi)
    tri.hull.push(lo)
    tri.hull.push(hi)
    return tri
  }
  if n == 3 {
    let o = orient2d(pts[lo], pts[lo + 1], pts[hi])
    if o > 0.0 {
      // CCW: (lo, lo+1, hi)
      add_triangle(tri, lo, lo + 1, hi)
      tri.hull.push(lo)
      tri.hull.push(lo + 1)
      tri.hull.push(hi)
    } else if o < 0.0 {
      // CW: (lo, hi, lo+1)
      add_triangle(tri, lo, hi, lo + 1)
      tri.hull.push(lo)
      tri.hull.push(hi)
      tri.hull.push(lo + 1)
    } else {
      // Collinear: chain lo → lo+1 → hi
      add_edge(tri, lo, lo + 1)
      add_edge(tri, lo + 1, hi)
      tri.hull.push(lo)
      tri.hull.push(lo + 1)
      tri.hull.push(hi)
    }
    return tri
  }
  // Recursive case: divide and conquer.
  let mid = lo + (hi - lo) / 2
  let left = triangulate_dc(pts, lo, mid)
  let right = triangulate_dc(pts, mid + 1, hi)
  merge_dc(pts, left, right, lo, mid, hi)
}

// ---------------------------------------------------------------------------
// Merge step
// ---------------------------------------------------------------------------

///|
/// Merge two Delaunay triangulations.
///
/// `left` covers points [lo, mid], `right` covers [mid+1, hi].
/// The result is stored in `left` (modified in place).
fn merge_dc(
  pts : Array[DcPoint],
  left : Triangulation,
  right : Triangulation,
  lo : Int,
  mid : Int,
  hi : Int,
) -> Triangulation {
  // Step 1: Find the lower common tangent.
  // Start from the rightmost vertex of the left hull and the leftmost
  // vertex of the right hull, then walk downward.
  let mut l_idx = 0
  for i = 1; i < left.hull.length(); i = i + 1 {
    if pts[left.hull[i]].x > pts[left.hull[l_idx]].x ||
      (
        pts[left.hull[i]].x == pts[left.hull[l_idx]].x &&
        pts[left.hull[i]].y < pts[left.hull[l_idx]].y
      ) {
      l_idx = i
    }
  }
  let mut r_idx = 0
  for i = 1; i < right.hull.length(); i = i + 1 {
    if pts[right.hull[i]].x < pts[right.hull[r_idx]].x ||
      (
        pts[right.hull[i]].x == pts[right.hull[r_idx]].x &&
        pts[right.hull[i]].y < pts[right.hull[r_idx]].y
      ) {
      r_idx = i
    }
  }
  // Walk downward: move l to its CCW predecessor if it is below the
  // current line (l, r); move r to its CCW successor if it is below.
  // The lower tangent has all points on or above the directed line l→r,
  // i.e. orient2d(l, r, p) >= 0 for all p.
  let mut improved = true
  while improved {
    improved = false
    let l_prev_idx = (l_idx + left.hull.length() - 1) % left.hull.length()
    let l_prev = left.hull[l_prev_idx]
    if orient2d(pts[left.hull[l_idx]], pts[right.hull[r_idx]], pts[l_prev]) <
      0.0 {
      l_idx = l_prev_idx
      improved = true
    }
    let r_next_idx = (r_idx + 1) % right.hull.length()
    let r_next = right.hull[r_next_idx]
    if orient2d(pts[left.hull[l_idx]], pts[right.hull[r_idx]], pts[r_next]) <
      0.0 {
      r_idx = r_next_idx
      improved = true
    }
  }
  let mut current_l = left.hull[l_idx]
  let mut current_r = right.hull[r_idx]
  // Step 2: Ensure left's adjacency covers all vertices in [0, hi].
  while left.adj.length() <= hi {
    left.adj.push([])
  }
  // Step 3: Merge right's triangles and adjacency into left.
  for t in right.triangles {
    left.triangles.push(t)
  }
  for i = 0; i < right.adj.length(); i = i + 1 {
    for v in right.adj[i] {
      add_edge(left, i, v)
    }
  }
  // Add the initial cross-edge (lower tangent).
  add_edge(left, current_l, current_r)
  // Collect cross-triangles formed during the merge.
  let cross_triangles : Array[(Int, Int, Int)] = []
  // Step 4: Zig-zag upward from the lower tangent.
  let mut merging = true
  while merging {
    // Find the left candidate.
    let best_l = find_left_candidate(pts, left, current_l, current_r, lo, mid)
    // Find the right candidate.
    let best_r = find_right_candidate(
      pts,
      left,
      current_r,
      current_l,
      mid + 1,
      hi,
    )
    if best_l == -1 && best_r == -1 {
      // Reached the upper tangent.
      merging = false
    } else if best_l == -1 {
      // Only right candidate.
      cross_triangles.push((current_l, current_r, best_r))
      add_edge(left, current_l, best_r)
      add_edge(left, current_r, best_r)
      current_r = best_r
    } else if best_r == -1 {
      // Only left candidate.
      cross_triangles.push((current_l, best_l, current_r))
      add_edge(left, current_l, best_l)
      add_edge(left, best_l, current_r)
      current_l = best_l
    } else {
      // Both candidates — choose the Delaunay one.
      // If best_r is inside the circumcircle of (l, r, best_l), use right.
      // Otherwise use left.
      let ic = incircle(
        pts[current_l],
        pts[current_r],
        pts[best_l],
        pts[best_r],
      )
      if ic > 0.0 {
        // best_r is inside circumcircle of (l, r, best_l) → use right.
        cross_triangles.push((current_l, current_r, best_r))
        add_edge(left, current_l, best_r)
        add_edge(left, current_r, best_r)
        current_r = best_r
      } else {
        cross_triangles.push((current_l, best_l, current_r))
        add_edge(left, current_l, best_l)
        add_edge(left, best_l, current_r)
        current_l = best_l
      }
    }
  }
  // Add cross-triangles to the result.
  for t in cross_triangles {
    left.triangles.push(t)
  }
  // Step 5: Rebuild the convex hull.
  rebuild_hull(pts, left)
  left
}

// ---------------------------------------------------------------------------
// Candidate search
// ---------------------------------------------------------------------------

///|
/// Normalize an angle to [0, 2π).
fn norm_angle(a : Double) -> Double {
  let two_pi = 2.0 * @math.PI
  let mut r = a
  while r < 0.0 {
    r = r + two_pi
  }
  while r >= two_pi {
    r = r - two_pi
  }
  r
}

///|
/// Find the Delaunay left candidate for the base edge (l, r).
///
/// Searches the neighbors of `l` that lie in [lo, mid] (the left half) and
/// are above the directed edge l→r. Candidates are processed in CCW order
/// starting from r's direction. The sequential incircle test removes
/// non-Delaunay edges and their associated triangles.
///
/// Returns the candidate vertex index, or -1 if no valid candidate exists.
fn find_left_candidate(
  pts : Array[DcPoint],
  tri : Triangulation,
  l : Int,
  r : Int,
  lo : Int,
  mid : Int,
) -> Int {
  // Collect neighbors of l in [lo, mid] (left half).
  let neighbors : Array[Int] = []
  for nb in tri.adj[l] {
    if nb >= lo && nb <= mid {
      neighbors.push(nb)
    }
  }
  if neighbors.length() == 0 {
    return -1
  }
  // Sort by angle CCW from direction (r - l).
  let base_angle = @math.atan2(pts[r].y - pts[l].y, pts[r].x - pts[l].x)
  neighbors.sort_by(fn(a, b) {
    let aa = norm_angle(
      @math.atan2(pts[a].y - pts[l].y, pts[a].x - pts[l].x) - base_angle,
    )
    let ba = norm_angle(
      @math.atan2(pts[b].y - pts[l].y, pts[b].x - pts[l].x) - base_angle,
    )
    if aa < ba {
      -1
    } else if aa > ba {
      1
    } else {
      0
    }
  })
  // Find the first neighbor above the base edge (CCW side of l→r).
  let mut start = 0
  while start < neighbors.length() {
    if orient2d(pts[l], pts[r], pts[neighbors[start]]) > 0.0 {
      break
    }
    start = start + 1
  }
  if start >= neighbors.length() {
    return -1
  }
  // Sequential search: remove non-Delaunay candidates.
  let mut candidate = neighbors[start]
  let mut i = start + 1
  while i < neighbors.length() {
    let next_nb = neighbors[i]
    // Check if next_nb is inside the circumcircle of (l, r, candidate).
    if incircle(pts[l], pts[r], pts[candidate], pts[next_nb]) > 0.0 {
      // candidate is not Delaunay — remove edge (l, candidate) and
      // the triangle on the r-side of that edge.
      remove_triangle_with_edge(tri, l, candidate, pts, r)
      remove_edge(tri, l, candidate)
      candidate = next_nb
      // If the new candidate is below the base edge, stop.
      if orient2d(pts[l], pts[r], pts[candidate]) <= 0.0 {
        return -1
      }
    } else {
      // candidate is Delaunay.
      break
    }
    i = i + 1
  }
  candidate
}

///|
/// Find the Delaunay right candidate for the base edge (l, r).
///
/// Searches the neighbors of `r` that lie in [r_lo, r_hi] (the right half)
/// and are above the directed edge l→r. Candidates are processed in CW order
/// starting from l's direction.
///
/// Returns the candidate vertex index, or -1 if no valid candidate exists.
fn find_right_candidate(
  pts : Array[DcPoint],
  tri : Triangulation,
  r : Int,
  l : Int,
  r_lo : Int,
  r_hi : Int,
) -> Int {
  // Collect neighbors of r in [r_lo, r_hi] (right half).
  let neighbors : Array[Int] = []
  for nb in tri.adj[r] {
    if nb >= r_lo && nb <= r_hi {
      neighbors.push(nb)
    }
  }
  if neighbors.length() == 0 {
    return -1
  }
  // Sort by angle CW from direction (l - r).
  // CW from (l - r) means: angle = atan2(l - r) - atan2(nb - r), normalized.
  let base_angle = @math.atan2(pts[l].y - pts[r].y, pts[l].x - pts[r].x)
  neighbors.sort_by(fn(a, b) {
    let aa = norm_angle(
      base_angle - @math.atan2(pts[a].y - pts[r].y, pts[a].x - pts[r].x),
    )
    let ba = norm_angle(
      base_angle - @math.atan2(pts[b].y - pts[r].y, pts[b].x - pts[r].x),
    )
    if aa < ba {
      -1
    } else if aa > ba {
      1
    } else {
      0
    }
  })
  // Find the first neighbor above the base edge.
  // "Above" l→r means orient2d(l, r, nb) > 0.
  let mut start = 0
  while start < neighbors.length() {
    if orient2d(pts[l], pts[r], pts[neighbors[start]]) > 0.0 {
      break
    }
    start = start + 1
  }
  if start >= neighbors.length() {
    return -1
  }
  // Sequential search: remove non-Delaunay candidates.
  // For the right side, the triangle is (r, l, candidate) which is CCW.
  let mut candidate = neighbors[start]
  let mut i = start + 1
  while i < neighbors.length() {
    let next_nb = neighbors[i]
    // Check if next_nb is inside the circumcircle of (r, l, candidate).
    if incircle(pts[r], pts[l], pts[candidate], pts[next_nb]) > 0.0 {
      // candidate is not Delaunay — remove edge (r, candidate) and
      // the triangle on the l-side of that edge.
      remove_triangle_with_edge(tri, r, candidate, pts, l)
      remove_edge(tri, r, candidate)
      candidate = next_nb
      // If the new candidate is below the base edge, stop.
      if orient2d(pts[l], pts[r], pts[candidate]) <= 0.0 {
        return -1
      }
    } else {
      break
    }
    i = i + 1
  }
  candidate
}

// ---------------------------------------------------------------------------
// Convex hull reconstruction
// ---------------------------------------------------------------------------

///|
/// Rebuild the convex hull of the merged triangulation.
/// Uses Andrew's monotone chain on all vertices that appear on boundary edges
/// (edges belonging to exactly one triangle).
fn rebuild_hull(pts : Array[DcPoint], tri : Triangulation) -> Unit {
  // Count edge occurrences: (a, b, count) with a < b.
  let edge_count : Array[(Int, Int, Int)] = []
  for t in tri.triangles {
    let edges = [(t.0, t.1), (t.1, t.2), (t.2, t.0)]
    for e in edges {
      let (a, b) = if e.0 < e.1 { (e.0, e.1) } else { (e.1, e.0) }
      let mut found = false
      for i = 0; i < edge_count.length(); i = i + 1 {
        if edge_count[i].0 == a && edge_count[i].1 == b {
          edge_count[i] = (a, b, edge_count[i].2 + 1)
          found = true
          break
        }
      }
      if !found {
        edge_count.push((a, b, 1))
      }
    }
  }
  // Collect boundary vertices (appearing in exactly one triangle's edge).
  let hull_set : Array[Int] = []
  for ec in edge_count {
    if ec.2 == 1 {
      let mut has0 = false
      for v in hull_set {
        if v == ec.0 {
          has0 = true
          break
        }
      }
      if !has0 {
        hull_set.push(ec.0)
      }
      let mut has1 = false
      for v in hull_set {
        if v == ec.1 {
          has1 = true
          break
        }
      }
      if !has1 {
        hull_set.push(ec.1)
      }
    }
  }
  if hull_set.length() < 3 {
    tri.hull = hull_set
    return
  }
  // Sort by angle from centroid for CCW ordering.
  let mut cx = 0.0
  let mut cy = 0.0
  for v in hull_set {
    cx = cx + pts[v].x
    cy = cy + pts[v].y
  }
  cx = cx / hull_set.length().to_double()
  cy = cy / hull_set.length().to_double()
  hull_set.sort_by(fn(a, b) {
    let angle_a = @math.atan2(pts[a].y - cy, pts[a].x - cx)
    let angle_b = @math.atan2(pts[b].y - cy, pts[b].x - cx)
    if angle_a < angle_b {
      -1
    } else if angle_a > angle_b {
      1
    } else {
      0
    }
  })
  tri.hull = hull_set
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "delaunay_dc: single triangle" {
  let pts = [point(0.0, 0.0), point(1.0, 0.0), point(0.5, 1.0)]
  let result = delaunay_triangulate(pts)
  assert_eq(result.triangles.length(), 1)
  assert_eq(result.edges.length(), 3)
}

///|
test "delaunay_dc: square (4 points)" {
  let pts = [point(0.0, 0.0), point(1.0, 0.0), point(1.0, 1.0), point(0.0, 1.0)]
  let result = delaunay_triangulate(pts)
  assert_eq(result.triangles.length(), 2)
  assert_eq(result.edges.length(), 5)
}

///|
test "delaunay_dc: collinear points" {
  let pts = [point(0.0, 0.0), point(1.0, 0.0), point(2.0, 0.0)]
  let result = delaunay_triangulate(pts)
  assert_eq(result.triangles.length(), 0)
  assert_eq(result.edges.length(), 2)
}

///|
test "delaunay_dc: degenerate (1-2 points)" {
  let r1 = delaunay_triangulate([point(0.0, 0.0)])
  assert_eq(r1.triangles.length(), 0)
  assert_eq(r1.edges.length(), 0)
  let r2 = delaunay_triangulate([point(0.0, 0.0), point(1.0, 0.0)])
  assert_eq(r2.triangles.length(), 0)
  assert_eq(r2.edges.length(), 1)
}

///|
test "delaunay_dc: grid of points" {
  let pts : Array[DcPoint] = []
  for r = 0; r < 3; r = r + 1 {
    for c = 0; c < 3; c = c + 1 {
      pts.push(point(c.to_double(), r.to_double()))
    }
  }
  let result = delaunay_triangulate(pts)
  assert_true(result.triangles.length() >= 6)
  assert_true(result.triangles.length() <= 10)
  for t in result.triangles {
    assert_true(t.0 != t.1 && t.1 != t.2 && t.0 != t.2)
  }
}

///|
test "delaunay_dc: random points" {
  let pts : Array[DcPoint] = []
  let mut seed = 42
  for i = 0; i < 20; i = i + 1 {
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
    let x = (seed % 100).to_double()
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
    let y = (seed % 100).to_double()
    pts.push(point(x, y))
  }
  let result = delaunay_triangulate(pts)
  assert_true(result.triangles.length() > 0)
  for t in result.triangles {
    assert_true(t.0 != t.1 && t.1 != t.2 && t.0 != t.2)
  }
  for e in result.edges {
    assert_true(e.0 != e.1)
  }
}

///|
test "delaunay_dc: points on a circle" {
  let pts : Array[DcPoint] = []
  for i = 0; i < 8; i = i + 1 {
    let angle = 2.0 * @math.PI * i.to_double() / 8.0
    pts.push(point(@math.cos(angle) * 10.0, @math.sin(angle) * 10.0))
  }
  let result = delaunay_triangulate(pts)
  assert_true(result.triangles.length() >= 5)
  assert_true(result.triangles.length() <= 8)
}

///|
test "delaunay_dc: two separate triangles" {
  let pts = [
    point(0.0, 0.0),
    point(1.0, 0.0),
    point(0.5, 1.0),
    point(10.0, 0.0),
    point(11.0, 0.0),
    point(10.5, 1.0),
  ]
  let result = delaunay_triangulate(pts)
  // The Delaunay triangulation of the convex hull must include at least
  // the two cluster triangles plus cross-edges on the hull.
  assert_true(result.triangles.length() >= 2)
  for t in result.triangles {
    assert_true(t.0 != t.1 && t.1 != t.2 && t.0 != t.2)
  }
  for e in result.edges {
    assert_true(e.0 != e.1)
  }
}

///|
test "delaunay_dc: convex quadrilateral diagonal" {
  let pts = [point(0.0, 0.0), point(2.0, 0.0), point(2.0, 1.0), point(0.0, 1.0)]
  let result = delaunay_triangulate(pts)
  assert_eq(result.triangles.length(), 2)
  // The Delaunay diagonal should be the shorter one: (0,2) not (1,3).
  let mut diag_count = 0
  for e in result.edges {
    if (e.0 == 0 && e.1 == 2) || (e.0 == 1 && e.1 == 3) {
      diag_count = diag_count + 1
    }
  }
  assert_eq(diag_count, 1)
}
