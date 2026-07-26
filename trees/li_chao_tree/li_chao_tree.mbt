/// Li Chao Tree (李超树) for line segment queries.
///
/// A segment tree that maintains a set of lines `y = m·x + b` and supports
/// querying the **minimum** (or maximum) `y`-value at any point `x` in
/// O(log C), where C is the coordinate range.
///
/// ## Algorithm
///
/// Each tree node covers a range `[lo, hi]` of x-coordinates and stores a
/// **dominant line** — the line that is "best" (minimum for a min-tree) at
/// the midpoint `mid = (lo + hi) / 2`. When inserting a new line, we compare
/// it with the existing dominant line at the midpoint:
///
/// - If the new line is better at the midpoint, swap them.
/// - Now the stored line is better at `mid`. The new (swapped) line can only
///   be better on one side: if it's better at `lo`, recurse left; if better
///   at `hi`, recurse right. If it's worse everywhere, discard it.
///
/// This ensures each node stores at most one line, giving O(log C) insertion
/// and query.
///
/// ## Complexity
///
/// - Insert a line: O(log C)
/// - Query at a point: O(log C)
/// - Space: O(C) for the full tree (but typically much less since only
///   touched nodes are materialised)
///
/// ## Overflow
///
/// All arithmetic is performed in `Int64` to prevent overflow when `m`, `x`,
/// and `b` are large. The product `m * x` can reach ~2^62 before approaching
/// `Int64` limits.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

///|
/// A line `y = m·x + b` with Int64 coefficients.
pub struct Line {
  m : Int64
  b : Int64
}

///|
/// Construct a line `y = m·x + b`.
pub fn line(m : Int64, b : Int64) -> Line {
  { m, b }
}

///|
/// Evaluate the line at `x`.
pub fn eval(l : Line, x : Int64) -> Int64 {
  l.m * x + l.b
}

///|
/// A Li Chao segment tree for **minimum** queries.
///
/// Stores lines and supports querying the minimum y-value at any point x
/// in the range `[x_lo, x_hi]`.
pub struct LiChaoTreeMin {
  x_lo : Int64
  x_hi : Int64
  // Tree stored as an array. Node i covers a sub-range; stores the dominant
  // line (the one that is minimum at the midpoint of that range).
  // Initialised with a "very large" line so any real line dominates it.
  lines : Array[Line]
  has_line : Array[Bool]
  size : Int // number of nodes (power of 2 * 2 - 1, approximately)
}

///|
/// A Li Chao segment tree for **maximum** queries.
pub struct LiChaoTreeMax {
  x_lo : Int64
  x_hi : Int64
  lines : Array[Line]
  has_line : Array[Bool]
  size : Int
}

// ---------------------------------------------------------------------------
// Min tree
// ---------------------------------------------------------------------------

///|
/// A sentinel line that evaluates to Int64::MAX, so any real line is smaller.
fn max_line() -> Line {
  { m: 0L, b: 9223372036854775807L }
}

///|
/// Create a Li Chao tree for minimum queries over x-range `[lo, hi]`.
pub fn new_min(lo : Int64, hi : Int64) -> LiChaoTreeMin {
  // Compute the number of leaves needed (power of 2 covering [lo, hi]).
  let range = hi - lo + 1L
  let mut leaves = 1
  while leaves.to_int64() < range {
    leaves = leaves * 2
  }
  let size = leaves * 2
  let lines : Array[Line] = []
  let has_line : Array[Bool] = []
  for i = 0; i < size; i = i + 1 {
    lines.push(max_line())
    has_line.push(false)
  }
  { x_lo: lo, x_hi: hi, lines, has_line, size }
}

///|
/// Insert a line into the min tree.
pub fn insert_min(tree : LiChaoTreeMin, l : Line) -> Unit {
  insert_min_rec(tree, 1, tree.x_lo, tree.x_hi, l)
}

///|
fn insert_min_rec(
  tree : LiChaoTreeMin,
  node : Int,
  lo : Int64,
  hi : Int64,
  new_line : Line,
) -> Unit {
  if lo > hi {
    return
  }
  if !tree.has_line[node] {
    tree.lines[node] = new_line
    tree.has_line[node] = true
    return
  }
  let mid = lo + (hi - lo) / 2L
  let cur = tree.lines[node]
  // Compare at midpoint.
  if eval(new_line, mid) < eval(cur, mid) {
    // New line is better at mid; swap so cur is the new line to push down.
    tree.lines[node] = new_line
    let tmp = cur
    // Now `tmp` (old dominant) might be better on one side.
    if lo == hi {
      return
    }
    // Check which side `tmp` might be better on.
    if eval(tmp, lo) < eval(new_line, lo) {
      insert_min_rec(tree, node * 2, lo, mid, tmp)
    } else if eval(tmp, hi) < eval(new_line, hi) {
      insert_min_rec(tree, node * 2 + 1, mid + 1L, hi, tmp)
    }
  } else {
    // Current line is better at mid; new line might be better on one side.
    if lo == hi {
      return
    }
    if eval(new_line, lo) < eval(cur, lo) {
      insert_min_rec(tree, node * 2, lo, mid, new_line)
    } else if eval(new_line, hi) < eval(cur, hi) {
      insert_min_rec(tree, node * 2 + 1, mid + 1L, hi, new_line)
    }
  }
}

///|
/// Query the minimum y-value at point `x`.
pub fn query_min(tree : LiChaoTreeMin, x : Int64) -> Int64 {
  query_min_rec(tree, 1, tree.x_lo, tree.x_hi, x)
}

///|
fn query_min_rec(
  tree : LiChaoTreeMin,
  node : Int,
  lo : Int64,
  hi : Int64,
  x : Int64,
) -> Int64 {
  let best = if tree.has_line[node] {
    eval(tree.lines[node], x)
  } else {
    9223372036854775807L
  }
  if lo == hi {
    return best
  }
  let mid = lo + (hi - lo) / 2L
  if x <= mid {
    let child_best = query_min_rec(tree, node * 2, lo, mid, x)
    if child_best < best {
      child_best
    } else {
      best
    }
  } else {
    let child_best = query_min_rec(tree, node * 2 + 1, mid + 1L, hi, x)
    if child_best < best {
      child_best
    } else {
      best
    }
  }
}

// ---------------------------------------------------------------------------
// Max tree
// ---------------------------------------------------------------------------

///|
/// A sentinel line that evaluates to Int64::MIN, so any real line is larger.
fn min_line() -> Line {
  { m: 0L, b: -9223372036854775808L }
}

///|
/// Create a Li Chao tree for maximum queries over x-range `[lo, hi]`.
pub fn new_max(lo : Int64, hi : Int64) -> LiChaoTreeMax {
  let range = hi - lo + 1L
  let mut leaves = 1
  while leaves.to_int64() < range {
    leaves = leaves * 2
  }
  let size = leaves * 2
  let lines : Array[Line] = []
  let has_line : Array[Bool] = []
  for i = 0; i < size; i = i + 1 {
    lines.push(min_line())
    has_line.push(false)
  }
  { x_lo: lo, x_hi: hi, lines, has_line, size }
}

///|
/// Insert a line into the max tree.
pub fn insert_max(tree : LiChaoTreeMax, l : Line) -> Unit {
  insert_max_rec(tree, 1, tree.x_lo, tree.x_hi, l)
}

///|
fn insert_max_rec(
  tree : LiChaoTreeMax,
  node : Int,
  lo : Int64,
  hi : Int64,
  new_line : Line,
) -> Unit {
  if lo > hi {
    return
  }
  if !tree.has_line[node] {
    tree.lines[node] = new_line
    tree.has_line[node] = true
    return
  }
  let mid = lo + (hi - lo) / 2L
  let cur = tree.lines[node]
  if eval(new_line, mid) > eval(cur, mid) {
    tree.lines[node] = new_line
    let tmp = cur
    if lo == hi {
      return
    }
    if eval(tmp, lo) > eval(new_line, lo) {
      insert_max_rec(tree, node * 2, lo, mid, tmp)
    } else if eval(tmp, hi) > eval(new_line, hi) {
      insert_max_rec(tree, node * 2 + 1, mid + 1L, hi, tmp)
    }
  } else {
    if lo == hi {
      return
    }
    if eval(new_line, lo) > eval(cur, lo) {
      insert_max_rec(tree, node * 2, lo, mid, new_line)
    } else if eval(new_line, hi) > eval(cur, hi) {
      insert_max_rec(tree, node * 2 + 1, mid + 1L, hi, new_line)
    }
  }
}

///|
/// Query the maximum y-value at point `x`.
pub fn query_max(tree : LiChaoTreeMax, x : Int64) -> Int64 {
  query_max_rec(tree, 1, tree.x_lo, tree.x_hi, x)
}

///|
fn query_max_rec(
  tree : LiChaoTreeMax,
  node : Int,
  lo : Int64,
  hi : Int64,
  x : Int64,
) -> Int64 {
  let best = if tree.has_line[node] {
    eval(tree.lines[node], x)
  } else {
    -9223372036854775808L
  }
  if lo == hi {
    return best
  }
  let mid = lo + (hi - lo) / 2L
  if x <= mid {
    let child_best = query_max_rec(tree, node * 2, lo, mid, x)
    if child_best > best {
      child_best
    } else {
      best
    }
  } else {
    let child_best = query_max_rec(tree, node * 2 + 1, mid + 1L, hi, x)
    if child_best > best {
      child_best
    } else {
      best
    }
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "li_chao_min: single line" {
  let t = new_min(0L, 100L)
  insert_min(t, line(2L, 1L)) // y = 2x + 1
  assert_eq(query_min(t, 0L), 1L)
  assert_eq(query_min(t, 50L), 101L)
  assert_eq(query_min(t, 100L), 201L)
}

///|
test "li_chao_min: two intersecting lines" {
  let t = new_min(0L, 100L)
  // y = x and y = 100 - x; they intersect at x = 50, y = 50
  insert_min(t, line(1L, 0L)) // y = x
  insert_min(t, line(-1L, 100L)) // y = 100 - x
  // At x=0: min(0, 100) = 0
  assert_eq(query_min(t, 0L), 0L)
  // At x=50: min(50, 50) = 50
  assert_eq(query_min(t, 50L), 50L)
  // At x=100: min(100, 0) = 0
  assert_eq(query_min(t, 100L), 0L)
  // At x=25: min(25, 75) = 25
  assert_eq(query_min(t, 25L), 25L)
  // At x=75: min(75, 25) = 25
  assert_eq(query_min(t, 75L), 25L)
}

///|
test "li_chao_min: many lines" {
  let t = new_min(0L, 1000L)
  // Insert y = i*x for i = 1..10
  for i = 1L; i <= 10L; i = i + 1L {
    insert_min(t, line(i, 0L))
  }
  // At x=0, all lines evaluate to 0, so min is 0
  assert_eq(query_min(t, 0L), 0L)
  // At x=1, min is 1 (from y = 1*x)
  assert_eq(query_min(t, 1L), 1L)
  // At x=100, min is 100 (from y = 1*x)
  assert_eq(query_min(t, 100L), 100L)
}

///|
test "li_chao_min: parallel lines" {
  let t = new_min(0L, 100L)
  insert_min(t, line(1L, 10L)) // y = x + 10
  insert_min(t, line(1L, 5L)) // y = x + 5
  insert_min(t, line(1L, 20L)) // y = x + 20
  // The minimum should always be y = x + 5
  assert_eq(query_min(t, 0L), 5L)
  assert_eq(query_min(t, 50L), 55L)
  assert_eq(query_min(t, 100L), 105L)
}

///|
test "li_chao_max: single line" {
  let t = new_max(0L, 100L)
  insert_max(t, line(3L, -5L)) // y = 3x - 5
  assert_eq(query_max(t, 0L), -5L)
  assert_eq(query_max(t, 33L), 94L)
  assert_eq(query_max(t, 100L), 295L)
}

///|
test "li_chao_max: two intersecting lines" {
  let t = new_max(0L, 100L)
  insert_max(t, line(1L, 0L)) // y = x
  insert_max(t, line(-1L, 100L)) // y = 100 - x
  // At x=0: max(0, 100) = 100
  assert_eq(query_max(t, 0L), 100L)
  // At x=50: max(50, 50) = 50
  assert_eq(query_max(t, 50L), 50L)
  // At x=100: max(100, 0) = 100
  assert_eq(query_max(t, 100L), 100L)
}

///|
test "li_chao_max: many lines" {
  let t = new_max(0L, 1000L)
  for i = 1L; i <= 10L; i = i + 1L {
    insert_max(t, line(i, 0L))
  }
  // At x=1, max is 10 (from y = 10*x)
  assert_eq(query_max(t, 1L), 10L)
  // At x=100, max is 1000 (from y = 10*x)
  assert_eq(query_max(t, 100L), 1000L)
}

///|
test "li_chao_min: brute force verification" {
  let t = new_min(0L, 100L)
  let lines : Array[Line] = []
  // Insert 20 random-ish lines.
  for i = 0; i < 20; i = i + 1 {
    let m = ((i * 7 + 3) % 10).to_int64()
    let b = ((i * 13 + 5) % 50).to_int64()
    let l = line(m, b)
    lines.push(l)
    insert_min(t, l)
  }
  // Query at several points and verify against brute force.
  for x = 0L; x <= 100L; x = x + 7L {
    let tree_val = query_min(t, x)
    let mut brute_min = 9223372036854775807L
    for i = 0; i < lines.length(); i = i + 1 {
      let v = eval(lines[i], x)
      if v < brute_min {
        brute_min = v
      }
    }
    assert_eq(tree_val, brute_min)
  }
}

///|
test "li_chao_max: brute force verification" {
  let t = new_max(0L, 100L)
  let lines : Array[Line] = []
  for i = 0; i < 20; i = i + 1 {
    let m = ((i * 7 + 3) % 10).to_int64()
    let b = ((i * 13 + 5) % 50).to_int64()
    let l = line(m, b)
    lines.push(l)
    insert_max(t, l)
  }
  for x = 0L; x <= 100L; x = x + 7L {
    let tree_val = query_max(t, x)
    let mut brute_max = -9223372036854775808L
    for i = 0; i < lines.length(); i = i + 1 {
      let v = eval(lines[i], x)
      if v > brute_max {
        brute_max = v
      }
    }
    assert_eq(tree_val, brute_max)
  }
}

///|
test "li_chao_min: single point range" {
  let t = new_min(5L, 5L)
  insert_min(t, line(2L, 3L)) // y = 2x + 3
  assert_eq(query_min(t, 5L), 13L)
}

///|
test "li_chao_max: negative slope" {
  let t = new_max(-50L, 50L)
  insert_max(t, line(-1L, 0L)) // y = -x
  assert_eq(query_max(t, -50L), 50L)
  assert_eq(query_max(t, 0L), 0L)
  assert_eq(query_max(t, 50L), -50L)
}
