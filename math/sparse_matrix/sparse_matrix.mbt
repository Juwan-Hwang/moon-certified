/// Sparse Matrix — CSR (Compressed Sparse Row) format with CG solver.
///
/// This package provides a sparse matrix implementation using the Compressed
/// Sparse Row (CSR) format, which is the standard representation for
/// general sparse matrices in scientific computing.
///
/// ## Features
/// - Matrix-vector multiplication in O(nnz) time
/// - Conjugate Gradient (CG) iterative solver for symmetric positive-definite systems
/// - Matrix construction from triplets (row, col, value)
///
/// ## Complexity
/// - Construction: O(nnz log nnz) for sorting
/// - SpMV: O(nnz)
/// - CG: O(k * nnz) for k iterations
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

///|
/// A sparse matrix in CSR (Compressed Sparse Row) format.
pub struct SparseMatrix {
  priv rows : Int
  priv cols : Int
  priv row_ptr : FixedArray[Int] // length = rows + 1
  priv col_idx : FixedArray[Int] // length = nnz
  priv values : FixedArray[Double] // length = nnz
}

///|
/// Create a sparse matrix from a list of (row, col, value) triplets.
///
/// Duplicate entries for the same (row, col) are summed.
pub fn from_triplets(
  rows : Int,
  cols : Int,
  triplets : Array[(Int, Int, Double)],
) -> SparseMatrix {
  // Sort triplets by (row, col).
  let sorted = Array::copy(triplets)
  sorted.sort_by(fn(a, b) { if a.0 != b.0 { a.0 - b.0 } else { a.1 - b.1 } })
  // Merge duplicates and build CSR arrays.
  let row_ptr = FixedArray::make(rows + 1, 0)
  let col_idx : Array[Int] = []
  let values : Array[Double] = []
  let mut i = 0
  while i < sorted.length() {
    let (r, c, v) = sorted[i]
    // Sum duplicates.
    let mut sum = v
    let mut j = i + 1
    while j < sorted.length() && sorted[j].0 == r && sorted[j].1 == c {
      sum = sum + sorted[j].2
      j = j + 1
    }
    col_idx.push(c)
    values.push(sum)
    row_ptr[r + 1] = row_ptr[r + 1] + 1
    i = j
  }
  // Prefix sum row_ptr.
  for r = 1; r <= rows; r = r + 1 {
    row_ptr[r] = row_ptr[r] + row_ptr[r - 1]
  }
  {
    rows,
    cols,
    row_ptr,
    col_idx: FixedArray::from_array(col_idx.view()),
    values: FixedArray::from_array(values.view()),
  }
}

///|
/// Number of rows.
pub fn num_rows(m : SparseMatrix) -> Int {
  m.rows
}

///|
/// Number of columns.
pub fn num_cols(m : SparseMatrix) -> Int {
  m.cols
}

///|
/// Number of non-zero entries.
pub fn nnz(m : SparseMatrix) -> Int {
  m.values.length()
}

///|
/// Sparse matrix-vector multiplication: y = A * x.
///
/// `x` must have length `cols`. Returns `y` of length `rows`.
pub fn spmv(m : SparseMatrix, x : Array[Double]) -> Array[Double] {
  let y = Array::make(m.rows, 0.0)
  for r = 0; r < m.rows; r = r + 1 {
    let mut sum = 0.0
    for idx = m.row_ptr[r]; idx < m.row_ptr[r + 1]; idx = idx + 1 {
      sum = sum + m.values[idx] * x[m.col_idx[idx]]
    }
    y[r] = sum
  }
  y
}

///|
/// Get a matrix element. Returns 0.0 for non-stored entries.
pub fn get(m : SparseMatrix, row : Int, col : Int) -> Double {
  if row < 0 || row >= m.rows || col < 0 || col >= m.cols {
    return 0.0
  }
  for idx = m.row_ptr[row]; idx < m.row_ptr[row + 1]; idx = idx + 1 {
    if m.col_idx[idx] == col {
      return m.values[idx]
    }
  }
  0.0
}

///|
/// Conjugate Gradient solver for Ax = b.
///
/// Solves the system Ax = b where A is symmetric positive-definite.
///
/// - `a`: sparse matrix (must be symmetric positive-definite).
/// - `b`: right-hand side vector.
/// - `max_iter`: maximum iterations.
/// - `tol`: convergence tolerance (relative residual norm).
/// - Returns: solution vector `x`.
pub fn conjugate_gradient(
  a : SparseMatrix,
  b : Array[Double],
  max_iter : Int,
  tol : Double,
) -> Array[Double] {
  let n = b.length()
  let x = Array::make(n, 0.0)
  let r = Array::copy(b)
  let p = Array::copy(r)
  let mut rs_old = dot(r, r)
  if rs_old < tol * tol {
    return x
  }
  let mut iter = 0
  while iter < max_iter {
    let ap = spmv(a, p)
    let pap = dot(p, ap)
    if pap.abs() < 1.0e-30 {
      return x
    }
    let alpha = rs_old / pap
    for i = 0; i < n; i = i + 1 {
      x[i] = x[i] + alpha * p[i]
      r[i] = r[i] - alpha * ap[i]
    }
    let rs_new = dot(r, r)
    if rs_new < tol * tol {
      return x
    }
    let beta = rs_new / rs_old
    for i = 0; i < n; i = i + 1 {
      p[i] = r[i] + beta * p[i]
    }
    rs_old = rs_new
    iter = iter + 1
  }
  x
}

///|
/// Dot product of two vectors.
fn dot(a : Array[Double], b : Array[Double]) -> Double {
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  let mut s = 0.0
  for i = 0; i < n; i = i + 1 {
    s = s + a[i] * b[i]
  }
  s
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "sparse_matrix: construction and access" {
  let m = from_triplets(3, 3, [(0, 0, 1.0), (1, 1, 2.0), (2, 2, 3.0)])
  assert_eq(num_rows(m), 3)
  assert_eq(num_cols(m), 3)
  assert_eq(nnz(m), 3)
  assert_true((get(m, 0, 0) - 1.0).abs() < 1.0e-10)
  assert_true((get(m, 1, 1) - 2.0).abs() < 1.0e-10)
  assert_true((get(m, 2, 2) - 3.0).abs() < 1.0e-10)
  assert_true((get(m, 0, 1) - 0.0).abs() < 1.0e-10)
}

///|
test "sparse_matrix: spmv" {
  // Diagonal matrix [1, 2, 3] * x = [1, 4, 9]
  let m = from_triplets(3, 3, [(0, 0, 1.0), (1, 1, 2.0), (2, 2, 3.0)])
  let x = [1.0, 2.0, 3.0]
  let y = spmv(m, x)
  assert_true((y[0] - 1.0).abs() < 1.0e-10)
  assert_true((y[1] - 4.0).abs() < 1.0e-10)
  assert_true((y[2] - 9.0).abs() < 1.0e-10)
}

///|
test "sparse_matrix: duplicate entries summed" {
  let m = from_triplets(2, 2, [(0, 0, 1.0), (0, 0, 2.0), (1, 1, 3.0)])
  assert_eq(nnz(m), 2)
  assert_true((get(m, 0, 0) - 3.0).abs() < 1.0e-10)
  assert_true((get(m, 1, 1) - 3.0).abs() < 1.0e-10)
}

///|
test "sparse_matrix: dense matrix spmv" {
  // 2x2 dense: [[1, 2], [3, 4]]
  let m = from_triplets(2, 2, [
    (0, 0, 1.0),
    (0, 1, 2.0),
    (1, 0, 3.0),
    (1, 1, 4.0),
  ])
  let x = [5.0, 6.0]
  let y = spmv(m, x)
  assert_true((y[0] - 17.0).abs() < 1.0e-10) // 1*5 + 2*6 = 17
  assert_true((y[1] - 39.0).abs() < 1.0e-10) // 3*5 + 4*6 = 39
}

///|
test "sparse_matrix: conjugate gradient" {
  // Solve [[4, 1], [1, 3]] * x = [1, 2]
  // Solution: x = [1/11, 7/11]
  let a = from_triplets(2, 2, [
    (0, 0, 4.0),
    (0, 1, 1.0),
    (1, 0, 1.0),
    (1, 1, 3.0),
  ])
  let b = [1.0, 2.0]
  let x = conjugate_gradient(a, b, 100, 1.0e-10)
  let expected = [1.0 / 11.0, 7.0 / 11.0]
  assert_true((x[0] - expected[0]).abs() < 1.0e-8)
  assert_true((x[1] - expected[1]).abs() < 1.0e-8)
}
