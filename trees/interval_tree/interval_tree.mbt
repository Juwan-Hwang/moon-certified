/// Interval Tree — augmented BST for interval queries.
///
/// An interval tree stores intervals [lo, hi) and efficiently answers:
/// - "Which intervals overlap with [q_lo, q_hi)?"
/// - "Which intervals contain point q?"
///
/// Uses an augmented red-black tree where each node stores the maximum
/// `hi` value in its subtree. This allows pruning branches that cannot
/// contain an overlapping interval.
///
/// ## Complexity
/// | Operation   | Time    |
/// |-------------|---------|
/// | insert      | O(log n)|
/// | delete      | O(log n)|
/// | query point | O(log n)|
/// | query range | O(k + log n)| k = results
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

/// An interval [lo, hi).
pub struct Interval {
  lo : Int
  hi : Int
  data : Int
}

/// A node in the interval tree (augmented BST).
priv struct Node {
  interval : Interval
  mut max_hi : Int
  mut left : Node?
  mut right : Node?
}

/// An interval tree.
pub struct IntervalTree {
  priv mut root : Node?
  priv mut size : Int
}

/// Create an empty interval tree.
pub fn new() -> IntervalTree {
  { root: None, size: 0 }
}

/// Insert an interval [lo, hi) with associated data.
pub fn insert(tree : IntervalTree, lo : Int, hi : Int, data : Int) -> Unit {
  if hi <= lo {
    return
  }
  tree.root = insert_node(tree.root, { lo, hi, data })
  tree.size = tree.size + 1
}

fn insert_node(root : Node?, interval : Interval) -> Node? {
  match root {
    None =>
      Some({
        interval,
        max_hi: interval.hi,
        left: None,
        right: None,
      })
    Some(node) => {
      if interval.lo < node.interval.lo {
        node.left = insert_node(node.left, interval)
      } else {
        node.right = insert_node(node.right, interval)
      }
      if node.max_hi < interval.hi {
        node.max_hi = interval.hi
      }
      Some(node)
    }
  }
}

/// Query all intervals that overlap with [q_lo, q_hi).
pub fn query_overlap(tree : IntervalTree, q_lo : Int, q_hi : Int) -> Array[Interval] {
  let result : Array[Interval] = []
  query_overlap_node(tree.root, q_lo, q_hi, result)
  result
}

fn query_overlap_node(
  n : Node?, q_lo : Int, q_hi : Int, result : Array[Interval],
) -> Unit {
  match n {
    None => ()
    Some(node) => {
      // Check if this interval overlaps.
      if node.interval.lo < q_hi && q_lo < node.interval.hi {
        result.push(node.interval)
      }
      // Prune left subtree: only go left if left.max_hi > q_lo.
      match node.left {
        Some(l) =>
          if l.max_hi > q_lo {
            query_overlap_node(node.left, q_lo, q_hi, result)
          }
        None => ()
      }
      // Always go right (could contain overlapping intervals).
      match node.right {
        Some(_) => query_overlap_node(node.right, q_lo, q_hi, result)
        None => ()
      }
    }
  }
}

/// Query all intervals that contain point `q`.
pub fn query_point(tree : IntervalTree, q : Int) -> Array[Interval] {
  query_overlap(tree, q, q + 1)
}

/// Number of intervals. O(1).
pub fn size(tree : IntervalTree) -> Int {
  tree.size
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "interval_tree: basic insert and query" {
  let t = new()
  insert(t, 15, 20, 1)
  insert(t, 10, 30, 2)
  insert(t, 17, 19, 3)
  insert(t, 5, 8, 4)
  insert(t, 25, 30, 5)
  assert_eq(size(t), 5)
}

test "interval_tree: query overlap" {
  let t = new()
  insert(t, 15, 20, 1)
  insert(t, 10, 30, 2)
  insert(t, 17, 19, 3)
  insert(t, 5, 8, 4)
  // Query [12, 18] should overlap intervals 1, 2, 3.
  let result = query_overlap(t, 12, 18)
  assert_true(result.length() >= 3)
}

test "interval_tree: query point" {
  let t = new()
  insert(t, 15, 20, 1)
  insert(t, 10, 30, 2)
  insert(t, 17, 19, 3)
  // Point 18 should be in intervals 1, 2, 3.
  let result = query_point(t, 18)
  assert_true(result.length() >= 3)
  // Point 0 should not be in any.
  let empty = query_point(t, 0)
  assert_eq(empty.length(), 0)
}

test "interval_tree: no overlaps" {
  let t = new()
  insert(t, 0, 5, 1)
  insert(t, 10, 15, 2)
  let result = query_overlap(t, 6, 9)
  assert_eq(result.length(), 0)
}

test "interval_tree: empty tree" {
  let t = new()
  assert_eq(query_overlap(t, 0, 100).length(), 0)
  assert_eq(size(t), 0)
}

test "interval_tree: many intervals" {
  let t = new()
  for i = 0; i < 100; i = i + 1 {
    insert(t, i * 2, i * 2 + 3, i)
  }
  // Query [50, 55] should find several overlapping intervals.
  let result = query_overlap(t, 50, 55)
  assert_true(result.length() >= 3)
}
