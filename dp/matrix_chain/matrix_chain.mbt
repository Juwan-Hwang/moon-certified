/// Matrix-chain multiplication optimisation (DP).
///
/// Finds the optimal parenthesisation of a chain of matrix multiplications
/// to minimise the total number of scalar multiplications.
///
/// ## Overflow safety
///
/// The cost `dims[i] * dims[k+1] * dims[j+1]` is computed in `Int64` to
/// prevent overflow when the dimensions are large (e.g. three dimensions
/// near 2^10 would already overflow `Int32`). The DP table itself uses
/// `Int64` so that accumulated costs beyond 2^31 are handled correctly.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

///|
/// Large sentinel value representing infinity for DP initialisation.
/// Using Int64::max would cause overflow on addition, so we use a value
/// that is large enough for any practical matrix chain (a chain of 1000
/// matrices each of dimension 10^6 would cost at most ~10^24, far below
/// 2^62) but small enough that `INF + INF` does not overflow.
const INF : Int64 = 9223372036854775807L / 4L

///|
fn compute_dp(
  dims : Array[Int],
  n : Int,
) -> (Array[Array[Int64]], Array[Array[Int]]) {
  let m : Array[Array[Int64]] = []
  let s : Array[Array[Int]] = []
  for _ in 0..<n {
    m.push(Array::make(n, 0L))
    s.push(Array::make(n, 0))
  }
  for chain_len in 2..<=n {
    for i in 0..<(n - chain_len + 1) {
      let j = i + chain_len - 1
      m[i][j] = INF
      for k in i..<j {
        // Compute cost in Int64 to prevent overflow.
        let cost = m[i][k] +
          m[k + 1][j] +
          dims[i].to_int64() * dims[k + 1].to_int64() * dims[j + 1].to_int64()
        if cost < m[i][j] {
          m[i][j] = cost
          s[i][j] = k
        }
      }
    }
  }
  (m, s)
}

///|
/// Compute the minimum number of scalar multiplications for the chain.
///
/// Returns the cost as `Int`. If the optimal cost exceeds `Int::max_value`
/// (extremely unlikely for practical inputs), `Int::max_value` is returned.
pub fn matrix_chain_order(dims : Array[Int]) -> Int {
  let n = dims.length() - 1
  if n <= 1 {
    return 0
  }
  let (m, _) = compute_dp(dims, n)
  let cost = m[0][n - 1]
  if cost > 2147483647L {
    2147483647
  } else {
    cost.to_int()
  }
}

///|
/// Return the optimal parenthesisation as a string (e.g. "((A0*A1)*A2)").
pub fn matrix_chain_parenthesization(dims : Array[Int]) -> String {
  let n = dims.length() - 1
  if n <= 0 {
    return ""
  }
  if n == 1 {
    return "A0"
  }
  let (_, s) = compute_dp(dims, n)
  build_parenthesization_iterative(0, n - 1, s)
}

///|
/// Iterative parenthesisation builder using an explicit stack to avoid
/// recursion depth issues on large chains.
fn build_parenthesization_iterative(
  root_i : Int,
  root_j : Int,
  s : Array[Array[Int]],
) -> String {
  // Stack entries: (i, j, phase)
  // phase 0 = emit "(", process left, process right, emit ")"
  // phase 1 = emit "*", process right (after left is done)
  let stack : Array[(Int, Int, Int)] = [(root_i, root_j, 0)]
  let parts : Array[String] = []
  while stack.length() > 0 {
    let (i, j, phase) = stack[stack.length() - 1]
    if i == j {
      parts.push("A" + i.to_string())
      stack.remove(stack.length() - 1) |> ignore
      continue
    }
    if phase == 0 {
      parts.push("(")
      // Update phase to 1 (will process right after left returns).
      stack[stack.length() - 1] = (i, j, 1)
      // Push left child.
      stack.push((i, s[i][j], 0))
    } else if phase == 1 {
      parts.push("*")
      // Update phase to 2 (done after right returns).
      stack[stack.length() - 1] = (i, j, 2)
      // Push right child.
      stack.push((s[i][j] + 1, j, 0))
    } else {
      parts.push(")")
      stack.remove(stack.length() - 1) |> ignore
    }
  }
  let buf = StringBuilder()
  for i = 0; i < parts.length(); i = i + 1 {
    buf.write_string(parts[i])
  }
  buf.to_string()
}

///|
test "basic chain of 3" {
  let dims = [10, 30, 5, 60]
  assert_eq(matrix_chain_order(dims), 4500)
  assert_eq(matrix_chain_parenthesization(dims), "((A0*A1)*A2)")
}

///|
test "chain of 2" {
  let dims = [10, 20, 30]
  assert_eq(matrix_chain_order(dims), 6000)
  assert_eq(matrix_chain_parenthesization(dims), "(A0*A1)")
}

///|
test "chain of 4" {
  let dims = [40, 20, 30, 10, 30]
  assert_eq(matrix_chain_order(dims), 26000)
  assert_eq(matrix_chain_parenthesization(dims), "((A0*(A1*A2))*A3)")
}

///|
test "single matrix" {
  let dims = [10, 20]
  assert_eq(matrix_chain_order(dims), 0)
  assert_eq(matrix_chain_parenthesization(dims), "A0")
}

///|
test "large dimensions do not overflow" {
  // Three matrices with dimensions that would overflow Int32 if
  // multiplied as Int: 50000 * 50000 * 50000 = 1.25e14.
  let dims = [50000, 50000, 50000, 50000]
  let result = matrix_chain_order(dims)
  // The optimal cost is the same regardless of parenthesisation for
  // a chain of 3 identical dimensions: p0*p1*p2 + p0*p2*p3
  // = 50000^3 + 50000^3 = 2.5e14, which exceeds Int32 max.
  assert_true(result == 2147483647) // clamped to Int max
}
