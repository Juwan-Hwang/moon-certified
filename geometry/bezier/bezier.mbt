/// Bézier Curves — de Casteljau evaluation, derivatives, subdivision, degree elevation, and arc length.
///
/// Bézier curves are parametric curves defined by control points and the
/// Bernstein polynomial basis. They are the backbone of vector graphics
/// (PostScript, SVG, PDF), CAD/CAM, and font rendering (TrueType/OpenType).
///
/// ## Implemented Features
///
/// - **Point evaluation**: de Casteljau algorithm (numerically stable) and
///   direct Bernstein polynomial form
/// - **Tangent / derivative**: first derivative via differentiated Bernstein
///   basis, yielding a degree-(n-1) Bézier curve of hodograph
/// - **Higher-order derivatives**: arbitrary k-th derivative via repeated
///   hodograph
/// - **Degree elevation**: express a degree-n curve as degree-(n+1) with
///   new control points
/// - **Subdivision**: de Casteljau split at parameter t ∈ [0,1]
/// - **Arc length**: adaptive Simpson's rule integration of ‖B'(t)‖
/// - **Point generation**: sample n points along the curve
/// - **Monomial ↔ Bernstein conversion** (optional)
/// - **Cubic Hermite → cubic Bézier conversion**
///
/// ## References
///
/// - Farin, G. (2002). *Curves and Surfaces for CAGD: A Practical Guide*,
///   5th ed. Morgan Kaufmann.
/// - de Casteljau, P. (1959). "Courbes et surfaces à pôles." Citroën internal
///   report.
/// - Bézier, P. (1972). *Numerical Control: Mathematics and Applications*.
///
/// ## Floating-Point Note
///
/// All coordinates and computations use `Double` because Bézier curves
/// inherently operate in continuous ℝ² space. Integer coordinates would
/// lose precision for sub-pixel rendering and parametric evaluation.

// =============================================================================
// Point Type (Double-precision 2D)
// =============================================================================

///|
/// A 2D point with floating-point coordinates.
pub struct DPoint {
  x : Double
  y : Double
}

///|
/// Construct a `DPoint`.
pub fn dpoint(x : Double, y : Double) -> DPoint {
  { x, y, }
}

// =============================================================================
// Internal: Binomial Coefficients (exact via Int)
// =============================================================================

///|
/// Compute binomial coefficient C(n, k) = n! / (k!(n-k)!).
///
/// Uses multiplicative formula to avoid overflow for moderate n.
/// Returns 0 if k < 0 or k > n.
fn binom(n : Int, k : Int) -> Int {
  if k < 0 || k > n {
    return 0
  }
  let k = if k > n - k { n - k } else { k }
  let mut result = 1
  for i in 0..<k {
    result = result * (n - i) / (i + 1)
  }
  result
}

// =============================================================================
// Core: de Casteljau Evaluation
// =============================================================================

///|
/// Evaluate a Bézier curve at parameter `t` using the de Casteljau algorithm.
///
/// This is the most numerically stable evaluation method — it avoids
/// catastrophic cancellation that can occur with direct Bernstein polynomial
/// evaluation for high-degree curves.
///
/// - `control_points`: array of n+1 control points defining a degree-n curve
/// - `t`: parameter in [0, 1]
/// - Returns: the point B(t) on the curve
pub fn bezier_eval_de_casteljau(
  control_points : Array[DPoint],
  t : Double,
) -> DPoint {
  let n = control_points.length()
  if n == 0 {
    return { x: 0.0, y: 0.0, }
  }
  if n == 1 {
    return control_points[0]
  }
  // Work on a mutable copy
  let pts : Array[DPoint] = []
  for i in 0..<n {
    pts.push(control_points[i])
  }
  let s = 1.0 - t
  // Iteratively reduce: level 0 = original, level j has (n-j) points
  for level in 1..<n {
    for i in 0..<(n - level) {
      pts[i] = {
        x: pts[i].x * s + pts[i + 1].x * t,
        y: pts[i].y * s + pts[i + 1].y * t,
      }
    }
  }
  pts[0]
}

// =============================================================================
// Core: Bernstein Polynomial Evaluation
// =============================================================================

///|
/// Evaluate a Bézier curve at parameter `t` using the Bernstein basis.
///
/// B(t) = Σ_{i=0}^{n} C(n,i) t^i (1-t)^{n-i} P_i
///
/// This is the direct formula. For high-degree curves (>20), prefer
/// `bezier_eval_de_casteljau` for better numerical stability.
pub fn bezier_eval_bernstein(
  control_points : Array[DPoint],
  t : Double,
) -> DPoint {
  let n = control_points.length() - 1
  if n < 0 {
    return { x: 0.0, y: 0.0, }
  }
  if n == 0 {
    return control_points[0]
  }
  let s = 1.0 - t
  let mut x = 0.0
  let mut y = 0.0
  for i in 0..<=n {
    let b = binom(n, i).to_double()
    let term = b * pow(t, i) * pow(s, n - i)
    x = x + term * control_points[i].x
    y = y + term * control_points[i].y
  }
  { x, y, }
}

///|
/// Power function: base^exp for non-negative integer exponents.
fn pow(base : Double, exp : Int) -> Double {
  let mut result = 1.0
  let mut b = base
  let mut e = exp
  while e > 0 {
    if (e & 1) == 1 {
      result = result * b
    }
    b = b * b
    e = e >> 1
  }
  result
}

// =============================================================================
// First Derivative (Hodograph)
// =============================================================================

///|
/// Compute the control points of the first-derivative (hodograph) curve.
///
/// The derivative of a degree-n Bézier curve is a degree-(n-1) Bézier curve
/// with control points Q_i = n * (P_{i+1} - P_i).
///
/// Returns an empty array if the input has fewer than 2 points.
pub fn bezier_derivative_control_points(
  control_points : Array[DPoint],
) -> Array[DPoint] {
  let n = control_points.length()
  if n < 2 {
    return []
  }
  let degree = n - 1
  let result : Array[DPoint] = []
  for i in 0..<(n - 1) {
    result.push({
      x: degree.to_double() * (control_points[i + 1].x - control_points[i].x),
      y: degree.to_double() * (control_points[i + 1].y - control_points[i].y),
    })
  }
  result
}

///|
/// Evaluate the first derivative B'(t) at parameter `t`.
///
/// Equivalent to evaluating the hodograph curve at `t`.
pub fn bezier_eval_derivative(
  control_points : Array[DPoint],
  t : Double,
) -> DPoint {
  let dcps = bezier_derivative_control_points(control_points)
  if dcps.length() == 0 {
    return { x: 0.0, y: 0.0, }
  }
  bezier_eval_de_casteljau(dcps, t)
}

// =============================================================================
// Higher-Order Derivatives
// =============================================================================

///|
/// Evaluate the k-th derivative B^(k)(t) at parameter `t`.
///
/// The k-th derivative of a degree-n Bézier curve is a degree-(n-k) Bézier
/// curve. For k > n, the derivative is zero.
pub fn bezier_eval_nth_derivative(
  control_points : Array[DPoint],
  k : Int,
  t : Double,
) -> DPoint {
  if k <= 0 {
    return bezier_eval_de_casteljau(control_points, t)
  }
  let n = control_points.length()
  if k >= n {
    return { x: 0.0, y: 0.0, }
  }
  // Iteratively compute derivative control points
  let mut current = Array::copy(control_points)
  for _step in 0..<k {
    current = bezier_derivative_control_points(current)
  }
  if current.length() == 0 {
    return { x: 0.0, y: 0.0, }
  }
  bezier_eval_de_casteljau(current, t)
}

// =============================================================================
// Degree Elevation
// =============================================================================

///|
/// Elevate the degree of a Bézier curve by 1.
///
/// Given degree-n control points P_0..P_n, compute degree-(n+1) control
/// points Q_0..Q_{n+1} that represent the same curve:
///
/// ```text
/// Q_0 = P_0
/// Q_i = (i/(n+1)) P_{i-1} + (1 - i/(n+1)) P_i   for 1 ≤ i ≤ n
/// Q_{n+1} = P_n
/// ```
pub fn bezier_elevate_degree(control_points : Array[DPoint]) -> Array[DPoint] {
  let n = control_points.length()
  if n == 0 {
    return []
  }
  // old degree = n-1, new degree = n
  // Q_0 = P_0
  // Q_i = (i/n) P_{i-1} + (1 - i/n) P_i  for 1 ≤ i ≤ n-1
  // Q_n = P_{n-1}
  let new_degree = n
  let result : Array[DPoint] = []
  result.push(control_points[0])
  for i in 1..<n {
    let alpha = i.to_double() / new_degree.to_double()
    let q = {
      x: alpha * control_points[i - 1].x + (1.0 - alpha) * control_points[i].x,
      y: alpha * control_points[i - 1].y + (1.0 - alpha) * control_points[i].y,
    }
    result.push(q)
  }
  result.push(control_points[n - 1])
  result
}

// =============================================================================
// Subdivision (Split at parameter t)
// =============================================================================

///|
/// Subdivide a Bézier curve at parameter `t` into two Bézier curves.
///
/// Uses the de Casteljau algorithm: the left curve's control points are
/// the "left edge" of the de Casteljau triangle, and the right curve's
/// control points are the "right edge".
///
/// Returns `(left, right)` where both are Bézier curves of the same degree
/// as the original.
pub fn bezier_subdivide(
  control_points : Array[DPoint],
  t : Double,
) -> (Array[DPoint], Array[DPoint]) {
  let n = control_points.length()
  if n == 0 {
    return ([], [])
  }
  if n == 1 {
    return ([control_points[0]], [control_points[0]])
  }
  // Build the full de Casteljau triangle
  // pts[0] = original, pts[level] = level-th reduction
  // We need the full triangle to extract both edges
  let s = 1.0 - t
  // Left curve: first element at each level
  // Right curve: last element at each level
  let left : Array[DPoint] = []
  let right_rev : Array[DPoint] = [] // built in reverse, will reverse at the end
  left.push(control_points[0])
  right_rev.push(control_points[n - 1])
  // Work on a mutable copy, updating in place
  let pts : Array[DPoint] = []
  for i in 0..<n {
    pts.push(control_points[i])
  }
  for level in 1..<n {
    for i in 0..<(n - level) {
      pts[i] = {
        x: pts[i].x * s + pts[i + 1].x * t,
        y: pts[i].y * s + pts[i + 1].y * t,
      }
    }
    left.push(pts[0])
    right_rev.push(pts[n - level - 1])
  }
  // right_rev = [P_n, L1_last, L2_last, ..., B(t)]
  // Right curve should be [B(t), ..., L1_last, P_n] (reversed)
  let right : Array[DPoint] = []
  for i in 0..<right_rev.length() {
    right.push(right_rev[right_rev.length() - 1 - i])
  }
  (left, right)
}

// =============================================================================
// Arc Length (Adaptive Simpson's Rule)
// =============================================================================

///|
/// Compute the Euclidean norm of a `DPoint` (vector magnitude).
fn vnorm(p : DPoint) -> Double {
  (p.x * p.x + p.y * p.y).sqrt()
}

///|
/// Adaptive Simpson's rule integration of the speed function ‖B'(t)‖
/// over [a, b] to compute arc length.
///
/// Recursively subdivides intervals where the error estimate exceeds
/// `tolerance`, achieving O(h^5) local accuracy per accepted interval.
fn adaptive_simpson(
  cps : Array[DPoint],
  a : Double,
  b : Double,
  tol : Double,
  depth : Int,
  max_depth : Int,
) -> Double {
  let fa = vnorm(bezier_eval_derivative(cps, a))
  let fb = vnorm(bezier_eval_derivative(cps, b))
  let m = (a + b) * 0.5
  let fm = vnorm(bezier_eval_derivative(cps, m))
  // Simpson's rule on [a, b]
  let whole = (b - a) / 6.0 * (fa + 4.0 * fm + fb)
  // Simpson's rule on [a, m] and [m, b]
  let lm = (a + m) * 0.5
  let rm = (m + b) * 0.5
  let flm = vnorm(bezier_eval_derivative(cps, lm))
  let frm = vnorm(bezier_eval_derivative(cps, rm))
  let left = (m - a) / 6.0 * (fa + 4.0 * flm + fm)
  let right = (b - m) / 6.0 * (fm + 4.0 * frm + fb)
  let diff = left + right - whole
  if depth >= max_depth || diff.abs() <= 15.0 * tol {
    left + right + diff / 15.0
  } else {
    adaptive_simpson(cps, a, m, tol * 0.5, depth + 1, max_depth) +
    adaptive_simpson(cps, m, b, tol * 0.5, depth + 1, max_depth)
  }
}

///|
/// Compute the arc length of a Bézier curve.
///
/// Integrates ‖B'(t)‖ from 0 to 1 using adaptive Simpson's rule.
/// - `tolerance`: desired accuracy (default 1e-8 is good)
/// - `max_depth`: recursion limit (default 25)
pub fn bezier_arc_length(
  control_points : Array[DPoint],
  tolerance : Double,
  max_depth : Int,
) -> Double {
  if control_points.length() < 2 {
    return 0.0
  }
  adaptive_simpson(control_points, 0.0, 1.0, tolerance, 0, max_depth)
}

///|
/// Compute arc length with default tolerance (1e-8) and depth (25).
pub fn bezier_arc_length_default(control_points : Array[DPoint]) -> Double {
  bezier_arc_length(control_points, 0.00000001, 25)
}

// =============================================================================
// Point Generation
// =============================================================================

///|
/// Generate `num_samples` points evenly spaced in parameter t ∈ [0, 1].
///
/// Returns an array of `num_samples` points on the curve.
/// Uses de Casteljau for each evaluation.
pub fn bezier_generate_points(
  control_points : Array[DPoint],
  num_samples : Int,
) -> Array[DPoint] {
  let result : Array[DPoint] = []
  if num_samples <= 0 {
    return result
  }
  if num_samples == 1 {
    result.push(bezier_eval_de_casteljau(control_points, 0.0))
    return result
  }
  for i in 0..<num_samples {
    let t = i.to_double() / (num_samples - 1).to_double()
    result.push(bezier_eval_de_casteljau(control_points, t))
  }
  result
}

// =============================================================================
// Cubic Hermite → Cubic Bézier Conversion
// =============================================================================

///|
/// Convert a cubic Hermite curve to cubic Bézier control points.
///
/// A cubic Hermite curve is defined by start point P0, end point P1,
/// start tangent T0, and end tangent T1. The equivalent cubic Bézier
/// control points are:
/// ```text
/// B0 = P0
/// B1 = P0 + T0/3
/// B2 = P1 - T1/3
/// B3 = P1
/// ```
pub fn hermite_to_bezier(
  p0 : DPoint,
  p1 : DPoint,
  t0 : DPoint,
  t1 : DPoint,
) -> Array[DPoint] {
  [
    p0,
    { x: p0.x + t0.x / 3.0, y: p0.y + t0.y / 3.0, },
    { x: p1.x - t1.x / 3.0, y: p1.y - t1.y / 3.0, },
    p1,
  ]
}

// =============================================================================
// Quadratic / Cubic Convenience Wrappers
// =============================================================================

///|
/// Evaluate a quadratic Bézier curve (3 control points) at `t`.
pub fn bezier_quad(p0 : DPoint, p1 : DPoint, p2 : DPoint, t : Double) -> DPoint {
  let s = 1.0 - t
  {
    x: s * s * p0.x + 2.0 * s * t * p1.x + t * t * p2.x,
    y: s * s * p0.y + 2.0 * s * t * p1.y + t * t * p2.y,
  }
}

///|
/// Evaluate a cubic Bézier curve (4 control points) at `t`.
pub fn bezier_cubic(
  p0 : DPoint,
  p1 : DPoint,
  p2 : DPoint,
  p3 : DPoint,
  t : Double,
) -> DPoint {
  let s = 1.0 - t
  let s2 = s * s
  let t2 = t * t
  {
    x: s2 * s * p0.x + 3.0 * s2 * t * p1.x + 3.0 * s * t2 * p2.x + t2 * t * p3.x,
    y: s2 * s * p0.y + 3.0 * s2 * t * p1.y + 3.0 * s * t2 * p2.y + t2 * t * p3.y,
  }
}

// =============================================================================
// Bounding Box
// =============================================================================

///|
/// Compute the axis-aligned bounding box of a Bézier curve.
///
/// Returns (min_point, max_point). For a degree-n curve, this requires
/// finding the extrema of x(t) and y(t) by solving B'_x(t) = 0 and
/// B'_y(t) = 0, then evaluating at those roots plus the endpoints.
///
/// Here we use a simple sampling approach (100 samples) which is
/// sufficient for most practical purposes. For exact bounds, solve
/// the derivative roots analytically.
pub fn bezier_bounding_box(control_points : Array[DPoint]) -> (DPoint, DPoint) {
  let samples = bezier_generate_points(control_points, 100)
  if samples.length() == 0 {
    return ({ x: 0.0, y: 0.0, }, { x: 0.0, y: 0.0, })
  }
  let mut min_x = samples[0].x
  let mut max_x = samples[0].x
  let mut min_y = samples[0].y
  let mut max_y = samples[0].y
  for i in 1..<samples.length() {
    let p = samples[i]
    if p.x < min_x {
      min_x = p.x
    }
    if p.x > max_x {
      max_x = p.x
    }
    if p.y < min_y {
      min_y = p.y
    }
    if p.y > max_y {
      max_y = p.y
    }
  }
  ({ x: min_x, y: min_y, }, { x: max_x, y: max_y, })
}
