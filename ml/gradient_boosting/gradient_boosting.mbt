/// Gradient Boosting — stage-wise additive modelling with regression trees.
///
/// Builds an ensemble `F(x) = F_0 + Σ_t η · h_t(x)` where each weak learner
/// `h_t` is a shallow regression tree fitted to the *negative gradient* of the
/// loss at the current prediction, and `η` is the learning rate (shrinkage).
/// Shrinkage slows learning so each tree corrects only a fraction of the
/// residual, which generalises far better than full-step fitting.
///
/// ## Losses
/// - **Squared loss** (regression): `L = ½(y − F)²`, negative gradient
///   `y − F`. Initial value `F_0 = mean(y)`.
/// - **Logistic loss** (binary classification, labels ∈ {0,1}): the model
///   outputs the log-odds `F`; `P(y=1|x) = σ(F)`. The negative gradient is
///   `y − σ(F)`. Initial value `F_0 = logit(mean(y))`.
///
/// ## Complexity
/// - Training: `O(n_estimators × n × d × depth)`.
/// - Prediction: `O(n_estimators × depth)` per row.
///
/// No external dependency: every primitive (regression tree, `exp`, `ln`) is
/// implemented locally.
///
/// Not formally verified. Correctness is ensured by the test suite.

// ---------------------------------------------------------------------------
// Local transcendentals (no @math import required)
// ---------------------------------------------------------------------------

///|
/// Natural exponential via argument halving + Taylor series.
/// `exp(x) = exp(x/2)²`; halve until `|r| ≤ ½`, evaluate the rapidly
/// convergent Taylor series, then square back. Accurate to ~1e-15.
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
  // Taylor series for exp(r), |r| <= 0.5.
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
  // square n times
  let mut result = sum
  for _i = 0; _i < n; _i = _i + 1 {
    result = result * result
  }
  result
}

///|
/// Natural logarithm via range reduction + atanh series.
/// `ln(x) = k·ln2 + ln(m)` with `m ∈ [1,2)`; `ln(m) = 2·atanh((m−1)/(m+1))`
/// expanded as `2·Σ z^(2i+1)/(2i+1)`, `z = (m−1)/(m+1) ∈ [0,⅓)`. Accurate to
/// ~1e-15. Returns a large negative number for `x ≤ 0`.
fn ln_double(x : Double) -> Double {
  if x <= 0.0 {
    return -700.0
  }
  // Reduce to m in [1, 2) by repeated halving/doubling.
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

///|
/// Logistic sigmoid, clamped against overflow.
fn sigmoid(z : Double) -> Double {
  if z >= 35.0 {
    1.0
  } else if z <= -35.0 {
    0.0
  } else {
    1.0 / (1.0 + exp_double(-z))
  }
}

///|
/// Logit p → log(p/(1−p)), with `p` clamped into the open interval (0,1).
fn logit(p : Double) -> Double {
  let q = if p <= 0.0 { 1.0e-10 } else if p >= 1.0 { 1.0 - 1.0e-10 } else { p }
  ln_double(q / (1.0 - q))
}

// ---------------------------------------------------------------------------
// Regression tree (weak learner)
// ---------------------------------------------------------------------------

///|
/// A regression-tree node. Leaves predict `value`; internal nodes test
/// `feature <= threshold`.
priv struct GbNode {
  is_leaf : Bool
  value : Double
  feature : Int
  threshold : Double
  left : GbNode?
  right : GbNode?
}

///|
fn leaf(value : Double) -> GbNode {
  { is_leaf: true, value, feature: -1, threshold: 0.0, left: None, right: None }
}

///|
fn mean_d(values : Array[Double]) -> Double {
  let n = values.length()
  if n == 0 {
    return 0.0
  }
  let mut s = 0.0
  for v in values {
    s = s + v
  }
  s / n.to_double()
}

///|
fn variance_d(values : Array[Double]) -> Double {
  let n = values.length()
  if n == 0 {
    return 0.0
  }
  let m = mean_d(values)
  let mut s = 0.0
  for v in values {
    let d = v - m
    s = s + d * d
  }
  s / n.to_double()
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
/// Best variance-reduction split over all features. Returns
/// `(feature, threshold)` or `None`.
fn best_split(
  x : Array[Array[Double]],
  y : Array[Double],
  n_features : Int,
) -> (Int, Double)? {
  let n = x.length()
  let parent_var = variance_d(y)
  let mut best_gain = -1.0
  let mut best_feat = -1
  let mut best_thresh = 0.0
  for f = 0; f < n_features; f = f + 1 {
    let values : Array[Double] = []
    for i = 0; i < n; i = i + 1 {
      values.push(x[i][f])
    }
    values.sort_by(cmp_double)
    for i = 1; i < n; i = i + 1 {
      if values[i] == values[i - 1] {
        continue
      }
      let thresh = (values[i] + values[i - 1]) / 2.0
      let left_y : Array[Double] = []
      let right_y : Array[Double] = []
      for j = 0; j < n; j = j + 1 {
        if x[j][f] <= thresh {
          left_y.push(y[j])
        } else {
          right_y.push(y[j])
        }
      }
      let nl = left_y.length()
      let nr = right_y.length()
      if nl == 0 || nr == 0 {
        continue
      }
      let child = (
          nl.to_double() * variance_d(left_y) +
          nr.to_double() * variance_d(right_y)
        ) /
        n.to_double()
      let gain = parent_var - child
      if gain > best_gain {
        best_gain = gain
        best_feat = f
        best_thresh = thresh
      }
    }
  }
  if best_feat < 0 {
    None
  } else {
    Some((best_feat, best_thresh))
  }
}

///|
/// Recursively grow a depth-limited regression tree.
fn build_tree(
  x : Array[Array[Double]],
  y : Array[Double],
  n_features : Int,
  depth : Int,
  max_depth : Int,
  min_split : Int,
) -> GbNode {
  let n = x.length()
  if variance_d(y) == 0.0 || depth >= max_depth || n < min_split {
    return leaf(mean_d(y))
  }
  match best_split(x, y, n_features) {
    None => leaf(mean_d(y))
    Some((feat, thresh)) => {
      let left_x : Array[Array[Double]] = []
      let left_y : Array[Double] = []
      let right_x : Array[Array[Double]] = []
      let right_y : Array[Double] = []
      for i = 0; i < n; i = i + 1 {
        if x[i][feat] <= thresh {
          left_x.push(x[i])
          left_y.push(y[i])
        } else {
          right_x.push(x[i])
          right_y.push(y[i])
        }
      }
      if left_y.length() == 0 || right_y.length() == 0 {
        return leaf(mean_d(y))
      }
      {
        is_leaf: false,
        value: 0.0,
        feature: feat,
        threshold: thresh,
        left: Some(
          build_tree(
            left_x,
            left_y,
            n_features,
            depth + 1,
            max_depth,
            min_split,
          ),
        ),
        right: Some(
          build_tree(
            right_x,
            right_y,
            n_features,
            depth + 1,
            max_depth,
            min_split,
          ),
        ),
      }
    }
  }
}

///|
/// Predict one row with a regression tree.
fn predict_tree(node : GbNode, x : Array[Double]) -> Double {
  if node.is_leaf {
    return node.value
  }
  if x[node.feature] <= node.threshold {
    match node.left {
      None => node.value
      Some(l) => predict_tree(l, x)
    }
  } else {
    match node.right {
      None => node.value
      Some(r) => predict_tree(r, x)
    }
  }
}

// ---------------------------------------------------------------------------
// Public model
// ---------------------------------------------------------------------------

///|
/// Gradient-boosting model. Train with `fit` (regression) or
/// `fit_classifier` (binary classification); predict with `predict_regress`
/// or `predict_proba` / `predict`.
pub struct GradientBoosting {
  priv mut trees : Array[GbNode?]
  priv mut init_pred : Double
  priv learning_rate : Double
  priv n_estimators : Int
  priv max_depth : Int
  priv min_samples_split : Int
  priv mut is_classifier : Bool
  priv mut n_features : Int
}

///|
/// Create a gradient-boosting **regressor** (squared loss).
///
/// - `learning_rate`: shrinkage η (typical: 0.1). `<= 0` → 0.1.
/// - `n_estimators`: number of boosting rounds (typical: 100).
/// - `max_depth`: weak-learner depth (typical: 3).
/// - `min_samples_split`: min rows to split a node. `< 2` → 2.
pub fn new(
  learning_rate : Double,
  n_estimators : Int,
  max_depth : Int,
  min_samples_split : Int,
) -> GradientBoosting {
  {
    trees: [],
    init_pred: 0.0,
    learning_rate: if learning_rate > 0.0 {
      learning_rate
    } else {
      0.1
    },
    n_estimators: if n_estimators > 0 {
      n_estimators
    } else {
      100
    },
    max_depth: if max_depth > 0 {
      max_depth
    } else {
      3
    },
    min_samples_split: if min_samples_split > 1 {
      min_samples_split
    } else {
      2
    },
    is_classifier: false,
    n_features: 0,
  }
}

///|
/// Create a gradient-boosting **binary classifier** (logistic loss).
/// Parameters mirror `new`.
pub fn new_classifier(
  learning_rate : Double,
  n_estimators : Int,
  max_depth : Int,
  min_samples_split : Int,
) -> GradientBoosting {
  let m = new(learning_rate, n_estimators, max_depth, min_samples_split)
  m.is_classifier = true
  m
}

///|
/// Train a regression model (squared loss).
pub fn fit(
  gb : GradientBoosting,
  x : Array[Array[Double]],
  y : Array[Double],
) -> Unit {
  let n = x.length()
  if n == 0 || y.length() != n {
    return
  }
  let n_features = x[0].length()
  gb.n_features = n_features
  gb.is_classifier = false
  gb.trees = []
  let init = mean_d(y)
  gb.init_pred = init
  // current predictions
  let pred = Array::make(n, init)
  for _t = 0; _t < gb.n_estimators; _t = _t + 1 {
    // negative gradient of ½(y−F)² is (y − F)
    let residual : Array[Double] = Array::make(n, 0.0)
    for i = 0; i < n; i = i + 1 {
      residual[i] = y[i] - pred[i]
    }
    let tree = build_tree(
      x,
      residual,
      n_features,
      0,
      gb.max_depth,
      gb.min_samples_split,
    )
    for i = 0; i < n; i = i + 1 {
      pred[i] = pred[i] + gb.learning_rate * predict_tree(tree, x[i])
    }
    gb.trees.push(Some(tree))
  }
}

///|
/// Train a binary classifier (logistic loss). Labels must be 0 or 1.
pub fn fit_classifier(
  gb : GradientBoosting,
  x : Array[Array[Double]],
  y : Array[Int],
) -> Unit {
  let n = x.length()
  if n == 0 || y.length() != n {
    return
  }
  let n_features = x[0].length()
  gb.n_features = n_features
  gb.is_classifier = true
  gb.trees = []
  // initial log-odds from class prior
  let mut pos = 0
  for v in y {
    if v != 0 {
      pos = pos + 1
    }
  }
  let p = pos.to_double() / n.to_double()
  let init = logit(p)
  gb.init_pred = init
  let pred = Array::make(n, init)
  for _t = 0; _t < gb.n_estimators; _t = _t + 1 {
    // negative gradient of logistic loss is (y − σ(F))
    let residual : Array[Double] = Array::make(n, 0.0)
    for i = 0; i < n; i = i + 1 {
      residual[i] = y[i].to_double() - sigmoid(pred[i])
    }
    let tree = build_tree(
      x,
      residual,
      n_features,
      0,
      gb.max_depth,
      gb.min_samples_split,
    )
    for i = 0; i < n; i = i + 1 {
      pred[i] = pred[i] + gb.learning_rate * predict_tree(tree, x[i])
    }
    gb.trees.push(Some(tree))
  }
}

///|
/// Raw additive model output `F(x)` = init + Σ η·h_t(x).
fn raw_score(gb : GradientBoosting, x : Array[Double]) -> Double {
  let mut s = gb.init_pred
  for t = 0; t < gb.trees.length(); t = t + 1 {
    match gb.trees[t] {
      None => ()
      Some(r) => s = s + gb.learning_rate * predict_tree(r, x)
    }
  }
  s
}

///|
/// Regression prediction.
pub fn predict_regress(gb : GradientBoosting, x : Array[Double]) -> Double {
  raw_score(gb, x)
}

///|
/// Classification probability `P(y=1|x) = σ(F(x))`.
pub fn predict_proba(gb : GradientBoosting, x : Array[Double]) -> Double {
  sigmoid(raw_score(gb, x))
}

///|
/// Classification label (0 or 1) at threshold 0.5.
pub fn predict(gb : GradientBoosting, x : Array[Double]) -> Int {
  if predict_proba(gb, x) >= 0.5 {
    1
  } else {
    0
  }
}

///|
/// Number of boosting rounds actually performed.
pub fn n_estimators_(gb : GradientBoosting) -> Int {
  gb.trees.length()
}

///|
/// Whether the model was trained as a classifier (`true`) or regressor
/// (`false`).
pub fn is_classifier(gb : GradientBoosting) -> Bool {
  gb.is_classifier
}

///|
/// Number of input features the model was trained on (0 before fitting).
pub fn n_features(gb : GradientBoosting) -> Int {
  gb.n_features
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "gradient_boosting: regression fits a linear trend" {
  let gb = new(0.3, 50, 3, 2)
  let x : Array[Array[Double]] = []
  let y : Array[Double] = []
  for i = 0; i < 10; i = i + 1 {
    x.push([i.to_double()])
    y.push(i.to_double() * 2.0 + 1.0)
  }
  fit(gb, x, y)
  let p0 = predict_regress(gb, [0.0])
  let p9 = predict_regress(gb, [9.0])
  // Predictions track the training values closely.
  assert_true((p0 - 1.0).abs() < 2.0)
  assert_true((p9 - 19.0).abs() < 2.0)
  assert_true(p0 < p9)
}

///|
test "gradient_boosting: regression reduces error with more rounds" {
  let mk = fn(rounds : Int) -> Double {
    let gb = new(0.5, rounds, 3, 2)
    let x = [[0.0], [1.0], [2.0], [3.0], [4.0]]
    let y = [1.0, 3.0, 5.0, 7.0, 9.0]
    fit(gb, x, y)
    let mut mse = 0.0
    for i = 0; i < 5; i = i + 1 {
      let d = predict_regress(gb, x[i]) - y[i]
      mse = mse + d * d
    }
    mse / 5.0
  }
  let few = mk(2)
  let many = mk(80)
  // More rounds → lower training MSE.
  assert_true(many < few)
  assert_true(many < 1.0)
}

///|
test "gradient_boosting: binary classification on threshold" {
  let gb = new_classifier(0.5, 50, 3, 2)
  let x : Array[Array[Double]] = []
  let y : Array[Int] = []
  for i = 0; i < 6; i = i + 1 {
    x.push([i.to_double()])
    y.push(if i < 3 { 0 } else { 1 })
  }
  fit_classifier(gb, x, y)
  assert_eq(predict(gb, [0.0]), 0)
  assert_eq(predict(gb, [1.0]), 0)
  assert_eq(predict(gb, [4.0]), 1)
  assert_eq(predict(gb, [5.0]), 1)
}

///|
test "gradient_boosting: probability is in [0,1]" {
  let gb = new_classifier(0.3, 30, 3, 2)
  let x = [[0.0], [1.0], [2.0], [3.0]]
  let y = [0, 0, 1, 1]
  fit_classifier(gb, x, y)
  let p = predict_proba(gb, [1.5])
  assert_true(p >= 0.0 && p <= 1.0)
}

///|
test "gradient_boosting: 2-D linearly separable classification" {
  let gb = new_classifier(0.5, 60, 3, 2)
  let x : Array[Array[Double]] = [
    [1.0, 1.0],
    [2.0, 1.0],
    [1.0, 2.0],
    [2.0, 2.0],
    [6.0, 6.0],
    [7.0, 6.0],
    [6.0, 7.0],
    [7.0, 7.0],
  ]
  let y = [0, 0, 0, 0, 1, 1, 1, 1]
  fit_classifier(gb, x, y)
  assert_eq(predict(gb, [1.0, 1.0]), 0)
  assert_eq(predict(gb, [7.0, 7.0]), 1)
  assert_eq(predict(gb, [6.0, 6.0]), 1)
}

///|
test "gradient_boosting: empty input is a no-op" {
  let gb = new(0.1, 10, 3, 2)
  fit(gb, [], [])
  assert_eq(n_estimators_(gb), 0)
  assert_true(predict_regress(gb, [1.0]) == 0.0)
}

///|
test "gradient_boosting: local exp/ln are accurate" {
  // exp(0) = 1, exp(1) ≈ e, ln(e) = 1, ln(1) = 0
  assert_true((exp_double(0.0) - 1.0).abs() < 1.0e-12)
  assert_true((exp_double(1.0) - 2.718281828459045).abs() < 1.0e-12)
  assert_true((ln_double(2.718281828459045) - 1.0).abs() < 1.0e-12)
  assert_true(ln_double(1.0).abs() < 1.0e-12)
  // round-trip
  let v = 3.7
  assert_true((ln_double(exp_double(v)) - v).abs() < 1.0e-12)
  assert_true((exp_double(ln_double(v)) - v).abs() < 1.0e-12)
}
