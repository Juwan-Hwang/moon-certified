///|
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

///|
/// B+ Tree leaf node.
pub struct BPTreeLeaf {
  keys : Array[Int]
  values : Array[Int]
  mut next : BPTreeLeaf? // Pointer to the next leaf (for range queries)
}

///|
/// B+ Tree internal node.
pub struct BPTreeNode {
  keys : Array[Int]
  children : Array[BPTreeChild]
}

///|
/// B+ Tree child: either an internal node or a leaf.
pub enum BPTreeChild {
  Node(BPTreeNode)
  Leaf(BPTreeLeaf)
}

///|
/// B+ Tree root.
pub struct BPTree {
  mut root : BPTreeChild
  mut size : Int
}

///|
/// Create an empty B+ Tree.
pub fn new() -> BPTree {
  { root: Leaf({ keys: [], values: [], next: None }), size: 0 }
}

///|
/// Insert a (key, value) pair into the B+ Tree.
///
/// If the key already exists, its value is updated (size unchanged).
pub fn insert(tree : BPTree, key : Int, value : Int) -> Unit {
  let (new_root, is_new) = insert_child(tree.root, key, value)
  // If the root is an internal node that overflowed, split it and create
  // a new root one level higher.
  match new_root {
    Node(node) =>
      if node.keys.length() > 2 * BPTREE_MIN_DEGREE - 1 {
        let (left, right, sep_key) = split_node(node)
        let new_root_node : BPTreeNode = {
          keys: [sep_key],
          children: [Node(left), Node(right)],
        }
        tree.root = Node(new_root_node)
      } else {
        tree.root = new_root
      }
    _ => tree.root = new_root
  }
  if is_new {
    tree.size = tree.size + 1
  }
}

///|
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

///|
/// Insert into a leaf node. Returns the (possibly new) leaf and whether the
/// key was new (not an update).
fn insert_leaf(leaf : BPTreeLeaf, key : Int, value : Int) -> (BPTreeLeaf, Bool) {
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

///|
/// Split a leaf node into two. Returns (left, right, separator_key).
fn split_leaf(leaf : BPTreeLeaf) -> (BPTreeLeaf, BPTreeLeaf, Int) {
  let mid = leaf.keys.length() / 2
  let right : BPTreeLeaf = { keys: [], values: [], next: leaf.next }
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

///|
/// Split an internal node. Returns (left, right, separator_key).
fn split_node(node : BPTreeNode) -> (BPTreeNode, BPTreeNode, Int) {
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

///|
/// Search for a key in the B+ Tree. Returns the value if found.
pub fn search(tree : BPTree, key : Int) -> Int? {
  search_child(tree.root, key)
}

///|
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

///|
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

///|
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

///|
/// Get the number of entries in the tree.
pub fn size(tree : BPTree) -> Int {
  tree.size
}

///|
/// Collect all keys in sorted order (for testing).
pub fn to_sorted_array(tree : BPTree) -> Array[Int] {
  let result : Array[Int] = []
  collect_keys(tree.root, result)
  result
}

///|
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
// Delete with rebalancing (borrow / merge)
// ---------------------------------------------------------------------------

///|
/// Delete a key from the B+ Tree.
///
/// Returns `true` if the key was found and removed, `false` if the key
/// was not present. After deletion, the tree is rebalanced to maintain
/// B+ Tree invariants: every non-root node has at least `t - 1` keys.
///
/// ## Complexity
/// - Time: O(log n) — single root-to-leaf descent with O(1) rebalancing.
pub fn delete(tree : BPTree, key : Int) -> Bool {
  let found = delete_child(tree.root, key)
  if found {
    tree.size = tree.size - 1
    // Contract: if root is an internal node with a single child, promote it.
    match tree.root {
      Node(node) =>
        if node.keys.length() == 0 && node.children.length() == 1 {
          tree.root = node.children[0]
        }
      _ => ()
    }
  }
  found
}

///|
/// Dispatch deletion to the appropriate node type.
fn delete_child(child : BPTreeChild, key : Int) -> Bool {
  match child {
    Leaf(leaf) => delete_from_leaf(leaf, key)
    Node(node) => delete_from_node(node, key)
  }
}

///|
/// Remove a key from a leaf node. Returns whether the key was found.
fn delete_from_leaf(leaf : BPTreeLeaf, key : Int) -> Bool {
  let mut idx = 0
  while idx < leaf.keys.length() && leaf.keys[idx] < key {
    idx = idx + 1
  }
  if idx < leaf.keys.length() && leaf.keys[idx] == key {
    ignore(leaf.keys.remove(idx))
    ignore(leaf.values.remove(idx))
    true
  } else {
    false
  }
}

///|
/// Remove a key from an internal node by descending to the appropriate child,
/// then rebalancing if the child underflows.
fn delete_from_node(node : BPTreeNode, key : Int) -> Bool {
  let mut idx = 0
  while idx < node.keys.length() && key >= node.keys[idx] {
    idx = idx + 1
  }
  let found = delete_child(node.children[idx], key)
  if !found {
    return false
  }
  let min_keys = BPTREE_MIN_DEGREE - 1
  match node.children[idx] {
    Leaf(child_leaf) =>
      if child_leaf.keys.length() < min_keys {
        rebalance_leaf(node, idx, child_leaf)
      }
    Node(child_node) =>
      if child_node.keys.length() < min_keys {
        rebalance_node(node, idx, child_node)
      }
  }
  true
}

///|
/// Rebalance a leaf that has underflowed.
/// Strategy: borrow from left sibling → borrow from right sibling → merge.
fn rebalance_leaf(parent : BPTreeNode, idx : Int, cur : BPTreeLeaf) -> Unit {
  let min_keys = BPTREE_MIN_DEGREE - 1
  // 1. Try borrowing from the left sibling.
  if idx > 0 {
    match parent.children[idx - 1] {
      Leaf(left) =>
        if left.keys.length() > min_keys {
          // Move the last (key, value) from left to the front of cur.
          let bk = left.keys[left.keys.length() - 1]
          let bv = left.values[left.values.length() - 1]
          ignore(left.keys.pop())
          ignore(left.values.pop())
          cur.keys.insert(0, bk)
          cur.values.insert(0, bv)
          // Update the separator key in the parent.
          parent.keys[idx - 1] = bk
          return
        }
      _ => ()
    }
  }
  // 2. Try borrowing from the right sibling.
  if idx < parent.children.length() - 1 {
    match parent.children[idx + 1] {
      Leaf(right) =>
        if right.keys.length() > min_keys {
          // Move the first (key, value) from right to the end of cur.
          let bk = right.keys[0]
          let bv = right.values[0]
          ignore(right.keys.remove(0))
          ignore(right.values.remove(0))
          cur.keys.push(bk)
          cur.values.push(bv)
          // Update the separator key in the parent.
          parent.keys[idx] = right.keys[0]
          return
        }
      _ => ()
    }
  }
  // 3. Merge with a sibling. If the parent has only one child, there
  //    is no sibling to merge with — the underflow is tolerated and
  //    will be resolved by the parent's own rebalancing (or root
  //    contraction if the parent is the root).
  if parent.children.length() < 2 {
    return
  }
  if idx > 0 {
    merge_leaf(parent, idx - 1)
  } else {
    merge_leaf(parent, idx)
  }
}

///|
/// Merge the leaf at `left_idx + 1` into the leaf at `left_idx`.
/// Removes the separator key and the right child from the parent.
fn merge_leaf(parent : BPTreeNode, left_idx : Int) -> Unit {
  let left = match parent.children[left_idx] {
    Leaf(l) => l
    _ => return
  }
  let right = match parent.children[left_idx + 1] {
    Leaf(r) => r
    _ => return
  }
  // Move all entries from right into left.
  for i = 0; i < right.keys.length(); i = i + 1 {
    left.keys.push(right.keys[i])
    left.values.push(right.values[i])
  }
  // Maintain the leaf linked list.
  left.next = right.next
  // Remove the separator key and the right child from the parent.
  ignore(parent.keys.remove(left_idx))
  ignore(parent.children.remove(left_idx + 1))
}

///|
/// Rebalance an internal node that has underflowed.
/// Strategy: borrow from left sibling → borrow from right sibling → merge.
fn rebalance_node(parent : BPTreeNode, idx : Int, cur : BPTreeNode) -> Unit {
  let min_keys = BPTREE_MIN_DEGREE - 1
  // 1. Try borrowing from the left sibling.
  if idx > 0 {
    match parent.children[idx - 1] {
      Node(left) =>
        if left.keys.length() > min_keys {
          // Pull the separator key down from the parent to the front of cur.
          cur.keys.insert(0, parent.keys[idx - 1])
          // Move the last child of left to the front of cur.
          cur.children.insert(0, left.children[left.children.length() - 1])
          // Promote the last key of left up to the parent.
          parent.keys[idx - 1] = left.keys[left.keys.length() - 1]
          ignore(left.keys.pop())
          ignore(left.children.pop())
          return
        }
      _ => ()
    }
  }
  // 2. Try borrowing from the right sibling.
  if idx < parent.children.length() - 1 {
    match parent.children[idx + 1] {
      Node(right) =>
        if right.keys.length() > min_keys {
          // Pull the separator key down from the parent to the end of cur.
          cur.keys.push(parent.keys[idx])
          // Move the first child of right to the end of cur.
          cur.children.push(right.children[0])
          // Promote the first key of right up to the parent.
          parent.keys[idx] = right.keys[0]
          ignore(right.keys.remove(0))
          ignore(right.children.remove(0))
          return
        }
      _ => ()
    }
  }
  // 3. Merge with a sibling. Same guard as rebalance_leaf.
  if parent.children.length() < 2 {
    return
  }
  if idx > 0 {
    merge_node(parent, idx - 1)
  } else {
    merge_node(parent, idx)
  }
}

///|
/// Merge the internal node at `left_idx + 1` into the node at `left_idx`.
/// Pulls the separator key down from the parent into the merged node.
fn merge_node(parent : BPTreeNode, left_idx : Int) -> Unit {
  let left = match parent.children[left_idx] {
    Node(n) => n
    _ => return
  }
  let right = match parent.children[left_idx + 1] {
    Node(n) => n
    _ => return
  }
  // Pull the separator key down into the merged node.
  left.keys.push(parent.keys[left_idx])
  // Move all keys and children from right into left.
  for i = 0; i < right.keys.length(); i = i + 1 {
    left.keys.push(right.keys[i])
  }
  for i = 0; i < right.children.length(); i = i + 1 {
    left.children.push(right.children[i])
  }
  // Remove the separator key and the right child from the parent.
  ignore(parent.keys.remove(left_idx))
  ignore(parent.children.remove(left_idx + 1))
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
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

///|
test "bptree: update existing key" {
  let tree = new()
  insert(tree, 10, 100)
  insert(tree, 10, 200) // update — size should not change
  assert_eq(search(tree, 10), Some(200))
  assert_eq(size(tree), 1) // size counts unique keys
}

///|
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

///|
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

///|
test "bptree: range query with no results" {
  let tree = new()
  insert(tree, 10, 100)
  insert(tree, 20, 200)
  let result = range_query(tree, 30, 40)
  assert_eq(result.length(), 0)
}

///|
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

///|
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

///|
test "bptree: duplicate keys" {
  let tree = new()
  insert(tree, 10, 100)
  insert(tree, 10, 200)
  insert(tree, 10, 300)
  assert_eq(search(tree, 10), Some(300))
  let sorted = to_sorted_array(tree)
  assert_eq(sorted.length(), 1) // only one key
}

///|
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

///|
test "bptree: range query full range" {
  let tree = new()
  for i = 0; i < 50; i = i + 1 {
    insert(tree, i, i)
  }
  let result = range_query(tree, 0, 49)
  assert_eq(result.length(), 100) // 50 keys * 2
}

///|
test "bptree: empty tree" {
  let tree = new()
  assert_eq(search(tree, 10), None)
  assert_eq(to_sorted_array(tree).length(), 0)
  assert_eq(range_query(tree, 0, 100).length(), 0)
}

///|
test "bptree: delete from empty tree" {
  let tree = new()
  assert_eq(delete(tree, 42), false)
  assert_eq(size(tree), 0)
}

///|
test "bptree: delete single element" {
  let tree = new()
  insert(tree, 10, 100)
  assert_eq(delete(tree, 10), true)
  assert_eq(search(tree, 10), None)
  assert_eq(size(tree), 0)
}

///|
test "bptree: delete non-existent key" {
  let tree = new()
  insert(tree, 10, 100)
  insert(tree, 20, 200)
  assert_eq(delete(tree, 15), false)
  assert_eq(size(tree), 2)
  assert_eq(search(tree, 10), Some(100))
  assert_eq(search(tree, 20), Some(200))
}

///|
test "bptree: delete and reinsert" {
  let tree = new()
  insert(tree, 10, 100)
  insert(tree, 20, 200)
  insert(tree, 30, 300)
  assert_eq(delete(tree, 20), true)
  assert_eq(search(tree, 20), None)
  assert_eq(size(tree), 2)
  insert(tree, 20, 250)
  assert_eq(search(tree, 20), Some(250))
  assert_eq(size(tree), 3)
}

///|
test "bptree: delete all sequential" {
  let n = 200
  let tree = new()
  for i = 0; i < n; i = i + 1 {
    insert(tree, i, i * 2)
  }
  assert_eq(size(tree), n)
  for i = 0; i < n; i = i + 1 {
    assert_eq(delete(tree, i), true)
    assert_eq(search(tree, i), None)
  }
  assert_eq(size(tree), 0)
  assert_eq(to_sorted_array(tree).length(), 0)
}

///|
test "bptree: delete all reverse" {
  let n = 200
  let tree = new()
  for i = 0; i < n; i = i + 1 {
    insert(tree, i, i * 2)
  }
  for i = n - 1; i >= 0; i = i - 1 {
    assert_eq(delete(tree, i), true)
  }
  assert_eq(size(tree), 0)
  assert_eq(to_sorted_array(tree).length(), 0)
}

///|
test "bptree: delete every other" {
  let n = 100
  let tree = new()
  for i = 0; i < n; i = i + 1 {
    insert(tree, i, i)
  }
  // Delete even keys.
  for i = 0; i < n; i = i + 2 {
    assert_eq(delete(tree, i), true)
  }
  // Odd keys should remain.
  assert_eq(size(tree), 50)
  for i = 0; i < n; i = i + 1 {
    if i % 2 == 0 {
      assert_eq(search(tree, i), None)
    } else {
      assert_eq(search(tree, i), Some(i))
    }
  }
  // Verify sorted order is correct.
  let sorted = to_sorted_array(tree)
  assert_eq(sorted.length(), 50)
  for i = 0; i < 50; i = i + 1 {
    assert_eq(sorted[i], 2 * i + 1)
  }
}

///|
test "bptree: delete triggers merge" {
  // Insert enough elements to create multiple levels, then delete
  // enough to trigger merges.
  let n = 500
  let tree = new()
  for i = 0; i < n; i = i + 1 {
    insert(tree, i, i)
  }
  // Delete 80% of keys to force extensive merges.
  for i = 0; i < n; i = i + 1 {
    if i % 5 != 0 {
      assert_eq(delete(tree, i), true)
    }
  }
  assert_eq(size(tree), 100)
  // Remaining keys (multiples of 5) should be found.
  for i = 0; i < n; i = i + 5 {
    assert_eq(search(tree, i), Some(i))
  }
  // Verify sorted order.
  let sorted = to_sorted_array(tree)
  assert_eq(sorted.length(), 100)
  for i = 0; i < 100; i = i + 1 {
    assert_eq(sorted[i], 5 * i)
  }
}

///|
test "bptree: delete maintains range query" {
  let tree = new()
  for i = 0; i < 100; i = i + 1 {
    insert(tree, i, i * 10)
  }
  // Delete keys 20-29.
  for i = 20; i < 30; i = i + 1 {
    assert_eq(delete(tree, i), true)
  }
  // Range query [10, 40] should skip deleted keys.
  let result = range_query(tree, 10, 40)
  // Keys 10-19 (10) + 30-40 (11) = 21 keys * 2 = 42 entries.
  assert_eq(result.length(), 42)
  // First entry should be (10, 100).
  assert_eq(result[0], 10)
  assert_eq(result[1], 100)
}

///|
test "bptree: delete root key" {
  let tree = new()
  insert(tree, 50, 500)
  insert(tree, 30, 300)
  insert(tree, 70, 700)
  // Delete the first key inserted (which may be in the root leaf).
  assert_eq(delete(tree, 50), true)
  assert_eq(search(tree, 50), None)
  assert_eq(search(tree, 30), Some(300))
  assert_eq(search(tree, 70), Some(700))
  assert_eq(size(tree), 2)
}

///|
test "bptree: stress delete" {
  let n = 1000
  let tree = new()
  for i = 0; i < n; i = i + 1 {
    insert(tree, i, i)
  }
  // Delete in random-looking pattern.
  for i = 0; i < n; i = i + 1 {
    let k = (i * 37 + 13) % n
    if search(tree, k) is Some(_) {
      assert_eq(delete(tree, k), true)
    }
  }
  // All should be deleted.
  assert_eq(size(tree), 0)
  for i = 0; i < n; i = i + 1 {
    assert_eq(search(tree, i), None)
  }
}
