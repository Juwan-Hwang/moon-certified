/// AdaBoost.M1 — adaptive boosting of decision stumps.
///
/// Combates many weak classifiers (here: decision stumps — a single
/// axis-aligned threshold) into a strong classifier by reweighting: each
/// round focuses the next learner on the samples the current ensemble gets
/// wrong. Labels use the ±1 convention.
///
/// ## Algorithm (AdaBoost.M1, Freund & Schapire)
/// 1. Initialise sample weights `w_i = 1/n`.
/// 2. For `t = 1 .. T`:
///    a. Train a stump `h_t` minimising the *weighted* misclassification
///       error `ε_t = Σ w_i [h_t(x_i) ≠ y_i]`.
///    b. Stop early if `ε_t ≥ ½` (the learner is no better than chance).
///    c. `α_t = ½ ln((1 − ε_t) / ε_t)` (clamped for `ε_t → 0`).
///    d. Reweight `w_i ← w_i · exp(−α_t y_i h_t(x_i))` and renormalise.
///       Correct predictions shrink a weight, wrong ones grow it.
/// 3. Classify by `sign(Σ_t α_t h_t(x))`.
///
/// ## Complexity
/// - Training: `O(T × n × d × log n)` (per round: sort each feature).
/// - Prediction: `O(T × d)` per row.
///
/// No external dependency: `exp` and `ln` are implemented locally.
///
/// Not formally verified. Correctness is ensured by the test suite.

// ---------------------------------------------------------------------------
// Local transcendentals (no @math import required)
// ---------------------------------------------------------------------------

///|
/// Natural exponential via argument halving + Taylor series. Accurate to
/// ~1e-15; saturates for very large arguments.
fn exp_double(x : Double) -> Double {
  if x >= 700.0 {
    return 1.7976931348623157e308
  }
  if x <= -745.0 {
    return 0.0
  }
  let mut r = x
  let mut n = 0
  while r > 0.5 || r < -0.5 {
    r = r / 2.0
    n = n + 1
  }
  let mut term = 1.0
  let mut sum = 1.0
  for i = 1; i < 20; i = i + 1 {
    term = term * r / i.to_double()
    sum = sum + term
    if term < 0.0 {
      if -term < 1.0e-18 * sum {
        break
      }
    } else if term < 1.0e-18 * sum {
      break
    }
  }
  let mut result = sum
  for _i = 0; _i < n; _i = _i + 1 {
    result = result * result
  }
  result
}

///|
/// Natural logarithm via range reduction + atanh series. Accurate to ~1e-15;
/// returns a large negative number for `x ≤ 0`.
fn ln_double(x : Double) -> Double {
  if x <= 0.0 {
    return -700.0
  }
  let mut m = x
  let mut k = 0
  while m >= 2.0 {
    m = m / 2.0
    k = k + 1
  }
  while m < 1.0 {
    m = m * 2.0
    k = k - 1
  }
  let z = (m - 1.0) / (m + 1.0)
  let z2 = z * z
  let mut term = z
  let mut sum = z
  for i = 1; i < 40; i = i + 1 {
    term = term * z2
    let inc = term / (2 * i + 1).to_double()
    sum = sum + inc
    if inc < 0.0 {
      if -inc < 1.0e-18 {
        break
      }
    } else if inc < 1.0e-18 {
      break
    }
  }
  k.to_double() * 0.6931471805599453 + 2.0 * sum
}

// ---------------------------------------------------------------------------
// Decision stump
// ---------------------------------------------------------------------------

///|
/// A decision stump: classify by `polarity · sign(threshold − x[feature])`.
/// With `polarity = +1`, `x[feature] ≤ threshold ⇒ +1`, else `−1`; with
/// `polarity = −1` the sense is reversed.
priv struct Stump {
  feature : Int
  threshold : Double
  polarity : Int // +1 or -1
}

///|
/// Predict ±1 with a stump.
fn stump_predict(s : Stump, x : Array[Double]) -> Int {
  let left = x[s.feature] <= s.threshold
  if s.polarity == 1 {
    if left {
      1
    } else {
      -1
    }
  } else if left {
    -1
  } else {
    1
  }
}

///|
fn cmp_double(a : Double, b : Double) -> Int {
  if a < b {
    -1
  } else if a > b {
    1
  } else {
    0
  }
}

///|
/// Train the best weighted-error stump over all features and candidate
/// thresholds (the sorted unique feature values). Returns the stump and its
/// weighted error `ε` (clamped into `(0, 1)`).
fn best_stump(
  x : Array[Array[Double]],
  y : Array[Int],
  w : Array[Double],
  n_features : Int,
) -> (Stump, Double) {
  let n = x.length()
  let mut best_err = 2.0 // above 1 → impossible, acts as +inf
  let mut best = { feature: 0, threshold: 0.0, polarity: 1 }
  for f = 0; f < n_features; f = f + 1 {
    // Candidate thresholds: sorted unique values of feature f.
    let values : Array[Double] = []
    for i = 0; i < n; i = i + 1 {
      values.push(x[i][f])
    }
    values.sort_by(cmp_double)
    let mut ti = 0
    while ti < n {
      let thresh = values[ti]
      // skip duplicates
      while ti + 1 < n && values[ti + 1] == thresh {
        ti = ti + 1
      }
      // both polarities
      for pol = 0; pol < 2; pol = pol + 1 {
        let polarity = if pol == 0 { 1 } else { -1 }
        let s = { feature: f, threshold: thresh, polarity }
        let mut err = 0.0
        for i = 0; i < n; i = i + 1 {
          if stump_predict(s, x[i]) != y[i] {
            err = err + w[i]
          }
        }
        if err < best_err {
          best_err = err
          best = s
        }
      }
      ti = ti + 1
    }
  }
  // Clamp ε into the open interval (0, 1) so α stays finite and non-zero.
  let e = if best_err < 1.0e-12 {
    1.0e-12
  } else if best_err > 1.0 - 1.0e-12 {
    1.0 - 1.0e-12
  } else {
    best_err
  }
  (best, e)
}

// ---------------------------------------------------------------------------
// Public model
// ---------------------------------------------------------------------------

///|
/// AdaBoost.M1 ensemble of decision stumps. Train with `fit` (labels ±1),
/// predict with `predict` (±1).
pub struct AdaBoost {
  priv mut stumps : Array[Stump]
  priv mut alphas : Array[Double]
  priv n_estimators : Int
  priv mut n_features : Int
}

///|
/// Create an AdaBoost model.
///
/// - `n_estimators`: maximum number of stumps (typical: 50). `<= 0` → 50.
pub fn new(n_estimators : Int) -> AdaBoost {
  {
    stumps: [],
    alphas: [],
    n_estimators: if n_estimators > 0 { n_estimators } else { 50 },
    n_features: 0,
  }
}

///|
/// Train the ensemble. `y` must use labels `+1` / `−1`.
pub fn fit(ab : AdaBoost, x : Array[Array[Double]], y : Array[Int]) -> Unit {
  let n = x.length()
  if n == 0 || y.length() != n {
    return
  }
  let n_features = x[0].length()
  ab.n_features = n_features
  ab.stumps = []
  ab.alphas = []
  let w = Array::make(n, 1.0 / n.to_double())
  for _t = 0; _t < ab.n_estimators; _t = _t + 1 {
    let (s, err) = best_stump(x, y, w, n_features)
    // Stop if the best learner is no better than chance.
    if err >= 0.5 {
      break
    }
    let alpha = 0.5 * ln_double((1.0 - err) / err)
    // Reweight: correct → exp(-α) shrinks, wrong → exp(+α) grows.
    let mut z = 0.0
    for i = 0; i < n; i = i + 1 {
      let correct = stump_predict(s, x[i]) == y[i]
      let factor = if correct {
        exp_double(-alpha)
      } else {
        exp_double(alpha)
      }
      w[i] = w[i] * factor
      z = z + w[i]
    }
    // Renormalise.
    if z > 0.0 {
      for i = 0; i < n; i = i + 1 {
        w[i] = w[i] / z
      }
    }
    ab.stumps.push(s)
    ab.alphas.push(alpha)
  }
}

///|
/// Raw weighted vote `Σ_t α_t h_t(x)`. Positive ⇒ class +1.
pub fn decision_score(ab : AdaBoost, x : Array[Double]) -> Double {
  let mut s = 0.0
  for t = 0; t < ab.stumps.length(); t = t + 1 {
    s = s + ab.alphas[t] * stump_predict(ab.stumps[t], x).to_double()
  }
  s
}

///|
/// Predict the class label (+1 or −1). Returns +1 on a tie.
pub fn predict(ab : AdaBoost, x : Array[Double]) -> Int {
  if decision_score(ab, x) >= 0.0 {
    1
  } else {
    -1
  }
}

///|
/// Number of stumps in the ensemble.
pub fn num_stumps(ab : AdaBoost) -> Int {
  ab.stumps.length()
}

///|
/// Number of input features the ensemble was trained on (0 before fitting).
pub fn n_features(ab : AdaBoost) -> Int {
  ab.n_features
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "adaboost: linearly separable 1-D threshold" {
  let ab = new(10)
  let x = [[1.0], [2.0], [3.0], [4.0], [5.0], [6.0]]
  let y = [-1, -1, -1, 1, 1, 1]
  fit(ab, x, y)
  assert_eq(predict(ab, [1.0]), -1)
  assert_eq(predict(ab, [2.5]), -1)
  assert_eq(predict(ab, [4.0]), 1)
  assert_eq(predict(ab, [6.0]), 1)
}

///|
test "adaboost: 2-D linearly separable clusters" {
  let ab = new(20)
  let x : Array[Array[Double]] = [
    [1.0, 1.0], [1.5, 0.5], [0.5, 1.5], [2.0, 1.0],
    [6.0, 6.0], [6.5, 5.5], [5.5, 6.5], [7.0, 6.0],
  ]
  let y = [-1, -1, -1, -1, 1, 1, 1, 1]
  fit(ab, x, y)
  assert_eq(predict(ab, [1.0, 1.0]), -1)
  assert_eq(predict(ab, [6.0, 6.0]), 1)
  assert_eq(predict(ab, [7.0, 7.0]), 1)
}

///|
test "adaboost: nonlinearly separable alternating pattern" {
  // A single stump cannot fit an alternating label sequence, but a small
  // ensemble of stumps can.
  let ab = new(30)
  let x = [[1.0], [2.0], [3.0], [4.0], [5.0], [6.0]]
  let y = [-1, 1, -1, 1, -1, 1]
  fit(ab, x, y)
  // Training accuracy should be perfect after boosting.
  let mut correct = 0
  for i = 0; i < 6; i = i + 1 {
    if predict(ab, x[i]) == y[i] {
      correct = correct + 1
    }
  }
  assert_eq(correct, 6)
}

///|
test "adaboost: weighted vote reduces training error monotonically-ish" {
  // With more estimators the ensemble should fit the data at least as well.
  let x = [[1.0], [2.0], [3.0], [4.0], [5.0], [6.0], [7.0], [8.0]]
  let y = [-1, 1, -1, 1, -1, 1, -1, 1]
  let ab = new(40)
  fit(ab, x, y)
  let mut correct = 0
  for i = 0; i < 8; i = i + 1 {
    if predict(ab, x[i]) == y[i] {
      correct = correct + 1
    }
  }
  assert_true(correct >= 7)
}

///|
test "adaboost: decision score sign is consistent with predict" {
  let ab = new(15)
  let x = [[1.0], [2.0], [3.0], [4.0]]
  let y = [-1, -1, 1, 1]
  fit(ab, x, y)
  for i = 0; i < 4; i = i + 1 {
    let s = decision_score(ab, x[i])
    let p = predict(ab, x[i])
    if s >= 0.0 {
      assert_eq(p, 1)
    } else {
      assert_eq(p, -1)
    }
  }
}

///|
test "adaboost: empty input is a no-op" {
  let ab = new(10)
  fit(ab, [], [])
  assert_eq(num_stumps(ab), 0)
  // No stumps → score 0 → predict returns +1.
  assert_eq(predict(ab, [1.0]), 1)
}

///|
test "adaboost: local exp/ln are accurate" {
  assert_true((exp_double(0.0) - 1.0).abs() < 1.0e-12)
  assert_true((exp_double(1.0) - 2.718281828459045).abs() < 1.0e-12)
  assert_true((ln_double(2.718281828459045) - 1.0).abs() < 1.0e-12)
  assert_true(ln_double(1.0).abs() < 1.0e-12)
}
