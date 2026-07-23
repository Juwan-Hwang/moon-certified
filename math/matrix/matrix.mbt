/// Matrix operations on flat row-major arrays.
///
/// A matrix with `n` rows and `m` columns is stored in a `FixedArray` of
/// length `n * m`, where element `(i, j)` (0-indexed) lives at index
/// `i * m + j`. This flat layout matches the convention used elsewhere in
/// this crate (e.g. `max_flow`'s adjacency matrix).
///
/// Two element types are supported:
/// - `Int` (32-bit): matrix multiplication accumulates each dot product in
///   `Int64` before storing the result, so a single product `a*b` that
///   overflows 32-bit `Int` no longer corrupts the running sum.
/// - `Int64` (64-bit): all arithmetic stays in `Int64`.
///
/// Determinant and Gaussian elimination use the Bareiss (fraction-free)
/// algorithm: every update
///   `M[i][j] = (pivot * M[i][j] - factor * M[pivot][j]) / prev`
/// is an exact integer division, so no fractions ever appear and the result
/// is exact for integer inputs.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

// ---------------------------------------------------------------------------
// Identity
// ---------------------------------------------------------------------------

/// Build the `n x n` identity matrix of `Int`.
///
/// The diagonal is `1`, every off-diagonal entry is `0`. For `n <= 0` an
/// empty array is returned.
pub fn identity_int(n : Int) -> FixedArray[Int] {
  let r = FixedArray::make(n * n, 0)
  for i = 0; i < n; i = i + 1 {
    r[i * n + i] = 1
  }
  r
}

/// Build the `n x n` identity matrix of `Int64`.
pub fn identity_int64(n : Int) -> FixedArray[Int64] {
  let r = FixedArray::make(n * n, 0L)
  for i = 0; i < n; i = i + 1 {
    r[i * n + i] = 1L
  }
  r
}

// ---------------------------------------------------------------------------
// Transpose
// ---------------------------------------------------------------------------

/// Transpose an `n x m` `Int` matrix into an `m x n` matrix.
///
/// Element `(i, j)` of the input becomes element `(j, i)` of the output.
pub fn transpose_int(
  mat : FixedArray[Int],
  n : Int,
  m : Int,
) -> FixedArray[Int] {
  let r = FixedArray::make(n * m, 0)
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < m; j = j + 1 {
      r[j * n + i] = mat[i * m + j]
    }
  }
  r
}

/// Transpose an `n x m` `Int64` matrix into an `m x n` matrix.
pub fn transpose_int64(
  mat : FixedArray[Int64],
  n : Int,
  m : Int,
) -> FixedArray[Int64] {
  let r = FixedArray::make(n * m, 0L)
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < m; j = j + 1 {
      r[j * n + i] = mat[i * m + j]
    }
  }
  r
}

// ---------------------------------------------------------------------------
// Matrix multiplication
// ---------------------------------------------------------------------------

/// Multiply `Int` matrix `A` (`n x m`) by `Int` matrix `B` (`m x p`).
///
/// Returns the `n x p` product `C` where `C[i][j] = sum_k A[i][k] * B[k][j]`.
///
/// Each product is computed and accumulated in `Int64` to prevent intermediate
/// overflow: the factors are widened to `Int64` *before* multiplying, so a
/// product that exceeds 32-bit `Int` range is still computed correctly. The
/// final sum is narrowed back to `Int`; callers must ensure each result fits
/// in 32-bit `Int` (otherwise `to_int` produces an out-of-range value).
///
/// Returns an empty array when `n <= 0`, `p <= 0`, `m < 0`, or the input
/// arrays are too short for the declared dimensions.
pub fn matmul_int(
  a : FixedArray[Int],
  n : Int,
  m : Int,
  b : FixedArray[Int],
  p : Int,
) -> FixedArray[Int] {
  if n <= 0 || p <= 0 || m < 0 || a.length() < n * m || b.length() < m * p {
    return FixedArray::make(0, 0)
  }
  let r = FixedArray::make(n * p, 0)
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < p; j = j + 1 {
      let mut sum = 0L
      for k = 0; k < m; k = k + 1 {
        sum = sum + a[i * m + k].to_int64() * b[k * p + j].to_int64()
      }
      r[i * p + j] = sum.to_int()
    }
  }
  r
}

/// Multiply `Int64` matrix `A` (`n x m`) by `Int64` matrix `B` (`m x p`).
///
/// Returns the `n x p` product. All arithmetic is in `Int64`; the dot product
/// of two `Int64` vectors may itself overflow `Int64` for very large entries,
/// in which case the result wraps.
///
/// Returns an empty array for invalid or mismatched dimensions.
pub fn matmul_int64(
  a : FixedArray[Int64],
  n : Int,
  m : Int,
  b : FixedArray[Int64],
  p : Int,
) -> FixedArray[Int64] {
  if n <= 0 || p <= 0 || m < 0 || a.length() < n * m || b.length() < m * p {
    return FixedArray::make(0, 0L)
  }
  let r = FixedArray::make(n * p, 0L)
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < p; j = j + 1 {
      let mut sum = 0L
      for k = 0; k < m; k = k + 1 {
        sum = sum + a[i * m + k] * b[k * p + j]
      }
      r[i * p + j] = sum
    }
  }
  r
}

// ---------------------------------------------------------------------------
// Matrix power (fast exponentiation)
// ---------------------------------------------------------------------------

/// Raise an `n x n` `Int` matrix to the power `exp` via binary exponentiation.
///
/// Computes `A^exp` in `O(log exp)` matrix multiplications. Each multiplication
/// accumulates in `Int64` (see `matmul_int`). `exp == 0` yields the identity
/// matrix; `exp < 0` is treated as `0` (identity). The input is not modified.
pub fn matpow_int(a : FixedArray[Int], n : Int, exp : Int) -> FixedArray[Int] {
  let acc = identity_int(n)
  if n <= 0 || exp <= 0 {
    return acc
  }
  // Copy the base so squaring never aliases the caller's array.
  let base = FixedArray::make(n * n, 0)
  for i = 0; i < n * n; i = i + 1 {
    base[i] = a[i]
  }
  let mut e = exp
  let mut acc = acc
  let mut b = base
  while e > 0 {
    if e % 2 == 1 {
      acc = matmul_int(acc, n, n, b, n)
    }
    e = e / 2
    if e > 0 {
      b = matmul_int(b, n, n, b, n)
    }
  }
  acc
}

/// Raise an `n x n` `Int64` matrix to the power `exp` via binary exponentiation.
///
/// `exp == 0` yields the identity matrix; `exp < 0` is treated as `0`.
/// The input is not modified.
pub fn matpow_int64(
  a : FixedArray[Int64],
  n : Int,
  exp : Int,
) -> FixedArray[Int64] {
  let acc = identity_int64(n)
  if n <= 0 || exp <= 0 {
    return acc
  }
  let base = FixedArray::make(n * n, 0L)
  for i = 0; i < n * n; i = i + 1 {
    base[i] = a[i]
  }
  let mut e = exp
  let mut acc = acc
  let mut b = base
  while e > 0 {
    if e % 2 == 1 {
      acc = matmul_int64(acc, n, n, b, n)
    }
    e = e / 2
    if e > 0 {
      b = matmul_int64(b, n, n, b, n)
    }
  }
  acc
}

// ---------------------------------------------------------------------------
// Gaussian elimination (fraction-free / Bareiss-Montante)
// ---------------------------------------------------------------------------

/// Fraction-free Gaussian elimination on an `n x m` `Int64` matrix, in place.
///
/// Reduces the matrix to row echelon form using only integer arithmetic.
/// At each pivot step every updated entry is
///   `M[i][j] = (pivot * M[i][j] - factor * M[pivot][j]) / prev`
/// where `prev` is the previous pivot (initially `1`). The Bareiss theorem
/// guarantees the division is always exact, so no fractions appear and the
/// transformed matrix stays integral.
///
/// Returns the rank (number of non-zero rows). The input matrix is modified.
pub fn gauss_int64(mat : FixedArray[Int64], n : Int, m : Int) -> Int {
  if n <= 0 || m <= 0 {
    return 0
  }
  let mut prev = 1L
  let mut rank = 0
  for col = 0; col < m; col = col + 1 {
    if rank < n {
      // Search for a pivot row at or below `rank` with a nonzero entry.
      let mut pivot_row = -1
      let mut r = rank
      while r < n && pivot_row < 0 {
        if mat[r * m + col] != 0L {
          pivot_row = r
        }
        r = r + 1
      }
      if pivot_row >= 0 {
        // Bring the pivot row into position `rank`.
        if pivot_row != rank {
          for j = 0; j < m; j = j + 1 {
            let tmp = mat[rank * m + j]
            mat[rank * m + j] = mat[pivot_row * m + j]
            mat[pivot_row * m + j] = tmp
          }
        }
        let pivot = mat[rank * m + col]
        // Eliminate every row below the pivot.
        for i = rank + 1; i < n; i = i + 1 {
          let factor = mat[i * m + col]
          for j = col; j < m; j = j + 1 {
            let num = pivot * mat[i * m + j] - factor * mat[rank * m + j]
            mat[i * m + j] = num / prev
          }
          mat[i * m + col] = 0L
        }
        prev = pivot
        rank = rank + 1
      }
    }
  }
  rank
}

/// Fraction-free Gaussian elimination on an `n x m` `Int` matrix, in place.
///
/// Delegates to `gauss_int64` by widening to `Int64`, then writes the echelon
/// form back as `Int`. The rank is always computed exactly in `Int64`; the
/// stored echelon form may overflow `Int` for large matrices (use
/// `gauss_int64` directly in that case). Returns the rank.
pub fn gauss_int(mat : FixedArray[Int], n : Int, m : Int) -> Int {
  if n <= 0 || m <= 0 {
    return 0
  }
  let buf = FixedArray::make(n * m, 0L)
  for i = 0; i < n * m; i = i + 1 {
    buf[i] = mat[i].to_int64()
  }
  let rank = gauss_int64(buf, n, m)
  for i = 0; i < n * m; i = i + 1 {
    mat[i] = buf[i].to_int()
  }
  rank
}

// ---------------------------------------------------------------------------
// Determinant (fraction-free / Bareiss)
// ---------------------------------------------------------------------------

/// Determinant of an `n x n` `Int64` matrix via the Bareiss algorithm.
///
/// A copy is reduced to upper-triangular form with exact integer divisions;
/// the determinant is the last pivot, sign-corrected for row swaps. The input
/// is not modified.
///
/// Returns `1` for `n == 0` (by convention) and `0` for singular matrices.
pub fn determinant_int64(mat : FixedArray[Int64], n : Int) -> Int64 {
  if n <= 0 {
    return 1L
  }
  if n == 1 {
    return mat[0]
  }
  // Work on a copy so the caller's matrix is untouched.
  let a = FixedArray::make(n * n, 0L)
  for i = 0; i < n * n; i = i + 1 {
    a[i] = mat[i]
  }
  let mut prev = 1L
  let mut sign = 1L
  let mut singular = false
  for k = 0; k < n - 1; k = k + 1 {
    if !singular {
      if a[k * n + k] == 0L {
        // Find a row below with a nonzero entry in column k to swap in.
        let mut swap_row = -1
        let mut r = k + 1
        while r < n && swap_row < 0 {
          if a[r * n + k] != 0L {
            swap_row = r
          }
          r = r + 1
        }
        if swap_row < 0 {
          singular = true
        } else {
          for j = 0; j < n; j = j + 1 {
            let tmp = a[k * n + j]
            a[k * n + j] = a[swap_row * n + j]
            a[swap_row * n + j] = tmp
          }
          sign = -sign
        }
      }
      if !singular {
        let pivot = a[k * n + k]
        for i = k + 1; i < n; i = i + 1 {
          let factor = a[i * n + k]
          for j = k + 1; j < n; j = j + 1 {
            let num = pivot * a[i * n + j] - factor * a[k * n + j]
            a[i * n + j] = num / prev
          }
          a[i * n + k] = 0L
        }
        prev = pivot
      }
    }
  }
  if singular {
    return 0L
  }
  sign * a[(n - 1) * n + (n - 1)]
}

/// Determinant of an `n x n` `Int` matrix.
///
/// Widens to `Int64` and delegates to `determinant_int64`, so the result is
/// exact and never overflows 32-bit `Int`. The input is not modified.
pub fn determinant_int(mat : FixedArray[Int], n : Int) -> Int64 {
  if n <= 0 {
    return 1L
  }
  let a = FixedArray::make(n * n, 0L)
  for i = 0; i < n * n; i = i + 1 {
    a[i] = mat[i].to_int64()
  }
  determinant_int64(a, n)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "identity: Int and Int64, various sizes" {
  // 3x3: row-major [1,0,0, 0,1,0, 0,0,1]
  let id = identity_int(3)
  assert_eq(id[0], 1)
  assert_eq(id[4], 1)
  assert_eq(id[8], 1)
  assert_eq(id[1], 0)
  assert_eq(id[2], 0)
  assert_eq(id[3], 0)
  let id64 = identity_int64(3)
  assert_eq(id64[0], 1L)
  assert_eq(id64[4], 1L)
  assert_eq(id64[8], 1L)
  assert_eq(id64[1], 0L)
  // 1x1 and 0x0
  let one = identity_int(1)
  assert_eq(one.length(), 1)
  assert_eq(one[0], 1)
  let empty = identity_int(0)
  assert_eq(empty.length(), 0)
}

test "transpose: Int and Int64 matrices" {
  // Int: 2x3 -> 3x2
  // [1 2 3]     [1 4]
  // [4 5 6] ->  [2 5]
  //             [3 6]
  let mat = FixedArray::make(6, 0)
  mat[0] = 1
  mat[1] = 2
  mat[2] = 3
  mat[3] = 4
  mat[4] = 5
  mat[5] = 6
  let t = transpose_int(mat, 2, 3)
  assert_eq(t[0], 1)
  assert_eq(t[1], 4)
  assert_eq(t[2], 2)
  assert_eq(t[3], 5)
  assert_eq(t[4], 3)
  assert_eq(t[5], 6)
  // Int64: square 2x2
  // [1 2]     [1 3]
  // [3 4] ->  [2 4]
  let mat64 = FixedArray::make(4, 0L)
  mat64[0] = 1L
  mat64[1] = 2L
  mat64[2] = 3L
  mat64[3] = 4L
  let t64 = transpose_int64(mat64, 2, 2)
  assert_eq(t64[0], 1L)
  assert_eq(t64[1], 3L)
  assert_eq(t64[2], 2L)
  assert_eq(t64[3], 4L)
}

test "matmul_int: basic multiplication and identity" {
  // [1 2]   [5 6]   [19 22]
  // [3 4] * [7 8] = [43 50]
  let a = FixedArray::make(4, 0)
  a[0] = 1
  a[1] = 2
  a[2] = 3
  a[3] = 4
  let b = FixedArray::make(4, 0)
  b[0] = 5
  b[1] = 6
  b[2] = 7
  b[3] = 8
  let c = matmul_int(a, 2, 2, b, 2)
  assert_eq(c[0], 19)
  assert_eq(c[1], 22)
  assert_eq(c[2], 43)
  assert_eq(c[3], 50)
  // A (2x3) * I3 (3x3) = A
  let a23 = FixedArray::make(6, 0)
  a23[0] = 1
  a23[1] = 2
  a23[2] = 3
  a23[3] = 4
  a23[4] = 5
  a23[5] = 6
  let id3 = identity_int(3)
  let c1 = matmul_int(a23, 2, 3, id3, 3)
  assert_eq(c1[0], 1)
  assert_eq(c1[5], 6)
  // I2 (2x2) * A (2x3) = A
  let id2 = identity_int(2)
  let c2 = matmul_int(id2, 2, 2, a23, 3)
  assert_eq(c2[0], 1)
  assert_eq(c2[5], 6)
}

test "matmul_int: Int64 accumulation prevents overflow" {
  // 50000 * 50000 = 2,500,000,000 which overflows 32-bit Int (> 2,147,483,647).
  // The factors are widened to Int64 *before* multiplying, so each product is
  // exact and the running sum stays correct. The final results fit in Int.
  //   [ 50000 -40000]   [50000]     50000*50000 + (-40000)*40000 = 900,000,000
  //   [-40000  50000] * [40000] =  (-40000)*50000 + 50000*40000  =         0
  let a = FixedArray::make(4, 0)
  a[0] = 50000
  a[1] = -40000
  a[2] = -40000
  a[3] = 50000
  let b = FixedArray::make(2, 0)
  b[0] = 50000
  b[1] = 40000
  let c = matmul_int(a, 2, 2, b, 1)
  assert_eq(c[0], 900000000)
  assert_eq(c[1], 0)
}

test "matmul: dimension mismatch returns empty (Int and Int64)" {
  // Int: b is only length 4, needs 3*2=6
  let a = FixedArray::make(6, 0)
  let b = FixedArray::make(4, 0)
  let c = matmul_int(a, 2, 3, b, 2)
  assert_eq(c.length(), 0)
  // Int64: same mismatch
  let a64 = FixedArray::make(6, 0L)
  let b64 = FixedArray::make(4, 0L)
  let c64 = matmul_int64(a64, 2, 3, b64, 2)
  assert_eq(c64.length(), 0)
}

test "matmul_int64: large values beyond Int32 range" {
  // Entries and products far exceed 32-bit Int; Int64 keeps them exact.
  // [100000 200000]   [500000 600000]   [1.9e11 2.2e11]
  // [300000 400000] * [700000 800000] = [4.3e11 5.0e11]
  let a = FixedArray::make(4, 0L)
  a[0] = 100000L
  a[1] = 200000L
  a[2] = 300000L
  a[3] = 400000L
  let b = FixedArray::make(4, 0L)
  b[0] = 500000L
  b[1] = 600000L
  b[2] = 700000L
  b[3] = 800000L
  let c = matmul_int64(a, 2, 2, b, 2)
  assert_eq(c[0], 190000000000L)
  assert_eq(c[1], 220000000000L)
  assert_eq(c[2], 430000000000L)
  assert_eq(c[3], 500000000000L)
}

test "matpow_int: zero, one, square, and cube" {
  let a = FixedArray::make(4, 0)
  a[0] = 1
  a[1] = 2
  a[2] = 3
  a[3] = 4
  // A^0 = I
  let z = matpow_int(a, 2, 0)
  assert_eq(z[0], 1)
  assert_eq(z[3], 1)
  assert_eq(z[1], 0)
  // A^1 = A
  let o = matpow_int(a, 2, 1)
  assert_eq(o[0], 1)
  assert_eq(o[1], 2)
  assert_eq(o[2], 3)
  assert_eq(o[3], 4)
  // A^2 = [7 10; 15 22]
  let sq = matpow_int(a, 2, 2)
  assert_eq(sq[0], 7)
  assert_eq(sq[1], 10)
  assert_eq(sq[2], 15)
  assert_eq(sq[3], 22)
  // A^3 = A^2 * A = [37 54; 81 118]
  let cu = matpow_int(a, 2, 3)
  assert_eq(cu[0], 37)
  assert_eq(cu[1], 54)
  assert_eq(cu[2], 81)
  assert_eq(cu[3], 118)
}

test "matpow: Fibonacci via matrix power (Int and Int64)" {
  // [[1,1],[1,0]]^n = [[F(n+1), F(n)], [F(n), F(n-1)]]
  // Int: F(10)=55, F(11)=89, F(9)=34
  let a = FixedArray::make(4, 0)
  a[0] = 1
  a[1] = 1
  a[2] = 1
  a[3] = 0
  let r = matpow_int(a, 2, 10)
  assert_eq(r[0], 89) // F(11)
  assert_eq(r[1], 55) // F(10)
  assert_eq(r[2], 55) // F(10)
  assert_eq(r[3], 34) // F(9)
  // Int64: F(90) = 2880067194370816120, F(89) = 1779979416004714189
  let a64 = FixedArray::make(4, 0L)
  a64[0] = 1L
  a64[1] = 1L
  a64[2] = 1L
  a64[3] = 0L
  let r64 = matpow_int64(a64, 2, 90)
  assert_eq(r64[1], 2880067194370816120L) // F(90)
  assert_eq(r64[3], 1779979416004714189L) // F(89)
}

test "gauss: full rank, rank-deficient, zero column, and rank 1" {
  // Full rank 3x3 (det = -3 != 0):
  // [1 2 3]
  // [4 5 6]
  // [7 8 10]
  let full = FixedArray::make(9, 0)
  full[0] = 1
  full[1] = 2
  full[2] = 3
  full[3] = 4
  full[4] = 5
  full[5] = 6
  full[6] = 7
  full[7] = 8
  full[8] = 10
  assert_eq(gauss_int(full, 3, 3), 3)
  // Rank-deficient: row 3 = row 1 + row 2
  // [1 2]
  // [3 4]
  // [4 6]  (= row1 + row2)
  let deficient = FixedArray::make(6, 0)
  deficient[0] = 1
  deficient[1] = 2
  deficient[2] = 3
  deficient[3] = 4
  deficient[4] = 4
  deficient[5] = 6
  assert_eq(gauss_int(deficient, 3, 2), 2)
  // Zero column: column 1 all zeros -> rank 2
  // [2 0 3]
  // [4 0 5]
  // [8 0 9]
  let zc = FixedArray::make(9, 0L)
  zc[0] = 2L
  zc[1] = 0L
  zc[2] = 3L
  zc[3] = 4L
  zc[4] = 0L
  zc[5] = 5L
  zc[6] = 8L
  zc[7] = 0L
  zc[8] = 9L
  assert_eq(gauss_int64(zc, 3, 3), 2)
  // Rank 1: all rows multiples of [1 2 3]
  let r1 = FixedArray::make(9, 0L)
  r1[0] = 1L
  r1[1] = 2L
  r1[2] = 3L
  r1[3] = 2L
  r1[4] = 4L
  r1[5] = 6L
  r1[6] = 3L
  r1[7] = 6L
  r1[8] = 9L
  assert_eq(gauss_int64(r1, 3, 3), 1)
}

test "determinant: 2x2, 3x3, and singular matrices" {
  // 2x2: [4 3; 6 3] -> 4*3 - 3*6 = 12 - 18 = -6
  let m2 = FixedArray::make(4, 0)
  m2[0] = 4
  m2[1] = 3
  m2[2] = 6
  m2[3] = 3
  assert_eq(determinant_int(m2, 2), -6L)
  // 3x3: [1 2 3; 4 5 6; 7 8 10] -> det = -3
  let m3 = FixedArray::make(9, 0)
  m3[0] = 1
  m3[1] = 2
  m3[2] = 3
  m3[3] = 4
  m3[4] = 5
  m3[5] = 6
  m3[6] = 7
  m3[7] = 8
  m3[8] = 10
  assert_eq(determinant_int(m3, 3), -3L)
  // Singular: [1 2 3; 4 5 6; 7 8 9] -> rank 2, det 0
  let s = FixedArray::make(9, 0)
  s[0] = 1
  s[1] = 2
  s[2] = 3
  s[3] = 4
  s[4] = 5
  s[5] = 6
  s[6] = 7
  s[7] = 8
  s[8] = 9
  assert_eq(determinant_int(s, 3), 0L)
}

test "determinant: zero pivot row swap and edge cases" {
  // [0 2; 3 4] -> det = 0*4 - 2*3 = -6
  // A zero leading pivot forces a row swap (sign flips) during Bareiss.
  let m = FixedArray::make(4, 0L)
  m[0] = 0L
  m[1] = 2L
  m[2] = 3L
  m[3] = 4L
  assert_eq(determinant_int64(m, 2), -6L)
  // [0 1 0; 1 0 0; 0 0 1] is a permutation matrix, det = -1.
  let p = FixedArray::make(9, 0L)
  p[1] = 1L
  p[3] = 1L
  p[8] = 1L
  assert_eq(determinant_int64(p, 3), -1L)
  // 1x1: det = the single element
  let one = FixedArray::make(1, 0)
  one[0] = 42
  assert_eq(determinant_int(one, 1), 42L)
  // 0x0: det = 1 by convention
  let empty : FixedArray[Int] = FixedArray::make(0, 0)
  assert_eq(determinant_int(empty, 0), 1L)
}

test "determinant_int64: input not modified" {
  let m = FixedArray::make(4, 0L)
  m[0] = 4L
  m[1] = 3L
  m[2] = 6L
  m[3] = 3L
  let _ = determinant_int64(m, 2)
  assert_eq(m[0], 4L)
  assert_eq(m[1], 3L)
  assert_eq(m[2], 6L)
  assert_eq(m[3], 3L)
}
