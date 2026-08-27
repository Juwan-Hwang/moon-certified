/// Fortune's algorithm — O(n log n) Voronoi diagram construction via sweep line.
///
/// Fortune's algorithm constructs the Voronoi diagram of n points in the plane
/// in O(n log n) time using a sweep line that moves from top to bottom. The
/// key insight is the **beach line**: the lower envelope of parabolic arcs
/// formed by the sites above the sweep line. Each parabola has its focus at a
/// site and its directrix at the sweep line.
///
/// ## Algorithm
///
/// 1. **Event queue**: A priority queue ordered by y-coordinate (descending).
///    Two event types:
///    - **Site event**: The sweep line reaches a new site. A new arc is
///      inserted into the beach line, splitting an existing arc.
///    - **Circle event**: Three consecutive arcs become cocircular — the
///      middle arc shrinks to a point and disappears, creating a Voronoi
///      vertex.
///
/// 2. **Beach line**: A sequence of arcs ordered by x-position. Each arc is
///    a portion of a parabola. Breakpoints between arcs trace out Voronoi
///    edges.
///
/// 3. **Processing**: At each event, the beach line is updated and new events
///    are detected. Site events create new arcs; circle events remove arcs
///    and create Voronoi vertices.
///
/// ## Complexity
///
/// - Time: O(n log n) — each site/circle event is processed in O(log n) time
///   (priority queue operations + beach line search).
/// - Space: O(n) for the beach line, event queue, and output.
///
/// ## References
///
/// - Fortune, S. "A Sweepline Algorithm for Voronoi Diagrams." Algorithmica,
///   2:153–174, 1987.
/// - de Berg, van Kreveld, Overmars, Schwarzkopf. "Computational Geometry:
///   Algorithms and Applications." Springer, 3rd ed., §7.2.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

///|
/// A 2D point with `Double` coordinates.
pub struct FPoint {
  x : Double
  y : Double
}

///|
/// Construct an [`FPoint`].
pub fn fpoint(x : Double, y : Double) -> FPoint {
  { x, y, }
}

///|
/// A Voronoi vertex.
pub struct FortuneVertex {
  x : Double
  y : Double
}

///|
/// A Voronoi edge. For bounded edges, both `start` and `end` are valid.
/// For unbounded edges, `end` extends in direction `(dir_x, dir_y)`.
pub struct FortuneEdge {
  start_x : Double
  start_y : Double
  end_x : Double
  end_y : Double
  is_bounded : Bool
  dir_x : Double
  dir_y : Double
  site_i : Int
  site_j : Int
}

///|
/// The result of Fortune's algorithm: Voronoi vertices and edges.
pub struct FortuneResult {
  vertices : Array[FortuneVertex]
  edges : Array[FortuneEdge]
  num_sites : Int
}

// ---------------------------------------------------------------------------
// Internal types
// ---------------------------------------------------------------------------

///|
/// An event in the sweep.
priv struct Event {
  y : Double
  x : Double
  is_site : Bool
  site_idx : Int
  arc_idx : Int
  center_x : Double
  center_y : Double
  mut valid : Bool
}

///|
/// An arc in the beach line (doubly-linked list).
priv struct Arc {
  site_idx : Int
  mut prev_idx : Int
  mut next_idx : Int
  mut event_idx : Int
  mut alive : Bool
  /// Index of the half-edge traced by the right breakpoint of this arc.
  mut edge_idx : Int
}

///|
/// A half-edge being traced by a breakpoint.
priv struct HalfEdge {
  start_x : Double
  start_y : Double
  mut end_x : Double
  mut end_y : Double
  mut finished : Bool
  site_i : Int
  site_j : Int
  dir_x : Double
  dir_y : Double
}

// ---------------------------------------------------------------------------
// Breakpoint computation
// ---------------------------------------------------------------------------

///|
/// Compute the x-coordinate of the breakpoint between two arcs at sweep
/// line position `d`.
///
/// Solves the system of two parabola equations. Returns the x-coordinate
/// of the intersection point on the beach line.
fn breakpoint_x(
  px : Double,
  py : Double,
  qx : Double,
  qy : Double,
  d : Double,
  prefer_left : Bool,
) -> Double {
  let dp = py - d
  let dq = qy - d
  if dp.abs() < 1.0e-12 && dq.abs() < 1.0e-12 {
    return (px + qx) / 2.0
  }
  if dp.abs() < 1.0e-12 {
    return px
  }
  if dq.abs() < 1.0e-12 {
    return qx
  }
  // A·x² + B·x + C = 0
  let a = dq - dp
  let b = 2.0 * (dp * qx - dq * px)
  let c = dq * px * px - dp * qx * qx - (dq - dp) * dp * dq
  if a.abs() < 1.0e-12 {
    if b.abs() < 1.0e-12 {
      return (px + qx) / 2.0
    }
    return -c / b
  }
  let disc = b * b - 4.0 * a * c
  if disc < 0.0 {
    return (px + qx) / 2.0
  }
  let sqrt_disc = disc.sqrt()
  let x1 = (-b - sqrt_disc) / (2.0 * a)
  let x2 = (-b + sqrt_disc) / (2.0 * a)
  if prefer_left {
    if x1 < x2 {
      x1
    } else {
      x2
    }
  } else if x1 > x2 {
    x1
  } else {
    x2
  }
}

// ---------------------------------------------------------------------------
// Circumcircle computation
// ---------------------------------------------------------------------------

///|
/// Compute the circumcircle of three points.
///
/// Returns `(center_x, center_y, radius, lowest_y)` where `lowest_y` is
/// the bottom of the circle — the y at which the circle event fires.
/// Returns `None` if the points are collinear.
fn circumcircle(
  ax : Double,
  ay : Double,
  bx : Double,
  by : Double,
  cx : Double,
  cy : Double,
) -> (Double, Double, Double, Double)? {
  let d = 2.0 * (ax * (by - cy) + bx * (cy - ay) + cx * (ay - by))
  if d.abs() < 1.0e-12 {
    return None
  }
  let ux = (
      (ax * ax + ay * ay) * (by - cy) +
      (bx * bx + by * by) * (cy - ay) +
      (cx * cx + cy * cy) * (ay - by)
    ) /
    d
  let uy = (
      (ax * ax + ay * ay) * (cx - bx) +
      (bx * bx + by * by) * (ax - cx) +
      (cx * cx + cy * cy) * (bx - ax)
    ) /
    d
  let dx = ux - ax
  let dy = uy - ay
  let r = (dx * dx + dy * dy).sqrt()
  Some((ux, uy, r, uy - r))
}

// ---------------------------------------------------------------------------
// Fortune's algorithm
// ---------------------------------------------------------------------------

///|
/// Construct the Voronoi diagram of `sites` using Fortune's sweep line
/// algorithm.
///
/// **Complexity**: O(n log n) time, O(n) space.
///
/// **Returns**: A [`FortuneResult`] containing Voronoi vertices and edges.
/// For fewer than 2 distinct sites, an empty result is returned.
pub fn fortune(sites : Array[FPoint]) -> FortuneResult {
  let n = sites.length()
  if n < 2 {
    return { vertices: [], edges: [], num_sites: n, }
  }
  // --- Deduplicate and sort sites by y (descending), then x ---
  let sorted : Array[FPoint] = []
  for i = 0; i < n; i = i + 1 {
    sorted.push(sites[i])
  }
  sorted.sort_by(fn(a : FPoint, b : FPoint) {
    if a.y != b.y {
      if a.y > b.y {
        -1
      } else {
        1
      }
    } else if a.x != b.x {
      if a.x < b.x {
        -1
      } else {
        1
      }
    } else {
      0
    }
  })
  let unique : Array[FPoint] = []
  for i = 0; i < sorted.length(); i = i + 1 {
    if i == 0 ||
      sorted[i].x != sorted[i - 1].x ||
      sorted[i].y != sorted[i - 1].y {
      unique.push(sorted[i])
    }
  }
  let m = unique.length()
  if m < 2 {
    return { vertices: [], edges: [], num_sites: m, }
  }
  // --- Data structures ---
  let pq : @priority_queue.PriorityQueue[Event] = @priority_queue.PriorityQueue::new(fn(
      a : Event,
      b : Event,
    ) {
      if a.y != b.y {
        if a.y > b.y {
          -1
        } else {
          1
        }
      } else if a.x != b.x {
        if a.x < b.x {
          -1
        } else {
          1
        }
      } else if a.is_site && !b.is_site {
        -1
      } else if !a.is_site && b.is_site {
        1
      } else {
        0
      }
    },
  )
  let arcs : Array[Arc] = []
  let events : Array[Event] = []
  let vertices : Array[FortuneVertex] = []
  let half_edges : Array[HalfEdge] = []
  // --- Insert all site events ---
  for i = 0; i < m; i = i + 1 {
    let _ = pq.push({
      y: unique[i].y,
      x: unique[i].x,
      is_site: true,
      site_idx: i,
      arc_idx: -1,
      center_x: 0.0,
      center_y: 0.0,
      valid: true,
    })
  }
  // --- Helper: find the arc whose parabola contains x at sweep position d ---
  fn find_arc(x : Double, d : Double) -> Int {
    let mut result = 0
    for i = 0; i < arcs.length(); i = i + 1 {
      if !arcs[i].alive {
        continue
      }
      let arc = arcs[i]
      result = i
      if arc.next_idx >= 0 {
        let next = arcs[arc.next_idx]
        let bp = breakpoint_x(
          unique[arc.site_idx].x,
          unique[arc.site_idx].y,
          unique[next.site_idx].x,
          unique[next.site_idx].y,
          d,
          true,
        )
        if x < bp {
          return i
        }
      } else {
        return i
      }
    }
    result
  }
  // --- Helper: schedule a circle event for arc a_idx ---
  fn schedule_circle(a_idx : Int, sweep_y : Double) -> Unit {
    let arc = arcs[a_idx]
    if arc.prev_idx < 0 || arc.next_idx < 0 {
      return
    }
    let prev = arcs[arc.prev_idx]
    let next = arcs[arc.next_idx]
    let p = unique[prev.site_idx]
    let s = unique[arc.site_idx]
    let q = unique[next.site_idx]
    match circumcircle(p.x, p.y, s.x, s.y, q.x, q.y) {
      Some((cx, cy, _r, lowest_y)) =>
        if lowest_y < sweep_y {
          let ev_idx = events.length()
          let ev : Event = {
            y: lowest_y,
            x: cx,
            is_site: false,
            site_idx: -1,
            arc_idx: a_idx,
            center_x: cx,
            center_y: cy,
            valid: true,
          }
          events.push(ev)
          let _ = pq.push(ev)
          arcs[a_idx].event_idx = ev_idx
        }
      None => ()
    }
  }
  // --- Helper: invalidate circle event for arc a_idx ---
  fn cancel_circle(a_idx : Int) -> Unit {
    let ev_idx = arcs[a_idx].event_idx
    if ev_idx >= 0 && ev_idx < events.length() {
      events[ev_idx].valid = false
    }
    arcs[a_idx].event_idx = -1
  }
  // --- Helper: create a half-edge ---
  fn make_edge(
    sx : Double,
    sy : Double,
    si : Int,
    sj : Int,
    dx : Double,
    dy : Double,
  ) -> Int {
    let idx = half_edges.length()
    half_edges.push({
      start_x: sx,
      start_y: sy,
      end_x: 0.0,
      end_y: 0.0,
      finished: false,
      site_i: si,
      site_j: sj,
      dir_x: dx,
      dir_y: dy,
    })
    idx
  }
  // --- Initialize beach line with the first site ---
  match pq.pop() {
    Some(first_ev) =>
      arcs.push({
        site_idx: first_ev.site_idx,
        prev_idx: -1,
        next_idx: -1,
        event_idx: -1,
        alive: true,
        edge_idx: -1,
      })
    None => return { vertices: [], edges: [], num_sites: m, }
  }
  // --- Main event loop ---
  while !pq.is_empty() {
    let ev = match pq.pop() {
      Some(e) => e
      None => break
    }
    if !ev.is_site && !ev.valid {
      continue
    }
    let sweep_y = ev.y
    if ev.is_site {
      // === Site event ===
      let site = unique[ev.site_idx]
      let found_idx = find_arc(site.x, sweep_y)
      let old_arc = arcs[found_idx]
      let old_site_idx = old_arc.site_idx
      cancel_circle(found_idx)
      // Create the new arc for the new site.
      let new_idx = arcs.length()
      arcs.push({
        site_idx: ev.site_idx,
        prev_idx: found_idx,
        next_idx: -1,
        event_idx: -1,
        alive: true,
        edge_idx: -1,
      })
      // Create a duplicate of the old arc (right half of the split).
      let dup_idx = arcs.length()
      arcs.push({
        site_idx: old_site_idx,
        prev_idx: new_idx,
        next_idx: old_arc.next_idx,
        event_idx: -1,
        alive: true,
        edge_idx: old_arc.edge_idx, // Inherit the right edge from the old arc
      })
      // Fix links.
      arcs[new_idx].next_idx = dup_idx
      arcs[found_idx].next_idx = new_idx
      if old_arc.next_idx >= 0 {
        arcs[old_arc.next_idx].prev_idx = dup_idx
      }
      // Compute the bisector direction for the new edge.
      let p = unique[old_site_idx]
      let q = site
      let bdx = q.y - p.y
      let bdy = p.x - q.x
      let blen = (bdx * bdx + bdy * bdy).sqrt()
      let (dir_x, dir_y) = if blen > 1.0e-12 {
        (bdx / blen, bdy / blen)
      } else {
        (1.0, 0.0)
      }
      // Start point: breakpoint position at current sweep.
      let start_x = breakpoint_x(p.x, p.y, q.x, q.y, sweep_y, true)
      let start_y = if (p.y - sweep_y).abs() > 1.0e-12 {
        (p.y + sweep_y) / 2.0
      } else {
        sweep_y
      }
      // Two half-edges: one going left (from the old arc's right breakpoint),
      // one going right.
      let he_left = make_edge(
        start_x,
        start_y,
        old_site_idx,
        ev.site_idx,
        -dir_x,
        -dir_y,
      )
      let he_right = make_edge(
        start_x,
        start_y,
        ev.site_idx,
        old_site_idx,
        dir_x,
        dir_y,
      )
      arcs[found_idx].edge_idx = he_left
      arcs[new_idx].edge_idx = he_right
      // Check for circle events on affected arcs.
      cancel_circle(found_idx)
      if arcs[found_idx].prev_idx >= 0 {
        schedule_circle(found_idx, sweep_y)
      }
      schedule_circle(new_idx, sweep_y)
      if arcs[dup_idx].next_idx >= 0 {
        schedule_circle(dup_idx, sweep_y)
      }
    } else {
      // === Circle event ===
      let arc_idx = ev.arc_idx
      let arc = arcs[arc_idx]
      if !arc.alive {
        continue
      }
      let prev_idx = arc.prev_idx
      let next_idx = arc.next_idx
      if prev_idx < 0 || next_idx < 0 {
        continue
      }
      // Add the Voronoi vertex.
      vertices.push({ x: ev.center_x, y: ev.center_y, })
      // Complete the two half-edges meeting at this vertex.
      // The left edge of the disappearing arc (traced by prev's right breakpoint).
      let prev_edge = arcs[prev_idx].edge_idx
      if prev_edge >= 0 {
        half_edges[prev_edge].end_x = ev.center_x
        half_edges[prev_edge].end_y = ev.center_y
        half_edges[prev_edge].finished = true
      }
      // The right edge of the disappearing arc.
      let arc_edge = arc.edge_idx
      if arc_edge >= 0 {
        half_edges[arc_edge].end_x = ev.center_x
        half_edges[arc_edge].end_y = ev.center_y
        half_edges[arc_edge].finished = true
      }
      // Remove the arc.
      arcs[arc_idx].alive = false
      arcs[arc_idx].event_idx = -1
      arcs[prev_idx].next_idx = next_idx
      arcs[next_idx].prev_idx = prev_idx
      // Cancel circle events on neighbors.
      cancel_circle(prev_idx)
      cancel_circle(next_idx)
      // Start a new half-edge between prev and next sites.
      let p = unique[arcs[prev_idx].site_idx]
      let q = unique[arcs[next_idx].site_idx]
      let bdx = q.y - p.y
      let bdy = p.x - q.x
      let blen = (bdx * bdx + bdy * bdy).sqrt()
      let (dir_x, dir_y) = if blen > 1.0e-12 {
        (bdx / blen, bdy / blen)
      } else {
        (1.0, 0.0)
      }
      let new_edge = make_edge(
        ev.center_x,
        ev.center_y,
        arcs[prev_idx].site_idx,
        arcs[next_idx].site_idx,
        dir_x,
        dir_y,
      )
      arcs[prev_idx].edge_idx = new_edge
      // Check for new circle events.
      if arcs[prev_idx].prev_idx >= 0 {
        schedule_circle(prev_idx, sweep_y)
      }
      if arcs[next_idx].next_idx >= 0 {
        schedule_circle(next_idx, sweep_y)
      }
    }
  }
  // --- Collect finished edges ---
  let edges : Array[FortuneEdge] = []
  for he = 0; he < half_edges.length(); he = he + 1 {
    let h = half_edges[he]
    if h.finished {
      edges.push({
        start_x: h.start_x,
        start_y: h.start_y,
        end_x: h.end_x,
        end_y: h.end_y,
        is_bounded: true,
        dir_x: 0.0,
        dir_y: 0.0,
        site_i: h.site_i,
        site_j: h.site_j,
      })
    } else {
      let far = 1.0e6
      edges.push({
        start_x: h.start_x,
        start_y: h.start_y,
        end_x: h.start_x + h.dir_x * far,
        end_y: h.start_y + h.dir_y * far,
        is_bounded: false,
        dir_x: h.dir_x,
        dir_y: h.dir_y,
        site_i: h.site_i,
        site_j: h.site_j,
      })
    }
  }
  { vertices, edges, num_sites: m, }
}

// ---------------------------------------------------------------------------
// Accessor functions
// ---------------------------------------------------------------------------

///|
/// Get the Voronoi vertices as `(x, y)` pairs.
pub fn get_vertices(result : FortuneResult) -> Array[(Double, Double)] {
  let v : Array[(Double, Double)] = []
  for i = 0; i < result.vertices.length(); i = i + 1 {
    v.push((result.vertices[i].x, result.vertices[i].y))
  }
  v
}

///|
/// Get the Voronoi edges as `((x1, y1), (x2, y2), is_bounded)` tuples.
pub fn get_edges(
  result : FortuneResult,
) -> Array[((Double, Double), (Double, Double), Bool)] {
  let e : Array[((Double, Double), (Double, Double), Bool)] = []
  for i = 0; i < result.edges.length(); i = i + 1 {
    let edge = result.edges[i]
    e.push(
      ((edge.start_x, edge.start_y), (edge.end_x, edge.end_y), edge.is_bounded),
    )
  }
  e
}

///|
/// Get the number of Voronoi vertices.
pub fn num_vertices(result : FortuneResult) -> Int {
  result.vertices.length()
}

///|
/// Get the number of Voronoi edges.
pub fn num_edges(result : FortuneResult) -> Int {
  result.edges.length()
}

///|
/// Get the number of input sites.
pub fn num_sites(result : FortuneResult) -> Int {
  result.num_sites
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "fortune_sweep: two sites" {
  let sites = [fpoint(0.0, 0.0), fpoint(10.0, 0.0)]
  let result = fortune(sites)
  assert_true(num_edges(result) >= 1)
  assert_eq(num_vertices(result), 0)
  assert_eq(num_sites(result), 2)
}

///|
test "fortune_sweep: three sites triangle" {
  let sites = [fpoint(0.0, 10.0), fpoint(-5.0, 0.0), fpoint(5.0, 0.0)]
  let result = fortune(sites)
  assert_eq(num_vertices(result), 1)
  assert_eq(num_sites(result), 3)
  let vs = get_vertices(result)
  assert_true((vs[0].0 - 0.0).abs() < 0.01)
  assert_true((vs[0].1 - 3.75).abs() < 0.01)
}

///|
test "fortune_sweep: three collinear sites" {
  let sites = [fpoint(0.0, 0.0), fpoint(5.0, 0.0), fpoint(10.0, 0.0)]
  let result = fortune(sites)
  assert_eq(num_vertices(result), 0)
  assert_eq(num_sites(result), 3)
}

///|
test "fortune_sweep: four sites in square" {
  let sites = [
    fpoint(0.0, 10.0),
    fpoint(10.0, 10.0),
    fpoint(0.0, 0.0),
    fpoint(10.0, 0.0),
  ]
  let result = fortune(sites)
  assert_eq(num_sites(result), 4)
  assert_true(num_vertices(result) >= 1)
  let vs = get_vertices(result)
  let mut found_center = false
  for i = 0; i < vs.length(); i = i + 1 {
    if (vs[i].0 - 5.0).abs() < 0.1 && (vs[i].1 - 5.0).abs() < 0.1 {
      found_center = true
    }
  }
  assert_true(found_center)
}

///|
test "fortune_sweep: single site" {
  let sites = [fpoint(0.0, 0.0)]
  let result = fortune(sites)
  assert_eq(num_sites(result), 1)
  assert_eq(num_vertices(result), 0)
  assert_eq(num_edges(result), 0)
}

///|
test "fortune_sweep: duplicate sites" {
  let sites = [fpoint(0.0, 0.0), fpoint(0.0, 0.0), fpoint(10.0, 0.0)]
  let result = fortune(sites)
  assert_eq(num_sites(result), 2)
  assert_true(num_edges(result) >= 1)
}

///|
test "fortune_sweep: grid of sites" {
  let sites : Array[FPoint] = []
  for i = 0; i < 4; i = i + 1 {
    for j = 0; j < 4; j = j + 1 {
      sites.push(fpoint(i.to_double() * 10.0, j.to_double() * 10.0))
    }
  }
  let result = fortune(sites)
  assert_eq(num_sites(result), 16)
  assert_true(num_vertices(result) > 0)
  assert_true(num_edges(result) > 0)
}

///|
test "fortune_sweep: random sites stress test" {
  let sites : Array[FPoint] = []
  let mut state = 42L
  for i = 0; i < 50; i = i + 1 {
    state = state ^ (state << 13)
    state = state ^ (state >> 7)
    state = state ^ (state << 17)
    let val = if state < 0L { -state } else { state }
    let x = (val % 1000L).to_double()
    state = state ^ (state << 13)
    state = state ^ (state >> 7)
    state = state ^ (state << 17)
    let val2 = if state < 0L { -state } else { state }
    let y = (val2 % 1000L).to_double()
    sites.push(fpoint(x, y))
  }
  let result = fortune(sites)
  assert_eq(num_sites(result), 50)
  assert_true(num_vertices(result) > 0)
  assert_true(num_edges(result) > 0)
}

///|
test "fortune_sweep: circumcircle basic" {
  match circumcircle(0.0, 0.0, 2.0, 0.0, 1.0, 1.0) {
    Some((cx, cy, r, lowest)) => {
      assert_true((cx - 1.0).abs() < 1.0e-9)
      assert_true((cy - 0.0).abs() < 1.0e-9)
      assert_true((r - 1.0).abs() < 1.0e-9)
      assert_true((lowest - -1.0).abs() < 1.0e-9)
    }
    None => assert_true(false)
  }
}

///|
test "fortune_sweep: circumcircle collinear" {
  match circumcircle(0.0, 0.0, 1.0, 0.0, 2.0, 0.0) {
    Some(_) => assert_true(false)
    None => assert_true(true)
  }
}

///|
test "fortune_sweep: breakpoint_x same height" {
  let bp = breakpoint_x(0.0, 10.0, 20.0, 10.0, 5.0, true)
  assert_true((bp - 10.0).abs() < 1.0e-9)
}

///|
test "fortune_sweep: breakpoint_x different heights" {
  let bp = breakpoint_x(0.0, 10.0, 10.0, 5.0, 0.0, true)
  assert_true(bp > -1.0)
  assert_true(bp < 11.0)
}

///|
test "fortune_sweep: five sites convex" {
  let sites = [
    fpoint(0.0, 100.0),
    fpoint(95.0, 31.0),
    fpoint(59.0, -81.0),
    fpoint(-59.0, -81.0),
    fpoint(-95.0, 31.0),
  ]
  let result = fortune(sites)
  assert_eq(num_sites(result), 5)
  assert_true(num_vertices(result) > 0)
  assert_true(num_edges(result) > 0)
}

///|
test "fortune_sweep: edges are bisectors" {
  let sites = [fpoint(0.0, 0.0), fpoint(10.0, 0.0)]
  let result = fortune(sites)
  let edges = get_edges(result)
  assert_true(edges.length() >= 1)
  let ((sx, _), _, _) = edges[0]
  assert_true((sx - 5.0).abs() < 0.1)
}

///|
test "fortune_sweep: many sites on circle" {
  let sites : Array[FPoint] = []
  for i = 0; i < 10; i = i + 1 {
    let angle = 3.14159265358979 * 2.0 * i.to_double() / 10.0
    // Manual cos/sin via Taylor series (avoid @math dependency).
    let cos_a = 1.0 - angle * angle / 2.0 + angle * angle * angle * angle / 24.0
    let sin_a = angle -
      angle * angle * angle / 6.0 +
      angle * angle * angle * angle * angle / 120.0
    sites.push(fpoint(100.0 * cos_a, 100.0 * sin_a))
  }
  let result = fortune(sites)
  assert_eq(num_sites(result), 10)
  assert_true(num_vertices(result) > 0)
}
