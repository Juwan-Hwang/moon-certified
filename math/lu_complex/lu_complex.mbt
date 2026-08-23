/// Complex LU Decomposition
///
/// LU decomposition for complex-valued matrices with partial pivoting.
/// Factors A = P·L·U where P is a permutation matrix, L is lower triangular,
/// and U is upper triangular.
///
/// `proof-enabled` is `false`.

///|
/// Complex number type.
pub struct Complex {
  re : Double
  im : Double
}

///|
/// Complex addition.
fn c_add(a : Complex, b : Complex) -> Complex {
  { re: a.re + b.re, im: a.im + b.im }
}

///|
/// Complex subtraction.
fn c_sub(a : Complex, b : Complex) -> Complex {
  { re: a.re - b.re, im: a.im - b.im }
}

///|
/// Complex multiplication.
fn c_mul(a : Complex, b : Complex) -> Complex {
  { re: a.re * b.re - a.im * b.im, im: a.re * b.im + a.im * b.re }
}

///|
/// Complex magnitude squared.
fn c_abs2(a : Complex) -> Double {
  a.re * a.re + a.im * a.im
}

///|
/// Complex magnitude.
fn c_abs(a : Complex) -> Double {
  c_abs2(a).sqrt()
}

///|
/// Complex reciprocal: 1/a.
fn c_inv(a : Complex) -> Complex {
  let d = c_abs2(a)
  if d == 0.0 {
    abort("c_inv: division by zero")
  }
  { re: a.re / d, im: -a.im / d }
}

///|
/// Complex division: a / b.
fn c_div(a : Complex, b : Complex) -> Complex {
  c_mul(a, c_inv(b))
}

///|
/// LU decomposition result.
pub struct ComplexLU {
  /// Lower triangular (unit diagonal)
  l : Array[Array[Complex]]
  /// Upper triangular
  u : Array[Array[Complex]]
  /// Permutation vector
  piv : Array[Int]
  /// Number of row swaps (sign of permutation)
  sign : Int
}

///|
/// Perform LU decomposition with partial pivoting on a complex matrix.
pub fn complex_lu_decompose(a : Array[Array[Complex]]) -> ComplexLU {
  let n = a.length()
  if n == 0 {
    return { l: [], u: [], piv: [], sign: 1 }
  }
  // Create working copies
  let lu : Array[Array[Complex]] = []
  for i = 0; i < n; i = i + 1 {
    let row : Array[Complex] = []
    for j = 0; j < n; j = j + 1 {
      row.push(a[i][j])
    }
    lu.push(row)
  }
  let piv = Array::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    piv[i] = i
  }
  let mut sign = 1
  for k = 0; k < n; k = k + 1 {
    // Find pivot: largest magnitude in column k, rows k..n-1
    let mut max_val = 0.0
    let mut max_idx = k
    for i = k; i < n; i = i + 1 {
      let val = c_abs(lu[i][k])
      if val > max_val {
        max_val = val
        max_idx = i
      }
    }
    // Swap rows if needed
    if max_idx != k {
      let tmp = lu[k]
      lu[k] = lu[max_idx]
      lu[max_idx] = tmp
      let tmp_piv = piv[k]
      piv[k] = piv[max_idx]
      piv[max_idx] = tmp_piv
      sign = -sign
    }
    // Check for singularity
    if c_abs2(lu[k][k]) == 0.0 {
      continue // Singular, leave zeros
    }
    // Eliminate below
    for i = k + 1; i < n; i = i + 1 {
      // lu[i][k] /= lu[k][k]
      lu[i][k] = c_div(lu[i][k], lu[k][k])
      // lu[i][j] -= lu[i][k] * lu[k][j]
      for j = k + 1; j < n; j = j + 1 {
        lu[i][j] = c_sub(lu[i][j], c_mul(lu[i][k], lu[k][j]))
      }
    }
  }
  // Extract L and U from LU
  let l : Array[Array[Complex]] = []
  let u : Array[Array[Complex]] = []
  for i = 0; i < n; i = i + 1 {
    let l_row : Array[Complex] = []
    let u_row : Array[Complex] = []
    for j = 0; j < n; j = j + 1 {
      if j < i {
        l_row.push(lu[i][j])
        u_row.push({ re: 0.0, im: 0.0 })
      } else if j == i {
        l_row.push({ re: 1.0, im: 0.0 })
        u_row.push(lu[i][j])
      } else {
        l_row.push({ re: 0.0, im: 0.0 })
        u_row.push(lu[i][j])
      }
    }
    l.push(l_row)
    u.push(u_row)
  }
  { l, u, piv, sign }
}

///|
/// Solve A·x = b using LU decomposition (forward + back substitution).
pub fn complex_lu_solve(lu : ComplexLU, b : Array[Complex]) -> Array[Complex] {
  let n = lu.piv.length()
  // Apply permutation
  let pb = Array::make(n, { re: 0.0, im: 0.0 })
  for i = 0; i < n; i = i + 1 {
    pb[i] = b[lu.piv[i]]
  }
  // Forward substitution: L·y = Pb
  let y = Array::make(n, { re: 0.0, im: 0.0 })
  for i = 0; i < n; i = i + 1 {
    let mut sum = pb[i]
    for j = 0; j < i; j = j + 1 {
      sum = c_sub(sum, c_mul(lu.l[i][j], y[j]))
    }
    y[i] = sum
  }
  // Back substitution: U·x = y
  let x = Array::make(n, { re: 0.0, im: 0.0 })
  for i = n - 1; i >= 0; i = i - 1 {
    let mut sum = y[i]
    for j = i + 1; j < n; j = j + 1 {
      sum = c_sub(sum, c_mul(lu.u[i][j], x[j]))
    }
    if c_abs2(lu.u[i][i]) > 0.0 {
      x[i] = c_div(sum, lu.u[i][i])
    }
  }
  x
}

///|
/// Compute the determinant from LU decomposition.
pub fn complex_lu_determinant(lu : ComplexLU) -> Complex {
  let n = lu.piv.length()
  let mut det = { re: lu.sign.to_double(), im: 0.0 }
  for i = 0; i < n; i = i + 1 {
    det = c_mul(det, lu.u[i][i])
  }
  det
}
