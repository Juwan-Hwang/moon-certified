/// Random Forest — bootstrap-aggregated (bagged) decision-tree ensemble.
///
/// Trains an ensemble of CART decision trees. Each tree is grown on a
/// *bootstrap sample* (sampling *n* rows with replacement) and, at every
/// split, considers only a random subset of `max_features` features. This
/// double injection of randomness decorrelates the trees so that averaging
/// their predictions sharply reduces variance compared with a single tree.
///
/// ## Algorithm
/// 1. **Bootstrap** — for tree *t*, draw *n* indices with replacement.
/// 2. **Random subspace** — at each node pick `max_features` features at
///    random and search only those for the best split. The default
///    `max_features` is ⌊√d⌋ for classification and ⌊d/3⌋ for regression
///    (Breiman's recommendations).
/// 3. **Grow** a depth-limited CART on the bootstrap sample.
/// 4. **Aggregate** — majority vote (classification) / arithmetic mean
///    (regression).
///
/// The rows *not* drawn into a tree's bootstrap set are its *out-of-bag*
/// (OOB) examples. Every tree votes on its own OOB rows, giving an unbiased
/// internal error estimate (the OOB error) without holding out data.
///
/// ## Complexity
/// - Training: `O(n_trees × n × d × depth)`.
/// - Prediction: `O(n_trees × depth)` per row.
///
/// Not formally verified. Correctness is ensured by the test suite.

// ---------------------------------------------------------------------------
// Deterministic PRNG — a 31-bit LCG (same family used across moon-certified).
// Keeping the generator local avoids any cross-package dependency and makes
// training fully reproducible from a single seed.
// ---------------------------------------------------------------------------

///|
priv struct Rng {
  mut state : Int
}

fn Rng::new(seed : Int) -> Rng {
  let s = seed & 0x7FFFFFFF
  { state: if s == 0 { 1 } else { s } }
}

/// Advance the generator and return a non-negative Int in [0, 2^31).
fn Rng::next(self : Rng) -> Int {
  self.state = (self.state * 1103515245 + 12345) & 0x7FFFFFFF
  self.state
}

/// Uniform Double in [0, 1). Uses the full 31-bit state, so the high bits
/// (which are well-mixed in an LCG) drive the value.
fn Rng::next_double(self : Rng) -> Double {
  self.next().to_double() / 2147483648.0
}

/// Uniform Int in [0, bound). Derived from `next_double` so the well-mixed
/// high bits — not the weak, short-period low bits — determine the result.
/// (LCG low bits cycle with tiny periods: e.g. `state mod 8` has period 8,
/// which would make every size-8 bootstrap a permutation of 0..7.)
fn Rng::next_int(self : Rng, bound : Int) -> Int {
  if bound <= 0 {
    0
  } else {
    let v = (self.next_double() * bound.to_double()).to_int()
    if v >= bound {
      bound - 1
    } else {
      v
    }
  }
}

// ---------------------------------------------------------------------------
// Tree node
// ---------------------------------------------------------------------------

///|
/// A CART node. Leaves carry either a class `label` (classification) or a
/// continuous `value` (regression); internal nodes carry a split test
/// `feature <= threshold` and two children.
priv struct Node {
  is_leaf : Bool
  label : Int // classification leaf: predicted class
  value : Double // regression leaf: predicted value
  feature : Int // internal: split feature index
  threshold : Double // internal: split threshold
  left : Node? // <= threshold
  right : Node? // >  threshold
}

fn leaf_cls(y : Array[Int]) -> Node {
  {
    is_leaf: true,
    label: majority(y),
    value: 0.0,
    feature: -1,
    threshold: 0.0,
    left: None,
    right: None,
  }
}

fn leaf_reg(y : Array[Double]) -> Node {
  {
    is_leaf: true,
    label: -1,
    value: mean(y),
    feature: -1,
    threshold: 0.0,
    left: None,
    right: None,
  }
}

// ---------------------------------------------------------------------------
// Statistics helpers
// ---------------------------------------------------------------------------

///|
/// Majority class of a label array (ties broken by first-seen order).
fn majority(labels : Array[Int]) -> Int {
  let counts : Map[Int, Int] = Map([])
  for l in labels {
    counts[l] = counts.get(l).unwrap_or(0) + 1
  }
  let mut best_label = 0
  let mut best_count = -1
  for kv in counts {
    let (label, count) = kv
    if count > best_count {
      best_count = count
      best_label = label
    }
  }
  best_label
}

///|
/// Gini impurity of a label array.
fn gini(labels : Array[Int]) -> Double {
  let n = labels.length()
  if n == 0 {
    return 0.0
  }
  let counts : Map[Int, Int] = Map([])
  for l in labels {
    counts[l] = counts.get(l).unwrap_or(0) + 1
  }
  let mut imp = 1.0
  for v in counts.values() {
    let p = v.to_double() / n.to_double()
    imp = imp - p * p
  }
  imp
}

///|
/// Arithmetic mean of a Double array.
fn mean(values : Array[Double]) -> Double {
  let n = values.length()
  if n == 0 {
    return 0.0
  }
  let mut sum = 0.0
  for v in values {
    sum = sum + v
  }
  sum / n.to_double()
}

///|
/// Population variance of a Double array.
fn variance(values : Array[Double]) -> Double {
  let n = values.length()
  if n == 0 {
    return 0.0
  }
  let m = mean(values)
  let mut sum_sq = 0.0
  for v in values {
    let d = v - m
    sum_sq = sum_sq + d * d
  }
  sum_sq / n.to_double()
}

///|
/// Comparator lifting a Double ordering to the sort_by convention.
fn cmp_double(a : Double, b : Double) -> Int {
  if a < b {
    -1
  } else if a > b {
    1
  } else {
    0
  }
}

// ---------------------------------------------------------------------------
// Random feature subset (partial Fisher–Yates)
// ---------------------------------------------------------------------------

///|
/// Pick `k` distinct indices from `[0, n_features)` without allocation of a
/// full shuffled copy beyond what is needed: a partial Fisher–Yates shuffle
/// moves `k` randomly chosen positions to the front.
fn random_subset(rng : Rng, n_features : Int, k : Int) -> Array[Int] {
  let kk = if k > n_features {
    n_features
  } else if k < 1 {
    1
  } else {
    k
  }
  let indices = Array::makei(n_features, fn(i) { i })
  for i = 0; i < kk; i = i + 1 {
    let j = i + rng.next_int(n_features - i)
    let tmp = indices[i]
    indices[i] = indices[j]
    indices[j] = tmp
  }
  let result = Array::make(kk, 0)
  for i = 0; i < kk; i = i + 1 {
    result[i] = indices[i]
  }
  result
}

// ---------------------------------------------------------------------------
// Split search (restricted to a candidate feature subset)
// ---------------------------------------------------------------------------

///|
/// Best Gini-gain split over `candidates` (a subset of feature indices).
/// Returns `(feature, threshold)` or `None` if no split helps.
fn best_split_cls(
  x : Array[Array[Double]],
  y : Array[Int],
  candidates : Array[Int],
) -> (Int, Double)? {
  let n = x.length()
  let parent_gini = gini(y)
  let mut best_gain = -1.0
  let mut best_feat = -1
  let mut best_thresh = 0.0
  for ci = 0; ci < candidates.length(); ci = ci + 1 {
    let f = candidates[ci]
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
      let left_labels : Array[Int] = []
      let right_labels : Array[Int] = []
      for j = 0; j < n; j = j + 1 {
        if x[j][f] <= thresh {
          left_labels.push(y[j])
        } else {
          right_labels.push(y[j])
        }
      }
      let nl = left_labels.length()
      let nr = right_labels.length()
      if nl == 0 || nr == 0 {
        continue
      }
      let child = (
        nl.to_double() * gini(left_labels) + nr.to_double() * gini(right_labels)
      ) /
        n.to_double()
      let gain = parent_gini - child
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
/// Best variance-reduction split over `candidates`.
fn best_split_reg(
  x : Array[Array[Double]],
  y : Array[Double],
  candidates : Array[Int],
) -> (Int, Double)? {
  let n = x.length()
  let parent_var = variance(y)
  let mut best_gain = -1.0
  let mut best_feat = -1
  let mut best_thresh = 0.0
  for ci = 0; ci < candidates.length(); ci = ci + 1 {
    let f = candidates[ci]
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
        nl.to_double() * variance(left_y) + nr.to_double() * variance(right_y)
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

// ---------------------------------------------------------------------------
// Tree construction
// ---------------------------------------------------------------------------

///|
/// Recursively grow a classification tree with per-node random subspaces.
fn build_cls(
  x : Array[Array[Double]],
  y : Array[Int],
  n_features : Int,
  max_features : Int,
  depth : Int,
  max_depth : Int,
  min_split : Int,
  rng : Rng,
) -> Node {
  let n = x.length()
  if gini(y) == 0.0 || depth >= max_depth || n < min_split {
    return leaf_cls(y)
  }
  let candidates = random_subset(rng, n_features, max_features)
  match best_split_cls(x, y, candidates) {
    None => leaf_cls(y)
    Some((feat, thresh)) => {
      let left_x : Array[Array[Double]] = []
      let left_y : Array[Int] = []
      let right_x : Array[Array[Double]] = []
      let right_y : Array[Int] = []
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
        return leaf_cls(y)
      }
      {
        is_leaf: false,
        label: -1,
        value: 0.0,
        feature: feat,
        threshold: thresh,
        left: Some(
          build_cls(
            left_x,
            left_y,
            n_features,
            max_features,
            depth + 1,
            max_depth,
            min_split,
            rng,
          ),
        ),
        right: Some(
          build_cls(
            right_x,
            right_y,
            n_features,
            max_features,
            depth + 1,
            max_depth,
            min_split,
            rng,
          ),
        ),
      }
    }
  }
}

///|
/// Recursively grow a regression tree with per-node random subspaces.
fn build_reg(
  x : Array[Array[Double]],
  y : Array[Double],
  n_features : Int,
  max_features : Int,
  depth : Int,
  max_depth : Int,
  min_split : Int,
  rng : Rng,
) -> Node {
  let n = x.length()
  if variance(y) == 0.0 || depth >= max_depth || n < min_split {
    return leaf_reg(y)
  }
  let candidates = random_subset(rng, n_features, max_features)
  match best_split_reg(x, y, candidates) {
    None => leaf_reg(y)
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
        return leaf_reg(y)
      }
      {
        is_leaf: false,
        label: -1,
        value: 0.0,
        feature: feat,
        threshold: thresh,
        left: Some(
          build_reg(
            left_x,
            left_y,
            n_features,
            max_features,
            depth + 1,
            max_depth,
            min_split,
            rng,
          ),
        ),
        right: Some(
          build_reg(
            right_x,
            right_y,
            n_features,
            max_features,
            depth + 1,
            max_depth,
            min_split,
            rng,
          ),
        ),
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Prediction (single tree)
// ---------------------------------------------------------------------------

///|
/// Classify one row by walking a tree.
fn predict_node(node : Node, x : Array[Double]) -> Int {
  if node.is_leaf {
    return node.label
  }
  if x[node.feature] <= node.threshold {
    match node.left {
      None => node.label
      Some(l) => predict_node(l, x)
    }
  } else {
    match node.right {
      None => node.label
      Some(r) => predict_node(r, x)
    }
  }
}

///|
/// Regress one row by walking a tree.
fn predict_node_reg(node : Node, x : Array[Double]) -> Double {
  if node.is_leaf {
    return node.value
  }
  if x[node.feature] <= node.threshold {
    match node.left {
      None => node.value
      Some(l) => predict_node_reg(l, x)
    }
  } else {
    match node.right {
      None => node.value
      Some(r) => predict_node_reg(r, x)
    }
  }
}

// ---------------------------------------------------------------------------
// Public model
// ---------------------------------------------------------------------------

///|
/// Random forest classifier / regressor.
///
/// Create with `new_classifier` or `new_regressor`, then call `fit` /
/// `fit_regress`. Use `set_seed` before fitting for reproducibility control.
pub struct RandomForest {
  priv mut trees : Array[Node?]
  priv n_trees : Int
  priv max_depth : Int
  priv min_samples_split : Int
  priv max_features : Int
  priv mut is_regressor : Bool
  priv mut n_features : Int
  priv mut oob_err : Double
  priv mut seed : Int
}

///|
/// Number of features considered at each split. `<= 0` selects the Breiman
/// default: ⌊√d⌋ for classification, ⌊d/3⌋ for regression (clamped to ≥ 1).
fn effective_max_features(
  requested : Int,
  n_features : Int,
  is_regressor : Bool,
) -> Int {
  let mf = if requested > 0 {
    requested
  } else if is_regressor {
    n_features / 3
  } else {
    n_features.to_double().sqrt().to_int()
  }
  if mf < 1 {
    1
  } else if mf > n_features {
    n_features
  } else {
    mf
  }
}

///|
/// Create a random-forest **classifier**.
///
/// - `n_trees`: number of trees (typical: 100). `<= 0` → 100.
/// - `max_depth`: max tree depth (typical: 10). `<= 0` → 10.
/// - `min_samples_split`: min rows to split a node. `< 2` → 2.
/// - `max_features`: features per split. `<= 0` → ⌊√d⌋.
pub fn new_classifier(
  n_trees : Int,
  max_depth : Int,
  min_samples_split : Int,
  max_features : Int,
) -> RandomForest {
  {
    trees: [],
    n_trees: if n_trees > 0 { n_trees } else { 100 },
    max_depth: if max_depth > 0 { max_depth } else { 10 },
    min_samples_split: if min_samples_split > 1 { min_samples_split } else { 2 },
    max_features,
    is_regressor: false,
    n_features: 0,
    oob_err: 1.0,
    seed: 0x1A2B3C4D,
  }
}

///|
/// Create a random-forest **regressor**.
///
/// Parameters mirror `new_classifier`; `max_features <= 0` → ⌊d/3⌋.
pub fn new_regressor(
  n_trees : Int,
  max_depth : Int,
  min_samples_split : Int,
  max_features : Int,
) -> RandomForest {
  {
    trees: [],
    n_trees: if n_trees > 0 { n_trees } else { 100 },
    max_depth: if max_depth > 0 { max_depth } else { 10 },
    min_samples_split: if min_samples_split > 1 { min_samples_split } else { 2 },
    max_features,
    is_regressor: true,
    n_features: 0,
    oob_err: -1.0,
    seed: 0x1A2B3C4D,
  }
}

///|
/// Set the PRNG seed (call before `fit` / `fit_regress`). Makes a run fully
/// reproducible.
pub fn set_seed(rf : RandomForest, seed : Int) -> Unit {
  rf.seed = seed
}

///|
/// Train a classification forest. Each tree is grown on a bootstrap sample;
/// OOB rows are voted on to produce the OOB error estimate.
pub fn fit(rf : RandomForest, x : Array[Array[Double]], y : Array[Int]) -> Unit {
  let n = x.length()
  if n == 0 || y.length() != n {
    return
  }
  let n_features = x[0].length()
  rf.n_features = n_features
  rf.is_regressor = false
  let mf = effective_max_features(rf.max_features, n_features, false)
  let rng = Rng::new(rf.seed)
  rf.trees = []
  // Per-row OOB vote tallies.
  let votes : Array[Map[Int, Int]] = Array::makei(n, fn(_i) { Map([]) })
  let has_oob : Array[Bool] = Array::make(n, false)
  for _t = 0; _t < rf.n_trees; _t = _t + 1 {
    let sample_x : Array[Array[Double]] = []
    let sample_y : Array[Int] = []
    let in_bag : Array[Bool] = Array::make(n, false)
    for i = 0; i < n; i = i + 1 {
      let idx = rng.next_int(n)
      sample_x.push(x[idx])
      sample_y.push(y[idx])
      in_bag[idx] = true
    }
    let root = build_cls(
      sample_x,
      sample_y,
      n_features,
      mf,
      0,
      rf.max_depth,
      rf.min_samples_split,
      rng,
    )
    rf.trees.push(Some(root))
    for i = 0; i < n; i = i + 1 {
      if !in_bag[i] {
        let p = predict_node(root, x[i])
        let m = votes[i]
        m[p] = m.get(p).unwrap_or(0) + 1
        has_oob[i] = true
      }
    }
  }
  // OOB misclassification rate.
  let mut errors = 0
  let mut counted = 0
  for i = 0; i < n; i = i + 1 {
    if !has_oob[i] {
      continue
    }
    let m = votes[i]
    let mut best_label = -1
    let mut best_count = -1
    for kv in m {
      let (label, c) = kv
      if c > best_count {
        best_count = c
        best_label = label
      }
    }
    counted = counted + 1
    if best_label != y[i] {
      errors = errors + 1
    }
  }
  rf.oob_err = if counted > 0 {
    errors.to_double() / counted.to_double()
  } else {
    1.0
  }
}

///|
/// Train a regression forest. OOB rows are averaged to produce the OOB MSE.
pub fn fit_regress(
  rf : RandomForest,
  x : Array[Array[Double]],
  y : Array[Double],
) -> Unit {
  let n = x.length()
  if n == 0 || y.length() != n {
    return
  }
  let n_features = x[0].length()
  rf.n_features = n_features
  rf.is_regressor = true
  let mf = effective_max_features(rf.max_features, n_features, true)
  let rng = Rng::new(rf.seed)
  rf.trees = []
  let oob_sum : Array[Double] = Array::make(n, 0.0)
  let oob_cnt : Array[Int] = Array::make(n, 0)
  for _t = 0; _t < rf.n_trees; _t = _t + 1 {
    let sample_x : Array[Array[Double]] = []
    let sample_y : Array[Double] = []
    let in_bag : Array[Bool] = Array::make(n, false)
    for i = 0; i < n; i = i + 1 {
      let idx = rng.next_int(n)
      sample_x.push(x[idx])
      sample_y.push(y[idx])
      in_bag[idx] = true
    }
    let root = build_reg(
      sample_x,
      sample_y,
      n_features,
      mf,
      0,
      rf.max_depth,
      rf.min_samples_split,
      rng,
    )
    rf.trees.push(Some(root))
    for i = 0; i < n; i = i + 1 {
      if !in_bag[i] {
        oob_sum[i] = oob_sum[i] + predict_node_reg(root, x[i])
        oob_cnt[i] = oob_cnt[i] + 1
      }
    }
  }
  // OOB mean-squared error.
  let mut sq_err = 0.0
  let mut counted = 0
  for i = 0; i < n; i = i + 1 {
    if oob_cnt[i] == 0 {
      continue
    }
    let pred = oob_sum[i] / oob_cnt[i].to_double()
    let d = pred - y[i]
    sq_err = sq_err + d * d
    counted = counted + 1
  }
  rf.oob_err = if counted > 0 {
    sq_err / counted.to_double()
  } else {
    -1.0
  }
}

///|
/// Classify a row by majority vote across all trees.
pub fn predict(rf : RandomForest, x : Array[Double]) -> Int {
  let votes : Map[Int, Int] = Map([])
  for t = 0; t < rf.trees.length(); t = t + 1 {
    match rf.trees[t] {
      None => ()
      Some(r) => {
        let p = predict_node(r, x)
        votes[p] = votes.get(p).unwrap_or(0) + 1
      }
    }
  }
  let mut best_label = 0
  let mut best_count = -1
  for kv in votes {
    let (label, c) = kv
    if c > best_count {
      best_count = c
      best_label = label
    }
  }
  best_label
}

///|
/// Regress a row by averaging predictions across all trees.
pub fn predict_regress(rf : RandomForest, x : Array[Double]) -> Double {
  let n = rf.trees.length()
  if n == 0 {
    return 0.0
  }
  let mut sum = 0.0
  for t = 0; t < n; t = t + 1 {
    match rf.trees[t] {
      None => ()
      Some(r) => sum = sum + predict_node_reg(r, x)
    }
  }
  sum / n.to_double()
}

///|
/// Out-of-bag error: misclassification rate (classification) or MSE
/// (regression), computed on each row by the trees for which it was OOB.
/// Returns `1.0` / `-1.0` if no OOB prediction was possible.
pub fn oob_error(rf : RandomForest) -> Double {
  rf.oob_err
}

///|
/// Number of trees currently in the forest.
pub fn num_trees(rf : RandomForest) -> Int {
  rf.trees.length()
}

///|
/// Whether the forest was trained for regression (`true`) or
/// classification (`false`).
pub fn is_regressor(rf : RandomForest) -> Bool {
  rf.is_regressor
}

///|
/// Number of input features the forest was trained on (0 before fitting).
pub fn n_features(rf : RandomForest) -> Int {
  rf.n_features
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "random_forest: simple 1-D threshold classification" {
  let rf = new_classifier(30, 5, 2, 1)
  let x : Array[Array[Double]] = []
  for i = 0; i < 5; i = i + 1 {
    x.push([i.to_double()])
  }
  let y = [0, 0, 1, 1, 1]
  fit(rf, x, y)
  assert_eq(predict(rf, [0.5]), 0)
  assert_eq(predict(rf, [4.5]), 1)
}

///|
test "random_forest: 2-D XOR classification" {
  // XOR needs both features; replicate each corner so that bootstrap
  // samples reliably contain every class — a random forest cannot learn a
  // pattern from corners it never draws.
  let rf = new_classifier(60, 4, 2, 2)
  let x : Array[Array[Double]] = []
  let y : Array[Int] = []
  let corners = [[0.0, 0.0], [0.0, 1.0], [1.0, 0.0], [1.0, 1.0]]
  let labels = [0, 1, 1, 0]
  for c = 0; c < 4; c = c + 1 {
    for _r = 0; _r < 6; _r = _r + 1 {
      x.push(corners[c])
      y.push(labels[c])
    }
  }
  fit(rf, x, y)
  assert_eq(predict(rf, [0.0, 0.0]), 0)
  assert_eq(predict(rf, [0.0, 1.0]), 1)
  assert_eq(predict(rf, [1.0, 0.0]), 1)
  assert_eq(predict(rf, [1.0, 1.0]), 0)
}

///|
test "random_forest: regression averages to a reasonable value" {
  let rf = new_regressor(40, 6, 2, 1)
  let x : Array[Array[Double]] = []
  for i = 0; i < 6; i = i + 1 {
    x.push([i.to_double()])
  }
  // y = 2x + 1
  let y = [1.0, 3.0, 5.0, 7.0, 9.0, 11.0]
  fit_regress(rf, x, y)
  let p1 = predict_regress(rf, [1.0])
  let p5 = predict_regress(rf, [5.0])
  // Monotonic and close to the training targets.
  assert_true(p1 < p5)
  assert_true((p1 - 3.0).abs() < 2.0)
  assert_true((p5 - 11.0).abs() < 2.0)
}

///|
test "random_forest: OOB error is in valid range for classification" {
  let rf = new_classifier(50, 6, 2, 1)
  let x : Array[Array[Double]] = []
  let y : Array[Int] = []
  for i = 0; i < 10; i = i + 1 {
    x.push([i.to_double()])
    y.push(if i < 5 { 0 } else { 1 })
  }
  fit(rf, x, y)
  let err = oob_error(rf)
  // Separable data → OOB error should be small but within [0, 1].
  assert_true(err >= 0.0 && err <= 1.0)
  assert_true(err < 0.5)
}

///|
test "random_forest: OOB error is non-negative for regression" {
  let rf = new_regressor(50, 6, 2, 1)
  let x : Array[Array[Double]] = []
  let y : Array[Double] = []
  for i = 0; i < 8; i = i + 1 {
    x.push([i.to_double()])
    y.push(i.to_double() * 2.0)
  }
  fit_regress(rf, x, y)
  let err = oob_error(rf)
  assert_true(err >= 0.0)
}

///|
test "random_forest: deterministic given a fixed seed" {
  let train = fn() -> Int {
    let rf = new_classifier(30, 5, 2, 1)
    set_seed(rf, 42)
    let x = [[0.0], [1.0], [2.0], [3.0]]
    let y = [0, 0, 1, 1]
    fit(rf, x, y)
    predict(rf, [1.5])
  }
  assert_eq(train(), train())
}

///|
test "random_forest: empty training data is a no-op" {
  let rf = new_classifier(10, 5, 2, 1)
  fit(rf, [], [])
  assert_eq(num_trees(rf), 0)
  // Prediction on an empty forest returns the default 0.
  assert_eq(predict(rf, [1.0]), 0)
  assert_true(predict_regress(rf, [1.0]) == 0.0)
}

///|
test "random_forest: multi-class classification" {
  let rf = new_classifier(50, 8, 2, 1)
  let x = [[0.0], [1.0], [2.0], [3.0]]
  let y = [0, 1, 2, 3]
  fit(rf, x, y)
  assert_eq(predict(rf, [0.0]), 0)
  assert_eq(predict(rf, [1.0]), 1)
  assert_eq(predict(rf, [2.0]), 2)
  assert_eq(predict(rf, [3.0]), 3)
}
