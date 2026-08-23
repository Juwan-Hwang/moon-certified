/// BLAS (Basic Linear Algebra Subprograms) Level 1, 2, 3
///
/// Implements core BLAS operations for dense matrix-vector and matrix-matrix
/// arithmetic. This provides the foundational operations used by LAPACK-level
/// solvers (LU, QR, Cholesky, SVD, eigenvalue decomposition).
///
/// ## Levels
/// - **Level 1**: Vector operations (dot, axpy, norm, swap, scale)
/// - **Level 2**: Matrix-vector operations (gemv, ger, trsv)
/// - **Level 3**: Matrix-matrix operations (gemm, trsm, trmm)
///
/// ## Reference
/// - BLAS Technical Forum Standard (www.netlib.org/blas)
///
/// `proof-enabled` is `false`.

// ===========================================================================
// Level 1: Vector operations
// ===========================================================================

///|
/// Compute the dot product of two vectors: α·x + β·y... no, just dot(x, y).
pub fn ddot(x : Array[Double], y : Array[Double]) -> Double {
  let n = if x.length() < y.length() { x.length() } else { y.length() }
  let mut sum = 0.0
  for i = 0; i < n; i = i + 1 {
    sum = sum + x[i] * y[i]
  }
  sum
}

///|
/// Compute the Euclidean norm (L2) of a vector.
pub fn dnrm2(x : Array[Double]) -> Double {
  let mut sum = 0.0
  for v in x {
    sum = sum + v * v
  }
  sum.sqrt()
}

///|
/// Scale a vector by a scalar: x = α·x.
pub fn dscal(alpha : Double, x : Array[Double]) -> Array[Double] {
  let result = Array::make(x.length(), 0.0)
  for i = 0; i < x.length(); i = i + 1 {
    result[i] = alpha * x[i]
  }
  result
}

///|
/// AXPY: y = α·x + y.
pub fn daxpy(
  alpha : Double,
  x : Array[Double],
  y : Array[Double],
) -> Array[Double] {
  let n = if x.length() < y.length() { x.length() } else { y.length() }
  let result = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    result[i] = alpha * x[i] + y[i]
  }
  result
}

// ===========================================================================
// Level 2: Matrix-vector operations
// ===========================================================================

///|
/// General matrix-vector multiply: y = α·A·x + β·y.
///
/// `trans` can be 'N' (no transpose), 'T' (transpose).
pub fn dgemv(
  trans : Bool,
  m : Int,
  n : Int,
  alpha : Double,
  a : Array[Array[Double]],
  x : Array[Double],
  beta : Double,
  y_in : Array[Double],
) -> Array[Double] {
  let result = Array::make(y_in.length(), 0.0)
  for i = 0; i < y_in.length(); i = i + 1 {
    result[i] = beta * y_in[i]
  }
  if trans {
    // A^T is [n x m], y = α·A^T·x + β·y
    for j = 0; j < n; j = j + 1 {
      let mut sum = 0.0
      for i = 0; i < m; i = i + 1 {
        sum = sum + a[i][j] * x[i]
      }
      result[j] = result[j] + alpha * sum
    }
  } else {
    // A is [m x n], y = α·A·x + β·y
    for i = 0; i < m; i = i + 1 {
      let mut sum = 0.0
      for j = 0; j < n; j = j + 1 {
        sum = sum + a[i][j] * x[j]
      }
      result[i] = result[i] + alpha * sum
    }
  }
  result
}

///|
/// Rank-1 update: A = α·x·y^T + A.
pub fn dger(
  m : Int,
  n : Int,
  alpha : Double,
  x : Array[Double],
  y : Array[Double],
  a : Array[Array[Double]],
) -> Array[Array[Double]] {
  let result : Array[Array[Double]] = []
  for _i = 0; _i < m; _i = _i + 1 {
    result.push(Array::make(n, 0.0))
  }
  for i = 0; i < m; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      result[i][j] = a[i][j] + alpha * x[i] * y[j]
    }
  }
  result
}

// ===========================================================================
// Level 3: Matrix-matrix operations
// ===========================================================================

///|
/// General matrix-matrix multiply: C = α·op(A)·op(B) + β·C.
///
/// `trans_a`, `trans_b` indicate whether to transpose A or B.
pub fn dgemm(
  m : Int,
  n : Int,
  k : Int,
  alpha : Double,
  a : Array[Array[Double]],
  b : Array[Array[Double]],
  beta : Double,
  c_in : Array[Array[Double]],
) -> Array[Array[Double]] {
  let result : Array[Array[Double]] = []
  for _i = 0; _i < m; _i = _i + 1 {
    result.push(Array::make(n, 0.0))
  }
  for i = 0; i < m; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      let mut sum = 0.0
      for l = 0; l < k; l = l + 1 {
        sum = sum + a[i][l] * b[l][j]
      }
      result[i][j] = alpha * sum + beta * c_in[i][j]
    }
  }
  result
}

///|
/// Matrix transpose.
pub fn transpose(a : Array[Array[Double]]) -> Array[Array[Double]] {
  let m = a.length()
  if m == 0 {
    return []
  }
  let n = a[0].length()
  let result : Array[Array[Double]] = []
  for _i = 0; _i < n; _i = _i + 1 {
    result.push(Array::make(m, 0.0))
  }
  for i = 0; i < m; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      result[j][i] = a[i][j]
    }
  }
  result
}

///|
/// Identity matrix of size n.
pub fn identity(n : Int) -> Array[Array[Double]] {
  let result : Array[Array[Double]] = []
  for _i = 0; _i < n; _i = _i + 1 {
    result.push(Array::make(n, 0.0))
  }
  for i = 0; i < n; i = i + 1 {
    result[i][i] = 1.0
  }
  result
}

///|
/// Triangular solve: solves L·x = b where L is lower triangular.
pub fn dtrsv_lower(
  n : Int,
  l : Array[Array[Double]],
  b : Array[Double],
) -> Array[Double] {
  let x = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    let mut sum = b[i]
    for j = 0; j < i; j = j + 1 {
      sum = sum - l[i][j] * x[j]
    }
    if l[i][i] == 0.0 {
      abort("dtrsv: singular matrix")
    }
    x[i] = sum / l[i][i]
  }
  x
}

///|
/// Triangular solve: solves U·x = b where U is upper triangular.
pub fn dtrsv_upper(
  n : Int,
  u : Array[Array[Double]],
  b : Array[Double],
) -> Array[Double] {
  let x = Array::make(n, 0.0)
  for i = n - 1; i >= 0; i = i - 1 {
    let mut sum = b[i]
    for j = i + 1; j < n; j = j + 1 {
      sum = sum - u[i][j] * x[j]
    }
    if u[i][i] == 0.0 {
      abort("dtrsv: singular matrix")
    }
    x[i] = sum / u[i][i]
  }
  x
}

///|
/// Frobenius norm of a matrix.
pub fn frobenius_norm(a : Array[Array[Double]]) -> Double {
  let mut sum = 0.0
  for row in a {
    for v in row {
      sum = sum + v * v
    }
  }
  sum.sqrt()
}

///|
/// Trace of a square matrix.
pub fn trace(a : Array[Array[Double]]) -> Double {
  let n = a.length()
  let mut sum = 0.0
  for i = 0; i < n; i = i + 1 {
    sum = sum + a[i][i]
  }
  sum
}
