/// Segment Intersection via Bentley-Ottmann Sweep-Line Algorithm.
///
/// The Bentley-Ottmann algorithm finds all intersection points among a set
/// of line segments using a sweep-line approach with an event queue and a
/// balanced status structure.
///
/// ## Algorithm
/// 1. Create events for each segment endpoint (left and right).
/// 2. Sweep from left to right, maintaining an ordered set of "active"
///    segments (those crossing the current sweep line) in a balanced BST.
/// 3. At a left endpoint: insert the segment into the status and test it
///    against its new upper/lower neighbours; schedule any intersection
///    found to the right of the sweep line as a future event.
/// 4. At a right endpoint: remove the segment and test the two segments
///    that become newly adjacent.
/// 5. At an intersection event: report the point, swap the two crossing
///    segments in the status, and test the two new neighbour pairs.
///
/// Because two segments only ever need to be tested when they are adjacent
/// in the status, and crossings are processed as events that restore the
/// adjacency invariant, the algorithm reports *every* intersection.
///
/// ## Complexity
/// - Time: O((n + k) log n) expected, where n = segments, k = intersections.
///   The status structure is a treap (randomised balanced BST) giving
///   O(log n) insert / remove / neighbour queries; the event queue is a
///   binary heap with O(log n) push / pop.
/// - Space: O(n + k).
///
/// ## Numerical robustness
/// Segment coordinates are `Double`. The vertical order is computed as the
/// y-coordinate at the current sweep x; ties (segments meeting exactly at
/// the sweep x) are broken by slope so that, just past a crossing, the
/// segment with the larger slope is ordered above. This is the standard
/// robust technique and handles ordinary inputs correctly. Truly
/// degenerate inputs — collinear overlaps, or three or more segments
/// meeting at a single point — may report duplicate points; the output is
/// deduplicated within a 1e-9 tolerance.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

///|
/// Epsilon for floating-point comparisons.
const BO_EPS : Double = 1.0e-9

///|
/// Delta for sweep-line position adjustment at intersection events.
/// Must be large enough that the y-difference between the two crossing
/// segments at `sweep_x ± SWEEP_DELTA` exceeds `BO_EPS`, ensuring the
/// comparator correctly distinguishes pre-crossing from post-crossing order.
const SWEEP_DELTA : Double = 1.0e-6

///|
/// An event in the sweep-line algorithm.
/// `kind`: 0 = left endpoint, 1 = intersection, 2 = right endpoint.
priv struct Event {
  x : Double
  y : Double
  kind : Int
  seg : Int // for left/right: the segment index; for intersection: first seg
  seg2 : Int // for intersection: second seg; -1 otherwise
}

///|
/// Total order on events: by x, then y, then kind (left < intersection < right),
/// then by segment indices for determinism.
fn event_cmp(a : Event, b : Event) -> Int {
  if (a.x - b.x).abs() > BO_EPS {
    if a.x < b.x {
      -1
    } else {
      1
    }
  } else if (a.y - b.y).abs() > BO_EPS {
    if a.y < b.y {
      -1
    } else {
      1
    }
  } else if a.kind != b.kind {
    a.kind - b.kind
  } else if a.seg != b.seg {
    a.seg - b.seg
  } else {
    a.seg2 - b.seg2
  }
}

// ---------------------------------------------------------------------------
// Binary min-heap event queue
// ---------------------------------------------------------------------------

///|
/// A min-heap of events ordered by `event_cmp`.
priv struct EventQueue {
  data : Array[Event]
}

///|
fn queue_new() -> EventQueue {
  { data: [] }
}

///|
fn EventQueue::push(self : EventQueue, e : Event) -> Unit {
  self.data.push(e)
  let mut i = self.data.length() - 1
  while i > 0 {
    let parent = (i - 1) / 2
    if event_cmp(self.data[i], self.data[parent]) < 0 {
      let tmp = self.data[i]
      self.data[i] = self.data[parent]
      self.data[parent] = tmp
      i = parent
    } else {
      break
    }
  }
}

///|
fn EventQueue::pop(self : EventQueue) -> Event? {
  let n = self.data.length()
  if n == 0 {
    return None
  }
  let top = self.data[0]
  let last = self.data.pop()
  if self.data.length() > 0 {
    self.data[0] = last.unwrap()
    let mut i = 0
    let mut done = false
    while !done {
      let left = 2 * i + 1
      let right = 2 * i + 2
      let mut smallest = i
      if left < self.data.length() &&
        event_cmp(self.data[left], self.data[smallest]) < 0 {
        smallest = left
      }
      if right < self.data.length() &&
        event_cmp(self.data[right], self.data[smallest]) < 0 {
        smallest = right
      }
      if smallest != i {
        let tmp = self.data[i]
        self.data[i] = self.data[smallest]
        self.data[smallest] = tmp
        i = smallest
      } else {
        done = true
      }
    }
  }
  Some(top)
}

///|
fn EventQueue::is_empty(self : EventQueue) -> Bool {
  self.data.length() == 0
}

// ---------------------------------------------------------------------------
// Treap status structure (randomised balanced BST) with a dynamic comparator.
// ---------------------------------------------------------------------------

///|
priv struct TNode {
  key : Int // segment index
  priority : Int64
  mut left : TNode?
  mut right : TNode?
}

///|
/// The status structure: an ordered set of active segment indices.
/// The ordering is defined by a comparator supplied to each operation,
/// which encodes "vertical order at the current sweep x".
priv struct Status {
  mut root : TNode?
}

///|
/// Split the treap by comparator: left subtree gets keys `< key`, right
/// subtree gets keys `>= key` (using `cmp(key, node.key)`).
fn Status::split(
  self : Status,
  node : TNode?,
  key : Int,
  cmp : (Int, Int) -> Int,
) -> (TNode?, TNode?) {
  match node {
    None => (None, None)
    Some(n) => {
      let c = cmp(key, n.key)
      if c > 0 {
        let (l, r) = self.split(n.right, key, cmp)
        n.right = l
        (Some(n), r)
      } else {
        let (l, r) = self.split(n.left, key, cmp)
        n.left = r
        (l, Some(n))
      }
    }
  }
}

///|
/// Merge two treaps where every key in `a` is ordered before every key in
/// `b` (with respect to the active comparator).
fn Status::merge(self : Status, a : TNode?, b : TNode?) -> TNode? {
  match (a, b) {
    (None, _) => b
    (_, None) => a
    (Some(na), Some(nb)) =>
      if na.priority > nb.priority {
        na.right = self.merge(na.right, b)
        Some(na)
      } else {
        nb.left = self.merge(a, nb.left)
        Some(nb)
      }
  }
}

///|
/// Find the node equal to `key` (same segment index).
fn find_node(node : TNode?, key : Int, cmp : (Int, Int) -> Int) -> TNode? {
  let mut cur = node
  let mut go = true
  while go {
    match cur {
      None => go = false
      Some(n) => {
        let c = cmp(key, n.key)
        if c == 0 {
          return Some(n)
        } else if c > 0 {
          cur = n.right
        } else {
          cur = n.left
        }
      }
    }
  }
  None
}

///|
/// Insert `key` into the status. If a node with an equal key (same segment)
/// already exists, it is left unchanged.
fn Status::insert(
  self : Status,
  key : Int,
  cmp : (Int, Int) -> Int,
  rng : RNG64,
) -> Unit {
  match find_node(self.root, key, cmp) {
    Some(_) => return
    None => ()
  }
  let node = { key, priority: rng.next(), left: None, right: None }
  let (l, r) = self.split(self.root, key, cmp)
  self.root = self.merge(self.merge(l, Some(node)), r)
}

///|
/// Split so that the left result contains keys `<= key` (equal kept on the
/// left). Used to isolate a single equal node.
fn split_strict(
  node : TNode?,
  key : Int,
  cmp : (Int, Int) -> Int,
) -> (TNode?, TNode?) {
  match node {
    None => (None, None)
    Some(n) => {
      let c = cmp(key, n.key)
      if c > 0 {
        let (l, r) = split_strict(n.right, key, cmp)
        n.right = l
        (Some(n), r)
      } else if c < 0 {
        let (l, r) = split_strict(n.left, key, cmp)
        n.left = r
        (l, Some(n))
      } else {
        let (l, r) = split_strict(n.right, key, cmp)
        n.right = l
        (Some(n), r)
      }
    }
  }
}

///|
/// Remove `key` from the status. Returns `true` if it was present.
fn Status::remove(self : Status, key : Int, cmp : (Int, Int) -> Int) -> Bool {
  match find_node(self.root, key, cmp) {
    None => false
    Some(_) => {
      let (l, rest) = self.split(self.root, key, cmp) // l: < key, rest: >= key
      let (mid, r) = split_strict(rest, key, cmp) // mid: == key, r: > key
      ignore(mid)
      self.root = self.merge(l, r)
      true
    }
  }
}

///|
fn min_key(node : TNode?) -> Int? {
  let mut cur = node
  let mut result : Int? = None
  let mut go = true
  while go {
    match cur {
      None => go = false
      Some(n) => {
        result = Some(n.key)
        cur = n.left
      }
    }
  }
  result
}

///|
fn max_key(node : TNode?) -> Int? {
  let mut cur = node
  let mut result : Int? = None
  let mut go = true
  while go {
    match cur {
      None => go = false
      Some(n) => {
        result = Some(n.key)
        cur = n.right
      }
    }
  }
  result
}

///|
/// Return the predecessor (largest key < query) and successor (smallest key
/// > query) of `key` in the current order. If `key` itself is present, the
/// neighbours of that node are returned.
fn Status::neighbours(
  self : Status,
  key : Int,
  cmp : (Int, Int) -> Int,
) -> (Int?, Int?) {
  let mut pred : Int? = None
  let mut succ : Int? = None
  let mut cur = self.root
  let mut go = true
  while go {
    match cur {
      None => go = false
      Some(n) => {
        let c = cmp(key, n.key)
        if c > 0 {
          pred = Some(n.key)
          cur = n.right
        } else if c < 0 {
          succ = Some(n.key)
          cur = n.left
        } else {
          // Key found: predecessor is max of left subtree, or the
          // tracked ancestor pred if no left subtree exists.
          // Successor is min of right subtree, or tracked ancestor succ.
          match max_key(n.left) {
            Some(k) => pred = Some(k)
            None => ()
          }
          match min_key(n.right) {
            Some(k) => succ = Some(k)
            None => ()
          }
          go = false
        }
      }
    }
  }
  (pred, succ)
}

// ---------------------------------------------------------------------------
// A small, fast, deterministic 64-bit pseudo-random generator for treap
// priorities (SplitMix64). Quality is far higher than a naive LCG and ample
// for randomised balancing; not for cryptographic use.
// ---------------------------------------------------------------------------

///|
priv struct RNG64 {
  mut state : Int64
}

///|
fn RNG64::next(self : RNG64) -> Int64 {
  self.state = self.state + 0x9E3779B97F4A7C15L
  let mut z = self.state
  z = (z ^ (z.reinterpret_as_uint64() >> 30).reinterpret_as_int64()) *
    0xBF58476D1CE4E5B9L
  z = (z ^ (z.reinterpret_as_uint64() >> 27).reinterpret_as_int64()) *
    0x94D049BB133111EBL
  z = z ^ (z.reinterpret_as_uint64() >> 31).reinterpret_as_int64()
  z
}

// ---------------------------------------------------------------------------
// Geometry helpers
// ---------------------------------------------------------------------------

///|
/// y-coordinate of segment `s` at vertical line `x`.
fn y_at(s : (Double, Double, Double, Double), x : Double) -> Double {
  let (x1, y1, x2, y2) = s
  if (x2 - x1).abs() < BO_EPS {
    return y1
  }
  y1 + (x - x1) * (y2 - y1) / (x2 - x1)
}

///|
/// Slope (dy/dx) of segment `s`. Vertical segments are treated as ±∞.
fn slope_of(s : (Double, Double, Double, Double)) -> Double {
  let (x1, y1, x2, y2) = s
  let dx = x2 - x1
  if dx.abs() < BO_EPS {
    return if y2 >= y1 { 1.0e18 } else { -1.0e18 }
  }
  (y2 - y1) / dx
}

///|
/// Compute the intersection point of two segments, or `None` if they are
/// parallel/collinear or do not intersect within their spans.
fn seg_intersection(
  a : (Double, Double, Double, Double),
  b : (Double, Double, Double, Double),
) -> (Double, Double)? {
  let (x1, y1, x2, y2) = a
  let (x3, y3, x4, y4) = b
  let denom = (x2 - x1) * (y4 - y3) - (y2 - y1) * (x4 - x3)
  if denom.abs() < BO_EPS {
    return None
  }
  let t = ((x3 - x1) * (y4 - y3) - (y3 - y1) * (x4 - x3)) / denom
  let u = ((x3 - x1) * (y2 - y1) - (y3 - y1) * (x2 - x1)) / denom
  if t >= -BO_EPS && t <= 1.0 + BO_EPS && u >= -BO_EPS && u <= 1.0 + BO_EPS {
    Some((x1 + t * (x2 - x1), y1 + t * (y2 - y1)))
  } else {
    None
  }
}

// ---------------------------------------------------------------------------
// Sweep context
// ---------------------------------------------------------------------------

///|
priv struct Ctx {
  segments : Array[(Double, Double, Double, Double)] // normalised: x1 <= x2
  mut sweep_x : Double
}

///|
/// Comparator for the status: order segments by y at the current sweep x;
/// break ties by slope (larger slope above). Returns <0 if a is below b.
fn ctx_cmp(ctx : Ctx, a : Int, b : Int) -> Int {
  let sa = ctx.segments[a]
  let sb = ctx.segments[b]
  let ya = y_at(sa, ctx.sweep_x)
  let yb = y_at(sb, ctx.sweep_x)
  if (ya - yb).abs() > BO_EPS {
    if ya < yb {
      -1
    } else {
      1
    }
  } else {
    let ma = slope_of(sa)
    let mb = slope_of(sb)
    if (ma - mb).abs() < BO_EPS {
      0
    } else if ma < mb {
      -1
    } else {
      1
    }
  }
}

///|
/// Is point `(px, py)` strictly to the right of the current event
/// `(ctx.sweep_x, event_y)`? Used to avoid re-scheduling the event being
/// processed.
fn to_the_right(ctx : Ctx, event_y : Double, px : Double, py : Double) -> Bool {
  if px > ctx.sweep_x + BO_EPS {
    true
  } else if (px - ctx.sweep_x).abs() < BO_EPS && py > event_y + BO_EPS {
    true
  } else {
    false
  }
}

///|
/// If segments `i` and `j` intersect strictly to the right of the current
/// event, push an intersection event for them (avoiding duplicate scheduling).
fn schedule(
  ctx : Ctx,
  q : EventQueue,
  norm : Array[(Double, Double, Double, Double)],
  scheduled : Map[(Int, Int), (Double, Double)],
  i : Int,
  j : Int,
  event_y : Double,
) -> Unit {
  let (a, b) = if i < j { (i, j) } else { (j, i) }
  match seg_intersection(norm[i], norm[j]) {
    None => ()
    Some((px, py)) =>
      if to_the_right(ctx, event_y, px, py) {
        let mut already = false
        match scheduled.get((a, b)) {
          Some((sx, sy)) =>
            if (sx - px).abs() < BO_EPS && (sy - py).abs() < BO_EPS {
              already = true
            }
          None => ()
        }
        if !already {
          scheduled[(a, b)] = (px, py)
          q.push({ x: px, y: py, kind: 1, seg: a, seg2: b })
        }
      }
  }
}

///|
/// Deduplicate intersection points within tolerance 1e-9.
fn dedup(pts : Array[(Double, Double)]) -> Array[(Double, Double)] {
  let unique : Array[(Double, Double)] = []
  for i = 0; i < pts.length(); i = i + 1 {
    let (rx, ry) = pts[i]
    let mut found = false
    for j = 0; j < unique.length(); j = j + 1 {
      let (ux, uy) = unique[j]
      if (rx - ux).abs() < 1.0e-9 && (ry - uy).abs() < 1.0e-9 {
        found = true
        break
      }
    }
    if !found {
      unique.push((rx, ry))
    }
  }
  unique
}

///|
/// Find all intersection points among a set of segments using the
/// Bentley-Ottmann sweep-line algorithm.
///
/// Each segment is `(x1, y1, x2, y2)`. Returns all intersection points,
/// deduplicated within a tolerance of 1e-9.
pub fn find_intersections(
  segments : Array[(Double, Double, Double, Double)],
) -> Array[(Double, Double)] {
  let n = segments.length()
  if n < 2 {
    return []
  }
  // Normalise segments so x1 <= x2 (and if vertical, y1 <= y2).
  let norm : Array[(Double, Double, Double, Double)] = []
  for i = 0; i < n; i = i + 1 {
    let (x1, y1, x2, y2) = segments[i]
    if x1 < x2 || (x1 == x2 && y1 <= y2) {
      norm.push((x1, y1, x2, y2))
    } else {
      norm.push((x2, y2, x1, y1))
    }
  }
  let ctx : Ctx = { segments: norm, sweep_x: 0.0 }
  let q = queue_new()
  let rng : RNG64 = { state: 0xDEADBEEFCAFEBABEL }
  for i = 0; i < n; i = i + 1 {
    let (x1, y1, x2, y2) = norm[i]
    q.push({ x: x1, y: y1, kind: 0, seg: i, seg2: -1 })
    q.push({ x: x2, y: y2, kind: 2, seg: i, seg2: -1 })
  }
  let status : Status = { root: None }
  let result : Array[(Double, Double)] = []
  // Track scheduled intersection events to avoid duplicates: a pair (i, j)
  // with i < j is scheduled at most once at a time.
  let scheduled : Map[(Int, Int), (Double, Double)] = Map([])
  let cmp = fn(a : Int, b : Int) -> Int { ctx_cmp(ctx, a, b) }
  while !q.is_empty() {
    let ev = q.pop().unwrap()
    if ev.kind == 0 {
      // Left endpoint: insert and test new neighbours.
      ctx.sweep_x = ev.x
      status.insert(ev.seg, cmp, rng)
      let (pred, succ) = status.neighbours(ev.seg, cmp)
      match pred {
        Some(j) => schedule(ctx, q, norm, scheduled, j, ev.seg, ev.y)
        None => ()
      }
      match succ {
        Some(j) => schedule(ctx, q, norm, scheduled, ev.seg, j, ev.y)
        None => ()
      }
    } else if ev.kind == 2 {
      // Right endpoint: remove and test the newly adjacent pair.
      ctx.sweep_x = ev.x
      let (pred, succ) = status.neighbours(ev.seg, cmp)
      ignore(status.remove(ev.seg, cmp))
      match (pred, succ) {
        (Some(a), Some(b)) => schedule(ctx, q, norm, scheduled, a, b, ev.y)
        _ => ()
      }
    } else {
      // Intersection event: report, swap the two segments, test new pairs.
      let i = ev.seg
      let j = ev.seg2
      // CRITICAL: Use pre-crossing ordering (sweep_x just before the
      // crossing) to find and remove the segments. The treap was built
      // with the pre-crossing comparator; using the post-crossing
      // comparator would cause find_node to search the wrong subtree
      // and fail to locate the nodes.
      ctx.sweep_x = ev.x - SWEEP_DELTA
      let removed_i = status.remove(i, cmp)
      let removed_j = status.remove(j, cmp)
      if removed_i && removed_j {
        // Use post-crossing ordering (sweep_x just after the crossing)
        // to re-insert. At this x, the slope tie-break places the
        // segments in their swapped order.
        ctx.sweep_x = ev.x + SWEEP_DELTA
        status.insert(i, cmp, rng)
        status.insert(j, cmp, rng)
        result.push((ev.x, ev.y))
        // Test new neighbour pairs under the post-crossing ordering.
        let (pi, si) = status.neighbours(i, cmp)
        let (pj, sj) = status.neighbours(j, cmp)
        match pi {
          Some(k) => schedule(ctx, q, norm, scheduled, k, i, ev.y)
          None => ()
        }
        match si {
          Some(k) => schedule(ctx, q, norm, scheduled, i, k, ev.y)
          None => ()
        }
        match pj {
          Some(k) => schedule(ctx, q, norm, scheduled, k, j, ev.y)
          None => ()
        }
        match sj {
          Some(k) => schedule(ctx, q, norm, scheduled, j, k, ev.y)
          None => ()
        }
      } else {
        // Stale event: one or both segments were already removed by a
        // right-endpoint event. Re-insert any that were successfully
        // removed to restore the status to its correct state.
        ctx.sweep_x = ev.x + SWEEP_DELTA
        if removed_i {
          status.insert(i, cmp, rng)
        }
        if removed_j {
          status.insert(j, cmp, rng)
        }
      }
    }
  }
  dedup(result)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
fn approx_eq(a : (Double, Double), b : (Double, Double)) -> Bool {
  let (ax, ay) = a
  let (bx, by) = b
  (ax - bx).abs() < 1.0e-7 && (ay - by).abs() < 1.0e-7
}

///|
fn contains_pt(pts : Array[(Double, Double)], p : (Double, Double)) -> Bool {
  for i = 0; i < pts.length(); i = i + 1 {
    if approx_eq(pts[i], p) {
      return true
    }
  }
  false
}

///|
test "bentley_ottmann: crossing segments" {
  let segs = [(0.0, 0.0, 2.0, 2.0), (0.0, 2.0, 2.0, 0.0)]
  let pts = find_intersections(segs)
  assert_eq(pts.length(), 1)
  assert_true(approx_eq(pts[0], (1.0, 1.0)))
}

///|
test "bentley_ottmann: no intersections" {
  let segs = [(0.0, 0.0, 1.0, 1.0), (3.0, 3.0, 4.0, 4.0)]
  let pts = find_intersections(segs)
  assert_eq(pts.length(), 0)
}

///|
test "bentley_ottmann: multiple crossings at one point" {
  let segs = [(0.0, 0.0, 4.0, 4.0), (0.0, 4.0, 4.0, 0.0), (0.0, 2.0, 4.0, 2.0)]
  let pts = find_intersections(segs)
  assert_eq(pts.length(), 1)
  assert_true(approx_eq(pts[0], (2.0, 2.0)))
}

///|
test "bentley_ottmann: parallel segments" {
  let segs = [(0.0, 0.0, 2.0, 0.0), (0.0, 1.0, 2.0, 1.0)]
  let pts = find_intersections(segs)
  assert_eq(pts.length(), 0)
}

///|
test "bentley_ottmann: single segment" {
  let segs = [(0.0, 0.0, 1.0, 1.0)]
  let pts = find_intersections(segs)
  assert_eq(pts.length(), 0)
}

///|
test "bentley_ottmann: empty input" {
  let segs : Array[(Double, Double, Double, Double)] = []
  let pts = find_intersections(segs)
  assert_eq(pts.length(), 0)
}

///|
test "bentley_ottmann: non-adjacent crossing found via swap" {
  // A rises (0,0)->(10,10), B falls (0,10)->(10,0), C horizontal y=6.
  // A∩B at (5,5) is only found once B and A become adjacent after the
  // B∩C crossing at (4,6) swaps their order. The previous implementation
  // missed (5,5) because it never processed the swap.
  let segs = [
    (0.0, 0.0, 10.0, 10.0),
    (0.0, 10.0, 10.0, 0.0),
    (0.0, 6.0, 10.0, 6.0),
  ]
  let pts = find_intersections(segs)
  assert_eq(pts.length(), 3)
  assert_true(contains_pt(pts, (4.0, 6.0)))
  assert_true(contains_pt(pts, (5.0, 5.0)))
  assert_true(contains_pt(pts, (6.0, 6.0)))
}

///|
test "bentley_ottmann: grid of crossings" {
  // Three rising and three falling diagonals: 9 distinct crossings.
  let segs : Array[(Double, Double, Double, Double)] = []
  for i = 0; i < 3; i = i + 1 {
    segs.push((0.0, i.to_double(), 10.0, (i + 10).to_double()))
    segs.push((0.0, (i + 10).to_double(), 10.0, i.to_double()))
  }
  let pts = find_intersections(segs)
  assert_eq(pts.length(), 9)
}

///|
test "bentley_ottmann: disjoint crossing pairs" {
  // Two independent X shapes that do not interact.
  let segs = [
    (0.0, 0.0, 4.0, 4.0),
    (0.0, 4.0, 4.0, 0.0),
    (10.0, 0.0, 14.0, 4.0),
    (10.0, 4.0, 14.0, 0.0),
  ]
  let pts = find_intersections(segs)
  assert_eq(pts.length(), 2)
  assert_true(contains_pt(pts, (2.0, 2.0)))
  assert_true(contains_pt(pts, (12.0, 2.0)))
}

///|
test "bentley_ottmann: nested segments share endpoint" {
  // Two segments sharing the left endpoint, diverging, then a third crossing
  // only the upper one.
  let segs = [
    (0.0, 0.0, 10.0, 10.0), // upper
    (0.0, 0.0, 10.0, 0.0), // lower (horizontal)
    (0.0, 5.0, 10.0, 5.0), // crosses upper at (5,5), parallel to lower
  ]
  let pts = find_intersections(segs)
  assert_eq(pts.length(), 1)
  assert_true(contains_pt(pts, (5.0, 5.0)))
}
