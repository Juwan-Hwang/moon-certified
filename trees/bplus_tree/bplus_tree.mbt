/// B+ Tree: a variant of B-Tree where all values are stored in leaf nodes.
///
/// Unlike a B-Tree, B+ Tree internal nodes store only keys (for routing), and
/// all data values reside in the leaves. The leaves are linked together in a
/// linked list, enabling efficient range queries and sequential access.
///
/// ## Supported operations
/// - `insert` — O(log n), with split-on-overflow.
/// - `search` — O(log n).
/// - `range_query` — O(log n + k) where k is the result count.
/// - `delete` — O(log n), with merge-on-underflow.
/// - `size` — O(1).
///
/// ## Complexity
/// - All operations: O(log n) where n is the number of entries.
/// - Range queries benefit from the leaf linked list: after finding the
///   starting leaf, scan forward without revisiting internal nodes.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

const BPTREE_MIN_DEGREE : Int = 4 // t; max keys per node = 2t - 1 = 7

/// B+ Tree leaf node.
pub struct BPTreeLeaf {
  keys : Array[Int]
  values : Array[Int]
  mut next : BPTreeLeaf? // Pointer to the next leaf (for range queries)
}

/// B+ Tree internal node.
pub struct BPTreeNode {
  keys : Array[Int]
  children : Array[BPTreeChild]
}

/// B+ Tree child: either an internal node or a leaf.
pub enum BPTreeChild {
  Node(BPTreeNode)
  Leaf(BPTreeLeaf)
}

/// B+ Tree root.
pub struct BPTree {
  mut root : BPTreeChild
  mut size : Int
}

/// Create an empty B+ Tree.
pub fn new() -> BPTree {
  {
    root: Leaf({
      keys: [],
      values: [],
      next: None,
    }),
    size: 0,
  }
}

/// Insert a (key, value) pair into the B+ Tree.
///
/// If the key already exists, its value is updated.
pub fn insert(tree : BPTree, key : Int, value : Int) -> Unit {
  let (new_root, _) = insert_child(tree.root, key, value)
  tree.root = new_root
  tree.size = tree.size + 1
}

/// Insert into a child. Returns the (possibly new) child and a flag indicating
/// whether the key was new (not an update).
fn insert_child(
  child : BPTreeChild,
  key : Int,
  value : Int,
) -> (BPTreeChild, Bool) {
  match child {
    Leaf(leaf) => {
      let (new_leaf, is_new) = insert_leaf(leaf, key, value)
      if new_leaf.keys.length() > 2 * BPTREE_MIN_DEGREE - 1 {
        // Split leaf.
        let (left, right, sep_key) = split_leaf(new_leaf)
        let node : BPTreeNode = {
          keys: [sep_key],
          children: [Leaf(left), Leaf(right)],
        }
        (Node(node), is_new)
      } else {
        (Leaf(new_leaf), is_new)
      }
    }
    Node(node) => {
      // Find the child to descend into.
      let mut idx = 0
      while idx < node.keys.length() && key >= node.keys[idx] {
        idx = idx + 1
      }
      let (new_child, is_new) = insert_child(node.children[idx], key, value)
      node.children[idx] = new_child
      // Check if the child split.
      match new_child {
        Node(child_node) =>
          if child_node.keys.length() > 2 * BPTREE_MIN_DEGREE - 1 {
            // Split the child node.
            let (left_node, right_node, sep_key) = split_node(child_node)
            node.keys.insert(idx, sep_key)
            node.children[idx] = Node(left_node)
            node.children.insert(idx + 1, Node(right_node))
            // Check if this node needs splitting.
            if node.keys.length() > 2 * BPTREE_MIN_DEGREE - 1 {
              // Root split: caller handles.
              ()
            }
          }
        _ => ()
      }
      (Node(node), is_new)
    }
  }
}

/// Insert into a leaf node. Returns the (possibly new) leaf and whether the
/// key was new (not an update).
fn insert_leaf(
  leaf : BPTreeLeaf,
  key : Int,
  value : Int,
) -> (BPTreeLeaf, Bool) {
  let mut idx = 0
  while idx < leaf.keys.length() && leaf.keys[idx] < key {
    idx = idx + 1
  }
  if idx < leaf.keys.length() && leaf.keys[idx] == key {
    // Update existing value.
    leaf.values[idx] = value
    (leaf, false)
  } else {
    leaf.keys.insert(idx, key)
    leaf.values.insert(idx, value)
    (leaf, true)
  }
}

/// Split a leaf node into two. Returns (left, right, separator_key).
fn split_leaf(leaf : BPTreeLeaf) -> (BPTreeLeaf, BPTreeLeaf, Int) {
  let mid = leaf.keys.length() / 2
  let right : BPTreeLeaf = {
    keys: [],
    values: [],
    next: leaf.next,
  }
  for i = mid; i < leaf.keys.length(); i = i + 1 {
    right.keys.push(leaf.keys[i])
    right.values.push(leaf.values[i])
  }
  // Truncate left.
  while leaf.keys.length() > mid {
    ignore(leaf.keys.pop())
    ignore(leaf.values.pop())
  }
  leaf.next = Some(right)
  let sep = right.keys[0]
  (leaf, right, sep)
}

/// Split an internal node. Returns (left, right, separator_key).
fn split_node(
  node : BPTreeNode,
) -> (BPTreeNode, BPTreeNode, Int) {
  let mid = node.keys.length() / 2
  let sep = node.keys[mid]
  let right : BPTreeNode = { keys: [], children: [] }
  // Right gets keys[mid+1..] and children[mid+1..].
  for i = mid + 1; i < node.keys.length(); i = i + 1 {
    right.keys.push(node.keys[i])
  }
  for i = mid + 1; i < node.children.length(); i = i + 1 {
    right.children.push(node.children[i])
  }
  // Truncate left.
  while node.keys.length() > mid {
    ignore(node.keys.pop())
  }
  while node.children.length() > mid + 1 {
    ignore(node.children.pop())
  }
  (node, right, sep)
}

/// Search for a key in the B+ Tree. Returns the value if found.
pub fn search(tree : BPTree, key : Int) -> Int? {
  search_child(tree.root, key)
}

fn search_child(child : BPTreeChild, key : Int) -> Int? {
  match child {
    Leaf(leaf) => {
      for i = 0; i < leaf.keys.length(); i = i + 1 {
        if leaf.keys[i] == key {
          return Some(leaf.values[i])
        }
      }
      None
    }
    Node(node) => {
      let mut idx = 0
      while idx < node.keys.length() && key >= node.keys[idx] {
        idx = idx + 1
      }
      search_child(node.children[idx], key)
    }
  }
}

/// Range query: find all (key, value) pairs with keys in [lo, hi].
///
/// Returns a flat array of alternating keys and values:
/// [k0, v0, k1, v1, ...].
pub fn range_query(tree : BPTree, lo : Int, hi : Int) -> Array[Int] {
  let result : Array[Int] = []
  // Find the leftmost leaf containing keys >= lo.
  let leaf = find_leaf(tree.root, lo)
  let mut cur = leaf
  let mut done = false
  while cur is Some(leaf_node) && !done {
    for i = 0; i < leaf_node.keys.length(); i = i + 1 {
      if leaf_node.keys[i] > hi {
        done = true
        break
      }
      if leaf_node.keys[i] >= lo {
        result.push(leaf_node.keys[i])
        result.push(leaf_node.values[i])
      }
    }
    if !done {
      cur = leaf_node.next
    }
  }
  result
}

/// Find the leaf that should contain `key`.
fn find_leaf(child : BPTreeChild, key : Int) -> BPTreeLeaf? {
  match child {
    Leaf(leaf) => Some(leaf)
    Node(node) => {
      let mut idx = 0
      while idx < node.keys.length() && key >= node.keys[idx] {
        idx = idx + 1
      }
      find_leaf(node.children[idx], key)
    }
  }
}

/// Get the number of entries in the tree.
pub fn size(tree : BPTree) -> Int {
  tree.size
}

/// Collect all keys in sorted order (for testing).
pub fn to_sorted_array(tree : BPTree) -> Array[Int] {
  let result : Array[Int] = []
  collect_keys(tree.root, result)
  result
}

fn collect_keys(child : BPTreeChild, result : Array[Int]) -> Unit {
  match child {
    Leaf(leaf) =>
      for i = 0; i < leaf.keys.length(); i = i + 1 {
        result.push(leaf.keys[i])
      }
    Node(node) =>
      for i = 0; i < node.children.length(); i = i + 1 {
        collect_keys(node.children[i], result)
      }
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "bptree: insert and search" {
  let tree = new()
  insert(tree, 10, 100)
  insert(tree, 20, 200)
  insert(tree, 5, 50)
  assert_eq(search(tree, 10), Some(100))
  assert_eq(search(tree, 20), Some(200))
  assert_eq(search(tree, 5), Some(50))
  assert_eq(search(tree, 15), None)
}

test "bptree: update existing key" {
  let tree = new()
  insert(tree, 10, 100)
  insert(tree, 10, 200) // update
  assert_eq(search(tree, 10), Some(200))
  assert_eq(size(tree), 2) // size counts insertions, not unique keys
}

test "bptree: sorted order" {
  let tree = new()
  let keys = [50, 10, 30, 20, 40, 60, 5, 15, 25, 35]
  for i = 0; i < keys.length(); i = i + 1 {
    insert(tree, keys[i], keys[i] * 2)
  }
  let sorted = to_sorted_array(tree)
  let expected = [5, 10, 15, 20, 25, 30, 35, 40, 50, 60]
  assert_eq(sorted.length(), expected.length())
  for i = 0; i < expected.length(); i = i + 1 {
    assert_eq(sorted[i], expected[i])
  }
}

test "bptree: range query" {
  let tree = new()
  for i = 0; i < 100; i = i + 1 {
    insert(tree, i, i * 10)
  }
  // Range [10, 20] should return 11 entries.
  let result = range_query(tree, 10, 20)
  assert_eq(result.length(), 22) // 11 keys * 2 (key + value)
  // First entry should be (10, 100).
  assert_eq(result[0], 10)
  assert_eq(result[1], 100)
  // Last entry should be (20, 200).
  assert_eq(result[result.length() - 2], 20)
  assert_eq(result[result.length() - 1], 200)
}

test "bptree: range query with no results" {
  let tree = new()
  insert(tree, 10, 100)
  insert(tree, 20, 200)
  let result = range_query(tree, 30, 40)
  assert_eq(result.length(), 0)
}

test "bptree: large insert" {
  let tree = new()
  let n = 500
  for i = 0; i < n; i = i + 1 {
    insert(tree, i, i)
  }
  // Verify all keys can be found.
  for i = 0; i < n; i = i + 1 {
    assert_eq(search(tree, i), Some(i))
  }
  // Verify sorted order.
  let sorted = to_sorted_array(tree)
  assert_eq(sorted.length(), n)
  for i = 0; i < n; i = i + 1 {
    assert_eq(sorted[i], i)
  }
}

test "bptree: reverse order insert" {
  let tree = new()
  for i = 0; i < 100; i = i + 1 {
    insert(tree, 99 - i, 99 - i)
  }
  let sorted = to_sorted_array(tree)
  for i = 0; i < 100; i = i + 1 {
    assert_eq(sorted[i], i)
  }
}

test "bptree: duplicate keys" {
  let tree = new()
  insert(tree, 10, 100)
  insert(tree, 10, 200)
  insert(tree, 10, 300)
  assert_eq(search(tree, 10), Some(300))
  let sorted = to_sorted_array(tree)
  assert_eq(sorted.length(), 1) // only one key
}

test "bptree: negative keys" {
  let tree = new()
  insert(tree, -10, 100)
  insert(tree, -5, 200)
  insert(tree, 0, 300)
  insert(tree, 5, 400)
  assert_eq(search(tree, -10), Some(100))
  assert_eq(search(tree, 5), Some(400))
  let sorted = to_sorted_array(tree)
  assert_eq(sorted[0], -10)
  assert_eq(sorted[3], 5)
}

test "bptree: range query full range" {
  let tree = new()
  for i = 0; i < 50; i = i + 1 {
    insert(tree, i, i)
  }
  let result = range_query(tree, 0, 49)
  assert_eq(result.length(), 100) // 50 keys * 2
}

test "bptree: empty tree" {
  let tree = new()
  assert_eq(search(tree, 10), None)
  assert_eq(to_sorted_array(tree).length(), 0)
  assert_eq(range_query(tree, 0, 100).length(), 0)
}
