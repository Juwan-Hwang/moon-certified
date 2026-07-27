/// Correlation Coefficients — Pearson, Spearman, and Covariance.
///
/// This package computes measures of association between two numeric arrays:
///
/// - **Pearson** `r`: the linear correlation coefficient, ranging from −1
///   (perfect negative linear) to +1 (perfect positive linear).
/// - **Spearman** `ρ`: the rank correlation coefficient — Pearson applied to
///   the ranks of the data. It captures monotonic (not just linear)
///   relationships and is robust to outliers.
/// - **Covariance**: the unnormalised co-variation `Σ(xᵢ−x̄)(yᵢ−ȳ)/n`
///   (population covariance, dividing by `n`).
///
/// ## Ranking (for Spearman)
///
/// Ranks are assigned using the **average-rank** method for ties: when `m`
/// values are tied, each receives the average of the ranks they would have
/// occupied. This is the standard convention (e.g. SciPy's `rankdata` with
/// `method='average'`).
///
/// ## Edge-case policy
///
/// - Arrays of different lengths, or fewer than 2 elements → `0.0`.
/// - Zero variance (constant array) → `0.0` (the denominator vanishes;
///   returning `0.0` indicates "no linear association").
/// - No function calls `abort`.
///
/// ## Complexity
///
/// - `covariance`, `pearson`: O(n) time, O(1) space.
/// - `spearman`: O(n log n) time (sorting for ranks), O(n) space.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Covariance
// ---------------------------------------------------------------------------

///|
/// Population covariance of two arrays.
///
/// ```
/// cov(x, y) = Σ(xᵢ − x̄)(yᵢ − ȳ) / n
/// ```
///
/// Returns `0.0` if the arrays have different lengths or are empty.
pub fn covariance(x : Array[Double], y : Array[Double]) -> Double {
  let n = x.length()
  if n == 0 || n != y.length() {
    return 0.0
  }
  let mut sx = 0.0
  let mut sy = 0.0
  for i = 0; i < n; i = i + 1 {
    sx = sx + x[i]
    sy = sy + y[i]
  }
  let mx = sx / n.to_double()
  let my = sy / n.to_double()
  let mut cov = 0.0
  for i = 0; i < n; i = i + 1 {
    cov = cov + (x[i] - mx) * (y[i] - my)
  }
  cov / n.to_double()
}

// ---------------------------------------------------------------------------
// Pearson correlation
// ---------------------------------------------------------------------------

///|
/// Pearson product-moment correlation coefficient.
///
/// ```
///                Σ(xᵢ − x̄)(yᵢ − ȳ)
/// r = ─────────────────────────────────
///     √(Σ(xᵢ − x̄)²) · √(Σ(yᵢ − ȳ)²)
/// ```
///
/// Equivalent to `cov(x, y) / (std(x) · std(y))` using population moments.
/// The result lies in [−1, +1].
///
/// Returns `0.0` if the arrays have different lengths, fewer than 2 elements,
/// or if either array has zero variance (constant).
pub fn pearson(x : Array[Double], y : Array[Double]) -> Double {
  let n = x.length()
  if n < 2 || n != y.length() {
    return 0.0
  }
  let mut sx = 0.0
  let mut sy = 0.0
  for i = 0; i < n; i = i + 1 {
    sx = sx + x[i]
    sy = sy + y[i]
  }
  let mx = sx / n.to_double()
  let my = sy / n.to_double()
  let mut sxy = 0.0
  let mut sxx = 0.0
  let mut syy = 0.0
  for i = 0; i < n; i = i + 1 {
    let dx = x[i] - mx
    let dy = y[i] - my
    sxy = sxy + dx * dy
    sxx = sxx + dx * dx
    syy = syy + dy * dy
  }
  let denom = (sxx * syy).sqrt()
  if denom == 0.0 {
    return 0.0
  }
  sxy / denom
}

// ---------------------------------------------------------------------------
// Rank computation (average-rank method for ties)
// ---------------------------------------------------------------------------

///|
/// Compute ranks of `data` using the average-rank method for ties.
///
/// Returns an array `r` where `r[i]` is the rank of `data[i]`. Tied values
/// receive the average of the ranks they would occupy. Ranks are 1-based.
fn rank_data(data : Array[Double]) -> Array[Double] {
  let n = data.length()
  if n == 0 {
    return []
  }
  // Build (value, original_index) pairs and sort by value.
  let pairs : Array[(Double, Int)] = []
  for i = 0; i < n; i = i + 1 {
    pairs.push((data[i], i))
  }
  pairs.sort()
  // Assign average ranks, handling ties.
  let ranks = Array::make(n, 0.0)
  let mut i = 0
  while i < n {
    // Find the group of tied values starting at position i.
    let mut j = i + 1
    while j < n && pairs[j].0 == pairs[i].0 {
      j = j + 1
    }
    // Average rank for positions i..j (1-based): (i+1 + j) / 2.
    let avg_rank = (i.to_double() + 1.0 + j.to_double()) / 2.0
    for k = i; k < j; k = k + 1 {
      ranks[pairs[k].1] = avg_rank
    }
    i = j
  }
  ranks
}

// ---------------------------------------------------------------------------
// Spearman correlation
// ---------------------------------------------------------------------------

///|
/// Spearman rank correlation coefficient.
///
/// Computes the Pearson correlation of the **ranks** of `x` and `y`, using
/// the average-rank method for ties. Captures monotonic relationships.
///
/// Returns `0.0` if the arrays have different lengths, fewer than 2 elements,
/// or if either rank array has zero variance (all values identical).
pub fn spearman(x : Array[Double], y : Array[Double]) -> Double {
  let n = x.length()
  if n < 2 || n != y.length() {
    return 0.0
  }
  let rx = rank_data(x)
  let ry = rank_data(y)
  pearson(rx, ry)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "covariance: positive covariance" {
  let x = [1.0, 2.0, 3.0, 4.0, 5.0]
  let y = [2.0, 4.0, 6.0, 8.0, 10.0]
  // cov = Σ(xᵢ−3)(yᵢ−6)/5 = (4+4+0+0+4+4)/5 ... actually:
  // x̄ = 3, ȳ = 6; deviations: (-2,-4)(-1,-2)(0,0)(1,2)(2,4)
  // products: 8+2+0+2+8 = 20; cov = 20/5 = 4
  assert_true((covariance(x, y) - 4.0).abs() < 1.0e-10)
}

///|
test "covariance: negative covariance" {
  let x = [1.0, 2.0, 3.0, 4.0, 5.0]
  let y = [5.0, 4.0, 3.0, 2.0, 1.0]
  // x̄ = 3, ȳ = 3; products: (-2)(2)+(-1)(1)+0+1(-1)+2(-2) = -4-1+0-1-4 = -10
  // cov = -10/5 = -2
  assert_true((covariance(x, y) - -2.0).abs() < 1.0e-10)
}

///|
test "covariance: zero covariance (independent)" {
  let x = [1.0, 2.0, 3.0, 4.0, 5.0]
  let y = [3.0, 3.0, 3.0, 3.0, 3.0]
  assert_true(covariance(x, y).abs() < 1.0e-10)
}

///|
test "covariance: mismatched lengths" {
  assert_true(covariance([1.0, 2.0], [1.0]) == 0.0)
}

///|
test "pearson: perfect positive" {
  let x = [1.0, 2.0, 3.0, 4.0, 5.0]
  let y = [2.0, 4.0, 6.0, 8.0, 10.0] // y = 2x
  assert_true((pearson(x, y) - 1.0).abs() < 1.0e-10)
}

///|
test "pearson: perfect negative" {
  let x = [1.0, 2.0, 3.0, 4.0, 5.0]
  let y = [10.0, 8.0, 6.0, 4.0, 2.0] // y = -2x + 12
  assert_true((pearson(x, y) - -1.0).abs() < 1.0e-10)
}

///|
test "pearson: no linear correlation" {
  let x = [1.0, 2.0, 3.0, 4.0, 5.0]
  let y = [3.0, 1.0, 4.0, 1.0, 5.0]
  // Not exactly zero but small; check it is in (-0.5, 0.5).
  let r = pearson(x, y)
  assert_true(r > -0.5 && r < 0.5)
}

///|
test "pearson: constant array returns zero" {
  let x = [5.0, 5.0, 5.0, 5.0]
  let y = [1.0, 2.0, 3.0, 4.0]
  assert_true(pearson(x, y) == 0.0)
}

///|
test "pearson: mismatched lengths" {
  assert_true(pearson([1.0, 2.0, 3.0], [1.0, 2.0]) == 0.0)
}

///|
test "spearman: perfect monotonic (nonlinear)" {
  // y = x² is perfectly monotonically increasing → Spearman = 1.
  let x = [1.0, 2.0, 3.0, 4.0, 5.0]
  let y = [1.0, 4.0, 9.0, 16.0, 25.0]
  assert_true((spearman(x, y) - 1.0).abs() < 1.0e-10)
}

///|
test "spearman: perfect negative monotonic" {
  let x = [1.0, 2.0, 3.0, 4.0, 5.0]
  let y = [25.0, 16.0, 9.0, 4.0, 1.0]
  assert_true((spearman(x, y) - -1.0).abs() < 1.0e-10)
}

///|
test "spearman: handles ties with average ranks" {
  // Both arrays have the same tie pattern, so their average ranks are
  // identical and perfectly positively correlated.
  // x = [10, 20, 20, 30], ranks = [1, 2.5, 2.5, 4]
  // y = [1,  2,  2,  3],  ranks = [1, 2.5, 2.5, 4]
  // Pearson of ranks: perfect positive → 1.0
  let x = [10.0, 20.0, 20.0, 30.0]
  let y = [1.0, 2.0, 2.0, 3.0]
  assert_true((spearman(x, y) - 1.0).abs() < 1.0e-10)
}

///|
test "spearman: ties with known non-trivial value" {
  // x = [10, 20, 20, 30], ranks = [1, 2.5, 2.5, 4]
  // y = [1,  2,  3,  4],  ranks = [1, 2,   3,   4]
  // Pearson of ranks is NOT 1.0 because the tie in x breaks linearity.
  // r = 4.5 / sqrt(4.5 * 5.0) = 4.5 / sqrt(22.5) ≈ 0.9486832981
  let x = [10.0, 20.0, 20.0, 30.0]
  let y = [1.0, 2.0, 3.0, 4.0]
  assert_true((spearman(x, y) - 0.9486832981).abs() < 1.0e-6)
}

///|
test "spearman: both arrays have ties" {
  // x = [1, 2, 2, 3], ranks = [1, 2.5, 2.5, 4]
  // y = [3, 2, 2, 1], ranks = [4, 2.5, 2.5, 1]
  // Perfect negative rank correlation → -1.0
  let x = [1.0, 2.0, 2.0, 3.0]
  let y = [3.0, 2.0, 2.0, 1.0]
  assert_true((spearman(x, y) - -1.0).abs() < 1.0e-10)
}

///|
test "spearman: mismatched lengths" {
  assert_true(spearman([1.0, 2.0, 3.0], [1.0, 2.0]) == 0.0)
}
