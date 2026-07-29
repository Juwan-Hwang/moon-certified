/// Nonparametric Statistical Tests.
///
/// Distribution-free hypothesis tests that do not assume a specific
/// parametric form for the underlying populations. All p-values are computed
/// via **large-sample (asymptotic) approximations**:
///
/// - **Mann-Whitney U** (`mann_whitney_u_test`): compares two independent
///   samples. The U statistic is standardised by its exact null mean and
///   variance (with a tie correction) and referred to the standard normal.
/// - **Wilcoxon signed-rank** (`wilcoxon_signed_rank_test`): compares two
///   paired samples. The signed-rank sum W is standardised by its exact null
///   mean and variance (with a tie correction) and referred to the standard
///   normal.
/// - **Kruskal-Wallis H** (`kruskal_wallis_test`): compares `k ≥ 3`
///   independent samples. The H statistic (chi-square distributed with
///   `k − 1` degrees of freedom under the null) is converted to a p-value
///   via the Wilson-Hilferty normal approximation to the chi-square
///   distribution.
///
/// ## Ranking
///
/// All three tests share a ranking routine that assigns **average (mid)
/// ranks** to ties, the convention required for valid tie corrections.
///
/// ## Edge-case policy
///
/// Degenerate inputs (samples too small, zero variance after tie correction,
/// or all-identical observations) yield `NaN` p-values. No function calls
/// `abort`.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Shared ranking helper
// ---------------------------------------------------------------------------

///|
/// Rank `values` using average (mid) ranks for ties.
///
/// The smallest value receives rank 1. A run of `t` equal values all receive
/// the average of the ranks they would span. Returns a pair `(ranks,
/// tie_term)` where `tie_term = Σ(t³ − t)` over tie groups, used by every
/// test's variance correction.
fn rank_average(values : Array[Double]) -> (Array[Double], Double) {
  let n = values.length()
  let ranks = Array::make(n, 0.0)
  // Sort indices by their associated value (stable enough for ties).
  let idx : Array[Int] = []
  for i = 0; i < n; i = i + 1 {
    idx.push(i)
  }
  idx.sort_by(fn(a, b) {
    let va = values[a]
    let vb = values[b]
    if va < vb {
      -1
    } else if va > vb {
      1
    } else {
      0
    }
  })
  let mut tie_term = 0.0
  let mut i = 0
  while i < n {
    let mut j = i + 1
    while j < n && values[idx[j]] == values[idx[i]] {
      j = j + 1
    }
    // 1-based ranks span (i+1) .. j; their average is ((i+1) + j) / 2.
    let avg = ((i + 1).to_double() + j.to_double()) / 2.0
    for k = i; k < j; k = k + 1 {
      ranks[idx[k]] = avg
    }
    let t = j - i
    if t > 1 {
      let tf = t.to_double()
      tie_term = tie_term + (tf * tf - 1.0) * tf // t³ − t
    }
    i = j
  }
  (ranks, tie_term)
}

///|
/// Two-sided p-value from a standard-normal z, `p = 2·(1 − Φ(|z|))`.
/// Returns `NaN` for a `NaN` input and clamps to `[0, 1]`.
fn normal_two_sided_p(z : Double) -> Double {
  if z.is_nan() {
    return @double.not_a_number
  }
  let cdf = @special_functions.normal_cdf(z.abs())
  let p = 2.0 * (1.0 - cdf)
  if p < 0.0 {
    0.0
  } else if p > 1.0 {
    1.0
  } else {
    p
  }
}

// ---------------------------------------------------------------------------
// Mann-Whitney U test (two independent samples)
// ---------------------------------------------------------------------------

///|
/// Result of a Mann-Whitney U test.
pub struct MannWhitneyResult {
  u1 : Double // U for the first sample
  u2 : Double // U for the second sample
  u : Double // min(u1, u2)
  z : Double // standardised statistic (no continuity correction)
  p_value : Double // two-sided asymptotic p-value
}

///|
/// Perform a Mann-Whitney U test on two independent samples `x` and `y`.
///
/// Ranks are assigned over the pooled sample with average ranks for ties.
/// `U1 = R1 − n1(n1+1)/2`, `U2 = n1·n2 − U1`. The variance of U under the
/// null incorporates the standard tie correction:
///
/// ```text
/// σ²_U = (n1·n2 / 12) · ( (N+1) − Σ(t³−t) / (N·(N−1)) )
/// ```
///
/// `z = (U1 − n1·n2/2) / σ_U`, and `p = 2·(1 − Φ(|z|))`.
///
/// Returns `NaN` statistics when either sample is empty or the variance is
/// zero (e.g. all observations tied).
pub fn mann_whitney_u_test(
  x : Array[Double],
  y : Array[Double]
) -> MannWhitneyResult {
  let n1 = x.length()
  let n2 = y.length()
  if n1 == 0 || n2 == 0 {
    return mw_nan(n1, n2)
  }
  let n = n1 + n2
  // Pool the samples, keeping per-element group membership.
  let pooled : Array[Double] = []
  for v in x {
    pooled.push(v)
  }
  for v in y {
    pooled.push(v)
  }
  let (ranks, tie_term) = rank_average(pooled)
  let mut r1 = 0.0
  for i = 0; i < n1; i = i + 1 {
    r1 = r1 + ranks[i]
  }
  let u1 = r1 - n1.to_double() * (n1 + 1).to_double() / 2.0
  let u2 = n1.to_double() * n2.to_double() - u1
  let u = if u1 < u2 { u1 } else { u2 }
  let nf = n.to_double()
  // Variance with tie correction (guard against N == 1, already excluded).
  let var_u = n1.to_double() * n2.to_double() / 12.0 *
    ((nf + 1.0) - tie_term / (nf * (nf - 1.0)))
  if var_u <= 0.0 {
    return {
      u1,
      u2,
      u,
      z: @double.not_a_number,
      p_value: @double.not_a_number,
    }
  }
  let mean_u = n1.to_double() * n2.to_double() / 2.0
  let std_u = var_u.sqrt()
  let z = (u1 - mean_u) / std_u
  let p = normal_two_sided_p(z)
  { u1, u2, u, z, p_value: p }
}

///|
fn mw_nan(n1 : Int, n2 : Int) -> MannWhitneyResult {
  let u1 = 0.0
  let u2 = n1.to_double() * n2.to_double()
  {
    u1,
    u2,
    u: 0.0,
    z: @double.not_a_number,
    p_value: @double.not_a_number,
  }
}

// ---------------------------------------------------------------------------
// Wilcoxon signed-rank test (paired samples)
// ---------------------------------------------------------------------------

///|
/// Result of a Wilcoxon signed-rank test.
pub struct WilcoxonResult {
  w_plus : Double // sum of ranks of positive differences
  w_minus : Double // sum of ranks of negative differences
  n : Int // number of non-zero differences
  z : Double // standardised statistic (no continuity correction)
  p_value : Double // two-sided asymptotic p-value
}

///|
/// Perform a Wilcoxon signed-rank test on paired samples `x` and `y`.
///
/// Differences `d_i = x_i − y_i` are formed; zero differences are dropped.
/// The absolute differences are ranked with average ranks for ties. `W+` and
/// `W−` are the rank sums of the positive and negative differences. The
/// variance of W under the null incorporates the tie correction:
///
/// ```text
/// σ²_W = n(n+1)(2n+1)/24 − Σ(t³−t)/48
/// ```
///
/// `z = (W+ − n(n+1)/4) / σ_W`, and `p = 2·(1 − Φ(|z|))`.
///
/// Returns `NaN` statistics when the samples differ in length, have no
/// non-zero differences, or the variance is zero.
pub fn wilcoxon_signed_rank_test(
  x : Array[Double],
  y : Array[Double]
) -> WilcoxonResult {
  if x.length() != y.length() || x.length() == 0 {
    return wil_nan(0)
  }
  // Absolute differences, dropping exact zeros.
  let abs_diffs : Array[Double] = []
  let signs : Array[Int] = []
  for i = 0; i < x.length(); i = i + 1 {
    let d = x[i] - y[i]
    if d != 0.0 {
      abs_diffs.push(if d < 0.0 { -d } else { d })
      signs.push(if d < 0.0 { -1 } else { 1 })
    }
  }
  let n = abs_diffs.length()
  if n == 0 {
    return wil_nan(0)
  }
  let (ranks, tie_term) = rank_average(abs_diffs)
  let mut w_plus = 0.0
  let mut w_minus = 0.0
  for i = 0; i < n; i = i + 1 {
    if signs[i] > 0 {
      w_plus = w_plus + ranks[i]
    } else {
      w_minus = w_minus + ranks[i]
    }
  }
  let nf = n.to_double()
  let var_w = nf * (nf + 1.0) * (2.0 * nf + 1.0) / 24.0 - tie_term / 48.0
  if var_w <= 0.0 {
    return {
      w_plus,
      w_minus,
      n,
      z: @double.not_a_number,
      p_value: @double.not_a_number,
    }
  }
  let mean_w = nf * (nf + 1.0) / 4.0
  let std_w = var_w.sqrt()
  let z = (w_plus - mean_w) / std_w
  let p = normal_two_sided_p(z)
  { w_plus, w_minus, n, z, p_value: p }
}

///|
fn wil_nan(n : Int) -> WilcoxonResult {
  {
    w_plus: 0.0,
    w_minus: 0.0,
    n,
    z: @double.not_a_number,
    p_value: @double.not_a_number,
  }
}

// ---------------------------------------------------------------------------
// Kruskal-Wallis H test (k independent samples)
// ---------------------------------------------------------------------------

///|
/// Result of a Kruskal-Wallis H test.
pub struct KruskalWallisResult {
  h : Double // H statistic (tie-corrected)
  df : Int // k − 1
  z : Double // Wilson-Hilferty normal variate
  p_value : Double // asymptotic p-value
}

///|
/// Perform a Kruskal-Wallis H test on `k ≥ 2` independent `groups`.
///
/// Observations are pooled and ranked with average ranks for ties. The H
/// statistic is
///
/// ```text
/// H = (12 / (N·(N+1))) · Σ(R_i² / n_i) − 3·(N+1)
/// ```
///
/// adjusted for ties by dividing by `1 − Σ(t³−t)/(N³−N)`. Under the null,
/// `H ~ χ²(k−1)`. The p-value uses the Wilson-Hilferty normal approximation
/// to the chi-square distribution:
///
/// ```text
/// z = ( (H/df)^(1/3) − (1 − 2/(9·df)) ) / √(2/(9·df))
/// p = 1 − Φ(z)
/// ```
///
/// Returns `NaN` statistics when there are fewer than 2 non-empty groups or
/// the tie correction is undefined.
pub fn kruskal_wallis_test(groups : Array[Array[Double]]) -> KruskalWallisResult {
  // Flatten, remembering group boundaries.
  let pooled : Array[Double] = []
  let group_of : Array[Int] = []
  let sizes : Array[Int] = []
  let mut n_total = 0
  for gi = 0; gi < groups.length(); gi = gi + 1 {
    let g = groups[gi]
    let n = g.length()
    if n > 0 {
      sizes.push(n)
      for v in g {
        pooled.push(v)
        group_of.push(sizes.length() - 1)
      }
      n_total = n_total + n
    }
  }
  let k = sizes.length()
  if k < 2 || n_total < 2 {
    return kw_nan(if k > 1 { k - 1 } else { 0 })
  }
  let (ranks, tie_term) = rank_average(pooled)
  let nf = n_total.to_double()
  // Sum of squared rank sums / size per group.
  let rank_sums = Array::make(k, 0.0)
  for i = 0; i < n_total; i = i + 1 {
    rank_sums[group_of[i]] = rank_sums[group_of[i]] + ranks[i]
  }
  let mut s = 0.0
  for gi = 0; gi < k; gi = gi + 1 {
    s = s + rank_sums[gi] * rank_sums[gi] / sizes[gi].to_double()
  }
  let h_raw = 12.0 / (nf * (nf + 1.0)) * s - 3.0 * (nf + 1.0)
  let tie_denom = 1.0 - tie_term / (nf * nf * nf - nf)
  if tie_denom <= 0.0 {
    return kw_nan(k - 1)
  }
  let h = h_raw / tie_denom
  let df = k - 1
  // Wilson-Hilferty normal approximation to the chi-square upper tail.
  let p = chi_square_upper_p_wh(h, df)
  let d = df.to_double()
  let z = if h <= 0.0 {
    0.0
  } else {
    let m = 1.0 - 2.0 / (9.0 * d)
    let sd = (2.0 / (9.0 * d)).sqrt()
    let cube_root = @math.exp(@math.ln(h / d) / 3.0)
    (cube_root - m) / sd
  }
  { h, df, z, p_value: p }
}

///|
/// Wilson-Hilferty normal approximation to the upper-tail probability
/// `P(χ²_df ≥ h)`. Accurate to within a few percent for `df ≥ 2`.
fn chi_square_upper_p_wh(h : Double, df : Int) -> Double {
  if h.is_nan() {
    return @double.not_a_number
  }
  if df <= 0 {
    return @double.not_a_number
  }
  if h <= 0.0 {
    return 1.0
  }
  let d = df.to_double()
  let m = 1.0 - 2.0 / (9.0 * d)
  let sd = (2.0 / (9.0 * d)).sqrt()
  let cube_root = @math.exp(@math.ln(h / d) / 3.0)
  let z = (cube_root - m) / sd
  let p = 1.0 - @special_functions.normal_cdf(z)
  if p < 0.0 {
    0.0
  } else if p > 1.0 {
    1.0
  } else {
    p
  }
}

///|
fn kw_nan(df : Int) -> KruskalWallisResult {
  { h: @double.not_a_number, df, z: @double.not_a_number, p_value: @double.not_a_number }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "mann_whitney: completely separated samples are significant" {
  // x entirely below y => U1 = 0.
  let x = [1.0, 2.0, 3.0, 4.0]
  let y = [5.0, 6.0, 7.0, 8.0]
  let r = mann_whitney_u_test(x, y)
  assert_true((r.u1 - 0.0).abs() < 1.0e-9)
  assert_true((r.u2 - 16.0).abs() < 1.0e-9)
  assert_true((r.u - 0.0).abs() < 1.0e-9)
  // z = (0 - 8) / sqrt(12) ≈ -2.309, two-sided p ≈ 0.021.
  assert_true(r.z < 0.0)
  assert_true(r.p_value < 0.05)
  assert_true(r.p_value > 0.0)
}

///|
test "mann_whitney: interleaved samples are not significant" {
  let x = [1.0, 3.0, 5.0]
  let y = [2.0, 4.0, 6.0]
  let r = mann_whitney_u_test(x, y)
  // U1 = 3, U2 = 6, mean = 4.5, z ≈ -0.655, p ≈ 0.51.
  assert_true((r.u1 - 3.0).abs() < 1.0e-9)
  assert_true((r.u2 - 6.0).abs() < 1.0e-9)
  assert_true(r.p_value > 0.2)
}

///|
test "mann_whitney: ties are handled without aborting" {
  let x = [1.0, 2.0, 2.0, 3.0]
  let y = [2.0, 3.0, 4.0, 5.0]
  let r = mann_whitney_u_test(x, y)
  // U1 + U2 == n1 * n2 invariant always holds.
  assert_true((r.u1 + r.u2 - 16.0).abs() < 1.0e-9)
  assert_true(r.p_value >= 0.0 && r.p_value <= 1.0)
}

///|
test "mann_whitney: empty sample returns NaN" {
  let r = mann_whitney_u_test([], [1.0, 2.0])
  assert_true(r.p_value.is_nan())
}

///|
test "wilcoxon: all-positive differences are significant" {
  // d = [1,2,3,4,5], ranks 1..5, W+ = 15, mean = 7.5, z ≈ 2.021.
  let x = [1.0, 2.0, 3.0, 4.0, 5.0]
  let y = [0.0, 0.0, 0.0, 0.0, 0.0]
  let r = wilcoxon_signed_rank_test(x, y)
  assert_eq(r.n, 5)
  assert_true((r.w_plus - 15.0).abs() < 1.0e-9)
  assert_true(r.w_minus.abs() < 1.0e-9)
  assert_true(r.p_value < 0.06)
  assert_true(r.p_value > 0.0)
}

///|
test "wilcoxon: symmetric differences are not significant" {
  // d = [-1, 1, -1, 1], |d| all tie at rank 2.5, W+ = W- = 5, z = 0.
  let x = [1.0, 2.0, 3.0, 4.0]
  let y = [2.0, 1.0, 4.0, 3.0]
  let r = wilcoxon_signed_rank_test(x, y)
  assert_eq(r.n, 4)
  assert_true((r.w_plus - 5.0).abs() < 1.0e-9)
  assert_true((r.w_minus - 5.0).abs() < 1.0e-9)
  assert_true((r.p_value - 1.0).abs() < 1.0e-9)
}

///|
test "wilcoxon: zero differences are dropped" {
  let x = [5.0, 2.0, 5.0]
  let y = [5.0, 1.0, 5.0]
  let r = wilcoxon_signed_rank_test(x, y)
  // Only one non-zero difference (d = 1), n = 1.
  assert_eq(r.n, 1)
}

///|
test "wilcoxon: mismatched lengths return NaN" {
  let r = wilcoxon_signed_rank_test([1.0, 2.0], [1.0])
  assert_true(r.p_value.is_nan())
}

///|
test "kruskal_wallis: separated groups are significant" {
  // Ranks 1..9 split as 6, 15, 24 => H = 7.2, df = 2, p ≈ 0.027.
  let groups = [[1.0, 2.0, 3.0], [4.0, 5.0, 6.0], [7.0, 8.0, 9.0]]
  let r = kruskal_wallis_test(groups)
  assert_eq(r.df, 2)
  assert_true((r.h - 7.2).abs() < 1.0e-9)
  assert_true(r.p_value < 0.05)
  assert_true(r.p_value > 0.0)
}

///|
test "kruskal_wallis: interleaved groups are not significant" {
  // Each group draws one rank from {1,2,3}, {4,5,6}, {7,8,9}; rank sums
  // 12, 15, 18 => H = 0.8, df = 2, p ≈ 0.67.
  let groups = [[1.0, 4.0, 7.0], [2.0, 5.0, 8.0], [3.0, 6.0, 9.0]]
  let r = kruskal_wallis_test(groups)
  assert_true((r.h - 0.8).abs() < 1.0e-9)
  assert_true(r.p_value > 0.5)
}

///|
test "kruskal_wallis: ties are handled" {
  let groups = [[1.0, 2.0, 2.0], [2.0, 3.0, 4.0], [5.0, 6.0, 7.0]]
  let r = kruskal_wallis_test(groups)
  assert_eq(r.df, 2)
  assert_true(r.h >= 0.0)
  assert_true(r.p_value >= 0.0 && r.p_value <= 1.0)
}

///|
test "kruskal_wallis: single group returns NaN" {
  let r = kruskal_wallis_test([[1.0, 2.0, 3.0]])
  assert_true(r.p_value.is_nan())
}
