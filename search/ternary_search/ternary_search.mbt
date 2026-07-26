/// Ternary search: locate the maximum or minimum of a **unimodal** function.
///
/// A function `f` is *unimodal* on an interval `[lo, hi]` if there is a single
/// point `x*` such that `f` is monotone non-decreasing on `[lo, x*]` and
/// monotone non-increasing on `[x*, hi]` (a single peak — the maximisation
/// case), or the reverse with a single valley (the minimisation case). Plainly
/// speaking, `f` has exactly one local extremum and no other local extrema in
/// the interior of the domain.
///
/// ## Algorithm
///
/// At every step two interior probe points are chosen at the one-third and
/// two-thirds marks of the current bracket:
///
/// ```text
///   m1 = lo + (hi - lo) / 3
///   m2 = hi - (hi - lo) / 3
/// ```
///
/// Comparing `f(m1)` and `f(m2)` discards the outer third that cannot contain
/// the extremum:
/// - **Maximise** (concave `f`): if `f(m1) < f(m2)` the peak lies in
///   `[m1, hi]`, so set `lo = m1`; otherwise set `hi = m2`.
/// - **Minimise** (convex `f`): if `f(m1) > f(m2)` the valley lies in
///   `[m1, hi]`, so set `lo = m1`; otherwise set `hi = m2`.
///
/// Each iteration shrinks the bracket by a factor of `2/3`.
///
/// ## Complexity
///
/// - **Discrete** (`Int`, inclusive `[lo, hi]`): the loop runs while
///   `hi - lo > 2`, i.e. `O(log_{3/2} n)` iterations for `n = hi - lo + 1`
///   points, followed by a constant scan of the final ≤ 3 survivors. Overall
///   **O(log n)** function evaluations.
/// - **Continuous** (`Double`): the loop runs until `hi - lo ≤ eps`, i.e.
///   `O(log((hi - lo) / eps) / log(3/2))` iterations. Overall
///   **O(log((hi - lo) / eps))** function evaluations.
///
/// ## Preconditions
///
/// - `lo <= hi` (non-empty domain).
/// - `f` is unimodal on `[lo, hi]`. With multiple local extrema the result is
///   unspecified — the search may converge to any of them.
/// - Continuous variants additionally require `eps > 0`.
///
/// ## Degenerate cases
///
/// A monotone (e.g. linear) function is unimodal in the degenerate sense: its
/// extremum lies at an endpoint, which the search returns. A constant function
/// has every point as an extremum; the search returns a valid one (the
/// leftmost on a plateau for the discrete variants).
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Absolute value of a `Double`.
///
/// Defined locally because `core/double::abs` is deprecated and would trip
/// `moon check --deny-warn`. Used only by the floating-point tests below.
fn abs(x : Double) -> Double {
  if x < 0.0 {
    -x
  } else {
    x
  }
}

// ---------------------------------------------------------------------------
// Discrete ternary search (Int domain)
// ---------------------------------------------------------------------------

/// Find `x` in the inclusive integer range `[lo, hi]` that **maximises** `f(x)`,
/// assuming `f` is unimodal (single-peaked / concave) on `[lo, hi]`.
///
/// On a plateau the leftmost maximiser is returned.
///
/// # Preconditions
/// - `lo <= hi`.
/// - `f` unimodal on `[lo, hi]`.
///
/// # Complexity
/// `O(log n)` function evaluations, where `n = hi - lo + 1`.
///
/// # Example
/// ```moonbit
/// // f(x) = -(x-5)^2 + 10 peaks at x = 5
/// ternary_search_max(fn(x) { -(x - 5) * (x - 5) + 10 }, 0, 10) // => 5
/// ```
pub fn ternary_search_max(f : (Int) -> Int, lo : Int, hi : Int) -> Int {
  if lo > hi {
    return lo
  }
  let mut lo = lo
  let mut hi = hi
  // Narrow the bracket until at most three candidates remain. Because
  // `hi - lo >= 3` here, `(hi - lo) / 3 >= 1`, so `m1 < m2` and the bracket
  // strictly shrinks every iteration — guaranteed termination.
  while hi - lo > 2 {
    let m1 = lo + (hi - lo) / 3
    let m2 = hi - (hi - lo) / 3
    if f(m1) < f(m2) {
      lo = m1
    } else {
      hi = m2
    }
  }
  // Final linear scan over the ≤ 3 surviving candidates.
  let mut best = lo
  let mut best_val = f(lo)
  for x = lo + 1; x <= hi; x = x + 1 {
    let v = f(x)
    if v > best_val {
      best = x
      best_val = v
    }
  }
  best
}

/// Find `x` in the inclusive integer range `[lo, hi]` that **minimises** `f(x)`,
/// assuming `f` is unimodal (single-valleyed / convex) on `[lo, hi]`.
///
/// On a plateau the leftmost minimiser is returned.
///
/// # Preconditions
/// - `lo <= hi`.
/// - `f` unimodal on `[lo, hi]`.
///
/// # Complexity
/// `O(log n)` function evaluations, where `n = hi - lo + 1`.
///
/// # Example
/// ```moonbit
/// // f(x) = (x-3)^2 bottoms at x = 3
/// ternary_search_min(fn(x) { (x - 3) * (x - 3) }, 0, 10) // => 3
/// ```
pub fn ternary_search_min(f : (Int) -> Int, lo : Int, hi : Int) -> Int {
  if lo > hi {
    return lo
  }
  let mut lo = lo
  let mut hi = hi
  while hi - lo > 2 {
    let m1 = lo + (hi - lo) / 3
    let m2 = hi - (hi - lo) / 3
    // Mirror of the maximisation case: the valley is on the side of the
    // smaller probe value.
    if f(m1) > f(m2) {
      lo = m1
    } else {
      hi = m2
    }
  }
  let mut best = lo
  let mut best_val = f(lo)
  for x = lo + 1; x <= hi; x = x + 1 {
    let v = f(x)
    if v < best_val {
      best = x
      best_val = v
    }
  }
  best
}

// ---------------------------------------------------------------------------
// Continuous ternary search (Double domain)
// ---------------------------------------------------------------------------

/// Find `x` in the real interval `[lo, hi]` that **maximises** `f(x)`,
/// assuming `f` is unimodal on `[lo, hi]`. Returns the midpoint of the final
/// bracket, whose width is at most `eps`.
///
/// # Preconditions
/// - `lo <= hi`.
/// - `eps > 0`.
/// - `f` unimodal on `[lo, hi]`.
///
/// # Complexity
/// `O(log((hi - lo) / eps))` function evaluations.
///
/// # Example
/// ```moonbit
/// // sin(x) on [0, pi] peaks at pi/2
/// ternary_search_max_double(@math.sin, 0.0, @math.PI, 1.0e-10)
/// ```
pub fn ternary_search_max_double(
  f : (Double) -> Double,
  lo : Double,
  hi : Double,
  eps : Double,
) -> Double {
  if eps <= 0.0 {
    return lo
  }
  if lo > hi {
    return lo
  }
  let mut lo = lo
  let mut hi = hi
  // `lo <= hi` is maintained: updates keep the extremum-bearing sub-interval,
  // and `m1 < m2` whenever `hi - lo > eps > 0`, so the bracket shrinks.
  while hi - lo > eps {
    let m1 = lo + (hi - lo) / 3.0
    let m2 = hi - (hi - lo) / 3.0
    if f(m1) < f(m2) {
      lo = m1
    } else {
      hi = m2
    }
  }
  (lo + hi) / 2.0
}

/// Find `x` in the real interval `[lo, hi]` that **minimises** `f(x)`,
/// assuming `f` is unimodal on `[lo, hi]`. Returns the midpoint of the final
/// bracket, whose width is at most `eps`.
///
/// # Preconditions
/// - `lo <= hi`.
/// - `eps > 0`.
/// - `f` unimodal on `[lo, hi]`.
///
/// # Complexity
/// `O(log((hi - lo) / eps))` function evaluations.
///
/// # Example
/// ```moonbit
/// // -sin(x) on [0, pi] bottoms at pi/2
/// ternary_search_min_double(fn(x) { -@math.sin(x) }, 0.0, @math.PI, 1.0e-10)
/// ```
pub fn ternary_search_min_double(
  f : (Double) -> Double,
  lo : Double,
  hi : Double,
  eps : Double,
) -> Double {
  if eps <= 0.0 {
    return lo
  }
  if lo > hi {
    return lo
  }
  let mut lo = lo
  let mut hi = hi
  while hi - lo > eps {
    let m1 = lo + (hi - lo) / 3.0
    let m2 = hi - (hi - lo) / 3.0
    if f(m1) > f(m2) {
      lo = m1
    } else {
      hi = m2
    }
  }
  (lo + hi) / 2.0
}

// ---------------------------------------------------------------------------
// Tests — discrete maximisation
// ---------------------------------------------------------------------------

test "ternary_search_max: parabola peak at x=5" {
  // f(x) = -(x-5)^2 + 10, concave, unique maximum at x = 5 with f(5) = 10.
  let f = fn(x : Int) -> Int { -(x - 5) * (x - 5) + 10 }
  assert_eq(ternary_search_max(f, 0, 10), 5)
  assert_eq(ternary_search_max(f, 0, 100), 5)
  assert_eq(ternary_search_max(f, 5, 5), 5)
  assert_eq(ternary_search_max(f, 4, 6), 5)
}

test "ternary_search_max: linear increasing (degenerate)" {
  // Monotone increasing: the maximum is the right endpoint.
  let f = fn(x : Int) -> Int { 2 * x + 1 }
  assert_eq(ternary_search_max(f, 0, 10), 10)
}

test "ternary_search_max: linear decreasing (degenerate)" {
  // Monotone decreasing: the maximum is the left endpoint.
  let f = fn(x : Int) -> Int { -3 * x }
  assert_eq(ternary_search_max(f, 0, 10), 0)
}

test "ternary_search_max: constant function (degenerate)" {
  // Every point is a maximum; the result must be a valid maximiser in range.
  let f = fn(_x : Int) -> Int { 42 }
  let x = ternary_search_max(f, 0, 10)
  assert_true(0 <= x && x <= 10)
  assert_eq(f(x), 42)
}

test "ternary_search_max: single point" {
  let f = fn(x : Int) -> Int { x * x }
  assert_eq(ternary_search_max(f, 7, 7), 7)
}

test "ternary_search_max: two points" {
  // Peak at the right of the two-point range.
  let f = fn(x : Int) -> Int { -(x - 1) * (x - 1) }
  assert_eq(ternary_search_max(f, 0, 1), 1)
  // Peak at the left of the two-point range.
  let g = fn(x : Int) -> Int { -x * x }
  assert_eq(ternary_search_max(g, 0, 1), 0)
}

test "ternary_search_max: larger domain" {
  // Wide concave parabola peaking at x = 500.
  let f = fn(x : Int) -> Int { -(x - 500) * (x - 500) }
  assert_eq(ternary_search_max(f, 0, 1000), 500)
  // Peak near the right edge still resolves to the exact integer maximiser.
  let g = fn(x : Int) -> Int { -(x - 999) * (x - 999) }
  assert_eq(ternary_search_max(g, 0, 1000), 999)
}

// ---------------------------------------------------------------------------
// Tests — discrete minimisation
// ---------------------------------------------------------------------------

test "ternary_search_min: parabola valley at x=3" {
  // f(x) = (x-3)^2, convex, unique minimum at x = 3 with f(3) = 0.
  let f = fn(x : Int) -> Int { (x - 3) * (x - 3) }
  assert_eq(ternary_search_min(f, 0, 10), 3)
  assert_eq(ternary_search_min(f, 0, 100), 3)
}

test "ternary_search_min: linear and constant (degenerate)" {
  let inc = fn(x : Int) -> Int { 5 * x }
  assert_eq(ternary_search_min(inc, 0, 10), 0) // minimum at the left endpoint
  let dec = fn(x : Int) -> Int { -5 * x }
  assert_eq(ternary_search_min(dec, 0, 10), 10) // minimum at the right endpoint
  let cst = fn(_x : Int) -> Int { 7 }
  let x = ternary_search_min(cst, 0, 10)
  assert_true(0 <= x && x <= 10)
  assert_eq(cst(x), 7)
}

test "ternary_search_min: single and two points" {
  let f = fn(x : Int) -> Int { (x - 5) * (x - 5) }
  assert_eq(ternary_search_min(f, 5, 5), 5)
  assert_eq(ternary_search_min(f, 4, 5), 5)
  assert_eq(ternary_search_min(f, 5, 6), 5)
  // Two points, valley at the left.
  let g = fn(x : Int) -> Int { x * x }
  assert_eq(ternary_search_min(g, 0, 1), 0)
}

test "ternary_search_min: larger domain" {
  let f = fn(x : Int) -> Int { (x - 314) * (x - 314) }
  assert_eq(ternary_search_min(f, 0, 1000), 314)
}

// ---------------------------------------------------------------------------
// Tests — continuous maximisation
// ---------------------------------------------------------------------------

test "ternary_search_max_double: sin(x) on [0, pi], max at pi/2" {
  // sin(x) is unimodal on [0, pi] with maximum 1 at x = pi/2.
  // (Note: -sin(x) has its *minimum* at pi/2, so the maximisation test uses
  // sin(x); the corresponding -sin(x) minimisation test is below.)
  let pi = @math.PI
  let x = ternary_search_max_double(@math.sin, 0.0, pi, 1.0e-12)
  assert_true(abs(x - pi / 2.0) < 1.0e-6)
  assert_true(abs(@math.sin(x) - 1.0) < 1.0e-6)
}

test "ternary_search_max_double: inverted parabola, max at x=2.5" {
  // f(x) = -(x-2.5)^2 + 7, smooth concave maximum at x = 2.5.
  let f = fn(x : Double) -> Double { -(x - 2.5) * (x - 2.5) + 7.0 }
  let x = ternary_search_max_double(f, -10.0, 10.0, 1.0e-12)
  assert_true(abs(x - 2.5) < 1.0e-6)
}

test "ternary_search_max_double: single-point interval" {
  let f = fn(x : Double) -> Double { -(x - 3.0) * (x - 3.0) }
  let x = ternary_search_max_double(f, 3.0, 3.0, 1.0e-6)
  assert_true(abs(x - 3.0) < 1.0e-6)
}

// ---------------------------------------------------------------------------
// Tests — continuous minimisation
// ---------------------------------------------------------------------------

test "ternary_search_min_double: -sin(x) on [0, pi], min at pi/2" {
  // -sin(x) is unimodal on [0, pi] with minimum -1 at x = pi/2.
  let pi = @math.PI
  let f = fn(x : Double) -> Double { -@math.sin(x) }
  let x = ternary_search_min_double(f, 0.0, pi, 1.0e-12)
  assert_true(abs(x - pi / 2.0) < 1.0e-6)
  assert_true(abs(f(x) - (-1.0)) < 1.0e-6)
}

test "ternary_search_min_double: parabola, min at x=1.5" {
  // f(x) = (x-1.5)^2, smooth convex minimum at x = 1.5.
  let f = fn(x : Double) -> Double { (x - 1.5) * (x - 1.5) }
  let x = ternary_search_min_double(f, -5.0, 5.0, 1.0e-12)
  assert_true(abs(x - 1.5) < 1.0e-6)
}

test "ternary_search_min_double: single-point interval" {
  let f = fn(x : Double) -> Double { (x - 2.0) * (x - 2.0) }
  let x = ternary_search_min_double(f, 2.0, 2.0, 1.0e-6)
  assert_true(abs(x - 2.0) < 1.0e-6)
}
