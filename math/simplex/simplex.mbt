/// Two-phase Simplex method for Linear Programming.
///
/// Solves the linear program
/// ```text
///   maximize    c^T x
///   subject to  A x <= b
///               x >= 0
/// ```
/// using a tableau-based primal simplex with Bland's rule for pivot
/// selection, which guarantees termination on degenerate problems.
///
/// ## Two-phase method
///
/// Every constraint receives one slack variable. A constraint whose
/// right-hand side is non-negative takes a `+1` slack that seeds the
/// initial basis directly. A constraint with a negative right-hand side
/// is first multiplied by `-1` (equivalently a `>=` constraint with a
/// positive right-hand side); its slack becomes a `-1` surplus and an
/// *artificial* variable is added to give the row a starting basic
/// variable. Equality and `>=` constraints entered as pairs of `<=`
/// rows therefore flow through the same machinery: the row with the
/// negative right-hand side contributes the surplus plus an artificial.
///
/// Phase 1 maximizes the negated sum of the artificials. If the optimum
/// is nonzero the original system `A x = b, x >= 0` has no solution and
/// the solver reports `Infeasible`. Otherwise Phase 1 has produced a
/// feasible basis; any artificial that is still basic (necessarily at
/// value zero) is driven out when possible, and columns marked artificial
/// are forbidden from re-entering.
///
/// Phase 2 restores the original objective, recomputes reduced costs, and
/// runs the primal simplex to optimality. A ray along which the objective
/// grows without bound (no positive entry in the entering column) is
/// reported as `Unbounded`.
///
/// ## Bland's rule
///
/// The entering variable is the smallest-indexed column with a strictly
/// positive reduced cost; the leaving variable is the smallest-indexed
/// basic variable among the rows achieving the minimum ratio. This
/// deterministic anti-cycling rule bounds the number of pivots, so the
/// solver always terminates.
///
/// All arithmetic is in `Double`; comparisons against the `EPS` tolerance
/// absorb accumulated round-off.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Result type
// ---------------------------------------------------------------------------

/// Outcome of [`solve`].
pub enum SimplexResult {
  /// An optimal basic feasible solution was found.
  ///
  /// Field 0 (`solution`) has the same length as the cost vector `c`;
  /// field 1 (`objective`) is the attained value `c^T x`.
  Optimal(Array[Double], Double)
  /// The constraints admit no feasible point.
  Infeasible
  /// The objective is unbounded above on the feasible region.
  Unbounded
}

// ---------------------------------------------------------------------------
// Tableau
// ---------------------------------------------------------------------------

/// Absolute tolerance for treating a tableau entry as zero. Pivot
/// selection, the ratio test, and the Phase-1 feasibility check all
/// compare against `EPS`.
const EPS : Double = 1.0e-9

/// Internal simplex tableau.
///
/// Row `0` is the objective row: columns `0..ncols-1` hold the reduced
/// costs `c_j - z_j`, and column `ncols` holds `-z` (the negated current
/// objective value, so the objective is `-tab[ncols]`). Rows `1..m` are
/// the constraint rows, with column `ncols` holding the right-hand side.
/// The whole tableau is stored flat in row-major order with stride
/// `ncols + 1`.
priv struct Tableau {
  tab : FixedArray[Double]
  basis : Array[Int]
  artificial : Array[Bool]
  ncols : Int
  m : Int
  n : Int
  num_art : Int
}

/// Build the initial tableau for `max c^T x s.t. A x <= b, x >= 0`.
///
/// Each constraint gets one slack/surplus in column `n + i`. Constraints
/// with `b_i >= 0` take a `+1` slack that is the initial basic variable.
/// Constraints with `b_i < 0` are multiplied by `-1` (so the right-hand
/// side becomes positive), their slack becomes a `-1` surplus, and an
/// artificial variable is appended to seed the basis.
fn Tableau::build(
  c : Array[Double],
  a : Array[Array[Double]],
  b : Array[Double],
) -> Tableau {
  let n = c.length()
  let m = b.length()
  // A constraint with a negative right-hand side needs an artificial.
  let need_art = FixedArray::make(m, false)
  let mut num_art = 0
  for i = 0; i < m; i = i + 1 {
    if b[i] < 0.0 {
      need_art[i] = true
      num_art = num_art + 1
    }
  }
  let ncols = n + m + num_art
  let width = ncols + 1
  let tab = FixedArray::make((m + 1) * width, 0.0)
  let basis : Array[Int] = []
  let artificial : Array[Bool] = []
  for j = 0; j < ncols; j = j + 1 {
    artificial.push(false)
  }
  let mut art_col = n + m
  for i = 0; i < m; i = i + 1 {
    // `sign = -1` flips a negative-RHS row into `>=` form with a
    // positive right-hand side; `sign = +1` leaves a normal `<=` row.
    let sign : Double = if b[i] < 0.0 { -1.0 } else { 1.0 }
    let base = (i + 1) * width
    for j = 0; j < n; j = j + 1 {
      tab[base + j] = sign * a[i][j]
    }
    tab[base + (n + i)] = sign // +1 slack or -1 surplus
    tab[base + ncols] = sign * b[i] // right-hand side, now >= 0
    if need_art[i] {
      tab[base + art_col] = 1.0
      artificial[art_col] = true
      basis.push(art_col)
      art_col = art_col + 1
    } else {
      basis.push(n + i)
    }
  }
  { tab, basis, artificial, ncols, m, n, num_art }
}

/// Reset the objective row to `cost` and eliminate every basic column so
/// that the reduced cost of each basic variable is zero. After this call
/// `tab[ncols]` (row 0, RHS) equals `-z`, the negated objective value at
/// the current basic solution.
fn Tableau::price_out(self : Tableau, cost : Array[Double]) -> Unit {
  let width = self.ncols + 1
  for j = 0; j < self.ncols; j = j + 1 {
    self.tab[j] = cost[j]
  }
  self.tab[self.ncols] = 0.0
  for i = 0; i < self.m; i = i + 1 {
    let c = cost[self.basis[i]]
    if c != 0.0 {
      let base = (i + 1) * width
      for j = 0; j < width; j = j + 1 {
        self.tab[j] = self.tab[j] - c * self.tab[base + j]
      }
    }
  }
}

/// Pivot on constraint row `row` (1-indexed) and entering column `col`.
///
/// Normalizes the pivot row by its entering-column entry, then eliminates
/// `col` from every other row including the objective row, and records
/// `col` as the new basic variable for that constraint row.
fn Tableau::pivot(self : Tableau, row : Int, col : Int) -> Unit {
  let width = self.ncols + 1
  let base = row * width
  let inv = 1.0 / self.tab[base + col]
  for j = 0; j < width; j = j + 1 {
    self.tab[base + j] = self.tab[base + j] * inv
  }
  for i = 0; i < self.m + 1; i = i + 1 {
    if i != row {
      let r = i * width
      let factor = self.tab[r + col]
      if factor != 0.0 {
        for j = 0; j < width; j = j + 1 {
          self.tab[r + j] = self.tab[r + j] - factor * self.tab[base + j]
        }
      }
    }
  }
  self.basis[row - 1] = col
}

/// Bland's rule for the entering variable: the smallest column index with
/// a strictly positive reduced cost, skipping artificial columns. Returns
/// `-1` when no column can improve the objective (optimum reached).
fn Tableau::entering(self : Tableau) -> Int {
  for j = 0; j < self.ncols; j = j + 1 {
    if !self.artificial[j] && self.tab[j] > EPS {
      return j
    }
  }
  -1
}

/// Minimum-ratio test with Bland's tie-break.
///
/// Among constraint rows with a positive entry in `col`, pick the one
/// minimizing `RHS / entry`; ties are broken by the smallest basic-variable
/// index. Returns the 1-indexed constraint row, or `-1` if no row has a
/// positive entry (an unbounded ray).
fn Tableau::leaving(self : Tableau, col : Int) -> Int {
  let width = self.ncols + 1
  let mut best_row = -1
  let mut best_ratio = 0.0
  let mut best_basis = 0
  for i = 0; i < self.m; i = i + 1 {
    let entry = self.tab[(i + 1) * width + col]
    if entry > EPS {
      let rhs = self.tab[(i + 1) * width + self.ncols]
      let ratio = rhs / entry
      let bv = self.basis[i]
      if best_row < 0 ||
         ratio < best_ratio - EPS ||
         (ratio < best_ratio + EPS && bv < best_basis) {
        best_row = i + 1
        best_ratio = ratio
        best_basis = bv
      }
    }
  }
  best_row
}

/// Run primal simplex iterations until optimal or unbounded.
///
/// Returns `true` on optimum, `false` on an unbounded ray. Bland's rule on
/// both the entering and leaving selections guarantees termination.
fn Tableau::simplex(self : Tableau) -> Bool {
  let mut optimal = false
  let mut unbounded = false
  while !optimal && !unbounded {
    let col = self.entering()
    if col < 0 {
      optimal = true
    } else {
      let row = self.leaving(col)
      if row < 0 {
        unbounded = true
      } else {
        self.pivot(row, col)
      }
    }
  }
  !unbounded
}

/// After a successful Phase 1, drive out any artificial that is still
/// basic (necessarily at value zero).
///
/// For each such row, pivot on the first non-artificial column with a
/// nonzero entry. Rows that are zero across every non-artificial column
/// correspond to redundant constraints and are left alone; the artificial
/// stays basic at zero and is barred from re-entering in Phase 2.
fn Tableau::drive_out_artificials(self : Tableau) -> Unit {
  let width = self.ncols + 1
  for i = 0; i < self.m; i = i + 1 {
    if self.artificial[self.basis[i]] {
      let mut pivot_col = -1
      for j = 0; j < self.ncols; j = j + 1 {
        if !self.artificial[j] &&
           self.tab[(i + 1) * width + j].abs() > EPS {
          pivot_col = j
          break
        }
      }
      if pivot_col >= 0 {
        self.pivot(i + 1, pivot_col)
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Solve `max c^T x` subject to `A x <= b`, `x >= 0`.
///
/// `c` is the length-`n` cost vector, `a` is the `m x n` constraint matrix
/// (`a[i]` is row `i`), and `b` is the length-`m` right-hand side. Returns
/// [`Optimal`] with an `n`-element solution and the objective value,
/// [`Infeasible`], or [`Unbounded`].
///
/// Minimization problems are solved by negating `c` and negating the
/// returned objective. Equality constraints are expressed as the pair
/// `A_i x <= b_i` and `-A_i x <= -b_i`; `>=` constraints as `-A_i x <= -b_i`.
/// The two-phase machinery handles the resulting negative-RHS rows.
pub fn solve(
  c : Array[Double],
  a : Array[Array[Double]],
  b : Array[Double],
) -> SimplexResult {
  let n = c.length()
  let m = b.length()
  // No variables: the only feasible point is the empty vector, attained
  // iff every constraint right-hand side is non-negative.
  if n == 0 {
    for i = 0; i < m; i = i + 1 {
      if b[i] < -EPS {
        return Infeasible
      }
    }
    return Optimal([], 0.0)
  }
  // No constraints: if any cost is positive the objective is unbounded;
  // otherwise the origin is optimal.
  if m == 0 {
    for j = 0; j < n; j = j + 1 {
      if c[j] > EPS {
        return Unbounded
      }
    }
    let sol : Array[Double] = []
    for j = 0; j < n; j = j + 1 {
      sol.push(0.0)
    }
    return Optimal(sol, 0.0)
  }
  let t = Tableau::build(c, a, b)
  // Phase 1: only when artificials are present.
  if t.num_art > 0 {
    let cost : Array[Double] = []
    for j = 0; j < t.ncols; j = j + 1 {
      cost.push(if t.artificial[j] { -1.0 } else { 0.0 })
    }
    t.price_out(cost)
    let _ = t.simplex()
    // Sum of artificials == tab[ncols]; positive means infeasible.
    if t.tab[t.ncols] > EPS {
      return Infeasible
    }
    t.drive_out_artificials()
  }
  // Phase 2: original objective; artificials keep cost 0 and are barred
  // from entering via the `artificial` flags.
  let cost : Array[Double] = []
  for j = 0; j < t.n; j = j + 1 {
    cost.push(c[j])
  }
  for j = t.n; j < t.ncols; j = j + 1 {
    cost.push(0.0)
  }
  t.price_out(cost)
  if !t.simplex() {
    return Unbounded
  }
  // Extract the solution: x_j is the RHS of the row where j is basic.
  let width = t.ncols + 1
  let sol : Array[Double] = []
  for j = 0; j < t.n; j = j + 1 {
    sol.push(0.0)
  }
  for i = 0; i < t.m; i = i + 1 {
    let bv = t.basis[i]
    if bv < t.n {
      sol[bv] = t.tab[(i + 1) * width + t.ncols]
    }
  }
  Optimal(sol, -t.tab[t.ncols])
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

/// Tolerant equality for `Double`: passes within an absolute bound of
/// `1e-6` or a relative bound of `1e-6` of the combined magnitudes.
fn approx_eq(a : Double, b : Double) -> Bool {
  let diff = (a - b).abs()
  diff < 1.0e-6 || diff < 1.0e-6 * (a.abs() + b.abs())
}

/// Assert `a ~= b` for `Double`, aborting with both values on failure.
fn assert_approx(a : Double, b : Double) -> Unit {
  if !approx_eq(a, b) {
    abort("assert_approx: " + a.to_string() + " != " + b.to_string())
  }
}

/// Assert that `r` is `Optimal` with the given objective and solution.
fn assert_optimal(
  r : SimplexResult,
  expected_obj : Double,
  expected_sol : Array[Double],
) -> Unit raise {
  match r {
    Optimal(sol, obj) => {
      assert_approx(obj, expected_obj)
      assert_eq(sol.length(), expected_sol.length())
      for i = 0; i < sol.length(); i = i + 1 {
        assert_approx(sol[i], expected_sol[i])
      }
    }
    Infeasible => abort("expected Optimal, got Infeasible")
    Unbounded => abort("expected Optimal, got Unbounded")
  }
}

/// True iff `sol` satisfies `A x <= b` (within tolerance) and `x >= 0`.
fn feasible(
  a : Array[Array[Double]],
  b : Array[Double],
  sol : Array[Double],
) -> Bool {
  for i = 0; i < b.length(); i = i + 1 {
    let mut s = 0.0
    for j = 0; j < sol.length(); j = j + 1 {
      s = s + a[i][j] * sol[j]
    }
    if s > b[i] + 1.0e-6 {
      return false
    }
  }
  for j = 0; j < sol.length(); j = j + 1 {
    if sol[j] < -1.0e-6 {
      return false
    }
  }
  true
}

/// Evaluate `c^T sol`.
fn eval_objective(c : Array[Double], sol : Array[Double]) -> Double {
  let mut s = 0.0
  for j = 0; j < c.length(); j = j + 1 {
    s = s + c[j] * sol[j]
  }
  s
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "simplex: simple maximization" {
  // max 40 x1 + 30 x2  s.t.  x1 + x2 <= 12,  2 x1 + x2 <= 16.
  // Unique optimum at (4, 8) with objective 400.
  let r = solve([40.0, 30.0], [[1.0, 1.0], [2.0, 1.0]], [12.0, 16.0])
  assert_optimal(r, 400.0, [4.0, 8.0])
}

test "simplex: minimization via negated objective" {
  // min 2 x1 + 3 x2  s.t.  x1 + x2 >= 1,  equivalently  max -2 x1 - 3 x2.
  // Unique optimum at (1, 0); min value 2 == -(max objective -2).
  let r = solve([-2.0, -3.0], [[-1.0, -1.0]], [-1.0])
  assert_optimal(r, -2.0, [1.0, 0.0])
}

test "simplex: infeasible problem" {
  // x1 + x2 <= 1  and  x1 + x2 >= 3  cannot both hold.
  let r = solve([1.0, 1.0], [[1.0, 1.0], [-1.0, -1.0]], [1.0, -3.0])
  assert_true(r is Infeasible)
}

test "simplex: unbounded problem" {
  // max x1 + x2  s.t.  x1 - x2 <= 1.  Setting x2 = t, x1 = t + 1 keeps
  // the constraint tight for all t >= 0 while the objective 2 t + 1 -> inf.
  let r = solve([1.0, 1.0], [[1.0, -1.0]], [1.0])
  assert_true(r is Unbounded)
}

test "simplex: degenerate problem terminates via Bland's rule" {
  // max x1 + x2  s.t.  x1 + x2 <= 2,  2 x1 + 2 x2 <= 4 (redundant),
  //                     x1 <= 1.
  // The vertex (1, 1) is degenerate (three constraints tight); the
  // optimum value is 2. Multiple optima exist, so only the objective,
  // feasibility, and tightness of x1 + x2 are checked.
  let a = [[1.0, 1.0], [2.0, 2.0], [1.0, 0.0]]
  let b = [2.0, 4.0, 1.0]
  let c = [1.0, 1.0]
  let r = solve(c, a, b)
  match r {
    Optimal(sol, obj) => {
      assert_approx(obj, 2.0)
      assert_true(feasible(a, b, sol))
      assert_approx(eval_objective(c, sol), 2.0)
      assert_approx(sol[0] + sol[1], 2.0)
    }
    Infeasible => abort("expected Optimal, got Infeasible")
    Unbounded => abort("expected Optimal, got Unbounded")
  }
}

test "simplex: equality constraint" {
  // max x1  s.t.  x1 + x2 = 2,  x1, x2 >= 0.
  // Encoded as  x1 + x2 <= 2  and  -x1 - x2 <= -2  (i.e. x1 + x2 >= 2).
  // Unique optimum at (2, 0) with objective 2.
  let r = solve([1.0, 0.0], [[1.0, 1.0], [-1.0, -1.0]], [2.0, -2.0])
  assert_optimal(r, 2.0, [2.0, 0.0])
}

test "simplex: multiple constraints" {
  // max 4 x1 + 5 x2  s.t.  2 x1 + 3 x2 <= 6,  2 x1 + x2 <= 4,
  //                         x1 <= 2,  x2 <= 2.
  // Unique optimum at (1.5, 1) with objective 11.
  let r = solve(
    [4.0, 5.0],
    [[2.0, 3.0], [2.0, 1.0], [1.0, 0.0], [0.0, 1.0]],
    [6.0, 4.0, 2.0, 2.0],
  )
  assert_optimal(r, 11.0, [1.5, 1.0])
}

test "simplex: known textbook example (Giapetto)" {
  // Winston, Operations Research: max 3 x1 + 2 x2  s.t.
  //   2 x1 + x2 <= 100,  x1 + x2 <= 80,  x1 <= 40.
  // Unique optimum at (20, 60) with objective 180.
  let r = solve(
    [3.0, 2.0],
    [[2.0, 1.0], [1.0, 1.0], [1.0, 0.0]],
    [100.0, 80.0, 40.0],
  )
  assert_optimal(r, 180.0, [20.0, 60.0])
}

test "simplex: single variable with lower and upper bounds" {
  // max 5 x  s.t.  x <= 3,  x >= 1  <=>  -x <= -1.
  // Unique optimum at x = 3 with objective 15 (Phase 1 needed for x >= 1).
  let r = solve([5.0], [[1.0], [-1.0]], [3.0, -1.0])
  assert_optimal(r, 15.0, [3.0])
}

test "simplex: Phase 1 with a >= constraint and bounded variables" {
  // max 2 x1 + 3 x2  s.t.  x1 + x2 >= 2,  x1 <= 3,  x2 <= 3.
  // Unique optimum at (3, 3) with objective 15.
  let r = solve(
    [2.0, 3.0],
    [[-1.0, -1.0], [1.0, 0.0], [0.0, 1.0]],
    [-2.0, 3.0, 3.0],
  )
  assert_optimal(r, 15.0, [3.0, 3.0])
}
