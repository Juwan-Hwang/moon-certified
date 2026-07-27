/// PCA — Principal Component Analysis via power iteration.
///
/// Linear dimensionality reduction: rotate the feature space so that the
/// first axes point along the directions of greatest variance, then keep only
/// the top `n_components`. The rotation is the eigendecomposition of the
/// (sample) covariance matrix; the eigenvectors are the *principal
/// components* and the eigenvalues are the *explained variances*.
///
/// ## Algorithm
/// 1. **Centre** the data by subtracting the per-feature mean.
/// 2. **Covariance** `C = (1/(n-1)) X_c^T X_c`, a `d×d` symmetric matrix
///    (`d` = feature count). The lower triangle is accumulated once and
///    mirrored, halving the work.
/// 3. **Eigendecomposition** by *power iteration with deflation*: for each
///    component, a vector is iterated `v ← C v / ‖C v‖` until the Rayleigh
///    quotient `λ = v^T C v` stabilises. Orthogonalising every iterate against
///    the already-found components performs deflation *implicitly* (no matrix
///    rewrite), guaranteeing an orthonormal basis ordered by descending
///    eigenvalue.
///
/// ## Complexity
/// - Time:  `O(n·d² + n_components·iter·d²)` — covariance build plus
///   `n_components` power sweeps, each doing a constant number of `d×d`
///   matrix-vector products per iteration.
/// - Space: `O(d²)` for the covariance matrix and the component store.
///
/// No external linear-algebra dependency is used: every primitive (dot
/// product, matrix-vector product, L2 norm, Gram-Schmidt) is implemented
/// locally and dimension-checked.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

///|
/// Maximum power-iteration sweeps per component. Power iteration converges
/// linearly at rate `λ₂/λ₁`; for well-separated spectra a few dozen sweeps
/// suffice, so this is a generous safety ceiling.
let pca_max_iter : Int = 1000

///|
/// Relative convergence tolerance on the Rayleigh quotient: the iteration
/// stops once `|Δλ| ≤ tol·(1 + |λ|)`, i.e. the eigenvalue has stabilised to
/// roughly `tol` relative precision.
let pca_tol : Double = 1.0e-12

///|
/// Floor on an initial vector's norm after Gram-Schmidt: below this the
/// random draw is deemed to lie (numerically) in the span of prior
/// components, triggering the canonical-basis fallback. The orthogonal
/// complement of `prev` is always at least one-dimensional because
/// `n_components ≤ d`, so a valid direction always exists.
let pca_init_min_norm : Double = 1.0e-12

// ---------------------------------------------------------------------------
// Deterministic PRNG (same LCG family used across moon-certified)
// ---------------------------------------------------------------------------

///|
/// LCG multiplier and increment (≡ 1 mod 4 / odd) with a 31-bit mask, giving
/// a full-period generator mod 2³¹ (Hull-Dobell). Reused verbatim by
/// `fisher_yates`, `reservoir_sampling` and `kmeans`, so every PCA run is
/// bit-for-bit reproducible.
let pca_lcg_a : Int = 1103515245

///|
let pca_lcg_c : Int = 12345

///|
/// Reproducible default seed (matches `kmeans`).
let pca_default_seed : Int = 0x1A2B3C4D

///|
/// Private mutable LCG state; `next` advances it and returns a value in
/// `[0, 2³¹)`.
priv struct Rng {
  mut state : Int
}

///|
/// Create an LCG from `seed`; a zero seed is replaced by `1` so the stream
/// never sits at the trivial fixed point.
fn Rng::new(seed : Int) -> Rng {
  let s = seed & 0x7FFFFFFF
  { state: if s == 0 { 1 } else { s } }
}

///|
/// Advance one step; the 31-bit mask keeps the recurrence correct mod 2³¹.
fn Rng::next(self : Rng) -> Int {
  self.state = (self.state * pca_lcg_a + pca_lcg_c) & 0x7FFFFFFF
  self.state
}

///|
/// Draw a `Double` in `[0, 1)` from the next state.
fn Rng::next_double(self : Rng) -> Double {
  self.next().to_double() / 2147483648.0
}

// ---------------------------------------------------------------------------
// Vector / matrix primitives (local, dimension-checked)
// ---------------------------------------------------------------------------

///|
/// Dot product of two equal-length vectors. Returns `0.0` on length mismatch
/// — a safe neutral value — since this helper is only ever called internally
/// with vectors of matching length (constructed to be so).
fn pca_dot(a : Array[Double], b : Array[Double]) -> Double {
  let n = a.length()
  if b.length() != n {
    return 0.0
  }
  let mut s = 0.0
  for i = 0; i < n; i = i + 1 {
    s = s + a[i] * b[i]
  }
  s
}

///|
/// Euclidean (L2) norm of a vector. Uses the `Double::sqrt` method (the
/// squared-sum is non-negative, so the argument to `sqrt` is always valid).
fn pca_l2_norm(v : Array[Double]) -> Double {
  pca_dot(v, v).sqrt()
}

///|
/// Matrix-vector product `out = m · v`, where `m` is row-major `d×d` and `v`
/// has length `d`. Built only with vectors of matching dimension.
fn pca_mat_vec(m : Array[Array[Double]], v : Array[Double]) -> Array[Double] {
  let d = m.length()
  let out = Array::make(d, 0.0)
  for i = 0; i < d; i = i + 1 {
    let row = m[i]
    let mut s = 0.0
    for j = 0; j < d; j = j + 1 {
      s = s + row[j] * v[j]
    }
    out[i] = s
  }
  out
}

///|
/// Rayleigh quotient `λ = vᵀ C v` for a unit vector `v`. Because `v` is
/// normalised this equals the eigenvalue estimate of the dominant eigenvector
/// aligned with `v`.
fn pca_rayleigh(cov : Array[Array[Double]], v : Array[Double]) -> Double {
  pca_dot(v, pca_mat_vec(cov, v))
}

///|
/// In-place Gram-Schmidt: subtract from `v` its projection onto every vector
/// in `prev` (assumed orthonormal), leaving `v` orthogonal to all of them.
fn pca_orthogonalize_in_place(
  v : Array[Double],
  prev : Array[Array[Double]],
) -> Unit {
  for k = 0; k < prev.length(); k = k + 1 {
    let u = prev[k]
    let proj = pca_dot(v, u)
    for i = 0; i < v.length(); i = i + 1 {
      v[i] = v[i] - proj * u[i]
    }
  }
}

///|
/// Normalise `v` in place to unit L2 length and return the pre-normalisation
/// norm. A zero vector is left untouched (and `0.0` returned) so the caller
/// can detect the degenerate case.
fn pca_normalize_in_place(v : Array[Double]) -> Double {
  let nrm = pca_l2_norm(v)
  if nrm > 0.0 {
    for i = 0; i < v.length(); i = i + 1 {
      v[i] = v[i] / nrm
    }
  }
  nrm
}

///|
/// Pin the arbitrary sign of an eigenvector so that its largest-magnitude
/// entry is positive. This makes the components bit-stable across runs
/// regardless of the random init's sign.
fn pca_fix_sign(v : Array[Double]) -> Unit {
  let n = v.length()
  if n == 0 {
    return
  }
  let mut max_idx = 0
  let mut max_abs = v[0].abs()
  for i = 1; i < n; i = i + 1 {
    let a = v[i].abs()
    if a > max_abs {
      max_abs = a
      max_idx = i
    }
  }
  if v[max_idx] < 0.0 {
    for i = 0; i < n; i = i + 1 {
      v[i] = -v[i]
    }
  }
}

///|
/// Build a unit start vector for the next power sweep. A pseudo-random draw
/// is orthogonalised against `prev` (the components already found); if it
/// collapses — possible only when it lands exactly in span(prev) — the first
/// canonical basis vector surviving orthogonalisation is used instead. Such a
/// vector always exists because `prev` holds fewer than `d` vectors.
fn pca_init_vector(
  d : Int,
  prev : Array[Array[Double]],
  rng : Rng,
) -> Array[Double] {
  let v = Array::make(d, 0.0)
  for j = 0; j < d; j = j + 1 {
    v[j] = rng.next_double() - 0.5
  }
  pca_orthogonalize_in_place(v, prev)
  if pca_l2_norm(v) >= pca_init_min_norm {
    return v
  }
  // Fallback: scan canonical basis vectors for one outside span(prev).
  for j = 0; j < d; j = j + 1 {
    let e = Array::make(d, 0.0)
    e[j] = 1.0
    pca_orthogonalize_in_place(e, prev)
    if pca_l2_norm(e) >= pca_init_min_norm {
      return e
    }
  }
  // Unreachable when d > 0 and prev.size < d; keep the call total anyway.
  Array::make(d, 0.0)
}

// ---------------------------------------------------------------------------
// Power iteration with implicit deflation
// ---------------------------------------------------------------------------

///|
/// Find the dominant eigenvector of `cov` restricted to the orthogonal
/// complement of `prev`, together with its eigenvalue (the Rayleigh
/// quotient). Returns a unit vector. The caller records it in `prev` so the
/// next call targets the next principal component.
fn pca_power_iteration(
  cov : Array[Array[Double]],
  d : Int,
  prev : Array[Array[Double]],
  rng : Rng,
) -> (Array[Double], Double) {
  let mut v = pca_init_vector(d, prev, rng)
  ignore(pca_normalize_in_place(v))
  let mut lambda = pca_rayleigh(cov, v)
  for it = 0; it < pca_max_iter; it = it + 1 {
    // One power step: w = C v, then stay in prev's orthogonal complement.
    let w = pca_mat_vec(cov, v)
    pca_orthogonalize_in_place(w, prev)
    let nrm = pca_normalize_in_place(w)
    if nrm < pca_tol {
      // C v ≈ 0: v is (numerically) a null-space direction of the deflated
      // operator. The remaining variance along it is ~0.
      lambda = 0.0
      break
    }
    v = w
    let new_lambda = pca_rayleigh(cov, v)
    // Relative-tolerance convergence test, robust to the eigenvalue scale.
    if (new_lambda - lambda).abs() <= pca_tol * (1.0 + lambda.abs()) {
      lambda = new_lambda
      break
    }
    lambda = new_lambda
  }
  (v, lambda)
}

// ---------------------------------------------------------------------------
// Statistics: mean and (sample) covariance
// ---------------------------------------------------------------------------

///|
/// Per-feature mean of the rows of `data`. Rows shorter than `d` contribute
/// `0` to the missing entries, so ragged input degrades gracefully rather
/// than trapping.
fn pca_compute_mean(data : Array[Array[Double]], d : Int) -> Array[Double] {
  let n = data.length()
  let mean = Array::make(d, 0.0)
  for i = 0; i < n; i = i + 1 {
    let row = data[i]
    let m = row.length()
    for j = 0; j < d; j = j + 1 {
      if j < m {
        mean[j] = mean[j] + row[j]
      }
    }
  }
  if n > 0 {
    let nd = n.to_double()
    for j = 0; j < d; j = j + 1 {
      mean[j] = mean[j] / nd
    }
  }
  mean
}

///|
/// Sample covariance matrix `C = (1/(n-1)) X_cᵀ X_c` of the centred data, as
/// a `d×d` row-major array. Only the lower triangle is accumulated (exploiting
/// symmetry) and then mirrored. With `n == 1` the divisor is `1` and every
/// entry is `0` (a single sample carries no variance).
fn pca_compute_covariance(
  data : Array[Array[Double]],
  mean : Array[Double],
  d : Int,
) -> Array[Array[Double]] {
  let n = data.length()
  let cov : Array[Array[Double]] = []
  for i = 0; i < d; i = i + 1 {
    cov.push(Array::make(d, 0.0))
  }
  for s = 0; s < n; s = s + 1 {
    let row = data[s]
    let m = row.length()
    for a = 0; a < d; a = a + 1 {
      let va = (if a < m { row[a] } else { 0.0 }) - mean[a]
      let cov_a = cov[a]
      for b = 0; b <= a; b = b + 1 {
        let vb = (if b < m { row[b] } else { 0.0 }) - mean[b]
        cov_a[b] = cov_a[b] + va * vb
      }
    }
  }
  let denom = if n > 1 { (n - 1).to_double() } else { 1.0 }
  for a = 0; a < d; a = a + 1 {
    let cov_a = cov[a]
    for b = 0; b <= a; b = b + 1 {
      let val = cov_a[b] / denom
      cov_a[b] = val
      cov[b][a] = val
    }
  }
  cov
}

// ---------------------------------------------------------------------------
// Public types & entry points
// ---------------------------------------------------------------------------

///|
/// The fitted PCA model.
///
/// - `components`          — principal axes as rows; `components[i]` is the
///   `i`-th eigenvector (unit length, mutually orthonormal) of the covariance
///   matrix, ordered by descending eigenvalue.
/// - `mean`                — per-feature mean subtracted before projection.
/// - `explained_variance`  — eigenvalue of each component, i.e. the variance
///   of the data along that axis. Summing it gives the variance captured by
///   the kept components; comparing against the covariance trace gives the
///   fraction of total variance retained.
pub struct PCAResult {
  components : Array[Array[Double]]
  mean : Array[Double]
  explained_variance : Array[Double]
}

///|
/// Fit PCA on `data` and keep the top `n_components` principal components.
///
/// **Parameters.**
/// - `data`         — sample matrix, rows = samples, cols = features. All
///   rows should share the same length; the feature count `d` is taken from
///   the first row.
/// - `n_components` — number of principal axes to keep; clamped to
///   `[1, d]`. Values `< 1` are treated as `1`.
///
/// **Return value.** A `PCAResult` whose `components` has `n_components`
/// orthonormal rows, `mean` has `d` entries, and `explained_variance` has
/// `n_components` entries sorted from largest to smallest.
///
/// **Edge cases.**
/// - Empty data (or `d == 0`) → empty `components`, `mean` and
///   `explained_variance`.
/// - `n == 1` → covariance is the zero matrix; components are an arbitrary
///   orthonormal basis with `explained_variance` all `0`.
/// - `n_components > d` → clamped to `d` (every axis retained).
///
/// **Determinism.** A fixed LCG seeds the power-iteration start vectors and
/// `pca_fix_sign` pins each eigenvector's sign, so identical input yields
/// identical output across runs.
pub fn pca(data : Array[Array[Double]], n_components : Int) -> PCAResult {
  let n = data.length()
  if n == 0 {
    return { components: [], mean: [], explained_variance: [] }
  }
  let d = data[0].length()
  if d == 0 {
    return { components: [], mean: [], explained_variance: [] }
  }
  let mean = pca_compute_mean(data, d)
  let cov = pca_compute_covariance(data, mean, d)
  let n_comp = if n_components < 1 {
    1
  } else if n_components > d {
    d
  } else {
    n_components
  }
  let rng = Rng::new(pca_default_seed)
  let components : Array[Array[Double]] = []
  let explained : Array[Double] = []
  let prev : Array[Array[Double]] = []
  for c = 0; c < n_comp; c = c + 1 {
    let (v, lambda) = pca_power_iteration(cov, d, prev, rng)
    pca_fix_sign(v)
    components.push(v)
    explained.push(lambda)
    prev.push(v)
  }
  { components, mean, explained_variance: explained }
}

///|
/// Project a single `sample` onto the fitted components.
///
/// Centres the sample by `result.mean`, then returns its coordinates in the
/// principal-axes basis: `out[i] = (sample - mean) · components[i]`.
///
/// Returns an empty array when the result has no components, or when the
/// sample's dimension disagrees with the fitted feature count — no `abort`
/// is raised.
pub fn pca_transform(
  result : PCAResult,
  sample : Array[Double],
) -> Array[Double] {
  let mean = result.mean
  let comps = result.components
  let nc = comps.length()
  if nc == 0 {
    return []
  }
  let d = mean.length()
  if sample.length() != d {
    return []
  }
  let out : Array[Double] = []
  for c = 0; c < nc; c = c + 1 {
    let comp = comps[c]
    let mut s = 0.0
    for j = 0; j < d; j = j + 1 {
      s = s + (sample[j] - mean[j]) * comp[j]
    }
    out.push(s)
  }
  out
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

///|
/// Tolerant `Double` equality: passes within an absolute bound (`1e-6`) or a
/// relative bound (`1e-6` of the combined magnitude).
fn approx_eq(a : Double, b : Double) -> Bool {
  let diff = (a - b).abs()
  diff < 1.0e-6 || diff < 1.0e-6 * (a.abs() + b.abs())
}

///|
/// `true` when `v` entrywise equals `expected` within tolerance.
fn vec_approx_eq(v : Array[Double], expected : Array[Double]) -> Bool {
  if v.length() != expected.length() {
    return false
  }
  for i = 0; i < v.length(); i = i + 1 {
    if !approx_eq(v[i], expected[i]) {
      return false
    }
  }
  true
}

///|
/// Sum of an array of doubles.
fn sum_arr(xs : Array[Double]) -> Double {
  let mut s = 0.0
  for i = 0; i < xs.length(); i = i + 1 {
    s = s + xs[i]
  }
  s
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "pca: empty data yields an empty result" {
  let r = pca([], 2)
  assert_eq(r.components.length(), 0)
  assert_eq(r.mean.length(), 0)
  assert_eq(r.explained_variance.length(), 0)
}

///|
test "pca: n_components clamped to feature count" {
  // 2 features, ask for 5 components -> clamped to 2.
  let data = [[0.0, 0.0], [2.0, 0.0], [0.0, 1.0], [2.0, 1.0]]
  let r = pca(data, 5)
  assert_eq(r.components.length(), 2)
  assert_eq(r.explained_variance.length(), 2)
}

///|
test "pca: n_components <= 0 is treated as 1" {
  let data = [[0.0], [1.0], [2.0], [3.0]]
  let r = pca(data, 0)
  assert_eq(r.components.length(), 1)
  assert_eq(r.explained_variance.length(), 1)
}

///|
test "pca: single sample gives zero variance, unit component" {
  let data = [[5.0, 7.0]]
  let r = pca(data, 1)
  assert_eq(r.mean.length(), 2)
  assert_true(approx_eq(r.mean[0], 5.0))
  assert_true(approx_eq(r.mean[1], 7.0))
  assert_eq(r.explained_variance.length(), 1)
  assert_true(approx_eq(r.explained_variance[0], 0.0))
  // The lone component is a unit vector.
  let comp = r.components[0]
  assert_true(approx_eq(pca_l2_norm(comp), 1.0))
}

///|
test "pca: 1-D variance recovered exactly" {
  // points 1,2,3 -> mean 2, sample variance (1+0+1)/2 = 1.
  let data = [[1.0], [2.0], [3.0]]
  let r = pca(data, 1)
  assert_true(approx_eq(r.mean[0], 2.0))
  assert_true(approx_eq(r.explained_variance[0], 1.0))
  assert_true(vec_approx_eq(r.components[0], [1.0]))
  // transform of the mean is the origin; of 5.0 is (5-2)*1 = 3.
  assert_true(approx_eq(pca_transform(r, [5.0])[0], 3.0))
}

///|
test "pca: principal axis aligns with the spread (2-D)" {
  // Points on the x-axis only: variance is purely along x.
  let data = [[0.0, 0.0], [1.0, 0.0], [2.0, 0.0], [3.0, 0.0], [4.0, 0.0]]
  let r = pca(data, 2)
  // mean = (2, 0).
  assert_true(approx_eq(r.mean[0], 2.0))
  assert_true(approx_eq(r.mean[1], 0.0))
  // sample variance along x: (4+1+0+1+4)/4 = 2.5; along y: 0.
  assert_true(approx_eq(r.explained_variance[0], 2.5))
  assert_true(approx_eq(r.explained_variance[1], 0.0))
  // First PC points along x; second along y (both sign-pinned positive-first).
  assert_true(vec_approx_eq(r.components[0], [1.0, 0.0]))
  assert_true(vec_approx_eq(r.components[1], [0.0, 1.0]))
}

///|
test "pca: components are orthonormal" {
  // A generic 3-D dataset with variance in every direction.
  let data = [
    [1.0, 2.0, 0.0],
    [3.0, 4.0, 1.0],
    [5.0, 0.0, 2.0],
    [2.0, 6.0, 3.0],
    [4.0, 8.0, 4.0],
  ]
  let r = pca(data, 3)
  assert_eq(r.components.length(), 3)
  // Each component is unit length.
  for c = 0; c < 3; c = c + 1 {
    assert_true(approx_eq(pca_l2_norm(r.components[c]), 1.0))
  }
  // Pairwise orthogonal.
  for i = 0; i < 3; i = i + 1 {
    for j = i + 1; j < 3; j = j + 1 {
      assert_true(pca_dot(r.components[i], r.components[j]).abs() < 1.0e-9)
    }
  }
  // Eigenvalues are non-increasing.
  assert_true(r.explained_variance[0] >= r.explained_variance[1])
  assert_true(r.explained_variance[1] >= r.explained_variance[2])
}

///|
test "pca: total variance equals the covariance trace (full capture)" {
  // Diagonal-ish covariance: var_x = 4/3, var_y = 1/3, cov = 0.
  let data = [[0.0, 0.0], [2.0, 0.0], [0.0, 1.0], [2.0, 1.0]]
  let r = pca(data, 2)
  // mean = (1, 0.5).
  assert_true(approx_eq(r.mean[0], 1.0))
  assert_true(approx_eq(r.mean[1], 0.5))
  // Eigenvalues 4/3 and 1/3, summing to the trace 5/3.
  assert_true(approx_eq(r.explained_variance[0], 4.0 / 3.0))
  assert_true(approx_eq(r.explained_variance[1], 1.0 / 3.0))
  // Captured variance = total variance when all components are kept.
  let captured = sum_arr(r.explained_variance)
  assert_true(approx_eq(captured, 5.0 / 3.0))
  // Axes align with the coordinate axes (off-diagonal covariance is 0).
  assert_true(vec_approx_eq(r.components[0], [1.0, 0.0]))
  assert_true(vec_approx_eq(r.components[1], [0.0, 1.0]))
}

///|
test "pca: partial capture keeps only the largest variance" {
  let data = [[0.0, 0.0], [2.0, 0.0], [0.0, 1.0], [2.0, 1.0]]
  let r = pca(data, 1)
  assert_eq(r.components.length(), 1)
  // The single kept component captures var_x = 4/3 of the total 5/3.
  assert_true(approx_eq(r.explained_variance[0], 4.0 / 3.0))
  // Dropping to one component loses var_y = 1/3 of the variance.
  let total = 5.0 / 3.0
  let ratio = sum_arr(r.explained_variance) / total
  assert_true(approx_eq(ratio, 0.8))
  assert_true(vec_approx_eq(r.components[0], [1.0, 0.0]))
}

///|
test "pca: rotated line yields equal-variance diagonalisation" {
  // Points on y = x: the dominant axis is (1,1)/sqrt2 with eigenvalue 20,
  // the minor axis (1,-1)/sqrt2 with eigenvalue 0.
  let data = [[0.0, 0.0], [2.0, 2.0], [4.0, 4.0], [6.0, 6.0], [8.0, 8.0]]
  let r = pca(data, 2)
  let inv_sqrt2 = 1.0 / 2.0.sqrt()
  assert_true(approx_eq(r.explained_variance[0], 20.0))
  assert_true(approx_eq(r.explained_variance[1], 0.0))
  assert_true(vec_approx_eq(r.components[0], [inv_sqrt2, inv_sqrt2]))
  assert_true(vec_approx_eq(r.components[1], [inv_sqrt2, -inv_sqrt2]))
}

///|
test "pca: transform projects onto the principal axes" {
  // Reuse the diagonal-covariance dataset: mean (1, 0.5), axes = x and y.
  let data = [[0.0, 0.0], [2.0, 0.0], [0.0, 1.0], [2.0, 1.0]]
  let r = pca(data, 2)
  // The mean projects to the origin.
  let m0 = pca_transform(r, [1.0, 0.5])
  assert_true(approx_eq(m0[0], 0.0))
  assert_true(approx_eq(m0[1], 0.0))
  // (3, 0.5) - (1, 0.5) = (2, 0) -> projection (2, 0).
  let p = pca_transform(r, [3.0, 0.5])
  assert_true(approx_eq(p[0], 2.0))
  assert_true(approx_eq(p[1], 0.0))
  // (1, 2.5) - (1, 0.5) = (0, 2) -> projection (0, 2).
  let q = pca_transform(r, [1.0, 2.5])
  assert_true(approx_eq(q[0], 0.0))
  assert_true(approx_eq(q[1], 2.0))
}

///|
test "pca: dimension-mismatched sample returns empty projection" {
  let data = [[0.0, 0.0], [1.0, 1.0], [2.0, 2.0]]
  let r = pca(data, 1)
  // A 3-D sample cannot be projected by a 2-D model -> empty, no abort.
  assert_eq(pca_transform(r, [1.0, 2.0, 3.0]).length(), 0)
}

///|
test "pca: deterministic across repeated fits" {
  let data = [[1.0, 2.0], [3.0, 4.0], [5.0, 6.0], [7.0, 8.0]]
  let r1 = pca(data, 2)
  let r2 = pca(data, 2)
  for c = 0; c < 2; c = c + 1 {
    assert_true(vec_approx_eq(r1.components[c], r2.components[c]))
    assert_true(approx_eq(r1.explained_variance[c], r2.explained_variance[c]))
  }
}
