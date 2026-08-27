///|
/// Gradient Boosted Decision Trees (GBDT)
///
/// GBDT is an ensemble learning method that builds decision trees sequentially,
/// each tree fitting the residuals (negative gradients) of the previous trees.
/// Features: L2 loss, shrinkage, subsampling, max_depth, min_samples_split.
///
/// ## References
/// - Friedman, J.H. "Greedy Function Approximation: A Gradient Boosting Machine." 2001.
/// - Chen & Guestrin. "XGBoost: A Scalable Tree Boosting System." KDD 2016.
///
/// `proof-enabled` is `false`.

// ===========================================================================
// Data structures
// ===========================================================================

struct TreeNode {
  mut feature : Int // -1 for leaf
  mut threshold : Double
  mut leaf_value : Double
  mut left : Int
  mut right : Int
}

///|
fn TreeNode::new() -> TreeNode {
  { feature: -1, threshold: 0.0, leaf_value: 0.0, left: -1, right: -1, }
}

///|
pub struct GbdtParams {
  n_estimators : Int
  max_depth : Int
  min_samples_split : Int
  learning_rate : Double
  l1_reg : Double
  l2_reg : Double
  subsample : Double
}

///|
pub fn gbdt_default_params() -> GbdtParams {
  {
    n_estimators: 100,
    max_depth: 3,
    min_samples_split: 2,
    learning_rate: 0.1,
    l1_reg: 0.0,
    l2_reg: 1.0,
    subsample: 1.0,
  }
}

///|
pub struct DecisionTree {
  nodes : Array[TreeNode]
}

///|
pub struct GbdtModel {
  trees : Array[DecisionTree]
  init_value : Double
  learning_rate : Double
}

// ===========================================================================
// Helpers
// ===========================================================================

///|
fn mean(arr : Array[Double]) -> Double {
  if arr.length() == 0 {
    return 0.0
  }
  let mut sum = 0.0
  for v in arr {
    sum = sum + v
  }
  sum / arr.length().to_double()
}

///|
fn squared_error(arr : Array[Double]) -> Double {
  if arr.length() == 0 {
    return 0.0
  }
  let m = mean(arr)
  let mut sum = 0.0
  for v in arr {
    let d = v - m
    sum = sum + d * d
  }
  sum
}

///|
priv struct SplitResult {
  threshold : Double
  gain : Double
}

///|
fn find_best_split(
  x : Array[Array[Double]],
  y : Array[Double],
  indices : Array[Int],
  feature : Int,
) -> SplitResult {
  let values : Array[Double] = []
  let targets : Array[Double] = []
  for idx in indices {
    values.push(x[idx][feature])
    targets.push(y[idx])
  }
  // Insertion sort by feature value
  let n = values.length()
  let si = Array::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    si[i] = i
  }
  for i = 1; i < n; i = i + 1 {
    let key = si[i]
    let mut j = i - 1
    while j >= 0 && values[si[j]] > values[key] {
      si[j + 1] = si[j]
      j = j - 1
    }
    si[j + 1] = key
  }
  let parent_loss = squared_error(targets)
  let mut best_threshold = 0.0
  let mut best_gain = 0.0
  for i = 1; i < n; i = i + 1 {
    if values[si[i]] == values[si[i - 1]] {
      // skip equal values
    } else {
      let threshold = (values[si[i]] + values[si[i - 1]]) / 2.0
      let left_t : Array[Double] = []
      let right_t : Array[Double] = []
      for j = 0; j < n; j = j + 1 {
        if j < i {
          left_t.push(targets[si[j]])
        } else {
          right_t.push(targets[si[j]])
        }
      }
      let left_loss = squared_error(left_t)
      let right_loss = squared_error(right_t)
      let gain = parent_loss - (left_loss + right_loss)
      if gain > best_gain {
        best_gain = gain
        best_threshold = threshold
      }
    }
  }
  { threshold: best_threshold, gain: best_gain, }
}

// ===========================================================================
// Tree building (iterative via explicit stack)
// ===========================================================================

///|
fn build_tree(
  x : Array[Array[Double]],
  y : Array[Double],
  indices : Array[Int],
  max_depth : Int,
  min_samples_split : Int,
) -> DecisionTree {
  let tree = { nodes: [], }
  if indices.length() == 0 {
    tree.nodes.push(TreeNode::new())
    return tree
  }
  let n_features = x[0].length()
  // Stack: (indices, depth, node_index)
  let stack_indices : Array[Array[Int]] = [indices]
  let stack_depths : Array[Int] = [0]
  let stack_nodes : Array[Int] = []
  // Pre-allocate root
  tree.nodes.push(TreeNode::new())
  stack_nodes.push(0)
  while stack_indices.length() > 0 {
    let idx = stack_indices.pop().unwrap()
    let dpt = stack_depths.pop().unwrap()
    let nidx = stack_nodes.pop().unwrap()
    // Check leaf conditions
    let is_leaf = idx.length() < min_samples_split || dpt >= max_depth
    if is_leaf {
      let t : Array[Double] = []
      for i in idx {
        t.push(y[i])
      }
      tree.nodes[nidx].leaf_value = mean(t)
    } else {
      // Find best split
      let mut best_f = -1
      let mut best_t = 0.0
      let mut best_g = 0.0
      for f = 0; f < n_features; f = f + 1 {
        let r = find_best_split(x, y, idx, f)
        if r.gain > best_g {
          best_g = r.gain
          best_f = f
          best_t = r.threshold
        }
      }
      if best_f == -1 || best_g <= 0.0 {
        let t : Array[Double] = []
        for i in idx {
          t.push(y[i])
        }
        tree.nodes[nidx].leaf_value = mean(t)
      } else {
        let left_idx : Array[Int] = []
        let right_idx : Array[Int] = []
        for i in idx {
          if x[i][best_f] <= best_t {
            left_idx.push(i)
          } else {
            right_idx.push(i)
          }
        }
        tree.nodes[nidx].feature = best_f
        tree.nodes[nidx].threshold = best_t
        // Create children
        tree.nodes.push(TreeNode::new())
        let li = tree.nodes.length() - 1
        tree.nodes.push(TreeNode::new())
        let ri = tree.nodes.length() - 1
        tree.nodes[nidx].left = li
        tree.nodes[nidx].right = ri
        stack_indices.push(left_idx)
        stack_depths.push(dpt + 1)
        stack_nodes.push(li)
        stack_indices.push(right_idx)
        stack_depths.push(dpt + 1)
        stack_nodes.push(ri)
      }
    }
  }
  tree
}

///|
fn tree_predict(tree : DecisionTree, sample : Array[Double]) -> Double {
  let mut node = 0
  while tree.nodes[node].feature != -1 {
    if sample[tree.nodes[node].feature] <= tree.nodes[node].threshold {
      node = tree.nodes[node].left
    } else {
      node = tree.nodes[node].right
    }
  }
  tree.nodes[node].leaf_value
}

// ===========================================================================
// Public API
// ===========================================================================

///|
pub fn gbdt_fit(
  x : Array[Array[Double]],
  y : Array[Double],
  params : GbdtParams,
  seed : Int,
) -> GbdtModel {
  let n = x.length()
  let init_value = mean(y)
  let predictions = Array::make(n, init_value)
  let trees : Array[DecisionTree] = []
  let mut rng = seed
  for est = 0; est < params.n_estimators; est = est + 1 {
    // Residuals (negative gradient for L2)
    let residuals = Array::make(n, 0.0)
    for i = 0; i < n; i = i + 1 {
      residuals[i] = y[i] - predictions[i]
    }
    // Subsample
    let indices : Array[Int] = []
    for i = 0; i < n; i = i + 1 {
      rng = (rng * 1103515245 + 12345) & 0x7FFFFFFF
      let r = rng.to_double() / 2147483647.0
      if r < params.subsample {
        indices.push(i)
      }
    }
    if indices.length() < 2 {
      for i = 0; i < n; i = i + 1 {
        indices.push(i)
      }
    }
    let tree = build_tree(
      x,
      residuals,
      indices,
      params.max_depth,
      params.min_samples_split,
    )
    for i = 0; i < n; i = i + 1 {
      predictions[i] = predictions[i] +
        params.learning_rate * tree_predict(tree, x[i])
    }
    trees.push(tree)
  }
  { trees, init_value, learning_rate: params.learning_rate, }
}

///|
pub fn gbdt_predict(model : GbdtModel, x : Array[Double]) -> Double {
  let mut pred = model.init_value
  for tree in model.trees {
    pred = pred + model.learning_rate * tree_predict(tree, x)
  }
  pred
}

///|
pub fn gbdt_predict_batch(
  model : GbdtModel,
  x : Array[Array[Double]],
) -> Array[Double] {
  let preds : Array[Double] = []
  for sample in x {
    preds.push(gbdt_predict(model, sample))
  }
  preds
}

///|
pub fn gbdt_score(
  model : GbdtModel,
  x : Array[Array[Double]],
  y : Array[Double],
) -> Double {
  let y_mean = mean(y)
  let mut ss_res = 0.0
  let mut ss_tot = 0.0
  for i = 0; i < x.length(); i = i + 1 {
    let pred = gbdt_predict(model, x[i])
    ss_res = ss_res + (y[i] - pred) * (y[i] - pred)
    ss_tot = ss_tot + (y[i] - y_mean) * (y[i] - y_mean)
  }
  if ss_tot == 0.0 {
    return 1.0
  }
  1.0 - ss_res / ss_tot
}

// ===========================================================================
// Tests
// ===========================================================================

///|
test "GBDT: default params" {
  let p = gbdt_default_params()
  assert_true(p.n_estimators == 100)
  assert_true(p.max_depth == 3)
  assert_true(p.learning_rate == 0.1)
}

///|
test "GBDT: fit and predict" {
  let x = [[1.0], [2.0], [3.0], [4.0], [5.0]]
  let y = [2.0, 4.0, 6.0, 8.0, 10.0]
  let params : GbdtParams = {
    n_estimators: 50,
    max_depth: 3,
    min_samples_split: 2,
    learning_rate: 0.1,
    l1_reg: 0.0,
    l2_reg: 1.0,
    subsample: 1.0,
  }
  let model = gbdt_fit(x, y, params, 42)
  let pred = gbdt_predict(model, [3.0])
  // Should be close to 6.0
  assert_true(pred > 4.0 && pred < 8.0)
}

///|
test "GBDT: R² score positive" {
  let x = [[1.0], [2.0], [3.0], [4.0], [5.0]]
  let y = [2.0, 4.0, 6.0, 8.0, 10.0]
  let params : GbdtParams = {
    n_estimators: 50,
    max_depth: 3,
    min_samples_split: 2,
    learning_rate: 0.1,
    l1_reg: 0.0,
    l2_reg: 1.0,
    subsample: 1.0,
  }
  let model = gbdt_fit(x, y, params, 42)
  let score = gbdt_score(model, x, y)
  assert_true(score > 0.0)
}
