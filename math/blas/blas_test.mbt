///|
/// White-box tests for the BLAS package.

// ---------------------------------------------------------------------------
// Local helpers
// ---------------------------------------------------------------------------

fn approx(a : Double, b : Double, tol : Double) -> Bool {
  (a - b).abs() < tol
}

///|
fn arr_close(a : Array[Double], b : Array[Double], tol : Double) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i = 0; i < a.length(); i = i + 1 {
    if (a[i] - b[i]).abs() > tol {
      return false
    }
  }
  true
}

///|
fn mat_close(
  a : Array[Array[Double]],
  b : Array[Array[Double]],
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
      if (a[i][j] - b[i][j]).abs() > tol {
        return false
      }
    }
  }
  true
}

// ---------------------------------------------------------------------------
// Level 1
// ---------------------------------------------------------------------------

///|
test "ddot_known_values" {
  assert_true(approx(ddot([1.0, 2.0, 3.0], [4.0, 5.0, 6.0]), 32.0, 1.0e-12))
}

///|
test "ddot_length_mismatch_uses_min" {
  // n = min(3, 2) = 2 -> 1*4 + 2*5 = 14
  assert_true(approx(ddot([1.0, 2.0, 3.0], [4.0, 5.0]), 14.0, 1.0e-12))
}

///|
test "ddot_empty" {
  assert_true(approx(ddot([], [1.0, 2.0]), 0.0, 1.0e-12))
}

///|
test "dnrm2_euclidean" {
  assert_true(approx(dnrm2([3.0, 4.0]), 5.0, 1.0e-12))
  assert_true(approx(dnrm2([]), 0.0, 1.0e-12))
}

///|
test "dscal_scales_vector" {
  let r = dscal(2.0, [1.0, 2.0, 3.0])
  assert_true(arr_close(r, [2.0, 4.0, 6.0], 1.0e-12))
}

///|
test "daxpy_combines" {
  let r = daxpy(2.0, [1.0, 2.0], [10.0, 20.0])
  assert_true(arr_close(r, [12.0, 24.0], 1.0e-12))
}

///|
test "daxpy_length_mismatch" {
  let r = daxpy(2.0, [1.0, 2.0, 3.0], [10.0, 20.0])
  // n = 2 -> 2*1+10, 2*2+20
  assert_true(arr_close(r, [12.0, 24.0], 1.0e-12))
}

// ---------------------------------------------------------------------------
// Level 2
// ---------------------------------------------------------------------------

///|
test "dgemv_no_transpose" {
  let a = [[1.0, 2.0], [3.0, 4.0]]
  let x = [10.0, 20.0]
  let y = dgemv(false, 2, 2, 1.0, a, x, 0.0, [0.0, 0.0])
  assert_true(arr_close(y, [50.0, 110.0], 1.0e-12))
}

///|
test "dgemv_with_beta" {
  let a = [[1.0, 2.0], [3.0, 4.0]]
  let x = [10.0, 20.0]
  let y = dgemv(false, 2, 2, 1.0, a, x, 2.0, [1.0, 1.0])
  // A*x + 2*y_in = [50,110] + [2,2] = [52,112]
  assert_true(arr_close(y, [52.0, 112.0], 1.0e-12))
}

///|
test "dgemv_transpose" {
  let a = [[1.0, 2.0], [3.0, 4.0]]
  let x = [10.0, 20.0]
  // A^T = [[1,3],[2,4]] ; A^T x = [1*10+3*20, 2*10+4*20] = [70,100]
  let y = dgemv(true, 2, 2, 1.0, a, x, 0.0, [0.0, 0.0])
  assert_true(arr_close(y, [70.0, 100.0], 1.0e-12))
}

///|
test "dger_rank_one_update" {
  let a = [[0.0, 0.0], [0.0, 0.0]]
  let r = dger(2, 2, 1.0, [1.0, 2.0], [3.0, 4.0], a)
  assert_true(mat_close(r, [[3.0, 4.0], [6.0, 8.0]], 1.0e-12))
}

///|
test "dger_with_alpha" {
  let a = [[0.0, 0.0], [0.0, 0.0]]
  let r = dger(2, 2, 3.0, [1.0, 2.0], [1.0, 1.0], a)
  // 3 * x * y^T = 3 * [[1,1],[2,2]] = [[3,3],[6,6]]
  assert_true(mat_close(r, [[3.0, 3.0], [6.0, 6.0]], 1.0e-12))
}

// ---------------------------------------------------------------------------
// Level 3
// ---------------------------------------------------------------------------

///|
test "dgemm_basic" {
  let a = [[1.0, 2.0], [3.0, 4.0]]
  let b = [[5.0, 6.0], [7.0, 8.0]]
  let r = dgemm(2, 2, 2, 1.0, a, b, 0.0, [[0.0, 0.0], [0.0, 0.0]])
  assert_true(mat_close(r, [[19.0, 22.0], [43.0, 50.0]], 1.0e-12))
}

///|
test "dgemm_with_beta" {
  let a = [[1.0, 0.0], [0.0, 1.0]]
  let b = [[2.0, 0.0], [0.0, 2.0]]
  let c = [[1.0, 1.0], [1.0, 1.0]]
  let r = dgemm(2, 2, 2, 1.0, a, b, 1.0, c)
  // A*B + C = [[2,0],[0,2]] + [[1,1],[1,1]] = [[3,1],[1,3]]
  assert_true(mat_close(r, [[3.0, 1.0], [1.0, 3.0]], 1.0e-12))
}

///|
test "transpose" {
  let r = transpose([[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]])
  assert_true(mat_close(r, [[1.0, 4.0], [2.0, 5.0], [3.0, 6.0]], 1.0e-12))
}

///|
test "transpose_square" {
  let r = transpose([[1.0, 2.0], [3.0, 4.0]])
  assert_true(mat_close(r, [[1.0, 3.0], [2.0, 4.0]], 1.0e-12))
}

///|
test "identity_matrix" {
  let r = identity(3)
  assert_true(
    mat_close(r, [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]], 1.0e-12),
  )
}

// ---------------------------------------------------------------------------
// Triangular solves & norms
// ---------------------------------------------------------------------------

///|
test "dtrsv_lower_solves" {
  let l = [[2.0, 0.0, 0.0], [1.0, 3.0, 0.0], [0.0, 1.0, 4.0]]
  let b = [4.0, 5.0, 9.0]
  match dtrsv_lower(3, l, b) {
    Some(x) => assert_true(arr_close(x, [2.0, 1.0, 2.0], 1.0e-12))
    None => assert_true(false)
  }
}

///|
test "dtrsv_upper_solves" {
  let u = [[2.0, 1.0, 0.0], [0.0, 3.0, 1.0], [0.0, 0.0, 4.0]]
  let b = [5.0, 10.0, 8.0]
  match dtrsv_upper(3, u, b) {
    Some(x) =>
      // x[2]=2, x[1]=(10-2)/3=8/3, x[0]=(5-8/3)/2=7/6
      assert_true(arr_close(x, [7.0 / 6.0, 8.0 / 3.0, 2.0], 1.0e-12))
    None => assert_true(false)
  }
}

///|
test "dtrsv_singular_returns_none" {
  let l_singular = [[2.0, 0.0], [1.0, 0.0]]
  match dtrsv_lower(2, l_singular, [1.0, 1.0]) {
    Some(_) => assert_true(false)
    None => ()
  }
  let u_singular = [[0.0, 1.0], [0.0, 2.0]]
  match dtrsv_upper(2, u_singular, [1.0, 1.0]) {
    Some(_) => assert_true(false)
    None => ()
  }
}

///|
test "frobenius_norm" {
  assert_true(approx(frobenius_norm([[3.0, 4.0], [0.0, 0.0]]), 5.0, 1.0e-12))
}

///|
test "trace" {
  assert_true(approx(trace([[1.0, 2.0], [3.0, 4.0]]), 5.0, 1.0e-12))
  assert_true(
    approx(
      trace([[1.0, 2.0, 3.0], [4.0, 5.0, 6.0], [7.0, 8.0, 9.0]]),
      15.0,
      1.0e-12,
    ),
  )
}
