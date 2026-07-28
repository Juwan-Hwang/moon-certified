///|
/// B+ Tree: a variant of B-Tree where all values are stored in leaf nodes.
///
/// Unlike a B-Tree, B+ Tree internal nodes store only keys (for routing), and
/// all data values reside in the leaves. The leaves are linked together in a
/// linked list, enabling efficient range queries and sequential access.
///
/// ## Generics
///
/// The tree is parameterised over key type `K` and value type `V`. A
/// `cmp_fn : (K, K) -> Int` (negative ⇒ `<`, zero ⇒ `=`, positive ⇒ `>`)
/// is stored in the root struct and used for all comparisons, following the
/// same callback-based genericity pattern as `HashTable[K, V]` and
/// `LRUCache[K, V]`.
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
pub struct BPTreeLeaf[K, V] {
  keys : Array[K]
  values : Array[V]
  mut next : BPTreeLeaf[K, V]? // Pointer to the next leaf (for range queries)
}

///|
/// B+ Tree internal node.
pub struct BPTreeNode[K, V] {
  keys : Array[K]
  children : Array[BPTreeChild[K, V]]
}

///|
/// B+ Tree child: either an internal node or a leaf.
pub enum BPTreeChild[K, V] {
  Node(BPTreeNode[K, V])
  Leaf(BPTreeLeaf[K, V])
}

///|
/// B+ Tree root.
pub struct BPTree[K, V] {
  mut root : BPTreeChild[K, V]
  mut size : Int
  cmp_fn : (K, K) -> Int
}

///|
/// Create an empty B+ Tree with the given comparison function.
///
/// `cmp_fn` defines the total ordering on keys. It must return a negative
/// value when `a < b`, zero when `a == b`, and a positive value when `a > b`.
/// For `Int` keys, pass `fn(a, b) { a - b }` or use the `new_int` convenience
/// constructor.
pub fn[K, V] new(cmp_fn : (K, K) -> Int) -> BPTree[K, V] {
  {
    root: Leaf({ keys: [], values: [], next: None }),
    size: 0,
    cmp_fn,
  }
}

///|
/// Convenience constructor for `Int`-keyed trees.
pub fn[V] new_int() -> BPTree[Int, V] {
  new(fn(a, b) { a - b })
}

///|
/// Insert a (key, value) pair into the B+ Tree.
///
/// If the key already exists, its value is updated (size unchanged).
pub fn[K, V] insert(tree : BPTree[K, V], key : K, value : V) -> Unit {
  let (new_root, is_new) = insert_child(tree.root, key, value, tree.cmp_fn)
  // If the root is an internal node that overflowed, split it and create
  // a new root one level higher.
  match new_root {
    Node(node) =>
      if node.keys.length() > 2 * BPTREE_MIN_DEGREE - 1 {
        let (left, right, sep_key) = split_node(node)
        let new_root_node : BPTreeNode[K, V] = {
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
fn[K, V] insert_child(
  child : BPTreeChild[K, V],
  key : K,
  value : V,
  cmp_fn : (K, K) -> Int,
) -> (BPTreeChild[K, V], Bool) {
  match child {
    Leaf(leaf) => {
      let (new_leaf, is_new) = insert_leaf(leaf, key, value, cmp_fn)
      if new_leaf.keys.length() > 2 * BPTREE_MIN_DEGREE - 1 {
        // Split leaf.
        let (left, right, sep_key) = split_leaf(new_leaf)
        let node : BPTreeNode[K, V] = {
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
      while idx < node.keys.length() && cmp_fn(key, node.keys[idx]) >= 0 {
        idx = idx + 1
      }
      let (new_child, is_new) = insert_child(node.children[idx], key, value, cmp_fn)
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
fn[K, V] insert_leaf(
  leaf : BPTreeLeaf[K, V],
  key : K,
  value : V,
  cmp_fn : (K, K) -> Int,
) -> (BPTreeLeaf[K, V], Bool) {
  let mut idx = 0
  while idx < leaf.keys.length() && cmp_fn(leaf.keys[idx], key) < 0 {
    idx = idx + 1
  }
  if idx < leaf.keys.length() && cmp_fn(leaf.keys[idx], key) == 0 {
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
fn[K, V] split_leaf(leaf : BPTreeLeaf[K, V]) -> (BPTreeLeaf[K, V], BPTreeLeaf[K, V], K) {
  let mid = leaf.keys.length() / 2
  let right : BPTreeLeaf[K, V] = { keys: [], values: [], next: leaf.next }
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
fn[K, V] split_node(
  node : BPTreeNode[K, V]
) -> (BPTreeNode[K, V], BPTreeNode[K, V], K) {
  let mid = node.keys.length() / 2
  let sep = node.keys[mid]
  let right : BPTreeNode[K, V] = { keys: [], children: [] }
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
pub fn[K, V] search(tree : BPTree[K, V], key : K) -> V? {
  search_child(tree.root, key, tree.cmp_fn)
}

///|
fn[K, V] search_child(
  child : BPTreeChild[K, V],
  key : K,
  cmp_fn : (K, K) -> Int,
) -> V? {
  match child {
    Leaf(leaf) => {
      for i = 0; i < leaf.keys.length(); i = i + 1 {
        if cmp_fn(leaf.keys[i], key) == 0 {
          return Some(leaf.values[i])
        }
      }
      None
    }
    Node(node) => {
      let mut idx = 0
      while idx < node.keys.length() && cmp_fn(key, node.keys[idx]) >= 0 {
        idx = idx + 1
      }
      search_child(node.children[idx], key, cmp_fn)
    }
  }
}

///|
/// Range query: find all (key, value) pairs with keys in [lo, hi].
///
/// Returns an array of `(key, value)` tuples.
pub fn[K, V] range_query(tree : BPTree[K, V], lo : K, hi : K) -> Array[(K, V)] {
  let result : Array[(K, V)] = []
  // Find the leftmost leaf containing keys >= lo.
  let leaf = find_leaf(tree.root, lo, tree.cmp_fn)
  let mut cur = leaf
  let mut done = false
  while cur is Some(leaf_node) && !done {
    for i = 0; i < leaf_node.keys.length(); i = i + 1 {
      if (tree.cmp_fn)(leaf_node.keys[i], hi) > 0 {
        done = true
        break
      }
      if (tree.cmp_fn)(leaf_node.keys[i], lo) >= 0 {
        result.push((leaf_node.keys[i], leaf_node.values[i]))
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
fn[K, V] find_leaf(
  child : BPTreeChild[K, V],
  key : K,
  cmp_fn : (K, K) -> Int,
) -> BPTreeLeaf[K, V]? {
  match child {
    Leaf(leaf) => Some(leaf)
    Node(node) => {
      let mut idx = 0
      while idx < node.keys.length() && cmp_fn(key, node.keys[idx]) >= 0 {
        idx = idx + 1
      }
      find_leaf(node.children[idx], key, cmp_fn)
    }
  }
}

///|
/// Get the number of entries in the tree.
pub fn[K, V] size(tree : BPTree[K, V]) -> Int {
  tree.size
}

///|
/// Collect all keys in sorted order (for testing).
pub fn[K, V] to_sorted_array(tree : BPTree[K, V]) -> Array[K] {
  let result : Array[K] = []
  collect_keys(tree.root, result)
  result
}

///|
fn[K, V] collect_keys(child : BPTreeChild[K, V], result : Array[K]) -> Unit {
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
pub fn[K, V] delete(tree : BPTree[K, V], key : K) -> Bool {
  let found = delete_child(tree.root, key, tree.cmp_fn)
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
fn[K, V] delete_child(
  child : BPTreeChild[K, V],
  key : K,
  cmp_fn : (K, K) -> Int,
) -> Bool {
  match child {
    Leaf(leaf) => delete_from_leaf(leaf, key, cmp_fn)
    Node(node) => delete_from_node(node, key, cmp_fn)
  }
}

///|
/// Remove a key from a leaf node. Returns whether the key was found.
fn[K, V] delete_from_leaf(
  leaf : BPTreeLeaf[K, V],
  key : K,
  cmp_fn : (K, K) -> Int,
) -> Bool {
  let mut idx = 0
  while idx < leaf.keys.length() && cmp_fn(leaf.keys[idx], key) < 0 {
    idx = idx + 1
  }
  if idx < leaf.keys.length() && cmp_fn(leaf.keys[idx], key) == 0 {
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
fn[K, V] delete_from_node(
  node : BPTreeNode[K, V],
  key : K,
  cmp_fn : (K, K) -> Int,
) -> Bool {
  let mut idx = 0
  while idx < node.keys.length() && cmp_fn(key, node.keys[idx]) >= 0 {
    idx = idx + 1
  }
  let found = delete_child(node.children[idx], key, cmp_fn)
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
fn[K, V] rebalance_leaf(
  parent : BPTreeNode[K, V],
  idx : Int,
  cur : BPTreeLeaf[K, V],
) -> Unit {
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
fn[K, V] merge_leaf(parent : BPTreeNode[K, V], left_idx : Int) -> Unit {
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
fn[K, V] rebalance_node(
  parent : BPTreeNode[K, V],
  idx : Int,
  cur : BPTreeNode[K, V],
) -> Unit {
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
fn[K, V] merge_node(parent : BPTreeNode[K, V], left_idx : Int) -> Unit {
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
  let tree : BPTree[Int, Int] = new(fn(a, b) { a - b })
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
  let tree : BPTree[Int, Int] = new_int()
  insert(tree, 10, 100)
  insert(tree, 10, 200) // update — size should not change
  assert_eq(search(tree, 10), Some(200))
  assert_eq(size(tree), 1) // size counts unique keys
}

///|
test "bptree: sorted order" {
  let tree : BPTree[Int, Int] = new_int()
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
  let tree : BPTree[Int, Int] = new_int()
  for i = 0; i < 100; i = i + 1 {
    insert(tree, i, i * 10)
  }
  // Range [10, 20] should return 11 entries.
  let result = range_query(tree, 10, 20)
  assert_eq(result.length(), 11) // 11 (key, value) pairs
  // First entry should be (10, 100).
  assert_eq(result[0].0, 10)
  assert_eq(result[0].1, 100)
  // Last entry should be (20, 200).
  assert_eq(result[result.length() - 1].0, 20)
  assert_eq(result[result.length() - 1].1, 200)
}

///|
test "bptree: range query with no results" {
  let tree : BPTree[Int, Int] = new_int()
  insert(tree, 10, 100)
  insert(tree, 20, 200)
  let result = range_query(tree, 30, 40)
  assert_eq(result.length(), 0)
}

///|
test "bptree: large insert" {
  let tree : BPTree[Int, Int] = new_int()
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
  let tree : BPTree[Int, Int] = new_int()
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
  let tree : BPTree[Int, Int] = new_int()
  insert(tree, 10, 100)
  insert(tree, 10, 200)
  insert(tree, 10, 300)
  assert_eq(search(tree, 10), Some(300))
  let sorted = to_sorted_array(tree)
  assert_eq(sorted.length(), 1) // only one key
}

///|
test "bptree: negative keys" {
  let tree : BPTree[Int, Int] = new_int()
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
  let tree : BPTree[Int, Int] = new_int()
  for i = 0; i < 50; i = i + 1 {
    insert(tree, i, i)
  }
  let result = range_query(tree, 0, 49)
  assert_eq(result.length(), 50) // 50 (key, value) pairs
}

///|
test "bptree: empty tree" {
  let tree : BPTree[Int, Int] = new_int()
  assert_eq(search(tree, 10), None)
  assert_eq(to_sorted_array(tree).length(), 0)
  assert_eq(range_query(tree, 0, 100).length(), 0)
}

///|
test "bptree: delete from empty tree" {
  let tree : BPTree[Int, Int] = new_int()
  assert_eq(delete(tree, 42), false)
  assert_eq(size(tree), 0)
}

///|
test "bptree: delete single element" {
  let tree : BPTree[Int, Int] = new_int()
  insert(tree, 10, 100)
  assert_eq(delete(tree, 10), true)
  assert_eq(search(tree, 10), None)
  assert_eq(size(tree), 0)
}

///|
test "bptree: delete non-existent key" {
  let tree : BPTree[Int, Int] = new_int()
  insert(tree, 10, 100)
  insert(tree, 20, 200)
  assert_eq(delete(tree, 15), false)
  assert_eq(size(tree), 2)
  assert_eq(search(tree, 10), Some(100))
  assert_eq(search(tree, 20), Some(200))
}

///|
test "bptree: delete and reinsert" {
  let tree : BPTree[Int, Int] = new_int()
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
  let tree : BPTree[Int, Int] = new_int()
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
  let tree : BPTree[Int, Int] = new_int()
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
  let tree : BPTree[Int, Int] = new_int()
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
  let tree : BPTree[Int, Int] = new_int()
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
  let tree : BPTree[Int, Int] = new_int()
  for i = 0; i < 100; i = i + 1 {
    insert(tree, i, i * 10)
  }
  // Delete keys 20-29.
  for i = 20; i < 30; i = i + 1 {
    assert_eq(delete(tree, i), true)
  }
  // Range query [10, 40] should skip deleted keys.
  let result = range_query(tree, 10, 40)
  // Keys 10-19 (10) + 30-40 (11) = 21 keys.
  assert_eq(result.length(), 21)
  // First entry should be (10, 100).
  assert_eq(result[0].0, 10)
  assert_eq(result[0].1, 100)
}

///|
test "bptree: delete root key" {
  let tree : BPTree[Int, Int] = new_int()
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
  let tree : BPTree[Int, Int] = new_int()
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

///|
test "bptree: generic string keys" {
  let tree : BPTree[String, Int] = new(@utils.str_cmp)
  insert(tree, "banana", 1)
  insert(tree, "apple", 2)
  insert(tree, "cherry", 3)
  assert_eq(search(tree, "apple"), Some(2))
  assert_eq(search(tree, "banana"), Some(1))
  assert_eq(search(tree, "cherry"), Some(3))
  assert_eq(search(tree, "date"), None)
  let sorted = to_sorted_array(tree)
  assert_eq(sorted[0], "apple")
  assert_eq(sorted[1], "banana")
  assert_eq(sorted[2], "cherry")
  assert_eq(delete(tree, "banana"), true)
  assert_eq(search(tree, "banana"), None)
  assert_eq(size(tree), 2)
}

///|
test "bptree: generic int64 keys" {
  let tree : BPTree[Int64, String] = new(
    fn(a, b) {
      if a < b { -1 } else if a > b { 1 } else { 0 }
    },
  )
  insert(tree, 100L, "hundred")
  insert(tree, 50L, "fifty")
  insert(tree, 200L, "two hundred")
  assert_eq(search(tree, 50L), Some("fifty"))
  assert_eq(search(tree, 200L), Some("two hundred"))
  let sorted = to_sorted_array(tree)
  assert_eq(sorted[0], 50L)
  assert_eq(sorted[1], 100L)
  assert_eq(sorted[2], 200L)
}
