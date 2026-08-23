/// Eigenvalue decomposition using the Jacobi rotation method for
/// symmetric matrices.
///
/// For symmetric matrices, the Jacobi method iteratively applies plane
/// rotations to zero out off-diagonal elements, converging to a diagonal
/// matrix of eigenvalues with the accumulated rotations forming the
/// eigenvector matrix.
///
/// ## Performance
/// - O(n³) per sweep, typically 5-10 sweeps needed
/// - All eigenvalues and eigenvectors computed simultaneously
///
/// ## References
/// - Jacobi, C.G.J. "Über ein leichtes Verfahren..."
///   Journal für die reine und angewandte Mathematik, 1846.
/// - Golub, G.H. and Van Loan, C.F. "Matrix Computations," 4th ed.
///
/// `proof-enabled` is `false`.

///|
/// Compute eigenvalues and eigenvectors of a symmetric matrix.
///
/// `n` = matrix dimension
/// `a` = symmetric matrix stored as flat array (row-major), n×n
///
/// Returns `(eigenvalues, eigenvectors)` where:
/// - `eigenvalues[i]` is the i-th eigenvalue
/// - `eigenvectors[i*n + j]` is the j-th component of the i-th eigenvector
///
/// For non-symmetric input, behavior is undefined (may not converge).
pub fn symmetric_eig(
  n : Int,
  a : Array[Double],
) -> (Array[Double], Array[Double]) {
  if n <= 0 {
    return ([], [])
  }
  if n == 1 {
    return ([a[0]], [1.0])
  }
  // Work on copies
  let w = Array::make(n * n, 0.0) // working matrix
  let v = Array::make(n * n, 0.0) // eigenvector matrix
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      w[i * n + j] = a[i * n + j]
    }
    v[i * n + i] = 1.0
  }
  let max_sweeps = 100
  let eps = 1.0e-15
  for iter = 0; iter < max_sweeps; iter = iter + 1 {
    let mut off = 0.0
    for i = 0; i < n - 1; i = i + 1 {
      for j = i + 1; j < n; j = j + 1 {
        off = off + w[i * n + j] * w[i * n + j]
      }
    }
    if off < eps {
      break
    }
    // Cyclic sweep through all off-diagonal pairs
    for p = 0; p < n - 1; p = p + 1 {
      for q = p + 1; q < n; q = q + 1 {
        let apq = w[p * n + q]
        if apq.abs() < eps {
          continue
        }
        let app = w[p * n + p]
        let aqq = w[q * n + q]
        // Compute rotation using tan(2*theta) = 2*apq/(app-aqq)
        let tau = (aqq - app) / (2.0 * apq)
        let t = if tau.abs() < 1.0e10 {
          // t = sign(tau)/(|tau| + sqrt(tau^2+1))
          let sign = if tau >= 0.0 { 1.0 } else { -1.0 }
          sign / (tau.abs() + (1.0 + tau * tau).sqrt())
        } else {
          1.0 / (2.0 * tau)
        }
        let c = 1.0 / (1.0 + t * t).sqrt()
        let s = t * c
        // Apply rotation
        for i = 0; i < n; i = i + 1 {
          if i != p && i != q {
            let aip = w[i * n + p]
            let aiq = w[i * n + q]
            w[i * n + p] = c * aip - s * aiq
            w[p * n + i] = w[i * n + p]
            w[i * n + q] = s * aip + c * aiq
            w[q * n + i] = w[i * n + q]
          }
        }
        w[p * n + p] = app - t * apq
        w[q * n + q] = aqq + t * apq
        w[p * n + q] = 0.0
        w[q * n + p] = 0.0
        // Accumulate eigenvectors
        for i = 0; i < n; i = i + 1 {
          let vip = v[i * n + p]
          let viq = v[i * n + q]
          v[i * n + p] = c * vip - s * viq
          v[i * n + q] = s * vip + c * viq
        }
      }
    }
  }
  // Extract eigenvalues
  let eigenvalues = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    eigenvalues[i] = w[i * n + i]
  }
  (eigenvalues, v)
}

///|
/// Compute eigenvalues only (without eigenvectors) of a symmetric matrix.
pub fn symmetric_eigenvalues(n : Int, a : Array[Double]) -> Array[Double] {
  let (vals, _) = symmetric_eig(n, a)
  vals
}

///|
test "eigenvalue: 2x2 diagonal" {
  let a = [3.0, 0.0, 0.0, 7.0]
  let (vals, _) = symmetric_eig(2, a)
  // Eigenvalues should be 3 and 7 (in some order)
  let mut min_v = vals[0]
  let mut max_v = vals[0]
  for i = 1; i < 2; i = i + 1 {
    if vals[i] < min_v {
      min_v = vals[i]
    }
    if vals[i] > max_v {
      max_v = vals[i]
    }
  }
  assert_true((min_v - 3.0).abs() < 1.0e-10)
  assert_true((max_v - 7.0).abs() < 1.0e-10)
}

///|
test "eigenvalue: 2x2 symmetric" {
  let a = [2.0, 1.0, 1.0, 2.0]
  let vals = symmetric_eigenvalues(2, a)
  // Eigenvalues of [[2,1],[1,2]] are 1 and 3
  let mut min_v = vals[0]
  let mut max_v = vals[0]
  for i = 1; i < 2; i = i + 1 {
    if vals[i] < min_v {
      min_v = vals[i]
    }
    if vals[i] > max_v {
      max_v = vals[i]
    }
  }
  assert_true((min_v - 1.0).abs() < 1.0e-10)
  assert_true((max_v - 3.0).abs() < 1.0e-10)
}

///|
test "eigenvalue: 3x3 identity" {
  let a = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]
  let vals = symmetric_eigenvalues(3, a)
  for i = 0; i < 3; i = i + 1 {
    assert_true((vals[i] - 1.0).abs() < 1.0e-10)
  }
}

///|
test "eigenvalue: 3x3 symmetric" {
  let a = [4.0, 1.0, 1.0, 1.0, 4.0, 1.0, 1.0, 1.0, 4.0]
  let vals = symmetric_eigenvalues(3, a)
  // Eigenvalues of [[4,1,1],[1,4,1],[1,1,4]] are 3, 3, 6
  // Check sum = trace = 12
  let mut sum = 0.0
  for i = 0; i < 3; i = i + 1 {
    sum = sum + vals[i]
  }
  assert_true((sum - 12.0).abs() < 1.0e-10)
  // Check that at least one eigenvalue is close to 6
  let mut found_6 = false
  for i = 0; i < 3; i = i + 1 {
    if (vals[i] - 6.0).abs() < 0.01 {
      found_6 = true
    }
  }
  assert_true(found_6)
  // Check that all eigenvalues are positive
  for i = 0; i < 3; i = i + 1 {
    assert_true(vals[i] > 0.0)
  }
}

///|
test "eigenvalue: 1x1" {
  let a = [42.0]
  let vals = symmetric_eigenvalues(1, a)
  assert_true((vals[0] - 42.0).abs() < 1.0e-10)
}

///|
test "eigenvalue: eigenvectors orthonormal" {
  let a = [2.0, 1.0, 1.0, 2.0]
  let (vals, vecs) = symmetric_eig(2, a)
  // Columns of V are eigenvectors. Column j = [vecs[j], vecs[n+j]]
  // Eigenvector 0: [vecs[0], vecs[2]]
  let v0_norm = vecs[0] * vecs[0] + vecs[2] * vecs[2]
  assert_true((v0_norm - 1.0).abs() < 1.0e-10)
  // Eigenvector 1: [vecs[1], vecs[3]]
  let v1_norm = vecs[1] * vecs[1] + vecs[3] * vecs[3]
  assert_true((v1_norm - 1.0).abs() < 1.0e-10)
  // Orthogonal: v0 . v1 = 0
  let dot = vecs[0] * vecs[1] + vecs[2] * vecs[3]
  assert_true(dot.abs() < 1.0e-10)
  // Verify Av = λv for first eigenvector (column 0)
  let lambda = vals[0]
  let av0_0 = a[0] * vecs[0] + a[1] * vecs[2]
  let av0_1 = a[2] * vecs[0] + a[3] * vecs[2]
  assert_true((av0_0 - lambda * vecs[0]).abs() < 1.0e-10)
  assert_true((av0_1 - lambda * vecs[2]).abs() < 1.0e-10)
}
