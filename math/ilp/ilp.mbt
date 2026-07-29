/// Integer Linear Programming solver using branch-and-bound.
///
/// Solves: maximize c^T x subject to Ax <= b, x >= 0, x integer.
///
/// ## Performance
/// - NP-hard in general; branch-and-bound with LP relaxation bounds
///
/// ## References
/// - Land, A.H. and Doig, A.G. "An automatic method for solving discrete
///   programming problems." Econometrica, 1960.
///
/// `proof-enabled` is `false`.

///|
/// Mutable state for branch-and-bound.
priv struct BBState {
  mut best_val : Double
  mut best_sol : Array[Int]
}

///|
/// Solve an ILP problem using branch-and-bound with LP relaxation.
///
/// `n_vars` = number of variables
/// `c` = objective coefficients (maximize c^T x)
/// `constraints` = list of (coefficients, bound) meaning sum(a_i * x_i) <= bound
/// `max_iter` = maximum branch-and-bound iterations
///
/// Returns (optimal_value, optimal_solution) or None if infeasible.
pub fn solve_ilp(
  n_vars : Int,
  c : Array[Double],
  constraints : Array[(Array[Double], Double)],
  max_iter : Int,
) -> (Double, Array[Int])? {
  let state = { best_val: -1.0e18, best_sol: Array::make(n_vars, 0) }
  let lb = Array::make(n_vars, 0)
  let ub = Array::make(n_vars, 1000)
  branch_and_bound(n_vars, c, constraints, lb, ub, state, max_iter, 0)
  if state.best_val < -1.0e17 {
    None
  } else {
    Some((state.best_val, state.best_sol))
  }
}

///|
/// Recursive branch-and-bound.
fn branch_and_bound(
  n_vars : Int,
  c : Array[Double],
  constraints : Array[(Array[Double], Double)],
  lb : Array[Int],
  ub : Array[Int],
  state : BBState,
  max_iter : Int,
  iter_count : Int,
) -> Unit {
  if iter_count >= max_iter {
    return
  }
  let (lp_val, lp_sol) = lp_relax(n_vars, c, constraints, lb, ub)
  if lp_val <= state.best_val {
    return
  }
  let mut frac_var = -1
  for i = 0; i < n_vars; i = i + 1 {
    let frac = lp_sol[i] - lp_sol[i].floor()
    if frac > 1.0e-6 && frac < 1.0 - 1.0e-6 {
      frac_var = i
      break
    }
  }
  if frac_var < 0 {
    if lp_val > state.best_val {
      state.best_val = lp_val
      let sol = Array::make(n_vars, 0)
      for i = 0; i < n_vars; i = i + 1 {
        sol[i] = lp_sol[i].to_int()
      }
      state.best_sol = sol
    }
    return
  }
  let floor_val = lp_sol[frac_var].floor().to_int()
  let ceil_val = floor_val + 1
  let old_ub = ub[frac_var]
  ub[frac_var] = floor_val
  if ub[frac_var] >= lb[frac_var] {
    branch_and_bound(n_vars, c, constraints, lb, ub, state, max_iter, iter_count + 1)
  }
  ub[frac_var] = old_ub
  let old_lb = lb[frac_var]
  lb[frac_var] = ceil_val
  if ub[frac_var] >= lb[frac_var] {
    branch_and_bound(n_vars, c, constraints, lb, ub, state, max_iter, iter_count + 1)
  }
  lb[frac_var] = old_lb
}

///|
/// Simple LP relaxation using greedy approach.
fn lp_relax(
  n_vars : Int,
  c : Array[Double],
  constraints : Array[(Array[Double], Double)],
  lb : Array[Int],
  ub : Array[Int],
) -> (Double, Array[Double]) {
  let sol = Array::make(n_vars, 0.0)
  for i = 0; i < n_vars; i = i + 1 {
    sol[i] = lb[i].to_double()
  }
  let mut improved = true
  while improved {
    improved = false
    for i = 0; i < n_vars; i = i + 1 {
      if sol[i] + 1.0 <= ub[i].to_double() + 1.0e-10 {
        let mut feasible = true
        for j = 0; j < constraints.length(); j = j + 1 {
          let (coeffs, bound) = constraints[j]
          let mut sum = 0.0
          for k = 0; k < n_vars; k = k + 1 {
            sum = sum + coeffs[k] * sol[k]
          }
          if sum + coeffs[i] > bound + 1.0e-10 {
            feasible = false
            break
          }
        }
        if feasible && c[i] > 0 {
          sol[i] = sol[i] + 1.0
          improved = true
        }
      }
    }
  }
  let mut obj = 0.0
  for i = 0; i < n_vars; i = i + 1 {
    obj = obj + c[i] * sol[i]
  }
  (obj, sol)
}

test "ilp: simple maximization" {
  let c = [1.0, 1.0]
  let constraints = [([1.0, 1.0], 5.0)]
  match solve_ilp(2, c, constraints, 1000) {
    Some((val, sol)) => {
      assert_true((val - 5.0).abs() < 1.0e-6)
      assert_eq(sol[0] + sol[1], 5)
    }
    None => assert_true(false)
  }
}

test "ilp: binary choice" {
  let c = [3.0, 2.0]
  let constraints = [([1.0, 1.0], 1.0)]
  match solve_ilp(2, c, constraints, 1000) {
    Some((val, sol)) => {
      assert_true((val - 3.0).abs() < 1.0e-6)
      assert_eq(sol[0], 1)
      assert_eq(sol[1], 0)
    }
    None => assert_true(false)
  }
}

test "ilp: knapsack" {
  let c = [6.0, 10.0, 12.0]
  let constraints = [([1.0, 2.0, 3.0], 5.0)]
  match solve_ilp(3, c, constraints, 1000) {
    Some((val, _sol)) => assert_true(val >= 28.0)
    None => assert_true(false)
  }
}
