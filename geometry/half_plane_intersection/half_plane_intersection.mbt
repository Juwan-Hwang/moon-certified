/// Half-plane intersection.
///
/// A half-plane is the region to the left of a directed line (from `p` to
/// `q`). Given a set of half-planes, this computes their intersection — a
/// convex polygon, possibly empty.
///
/// ## Algorithm
///
/// Sort-and-sweep with a double-ended queue (the "S&I" algorithm):
///
/// 1. Each half-plane is a directed line `p -> q`; the valid region is
///    `{ x : cross(q-p, x-p) >= -eps }` (left side, inclusive).
/// 2. Four large bounding-box half-planes are appended so that unbounded
///    intersections are clamped to a finite polygon instead of leaking
///    infinities.
/// 3. Sort half-planes by the polar angle of their direction vectors, using
///    a half-plane + cross-product comparator (no `atan2`, hence no
///    floating-point angle round-off in the ordering).
/// 4. Reduce parallel same-direction half-planes to the single most
///    restrictive one (the boundary line furthest in the inward-normal
///    direction, i.e. maximising `cross(dir, p)`). This also merges any
///    user half-plane with the coincident bounding-box edge.
/// 5. Sweep with a deque of half-planes and a parallel deque of
///    intersection points (one per adjacent pair). For each new half-plane
///    `h`, pop from either end any half-plane whose intersection point with
///    its neighbour falls strictly to the right of `h`. A parallel check
///    against the back detects the degenerate empty-strip case early.
/// 6. After the sweep, clean up the front against the back and vice versa.
///
/// ## Complexity
///
/// - O(n log n) for the sort; O(n) for the sweep.
/// - Space: O(n).
///
/// ## Numerical stability
///
/// All geometric comparisons use an epsilon (`1e-9`). Intersection points are
/// computed via the parametric line-intersection formula; a near-zero
/// denominator (parallel lines, which the bounding box prevents for bounded
/// inputs) yields a far sentinel point rather than `NaN`.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

///|
/// A 2D point with double-precision coordinates.
pub struct DPoint {
  x : Double
  y : Double
}

///|
/// Construct a [`DPoint`].
pub fn dpoint(x : Double, y : Double) -> DPoint {
  { x, y, }
}

///|
/// A half-plane: the region to the left of the directed line `p -> q`.
///
/// Concretely, a point `x` is in the half-plane iff
/// `cross(q - p, x - p) >= -eps`.
pub struct HalfPlane {
  p : DPoint
  q : DPoint
}

///|
/// Construct a [`HalfPlane`] — the region to the left of the directed line
/// `p -> q`.
pub fn half_plane(p : DPoint, q : DPoint) -> HalfPlane {
  { p, q, }
}

// ---------------------------------------------------------------------------
// Constants & vector arithmetic
// ---------------------------------------------------------------------------

///|
const EPS : Double = 1.0e-9

///|
/// Sign of `x` with epsilon tolerance: -1, 0, or 1.
fn sign(x : Double) -> Int {
  if x > EPS {
    1
  } else if x < -EPS {
    -1
  } else {
    0
  }
}

///|
/// 2D cross product of two free vectors.
fn cross_v(a : DPoint, b : DPoint) -> Double {
  a.x * b.y - a.y * b.x
}

///|
/// Dot product of two free vectors.
fn dot_v(a : DPoint, b : DPoint) -> Double {
  a.x * b.x + a.y * b.y
}

///|
/// Direction vector of a half-plane (`q - p`).
fn hp_dir(h : HalfPlane) -> DPoint {
  { x: h.q.x - h.p.x, y: h.q.y - h.p.y, }
}

///|
/// Signed cross of a half-plane's direction with the vector `x - h.p`.
/// Positive => `x` lies to the left of the directed line.
fn hp_cross(h : HalfPlane, x : DPoint) -> Double {
  let d = hp_dir(h)
  let dx = x.x - h.p.x
  let dy = x.y - h.p.y
  d.x * dy - d.y * dx
}

///|
/// Intersection point of the boundary lines of `a` and `b`.
///
/// Uses the parametric formula `a.p + t * dir(a)` where
/// `t = cross(b.p - a.p, dir(b)) / cross(dir(a), dir(b))`. A near-zero
/// denominator (parallel lines) yields a far sentinel point to avoid
/// division by zero; this case does not arise for bounded intersections
/// once the bounding box is in place.
fn hp_intersect(a : HalfPlane, b : HalfPlane) -> DPoint {
  let da = hp_dir(a)
  let db = hp_dir(b)
  let denom = cross_v(da, db)
  let mag = if denom < 0.0 { -denom } else { denom }
  if mag < 1.0e-12 {
    return { x: 1.0e15, y: 1.0e15, }
  }
  let t = cross_v({ x: b.p.x - a.p.x, y: b.p.y - a.p.y, }, db) / denom
  { x: a.p.x + t * da.x, y: a.p.y + t * da.y, }
}

// ---------------------------------------------------------------------------
// Angle comparator (no atan2)
// ---------------------------------------------------------------------------

///|
/// Half-plane index of a vector for polar sorting. Returns 0 for the upper
/// open half (y > 0, or y == 0 && x > 0), 1 for the lower half. This induces
/// a total order consistent with counterclockwise angle without calling any
/// trigonometric function.
fn half(v : DPoint) -> Int {
  if v.y > 0.0 || (v.y == 0.0 && v.x > 0.0) {
    0
  } else {
    1
  }
}

///|
/// Comparator: ascending polar angle (CCW) of the direction vectors.
/// Returns a negative value when `a` should precede `b`. Two vectors in the
/// same half are ordered by the sign of their cross product.
fn cmp_angle(a : HalfPlane, b : HalfPlane) -> Int {
  let da = hp_dir(a)
  let db = hp_dir(b)
  let ha = half(da)
  let hb = half(db)
  if ha != hb {
    return ha - hb
  }
  let c = cross_v(da, db)
  if c > 0.0 {
    -1
  } else if c < 0.0 {
    1
  } else {
    0
  }
}

///|
/// True iff `a` and `b` point in the same direction: parallel (cross ≈ 0)
/// and same orientation (dot > 0).
fn same_dir(a : HalfPlane, b : HalfPlane) -> Bool {
  sign(cross_v(hp_dir(a), hp_dir(b))) == 0 && dot_v(hp_dir(a), hp_dir(b)) > 0.0
}

// ---------------------------------------------------------------------------
// Main entry
// ---------------------------------------------------------------------------

///|
/// Compute the intersection of `half_planes` (a convex polygon).
///
/// Returns the polygon vertices in counterclockwise order. If the
/// intersection is empty, returns an empty array. Unbounded intersections
/// are clamped to a large bounding box (half-side `1e9`); callers that need
/// to detect unboundedness can check whether any vertex lies on the box
/// boundary (|x| or |y| near `1e9`).
pub fn intersect(half_planes : Array[HalfPlane]) -> Array[DPoint] {
  let n0 = half_planes.length()
  let lo = -1.0e9
  let hi = 1.0e9
  // Accumulate user half-planes plus a bounding box whose left sides form
  // the box interior. The four box edges are CCW directed lines.
  let hps : Array[HalfPlane] = []
  for i = 0; i < n0; i = i + 1 {
    hps.push(half_planes[i])
  }
  hps.push({ p: { x: lo, y: lo, }, q: { x: hi, y: lo, }, }) // bottom: y >= lo
  hps.push({ p: { x: hi, y: lo, }, q: { x: hi, y: hi, }, }) // right:  x <= hi
  hps.push({ p: { x: hi, y: hi, }, q: { x: lo, y: hi, }, }) // top:    y <= hi
  hps.push({ p: { x: lo, y: hi, }, q: { x: lo, y: lo, }, }) // left:   x >= lo
  hps.sort_by(cmp_angle)

  // Deduplicate parallel same-direction half-planes, keeping the single
  // most restrictive one. "Most restrictive" = the boundary line furthest
  // in the inward-normal direction, i.e. maximising `cross(dir, p)` (the
  // projection of `p` onto the left normal of `dir`).
  let uniq : Array[HalfPlane] = []
  let n = hps.length()
  let mut i = 0
  while i < n {
    let mut j = i + 1
    while j < n && same_dir(hps[i], hps[j]) {
      j = j + 1
    }
    let d = hp_dir(hps[i])
    let mut best = hps[i]
    let mut best_val = cross_v(d, hps[i].p)
    let mut k = i + 1
    while k < j {
      let val = cross_v(d, hps[k].p)
      if val > best_val {
        best = hps[k]
        best_val = val
      }
      k = k + 1
    }
    uniq.push(best)
    i = j
  }

  let m = uniq.length()
  if m < 3 {
    return []
  }

  // Deques. `dq` holds the active half-planes; `pts` holds the intersection
  // of each adjacent pair. Both share the front index `head`. Invariant:
  //   pts.length() == dq.length() - 1
  //   pts[t] == hp_intersect(dq[t], dq[t+1])  for t in [head, dq.length()-1)
  let dq : Array[HalfPlane] = []
  let pts : Array[DPoint] = []
  let mut head = 0

  dq.push(uniq[0])
  let mut idx = 1
  while idx < m {
    let h = uniq[idx]
    // Pop back while the last intersection point is strictly to the right of
    // `h` (i.e. outside the new half-plane).
    while pts.length() > head && sign(hp_cross(h, pts[pts.length() - 1])) < 0 {
      let _ = pts.pop()
      let _ = dq.pop()
    }
    // Pop front while the first intersection point is strictly to the right
    // of `h`.
    while pts.length() > head && sign(hp_cross(h, pts[head])) < 0 {
      head = head + 1
    }
    // Parallel check against the current back.
    let mut push_h = true
    if dq.length() - head >= 1 {
      let back = dq[dq.length() - 1]
      let db = hp_dir(back)
      let dh = hp_dir(h)
      if sign(cross_v(db, dh)) == 0 {
        if dot_v(db, dh) < 0.0 {
          // Opposite directions: the region between them is a strip. If the
          // two lines do not overlap, the intersection is empty.
          if sign(hp_cross(h, back.p)) < 0 || sign(hp_cross(back, h.p)) < 0 {
            return []
          }
          // Otherwise they overlap (a strip); push `h` normally. The
          // bounding box caps the strip to a finite polygon.
          // Same direction: keep the more restrictive (post-dedup this is
          // rare, but handled for numerical safety).
        } else if cross_v(dh, h.p) > cross_v(dh, back.p) + EPS {
          let _ = dq.pop()
          if pts.length() > head {
            let _ = pts.pop()
          }
          // Fall through: push `h` as the new back.
        } else {
          push_h = false
        }
      }
    }
    if push_h {
      dq.push(h)
      if dq.length() - head >= 2 {
        pts.push(hp_intersect(dq[dq.length() - 2], dq[dq.length() - 1]))
      }
    }
    idx = idx + 1
  }

  // Final cleanup: pop back while the last intersection is right of the
  // first half-plane, and pop front while the first intersection is right
  // of the last half-plane.
  while pts.length() - head >= 2 &&
        sign(hp_cross(dq[head], pts[pts.length() - 1])) < 0 {
    let _ = pts.pop()
    let _ = dq.pop()
  }
  while pts.length() - head >= 2 &&
        sign(hp_cross(dq[dq.length() - 1], pts[head])) < 0 {
    head = head + 1
  }

  let sz = dq.length() - head
  if sz < 3 {
    return []
  }
  // Build the polygon: the `sz - 1` cached intersection points, plus the
  // closing vertex at the intersection of the last and first half-planes.
  let poly : Array[DPoint] = []
  for t = 0; t < sz - 1; t = t + 1 {
    poly.push(pts[head + t])
  }
  poly.push(hp_intersect(dq[dq.length() - 1], dq[head]))
  poly
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

///|
/// Signed area of a polygon (positive for CCW).
fn polygon_area(poly : Array[DPoint]) -> Double {
  let n = poly.length()
  if n < 3 {
    return 0.0
  }
  let mut s = 0.0
  for i = 0; i < n; i = i + 1 {
    let j = (i + 1) % n
    s = s + poly[i].x * poly[j].y - poly[j].x * poly[i].y
  }
  0.5 * s
}

///|
/// True iff `p` lies inside (or on the boundary of) half-plane `h`.
fn in_hp(h : HalfPlane, p : DPoint) -> Bool {
  hp_cross(h, p) >= -1.0e-7
}

///|
/// True iff every vertex of `poly` lies inside every half-plane of `hps`.
fn all_in(hps : Array[HalfPlane], poly : Array[DPoint]) -> Bool {
  for i = 0; i < poly.length(); i = i + 1 {
    let p = poly[i]
    for j = 0; j < hps.length(); j = j + 1 {
      if !in_hp(hps[j], p) {
        return false
      }
    }
  }
  true
}

///|
/// Approximate equality for doubles within an absolute tolerance.
fn approx(a : Double, b : Double) -> Bool {
  let d = a - b
  let ad = if d < 0.0 { -d } else { d }
  ad < 1.0e-6
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "half_plane: unit square" {
  let hps = [
    half_plane(dpoint(0.0, 0.0), dpoint(0.0, -1.0)), // x >= 0
    half_plane(dpoint(1.0, 0.0), dpoint(1.0, 1.0)), // x <= 1
    half_plane(dpoint(0.0, 0.0), dpoint(1.0, 0.0)), // y >= 0
    half_plane(dpoint(0.0, 1.0), dpoint(-1.0, 1.0)), // y <= 1
  ]
  let poly = intersect(hps)
  assert_eq(poly.length(), 4)
  assert_true(approx(polygon_area(poly), 1.0))
  assert_true(all_in(hps, poly))
}

///|
test "half_plane: triangle" {
  let hps = [
    half_plane(dpoint(0.0, 0.0), dpoint(0.0, -1.0)), // x >= 0
    half_plane(dpoint(0.0, 0.0), dpoint(1.0, 0.0)), // y >= 0
    half_plane(dpoint(1.0, 1.0), dpoint(0.0, 2.0)), // x + y <= 2
  ]
  let poly = intersect(hps)
  assert_eq(poly.length(), 3)
  assert_true(approx(polygon_area(poly), 2.0))
  assert_true(all_in(hps, poly))
}

///|
test "half_plane: empty intersection (disjoint strip)" {
  let hps = [
    half_plane(dpoint(1.0, 0.0), dpoint(1.0, -1.0)), // x >= 1
    half_plane(dpoint(0.0, 0.0), dpoint(0.0, 1.0)), // x <= 0
  ]
  let poly = intersect(hps)
  assert_eq(poly.length(), 0)
}

///|
test "half_plane: clipped triangle (trapezoid)" {
  // x >= 0, y >= 0, x + y <= 2, x <= 1  =>  area 1.5
  let hps = [
    half_plane(dpoint(0.0, 0.0), dpoint(0.0, -1.0)), // x >= 0
    half_plane(dpoint(0.0, 0.0), dpoint(1.0, 0.0)), // y >= 0
    half_plane(dpoint(1.0, 1.0), dpoint(0.0, 2.0)), // x + y <= 2
    half_plane(dpoint(1.0, 0.0), dpoint(1.0, 1.0)), // x <= 1
  ]
  let poly = intersect(hps)
  assert_true(poly.length() >= 3)
  assert_true(approx(polygon_area(poly), 1.5))
  assert_true(all_in(hps, poly))
}

///|
test "half_plane: regular hexagon" {
  // Six half-planes, each with its boundary at distance 1 from the origin
  // (apothem 1). The intersection is a regular hexagon of area 2*sqrt(3)
  // ~= 3.4641.
  let hps : Array[HalfPlane] = []
  for k = 0; k < 6; k = k + 1 {
    // Outward normal direction at angle k*60 deg: (cos, sin). The edge
    // point is (cos, sin) (distance 1); the edge direction is the outward
    // normal rotated by +90 deg => (-sin, cos), whose left side is the
    // inward direction, giving the half-plane `cos*x + sin*y <= 1`.
    let ang = (k * 60).to_double() * 3.141592653589793 / 180.0
    let nx = @math.cos(ang)
    let ny = @math.sin(ang)
    let p = dpoint(nx, ny)
    let q = dpoint(nx - ny, ny + nx)
    hps.push(half_plane(p, q))
  }
  let poly = intersect(hps)
  assert_true(poly.length() >= 5)
  let area = polygon_area(poly)
  assert_true(approx(area, 3.4641016151377544))
  assert_true(all_in(hps, poly))
}

///|
test "half_plane: redundant half-plane is ignored" {
  // x >= 0 plus a strictly weaker x >= -5: the result equals the box clipped
  // by x >= 0 only (a half-box). Check the leftmost vertex has x ~ 0.
  let hps = [
    half_plane(dpoint(0.0, 0.0), dpoint(0.0, -1.0)), // x >= 0
    half_plane(dpoint(-5.0, 0.0), dpoint(-5.0, -1.0)), // x >= -5 (redundant)
    half_plane(dpoint(0.0, 0.0), dpoint(1.0, 0.0)), // y >= 0
  ]
  let poly = intersect(hps)
  assert_true(poly.length() >= 3)
  assert_true(all_in(hps, poly))
  // No vertex should have x < -eps (x >= 0 dominates).
  for i = 0; i < poly.length(); i = i + 1 {
    assert_true(poly[i].x > -1.0e-6)
  }
}

///|
test "half_plane: single half-plane (unbounded, clamped to box)" {
  // Only x >= 0: unbounded, clamped to the bounding box. The result is a
  // large polygon to the right of the y-axis.
  let hps = [half_plane(dpoint(0.0, 0.0), dpoint(0.0, -1.0))] // x >= 0
  let poly = intersect(hps)
  assert_true(poly.length() >= 3)
  assert_true(all_in(hps, poly))
  // Area should be half the box: (2e9)^2 / 2 = 2e18.
  let area = polygon_area(poly)
  assert_true(area > 1.0e17)
}

///|
test "half_plane: point (degenerate, near-empty)" {
  // x >= 0, x <= 0, y >= 0, y <= 0 => the single point (0,0). With epsilon,
  // this yields an empty or near-empty polygon.
  let hps = [
    half_plane(dpoint(0.0, 0.0), dpoint(0.0, -1.0)), // x >= 0
    half_plane(dpoint(0.0, 0.0), dpoint(0.0, 1.0)), // x <= 0
    half_plane(dpoint(0.0, 0.0), dpoint(1.0, 0.0)), // y >= 0
    half_plane(dpoint(0.0, 0.0), dpoint(-1.0, 0.0)), // y <= 0
  ]
  let poly = intersect(hps)
  // The intersection is a single point; area must be ~0.
  let area = polygon_area(poly)
  let a = if area < 0.0 { -area } else { area }
  assert_true(a < 1.0e-6)
  assert_true(all_in(hps, poly))
}

///|
test "half_plane: shifted square" {
  // Square [10, 20] x [-5, 5].
  let hps = [
    half_plane(dpoint(10.0, 0.0), dpoint(10.0, -1.0)), // x >= 10
    half_plane(dpoint(20.0, 0.0), dpoint(20.0, 1.0)), // x <= 20
    half_plane(dpoint(0.0, -5.0), dpoint(1.0, -5.0)), // y >= -5
    half_plane(dpoint(0.0, 5.0), dpoint(-1.0, 5.0)), // y <= 5
  ]
  let poly = intersect(hps)
  assert_eq(poly.length(), 4)
  assert_true(approx(polygon_area(poly), 100.0))
  assert_true(all_in(hps, poly))
}
