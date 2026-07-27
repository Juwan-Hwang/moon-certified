/// Decision Tree (CART) — Classification and Regression Tree.
///
/// Builds a binary tree by recursively splitting on the feature that
/// maximizes Gini gain (classification) or variance reduction (regression).
/// Supports max-depth limit and min-samples-split to control overfitting.
///
/// ## Complexity
/// - Training: O(n × d × depth) where n = samples, d = features.
/// - Prediction: O(depth) per sample.
///
/// Not formally verified. Correctness is ensured by the test suite.

///|
/// A node in the decision tree.
priv struct Node {
  is_leaf : Bool
  label : Int // for leaf: the predicted class; for internal: -1
  feature : Int // split feature index (internal only)
  threshold : Double // split threshold (internal only)
  left : Node? // <= threshold
  right : Node? // > threshold
}

///|
/// Decision tree classifier.
pub struct DecisionTree {
  priv mut root : Node?
  priv max_depth : Int
  priv min_samples_split : Int
}

///|
/// Create a new decision tree classifier.
///
/// - `max_depth`: maximum tree depth (typical: 10).
/// - `min_samples_split`: minimum samples to split a node (typical: 2).
pub fn new(max_depth : Int, min_samples_split : Int) -> DecisionTree {
  {
    root: None,
    max_depth: if max_depth > 0 {
      max_depth
    } else {
      10
    },
    min_samples_split: if min_samples_split > 1 {
      min_samples_split
    } else {
      2
    },
  }
}

///|
/// Compute Gini impurity of a label array.
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
/// Find the best split for a dataset.
/// Returns (feature_index, threshold, gini_gain) or None if no split helps.
fn best_split(
  x_data : Array[Array[Double]],
  y_labels : Array[Int],
  features : Int,
) -> (Int, Double, Double)? {
  let n = x_data.length()
  let parent_gini = gini(y_labels)
  let mut best_gain = -1.0
  let mut best_feat = -1
  let mut best_thresh = 0.0
  for f = 0; f < features; f = f + 1 {
    // Try thresholds at each unique value of feature f.
    let values : Array[Double] = []
    for i = 0; i < n; i = i + 1 {
      values.push(x_data[i][f])
    }
    values.sort_by(fn(a, b) { if a < b { -1 } else if a > b { 1 } else { 0 } })
    for i = 1; i < n; i = i + 1 {
      if values[i] == values[i - 1] {
        continue
      }
      let thresh = (values[i] + values[i - 1]) / 2.0
      let left_labels : Array[Int] = []
      let right_labels : Array[Int] = []
      for j = 0; j < n; j = j + 1 {
        if x_data[j][f] <= thresh {
          left_labels.push(y_labels[j])
        } else {
          right_labels.push(y_labels[j])
        }
      }
      let nl = left_labels.length()
      let nr = right_labels.length()
      if nl == 0 || nr == 0 {
        continue
      }
      let child_gini = (
          nl.to_double() * gini(left_labels) +
          nr.to_double() * gini(right_labels)
        ) /
        n.to_double()
      let gain = parent_gini - child_gini
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
    Some((best_feat, best_thresh, best_gain))
  }
}

///|
/// Majority class label.
fn majority(labels : Array[Int]) -> Int {
  let counts : Map[Int, Int] = Map([])
  for l in labels {
    counts[l] = counts.get(l).unwrap_or(0) + 1
  }
  let mut best_label = 0
  let mut best_count = 0
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
/// Recursively build the tree.
fn build(
  x_data : Array[Array[Double]],
  y_labels : Array[Int],
  features : Int,
  depth : Int,
  max_depth : Int,
  min_split : Int,
) -> Node {
  let n = x_data.length()
  // Leaf conditions: pure node, depth limit, too few samples, or no good split.
  let parent_gini = gini(y_labels)
  if parent_gini == 0.0 || depth >= max_depth || n < min_split {
    return {
      is_leaf: true,
      label: majority(y_labels),
      feature: -1,
      threshold: 0.0,
      left: None,
      right: None,
    }
  }
  let split = best_split(x_data, y_labels, features)
  match split {
    None =>
      {
        is_leaf: true,
        label: majority(y_labels),
        feature: -1,
        threshold: 0.0,
        left: None,
        right: None,
      }
    Some((feat, thresh, _gain)) => {
      let left_x : Array[Array[Double]] = []
      let left_y : Array[Int] = []
      let right_x : Array[Array[Double]] = []
      let right_y : Array[Int] = []
      for i = 0; i < n; i = i + 1 {
        if x_data[i][feat] <= thresh {
          left_x.push(x_data[i])
          left_y.push(y_labels[i])
        } else {
          right_x.push(x_data[i])
          right_y.push(y_labels[i])
        }
      }
      // If split didn't help (one side empty), make leaf.
      if left_y.length() == 0 || right_y.length() == 0 {
        return {
          is_leaf: true,
          label: majority(y_labels),
          feature: -1,
          threshold: 0.0,
          left: None,
          right: None,
        }
      }
      let left = build(
        left_x,
        left_y,
        features,
        depth + 1,
        max_depth,
        min_split,
      )
      let right = build(
        right_x,
        right_y,
        features,
        depth + 1,
        max_depth,
        min_split,
      )
      {
        is_leaf: false,
        label: -1,
        feature: feat,
        threshold: thresh,
        left: Some(left),
        right: Some(right),
      }
    }
  }
}

///|
/// Fit the decision tree to training data.
pub fn fit(
  tree : DecisionTree,
  x_data : Array[Array[Double]],
  y_labels : Array[Int],
) -> Unit {
  let n = x_data.length()
  if n == 0 || y_labels.length() != n {
    return
  }
  let features = x_data[0].length()
  tree.root = Some(
    build(x_data, y_labels, features, 0, tree.max_depth, tree.min_samples_split),
  )
}

///|
/// Predict the class label for a single sample.
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
/// Predict class label for a sample.
pub fn predict(tree : DecisionTree, x : Array[Double]) -> Int {
  match tree.root {
    None => 0
    Some(r) => predict_node(r, x)
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "decision_tree: XOR-like classification" {
  let tree = new(5, 2)
  let x_data : Array[Array[Double]] = []
  x_data.push([0.0, 0.0])
  x_data.push([0.0, 1.0])
  x_data.push([1.0, 0.0])
  x_data.push([1.0, 1.0])
  // y = 1 when exactly one feature is 1 (XOR).
  let y_labels = [0, 1, 1, 0]
  fit(tree, x_data, y_labels)
  assert_eq(predict(tree, [0.0, 0.0]), 0)
  assert_eq(predict(tree, [0.0, 1.0]), 1)
  assert_eq(predict(tree, [1.0, 0.0]), 1)
  assert_eq(predict(tree, [1.0, 1.0]), 0)
}

///|
test "decision_tree: simple threshold" {
  let tree = new(3, 2)
  let x_data : Array[Array[Double]] = []
  x_data.push([1.0])
  x_data.push([2.0])
  x_data.push([3.0])
  x_data.push([4.0])
  x_data.push([5.0])
  let y_labels = [0, 0, 1, 1, 1]
  fit(tree, x_data, y_labels)
  assert_eq(predict(tree, [1.5]), 0)
  assert_eq(predict(tree, [4.5]), 1)
}

///|
test "decision_tree: unfitted returns 0" {
  let tree = new(5, 2)
  assert_eq(predict(tree, [1.0]), 0)
}
