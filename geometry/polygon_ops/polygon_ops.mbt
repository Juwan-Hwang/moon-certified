///|
/// Polygon operations: clipping, triangulation, area, point-in-polygon.
/// All coordinates are integers. No abort() — errors return empty arrays.
fn signed_area2(poly : Array[(Int, Int)]) -> Int {
  let n = poly.length()
  let mut s = 0
  for i = 0; i < n; i = i + 1 {
    let (xi, yi) = poly[i]
    let (xj, yj) = poly[(i + 1) % n]
    s = s + xi * yj - xj * yi
  }
  s
}

///|
fn in_triangle(
  px : Int,
  py : Int,
  ax : Int,
  ay : Int,
  bx : Int,
  by : Int,
  cx : Int,
  cy : Int,
) -> Bool {
  let d1 = (px - bx) * (ay - by) - (ax - bx) * (py - by)
  let d2 = (px - cx) * (by - cy) - (bx - cx) * (py - cy)
  let d3 = (px - ax) * (cy - ay) - (cx - ax) * (py - ay)
  (d1 >= 0 && d2 >= 0 && d3 >= 0) || (d1 <= 0 && d2 <= 0 && d3 <= 0)
}

///|
fn is_left(px : Int, py : Int, ax : Int, ay : Int, bx : Int, by : Int) -> Bool {
  (bx - ax) * (py - ay) - (by - ay) * (px - ax) >= 0
}

///|
fn line_intersect(
  sx : Int,
  sy : Int,
  ex : Int,
  ey : Int,
  ax : Int,
  ay : Int,
  bx : Int,
  by : Int,
) -> (Int, Int) {
  let ds = (bx - ax) * (sy - ay) - (by - ay) * (sx - ax)
  let de = (bx - ax) * (ey - ay) - (by - ay) * (ex - ax)
  let d = ds - de
  ((ds * ex - de * sx) / d, (ds * ey - de * sy) / d)
}

///|
/// Clip `subject` against convex `clip` polygon (CCW). Returns clipped polygon or empty.
pub fn sutherland_hodgman(
  subject : Array[(Int, Int)],
  clip : Array[(Int, Int)],
) -> Array[(Int, Int)] {
  let cn = clip.length()
  if cn < 3 {
    return []
  }
  let mut output : Array[(Int, Int)] = []
  for i = 0; i < subject.length(); i = i + 1 {
    output.push(subject[i])
  }
  for i = 0; i < cn; i = i + 1 {
    let (ax, ay) = clip[i]
    let (bx, by) = clip[(i + 1) % cn]
    let input = output
    output = []
    let m = input.length()
    if m == 0 {
      continue
    }
    for j = 0; j < m; j = j + 1 {
      let (sx, sy) = input[(j - 1 + m) % m]
      let (ex, ey) = input[j]
      let si = is_left(sx, sy, ax, ay, bx, by)
      let ei = is_left(ex, ey, ax, ay, bx, by)
      if si {
        if ei {
          output.push((ex, ey))
        } else {
          output.push(line_intersect(sx, sy, ex, ey, ax, ay, bx, by))
        }
      } else if ei {
        output.push(line_intersect(sx, sy, ex, ey, ax, ay, bx, by))
        output.push((ex, ey))
      }
    }
  }
  output
}

///|
/// Triangulate a simple polygon via ear clipping. Returns vertex-index triples.
pub fn ear_clipping_triangulate(
  polygon : Array[(Int, Int)],
) -> Array[(Int, Int, Int)] {
  let n = polygon.length()
  if n < 3 {
    return []
  }
  if n == 3 {
    return [(0, 1, 2)]
  }
  let prev : Array[Int] = []
  let next : Array[Int] = []
  for i = 0; i < n; i = i + 1 {
    prev.push((i - 1 + n) % n)
    next.push((i + 1) % n)
  }
  if signed_area2(polygon) < 0 {
    for i = 0; i < n; i = i + 1 {
      let t = prev[i]
      prev[i] = next[i]
      next[i] = t
    }
  }
  let tris : Array[(Int, Int, Int)] = []
  let mut remaining = n
  let mut cur = 0
  while remaining > 3 {
    let mut found = false
    let mut i = cur
    let mut tries = 0
    while tries < remaining {
      let p = prev[i]
      let q = next[i]
      let (px, py) = polygon[p]
      let (cx, cy) = polygon[i]
      let (qx, qy) = polygon[q]
      if (cx - px) * (qy - py) - (cy - py) * (qx - px) > 0 {
        let mut is_ear = true
        let mut j = next[q]
        while j != p {
          let (vx, vy) = polygon[j]
          if in_triangle(vx, vy, px, py, cx, cy, qx, qy) {
            is_ear = false
            break
          }
          j = next[j]
        }
        if is_ear {
          tris.push((p, i, q))
          next[p] = q
          prev[q] = p
          remaining = remaining - 1
          cur = q
          found = true
          break
        }
      }
      i = next[i]
      tries = tries + 1
    }
    if !found {
      break
    }
  }
  if remaining == 3 {
    tris.push((cur, next[cur], prev[cur]))
  }
  tris
}

///|
/// Compute the absolute area of a polygon using the shoelace formula.
pub fn polygon_area(polygon : Array[(Int, Int)]) -> Double {
  let n = polygon.length()
  if n < 3 {
    return 0.0
  }
  let mut s = 0
  for i = 0; i < n; i = i + 1 {
    let (xi, yi) = polygon[i]
    let (xj, yj) = polygon[(i + 1) % n]
    s = s + xi * yj - xj * yi
  }
  let a = s.to_double() / 2.0
  if a < 0.0 {
    -a
  } else {
    a
  }
}

///|
/// Test whether (px, py) is inside `polygon` using ray casting.
pub fn point_in_polygon(
  px : Int,
  py : Int,
  polygon : Array[(Int, Int)],
) -> Bool {
  let n = polygon.length()
  if n < 3 {
    return false
  }
  let mut inside = false
  let mut j = n - 1
  for i = 0; i < n; i = i + 1 {
    let (xi, yi) = polygon[i]
    let (xj, yj) = polygon[j]
    if (yi > py) != (yj > py) {
      let dy = yj - yi
      if dy != 0 {
        let x_int = xi.to_double() +
          (py - yi).to_double() / dy.to_double() * (xj - xi).to_double()
        if px.to_double() < x_int {
          inside = !inside
        }
      }
    }
    j = i
  }
  inside
}

///|
test "sutherland_hodgman: clip and no-overlap" {
  let r = sutherland_hodgman([(0, 0), (10, 0), (10, 10), (0, 10)], [
    (5, 5),
    (15, 5),
    (15, 15),
    (5, 15),
  ])
  assert_eq(r.length(), 4)
  assert_eq(polygon_area(r), 25.0)
  let e = sutherland_hodgman([(0, 0), (2, 0), (2, 2), (0, 2)], [
    (5, 5),
    (10, 5),
    (10, 10),
    (5, 10),
  ])
  assert_eq(e.length(), 0)
}

///|
test "ear_clipping: convex and concave" {
  assert_eq(
    ear_clipping_triangulate([(0, 0), (4, 0), (4, 4), (0, 4)]).length(),
    2,
  )
  assert_eq(
    ear_clipping_triangulate([(0, 0), (4, 0), (4, 2), (2, 2), (2, 4), (0, 4)]).length(),
    4,
  )
}

///|
test "polygon_area: triangle and square" {
  assert_eq(polygon_area([(0, 0), (6, 0), (0, 4)]), 12.0)
  assert_eq(polygon_area([(0, 0), (4, 0), (4, 4), (0, 4)]), 16.0)
}

///|
test "point_in_polygon: convex and concave" {
  let sq = [(0, 0), (10, 0), (10, 10), (0, 10)]
  assert_true(point_in_polygon(5, 5, sq))
  assert_false(point_in_polygon(15, 5, sq))
  let l = [(0, 0), (4, 0), (4, 2), (2, 2), (2, 4), (0, 4)]
  assert_true(point_in_polygon(1, 1, l))
  assert_false(point_in_polygon(3, 3, l))
}
