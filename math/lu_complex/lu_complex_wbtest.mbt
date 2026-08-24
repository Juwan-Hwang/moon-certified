///|
/// White-box tests for the complex LU decomposition package.
/// (White-box => `_wbtest.mbt` suffix so `pub` structs can be constructed.)

// ---------------------------------------------------------------------------
// Local helpers
// ---------------------------------------------------------------------------

fn c_approx(a : Complex, b : Complex, tol : Double) -> Bool {
  (a.re - b.re).abs() < tol && (a.im - b.im).abs() < tol
}

///|
fn c_arr_approx(a : Array[Complex], b : Array[Complex], tol : Double) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i = 0; i < a.length(); i = i + 1 {
    if !c_approx(a[i], b[i], tol) {
      return false
    }
  }
  true
}

///|
fn cmul(a : Complex, b : Complex) -> Complex {
  { re: a.re * b.re - a.im * b.im, im: a.re * b.im + a.im * b.re }
}

///|
fn cadd(a : Complex, b : Complex) -> Complex {
  { re: a.re + b.re, im: a.im + b.im }
}

///|
/// Reconstruct A from P^T L U using the pivot vector.
fn reconstruct(
  _a : Array[Array[Complex]],
  lu : ComplexLU,
) -> Array[Array[Complex]] {
  let n = lu.piv.length()
  let m : Array[Array[Complex]] = []
  for i = 0; i < n; i = i + 1 {
    let row : Array[Complex] = []
    for j = 0; j < n; j = j + 1 {
      let mut s : Complex = { re: 0.0, im: 0.0 }
      for k = 0; k < n; k = k + 1 {
        s = cadd(s, cmul(lu.l[i][k], lu.u[k][j]))
      }
      row.push(s)
    }
    m.push(row)
  }
  let piv_inv = Array::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    piv_inv[lu.piv[i]] = i
  }
  let r : Array[Array[Complex]] = []
  for rr = 0; rr < n; rr = rr + 1 {
    r.push(m[piv_inv[rr]])
  }
  r
}

///|
fn mat_c_approx(
  a : Array[Array[Complex]],
  b : Array[Array[Complex]],
  tol : Double,
) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i = 0; i < a.length(); i = i + 1 {
    if a[i].length() != b[i].length() {
      return false
    }
    for j = 0; j < a[i].length(); j = j + 1 {
      if !c_approx(a[i][j], b[i][j], tol) {
        return false
      }
    }
  }
  true
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "complex_lu_decompose_empty" {
  let lu = complex_lu_decompose([])
  assert_eq(lu.l.length(), 0)
  assert_eq(lu.u.length(), 0)
  assert_eq(lu.piv.length(), 0)
  assert_eq(lu.sign, 1)
}

///|
test "complex_lu_no_pivoting_reconstruct" {
  let a : Array[Array[Complex]] = [
    [{ re: 1.0, im: 0.0 }, { re: 1.0, im: 0.0 }],
    [{ re: 1.0, im: 0.0 }, { re: -1.0, im: 0.0 }],
  ]
  let lu = complex_lu_decompose(a)
  let det = complex_lu_determinant(lu)
  let expected_det : Complex = { re: -2.0, im: 0.0 }
  assert_true(c_approx(det, expected_det, 1.0e-12))
  // A = P^T L U (piv is identity here)
  assert_true(mat_c_approx(reconstruct(a, lu), a, 1.0e-12))
}

///|
test "complex_lu_with_pivoting_reconstruct" {
  let a : Array[Array[Complex]] = [
    [{ re: 0.0, im: 0.0 }, { re: 1.0, im: 0.0 }],
    [{ re: 1.0, im: 0.0 }, { re: 1.0, im: 0.0 }],
  ]
  let lu = complex_lu_decompose(a)
  let det = complex_lu_determinant(lu)
  let expected_det : Complex = { re: -1.0, im: 0.0 }
  assert_true(c_approx(det, expected_det, 1.0e-12))
  let rec = reconstruct(a, lu)
  assert_true(mat_c_approx(rec, a, 1.0e-12))
}

///|
test "complex_lu_solve_known_rhs" {
  let a : Array[Array[Complex]] = [
    [{ re: 1.0, im: 0.0 }, { re: 1.0, im: 0.0 }],
    [{ re: 1.0, im: 0.0 }, { re: -1.0, im: 0.0 }],
  ]
  let lu = complex_lu_decompose(a)
  let b : Array[Complex] = [{ re: 5.0, im: 0.0 }, { re: -1.0, im: 0.0 }]
  let x = complex_lu_solve(lu, b)
  let expected : Array[Complex] = [{ re: 2.0, im: 0.0 }, { re: 3.0, im: 0.0 }]
  assert_true(c_arr_approx(x, expected, 1.0e-12))
}

///|
test "complex_lu_solve_with_pivoting" {
  let a : Array[Array[Complex]] = [
    [{ re: 0.0, im: 0.0 }, { re: 1.0, im: 0.0 }],
    [{ re: 1.0, im: 0.0 }, { re: 1.0, im: 0.0 }],
  ]
  let lu = complex_lu_decompose(a)
  let b : Array[Complex] = [{ re: 4.0, im: 0.0 }, { re: 7.0, im: 0.0 }]
  let x = complex_lu_solve(lu, b)
  let expected : Array[Complex] = [{ re: 3.0, im: 0.0 }, { re: 4.0, im: 0.0 }]
  assert_true(c_arr_approx(x, expected, 1.0e-12))
}

///|
test "complex_lu_solve_complex_rhs" {
  let a : Array[Array[Complex]] = [
    [{ re: 0.0, im: 1.0 }, { re: 0.0, im: 0.0 }],
    [{ re: 0.0, im: 0.0 }, { re: 0.0, im: 1.0 }],
  ]
  let lu = complex_lu_decompose(a)
  let det = complex_lu_determinant(lu)
  let expected_det : Complex = { re: -1.0, im: 0.0 }
  assert_true(c_approx(det, expected_det, 1.0e-12))
  let b : Array[Complex] = [{ re: 0.0, im: 1.0 }, { re: 0.0, im: 1.0 }]
  let x = complex_lu_solve(lu, b)
  let expected : Array[Complex] = [{ re: 1.0, im: 0.0 }, { re: 1.0, im: 0.0 }]
  assert_true(c_arr_approx(x, expected, 1.0e-12))
}
