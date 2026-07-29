/// Aliens' Trick -- Lagrangian relaxation for constrained DP.
///
/// Solves: select at most `k` items from `costs[0..n)` to maximize the
/// total value. Instead of tracking the item count in the DP state, we
/// add a per-item penalty `lambda` and binary-search on `lambda` until
/// the unconstrained optimum uses the desired number of items.
///
/// ## Complexity
/// - Time:  O(n log C) where C = max cost magnitude.
/// - Space: O(1).
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

///|
/// Relaxed objective for a given Lagrange multiplier `lambda`.
///
/// Picks every item whose net gain `cost - lambda` is strictly positive.
/// Returns `(adjusted_value, count)` where `adjusted_value` is the sum
/// of net gains and `count` is how many items were picked.
fn solve_lambda(costs : Array[Int], lambda : Int, n : Int) -> (Int, Int) {
  let mut val = 0
  let mut cnt = 0
  for i = 0; i < n; i = i + 1 {
    let gain = costs[i] - lambda
    if gain > 0 {
      val = val + gain
      cnt = cnt + 1
    }
  }
  (val, cnt)
}

///|
/// Maximum total value selecting at most `k` items from `costs[0..n)`.
///
/// Returns `None` for invalid inputs (negative `n`/`k`, or `costs` shorter
/// than `n`). Returns `Some(value)` otherwise.
pub fn aliens_trick(n : Int, costs : Array[Int], k : Int) -> Int? {
  if n < 0 || k < 0 || costs.length() < n {
    return None
  }
  if n == 0 || k == 0 {
    return Some(0)
  }
  // Upper bound for lambda: above the maximum cost nothing is picked.
  let mut max_c = costs[0]
  for i = 1; i < n; i = i + 1 {
    if costs[i] > max_c {
      max_c = costs[i]
    }
  }
  if max_c <= 0 {
    return Some(0)
  }
  // If lambda = 0 already picks <= k items, take them all.
  let (val0, cnt0) = solve_lambda(costs, 0, n)
  if cnt0 <= k {
    return Some(val0)
  }
  // Binary search for the largest lambda where count >= k.
  let mut lo = 0 // count(lo) >= k
  let mut hi = max_c + 1 // count(hi) = 0 < k
  while lo + 1 < hi {
    let mid = lo + (hi - lo) / 2
    let (_, cnt) = solve_lambda(costs, mid, n)
    if cnt >= k {
      lo = mid
    } else {
      hi = mid
    }
  }
  // The dual f(lambda) = val(lambda) + lambda * k is convex; its minimum
  // lies at the count transition, so take min(f(lo), f(hi)).
  let (vlo, _) = solve_lambda(costs, lo, n)
  let (vhi, _) = solve_lambda(costs, hi, n)
  let f_lo = vlo + lo * k
  let f_hi = vhi + hi * k
  Some(if f_lo < f_hi { f_lo } else { f_hi })
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "aliens_trick: pick top k from distinct values" {
  // Pick 3 of [10, 20, 30, 40, 50] -> 30 + 40 + 50 = 120
  assert_eq(aliens_trick(5, [10, 20, 30, 40, 50], 3), Some(120))
}

///|
test "aliens_trick: ties at boundary" {
  // Pick 2 of [5, 5, 5, 5] -> 5 + 5 = 10
  assert_eq(aliens_trick(4, [5, 5, 5, 5], 2), Some(10))
}

///|
test "aliens_trick: at-most semantics with negatives" {
  // Only 10 and 20 are positive; k = 5 so take both -> 30
  assert_eq(aliens_trick(4, [10, -5, 20, -10], 5), Some(30))
}

///|
test "aliens_trick: k equals zero" {
  assert_eq(aliens_trick(3, [10, 20, 30], 0), Some(0))
}

///|
test "aliens_trick: n equals zero" {
  assert_eq(aliens_trick(0, [], 5), Some(0))
}

///|
test "aliens_trick: all negative costs" {
  assert_eq(aliens_trick(3, [-10, -20, -30], 2), Some(0))
}

///|
test "aliens_trick: k greater than n" {
  // Pick all positive: 5 + 10 + 15 = 30
  assert_eq(aliens_trick(3, [5, 10, 15], 10), Some(30))
}

///|
test "aliens_trick: single element" {
  assert_eq(aliens_trick(1, [42], 1), Some(42))
}

///|
test "aliens_trick: invalid inputs return None" {
  assert_true(aliens_trick(-1, [1, 2], 1) is None)
  assert_true(aliens_trick(2, [1], 1) is None)
  assert_true(aliens_trick(2, [1, 2], -1) is None)
}

///|
test "aliens_trick: exact k with mixed signs" {
  // costs = [3, -1, 5, -2, 7], k = 3 → pick 3, 5, 7 = 15
  assert_eq(aliens_trick(5, [3, -1, 5, -2, 7], 3), Some(15))
}
