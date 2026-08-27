/// Analysis of Variance (ANOVA).
///
/// This package implements:
///
/// - **One-way ANOVA** (`one_way_anova`): tests whether the means of two or
///   more independent groups are equal. It decomposes the total variance into
///   a between-groups component (SSB) and a within-groups component (SSW),
///   then forms the F statistic `F = MSB / MSW` with `(k−1, N−k)` degrees of
///   freedom. The p-value is the upper tail of the F-distribution, computed
///   via a self-contained regularised incomplete beta function
///   (`f_distribution_cdf`).
/// - **Two-way ANOVA without replication** (`two_way_anova_no_replication`):
///   the randomised complete block design with one observation per cell. It
///   simultaneously tests two factors (A = rows, B = columns) against a
///   residual error, producing separate F statistics and p-values for each
///   factor with degrees of freedom `(a−1, (a−1)(b−1))` and
///   `(b−1, (a−1)(b−1))`.
///
/// ## Sum-of-squares identities
///
/// One-way:
///
/// ```text
/// SSB = Σ_i n_i · (x̄_i − x̄)²       df = k − 1
/// SSW = Σ_i Σ_j (x_ij − x̄_i)²       df = N − k
/// SST = SSB + SSW                    df = N − 1
/// ```
///
/// Two-way (no replication, a rows × b columns):
///
/// ```text
/// SSA = b · Σ_i (x̄_i. − x̄)²         df = a − 1
/// SSB = a · Σ_j (x̄_.j − x̄)²         df = b − 1
/// SSE = SST − SSA − SSB              df = (a−1)(b−1)
/// ```
///
/// ## Edge-case policy
///
/// Degenerate inputs (fewer than 2 groups, non-positive residual degrees of
/// freedom, or empty data) yield a result whose `f_statistic` and `p_value`
/// are `NaN`. A zero residual mean square with a non-zero factor mean square
/// yields `f_statistic = +∞` and `p_value = 0.0`. No function calls `abort`.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// One-way ANOVA
// ---------------------------------------------------------------------------

///|
/// Result of a one-way ANOVA.
///
/// All sum-of-squares fields are in squared-data units. `p_value` is the
/// upper-tail probability `P(F ≥ f_statistic)` under `F(df_between, df_within)`.
pub struct OneWayAnovaResult {
  ssb : Double // between-groups sum of squares
  ssw : Double // within-groups (error) sum of squares
  sst : Double // total sum of squares
  df_between : Int
  df_within : Int
  msb : Double // between-groups mean square = ssb / df_between
  msw : Double // within-groups mean square = ssw / df_within
  f_statistic : Double
  p_value : Double
}

///|
/// Perform a one-way (single-factor) ANOVA on `groups`.
///
/// `groups[i]` is the sample of observations for treatment `i`. Groups may
/// have unequal sizes. The grand mean is the size-weighted mean of all
/// observations.
///
/// Returns a [`OneWayAnovaResult`] with `NaN` statistics when there are
/// fewer than 2 non-empty groups or the residual degrees of freedom is
/// non-positive (`N ≤ k`).
pub fn one_way_anova(groups : Array[Array[Double]]) -> OneWayAnovaResult {
  // Pass 1: accumulate sizes and the grand sum over non-empty groups.
  let sizes : Array[Int] = []
  let mut n_total = 0
  let mut grand_sum = 0.0
  for g in groups {
    let n = g.length()
    if n > 0 {
      sizes.push(n)
      n_total = n_total + n
      for x in g {
        grand_sum = grand_sum + x
      }
    }
  }
  let k = sizes.length()
  // Degenerate: need at least 2 groups and a positive residual df.
  if k < 2 || n_total - k < 1 {
    return {
      ssb: 0.0,
      ssw: 0.0,
      sst: 0.0,
      df_between: if k > 1 {
        k - 1
      } else {
        0
      },
      df_within: if n_total > k {
        n_total - k
      } else {
        0
      },
      msb: 0.0,
      msw: 0.0,
      f_statistic: @double.not_a_number,
      p_value: @double.not_a_number,
    }
  }
  let grand_mean = grand_sum / n_total.to_double()
  // Pass 2: SSB, SSW, SST.
  let mut ssb = 0.0
  let mut ssw = 0.0
  let mut sst = 0.0
  for g in groups {
    let n = g.length()
    if n == 0 {
      continue
    }
    let mut sum_i = 0.0
    for x in g {
      sum_i = sum_i + x
    }
    let mean_i = sum_i / n.to_double()
    let d_between = mean_i - grand_mean
    ssb = ssb + n.to_double() * d_between * d_between
    for x in g {
      let d_within = x - mean_i
      ssw = ssw + d_within * d_within
      let d_total = x - grand_mean
      sst = sst + d_total * d_total
    }
  }
  let df_between = k - 1
  let df_within = n_total - k
  let msb = ssb / df_between.to_double()
  let msw = ssw / df_within.to_double()
  let f_statistic = if msw == 0.0 {
    if msb <= 0.0 {
      @double.not_a_number
    } else {
      @double.infinity
    }
  } else {
    msb / msw
  }
  let p_value = f_upper_tail_pvalue(f_statistic, df_between, df_within)
  { ssb, ssw, sst, df_between, df_within, msb, msw, f_statistic, p_value, }
}

// ---------------------------------------------------------------------------
// Two-way ANOVA (no replication / randomised complete block)
// ---------------------------------------------------------------------------

///|
/// Result of a two-way ANOVA without replication.
///
/// `ss_a` / `ss_b` are the sum of squares for factors A (rows) and B
/// (columns); `ss_error` is the residual. `p_a` and `p_b` are the upper-tail
/// p-values for the respective F tests.
pub struct TwoWayAnovaResult {
  ss_a : Double
  ss_b : Double
  ss_error : Double
  ss_total : Double
  df_a : Int
  df_b : Int
  df_error : Int
  ms_a : Double
  ms_b : Double
  ms_error : Double
  f_a : Double
  f_b : Double
  p_a : Double
  p_b : Double
}

///|
/// Perform a two-way ANOVA without replication on `data`.
///
/// `data[i][j]` is the single observation at row `i` (factor A, `a` levels)
/// and column `j` (factor B, `b` levels). Every cell must contain exactly one
/// observation. The design decomposes the total variance into factor A,
/// factor B, and a residual (interaction is not estimable without
/// replication).
///
/// Returns a [`TwoWayAnovaResult`] with `NaN` statistics when the design is
/// too small (`a < 2` or `b < 2`) or a row/column has a mismatched length.
pub fn two_way_anova_no_replication(
  data : Array[Array[Double]],
) -> TwoWayAnovaResult {
  let a = data.length()
  // Degenerate: need at least 2 rows.
  if a < 2 {
    return degenerate_two_way(a, 0)
  }
  let b = data[0].length()
  if b < 2 {
    return degenerate_two_way(a, b)
  }
  // Validate rectangular shape.
  for i = 0; i < a; i = i + 1 {
    if data[i].length() != b {
      return degenerate_two_way(a, b)
    }
  }
  let total = a * b
  let grand_mean = {
    let mut s = 0.0
    for i = 0; i < a; i = i + 1 {
      for j = 0; j < b; j = j + 1 {
        s = s + data[i][j]
      }
    }
    s / total.to_double()
  }
  // Row means (factor A) and column means (factor B).
  let row_means = Array::make(a, 0.0)
  let col_means = Array::make(b, 0.0)
  for i = 0; i < a; i = i + 1 {
    let mut s = 0.0
    for j = 0; j < b; j = j + 1 {
      s = s + data[i][j]
    }
    row_means[i] = s / b.to_double()
  }
  for j = 0; j < b; j = j + 1 {
    let mut s = 0.0
    for i = 0; i < a; i = i + 1 {
      s = s + data[i][j]
    }
    col_means[j] = s / a.to_double()
  }
  let mut ss_a = 0.0
  let mut ss_b = 0.0
  let mut ss_total = 0.0
  for i = 0; i < a; i = i + 1 {
    let d = row_means[i] - grand_mean
    ss_a = ss_a + d * d
  }
  ss_a = ss_a * b.to_double()
  for j = 0; j < b; j = j + 1 {
    let d = col_means[j] - grand_mean
    ss_b = ss_b + d * d
  }
  ss_b = ss_b * a.to_double()
  for i = 0; i < a; i = i + 1 {
    for j = 0; j < b; j = j + 1 {
      let d = data[i][j] - grand_mean
      ss_total = ss_total + d * d
    }
  }
  let ss_error = ss_total - ss_a - ss_b
  let df_a = a - 1
  let df_b = b - 1
  let df_error = df_a * df_b
  let ms_a = ss_a / df_a.to_double()
  let ms_b = ss_b / df_b.to_double()
  let ms_error = ss_error / df_error.to_double()
  let f_a = if ms_error == 0.0 {
    if ms_a <= 0.0 {
      @double.not_a_number
    } else {
      @double.infinity
    }
  } else {
    ms_a / ms_error
  }
  let f_b = if ms_error == 0.0 {
    if ms_b <= 0.0 {
      @double.not_a_number
    } else {
      @double.infinity
    }
  } else {
    ms_b / ms_error
  }
  let p_a = f_upper_tail_pvalue(f_a, df_a, df_error)
  let p_b = f_upper_tail_pvalue(f_b, df_b, df_error)
  {
    ss_a,
    ss_b,
    ss_error,
    ss_total,
    df_a,
    df_b,
    df_error,
    ms_a,
    ms_b,
    ms_error,
    f_a,
    f_b,
    p_a,
    p_b,
  }
}

// ---------------------------------------------------------------------------
// Internal helpers: F-distribution CDF
// ---------------------------------------------------------------------------

///|
/// Upper-tail p-value `P(F ≥ f)` for the F-distribution with `d1, d2` degrees
/// of freedom. Handles the `NaN` / `+∞` / non-positive sentinels produced by
/// the ANOVA routines without invoking the CDF on them.
fn f_upper_tail_pvalue(f : Double, d1 : Int, d2 : Int) -> Double {
  if f.is_nan() {
    return @double.not_a_number
  }
  // The ANOVA routines only ever emit a positive-infinity sentinel (a
  // non-zero factor mean square against a zero residual). Treat it as a
  // certain rejection: p = 0.
  if f == @double.infinity {
    return 0.0
  }
  if f <= 0.0 {
    return 1.0
  }
  if d1 <= 0 || d2 <= 0 {
    return @double.not_a_number
  }
  let cdf = f_distribution_cdf(f, d1.to_double(), d2.to_double())
  let p = 1.0 - cdf
  if p < 0.0 {
    0.0
  } else if p > 1.0 {
    1.0
  } else {
    p
  }
}

///|
/// Cumulative distribution function of the F-distribution with `d1, d2`
/// degrees of freedom.
///
/// ```text
/// F(x; d1, d2) = I_{ d1·x / (d1·x + d2) }(d1/2, d2/2)
/// ```
///
/// where `I_z(a, b)` is the regularised incomplete beta function. The
/// incomplete beta is evaluated with the standard Lentz continued-fraction
/// expansion (Numerical Recipes §6.4), using the symmetry relation to keep
/// the fraction converging rapidly. Accuracy is ~1e-14 for Double inputs.
fn f_distribution_cdf(x : Double, d1 : Double, d2 : Double) -> Double {
  if x <= 0.0 || d1 <= 0.0 || d2 <= 0.0 {
    return 0.0
  }
  let z = d1 * x / (d1 * x + d2)
  regularized_incomplete_beta(z, d1 / 2.0, d2 / 2.0)
}

///|
/// Regularised incomplete beta function `I_x(a, b) = B_x(a,b) / B(a,b)`.
///
/// Uses the continued-fraction representation of the incomplete beta,
/// selecting the direct or complementary branch via the standard symmetry
/// test `x < (a+1)/(a+b+2)` to maximise convergence.
fn regularized_incomplete_beta(x : Double, a : Double, b : Double) -> Double {
  if x <= 0.0 {
    return 0.0
  }
  if x >= 1.0 {
    return 1.0
  }
  if a <= 0.0 || b <= 0.0 {
    return 0.0
  }
  let lbeta = @special_functions.lgamma(a + b) -
    @special_functions.lgamma(a) -
    @special_functions.lgamma(b)
  let front = @math.exp(lbeta + a * @math.ln(x) + b * @math.ln(1.0 - x))
  if x < (a + 1.0) / (a + b + 2.0) {
    front * beta_continued_fraction(x, a, b) / a
  } else {
    1.0 - front * beta_continued_fraction(1.0 - x, b, a) / b
  }
}

///|
/// Continued fraction for the incomplete beta function, evaluated with
/// Lentz's method (Numerical Recipes §6.4). Returns the factor that, when
/// multiplied by `front / a`, yields `I_x(a, b)`.
fn beta_continued_fraction(x : Double, a : Double, b : Double) -> Double {
  let fpmin = 1.0e-30
  let qab = a + b
  let qap = a + 1.0
  let qam = a - 1.0
  let mut c = 1.0
  let mut d = 1.0 - qab * x / qap
  if d.abs() < fpmin {
    d = fpmin
  }
  d = 1.0 / d
  let mut h = d
  let mut m = 1
  while m < 300 {
    let mf = m.to_double()
    let m2 = (2 * m).to_double()
    // Even step.
    let aa = mf * (b - mf) * x / ((qam + m2) * (a + m2))
    d = 1.0 + aa * d
    if d.abs() < fpmin {
      d = fpmin
    }
    c = 1.0 + aa / c
    if c.abs() < fpmin {
      c = fpmin
    }
    d = 1.0 / d
    h = h * d * c
    // Odd step.
    let aa2 = -(a + mf) * (qab + mf) * x / ((a + m2) * (qap + m2))
    d = 1.0 + aa2 * d
    if d.abs() < fpmin {
      d = fpmin
    }
    c = 1.0 + aa2 / c
    if c.abs() < fpmin {
      c = fpmin
    }
    d = 1.0 / d
    let del = d * c
    h = h * del
    if (del - 1.0).abs() < 1.0e-15 {
      break
    }
    m = m + 1
  }
  h
}

///|
/// Build a degenerate (all-`NaN`) two-way result for invalid inputs.
fn degenerate_two_way(a : Int, b : Int) -> TwoWayAnovaResult {
  {
    ss_a: 0.0,
    ss_b: 0.0,
    ss_error: 0.0,
    ss_total: 0.0,
    df_a: if a > 1 {
      a - 1
    } else {
      0
    },
    df_b: if b > 1 {
      b - 1
    } else {
      0
    },
    df_error: if a > 1 && b > 1 {
      (a - 1) * (b - 1)
    } else {
      0
    },
    ms_a: 0.0,
    ms_b: 0.0,
    ms_error: 0.0,
    f_a: @double.not_a_number,
    f_b: @double.not_a_number,
    p_a: @double.not_a_number,
    p_b: @double.not_a_number,
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "one_way_anova: significant difference between groups" {
  // Three groups with clearly separated means: 2, 5, 8.
  let groups = [[1.0, 2.0, 3.0], [4.0, 5.0, 6.0], [7.0, 8.0, 9.0]]
  let r = one_way_anova(groups)
  // SSB = 3*(2-5)^2 + 0 + 3*(8-5)^2 = 54
  assert_true((r.ssb - 54.0).abs() < 1.0e-9)
  // SSW = 2 + 2 + 2 = 6
  assert_true((r.ssw - 6.0).abs() < 1.0e-9)
  // SST = SSB + SSW = 60
  assert_true((r.sst - 60.0).abs() < 1.0e-9)
  assert_eq(r.df_between, 2)
  assert_eq(r.df_within, 6)
  // MSB = 27, MSW = 1, F = 27.
  assert_true((r.msb - 27.0).abs() < 1.0e-9)
  assert_true((r.msw - 1.0).abs() < 1.0e-9)
  assert_true((r.f_statistic - 27.0).abs() < 1.0e-9)
  // Highly significant.
  assert_true(r.p_value < 0.01)
  assert_true(r.p_value > 0.0)
}

///|
test "one_way_anova: no significant difference" {
  // Same multiset in each group => identical means => F = 0.
  let groups = [[1.0, 2.0, 3.0], [2.0, 3.0, 1.0], [3.0, 1.0, 2.0]]
  let r = one_way_anova(groups)
  assert_true(r.ssb.abs() < 1.0e-9)
  // p-value for F = 0 is 1.0.
  assert_true((r.p_value - 1.0).abs() < 1.0e-9)
  assert_true(r.f_statistic.abs() < 1.0e-9)
}

///|
test "one_way_anova: unequal group sizes" {
  // Group means 2 and 5, sizes 4 and 2.
  // Grand mean = (1+2+3+2 + 4+5)/6 = 17/6
  let groups = [[1.0, 2.0, 3.0, 2.0], [4.0, 5.0]]
  let r = one_way_anova(groups)
  assert_eq(r.df_between, 1)
  assert_eq(r.df_within, 4)
  // F should be large (means differ), p small.
  assert_true(r.f_statistic > 10.0)
  assert_true(r.p_value < 0.05)
}

///|
test "one_way_anova: degenerate inputs return NaN" {
  let r1 = one_way_anova([[1.0, 2.0, 3.0]])
  assert_true(r1.f_statistic.is_nan())
  assert_true(r1.p_value.is_nan())
  // Residual df == 0 (N == k with one observation each).
  let r2 = one_way_anova([[1.0], [2.0]])
  assert_true(r2.f_statistic.is_nan())
}

///|
test "two_way_anova: known F statistics" {
  // a = 2 rows, b = 3 columns.
  // By exact arithmetic: F_A = 49/4 = 12.25, F_B = 7.0.
  let data = [[1.0, 2.0, 5.0], [4.0, 5.0, 6.0]]
  let r = two_way_anova_no_replication(data)
  assert_eq(r.df_a, 1)
  assert_eq(r.df_b, 2)
  assert_eq(r.df_error, 2)
  assert_true((r.f_a - 12.25).abs() < 1.0e-9)
  assert_true((r.f_b - 7.0).abs() < 1.0e-9)
  assert_true(r.p_a > 0.0 && r.p_a < 1.0)
  assert_true(r.p_b > 0.0 && r.p_b < 1.0)
  // SS identity: SST = SSA + SSB + SSE.
  let recon = r.ss_a + r.ss_b + r.ss_error
  assert_true((recon - r.ss_total).abs() < 1.0e-9)
}

///|
test "two_way_anova: factor with no effect" {
  // Column sums are equal (col0 = 1+5 = 6, col1 = 3+3 = 6) => column
  // means are identical => SS_B = 0 => F_B = 0 => p_B = 1, while the row
  // factor and a non-zero residual remain.
  let data = [[1.0, 3.0], [5.0, 3.0]]
  let r = two_way_anova_no_replication(data)
  assert_true(r.ss_b.abs() < 1.0e-9)
  assert_true(r.f_b.abs() < 1.0e-9)
  assert_true((r.p_b - 1.0).abs() < 1.0e-9)
  // Row factor and residual are non-zero.
  assert_true(r.ss_a > 0.0)
  assert_true(r.ss_error > 0.0)
}

///|
test "two_way_anova: degenerate design returns NaN" {
  let r = two_way_anova_no_replication([[1.0, 2.0, 3.0]])
  assert_true(r.f_a.is_nan())
  assert_true(r.f_b.is_nan())
}

///|
test "two_way_anova: ragged matrix returns NaN" {
  let r = two_way_anova_no_replication([[1.0, 2.0, 3.0], [4.0, 5.0]])
  assert_true(r.f_a.is_nan())
}
