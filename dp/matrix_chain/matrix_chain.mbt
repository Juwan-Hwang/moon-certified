fn compute_dp(dims: Array[Int], n: Int) -> (Array[Array[Int]], Array[Array[Int]]) {
  let m : Array[Array[Int]] = []
  let s : Array[Array[Int]] = []
  for _ in 0..<n {
    m.push(Array::make(n, 0))
    s.push(Array::make(n, 0))
  }
  for chain_len in 2..=n {
    for i in 0..<(n - chain_len + 1) {
      let j = i + chain_len - 1
      m[i][j] = 999999999
      for k in i..<j {
        let cost = m[i][k] + m[k + 1][j] + dims[i] * dims[k + 1] * dims[j + 1]
        if cost < m[i][j] {
          m[i][j] = cost
          s[i][j] = k
        }
      }
    }
  }
  (m, s)
}

fn matrix_chain_order(dims: Array[Int]) -> Int {
  let n = dims.length() - 1
  if n <= 1 {
    return 0
  }
  let (m, _) = compute_dp(dims, n)
  m[0][n - 1]
}

fn matrix_chain_parenthesization(dims: Array[Int]) -> String {
  let n = dims.length() - 1
  if n <= 0 {
    return ""
  }
  if n == 1 {
    return "A0"
  }
  let (_, s) = compute_dp(dims, n)
  build_parenthesization(0, n - 1, s)
}

fn build_parenthesization(i: Int, j: Int, s: Array[Array[Int]]) -> String {
  if i == j {
    "A" + i.to_string()
  } else {
    let left = build_parenthesization(i, s[i][j], s)
    let right = build_parenthesization(s[i][j] + 1, j, s)
    "(" + left + "*" + right + ")"
  }
}

test "basic chain of 3" {
  let dims = [10, 30, 5, 60]
  assert_eq(matrix_chain_order(dims), 4500)
  assert_eq(matrix_chain_parenthesization(dims), "((A0*A1)*A2)")
}

test "chain of 2" {
  let dims = [10, 20, 30]
  assert_eq(matrix_chain_order(dims), 6000)
  assert_eq(matrix_chain_parenthesization(dims), "(A0*A1)")
}

test "chain of 4" {
  let dims = [40, 20, 30, 10, 30]
  assert_eq(matrix_chain_order(dims), 26000)
  assert_eq(matrix_chain_parenthesization(dims), "((A0*(A1*A2))*A3)")
}

test "single matrix" {
  let dims = [10, 20]
  assert_eq(matrix_chain_order(dims), 0)
  assert_eq(matrix_chain_parenthesization(dims), "A0")
}
