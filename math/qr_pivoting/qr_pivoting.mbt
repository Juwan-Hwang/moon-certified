/// QR decomposition with column pivoting.
///
/// Decomposes A (m×n) into A*P = Q*R where Q is orthogonal, R is upper
/// triangular, and P is a permutation matrix. Column pivoting improves
/// numerical stability and reveals rank deficiency.
///
/// ## Performance
/// - O(mn²) time
/// - O(mn) space
///
/// ## References
/// - Businger, P. and Golub, G.H. "Linear least squares solutions by
///   Householder transformations." Numerische Mathematik, 1965.
///
/// `proof-enabled` is `false`.

///|
/// QR decomposition with column pivoting using Householder reflections.
///
/// `m` = number of rows, `n` = number of columns
/// `a` = m×n matrix (row-major), modified in place to hold R
///
/// Returns `(R, pivots)` where R is upper triangular and pivots is the
/// permutation array (pivots[j] = original column index at position j).
pub fn qr_pivoting(m : Int, n : Int, a : Array[Double]) -> (Array[Double], Array[Int]) {
  let r = Array::make(m * n, 0.0)
  for i = 0; i < m * n; i = i + 1 {
    r[i] = a[i]
  }
  let pivots = Array::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    pivots[i] = i
  }
  let min_dim = if m < n { m } else { n }
  for k = 0; k < min_dim; k = k + 1 {
    // Find column with largest norm in rows k..m-1
    let mut max_norm = -1.0
    let mut max_col = k
    for j = k; j < n; j = j + 1 {
      let mut norm = 0.0
      for i = k; i < m; i = i + 1 {
        norm = norm + r[i * n + j] * r[i * n + j]
      }
      if norm > max_norm {
        max_norm = norm
        max_col = j
      }
    }
    // Swap columns k and max_col
    if max_col != k {
      for i = 0; i < m; i = i + 1 {
        let tmp = r[i * n + k]
        r[i * n + k] = r[i * n + max_col]
        r[i * n + max_col] = tmp
      }
      let tmp = pivots[k]
      pivots[k] = pivots[max_col]
      pivots[max_col] = tmp
    }
    // Householder reflection for column k, rows k..m-1
    let mut norm = 0.0
    for i = k; i < m; i = i + 1 {
      norm = norm + r[i * n + k] * r[i * n + k]
    }
    norm = norm.sqrt()
    if norm < 1.0e-15 {
      continue
    }
    let alpha = if r[k * n + k] >= 0.0 { -norm } else { norm }
    // v = x - alpha*e1
    let v = Array::make(m - k, 0.0)
    v[0] = r[k * n + k] - alpha
    for i = 1; i < m - k; i = i + 1 {
      v[i] = r[(k + i) * n + k]
    }
    let mut vnorm = 0.0
    for i = 0; i < m - k; i = i + 1 {
      vnorm = vnorm + v[i] * v[i]
    }
    if vnorm < 1.0e-30 {
      continue
    }
    // Apply H = I - 2*v*v^T/(v^T*v) to columns k..n-1
    for j = k; j < n; j = j + 1 {
      let mut dot = 0.0
      for i = 0; i < m - k; i = i + 1 {
        dot = dot + v[i] * r[(k + i) * n + j]
      }
      let factor = 2.0 * dot / vnorm
      for i = 0; i < m - k; i = i + 1 {
        r[(k + i) * n + j] = r[(k + i) * n + j] - factor * v[i]
      }
    }
  }
  (r, pivots)
}

///|
/// Compute matrix rank from QR with pivoting.
pub fn matrix_rank(m : Int, n : Int, r : Array[Double], tol : Double) -> Int {
  let min_dim = if m < n { m } else { n }
  let mut rank = 0
  for k = 0; k < min_dim; k = k + 1 {
    if r[k * n + k].abs() > tol {
      rank = rank + 1
    }
  }
  rank
}

test "qr_pivoting: 3x2 matrix" {
  let a = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]
  let (r, _) = qr_pivoting(3, 2, a)
  // R should be upper triangular (2x2 effective)
  assert_true(r[0 * 2 + 0].abs() > r[1 * 2 + 0].abs())
  assert_true((r[1 * 2 + 0]).abs() < 1.0e-10)
}

test "qr_pivoting: identity" {
  let a = [1.0, 0.0, 0.0, 1.0]
  let (r, _) = qr_pivoting(2, 2, a)
  assert_true((r[0] - 1.0).abs() < 1.0e-10 || (r[0] + 1.0).abs() < 1.0e-10)
  assert_true((r[3] - 1.0).abs() < 1.0e-10 || (r[3] + 1.0).abs() < 1.0e-10)
}

test "qr_pivoting: rank deficient" {
  // Column 2 = 2 * Column 1
  let a = [1.0, 2.0, 3.0, 6.0]
  let (r, _) = qr_pivoting(2, 2, a)
  let rank = matrix_rank(2, 2, r, 1.0e-10)
  assert_eq(rank, 1)
}

test "qr_pivoting: full rank" {
  let a = [1.0, 0.0, 0.0, 1.0]
  let (r, _) = qr_pivoting(2, 2, a)
  let rank = matrix_rank(2, 2, r, 1.0e-10)
  assert_eq(rank, 2)
}

test "qr_pivoting: column pivot" {
  // Second column has larger norm, should be pivoted to first
  let a = [1.0, 10.0, 1.0, 10.0]
  let (_, pivots) = qr_pivoting(2, 2, a)
  // pivots[0] should be 1 (the larger-norm column)
  assert_eq(pivots[0], 1)
  assert_eq(pivots[1], 0)
}
