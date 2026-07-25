/// Convex Hull Trick (CHT) for slope-optimised dynamic programming.
///
/// Many DP problems have the transition form
///
/// ```text
///   dp[i] = min_{j < i} { dp[j] + slope(j) * x[i] + intercept(j) }
/// ```
///
/// where `slope(j)` and `intercept(j)` depend only on `j`, and `x[i]` is a
/// query value associated with state `i`. If the slopes are **monotonic**
/// (either non-decreasing or non-increasing) and the query values `x[i]` are
/// also monotonic, the amortised cost per query drops from O(n) to O(1),
/// giving an overall O(n) DP instead of O(n²).
///
/// ## Algorithm
///
/// Lines `y = m*x + b` are inserted in order of monotonic slope. The convex
/// hull is maintained in a deque. When a new line is added, any previous line
/// that becomes redundant (lies above the intersection of its neighbours) is
/// popped from the back. Queries are answered from the front: since query
/// values are monotonic, the optimal line for `x[i]` can only move forward in
/// the deque.
///
/// ## Variants
///
/// This module provides two implementations:
/// - **Monotonic deque** (`CHTMin`): slopes inserted in **non-increasing**
///   order, queries in non-decreasing order. Amortised O(1) per operation.
/// - **Li Chao Tree fallback**: for non-monotonic queries, use the
///   `trees/li_chao_tree` package which handles arbitrary insertion order in
///   O(log C) per operation.
///
/// ## Complexity (monotonic deque)
///
/// - Insert: amortised O(1).
/// - Query: amortised O(1).
/// - Total for n lines and n queries: O(n).
///
/// ## Overflow safety
///
/// All arithmetic (slope * x, intersection cross-multiplication) is done in
/// `Int64` to prevent overflow for coordinates up to ~10⁹.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

/// A line `y = m * x + b` with `Int64` coefficients.
pub struct Line {
  m : Int64
  b : Int64
}

/// Construct a [`Line`].
pub fn line(m : Int64, b : Int64) -> Line {
  { m, b }
}

/// Evaluate the line at `x`.
pub fn eval(l : Line, x : Int64) -> Int64 {
  l.m * x + l.b
}

/// Monotonic-deque Convex Hull Trick for **minimum** queries.
///
/// Lines must be inserted in **non-increasing** order of slope `m`.
/// Queries must be made in **non-decreasing** order of `x`.
///
/// For **maximum** queries, negate all slopes and intercepts, query the min
/// hull, and negate the result.
pub struct CHTMin {
  /// Deque of lines forming the lower envelope.
  lines : Array[Line]
  /// Index of the front line for the current query position.
  mut head : Int
}

/// Create an empty [`CHTMin`].
pub fn new_min() -> CHTMin {
  { lines: [], head: 0 }
}

/// Insert a line into the min-hull.
///
/// **Precondition**: slopes must be inserted in non-increasing order.
/// Violating this produces incorrect results (no runtime check for
/// performance reasons).
pub fn insert_min(cht : CHTMin, l : Line) -> Unit {
  // Remove lines from the back that are made redundant by the new line.
  // A line `b` is redundant if the intersection of (a, b) is
  // >= the intersection of (b, new_line). Using cross-multiplication to avoid
  // floating point:
  //   intersect(a, b).x = (b.b - a.b) / (a.m - b.m)
  //   intersect(b, l).x = (l.b - b.b) / (b.m - l.m)
  // Since slopes are non-increasing: a.m >= b.m >= l.m
  // Denominators: a.m - b.m >= 0, b.m - l.m >= 0
  // b is redundant if:
  //   (b.b - a.b) / (a.m - b.m) >= (l.b - b.b) / (b.m - l.m)
  // Cross-multiplied (both denominators are non-negative):
  //   (b.b - a.b) * (b.m - l.m) >= (l.b - b.b) * (a.m - b.m)
  while cht.lines.length() - cht.head >= 2 {
    let n = cht.lines.length()
    let a = cht.lines[n - 2]
    let b = cht.lines[n - 1]
    let lhs = (b.b - a.b) * (b.m - l.m)
    let rhs = (l.b - b.b) * (a.m - b.m)
    if lhs >= rhs {
      ignore(cht.lines.pop())
    } else {
      break
    }
  }
  cht.lines.push(l)
}

/// Query the minimum value at `x`.
///
/// **Precondition**: queries must be made in non-decreasing order of `x`.
pub fn query_min(cht : CHTMin, x : Int64) -> Int64 {
  // Advance the head pointer while the next line gives a smaller value.
  while cht.head + 1 < cht.lines.length() {
    let cur = cht.lines[cht.head]
    let nxt = cht.lines[cht.head + 1]
    if eval(nxt, x) <= eval(cur, x) {
      cht.head = cht.head + 1
    } else {
      break
    }
  }
  eval(cht.lines[cht.head], x)
}

/// Binary-search variant: query the minimum at an arbitrary `x` (not requiring
/// monotonic query order). O(log n) per query.
pub fn query_min_bs(cht : CHTMin, x : Int64) -> Int64 {
  let n = cht.lines.length()
  if n == 0 {
    return 0L // undefined; return a safe default
  }
  if n == 1 {
    return eval(cht.lines[0], x)
  }
  let mut lo = 0
  let mut hi = n - 1
  while lo < hi {
    let mid = (lo + hi) / 2
    let cur = cht.lines[mid]
    let nxt = cht.lines[mid + 1]
    if eval(nxt, x) < eval(cur, x) {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  eval(cht.lines[lo], x)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "cht: single line" {
  let cht = new_min()
  insert_min(cht, line(2L, 3L)) // y = 2x + 3
  assert_eq(query_min(cht, 0L), 3L)
  assert_eq(query_min(cht, 5L), 13L)
}

test "cht: two lines, first always better" {
  let cht = new_min()
  // Non-increasing slopes: 2, then 1.
  insert_min(cht, line(2L, 10L)) // y = 2x + 10
  insert_min(cht, line(1L, 0L)) // y = x
  // At x=0: min(10, 0) = 0
  // At x=5: min(20, 5) = 5
  // At x=20: min(50, 20) = 20
  assert_eq(query_min(cht, 0L), 0L)
  assert_eq(query_min(cht, 5L), 5L)
  assert_eq(query_min(cht, 20L), 20L)
}

test "cht: two lines, crossover" {
  let cht = new_min()
  // Non-increasing slopes: 3, then 1.
  insert_min(cht, line(3L, 0L)) // y = 3x (steep slope, low intercept)
  insert_min(cht, line(1L, 10L)) // y = x + 10 (shallow slope, high intercept)
  // Crossover at x = 5: 3x = x+10 => x = 5
  // At x=0: min(0, 10) = 0
  // At x=3: min(9, 13) = 9
  // At x=6: min(18, 16) = 16
  // At x=10: min(30, 20) = 20
  assert_eq(query_min(cht, 0L), 0L)
  assert_eq(query_min(cht, 3L), 9L)
  assert_eq(query_min(cht, 6L), 16L)
  assert_eq(query_min(cht, 10L), 20L)
}

test "cht: redundant middle line removed" {
  let cht = new_min()
  // Three lines with non-increasing slopes: 3, 2, 1.
  // y = 3x, y = 2x+5, y = x+10
  // The middle line y=2x+5 is always above the min of the other two.
  // At x=0: min(0, 5, 10) = 0 (first line)
  // At x=5: min(15, 15, 15) = 15 (all equal)
  // At x=10: min(30, 25, 20) = 20 (third line)
  insert_min(cht, line(3L, 0L))
  insert_min(cht, line(2L, 5L)) // redundant
  insert_min(cht, line(1L, 10L))
  // After removal, the hull should have lines 1 and 3.
  assert_eq(cht.lines.length(), 2)
  assert_eq(query_min(cht, 0L), 0L)
  assert_eq(query_min(cht, 10L), 20L)
}

test "cht: dp optimization example" {
  // Lines with non-increasing slopes: 3, 2, 1.
  // y = 3x - 12, y = 2x - 5, y = x
  // These represent dp[j] + slope*x where slope decreases.
  let cht = new_min()
  insert_min(cht, line(3L, -12L))
  insert_min(cht, line(2L, -5L))
  insert_min(cht, line(1L, 0L))
  // At x=0: min(-12, -5, 0) = -12
  // At x=5: min(3, 5, 5) = 3
  // At x=10: min(18, 15, 10) = 10
  assert_eq(query_min(cht, 0L), -12L)
  assert_eq(query_min(cht, 5L), 3L)
  assert_eq(query_min(cht, 10L), 10L)
}

test "cht: binary search query (non-monotonic)" {
  let cht = new_min()
  // Non-increasing slopes: 3, 2, 1.
  insert_min(cht, line(3L, 0L))
  insert_min(cht, line(2L, 5L))
  insert_min(cht, line(1L, 10L))
  // Hull: lines 1 and 3 (middle removed).
  // query_min_bs can handle out-of-order queries.
  assert_eq(query_min_bs(cht, 0L), 0L)
  assert_eq(query_min_bs(cht, 10L), 20L)
  assert_eq(query_min_bs(cht, 3L), 9L)
}

test "cht: empty hull returns zero" {
  let cht = new_min()
  assert_eq(query_min_bs(cht, 5L), 0L)
}

test "cht: overflow safety" {
  let cht = new_min()
  // Large slopes and intercepts that would overflow Int32.
  // Non-increasing slopes: 2*10^9, then 10^9.
  insert_min(cht, line(2000000000L, 0L))
  insert_min(cht, line(1000000000L, 1000000000L))
  // At x = 10^9: line1 = 2*10^9 * 10^9 = 2*10^18 (fits in Int64)
  //              line2 = 10^9 * 10^9 + 10^9 ≈ 10^18 (fits in Int64)
  let result = query_min_bs(cht, 1000000000L)
  assert_true(result > 0L)
}

test "cht: many lines stress" {
  // Insert 100 lines with non-increasing slopes, query increasing x.
  let cht = new_min()
  for i = 99; i >= 0; i = i - 1 {
    // slope = i, intercept = i - 50.
    insert_min(cht, line(i.to_int64(), (i - 50).to_int64()))
  }
  // Query at several points and verify it equals the brute-force minimum.
  for x_val = 0; x_val <= 100; x_val = x_val + 10 {
    let x = x_val.to_int64()
    let cht_result = query_min_bs(cht, x)
    let mut brute = 999999999999L
    for i = 0; i < 100; i = i + 1 {
      let val = i.to_int64() * x + (i - 50).to_int64()
      if val < brute {
        brute = val
      }
    }
    assert_eq(cht_result, brute)
  }
}
