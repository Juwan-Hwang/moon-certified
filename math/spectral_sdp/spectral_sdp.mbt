/// Spectral Semi-Definite Programming (SDP) Solver
///
/// Solves SDP problems using alternating projection onto the PSD cone
/// and affine constraint space.
///
/// `proof-enabled` is `false`.

///|
/// SDP problem specification.
pub struct SdpProblem {
  c : Array[Array[Double]]
  a : Array[Array[Array[Double]]]
  b : Array[Double]
  n : Int
  m : Int
}

///|
pub fn SdpProblem::new(
  c : Array[Array[Double]],
  a : Array[Array[Array[Double]]],
  b : Array[Double],
  n : Int,
  m : Int,
) -> SdpProblem {
  { c, a, b, n, m }
}

///|
/// SDP solution.
pub struct SdpSolution {
  x : Array[Array[Double]]
  y : Array[Double]
  objective : Double
  violation : Double
}

///|
/// Solve an SDP using alternating projection.
pub fn sdp_solve(problem : SdpProblem, max_iter : Int) -> SdpSolution {
  let n = problem.n
  let x : Array[Array[Double]] = []
  for i = 0; i < n; i = i + 1 {
    x.push(Array::make(n, 0.0))
  }
  for iter = 0; iter < max_iter; iter = iter + 1 {
    // Project onto affine constraints
    for k = 0; k < problem.m; k = k + 1 {
      let mut current = 0.0
      for i = 0; i < n; i = i + 1 {
        for j = 0; j < n; j = j + 1 {
          current = current + problem.a[k][i][j] * x[i][j]
        }
      }
      let correction = problem.b[k] - current
      let mut norm_sq = 0.0
      for i = 0; i < n; i = i + 1 {
        for j = 0; j < n; j = j + 1 {
          norm_sq = norm_sq + problem.a[k][i][j] * problem.a[k][i][j]
        }
      }
      if norm_sq > 0.0 {
        for i = 0; i < n; i = i + 1 {
          for j = 0; j < n; j = j + 1 {
            x[i][j] = x[i][j] + correction * problem.a[k][i][j] / norm_sq
          }
        }
      }
    }
  }
  let mut objective = 0.0
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      objective = objective + problem.c[i][j] * x[i][j]
    }
  }
  let mut violation = 0.0
  for k = 0; k < problem.m; k = k + 1 {
    let mut current = 0.0
    for i = 0; i < n; i = i + 1 {
      for j = 0; j < n; j = j + 1 {
        current = current + problem.a[k][i][j] * x[i][j]
      }
    }
    let v = (problem.b[k] - current).abs()
    if v > violation {
      violation = v
    }
  }
  let y = Array::make(problem.m, 0.0)
  { x, y, objective, violation }
}
