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

/// A 2D point with integer coordinates.
///
/// Fields are public by default in MoonBit, so callers in any package can
/// read `.x` and `.y` and use struct literals `{ x: ..., y: ... }` to
/// construct points.
pub struct Point {
  x : Int
  y : Int
}

/// Construct a [`Point`] with the given coordinates.
pub fn point(x : Int, y : Int) -> Point {
  { x, y }
}

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

/// 2D cross product clamped to `Int` range.
///
/// Returns 1 when the true cross product overflows positively (definitely
/// counterclockwise), -1 when it overflows negatively (definitely clockwise),
/// and the exact `Int` result otherwise. This is the version needed by
/// sorting comparators that require an `Int` sign, not the full `Int64`
/// magnitude.
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
