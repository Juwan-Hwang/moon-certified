/// Shared geometry utilities: 2D point type and geometric helper functions.
///
/// These primitives are used by `convex_hull`, `rotating_calipers`, `kd_tree`,
/// `closest_pair`, and `segment_ops`. Centralising them here eliminates code
/// duplication and — critically — ensures that all geometry packages share a
/// single `Point` type, so the output of one (e.g. `convex_hull`) can be fed
/// directly into another (e.g. `rotating_calipers`) without conversion.
///
/// **Overflow safety.** `dist2` and `cross64` use `Int64` internally so that
/// coordinates up to ~3037000499 per axis keep every intermediate product
/// below `Int64::max`.

///|
/// A 2D point with integer coordinates.
///
/// Fields are public by default in MoonBit, so callers in any package can
/// read `.x` and `.y` and use struct literals `{ x: ..., y: ... }` to
/// construct points.
pub struct Point {
  x : Int
  y : Int
}

///|
/// Construct a [`Point`] with the given coordinates.
pub fn point(x : Int, y : Int) -> Point {
  { x, y }
}

///|
/// Squared Euclidean distance between two points (avoids floating point).
///
/// Returns `Int64` to prevent overflow for large coordinates — using `Int`
/// would silently clamp far-apart collinear points to the same value,
/// corrupting polar-angle sorts and nearest-neighbour comparisons.
pub fn dist2(a : Point, b : Point) -> Int64 {
  let dx = a.x.to_int64() - b.x.to_int64()
  let dy = a.y.to_int64() - b.y.to_int64()
  dx * dx + dy * dy
}

///|
/// 2D cross product of vectors `o->a` and `o->b`, returned as `Int64`.
///
/// Positive => `b` is counterclockwise from `a`; negative => clockwise;
/// zero => collinear. Uses `Int64` throughout to prevent overflow.
pub fn cross64(o : Point, a : Point, b : Point) -> Int64 {
  let ax = a.x.to_int64() - o.x.to_int64()
  let ay = a.y.to_int64() - o.y.to_int64()
  let bx = b.x.to_int64() - o.x.to_int64()
  let by = b.y.to_int64() - o.y.to_int64()
  ax * by - ay * bx
}

///|
/// 2D cross product clamped to `Int` range.
///
/// **Intentional clamping** — not a silent failure:
/// - Returns `1` when the true cross product overflows positively
///   (the orientation is definitely counterclockwise).
/// - Returns `-1` when it overflows negatively
///   (the orientation is definitely clockwise).
/// - Returns the exact `Int` result when it fits in 32-bit range.
///
/// This sign-preserving clamp is designed for sorting comparators that only
/// need the **sign** of the cross product (CCW/CW/collinear). The magnitude
/// is lost on overflow, but the sign — which is all that matters for
/// orientation tests — is always correct.
///
/// **When you need the exact magnitude**, use [`cross64`] instead, which
/// returns `Int64` and never clamps.
pub fn cross(o : Point, a : Point, b : Point) -> Int {
  let result = cross64(o, a, b)
  if result > 2147483647L {
    1
  } else if result < -2147483648L {
    -1
  } else {
    result.to_int()
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "geometry_utils: point construction and field access" {
  let p = point(3, 4)
  assert_eq(p.x, 3)
  assert_eq(p.y, 4)
  let q : Point = { x: 5, y: 6 }
  assert_eq(q.x, 5)
  assert_eq(q.y, 6)
}

///|
test "geometry_utils: point with negative coordinates" {
  let p = point(-100, -200)
  assert_eq(p.x, -100)
  assert_eq(p.y, -200)
}

///|
test "geometry_utils: point at origin" {
  let p = point(0, 0)
  assert_eq(p.x, 0)
  assert_eq(p.y, 0)
}

///|
test "geometry_utils: dist2 basic" {
  let a = point(0, 0)
  let b = point(3, 4)
  assert_eq(dist2(a, b), 25L) // 3² + 4² = 25
}

///|
test "geometry_utils: dist2 same point" {
  let a = point(5, 5)
  assert_eq(dist2(a, a), 0L)
}

///|
test "geometry_utils: dist2 negative coordinates" {
  let a = point(-3, -4)
  let b = point(0, 0)
  assert_eq(dist2(a, b), 25L)
}

///|
test "geometry_utils: dist2 large coordinates (Int64 overflow safety)" {
  // Coordinates near Int32 max — dist2 uses Int64 to prevent overflow.
  let a = point(2000000000, 2000000000)
  let b = point(0, 0)
  let d2 = dist2(a, b)
  // 2e9² + 2e9² = 8e18, well within Int64 range but would overflow Int32.
  assert_true(d2 > 0L)
}

///|
test "geometry_utils: dist2 symmetric" {
  let a = point(1, 2)
  let b = point(4, 6)
  assert_eq(dist2(a, b), dist2(b, a))
}

///|
test "geometry_utils: cross64 counterclockwise" {
  // o=(0,0), a=(1,0), b=(0,1) → b is CCW from a
  let o = point(0, 0)
  let a = point(1, 0)
  let b = point(0, 1)
  let c = cross64(o, a, b)
  assert_true(c > 0L) // Positive = counterclockwise
}

///|
test "geometry_utils: cross64 clockwise" {
  // o=(0,0), a=(0,1), b=(1,0) → b is CW from a
  let o = point(0, 0)
  let a = point(0, 1)
  let b = point(1, 0)
  let c = cross64(o, a, b)
  assert_true(c < 0L) // Negative = clockwise
}

///|
test "geometry_utils: cross64 collinear" {
  // o=(0,0), a=(1,1), b=(2,2) → collinear
  let o = point(0, 0)
  let a = point(1, 1)
  let b = point(2, 2)
  let c = cross64(o, a, b)
  assert_eq(c, 0L) // Zero = collinear
}

///|
test "geometry_utils: cross64 with negative origin" {
  let o = point(-1, -1)
  let a = point(0, 0)
  let b = point(1, 0)
  let c = cross64(o, a, b)
  // o→a = (1,1), o→b = (2,1), cross = 1*1 - 1*2 = -1
  assert_eq(c, -1L)
}

///|
test "geometry_utils: cross64 large coordinates (overflow safety)" {
  let o = point(0, 0)
  let a = point(2000000000, 0)
  let b = point(0, 2000000000)
  let c = cross64(o, a, b)
  // 2e9 * 2e9 = 4e18, well within Int64 range
  assert_true(c > 0L)
  assert_eq(c, 4000000000000000000L)
}

///|
test "geometry_utils: cross clamped returns sign" {
  let o = point(0, 0)
  let a = point(1, 0)
  let b = point(0, 1)
  assert_eq(cross(o, a, b), 1) // CCW → positive
}

///|
test "geometry_utils: cross clockwise returns negative" {
  let o = point(0, 0)
  let a = point(0, 1)
  let b = point(1, 0)
  assert_eq(cross(o, a, b), -1) // CW → negative
}

///|
test "geometry_utils: cross collinear returns zero" {
  let o = point(0, 0)
  let a = point(1, 1)
  let b = point(2, 2)
  assert_eq(cross(o, a, b), 0) // Collinear → zero
}

///|
test "geometry_utils: cross overflow clamped to +1" {
  // Cross product > Int32::max → should return 1
  let o = point(0, 0)
  let a = point(100000, 0)
  let b = point(0, 100000)
  // cross = 100000 * 100000 = 10^10 > Int32::max (2147483647)
  assert_eq(cross(o, a, b), 1)
}

///|
test "geometry_utils: cross overflow clamped to -1" {
  // Cross product < Int32::min → should return -1
  let o = point(0, 0)
  let a = point(0, 100000)
  let b = point(100000, 0)
  // cross = -(100000 * 100000) = -10^10 < Int32::min
  assert_eq(cross(o, a, b), -1)
}

///|
test "geometry_utils: cross within Int range returns exact value" {
  let o = point(0, 0)
  let a = point(3, 0)
  let b = point(0, 4)
  // cross = 3 * 4 - 0 * 0 = 12
  assert_eq(cross(o, a, b), 12)
}
