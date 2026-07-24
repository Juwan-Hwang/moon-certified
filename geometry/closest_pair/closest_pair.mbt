/// Closest pair of points in 2D via divide and conquer.
///
/// Finds the minimum squared Euclidean distance between any two distinct
/// points, using the classic O(n log n) plane-sweep recursion:
///
/// 1. Sort the points once by x (`Px`) and once by y (`Py`).
/// 2. Recurse on the left and right halves of the x-sorted order. Each half
///    receives its own y-sorted companion, produced in O(n) by a single
///    linear sweep that preserves y-order (see [`closest_rec`]).
/// 3. Combine: keep points whose x lies within `sqrt(d)` of the dividing
///    line (the "strip"), already y-sorted. For each strip point, scan
///    forward only while the y-gap stays below the running best; the
///    standard packing argument bounds this at 7 neighbours, so the combine
///    is linear.
///
/// Total work: two O(n log n) sorts plus O(n) per level across O(log n)
/// levels, i.e. O(n log n) time and O(n) space.
///
/// **Overflow safety.** All squared distances and the strip filters use
/// `Int64`. Coordinates up to ~3037000499 per axis keep a single coordinate
/// square below `Int64::max`; whenever every pairwise squared distance fits
/// in `Int64`, so does every intermediate quantity here.
///
/// Returns `None` for fewer than 2 points, otherwise `Some(min_dist_sq)`.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

// @geometry_utils.Point and point are imported from @geometry_utils.
// This eliminates code duplication across geometry packages.

/// Convenience constructor — delegates to @geometry_utils.point.
pub fn point(x : Int, y : Int) -> @geometry_utils.Point {
  @geometry_utils.point(x, y)
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Sentinel "infinity" for the internal recursion: no pair found yet.
/// It is only ever returned by base cases covering fewer than 2 points,
/// which the top-level entry converts into `None`.
let int64_max : Int64 = 9223372036854775807L



/// Three-way comparator by (x, then y). Returns < 0 when `a` precedes `b`.
/// Comparisons (not arithmetic) are used so coordinates near the Int32
/// extremes compare correctly.
fn cmp_xy(a : @geometry_utils.Point, b : @geometry_utils.Point) -> Int {
  let ax = a.x.to_int64()
  let bx = b.x.to_int64()
  if ax != bx {
    if ax < bx {
      -1
    } else {
      1
    }
  } else {
    let ay = a.y.to_int64()
    let by = b.y.to_int64()
    if ay < by {
      -1
    } else if ay > by {
      1
    } else {
      0
    }
  }
}

/// Three-way comparator by (y, then x).
fn cmp_yx(a : @geometry_utils.Point, b : @geometry_utils.Point) -> Int {
  let ay = a.y.to_int64()
  let by = b.y.to_int64()
  if ay != by {
    if ay < by {
      -1
    } else {
      1
    }
  } else {
    let ax = a.x.to_int64()
    let bx = b.x.to_int64()
    if ax < bx {
      -1
    } else if ax > bx {
      1
    } else {
      0
    }
  }
}

/// Stable merge sort of `pts[lo, hi)` by comparator `cmp`, in place, using
/// `tmp` as scratch space of the same length.
fn msort(
  pts : FixedArray[@geometry_utils.Point],
  tmp : FixedArray[@geometry_utils.Point],
  lo : Int,
  hi : Int,
  cmp : (@geometry_utils.Point, @geometry_utils.Point) -> Int,
) -> Unit {
  let len = hi - lo
  if len <= 1 {
    return
  }
  let mid = lo + len / 2
  msort(pts, tmp, lo, mid, cmp)
  msort(pts, tmp, mid, hi, cmp)
  let mut i = lo
  let mut j = mid
  for k = lo; k < hi; k = k + 1 {
    if j >= hi || (i < mid && cmp(pts[i], pts[j]) <= 0) {
      tmp[k] = pts[i]
      i = i + 1
    } else {
      tmp[k] = pts[j]
      j = j + 1
    }
  }
  for k = lo; k < hi; k = k + 1 {
    pts[k] = tmp[k]
  }
}

/// Brute-force minimum squared distance over `Px[lo, hi)`.
/// Returns `int64_max` when the range holds fewer than 2 points.
fn brute_force(pts : FixedArray[@geometry_utils.Point], lo : Int, hi : Int) -> Int64 {
  let n = hi - lo
  if n < 2 {
    return int64_max
  }
  let mut best = int64_max
  for i = lo; i < hi; i = i + 1 {
    for j = i + 1; j < hi; j = j + 1 {
      let d = @geometry_utils.dist2(pts[i], pts[j])
      if d < best {
        best = d
      }
    }
  }
  best
}

// ---------------------------------------------------------------------------
// Divide and conquer
// ---------------------------------------------------------------------------

/// Recursive closest-pair over `px[lo, hi)` (x-sorted) with the companion
/// `py` (y-sorted, the same point set). Returns the minimum squared
/// distance, or `int64_max` if the range has fewer than 2 points.
///
/// The y-sorted companion is repartitioned in O(n) per level while preserving
/// y-order. The split keeps a valid separator: every point placed in the left
/// half has `x <= mid_x` and every point in the right half has `x >= mid_x`.
/// Points with `x < mid_x` must go left and points with `x > mid_x` must go
/// right; the remaining `x == mid_x` points are split so the left half reaches
/// exactly `left_size` (the first `need_left` of them in y-order go left). This
/// guarantees that any cross pair closer than `d` has both endpoints inside the
/// strip, so the combine step is correct.
fn closest_rec(
  px : FixedArray[@geometry_utils.Point],
  lo : Int,
  hi : Int,
  py : FixedArray[@geometry_utils.Point],
) -> Int64 {
  let n = hi - lo
  if n <= 3 {
    return brute_force(px, lo, hi)
  }
  let left_size = n / 2
  let mid_idx = lo + left_size
  let mid_x = px[mid_idx].x
  let right_size = n - left_size
  // Partition py (y-sorted) into py_l (left half) and py_r (right half)
  // while preserving y-order. Points with x < mid_x must go left and points
  // with x > mid_x must go right; only points with x == mid_x are split.
  // Because py is y-sorted (so the three classes are interleaved), we first
  // count how many x == mid_x points the left half still needs, then assign
  // them in a single y-ordered pass.
  let mut strict_left = 0
  for i = 0; i < n; i = i + 1 {
    if py[i].x < mid_x {
      strict_left = strict_left + 1
    }
  }
  let need_left = left_size - strict_left
  let py_l : FixedArray[@geometry_utils.Point] = FixedArray::make(left_size, py[0])
  let py_r : FixedArray[@geometry_utils.Point] = FixedArray::make(right_size, py[0])
  let mut li = 0
  let mut ri = 0
  let mut eq_left = 0
  for i = 0; i < n; i = i + 1 {
    let p = py[i]
    if p.x < mid_x {
      py_l[li] = p
      li = li + 1
    } else if p.x > mid_x {
      py_r[ri] = p
      ri = ri + 1
    } else if eq_left < need_left {
      py_l[li] = p
      li = li + 1
      eq_left = eq_left + 1
    } else {
      py_r[ri] = p
      ri = ri + 1
    }
  }
  let dl = closest_rec(px, lo, mid_idx, py_l)
  let dr = closest_rec(px, mid_idx, hi, py_r)
  let d = if dl <= dr {
    dl
  } else {
    dr
  }
  let mut best = d
  // Strip: points whose x is within sqrt(d) of the dividing line. Because py
  // is y-sorted, the strip is y-sorted too. For each point we scan forward
  // only while the y-gap stays below the running best; the classic packing
  // argument bounds this at 7 neighbours, so the combine is O(n).
  let strip : Array[@geometry_utils.Point] = []
  let mid_x64 = mid_x.to_int64()
  for i = 0; i < n; i = i + 1 {
    let dx = py[i].x.to_int64() - mid_x64
    if dx * dx < d {
      strip.push(py[i])
    }
  }
  let m = strip.length()
  for i = 0; i < m; i = i + 1 {
    let pi = strip[i]
    let mut j = i + 1
    while j < m {
      let dy = strip[j].y.to_int64() - pi.y.to_int64()
      if dy * dy >= best {
        break
      }
      let dd = @geometry_utils.dist2(pi, strip[j])
      if dd < best {
        best = dd
      }
      j = j + 1
    }
  }
  best
}

/// Minimum squared Euclidean distance among any two distinct points.
///
/// Returns `None` when `points` has fewer than 2 elements, otherwise
/// `Some(min_dist_sq)`. Runs in O(n log n) time and O(n) space. The input
/// array is not modified.
pub fn closest_pair(points : Array[@geometry_utils.Point]) -> Int64? {
  let n = points.length()
  if n < 2 {
    return None
  }
  // x-sorted copy (px) and y-sorted copy (py); the input array is untouched.
  let px : FixedArray[@geometry_utils.Point] = FixedArray::makei(n, fn(i) { points[i] })
  let tmp_x : FixedArray[@geometry_utils.Point] = FixedArray::make(n, points[0])
  msort(px, tmp_x, 0, n, cmp_xy)
  let py : FixedArray[@geometry_utils.Point] = FixedArray::makei(n, fn(i) { points[i] })
  let tmp_y : FixedArray[@geometry_utils.Point] = FixedArray::make(n, points[0])
  msort(py, tmp_y, 0, n, cmp_yx)
  Some(closest_rec(px, 0, n, py))
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

/// Brute-force minimum squared distance over an array, for cross-checking.
fn brute_force_closest(points : Array[@geometry_utils.Point]) -> Int64? {
  let n = points.length()
  if n < 2 {
    return None
  }
  let mut best = int64_max
  for i = 0; i < n; i = i + 1 {
    for j = i + 1; j < n; j = j + 1 {
      let d = @geometry_utils.dist2(points[i], points[j])
      if d < best {
        best = d
      }
    }
  }
  Some(best)
}

test "closest_pair: empty" {
  let pts : Array[@geometry_utils.Point] = []
  assert_true(closest_pair(pts) is None)
}

test "closest_pair: single point" {
  let pts = [point(5, 5)]
  assert_true(closest_pair(pts) is None)
}

test "closest_pair: two points" {
  let pts = [point(0, 0), point(3, 4)]
  // 3² + 4² = 25
  assert_eq(closest_pair(pts), Some(25L))
}

test "closest_pair: three collinear points" {
  let pts = [point(0, 0), point(1, 0), point(2, 0)]
  // Closest pair: adjacent points, dist² = 1.
  assert_eq(closest_pair(pts), Some(1L))
}

test "closest_pair: triangle" {
  let pts = [point(0, 0), point(4, 0), point(0, 3)]
  // Sides: 4, 3, 5 → squared 16, 9, 25. Min = 9.
  assert_eq(closest_pair(pts), Some(9L))
}

test "closest_pair: duplicate points" {
  let pts = [point(2, 2), point(5, 5), point(2, 2)]
  // Two coincident points → dist² = 0.
  assert_eq(closest_pair(pts), Some(0L))
}

test "closest_pair: all identical points" {
  let pts = [point(7, 7), point(7, 7), point(7, 7), point(7, 7)]
  assert_eq(closest_pair(pts), Some(0L))
}

test "closest_pair: negative coordinates" {
  let pts = [point(-3, -4), point(-1, -1), point(-2, -5), point(0, 0)]
  assert_eq(closest_pair(pts), brute_force_closest(pts))
  // (0,0) vs (-1,-1): 1+1 = 2 is the minimum.
  assert_eq(closest_pair(pts), Some(2L))
}

test "closest_pair: closest pair straddles the dividing line" {
  // Left cluster and right cluster are each internally far apart; the only
  // close pair lies across the median.
  let pts = [
    point(0, 0), point(0, 10), point(0, 20),
    point(100, 0), point(100, 10), point(100, 20),
    point(49, 5), point(51, 5),
  ]
  // (49,5)-(51,5): dist² = 4. Everything else is >= 100.
  assert_eq(closest_pair(pts), Some(4L))
  assert_eq(closest_pair(pts), brute_force_closest(pts))
}

test "closest_pair: square grid" {
  // 3×3 grid with spacing 10. Minimum spacing squared = 100.
  let pts : Array[@geometry_utils.Point] = []
  for i = 0; i < 3; i = i + 1 {
    for j = 0; j < 3; j = j + 1 {
      pts.push(point(i * 10, j * 10))
    }
  }
  assert_eq(closest_pair(pts), Some(100L))
  assert_eq(closest_pair(pts), brute_force_closest(pts))
}

test "closest_pair: large random set vs brute force" {
  let pts : Array[@geometry_utils.Point] = []
  let mut st = 987654
  for i = 0; i < 200; i = i + 1 {
    st = (st * 1103515245 + 12345) % 2147483647
    let x = st % 1000 - 500
    st = (st * 1103515245 + 12345) % 2147483647
    let y = st % 1000 - 500
    pts.push(point(x, y))
  }
  assert_eq(closest_pair(pts), brute_force_closest(pts))
}

test "closest_pair: large coordinates (overflow safety)" {
  // Coordinates up to 10^8: squared differences stay well within Int64.
  let pts : Array[@geometry_utils.Point] = []
  let mut st = 4242
  for i = 0; i < 60; i = i + 1 {
    st = (st * 1103515245 + 12345) % 2147483647
    let x = st % 100000000
    st = (st * 1103515245 + 12345) % 2147483647
    let y = st % 100000000
    pts.push(point(x, y))
  }
  assert_eq(closest_pair(pts), brute_force_closest(pts))
}

test "closest_pair: points on a vertical line" {
  let pts = [point(5, 0), point(5, 3), point(5, 1), point(5, 2), point(5, 10)]
  // Sorted by y: 0,1,2,3,10. Min gap = 1 (squared 1).
  assert_eq(closest_pair(pts), Some(1L))
  assert_eq(closest_pair(pts), brute_force_closest(pts))
}
